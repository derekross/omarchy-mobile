#!/bin/bash
# SPDX-License-Identifier: MIT
# Keyboard haptics level: probe/get/set. The level is the strength of one 15 ms tick that feedbackd plays for key and
# button presses. It lives in the user's feedbackd theme ($XDG_CONFIG_HOME/feedbackd/themes/custom.json, entries
# button-pressed and key-pressed of the "full" profile). Levels (Lef 2026-11-08, motor level of 255 in brackets):
#   low 0.015 (motor level 3, the lowest and the default he chose), medium 0.035 (8), high 0.07 (17), all 15 ms.
# The length is the same for every level (Lef: only the strength differs; a longer pulse was tried and rejected).
# Nothing above 0.125 and nothing longer than 60 ms is ever written.
# "off" switches feedbackd's profile to "silent": no haptic from any app, the lock-screen PIN pad included (Lef 2026-11-08).
# Any other level puts the profile back to "full" and writes the strength.
# Nothing in the environment changes what runs here except XDG_CONFIG_HOME (the theme directory); the test runs a copy
# of this script with `dry=1`, which skips feedbackd, gsettings and the preview tick. The theme file is checked
# (exactly the two key entries in the full profile) before anything is changed, and the previous profile is not
# restored: any level after Off puts the profile back to full.
set -euo pipefail
dry=0
dir=${XDG_CONFIG_HOME:-$HOME/.config}/feedbackd/themes
file=$dir/custom.json
cap=0.125
verb=${1:-}
key=${2:-}
value=${3:-}

fail() { printf '%s\n' "$1"; exit 2; }

level_pair() {
  case $1 in
    low) echo "0.015 15" ;;
    medium) echo "0.035 15" ;;
    high) echo "0.07 15" ;;
    *) return 1 ;;
  esac
}

get_profile() {
  if [[ $dry == 1 ]]; then cat "$dir/.profile-dry" 2>/dev/null || echo full
  else gsettings get org.sigxcpu.feedbackd profile | tr -d "'"; fi
}
set_profile() {
  if [[ $dry == 1 ]]; then echo "$1" >"$dir/.profile-dry"
  else gsettings set org.sigxcpu.feedbackd profile "$1"; fi
}

current_level() {
  [[ $(get_profile) == silent ]] && { echo off; return; }
  /usr/bin/python3 -I - "$file" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
pairs = set()
for p in d["profiles"]:
    if p["name"] != "full":
        continue
    for f in p["feedbacks"]:
        if f.get("type") == "VibraPattern" and f["event-name"] in ("button-pressed", "key-pressed"):
            pairs.add((f["magnitudes"][0], f["durations"][0]))
names = {(0.015, 15): "low", (0.035, 15): "medium", (0.07, 15): "high"}
if len(pairs) == 1 and next(iter(pairs)) in names:
    print(names[next(iter(pairs))])
elif pairs:
    print("custom")
else:
    sys.exit(1)
PY
}

case $verb in
probe)
  if [[ -r $file ]] && current_level >/dev/null 2>&1; then
    printf '{"id":"haptics","state":"working","reason":"","risk":"none"}\n'
  else
    printf '{"id":"haptics","state":"unavailable","reason":"no keyboard haptics theme on this phone","risk":"none"}\n'
    exit 2
  fi
  ;;
get)
  [[ -r $file ]] || fail '{"error":"no keyboard haptics theme on this phone"}'
  lvl=$(current_level) || fail '{"error":"the haptics theme has no key entries"}'
  printf '{"level":"%s"}\n' "$lvl"
  ;;
set)
  [[ $key == level ]] || fail '{"error":"unknown key"}'
  if [[ $value == off ]]; then
    set_profile silent || fail '{"error":"could not set the feedbackd profile"}'
    printf '{"level":"off"}\n'
    exit 0
  fi
  pair=$(level_pair "$value") || fail '{"error":"bad value"}'
  mag=${pair% *}; ms=${pair#* }
  # defence in depth: the table above can never exceed the cap or 60 ms
  /usr/bin/python3 -I -c "import sys; sys.exit(0 if float('$mag') <= $cap and int('$ms') <= 60 else 1)" || fail '{"error":"above the safety cap"}'
  [[ -w $file ]] || fail '{"error":"theme file not writable"}'
  edit() { /usr/bin/python3 -I - "$file" "$mag" "$ms" "$1" <<'PY'
import json, os, sys, tempfile
path, mag, ms, mode = sys.argv[1], float(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
try:
    d = json.load(open(path))
    n = 0
    for p in d["profiles"]:
        if p["name"] != "full":
            continue
        for f in p["feedbacks"]:
            if f.get("type") == "VibraPattern" and f["event-name"] in ("button-pressed", "key-pressed"):
                f["magnitudes"] = [mag]
                f["durations"] = [ms]
                n += 1
except (OSError, ValueError, KeyError, TypeError):
    n = -1
if n != 2:
    print('{"error":"the haptics theme does not have the two key entries"}')
    sys.exit(2)
if mode == "write":
    real = os.path.realpath(path)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(real))
    try:
        with os.fdopen(fd, "w") as out:
            json.dump(d, out, indent=2)
            out.flush()
            os.fsync(out.fileno())
        os.chmod(tmp, os.stat(real).st_mode & 0o7777)
        os.replace(tmp, real)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
PY
  }
  # nothing is changed until the theme is known to be what this edit expects
  edit check || exit 2
  [[ -e $file.bak-haptics ]] || cp -p "$file" "$file.bak-haptics"
  # best effort: the strength edit below must work even where gsettings cannot be reached
  [[ $(get_profile) == silent ]] && { set_profile full || fail '{"error":"could not turn haptics back on"}'; }
  edit write || fail '{"error":"could not write the haptics theme"}'
  if [[ $dry != 1 ]]; then
    # feedbackd reads the theme when it starts; D-Bus starts it again on the next event. Exact name only.
    for p in $(pgrep -u "$(id -u)" -x feedbackd || true); do kill "$p" 2>/dev/null || true; done
    sleep 1
    # fbcli ends the feedback when its input closes, and the shell gives it none: keep it open for one pulse.
    sleep 0.02 | fbcli -E button-pressed -w 1 >/dev/null 2>&1 || true
  fi
  printf '{"level":"%s"}\n' "$value"
  ;;
watch)
  "$0" get
  ;;
*)
  fail '{"error":"usage: probe|get|set|watch"}'
  ;;
esac
