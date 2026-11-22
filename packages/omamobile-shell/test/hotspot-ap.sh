#!/bin/bash
# SPDX-License-Identifier: MIT
# hotspot/hotspot-ap against stub nmcli, iw, ufw, ip and systemd-notify: nothing on this machine is touched.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/run" "$tmp/st"; st=$tmp/st
U=aaaaaaaa-0000-0000-0000-000000000001 W=cccccccc-0000-0000-0000-000000000003
stub() { printf '#!/bin/bash\necho "%s $*" >> "$ST/log"\n%s\n' "$1" "$2" > "$tmp/bin/$1"; chmod +x "$tmp/bin/$1"; }
stub nmcli '[[ $1 == -w ]] && shift 2; a="$*"
case "$a" in
  "-t -f DEVICE,TYPE device") echo wlp1s0:wifi; [[ -e $ST/ap0 ]] && echo ap0:wifi ;;
  "-t -f DEVICE,STATE device") echo wlp1s0:connected; [[ -e $ST/ap0 ]] && echo ap0:disconnected ;;
  "-t -f UUID,NAME connection show") echo "'$U':Hotspot" ;;
  "-g 802-11-wireless.mode connection show uuid '$U'") echo ap ;;
  "-g 802-11-wireless-security.key-mgmt connection show uuid '$U'") [[ -e $ST/open ]] || echo wpa-psk ;;
  "-s -g 802-11-wireless-security.psk connection show uuid '$U'") [[ -e $ST/nopsk ]] || echo longenough ;;
  "-g GENERAL.CON-UUID device show wlp1s0") echo '$W' ;;
  "connection modify uuid '$U' "*) ;;
  "connection up uuid '$U' ifname ap0") [[ -e $ST/failup ]] || { cat "$ST/upstart" 2>/dev/null || echo 0; } > "$ST/up" ;;
  "-t -f UUID,DEVICE connection show --active")
    if [[ -e $ST/up ]]; then n=$(cat "$ST/up"); echo $((n + 1)) > "$ST/up"; (( n < 2 )) && echo "'$U':ap0"; fi; true ;;
  "connection down uuid '$U'") rm -f "$ST/up" ;;
  "connection up uuid '$W' ifname wlp1s0") touch "$ST/route" ;;
  *) echo "unexpected nmcli $a" >&2; exit 1 ;;
esac'
cp "$tmp/bin/nmcli" "$tmp/nmcli.orig"
stub iw 'case "$*" in
  "dev ap0 info") [[ -e $ST/ap0 ]] ;;
  "phy phy0 interface add ap0 type __ap") touch "$ST/ap0" ;;
  "dev ap0 del") rm -f "$ST/ap0" ;;
  "dev ap0 station dump"|"dev wlp1s0 station dump") if [[ -e $ST/stations ]]; then cat "$ST/stations"; else printf "Station 02:BB:CC:DD:EE:01 (on ap0)\n\tsignal: -40\nStation 02:bb:cc:dd:ee:02 (on ap0)\n"; fi ;;
  *) exit 1 ;;
esac'
stub ufw 'case "$*" in
  "status numbered") echo "Status: active"; [[ -e $ST/ownerdel ]] || echo "[ 3] 67/udp on ap0 ALLOW IN Anywhere"
    [[ -e $ST/leftover ]] && printf "[ 1] 22/tcp ALLOW IN Anywhere\n[ 7] Anywhere on ap0 ALLOW FWD Anywhere # omamobile-hotspot\n"
    [[ -e $ST/leftover_wl ]] && echo "[ 9] 67/udp on wlp1s0 ALLOW IN Anywhere # omamobile-hotspot"; true ;;
  status) echo "Status: active"; [[ -e $ST/leftover ]] && echo "Anywhere on ap0 ALLOW FWD Anywhere"
    [[ -e $ST/ownerrule ]] && echo "67/udp on ap0              ALLOW IN    Anywhere"; true ;;
  "--force delete 7") rm -f "$ST/leftover" ;;
  "--force delete 9") rm -f "$ST/leftover_wl" ;;
  "--force delete 3") touch "$ST/ownerdel" ;;
  "--force delete "[0-9]*) exit 1 ;;
  "--force delete "*|"--force route delete "*) ;;
  allow*|route*) ;;
  *) exit 1 ;;
