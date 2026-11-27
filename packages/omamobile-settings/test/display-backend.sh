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
def=$tmp/rate-default  # the device default file, absent unless a test writes it
sed -e "s|^fake=.*|fake=$fake|" -e "s|^default_file=.*|default_file=$def|" "$src/backends/display.sh" > "$tmp/display.sh"
grep -q "^fake=$fake" "$tmp/display.sh"
grep -q "^default_file=$def" "$tmp/display.sh"
run() { bash "$tmp/display.sh" "$@" || true; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }

eq "$(run get)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0,"default":0}'
eq "$(run set brightness 25)" '{"brightness":25,"refresh":120,"rates":[60,120],"saved":0,"default":0}'
eq "$(run set brightness 5)" '{"error":"bad value"}'
eq "$(run set brightness 101)" '{"error":"bad value"}'
eq "$(run set refresh 60)" '{"brightness":50,"refresh":60,"rates":[60,120],"saved":60,"default":0}'
rm -f "$XDG_CONFIG_HOME/omamobile/refresh-rate"  # the later gets start with no choice
eq "$(run set refresh 90)" '{"error":"this display does not list that rate"}'
eq "$(run set refresh abc)" '{"error":"bad value"}'
eq "$(run set night on)" '{"error":"unknown key"}'
eq "$(run nonsense)" '{"error":"usage: get|set|apply"}'

# one rate only: the page hides the refresh rate buttons
sed -i '2s/.*/[{"name":"HDMI-A-1","width":1920,"height":1080,"x":0,"y":0,"scale":1,"refreshRate":60.0,"availableModes":["1920x1080@60.00Hz"]}]/' "$fake"
eq "$(run get)" '{"brightness":50,"refresh":60,"rates":[60],"saved":0,"default":0}'
# two monitors: the built-in panel is picked
sed -i '2s/.*/[{"name":"HDMI-A-1","width":1920,"height":1080,"x":0,"y":0,"scale":1,"refreshRate":60.0,"availableModes":["1920x1080@60.00Hz"]},{"name":"DSI-1","width":1344,"height":2992,"x":0,"y":0,"scale":3.2,"transform":1,"refreshRate":120.0,"availableModes":["1344x2992@120.00Hz","1344x2992@60.00Hz"]}]/' "$fake"
eq "$(run get)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0,"default":0}'
# two external monitors and none focused: no monitor, but the brightness still works
sed -i '2s/.*/[{"name":"A-1","width":1,"height":1,"x":0,"y":0,"scale":1,"refreshRate":60.0},{"name":"B-1","width":1,"height":1,"x":0,"y":0,"scale":1,"refreshRate":60.0}]/' "$fake"
eq "$(run get)" '{"brightness":50,"refresh":-1,"rates":[],"saved":0,"default":0}'
eq "$(run set brightness 75)" '{"brightness":75,"refresh":-1,"rates":[],"saved":0,"default":0}'
eq "$(run set refresh 60)" '{"error":"cannot read the monitor"}'
# a monitor name that is not a plain connector name never reaches hyprctl
sed -i '2s/.*/[{"name":"X\"-1","width":1,"height":1,"x":0,"y":0,"scale":1,"refreshRate":60.0}]/' "$fake"
eq "$(run set refresh 60)" '{"error":"cannot read the monitor"}'
# one odd mode string does not take the others down
sed -i '2s/.*/[{"name":"DSI-1","width":1344,"height":2992,"x":0,"y":0,"scale":3.2,"refreshRate":120.0,"availableModes":["1344x2992@odd","1344x2992@60.00Hz","1344x2992@120.00Hz"]}]/' "$fake"
eq "$(run get)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0,"default":0}'
# the monitor query failing leaves the brightness working
sed -i '2s/.*/not json/' "$fake"
eq "$(run get)" '{"brightness":50,"refresh":-1,"rates":[],"saved":0,"default":0}'
# the choice is saved, survives a fake reload (apply), an unlisted saved rate falls back, preferred clears it
rf=$XDG_CONFIG_HOME/omamobile/refresh-rate
sed -i '2s/.*/[{"name":"DSI-1","width":1344,"height":2992,"x":0,"y":0,"scale":3.2,"refreshRate":120.0,"availableModes":["1344x2992@120.00Hz","1344x2992@60.00Hz"]}]/' "$fake"
eq "$(run set refresh 90)" '{"error":"this display does not list that rate"}'
[[ ! -e $rf ]] || { echo "FAIL: a refused rate was saved" >&2; exit 1; }
run set refresh 60 >/dev/null
eq "$(cat "$rf")" 60
eq "$(run apply)" '{"brightness":50,"refresh":60,"rates":[60,120],"saved":60,"default":0}'
echo 90 > "$rf"
eq "$(run apply)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0,"default":0}'
echo junk > "$rf"
eq "$(run apply)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0,"default":0}'
echo 60 > "$rf"
eq "$(run get)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":60,"default":0}'
echo 90 > "$rf"
eq "$(run get)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0,"default":0}'
echo 60 > "$rf"
# apply with no readable backlight still applies the rate
sed -i '1s/.*/x/' "$fake"
eq "$(run apply)" '{"brightness":-1,"refresh":60,"rates":[60,120],"saved":60,"default":0}'
sed -i '1s/.*/50/' "$fake"
eq "$(run set refresh preferred)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0,"default":0}'
[[ ! -e $rf ]] || { echo "FAIL: preferred did not clear the choice" >&2; exit 1; }
# the page offers Default (set refresh preferred) and marks the saved choice
grep -q '"set", "refresh", "preferred"' "$src/app/DisplayPage.qml" || { echo "FAIL: no Default button" >&2; exit 1; }
grep -q 'highlighted: page.saved === modelData' "$src/app/DisplayPage.qml" || { echo "FAIL: saved choice not marked" >&2; exit 1; }
grep -q 'r\["default"\]' "$src/app/DisplayPage.qml" && ! grep -q '60 Hz on this phone' "$src/app/DisplayPage.qml" \
  || { echo "FAIL: the page names a device default the backend did not report" >&2; exit 1; }
