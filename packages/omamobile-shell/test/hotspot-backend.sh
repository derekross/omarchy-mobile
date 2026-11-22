#!/bin/bash
# SPDX-License-Identifier: MIT
# hotspot/hotspot-backend against stub nmcli and systemctl: nothing on this machine is touched.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/run" "$tmp/st"; export ST=$tmp/st
U=aaaaaaaa-0000-0000-0000-000000000001
fail() { echo "FAIL: $*" >&2; exit 1; }
stub() { printf '#!/bin/bash\necho "%s $*" >> "$ST/log"\n%s\n' "$1" "$2" > "$tmp/bin/$1"; chmod +x "$tmp/bin/$1"; }
stub nmcli '[[ $1 == -e && $2 == no ]] || { echo "nmcli without -e no" >&2; exit 1; }; shift 2; case "$*" in
  "-t -f UUID,NAME connection show") [[ -e $ST/profile ]] && echo "'$U':Hotspot"; true ;;
  "-g 802-11-wireless.mode connection show uuid '$U'") echo ap ;;
  "-s -g 802-11-wireless.ssid connection show uuid '$U'") echo "Phone hotspot" ;;
  "-s -g 802-11-wireless-security.psk connection show uuid '$U'") echo "pass\"word1" ;;
  "connection add "*) touch "$ST/profile" ;;
  "connection modify uuid '$U' "*) ;;
  *) echo "unexpected nmcli $*" >&2; exit 1 ;;
esac'
stub systemctl 'case "$1" in show) cat "$ST/unit" 2>/dev/null || echo inactive ;; esac; [[ ! -e $ST/sysfail ]]'
stub hostname 'echo husky'
touch "$tmp/devconf"
be() { PATH="$tmp/bin:/usr/bin" OMAMOBILE_HOTSPOT_RUN="$tmp/run" OMAMOBILE_HOTSPOT_DEVCONF="$tmp/devconf" bash "$src/hotspot/hotspot-backend" "$@"; }
field() { python3 -c 'import json,sys; v=json.load(sys.stdin)[sys.argv[1]]; print(v if not isinstance(v,bool) else str(v).lower())' "$1"; }

# no profile yet: off, empty name, no VPN boxes, the uplink note
s=$(be state)
[[ $(field hotspot <<< "$s") == off && $(field ssid <<< "$s") == "" ]] || fail "state without a profile"
[[ $(field share_available <<< "$s") == false && $(field all_traffic_available <<< "$s") == false ]] || fail "VPN boxes must stay hidden"
[[ $(field uplink_note <<< "$s") == *802.11w* ]] || fail "the uplink note names the PMF limit"
# on without a profile: one is made with pmf 3 on ap0, 2.4 GHz, then the unit starts
: > "$ST/log"; be on
grep -c "^nmcli -e no connection add type wifi con-name Hotspot ifname ap0 ssid Hotspot-husky .*802-11-wireless.band bg .*802-11-wireless-security.pmf 3 802-11-wireless-security.proto rsn 802-11-wireless-security.pairwise ccmp 802-11-wireless-security.group ccmp" "$ST/log" >/dev/null || fail "on makes an RSN/CCMP profile with pmf 3 on ap0 (without proto wpa_supplicant can't build its WPA IE)"
grep -c "^systemctl start omamobile-hotspot.service" "$ST/log" >/dev/null || fail "on starts the unit"
[[ $(be active) == off ]] || fail "active while off"
echo activating > "$ST/unit"; [[ $(be active) == on && $(be state | field hotspot) == on ]] || fail "activating counts as on"
# running: on, name and password read back (JSON-quoted), clients counted from the helper's list
echo active > "$ST/unit"; printf 'aa\t10.42.0.2\tA\nbb\t\t\n' > "$tmp/run/clients"
s=$(be state)
[[ $(field hotspot <<< "$s") == on && $(field clients <<< "$s") == 2 ]] || fail "state while on"
[[ $(field psk <<< "$s") == 'pass"word1' && $(field ssid <<< "$s") == "Phone hotspot" ]] || fail "name and password read back"
# set while on: modify, then stop and start (polkit allows only those two)
: > "$ST/log"
[[ $(be set "New name" "newpassword") == "ok: hotspot restarted with the new name and password" ]] || fail "set while on"
grep -c "^nmcli -e no connection modify uuid $U 802-11-wireless.ssid New name 802-11-wireless-security.psk newpassword" "$ST/log" >/dev/null || fail "set modifies the profile"
[[ $(grep "^systemctl \(stop\|start\)" "$ST/log" | tr '\n' '|') == "systemctl stop omamobile-hotspot.service|systemctl start omamobile-hotspot.service|" ]] || fail "set restarts the unit: stop, then start"
# a stop that fails: set says so, exits 1 and doesn't start
touch "$ST/sysfail"; : > "$ST/log"
out=$(be set "New name" "newpassword") && fail "set exits 0 when the stop fails"
[[ $out == error:* ]] && (( $(grep -c "^systemctl start" "$ST/log" || true) == 0 )) || fail "a failed stop must not start"
[[ $(be on) == error:* ]] || fail "on says error when systemctl fails"
rm -f "$ST/sysfail"
# set while off: saved only
echo inactive > "$ST/unit"; : > "$ST/log"
[[ $(be set "New name" "newpassword") == "ok: saved; applies when the hotspot is turned on" ]] || fail "set while off"
(( $(grep -c "^systemctl \(start\|stop\)" "$ST/log" || true) == 0 )) || fail "set while off must not touch the unit"
# off stops the unit; the VPN verbs say no
: > "$ST/log"; be off; grep -c "^systemctl stop --no-block omamobile-hotspot.service" "$ST/log" >/dev/null || fail "off stops the unit"
[[ $(be share on) == error:* && $(be alltraffic on) == error:* ]] || fail "VPN verbs refused"
[[ $(be bogus 2>&1; echo $?) == *2 ]] || fail "usage"
# a phone that didn't opt in: on says so and starts nothing
rm -f "$tmp/devconf"; : > "$ST/log"
[[ $(be on) == "error: this phone has no hotspot settings" ]] || fail "on without the device's hotspot.conf"
(( $(grep -c "^systemctl" "$ST/log" || true) == 0 )) || fail "on without the device's hotspot.conf must not start the unit"
echo "hotspot-backend: ok"
