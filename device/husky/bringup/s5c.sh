#!/bin/sh
# SPDX-License-Identifier: MIT
# Test only, as run on the 8 Pro on 2026-11-07 (see device/husky/MODEM-PLAN.md); this note and the SPDX line are the only changes.
# S5c (TEST ONLY): pda_active=1, then gpio_on once, 55 s of 1 s samples, gpio_off, pda_active=0 only if the CP side is quiet.
# Runs ON the phone so the power-off happens even if ssh drops. Log: /root/s5c.log
L=/sys/kernel/debug/cpif_test; U=/sys/kernel/debug/ufshcd/13200000.ufs/stats; O=/root/s5c.log
B=$(ls -d /sys/class/power_supply/*battery* | head -1)
: > $O
cp2ap() { awk '/^CP2AP_/ {s+=$2} END {print s+0}' $L/lines; }
ufsbad() { [ "$(grep -vc ': 0$' $U)" != 0 ] || [ "$(dmesg | grep -c 'ufshcd_err_handler started')" != 0 ]; }
snap() { echo "$(date +%T.%N | cut -c1-12) $1 $(awk '{printf "%s=%s ",$1,$2}' $L/lines | sed 's/AP2CP_//g;s/CP2AP_/c2a_/g') ufs=$(grep -vc ': 0$' $U) cur=$(cat $B/current_now) avg=$(cat $B/current_avg 2>/dev/null) v=$(cat $B/voltage_now) bat=$(cat $B/capacity)% bt=$(cat $B/temp)" >> $O; }
# 30 s baseline at the same cadence
i=0; while [ $i -lt 30 ]; do snap "base-$i"; sleep 1; i=$((i+1)); done
BASE=$(awk '/ base-/ {for(i=1;i<=NF;i++) if ($i ~ /^cur=/) {sub("cur=","",$i); s+=$i; n++}} END {printf "%d", s/n}' $O)
echo "baseline cur=$BASE uA" >> $O
echo 1 > $L/pda_active; echo "pda_active=1 rc=$?" >> $O; snap "pda1"
echo 1 > $L/gpio_on; RC=$?; echo "gpio_on rc=$RC" >> $O
STOP=""
if [ $RC = 0 ]; then
  i=0
  while [ $i -lt 55 ]; do
    sleep 1; i=$((i+1)); snap "on+$i"
    ufsbad && { STOP="UFS"; break; }
    BT=$(cat $B/temp); [ "$BT" -gt 450 ] && { STOP="BATTEMP"; break; }
    CUR=$(cat $B/current_now); [ $((BASE - CUR)) -gt 300000 ] && { STOP="CURRENT"; break; }
  done
fi
echo "STOPREASON=${STOP:-none-at-55s}" >> $O
echo 1 > $L/gpio_off; echo "gpio_off rc=$?" >> $O
sleep 2; snap "off+2"
if [ "$(cp2ap)" = 0 ]; then
  echo 0 > $L/pda_active; echo "pda_active=0 rc=$?" >> $O
else
  echo "CP2AP STILL HIGH after gpio_off: pda_active NOT lowered, do not reboot" >> $O
fi
for t in 3 8 13 18 23 28; do sleep 5; snap "post+$t"; done
echo DONE >> $O
