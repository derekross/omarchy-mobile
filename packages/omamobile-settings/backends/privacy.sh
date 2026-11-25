#!/bin/bash
# SPDX-License-Identifier: MIT
# Microphone and camera access for the Settings app's Security & privacy page. Prints one line of JSON.
#   privacy.sh get
#     {"switchable":true,"mic":"on","camera":"off","cameras":0}
#     switchable: omamobile-shell's omamobile-privacy@.service is installed and its helper knows mic-off (an
#     older shell has the unit for NFC only); mic and camera: "off" while
#     /var/lib/omamobile/privacy/<name> exists (off totally), else "on"; cameras: how many video4linux devices
#     other than the video codec (driver s5p-mfc) exist now, so the page can say no camera works yet.
#   privacy.sh set mic|camera on|off
#     omamobile-privacy@<name>-<on|off>.service as root (omamobile-shell's polkit rule 50-omamobile-privacy.rules
#     asks for the owner's PIN both ways through the shell's polkit prompt), then the get answer. A cancelled or
#     unanswered PIN gives {"error":"not changed: the PIN was not entered",...} with the state read again; a unit
#     that failed gives its reason when it is one the helper prints (an app still holding the microphone, an
#     omamobile-audio without the microphone guard).
# While off, no app can open a capture PCM (built-in, USB, dock): omamobile-shell's udev rule makes them root's.
# Bluetooth headset microphones are cut only through WirePlumber (A2DP only), best effort; the page says so.
# The test runs a copy of this script with `fake` set to a scratch root for /var/lib, /usr/lib and /sys, and a stub
# systemctl on PATH; `set` then also writes the scratch state the root helper would. Nothing in the environment
# sets it.
set -euo pipefail
export LC_ALL=C
verb=${1:-}; key=${2:-}; value=${3:-}
fail() { printf '{"error":"%s"}\n' "$1"; exit 2; }
fake=''
dir=$fake/var/lib/omamobile/privacy
unit=$fake/usr/lib/systemd/system/omamobile-privacy@.service
helper=$fake/usr/lib/omamobile-shell/privacy

state_of() { [[ -e $dir/$1 ]] && echo off || echo on; }

# video4linux devices that are not the codec: a camera driver that has landed
cameras() {
  local n=0 d drv
  for d in "$fake"/sys/class/video4linux/*; do
    [[ -e $d ]] || continue
    drv=$(readlink "$d/device/driver" 2>/dev/null) || drv=''
    [[ ${drv##*/} == s5p-mfc* ]] && continue
    n=$((n + 1))
  done
  echo "$n"
}

switchable() { [[ -f $unit && -r $helper ]] && grep -c '^mic-off)' "$helper" >/dev/null; }

get() {
  local sw=false
  switchable && sw=true
  printf '{"switchable":%s,"mic":"%s","camera":"%s","cameras":%s}\n' "$sw" "$(state_of mic)" "$(state_of camera)" "$(cameras)"
}

case $verb in
get)
  (( $# == 1 )) || fail "usage: get"
  get ;;
set)
  (( $# == 3 )) && [[ $key == mic || $key == camera ]] || fail "usage: set mic|camera on|off"
  [[ $value == on || $value == off ]] || fail "bad value"
  switchable || fail "omamobile-shell has no microphone or camera switch here"
  [[ $key == mic ]] && name=microphone || name=camera
  setfail() { local st; st=$(get); printf '{"error":"%s",%s\n' "$1" "${st#\{}"; exit 2; }
  # systemctl waits for the owner's PIN (polkit AUTH_ADMIN_KEEP, the shell's PIN pad); the unit's own limit is 60 s
  # once it starts, so 122 s is the backstop, as on the firewall and NFC switches; the app's runner kills a set at 160 s.
  rc=0
  since=@$(date +%s)
  err=$(timeout 122 systemctl start "omamobile-privacy@$key-$value.service" 2>&1 >/dev/null) || rc=$?
  if (( rc != 0 )); then
    if [[ $err == *'Access denied'* || $err == *'nteractive authentication'* || $rc == 124 ]]; then
      setfail "not changed: the PIN was not entered"
    fi
    # the helper's own reasons are in the journal (this run only), not here: name the two the owner can act on
    why=$(timeout 5 journalctl -q -o cat --since "$since" -u "omamobile-privacy@$key-$value.service" 2>/dev/null) || why=''
    case $why in
      *'update omamobile-audio first'*) setfail "not changed: update omamobile-audio first (its microphone guard is missing)" ;;
      *'still open by:'*) why=${why##*still open by: }; why=${why%%$'\n'*}; why=${why//[^a-zA-Z0-9 ()._-]/}
        setfail "the $name is off, but an app still had it open and would not stop: $why" ;;
    esac
    setfail "could not turn the $name $value"
  fi
  if [[ -n $fake ]]; then
    if [[ $value == off ]]; then mkdir -p "$dir"; echo off > "$dir/$key"; else rm -f "$dir/$key"; fi
  fi
  st=$(get)
  [[ $st == *"\"$key\":\"$value\""* ]] || setfail "the $name did not turn $value"
  printf '%s\n' "$st" ;;
*) fail "usage: get|set mic|camera on|off" ;;
esac
