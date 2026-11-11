#!/bin/bash
# SPDX-License-Identifier: MIT
# On the palmtop: N systemd sleeps of S seconds with the modem up (MODEM-PLAN, "Suspend
# with the modem on"), an RTC alarm as the wake. A test only, and it ends in a reboot:
# the modem's own block inhibitor is passed with "systemctl suspend -i", and one sleep
# attempt, entered or refused, has left the phone service unable to reach the CP until
# the next reboot (2026-11-09). The sleep hooks run (NFC polling stopped, C2 out of the
# sleep, Wi-Fi kept). Records for each request how long it lasted, what woke it, and the
# CP's and the phone service's state after; "omamobile-sit status" shows the last state
# read, so check sitd's journal for "poll failed" as well. Stops when the CP isn't ONLINE,
# sitd isn't active or a UFS line appears. Attended, on the charger (AGENTS.md, "Suspend
# with the modem on"). Run detached:
#   systemd-run --unit=x-modem-sleep /root/modem-sleep-test.sh [N] [S]
# and when it is done, the last step is always "systemctl reboot", never reboot-to, so the
# modem stops cleanly and the phone service comes back with the next boot.
N=${1:-1}; S=${2:-60}; L=/var/log/omamobile/modem-sleep-test.log
U='link startup failed|Host init failed|I/O error, dev|ufshcd_err_handler'
CP=/usr/lib/omamobile-vendor/omamobile-modem-cp
st() { echo "cp $($CP state 2>&1), sitd $(systemctl is-active omamobile-sitd), $(omamobile-sit status 2>/dev/null | sed -n 's/^network: //p'), $(omamobile-sit status 2>/dev/null | sed -n 's/^IMS voice: //p' | cut -c1-60)"; }
echo "$(date -Is) $(uname -r) $(uname -v | cut -d' ' -f1): $N sleeps of $S s with the modem up; before: $(st); state1 disable $(cat /sys/devices/system/cpu/cpu*/cpuidle/state1/disable 2>/dev/null | tr -d '\n'), spm_lvl $(cat /sys/devices/platform/soc/13200000.ufs/spm_lvl 2>/dev/null)" >> $L
[[ $($CP state 2>&1) == ONLINE ]] || { echo "the CP is not ONLINE: stop" >> $L; exit 1; }
for c in $(seq 1 "$N"); do
  s0=$(cat /sys/power/suspend_stats/success); f0=$(cat /sys/power/suspend_stats/fail); u0=$(journalctl -b -k --no-pager | grep -cE "$U")
  rtcwake -m no -s "$S" >/dev/null || { echo "cycle $c: rtcwake could not arm the alarm: stop" >> $L; exit 1; }
  r0=$(cat /sys/class/rtc/rtc0/since_epoch); k0=$(awk '{print $1}' /proc/uptime)
  systemctl suspend -i || { echo "cycle $c: systemctl suspend -i refused: stop" >> $L; exit 1; }
  for _ in $(seq 1 $((S * 2 + 60))); do [[ $(cat /sys/power/suspend_stats/success) != "$s0" || $(cat /sys/power/suspend_stats/fail) != "$f0" ]] && break; sleep 0.5; done
  r1=$(cat /sys/class/rtc/rtc0/since_epoch); sleep 6
  irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
  line="cycle $c $(date +%T): rtc $((r1 - r0)) s, suspend_stats $(cat /sys/power/suspend_stats/success)/$(cat /sys/power/suspend_stats/fail) (was $s0/$f0), wake irq $irq ($(grep -E "^ *$irq:" /proc/interrupts | awk '{print $(NF-1), $NF}')), new ufs lines $(($(journalctl -b -k --no-pager | grep -cE "$U") - u0)), after: $(st)"
  echo "$line" >> $L
  journalctl -b -k --no-pager --since "-$((S + 30)) s" | grep -E "PM: suspend (entry|exit)|PM: .*(abort|fail|wakeup)|cpif:.*(suspend|resume|ERR|crash)|pcie.*(suspend|resume|fail)" | tail -8 | cut -c40-200 | sed 's/^/   /' >> $L
  rtcwake -m disable >/dev/null 2>&1
  echo "   wlan0 $(cat /sys/class/net/wlan0/operstate 2>/dev/null || echo gone), wifi hook: $(journalctl -b --no-pager --since "-$((S + 40)) s" | grep -o "Wi-Fi lost across sleep[^;]*" | tail -1)" >> $L
  case "$line" in *"new ufs lines 0, after: cp ONLINE, sitd active"*) ;; *) echo "stop: the modem or storage is not as before" >> $L; exit 2 ;; esac
  sleep 20
done
echo "done: $N sleeps" >> $L
