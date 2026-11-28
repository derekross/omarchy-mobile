#!/bin/bash
# SPDX-License-Identifier: MIT
# bin/omamobile-screenrecord against stand-ins for wf-recorder, pactl,
# hyprctl, slurp, systemd-inhibit and the thermal zones: the arguments per
# audio mode and area, the null sink's modules and their cleanup, the heat
# gate and the heat stop (file kept), the screen-off stop, a cancelled
# pick, the start lock, and the older positional form.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
t=$(mktemp -d)
cleanup() { pkill -INT -f "$t/bin/wf-recorder" 2>/dev/null || true; rm -rf "$t"; }
trap cleanup EXIT
rec=$PWD/bin/omamobile-screenrecord

mkdir -p "$t/bin" "$t/run" "$t/videos" "$t/thermal"/{z0,z1,z2} "$t/home"
export T=$t HOME=$t/home XDG_RUNTIME_DIR=$t/run XDG_VIDEOS_DIR=$t/videos XDG_CONFIG_HOME=$t/home/.config
export OMAMOBILE_RECORD_THERMAL_GLOB="$t/thermal/z*" OMAMOBILE_RECORD_TICK=0.2
export OMAMOBILE_RECORD_PICK_DELAY=0
export PATH="$t/bin:$PATH"
# The recorder by path, never by name, so a real wf-recorder later on PATH is never started.
export OMAMOBILE_RECORD_WF=$t/bin/wf-recorder
unset OMAMOBILE_RECORD_HEAT_START OMAMOBILE_RECORD_HEAT_STOP
echo big-thermal >"$t/thermal/z0/type"; echo gpu-thermal >"$t/thermal/z1/type"; echo battery >"$t/thermal/z2/type"
temps() { echo "$1" >"$t/thermal/z0/temp"; echo "$2" >"$t/thermal/z1/temp"; echo 90000 >"$t/thermal/z2/temp"; }
temps 50000 48000

# Python, because a shell can't trap SIGINT that a background start ignored
# (wf-recorder, in C, installs its own handler the same way).
cat >"$t/bin/wf-recorder" <<'EOF'
#!/usr/bin/env python3
import os, signal, sys, time
a = sys.argv[1:]
open(os.environ["T"] + "/wf-args", "w").write("\n".join(a) + "\n")
f = a[a.index("-f") + 1]
def done(*_):
    open(f, "w").write("video"); sys.exit(0)
signal.signal(signal.SIGINT, done); signal.signal(signal.SIGTERM, done)
while True: time.sleep(0.05)
EOF
cat >"$t/bin/pactl" <<'EOF'
#!/bin/bash
echo "$*" >>"$T/pactl"
case $1 in
  get-default-sink) echo speaker ;;
  get-default-source) echo mic0 ;;
  load-module) n=$(( $(cat "$T/modn" 2>/dev/null || echo 40) + 1 )); echo $n >"$T/modn"; echo "$n $*" >>"$T/mods"; echo $n ;;
  unload-module) sed -i "/^$2 /d" "$T/mods" 2>/dev/null; true ;;
  list) [[ -f $T/mods ]] && awk '{print $1"\t"$4"\t"$5}' "$T/mods"; true ;;
