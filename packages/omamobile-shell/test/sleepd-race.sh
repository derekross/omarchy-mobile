#!/bin/bash
# SPDX-License-Identifier: MIT
# omamobile-sleepd-race against a fake /sys and /run/user: it refuses only a
# sleep omamobile-sleepd marked, only with the panel lit, only before the
# sleep, and only for a fresh mark, which it removes.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
hook=$here/systemd/system-sleep/omamobile-sleepd-race
c=$t/sys/class/drm/card1-DSI-1 mark=$t/run/1000/omamobile-sleepd.request
mkdir -p "$t/sys/power" "$c" "$t/run/1000"
echo 5 >"$t/sys/power/wakeup_count"; echo connected >"$c/status"; echo enabled >"$c/enabled"; echo On >"$c/dpms"
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
run() { OMAMOBILE_SLEEP_SYSFS=$t/sys OMAMOBILE_SLEEP_RUN=$t/run OMAMOBILE_SLEEP_RACE_DRY=1 bash "$hook" "$@"; }

[[ -z $(run pre suspend) ]] || fail "a sleep nobody marked goes ahead with the screen lit"
touch "$mark"
[[ $(run pre suspend) == *refusing* ]] || fail "a marked sleep with the screen lit is refused"
[[ ! -e $mark ]] || fail "the mark is used once"
touch "$mark"; echo Off >"$c/dpms"
[[ -z $(run pre suspend) ]] || fail "a marked sleep with the panel in DPMS off goes ahead"
touch "$mark"; echo On >"$c/dpms"; echo disabled >"$c/enabled"
[[ -z $(run pre suspend) ]] || fail "a marked sleep with the output disabled goes ahead"
echo enabled >"$c/enabled"; touch "$mark"
[[ -z $(run post suspend) && -e $mark ]] || fail "after the sleep nothing happens"
touch -d '-60 sec' "$mark"
[[ -z $(run pre suspend) ]] || fail "a stale mark counts for nothing"
echo 7 >"$t/sys/power/wakeup_count"
run pre suspend >/dev/null
[[ $(<"$t/sys/power/wakeup_count") == 7 ]] || fail "the wakeup count is written back"
echo "ok - sleepd-race: refuses only omamobile-sleepd's sleep with the screen lit, once, and counts wakeups from the hook on"
