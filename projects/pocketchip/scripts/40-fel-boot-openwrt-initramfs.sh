#!/usr/bin/env bash
# FEL-boot OpenWrt's own initramfs image into RAM (non-destructive; NAND is
# untouched). Full OpenWrt in RAM -- with ubiformat, dropbear, mtd/ubi tools,
# and our usb0=10.43.43.1 gadget overlay -- the correct place to install the
# UBI rootfs onto slc-mode NAND (the KERNEL writes it, consistent ECC).
#
# Uses a dedicated "felboot" u-boot built with CONFIG_ENV_IS_NOWHERE: it does
# NOT read the NAND env partition (which a stray `saveenv` polluted), so its
# COMPILED bootcmd always runs -- set bootargs with console=ttyS0 (CHIP UART =
# serial0/uart1) and `bootz` the FEL-staged kernel. No `nand read`, so nothing
# clobbers the staged image. bootdelay 0 -> autoboots immediately.
#
# After boot: give the host USB-ECM iface 10.43.43.2/24, then ssh root@10.43.43.1
# (the baked dropbear key matches this Mac), scp the factory UBI, and
# `ubiformat /dev/mtd5 -f ...`; also flash_erase /dev/mtd3 to clear the polluted
# resident env so the NAND autoboot uses correct (compiled) bootargs.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
UBOOT="$REPO/artifacts/uboot-legacy/felboot-u-boot-sunxi-with-spl.bin"  # env-nowhere, console=ttyS0 bootcmd
KERNEL="$REPO/artifacts/openwrt-nand/owrt-initramfs-kernel.bin"          # zImage + embedded OpenWrt initramfs
DTB="$REPO/artifacts/openwrt-nand/owrt.dtb"

ADDR_KERNEL=0x42000000      # must match felboot bootcmd
ADDR_DTB=0x49000000         # high enough to clear the ~10 MB kernel at 0x42000000

for f in "$FEL" "$UBOOT" "$KERNEL" "$DTB"; do [ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }; done

echo "FEL probe:"; "$FEL" ver
echo "  kernel -> $ADDR_KERNEL ($(wc -c < "$KERNEL") bytes)"
echo "  dtb    -> $ADDR_DTB ($(wc -c < "$DTB") bytes)"
"$FEL" \
    uboot "$UBOOT" \
    write-with-progress "$ADDR_KERNEL" "$KERNEL" \
    write-with-progress "$ADDR_DTB"    "$DTB"
echo ""
echo "felboot u-boot autoboots the staged OpenWrt initramfs (console=ttyS0)."
echo "Watch UART for OpenWrt boot + login; then on the host:"
echo "  sudo ifconfig <usb-ecm-iface> 10.43.43.2/24 up && ssh root@10.43.43.1"
