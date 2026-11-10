#!/bin/sh
# SPDX-License-Identifier: MIT
# Test only, as run on the 8 Pro on 2026-11-07 (see device/husky/MODEM-PLAN.md); this note and the SPDX line are the only changes.
# S5d (TEST ONLY): battery-only current measurement around the modem power-on. Runs ON the phone; log /root/s5d.log.
# Phases: A baseline 150 s (no writes) -> B pda_active=1 + gpio_on, 60 s (median-of-5 abort) -> gpio_off, pda_active=0 if CP2AP quiet
#         -> C post 120 s -> D control 120 s (no writes). 1 s samples of current_now/current_avg/voltage.
L=/sys/kernel/debug/cpif_test; U=/sys/kernel/debug/ufshcd/13200000.ufs/stats; O=/root/s5d.log; B=/sys/class/power_supply/max170xx_battery
: > $O
cp2ap() { awk '/^CP2AP_/ {s+=$2} END {print s+0}' $L/lines; }
ufsbad() { [ "$(grep -vc ': 0$' $U)" != 0 ] || [ "$(dmesg | grep -c 'ufshcd_err_handler started')" != 0 ]; }
snap() { echo "$(date +%T) $1 cur=$(cat $B/current_now) avg=$(cat $B/current_avg) v=$(cat $B/voltage_now) bt=$(cat $B/temp) c2a=$(cp2ap) ufs=$(grep -vc ': 0$' $U)" >> $O; }
med5() { tail -5 $O | sed 's/.* cur=\([-0-9]*\) .*/\1/' | sort -n | sed -n 3p; }
phase() { n=$1; tag=$2; i=0; while [ $i -lt $n ]; do snap "$tag-$i"; sleep 1; i=$((i+1)); done; }
phase 150 A
BASEMED=$(sed -n '/ A-/p' $O | tail -60 | sed 's/.* cur=\([-0-9]*\) .*/\1/' | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')
echo "BASELINE_MEDIAN_cur=$BASEMED uA" >> $O
echo 1 > $L/pda_active; echo "pda_active=1 rc=$?" >> $O
echo 1 > $L/gpio_on; RC=$?; echo "gpio_on rc=$RC" >> $O
STOP=""
if [ $RC = 0 ]; then
  i=0
  while [ $i -lt 60 ]; do
    sleep 1; i=$((i+1)); snap "B-$i"
    ufsbad && { STOP="UFS"; break; }
    [ "$(cat $B/temp)" -gt 450 ] && { STOP="BATTEMP"; break; }
    if [ $i -ge 5 ]; then M=$(med5); [ $((BASEMED - M)) -gt 300000 ] && { STOP="CURRENT_MEDIAN"; break; }; fi
  done
fi
echo "STOPREASON=${STOP:-none-at-60s}" >> $O
echo 1 > $L/gpio_off; echo "gpio_off rc=$?" >> $O
sleep 2; snap "off+2"
if [ "$(cp2ap)" = 0 ]; then echo 0 > $L/pda_active; echo "pda_active=0 rc=$?" >> $O; else echo "CP2AP STILL HIGH: pda_active NOT lowered, do not reboot" >> $O; fi
phase 120 C
phase 120 D
echo DONE >> $O
