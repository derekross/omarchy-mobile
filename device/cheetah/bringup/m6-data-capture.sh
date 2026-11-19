#!/bin/bash
# SPDX-License-Identifier: MIT
# m6-data-capture.sh: where mobile data stops across a sleep with the modem up
# (SUSPEND-PLAN, M6-D).
#
# Run on the 7 Pro as root, attended, on the charger, in a boot that ends in a
# reboot (AGENTS.md section 1 and section 4, "Suspend with the modem on"),
# after the runbook's step 2 has killed omamobile-modem-inhibit.service for
# this boot. Auto-sleep (omamobile-sleepd) does the sleeping. This script arms
# an RTC alarm in each awake window and, the moment a wake is seen (polled
# every 0.5 s), takes a sleep inhibitor of its own and holds it while it
# reads, so the next sleep can't cut the check off (the 2026-11-14 recorder
# pinged inside sleepd's 5 s grace).
#
# Per wake it records: the wake source and whether the RTC alarm was due
# (an s2mpg12-pmic wake well before the alarm is the PMIC's early wake,
# counted apart), CPIF's own state before and after a ping over the bearer
# (the IPC queues, FMT being the control channel; the packet processor's
# downlink and uplink queues; the wake lines and the reserved doorbell; the
# modem's MSI count), the bearer's packet counters, the route the kernel
# picks for the bearer, the UFS error-handler count and the CPIF and link
# lines logged since the last wake. Besides its log it arms the RTC alarm and
# sends pings; it writes nothing else but a temporary file in /run.
#
# No identifiers: the bearer's addresses and gateways are logged only as
# present or absent with their prefix length, routes by device and metric.
#
# Ends after WAKES RTC wakes, three failing wakes in a row, any rise in the
# UFS error-handler count, or 45 minutes; on any exit, including a signal, it
# starts omamobile-modem-inhibit.service again, so the phone stops sleeping
# with the modem up the moment the series ends.
#
#   WAKES=10 SLEEP_S=60 IFACE=rmnet2 bash m6-data-capture.sh
#
# Log: /var/log/omamobile/m6-data-capture.log (an earlier one is kept as
# .prev).
set -u
WAKES=${WAKES:-10}
SLEEP_S=${SLEEP_S:-60}
IFACE=${IFACE:-rmnet2}
out=/var/log/omamobile/m6-data-capture.log
cpif=/sys/devices/platform/cpif

die() {	# a refusal after the runbook's step 2 leaves the modem's inhibitor killed
	systemctl start omamobile-modem-inhibit.service >/dev/null 2>&1
	echo "m6-data-capture: $*" >&2; exit 1
}

# Refusals, before anything is armed.
[ "$(id -u)" = 0 ] || die "run as root"
tr -d '\0' < /proc/device-tree/compatible 2>/dev/null | grep -c cheetah >/dev/null || die "not a Pixel 7 Pro (cheetah)"
online=0
for s in /sys/class/power_supply/*/online; do [ "$(cat "$s" 2>/dev/null)" = 1 ] && online=1; done
[ "$online" = 1 ] || die "not on the charger: modem tests run on the charger"
[ -r $cpif/legacy_queues ] || die "no CPIF state in $cpif (is the modem up?)"
ip link show "$IFACE" >/dev/null 2>&1 || die "no $IFACE: the bearer is not up"
if systemd-inhibit --list --no-legend 2>/dev/null | grep -c omamobile-modem >/dev/null; then
	die "the modem's sleep inhibitor still holds: the runbook's step 2 comes first"
fi

restore() {
	systemctl start omamobile-modem-inhibit.service >/dev/null 2>&1
	echo "inhibitor restored: $(systemd-inhibit --list --no-legend 2>/dev/null | grep -c omamobile-modem) $(date -Is)" >> "$out"
}
trap restore EXIT
trap 'exit 1' INT TERM HUP

[ -e "$out" ] && mv -f "$out" "$out.prev"

ufs_count() { dmesg | grep -c ufshcd_err_handler; }

addr_shape() {	# presence and prefix length only, never the address
	ip -o addr show "$IFACE" | awk '{split($4, a, "/"); print $3 "/" a[2]}' | tr '\n' ' '
}

snap() {	# $1: label
	echo "--- $1 $(date -Is)"
	echo "suspend_stats success=$(cat /sys/power/suspend_stats/success) fail=$(cat /sys/power/suspend_stats/fail) ufs=$(ufs_count)"
	echo "[legacy_queues]"; cat $cpif/legacy_queues
	echo "[pktproc dl]"; grep -E 'Queue|fore/rear|pass|fail' $cpif/pktproc/status
	echo "[pktproc ul]"; grep -E 'Queue|fore/rear|pass|fail|total' $cpif/pktproc_ul/status
	echo "[irqs]"; grep -E 'mif_|cp2ap|11920000|pcie-cp|DW-PCI-MSI-0001' /proc/interrupts |
		awk '{s=0; for (i = 2; i <= 9; i++) s += $i; print $1, s, $NF}'
	echo "[$IFACE] $(ip -s -o link show "$IFACE" | grep -oE 'state [A-Z]+') addr: $(addr_shape)"
	ip -s link show "$IFACE" | awk '/RX:/ {getline; print "rx packets", $2} /TX:/ {getline; print "tx packets", $2, "dropped", $4}'
	echo "[route] defaults: $(ip route show default | awk '{for (i = 1; i <= NF; i++) if ($i == "dev" || $i == "metric") printf "%s %s ", $i, $(i+1); printf "; "}')"
	echo "route for 1.1.1.1 oif $IFACE: $(ip route get 1.1.1.1 oif "$IFACE" 2>&1 | grep -oE 'dev [^ ]+|unreachable|No route[^,]*' | head -1)"
	echo "[modem] $(omamobile-sit status 2>&1 | grep -oE 'data bearer: [a-z]+|IMS registered|network: [a-z]+' | tr '\n' ' ')"
}

check() {
	p=$(ping -c3 -W2 -I "$IFACE" 1.1.1.1 2>&1 | grep -oE '[0-9]+ received')
	echo "check ping=${p:-none}"
}

kernel_since() {	# $1: seconds since the epoch
	journalctl -k --no-pager -o short-precise --since "@$1" 2>/dev/null > /run/m6-kmsg.$$
	grep -E 'cpif|pcie-cp|11920000' /run/m6-kmsg.$$ |
		grep -vE 'secure ATU|DBI ID|MSI re-armed|kerneltime|PHY isolated|link up: Gen3' |
		sed -E 's/^[A-Za-z]+ [0-9]+ //; s/ [^ ]+ kernel: / /' | tail -40
	echo "link-ups: $(grep -c 'link up: Gen3' /run/m6-kmsg.$$)  reserves(off): $(grep -c 'PCI not powered on' /run/m6-kmsg.$$)  reserves(onoff): $(grep -c 'PCI on/off working' /run/m6-kmsg.$$)"
	rm -f /run/m6-kmsg.$$
}

ufs0=$(ufs_count)
{
	echo "start $(date -Is) kernel $(uname -r) wakes=$WAKES sleep=${SLEEP_S}s iface=$IFACE ufs=$ufs0"
	echo "wifi-keep-across-sleep: $([ -e /etc/omamobile/wifi-keep-across-sleep ] && echo set || echo unset)"
	echo "auto-sleep toggle: $(ls /home/*/.local/state/omarchy/toggles/ 2>/dev/null | grep -c omamobile-sleep)"
	snap baseline
	check
	snap "baseline after ping"
} > "$out" 2>&1

