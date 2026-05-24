#!/usr/bin/env bash
# Flash the MODERN boot chain to NAND (boot0 + u-boot + kernel + dtb), all plain
# MLC with the unified sunxi BCH-40/1024 + scrambler ECC shared bit-for-bit
# between u-boot v2025.01 and the Linux 6.12 kernel (after the nand_toshiba
# NAND_NEED_SCRAMBLING fix). Replaces the legacy 2016 NTC u-boot with mainline.
#
# The UBI rootfs is NOT written here: UBI/ubinize cannot use the 4 MiB MLC
# eraseblock (max PEB 2 MiB), so the rootfs must be a slc-mode UBI installed by
# the KERNEL via ubiformat (scripts/40 + ubiformat) in a second FEL session.
#
# Chain: BootROM -> modern boot0 (256-page, BCH-64) -> modern SPL (geometry
# hardcode) -> modern u-boot @0x800000 -> nand read kernel@0x1000000 +
# dtb@0x2000000 (MLC, unified ECC) -> bootz -> kernel -> slc-mode UBI rootfs.
#
# The flasher (modern u-boot, bootcmd "source 0x4d000000") is FEL-run and sources
# the staged script, writing with the modern NAND driver so the ECC/scramble
# matches what the SPL/u-boot/kernel later read.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
MKIMAGE="${MKIMAGE:-mkimage}"
FLASHER="$REPO/artifacts/uboot-modern/modern-flasher-with-spl.bin"   # bootcmd=source 0x4d000000
BOOT0="$REPO/artifacts/uboot-modern/modern-boot0.bin"                # 256-page, BCH-64
UBOOT="$REPO/artifacts/uboot-modern/modern-resident-u-boot.img"      # NAND-boot bootcmd
KERNEL="$REPO/artifacts/openwrt-nand/owrt-kernel.img"                # zImage
DTB="$REPO/artifacts/openwrt-nand/owrt.dtb"                          # slc-mode UBI dtb

ADDR_BOOT0=0x42000000
ADDR_UBOOT=0x43000000
ADDR_KERNEL=0x44000000
ADDR_DTB=0x46000000
ADDR_SCRIPT=0x4d000000

PAGE=16384; OOB=1280; RAWPAGE=$((PAGE + OOB))
b0pages=$(printf '0x%x' $(( ($(wc -c < "$BOOT0") + RAWPAGE - 1) / RAWPAGE )))   # 0x100
hexsz() { printf '0x%x' "$(wc -c < "$1")"; }
ubsz=$(hexsz "$UBOOT"); ksz=$(hexsz "$KERNEL"); dsz=$(hexsz "$DTB")

for f in "$FEL" "$FLASHER" "$BOOT0" "$UBOOT" "$KERNEL" "$DTB"; do [ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }; done
command -v "$MKIMAGE" >/dev/null || { echo "need mkimage" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/m.cmd" <<EOF
echo "=== modern boot chain flash (MLC, unified ECC) ==="
nand erase 0x0 0x2800000
echo "boot0 raw x2..."
nand write.raw.noverify $ADDR_BOOT0 0x0 $b0pages
nand write.raw.noverify $ADDR_BOOT0 0x400000 $b0pages
echo "u-boot @0x800000..."
nand write $ADDR_UBOOT 0x800000 $ubsz
echo "kernel @0x1000000..."
nand write $ADDR_KERNEL 0x1000000 $ksz
echo "dtb @0x2000000..."
nand write $ADDR_DTB 0x2000000 $dsz
echo "=== boot chain done; reset in 2s (UBI rootfs via kernel ubiformat next) ==="
sleep 2
reset
EOF
"$MKIMAGE" -A arm -O linux -T script -C none -a 0 -e 0 -n pchip-modern -d "$WORK/m.cmd" "$WORK/m.scr" >/dev/null

echo "FEL probe:"; "$FEL" ver
echo "  boot0  -> 0x0/0x400000 ($b0pages pages, BCH-64)"
echo "  u-boot -> 0x800000 ($ubsz)  [modern v2025.01]"
echo "  kernel -> 0x1000000 ($ksz)"
echo "  dtb    -> 0x2000000 ($dsz)"
"$FEL" \
    uboot "$FLASHER" \
    write-with-progress "$ADDR_BOOT0"  "$BOOT0" \
    write-with-progress "$ADDR_UBOOT"  "$UBOOT" \
    write-with-progress "$ADDR_KERNEL" "$KERNEL" \
    write-with-progress "$ADDR_DTB"    "$DTB" \
    write               "$ADDR_SCRIPT" "$WORK/m.scr"
echo ""
echo "Modern boot chain flashed + reset. It NAND-boots the new kernel but the UBI"
echo "rootfs is still the old/absent one -- next: FEL-boot initramfs + ubiformat"
echo "the slc UBI (scripts/40 then ubiformat /dev/mtd5 -f factory.ubi)."
