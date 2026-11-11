#!/bin/sh
# SPDX-License-Identifier: MIT
# Test only, as run on the 8 Pro on 2026-11-07 (see device/husky/MODEM-PLAN.md); this note and the SPDX line are the only changes.
# S5e v2 (TEST ONLY): battery-only current, isolating pda_active from gpio_on. Run as: nohup setsid sh /root/s5e.sh &   Log: /root/s5e.log
# A 90 s base | E1 pda_active ALONE 30 s | B 60 s | E2 gpio_on, pda LOW 60 s | C 60 s | E3 pda=1 then gpio_on 60 s | D 60 s | E1b (replicate) 30 s | E 60 s
# Fixes after review: trap (safe_off on INT/TERM/HUP), abort ends the run, CP2AP-high stops, pda verified low before powered steps,
# UFS error count compared to the count at start, tighter E1 rule (150 mA), screen state in every sample, per-phase medians at the end.
L=/sys/kernel/debug/cpif_test; U=/sys/kernel/debug/ufshcd/13200000.ufs/stats; O=/root/s5e.log; B=/sys/class/power_supply/max170xx_battery
: > $O
N0=$(dmesg | grep -c 'ufshcd_err_handler started')
ABORT=""
hw() { echo "$2" > $L/$1; }
cp2ap() { awk '/^CP2AP_/ {s+=$2} END {print s+0}' $L/lines; }
ap2cp() { awk '/^AP2CP_/ {s+=$2} END {print s+0}' $L/lines; }
pda() { awk '/^AP2CP_AP_ACTIVE/ {print $2}' $L/lines; }
ufsbad() { [ "$(grep -vc ': 0$' $U)" != 0 ] || [ "$(dmesg | grep -c 'ufshcd_err_handler started')" != "$N0" ]; }
snap() { echo "$(date +%T) $1 cur=$(cat $B/current_now) avg=$(cat $B/current_avg) v=$(cat $B/voltage_now) bt=$(cat $B/temp) c2a=$(cp2ap) a2c=$(ap2cp) pda=$(pda) ufs=$(grep -vc ': 0$' $U) bl=$(cat /sys/class/backlight/*/bl_power | head -1)" >> $O; }
med5() { tail -5 $O | sed 's/.* cur=\([-0-9]*\) .*/\1/' | sort -n | sed -n 3p; }
phase() { n=$1; tag=$2; i=0; while [ $i -lt $n ]; do snap "$tag-$i"; sleep 1; i=$((i+1)); done; }
safe_off() {
  hw gpio_off 1; echo "gpio_off rc=$?" >> $O; sleep 2; snap "off+2"
  if [ "$(cp2ap)" = 0 ]; then hw pda_active 0; echo "pda_active=0 rc=$?" >> $O
  else echo "CP2AP STILL HIGH: pda_active NOT lowered, do not reboot" >> $O; ABORT="CP2AP_HIGH"; fi
  [ "$(pda)" = 0 ] || [ "$ABORT" = "CP2AP_HIGH" ] || ABORT="PDA_NOT_LOW"
}
trap 'echo TRAP >> $O; safe_off; echo ABORTED-BY-SIGNAL >> $O; exit 1' INT TERM HUP
# powered TAG SECONDS THRESHOLD_uA : the enabling write(s) were done by the caller
powered() { tag=$1; n=$2; th=$3; STOP=""; i=0
  while [ $i -lt $n ]; do sleep 1; i=$((i+1)); snap "$tag-$i"
    ufsbad && { STOP=UFS; break; }
    [ "$(cat $B/temp)" -gt 450 ] && { STOP=BATTEMP; break; }
    if [ $i -ge 5 ]; then M=$(med5); [ $((BASEMED - M)) -gt $th ] && { STOP=CURRENT_MEDIAN; break; }; fi
  done
  echo "STOPREASON($tag)=${STOP:-none-at-${n}s}" >> $O; [ -n "$STOP" ] && ABORT="$tag:$STOP"; }
