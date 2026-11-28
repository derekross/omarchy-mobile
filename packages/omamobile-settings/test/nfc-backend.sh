#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/nfc.sh against a scratch root (a copy of the script with FAKE set) and a scratch HOME, with stub
# systemctl and pw-play on PATH: no unit is started, no sound plays, nothing real is read or written.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
root=$tmp/root
sed "s|^FAKE = ''\$|FAKE = '$root'|" "$src/backends/nfc.sh" > "$tmp/nfc.sh"
grep -q "^FAKE = '$root'" "$tmp/nfc.sh"
mkdir -p "$tmp/bin" "$tmp/home/.config" "$root"
cat > "$tmp/bin/systemctl" <<STUB
#!/bin/sh
echo "systemctl \$*" >> "$tmp/log"
[ -e "$tmp/deny" ] && { echo "Failed to start: Access denied" >&2; exit 4; }
exit 0
STUB
cat > "$tmp/bin/pw-play" <<STUB
#!/bin/sh
echo "pw-play \$*" >> "$tmp/log"
STUB
chmod 755 "$tmp/bin/systemctl" "$tmp/bin/pw-play"
export HOME=$tmp/home XDG_CONFIG_HOME=$tmp/home/.config
run() { PATH="$tmp/bin:$PATH" bash "$tmp/nfc.sh" "$@" || true; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }
conf=$XDG_CONFIG_HOME/omamobile/nfc.json
sounds=$XDG_CONFIG_HOME/omamobile/sounds

# no NFC at all
eq "$(run get)" '{"available":false,"on":false,"switchable":false,"sound":true,"custom":false}'
eq "$(run set nfc on)" '{"error":"this phone has no NFC"}'
# an NFC switch, unblocked; omamobile-shell's unit missing
mkdir -p "$root/sys/class/rfkill/rfkill3"; echo nfc > "$root/sys/class/rfkill/rfkill3/type"; echo 0 > "$root/sys/class/rfkill/rfkill3/soft"
mkdir -p "$root/sys/class/rfkill/rfkill0"; echo wlan > "$root/sys/class/rfkill/rfkill0/type"; echo 1 > "$root/sys/class/rfkill/rfkill0/soft"
eq "$(run get)" '{"available":true,"on":true,"switchable":false,"sound":true,"custom":false}'
eq "$(run set nfc off)" '{"error":"omamobile-shell has no NFC switch here"}'
[[ ! -e $tmp/log ]] || { echo "FAIL: systemctl ran without the unit" >&2; exit 1; }
mkdir -p "$root/usr/lib/systemd/system"; : > "$root/usr/lib/systemd/system/omamobile-privacy@.service"
# off and on through the units
eq "$(run set nfc off)" '{"available":true,"on":false,"switchable":true,"sound":true,"custom":false}'
eq "$(cat "$tmp/log")" 'systemctl start omamobile-privacy@nfc-off.service'
eq "$(cat "$root/var/lib/omamobile/privacy/nfc")" off
eq "$(run set nfc on)" '{"available":true,"on":true,"switchable":true,"sound":true,"custom":false}'
# off totally with the switch blocked counts as off, and stays available even without a switch
echo 1 > "$root/sys/class/rfkill/rfkill3/soft"
eq "$(run get)" '{"available":true,"on":false,"switchable":true,"sound":true,"custom":false}'
echo 0 > "$root/sys/class/rfkill/rfkill3/soft"
# a cancelled PIN changes nothing and says so, with the state read again
touch "$tmp/deny"
eq "$(run set nfc off)" '{"available":true,"on":true,"switchable":true,"sound":true,"custom":false,"error":"not changed: the PIN was not entered"}'
[[ ! -e $root/var/lib/omamobile/privacy/nfc ]] || { echo "FAIL: a denied set changed the state" >&2; exit 1; }
rm "$tmp/deny"
for bad in 'set nfc maybe' 'set nfc' 'set wifi on' 'set nfc on x' 'nonsense' 'get x' 'sound' 'sound loud' 'sound on x'; do
  # shellcheck disable=SC2086
  out=$(run $bad); [[ $out == '{"error":'* ]] || { echo "FAIL: accepted: $bad ($out)" >&2; exit 1; }
