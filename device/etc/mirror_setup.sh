#!/system/bin/sh
# Runs once per boot after boot_completed (idempotent). Readable version; the installed one is a comment-free variant
# padded to the same file length (see docs: same-length single-block patch).
chmod 0600 /dev/mpp_service 2>/dev/null
mkdir -p /data/local 2>/dev/null
# Chrome: no hardware video decode (only honoured on debuggable builds; the /dev/mpp_service rule is what really matters)
echo '_ --disable-accelerated-video-decode' > /data/local/chrome-command-line
chmod 0644 /data/local/chrome-command-line
# First boot only: mirror-friendly defaults (screen off after 60 s, no lock screen)
F=/data/local/.mirror_defaults_done
if [ ! -e $F ]; then
  settings put system screen_off_timeout 60000
  settings put global stay_on_while_plugged_in 0
  cmd lock_settings set-disabled true >/dev/null 2>&1
  touch $F
fi
# local tuning hook (editable over adb, no reflash)
[ -f /data/local/mirror_local.sh ] && sh /data/local/mirror_local.sh
# stop the boot-time log capture after 10 minutes (avoids constant flash writes)
sleep 600
stop dbg_logcat