finish() { phase 30 Z; echo "ABORTED=$ABORT" >> $O; summary; echo DONE >> $O; exit 1; }
summary() { echo "--- per-phase median cur (uA) and n" >> $O
  for ph in A E1 B E2 C E3 D E1b E; do grep -E "^[0-9:]+ $ph-[0-9]+ " $O | sed 's/.* cur=\([-0-9]*\) .*/\1/' | sort -n | awk -v ph=$ph '{a[NR]=$1} END { if (NR) printf "%s median=%d n=%d\n", ph, a[int((NR+1)/2)], NR }' >> $O; done; }
echo "start: bl=$(cat /sys/class/backlight/*/bl_power | head -1) N0=$N0 status=$(cat $B/status)" >> $O
[ "$(cat $B/status)" = "Discharging" ] || { echo "NOT DISCHARGING: refusing" >> $O; ABORT=START_STATUS; finish; }
[ "$(cat $B/temp)" -le 450 ] || { echo "BATTERY HOT: refusing" >> $O; ABORT=START_TEMP; finish; }
[ "$(ap2cp)$(cp2ap)" = "00" ] || { echo "LINES NOT ALL 0: refusing" >> $O; ABORT=START_LINES; finish; }
ufsbad && { echo "UFS NOT CLEAN: refusing" >> $O; ABORT=START_UFS; finish; }
phase 90 A
BASEMED=$(sed -n '/ A-/p' $O | tail -60 | sed 's/.* cur=\([-0-9]*\) .*/\1/' | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')
echo "BASELINE_MEDIAN_cur=$BASEMED uA" >> $O
[ "$(pda)" = 0 ] || { echo "pda not low at start" >> $O; ABORT=START; finish; }
# E1: pda_active alone (tight rule 150 mA)
hw pda_active 1; echo "E1 pda_active=1 rc=$?" >> $O
if [ "$(pda)" = 1 ] && [ "$(ap2cp)" = 1 ]; then powered E1 30 150000; else echo "E1 READBACK MISMATCH" >> $O; ABORT="E1:READBACK"; fi
hw pda_active 0; echo "E1 pda_active=0 rc=$?" >> $O; [ -z "$ABORT" ] || finish
[ "$(pda)" = 0 ] || { ABORT="PDA_NOT_LOW_AFTER_E1"; finish; }
phase 60 B
# E2: gpio_on with pda low
[ "$(pda)" = 0 ] || { ABORT="PDA_NOT_LOW_BEFORE_E2"; finish; }
hw gpio_on 1; RC=$?; echo "E2 gpio_on(pda low) rc=$RC" >> $O
if [ "$(ap2cp)" = 4 ] && [ "$(pda)" = 0 ]; then powered E2 60 400000; else echo "E2 READBACK MISMATCH (ap2cp=$(ap2cp) pda=$(pda))" >> $O; ABORT="E2:READBACK"; fi
safe_off; [ -z "$ABORT" ] || finish
phase 60 C
# E3: pda_active then gpio_on (the S5d order)
hw pda_active 1; echo "E3 pda_active=1 rc=$?" >> $O
hw gpio_on 1; RC=$?; echo "E3 gpio_on rc=$RC" >> $O
if [ "$(ap2cp)" = 5 ] && [ "$(pda)" = 1 ]; then powered E3 60 400000; else echo "E3 READBACK MISMATCH (ap2cp=$(ap2cp) pda=$(pda))" >> $O; ABORT="E3:READBACK"; fi
safe_off; [ -z "$ABORT" ] || finish
phase 60 D
# E1b: replicate of E1
hw pda_active 1; echo "E1b pda_active=1 rc=$?" >> $O
if [ "$(pda)" = 1 ] && [ "$(ap2cp)" = 1 ]; then powered E1b 30 150000; else echo "E1b READBACK MISMATCH" >> $O; ABORT="E1b:READBACK"; fi
hw pda_active 0; echo "E1b pda_active=0 rc=$?" >> $O; [ -z "$ABORT" ] || finish
phase 60 E
summary
echo DONE >> $O
