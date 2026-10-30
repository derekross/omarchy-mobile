# SPDX-License-Identifier: MIT
"""IPv6 on rmnet0 and the CLAT, offline: the setup response's IPv6 fields,
RFC 7050 prefix discovery from made-up DNS replies, the CLAT's addresses,
and the whole rmnet0 configuration in a private network namespace (a user
namespace, `unshare -rn`: a dummy rmnet0, a stub tayga and a stub
ip6tables; nothing on the machine's own network changes). Every address is
from the documentation ranges."""
import env  # noqa: F401  (paths and sys.path first)
import configparser
import ipaddress
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import textwrap
import unittest

import clat
from data_network import configuration, is_global, link_local

HERE = Path(__file__).resolve().parent
LIB = HERE.parent / 'lib'


def response(pdp, v4=None, v6=None, dns4=(), dns6=(), mtu=0):
    r = bytearray(292)
    struct.pack_into('<HBBB', r, 0, 0, 1, 2, pdp)
    struct.pack_into('<I', r, 0x7f, mtu)
    if v4:
        r[5:9] = ipaddress.IPv4Address(v4).packed
    if v6:
        r[9:25] = ipaddress.IPv6Address(v6).packed
    for offset, server in zip((0x1a, 0x2e), dns4):
        r[offset:offset + 4] = ipaddress.IPv4Address(server).packed
    for offset, server in zip((0x1e, 0x32), dns6):
        r[offset:offset + 16] = ipaddress.IPv6Address(server).packed
    return bytes(r)


class BearerTests(unittest.TestCase):
    def test_ipv4v6_bearer(self):
        b = configuration(response(3, '192.0.2.2', '2001:db8::2', ['192.0.2.53'], ['2001:db8::53']))
        self.assertEqual((b.pdp, b.ipv4, b.ipv6, b.dns4, b.dns6),
                         (3, '192.0.2.2', '2001:db8::2', ['192.0.2.53'], ['2001:db8::53']))

    def test_ipv6_only_bearer_is_accepted(self):
        b = configuration(response(2, None, '2001:db8:64::2', (), ['2001:db8:64::53', '2001:db8:64::54']))
        self.assertEqual((b.ipv4, b.ipv6, b.dns6), ('', '2001:db8:64::2', ['2001:db8:64::53', '2001:db8:64::54']))

    def test_identifier_only_address_is_kept_for_slaac(self):
        b = configuration(response(2, None, '::1a2b:3c4d:5e6f:7081', (), ['2001:db8:64::53']))
        self.assertEqual(b.ipv6, '::1a2b:3c4d:5e6f:7081')
        self.assertFalse(is_global(b.ipv6))
        self.assertEqual(str(link_local(b.ipv6)), 'fe80::1a2b:3c4d:5e6f:7081')
        self.assertTrue(is_global('2001:db8::2'))
        self.assertEqual(str(link_local('2001:db8::2')), 'fe80::2')

    def test_ipv4_fields_ignored_on_an_ipv6_only_bearer(self):
        b = configuration(response(2, '192.0.2.2', '2001:db8::2', ['192.0.2.53'], ['2001:db8::53']))
        self.assertEqual((b.ipv4, b.dns4), ('', []))

    def test_mtu(self):
        self.assertEqual(configuration(response(1, '192.0.2.2', None, ['192.0.2.53'], mtu=1400)).mtu, 1400)
        for odd in (0, 576, 9000):
            self.assertEqual(configuration(response(1, '192.0.2.2', None, ['192.0.2.53'], mtu=odd)).mtu, 0)

    def test_unusable_bearers_are_refused(self):
        for data in (response(2, None, None, (), ['2001:db8::53']),       # no address
                     response(2, None, '2001:db8::2'),                     # no DNS
                     response(2, None, 'ff02::1', (), ['2001:db8::53']),   # multicast
                     response(5, '192.0.2.2', None, ['192.0.2.53'])):      # non-IP
            with self.assertRaises(ValueError):
                configuration(data)


