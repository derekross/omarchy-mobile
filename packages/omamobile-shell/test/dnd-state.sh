#!/bin/bash
# SPDX-License-Identifier: MIT
# The Do Not Disturb read in the quick-settings tile and the home toggles,
# against a stand-in `qs`: Omarchy 4.5's notification service answers isDnd
# and says "Function not found" to 4.0's dndState, and 4.0's the other way
# round. Both callers run the same line, taken here from the QML itself.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
line() {
  python3 - "$1" <<'PY'
import json, re, sys
m = re.search(r'\["sh", "-c", ("(?:[^"\\]|\\.)*"), "sh", Quickshell\.shellDir\]', open(sys.argv[1]).read().split("isDnd", 1)[0][-400:] + "isDnd" + open(sys.argv[1]).read().split("isDnd", 1)[1][:400])
if not m: sys.exit("no Do Not Disturb read in " + sys.argv[1])
print(json.loads(m.group(1)), end="")
PY
}
qs_line=$(line plugins/omamobile.quicksettings/QuickSettings.qml) || fail "found the tile's read"
home_line=$(line plugins/omamobile.home/TogglesWidget.qml) || fail "found the home toggles' read"
[[ $qs_line == "$home_line" ]] || fail "the tile and the home toggles read Do Not Disturb the same way"
mkdir -p "$t/bin"
cat > "$t/bin/qs" <<'QS'
#!/bin/sh
# qs ipc -p DIR call notifications METHOD
echo "$6" >> "$T/calls"
if [ "$6" = "$HAVE" ]; then echo "$STATE"; else echo "Function not found."; fi
QS
chmod +x "$t/bin/qs"
ask() { : > "$t/calls"; T=$t HAVE=$1 STATE=$2 PATH="$t/bin:$PATH" sh -c "$qs_line" sh /some/dir; }
[[ $(ask isDnd on) == on && $(cat "$t/calls") == isDnd ]] || fail "Omarchy 4.5: isDnd is asked first and its answer is used"
[[ $(ask isDnd off) == off ]] || fail "Omarchy 4.5: off is read as off"
[[ $(ask dndState on) == on && $(tr '\n' ' ' < "$t/calls") == "isDnd dndState " ]] || fail "Omarchy 4.0: dndState is asked when isDnd isn't there"
[[ -z $(ask neither on) ]] || fail "neither name: nothing is printed, so the tile keeps its state"
pass "Do Not Disturb is read with isDnd on Omarchy 4.5 and dndState on 4.0, the same way in both places"
