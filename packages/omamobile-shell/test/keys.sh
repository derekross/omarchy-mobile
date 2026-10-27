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
export PATH="$t/bin:$PATH" XDG_RUNTIME_DIR="$t/run"
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
# stubs, and bl_power is not consulted (no backlight device on this machine).
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
[[ "$tool \$*" == "omarchy-shell lock isLocked" ]] && { cat "$t/locked"; exit 0; }
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

echo false >"$t/locked"; echo true >"$t/dpms"
press; grep -q "omarchy-system-lock" "$log" || fail "unlocked and lit: a press locks"
echo false >"$t/locked"; echo false >"$t/dpms"
press; grep -q "omarchy-brightness-display on" "$log" || fail "unlocked and dark: a press lights the screen"
grep -q "omarchy-system-lock" "$log" && fail "unlocked and dark: a press does not lock"
echo true >"$t/locked"; echo true >"$t/dpms"
press; grep -q "omarchy-brightness-display off" "$log" || fail "locked and lit: a press turns the screen off"
grep -q "omarchy-system-lock" "$log" && fail "locked and lit: a press does not lock again"
echo true >"$t/locked"; echo false >"$t/dpms"
press; grep -q "omarchy-shell lock wake" "$log" || fail "locked and dark: a press wakes the lock screen"
grep -q "omarchy-brightness-display on" "$log" || fail "locked and dark: a press lights the screen"
grep -q "omarchy-system-lock" "$log" && fail "locked and dark: a press does not lock again"
# hyprctl failing must read as "screen on": the press locks, never wakes blind.
cat >"$t/bin/hyprctl" <<STUB
#!/bin/bash
exit 1
STUB
echo false >"$t/locked"
press; grep -q "omarchy-system-lock" "$log" || fail "an unanswered screen state reads as lit: the press locks"
echo "ok - power key: lock, screen off, and wake by lock and screen state"

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
