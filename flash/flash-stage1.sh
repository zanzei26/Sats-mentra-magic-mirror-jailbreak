#!/system/bin/sh
# STAGE 1 of the permanent Android 13 install: write system extents into super and verify them by hash.
# Order: extent B (free tail) first, then extent A (the old stock system region). LP metadata is written in stage 2.
SUPER=/dev/block/by-name/super
IMG=/data/local/tmp/system_final.img
LOG=/data/local/tmp/flash-stage1.log
exec > $LOG 2>&1
say() { echo "[$(date +%H:%M:%S)] $*"; }
die() { say "ABORT: $*"; echo "STAGE1_FAILED" ; exit 1; }

EXP_IMG=40ad372086fe195334988d7b892a6c3d56ffb75ede22a912e5ae808450aeabd4
EXP_A=8f836b60c3f1fac12e628c816e55c10ab0ea3fec91ee53e91ab240b76dacd3dd
EXP_B=5958c46d7f00501905443740846fef0c049be4370f299b3b181a2caf4a9d7bae
EXP_HEAD_LIVE=1114605a4e2ec83a24666ec799602f106686f4d956e9c0d68c37a512aa8b37e7

say "pre-checks"
[ "$(sha256sum $IMG | cut -d' ' -f1)" = "$EXP_IMG" ] || die "image hash mismatch"
[ "$(dd if=$SUPER bs=4096 count=256 2>/dev/null | sha256sum | cut -d' ' -f1)" = "$EXP_HEAD_LIVE" ] || die "live LP metadata is not what I expected"
[ "$(blockdev --getsize64 $SUPER)" = "3263168512" ] || die "super size unexpected"
say "pre-checks ok"

say "WRITE extent B: image 4K-blocks 229369..608679 -> super 4K-block 366336 (sector 2930688), 379311 blocks"
dd if=$IMG of=$SUPER bs=4096 skip=229369 seek=366336 count=379311 || die "dd B failed"
sync
echo 3 > /proc/sys/vm/drop_caches
H=$(dd if=$SUPER bs=4096 skip=366336 count=379311 2>/dev/null | sha256sum | cut -d' ' -f1)
say "extent B readback: $H"
[ "$H" = "$EXP_B" ] || die "extent B verify FAILED"
say "extent B verified"

say "WRITE extent A: image 4K-blocks 0..229368 -> super 4K-block 256 (sector 2048), 229369 blocks  [stock system is overwritten from here]"
dd if=$IMG of=$SUPER bs=4096 skip=0 seek=256 count=229369 || die "dd A failed"
sync
echo 3 > /proc/sys/vm/drop_caches
H=$(dd if=$SUPER bs=4096 skip=256 count=229369 2>/dev/null | sha256sum | cut -d' ' -f1)
say "extent A readback: $H"
[ "$H" = "$EXP_A" ] || die "extent A verify FAILED"
say "extent A verified"

say "dm-linear mapping test with the NEW layout (what first-stage init will build from the metadata)"
dmctl delete sysnew >/dev/null 2>&1
dmctl create sysnew -ro linear 0 1834952 $SUPER 2048 linear 1834952 3034488 $SUPER 2930688 || die "dmctl create failed"
P=$(dmctl getpath sysnew); say "mapped at $P"
echo 3 > /proc/sys/vm/drop_caches
H=$(sha256sum $P | cut -d' ' -f1)
say "mapped device sha256: $H"
[ "$H" = "$EXP_IMG" ] || { dmctl delete sysnew; die "mapped device hash mismatch"; }
mkdir -p /mnt/sysnew
mount -t ext4 -o ro $P /mnt/sysnew && { say "mounted ro OK:"; ls /mnt/sysnew | tr '\n' ' '; echo; ls /mnt/sysnew/system | head -5 | tr '\n' ' '; echo; grep -E '^ro.build.version.release=' /mnt/sysnew/system/build.prop; umount /mnt/sysnew; } || say "WARN: ro mount test failed"
dmctl delete sysnew
say "STAGE1_OK"
echo STAGE1_OK
