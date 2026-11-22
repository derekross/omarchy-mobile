#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/notifications.sh on a scratch HOME with stand-ins for omarchy-shell (a notification service that forgets
# keys from its files, as Service.qml forgetNotification does), omarchy-toggle and omarchy-toggle-enabled (copies of
# Omarchy's own logic). Nothing real is touched: every run is env -i, PATH holds only the stubs and /usr/bin, HOME and
# OMARCHY_PATH are scratch.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.local/state/omarchy/notifications" "$tmp/o/shell/plugins/lock" "$tmp/empty"
export T=$tmp
st=$tmp/home/.local/state/omarchy/notifications
echo 'FileView { path: home + "/.local/state/omarchy/toggles/lock-hide-notification-text" }' > "$tmp/o/shell/plugins/lock/LockGlance.qml"
cat > "$tmp/bin/omarchy-toggle" <<'EOT'
#!/bin/bash
[[ -n ${TOGGLESTUCK:-} ]] && exit 0
f=$HOME/.local/state/omarchy/toggles/$1
case ${2:-toggle} in on) mkdir -p "${f%/*}"; touch "$f" ;; off) rm -f "$f" ;; *) exit 1 ;; esac
EOT
cat > "$tmp/bin/omarchy-toggle-enabled" <<'EOT'
#!/bin/bash
[[ -f "$HOME/.local/state/omarchy/toggles/$1" ]]
EOT
cat > "$tmp/bin/omarchy-shell" <<'EOT'
#!/bin/bash
echo "$*" >> "$T/calls"
[[ -n ${HANG:-} ]] && sleep 10
[[ -n ${DOWN:-} ]] && { echo "Omarchy shell is not running" >&2; exit 1; }
[[ $1 == notifications ]] || exit 1
case $2 in
  forget)
    [[ -n ${NOFORGET:-} ]] && { echo "Function not found."; exit 0; }
    [[ $3 =~ ^[A-Za-z0-9_-]{1,120}$ ]] || { echo none; exit 0; }
    [[ -n ${KEEP:-} && $3 == "$KEEP" ]] && { echo ok; exit 0; }
    [[ -n ${FAILAT:-} && $3 == "$FAILAT" ]] && { echo "Function not found."; exit 0; }
    [[ -n ${ARRIVE:-} && $3 == h1 ]] && python3 -I -c 'import json,sys; p=sys.argv[1]; r=json.load(open(p)); r.append({"key":"new9"}); json.dump(r,open(p,"w"))' "$HOME/.local/state/omarchy/notifications/history.json"
    d=$HOME/.local/state/omarchy/notifications
    for f in live.json history.json; do
      [[ -s $d/$f && -r $d/$f ]] || continue
      python3 -I -c 'import json,sys; p,k=sys.argv[1:]; r=json.load(open(p)); json.dump([x for x in r if not (isinstance(x,dict) and x.get("key")==k)],open(p,"w"))' "$d/$f" "$3"
    done
    echo ok
    [[ -n ${LATE:-} ]] && sleep 0.3   # a slow service: the loop is still running when the late history write lands
    exit 0 ;;
  dismissAll)
    [[ -n ${DISMISSFAIL:-} ]] && { echo "Function not found."; exit 0; }
    if [[ -n ${LATE:-} ]]; then
      # the card leaves live.json now and reaches history.json only 0.7 s later, after the backend's second read
      d=$HOME/.local/state/omarchy/notifications
      python3 -I -c 'import json,sys; p=sys.argv[1]; json.dump([x for x in json.load(open(p)) if x.get("key")!="card1"],open(p,"w"))' "$d/live.json"
      ( sleep 0.7; python3 -I -c 'import json,sys; p=sys.argv[1]; r=json.load(open(p)); r.append({"key":"card1"}); json.dump(r,open(p,"w"))' "$d/history.json" ) >/dev/null 2>&1 &
    fi
    echo ok ;;
  *) echo "Function not found." ;;
esac
EOT
chmod +x "$tmp/bin/"*
# the stubs' switches (HANG, DOWN, ...) are passed through by name; nothing else of this shell's environment reaches the backend
run() { env -i HOME="$tmp/home" PATH="$tmp/bin:/usr/bin" OMARCHY_PATH="$tmp/o" T="$T" HANG="${HANG:-}" DOWN="${DOWN:-}" NOFORGET="${NOFORGET:-}" \
  KEEP="${KEEP:-}" FAILAT="${FAILAT:-}" ARRIVE="${ARRIVE:-}" TOGGLESTUCK="${TOGGLESTUCK:-}" \
  DISMISSFAIL="${DISMISSFAIL:-}" LATE="${LATE:-}" /usr/bin/bash "$src/backends/notifications.sh" "$@" || true; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }
seed() {
  echo '[{"key":"live1","summary":"a"}]' > "$st/live.json"
  echo '[{"key":"h1"},{"key":"h2"},{"key":"live1"},{"key":"bad key"},{"key":"../x"},"junk",{"nokey":1}]' > "$st/history.json"
}

