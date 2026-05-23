#!/usr/bin/env bash
# Wrap our SPL with the ECC layout the Allwinner BootROM expects when
# loading from NAND. The BootROM tries up to four copies of boot0 at
# 0x000000, 0x100000, 0x200000, 0x300000 -- we generate one ECC-encoded
# image and the flash procedure writes it to all four locations for
# bad-block resilience.
#
# NAND parameters are CHIP-specific. The values below are the
# community-known-good baseline for the Hynix MLC NAND that shipped on
# most C.H.I.P. revisions. Read /proc/mtd / dmesg on the running board
# (via FEL-booted Linux) to confirm before flashing:
#
#   nand: device found, Manufacturer ID: 0x...
#   nand: Hynix H27UCG8T2BTR
#   nand: 8192 MiB, MLC, erase size: 4096 KiB,
#         page size: 16384, OOB size: 1280
#
# If your chip differs, override via environment:
#   PAGE_SIZE=... OOB_SIZE=... ERASE_BLOCK=... ECC_STRENGTH=... ECC_STEP=...

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.env"
. "$HERE/lib.sh"

SPL_BIN="${SPL_BIN:-$ARTIFACTS_DIR/uboot-nand/sunxi-spl.bin}"
SPL_OUT="${SPL_OUT:-$ARTIFACTS_DIR/uboot-nand/sunxi-spl-nand.bin}"
NIB="${NIB:-$(cd "$HERE/.." && pwd)/tools/sunxi-tools/sunxi-nand-image-builder}"

PAGE_SIZE="${PAGE_SIZE:-16384}"
OOB_SIZE="${OOB_SIZE:-1280}"
USABLE_PAGE="${USABLE_PAGE:-$PAGE_SIZE}"
ERASE_BLOCK="${ERASE_BLOCK:-4194304}"
ECC_STRENGTH="${ECC_STRENGTH:-40}"
ECC_STEP="${ECC_STEP:-1024}"

[ -f "$SPL_BIN" ] || die "missing $SPL_BIN (run 20-build-uboot-nand.sh)"
[ -x "$NIB"     ] || die "sunxi-nand-image-builder not built; run 'make misc' in tools/sunxi-tools"

log "wrapping $SPL_BIN with NAND ECC layout"
log "  page=$PAGE_SIZE oob=$OOB_SIZE eraseblock=$ERASE_BLOCK ecc=$ECC_STRENGTH/$ECC_STEP"

"$NIB" \
    -c "$ECC_STRENGTH/$ECC_STEP" \
    -p "$PAGE_SIZE" \
    -o "$OOB_SIZE" \
    -u "$USABLE_PAGE" \
    -e "$ERASE_BLOCK" \
    -b \
    "$SPL_BIN" \
    "$SPL_OUT"

log "boot0 image: $(du -h "$SPL_OUT" | cut -f1) at $SPL_OUT"
log ""
log "Flash to NAND with (on the booted PocketCHIP):"
log "  for o in 0x000000 0x400000 0x800000 0xc00000; do"
log "      nandwrite -o -O -m \$o /dev/mtd0 $SPL_OUT"
log "  done"
log ""
log "(the four copies are for bad-block resilience -- BootROM tries them in order)"
