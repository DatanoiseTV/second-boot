#!/usr/bin/env bash
# Build a tiny busybox-based initramfs for the FEL smoke test.
# The whole thing fits in well under 10 MiB and gets baked into the
# kernel via CONFIG_INITRAMFS_SOURCE so we only have to FEL-stage two
# files in DDR (zImage + DTB) before kicking off U-Boot.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.env"
. "$HERE/lib.sh"

STAGE="$ARTIFACTS_DIR/initramfs/root"
OUT="$ARTIFACTS_DIR/initramfs/initramfs.cpio"
KREL_FILE="$ARTIFACTS_DIR/kernel/kernelrelease"
MOD_STAGE="$ARTIFACTS_DIR/kernel/modules"
FW_SRC="$SOURCES_DIR/linux-firmware"

ensure_dir "$(dirname "$OUT")"

log "building rootfs skeleton in $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE"/{bin,sbin,usr/bin,usr/sbin,etc,proc,sys,dev,tmp,run,root,lib,lib/firmware/rtlwifi,lib/firmware/rtl_bt}

# Busybox: borrow Debian armhf static binary instead of cross-building.
# /usr/bin/busybox in busybox-static_*armhf*.deb is fully static armhf.
BBPKG=$(apt-get download --print-uris busybox-static:armhf 2>/dev/null | awk -F"'" '/.deb/ {print $2}' | head -1 || true)
if [ -z "$BBPKG" ]; then
    log "fetching busybox-static armhf from Debian mirror"
    TMPDEB="$(mktemp -d)"
    ( cd "$TMPDEB" && apt-get download busybox-static:armhf >/dev/null )
    DEB=$(ls "$TMPDEB"/*.deb | head -1)
else
    TMPDEB="$(mktemp -d)"
    ( cd "$TMPDEB" && wget -q "$BBPKG" )
    DEB=$(ls "$TMPDEB"/*.deb | head -1)
fi

[ -f "$DEB" ] || die "could not obtain busybox-static armhf"
log "extracting $DEB"
( cd "$TMPDEB" && dpkg-deb -x "$DEB" extracted )
BB_BIN=$(find "$TMPDEB/extracted" -name busybox -type f -executable | head -1)
[ -n "$BB_BIN" ] || die "busybox binary not found in deb"
cp -v "$BB_BIN" "$STAGE/bin/busybox"
chmod +x "$STAGE/bin/busybox"
rm -rf "$TMPDEB"

# Symlink common applets via busybox itself at runtime; the /init
# script below runs `busybox --install -s /bin` after mount.
ln -sf busybox "$STAGE/bin/sh"

# RTL8723BS firmware
if [ -d "$FW_SRC" ]; then
    log "staging RTL8723BS firmware"
    cp -v "$FW_SRC/rtlwifi/rtl8723bs_nic.bin"     "$STAGE/lib/firmware/rtlwifi/" 2>/dev/null || warn "missing rtl8723bs_nic.bin"
    cp -v "$FW_SRC/rtlwifi/rtl8723bs_config.bin"  "$STAGE/lib/firmware/rtlwifi/" 2>/dev/null || warn "missing rtl8723bs_config.bin"
    cp -v "$FW_SRC/rtl_bt/rtl8723bs_fw.bin"       "$STAGE/lib/firmware/rtl_bt/"  2>/dev/null || true
    cp -v "$FW_SRC/rtl_bt/rtl8723bs_config.bin"   "$STAGE/lib/firmware/rtl_bt/"  2>/dev/null || true
fi

# Kernel modules: copy just what we actually need for WiFi + USB
# gadgets. Everything else can be left out.
KREL="$(cat "$KREL_FILE" 2>/dev/null || true)"
if [ -n "$KREL" ] && [ -d "$MOD_STAGE/lib/modules/$KREL" ]; then
    log "copying selected modules ($KREL)"
    SRC_MOD="$MOD_STAGE/lib/modules/$KREL"
    DST_MOD="$STAGE/lib/modules/$KREL"
    mkdir -p "$DST_MOD"
    cp -v "$SRC_MOD/modules."{order,builtin,builtin.modinfo,dep,alias,symbols} "$DST_MOD/" 2>/dev/null || true
    # Wifi driver lives in staging
    find "$SRC_MOD" \( -name 'r8723bs.ko*' -o -name 'rtl8723bs.ko*' \) -exec sh -c '
        for f; do
            d="$2/$(dirname "${f#$1/}")"
            mkdir -p "$d"
            cp -v "$f" "$d/"
        done' sh "$SRC_MOD" "$DST_MOD" {} +
fi

# Minimal /init: mount pseudo-fs, install busybox applets, bring up
# USB gadgets (g_serial + g_ether), then drop to a shell on the
# console (which is ttyGS0 + tty0 thanks to bootargs).
cat > "$STAGE/init" <<'INIT'
#!/bin/sh
# PocketCHIP-ng smoke-test initramfs init.

PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

/bin/busybox --install -s /bin

mount -t proc  proc  /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev || mdev -s
mount -t tmpfs tmpfs /run
mount -t tmpfs tmpfs /tmp

# Greet on every console.
banner() {
    local msg="$1"
    for tty in /dev/tty0 /dev/ttyGS0 /dev/console; do
        [ -e "$tty" ] && echo "$msg" > "$tty" 2>/dev/null
    done
}

banner ""
banner "==============================================="
banner "  pocketchip-ng smoke test initramfs"
banner "  kernel $(uname -r)"
banner "==============================================="
banner ""

# USB gadgets via configfs: serial console + RNDIS ethernet
mount -t configfs none /sys/kernel/config 2>/dev/null
if [ -d /sys/kernel/config/usb_gadget ]; then
    cd /sys/kernel/config/usb_gadget
    mkdir -p pocketchip
    cd pocketchip
    echo 0x1d6b > idVendor       # Linux Foundation
    echo 0x0104 > idProduct      # Multifunction Composite Gadget
    echo 0x0100 > bcdDevice
    echo 0x0200 > bcdUSB
    mkdir -p strings/0x409
    echo "0123456789" > strings/0x409/serialnumber
    echo "DatanoiseTV"  > strings/0x409/manufacturer
    echo "PocketCHIP-NG" > strings/0x409/product
    mkdir -p configs/c.1/strings/0x409
    echo "Conf 1: ACM+ECM" > configs/c.1/strings/0x409/configuration
    echo 250 > configs/c.1/MaxPower
    mkdir -p functions/acm.GS0
    mkdir -p functions/ecm.usb0
    ln -s functions/acm.GS0 configs/c.1/
    ln -s functions/ecm.usb0 configs/c.1/
    UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
    if [ -n "$UDC" ]; then
        echo "$UDC" > UDC
        banner "USB gadget bound to $UDC"
    else
        banner "no UDC available"
    fi
fi

# Bring up loopback + USB ethernet
ip link set lo up
ip link set usb0 up 2>/dev/null
ip addr add 10.43.43.1/24 dev usb0 2>/dev/null
banner "usb0 = 10.43.43.1/24 (host should DHCP-less assign 10.43.43.2)"

# Try to load WiFi
modprobe r8723bs 2>/dev/null && banner "r8723bs loaded" || banner "no r8723bs module"

banner ""
banner "dropping to shell on /dev/console (ttyGS0/tty0)"
banner ""

exec setsid sh -c 'exec sh </dev/console >/dev/console 2>&1'
INIT
chmod +x "$STAGE/init"

# Minimal /etc files
echo "root:x:0:0:root:/root:/bin/sh" > "$STAGE/etc/passwd"
echo "root:x:0:" > "$STAGE/etc/group"
cat > "$STAGE/etc/inittab" <<'EOF'
::sysinit:/etc/init.d/rcS
::respawn:-/bin/sh
EOF
echo "pocketchip-ng" > "$STAGE/etc/hostname"

log "packing cpio"
( cd "$STAGE" && find . -print0 | cpio --null -ov --format=newc 2>/dev/null ) > "$OUT"
gzip -fk "$OUT"
log "initramfs: $(du -sh "$OUT" | cut -f1) (gzipped: $(du -sh "$OUT.gz" | cut -f1))"
log "size: $(stat -c%s "$OUT") bytes"
