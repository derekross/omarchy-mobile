#!/bin/bash
# SPDX-License-Identifier: MIT
# Patch 0037 against the real omarchy-hyprland-session-lock-stranded
# (OMARCHY_PKG_ROOT, an extracted omarchy package), with real processes: a
# lock is stranded when the only other quickshell processes are the caller's
# own crash processes (its children, one a zombie), a zombie of another
# process, or Voxtype's overlay, and undetermined
# while another shell runs. pgrep is a fake that lists only this test's
# processes, so the shell running this test isn't counted.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
package_root=${OMARCHY_PKG_ROOT:?an extracted omarchy package}
[[ $(sed -n 's/^pkgver = //p' "$package_root/.PKGINFO") == 4.5.0-* ]] || { pass "stranded lock (0037) # SKIP not Omarchy 4.5"; exit 0; }
t=$(mktemp -d)
pids=()
cleanup() { kill "${pids[@]}" 2>/dev/null || true; wait 2>/dev/null || true; rm -rf "$t"; }
trap cleanup EXIT

mkdir -p "$t/omarchy/bin" "$t/fake" "$t/procs"
cp "$package_root/usr/bin/omarchy-hyprland-session-lock-stranded" "$t/omarchy/bin/"
(cd "$t/omarchy" && patch -p1 --fuzz=0 -s) <patches/0037-lock-recover-a-stranded-lock-after-a-shell-crash.patch \
  || fail "0037 applies to the real omarchy-hyprland-session-lock-stranded"
helper=$t/omarchy/bin/omarchy-hyprland-session-lock-stranded

printf '#!/bin/bash\n[[ ${LOCKED:-1} == 1 ]]\n' >"$t/fake/omarchy-hyprland-session-locked"
printf '#!/bin/bash\ncat "%s/listed" 2>/dev/null\n' "$t" >"$t/fake/pgrep"
# A script named qs: its process name (comm) is qs, its command line carries its arguments
printf '#!/bin/bash\nsleep 60 & wait\n' >"$t/procs/qs"
printf '#!/bin/bash\nexit 0\n' >"$t/procs/qs-dead"
chmod +x "$t/fake/"* "$t/procs/"*
run() { PATH="$t/fake:$PATH" "$helper" "$1" >/dev/null 2>&1 && echo 0 || echo $?; }
list() { printf '%s\n' "$@" >"$t/listed"; }
wait_comm() { for _ in $(seq 50); do [[ $(cat "/proc/$1/comm" 2>/dev/null) == "$2" ]] && return; sleep 0.1; done; fail "process $1 named $2"; }

# The shell after a crash (the caller, re-exec'd in place) with its crash
# processes as children: one that stays, and one that is a zombie, since
# the shell hasn't reaped it
bash -c '"$1" & echo $! >"$3"; "$2" & exec sleep 60' _ "$t/procs/qs" "$t/procs/qs-dead" "$t/child.pid" & own=$!; pids+=("$own")
for _ in $(seq 50); do [[ -s $t/child.pid ]] && break; sleep 0.1; done
child=$(cat "$t/child.pid"); pids+=("$child")
wait_comm "$child" qs
sleep 0.5
zombie=$(ps -o pid=,stat= --ppid "$own" | awk '$2 ~ /^Z/ {print $1}')
[[ -n $zombie ]] || fail "a zombie child for the test"
# A zombie whose parent is some other process, so only the zombie rule
# skips it, not the descendant rule
bash -c '"$1" & exec sleep 60' _ "$t/procs/qs-dead" & foreign=$!; pids+=("$foreign")
sleep 0.5
foreign_zombie=$(ps -o pid=,stat= --ppid "$foreign" | awk '$2 ~ /^Z/ {print $1}')
[[ -n $foreign_zombie ]] || fail "a zombie of another process for the test"
# Voxtype's overlay, and another live shell
"$t/procs/qs" -p /usr/share/voxtype/quickshell & voxtype=$!; pids+=("$voxtype")
"$t/procs/qs" -p /usr/share/omarchy/shell & other=$!; pids+=("$other")
wait_comm "$voxtype" qs; wait_comm "$other" qs

list "$own"
[[ $(run "$own") == 0 ]] || fail "alone: stranded"
[[ $(LOCKED=0 run "$own") == 1 ]] || fail "unlocked: 1"
list "$own" "$child" "$zombie"
[[ $(run "$own") == 0 ]] || fail "the shell's own crash processes are no other locker"
list "$own" "$foreign_zombie"
[[ $(run "$own") == 0 ]] || fail "a zombie of another process is no other locker"
list "$own" "$child" "$zombie" "$foreign_zombie" "$voxtype"
[[ $(run "$own") == 0 ]] || fail "Voxtype's overlay is no other locker"
list "$own" "$child" "$zombie" "$voxtype" "$other"
[[ $(run "$own") == 2 ]] || fail "another live shell leaves it undetermined"
pass "a lock stranded by a shell crash is recovered beside its crash processes and Voxtype (0037)"
