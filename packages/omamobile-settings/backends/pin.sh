#!/bin/bash
# SPDX-License-Identifier: MIT
# Change the lock-screen PIN, and say what this phone has. Prints one line of JSON.
#   pin.sh change     reads three lines from stdin (the current PIN, the new PIN, the new PIN again) and hands
#                     them, still on stdin, to `omamobile-set-pin --change`, which feeds them to passwd. Its
#                     exit status and stderr become one line of JSON: {"changed":true}, {"error":<what
#                     passwd or set-pin said>}, or for status 75 the "may or may not have changed" message.
#                     The PIN-or-password choice is not recorded by --change; the page only runs on a
#                     phone that already unlocks with a PIN (see status).
#   pin.sh status     {"type":"pin"|"password","hasPassword":true|false}: how the phone unlocks (what
#                     omamobile-set-pin recorded) and whether the account has a password at all. The page changes
#                     the PIN only on a phone that unlocks with one.
# The test runs a copy of this script with the tool paths replaced.
set -euo pipefail
PATH=/usr/bin
# Every tool is named by its full path; none is looked up by name.
case ${1:-} in
change)
  [[ -x /usr/bin/omamobile-set-pin ]] || { printf '%s\n' '{"error":"omamobile-set-pin is missing; nothing was changed"}'; exit 2; }
  # stdin goes straight through; only stderr is kept (passwd's prompts are answered, echo is off, so a PIN is
  # never in it), and only its last lines
  rc=0
  err=$(/usr/bin/omamobile-set-pin --change 2>&1 >/dev/null) || rc=$?
  if (( rc == 0 )); then
    printf '%s\n' '{"changed":true}'
    exit 0
  fi
  if (( rc == 75 )); then
    msg="passwd did not finish after the retype: the PIN may or may not have changed. Try the new PIN first, then the old one, and don't change it again for a minute."
  else
    msg=$err
    [[ -n ${msg//[[:space:]]/} ]] || msg="the PIN was not changed (exit $rc)"
  fi
  # the last three lines, at most 400 characters, cut as text and escaped by python
  unknown=False; (( rc == 75 )) && unknown=True
  printf '%s' "$msg" | UNKNOWN=$unknown /usr/bin/python3 -I -c 'import json,os,sys; t="\n".join(sys.stdin.buffer.read().decode(errors="replace").strip().splitlines()[-3:])[-400:]; r={"error": t}; r.update({"unknown": True} if os.environ["UNKNOWN"] == "True" else {}); print(json.dumps(r, separators=(",", ":")))'
  exit 1
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
