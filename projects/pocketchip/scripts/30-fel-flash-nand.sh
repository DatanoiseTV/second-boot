#!/usr/bin/env bash
# Flash the PocketCHIP NAND entirely from U-Boot, driven over FEL.
#
# No Linux kernel and no USB gadget are involved: we FEL-load a
# "flasher" U-Boot (CHIP_defconfig + NAND commands), stage the three
# NAND payloads plus a U-Boot boot script in DDR, and let U-Boot's
# bootcmd 'source' the script. The script erases NAND and writes SPL,
# U-Boot and the UBI image, then resets into a normal NAND boot.
#
# This sidesteps the macOS FEL-vs-cold-boot OTG state problem: after
# the reset, the board does a clean cold boot from NAND and the kernel
# brings up its USB gadget on a pristine controller.
#
# Run on the Mac with the PocketCHIP in FEL mode.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
MKIMAGE="${MKIMAGE:-mkimage}"

FLASH_UBOOT="$REPO/artifacts/uboot-nand/u-boot-sunxi-with-spl.bin"   # the flasher
SPL_NAND="$REPO/artifacts/uboot-nand/sunxi-spl-nand.bin"             # ECC-wrapped SPL to write
UBOOT_NAND="$REPO/artifacts/uboot-nand/u-boot.bin"                   # u-boot proper to write
UBI_IMG="$REPO/artifacts/ubi/pocketchip.ubi"                         # kernel + rootfs

# DDR staging addresses (all in DRAM, which the flasher's SPL inits).
ADDR_SPL=0x43000000
ADDR_UBOOT=0x44000000
ADDR_UBI=0x46000000
ADDR_SCRIPT=0x7f000000   # matches CONFIG_BOOTCOMMAND "source 0x7f000000"

# NAND target offsets.
NAND_SPL_0=0x000000
NAND_SPL_1=0x100000
NAND_SPL_2=0x200000
NAND_SPL_3=0x300000
NAND_UBOOT=0x400000
NAND_UBI=0x800000

for f in "$FEL" "$FLASH_UBOOT" "$SPL_NAND" "$UBOOT_NAND" "$UBI_IMG"; do
    [ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }
done
command -v "$MKIMAGE" >/dev/null || { echo "need mkimage (brew install u-boot-tools)" >&2; exit 1; }

splsz=$(printf '0x%x' "$(wc -c < "$SPL_NAND")")
ubsz=$(printf '0x%x' "$(wc -c < "$UBOOT_NAND")")
ubisz=$(printf '0x%x' "$(wc -c < "$UBI_IMG")")

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Generate the U-Boot flash script. nand write rounds size up to page,
# which is fine. We write the SPL to all four BootROM scan offsets.
cat > "$WORK/flash.cmd" <<EOF
echo "=== pocketchip-ng NAND flash ==="
mtd list
nand erase.chip
echo "writing SPL (x4 copies)..."
nand write $ADDR_SPL   $NAND_SPL_0 $splsz
nand write $ADDR_SPL   $NAND_SPL_1 $splsz
nand write $ADDR_SPL   $NAND_SPL_2 $splsz
nand write $ADDR_SPL   $NAND_SPL_3 $splsz
echo "writing u-boot proper..."
nand write $ADDR_UBOOT $NAND_UBOOT $ubsz
echo "writing UBI (kernel + rootfs)..."
nand write $ADDR_UBI   $NAND_UBI   $ubisz
echo "=== flash done, resetting into NAND boot in 3s ==="
sleep 3
reset
EOF

"$MKIMAGE" -A arm -O linux -T script -C none -a 0 -e 0 \
    -n "pocketchip-ng-nand-flash" -d "$WORK/flash.cmd" "$WORK/flash.scr"

echo "FEL probe:"
"$FEL" ver
echo ""
echo "Staging payloads + flash script in DDR, then starting the flasher U-Boot."
echo "  SPL    -> $ADDR_SPL   ($splsz)"
echo "  U-Boot -> $ADDR_UBOOT ($ubsz)"
echo "  UBI    -> $ADDR_UBI   ($ubisz)"
echo "  script -> $ADDR_SCRIPT"
echo ""

"$FEL" \
    uboot "$FLASH_UBOOT" \
    write-with-progress "$ADDR_SPL"    "$SPL_NAND" \
    write-with-progress "$ADDR_UBOOT"  "$UBOOT_NAND" \
    write-with-progress "$ADDR_UBI"    "$UBI_IMG" \
    write              "$ADDR_SCRIPT" "$WORK/flash.scr"

cat <<MSG

The flasher U-Boot is now running its bootcmd ('source $ADDR_SCRIPT').
It will erase NAND, write SPL/U-Boot/UBI, and reset (~30-60s for the
UBI write). Do NOT unplug until well after that.

After the reset the board cold-boots from NAND. Watch for the kernel's
USB gadget to enumerate on the Mac (CDC-ECM network interface +
/dev/cu.usbmodem*). If anything went wrong, FEL still works -- power
cycle with the FEL pad shorted and we recover.
MSG
