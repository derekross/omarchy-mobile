#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check descriptor packing, legacy handover and fail-closed development modes."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parent.parent
source = (repo / 'initramfs/init').read_text()


def function(name):
    return name + '() {' + source.split(name + '() {', 1)[1].split('\n}\n', 1)[0] + '\n}\n'


with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp)
    fixture = p / 'repo'
    (fixture / 'bin').mkdir(parents=True)
    (fixture / 'device/six').mkdir(parents=True)
    shutil.copy2(repo / 'bin/omamobile', fixture / 'bin/omamobile')
    (fixture / 'omamobile.conf').write_text('DEVICE="${DEVICE:-six}"\nSRC_DIR=/nonexistent\n')
    descriptor = (repo / 'device/bluejay/device.conf').read_text().replace('CODENAME=bluejay', 'CODENAME=six')
    conf = fixture / 'device/six/device.conf'

    def pack(extra, name, valid=True):
        conf.write_text(descriptor + '\n' + extra)
        out = p / name
        result = subprocess.run([str(fixture / 'bin/omamobile'), 'initramfs-config', str(out)],
                                env={**os.environ, 'DEVICE': 'six'}, capture_output=True, text=True)
        assert (result.returncode == 0) == valid, result.stderr
        if not valid:
            assert not out.exists(), name
        return out

    names = ('omamobile-root-label', 'omamobile-root-mode', 'omamobile-usb-recovery')
    default = pack('', 'default')
    assert not any((default / n).exists() for n in names)
    for mode in ('persistent-development', 'ram-rescue'):
        out = pack('INITRAMFS_ROOT_LABEL=omamobile-root\nINITRAMFS_ROOT_MODE=' + mode +
                   '\nINITRAMFS_USB_RECOVERY=no\n', mode)
        assert [(out / n).read_text().strip() for n in names] == ['omamobile-root', mode, 'no']
    for i, bad in enumerate(('INITRAMFS_ROOT_LABEL=wrong\n', 'INITRAMFS_ROOT_LABEL=""\n',
                             'INITRAMFS_ROOT_MODE=unknown\n', 'INITRAMFS_ROOT_MODE=ram-rescue\n',
                             'INITRAMFS_USB_RECOVERY=maybe\n')):
        pack(bad, 'bad-' + str(i), False)
    print('ok - default packing is unchanged; explicit policies validated before output')

    (fixture / 'initramfs').mkdir()
    (fixture / 'initramfs/init').write_text('#!/bin/sh\n')
    for i, (extra, message) in enumerate((
        ('INITRAMFS_ROOT_LABEL=omamobile-root\nINITRAMFS_ROOT_MODE=persistent-development\n', 'INITRAMFS_ROOT_MODE'),
        ('INITRAMFS_ROOT_LABEL=omamobile-root\nINITRAMFS_ROOT_MODE=ram-rescue\n', 'INITRAMFS_ROOT_MODE'),
        ('INITRAMFS_USB_RECOVERY=no\n', 'INITRAMFS_USB_RECOVERY=no'),
    )):
        conf.write_text(descriptor + '\n' + extra)
        output = p / ('release-' + str(i))
        result = subprocess.run([str(fixture / 'bin/omamobile'), 'initramfs', '--release'],
                                env={**os.environ, 'DEVICE': 'six', 'KERNEL_OUT': str(output), 'WORK': str(p / 'work')},
                                capture_output=True, text=True)
        assert result.returncode != 0 and message in result.stderr and 'not --release' in result.stderr, result
        assert not output.exists() and not (p / 'work').exists()
    print('ok - development root mode and disabled USB recovery refuse release builds before downloads')

    nfsfile = p / 'nfsroot'
    dispatch = source.rsplit('# A requested NFS root must not silently fall through', 1)[1].split('\nfi', 1)[0].split('\n', 1)[1] + '\nfi\n'
    assert len(dispatch.splitlines()) == 6 and dispatch.count('boot_nfs') == 1 and dispatch.count('boot_root') == 1
    assert all(word not in dispatch for word in ('/sys/', 'mount', 'kill', 'blockdev', 'devmem'))
    for requested in (False, True):
        nfsfile.write_text('host:/export\n' if requested else '')
        spies = 'say() { :; }; boot_nfs() { echo nfs; return 1; }; boot_root() { echo userdata; return 1; }\n'
        result = subprocess.run(['/bin/sh', '-c', spies + dispatch.replace('/etc/omamobile-nfsroot', str(nfsfile))], capture_output=True, text=True)
        assert result.stdout.strip() == ('nfs' if requested else 'userdata'), result
    print('ok - requested NFS failure never falls through to userdata policy')

    modefile = p / 'mode'
    for value, calls_arch in ((None, True), ('persistent-development', True),
                              ('ram-rescue', False), ('unknown', False), ('', False)):
        if value is None:
            modefile.unlink(missing_ok=True)
        else:
            modefile.write_text(value + '\n')
        script = 'say() { :; }; boot_arch() { echo handover; return 1; }\n'
        script += function('boot_root').replace('/etc/omamobile-root-mode', str(modefile))
        result = subprocess.run(['/bin/sh', '-c', script + 'boot_root'], capture_output=True, text=True)
        assert result.returncode == 1
        assert ('handover' in result.stdout) == calls_arch, (value, result)
    print('ok - absent mode preserves boot; rescue and malformed modes cannot hand over')

    block = p / 'block/sda27'
    block.mkdir(parents=True)
    (block / 'uevent').write_text('PARTNAME=userdata\n')
    (block / 'ro').write_text('0\n')
    (p / 'cmdline').write_text('console=null\n')
    script = function('boot_arch').replace('/sys/block/sda', str(p / 'block'))
    script = script.replace('/proc/cmdline', str(p / 'cmdline'))
    script = script.replace('/etc/omamobile-root-label', str(p / 'absent-label'))
    script = script.replace('/etc/omamobile-root-mode', str(p / 'absent-mode'))
    # A legacy unlabelled root retains repair/growth/mount ordering, even if
    # repair returns 4. Tightening that policy requires the descriptor opt-in.
    spies = '''
say() { :; }
dumpe2fs() { echo UNEXPECTED_HEADER; return 1; }
mkdir() { :; }
e2fsck() { echo fsck >> "$LOG"; return 4; }
grow_root() { echo grow >> "$LOG"; }
mount() { echo mount >> "$LOG"; return 1; }
'''
    log = p / 'calls'
    result = subprocess.run(['/bin/sh', '-c', spies + script + 'boot_arch'],
                            env={**os.environ, 'LOG': str(log)}, capture_output=True, text=True)
    assert result.returncode == 1 and not result.stdout
    assert log.read_text().splitlines() == ['fsck', 'grow', 'mount']
    print('ok - unlabelled legacy roots retain their existing handover path')
