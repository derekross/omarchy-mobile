#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-keyboard-switch against a fake hyprctl and a fake
# omamobile-keyboard-languages: only real keyboards are switched (never
# squeekboard's hl-virtual-keyboard or a consumer-control pseudo-keyboard),
# next wraps around, the OSK gets the layout by name (layout+variant), and
# listen follows activelayout events from real keyboards only.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export T=$t
cat >"$t/hyprctl" <<'SH'
#!/bin/bash
case "$1 $2" in
  "-j devices") cat "$T/devices.json" ;;
  --batch*) printf '%s\n' "$2" >>"$T/hypr.log" ;;
  *) exit 1 ;;
esac
SH
cat >"$t/languages" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$T/osk.log"
SH
chmod +x "$t/hyprctl" "$t/languages"
cat >"$t/devices.json" <<'J'
{"keyboards":[
{"name":"hl-virtual-keyboard-squeekboard","layout":"us","variant":"","active_layout_index":0,"main":false},
{"name":"dell-kb7120w-consumer-control","layout":"us,gr","variant":",polytonic","active_layout_index":0,"main":false},
{"name":"dell-kb7120w","layout":"us,gr","variant":",polytonic","active_layout_index":1,"main":true},
{"name":"other-kbd","layout":"us,gr","variant":",polytonic","active_layout_index":1,"main":false},
{"name":"bad name;exec x","layout":"us,gr","variant":",polytonic","active_layout_index":1,"main":false}]}
J
export OMAMOBILE_HYPRCTL=$t/hyprctl OMAMOBILE_KBD_LANGUAGES=$t/languages HYPRLAND_INSTANCE_SIGNATURE=test
s=bin/omamobile-keyboard-switch

python3 -B "$s" next 2>"$t/err"
grep -q "skipping keyboard 'bad name;exec x'" "$t/err" || fail "a name with a space or ; is left out of the batch"
[[ $(cat "$t/hypr.log") == "switchxkblayout dell-kb7120w 0; switchxkblayout other-kbd 0" ]] || fail "next wraps to 0 on real keyboards only: $(cat "$t/hypr.log")"
[[ $(cat "$t/osk.log") == "set us" ]] || fail "next puts us first in the OSK list"
pass "keyboard-switch next"

: >"$t/hypr.log"; : >"$t/osk.log"
python3 -B "$s" set 1
[[ $(cat "$t/hypr.log") == "switchxkblayout dell-kb7120w 1; switchxkblayout other-kbd 1" ]] || fail "set 1"
[[ $(cat "$t/osk.log") == "set gr+polytonic" ]] || fail "set 1 puts gr+polytonic first"
: >"$t/hypr.log"; : >"$t/osk.log"
python3 -B "$s" lock
[[ $(cat "$t/hypr.log") == "switchxkblayout dell-kb7120w 0; switchxkblayout other-kbd 0" && $(cat "$t/osk.log") == "set us" ]] || fail "lock goes to layout 0"
pass "keyboard-switch set and lock"

python3 -B "$s" bogus 2>/dev/null && fail "unknown verb fails"
pass "keyboard-switch refuses unknown verbs"

# listen: a fake socket2 sends a squeekboard event (ignored) and a hardware one
mkdir -p "$t/run/hypr/test"
: >"$t/osk.log"
python3 -B - "$t/run/hypr/test/.socket2.sock" <<'PY' &
import socket, sys
s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(1)
c, _ = s.accept()
c.sendall(b"workspace>>1\nactivelayout>>hl-virtual-keyboard-squeekboard,English (US)\nactivelayout>>dell-kb7120w,Greek (polytonic)\n")
c.close()
PY
server=$!
for _ in $(seq 50); do [[ -S $t/run/hypr/test/.socket2.sock ]] && break; sleep 0.1; done
XDG_RUNTIME_DIR=$t/run timeout 10 python3 -B "$s" listen
wait "$server"
[[ $(cat "$t/osk.log") == "set gr+polytonic" ]] || fail "listen follows hardware events only: $(cat "$t/osk.log")"
pass "keyboard-switch listen"

# listen brings the other real keyboards to the index of the one switched (dell on 1, other-kbd on 0)
cat >"$t/devices.json" <<'J'
{"keyboards":[
{"name":"hl-virtual-keyboard-squeekboard","layout":"us","variant":"","active_layout_index":0,"main":true},
{"name":"gpio-keys","layout":"us,gr","variant":",polytonic","active_layout_index":0,"main":false},
{"name":"dell-kb7120w","layout":"us,gr","variant":",polytonic","active_layout_index":1,"main":false},
{"name":"other-kbd","layout":"us,gr","variant":",polytonic","active_layout_index":0,"main":false}]}
J
rm -f "$t/run/hypr/test/.socket2.sock"; : >"$t/hypr.log"; : >"$t/osk.log"
python3 -B -c '
import socket, sys
s = socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(1)
c, _ = s.accept()
c.sendall(b"activelayout>>dell-kb7120w,Greek (polytonic)\n")
c.close()' "$t/run/hypr/test/.socket2.sock" &
server=$!
for _ in $(seq 50); do [[ -S $t/run/hypr/test/.socket2.sock ]] && break; sleep 0.1; done
XDG_RUNTIME_DIR=$t/run timeout 10 python3 -B "$s" listen
wait "$server"
[[ $(cat "$t/hypr.log") == "switchxkblayout other-kbd 1" ]] || fail "listen syncs the other real keyboards: $(cat "$t/hypr.log")"
[[ $(cat "$t/osk.log") == "set gr+polytonic" ]] || fail "listen moves the OSK after the sync"
pass "keyboard-switch listen syncs other keyboards"

# main pick with no real keyboard marked main: the first real one with more than one layout
# (not the virtual one marked main, not gpio-keys, not a one-layout keyboard)
cat >"$t/devices.json" <<'J'
{"keyboards":[
{"name":"hl-virtual-keyboard-squeekboard","layout":"us","variant":"","active_layout_index":0,"main":true},
{"name":"gpio-keys","layout":"us,gr","variant":"","active_layout_index":0,"main":false},
{"name":"single","layout":"us","variant":"","active_layout_index":0,"main":false},
{"name":"dell-kb7120w","layout":"us,gr","variant":",polytonic","active_layout_index":1,"main":false}]}
J
: >"$t/hypr.log"; : >"$t/osk.log"
python3 -B "$s" next
[[ $(cat "$t/osk.log") == "set us" ]] || fail "next steps from the first real keyboard with 2+ layouts: $(cat "$t/osk.log")"
pass "keyboard-switch main keyboard rule"
