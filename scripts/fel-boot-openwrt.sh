#!/usr/bin/env bash
# FEL-boot the freshly-built OpenWrt image into RAM.
#
# OpenWrt produces (for our sunxi-cortexa8 + nextthing_chip-pocketchip-ng
# target with CONFIG_TARGET_ROOTFS_INITRAMFS=y):
#
#   openwrt-sunxi-cortexa8-nextthing_chip-pocketchip-ng-initramfs-kernel.bin
#
# That is a zImage with the initramfs (squashed root with all packages,
# kmods, and our /etc overlay) embedded. We pre-stage it at the same
# address U-Boot's bootcmd expects, plus the DTB, then trigger U-Boot.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
UBOOT="${UBOOT_BIN:-$REPO/artifacts/uboot/u-boot-sunxi-with-spl.bin}"

# Search candidates -- OpenWrt drops the artifact in the build tree on
# the remote host, so by default we expect it to be rsync'd into
# artifacts/openwrt/ first by 11-pull-openwrt-image.sh.
KIMG="${OPENWRT_KIMG:-$REPO/artifacts/openwrt/initramfs-kernel.bin}"
DTB="${DTB_BIN:-$REPO/artifacts/openwrt/sun5i-r8-chip-pocketchip-ng.dtb}"

# DDR layout: u-boot lives at 0x4a000000; keep everything well below.
KIMG_ADDR=0x42000000
DTB_ADDR=0x43000000

for f in "$FEL" "$UBOOT" "$KIMG" "$DTB"; do
    [ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }
done

echo "FEL probe:"
"$FEL" ver

echo ""
echo "Staging files in DDR and starting U-Boot..."
echo "  kernel -> $KIMG_ADDR  ($(wc -c < "$KIMG") bytes)"
echo "  DTB    -> $DTB_ADDR   ($(wc -c < "$DTB") bytes)"
echo ""

"$FEL" \
    uboot "$UBOOT" \
    write-with-progress "$KIMG_ADDR" "$KIMG" \
    write-with-progress "$DTB_ADDR" "$DTB"

echo ""
cat <<MSG

U-Boot has the kernel staged at $KIMG_ADDR and is about to execute.

What to expect on the Mac side, in this order (allow ~10 seconds):

  1. New USB device 'PocketCHIP-NG' appears
  2. /dev/cu.usbmodem* exists (CDC-ACM serial console)
  3. New network interface (en17/en18/etc.) with link-local IP
  4. ssh root@10.43.43.1   (using your GitHub ed25519 / RSA keys)

To watch enumeration:
  while sleep 1; do
      ls /dev/cu.usbmodem* 2>/dev/null
      ifconfig | grep -A1 PocketCHIP
  done
MSG
