#!/system/bin/sh
# Patch single 4K blocks of the installed system. Aborts per block unless the current content matches the expected old hash.
S=/dev/block/by-name/super
echo 3 > /proc/sys/vm/drop_caches
while read name idx old new; do
  F=/data/local/tmp/patch_$name.bin
  CUR=$(dd if=$S bs=4096 skip=$idx count=1 2>/dev/null | sha256sum | cut -d' ' -f1)
  if [ "$CUR" = "$new" ]; then echo "$name: already patched"; continue; fi
  [ "$CUR" = "$old" ] || { echo "$name: ABORT, block is not the expected old content ($CUR)"; continue; }
  [ "$(sha256sum $F | cut -d' ' -f1)" = "$new" ] || { echo "$name: ABORT, patch file hash"; continue; }
  dd if=$F of=$S bs=4096 seek=$idx count=1 2>/dev/null
  sync; echo 3 > /proc/sys/vm/drop_caches
  CUR=$(dd if=$S bs=4096 skip=$idx count=1 2>/dev/null | sha256sum | cut -d' ' -f1)
  [ "$CUR" = "$new" ] && echo "$name: PATCH_OK" || echo "$name: PATCH_VERIFY_FAILED"
done < /data/local/tmp/patch_files.txt
