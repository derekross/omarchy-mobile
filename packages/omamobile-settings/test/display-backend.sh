#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/display.sh against a fake brightness and monitor, in a copy of the script with `fake` set: no tool is run.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
fake=$tmp/fake
export HOME=$tmp/home XDG_CONFIG_HOME=$tmp/home/.config
cat > "$fake" <<'EOT'
50
[{"name":"DSI-1","width":1344,"height":2992,"x":0,"y":0,"scale":3.2,"refreshRate":120.000,"availableModes":["1344x2992@120.00Hz","1344x2992@60.00Hz","1008x2244@120.00Hz"]}]
EOT
sed "s|^fake=.*|fake=$fake|" "$src/backends/display.sh" > "$tmp/display.sh"
grep -q "^fake=$fake" "$tmp/display.sh"
run() { bash "$tmp/display.sh" "$@" || true; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }

eq "$(run get)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0}'
eq "$(run set brightness 25)" '{"brightness":25,"refresh":120,"rates":[60,120],"saved":0}'
eq "$(run set brightness 5)" '{"error":"bad value"}'
eq "$(run set brightness 101)" '{"error":"bad value"}'
eq "$(run set refresh 60)" '{"brightness":50,"refresh":60,"rates":[60,120],"saved":60}'
rm -f "$XDG_CONFIG_HOME/omamobile/refresh-rate"  # the later gets start with no choice
eq "$(run set refresh 90)" '{"error":"this display does not list that rate"}'
eq "$(run set refresh abc)" '{"error":"bad value"}'
eq "$(run set night on)" '{"error":"unknown key"}'
eq "$(run nonsense)" '{"error":"usage: get|set|apply"}'

# one rate only: the page hides the refresh rate buttons
sed -i '2s/.*/[{"name":"HDMI-A-1","width":1920,"height":1080,"x":0,"y":0,"scale":1,"refreshRate":60.0,"availableModes":["1920x1080@60.00Hz"]}]/' "$fake"
eq "$(run get)" '{"brightness":50,"refresh":60,"rates":[60],"saved":0}'
# two monitors: the built-in panel is picked
sed -i '2s/.*/[{"name":"HDMI-A-1","width":1920,"height":1080,"x":0,"y":0,"scale":1,"refreshRate":60.0,"availableModes":["1920x1080@60.00Hz"]},{"name":"DSI-1","width":1344,"height":2992,"x":0,"y":0,"scale":3.2,"transform":1,"refreshRate":120.0,"availableModes":["1344x2992@120.00Hz","1344x2992@60.00Hz"]}]/' "$fake"
eq "$(run get)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0}'
# two external monitors and none focused: no monitor, but the brightness still works
sed -i '2s/.*/[{"name":"A-1","width":1,"height":1,"x":0,"y":0,"scale":1,"refreshRate":60.0},{"name":"B-1","width":1,"height":1,"x":0,"y":0,"scale":1,"refreshRate":60.0}]/' "$fake"
eq "$(run get)" '{"brightness":50,"refresh":-1,"rates":[],"saved":0}'
eq "$(run set brightness 75)" '{"brightness":75,"refresh":-1,"rates":[],"saved":0}'
eq "$(run set refresh 60)" '{"error":"cannot read the monitor"}'
# a monitor name that is not a plain connector name never reaches hyprctl
sed -i '2s/.*/[{"name":"X\"-1","width":1,"height":1,"x":0,"y":0,"scale":1,"refreshRate":60.0}]/' "$fake"
eq "$(run set refresh 60)" '{"error":"cannot read the monitor"}'
# one odd mode string does not take the others down
sed -i '2s/.*/[{"name":"DSI-1","width":1344,"height":2992,"x":0,"y":0,"scale":3.2,"refreshRate":120.0,"availableModes":["1344x2992@odd","1344x2992@60.00Hz","1344x2992@120.00Hz"]}]/' "$fake"
eq "$(run get)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0}'
# the monitor query failing leaves the brightness working
sed -i '2s/.*/not json/' "$fake"
eq "$(run get)" '{"brightness":50,"refresh":-1,"rates":[],"saved":0}'
# the choice is saved, survives a fake reload (apply), an unlisted saved rate falls back, preferred clears it
rf=$XDG_CONFIG_HOME/omamobile/refresh-rate
sed -i '2s/.*/[{"name":"DSI-1","width":1344,"height":2992,"x":0,"y":0,"scale":3.2,"refreshRate":120.0,"availableModes":["1344x2992@120.00Hz","1344x2992@60.00Hz"]}]/' "$fake"
eq "$(run set refresh 90)" '{"error":"this display does not list that rate"}'
[[ ! -e $rf ]] || { echo "FAIL: a refused rate was saved" >&2; exit 1; }
run set refresh 60 >/dev/null
eq "$(cat "$rf")" 60
eq "$(run apply)" '{"brightness":50,"refresh":60,"rates":[60,120],"saved":60}'
echo 90 > "$rf"
eq "$(run apply)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0}'
echo junk > "$rf"
eq "$(run apply)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0}'
echo 60 > "$rf"
eq "$(run get)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":60}'
echo 90 > "$rf"
eq "$(run get)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0}'
echo 60 > "$rf"
# apply with no readable backlight still applies the rate
sed -i '1s/.*/x/' "$fake"
eq "$(run apply)" '{"brightness":-1,"refresh":60,"rates":[60,120],"saved":60}'
sed -i '1s/.*/50/' "$fake"
eq "$(run set refresh preferred)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0}'
[[ ! -e $rf ]] || { echo "FAIL: preferred did not clear the choice" >&2; exit 1; }
# the page offers Default (set refresh preferred) and marks the saved choice
grep -q '"set", "refresh", "preferred"' "$src/app/DisplayPage.qml" || { echo "FAIL: no Default button" >&2; exit 1; }
grep -q 'highlighted: page.saved === modelData' "$src/app/DisplayPage.qml" || { echo "FAIL: saved choice not marked" >&2; exit 1; }
# the real path (no fake) with stand-in tools: apply with no valid saved rate sends no eval at all; a set saves the
# choice before its pause; every set answer, brightness included, carries "saved"
mkdir -p "$tmp/bin"
real=$tmp/display-real.sh
cp "$src/backends/display.sh" "$real"
cat > "$tmp/bin/hyprctl" <<'EOT'
#!/bin/bash
if [[ $1 == monitors ]]; then
  # a turned monitor: hyprctl reports the size swapped, the modes stay in the panel's orientation
  echo '[{"name":"DSI-1","width":2992,"height":1344,"x":0,"y":0,"scale":3.2,"transform":1,"refreshRate":120.0,"availableModes":["1344x2992@120.00Hz","1344x2992@60.00Hz"]}]'
