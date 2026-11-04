#!/bin/bash
# Final modifications for the PERMANENT Android 13 system image of the SATS mirror, then shrink the filesystem.
set -e
W=/root/a13; N=$W/system_new.img; M=$W/new; LOG=$W/final.log
exec > >(tee $LOG) 2>&1
mkdir -p $M
mountpoint -q $M && umount $M
cp --sparse=always $N $W/system_new_before_final.img     # keep the previous (DSU-tested) image
mount -o loop $N $M
S=$M/system
echo "mounted rw: $(mount | grep a13/new | cut -c1-80)"

python3 - <<'PY'
import os
M = '/root/a13/new/system'
O = '/root/a13/orig/system'
lab = os.getxattr(f'{O}/etc/init/logd.rc', 'security.selinux')
print('label for new rc/sh files:', lab)

dbg_log = r'''#!/system/bin/sh
# SATS mirror: boot diagnostics -> /metadata/dbg (unencrypted, survives a data wipe). Bounded: only the first ~10 min after boot.
D=/metadata/dbg
mkdir -p $D 2>/dev/null
chmod 777 $D 2>/dev/null
echo "dbg_log started: $(date) uptime $(cut -d' ' -f1 /proc/uptime)" >> $D/boot.txt
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
( i=0; while [ $i -lt 100 ]; do dmesg > $D/dmesg.new 2>/dev/null && mv -f $D/dmesg.new $D/dmesg.txt; i=$((i+1)); sleep 6; done ) &
( i=0; while [ $i -lt 75 ]; do { date; getprop | grep -E 'init\.svc|sys\.boot|ro\.boottime|vold|apex|keystore|crypto|sys\.usb'; } > $D/props.new 2>/dev/null && mv -f $D/props.new $D/props.txt; i=$((i+1)); sleep 8; done ) &
# Watchdog: boot not completed after 420 s => save state and reboot, at most 2 times in a row (then it stays out of the way).
( sleep 420
  n=$(cat $D/wdcount 2>/dev/null); [ -z "$n" ] && n=0
  if [ "$(getprop sys.boot_completed)" != "1" ]; then
    if [ "$n" -lt 2 ]; then
      echo $((n+1)) > $D/wdcount
      echo "WATCHDOG #$((n+1)): boot_completed != 1 after 420 s -> rebooting ($(date))" >> $D/boot.txt
      dmesg > $D/dmesg_final.txt 2>/dev/null
      sync
      setprop sys.powerctl reboot,dbgwd
      sleep 20
      echo b > /proc/sysrq-trigger
    else
      echo "WATCHDOG disabled: already rebooted $n times ($(date))" >> $D/boot.txt
    fi
  else
    echo 0 > $D/wdcount
    echo "boot_completed=1 at $(date); watchdog idle" >> $D/boot.txt
  fi ) &
wait
'''

rc = '''# SATS mirror (RK3399, vendor Android 10 + Android 13 GSI): diagnostics, hardware-decoder block, touch-to-wake, defaults
on early-init
    mkdir /metadata/dbg 0777 root system
    start dbg_log

on property:logd.ready=true
    start dbg_logcat

# The vendor VPU driver (rkvdec/mpp, kernel 4.19) page-faults the whole kernel on VP9 and renders garbage with the
# Android 13 framework. Make the node unreachable for everything except root, so media falls back to software decoding.
on boot
    chmod 0000 /dev/mpp_service
    chown root root /dev/mpp_service

on property:sys.boot_completed=1
    start mirror_setup
    start tw_daemon

service dbg_log /system/bin/sh /system/etc/dbg_log.sh
    user root
    group root system log shell
    seclabel u:r:shell:s0
    oneshot
    disabled

service dbg_logcat /system/bin/logcat -b all -v threadtime -f /metadata/dbg/logcat.txt -r 1024 -n 3
    user root
    group root system log shell
    seclabel u:r:shell:s0
    oneshot
    disabled

service mirror_setup /system/bin/sh /system/etc/mirror_setup.sh
    user root
    group root system shell
    seclabel u:r:shell:s0
    oneshot
    disabled

service tw_daemon /system/bin/sh /system/etc/tw_daemon.sh
    user root
    group root input shell
    seclabel u:r:shell:s0
    disabled
'''

