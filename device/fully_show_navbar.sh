#!/system/bin/sh
# Fully Kiosk Browser hides the system bars by default; with the Launcher3 taskbar this also hides the volume shortcut.
# Turn on its "Show Navigation Bar" setting by editing only that one preference (Fully must be stopped while we do it).
# Only the value of showNavigationBar is touched. The backup stays ON THE DEVICE (it may contain the remote-admin password / PIN).
P=/data/data/de.ozerov.fully/shared_prefs/de.ozerov.fully_preferences.xml
am force-stop de.ozerov.fully
sleep 1
cp $P /data/local/tmp/fully_preferences.xml.bak
chmod 600 /data/local/tmp/fully_preferences.xml.bak
sed -i 's|<boolean name="showNavigationBar" value="false" />|<boolean name="showNavigationBar" value="true" />|' $P
echo "now: $(grep -o '<boolean name="showNavigationBar"[^>]*>' $P)"
OWNER=$(stat -c '%u:%g' /data/data/de.ozerov.fully/shared_prefs)
chown $OWNER $P
chmod 660 $P
restorecon $P 2>/dev/null
am start -n de.ozerov.fully/de.ozerov.fully.FullyActivity > /dev/null 2>&1
