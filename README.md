# pocketchip-ng

Modern mainline Linux for the Next Thing Co. **PocketCHIP** (and the bare
C.H.I.P. board). Targets a current Debian userspace on a recent mainline
kernel, with hardware support for the LCD, touchscreen, keyboard matrix,
audio, WiFi/BT and AXP209 PMIC.

## Hardware target

| Block       | Part                                                   |
|-------------|--------------------------------------------------------|
| SoC         | Allwinner R8 (single-core Cortex-A8 @ 1 GHz, sun5i)    |
| RAM         | 512 MiB DDR3                                            |
| Storage     | 4 GiB SLC/MLC NAND, microSD slot (PocketCHIP daughter) |
| PMIC        | AXP209                                                  |
| WiFi/BT     | Realtek RTL8723BS (SDIO)                                |
| Display     | 4.3" 480x272 parallel RGB, resistive touch              |
| Input       | Tactile keyboard matrix, on-screen GPIO buttons         |
| Audio       | sun4i-codec via AXP209, 3.5 mm jack with detect         |
| Battery     | LiPo via AXP209 charger                                 |

## Boot strategy

1. **SD-card first.** Non-destructive, recoverable. Holds U-Boot SPL, kernel
   image, device tree, extlinux config, and rootfs.
2. **NAND install** is a follow-up. Only attempted once SD boot is verified
   end-to-end, because a bad NAND write means recovery via FEL mode.

## Components

- **U-Boot** — mainline, `chip_defconfig` (and `pocketchip` variants once we
  branch a board defconfig). Built as `u-boot-sunxi-with-spl.bin` and dd'd
  to sector 16 (8 KiB offset) of the SD card.
- **Linux** — mainline 6.x. Device tree based on `sun5i-r8-chip.dts` plus a
  PocketCHIP overlay carrying LCD panel timings, keyboard matrix, backlight
  PWM, and audio routing.
- **Rootfs** — Debian trixie armhf via `debootstrap --foreign` + qemu second
  stage. Minimal X stack (xserver-xorg + openbox), NetworkManager, alsa,
  bluez. No desktop bloat; this is a 512 MiB box.
- **Firmware** — RTL8723BS NIC/config/firmware blobs from linux-firmware,
  staged into `/lib/firmware/`.

## Build layout

```
pocketchip-ng/
  configs/         u-boot & kernel fragment configs, package lists
  dts/             out-of-tree DT overlays for PocketCHIP peripherals
  patches/         local patches against u-boot and linux trees
  scripts/         build orchestration, rootfs, image assembly
  sources/         external trees (cloned on build host, gitignored)
  artifacts/       built bootloader, kernel, image (gitignored)
  docs/            FEL recovery, flashing, hardware notes
```

External sources (U-Boot, Linux, sunxi-tools, linux-firmware) are fetched on
the build host and pinned by commit in `scripts/versions.env` — they are
not vendored into this repo to keep it small, but the pinned hashes give
reproducibility.

## Building

Cross-build is done on a Linux host (Debian recommended, armhf toolchain).
The macOS workstation only runs orchestration scripts over SSH.

```
scripts/01-fetch-sources.sh    # clone & checkout pinned versions on build host
scripts/02-build-uboot.sh
scripts/03-build-kernel.sh
scripts/04-make-rootfs.sh
scripts/05-assemble-image.sh
```

Each script is idempotent. Re-running step N skips earlier finished steps
unless `FORCE=1` is set.

## Flashing

See [docs/flashing.md](docs/flashing.md) for the full procedure, including
**FEL mode recovery** (jumper FEL pin to GND, plug USB — host sees an
Allwinner USB device and can push U-Boot into RAM).

## Status

Work in progress. Tracked in `TODO.md` (gitignored, local notes only).

## License

This repository contains build glue and configuration only. Upstream
components (U-Boot, Linux, Debian) retain their own licenses.
