#!/usr/bin/env bash
# Flash the PROVEN patched LEGACY NTC CHIP u-boot (production-mlc-pc + SPL
# geometry-hardcode + slc-mode patches) + our kernel, via FEL. This is the
# bootloader that reliably loads boot0 from the Toshiba MLC NAND (mainline
# u-boot's SPL mis-detects it). Mirrors m4xx3d0ut/pocketchip-debian-builder's
# slc-mode flash recipe, but boots OUR zImage (embedded initramfs) instead of
# their Debian/UBI rootfs (we run from RAM, no UBI needed for Stage 1).
#
# Chain: BootROM -> legacy boot0 (256pg, geometry hardcoded) -> legacy SPL
#   (reliably reads NAND) -> legacy u-boot @0x800000 (.img, slc-mode) -> bootcmd
#   `nand read.slc-mode` kernel@0x1000000 + dtb@0x2000000 -> bootz -> our kernel.
#
# Writes: boot0 RAW x2 (0x0,0x400000); u-boot/kernel/dtb via `nand write.slc-mode`
# (the legacy flasher has the slc-mode commands). Region erase (skip-bad) avoids
# nand erase.chip aborting on the factory bad block at 0x2000000.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
MKIMAGE="${MKIMAGE:-mkimage}"
FLASHER="$REPO/artifacts/uboot-legacy/legacy-flasher-with-spl.bin"
BOOT0="$REPO/artifacts/uboot-legacy/legacy-boot0-256.bin"
UBOOT="$REPO/artifacts/uboot-legacy/legacy-resident-u-boot.img"   # .img = what the SPL loads
KERNEL="$REPO/artifacts/kernel/zImage"                            # embedded initramfs
DTB="$REPO/artifacts/installer/sun5i-r8-chip-pocketchip-ng.dtb"

ADDR_BOOT0=0x42000000
ADDR_UBOOT=0x43000000
ADDR_KERNEL=0x44000000
ADDR_DTB=0x46000000
ADDR_SCRIPT=0x4d000000      # matches legacy flasher bootcmd "source 0x4d000000"

PAGE=16384; OOB=1280; RAWPAGE=$((PAGE + OOB))
b0pages=$(printf '0x%x' $(( ($(wc -c < "$BOOT0") + RAWPAGE - 1) / RAWPAGE )))   # 0x100
hexsz() { printf '0x%x' "$(wc -c < "$1")"; }
ubsz=$(hexsz "$UBOOT"); ksz=$(hexsz "$KERNEL"); dsz=$(hexsz "$DTB")

for f in "$FEL" "$FLASHER" "$BOOT0" "$UBOOT" "$KERNEL" "$DTB"; do [ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }; done
command -v "$MKIMAGE" >/dev/null || { echo "need mkimage" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/l.cmd" <<EOF
echo "=== legacy NTC u-boot + our kernel (slc-mode) ==="
nand erase 0x0 0x2800000
echo "boot0 raw x2 (0x0/0x400000)..."
nand write.raw.noverify $ADDR_BOOT0 0x0 $b0pages
nand write.raw.noverify $ADDR_BOOT0 0x400000 $b0pages
echo "u-boot slc @ 0x800000..."
nand write.slc-mode $ADDR_UBOOT 0x800000 $ubsz
echo "kernel slc @ 0x1000000..."
nand write.slc-mode $ADDR_KERNEL 0x1000000 $ksz
echo "dtb slc @ 0x2000000..."
nand write.slc-mode $ADDR_DTB 0x2000000 $dsz
echo "=== done; reset in 2s ==="
sleep 2
reset
EOF
"$MKIMAGE" -A arm -O linux -T script -C none -a 0 -e 0 -n pchip-legacy -d "$WORK/l.cmd" "$WORK/l.scr" >/dev/null

echo "FEL probe:"; "$FEL" ver
echo "  boot0  -> 0x0/0x400000 ($b0pages pages raw)"
echo "  u-boot -> 0x800000 slc ($ubsz)"
echo "  kernel -> 0x1000000 slc ($ksz)"
echo "  dtb    -> 0x2000000 slc ($dsz)"
"$FEL" \
    uboot "$FLASHER" \
    write-with-progress "$ADDR_BOOT0"  "$BOOT0" \
    write-with-progress "$ADDR_UBOOT"  "$UBOOT" \
    write-with-progress "$ADDR_KERNEL" "$KERNEL" \
    write-with-progress "$ADDR_DTB"    "$DTB" \
    write               "$ADDR_SCRIPT" "$WORK/l.scr"
echo ""
echo "Reset pending. Watch for PocketCHIP_NG on USB (board should stay powered)."
