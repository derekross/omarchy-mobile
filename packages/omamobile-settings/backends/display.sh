#!/bin/bash
# SPDX-License-Identifier: MIT
# Display settings for the Settings app: brightness (the backlight, through brightnessctl, on the device
# omarchy-hw-display names like the shell does) and the refresh rate (applied live through
# `hyprctl eval hl.monitor{...}` with the monitor's own name, size, position, scale and transform).
# Prints one line of JSON.
#   display.sh get                 {"brightness":50,"refresh":120,"rates":[60,120],"saved":0,"default":60}
#                                  (saved: the kept choice, 0 for none; default: the device default below when the
#                                  panel lists it, 0 for none)
#   display.sh set brightness N    N is 10, 25, 50, 75 or 100 (never below 10, so the screen cannot go black)
#   display.sh set refresh N       N must be one of the rates the monitor lists at its current size
#   display.sh set refresh preferred   forget the choice and go back to the device default (below), else the
#                                  panel's preferred mode
#   display.sh apply               apply the saved choice at a session start, else the device default; with neither
#                                  valid and listed it does nothing at all (no eval), so Hyprland's own rule stays.
#                                  It waits up to 5 s for the monitor at a session start, sends nothing when the
#                                  panel already runs the wanted rate, and reads the rate back: with the screen off
#                                  (DPMS) Hyprland ignores a monitor rule and still exits 0, so apply then sends
#                                  nothing and fails; the rate comes back at the next config reload, rotation (when
#                                  auto-rotate is on) or Settings tap, not when the screen comes on.
#                                  apply and set refresh take a lock, so two applies (session start and the first
#                                  config reload) never interleave.
# The device default is a bare number in /usr/share/omamobile/refresh-rate-default, shipped by a device package that
# wants a rate other than Hyprland's pick (husky: 60, as its panel scans out every frame at 120 even when idle).
# It is used only while the user has no saved choice and only when the panel lists it; "saved" stays 0 then.
# Every answer to get and set carries "saved" and "default" (0 for none). The rates are the monitor's own availableModes at its current width and height. The choice is saved as a bare number
# in ~/.config/omamobile/refresh-rate (a fixed path: the
# auto-rotate user service may not see a session-only XDG_CONFIG_HOME), which `apply` and omamobile-sensors' auto-rotate read (the
# shell's Hyprland config carries no monitor rule, so this is the only place a rate is set; phone.lua runs `apply` at
# session start and after every config reload). A saved rate the panel no longer lists is ignored: the device default
# if listed, else the monitor is left as Hyprland set it, so the screen cannot go black. The monitor is the
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
  if [[ -n $fake ]]; then sed -n 2p "$fake"; else timeout 3 hyprctl monitors -j 2>/dev/null; fi
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
# hyprctl may report the size turned by the transform while availableModes keep the panel own orientation, so a
# mode matches in either orientation; the exact token (without "Hz") is what Hyprland is sent back later
tokens = {}
for want in ("%dx%d" % (w, h), "%dx%d" % (h, w)):  # the size as reported first, the swapped one only for rates missing there
    for mode in m.get("availableModes", []):
        size, _, hz = mode.partition("@")
        if size == want:
            hz = hz.removesuffix("Hz")
            try:
                tokens.setdefault(int(round(float(hz))), size + "@" + hz)
            except ValueError:
                pass  # a mode this parser does not know is left out
