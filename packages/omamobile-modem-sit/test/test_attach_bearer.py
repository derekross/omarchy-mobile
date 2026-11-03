# SPDX-License-Identifier: MIT
"""attach_apn = none and IMS on the modem's own attach bearer: no
SET_INITIAL_ATTACH_APN, the attach bearer picked from the data-call list
(never one sitd owns), ADD_PDN_INFO from it, the fallback to sitd's own IMS
bearer, and the attach bearer never claimed or released. Documentation-range
addresses only."""
import env  # noqa: F401  (paths and sys.path first)
import ipaddress
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import Mock, patch

import bringup
import data_call
import ims
import paths


def item(cid, pdp=2, active=2, pcscf=3, dns=2, status=0, size=292):
    """A data-call item as the modem lists it: the stock attach bearer had
    type IPv6, three IPv6 P-CSCF addresses and two IPv6 DNS servers."""
    entry = bytearray(size)
    struct.pack_into('<HBBB', entry, 0, status, cid, active, pdp)
    entry[9:25] = ipaddress.IPv6Address(f'2001:db8:{cid}::2').packed
    for n, at in enumerate((0x1e, 0x32)[:dns]):
        entry[at:at + 16] = ipaddress.IPv6Address(f'2001:db8:53::{n + 1}').packed
    if pcscf:
        entry[0x42] = 2
        for n, at in enumerate((0x4f, 0x5f, 0x6f)[:pcscf]):
            entry[at:at + 16] = ipaddress.IPv6Address(f'2001:db8:cf::{n + 1}').packed
    return bytes(entry)


def listing(*items):
    return bytes([len(items)]) + b''.join(items)


