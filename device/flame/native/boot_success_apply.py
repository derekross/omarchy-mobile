#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Explicit one-time boot_b GPT success transaction; no RO flags are changed."""
import argparse
import base64
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess

from read_gpt import Header, Reader, require, snapshot, verify_storage
from boot_success_plan import plan


def verify_safety_net():
    held = False
    for fd in Path('/proc/1/fd').iterdir():
        try:
            held = held or os.readlink(fd) == '/dev/watchdog0'
        except FileNotFoundError:
            continue
    require(held, 'PID 1 must hold the hardware watchdog')
    pid = int(Path('/run/rescue/run/flame-boot-repair-deadman.pid').read_text().strip())
    require(pid > 1, 'invalid recovery timer PID')
    require(b'flame-boot-repair-deadman.sh' in Path('/proc/' + str(pid) + '/cmdline').read_bytes(),
            'independent RAM recovery timer is not running')


def verify_loader(image, expected_sha256, installed):
    require(4096 < len(image) <= 4*1024*1024, 'unsupported loader size')
    require(hashlib.sha256(image).hexdigest() == expected_sha256, 'loader checksum mismatch')
    require(image[:8] == b'ANDROID!', 'loader header missing')
    require(struct.unpack_from('<I', image, 40)[0] == 0, 'loader must use header v0')
    require(struct.unpack_from('<I', image, 36)[0] == 4096, 'unexpected loader page size')
    require(struct.unpack_from('<I', image, 16)[0] == 0, 'unexpected loader ramdisk')
    size = struct.unpack_from('<I', image, 8)[0]
    require(0 < size <= len(image)-4096 and image[4096:4099] == b'\x1f\x8b\x08', 'missing compressed loader payload')
    require(image == installed, 'installed loader differs, including header; repair it before marking success')


def apply(r, before, approved):
    require(snapshot(r) == before, 'live GPT differs from the approved backup')
    require(plan(before) == approved, 'approved plan differs from the constrained operation')
    for number, write in enumerate(approved['writes_backup_first'], 1):
        lba = write['lba']; old = base64.b64decode(write['old']); new = base64.b64decode(write['new'])
        require(r.read(lba) == old, 'sector changed before write')
        # SG_IO addresses the LUN; the only permitted writes come from the
        # validated boot_b-bit plan. The block nodes retain their RO flags.
        cdb = bytes([0x8a, 8]) + struct.pack('>QI', lba, 1) + bytes(2)
        cmd = C.create_string_buffer(cdb); data = C.create_string_buffer(new); sense = C.create_string_buffer(96)
        h = Header(interface_id=ord('S'), dxfer_direction=-2, cmd_len=16,
                   mx_sb_len=96, dxfer_len=r.bs, dxferp=C.addressof(data),
                   cmdp=C.addressof(cmd), sbp=C.addressof(sense), timeout=15000)
        result = r.libc.ioctl(r.fd, 0x2285, C.byref(h))
        require(result == 0, 'write ioctl failed, errno=' + str(C.get_errno()))
        require(not (h.status or h.host_status or h.driver_status or h.resid), 'SCSI write did not complete cleanly')
        require(r.read(lba) == new, 'sector readback mismatch; stop without further writes')
        print('Verified metadata sector', number, 'of 4', flush=True)
    after = snapshot(r)
    expected = dict(before['blocks'])
    for w in approved['writes_backup_first']:
        expected[str(w['lba'])] = w['new']
    require(after['blocks'] == expected, 'unplanned GPT byte change')
    b = [p for p in after['partitions'] if p['name'] == 'boot_b']
    require(len(b) == 1 and b[0]['attributes'] & (1 << 54), 'successful flag did not read back')
    require(verify_storage() == (r.boot_node, r.userdata_node, r.disk_node),
            'partition nodes changed during the transaction')
    print('BOOT_B_SUCCESSFUL_READBACK_VERIFIED; all other GPT bytes and storage RO flags preserved', flush=True)


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--backup', required=True)
    p.add_argument('--backup-sha256', required=True)
    p.add_argument('--plan', required=True)
    p.add_argument('--plan-sha256', required=True)
    p.add_argument('--loader', required=True)
    p.add_argument('--loader-sha256', required=True)
    p.add_argument('--apply-only-boot-b-successful', action='store_true', required=True)
    args = p.parse_args()
    backup = Path(args.backup).read_bytes(); approved = Path(args.plan).read_bytes()
    require(hashlib.sha256(backup).hexdigest() == args.backup_sha256, 'backup checksum mismatch')
    require(hashlib.sha256(approved).hexdigest() == args.plan_sha256, 'plan checksum mismatch')
    subprocess.run(['systemctl', 'is-active', '--quiet', 'flame-storage-guard.service'], check=True)
    subprocess.run(['/usr/bin/flame-partition-links'], check=True)
    subprocess.run(['sha256sum', '--check', '--status', '/etc/omamobile/flame-calibration.sha256'], check=True)
    verify_safety_net()
    r = Reader()
    image = Path(args.loader).read_bytes()
    verify_loader(image, args.loader_sha256, os.pread(r.fd, len(image), 0))
    apply(r, json.loads(backup), json.loads(approved))
