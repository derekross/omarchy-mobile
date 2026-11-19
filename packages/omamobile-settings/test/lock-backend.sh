#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/lock.sh against a scratch HOME, a fake /sys/class/input and /run/udev/data.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
export HOME=$tmp/home XDG_CONFIG_HOME=$tmp/home/.config OMARCHY_PATH=$tmp/omarchy
export OMAMOBILE_LOCK_SYSFS=$tmp/sys OMAMOBILE_LOCK_UDEVDATA=$tmp/udev OMAMOBILE_LOCK_WATCHER=1
# stand-ins for omarchy-shell and systemctl: never touch the shell or units of the machine running the tests
mkdir -p "$tmp/stubs"; export STUB_LOG=$tmp/stubs/log STUB_FAIL=$tmp/stubs/fail; : > "$STUB_LOG"
for c in omarchy-shell systemctl; do
  printf '#!/bin/bash\necho "%s $*" >> "$STUB_LOG"\n[[ -e $STUB_FAIL.%s ]] && exit 1\nexit 0\n' "$c" "$c" > "$tmp/stubs/$c"
  chmod +x "$tmp/stubs/$c"
done
export PATH=$tmp/stubs:$PATH
mkdir -p "$HOME/.config/omarchy" "$OMARCHY_PATH/config/omarchy" "$tmp/sys/class/input" "$tmp/udev"
shell=$HOME/.config/omarchy/shell.json prefs=$XDG_CONFIG_HOME/omamobile/lock.json
echo '{"version":1,"bar":{"id":"omamobile.bar"},"idle":{"screensaver":0,"lock":60}}' > "$shell"
echo '{"version":1,"bar":{"id":"default"},"idle":{"screensaver":150,"lock":300}}' > "$OMARCHY_PATH/config/omarchy/shell.json"
run() { bash "$src/backends/lock.sh" "$@" || true; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }
idle() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["idle"]["lock"], d["idle"]["screensaver"], d["bar"]["id"])' "$shell"; }
full='ffffffffffffffff fffffffffffffffe'  # keys 1..127: a whole keyboard
# an input device: N, bus, keyboard (1/0), where it lives under /sys/devices, [name], [key capabilities]
dev() {
  local d=$tmp/sys/devices/$4/input$1
  mkdir -p "$d/id" "$d/capabilities" "$tmp/sys/class/input/event$1"
  echo "$2" > "$d/id/bustype"
  printf '%s\n' "${5-Some Keyboard}" > "$d/name"
  echo "${6-$full}" > "$d/capabilities/key"
  echo "13:$((64 + $1))" > "$tmp/sys/class/input/event$1/dev"
  ln -sfn "$d" "$tmp/sys/class/input/event$1/device"
  { echo "E:ID_INPUT=1"; [[ $3 == 1 ]] && echo "E:ID_INPUT_KEYBOARD=1" || echo "E:ID_INPUT_KEY=1"; } > "$tmp/udev/c13:$((64 + $1))"
}
pj() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$prefs" "$1"; }
gone() { rm -rf "$tmp/sys/class/input/event$1" "$tmp/udev/c13:$((64 + $1))"; }

# the phone's own keys (gpio-keys on the host bus 0019, a pmic power key) and a uinput device that says USB
dev 0 0019 1 platform/gpio-keys
dev 1 0000 1 platform/pwrkey
dev 2 0003 1 virtual/input
# AVRCP from Bluetooth headphones: keys, but not a keyboard
dev 3 0005 0 virtual/input

# nothing chosen yet: get reports Omarchy's value and apply writes nothing
eq "$(run get)" '{"lock":60,"keyboardAwake":false,"keyboard":false,"effective":60}'
eq "$(run apply)" '{"applied":null}'
[[ ! -e $prefs ]] || { echo "FAIL: apply wrote prefs" >&2; exit 1; }

