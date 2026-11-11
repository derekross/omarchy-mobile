#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/display.sh against a fake brightness and monitor, in a copy of the script with `fake` set: no tool is run.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
fake=$tmp/fake
cat > "$fake" <<'EOT'
50
[{"name":"DSI-1","width":1344,"height":2992,"x":0,"y":0,"scale":3.2,"refreshRate":120.000,"availableModes":["1344x2992@120.00Hz","1344x2992@60.00Hz","1008x2244@120.00Hz"]}]
EOT
sed "s|^fake=.*|fake=$fake|" "$src/backends/display.sh" > "$tmp/display.sh"
grep -q "^fake=$fake" "$tmp/display.sh"
run() { bash "$tmp/display.sh" "$@" || true; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }

eq "$(run get)" '{"brightness":50,"refresh":120,"rates":[60,120]}'
eq "$(run set brightness 25)" '{"brightness":25,"refresh":120,"rates":[60,120]}'
eq "$(run set brightness 5)" '{"error":"bad value"}'
eq "$(run set brightness 101)" '{"error":"bad value"}'
eq "$(run set refresh 60)" '{"brightness":50,"refresh":60,"rates":[60,120]}'
eq "$(run set refresh 90)" '{"error":"this display does not list that rate"}'
eq "$(run set refresh abc)" '{"error":"bad value"}'
eq "$(run set night on)" '{"error":"unknown key"}'
eq "$(run nonsense)" '{"error":"usage: get|set"}'

# one rate only: the page hides the refresh rate buttons
sed -i '2s/.*/[{"name":"HDMI-A-1","width":1920,"height":1080,"x":0,"y":0,"scale":1,"refreshRate":60.0,"availableModes":["1920x1080@60.00Hz"]}]/' "$fake"
eq "$(run get)" '{"brightness":50,"refresh":60,"rates":[60]}'
# two monitors: the built-in panel is picked
sed -i '2s/.*/[{"name":"HDMI-A-1","width":1920,"height":1080,"x":0,"y":0,"scale":1,"refreshRate":60.0,"availableModes":["1920x1080@60.00Hz"]},{"name":"DSI-1","width":1344,"height":2992,"x":0,"y":0,"scale":3.2,"transform":1,"refreshRate":120.0,"availableModes":["1344x2992@120.00Hz","1344x2992@60.00Hz"]}]/' "$fake"
eq "$(run get)" '{"brightness":50,"refresh":120,"rates":[60,120]}'
# two external monitors and none focused: no monitor, but the brightness still works
sed -i '2s/.*/[{"name":"A-1","width":1,"height":1,"x":0,"y":0,"scale":1,"refreshRate":60.0},{"name":"B-1","width":1,"height":1,"x":0,"y":0,"scale":1,"refreshRate":60.0}]/' "$fake"
eq "$(run get)" '{"brightness":50,"refresh":-1,"rates":[]}'
eq "$(run set brightness 75)" '{"brightness":75,"refresh":-1,"rates":[]}'
eq "$(run set refresh 60)" '{"error":"cannot read the monitor"}'
# a monitor name that is not a plain connector name never reaches hyprctl
sed -i '2s/.*/[{"name":"X\"-1","width":1,"height":1,"x":0,"y":0,"scale":1,"refreshRate":60.0}]/' "$fake"
eq "$(run set refresh 60)" '{"error":"cannot read the monitor"}'
# one odd mode string does not take the others down
sed -i '2s/.*/[{"name":"DSI-1","width":1344,"height":2992,"x":0,"y":0,"scale":3.2,"refreshRate":120.0,"availableModes":["1344x2992@odd","1344x2992@60.00Hz","1344x2992@120.00Hz"]}]/' "$fake"
eq "$(run get)" '{"brightness":50,"refresh":120,"rates":[60,120]}'
# the monitor query failing leaves the brightness working
sed -i '2s/.*/not json/' "$fake"
eq "$(run get)" '{"brightness":50,"refresh":-1,"rates":[]}'
echo "display backend: ok"
