#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-keys' volume keys: a photo while the Camera app (omacam) is in
# front of an unlocked phone, once per press; the volume otherwise. Stand-ins
# for hyprctl, omacam, omarchy-shell and omarchy-audio-output-volume record
# what was called.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/run"
log=$t/calls
cat >"$t/bin/hyprctl" <<STUB
#!/bin/bash
printf '{"class": "%s"}\n' "\$(cat "$t/class")"
STUB
cat >"$t/bin/omacam" <<STUB
#!/bin/bash
echo "omacam \$*" >>"$log"
STUB
cat >"$t/bin/omarchy-audio-output-volume" <<STUB
#!/bin/bash
echo "volume \$*" >>"$log"
STUB
cat >"$t/bin/omarchy-shell" <<STUB
#!/bin/bash
cat "$t/locked"
STUB
chmod +x "$t"/bin/*
# The panel's own state (backlight bl_power, the DRM connector's dpms) is read
# from this fake sysfs, never from the machine the test runs on.
mkdir -p "$t/sys/class/backlight/panel" "$t/sys/class/drm/card0-DSI-1"
echo 0 >"$t/sys/class/backlight/panel/bl_power"; echo On >"$t/sys/class/drm/card0-DSI-1/dpms"; echo connected >"$t/sys/class/drm/card0-DSI-1/status"
export PATH="$t/bin:$PATH" XDG_RUNTIME_DIR="$t/run" OMAMOBILE_KEYS_SYSFS="$t/sys"
keys() { bash "$here/bin/omamobile-keys" "$@"; }
fail() { printf 'not ok - %s\n' "$1" >&2; cat "$log" >&2 2>/dev/null; exit 1; }
reset() { : >"$log"; rm -rf "$t/run/omamobile-keys"; }

echo foot >"$t/class"; echo false >"$t/locked"
reset; keys volume-up; [[ $(cat "$log") == "volume raise" ]] || fail "volume up raises the volume"
reset; keys volume-down; sleep 0.4; [[ $(cat "$log") == "volume lower" ]] || fail "volume down lowers the volume"

echo omacam >"$t/class"
reset; keys volume-up; [[ $(cat "$log") == "omacam --remote shutter" ]] || fail "volume up takes a photo in the camera"
reset; keys volume-down; sleep 0.4; [[ $(cat "$log") == "omacam --remote shutter" ]] || fail "volume down takes a photo in the camera"
reset; keys volume-up; keys volume-up; keys volume-up
[[ $(grep -c shutter "$log") == 1 ]] || fail "a held key takes one photo"

echo true >"$t/locked"
reset; keys volume-up; [[ $(cat "$log") == "volume raise" ]] || fail "a locked phone changes the volume, never takes a photo"
echo "ok - volume keys: camera shutter in front, volume otherwise"

# The power key's short press, by lock state and screen state. hyprctl answers
# both the window class and the monitors' dpmsStatus; the backlight tools are
# stubs, and with no backlight device name (omarchy-hw-display answers nothing)
# bl_power is not consulted; the flash block below gives the panel a fake one.
cat >"$t/bin/hyprctl" <<STUB
#!/bin/bash
if [[ \$1 == monitors ]]; then printf '[{"dpmsStatus": %s}]\n' "\$(cat "$t/dpms")"; exit 0; fi
printf '{"class": "%s"}\n' "\$(cat "$t/class")"
STUB
cat >"$t/bin/omarchy-hw-display" <<STUB
#!/bin/bash
echo ""
STUB
# No screensaver on this machine, whatever Omarchy runs here.
cat >"$t/bin/pgrep" <<STUB
#!/bin/bash
exit 1
STUB
for tool in omarchy-brightness-display omarchy-system-lock omarchy-shell brightnessctl; do
  cat >"$t/bin/$tool" <<STUB
#!/bin/bash
[[ "$tool \$*" == "omarchy-shell lock isLocked" ]] && { [[ -f "$t/slow-locked" ]] && sleep 0.1; cat "$t/locked"; exit 0; }
[[ "$tool \$*" == "omarchy-shell lock status" ]] && { printf '{"locked":true,"secure":%s}\n' "\$(cat "$t/secure")"; exit 0; }
echo "$tool \$*" >>"$log"
STUB
done
chmod +x "$t"/bin/*
# omamobile-sleepd decides itself (toggle, inhibitors); the key only asks.
cat >"$t/bin/omamobile-sleepd" <<STUB
#!/bin/bash
echo "omamobile-sleepd \$*" >>"$log"
STUB
chmod +x "$t"/bin/*
echo true >"$t/secure"
echo foot >"$t/class"
press() { reset; keys power-down; keys power-up; sleep 0.5; }

# The lock hears that its screen goes dark before the panel goes off, so it
# is back on its glance view for the next wake (patches/omarchy/0023).
before() { awk -v a="$1" -v b="$2" '{ sub(/ +$/, "") } $0 == a && !x { x = NR } $0 == b && !y { y = NR } END { exit !(x && y && x < y) }' "$log"; }
echo false >"$t/locked"; echo true >"$t/dpms"
press; grep -q "omarchy-system-lock" "$log" || fail "unlocked and lit: a press locks"
before "omarchy-system-lock" "omarchy-shell lock dark" && before "omarchy-shell lock dark" "omarchy-brightness-display off" \
  || fail "unlocked and lit: the new lock hears it goes dark, before the panel goes off"

# The flash: Hyprland reports the display off at once (dpmsStatus) but the panel
# goes off only when the compositor commits it, 0.3 s later on the Pixel 8 Pro
# (measured), so the saved brightness must not go back before the panel itself
# reads as off (bl_power 4 or the connector's dpms Off), or the lock screen shows
# at full brightness for an instant. Here the stand-in flips hyprctl's dpmsStatus
# when "omarchy-brightness-display off" is called and the panel 0.4 s later,
# writing "panel-off" to the log when it does; with a real device name, a saved
# level of 2083, and a second case where the panel never goes off.
mkdir -p "$t/orig"; cp "$t"/bin/omarchy-hw-display "$t"/bin/brightnessctl "$t"/bin/omarchy-brightness-display "$t/orig/"
cat >"$t/bin/omarchy-hw-display" <<STUB
#!/bin/bash
echo panel
STUB
cat >"$t/bin/brightnessctl" <<STUB
#!/bin/bash
[[ "\$*" == *" get" ]] && { echo 2083; exit 0; }
echo "brightnessctl \$*" >>"$log"
STUB
cat >"$t/bin/omarchy-brightness-display" <<STUB
#!/bin/bash
echo "omarchy-brightness-display \$*" >>"$log"
if [[ \$1 == off && -f "$t/async-off" ]]; then
  echo false >"$t/dpms"
  ( sleep 0.4; echo 4 >"$t/sys/class/backlight/panel/bl_power"; echo Off >"$t/sys/class/drm/card0-DSI-1/dpms"; echo "panel-off" >>"$log" ) >/dev/null 2>&1 &
fi
STUB
chmod +x "$t"/bin/*
panel_on() { echo true >"$t/dpms"; mkdir -p "$t/sys/class/backlight/panel" "$t/sys/class/drm/card0-DSI-1"; echo 0 >"$t/sys/class/backlight/panel/bl_power"; echo On >"$t/sys/class/drm/card0-DSI-1/dpms"; echo connected >"$t/sys/class/drm/card0-DSI-1/status"; }
echo false >"$t/locked"; panel_on; : >"$t/async-off"
reset; keys power-down; keys power-up; sleep 1.5
before "brightnessctl -q -d panel set 0" "omarchy-system-lock" || fail "flash: the panel goes dark by the backlight before the lock is built"
before "panel-off" "brightnessctl -q -d panel set 2083" || fail "flash: the saved brightness goes back only after the panel is off"
before "panel-off" "omamobile-sleepd now" || fail "flash: sleep is asked for after the panel is off"
# The panel never goes off: the key handler still puts the brightness back and
# asks for sleep, after at most about 1 s.
rm -f "$t/async-off"; panel_on
reset; start=$(date +%s%N); keys power-down; keys power-up
for _ in $(seq 60); do grep -q "brightnessctl -q -d panel set 2083" "$log" && break; sleep 0.1; done
# The limit is read from `date`, never from EPOCHREALTIME (a comma locale writes it with a comma).
grep -q EPOCHREALTIME "$here/bin/omamobile-keys" && fail "flash: the wait's clock doesn't depend on the locale"
# ... and never from date's %3N: uutils' date (0.10.0) drops the nanoseconds'
# leading zeros before it takes three digits, so one reading in ten was wrong
# and this wait ended up to 400 ms early on the build machine (2026-11-11).
grep -q '%[0-9]N' "$here/bin/omamobile-keys" && fail "flash: the wait's clock doesn't use date's %3N"
took=$(( ($(date +%s%N) - start) / 1000000 ))
grep -q "brightnessctl -q -d panel set 2083" "$log" || fail "flash: with a panel that never goes off the brightness still goes back"
(( took >= 900 && took < 2500 )) || fail "flash: with a panel that never goes off the wait lasts about 1 s ($took ms)"
# No panel files at all (another machine): Hyprland's answer is all there is.
rm -rf "$t/sys/class/drm/card0-DSI-1" "$t/sys/class/backlight/panel"; : >"$t/async-off"
reset; start=$(date +%s%N); keys power-down; keys power-up
took=$(( ($(date +%s%N) - start) / 1000000 )); sleep 1
grep -q "brightnessctl -q -d panel set 2083" "$log" || fail "flash: with no panel files the brightness goes back by Hyprland's word"
(( took < 1500 )) || fail "flash: with no panel files Hyprland's word ends the wait at once, not at the bound ($took ms)"
# A connector that is not connected (a second, unused one) says Off and must not end the wait.
panel_on; mkdir -p "$t/sys/class/drm/card0-DSI-2"; echo Off >"$t/sys/class/drm/card0-DSI-2/dpms"; echo disconnected >"$t/sys/class/drm/card0-DSI-2/status"; : >"$t/async-off"
reset; keys power-down; keys power-up; sleep 1
before "panel-off" "brightnessctl -q -d panel set 2083" || fail "flash: an unconnected connector's Off does not end the wait"
rm -rf "$t/sys/class/drm/card0-DSI-2"; panel_on
cp "$t"/orig/omarchy-hw-display "$t"/orig/brightnessctl "$t"/orig/omarchy-brightness-display "$t/bin/"
echo "ok - power press unlocked and lit: the brightness comes back only after the panel is off (and still after 1 s if it never is)"
echo false >"$t/locked"; echo false >"$t/dpms"
press; grep -q "omarchy-brightness-display on" "$log" || fail "unlocked and dark: a press lights the screen"
grep -q "omarchy-system-lock" "$log" && fail "unlocked and dark: a press does not lock"
echo true >"$t/locked"; echo true >"$t/dpms"
press; grep -q "omarchy-brightness-display off" "$log" || fail "locked and lit: a press turns the screen off"
before "omarchy-shell lock dark" "omarchy-brightness-display off" || fail "locked and lit: the lock hears it goes dark, before the panel goes off"
grep -q "omarchy-system-lock" "$log" && fail "locked and lit: a press does not lock again"
echo true >"$t/locked"; echo false >"$t/dpms"
press; grep -q "omarchy-shell lock wake" "$log" || fail "locked and dark: a press wakes the lock screen"
grep -q "omarchy-brightness-display on" "$log" || fail "locked and dark: a press lights the screen"
grep -q "lock dark" "$log" && fail "locked and dark: a wake doesn't tell the lock it went dark"
grep -q "omarchy-system-lock" "$log" && fail "locked and dark: a press does not lock again"
# hyprctl failing must read as "screen on": the press locks, never wakes blind.
cat >"$t/bin/hyprctl" <<STUB
#!/bin/bash
exit 1
STUB
echo false >"$t/locked"
press; grep -q "omarchy-system-lock" "$log" || fail "an unanswered screen state reads as lit: the press locks"
echo "ok - power key: lock, screen off, and wake by lock and screen state"

# A double tap on the touchscreen (omamobile-doubletap): a dark screen wakes
# as a short press wakes it, locked or not; a lit one is left alone.
cat >"$t/bin/hyprctl" <<STUB
#!/bin/bash
if [[ \$1 == monitors ]]; then printf '[{"dpmsStatus": %s}]\n' "\$(cat "$t/dpms")"; exit 0; fi
printf '{"class": "%s"}\n' "\$(cat "$t/class")"
STUB
tap2() { reset; keys double-tap; }
echo true >"$t/locked"; echo false >"$t/dpms"
tap2; grep -q "omarchy-shell lock wake" "$log" && grep -q "omarchy-brightness-display on" "$log" \
  || fail "double tap, locked and dark: wakes the lock screen and lights it"
echo false >"$t/locked"; echo false >"$t/dpms"
tap2; grep -q "omarchy-brightness-display on" "$log" || fail "double tap, unlocked and dark: lights the screen"
grep -q "omarchy-shell lock wake" "$log" && fail "double tap, unlocked and dark: no lock wake"
for locked in true false; do
  echo $locked >"$t/locked"; echo true >"$t/dpms"
  tap2; [[ ! -s $log ]] || fail "double tap on a lit screen (locked $locked) does nothing"
done
grep -qE "omarchy-system-lock|lock dark|omamobile-sleepd" "$log" && fail "a double tap never locks or sleeps"
[[ ! -e $t/run/omamobile-keys/power-wake ]] || fail "a double tap doesn't swallow the next power press"
# The double tap lights the display first and runs the lock's wake beside it (the display's
# modeset is the slow part): with a display that takes 0.4 s, "lock wake" must be logged
# between the display's start and its end, and the handler must still wait for the display.
mkdir -p "$t/orig2"; cp "$t/bin/omarchy-brightness-display" "$t/orig2/"
cat >"$t/bin/omarchy-brightness-display" <<STUB
#!/bin/bash
echo "omarchy-brightness-display \$* start" >>"$log"
sleep 0.4
echo "omarchy-brightness-display \$* done" >>"$log"
STUB
chmod +x "$t/bin/omarchy-brightness-display"
echo true >"$t/locked"; echo false >"$t/dpms"; : >"$t/slow-locked"   # the locked check takes 0.1 s, as on the phone: the display must not wait for it
tap2
before "omarchy-brightness-display on start" "omarchy-shell lock wake" || fail "double tap: the display starts before the lock's wake"
before "omarchy-shell lock wake" "omarchy-brightness-display on done" || fail "double tap: the lock's wake runs beside the display, not after it"
grep -q "omarchy-brightness-display on done" "$log" || fail "double tap: the handler waits for the display to come on"
echo false >"$t/locked"; echo false >"$t/dpms"
tap2
grep -q "omarchy-brightness-display on done" "$log" || fail "double tap, unlocked: the handler waits for the display"
grep -q "omarchy-shell lock wake" "$log" && fail "double tap, unlocked: still no lock wake"
rm -f "$t/slow-locked"; cp "$t/orig2/omarchy-brightness-display" "$t/bin/"
echo "ok - double tap: wakes a dark screen, locked or not, and leaves a lit one alone"

# The screen gone dark while unlocked (omamobile-doubletap tells): it locks,
# and the new lock hears it is dark, so a touch on the dark screen reaches
# the lock, never the app under it. Lit, or already locked: nothing.
darku() { reset; keys dark-unlocked; }
echo false >"$t/locked"; echo false >"$t/dpms"
darku; before "omarchy-system-lock" "omarchy-shell lock dark" || fail "dark and unlocked: locks, then the lock hears it is dark"
grep -qE "brightness-display|omamobile-sleepd" "$log" && fail "dark and unlocked: the panel is left as it is"
echo false >"$t/locked"; echo true >"$t/dpms"
darku; [[ ! -s $log ]] || fail "lit and unlocked: dark-unlocked does nothing"
echo true >"$t/locked"; echo false >"$t/dpms"
darku; [[ ! -s $log ]] || fail "dark and locked: dark-unlocked does nothing"
echo "ok - a screen gone dark while unlocked locks, as on Android"

# A lock slower than the long-press timer (it takes about a second on the
# phone) must not turn the short press into a long one that wakes the lock.
cat >"$t/bin/hyprctl" <<STUB
#!/bin/bash
if [[ \$1 == monitors ]]; then printf '[{"dpmsStatus": %s}]\n' "\$(cat "$t/dpms")"; exit 0; fi
printf '{"class": "%s"}\n' "\$(cat "$t/class")"
STUB
mv "$t/bin/omarchy-system-lock" "$t/bin/omarchy-system-lock.fast"
cat >"$t/bin/omarchy-system-lock" <<STUB
#!/bin/bash
echo "omarchy-system-lock" >>"$log"
echo true >"$t/locked"
sleep 1
STUB
chmod +x "$t/bin/omarchy-system-lock"
echo false >"$t/locked"; echo true >"$t/dpms"
press; sleep 0.6
grep -q "omarchy-system-lock" "$log" || fail "slow lock: the press locks"
grep -q "lock wake\|brightness-display on\|omarchy-menu" "$log" && fail "slow lock: the long-press timer doesn't wake the lock it just took"
mv "$t/bin/omarchy-system-lock.fast" "$t/bin/omarchy-system-lock"
# After a power-key wake from sleep, sleepd lights the PIN pad; the waking
# press, if Hyprland delivers it late, must not turn the screen back off.
echo true >"$t/locked"; echo false >"$t/dpms"
reset; keys wake
grep -q "omarchy-shell lock wake" "$log" || fail "wake: a dark locked phone lights the PIN pad"
echo true >"$t/dpms"; : >"$log"; keys power-down; keys power-up; sleep 0.5
grep -q "omarchy-brightness-display off" "$log" && fail "the press that woke the phone doesn't turn the screen off again"
echo true >"$t/locked"; echo true >"$t/dpms"
reset; keys wake
grep -q "lock wake" "$log" && fail "wake: a lit screen is left alone"
echo "ok - power key: a slow lock stays a short press, and the press that woke the phone is the wake"

# Sleep now (SUSPEND-PLAN 6.1): only after a press that turned the screen
# off behind a secure lock; never after a wake or with the lock not secure.
cat >"$t/bin/hyprctl" <<STUB
#!/bin/bash
if [[ \$1 == monitors ]]; then printf '[{"dpmsStatus": %s}]\n' "\$(cat "$t/dpms")"; exit 0; fi
printf '{"class": "%s"}\n' "\$(cat "$t/class")"
STUB
echo true >"$t/secure"
echo false >"$t/locked"; echo true >"$t/dpms"
press; grep -c "omamobile-sleepd now" "$log" >/dev/null || fail "unlocked and lit: the press that locks asks for sleep"
echo true >"$t/locked"; echo true >"$t/dpms"
press; grep -c "omamobile-sleepd now" "$log" >/dev/null || fail "locked and lit: the press that turns the screen off asks for sleep"
echo true >"$t/locked"; echo false >"$t/dpms"
press; grep -c "omamobile-sleepd" "$log" >/dev/null && fail "locked and dark: a wake never asks for sleep"
echo false >"$t/locked"; echo false >"$t/dpms"
press; grep -c "omamobile-sleepd" "$log" >/dev/null && fail "unlocked and dark: lighting the screen never asks for sleep"
echo false >"$t/secure"
echo true >"$t/locked"; echo true >"$t/dpms"
press; grep -c "omamobile-sleepd" "$log" >/dev/null && fail "a lock that isn't secure never asks for sleep"
echo "ok - power key: screen off behind a secure lock asks omamobile-sleepd to sleep now"

# Power + Volume Up push-to-talk (voice input): off unless the voice
# settings turn it on, never on the lock screen; on, power held then volume
# up starts it (no volume change, no power gesture) and volume up's release
# stops it. Every other release does nothing.
export XDG_CONFIG_HOME=$t/config
mkdir -p "$t/config/omamobile"
echo false >"$t/locked"; echo true >"$t/dpms"
echo foot >"$t/class"
voice() { grep -c "omamobile.voice $1" "$log" 2>/dev/null || true; }
ptt() { reset; keys power-down; keys volume-up; keys volume-up; sleep 0.3; }
release() { keys volume-up-release; keys power-up; sleep 0.5; }

rm -f "$t/config/omamobile/voice.json"
ptt; release
[[ $(voice keyPress) == 0 ]] || fail "push-to-talk is off without the setting"
grep -c "volume raise" "$log" >/dev/null || fail "with it off, power + volume up still raises the volume"
echo '{"powerVolumeUp": false}' >"$t/config/omamobile/voice.json"
ptt; release; [[ $(voice keyPress) == 0 ]] || fail "push-to-talk is off when the setting says so"

echo '{"powerVolumeUp": true}' >"$t/config/omamobile/voice.json"
ptt
[[ $(voice keyPress) == 1 ]] || fail "power + volume up starts push-to-talk once (key repeat starts nothing)"
grep -c "volume raise" "$log" >/dev/null && fail "push-to-talk doesn't change the volume"
[[ $(voice keyRelease) == 0 ]] || fail "still talking while volume up is held"
release
[[ $(voice keyRelease) == 1 ]] || fail "volume up's release stops push-to-talk"
grep -cE "omarchy-system-lock|omarchy-brightness-display" "$log" >/dev/null && fail "the chord's power release locks nothing"

# Volume up first, then power: the same chord.
reset; keys volume-up; keys power-down; sleep 0.3
[[ $(voice keyPress) == 1 ]] || fail "volume up held, then power, starts push-to-talk"
# Hyprland drops volume up's release here (power went down after it): power's ends it.
keys power-up; sleep 0.3
[[ $(voice keyRelease) == 1 ]] || fail "power's release ends push-to-talk when volume up's never comes"
keys volume-up-release; sleep 0.3
[[ $(voice keyRelease) == 1 ]] || fail "push-to-talk ends once"

# A plain volume-up release does nothing; locked, no push-to-talk.
reset; keys volume-up; keys volume-up-release; sleep 0.3
[[ $(voice key) == 0 ]] || fail "a plain volume-up release calls nothing"
echo true >"$t/locked"
ptt; release
[[ $(voice keyPress) == 0 ]] || fail "no push-to-talk on the lock screen"
echo false >"$t/locked"
echo "ok - power + volume up: push-to-talk only when turned on, never locked, stops on release, volume untouched"
