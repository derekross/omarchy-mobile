#!/bin/bash
# SPDX-License-Identifier: MIT
# Lock screen and history settings for the Settings app's Notifications page. Prints one line of JSON.
#   notifications.sh get
#       {"lock":{"available":true,"hide":false,"keypad":true},"history":{"available":true,"count":3}}
#   notifications.sh set lockhide on|off
#       Omarchy's lock-hide-notification-text toggle, written only through `omarchy-toggle` and read back with
#       `omarchy-toggle-enabled`. The phone's lock screen (LockGlance, omamobile patch 0023) then shows the app name
#       and "Unlock to read" instead of the text, and LockMedia hides the track title. It is read only while the
#       keypad lock is on (the lock-keypad toggle), so "keypad" is reported too. Answers like get.
#   notifications.sh clear
#       Forgets every stored notification (on screen and history) through the notification service's own
#       `forget <key>` call, one key at a time; the service rewrites its files itself, so nothing is written here.
#       It cannot be undone. Answers like get, the count read back after; an "error" when some are still there.
# "lock" is {"available":false} when omarchy-toggle is missing or the installed lock screen does not read the toggle.
# "history" is {"available":false} when there is no shell or its service has no `forget`. A call that timed out
# gives {"available":true,"count":N,"error":"...did not answer in time"}. Keys come from the service's own
# live.json and history.json (read only) and must match the service's key pattern. Every call runs under `timeout`.
# The environment may hold stand-ins for omarchy-shell, omarchy-toggle and omarchy-toggle-enabled first on PATH
# (tests); HOME is where the files are read, OMARCHY_PATH where the lock screen's QML is looked for.
set -euo pipefail
set +x
verb=${1:-}; key=${2:-}; value=${3:-}
usage="usage: get | set lockhide on|off | clear"
fail() { printf '{"error":"%s"}\n' "$1"; exit 2; }
case $verb in
  get | clear) [[ $# -eq 1 ]] || fail "$usage" ;;
  set) [[ $# -eq 3 && $key == lockhide && ( $value == on || $value == off ) ]] || fail "$usage" ;;
  *) fail "$usage" ;;
esac
export OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}
have() { command -v "$1" >/dev/null 2>&1; }
flag=lock-hide-notification-text
statedir=$HOME/.local/state/omarchy/notifications
glance=$OMARCHY_PATH/shell/plugins/lock/LockGlance.qml

lock_json() {
  if ! have omarchy-toggle || ! have omarchy-toggle-enabled || ! grep -qF "$flag" "$glance" 2>/dev/null; then
    printf '{"available":false}'; return
  fi
  local hide=false keypad=false
  timeout -k 1 3 omarchy-toggle-enabled "$flag" && hide=true
  timeout -k 1 3 omarchy-toggle-enabled lock-keypad && keypad=true
  printf '{"available":true,"hide":%s,"keypad":%s}' "$hide" "$keypad"
}

# The stored keys, one per line, unique: live.json (on screen) then history.json. Only keys the service accepts.
# Fails (status 1) when python cannot run; a missing, empty or unreadable file holds no keys (the service reads it so).
keys() {
  python3 -I - "$statedir/live.json" "$statedir/history.json" <<'PY'
import json, re, sys
seen = []
for path in sys.argv[1:]:
    try:
        with open(path) as f:
            rows = json.load(f)
    except (OSError, ValueError):
        continue
    if not isinstance(rows, list):
        continue
    for row in rows:
        k = row.get("key") if isinstance(row, dict) else None
        if isinstance(k, str) and re.fullmatch(r"[A-Za-z0-9_-]{1,120}", k) and k not in seen:
            seen.append(k)
print("\n".join(seen))
PY
}
# the number of stored keys, or nothing when they cannot be read
count() { local k; k=$(keys) || return 1; [[ -z $k ]] && echo 0 || grep -c . <<<"$k"; }

# 0: the service answered ok; 1: no shell or no forget; 2: timed out
forget() {
  local v rc=0
  # </dev/null: a fallback client that reads stdin must not eat the clear loop's list of keys
  v=$(timeout -k 1 3 omarchy-shell notifications forget "$1" </dev/null 2>&1) || rc=$?
  if ((rc == 124 || rc == 137)) || [[ $v == *"not responding"* ]]; then return 2; fi
  [[ ${v%%$'\n'*} == ok ]] && return 0
  return 1
}
# A well-formed key that is not stored: the service answers ok and changes nothing (Service.qml forgetNotification).
probe_key=omamobile-settings-probe   # the service makes keys "n" + base36 (nextKey): never with a dash
history_ok() { have omarchy-shell || return 1; forget "$probe_key"; }

hist_json() {
  local rc=0
  history_ok || rc=$?
  case $rc in
    0) if n=$(count); then printf '{"available":true,"count":%s' "$n"
       else printf '{"available":true,"error":"the stored notifications could not be read"'; fi ;;
    2) printf '{"available":true,"error":"the notification service did not answer in time"}'; return ;;
    *) printf '{"available":false}'; return ;;
  esac
  printf '}'
}

