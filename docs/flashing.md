# PocketCHIP-NG flashing & FEL recovery

## What "FEL mode" is

The Allwinner R8 BootROM has a permanent USB recovery mode called FEL.
When the SoC fails to find a valid boot image, *or* a specific pin is
held at boot, the BootROM exposes a USB device (VID 1f3a / PID efe8) on
the OTG port that accepts code to be uploaded into SRAM/DRAM and
executed. **It is impossible to brick the C.H.I.P. by software** — even
a fully wiped NAND falls back to FEL.

On the PocketCHIP the FEL trigger is a small pad on the C.H.I.P. board
labelled `FEL` near the USB OTG receptacle. Short it to `GND` while
plugging in USB power, then release. If everything is wired up correctly
the Mac will see:

    $ ioreg -p IOUSB -l -w 0 | grep -E "idVendor|idProduct"
    "idVendor" = 7994     (0x1f3a, Allwinner)
    "idProduct" = 61416   (0xefe8, FEL)

…and `sunxi-fel ver` will report `soc=00001625(A13)`.

## RAM-only smoke test (no risk)

This boots a fresh mainline kernel + initramfs into DDR without ever
touching the NAND. After power-cycle the board reverts to whatever it
was doing before.

1. Put the PocketCHIP into FEL mode (see above), connect USB to the Mac.
2. Verify communication:

       ./tools/sunxi-tools/sunxi-fel ver

3. Run the launcher:

       ./scripts/fel-boot.sh

   The launcher uploads our U-Boot SPL + U-Boot proper into DDR,
   stages the kernel at `0x42000000` and DTB at `0x43000000`, and then
   releases the SoC. U-Boot wakes up with `bootcmd=bootz 0x42000000 -
   0x43000000` and starts Linux.

4. Within a couple of seconds the PocketCHIP should re-enumerate on USB,
   this time as a CDC-ACM serial gadget + ECM/RNDIS ethernet. On macOS:

       ls /dev/cu.usbmodem*
       screen /dev/cu.usbmodem<TAB> 115200

   You should land in a busybox shell. The LCD backlight should also
   come on and show the kernel boot log on tty0.

5. From the shell, useful first checks:

       dmesg | grep -iE 'sun4i-drm|panel|rtl8723|axp|backlight'
       cat /proc/device-tree/model
       modprobe r8723bs && iw dev

## Sanity-check before NAND install

Don't even think about writing NAND until:

- The board enumerates as USB serial+ethernet reliably across 3 cold
  power cycles.
- `dmesg` shows no `*** late init failed ***` or panics.
- WiFi at least probes (the staging driver doesn't need /lib/firmware
  blobs, but it needs the SDIO bus to come up cleanly).
- The LCD shows a console.

If any of those fail, fix it in the FEL flow first — every reboot is
free in FEL mode, every NAND write is not.

## NAND install (TODO)

Procedure not yet written. The outline is:

1. `nand-part` to partition the NAND (boot0, boot1, UBI).
2. `sunxi-fel write` the SPL+u-boot at the boot0 offsets.
3. From a FEL-booted Linux, `ubiformat` the rootfs partition and
   `ubimkvol`/`ubinize` a UBIFS root.
4. Update `bootcmd` in U-Boot to `ubi part UBI && ubifsmount ubi:rootfs &&
   ubifsload 0x42000000 zImage && ubifsload 0x43000000 chip.dtb && bootz
   0x42000000 - 0x43000000`.

The NAND parameters (page size, OOB, ECC strength) must come from the
runtime ONFI probe in dmesg, not from guessing.