start=$(cat /sys/power/suspend_stats/success)
last=$start
mark=$(date +%s)
alarm=0
rtc_wakes=0
early=0
bad=0
deadline=$(( $(date +%s) + 2700 ))
while :; do
	now=$(cat /sys/power/suspend_stats/success)
	if [ "$now" -ne "$last" ]; then
		systemd-inhibit --what=sleep --who=m6-data-capture --why="data check after a wake" \
			--mode=block sleep 120 &
		hold=$!
		t=$(date +%s)
		irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
		name=$(awk -v i="$irq" '$1 == i":" {print $NF}' /proc/interrupts)
		case $name in
		*pmic*)
			if [ "$alarm" -gt 0 ] && [ "$t" -ge $((alarm - 3)) ]; then
				rtc_wakes=$((rtc_wakes + 1)); kind="rtc"
			else
				early=$((early + 1)); kind="pmic, before the alarm"
			fi ;;
		*) kind=${name:-unknown} ;;
		esac
		{
			snap "wake $((now - start)) ($kind, alarm due $((alarm > 0 ? t - alarm : 0)) s ago)"
			echo "[kernel since last wake]"; kernel_since "$mark"
			check
			snap "after the ping"
		} >> "$out" 2>&1
		kill "$hold" 2>/dev/null; wait "$hold" 2>/dev/null
		case $(grep '^check ' "$out" | tail -1) in *"ping=3 received"*) bad=0 ;; *) bad=$((bad + 1)) ;; esac
		mark=$t
		last=$now
		alarm=0
		u=$(ufs_count)
		[ "$u" -gt "$ufs0" ] && { echo "end: the UFS error handler ran ($ufs0 -> $u)" >> "$out"; break; }
	fi
	[ "$rtc_wakes" -ge "$WAKES" ] && { echo "end: $WAKES RTC wakes ($early early PMIC wakes)" >> "$out"; break; }
	[ "$bad" -ge 3 ] && { echo "end: three failing wakes in a row" >> "$out"; break; }
	[ "$(date +%s)" -ge "$deadline" ] && { echo "end: deadline" >> "$out"; break; }
	# arm one when none is set, and again when the last went off while awake
	# (an early refusal, sleepd's retry or a lit screen), or the next sleep
	# has no alarm and its PMIC wake would be counted as the RTC's
	if [ "$alarm" -eq 0 ] || [ "$(date +%s)" -ge "$alarm" ]; then
		rtcwake -m no -s "$SLEEP_S" >/dev/null 2>&1 && alarm=$(( $(date +%s) + SLEEP_S ))
	fi
	sleep 0.5
done

# The inhibitor comes back first (the trap), then the awake read.
restore
trap - EXIT
{
	echo "--- awake, 60 s after the end, the modem's inhibitor holding"
	sleep 60
	snap "awake end"
	check
	echo "done $(date -Is)"
} >> "$out" 2>&1
