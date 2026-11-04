#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host-only lifecycle failure tests; no radio/device access."""
import env  # noqa: F401  (paths and sys.path first)
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import data_call

APN = 'internet.example'


class Modem:
    def __init__(self, status=0, fail_release=False):
        self.sent = []
        self.status = status
        self.fail_release = fail_release

    def next_indication(self, timeout=1):
        return None

    def request(self, ident, payload=b'', **kwargs):
        self.sent.append((ident, payload))
        if ident == 0x0701:
            return b'\1\0\0\x15'
        if ident == 0x0602:
            return b'\0'
        if ident == 0x0711:
            return b'\1'
        if ident == 0x061a:
            return struct.pack('<i', 3)
        if ident == 0x0600:
            response = bytearray(292)
            struct.pack_into('<HBBB', response, 0, self.status, payload[0], 0 if self.status else 1, 2)
            return response
        if ident == 0x0601 and self.fail_release:
            raise TimeoutError('synthetic release failure')
        return b''


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        root = Path(self.directory.name)
        self.state = root / 'owned.json'
        self.response = root / 'response.bin'
        self.patches = [patch.object(data_call, 'STATE', self.state),
                        patch.object(data_call, 'RESPONSE', self.response),
                        patch.object(data_call, 'SETTLE_QUIET', 0),
                        patch.object(data_call, 'SETTLE_LIMIT', 0)]
        for item in self.patches:
            item.start()

    def tearDown(self):
        for item in self.patches:
            item.stop()
        self.directory.cleanup()

    def test_records_of_an_earlier_start_are_cleared_when_the_modem_lists_none(self):
        class Empty:
            def request(self, ident, payload=b'', **kwargs):
                return b'\0'
        ims_state, ims_response = data_call.paths(2)
        registration = ims_state.with_name('ims-registration.json')
        records = (self.state, self.response, ims_state, ims_response, registration)
        for path in records:
            path.write_text('{}')
        data_call.clear_stale(Empty())
        for path in records:
            self.assertFalse(path.exists())

    def test_a_reservation_without_a_confirmed_outcome_stays(self):
        class Empty:
            def request(self, ident, payload=b'', **kwargs):
                return b'\0'
        ims_state, ims_response = data_call.paths(2)
        registration = ims_state.with_name('ims-registration.json')
        for path in (self.state, self.response, ims_state, registration):
            path.write_text('{}')
        data_call.clear_stale(Empty())
        self.assertFalse(self.state.exists() or self.response.exists())     # confirmed: cleared
        self.assertTrue(ims_state.exists() and registration.exists())      # IMS setup unanswered

    def test_records_stay_while_the_modem_lists_a_bearer(self):
        class Listed:
            def request(self, ident, payload=b'', **kwargs):
                record = bytearray(132)
                record[2] = 1
                return b'\1' + bytes(record)
        self.state.write_text('{}')
        data_call.clear_stale(Listed())
        self.assertTrue(self.state.exists())

    def test_rejected_setup_leaves_no_ownership(self):
        modem = Modem(status=36)
        with self.assertRaises(RuntimeError):
            data_call.activate(modem, APN)
        self.assertEqual(modem.sent[-1][0], 0x0600)
        self.assertFalse({0x061a, 0x061b} & {i for i, _ in modem.sent})
        self.assertFalse(self.state.exists())
        self.assertFalse(self.response.exists())

    def test_rejected_setup_keeps_the_record_and_listens(self):
        # The refused record goes to a private file, and the modem's next
        # messages are logged by name with a data-call list decoded to
        # status, CID, active and PDP type.
        modem = Modem(status=36)
        record = bytearray(292)
        struct.pack_into('<HBBB', record, 0, 36, 1, 0, 0)
        indication = struct.pack('<BBHHxx', 2, 0, 0x0604, 8 + 1 + len(record)) + b'\1' + bytes(record)
        queue = [indication, None]
        modem.next_indication = lambda timeout=1: queue.pop(0) if queue else None
        clock = iter([0, 0, 0, 0, 1, 2, 10] + [100] * 20)
        with patch('data_call.time.monotonic', side_effect=lambda: next(clock)), \
                patch('builtins.print') as printed:
            with self.assertRaises(RuntimeError):
                data_call.activate(modem, APN)
        failed = self.response.with_name('failed-setup-cid1.bin')
        self.assertTrue(failed.exists())
        self.assertEqual(len(failed.read_bytes()), 292)
        lines = ' '.join(str(call.args[0]) for call in printed.call_args_list)
        self.assertIn('IND_DATA_CALL_LIST_CHANGED', lines)
        self.assertIn('[(36, 1, 0, 0)]', lines)
        kept = self.response.with_name('indications.bin').read_bytes()
        self.assertEqual(kept, struct.pack('<H', len(indication)) + indication)
        self.assertFalse(self.state.exists())
        self.assertFalse(self.response.exists())

    def test_cellular_setups_carry_no_pdu_session_id(self):
        # Stock leaves the PDU session ID unset (0) on cellular and never
        # sends ALLOC_PDU_SESSION for it: the modem picks the ID.
        modem = Modem()
        request = modem.request
        def listed(ident, payload=b'', **kwargs):
            if ident == 0x0602 and self.state.exists():
                record = bytearray(292)
                record[2:4] = bytes([1, 1])
                return bytes([1]) + record
            return request(ident, payload, **kwargs)
        modem.request = listed
        data_call.activate(modem, APN)
        data_call.activate(modem, 'ims', ims=True)
        setups = [p for i, p in modem.sent if i == 0x0600]
        self.assertEqual([(p[0], struct.unpack_from('<i', p, 0xf6 - 12)[0]) for p in setups], [(1, 0), (2, 0)])
        self.assertFalse({0x061a, 0x061b} & {i for i, _ in modem.sent})
        self.assertEqual(json.loads(self.state.read_text()), {'cid': 1, 'session': 0})
        self.assertEqual(json.loads(data_call.paths(2)[0].read_text()), {'cid': 2, 'session': 0})
        data_call.paths(2)[0].unlink()

    def test_setup_waits_for_the_modem_to_go_quiet_and_rereads_registration(self):
        # After the data permission, indications are drained and logged, the
        # registration is read again, and only then does the setup go out.
        modem = Modem()
        packet = struct.pack('<BBHHxx', 2, 0, 0x0604, 8 + 1) + b'\0'
        queue = [packet, None]
        modem.next_indication = lambda timeout=1: queue.pop(0) if queue else None
        with patch.object(data_call, 'SETTLE_QUIET', 5), patch.object(data_call, 'SETTLE_LIMIT', 5), \
                patch('data_call.time.monotonic', side_effect=[0, 0, 0, 1, 1, 9, 9, 9, 9, 9]), \
                patch('builtins.print') as printed:
            data_call.activate(modem, APN)
        lines = [str(call.args[0]) for call in printed.call_args_list]
        self.assertTrue(any(line.startswith('after allowing data: IND_') for line in lines))
        self.assertIn('registration before the setup: PS state, reject, RAT', ' '.join(lines))
        idents = [i for i, _ in modem.sent]
        self.assertLess(idents.index(0x0710), idents.index(0x0600))
        self.assertEqual(idents.count(0x0701), 2)

    def test_indications_during_the_wait_reach_the_service(self):
        # An SMS that arrives while the setup waits (or after a refusal) is
        # handed to the service, which stores and acknowledges it, not only
        # recorded.
        sms = struct.pack('<BBHHxx', 2, 0, 0x0d1e, 8 + 4) + b'sms!'
        for status in (0, 36):
            modem = Modem(status=status)
            queue = [sms, None] if status == 0 else [None]
            after = [sms, None]
            def next_indication(timeout=1, queue=queue, after=after, modem=modem):
                if any(i == 0x0600 for i, _ in modem.sent):
                    return after.pop(0) if after else None
                return queue.pop(0) if queue else None
            modem.next_indication = next_indication
            handled = []
            ticks = iter(range(10 ** 6))
            with patch.object(data_call, 'SETTLE_QUIET', 5), patch.object(data_call, 'SETTLE_LIMIT', 5), \
                    patch('data_call.time.monotonic', side_effect=lambda: next(ticks)), patch('builtins.print'):
                if status:
                    with self.assertRaises(RuntimeError):
                        data_call.activate(modem, APN, on_event=handled.append)
                else:
                    data_call.activate(modem, APN, on_event=handled.append)
                    self.state.unlink()
                    self.response.unlink(missing_ok=True)
            self.assertEqual(handled, [sms], f'status {status}')

    def test_existing_ownership_prevents_setup(self):
        self.state.write_text('{}')
        modem = Modem()
        with self.assertRaises(RuntimeError):
            data_call.activate(modem, APN)
        self.assertNotIn(0x0600, [i for i, _ in modem.sent])

    def test_setup_timeout_keeps_the_ownership_record(self):
        modem = Modem()
        request = modem.request
        def timeout(ident, payload=b'', **kwargs):
            if ident == 0x0600:
                raise TimeoutError('unknown setup outcome')
            return request(ident, payload, **kwargs)
        modem.request = timeout
        with self.assertRaises(TimeoutError):
            data_call.activate(modem, APN)
        self.assertEqual(json.loads(self.state.read_text()), {'cid': 1, 'session': 0})
        self.assertNotIn(0x061b, [i for i, _ in modem.sent])

    def test_failed_deactivation_retains_recovery_record(self):
        self.state.write_text(json.dumps({'cid': 1, 'session': 3}))
        self.response.write_bytes(b'private')
        original = Path.read_text
        def read(path, *args, **kwargs):
            if str(path) == '/sys/class/net/rmnet0/flags':
                return '0x0'
            return original(path, *args, **kwargs)
        modem = Modem(fail_release=True)
        with patch.object(Path, 'read_text', read), self.assertRaises(TimeoutError):
            data_call.deactivate(modem)
        self.assertEqual(modem.sent, [(0x0601, b'\1\0')])
        self.assertTrue(self.state.exists())
        self.assertTrue(self.response.exists())

    def test_ims_failure_preserves_active_internet_bearer(self):
        self.state.write_text(json.dumps({'cid': 1, 'session': 2}))
        self.response.write_bytes(b'existing private internet configuration')
        modem = Modem(status=36)
        request = modem.request
        def existing(ident, payload=b'', **kwargs):
            if ident == 0x0602:
                record = bytearray(292)
                record[2:4] = bytes([1, 1])
                return bytes([1]) + record
            return request(ident, payload, **kwargs)
        modem.request = existing
        with self.assertRaises(RuntimeError):
            data_call.activate(modem, 'ims', ims=True)
        self.assertEqual(json.loads(self.state.read_text()), {'cid': 1, 'session': 2})
        self.assertEqual(self.response.read_bytes(), b'existing private internet configuration')
        self.assertFalse(data_call.paths(2)[0].exists())
        self.assertEqual(modem.sent[-1][0], 0x0600)
        self.assertNotIn(0x061b, [i for i, _ in modem.sent])

    def test_deactivation_releases_only_an_allocated_pdu_session(self):
        original = Path.read_text
        def read(path, *args, **kwargs):
            if str(path) == '/sys/class/net/rmnet0/flags':
                return '0x0'
            return original(path, *args, **kwargs)
        # session 0 (this version) and 3 (a record from 0.3.4 or earlier)
        for session, sent in ((0, [(0x0601, b'\1\0'), (0x0602, b'')]),
                              (3, [(0x0601, b'\1\0'), (0x0602, b''), (0x061b, struct.pack('<i', 3))])):
            self.state.write_text(json.dumps({'cid': 1, 'session': session}))
            modem = Modem()
            with patch.object(Path, 'read_text', read):
                data_call.deactivate(modem)
            self.assertEqual(modem.sent, sent)
            self.assertFalse(self.state.exists())

    def test_unowned_bearer_blocks_additional_setup(self):
        modem = Modem()
        request = modem.request
        def unowned(ident, payload=b'', **kwargs):
            if ident == 0x0602:
                record = bytearray(292)
                record[2:4] = bytes([1, 1])
                return bytes([1]) + record
            return request(ident, payload, **kwargs)
        modem.request = unowned
        with self.assertRaises(RuntimeError):
            data_call.activate(modem, 'ims', ims=True)
        self.assertNotIn(0x061a, [i for i, _ in modem.sent])

    def test_setup_layout_and_apn_check(self):
        payload = data_call.setup_payload(1, 14, 3, APN)
        self.assertEqual(len(payload), 983 - 12)
        self.assertEqual(payload[4:4 + len(APN)], APN.encode())
        self.assertEqual((payload[0xda - 12], payload[0xf5 - 12]), (3, 2))
        ims = data_call.setup_payload(2, 14, 4, 'ims', ims=True)
        self.assertEqual((ims[3], ims[0xda - 12], ims[0xdb - 12]), (1, 2, 2))
        # An IPv4v6 IMS APN (stock: the APN's protocol, GetPcscfReqType).
        both = data_call.setup_payload(2, 14, 0, 'ims', ims=True, ip_type='ipv4v6')
        self.assertEqual((both[0xda - 12], both[0xdb - 12]), (3, 3))
        # The APN-type bitmap at 0xf1: DEFAULT for the internet bearer, IMS
        # for the IMS one; the attach request carries none and keeps its
        # length and roaming type.
        self.assertEqual(struct.unpack_from('<I', payload, 0xf1 - 12)[0], 1)
        self.assertEqual(struct.unpack_from('<I', ims, 0xf1 - 12)[0], 0x40)
        # The IMS profile's whole bitmask when given (stock: ApnSetting's
        # supported types, ims|ia on Verizon); nothing else changes.
        ia = data_call.setup_payload(2, 14, 0, 'ims', ims=True, ip_type='ipv4v6', apn_types=0x140)
        self.assertEqual(struct.unpack_from('<I', ia, 0xf1 - 12)[0], 0x140)
        self.assertEqual(ia[:0xf1 - 12] + ia[0xf5 - 12:], both[:0xf1 - 12] + both[0xf5 - 12:])
        for bad in (0, 0x1000, -1):
            with self.assertRaises(ValueError):
                data_call.setup_payload(2, 14, 0, 'ims', ims=True, apn_types=bad)
        modem = Modem()
        data_call.initial_attach(modem, APN)
        ident, attach = modem.sent[-1]
        self.assertEqual((ident, len(attach)), (0x0603, 251 - 12))
        self.assertEqual(attach[0xf1 - 12:0xf5 - 12], bytes(4))
        self.assertEqual((attach[0xda - 12], attach[0xf8 - 12]), (3, 3))
        # An internet-APN attach asks for no P-CSCF and has the default type.
        self.assertEqual((attach[0x0f - 12], attach[0xdb - 12], attach[0xf9 - 12]), (0, 0, 0))
        # An attach on the IMS APN marks the IMS type and asks for the
        # P-CSCF (home and roaming) by the IP type, as stock's builder does.
        for ip_type, request in (('ipv4v6', 3), ('ipv6', 2), ('ipv4', 1)):
            data_call.initial_attach(modem, 'ims', ip_type, ims=True)
            attach = modem.sent[-1][1]
            self.assertEqual((attach[0x0f - 12], attach[0xdb - 12], attach[0xf9 - 12]), (1, request, request))
            self.assertEqual(attach[0xda - 12], attach[0xf8 - 12])
        for bad in ('', 'a b', 'x' * 100, 'apn;rm', '.lead'):
            with self.assertRaises(ValueError):
                data_call.setup_payload(1, 14, 3, bad)

    def test_call_list_rejects_truncation_and_duplicate_cids(self):
        with self.assertRaises(RuntimeError):
            data_call.call_ids(bytes([1]) + bytes(291))
        record = bytearray(292)
        record[2] = 1
        with self.assertRaises(RuntimeError):
            data_call.call_ids(bytes([2]) + record + record)



