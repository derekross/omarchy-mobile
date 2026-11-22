#!/bin/bash
# SPDX-License-Identifier: MIT
# backends/security.sh and libexec/firewall against stub commands on PATH and a scratch /etc: nothing on the host is read
# or changed, no unit is started.
set -euo pipefail
src=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/root/etc/ufw" "$tmp/root/etc/default" "$tmp/root/usr/bin"
sed "s|^fake=''|fake='$tmp/root'|" "$src/backends/security.sh" > "$tmp/security.sh"
grep -q "^fake='$tmp/root'" "$tmp/security.sh"
: > "$tmp/root/usr/bin/ufw"; chmod +x "$tmp/root/usr/bin/ufw"
printf '# x\nENABLED=yes\nLOGLEVEL=low\n' > "$tmp/root/etc/ufw/ufw.conf"
printf 'IPV6=yes\n' > "$tmp/root/etc/default/ufw"
rules4() { cat > "$tmp/root/etc/ufw/user.rules" <<'EOT'
*filter
-A ufw-user-input -p udp --dport 53317 -j ACCEPT
-A ufw-user-input -i usb0 -p tcp --dport 22 -j ACCEPT
-A ufw-user-input -i wlp1s0 -p tcp -m tcp --dport 22 -s 10.0.0.0/24 -j ACCEPT
-A ufw-user-input -i wlp1s0 -p udp --dport 5353 -s 10.0.0.0/24 -j ACCEPT
-A ufw-user-input -i usb0 -p tcp --dport 22 -j ACCEPT"; touch /tmp/x
COMMIT
EOT
}
rules6() { printf '%s\n' '-A ufw6-user-input -p tcp --dport 53317 -j ACCEPT' '-A ufw6-user-input -i usb0 -p tcp --dport 22 -j ACCEPT' > "$tmp/root/etc/ufw/user6.rules"; }
rules4; rules6
cat > "$tmp/bin/systemctl" <<'EOT'
#!/bin/bash
c=$(cat "$CASE_FILE")
[[ $c == broken && $* == *sshd* ]] && exit 1
case $* in
  "is-active sshd.service") [[ $c == sshoff || $c == socket ]] && { echo inactive; exit 3; }; echo active ;;
  "is-enabled sshd.service") [[ $c == sshoff || $c == socket ]] && { echo disabled; exit 1; }; echo enabled ;;
  "is-enabled sshd.socket") [[ $c == socket ]] && { echo enabled; exit 0; }; echo disabled; exit 1 ;;
  "is-active omamobile-hotspot.service") [[ $c == hotspot ]] && { echo active; exit 0; }; echo inactive; exit 3 ;;
  "is-active "*) echo inactive; exit 3 ;;
  *) echo "unexpected: $*" >&2; exit 1 ;;
esac
EOT
# ufw stub for the helper: writes ENABLED= like the real one, logs its arguments
cat > "$tmp/bin/ufw" <<'EOT'
#!/bin/bash
echo "$*" >> "$UFW_LOG"
case $* in
  "--force enable") sed -i 's/^ENABLED=.*/ENABLED=yes/' "$OMAMOBILE_FIREWALL_ROOT/etc/ufw/ufw.conf" ;;
  disable) sed -i 's/^ENABLED=.*/ENABLED=no/' "$OMAMOBILE_FIREWALL_ROOT/etc/ufw/ufw.conf" ;;
  *) exit 1 ;;
esac
EOT
chmod +x "$tmp/bin/"*
export CASE_FILE=$tmp/case UFW_LOG=$tmp/ufw.log
# env -i: only the stubs, /usr/bin, a scratch HOME and the stubs' two files reach the scripts
mkdir -p "$tmp/home"
clean=(env -i HOME="$tmp/home" PATH="$tmp/bin:/usr/bin" CASE_FILE="$CASE_FILE" UFW_LOG="$UFW_LOG")
run() { "${clean[@]}" /usr/bin/bash "$tmp/security.sh" "$@" || true; }
eq() { [[ $1 == "$2" ]] || { echo "FAIL: got $1, want $2" >&2; exit 1; }; }
has() { [[ $1 == *"$2"* ]] || { echo "FAIL: $1 lacks $2" >&2; exit 1; }; }

