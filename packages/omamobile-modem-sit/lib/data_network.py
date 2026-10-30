#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""omamobile-sit-data: the internet bearer (CID 1) as a fallback behind Wi-Fi.

CPIF's rmnet devices are raw-IP links that NetworkManager doesn't manage
(the package marks rmnet* unmanaged). This owns rmnet0's addresses, a
metric-700 default route per address family (Wi-Fi's default is 600, so
Wi-Fi wins while it is up) and the carrier's DNS while rmnet0 is the only
way out. All state and rollback records stay in RAM; nothing here is logged
with an address.

IPv4: the bearer's address as a /32 and a default route through rmnet0.

IPv6 (0.4.0, [data] ipv6 = yes): the link-local address is fe80:: plus the
interface identifier the network assigned (3GPP: the UE's link-local uses
it), the kernel's own address generation is off, and router advertisements
are accepted without their default route, so SLAAC forms the global address
from the network's prefix and that identifier. A global address in the
setup response is added at once. The IPv6 default route is ours, metric 700.

An IPv6-only bearer (PDP type 2) gets a CLAT (clat.py, [data] clat = auto):
IPv4 through the carrier's NAT64, with the carrier's DNS64 servers.

The carrier's DNS is used only while rmnet0 is the only way out. A bearer
that sends but receives nothing, and then answers no ping either, loses its
default routes, and gets them back as soon as nothing else is left:
otherwise a dead bearer's route plus its DNS can outlive a short Wi-Fi
outage, make NetworkManager's connectivity check fail through it and keep
the phone offline with Wi-Fi up.
"""
from dataclasses import dataclass, field
import fcntl
import ipaddress
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import time

import clat as clat_mod
import cp
import paths
from data_call import RESPONSE

RESOLVER = Path(os.environ.get('OMAMOBILE_SIT_RESOLVER', '/etc/resolv.conf'))
SYSCTL = Path(os.environ.get('OMAMOBILE_SIT_SYSCTL', '/proc/sys/net/ipv6/conf'))
# What omamobile-sitd shows its private status readers (and omamobile-mmd
# exports as the bearer's Ip4Config/Ip6Config). Root only, RAM only.
RECORD = paths.RUN / 'bearer-ip.json'
DEV = 'rmnet0'
CELLULAR = (DEV, clat_mod.DEVICE)
PROBES = {4: ('1.1.1.1', '8.8.8.8'), 6: ('2606:4700:4700::1111', '2001:4860:4860::8888')}
# rmnet0's IPv6 settings while the bearer is ours, set before the link is up.
IPV6_SYSCTLS = (('disable_ipv6', 0), ('addr_gen_mode', 1), ('accept_dad', 0), ('accept_ra', 2),
                ('accept_ra_defrtr', 0), ('accept_ra_pinfo', 1), ('autoconf', 1))


def run(*args):
    p = subprocess.run(args, capture_output=True, timeout=20)
    if p.returncode:
        raise RuntimeError('Cellular network operation failed: ' + args[0])
    return p.stdout


def sysctl(dev, key, value):
    """Set an IPv6 per-interface setting; return the old value."""
    path = SYSCTL / dev / key
    old = path.read_text().strip()
    if old != str(value):
        path.write_text(str(value))
    return old


@dataclass
class Bearer:
    pdp: int
    ipv4: str = ''
    ipv6: str = ''
    dns4: list = field(default_factory=list)
    dns6: list = field(default_factory=list)
    mtu: int = 0


def usable6(packed):
    address = ipaddress.IPv6Address(packed)
    if address.is_unspecified or address.is_multicast or address.is_loopback:
        return None
    return address


def configuration(data):
    """The internet bearer's addresses and DNS from the setup response (the
    layout the working stack read on this phone: IPv4 at 5, IPv6 at 9, DNS1
    IPv4/IPv6 at 0x1a/0x1e, DNS2 at 0x2e/0x32; the stock codec adds the MTU,
    a u32 at 0x7f, used when it is 1280-1500, MODEM-SIT-RESEARCH 3.5)."""
    if len(data) < 132:
        raise ValueError('Short internet bearer response')
    status, cid, active, pdp = struct.unpack_from('<HBBB', data)
    if status or cid != 1 or active not in (1, 2) or pdp not in (1, 2, 3):
        raise ValueError('An active internet bearer is required')
    bearer = Bearer(pdp)
    if pdp in (1, 3):
        addr = ipaddress.IPv4Address(data[5:9])
        if not (addr.is_unspecified or addr.is_multicast):
            bearer.ipv4 = str(addr)
        bearer.dns4 = list(dict.fromkeys(str(ipaddress.IPv4Address(data[i:i+4]))
                                         for i in (0x1a, 0x2e) if any(data[i:i+4])))
    if pdp in (2, 3):
        addr = usable6(data[9:25])
        if addr and int(addr) & ((1 << 64) - 1):
            bearer.ipv6 = str(addr)
        bearer.dns6 = list(dict.fromkeys(str(a) for a in (usable6(data[i:i+16]) for i in (0x1e, 0x32))
                                         if a and not a.is_link_local))
    mtu = struct.unpack_from('<I', data, 0x7f)[0]
    bearer.mtu = mtu if 1280 <= mtu <= 1500 else 0
    if not bearer.ipv4 and not bearer.ipv6:
        raise ValueError('Missing internet address')
    if not bearer.dns4 and not bearer.dns6:
        raise ValueError('Missing carrier DNS')
    return bearer


def link_local(address):
    """fe80:: plus the interface identifier the network gave the bearer."""
    return ipaddress.IPv6Address((0xfe80 << 112) | (int(ipaddress.IPv6Address(address)) & ((1 << 64) - 1)))


def is_global(address):
    address = ipaddress.IPv6Address(address)
    return not address.is_link_local and int(address) >> 64 != 0


def global_address(dev=DEV):
    """rmnet0's global IPv6 address and prefix length, or None."""
    for link in json.loads(run('ip', '-j', '-6', 'address', 'show', 'dev', dev, 'scope', 'global')):
        for a in link.get('addr_info', []):
            if a.get('family') == 'inet6' and not a.get('tentative') and not a.get('dadfailed'):
                return a['local'], a['prefixlen']
    return None


