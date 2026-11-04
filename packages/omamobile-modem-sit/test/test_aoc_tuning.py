# SPDX-License-Identifier: MIT
"""Synthetic AoC service records only; never open a device or use a blob."""
import env  # noqa: F401
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

import aoc_tuning as tuning


class Services:
    def __init__(self):
        self.opened = []
        self.closed = []
        self.written = []
        self.reply = None
        self.pending = False
        self.timeout = False
        self.short_fd = None
        self.refuse = False
        self.bad_reply = False

    def open(self, path, flags):
        self.opened.append((path, flags))
        return 10 if path.endswith('output_tuning') else 11

    def close(self, fd):
        self.closed.append(fd)

    def select(self, read, write, errors, timeout):
        if write:
            return [], write, []
        return (read if (self.pending if timeout == 0 else not self.timeout) else []), [], []

    def write(self, fd, data):
        self.written.append((fd, data))
        if fd == 10:
            reply = bytearray(data)
            # As the palmtop's AoC does: the second header byte comes back
            # rewritten, the rest of the header as sent.
            reply[1] = 0x3e
            if self.refuse:
                struct.pack_into('<h', reply, 6, -3)
                self.refuse = False
            if self.bad_reply:
                reply[4] ^= 1
            self.reply = bytes(reply)
        return len(data) - 1 if fd == self.short_fd else len(data)

    def read(self, fd, count):
        return self.reply


class TuningTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.marker = self.root / 'uncertain'
        for route in ('speaker', 'handset'):
            for name, value in ((f'uplink_{route}_aec_on_config.pb', b'\x08\x01'),
                                (f'uplink_{route}_aec_off_config.pb', b'\x08\x00'),
                                (f'downlink_{route}_config.pb', b'\x10\x01')):
                (self.root / name).write_bytes(value)
        self.io = Services()
        for target, name, value in ((tuning, 'UNCERTAIN', self.marker),
                                    (tuning.os, 'open', self.io.open),
                                    (tuning.os, 'close', self.io.close),
                                    (tuning.os, 'write', self.io.write),
                                    (tuning.os, 'read', self.io.read),
                                    (tuning.select, 'select', self.io.select)):
            patcher = patch.object(target, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def voice(self, route='speaker'):
        return tuning.VoiceTuning(route, root=self.root)

    def test_bulk_envelopes_and_confirmed_off_cleanup(self):
        voice = self.voice()
        voice.start()
        voice.close()
        self.assertEqual([p for p, _ in self.io.opened],
                         ['/dev/acd-audio_output_tuning', '/dev/acd-audio_bulk_tx'])
        self.assertEqual(self.io.closed, [11, 10])
        for index, operation in enumerate((19, 20, 19)):
            fd, bulk = self.io.written[2 * index]
            self.assertEqual((fd, len(bulk)), (11, 16384))
            self.assertEqual(struct.unpack_from('<HHII', bulk), (2, 14, operation, 2))
            self.assertFalse(any(bulk[14:]))
            fd, command = self.io.written[2 * index + 1]
            self.assertEqual(fd, 10)
            self.assertEqual(command, struct.pack('<BBHHhBBIII', 0, index + 1, 22, 210, 0,
                                                   19, 24, 0, 0, 14))
        self.assertFalse(self.marker.exists())
        before = list(self.io.written)
        voice.close()
        self.assertEqual(self.io.written, before)

    def test_earpiece_uses_handset_files(self):
        (self.root / 'uplink_handset_aec_on_config.pb').write_bytes(b'handset-test')
        voice = self.voice('earpiece')
        voice.start()
        self.assertEqual(self.io.written[0][1][12:24], b'handset-test')
        voice.close()

    def test_missing_or_oversized_files_fail_before_open(self):
        path = self.root / 'downlink_speaker_config.pb'
        path.unlink()
        with self.assertRaises(OSError):
            self.voice()
        path.write_bytes(b'x' * 16384)
        with self.assertRaises(tuning.TuningError):
            self.voice()
        self.assertEqual(self.io.opened, [])

    def test_unknown_ack_keeps_marker_and_prevents_another_call_replaying(self):
        for timeout, bad in ((True, False), (False, True)):
            self.io.timeout, self.io.bad_reply = timeout, bad
            with self.assertRaises(tuning.TuningError):
                self.voice().start()
            self.assertTrue(self.marker.exists())
            before = (list(self.io.opened), list(self.io.written))
            with self.assertRaisesRegex(tuning.TuningError, 'attended recovery'):
                self.voice().start()
            self.assertEqual((self.io.opened, self.io.written), before)
            # Only the test removes its synthetic marker between cases.
            self.marker.unlink()

    def test_short_records_are_not_retried_or_followed_by_cleanup_writes(self):
        for fd in (10, 11):
            self.io.written.clear()
            self.io.short_fd = fd
            with self.assertRaises(tuning.TuningError):
                self.voice().start()
            self.assertEqual(len(self.io.written), 2 if fd == 10 else 1)
            self.assertTrue(self.marker.exists())
            self.marker.unlink()

    def test_explicit_refusal_is_known_and_can_be_cleared_with_aec_off(self):
        self.io.refuse = True
        with self.assertRaisesRegex(tuning.TuningError, 'refused'):
            self.voice().start()
        self.assertFalse(self.marker.exists())
        self.assertEqual(len(self.io.written), 4)  # refused on, confirmed off
        self.assertEqual(self.io.closed, [11, 10])

    def test_cleanup_timeout_closes_services_and_keeps_uncertainty(self):
        voice = self.voice()
        voice.start()
        self.io.timeout = True
        with self.assertRaises(tuning.TuningError):
            voice.close()
        self.assertEqual(self.io.closed, [11, 10])
        self.assertTrue(self.marker.exists())

    def test_pending_reply_is_not_mistaken_for_this_calls_ack(self):
        self.io.pending = True
        with self.assertRaisesRegex(tuning.TuningError, 'pending response'):
            self.voice().start()
        self.assertFalse(self.io.written)
        self.assertEqual(self.io.closed, [11, 10])

    def test_open_failure_closes_the_first_service(self):
        original = self.io.open
        def opening(path, flags):
            if path.endswith('bulk_tx'):
                raise OSError('synthetic open failure')
            return original(path, flags)
        with patch.object(tuning.os, 'open', opening), self.assertRaises(OSError):
            self.voice().start()
        self.assertEqual(self.io.closed, [10])
        self.assertFalse(self.io.written)
