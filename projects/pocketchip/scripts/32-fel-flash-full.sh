#!/usr/bin/env bash
# Full NAND flash via U-Boot over FEL, using macromorgan's BootROM-accepted
# boot0 (the only SPL the sun5i BootROM loads from this MLC NAND -- it has the
# correct full-eraseblock MLC lower-page layout) + OUR u-boot + OUR kernel.
#
# Everything is written by the FEL-loaded flasher u-boot, so all regions get a
# consistent NAND ECC: macromorgan's SPL reads our u-boot, and our u-boot reads
# our uImage/DTB, all with the same sunxi data-area ECC. (Linux nandwrite gave a
# mismatched ECC/OOB layout, which is why the SPL->u-boot handoff hung.)
#
# Layout: 0x0/0x400000 boot0 (macromorgan, raw 256pg) | 0x800000 our u-boot |
#         0x1000000 bootfs: our uImage | 0x2e00000 our DTB | 0x3000000 rootfs(later)
# No erase.chip (aborts on the 0x2000000 bad block); erase per-partition.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
MKIMAGE="${MKIMAGE:-mkimage}"
FLASHER="$REPO/artifacts/uboot-nand/flasher-u-boot-sunxi-with-spl.bin"
BOOT0="${BOOT0:-$REPO/artifacts/macromorgan/spl-400000-4000-500.bin}"   # BootROM-accepted SPL
UBOOT="${UBOOT:-$REPO/artifacts/uboot-nand/u-boot-dtb.bin}"             # our u-boot (+dtb, auto-boot bootcmd)
UIMG="${UIMG:-$REPO/artifacts/installer/uImage}"
DTB="${DTB:-$REPO/artifacts/installer/sun5i-r8-chip-pocketchip-ng.dtb}"

ADDR_BOOT0=0x43000000
ADDR_UBOOT=0x44000000
ADDR_UIMG=0x45000000
ADDR_DTB=0x46000000
ADDR_SCRIPT=0x4d000000

PAGE=16384; OOB=1280; RAWPAGE=$((PAGE + OOB))
b0pages=$(printf '0x%x' $(( ($(wc -c < "$BOOT0") + RAWPAGE - 1) / RAWPAGE )))
hexsz() { printf '0x%x' "$(wc -c < "$1")"; }
ubsz=$(hexsz "$UBOOT"); uimgsz=$(hexsz "$UIMG"); dtbsz=$(hexsz "$DTB")

for f in "$FEL" "$FLASHER" "$BOOT0" "$UBOOT" "$UIMG" "$DTB"; do [ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }; done
command -v "$MKIMAGE" >/dev/null || { echo "need mkimage" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/f.cmd" <<EOF
echo "=== full NAND flash (macromorgan boot0 + our u-boot/kernel) ==="
nand erase 0x0 0x400000
nand erase 0x400000 0x400000
nand erase 0x800000 0x400000
nand erase 0x1000000 0x2000000
echo "boot0 (raw x2)..."
nand write.raw $ADDR_BOOT0 0x0 $b0pages
nand write.raw $ADDR_BOOT0 0x400000 $b0pages
echo "u-boot @ 0x800000..."
nand write $ADDR_UBOOT 0x800000 $ubsz
echo "uImage @ 0x1000000..."
nand write $ADDR_UIMG 0x1000000 $uimgsz
echo "dtb @ 0x2e00000..."
nand write $ADDR_DTB 0x2e00000 $dtbsz
echo "=== done; reset in 2s ==="
sleep 2
reset
EOF
"$MKIMAGE" -A arm -O linux -T script -C none -a 0 -e 0 -n pchip-full -d "$WORK/f.cmd" "$WORK/f.scr" >/dev/null

echo "FEL probe:"; "$FEL" ver
echo "  boot0  -> 0x0/0x400000 ($(wc -c < "$BOOT0") bytes, $b0pages pages raw)"
echo "  u-boot -> 0x800000 ($ubsz)"
echo "  uImage -> 0x1000000 ($uimgsz)"
echo "  dtb    -> 0x2e00000 ($dtbsz)"
"$FEL" \
    uboot "$FLASHER" \
    write-with-progress "$ADDR_BOOT0" "$BOOT0" \
    write-with-progress "$ADDR_UBOOT" "$UBOOT" \
    write-with-progress "$ADDR_UIMG"  "$UIMG" \
    write-with-progress "$ADDR_DTB"   "$DTB" \
    write               "$ADDR_SCRIPT" "$WORK/f.scr"
echo ""
echo "Flasher writing all regions via u-boot, then resetting."
echo "Watch for PocketCHIP_NG on USB (full chain: boot0->SPL->our u-boot->our kernel)."
