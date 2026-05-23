#!/usr/bin/env bash
# Build OpenWrt for the PocketCHIP.
#
# Steps:
#   1. Update OpenWrt feeds.
#   2. Drop our PocketCHIP DTS into the kernel-files overlay.
#   3. Append our Device entry to target/linux/sunxi/image/cortexa8.mk
#      (idempotent: greps for the marker line before re-appending).
#   4. Write a .config selecting the cortexa8 target + our device, the
#      kernel-pubkey overlay, and a few sanity packages.
#   5. Sync our files/ overlay into the OpenWrt tree.
#   6. Build with NPROC threads.
#
# Run on the remote build host:
#   ssh syso@... 'cd ~/pocketchip-build && bash scripts/10-build-openwrt.sh'

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
. "$HERE/versions.env"
. "$HERE/lib.sh"

OW_SRC="$SOURCES_DIR/openwrt"
[ -d "$OW_SRC" ] || die "openwrt source missing; run: git clone --depth 1 -b v24.10.0 https://git.openwrt.org/openwrt/openwrt.git $OW_SRC"

# --- 1. feeds --------------------------------------------------------------
log "updating + installing OpenWrt feeds"
( cd "$OW_SRC" && ./scripts/feeds update -a >/dev/null && ./scripts/feeds install -a >/dev/null )

# --- 2. DTS into kernel files-* --------------------------------------------
# files-<kver>/ is the OpenWrt mechanism for shipping out-of-tree DT
# alongside the target. The kver matches target/linux/sunxi/config-<kver>.
KVER=$(ls "$OW_SRC/target/linux/sunxi/" | grep -E '^config-[0-9]' | head -1 | sed 's/config-//')
[ -n "$KVER" ] || die "could not infer KVER from $OW_SRC/target/linux/sunxi/config-*"
FILES_DIR="$OW_SRC/target/linux/sunxi/files-$KVER/arch/arm/boot/dts/allwinner"
log "installing PocketCHIP DTS into files-$KVER ($FILES_DIR)"
mkdir -p "$FILES_DIR"
cp -v "$REPO/openwrt/target/sun5i-r8-chip-pocketchip-ng.dts" "$FILES_DIR/"

# --- 3. Device entry in cortexa8.mk ---------------------------------------
CORTEXA8_MK="$OW_SRC/target/linux/sunxi/image/cortexa8.mk"
MARKER="# === pocketchip-ng device entry ==="
if ! grep -q "$MARKER" "$CORTEXA8_MK"; then
    log "appending PocketCHIP device entry to cortexa8.mk"
    {
        echo ""
        echo "$MARKER"
        cat "$REPO/openwrt/target/cortexa8-pocketchip.mk"
    } >> "$CORTEXA8_MK"
else
    log "device entry already present in cortexa8.mk"
fi

# --- 4. .config ------------------------------------------------------------
log "writing OpenWrt .config (cortexa8 + nextthing_chip-pocketchip-ng)"
cat > "$OW_SRC/.config" <<'EOF'
CONFIG_TARGET_sunxi=y
CONFIG_TARGET_sunxi_cortexa8=y
CONFIG_TARGET_sunxi_cortexa8_DEVICE_nextthing_chip-pocketchip-ng=y
CONFIG_TARGET_ROOTFS_INITRAMFS=y
CONFIG_TARGET_INITRAMFS_COMPRESSION_XZ=y
CONFIG_PACKAGE_kmod-usb-gadget=y
CONFIG_PACKAGE_kmod-usb-lib-composite=y
CONFIG_PACKAGE_kmod-usb-gadget-serial=y
CONFIG_PACKAGE_kmod-usb-gadget-eth=y
CONFIG_PACKAGE_kmod-rtl8723bs=y
CONFIG_PACKAGE_kmod-backlight-pwm=y
CONFIG_PACKAGE_kmod-bluetooth=y
CONFIG_PACKAGE_wireless-regdb=y
CONFIG_PACKAGE_wpad-basic-mbedtls=y
CONFIG_PACKAGE_iw=y
CONFIG_PACKAGE_dropbear=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_usbutils=y

# Bake our files/ overlay into the rootfs.
CONFIG_TARGET_PREINIT_TIMEOUT=2
EOF
( cd "$OW_SRC" && make defconfig >/dev/null )

# --- 5. files/ overlay -----------------------------------------------------
log "syncing files/ overlay"
rm -rf "$OW_SRC/files"
mkdir -p "$OW_SRC/files"
cp -a "$REPO/openwrt/files/." "$OW_SRC/files/"

# uci-defaults scripts must be executable.
find "$OW_SRC/files/etc/uci-defaults" -type f -exec chmod 0755 {} +
find "$OW_SRC/files/etc/init.d"        -type f -exec chmod 0755 {} +

# Permissions on authorized_keys: must be 0600, owned by root (built
# image owns root automatically when running as build user).
chmod 0600 "$OW_SRC/files/etc/dropbear/authorized_keys"

# --- 6. build --------------------------------------------------------------
log "starting OpenWrt build (this takes a while)"
cd "$OW_SRC"
make -j"$NPROC" V=s 2>&1 | tail -200
RC=${PIPESTATUS[0]}

if [ "$RC" -ne 0 ]; then
    die "OpenWrt build failed (exit $RC) -- inspect the full log at ~/.cache/openwrt-build.log"
fi

log "build complete; output:"
ls -lh "$OW_SRC/bin/targets/sunxi/cortexa8/" 2>/dev/null || true
