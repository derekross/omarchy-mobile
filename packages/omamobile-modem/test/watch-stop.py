#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""omamobile-modem-cp watch when the CP leaves ONLINE: during this unit
invocation's orderly stop (profile_stop's intent file, holding the ID) no
notice goes out; without one, or with a wrong or symlinked intent, one does
(#389 review)."""
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

loader = importlib.machinery.SourceFileLoader('modem_cp', 'lib/omamobile-modem-cp')
cp = importlib.util.module_from_spec(importlib.util.spec_from_loader('modem_cp', loader))
loader.exec_module(cp)

INVOCATION = '0123456789abcdef0123456789abcdef'
OTHER = 'fedcba9876543210fedcba9876543210'


class Done(Exception):
    pass


class WatchStop(unittest.TestCase):
    def run_watch(self, intent=None, symlink=False):
        """ONLINE, then OFFLINE; returns the notices sent."""
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory) / 'run'
            run.mkdir()
            if intent is not None:
                target = run / f'intent-{INVOCATION}'
                if symlink:
                    real = Path(directory) / 'elsewhere'
                    real.write_text(intent + '\n')
                    target.symlink_to(real)
                else:
                    target.write_text(intent + '\n')
            states = iter([cp.ONLINE, 0, 0])
            sleeps = []

            def sleep(seconds):
                sleeps.append(seconds)
                if len(sleeps) == 3:
                    raise Done

            sent = []
            with patch.object(cp, 'RUN', run), \
                 patch.dict(os.environ, {'INVOCATION_ID': INVOCATION}), \
                 patch.object(cp.os, 'open', return_value=99), \
                 patch.object(cp.fcntl, 'ioctl', side_effect=lambda fd, cmd: next(states)), \
                 patch.object(cp, 'record_crash'), \
                 patch.object(cp, 'notify', side_effect=lambda title, body: sent.append(title)), \
                 patch.object(cp.time, 'sleep', side_effect=sleep):
                with self.assertRaises(Done):
                    cp.watch()
            return sent

    def test_stop_with_this_invocations_intent_sends_nothing(self):
        self.assertEqual(self.run_watch(intent=INVOCATION), [])

    def test_without_intent_sends_once(self):
        self.assertEqual(self.run_watch(), ['Cellular stopped'])

    def test_wrong_intent_sends_once(self):
        self.assertEqual(self.run_watch(intent=OTHER), ['Cellular stopped'])

    def test_symlinked_intent_sends_once(self):
        self.assertEqual(self.run_watch(intent=INVOCATION, symlink=True), ['Cellular stopped'])

    def test_no_invocation_id_is_no_intent(self):
        with patch.dict(os.environ, {'INVOCATION_ID': ''}):
            self.assertFalse(cp.stop_intended())


if __name__ == '__main__':
    unittest.main()