def dns_reply(ident, addresses, rcode=0):
    question = b'\x08ipv4only\x04arpa\x00' + struct.pack('>HH', 28, 1)
    answers = b''.join(b'\xc0\x0c' + struct.pack('>HHIH', 28, 1, 60, 16) + ipaddress.IPv6Address(a).packed
                       for a in addresses)
    return struct.pack('>HHHHHH', ident, 0x8180 | rcode, 1, len(addresses), 0, 0) + question + answers


class Pref64Tests(unittest.TestCase):
    def test_query_is_an_aaaa_question_for_ipv4only_arpa(self):
        q = clat.aaaa_query('ipv4only.arpa', 0x1234)
        self.assertEqual(q[:12], struct.pack('>HHHHHH', 0x1234, 0x0100, 1, 0, 0, 0))
        self.assertEqual(q[12:], b'\x08ipv4only\x04arpa\x00\x00\x1c\x00\x01')

    def test_well_known_and_network_specific_prefixes(self):
        found = clat.prefixes_from(clat.aaaa_answers(
            dns_reply(7, ['64:ff9b::c000:aa', '64:ff9b::c000:ab']), 7))
        self.assertEqual(found, [clat.WELL_KNOWN])
        # A /64: the IPv4 bits sit after the zero "u" octet (RFC 6052 2.2).
        found = clat.prefixes_from(clat.aaaa_answers(dns_reply(8, ['2001:db8:100:200:c0:0:aa00:0']), 8))
        self.assertEqual(found, [ipaddress.IPv6Network('2001:db8:100:200::/64')])

    def test_wrong_id_error_or_garbage_gives_nothing(self):
        self.assertEqual(clat.aaaa_answers(dns_reply(7, ['64:ff9b::c000:aa']), 8), [])
        self.assertEqual(clat.aaaa_answers(dns_reply(7, [], rcode=3), 7), [])
        self.assertEqual(clat.aaaa_answers(b'\x00\x07\x81', 7), [])
        self.assertEqual(clat.prefixes_from([ipaddress.IPv6Address('2001:db8::1').packed]), [])

    def test_configured_prefix_checks(self):
        self.assertEqual(clat.check_prefix('64:ff9b::/96'), clat.WELL_KNOWN)
        for bad in ('64:ff9b::/80', '2001:db8::1/96', 'nonsense', '2001:db8:0:0:ff00::/64'):
            with self.assertRaises(ValueError):
                clat.check_prefix(bad)

    def test_pair_is_an_even_odd_127_inside_the_prefix_and_not_ours(self):
        network = ipaddress.IPv6Network('2001:db8:64::/64')
        ours = ipaddress.IPv6Address('2001:db8:64::2')
        for _ in range(50):
            user, own = clat.pair(network, {ours})
            self.assertIn(user, network)
            self.assertEqual((int(user) % 2, int(own) - int(user)), (0, 1))
            self.assertNotIn(ours, (user, own))

    def test_tayga_configuration(self):
        text = clat.config_text(clat.WELL_KNOWN, ipaddress.IPv6Address('2001:db8:64::a0'),
                                ipaddress.IPv6Address('2001:db8:64::a1'))
        self.assertEqual(text.splitlines(), [
            'tun-device v4-rmnet0', 'ipv4-addr 192.0.0.2', 'ipv6-addr 2001:db8:64::a1',
            'map 192.0.0.1 2001:db8:64::a0', 'prefix 64:ff9b::/96'])


def netns_usable():
    if not shutil.which('unshare') or not shutil.which('ip'):
        return False
    probe = subprocess.run(['unshare', '-rn', 'sh', '-c', 'ip link add rmnet0 type dummy && '
                            'test -w /proc/sys/net/ipv6/conf/rmnet0/accept_ra && '
                            'test -e /proc/sys/net/ipv6/conf/rmnet0/force_forwarding && '
                            'ip tuntap add mode tun dev t0'],
                           capture_output=True, timeout=20)
    return probe.returncode == 0


