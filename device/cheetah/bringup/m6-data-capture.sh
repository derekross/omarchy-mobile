#!/bin/bash
# SPDX-License-Identifier: MIT
# m6-data-capture.sh: where mobile data stops across a sleep with the modem up
# (SUSPEND-PLAN, "The release check with the modem up, 2026-11-14 night").
#
# Run on the 7 Pro as root, attended, on the charger, in a boot that ends in a
# reboot (AGENTS.md section 1 and section 4, "Suspend with the modem on"). The
# caller has stopped omamobile-modem-inhibit for this boot; auto-sleep
# (omamobile-sleepd) does the sleeping. This script only arms an RTC alarm in
# each awake window and, after each wake, holds a sleep inhibitor of its own
# while it reads: so the data check is never cut off by the next sleep, which
# the 2026-11-14 recorder's ping inside sleepd's 5 s grace could be.
#
# It reads only. Per wake it records the wake source, a ping and a DNS lookup
# over the bearer, the routes, the bearer's packet counters and CPIF's own
# state: the IPC queues (FMT is the control channel), the packet processor's
# downlink and uplink queues, the wake lines and the reserved doorbell, the
# modem's MSI count, and the CPIF and link lines the kernel logged since the
# last wake. The point is to tell, at the first wake where data fails, whether
# the modem stops consuming uplink, stops delivering downlink, or stops
# talking on the control channel too.
#
#   WAKES=10 SLEEP_S=60 IFACE=rmnet2 bash m6-data-capture.sh
#
# Output: /var/log/omamobile/m6-data-capture.log (no identifiers: it records
# counters, queue positions, the bearer's own address and routes, not the
# SIM, IMEI or network names). Ends after WAKES timer wakes, after three
# failing wakes in a row, or after 45 minutes.
set -u
WAKES=${WAKES:-10}
SLEEP_S=${SLEEP_S:-60}
IFACE=${IFACE:-rmnet2}
out=/var/log/omamobile/m6-data-capture.log
cpif=/sys/devices/platform/cpif

snap() {	# $1: label
	echo "--- $1 $(date -Is)"
	echo "suspend_stats success=$(cat /sys/power/suspend_stats/success) fail=$(cat /sys/power/suspend_stats/fail) wake_irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)"
	echo "inhibitors: $(systemd-inhibit --list --no-legend 2>/dev/null | awk '{print $1}' | sort | uniq -c | tr '\n' ' ')"
	echo "[legacy_queues]"; cat $cpif/legacy_queues
	echo "[pktproc dl]"; grep -E 'Queue|fore/rear|pass|fail' $cpif/pktproc/status
	echo "[pktproc ul]"; grep -E 'Queue|fore/rear|pass|fail|total' $cpif/pktproc_ul/status
	echo "[irqs]"; grep -E 'mif_|cp2ap|11920000|pcie-cp|DW-PCI-MSI-0001' /proc/interrupts | awk '{s=0; for(i=2;i<=9;i++) s+=$i; print $1, s, $NF}'
	echo "[$IFACE]"; ip -s -o link show "$IFACE" | sed -E 's/link\/[^ ]+ ?//'
	ip -o addr show "$IFACE" | awk '{print "addr", $4}'
	echo "[routes]"; ip route show default; ip route show table all | grep -c "$IFACE" | sed 's/^/routes naming iface: /'
	echo "[modem] $(omamobile-sit status 2>&1 | grep -oE 'data bearer: [a-z]+|IMS registered|network: [a-z]+' | tr '\n' ' ')"
}

check() {	# under our own inhibitor, so the next sleep waits for it
	systemd-inhibit --what=sleep --who=m6-data-capture --why="data check after a wake" --mode=block \
		bash -c "sleep 3
			p=\$(ping -c3 -W2 -I $IFACE 1.1.1.1 2>&1 | grep -oE '[0-9]+ received')
			d=\$(timeout 6 getent ahostsv4 example.com >/dev/null 2>&1 && echo ok || echo fail)
			echo \"check ping=\${p:-none} dns=\$d\""
}

kernel_since() {	# $1: seconds-since-epoch
	journalctl -k --no-pager -o short-precise --since "@$1" 2>/dev/null |
		grep -E 'cpif|pcie-cp|11920000' |
		grep -vE 'secure ATU|DBI ID|MSI re-armed|kerneltime|PHY isolated|link up: Gen3' |
		sed -E 's/^[A-Za-z]+ [0-9]+ //; s/ [^ ]+ kernel: / /' | tail -40
	echo "link-ups: $(journalctl -k --no-pager --since "@$1" 2>/dev/null | grep -c 'link up: Gen3')  reserves(off): $(journalctl -k --no-pager --since "@$1" 2>/dev/null | grep -c 'PCI not powered on')  reserves(onoff): $(journalctl -k --no-pager --since "@$1" 2>/dev/null | grep -c 'PCI on/off working')"
}

{
	echo "start $(date -Is) kernel $(uname -r) wakes=$WAKES sleep=${SLEEP_S}s iface=$IFACE"
	echo "wifi-keep-across-sleep: $([ -e /etc/omamobile/wifi-keep-across-sleep ] && echo set || echo unset)"
	echo "policy: $(/usr/lib/omamobile-vendor/omamobile-modem-sleep-policy check 2>&1)"
	echo "charger online: $(cat /sys/class/power_supply/*/online 2>/dev/null | tr '\n' ' ')"
	snap baseline
	check
} > "$out" 2>&1

start=$(cat /sys/power/suspend_stats/success)
last=$start
mark=$(date +%s)
timer_wakes=0
bad=0
deadline=$(( $(date +%s) + 2700 ))
while :; do
	now=$(cat /sys/power/suspend_stats/success)
	if [ "$now" -ne "$last" ]; then
		irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
		name=$(awk -v i="$irq" '$1 == i":" {print $NF}' /proc/interrupts)
		case $name in *pmic*) timer_wakes=$((timer_wakes + 1)); kind=timer ;; *) kind=$name ;; esac
		{
			snap "wake $((now - start)) ($kind)"
			echo "[kernel since last wake]"; kernel_since "$mark"
			c=$(check); echo "$c"
		} >> "$out" 2>&1
		case $(tail -1 "$out") in *"ping=3 received"*) bad=0 ;; *) bad=$((bad + 1)) ;; esac
		mark=$(date +%s)
		last=$now
	fi
	[ "$timer_wakes" -ge "$WAKES" ] && { echo "end: $WAKES timer wakes" >> "$out"; break; }
	[ "$bad" -ge 3 ] && { echo "end: three failing wakes in a row" >> "$out"; break; }
	[ "$(date +%s)" -ge "$deadline" ] && { echo "end: deadline" >> "$out"; break; }
	rtcwake -m no -s "$SLEEP_S" >/dev/null 2>&1
	sleep 2
done
{
	echo "--- awake, 60 s after the end"
	sleep 60
	snap "awake end"
	check
	echo "done $(date -Is)"
} >> "$out" 2>&1