# the real path (no fake) with stand-in tools: apply with no valid saved rate sends no eval at all; a set saves the
# choice only after the panel reports the new rate; every set answer, brightness included, carries "saved"
mkdir -p "$tmp/bin"
real=$tmp/display-real.sh
sed "s|^default_file=.*|default_file=$def|" "$src/backends/display.sh" > "$real"
grep -q "^default_file=$def" "$real"
cat > "$tmp/bin/hyprctl" <<'EOT'
#!/bin/bash
# the panel's state: $TLOG/rate (120 when absent), $TLOG/dpms (true when absent); $TLOG/fails makes that many
# monitor reads fail first (a session start before the monitor is up); with $TLOG/stuck an eval exits 0 but changes
# nothing, like Hyprland with the screen off
if [[ $1 == monitors ]]; then
  if [[ -s $TLOG/fails ]]; then n=$(cat "$TLOG/fails"); echo $((n - 1)) > "$TLOG/fails"; ((n > 0)) && { echo 'not json'; exit 0; }; fi
  # a turned monitor: hyprctl reports the size swapped, the modes stay in the panel's orientation
  echo "[{\"name\":\"DSI-1\",\"width\":2992,\"height\":1344,\"x\":0,\"y\":0,\"scale\":3.2,\"transform\":1,\"refreshRate\":$(cat "$TLOG/rate" 2>/dev/null || echo 120).0,\"dpmsStatus\":$(cat "$TLOG/dpms" 2>/dev/null || echo true),\"availableModes\":[\"1344x2992@120.00Hz\",\"1344x2992@60.00Hz\"]}]"
else
  # a strict stub of ours (real Hyprland tries an unlisted mode as a custom one and falls back): it checks the token
  mode=$(sed -n 's/.*mode = "\([^"]*\)".*/\1/p' <<<"$2")
  if [[ $mode == preferred || $mode == 1344x2992@120.00 || $mode == 1344x2992@60.00 ]]; then
    echo "$*" >> "$TLOG/evals"; echo eval >> "$TLOG/order"; echo ok
    [[ $(cat "$TLOG/stuck" 2>/dev/null) != off-after-eval ]] || echo false > "$TLOG/dpms"
    [[ -e $TLOG/stuck ]] || { [[ $mode == *@60.00 ]] && echo 60 > "$TLOG/rate" || echo 120 > "$TLOG/rate"; }
  else echo "error: bad mode $mode"; fi
