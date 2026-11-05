#!/system/bin/sh
# Self-healing for the Companion app's wake word recorder on the USB camera microphone.
#
# Problem: when the Assist window closes at the same moment the wake word listener reopens the microphone, the USB audio
# HAL can lose its profile ("adev_open_input_stream fail ... doesn't match existing profile"). AudioRecord then fails with
# status -38, the app gives up ("AudioRecord failed to initialize") and never retries, so "Hey Jarvis" is dead until
# something restarts the listener.
#
# Fix: watch the log for those errors, then (1) unbind/rebind the voice service, and if no recorder comes back
# (2) re-enumerate the USB camera (only while NO recorder is active: touching USB under an active recorder crash-loops
# audioserver) and rebind again. Cooldown 90 s, at most 3 heals per 15 minutes. Log: /data/local/mic_watchdog.log
VIS=io.homeassistant.companion.android/.assist.service.AssistVoiceInteractionService
USBDEV=/sys/bus/usb/devices/5-1.2
LOG=/data/local/mic_watchdog.log
PIDF=/data/local/tmp/mic_watchdog.pid
# one instance only. The pid file survives a reboot, and its pid may now belong to some other process (or to this one),
# so the old pid only counts if it is not our own pid and its command line is this script.
oldpid=$(cat $PIDF 2>/dev/null)
if [ -n "$oldpid" ] && [ "$oldpid" != "$$" ] && grep -q mic_watchdog /proc/$oldpid/cmdline 2>/dev/null; then exit 0; fi
echo $$ > $PIDF
log() {
  echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG
  if [ "$(wc -c < $LOG)" -gt 100000 ]; then tail -n 200 $LOG > $LOG.tmp && mv $LOG.tmp $LOG; fi
}
recorders() { dumpsys audio 2>/dev/null | grep -c 'source client'; }
set_vis() { settings put secure voice_interaction_service "$1"; [ -n "$1" ] && settings put secure assistant "$1"; }
last_heal=0; heals=0; win_start=$(date +%s)
heal() {
  now=$(date +%s)
  if [ $((now - last_heal)) -lt 90 ]; then log "skip: cooldown"; return; fi
  if [ $((now - win_start)) -gt 900 ]; then win_start=$now; heals=0; fi
  if [ $heals -ge 3 ]; then log "skip: 3 heals in 15 minutes already"; return; fi
  heals=$((heals + 1)); last_heal=$now
  sleep 4
  if [ "$(recorders)" != "0" ]; then log "a recorder is active again, nothing to do"; return; fi
  log "soft heal: rebinding the voice service"
  set_vis ""; sleep 3; set_vis "$VIS"; sleep 10
  if [ "$(recorders)" != "0" ]; then log "soft heal ok (recorder is back)"; return; fi
  log "hard heal: re-enumerating the USB camera"
  set_vis ""; sleep 3
  if [ "$(recorders)" = "0" ] && [ -e "$USBDEV/authorized" ]; then
    echo 0 > $USBDEV/authorized; sleep 3; echo 1 > $USBDEV/authorized; sleep 10
  else
    log "recorder active or camera path missing, USB untouched"
  fi
  set_vis "$VIS"; sleep 10
  if [ "$(recorders)" != "0" ]; then log "hard heal ok (recorder is back)"; else log "hard heal done, no recorder (wake word may be switched off in the app)"; fi
}
log "watchdog started (pid $$)"
# only react to errors that appear from now on (the log buffer still holds old ones)
START=$(date '+%m-%d %H:%M:%S.000')
last_ovf=0
logcat -T "$START" -v time -e 'could not create record track, status: -38|AudioRecord failed to initialize|RecordThread: buffer overflow' 2>/dev/null | while read -r line; do
  case "$line" in
    *"buffer overflow"*)   # only logged (no heal): audio was dropped on its way to the app; at most one line per 5 s
      now=$(date +%s); if [ $((now - last_ovf)) -ge 5 ]; then last_ovf=$now; log "overflow: $(echo "$line" | cut -c1-110)"; fi; continue ;;
    *"status: -38"*|*"failed to initialize"*) ;;
    *) continue ;;   # skip logcat's "--- beginning of ..." banners
  esac
  log "trigger: $(echo "$line" | cut -c1-120)"
  heal
done
log "watchdog: logcat ended, exiting"
rm -f $PIDF
