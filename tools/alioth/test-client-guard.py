#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check mirroring leaves its timed stop armed on a broken SSH path."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))
spec = importlib.util.spec_from_file_location("client", Path(__file__).with_name("phone-client.py"))
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)


class MirrorGuard(unittest.TestCase):
    def test_success_cancels_only_after_fresh_ssh(self):
        with patch.object(client, "run_ssh") as ssh:
            client.guarded_mirror("on")
        commands = [call.args[0] for call in ssh.call_args_list]
        self.assertEqual(commands[0][0], "systemd-run")
        self.assertIn("--on-active=90", commands[0])
        self.assertEqual(commands[0][-2:], ["/usr/bin/omamobile-mirror", "off"])
        self.assertEqual(commands[1:3], [["omamobile-mirror", "on"], ["true"]])
        self.assertEqual(commands[3][:2], ["systemctl", "stop"])
        self.assertEqual(commands[3][2], commands[0][1].removeprefix("--unit=") + ".timer")

    def test_mirror_failure_keeps_timer(self):
        failure = subprocess.CalledProcessError(1, "synthetic SSH failure")
        with patch.object(client, "run_ssh", side_effect=[None, failure]) as ssh:
            with self.assertRaises(subprocess.CalledProcessError):
                client.guarded_mirror("on")
        self.assertEqual(ssh.call_count, 2)

    def test_fresh_ssh_failure_keeps_timer(self):
        failure = subprocess.CalledProcessError(1, "synthetic SSH failure")
        with patch.object(client, "run_ssh", side_effect=[None, None, failure]) as ssh:
            with self.assertRaises(subprocess.CalledProcessError):
                client.guarded_mirror("off")
        self.assertEqual(ssh.call_count, 3)


if __name__ == "__main__":
    unittest.main()
