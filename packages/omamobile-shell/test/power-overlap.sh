#!/bin/bash
# SPDX-License-Identifier: MIT
# Two presses during a slow lock must leave the phone awake at its old brightness.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/run"
export XDG_RUNTIME_DIR="$t/run" T="$t" PATH="$t/bin:$PATH"
echo 512 >"$t/brightness"; echo true >"$t/dpms"
cat >"$t/bin/hyprctl" <<'STUB'
#!/bin/bash
printf '[{"dpmsStatus":%s}]\n' "$(cat "$T/dpms")"
STUB
cat >"$t/bin/omarchy-shell" <<'STUB'
#!/bin/bash
[[ $2 == isLocked ]] && echo false
exit 0
STUB
cat >"$t/bin/omarchy-hw-display" <<'STUB'
#!/bin/bash
echo fake-panel
STUB
cat >"$t/bin/brightnessctl" <<'STUB'
#!/bin/bash
if [[ $* == *get* ]]; then cat "$T/brightness"; else echo "${@: -1}" >"$T/brightness"; fi
STUB
cat >"$t/bin/omarchy-brightness-display" <<'STUB'
#!/bin/bash
case $1 in off) echo false >"$T/dpms";; on) echo true >"$T/dpms";; esac
STUB
cat >"$t/bin/omarchy-system-lock" <<'STUB'
#!/bin/bash
for fd in /proc/$$/fd/*; do
  [[ $(readlink "$fd" 2>/dev/null) == "$T/run/omamobile-keys/short.lock" ]] && touch "$T/inherited-lock"
done
sleep 1.5
STUB
cat >"$t/bin/pgrep" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$t"/bin/*
keys() { bash "$here/bin/omamobile-keys" "$@"; }
run_case() {
  local delay=$1 expected=$2 first second
  rm -rf "$t/run/omamobile-keys"
  echo 512 >"$t/brightness"; echo true >"$t/dpms"
  keys power-down; sleep 0.1; keys power-up & first=$!
  sleep "$delay"; keys power-down; sleep 0.1; keys power-up & second=$!
  wait "$first"; wait "$second"
  [[ ! -e $t/inherited-lock ]] || { echo 'not ok - helper inherited the power-key lock' >&2; exit 1; }
  [[ $(cat "$t/dpms") == "$expected" && $(cat "$t/brightness") == 512 ]] || {
    echo "not ok - delay $delay produced wrong screen state or brightness" >&2
    exit 1
  }
}
run_case 1 true
run_case 0.2 false
echo 'ok - overlapping presses wake after one second and debounce at 0.2 seconds'
