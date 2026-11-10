# SPDX-License-Identifier: MIT
"""omamobile-mobile-network (the Mobile network page's backend) against
made-up sitd states and settings: the view it prints, "No modem" without
the stack, and that changes go to the right commands. Run by test/all."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
TOOL = HERE.parent / 'bin' / 'omamobile-mobile-network'
loader = importlib.machinery.SourceFileLoader('omamobile_mobile_network', str(TOOL))
spec = importlib.util.spec_from_loader('omamobile_mobile_network', loader)
mn = importlib.util.module_from_spec(spec)
loader.exec_module(mn)

CONF = dict(apn='auto', attach_apn='auto', roaming=True)


def state(**modem):
    base = dict(stage='running', registration='home', tech='LTE', operator='Example', plmn='00101',
                operator_name='Example', voice=True, sms=True, data=True,
                sim=dict(state='ready', pin_retries=3, puk_retries=10, pin_lock='off'),
                apn=dict(value='internet.example', source='carrier-database', attach='internet.example',
                         attach_source='same'), data_available=True)
    base.update(modem)
    return dict(modem=base, calls=[], sms=dict(unread=0))


class Describe(unittest.TestCase):
    def test_registered(self):
        v = mn.describe(True, state(), CONF, True)
        self.assertEqual((v['carrier'], v['registration'], v['tech'], v['signal']), ('Example', 'home', 'LTE', -1))
        self.assertEqual(v['data'], dict(enabled=True, up=True, available=True))
        self.assertEqual(v['apn'], dict(in_use='internet.example', source='carrier-database', configured='auto',
                                        attach_in_use='internet.example', attach_source='same',
                                        attach_configured='auto'))
        self.assertEqual(v['sim'], dict(state='ready', pin_lock='off'))
        self.assertEqual(v['roaming'], dict(now=False, allowed=True))

    def test_no_stack_and_not_running(self):
        self.assertFalse(mn.describe(False, None, CONF, False)['installed'])
        v = mn.describe(True, None, CONF, False)
        self.assertEqual((v['installed'], v['running']), (True, False))

    def test_signal_from_modemmanager_only_when_recent(self):
        self.assertEqual(mn.describe(True, state(), CONF, True, dict(SignalQuality=(70, True)))['signal'], 70)
        self.assertEqual(mn.describe(True, state(), CONF, True, dict(SignalQuality=(70, False)))['signal'], -1)

    def test_unregistered_shows_no_carrier_and_no_apn_means_unavailable(self):
        v = mn.describe(True, state(registration='searching', data=False, data_available=False,
                                    apn=dict(value='', source='none')), dict(apn='auto', attach_apn='auto', roaming=False), False)
        self.assertEqual((v['carrier'], v['tech'], v['data']['available'], v['roaming']['allowed']),
                         ('', '', False, False))

    def test_no_identifiers_in_the_view(self):
        text = json.dumps(mn.describe(True, state(), CONF, True))
        self.assertNotIn('00101', text)
        self.assertNotIn('retries', text)


class Cli(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        d = Path(self.dir.name)
        (d / 'run').mkdir()
        (d / 'bin').mkdir()
        self.log = d / 'log'
        for name in ('systemctl', 'pkexec', 'omamobile-sit'):
            fake = d / 'bin' / name
            fake.write_text(f'#!/bin/sh\necho "{name} $*" >> "{self.log}"\n'
                            + ('exit 1\n' if name == 'systemctl' else ''))
            fake.chmod(0o755)
        self.helper = d / 'omamobile-sit-config'
        self.helper.write_text('#!/bin/sh\n')
        self.helper.chmod(0o755)
        (d / 'modem-sit.conf').write_text('[network]\napn = internet.example\n[data]\nroaming = no\n')
        self.env = dict(os.environ, OMAMOBILE_SIT_RUN=str(d / 'run'), OMAMOBILE_SIT_CONFIG=str(d / 'modem-sit.conf'),
                        OMAMOBILE_SIT_CONFIG_HELPER=str(self.helper), OMAMOBILE_MM='none',
                        PATH=str(d / 'bin'))
        self.d = d

    def tearDown(self):
        self.dir.cleanup()

    def run_tool(self, *args):
        return subprocess.run([sys.executable, str(TOOL), *args], env=self.env, capture_output=True,
                              text=True, timeout=20)

    def test_status(self):
        (self.d / 'run' / 'state.json').write_text(json.dumps(state()))
        v = json.loads(self.run_tool('status').stdout)
        self.assertEqual((v['installed'], v['running'], v['data']['enabled']), (True, True, False))
        self.assertEqual((v['apn']['configured'], v['roaming']['allowed']), ('internet.example', False))

    def test_not_installed(self):
        self.helper.unlink()
        v = json.loads(self.run_tool('status').stdout)
        self.assertFalse(v['installed'])

    def test_changes(self):
        if os.geteuid() == 0:
            self.skipTest('runs the helper directly as root')
        self.run_tool('data', 'on')
        self.run_tool('roaming', 'off')
        self.run_tool('apn', 'internet.example')
        self.run_tool('attach-apn', 'ims')
        self.assertEqual(self.log.read_text().splitlines(), [
            'omamobile-sit data on',
            f'pkexec {self.helper} set roaming off',
            f'pkexec {self.helper} set apn internet.example',
            f'pkexec {self.helper} set attach_apn ims'])
        self.assertEqual(self.run_tool('data', 'maybe').returncode, 2)


if __name__ == '__main__':
    unittest.main()
