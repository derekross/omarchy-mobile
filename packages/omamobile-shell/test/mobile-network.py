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

    def test_modem_switch(self):
        self.assertIsNone(mn.describe(True, None, CONF, False)['modem'])
        sw = dict(available=True, enabled=False, running=True, started=True, provisioned=True,
                  sleep_blocked=True, restart_needed=True, extra='x')
        want = dict(sw)
        del want['extra']
        self.assertEqual(mn.describe(True, state(), CONF, True, switch=sw)['modem'], want)
        # An older helper without "available": the page hides the switch.
        self.assertFalse(mn.describe(True, state(), CONF, True, switch=dict(enabled=True))['modem']['available'])

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
        self.switch = d / 'omamobile-modem-switch'
        self.switch.write_text('#!/bin/sh\n[ "$1" = status ] && echo \'{"available": true, "enabled": false, '
                               '"running": false, "started": false, "provisioned": true, "sleep_blocked": false, '
                               '"restart_needed": false}\'\n')
        self.switch.chmod(0o755)
        self.env = dict(os.environ, OMAMOBILE_SIT_RUN=str(d / 'run'), OMAMOBILE_SIT_CONFIG=str(d / 'modem-sit.conf'),
                        OMAMOBILE_SIT_CONFIG_HELPER=str(self.helper), OMAMOBILE_MM='none',
                        OMAMOBILE_MODEM_SWITCH=str(self.switch), PATH=str(d / 'bin'))
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
        self.assertEqual((v['modem']['enabled'], v['modem']['provisioned']), (False, True))
        self.switch.unlink()
        self.assertIsNone(json.loads(self.run_tool('status').stdout)['modem'])

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
        self.run_tool('modem', 'off')
        self.run_tool('modem', 'on')
        self.assertEqual(self.log.read_text().splitlines(), [
            'omamobile-sit data on',
            f'pkexec {self.helper} set roaming off',
            f'pkexec {self.helper} set apn internet.example',
            f'pkexec {self.helper} set attach_apn ims',
            f'pkexec {self.switch} off',
            f'pkexec {self.switch} on'])
        self.assertEqual(self.run_tool('data', 'maybe').returncode, 2)
        self.assertEqual(self.run_tool('modem', 'restart').returncode, 2)


def mm(**over):
    base = dict(state=8, failed=0, unlock=1, quality=(54, True), tech=1 << 14, registration=1,
                operator='Example', voice=True, sms=True, initial_apn='internet.example', bearer_apn='')
    base.update(over)
    return base


