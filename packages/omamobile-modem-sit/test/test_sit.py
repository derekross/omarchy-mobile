#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host-only transport tests; no modem or radio access."""
import env  # noqa: F401  (paths and sys.path first)
from collections import deque
import os
import socket
import struct
import tempfile
import threading
import unittest
from unittest.mock import patch
import sit
from sit import Sit


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.local, self.peer = socket.socketpair()
        self.local.setblocking(False)
        self.client = Sit.__new__(Sit)
        self.client.fd = self.local.fileno()
        self.client.token = 100
        self.client.buffer = bytearray()
        self.client.indications = deque()

    def tearDown(self):
        self.local.close()
        self.peer.close()

    def test_fragmented_reply_preserves_coalesced_indications(self):
        indication = struct.pack('<BBHHH', 2, 0, 0x0009, 8, 0)
        def reply():
            request = self.peer.recv(4096)
            token = struct.unpack_from('<I', request, 6)[0]
            response = struct.pack('<BBHHIBB', 1, 0, 0x0701, 16, token, 0, 0) + b'\x01\0\0\x15'
            self.peer.sendall(indication[:3])
            self.peer.sendall(indication[3:] + response + indication)
        worker = threading.Thread(target=reply)
        worker.start()
        self.assertEqual(self.client.request(0x0701), b'\x01\0\0\x15')
        worker.join(2)
        self.assertEqual(self.client.next_indication(), indication)
        self.assertEqual(self.client.next_indication(), indication)

    def test_telemetry_burst_preserves_sms_and_request_response(self):
        sms = struct.pack('<BBHHHBB', 2, 0, 0x0d1e, 11, 0, 7, 1)+b'x'
        def reply():
            request = self.peer.recv(4096)
            token = struct.unpack_from('<I', request, 6)[0]
            self.peer.sendall(sms)
            for index in range(400):
                self.peer.sendall(struct.pack('<BBHHHI', 2, 0, 0x0742, 12, 0, index))
            self.peer.sendall(struct.pack('<BBHHIBB', 1, 0, 0x0701, 16, token, 0, 0)+b'\1\0\0\x0e')
        worker = threading.Thread(target=reply)
        worker.start()
        self.assertEqual(self.client.request(0x0701), b'\1\0\0\x0e')
        worker.join(2)
        self.assertEqual(self.client.next_indication(), sms)
        self.assertEqual(struct.unpack_from('<I', self.client.next_indication(), 8)[0], 399)
        self.assertFalse(self.client.indications)

    def test_request_deadline_counts_suspend_and_preserves_indications(self):
        # Real socket I/O, with only the clocks advanced to model suspend.
        # A completed write does not prove that the modem did not execute it.
        for elapsed, error in ((7, 0), (8, 0), (9, 0), (9, 1)):
            with self.subTest(elapsed=elapsed, error=error):
                now = [100.0]
                token = self.client.token + 1
                indication = struct.pack('<BBHHH', 2, 0, 0x0009, 8, 0)
                response = struct.pack('<BBHHIBB', 1, 0, 0x0701, 13,
                                       token, error, 0) + b'x'
                self.peer.sendall(indication + response)
                real_read = os.read

                def resumed_read(fd, size):
                    data = real_read(fd, size)
                    now[0] += elapsed
                    return data

                def boottime(clock):
                    self.assertEqual(clock, sit.time.CLOCK_BOOTTIME)
                    return now[0]

                with patch.object(sit.time, 'monotonic', return_value=100.0), \
                        patch.object(sit.time, 'clock_gettime', side_effect=boottime), \
                        patch.object(sit.os, 'read', side_effect=resumed_read):
                    if elapsed < 8:
                        self.assertEqual(self.client.request(0x0701), b'x')
                    else:
                        with self.assertRaises(TimeoutError):
                            self.client.request(0x0701)
                self.assertEqual(self.client.next_indication(), indication)
                # Drain any late response without treating it as an indication.
                self.assertIsNone(self.client.next_indication(0.001))
                sent = self.peer.recv(4096)
                self.assertEqual(len(sent), 12)  # exactly one request, no retry
                self.assertEqual(struct.unpack_from('<I', sent, 6)[0], token)

    def test_reply_crossing_deadline_after_read_is_not_success(self):
        for error in (0, 1):
            with self.subTest(error=error):
                token = self.client.token + 1
                response = struct.pack('<BBHHIBB', 1, 0, 0x0701, 13,
                                       token, error, 0) + b'x'
                self.peer.sendall(response)
                now = [100.0]
                real_read_packet = self.client.read_packet

                def delayed_packet(timeout):
                    packet = real_read_packet(timeout)
                    now[0] += 8
                    return packet

                with patch.object(sit.time, 'monotonic', side_effect=lambda: now[0]), \
                        patch.object(sit.time, 'clock_gettime', side_effect=lambda _: now[0]), \
                        patch.object(self.client, 'read_packet', side_effect=delayed_packet):
                    with self.assertRaises(TimeoutError):
                        self.client.request(0x0701)

    def test_disallowed_commands_never_write(self):
        for command in (0x0001, 0x0100, 0x0d00, 0x0d02, 0x0d03, 0x0d0a, 0x0d1b, 0x0201, 0x0208, 0x020c, 0x0249):
            with self.assertRaises(ValueError):
                self.client.request(command)
        self.peer.setblocking(False)
        with self.assertRaises(BlockingIOError):
            self.peer.recv(1)

    def test_do_not_send_list_wins_over_the_allow_list(self):
        from unittest.mock import patch
        self.assertTrue(sit.DENIED)
        self.assertFalse(sit.DENIED & (sit.ALLOWED | sit.SMS | sit.CALLS))
        for ident in sorted(sit.DENIED)[:8] + [0x0e00, 0x1300]:
            with patch.object(sit, 'ALLOWED', sit.ALLOWED | {ident}), self.assertRaises(ValueError):
                self.client.request(ident)
        # no identity reads at all
        for ident in (0x0401, 0x0402):
            with self.assertRaises(ValueError):
                self.client.request(ident)

    def test_calls_and_sms_need_the_owner_flags(self):
        self.client.allow_calls = True
        self.client.allow_sms = True
        for ident in (0x0d00, 0x0d1b):
            sit.check(ident, sms=True, calls=True)
        with self.assertRaises(ValueError):
            sit.check(0x0100, sms=True, calls=True)

    def test_invalid_length_is_rejected(self):
        self.peer.sendall(struct.pack('<BBHH', 1, 0, 0x0701, 8))
        with self.assertRaises(RuntimeError):
            self.client.read_packet(0.1)

    def test_timeout_and_eof_are_distinct(self):
        self.assertIsNone(self.client.read_packet(0.01))
        self.peer.shutdown(socket.SHUT_WR)
        with self.assertRaises(EOFError):
            self.client.read_packet(0.1)

    def test_sms_persist_is_private_and_rejects_truncation(self):
        from pathlib import Path
        from unittest.mock import patch
        import inbox
        import paths
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(paths, 'INBOX', Path(directory) / 'inbox'):
            packet = struct.pack('<BBHHHBB', 2, 0, 0x010c, 13, 0, 7, 3) + b'\0\0\0'
            self.assertEqual(inbox.persist_sms(packet), 7)
            stored, = paths.INBOX.iterdir()
            self.assertEqual(stored.read_bytes(), packet)
            self.assertEqual(stored.stat().st_mode & 0o777, 0o600)
            self.assertEqual(paths.INBOX.stat().st_mode & 0o777, 0o700)
            with self.assertRaises(ValueError):
                inbox.persist_sms(packet[:-1])


if __name__ == '__main__':
    unittest.main()
