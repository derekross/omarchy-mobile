#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check Grizzly D1 images against checksums and saved Fastboot variables."""

import argparse
import hashlib
import os
from pathlib import Path
import re
import struct


IMAGES = ('boot', 'init_boot', 'vendor_boot', 'vendor_kernel_boot', 'dtbo')
IMAGE_FILES = {f'{name}.img' for name in IMAGES}
CHAINED = ('boot', 'init_boot')
D1_BOOTLOADER = 'spacecraft-17.4-16729013'
FOOTER = struct.Struct('>4sIIQQQ28x')
VBMETA_HEADER_SIZE = 256
ANDROID_SPARSE_MAGIC = b'\x3a\xff\x26\xed'
BASE_VARS = ('product', 'is-userspace', 'current-slot', 'unlocked',
             'version-bootloader', 'snapshot-update-status')
SLOT_VARS = ('slot-successful', 'slot-unbootable', 'slot-retry-count')
PARTITION_VARS = tuple(f'partition-size:{image}_b' for image in IMAGES)
GETVAR_KEYS = (
    *PARTITION_VARS,
    *(f'{key}:{slot}' for key in SLOT_VARS for slot in 'ab'),
    *(f'version-bootloader{separator}{slot}' for separator in '-_:' for slot in 'ab'),
    'serialno',
    *BASE_VARS,
)
GETVAR_LINE = re.compile(r'^(?:\(bootloader\)\s*)?(' + '|'.join(map(re.escape, GETVAR_KEYS))
                         + r'):\s*(.*?)\s*$')


def expected_hashes(path):
    hashes = {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r'([0-9a-fA-F]{64})[ \t]+\*?([^ \t]+)', line)
        if not match or match[2] not in IMAGE_FILES:
            continue
        digest, name = match.groups()
        if name in hashes:
            raise ValueError(f'duplicate checksum for {name}')
        hashes[name] = digest.lower()
    return hashes


def fastboot_vars(path):
    values = {}
    for line in path.read_text().splitlines():
        match = GETVAR_LINE.fullmatch(line.strip())
        if not match:
            continue
        key, value = match.groups()
        if key not in BASE_VARS and key.startswith('version-bootloader'):
            key = f'version-bootloader:{key[-1]}'
        if key in values and values[key] != value:
            raise ValueError(f'conflicting observations for {key}')
        values[key] = value
    return values


def check_rescue_return(values, before):
    """Recognize reselection of the verified stock slot after a B rescue."""
    identity = ('serialno', *BASE_VARS, *PARTITION_VARS)
    return (all(values.get(key) and values[key] == before.get(key) for key in identity)
            and before.get('slot-successful:a') == 'yes'
            and before.get('slot-unbootable:a') == 'no'
            and values.get('slot-successful:a') == 'no'
            and values.get('slot-unbootable:a') == 'no'
            and values.get('slot-retry-count:a') == '3')


def check_phone(values, issues, require_healthy_a=False, before_rescue=None):
    if not values:
        issues.append('Fastboot observations are missing')
        return {}

    expected = {'product': 'grizzly', 'is-userspace': 'no', 'current-slot': 'a',
                'unlocked': 'yes', 'snapshot-update-status': 'none'}
    for key, want in expected.items():
        value = values.get(key)
        if value != want and (key, value) != ('current-slot', '_a'):
            issues.append(f'{key} must report {want} ({value or "unmeasured"})')
    if require_healthy_a and values.get('slot-successful:a') != 'yes':
        if before_rescue and check_rescue_return(values, before_rescue):
            print('Slot A passed before rescue. The reselection reset its success flag.')
        else:
            issues.append('slot A must be marked successful or match its verified rescue return')
    if values.get('slot-unbootable:a') == 'yes':
        issues.append('slot A is marked unbootable')
    elif require_healthy_a and values.get('slot-unbootable:a') != 'no':
        issues.append('slot A must be marked bootable')

    for slot in 'ab':
        version = values.get(f'version-bootloader:{slot}')
        if slot == 'a' and values.get('current-slot') in ('a', '_a'):
            active_version = values.get('version-bootloader')
            if version and active_version and version != active_version:
                issues.append('current and explicit slot A bootloader versions disagree')
            version = version or active_version
        if version != D1_BOOTLOADER:
            issues.append(f'slot {slot} D1 bootloader version is {version or "unmeasured"}')
        successful, unbootable, retries = (values.get(f'{key}:{slot}') or '?' for key in SLOT_VARS)
        print(f'Slot {slot} bootloader {version or "unmeasured"}, '
              f'successful {successful}, unbootable {unbootable}, retries {retries}')

    capacities = {}
    for name in IMAGES:
        key = f'partition-size:{name}_b'
        value = values.get(key, '')
        if re.fullmatch(r'0[xX][0-9a-fA-F]+', value):
            size = int(value, 16)
            if size:
                capacities[name] = size
                continue
        issues.append(f'{key} has no measured positive capacity')
    return capacities


