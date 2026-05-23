#!/usr/bin/env bash
# Build the two NAND-related U-Boots for the PocketCHIP:
#
#   flasher  - FEL-loaded; its bootcmd 'source's a flash script we stage
#              in DDR, which erases NAND and writes everything. Output:
#              artifacts/uboot-nand/flasher-u-boot-sunxi-with-spl.bin
#
#   resident - lives in NAND; reads the kernel uImage + DTB out of NAND
#              and boots them on every cold boot. Outputs the SPL and
#              u-boot.bin that get flashed:
#              artifacts/uboot-nand/sunxi-spl.bin, u-boot.bin
#
# Both start from CHIP_defconfig and differ only in their fragment
# (mainly bootcmd). See configs/uboot/pocketchip-nand*.fragment.config.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.env"
. "$HERE/lib.sh"

UBOOT_SRC="$SOURCES_DIR/u-boot"
UBOOT_OUT="$ARTIFACTS_DIR/uboot-nand"
FRAG_FLASHER="$HERE/../configs/uboot/pocketchip-nand.fragment.config"
FRAG_RESIDENT="$HERE/../configs/uboot/pocketchip-nand-resident.fragment.config"

[ -d "$UBOOT_SRC" ] || die "u-boot source missing; run 01-fetch-sources.sh first"
[ -f "$FRAG_FLASHER"  ] || die "missing $FRAG_FLASHER"
[ -f "$FRAG_RESIDENT" ] || die "missing $FRAG_RESIDENT"

ensure_dir "$UBOOT_OUT"

build_uboot() {
    local frag="$1" label="$2"
    log "[$label] CHIP_defconfig + $(basename "$frag")"
    make -C "$UBOOT_SRC" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" distclean >/dev/null 2>&1
    make -C "$UBOOT_SRC" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" CHIP_defconfig >/dev/null
    cat "$frag" >> "$UBOOT_SRC/.config"
    make -C "$UBOOT_SRC" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" olddefconfig </dev/null >/dev/null
    log "[$label] building"
    make -C "$UBOOT_SRC" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" -j"$NPROC" </dev/null >/dev/null 2>&1 \
        || die "[$label] u-boot build failed"
}

# --- resident: SPL + u-boot.bin that get written to NAND -------------------
build_uboot "$FRAG_RESIDENT" resident
cp -v "$UBOOT_SRC/u-boot.bin"        "$UBOOT_OUT/u-boot.bin"          # resident proper
cp -v "$UBOOT_SRC/spl/sunxi-spl.bin" "$UBOOT_OUT/sunxi-spl.bin"       # resident SPL (pre-ECC)

# --- flasher: the FEL-loaded combined SPL+u-boot ---------------------------
build_uboot "$FRAG_FLASHER" flasher
cp -v "$UBOOT_SRC/u-boot-sunxi-with-spl.bin" "$UBOOT_OUT/flasher-u-boot-sunxi-with-spl.bin"

log "NAND u-boot artifacts in $UBOOT_OUT"
ls -lh "$UBOOT_OUT"
