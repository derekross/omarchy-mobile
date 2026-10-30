# SPDX-License-Identifier: MIT
"""464XLAT's client side (CLAT, RFC 6877) for an IPv6-only internet bearer.

Translation is TAYGA's (a small stateless NAT64 in C, run as a child of
omamobile-sit-data); this module only decides and configures, as TAYGA's own
"dynamic routing" CLAT example does: the network routes the whole /64 to
the phone, so one /127 out of it is the translator's (the even address for
translated traffic, the odd one for TAYGA's own ICMPv6 errors). Applications
see 192.0.0.1/29 (RFC 7335) on v4-rmnet0 and an IPv4 default route behind
Wi-Fi's (metric 700), so IPv4 literals and IPv4-only programs work.

The NAT64 prefix comes from [data] clat_prefix, else from the carrier's
DNS64 (RFC 7050: the AAAA records of ipv4only.arpa, asked over rmnet0 only).
Forwarding is enabled per interface (force_forwarding, Linux 6.17+) on
rmnet0 and v4-rmnet0 only; nothing global changes. With ip6tables (ufw)
present, two FORWARD rules let the /127's traffic between the two through
and nothing else. Every change is undone at stop, and nothing here is
logged with an address.
"""
import ipaddress
import os
from pathlib import Path
import secrets
import shutil
import socket
import struct
import subprocess
import time

DEVICE = 'v4-rmnet0'
UPLINK = 'rmnet0'
IPV4_HOST = '192.0.0.1'      # the phone's IPv4 address on the CLAT (RFC 7335)
IPV4_TAYGA = '192.0.0.2'     # TAYGA's own, the source of its ICMPv4 errors
COMMENT = 'omamobile-clat'
WELL_KNOWN = ipaddress.IPv6Network('64:ff9b::/96')
# RFC 7050 section 2.2: the two well-known IPv4 addresses of ipv4only.arpa.
WKA = (ipaddress.IPv4Address('192.0.0.170').packed, ipaddress.IPv4Address('192.0.0.171').packed)
# RFC 6052 section 2.2: where the 32 IPv4 bits sit for each prefix length
# (bits 64-71, the "u" octet, are always zero and skipped).
POSITIONS = {32: (4, 5, 6, 7), 40: (5, 6, 7, 9), 48: (6, 7, 9, 10), 56: (7, 9, 10, 11),
             64: (9, 10, 11, 12), 96: (12, 13, 14, 15)}
IP6TABLES = os.environ.get('OMAMOBILE_SIT_IP6TABLES', 'ip6tables')
TAYGA = os.environ.get('OMAMOBILE_SIT_TAYGA', 'tayga')


def check_prefix(text):
    """A NAT64 prefix as RFC 6052 allows it."""
    network = ipaddress.IPv6Network(text, strict=True)
    if network.prefixlen not in POSITIONS:
        raise ValueError('NAT64 prefix length must be 32, 40, 48, 56, 64 or 96')
    if network.prefixlen < 96 and network.network_address.packed[8]:
        raise ValueError('NAT64 prefix has bits 64-71 set')
    return network


def prefixes_from(addresses):
    """RFC 7050 section 3: the NAT64 prefixes the synthesized AAAA records
    reveal. Each address is tried at every RFC 6052 position; the shortest
    match wins (a /96 is checked last)."""
    found = []
    for packed in addresses:
        for length in sorted(POSITIONS):
            embedded = bytes(packed[i] for i in POSITIONS[length])
            if embedded in WKA:
                prefix = ipaddress.IPv6Network((int.from_bytes(packed, 'big') >> (128 - length) << (128 - length),
                                                length))
                if prefix not in found:
                    found.append(prefix)
                break
    return found


def aaaa_query(name, ident):
    header = struct.pack('>HHHHHH', ident, 0x0100, 1, 0, 0, 0)    # RD, one question
    labels = b''.join(bytes([len(p)]) + p.encode('ascii') for p in name.split('.')) + b'\0'
    return header + labels + struct.pack('>HH', 28, 1)               # AAAA, IN


def skip_name(data, offset):
    while True:
        length = data[offset]
        if length & 0xc0 == 0xc0:
            return offset + 2
        offset += 1
        if not length:
            return offset
        offset += length


def aaaa_answers(data, ident):
    """The AAAA addresses in a DNS reply to aaaa_query(ident); [] for a reply
    that isn't one."""
    if len(data) < 12:
        return []
    rid, flags, questions, answers = struct.unpack_from('>HHHH', data)
    if rid != ident or not flags & 0x8000 or flags & 0x000f:
        return []
    offset = 12
    try:
        for _ in range(questions):
            offset = skip_name(data, offset) + 4
        found = []
        for _ in range(answers):
            offset = skip_name(data, offset)
            rtype, _, _, length = struct.unpack_from('>HHIH', data, offset)
            offset += 10
            if rtype == 28 and length == 16 and offset + 16 <= len(data):
                found.append(bytes(data[offset:offset + 16]))
            offset += length
        return found
    except (IndexError, struct.error):
        return []