class ModemManager(unittest.TestCase):
    """Phones without omamobile-modem-sit: ModemManager and NetworkManager."""

    def test_registered_without_profile(self):
        v = mn.describe_mm(mm(), None)
        self.assertEqual((v['installed'], v['running'], v['carrier'], v['registration'], v['tech'], v['signal']),
                         (True, True, 'Example', 'home', 'LTE', 54))
        self.assertEqual(v['data'], dict(enabled=False, up=False, available=True))
        self.assertEqual((v['apn']['in_use'], v['apn']['source'], v['apn']['configured']),
                         ('internet.example', 'network', 'auto'))
        self.assertEqual(v['sim']['state'], 'ready')

    def test_connected_profile(self):
        profile = dict(uuid='u', autoconnect=True, apn='internet.example', home_only=True, active=True)
        v = mn.describe_mm(mm(state=11, registration=5, bearer_apn='internet.example'), profile)
        self.assertEqual(v['data'], dict(enabled=True, up=True, available=True))
        self.assertEqual((v['registration'], v['roaming']), ('roaming', dict(now=True, allowed=False)))
        self.assertEqual(v['apn']['configured'], 'auto')
        typed = dict(profile, apn='web.example')
        self.assertEqual(mn.describe_mm(mm(), typed)['apn']['configured'], 'web.example')

    def test_sim_states(self):
        self.assertEqual(mn.describe_mm(mm(state=-1, failed=2), None)['sim']['state'], 'absent')
        self.assertEqual(mn.describe_mm(mm(state=2, unlock=2), None)['sim']['state'], 'pin')
        self.assertEqual(mn.describe_mm(mm(state=2, unlock=4), None)['sim']['state'], 'puk')
        # PIN2 (fixed dialling) on a registered modem is no SIM problem
        self.assertEqual(mn.describe_mm(mm(state=8, unlock=3), None)['sim']['state'], 'ready')
        v = mn.describe_mm(mm(state=-1, failed=2), None)
        self.assertEqual((v['registration'], v['carrier'], v['tech']), ('unknown', '', ''))

    def test_tile(self):
        self.assertEqual(mn.mm_tile(None, None), ['data=none'])
        self.assertEqual(mn.mm_tile(mm(), None), ['data=off', 'data_signal=54', 'data_status=Example LTE'])
        self.assertEqual(mn.mm_tile(mm(operator='00101'), None), ['data=off', 'data_signal=54', 'data_status=LTE'])
        self.assertEqual(mn.mm_tile(mm(registration=2), None), ['data=off', 'data_signal=-1', 'data_status=No signal'])

    def test_commands(self):
        calls = []
        profile = dict(uuid='u1', autoconnect=False, apn='internet.example', home_only=False, active=True)

        class Done:
            returncode = 0
            stdout = ''

        def fake(*args, check=False):
            calls.append(list(args))
            return Done()
        saved = (mn.nmcli, mn.nm_profile)
        mn.nmcli, mn.nm_profile = fake, lambda: profile
        try:
            self.assertEqual(mn.mm_command(['data', 'on'], mm()), 0)
            self.assertEqual(mn.mm_command(['data', 'off'], mm()), 0)
            self.assertEqual(mn.mm_command(['roaming', 'off'], mm()), 0)
            self.assertEqual(mn.mm_command(['apn', 'auto'], mm()), 0)
            self.assertEqual(mn.mm_command(['attach-apn', 'ims'], mm()), 1)
        finally:
            mn.nmcli, mn.nm_profile = saved
        self.assertEqual(calls, [
            ['connection', 'modify', 'u1', 'connection.autoconnect', 'yes'], ['connection', 'up', 'u1'],
            ['connection', 'modify', 'u1', 'connection.autoconnect', 'no'], ['connection', 'down', 'u1'],
            ['connection', 'modify', 'u1', 'gsm.home-only', 'yes'],
            ['connection', 'modify', 'u1', 'gsm.apn', 'internet.example'], ['connection', 'up', 'u1']])

    def test_never_an_empty_apn_profile_from_auto(self):
        # ModemManager 1.24.2 crashed reconnecting on an empty APN: "auto"
        # is the network's APN
        calls = []

        class Done:
            returncode = 0
            stdout = ''
        saved = (mn.nmcli, mn.nm_profile)
        mn.nmcli = lambda *a, check=False: (calls.append(list(a)), Done())[1]
        mn.nm_profile = lambda: dict(uuid='u1', autoconnect=True, apn='x', home_only=False, active=False)
        try:
            mn.mm_command(['apn', ''], mm(initial_apn='internet.example'))
        finally:
            mn.nmcli, mn.nm_profile = saved
        self.assertEqual(calls, [['connection', 'modify', 'u1', 'gsm.apn', 'internet.example']])


class OptIn(unittest.TestCase):
    """The ModemManager path runs only where the device package opts in."""

    def test_off_without_the_file(self):
        def boom():
            raise AssertionError('ModemManager asked without the opt-in')
        saved = (mn.mm_snapshot, mn.MM_ENABLE, mn.installed)
        mn.mm_snapshot, mn.MM_ENABLE, mn.installed = boom, '/nonexistent/mobile-network-modemmanager', lambda: False
        try:
            import contextlib
            import io
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(mn.main(['tile']), 0)
            self.assertEqual(out.getvalue().strip(), 'data=none')
        finally:
            mn.mm_snapshot, mn.MM_ENABLE, mn.installed = saved


if __name__ == '__main__':
    unittest.main()
