# SPDX-License-Identifier: MIT
"""Synthetic USIM MSISDN records and byte-level read guards; no phone I/O."""
import contextlib
import io
from pathlib import Path
import struct
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
import msisdn
import sit

AID = bytes.fromhex('A0000000871002')


def status(*apps, present=1):
    body = bytearray([present, 0, len(apps)])
    for kind, state, aid in apps:
        app = bytearray(63)
        app[0], app[1], app[3] = kind, state, len(aid)
        app[4:4 + len(aid)] = aid
        body.extend(app)
    return bytes(body)


def record(number, *, ton=0x91, extension=0xff, size=32):
    body = bytearray(b'\xff' * size)
    if number:
        digits = number + ('f' if len(number) % 2 else '')
        bcd = bytes(int(digits[i + 1] + digits[i], 16) for i in range(0, len(digits), 2))
        body[-14] = len(bcd) + 1
        body[-13] = ton
        body[-12:-12 + len(bcd)] = bcd
    body[-1] = extension
    return bytes(body)


def sim_io(data=b'', sw1=0x90, sw2=0):
    return bytes([sw1, sw2]) + struct.pack('<h', len(data)) + data


class FakeCard:
    """Checks the real payload guard before returning synthetic SIM data."""
    def __init__(self, records=(), *, ready=True, present=1, fcp=True, count=None):
        self.records = list(records)
        self.ready = ready
        self.present = present
        self.fcp = fcp
        self.count = len(self.records) if count is None else count
        self.sent = []
        self.timeouts = []

    def request(self, ident, payload=b'', timeout=8):
        self.sent.append((ident, payload))
        self.timeouts.append(timeout)
        if ident == msisdn.GET_SIM_STATUS:
            if payload:
                raise AssertionError('GET_SIM_STATUS payload is not empty')
            return status((2, 5 if self.ready else 2, AID), present=self.present)
        if ident != msisdn.SIM_IO:
            raise AssertionError('unexpected modem request')
        sit.check(ident, msisdn=True, payload=payload)
        size = len(self.records[0]) if self.records else 32
        if payload[0] == msisdn.GET_RESPONSE:
            if self.fcp:
                fcp = bytes([0x82, 5, 0x42, 0x21, size >> 8, size & 255, self.count,
                             0x83, 2, 0x6f, 0x40])
                return sim_io(bytes([0x62, len(fcp)]) + fcp)
            legacy = bytearray(15)
            struct.pack_into('>H', legacy, 2, size * self.count)
            struct.pack_into('>H', legacy, 4, msisdn.EF_MSISDN)
            legacy[6], legacy[13], legacy[14] = 4, 1, size
            return sim_io(legacy)
        index = payload[17] - 1
        if not 0 <= index < len(self.records):
            return sim_io(sw1=0x6a, sw2=0x83)
        return sim_io(self.records[index])


class GuardTests(unittest.TestCase):
    def test_valid_reads_only(self):
        for command, p1, p2, p3 in [(0xc0, 0, 0, 15), (0xb2, 1, 4, 32), (0xb2, 8, 4, 255)]:
            payload = msisdn.request(command, AID, p1, p2, p3)
            self.assertEqual(len(payload), 560)
            msisdn.check_request(payload)

    def test_refuses_other_files_apps_commands_and_paths(self):
        good = msisdn.request(0xb2, AID, 1, 4, 32)
        changes = [(0, 0xd6), (0, 0xdc), (0, 0xb0), (1, 5),
                   (2, 0x09), (3, 0x2f), (4, 2), (5, 0x3f), (9, 1),
                   (17, 0), (17, 9), (18, 2), (19, 13), (19, 0),
                   (20, 1), (22, 0xaa), (533, 1), (534, 1), (535, 0x31),
                   (542, 1), (543, 0), (543, 17), (550, 4), (559, 1)]
        for offset, value in changes:
            bad = bytearray(good)
            bad[offset] = value
            with self.subTest(offset=offset, value=value), self.assertRaises(ValueError):
                msisdn.check_request(bad)
        for bad in (good[:-1], good + b'\0'):
            with self.assertRaises(ValueError):
                msisdn.check_request(bad)
        for params in [(0xc0, 1, 0, 15), (0xc0, 0, 1, 15), (0xc0, 0, 0, 0)]:
            with self.assertRaises(ValueError):
                msisdn.request(params[0], AID, *params[1:])

    def test_builder_refuses_isim_or_oversized_aid(self):
        for aid in (b'', bytes.fromhex('A0000000871004'), AID + b'\0' * 10):
            with self.assertRaises(ValueError):
                msisdn.request(0xc0, aid, 0, 0, 15)

    def test_transport_flags_do_not_grant_other_sim_access(self):
        good = msisdn.request(0xb2, AID, 1, 4, 32)
        sit.check(msisdn.SIM_IO, msisdn=True, payload=good)
        for options in ({}, {'isim_pcscf': True}):
            with self.assertRaises(ValueError):
                sit.check(msisdn.SIM_IO, payload=good, **options)
        wrong = bytearray(good)
        struct.pack_into('<H', wrong, 2, 0x6f07)  # IMSI is not MSISDN.
        with self.assertRaises(ValueError):
            sit.check(msisdn.SIM_IO, msisdn=True, isim_pcscf=True, payload=wrong)
        for ident in (0x020c, 0x020d, 0x0201, 0x0401):
            with self.assertRaises(ValueError):
                sit.check(ident, msisdn=True, isim_pcscf=True)