class ProfileTests(unittest.TestCase):
    """SET_DATA_PROFILE (0x0613) in stock's 246-byte layout, and the
    [profiles] lines. Example APNs only."""

    def full(self, profile):
        # The request as on the wire, header included, so offsets match stock's.
        payload = data_call.profile_payload(profile)
        self.assertEqual(len(payload), 246 - 12)
        return bytes(12) + payload

    def test_offsets(self):
        profile = data_call.parse_profile('2', 'ims.example; types=ia,ims; ip=ipv4v6; roaming_ip=ipv6')
        full = self.full(profile)
        self.assertEqual(struct.unpack_from('<I', full, 0x0c)[0], 2)
        self.assertEqual(full[0x10:0x10 + 100].rstrip(b'\0'), b'ims.example')
        self.assertEqual((full[0x75], full[0x76], full[0x77]), (3, 2, 0))
        self.assertEqual(full[0x78:0xdb], bytes(0xdb - 0x78))       # no user or password
        self.assertEqual(struct.unpack_from('<IIIBII', full, 0xdd), (300, 20, 0, 1, 64 | 256, 0))
        self.assertEqual(full[0xf2:], bytes(4))

    def test_bitmask_and_ids(self):
        cases = {'default': 1, 'mms': 2, 'supl': 4, 'dun': 8, 'fota': 32, 'ims': 64, 'cbs': 128, 'ia': 256}
        for name, bit in cases.items():
            self.assertEqual(data_call.parse_profile('0', f'apn.example; types={name}').types, bit)
        self.assertEqual(data_call.parse_profile('0', 'a.example; types=default,supl,dun').types, 13)
        self.assertEqual(data_call.parse_profile('4', 'a.example; types=cbs,mms').types, 130)
        for ident in (0, 2, 3, 4, 1000):
            full = self.full(data_call.parse_profile(str(ident), 'a.example; types=default'))
            self.assertEqual(struct.unpack_from('<I', full, 0x0c)[0], ident)

    def test_pdp_types(self):
        for name, value in data_call.IP_TYPES.items():
            full = self.full(data_call.parse_profile('3', f'a.example; types=fota; ip={name}'))
            self.assertEqual((full[0x75], full[0x76]), (value, value))   # roaming follows home
        full = self.full(data_call.parse_profile('3', 'a.example; types=fota; ip=ipv4; roaming_ip=ipv6'))
        self.assertEqual((full[0x75], full[0x76]), (1, 2))
        self.assertEqual(data_call.parse_profile('3', 'a.example; types=fota').ip, 'ipv4v6')

    def test_default_profile_is_unchanged_from_0_3_14(self):
        # 0.3.14's encoder, kept here as the reference.
        old = bytearray(246)
        old[16:16 + len(APN)] = APN.encode()
        old[0x75] = old[0x76] = 3
        old[0xe9] = 1
        struct.pack_into('<I', old, 0xea, 1)
        self.assertEqual(data_call.profile_payload(data_call.default_profile(APN)), bytes(old[12:]))
        modem = Modem()
        data_call.provision_default_profile(modem, APN)
        self.assertEqual(modem.sent, [(0x0613, bytes(old[12:]))])

    def test_good_lines_tolerate_spacing_and_case(self):
        profile = data_call.parse_profile(' 2 ', '  ims.example ;types = IA, ims ;  IP=IPv4v6;roaming_ip= ipv6 ')
        self.assertEqual((profile.ident, profile.apn, profile.types, profile.ip, profile.roaming_ip),
                         (2, 'ims.example', 320, 'ipv4v6', 'ipv6'))

    def test_bad_lines(self):
        bad = [('x', 'a.example; types=ims'),                   # not a number
               ('7', 'a.example; types=ims'),                   # not an Android profile ID
               ('-1', 'a.example; types=ims'),
               ('2', 'a.example'),                              # no types
               ('2', 'a.example; types='),
               ('2', 'a.example; types=ims,voice'),             # unknown type
               ('2', '; types=ims'),                            # no APN
               ('2', 'bad apn!; types=ims'),
               ('2', 'a.example; types=ims; ip=ipv5'),
               ('2', 'a.example; types=ims; roaming_ip=x'),
               ('2', 'a.example; types=ims; mtu=1400'),         # unknown field
               ('2', 'a.example; types=ims; ip'),               # no value
               ('2', 'a.example; types=ims; types=ia')]         # twice
        for key, value in bad:
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                data_call.parse_profile(key, value)

    def settings(self, profiles=''):
        import paths
        settings = paths.config('/nonexistent')
        settings['network']['apn'] = APN
        settings.read_string('[profiles]\n' + profiles)
        return settings

    def test_empty_profiles_send_only_the_default(self):
        self.assertEqual(data_call.configured_profiles(self.settings()), [data_call.default_profile(APN)])

    def test_profiles_in_id_order_and_profile_0_replaced(self):
        found = data_call.configured_profiles(self.settings(
            '4 = cbs.example; types=cbs,mms\n'
            '2 = ims.example; types=ia,ims; roaming_ip=ipv6\n'
            '0 = internet.example; types=default,supl,dun\n'))
        self.assertEqual([p.ident for p in found], [0, 2, 4])
        self.assertEqual(found[0].types, 13)
        self.assertEqual(found[0].max_conns, 20)                      # stock's, not the legacy 0
        found = data_call.configured_profiles(self.settings('3 = fota.example; types=fota\n'))
        self.assertEqual([p.ident for p in found], [0, 3])
        self.assertEqual(found[0], data_call.default_profile(APN))

    def test_a_bad_line_fails_the_whole_set(self):
        with self.assertRaises(ValueError):
            data_call.configured_profiles(self.settings('2 = ims.example; types=ims\n3 = x; types=nope\n'))
        with self.assertRaises(ValueError):                           # 2 and 02 are one ID
            data_call.configured_profiles(self.settings('2 = a.example; types=ims\n02 = b.example; types=ims\n'))

    def test_the_chosen_apn_and_a_carriers_profiles(self):
        # The APN chosen at start-up (not [network] apn) makes profile 0.
        found = data_call.configured_profiles(self.settings(), 'chosen.example')
        self.assertEqual(found, [data_call.default_profile('chosen.example')])
        # A carrier override's lines, when [profiles] is empty.
        extra = [('2', 'ims.example; types=ia,ims; roaming_ip=ipv6'), ('4', 'cbs.example; types=cbs,mms')]
        found = data_call.configured_profiles(self.settings(), 'chosen.example', extra)
        self.assertEqual([(p.ident, p.apn) for p in found], [(0, 'chosen.example'), (2, 'ims.example'), (4, 'cbs.example')])
        found = data_call.configured_profiles(self.settings(), 'chosen.example', [('0', 'own.example; types=default')])
        self.assertEqual([(p.ident, p.apn) for p in found], [(0, 'own.example')])
        # [profiles] with any line replaces the override's set.
        found = data_call.configured_profiles(self.settings('3 = fota.example; types=fota\n'), 'chosen.example', extra)
        self.assertEqual([p.ident for p in found], [0, 3])
        # No APN known and no profile 0: nothing for the internet.
        self.assertEqual(data_call.configured_profiles(self.settings(), ''), [])
        self.assertEqual([p.ident for p in data_call.configured_profiles(self.settings(), '', extra)], [2, 4])
        with self.assertRaises(ValueError):
            data_call.configured_profiles(self.settings(), 'chosen.example', [('2', 'x; types=nope')])

    def test_shipped_config_has_no_profiles(self):
        import paths
        conf = Path(__file__).resolve().parent.parent / 'etc/omamobile/modem-sit.conf'
        settings = paths.config(str(conf))
        settings['network']['apn'] = APN
        self.assertEqual(settings.items('profiles', raw=True), [])
        self.assertEqual(data_call.configured_profiles(settings), [data_call.default_profile(APN)])


if __name__ == '__main__':
    unittest.main()
