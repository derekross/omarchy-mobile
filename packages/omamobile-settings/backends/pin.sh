#!/bin/bash
# SPDX-License-Identifier: MIT
# Change the lock-screen PIN, and say what this phone has. Prints one line of JSON.
#   pin.sh change     reads three lines from stdin (the current PIN, the new PIN, the new PIN again) and runs
#                     pin.py, which hands them to the system's own passwd; see pin.py
#   pin.sh status     {"type":"pin"|"password","hasPassword":true|false}: how the phone unlocks (what
#                     omamobile-set-pin recorded) and whether the account has a password at all. The page changes
#                     the PIN only on a phone that unlocks with one.
# The test runs a copy of this script with the two tool paths replaced.
set -euo pipefail
PATH=/usr/bin
# $0 is the absolute path the runner passed; no tool is looked up by name.
here=${0%/*}
case ${1:-} in
change)
  exec /usr/bin/python3 -I "$here/pin.py"
  ;;
status)
  # Fails closed: a phone where either answer cannot be had gets no form.
  cannot() { printf '%s\n' '{"error":"cannot tell how this phone unlocks"}'; exit 2; }
  [[ -x /usr/bin/omamobile-set-pin ]] || cannot
  type=$(/usr/bin/omamobile-set-pin --type 2>/dev/null) || cannot
  [[ $type == pin || $type == password ]] || cannot
  state=$(/usr/bin/passwd -S 2>/dev/null | /usr/bin/awk '{ print $2; exit }') || cannot
  [[ -n $state ]] || cannot
  has=true
  [[ $state == NP ]] && has=false
  printf '{"type":"%s","hasPassword":%s}\n' "$type" "$has"
  ;;
*)
  printf '%s\n' '{"error":"usage: change|status"}'
  exit 2
  ;;
esac