def avb_algorithm(image, size):
    """Read the footer and vbmeta envelope, without claiming signature trust."""
    if size < FOOTER.size:
        return None
    image.seek(-FOOTER.size, os.SEEK_END)
    magic, major, _, original, offset, length = FOOTER.unpack(image.read(FOOTER.size))
    if magic != b'AVBf':
        return None
    if major != 1 or not 0 < original <= offset or length < VBMETA_HEADER_SIZE:
        raise ValueError('invalid AVB footer')
    if offset + length > size - FOOTER.size:
        raise ValueError('AVB metadata extends past the footer')
    image.seek(offset)
    magic, _, _, auth, aux, algorithm = struct.unpack('>4sIIQQI', image.read(32))
    if magic != b'AVB0' or VBMETA_HEADER_SIZE + auth + aux != length or (algorithm and not auth):
        raise ValueError('invalid AVB metadata envelope')
    return algorithm


def check_image(directory, name, expected, capacity, issues):
    filename = f'{name}.img'
    path = directory / filename
    if not path.is_file():
        issues.append(f'{filename} is missing or not a regular file')
        return
    with path.open('rb') as image:
        size = os.fstat(image.fileno()).st_size
        prefix = image.read(4)
        digest = hashlib.sha256()
        digest.update(prefix)
        for block in iter(lambda: image.read(1 << 20), b''):
            digest.update(block)
        try:
            algorithm = avb_algorithm(image, size)
        except (ValueError, struct.error) as exc:
            issues.append(f'{filename}: {exc}')
            algorithm = None

    if not size:
        issues.append(f'{filename} is empty')
    if prefix == ANDROID_SPARSE_MAGIC:
        issues.append(f'{filename} is Android sparse and cannot be checked as a raw image')
    if expected is None or digest.hexdigest() != expected:
        issues.append(f'{filename} checksum is missing or differs')
    if capacity is not None and size > capacity:
        issues.append(f'{filename} exceeds {name}_b capacity')
    if name in CHAINED:
        if not algorithm:
            issues.append(f'{filename} has no AVB metadata declaring a signature algorithm')
        elif capacity is not None and size != capacity:
            issues.append(f'{filename} footer would miss the end of {name}_b')

    metadata = 'absent' if algorithm is None else f'algorithm {algorithm}'
    print(f'{filename:24} {size:>10} bytes  {name}_b {capacity or "unmeasured"}  AVB {metadata}')


def check_readback(images, path, capacity, issues):
    if capacity is None:
        issues.append('vendor_boot_b readback needs a measured partition capacity')
        return
    with path.open('rb') as readback, (images / 'vendor_boot.img').open('rb') as staged:
        if os.fstat(readback.fileno()).st_size != capacity:
            issues.append('vendor_boot_b readback length differs from the measured capacity')
            return
        for block in iter(lambda: staged.read(1 << 20), b''):
            if readback.read(len(block)) != block:
                issues.append('vendor_boot_b readback differs from the supplied vendor_boot.img')
                return
        print(f'vendor_boot_b readback matches {staged.tell()} supplied image bytes')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('images', type=Path, help='directory of Grizzly boot images')
    parser.add_argument('checksums', type=Path, help='reviewed SHA-256 manifest for the five images')
    parser.add_argument('--fastboot-vars', type=Path, help='saved read-only Fastboot observations')
    parser.add_argument('--require-healthy-a', action='store_true',
                        help='require slot A to report successful and bootable before staging')
    parser.add_argument('--before-rescue', type=Path,
                        help='private Fastboot capture of verified stock A immediately before the rescue')
    parser.add_argument('--vendor-boot-readback', type=Path, help='saved full vendor_boot_b readback')
    args = parser.parse_args()
    if args.before_rescue and not args.require_healthy_a:
        parser.error('--before-rescue requires --require-healthy-a')

    issues = []
    try:
        hashes = expected_hashes(args.checksums)
        variables = fastboot_vars(args.fastboot_vars) if args.fastboot_vars else {}
        before = fastboot_vars(args.before_rescue) if args.before_rescue else None
        capacities = check_phone(variables, issues, args.require_healthy_a, before)
        for image in IMAGES:
            check_image(args.images, image, hashes.get(f'{image}.img'), capacities.get(image), issues)
        if args.vendor_boot_readback:
            check_readback(args.images, args.vendor_boot_readback, capacities.get('vendor_boot'), issues)
    except (OSError, ValueError) as exc:
        parser.exit(1, f'{exc}\n')

    for issue in issues:
        print(f'HOLD {issue}')
    if not issues:
        print('File and captured-device checks passed. Device acceptance still requires review.')
    return bool(issues)


if __name__ == '__main__':
    raise SystemExit(main())
