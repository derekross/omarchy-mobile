# SPDX-License-Identifier: MIT
"""The T0 additions: SIM and radio state without identifiers, the emergency
numbers, and the event subscription (docs/TELEPHONY-APPS-PLAN.md T0)."""
import env  # noqa: F401  (paths and sys.path first)
import json
from pathlib import Path
import socket
import struct
import tempfile
import unittest
from unittest.mock import Mock, patch

import paths
import service as app_service


def sim_payload(card, apps=()):
    payload = bytes([card, 0, len(apps)])
    for app_type, state, pin, puk in apps:
        record = bytearray(63)
        record[0], record[1], record[59], record[60] = app_type, state, pin, puk
        # An AID and a label that must never come out.
        record[3], record[4:8] = 4, b'\xa0\x00\x00\x87'
        record[20], record[21:25] = 4, b'USIM'
        payload += bytes(record)
    return payload


class SimStatusTests(unittest.TestCase):
    def test_states(self):
        self.assertEqual(app_service.sim_status(bytes(3)), dict(state='absent'))
        self.assertEqual(app_service.sim_status(sim_payload(2)), dict(state='error'))
        self.assertEqual(app_service.sim_status(sim_payload(1)), dict(state='detected'))
        self.assertEqual(app_service.sim_status(sim_payload(1, [(2, 5, 3, 10)])),
                         dict(state='ready', pin_retries=3, puk_retries=10, pin_lock='unknown'))
        locked = bytearray(sim_payload(1, [(2, 5, 3, 10)]))
        for pin1, lock in ((3, 'off'), (2, 'on'), (1, 'on'), (0, 'unknown')):
            locked[3 + 57] = pin1
            self.assertEqual(app_service.sim_status(bytes(locked))['pin_lock'], lock)
        self.assertEqual(app_service.sim_status(sim_payload(1, [(2, 2, 2, 10)]))['state'], 'pin')
        self.assertEqual(app_service.sim_status(sim_payload(1, [(2, 3, 0, 9)]))['state'], 'puk')
        # The USIM wins over an ISIM listed first.
        self.assertEqual(app_service.sim_status(sim_payload(1, [(5, 1, 0, 0), (2, 5, 3, 10)]))['state'], 'ready')

    def test_layout_errors(self):
        for bad in (b'', bytes([1, 0, 1]), bytes([1, 0, 9]) + bytes(9 * 63)):
            with self.assertRaises(ValueError):
                app_service.sim_status(bad)

    def test_no_identifiers(self):
        status = app_service.sim_status(sim_payload(1, [(2, 5, 3, 10)]))
        self.assertNotIn('USIM', json.dumps(status))
        self.assertEqual(set(status), {'state', 'pin_retries', 'puk_retries', 'pin_lock'})


class StatusAndSubscriptionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.paths = patch.object(paths, 'RUN', self.root)
        self.paths.start()
        self.db = app_service.database(self.root / 'db')
        self.client = Mock()
        self.client.next_indication.return_value = None
        self.service = app_service.Service(self.client, self.db)

    def tearDown(self):
        for connection in list(self.service.subscribers):
            self.service.drop(connection)
        self.db.close()
        self.paths.stop()
        self.temp.cleanup()

    def poll_with(self, sim, radio, ps=bytes(4)):
        replies = {0x0200: sim, 0x0801: struct.pack('<I', radio), 0x0701: ps,
                   0x0702: bytearray(0x77 - 12)}
        self.client.request.side_effect = lambda ident, *a, **k: replies[ident]
        self.service.next_poll = 0
        self.service.poll()

    def test_poll_reads_sim_and_radio_read_only(self):
        self.poll_with(bytes(3), 3)
        modem = self.service.status()['modem']
        self.assertEqual((modem['sim'], modem['radio'], modem['registration']),
                         (dict(state='absent'), 'off', 'not-registered'))
        self.assertEqual(modem['emergency_numbers'], ['112', '911', '000', '08', '110', '118', '119', '999'])
        self.assertEqual([c.args[0] for c in self.client.request.call_args_list], [0x0200, 0x0801, 0x0701])
        self.poll_with(sim_payload(1, [(2, 5, 3, 10)]), 2)
        modem = self.service.status()['modem']
        self.assertEqual((modem['sim']['state'], modem['radio']), ('ready', 'on'))
        self.assertEqual(modem['emergency_numbers'], ['112', '911'])

    def test_failed_polls_keep_the_service_running(self):
        self.client.request.side_effect = TimeoutError()
        self.service.next_poll = 0
        self.service.poll()
        self.assertEqual(self.service.status()['modem']['sim'], dict(state='unknown'))

    def test_radio_indication(self):
        self.service.next_poll = 99e9
        self.service.event(struct.pack('<BBHHHI', 2, 0, 0x0802, 12, 0, 2))
        self.assertEqual(self.service.radio, 'on')
        self.assertEqual(self.service.next_poll, 0)
        self.client.request.assert_not_called()

    def test_subscriber_gets_status_and_changes_only(self):
        mine, theirs = socket.socketpair()
        self.addCleanup(theirs.close)
        self.service.subscribe(mine)
        first = json.loads(theirs.recv(65536))
        self.assertEqual(first['event'], 'status')
        self.assertEqual(first['status']['sms'], dict(received=[]))
        self.service.broadcast()
        theirs.setblocking(False)
        with self.assertRaises(BlockingIOError):
            theirs.recv(65536)
        call = self.service.new_call('+12025550123', 'incoming', 'ringing-in', 7)
        self.service.broadcast()
        event = json.loads(theirs.recv(65536))
        self.assertEqual(event['status']['calls'][0]['id'], call['id'])
        self.assertEqual(event['status']['calls'][0]['number'], '+12025550123')

    def test_subscriber_that_hangs_up_is_dropped(self):
        mine, theirs = socket.socketpair()
        self.service.subscribe(mine)
        theirs.close()
        self.service.reap()
        self.assertEqual(self.service.subscribers, [])

    def test_subscriber_limit(self):
        pairs = [socket.socketpair() for _ in range(app_service.SUBSCRIBERS + 1)]
        for mine, theirs in pairs:
            self.addCleanup(theirs.close)
        for mine, _ in pairs[:-1]:
            self.service.subscribe(mine)
        with self.assertRaises(RuntimeError):
            self.service.subscribe(pairs[-1][0])
        pairs[-1][0].close()

    def test_subscribe_over_the_socket_protocol(self):
        mine, theirs = socket.socketpair()
        self.addCleanup(theirs.close)
        import os
        theirs.sendall(b'{"action": "subscribe"}\n')
        kept = app_service.serve_one(self.service, mine, {os.getuid()})
        self.assertTrue(kept)
        reply, event = theirs.recv(65536).decode().splitlines()[:2]
        self.assertEqual(json.loads(reply), dict(ok=True, result=dict(subscribed=True)))
        self.assertEqual(json.loads(event)['event'], 'status')

    def test_stranger_cannot_subscribe(self):
        mine, theirs = socket.socketpair()
        self.addCleanup(theirs.close)
        theirs.sendall(b'{"action": "subscribe"}\n')
        self.assertFalse(app_service.serve_one(self.service, mine, set()))
        mine.close()
        self.assertFalse(json.loads(theirs.recv(65536))['ok'])
        self.assertEqual(self.service.subscribers, [])


if __name__ == '__main__':
    unittest.main()
