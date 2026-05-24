# pocketchip — Next Thing Co. PocketCHIP

> Part of the [**second-boot**](../../) series: pulling forgotten
> hardware out of the parts bin and getting it running on current
> software. This is entry #1.

Bringing the Next Thing Co. **PocketCHIP** back from the drawer of dead
electronics with a current mainline Linux kernel, current U-Boot, and a
properly small OpenWrt userspace you can actually `ssh` into.

<img width="682" height="570" alt="Screenshot 2026-05-23 at 18 04 11" src="https://github.com/user-attachments/assets/92390693-9f4e-4263-a3a2-da09dac01d55" />

---

## The device

A C.H.I.P. computer (Allwinner R8 — a `sun5i` rebadge of the A13, single
Cortex-A8, 512 MiB DDR3, 4 GiB SLC NAND, RTL8723BS WiFi+BT, AXP209 PMIC)
mounted on the PocketCHIP daughterboard that adds a 4.3" 480×272 LCD
with resistive touch, a tactile QWERTY membrane keyboard, a LiPo battery
and a USB-A host receptacle.

Next Thing Co. went bankrupt in 2018. Their kernel was a 3.4 BSP fork.
The original Debian image was Jessie. Years of bitrot later, the parts
bin version still boots its original firmware — and is otherwise
inert.

This repository takes that hardware to **mainline Linux 6.x** plus
mainline U-Boot, with first-class hardware support for the bits anyone
actually needs from a handheld: networking (USB-gadget Ethernet + WiFi),
SSH, the LCD, the resistive touch, audio, and the AXP209's power
management. Keyboard matrix is the last loose end and will land once we
verify the per-revision daughterboard wiring with a multimeter rather
than guess.

## The approach

No reflashing the NAND blind. The Allwinner BootROM exposes a
permanent USB recovery mode (FEL) — short a single pad to ground while
applying power and the SoC enumerates as a USB device willing to accept
code into RAM. We use that for everything until the build is solid:

```
host ──[USB FEL]─► sunxi-fel ──► SPL → DDR init → U-Boot proper
                                        │
                              [bootcmd "bootz ..."]
                                        ▼
                              kernel → initramfs → /sbin/init
                                        │
                              [USB gadget composite via configfs]
                                        ▼
                          host sees a CDC-ACM serial console
                          host sees a CDC-ECM ethernet → 10.43.43.1
                                        ▼
                              ssh root@10.43.43.1
```

NAND writes happen only after the RAM boot is reproducible across cold
power cycles. FEL stays available even when NAND is wiped, so the box
remains recoverable forever short of physical damage to the SoC.

## Status

**Full, writable OpenWrt 25.12.4 now boots persistently from NAND** and is
reachable over SSH via the USB-ethernet gadget — survives cold power cycles, no
host/FEL needed. squashfs `/rom` + ubifs `/overlay` (≈1.7 GiB writable) on a
slc-mode UBI.

| Component               | State            | Notes                                    |
|-------------------------|------------------|-------------------------------------------|
| OpenWrt on NAND (root)  | ✓ working        | writable squashfs+overlay on slc-mode UBI, persistent |
| NAND boot chain         | ✓ working        | legacy NTC u-boot (see below) — mainline SPL mis-detects this MLC |
| Mainline kernel 6.12    | ✓ working        | sunxi target + our DT, boots from NAND    |
| FEL boot                | ✓ working        | board enumerates, U-Boot runs, kernel runs|
| USB gadget (ACM + ECM)  | ✓ working        | CDC-ACM serial + CDC-ECM ethernet (g_cdc) |
| USB ethernet            | ✓ working        | `ssh root@10.43.43.1`, board runs DHCP    |
| AXP209 PMIC             | ✓ working        | mainline driver, regulators correct       |
| RTL8723BS WiFi+BT       | ⚙  driver binds  | SDIO chip detected, `phy0` registered, but the vendor driver's cfg80211 can't create a station iface (`iw interface add` → -95) and reads MAC 00:00:00:00:00:00 — not associating. Not a firmware issue (fw is built into the driver). |
| LCD / touch / audio     | n/a (bare C.H.I.P.) | test unit is a bare C.H.I.P. — no screen/keyboard/touch hardware to verify against |
| Keyboard matrix         | n/a (bare C.H.I.P.) | PocketCHIP-only peripheral; absent on the test unit |

### How OpenWrt gets onto the NAND (the working method)

The CHIP's Toshiba **TC58TEG5DCLTA00 MLC NAND** is the whole challenge. Two
hard-won facts drove the working pipeline:

1. **Mainline U-Boot's sunxi NAND SPL mis-detects this MLC's boot-slot
   geometry**, so it can't reliably load U-Boot from NAND. The fix is the
   **legacy Next Thing Co. U-Boot** (`Project-chip-crumbs/CHIP-u-boot`,
   `production-mlc-pc`) plus an SPL-geometry-hardcode patch and a `slc-mode`
   read/write patch. boot0 is a 256-page full-eraseblock image.
2. **U-Boot's `nand write.slc-mode` and the kernel's slc-mode NAND read use
   incompatible ECC**, so a UBI rootfs written from U-Boot is unreadable by the
   kernel (`ubi_io_read: -74 (ECC error)` → root-mount panic). The UBI rootfs
   must be written **by a running kernel** so write/read ECC match.

