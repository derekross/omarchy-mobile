#!/bin/bash
# SPDX-License-Identifier: MIT
# Two presses during a slow lock must leave the phone awake at its old brightness.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/run"
export XDG_RUNTIME_DIR="$t/run" T="$t"
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
touch "$T/locking"
sleep "${LOCK_DELAY:-1.5}"
STUB
cat >"$t/bin/pgrep" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$t"/bin/*
# Only these host tools are reachable; unstubbed desktop commands must fail.
for tool in bash cat readlink touch sleep mkdir rm seq grep jq flock date stat timeout; do
  ln -s "$(command -v "$tool")" "$t/bin/$tool"
done
export PATH="$t/bin"
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

# A hung lock helper must not queue later presses indefinitely. The second
# press is dropped after five seconds without changing debounce or display.
rm -rf "$t/run/omamobile-keys"
rm -f "$t/locking"
echo 512 >"$t/brightness"; echo true >"$t/dpms"
export LOCK_DELAY=8
keys power-down; sleep 0.1; keys power-up & first=$!
for _ in {1..100}; do
  [[ -e $t/locking ]] && break
  sleep 0.05
done
[[ -e $t/locking ]] || { echo 'not ok - slow action never started' >&2; exit 1; }
last=$(cat "$t/run/omamobile-keys/last-press")
keys power-down; sleep 0.1
ms() { local t; t=$(date +%s%N); echo $((t / 1000000)); }   # not %3N: uutils' date gets it wrong (bin/omamobile-keys)
start=$(ms)
rc=0
timeout 7 bash "$here/bin/omamobile-keys" power-up 2>"$t/timeout-log" || rc=$?
elapsed=$(( $(ms) - start ))
if [[ $rc != 0 || $elapsed -lt 4500 || $elapsed -ge 7000 ]] ||
   ! grep -q 'short-press lock wait failed; dropping press' "$t/timeout-log" ||
   [[ $(cat "$t/run/omamobile-keys/last-press") != "$last" ||
      $(cat "$t/dpms") != true || $(cat "$t/brightness") != 0 ]]; then
  wait "$first"
  echo 'not ok - blocked press did not time out without acting' >&2
  exit 1
fi
wait "$first"
unset LOCK_DELAY
# Once the slow action releases the lock, a fresh press still wakes normally.
keys power-down; sleep 0.1; keys power-up
[[ $(cat "$t/dpms") == true && $(cat "$t/brightness") == 512 ]] || {
  echo 'not ok - power key failed to recover after lock release' >&2; exit 1;
}
echo 'ok - blocked press is dropped after five seconds; next press works after release'
