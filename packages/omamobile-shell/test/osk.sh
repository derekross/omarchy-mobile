#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-osk against a scratch home and fake keyboards: the choice, the
# fallback to squeekboard, and how a change of keyboard is carried out.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
F=$t/fakes; H=$t/home; mkdir -p "$F" "$H"
fake() { printf '#!/bin/bash\n%s\n' "$2" >"$F/$1"; chmod +x "$F/$1"; }
# Only the fakes and the few real tools the script and the fakes use: a keyboard installed on the
# machine that runs the tests (tactus in /usr/bin) must not count
for tool in bash head tr id mkdir mv seq sleep sed rm; do ln -s "$(command -v "$tool")" "$F/$tool"; done
fake squeekboard 'echo "squeekboard runs"'
# pgrep: a keyboard runs while $T/running-NAME exists; pkill stops it
fake pgrep 'name=${!#}; [[ -e $T/running-$name ]]'
fake pkill 'name=${!#}; echo "pkill $name" >>"$T/calls"; rm -f "$T/running-$name"'
fake hyprctl 'echo "hyprctl $*" >>"$T/calls"'
fake uwsm-app 'echo "uwsm-app $*" >>"$T/calls"'
fake setsid 'echo "setsid $*" >>"$T/calls"'
# systemctl: the keyboard's unit is active while $T/unit-active exists
fake systemctl 'echo "systemctl $*" >>"$T/calls"; [[ $* != *is-active* || -e $T/unit-active ]]'
osk() { env -i HOME="$H" T="$t" PATH="$F" "${EXTRA[@]}" bash bin/omamobile-osk "$@"; }
EXTRA=(X=1)
calls() { cat "$t/calls" 2>/dev/null || true; }

# Only squeekboard installed
[[ $(osk which) == squeekboard && $(osk list) == squeekboard ]] || fail "with nothing chosen and one keyboard: squeekboard"
rc=0; osk use tactus 2>"$t/err" || rc=$?
[[ $rc == 1 && ! -e $H/.config/omamobile/keyboard ]] && grep -c "tactus is not installed" "$t/err" >/dev/null || fail "a keyboard that isn't installed can't be chosen"
rc=0; osk use other 2>/dev/null || rc=$?; [[ $rc == 2 ]] || fail "only the two keyboards have names"
rc=0; osk frobnicate 2>"$t/err" || rc=$?; [[ $rc == 2 ]] && grep -c "omamobile-osk use NAME" "$t/err" >/dev/null || fail "anything else prints the usage"
[[ $(osk) == "squeekboard runs" ]] || fail "run: squeekboard"
pass "one keyboard: squeekboard, and nothing else can be chosen"

# Tactus installed beside it
fake tactus 'echo "tactus runs"'
[[ $(osk list | tr '\n' ' ') == "squeekboard tactus " && $(osk which) == squeekboard ]] || fail "installing Tactus chooses nothing"
touch "$t/running-squeekboard"; : >"$t/calls"
EXTRA=(HYPRLAND_INSTANCE_SIGNATURE=x)
osk use tactus
[[ $(cat "$H/.config/omamobile/keyboard") == tactus && $(osk which) == tactus ]] || fail "the choice is kept"
grep -cx 'pkill -u [0-9]* -x squeekboard\|pkill squeekboard' "$t/calls" >/dev/null || fail "the keyboard that ran is stopped: $(calls)"
grep -cxF 'hyprctl dispatch hl.dsp.exec_cmd("uwsm-app -- omamobile-osk")' "$t/calls" >/dev/null || fail "the other is started through Hyprland, as the autostart starts it: $(calls)"
if grep -c 'pkill.*tactus\|systemctl --user restart' "$t/calls" >/dev/null; then fail "nothing else is stopped or restarted: $(calls)"; fi
[[ $(osk) == "tactus runs" ]] || fail "run: the chosen keyboard"
pass "a change of keyboard: the choice kept, the old one stopped, the new one started through Hyprland"

# Outside Hyprland (a terminal, SSH)
touch "$t/running-tactus"; : >"$t/calls"
EXTRA=(X=1)
osk use squeekboard
grep -cx 'setsid -f uwsm-app -- omamobile-osk' "$t/calls" >/dev/null || fail "without Hyprland it is started detached: $(calls)"
[[ $(osk which) == squeekboard ]] || fail "back to squeekboard"
pass "without Hyprland the keyboard is started detached"

# A session that runs the keyboard as squeekboard's user unit
touch "$t/unit-active" "$t/running-squeekboard"; : >"$t/calls"
osk use tactus
grep -cx 'systemctl --user restart mobi.phosh.OSK.service' "$t/calls" >/dev/null || fail "the unit is restarted: $(calls)"
if grep -c 'pkill\|hyprctl\|setsid' "$t/calls" >/dev/null; then fail "with the unit nothing is stopped or started by hand: $(calls)"; fi
rm -f "$t/unit-active"
pass "where the keyboard runs as a unit, the unit is restarted"

# The choice outlives nothing it shouldn't
rm -f "$F/tactus"
[[ $(osk which) == squeekboard && $(osk) == "squeekboard runs" ]] || fail "Tactus chosen and then removed: squeekboard"
fake tactus 'echo "tactus runs"'
printf 'something else\n' >"$H/.config/omamobile/keyboard"
[[ $(osk which) == squeekboard ]] || fail "anything else in the file: squeekboard"
printf '  tactus  \nmore\n' >"$H/.config/omamobile/keyboard"
[[ $(osk which) == tactus ]] || fail "the first word is the choice"
pass "a choice that can't be met, or isn't one, means squeekboard"
