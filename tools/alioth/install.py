#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Gated initial F3 install. Default is an offline, read-only command plan."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import struct
import subprocess
import time
from backup_recovery_names import REQUIRED_BACKUPS

ROOT = Path(__file__).resolve().parents[2]
RECOVERY = ROOT / "out/alioth/inputs/twrp-3.7.1_12-0-alioth.img"
RECOVERY_SHA256 = "bf5bf3300da28abbef0493829a35fcd703424c1255172f5613789a7e2cfed2e3"


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as src:
        for b in iter(lambda: src.read(4 * 1024 * 1024), b""):
            h.update(b)
    return h.hexdigest()


def verify_images(directory):
    boot = json.loads((directory / "BOOT-MANIFEST.json").read_text())
    root = json.loads((directory / "ROOT-MANIFEST.json").read_text())
    if boot["device"] != "alioth" or root["device"] != "alioth":
        raise ValueError("Images are not marked for alioth")
    for name, expected in (("boot.img", boot["boot_sha256"]),
                           ("boot-rescue.img", boot["rescue_boot_sha256"]),
                           ("rootfs-sparse.img", root["rootfs_sparse_sha256"])):
        if digest(directory / name) != expected:
            raise ValueError(f"Image checksum mismatch: {name}")
    with (directory / "rootfs-sparse.img").open("rb") as src:
        header = src.read(28)
    if len(header) != 28:
        raise ValueError("Truncated sparse image")
    magic, major, minor, file_header, chunk_header, block, count, chunks, crc = struct.unpack("<I4H4I", header)
    if magic != 0xed26ff3a or major != 1 or file_header != 28 or chunk_header != 12 or block != 4096:
        raise ValueError("Unsupported sparse image format")
    if block * count != root["rootfs_bytes"]:
        raise ValueError("Expanded root image size differs from its manifest")
    validation = json.loads((directory / "VALIDATION.json").read_text())
    if (validation.get("device") != "alioth" or not validation.get("boot_payload_checked")
            or not validation.get("root_payload_checked")
            or validation.get("boot_sha256") != boot["boot_sha256"]
            or validation.get("rescue_boot_sha256") != boot["rescue_boot_sha256"]
            or validation.get("rootfs_sparse_sha256") != root["rootfs_sparse_sha256"]):
        raise ValueError("Images have no matching successful offline validation")
    return boot, root


def plan(directory, probe=False, finish_boot=False, serial="<serial>"):
    # These targets are fixed in code. No manifest can redirect a write to
    # calibration, a bootloader, vbmeta, radio, or slot A.
    if probe:
        return [["fastboot", "-s", serial, "erase", "dtbo_b"], ["fastboot", "-s", serial, "--set-active=b"],
                ["fastboot", "-s", serial, "boot", str(directory / "boot-rescue.img")]]
    finish = [["fastboot", "-s", serial, "erase", "dtbo_b"],
            ["fastboot", "-s", serial, "flash", "boot_b", str(directory / "boot.img")],
            ["fastboot", "-s", serial, "--set-active=b"], ["fastboot", "-s", serial, "reboot"]]
    if finish_boot:
        return finish
    return [["fastboot", "-s", serial, "-S", "64M", "flash", "userdata", str(directory / "rootfs-sparse.img")]] + finish


def getvar(name, serial=None):
    command = ["fastboot"] + (["-s", serial] if serial else []) + ["getvar", name]
    result = subprocess.run(command, capture_output=True, text=True, timeout=15)
    text = result.stdout + result.stderr
    if result.returncode:
        raise ValueError(f"Cannot read fastboot variable {name}")
    match = re.search(r"(?:\(bootloader\)\s*)?" + re.escape(name) + r":\s*(\S+)", text)
    if not match:
        raise ValueError(f"Fastboot variable missing: {name}")
    return match.group(1)


def verify_backups(path, serial):
    receipt = json.loads(path.read_text())
    if receipt.get("device") != "alioth" or not receipt.get("read_only_capture") or not receipt.get("device_sha256_verified"):
        raise ValueError("Backup receipt is not a read-only alioth capture")
    if receipt.get("serial_sha256") != hashlib.sha256(serial.encode()).hexdigest():
        raise ValueError("Backups do not belong to the connected phone")
    partitions = receipt.get("partitions", {})
    if not REQUIRED_BACKUPS <= partitions.keys():
        raise ValueError("Original boot and calibration backups are incomplete")
    for name, record in partitions.items():
        filename = record["file"]
        if Path(filename).name != filename:
            raise ValueError("Unsafe backup filename")
        file = path.parent / filename
        if file.stat().st_size != record["bytes"] or digest(file) != record["sha256"]:
            raise ValueError(f"Original backup differs: {name}")


