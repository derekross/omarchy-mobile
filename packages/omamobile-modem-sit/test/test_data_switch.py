#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""omamobile-sit data on|off against a stand-in systemctl; no systemd, modem or radio access."""
import env  # noqa: F401  (paths and sys.path first)
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

CLI = pathlib.Path(__file__).resolve().parent.parent / 'bin' / 'omamobile-sit'
SYSTEMCTL = '''#!/bin/sh
echo "$*" >> "$FAKE_LOG"
[ "$1" = is-active ] || exit 0
cat "$FAKE_SITD"
[ "$(cat "$FAKE_SITD")" = active ]
'''


class DataSwitchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='omamobile-sit-data-switch-')
        self.dir = pathlib.Path(self.tmp.name)
        (self.dir / 'bin').mkdir()
        fake = self.dir / 'bin' / 'systemctl'
        fake.write_text(SYSTEMCTL)
        fake.chmod(0o755)
        self.log = self.dir / 'log'
        self.log.write_text('')
        self.env = dict(os.environ, PATH=f"{self.dir / 'bin'}:{os.environ['PATH']}",
                        FAKE_LOG=str(self.log), FAKE_SITD=str(self.dir / 'sitd'))

    def tearDown(self):
        self.tmp.cleanup()

    def data(self, want, sitd):
        (self.dir / 'sitd').write_text(sitd + '\n')
        result = subprocess.run([sys.executable, str(CLI), 'data', want], env=self.env,
                                capture_output=True, text=True, timeout=30)
        return result, self.log.read_text().splitlines()

    def test_on_starts_the_data_unit_while_sitd_runs(self):
        for state in ('active', 'activating'):
            self.log.write_text('')
            result, calls = self.data('on', state)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls, ['is-active omamobile-sitd.service', 'start omamobile-sit-data.service'])

    def test_on_is_refused_while_sitd_is_not_running(self):
        # Starting the data unit would start sitd again (Requires=), and a
        # second sitd start-up on the same CP isn't supported.
        for state in ('inactive', 'failed', 'deactivating'):
            self.log.write_text('')
            result, calls = self.data('on', state)
            self.assertEqual(result.returncode, 1)
            self.assertIn("the phone service isn't running this boot; restart the phone", result.stderr)
            self.assertEqual(calls, ['is-active omamobile-sitd.service'])

    def test_off_stops_the_data_unit_whatever_sitd_does(self):
        for state in ('active', 'inactive'):
            self.log.write_text('')
            result, calls = self.data('off', state)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(calls, ['stop omamobile-sit-data.service'])


if __name__ == '__main__':
    unittest.main()
