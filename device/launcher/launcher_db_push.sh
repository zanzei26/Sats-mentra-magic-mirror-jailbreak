#!/system/bin/sh
# Put an edited launcher database back (launcher stopped), fix owner/mode, restart the launcher.
# Expects the edited file at /data/local/tmp/l3/<DB>.new  (adb push it there first).
DB=launcher_6_by_5.db
D=/data/data/com.android.launcher3/databases
OWNER=$(stat -c '%u:%g' $D)
am force-stop com.android.launcher3
sleep 1
cp /data/local/tmp/l3/$DB.new $D/$DB
rm -f $D/$DB-journal $D/$DB-wal $D/$DB-shm
chown $OWNER $D/$DB
chmod 660 $D/$DB
restorecon $D/$DB 2>/dev/null
input keyevent 224
input keyevent 3
