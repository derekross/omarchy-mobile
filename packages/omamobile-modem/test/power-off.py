#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""omamobile-modem-cp power-off without a modem: 0 only when the boot device
itself reported OFFLINE (the profile's stop witness rests on it); a missing or
vanishing device is unconfirmed, and allow_hw is put back either way."""
import importlib.machinery
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

cp = importlib.machinery.SourceFileLoader('modem_cp', 'lib/omamobile-modem-cp').load_module()


class PowerOff(unittest.TestCase):
    def test_missing_device_is_not_offline(self):
        with patch.object(cp, 'ioctl', side_effect=FileNotFoundError('missing')):
            self.assertEqual(cp.state(), 0)  # state and watch keep reading a missing device as OFFLINE
            self.assertEqual(cp.power_off(), 1)

    def test_already_offline(self):
        with patch.object(cp, 'ioctl', return_value=0) as ioctl:
            self.assertEqual(cp.power_off(), 0)
            self.assertEqual(ioctl.call_count, 1)

    def test_online_then_offline(self):
        with tempfile.TemporaryDirectory() as directory:
            allow = Path(directory) / 'allow'; allow.write_text('N')
            with patch.object(cp, 'ALLOW', allow), patch.object(cp, 'ioctl', side_effect=[4, 0, 0]):
                self.assertEqual(cp.power_off(), 0)
            self.assertEqual(allow.read_text(), 'N')

    def test_device_disappearing_after_request_fails_and_restores_allow(self):
        with tempfile.TemporaryDirectory() as directory:
            allow = Path(directory) / 'allow'; allow.write_text('N')
            with patch.object(cp, 'ALLOW', allow), patch.object(cp, 'ioctl', side_effect=[4, 0, FileNotFoundError('missing')]):
                self.assertEqual(cp.power_off(), 1)
            self.assertEqual(allow.read_text(), 'N')

    def test_timeout_fails_and_restores_allow(self):
        with tempfile.TemporaryDirectory() as directory:
            allow = Path(directory) / 'allow'; allow.write_text('N')
            with patch.object(cp, 'ALLOW', allow), patch.object(cp, 'ioctl', side_effect=[4, 0]), patch.object(cp, 'wait_for', return_value=False):
                self.assertEqual(cp.power_off(), 1)
            self.assertEqual(allow.read_text(), 'N')


if __name__ == '__main__':
    unittest.main()
