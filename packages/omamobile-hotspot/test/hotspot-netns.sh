#!/bin/bash
# SPDX-License-Identifier: MIT
# lib/hotspot-ap's client isolation on a real kernel with real nft, in a user + network + mount namespace of its own
# (unshare -rnm), so it runs as a normal user and touches nothing outside. Where namespaces or the tools aren't
# available it prints a "skip -" line and exits 0; test/all shows that line.
#   ns c (client 10.42.0.23) --ap0-- this ns ("phone") --wlp-- ns i (uplink, 198.51.100.1 on lo, route back to 10.42/24)
# Checks: I0 without isolation the LAN is reachable (so the checks have teeth), I1 isolation on, I4 the README's limit
# (an on-link split default fails closed), I3 cleared.
set -uo pipefail
HAP=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)/lib/hotspot-ap
skip() { echo "skip - hotspot-netns: $*"; exit 0; }
if [[ ${OMAMOBILE_HOTSPOT_NETNS_IN:-} != 1 ]]; then
  for t in unshare ip nft ping python3 timeout; do command -v "$t" >/dev/null 2>&1 || skip "no $t"; done
  unshare -rnm true 2>/dev/null || skip "user namespaces not allowed here (unshare -rnm)"
  OMAMOBILE_HOTSPOT_NETNS_IN=1 exec unshare -rnm bash "$0" "$@"
fi
tmp=$(mktemp -d); trap 'kill ${PH22:-} ${PH53:-} ${PI22:-} 2>/dev/null; rm -rf -- "$tmp"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
ok() { echo "ok - $*"; }
# namespace plumbing; anything refused here is the environment, not the helper
mount -t tmpfs none /run 2>/dev/null && mkdir -p /run/netns || skip "can't mount /run in the namespace"
ip link set lo up || skip "no network namespace"
for n in c i; do ip netns add $n 2>/dev/null && ip -n $n link set lo up || skip "ip netns refused (ip -n mounts /sys)"; done
ip netns exec c true 2>/dev/null || skip "ip netns exec refused (it mounts /sys)"
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || skip "net.ipv4.ip_forward not writable in the namespace"
nft add table inet probe 2>/dev/null && nft delete table inet probe || skip "nft refused in the namespace"
ip link add ap0 type veth peer name eth0 netns c
ip link add wlp type veth peer name eth0 netns i
ip addr add 10.42.0.1/24 dev ap0; ip link set ap0 up
ip addr add 192.168.50.1/24 dev wlp; ip link set wlp up
ip -n c addr add 10.42.0.23/24 dev eth0; ip -n c link set eth0 up; ip -n c route add default via 10.42.0.1
ip -n i addr add 192.168.50.2/24 dev eth0; ip -n i link set eth0 up; ip -n i addr add 198.51.100.1/32 dev lo
ip -n i route add 10.42.0.0/24 via 192.168.50.1
ip route add default via 192.168.50.2 dev wlp
# client packets seen at the plain uplink's far end (ns i), by source address: the leak counter (ARP and the phone's
# own neighbour probes don't count)
ip netns exec i nft -f - <<'NFT'
table inet leak {
  chain pre {
    type filter hook prerouting priority -300;
    ip saddr 10.42.0.0/24 counter
  }
}
NFT
leaks() { ip netns exec i nft -j list chain inet leak pre | python3 -c 'import json,sys; print([e["rule"]["expr"][1]["counter"]["packets"] for e in json.load(sys.stdin)["nftables"] if "rule" in e][0])'; }
rx() { ip -n "$1" -s -j link show eth0 | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["stats64"]["rx"]["packets"])'; }
ping_c() { ip netns exec c ping -c 2 -W 1 -q 198.51.100.1 >/dev/null 2>&1; }

# the helper's functions (everything above run()), not its main
RUN=$tmp/run; mkdir -p "$RUN"; export OMAMOBILE_HOTSPOT_RUN=$RUN OMAMOBILE_HOTSPOT_SYSCTL=/proc/sys/net/ipv4/conf
eval "$(sed -n '/^set -uo pipefail/,/^run() {/p' "$HAP" | sed '$d' | grep -v '^if \[\[ \${1:-} == down')"
command -v iso_sync >/dev/null || fail "no client isolation in this hotspot-ap"
AP=ap0

