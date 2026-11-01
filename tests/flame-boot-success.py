#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Synthetic GPT and SCSI backend; never opens a host or phone block device."""
import base64
import contextlib
import copy
import ctypes as C
import hashlib
import importlib.util
import io
from pathlib import Path
import struct
import sys
import tempfile
import zlib

source = Path(__file__).resolve().parents[1] / 'device/flame/native'
def module(name, file):
    spec = importlib.util.spec_from_file_location(name, source / file)
    result = importlib.util.module_from_spec(spec)
    sys.modules[name] = result
    spec.loader.exec_module(result)
    return result

read = module('read_gpt', 'read_gpt.py')
planner = module('boot_success_plan', 'boot_success_plan.py')
writer = module('boot_success_apply', 'boot_success_apply.py')
BS, LAST = 4096, 4095
table = bytearray(15 * 128)
entry = bytearray(128)
entry[:16] = bytes([1]) * 16
entry[16:32] = bytes([2]) * 16
struct.pack_into('<3Q', entry, 32, 100, 199, 0x16 << 48)
entry[56:68] = 'boot_b'.encode('utf-16le')
table[6*128:7*128] = entry
crc = zlib.crc32(table)
def header(lba, padding):
    h = bytearray([padding] * BS)
    h[:92] = bytes(92)
    h[:8] = b'EFI PART'
    struct.pack_into('<4I', h, 8, 0x10000, 92, 0, 0)
    struct.pack_into('<4Q', h, 24, lba, LAST if lba == 1 else 1, 6, LAST-5)
    h[56:72] = bytes([3]) * 16
    # Match coral's legacy backup pointer; physical backup array is LAST-1.
    struct.pack_into('<Q3I', h, 72, 2, 15, 128, crc)
    struct.pack_into('<I', h, 16, zlib.crc32(h[:92]))
    return bytes(h)

original = {i: bytes([i % 251]) * BS for i in list(range(6)) + list(range(LAST-4, LAST+1))}
original[1] = header(1, 0xa5)
original[LAST] = header(LAST, 0x5a)
original[2] = bytes(table) + bytes([0x31]) * (BS-len(table))
original[LAST-1] = bytes(table) + bytes([0x62]) * (BS-len(table))

fixture = tempfile.TemporaryDirectory()
root = Path(fixture.name); sysfs = root / 'sys'; devdir = root / 'dev'
sysfs.mkdir(); devdir.mkdir()

def node(name, part=None, parent=None, ro='1'):
    location = root / 'devices' / (parent or name)
    if parent: location /= name
    location.mkdir(parents=True)
    (sysfs / name).symlink_to(location, target_is_directory=True)
    (location / 'ro').write_text(ro)
    (location / 'uevent').write_text('PARTNAME=' + part if part else 'DEVTYPE=disk')
    if part: (location / 'partition').write_text('1')
    (location / 'start').write_text(str(100 * 8))
    (location / 'size').write_text(str(100 * 8))
    return sysfs / name

# Different LUN letters, and an unrelated writable userdata must not be
# mistaken for the single intended root partition.
disk_node = node('sde'); boot_node = node('sde7', 'boot_b', 'sde')
userdata_node = node('sde15', 'userdata', 'sde', ro='0')
node('sdb'); node('sdb2', 'persist', 'sdb')
writer.verify_storage = lambda: read.verify_storage(sysfs, devdir)
assert read.resolve_layout(sysfs) == (boot_node, userdata_node, disk_node)

