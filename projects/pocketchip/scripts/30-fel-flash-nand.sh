#!/usr/bin/env bash
# Flash the PocketCHIP NAND from U-Boot over FEL -- no kernel, no UBI.
#
# Layout written to NAND (raw, no filesystem):
#   0x000000/0x100000/0x200000/0x300000  SPL (ECC, 4 copies for BootROM)
#   0x400000                             resident u-boot (proper)
#   0x800000                             OpenWrt uImage (kernel + initramfs)
#   0x1800000                            DTB
#
# The resident u-boot's bootcmd reads the uImage + DTB from those NAND
# offsets and bootm's them. The rootfs is the uImage's embedded
# initramfs, so there is no rootfs partition to mount and no
# geometry-sensitive UBIFS.
#
# Flow: FEL-load the flasher u-boot, stage all payloads + a flash script
# in DDR, the flasher's bootcmd 'source's the script which erases NAND,
# writes everything, and resets into a cold NAND boot.
#
# Recovery: if the board doesn't cold-boot, FEL still works (BootROM is
# immutable). Power-cycle with the FEL pad shorted and re-run.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
MKIMAGE="${MKIMAGE:-mkimage}"

FLASHER="$REPO/artifacts/uboot-nand/flasher-u-boot-sunxi-with-spl.bin"
SPL_NAND="$REPO/artifacts/uboot-nand/sunxi-spl-nand.bin"   # ECC-wrapped resident SPL
UBOOT_NAND="$REPO/artifacts/uboot-nand/u-boot.bin"         # resident u-boot proper
KERNEL_UIMG="${KERNEL_UIMG:-$REPO/artifacts/openwrt/initramfs-kernel.bin}"
DTB="${DTB:-$REPO/artifacts/openwrt/sun5i-r8-chip-pocketchip-ng.dtb}"

# DDR staging (all in DRAM the flasher SPL inits; spaced to avoid overlap)
ADDR_SPL=0x43000000
ADDR_UBOOT=0x44000000
ADDR_UIMG=0x46000000
ADDR_DTB=0x48000000
ADDR_SCRIPT=0x7f000000   # matches flasher CONFIG_BOOTCOMMAND "source 0x7f000000"

# NAND target offsets
N_SPL0=0x0; N_SPL1=0x100000; N_SPL2=0x200000; N_SPL3=0x300000
N_UBOOT=0x400000; N_UIMG=0x800000; N_DTB=0x1800000

for f in "$FEL" "$FLASHER" "$SPL_NAND" "$UBOOT_NAND" "$KERNEL_UIMG" "$DTB"; do
    [ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }
done
command -v "$MKIMAGE" >/dev/null || { echo "need mkimage (brew install u-boot-tools)" >&2; exit 1; }

hexsz() { printf '0x%x' "$(wc -c < "$1")"; }
splsz=$(hexsz "$SPL_NAND"); ubsz=$(hexsz "$UBOOT_NAND")
uimgsz=$(hexsz "$KERNEL_UIMG"); dtbsz=$(hexsz "$DTB")

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/flash.cmd" <<EOF
echo "=== pocketchip-ng NAND flash ==="
nand erase.chip
echo "SPL x4..."
nand write $ADDR_SPL $N_SPL0 $splsz
nand write $ADDR_SPL $N_SPL1 $splsz
nand write $ADDR_SPL $N_SPL2 $splsz
nand write $ADDR_SPL $N_SPL3 $splsz
echo "u-boot..."
nand write $ADDR_UBOOT $N_UBOOT $ubsz
echo "uImage..."
nand write $ADDR_UIMG $N_UIMG $uimgsz
echo "dtb..."
nand write $ADDR_DTB $N_DTB $dtbsz
echo "=== done; cold-booting from NAND in 3s ==="
sleep 3
reset
EOF

"$MKIMAGE" -A arm -O linux -T script -C none -a 0 -e 0 \
    -n pocketchip-ng-nand-flash -d "$WORK/flash.cmd" "$WORK/flash.scr" >/dev/null

echo "FEL probe:"; "$FEL" ver
echo ""
echo "Staging payloads + flash script, starting the flasher U-Boot:"
echo "  SPL    -> $ADDR_SPL   ($splsz, written x4)"
echo "  u-boot -> $ADDR_UBOOT ($ubsz)"
echo "  uImage -> $ADDR_UIMG  ($uimgsz)"
echo "  DTB    -> $ADDR_DTB   ($dtbsz)"
echo ""

"$FEL" \
    uboot "$FLASHER" \
    write-with-progress "$ADDR_SPL"   "$SPL_NAND" \
    write-with-progress "$ADDR_UBOOT" "$UBOOT_NAND" \
    write-with-progress "$ADDR_UIMG"  "$KERNEL_UIMG" \
    write-with-progress "$ADDR_DTB"   "$DTB" \
    write               "$ADDR_SCRIPT" "$WORK/flash.scr"

cat <<MSG

Flasher U-Boot is running its bootcmd (source $ADDR_SCRIPT): erase NAND,
write SPL/u-boot/uImage/DTB, reset. The NAND writes take ~30-60s. DO NOT
unplug until well after that.

After reset the board cold-boots from NAND. Watch the Mac for the kernel
USB gadget (CDC-ACM /dev/cu.usbmodem* + CDC-ECM network interface).
If it doesn't appear, FEL still recovers: power-cycle with FEL pad to GND.
MSG