def discover(servers, source, timeout=3):
    """The carrier's NAT64 prefix from its DNS64 servers, asked over rmnet0."""
    for server in servers:
        ident = secrets.randbelow(65536)
        try:
            with socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as sock:
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, UPLINK.encode())
                sock.bind((source, 0))
                sock.settimeout(timeout)
                sock.sendto(aaaa_query('ipv4only.arpa', ident), (server, 53))
                deadline = time.monotonic() + timeout
                while time.monotonic() < deadline:
                    data, _ = sock.recvfrom(4096)
                    found = prefixes_from(aaaa_answers(data, ident))
                    if found:
                        return found[0]
        except OSError:
            continue
    return None


def pair(network, avoid):
    """An even/odd /127 inside the bearer's prefix that isn't our address."""
    if network.prefixlen > 120:
        raise ValueError('The IPv6 bearer prefix is too long for a CLAT address')
    host_bits = 128 - network.prefixlen
    for _ in range(16):
        offset = secrets.randbits(host_bits) & ~1
        base = network.network_address + offset
        if offset > 1 and base not in avoid and base + 1 not in avoid:
            return base, base + 1
    raise RuntimeError('No free CLAT address in the IPv6 bearer prefix')


def config_text(prefix, user, own):
    return (f'tun-device {DEVICE}\nipv4-addr {IPV4_TAYGA}\nipv6-addr {own}\n'
            f'map {IPV4_HOST} {user}\nprefix {prefix}\n')


class Clat:
    """One running CLAT. start() raises on anything that leaves it unusable
    (after undoing what it did); stop() is safe to call more than once."""

    def __init__(self, run, sysctl, workdir):
        self.run = run
        self.sysctl = sysctl
        self.conf = Path(workdir) / 'clat.conf'
        self.process = None
        self.undo = []

    def start(self, prefix, network, address, mtu=1500):
        """Start translating; the arguments of the IPv4 default route through
        the CLAT, for the caller to add."""
        tayga = shutil.which(TAYGA)
        if not tayga:
            raise FileNotFoundError('CLAT unavailable: tayga is not installed')
        user, own = pair(network, {address})
        fd = os.open(self.conf, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_CLOEXEC, 0o600)
        with os.fdopen(fd, 'w') as out:
            out.write(config_text(prefix, user, own))
        self.undo.append(lambda: self.conf.unlink(missing_ok=True))
        try:
            self.run(tayga, '-c', str(self.conf), '--mktun')
            self.undo.append(lambda: subprocess.run([tayga, '-c', str(self.conf), '--rmtun'],
                                                    capture_output=True, timeout=20))
            # IPv4 packets grow by 20 bytes, plus 8 for a fragment header.
            mtu4 = max(1260, min(mtu, 1500) - 28)
            self.run('ip', 'link', 'set', 'dev', DEVICE, 'up')
            self.run('ip', 'addr', 'add', IPV4_HOST + '/29', 'dev', DEVICE)
            self.run('ip', '-6', 'route', 'add', f'{user}/127', 'dev', DEVICE)
            for dev in (DEVICE, UPLINK):
                old = self.sysctl(dev, 'force_forwarding', 1)
                self.undo.append(lambda dev=dev, old=old: self.sysctl(dev, 'force_forwarding', old))
            if shutil.which(IP6TABLES):
                for rule in (('-i', DEVICE, '-o', UPLINK, '-s', f'{user}/127'),
                             ('-i', UPLINK, '-o', DEVICE, '-d', f'{user}/127')):
                    spec = (*rule, '-m', 'comment', '--comment', COMMENT, '-j', 'ACCEPT')
                    self.run(IP6TABLES, '-w', '-I', 'FORWARD', *spec)
                    self.undo.append(lambda spec=spec: subprocess.run(
                        [IP6TABLES, '-w', '-D', 'FORWARD', *spec], capture_output=True, timeout=20))
            self.process = subprocess.Popen([tayga, '-c', str(self.conf), '--nodetach'],
                                            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                            stderr=subprocess.DEVNULL)
            time.sleep(.5)
            if self.process.poll() is not None:
                raise RuntimeError(f'CLAT translator exited at start (status {self.process.returncode})')
        except BaseException:
            self.stop()
            raise
        return ('default', 'dev', DEVICE, 'metric', '700', 'mtu', str(mtu4))

    def alive(self):
        return self.process is not None and self.process.poll() is None

    def stop(self):
        if self.process is not None:
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(10)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()
            self.process = None
        while self.undo:
            try:
                self.undo.pop()()
            except (OSError, subprocess.SubprocessError):
                pass
