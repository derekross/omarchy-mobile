#!/bin/bash
# SPDX-License-Identifier: MIT
# On the palmtop: N systemd sleeps of S seconds with the modem up, for a kernel whose
# link driver has the sleep guard on for zumapro (linux-omarchy-mobile#232; MODEM-PLAN,
# "Suspend with the modem on, with the sleep guard"). On a kernel without it one sleep
# costs the phone service until a reboot: use modem-sleep-test.sh there, attended.
# Before each request the modem is told "screen off" through sitd's socket and the
# script waits until the link driver's last line is "link down" and 5 s old; after it,
# "screen on". The modem's block inhibitor is passed with "systemctl suspend -i", an RTC
# alarm is the wake. The cellular data service is started if it isn't running, and the
# default routes are logged before each request: with Wi-Fi connected and the service
# as on main, the bearer's route is the only one left at the freeze and every request
# is refused (omarchy-mobile#750). 20 s after each request: the CP's state, sitd, its
# failed polls, Wi-Fi and new UFS lines. Stops when the CP isn't ONLINE. On the charger.
#   systemd-run --unit=x-modem-sleep-series /root/modem-sleep-series.sh [N] [S] [append]
# The last step afterwards is "systemctl reboot", never reboot-to.
L=/var/log/omamobile/modem-sleep-series.log; CP=/usr/lib/omamobile-vendor/omamobile-modem-cp
N=${1:-20}; S=${2:-60}; H=1.1.1.1
U='link startup failed|Host init failed|I/O error, dev|ufshcd_err_handler'
say() { echo "$(date +%T) $*" >> $L; sync "$L" 2>/dev/null; }
screen() { python3 - "$1" <<'PY' 2>&1 | tail -1
import json, socket, sys
s = socket.socket(socket.AF_UNIX); s.settimeout(15); s.connect('/run/omamobile-sit/socket')
s.sendall(json.dumps({'action': 'screen-state', 'on': sys.argv[1] == 'on'}).encode() + b'\n')
print(s.recv(4096).decode().strip()[:120])
PY
}
st() { echo "cp $($CP state 2>&1 | tail -1), sitd $(systemctl is-active omamobile-sitd), poll failures $(journalctl -b -u omamobile-sitd --no-pager | grep -c 'poll failed'), wlan0 $(cat /sys/class/net/wlan0/operstate 2>/dev/null || echo gone)"; }
idle() { # wait until the link has been down for 5 s; prints how long it took
  local t0=$SECONDS last
  while ((SECONDS - t0 < 60)); do
    last=$(journalctl -b -k --no-pager --since "-5 s" | grep -cE "gs201-pcie-cp .*(link up|link down)")
    [[ $last == 0 ]] && journalctl -b -k --no-pager -n 400 | grep -E "gs201-pcie-cp .*(link up|link down)" | tail -1 | grep -c "link down" >/dev/null && { echo "idle after $((SECONDS - t0)) s"; return 0; }
    sleep 1
  done
  echo "not idle in 60 s"; return 1
}
[[ -e /sys/class/rtc/rtc0/wakealarm ]] || { echo "no RTC wake alarm on this kernel" >&2; exit 1; }
[[ ${3:-} == append ]] || : > $L
systemctl is-active -q omamobile-sit-data || { systemctl start omamobile-sit-data; sleep 8; }
say "$(uname -r) $(uname -v | cut -d' ' -f1); the data service: $(systemctl is-active omamobile-sit-data), device $(cat /run/omamobile-sit/data-interface-kept 2>/dev/null), default via $(ip route show default | awk '{print $5}' | paste -sd,); $(st)"
sleep 10
for n in $(seq 1 "$N"); do
  s0=$(cat /sys/power/suspend_stats/success); f0=$(cat /sys/power/suspend_stats/fail); u0=$(journalctl -b -k --no-pager | grep -cE "$U")
  for _ in $(seq 1 30); do ip route show default | grep -c wlan0 >/dev/null && break; sleep 1; done
  say "sleep $n: default via $(ip route show default | awk '{print $5}' | paste -sd,); screen off -> $(screen off); link: $(idle); link-ups in the last 20 s: $(journalctl -b -k --no-pager --since '-20 s' | grep -c 'link up: Gen3')"
  rtcwake -m no -s "$S" >/dev/null 2>&1 || { say "sleep $n: rtcwake could not arm the alarm: stop"; break; }
  r0=$(cat /sys/class/rtc/rtc0/since_epoch)
  systemctl suspend -i
  for _ in $(seq 1 300); do [[ $(cat /sys/power/suspend_stats/success) != "$s0" || $(cat /sys/power/suspend_stats/fail) != "$f0" ]] && break; sleep 0.5; done
  r1=$(cat /sys/class/rtc/rtc0/since_epoch); sleep 3; rtcwake -m disable >/dev/null 2>&1
  if [[ $(cat /sys/power/suspend_stats/success) != "$s0" ]]; then
    irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
    res="entered, $((r1 - r0)) s, wake irq $irq ($(grep -E "^ *$irq:" /proc/interrupts | awk '{print $NF}'))"
  elif [[ $(cat /sys/power/suspend_stats/fail) != "$f0" ]]; then res="refused (fail $(cat /sys/power/suspend_stats/fail))"
  else res="no change in suspend_stats after 150 s"; fi
  say "sleep $n: $res; screen on -> $(screen on)"
  sleep 20
  say "sleep $n, 20 s after: $(st), new ufs lines $(( $(journalctl -b -k --no-pager | grep -cE "$U") - u0 )), sitd's last line: $(journalctl -b -u omamobile-sitd --no-pager | tail -1 | cut -c40-120)"
  [[ $($CP state 2>&1 | tail -1) == ONLINE ]] || { say "the CP is not ONLINE: stop"; break; }
done
IF=$(cat /run/omamobile-sit/data-interface-kept 2>/dev/null)
[[ -n $IF ]] && say "ping over $IF: $(ping -c 5 -W 3 -I "$IF" "$H" 2>&1 | grep -o '[0-9]* received')"
say "end: $(st)"
say "kernel lines of the boot:"
journalctl -b -k --no-pager | grep -E "sleep refused|Unable to change power state|Link Active not set|Can.t set D0|BME is not set|link-down recovery|suspend_cp: abort|failed to suspend" | sed -E 's/^.{16}[^ ]+ kernel: //' | cut -c1-110 | sort | uniq -c | sort -rn | head -20 >> $L
say "done"
