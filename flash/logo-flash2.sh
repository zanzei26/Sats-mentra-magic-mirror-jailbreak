#!/system/bin/sh
# Replace the two boot-logo bitmaps (adjacent 226 sectors inside the boot partition's resource image).
# Aborts unless the current region equals the original; verifies the written region AND the whole 32 MiB boot partition.
B=/dev/block/by-name/boot
read start count old new fullnew fullold < /data/local/tmp/region_patch.txt
F=/data/local/tmp/region_new.bin
echo 3 > /proc/sys/vm/drop_caches
CUR=$(dd if=$B bs=512 skip=$start count=$count 2>/dev/null | sha256sum | cut -d' ' -f1)
if [ "$CUR" = "$new" ]; then echo "already patched"; exit 0; fi
[ "$CUR" = "$old" ] || { echo "ABORT: region is not the expected original ($CUR)"; exit 1; }
[ "$(dd if=$B bs=1M 2>/dev/null | sha256sum | cut -d' ' -f1)" = "$fullold" ] || { echo "ABORT: whole boot partition differs from the backup"; exit 1; }
[ "$(sha256sum $F | cut -d' ' -f1)" = "$new" ] || { echo "ABORT: patch file hash"; exit 1; }
dd if=$F of=$B bs=512 seek=$start count=$count 2>/dev/null
sync; echo 3 > /proc/sys/vm/drop_caches
CUR=$(dd if=$B bs=512 skip=$start count=$count 2>/dev/null | sha256sum | cut -d' ' -f1)
[ "$CUR" = "$new" ] && echo "region written and verified" || { echo "REGION_VERIFY_FAILED"; exit 1; }
FULL=$(dd if=$B bs=1M 2>/dev/null | sha256sum | cut -d' ' -f1)
[ "$FULL" = "$fullnew" ] && echo "whole boot partition = original + logo patch only: PATCH_OK" || echo "WHOLE_PARTITION_MISMATCH ($FULL)"
