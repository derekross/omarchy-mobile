# SPDX-License-Identifier: MIT
"""sitd's log line for IND_DATA_CALL_LIST_CHANGED against the internet
bearer the data service runs on (SUSPEND-PLAN M6-D, 2026-11-15)."""
import env  # noqa: F401  (paths and sys.path first)
import struct
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import data_call
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


class Reconnect(unittest.TestCase):
    """The internet bearer set up again after the modem drops it."""
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        self.state, self.response = root / 'data-session.json', root / 'data-call-response.bin'
        self.state.write_text('{"cid": 3, "session": 0}')
        self.response.write_bytes(item(3))
        self.patches = [patch.object(data_call, 'RESPONSE', self.response),
                        patch.object(data_call, 'INTERNET_CID', 3),
                        patch.object(app_service, 'bearer_paths', lambda cid: (self.state, self.response)),
                        patch.object(app_service.subprocess, 'run'),
                        patch('builtins.print')]
        for p in self.patches:
            p.start()
        self.client = Mock()
        self.listed = listing(item(2))
        self.client.request.side_effect = lambda ident, *a, **k: {0x0701: b'\x01\x00\x00\x0e', 0x0602: self.listed}[ident]
        self.db = app_service.database(root / 'db')
        self.service = app_service.Service(self.client, self.db)
        self.service.publish = Mock()
        self.service.current_stage = 'running'
        self.service.internet_setup = dict(apn='internet', ip_type='ipv4v6')
        self.service.reconnect_at = None
        self.service.reconnect_tries = 0
        self.service.reconnecting = False

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.db.close()
        self.temp.cleanup()

    def indication(self, payload):
        return struct.pack('<BBHHxx', 2, 0, 0x0604, 8 + len(payload)) + payload

    def test_dropped_detects_gone_and_inactive(self):
        self.assertTrue(app_service.internet_dropped(listing(item(2)), response=item(3)))
        self.assertFalse(app_service.internet_dropped(listing(item(3, active=0)), response=item(3)))
        self.assertFalse(app_service.internet_dropped(listing(item(3, active=1)), response=item(3)))
        self.assertFalse(app_service.internet_dropped(b'\x01\x02', response=item(3)))

    def test_a_drop_schedules_and_the_setup_runs_with_start_ups_settings(self):
        app_service.subprocess.run.return_value.returncode = 0     # mobile data on
        self.service.event(self.indication(listing(item(2))))
        self.assertIsNotNone(self.service.reconnect_at)
        self.assertTrue(self.service.reconnect_data)
        self.service.reconnect_at = 0
        with patch.object(data_call, 'activate') as activate:
            self.service.reconnect()
        activate.assert_called_once()
        self.assertEqual(activate.call_args.args[1], 'internet')
        self.assertEqual(activate.call_args.kwargs['ip_type'], 'ipv4v6')
        self.assertFalse(self.state.exists())       # the stale record was cleared first
        calls = [c.args[0] for c in app_service.subprocess.run.call_args_list]
        self.assertIn(['systemctl', 'stop', 'omamobile-sit-data.service'], calls)
        self.assertEqual(calls[-1], ['systemctl', 'start', 'omamobile-sit-data.service'])
        self.assertIsNone(self.service.reconnect_at)

    def test_data_off_stays_off(self):
        app_service.subprocess.run.return_value.returncode = 3     # the route service stopped
        self.service.event(self.indication(listing(item(2))))
        self.service.reconnect_at = 0
        with patch.object(data_call, 'activate'):
            self.service.reconnect()
        calls = [c.args[0] for c in app_service.subprocess.run.call_args_list]
        self.assertNotIn(['systemctl', 'start', 'omamobile-sit-data.service'], calls)

    def test_held_without_its_setup_is_released_first(self):
        self.listed = listing(item(2), item(3))
        self.response.unlink()                       # a setup that timed out kept only the record
        self.service.reconnect_at = 0
        order = []
        with patch.object(data_call, 'deactivate', side_effect=lambda *a: order.append('release')) as release, \
                patch.object(data_call, 'activate', side_effect=lambda *a, **k: order.append('setup')):
            self.service.reconnect()
        release.assert_called_once_with(self.client, 3)
        self.assertEqual(order, ['release', 'setup'])

    def test_radio_off_cancels(self):
        self.service.radio = 'off'
        self.service.reconnect_at = 0
        with patch.object(data_call, 'activate') as activate:
            self.service.reconnect()
        activate.assert_not_called()
        self.assertIsNone(self.service.reconnect_at)

    def test_a_live_call_waits(self):
        self.service.calls = {'x': dict(state='active')}
        self.service.reconnect_at = 0
        with patch.object(data_call, 'activate') as activate:
            self.service.reconnect()
        activate.assert_not_called()
        self.assertGreater(self.service.reconnect_at, 0)

    def test_no_schedule_during_start_up_or_its_own_setup(self):
        self.service.current_stage = 'data'
        self.service.event(self.indication(listing(item(2))))
        self.assertIsNone(self.service.reconnect_at)
        self.service.current_stage = 'running'
        self.service.reconnecting = True
        self.service.event(self.indication(listing(item(2))))
        self.assertIsNone(self.service.reconnect_at)

    def test_listed_again_needs_nothing(self):
        self.listed = listing(item(2), item(3))
        self.service.reconnect_at = 0
        with patch.object(data_call, 'activate') as activate:
            self.service.reconnect()
        activate.assert_not_called()
        self.assertTrue(self.state.exists())
        self.assertIsNone(self.service.reconnect_at)

    def test_not_registered_waits(self):
        self.client.request.side_effect = lambda ident, *a, **k: b'\x02\x00\x00\x0e'
        self.service.reconnect_at = 0
        with patch.object(data_call, 'activate') as activate:
            self.service.reconnect()
        activate.assert_not_called()
        self.assertGreater(self.service.reconnect_at, 0)

    def test_a_stale_ring_doesnt_hold_it(self):
        self.service.calls = {'x': dict(state='ringing-in', since=app_service.time.time() - 600)}
        self.service.reconnect_at = 0
        with patch.object(data_call, 'activate') as activate:
            self.service.reconnect()
        activate.assert_called_once()

    def test_a_fresh_ring_waits(self):
        self.service.calls = {'x': dict(state='ringing-in', since=app_service.time.time())}
        self.service.reconnect_at = 0
        with patch.object(data_call, 'activate') as activate:
            self.service.reconnect()
        activate.assert_not_called()

    def test_failure_backs_off(self):
        delays = []
        for _ in range(7):
            self.service.reconnect_at = 0
            with patch.object(data_call, 'activate', side_effect=RuntimeError('data call did not become active')), \
                    patch.object(app_service.time, 'monotonic', return_value=1000):
                self.service.reconnect()
            delays.append(self.service.reconnect_at - 1000)
        self.assertEqual(delays, [15, 30, 60, 120, 240, 300, 300])
        for _ in range(5):
            self.service.reconnect_at = 0
            with patch.object(data_call, 'activate', side_effect=RuntimeError('refused')):
                self.service.reconnect()
        self.assertEqual(self.service.reconnect_at - time.monotonic() > 1700, True)   # every 30 minutes after twelve
        calls = [c.args[0] for c in app_service.subprocess.run.call_args_list]
        self.assertNotIn(['systemctl', 'start', 'omamobile-sit-data.service'], calls)


if __name__ == '__main__':
    unittest.main()
