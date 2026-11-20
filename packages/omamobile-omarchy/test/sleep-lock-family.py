#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Observe the actual sleep test's patch input; no sleep/display command runs."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

PACKAGE = Path(__file__).resolve().parent.parent
PATCH = '0021-sleep-turn-the-display-off-before-suspend.patch'


class SourceFamily(unittest.TestCase):
    def capture(self, version, wrong_family=False):
        with tempfile.TemporaryDirectory(prefix='sleep-family-') as temporary:
            root = Path(temporary)
            package = root / 'package'
            (package / 'test').mkdir(parents=True)
            for family in ['patches', 'legacy-4.0.6']:
                target = package / family / PATCH
                target.parent.mkdir()
                target.write_bytes((PACKAGE / family / PATCH).read_bytes())
            source = (PACKAGE / 'test/sleep-lock.sh').read_text()
            if wrong_family:
                source = source.replace('series=legacy-4.0.6', 'series=patches')
            script = package / 'test/sleep-lock.sh'
            script.write_text(source)
            extracted = root / 'extracted'
            binary = extracted / 'usr/share/omarchy/bin/omarchy-system-sleep-lock'
            binary.parent.mkdir(parents=True)
            binary.write_text('#!/bin/sh\nexit 99\n')
            (extracted / '.PKGINFO').write_text(f'pkgname = omarchy\npkgver = {version}\n')
            fake = root / 'fake'
            fake.mkdir()
            recorder = fake / 'patch'
            recorder.write_text('#!/bin/sh\ncat > "$PATCH_CAPTURE"\nexit 73\n')
            recorder.chmod(0o755)
            capture = root / 'captured-patch'
            env = dict(os.environ, OMARCHY_PKG_ROOT=str(extracted),
                       PATH=str(fake) + os.pathsep + os.environ['PATH'], PATCH_CAPTURE=str(capture))
            result = subprocess.run(['bash', str(script)], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, 'inert recorder must stop before display/sleep helpers')
            return capture.read_bytes() if capture.exists() else None

    def test_current_phone_family(self):
        self.assertEqual(self.capture('4.0.6-1'), (PACKAGE / 'legacy-4.0.6' / PATCH).read_bytes())

    def test_new_source_family(self):
        self.assertEqual(self.capture('4.5.0-3'), (PACKAGE / 'patches' / PATCH).read_bytes())

    def test_unsupported_family_stops_before_patch(self):
        self.assertIsNone(self.capture('4.6.0-1'))

    def test_old_flat_selection_negative(self):
        self.assertNotEqual(self.capture('4.0.6-1', wrong_family=True),
                            (PACKAGE / 'legacy-4.0.6' / PATCH).read_bytes())


unittest.main()