mirror_setup = r'''#!/system/bin/sh
# SATS mirror: runs once per boot after boot_completed (idempotent).
chmod 0000 /dev/mpp_service 2>/dev/null
mkdir -p /data/local 2>/dev/null
# Chrome: no hardware video decode (honoured because the build is debuggable)
echo '_ --disable-accelerated-video-decode' > /data/local/chrome-command-line
chmod 0644 /data/local/chrome-command-line
# First boot only: mirror-friendly defaults (screen off after 60 s, no lock screen)
F=/data/local/.mirror_defaults_done
if [ ! -e $F ]; then
  settings put system screen_off_timeout 60000
  settings put global stay_on_while_plugged_in 0
  cmd lock_settings set-disabled true >/dev/null 2>&1
  touch $F
fi
# stop the boot-time log capture after 10 minutes (avoids constant flash writes)
sleep 600
stop dbg_logcat
'''

tw = open('/path/to/work/tw_daemon.sh').read()

for rel, content, mode in (('etc/dbg_log.sh', dbg_log, 0o755), ('etc/init/zz_dbg.rc', rc, 0o644),
                           ('etc/mirror_setup.sh', mirror_setup, 0o755), ('etc/tw_daemon.sh', tw, 0o755)):
    p = f'{M}/{rel}'
    if os.path.exists(p):
        fd = os.open(p, os.O_WRONLY | os.O_TRUNC); os.write(fd, content.encode()); os.close(fd)
    else:
        with open(p, 'w') as f: f.write(content)
    os.chmod(p, mode); os.chown(p, 0, 0); os.setxattr(p, 'security.selinux', lab)
    print('wrote', rel, oct(mode))
PY

echo "--- verify ---"
ls -la $S/etc/dbg_log.sh $S/etc/mirror_setup.sh $S/etc/tw_daemon.sh $S/etc/init/zz_dbg.rc
getfattr -n security.selinux $S/etc/mirror_setup.sh $S/etc/init/zz_dbg.rc 2>&1 | grep -E 'file:|selinux' || true
grep -E '^(ro\.secure|ro\.adb\.secure|ro\.debuggable|persist\.sys\.usb\.config|service\.adb\.root)=' $S/build.prop
grep -c typepermissive $S/etc/selinux/plat_sepolicy.cil
sync
umount $M

echo "--- fsck + shrink ---"
e2fsck -fy $N | tail -3 || true
resize2fs -M $N 2>&1 | tail -2
e2fsck -fn $N | tail -2
BS=4096
BLK=$(dumpe2fs -h $N 2>/dev/null | awk -F: '/^Block count/{gsub(/ /,"",$2); print $2}')
echo "minimum block count: $BLK  ($((BLK*BS/1024/1024)) MiB)"
# add ~64 MiB headroom, then truncate the file to exactly the filesystem size
NEWBLK=$((BLK + 16384))
resize2fs $N ${NEWBLK} 2>&1 | tail -2 || true
FINBLK=$(dumpe2fs -h $N 2>/dev/null | awk -F: '/^Block count/{gsub(/ /,"",$2); print $2}')
echo "final filesystem block count: $FINBLK"
truncate -s $((FINBLK*BS)) $N
e2fsck -fn $N | tail -2
dumpe2fs -h $N 2>/dev/null | grep -E 'Filesystem features|Block count|Free blocks|Inode count'
ls -l $N
echo "sectors (512 B): $(( $(stat -c %s $N) / 512 ))"
echo "FINAL DONE"
