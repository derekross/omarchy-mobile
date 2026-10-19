#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise image metadata validation without allocating or opening a device."""
from pathlib import Path
from types import SimpleNamespace
import importlib.util
import io
import struct

source = Path(__file__).resolve().parents[1] / 'device/flame/native/root_image.py'
spec = importlib.util.spec_from_file_location('flame_image', source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Image:
    def __init__(self):
        self.data = bytearray(16 * 1024)
        self.size = len(self.data)
        self.data[1080:1082] = b'\x53\xef'
        self.data[1144:1158] = b'omamobile-root'
        struct.pack_into('<I', self.data, 1028, 4)
        struct.pack_into('<I', self.data, 1048, 2)

    def stat(self):
        return SimpleNamespace(st_size=self.size)

    def open(self, mode):
        assert mode == 'rb'
        return io.BytesIO(self.data)


assert module.validate(Image()) == 16 * 1024
for offset, value in ((1080, b'bad'), (1144, b'wrong-label'),
                      (1028, bytes(4)), (1048, struct.pack('<I', 1)),
                      (1116, struct.pack('<I', 0x1000)),
                      (1120, struct.pack('<I', 0x2000))):
    image = Image()
    image.data[offset:offset + len(value)] = value
    try:
        module.validate(image)
    except ValueError:
        pass
    else:
        raise AssertionError('invalid metadata accepted at ' + str(offset))
image = Image()
image.size -= 4096
try:
    module.validate(image)
except ValueError:
    pass
else:
    raise AssertionError('incomplete image accepted')
# The high block count must participate in size/capacity checking. No large
# file is created: this fixture only supplies in-memory metadata and a stat.
image = Image()
struct.pack_into('<I', image.data, 1120, 0x80)
struct.pack_into('<I', image.data, 1360, 1)
try:
    module.validate(image)
except ValueError:
    pass
else:
    raise AssertionError('64-bit size truncated')
image.size += (1 << 32) * 4096
assert module.validate(image) == image.size
print('ok - native root label, block size/features, complete image and 64-bit capacity validation')
