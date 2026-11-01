# SPDX-License-Identifier: MIT
"""cp.state() reads the CP state on one open file: it opens umts_boot0 once
and reuses it, reopens after an error, and reads a missing device as
OFFLINE (the suite itself runs with the CP check off)."""
import env  # noqa: F401  (paths and sys.path first)
import unittest
from unittest.mock import patch

import cp


class HeldFile(unittest.TestCase):
    def setUp(self):
        cp._fd = None
        self.addCleanup(setattr, cp, '_fd', None)

    def test_opens_once_and_reuses_the_file(self):
        with patch.object(cp, 'BOOT', '/dev/umts_boot0'), \
             patch.object(cp.os, 'open', return_value=7) as opened, \
             patch.object(cp.os, 'close') as closed, \
             patch.object(cp.fcntl, 'ioctl', return_value=cp.ONLINE) as ioctl:
            self.assertEqual(cp.state(), cp.ONLINE)
            self.assertEqual(cp.state(), cp.ONLINE)
            self.assertTrue(cp.online())
        self.assertEqual(opened.call_count, 1)
        self.assertEqual(ioctl.call_count, 3)
        closed.assert_not_called()
        self.assertEqual(ioctl.call_args[0][0], 7)

    def test_reopens_after_an_error(self):
        with patch.object(cp, 'BOOT', '/dev/umts_boot0'), \
             patch.object(cp.os, 'open', side_effect=[7, 8]) as opened, \
             patch.object(cp.os, 'close') as closed, \
             patch.object(cp.fcntl, 'ioctl',
                          side_effect=[OSError(5, 'I/O error'), 3]):
            with self.assertRaises(OSError):
                cp.state()
            closed.assert_called_once_with(7)
            self.assertIsNone(cp._fd)
            self.assertEqual(cp.state(), 3)
        self.assertEqual(opened.call_count, 2)
        self.assertEqual(cp._fd, 8)

    def test_missing_device_reads_offline(self):
        with patch.object(cp, 'BOOT', '/dev/umts_boot0'), \
             patch.object(cp.os, 'open', side_effect=FileNotFoundError):
            self.assertEqual(cp.state(), 0)
            self.assertFalse(cp.online())
        self.assertIsNone(cp._fd)

    def test_no_device_configured_is_online(self):
        with patch.object(cp, 'BOOT', 'none'), \
             patch.object(cp.os, 'open') as opened:
            self.assertTrue(cp.online())
        opened.assert_not_called()


if __name__ == '__main__':
    unittest.main()
