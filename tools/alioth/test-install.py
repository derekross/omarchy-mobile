#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise destructive-install gates with local fixtures; never call fastboot."""
import importlib.util
import contextlib
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))
spec = importlib.util.spec_from_file_location("installer", Path(__file__).with_name("install.py"))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallGates(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ("boot.img", "boot-rescue.img"):
            (self.root / name).write_bytes(name.encode())
        (self.root / "rootfs-sparse.img").write_bytes(
            struct.pack("<I4H4I", 0xed26ff3a, 1, 0, 28, 12, 4096, 2, 0, 0))
        self.boot = dict(device="alioth", boot_sha256=installer.digest(self.root / "boot.img"),
                         rescue_boot_sha256=installer.digest(self.root / "boot-rescue.img"))
        self.fs = dict(device="alioth", rootfs_bytes=8192,
                       rootfs_sha256="f" * 64,
                       rootfs_sparse_sha256=installer.digest(self.root / "rootfs-sparse.img"))
        self.write("BOOT-MANIFEST.json", self.boot)
        self.write("ROOT-MANIFEST.json", self.fs)
        self.validation = dict(device="alioth", boot_payload_checked=True, root_payload_checked=True,
                               boot_sha256=self.boot["boot_sha256"],
                               rescue_boot_sha256=self.boot["rescue_boot_sha256"],
                               rootfs_sparse_sha256=self.fs["rootfs_sparse_sha256"])
        self.write("VALIDATION.json", self.validation)

    def write(self, name, value):
        (self.root / name).write_text(json.dumps(value))

    def test_changed_boot_rejected(self):
        (self.root / "boot.img").write_bytes(b"modified")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            installer.verify_images(self.root)

    def test_wrong_device_rejected(self):
        self.boot["device"] = "cheetah"
        self.write("BOOT-MANIFEST.json", self.boot)
        with self.assertRaisesRegex(ValueError, "not marked for alioth"):
            installer.verify_images(self.root)

    def test_sparse_size_mismatch_rejected(self):
        self.fs["rootfs_bytes"] = 4096
        self.write("ROOT-MANIFEST.json", self.fs)
        with self.assertRaisesRegex(ValueError, "Expanded root image size"):
            installer.verify_images(self.root)

    def test_unvalidated_rebuild_rejected(self):
        self.validation["rootfs_sparse_sha256"] = "stale"
        self.write("VALIDATION.json", self.validation)
        with self.assertRaisesRegex(ValueError, "successful offline validation"):
            installer.verify_images(self.root)

    def test_backup_wrong_phone_rejected(self):
        self.write("backups.json", dict(device="alioth", read_only_capture=True,
                                        device_sha256_verified=True, serial_sha256="other"))
        with self.assertRaisesRegex(ValueError, "connected phone"):
            installer.verify_backups(self.root / "backups.json", "synthetic-phone")

    def test_backup_modified_partition_rejected(self):
        partition = self.root / "partition.img"
        partition.write_bytes(b"original")
        record = dict(file=partition.name, bytes=partition.stat().st_size, sha256=installer.digest(partition))
        self.write("backups.json", dict(device="alioth", read_only_capture=True, device_sha256_verified=True,
                                        serial_sha256=installer.hashlib.sha256(b"synthetic-phone").hexdigest(),
                                        partitions={name: record for name in installer.REQUIRED_BACKUPS}))
        partition.write_bytes(b"changed!")
        with self.assertRaisesRegex(ValueError, "Original backup differs"):
            installer.verify_backups(self.root / "backups.json", "synthetic-phone")

    def test_probe_never_flashes_userdata(self):
        commands = installer.plan(self.root, probe=True)
        self.assertFalse(any("userdata" in command or "flash" in command for command in commands))
        self.assertEqual(commands[-1][:2], ["fastboot", "boot"])

    def test_full_plan_only_writes_allowed_targets(self):
        commands = installer.plan(self.root)
        self.assertEqual([command[command.index("flash") + 1] for command in commands if "flash" in command],
                         ["userdata", "boot_b"])
        self.assertEqual([command[2] for command in commands if "erase" in command], ["dtbo_b"])
        self.assertEqual(installer.verify_images(self.root), (self.boot, self.fs))

    def proof(self, **changes):
        receipt = dict(device="alioth", kernel_release="6.15.1-sm8250",
                       read_only_capture=True, rescue_boot=True, userdata_unmounted=True,
                       storage_guard_passed=True, captured_at=installer.time.time(),
                       serial_sha256=installer.hashlib.sha256(b"synthetic-phone").hexdigest(),
                       rootfs_bytes=self.fs["rootfs_bytes"], rootfs_sha256=self.fs["rootfs_sha256"])
        receipt.update(changes)
        self.write("proof.json", receipt)
        return self.root / "proof.json"

    def test_finish_requires_matching_readback(self):
        installer.verify_device_root(self.proof(), self.fs, "synthetic-phone")
        with self.assertRaisesRegex(ValueError, "differs from the prepared image"):
            installer.verify_device_root(self.proof(rootfs_sha256="changed"), self.fs, "synthetic-phone")

    def test_finish_rejects_wrong_phone(self):
        with self.assertRaisesRegex(ValueError, "different phone"):
            installer.verify_device_root(self.proof(), self.fs, "other-phone")

    def test_finish_rejects_stale_readback(self):
        with self.assertRaisesRegex(ValueError, "stale"):
            installer.verify_device_root(self.proof(captured_at=installer.time.time() - 1801), self.fs, "synthetic-phone")

    def test_finish_rejects_mounted_root(self):
        with self.assertRaisesRegex(ValueError, "unmounted"):
            installer.verify_device_root(self.proof(userdata_unmounted=False), self.fs, "synthetic-phone")

    def test_finish_never_reflashes_userdata(self):
        commands = installer.plan(self.root, finish_boot=True)
        self.assertFalse(any("userdata" in command for command in commands))
        self.assertEqual([c[c.index("flash") + 1] for c in commands if "flash" in c], ["boot_b"])
        self.assertEqual([c[2] for c in commands if "erase" in c], ["dtbo_b"])

    def test_dry_run_never_queries_or_mutates_phone(self):
        argv = ['install.py', '--images', str(self.root), '--flash', '--dry-run']
        with patch.object(sys, 'argv', argv), patch.object(installer, 'getvar') as getvar, \
             patch.object(installer.subprocess, 'run') as run, contextlib.redirect_stdout(io.StringIO()):
            installer.main()
        getvar.assert_not_called()
        run.assert_not_called()

    def test_missing_wipe_confirmation_stops_before_phone_access(self):
        argv = ['install.py', '--images', str(self.root), '--flash', '--backups', 'unused.json']
        with patch.object(sys, 'argv', argv), patch.object(installer, 'getvar') as getvar, \
             patch.object(installer.subprocess, 'run') as run, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(SystemExit, 'userdata-loss confirmation'):
                installer.main()
        getvar.assert_not_called()
        run.assert_not_called()

    def test_wrong_product_or_slot_never_reaches_writes(self):
        argv = ['install.py', '--images', str(self.root), '--flash',
                '--confirm-erase-userdata', '--backups', 'unused.json']
        for values in ({'product': 'other'}, {'product': 'alioth', 'unlocked': 'yes', 'current-slot': 'b'}):
            with patch.object(sys, 'argv', argv), patch.object(installer, 'verify_recovery'), \
                 patch.object(installer, 'getvar', side_effect=lambda key: values[key]), \
                 patch.object(installer.subprocess, 'run') as run, contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit):
                    installer.main()
            run.assert_not_called()

    def test_unpinned_recovery_rejected(self):
        image = self.root / 'recovery.img'; image.write_bytes(b'unknown image')
        with self.assertRaisesRegex(ValueError, 'integrity check failed'):
            installer.verify_recovery(image)


if __name__ == "__main__":
    unittest.main()