seed
eq "$(run get)" '{"lock":{"available":true,"hide":false,"keypad":false},"history":{"available":true,"count":3}}'
# the probe forget uses a key that is not stored: nothing changes
grep -q '"h1"' "$st/history.json"
# hide on and off, through omarchy-toggle, read back from the flag
touch "$tmp/home/.local/state/omarchy/toggles/lock-keypad" 2>/dev/null || { mkdir -p "$tmp/home/.local/state/omarchy/toggles"; touch "$tmp/home/.local/state/omarchy/toggles/lock-keypad"; }
eq "$(run set lockhide on)" '{"lock":{"available":true,"hide":true,"keypad":true},"history":{"available":true,"count":3}}'
[[ -f $tmp/home/.local/state/omarchy/toggles/lock-hide-notification-text ]]
eq "$(run set lockhide off)" '{"lock":{"available":true,"hide":false,"keypad":true},"history":{"available":true,"count":3}}'
[[ ! -e $tmp/home/.local/state/omarchy/toggles/lock-hide-notification-text ]]
# a toggle that does not take is an error with the state read
eq "$(TOGGLESTUCK=1 run set lockhide on)" '{"lock":{"available":true,"hide":false,"keypad":true},"history":{"available":true,"count":3},"error":"the lock screen setting did not change"}'
# a lock screen that does not read the flag: not offered, and set writes nothing
echo 'nothing' > "$tmp/o/shell/plugins/lock/LockGlance.qml"
eq "$(run set lockhide on)" '{"lock":{"available":false},"history":{"available":true,"count":3},"error":"this lock screen has no hide-text setting"}'
[[ ! -e $tmp/home/.local/state/omarchy/toggles/lock-hide-notification-text ]]
echo 'lock-hide-notification-text' > "$tmp/o/shell/plugins/lock/LockGlance.qml"
# clear forgets every valid key, on screen and in history, and reads the count back
: > "$tmp/calls"
eq "$(run clear)" '{"lock":{"available":true,"hide":false,"keypad":true},"history":{"available":true,"count":0}}'
for k in live1 h1 h2; do grep -qx "notifications forget $k" "$tmp/calls"; done
grep -qx 'notifications dismissAll' "$tmp/calls"
! grep -q 'forget bad\|forget \.\./x' "$tmp/calls" || { echo "FAIL: an invalid key was sent" >&2; exit 1; }
# a notification that arrives during the clear is not a failure; it stays and is counted
seed
eq "$(ARRIVE=1 run clear)" '{"lock":{"available":true,"hide":false,"keypad":true},"history":{"available":true,"count":1}}'
# a forget the service refuses stops the loop with an error
seed
eq "$(FAILAT=h1 run clear)" '{"lock":{"available":true,"hide":false,"keypad":true},"history":{"available":true,"count":2},"error":"the notification service stopped answering"}'
# an unreadable file holds no keys, as the service reads it (python itself failing is an error)
seed; chmod 000 "$st/history.json"
[[ $(id -u) == 0 ]] || eq "$(run get)" '{"lock":{"available":true,"hide":false,"keypad":true},"history":{"available":true,"count":1}}'
chmod 600 "$st/history.json"
# one the service keeps: an error, count read back
seed
eq "$(KEEP=h2 run clear)" '{"lock":{"available":true,"hide":false,"keypad":true},"history":{"available":true,"count":1},"error":"some notifications are still stored","still_stored":true}'
# a dismissAll that does not answer ok is an error, and the stored ones are still forgotten
seed
eq "$(DISMISSFAIL=1 run clear)" '{"lock":{"available":true,"hide":false,"keypad":true},"history":{"available":true,"count":0},"error":"the notification service did not clear the notifications on screen"}'
# a dismissed card whose history write lands late: it was in the list taken before dismissAll, so it is forgotten
# (again, once it is back) and the clear ends with nothing stored
seed; echo '[{"key":"card1"}]' > "$st/live.json"   # on screen only, not yet in history
eq "$(LATE=1 run clear)" '{"lock":{"available":true,"hide":false,"keypad":true},"history":{"available":true,"count":0}}'
sleep 0.5; grep -q '"card1"' "$st/history.json" && { echo "FAIL: the late card is still stored" >&2; exit 1; }
# empty or missing files count 0
: > "$st/live.json"; rm -f "$st/history.json"
eq "$(run get)" '{"lock":{"available":true,"hide":false,"keypad":true},"history":{"available":true,"count":0}}'
# a service without forget, or no shell: history not available, clear forgets nothing
seed; : > "$tmp/calls"
eq "$(NOFORGET=1 run clear)" '{"lock":{"available":true,"hide":false,"keypad":true},"history":{"available":false},"error":"the notification service cannot forget notifications"}'
! grep -v 'forget omamobile-settings-probe' "$tmp/calls" | grep -c . >/dev/null || { echo "FAIL: a call other than the probe reached a service without forget" >&2; exit 1; }
eq "$(DOWN=1 run get)" '{"lock":{"available":true,"hide":false,"keypad":true},"history":{"available":false}}'
# a hung service is cut off: available, count from the files, an error, and nothing forgotten
start=$SECONDS
: > "$tmp/calls"
eq "$(HANG=1 run clear)" '{"lock":{"available":true,"hide":false,"keypad":true},"history":{"available":true,"error":"the notification service did not answer in time"},"error":"the notification service did not answer in time"}'
(( SECONDS - start < 12 )) || { echo "FAIL: hung service not cut off" >&2; exit 1; }
! grep -v 'forget omamobile-settings-probe' "$tmp/calls" | grep -c . >/dev/null || { echo "FAIL: a call other than the probe reached a hung service" >&2; exit 1; }
# no tools at all
eq "$(env -i HOME="$tmp/home" PATH="$tmp/empty" OMARCHY_PATH="$tmp/o" /usr/bin/bash "$src/backends/notifications.sh" get)" '{"lock":{"available":false},"history":{"available":false}}'
# bad arguments run nothing
: > "$tmp/calls"
for args in "" "toggle" "set" "set lockhide" "set lockhide maybe" "set other on" "get x" "clear now" "set lockhide on x"; do
  # shellcheck disable=SC2086
  eq "$(run $args)" '{"error":"usage: get | set lockhide on|off | clear"}'
done
[[ ! -s $tmp/calls ]]
echo "notifications backend: ok"
