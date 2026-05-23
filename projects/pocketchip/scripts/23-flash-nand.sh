#!/bin/sh
# Flash the PocketCHIP NAND from a FEL-booted Linux.
#
# This script is meant to run ON the PocketCHIP itself, after it has
# been booted via FEL into a kernel that has mtd-utils. The Mac side
# uses scp to push the artifacts up before invoking it:
#
#   scp -O artifacts/uboot-nand/sunxi-spl-nand.bin   root@10.43.43.1:/tmp/
#   scp -O artifacts/uboot-nand/u-boot.bin           root@10.43.43.1:/tmp/
#   scp -O artifacts/ubi/pocketchip.ubi              root@10.43.43.1:/tmp/
#   scp -O scripts/23-flash-nand.sh                  root@10.43.43.1:/tmp/
#   ssh root@10.43.43.1 'sh /tmp/23-flash-nand.sh'
#
# This is destructive to NAND. After it runs the device should reboot
# from NAND alone. FEL recovery is still available if anything goes
# wrong (it's BootROM-resident and cannot be wiped by NAND writes).

set -e

echo "=== PocketCHIP NAND flash ==="
echo ""
echo "PRE-FLIGHT"
echo "  - confirm /proc/mtd shows at least one mtd device"
echo "  - confirm dmesg shows the NAND was probed cleanly"
echo "  - confirm /tmp has spl, u-boot.bin, pocketchip.ubi"
echo ""
ls -lh /tmp/sunxi-spl-nand.bin /tmp/u-boot.bin /tmp/pocketchip.ubi || {
    echo "missing artifacts in /tmp; aborting"; exit 1
}
echo ""
cat /proc/mtd

# Identify MTD partitions. The sunxi NAND driver typically exposes
# /dev/mtd0 as the whole device; we partition logically via offsets.
NAND=/dev/mtd0
[ -c "$NAND" ] || { echo "no $NAND -- is mtd-utils + nand probed?"; exit 1; }

echo ""
echo "FLASHING boot0 (SPL) at four sunxi BootROM offsets"
for off in 0x000000 0x400000 0x800000 0xc00000; do
    echo "  -> $off"
    flash_erase "$NAND" "$off" 1
    nandwrite -p -s $((off)) "$NAND" /tmp/sunxi-spl-nand.bin
done

echo ""
echo "FLASHING U-Boot proper at 0x1000000 (16 MiB) and 0x1400000 (20 MiB)"
for off in 0x1000000 0x1400000; do
    echo "  -> $off"
    flash_erase "$NAND" "$off" 1
    nandwrite -p -s $((off)) "$NAND" /tmp/u-boot.bin
done

echo ""
echo "WRITING UBI image to NAND from 0x2000000 (32 MiB) to end"
flash_erase "$NAND" 0x2000000 0
ubiformat "$NAND" -s 2048 -O 2048
ubinize_offset=0x2000000
# ubidetach/attach to enable volume operations
ubidetach -m 0 2>/dev/null || true
nandwrite -p -s $((ubinize_offset)) "$NAND" /tmp/pocketchip.ubi

echo ""
echo "DONE. Sync and reboot:"
echo "  sync"
echo "  reboot"
echo ""
echo "After reboot the board boots SPL -> U-Boot -> kernel from NAND."
echo "If anything fails, FEL recovery still works: short FEL pad to GND"
echo "while applying power and the BootROM will appear on USB again."
