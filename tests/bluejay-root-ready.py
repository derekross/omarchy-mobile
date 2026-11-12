#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run the proposed SSH-ready helper with a fake USB link and service state."""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parent.parent
source = (repo / 'device/bluejay/bringup/bin/omamobile-bluejay-boot-ready').read_text()
for address, ssh in ((True, True), (False, True), (True, False)):
    with tempfile.TemporaryDirectory() as tmp:
        p = Path(tmp)
        root = p / 'state'
        root.mkdir()
        marker = root / 'root-boot-pending'
        marker.write_text('pending\n')
        bindir = p / 'bin'
        bindir.mkdir()
        (bindir / 'ip').write_text('#!/bin/sh\n' +
                                  ('echo "1: usb0 inet 172.16.42.1/24 scope global usb0"\n' if address else 'exit 0\n'))
        (bindir / 'systemctl').write_text('#!/bin/sh\nexit ' + ('0\n' if ssh else '1\n'))
        for f in bindir.iterdir():
            f.chmod(0o755)
        helper = p / 'ready'
        helper.write_text(source.replace('/var/lib/omamobile', str(root)))
        result = subprocess.run(['bash', str(helper)],
                                env={**os.environ, 'PATH': str(bindir) + ':' + os.environ['PATH']},
                                capture_output=True, text=True)
        assert (result.returncode == 0) == (address and ssh), result
        assert marker.exists() != (address and ssh)
        print('ok - pending marker follows verified USB and SSH readiness:', address, ssh)