# 0. the client goes out the phone's default route (wlp)
ping_c || fail "no forwarding at all"
ok "the client reaches the internet over wlp"

# home LAN on the uplink's own subnet (192.168.50.0/24, the phone 192.168.50.1, ns i 192.168.50.2), a LAN host behind it
# (192.168.1.5 on ns i's lo, routed via wlp)
ip -n i addr add 192.168.1.5/32 dev lo; ip route add 192.168.1.0/24 via 192.168.50.2 dev wlp
ip -n i addr add 198.18.0.5/32 dev lo; ip route add 198.18.0.0/15 via 192.168.50.2 dev wlp
ping_to() { ip netns exec c ping -c 1 -W 1 -q "$1" >/dev/null 2>&1; }
tcp_to() { ip netns exec c timeout 2 bash -c "echo x > /dev/tcp/$1/$2" >/dev/null 2>&1; }
udp_dns_ok() { ip netns exec c timeout 2 python3 -c 'import socket,sys;s=socket.socket(2,2);s.settimeout(1);s.sendto(b"q",(sys.argv[1],53));s.recv(9)' "$1" >/dev/null 2>&1; }

# I0. without isolation (the old behaviour): the LAN is reachable, the check below has teeth
ping_to 192.168.50.2 || fail "setup: the uplink's LAN not reachable before isolation"
ping_to 192.168.1.5 || fail "setup: the LAN host not reachable before isolation"
ping_to 198.18.0.5 || fail "setup: the 198.18/15 host not reachable before isolation"
ip netns exec i python3 -c 'import socket;s=socket.socket();s.setsockopt(1,2,1);s.bind(("0.0.0.0",22));s.listen(5);[s.accept()[0].close() for _ in iter(int,1)]' & PI22=$!
python3 -c 'import socket;s=socket.socket();s.setsockopt(1,2,1);s.bind(("0.0.0.0",22));s.listen(5);[s.accept()[0].close() for _ in iter(int,1)]' & PH22=$!
python3 -c 'import socket;s=socket.socket(2,2);s.bind(("0.0.0.0",53));[s.sendto(b"a",a) for d,a in iter(lambda:s.recvfrom(9),None)]' & PH53=$!
sleep 0.5
tcp_to 10.42.0.1 22 || fail "setup: the phone's port 22 not reachable before isolation"
tcp_to 192.168.50.1 22 || fail "setup: the phone's uplink address not reachable before isolation"
udp_dns_ok 10.42.0.1 || fail "setup: DNS on the phone not answering"
ok "before isolation: the client reaches the LAN, the phone's ssh port and the phone's uplink address (the gap)"

