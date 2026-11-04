#!/system/bin/sh
# Touch-to-wake helper for the SATS mirror: a tap on the USB touchscreen wakes the display (Android 13 does not do this itself).
# The touch controller here is an eGalax USB device; adjust the grep for yours.
DEV=/dev/input/$(grep -A8 -i 'eGalax' /proc/bus/input/devices | grep -o 'event[0-9]*' | head -1)
while true; do
  # block until the touchscreen reports an event, then wake the display if it's off
  getevent -c 1 "$DEV" > /dev/null 2>&1 || { sleep 2; continue; }
  # not "Awake" (covers Asleep AND the ~2 s Dozing state)
  if ! dumpsys power 2>/dev/null | grep -q 'mWakefulness=Awake'; then
    input keyevent 224
  fi
  sleep 1
done