class ParserTests(unittest.TestCase):
    def test_international_national_and_unknown_ton(self):
        self.assertEqual(msisdn.parse_record(record('12025550123')), '+12025550123')
        self.assertEqual(msisdn.parse_record(record('2025550124', ton=0xa1)), '2025550124')
        self.assertEqual(msisdn.parse_record(record('2025550125', ton=0x81)), '2025550125')
        self.assertEqual(msisdn.parse_record(record('12025550123456789012')), '+12025550123456789012')

    def test_empty_records(self):
        self.assertIsNone(msisdn.parse_record(record('')))
        value = bytearray(record(''))
        value[-14] = 0
        self.assertIsNone(msisdn.parse_record(value))

    def test_extensions_never_publish_a_prefix(self):
        for extension in (0, 1, 254):
            with self.assertRaises(msisdn.IncompleteNumber):
                msisdn.parse_record(record('12025550123', extension=extension))

    def test_bad_records(self):
        good = record('12025550123')
        for offset, value in [(-14, 1), (-14, 12), (-13, 0x11), (-13, 0x93),
                              (-13, 0xd1), (-12, 0xfa), (-12, 0xf1), (-11, 0xaf), (-3, 0)]:
            bad = bytearray(good)
            bad[offset] = value
            with self.subTest(offset=offset, value=value), self.assertRaises(ValueError):
                msisdn.parse_record(bad)
        for bad in (b'\xff' * 13, b'\xff' * 256):
            with self.assertRaises(ValueError):
                msisdn.parse_record(bad)

    def test_usim_must_be_ready_and_present(self):
        self.assertEqual(msisdn.usim_aid(status((5, 5, bytes.fromhex('A0000000871004')),
                                               (2, 5, AID))), AID)
        for value in (status((2, 2, AID)), status((2, 5, AID), present=0),
                      status((2, 5, bytes.fromhex('A0000000871004'))), status()):
            self.assertIsNone(msisdn.usim_aid(value))
        for bad in (b'', b'\x01\0\x09', status((2, 5, AID))[:-1]):
            with self.assertRaises(ValueError):
                msisdn.usim_aid(bad)


