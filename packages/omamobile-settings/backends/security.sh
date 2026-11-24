#!/bin/bash
# SPDX-License-Identifier: MIT
# Firewall & SSH for the Settings app's Security & privacy page. Prints one line of JSON.
#   security.sh get
#     {"firewall":"on|off|not installed","ssh_active":"active","ssh_enabled":"enabled",
#      "ssh_allowed":["USB","Wi-Fi from 10.0.0.0/24"],"usb_ssh_rule":true,"hotspot":false,"can_enable":true,"why":""}
#   security.sh firewall   on|off|not installed|unknown, the firewall line alone (for a one-line status; no command
#     is run, only ufw.conf is read)
#   security.sh set firewall on|off
#     saved and applied as root by omamobile-firewall@on|off.service (the polkit rule 50-omamobile-firewall.rules lets
#     the active local user start those two and nothing else, and asks for the admin PIN through the shell's polkit
#     prompt both ways), then read back; prints the get answer. A PIN prompt that is cancelled or fails gives
#     {"error":"not changed: the PIN was not entered",...} with the state read again.
# The firewall state is ENABLED= in /etc/ufw/ufw.conf (what `ufw enable|disable` writes and what ufw.service applies at
# boot). ufw.service is a oneshot with RemainAfterExit, so its "active" does not change on `ufw disable` and is not used.
# SSH is shown, never switched: USB SSH is the same sshd as any other SSH, so a switch here could take away the only
# way into a phone under development. The rules that let port 22 in are read from /etc/ufw/user.rules and
# user6.rules (mode 644; `ufw status` needs root and is not called).
# Turning the firewall on is refused (here, and again in the root helper) while sshd.service or sshd.socket is enabled
# or running (or can't be read) and there is no rule letting port 22 in on usb0 ahead of any rule that could drop it
# (both IPv4 and, when ufw uses IPv6, IPv6), and while the hotspot runs (its own UFW rules
# are added only when it starts with the firewall on). Turning it off is never refused.
# The test runs a copy of this script with `fake` set to a scratch root for /etc and /usr/bin, and stub commands on PATH;
# `set` still calls the (stub) systemctl start, then writes ENABLED= in the scratch ufw.conf in place of the root
# helper. Nothing in the environment sets it.
set -euo pipefail
set +x
export LC_ALL=C
verb=${1:-}; key=${2:-}; value=${3:-}
fail() { printf '{"error":"%s"}\n' "$1"; exit 2; }
fake=''
[[ -z $fake || -d $fake ]] || fail "cannot read the test root"
conf=$fake/etc/ufw/ufw.conf
defaults=$fake/etc/default/ufw
rules4=$fake/etc/ufw/user.rules
rules6=$fake/etc/ufw/user6.rules

word() { local v=$1; shift; local o; o=$("$@" 2>/dev/null) || true; o=${o%%$'\n'*};
  [[ $o =~ ^($v)$ ]] && printf '%s' "$o" || printf 'unknown'; }
units='active|inactive|failed|activating|deactivating|reloading|maintenance|refreshing'

firewall_state() {
  [[ -x $fake/usr/bin/ufw && -r $conf ]] || { echo 'not installed'; return; }
  local v; v=$(sed -n 's/^ENABLED=//p' "$conf" 2>/dev/null | tail -n 1) || v=''; v=${v//\"/}
  case $v in yes) echo on ;; no) echo off ;; *) echo unknown ;; esac
}

