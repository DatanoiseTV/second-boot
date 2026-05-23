# NAND backup & restore (original NTC firmware)

Before modifying the PocketCHIP's NAND we take a full raw backup of every
MTD partition **including OOB** (the ECC/spare bytes), so the original
Next Thing Co. firmware can be byte-for-byte restored.

## What's backed up

Dumps live in `artifacts/nand-backup/` (gitignored -- they're multi-GB
and device-specific). Each is `nanddump -o` output: raw page data with
the OOB area interleaved, exactly as on the chip.

| File | Partition | Size (with OOB) | Contents |
|------|-----------|-----------------|----------|
| `mtd0-SPL.nanddump`        | mtd0 SPL        | ~4.3 MiB | boot0 / SPL |
| `mtd1-SPL.backup.nanddump` | mtd1 SPL.backup | ~4.3 MiB | SPL copy |
| `mtd2-U-Boot.nanddump`     | mtd2 U-Boot     | ~4.3 MiB | u-boot proper |
| `mtd3-env.nanddump`        | mtd3 env        | ~4.3 MiB | u-boot environment |
| `mtd4-UBI.nanddump`        | mtd4 rootfs     | ~4.4 GiB | UBI (Debian 8 rootfs) |

NAND geometry (Toshiba TC58TEG5DCLTA00): page 16 KiB, OOB 1280 B,
erase block 4 MiB. With OOB, each page is 16384+1280 = 17664 bytes on
disk, so the dump is ~7.8% larger than the nominal partition size.

## Restore (from a FEL-booted or running Linux with mtd-utils)

The dumps include OOB, so restore with raw, no-ECC writes -- the ECC
bytes are already in the data:

```sh
# Per partition, e.g. to restore u-boot (mtd2):
sudo flash_erase /dev/mtd2 0 0
sudo nandwrite -o -n -p /dev/mtd2 mtd2-U-Boot.nanddump
#         -o = write OOB from the file
#         -n = no internal ECC calc (OOB already has it)
#         -p = pad to page size
```

Restore order for a full recovery: mtd0, mtd1, mtd2, mtd3, then mtd4.
After restoring mtd0-3 the board boots the original u-boot again; mtd4
brings back the original Debian rootfs.

## If the board won't boot at all

The Allwinner BootROM FEL mode is immutable and always available: short
the FEL pad to GND while applying power, then use `sunxi-fel` to load a
u-boot into RAM, and from that u-boot (or a FEL-booted Linux with
mtd-utils) run the restore commands above. NAND writes cannot remove
FEL, so the board is always recoverable.

## Verifying a backup

`nanddump` of a partition twice should match (modulo bad-block reads).
We checksum each dump (`md5`) right after pulling it; keep those
checksums with the backup.
