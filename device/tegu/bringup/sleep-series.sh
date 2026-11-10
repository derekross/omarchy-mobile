#!/bin/bash
# SPDX-License-Identifier: MIT
# 2026-11-07 link-wait series: N RTC-woken systemd sleeps of S s, UFS at
# spm_lvl 5 (device powered down, link off), CPU core power-down as WFI says
# (WFI=1: state1 disabled, WFI-only; WFI=0: as the kernel ships). Wi-Fi kept,
# the NFC hook stops polling, console kept, cable in, modem not started this
# boot. Records each sleep's RTC length, dmesg length, wake IRQ, UFS and ACPM
# errors, and the link-wait lines (a slow wake rather than a dead one).
N=${N:-300}; S=${S:-60}; L=${L:-/var/log/omamobile/sleep-linkwait-20261107.log}; U=/sys/devices/platform/soc/13200000.ufs
mkdir -p /var/log/omamobile; : > $L
uid=$(id -u mobile)
hy() { runuser -u mobile -- env XDG_RUNTIME_DIR=/run/user/$uid HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/$uid/hypr | head -1) hyprctl dispatch "hl.dsp.dpms({ action = \"$1\" })" >/dev/null 2>&1; }
echo N > /sys/module/printk/parameters/console_suspend
systemctl is-active -q omamobile-modem && { echo "the modem is up: stop" >> $L; exit 1; }
# The cpuidle sleep hook (omarchy-mobile#591; an earlier hook of this name was withdrawn in #255): when it is
# installed and its keep flag is absent, every sleep of the series runs in WFI whatever WFI= says. Noted, not refused.
if [ -e /usr/lib/systemd/system-sleep/omamobile-tegu-cpuidle ]; then echo "cpuidle hook installed, keep flag $([ -e /etc/omamobile/cpuidle-keep-across-sleep ] && echo present || echo absent)" >> $L; fi
# The modem boot unit's state is put back as it was found, not forced on.
modem_unit_before=$(systemctl is-enabled omamobile-tegu-modem-boot.service 2>/dev/null)
state1_before=$(cat /sys/devices/system/cpu/cpu0/cpuidle/state1/disable)
# RPM (default: as found): UFS rpm_lvl for the run. Experiment #92 runs with 1
# (device active, link hibern8 in runtime suspend) so a VCC that is no longer
# always-on is cut only by the system suspend, not by every idle period.
rpm_before=$(cat $U/rpm_lvl)
restore() {
  for f in /sys/devices/system/cpu/cpu*/cpuidle/state1/disable; do echo $state1_before > $f; done
  echo 5 > $U/spm_lvl
  echo $rpm_before > $U/rpm_lvl
  [ "$modem_unit_before" = enabled ] && systemctl enable omamobile-tegu-modem-boot.service >/dev/null 2>&1
  echo "restored: spm_lvl $(cat $U/spm_lvl), state1 disable $state1_before, modem boot unit $(systemctl is-enabled omamobile-tegu-modem-boot.service 2>/dev/null) (was $modem_unit_before)" >> $L
}
trap restore EXIT
for f in /sys/devices/system/cpu/cpu*/cpuidle/state1/disable; do echo ${WFI:-1} > $f; done
echo 5 > $U/spm_lvl
echo ${RPM:-$rpm_before} > $U/rpm_lvl
echo "$(uname -v): rpm_lvl $(cat $U/rpm_lvl) (was $rpm_before), ufs-vcc always-on: $([ -e /proc/device-tree/regulator-ufs-vcc/regulator-always-on ] && echo yes || echo no), spm_lvl $(cat $U/spm_lvl) ($(cat $U/spm_target_dev_state)/$(cat $U/spm_target_link_state)), state1 disable $(cat /sys/devices/system/cpu/cpu*/cpuidle/state1/disable | tr -d '\n'), modem boot unit $modem_unit_before, $(uname -r)" >> $L
[ "$(cat $U/spm_lvl)" = 5 ] || { echo "spm_lvl didn't take: stop" >> $L; exit 1; }
for c in $(seq 1 $N); do
  dmesg -C
  hy disable
  r0=$(cat /sys/class/rtc/rtc0/since_epoch)
  rtcwake -m no -s $S >/dev/null || { echo "rtcwake could not arm the alarm: stop" >> $L; hy enable; exit 1; }
  # A keep-awake block inhibitor left by a push script (x-awake) would refuse every sleep. It is
  # released here, by the series itself and only once the first alarm is armed: released by the
  # starter before a start that then failed, it left the palmtop to the shell's auto-sleep with
  # no alarm, until a key press (2026-11-10).
  [ "$c" = 1 ] && systemctl stop x-awake 2>/dev/null
  ok0=$(cat /sys/power/suspend_stats/success)
  systemctl suspend
  sleep 20
  hy enable
  # A sleep that never started (a block inhibitor held, a masked target) must not count as a cycle
  [ "$(cat /sys/power/suspend_stats/success)" != "$ok0" ] || { echo "cycle $c: no suspend happened (an inhibitor or a masked sleep target?): stop" >> $L; exit 1; }
  en=$(dmesg | grep -m1 "PM: suspend entry" | sed -E "s/^\[ *([0-9.]+)\].*/\1/"); ex=$(dmesg | grep -m1 "PM: suspend exit" | sed -E "s/^\[ *([0-9.]+)\].*/\1/")
  echo "cycle $c $(date +%T): rtc $(( $(cat /sys/class/rtc/rtc0/since_epoch) - r0 - 20 )) s, dmesg $(awk -v a=$en -v b=$ex 'BEGIN{printf "%.1f", b-a}') s, wake irq $(cat /sys/power/pm_wakeup_irq 2>/dev/null), ufs $(dmesg | grep -cE "link startup failed|Host init failed|I/O error"), linkfail $(dmesg | grep -c "startup=1"), linkwait $(dmesg | grep -c "link-wait:"), acpm $(dmesg | grep -c "Timeout! ch"), oops $(dmesg | grep -c "Internal error"), spm $(cat $U/spm_lvl), c2-s2idle $(cat /sys/devices/system/cpu/cpu0/cpuidle/state1/s2idle/usage 2>/dev/null) c2-run $(cat /sys/devices/system/cpu/cpu0/cpuidle/state1/usage 2>/dev/null), ok $(cat /sys/power/suspend_stats/success) fail $(cat /sys/power/suspend_stats/fail)" >> $L
  dmesg | grep -E "link-wait:|startup=1|link startup failed|Host init failed" | head -40 >> $L
  sync
  [ "$(dmesg | grep -cE "link startup failed|Host init failed|I/O error")" = 0 ] || { echo "UFS errors: stop" >> $L; break; }
  [ "$(dmesg | grep -c "Internal error")" = 0 ] || { echo "kernel oops: stop" >> $L; dmesg | grep -A30 "Internal error" >> $L; break; }
  sleep 5
done
echo done >> $L