tokens = {r: t for r, t in tokens.items() if re.fullmatch(r"[0-9]{1,5}x[0-9]{1,5}@[0-9]{1,4}(\.[0-9]{1,6})?", t)}
cur = int(round(float(m["refreshRate"])))
dpms = 0 if m.get("dpmsStatus", True) is False else 1
print(name, w, h, x, y, "%g" % scale, transform, cur, dpms, ",".join(str(r) for r in sorted(tokens)) or "-",
      ",".join("%d=%s" % (r, tokens[r]) for r in sorted(tokens)) or "-")' 2>/dev/null
}
# sets the monitor variables from mon_info ("-" stands for an empty list there)
readmon() {
  read -r name w h x y scale transform refresh dpms rates tokens < <(mon_info) || return 1
  [[ $rates != - ]] || rates=""
  [[ $tokens != - ]] || tokens=""
}
read_all() {
  bright=$(get_brightness) || fail "cannot read the backlight"
  if ! readmon; then
    name=""; refresh=-1; rates=""; tokens=""
  fi
}
rate_file=$HOME/.config/omamobile/refresh-rate
default_file=/usr/share/omamobile/refresh-rate-default
# apply_mode WHEN: WHEN is a listed rate or "preferred"; sets this monitor's mode and keeps its other fields
apply_mode() {
  local mode=preferred res t
  if [[ $1 != preferred ]]; then
    # the exact mode token the panel lists (its own orientation and decimals), never a rebuilt one
    for t in ${tokens//,/ }; do [[ ${t%%=*} == "$1" ]] && mode=${t#*=}; done
    [[ $mode != preferred ]] || return 1
  fi
  res=$(timeout 3 hyprctl eval "hl.monitor({ output = \"$name\", mode = \"$mode\", position = \"${x}x${y}\", scale = $scale, transform = $transform })" 2>&1) \
    || return 1
  [[ ${res,,} != *error* ]]
}
# a rate file holds exactly one bare number (1 to 3 digits, no leading zero) and at most one trailing newline, nothing
# else; omamobile-sensors' autorotate.py (_read_rate) accepts exactly the same
read_rate() {
  local r
  [[ -r $1 ]] || return 0
  r=$(cat -- "$1" 2>/dev/null; printf x) || return 0
  r=${r%x}; r=${r%$'\n'}
  [[ $r =~ ^[1-9][0-9]{0,2}$ ]] && echo "$r" || true
}
saved_rate() { read_rate "$rate_file"; }
# the device default, only when the panel lists it at its current size
default_rate() { local d; d=$(read_rate "$default_file"); [[ -n $d && ,$rates, == *",$d,"* ]] && echo "$d" || true; }
# the answer: "saved" is the choice kept in the file (0 for none, or one the panel does not list), "default" the
# device default when listed (0 for none)
out_saved() {
  local s d; s=$(saved_rate); d=$(default_rate)
  [[ -n $s && ,$rates, == *",$s,"* ]] || s=0
  printf '{"brightness":%s,"refresh":%s,"rates":[%s],"saved":%s,"default":%s}\n' "$bright" "$refresh" "$rates" "$s" "${d:-0}"
}
# one refresh change at a time: session start and the first config reload can both run apply
lock() {
  local f=${XDG_RUNTIME_DIR:-$HOME/.cache}/omamobile-display.lock
  mkdir -p -- "${f%/*}" && exec 9>"$f" && flock -w 15 9 || fail "another refresh change is running"
}
# after an eval: 0 once the panel reports rate $1 (checked for up to 2 s), 2 if the screen turned off meanwhile
# (Hyprland then ignores the rule), else 1
took() {
  local i
  for i in 1 2 3 4; do
    sleep 0.5
    if readmon; then
      [[ $refresh != "$1" ]] || return 0
      [[ $dpms == 1 ]] || return 2
    fi
  done
  return 1
}
# took's failure as a message, with the state as now read, so the page stays in sync
fail_took() {
  case $1 in 2) fail_state "the screen turned off before the rate took" ;; *) fail_state "the screen did not take the rate" ;; esac
}
# an error that still carries brightness, refresh, rates, saved and default
fail_state() {
  local s d; s=$(saved_rate); d=$(default_rate)
  [[ -n $s && ,$rates, == *",$s,"* ]] || s=0
  printf '{"error":"%s","brightness":%s,"refresh":%s,"rates":[%s],"saved":%s,"default":%s}\n' "$1" "$bright" "$refresh" "$rates" "$s" "${d:-0}"
  exit 2
}

