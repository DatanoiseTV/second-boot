#!/usr/bin/env bash
# Cross-build mainline Linux for the PocketCHIP.

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/versions.env"
. "$HERE/lib.sh"

LINUX_SRC="$SOURCES_DIR/linux"
LINUX_OUT="$ARTIFACTS_DIR/kernel"
FRAG="$HERE/../configs/kernel/pocketchip.fragment"

[ -d "$LINUX_SRC" ] || die "kernel source missing; run 01-fetch-sources.sh first"
[ -f "$FRAG"      ] || die "kernel fragment missing: $FRAG"

ensure_dir "$LINUX_OUT"

# Apply local patches (if any).
if compgen -G "$HERE/../patches/linux/*.patch" > /dev/null; then
    for p in "$HERE"/../patches/linux/*.patch; do
        git -C "$LINUX_SRC" apply --check "$p" 2>/dev/null || {
            warn "$p already applied or non-applicable, skipping"
            continue
        }
        log "applying $p"
        git -C "$LINUX_SRC" apply "$p"
    done
fi

KMAKE=(make -C "$LINUX_SRC" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE")

# Stage out-of-tree DT additions into the kernel's dts tree before config.
DTS_OVERLAY="$HERE/../dts/sun5i-r8-chip-pocketchip-ng.dts"
if [ -f "$DTS_OVERLAY" ]; then
    cp -v "$DTS_OVERLAY" "$LINUX_SRC/arch/arm/boot/dts/allwinner/"
    # Make sure the new dtb appears in the Makefile if not present.
    DTS_MAKEFILE="$LINUX_SRC/arch/arm/boot/dts/allwinner/Makefile"
    DTB_NAME="sun5i-r8-chip-pocketchip-ng.dtb"
    if [ -f "$DTS_MAKEFILE" ] && ! grep -q "$DTB_NAME" "$DTS_MAKEFILE"; then
        log "adding $DTB_NAME to dts Makefile"
        echo "dtb-\$(CONFIG_MACH_SUN5I) += $DTB_NAME" >> "$DTS_MAKEFILE"
    fi
fi

log "applying sunxi_defconfig + pocketchip fragment"
"${KMAKE[@]}" sunxi_defconfig
# Direct-append the fragment to .config. We avoid merge_config.sh
# because it's been observed to silently drop bool symbols whose parent
# menus weren't already enabled in the base defconfig (e.g. CONFIG_WLAN).
cat "$FRAG" >> "$LINUX_SRC/.config"

# If an initramfs cpio is present, bake it into the kernel image. This
# lets us boot via FEL by staging only zImage + DTB in RAM, no separate
# initrd argument needed in U-Boot.
INITRAMFS_CPIO="$ARTIFACTS_DIR/initramfs/initramfs.cpio"
if [ -f "$INITRAMFS_CPIO" ]; then
    log "embedding initramfs from $INITRAMFS_CPIO"
    {
        echo 'CONFIG_BLK_DEV_INITRD=y'
        echo 'CONFIG_INITRAMFS_SOURCE="'"$INITRAMFS_CPIO"'"'
        echo 'CONFIG_INITRAMFS_ROOT_UID=0'
        echo 'CONFIG_INITRAMFS_ROOT_GID=0'
        echo '# CONFIG_INITRAMFS_FORCE is not set'
        echo '# CONFIG_INITRAMFS_COMPRESSION_NONE is not set'
        echo 'CONFIG_INITRAMFS_COMPRESSION_GZIP=y'
    } >> "$LINUX_SRC/.config"
fi

"${KMAKE[@]}" olddefconfig

log "building zImage + DTBs + modules"
"${KMAKE[@]}" -j"$NPROC" zImage dtbs modules

log "installing modules to staging dir"
MOD_STAGE="$LINUX_OUT/modules"
rm -rf "$MOD_STAGE"
ensure_dir "$MOD_STAGE"
"${KMAKE[@]}" INSTALL_MOD_PATH="$MOD_STAGE" modules_install

cp -v "$LINUX_SRC/arch/arm/boot/zImage" "$LINUX_OUT/"
# Copy every sunxi DTB we built; the SD image script will pick the right one.
mkdir -p "$LINUX_OUT/dtbs"
find "$LINUX_SRC/arch/arm/boot/dts" -name 'sun5i-r8-chip*.dtb' \
    -exec cp -v {} "$LINUX_OUT/dtbs/" \;

KREL="$("${KMAKE[@]}" -s kernelrelease)"
echo "$KREL" > "$LINUX_OUT/kernelrelease"
log "kernel $KREL built. zImage + dtbs in $LINUX_OUT, modules in $MOD_STAGE"
