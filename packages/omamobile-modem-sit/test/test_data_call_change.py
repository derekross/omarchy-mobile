# SPDX-License-Identifier: MIT
"""sitd's log line for IND_DATA_CALL_LIST_CHANGED against the internet
bearer the data service runs on (SUSPEND-PLAN M6-D, 2026-11-15)."""
import env  # noqa: F401  (paths and sys.path first)
import struct
import unittest

import service as app_service


def item(cid, active=2, address=b'\x0a\x00\x00\x01', size=292):
    record = bytearray(size)
    struct.pack_into('<HBBB', record, 0, 0, cid, active, 1)
    record[5:5 + len(address)] = address
    return bytes(record)


def listing(*items):
    return bytes([len(items)]) + b''.join(items)


class DataCallChange(unittest.TestCase):
    def test_as_set_up(self):
        line = app_service.data_call_change(listing(item(3), item(2)), response=item(3))
        self.assertIn('the internet bearer (CID 3) has its setup addresses and DNS', line)
        self.assertIn('CID 2', line)

    def test_gone(self):
        line = app_service.data_call_change(listing(item(2)), response=item(3))
        self.assertIn('CID 3) is gone from the list', line)

    def test_inactive(self):
        line = app_service.data_call_change(listing(item(3, active=0)), response=item(3))
        self.assertIn('CID 3) is listed inactive', line)

    def test_new_address(self):
        line = app_service.data_call_change(listing(item(3, address=b'\x0a\x00\x00\x02')), response=item(3))
        self.assertIn('other addresses or DNS than at setup', line)

    def test_other_size_same_addresses(self):
        line = app_service.data_call_change(listing(item(3, size=280)), response=item(3, size=292))
        self.assertIn('has its setup addresses and DNS', line)
        self.assertIn('list item 280 bytes, setup response 292', line)

    def test_later_fields_ignored(self):
        later = bytearray(item(3)); later[0xf0] = 9
        line = app_service.data_call_change(listing(bytes(later)), response=item(3))
        self.assertIn('has its setup addresses and DNS', line)

    def test_dormant(self):
        line = app_service.data_call_change(listing(item(3, active=1)), response=item(3))
        self.assertIn('dormant', line)

    def test_dns_changed(self):
        other = bytearray(item(3)); other[0x1a:0x1e] = b'\x08\x08\x08\x08'
        line = app_service.data_call_change(listing(bytes(other)), response=item(3))
        self.assertIn('other addresses or DNS', line)

    def test_empty_list(self):
        line = app_service.data_call_change(b'\x00', response=item(3))
        self.assertIn('no bearers', line)
        self.assertIn('gone from the list', line)

    def test_unreadable(self):
        self.assertIn('unreadable', app_service.data_call_change(b'\x01\x02', response=item(3)))

    def test_no_address_in_the_line(self):
        line = app_service.data_call_change(listing(item(3, address=b'\xc0\xa8\x07\x09')), response=item(3))
        self.assertNotIn('192.168.7.9', line)
        self.assertNotIn('c0a80709', line)


if __name__ == '__main__':
    unittest.main()
