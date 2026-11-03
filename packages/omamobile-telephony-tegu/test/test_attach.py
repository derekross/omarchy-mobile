# SPDX-License-Identifier: MIT
"""The attended script with fake service/bus calls and private socket data."""
import contextlib
import copy
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

SCRIPT = Path(__file__).resolve().parents[1] / 'bin/omamobile-tegu-mmd-attach'
loader = importlib.machinery.SourceFileLoader('attach', str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
a = importlib.util.module_from_spec(spec)
loader.exec_module(a)


class SystemCheck(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        desc = self.root / 'usr/share/omamobile/device.conf'
        desc.parent.mkdir(parents=True)
        desc.write_text('CODENAME=tegu\n')
        ver = self.root / 'usr/share/omamobile/device-tegu/version'
        ver.parent.mkdir()
        ver.write_text('0.2.9\n')
        self.status = dict(modem=dict(present=True, sim=dict(state='ready'), radio='on',
                                     registration='home', ims='unregistered', data=False,
                                     operator='PRIVATE NETWORK'), calls=[], sms={'received': []})
        self.units = {
            a.SITD: dict(ActiveState='active', MainPID='123', FragmentPath='/usr/lib/systemd/system/' + a.SITD,
                         Requisite=a.MODEM, Requires='sysinit.target', Wants='', BindsTo='', NeedDaemonReload='no'),
            a.MODEM: dict(ActiveState='active', MainPID='122'),
            a.BRIDGE: dict(ActiveState='inactive', MainPID='0', FragmentPath='/usr/lib/systemd/system/' + a.BRIDGE,
                           Requisite=a.SITD, Requires='dbus.socket sysinit.target', Wants='', BindsTo='', NeedDaemonReload='no'),
            'ModemManager.service': dict(ActiveState='inactive', MainPID='0'),
        }
        self.owner = 'b false'
        self.commands = []
        for target, value in [('os.geteuid', lambda: 0), ('properties', lambda name: self.units[name]),
                              ('run', self.command), ('socket_status', lambda path: self.status)]:
            helper = patch.object(a.os, 'geteuid', value) if target == 'os.geteuid' else patch.object(a, target, value)
            helper.start()
            self.addCleanup(helper.stop)
        helper = patch.dict(a.os.environ, OMAMOBILE_TEGU_ROOT=str(self.root))
        helper.start()
        self.addCleanup(helper.stop)

    def command(self, args):
        self.commands.append(args)
        self.assertEqual(args[:3], ['busctl', '--system', 'call'])
        self.assertIn('NameHasOwner', args)
        return self.owner

    def refused(self):
        with self.assertRaises(a.Refused):
            a.system_check()

    def test_live_no_ims_no_bearer_passes_without_radio_actions(self):
        self.assertEqual(a.system_check(), {'sitd_pid': '123', 'modem_pid': '122'})
        self.assertEqual(len(self.commands), 1)
        self.assertNotIn('PRIVATE', json.dumps(a.system_check()))

    def test_wrong_board_and_non_root_refused(self):
        with patch.object(a.os, 'geteuid', return_value=1000):
            self.refused()
        (self.root / 'usr/share/omamobile/device.conf').write_text('CODENAME=cheetah\n')
        self.refused()

    def test_missing_or_inactive_ril_or_modem_refused(self):
        for unit in (a.SITD, a.MODEM):
            for field, value in [('ActiveState', 'inactive'), ('MainPID', '0')]:
                with self.subTest(unit=unit, field=field):
                    old = self.units[unit][field]
                    self.units[unit][field] = value
                    self.refused()
                    self.units[unit][field] = old

    def test_shadow_units_and_reload_pending_refused(self):
        for unit in (a.SITD, a.BRIDGE):
            for field, value in [('FragmentPath', '/etc/systemd/system/' + unit), ('NeedDaemonReload', 'yes')]:
                with self.subTest(unit=unit, field=field):
                    old = self.units[unit][field]
                    self.units[unit][field] = value
                    self.refused()
                    self.units[unit][field] = old

    def test_missing_policy_or_pulling_dependency_refused(self):
        for unit in (a.SITD, a.BRIDGE):
            for field, value in [('Requisite', ''), ('Requires', a.MODEM), ('Wants', a.SITD), ('BindsTo', a.MODEM)]:
                with self.subTest(unit=unit, field=field):
                    old = self.units[unit][field]
                    self.units[unit][field] = value
                    self.refused()
                    self.units[unit][field] = old

    def test_competing_bus_owner_or_real_manager_refused(self):
        self.owner = 'b true'
        self.refused()
        self.units[a.BRIDGE]['ActiveState'] = 'active'
        self.assertEqual(a.system_check()['sitd_pid'], '123')
        self.units['ModemManager.service']['ActiveState'] = 'activating'
        self.refused()

    def test_unready_registration_or_live_call_refused(self):
        good = copy.deepcopy(self.status)
        for key, value in [('sim', {'state': 'absent'}), ('radio', 'off'), ('registration', 'searching')]:
            self.status = copy.deepcopy(good)
            self.status['modem'][key] = value
            self.refused()
        self.status = copy.deepcopy(good)
        self.status['calls'] = [dict(state='active', number='PRIVATE NUMBER')]
        self.refused()

    def test_service_recovery_allows_live_calls_and_registration_loss(self):
        self.status['calls'] = [dict(state='active')]
        self.status['modem']['radio'] = 'off'
        self.status['modem']['registration'] = 'searching'
        self.status['modem']['sim'] = dict(state='absent')
        self.refused()
        self.assertEqual(a.system_check(require_ready=False)['sitd_pid'], '123')

    def test_stop_dependency_is_refused(self):
        self.units[a.BRIDGE]['Conflicts'] = 'ModemManager.service shutdown.target'
        self.refused()

    def test_malformed_rpc_is_refused_without_private_output(self):
        self.status = {'modem': None, 'calls': ['PRIVATE']}
        self.refused()
        self.status = dict(modem=dict(present=True, sim=None))
        self.refused()


class SocketRead(unittest.TestCase):
    def test_only_status_sent_and_refused_payload_hidden(self):
        fake = Mock()
        fake.__enter__ = Mock(return_value=fake)
        fake.__exit__ = Mock(return_value=False)
        fake.makefile.return_value = io.BytesIO(b'{"ok":true,"result":{"calls":[]}}\n')
        with patch.object(a.socket, 'socket', return_value=fake):
            self.assertEqual(a.socket_status('/private/socket'), {'calls': []})
        fake.sendall.assert_called_once_with(b'{"action":"status"}\n')
        for response in [b'{"ok":false,"error":"PRIVATE NUMBER"}\n', b'bad PRIVATE JSON\n', b'{}']:
            fake.makefile.return_value = io.BytesIO(response)
            with patch.object(a.socket, 'socket', return_value=fake), self.assertRaises(a.Refused) as error:
                a.socket_status('/private/socket')
            self.assertNotIn('PRIVATE', str(error.exception))


class Attended(unittest.TestCase):
    def setUp(self):
        self.commands = []
        self.identity = {'sitd_pid': '123', 'modem_pid': '122'}
        self.output = io.StringIO()
        self.output.isatty = lambda: True
        self.input = Mock()
        self.input.isatty.return_value = True
        helpers = [patch.object(a.os, 'geteuid', return_value=1000),
                   patch.object(a, 'root_check', return_value=self.identity),
                   patch.object(a, 'run', side_effect=self.command),
                   patch.object(a.sys, 'stdin', self.input), patch.object(a.sys, 'stdout', self.output),
                   patch.object(a.sys, 'stderr', new=io.StringIO()), patch('builtins.input', return_value='ATTACH')]
        for helper in helpers:
            helper.start()
            self.addCleanup(helper.stop)

    def command(self, args, **kwargs):
        self.commands.append(args)
        return 'loaded' if '--property=LoadState' in args else ''

    def mutations(self):
        return [cmd for cmd in self.commands if 'start' in cmd]

    def test_check_changes_nothing(self):
        self.assertEqual(a.main(['--check']), 0)
        self.assertFalse(self.mutations())

    def test_attach_starts_exactly_bridge_and_user_agent(self):
        for _ in range(2):
            self.assertEqual(a.main(['--attach']), 0)
        self.assertEqual(self.mutations(), [
            ['sudo', '--', 'systemctl', 'start', a.BRIDGE], ['systemctl', '--user', 'start', a.AGENT]] * 2)
        self.assertNotIn('restart', str(self.commands))
        self.assertNotIn('enable', str(self.commands))
        self.assertNotIn(a.MODEM, str(self.commands))
        self.assertNotIn(a.SITD, str(self.commands))

    def test_requires_terminal_and_explicit_confirmation(self):
        self.input.isatty.return_value = False
        self.assertEqual(a.main(['--attach']), 1)
        self.assertFalse(self.commands)
        self.input.isatty.return_value = True
        with patch('builtins.input', return_value='yes'):
            self.assertEqual(a.main(['--attach']), 1)
        self.assertFalse(self.mutations())

    def test_ril_change_or_preflight_failure_never_starts_services(self):
        with patch.object(a, 'root_check', side_effect=[self.identity, {'sitd_pid': '124', 'modem_pid': '122'}]):
            self.assertEqual(a.main(['--attach']), 1)
        self.assertFalse(self.mutations())
        with patch.object(a, 'root_check', side_effect=a.Refused('inactive')):
            self.assertEqual(a.main(['--attach']), 1)
        self.assertFalse(self.mutations())

    def test_agent_failure_never_recovers_modem_or_ril(self):
        def command(args, **kwargs):
            value = self.command(args, **kwargs)
            if args == ['systemctl', '--user', 'start', a.AGENT]:
                raise a.Refused('agent failed')
            return value
        with patch.object(a, 'run', side_effect=command):
            self.assertEqual(a.main(['--attach']), 1)
        self.assertEqual(self.mutations(), [['sudo', '--', 'systemctl', 'start', a.BRIDGE],
                                           ['systemctl', '--user', 'start', a.AGENT]])

    def test_refuses_root_and_missing_user_unit(self):
        with patch.object(a.os, 'geteuid', return_value=0):
            self.assertEqual(a.main(['--check']), 1)
        with patch.object(a, 'run', return_value='not-found'):
            self.assertEqual(a.main(['--check']), 1)
        self.assertFalse(self.mutations())


class UnitPolicy(unittest.TestCase):
    repo = Path(__file__).resolve().parents[3]

    def unit(self, path):
        fields = {}
        for line in path.read_text().splitlines():
            if '=' in line and not line.startswith('#'):
                key, value = line.split('=', 1)
                fields.setdefault(key, []).extend(value.split())
        return fields

    def test_effective_device_dependencies_and_readiness(self):
        base_path = self.repo / 'packages/omamobile-modem-sit/systemd/omamobile-sitd.service'
        if not base_path.exists():
            self.skipTest('device unit integration needs the repository')
        base = self.unit(base_path)
        self.assertNotIn('Requires', base)
        self.assertIn('omamobile-audio.service', base['After'])
        for dev in ('tegu', 'cheetah', 'raven'):
            policy = self.unit(self.repo / f'packages/omamobile-device-{dev}/vendor/systemd/system/omamobile-sitd.service.d/10-device-modem.conf')
            if dev == 'tegu':
                self.assertEqual(policy['Requisite'], [a.MODEM])
                for field in ('Requires', 'Wants', 'BindsTo'):
                    self.assertNotIn(field, policy)
                self.assertEqual(policy['ExecStartPre'], ['/usr/lib/omamobile-vendor/omamobile-modem-cp', 'state'])
                self.assertIn(a.MODEM, policy['After'])
            else:
                self.assertEqual(policy['Requires'], ['omamobile-modem.service'])
                self.assertEqual(policy['After'], ['omamobile-modem.service'])

    def test_bridge_dependency_cannot_start_ril_or_cp(self):
        base_path = self.repo / 'packages/omamobile-mmd/systemd/omamobile-mmd.service'
        if not base_path.exists():
            self.skipTest('bridge unit integration needs the repository')
        policy = self.unit(Path(__file__).resolve().parents[1] / 'systemd/10-tegu-attach.conf')
        base = self.unit(base_path)
        for fields in (base, policy):
            for key in ('Requires', 'Wants', 'BindsTo'):
                self.assertNotIn(key, fields)
        self.assertNotIn('Conflicts', base)
        self.assertEqual(policy['Requisite'], [a.SITD])
        self.assertEqual(policy['ExecStartPre'], ['/usr/bin/omamobile-tegu-mmd-attach', '--service-check'])

    def test_ril_requires_device_policy_and_dependency_fix(self):
        pkg = self.repo / 'packages/omamobile-modem-sit/PKGBUILD'
        if not pkg.exists():
            self.skipTest('package closure needs the repository')
        def array(path, name):
            return subprocess.run(['bash', '-c',
                'startdir=$(dirname "$1"); source "$1"; declare -p "$2"', '_', str(path), name],
                check=True, capture_output=True, text=True).stdout
        self.assertIn('omamobile-sitd-policy', array(pkg, 'depends'))
        modem = self.repo / 'packages/omamobile-modem/PKGBUILD'
        self.assertIn('omamobile-modem-policy', array(modem, 'depends'))
        self.assertNotIn('omamobile-device-cheetah', array(modem, 'depends'))
        for device in ('cheetah', 'raven', 'tegu'):
            provides = array(self.repo / f'packages/omamobile-device-{device}/PKGBUILD', 'provides')
            self.assertIn('omamobile-sitd-policy', provides)
            self.assertIn('omamobile-modem-policy', provides)


if __name__ == '__main__':
    unittest.main()
