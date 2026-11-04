#!/system/bin/sh
# SATS mirror: boot diagnostics -> /metadata/dbg (unencrypted, survives a data wipe). Bounded: only the first ~10 min after boot.
D=/metadata/dbg
mkdir -p $D 2>/dev/null
chmod 777 $D 2>/dev/null
echo "dbg_log started: $(date) uptime $(cut -d' ' -f1 /proc/uptime)" >> $D/boot.txt
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
( i=0; while [ $i -lt 100 ]; do dmesg > $D/dmesg.new 2>/dev/null && mv -f $D/dmesg.new $D/dmesg.txt; i=$((i+1)); sleep 6; done ) &
( i=0; while [ $i -lt 75 ]; do { date; getprop | grep -E 'init\.svc|sys\.boot|ro\.boottime|vold|apex|keystore|crypto|sys\.usb'; } > $D/props.new 2>/dev/null && mv -f $D/props.new $D/props.txt; i=$((i+1)); sleep 8; done ) &
# Watchdog: boot not completed after 420 s => save state and reboot, at most 2 times in a row (then it stays out of the way).
( sleep 420
  n=$(cat $D/wdcount 2>/dev/null); [ -z "$n" ] && n=0
  if [ "$(getprop sys.boot_completed)" != "1" ]; then
    if [ "$n" -lt 2 ]; then
      echo $((n+1)) > $D/wdcount
      echo "WATCHDOG #$((n+1)): boot_completed != 1 after 420 s -> rebooting ($(date))" >> $D/boot.txt
      dmesg > $D/dmesg_final.txt 2>/dev/null
      sync
      setprop sys.powerctl reboot,dbgwd
      sleep 20
      echo b > /proc/sysrq-trigger
    else
      echo "WATCHDOG disabled: already rebooted $n times ($(date))" >> $D/boot.txt
    fi
  else
    echo 0 > $D/wdcount
    echo "boot_completed=1 at $(date); watchdog idle" >> $D/boot.txt
  fi ) &
wait
