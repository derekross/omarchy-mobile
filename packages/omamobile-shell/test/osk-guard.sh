#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-osk-guard against fake gsettings, pgrep, udevadm, omarchy-shell,
# busctl and bluetoothctl and a made-up sysfs: with no keyboard it turns the
# on-screen keyboard back on only when no screensaver runs, waits out one that
# does, and leaves an enabled keyboard alone; a real Bluetooth or USB keyboard
# turns auto-show off (one entry per uniq), the card's "show" mode and a
# password lock keep it on, and a keyboard that went away is dropped after
# its grace with the mode back to auto.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
F=$t/fakes; mkdir -p "$F" "$t/home"
fake() { printf '#!/bin/bash\n%s\n' "$2" >"$F/$1"; chmod +x "$F/$1"; }
fake gsettings 'case $1 in
  get) cat "$T/osk" ;;
  set) echo "$4" >"$T/osk"; echo set >>"$T/log" ;;
  monitor) echo false >"$T/osk"; printf "screen-keyboard-enabled: false\n" ;;
esac'
# A screensaver "runs" for as many pgrep calls as $T/screensaver says
fake pgrep 'n=$(cat "$T/screensaver" 2>/dev/null || echo 0); ((n > 0)) || exit 1; echo $((n - 1)) >"$T/screensaver"'
fake udevadm 'exec /usr/bin/sleep 30'
fake omarchy-shell 'cat "$T/locked" 2>/dev/null || echo false'
fake busctl 'echo "busctl $*" >>"$T/log"'
fake bluetoothctl 'echo "bluetoothctl $*" >>"$T/log"'
guard() {
  env T="$t" HOME="$t/home" OMAMOBILE_OSK_SYSFS="$t/sys" OMAMOBILE_OSK_UDEVDATA="$t/udev" \
    OMAMOBILE_OSK_GUARD_GRACE=0 OMAMOBILE_OSK_POLL=0 OMAMOBILE_OSK_KEYBOARD_GRACE="${KGRACE:-5}" \
    PATH="$F:/usr/bin:/bin" python3 -I bin/omamobile-osk-guard "$@" >/dev/null
}
state() { : >"$t/log"; echo "$1" >"$t/osk"; echo "$2" >"$t/screensaver"; }
st=$t/home/.local/state/omamobile/osk-hwkbd.json
mkdir -p "$t/sys/class/input" "$t/udev"
# node N BUS NAME UNIQ [caps] [virtual]: an event node with its udev data
letters="207f07fc3ff0000"  # covers Q..P, A..L, Z..M, space
node() {
  local n=$1 dev=$t/sys/devices/$1
  [[ ${6:-} == virtual ]] && dev=$t/sys/devices/virtual/input/$1
  mkdir -p "$dev/id" "$dev/capabilities"
  mkdir -p "$t/sys/class/input/event$n"
  echo "13:$n" >"$t/sys/class/input/event$n/dev"
  ln -sfn "$dev" "$t/sys/class/input/event$n/device"
  echo "$2" >"$dev/id/bustype"; echo "$3" >"$dev/name"; echo "$4" >"$dev/uniq"; echo "phys-$n" >"$dev/phys"
  echo "${5:-$letters}" >"$dev/capabilities/key"
  printf 'E:ID_INPUT=1\nE:ID_INPUT_KEYBOARD=1\n' >"$t/udev/c13:$n"
}
unplug() { rm -rf "$t/sys/class/input/event$1"; }

# ---- the safety net, no keyboard
state false 0; guard --once
[[ $(cat "$t/osk") == true ]] || fail "off with no screensaver: turned back on"
state true 0; guard --once
[[ ! -s $t/log ]] || fail "on: left alone"
state false 3; guard --once
[[ $(cat "$t/osk") == true && $(cat "$t/screensaver") == 0 ]] || fail "a running screensaver is waited out"
pass "the keyboard comes back on only once no screensaver runs"

# ---- devices that are not keyboards
node 1 0019 gpio-keys ""                         # the phone's buttons
node 2 0003 "Virtual keyboard" "" "" virtual     # squeekboard's
node 3 0005 "YubiKey OTP+FIDO" "aa:bb:cc:dd:ee:01"
node 4 0005 "BT Mouse" "aa:bb:cc:dd:ee:02" "0 0 0 0 0 0 0 0"
state true 0; guard --once
[[ $(cat "$t/osk") == true && ! -s $t/log ]] || fail "buttons, virtual keyboards, keys and mice are no keyboard"
[[ ! -e $st ]] || fail "no keyboard listed (nothing written)"
pass "gpio-keys, squeekboard's virtual keyboard, a security key and a mouse are not keyboards"