echo normal > "$CASE_FILE"
eq "$(run get)" '{"firewall":"on","ssh_active":"active","ssh_enabled":"enabled","ssh_allowed":["USB","Wi-Fi from 10.0.0.0/24"],"usb_ssh_rule":true,"hotspot":false,"can_enable":true,"why":""}'
# off, then on, through the scratch conf; the rules files are not touched
sum=$(cat "$tmp/root/etc/ufw/user.rules" "$tmp/root/etc/ufw/user6.rules" | sha256sum)
has "$(run set firewall off)" '"firewall":"off"'
has "$(run set firewall on)" '"firewall":"on"'
# the firewall line alone (what Developer options shows)
eq "$(run firewall)" on
has "$(run firewall x)" '"error":"usage: firewall"'
eq "$(cat "$tmp/root/etc/ufw/user.rules" "$tmp/root/etc/ufw/user6.rules" | sha256sum)" "$sum"
# bad arguments
has "$(run set firewall maybe)" '"error":"bad value"'
has "$(run set ssh off)" '"error":"usage: set firewall on|off"'
has "$(run set firewall)" '"error"'
has "$(run get x)" '"error":"usage: get"'
has "$(run probe)" '"error"'
# no IPv6 usb0 rule with IPV6=yes: on is refused, off still works
run set firewall off >/dev/null
printf '%s\n' '-A ufw6-user-input -p tcp --dport 53317 -j ACCEPT' > "$tmp/root/etc/ufw/user6.rules"
out=$(run get); has "$out" '"usb_ssh_rule":false'; has "$out" '"can_enable":false'
has "$(run set firewall on)" '"error":"SSH is on and no firewall rule lets it in over USB'
grep -q '^ENABLED=no' "$tmp/root/etc/ufw/ufw.conf"
# ... unless IPv6 is off in ufw, or sshd is off and disabled
printf 'IPV6=no\n' > "$tmp/root/etc/default/ufw"; has "$(run get)" '"can_enable":true'
printf 'IPV6=yes\n' > "$tmp/root/etc/default/ufw"
echo sshoff > "$CASE_FILE"; has "$(run get)" '"can_enable":true'; has "$(run get)" '"ssh_active":"inactive"'
rules6
# the hotspot running: on refused
echo hotspot > "$CASE_FILE"
out=$(run get); has "$out" '"hotspot":true'; has "$out" '"can_enable":false'
has "$(run set firewall on)" '"error":"Stop the hotspot first'
has "$(run set firewall off)" '"firewall":"off"'
# not installed
echo normal > "$CASE_FILE"; rm "$tmp/root/usr/bin/ufw"
has "$(run get)" '"firewall":"not installed"'
has "$(run set firewall off)" '"error":"UFW is not installed"'
: > "$tmp/root/usr/bin/ufw"; chmod +x "$tmp/root/usr/bin/ufw"
# a broken ENABLED= line
printf 'ENABLED=maybe\n' > "$tmp/root/etc/ufw/ufw.conf"; has "$(run get)" '"firewall":"unknown"'
# the JSON is valid
python3 -I -c 'import json,sys; json.loads(sys.argv[1])' "$(run get)"

