#!/bin/bash
# Step 2: apply the SATS-mirror debug/compat modifications to the writable Android 13 system image.
set -e
W=/root/a13; N=$W/system_new.img; M=$W/new; LOG=$W/mod.log
exec > >(tee $LOG) 2>&1
mkdir -p $M
mountpoint -q $M && umount $M
mount -o loop $N $M
echo "mounted rw: $(mount | grep a13/new | cut -c1-80)"
S=$M/system

python3 - <<'PY'
import os, re
M = '/root/a13/new/system'
O = '/root/a13/orig/system'

def label_of(p):
    try: return os.getxattr(p, 'security.selinux')
    except OSError as e: return None

# --- 0. sanity: xattrs survived the copy? ---
for rel in ('build.prop', 'bin/sh', 'etc/selinux/plat_sepolicy.cil', 'etc/init/logd.rc'):
    a, b = label_of(f'{O}/{rel}'), label_of(f'{M}/{rel}')
    print(f'xattr {rel}: orig={a} new={b} equal={a == b}')
    assert a == b and a is not None, f'security.selinux lost for {rel}'

# --- 1. build.prop: root adb without auth + graphics compat (edit IN PLACE: keeps inode + xattrs) ---
bp = f'{M}/build.prop'
txt = open(bp, 'r').read()
repl = {'ro.secure=1': 'ro.secure=0', 'ro.adb.secure=1': 'ro.adb.secure=0', 'ro.debuggable=0': 'ro.debuggable=1'}
for a, b in repl.items():
    assert a in txt, f'missing {a}'
    txt = txt.replace(a, b)
if not txt.endswith('\n'): txt += '\n'
txt += '''
# --- SATS mirror: RK3399 (vendor Android 10, kernel 4.19) + Android 13 GSI tweaks ---
persist.sys.usb.config=adb
service.adb.root=1
# Mali-T860 r18p0 EGL: avoid partial-update/buffer-age paths that crashed HWUI (EGL_BAD_ACCESS) on Android 11
debug.hwui.use_partial_updates=false
debug.hwui.use_buffer_age=false
# Android 13 defaults to Skia RenderEngine; use the legacy GLES backend with the old Mali blob
debug.renderengine.backend=gles
'''
fd = os.open(bp, os.O_WRONLY | os.O_TRUNC)
os.write(fd, txt.encode()); os.close(fd)
print('build.prop edited; ro.* lines now:')
for l in txt.splitlines():
    if re.match(r'ro\.(secure|adb\.secure|debuggable)=', l): print('   ', l)

# --- 2. debug helper script + init rc ---
sh = r'''#!/system/bin/sh
# Added for the SATS mirror GSI test. Logs to /metadata/dbg (unencrypted: readable from the stock Android 10 afterwards).
D=/metadata/dbg
mkdir -p $D 2>/dev/null
chmod 777 $D 2>/dev/null
echo "dbg_log started: $(date) uptime $(cut -d' ' -f1 /proc/uptime)" >> $D/boot.txt
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
# kernel log snapshot (init prints service crashes/exits here)
( while :; do dmesg > $D/dmesg.new 2>/dev/null && mv -f $D/dmesg.new $D/dmesg.txt; sleep 3; done ) &
# service / boot state snapshot
( while :; do { date; getprop | grep -E 'init\.svc|sys\.boot|ro\.boottime|vold|apex|keystore|crypto|sys\.usb'; } > $D/props.new 2>/dev/null && mv -f $D/props.new $D/props.txt; sleep 8; done ) &
# watchdog: not booted after 240 s => save state and warm-reboot (DSU one-shot => back to stock Android 10)
( sleep 240
  if [ "$(getprop sys.boot_completed)" != "1" ]; then
    echo "WATCHDOG: boot_completed != 1 after 240 s -> rebooting ($(date))" >> $D/boot.txt
    dmesg > $D/dmesg_final.txt 2>/dev/null
    ls -la /data/tombstones 2>/dev/null | head -5 >> $D/boot.txt
    sync
    setprop sys.powerctl reboot,dbgwd
    sleep 20
    echo b > /proc/sysrq-trigger
  else
    echo "boot_completed=1 at $(date); watchdog idle" >> $D/boot.txt
  fi ) &
wait
'''
rc = '''# Added for the SATS mirror GSI test (debug logging + boot watchdog)
on early-init
    mkdir /metadata/dbg 0777 root system
    start dbg_log

on property:logd.ready=true
    start dbg_logcat

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
'''
lab = label_of(f'{O}/etc/init/logd.rc')
for path, content, mode in ((f'{M}/etc/dbg_log.sh', sh, 0o755), (f'{M}/etc/init/zz_dbg.rc', rc, 0o644)):
    with open(path, 'w') as f: f.write(content)
    os.chmod(path, mode); os.chown(path, 0, 0)
    os.setxattr(path, 'security.selinux', lab)       # same label as other system rc/etc files
    print('created', path.replace(M, ''), oct(mode), 'label', lab)

# --- 3. SELinux: make every type permissive (denials logged, not enforced) ---
types = []
def collect(path):
    for l in open(path, errors='ignore'):
        m = re.match(r'^\(type\s+([A-Za-z0-9_]+)\)\s*$', l.strip())
        if m: types.append(m.group(1))
cil = f'{M}/etc/selinux/plat_sepolicy.cil'
collect(cil)
n_plat = len(types)
vend = '/path/to/vendor_sepolicy.cil'
collect(vend)
types = list(dict.fromkeys(types))
print(f'types: plat={n_plat}, plat+vendor unique={len(types)}')
add = '\n; --- SATS mirror: all types permissive (debug bring-up on vendor Android 10) ---\n' + ''.join(f'(typepermissive {t})\n' for t in types)
txt = open(cil).read()
assert 'typepermissive' not in txt
if not txt.endswith('\n'): add = '\n' + add
fd = os.open(cil, os.O_WRONLY | os.O_APPEND)
os.write(fd, add.encode()); os.close(fd)
print('plat_sepolicy.cil: appended', len(types), 'typepermissive lines; xattr kept:', label_of(cil) == label_of(f'{O}/etc/selinux/plat_sepolicy.cil'))
PY

echo "--- verify ---"
grep -c typepermissive $S/etc/selinux/plat_sepolicy.cil
grep -E '^ro\.(secure|adb\.secure|debuggable)=' $S/build.prop
tail -8 $S/build.prop
ls -laZ $S/etc/dbg_log.sh $S/etc/init/zz_dbg.rc 2>/dev/null || ls -la $S/etc/dbg_log.sh $S/etc/init/zz_dbg.rc
sync
umount $M
echo "--- fsck after modifications ---"
e2fsck -fn $N | tail -3
ls -la $N
echo "MOD DONE"
