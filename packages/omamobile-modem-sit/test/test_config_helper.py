# SPDX-License-Identifier: MIT
"""omamobile-sit-config (the Mobile network page's root helper) and data
roaming in omamobile-sit-data."""
import env  # noqa: F401  (paths and sys.path first)
import configparser
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import data_network

HERE = Path(__file__).resolve().parent
HELPER = HERE.parent / 'lib' / 'omamobile-sit-config'
SHIPPED = HERE.parent / 'etc' / 'omamobile' / 'modem-sit.conf'


class ConfigHelperTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.conf = Path(self.dir.name) / 'modem-sit.conf'
        self.conf.write_text(SHIPPED.read_text())

    def tearDown(self):
        self.dir.cleanup()

    def run_helper(self, *args):
        return subprocess.run([sys.executable, str(HELPER), *args], capture_output=True, text=True,
                              env=dict(os.environ, OMAMOBILE_SIT_CONFIG=str(self.conf)), timeout=20)

    def parsed(self):
        parser = configparser.ConfigParser(interpolation=None)
        parser.read(self.conf)
        return parser

    def test_set_apn_keeps_comments_and_other_settings(self):
        before = self.conf.read_text()
        result = self.run_helper('set', 'apn', 'internet.example')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), dict(apn='internet.example', attach_apn='auto', roaming=True))
        after = self.conf.read_text()
        self.assertEqual(self.parsed()['network']['apn'], 'internet.example')
        self.assertEqual(self.parsed()['network']['ims_apn'], 'auto')
        # One line changed; every comment kept.
        changed = [(a, b) for a, b in zip(before.splitlines(), after.splitlines()) if a != b]
        self.assertEqual(changed, [('apn = auto', 'apn = internet.example')])
        self.assertEqual(oct(self.conf.stat().st_mode & 0o777), '0o644')
        self.assertEqual(self.run_helper('set', 'attach_apn', 'ims').returncode, 0)
        self.assertEqual(self.parsed()['network']['attach_apn'], 'ims')
        self.run_helper('set', 'apn', 'AUTO')
        self.assertEqual(self.parsed()['network']['apn'], 'auto')

    def test_roaming(self):
        self.assertEqual(self.run_helper('set', 'roaming', 'off').returncode, 0)
        self.assertEqual(self.parsed()['data']['roaming'], 'no')
        self.assertEqual(json.loads(self.run_helper('get').stdout)['roaming'], False)
        self.run_helper('set', 'roaming', 'on')
        self.assertEqual(self.parsed()['data']['roaming'], 'yes')

    def test_refuses_anything_but_a_plain_value(self):
        before = self.conf.read_text()
        for args in (('set', 'apn', 'bad apn'), ('set', 'apn', 'x\n[control]\ngroup = users'),
                     ('set', 'apn', 'a' * 100), ('set', 'apn', ''), ('set', 'roaming', 'maybe'),
                     ('set', 'group', 'users'), ('set', 'apn'), ()):
            self.assertNotEqual(self.run_helper(*args).returncode, 0, args)
        self.assertEqual(self.conf.read_text(), before)

    def test_old_file_without_the_keys(self):
        self.conf.write_text('[network]\nip_type = ipv4v6\n[audio]\ncard = none\n')
        self.run_helper('set', 'apn', 'internet.example')
        self.run_helper('set', 'roaming', 'off')
        parser = self.parsed()
        self.assertEqual((parser['network']['apn'], parser['data']['roaming'], parser['audio']['card']),
                         ('internet.example', 'no', 'none'))


class RoamingTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.conf = Path(self.dir.name) / 'modem-sit.conf'
        self.state = Path(self.dir.name) / 'state.json'

    def tearDown(self):
        self.dir.cleanup()

    def blocked(self, roaming, registration):
        self.conf.write_text(f'[data]\nroaming = {roaming}\n')
        self.state.write_text(json.dumps(dict(modem=dict(registration=registration))))
        return data_network.roaming_blocked(str(self.conf), str(self.state))

    def test_only_roaming_with_roaming_off_blocks(self):
        self.assertTrue(self.blocked('no', 'roaming'))
        self.assertFalse(self.blocked('no', 'home'))
        self.assertFalse(self.blocked('yes', 'roaming'))
        self.assertFalse(self.blocked('maybe', 'roaming'))

    def test_missing_state_does_not_block(self):
        self.conf.write_text('[data]\nroaming = no\n')
        self.assertFalse(data_network.roaming_blocked(str(self.conf), str(self.state)))


if __name__ == '__main__':
    unittest.main()
