#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""spawn_modem_rfsd from modem.conf with a stand-in rfsd: its exit ends the job
(the supervisor then stops the profile) unless this invocation's stop intent
is in place, when the job stays open for systemd; a wrong or symlinked intent
doesn't hide a crash."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

PROFILE = Path('profiles/modem.conf').read_text()
FUNCTION = 'spawn_modem_rfsd() {' + PROFILE.split('spawn_modem_rfsd() {', 1)[1].split('\n}', 1)[0] + '\n}'
INVOCATION = 'a' * 32


class RfsdLifecycle(unittest.TestCase):
    def run_case(self, intent):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake = root / 'fake-rfsd'
            fake.write_text('#!/bin/bash\necho $$ > "$FAKE_PID"\ntrap "exit 1" USR1\nwhile :; do sleep 0.05; done\n')
            fake.chmod(0o700)
            stop_dir = root / 'run'
            stop_dir.mkdir()
            marker = stop_dir / ('intent-' + INVOCATION)
            if intent == 'valid':
                marker.write_text(INVOCATION + '\n')
            elif intent == 'wrong':
                marker.write_text('another invocation\n')
            elif intent == 'symlink':
                target = root / 'target'
                target.write_text(INVOCATION + '\n')
                marker.symlink_to(target)
            script = '''set -euo pipefail
declare -A PIDS
say() { :; }
android_env() { ENV=(env); }
CHROOT_BIN=$FAKE; ROOT=/unused
''' + FUNCTION + '''
spawn_modem_rfsd
wait -n || true
'''
            env = os.environ | {'INVOCATION_ID': INVOCATION, 'OMAMOBILE_MODEM_RUN': str(stop_dir),
                                'FAKE_PID': str(root / 'pid'), 'FAKE': str(fake)}
            process = subprocess.Popen(['bash', '-c', script], env=env, start_new_session=True,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                deadline = time.monotonic() + 5
                while not (root / 'pid').exists() and time.monotonic() < deadline:
                    time.sleep(.02)
                self.assertTrue((root / 'pid').exists(), 'fake rfsd did not start')
                os.kill(int((root / 'pid').read_text()), signal.SIGUSR1)
                if intent == 'valid':
                    time.sleep(.4)
                    self.assertIsNone(process.poll(), 'orderly-stop rfsd exit stopped the supervisor')
                else:
                    process.wait(timeout=5)
            finally:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=5)

    def test_unexpected_rfsd_exit_stops_supervision(self):
        self.run_case(None)

    def test_orderly_poweroff_keeps_supervisor_alive(self):
        self.run_case('valid')

    def test_wrong_or_symlinked_intent_does_not_hide_a_crash(self):
        for intent in ('wrong', 'symlink'):
            with self.subTest(intent=intent):
                self.run_case(intent)


if __name__ == '__main__':
    unittest.main()
