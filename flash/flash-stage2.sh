#!/system/bin/sh
# STAGE 2: write the new LP metadata (first 1 MiB of super) and verify it.
SUPER=/dev/block/by-name/super
NEW=/data/local/tmp/super_head_new.bin
EXP=ef43d6fb000dd59455447c419325ec25c1ea045ece56f40682d9597661775eb0
[ "$(sha256sum $NEW | cut -d' ' -f1)" = "$EXP" ] || { echo "ABORT: metadata file hash mismatch"; exit 1; }
[ "$(stat -c %s $NEW)" = "1048576" ] || { echo "ABORT: metadata file size"; exit 1; }
dd if=$NEW of=$SUPER bs=4096 count=256 || { echo "ABORT: dd failed"; exit 1; }
sync
echo 3 > /proc/sys/vm/drop_caches
H=$(dd if=$SUPER bs=4096 count=256 2>/dev/null | sha256sum | cut -d' ' -f1)
echo "readback head: $H"
[ "$H" = "$EXP" ] && echo "STAGE2_HASH_OK" || { echo "STAGE2_HASH_MISMATCH"; exit 1; }
echo "--- lpdump of the REAL super partition now ---"
lpdump 2>&1 | sed -n '1,45p'
