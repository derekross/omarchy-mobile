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
for stale, guard_fault in ((False, False), (False, True), (True, False)):
    with tempfile.TemporaryDirectory() as tmp:
        p = Path(tmp)
        (p / 'block/sda48').mkdir(parents=True)
        (p / 'block/sda48/uevent').write_text('PARTNAME=userdata\n')
        (p / 'block/sda48/ro').write_text('0\n')
        (p / 'cmdline').write_text('rdinit=/init\n')
        (p / 'mode').write_text('persistent-development\n')
        (p / 'policy').write_text('omamobile-root\n')
        root = p / 'root'
        (root / 'usr/lib/systemd').mkdir(parents=True)
        systemd = root / 'usr/lib/systemd/systemd'
        systemd.touch()
        systemd.chmod(0o755)
        pending = root / 'var/lib/omamobile/root-boot-pending'
        pending.parent.mkdir(parents=True)
        if stale:
            pending.write_text('previous-boot\n')
        script = body.replace('/etc/omamobile-root-label', str(p / 'policy')).replace('/sys/block/sda', str(p / 'block')).replace('/proc/cmdline', str(p / 'cmdline')).replace('/etc/omamobile-root-mode', str(p / 'mode')).replace('/newroot', str(root))
        # Stop immediately before process quiescing; never execute kill/switch_root.
        stop = '  kill -9 -1 2>/dev/null'
        assert script.count(stop) == 1
        script = script.replace(stop, '  return 42')
        spies = '''
say() { echo "$*" >> "$LOG"; }
dumpe2fs() { echo 'Filesystem volume name: omamobile-root'; }
e2fsck() { return 0; }
grow_root() { echo UNEXPECTED_GROW >> "$LOG"; return 1; }
mount() { return 0; }
umount() { echo unmounted >> "$LOG"; }
sync() { echo synced >> "$LOG"; }
ufs_ro_pass() { :; }
ufs_unguarded() { [ "$GUARD_FAULT" = 1 ] && echo test-stop; }
'''
        f = p / 'run.sh'
        f.write_text(spies + script + 'boot_arch\n')
        shell = json.loads(os.environ.get('OMAMOBILE_BOOT_ARCH_TEST_SHELL', '["/bin/sh"]'))
        result = subprocess.run(shell + [str(f)], env={**os.environ, 'LOG': str(p / 'log'), 'GUARD_FAULT': str(int(guard_fault))}, capture_output=True, text=True, timeout=5)
        assert result.returncode == (42 if not stale and not guard_fault else 1), result
        log = (p / 'log').read_text()
        assert 'UNEXPECTED_GROW' not in log
        if stale:
            assert 'holding in RAM' in log and pending.read_text() == 'previous-boot\n'
            assert 'synced' not in log
        elif guard_fault:
            assert not pending.exists(), 'guard refusal must not leave a handover marker'
            assert 'test-stop' in log and 'synced' not in log
        else:
            assert pending.read_text() == Path('/proc/sys/kernel/random/boot_id').read_text()
            assert 'synced' in log and 'switching to Arch' in log
            # A held boot never clears the marker: every later boot stays held.
            for _ in range(2):
                held = subprocess.run(shell + [str(f)], env={**os.environ, 'LOG': str(p / 'log'), 'GUARD_FAULT': '0'}, capture_output=True, text=True, timeout=5)
                assert held.returncode == 1 and pending.exists()
        print('PASS:', 'failed previous boot holds in RAM' if stale else 'guard refusal leaves no marker' if guard_fault else 'fresh boot persists marker after guard; later boots remain held')
