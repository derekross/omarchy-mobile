#!/bin/bash
# SPDX-License-Identifier: MIT
# Keyboard haptics level: probe/get/set. The level is the strength of one 15 ms tick that feedbackd plays for key and
# button presses. It lives in the user's feedbackd theme ($XDG_CONFIG_HOME/feedbackd/themes/custom.json, entries
# button-pressed and key-pressed of the "full" profile); where that theme comes from is the keyboard haptics notes in
# https://github.com/derekross/omarchy-mobile/issues/538. Levels (motor level of 255 in brackets):
#   low 0.015 (3, the lowest), medium 0.035 (8), high 0.07 (17), all 15 ms: only the strength differs.
# Nothing above 0.125 and nothing longer than 60 ms is ever written.
# Only the two key entries of the theme are written. feedbackd's profile, and so whether calls, messages and alarms
# ring, is never touched here: a keyboard page does not change that. Changing the level restarts feedbackd (a ring
# in progress stops).
# The theme directory comes from XDG_CONFIG_HOME, else HOME; nothing else in the environment is read (python3 is
# called by its absolute path, the helper tools by PATH). The test runs a copy
# of this script with `dry=1`, which skips feedbackd and the preview tick. The theme file is checked (exactly the
# two key entries in the full profile) before anything is changed.
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

# Prints the level; exit 3: the theme does not have exactly the two key entries (the same rule set applies);
# exit 4: it cannot be read as a theme.
current_level() {
  /usr/bin/python3 -I - "$file" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    pairs = []
    for p in d["profiles"]:
        if p["name"] != "full":
            continue
        for f in p["feedbacks"]:
            if f.get("type") == "VibraPattern" and f["event-name"] in ("button-pressed", "key-pressed"):
                pairs.append((f["magnitudes"][0], f["durations"][0]))
except Exception:
    sys.exit(4)
if len(pairs) != 2:
    sys.exit(3)
names = {(0.015, 15): "low", (0.035, 15): "medium", (0.07, 15): "high"}
if pairs[0] == pairs[1] and pairs[0] in names:
    print(names[pairs[0]])
else:
    print("custom")
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
  rc=0; lvl=$(current_level) || rc=$?
  case $rc in
    0) ;;
    3) fail '{"error":"the haptics theme does not have the two key entries"}' ;;
    *) fail '{"error":"the haptics theme could not be read"}' ;;
  esac
  printf '{"level":"%s"}\n' "$lvl"
  ;;
set)
  [[ $key == level ]] || fail '{"error":"unknown key"}'
  pair=$(level_pair "$value") || fail '{"error":"bad value"}'
  mag=${pair% *}; ms=${pair#* }
  # defence in depth: the table above can never exceed the cap or 60 ms
  /usr/bin/python3 -I -c "import sys; sys.exit(0 if float('$mag') <= $cap and int('$ms') <= 60 else 1)" || fail '{"error":"above the safety cap"}'
  [[ -e $file ]] || fail '{"error":"no keyboard haptics theme on this phone"}'
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
except Exception:
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
        print('{"error":"could not write the haptics theme"}')
        sys.exit(2)
PY
  }
  # nothing is changed until the theme is known to be what this edit expects
  edit check || exit 2
  [[ -e $file.bak-haptics ]] || cp -p "$file" "$file.bak-haptics" || fail '{"error":"could not keep a copy of the haptics theme"}'
  edit write || exit 2
  if [[ $dry != 1 ]]; then
    # feedbackd reads the theme when it starts; D-Bus starts it again on the next event. Exact name only.
    for p in $(pgrep -u "$(id -u)" -x feedbackd || true); do kill "$p" 2>/dev/null || true; done
    sleep 1
    # fbcli ends the feedback when its input closes, and the shell gives it none: keep it open for one pulse.
    sleep 0.02 | fbcli -E button-pressed -w 1 >/dev/null 2>&1 || true
  fi
  printf '{"level":"%s"}\n' "$value"
  ;;
*)
  fail '{"error":"usage: probe|get|set"}'
  ;;
esac
