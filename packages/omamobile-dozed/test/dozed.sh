#!/bin/bash
# omamobile-dozed against a fake sysfs, /proc and stubbed commands (no real
# systemctl, no phone): the charger test, journal handling, the watcher's
# stages on a fake clock, the never-freeze rules, the per-app policy and the
# superwhisper thaw wrapper.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
root=$(mktemp -d); trap 'rm -rf "$root"' EXIT
fail=0; n=0; ok() { n=$((n+1)); echo "ok - $1"; }; bad() { n=$((n+1)); echo "FAIL - $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
export OMAMOBILE_DOZE_SYSFS=$root/sys

# ---- charging()
ps=$root/sys/class/power_supply
mkdir -p "$ps/usb" "$ps/battery"
echo USB >"$ps/usb/type"; echo Battery >"$ps/battery/type"; echo 1 >"$ps/battery/online"
eval "$(sed -n '/^charging() {/,/^}/p' "$here/bin/omamobile-dozed")"
sys=$root/sys
echo 0 >"$ps/usb/online"; check "unplugged" '! charging'
echo 1 >"$ps/usb/online"; check "plugged" 'charging'
echo 0 >"$ps/usb/online"

# ---- stubs
bin=$root/bin; mkdir -p "$bin" "$root/sys/class/backlight/bl" "$root/sys/power/suspend_stats"
echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 0 >"$root/sys/power/suspend_stats/success"
st=$root/st; mkdir -p "$st"; : >"$st/calls"; : >"$st/frozen"
echo 0 >"$root/clock"
cat >"$bin/systemctl" <<EOF
#!/bin/bash
st=$st; here=$here
a=(); for x in "\$@"; do case \$x in --no-ask-password|--user|--system|--plain|--no-legend|--all|--state=*) ;; *) a+=("\$x");; esac; done
echo "\${a[*]}" >>\$st/calls; echo "\$*" >>\$st/raw
[[ -e \$st/show-fail && \${a[0]} == show ]] && exit 1
case \${a[0]} in
  list-units) printf '%s loaded active running x\n' app-foo.scope app-bar.service app-quickshell.scope app-recorder.scope app-alarmclock-x.scope app-Hyprland-rest-1a2b3c4d.scope app-Hyprland-unr-5e6f7a8b.scope 'app-Hyprland-gtk\\x2dlaunch-9a9a9a9a.scope'; [[ " \${a[*]} " == *' superwhisper.service '* ]] && echo 'superwhisper.service loaded active running x' ;;
  show) case \${a[2]} in
          Slice) echo app.slice ;;
          FreezerState) grep -qxF "\${a[3]}" \$st/frozen && echo frozen || echo running ;;
          ControlGroup) echo "/user.slice/app.slice/\${a[3]}" ;;
        esac ;;
  freeze) echo "\${a[1]}" >>\$st/frozen ;;
  thaw) [[ -e \$st/thaw-fail ]] && exit 1; grep -vxF "\${a[1]}" \$st/frozen >\$st/f.tmp; mv \$st/f.tmp \$st/frozen ;;
esac
EOF
cat >"$bin/sleep" <<EOF
#!/bin/bash
# fake clock: each poll moves time; a "resume" file makes a 1000 s suspend
c=\$(<$root/clock); add=\$1
if [[ -e $st/resume-at && \$c -ge \$(<$st/resume-at) ]]; then
  add=\$((add + 1000)); rm $st/resume-at
  echo \$((\$(<$root/sys/power/suspend_stats/success) + 1)) >$root/sys/power/suspend_stats/success
