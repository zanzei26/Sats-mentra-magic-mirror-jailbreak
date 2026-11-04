# Checksums (from the one unit this was done on)

These are **examples to show what was verified**, not values to compare against your own device. Your eMMC, partition contents and images will differ.

## What was compared, and how

| Item | SHA-256 |
|---|---|
| Full eMMC backup (61 865 984 000 bytes) | `be343fac2962722ae337c7938e8ec01e05f6cb39a4a207b8d057ef532bd70889` |
| Original `system` extent (super sectors 2048…1 837 000, from the backup) | `4eb7b0f4740927489f4c83cfecf7e2db1317db5b9fa9fa8a02a48e95f152a9f9` (identical on the live device before writing) |
| Rollback slice = super sectors 0…1 837 000 (LP metadata + original system) | `56b6f425da724552fc7451f82268f41a601d4808df88aada6c0764a37ef8fdef` |
| Original `vendor` region (467 312 sectors @ 1 837 056) | `fa787a934af30645d3803675358562d1b83ae4948c98f00268ed257a68f102c4` |
| Original `product` region (580 864 sectors @ 2 306 048) | `edbecbdb3702e7ca17ea3e818914d36be90621a29ef51e520857087092756882` |
| Original `odm` region (40 408 sectors @ 2 887 680) | `634edcb2aea229b0194d243d9c7981856ac5ab3d185dbb17a940cec6b8868c5f` |
| New `super` metadata head (first 1 MiB) | `ef43d6fb000dd59455447c419325ec25c1ea045ece56f40682d9597661775eb0` |
| Android 13 `system` image as first written (2 493 153 280 B) | `40ad372086fe195334988d7b892a6c3d56ffb75ede22a912e5ae808450aeabd4` |
| …extent A piece (1 834 952 sectors) | `8f836b60c3f1fac12e628c816e55c10ab0ea3fec91ee53e91ab240b76dacd3dd` |
| …extent B piece (3 034 488 sectors) | `5958c46d7f00501905443740846fef0c049be4370f299b3b181a2caf4a9d7bae` |

(The installed system has since been changed by a handful of same-length single-block patches; see the report.)

## Layout that was written (512-byte sectors, `super` starts at eMMC LBA 0x150c00)

| Partition | Extents |
|---|---|
| `system` | 1 834 952 @ 2048, then 3 034 488 @ 2 930 688 (total 4 869 440 = 2377.7 MiB) |
| `vendor` | 467 312 @ 1 837 056 (unchanged) |
| `product` | 580 864 @ 2 306 048 (unchanged; skipped at boot via the GSI's `skip_mount.cfg`) |
| `odm` | 40 408 @ 2 887 680 (unchanged) |

Group `rockchip_dynamic_partitions`: 5 958 024 sectors used of a 3 258 974 208-byte maximum.

## Verification chain used before the first reboot

1. Own parser reads the original and the live metadata and agrees with the device's `lpdump`.
2. The device's own AOSP `lpdump <file>` parses the new metadata and prints the expected layout.
3. Extents written one at a time, each read back and hashed.
4. A `dm-linear` device with the new table was created (`dmctl create`), hashed end-to-end (== image) and mounted read-only.
5. Metadata written, read back, `lpdump` on the real `super`.
6. `vendor`/`product`/`odm` regions re-hashed: byte-identical to the backup.