esac'
stub ip '[[ -e $ST/route ]] && echo "default via 10.0.0.1 dev wlp1s0"; [[ -e $ST/linkdown ]] && echo "default via 10.0.0.1 dev wlp1s0 linkdown"; [[ -e $ST/rmnet ]] && echo "default dev rmnet0 proto static metric 700"; [[ -e $ST/usbdown ]] && echo "default via 172.16.42.2 dev usb1 linkdown"; true'
stub ping '[[ ! -e $ST/silentgw ]]'
stub systemd-notify 'true'
# the reconnect unit: run at once (the tests read its result); a failing systemd-run is the fallback case
stub systemd-run '[[ -e $ST/norun ]] && exit 1; while [[ $1 == --* ]]; do shift; done; "$@"'
stub systemctl '[[ $1 == show ]] && { cat "$ST/unit" 2>/dev/null || echo inactive; }; true'
mkdir -p "$tmp/sys/net/wlp1s0/phy80211"; echo phy0 > "$tmp/sys/net/wlp1s0/phy80211/name"
cp "$src/hotspot/hotspot-ap" "$tmp/hotspot-ap"
printf '1700000000 02:bb:cc:dd:ee:01 10.42.0.23 OnePlus-13 01:aa\n' > "$tmp/leases"
echo 50000 > "$tmp/temp"; touch "$st/route"
export ST=$st
ap() { PATH="$tmp/bin:/usr/bin" OMAMOBILE_HOTSPOT_RUN="$tmp/run" OMAMOBILE_HOTSPOT_TEMP="$tmp/temp" OMAMOBILE_HOTSPOT_LEASES="$tmp/leases" \
  OMAMOBILE_HOTSPOT_SYSNET="$tmp/sys/net" OMAMOBILE_HOTSPOT_CONF="$tmp/hotspot.conf" \
  OMAMOBILE_HOTSPOT_DEVCONF="$tmp/devconf" OMAMOBILE_HOTSPOT_SYSCTL="$tmp/sysctl" \
  OMAMOBILE_HOTSPOT_HOT_MC=${HOTMC-60000} OMAMOBILE_HOTSPOT_POLL=0.1 bash "$tmp/hotspot-ap" "$@"; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }

# too hot: no start, nothing made
echo 61000 > "$tmp/temp"; : > "$st/log"
ap run >/dev/null && { echo "FAIL: started while hot" >&2; exit 1; }
eq "$(cat "$tmp/run/last-stop")" too-hot
grep -q 'interface add' "$st/log" && { echo "FAIL: made ap0 while hot" >&2; exit 1; }
echo 50000 > "$tmp/temp"
# a start: ap0 made, profile bound to ap0, UFW opened on ap0 only, clients listed, then the profile goes down -> ended
: > "$st/log"
ap run >/dev/null
grep -q "iw phy phy0 interface add ap0 type __ap" "$st/log" || { echo "FAIL: no ap0" >&2; exit 1; }
grep -q "connection modify uuid $U connection.interface-name ap0 .*802-11-wireless-security.pmf 3 .*ipv4.method shared" "$st/log" || { echo "FAIL: not bound to ap0" >&2; exit 1; }
eq "$(grep -c '^ufw allow in on ap0\|^ufw route allow in on ap0' "$st/log")" 4
(( $(grep '^ufw ' "$st/log" | grep -v status | grep -cv ' on ap0' || true) > 0 )) && { echo "FAIL: a UFW rule not on ap0" >&2; exit 1; }
eq "$(cat "$tmp/run/last-stop")" ended
eq "$(cat "$tmp/run/uplink-uuid")" "$W"
eq "$(cat "$tmp/run/clients")" "$(printf '02:bb:cc:dd:ee:01\t10.42.0.23\tOnePlus-13\n02:bb:cc:dd:ee:02\t\t')"
# the client list from a full station dump and lease file: only associated stations, in dump order; the MAC matched
# without case; "*" (no name) and a lease for a station that left are dropped; a name loses every unsafe character
printf 'Station 02:BB:CC:DD:EE:01 (on ap0)\n\tinactive time:\t20 ms\n\trx bytes:\t1234\nStation 02:22:33:44:55:66 (on ap0)\n\tsignal:  \t-61 dBm\nStation 06:88:99:aa:bb:cc (on ap0)\nStation not-a-mac (on ap0)\n' > "$st/stations"
printf '%s\n' '1700000000 02:bb:cc:dd:ee:01 10.42.0.23 OnePlus-13 01:aa' '1700000001 02:22:33:44:55:66 10.42.0.50 * *' \
  '1700000002 06:88:99:AA:BB:CC 10.42.0.61 bad$(x);`y`/z ff:01' '1700000003 0a:ad:be:ef:00:00 10.42.0.99 gone *' > "$tmp/leases"