# the root helper
printf 'ENABLED=yes\n' > "$tmp/root/etc/ufw/ufw.conf"
helper() { "${clean[@]}" OMAMOBILE_FIREWALL_ROOT="$tmp/root" /usr/bin/bash "$src/libexec/firewall" "$@"; }
helper off >/dev/null; grep -q '^ENABLED=no' "$tmp/root/etc/ufw/ufw.conf"
helper on >/dev/null; grep -q '^ENABLED=yes' "$tmp/root/etc/ufw/ufw.conf"
nok() { if helper "$@" >/dev/null 2>&1; then echo "FAIL: helper $* succeeded" >&2; exit 1; fi; }
nok maybe
nok on off
helper off >/dev/null
printf '%s\n' '-A ufw6-user-input -p tcp --dport 53317 -j ACCEPT' > "$tmp/root/etc/ufw/user6.rules"
: > "$UFW_LOG"
nok on
[[ ! -s $UFW_LOG ]] || { echo "FAIL: ufw ran though the IPv6 SSH rule is missing" >&2; exit 1; }
rules6; echo hotspot > "$CASE_FILE"
nok on
[[ ! -s $UFW_LOG ]] || { echo "FAIL: ufw ran while the hotspot runs" >&2; exit 1; }
helper off >/dev/null
eq "$(cat "$UFW_LOG")" disable
if "${clean[@]}" OMAMOBILE_FIREWALL_ROOT=/ /usr/bin/bash "$src/libexec/firewall" off; then echo "FAIL: root / accepted" >&2; exit 1; fi
# sshd off and disabled: no rule needed; a usb0 rule limited to a source does not count
echo sshoff > "$CASE_FILE"; : > "$tmp/root/etc/ufw/user6.rules"; helper on >/dev/null; helper off >/dev/null
echo normal > "$CASE_FILE"; rules6
printf '%s\n' '-A ufw-user-input -i usb0 -p tcp --dport 22 -s 10.1.0.0/16 -j ACCEPT' > "$tmp/root/etc/ufw/user.rules"
nok on
out=$(run get); has "$out" '"usb_ssh_rule":false'; has "$out" '"ssh_allowed":["USB from 10.1.0.0/16","USB"]'
python3 -I -c 'import json,sys; json.loads(sys.argv[1])' "$out"
# a failing systemctl (sshd state unreadable) counts as SSH on
echo broken > "$CASE_FILE"
out=$(run get); has "$out" '"can_enable":false'
rules4

# --- the USB SSH guard, the same answer from the backend and the root helper ---
v4() { printf '%s\n' "$@" > "$tmp/root/etc/ufw/user.rules"; }
allowed() {   # $1: what is checked; on is allowed by both
  local out; out=$(run get)
  has "$out" '"usb_ssh_rule":true'; has "$out" '"can_enable":true'
  helper on >/dev/null 2>&1 || { echo "FAIL: helper refused: $1" >&2; exit 1; }
  helper off >/dev/null
}
refused() {   # $1: what is checked; on is refused by both, and ufw is not run
  local out; out=$(run get)
  has "$out" '"can_enable":false'
  : > "$UFW_LOG"; nok on
  [[ ! -s $UFW_LOG ]] || { echo "FAIL: ufw ran: $1" >&2; exit 1; }
}
usb='-A ufw-user-input -i usb0 -p tcp --dport 22 -j ACCEPT'
echo normal > "$CASE_FILE"; rules6; printf 'IPV6=yes\n' > "$tmp/root/etc/default/ufw"; printf 'ENABLED=no\n' > "$tmp/root/etc/ufw/ufw.conf"
v4 "$usb"; allowed "a plain usb0 allow"
# the line with trailing garbage, alone: not a rule
v4 '-A ufw-user-input -i usb0 -p tcp --dport 22 -j ACCEPT"; touch /tmp/x'; has "$(run get)" '"usb_ssh_rule":false'; refused "trailing garbage"
# commented out, another interface
v4 "# $usb"; refused "a commented allow"
v4 '-A ufw-user-input -i usb1 -p tcp --dport 22 -j ACCEPT'; refused "usb1"
# deny before allow: ufw takes the first match
v4 '-A ufw-user-input -p tcp --dport 22 -j DROP' "$usb"; has "$(run get)" '"usb_ssh_rule":false'; refused "DROP 22 before the allow"
v4 '-A ufw-user-input -i usb0 -j REJECT --reject-with tcp-reset' "$usb"; refused "REJECT all on usb0 before the allow"
v4 '-A ufw-user-input -p tcp --dport 20:30 -s 0.0.0.0/0 -j DROP' "$usb"; refused "a port range with any source before the allow"
# ... but not one that can't match, nor one after the allow
# a deny with any source counts (the USB peer's address isn't known), as do a negation and a port name
v4 '-A ufw-user-input -p tcp --dport 22 -s 10.9.0.0/16 -j DROP' "$usb"; refused "a source-limited DROP before the allow"
v4 '-A ufw-user-input -p tcp ! --dport 80 -j DROP' "$usb"; refused "a ! --dport 80 DROP before the allow"
v4 '-A ufw-user-input -p tcp --dport ssh -j DROP' "$usb"; refused "a --dport ssh DROP before the allow"
# a ufw limit rule on usb0 is not the USB allow
v4 '-A ufw-user-input -i usb0 -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --set' \
   '-A ufw-user-input -i usb0 -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --update --seconds 30 --hitcount 6 -j ufw-user-limit' \
   '-A ufw-user-input -i usb0 -p tcp --dport 22 -j ufw-user-limit-accept'