Pipeline:

- **Boot region** (legacy boot0 ×2, legacy resident U-Boot @0x800000, OpenWrt
  `zImage` @0x1000000, dtb @0x2000000) is flashed slc-mode from a FEL session
  (`scripts/37-fel-flash-openwrt.sh`).
- **UBI rootfs** is installed by FEL-booting OpenWrt's *own* initramfs into RAM
  (`scripts/40-fel-boot-openwrt-initramfs.sh`, using an `ENV_IS_NOWHERE` "felboot"
  U-Boot so a polluted NAND env can't hijack boot), then over SSH:
  `ubiformat /dev/mtd5 -f <factory.ubi>`. Reboot → the resident U-Boot loads
  kernel+dtb (`nand read.slc-mode` + `bootz`, bootargs `ubi.mtd=UBI
  ubi.block=0,rootfs root=/dev/ubiblock0_0 rootfstype=squashfs`) → OpenWrt.

NAND layout: `spl`(0)/`spl-backup`(0x400000)/`uboot`(0x800000)/`env`(0xc00000)/
`boot`(0x1000000, 64 MiB raw kernel+dtb)/`UBI`(0x5000000, slc-mode rootfs).

## Layout

```
projects/pocketchip/
  README.md              this file
  LICENSE                MIT
  .gitignore
  configs/
    kernel/              kernel config fragment (over sunxi_defconfig)
    uboot/               u-boot config fragment (over CHIP_defconfig)
    rootfs/              authorized_keys, package lists
  dts/
    sun5i-r8-chip-pocketchip-ng.dts   PocketCHIP daughterboard DT
  openwrt/
    target/              Device entry + DTS for OpenWrt's sunxi target
    files/               files/ overlay (uci-defaults, dropbear keys,
                                          usb-gadget init.d service)
  scripts/
    versions.env         pinned upstream commit refs
    01-fetch-sources.sh  clone u-boot, linux, sunxi-tools, firmware
    02-build-uboot.sh    CHIP_defconfig + our bootcmd fragment
    03-build-kernel.sh   sunxi_defconfig + our fragment + DTS
    06-build-initramfs.sh  busybox smoke-test initramfs
    10-build-openwrt.sh  install DTS, append Device entry, build
    11-pull-openwrt-image.sh  scp artifacts back to the host
    20-23,30-35         earlier NAND-flash experiments (mainline/macromorgan
                        u-boot variants) — superseded by the legacy path
    36-fel-flash-legacy.sh        flash legacy boot0+u-boot+kernel (RAM-rootfs)
    37-fel-flash-openwrt.sh       flash the OpenWrt boot region (boot0, u-boot,
                                  zImage, dtb) slc-mode via FEL
    38-fel-catch-flash-openwrt.sh aggressive FEL-catch wrapper for 37
    40-fel-boot-openwrt-initramfs.sh  FEL-boot OpenWrt initramfs into RAM
                                  (to ubiformat the UBI rootfs from the kernel)
    fel-boot.sh          drive sunxi-fel to RAM-boot our build
    fel-boot-openwrt.sh  same, but for the OpenWrt initramfs image
  uboot-legacy/          legacy NTC CHIP-u-boot build scripts + patches
    build-one-variant.sh   build a variant with a given bootcmd
    build-felboot.sh       ENV_IS_NOWHERE felboot variant (console=ttyS0)
    make-boot0.sh          256-page MLC boot0 image
    patches/               slc-mode + SPL geometry + spectre patches
  tools/
    sunxi-tools/         git submodule (fel.c patched: SPL_MAX_VERSION 1→3)
  docs/
    flashing.md          FEL recovery procedure + smoke test
```

External trees (u-boot, linux, openwrt, linux-firmware) are not vendored
— they're cloned on the build host and pinned by ref in
`scripts/versions.env`. Reproducibility is the same; the repo stays
small.

## Building

You need a Linux box with `gcc-arm-linux-gnueabihf`, `u-boot-tools`,
`device-tree-compiler`, and ~5 GiB of disk for the OpenWrt build tree.
The build is driven by SSH from a Mac (or anything), but the actual
cross-compilation runs on the build host.

```
./scripts/01-fetch-sources.sh      # on the build host
./scripts/02-build-uboot.sh
./scripts/10-build-openwrt.sh      # OpenWrt path; long-running
./scripts/11-pull-openwrt-image.sh # back on the Mac
./scripts/fel-boot-openwrt.sh      # board in FEL, plug USB
```

When the kernel finishes coming up, `ssh root@10.43.43.1` works using
any key listed in the GitHub user whose authorized_keys we baked in.

## FEL — the safety net

The single most important thing to internalize about Allwinner devices:
**you cannot brick them by software alone**. Hold the `FEL` pad to GND
while power is applied, plug USB into a host, run `sunxi-fel ver`, and
the chip is back. Knowing this is the difference between treating an
embedded board as a black box and treating it as a workbench.

## License

MIT — series-wide. See [LICENSE](../../LICENSE) at the repo root.
Upstream components (U-Boot, Linux, OpenWrt) retain their own licenses.

## More entries in the series

See the top-level [`README.md`](../../) for the series intro, the
project index, and how to donate dead hardware for future entries.
