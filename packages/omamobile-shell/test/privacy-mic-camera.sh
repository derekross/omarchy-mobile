#!/bin/bash
# SPDX-License-Identifier: MIT
# libexec/privacy mic-off|mic-on|camera-off|camera-on in a scratch root: /dev
# holds plain files, /proc symlinks; udevadm, setfacl, systemctl, loginctl,
# kill, stat, chown and chmod are stubs that record what they were asked (stat
# answers from a table the stubs keep, as udev and chown would set it).
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
r=$tmp/root; b=$tmp/bin; log=$tmp/log; modes=$tmp/modes
mkdir -p "$b" "$r/dev/snd" "$r/proc" "$r/usr/share/alsa/ucm2/Google/husky"
die() { echo "FAIL: $1" >&2; [[ -f $log ]] && sed 's/^/  log: /' "$log" >&2; exit 1; }
stub() { printf '#!/bin/bash\n%s\n' "$2" > "$b/$1"; chmod 755 "$b/$1"; }
# the table: "<path> <uid:gid:mode>"; a node not in it is the session's (0:29:660 with an ACL)
stub stat 'f=${@: -1}; l=$(grep -F "$f " "'"$modes"'" | tail -n 1); echo "${l##* }"; [[ -n $l ]] || echo 0:29:660'
stub chown 'echo "chown $*" >> "'"$log"'"'
stub chmod 'echo "chmod $*" >> "'"$log"'"; [[ $1 == 600 ]] && echo "$2 0:0:600" >> "'"$modes"'"; true'
stub setfacl 'echo "setfacl $*" >> "'"$log"'"'
# getfacl: a named user entry while $tmp/aclstays exists (an ACL setfacl could not clear)
stub getfacl '[[ -f "'"$tmp"'/aclstays" ]] && echo "user:lef:rw-"; echo "user::rw-"; true'
# udev: the rule locks what the test lists in $tmp/udev-locks when it is triggered
stub udevadm 'echo "udevadm $*" >> "'"$log"'"; [[ $1 == trigger && -f "'"$tmp"'/udev-locks" ]] && sed "s/$/ 0:0:600/" "'"$tmp"'/udev-locks" >> "'"$modes"'"; true'
stub loginctl 'echo "1000 lef no active"; echo "0 root no active"'
# a restart of the user's audio closes PipeWire's capture (pid 100); pid 200 stays until it gets TERM
stub systemctl 'echo "systemctl $*" >> "'"$log"'"; [[ -f "'"$tmp"'/sysfail" ]] && exit 1; rm -rf "'"$r"'/proc/100"'
stub kill 'echo "kill $*" >> "'"$log"'"; [[ -f "'"$tmp"'/stubborn" || ( -f "'"$tmp"'/termproof" && $1 == -TERM ) ]] || rm -rf "'"$r"'/proc/${@: -1}"'
run() { PATH="$b:$PATH" OMAMOBILE_PRIVACY_ROOT=$r bash libexec/privacy "$@"; }
reset() { : > "$log"; : > "$modes"; rm -f "$tmp/udev-locks" "$tmp/stubborn" "$tmp/termproof" "$tmp/sysfail" "$tmp/aclstays"; rm -rf "$r/proc"/*; }
holder() { mkdir -p "$r/proc/$1/fd"; echo "$2" > "$r/proc/$1/comm"; ln -sf "$3" "$r/proc/$1/fd/7"; printf 'Uid:\t%s\t%s\n' "${4:-1000}" "${4:-1000}" > "$r/proc/$1/status"; }
guarded='SectionDevice."Speaker" {}
If.omamobile_privacy_mic { Condition { Type Path Path "/var/lib/omamobile/privacy/mic" Mode exists }
False { SectionDevice."Mic" { Value { CapturePCM "hw:0,8" } } } }'
printf '%s\n' "$guarded" > "$r/usr/share/alsa/ucm2/Google/husky/HiFi.conf"
touch "$r/dev/snd/pcmC0D8c" "$r/dev/snd/pcmC0D5p" "$r/dev/snd/pcmC1D0c" "$r/dev/snd/controlC0"
state=$r/var/lib/omamobile/privacy
dropin=$r/etc/wireplumber/wireplumber.conf.d

# --- mic-off: state, drop-in, udev, ACLs cleared, audio restarted, holders stopped
reset
printf '%s\n' "$r/dev/snd/pcmC0D8c" "$r/dev/snd/pcmC1D0c" > "$tmp/udev-locks"
holder 100 pipewire /dev/snd/pcmC0D8c
holder 200 arecord /dev/snd/pcmC1D0c
holder 300 pipewire /dev/snd/pcmC0D5p
out=$(run mic-off) || die "mic-off succeeds"
[[ $(cat "$state/mic") == off ]] || die "mic-off writes the state file"
grep -c 'a2dp_sink a2dp_source' "$dropin/90-omamobile-privacy-mic.conf" >/dev/null || die "the drop-in keeps Bluetooth to A2DP"
grep -c 'node.disabled = true' "$dropin/90-omamobile-privacy-mic.conf" >/dev/null || die "the drop-in hides ALSA inputs"
grep -c 'api.alsa.use-ucm = false' "$dropin/90-omamobile-privacy-mic.conf" >/dev/null || die "USB cards drop UCM while the mic is off"
grep -cx 'udevadm trigger --action=change --subsystem-match=sound' "$log" >/dev/null || die "udev re-applies the rule to sound"
grep -cx "setfacl -b $r/dev/snd/pcmC0D8c" "$log" >/dev/null || die "the built-in capture's ACL is cleared"
grep -cx "setfacl -b $r/dev/snd/pcmC1D0c" "$log" >/dev/null || die "a USB capture's ACL is cleared"
grep -c 'pcmC0D5p\|controlC0' "$log" >/dev/null && die "playback and the mixer are never touched"
grep -cx 'systemctl --user -M lef@ try-restart wireplumber.service pipewire.service' "$log" >/dev/null \
  || die "the user's WirePlumber and PipeWire restart"
grep -c -- '-M root@' "$log" >/dev/null && die "only users from uid 1000 are restarted"
grep -cx 'kill -TERM 200' "$log" >/dev/null || die "a process still holding a capture gets TERM"
grep -c 'kill -TERM 300' "$log" >/dev/null && die "a playback holder is left alone"
[[ $out == *"stopping arecord (200)"* && $out == *"The microphone is off"* ]] || die "mic-off says what it stopped: $out"

# a holder that won't go: mic-off fails and names it, the state stays off (the private side)
reset
printf '%s\n' "$r/dev/snd/pcmC0D8c" > "$tmp/udev-locks"
touch "$tmp/stubborn"; holder 200 recorder /dev/snd/pcmC0D8c
rc=0; err=$(run mic-off 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"still open by: recorder (200)"* ]] || die "a holder that stays fails mic-off by name (rc $rc: $err)"
[[ -e $state/mic ]] || die "a failed mic-off still leaves the microphone off"

# TERM ignored: KILL after the wait; an mmap left after close counts; a hostile name never picks a pid
reset
printf '%s\n' "$r/dev/snd/pcmC0D8c" > "$tmp/udev-locks"
touch "$tmp/termproof"
holder 200 stubborn /dev/snd/pcmC0D8c
mkdir -p "$r/proc/600"; printf 'x\n1 y' > "$r/proc/600/comm"; printf 'Uid:\t1000\t1000\n' > "$r/proc/600/status"
printf '7f00-7f10 rw-s 00000000 00:05 12 /dev/snd/pcmC0D8c\n' > "$r/proc/600/maps"
out=$(run mic-off) || die "mic-off succeeds once KILL stops what TERM did not"
grep -cx 'kill -TERM 200' "$log" >/dev/null && grep -cx 'kill -KILL 200' "$log" >/dev/null || die "TERM, then KILL"
grep -cx 'kill -TERM 600' "$log" >/dev/null || die "a holder by mapping alone is stopped too"
grep -c 'kill -[A-Z]* 1$' "$log" >/dev/null && die "a newline in a process name made the helper signal pid 1"
[[ $out == *"stopping x1y (600)"* ]] || die "a process name is shown cleaned: $out"

# a mapping of another node (video10, a file named like the node) is no holder of video1; nobody (65534) is a system process
reset
touch "$r/dev/video1"; printf '%s\n' "$r/dev/video1" > "$tmp/udev-locks"
mkdir -p "$r/proc/810" "$r/proc/820"; printf 'Uid:\t1000\t1000\n' | tee "$r/proc/810/status" > "$r/proc/820/status"
printf '7f00-7f10 rw-s 00000000 00:05 12 /dev/video10\n' > "$r/proc/810/maps"
printf '7f00-7f10 r--p 00000000 00:05 12 /home/x/dev/video1.mp4\n' > "$r/proc/820/maps"
holder 830 nobodyd /dev/video1 65534
rc=0; err=$(run camera-off 2>&1 >/dev/null) || rc=$?
grep -c 'kill .* 8[12]0$' "$log" >/dev/null && die "a look-alike mapping was taken for a holder"
grep -c 'kill .* 830$' "$log" >/dev/null && die "nobody (65534) was signalled"
[[ $rc == 1 && $err == *"still open by: nobodyd (830)"* ]] || die "nobody's holder is named (rc $rc: $err)"
rm -f "$r/dev/video1"

# a system process is never signalled: named, and mic-off fails
reset
printf '%s\n' "$r/dev/snd/pcmC0D8c" > "$tmp/udev-locks"
holder 700 sysrec /dev/snd/pcmC0D8c 0
rc=0; err=$(run mic-off 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"still open by: sysrec (700)"* ]] || die "a root holder fails mic-off by name (rc $rc: $err)"
grep -c 'kill .* 700' "$log" >/dev/null && die "a root process was signalled"

# a failed restart of the user's audio fails mic-off (PipeWire may still have the old profile)
reset
touch "$tmp/sysfail"
rc=0; err=$(run mic-off 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"could not restart the audio of lef"* ]] || die "a failed audio restart fails mic-off (rc $rc: $err)"

# an ACL that stays after setfacl fails mic-off and names the node
reset
printf '%s\n' "$r/dev/snd/pcmC0D8c" "$r/dev/snd/pcmC1D0c" > "$tmp/udev-locks"; touch "$tmp/aclstays"
rc=0; err=$(run mic-off 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"an ACL is still on /dev/snd/pcmC0D8c"* ]] || die "an ACL left fails mic-off (rc $rc: $err)"

# a failed udev trigger fails mic-on (the nodes would stay root's)
reset
stub udevadm 'echo "udevadm $*" >> "'"$log"'"; [[ $1 == trigger ]] && exit 1; true'
rc=0; err=$(run mic-on 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"udev could not re-apply"* ]] || die "a failed trigger fails mic-on (rc $rc: $err)"
grep -c 'try-restart wireplumber.service' "$log" >/dev/null || die "a failed trigger still restarts the audio (no off config left running)"
: > "$log"
rc=0; err=$(run camera-on 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"udev could not re-apply"* ]] || die "a failed trigger fails camera-on (rc $rc: $err)"
stub udevadm 'echo "udevadm $*" >> "'"$log"'"; [[ $1 == trigger && -f "'"$tmp"'/udev-locks" ]] && sed "s/$/ 0:0:600/" "'"$tmp"'/udev-locks" >> "'"$modes"'"; true'

# a node the rule didn't lock is locked here (mic: every capture is in scope)
reset
out=$(run mic-off) || die "mic-off without udev's lock still succeeds once it locks the nodes itself"
grep -cx "chmod 600 $r/dev/snd/pcmC0D8c" "$log" >/dev/null || die "an unlocked capture is set 0600 here"
grep -cx "chown root:root $r/dev/snd/pcmC1D0c" "$log" >/dev/null || die "an unlocked capture is set root:root here"

# --- mic-on: file and drop-in gone, udev again, audio restarted
reset
out=$(run mic-on) || die "mic-on succeeds"
[[ ! -e $state/mic && ! -e $dropin/90-omamobile-privacy-mic.conf ]] || die "mic-on removes the file and the drop-in"
grep -cx 'udevadm trigger --action=change --subsystem-match=sound' "$log" >/dev/null || die "mic-on re-applies udev"
grep -c 'try-restart wireplumber.service' "$log" >/dev/null || die "mic-on restarts the user's audio"
grep -c 'setfacl\|kill' "$log" >/dev/null && die "mic-on clears nothing and stops nothing"

# --- mic-off refused while a Google UCM profile has an unguarded Mic
reset
mkdir -p "$r/usr/share/alsa/ucm2/Google/cheetah"
printf '# guarded by /var/lib/omamobile/privacy/mic (a comment only)\nSectionDevice."Mic" { Value { CapturePCM "hw:0,8" } }\n' > "$r/usr/share/alsa/ucm2/Google/cheetah/HiFi.conf"
rc=0; err=$(run mic-off 2>&1) || rc=$?
[[ $rc == 3 && $err == *"update omamobile-audio first"*"/usr/share/alsa/ucm2/Google/cheetah/HiFi.conf"* ]] \
  || die "an unguarded UCM Mic refuses mic-off (rc $rc: $err)"
[[ ! -e $state/mic && ! -s $log ]] || die "a refused mic-off changes nothing"
rm -r "$r/usr/share/alsa/ucm2/Google/cheetah"

# --- camera-off: video4linux and media, only the nodes the rule locked (the codec stays open)
reset
touch "$r/dev/video0" "$r/dev/video1" "$r/dev/media0" "$r/dev/v4l-subdev0"
printf '%s\n' "$r/dev/video1" "$r/dev/media0" "$r/dev/v4l-subdev0" > "$tmp/udev-locks"
holder 400 decoder /dev/video0
holder 500 camapp /dev/video1
out=$(run camera-off) || die "camera-off succeeds"
[[ $(cat "$state/camera") == off ]] || die "camera-off writes the state file"
grep -c 'monitor.v4l2 = disabled' "$dropin/90-omamobile-privacy-camera.conf" >/dev/null || die "the camera drop-in turns the V4L2 monitor off"
grep -cx 'udevadm trigger --action=change --subsystem-match=video4linux --subsystem-match=media' "$log" >/dev/null || die "udev re-applies the rule to video4linux and media"
grep -cx "setfacl -b $r/dev/video1" "$log" >/dev/null || die "a camera node's ACL is cleared"
grep -c "/dev/video0" "$log" >/dev/null && die "the codec node (not locked by the rule) is never touched"
grep -c '^ch\(mod\|own\) .*/dev/' "$log" >/dev/null && die "camera-off sets no mode itself (the rule decides, so the codec stays open)"
grep -cx 'kill -TERM 500' "$log" >/dev/null || die "a camera holder gets TERM"
grep -c 'kill -TERM 400' "$log" >/dev/null && die "the decoder is left alone"
reset
touch "$r/dev/video1"; printf '%s\n' "$r/dev/video1" > "$tmp/udev-locks"; touch "$tmp/stubborn"; holder 500 camapp /dev/video1
rc=0; err=$(run camera-off 2>&1 >/dev/null) || rc=$?
[[ $rc == 1 && $err == *"still open by: camapp (500)"* ]] || die "a camera holder that stays fails camera-off by name (rc $rc: $err)"
reset
out=$(run camera-on) || die "camera-on succeeds"
[[ ! -e $state/camera && ! -e $dropin/90-omamobile-privacy-camera.conf ]] || die "camera-on removes the file and the drop-in"

for bad in mic camera mic-of 'mic-off x' camera-offx MIC-OFF; do
  reset
  if run "$bad" >/dev/null 2>&1; then die "accepted: '$bad'"; fi
  [[ ! -s $log ]] || die "a refused argument changed something: '$bad'"
done
echo ok