eq "$(run set lock 120)" '{"lock":120,"keyboardAwake":false,"keyboard":false,"effective":120}'
eq "$(idle)" '120 0 omamobile.bar'
eq "$(run set lock 0)" '{"error":"bad value"}'  # no Never on the page (derekross, #866)
eq "$(idle)" '120 0 omamobile.bar'
eq "$(run set lock 45)" '{"error":"bad value"}'
eq "$(run set lock x)" '{"error":"bad value"}'
eq "$(run set keyboard maybe)" '{"error":"bad value"}'
eq "$(run set night on)" '{"error":"unknown key"}'
eq "$(run nonsense)" '{"error":"usage: get|set|apply|restore"}'
eq "$(run set lock 30)" '{"lock":30,"keyboardAwake":false,"keyboard":false,"effective":30}'
eq "$(run set keyboard on)" '{"lock":30,"keyboardAwake":true,"keyboard":false,"effective":30}'

# a BLE keyboard through uhid (bus 0005 under /devices/virtual/misc/uhid): lock after 1800 s
dev 4 0005 1 virtual/misc/uhid/0005:046D:B35B.0001
eq "$(run apply)" '{"lock":30,"keyboardAwake":true,"keyboard":true,"effective":1800}'
eq "$(idle)" '1800 0 omamobile.bar'
# picking a time while it is connected keeps 1800 in force, and keeps the choice
eq "$(run set lock 300)" '{"lock":300,"keyboardAwake":true,"keyboard":true,"effective":1800}'
gone 4
eq "$(run apply)" '{"lock":300,"keyboardAwake":true,"keyboard":false,"effective":300}'
eq "$(idle)" '300 0 omamobile.bar'
# a real USB keyboard
dev 5 0003 1 platform/soc/usb1/1-1/1-1:1.0/0003:04D9:A0F8.0002
eq "$(run apply)" '{"lock":300,"keyboardAwake":true,"keyboard":true,"effective":1800}'
# the toggle off: the keyboard no longer matters
eq "$(run set keyboard off)" '{"lock":300,"keyboardAwake":false,"keyboard":true,"effective":300}'
gone 5

# changed in Omarchy's own settings: adopted, not overwritten
sed -i 's/"lock": 300/"lock": 600/' "$shell"
eq "$(run get)" '{"lock":600,"keyboardAwake":false,"keyboard":false,"effective":600}'
eq "$(run apply)" '{"lock":600,"keyboardAwake":false,"keyboard":false,"effective":600}'
eq "$(idle)" '600 0 omamobile.bar'

# no user shell.json: start from Omarchy's defaults (it never merges), touching only idle.lock
rm "$shell"
eq "$(run set lock 60)" '{"lock":60,"keyboardAwake":false,"keyboard":false,"effective":60}'
eq "$(idle)" '60 150 default'

# restore (the watcher's ExecStopPost) writes the choice although a keyboard is connected
echo '{"version":1,"bar":{"id":"omamobile.bar"},"idle":{"screensaver":0,"lock":60}}' > "$shell"
eq "$(run set lock 120)" '{"lock":120,"keyboardAwake":false,"keyboard":false,"effective":120}'
eq "$(run set keyboard on)" '{"lock":120,"keyboardAwake":true,"keyboard":false,"effective":120}'
dev 6 0005 1 virtual/misc/uhid/0005:046D:B35B.0003
eq "$(run apply)" '{"lock":120,"keyboardAwake":true,"keyboard":true,"effective":1800}'
eq "$(pj override)" 'True'
eq "$(run restore)" '{"lock":120,"keyboardAwake":true,"keyboard":true,"effective":120}'
eq "$(idle)" '120 0 omamobile.bar'
# no watcher running: the keyboard's 1800 is never written
eq "$(OMAMOBILE_LOCK_WATCHER=0 run apply)" '{"lock":120,"keyboardAwake":true,"keyboard":true,"effective":120}'
eq "$(run apply)" '{"lock":120,"keyboardAwake":true,"keyboard":true,"effective":1800}'

