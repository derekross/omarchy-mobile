# SPDX-License-Identifier: MIT
"""Exercise the actual SIT framing against the qualified S5400 request bytes."""
import sys
from pathlib import Path
import env  # noqa: F401
from collections import deque
from concurrent.futures import ThreadPoolExecutor
import socket
import struct
import unittest

import radio_power
from sit import Sit


class NativeRadioWire(unittest.TestCase):
    def test_power_frame_matches_the_executed_s5400_protocol(self):
        for enabled, payload in ((True, bytes.fromhex('020000000000')),
                                 (False, bytes.fromhex('010000000000'))):
            with self.subTest(enabled=enabled):
                # Separate socket context closes both real transport endpoints.
                local, peer = socket.socketpair()
                with local, peer, ThreadPoolExecutor(max_workers=1) as workers:
                    local.setblocking(False)
                    peer.settimeout(2)
                    client = Sit.__new__(Sit)
                    client.fd = local.fileno()
                    client.token = 100
                    client.buffer = bytearray()
                    client.indications = deque()

                    def respond():
                        frame = peer.recv(4096)
                        token = struct.unpack_from('<I', frame, 6)[0]
                        peer.sendall(struct.pack('<BBHHIBB', 1, 0, 0x0800,
                                                 12, token, 0, 0))
                        return frame

                    response = workers.submit(respond)
                    radio_power.native_radio(client, enabled)
                    frame = response.result(timeout=2)
                    self.assertEqual(frame, struct.pack('<BBHHIBB', 0, 0,
                                                       0x0800, 18, 101, 0, 0) + payload)

    def test_non_boolean_rejected_before_transport(self):
        class NeverSend:
            def request(self, *args, **kwargs):
                raise AssertionError('invalid input reached the modem transport')
        for value in (0, 1, None, 'on', []):
            with self.subTest(value=value), self.assertRaises(ValueError):
                radio_power.native_radio(NeverSend(), value)