case $verb in
get)
  read_all; out_saved ;;
set)
  read_all
  case $key in
    brightness)
      case $value in 10|25|50|75|100) ;; *) fail "bad value" ;; esac
      if [[ -z $fake ]]; then set_brightness "$value" || fail "could not set the brightness"; fi
      bright=$value ;;
    refresh)
      # the file changes only after the panel reports the new rate, so the page and the file never disagree; the
      # monitor is read again right before the eval, so a turn by auto-rotate since read_all is not undone (one
      # landing between that read and the eval still is)
      if [[ $value == preferred ]]; then
        [[ -n $name ]] || fail "cannot read the monitor"
        if [[ -z $fake ]]; then
          lock
          readmon || fail "cannot read the monitor"
          def=$(default_rate)
          apply_mode "${def:-preferred}" || fail "the screen did not accept the change"
          # with a device default the rate is confirmed; without one Hyprland picks its preferred mode, which this
          # script cannot name, so the answer only reports the rate read after a pause, confirming nothing
          if [[ -n $def ]]; then took "$def" || fail_took $?
          else sleep 1; readmon || fail "cannot read the monitor"; fi
        else
          def=$(default_rate); [[ -z $def ]] || refresh=$def
        fi
        rm -f -- "$rate_file" || fail_state "could not forget the choice"
        out_saved; exit 0
      fi
      [[ $value =~ ^[1-9][0-9]{0,2}$ ]] || fail "bad value"
      [[ -n $name ]] || fail "cannot read the monitor"
      [[ ,$rates, == *",$value,"* ]] || fail "this display does not list that rate"
      if [[ -z $fake ]]; then
        lock
        readmon || fail "cannot read the monitor"
        apply_mode "$value" || fail "the screen did not accept the change"
        took "$value" || fail_took $?
      else
        refresh=$value
      fi
      mkdir -p -- "${rate_file%/*}" && printf '%s\n' "$value" > "$rate_file" || fail_state "could not save the choice" ;;
    *) fail "unknown key" ;;
  esac
  out_saved ;;
apply)
  # a phone with no readable backlight still gets its refresh rate back
  bright=$(get_brightness) || bright=-1
  [[ -n $fake ]] || lock
  # at a session start the monitor may not be readable yet: up to 10 tries, 0.5 s apart
  for try in 1 2 3 4 5 6 7 8 9 10; do
    readmon && break
    name=""; refresh=-1; rates=""; tokens=""
    [[ -z $fake && $try != 10 ]] || break
    sleep 0.5
  done
  [[ -n $name ]] || fail "cannot read the monitor"
  want=$(saved_rate)
  # nothing is applied unless the panel lists the rate right now: the saved choice, else the device default; with
  # neither (or a stale one) the monitor stays exactly as Hyprland's own rule set it, and a stale file is never
  # turned into a rule
  [[ -n $want && ,$rates, == *",$want,"* ]] || want=$(default_rate)
  [[ -n $want ]] || { out_saved; exit 0; }
  # already there (a second apply, or a reload that kept it): nothing is sent
  [[ $refresh != "$want" ]] || { out_saved; exit 0; }
  if [[ -z $fake ]]; then
    # Hyprland ignores the rule while the screen is off (and still exits 0): nothing is sent, and the failure says so
    [[ $dpms == 1 ]] || fail "the screen is off; the rate is applied at the next config reload, rotation or Settings tap"
    # the transform is read again right before the eval: auto-rotate may turn the screen after the first read, and
    # the eval would turn it back; the gap left is this one read (a hyprctl call and a python start) and the eval
    readmon || fail "cannot read the monitor"
    apply_mode "$want" || fail "the screen did not accept the change"
    took "$want" || fail_took $?
  else refresh=$want; fi
  out_saved ;;
*)
  fail "usage: get|set|apply" ;;
esac