class Memory:
    def __init__(self, failure=None):
        self.boot_node, self.userdata_node, self.disk_node = boot_node, userdata_node, disk_node
        self.bs = BS; self.last = LAST; self.fd = -1
        self.mem = dict(original); self.calls = []; self.failure = failure; self.libc = self
    def read(self, lba, count=1): return b''.join(self.mem[lba+i] for i in range(count))
    def ioctl(self, fd, operation, ptr):
        h = C.cast(ptr, C.POINTER(read.Header)).contents
        cmd = C.string_at(h.cmdp, h.cmd_len)
        lba, count = struct.unpack_from('>QI', cmd, 2)
        assert fd == -1 and operation == 0x2285
        assert cmd[:2] == bytes([0x8a, 8]) and count == 1
        assert h.dxfer_direction == -2 and h.dxfer_len == BS
        assert lba == [LAST-1, LAST, 2, 1][len(self.calls)]
        self.calls.append(lba)
        if len(self.calls) == self.failure: h.status = 2
        else: self.mem[lba] = C.string_at(h.dxferp, BS)
        return 0

before = read.snapshot(Memory())
approved = planner.plan(before)
def refuses(action):
    try: action()
    except RuntimeError: return
    raise AssertionError('unsafe action accepted')

assert read.verify_storage(sysfs, devdir) == (boot_node, userdata_node, disk_node)
(devdir / disk_node.name).touch()
refuses(lambda: read.verify_storage(sysfs, devdir))
(devdir / disk_node.name).unlink()
(sysfs / 'sdb2' / 'ro').write_text('0')
refuses(lambda: read.verify_storage(sysfs, devdir))
(sysfs / 'sdb2' / 'ro').write_text('1')
extra = node('sdb3', 'userdata', 'sdb', ro='0')
refuses(lambda: read.resolve_layout(sysfs))
extra.unlink()
(userdata_node / 'uevent').write_text('PARTNAME=not-userdata')
refuses(lambda: read.resolve_layout(sysfs))
extra.symlink_to(root / 'devices/sdb/sdb3')
refuses(lambda: read.resolve_layout(sysfs))
extra.unlink()
(userdata_node / 'uevent').write_text('PARTNAME=userdata')

with contextlib.redirect_stdout(io.StringIO()):
    m = Memory()
    writer.apply(m, before, approved)
    after = read.snapshot(m)
    assert len(m.calls) == 4
    assert next(p for p in after['partitions'] if p['name'] == 'boot_b')['attributes'] == (0x56 << 48)
    # Distinct primary/backup padding, PMBR, unrelated entries and gaps survive.
    for lba in original:
        if lba not in (1, 2, LAST-1, LAST): assert m.mem[lba] == original[lba]
    assert m.mem[2][15*128:] == original[2][15*128:]
    assert m.mem[LAST-1][15*128:] == original[LAST-1][15*128:]
    refuses(lambda: planner.plan(after))  # No repeat write to an already successful B.
    for step in range(1, 5):
        m = Memory(step)
        refuses(lambda: writer.apply(m, before, approved))
        assert len(m.calls) == step
    m = Memory(); m.mem[0] = bytes([1]) + m.mem[0][1:]
    refuses(lambda: writer.apply(m, before, approved)); assert not m.calls
    m = Memory(); changed = copy.deepcopy(approved); changed['writes_backup_first'][0]['lba'] = 0
    refuses(lambda: writer.apply(m, before, changed)); assert not m.calls
    corrupt = copy.deepcopy(before); corrupt['blocks']['2'] = base64.b64encode(bytes(BS)).decode()
    refuses(lambda: planner.plan(corrupt))
    missing = copy.deepcopy(before); del missing['blocks']['0']
    refuses(lambda: planner.plan(missing))
    image = bytearray(8192); image[:8] = b'ANDROID!'; struct.pack_into('<I', image, 36, 4096)
    struct.pack_into('<I', image, 8, 64); image[4096:4099] = b'\x1f\x8b\x08'
    sha = hashlib.sha256(image).hexdigest()
    writer.verify_loader(image, sha, image)
    stale = bytearray(image); struct.pack_into('<I', stale, 16, 1024)
    refuses(lambda: writer.verify_loader(image, sha, stale))
    refuses(lambda: writer.verify_loader(image, '0' * 64, image))
fixture.cleanup()
print('ok - PARTNAME resolution/RO checks; boot-success scope, GPT checksums/padding, backup-first failures, stale plans and exact loader verification')
