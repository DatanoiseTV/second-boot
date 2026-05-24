#!/usr/bin/env bash
set -euo pipefail

# Build one legacy CHIP u-boot variant with a specific CONFIG_BOOTCOMMAND.
# Replicates reference pocketchip-debian-builder/scripts/build-legacy-uboot.sh,
# adding a per-variant bootcmd/bootdelay injection into sunxi-common.h.
#
# Usage: build-one-variant.sh <variant-name> <bootcommand> <bootdelay>

variant="$1"
bootcommand="$2"
bootdelay="$3"

root="$HOME/legacy-uboot-build"
uboot_repo="$root/CHIP-u-boot"
patches_dir="$root/patches"
worktree_dir="$root/src-$variant"
build_dir="$root/build-$variant"
cross_compile="arm-linux-gnueabi-"
jobs="$(nproc)"

patches=(
  "$patches_dir/pocketchip-cortex-a8-spectre-v2.patch"
  "$patches_dir/pocketchip-slc-mode.patch"
  "$patches_dir/pocketchip-spl-toshiba-mlc.patch"
  "$patches_dir/pocketchip-spl-toshiba-slc-uboot.patch"
  "$patches_dir/pocketchip-spl-nand-trace.patch"
)

echo "=== building variant: $variant ==="
echo "bootcommand: $bootcommand"
echo "bootdelay:   $bootdelay"

# Fresh isolated worktree at the production-mlc-pc tip.
git -C "$uboot_repo" worktree remove --force "$worktree_dir" >/dev/null 2>&1 || rm -rf "$worktree_dir"
git -C "$uboot_repo" worktree prune
git -C "$uboot_repo" worktree add --force --detach "$worktree_dir" production-mlc-pc

# Apply the five patches in the proven order.
for patch in "${patches[@]}"; do
  echo "apply $patch"
  git -C "$worktree_dir" apply --3way "$patch"
done

# Inject the per-variant bootcmd/bootdelay just before the distro bootcmd
# include, where CONFIG_BOOTCOMMAND/CONFIG_BOOTDELAY are still C macros in this
# 2016-era u-boot (env_default.h consumes them; config_distro_bootcmd.h only
# supplies a fallback when undefined).
common="$worktree_dir/include/configs/sunxi-common.h"
marker='#include <config_distro_bootcmd.h>'
inject="/* PocketCHIP legacy ${variant} variant boot defaults */\n#undef CONFIG_BOOTCOMMAND\n#define CONFIG_BOOTCOMMAND \"${bootcommand}\"\n#undef CONFIG_BOOTDELAY\n#define CONFIG_BOOTDELAY ${bootdelay}\n\n${marker}"
python3 - "$common" "$marker" "$inject" <<'PY'
import sys
path, marker, inject = sys.argv[1], sys.argv[2], sys.argv[3]
inject = inject.replace('\\n', '\n')
with open(path) as f:
    data = f.read()
assert marker in data, "marker not found in %s" % path
assert data.count(marker) == 1, "marker not unique"
data = data.replace(marker, inject, 1)
with open(path, 'w') as f:
    f.write(data)
PY
echo "--- injected boot defaults in sunxi-common.h ---"
grep -n "PocketCHIP legacy ${variant}" "$common" || true
grep -n "CONFIG_BOOTCOMMAND\|CONFIG_BOOTDELAY" "$common"

rm -rf "$build_dir"
mkdir -p "$build_dir/include/linux"
build_dir="$(cd "$build_dir" && pwd)"

make -C "$worktree_dir" O="$build_dir" CROSS_COMPILE="$cross_compile" CHIP_defconfig

# Spectre v2 mitigation: add POCKETCHIP_CORTEX_A8_SPECTRE_V2 to extra options.
extra_options="$(sed -n 's/^CONFIG_SYS_EXTRA_OPTIONS="\([^"]*\)"/\1/p' "$build_dir/.config")"
if [[ -n "$extra_options" && "$extra_options" != *POCKETCHIP_CORTEX_A8_SPECTRE_V2* ]]; then
  extra_options="$extra_options,POCKETCHIP_CORTEX_A8_SPECTRE_V2"
  sed -i "s/^CONFIG_SYS_EXTRA_OPTIONS=.*/CONFIG_SYS_EXTRA_OPTIONS=\"$extra_options\"/" "$build_dir/.config"
elif [[ -z "$extra_options" ]]; then
  printf 'CONFIG_SYS_EXTRA_OPTIONS="POCKETCHIP_CORTEX_A8_SPECTRE_V2"\n' >> "$build_dir/.config"
fi
make -C "$worktree_dir" O="$build_dir" CROSS_COMPILE="$cross_compile" silentoldconfig

# Mirror generated autoconf.h into the source tree for the broken host-tool
# include path of this u-boot vintage.
src_generated="$worktree_dir/include/generated"
src_autoconf="$src_generated/autoconf.h"
build_autoconf="$build_dir/include/generated/autoconf.h"
mkdir -p "$src_generated"
cp "$build_autoconf" "$src_autoconf"

# GCC version compat shim: CHIP-u-boot predates modern compiler-gccN.h names.
gcc_major="$("${cross_compile}gcc" -dumpversion | cut -d. -f1)"
if [[ ! -f "$worktree_dir/include/linux/compiler-gcc${gcc_major}.h" ]]; then
  cp "$worktree_dir/include/linux/compiler-gcc5.h" "$build_dir/include/linux/compiler-gcc${gcc_major}.h"
fi

rm -f \
  "$build_dir/include/config/auto.conf" \
  "$build_dir/include/config/auto.conf.cmd" \
  "$build_dir/include/autoconf.mk" \
  "$build_dir/include/autoconf.mk.dep" \
  "$build_dir/include/config.h"

# GCC 14 promotes several legacy-tolerated warnings to hard errors
# (implicit-function-declaration, return-mismatch, incompatible-pointer-types,
# int-conversion, enum-int-mismatch). This ~2016 u-boot predates that, so
# relax those specific diagnostics back to warnings via KCFLAGS.
kcflags="-Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=return-mismatch -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=enum-int-mismatch -Wno-error=int-to-pointer-cast -Wno-error=pointer-to-int-cast"

make -C "$worktree_dir" O="$build_dir" CROSS_COMPILE="$cross_compile" -j"$jobs" \
  KCFLAGS="$kcflags" \
  spl/sunxi-spl.bin u-boot-dtb.bin u-boot-dtb.img u-boot-sunxi-with-spl.bin

# Clean the temporary source-tree autoconf.h mirror.
rm -f "$src_autoconf"
rmdir "$src_generated" 2>/dev/null || true

echo "=== variant $variant built ==="
ls -l "$build_dir/spl/sunxi-spl.bin" "$build_dir/u-boot-dtb.bin" \
  "$build_dir/u-boot-dtb.img" "$build_dir/u-boot-sunxi-with-spl.bin" 2>/dev/null || true
