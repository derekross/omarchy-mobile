#!/bin/bash
# SPDX-License-Identifier: MIT
# lib/power-profile against a scratch cpufreq tree shaped like the Pixel 9a's
# three clusters, and its watch loop against stub busctl and gdbus. Run from
# the package directory (test/all does).
set -euo pipefail
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
tool=$PWD/lib/power-profile
export OMAMOBILE_CPUFREQ=$t/cpufreq OMAMOBILE_POWER_PROFILE_CONF=$t/power-profile.conf OMAMOBILE_POWER_PROFILE_OFF=$t/off

policy() { # NAME TOP STEPS...
  local d=$t/cpufreq/$1; mkdir -p "$d"
  echo "$2" > "$d/cpuinfo_max_freq"; echo "$2" > "$d/scaling_max_freq"
  echo "$3" > "$d/cpuinfo_min_freq"; echo "$3" > "$d/scaling_min_freq"
  shift 2; echo "$* " > "$d/scaling_available_frequencies"
}
policy policy0 1950000 324000 610000 820000 955000 1098000 1197000 1328000 1425000 1548000 1696000 1849000 1950000
policy policy4 2367000 357000 578000 648000 787000 910000 1065000 1221000 1328000 1418000 1549000 1795000 1945000 2130000 2245000 2367000
policy policy7 2687000 700000 1164000 1396000 1557000 1745000 1885000 1999000 2147000 2294000 2363000 2499000 2687000
ceilings() { cat "$t"/cpufreq/policy{0,4,7}/scaling_max_freq | tr '\n' ' '; }
floors() { cat "$t"/cpufreq/policy{0,4,7}/scaling_min_freq | tr '\n' ' '; }
bottoms="324000 357000 700000 "

"$tool" apply power-saver >/dev/null
[[ $(ceilings) == "1098000 1418000 1557000 " ]] || fail "power-saver caps each cluster at the step under 60 %: $(ceilings)"
"$tool" apply balanced >/dev/null
[[ $(ceilings) == "1950000 2367000 2687000 " ]] || fail "balanced gives the top back: $(ceilings)"
[[ $(floors) == "$bottoms" ]] || fail "power-saver and balanced leave the floor at the bottom: $(floors)"
"$tool" apply power-saver >/dev/null; "$tool" apply performance >/dev/null
[[ $(ceilings) == "1950000 2367000 2687000 " ]] || fail "performance gives the top back: $(ceilings)"
[[ $(floors) == "955000 1065000 1164000 " ]] || fail "performance raises each floor to the step under 50 %: $(floors)"
"$tool" apply power-saver >/dev/null
[[ $(ceilings) == "1098000 1418000 1557000 " && $(floors) == "$bottoms" ]] || fail "performance to power-saver: $(floors)/ $(ceilings)"
"$tool" apply performance >/dev/null; "$tool" restore >/dev/null
[[ $(ceilings) == "1950000 2367000 2687000 " && $(floors) == "$bottoms" ]] || fail "restore gives the full range back: $(floors)/ $(ceilings)"
pass "power-saver caps every cluster a step under 60 %, performance raises the floor a step under 50 %, balanced and restore give the full range back"

printf 'POWER_SAVER_PERCENT=80\nPERFORMANCE_PERCENT=70\n' > "$t/power-profile.conf"
"$tool" apply power-saver >/dev/null
[[ $(ceilings) == "1548000 1795000 2147000 " ]] || fail "POWER_SAVER_PERCENT=80: $(ceilings)"
"$tool" apply performance >/dev/null
[[ $(floors) == "1328000 1549000 1745000 " ]] || fail "PERFORMANCE_PERCENT=70: $(floors)"
for bad in 5 101 abc 60x; do
  printf 'POWER_SAVER_PERCENT=%s\nPERFORMANCE_PERCENT=%s\n' "$bad" "$bad" > "$t/power-profile.conf"
  "$tool" apply power-saver >/dev/null
  [[ $(ceilings) == "1098000 1418000 1557000 " ]] || fail "POWER_SAVER_PERCENT=$bad falls back to 60: $(ceilings)"
  "$tool" apply performance >/dev/null
  [[ $(floors) == "955000 1065000 1164000 " ]] || fail "PERFORMANCE_PERCENT=$bad falls back to 50: $(floors)"
