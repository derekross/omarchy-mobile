#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/lock.sh against a scratch HOME, a fake /sys/class/input and /run/udev/data.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
export HOME=$tmp/home XDG_CONFIG_HOME=$tmp/home/.config OMARCHY_PATH=$tmp/omarchy
export OMAMOBILE_LOCK_SYSFS=$tmp/sys OMAMOBILE_LOCK_UDEVDATA=$tmp/udev
mkdir -p "$HOME/.config/omarchy" "$OMARCHY_PATH/config/omarchy" "$tmp/sys/class/input" "$tmp/udev"
shell=$HOME/.config/omarchy/shell.json prefs=$XDG_CONFIG_HOME/omamobile/lock.json
echo '{"version":1,"bar":{"id":"omamobile.bar"},"idle":{"screensaver":0,"lock":60}}' > "$shell"
echo '{"version":1,"bar":{"id":"default"},"idle":{"screensaver":150,"lock":300}}' > "$OMARCHY_PATH/config/omarchy/shell.json"
run() { bash "$src/backends/lock.sh" "$@" || true; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }
idle() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["idle"]["lock"], d["idle"]["screensaver"], d["bar"]["id"])' "$shell"; }
# an input device: N, bus, keyboard (1/0), where it lives under /sys/devices
dev() {
  local d=$tmp/sys/devices/$4/input$1
  mkdir -p "$d/id" "$tmp/sys/class/input/event$1"
  echo "$2" > "$d/id/bustype"
  echo "13:$((64 + $1))" > "$tmp/sys/class/input/event$1/dev"
  ln -sfn "$d" "$tmp/sys/class/input/event$1/device"
  { echo "E:ID_INPUT=1"; [[ $3 == 1 ]] && echo "E:ID_INPUT_KEYBOARD=1" || echo "E:ID_INPUT_KEY=1"; } > "$tmp/udev/c13:$((64 + $1))"
}
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
eq "$(run nonsense)" '{"error":"usage: get|set|apply"}'
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

# the watcher: apply once at start, then once per settled burst of input events (fake udevadm, stub backend)
mkdir -p "$tmp/bin"
printf '#!/bin/sh\necho "monitor will print the received events for:"\necho "UDEV  [1] add /devices/a (input)"\necho "UDEV  [1] add /devices/a/event9 (input)"\nsleep 2\necho "UDEV  [3] remove /devices/a (input)"\n' > "$tmp/bin/udevadm"
printf '#!/bin/sh\necho "$1" >> "%s/calls"\n' "$tmp" > "$tmp/stub.sh"
chmod +x "$tmp/bin/udevadm"
PATH="$tmp/bin:$PATH" OMAMOBILE_LOCK_BACKEND=$tmp/stub.sh timeout 20 bash "$src/libexec/omamobile-lock-keyboard"
eq "$(tr '\n' ' ' < "$tmp/calls")" 'apply apply apply '
echo "lock backend: ok"