# a run that died after lock.json (override) but before shell.json, or after both: our 1800 is never adopted
gone 6
echo '{"lock":120,"keyboardAwake":true,"applied":1800,"override":true}' > "$prefs"
eq "$(run apply)" '{"lock":120,"keyboardAwake":true,"keyboard":false,"effective":120}'
eq "$(idle)" '120 0 omamobile.bar'
echo '{"lock":120,"keyboardAwake":true,"applied":1800,"override":true}' > "$prefs"
sed -i 's/"lock": 120/"lock": 1800/' "$shell"
eq "$(run apply)" '{"lock":120,"keyboardAwake":true,"keyboard":false,"effective":120}'
# lock.json cannot be saved: shell.json is not touched (lock.json is written first)
dev 6 0005 1 virtual/misc/uhid/0005:046D:B35B.0003
chmod a-w "$XDG_CONFIG_HOME/omamobile"
eq "$(run apply)" '{"error":"cannot save the setting"}'
chmod u+w "$XDG_CONFIG_HOME/omamobile"
eq "$(idle)" '120 0 omamobile.bar'
gone 6
# no temp files left behind
eq "$(find "$HOME" -name '.*.json.*' | wc -l)" 0

# concurrent runs: one flock, unique temp files; every run answers and both files stay valid
for i in $(seq 1 15); do
  run apply > "$tmp/c$i.a" & run set lock 60 > "$tmp/c$i.b" & run set lock 30 > "$tmp/c$i.c" &
done; wait
! grep -h error "$tmp"/c*.? || { echo "FAIL: concurrent run failed" >&2; exit 1; }
python3 -I -c 'import json,sys; [json.load(open(p)) for p in sys.argv[1:]]' "$shell" "$prefs"

# the user's shell.json does not parse or has another version: an error, and nothing is written
cp "$shell" "$tmp/shell.good"
echo '{"version":1,"bar":{"id":"omamobile.bar"},}' > "$shell"; cp "$shell" "$tmp/shell.bad"
eq "$(run set lock 300)" '{"error":"shell.json is not readable"}'
cmp -s "$shell" "$tmp/shell.bad" || { echo "FAIL: broken shell.json was replaced" >&2; exit 1; }
echo '{"version":2,"idle":{"lock":60}}' > "$shell"
eq "$(run apply)" '{"error":"shell.json is not readable"}'
eq "$(head -c 13 "$shell")" '{"version":2,'
# an empty one is treated as missing: Omarchy's defaults
: > "$shell"
eq "$(run set lock 180)" '{"lock":180,"keyboardAwake":true,"keyboard":false,"effective":180}'
eq "$(idle)" '180 150 default'
# a symlinked shell.json stays a symlink, other keys and non-ASCII text are kept
mv "$shell" "$tmp/real-shell.json"; ln -s "$tmp/real-shell.json" "$shell"
python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["clock"]="ώρα"; json.dump(d,open(p,"w"),ensure_ascii=False)' "$shell"
eq "$(run set lock 30)" '{"lock":30,"keyboardAwake":true,"keyboard":false,"effective":30}'
[[ -L $shell ]] || { echo "FAIL: symlink replaced" >&2; exit 1; }
grep -q 'ώρα' "$shell"

# not a keyboard: no name, a security token, a barcode scanner, too few keys (a receiver's partial key map)
dev 7 0003 1 platform/usb/7 ''
dev 8 0003 1 platform/usb/8 'Yubico YubiKey OTP+FIDO+CCID'
dev 9 0005 1 virtual/misc/uhid/9 'Wireless Barcode Scanner'
dev 10 0003 1 platform/usb/10 'Logitech USB Receiver' 'fffffffe'
eq "$(run get)" '{"lock":30,"keyboardAwake":true,"keyboard":false,"effective":30}'
dev 11 0003 1 platform/usb/11 'Logitech K380'
eq "$(run get)" '{"lock":30,"keyboardAwake":true,"keyboard":true,"effective":30}'
gone 7; gone 8; gone 9; gone 10; gone 11

