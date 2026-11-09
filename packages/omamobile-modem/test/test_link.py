# SPDX-License-Identifier: MIT
"""Run the starter's link checks with synthetic sysfs and inert module loads."""
from pathlib import Path
import re
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
        loop = re.search(r'for entry in "\$\{LINK_MODULES\[@\]\}"; do\n  read -r -a words <<< "\$entry"\n  modprobe "\$\{words\[@\]\}"\ndone', SOURCE).group()
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


if __name__ == '__main__':
    unittest.main()
