#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-sleepd against stand-ins: a fake clock that only "sleep" moves,
# a fake /sys and /proc, and stubs for systemctl, hyprctl, omarchy-shell,
# omarchy-toggle-enabled, ss, busctl and pactl. "systemctl suspend" counts
# a successful suspend in the fake suspend_stats and moves the clock ten
# minutes on, as a real sleep would.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
F=$t/bin; mkdir -p "$F" "$t/sys/power/suspend_stats" "$t/sys/class/backlight/panel" "$t/proc" "$t/home"
fail() { printf 'not ok - %s\n' "$1" >&2; sed 's/^/# /' "$t/log" "$t/out" >&2 2>/dev/null; exit 1; }
fake() { printf '#!/bin/bash\nT=%q\n%s\n' "$t" "$2" >"$F/$1"; chmod +x "$F/$1"; }

fake sleep 'echo $(( $(cat "$T/clock") + ${1%%.*} )) >"$T/clock"
# "the user presses power" at a given time: the watcher gets its signal.
if [[ -f $T/now_at ]] && (( $(cat "$T/clock") >= $(cat "$T/now_at") )); then rm -f "$T/now_at"; kill -USR1 $PPID; fi
# "the panel finishes powering off" at a given time.
if [[ -f $T/off_at ]] && (( $(cat "$T/clock") >= $(cat "$T/off_at") )); then rm -f "$T/off_at"; echo 4 >"$T/sys/class/backlight/panel/bl_power"; fi'
fake omarchy-toggle-enabled '[[ $1 == omamobile-sleep && -f $T/toggle ]]'
fake omarchy-hw-display 'echo panel'
fake hyprctl '[[ $1 == monitors ]] && printf "[{\"dpmsStatus\": %s}]\n" "$(cat "$T/dpms")"'
fake omarchy-shell '[[ "$*" == "lock status" ]] && printf "{\"locked\":true,\"secure\":%s}\n" "$(cat "$T/secure")"'
fake ss 'cat "$T/ssh"'
fake busctl 'printf "{\"type\":\"a(ssssuu)\",\"data\":[[%s]]}\n" "$(cat "$T/inhibitors")"'
fake pactl 'cat "$T/sinks"'
fake omamobile-keys 'echo "omamobile-keys $* at $(cat "$T/clock")" >>"$T/log"'
fake systemctl 'echo "systemctl $* at $(cat "$T/clock")" >>"$T/log"
case "$*" in
  suspend)
    echo $(( $(cat "$T/sys/power/suspend_stats/success") + 1 )) >"$T/sys/power/suspend_stats/success"
    cat "$T/wake_irq" 2>/dev/null >"$T/sys/power/pm_wakeup_irq" || echo 145 >"$T/sys/power/pm_wakeup_irq"
    echo $(( $(cat "$T/clock") + 600 )) >"$T/clock"
    [[ -f $T/on_resume ]] && bash "$T/on_resume"
    exit 0 ;;
  "--user --quiet is-active omamobile-sleepd.service") [[ -f $T/active ]] ;;
esac'

# A screen-off, locked phone with nothing holding it awake.
reset() {
  : >"$t/log"; echo 1000 >"$t/clock"; touch "$t/toggle"
  echo 4 >"$t/sys/class/backlight/panel/bl_power"; echo false >"$t/dpms"; echo true >"$t/secure"
  : >"$t/ssh"; : >"$t/inhibitors"
  printf '50\talsa_output.aoc\tPipeWire\ts16le 2ch 48000Hz\tSUSPENDED\n' >"$t/sinks"
  echo 0 >"$t/sys/power/suspend_stats/success"; echo 0 >"$t/sys/power/suspend_stats/fail"
  printf ' 145:          3          0  s2mpg12-pmic   0 Edge      rtc-alarm0\n' >"$t/proc/interrupts"
  printf ' 111:         76          1  gpa10   0 Edge      KEY_POWER\n' >>"$t/proc/interrupts"
  rm -f "$t/wake_irq" "$t/sys/power/pm_wakeup_irq" "$t/on_resume" "$t/now_at" "$t/off_at" "$t/active" "$t/home/.local/state/omarchy/indicators/stay-awake"
}
# Watch until the fake clock reaches 1000 + $1.
watch() {
  env HOME="$t/home" PATH="$F:$PATH" OMAMOBILE_SLEEP_SYSFS="$t/sys" OMAMOBILE_SLEEP_PROCFS="$t/proc" \
    OMAMOBILE_SLEEP_CLOCK="$t/clock" OMAMOBILE_SLEEPD_STOP_AT=$((1000 + $1)) "${@:2}" \
    bash "$here/bin/omamobile-sleepd" >"$t/out" 2>&1
}
sleepd() {
  env HOME="$t/home" PATH="$F:$PATH" OMAMOBILE_SLEEP_SYSFS="$t/sys" OMAMOBILE_SLEEP_PROCFS="$t/proc" \
    OMAMOBILE_SLEEP_CLOCK="$t/clock" bash "$here/bin/omamobile-sleepd" "$@"
}
suspends() { grep -c '^systemctl suspend' "$t/log" || true; }
first_at() { sed -n 's/^systemctl suspend at //p' "$t/log" | head -n 1; }