done

# the sound switch writes nfc.json and keeps other keys
mkdir -p "${conf%/*}"; echo '{"file":"/nope.ogg","other":1}' > "$conf"
eq "$(run sound off)" '{"available":true,"on":true,"switchable":true,"sound":false,"custom":false}'
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d=={"file":"/nope.ogg","other":1,"sound":False}, d' "$conf"
eq "$(run sound on)" '{"available":true,"on":true,"switchable":true,"sound":true,"custom":false}'
echo 'not json' > "$conf"
eq "$(run get)" '{"available":true,"on":true,"switchable":true,"sound":true,"custom":false}'
eq "$(run sound off)" '{"available":true,"on":true,"switchable":true,"sound":false,"custom":false}'
echo '{"sound":"yes"}' > "$conf"
eq "$(run get)" '{"available":true,"on":true,"switchable":true,"sound":true,"custom":false}'

echo "{}" > "$conf"
# import: nothing staged, a 1 s WAV, a 3 s WAV, a file that isn't a sound, one too big
eq "$(run sound import)" '{"error":"no sound was picked"}'
wav() { python3 -c 'import sys,wave; w=wave.open(sys.argv[1],"wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000); w.writeframes(b"\0\0"*int(8000*float(sys.argv[2]))); w.close()' "$@"; }
mkdir -p "$sounds"
wav "$sounds/.import" 3
eq "$(run sound import)" '{"error":"that sound is longer than 2 seconds"}'
[[ ! -e $sounds/.import ]] || { echo "FAIL: a refused sound was left staged" >&2; exit 1; }
echo 'hello' > "$sounds/.import"
eq "$(run sound import)" '{"error":"that file isn'"'"'t a sound this phone can play"}'
head -c 3000000 /dev/zero > "$sounds/.import"
eq "$(run sound import)" '{"error":"that file is too big for a tag sound"}'
ln -s /etc/hostname "$sounds/.import"
eq "$(run sound import)" '{"error":"that file isn'"'"'t a sound this phone can play"}'
[[ ! -e $sounds/.import && ! -L $sounds/.import ]] || { echo "FAIL: a symlink was left staged" >&2; exit 1; }
wav "$sounds/.import" 1
eq "$(run sound import)" '{"available":true,"on":true,"switchable":true,"sound":true,"custom":true}'
[[ -f $sounds/nfc-tag && ! -e $sounds/.import ]] || { echo "FAIL: the sound was not taken" >&2; exit 1; }
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d=={"file":sys.argv[2]}, d' "$conf" "$sounds/nfc-tag"
: > "$tmp/log"
run sound test >/dev/null
eq "$(cat "$tmp/log")" "pw-play --media-role Notification -- $sounds/nfc-tag"
eq "$(run sound default)" '{"available":true,"on":true,"switchable":true,"sound":true,"custom":false}'
[[ ! -e $sounds/nfc-tag ]] || { echo "FAIL: the old sound was kept" >&2; exit 1; }
: > "$tmp/log"
run sound test >/dev/null
eq "$(cat "$tmp/log")" ''
eq "$(run sound test)" '{"error":"the built-in chirp is missing (it comes with omamobile-shell)"}'
mkdir -p "$root/usr/share/omamobile/sounds"; wav "$root/usr/share/omamobile/sounds/nfc-detect.wav" 0.3
run sound test >/dev/null
eq "$(cat "$tmp/log")" "pw-play --media-role Notification -- $root/usr/share/omamobile/sounds/nfc-detect.wav"
printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/pw-play"
eq "$(run sound test)" '{"error":"the sound could not be played"}'
# a directory where the staged copy goes is an error, not a crash
mkdir -p "$sounds/.import"
eq "$(run sound import)" '{"error":"cannot remove .import in ~/.config/omamobile/sounds"}'
rmdir "$sounds/.import"
echo "ok - nfc backend"
