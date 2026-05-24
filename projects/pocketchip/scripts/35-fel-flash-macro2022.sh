#!/usr/bin/env bash
# Flash macromorgan's PROVEN u-boot v2022.01 (whose SPL has the NAND-DMA fix so
# it can actually read NAND) + our kernel FIT, via the 2025.01 FEL flasher.
#
# Why this should finally work: every prior "boot0 accepted -> hung" was the SPL
# being unable to read u-boot from NAND (mainline removed the sunxi NAND-SPL DMA
# code in 2021). This v2022.01 build carries macromorgan's revert patch, so the
# SPL reads NAND. boot0 is the 256-page full-eraseblock MLC image. u-boot is
# written to 0x800000 AND 0xc00000 (SYS_NAND_U_BOOT_OFFS + _REDUND). Our kernel
# FIT (zImage+dtb, embedded initramfs) goes at 0x1000000 (native), and u-boot's
# bootcmd `nand read 0x42000000 0x1000000 0x800000; bootm` loads it.
#
# All data-area writes (u-boot, FIT) use normal nand write (data-area ECC, which
# the v2022.01 SPL/u-boot read with -- version-independent for the same chip).
# boot0 is raw. No slc needed for Stage 1 (kernel runs from RAM).

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
MKIMAGE="${MKIMAGE:-mkimage}"
# v2022.01 flasher, poweron-VIN DISABLED (else it powers the board off mid-flash)
# and same Toshiba scramble/ECC as the resident reads with.
FLASHER="$REPO/artifacts/uboot-macro-build/flasher-v2022-novin.bin"
BOOT0="$REPO/artifacts/uboot-macro-build/boot0-256.bin"        # v2022.01 SPL, 256pg MLC boot0
UBOOT="$REPO/artifacts/uboot-macro-build/u-boot-dtb-novin.bin" # v2022.01 u-boot (native-read, no poweron-VIN)
FIT="$REPO/artifacts/fit/pchip.itb"                            # our kernel+dtb

ADDR_BOOT0=0x42000000
ADDR_UBOOT=0x43000000
ADDR_FIT=0x44000000
ADDR_SCRIPT=0x4d000000

PAGE=16384; OOB=1280; RAWPAGE=$((PAGE + OOB))
b0pages=$(printf '0x%x' $(( ($(wc -c < "$BOOT0") + RAWPAGE - 1) / RAWPAGE )))
hexsz() { printf '0x%x' "$(wc -c < "$1")"; }
ubsz=$(hexsz "$UBOOT"); fitsz=$(hexsz "$FIT")

for f in "$FEL" "$FLASHER" "$BOOT0" "$UBOOT" "$FIT"; do [ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }; done
command -v "$MKIMAGE" >/dev/null || { echo "need mkimage" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/m.cmd" <<EOF
echo "=== macromorgan v2022.01 boot0+u-boot + our FIT ==="
nand erase 0x0 0x400000
nand erase 0x400000 0x400000
nand erase 0x800000 0x400000
nand erase 0xc00000 0x400000
nand erase 0x1000000 0x1000000
echo "boot0 raw x2..."
nand write.raw $ADDR_BOOT0 0x0 $b0pages
nand write.raw $ADDR_BOOT0 0x400000 $b0pages
echo "u-boot @ 0x800000 + 0xc00000 (redund)..."
nand write $ADDR_UBOOT 0x800000 $ubsz
nand write $ADDR_UBOOT 0xc00000 $ubsz
echo "FIT @ 0x1000000..."
nand write $ADDR_FIT 0x1000000 $fitsz
echo "=== done; reset in 2s ==="
sleep 2
reset
EOF
"$MKIMAGE" -A arm -O linux -T script -C none -a 0 -e 0 -n pchip-m2022 -d "$WORK/m.cmd" "$WORK/m.scr" >/dev/null

echo "FEL probe:"; "$FEL" ver
echo "  boot0 -> 0x0/0x400000 ($b0pages pages raw)"
echo "  u-boot-> 0x800000 + 0xc00000 ($ubsz)"
echo "  FIT   -> 0x1000000 ($fitsz)"
"$FEL" \
    uboot "$FLASHER" \
    write-with-progress "$ADDR_BOOT0" "$BOOT0" \
    write-with-progress "$ADDR_UBOOT" "$UBOOT" \
    write-with-progress "$ADDR_FIT"   "$FIT" \
    write               "$ADDR_SCRIPT" "$WORK/m.scr"
echo ""
echo "Reset pending. Watch for PocketCHIP_NG on USB."
