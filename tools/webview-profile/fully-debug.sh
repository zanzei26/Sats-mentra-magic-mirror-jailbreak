#!/system/bin/sh
# usage: fully-debug.sh on|off   - flip Fully's "webviewDebugging" preference and restart Fully (backup kept once)
P=/data/data/de.ozerov.fully/shared_prefs/de.ozerov.fully_preferences.xml
[ -f $P.bak-20261105 ] || cp -p $P $P.bak-20261105
case "$1" in on) V=true;; off) V=false;; *) echo "usage: on|off"; exit 1;; esac
am force-stop de.ozerov.fully
sleep 1
sed -i "s/<boolean name=\"webviewDebugging\" value=\"[a-z]*\" \/>/<boolean name=\"webviewDebugging\" value=\"$V\" \/>/" $P
grep webviewDebugging $P
am start -n de.ozerov.fully/.FullyActivity >/dev/null 2>&1
sleep 10
input keyevent KEYCODE_WAKEUP
echo "top=$(dumpsys activity activities 2>/dev/null | grep -m1 topResumedActivity | sed 's/.*u0 //' | cut -d' ' -f1) pid=$(pidof de.ozerov.fully)"
grep -a devtools /proc/net/unix | head -3
