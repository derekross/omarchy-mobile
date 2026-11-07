#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Execute the actual mobile PAM-preservation branch on isolated fake paths.
Only root-UID metadata is stubbed; real modes/symlink tests and file hashes apply.
No PAM, service or privilege helper is ever invoked.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

source=Path(sys.argv[1]).read_text()
start=source.index('# Mobile owns its existing PAM policy')
end=source.index('echo "Configuring lock screen password authentication..."',start)
guard=source[start:end]
with tempfile.TemporaryDirectory() as d:
    root=Path(d);helper=root/'mobile-update';helper.write_text('#!/bin/sh\nexit 0\n');helper.chmod(0o755)
    policy=root/'password';policy.write_text('synthetic customized password PAM\n');policy.chmod(0o644)
    fp=root/'fingerprint';fp.write_text('synthetic fingerprint max-tries=1\n');fp.chmod(0o644)
    baseline=[hashlib.sha256(p.read_bytes()).hexdigest() for p in (policy,fp)]
    script='set -eu\nstat() { echo "$FAKE_UID"; }\n'+guard.replace('/usr/bin/omamobile-update',str(helper)).replace('/etc/pam.d/omarchy-lock-password',str(policy))+'\nexit 77\n'
    def run(uid='0'):
        env=dict(os.environ);env['FAKE_UID']=uid
        return subprocess.run(['bash','-c',script],env=env,capture_output=True,text=True)
    assert run().returncode==0
    assert [hashlib.sha256(p.read_bytes()).hexdigest() for p in (policy,fp)]==baseline
    assert run('1000').returncode==1
    policy.chmod(0o666);assert run().returncode==1;policy.chmod(0o644)
    original=root/'saved';policy.rename(original);policy.symlink_to(original)
    assert run().returncode==1
    policy.unlink();assert run().returncode==77,'fresh setup may continue when no prior password policy exists'
print('PASS actual PAM preservation branch: secure policy unchanged; wrong owner/writable/symlink refused; absent policy permits initial setup; no privileged commands')