: > "$st/log"; ap run >/dev/null
grep -q '^iw dev ap0 station dump' "$st/log" || { echo "FAIL: stations not read on ap0" >&2; exit 1; }
eq "$(cat "$tmp/run/clients")" "$(printf '02:bb:cc:dd:ee:01\t10.42.0.23\tOnePlus-13\n02:22:33:44:55:66\t10.42.0.50\t\n06:88:99:aa:bb:cc\t10.42.0.61\tbadxyz')"
# no lease file yet (a client still asking for an address): listed by MAC, no address or name
mv "$tmp/leases" "$tmp/leases.k"; ap run >/dev/null
eq "$(cat "$tmp/run/clients")" "$(printf '02:bb:cc:dd:ee:01\t\t\n02:22:33:44:55:66\t\t\n06:88:99:aa:bb:cc\t\t')"
# no stations: an empty list file (the page reads it as on with 0 clients)
: > "$st/stations"; ap run >/dev/null
[[ -e $tmp/run/clients && ! -s $tmp/run/clients ]] || { echo "FAIL: list not emptied" >&2; exit 1; }
mv "$tmp/leases.k" "$tmp/leases"; rm -f "$st/stations"; ap run >/dev/null
# an owner's own rule equal to one of ours: ours isn't added (ufw would put our comment on theirs), the rest are
touch "$st/ownerrule"; : > "$st/log"; ap run >/dev/null 2>&1 || true
grep -c '^ufw allow in on ap0 to any port 67 proto udp' "$st/log" >/dev/null && { echo "FAIL: added a rule equal to the owner's" >&2; exit 1; }
eq "$(grep -c '^ufw allow in on ap0\|^ufw route allow in on ap0' "$st/log")" 3
rm -f "$st/ownerrule"; ap down >/dev/null 2>&1 || true
ap run >/dev/null
# down: profile down, the same rules deleted, ap0 gone, the saved client connection brought up again even with a route
rm -f "$st/route"; touch "$st/leftover"; : > "$st/log"
ap down >/dev/null
# never by spec (that would take the owner's own equal rule too), and the owner's untagged rule on ap0 stays
eq "$(grep -c '^ufw --force delete allow\|^ufw --force route delete' "$st/log" || true)" 0
[[ -e $st/ownerdel ]] && { echo "FAIL: the owner's own rule on ap0 was deleted" >&2; exit 1; }
grep -qx 'ufw --force delete 7' "$st/log" || { echo "FAIL: a tagged leftover rule was not deleted by number" >&2; exit 1; }
[[ -e $st/leftover ]] && { echo "FAIL: leftover rule kept" >&2; exit 1; }
[[ -e $st/ap0 ]] && { echo "FAIL: ap0 left" >&2; exit 1; }
grep -q "nmcli -w 40 connection up uuid $W ifname wlp1s0" "$st/log" || { echo "FAIL: client Wi-Fi not restored" >&2; exit 1; }
grep -q "^systemd-run .*--unit=omamobile-hotspot-reconnect .*hotspot-ap reconnect wlp1s0 $W" "$st/log" || { echo "FAIL: reconnect not handed to its own unit" >&2; exit 1; }
[[ -e $tmp/run/reconnecting ]] && { echo "FAIL: reconnecting marker left" >&2; exit 1; }
[[ -e $tmp/run/clients || -e $tmp/run/uplink-uuid ]] && { echo "FAIL: stale run files" >&2; exit 1; }
# a profile without a key is never started
touch "$st/open"; : > "$st/log"
ap run >/dev/null && { echo "FAIL: started an open profile" >&2; exit 1; }
eq "$(cat "$tmp/run/last-stop")" "failed: the Hotspot settings have no password"
grep -q 'interface add' "$st/log" && { echo "FAIL: made ap0 for an open profile" >&2; exit 1; }
rm -f "$st/open"
# a route left "linkdown" after ap0 goes is no route: the client Wi-Fi is brought up again
echo 0 > "$st/up"; ap run >/dev/null; rm -f "$st/route"; touch "$st/linkdown"; : > "$st/log"
ap down >/dev/null; rm -f "$st/linkdown"
grep -q "connection up uuid $W ifname wlp1s0" "$st/log" || { echo "FAIL: a linkdown route was taken as working" >&2; exit 1; }
# a gateway that drops ping but is REACHABLE: the working Wi-Fi is left alone
stub ip '[[ $1 == -4 && $2 == neigh ]] && { echo "10.0.0.1 lladdr aa:bb:cc:dd:ee:ff REACHABLE"; exit 0; }; [[ -e $ST/route ]] && echo "default via 10.0.0.1 dev wlp1s0"; [[ -e $ST/linkdown ]] && echo "default via 10.0.0.1 dev wlp1s0 linkdown"; [[ -e $ST/rmnet ]] && echo "default dev rmnet0 proto static metric 700"; [[ -e $ST/usbdown ]] && echo "default via 172.16.42.2 dev usb1 linkdown"; true'
echo 0 > "$st/up"; ap run >/dev/null; touch "$st/route" "$st/silentgw"; : > "$st/log"
ap down >/dev/null; rm -f "$st/silentgw"
grep -q "connection up uuid $W" "$st/log" && { echo "FAIL: bounced a working Wi-Fi whose gateway drops ping" >&2; exit 1; }
# a failed start leaves why; down after it still cleans up and runs with nothing to clean
touch "$st/failup"; : > "$st/log"
ap run >/dev/null && { echo "FAIL: a failed start returned 0" >&2; exit 1; }
eq "$(cat "$tmp/run/last-stop")" "failed: the access point did not start"
ap down >/dev/null; [[ -e $st/ap0 ]] && { echo "FAIL: ap0 left after a failed start" >&2; exit 1; }
ap down >/dev/null || { echo "FAIL: down with nothing to do" >&2; exit 1; }
rm -f "$st/failup"
# too hot while on: two reads in a row end it
echo 0 > "$st/up"; : > "$st/log"
stub nmcli "$(sed -n '3,$p' "$tmp/bin/nmcli" | sed 's/(( n < 2 ))/(( n < 99 ))/')"
( sleep 0.5; echo 62000 > "$tmp/temp" ) &
ap run >/dev/null
eq "$(cat "$tmp/run/last-stop")" too-hot
eq "$(cat "$tmp/run/created")" ap0
# a stale marker for ap0 never makes another interface count as made here
ap down >/dev/null; echo ap0 > "$tmp/run/created"
eq "$(ap bogus 2>&1 >/dev/null; echo $?)" "$(printf 'usage: hotspot-ap run|down|reconnect STA UUID\n2')"
# interface=wlp1s0: the Wi-Fi device itself carries the AP: no second interface made or deleted, the client
# connection replaced while on and brought back after
echo 50000 > "$tmp/temp"; echo interface=wlp1s0 > "$tmp/hotspot.conf"
stub nmcli "$(sed -n '3,$p' "$tmp/bin/nmcli" | sed "s/(( n < 99 ))/(( n < 2 ))/; s/:ap0\"; fi/:wlp1s0\"; fi/; s/ifname ap0\")/ifname wlp1s0\")/")"
rm -f "$st/route"; : > "$st/log"
mkdir -p "$tmp/sys/net/ap0/phy80211" "$tmp/sys/net/p2p-dev-wlp1s0/phy80211"   # a leftover ap0 and a p2p device beside it
ap run >/dev/null
grep -q 'interface add' "$st/log" && { echo "FAIL: made an interface in wlp1s0 mode" >&2; exit 1; }
[[ $(cat "$tmp/run/created") == wlp1s0 ]] && { echo "FAIL: marked the Wi-Fi device as made here" >&2; exit 1; }
grep -q "connection.interface-name wlp1s0" "$st/log" || { echo "FAIL: not bound to wlp1s0" >&2; exit 1; }
grep -q '^ufw allow in on wlp1s0 to any port 67' "$st/log" || { echo "FAIL: UFW not on wlp1s0" >&2; exit 1; }
grep -q '^iw dev wlp1s0 station dump' "$st/log" || { echo "FAIL: stations not read on wlp1s0" >&2; exit 1; }
grep -q '^iw dev ap0 station dump' "$st/log" && { echo "FAIL: stations read on ap0 in wlp1s0 mode" >&2; exit 1; }
echo interface=ap0 > "$tmp/hotspot.conf"     # a changed value: down still uses the interface run used
: > "$st/log"; touch "$st/leftover_wl"; ap down >/dev/null
grep -q 'iw dev wlp1s0 del\|iw dev ap0 del' "$st/log" && { echo "FAIL: deleted an interface it did not make" >&2; exit 1; }
grep -qx 'ufw --force delete 9' "$st/log" && [[ ! -e $st/leftover_wl ]] || { echo "FAIL: tagged wlp1s0 rules not removed by number" >&2; exit 1; }
grep -q "connection up uuid $W ifname wlp1s0" "$st/log" || { echo "FAIL: client Wi-Fi not brought back" >&2; exit 1; }
echo interface=ap0 > "$tmp/hotspot.conf"; rm -rf "$tmp/sys/net/ap0"
cp "$tmp/nmcli.orig" "$tmp/bin/nmcli"
# a client Wi-Fi that kept its route: no reconnect at all, the stop does not wait
echo 0 > "$st/up"; touch "$st/route"; ap run >/dev/null; : > "$st/log"
ap down >/dev/null
grep -q "systemd-run\|connection up uuid $W" "$st/log" && { echo "FAIL: reconnected a working Wi-Fi" >&2; exit 1; }
# the route comes back by itself within the wait: the reconnect unit does not bounce it
echo 0 > "$st/up"; ap run >/dev/null; rm -f "$st/route"; : > "$st/log"
stub systemd-run '[[ -e $ST/norun ]] && exit 1; while [[ $1 == --* ]]; do shift; done; ( sleep 1.5; touch "$ST/route" ) & "$@"'
ap down >/dev/null
grep -q "^systemd-run .*reconnect wlp1s0 $W" "$st/log" || { echo "FAIL: no reconnect unit" >&2; exit 1; }
grep -q "connection up uuid $W" "$st/log" && { echo "FAIL: bounced a Wi-Fi that came back by itself" >&2; exit 1; }
# a hotspot started again meanwhile: the reconnect gives way
echo 0 > "$st/up"; ap run >/dev/null; rm -f "$st/route"; : > "$st/log"; echo active > "$st/unit"
stub systemd-run '[[ -e $ST/norun ]] && exit 1; while [[ $1 == --* ]]; do shift; done; "$@"'
ap down >/dev/null; rm -f "$st/unit"
grep -q "^systemd-run .*reconnect wlp1s0 $W" "$st/log" || { echo "FAIL: no reconnect unit" >&2; exit 1; }
grep -q "connection up uuid $W" "$st/log" && { echo "FAIL: reconnect ran over a new hotspot" >&2; exit 1; }
eq "$(cat "$tmp/run/uplink-uuid")" "$W"     # kept for the new hotspot's own stop
# no systemd-run: the reconnect runs inline, as before
echo 0 > "$st/up"; ap run >/dev/null; rm -f "$st/route"; touch "$st/norun"; : > "$st/log"
ap down >/dev/null; rm -f "$st/norun"
grep -q "connection up uuid $W ifname wlp1s0" "$st/log" || { echo "FAIL: no inline fallback" >&2; exit 1; }
# a start stops a reconnect left from the last stop
: > "$st/log"; echo 0 > "$st/up"; touch "$tmp/run/reconnecting"; ap run >/dev/null
grep -q "^systemctl stop omamobile-hotspot-reconnect.service" "$st/log" || { echo "FAIL: start left the old reconnect" >&2; exit 1; }
[[ -e $tmp/run/reconnecting ]] && { echo "FAIL: stale reconnecting marker" >&2; exit 1; }
eq "$(ap reconnect 'bad name' x; echo $?)" 2
# a refused start (too hot) leaves a pending reconnect alone
: > "$st/log"; echo 61000 > "$tmp/temp"; ap run >/dev/null || :; echo 50000 > "$tmp/temp"
grep -q "^systemctl stop" "$st/log" && { echo "FAIL: a refused start stopped the reconnect" >&2; exit 1; }
# an empty client read on start keeps the connection saved before
echo "$W" > "$tmp/run/uplink-uuid"
cp "$tmp/bin/nmcli" "$tmp/nmcli.k"; sed -i "s/echo '\?$W'\? ;;/echo ;;/" "$tmp/bin/nmcli"
grep -q "GENERAL.CON-UUID device show wlp1s0\") echo ;;" "$tmp/bin/nmcli" || { echo "FAIL: test setup" >&2; exit 1; }
echo 0 > "$st/up"; ap run >/dev/null; cp "$tmp/nmcli.k" "$tmp/bin/nmcli"
eq "$(cat "$tmp/run/uplink-uuid")" "$W"
# a profile with an empty password is refused like an open one
touch "$st/nopsk"; rm -f "$tmp/run/last-stop"; echo 50000 > "$tmp/temp"
ap run >/dev/null 2>&1 && { echo "FAIL: started with an empty password" >&2; exit 1; }
eq "$(cat "$tmp/run/last-stop")" "failed: the Hotspot settings have no password"
rm -f "$st/nopsk"; ap down >/dev/null 2>&1 || true
# the bind asks for PMF required (pmf 3): the only setting clients can join on this firmware (#523)
grep -c "connection modify uuid $U .*802-11-wireless.band bg 802-11-wireless-security.pmf 3 802-11-wireless-security.proto rsn 802-11-wireless-security.pairwise ccmp 802-11-wireless-security.group ccmp" "$st/log" >/dev/null || { echo "FAIL: the profile is not bound with pmf 3 and RSN/CCMP" >&2; exit 1; }
# no stop temperature set (the default): a hot phone still starts, and the watch never ends it for heat
ap down >/dev/null 2>&1 || true
rm -f "$tmp/hotspot.conf" "$tmp/run/last-stop"; echo 61000 > "$tmp/temp"; : > "$st/log"
( sleep 0.6; rm -f "$st/up" ) &
HOTMC='' ap run >/dev/null 2>&1 || true; wait
eq "$(cat "$tmp/run/last-stop")" ended
echo stop_temp_mc=60000 > "$tmp/hotspot.conf"; rm -f "$tmp/run/last-stop"
HOTMC='' ap run >/dev/null 2>&1 || true
eq "$(cat "$tmp/run/last-stop")" too-hot
# forwarding: on for ap0 and every uplink that had it off (here the Wi-Fi and, coming up mid-run, mobile data),
# never for conf/all; an uplink that was already on is left alone; down writes the old values back
rm -f "$tmp/hotspot.conf" "$tmp/run/last-stop"; echo 50000 > "$tmp/temp"
for l in all ap0 wlp1s0 rmnet0 usb0; do mkdir -p "$tmp/sysctl/$l"; echo 0 > "$tmp/sysctl/$l/forwarding"; done
echo 1 > "$tmp/sysctl/usb0/forwarding"; touch "$st/route"; rm -f "$st/rmnet"
mkdir -p "$tmp/sysctl/usb1"; echo 0 > "$tmp/sysctl/usb1/forwarding"
touch "$st/usbdown"   # a default route marked linkdown (usb1, no cable) carries nothing: no forwarding for it
echo -6 > "$st/upstart"; ( sleep 0.35; touch "$st/rmnet" ) &
ap run >/dev/null 2>&1 || true; wait; rm -f "$st/upstart"
eq "$(cat "$tmp/sysctl/all/forwarding")" 0
eq "$(cat "$tmp/sysctl/usb1/forwarding")" 0
eq "$(cat "$tmp/sysctl/ap0/forwarding") $(cat "$tmp/sysctl/wlp1s0/forwarding") $(cat "$tmp/sysctl/rmnet0/forwarding")" "1 1 1"
[[ -e $tmp/run/fwd/usb0 ]] && { echo "FAIL: a link already forwarding was recorded" >&2; exit 1; }
# a second run before any down (a crash; the link back at 0) keeps the first values
# (the record holds a marker value here, so the test sees whether it was rewritten)
echo 0 > "$tmp/sysctl/wlp1s0/forwarding"; echo 7 > "$tmp/run/fwd/wlp1s0"
ap run >/dev/null 2>&1 || true
eq "$(cat "$tmp/run/fwd/wlp1s0")" 7
echo 0 > "$tmp/run/fwd/wlp1s0"
eq "$(cat "$tmp/run/fwd/wlp1s0")" 0
ap down >/dev/null 2>&1 || true
eq "$(cat "$tmp/sysctl/ap0/forwarding") $(cat "$tmp/sysctl/wlp1s0/forwarding") $(cat "$tmp/sysctl/rmnet0/forwarding") $(cat "$tmp/sysctl/usb0/forwarding") $(cat "$tmp/sysctl/all/forwarding")" "0 0 0 1 0"
[[ -z $(ls -A "$tmp/run/fwd" 2>/dev/null) ]] || { echo "FAIL: forwarding records left after down" >&2; exit 1; }
rm -f "$st/usbdown"
rm -f "$st/rmnet"
# a link that is gone at down drops its record; one whose write fails keeps it
mkdir -p "$tmp/run/fwd"; echo 0 > "$tmp/run/fwd/gone0"; echo 0 > "$tmp/run/fwd/ro0"
mkdir -p "$tmp/sysctl/ro0"; echo 1 > "$tmp/sysctl/ro0/forwarding"; chmod 444 "$tmp/sysctl/ro0/forwarding"
ap down >/dev/null 2>&1 || true
[[ ! -e $tmp/run/fwd/gone0 && -e $tmp/run/fwd/ro0 ]] || { echo "FAIL: restore records: gone link kept or failed write dropped" >&2; exit 1; }
chmod 644 "$tmp/sysctl/ro0/forwarding"; rm -f "$tmp/run/fwd/ro0"
# the device's file gives the interface when the owner's has none
printf 'interface=wlan9\n' > "$tmp/devconf"
eq "$(OMAMOBILE_HOTSPOT_RUN="$tmp/run2" OMAMOBILE_HOTSPOT_DEVCONF="$tmp/devconf" OMAMOBILE_HOTSPOT_CONF="$tmp/none" bash -c 'source <(sed -n "/^conf()/p" "$0"); CONF=$OMAMOBILE_HOTSPOT_CONF DEVCONF=$OMAMOBILE_HOTSPOT_DEVCONF; conf interface' "$tmp/hotspot-ap")" wlan9
printf 'interface=wlan8\n' > "$tmp/hotspot.conf"
eq "$(bash -c 'source <(sed -n "/^conf()/p" "$0"); CONF=$1 DEVCONF=$2; conf interface' "$tmp/hotspot-ap" "$tmp/hotspot.conf" "$tmp/devconf")" wlan8
rm -f "$tmp/hotspot.conf" "$tmp/devconf"
echo "hotspot-ap: ok"
