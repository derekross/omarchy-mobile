# SPDX-License-Identifier: MIT
"""MMS ownership and permission isolation; no hardware or network access."""
import env  # noqa: F401
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

import data_call

APN = 'mms.example'


def record(cid, active=2, status=0):
    result = bytearray(292)
    struct.pack_into('<HBBB', result, 0, status, cid, active, 3)
    return bytes(result)


class Modem:
    def __init__(self):
        self.records = {1: record(1), 2: record(2)}
        self.sent = []
        self.permission = b'\1'
        self.refusal = 0
        self.timeout = False
        self.release_timeout = False

    def request(self, ident, payload=b'', **kwargs):
        self.sent.append((ident, payload))
        if ident == 0x0701:
            return b'\1\0\0\x0e'
        if ident == 0x0711:
            return self.permission
        if ident == 0x0602:
            return bytes([len(self.records)]) + b''.join(self.records.values())
        if ident == 0x0600:
            if self.timeout:
                raise TimeoutError('unknown setup outcome')
            if self.refusal:
                return record(payload[0], 0, self.refusal)
            self.records[payload[0]] = record(payload[0])
            return self.records[payload[0]]
        if ident == 0x0601:
            if self.release_timeout:
                raise TimeoutError('unknown release outcome')
            self.records.pop(payload[0])
            return b''
        raise AssertionError(f'Unexpected MMS request {ident:04x}')


class MmsBearerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        for name, path in (('STATE', root / 'data-session.json'),
                           ('RESPONSE', root / 'data-call-response.bin')):
            patcher = patch.object(data_call, name, path)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = patch.object(data_call, 'listen_after_failure')
        patcher.start()
        self.addCleanup(patcher.stop)
        self.modem = Modem()
        for cid in (1, 2):
            state, response = data_call.paths(cid)
            state.write_text(json.dumps({'cid': cid, 'session': 0}))
            response.write_bytes(record(cid))
        self.originals = {path: path.read_bytes() for cid in (1, 2) for path in data_call.paths(cid)}

    def assert_existing_unchanged(self):
        for path, content in self.originals.items():
            self.assertEqual(path.read_bytes(), content)

    def assert_no_setup(self):
        self.assertNotIn(0x0600, [ident for ident, _ in self.modem.sent])
        self.assertFalse(data_call.paths(3)[0].exists())
        self.assert_existing_unchanged()

    def test_mms_layout_uses_its_own_bitmap_not_the_legacy_selector(self):
        for protocol, expected in (('ipv4', 1), ('ipv6', 2), ('ipv4v6', 3)):
            payload = bytes(12) + data_call.setup_payload(3, 14, 0, APN, mms=True, ip_type=protocol)
            self.assertEqual(len(payload), 983)
            self.assertEqual(payload[12:16], bytes([3, 14, 0, 0]))
            self.assertEqual(payload[0xd9:0xdc], bytes([0, expected, 0]))
            self.assertEqual(struct.unpack_from('<I', payload, 0xf1)[0], 2)
            self.assertEqual(struct.unpack_from('<i', payload, 0xf6)[0], 0)

    def test_setup_and_release_preserve_internet_and_ims_without_permission_writes(self):
        data_call.activate(self.modem, APN, mms=True)
        self.assertEqual(data_call.owned_ids(), {1, 2, 3})
        self.assert_existing_unchanged()
        self.assertEqual([i for i, _ in self.modem.sent], [0x0701, 0x0602, 0x0711, 0x0701, 0x0600])
        state, response = data_call.paths(3)
        self.assertEqual(state.stat().st_mode & 0o777, 0o600)
        self.assertEqual(response.stat().st_mode & 0o777, 0o600)
        original = Path.read_text
        def read(path, *args, **kwargs):
            if str(path) == '/sys/class/net/rmnet2/flags':
                return '0x0'
            return original(path, *args, **kwargs)
        with patch.object(Path, 'read_text', read):
            data_call.deactivate(self.modem, 3)
        self.assertEqual(self.modem.sent[-2:], [(0x0601, b'\3\0'), (0x0602, b'')])
        self.assertEqual(data_call.owned_ids(), {1, 2})
        self.assertFalse(response.exists())
        self.assert_existing_unchanged()

    def test_refusal_releases_only_mms_reservation(self):
        self.modem.refusal = 36
        with self.assertRaises(RuntimeError):
            data_call.activate(self.modem, APN, mms=True)
        self.assertEqual(data_call.owned_ids(), {1, 2})
        self.assertTrue(data_call.RESPONSE.with_name('failed-setup-cid3.bin').exists())
        self.assert_existing_unchanged()

    def test_timeout_keeps_mms_ownership_and_blocks_retry(self):
        self.modem.timeout = True
        with self.assertRaises(TimeoutError):
            data_call.activate(self.modem, APN, mms=True)
        self.assertEqual(data_call.owned_ids(), {1, 2, 3})
        self.modem.sent.clear()
        with self.assertRaises(RuntimeError):
            data_call.activate(self.modem, APN, mms=True)
        self.assertEqual([i for i, _ in self.modem.sent], [0x0701, 0x0602])
        self.assert_existing_unchanged()

    def test_release_timeout_keeps_all_ownership(self):
        data_call.activate(self.modem, APN, mms=True)
        self.modem.release_timeout = True
        original = Path.read_text
        def read(path, *args, **kwargs):
            return '0x0' if str(path) == '/sys/class/net/rmnet2/flags' else original(path, *args, **kwargs)
        with patch.object(Path, 'read_text', read), self.assertRaises(TimeoutError):
            data_call.deactivate(self.modem, 3)
        self.assertEqual(data_call.owned_ids(), {1, 2, 3})
        self.assert_existing_unchanged()

    def test_host_link_up_blocks_release(self):
        data_call.activate(self.modem, APN, mms=True)
        before = list(self.modem.sent)
        original = Path.read_text
        def read(path, *args, **kwargs):
            return '0x1' if str(path) == '/sys/class/net/rmnet2/flags' else original(path, *args, **kwargs)
        exists = Path.exists
        def present(path, *args, **kwargs):
            return True if str(path) == '/sys/class/net/rmnet2/flags' else exists(path, *args, **kwargs)
        with patch.object(Path, 'read_text', read), patch.object(Path, 'exists', present), \
             self.assertRaisesRegex(RuntimeError, 'host data'):
            data_call.deactivate(self.modem, 3)
        self.assertEqual(self.modem.sent, before)
        self.assertEqual(data_call.owned_ids(), {1, 2, 3})
        self.assert_existing_unchanged()

    def test_mms_does_not_require_an_ims_bearer(self):
        self.modem.records.pop(2)
        for path in data_call.paths(2):
            path.unlink()
            self.originals.pop(path)
        data_call.activate(self.modem, APN, mms=True)
        self.assertEqual(data_call.owned_ids(), {1, 3})
        self.assert_existing_unchanged()

    def test_permission_off_never_changes_global_permission(self):
        self.modem.permission = b'\0'
        with self.assertRaisesRegex(RuntimeError, 'already enabled'):
            data_call.activate(self.modem, APN, mms=True)
        self.assert_no_setup()

    def test_reserved_internet_without_response_is_not_connected(self):
        data_call.RESPONSE.unlink()
        self.originals.pop(data_call.RESPONSE)
        with self.assertRaises(RuntimeError):
            data_call.activate(self.modem, APN, mms=True)
        self.assert_no_setup()

    def test_inactive_listed_internet_cannot_enable_mms(self):
        self.modem.records[1] = record(1, 0)
        with self.assertRaises(RuntimeError):
            data_call.activate(self.modem, APN, mms=True)
        self.assert_no_setup()

    def test_unknown_bearer_is_not_adopted(self):
        self.modem.records[4] = record(4)
        with self.assertRaises(RuntimeError):
            data_call.activate(self.modem, APN, mms=True)
        self.assert_no_setup()

    def test_invalid_configuration_sends_nothing(self):
        for options in ({'ims': True, 'mms': True}, {'mms': True, 'ip_type': 'bad'}):
            with self.assertRaises(ValueError):
                data_call.activate(self.modem, APN, **options)
        with self.assertRaises(ValueError):
            data_call.activate(self.modem, 'not an apn', mms=True)
        self.assertEqual(self.modem.sent, [])
        self.assert_no_setup()
