#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Stage Bluejay development init and optional DT overlays from existing images."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile


def align(n, page):
    return (n + page - 1) // page * page


def records(data):
    pos = 0
    while True:
        start = pos
        header = data[pos:pos + 110]
        assert header[:6] == b'070701'
        fields = [int(header[6 + i * 8:14 + i * 8], 16) for i in range(13)]
        name = data[pos + 110:pos + 110 + fields[11] - 1].decode()
        body = align(pos + 110 + fields[11], 4)
        end = align(body + fields[6], 4)
        yield name, header, data[pos + 110:body], data[body:body + fields[6]], data[start:end]
        pos = end
        if name == 'TRAILER!!!':
            break


def new_record(name, body, inode):
    encoded = name.encode() + b'\0'
    fields = [inode, 0o100644, 0, 0, 1, 0, len(body), 0, 0, 0, 0,
              len(encoded), 0]
    record = b'070701' + b''.join(f'{value:08x}'.encode() for value in fields) + encoded
    record += b'\0' * (align(len(record), 4) - len(record))
    record += body
    return record + b'\0' * (align(len(record), 4) - len(record))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base', type=Path, help='existing candidate directory with images/')
    parser.add_argument('output', type=Path)
    parser.add_argument('--dt-overlay', type=Path, action='append', default=[],
                        help='compiled overlay to apply to each silicon DT variant')
    parser.add_argument('--mode', choices=['persistent-development', 'ram-rescue'],
                        default='persistent-development', help='explicit root handover policy')
    args = parser.parse_args()
    assert (args.base / 'images/DEVICE').read_text().strip() == 'bluejay'
    args.output.mkdir(parents=True, exist_ok=False)
    images = args.output / 'images'
    images.mkdir()
    source = Path(__file__).resolve().parent.parent
    vendor = (args.base / 'images/vendor_boot.img').read_bytes()
    u32 = lambda offset: struct.unpack_from('<I', vendor, offset)[0]
    assert vendor[:8] == b'VNDRBOOT' and u32(8) == 4
    page = u32(12)
    rs = align(u32(2096), page)
    rn = u32(24)
    ds = rs + align(rn, page)
    dn = u32(2100)
    table = ds + align(dn, page)
    assert u32(2116) == 1 and u32(2120) == 108
    packed = subprocess.check_output(['lz4', '-d', '-c'], input=vendor[rs:rs + rn], stderr=subprocess.DEVNULL)
    replacements = {'init': (source / 'initramfs/init').read_bytes(),
                    'etc/omamobile-bluejay-firstroot': (args.mode + '\n').encode()}
    changed = set()
    output = bytearray()
    old = list(records(packed))
    selector = 'etc/omamobile-bluejay-firstroot'
    selector_missing = not any(r[0].removeprefix('./') == selector for r in old)
    inode = max(int(r[1][6:14], 16) for r in old) + 1
    for name, header, name_bytes, body, raw in old:
        key = name.removeprefix('./')
        if key == 'TRAILER!!!' and selector_missing:
            output.extend(new_record(selector, replacements[selector], inode))
            changed.add(selector)
        if key not in replacements:
            output.extend(raw)
            continue
        changed.add(key)
        body = replacements[key]
        header = bytearray(header)
        header[54:62] = f'{len(body):08x}'.encode()
        output.extend(header + name_bytes + body)
        output.extend(b'\0' * (align(len(output), 4) - len(output)))
    assert changed == replacements.keys()
    output.extend(b'\0' * (align(len(output), 512) - len(output)))
    new = list(records(output))
    expected_names = [r[0] for r in old]
    if selector_missing:
        expected_names.insert(-1, selector)
    assert expected_names == [r[0] for r in new]
    original_new = [r for r in new if not (selector_missing and r[0] == selector)]
    for before, after in zip(old, original_new):
        if before[0].removeprefix('./') not in changed:
            assert before[4] == after[4], before[0]
    ram = subprocess.check_output(['lz4', '-l', '-c'], input=output, stderr=subprocess.DEVNULL)
    bundle = vendor[ds:ds + dn]
    if args.dt_overlay:
        variants = []
        pos = 0
        with tempfile.TemporaryDirectory() as tmp:
            base_dtb, result_dtb = Path(tmp) / 'base.dtb', Path(tmp) / 'result.dtb'
            while pos < len(bundle):
                assert bundle[pos:pos + 4] == b'\xd0\x0d\xfe\xed'
                size = struct.unpack_from('>I', bundle, pos + 4)[0]
                assert 40 <= size <= len(bundle) - pos
                base_dtb.write_bytes(bundle[pos:pos + size])
                subprocess.run(['fdtoverlay', '-i', str(base_dtb), '-o', str(result_dtb),
                                *map(str, args.dt_overlay)], check=True)
                variants.append(result_dtb.read_bytes())
                pos += size
        assert pos == len(bundle) and len(variants) == 2
        bundle = b''.join(variants)
    header = bytearray(vendor[:rs])
    struct.pack_into('<I', header, 24, len(ram))
    struct.pack_into('<I', header, 2100, len(bundle))
    tail = bytearray(vendor[table:])
    struct.pack_into('<I', tail, 0, len(ram))
    result = (header + ram + b'\0' * (align(len(ram), page) - len(ram))
              + bundle + b'\0' * (align(len(bundle), page) - len(bundle)) + tail)
    (images / 'vendor_boot.img').write_bytes(result)
    for name in ('boot.img', 'dtbo.img', 'DEVICE'):
        shutil.copy2(args.base / 'images' / name, images / name)
    (args.output / 'include/config').mkdir(parents=True)
    shutil.copy2(args.base / 'include/config/kernel.release', args.output / 'include/config/kernel.release')
    if not args.dt_overlay:
        assert result[rs + align(len(ram), page):rs + align(len(ram), page) + dn] == vendor[ds:ds + dn]
    report = {'changed_ram_records': sorted(changed),
              'mode': args.mode,
              'kernel_and_both_DT_variants_unchanged': not args.dt_overlay,
              'dt_overlays': {str(f): hashlib.sha256(f.read_bytes()).hexdigest()
                              for f in args.dt_overlay},
              'all_other_RAM_records_unchanged': True,
              'images': {f.name: hashlib.sha256(f.read_bytes()).hexdigest() for f in images.glob('*.img')}}
    (args.output / 'build.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
