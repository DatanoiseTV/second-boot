# Installing our kernel via the original NTC U-Boot (the easy, safe way)

This is the method that actually worked, and it's far safer than
reflashing SPL/U-Boot into NAND. It piggy-backs on the original Next
Thing Co. bootloader, which is already in NAND and proven.

## Why it works

NTC's U-Boot environment boots like this (see
`reference/ntc-original/uboot-env.txt`):

```
boot_noinitrd: ubi part UBI; ubifsmount ubi0:rootfs;
   ubifsload $fdt_addr_r /boot/sun5i-r8-chip.dtb;
   ubifsload $kernel_addr_r /boot/zImage;
   bootz $kernel_addr_r - $fdt_addr_r
boot_initrd:   ... also ubifsload 0x44000000 /boot/initrd.uimage ...
bootpaths = "initrd noinitrd"
```

So U-Boot loads `/boot/zImage`, `/boot/sun5i-r8-chip.dtb` (and, on the
initrd path, `/boot/initrd.uimage`) **from the writable UBI rootfs** and
`bootz`'s them. Replace those files and you boot your own kernel -- no
SPL, no boot0 ECC, no NAND partition writes.

## Steps

Prereqs: the board is booted into the original OS, reachable over `usb0`
(ssh `chip@<board-ip>`, key installed, passwordless sudo). Build outputs:
a raw `zImage` (with an embedded initramfs, or paired with an initrd),
our DTB, and the initramfs wrapped as a uImage.

```sh
# 1. Wrap our initramfs cpio as a u-boot ramdisk (on the build host):
mkimage -A arm -O linux -T ramdisk -C none -a 0 -e 0 \
    -n pocketchip-ng-initramfs -d initramfs.cpio initrd.uimage

# 2. Copy the three files to the board:
scp zImage         chip@<board>:/tmp/our-zImage
scp <our>.dtb      chip@<board>:/tmp/our-dtb
scp initrd.uimage  chip@<board>:/tmp/our-initrd.uimage

# 3. On the board: back up NTC's originals, install ours, reboot:
sudo cp -n /boot/zImage             /boot/zImage.ntc
sudo cp -n /boot/sun5i-r8-chip.dtb  /boot/sun5i-r8-chip.dtb.ntc
sudo cp -n /boot/initrd.uimage      /boot/initrd.uimage.ntc
sudo cp /tmp/our-zImage        /boot/zImage
sudo cp /tmp/our-dtb           /boot/sun5i-r8-chip.dtb
sudo cp /tmp/our-initrd.uimage /boot/initrd.uimage
sudo sync && sudo reboot
```

We replace **all three** files (not just zImage) because NTC tries the
`initrd` boot path first; if `/boot/initrd.uimage` were still NTC's, it
would load their initramfs over ours. `fw_setenv` can't be used to set
`bootpaths=noinitrd` here -- it fails with "Unsupported flash type 8" on
this MLC NAND -- so making all three files ours is the clean fix.

## Result

NTC U-Boot -> our 6.12 kernel -> our initramfs. The USB gadget comes up
on the cold boot (CDC-ACM `/dev/cu.usbmodem*` + CDC-ECM `usb0`), unlike
FEL RAM-boots where the OTG controller is left in FEL-session state.

## Rollback

```sh
sudo cp /boot/zImage.ntc            /boot/zImage
sudo cp /boot/sun5i-r8-chip.dtb.ntc /boot/sun5i-r8-chip.dtb
sudo cp /boot/initrd.uimage.ntc     /boot/initrd.uimage
sudo sync && sudo reboot
```

`.bak` copies of NTC's kernel/dtb also exist from the factory image, and
mtd0-3 are backed up with OOB on the host. FEL is the final safety net.
