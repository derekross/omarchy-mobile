#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/lock.sh against a scratch HOME, a fake /sys/class/input and /run/udev/data.
set -euo pipefail
export OMAMOBILE_LOCK_NO_REARM=1  # never touch the idle service of the machine running the tests
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
export HOME=$tmp/home XDG_CONFIG_HOME=$tmp/home/.config OMARCHY_PATH=$tmp/omarchy
export OMAMOBILE_LOCK_SYSFS=$tmp/sys OMAMOBILE_LOCK_UDEVDATA=$tmp/udev OMAMOBILE_LOCK_WATCHER=1
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
eq "$(run set lock 0)" '{"lock":0,"keyboardAwake":false,"keyboard":false,"effective":0}'
eq "$(idle)" '0 0 omamobile.bar'
eq "$(run set lock 45)" '{"error":"bad value"}'
eq "$(run set lock x)" '{"error":"bad value"}'
eq "$(run set keyboard maybe)" '{"error":"bad value"}'
eq "$(run set night on)" '{"error":"unknown key"}'
eq "$(run nonsense)" '{"error":"usage: get|set|apply|restore"}'
eq "$(run set lock 30)" '{"lock":30,"keyboardAwake":false,"keyboard":false,"effective":30}'
eq "$(run set keyboard on)" '{"lock":30,"keyboardAwake":true,"keyboard":false,"effective":30}'

# a BLE keyboard through uhid (bus 0005 under /devices/virtual/misc/uhid): never lock
dev 4 0005 1 virtual/misc/uhid/0005:046D:B35B.0001
eq "$(run apply)" '{"lock":30,"keyboardAwake":true,"keyboard":true,"effective":0}'
eq "$(idle)" '0 0 omamobile.bar'
# picking a time while it is connected keeps "never" in force, and keeps the choice
eq "$(run set lock 300)" '{"lock":300,"keyboardAwake":true,"keyboard":true,"effective":0}'
gone 4
eq "$(run apply)" '{"lock":300,"keyboardAwake":true,"keyboard":false,"effective":300}'
eq "$(idle)" '300 0 omamobile.bar'
# a real USB keyboard
dev 5 0003 1 platform/soc/usb1/1-1/1-1:1.0/0003:04D9:A0F8.0002
eq "$(run apply)" '{"lock":300,"keyboardAwake":true,"keyboard":true,"effective":0}'
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
eq "$(run apply)" '{"lock":120,"keyboardAwake":true,"keyboard":true,"effective":0}'
eq "$(pj override)" 'True'
eq "$(run restore)" '{"lock":120,"keyboardAwake":true,"keyboard":true,"effective":120}'
eq "$(idle)" '120 0 omamobile.bar'
# no watcher running: the keyboard's 0 is never written
eq "$(OMAMOBILE_LOCK_WATCHER=0 run apply)" '{"lock":120,"keyboardAwake":true,"keyboard":true,"effective":120}'
eq "$(run apply)" '{"lock":120,"keyboardAwake":true,"keyboard":true,"effective":0}'