def counters(stats):
    """(received bytes, sent packets) from `ip -j -s link` output for rmnet0."""
    link = stats[0]['stats64']
    return link['rx']['bytes'], link['tx']['packets']


def looks_silent(routed, before, after):
    """The routed bearer sent packets but received nothing since the last
    check. Not proof: a few router solicitations get no answer on a live one."""
    return routed and after[1] > before[1] and after[0] == before[0]


def guarded(step):
    """One pass of the route watch; the error of a failed or stalled `ip`, or
    None. Such a failure is retried: when this service exits the cellular
    fallback is gone until someone restarts it, and one stalled `ip route`
    must not cost hours without cellular."""
    try:
        step()
    except (subprocess.SubprocessError, RuntimeError, ValueError) as error:
        return error
    return None


def answers(family):
    """Whether the bearer carries anything: a ping out through rmnet0."""
    for target in PROBES[family]:
        p = subprocess.run(['ping', '-n', '-q', f'-{family}', '-c', '1', '-W', '3', '-I', DEV, target],
                           capture_output=True, timeout=10)
        if p.returncode == 0:
            return True
    return False


class Resolver:
    """The carrier's DNS in /etc/resolv.conf while cellular is the only way
    out; the previous file comes back unless something (NetworkManager) has
    written a newer one meanwhile."""
    def __init__(self, path):
        self.path = path.resolve()
        self.original = None
        self.owned = None

    def update(self, cellular, servers):
        if cellular:
            content = '# Omarchy Mobile cellular fallback (session only)\n' + ''.join('nameserver ' + s + '\n' for s in servers)
            current = self.path.read_text()
            if self.owned is None or current != self.owned:
                self.original = current
            if current != content:
                self.path.write_text(content)
            self.owned = content
        else:
            self.restore()

    def restore(self):
        if self.owned is not None:
            if self.path.read_text() == self.owned:
                self.path.write_text(self.original)
            self.owned = None


