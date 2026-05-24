# Modern u-boot (v2025.01) for C.H.I.P. NAND — config notes

Base: u-boot v2025.01, `CHIP_defconfig` (which ships with NO NAND).

## Kconfig additions (via scripts/config, on top of CHIP_defconfig)
    CONFIG_CMD_NAND=y
    CONFIG_CMD_NAND_TRIMFFS=y
    CONFIG_MTD=y
    CONFIG_DM_MTD=y
    CONFIG_MTD_RAW_NAND=y
    CONFIG_NAND_SUNXI=y
    CONFIG_CMD_MTD=y
    CONFIG_MTD_UBI=y
    CONFIG_CMD_UBI=y
    CONFIG_SYS_NAND_PAGE_SIZE=0x4000     # 16384
    CONFIG_SYS_NAND_BLOCK_SIZE=0x400000  # 4 MiB
    CONFIG_SYS_NAND_OOBSIZE=0x500        # 1280
    CONFIG_SYS_NAND_5_ADDR_CYCLE=y
    CONFIG_SYS_MAX_NAND_DEVICE=1

## Source patch (0001-...patch)
- nand_toshiba.c: set NAND_NEED_SCRAMBLING for Toshiba MLC (matches Linux
  nand_toshiba tc58teg5dclta00_init). THIS is what makes u-boot's NAND ECC
  bit-compatible with the 6.12 kernel (proven: u-boot write -> kernel read clean,
  ecc_failures=0).
- sun5i-r8-chip.dts: enable &nfc (controller + pins + nand@0); mainline leaves it off.

## Verified
v2025.01 + above: `nand info` shows Toshiba TC58TEG5DCLTA00, BCH-40/1024; a page
written by u-boot reads back byte-exact in the kernel with 0 ecc_failures.

## NOT yet done (for full NAND boot)
Port the legacy SPL boot0 patches (uboot-legacy/patches/pocketchip-spl-toshiba-mlc
+ -slc-uboot) to v2025.01 drivers/mtd/nand/raw/sunxi_nand_spl.c so the BootROM can
load the modern SPL from this MLC; build the 256-page boot0; flash the modern stack.