# a run that died after lock.json (override) but before shell.json, or after both: our 0 is never adopted
gone 6
echo '{"lock":120,"keyboardAwake":true,"applied":0,"override":true}' > "$prefs"
eq "$(run apply)" '{"lock":120,"keyboardAwake":true,"keyboard":false,"effective":120}'
eq "$(idle)" '120 0 omamobile.bar'
echo '{"lock":120,"keyboardAwake":true,"applied":0,"override":true}' > "$prefs"
sed -i 's/"lock": 120/"lock": 0/' "$shell"
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
# a failed apply also ends it non-zero, so systemd restarts it
printf '#!/bin/sh\nexit 2\n' > "$tmp/stub.sh"
rc=0; PATH="$tmp/bin:$PATH" OMAMOBILE_LOCK_BACKEND=$tmp/stub.sh timeout 20 bash "$src/libexec/omamobile-lock-keyboard" 2>/dev/null || rc=$?
eq "$rc" 1
grep -qx 'Restart=always' "$src/systemd/user/omamobile-lock-keyboard.service"
grep -q '^ExecStopPost=.*lock.sh restore$' "$src/systemd/user/omamobile-lock-keyboard.service"
# The idle re-arm: with idle on and stay-awake off a set switches idle off and on; with stay-awake on,
# or for get, it is left alone. A fake omarchy-shell logs its calls.
mkdir -p "$tmp/rearm"; cat > "$tmp/rearm/omarchy-shell" <<'SH'
#!/bin/bash
echo "$*" >> "$REARM_LOG"
[[ $* == "idle status" ]] && cat "$REARM_STATUS"
exit 0
SH
chmod +x "$tmp/rearm/omarchy-shell"
export REARM_LOG=$tmp/rearm/log REARM_STATUS=$tmp/rearm/status
echo '{"enabled":true,"stayAwake":false}' > "$REARM_STATUS"; : > "$REARM_LOG"
PATH="$tmp/rearm:$PATH" OMAMOBILE_LOCK_NO_REARM= bash "$src/backends/lock.sh" set lock 60 >/dev/null
eq "$(tr '\n' ',' < "$REARM_LOG")" "idle status,idle disable,idle enable,idle status,"
# the same value again: shell.json unchanged, no re-arm (it would restart the countdown)
: > "$REARM_LOG"
PATH="$tmp/rearm:$PATH" OMAMOBILE_LOCK_NO_REARM= bash "$src/backends/lock.sh" set lock 60 >/dev/null
eq "$(cat "$REARM_LOG")" ""
# idle switched off by the user: left alone
echo '{"enabled":false,"stayAwake":false}' > "$REARM_STATUS"; : > "$REARM_LOG"
PATH="$tmp/rearm:$PATH" OMAMOBILE_LOCK_NO_REARM= bash "$src/backends/lock.sh" set lock 90 >/dev/null || true
PATH="$tmp/rearm:$PATH" OMAMOBILE_LOCK_NO_REARM= bash "$src/backends/lock.sh" set lock 180 >/dev/null
eq "$(tr '\n' ',' < "$REARM_LOG")" "idle status,"
# enable that never takes: retried, then a non-zero exit instead of silence
cat > "$tmp/rearm/omarchy-shell" <<'SH'
#!/bin/bash
echo "$*" >> "$REARM_LOG"
[[ $* == "idle status" ]] && { [[ -e $REARM_LOG.disabled ]] && echo '{"enabled":false,"stayAwake":false}' || cat "$REARM_STATUS"; }
[[ $* == "idle disable" ]] && touch "$REARM_LOG.disabled"
exit 0
SH
echo '{"enabled":true,"stayAwake":false}' > "$REARM_STATUS"; : > "$REARM_LOG"; rm -f "$REARM_LOG.disabled"
rc=0; PATH="$tmp/rearm:$PATH" OMAMOBILE_LOCK_NO_REARM= bash "$src/backends/lock.sh" set lock 300 >/dev/null 2>&1 || rc=$?
eq "$rc" 3
eq "$(grep -c 'idle enable' "$REARM_LOG")" 3
echo '{"enabled":true,"stayAwake":true}' > "$REARM_STATUS"; : > "$REARM_LOG"
PATH="$tmp/rearm:$PATH" OMAMOBILE_LOCK_NO_REARM= bash "$src/backends/lock.sh" set lock 120 >/dev/null
eq "$(tr '\n' ',' < "$REARM_LOG")" "idle status,"
rm -f "$REARM_LOG.disabled"
: > "$REARM_LOG"
PATH="$tmp/rearm:$PATH" OMAMOBILE_LOCK_NO_REARM= bash "$src/backends/lock.sh" get >/dev/null
eq "$(cat "$REARM_LOG")" ""
echo "lock backend: ok"
