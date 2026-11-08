#!/bin/bash
# Link-wait series loop (2026-11-07): runs the sleep series on the palmtop,
# polls it every 20 s; a dead-storage wake is captured (kernel journal with
# the link-wait lines and the UFS register dump) and recovered with sysrq,
# and the series restarts, at most MAXREC times; a silent hang messages Dave
# and stops. Dave gets a count every 25 good wakes.
cd /home/dave/git/omarchy-mobile
PS=tools/phone-ssh; H=logs/tegu-linkwait-20261107; L=/var/log/omamobile/sleep-linkwait-20261107.log
MAXREC=${MAXREC:-3}; WFI=${WFI:-1}; CRUMBS=${CRUMBS:-logs/tegu-sleep-crumbs-20261104/tegu-sleep-crumbs.ko}
send() { /home/dave/.local/bin/ask-w4ho "$1" >/dev/null 2>&1; echo "$(date +%T) sent: $1" >> $H/loop.log; }
log() { echo "$(date +%T) $*" >> $H/loop.log; }
start_series() {
  for i in $(seq 40); do $PS --fresh true 2>/dev/null && break; sleep 10; done
  timeout 30 $PS --fresh "cat $L 2>/dev/null" > $H/series-before-run$run.log 2>/dev/null
  # Breadcrumbs v2 (logs/tegu-sleep-crumbs-20261104): a stage code in the PMIC
  # RTC's unused alarm at each suspend and resume phase; its load line names
  # the last boot's last stage. Unloaded again unless its read-back selftest passes.
  if [[ -f $CRUMBS ]]; then
    $PS --fresh 'cat > /root/tegu-sleep-crumbs.ko' < $CRUMBS
    timeout 30 $PS --fresh 'rmmod tegu_sleep_crumbs 2>/dev/null; insmod /root/tegu-sleep-crumbs.ko 2>&1; sleep 1; dmesg | grep tegu-sleep-crumbs | tail -3; dmesg | grep tegu-sleep-crumbs | tail -2 | grep -q "selftest ok" || { rmmod tegu_sleep_crumbs 2>/dev/null; echo crumbs unloaded; }' >> $H/crumbs.log 2>&1
    log "crumbs: $(tail -3 $H/crumbs.log | tr '\n' ' ' | cut -c1-300)"
  fi
  $PS --fresh 'cat > /root/sleep-linkwait.sh' < device/tegu/bringup/sleep-series.sh
  # The first sleep waits for the graphical session: a suspend while the
  # shell is still starting after a boot left the session closed and the
  # splash on the screen (2026-11-07 13:16).
  $PS --fresh 'systemctl unmask sleep.target suspend.target >/dev/null 2>&1; for i in $(seq 36); do [ -d /run/user/1000/hypr ] && pgrep -x Hyprland >/dev/null && break; sleep 5; done; echo "hyprland after boot: $(pgrep -x Hyprland >/dev/null && echo up || echo not up), uptime $(cut -d. -f1 /proc/uptime) s"; systemd-run --unit=x-audio-loop --wait -p TimeoutStartSec=300 /usr/local/bin/omamobile-tegu-audio-up >/dev/null 2>&1; systemctl reset-failed x-sleep-linkwait 2>/dev/null; sleep 30; systemd-run --unit=x-sleep-linkwait -E WFI='"$WFI"' -E RPM='"${RPM:-}"' bash /root/sleep-linkwait.sh' >> $H/loop.log 2>&1
  log "series started (run $run, WFI=$WFI)"
}
run=1; total=0; captures=0; last25=0
# ATTACH=1: the series is already running on the palmtop; watch it without restarting it.
[[ ${ATTACH:-0} == 1 ]] && log "attached to the running series" || start_series
last_ok=$(date +%s)
while true; do
  # The palmtop's USB link is up for only about 9 s of each 67 s cycle (it
  # comes back some 15 s after the wake), so ping once a second until it
  # answers, then ask at once; one try per 20 s missed the window for minutes.
  out=; for p in $(seq 240); do ping -c1 -W1 172.16.42.1 >/dev/null 2>&1 && { out=$(timeout 12 $PS --fresh "grep -c '^cycle' $L 2>/dev/null; systemctl is-active x-sleep-linkwait; case \"\$(< /proc/mounts)\" in *emergency_ro*) echo disk-dead;; *) echo disk-ok;; esac; grep -c 'link-wait:' $L 2>/dev/null; true" 2>/dev/null); [[ -n $out ]] && break; }; sleep 1; done
  if [[ -n $out ]]; then
    last_ok=$(date +%s)
    n=$(sed -n 1p <<<"$out"); st=$(sed -n 2p <<<"$out"); disk=$(sed -n 3p <<<"$out"); lw=$(sed -n 4p <<<"$out")
    # A poll cut short (the palmtop fell asleep mid-command) is not a verdict:
    # judge only a complete answer. Otherwise 54 good wakes were lost to a
    # "clean reboot" on empty fields (2026-11-07 09:40).
    if ! [[ $st =~ ^(active|activating|inactive|failed)$ && $disk =~ ^disk-(ok|dead)$ ]]; then log "incomplete poll ignored: '$(tr '\n' '|' <<<"$out")'"; sleep 20; continue; fi
    [[ $n =~ ^[0-9]+$ ]] || n=0; [[ $lw =~ ^[0-9]+$ ]] || lw=0
    if (( total + n >= last25 + 25 )); then last25=$(( (total + n) / 25 * 25 )); send "Palmtop sleep series: $((total + n)) good wakes so far, $lw slow (link-wait) wakes, $captures dead-storage wakes."; fi
    if [[ $st == inactive && $n -ge 300 ]]; then
      log "run $run finished: $n cycles, $lw link-wait wakes"; timeout 30 $PS --fresh "cat $L" > $H/series-run$run.log 2>&1
      send "Palmtop sleep series done: $((total + n)) good wakes, $lw slow (link-wait) wakes, $captures dead-storage wakes."; exit 0
    fi
    if [[ $disk == disk-dead || ( $st != active && $st != activating ) ]]; then
      captures=$((captures + 1)); total=$((total + n))
      log "run $run ended after $n ($st, $disk): capturing"
      # Host-side state of a dead-storage wake (the kernel is alive, the disk is not):
      # the UFS pads' pin controller (one controller only, never */pins), the UFS
      # clocks, the regulators, the GPIOs, the UFS host's sysfs. Read-only.
      if [[ $disk == disk-dead ]]; then
        timeout 90 $PS --fresh 'U=/sys/bus/platform/devices/13200000.ufs; echo "== pinctrl hsi2ufs"; cat /sys/kernel/debug/pinctrl/13060000.pinctrl-samsung-pinctrl/pins 2>&1 | head -40; echo "== pinconf hsi2ufs"; cat /sys/kernel/debug/pinctrl/13060000.pinctrl-samsung-pinctrl/pinconf-pins 2>&1 | head -40; echo "== clk ufs/hsi2"; grep -iE "ufs|hsi2" /sys/kernel/debug/clk/clk_summary 2>&1 | head -40; echo "== regulators"; cat /sys/kernel/debug/regulator/regulator_summary 2>&1 | head -40; echo "== gpio"; cat /sys/kernel/debug/gpio 2>&1 | grep -iE "ufs|gpp0|gph5" ; echo "== ufs sysfs"; for a in spm_lvl rpm_lvl power_info/\*; do echo "$a: $(cat $U/$a 2>&1 | tr "\n" " ")"; done; echo "== phy"; cat /sys/kernel/debug/regmap/13204000.phy/registers 2>/dev/null | head -5; echo "== last kmsg"; dmesg | tail -60' > $H/capture-$captures-hoststate.txt 2>&1
        log "host state captured ($(wc -l < $H/capture-$captures-hoststate.txt) lines)"
      fi
      timeout 60 $PS --fresh "journalctl -b -k --no-pager -o short-monotonic | tail -2500" > $H/capture-$captures-k.txt 2>&1
      timeout 20 $PS --fresh "dmesg | tail -600" > $H/capture-$captures-dmesg.txt 2>&1
      timeout 20 $PS --fresh "cat $L" > $H/capture-$captures-series.log 2>&1
      # A palmtop that already rebooted on its own (a panic or a watchdog: the
      # test kernels panic on a failed UFS restore) is not rebooted again.
      up=$(timeout 12 $PS --fresh 'cut -d. -f1 /proc/uptime' 2>/dev/null)
      if [[ $up =~ ^[0-9]+$ && $up -lt 600 ]]; then
        log "the palmtop rebooted on its own ${up}s ago: no reboot from here"
        # Its last console (ramoops, copied by x-keep-ramoops at boot) and the reset reason.
        timeout 60 $PS --fresh 'grep bootreason /proc/bootconfig; f=$(ls -t /var/log/omamobile/ramoops/console-* 2>/dev/null | head -1); echo "console: $f"; cat "$f" 2>/dev/null' > $H/capture-$captures-ramoops.txt 2>&1
        log "ramoops saved ($(wc -l < $H/capture-$captures-ramoops.txt) lines, $(head -1 $H/capture-$captures-ramoops.txt))"
      elif [[ $disk == disk-dead ]]; then timeout 15 $PS --fresh 'echo 1 > /proc/sys/kernel/sysrq; echo b > /proc/sysrq-trigger' >/dev/null 2>&1; log "sysrq reboot"
      else timeout 15 $PS --fresh 'systemctl --no-block reboot' >/dev/null 2>&1; log "clean reboot"; fi
      (( captures >= MAXREC )) && { send "Palmtop sleep series: $captures dead-storage wakes (the cap), stopping. $total good wakes in total; captures saved."; log "cap reached: stop"; exit 0; }
      sleep 90; run=$((run + 1)); start_series; last_ok=$(date +%s)
    fi
  fi
  if (( $(date +%s) - last_ok > 900 )); then send "Palmtop sleep series: no answer for 15 minutes after $((total + n)) good wakes and $captures dead-storage wakes. Needs Power + Volume Up whenever you're up; no rush."; log "silent hang: stop"; exit 0; fi
  sleep 20
done
