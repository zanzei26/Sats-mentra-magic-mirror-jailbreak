#!/system/bin/sh
# usage: sf-latency.sh chrome|fully|<plain layer substring> <seconds>
# passive: reads SurfaceFlinger's per-frame present times for ONE layer and prints fps + interval distribution
# (>20 ms = a missed 60 Hz slot, >34 ms = two missed slots)
MODE="$1"; SEC=${2:-20}
case "$MODE" in
  chrome) NAME=$(dumpsys SurfaceFlinger --list 2>/dev/null | grep 'com.chrome.beta/ChromeChildSurface' | head -1) ;;
  fully)  NAME=$(dumpsys SurfaceFlinger --list 2>/dev/null | grep -E '^de.ozerov.fully/de.ozerov.fully.FullyActivity#' | tail -1) ;;
  *)      NAME=$(dumpsys SurfaceFlinger --list 2>/dev/null | grep -F "$MODE" | head -1) ;;
esac
[ -z "$NAME" ] && { echo "no layer for '$MODE'"; exit 1; }
echo "layer: $NAME"
OUT=/data/local/tmp/sfl.txt; : > $OUT
T0=$(awk '{printf "%.0f", $1*1000000000}' /proc/uptime)
i=0
while [ $i -lt $SEC ]; do
  dumpsys SurfaceFlinger --latency "$NAME" 2>/dev/null | awk -v t0=$T0 'NR>1 && $2>0 && $2<9000000000000000000 && $2+0>=t0+0 {print $2}' >> $OUT
  i=$((i+1)); sleep 1
done
sort -n -u $OUT > $OUT.u
awk 'NR>1 { d=($1-p)/1e6; if (d<500) print d } { p=$1 }' $OUT.u > $OUT.d
N=$(wc -l < $OUT.u); M=$(wc -l < $OUT.d)
if [ "$M" -lt 3 ]; then echo "only $N presented frames in the window"; rm -f $OUT $OUT.u $OUT.d; exit 0; fi
sort -n $OUT.d > $OUT.s
pk() { sed -n "$(( ($M * $1 + 99) / 100 ))p" $OUT.s; }
SPAN=$(awk 'NR==1{a=$1} {b=$1} END{printf "%.1f", (b-a)/1e9}' $OUT.u)
echo "frames $N over ${SPAN} s"
echo "interval ms: p50 $(pk 50)  p90 $(pk 90)  p95 $(pk 95)  p99 $(pk 99)  max $(tail -1 $OUT.s)"
awk '{ if ($1>20) a++; if ($1>34) b++; if ($1>50) c++ } END { printf "missed slots: >20 ms %d (%.1f%%)   >34 ms %d (%.1f%%)   >50 ms %d (%.1f%%)   of %d intervals\n", a, 100*a/NR, b, 100*b/NR, c, 100*c/NR, NR }' $OUT.d
rm -f $OUT $OUT.u $OUT.d $OUT.s
