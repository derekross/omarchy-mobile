#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-keyboard-switch against a fake hyprctl: only real keyboards are
# switched (never squeekboard's hl-virtual-keyboard or a consumer-control
# pseudo-keyboard), next wraps around, and the on-screen keyboard is never
# touched (no gsettings, no omamobile-keyboard-languages: both are fakes on
# PATH that log a call).
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export T=$t
mkdir -p "$t/bin"
cat >"$t/bin/hyprctl" <<'SH'
#!/bin/bash
case "$1 $2" in
  "-j devices") cat "$T/devices.json" ;;
  --batch*) printf '%s\n' "$2" >>"$T/hypr.log" ;;
  *) exit 1 ;;
esac
SH
for f in gsettings omamobile-keyboard-languages; do
  printf '#!/bin/bash\necho "%s $*" >>"$T/osk.log"\n' "$f" >"$t/bin/$f"
done
chmod +x "$t/bin/"*
export PATH="$t/bin:$PATH"
cat >"$t/devices.json" <<'J'
{"keyboards":[
{"name":"hl-virtual-keyboard-squeekboard","layout":"us","variant":"","active_layout_index":0,"main":false},
{"name":"dell-kb7120w-consumer-control","layout":"us,gr","variant":",polytonic","active_layout_index":0,"main":false},
{"name":"dell-kb7120w","layout":"us,gr","variant":",polytonic","active_layout_index":1,"main":true},
{"name":"other-kbd","layout":"us,gr","variant":",polytonic","active_layout_index":1,"main":false},
{"name":"bad name;exec x","layout":"us,gr","variant":",polytonic","active_layout_index":1,"main":false}]}
J
export OMAMOBILE_HYPRCTL=$t/bin/hyprctl HYPRLAND_INSTANCE_SIGNATURE=test
s=bin/omamobile-keyboard-switch

python3 -B "$s" next 2>"$t/err"
grep -q "skipping keyboard 'bad name;exec x'" "$t/err" || fail "a name with a space or ; is left out of the batch"
[[ $(cat "$t/hypr.log") == "switchxkblayout dell-kb7120w 0; switchxkblayout other-kbd 0" ]] || fail "next wraps to 0 on real keyboards only: $(cat "$t/hypr.log")"
pass "keyboard-switch next"

: >"$t/hypr.log"
python3 -B "$s" set 1
[[ $(cat "$t/hypr.log") == "switchxkblayout dell-kb7120w 1; switchxkblayout other-kbd 1" ]] || fail "set 1"
: >"$t/hypr.log"
python3 -B "$s" lock
[[ $(cat "$t/hypr.log") == "switchxkblayout dell-kb7120w 0; switchxkblayout other-kbd 0" ]] || fail "lock goes to layout 0"
pass "keyboard-switch set and lock"

python3 -B "$s" bogus 2>/dev/null && fail "unknown verb fails"
python3 -B "$s" listen 2>/dev/null && fail "the follower is gone"
pass "keyboard-switch refuses unknown verbs"

# main pick with no real keyboard marked main: the first real one with more than one layout
# (not the virtual one marked main, not gpio-keys, not a one-layout keyboard)
cat >"$t/devices.json" <<'J'
{"keyboards":[
{"name":"hl-virtual-keyboard-squeekboard","layout":"us","variant":"","active_layout_index":0,"main":true},
{"name":"gpio-keys","layout":"us,gr","variant":"","active_layout_index":0,"main":false},
{"name":"single","layout":"us","variant":"","active_layout_index":0,"main":false},
{"name":"dell-kb7120w","layout":"us,gr","variant":",polytonic","active_layout_index":1,"main":false}]}
J
: >"$t/hypr.log"
python3 -B "$s" next
[[ $(cat "$t/hypr.log") == "switchxkblayout single 0; switchxkblayout dell-kb7120w 0" ]] || fail "next steps from the first real keyboard with 2+ layouts: $(cat "$t/hypr.log")"
pass "keyboard-switch main keyboard rule"

[[ ! -e $t/osk.log ]] || fail "a hardware switch touched the on-screen keyboard: $(cat "$t/osk.log")"
pass "keyboard-switch leaves the on-screen keyboard alone"
