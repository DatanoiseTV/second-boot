#!/usr/bin/env bash
# Boot the freshly-built kernel into RAM via FEL.
# Run on the Mac (or any host with a working sunxi-fel) with the
# PocketCHIP plugged in over USB OTG and in FEL mode.
#
# This is non-destructive: nothing touches NAND. Power-cycling the
# PocketCHIP returns it to whatever state it was in before.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
UBOOT="${UBOOT_BIN:-$REPO/artifacts/uboot/u-boot-sunxi-with-spl.bin}"
ZIMAGE="${ZIMAGE_BIN:-$REPO/artifacts/kernel/zImage}"
DTB="${DTB_BIN:-$REPO/artifacts/kernel/dtbs/sun5i-r8-chip-pocketchip-ng.dtb}"

# Sun5i SDRAM lives at 0x40000000..0x60000000 (512 MiB).
# U-Boot's TEXT_BASE is 0x4A000000; we keep everything well below it.
ZIMAGE_ADDR=0x42000000
# 0x49000000 (not 0x43000000): big kernels (the OpenWrt-embedded
# installer is ~16.4 MB) loaded at 0x42000000 run past 0x43000000, so a
# DTB there collides with the kernel image. Must match u-boot's bootcmd.
DTB_ADDR=0x49000000

for f in "$FEL" "$UBOOT" "$ZIMAGE" "$DTB"; do
    [ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }
done

echo "FEL probe:"
"$FEL" ver

echo ""
echo "Staging files in DDR and starting U-Boot..."
echo "  zImage -> $ZIMAGE_ADDR ($(wc -c < "$ZIMAGE") bytes)"
echo "  DTB    -> $DTB_ADDR ($(wc -c < "$DTB") bytes)"
echo ""

"$FEL" \
    uboot "$UBOOT" \
    write-with-progress "$ZIMAGE_ADDR" "$ZIMAGE" \
    write-with-progress "$DTB_ADDR" "$DTB"

echo ""
echo "U-Boot will execute as soon as this command returns."
echo "Watch for USB enumeration on the host:"
echo "  ls /dev/cu.usbmodem*"
echo "Then attach a terminal:"
echo "  screen /dev/cu.usbmodem<TAB> 115200"
