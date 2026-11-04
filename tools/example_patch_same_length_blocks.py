#!/usr/bin/env python3
"""Same-length, single-block in-place patches of /system files inside the final image (inode untouched).
Writes patch blocks + an info file for the device-side patch script, and patches the master image as well."""
import hashlib, subprocess, json
IMG = '/root/a13/system_new.img'
OUT = '/path/to/perm-flash'

RC = '''# SATS mirror (RK3399 + Android 13 GSI on Android 10 vendor): diagnostics, VPU access control, touch-to-wake
on early-init
    mkdir /metadata/dbg 0777 root system
    start dbg_log

on property:logd.ready=true
    start dbg_logcat

# VPU video decode crashes the kernel (VP9) / renders garbage on A13: keep codecs out.
# Only the camera provider (webcam MJPEG decode) may open the node.
on boot
    chmod 0600 /dev/mpp_service
    chown cameraserver root /dev/mpp_service

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

SETUP = '''#!/system/bin/sh
chmod 0600 /dev/mpp_service 2>/dev/null
mkdir -p /data/local 2>/dev/null
echo '_ --disable-accelerated-video-decode' > /data/local/chrome-command-line
chmod 0644 /data/local/chrome-command-line
F=/data/local/.mirror_defaults_done
if [ ! -e $F ]; then
  settings put system screen_off_timeout 60000
  settings put global stay_on_while_plugged_in 0
  cmd lock_settings set-disabled true >/dev/null 2>&1
  touch $F
fi
[ -f /data/local/mirror_local.sh ] && sh /data/local/mirror_local.sh
sleep 600
stop dbg_logcat
'''


def dbg(args):
    return subprocess.run(['debugfs', '-R', args, IMG], capture_output=True, text=True).stdout


def fit(content, size):
    assert len(content.encode()) <= size - 3, (len(content.encode()), size)
    pad = size - len(content.encode())
    # pad with a trailing comment line so the file keeps exactly its old length
    return content + '#' * (pad - 1) + '\n' if pad > 1 else content + '\n'


info = []
for path, new, name in (('system/etc/init/zz_dbg.rc', RC, 'rc'), ('system/etc/mirror_setup.sh', SETUP, 'setup')):
    blk = int(dbg(f'bmap {path} 0').strip().split()[-1])
    assert 'not' in dbg(f'bmap {path} 1').lower() or dbg(f'bmap {path} 1').strip().split()[-1] == '0', 'file spans >1 block'
    size = int(dbg(f'stat {path}').split('Size:')[1].split()[0])
    with open(IMG, 'rb') as f:
        f.seek(blk * 4096); old_block = f.read(4096)
    newtxt = fit(new, size)
    assert len(newtxt.encode()) == size
    new_block = newtxt.encode() + old_block[size:]
    off = blk * 4096
    sup = (2048 * 512 + off) if off < 1834952 * 512 else (2930688 * 512 + off - 1834952 * 512)
    assert sup % 4096 == 0
    fn = f'{OUT}/patch_{name}.bin'
    open(fn, 'wb').write(new_block)
    with open(IMG, 'r+b') as f:
        f.seek(blk * 4096); f.write(new_block)
    info.append(dict(name=name, path=path, size=size, super_block=sup // 4096,
                     old=hashlib.sha256(old_block).hexdigest(), new=hashlib.sha256(new_block).hexdigest()))
    print(name, path, 'size', size, 'fs block', blk, 'super 4K block', sup // 4096)
json.dump(info, open(f'{OUT}/patch_files.json', 'w'), indent=1)
open(f'{OUT}/patch_files.txt', 'w').write(''.join(f"{i['name']} {i['super_block']} {i['old']} {i['new']}\n" for i in info))
print(open(f'{OUT}/patch_files.txt').read())