err='' derr=''
if [[ $verb == set ]]; then
  if [[ $(lock_json) == '{"available":false}' ]]; then
    err="this lock screen has no hide-text setting"
  else
    timeout -k 1 3 omarchy-toggle "$flag" "$value" >/dev/null 2>&1 || true
    want=false; [[ $value == on ]] && want=true
    [[ $(lock_json) == *"\"hide\":$want"* ]] || err="the lock screen setting did not change"
  fi
elif [[ $verb == clear ]]; then
  rc=0; history_ok || rc=$?
  case $rc in
    0)
      # The runner kills a clear at 90 s. The deadline counts from the script's start (SECONDS), so the probe forget,
      # the two key reads, dismissAll and the 0.5 s sleep are inside it, and so is every re-forget. Each call is
      # `timeout -k 1 3`: 4 s at worst. Worst case, every call at its timeout: 55 s, + 4 s for the forget running at
      # the deadline, + 4 s for a re-forget started just before it, + 0.3 s and 1.5 s of polls, + lock_json 8 s,
      # + hist_json 4 s, + about 0.1 s per python read (up to 9): about 78 s, so 12 s to spare.
      deadline=55
      # the stored keys before dismissAll and after it: cards it moves to history (written a quarter second later,
      # sometimes later still) are in the first list even when the move lands after the second
      if ! before=$(keys); then err="the stored notifications could not be read"
      else
        # cards on screen first, as the shade's Clear all does: transient ones are in no file, so a dismissAll that
        # did not answer ok is an error of its own (the stored ones are still forgotten)
        d=$(timeout -k 1 3 omarchy-shell notifications dismissAll </dev/null 2>/dev/null) || d=''
        [[ ${d%%$'\n'*} == ok ]] || derr="the notification service did not clear the notifications on screen"
        sleep 0.5
        if ! after=$(keys); then err="the stored notifications could not be read"
        else
          snap=$(printf '%s\n%s\n' "$before" "$after" | awk 'NF && !seen[$0]++')
          while IFS= read -r k; do
            [[ -n $k ]] || continue
            ((SECONDS < deadline)) || { err="clearing took too long; some notifications are still stored"; break; }
            rc=0; forget "$k" || rc=$?
            case $rc in 0) ;; 2) err="the notification service did not answer in time"; break ;;
              *) err="the notification service stopped answering"; break ;; esac
          done <<<"$snap"
          # only what was there when the clear started counts: a notification that arrives meanwhile is not a
          # failure. A key that is back (a late history write of a dismissed card) is forgotten again.
          if [[ -z $err ]]; then
            left=1 again=0
            sleep 0.3   # the service saves a quarter second after a forget: don't take keys just forgotten for leftovers
            for _ in 1 2 3 4 5 6; do
              now=$(keys) || break
              back=$(comm -12 <(sort <<<"$snap") <(sort <<<"$now") | grep . || true)
              left=$(grep -c . <<<"$back" || true)
              ((left == 0)) && break
              if ((!again && SECONDS < deadline)); then
                again=1
                while IFS= read -r k; do
                  ((SECONDS < deadline)) || break
                  [[ -z $k ]] || forget "$k" || break
                done <<<"$back"
              fi
              sleep 0.25
            done
            ((left == 0)) || err="some notifications are still stored"
          fi
        fi
      fi ;;
    2) err="the notification service did not answer in time" ;;
    *) err="the notification service cannot forget notifications" ;;
  esac
fi
out='{"lock":'"$(lock_json)"',"history":'"$(hist_json)"
[[ -z $err ]] && err=$derr
[[ -n $err ]] && out+=',"error":"'"$err"'"'
# the one error a later read can make stale: stored notifications that a poll then finds gone
[[ $err == "some notifications are still stored" ]] && out+=',"still_stored":true'
printf '%s}\n' "$out"
