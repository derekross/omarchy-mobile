# SPDX-License-Identifier: MIT
"""IND_SIGNAL_STRENGTH decoding (sit_signal.py) on made-up reports in the
stock codec's layouts. Which layout this firmware sends is still to be
confirmed on hardware (MODEM-PLAN A8)."""
import env  # noqa: F401  (paths and sys.path first)
import struct
import unittest

import sit_signal

INT_MAX = 0x7fffffff


def report(mask, size, fields):
    body = bytearray(struct.pack('<i', INT_MAX) * (size // 4))
    for offset, value in fields.items():
        struct.pack_into('<i', body, offset, value)
    return struct.pack('<H', mask) + bytes(body)


class SignalTests(unittest.TestCase):
    def test_v2_lte(self):
        d = sit_signal.decode(report(0x04, 108, {0x3c: 20, 0x40: 95, 0x44: 10, 0x48: 120}))
        self.assertEqual(d, dict(layout='v2', lte=dict(rssi=-73, rsrp=-95, rsrq=-10, snr=12.0)))
        self.assertEqual(sit_signal.quality(d, 'LTE'), 60)

    def test_v4_lte_and_nr(self):
        d = sit_signal.decode(report(0x44, 196, {0x40: 110, 0x44: 12, 0x58: 100, 0x5c: 11, 0x60: 7}))
        self.assertEqual(d['layout'], 'v4')
        self.assertEqual(d['lte'], dict(rsrp=-110, rsrq=-12))
        self.assertEqual(d['nr'], dict(rsrp=-100, rsrq=-11, snr=7))
        self.assertEqual(sit_signal.quality(d, 'NR'), 50)
        self.assertEqual(sit_signal.quality(d, 'LTE'), 30)
        # V5 (200 bytes) shares V4's offsets.
        self.assertEqual(sit_signal.decode(report(0x04, 200, {0x40: 70}))['lte'], dict(rsrp=-70))

    def test_v1_lte(self):
        d = sit_signal.decode(report(0x08, 60, {0x20: 125}))
        self.assertEqual(d, dict(layout='v1', lte=dict(rsrp=-125)))
        self.assertEqual(sit_signal.quality(d), 0)

    def test_absent_or_out_of_range_reads_as_absent(self):
        self.assertEqual(sit_signal.decode(report(0x00, 108, {0x40: 95})), dict(layout='v2'))
        self.assertEqual(sit_signal.decode(report(0x04, 108, {0x40: 200, 0x44: 1, 0x3c: 99})), dict(layout='v2'))
        self.assertIsNone(sit_signal.decode(report(0x04, 40, {})))
        self.assertIsNone(sit_signal.decode(b'\x04'))
        self.assertEqual(sit_signal.quality(None), 0)
        self.assertEqual(sit_signal.quality(dict(layout='v2')), 0)


if __name__ == '__main__':
    unittest.main()