# I1. isolation on
iso_sync || fail "iso_sync"
ping_c || fail "the internet (198.51.100.1, TEST-NET) is blocked by isolation"
ok "isolation: the client still reaches the internet over the uplink"
ping_to 192.168.50.2 && fail "the uplink's own subnet (home LAN) reachable"
ping_to 192.168.1.5 && fail "a private LAN host behind the uplink reachable"
tcp_to 192.168.1.5 22 && fail "tcp to a LAN host"
ping_to 198.18.0.5 && fail "a host in 198.18/15 behind the uplink reachable"
ok "isolation: the home LAN (uplink subnet, private and 198.18/15 hosts behind it) is out of reach"
ip addr add 45.0.0.1/24 dev wlp; ip -n i addr add 45.0.0.2/24 dev eth0; iso_sync || fail "iso_sync with a public on-link subnet"
ping_to 45.0.0.2 && fail "a home LAN on public addresses (on-link) reachable"
ok "isolation: a home LAN on public addresses directly on the uplink is out of reach"
# an on-link host route, which ip prints without a prefix: reachable until the next sync, dropped after it (and real nft
# takes a bare address in the set next to the prefixes)
ip -n i addr add 203.0.113.9/32 dev eth0; ip route add 203.0.113.9 dev wlp
ip -4 -o route show scope link | grep -c '^203\.0\.113\.9 dev wlp ' >/dev/null || fail "setup: no host route without a prefix"
ping_to 203.0.113.9 || fail "setup: the on-link host 203.0.113.9 not reachable before the sync"
iso_sync || fail "iso_sync with an on-link host route"
nft list chain inet omamobile_hotspot_iso forward_iso | grep -c '203\.0\.113\.9' >/dev/null || fail "the host route is not in the drop set"
ping_to 203.0.113.9 && fail "an on-link host route reachable"
ok "isolation: an on-link host route (no prefix) is out of reach"
tcp_to 10.42.0.1 22 && fail "the phone's port 22 on ap0 reachable"
tcp_to 192.168.50.1 22 && fail "the phone's uplink address reachable from a client"
ok "isolation: the phone's own services (tcp/22 on ap0 and on the uplink address) are dropped"
udp_dns_ok 10.42.0.1 || fail "DNS on ap0's address blocked"
udp_dns_ok 192.168.50.1 && fail "DNS on the phone's uplink address answered"
ok "isolation: DNS to ap0's address passes, DNS to another phone address does not"
ip netns exec c python3 -c 'import socket;s=socket.socket(2,2);s.setsockopt(1,6,1);s.bind(("0.0.0.0",68));s.sendto(b"x",("255.255.255.255",67))' 2>/dev/null || true
nft list chain inet omamobile_hotspot_iso input_iso | grep -c 'udp dport 67 accept' >/dev/null || fail "DHCP accept missing"
ok "isolation: DHCP (67/udp) accepted on ap0"
ip netns exec i ping -c 1 -W 1 -q 10.42.0.23 >/dev/null 2>&1 && fail "the LAN opened a connection to a client"
ok "isolation: nothing on the uplink side can open a connection to a client"
ip -n c -6 addr add fd00:42::23/64 dev eth0 nodad; ip -6 addr add fd00:42::1/64 dev ap0 nodad
ip netns exec c ping -6 -c 1 -W 1 -q fd00:42::1 >/dev/null 2>&1 && fail "IPv6 from a client to the phone"
ok "isolation: IPv6 from ap0 dropped"
# client to client: ap0 -> ap0 (hairpin through the phone, a second client routed via the phone)
ip -n c route add 10.99.0.0/24 via 10.42.0.1; ip addr add 10.99.0.1/24 dev ap0
ip route get 10.99.0.7 iif ap0 from 10.42.0.23 >/dev/null 2>&1
nft list chain inet omamobile_hotspot_iso forward_iso | grep -c 'iifname "ap0" oifname "ap0" drop' >/dev/null || fail "ap0->ap0 drop missing"
ok "isolation: ap0 to ap0 forward dropped (rule present; L2 inside the radio is ap-isolation's job)"

# I4. the README's limit: an on-link split default route (as some VPNs add) lands in the drop set, the clients lose
# the internet, and nothing of theirs reaches the uplink side (fails closed)
ip route add 0.0.0.0/1 dev wlp; ip route add 128.0.0.0/1 dev wlp
iso_sync || fail "iso_sync with an on-link split default (nft refused?)"
l0=$(leaks); ping_c && fail "the internet reachable with an on-link split default"
l1=$(leaks); [[ $l0 == "$l1" ]] || fail "client packets reached the uplink side with the split default ($l0 -> $l1)"
ok "limit: an on-link split default route cuts the clients off, and none of their packets leave (fails closed)"
ip route del 0.0.0.0/1 dev wlp; ip route del 128.0.0.0/1 dev wlp; iso_sync || fail "iso_sync after the split default went"
ping_c || fail "no internet after the split default went"
ok "limit: the internet is back once the split default is gone"

# I3. clear
iso_clear
nft list table inet omamobile_hotspot_iso >/dev/null 2>&1 && fail "isolation table left after clear"
ping_to 192.168.50.2 || fail "no LAN after clear (test sanity)"
ok "iso_clear: table gone"
echo "hotspot-netns: ok"
