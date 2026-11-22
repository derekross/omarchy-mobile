#!/bin/bash
# SPDX-License-Identifier: MIT
# bin/omamobile-shell-child: a helper ends with the process that started it and
# holds none of its descriptors past stderr; and every long-lived helper the
# plugins start goes through it (omarchy-mobile#989, #990).
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
child=$PWD/bin/omamobile-shell-child
command -v setpriv >/dev/null || { pass "shell child # SKIP no setpriv"; exit 0; }
t=$(mktemp -d)
cleanup() { for f in "$t"/pid*; do [[ -f $f ]] && { kill "$(cat "$f")" 2>/dev/null || true; }; done; rm -rf -- "$t"; true; }
trap cleanup EXIT

# 1. Descriptors: the parent holds 7 and 9 open without close-on-exec (as
# Quickshell held the GPU's render node); the helper sees 0, 1 and 2 only.
fds=$(bash -c 'exec 7</dev/null 9>"$1"; exec "$2" bash -c "ls /proc/\$\$/fd; true"' sh "$t/out" "$child" | sort -n | tr '\n' ' ')
[[ $fds == "0 1 2 " ]] || fail "the helper inherits only stdin, stdout and stderr (saw: $fds)"
pass "shell child: no descriptor of the shell's past stderr"

# 2. The parent dies (as a crashed Quickshell does): the helper goes with it.
bash -c '"$1" sleep 4242 & echo $! > "$2"; sleep 0.5' sh "$child" "$t/pid"
pid=$(cat "$t/pid")
for _ in $(seq 1 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
kill -0 "$pid" 2>/dev/null && fail "the helper outlives the process that started it"
# The same without the wrapper stays: the test can tell the difference.
bash -c 'sleep 4242 & echo $! > "$1"; sleep 0.2' sh "$t/pid2"
sleep 0.5; kill -0 "$(cat "$t/pid2")" 2>/dev/null || fail "test: a plain child should have outlived its parent"
kill "$(cat "$t/pid2")" 2>/dev/null || true
pass "shell child: the helper ends when the shell's process ends"

# 3. Arguments, stdin and the exit status pass through unchanged.
out=$(printf 'in\n' | "$child" bash -c 'read -r x; printf "%s|%s|%s" "$x" "$1" "$2"; exit 3' sh "a b" "") && rc=0 || rc=$?
[[ $out == "in|a b|" && $rc == 3 ]] || fail "arguments, stdin and status pass through (out=$out rc=$rc)"
pass "shell child: arguments, stdin, stdout and the exit status are the command's"

# 4. Every long-lived helper a plugin starts runs through it.
for want in '"omamobile-cell-watch"' '"omamobile-call-watch", "--observe"' '"omamobile-call-watch"]' \
            '"omamobile-osk-watch"' '"inotifywait", "-m", "-r"' '"tail", "-n", "+1", "-F"' \
            '"voxtype-audio-bridge"' '"omamobile-bt-agent"'; do
  bad=$(grep -rn --include=*.qml -F "$want" plugins | grep -vF 'command: ["omamobile-shell-child", ' || true)
  [[ -z $bad ]] || fail "a long-lived helper is started without omamobile-shell-child: $bad"
done
[[ $(grep -rn --include=*.qml -F 'command: ["omamobile-shell-child", ' plugins | wc -l) -ge 10 ]] \
  || fail "the ten long-lived helpers go through omamobile-shell-child"
pass "shell child: the plugins' ten long-lived helpers go through it"
