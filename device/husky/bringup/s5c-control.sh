#!/bin/sh
# SPDX-License-Identifier: MIT
# Test only, as run on the 8 Pro on 2026-11-07 (see device/husky/MODEM-PLAN.md); this note and the SPDX line are the only changes.
# CONTROL for S5c: the same 30 s + 55 s + 30 s sampling, NO writes to any modem line. Log: /root/s5c-control.log
L=/sys/kernel/debug/cpif_test; U=/sys/kernel/debug/ufshcd/13200000.ufs/stats; O=/root/s5c-control.log
B=/sys/class/power_supply/max170xx_battery
: > $O
snap() { echo "$(date +%T.%N | cut -c1-12) $1 cur=$(cat $B/current_now) avg=$(cat $B/current_avg) v=$(cat $B/voltage_now) bat=$(cat $B/capacity)% bt=$(cat $B/temp) ufs=$(grep -vc ': 0$' $U) lines=$(awk '{s+=$2} END {print s+0}' $L/lines)" >> $O; }
i=0; while [ $i -lt 30 ]; do snap "base-$i"; sleep 1; i=$((i+1)); done
snap "pda1(none)"
i=0; while [ $i -lt 55 ]; do sleep 1; i=$((i+1)); snap "on+$i(none)"; done
sleep 2; snap "off+2(none)"
for t in 3 8 13 18 23 28; do sleep 5; snap "post+$t(none)"; done
echo DONE >> $O
