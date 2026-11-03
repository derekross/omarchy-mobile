# SPDX-License-Identifier: MIT
"""The ISIM EF_PCSCF read: the SIM_IO guard, the record parser and ADD_PDN
filled from it. Made-up records, documentation-range addresses and a
made-up AID tail."""
import env  # noqa: F401  (paths and sys.path first)
import ipaddress
import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import ims
import isim
import sit

AID = isim.ISIM_AID_PREFIX + bytes(8)  # 15 bytes, made up
V6 = ipaddress.IPv6Address('2001:db8::5').packed
V6B = ipaddress.IPv6Address('2001:db8::6').packed


def record(kind, address, size=40):
    value = bytes([kind]) + address
    return (bytes([0x80, len(value)]) + value).ljust(size, b'\xff')


def status(*apps):
    payload = bytes([1, 0, len(apps)])
    for app_type, state, aid in apps:
        rec = bytearray(63)
        rec[0], rec[1], rec[3] = app_type, state, len(aid)
        rec[4:4 + len(aid)] = aid
        payload += bytes(rec)
    return payload


def sim_io_reply(data, sw1=0x90, sw2=0):
    return bytes([sw1, sw2]) + struct.pack('<h', len(data)) + data


def bearer(dns=True):
    r = bytearray(292)
    struct.pack_into('<HBBB', r, 0, 0, 2, 1, 2)
    r[9:25] = ipaddress.IPv6Address('2001:db8::2').packed
    if dns:
        r[0x1e:0x2e] = ipaddress.IPv6Address('2001:db8::53').packed
    return bytes(r)


class FakeCard:
    """A SIM_IO responder behind the real transport guard."""
    def __init__(self, records, fcp=True):
        self.records = records
        self.fcp = fcp
        self.sent = []

    def request(self, ident, payload=b'', timeout=8):
        sit.check(ident, isim_pcscf=True, payload=payload)
        self.sent.append((ident, payload))
        if ident == 0x0200:
            return status((2, 5, bytes.fromhex('A0000000871002')), (5, 5, AID))
        command, p1, p3 = payload[0], payload[17], payload[19]
        size = len(self.records[0])
        if command == isim.GET_RESPONSE:
            if self.fcp:
                fcp = bytes([0x82, 5, 0x42, 0x21]) + struct.pack('>H', size) + bytes([len(self.records)])
                return sim_io_reply(bytes([0x62, len(fcp)]) + fcp)
            two_g = bytearray(15)
            struct.pack_into('>H', two_g, 2, size * len(self.records))
            two_g[14] = size
            return sim_io_reply(bytes(two_g))
        if p1 > len(self.records):
            return sim_io_reply(b'', 0x6a, 0x83)
        return sim_io_reply(self.records[p1 - 1][:p3])


class GuardTests(unittest.TestCase):
    def test_the_two_reads_pass(self):
        isim.check_request(isim.request(isim.GET_RESPONSE, AID, 0, 0, 15))
        isim.check_request(isim.request(isim.READ_RECORD, AID, 1, 4, 40))
        sit.check(0x0208, isim_pcscf=True, payload=isim.request(isim.READ_RECORD, AID, 2, 4, 40))

    def test_sim_io_needs_the_owner_flag(self):
        with self.assertRaises(ValueError):
            sit.check(0x0208, payload=isim.request(isim.READ_RECORD, AID, 1, 4, 40))

    def refused(self, payload):
        with self.assertRaises(ValueError):
            sit.check(0x0208, isim_pcscf=True, payload=bytes(payload))

    def test_everything_else_is_refused(self):
        good = bytearray(isim.request(isim.READ_RECORD, AID, 1, 4, 40))
        for command in (0xB0, 0xD6, 0xDC, 0xF2, 0xA4, 0x88):   # binary, updates, status...
            bad = bytearray(good)
            bad[0] = command
            self.refused(bad)
        for offset, value in ((1, 2), (2, 0x02), (3, 0x2F), (4, 2), (9, 1), (18, 2), (17, 0)):
            bad = bytearray(good)
            bad[offset] = value
            self.refused(bad)
        # Other ISIM files: IMPI 6F02, IMPU 6F04, domain 6F03.
        for fid in (0x6F02, 0x6F03, 0x6F04, 0x2FE2):
            bad = bytearray(good)
            struct.pack_into('<H', bad, 2, fid)
            self.refused(bad)
        bad = bytearray(good)
        struct.pack_into('<H', bad, 20, 1)        # data
        bad[22] = 0xAA
        self.refused(bad)
        bad = bytearray(good)
        bad[534], bad[535] = 4, 0x31              # PIN2
        self.refused(bad)
        bad = bytearray(good)
        bad[544:544 + 7] = bytes.fromhex('A0000000871002')   # the USIM
        self.refused(bad)
        self.refused(good[:-1])
        with self.assertRaises(ValueError):
            sit.check(0x0208, isim_pcscf=True, payload=bytes(isim.request(isim.GET_RESPONSE, AID, 0, 1, 15)))

    def test_other_requests_keep_their_rules(self):
        with self.assertRaises(ValueError):
            sit.check(0x020c, isim_pcscf=True)        # TRANSMIT_SIM_APDU_BASIC
        with self.assertRaises(ValueError):
            sit.check(0x0400, isim_pcscf=True)        # GET_IMSI
        sit.check(0x0200, isim_pcscf=True)