done
rm -f "$t/power-profile.conf"
"$tool" restore >/dev/null
pass "the configured percentages are used, and an out-of-range or malformed one falls back to the default"

rm "$t/cpufreq/policy4/scaling_available_frequencies"
"$tool" apply power-saver >/dev/null
[[ $(cat "$t/cpufreq/policy4/scaling_max_freq") == $((2367000 * 60 / 100)) ]] || fail "no step list: the plain 60 %"
"$tool" restore >/dev/null
pass "a cluster with no step list gets the plain percentage"

touch "$t/off"
echo 1098000 > "$t/cpufreq/policy0/scaling_max_freq"
for c in "apply power-saver" "apply balanced" "restore"; do
  "$tool" $c >/dev/null || fail "off: $c succeeds"
done
[[ $(cat "$t/cpufreq/policy0/scaling_max_freq") == 1098000 ]] || fail "off: a cap someone else set stays, restore included"
rm "$t/off"; "$tool" restore >/dev/null
pass "a device that ships power-profile-off: nothing is written, restore included"

"$tool" apply 'power saver' >/dev/null 2>&1 && fail "a malformed profile is refused"
"$tool" bogus >/dev/null 2>&1 && fail "an unknown command is refused"
pass "malformed profiles and unknown commands are refused"

# watch: the stub daemon reports power-saver, then balanced after one change
# signal, then leaves the bus
mkdir -p "$t/bin"
cat > "$t/bin/busctl" <<'EOF'
#!/bin/bash
n=$(cat "$STUB/count" 2>/dev/null || echo 0); echo $((n + 1)) > "$STUB/count"
(( n == 0 )) && echo 's "power-saver"' || echo 's "balanced"'
EOF
cat > "$t/bin/gdbus" <<'EOF'
#!/bin/bash
[[ "$*" == "monitor --system --dest org.freedesktop.UPower.PowerProfiles --object-path /org/freedesktop/UPower/PowerProfiles" ]] || exit 9
until [[ -s $STUB/count ]]; do sleep 0.05; done
cat "$STUB/cpufreq/policy7/scaling_max_freq" > "$STUB/seen"
echo "/org/freedesktop/UPower/PowerProfiles: org.freedesktop.DBus.Properties.PropertiesChanged ('org.freedesktop.UPower.PowerProfiles', {'PerformanceDegraded': <''>}, @as [])"
echo "/org/freedesktop/UPower/PowerProfiles: org.freedesktop.DBus.Properties.PropertiesChanged ('org.freedesktop.UPower.PowerProfiles', {'ActiveProfile': <'balanced'>}, @as [])"
EOF
chmod +x "$t/bin/busctl" "$t/bin/gdbus"
rc=0; STUB=$t PATH=$t/bin:$PATH timeout 10 "$tool" watch > "$t/out" 2>&1 || rc=$?
[[ $rc == 1 ]] || fail "watch exits 1 when the daemon leaves the bus (rc $rc)"
[[ $(cat "$t/seen") == 1557000 ]] || fail "watch applied the starting profile before listening"
[[ $(cat "$t/count") == 2 ]] || fail "watch re-read the profile only on ActiveProfile: $(cat "$t/count") reads"
grep -qx 'power-profile: power-saver' "$t/out" && grep -qx 'power-profile: balanced' "$t/out" || fail "watch logs each profile"
[[ $(ceilings) == "1950000 2367000 2687000 " && $(floors) == "$bottoms" ]] || fail "watch leaves the full range when the daemon goes"
pass "watch applies the profile at start and on each change, and gives the top back when the daemon goes"
