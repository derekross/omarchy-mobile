#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Read back the complete flashed root from rescue, before mounting it."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shlex
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("phone_client", Path(__file__).with_name("phone-client.py"))
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)
SSH_OPTIONS = None


def remote(script, timeout=30):
    global SSH_OPTIONS
    if SSH_OPTIONS is None:
        SSH_OPTIONS = client.ssh_options()
    return subprocess.check_output(SSH_OPTIONS + [shlex.join(["sh", "-c", script])],
                                   text=True, timeout=timeout).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backups", type=Path, required=True)
    args = parser.parse_args()
    target = ROOT / "keys/alioth/alioth-userdata-verified.json"
    target.unlink(missing_ok=True)
    backup = json.loads(args.backups.read_text())
    root = json.loads((ROOT / "out/alioth/images/ROOT-MANIFEST.json").read_text())
    release = remote("uname -r")
    if release != "6.15.1-sm8250":
        raise SystemExit("Unexpected rescue kernel")
    cmdline = remote("cat /proc/cmdline")
    if not {"omamobile.initramfs", "omamobile.noresize"} <= set(cmdline.split()):
        raise SystemExit("Must run from the unmounted rescue boot")
    serial = re.search(r"(?:^| )androidboot.serialno=([^ ]+)", cmdline)
    if not serial or hashlib.sha256(serial[1].encode()).hexdigest() != backup["serial_sha256"]:
        raise SystemExit("Rescue phone identity differs from the original backups")
    if not remote("cat /proc/device-tree/compatible").startswith("xiaomi,alioth\0"):
        raise SystemExit("Rescue device tree is not alioth")
    userdata = remote('''set -e
for p in /sys/class/block/*; do
    if grep -qx PARTNAME=userdata "$p/uevent" 2>/dev/null; then echo "/dev/${p##*/}"; fi
done
''')
    if not re.fullmatch(r"/dev/sda[0-9]+", userdata):
        raise SystemExit("Unexpected or ambiguous userdata layout")
    remote('''set -e
test ! -e /dev/sda
test -z "$(awk '$1 ~ /^\\/dev\\/sd/ {print}' /proc/mounts)"
test "$(cat /sys/class/block/''' + userdata.removeprefix('/dev/') + '''/ro)" = 0
for p in /sys/class/block/sd*; do
    [ -r "$p/ro" ] || continue
    [ "$(cat "$p/ro")" = 0 ] || continue
    case "${p##*/}" in sda|''' + userdata.removeprefix('/dev/') + ''') ;; *) exit 1 ;; esac
done
echo guard-passed
''')
    size = root["rootfs_bytes"]
    if size % 1048576 or size > int(remote("blockdev --getsize64 " + userdata)):
        raise SystemExit("Unexpected root size")
    print("Reading and hashing the entire flashed root without mounting it...", flush=True)
    actual = remote(f"dd if={userdata} bs=1048576 count={size // 1048576} 2>/dev/null | sha256sum", 600).split()[0]
    if actual != root["rootfs_sha256"]:
        raise SystemExit("Flashed root checksum differs; no completion receipt written")
    receipt = dict(device="alioth", kernel_release=release, captured_at=time.time(),
                   serial_sha256=backup["serial_sha256"], read_only_capture=True,
                   rescue_boot=True, userdata_unmounted=True, storage_guard_passed=True,
                   rootfs_bytes=size, rootfs_sha256=actual)
    target.touch(mode=0o600, exist_ok=True)
    target.chmod(0o600)
    target.write_text(json.dumps(receipt, indent=2) + "\n")
    print("Complete device root matches the prepared raw image. Private receipt:", target)


if __name__ == "__main__":
    main()
