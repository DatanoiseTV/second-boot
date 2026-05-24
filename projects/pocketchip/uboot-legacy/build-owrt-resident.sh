#!/usr/bin/env bash
set -euo pipefail
cd ~/legacy-uboot-build
BC="setenv bootargs 'console=tty0 console=ttyGS0,115200 ubi.mtd=UBI ubi.block=0,rootfs root=/dev/ubiblock0_0 rootfstype=squashfs rootwait'; nand read.slc-mode 0x42000000 0x1000000 0x800000; nand read.slc-mode 0x49000000 0x2000000 0x20000; bootz 0x42000000 - 0x49000000"
./build-one-variant.sh owrt-resident "$BC" 1
