# SPDX-License-Identifier: MIT
"""Small USB/SSH-tunnel RFB client for screenshots, pointer and keyboard input."""
import socket
import struct
import zlib


def read_exact(stream, size):
    chunks = bytearray()
    while len(chunks) < size:
        data = stream.recv(size - len(chunks))
        if not data:
            raise ConnectionError("VNC server closed the connection")
        chunks.extend(data)
    return bytes(chunks)


class RFB:
    def __init__(self, stream):
        self.s = stream
        version = read_exact(stream, 12)
        if not version.startswith(b"RFB 003."):
            raise ValueError("Not an RFB server")
        stream.sendall(b"RFB 003.008\n")
        count = read_exact(stream, 1)[0]
        if not count:
            raise ConnectionError("VNC server refused the connection")
        methods = read_exact(stream, count)
        if 1 not in methods:
            raise ValueError("This local client requires the USB mirror's default no-password mode")
        stream.sendall(b"\x01")
        if struct.unpack(">I", read_exact(stream, 4))[0]:
            raise ConnectionError("VNC authentication failed")
        stream.sendall(b"\x01")  # shared session
        header = read_exact(stream, 24)
        self.width, self.height = struct.unpack_from(">HH", header)
        length = struct.unpack_from(">I", header, 20)[0]
        if length > 65536 or not (0 < self.width <= 8192 and 0 < self.height <= 8192):
            raise ValueError("Unexpected framebuffer dimensions or name")
        read_exact(stream, length)
        # Request native little-endian 32-bit BGRX and only raw pixels.
        fmt = struct.pack(">BBBBHHHBBB3x", 32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
        stream.sendall(b"\x00\x00\x00\x00" + fmt)
        stream.sendall(struct.pack(">BBHii", 2, 0, 2, 0, -223))

    def pointer(self, x, y, mask=0):
        if not (0 <= x < self.width and 0 <= y < self.height and 0 <= mask <= 255):
            raise ValueError("Pointer coordinate outside the phone screen")
        self.s.sendall(struct.pack(">BBHH", 5, mask, x, y))

    def tap(self, x, y):
        self.pointer(x, y, 1)
        self.pointer(x, y, 0)

    def key(self, keysym, down):
        self.s.sendall(struct.pack(">BBHI", 4, bool(down), 0, keysym))

    def type(self, text):
        for character in text:
            code = ord(character)
            symbol = code if code <= 255 else 0x01000000 | code
            self.key(symbol, True)
            self.key(symbol, False)

    def screenshot(self):
        self.s.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, self.width, self.height))
        pixels = bytearray(self.width * self.height * 3)
        while True:
            message = read_exact(self.s, 1)[0]
            if message == 2:  # bell
                continue
            if message == 3:  # clipboard
                length = struct.unpack(">3xI", read_exact(self.s, 7))[0]
                if length > 16 * 1024 * 1024:
                    raise ValueError("Unexpected clipboard length")
                read_exact(self.s, length)
                continue
            if message != 0:
                raise ValueError(f"Unsupported VNC server message {message}")
            count = struct.unpack(">xH", read_exact(self.s, 3))[0]
            painted = False
            for _ in range(count):
                x, y, width, height, encoding = struct.unpack(">HHHHi", read_exact(self.s, 12))
                if encoding == -223:
                    if not (0 < width <= 8192 and 0 < height <= 8192):
                        raise ValueError("Unexpected resized framebuffer")
                    self.width, self.height = width, height
                    pixels = bytearray(width * height * 3)
                    continue
                if encoding != 0 or x + width > self.width or y + height > self.height:
                    raise ValueError("Unexpected framebuffer rectangle")
                raw = read_exact(self.s, width * height * 4)
                painted = True
                rgb = bytearray(width * height * 3)
                rgb[0::3], rgb[1::3], rgb[2::3] = raw[2::4], raw[1::4], raw[0::4]
                for row in range(height):
                    target = ((y + row) * self.width + x) * 3
                    source = row * width * 3
                    pixels[target:target + width * 3] = rgb[source:source + width * 3]
            if painted:
                return png(self.width, self.height, pixels)
            self.s.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, self.width, self.height))


def png(width, height, pixels):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\0" + pixels[y * width * 3:(y + 1) * width * 3] for y in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 3)) + chunk(b"IEND", b""))