else
  # like Hyprland: a mode the monitor does not list is an error
  mode=$(sed -n 's/.*mode = "\([^"]*\)".*/\1/p' <<<"$2")
  if [[ $mode == preferred || $mode == 1344x2992@120.00 || $mode == 1344x2992@60.00 ]]; then echo "$*" >> "$TLOG/evals"; echo ok
  else echo "error: bad mode $mode"; fi
fi
EOT
cat > "$tmp/bin/sleep" <<'EOT'
#!/bin/bash
[[ -e $XDG_CONFIG_HOME/omamobile/refresh-rate ]] && echo saved >> "$TLOG/sleep" || echo missing >> "$TLOG/sleep"
EOT
cat > "$tmp/bin/omarchy-hw-display" <<'EOT'
#!/bin/bash
echo fake
EOT
cat > "$tmp/bin/brightnessctl" <<'EOT'
#!/bin/bash
echo "fake,backlight,1,50%,100"
EOT
chmod +x "$tmp"/bin/*
export TLOG=$tmp/log; mkdir -p "$TLOG"
rreal() { PATH="$tmp/bin:$PATH" bash "$real" "$@" || true; }
rm -f "$rf" "$TLOG"/*
eq "$(rreal apply)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0}'
echo 90 > "$rf"
eq "$(rreal apply)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0}'
echo junk > "$rf"; rreal apply >/dev/null
[[ ! -e $TLOG/evals ]] || { echo "FAIL: apply sent an eval with no valid saved rate" >&2; exit 1; }
eq "$(rreal set brightness 25)" '{"brightness":25,"refresh":120,"rates":[60,120],"saved":0}'
echo 60 > "$rf"
eq "$(rreal set brightness 25)" '{"brightness":25,"refresh":120,"rates":[60,120],"saved":60}'
rm -f "$rf"
rreal set refresh 60 >/dev/null
eq "$(cat "$TLOG/sleep")" saved
grep -q 'transform = 1' "$TLOG/evals" || { echo "FAIL: transform not kept" >&2; exit 1; }
: > "$TLOG/evals"; rm -f "$TLOG/sleep"
rreal set refresh preferred >/dev/null
eq "$(cat "$TLOG/sleep")" missing
[[ ! -e $rf ]] || { echo "FAIL: preferred left the file" >&2; exit 1; }
echo 60 > "$rf"; : > "$TLOG/evals"
rreal apply >/dev/null
[[ $(grep -c eval "$TLOG/evals") == 1 ]] && grep -q 'mode = "1344x2992@60.00"' "$TLOG/evals" || { echo "FAIL: apply of a listed saved rate" >&2; exit 1; }
echo "display backend: ok"
