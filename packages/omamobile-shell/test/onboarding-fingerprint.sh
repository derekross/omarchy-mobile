#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-onboarding's fingerprint offer against fakes (gum, fprintd's
# listing through omamobile-fp-enroll, the shell, notifications): offered
# after the PIN when the sensor is ready and nothing is enrolled, once;
# never before a PIN, never with a finger enrolled, and a not-ready sensor
# gets a "later" line in setup and silence at login (then the next login
# offers it).
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
F=$t/fakes; mkdir -p "$F" "$t/home"
fake() { printf '#!/bin/bash\n%s\n' "$2" >"$F/$1"; chmod +x "$F/$1"; }
: >"$t/runner"; chmod +x "$t/runner"
fake git 'echo set'
# an empty password is accepted (no PIN) until $T/pin exists
fake unix_chkpwd '[[ ! -e $T/pin ]]'
fake gum 'case $1 in input) echo ;; confirm) echo "confirm $2" >>"$T/log"; [[ -e $T/yes ]] ;; esac'
fake omamobile-set-pin 'case $1 in --type) echo PIN ;; --inner) touch "$T/pin" ;; esac'
fake omamobile-fp-enroll '[[ -e $T/listing ]] && cat "$T/listing"; true'
fake omarchy-shell 'echo "shell $*" >>"$T/log"'
fake omarchy-notification-send 'echo "notify $*" >>"$T/log"'
fake systemctl '[[ $* == "is-failed --quiet omamobile-fp.service" && -e $T/failed ]]'
fake timeout 'shift; "$@"'
ob() {
  env -u XDG_STATE_HOME T="$t" HOME="$t/home" USER=alice OMARCHY_PATH="$t/none" OMAMOBILE_FP_RUNNER="$t/runner" OMAMOBILE_FP_IMAGE="$t/image" \
    PATH="$F:/usr/bin:/bin" bash bin/omamobile-onboarding "$@" >"$t/out" 2>&1
}
reset() { rm -rf "$t/pin" "$t/yes" "$t/listing" "$t/failed" "$t/image" "$t/log"; rm -rf "$t/home/.local"; : >"$t/log"; }
ready() { printf '{"event": "fingers", "fingers": [%s], "stages": 12, "device": "Omarchy Mobile UDFPS"}\n' "${1:-}" >"$t/listing"; }

# Setup: the PIN is set, then the fingerprint is offered and taken
reset; ready; touch "$t/yes"
ob --inner || { cat "$t/out"; fail "setup runs"; }
grep -c '^confirm Add a fingerprint' "$t/log" >/dev/null || fail "the fingerprint is offered after the PIN"
grep -c 'shell shell summon omamobile.fingerprint {"page":"enroll"}' "$t/log" >/dev/null || fail "yes opens the enrollment screen"
[[ -e $t/home/.local/state/omamobile/fingerprint-offered ]] || fail "the offer is remembered"
ob --inner; [[ $(grep -c '^confirm' "$t/log") == 1 ]] || fail "offered once only"
pass "setup: after the PIN, a ready sensor with no finger gets one offer"

reset; ready
ob --inner
grep -c 'Skipped' "$t/out" >/dev/null || fail "skip says where to add one later"
grep -c 'summon' "$t/log" >/dev/null && fail "skip opens nothing"
reset; ready '"right-index-finger"'
ob --inner; grep -c 'confirm' "$t/log" >/dev/null && fail "a finger already enrolled: no offer"
reset
ob --inner; grep -c 'confirm' "$t/log" >/dev/null && fail "a sensor not ready: no offer"
grep -c 'ready once your phone' "$t/out" >/dev/null || fail "not provisioned yet: setup says it comes after the firmware"
reset; mkdir "$t/image"; touch "$t/failed"
ob --inner; grep -c 'unavailable on this boot' "$t/out" >/dev/null || fail "a refused or failed unit: setup says unavailable, not 'after the firmware'"
grep -c 'ready once your phone' "$t/out" >/dev/null && fail "a failed unit isn't blamed on missing firmware"
reset; mkdir "$t/image"
ob --inner; grep -c 'still starting' "$t/out" >/dev/null || fail "provisioned but not up yet: offered at the next login"
reset
[[ ! -e $t/home/.local/state/omamobile/fingerprint-offered ]] || fail "not ready: the offer waits for a later login"
reset; ready; rm -f "$t/runner"
ob --inner; grep -c 'confirm' "$t/log" >/dev/null && fail "no fingerprint stack: no offer"
: >"$t/runner"; chmod +x "$t/runner"
pass "setup: no offer when skipped, already enrolled, not ready or not installed"

# Login: no PIN yet means the setup nudge, not the fingerprint
reset; ready
ob --nudge; grep -c 'notify.*Finish setting up' "$t/log" >/dev/null || fail "no PIN: the setup nudge"
grep -c 'Add a fingerprint' "$t/log" >/dev/null && fail "no fingerprint offer before a PIN"
# PIN set, sensor ready, nothing enrolled: one fingerprint notification
reset; ready; touch "$t/pin"
ob --nudge; grep -c '^notify Add a fingerprint.*--exec omamobile-onboarding --fingerprint' "$t/log" >/dev/null || fail "login offers the fingerprint"
: >"$t/log"; ob --nudge; grep -c 'notify' "$t/log" >/dev/null && fail "the login offer comes once"
# not ready at login: silent, and the next login offers it
reset; touch "$t/pin"
ob --nudge; grep -c 'notify' "$t/log" >/dev/null && fail "not ready at login: no notification"
ready; ob --nudge; grep -c '^notify Add a fingerprint.*--exec omamobile-onboarding --fingerprint' "$t/log" >/dev/null || fail "the next login offers it once ready"
pass "login: one fingerprint notification once the PIN exists and the sensor is ready"
