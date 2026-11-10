#!/bin/bash
# SPDX-License-Identifier: MIT
# On the palmtop, read-only apart from the sleeps: each CPU's cpuidle state0 and state1
# usage and time just before and just after one 60 s RTC-woken systemd sleep, twice:
# (A) as the kernel ships, (B) with state1 disabled for the sleep (what a sleep hook would do).
# If state1's time grows by about the sleep's length per core, C2 ran through the sleep.
L=/var/log/omamobile/cpuidle-check.log; : > $L
snap() { for c in /sys/devices/system/cpu/cpu[0-9]*; do echo "${c##*/} $(cat $c/cpuidle/state0/usage) $(cat $c/cpuidle/state0/time) $(cat $c/cpuidle/state1/usage) $(cat $c/cpuidle/state1/time) $(cat $c/cpuidle/state1/s2idle/usage 2>/dev/null || echo -) $(cat $c/cpuidle/state1/s2idle/time 2>/dev/null || echo -)"; done; }
# The kernel log is left alone (a later UFS check reads it): count before, compare after.
ufs_lines() { dmesg | grep -cE "link startup failed|Host init failed|I/O error"; }
one() { # LABEL
  local s0 r0 r1 u0; s0=$(cat /sys/power/suspend_stats/success); u0=$(ufs_lines)
  snap > /run/cpuidle-before; r0=$(cat /sys/class/rtc/rtc0/since_epoch)
  rtcwake -m no -s 60 >/dev/null || { echo "== $1: rtcwake could not arm the alarm (no /sys/class/rtc/rtc0/wakealarm?): stop, a sleep without an alarm ends only on a key" >> $L; exit 1; }
  systemctl suspend -i
  while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ]; do sleep 0.5; done
  r1=$(cat /sys/class/rtc/rtc0/since_epoch); snap > /run/cpuidle-after
  echo "== $1: rtc $((r1 - r0)) s between the snapshots, wake irq $(cat /sys/power/pm_wakeup_irq), new ufs lines $(($(ufs_lines) - u0))" >> $L
  paste /run/cpuidle-before /run/cpuidle-after | awk '{printf "%s: state0 +%d entries %.1f s; state1 +%d entries %.1f s; state1 s2idle +%s entries\n", $1, $9-$2, ($10-$3)/1e6, $11-$4, ($12-$5)/1e6, ($13=="-"?"-":$13-$6)}' >> $L
}
echo "$(uname -v | cut -c1-5) $(uname -r); state1: $(cat /sys/devices/system/cpu/cpu0/cpuidle/state1/name) $(cat /sys/devices/system/cpu/cpu0/cpuidle/state1/desc); s2idle dir: $([ -d /sys/devices/system/cpu/cpu0/cpuidle/state1/s2idle ] && echo yes || echo no)" >> $L
one "A, as shipped (state1 enabled)"
sleep 20
for f in /sys/devices/system/cpu/cpu*/cpuidle/state1/disable; do echo 1 > $f; done
one "B, state1 disabled for the sleep"
for f in /sys/devices/system/cpu/cpu*/cpuidle/state1/disable; do echo 0 > $f; done
echo "state1 disable after: $(cat /sys/devices/system/cpu/cpu*/cpuidle/state1/disable | tr -d '\n')" >> $L
echo done >> $L
