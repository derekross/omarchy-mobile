#!/bin/bash
# SPDX-License-Identifier: MIT
# tmpfiles/omamobile-run.conf: the staged file, and, where systemd-tmpfiles
# can run on a made-up root (--root), that it takes a 1777 /run to 0755 and
# leaves what is in it alone. Nothing on this machine's /run is touched.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

./install "$t/stage" >/dev/null
f=$t/stage/usr/lib/tmpfiles.d/omamobile-run.conf
[[ -f $f ]] || fail "the /run rule is staged in usr/lib/tmpfiles.d, where pacman's tmpfiles hook looks"
[[ $(grep -vE '^[[:space:]]*(#|$)' "$f") == "z /run 0755 root root - -" ]] || fail "one rule: z /run 0755 root root"
pass "the /run rule is staged: z /run 0755 root root"

if command -v systemd-tmpfiles >/dev/null && [[ $(id -u) == 0 ]]; then
  mkdir -p "$t/root/run/keep"; chmod 1777 "$t/root/run"; chmod 0700 "$t/root/run/keep"
  systemd-tmpfiles --root="$t/root" --create "$f" || fail "systemd-tmpfiles accepts the rule"
  [[ $(stat -c %a "$t/root/run") == 755 ]] || fail "a 1777 /run becomes 0755 (got $(stat -c %a "$t/root/run"))"
  [[ $(stat -c %a "$t/root/run/keep") == 700 ]] || fail "what is in /run keeps its mode"
  pass "systemd-tmpfiles takes a 1777 /run to 0755 and leaves its contents alone"
else
  pass "systemd-tmpfiles takes a 1777 /run to 0755 # SKIP needs root and systemd-tmpfiles"
fi