reset; watch 100
[[ $(suspends) -ge 1 ]] || fail "screen off and locked: it sleeps"
at=$(first_at); ((at >= 1030 && at <= 1034)) || fail "the first sleep comes 30 s after the screen went off (at $at)"
grep -c 'sleeping (screen off and locked for 30 s)' "$t/out" >/dev/null || fail "the sleep is logged with its cause"
reset; watch 100 OMAMOBILE_SLEEP_AFTER_OFF=12
at=$(first_at); ((at >= 1012 && at <= 1016)) || fail "OMAMOBILE_SLEEP_AFTER_OFF sets the wait (at $at)"
reset; watch 100 OMAMOBILE_SLEEP_AFTER_OFF=0
at=$(first_at); ((at >= 1005 && at <= 1009)) || fail "the wait is never under 5 s (at $at)"
echo "ok - sleepd: sleeps once the screen has been off behind a secure lock for OMAMOBILE_SLEEP_AFTER_OFF"

# Each refusal on its own: no "systemctl suspend" in 200 s, and one log line.
refused() { # NAME SETUP...
  reset; eval "$2"; watch 200
  [[ $(suspends) == 0 ]] || fail "$1: no sleep"
}
refused "the toggle is off" 'rm -f "$t/toggle"'
refused "the screen is on" 'echo 0 >"$t/sys/class/backlight/panel/bl_power"; echo true >"$t/dpms"'
refused "the lock isn't secure" 'echo false >"$t/secure"'
refused "an SSH session is open" 'echo "0 0 172.16.42.1:22 172.16.42.2:51234" >"$t/ssh"'
[[ $(grep -c 'not sleeping: an SSH session is open' "$t/out") == 1 ]] || fail "a refusal is logged once, not at every poll"
refused "ss can't answer" 'fake ss "exit 1"'
fake ss 'cat "$T/ssh"'
refused "a block sleep inhibitor" 'echo "[\"sleep\",\"Omarchy Mobile GNSS\",\"A location session is running\",\"block\",0,77]" >"$t/inhibitors"'
grep -c 'not sleeping: a sleep inhibitor is held (Omarchy Mobile GNSS)' "$t/out" >/dev/null || fail "the inhibitor's holder is named"
refused "a block shutdown:sleep inhibitor" 'echo "[\"shutdown:sleep\",\"x\",\"y\",\"block\",0,77]" >"$t/inhibitors"'
refused "a RUNNING sink" 'printf "50\talsa_output.aoc\tPipeWire\ts16le 2ch 48000Hz\tRUNNING\n" >"$t/sinks"'
grep -c 'not sleeping: audio is playing (alsa_output.aoc)' "$t/out" >/dev/null || fail "the playing sink is named"
refused "Stay awake" 'mkdir -p "$t/home/.local/state/omarchy/indicators"; touch "$t/home/.local/state/omarchy/indicators/stay-awake"'
echo "ok - sleepd: never with the toggle off, the screen on, an insecure lock, SSH, an inhibitor, media or Stay awake"

# Delay-mode inhibitors (NetworkManager, the lock) and idle sinks don't count.
reset
echo '["sleep","NetworkManager","NetworkManager needs to turn off networks","delay",0,1014],["sleep","Omarchy","Lock screen before suspend","delay",1000,1184]' >"$t/inhibitors"
printf '50\ta\tPipeWire\ts16le 2ch 48000Hz\tIDLE\n51\tb\tPipeWire\ts16le 2ch 48000Hz\tSUSPENDED\n' >"$t/sinks"
watch 100
[[ $(suspends) -ge 1 ]] || fail "delay inhibitors and idle sinks don't stop sleep"
# The screen read from Hyprland alone (bl_power 0, DPMS off), as on tegu.
reset; echo 0 >"$t/sys/class/backlight/panel/bl_power"; watch 100
[[ $(suspends) -ge 1 ]] || fail "DPMS off counts as screen off"
# An unanswered Hyprland reads as a lit screen.
reset; echo 0 >"$t/sys/class/backlight/panel/bl_power"; echo garbage >"$t/dpms"; watch 100
[[ $(suspends) == 0 ]] || fail "an unreadable screen state never sleeps"
echo "ok - sleepd: delay inhibitors, idle sinks and DPMS-only screens; an unknown screen state stays awake"

