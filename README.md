# second-boot

A series of write-ups about pulling forgotten, abandoned, or
manufacturer-orphaned hardware out of the parts bin and getting it
running on **current** software again — mainline kernels, current
bootloaders, sensible userspaces, full hardware support — and doing it
in a way someone else can reproduce.

> *second-boot*: the bootloader you write the second time around — when
> the vendor is gone, the BSP is dead, and the only thing keeping the
> board alive is the recovery path nobody at the original company
> thought you would use.

Each entry is a self-contained subdirectory under [`projects/`](projects/).
Same approach across the series: figure out the recovery / FEL / SWD /
TFTP / serial-bootloader path first, then climb up the stack until the
device is actually useful.

## Projects

| Project | Device | SoC | Status | Notes |
|---|---|---|---|---|
| [`pocketchip`](projects/pocketchip/) | Next Thing Co. PocketCHIP (2017) | Allwinner R8 (sun5i, Cortex-A8) | **bringup** | Mainline U-Boot, mainline kernel, OpenWrt rootfs, FEL recovery, USB-gadget SSH over OTG. |

(More entries will land here. Open an issue if you'd like to suggest a
target, or read on for how to donate hardware.)

## The approach

Every project in this repo follows the same playbook:

1. **Find the recovery path before doing anything else.**
   On Allwinner SoCs that's FEL (USB BootROM); on Rockchip it's RKDevTool /
   Maskrom; on NXP it's SDP; on Espressif it's the ROM bootloader UART;
   on classic Intel it's the BIOS/UEFI shell. *Knowing how to unbrick is
   the prerequisite to permission to brick.*
2. **Boot a current upstream U-Boot from RAM via the recovery path.**
   No writes to the device's storage yet. Iterate freely.
3. **Boot a current mainline kernel + minimal initramfs into RAM.**
   Validate enough hardware to know we have a real system: clocks, RAM
   training, USB, network.
4. **Layer a real userspace on top.**
   OpenWrt for hacky-tinker handhelds (small, ssh-default, sane
   defaults); Debian when the device needs a real glibc desktop.
5. **Only then, commit to the device's persistent storage.**
   NAND, eMMC, SPI flash, mSATA — whatever it is, you write to it once
   you've already booted the same image from RAM successfully across
   several cold power cycles.
6. **Document the whole thing in the project's README** so someone with
   the same device in their drawer can reproduce it end to end.

## Folder layout

```
second-boot/
  README.md             this file — series-level
  LICENSE
  projects/
    pocketchip/
      README.md         device-specific writeup
      configs/          kernel + bootloader config fragments
      dts/              device-tree additions
      openwrt/          rootfs overlays, package selection
      docs/             flashing / recovery procedures
      scripts/          driven build pipeline
      tools/            git submodules (e.g. sunxi-tools)
    <future-project>/
      ...
```

Each project subdirectory is roughly self-contained: it has its own
build pipeline, its own pinned upstream refs, and its own docs.
Cross-project sharing is fine when it makes sense (a shared bring-up
checklist, say), but the bias is toward "you can read just one
subdirectory and know what's going on."

## Device donations welcome

If you have a dead, obsolete, or just-forgotten piece of hardware you'd
like to see resurrected, **send it.**

Strong candidates:
- Single-board computers whose vendor went under (Next Thing,
  Hardkernel pre-Odroid, original Beagleboard variants, etc.)
- Handhelds with custom Linux (GPD, GP2X, Pandora, old smartphones)
- Networking gear that's still hardware-capable but software-abandoned
- E-readers with proprietary firmware
- Anything with an Allwinner / Rockchip / TI / NXP / Espressif SoC
  that hasn't seen a software update in three or more years

Open an issue with what you have, DM
[@DatanoiseTV](https://github.com/DatanoiseTV), or ship it cold —
contact channels in the GitHub profile. Interesting devices become
entries; the boring ones at least get tested and returned if requested.

## License

All build glue, scripts, configs, and DTS additions in this repository
are **MIT** licensed — see [LICENSE](LICENSE). Upstream components used
during builds (U-Boot, Linux, OpenWrt, Debian) retain their own
licenses.

## Follow

[github.com/DatanoiseTV](https://github.com/DatanoiseTV)