has "$(run get)" '"usb_ssh_rule":false'; refused "a limit rule on usb0 only"
# the allow on a last line with no newline: both read it
printf '%s' "$usb" > "$tmp/root/etc/ufw/user.rules"; allowed "an allow on a last line without a newline"
printf '%s\n%s' "$usb" '-A ufw-user-input -p tcp --dport 22 -j DROP' > "$tmp/root/etc/ufw/user.rules"; allowed "a deny after it on such a line"
printf '%s\n%s' '-A ufw-user-input -p tcp --dport 22 -j DROP' "$usb" > "$tmp/root/etc/ufw/user.rules"; refused "a deny before an allow on such a line"
v4 '-A ufw-user-input -i wlan0 -p tcp --dport 22 -j DROP' \
   '-A ufw-user-input -p udp --dport 22 -j DROP' '-A ufw-user-input -p tcp --dport 80 -j DROP' "$usb"; allowed "denies that can't match tcp 22 on usb0"
v4 "$usb" '-A ufw-user-input -p tcp --dport 22 -j DROP'; allowed "a deny after the allow"
# the same in user6.rules
v4 "$usb"; printf '%s\n' '-A ufw6-user-input -p tcp --dport 22 -j DROP' '-A ufw6-user-input -i usb0 -p tcp --dport 22 -j ACCEPT' > "$tmp/root/etc/ufw/user6.rules"
refused "an IPv6 DROP before the IPv6 allow"; rules6
# IPV6= read like ufw: lowercased, quotes stripped, ufw.conf after /etc/default/ufw; a line ufw skips counts as yes
printf '%s\n' '-A ufw6-user-input -p tcp --dport 53317 -j ACCEPT' > "$tmp/root/etc/ufw/user6.rules"
for line in 'IPV6=YES' 'IPV6="yes"' "IPV6='yes'" 'ipv6=yes'; do
  printf '%s\n' "$line" > "$tmp/root/etc/default/ufw"; refused "$line without an IPv6 usb0 rule"
done
printf 'IPV6=no\n' > "$tmp/root/etc/default/ufw"; allowed "IPV6=no"
printf 'ENABLED=no\nIPV6=yes #keep\n' > "$tmp/root/etc/ufw/ufw.conf"; refused "IPV6=yes #keep in ufw.conf"
printf 'ENABLED=no\n' > "$tmp/root/etc/ufw/ufw.conf"
printf 'IPV6=no\n' > "$tmp/root/etc/default/ufw"; printf 'ENABLED=no\nIPV6=yes\n' > "$tmp/root/etc/ufw/ufw.conf"; refused "IPV6=yes in ufw.conf after no in the defaults"
printf 'IPV6=yes\n' > "$tmp/root/etc/default/ufw"; printf 'ENABLED=no\nIPV6=no\n' > "$tmp/root/etc/ufw/ufw.conf"; allowed "IPV6=no in ufw.conf after yes in the defaults"
printf 'IPV6=yes\n' > "$tmp/root/etc/default/ufw"; printf 'ENABLED=no\n' > "$tmp/root/etc/ufw/ufw.conf"; rules6
# SSH counted as on: sshd.socket enabled with the service off, and systemctl that can't be read
v4 '-A ufw-user-input -p tcp --dport 53317 -j ACCEPT'
echo sshoff > "$CASE_FILE"; allowed_off=$(run get); has "$allowed_off" '"can_enable":true'
echo socket > "$CASE_FILE"; refused "sshd.socket enabled"
echo broken > "$CASE_FILE"; refused "systemctl failing"
echo normal > "$CASE_FILE"; rules4
echo "security backend ok"
