#!/bin/bash
# SPDX-License-Identifier: MIT
# 2026-11-07 link-wait series: N RTC-woken systemd sleeps of S s, UFS at
# spm_lvl 5 (device powered down, link off), CPU core power-down as WFI says
# (WFI=1: state1 disabled, WFI-only; WFI=0: as the kernel ships). Wi-Fi kept,
# the NFC hook stops polling, console kept, cable in, modem not started this
# boot. Records each sleep's RTC length, dmesg length, wake IRQ, UFS and ACPM
# errors, and the link-wait lines (a slow wake rather than a dead one).
N=${N:-300}; S=${S:-60}; W=${W:-20}; L=${L:-/var/log/omamobile/sleep-linkwait-20261107.log}; U=/sys/devices/platform/soc/13200000.ufs
mkdir -p /var/log/omamobile; : > $L
# Debugging a no-wake (2026-11-10; off unless asked for). PMDEBUG=1 turns pm_print_times and pm_debug_messages
# on, so the console names each device's suspend callback as it starts and returns (the maintainer's pointer,
# kernel #224), and makes an RCU stall a panic (kernel.panic_on_rcu_stall), which panic=10 turns into a reboot
# with the console in pstore. TRACE=1, on a kernel with the function tracer, also runs function and event
# tracing in small per-CPU buffers that the panic dumps to the console. The dump has to fit the 2 MB ramoops
# console together with the sleep's own callback lines: it prints oldest first, and 24 KB per CPU is about 900
# calls a core and under 1 MB of text for eight (measure it with an awake sysrq-c before a series).
# Either one first fills the kernel's log ring: three test crashes on the tracing build (sysrq-c, awake) lost
# everything after record 4096 since boot, the trace dump's tail and the "Rebooting" line with it, when the
# ring's first wrap fell inside the panic; with the ring filled beforehand the fourth kept the whole dump.
if [ "${PMDEBUG:-0}" = 1 ] || [ "${TRACE:-0}" = 1 ]; then
  echo on > /proc/sys/kernel/printk_devkmsg 2>/dev/null; for i in $(seq 1 5000); do echo "ring fill $i" > /dev/kmsg; done
  echo 1 > /sys/power/pm_print_times; echo 1 > /sys/power/pm_debug_messages
  echo 1 > /proc/sys/kernel/panic_on_rcu_stall
  # systemd's runtime watchdog (10 s on the palmtop) would reset a panicking kernel before the dump and the
  # panic's own reboot are through (32 s in the test that kept its dump): off for the run, put back at the end.
  WD=org.freedesktop.systemd1; wd_before=$(busctl get-property $WD /org/freedesktop/systemd1 $WD.Manager RuntimeWatchdogUSec | awk '{print $2}')
  busctl set-property $WD /org/freedesktop/systemd1 $WD.Manager RuntimeWatchdogUSec t 0
fi
if [ "${TRACE:-0}" = 1 ] && [ -d /sys/kernel/tracing ]; then
  T=/sys/kernel/tracing; mountpoint -q $T || mount -t tracefs nodev $T
  echo 0 > $T/tracing_on; echo ${TRACE_KB:-24} > $T/buffer_size_kb; echo function > $T/current_tracer
  for e in sched/sched_switch irq/irq_handler_entry irq/irq_handler_exit ipi power/cpu_idle power/suspend_resume timer/hrtimer_expire_entry; do echo 1 > $T/events/$e/enable; done
  echo 1 > $T/tracing_on; echo 1 > /proc/sys/kernel/ftrace_dump_on_oops