# A dark resume (the RTC): back to sleep after the grace, not after 30 s.
reset; watch 700
[[ $(suspends) -ge 2 ]] || fail "a dark resume sleeps again"
second=$(sed -n 's/^systemctl suspend at //p' "$t/log" | sed -n 2p)
first=$(first_at)
((second - (first + 600) >= 5 && second - (first + 600) <= 8)) || fail "the second sleep comes 5 s after the resume (resumed at $((first + 600)), slept at $second)"
grep -c 'resumed, woken by IRQ 145: 3 0 s2mpg12-pmic 0 Edge rtc-alarm0' "$t/out" >/dev/null || fail "the wake IRQ is logged by name"
grep -c 'sleeping (dark resume, 5 s grace)' "$t/out" >/dev/null || fail "the second sleep is logged as a dark resume"
# A power-key wake lights the screen: no sleep after it.
reset; printf 'echo 0 >"%s"; echo true >"%s"\n' "$t/sys/class/backlight/panel/bl_power" "$t/dpms" >"$t/on_resume"; watch 700
[[ $(suspends) == 1 ]] || fail "a wake that lit the screen stays awake"
grep -c '^omamobile-keys' "$t/log" >/dev/null && fail "an RTC wake doesn't light the screen"
# Power woke it: Hyprland never sees that press, so sleepd lights the PIN pad.
reset; echo 111 >"$t/wake_irq"; printf 'echo 0 >"%s"; echo true >"%s"\n' "$t/sys/class/backlight/panel/bl_power" "$t/dpms" >"$t/on_resume"; watch 700
grep -c '^omamobile-keys wake' "$t/log" >/dev/null || fail "a power-key wake asks omamobile-keys to light the PIN pad"
grep -c 'a power-key wake: lighting the lock screen' "$t/out" >/dev/null || fail "the power-key wake is logged"
# A failed suspend is logged and retried no sooner than 30 s later.
reset
fake systemctl 'echo "systemctl $* at $(cat "$T/clock")" >>"$T/log"
[[ $1 == suspend ]] && { echo $(( $(cat "$T/sys/power/suspend_stats/fail") + 1 )) >"$T/sys/power/suspend_stats/fail"; echo 0000:01:00.0 >"$T/sys/power/suspend_stats/last_failed_dev"; }
exit 0'
watch 100
grep -c 'the suspend failed (last failed device: 0000:01:00.0)' "$t/out" >/dev/null || fail "a failed suspend is logged with its device"
mapfile -t ats < <(sed -n 's/^systemctl suspend at //p' "$t/log")
((${#ats[@]} >= 2 && ats[1] - ats[0] >= 30)) || fail "a failed request is retried after 30 s, not at every poll (${ats[*]})"
echo "ok - sleepd: dark resumes sleep again after the grace, power-key wakes stay awake, failures are retried slowly"

# The power key: "now" ends the 30 s wait 2 s after the request.
fake systemctl 'echo "systemctl $* at $(cat "$T/clock")" >>"$T/log"
case "$*" in
  suspend) echo $(( $(cat "$T/sys/power/suspend_stats/success") + 1 )) >"$T/sys/power/suspend_stats/success"; echo $(( $(cat "$T/clock") + 600 )) >"$T/clock" ;;
  "--user --quiet is-active omamobile-sleepd.service") [[ -f $T/active ]] ;;
esac'
reset; echo 1004 >"$t/now_at"; watch 20
at=$(first_at); [[ -n $at ]] && ((at >= 1004 && at <= 1008)) || fail "a power-key request sleeps within about 2 s (at ${at:-never})"
grep -c 'sleeping (power key)' "$t/out" >/dev/null || fail "the power-key sleep is logged as such"
# A request that comes while the panel still reads lit is kept a few seconds.
reset; echo 0 >"$t/sys/class/backlight/panel/bl_power"; echo true >"$t/dpms"; echo 1004 >"$t/now_at"; echo 1008 >"$t/off_at"; watch 25
at=$(first_at); [[ -n $at ]] && ((at >= 1008 && at <= 1012)) || fail "a power-key request survives a panel still powering off (at ${at:-never})"
# A power-key request still waits for the inhibitors.
reset; echo "0 0 172.16.42.1:22 172.16.42.2:51234" >"$t/ssh"; echo 1004 >"$t/now_at"; watch 60
[[ $(suspends) == 0 ]] || fail "a power-key request with SSH open: no sleep"

# "now" from the key handler: nothing with the toggle off; a signal to the
# watcher when it runs; one checked attempt of its own when it doesn't.
reset; rm -f "$t/toggle"; sleepd now
[[ ! -s $t/log ]] || fail "now with the toggle off does nothing"
reset; touch "$t/active"; sleepd now
grep -c 'systemctl --user kill --signal=USR1 --kill-whom=main omamobile-sleepd.service' "$t/log" >/dev/null || fail "now signals the running watcher"
[[ $(suspends) == 0 ]] || fail "now leaves the sleep to the running watcher"
reset; sleepd now >"$t/out"
[[ $(suspends) == 1 ]] || fail "now with no watcher sleeps itself"
reset; echo false >"$t/secure"; sleepd now >"$t/out"
[[ $(suspends) == 0 ]] || fail "now with no watcher still checks the lock"
echo "ok - sleepd: now (the power key) sleeps within 2 s through the watcher, and does nothing with the toggle off"

reset; out=$(sleepd check) || fail "check: exit 0 when nothing stops sleep"
[[ $out == "nothing stops sleep" ]] || fail "check: says so ($out)"
echo true >"$t/dpms"; echo 0 >"$t/sys/class/backlight/panel/bl_power"
out=$(sleepd check) && fail "check: exit 1 with the screen on"
[[ $out == "not sleeping: the screen is on" ]] || fail "check names the reason ($out)"
echo "ok - sleepd: check names what stops sleep"