class Isolated(unittest.TestCase):
    """Ownership and modem-owned records in a private directory."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        root = Path(self.directory.name)
        self.patches = [patch.object(data_call, 'STATE', root / 'data-session.json'),
                        patch.object(data_call, 'RESPONSE', root / 'data-call-response.bin'),
                        patch.object(data_call, 'MODEM_OWNED', root / 'modem-owned-bearers.json'),
                        patch.object(data_call, 'SETTLE_QUIET', 0),
                        patch.object(data_call, 'SETTLE_LIMIT', 0),
                        patch.object(ims, 'REGISTRATION', root / 'ims-registration.json'),
                        patch('builtins.print')]
        for p in self.patches:
            self.out = p.start()
        self.root = root

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.directory.cleanup()

    def own(self, cid):
        data_call.paths(cid)[0].write_text(json.dumps({'cid': cid, 'session': 0}))

    def lines(self):
        return [' '.join(str(a) for a in c.args) for c in self.out.call_args_list]


class ListTests(Isolated):
    def test_entries_and_summary_never_show_addresses(self):
        items = data_call.entries(listing(item(1, pdp=3, pcscf=0, dns=1), item(2)))
        self.assertEqual([i[2] for i in items], [1, 2])
        self.assertEqual(data_call.summary(items[1]), 'CID 2 IPv6 status 0 active 2 P-CSCF 3 DNS 2')
        self.assertNotIn('2001', data_call.summary(items[1]))
        self.assertEqual(data_call.call_ids(listing(item(1), item(2))), {1, 2})
        self.assertEqual(data_call.entries(b'\0'), [])

    def test_attach_bearer_is_ims_capable_and_not_sitd_owned(self):
        self.own(2)
        items = data_call.entries(listing(item(2), item(3)))
        self.assertEqual(data_call.attach_bearer(items)[2], 3)
        # sitd's own CID is never picked, even with a P-CSCF.
        self.assertIsNone(data_call.attach_bearer(items[:1]))
        for bad in (item(4, pcscf=0), item(4, pdp=1), item(4, active=0), item(4, status=36)):
            self.assertIsNone(data_call.attach_bearer([bad], owned=set()))
        self.assertEqual(data_call.attach_bearer([item(4, pdp=3)], owned=set())[2], 4)

    def test_a_sitd_owned_cid_is_never_recorded_as_modem_owned(self):
        self.own(1)
        with self.assertRaises(RuntimeError):
            data_call.record_modem_owned({1})
        data_call.record_modem_owned({2})
        data_call.record_modem_owned({2, 3})
        self.assertEqual(data_call.modem_owned_ids(), {2, 3})


class Modem:
    def __init__(self, listed):
        self.listed = listed
        self.sent = []

    def next_indication(self, timeout=1):
        return None

    def request(self, ident, payload=b'', **kwargs):
        self.sent.append((ident, payload))
        if ident == 0x0602:
            return self.listed()
        if ident == 0x0701:
            return b'\1\0\0\x0e'
        if ident == 0x0711:
            return b'\1'
        if ident == 0x0600:
            response = bytearray(292)
            struct.pack_into('<HBBB', response, 0, 0, payload[0], 2, 3)
            return bytes(response)
        return b''


class OwnershipTests(Isolated):
    def test_modem_owned_bearer_is_never_deactivated(self):
        data_call.record_modem_owned({2})
        modem = Modem(lambda: listing(item(2)))
        with self.assertRaises(RuntimeError) as raised:
            data_call.deactivate(modem, 2)
        self.assertIn('modem-owned', str(raised.exception))
        self.assertEqual(modem.sent, [])
        self.assertFalse(data_call.paths(2)[0].exists())

    def test_internet_setup_goes_ahead_beside_the_modem_owned_bearer(self):
        data_call.record_modem_owned({2})
        modem = Modem(lambda: listing(item(2)))
        data_call.activate(modem, 'internet.example')
        self.assertEqual(json.loads(data_call.STATE.read_text()), {'cid': 1, 'session': 0})
        # The modem-owned CID is never set up or claimed by sitd.
        with self.assertRaises(RuntimeError):
            data_call.activate(modem, 'ims', ims=True)
        self.assertFalse(data_call.paths(2)[0].exists())
        self.assertEqual([p[0] for i, p in modem.sent if i == 0x0600], [1])
        # Releasing the internet bearer leaves the modem's alone (no rmnet
        # device exists on the host, so none is up).
        modem.listed = lambda: listing(item(2))
        data_call.deactivate(modem, 1)
        self.assertEqual([p for i, p in modem.sent if i == 0x0601], [b'\1\0'])
        self.assertEqual(data_call.modem_owned_ids(), {2})

    def test_an_unrecorded_bearer_still_blocks_a_setup(self):
        modem = Modem(lambda: listing(item(3)))
        with self.assertRaises(RuntimeError):
            data_call.activate(modem, 'internet.example')
        self.assertNotIn(0x0600, [i for i, _ in modem.sent])


class AddPdnTests(Isolated):
    def test_add_pdn_from_the_attach_bearer(self):
        found = item(2)
        data_call.record_modem_owned({2})
        modem = Modem(lambda: listing(found))
        ims.register(modem, attach=found)
        body = next(p for i, p in modem.sent if i == 0x0d08)
        self.assertEqual(body[:2], bytes([2, 2]))                # IMS PDN, IPv6
        self.assertEqual(body[6:22], found[9:25])                # the bearer's address
        self.assertEqual(body[39:41], bytes([0, 3]))             # no IPv4, three IPv6 P-CSCF
        self.assertEqual(body[41:89], found[0x4f:0x7f])
        self.assertEqual(len(body), 679 + 2 * 16)
        # No ownership record was made for it.
        self.assertFalse(data_call.paths(2)[0].exists())

    def test_attach_bearer_on_another_cid(self):
        found = item(5)
        data_call.record_modem_owned({5})
        modem = Modem(lambda: listing(found))
        ims.register(modem, attach=found)
        self.assertIn(0x0d08, [i for i, _ in modem.sent])

    def test_pcscf_from_the_indication_when_the_list_has_none(self):
        found = item(2)
        data_call.record_modem_owned({2})
        modem = Modem(lambda: listing(item(2, pcscf=0)))
        ims.register(modem, attach=found)
        body = next(p for i, p in modem.sent if i == 0x0d08)
        self.assertEqual(body[40], 3)

    def test_gone_or_unrecorded_attach_bearer_sends_nothing(self):
        found = item(2)
        modem = Modem(lambda: listing(found))
        with self.assertRaises(RuntimeError):
            ims.register(modem, attach=found)               # not recorded as modem-owned
        data_call.record_modem_owned({2})
        modem = Modem(lambda: b'\0')
        with self.assertRaises(RuntimeError):
            ims.register(modem, attach=found)
        moved = bytearray(item(2))
        moved[9:25] = ipaddress.IPv6Address('2001:db8:9::2').packed
        modem = Modem(lambda: listing(bytes(moved)))
        with self.assertRaises(RuntimeError):
            ims.register(modem, attach=found)
        self.assertNotIn(0x0d08, [i for i, _ in modem.sent])


class FindTests(Isolated):
    def service(self, lists, indication=None):
        service = Mock()
        service.data_call_list = indication
        queue = list(lists)
        service.client.request.side_effect = lambda ident, *a, **k: queue.pop(0) if len(queue) > 1 else queue[0]
        return service

    def test_found_at_once_and_recorded(self):
        self.own(1)
        service = self.service([listing(item(1), item(2))])
        found = bringup.find_attach_bearer(service, 0, lambda: False, adopt_unknown=False)
        self.assertEqual(found[2], 2)
        self.assertEqual(data_call.modem_owned_ids(), {2})
        text = ' '.join(self.lines())
        self.assertIn('CID 2 IPv6 status 0 active 2 P-CSCF 3 DNS 2', text)
        self.assertNotIn('2001', text)

    def test_waits_for_it_and_reads_the_indication(self):
        service = self.service([b'\0'])
        calls = []

        def wait(svc, predicate, seconds, stopped):
            calls.append(seconds)
            self.assertFalse(predicate())
            svc.data_call_list = listing(item(2))
            self.assertTrue(predicate())
        with patch.object(bringup, 'wait_for', wait), \
                patch.object(bringup.time, 'monotonic', return_value=100):
            found = bringup.find_attach_bearer(service, 120, lambda: False, adopt_unknown=True)
        self.assertEqual(calls, [20])
        self.assertEqual(found[2], 2)

    def test_adopts_every_unknown_bearer_before_sitd_has_any(self):
        service = self.service([listing(item(2, pcscf=0), item(3, pdp=1))])
        self.assertIsNone(bringup.find_attach_bearer(service, 0, lambda: False, adopt_unknown=True))
        self.assertEqual(data_call.modem_owned_ids(), {2, 3})

    def test_none_after_the_deadline(self):
        service = self.service([listing(item(2, pcscf=0))])
        with patch.object(bringup, 'wait_for', side_effect=TimeoutError), \
                patch.object(bringup.time, 'monotonic', return_value=100):
            self.assertIsNone(bringup.find_attach_bearer(service, 120, lambda: False, adopt_unknown=False))
        self.assertEqual(data_call.modem_owned_ids(), set())
        self.assertIn('no modem-owned attach bearer with a P-CSCF listed', self.lines())

    def test_an_undecoded_list_is_logged_not_fatal(self):
        service = self.service([b'\1' + bytes(100)])
        self.assertIsNone(bringup.find_attach_bearer(service, 0, lambda: False, adopt_unknown=True))
        self.assertTrue(any('not decoded' in line for line in self.lines()))


class StartTests(unittest.TestCase):
    def start(self, attach_apn, found):
        settings = paths.config('/nonexistent')
        settings['network']['apn'] = 'VZWINTERNET'
        settings['network']['attach_apn'] = attach_apn
        settings['network']['ims_apn'] = 'IMS'
        service = Mock()
        service.registration.return_value = {'state': 2, 'features': 3}
        searches = []

        def find(svc, deadline, stopped, *, adopt_unknown):
            searches.append(adopt_unknown)
            return found
        with patch.object(bringup, 'wait_for'), patch.object(bringup, 'radio'), \
             patch.object(bringup, 'radio_state', return_value=0), \
             patch.object(bringup, 'provision_profiles') as profiles, \
             patch.object(bringup, 'nr_mode'), patch.object(bringup, 'data_snapshot'), \
             patch.object(bringup, 'find_attach_bearer', side_effect=find), \
             patch.object(bringup, 'clear_stale', return_value=0), patch.object(bringup, 'activate') as activate, patch.object(bringup, 'start_stack'), \
             patch.object(bringup, 'register') as register, patch('builtins.print'):
            bringup.start(service, settings)
        sent = [c.args[0] for c in service.client.request.call_args_list]
        return sent, profiles, activate, register, searches

    def test_attach_apn_none_sends_no_initial_attach(self):
        sent, profiles, activate, _, _ = self.start('none', None)
        self.assertNotIn(0x0603, sent)
        self.assertEqual([p.apn for p in profiles.call_args.args[1]], ['VZWINTERNET'])
        self.assertEqual(activate.call_args_list[0].args[1], 'VZWINTERNET')
        sent, *_ = self.start('NONE', None)
        self.assertNotIn(0x0603, sent)

    def test_ims_on_the_attach_bearer_skips_our_own_ims_setup(self):
        found = item(2)
        _, _, activate, register, searches = self.start('none', found)
        self.assertEqual([c.args[1] for c in activate.call_args_list], ['VZWINTERNET'])
        self.assertIs(register.call_args.kwargs['attach'], found)
        self.assertIsNone(register.call_args.kwargs['pcscf_fallback'])
        self.assertEqual(searches, [True])

    def test_fallback_to_our_own_ims_bearer(self):
        _, _, activate, register, searches = self.start('none', None)
        self.assertEqual([c.args[1] for c in activate.call_args_list], ['VZWINTERNET', 'IMS'])
        self.assertTrue(activate.call_args_list[1].kwargs['ims'])
        self.assertIsNone(register.call_args.kwargs['attach'])
        self.assertIsNotNone(register.call_args.kwargs['pcscf_fallback'])
        self.assertEqual(searches, [True, False])

    def test_explicit_attach_apn_looks_once_without_adopting(self):
        with patch.object(bringup, 'initial_attach'):
            _, _, _, _, searches = self.start('IMS', None)
        self.assertEqual(searches, [False])


if __name__ == '__main__':
    unittest.main()
