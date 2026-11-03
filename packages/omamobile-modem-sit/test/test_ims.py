# SPDX-License-Identifier: MIT
"""Host-only IMS framing checks with documentation-range IPv6 fixtures."""
import env  # noqa: F401  (paths and sys.path first)
import ipaddress
import struct
import unittest
from data_call import pcscf_addresses
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

    def test_pcscf_from_the_234_byte_item_extension(self):
        # Base slots empty (family 3), the addresses in the extension: version
        # byte 2 at 0x84, IPv4 at 0x86, IPv6 at 0x9a (stock's layout).
        result = self.response()
        result[4] = 3
        result[0x42] = 3
        result[0x4f:0x7f] = bytes(48)
        result[0x84] = 2
        result[0x86:0x8a] = ipaddress.IPv4Address('192.0.2.7').packed
        for n, offset in enumerate((0x9a, 0xaa, 0xba, 0xca)):
            result[offset:offset + 16] = ipaddress.IPv6Address(f'2001:db8::{n + 5}').packed
        v4, v6 = pcscf_addresses(result)
        self.assertEqual(v4, [ipaddress.IPv4Address('192.0.2.7').packed])
        self.assertEqual(len(v6), 4)
        body = add_pdn_payload(result)
        self.assertEqual(body[39:41], bytes([0, 3]))  # at most three announced
        self.assertEqual(body[41:57], ipaddress.IPv6Address('2001:db8::5').packed)
        # Without the version byte the extension isn't read.
        result[0x84] = 0
        self.assertEqual(pcscf_addresses(result), ([], []))
        with self.assertRaises(ValueError):
            add_pdn_payload(result)
        # pcscf_required = no: an empty list, the same layout otherwise.
        empty = add_pdn_payload(result, pcscf_required=False)
        self.assertEqual(empty[39:41], bytes([0, 0]))
        self.assertEqual(len(empty), len(body) - 3 * 16)

    def test_pcscf_base_slots_follow_the_family_byte(self):
        result = bytearray(132)
        result[0x43:0x47] = ipaddress.IPv4Address('192.0.2.1').packed
        result[0x4f:0x5f] = ipaddress.IPv6Address('2001:db8::1').packed
        for family, counts in ((0, (0, 0)), (1, (1, 0)), (2, (0, 1)), (3, (1, 1))):
            result[0x42] = family
            v4, v6 = pcscf_addresses(result)
            self.assertEqual((len(v4), len(v6)), counts)

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


if __name__ == '__main__':
    unittest.main()
