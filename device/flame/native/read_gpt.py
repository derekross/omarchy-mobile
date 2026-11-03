#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Read-only SCSI/GPT snapshot through the existing boot_b partition node."""
import base64
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import stat
import struct
import sys
import zlib


class Header(C.Structure):
    _fields_ = [
        ('interface_id', C.c_int), ('dxfer_direction', C.c_int),
        ('cmd_len', C.c_ubyte), ('mx_sb_len', C.c_ubyte),
        ('iovec_count', C.c_ushort), ('dxfer_len', C.c_uint),
        ('dxferp', C.c_void_p), ('cmdp', C.c_void_p), ('sbp', C.c_void_p),
        ('timeout', C.c_uint), ('flags', C.c_uint), ('pack_id', C.c_int),
        ('usr_ptr', C.c_void_p), ('status', C.c_ubyte),
        ('masked_status', C.c_ubyte), ('msg_status', C.c_ubyte),
        ('sb_len_wr', C.c_ubyte), ('host_status', C.c_ushort),
        ('driver_status', C.c_ushort), ('resid', C.c_int),
        ('duration', C.c_uint), ('info', C.c_uint),
    ]


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def resolve_layout(sysfs=None):
    """Resolve unique boot_b/userdata partitions and their shared UFS LUN."""
    sysfs = Path('/sys/class/block') if sysfs is None else sysfs
    found = {'boot_b': [], 'userdata': []}
    for node in sysfs.glob('sd*'):
        try:
            lines = (node / 'uevent').read_text().splitlines()
        except FileNotFoundError:
            continue
        for name in found:
            if 'PARTNAME=' + name in lines:
                found[name].append(node)
    require(all(len(nodes) == 1 for nodes in found.values()), 'missing or ambiguous boot_b/userdata PARTNAME')
    boot, userdata = found['boot_b'][0], found['userdata'][0]
    require(all((node / 'partition').is_file() for node in (boot, userdata)), 'expected partition nodes')
    parent = boot.resolve().parent
    require(userdata.resolve().parent == parent, 'boot_b and userdata are on different LUNs')
    disk = sysfs / parent.name
    require(disk.resolve() == parent and 'DEVTYPE=disk' in (disk / 'uevent').read_text().splitlines(), 'unverified parent LUN')
    return boot, userdata, disk


def verify_storage(sysfs=None, devdir=None):
    sysfs = Path('/sys/class/block') if sysfs is None else sysfs
    devdir = Path('/dev') if devdir is None else devdir
    boot, userdata, disk = resolve_layout(sysfs)
    require(not (devdir / disk.name).exists(), 'whole-disk node must stay absent')
    for node in sysfs.glob('sd*'):
        if node.name in (disk.name, userdata.name):
            continue
        require((node / 'ro').read_text().strip() == '1', 'protected storage is writable')
    return boot, userdata, disk


class Reader:
    def __init__(self):
        require(Path('/usr/share/omamobile/flame-root').is_file(), 'wrong root')
        require(Path('/proc/device-tree/model').read_bytes().rstrip(b'\0') == b'Google Pixel 4', 'wrong model')
        self.boot_node, self.userdata_node, self.disk_node = verify_storage()
        device = Path('/dev') / self.boot_node.name
        require(stat.S_ISBLK(device.stat().st_mode), 'expected block node')
        self.fd = os.open(device, os.O_RDONLY | os.O_CLOEXEC)
        self.libc = C.CDLL(None, use_errno=True)
        self.libc.ioctl.argtypes = [C.c_int, C.c_ulong, C.c_void_p]
        cdb = bytes([0x9e, 0x10]) + bytes(8) + struct.pack('>I', 32) + bytes(2)
        cap = self.request(cdb, 32)
        self.last, self.bs = struct.unpack_from('>QI', cap)
        require(self.bs == 4096, 'unexpected sector size')
        require((self.last + 1) * self.bs == int((self.disk_node / 'size').read_text()) * 512, 'capacity mismatch')

    def request(self, cdb, count):
        require(cdb[0] in (0x88, 0x9e), 'read-only commands only')
        data = C.create_string_buffer(count)
        cmd = C.create_string_buffer(cdb)
        sense = C.create_string_buffer(96)
        h = Header(interface_id=ord('S'), dxfer_direction=-3, cmd_len=len(cdb),
                   mx_sb_len=96, dxfer_len=count, dxferp=C.addressof(data),
                   cmdp=C.addressof(cmd), sbp=C.addressof(sense), timeout=15000)
        result = self.libc.ioctl(self.fd, 0x2285, C.byref(h))
        require(result == 0, 'SG_IO failed, errno=' + str(C.get_errno()))
        require(not (h.status or h.host_status or h.driver_status or h.resid),
                'SCSI read failed: status=' + str((h.status, h.host_status, h.driver_status, h.resid)))
        return data.raw

    def read(self, lba, count=1):
        require(0 <= lba <= self.last and 1 <= count <= 256 and lba + count <= self.last + 1, 'read outside capacity')
        cdb = bytes([0x88, 0]) + struct.pack('>QI', lba, count) + bytes(2)
        return self.request(cdb, self.bs * count)


