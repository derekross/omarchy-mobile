#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Merge a split Qualcomm firmware (.mdt + .bNN) into the single .mbn image
mainline remoteproc loads.

The .mdt holds the ELF header and program headers; each loadable segment sits in
.bNN at the offset its program header names. Writing the segments back at those
offsets, under the .mdt's own header, reconstructs the image.

    pil-squash.py <raw dir> <out dir> [name ...]
"""
# pil-squasher: an .mdt is the ELF header plus program headers; each loadable
# segment lives in .bNN at the offset its program header names. Writing them
# back at those offsets reconstructs the single .mbn image.
import struct, sys
from pathlib import Path

raw, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
only = set(sys.argv[3:])
for mdt in sorted(raw.glob('*.mdt')):
    if only and mdt.stem not in only:
        continue
    d = mdt.read_bytes()
    if d[:4] != b'\x7fELF':
        print(f"{mdt.name}: not an ELF, skipped"); continue
    is64 = d[4] == 2
    if is64:
        e_phoff, = struct.unpack_from('<Q', d, 32)
        e_phentsize, e_phnum = struct.unpack_from('<HH', d, 54)
    else:
        e_phoff, = struct.unpack_from('<I', d, 28)
        e_phentsize, e_phnum = struct.unpack_from('<HH', d, 42)
    blob = bytearray()
    written = 0
    for i in range(e_phnum):
        ph = e_phoff + i * e_phentsize
        if is64:
            p_type, p_flags = struct.unpack_from('<II', d, ph)
            p_offset, = struct.unpack_from('<Q', d, ph + 8)
            p_filesz, = struct.unpack_from('<Q', d, ph + 32)
        else:
            p_type, p_offset, _, _, p_filesz = struct.unpack_from('<IIIII', d, ph)
        seg = raw / f"{mdt.stem}.b{i:02d}"
        if not seg.is_file() or p_filesz == 0:
            continue
        s = seg.read_bytes()
        if len(s) != p_filesz:
            print(f"  {seg.name}: {len(s)} bytes but the header says {p_filesz} -- refusing")
            blob = None; break
        if len(blob) < p_offset:
            blob.extend(b'\0' * (p_offset - len(blob)))
        blob[p_offset:p_offset + len(s)] = s
        written += 1
    if blob is None:
        continue
    # keep the ELF header/phdrs from the .mdt itself
    head = min(e_phoff + e_phnum * e_phentsize, len(d))
    if len(blob) < head:
        blob.extend(b'\0' * (head - len(blob)))
    blob[0:head] = d[0:head]
    target = out / f"{mdt.stem}.mbn"
    target.write_bytes(bytes(blob))
    print(f"  {target.name}: {len(blob)} bytes from {written} segment(s)")
