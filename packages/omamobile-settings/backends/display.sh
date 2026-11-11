#!/bin/bash
# SPDX-License-Identifier: MIT
# Display settings for the Settings app: brightness (the backlight, through brightnessctl, on the device
# omarchy-hw-display names like the shell does) and the refresh rate (applied live through
# `hyprctl eval hl.monitor{...}` with the monitor's own name, size, position, scale and transform).
# Prints one line of JSON.
#   display.sh get                 {"brightness":50,"refresh":120,"rates":[60,120]}
#   display.sh set brightness N    N is 10, 25, 50, 75 or 100 (never below 10, so the screen cannot go black)
#   display.sh set refresh N       N must be one of the rates the monitor lists at its current size
# The rates are the monitor's own availableModes at its current width and height. The change is live only: turning the phone
# (omamobile-sensors' auto-rotate applies the monitor's preferred mode again each time), a restart of the
# session or a reload of Hyprland's config sets the configured mode again. The monitor is the
# built-in panel (DSI-* or eDP-*), else the only one, else the focused one. Without a monitor the brightness
# still works and "refresh" reads -1 with no rates.
# The test runs a copy of this script with `fake` set to a file holding the brightness (a number) and the monitor
# JSON (two lines): no tool is run then. Nothing in the environment sets it.
set -euo pipefail
set +x
verb=${1:-}; key=${2:-}; value=${3:-}
fail() { printf '{"error":"%s"}\n' "$1"; exit 2; }
fake=''
[[ -z $fake || -r $fake ]] || fail "cannot read the test file"

get_brightness() {
  local v dev
  if [[ -n $fake ]]; then v=$(sed -n 1p "$fake")
  else
    dev=$(omarchy-hw-display 2>/dev/null || true)
    if [[ -n $dev ]]; then v=$(brightnessctl -d "$dev" -m 2>/dev/null | head -n1 | awk -F, '{gsub("%","",$4); print $4}')
    else v=$(brightnessctl --class=backlight -m 2>/dev/null | head -n1 | awk -F, '{gsub("%","",$4); print $4}'); fi
  fi
  [[ $v =~ ^[0-9]+$ ]] || return 1
  echo "$v"
}
set_brightness() {
  local dev
  dev=$(omarchy-hw-display 2>/dev/null || true)
  if [[ -n $dev ]]; then brightnessctl -d "$dev" --quiet set "${1}%" >/dev/null 2>&1
  else brightnessctl --class=backlight --quiet set "${1}%" >/dev/null 2>&1; fi
}
monitors_json() {
  if [[ -n $fake ]]; then sed -n 2p "$fake"; else hyprctl monitors -j 2>/dev/null; fi
}
# prints: name width height x y scale transform refresh rates(comma separated); fails on anything odd, so
# nothing unchecked reaches the eval below
mon_info() {
  monitors_json | /usr/bin/python3 -I -c '
import sys, json, re
ms = json.load(sys.stdin)
pick = [m for m in ms if re.match(r"(DSI|eDP)-", m.get("name", ""))]
if not pick and len(ms) == 1: pick = ms
if not pick: pick = [m for m in ms if m.get("focused")]
m = pick[0]
w, h, x, y = (int(m[k]) for k in ("width", "height", "x", "y"))
name = m["name"]
scale = float(m["scale"])
transform = int(m.get("transform", 0))
if not re.fullmatch(r"[A-Za-z0-9_.-]{1,32}", name) or not 0 <= transform <= 7: raise SystemExit(1)
rates = set()
for mode in m.get("availableModes", []):
    size, _, hz = mode.partition("@")
    if size == "%dx%d" % (w, h):
        try:
            rates.add(int(round(float(hz.rstrip("Hz")))))
        except ValueError:
            pass  # a mode this parser does not know is left out
cur = int(round(float(m["refreshRate"])))
rates.add(cur)
print(name, w, h, x, y, "%g" % scale, transform, cur, ",".join(str(r) for r in sorted(rates)))' 2>/dev/null
}
read_all() {
  bright=$(get_brightness) || fail "cannot read the backlight"
  if ! read -r name w h x y scale transform refresh rates < <(mon_info); then
    name=""; refresh=-1; rates=""
  fi
}
out() { printf '{"brightness":%s,"refresh":%s,"rates":[%s]}\n' "$bright" "$refresh" "$rates"; }

case $verb in
get)
  read_all; out ;;
set)
  read_all
  case $key in
    brightness)
      case $value in 10|25|50|75|100) ;; *) fail "bad value" ;; esac
      if [[ -z $fake ]]; then set_brightness "$value" || fail "could not set the brightness"; fi
      bright=$value ;;
    refresh)
      [[ $value =~ ^[0-9]{1,3}$ ]] || fail "bad value"
      [[ -n $name ]] || fail "cannot read the monitor"
      [[ ,$rates, == *",$value,"* ]] || fail "this display does not list that rate"
      if [[ -z $fake ]]; then
        res=$(hyprctl eval "hl.monitor({ output = \"$name\", mode = \"${w}x${h}@${value}\", position = \"${x}x${y}\", scale = $scale, transform = $transform })" 2>&1) \
          || fail "the screen did not accept the change"
        [[ ${res,,} != *error* ]] || fail "the screen did not accept the change"
        sleep 1
        read -r name w h x y scale transform refresh rates < <(mon_info) || fail "cannot read the monitor"
      else
        refresh=$value
      fi ;;
    *) fail "unknown key" ;;
  esac
  out ;;
*)
  fail "usage: get|set" ;;
esac
