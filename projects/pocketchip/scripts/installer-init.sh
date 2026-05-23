#!/bin/sh
# Autonomous OpenWrt installer initramfs /init.
# Runs from a FEL boot (no console/gadget needed): mount the NAND UBI
# rootfs and drop OpenWrt into /boot, then reboot into a clean NAND boot.
PATH=/bin:/sbin:/usr/bin:/usr/sbin; export PATH
/bin/busybox --install -s /bin 2>/dev/null
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
mount -t devtmpfs devtmpfs /dev 2>/dev/null
# status LED on (axp gpio / chip:white:status) as a crude progress sign
echo none > /sys/class/leds/*status*/trigger 2>/dev/null
echo 1 > /sys/class/leds/*status*/brightness 2>/dev/null
# wait for ubi0 (kernel auto-attaches via ubi.mtd=4)
i=0; while [ ! -e /dev/ubi0 ] && [ $i -lt 15 ]; do sleep 1; i=$((i+1)); done
mkdir -p /mnt
if mount -t ubifs ubi0:rootfs /mnt 2>/dev/null && [ -d /mnt/boot ]; then
    cp -f /mnt/boot/zImage /mnt/boot/zImage.preopenwrt 2>/dev/null
    cp -f /install/openwrt-zImage   /mnt/boot/zImage
    cp -f /install/empty-initrd.uimage /mnt/boot/initrd.uimage
    cp -f /install/our.dtb          /mnt/boot/sun5i-r8-chip.dtb
    sync
    # blink fast 6x = success
    n=0; while [ $n -lt 12 ]; do echo 1 > /sys/class/leds/*status*/brightness 2>/dev/null; sleep 0.15; echo 0 > /sys/class/leds/*status*/brightness 2>/dev/null; sleep 0.15; n=$((n+1)); done
    umount /mnt; sync
    sleep 1
    reboot -f
else
    # mount failed (ECC mismatch?) -- slow blink forever
    while true; do echo 1 > /sys/class/leds/*status*/brightness 2>/dev/null; sleep 1; echo 0 > /sys/class/leds/*status*/brightness 2>/dev/null; sleep 1; done
fi
