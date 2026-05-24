#!/usr/bin/env bash
set -euo pipefail
root="$HOME/legacy-uboot-build"
uboot_repo="$root/CHIP-u-boot"; patches_dir="$root/patches"
variant="felboot"; worktree_dir="$root/src-$variant"; build_dir="$root/build-$variant"
cross_compile="arm-linux-gnueabi-"; jobs="$(nproc)"
patches=( pocketchip-cortex-a8-spectre-v2 pocketchip-slc-mode pocketchip-spl-toshiba-mlc pocketchip-spl-toshiba-slc-uboot pocketchip-spl-nand-trace )
bootcommand="setenv bootargs 'console=ttyGS0,115200 console=ttyS0,115200 panic=10'; bootz 0x42000000 - 0x49000000"

git -C "$uboot_repo" worktree remove --force "$worktree_dir" >/dev/null 2>&1 || rm -rf "$worktree_dir"
git -C "$uboot_repo" worktree prune
git -C "$uboot_repo" worktree add --force --detach "$worktree_dir" production-mlc-pc
for p in "${patches[@]}"; do git -C "$worktree_dir" apply --3way "$patches_dir/$p.patch"; done

common="$worktree_dir/include/configs/sunxi-common.h"
# (1) Inject bootcmd/bootdelay at the distro-bootcmd marker.
marker='#include <config_distro_bootcmd.h>'
inject="/* felboot variant */\n#undef CONFIG_BOOTCOMMAND\n#define CONFIG_BOOTCOMMAND \"${bootcommand}\"\n#undef CONFIG_BOOTDELAY\n#define CONFIG_BOOTDELAY 0\n\n${marker}"
# (2) Define CONFIG_ENV_SIZE at TOP LEVEL (before the env-location #if block, so
#     both SPL and u-boot proper see it once ENV_IS_NOWHERE is active).
envmarker='#if defined(CONFIG_ENV_IS_IN_NAND)'
envinject="#ifndef CONFIG_ENV_SIZE\n#define CONFIG_ENV_SIZE\t\t\t0x20000\n#endif\n\n${envmarker}"
python3 - "$common" "$marker" "$inject" "$envmarker" "$envinject" <<'PY'
import sys
path, m1, i1, m2, i2 = sys.argv[1:6]
i1=i1.replace('\\n','\n').replace('\\t','\t'); i2=i2.replace('\\n','\n').replace('\\t','\t')
d=open(path).read()
assert d.count(m1)==1, "bootcmd marker"; d=d.replace(m1,i1,1)
assert d.count(m2)>=1, "env marker"; d=d.replace(m2,i2,1)
open(path,"w").write(d)
print("injected bootcmd + CONFIG_ENV_SIZE")
PY

rm -rf "$build_dir"; mkdir -p "$build_dir/include/linux"; build_dir="$(cd "$build_dir" && pwd)"
make -C "$worktree_dir" O="$build_dir" CROSS_COMPILE="$cross_compile" CHIP_defconfig
# Remove ENV_IS_IN_NAND from SYS_EXTRA_OPTIONS -> no ENV_IS_IN_* -> ENV_IS_NOWHERE.
sed -i 's/,ENV_IS_IN_NAND//; s/ENV_IS_IN_NAND,//; s/ENV_IS_IN_NAND//' "$build_dir/.config"
eo="$(sed -n 's/^CONFIG_SYS_EXTRA_OPTIONS="\([^"]*\)"/\1/p' "$build_dir/.config")"
if [[ -n "$eo" && "$eo" != *POCKETCHIP_CORTEX_A8_SPECTRE_V2* ]]; then sed -i "s/^CONFIG_SYS_EXTRA_OPTIONS=.*/CONFIG_SYS_EXTRA_OPTIONS=\"$eo,POCKETCHIP_CORTEX_A8_SPECTRE_V2\"/" "$build_dir/.config"; elif [[ -z "$eo" ]]; then echo 'CONFIG_SYS_EXTRA_OPTIONS="POCKETCHIP_CORTEX_A8_SPECTRE_V2"' >> "$build_dir/.config"; fi
make -C "$worktree_dir" O="$build_dir" CROSS_COMPILE="$cross_compile" silentoldconfig
src_gen="$worktree_dir/include/generated"; mkdir -p "$src_gen"; cp "$build_dir/include/generated/autoconf.h" "$src_gen/autoconf.h"
gm="$("${cross_compile}gcc" -dumpversion|cut -d. -f1)"; [[ -f "$worktree_dir/include/linux/compiler-gcc${gm}.h" ]] || cp "$worktree_dir/include/linux/compiler-gcc5.h" "$build_dir/include/linux/compiler-gcc${gm}.h"
rm -f "$build_dir/include/config/auto.conf" "$build_dir/include/config/auto.conf.cmd" "$build_dir/include/autoconf.mk" "$build_dir/include/autoconf.mk.dep" "$build_dir/include/config.h"
kc="-Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=return-mismatch -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=enum-int-mismatch -Wno-error=int-to-pointer-cast -Wno-error=pointer-to-int-cast"
make -C "$worktree_dir" O="$build_dir" CROSS_COMPILE="$cross_compile" -j"$jobs" KCFLAGS="$kc" spl/sunxi-spl.bin u-boot-dtb.bin u-boot-sunxi-with-spl.bin
rm -f "$src_gen/autoconf.h"; rmdir "$src_gen" 2>/dev/null || true
echo "=== felboot built ==="; ls -l "$build_dir/u-boot-sunxi-with-spl.bin"
