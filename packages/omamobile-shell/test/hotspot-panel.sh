#!/bin/bash
# SPDX-License-Identifier: MIT
# Tests for the Hotspot page's script (hotspot-panel.sh) against fake
# commands: the NetworkManager backend's state line, a name and password
# change, the VPN boxes staying off there, the QR code when qrencode is
# there and when it isn't, the checks on a new name and password, and a
# device's own backend taking over.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
script=plugins/omamobile.quicksettings/hotspot-panel.sh
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fake=$tmp/bin; basic=$tmp/basic; log=$tmp/log
mkdir -p "$fake" "$basic" "$tmp/home/.config" "$tmp/run"
for tool in bash sh awk sed grep cat head printf python3 rm mkdir; do
  ln -s "$(command -v "$tool")" "$basic/$tool"
done
: >"$log"
stub() { printf '#!/bin/sh\n%s\n' "$2" >"$fake/$1"; chmod +x "$fake/$1"; }

# nmcli: the Hotspot connection with a name and password, active or not
# ($tmp/active), and `connection modify` recorded.
stub nmcli '
case "$*" in
  "-s -g 802-11-wireless.ssid connection show Hotspot") cat '"$tmp"'/ssid ;;
  "-s -g 802-11-wireless-security.psk connection show Hotspot") cat '"$tmp"'/psk ;;
  "-t -f NAME connection show --active") [ -e '"$tmp"'/active ] && echo Hotspot; echo Home ;;
  "-t -f TYPE connection show --active") echo 802-11-wireless ;;
  "-t -f DEVICE,NAME connection show --active") [ -e '"$tmp"'/active ] && echo "wlan0:Hotspot" ;;
  "connection modify Hotspot 802-11-wireless.ssid "*) echo "nmcli $*" >>'"$log"'; echo "$5" >'"$tmp"'/ssid; echo "$7" >'"$tmp"'/psk ;;
  "connection up Hotspot") echo "nmcli $*" >>'"$log"' ;;
  *) echo "nmcli: unexpected $*" >&2; exit 1 ;;
esac'
stub iw 'printf "Station aa\nStation bb\n"'
stub qrencode 'echo "qrencode $*" >>'"$log"'; for a in "$@"; do [ "$prev" = -o ] && : >"$a"; prev=$a; done'
echo "Phone" >"$tmp/ssid"; echo "correct horse battery" >"$tmp/psk"