class ResolvedLink:
    """The same with systemd-resolved: rmnet0's DNS servers are set once and
    the link is the default DNS route only while cellular is the only way out."""
    def __init__(self, servers):
        run('resolvectl', 'dns', DEV, *servers)
        self.cellular = None

    def update(self, cellular, servers):
        if cellular != self.cellular:
            run('resolvectl', 'default-route', DEV, 'yes' if cellular else 'no')
            self.cellular = cellular

    def restore(self):
        subprocess.run(['resolvectl', 'revert', DEV], capture_output=True, timeout=20)


def resolver_for(servers):
    target = str(RESOLVER.resolve()) if RESOLVER.exists() else ''
    if target.startswith('/run/systemd/resolve/'):
        return ResolvedLink(servers)
    return Resolver(RESOLVER)


def wait_for_bearer(seconds):
    deadline = time.monotonic() + seconds
    while not RESPONSE.exists():
        if time.monotonic() >= deadline:
            raise RuntimeError('No internet bearer: omamobile-sitd has not set one up')
        time.sleep(1)


def private_json(path, value):
    tmp = path.with_suffix('.tmp')
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_CLOEXEC, 0o600)
    with os.fdopen(fd, 'w') as out:
        json.dump(value, out)
    tmp.replace(path)


class Network:
    """rmnet0 for one bearer: set up, watched, taken down. Every change is
    recorded in `undo` as it is made."""

    def __init__(self, bearer, settings, log=print):
        self.bearer = bearer
        self.settings = settings
        self.log = lambda *a: log(*a, flush=True)
        self.undo = []
        self.routes = {}            # family -> the `ip route add` arguments of our default route
        self.ipv6 = None            # (address, prefix length) once configured
        self.clat = None
        self.dns = []

    def setup(self):
        b, data = self.bearer, self.settings
        want6 = bool(b.ipv6 or b.pdp in (2, 3)) and data.getboolean('ipv6', True)
        if not b.ipv4 and not want6:
            raise RuntimeError('The bearer is IPv6 only and [data] ipv6 = no')
        info = json.loads(run('ip', '-j', 'address', 'show', 'dev', DEV))[0]
        if 'UP' in info['flags'] or info['addr_info']:
            raise RuntimeError('rmnet0 already configured; refusing to replace it')
        olds = []
        try:
            for key, value in IPV6_SYSCTLS if want6 else ():
                olds.append((key, sysctl(DEV, key, value)))
        except OSError:
            for key, old in reversed(olds):
                sysctl(DEV, key, old)
            raise
        if b.mtu and b.mtu != info.get('mtu'):
            run('ip', 'link', 'set', 'dev', DEV, 'mtu', str(b.mtu))
            self.undo.append(lambda: run('ip', 'link', 'set', 'dev', DEV, 'mtu', str(info['mtu'])))
        run('ip', 'link', 'set', 'dev', DEV, 'up')
        self.undo.append(lambda: run('ip', 'link', 'set', 'dev', DEV, 'down'))
        # Restored while the link is still up: a changed addr_gen_mode makes
        # the kernel generate a link-local address, which the link going
        # down then removes (a down rmnet0 with an address is refused above).
        self.undo.append(lambda: [sysctl(DEV, key, old) for key, old in reversed(olds)])
        if b.ipv4:
            run('ip', 'addr', 'add', b.ipv4 + '/32', 'dev', DEV)
            self.undo.append(lambda: run('ip', 'addr', 'del', b.ipv4 + '/32', 'dev', DEV))
            self.routes[4] = ('default', 'dev', DEV, 'src', b.ipv4, 'metric', '700')
        if want6:
            self.setup_ipv6()
        if not self.routes:
            raise RuntimeError('No usable address on the internet bearer')
        if b.ipv4 or not self.ipv6:
            self.dns = b.dns4 + b.dns6
        else:
            self.dns = b.dns6
        if not b.ipv4 and self.ipv6 and data.get('clat', 'auto') != 'off':
            self.start_clat()
        for family in sorted(self.routes):
            self.add_route(family)
        private_json(RECORD, self.record())
        self.undo.append(lambda: RECORD.unlink(missing_ok=True))
        ipv4 = 'yes' if b.ipv4 else 'through CLAT' if self.clat else 'no'
        self.log(f'Cellular fallback ready; Wi-Fi remains preferred (IPv4 {ipv4}, '
                 f'IPv6 {"yes" if self.ipv6 else "no"})')

    def setup_ipv6(self):
        b = self.bearer
        if not b.ipv6:
            # Only a link-local or no address: nothing to form SLAAC from.
            self.log('IPv6: the bearer carries no interface identifier; IPv6 not configured')
            if not b.ipv4:
                raise RuntimeError('The IPv6 bearer has no address')
            return
        local = link_local(b.ipv6)
        run('ip', '-6', 'addr', 'add', f'{local}/64', 'dev', DEV, 'nodad')
        self.undo.append(lambda: run('ip', '-6', 'addr', 'flush', 'dev', DEV))
        if is_global(b.ipv6):
            run('ip', '-6', 'addr', 'add', f'{b.ipv6}/64', 'dev', DEV, 'nodad')
        deadline = time.monotonic() + self.settings.getint('ra_timeout', 10)
        found = global_address()
        while found is None and time.monotonic() < deadline:
            time.sleep(.5)
            found = global_address()
        if found is None:
            if not b.ipv4:
                raise RuntimeError('No global IPv6 address from the network (no router advertisement)')
            self.log('IPv6: no global address from the network; IPv4 only')
            return
        self.ipv6 = found
        self.log('IPv6 configured', 'from the setup response' if is_global(b.ipv6) else 'by SLAAC')
        self.routes[6] = ('default', 'dev', DEV, 'metric', '700')

    def start_clat(self):
        prefix = self.settings.get('clat_prefix', '').strip()
        try:
            if prefix:
                prefix = clat_mod.check_prefix(prefix)
            else:
                prefix = clat_mod.discover(self.bearer.dns6, self.ipv6[0])
                if prefix is None:
                    self.log('CLAT: the carrier DNS named no NAT64 prefix (RFC 7050); '
                             'set [data] clat_prefix to use one. IPv6 only')
                    return
            mtu = json.loads(run('ip', '-j', 'link', 'show', 'dev', DEV))[0].get('mtu', 1500)
            clat = clat_mod.Clat(run, sysctl, paths.RUN)
            network = ipaddress.IPv6Network(f'{self.ipv6[0]}/{self.ipv6[1]}', strict=False)
            route = clat.start(prefix, network, ipaddress.IPv6Address(self.ipv6[0]), mtu)
        except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
            # IPv6 keeps working; IPv4 literals and IPv4-only programs don't.
            self.log('CLAT not started (' + type(error).__name__ + ': ' + str(error) + '); IPv6 only')
            return
        self.clat = clat
        self.undo.append(clat.stop)
        self.routes[4] = route
        self.log('CLAT running: IPv4 through the carrier NAT64',
                 'well-known prefix' if prefix == clat_mod.WELL_KNOWN else 'network-specific prefix')

    def add_route(self, family):
        run('ip', f'-{family}', 'route', 'add', *self.routes[family])

    def del_routes(self):
        for family in (4, 6):
            for dev in CELLULAR:
                subprocess.run(['ip', f'-{family}', 'route', 'del', 'default', 'dev', dev, 'metric', '700'],
                               capture_output=True, timeout=20)

    def record(self):
        b = self.bearer
        ipv4 = dict(address=b.ipv4, prefix=32, dns=b.dns4) if b.ipv4 else (
            dict(address=clat_mod.IPV4_HOST, prefix=29, dns=[], clat=True) if self.clat else None)
        ipv6 = dict(address=self.ipv6[0], prefix=self.ipv6[1], dns=b.dns6) if self.ipv6 else None
        return dict(pdp=b.pdp, ipv4=ipv4, ipv6=ipv6, clat=self.clat is not None)

    def families(self):
        """The families whose default routes are ours, IPv4 first."""
        return sorted(self.routes)

    def check_clat(self):
        """A translator that died takes its IPv4 route with it; IPv6 stays."""
        if self.clat and not self.clat.alive():
            self.clat.stop()
            self.clat = None
            self.routes.pop(4, None)
            private_json(RECORD, self.record())
            self.log('CLAT translator exited; IPv6 only')

    def teardown(self):
        self.del_routes()
        while self.undo:
            try:
                self.undo.pop()()
            except (OSError, RuntimeError, subprocess.SubprocessError):
                pass


