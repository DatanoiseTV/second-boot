#!/usr/bin/env bash
# Assemble a flashable microSD image:
#
#   sector 0 .. 15        reserved (1 MiB hole, but SPL sits at sector 16)
#   sector 16 ..          u-boot-sunxi-with-spl.bin (dd'd raw)
#   partition 1           FAT32, label POCKETBOOT (kernel, dtb, extlinux.conf)
#   partition 2           ext4,  label POCKETROOT (Debian rootfs)
#
# Output: $ARTIFACTS_DIR/pocketchip-<suite>.img(.xz)
#
# Needs root for losetup + mount.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.env"
. "$HERE/lib.sh"

[ "$(id -u)" -eq 0 ] || die "must be run as root"

UBOOT_BIN="$ARTIFACTS_DIR/uboot/u-boot-sunxi-with-spl.bin"
KERNEL_DIR="$ARTIFACTS_DIR/kernel"
MOD_STAGE="$KERNEL_DIR/modules"
ROOTFS_TAR="$ARTIFACTS_DIR/rootfs/pocketchip-trixie-armhf.tar"

DTB_NAME="${POCKETCHIP_DTB:-sun5i-r8-chip-pocketchip-ng.dtb}"
DTB="$KERNEL_DIR/dtbs/$DTB_NAME"
if [ ! -f "$DTB" ]; then
    # fall back to upstream chip dtb if our overlay didn't build
    DTB="$KERNEL_DIR/dtbs/sun5i-r8-chip.dtb"
    warn "using upstream DTB $DTB (PocketCHIP-specific DT not present)"
fi

for f in "$UBOOT_BIN" "$KERNEL_DIR/zImage" "$DTB" "$ROOTFS_TAR"; do
    [ -f "$f" ] || die "missing artifact: $f"
done

IMG="$ARTIFACTS_DIR/pocketchip-trixie.img"
SIZE_MIB="${IMG_SIZE_MIB:-1900}"   # ~1.9 GiB raw; fits a 2 GiB+ card

log "creating sparse image $IMG (${SIZE_MIB} MiB)"
rm -f "$IMG" "$IMG.xz"
truncate -s "${SIZE_MIB}M" "$IMG"

log "partitioning"
parted -s "$IMG" mklabel msdos
parted -s "$IMG" mkpart primary fat32 1MiB   65MiB
parted -s "$IMG" mkpart primary ext4  65MiB  100%
parted -s "$IMG" set 1 boot on

log "dd u-boot SPL+proper at sector 16 (8 KiB)"
dd if="$UBOOT_BIN" of="$IMG" bs=1024 seek=8 conv=notrunc,fsync status=none

LOOP="$(losetup --show -fP "$IMG")"
trap 'set +e; sync; umount -R "$MNT" 2>/dev/null; losetup -d "$LOOP" 2>/dev/null' EXIT

log "formatting partitions on $LOOP"
mkfs.vfat -F32 -n POCKETBOOT "${LOOP}p1"
mkfs.ext4  -L POCKETROOT -F  "${LOOP}p2"

MNT="$(mktemp -d)"
mount "${LOOP}p2" "$MNT"
mkdir -p "$MNT/boot"
mount "${LOOP}p1" "$MNT/boot"

log "extracting rootfs"
tar -xf "$ROOTFS_TAR" -C "$MNT"

log "installing kernel + dtb + extlinux"
cp -v "$KERNEL_DIR/zImage" "$MNT/boot/zImage"
cp -v "$DTB"               "$MNT/boot/$(basename "$DTB")"

mkdir -p "$MNT/boot/extlinux"
cat > "$MNT/boot/extlinux/extlinux.conf" <<EOF
default pocketchip
timeout 2
label pocketchip
    kernel /zImage
    fdt    /$(basename "$DTB")
    append root=LABEL=POCKETROOT rootwait rw console=ttyS0,115200 console=tty0 loglevel=4 panic=10
EOF

log "installing kernel modules"
KREL="$(cat "$KERNEL_DIR/kernelrelease" 2>/dev/null || true)"
if [ -n "$KREL" ] && [ -d "$MOD_STAGE/lib/modules/$KREL" ]; then
    mkdir -p "$MNT/lib/modules"
    cp -a "$MOD_STAGE/lib/modules/$KREL" "$MNT/lib/modules/"
fi

log "installing RTL8723BS firmware blobs"
FW_SRC="$SOURCES_DIR/linux-firmware"
mkdir -p "$MNT/lib/firmware/rtlwifi" "$MNT/lib/firmware/rtl_bt"
cp -v "$FW_SRC/rtlwifi/rtl8723bs_nic.bin"     "$MNT/lib/firmware/rtlwifi/" 2>/dev/null || warn "rtl8723bs_nic.bin missing"
cp -v "$FW_SRC/rtlwifi/rtl8723bs_config.bin"  "$MNT/lib/firmware/rtlwifi/" 2>/dev/null || warn "rtl8723bs_config.bin missing"
cp -v "$FW_SRC/rtl_bt/rtl8723bs_fw.bin"       "$MNT/lib/firmware/rtl_bt/"  2>/dev/null || warn "rtl8723bs_fw.bin missing"
cp -v "$FW_SRC/rtl_bt/rtl8723bs_config.bin"   "$MNT/lib/firmware/rtl_bt/"  2>/dev/null || true

sync
umount "$MNT/boot"
umount "$MNT"
rmdir "$MNT"
losetup -d "$LOOP"
trap - EXIT

log "compressing image (xz -T0 -3)"
xz -T0 -3 -v "$IMG"
ls -lh "${IMG}.xz"
log "done. flash with: xzcat ${IMG##*/}.xz | sudo dd of=/dev/sdX bs=4M conv=fsync"