def parse_header(raw, expected, last, bs):
    require(raw[:8] == b'EFI PART', 'GPT signature missing')
    rev, size, crc, reserved = struct.unpack_from('<4I', raw, 8)
    require(rev == 0x10000 and size == 92 and reserved == 0, 'unknown GPT header')
    chk = bytearray(raw[:size]); chk[16:20] = bytes(4)
    require(zlib.crc32(chk) == crc, 'GPT header checksum mismatch')
    current, alternate, first, end = struct.unpack_from('<4Q', raw, 24)
    entries, n, es, table_crc = struct.unpack_from('<Q3I', raw, 72)
    require(current == expected and alternate == (last if expected == 1 else 1), 'GPT header location mismatch')
    require(2 < first <= end < last, 'GPT usable range invalid')
    require(es == 128 and 1 <= n <= 1024, 'unknown GPT entry layout')
    blocks = (n * es + bs - 1) // bs
    # Coral's backup header retains the primary array LBA; its physical copy
    # is immediately before the backup header. Preserve this observed layout.
    require((expected == 1 and entries >= 2 and entries + blocks <= first) or
            (expected == last and ((entries > end and entries + blocks <= last) or entries == 2)),
            'GPT entries overlap data')
    return {'entries': entries, 'count': n, 'entry_size': es, 'crc': table_crc,
            'first': first, 'end': end, 'blocks': blocks, 'guid': raw[56:72].hex()}


def snapshot(reader):
    p = reader.read(1); b = reader.read(reader.last)
    ph = parse_header(p, 1, reader.last, reader.bs)
    bh = parse_header(b, reader.last, reader.last, reader.bs)
    require(all(ph[k] == bh[k] for k in ('count', 'entry_size', 'first', 'end', 'guid')), 'GPT copies disagree')
    bh['physical_entries'] = reader.last - bh['blocks'] if bh['entries'] == ph['entries'] else bh['entries']
    require(bh['physical_entries'] > bh['end'], 'physical backup array overlaps data')
    ph['physical_entries'] = ph['entries']
    pt = reader.read(ph['physical_entries'], ph['blocks']); bt = reader.read(bh['physical_entries'], bh['blocks'])
    used = ph['count'] * ph['entry_size']
    require(zlib.crc32(pt[:used]) == ph['crc'] and zlib.crc32(bt[:used]) == bh['crc'], 'GPT array checksum mismatch')
    require(pt[:used] == bt[:used], 'GPT arrays disagree')
    parts = []
    for i in range(ph['count']):
        entry = pt[i * 128:(i + 1) * 128]
        if entry[:16] == bytes(16):
            continue
        name = entry[56:128].decode('utf-16le').split('\0', 1)[0]
        start, end, attributes = struct.unpack_from('<3Q', entry, 32)
        parts.append({'index': i, 'name': name, 'start': start, 'end': end, 'attributes': attributes})
    boot = [p for p in parts if p['name'] == 'boot_b']
    require(len(boot) == 1 and boot[0]['index'] == 6, 'boot_b index mismatch')
    require(boot[0]['start'] * reader.bs == int((reader.boot_node / 'start').read_text()) * 512, 'boot_b start mismatch')
    require((boot[0]['end'] - boot[0]['start'] + 1) * reader.bs == int((reader.boot_node / 'size').read_text()) * 512, 'boot_b size mismatch')
    blocks = {0: reader.read(0), 1: p, reader.last: b}
    require(ph['first'] <= 256 and reader.last - bh['end'] <= 256, 'excessive GPT reservation')
    for lba in list(range(ph['first'])) + list(range(bh['end'] + 1, reader.last + 1)):
        blocks[lba] = reader.read(lba)
    for header, table in ((ph, pt), (bh, bt)):
        for i in range(header['blocks']):
            blocks[header['physical_entries'] + i] = table[i * reader.bs:(i + 1) * reader.bs]
    return {'sector_size': reader.bs, 'last_lba': reader.last, 'primary': ph,
            'backup': bh, 'partitions': parts, 'blocks': {str(k): base64.b64encode(v).decode() for k, v in blocks.items()}}


if __name__ == '__main__':
    result = snapshot(Reader())
    json.dump(result, sys.stdout, indent=2)
    print()
