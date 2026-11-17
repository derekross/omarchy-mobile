#!/bin/bash
# SPDX-License-Identifier: MIT
# Screen lock settings for the Settings app's Display page. Prints one line of JSON.
#   lock.sh get                 {"lock":60,"keyboardAwake":false,"keyboard":false,"effective":60}
#   lock.sh set lock N          N is 30, 60, 120, 180, 300 or 0 (never)
#   lock.sh set keyboard on|off stay unlocked while a Bluetooth or USB keyboard is connected
#   lock.sh apply               write the value in force now (omamobile-lock-keyboard, on each input change)
# How the phone locks: Omarchy's idle service locks after shell.json's idle.lock seconds (0 = never, the
# phone profile's value is 60), and the lock turns the screen off a few seconds later. So this one value
# is both "lock after" and "screen off after"; there is no separate screen-off timer.
# The choice is kept in ~/.config/omamobile/lock.json with the value last written ("applied"); shell.json's
# idle.lock is the value in force: 0 while the keyboard toggle is on and a keyboard is connected, the
# choice otherwise. If idle.lock no longer holds what this wrote, it was changed elsewhere (Omarchy's own
# settings) and that value becomes the choice. Nothing is written before the user picks something here.
# A keyboard is an input device udev marks ID_INPUT_KEYBOARD=1 on the Bluetooth bus (0005, uhid included)
# or on USB (0003) outside /devices/virtual/input (uinput devices can claim USB): the built-in keys,
# the on-screen keyboard and virtual devices are left out.
# Test hooks: OMAMOBILE_LOCK_SYSFS and OMAMOBILE_LOCK_UDEVDATA stand in for /sys and /run/udev/data.
set -euo pipefail
set +x
verb=${1:-}; key=${2:-}; value=${3:-}
fail() { printf '{"error":"%s"}\n' "$1"; exit 2; }
sys=${OMAMOBILE_LOCK_SYSFS:-/sys}
udev=${OMAMOBILE_LOCK_UDEVDATA:-/run/udev/data}
prefs=${XDG_CONFIG_HOME:-$HOME/.config}/omamobile/lock.json
shell=$HOME/.config/omarchy/shell.json
defaults=${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json

keyboard_connected() {
  local ev dev path bus
  for ev in "$sys"/class/input/event*; do
    [[ -r $ev/dev && -r $ev/device/id/bustype ]] || continue
    dev=$(<"$ev/dev")
    grep -qx 'E:ID_INPUT_KEYBOARD=1' "$udev/c$dev" 2>/dev/null || continue
    bus=$(<"$ev/device/id/bustype")
    path=$(realpath -- "$ev/device")
    case $bus in
      0005) return 0 ;;
      0003) [[ $path == */devices/virtual/input/* ]] || return 0 ;;
    esac
  done
  return 1
}
kb=false; keyboard_connected && kb=true

# All JSON work in one place: reads prefs and shell.json, applies the verb, writes both atomically.
/usr/bin/python3 -I - "$prefs" "$shell" "$defaults" "$kb" "$verb" "$key" "$value" <<'PY'
import json, os, sys
prefs_path, shell_path, defaults_path, kb, verb, key, value = sys.argv[1:]
kb = kb == "true"
CHOICES = (30, 60, 120, 180, 300, 0)
def out(d): print(json.dumps(d, separators=(",", ":"))); sys.exit(0)
def fail(m): print(json.dumps({"error": m}, separators=(",", ":"))); sys.exit(2)
def load(p):
    try:
        with open(p) as f: d = json.load(f)
        return d if isinstance(d, dict) else None
    except (OSError, ValueError):
        return None
def save(p, d, indent=None):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p + ".new", "w") as f:
        json.dump(d, f, indent=indent); f.write("\n")
    os.replace(p + ".new", p)
def secs(v, fallback):  # as Omarchy's IdleModel.secondsFromConfig
    try: n = float(v)
    except (TypeError, ValueError): return fallback
    return int(n) if n >= 0 and n == n and n != float("inf") else fallback

shell = load(shell_path)
if shell is not None and shell.get("version") != 1: shell = None  # Omarchy ignores it: so do we
current = secs(((shell or load(defaults_path) or {}).get("idle") or {}).get("lock"), 300)
prefs = load(prefs_path)
if prefs is not None:
    applied = prefs.get("applied")
    if isinstance(applied, int) and applied != current:
        prefs["lock"] = current  # changed outside this page
    if not isinstance(prefs.get("lock"), int) or prefs["lock"] < 0: prefs["lock"] = current
    prefs["keyboardAwake"] = bool(prefs.get("keyboardAwake"))

if verb == "get":
    p = prefs or {"lock": current, "keyboardAwake": False}
    out({"lock": p["lock"], "keyboardAwake": p["keyboardAwake"], "keyboard": kb, "effective": current})
elif verb == "set":
    p = prefs or {"lock": current, "keyboardAwake": False}
    if key == "lock":
        if not value.isdigit() or int(value) not in CHOICES: fail("bad value")
        p["lock"] = int(value)
    elif key == "keyboard":
        if value not in ("on", "off"): fail("bad value")
        p["keyboardAwake"] = value == "on"
    else: fail("unknown key")
    prefs = p
elif verb == "apply":
    if prefs is None: out({"applied": None})  # never set here: leave Omarchy's value alone
else:
    fail("usage: get|set|apply")

want = 0 if prefs["keyboardAwake"] and kb else prefs["lock"]
if want != current:
    if shell is None:
        shell = load(defaults_path)  # Omarchy never merges: start from its defaults, as omarchy-shell-config does
        if shell is None: fail("cannot read shell.json")
    idle = shell.get("idle") if isinstance(shell.get("idle"), dict) else {}
    idle["lock"] = want; shell["idle"] = idle
    try: save(shell_path, shell, indent=2)
    except OSError: fail("cannot write shell.json")
prefs["applied"] = want
try: save(prefs_path, prefs)
except OSError: fail("cannot save the setting")
out({"lock": prefs["lock"], "keyboardAwake": prefs["keyboardAwake"], "keyboard": kb, "effective": want})
PY
