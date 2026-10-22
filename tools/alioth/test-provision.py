#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Provision a tiny ext4 fixture in a path containing spaces; no phone access."""
from pathlib import Path
import os
import pwd
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ['mke2fs', 'debugfs', 'e2fsck', 'img2simg', 'openssl', 'ssh-keygen']
missing = [name for name in TOOLS if not shutil.which(name)]
if missing:
    print('ok - owner-image fixture # SKIP missing: ' + ', '.join(missing))
    raise SystemExit(0)


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, **kwargs)


with tempfile.TemporaryDirectory(prefix='alioth-provision-') as directory:
    project = Path(directory) / 'checkout with spaces'
    tools = project / 'tools/alioth'; tools.mkdir(parents=True)
    shutil.copyfile(ROOT / 'tools/alioth/provision-image.py', tools / 'provision-image.py')
    checker = project / 'packages/omamobile-firstboot/bin'; checker.mkdir(parents=True)
    shutil.copyfile(ROOT / 'packages/omamobile-firstboot/bin/omamobile-firstboot', checker / 'omamobile-firstboot')
    private = project / 'keys'; private.mkdir(mode=0o700)
    result = run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(private / 'alioth_ed25519')])
    assert result.returncode == 0, 'Fixture SSH key generation failed'
    tree = project / 'fixture-root'
    (tree / 'etc/omamobile').mkdir(parents=True); (tree / 'root').mkdir()
    (tree / 'etc/passwd').write_text('root:x:0:0:root:/root:/bin/bash\n')
    image = project / 'generic.img'
    result = run(['mke2fs', '-q', '-t', 'ext4', '-L', 'omamobile-root', '-d', str(tree), str(image), '32M'])
    assert result.returncode == 0, 'Fixture ext4 creation failed'
    command = ['python3', str(tools / 'provision-image.py'), '--root-image', str(image), '--timezone', 'UTC']
    result = run(command + ['--username', 'root'])
    assert result.returncode != 0, 'Reserved account accepted'
    assert not (private / 'alioth-credentials.json').exists(), 'Invalid owner settings persisted'
    assert not (project / 'out/alioth/images/rootfs.img').exists(), 'Invalid owner changed image'
    # When possible, exercise the build host's existing account name: it must
    # be validated against the target passwd, not against the host's users.
    username = pwd.getpwuid(os.getuid()).pw_name if os.getuid() >= 1000 else 'mobile'
    result = run(command + ['--username', username])
    assert result.returncode == 0, 'Valid owner provisioning failed'
    assert (private / 'alioth-credentials.json').stat().st_mode & 0o777 == 0o600
    assert (project / 'out/alioth/images/rootfs.img').stat().st_mode & 0o777 == 0o600
    assert (project / 'out/alioth/images/rootfs-sparse.img').is_file()
print('ok - real ext4 provisioning supports spaces, validates target accounts, and keeps credentials private')