esac
EOF
cat >"$t/bin/hyprctl" <<'EOF'
#!/bin/bash
d=true; [[ -f $T/dpms-off ]] && d=false
echo "[{\"name\":\"DSI-1\",\"focused\":true,\"dpmsStatus\":$d}]"
EOF
cat >"$t/bin/slurp" <<'EOF'
#!/bin/bash
cat "$T/pick" 2>/dev/null
EOF
cat >"$t/bin/systemd-inhibit" <<'EOF'
#!/bin/bash
while [[ $1 == --* ]]; do shift; done
echo inhibit >>"$T/inhibit"; exec "$@"
EOF
printf '#!/bin/sh\necho "$@" >>"$T/notes"\n' >"$t/bin/notify-send"
cp "$t/bin/notify-send" "$t/bin/omarchy-notification-send"
printf '#!/bin/sh\nexit 0\n' >"$t/bin/omarchy-shell"
# Stand-ins first on PATH, so a run never reaches a real picker or notifier.
cat >"$t/bin/omarchy-capture-region" <<'EOF'
#!/bin/bash
[[ -f $T/pick-wait ]] && { sleep 20; exit 1; }
cat "$T/pick" 2>/dev/null
EOF
chmod +x "$t/bin"/*

arg() { grep -qxF -- "$1" "$t/wf-args"; }
wait_stopped() { local i; for i in $(seq 1 100); do [[ ! -e $t/run/omamobile-screenrecord/supervisor ]] && return 0; sleep 0.1; done; return 1; }
reset() { "$rec" stop >/dev/null 2>&1 || true; wait_stopped || true; rm -f "$t"/{wf-args,pactl,mods,notes,inhibit,dpms-off,pick,pick-wait} "$t/videos"/*; }

# --- full screen, no sound
"$rec" start --audio none --area full
[[ $("$rec" status) == on ]] || fail "status is on while recording"
[[ -s $t/run/omamobile-screenrecord/started ]] || fail "started file for the bar"
arg DSI-1 || fail "focused output"
grep -q 'threads=2' "$t/wf-args" || fail "threads cap passed"
grep -q -- "--audio" "$t/wf-args" && fail "no audio for none"
grep -q -- '-R' "$t/wf-args" && fail "no -R without audio"
grep -q "trunc(min(720,iw)/2)\*2" "$t/wf-args" || fail "720 px, even, never upscaled"
[[ -s $t/inhibit ]] || fail "the supervisor runs under systemd-inhibit"
"$rec" stop
wait_stopped || fail "supervisor ended after stop"
[[ $("$rec" status) == off ]] || fail "status off after stop"
ls "$t/videos"/*.mp4 >/dev/null 2>&1 || fail "file kept after stop"
[[ -e $t/run/omamobile-screenrecord/started ]] && fail "started file removed"
grep -q "saved" "$t/notes" || fail "saved notification"
pass "full screen, no sound: start, status, stop, file and notification"
reset

# --- each audio mode
"$rec" start --audio mic; arg "--audio=mic0" && arg "-R" || fail "mic: default source"; reset
"$rec" start --audio system; arg "--audio=speaker.monitor" || fail "system: default sink monitor"; reset
"$rec" start mic; arg "--audio=mic0" || fail "older positional form"; reset
"$rec" start --audio both
arg "--audio=omamobile_screenrec.monitor" || fail "both: null sink monitor"
[[ $(wc -l <"$t/mods") == 3 ]] || fail "both: null sink + two loopbacks loaded"
grep -q "source=speaker.monitor sink=omamobile_screenrec" "$t/mods" && grep -q "source=mic0 sink=omamobile_screenrec" "$t/mods" \
  || fail "both: loopbacks from the sink monitor and the mic"
"$rec" stop; wait_stopped
[[ -s $t/mods ]] && fail "both: modules unloaded after stop"
pass "audio modes none/both/system/mic and the older form"
reset

# --- crash in both mode: the supervisor unloads at once
"$rec" start --audio both
pkill -KILL -f "$t/bin/wf-recorder"
wait_stopped || fail "supervisor notices a crashed recorder"
[[ -s $t/mods ]] && fail "modules unloaded after a crash"
pass "a crashed recorder: modules unloaded, state cleared"
reset

# --- stale modules from an earlier crash are swept at start
echo "77 load-module module-loopback source=x sink=omamobile_screenrec" >"$t/mods"
"$rec" start --audio none
grep -q "^77 " "$t/mods" && fail "stale module swept at start"
pass "stale omamobile_screenrec modules swept at start"
reset

# --- area pick
echo "10,20 301x201" >"$t/pick"
"$rec" start --audio none --area pick
grep -qx -- "-g" "$t/wf-args" && arg "10,20 300x200" || fail "area: even geometry passed"
pass "area pick: geometry evened"
reset
: >"$t/pick"
if "$rec" start --audio none --area pick 2>/dev/null; then fail "cancelled pick returns non-zero"; fi
[[ $("$rec" status) == off ]] || fail "nothing records after a cancelled pick"
pass "cancelled pick: nothing starts"
reset
"$rec" start --audio none --area pick --geometry "0,0 100x100"; arg "0,0 100x100" || fail "--geometry"; reset

# --- stop during a pick closes the picker and starts nothing
touch "$t/pick-wait"
"$rec" start --audio none --area pick 2>/dev/null & sp=$!
sleep 0.5
s0=$SECONDS; "$rec" stop
wait $sp 2>/dev/null || true
(( SECONDS - s0 < 5 )) || fail "stop during a pick returns quickly"
[[ -e $t/wf-args ]] && fail "nothing launched after a stop during the pick"
pass "stop during a pick cancels it"
reset

# --- native width stays even
OMAMOBILE_RECORD_WIDTH=native "$rec" start --audio none
grep -q "trunc(iw/2)\*2:trunc(ih/2)\*2" "$t/wf-args" || fail "native: even size"
pass "native width"
reset

# --- a dead supervisor: stop still saves and cleans up; a stale started file clears
"$rec" start --audio both
pkill -KILL -f "$rec supervise"
sleep 0.2
"$rec" stop
[[ $("$rec" status) == off ]] || fail "dead supervisor: stopped"
[[ -s $t/mods ]] && fail "dead supervisor: modules unloaded"
[[ -e $t/run/omamobile-screenrecord/started ]] && fail "dead supervisor: started cleared"
date +%s >"$t/run/omamobile-screenrecord/started"
"$rec" stop
[[ -e $t/run/omamobile-screenrecord/started ]] && fail "stale started file cleared by stop"
pass "dead supervisor and stale state"
reset

# --- pactl failing does not kill start or stop
mv "$t/bin/pactl" "$t/bin/.pactl"; printf '#!/bin/sh\nexit 1\n' >"$t/bin/pactl"; chmod +x "$t/bin/pactl"
"$rec" start --audio system 2>/dev/null
[[ $("$rec" status) == on ]] || fail "pactl failing: records without sound"
grep -q -- "--audio" "$t/wf-args" && fail "pactl failing: no audio device"
"$rec" stop; wait_stopped || fail "pactl failing: supervisor finished"
mv "$t/bin/.pactl" "$t/bin/pactl"
pass "pactl failing"
reset

# --- stop is prompt with the default 5 s tick, and an immediate restart is not hurt by the old supervisor
OMAMOBILE_RECORD_TICK=5 "$rec" start --audio both
s0=$SECONDS; "$rec" stop
(( SECONDS - s0 < 4 )) || fail "stop wakes the supervisor"
[[ -e $t/run/omamobile-screenrecord/started ]] && fail "chip cleared at stop"
OMAMOBILE_RECORD_TICK=5 "$rec" start --audio both
sleep 1
[[ $("$rec" status) == on ]] || fail "second recording runs"
[[ -s $t/run/omamobile-screenrecord/started ]] || fail "second recording keeps its state"
[[ $(wc -l <"$t/mods") == 3 ]] || fail "second recording keeps its modules"
pass "prompt stop and an immediate restart"
reset

# --- unknown heat prints -
mkdir -p "$t/thermal-none"; OMAMOBILE_RECORD_THERMAL_GLOB="$t/thermal-none/z*" "$rec" heat | grep -cx -- "- off" >/dev/null || fail "unknown heat prints -"
pass "unknown heat"

# --- heat limits are off by default: starts and keeps running when hot
temps 75000 40000
"$rec" start --audio none; [[ $("$rec" status) == on ]] || fail "starts hot with no HEAT_START"
sleep 1; [[ $("$rec" status) == on ]] || fail "no heat stop without HEAT_STOP"
[[ $("$rec" heat) == "75 off" ]] || fail "heat prints off without a limit"
pass "heat: no start refusal and no heat stop by default"
reset

# --- heat gate (HEAT_START=59) and heat stop (HEAT_STOP=60, file kept), opted in
export OMAMOBILE_RECORD_HEAT_START=59 OMAMOBILE_RECORD_HEAT_STOP=60
temps 60000 40000
rc=0; "$rec" start --audio none || rc=$?
[[ $rc == 3 ]] || fail "refuses at 60 C (rc $rc)"
grep -q "warm" "$t/notes" || fail "warm notification"
[[ $("$rec" status) == off ]] || fail "nothing started when warm"
temps 59000 40000
"$rec" start --audio none; [[ $("$rec" status) == on ]] || fail "starts at 59 C"
temps 61000 40000
wait_stopped || fail "stops at 60 C"
ls "$t/videos"/*.mp4 >/dev/null 2>&1 || fail "file kept on the heat stop"
grep -q "reached 61 C" "$t/notes" || fail "heat stop notification"
grep -q "stopped: heat:61" "$t/run/omamobile-screenrecord/log" || fail "heat stop reason in the log"
[[ $("$rec" heat) == "61 59" ]] || fail "heat ignores the battery zone, prints the limit"
unset OMAMOBILE_RECORD_HEAT_START OMAMOBILE_RECORD_HEAT_STOP
pass "heat opted in: starts at 59 C, refuses above, stops at 60 C with the file kept"
temps 50000 48000
reset
mkdir -p "$t/home/.config/omamobile"; echo "HEAT_START=45" >"$t/home/.config/omamobile/screenrecord.conf"
rc=0; "$rec" start --audio none || rc=$?; [[ $rc == 3 ]] || fail "HEAT_START from the config file"
rm -f "$t/home/.config/omamobile/screenrecord.conf"
pass "heat limits from screenrecord.conf"
reset

# --- screen off stops and keeps
"$rec" start --audio none
touch "$t/dpms-off"
wait_stopped || fail "stops when the screen goes off"
grep -q "screen went off" "$t/notes" || fail "screen-off notification"
pass "screen off: stops, file kept"
reset

# --- start lock: a second start while one holds the lock does nothing
mkdir -p "$t/run/omamobile-screenrecord"
exec 7>"$t/run/omamobile-screenrecord/lock"; flock 7
"$rec" start --audio none 2>/dev/null
[[ -e $t/wf-args ]] && fail "no second recorder while a start holds the lock"
exec 7>&-
pass "start lock"
reset

# --- no recorder: a path that doesn't exist, never a lookup on PATH
rc=0; OMAMOBILE_RECORD_WF=$t/no-such/wf-recorder "$rec" start --audio none >/dev/null 2>&1 || rc=$?
[[ $rc == 1 ]] || fail "needs wf-recorder"
[[ -e $t/wf-args ]] && fail "no recorder started when it is missing"
pass "missing wf-recorder"

# --- the tile passes the page's choices through
grep -q 'exec omamobile-screenrecord start "\$@"' plugins/omamobile.quicksettings/tile-action.sh || fail "tile-action passes all arguments"
pass "tile-action passes the page's choices"