def verify_device_root(path, root, serial):
    receipt = json.loads(path.read_text())
    if (receipt.get("device") != "alioth" or receipt.get("kernel_release") != "6.15.1-sm8250"
            or any(receipt.get(flag) is not True for flag in
                   ("read_only_capture", "rescue_boot", "userdata_unmounted", "storage_guard_passed"))):
        raise ValueError("Root readback was not performed from guarded, unmounted alioth rescue")
    if receipt.get("serial_sha256") != hashlib.sha256(serial.encode()).hexdigest():
        raise ValueError("Root readback belongs to a different phone")
    if (receipt.get("rootfs_bytes") != root["rootfs_bytes"]
            or receipt.get("rootfs_sha256") != root["rootfs_sha256"]):
        raise ValueError("Device root readback differs from the prepared image")
    age = time.time() - receipt.get("captured_at", 0)
    if not 0 <= age <= 1800:
        raise ValueError("Device root readback is stale; verify again without booting Android")


def verify_recovery(image=RECOVERY):
    if digest(image) != RECOVERY_SHA256:
        raise ValueError("F3 recovery image integrity check failed")
    # verify_backups checks this phone's original A/B boot/dtbo/vendor_boot
    # images. Do not require a different owner's regional factory archive.


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--images", type=Path, default=ROOT / "out/alioth/images")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--flash", action="store_true")
    p.add_argument("--confirm-erase-userdata", action="store_true")
    p.add_argument("--backups", type=Path)
    p.add_argument("--recovery", type=Path, default=RECOVERY)
    p.add_argument("--probe", action="store_true", help="Rescue trial: erases dtbo_b and leaves slot B active; does not mount or flash userdata")
    p.add_argument("--finish-boot", action="store_true", help="Complete only slot B after verified full userdata readback")
    p.add_argument("--verified-root", type=Path, help="Fresh private receipt from verify-device-root.py")
    args = p.parse_args()
    if args.probe and args.finish_boot:
        p.error("--probe and --finish-boot are mutually exclusive")
    directory = args.images.resolve()
    boot, root = verify_images(directory)
    print("POCO F3 / alioth initial installation")
    if args.probe:
        print("Rescue trial: erases dtbo_b and leaves slot B active; temporarily boots the rescue image.")
        print("The rescue command line disables root mounting and resize. Original backups are required.")
    elif args.finish_boot:
        print("Complete slot B only. Requires a fresh, complete device root checksum matching this image and phone.")
    else:
        print("This replaces ALL Android userdata. Slot A boot images are retained; Android data is not.")
    print("boot.img sha256:", boot["boot_sha256"])
    print("rootfs-sparse.img sha256:", root["rootfs_sparse_sha256"])
    commands = plan(directory, args.probe, args.finish_boot)
    for command in commands:
        print(shlex.join(command))
    if not args.flash or args.dry_run:
        print("DRY RUN: no phone commands, reboot, erase or flash executed")
        return
    if not args.backups or (not args.probe and not args.finish_boot and not args.confirm_erase_userdata):
        raise SystemExit("Flashing requires explicit userdata-loss confirmation and a verified original backup manifest")
    if args.finish_boot and not args.verified_root:
        raise SystemExit("Finishing slot B requires complete device userdata readback; no writes attempted")
    verify_recovery(args.recovery.resolve())
    serial = getvar("serialno")
    if not serial or serial.startswith("-") or serial.lower() in ("unknown", "none"):
        raise SystemExit("Cannot pin a valid fastboot serial")
    if getvar("product", serial) != "alioth" or getvar("unlocked", serial).lower() not in ("yes", "true", "1"):
        raise SystemExit("Connected phone must be an unlocked alioth")
    if getvar("current-slot", serial) != "a":
        raise SystemExit("Initial installation requires the verified stock slot A to be active")
    verify_backups(args.backups.resolve(), serial)
    if args.finish_boot:
        verify_device_root(args.verified_root.resolve(), root, serial)
    if int(getvar("partition-size:boot_b", serial), 0) < boot["boot_bytes"]:
        raise SystemExit("Boot image does not fit the actual phone")
    if not args.probe and int(getvar("partition-size:userdata", serial), 0) < root["rootfs_bytes"]:
        raise SystemExit("Root image does not fit userdata")
    if int(getvar("partition-size:dtbo_b", serial), 0) <= 0:
        raise SystemExit("Missing slot B dtbo partition")
    print("All preflight gates passed. Executing the reviewed initial-install plan.", flush=True)
    commands = plan(directory, args.probe, args.finish_boot, serial=serial)
    for command in commands:
        subprocess.run(command, check=True, timeout=1800)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
