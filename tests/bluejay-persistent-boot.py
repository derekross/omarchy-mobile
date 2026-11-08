#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the actual persistent boot function without mounts or phone access."""
from pathlib import Path
import os
import json
import subprocess
import tempfile

repo = Path(__file__).resolve().parent.parent
source = (repo / 'initramfs/init').read_text()
body = 'boot_arch() {' + source.split('boot_arch() {', 1)[1].split('\n}\n', 1)[0] + '\n}\n'
for stale in (False, True):
    with tempfile.TemporaryDirectory() as tmp:
        p = Path(tmp)
        (p / 'block/sda48').mkdir(parents=True)
        (p / 'block/sda48/uevent').write_text('PARTNAME=userdata\n')
        (p / 'block/sda48/ro').write_text('0\n')
        (p / 'cmdline').write_text('rdinit=/init\n')
        (p / 'mode').write_text('persistent-development\n')
        root = p / 'root'
        (root / 'usr/lib/systemd').mkdir(parents=True)
        systemd = root / 'usr/lib/systemd/systemd'
        systemd.touch()
        systemd.chmod(0o755)
        pending = root / 'var/lib/omamobile/bluejay-root-pending'
        pending.parent.mkdir(parents=True)
        if stale:
            pending.write_text('previous-boot\n')
        script = body.replace('/sys/block/sda', str(p / 'block')).replace('/proc/cmdline', str(p / 'cmdline')).replace('/etc/omamobile-bluejay-firstroot', str(p / 'mode')).replace('/newroot', str(root))
        spies = '''
say() { echo "$*" >> "$LOG"; }
dumpe2fs() { echo 'Filesystem volume name: omamobile-root'; }
e2fsck() { return 0; }
grow_root() { echo UNEXPECTED_GROW >> "$LOG"; return 1; }
mount() { return 0; }
umount() { echo unmounted >> "$LOG"; }
sync() { echo synced >> "$LOG"; }
ufs_ro_pass() { :; }
# Stop before process quiescing: the test deliberately reports a guard fault.
ufs_unguarded() { echo test-stop; }
'''
        f = p / 'run.sh'
        f.write_text(spies + script + 'boot_arch\n')
        shell = json.loads(os.environ.get('OMAMOBILE_BOOT_ARCH_TEST_SHELL', '["/bin/sh"]'))
        result = subprocess.run(shell + [str(f)], env={**os.environ, 'LOG': str(p / 'log')}, capture_output=True, text=True, timeout=5)
        assert result.returncode == 1, result
        log = (p / 'log').read_text()
        assert 'UNEXPECTED_GROW' not in log
        if stale:
            assert 'holding in RAM' in log and pending.read_text() == 'previous-boot\n'
            assert 'synced' not in log
        else:
            assert pending.read_text() == Path('/proc/sys/kernel/random/boot_id').read_text()
            assert 'synced' in log and 'test-stop' in log
        print('PASS:', 'failed previous boot holds in RAM' if stale else 'fresh boot persists marker and skips growth')
