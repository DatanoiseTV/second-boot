#!/usr/bin/env bash
# Flash ONLY the NAND boot region (boot0 + resident u-boot + kernel + dtb) via
# FEL, slc-mode. Use this to update the boot chain without touching the UBI
# rootfs (which must be installed separately by the kernel via ubiformat --
# u-boot's slc-mode ECC is unreadable by the kernel, see scripts/40).
#
# Writes: legacy boot0 raw x2 (0x0/0x400000), resident u-boot @0x800000,
# OpenWrt zImage @0x1000000, dtb @0x2000000 -- all slc. Region-erases the boot
# area first (skip-bad). Boots OUR proven chain: BootROM -> legacy boot0 ->
# legacy SPL -> resident u-boot (console=ttyS0) -> nand read.slc-mode + bootz.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
MKIMAGE="${MKIMAGE:-mkimage}"
FLASHER="$REPO/artifacts/uboot-legacy/legacy-flasher-with-spl.bin"
BOOT0="$REPO/artifacts/uboot-legacy/legacy-boot0-256.bin"
UBOOT="$REPO/artifacts/uboot-legacy/legacy-owrt-resident-ttys0-u-boot.img"  # console=ttyS0 bootargs
KERNEL="$REPO/artifacts/openwrt-nand/owrt-kernel.img"                       # raw zImage (sun4i-codec built-in)
DTB="$REPO/artifacts/openwrt-nand/owrt.dtb"                                 # post-power-on-delay-ms for RTL8723BS

ADDR_BOOT0=0x42000000
ADDR_UBOOT=0x43000000
ADDR_KERNEL=0x44000000
ADDR_DTB=0x46000000
ADDR_SCRIPT=0x4d000000

PAGE=16384; OOB=1280; RAWPAGE=$((PAGE + OOB))
b0pages=$(printf '0x%x' $(( ($(wc -c < "$BOOT0") + RAWPAGE - 1) / RAWPAGE )))
hexsz() { printf '0x%x' "$(wc -c < "$1")"; }
ubsz=$(hexsz "$UBOOT"); ksz=$(hexsz "$KERNEL"); dsz=$(hexsz "$DTB")

for f in "$FEL" "$FLASHER" "$BOOT0" "$UBOOT" "$KERNEL" "$DTB"; do [ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }; done
command -v "$MKIMAGE" >/dev/null || { echo "need mkimage" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/r.cmd" <<EOF
echo "=== flash boot region (slc-mode) ==="
nand erase 0x0 0x2800000
echo "boot0 raw x2..."
nand write.raw.noverify $ADDR_BOOT0 0x0 $b0pages
nand write.raw.noverify $ADDR_BOOT0 0x400000 $b0pages
echo "u-boot slc @0x800000..."
nand write.slc-mode $ADDR_UBOOT 0x800000 $ubsz
echo "kernel slc @0x1000000..."
nand write.slc-mode $ADDR_KERNEL 0x1000000 $ksz
echo "dtb slc @0x2000000..."
nand write.slc-mode $ADDR_DTB 0x2000000 $dsz
echo "=== boot region done; reset in 2s (UBI rootfs unchanged) ==="
sleep 2
reset
EOF
"$MKIMAGE" -A arm -O linux -T script -C none -a 0 -e 0 -n pchip-bootregion -d "$WORK/r.cmd" "$WORK/r.scr" >/dev/null

echo "FEL probe:"; "$FEL" ver
echo "  boot0  -> 0x0/0x400000 ($b0pages pages)"
echo "  u-boot -> 0x800000 ($ubsz)  [console=ttyS0]"
echo "  kernel -> 0x1000000 ($ksz)  [sun4i-codec]"
echo "  dtb    -> 0x2000000 ($dsz)  [wifi reset delay]"
"$FEL" \
    uboot "$FLASHER" \
    write-with-progress "$ADDR_BOOT0"  "$BOOT0" \
    write-with-progress "$ADDR_UBOOT"  "$UBOOT" \
    write-with-progress "$ADDR_KERNEL" "$KERNEL" \
    write-with-progress "$ADDR_DTB"    "$DTB" \
    write               "$ADDR_SCRIPT" "$WORK/r.scr"
echo ""
echo "Boot region flashed. Board resets and NAND-boots the new kernel/dtb"
echo "(with the OLD rootfs until you run the UBI install, scripts/40 + ubiformat)."
