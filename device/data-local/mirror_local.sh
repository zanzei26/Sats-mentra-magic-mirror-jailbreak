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
