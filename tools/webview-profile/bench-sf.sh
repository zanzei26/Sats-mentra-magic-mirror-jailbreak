#!/system/bin/sh
# 3D house orbit test with SurfaceFlinger present times: ~21 s of horizontal drags, no taps
F=de.ozerov.fully
S0=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat)
sh /data/local/tmp/sf-latency.sh fully 21 > /data/local/tmp/sf.out 2>&1 &
i=0
while [ $i -lt 19 ]; do
  input swipe 200 900 880 960 500
  input swipe 880 960 200 900 500
  i=$((i+1))
done
wait
S1=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat)
cat /data/local/tmp/sf.out
echo "$S0 $S1" | awk '{ tot=$3-$1; idle=$4-$2; printf "cpu busy %.1f %%\n", 100*(tot-idle)/tot }'
