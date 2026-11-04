# SPDX-License-Identifier: MIT
"""Have systemd itself validate the three composed unit policies offline."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(shutil.which('systemd-analyze'), 'systemd-analyze not installed')
class Units(unittest.TestCase):
    def test_composed_units_verify_for_each_device(self):
        repo = Path(__file__).resolve().parents[3]
        packages = repo / 'packages'
        if not (packages / 'omamobile-mmd').exists():
            self.skipTest('composed unit test needs the repository')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            units = root / 'usr/lib/systemd/system'
            units.mkdir(parents=True)
            for pkg, name in [('omamobile-modem-sit', 'omamobile-sitd'), ('omamobile-mmd', 'omamobile-mmd')]:
                shutil.copy2(packages / pkg / f'systemd/{name}.service', units / f'{name}.service')
            # Stubs satisfy references only; verify never starts them.
            for name in ['basic', 'sysinit', 'shutdown', 'sockets', 'multi-user', 'slices']:
                (units / f'{name}.target').write_text('[Unit]\nDescription=Fixture\n')
            (units / 'system.slice').write_text('[Unit]\nDescription=Fixture slice\n')
            for name in ['omamobile-modem', 'omamobile-tegu-modem', 'omamobile-audio',
                         'omamobile-aoc', 'omamobile-tegu-aoc', 'dbus']:
                (units / f'{name}.service').write_text('[Service]\nExecStart=/bin/true\n')
            (units / 'dbus.socket').write_text('[Socket]\nListenStream=/run/fixture-bus\n')
            for name in ['bin/true', 'usr/bin/omamobile-sitd', 'usr/bin/omamobile-mmd',
                         'usr/bin/omamobile-tegu-mmd-attach', 'usr/lib/omamobile-vendor/omamobile-modem-cp']:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('fixture')
                path.chmod(0o755)
            drop = units / 'omamobile-sitd.service.d'
            drop.mkdir()
            bridge = units / 'omamobile-mmd.service.d'
            bridge.mkdir()
            for device in ['cheetah', 'raven', 'tegu']:
                shutil.copy2(packages / f'omamobile-device-{device}/vendor/systemd/system/omamobile-sitd.service.d/10-device-modem.conf',
                             drop / '10-device-modem.conf')
                if device == 'tegu':
                    shutil.copy2(packages / 'omamobile-telephony-tegu/systemd/10-tegu-attach.conf', bridge / '10-tegu-attach.conf')
                result = subprocess.run(['systemd-analyze', '--root', directory, '--man=no', 'verify',
                                         'omamobile-sitd.service', 'omamobile-mmd.service'],
                                        capture_output=True, text=True)
                if result.returncode and 'Operation not permitted' in result.stderr:
                    self.skipTest('local sandbox blocks systemd verification sockets')
                self.assertEqual(result.returncode, 0, f'{device}: {result.stdout}{result.stderr}')
