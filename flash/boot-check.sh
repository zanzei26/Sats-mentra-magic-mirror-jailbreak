#!/system/bin/sh
echo "release=$(getprop ro.build.version.release) sdk=$(getprop ro.build.version.sdk) build=$(getprop ro.build.display.id)"
echo "boot_completed=$(getprop sys.boot_completed) uptime=$(cut -d' ' -f1 /proc/uptime)  bootreason=$(getprop sys.boot.reason)"
echo "--- root / system / vendor / data mounts ---"
grep -E ' / | /system | /vendor | /odm | /data | /metadata ' /proc/mounts | cut -c1-140
echo "--- dm devices ---"
for d in /sys/block/dm-*; do echo "$(basename $d): $(cat $d/dm/name) $(cat $d/size)"; done
echo "--- gsi_tool / dsu ---"
gsi_tool status 2>&1 | tail -3
echo "--- my services ---"
getprop init.svc.tw_daemon; getprop init.svc.mirror_setup; getprop init.svc.dbg_log; getprop init.svc.dbg_logcat
echo "--- mpp_service node ---"
ls -l /dev/mpp_service
echo "--- /metadata/dbg/boot.txt ---"
cat /metadata/dbg/boot.txt 2>&1 | tail -8
echo "--- chrome flag file / defaults ---"
cat /data/local/chrome-command-line 2>&1; ls -la /data/local/.mirror_defaults_done 2>&1
settings get system screen_off_timeout 2>&1
echo "--- device owner / mentra ---"
pm list packages 2>/dev/null | grep -i -E 'mentra|sats' ; dumpsys device_policy 2>/dev/null | grep -i -E 'Device Owner' | head -2
echo "--- lpdump head ---"
lpdump 2>&1 | grep -E 'Name:|linear' | head -12
