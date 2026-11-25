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
#     omamobile-audio without the microphone guard, a switch the helper undid: "not changed").
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
  err=$(timeout 122 systemctl start "omamobile-privacy@$key-$value.service" 2>&1 >/dev/null) || rc=$?
  if (( rc != 0 )); then
    if [[ $err == *'Access denied'* || $err == *'nteractive authentication'* || $rc == 124 ]]; then
      setfail "not changed: the PIN was not entered"
    fi
    # the helper's own reasons are in the journal, not here: this run's only (its invocation id, so a clock step on
    # this RTC-less phone can't hide them); name the ones the owner can act on
    inv=$(timeout 5 systemctl show -p InvocationID --value "omamobile-privacy@$key-$value.service" 2>/dev/null) || inv=''
    why=''
    if [[ $inv =~ ^[0-9a-f]{32}$ ]]; then
      why=$(timeout 5 journalctl -q -o cat "_SYSTEMD_INVOCATION_ID=$inv" 2>/dev/null) || why=''
    fi
    case $why in
      *'update omamobile-audio first'*) setfail "not changed: update omamobile-audio first (its microphone guard is missing)" ;;
      *'maybe still open'*|*'maybe partly open'*) setfail "the $name could not be switched and may be partly open: try again" ;;
      *'its nodes locked here'*) setfail "the $name could not be switched cleanly: it is left off" ;;
      *'stopped in the middle'*) setfail "the switch took too long and was stopped: the $name is left off" ;;
      *'another privacy switch is still running'*) setfail "not changed: another switch is still running" ;;
      *'not changed: '*) setfail "not changed: the $name could not be switched $value, so it stays $([[ $value == on ]] && echo off || echo on)" ;;
      *'still open by:'*) why=${why##*still open by: }; why=${why%%$'\n'*}; why=${why//[^a-zA-Z0-9 ()._-]/}
        setfail "the $name is off, but an app still had it open and would not stop: $why" ;;
      *'could not restart the audio'*) setfail "the $name is $value, but the sound could not restart: log out and back in" ;;
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