# ---- a Bluetooth keyboard with two nodes, one uniq (the Dell KB7120W)
node 15 0005 "Dell Keybd Keyboard" "00:00:5E:00:53:01"
node 16 0005 "Dell Keybd" "00:00:5e:00:53:01"
state true 0; guard --once
[[ $(cat "$t/osk") == false ]] || fail "a connected keyboard turns auto-show off"
python3 - "$st" <<'EOF' || fail "one entry per uniq, mode auto"
import json, sys
s = json.load(open(sys.argv[1]))
assert s["mode"] == "auto", s
assert [(k["name"], k["uniq"], k["bus"]) for k in s["keyboards"]] == [("Dell Keybd Keyboard", "00:00:5e:00:53:01", "bluetooth")], s
EOF
# Patch 0006's restore wrote true over it: straight back off, screensaver or not
state true 0; guard --once
[[ $(cat "$t/osk") == false ]] || fail "true written over a connected keyboard goes back off"
pass "a Bluetooth keyboard turns auto-show off, listed once by uniq; a restore to true is undone"

# ---- the card's modes
state false 0; guard --mode show
[[ $(cat "$t/osk") == true ]] && grep -q 'SetVisible b true' "$t/log" || fail "show: auto-show on and the keyboard shown"
state true 0; guard --once
[[ $(cat "$t/osk") == true ]] || fail "show mode is kept by the watcher"
state true 0; guard --mode hide
[[ $(cat "$t/osk") == false ]] && grep -q 'SetVisible b false' "$t/log" || fail "hide: auto-show off and the keyboard hidden"
pass "Show and Hide set the mode, the setting and the keyboard"

# ---- the lock: a password keeps it showable, a PIN does not
mkdir -p "$t/home/.local/state/omarchy/toggles"
echo true >"$t/locked"
state false 0; guard --once
[[ $(cat "$t/osk") == false ]] || fail "locked with a PIN: auto-show stays off"
: >"$t/home/.local/state/omarchy/toggles/credential-password"
state false 0; guard --once
[[ $(cat "$t/osk") == true ]] || fail "locked with a password: the keyboard can come up"
echo false >"$t/locked"
state true 0; guard --once
[[ $(cat "$t/osk") == false ]] || fail "unlocked: auto-show off again"
pass "while locked with a password the on-screen keyboard stays showable"

# ---- a USB keyboard; a virtual one never counts
unplug 15; unplug 16
node 20 0003 "USB Keyboard" ""
state true 0; KGRACE=0 guard --once
[[ $(cat "$t/osk") == false ]] || fail "a USB keyboard turns auto-show off"
python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); assert [k["name"] for k in s["keyboards"]]==["USB Keyboard"], s' "$st" || fail "the Dell is gone after its grace"
pass "a USB keyboard counts"

# ---- it goes away: kept for its grace, then dropped and the mode back to auto
guard --mode hide
unplug 20
state false 0; guard --once
[[ $(cat "$t/osk") == false ]] || fail "a keyboard in its grace still counts"
python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); assert s["mode"]=="hide" and len(s["keyboards"])==1' "$st" || fail "kept with its mode in the grace"
state false 0; KGRACE=0 guard --once
[[ $(cat "$t/osk") == true ]] || fail "after the grace, no keyboard: the keyboard is back on"
python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); assert s=={"keyboards":[],"mode":"auto"}, s' "$st" || fail "dropped, mode auto"
pass "a keyboard that went away is kept for its grace, then the mode goes back to auto"

# ---- disconnect
: >"$t/log"; guard --disconnect 00:00:5e:00:53:01
grep -qx 'bluetoothctl disconnect 00:00:5E:00:53:01' "$t/log" || fail "disconnect by MAC, upper case"
: >"$t/log"; guard --disconnect 'x; reboot' 2>/dev/null && fail "a bad address is refused"
[[ ! -s $t/log ]] || fail "nothing run for a bad address"
pass "Disconnect runs bluetoothctl for a valid address only"

# ---- watching: the fake monitor turns the keyboard off and reports it; the
# guard turns it back on, and exits non-zero when the monitor ends, so
# systemd restarts it
state true 0
guard && fail "the guard exits non-zero when its monitor ends"
[[ $(cat "$t/osk") == true && $(grep -c set "$t/log") == 1 ]] || fail "a change the monitor reports is checked"
pass "the watch loop restores the keyboard and exits for a restart when the monitor ends"
