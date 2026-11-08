#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check actual repacked CPIO and DT variants using independent system readers."""
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

repo = Path(__file__).resolve().parent.parent
if any(shutil.which(tool) is None for tool in ('cpio', 'lz4', 'dtc', 'fdtget', 'fdtoverlay')):
    print('ok - # skip: image packing requires cpio, lz4 and device-tree tools')
    raise SystemExit(0)


def run(args, **kwargs):
    return subprocess.check_output(args, stderr=subprocess.DEVNULL, **kwargs)


def align(n):
    return (n + 2047) // 2048 * 2048


with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp)
    base = p / 'base'
    images = base / 'images'
    images.mkdir(parents=True)
    (base / 'include/config').mkdir(parents=True)
    (base / 'include/config/kernel.release').write_text('7.3.0-test\n')
    (images / 'DEVICE').write_text('bluejay\n')
    (images / 'boot.img').write_bytes(b'synthetic kernel image\n')
    (images / 'dtbo.img').write_bytes(b'synthetic board image\n')
    ram = p / 'ram'
    (ram / 'etc').mkdir(parents=True)
    (ram / 'init').write_text('old init\n')
    (ram / 'etc/sentinel').write_text('unrelated record retained\n')
    dtbs = []
    for variant in (0, 1):
        dtbs.append(run(['dtc', '-q', '-I', 'dts', '-O', 'dtb'],
                        input=('/dts-v1/; / { soc_id = <' + str(variant) + '>; };').encode()))
    overlay = p / 'overlay.dtbo'
    overlay.write_bytes(run(['dtc', '-q', '-@', '-I', 'dts', '-O', 'dtb'],
                            input=b'/dts-v1/; /plugin/; &{/} { test-value = <42>; };'))
    for existing in (False, True):
        if existing:
            (ram / 'etc/omamobile-bluejay-firstroot').write_text('old selector\n')
        names = ['init', 'etc', 'etc/sentinel']
        if existing:
            names.append('etc/omamobile-bluejay-firstroot')
        cpio = run(['cpio', '--quiet', '-o', '-H', 'newc'], cwd=ram,
                   input=('\n'.join(names) + '\n').encode())
        packed = run(['lz4', '-l', '-c'], input=cpio)
        header = bytearray(4096)
        header[:8] = b'VNDRBOOT'
        for offset, value in {8: 4, 12: 2048, 24: len(packed), 2096: 2128,
                              2100: sum(map(len, dtbs)), 2112: 108, 2116: 1, 2120: 108}.items():
            struct.pack_into('<I', header, offset, value)
        table = struct.pack('<I', len(packed)) + bytes(104)
        payload = header + packed + bytes(align(len(packed)) - len(packed))
        bundle = b''.join(dtbs)
        payload += bundle + bytes(align(len(bundle)) - len(bundle)) + table
        (images / 'vendor_boot.img').write_bytes(payload)
        for mode in ('persistent-development', 'ram-rescue'):
            out = p / f'out-{existing}-{mode}'
            run(['python3', str(repo / 'tools/bluejay-development-images.py'), str(base),
                 str(out), '--mode', mode, '--dt-overlay', str(overlay)])
            result = (out / 'images/vendor_boot.img').read_bytes()
            rn = struct.unpack_from('<I', result, 24)[0]
            dt_start = 4096 + align(rn)
            extracted = p / f'extract-{existing}-{mode}'
            extracted.mkdir()
            archive = run(['lz4', '-d', '-c'], input=result[4096:4096 + rn])
            run(['cpio', '-id', '--quiet', '--no-preserve-owner'], cwd=extracted, input=archive)
            assert (extracted / 'init').read_bytes() == (repo / 'initramfs/init').read_bytes()
            assert (extracted / 'etc/omamobile-bluejay-firstroot').read_text() == mode + '\n'
            assert (extracted / 'etc/sentinel').read_text() == 'unrelated record retained\n'
            for variant in (0, 1):
                size = struct.unpack_from('>I', result, dt_start + 4)[0]
                dtb = p / 'variant.dtb'
                dtb.write_bytes(result[dt_start:dt_start + size])
                assert run(['fdtget', '-t', 'u', str(dtb), '/', 'soc_id']).strip() == str(variant).encode()
                assert run(['fdtget', '-t', 'u', str(dtb), '/', 'test-value']).strip() == b'42'
                dt_start += size
            for name in ('boot.img', 'dtbo.img'):
                assert (out / 'images' / name).read_bytes() == (images / name).read_bytes()
    (images / 'DEVICE').write_text('another-device\n')
    rejected = subprocess.run(['python3', str(repo / 'tools/bluejay-development-images.py'),
                               str(base), str(p / 'wrong-device')], capture_output=True)
    assert rejected.returncode and not (p / 'wrong-device').exists()
print('ok - real CPIO reader verifies selector creation/update and both handover modes')
print('ok - both silicon variants retain identity and receive the overlay; kernel/board images retained')
print('ok - foreign-device images fail before creating output')