NETNS = netns_usable()
STUB_TAYGA = '''#!/bin/sh
echo "$*" >> "$STUB_LOG"
case "$*" in
  *--mktun*) exec ip tuntap add mode tun dev v4-rmnet0 ;;
  *--rmtun*) exec ip link del v4-rmnet0 ;;
  *--nodetach*) exec sleep 600 ;;
esac
'''
STUB_IP6TABLES = '#!/bin/sh\necho "ip6tables $*" >> "$STUB_LOG"\n'

# Runs inside `unshare -rn`: configures the dummy rmnet0 as the service
# does, prints what the kernel then shows, tears it down, prints again.
INSIDE = textwrap.dedent('''
    import configparser, json, subprocess, sys
    sys.path.insert(0, sys.argv[1])
    import data_network as dn
    def show():
        def j(*a):
            return json.loads(subprocess.run(['ip', '-j', *a], capture_output=True, text=True).stdout or '[]')
        sysctls = {k: open(f'/proc/sys/net/ipv6/conf/rmnet0/{k}').read().strip()
                   for k in ('addr_gen_mode', 'accept_ra', 'accept_ra_defrtr', 'force_forwarding')}
        return dict(mtu=j('link', 'show', 'dev', 'rmnet0')[0]['mtu'],
                    addr=[(a['local'], a['prefixlen']) for l in j('address', 'show', 'dev', 'rmnet0')
                          for a in l['addr_info']],
                    route4=[(r['dev'], r.get('metric')) for r in j('-4', 'route', 'show', 'default')],
                    route6=[(r['dev'], r.get('metric')) for r in j('-6', 'route', 'show', 'default')],
                    links=sorted(l['ifname'] for l in j('link', 'show')),
                    sysctl=sysctls)
    subprocess.run(['ip', 'link', 'add', 'rmnet0', 'type', 'dummy'], check=True)
    before = show()
    settings = configparser.ConfigParser()
    settings.read_dict({'data': json.loads(sys.argv[3])})
    net = dn.Network(dn.configuration(bytes.fromhex(sys.argv[2])), settings['data'],
                     log=lambda *a, **k: print(*a, file=sys.stderr, **k))
    net.setup()
    during = dict(show(), record=json.load(open(dn.RECORD)), dns=net.dns)
    net.teardown()
    print(json.dumps(dict(before=before, during=during, after=show())))
''')


