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
# is refused (fixed by omarchy-mobile#556). 5 s after each wake: a ping and a DNS lookup over the
# bearer's interface (rmnet0), so mobile data is checked after every sleep, not only at the
# end, with sitd's data-call lines from that sleep ("Data-call list changed", "Internet
# bearer set up again", #817) beside it; 20 s after: the CP's state, sitd, its failed polls
# and Wi-Fi. WIFI=off turns the Wi-Fi radio off for the run (back on when the script ends,
# however it ends), so mobile data is the only route at each wake, the shape that lost data
# on the 7 Pro (omarchy-mobile#799, SUSPEND-PLAN M6-D). Stops itself, as omarchy-mobile#809
# asks: off the charger (and refuses to start there), on the CP not ONLINE, and on a new UFS
# error line or an oops, both read from dmesg, which is in memory, so the check still works
# if storage is what failed. The end counts the boot's "Reserve doorbell interrupt" and
# "PCI not powered on" lines.
# Before each request and with each data check, one line of CPIF's own state, as the 7 Pro's
# M6-D recorder reads it (device/cheetah/bringup/m6-data-capture.sh): the FMT and raw queues'
# heads and tails, the wake lines, pcie_powered_on and reserve_doorbell, each pktproc queue's
# fore/rear and pass, and the mif_cp2ap_msg count, so a failed wake says whether uplink,
# downlink or the control channel stopped.
# On W4HO-ham's palmtop under #809's terms (AGENTS.md, the 9a's modem-up entry), everywhere
# else attended; on the charger either way, and the boot ends in a reboot. N defaults to 10,
# the most a new kernel's first run may have:
#   [WIFI=off] systemd-run --unit=x-modem-sleep-series /root/modem-sleep-series.sh [N] [S] [append]
# The last step afterwards is "systemctl reboot", never reboot-to.
L=/var/log/omamobile/modem-sleep-series.log; CP=/usr/lib/omamobile-vendor/omamobile-modem-cp
N=${1:-10}; S=${2:-60}; H=1.1.1.1; Q=example.com; BAT=/sys/class/power_supply/max77779-battery
U='link startup failed|Host init failed|I/O error, dev|ufshcd_err_handler'
# An oops, a BUG or a kernel panic path in dmesg
O='Internal error:|Unable to handle kernel|kernel BUG at|BUG: |Oops'
bad() { dmesg | grep -cE "$1"; }
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
# On the charger: the battery charging, or full with the cable in (the charger then holds it
# and the current is about 0; a series stopped at sleep 47 on 2026-11-15 when the pack filled).
# Off the cable the status is Discharging.
charging() { case $(cat $BAT/status 2>/dev/null) in Charging | Full) return 0 ;; esac
  (( $(cat $BAT/current_avg 2>/dev/null || echo 0) > 0 )); }
data() { # a ping and a DNS lookup over the bearer's interface
  [[ -n $IF ]] || { echo "no bearer interface"; return; }
  echo "ping $(ping -c 3 -W 3 -I "$IF" "$H" 2>&1 | grep -o '[0-9]* received'), dns $(dns)"
}
cpif() { # one line of CPIF's state (read-only sysfs and /proc/interrupts)
  local c=/sys/devices/platform/cpif
  [[ -r $c/legacy_queues ]] || { echo "no cpif state"; return; }
  echo "fmt $(grep -oE '^FMT: tx head:[0-9]+ tail:[0-9]+|rx head:[0-9]+ tail:[0-9]+' $c/legacy_queues | head -2 | grep -oE '[0-9]+' | paste -sd/)" \
    "raw $(grep '^NORM_RAW' $c/legacy_queues | grep -oE '(head|tail):[0-9]+' | cut -d: -f2 | paste -sd/)" \
    "$(grep -oE '(cp2ap_wakeup|ap2cp_wakeup|pcie_powered_on|reserve_doorbell):[0-9]+' $c/legacy_queues | paste -sd' ')" \
    "dl $(awk '/fore\/rear\/done/ {f=$NF} /^ *pass:/ {printf "%s,%s ", f, $1}' $c/pktproc/status | sed 's/pass://g; s|fore/rear/done:||g')" \
    "ul $(awk '/fore\/rear:/ {f=$NF} /^ *pass:/ {printf "%s,%s ", f, $1}' $c/pktproc_ul/status | sed 's/pass://g; s|fore/rear:||g')" \
    "msg $(awk '/mif_cp2ap_msg/ {s=0; for (i = 2; i <= 9; i++) s += $i; print s}' /proc/interrupts)"
}
dns() { # one A query for $Q to the bearer's first DNS server, sent out of $IF itself: with Wi-Fi
  # connected the bearer's link is not resolved's default route, so resolvectl won't use it
  local srv; srv=$(resolvectl dns "$IF" 2>/dev/null | awk '{print $4}')
  [[ -n $srv ]] || { echo "no server"; return; }
  python3 - "$IF" "$srv" "$Q" <<'PY' 2>&1 | tail -1
import socket, struct, sys
dev, srv, name = sys.argv[1:4]
fam = socket.AF_INET6 if ':' in srv else socket.AF_INET
q = struct.pack('>HHHHHH', 0x5a5a, 0x0100, 1, 0, 0, 0)
q += b''.join(bytes([len(x)]) + x.encode() for x in name.split('.')) + b'\0' + struct.pack('>HH', 1, 1)
s = socket.socket(fam, socket.SOCK_DGRAM); s.settimeout(4)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, dev.encode())
try:
    s.sendto(q, (srv, 53)); r = s.recv(512)
    ok = r[:2] == q[:2] and r[3] & 0x0f == 0 and struct.unpack('>H', r[6:8])[0] > 0
    print('ok' if ok else 'bad answer')
