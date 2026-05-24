#!/usr/bin/env bash
# Restore NTC's FACTORY boot0 + u-boot (the proven, reliable, matched pair that
# shipped on the device) and redirect them to OUR kernel via a custom env.
#
# Rationale: our own 2025.01 SPL boots inconsistently (MLC) and its SPL->u-boot
# handoff hangs. NTC's factory SPL reliably reads MLC and is matched to NTC's
# u-boot. NTC's u-boot has `nand read`+`bootm` (verified), so a custom env makes
# it boot our kernel from a raw bootfs partition -- no UBI (which mainline can't
# write). NTC ENV_SIZE=0x400000 confirmed by CRC over the factory env dump.
#
# Chain: BootROM -> NTC boot0 (mtd0, raw restore) -> NTC SPL -> NTC u-boot (mtd2,
#   raw restore) -> reads our env (mtd3) -> bootcmd: nand read our uImage+DTB
#   from bootfs -> bootm -> our kernel -> USB gadget.
#
# mtd0/mtd2 are restored RAW (write.raw) from the OOB-inclusive factory dumps, so
# the exact factory bytes+ECC land back -> NTC's SPL/u-boot read them perfectly.
# env/uImage/dtb are written by the flasher u-boot (normal ECC); NTC u-boot reads
# them with the same sunxi data-area ECC.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
MKIMAGE="${MKIMAGE:-mkimage}"
FLASHER="$REPO/artifacts/uboot-nand/flasher-u-boot-sunxi-with-spl.bin"
NTC_BOOT0="$REPO/artifacts/nand-backup/mtd0-SPL.nanddump"      # factory boot0 (raw +OOB, 256pg)
NTC_UBOOT="$REPO/artifacts/nand-backup/mtd2-U-Boot.nanddump"   # factory u-boot (raw +OOB)
ENVB="$REPO/artifacts/env/env.bin"                            # our bootcmd -> our kernel (0x400000)
UIMG="$REPO/artifacts/installer/uImage"
DTB="$REPO/artifacts/installer/sun5i-r8-chip-pocketchip-ng.dtb"

ADDR_BOOT0=0x42000000
ADDR_UBOOT=0x43000000
ADDR_ENV=0x44000000
ADDR_UIMG=0x45000000
ADDR_DTB=0x46000000
ADDR_SCRIPT=0x4d000000

PAGE=16384; OOB=1280; RAWPAGE=$((PAGE + OOB))
b0pages=$(printf '0x%x' $(( ($(wc -c < "$NTC_BOOT0") + RAWPAGE - 1) / RAWPAGE )))   # 256
ubpages=$(printf '0x%x' $(( ($(wc -c < "$NTC_UBOOT") + RAWPAGE - 1) / RAWPAGE )))   # 256
hexsz() { printf '0x%x' "$(wc -c < "$1")"; }
envsz=$(hexsz "$ENVB"); uimgsz=$(hexsz "$UIMG"); dtbsz=$(hexsz "$DTB")

for f in "$FEL" "$FLASHER" "$NTC_BOOT0" "$NTC_UBOOT" "$ENVB" "$UIMG" "$DTB"; do [ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }; done
command -v "$MKIMAGE" >/dev/null || { echo "need mkimage" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/n.cmd" <<EOF
echo "=== NTC factory boot0+u-boot restore + our env/kernel ==="
nand erase 0x0 0x400000
nand erase 0x400000 0x400000
nand erase 0x800000 0x400000
nand erase 0xc00000 0x400000
nand erase 0x1000000 0x2000000
echo "NTC boot0 raw -> mtd0/mtd1..."
nand write.raw $ADDR_BOOT0 0x0 $b0pages
nand write.raw $ADDR_BOOT0 0x400000 $b0pages
echo "NTC u-boot raw -> mtd2..."
nand write.raw $ADDR_UBOOT 0x800000 $ubpages
echo "our env -> mtd3..."
nand write $ADDR_ENV 0xc00000 $envsz
echo "our uImage -> bootfs..."
nand write $ADDR_UIMG 0x1000000 $uimgsz
echo "our dtb..."
nand write $ADDR_DTB 0x2e00000 $dtbsz
echo "=== done; reset in 2s ==="
sleep 2
reset
EOF
"$MKIMAGE" -A arm -O linux -T script -C none -a 0 -e 0 -n pchip-ntc -d "$WORK/n.cmd" "$WORK/n.scr" >/dev/null

echo "FEL probe:"; "$FEL" ver
echo "  NTC boot0 -> 0x0/0x400000 ($b0pages pages raw)"
echo "  NTC u-boot-> 0x800000 ($ubpages pages raw)"
echo "  env       -> 0xc00000 ($envsz)"
echo "  uImage    -> 0x1000000 ($uimgsz)"
echo "  dtb       -> 0x2e00000 ($dtbsz)"
"$FEL" \
    uboot "$FLASHER" \
    write-with-progress "$ADDR_BOOT0" "$NTC_BOOT0" \
    write-with-progress "$ADDR_UBOOT" "$NTC_UBOOT" \
    write-with-progress "$ADDR_ENV"   "$ENVB" \
    write-with-progress "$ADDR_UIMG"  "$UIMG" \
    write-with-progress "$ADDR_DTB"   "$DTB" \
    write               "$ADDR_SCRIPT" "$WORK/n.scr"
echo ""
echo "Reset pending. Watch for PocketCHIP_NG on USB."
