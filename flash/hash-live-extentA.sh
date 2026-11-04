#!/system/bin/sh
# Hash the CURRENT stock system extent (super sectors 2048..1837000) on the mirror, to compare with the backup.
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
dd if=/dev/block/by-name/super bs=4096 skip=256 count=229369 2>/dev/null | sha256sum