except OSError as e:
    print('fail (%s)' % (e.strerror or 'timeout'))
PY
}
[[ -e /sys/class/rtc/rtc0/wakealarm ]] || { echo "no RTC wake alarm on this kernel" >&2; exit 1; }
charging || { echo "not charging: run this on the charger" >&2; exit 1; }
[[ ${3:-} == append ]] || : > $L
systemctl is-active -q omamobile-sit-data || { systemctl start omamobile-sit-data; sleep 8; }
[[ ${WIFI:-} == off ]] && { trap 'nmcli radio wifi on' EXIT; nmcli radio wifi off; sleep 10; }
IF=$(cat /run/omamobile-sit/data-interface /run/omamobile-sit/data-interface-kept 2>/dev/null | head -1)
say "$(uname -r) $(uname -v | cut -d' ' -f1); the data service: $(systemctl is-active omamobile-sit-data), device ${IF:-none}, Wi-Fi radio $(nmcli radio wifi), default via $(ip route show default | awk '{print $5}' | paste -sd,); $(st); data: $(data)"
sleep 10
for n in $(seq 1 "$N"); do
  s0=$(cat /sys/power/suspend_stats/success); f0=$(cat /sys/power/suspend_stats/fail); u0=$(bad "$U"); o0=$(bad "$O"); t0=$(date +%s)
  charging || { say "sleep $n: not charging any more: stop"; break; }
  [[ ${WIFI:-} == off ]] || for _ in $(seq 1 30); do ip route show default | grep -c wlan0 >/dev/null && break; sleep 1; done
  say "sleep $n: default via $(ip route show default | awk '{print $5}' | paste -sd,); screen off -> $(screen off); link: $(idle); link-ups in the last 20 s: $(journalctl -b -k --no-pager --since '-20 s' | grep -c 'link up: Gen3')"
  say "sleep $n, before: cpif $(cpif)"
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
  sleep 5
  say "sleep $n, 5 s after: default via $(ip route show default | awk '{print $5}' | paste -sd,); cpif $(cpif); data: $(data); cpif after the data check: $(cpif); sitd's data-call lines this sleep: $(journalctl -u omamobile-sitd --since "@$t0" --no-pager -o cat | grep -E 'Data-call list changed|Internet bearer' | cut -c1-160 | paste -sd'|' | sed 's/^$/none/')"
  sleep 15
  say "sleep $n, 20 s after: $(st), new ufs lines $(( $(bad "$U") - u0 )), new oops lines $(( $(bad "$O") - o0 )), sitd's last line: $(journalctl -b -u omamobile-sitd --no-pager | tail -1 | cut -c40-120)"
  (( $(bad "$U") > u0 )) && { say "a UFS error line in dmesg: stop"; dmesg | grep -E "$U" | tail -3 >> $L; break; }
  (( $(bad "$O") > o0 )) && { say "an oops in dmesg: stop"; dmesg | grep -E "$O" | tail -3 >> $L; break; }
  [[ $($CP state 2>&1 | tail -1) == ONLINE ]] || { say "the CP is not ONLINE: stop"; break; }
done
[[ -n $IF ]] && say "ping over $IF: $(ping -c 5 -W 3 -I "$IF" "$H" 2>&1 | grep -o '[0-9]* received')"
say "end: $(st); in the boot's kernel log: Reserve doorbell interrupt $(journalctl -b -k --no-pager | grep -c 'Reserve doorbell interrupt'), PCI not powered on $(journalctl -b -k --no-pager | grep -c 'PCI not powered on')"
say "kernel lines of the boot:"
journalctl -b -k --no-pager | grep -E "sleep refused|Unable to change power state|Link Active not set|Can.t set D0|BME is not set|link-down recovery|suspend_cp: abort|failed to suspend" | sed -E 's/^.{16}[^ ]+ kernel: //' | cut -c1-110 | sort | uniq -c | sort -rn | head -20 >> $L
say "done"
