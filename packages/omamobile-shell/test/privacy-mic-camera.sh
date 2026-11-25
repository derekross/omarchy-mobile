#!/bin/bash
# SPDX-License-Identifier: MIT
# libexec/privacy mic-off|mic-on|camera-off|camera-on in a scratch root: /dev
# holds plain files, /proc fd and map_files links to them, /sys the codec's
# driver link; udevadm, setfacl, systemctl, loginctl, kill, stat, chown and
# chmod are stubs that record what they were asked (stat answers from a table
# the stubs keep, as udev and chown would set it).
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
r=$tmp/root; b=$tmp/bin; log=$tmp/log; modes=$tmp/modes
state=$r/var/lib/omamobile/privacy
dropin=$r/etc/wireplumber/wireplumber.conf.d
mkdir -p "$b" "$r/dev/snd" "$r/proc" "$r/usr/share/alsa/ucm2/Google/husky"
die() { echo "FAIL: $1" >&2; [[ -f $log ]] && sed 's/^/  log: /' "$log" >&2; exit 1; }
stub() { printf '#!/bin/bash\n%s\n' "$2" > "$b/$1"; chmod 755 "$b/$1"; }
# the table: "<path> <uid:gid:mode>"; a node not in it is the session's (0:29:660 with an ACL)
stub stat 'f=${@: -1}; l=$(grep -F "$f " "'"$modes"'" | tail -n 1); echo "${l##* }"; [[ -n $l ]] || echo 0:29:660'
stub chown 'echo "chown $*" >> "'"$log"'"'
# chmod 600 locks unless $tmp/chmodfail
stub chmod 'echo "chmod $*" >> "'"$log"'"; [[ $1 == 600 && ! -f "'"$tmp"'/chmodfail" ]] && echo "$2 0:0:600" >> "'"$modes"'"; true'
stub setfacl 'echo "setfacl $*" >> "'"$log"'"'
# getfacl: a named user entry while $tmp/aclstays exists (an ACL setfacl could not clear)
stub getfacl '[[ -f "'"$tmp"'/aclstays" ]] && echo "user:lef:rw-"; echo "user::rw-"; true'
# udev: on a trigger the rule locks the nodes listed in $tmp/udev-locks while
# their state file is there and gives them back to the session when it is not;
# $tmp/udevfail fails every trigger
stub udevadm 'echo "udevadm $*" >> "'"$log"'"; [[ $1 == trigger ]] || exit 0; [[ -f "'"$tmp"'/udevfail" ]] && exit 1
[[ -f "'"$tmp"'/udev-locks" ]] || exit 0
while read -r n; do case $n in */snd/*) k=mic ;; *) k=camera ;; esac
  if [[ -e "'"$state"'/$k" ]]; then echo "$n 0:0:600"; else echo "$n 0:29:660"; fi; done < "'"$tmp"'/udev-locks" >> "'"$modes"'"'
cp "$b/udevadm" "$b/udevadm.keep"
stub loginctl 'echo "1000 lef no active"; echo "0 root no active"'
# a restart of the user audio closes PipeWire (pid 100) unless $tmp/pwstays; $tmp/sysfail fails it
stub systemctl 'echo "systemctl $*" >> "'"$log"'"; [[ -f "'"$tmp"'/sysfail" ]] && exit 1; [[ -f "'"$tmp"'/pwstays" ]] || rm -rf "'"$r"'/proc/100"; true'
stub kill 'echo "kill $*" >> "'"$log"'"; [[ -f "'"$tmp"'/stubborn" || ( -f "'"$tmp"'/termproof" && $1 == -TERM ) ]] || rm -rf "'"$r"'/proc/${@: -1}"'
run() { PATH="$b:$PATH" OMAMOBILE_PRIVACY_ROOT=$r bash libexec/privacy "$@"; }
reset() {
  : > "$log"; : > "$modes"; rm -rf "$state" "$dropin" "$r/proc"/* "$r/sys"
  rm -f "$tmp"/{udev-locks,stubborn,termproof,sysfail,aclstays,udevfail,chmodfail,pwstays}
}
# /proc/<pid>: comm, a stat with start time 4242, status Uid, an optional cgroup
proc() {
  mkdir -p "$r/proc/$1/fd" "$r/proc/$1/map_files"; printf '%s\n' "$2" > "$r/proc/$1/comm"
  printf '%s (%s) S%s 4242\n' "$1" "$2" "$(printf ' 0%.0s' {1..18})" > "$r/proc/$1/stat"
  printf 'Uid:\t%s\t%s\n' "${3:-1000}" "${3:-1000}" > "$r/proc/$1/status"
  [[ -z ${4:-} ]] || printf '0::%s\n' "$4" > "$r/proc/$1/cgroup"
}
# holder <pid> <name> <node> [uid] [cgroup]: an open fd on the node
holder() { proc "$1" "$2" "${4:-1000}" "${5:-}"; ln -sf "$r$3" "$r/proc/$1/fd/7"; }
pwcg=/user.slice/user-1000.slice/user@1000.service/session.slice/pipewire.service
guarded='SectionDevice."Speaker" {}
If.omamobile_privacy_mic { Condition { Type Path Path "/var/lib/omamobile/privacy/mic" Mode exists }
False { SectionDevice."Mic" { Value { CapturePCM "hw:0,8" } } } }'
printf '%s\n' "$guarded" > "$r/usr/share/alsa/ucm2/Google/husky/HiFi.conf"
touch "$r/dev/snd/pcmC0D8c" "$r/dev/snd/pcmC0D5p" "$r/dev/snd/pcmC1D0c" "$r/dev/snd/controlC0"
mics() { printf '%s\n' "$r/dev/snd/pcmC0D8c" "$r/dev/snd/pcmC1D0c" > "$tmp/udev-locks"; }

# --- mic-off: state, drop-in, udev, nodes locked here too, ACLs cleared, audio restarted, holders stopped
reset; mics
holder 100 pipewire /dev/snd/pcmC0D8c 1000 "$pwcg"
holder 200 arecord /dev/snd/pcmC1D0c
holder 300 pipewire /dev/snd/pcmC0D5p
out=$(run mic-off) || die "mic-off succeeds"
[[ $(cat "$state/mic") == off ]] || die "mic-off writes the state file"
grep -c 'a2dp_sink a2dp_source' "$dropin/90-omamobile-privacy-mic.conf" >/dev/null || die "the drop-in keeps Bluetooth to A2DP"
grep -c 'node.disabled = true' "$dropin/90-omamobile-privacy-mic.conf" >/dev/null || die "the drop-in hides ALSA inputs"
grep -c 'api.alsa.use-ucm = false' "$dropin/90-omamobile-privacy-mic.conf" >/dev/null || die "USB cards drop UCM while the mic is off"
grep -c 'EO[FD]' "$dropin/90-omamobile-privacy-mic.conf" >/dev/null && die "the drop-in has no heredoc marker in it"
grep -cx 'udevadm trigger --action=change --subsystem-match=sound' "$log" >/dev/null || die "udev re-applies the rule to sound"
grep -cx "setfacl -b $r/dev/snd/pcmC0D8c" "$log" >/dev/null || die "the built-in capture's ACL is cleared"
grep -cx "setfacl -b $r/dev/snd/pcmC1D0c" "$log" >/dev/null || die "a USB capture's ACL is cleared"
grep -cx "chmod 600 $r/dev/snd/pcmC1D0c" "$log" >/dev/null || die "every capture is also set 0600 here"
grep -c 'pcmC0D5p\|controlC0' "$log" >/dev/null && die "playback and the mixer are never touched"
grep -cx 'systemctl --user -M lef@ try-restart wireplumber.service pipewire.service' "$log" >/dev/null \
  || die "the user's WirePlumber and PipeWire restart"
grep -c -- '-M root@' "$log" >/dev/null && die "only users from uid 1000 are restarted"
grep -cx 'kill -TERM 200' "$log" >/dev/null || die "a process still holding a capture gets TERM"
grep -c 'kill -TERM 300' "$log" >/dev/null && die "a playback holder is left alone"
[[ $out == *"stopping arecord (200)"* && $out == *"The microphone is off"* ]] || die "mic-off says what it stopped: $out"

# PipeWire still holding a capture after the restart: its unit is restarted again, never signalled
reset; mics; touch "$tmp/pwstays"
holder 100 pipewire /dev/snd/pcmC0D8c 1000 "$pwcg"
rc=0; out=$(run mic-off 2>&1) || rc=$?
grep -c 'kill .* 100$' "$log" >/dev/null && die "PipeWire was signalled"
grep -cx 'systemctl --user -M lef@ restart pipewire.service' "$log" >/dev/null || die "PipeWire's unit is restarted through the user's manager"
[[ $(grep -c 'restart pipewire.service$' "$log") == 1 ]] || die "PipeWire's unit is restarted once"
[[ $rc == 1 && $out == *"still open by: pipewire (100)"* ]] || die "a PipeWire that stays is named (rc $rc: $out)"

# a process of the user's in a look-alike cgroup deeper down is no audio unit: it is signalled
reset; mics
holder 210 fakepw /dev/snd/pcmC0D8c 1000 /user.slice/user-1000.slice/user@1000.service/app.slice/x.scope/pipewire.service
holder 220 otheruid /dev/snd/pcmC1D0c 1001 "$pwcg"
out=$(run mic-off) || die "look-alike audio units are stopped"
grep -cx 'kill -TERM 210' "$log" >/dev/null || die "a nested pipewire.service cgroup was taken for PipeWire"
grep -cx 'kill -TERM 220' "$log" >/dev/null || die "another uid in user 1000's PipeWire cgroup was taken for it"

# a holder that won't go: mic-off fails and names it; the lock held, so the state stays off
reset; mics
touch "$tmp/stubborn"; holder 200 recorder /dev/snd/pcmC0D8c
rc=0; err=$(run mic-off 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"still open by: recorder (200)"* ]] || die "a holder that stays fails mic-off by name (rc $rc: $err)"
[[ -e $state/mic ]] || die "a holder that stays leaves the (locked) microphone off"

# TERM ignored: KILL after the wait; a mapping (map_files) counts; a hostile name never picks a pid
reset; mics; touch "$tmp/termproof"
holder 200 stubborn /dev/snd/pcmC0D8c
proc 600 $'x\n1 y'; ln -s "$r/dev/snd/pcmC0D8c" "$r/proc/600/map_files/7f00-7f10"
out=$(run mic-off) || die "mic-off succeeds once KILL stops what TERM did not"
grep -cx 'kill -TERM 200' "$log" >/dev/null && grep -cx 'kill -KILL 200' "$log" >/dev/null || die "TERM, then KILL"
grep -cx 'kill -TERM 600' "$log" >/dev/null || die "a holder by mapping alone is stopped too"
grep -c 'kill -[A-Z]* 1$' "$log" >/dev/null && die "a newline in a process name made the helper signal pid 1"
[[ $out == *"stopping x1y (600)"* ]] || die "a process name is shown cleaned: $out"

# a pid reused between the scan and its signal (another start time) is not signalled in that round
reset; mics
holder 200 first /dev/snd/pcmC0D8c; holder 201 second /dev/snd/pcmC1D0c
stub kill 'echo "kill $*" >> "'"$log"'"; [[ ${@: -1} == 200 ]] && sed -i "s/ 4242$/ 9999/" "'"$r"'/proc/201/stat"; rm -rf "'"$r"'/proc/${@: -1}"'
run mic-off >/dev/null 2>&1 || true
grep -cx 'kill -TERM 200' "$log" >/dev/null || die "the first holder gets TERM"
grep -cx 'kill -TERM 201' "$log" >/dev/null && die "a pid whose start time changed after the scan got TERM"
stub kill 'echo "kill $*" >> "'"$log"'"; [[ -f "'"$tmp"'/stubborn" || ( -f "'"$tmp"'/termproof" && $1 == -TERM ) ]] || rm -rf "'"$r"'/proc/${@: -1}"'

# another file (one with the same path under another root, one named like the node) is no holder of video1; nobody (65534) is a system process
reset
mkdir -p "$tmp/other/dev"; touch "$r/dev/video1" "$tmp/other/dev/video1" "$tmp/video1.mp4"; printf '%s\n' "$r/dev/video1" > "$tmp/udev-locks"
proc 810 other; ln -s "$tmp/other/dev/video1" "$r/proc/810/fd/7"
proc 820 player; ln -s "$tmp/video1.mp4" "$r/proc/820/map_files/7f00-7f10"
holder 830 nobodyd /dev/video1 65534
rc=0; err=$(run camera-off 2>&1 >/dev/null) || rc=$?
grep -c 'kill .* 8[12]0$' "$log" >/dev/null && die "a look-alike was taken for a holder"
grep -c 'kill .* 830$' "$log" >/dev/null && die "nobody (65534) was signalled"
[[ $rc == 1 && $err == *"still open by: nobodyd (830)"* ]] || die "nobody's holder is named (rc $rc: $err)"
rm -f "$r/dev/video1"

# a system process is never signalled: named, and mic-off fails
reset; mics
holder 700 sysrec /dev/snd/pcmC0D8c 0
rc=0; err=$(run mic-off 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"still open by: sysrec (700)"* ]] || die "a root holder fails mic-off by name (rc $rc: $err)"
grep -c 'kill .* 700' "$log" >/dev/null && die "a root process was signalled"

# a failed restart of the user's audio fails mic-off (PipeWire may still have the old profile); the lock stays
reset; mics; touch "$tmp/sysfail"
rc=0; err=$(run mic-off 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"could not restart the audio of lef"* ]] || die "a failed audio restart fails mic-off (rc $rc: $err)"
[[ -e $state/mic ]] || die "a failed restart over a good lock leaves the microphone off"

# a lock that fails (an ACL stays) is undone: not changed, no state file, no drop-in, no restart
reset; mics; touch "$tmp/aclstays"
rc=0; err=$(run mic-off 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"an ACL is still on /dev/snd/pcmC0D8c"* && $err == *"not changed: the microphone could not be locked"* ]] \
  || die "an ACL left fails mic-off and undoes it (rc $rc: $err)"
[[ ! -e $state/mic && ! -e $dropin/90-omamobile-privacy-mic.conf ]] || die "a failed lock leaves no state file or drop-in"
grep -c 'try-restart' "$log" >/dev/null && die "a failed lock restarts no audio"
# a failed trigger is a failed lock too (logind re-grants ACLs from udev's uaccess tag)
reset; touch "$r/dev/video1" "$tmp/udevfail"
rc=0; err=$(run camera-off 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"it is left off, its nodes locked here"* && -e $state/camera ]] \
  || die "a failed lock whose undo fails too stays off and says so (rc $rc: $err)"
grep -cx "chmod 600 $r/dev/video1" "$log" >/dev/null || die "a failed undo still locks the node it can"
rm -f "$r/dev/video1"
# a drop-in that can't be written stops mic-off before the state file
reset; mics; mkdir -p "$r/etc/wireplumber"; touch "$dropin"
rc=0; err=$(run mic-off 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"not changed: could not write the WirePlumber drop-in"* && ! -e $state/mic ]] \
  || die "a failed drop-in write changes nothing (rc $rc: $err)"
grep -c 'udevadm\|chmod 600' "$log" >/dev/null && die "a failed drop-in write locks nothing"
reset; touch "$tmp/chmodfail"  # udev did not lock either
rc=0; err=$(run mic-off 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"pcmC0D8c is still open to the session"* && ! -e $state/mic ]] || die "a node that stays open is undone (rc $rc: $err)"

# a node the rule didn't lock is locked here
reset
out=$(run mic-off) || die "mic-off without udev's lock still succeeds once it locks the nodes itself"
grep -cx "chmod 600 $r/dev/snd/pcmC0D8c" "$log" >/dev/null || die "an unlocked capture is set 0600 here"
grep -cx "chown root:root $r/dev/snd/pcmC1D0c" "$log" >/dev/null || die "an unlocked capture is set root:root here"

# --- mic-on: file gone, udev unlocks, then the drop-in goes and the audio restarts
reset; mics; run mic-off >/dev/null || die "mic-off before mic-on"; : > "$log"
out=$(run mic-on) || die "mic-on succeeds"
[[ ! -e $state/mic && ! -e $dropin/90-omamobile-privacy-mic.conf ]] || die "mic-on removes the file and the drop-in"
grep -cx 'udevadm trigger --action=change --subsystem-match=sound' "$log" >/dev/null || die "mic-on re-applies udev"
grep -c 'try-restart wireplumber.service' "$log" >/dev/null || die "mic-on restarts the user's audio"
grep -c 'setfacl\|kill' "$log" >/dev/null && die "mic-on clears nothing and stops nothing"
# a failed trigger: the file, the drop-in and the lock come back, and no audio restart re-adds the UCM Mic
reset; mics; run mic-off >/dev/null || die "mic-off before a failed mic-on"; : > "$log"; touch "$tmp/udevfail"
rc=0; err=$(run mic-on 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"udev could not re-apply"* && $err == *"not changed: the microphone could not be unlocked"* ]] || die "a failed trigger fails mic-on (rc $rc: $err)"
[[ -e $state/mic && -e $dropin/90-omamobile-privacy-mic.conf ]] || die "a failed mic-on puts the state file back and keeps the drop-in"
grep -c 'try-restart' "$log" >/dev/null && die "a failed mic-on restarts no audio"
grep -cx "chmod 600 $r/dev/snd/pcmC0D8c" "$log" >/dev/null || die "a failed mic-on locks the nodes again"
# a node udev left locked (trigger ok): the same
reset; mics; run mic-off >/dev/null || die "mic-off before a half mic-on"; : > "$log"
printf '%s\n' "$r/dev/snd/pcmC0D8c" > "$tmp/udev-locks"
rc=0; err=$(run mic-on 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"/dev/snd/pcmC1D0c is still locked"* && -e $state/mic ]] || die "a capture still locked fails mic-on (rc $rc: $err)"
grep -c 'try-restart' "$log" >/dev/null && die "a capture still locked restarts no audio"
# a failed unlock whose relock fails too never says "not changed"
reset; mics; run mic-off >/dev/null || die "mic-off before a broken mic-on"; : > "$log"; touch "$tmp/udevfail" "$tmp/chmodfail"
: > "$modes"
rc=0; err=$(run mic-on 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"maybe partly open"* && $err != *"not changed"* && -e $state/mic ]] || die "a failed relock says it may be partly open (rc $rc: $err)"
reset; touch "$tmp/udevfail"; mkdir -p "$state"; echo off > "$state/camera"
rc=0; err=$(run camera-on 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"not changed: the camera could not be unlocked"* && -e $state/camera ]] || die "a failed trigger fails camera-on (rc $rc: $err)"

# stopped mid-switch (the unit's time limit, TERM): fail closed, with the file and the nodes root's
reset; mics; run mic-off >/dev/null || die "mic-off before a stopped mic-on"; : > "$log"
stub udevadm 'echo "udevadm $*" >> "'"$log"'"; [[ $1 == trigger ]] && sleep 2; true'
PATH="$b:$PATH" OMAMOBILE_PRIVACY_ROOT=$r bash libexec/privacy mic-on > /dev/null 2> "$tmp/err" & pid=$!
for _ in $(seq 50); do grep -q 'udevadm trigger' "$log" && break; sleep 0.1; done
kill -TERM "$pid"; rc=0; wait "$pid" || rc=$?
[[ $rc == 1 && $(cat "$tmp/err") == *"stopped in the middle: the microphone is left off"* && -e $state/mic ]] \
  || die "a stopped mic-on fails closed (rc $rc: $(cat "$tmp/err"))"
grep -cx "chmod 600 $r/dev/snd/pcmC0D8c" "$log" >/dev/null || die "a stopped mic-on locks the nodes"
grep -c 'try-restart' "$log" >/dev/null && die "a stopped mic-on restarts no audio"
cp "$b/udevadm.keep" "$b/udevadm"

# --- mic-off refused while a Google UCM profile has an unguarded Mic
reset
mkdir -p "$r/usr/share/alsa/ucm2/Google/cheetah"
printf '# guarded by /var/lib/omamobile/privacy/mic (a comment only)\nSectionDevice."Mic" { Value { CapturePCM "hw:0,8" } }\n' > "$r/usr/share/alsa/ucm2/Google/cheetah/HiFi.conf"
rc=0; err=$(run mic-off 2>&1) || rc=$?
[[ $rc == 3 && $err == *"update omamobile-audio first"*"/usr/share/alsa/ucm2/Google/cheetah/HiFi.conf"* ]] \
  || die "an unguarded UCM Mic refuses mic-off (rc $rc: $err)"
[[ ! -e $state/mic && ! -s $log ]] || die "a refused mic-off changes nothing"
rm -r "$r/usr/share/alsa/ucm2/Google/cheetah"

# --- camera-off: video4linux (subdevs too) and media nodes, locked here as well; the codec stays open
codec() { # video0 is the codec: its device's parent has the s5p-mfc driver; video2 by name
  mkdir -p "$r/sys/devices/platform/mfc/sub" "$r/sys/bus/platform/drivers/s5p-mfc" "$r/sys/class/video4linux/video0" "$r/sys/class/video4linux/video2"
  ln -s "$r/sys/bus/platform/drivers/s5p-mfc" "$r/sys/devices/platform/mfc/driver"
  ln -s "$r/sys/devices/platform/mfc/sub" "$r/sys/class/video4linux/video0/device"
  echo s5p-mfc-enc > "$r/sys/class/video4linux/video2/name"
}
reset; codec
touch "$r/dev/video0" "$r/dev/video1" "$r/dev/video2" "$r/dev/media0" "$r/dev/v4l-subdev0"
printf '%s\n' "$r/dev/video1" "$r/dev/media0" > "$tmp/udev-locks"
holder 400 decoder /dev/video0
holder 500 camapp /dev/video1
out=$(run camera-off) || die "camera-off succeeds"
[[ $(cat "$state/camera") == off ]] || die "camera-off writes the state file"
grep -c 'monitor.v4l2 = disabled' "$dropin/90-omamobile-privacy-camera.conf" >/dev/null || die "the camera drop-in turns the V4L2 monitor off"
grep -cx 'udevadm trigger --action=change --subsystem-match=video4linux --subsystem-match=media' "$log" >/dev/null || die "udev re-applies the rule to video4linux and media"
grep -cx "setfacl -b $r/dev/video1" "$log" >/dev/null || die "a camera node's ACL is cleared"
grep -cx "chmod 600 $r/dev/v4l-subdev0" "$log" >/dev/null || die "a subdev the rule missed is locked here"
grep -cx "chown root:root $r/dev/media0" "$log" >/dev/null || die "a media node is set root:root here"
grep -c "/dev/video[02]$" "$log" >/dev/null && die "the codec (by driver or by name) is never touched"
grep -cx 'kill -TERM 500' "$log" >/dev/null || die "a camera holder gets TERM"
grep -c 'kill -TERM 400' "$log" >/dev/null && die "the decoder is left alone"
reset
touch "$r/dev/video1"; printf '%s\n' "$r/dev/video1" > "$tmp/udev-locks"; touch "$tmp/stubborn"; holder 500 camapp /dev/video1
rc=0; err=$(run camera-off 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"still open by: camapp (500)"* ]] || die "a camera holder that stays fails camera-off by name (rc $rc: $err)"
reset; codec; printf '%s\n' "$r/dev/video1" "$r/dev/media0" "$r/dev/v4l-subdev0" > "$tmp/udev-locks"
run camera-off >/dev/null || die "camera-off before camera-on"
out=$(run camera-on) || die "camera-on succeeds"
[[ ! -e $state/camera && ! -e $dropin/90-omamobile-privacy-camera.conf ]] || die "camera-on removes the file and the drop-in"
rm -f "$r"/dev/video* "$r"/dev/media* "$r"/dev/v4l-subdev*

for bad in mic camera mic-of 'mic-off x' camera-offx MIC-OFF; do
  reset
  if run "$bad" >/dev/null 2>&1; then die "accepted: '$bad'"; fi
  [[ ! -s $log ]] || die "a refused argument changed something: '$bad'"
done
echo ok
