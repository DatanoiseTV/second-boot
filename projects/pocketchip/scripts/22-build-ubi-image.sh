#!/usr/bin/env bash
# Build a UBI image containing:
#   volume "boot"    -- kernel zImage + DTB + extlinux.conf  (~32 MiB)
#   volume "rootfs"  -- the OpenWrt squashfs root            (~28 MiB)
#
# Produces a .ubi file that is dd'd onto the NAND's UBI MTD partition.
#
# NAND geometry must match the runtime hardware (page/oob/erase block).
# Defaults match the most common CHIP NAND (Hynix MLC); override via env
# if your chip is different.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.env"
. "$HERE/lib.sh"

UBI_OUT_DIR="$ARTIFACTS_DIR/ubi"
ensure_dir "$UBI_OUT_DIR"

KERNEL_DIR="$ARTIFACTS_DIR/kernel"
ZIMAGE="${ZIMAGE:-$KERNEL_DIR/zImage}"
DTB="${DTB:-$KERNEL_DIR/dtbs/sun5i-r8-chip-pocketchip-ng.dtb}"

# OpenWrt squashfs rootfs (built by scripts/10-build-openwrt.sh).
# The raw squashfs lives in build_dir, not bin/ -- OpenWrt only ships
# sysupgrade-wrapped images in bin/ for the sunxi target.
ROOTFS_SQUASHFS="${ROOTFS_SQUASHFS:-$SOURCES_DIR/openwrt/build_dir/target-arm_cortex-a8+vfpv3_musl_eabi/linux-sunxi_cortexa8/root.squashfs}"

# Geometry for the 4 GB C.H.I.P. NAND (confirmed from a flashing session:
# 16K page, 1280 OOB, 4M erase block). This MLC NAND does not support
# sub-page writes, so the UBI min-I/O unit is the full page.
PAGE_SIZE="${PAGE_SIZE:-16384}"
ERASE_BLOCK="${ERASE_BLOCK:-4194304}"
MIN_IO="${MIN_IO:-$PAGE_SIZE}"
# UBI reserves 2 min-I/O units per erase block (EC + VID headers), so the
# logical erase block (LEB) is PEB - 2*min_io. Must be a multiple of
# min_io, which it is: (4M - 2*16K) / 16K = 254.
LEB=$((ERASE_BLOCK - 2 * MIN_IO))

for f in "$ZIMAGE" "$DTB" "$ROOTFS_SQUASHFS"; do
    [ -f "$f" ] || die "missing artifact: $f"
done

STAGE="$UBI_OUT_DIR/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/boot"

cp -v "$ZIMAGE" "$STAGE/boot/zImage"
cp -v "$DTB"    "$STAGE/boot/$(basename "$DTB")"
cat > "$STAGE/boot/extlinux.conf" <<EOF
default pocketchip
timeout 2
label pocketchip
    kernel /zImage
    fdt    /$(basename "$DTB")
    append ubi.mtd=UBI root=ubi0:rootfs rootfstype=ubifs rw console=tty0 console=ttyGS0,115200 loglevel=4 panic=10
EOF

log "building UBIFS image for boot volume (min_io=$MIN_IO LEB=$LEB)"
mkfs.ubifs \
    -m "$MIN_IO" \
    -e "$LEB" \
    -c 8 \
    -r "$STAGE/boot" \
    -o "$UBI_OUT_DIR/boot.ubifs"

log "generating UBI config"
cat > "$UBI_OUT_DIR/ubi.cfg" <<EOF
[boot]
mode=ubi
image=$UBI_OUT_DIR/boot.ubifs
vol_id=0
vol_size=32MiB
vol_type=dynamic
vol_name=boot
vol_flags=autoresize

[rootfs]
mode=ubi
image=$ROOTFS_SQUASHFS
vol_id=1
vol_size=64MiB
vol_type=dynamic
vol_name=rootfs

[rootfs_data]
mode=ubi
vol_id=2
vol_size=512MiB
vol_type=dynamic
vol_name=rootfs_data
vol_flags=autoresize
EOF

log "running ubinize"
# -m min-io, -p physical erase block. No -s (sub-page) because this MLC
# NAND has no usable sub-pages; min-io is the full page.
ubinize \
    -o "$UBI_OUT_DIR/pocketchip.ubi" \
    -m "$MIN_IO" \
    -p "$ERASE_BLOCK" \
    "$UBI_OUT_DIR/ubi.cfg"

log "UBI image: $(du -h "$UBI_OUT_DIR/pocketchip.ubi" | cut -f1) at $UBI_OUT_DIR/pocketchip.ubi"
