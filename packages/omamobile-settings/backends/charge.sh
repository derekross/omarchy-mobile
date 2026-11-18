#!/bin/bash
# SPDX-License-Identifier: MIT
# Charge limit for the Settings app's Battery page. Prints one line of JSON.
#   charge.sh get            {"available":true,"limit":80}  (read from the charger), or {"available":false}
#   charge.sh set limit N    N is 80, 85, 90, 95 or 100; saved and applied as root by
#                            omamobile-charge-limit@N.service, which the polkit rule lets the active local user start
# Available only on a phone whose device package declares its charge limit in /usr/share/omamobile/charge-limit.conf
# (a line supply=NAME; omamobile-device-husky ships it for max77759-charger), and only while that supply has
# charge_control_end_threshold. Anywhere else: {"available":false}, and set changes nothing.
# The test runs a copy of this script with `fake` set to a scratch root: the threshold is read there and
# `set` writes it directly, no service is started. Nothing in the environment sets it.
set -euo pipefail
set +x
verb=${1:-}; key=${2:-}; value=${3:-}
fail() { printf '{"error":"%s"}\n' "$1"; exit 2; }
fake=''
[[ -z $fake || -d $fake ]] || fail "cannot read the test root"
decl=$fake/usr/share/omamobile/charge-limit.conf
supply=$(sed -n 's/^supply=//p' "$decl" 2>/dev/null | head -n 1) || supply=''
[[ $supply =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]] || supply=''
end=$fake/sys/class/power_supply/$supply/charge_control_end_threshold

read_limit() {
  [[ -n $supply && -r $end ]] || return 1
  local v; v=$(tr -d ' \t\n' < "$end")
  [[ $v =~ ^[0-9]{1,3}$ ]] || return 2
  echo $((10#$v))
}
get() {
  local v rc=0
  v=$(read_limit) || rc=$?
  case $rc in
    0) printf '{"available":true,"limit":%s}\n' "$v" ;;
    1) printf '{"available":false}\n' ;;
    *) fail "cannot read the charger" ;;
  esac
}

case $verb in
get) get ;;
set)
  [[ $key == limit ]] || fail "unknown key"
  case $value in 80|85|90|95|100) ;; *) fail "bad value" ;; esac
  [[ -n $supply && -e $end ]] || fail "this phone has no charge limit"
  if [[ -n $fake ]]; then echo "$value" > "$end"
  else
    systemctl start --no-ask-password "omamobile-charge-limit@$value.service" >/dev/null 2>&1 || fail "could not set the charge limit"
  fi
  get ;;
*) fail "usage: get|set" ;;
esac
