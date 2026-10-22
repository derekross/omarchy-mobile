#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the boot function against scratch sysfs and blocked write commands."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RootGuard(unittest.TestCase):
    def exercise(self, label):
        source = (ROOT / "initramfs/init").read_text()
        start = source.index("boot_arch() {")
        end = source.index("\nboot_arch\n", start)
        function = source[start:end]
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            sys = base / "sys/block/sda/sda35"
            sys.mkdir(parents=True)
            (sys / "uevent").write_text("PARTNAME=userdata\n")
            (sys / "ro").write_text("0\n")
            (base / "cmdline").write_text("")
            function = function.replace("/sys/block/sda", str(base / "sys/block/sda"))
            function = function.replace("/proc/cmdline", str(base / "cmdline"))
            function = function.replace("/newroot", str(base / "newroot"))
            # Never invoke a block operation, mount, process kill or switch_root.
            script = '''
say() { :; }
blkid() { printf '%s\\n' "$LABEL"; }
e2fsck() { echo repair >> "$MARKER"; }
grow_root() { echo grow >> "$MARKER"; }
mount() { echo mount >> "$MARKER"; return 1; }
kill() { echo forbidden-kill >> "$MARKER"; return 99; }
switch_root() { echo forbidden-switch >> "$MARKER"; return 99; }
''' + function + '\nboot_arch\n'
            env = os.environ.copy()
            env.update(LABEL=label, MARKER=str(base / "writes"))
            result = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)
            marker = base / "writes"
            return result.returncode, marker.read_text() if marker.exists() else ""

    def test_existing_android_is_never_repaired_or_mounted(self):
        for label in ("", "userdata", "android", "anything-else"):
            status, writes = self.exercise(label)
            self.assertEqual(status, 1)
            self.assertEqual(writes, "", label)

    def test_only_explicit_omarchy_root_reaches_write_steps(self):
        status, writes = self.exercise("omamobile-root")
        self.assertEqual(status, 1)  # the fake mount deliberately refuses
        self.assertEqual(writes.splitlines(), ["repair", "grow", "mount"])


if __name__ == "__main__":
    unittest.main()
