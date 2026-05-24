#!/usr/bin/env bash
# Write ONLY the boot0 (SPL) to NAND via U-Boot's TRUE raw write over FEL.
#
# Why this exists: Linux `nandwrite -n -o` routes the OOB through MTD's OOB
# layout, which misplaces the BootROM's ECC bytes, so a boot0 written that way
# is not BootROM-loadable (board drops to FEL). U-Boot's `nand write.raw`
# writes main+OOB byte-for-byte, exactly how the sun5i BootROM reads boot0
# (this is macromorgan's method). u-boot proper + kernel uImage are written
# separately from Linux (mtd-utils) and verified; this only fixes boot0.
#
# No `nand erase.chip` (it aborts on the factory bad block at 0x2000000);
# we erase just the two boot0 eraseblocks (0x0, 0x400000), which are good.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
MKIMAGE="${MKIMAGE:-mkimage}"
FLASHER="$REPO/artifacts/uboot-nand/flasher-u-boot-sunxi-with-spl.bin"
BOOT0="${BOOT0:-$REPO/artifacts/uboot-nand/sunxi-spl-with-ecc.bin}"

ADDR_BOOT0=0x43000000
ADDR_SCRIPT=0x4d000000

PAGE=16384; OOB=1280; RAWPAGE=$((PAGE + OOB))
pages=$(printf '0x%x' $(( ($(wc -c < "$BOOT0") + RAWPAGE - 1) / RAWPAGE )))

for f in "$FEL" "$FLASHER" "$BOOT0"; do [ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }; done
command -v "$MKIMAGE" >/dev/null || { echo "need mkimage" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/b0.cmd" <<EOF
echo "=== boot0-only raw write ==="
nand erase 0x0 0x400000
nand erase 0x400000 0x400000
nand write.raw $ADDR_BOOT0 0x0 $pages
nand write.raw $ADDR_BOOT0 0x400000 $pages
echo "=== boot0 written; reset in 2s ==="
sleep 2
reset
EOF
"$MKIMAGE" -A arm -O linux -T script -C none -a 0 -e 0 -n pchip-boot0 -d "$WORK/b0.cmd" "$WORK/b0.scr" >/dev/null

echo "FEL probe:"; "$FEL" ver
echo "boot0 -> $ADDR_BOOT0 ($(wc -c < "$BOOT0") bytes, $pages pages raw, written x2 @ 0x0/0x400000)"
"$FEL" \
    uboot "$FLASHER" \
    write-with-progress "$ADDR_BOOT0" "$BOOT0" \
    write               "$ADDR_SCRIPT" "$WORK/b0.scr"
echo ""
echo "Flasher writing boot0 via raw, then resetting. After reset the BootROM"
echo "loads boot0 -> our SPL -> u-boot (already on NAND) -> kernel."
echo "Watch for PocketCHIP_NG on USB; if FEL reappears, boot0 still rejected."