def default_routes(family):
    routes = json.loads(run('ip', '-j', f'-{family}', 'route', 'show', 'default'))
    ours = [r for r in routes if r.get('dev') in CELLULAR]
    return ours, [r for r in routes if r.get('dev') not in CELLULAR]


def main():
    os.umask(0o077)
    settings = paths.config()['data']
    lock = os.open(paths.RUN / 'data-network.lock', os.O_CREAT | os.O_RDWR, 0o600)
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    wait_for_bearer(60)
    bearer = configuration(RESPONSE.read_bytes())
    print('Internet bearer PDP type', bearer.pdp, 'IPv4', 'yes' if bearer.ipv4 else 'no',
          'IPv6', 'yes' if bearer.ipv6 else 'no', flush=True)
    network = Network(bearer, settings)
    stopping = False

    def stop(*_):
        nonlocal stopping
        stopping = True
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    resolver = None
    try:
        network.setup()
        resolver = resolver_for(network.dns)
        last = None
        seen = counters(json.loads(run('ip', '-j', '-s', 'link', 'show', 'dev', DEV)))
        check_at = time.monotonic() + 30

        def watch():
            nonlocal last, seen, check_at
            network.check_clat()
            # The family that decides "cellular is the only way out": IPv4
            # (native or through the CLAT) when we have it, as Wi-Fi has.
            state = {f: default_routes(f) for f in network.families()}
            ours, others = state[network.families()[0]]
            # With Wi-Fi up but rated limited, the carrier's DNS would keep
            # NetworkManager's own check failing and Wi-Fi penalised.
            cellular = bool(ours) and not others
            resolver.update(cellular, network.dns)
            if cellular != last:
                print('Default internet path', 'cellular' if cellular else 'Wi-Fi/other', flush=True)
                last = cellular
            missing = [f for f, (o, x) in state.items() if not o and not x]
            for family in missing:
                network.add_route(family)
            if missing:
                print('Nothing else leads out; the cellular default route is back', flush=True)
            elif time.monotonic() >= check_at:
                now = counters(json.loads(run('ip', '-j', '-s', 'link', 'show', 'dev', DEV)))
                probe = 4 if network.bearer.ipv4 else 6
                if looks_silent(bool(ours), seen, now) and not answers(probe):
                    network.del_routes()
                    print('Cellular bearer carries nothing; its default route is removed', flush=True)
                    now = counters(json.loads(run('ip', '-j', '-s', 'link', 'show', 'dev', DEV)))
                seen = now
                check_at = time.monotonic() + 30
        failing = None
        while not stopping and cp.online() and RESPONSE.exists():
            error = guarded(watch)
            if error and not failing:
                print('Network check failed, retrying:', type(error).__name__, flush=True)
            elif failing and not error:
                print('Network checks work again', flush=True)
            failing = error
            time.sleep(2 if error else .5)
    finally:
        if resolver is not None:
            resolver.restore()
        network.teardown()
        os.close(lock)
        print('Cellular fallback configuration removed', flush=True)


if __name__ == '__main__':
    main()
