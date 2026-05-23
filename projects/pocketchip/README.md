# pocketchip — Next Thing Co. PocketCHIP

> Part of the [**second-boot**](../../) series: pulling forgotten
> hardware out of the parts bin and getting it running on current
> software. This is entry #1.

Bringing the Next Thing Co. **PocketCHIP** back from the drawer of dead
electronics with a current mainline Linux kernel, current U-Boot, and a
properly small OpenWrt userspace you can actually `ssh` into.

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

| Component               | State            | Notes                                    |
|-------------------------|------------------|-------------------------------------------|
| Mainline U-Boot         | ✓ working        | `CHIP_defconfig` + custom `bootcmd`       |
| Mainline kernel 6.6/6.12| ✓ working        | sunxi target + PocketCHIP DT              |
| FEL boot                | ✓ working        | board enumerates, U-Boot runs, kernel runs|
| USB gadget (ACM + ECM)  | ✓ working        | confirmed by USB enumeration on host      |
| USB ethernet            | ✓ working        | `ping 10.43.43.1` ≈ 0.4 ms RTT            |
| AXP209 PMIC             | ✓ working        | mainline driver, regulators correct       |
| RTL8723BS WiFi+BT       | ⚙  driver loads  | needs runtime verification                |
| LCD panel + backlight   | ⚙  DT in place   | needs visual confirmation                 |
| Resistive touchscreen   | ⚙  driver loads  | needs runtime verification                |
| Audio (sun4i-codec)     | ⚙  driver loads  | needs runtime verification                |
| Keyboard matrix         | ✗ unsupported    | per-revision wiring TBD                   |
| NAND install pipeline   | ⚙  scripted      | scripts + procedure ready, see [docs/nand-install.md](docs/nand-install.md). Pending RAM-boot sign-off before first run. |

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
    20-build-uboot-nand.sh  NAND-resident u-boot (UBI bootcmd)
    21-pack-spl-for-nand.sh wrap SPL with sunxi NAND ECC layout
    22-build-ubi-image.sh   pack kernel + rootfs into UBI volumes
    23-flash-nand.sh        run ON the booted PocketCHIP to flash NAND
    fel-boot.sh          drive sunxi-fel to RAM-boot our build
    fel-boot-openwrt.sh  same, but for the OpenWrt initramfs image
  tools/
    sunxi-tools/         git submodule, pinned to v1.4.2
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