# ufw's chains are first match: a DROP, REJECT or limit line that could match tcp port 22 on usb0 (no -i or -i usb0,
# any source, since the USB peer's address isn't known here; tcp or all; port 22, no port, or anything but a plain
# number, such as a range or a service name; any line with a `!`) ahead of the usb0 allow means it is never reached.
# backends/security.sh and libexec/firewall keep the same copy of this and of ipv6_yes.
could_deny() {
  local l=$1 v
  [[ $l =~ ^-A\ ufw6?-user-input\  && $l =~ \ -j\ (DROP|REJECT|ufw6?-user-limit)(\ |$) ]] || return 1
  [[ $l == *" ! "* ]] && return 0   # a negation (! -p, ! --dport, ! -s ...) is not read: it could match
  if [[ $l =~ \ -i\ ([^ ]+) ]]; then [[ ${BASH_REMATCH[1]} == usb0 ]] || return 1; fi
  if [[ $l =~ \ -p\ ([^ ]+) ]]; then [[ ${BASH_REMATCH[1]} =~ ^(tcp|all|6)$ ]] || return 1; fi
  if [[ $l =~ \ --dport\ ([^ ]+) ]]; then v=${BASH_REMATCH[1]}; [[ $v =~ ^[0-9]+$ && $v != 22 ]] && return 1; fi
  return 0
}
# ufw reads /etc/default/ufw, then /etc/ufw/ufw.conf (a later IPV6= wins). A line counts when it matches ufw's pattern
# ^\w+="?\w+"?; the key and value are lowercased and quotes stripped, and IPv6 is used only for "yes"
# (ufw/backend.py _get_defaults, use_ipv6). The value is the word that pattern matches. An IPV6= line ufw would skip
# (IPV6='yes') is taken as yes here: asking for the IPv6 rule too is the safe side.
ipv6_yes() {
  local f line key val r=''
  for f in "$1" "$2"; do
    [[ -r $f ]] || continue
    while IFS= read -r line || [[ -n $line ]]; do
      key=${line%%=*}
      [[ $line == *=* && ${key,,} == ipv6 ]] || continue
      # the word ufw's pattern matches: IPV6=yes #keep reads yes (requiring the IPv6 rule is the safe side)
      if [[ $line =~ ^[A-Za-z0-9_]+=\"?([A-Za-z0-9_]+) ]]; then
        r=${BASH_REMATCH[1],,}
      else
        r=yes
      fi
    done < <(head -c 65536 -- "$f" 2>/dev/null)
  done
  [[ $r == yes ]]
}

# SSH allow rules: "-A ufw-user-input [-i IF] -p tcp( -m tcp)? --dport 22 [-s SRC] -j ACCEPT". A `ufw limit` rule
# (its ufw-user-limit line comes first) is not an allow here.
ssh_re='^-A ufw6?-user-input( -i ([A-Za-z0-9._-]{1,15}))? -p tcp( -m tcp)? --dport 22( -s ([0-9A-Fa-f.:/]{1,49}))? -j ACCEPT$'
labels=() usb4=0 usb6=0
add_label() { local l=$1 x; for x in "${labels[@]}"; do [[ $x == "$l" ]] && return; done; labels+=("$l"); }
read_rules() {
  local file=$1 v6=$2 line ifc src name denied=0
  [[ -r $file ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    could_deny "$line" && denied=1
    [[ $line =~ $ssh_re ]] || continue
    ifc=${BASH_REMATCH[2]} src=${BASH_REMATCH[5]}
    case $ifc in
      '') name='any network' ;;
      usb0) name=USB; if [[ -z $src ]] && ((!denied)); then ((v6)) && usb6=1 || usb4=1; fi ;;
      wl*) name=Wi-Fi ;;
      *) name=$ifc ;;
    esac
    [[ -n $src ]] && name+=" from $src"
    add_label "$name"
  done < <(head -c 262144 "$file")
}