# the watcher: apply once at start, then once per settled burst of input events (fake udevadm, stub backend);
# the real header line "UDEV - the event which udev sends..." is not an event. When udevadm ends it exits 1.
mkdir -p "$tmp/bin"
printf '#!/bin/sh\necho "monitor will print the received events for:"\necho "UDEV - the event which udev sends out after rule processing"\necho "UDEV  [1] add /devices/a (input)"\necho "UDEV  [1] add /devices/a/event9 (input)"\nsleep 2\necho "UDEV  [3] remove /devices/a (input)"\n' > "$tmp/bin/udevadm"
printf '#!/bin/sh\necho "$1" >> "%s/calls"\n' "$tmp" > "$tmp/stub.sh"
chmod +x "$tmp/bin/udevadm"
rc=0; PATH="$tmp/bin:$PATH" OMAMOBILE_LOCK_BACKEND=$tmp/stub.sh timeout 20 bash "$src/libexec/omamobile-lock-keyboard" 2>/dev/null || rc=$?
eq "$(tr '\n' ' ' < "$tmp/calls")" 'apply apply apply '
eq "$rc" 1
# a failing apply (a broken shell.json) does not end it: logged once, tried again on the next event
printf '#!/bin/sh\necho "$1" >> "%s/calls2"\necho "{\\"error\\":\\"shell.json is not readable\\"}"\nexit 2\n' "$tmp" > "$tmp/stub.sh"
rc=0; PATH="$tmp/bin:$PATH" OMAMOBILE_LOCK_BACKEND=$tmp/stub.sh timeout 20 bash "$src/libexec/omamobile-lock-keyboard" 2>"$tmp/werr" || rc=$?
eq "$(tr '\n' ' ' < "$tmp/calls2")" 'apply apply apply '
eq "$(grep -c 'apply failed' "$tmp/werr")" 1
eq "$rc" 1  # only because the fake udevadm ended
unit=$src/systemd/user/omamobile-lock-keyboard.service
grep -q '^ExecStopPost=.*lock.sh restore$' "$unit"
grep -qx 'WantedBy=graphical-session.target' "$unit"
! grep -q 'graphical-session.target.wants' "$src/install" || { echo "FAIL: unit enabled for everyone" >&2; exit 1; }
grep -q '^depends=.*coreutils.*systemd' "$src/PKGBUILD"

# reloadConfig after a write, nothing when unchanged; Stay awake / idle on-off are never called
echo '{"version":1,"bar":{"id":"omamobile.bar"},"idle":{"screensaver":0,"lock":60}}' > "$shell"; rm -f "$prefs"
: > "$STUB_LOG"
eq "$(run set lock 120)" '{"lock":120,"keyboardAwake":false,"keyboard":false,"effective":120}'
eq "$(tr '\n' ',' < "$STUB_LOG")" "omarchy-shell shell reloadConfig,"
: > "$STUB_LOG"; before=$(stat -c %Y.%i "$prefs"); sleep 1.1
run set lock 120 >/dev/null; run apply >/dev/null
eq "$(cat "$STUB_LOG")" ""
eq "$(stat -c %Y.%i "$prefs")" "$before"  # lock.json not rewritten when nothing changed
# a failed reload: the value is saved, the JSON carries the error, exit 3
touch "$STUB_FAIL.omarchy-shell"
rc=0; out=$(bash "$src/backends/lock.sh" set lock 300) || rc=$?

