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
# sunxi-nand-image-builder may live in the build-host clone ($SOURCES_DIR)
# or the repo submodule (tools/). Prefer whichever is built.
if [ -n "${NIB:-}" ]; then
    :
elif [ -x "$SOURCES_DIR/sunxi-tools/sunxi-nand-image-builder" ]; then
    NIB="$SOURCES_DIR/sunxi-tools/sunxi-nand-image-builder"
else
    NIB="$(cd "$HERE/.." && pwd)/tools/sunxi-tools/sunxi-nand-image-builder"
fi

PAGE_SIZE="${PAGE_SIZE:-16384}"
OOB_SIZE="${OOB_SIZE:-1280}"
ERASE_BLOCK="${ERASE_BLOCK:-4194304}"
# boot0/SPL ECC is FIXED by the BootROM and is independent of the data-area
# ECC (40/1024). The BROM reads the SPL with 64-bit/1024-byte ECC, accessing
# only the first 4096 "usable" bytes per page, with data scrambling (-s).
# These match U-Boot's NAND_SUNXI_SPL_ECC_* defaults and the worked example
# for the matching 16K/1280/4M MLC chip in sunxi-nand-image-builder's help.
USABLE_PAGE="${USABLE_PAGE:-4096}"
ECC_STRENGTH="${ECC_STRENGTH:-64}"
ECC_STEP="${ECC_STEP:-1024}"

[ -f "$SPL_BIN" ] || die "missing $SPL_BIN (run 20-build-uboot-nand.sh)"
[ -x "$NIB"     ] || die "sunxi-nand-image-builder not built; run 'make misc' in tools/sunxi-tools"

log "wrapping $SPL_BIN as a boot0 image (BootROM ECC layout)"
log "  page=$PAGE_SIZE oob=$OOB_SIZE eraseblock=$ERASE_BLOCK usable=$USABLE_PAGE ecc=$ECC_STRENGTH/$ECC_STEP scramble=on"

"$NIB" \
    -c "$ECC_STRENGTH/$ECC_STEP" \
    -p "$PAGE_SIZE" \
    -o "$OOB_SIZE" \
    -u "$USABLE_PAGE" \
    -e "$ERASE_BLOCK" \
    -s \
    -b \
    "$SPL_BIN" \
    "$SPL_OUT"

log "boot0 image: $(du -h "$SPL_OUT" | cut -f1) at $SPL_OUT"
log ""
log "Flashed by scripts/30-fel-flash-nand.sh via U-Boot:"
log "  nand write.raw.noverify <addr> 0x0       <pages>"
log "  nand write.raw.noverify <addr> 0x400000  <pages>"
log ""
log "(two copies, one erase-block apart -- the BootROM tries 0x0 then 0x400000)"
