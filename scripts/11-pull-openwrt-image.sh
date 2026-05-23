#!/usr/bin/env bash
# Pull the just-built OpenWrt artifact + DTB down to the Mac.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

REMOTE_HOST="${REMOTE_HOST:-syso@10.243.243.8}"
REMOTE_BIN="\$HOME/pocketchip-build/sources/openwrt/bin/targets/sunxi/cortexa8"

DST="$REPO/artifacts/openwrt"
mkdir -p "$DST"

echo "fetching OpenWrt artifacts from $REMOTE_HOST:$REMOTE_BIN"
ssh "$REMOTE_HOST" "ls $REMOTE_BIN/" || {
    echo "remote build dir not present; did the OpenWrt build finish?" >&2
    exit 1
}

# The initramfs kernel binary -- the thing we FEL-boot.
scp "$REMOTE_HOST:$REMOTE_BIN/*nextthing_chip-pocketchip-ng-initramfs-kernel.bin" \
    "$DST/initramfs-kernel.bin"

# Sysupgrade image (for later NAND install).
scp "$REMOTE_HOST:$REMOTE_BIN/*nextthing_chip-pocketchip-ng-squashfs-sysupgrade.bin" \
    "$DST/sysupgrade.bin" 2>/dev/null || true

# The DTB lives in the kernel-build dir, not in bin/. Fetch from the
# kernel build's "linux-*/arch/arm/boot/dts/allwinner/" subtree.
ssh "$REMOTE_HOST" '
    F=$(find $HOME/pocketchip-build/sources/openwrt/build_dir -name "sun5i-r8-chip-pocketchip-ng.dtb" 2>/dev/null | head -1)
    [ -n "$F" ] && cat "$F"
' > "$DST/sun5i-r8-chip-pocketchip-ng.dtb" || true

ls -lh "$DST/"