run() { env -i HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp/run" PATH="$fake:$basic" bash "$script" "$@"; }
field() { python3 -c 'import json,sys; v=json.load(sys.stdin)[sys.argv[1]]; print(v if not isinstance(v,bool) else str(v).lower())' "$1"; }

# ---- NetworkManager backend, hotspot off
s=$(run state)
[[ $(echo "$s" | field backend) == networkmanager ]] || fail "the backend is NetworkManager"
[[ $(echo "$s" | field hotspot) == off ]] || fail "the hotspot reads off while the connection is down"
[[ $(echo "$s" | field ssid) == Phone ]] || fail "the name comes from the connection"
[[ $(echo "$s" | field psk) == "correct horse battery" ]] || fail "the password comes from the connection"
[[ $(echo "$s" | field share_available) == false ]] || fail "no VPN sharing with NetworkManager's hotspot"
[[ $(echo "$s" | field editable) == true ]] || fail "a connection with a name is editable"
[[ $(echo "$s" | field qr) == "$tmp/run/omamobile-hotspot/wifi-qr.png" ]] || fail "the QR code is drawn into the runtime directory"
grep -q 'WIFI:T:WPA;S:Phone;P:correct horse battery;;' "$log" || fail "the QR code holds the WIFI: string"
[[ $(stat -c %a "$tmp/run/omamobile-hotspot/wifi-qr.src") == 600 ]] || fail "the QR source is private"
n=$(grep -c qrencode "$log"); run state >/dev/null
[[ $(grep -c qrencode "$log") == "$n" ]] || fail "an unchanged code is not drawn again"
pass "hotspot-panel.sh: NetworkManager state, the QR code once"

# ---- hotspot on: connected devices
: >"$tmp/active"
s=$(run state)
[[ $(echo "$s" | field hotspot) == on && $(echo "$s" | field clients) == 2 ]] || fail "an active hotspot reports its devices"
pass "hotspot-panel.sh: an active hotspot counts its devices"

# ---- set: the checks, then nmcli modify and a restart of a running hotspot
(run set "" "longenough" || true) | grep -q '^error:' || fail "an empty name is refused"
(run set "Phone" "short" || true) | grep -q '^error:' || fail "a short password is refused"
(run set "$(printf 'x%.0s' $(seq 33))" "longenough" || true) | grep -q '^error:' || fail "a 33-character name is refused"
grep -q 'connection modify' "$log" && fail "nothing is written while a value is refused"
out=$(run set "Cafe" "newpassword1")
echo "$out" | grep -q '^ok: hotspot restarted' || fail "a change on a running hotspot restarts it: $out"
grep -q 'nmcli connection modify Hotspot 802-11-wireless.ssid Cafe 802-11-wireless-security.psk newpassword1' "$log" || fail "the change goes to the connection"
grep -q 'nmcli connection up Hotspot' "$log" || fail "the running hotspot is brought up again"
[[ ! -e $tmp/run/omamobile-hotspot/wifi-qr.png ]] || fail "the old QR code is dropped after a change"
s=$(run state); [[ $(echo "$s" | field ssid) == Cafe ]] || fail "the state shows the new name"
rm "$tmp/active"; : >"$log"
run set "Cafe" "newpassword2" | grep -q '^ok: saved' || fail "a change on a stopped hotspot only saves"
grep -q 'connection up' "$log" && fail "a stopped hotspot is not started by a change"
pass "hotspot-panel.sh: name and password changes"

# ---- the VPN boxes are refused with NetworkManager
run share on | grep -q '^error:' || fail "Share VPN is refused with NetworkManager's hotspot"
run alltraffic on | grep -q '^error:' || fail "Route all traffic is refused with NetworkManager's hotspot"
pass "hotspot-panel.sh: no VPN boxes with NetworkManager"

# ---- no qrencode: the page gets no code, everything else as before
rm "$fake/qrencode"
s=$(run state)
[[ $(echo "$s" | field qr) == "" && $(echo "$s" | field ssid) == Cafe ]] || fail "without qrencode the state carries no code"
pass "hotspot-panel.sh: works without qrencode"

# ---- a device's own backend takes over, the QR code is still added
mkdir -p "$tmp/home/.config/omamobile"
cat >"$tmp/home/.config/omamobile/hotspot-backend" <<'EOF'
#!/bin/sh
echo "backend $*" >>"$LOG"
case $1 in
  state) echo '{"backend":"own","hotspot":"on","vpn":"on","share":"on","share_available":true,"prefer_share":true,"all_traffic_available":true,"all_traffic":false,"editable":true,"ssid":"Own","psk":"ownpassword","clients":1}' ;;
  set) echo "ok: own set" ;;
  share|alltraffic) echo ok ;;
esac
EOF
chmod +x "$tmp/home/.config/omamobile/hotspot-backend"
printf '#!/bin/sh\necho "qrencode $*" >>%s; for a in "$@"; do [ "$prev" = -o ] && : >"$a"; prev=$a; done\n' "$log" >"$fake/qrencode"; chmod +x "$fake/qrencode"
own() { env -i HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp/run" PATH="$fake:$basic" LOG="$log" bash "$script" "$@"; }
s=$(own state)
[[ $(echo "$s" | field backend) == own && $(echo "$s" | field share_available) == true ]] || fail "the device's backend answers the state"
[[ $(echo "$s" | field qr) == "$tmp/run/omamobile-hotspot/wifi-qr.png" ]] || fail "the QR code is added to the backend's state"
grep -q 'S:Own;P:ownpassword' "$log" || fail "the code is drawn from the backend's name and password"
own set "Own" "ownpassword" | grep -q '^ok: own set' || fail "set goes to the device's backend"
own share on | grep -q '^ok' && grep -q 'backend share on' "$log" || fail "share goes to the device's backend"
own alltraffic off | grep -q '^ok' && grep -q 'backend alltraffic off' "$log" || fail "alltraffic goes to the device's backend"
(own set "Own" "short" || true) | grep -q '^error:' || fail "the checks run before any backend"
pass "hotspot-panel.sh: a device's own backend"
