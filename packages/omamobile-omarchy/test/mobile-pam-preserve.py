#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run the real PAM-preservation branch with isolated paths and fake UID metadata.

No PAM, service or privilege helper is invoked. Modes, symlinks and hashes use
real temporary files.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).read_text()
start = source.index('# Mobile owns its existing PAM policy')
end = source.index('echo "Configuring lock screen password authentication..."', start)
guard = source[start:end]

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    helper = root / 'mobile-update'
    helper.write_text('#!/bin/sh\nexit 0\n')
    helper.chmod(0o755)
    policy = root / 'password'
    policy.write_text('synthetic customized password PAM\n')
    policy.chmod(0o644)
    fingerprint = root / 'fingerprint'
    fingerprint.write_text('synthetic fingerprint max-tries=1\n')
    fingerprint.chmod(0o644)

    def hashes():
        return [hashlib.sha256(path.read_bytes()).hexdigest() for path in (policy, fingerprint)]

    baseline = hashes()
    isolated_guard = guard.replace('/usr/bin/omamobile-update', str(helper))
    isolated_guard = isolated_guard.replace('/etc/pam.d/omarchy-lock-password', str(policy))
    script = 'set -eu\nstat() { echo "$FAKE_UID"; }\n' + isolated_guard + '\nexit 77\n'

    def run(uid='0'):
        return subprocess.run(
            ['bash', '-c', script], env=dict(os.environ, FAKE_UID=uid),
            capture_output=True, text=True,
        )

    assert run().returncode == 0
    assert hashes() == baseline
    assert run('1000').returncode == 1
    policy.chmod(0o666)
    assert run().returncode == 1
    policy.chmod(0o644)
    original = root / 'saved'
    policy.rename(original)
    policy.symlink_to(original)
    assert run().returncode == 1
    policy.unlink()
    assert run().returncode == 77, 'absent policy permits fresh setup'

print('PASS actual PAM guard: secure policy unchanged; unsafe metadata refused; absent policy permits setup; no privileged commands')
