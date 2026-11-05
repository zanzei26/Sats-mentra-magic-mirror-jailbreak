#!/system/bin/sh
# AOT-compile the apps on the touch path (they are only 'verify'-compiled on this GSI, i.e. interpreted + JIT).
echo "start: $(date +%H:%M:%S)"
for p in com.android.settings com.android.launcher3 de.ozerov.fully com.android.camera2 com.android.systemui; do
  s=$(date +%s)
  r=$(cmd package compile -m speed -f $p 2>&1 | tail -1)
  echo "$p: $r ($(( $(date +%s) - s )) s)"
done
echo "done: $(date +%H:%M:%S)"
for p in com.android.settings com.android.launcher3 de.ozerov.fully com.android.camera2 com.android.systemui; do
  echo "$p: $(dumpsys package dexopt 2>/dev/null | grep -A2 "\[$p\]" | grep -m1 -E 'status=' | sed 's/^ *//')"
done
echo "free /data: $(df /data | tail -1 | tr -s ' ' | cut -d' ' -f4) KB"
