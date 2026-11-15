#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Offline negative tests for gates that protect actual handset operations."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import subprocess
import unittest
from unittest.mock import patch

P = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('revised', P / 'start.py')
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)


class Controls(unittest.TestCase):
    def test_graphics_environment_uses_current_unit_and_preserves_historical(self):
        text = (P / 'graphics-env').read_text()
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            (p / 'enable').touch()
            source = p / 'env'
            source.write_text(text.replace('/etc/omamobile/bluejay-revised-enable', str(p / 'enable'))
                                  .replace('/dev/dri/renderD128', '/dev/null'))
            for release, active, expected in [(s.HISTORICAL, 0, 'sentinel'),
                                              (s.RELEASE, 1, 'llvmpipe'),
                                              (s.RELEASE, 0, 'panfrost')]:
                script = ('uname() { printf "%s\\n" "' + release + '"; }; '
                          'systemctl() { return ' + str(active) + '; }; '
                          'GALLIUM_DRIVER=sentinel; . "$1"; printf "%s" "$GALLIUM_DRIVER"')
                with self.subTest(release=release, active=active):
                    got = subprocess.check_output(['sh', '-c', script, 'test', str(source)], text=True)
                    self.assertEqual(got, expected)

    def test_only_console_rewrite_is_normalized(self):
        expected = ('console=tty0 panic=10 clk_ignore_unused pd_ignore_unused '
                    'systemd.mask=sleep.target systemd.mask=omamobile-boot-success.service '
                    'modprobe.blacklist=salixp,panfrost bluejay.gpu_evening=1')
        actual = expected.replace('console=tty0', 'console=null')
        actual += ' clk_ignore_unused pd_ignore_unused'
        self.assertTrue(s.bootargs_ok(actual + ' androidboot.hardware=bluejay', expected))
        for word in expected.split():
            got = actual.replace(word.replace('console=tty0', 'console=null'), '')
            with self.subTest(missing=word), self.assertRaises(RuntimeError):
                s.bootargs_ok(got, expected)
        for extra in ('console=tty0', 'console=ttyS0', 'panic=0', 'panic=10',
                      'systemd.mask=other.service', 'modprobe.blacklist=salixp',
                      'clk_ignore_unused', 'pd_ignore_unused'):
            with self.subTest(extra=extra), self.assertRaises(RuntimeError):
                s.bootargs_ok(actual + ' ' + extra, expected)

    def test_vendor_and_DT_hold_multiplicity_is_exact(self):
        expected = 'console=tty0 panic=10 clk_ignore_unused pd_ignore_unused'
        actual = 'console=null panic=10 clk_ignore_unused pd_ignore_unused'
        with self.assertRaises(RuntimeError):
            s.bootargs_ok(actual, expected)
        self.assertTrue(s.bootargs_ok(actual + ' clk_ignore_unused pd_ignore_unused', expected))
        for extra in ('clk_ignore_unused', 'pd_ignore_unused'):
            with self.subTest(extra=extra), self.assertRaises(RuntimeError):
                s.bootargs_ok(actual + ' clk_ignore_unused pd_ignore_unused ' + extra, expected)

    def fixture(self):
        args = ('console=tty0 panic=10 clk_ignore_unused pd_ignore_unused rdinit=/init '
                'mem_sleep_default=s2idle omamobile.noresize systemd.unit=multi-user.target '
                'bluejay.gpu_evening=1 modprobe.blacklist=' + ','.join(sorted(s.HELD_MODULES)))
        args += ' ' + ' '.join('systemd.mask=' + name for name in sorted(s.REQUIRED_MASKS))
        return dict(source=s.SOURCE, release=s.RELEASE, serial='FAKEONLY',
                    host_logging_required=True,
                    bootargs=args, masked_units=sorted(s.REQUIRED_MASKS),
                    root_marker='/var/lib/omamobile/root-boot-pending',
                    image_hashes={n: 'a' * 64 for n in ('boot_b', 'vendor_boot_b', 'dtbo_b')},
                    protected_hashes={n: 'b' * 64 for n in ('efs', 'efs_backup',
                        'modem_userdata', 'persist', 'modem_a', 'modem_b', 'boot_a',
                        'vendor_boot_a', 'dtbo_a')},
                    devinfo_hashes=['c' * 64], dt_properties=[['soc', 'status', '00']],
                    firmware={'brcm/test': 'd' * 64})

    def test_identity_policy_and_complete_hash_inventory(self):
        c = self.fixture()
        self.assertEqual(s.validate_profile(c), c)
        for key, wrong in {'source': 'other', 'release': s.HISTORICAL,
                           'serial': '', 'host_logging_required': False,
                           'root_marker': '/var/lib/omamobile/bluejay-root-pending',
                           'masked_units': [], 'bootargs': 'console=tty0',
                           'image_hashes': {}, 'protected_hashes': {},
                           'devinfo_hashes': [], 'dt_properties': [], 'firmware': {}}.items():
            d = copy.deepcopy(c)
            d[key] = wrong
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                s.validate_profile(d)

    def test_module_parent_ownership_refuses_before_loading_or_hash_read(self):
        c = {'modules': {'test': {'path': 'kernel/drivers/test.ko', 'sha256': 'a' * 64}}}
        with patch.object(s, 'secure', side_effect=[None, RuntimeError('unsafe parent')]) as secure, \
                patch.object(s, 'sha') as digest, patch.object(s, 'cmd') as command:
            with self.assertRaisesRegex(RuntimeError, 'unsafe parent'):
                s.module(c, 'test')
            self.assertEqual(secure.call_args.kwargs, {'directory': True})
            digest.assert_not_called()
            command.assert_not_called()

    def test_path_traversal_is_rejected(self):
        for key, value in [('firmware', {'/outside': 'a' * 64}),
                           ('firmware', {'brcm/../../outside': 'a' * 64}),
                           ('dt_properties', [['/outside', 'value', '00']]),
                           ('dt_properties', [['soc/../..', 'value', '00']]),
                           ('dt_properties', [['soc', '../value', '00']])]:
            c = self.fixture()
            c[key] = value
            with self.subTest(value=value), self.assertRaises(RuntimeError):
                s.validate_profile(c)

    def test_same_boot_stale_host_receipt_refuses(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            with patch.object(s, 'RUN', p), patch.object(s, 'secure'), \
                    patch.object(s, 'boot', return_value='CURRENT'):
                for record in ({'boot_id': 'OLD', 'kernel_stream_proven': True},
                               {'boot_id': 'CURRENT', 'kernel_stream_proven': False}):
                    (p / 'host-log.json').write_text(json.dumps(record))
                    with self.assertRaises(RuntimeError):
                        s.check_host()
                (p / 'host-log.json').write_text(json.dumps(
                    {'boot_id': 'CURRENT', 'kernel_stream_proven': True}))
                s.check_host()

    def test_attempt_receipt_cannot_be_overwritten(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'attempt'
            s.save(p, {'first': True})
            with self.assertRaises(FileExistsError):
                s.save(p, {'second': True})
            self.assertEqual(json.loads(p.read_text()), {'first': True})

    def test_held_stage_refuses_before_any_hardware_or_journal_command(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            (p / 'gpu.pending').write_text('old failure')
            with patch.object(s, 'profile', return_value={}), \
                    patch.object(s, 'STATE', p), patch.object(s, 'RUN', p), \
                    patch.object(s, 'LOG', p), patch.object(s, 'secure'), \
                    patch.object(s, 'common') as common, patch.object(s, 'cmd') as command:
                with self.assertRaisesRegex(RuntimeError, 'previous attempt held'):
                    s.run('gpu')
                common.assert_not_called()
                command.assert_not_called()

    def test_journal_retains_early_proof_not_present_in_live_ring(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            full = '\n'.join(s.TOUCH_PROOFS) + '\nlate message'
            with patch.object(s, 'LOG', p), patch.object(s, 'secure'), \
                    patch.object(s, 'boot', return_value='CURRENT'), \
                    patch.object(s, 'cmd', side_effect=['', full]) as command:
                self.assertEqual(s.journal('stage-before'), full)
                self.assertIn('chip id 36 48', (p / 'CURRENT/stage-before.kernel.txt').read_text())
                self.assertEqual(command.call_args.args[:3], ('journalctl', '-k', '-b'))

    def test_failed_probe_keeps_marker_and_refuses_second_attempt(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            cpu = p / 'cpu'
            cpu.mkdir()
            (cpu / 'driver_override').write_text('')
            modules = p / 'modules'
            modules.write_text('')
            real_path = Path

            def fixture_path(value):
                if value == '/sys/bus/platform/devices/cpufreq-dt':
                    return cpu
                if value == '/proc/modules':
                    return modules
                return real_path(value)

            c = {'root_marker': str(p / 'root-marker')}
            with patch.object(s, 'profile', return_value=c), \
                    patch.object(s, 'STATE', p / 'state'), patch.object(s, 'RUN', p / 'run'), \
                    patch.object(s, 'LOG', p / 'log'), patch.object(s, 'secure'), \
                    patch.object(s, 'common', return_value={'boot_id': 'CURRENT'}), \
                    patch.object(s, 'journal', return_value='full boot log'), \
                    patch.object(s, 'receipt'), patch.object(s, 'check_host'), \
                    patch.object(s, 'Path', side_effect=fixture_path), \
                    patch.object(s, 'module', return_value=p / 'module'), \
                    patch.object(s, 'load', side_effect=RuntimeError('probe failed')) as load:
                with self.assertRaisesRegex(RuntimeError, 'probe failed'):
                    s.run('gpu')
                self.assertTrue((p / 'state/gpu.pending').exists())
                self.assertFalse((p / 'run/gpu.json').exists())
                with self.assertRaisesRegex(RuntimeError, 'previous attempt held'):
                    s.run('gpu')
                self.assertEqual(load.call_count, 1)

    def test_fault_journal_is_preserved_even_on_refusal(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            with patch.object(s, 'LOG', p), patch.object(s, 'secure'), \
                    patch.object(s, 'boot', return_value='CURRENT'), \
                    patch.object(s, 'cmd', side_effect=['', 'Oops: test fault']):
                with self.assertRaisesRegex(RuntimeError, 'fault'):
                    s.journal('failure')
                self.assertIn('Oops:', (p / 'CURRENT/failure.kernel.txt').read_text())

    def test_missing_host_times_out_without_hardware_or_reboot(self):
        with tempfile.TemporaryDirectory() as d:
            with patch.object(s, 'RUN', Path(d)), patch.object(s, 'receipt'), \
                    patch.object(s.time, 'sleep'), patch.object(s, 'cmd') as command, \
                    patch.object(s, 'acknowledge') as ack:
                with self.assertRaisesRegex(RuntimeError, 'hardware held'):
                    s.wait_host()
                command.assert_not_called()
                ack.assert_not_called()

    def test_units_do_not_reboot_or_retry_on_failure(self):
        units = list((P / 'units').glob('*.service'))
        self.assertEqual(len(units), 8)
        for path in units:
            text = path.read_text()
            with self.subTest(unit=path.name):
                self.assertIn('Restart=no', text)
                self.assertIn('TimeoutStartSec=', text)
                self.assertIn('TimeoutStopSec=', text)
                self.assertIn('ConditionPathExists=/etc/omamobile/bluejay-revised-enable', text)
                self.assertNotIn('FailureAction=', text)
                self.assertNotIn('reboot', text)
        text = (P / 'start.py').read_text()
        self.assertNotIn("cmd('rmmod'", text)
        self.assertNotIn("cmd('modprobe'", text)
        self.assertNotIn('reboot-force', text)


if __name__ == '__main__':
    unittest.main()
