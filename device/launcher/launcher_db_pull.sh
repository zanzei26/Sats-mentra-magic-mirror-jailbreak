#!/system/bin/sh
# Stop the launcher and copy its database to /data/local/tmp/l3/ (then: adb pull /data/local/tmp/l3/<db> .)
# Adjust DB if your grid differs (ls /data/data/com.android.launcher3/databases/).
DB=launcher_6_by_5.db
mkdir -p /data/local/tmp/l3
am force-stop com.android.launcher3
sleep 1
cp /data/data/com.android.launcher3/databases/$DB /data/local/tmp/l3/$DB
ls -ln /data/data/com.android.launcher3/databases/$DB