fi
EOT
cat > "$tmp/bin/sleep" <<'EOT'
#!/bin/bash
[[ -e $XDG_CONFIG_HOME/omamobile/refresh-rate ]] && echo saved >> "$TLOG/sleep" || echo missing >> "$TLOG/sleep"
[[ -z ${REAL_SLEEP:-} ]] || /usr/bin/sleep "$1"
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
export TLOG=$tmp/log XDG_RUNTIME_DIR=$tmp/run; mkdir -p "$TLOG"
rreal() { PATH="$tmp/bin:$PATH" bash "$real" "$@" || true; }
rm -f "$rf" "$TLOG"/*
eq "$(rreal apply)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0,"default":0}'
echo 90 > "$rf"
eq "$(rreal apply)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0,"default":0}'
echo junk > "$rf"; rreal apply >/dev/null
[[ ! -e $TLOG/evals ]] || { echo "FAIL: apply sent an eval with no valid saved rate" >&2; exit 1; }
eq "$(rreal set brightness 25)" '{"brightness":25,"refresh":120,"rates":[60,120],"saved":0,"default":0}'
echo 60 > "$rf"
eq "$(rreal set brightness 25)" '{"brightness":25,"refresh":120,"rates":[60,120],"saved":60,"default":0}'
rm -f "$rf"
rreal set refresh 60 >/dev/null
eq "$(sort -u "$TLOG/sleep")" missing  # nothing saved before the panel reported 60
eq "$(cat "$rf")" 60
grep -q 'transform = 1' "$TLOG/evals" || { echo "FAIL: transform not kept" >&2; exit 1; }
: > "$TLOG/evals"; rm -f "$TLOG/sleep"
rreal set refresh preferred >/dev/null
eq "$(sort -u "$TLOG/sleep")" saved  # the choice is forgotten only after the change
[[ ! -e $rf ]] || { echo "FAIL: preferred left the file" >&2; exit 1; }
echo 60 > "$rf"; : > "$TLOG/evals"; echo 120 > "$TLOG/rate"
rreal apply >/dev/null
[[ $(grep -c eval "$TLOG/evals") == 1 ]] && grep -q 'mode = "1344x2992@60.00"' "$TLOG/evals" || { echo "FAIL: apply of a listed saved rate" >&2; exit 1; }
# a device default (husky ships 60): with no saved choice apply sends it, only when listed; a saved choice wins;
# preferred goes back to it; "saved" stays 0 for it
rm -f "$rf"; echo 60 > "$def"; : > "$TLOG/evals"; echo 120 > "$TLOG/rate"
eq "$(rreal apply)" '{"brightness":50,"refresh":60,"rates":[60,120],"saved":0,"default":60}'
grep -q 'mode = "1344x2992@60.00"' "$TLOG/evals" || { echo "FAIL: apply did not send the device default" >&2; exit 1; }
echo 120 > "$rf"; : > "$TLOG/evals"  # the panel runs 60 now
rreal apply >/dev/null
grep -q 'mode = "1344x2992@120.00"' "$TLOG/evals" || { echo "FAIL: a saved rate lost to the device default" >&2; exit 1; }
: > "$TLOG/evals"
rreal set refresh preferred >/dev/null
grep -q 'mode = "1344x2992@60.00"' "$TLOG/evals" || { echo "FAIL: preferred did not go back to the device default" >&2; exit 1; }
[[ ! -e $rf ]] || { echo "FAIL: preferred left the file" >&2; exit 1; }
echo 90 > "$def"; : > "$TLOG/evals"
rreal apply >/dev/null
[[ ! -s $TLOG/evals ]] || { echo "FAIL: an unlisted device default sent an eval" >&2; exit 1; }
# a rate file is one bare 1 to 3 digit number and at most one trailing newline: anything else counts as no choice
# (the default 60 is sent, never the 120 in the odd file); a clean one, with or without its newline, wins
echo 60 > "$def"
for bad in '120 ' ' 120' '0120' '060' '012' '1e2' '120\n\n' '120\nfoo' '120\r\n'; do
  printf "$bad" > "$rf"; : > "$TLOG/evals"; echo 120 > "$TLOG/rate"
  rreal apply >/dev/null
  grep -q 'mode = "1344x2992@60.00"' "$TLOG/evals" || { echo "FAIL: odd rate file '$bad' was not ignored" >&2; exit 1; }
done
for good in '120' '120\n'; do
  printf "$good" > "$rf"; : > "$TLOG/evals"; echo 60 > "$TLOG/rate"
  rreal apply >/dev/null
  grep -q 'mode = "1344x2992@120.00"' "$TLOG/evals" || { echo "FAIL: clean rate file '$good' was ignored" >&2; exit 1; }
done
# no-op: the panel already runs the wanted rate, nothing is sent
echo 60 > "$rf"; echo 60 > "$TLOG/rate"; : > "$TLOG/evals"
eq "$(rreal apply)" '{"brightness":50,"refresh":60,"rates":[60,120],"saved":60,"default":60}'
[[ ! -s $TLOG/evals ]] || { echo "FAIL: apply sent an eval for the rate the panel already runs" >&2; exit 1; }
# read-back: an eval that exits 0 but does not take is a failure, never a claimed 60
echo 120 > "$TLOG/rate"; touch "$TLOG/stuck"
eq "$(rreal apply)" '{"error":"the screen did not take the rate","brightness":50,"refresh":120,"rates":[60,120],"saved":60,"default":60}'
rm -f "$rf"; eq "$(rreal set refresh 60)" '{"error":"the screen did not take the rate","brightness":50,"refresh":120,"rates":[60,120],"saved":0,"default":60}'
[[ ! -e $rf ]] || { echo "FAIL: a rate that did not take was saved" >&2; exit 1; }
echo 120 > "$rf"; eq "$(rreal set refresh preferred)" '{"error":"the screen did not take the rate","brightness":50,"refresh":120,"rates":[60,120],"saved":120,"default":60}'
eq "$(cat "$rf")" 120
# the screen turning off between the eval and the read-back is named as such
echo off-after-eval > "$TLOG/stuck"; echo 60 > "$TLOG/rate"
eq "$(rreal apply)" '{"error":"the screen turned off before the rate took","brightness":50,"refresh":60,"rates":[60,120],"saved":120,"default":60}'
rm -f "$TLOG/dpms"
# a save that fails after the rate took is an error that still reports the new rate
rm -f "$TLOG/stuck"; echo 120 > "$TLOG/rate"; rm -f "$rf"; mkdir -p "$rf"
eq "$(rreal set refresh 60)" '{"error":"could not save the choice","brightness":50,"refresh":60,"rates":[60,120],"saved":0,"default":60}'
rmdir "$rf"; echo 120 > "$TLOG/rate"
# preferred with no device default reports the rate read afterwards and forgets the choice
mv "$def" "$def.off"; echo 60 > "$rf"; echo 60 > "$TLOG/rate"
eq "$(rreal set refresh preferred)" '{"brightness":50,"refresh":120,"rates":[60,120],"saved":0,"default":0}'
[[ ! -e $rf ]] || { echo "FAIL: preferred left the file" >&2; exit 1; }
mv "$def.off" "$def"
rm -f "$TLOG/stuck" "$rf"
# the screen off (DPMS): nothing is sent and apply fails, saying when it is tried again
echo false > "$TLOG/dpms"; : > "$TLOG/evals"
eq "$(rreal apply)" '{"error":"the screen is off; the rate is applied at the next config reload, rotation or Settings tap"}'
[[ ! -s $TLOG/evals ]] || { echo "FAIL: apply sent an eval with the screen off" >&2; exit 1; }
rm -f "$TLOG/dpms"
# retry at a session start: 3 failed monitor reads, then it applies; 10 failed reads give up
echo 3 > "$TLOG/fails"; : > "$TLOG/evals"; rm -f "$TLOG/sleep"
eq "$(rreal apply)" '{"brightness":50,"refresh":60,"rates":[60,120],"saved":0,"default":60}'
echo 120 > "$TLOG/rate"; echo 10 > "$TLOG/fails"
eq "$(rreal apply)" '{"error":"cannot read the monitor"}'
rm -f "$TLOG/fails"
# the lock: an apply waits for one already running (held here for 1 s) and only then sends its eval
echo 120 > "$TLOG/rate"; rm -f "$TLOG/order"; mkdir -p "$XDG_RUNTIME_DIR"
( exec 9>"$XDG_RUNTIME_DIR/omamobile-display.lock"; flock 9; touch "$TLOG/held"; /usr/bin/sleep 1; echo released >> "$TLOG/order" ) &
for _ in $(seq 50); do [[ -e $TLOG/held ]] && break; /usr/bin/sleep 0.1; done
rreal apply >/dev/null; wait
eq "$(tr '\n' ' ' < "$TLOG/order")" 'released eval '
# two applies at once (session start and the first reload): one eval, the second finds 60 and sends nothing
echo 120 > "$TLOG/rate"; : > "$TLOG/evals"
REAL_SLEEP=1 rreal apply >/dev/null & REAL_SLEEP=1 rreal apply >/dev/null; wait
eq "$(grep -c eval "$TLOG/evals")" 1
rm -f "$rf"
eq "$(run apply)" '{"brightness":50,"refresh":60,"rates":[60,120],"saved":0,"default":60}'
eq "$(run set refresh preferred)" '{"brightness":50,"refresh":60,"rates":[60,120],"saved":0,"default":60}'
rm -f "$def"
echo "display backend: ok"