class ReadTests(unittest.TestCase):
    def test_reads_only_msisdn_deduplicates_and_never_logs(self):
        for fcp in (True, False):
            card = FakeCard([record('12025550123'), record(''),
                             record('12025550123'), record('2025550124', ton=0xa1)], fcp=fcp)
            output = io.StringIO()
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                value = msisdn.read_numbers(card)
            self.assertEqual(value, dict(status='available', source='sim',
                                         numbers=['+12025550123', '2025550124']))
            self.assertEqual(output.getvalue(), '')
            self.assertEqual([ident for ident, _ in card.sent], [0x0200] + [0x0208] * 5)
            self.assertEqual([p[0] for i, p in card.sent if i == 0x0208], [0xc0] + [0xb2] * 4)
            self.assertTrue(all(0 < timeout <= msisdn.REQUEST_TIMEOUT for timeout in card.timeouts))

    def test_empty_file_and_missing_or_locked_sim(self):
        self.assertEqual(msisdn.read_numbers(FakeCard([record('')])),
                         dict(status='empty', source='sim', numbers=[]))
        for card in (FakeCard(ready=False), FakeCard(present=0)):
            self.assertEqual(msisdn.read_numbers(card)['reason'], 'sim-not-ready')
            self.assertEqual(len(card.sent), 1)

    def test_missing_file_and_bad_status_words_are_unavailable(self):
        card = FakeCard([record('12025550123')])
        original = card.request
        for sw1, sw2 in [(0x6a, 0x82), (0x98, 0x04), (0x90, 1)]:
            def answer(ident, payload=b'', timeout=8):
                return (original(ident, payload, timeout) if ident == 0x0200
                        else sim_io(sw1=sw1, sw2=sw2))
            with patch.object(card, 'request', side_effect=answer):
                value = msisdn.read_numbers(card)
            self.assertEqual(value, dict(status='unavailable', source='sim', numbers=[],
                                         reason='file-unavailable'))

    def test_extension_discards_partial_list(self):
        card = FakeCard([record('12025550123'), record('12025550124', extension=1)])
        self.assertEqual(msisdn.read_numbers(card), dict(status='incomplete', source='sim',
                         numbers=[], reason='extension-record'))

    def test_record_limit_is_bounded_before_reading_records(self):
        card = FakeCard([record('')], count=9)
        self.assertEqual(msisdn.read_numbers(card), dict(status='incomplete', source='sim',
                         numbers=[], reason='record-limit'))
        self.assertEqual(len(card.sent), 2)

    def test_timeout_and_transport_errors_never_return_error_text(self):
        for error, reason in [(TimeoutError('private'), 'timeout'),
                              (OSError('private'), 'read-failed'),
                              (RuntimeError('private'), 'read-failed'),
                              (ValueError('private'), 'invalid-response')]:
            with patch.object(FakeCard, 'request', side_effect=error):
                value = msisdn.read_numbers(FakeCard())
            self.assertEqual(value, dict(status='unavailable', source='sim', numbers=[], reason=reason))
            self.assertNotIn('private', str(value))

    def test_total_deadline_shrinks_request_timeout_and_stops(self):
        card = FakeCard([record('')])
        with patch.object(msisdn.time, 'monotonic', side_effect=[0, 1, 4, 4, 6]):
            value = msisdn.read_numbers(card)
        self.assertEqual(value['reason'], 'timeout')
        self.assertEqual(card.timeouts, [3.0, 1.0])

    def test_expired_budget_sends_nothing(self):
        card = FakeCard([record('')])
        with patch.object(msisdn.time, 'monotonic', side_effect=[0, 5]):
            value = msisdn.read_numbers(card)
        self.assertEqual(value['reason'], 'timeout')
        self.assertEqual(card.sent, [])

    def test_late_record_discards_partial_list(self):
        card = FakeCard([record('12025550123'), record('12025550124')])
        # One record completes at three seconds; the second reply arrives
        # after the total budget, so neither number may be returned.
        with patch.object(msisdn.time, 'monotonic', side_effect=[0, 0, 1, 1, 2, 2, 3, 4, 6]):
            value = msisdn.read_numbers(card)
        self.assertEqual([p[17] for i, p in card.sent
                          if i == msisdn.SIM_IO and p[0] == msisdn.READ_RECORD], [1, 2])
        self.assertEqual(card.timeouts[-1], 1.0)
        self.assertEqual(value, dict(status='unavailable', source='sim',
                                     numbers=[], reason='timeout'))

    def test_malformed_response_and_record_are_not_exposed(self):
        for payload in (b'', bytes([0x90, 0, 0xff, 0x7f]),
                        sim_io(b'bad private data')):
            card = FakeCard([record('12025550123')])
            original = card.request
            def answer(ident, body=b'', timeout=8):
                return original(ident, body, timeout) if ident == 0x0200 else payload
            with patch.object(card, 'request', side_effect=answer):
                value = msisdn.read_numbers(card)
            self.assertEqual(value['status'], 'unavailable')
            self.assertEqual(value['numbers'], [])
        card = FakeCard([record('12025550123'), b'\xff' * 31])
        self.assertEqual(msisdn.read_numbers(card)['reason'], 'invalid-response')

    def test_layout_requires_linear_fixed_and_expected_file(self):
        good = bytearray([0x62, 11, 0x82, 5, 0x42, 0x21, 0, 32, 1, 0x83, 2, 0x6f, 0x40])
        for offset, value in [(4, 0x41), (12, 0x09), (7, 13), (8, 0)]:
            bad = bytearray(good)
            bad[offset] = value
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                msisdn._layout(bad)


if __name__ == '__main__':
    unittest.main()