fi
echo \$((c + add)) >$root/clock
[[ -e $st/screen-on-at && \$((c + add)) -ge \$(<$st/screen-on-at) ]] && echo 0 >$root/sys/class/backlight/bl/bl_power
[[ -z \${OMAMOBILE_TEST_HOOK:-} ]] || "\$OMAMOBILE_TEST_HOOK"
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' >"$bin/omarchy-toggle-enabled"
printf '#!/bin/bash\necho bl\n' >"$bin/omarchy-hw-display"
printf '#!/bin/bash\necho %s\n' "'{\"secure\":true}'" >"$bin/omarchy-shell"
printf '#!/bin/bash\nexit 0\n' >"$bin/ss"
printf '#!/bin/bash\necho %s\n' "'{\"data\":[[]]}'" >"$bin/busctl"
printf '#!/bin/bash\nexit 0\n' >"$bin/pactl"
printf '#!/bin/bash\nexit 0\n' >"$bin/systemd-inhibit"
printf '#!/bin/bash\nexit 1\n' >"$bin/hyprctl"
chmod +x "$bin"/*
export PATH=$bin:$PATH HOME=$root/home
export OMAMOBILE_DOZE_STATE=$root/run OMAMOBILE_DOZE_CLOCK=$root/clock
export OMAMOBILE_DOZE_POLL=60 OMAMOBILE_DOZE_PROC=$root/proc
mkdir -p "$root/home/.config/omamobile"
printf 'app-recorder*' >"$root/home/.config/omamobile/doze-allow"   # no final newline
dozed() { "$here/bin/omamobile-dozed" "$@" 2>&1; }
# readable (empty) cgroups for the stub units: never_proc fails closed without them
mkcg() { local u; for u in app-foo.scope app-bar.service app-quickshell.scope app-recorder.scope app-alarmclock-x.scope superwhisper.service app-Hyprland-rest-1a2b3c4d.scope app-Hyprland-unr-5e6f7a8b.scope 'app-Hyprland-gtk\x2dlaunch-9a9a9a9a.scope'; do
  mkdir -p "$root/sys/fs/cgroup/user.slice/app.slice/$u"; touch "$root/sys/fs/cgroup/user.slice/app.slice/$u/cgroup.procs"; done; }
mkcg

# ---- full run: LIGHT 300, DEEP 1800, maint at 5400 for 60 s, screen on at 6000
echo 6000 >"$st/screen-on-at"
out=$(OMAMOBILE_DOZED_STOP_AT=6200 dozed)
check "LIGHT, DEEP, maint, back, exit in order" \
  '[[ $(grep -oE "LIGHT_DOZE|DEEP_DOZE|maintenance window|back to DEEP_DOZE|exit \(the screen is on\)" <<<"$out" | tr "\n" ,) == "LIGHT_DOZE,DEEP_DOZE,maintenance window,back to DEEP_DOZE,exit (the screen is on)," ]]'
check "froze app-foo and app-bar" 'grep -q "froze app-foo.scope" <<<"$out" && grep -q "froze app-bar.service" <<<"$out"'
check "allowlist line without newline honoured" '! grep -q "froze app-recorder" <<<"$out"'
check "built-in allowlist skips quickshell and alarm clock" '! grep -qE "froze app-(quickshell|alarmclock)" <<<"$out"'
check "all thawed after exit" '[[ ! -s $st/frozen ]]'
check "superwhisper.service is not frozen by default" '! grep -q "froze superwhisper" <<<"$out"'
check "journal empty after exit" '[[ ! -s $root/run/applied ]]'
check "state file says ACTIVE after exit" '[[ $(<$root/run/state) == ACTIVE ]]'
check "every systemctl call has --no-ask-password" '[[ -s $st/raw ]] && ! grep -v -- --no-ask-password $st/raw'

# ---- failed thaw keeps the journal line
: >"$st/calls"; echo app-foo.scope >"$st/frozen"; echo "thaw app-foo.scope" >"$root/run/applied"; touch "$st/thaw-fail"
dozed restore >/dev/null
check "failed thaw keeps the undo line" 'grep -qx "thaw app-foo.scope" $root/run/applied'
rm "$st/thaw-fail"; dozed restore >/dev/null
check "retry thaws and empties the journal" '[[ ! -s $root/run/applied && ! -s $st/frozen ]]'
echo "thaw app-gone.scope" >"$root/run/applied"; touch "$st/thaw-fail"; dozed restore >/dev/null; rm "$st/thaw-fail"
check "thaw of a unit that is no longer frozen counts as done" '[[ ! -s $root/run/applied ]]'

# ---- start sweep: frozen unit with no journal line
echo 0 >"$root/clock"; echo 0 >"$root/sys/class/backlight/bl/bl_power"; rm -f "$st/screen-on-at"
echo app-bar.service >"$st/frozen"; : >"$root/run/applied"
OMAMOBILE_DOZED_STOP_AT=1 dozed >/dev/null
check "start thaws a frozen app-* with no journal" '[[ ! -s $st/frozen ]]'

# ---- resume: a 1000 s suspend at t=120 must not trigger LIGHT on wake
echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 120 >"$st/resume-at"
out=$(OMAMOBILE_DOZED_STOP_AT=1300 dozed)
check "resume moves the timers (no LIGHT right at wake)" '! grep -q LIGHT_DOZE <<<"$out" && grep -q "resume seen" <<<"$out"'

# ---- cheap polling: no ss/busctl/pactl before the LIGHT deadline
for c in ss busctl pactl; do printf '#!/bin/bash\necho %s >>%s\n' "$c" "$st/expensive" >"$bin/$c"; done
chmod +x "$bin"/*; : >"$st/expensive"; echo 0 >"$root/clock"
OMAMOBILE_DOZE_LIGHT_AFTER=10000 OMAMOBILE_DOZED_STOP_AT=600 dozed >/dev/null
check "no expensive checks long before LIGHT" '[[ ! -s $st/expensive ]]'

# ---- refuses without XDG_RUNTIME_DIR
env -u OMAMOBILE_DOZE_STATE -u XDG_RUNTIME_DIR "$here/bin/omamobile-dozed" status >/dev/null 2>&1
check "refuses without XDG_RUNTIME_DIR" '[[ $? == 1 ]]'


# ---- plugged LIGHT (freeze, 60 min thaw window, never DEEP)
rm -rf "$root/run"; : >"$st/frozen"; : >"$st/calls"
echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 8000 >"$st/screen-on-at"
echo 1 >"$ps/usb/online"
out=$(OMAMOBILE_DOZED_STOP_AT=8200 dozed)
check "plugged: LIGHT, light window, back, staying, exit; never DEEP" \
  '[[ $(grep -oE "LIGHT_DOZE|DEEP_DOZE|maintenance window 60 s \(light\)|back to LIGHT_DOZE|staying in LIGHT \(on charger\)|exit \(the screen is on\)" <<<"$out" | tr "\n" ,) == "LIGHT_DOZE,staying in LIGHT (on charger),maintenance window 60 s (light),back to LIGHT_DOZE,maintenance window 60 s (light),back to LIGHT_DOZE,exit (the screen is on)," ]]'
check "plugged: froze apps" 'grep -q "froze app-foo.scope" <<<"$out"'
check "no root unit is ever started" '! grep -q "^start" $st/calls'
check "plugged: all thawed after exit" '[[ ! -s $st/frozen ]]'
echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; rm -f "$st/screen-on-at"; rm -rf "$root/run"
out=$(OMAMOBILE_DOZE_PLUGGED=0 OMAMOBILE_DOZE_LIGHT_AFTER=60 OMAMOBILE_DOZED_STOP_AT=600 dozed)
check "OMAMOBILE_DOZE_PLUGGED=0 refuses on the charger" 'grep -q "not dozing: on charger" <<<"$out" && ! grep -q LIGHT_DOZE <<<"$out"'
echo 0 >"$ps/usb/online"

# ---- never-freeze by process name (Stevia lives in app-Hyprland-sh-*.scope)
mkdir -p "$root/sys/fs/cgroup/user.slice/app.slice/app-foo.scope" "$root/proc/42"
echo 42 >"$root/sys/fs/cgroup/user.slice/app.slice/app-foo.scope/cgroup.procs"; echo phosh-osk-stevi >"$root/proc/42/comm"
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 700 >"$st/screen-on-at"
out=$(OMAMOBILE_DOZED_STOP_AT=900 dozed)
check "a unit running phosh-osk-stevia is never frozen" '! grep -q "froze app-foo.scope" <<<"$out" && grep -q "froze app-bar.service" <<<"$out"'
rm -rf "$root/sys/fs/cgroup" "$root/proc/42"; mkcg

# ---- screen: Hyprland dpms decides over bl_power
printf '#!/bin/bash\necho %s\n' "'[{\"dpmsStatus\":false}]'" >"$bin/hyprctl"
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 0 >"$root/sys/class/backlight/bl/bl_power"; rm -f "$st/screen-on-at"
out=$(OMAMOBILE_DOZED_STOP_AT=400 dozed)
check "dpms off with bl_power 0 still dozes" 'grep -q LIGHT_DOZE <<<"$out"'
printf '#!/bin/bash\necho %s\n' "'[{\"dpmsStatus\":true}]'" >"$bin/hyprctl"
echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"
out=$(OMAMOBILE_DOZED_STOP_AT=400 dozed)
check "dpms on with bl_power 1 does not doze" '! grep -q LIGHT_DOZE <<<"$out"'
printf '#!/bin/bash\nexit 1\n' >"$bin/hyprctl"

# ---- plug-in during DEEP goes back to LIGHT
rm -rf "$root/run"; : >"$st/frozen"; : >"$st/calls"
echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 3000 >"$st/screen-on-at"
cat >"$bin/plugat" <<EOF2
#!/bin/bash
[[ \$(<$root/clock) -ge 2400 ]] && echo 1 >$ps/usb/online
EOF2
chmod +x "$bin/plugat"
out=$(OMAMOBILE_DOZED_STOP_AT=3200 OMAMOBILE_TEST_HOOK=plugat dozed)
echo 0 >"$ps/usb/online"
check "plug-in during DEEP: back to LIGHT (on charger)" 'grep -q "DEEP_DOZE" <<<"$out" && grep -q "back to LIGHT_DOZE (on charger)" <<<"$out"'
# ---- never_proc fails closed when the cgroup can't be read
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 700 >"$st/screen-on-at"
rm -rf "$root/sys/fs/cgroup/user.slice/app.slice/app-foo.scope"
mkdir -p "$root/sys/fs/cgroup/user.slice/app.slice/app-bar.service/sub" "$root/proc/43"
echo 43 >"$root/sys/fs/cgroup/user.slice/app.slice/app-bar.service/sub/cgroup.procs"; : >"$root/sys/fs/cgroup/user.slice/app.slice/app-bar.service/cgroup.procs"
echo voxtype >"$root/proc/43/comm"
out=$(OMAMOBILE_DOZED_STOP_AT=900 dozed)
check "unreadable cgroup counts as protected; child cgroup comm seen" '! grep -q "froze app-foo.scope" <<<"$out" && ! grep -q "froze app-bar.service" <<<"$out"'
rm -rf "$root/sys/fs/cgroup" "$root/proc/43"; mkcg
# ---- pactl failing refuses (audio state unreadable)
printf '#!/bin/bash\nexit 1\n' >"$bin/pactl"
rm -rf "$root/run"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; rm -f "$st/screen-on-at"
out=$(OMAMOBILE_DOZED_STOP_AT=600 dozed)
check "pactl failing refuses Doze" '! grep -q LIGHT_DOZE <<<"$out" && grep -q "audio state unreadable" <<<"$out"'
printf '#!/bin/bash\nexit 0\n' >"$bin/pactl"

# ---- superwhisper.service is frozen when listed in OMAMOBILE_DOZE_EXTRA_UNITS
export OMAMOBILE_DOZE_EXTRA_UNITS=superwhisper.service
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 700 >"$st/screen-on-at"
out=$(OMAMOBILE_DOZED_STOP_AT=900 dozed)
check "superwhisper.service is frozen in LIGHT and thawed on exit" 'grep -q "froze superwhisper.service" <<<"$out" && [[ ! -s $st/frozen ]]'
# ---- only sleep/idle inhibitors protect: shutdown alone doesn't (herdr)
mkdir -p "$root/proc/77" "$root/proc/78"
echo "0::/user.slice/app.slice/app-foo.scope" >"$root/proc/77/cgroup"; echo "0::/user.slice/app.slice/app-bar.service" >"$root/proc/78/cgroup"
printf '#!/bin/bash\necho %s\n' "'{\"data\":[[[\"shutdown\",\"Herdr\",\"save\",\"delay\",1000,77],[\"sleep\",\"Omarchy\",\"lock\",\"delay\",1000,78]]]}'" >"$bin/busctl"
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 700 >"$st/screen-on-at"
out=$(OMAMOBILE_DOZED_STOP_AT=900 dozed)
check "a shutdown-only inhibitor holder is frozen; a sleep delay holder is not" 'grep -q "froze app-foo.scope" <<<"$out" && ! grep -q "froze app-bar.service" <<<"$out"'
printf '#!/bin/bash\necho %s\n' "'{\"data\":[[]]}'" >"$bin/busctl"; rm -rf "$root/proc/77" "$root/proc/78"
# ---- the superwhisper wrapper thaws a frozen service, then runs the real command
printf '#!/bin/bash\necho "real $*"\n' >"$bin/sw-real"; chmod +x "$bin/sw-real"
echo superwhisper.service >"$st/frozen"; : >"$st/calls"; echo "frozen 1" >"$root/swev"
w=$(OMAMOBILE_SUPERWHISPER_CGEVENTS=$root/swev OMAMOBILE_SUPERWHISPER_REAL=$bin/sw-real "$here/lib/superwhisper-thaw" status 2>&1)
check "wrapper thaws a frozen superwhisper, then runs it" '[[ $w == "real status" ]] && grep -q "^thaw superwhisper.service" $st/calls && [[ ! -s $st/frozen ]]'
: >"$st/calls"; echo "frozen 0" >"$root/swev"; w=$(OMAMOBILE_SUPERWHISPER_CGEVENTS=$root/swev OMAMOBILE_SUPERWHISPER_REAL=$bin/sw-real "$here/lib/superwhisper-thaw" start 2>&1)
check "wrapper leaves a running superwhisper alone" '[[ $w == "real start" ]] && ! grep -q "^thaw" $st/calls'
echo "frozen 1" >"$root/swev"; touch "$st/thaw-fail"; w=$(OMAMOBILE_SUPERWHISPER_CGEVENTS=$root/swev OMAMOBILE_SUPERWHISPER_REAL=$bin/sw-real "$here/lib/superwhisper-thaw" status 2>&1); rm -f "$st/thaw-fail"
check "a failed thaw still runs the real command" '[[ $w == "real status" ]]'
# ---- sweep thaws a leftover frozen extra unit; refreeze after an outside thaw
rm -rf "$root/run"; echo superwhisper.service >"$st/frozen"; echo 0 >"$root/clock"; echo 0 >"$root/sys/class/backlight/bl/bl_power"; rm -f "$st/screen-on-at"
OMAMOBILE_DOZED_STOP_AT=1 dozed >/dev/null
check "start thaws a leftover frozen superwhisper.service" '[[ ! -s $st/frozen ]]'
cat >"$bin/swthaw" <<EOF2
#!/bin/bash
[[ \$(<$root/clock) -ge 400 && ! -e $st/thawed-once ]] && { touch $st/thawed-once; grep -vx superwhisper.service $st/frozen >$st/f2; mv $st/f2 $st/frozen; }
EOF2
chmod +x "$bin/swthaw"; rm -f "$st/thawed-once"
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 1200 >"$st/screen-on-at"
out=$(OMAMOBILE_DOZE_REFREEZE_EVERY=300 OMAMOBILE_TEST_HOOK=swthaw OMAMOBILE_DOZED_STOP_AT=1300 dozed)
check "an outside thaw is frozen again within the refreeze period" 'grep -q "froze superwhisper.service again" <<<"$out" && [[ ! -s $st/frozen ]]'

# ---- Settings > Apps policy: Restricted frozen at screen off (before LIGHT) and kept through maintenance;
# Unrestricted never frozen; a policy line for a never-freeze app does not override it
printf 'org.r\trestricted\trest\norg.u\tunrestricted\tunr\n' >"$root/home/.config/omamobile/app-policy"
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 200 >"$st/screen-on-at"
out=$(OMAMOBILE_DOZED_STOP_AT=300 dozed)
check "restricted frozen at screen off, before LIGHT" 'grep -q "froze app-Hyprland-rest-1a2b3c4d.scope" <<<"$out" && ! grep -q LIGHT_DOZE <<<"$out" && ! grep -q "froze app-foo.scope" <<<"$out"'
check "restricted thawed on exit" '[[ ! -s $st/frozen ]]'
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 6000 >"$st/screen-on-at"
out=$(OMAMOBILE_DOZED_STOP_AT=6200 dozed)
check "unrestricted never frozen" '! grep -q "froze app-Hyprland-unr" <<<"$out" && grep -q "froze app-foo.scope" <<<"$out"'
check "restricted frozen again after the maintenance thaw" '[[ $(awk "/maintenance window/{m=1} m && /froze app-Hyprland-rest/{print; exit}" <<<"$out") != "" ]]'
rm -f "$root/home/.config/omamobile/app-policy"
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 200 >"$st/screen-on-at"
out=$(OMAMOBILE_DOZED_STOP_AT=300 dozed)
check "no policy file: nothing frozen before LIGHT" '! grep -q "froze" <<<"$out"'

# ---- a drawer launch (unit named after gtk-launch) is matched by GIO_LAUNCHED_DESKTOP_FILE in its environment
mkdir -p "$root/proc/4242" "$root/proc/4343"
printf 'X=1\0GIO_LAUNCHED_DESKTOP_FILE=/usr/share/applications/org.r.desktop\0GIO_LAUNCHED_DESKTOP_FILE_PID=4242\0' >"$root/proc/4242/environ"
printf 'GIO_LAUNCHED_DESKTOP_FILE=/usr/share/applications/org.r.desktop\0GIO_LAUNCHED_DESKTOP_FILE_PID=4242\0' >"$root/proc/4343/environ"
G='app-Hyprland-gtk\x2dlaunch-9a9a9a9a.scope'
echo 4242 >"$root/sys/fs/cgroup/user.slice/app.slice/$G/cgroup.procs"
echo 4343 >"$root/sys/fs/cgroup/user.slice/app.slice/app-foo.scope/cgroup.procs"   # inherited: never org.r
printf 'org.r\trestricted\tnomatch\n' >"$root/home/.config/omamobile/app-policy"
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 200 >"$st/screen-on-at"
out=$(OMAMOBILE_DOZED_STOP_AT=300 dozed)
check "a gtk-launch unit is Restricted by the ID in its environment; an inherited copy is not" 'grep -qF "froze $G" <<<"$out" && ! grep -q "froze app-foo.scope" <<<"$out" && ! grep -q LIGHT_DOZE <<<"$out"'
: >"$root/sys/fs/cgroup/user.slice/app.slice/app-foo.scope/cgroup.procs"; : >"$root/sys/fs/cgroup/user.slice/app.slice/$G/cgroup.procs"; rm -f "$root/home/.config/omamobile/app-policy"

# ---- two apps in one gtk-launch unit: an Unrestricted one keeps it unfrozen even next to a Restricted one
mkdir -p "$root/proc/4444"; printf 'GIO_LAUNCHED_DESKTOP_FILE=/usr/share/applications/org.u.desktop\0GIO_LAUNCHED_DESKTOP_FILE_PID=4444\0' >"$root/proc/4444/environ"
printf '4242\n4444\n' >"$root/sys/fs/cgroup/user.slice/app.slice/$G/cgroup.procs"
printf 'org.r\trestricted\tx\norg.u\tunrestricted\ty\n' >"$root/home/.config/omamobile/app-policy"
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 6000 >"$st/screen-on-at"
out=$(OMAMOBILE_DOZED_STOP_AT=6200 dozed)
check "a unit holding an Unrestricted app is never frozen" '! grep -qF "froze $G" <<<"$out" && grep -q "froze app-foo.scope" <<<"$out"'
: >"$root/sys/fs/cgroup/user.slice/app.slice/$G/cgroup.procs"; rm -f "$root/home/.config/omamobile/app-policy"

# ---- review round 1124: audio starting during SCREEN_OFF thaws a Restricted app before LIGHT
printf 'org.r\trestricted\trest\n' >"$root/home/.config/omamobile/app-policy"
cat >"$bin/pactl" <<EOF2
#!/bin/bash
[[ \$(<$root/clock) -ge 120 && \$3 == sinks ]] && printf '1\tspk\tx\tx\tRUNNING\n'
exit 0
EOF2
chmod +x "$bin/pactl"
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; rm -f "$st/screen-on-at"
out=$(OMAMOBILE_DOZE_POLL=30 OMAMOBILE_DOZED_STOP_AT=250 dozed)
check "audio starting during SCREEN_OFF thaws the Restricted app, and it stays thawed while audio plays" \
  '[[ $(grep -c "froze app-Hyprland-rest" <<<"$out") == 1 ]] && [[ $(grep -n "exit (audio is playing (spk))" <<<"$out" | cut -d: -f1) -gt $(grep -n "froze app-Hyprland-rest" <<<"$out" | cut -d: -f1) ]] && [[ ! -s $st/frozen ]]'
printf '#!/bin/bash\nexit 0\n' >"$bin/pactl"
# ---- an Unrestricted line wins over a Restricted one for the same key, whatever the order
printf 'org.a\trestricted\trest\norg.b\tunrestricted\trest\n' >"$root/home/.config/omamobile/app-policy"
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 6000 >"$st/screen-on-at"
out=$(OMAMOBILE_DOZED_STOP_AT=6200 dozed)
check "Unrestricted beats an earlier Restricted line for a shared key" '! grep -q "froze app-Hyprland-rest" <<<"$out" && grep -q "froze app-foo.scope" <<<"$out"'
# ---- the policy file follows XDG_CONFIG_HOME, as the writer does
mkdir -p "$root/xdg/omamobile"; printf 'org.r\trestricted\n' >"$root/xdg/omamobile/app-policy"; rm -f "$root/home/.config/omamobile/app-policy"
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 200 >"$st/screen-on-at"
mkdir -p "$root/proc/4242"; printf 'GIO_LAUNCHED_DESKTOP_FILE=/usr/share/applications/org.r.desktop\0GIO_LAUNCHED_DESKTOP_FILE_PID=4242\0' >"$root/proc/4242/environ"
echo 4242 >"$root/sys/fs/cgroup/user.slice/app.slice/$G/cgroup.procs"
out=$(XDG_CONFIG_HOME=$root/xdg OMAMOBILE_DOZED_STOP_AT=300 dozed)
check "XDG_CONFIG_HOME policy read; a line with no unit keys still counts as Restricted" 'grep -qF "froze $G" <<<"$out"'
rm -rf "$root/xdg"
# ---- a drawer-launched clock app is skipped by its launched ID
printf 'GIO_LAUNCHED_DESKTOP_FILE=/usr/share/applications/org.gnome.clocks.desktop\0GIO_LAUNCHED_DESKTOP_FILE_PID=4242\0' >"$root/proc/4242/environ"
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 700 >"$st/screen-on-at"
out=$(OMAMOBILE_DOZED_STOP_AT=900 dozed)
check "a clock app launched from the drawer is never frozen" '! grep -qF "froze $G" <<<"$out" && grep -q "froze app-foo.scope" <<<"$out"'
: >"$root/sys/fs/cgroup/user.slice/app.slice/$G/cgroup.procs"
# ---- a freeze that fails is thawed; its line goes only once systemd says the unit runs
cat >"$bin/systemctl.fail" <<EOF2
#!/bin/bash
for x in "\$@"; do [[ \$x == freeze ]] && { echo "\${@: -1}" >>$st/frozen; exit 124; }; done
exec $bin/systemctl.real "\$@"
EOF2
mv "$bin/systemctl" "$bin/systemctl.real"; mv "$bin/systemctl.fail" "$bin/systemctl"; chmod +x "$bin/systemctl"
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 700 >"$st/screen-on-at"
out=$(OMAMOBILE_DOZED_STOP_AT=600 dozed)
check "a timed-out freeze that landed is thawed again" 'grep -q "could not freeze app-foo.scope" <<<"$out" && [[ ! -s $st/frozen ]] && [[ ! -s $root/run/applied ]]'
mv "$bin/systemctl.real" "$bin/systemctl"
# ---- a thaw that fails while systemd can't say the state keeps the line, a later restore releases it
echo app-foo.scope >"$st/frozen"; printf 'thaw app-foo.scope\n' >"$root/run/applied"; touch "$st/thaw-fail" "$st/show-fail"
o1=$(dozed restore); o2=$(dozed restore)
check "an unknown state keeps the thaw line" 'grep -qx "thaw app-foo.scope" $root/run/applied && grep -q "kept for retry" <<<"$o1"'
rm -f "$st/thaw-fail" "$st/show-fail"; dozed restore >/dev/null
check "the kept line is thawed and dropped on a later restore" '[[ ! -s $root/run/applied && ! -s $st/frozen ]]'
# ---- an upper-case drawer ID is checked lowercased (ALARM matches only as alarm)
printf 'GIO_LAUNCHED_DESKTOP_FILE=/usr/share/applications/com.example.ALARM.desktop\0GIO_LAUNCHED_DESKTOP_FILE_PID=4242\0' >"$root/proc/4242/environ"
echo 4242 >"$root/sys/fs/cgroup/user.slice/app.slice/$G/cgroup.procs"
rm -rf "$root/run"; : >"$st/frozen"; echo 0 >"$root/clock"; echo 1 >"$root/sys/class/backlight/bl/bl_power"; echo 700 >"$st/screen-on-at"
out=$(OMAMOBILE_DOZED_STOP_AT=900 dozed)
check "an upper-case alarm app ID from the drawer is never frozen" '! grep -qF "froze $G" <<<"$out" && grep -q "froze app-foo.scope" <<<"$out"'
: >"$root/sys/fs/cgroup/user.slice/app.slice/$G/cgroup.procs"
# ---- the wrapper refuses to run itself
w=$(OMAMOBILE_SUPERWHISPER_REAL=$here/lib/superwhisper-thaw "$here/lib/superwhisper-thaw" status 2>&1); rc=$?
check "the wrapper linked in place of the real binary stops" '[[ $rc == 127 && $w == *"in place of the real"* ]]'

echo "$n checks, $([[ $fail == 0 ]] && echo all pass || echo FAILURES)"
exit $fail
