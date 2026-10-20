#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Validate the local raw ext4 root before the explicit userdata stage."""
from pathlib import Path
import struct
import sys


def validate(path):
    size = path.stat().st_size
    with path.open('rb') as stream:
        stream.seek(1024)
        sb = stream.read(1024)
    if len(sb) != 1024 or sb[56:58] != b'\x53\xef':
        raise ValueError('Expected a raw ext4 image; convert Android sparse input locally first')
    if sb[120:136].rstrip(b'\0') != b'omamobile-root':
        raise ValueError('Expected the omamobile-root filesystem label')
    log_block = struct.unpack_from('<I', sb, 24)[0]
    if log_block != 2:
        raise ValueError('Expected the tested 4096-byte ext4 block size')
    blocks = struct.unpack_from('<I', sb, 4)[0]
    incompat = struct.unpack_from('<I', sb, 96)[0]
    if incompat & 0x80:
        blocks |= struct.unpack_from('<I', sb, 336)[0] << 32
    if incompat & 0x2000:  # metadata_csum_seed
        raise ValueError('Disable metadata_csum_seed for the storage loader')
    if struct.unpack_from('<I', sb, 92)[0] & 0x1000:  # orphan_file
        raise ValueError('Disable orphan_file for the storage loader')
    if not blocks or blocks * 4096 != size:
        raise ValueError('Filesystem size does not match the complete image')
    return size


if __name__ == '__main__':
    try:
        print(validate(Path(sys.argv[1])))
    except (IndexError, OSError, ValueError) as error:
        sys.exit(str(error))
