#!/usr/bin/env bash
set -euo pipefail

# Replicates prepare_spl() from pocketchip-debian-builder/scripts/build-nand-image.sh
# for the toshiba-4g-mlc geometry. Tiles the SPL across the 4 MiB eraseblock as
# 4 slots, each [boot0-image | random padding], all run through
# sunxi-nand-image-builder. Output is the 256-page tiled boot0.

spl_image="$1"
out="$2"

builder="$HOME/pocketchip-build/sources/sunxi-tools/sunxi-nand-image-builder"

# toshiba-4g-mlc geometry (matches docs/nand.md: 400000-4000-500)
eraseblocksize=4194304   # 0x400000
pagesize=16384           # 0x4000
oob=1280                 # 0x500

repeat=$((eraseblocksize / pagesize / 64))   # 4194304/16384/64 = 4 slots

tmpdir="$(mktemp -d)"
nandspl="$tmpdir/nand-spl.bin"
nandpaddedspl="$tmpdir/nand-padded-spl.bin"
padding="$tmpdir/padding"
splpadding="$tmpdir/nand-spl-padding"

"$builder" -c 64/1024 -p "$pagesize" -o "$oob" -u 1024 -e "$eraseblocksize" -b -s "$spl_image" "$nandspl"
splsize="$(stat --printf='%s' "$nandspl")"
paddingsize=$((64 - (splsize / (pagesize + oob))))

echo "spl raw size:    $(stat --printf='%s' "$spl_image")"
echo "nandspl size:    $splsize"
echo "repeat slots:    $repeat"
echo "padding size KB: $paddingsize"

: > "$out"
for ((i = 0; i < repeat; i++)); do
  dd if=/dev/urandom of="$padding" bs=1024 count="$paddingsize" status=none
  "$builder" -c 64/1024 -p "$pagesize" -o "$oob" -u 1024 -e "$eraseblocksize" -b -s "$padding" "$splpadding"
  cat "$nandspl" "$splpadding" > "$nandpaddedspl"
  cat "$nandpaddedspl" >> "$out"
done

rm -rf "$tmpdir"

echo "boot0 out: $out"
echo "boot0 size: $(stat --printf='%s' "$out") bytes"
