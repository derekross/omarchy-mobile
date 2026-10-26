#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Plan exactly one Qualcomm boot_b successful bit, preserving both GPT copies."""
import base64
import copy
import hashlib
import json
import struct
import sys
import zlib
from pathlib import Path


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def digest(value):
    return hashlib.sha256(value).hexdigest()


def plan(snapshot):
    bs = snapshot['sector_size']; last = snapshot['last_lba']
    require(bs == 4096 and last > 1024, 'unsupported disk geometry')
    old = {int(k): base64.b64decode(v, validate=True) for k, v in snapshot['blocks'].items()}
    require(all(len(v) == bs for v in old.values()), 'invalid sector backup')
    headers = [snapshot['primary'], snapshot['backup']]
    require(all(h['count'] == 15 and h['entry_size'] == 128 and h['blocks'] == 1 for h in headers), 'unverified partition layout')
    require(headers[0]['physical_entries'] == 2 and headers[1]['physical_entries'] == last-1, 'unverified GPT locations')
    require(set(old) == set(range(6)) | set(range(last-4, last+1)), 'incomplete GPT backup')
    new = copy.copy(old)
    tables = []
    for location, h in zip((1, last), headers):
        raw = old[location]; table = old[h['physical_entries']]
        require(raw[:8] == b'EFI PART', 'bad signature')
        require(struct.unpack_from('<I', raw, 12)[0] == 92, 'unsupported header')
        hc = bytearray(raw[:92]); hc[16:20] = bytes(4)
        require(zlib.crc32(hc) == struct.unpack_from('<I', raw, 16)[0], 'bad header checksum')
        require(zlib.crc32(table[:15*128]) == struct.unpack_from('<I', raw, 88)[0], 'bad table checksum')
        require(struct.unpack_from('<Q', raw, 24)[0] == location, 'wrong header LBA')
        require(struct.unpack_from('<Q', raw, 32)[0] == (last if location == 1 else 1), 'wrong alternate LBA')
        matches = [i for i in range(15) if table[i*128+56:i*128+128].decode('utf-16le').split('\0',1)[0] == 'boot_b']
        require(matches == [6], 'wrong boot_b entry')
        offset = 6*128+54
        require(table[offset] & 4 and not table[offset] & 128, 'B must be active and bootable')
        require(not table[offset] & 64, 'B is already successful; no write needed')
        changed = bytearray(table); changed[offset] |= 64
        require([i for i in range(bs) if changed[i] != table[i]] == [offset], 'unexpected table change')
        new[h['physical_entries']] = bytes(changed)
        nh = bytearray(raw)
        struct.pack_into('<I', nh, 88, zlib.crc32(changed[:15*128]))
        struct.pack_into('<I', nh, 16, 0)
        struct.pack_into('<I', nh, 16, zlib.crc32(nh[:92]))
        require(all(nh[i] == raw[i] for i in range(bs) if i not in list(range(16,20))+list(range(88,92))), 'unexpected header change')
        new[location] = bytes(nh)
        tables.append(table[:15*128])
    require(tables[0] == tables[1], 'partition tables disagree')
    changes = []
    for lba in (last-1, last, 2, 1):
        changes.append({'lba':lba,'old_sha256':digest(old[lba]),'new_sha256':digest(new[lba]),
                        'old':base64.b64encode(old[lba]).decode(),'new':base64.b64encode(new[lba]).decode()})
    return {'operation':'mark-only-boot_b-successful','sector_size':bs,'last_lba':last,
            'writes_backup_first':changes,'unchanged_sha256':{str(k):digest(v) for k,v in old.items() if k not in (last-1,last,2,1)}}


if __name__ == '__main__':
    p = plan(json.loads(Path(sys.argv[1]).read_text()))
    Path(sys.argv[2]).write_text(json.dumps(p,indent=2)+'\n')
    print('Plan: boot_b successful bit only; four sectors, backup first; other partition attributes and GPT padding preserved')
