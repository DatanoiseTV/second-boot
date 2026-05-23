#!/usr/bin/env bash
# Build a NAND-resident U-Boot for the PocketCHIP. The resulting
# u-boot-sunxi-with-spl.bin is laid out for being burned into NAND
# (boot0 = SPL with ECC, boot1 = u-boot proper); see
# scripts/21-pack-spl-for-nand.sh for the ECC-aware repackaging step.
#
# This produces a DIFFERENT artifact from 02-build-uboot.sh (which
# builds an SD/FEL-RAM variant). The directories are kept separate so
# you can keep both around for recovery purposes.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.env"
. "$HERE/lib.sh"

UBOOT_SRC="$SOURCES_DIR/u-boot"
UBOOT_OUT="$ARTIFACTS_DIR/uboot-nand"
FRAG="$HERE/../configs/uboot/pocketchip-nand.fragment.config"

[ -d "$UBOOT_SRC" ] || die "u-boot source missing; run 01-fetch-sources.sh first"
[ -f "$FRAG"      ] || die "missing $FRAG"

ensure_dir "$UBOOT_OUT"

log "configuring u-boot (CHIP_defconfig + NAND fragment)"
make -C "$UBOOT_SRC" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
    distclean
make -C "$UBOOT_SRC" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
    CHIP_defconfig

log "applying $FRAG"
cat "$FRAG" >> "$UBOOT_SRC/.config"
make -C "$UBOOT_SRC" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
    olddefconfig

log "building NAND-targeted u-boot"
make -C "$UBOOT_SRC" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
    -j"$NPROC"

cp -v "$UBOOT_SRC/u-boot-sunxi-with-spl.bin" "$UBOOT_OUT/"
cp -v "$UBOOT_SRC/u-boot.bin"                "$UBOOT_OUT/"
cp -v "$UBOOT_SRC/spl/sunxi-spl.bin"         "$UBOOT_OUT/"

log "NAND u-boot artifacts in $UBOOT_OUT"
ls -lh "$UBOOT_OUT"
