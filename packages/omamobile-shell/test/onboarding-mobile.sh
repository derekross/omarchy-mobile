#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-onboarding's SIM line against a fake omamobile-mobile-network:
# the carrier and "set up automatically" with a SIM, a pointer to Setup >
# Mobile network when no APN was found, and silence without the modem stack.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
F=$t/fakes; mkdir -p "$F" "$t/home"
fake() { printf '#!/bin/bash\n%s\n' "$2" >"$F/$1"; chmod +x "$F/$1"; }
fake git 'echo set'
fake unix_chkpwd 'exit 1'
fake gum 'case $1 in input) echo ;; confirm) exit 1 ;; esac'
fake omamobile-set-pin 'case $1 in --type) echo PIN ;; esac'
fake timeout 'shift; "$@"'
fake omamobile-mobile-network '[[ -e $T/status ]] && cat "$T/status"; true'
ob() {
  env -u XDG_STATE_HOME T="$t" HOME="$t/home" USER=alice OMARCHY_PATH="$t/none" OMAMOBILE_FP_RUNNER="$t/none" \
    PATH="$F:/usr/bin:/bin" bash bin/omamobile-onboarding --inner >"$t/out" 2>&1
}
status() {
  printf '{"installed": true, "running": true, "carrier": "%s", "sim": {"state": "%s"}, "apn": {"source": "%s"}}\n' "$1" "$2" "$3" >"$t/status"
}

status Example ready carrier-database; ob
grep -c "^Mobile network: Example. Mobile data is set up automatically from your SIM; there's nothing to type.$" "$t/out" >/dev/null ||
  { cat "$t/out"; fail "a SIM: the carrier, and nothing to type"; }
status "" ready override; ob
grep -c "^Your SIM is ready. Mobile data is set up automatically" "$t/out" >/dev/null || fail "not registered yet: still automatic"
status Example ready none; ob
grep -c "Mobile data needs your carrier's APN: Setup > Mobile network." "$t/out" >/dev/null || fail "no APN found: points at the page"
status "" absent ""; ob
grep -c "No SIM card" "$t/out" >/dev/null || fail "no SIM: says so"
rm -f "$t/status"; ob
grep -cE "Mobile network:|Your SIM|No SIM|Mobile data" "$t/out" >/dev/null && fail "no modem stack: nothing about the SIM"
printf '{"installed": false}\n' >"$t/status"; ob
grep -cE "Mobile network:|Your SIM|No SIM|Mobile data" "$t/out" >/dev/null && fail "not installed: nothing about the SIM"
pass "setup: the SIM's carrier and automatic mobile data, nothing to type"
