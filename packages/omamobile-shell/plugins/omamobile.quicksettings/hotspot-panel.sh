#!/bin/bash
# SPDX-License-Identifier: MIT
# Data and actions for the Hotspot page (HotspotPanel.qml), as the session user.
#
#   hotspot-panel.sh state            one JSON line (see below)
#   hotspot-panel.sh set NAME PASS    a new network name and password; a running
#                                     hotspot restarts with them. Prints
#                                     "ok: ..." or "error: ..."
#   hotspot-panel.sh share on|off     "Share VPN": devices on the hotspot reach
#                                     what the phone's VPN reaches
#   hotspot-panel.sh alltraffic on|off
#                                     "Route all traffic through the VPN": their
#                                     internet traffic goes through it as well
#
# The state line: {"backend", "hotspot": on|off, "vpn": on|off,
#   "share": on|off, "share_available", "prefer_share",
#   "all_traffic_available", "all_traffic", "editable",
#   "ssid", "psk", "qr": PNG path or "", "qr_rev": a number that changes
#   with the picture, "clients": connected devices}
#
# The hotspot itself is NetworkManager's "Hotspot" connection, the one
# tile-action.sh makes with `nmcli device wifi hotspot`: name and password
# come from that connection and change with `nmcli connection modify`.
# NetworkManager's shared mode has no switch for sharing a VPN, so the two
# VPN boxes stay hidden there (share_available false).
#
# A device may bring its own hotspot (its own hostapd, its own firewall)
# and with it the VPN boxes: an executable at /etc/omamobile/hotspot-backend
# (or ~/.config/omamobile/hotspot-backend, for the owner's own) that takes
# the same verbs and prints the same lines replaces everything below; this
# script then only draws the QR code for it.
#
# The QR code is the usual WIFI: string, drawn by qrencode into the runtime
# directory; without qrencode the page shows no code.
set -u
RUN=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/omamobile-hotspot
QR=$RUN/wifi-qr.png
NM_CON=${OMAMOBILE_HOTSPOT_CONNECTION:-Hotspot}

json_str() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }

backend=""
for b in "${XDG_CONFIG_HOME:-$HOME/.config}/omamobile/hotspot-backend" /etc/omamobile/hotspot-backend; do
  [[ -x $b ]] && { backend=$b; break; }
done

# ---- NetworkManager
nm_read() {
  ssid=$(nmcli -s -g 802-11-wireless.ssid connection show "$NM_CON" 2>/dev/null)
  psk=$(nmcli -s -g 802-11-wireless-security.psk connection show "$NM_CON" 2>/dev/null)
}
nm_active() { nmcli -t -f NAME connection show --active 2>/dev/null | grep -qx "$NM_CON"; }
nm_state() {
  nm_read
  hotspot=off; nm_active && hotspot=on
  vpn=off; nmcli -t -f TYPE connection show --active 2>/dev/null | grep -qE '^(vpn|wireguard)$' && vpn=on
  editable=true; [[ -n $ssid ]] || editable=false
  clients=0
  if [[ $hotspot == on ]]; then
    local dev
    dev=$(nmcli -t -f DEVICE,NAME connection show --active 2>/dev/null | awk -F: -v c="$NM_CON" '$2 == c { print $1; exit }')
    [[ -n $dev ]] && clients=$(iw dev "$dev" station dump 2>/dev/null | grep -c '^Station')
  fi
  printf '{"backend":"networkmanager","hotspot":"%s","vpn":"%s","share":"off","share_available":false,"prefer_share":false,"all_traffic_available":false,"all_traffic":false,"editable":%s,"ssid":%s,"psk":%s,"clients":%s}\n' \
    "$hotspot" "$vpn" "$editable" "$(json_str "$ssid")" "$(json_str "$psk")" "${clients:-0}"
}
nm_set() {
  if ! nmcli connection modify "$NM_CON" 802-11-wireless.ssid "$1" 802-11-wireless-security.psk "$2" >/dev/null 2>&1; then
    echo "error: NetworkManager refused the change"; return
  fi
  if nm_active; then
    nmcli connection up "$NM_CON" >/dev/null 2>&1 && echo "ok: hotspot restarted with the new name and password" || echo "error: the hotspot did not restart"
  else
    echo "ok: saved; applies when the hotspot is turned on"
  fi
}
nm_share() { echo "error: sharing a VPN isn't available with this hotspot"; }

# ---- the QR code, added to whichever backend answered
# WIFI: strings escape \ ; , : and "
qr_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/;/\\;/g' -e 's/,/\\,/g' -e 's/:/\\:/g' -e 's/"/\\"/g'; }
with_qr() { # reads the state line on stdin, prints it with qr and qr_rev
  python3 -c '
import json, os, subprocess, sys
s = json.loads(sys.stdin.readline() or "{}")
run, qr = sys.argv[1], sys.argv[2]
s.setdefault("qr", ""); s.setdefault("qr_rev", 0)
ssid, psk = s.get("ssid") or "", s.get("psk") or ""
def esc(v): return "".join("\\" + c if c in "\\;,:\"" else c for c in v)
want = "WIFI:T:WPA;S:%s;P:%s;;" % (esc(ssid), esc(psk))
if ssid:
    try:
        os.makedirs(run, mode=0o700, exist_ok=True)
        src = os.path.join(run, "wifi-qr.src")
        old = open(src).read() if os.path.exists(src) else None
        if old != want or not os.path.exists(qr):
            fd = os.open(src, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600); os.write(fd, want.encode()); os.close(fd)
            subprocess.run(["qrencode", "-o", qr, "-s", "8", "-m", "2", "-l", "M", want], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            os.chmod(qr, 0o600)
        s["qr"] = qr; s["qr_rev"] = int(os.stat(qr).st_mtime)
    except Exception:
        s["qr"] = ""; s["qr_rev"] = 0
print(json.dumps(s))' "$RUN" "$QR"
}

case ${1:-} in
  state)
    if [[ -n $backend ]]; then "$backend" state; else nm_state; fi | with_qr
    ;;
  set)
    name=${2:-}; pass=${3:-}
    if [[ -z $name || ${#name} -gt 32 ]]; then echo "error: the network name must be 1 to 32 characters"; exit 1; fi
    if [[ ${#pass} -lt 8 || ${#pass} -gt 63 ]]; then echo "error: the password must be 8 to 63 characters"; exit 1; fi
    if [[ -n $backend ]]; then "$backend" set "$name" "$pass"; else nm_set "$name" "$pass"; fi
    rm -f "$QR"
    ;;
  share|alltraffic)
    case ${2:-} in on|off) ;; *) echo "usage: hotspot-panel.sh $1 on|off" >&2; exit 2 ;; esac
    if [[ -n $backend ]]; then "$backend" "$1" "$2"; else nm_share; fi
    ;;
  *) echo "usage: hotspot-panel.sh state | set NAME PASSWORD | share on|off | alltraffic on|off" >&2; exit 2 ;;
esac
