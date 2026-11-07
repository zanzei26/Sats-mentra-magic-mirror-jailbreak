#!/system/bin/sh
# Local tuning for the mirror. Lives in /data/local/ and runs at every boot (hook in mirror_setup.sh). Edit freely over adb.
# GPU (Mali-T860): do not idle at 200 MHz - the UI is redrawn in full every frame (partial updates are off for Mali compatibility)
echo 400000000 > /sys/class/devfreq/ff9a0000.gpu/min_freq
# CPU floor: A53 little 816 MHz, A72 big 816 MHz (max stays 1416 / 1800 MHz, governor interactive)
echo 816000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
echo 816000 > /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq
# UI scale and animations are normal Android settings (persist by themselves):
#   wm density 180        # panel default is 240; "wm density reset" undoes it
#   settings put global window_animation_scale 0.5   (same for transition_animation_scale, animator_duration_scale)
# USB camera microphone: /vendor/etc/usb_audio_policy_configuration.xml leaves the USB input profile dynamic, and Android then
# asks the webcam for 24-bit mono, which it does not have (ALSA "cannot set hw params"), so apps record silence. Overlay a copy
# of the file with an explicit 16-bit 48 kHz profile (see docs/doorbell-camera-performance.md, section 4) and restart audioserver.
# Only once per boot (never re-run by hand while an app records: re-registering the USB device under an active recorder makes
# audioserver abort in a crash loop). Do NOT force-stop apps here: force-stopping the Companion app makes Android drop it as the
# default assistant (voice_interaction_service / assistant settings).
if [ -f /data/local/usb_audio_policy_configuration.xml ] && ! grep -q usb_audio_policy /proc/mounts; then
  mount -o bind /data/local/usb_audio_policy_configuration.xml /vendor/etc/usb_audio_policy_configuration.xml
  setprop ctl.restart audioserver
fi

# adb over Wi-Fi must survive reboots (port 5555); the persist property is read by adbd at start.
setprop persist.adb.tcp.port 5555
if [ "$(getprop service.adb.tcp.port)" != "5555" ]; then
  setprop service.adb.tcp.port 5555
  setprop ctl.restart adbd
fi

# Keep the Companion app as the default assistant (on-device wake word). Android drops the setting when the voice
# service dies or after some reboots; only restore it when it is empty, after boot has completed.
(
  n=0
  while [ "$(getprop sys.boot_completed)" != "1" ] && [ $n -lt 120 ]; do sleep 2; n=$((n+1)); done
  sleep 45
  cur="$(settings get secure voice_interaction_service)"
  if [ -z "$cur" ] || [ "$cur" = "null" ]; then
    if pm list packages 2>/dev/null | grep -q io.homeassistant.companion.android; then
      VIS=io.homeassistant.companion.android/.assist.service.AssistVoiceInteractionService
      settings put secure voice_interaction_service $VIS
      settings put secure assistant $VIS
    fi
  fi
) > /dev/null 2>&1 &

# Self-healing for the Companion app's wake-word recorder on the USB camera microphone (see docs/home-assistant-wall-panel.md,
# section 2). Starts one watchdog per boot, 90 s after boot has completed (the assistant setting above is restored 45 s after
# boot, so the two do not step on each other). The script exits at once if an instance is already running.
if [ -f /data/local/mic_watchdog.sh ]; then
  (
    n=0
    while [ "$(getprop sys.boot_completed)" != "1" ] && [ $n -lt 120 ]; do sleep 2; n=$((n+1)); done
    sleep 90
    setsid sh /data/local/mic_watchdog.sh > /dev/null 2>&1
  ) > /dev/null 2>&1 &
fi

# Keep the mirror reachable over Wi-Fi and adb, also while the screen is off (see docs/home-assistant-wall-panel.md, section 1).
# Starts one watchdog per boot, 60 s after boot has completed. It never wakes the screen and never switches Wi-Fi off. The
# script exits at once if an instance is already running.
if [ -f /data/local/net_watchdog.sh ]; then
  (
    n=0
    while [ "$(getprop sys.boot_completed)" != "1" ] && [ $n -lt 120 ]; do sleep 2; n=$((n+1)); done
    sleep 60
    setsid sh /data/local/net_watchdog.sh > /dev/null 2>&1
  ) > /dev/null 2>&1 &
fi

# External camera HAL: JPEG stills of 2592x1944 (the webcam's maximum) crash the provider on the stock vendor library (an AOSP bug reads past the
# end of the YU12 buffer, see docs/home-assistant-wall-panel.md, section 5). A copy of camera.device@3.4-external-impl.so with a larger frame buffer
# (made by tools/patch_external_camera_hal.py) is bind-mounted over the vendor file, once per boot, and only when both files are exactly the ones
# the patch was made for. The provider is restarted only if it is already running (otherwise it loads the patched file when it starts).
CAMLIB=/vendor/lib/camera.device@3.4-external-impl.so
CAMNEW=/data/local/ext-impl-patched.so
if [ -f "$CAMNEW" ] && ! grep -q " $CAMLIB " /proc/mounts \
   && [ "$(sha256sum $CAMLIB | cut -d' ' -f1)" = "7f9709755376a60b64af35d41c96a361692919f5a0b47b4ce52f70b0d9c58efa" ] \
   && [ "$(sha256sum $CAMNEW | cut -d' ' -f1)" = "5faf6b7d4080e8787c3fcc7b47a07bcf1926da1753968ba6a146d70c1d63fc42" ]; then
  chmod 644 "$CAMNEW"
  mount -o bind "$CAMNEW" "$CAMLIB"
  [ -n "$(pidof android.hardware.camera.provider@2.4-external-service)" ] && setprop ctl.restart vendor.camera-provider-2-4-ext
fi