@unittest.skipUnless(NETNS, 'no unprivileged network namespace with tun and force_forwarding')
class NamespaceTests(unittest.TestCase):
    def run_inside(self, data, settings):
        with tempfile.TemporaryDirectory() as temp:
            temp = Path(temp)
            for name, text in (('tayga', STUB_TAYGA), ('ip6tables', STUB_IP6TABLES)):
                (temp / name).write_text(text)
                (temp / name).chmod(0o755)
            (temp / 'run').mkdir()
            (temp / 'resolv.conf').write_text('nameserver 192.0.2.1\n')
            env = dict(os.environ, OMAMOBILE_SIT_RUN=str(temp / 'run'), STUB_LOG=str(temp / 'log'),
                       OMAMOBILE_SIT_TAYGA=str(temp / 'tayga'), OMAMOBILE_SIT_IP6TABLES=str(temp / 'ip6tables'),
                       OMAMOBILE_SIT_RESOLVER=str(temp / 'resolv.conf'), PYTHONDONTWRITEBYTECODE='1')
            p = subprocess.run(['unshare', '-rn', sys.executable, '-c', INSIDE, str(LIB), data.hex(),
                                json.dumps(settings)], env=env, capture_output=True, text=True, timeout=60)
            self.assertEqual(p.returncode, 0, p.stderr)
            calls = (temp / 'log').read_text().splitlines() if (temp / 'log').exists() else []
            self.assertFalse(os.listdir(temp / 'run'), 'RAM records left behind')
            return json.loads(p.stdout), calls, p.stderr

    def test_ipv4v6_bearer_gets_both_families_and_no_clat(self):
        state, calls, log = self.run_inside(
            response(3, '192.0.2.2', '2001:db8::2', ['192.0.2.53'], ['2001:db8::53']), {})
        during = state['during']
        self.assertIn(['192.0.2.2', 32], during['addr'])
        self.assertIn(['2001:db8::2', 64], during['addr'])
        self.assertIn(['fe80::2', 64], during['addr'])
        self.assertEqual((during['route4'], during['route6']), ([['rmnet0', 700]], [['rmnet0', 700]]))
        self.assertEqual(during['sysctl'], dict(addr_gen_mode='1', accept_ra='2', accept_ra_defrtr='0',
                                                force_forwarding='0'))
        self.assertEqual(during['record']['ipv6'], dict(address='2001:db8::2', prefix=64, dns=['2001:db8::53']))
        self.assertEqual(during['dns'], ['192.0.2.53', '2001:db8::53'])
        self.assertEqual(calls, [])
        self.assertEqual(state['after'], state['before'])
        self.assertNotIn('2001:db8', log)
        self.assertNotIn('192.0.2', log)

    def test_ipv6_only_bearer_gets_a_clat(self):
        state, calls, log = self.run_inside(
            response(2, None, '2001:db8:64::2', (), ['2001:db8:64::53'], mtu=1430), dict(clat_prefix='64:ff9b::/96'))
        during = state['during']
        self.assertEqual(during['mtu'], 1430)
        self.assertIn(['2001:db8:64::2', 64], during['addr'])
        self.assertNotIn('192.0.2.2', json.dumps(during['addr']))
        self.assertEqual(during['route4'], [['v4-rmnet0', 700]])
        self.assertEqual(during['route6'], [['rmnet0', 700]])
        self.assertIn('v4-rmnet0', during['links'])
        self.assertEqual(during['sysctl']['force_forwarding'], '1')
        self.assertEqual(during['record']['ipv4'], dict(address='192.0.0.1', prefix=29, dns=[], clat=True))
        self.assertEqual(during['dns'], ['2001:db8:64::53'])
        self.assertEqual([c.split()[-1] for c in calls if not c.startswith('ip6tables')],
                         ['--mktun', '--nodetach', '--rmtun'])
        rules = [c for c in calls if c.startswith('ip6tables')]
        self.assertEqual([r.split()[2] for r in rules], ['-I', '-I', '-D', '-D'])
        self.assertTrue(all('omamobile-clat' in r and '/127' in r for r in rules))
        self.assertEqual(state['after'], state['before'])
        self.assertIn('CLAT running', log)
        self.assertNotIn('2001:db8', log)

    def test_ipv6_only_without_a_prefix_stays_ipv6_only(self):
        # No configured prefix and no reachable DNS64: no CLAT, IPv6 still up.
        state, calls, log = self.run_inside(
            response(2, None, '2001:db8:64::2', (), ['2001:db8:64::53']), {})
        during = state['during']
        self.assertEqual((during['route4'], during['route6']), ([], [['rmnet0', 700]]))
        self.assertIsNone(during['record']['ipv4'])
        self.assertEqual(calls, [])
        self.assertIn('no NAT64 prefix', log)
        self.assertEqual(state['after'], state['before'])

    def test_clat_off(self):
        state, calls, _ = self.run_inside(
            response(2, None, '2001:db8:64::2', (), ['2001:db8:64::53']),
            dict(clat='off', clat_prefix='64:ff9b::/96'))
        self.assertEqual((state['during']['route4'], calls), ([], []))


if __name__ == '__main__':
    unittest.main()
