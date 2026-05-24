#!/usr/bin/env bash
# Flash a full, writable OpenWrt to the Toshiba MLC NAND via the PROVEN patched
# LEGACY NTC CHIP u-boot (production-mlc-pc + SPL-geometry-hardcode + slc-mode).
# Same boot chain that already boots our kernel from NAND -- here it boots
# OpenWrt's zImage and mounts a squashfs+overlay rootfs from a slc-mode UBI.
#
# Chain: BootROM -> legacy boot0 (256pg, geometry hardcoded) -> legacy SPL
#   (reliably reads NAND) -> legacy u-boot @0x800000 (.img, slc-mode) -> bootcmd
#   sets OpenWrt bootargs, `nand read.slc-mode` kernel@0x1000000 + dtb@0x2000000,
#   then bootz -> OpenWrt. Root: ubi.mtd=UBI -> ubiblock0_0 (rootfs squashfs),
#   rootfs_data ubifs overlay (autoresize) for the writable layer.
#
# NAND layout written here:
#   boot0    0x00000000 + 0x00400000 (raw, 256-page MLC image, x2)
#   u-boot   0x00800000 (slc)
#   kernel   0x01000000 (slc, raw zImage)
#   dtb      0x02000000 (slc)
#   UBI      0x05000000 (slc, OpenWrt factory.ubi: rootfs + rootfs_data)
#
# All slc writes use `nand write.slc-mode` (= nand_write_skip_bad in slc mode),
# so the UBI image's PEBs map 1:1 onto good physical eraseblocks, bad ones
# skipped -- the standard way to install a ubinize image to NAND from u-boot.
# Region erases skip bad blocks (NOT erase.chip, which aborts on the factory
# bad block). The whole UBI partition is erased first for a clean UBI scan.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
MKIMAGE="${MKIMAGE:-mkimage}"
FLASHER="$REPO/artifacts/uboot-legacy/legacy-flasher-with-spl.bin"
BOOT0="$REPO/artifacts/uboot-legacy/legacy-boot0-256.bin"
UBOOT="$REPO/artifacts/uboot-legacy/legacy-owrt-resident-u-boot.img"  # OpenWrt bootcmd
KERNEL="$REPO/artifacts/openwrt-nand/owrt-kernel.img"                 # raw zImage
DTB="$REPO/artifacts/openwrt-nand/owrt.dtb"
UBI="$REPO/artifacts/openwrt-nand/owrt-rootfs.ubi"                    # factory.ubi (slc geometry)

ADDR_BOOT0=0x42000000
ADDR_UBOOT=0x43000000
ADDR_KERNEL=0x44000000
ADDR_DTB=0x46000000
ADDR_UBI=0x50000000         # well clear of relocated u-boot near RAM top
ADDR_SCRIPT=0x4d000000      # matches legacy flasher bootcmd "source 0x4d000000"

UBI_OFF=0x5000000
# Erase only enough of the UBI partition for the image + headroom; UBI's
# autoresize rootfs_data claims (and erases on demand) the rest of the
# partition at first attach. A bounded erase avoids a multi-minute full-device
# erase that can stall/crash this legacy u-boot before the boot chain is
# written. Round the image size up to 64 MiB, min 64 MiB.
UBI_ERASE=$(printf '0x%x' $(( ( ( $(wc -c < "$UBI") + 0x4000000 - 1 ) / 0x4000000 ) * 0x4000000 )))

PAGE=16384; OOB=1280; RAWPAGE=$((PAGE + OOB))
b0pages=$(printf '0x%x' $(( ($(wc -c < "$BOOT0") + RAWPAGE - 1) / RAWPAGE )))   # 0x100
hexsz() { printf '0x%x' "$(wc -c < "$1")"; }
ubsz=$(hexsz "$UBOOT"); ksz=$(hexsz "$KERNEL"); dsz=$(hexsz "$DTB"); usz=$(hexsz "$UBI")

for f in "$FEL" "$FLASHER" "$BOOT0" "$UBOOT" "$KERNEL" "$DTB" "$UBI"; do
    [ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }
done
command -v "$MKIMAGE" >/dev/null || { echo "need mkimage" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/o.cmd" <<EOF
echo "=== OpenWrt NAND install (legacy NTC u-boot, slc-mode) ==="
echo "erase boot region 0x0..0x2800000 (skip-bad)..."
nand erase 0x0 0x2800000
echo "boot0 raw x2 (0x0/0x400000)..."
nand write.raw.noverify $ADDR_BOOT0 0x0 $b0pages
nand write.raw.noverify $ADDR_BOOT0 0x400000 $b0pages
echo "u-boot slc @ 0x800000..."
nand write.slc-mode $ADDR_UBOOT 0x800000 $ubsz
echo "kernel slc @ 0x1000000..."
nand write.slc-mode $ADDR_KERNEL 0x1000000 $ksz
echo "dtb slc @ 0x2000000..."
nand write.slc-mode $ADDR_DTB 0x2000000 $dsz
echo "--- boot chain written; now UBI rootfs ---"
echo "erase UBI region $UBI_OFF size $UBI_ERASE (skip-bad)..."
nand erase $UBI_OFF $UBI_ERASE
echo "ubi rootfs slc @ 0x5000000..."
nand write.slc-mode $ADDR_UBI $UBI_OFF $usz
echo "=== done; reset in 2s ==="
sleep 2
reset
EOF
"$MKIMAGE" -A arm -O linux -T script -C none -a 0 -e 0 -n pchip-owrt -d "$WORK/o.cmd" "$WORK/o.scr" >/dev/null

echo "FEL probe:"; "$FEL" ver
echo "  boot0  -> 0x0/0x400000 ($b0pages pages raw)"
echo "  u-boot -> 0x800000 slc ($ubsz)"
echo "  kernel -> 0x1000000 slc ($ksz)"
echo "  dtb    -> 0x2000000 slc ($dsz)"
echo "  ubi    -> 0x5000000 slc ($usz)"
"$FEL" \
    uboot "$FLASHER" \
    write-with-progress "$ADDR_BOOT0"  "$BOOT0" \
    write-with-progress "$ADDR_UBOOT"  "$UBOOT" \
    write-with-progress "$ADDR_KERNEL" "$KERNEL" \
    write-with-progress "$ADDR_DTB"    "$DTB" \
    write-with-progress "$ADDR_UBI"    "$UBI" \
    write               "$ADDR_SCRIPT" "$WORK/o.scr"
echo ""
echo "Reset pending. Board should stay powered and boot OpenWrt in ~15s."
echo "Look for PocketCHIP_NG / a CDC-ACM serial + CDC-ECM net device on USB."
