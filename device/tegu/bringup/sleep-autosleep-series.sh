#!/bin/bash
# SPDX-License-Identifier: MIT
# Long-sleep series the way the palmtop really sleeps: the shell's auto-sleep
# (omamobile-sleepd, toggle omamobile-sleep on) puts it down 30 s after the screen
# goes off behind the lock, and 5 s after a dark resume; this script only arms an
# RTC alarm S seconds ahead, waits for the wake, records it and arms the next.
# N alarms. Records each wake's RTC length, wake IRQ and UFS errors.
N=${N:-12}; S=${S:-1800}; L=${L:-/var/log/omamobile/sleep-autosleep-20261108.log}
mkdir -p /var/log/omamobile; : > $L
echo "$(uname -v): N=$N S=$S, toggle $(runuser -u mobile -- env HOME=/home/mobile OMARCHY_PATH=/usr/share/omarchy XDG_RUNTIME_DIR=/run/user/1000 omarchy-toggle-enabled omamobile-sleep && echo on || echo off), state1 disable $(cat /sys/devices/system/cpu/cpu*/cpuidle/state1/disable | tr -d '\n'), $(uname -r)" >> $L
echo N > /sys/module/printk/parameters/console_suspend
for c in $(seq 1 $N); do
  dmesg -C
  s0=$(cat /sys/power/suspend_stats/success); r0=$(cat /sys/class/rtc/rtc0/since_epoch)
  rtcwake -m no -s $S >/dev/null
  # wait for the sleep and the wake (success counts the completed cycle)
  while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ]; do sleep 1; done
  r1=$(cat /sys/class/rtc/rtc0/since_epoch)
  echo "cycle $c $(date +%T): rtc $((r1 - r0)) s, wake irq $(cat /sys/power/pm_wakeup_irq 2>/dev/null), ufs $(dmesg | grep -cE "link startup failed|Host init failed|I/O error"), oops $(dmesg | grep -c "Internal error"), ok $(cat /sys/power/suspend_stats/success) fail $(cat /sys/power/suspend_stats/fail)" >> $L
  sync
  [ "$(dmesg | grep -cE "link startup failed|Host init failed|I/O error")" = 0 ] || { echo "UFS errors: stop" >> $L; break; }
done
echo done >> $L
