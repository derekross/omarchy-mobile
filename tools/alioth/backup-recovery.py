#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Read original F3 boot/NV partitions from temporary TWRP into private backups."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
from backup_recovery_names import REQUIRED_BACKUPS as REQUIRED

ROOT = Path(__file__).resolve().parents[2]


def adb(*args):
    return subprocess.check_output(["adb", "-d", *args], text=True).strip()


def main():
    if adb("shell", "id", "-u") != "0":
        raise SystemExit("Read-only backup requires root ADB from temporary TWRP; no reboot or write was attempted")
    subprocess.run(["adb", "-d", "shell", "test -x /sbin/twrp || test -x /system/bin/twrp"], check=True)
    if adb("shell", "getprop", "ro.product.device") not in ("alioth", "aliothin"):
        raise SystemExit("Connected recovery is not alioth")
    names = set(adb("shell", "ls", "/dev/block/by-name").split())
    if not REQUIRED <= names:
        raise SystemExit("Required F3 partitions missing; inspect the layout without writing anything")
    selected = REQUIRED | {n for n in names if re.fullmatch(r"fsc|efs.*|mdm.*efs.*|modem_[ab]", n)}
    if not all(re.fullmatch(r"[a-z0-9_]+", n) for n in selected):
        raise SystemExit("Unexpected partition name")
    serial = adb("get-serialno")
    private = ROOT / "keys"
    private.mkdir(mode=0o700, exist_ok=True)
    private.chmod(0o700)
    base = private / "backups"
    base.mkdir(mode=0o700, exist_ok=True)
    base.chmod(0o700)
    out = base / time.strftime("alioth-%Y%m%d-%H%M%S", time.gmtime())
    out.mkdir(parents=True, mode=0o700)
    records = {}
    for name in sorted(selected):
        device = "/dev/block/by-name/" + name
        expected = int(adb("shell", "blockdev", "--getsize64", device))
        if not (0 < expected <= 512 * 1024 * 1024):
            raise SystemExit("Unexpected partition size; backup stopped")
        target = out / (name + ".img")
        # Recovery's exec-out merges the remote stdout and stderr streams.
        # Suppress dd's status remotely so it cannot be appended to the image.
        proc = subprocess.Popen(["adb", "-d", "exec-out",
                                 f"dd if={device} bs=1048576 2>/dev/null"],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        h, size = hashlib.sha256(), 0
        with target.open("wb") as dest:
            target.chmod(0o600)
            for data in iter(lambda: proc.stdout.read(1024 * 1024), b""):
                dest.write(data)
                h.update(data)
                size += len(data)
        errors = proc.stderr.read()
        if proc.wait() or size != expected:
            raise SystemExit(f"Incomplete backup for {name}; no device writes were made")
        device_sha256 = adb("shell", "sha256sum", device).split()[0]
        if device_sha256 != h.hexdigest():
            raise SystemExit(f"Device/off-device checksum differs for {name}; backup stopped")
        target.chmod(0o600)
        records[name] = {"file": target.name, "bytes": size, "sha256": h.hexdigest()}
        print(f"Read and checksummed {name} ({size} bytes)", flush=True)
    receipt = {"device": "alioth", "serial_sha256": hashlib.sha256(serial.encode()).hexdigest(),
               "read_only_capture": True, "device_sha256_verified": True,
               "partitions": records, "phone_written": False}
    manifest = out / "BACKUP-MANIFEST.json"
    manifest.write_text(json.dumps(receipt, indent=2) + "\n")
    manifest.chmod(0o600)
    print(f"Private backup manifest: {manifest}", flush=True)


if __name__ == "__main__":
    main()
