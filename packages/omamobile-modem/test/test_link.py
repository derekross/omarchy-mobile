# SPDX-License-Identifier: MIT
"""Run the starter's link checks with synthetic sysfs and inert module loads."""
from pathlib import Path
import re
import os
import subprocess
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'lib/omamobile-modem-start').read_text()


class LinkTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.function = re.search(r'^link_param_ok\(\) \{\n.*?^\}', SOURCE, re.M | re.S).group()
        self.function = self.function.replace('/sys/module/', str(self.root) + '/')

    def run_value(self, value, wanted):
        parameter = self.root / 'test/parameters/flag'
        parameter.parent.mkdir(parents=True, exist_ok=True)
        if value is not None:
            parameter.write_text(value + '\n')
        return subprocess.run(['bash', '-c', 'set -euo pipefail\n' + self.function +
                               '\nlink_param_ok test flag=' + wanted], capture_output=True).returncode

    def test_missing_parameter_refuses(self):
        self.assertNotEqual(self.run_value(None, '1'), 0)

    def test_boolean_and_literal_values(self):
        for value, wanted in [('Y', '1'), ('N', '0'), ('1', '1'), ('0', '0'), ('42', '42')]:
            self.assertEqual(self.run_value(value, wanted), 0)

    def test_mismatched_values_refuse(self):
        for value, wanted in [('N', '1'), ('Y', '0'), ('unknown', '1')]:
            self.assertNotEqual(self.run_value(value, wanted), 0)

    def test_device_modules_load_in_order_with_arguments(self):
        loop = re.search(r'for entry in "\$\{LINK_MODULES\[@\]\}"; do\n  read -r -a words <<< "\$entry"\n  modprobe "\$\{words\[@\]\}" \|\| refuse "Off: \$\{words\[0\]\} didn\'t load"\ndone', SOURCE).group()
        script = ('LINK_MODULES=("first allow_hw=1" "second cpif=1")\n'
                  'modprobe() { printf "%s " "$@"; printf "\\n"; }\n' + loop)
        result = subprocess.run(['bash', '-c', script], text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout, 'first allow_hw=1 \nsecond cpif=1 \n')

    def test_default_keeps_existing_gs201_parameters(self):
        self.assertIn('LINK_MODULES=("pcie-gs201-cp allow_hw=1")', SOURCE)

    def test_loaded_module_mismatch_refuses_before_loading(self):
        block = SOURCE[SOURCE.index('link_param_ok() {'):SOURCE.index('# The sleep inhibitor before the drivers:')]
        block = block.replace('/sys/module/', str(self.root) + '/')
        parameter = self.root / 'second/parameters/cpif'
        parameter.parent.mkdir(parents=True)
        for value in [None, 'N', 'Y']:
            if value is not None:
                parameter.write_text(value + '\n')
            script = ('set -euo pipefail\nLINK_MODULES=("first allow_hw=1" "second cpif=1")\n'
                      'say() { :; }; refuse() { exit 7; }\n' + block + '\necho load-reached\n')
            result = subprocess.run(['bash', '-c', script], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0 if value == 'Y' else 7)
            self.assertEqual('load-reached' in result.stdout, value == 'Y')

    def run_starter(self, config, loaded=None, fail_module=None, inhibitor=False):
        """Run actual starter with only paths redirected and inert external tools."""
        config_path = self.root / 'link.conf'
        if config is not None:
            if isinstance(config, bytes):
                config_path.write_bytes(config)
            else:
                config_path.write_text(config)
        vendor = self.root / 'vendor'
        vendor.mkdir()
        profile = vendor / 'omamobile-vendor-chroot'
        profile.write_text('#!/bin/bash\necho profile-$2 >> "$TRACE"\nexit 1\n')
        profile.chmod(0o700)
        sysfs = self.root / 'sys'
        sysfs.mkdir()
        if loaded is not None:
            parameter = sysfs / 'second/parameters/cpif'
            parameter.parent.mkdir(parents=True)
            if loaded != 'missing':
                parameter.write_text(loaded + '\n')
        tools = self.root / 'bin'
        tools.mkdir()
        for name, body in {
            'systemd-inhibit': 'echo inhibitor >> "$TRACE"; echo "omamobile-modem held"',
            'sync': ':',
            'modprobe': 'test -f "$OMAMOBILE_MODEM_LATCH" || exit 23; echo "load:$*" >> "$TRACE"; '
                        '[[ $1 != "${FAIL_MODULE:-}" ]] || exit 1; mkdir -p "$SYSMODULE/${1//-/_}"',
            'systemctl': 'case $1 in is-active) test -e "$INHIBIT_ACTIVE";; *) echo "systemctl:$*" >> "$TRACE";; esac',
        }.items():
            tool = tools / name
            tool.write_text('#!/bin/bash\n' + body + '\n')
            tool.chmod(0o700)
        provision = self.root / 'provisioned'
        provision.touch()
        starter = self.root / 'starter'
        starter.write_text(SOURCE.replace('LIB=/usr/lib/omamobile-vendor',
                           'LIB=' + str(vendor)).replace(
                           'LINK_CONFIG=/usr/lib/omamobile-modem/link.conf',
                           'LINK_CONFIG=' + str(config_path)).replace(
                           '/sys/module/', str(sysfs) + '/'))
        trace = self.root / 'trace'
        env = os.environ.copy()
        env.update(PATH=str(tools) + ':' + env['PATH'], TRACE=str(trace),
                   OMAMOBILE_MODEM_LATCH=str(self.root / 'latch'),
                   OMAMOBILE_MODEM_UP_MARK=str(self.root / 'up'),
                   OMAMOBILE_MODEM_HOLD=str(self.root / 'hold'),
                   OMAMOBILE_MODEM_REFUSED=str(self.root / 'refused'),
                   OMAMOBILE_MODEM_CHROOT=str(provision),
                   OMAMOBILE_MODEM_NV_SUMS=str(provision),
                   OMAMOBILE_MODEM_PROPS=str(provision))
        modules = self.root / 'loaded'
        modules.mkdir()
        if inhibitor:
            (self.root / 'inhibit-active').touch()
        env.update(OMAMOBILE_MODEM_SYSMODULE=str(modules), SYSMODULE=str(modules),
                   OMAMOBILE_MODEM_SYSTEMCTL=str(tools / 'systemctl'),
                   INHIBIT_ACTIVE=str(self.root / 'inhibit-active'),
                   FAIL_MODULE=fail_module or '')
        env.pop('OMAMOBILE_MODEM_TEST_STOP_AFTER_CHECKS', None)
        result = subprocess.run(['bash', str(starter)], env=env,
                                capture_output=True, text=True, timeout=5)
        return result, trace.read_text().splitlines() if trace.exists() else []

    def test_data_list_reaches_inhibitor_then_ordered_loads_with_latch(self):
        result, trace = self.run_starter('# device list\nfirst allow_hw=1\nsecond cpif=1', 'Y')
        self.assertEqual(result.returncode, 1)  # inert profile check deliberately refuses
        self.assertEqual(trace, ['inhibitor', 'inhibitor', 'load:first allow_hw=1',
                                'load:second cpif=1', 'load:shm_ipc', 'load:cpif', 'profile-check'])

    def test_first_module_failing_refuses_and_releases_the_sleep_block(self):
        result, trace = self.run_starter('first allow_hw=1\nsecond cpif=1\n', 'Y',
                                         fail_module='first', inhibitor=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(trace, ['inhibitor', 'inhibitor', 'load:first allow_hw=1',
                                 'systemctl:kill omamobile-modem-inhibit.service'])
        self.assertEqual((self.root / 'refused').read_text().strip(), "Off: first didn't load")
        self.assertTrue((self.root / 'latch').exists())

    def test_later_module_failing_keeps_the_sleep_block(self):
        # Only first is loaded, a module known by its name in link.conf alone.
        result, trace = self.run_starter('first allow_hw=1\nsecond cpif=1\n', 'Y',
                                         fail_module='second', inhibitor=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(trace, ['inhibitor', 'inhibitor', 'load:first allow_hw=1',
                                 'load:second cpif=1'])
        self.assertEqual((self.root / 'refused').read_text().strip(), "Off: second didn't load")

    def test_no_config_preserves_real_default_load(self):
        result, trace = self.run_starter(None)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(trace[2], 'load:pcie-gs201-cp allow_hw=1')

    def test_data_substitution_refuses_without_executing_marker(self):
        marker = self.root / 'injected'
        result, trace = self.run_starter('first allow_hw=$(touch ' + str(marker) + ')\n')
        self.assertFalse(marker.exists())
        self.assertEqual(result.returncode, 1)
        self.assertEqual(trace, [])
        self.assertFalse((self.root / 'latch').exists())
        self.assertEqual((self.root / 'refused').read_text().strip(),
                         'Off: invalid link configuration')

    def assert_binary_config_refused(self, raw):
        result, trace = self.run_starter(raw)
        self.assertEqual(trace, [])
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.root / 'latch').exists())
        self.assertEqual((self.root / 'refused').read_text().strip(),
                         'Off: invalid link configuration')

    def test_nul_inside_module_cannot_normalize_to_valid_load(self):
        self.assert_binary_config_refused(b'fi\x00rst allow_hw=1\n')

    def test_nul_inside_parameter_cannot_normalize_to_valid_load(self):
        self.assert_binary_config_refused(b'first allow_hw=\x001\n')

    def test_nul_only_configuration_is_invalid(self):
        self.assert_binary_config_refused(b'\x00')

    def test_invalid_data_cannot_override_guards(self):
        # Execute the actual parser once per hostile data sample, never source it.
        function = re.search(r'^read_link_config\(\) \{\n.*?^\}', SOURCE, re.M | re.S).group()
        for text in ['MARK=/wrong', 'HOLD=/wrong', 'refuse() { :; }',
                     'first a=`true`', 'first a="1"', '-r first',
                     'first a=1; true', 'first a=', 'first ../a=1',
                     'first a=1 # inline', '', '# comment only\n']:
            path = self.root / 'invalid.conf'
            path.write_text(text)
            result = subprocess.run(['bash', '-c',
                'set -euo pipefail\nrefuse() { exit 7; }\n' + function +
                '\nread_link_config "$1"\necho accepted', 'test', str(path)],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 7, text)
            self.assertNotIn('accepted', result.stdout)

    def test_full_starter_loaded_parameter_refuses_before_inhibitor_or_latch(self):
        result, trace = self.run_starter('first allow_hw=1\nsecond cpif=1\n', 'missing')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(trace, [])
        self.assertFalse((self.root / 'latch').exists())
        self.assertEqual((self.root / 'refused').read_text().strip(), 'Off: reboot needed')

    def test_parser_accepts_only_named_module_arguments_and_refuses_symlink(self):
        function = re.search(r'^read_link_config\(\) \{\n.*?^\}', SOURCE, re.M | re.S).group()
        path = self.root / 'valid.conf'
        path.write_text('first\nsecond\tflag=1,2 value=a/b:c+_-.\n')
        script = ('set -euo pipefail\nrefuse() { exit 7; }\n' + function +
                  '\nread_link_config "$1"\nprintf "%s\\n" "${LINK_MODULES[@]}"')
        result = subprocess.run(['bash', '-c', script, 'test', str(path)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.splitlines(), ['first', 'second\tflag=1,2 value=a/b:c+_-.'])
        link = self.root / 'alias.conf'
        link.symlink_to(path)
        result = subprocess.run(['bash', '-c', script, 'test', str(link)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 7)

    def test_config_read_precedes_parameter_check_inhibitor_and_latch(self):
        self.assertLess(SOURCE.index('read_link_config "$LINK_CONFIG"'),
                        SOURCE.index('link_param_ok() {'))
        self.assertLess(SOURCE.index('link_param_ok() {'),
                        SOURCE.index('# The sleep inhibitor before the drivers:'))
        self.assertLess(SOURCE.index('# The sleep inhibitor before the drivers:'),
                        SOURCE.index("printf '%s boot %s"))


if __name__ == '__main__':
    unittest.main()
