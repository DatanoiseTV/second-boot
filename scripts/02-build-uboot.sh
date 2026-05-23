#!/usr/bin/env bash
# Build mainline U-Boot for C.H.I.P. (and PocketCHIP — same boot path).

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.env"
. "$HERE/lib.sh"

UBOOT_SRC="$SOURCES_DIR/u-boot"
UBOOT_OUT="$ARTIFACTS_DIR/uboot"

[ -d "$UBOOT_SRC" ] || die "u-boot source missing; run 01-fetch-sources.sh first"
ensure_dir "$UBOOT_OUT"

# Apply local patches (if any).
if compgen -G "$HERE/../patches/uboot/*.patch" > /dev/null; then
    log "applying local u-boot patches"
    for p in "$HERE"/../patches/uboot/*.patch; do
        git -C "$UBOOT_SRC" apply --check "$p" 2>/dev/null || {
            warn "$p already applied or non-applicable, skipping"
            continue
        }
        git -C "$UBOOT_SRC" apply "$p"
    done
fi

log "configuring u-boot (CHIP_defconfig)"
make -C "$UBOOT_SRC" \
    ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
    CHIP_defconfig

log "building u-boot"
make -C "$UBOOT_SRC" \
    ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
    -j"$NPROC"

cp -v "$UBOOT_SRC/u-boot-sunxi-with-spl.bin" "$UBOOT_OUT/"
cp -v "$UBOOT_SRC/u-boot.bin"                "$UBOOT_OUT/" 2>/dev/null || true
cp -v "$UBOOT_SRC/spl/sunxi-spl.bin"         "$UBOOT_OUT/" 2>/dev/null || true

log "u-boot artifacts in $UBOOT_OUT"
ls -lh "$UBOOT_OUT"