class RecordTests(unittest.TestCase):
    def test_records(self):
        self.assertEqual(isim.parse_record(record(0, b'pcscf.ims.example.net')),
                         ('fqdn', 'pcscf.ims.example.net'))
        self.assertEqual(isim.parse_record(record(1, bytes([192, 0, 2, 7]))),
                         ('ipv4', bytes([192, 0, 2, 7])))
        self.assertEqual(isim.parse_record(record(2, V6)), ('ipv6', V6))
        self.assertEqual(isim.parse_record(record(2, b'2001:db8::6')), ('ipv6', V6B))
        self.assertEqual(isim.parse_record(record(1, b'192.0.2.9')),
                         ('ipv4', bytes([192, 0, 2, 9])))
        self.assertIsNone(isim.parse_record(b'\xff' * 40))
        self.assertIsNone(isim.parse_record(record(0, b'bad name!')))
        self.assertIsNone(isim.parse_record(record(7, b'x')))
        self.assertIsNone(isim.parse_record(bytes([0x80, 30, 0])))   # truncated

    def test_aid_only_from_a_ready_isim(self):
        self.assertEqual(isim.isim_aid(status((2, 5, b'\xa0'), (5, 5, AID))), AID)
        self.assertIsNone(isim.isim_aid(status((2, 5, b'\xa0'), (5, 2, AID))))
        self.assertIsNone(isim.isim_aid(status((2, 5, b'\xa0'))))

    def test_layouts(self):
        self.assertEqual(isim.record_layout(bytes([0x62, 7, 0x82, 5, 0x42, 0x21, 0, 40, 3])), (40, 3))
        two_g = bytearray(15)
        struct.pack_into('>H', two_g, 2, 120)
        two_g[14] = 40
        self.assertEqual(isim.record_layout(bytes(two_g)), (40, 3))


class ReadTests(unittest.TestCase):
    def test_reads_only_ef_pcscf_and_resolves_names(self):
        for fcp in (True, False):
            card = FakeCard([record(0, b'pcscf.ims.example.net'), record(2, V6),
                             record(1, bytes([192, 0, 2, 7])), b'\xff' * 40], fcp=fcp)
            asked = []

            def on_bearer(name, source, servers):
                asked.append((name, source, servers))
                return [V6B]
            with patch('builtins.print') as out:
                found = isim.ipv6_pcscf(card, card.request(0x0200), bearer(), resolve_bearer=on_bearer,
                                        resolve_host=lambda name: self.fail('host resolver used'))
            self.assertEqual(found, [V6, V6B])
            self.assertEqual(asked, [('pcscf.ims.example.net', '2001:db8::2', ['2001:db8::53'])])
            lines = [' '.join(map(str, c.args)) for c in out.call_args_list]
            self.assertIn('P-CSCF from ISIM: 3 addresses (1 FQDN, 1 IPv4, 1 IPv6)', lines)
            self.assertFalse(any(AID.hex() in l.lower() for l in lines))
            sim_io = [p for i, p in card.sent if i == 0x0208]
            self.assertEqual([p[0] for p in sim_io], [0xC0, 0xB2, 0xB2, 0xB2, 0xB2])
            self.assertEqual({struct.unpack_from('<H', p, 2)[0] for p in sim_io}, {0x6F09})

    def test_host_resolver_after_the_bearer(self):
        card = FakeCard([record(0, b'pcscf.ims.example.net')])
        with patch('builtins.print'):
            found = isim.ipv6_pcscf(card, card.request(0x0200), bearer(),
                                    resolve_bearer=lambda *a: [], resolve_host=lambda n: [V6])
        self.assertEqual(found, [V6])

    def test_dns_reply_parser(self):
        ident, query = isim.dns_query('pcscf.ims.example.net')
        answer = b'\xc0\x0c' + struct.pack('>HHIH', 28, 1, 60, 16) + V6
        reply = struct.pack('>HHHHHH', ident, 0x8180, 1, 1, 0, 0) + query[12:] + answer
        self.assertEqual(isim.dns_answers(reply, ident), [V6])
        self.assertEqual(isim.dns_answers(reply, ident ^ 1), [])


class AddPdnTests(unittest.TestCase):
    def test_add_pdn_filled_from_the_isim_only_when_the_pco_has_none(self):
        body = ims.add_pdn_payload(bearer(), fallback=[V6, V6B, V6, b'\0' * 16])
        self.assertEqual(body[39:41], bytes([0, 2]))
        self.assertEqual(body[41:73], V6 + V6B)
        with_pco = bytearray(bearer())
        with_pco[0x42] = 2
        with_pco[0x4f:0x5f] = ipaddress.IPv6Address('2001:db8::1').packed
        body = ims.add_pdn_payload(bytes(with_pco), fallback=[V6])
        self.assertEqual(body[39:57], bytes([0, 1]) + ipaddress.IPv6Address('2001:db8::1').packed)
        with self.assertRaises(ValueError):
            ims.add_pdn_payload(bearer(), fallback=[])

    def test_register_calls_the_fallback_on_an_empty_pco(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            state, response = tmp / 'ims-session.json', tmp / 'ims-response.bin'
            state.write_text(json.dumps({'cid': 2, 'session': 0}))
            response.write_bytes(bearer())

            class Client:
                bodies = []

                def request(self, ident, payload=b'', timeout=8):
                    if ident == 0x0602:
                        item = bytearray(132)
                        item[2] = 2
                        return bytes([1]) + bytes(item)
                    self.bodies.append((ident, payload))
                    return b''
            client = Client()
            seen = []
            with patch.object(ims, 'paths', return_value=(state, response)), \
                 patch.object(ims, 'REGISTRATION', tmp / 'reg.json'), patch('builtins.print'):
                ims.register(client, pcscf_fallback=lambda b: seen.append(b) or [V6])
            self.assertEqual(seen, [bearer()])
            add_pdn = [p for i, p in client.bodies if i == 0x0d08][0]
            self.assertEqual(add_pdn[39:57], bytes([0, 1]) + V6)


if __name__ == '__main__':
    unittest.main()
