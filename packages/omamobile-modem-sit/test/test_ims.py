# SPDX-License-Identifier: MIT
"""Host-only IMS framing checks with documentation-range IPv6 fixtures."""
import env  # noqa: F401  (paths and sys.path first)
import configparser
import hashlib
import ipaddress
from pathlib import Path
import struct
import tempfile
import unittest

import ims
import paths
from ims import add_pdn_payload, hidden_menu


class ImsPayloadTests(unittest.TestCase):
    def response(self):
        result = bytearray(292)
        struct.pack_into('<HBBB', result, 0, 0, 2, 1, 2)
        result[9:25] = ipaddress.IPv6Address('2001:db8::2').packed
        result[0x42] = 2
        for offset in (0x4f, 0x5f):
            result[offset:offset+16] = ipaddress.IPv6Address('2001:db8::1').packed
        return result

    def test_ipv6_only_pdn_has_deduplicated_pcscf_and_fixed_extension(self):
        body = add_pdn_payload(self.response())
        self.assertEqual(body[:6], bytes([2, 2, 0, 0, 0, 0]))
        self.assertEqual(body[22:33], struct.pack('<6BH3B', 17, 0, 0, 1, 0, 0, 35, 0, 0, 1))
        self.assertEqual(body[39:41], bytes([0, 1]))
        self.assertEqual(body[41:57], ipaddress.IPv6Address('2001:db8::1').packed)
        self.assertEqual(body[-502:-488], struct.pack('<HHHQ', 12, 1, 8, 0))
        self.assertEqual(body[-488:], bytes(488))
        self.assertEqual(len(body), 679)

    def test_inactive_or_missing_pcscf_is_rejected(self):
        result = self.response()
        result[3] = 0
        with self.assertRaises(ValueError):
            add_pdn_payload(result)
        result = self.response()
        result[0x4f:0x7f] = bytes(48)
        with self.assertRaises(ValueError):
            add_pdn_payload(result)

    def test_configuration_segment_length_and_complete_flag(self):
        packet = hidden_menu()
        complete, length = struct.unpack_from('<BH', packet)
        self.assertEqual(complete, 0)
        self.assertEqual(length, len(packet)-3)
        self.assertEqual(packet[3:9], struct.pack('<HI', 523, 30))


def golden_response():
    r = bytearray(292)
    struct.pack_into('<HBBB', r, 0, 0, 2, 1, 2)
    r[9:25] = ipaddress.IPv6Address('2001:db8:1::2').packed
    r[0x1e:0x2e] = ipaddress.IPv6Address('2001:db8:1::53').packed
    r[0x32:0x42] = ipaddress.IPv6Address('2001:db8:1::54').packed
    r[0x42] = 2
    r[0x4f:0x5f] = ipaddress.IPv6Address('2001:db8:1::10').packed
    r[0x5f:0x6f] = ipaddress.IPv6Address('2001:db8:1::11').packed
    return bytes(r)


# What omamobile-modem-sit 0.3.3 sent (the values that registered IMS on the
# one network proven so far), recorded before they became configurable.
GOLDEN_HIDDEN_MENU = '69aaa62f25c320ffe797e7b4c38d7791abc3ba360a8dff5360ba71d898655762'
GOLDEN_ADD_PDN = 'd9f3421fa3b3eb462744f51db1a7122b4531861f5db23448aec62d9db887bbb8'


def digest(data):
    return hashlib.sha256(data).hexdigest()


class ImsValuesTests(unittest.TestCase):
    def test_defaults_are_byte_identical(self):
        # No config, the shipped config, an empty [ims] section, and a profile
        # directory without this network's file: all the proven bytes.
        shipped = configparser.ConfigParser(interpolation=None)
        shipped.read_dict(paths.DEFAULTS)
        shipped.read(Path(__file__).resolve().parent.parent / 'etc/omamobile/modem-sit.conf')
        empty = configparser.ConfigParser(interpolation=None)
        empty.read_string('[ims]\n')
        with tempfile.TemporaryDirectory() as temp:
            nowhere = configparser.ConfigParser(interpolation=None)
            nowhere.read_dict(dict(ims=dict(profile_dir=temp)))
            for settings in (None, paths.config('/nonexistent'), shipped, empty, nowhere):
                v = ims.values(settings, '00101')
                self.assertEqual(v.source, 'defaults')
                self.assertEqual(digest(hidden_menu(v)), GOLDEN_HIDDEN_MENU)
                self.assertEqual(digest(add_pdn_payload(golden_response(), v)), GOLDEN_ADD_PDN)
        self.assertEqual(digest(hidden_menu()), GOLDEN_HIDDEN_MENU)
        self.assertEqual(digest(add_pdn_payload(golden_response())), GOLDEN_ADD_PDN)

    def test_config_and_network_profile(self):
        with tempfile.TemporaryDirectory() as temp:
            settings = configparser.ConfigParser(interpolation=None)
            settings.read_dict(dict(ims=dict(hidden_menu='523:20 600:1', add_pdn_flags='17 0 0 1 0 0 3 0 0 1',
                                             profile_dir=temp)))
            v = ims.values(settings, '00101')
            self.assertEqual((v.source, v.hidden_menu, v.pdn_flags[6]), ('config', ((523, 20), (600, 1)), 3))
            packet = hidden_menu(v)
            self.assertEqual(packet[3:15], struct.pack('<HIHI', 523, 20, 600, 1))
            body = add_pdn_payload(golden_response(), v)
            self.assertEqual(body[22:33], struct.pack('<6BH3B', 17, 0, 0, 1, 0, 0, 3, 0, 0, 1))
            Path(temp, '00101.conf').write_text('[ims]\nhidden_menu = 529:7\n')
            v = ims.values(settings, '00101')
            self.assertEqual((v.source, v.hidden_menu, v.pdn_flags[6]), ('network profile', ((529, 7),), 3))
            # Another network, or no PLMN known: the config's values.
            self.assertEqual(ims.values(settings, '00102').source, 'config')
            self.assertEqual(ims.values(settings, '').source, 'config')
            self.assertEqual(ims.values(settings, '../00101').source, 'config')

    def test_bad_values_are_refused(self):
        for text in ('523', '523:x', '70000:1', '523:4294967296', '775:1', '523:1 523:2'):
            with self.assertRaises(ValueError):
                ims.parse_hidden_menu(text)
        for text in ('17 0 0 1', '17 0 0 1 0 0 35 0 0 256', '17 0 0 1 0 0 65536 0 0 1', '17 0 0 1 0 0 -1 0 0 1'):
            with self.assertRaises(ValueError):
                ims.parse_pdn_flags(text)


if __name__ == '__main__':
    unittest.main()
