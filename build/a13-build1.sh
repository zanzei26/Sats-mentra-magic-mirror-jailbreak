#!/bin/bash
# Step 1: create a clean, writable (non-shared-blocks) ext4 copy of the Android 13 GSI system image.
set -e
W=/root/a13; O=$W/orig; N=$W/system_new.img; LOG=$W/build1.log
exec > >(tee $LOG) 2>&1
mkdir -p $O
mountpoint -q $O || mount -o loop,ro $W/system_orig.img $O
echo "orig mounted: $(mount | grep a13/orig | cut -c1-80)"
rm -f $N
truncate -s 3072M $N
echo "--- mke2fs (features chosen for Linux 4.19 BSP kernel: no orphan_file/metadata_csum/64bit/flex_bg) ---"
date
mke2fs -q -t ext4 -b 4096 -I 256 -m 0 -L system \
  -O ^has_journal,^resize_inode,^64bit,^metadata_csum,^orphan_file,^flex_bg,uninit_bg \
  -d $O $N
date
echo "--- fsck (read-only) ---"
e2fsck -fn $N | tail -4
echo "--- features of new image ---"
dumpe2fs -h $N 2>/dev/null | grep -E 'Filesystem features|Block count|Free blocks|Inode count|Block size'
echo "BUILD1 DONE"
