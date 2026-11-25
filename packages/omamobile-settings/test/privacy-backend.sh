#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/privacy.sh against a scratch root (a copy of the script with `fake` set), with stub systemctl and
# journalctl on PATH: no unit is started, nothing real is read or written.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
root=$tmp/root
sed "s|^fake=''\$|fake='$root'|" "$src/backends/privacy.sh" > "$tmp/privacy.sh"
grep -c "^fake='$root'" "$tmp/privacy.sh" >/dev/null
mkdir -p "$tmp/bin" "$root"
cat > "$tmp/bin/systemctl" <<STUB
#!/bin/sh
echo "systemctl \$*" >> "$tmp/log"
[ -e "$tmp/deny" ] && { echo "Failed to start: Access denied" >&2; exit 4; }
[ -e "$tmp/unitfail" ] && { echo "Job failed" >&2; exit 1; }
exit 0
STUB
cat > "$tmp/bin/journalctl" <<STUB
#!/bin/sh
cat "$tmp/journal" 2>/dev/null
STUB
chmod 755 "$tmp/bin/systemctl" "$tmp/bin/journalctl"
run() { PATH="$tmp/bin:$PATH" bash "$tmp/privacy.sh" "$@" || true; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }

# no omamobile-shell switch
eq "$(run get)" '{"switchable":false,"mic":"on","camera":"on","cameras":0}'
eq "$(run set mic off)" '{"error":"omamobile-shell has no microphone or camera switch here"}'
# an older shell: the unit and a helper for NFC only
mkdir -p "$root/usr/lib/systemd/system" "$root/usr/lib/omamobile-shell"; : > "$root/usr/lib/systemd/system/omamobile-privacy@.service"
printf 'case $1 in\nnfc-off)\n  ;;\nesac\n' > "$root/usr/lib/omamobile-shell/privacy"
eq "$(run get)" '{"switchable":false,"mic":"on","camera":"on","cameras":0}'
eq "$(run set camera off)" '{"error":"omamobile-shell has no microphone or camera switch here"}'
[[ ! -e $tmp/log ]] || { echo "FAIL: systemctl ran without the switch" >&2; exit 1; }
printf 'case $1 in\nnfc-off)\n  ;;\nmic-off)\n  ;;\nesac\n' > "$root/usr/lib/omamobile-shell/privacy"
# the codec is not a camera; any other video4linux device is
mkdir -p "$root/sys/class/video4linux/video0/device" "$root/sys/bus/platform/drivers/s5p-mfc"
ln -s "$root/sys/bus/platform/drivers/s5p-mfc" "$root/sys/class/video4linux/video0/device/driver"
eq "$(run get)" '{"switchable":true,"mic":"on","camera":"on","cameras":0}'
# off and on through the units
eq "$(run set mic off)" '{"switchable":true,"mic":"off","camera":"on","cameras":0}'
eq "$(tail -n 1 "$tmp/log")" "systemctl start omamobile-privacy@mic-off.service"
eq "$(run set camera off)" '{"switchable":true,"mic":"off","camera":"off","cameras":0}'
eq "$(tail -n 1 "$tmp/log")" "systemctl start omamobile-privacy@camera-off.service"
eq "$(run set mic on)" '{"switchable":true,"mic":"on","camera":"off","cameras":0}'
eq "$(tail -n 1 "$tmp/log")" "systemctl start omamobile-privacy@mic-on.service"
# a cancelled PIN: nothing changes, the state is read again
touch "$tmp/deny"
eq "$(run set camera on)" '{"error":"not changed: the PIN was not entered","switchable":true,"mic":"on","camera":"off","cameras":0}'
rm "$tmp/deny"
# the helper's reasons, from its journal
touch "$tmp/unitfail"
echo 'not changed: update omamobile-audio first (no microphone guard in /usr/share/alsa/ucm2/Google/x/HiFi.conf)' > "$tmp/journal"
eq "$(run set mic off)" '{"error":"not changed: update omamobile-audio first (its microphone guard is missing)","switchable":true,"mic":"on","camera":"off","cameras":0}'
printf 'stopping rec (9)\nstill open by: rec"x (9)\n' > "$tmp/journal"
eq "$(run set mic off)" '{"error":"the microphone is off, but an app still had it open and would not stop: recx (9)","switchable":true,"mic":"on","camera":"off","cameras":0}'
: > "$tmp/journal"
eq "$(run set camera on)" '{"error":"could not turn the camera on","switchable":true,"mic":"on","camera":"off","cameras":0}'
rm "$tmp/unitfail"
# a camera driver that landed is counted
mkdir -p "$root/sys/class/video4linux/video1/device" "$root/sys/bus/platform/drivers/csis"
ln -s "$root/sys/bus/platform/drivers/csis" "$root/sys/class/video4linux/video1/device/driver"
eq "$(run get)" '{"switchable":true,"mic":"on","camera":"off","cameras":1}'
# refused input never reaches systemctl
: > "$tmp/log"
for a in "set nfc off" "set mic maybe" "set mic" "get x" "frob" "set camera on extra"; do
  out=$(run $a); [[ $out == '{"error":'* ]] || { echo "FAIL: accepted: $a" >&2; exit 1; }
done
[[ ! -s $tmp/log ]] || { echo "FAIL: a refused set ran systemctl" >&2; exit 1; }
echo "ok - privacy backend"