get() {
  local fw ssh_active ssh_enabled sock_active sock_enabled hotspot=false usb_rule=false can=true why='' list='' first=1 l
  fw=$(firewall_state)
  ssh_active=$(word "$units" timeout 2 systemctl is-active sshd.service)
  local enabled='enabled|enabled-runtime|disabled|static|masked|indirect|generated|alias|linked|linked-runtime|masked-runtime|transient|bad|not-found'
  ssh_enabled=$(word "$enabled" timeout 2 systemctl is-enabled sshd.service)
  # socket activation: sshd.socket starts sshd on the first connection, so it counts as SSH on as well
  sock_active=$(word "$units|listening" timeout 2 systemctl is-active sshd.socket)
  sock_enabled=$(word "$enabled" timeout 2 systemctl is-enabled sshd.socket)
  # anything but stopped counts as running: a hotspot that is starting may already have seen the firewall off
  [[ $(word "$units" timeout 2 systemctl is-active omamobile-hotspot.service) =~ ^(inactive|failed)$ ]] || hotspot=true
  read_rules "$rules4" 0
  read_rules "$rules6" 1
  if ((usb4)) && { ! ipv6_yes "$defaults" "$conf" || ((usb6)); }; then usb_rule=true; fi
  if [[ $fw == 'not installed' ]]; then can=false; why='UFW is not installed.'
  elif [[ $hotspot == true ]]; then can=false; why='Stop the hotspot first: it opens the firewall for its clients only when it starts.'
  # sshd counts as off only when it is clearly stopped and clearly not started at boot (a failed read counts as on)
  elif [[ $usb_rule == false ]] && ! [[ $ssh_active =~ ^(inactive|failed)$ && $ssh_enabled =~ ^(disabled|masked|not-found)$
                                       && $sock_active =~ ^(inactive|failed)$ && $sock_enabled =~ ^(disabled|masked|not-found)$ ]]; then
    can=false; why='SSH is on and no firewall rule lets it in over USB, so turning the firewall on could lock SSH out.'
  fi
  for l in "${labels[@]}"; do ((first)) || list+=,; first=0; list+="\"$l\""; done
  printf '{"firewall":"%s","ssh_active":"%s","ssh_enabled":"%s","ssh_allowed":[%s],"usb_ssh_rule":%s,"hotspot":%s,"can_enable":%s,"why":"%s"}\n' \
    "$fw" "$ssh_active" "$ssh_enabled" "$list" "$usb_rule" "$hotspot" "$can" "$why"
}

case $verb in
get) (( $# == 1 )) || fail "usage: get"; get ;;
firewall) (( $# == 1 )) || fail "usage: firewall"; firewall_state ;;
set)
  (( $# == 3 )) && [[ $key == firewall ]] || fail "usage: set firewall on|off"
  [[ $value == on || $value == off ]] || fail "bad value"
  state=$(get)
  [[ $state == *'"firewall":"not installed"'* ]] && fail "UFW is not installed"
  if [[ $value == on && $state != *'"can_enable":true'* ]]; then
    why=${state##*\"why\":\"}; fail "${why%\"\}}"
  fi
  # a failed set prints the state read again, with the error, so the page never keeps a stale state
  setfail() { local st; st=$(get); printf '{"error":"%s",%s\n' "$1" "${st#\{}"; exit 2; }
  # systemctl may ask for a password here: the polkit rule answers AUTH_ADMIN_KEEP, so systemctl asks the session's polkit agent (the
  # shell's PIN pad) and waits for the owner. The unit's own limit is TimeoutStartSec=60 once it starts; the owner gets
  # about 60 s more to type the PIN, so 122 s is the backstop. With the two reads around it (five systemctl calls of at
  # most 2 s each: 10 s) and the read of a failed set (10 s more), a set ends by 10 + 122 + 10 + 10 = 152 s; the app's
  # runner kills it at 160 s.
  err=$(timeout 122 systemctl start "omamobile-firewall@$value.service" 2>&1 >/dev/null) || {
    # a cancelled, failed or unanswered PIN prompt: systemctl says "Access denied" or "Interactive authentication
    # required"; timeout's 124 is a prompt nobody answered
    rc=$?
    if [[ $err == *'Access denied'* || $err == *'nteractive authentication'* || $rc == 124 ]]; then
      setfail "not changed: the PIN was not entered"
    fi
    setfail "could not turn the firewall $value"
  }
  if [[ -n $fake ]]; then
    [[ $value == on ]] && v=yes || v=no
    sed -i "s/^ENABLED=.*/ENABLED=$v/" "$conf"
  fi
  state=$(get)
  [[ $state == *"\"firewall\":\"$value\""* ]] || setfail "the firewall did not turn $value"
  printf '%s\n' "$state" ;;
*) fail "usage: get|firewall|set" ;;
esac