fi
echo "debug: pm_print_times $(cat /sys/power/pm_print_times), pm_debug_messages $(cat /sys/power/pm_debug_messages), panic_on_rcu_stall $(cat /proc/sys/kernel/panic_on_rcu_stall), panic timeout $(cat /proc/sys/kernel/panic) s, tracer $(cat /sys/kernel/tracing/current_tracer 2>/dev/null || echo none) $(cat /sys/kernel/tracing/buffer_size_kb 2>/dev/null) KB per CPU on $(cat /sys/kernel/tracing/tracing_on 2>/dev/null), ftrace_dump_on_oops $(cat /proc/sys/kernel/ftrace_dump_on_oops 2>/dev/null)" >> $L
uid=$(id -u mobile)
hy() { runuser -u mobile -- env XDG_RUNTIME_DIR=/run/user/$uid HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/$uid/hypr | head -1) hyprctl dispatch "hl.dsp.dpms({ action = \"$1\" })" >/dev/null 2>&1; }
echo N > /sys/module/printk/parameters/console_suspend
{ systemctl is-active -q omamobile-modem || [ -d /sys/module/cpif ]; } && { echo "the modem is up: stop" >> $L; exit 1; }
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
  [ -n "$wd_before" ] && busctl set-property org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager RuntimeWatchdogUSec t $wd_before
  [ -n "$INH" ] && kill $INH 2>/dev/null
  for f in /sys/devices/system/cpu/cpu*/cpuidle/state1/disable; do echo $state1_before > $f; done
  echo 5 > $U/spm_lvl
  echo $rpm_before > $U/rpm_lvl
  [ "$modem_unit_before" = enabled ] && systemctl enable omamobile-tegu-modem-boot.service >/dev/null 2>&1
  echo "restored: spm_lvl $(cat $U/spm_lvl), state1 disable $state1_before, modem boot unit $(systemctl is-enabled omamobile-tegu-modem-boot.service 2>/dev/null) (was $modem_unit_before)" >> $L
}
trap restore EXIT
# Only the series' own sleeps, each with its alarm, may happen during a run. The shell's auto-sleep
# (omamobile-sleepd) puts a dark resume back to sleep 5 s after it once the lock is secure and no SSH session
# is open, with no alarm: it did between two cycles on 2026-11-10, and the palmtop slept nine and a half
# hours, until the Power key, which from the laptop looked like a no-wake. So the series holds a block
# inhibitor of its own for the whole run (a push script's x-awake has a time limit) and sleeps past it
# with "systemctl suspend -i"; the modem's inhibitor is not passed that way, since the series refuses
# to start with the modem up.
systemd-inhibit --what=sleep --who=sleep-series --why="only the series' own sleeps, each with an alarm" --mode=block sleep infinity &
INH=$!
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
  ok0=$(cat /sys/power/suspend_stats/success)
  systemctl suspend -i
  # logind holds a sleep back while a delay inhibitor is taken, up to 15 s here: NetworkManager did at the 90th
  # sleep of the first run (2026-11-10), the sleep began 15 s after the request, and a fixed wait of 10 s (W=10) took that
  # for "no suspend happened" while the palmtop slept and woke. So wait for the sleep itself, up to 45 s, and
  # give S at least 30 s, so the alarm can't fire before a held-back sleep begins.
  for i in $(seq 90); do [ "$(cat /sys/power/suspend_stats/success)" != "$ok0" ] && break; sleep 0.5; done
  sleep $W
  hy enable
  # A sleep that never started (a block inhibitor held, a masked target) must not count as a cycle
  [ "$(cat /sys/power/suspend_stats/success)" != "$ok0" ] || { echo "cycle $c: no suspend happened (an inhibitor or a masked sleep target?): stop" >> $L; exit 1; }
  en=$(dmesg | grep -m1 "PM: suspend entry" | sed -E "s/^\[ *([0-9.]+)\].*/\1/"); ex=$(dmesg | grep -m1 "PM: suspend exit" | sed -E "s/^\[ *([0-9.]+)\].*/\1/")
  echo "cycle $c $(date +%T): rtc $(( $(cat /sys/class/rtc/rtc0/since_epoch) - r0 - W )) s, dmesg $(awk -v a=$en -v b=$ex 'BEGIN{printf "%.1f", b-a}') s, wake irq $(cat /sys/power/pm_wakeup_irq 2>/dev/null), ufs $(dmesg | grep -cE "link startup failed|Host init failed|I/O error"), linkfail $(dmesg | grep -c "startup=1"), linkwait $(dmesg | grep -c "link-wait:"), acpm $(dmesg | grep -c "Timeout! ch"), oops $(dmesg | grep -c "Internal error"), spm $(cat $U/spm_lvl), c2-s2idle $(cat /sys/devices/system/cpu/cpu0/cpuidle/state1/s2idle/usage 2>/dev/null) c2-run $(cat /sys/devices/system/cpu/cpu0/cpuidle/state1/usage 2>/dev/null), ok $(cat /sys/power/suspend_stats/success) fail $(cat /sys/power/suspend_stats/fail)" >> $L
  dmesg | grep -E "link-wait:|startup=1|link startup failed|Host init failed" | head -40 >> $L
  sync
  [ "$(dmesg | grep -cE "link startup failed|Host init failed|I/O error")" = 0 ] || { echo "UFS errors: stop" >> $L; break; }
  [ "$(dmesg | grep -c "Internal error")" = 0 ] || { echo "kernel oops: stop" >> $L; dmesg | grep -A30 "Internal error" >> $L; break; }
  sleep 5
done
echo done >> $L
