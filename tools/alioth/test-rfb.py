#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the real RFB wire protocol against a local socket server."""
import socket
import struct
import threading
import unittest
import zlib
from rfb import RFB, read_exact


class ProtocolTest(unittest.TestCase):
    def session(self, server):
        left, right = socket.socketpair()
        left.settimeout(3)
        right.settimeout(3)
        errors = []

        def serve():
            try:
                with right:
                    right.sendall(b"RFB 003.008\n")
                    self.assertEqual(read_exact(right, 12), b"RFB 003.008\n")
                    right.sendall(b"\x01\x01")
                    self.assertEqual(read_exact(right, 1), b"\x01")
                    right.sendall(b"\0\0\0\0")
                    self.assertEqual(read_exact(right, 1), b"\x01")
                    right.sendall(struct.pack(">HH", 2, 2) + b"\0" * 16 + struct.pack(">I", 4) + b"test")
                    self.assertEqual(read_exact(right, 20)[:4], b"\0\0\0\0")
                    self.assertEqual(read_exact(right, 12), struct.pack(">BBHii", 2, 0, 2, 0, -223))
                    server(right)
            except BaseException as error:
                errors.append(error)
        thread = threading.Thread(target=serve)
        thread.start()
        return left, thread, errors

    def test_capture_real_pixels_and_png(self):
        def server(stream):
            self.assertEqual(read_exact(stream, 10), struct.pack(">BBHHHH", 3, 0, 0, 0, 2, 2))
            # Red, green, blue, white, encoded as requested little-endian BGRX.
            stream.sendall(b"\0\0\0\1" + struct.pack(">HHHHi", 0, 0, 2, 2, 0)
                           + bytes.fromhex("0000ff0000ff0000ff000000ffffff00"))
        stream, thread, errors = self.session(server)
        with stream:
            image = RFB(stream).screenshot()
        thread.join(3)
        self.assertFalse(errors, errors)
        self.assertTrue(image.startswith(b"\x89PNG\r\n\x1a\n"))
        self.assertEqual(struct.unpack_from(">II", image, 16), (2, 2))
        pos, pixels = 8, b""
        while pos < len(image):
            size = struct.unpack_from(">I", image, pos)[0]
            if image[pos + 4:pos + 8] == b"IDAT":
                pixels += image[pos + 8:pos + 8 + size]
            pos += size + 12
        self.assertEqual(zlib.decompress(pixels), bytes.fromhex("00ff000000ff00000000ffffffff"))

    def test_pointer_and_unicode_keyboard(self):
        def server(stream):
            self.assertEqual(read_exact(stream, 6), struct.pack(">BBHH", 5, 1, 1, 0))
            self.assertEqual(read_exact(stream, 6), struct.pack(">BBHH", 5, 0, 1, 0))
            self.assertEqual(read_exact(stream, 8), struct.pack(">BBHI", 4, 1, 0, 0x010003bb))
            self.assertEqual(read_exact(stream, 8), struct.pack(">BBHI", 4, 0, 0, 0x010003bb))
        stream, thread, errors = self.session(server)
        with stream:
            client = RFB(stream)
            with self.assertRaises(ValueError):
                client.tap(2, 0)
            client.tap(1, 0)
            client.type("λ")
        thread.join(3)
        self.assertFalse(errors, errors)


if __name__ == "__main__":
    unittest.main()
