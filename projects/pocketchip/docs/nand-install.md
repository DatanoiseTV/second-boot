# NAND install procedure

This is the destructive flow that puts our build into the PocketCHIP's
on-board 4 GiB NAND. **Do not run this until the FEL-RAM boot is solid
across at least three cold power cycles.** Every step here can be
recovered from via FEL — short the `FEL` pad to GND while applying
power and the BootROM reappears on USB — but you should still treat the
write-side commands as "I meant to do this", not "let me see what
happens".

## Overview

Allwinner SoCs boot in this order:

1. **BROM** (mask ROM, immutable): looks for SPL at four NAND offsets:
   `0x000000`, `0x100000`, `0x200000`, `0x300000`. The four copies are a
   bad-block insurance policy; the BROM walks the list until it finds
   one that ECCs cleanly.
2. **SPL** (`sunxi-spl.bin`, ECC-wrapped): initialises DDR, loads U-Boot
   proper from a higher NAND address into DRAM, jumps to it.
3. **U-Boot proper**: reads our `bootcmd` from NAND env, walks a UBI
   volume to find the kernel, kernel takes over.

## NAND layout we use

| Offset     | Size  | Contents                               |
|------------|-------|----------------------------------------|
| `0x0000000`| 1 MiB | SPL copy #1 (boot0, ECC-wrapped)        |
| `0x0400000`| 1 MiB | SPL copy #2                             |
| `0x0800000`| 1 MiB | SPL copy #3 + env area (`0x800000`)    |
| `0x0c00000`| 1 MiB | SPL copy #4                             |
| `0x1000000`| 4 MiB | U-Boot proper (primary)                 |
| `0x1400000`| 4 MiB | U-Boot proper (backup copy)             |
| `0x2000000`| rest  | UBI MTD partition: boot + rootfs volumes|

The UBI partition holds two named volumes:

| Volume   | Size      | Filesystem | Contents                              |
|----------|-----------|------------|---------------------------------------|
| `boot`   |  32 MiB   | UBIFS      | `zImage`, DTB, `extlinux.conf`        |
| `rootfs` |  ~ rest   | UBIFS / squashfs over UBI | OpenWrt root         |

UBI on top of NAND is the standard modern layout: it handles
wear-levelling, bad-block management and CRC across the volumes for us.
Doing raw partition-style flashing on MLC NAND without UBI is asking
for a bad time.

## Steps

### 1. Build the NAND-targeted U-Boot

The RAM-boot U-Boot built by `02-build-uboot.sh` is wrong for NAND:
its `bootcmd` boots from RAM at a fixed address. The NAND variant has
a different `bootcmd` that reads from UBI.

```
ssh syso@<build-host> bash projects/pocketchip/scripts/20-build-uboot-nand.sh
```

Output: `artifacts/uboot-nand/u-boot-sunxi-with-spl.bin`,
`artifacts/uboot-nand/u-boot.bin`, `artifacts/uboot-nand/sunxi-spl.bin`.

### 2. Wrap the SPL with NAND ECC

The BROM expects SPL pages laid out with the controller's ECC bytes
interleaved into the OOB. `sunxi-nand-image-builder` (from sunxi-tools)
does this:

```
ssh syso@<build-host> bash projects/pocketchip/scripts/21-pack-spl-for-nand.sh
```

This produces `sunxi-spl-nand.bin`. The defaults (page=16K, oob=1280,
ECC=40/1024, eraseblock=4M) match the Hynix MLC NAND that shipped on
most C.H.I.P. revisions. If your board's NAND is different, override
via env vars; the dmesg of a FEL-booted Linux tells you what to set.

### 3. Build the UBI image

```
ssh syso@<build-host> bash projects/pocketchip/scripts/22-build-ubi-image.sh
```

Reads the kernel artifacts and the OpenWrt squashfs rootfs, packs them
into a single `pocketchip.ubi` file that will sit at NAND offset
`0x2000000`.

### 4. Pull artifacts back to the Mac

```
mkdir -p artifacts/uboot-nand artifacts/ubi
scp syso@<build-host>:pocketchip-build/artifacts/uboot-nand/{sunxi-spl-nand.bin,u-boot.bin} artifacts/uboot-nand/
scp syso@<build-host>:pocketchip-build/artifacts/ubi/pocketchip.ubi             artifacts/ubi/
```

### 5. FEL-boot the OpenWrt RAM image

Same as the smoke test — see [flashing.md](flashing.md). After this
the PocketCHIP is reachable as `root@10.43.43.1`.

### 6. Push artifacts to the running PocketCHIP

```
scp -O artifacts/uboot-nand/sunxi-spl-nand.bin   root@10.43.43.1:/tmp/
scp -O artifacts/uboot-nand/u-boot.bin           root@10.43.43.1:/tmp/
scp -O artifacts/ubi/pocketchip.ubi              root@10.43.43.1:/tmp/
scp -O projects/pocketchip/scripts/23-flash-nand.sh  root@10.43.43.1:/tmp/
```

### 7. Run the flash

```
ssh root@10.43.43.1 'sh /tmp/23-flash-nand.sh'
```

This writes SPL copies, U-Boot copies, and the UBI image. It does **not**
reboot; verify the writes by inspecting dmesg + `ubinfo` before
power-cycling.

### 8. Cold-boot from NAND

Power off the PocketCHIP. Apply power without the FEL pad shorted.
The BROM should find the SPL we just wrote, jump to U-Boot, U-Boot
should run our `bootcmd`, the kernel should come up exactly like the
FEL RAM-boot did. Look for `/dev/cu.usbmodem*` and the USB-ethernet
interface on the Mac as confirmation.

## Recovery

If the board doesn't boot:

1. Short the FEL pad to GND while applying power.
2. `sunxi-fel ver` on the host should show the Allwinner USB device.
3. `bash scripts/fel-boot-openwrt.sh` to get back to a working RAM
   system.
4. Inspect what went wrong (`dmesg | grep -iE 'mtd|nand|ubi'`,
   `ubinfo /dev/ubi0`), fix, re-flash the broken pieces only.

You can also re-erase NAND completely from a FEL-RAM system:

```
flash_erase /dev/mtd0 0 0       # erases the entire chip
```

…then start over from step 5. FEL is permanent; you can't lose it.
