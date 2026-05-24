#!/usr/bin/env bash
# Flash the PocketCHIP NAND from U-Boot over FEL -- no host kernel needed.
#
# NAND layout written (matches macromorgan's reverse-engineered layout and
# U-Boot board/sunxi/README.nand):
#   0x000000   SPL (boot0, ECC+scramble) copy 1   <- BootROM loads this
#   0x400000   SPL (boot0) copy 2 (backup)        <- one erase block later
#   0x800000   resident u-boot proper             <- SYS_NAND_U_BOOT_OFFS
#   0x1000000  bootfs: kernel uImage (+ embedded initramfs)
#   0x2e00000  bootfs: DTB
#   0x3000000  rootfs (slc-mode UBI) -- written later in Stage 2
#
# The SPL is written RAW (nand write.raw.noverify): sunxi-nand-image-builder
# (run automatically by the CONFIG_MTD_RAW_NAND=y u-boot build, producing
# sunxi-spl-with-ecc.bin) has already baked in the BootROM's 64bit/1024
# ECC + data scrambling. A normal ECC write would re-encode and corrupt the
# BootROM layout. u-boot proper / kernel / dtb use normal `nand write` (the
# data-area HW ECC the resident SPL and kernel read with).
#
# Flow: FEL-load the flasher u-boot, stage all payloads + a flash script in
# DDR, the flasher's bootcmd 'source's the script which erases NAND, writes
# everything, and resets into a cold NAND boot.
#
# Recovery: if the board doesn't cold-boot, FEL still works (BootROM is
# immutable). Power-cycle with the FEL pad shorted and re-run.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

FEL="${SUNXI_FEL:-$REPO/tools/sunxi-tools/sunxi-fel}"
MKIMAGE="${MKIMAGE:-mkimage}"

FLASHER="$REPO/artifacts/uboot-nand/flasher-u-boot-sunxi-with-spl.bin"
# Prefer the build-emitted ECC+scramble SPL image; fall back to a manually
# packed one (scripts/21-pack-spl-for-nand.sh).
SPL_NAND="${SPL_NAND:-$REPO/artifacts/uboot-nand/sunxi-spl-with-ecc.bin}"
[ -f "$SPL_NAND" ] || SPL_NAND="$REPO/artifacts/uboot-nand/sunxi-spl-nand.bin"
# u-boot-dtb.bin: resident u-boot proper WITH its appended control DTB
# (plain u-boot.bin lacks the dtb and won't boot once the SPL hands off).
UBOOT_NAND="${UBOOT_NAND:-$REPO/artifacts/uboot-nand/u-boot-dtb.bin}"
# Stage 1 boots the installer kernel (busybox + mtd-utils + USB gadget);
# override to point at OpenWrt's uImage once Stage 2 is done.
KERNEL_UIMG="${KERNEL_UIMG:-$REPO/artifacts/installer/uImage}"
DTB="${DTB:-$REPO/artifacts/installer/sun5i-r8-chip-pocketchip-ng.dtb}"

# NAND geometry (Toshiba TC58TEG5DCLTA00): 16K page + 1280 OOB.
PAGE=16384
OOB=1280
RAWPAGE=$((PAGE + OOB))   # bytes per page when writing raw (data + OOB)

# DDR staging (all in DRAM the flasher SPL inits; spaced to avoid overlap,
# all well below the flasher u-boot's TEXT_BASE at 0x4a000000).
ADDR_SPL=0x43000000
ADDR_UBOOT=0x44000000
ADDR_UIMG=0x46000000
ADDR_DTB=0x49000000
# Must be valid DRAM (0x40000000-0x5fffffff) and clear of the payloads above
# and u-boot's relocation. Matches flasher CONFIG_BOOTCOMMAND "source ...".
ADDR_SCRIPT=0x4d000000

# NAND target offsets
N_SPL0=0x0
N_SPL1=0x400000
N_UBOOT=0x800000
N_UIMG=0x1000000
N_DTB=0x2e00000

for f in "$FEL" "$FLASHER" "$SPL_NAND" "$UBOOT_NAND" "$KERNEL_UIMG" "$DTB"; do
    [ -e "$f" ] || { echo "missing: $f" >&2; exit 1; }
done
command -v "$MKIMAGE" >/dev/null || { echo "need mkimage (brew install u-boot-tools)" >&2; exit 1; }

hexsz() { printf '0x%x' "$(wc -c < "$1")"; }
# raw page count for the SPL image (ceil(size / (page+oob)))
splpages=$(printf '0x%x' $(( ($(wc -c < "$SPL_NAND") + RAWPAGE - 1) / RAWPAGE )))
ubsz=$(hexsz "$UBOOT_NAND"); uimgsz=$(hexsz "$KERNEL_UIMG"); dtbsz=$(hexsz "$DTB")

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# nand erase.chip (not scrub): scrub prompts y/N interactively and would
# hang here -- we have no console on the flasher. erase.chip skips blocks
# marked bad in the factory BBT, which is what we want.
cat > "$WORK/flash.cmd" <<EOF
echo "=== pocketchip-ng NAND flash ==="
nand erase.chip
echo "SPL (raw) x2 @ 0x0, 0x400000 ..."
nand write.raw.noverify $ADDR_SPL $N_SPL0 $splpages
nand write.raw.noverify $ADDR_SPL $N_SPL1 $splpages
echo "u-boot @ 0x800000 ..."
nand write $ADDR_UBOOT $N_UBOOT $ubsz
echo "uImage @ 0x1000000 ..."
nand write $ADDR_UIMG $N_UIMG $uimgsz
echo "dtb @ 0x2e00000 ..."
nand write $ADDR_DTB $N_DTB $dtbsz
echo "=== done; cold-booting from NAND in 3s ==="
sleep 3
reset
EOF

"$MKIMAGE" -A arm -O linux -T script -C none -a 0 -e 0 \
    -n pocketchip-ng-nand-flash -d "$WORK/flash.cmd" "$WORK/flash.scr" >/dev/null

echo "FEL probe:"; "$FEL" ver
echo ""
echo "Staging payloads + flash script, starting the flasher U-Boot:"
echo "  SPL    -> $ADDR_SPL   ($(hexsz "$SPL_NAND"), $splpages pages raw, written x2)"
echo "  u-boot -> $ADDR_UBOOT ($ubsz)"
echo "  uImage -> $ADDR_UIMG  ($uimgsz)"
echo "  DTB    -> $ADDR_DTB   ($dtbsz)"
echo ""

"$FEL" \
    uboot "$FLASHER" \
    write-with-progress "$ADDR_SPL"   "$SPL_NAND" \
    write-with-progress "$ADDR_UBOOT" "$UBOOT_NAND" \
    write-with-progress "$ADDR_UIMG"  "$KERNEL_UIMG" \
    write-with-progress "$ADDR_DTB"   "$DTB" \
    write               "$ADDR_SCRIPT" "$WORK/flash.scr"

cat <<MSG

Flasher U-Boot is running its bootcmd (source $ADDR_SCRIPT): erase NAND,
write SPL/u-boot/uImage/DTB, reset. The NAND writes take ~30-60s. DO NOT
unplug until well after that.

After reset the board cold-boots from NAND. Watch the Mac for the kernel
USB gadget (CDC-ACM /dev/cu.usbmodem* + CDC-ECM network interface).
If it doesn't appear, FEL still recovers: power-cycle with FEL pad to GND.
MSG
