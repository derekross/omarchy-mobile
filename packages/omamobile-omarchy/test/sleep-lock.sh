#!/bin/bash
# SPDX-License-Identifier: MIT
# Patch 0021 against the real omarchy-system-sleep-lock (OMARCHY_PKG_ROOT, an
# extracted omarchy package), run against fakes: the display goes off once
# the session is secure on a panel with a writable bl_power, never without
# one, never while the lock isn't secure, and a hung display call can't hold
# the suspend past the lock's budget.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
src=${OMARCHY_PKG_ROOT:?an extracted omarchy package}/usr/share/omarchy
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

mkdir -p "$t/omarchy/bin" "$t/fake" "$t/backlight/panel"
cp "$src/bin/omarchy-system-sleep-lock" "$t/omarchy/bin/"
(cd "$t/omarchy" && patch -p1 --fuzz=0 -s) <patches/0021-sleep-turn-the-display-off-before-suspend.patch \
  || fail "0021 applies to the real omarchy-system-sleep-lock"
lock=$t/omarchy/bin/omarchy-system-sleep-lock

# The shell reports a secure lock unless LOCK_STATE says otherwise; the
# display call is recorded, or hangs with DISPLAY_HANG set.
cat >"$t/fake/omarchy-shell" <<'SH'
#!/bin/bash
case "$*" in
  "lock lock") echo ok ;;
  "lock status") [[ ${LOCK_STATE:-secure} == secure ]] && echo '{"secure":true}' || echo '{"requested":true}' ;;
esac
SH
cat >"$t/fake/omarchy-brightness-display" <<'SH'
#!/bin/bash
[[ -n ${DISPLAY_HANG:-} ]] && sleep 30
echo "$*" >>"$CALLS"
SH
printf '#!/bin/bash\necho panel\n' >"$t/fake/omarchy-hw-display"
printf '#!/bin/bash\necho "t 5000000"\n' >"$t/fake/busctl"
printf '#!/bin/bash\nexit 0\n' >"$t/fake/omarchy-hyprland-monitor-clamshell"
printf '#!/bin/bash\nexit 0\n' >"$t/fake/omarchy-notification-send"
chmod +x "$t"/fake/*

run() {
  : >"$t/calls"
  PATH=$t/fake:$PATH CALLS=$t/calls OMARCHY_BACKLIGHT_PATH=$t/backlight "$lock" "$@" 2>/dev/null
}

touch "$t/backlight/panel/bl_power"
run 2000 || fail "a secure lock exits 0"
[[ $(<"$t/calls") == off ]] || fail "the display goes off once the lock is secure (got '$(<"$t/calls")')"
pass "a panel with a writable bl_power: the display goes off after a secure lock"

rm "$t/backlight/panel/bl_power"
run 2000 || fail "a secure lock exits 0 without bl_power"
[[ ! -s $t/calls ]] || fail "no bl_power, no display call (got '$(<"$t/calls")')"
pass "no writable bl_power (a laptop): the display is left alone"

touch "$t/backlight/panel/bl_power"
rc=0; LOCK_STATE=locking run 600 || rc=$?
((rc != 0)) || fail "a lock that never secures reports it"
[[ ! -s $t/calls ]] || fail "the display stays on while the lock isn't secure"
pass "a lock that never secures: the display is not turned off behind it"

start=$(date +%s%3N)
DISPLAY_HANG=1 run 1500 || fail "a hung display call still exits 0"
((($(date +%s%3N) - start) < 2500)) || fail "a hung display call held the suspend past the budget"
pass "a hung display call is cut off within the lock's budget"
