#!/bin/sh
# SPDX-License-Identifier: MIT
# Test only, as run on the 8 Pro on 2026-11-07 (see device/husky/MODEM-PLAN.md); this note and the SPDX line are the only changes.
L=/sys/kernel/debug/cpif_test; U=/sys/kernel/debug/ufshcd/13200000.ufs/stats; O=/root/s5b.log
: > $O
snap() { echo "$(date +%T.%N | cut -c1-12) $1 $(awk '{printf "%s=%s ",$1,$2}' $L/lines) ufs=$(grep -vc ': 0$' $U) errh=$(dmesg | grep -c 'ufshcd_err_handler started') bat=$(cat /sys/class/power_supply/*battery*/capacity)% bt=$(cat /sys/class/power_supply/*battery*/temp)" >> $O; }
snap pre
echo 1 > $L/gpio_on; echo "gpio_on rc=$?" >> $O
i=0
while [ $i -lt 55 ]; do
  sleep 1; i=$((i+1)); snap "on+$i"
  if [ "$(grep -vc ': 0$' $U)" != 0 ]; then echo "STOP-UFS-COUNTER" >> $O; break; fi
done
echo 1 > $L/gpio_off; echo "gpio_off rc=$?" >> $O
for t in 1 5 10 30 60; do
  sleep $([ $t = 1 ] && echo 1 || echo 5); snap "off+$t"
done
echo DONE >> $O
