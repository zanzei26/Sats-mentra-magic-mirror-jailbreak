#!/system/bin/sh
# Opens the camera app for the "Camera" button on the wall-panel dashboard. Home Assistant calls it over adb
# (script.speil_kamera -> androidtv.adb_command "sh /data/local/camera_open.sh"). See docs/home-assistant-wall-panel.md, section 5.
# One-shot: it starts nothing that keeps running and it is not part of the boot hook.
#
#   sh /data/local/camera_open.sh [seconds]
#
# The camera app (AOSP Camera2, com.android.camera2) has a built-in countdown timer (off / 3 s / 10 s) that the shutter button starts, with
# beeps and large numbers; the timer button is in the options bar of the preview and the choice is remembered in the app's preferences
# (key pref_camera_countdown_duration_key). Without an argument this script keeps whatever was chosen and only sets 10 s when the app has
# no value yet; with an argument (0, 3 or 10) it sets that value.
#
# It also undoes one trap in the app's settings: on the stock vendor library the photo size 2592x1944 (the webcam's maximum) crashes the
# external camera HAL when a picture is taken (libjpeg over-read, the height is not a multiple of 16). If that size is selected and the
# patched HAL library is not mounted, the size is set back to 2048x1536.
T="$1"
case "$T" in ""|0|3|10) ;; *) T="" ;; esac
PKG=com.android.camera2
PREF=/data/data/$PKG/shared_prefs/${PKG}_preferences.xml
TMP=/data/local/tmp/camera_prefs.new

# Stop the app first: it keeps its preferences in memory and would write them back over our change, and a fresh start always
# lands in the live preview (not in the photo strip or the settings screen of the previous visit).
am force-stop $PKG

if [ -f "$PREF" ]; then
  NEED_T=0; [ -n "$T" ] && NEED_T=1
  grep -q 'pref_camera_countdown_duration_key' "$PREF" || NEED_T=1
  NEED_S=0
  # (not needed when the patched HAL library is mounted, see tools/patch_external_camera_hal.py)
  if ! grep -q ' /vendor/lib/camera.device@3.4-external-impl.so ' /proc/mounts; then
    grep -q 'name="pref_camera_picturesize_front_key">2592x1944<' "$PREF" && NEED_S=1
  fi
  if [ "$NEED_T" = 1 ] || [ "$NEED_S" = 1 ]; then
    [ -n "$T" ] || T=10
    awk -v t="$T" -v nt="$NEED_T" -v ns="$NEED_S" '
      nt == 1 && /pref_camera_countdown_duration_key/ { next }
      ns == 1 && /pref_camera_picturesize_front_key/ { print "    <string name=\"pref_camera_picturesize_front_key\">2048x1536</string>"; next }
      nt == 1 && /<\/map>/ { printf "    <string name=\"pref_camera_countdown_duration_key\">%s</string>\n", t }
      { print }' "$PREF" > "$TMP"
    # rewrite the existing file in place (no rename), so owner and SELinux label stay as the app expects
    if [ -s "$TMP" ] && grep -q '</map>' "$TMP"; then cat "$TMP" > "$PREF"; fi
    rm -f "$TMP"
  fi
fi

am start -n $PKG/com.android.camera.CameraActivity -a android.media.action.STILL_IMAGE_CAMERA > /dev/null 2>&1
