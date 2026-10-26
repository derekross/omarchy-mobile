#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prove owner builds cannot replace the maintainer signing/release outputs."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]

with tempfile.TemporaryDirectory(prefix='alioth-isolation-') as directory:
    project = Path(directory) / 'checkout with spaces'
    tools = project / 'tools/alioth'
    tools.mkdir(parents=True)
    for name in ('init-keys.py', 'build.py'):
        shutil.copyfile(ROOT / 'tools/alioth' / name, tools / name)
    sentinels = {
        'keys/fingerprint': b'maintainer fingerprint\n',
        'keys/gnupg/keep': b'maintainer secret key placeholder',
        'out/repo/aarch64/omamobile.db': b'maintainer package database',
        'out/omamobile-rootfs-release-aarch64.img': b'Pixel root image',
    }
    for name, data in sentinels.items():
        path = project / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    subprocess.run([sys.executable, str(tools / 'init-keys.py')], check=True, stdout=subprocess.DEVNULL)
    assert (project / 'keys/alioth/fingerprint').is_file()
    assert (project / 'keys/alioth/gnupg').is_dir()
    assert (project / 'keys/alioth/alioth_ed25519').stat().st_mode & 0o777 == 0o600
    profile = project / 'rootfs'
    profile.mkdir()
    shutil.copyfile(ROOT / 'rootfs/packages.omamobile-alioth', profile / 'packages.omamobile-alioth')
    spec = importlib.util.spec_from_file_location('build', tools / 'build.py')
    build = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(build)
    calls = []
    def run(command, *, env, check):
        calls.append((command, env.copy()))
        assert env['OMAMOBILE_REPO_DIR'] == str(project / 'out/alioth/repo')
        assert env['OMAMOBILE_ROOTFS_OUT'] == str(project / 'out/alioth')
        assert env['OMAMOBILE_SIGNING_DIR'] == str(project / 'keys/alioth')
        assert env['OMAMOBILE_KEYRING_DIR'] == str(project / 'keys/alioth/build-keyring')
    cwd = Path.cwd()
    old_mask = os.umask(0o077)
    try:
        with patch.object(sys, 'argv', ['build.py', '--username', 'mobile']), \
             patch.object(build.subprocess, 'run', side_effect=run), contextlib.redirect_stdout(io.StringIO()):
            build.main()
    finally:
        os.chdir(cwd)
        os.umask(old_mask)
    command = next(c for c, _ in calls if 'tools/alioth/provision-image.py' in c)
    assert command[command.index('--root-image') + 1].startswith('out/alioth/')
    assert any(c[0] == 'tools/build-packages' for c, _ in calls)
    assert any(c[0] == 'tools/build-rootfs' for c, _ in calls)
    for name, data in sentinels.items():
        assert (project / name).read_bytes() == data, 'maintainer file changed: ' + name
    # Stop gpg-agent before deleting its temporary homedir.
    subprocess.run(['gpgconf', '--homedir', str(project / 'keys/alioth/gnupg'), '--kill', 'gpg-agent'], check=True)
print('ok - actual F3 key generation preserves maintainer keys; build commands isolate repository and root output')