eq "$(python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); print(d["lock"], d["error"])' "$out")" "300 saved, but the shell did not reload its settings"
eq "$rc" 3
eq "$(idle)" '300 0 omamobile.bar'
rm -f "$STUB_FAIL.omarchy-shell"
# the toggle enables/starts and stops/disables the watcher unit
: > "$STUB_LOG"
eq "$(run set keyboard on)" '{"lock":300,"keyboardAwake":true,"keyboard":false,"effective":300}'
# the reload that failed above is still pending: done now, before the watcher starts
eq "$(tr '\n' ',' < "$STUB_LOG")" "omarchy-shell shell reloadConfig,systemctl --user enable --now omamobile-lock-keyboard.service,"
: > "$STUB_LOG"
eq "$(run set keyboard off)" '{"lock":300,"keyboardAwake":false,"keyboard":false,"effective":300}'
eq "$(tr '\n' ',' < "$STUB_LOG")" "systemctl --user disable --now --no-block omamobile-lock-keyboard.service,"
err() { python3 -I -c 'import json,sys; d=json.loads(sys.argv[1]); print(d["keyboardAwake"], d["effective"], d.get("error"))' "$1"; }
# a) enable fails: the toggle goes back to off (saved), with a keyboard in the 1800 is undone too
dev 12 0005 1 virtual/misc/uhid/12
touch "$STUB_FAIL.systemctl"
rc=0; out=$(bash "$src/backends/lock.sh" set keyboard on) || rc=$?
eq "$rc" 3
eq "$(err "$out")" "False 300 could not start the keyboard watcher"
eq "$(pj keyboardAwake)" 'False'
eq "$(pj override)" 'False'
eq "$(idle)" '300 0 omamobile.bar'
rm -f "$STUB_FAIL.systemctl"
# a) a failed reload does not skip enable/disable; both errors are reported together
eq "$(run set keyboard on)" '{"lock":300,"keyboardAwake":true,"keyboard":true,"effective":1800}'
touch "$STUB_FAIL.omarchy-shell"; : > "$STUB_LOG"
rc=0; out=$(bash "$src/backends/lock.sh" set keyboard off) || rc=$?
eq "$rc" 3
eq "$(err "$out")" "False 300 saved, but the shell did not reload its settings"
grep -q 'systemctl --user disable --now --no-block' "$STUB_LOG"
touch "$STUB_FAIL.systemctl"
rc=0; out=$(bash "$src/backends/lock.sh" set keyboard on) || rc=$?
eq "$rc" 3
eq "$(err "$out")" "False 300 saved, but the shell did not reload its settings; could not start the keyboard watcher"
eq "$(pj keyboardAwake)" 'False'
rm -f "$STUB_FAIL.systemctl"
# b) the reload is still pending: the same set again writes nothing but reloads, and keeps the error until it works
eq "$(pj reloadPending)" 'True'
: > "$STUB_LOG"
rc=0; out=$(bash "$src/backends/lock.sh" set lock 300) || rc=$?
eq "$rc" 3
eq "$(err "$out")" "False 300 saved, but the shell did not reload its settings"
rm -f "$STUB_FAIL.omarchy-shell"; : > "$STUB_LOG"
eq "$(run set lock 300)" '{"lock":300,"keyboardAwake":false,"keyboard":true,"effective":300}'
eq "$(tr '\n' ',' < "$STUB_LOG")" "omarchy-shell shell reloadConfig,"
eq "$(pj reloadPending)" 'False'
: > "$STUB_LOG"; run set lock 300 >/dev/null
eq "$(cat "$STUB_LOG")" ""
gone 12
# c) restore died after lock.json, before shell.json: override is still set, so the 1800 is not adopted
echo '{"lock":120,"keyboardAwake":true,"applied":120,"override":true,"reloadPending":true}' > "$prefs"
sed -i 's/"lock": 300/"lock": 1800/' "$shell"
eq "$(run apply)" '{"lock":120,"keyboardAwake":true,"keyboard":false,"effective":120}'
eq "$(idle)" '120 0 omamobile.bar'
eq "$(pj override)" 'False'
# c) the real step 1 of a restore keeps override true: kill shell.json's write by making it unwritable
dev 13 0005 1 virtual/misc/uhid/13
eq "$(run apply)" '{"lock":120,"keyboardAwake":true,"keyboard":true,"effective":1800}'
chmod a-w "$HOME/.config/omarchy"
eq "$(run restore)" '{"error":"cannot write shell.json"}'
chmod u+w "$HOME/.config/omarchy"
eq "$(pj override) $(pj applied)" 'True 120'
gone 13
eq "$(run apply)" '{"lock":120,"keyboardAwake":true,"keyboard":false,"effective":120}'
eq "$(idle)" '120 0 omamobile.bar'
# d) off with a reload that hangs: bounded (5 s reload, --no-block stop), well under the runner's 20 s
printf '#!/bin/bash\necho "omarchy-shell $*" >> "$STUB_LOG"\nsleep 30\n' > "$tmp/stubs/omarchy-shell"
run set keyboard on >/dev/null
dev 14 0005 1 virtual/misc/uhid/14; run apply >/dev/null
t0=$(date +%s); run set keyboard off >/dev/null; t1=$(date +%s)
(( t1 - t0 <= 8 )) || { echo "FAIL: set keyboard off took $((t1 - t0)) s" >&2; exit 1; }
printf '#!/bin/bash\necho "omarchy-shell $*" >> "$STUB_LOG"\n[[ -e $STUB_FAIL.omarchy-shell ]] && exit 1\nexit 0\n' > "$tmp/stubs/omarchy-shell"
gone 14
# e) get puts the unit in line with lock.json (an upgrade left keyboardAwake on, unit never enabled)
echo '{"lock":120,"keyboardAwake":true,"applied":120,"override":false,"reloadPending":false}' > "$prefs"
: > "$STUB_LOG"; eq "$(OMAMOBILE_LOCK_UNIT_ENABLED=0 run get)" '{"lock":120,"keyboardAwake":true,"keyboard":false,"effective":120}'
eq "$(cat "$STUB_LOG")" "systemctl --user enable --now omamobile-lock-keyboard.service"
: > "$STUB_LOG"; OMAMOBILE_LOCK_UNIT_ENABLED=1 run get >/dev/null; eq "$(cat "$STUB_LOG")" ""
: > "$STUB_LOG"; run get >/dev/null  # no hook: asks systemctl (the stub says enabled), nothing to change
eq "$(cat "$STUB_LOG")" "systemctl --user is-enabled --quiet omamobile-lock-keyboard.service"
echo '{"lock":120,"keyboardAwake":false,"applied":120,"override":false,"reloadPending":false}' > "$prefs"
: > "$STUB_LOG"; OMAMOBILE_LOCK_UNIT_ENABLED=1 run get >/dev/null
eq "$(cat "$STUB_LOG")" "systemctl --user disable --now --no-block omamobile-lock-keyboard.service"
: > "$STUB_LOG"; OMAMOBILE_LOCK_UNIT_ENABLED=0 run get >/dev/null; eq "$(cat "$STUB_LOG")" ""
# systemctl fails: reported in the JSON, the choice is kept
touch "$STUB_FAIL.systemctl"
eq "$(OMAMOBILE_LOCK_UNIT_ENABLED=1 run get)" '{"lock":120,"keyboardAwake":false,"keyboard":false,"effective":120,"error":"could not stop the keyboard watcher"}'
echo '{"lock":120,"keyboardAwake":true,"applied":120,"override":false,"reloadPending":false}' > "$prefs"
eq "$(OMAMOBILE_LOCK_UNIT_ENABLED=0 run get)" '{"lock":120,"keyboardAwake":true,"keyboard":false,"effective":120,"error":"could not start the keyboard watcher"}'
eq "$(pj keyboardAwake)" 'True'
rm -f "$STUB_FAIL.systemctl"
# no lock.json, or a broken one: the unit is never touched
rm -f "$prefs"; : > "$STUB_LOG"; OMAMOBILE_LOCK_UNIT_ENABLED=1 run get >/dev/null; eq "$(cat "$STUB_LOG")" ""
echo '{broken' > "$prefs"; OMAMOBILE_LOCK_UNIT_ENABLED=1 run get >/dev/null; eq "$(cat "$STUB_LOG")" ""
! grep -q 'idle' "$STUB_LOG" || { echo "FAIL: idle service touched" >&2; exit 1; }
echo "lock backend: ok"
