#!/usr/bin/env bash
# NAND flash using macromorgan's PROVEN matched boot0+u-boot pair, plus a custom
# u-boot env that chains to OUR kernel, plus our uImage/DTB. Everything written
# by the FEL-loaded flasher u-boot (consistent ECC).
#
# Chain: BootROM -> macromorgan boot0 (MLC layout, BootROM-accepted) -> his SPL
#   -> his u-boot (matched pair) -> reads our env @ 0xc00000 -> our bootcmd:
#      nand read uImage+DTB from bootfs -> bootm -> our kernel -> USB gadget.
#
# His u-boot's default bootcmd is distro_bootcmd (won't auto-boot our NAND
# bootfs), so the custom env (env/env.bin) is required. No erase.chip (bad block
# at 0x2000000); erase per-partition.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
MKIMAGE="${MKIMAGE:-mkimage}"
FLASHER="$REPO/artifacts/uboot-nand/flasher-u-boot-sunxi-with-spl.bin"
BOOT0="$REPO/artifacts/macromorgan/spl-400000-4000-500.bin"   # BootROM-accepted SPL
UBOOT="$REPO/artifacts/macromorgan/u-boot-dtb.bin"            # his matched u-boot
ENVB="$REPO/artifacts/env/env.bin"                            # our bootcmd -> our kernel
UIMG="$REPO/artifacts/installer/uImage"
DTB="$REPO/artifacts/installer/sun5i-r8-chip-pocketchip-ng.dtb"

ADDR_BOOT0=0x42000000
ADDR_UBOOT=0x43000000
ADDR_ENV=0x44000000
ADDR_UIMG=0x45000000
ADDR_DTB=0x46000000
ADDR_SCRIPT=0x4d000000

PAGE=16384; OOB=1280; RAWPAGE=$((PAGE + OOB))
b0pages=$(printf '0x%x' $(( ($(wc -c < "$BOOT0") + RAWPAGE - 1) / RAWPAGE )))
hexsz() { printf '0x%x' "$(wc -c < "$1")"; }
ubsz=$(hexsz "$UBOOT"); envsz=$(hexsz "$ENVB"); uimgsz=$(hexsz "$UIMG"); dtbsz=$(hexsz "$DTB")

for f in "$FEL" "$FLASHER" "$BOOT0" "$UBOOT" "$ENVB" "$UIMG" "$DTB"; do [ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }; done
command -v "$MKIMAGE" >/dev/null || { echo "need mkimage" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/m.cmd" <<EOF
echo "=== macromorgan boot0+u-boot + our env/kernel ==="
nand erase 0x0 0x400000
nand erase 0x400000 0x400000
nand erase 0x800000 0x400000
nand erase 0xc00000 0x400000
nand erase 0x1000000 0x2000000
echo "boot0 raw x2..."
nand write.raw $ADDR_BOOT0 0x0 $b0pages
nand write.raw $ADDR_BOOT0 0x400000 $b0pages
echo "his u-boot @ 0x800000..."
nand write $ADDR_UBOOT 0x800000 $ubsz
echo "env @ 0xc00000..."
nand write $ADDR_ENV 0xc00000 $envsz
echo "uImage @ 0x1000000..."
nand write $ADDR_UIMG 0x1000000 $uimgsz
echo "dtb @ 0x2e00000..."
nand write $ADDR_DTB 0x2e00000 $dtbsz
echo "=== done; reset in 2s ==="
sleep 2
reset
EOF
"$MKIMAGE" -A arm -O linux -T script -C none -a 0 -e 0 -n pchip-macro -d "$WORK/m.cmd" "$WORK/m.scr" >/dev/null

echo "FEL probe:"; "$FEL" ver
echo "  boot0(macro) -> 0x0/0x400000 ($b0pages pages raw)"
echo "  u-boot(macro)-> 0x800000 ($ubsz)"
echo "  env          -> 0xc00000 ($envsz)"
echo "  uImage       -> 0x1000000 ($uimgsz)"
echo "  dtb          -> 0x2e00000 ($dtbsz)"
"$FEL" \
    uboot "$FLASHER" \
    write-with-progress "$ADDR_BOOT0" "$BOOT0" \
    write-with-progress "$ADDR_UBOOT" "$UBOOT" \
    write-with-progress "$ADDR_ENV"   "$ENVB" \
    write-with-progress "$ADDR_UIMG"  "$UIMG" \
    write-with-progress "$ADDR_DTB"   "$DTB" \
    write               "$ADDR_SCRIPT" "$WORK/m.scr"
echo ""
echo "Reset pending. Watch for PocketCHIP_NG on USB."
echo "(MLC boot is flaky; if it FELs/hangs, power-cycle to FEL and re-run.)"
