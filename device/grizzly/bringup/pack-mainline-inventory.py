# SPDX-License-Identifier: MIT
"""Build the standalone Grizzly mainline inventory initramfs."""

import argparse
import hashlib
import os
from pathlib import Path
import struct
import subprocess
from tempfile import TemporaryDirectory


HERE = Path(__file__).resolve().parent
BUSYBOX = "grizzly-inventory/busybox"
LOADER = "lib/ld-musl-aarch64.so.1"


def arm64_member(archive, member):
    content = subprocess.check_output(["bsdtar", "-xOf", archive, member])
    if (len(content) < 64 or content[:6] != b"\x7fELF\x02\x01"
            or struct.unpack_from("<H", content, 18)[0] != 183):
        raise ValueError(f"rescue archive member is not ARM64 ELF: {member}")
    return content


def pack(rescue, output, device_query_only=False, single_lun_only=False,
         single_disk_only=False, gpt_scan_only=False):
    busybox = arm64_member(rescue, "bin/busybox")
    loader = arm64_member(rescue, LOADER)
    output.mkdir(mode=0o700)
    archive = output / "inventory.cpio"
    compressed = output / "inventory.cpio.lz4"
    with TemporaryDirectory(dir=output) as scratch:
        root = Path(scratch)
        dirs = ("grizzly-inventory", "lib")
        files = {
            "init": ((HERE / "stock-inventory-init").read_bytes(), 0o755),
            "grizzly-inventory/mainline-inventory": (b"", 0o644),
            "grizzly-inventory/scan.sh": ((HERE / "stock-inventory-scan.sh").read_bytes(), 0o644),
            "grizzly-inventory/nv-guard.sh": ((HERE / "stock-nv-guard.sh").read_bytes(), 0o644),
            BUSYBOX: (busybox, 0o755),
            LOADER: (loader, 0o755),
        }
        if device_query_only or single_lun_only or single_disk_only or gpt_scan_only:
            files["grizzly-inventory/device-query-only"] = (b"", 0o644)
        if single_lun_only or single_disk_only or gpt_scan_only:
            files["grizzly-inventory/single-lun-only"] = (b"", 0o644)
        if single_disk_only or gpt_scan_only:
            files["grizzly-inventory/single-disk-only"] = (b"", 0o644)
        if gpt_scan_only:
            files["grizzly-inventory/gpt-scan-only"] = (b"", 0o644)
        libc = "lib/libc.musl-aarch64.so.1"
        for name in dirs:
            path = root / name
            path.mkdir()
            path.chmod(0o755)
        for name, (data, mode) in files.items():
            path = root / name
            path.write_bytes(data)
            path.chmod(mode)
        (root / libc).symlink_to(Path(LOADER).name)
        members = (*dirs, *files, libc)
        for name in members:
            os.utime(root / name, (0, 0), follow_symlinks=False)
        subprocess.run(["bsdtar", "--format", "newc", "--uid", "0", "--gid", "0",
                        "--no-recursion", "-cf", archive, "-C", root, *members], check=True)
    listing = subprocess.check_output(["bsdtar", "-tf", archive]).decode().splitlines()
    if len(listing) != len(members) or set(listing) != set(members):
        raise ValueError("unexpected inventory archive members")

    subprocess.run(["lz4", "-l", "-12", archive, compressed], check=True)
    if subprocess.check_output(["lz4", "-dc", compressed]) != archive.read_bytes():
        raise ValueError("inventory ramdisk failed LZ4 round-trip")
    with (output / "SHA256SUMS").open("w", encoding="ascii") as manifest:
        for path in (archive, compressed):
            with path.open("rb") as data:
                digest = hashlib.file_digest(data, "sha256").hexdigest()
            print(f"{digest}  {path.name}", file=manifest)


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rescue-cpio", type=Path, required=True)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--device-query-only", action="store_true",
                      help="expect no SCSI disks and skip NV inventory")
    mode.add_argument("--single-lun-only", action="store_true",
                      help="allow a manual LUN probe and expect no SCSI disks")
    mode.add_argument("--single-disk-only", action="store_true",
                      help="verify one temporary read-only SCSI disk in sysfs")
    mode.add_argument("--gpt-scan-only", action="store_true",
                      help="verify a temporary read-only LUN 0 disk and its GPT partitions")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        pack(args.rescue_cpio, args.output, args.device_query_only,
             args.single_lun_only, args.single_disk_only, args.gpt_scan_only)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"mainline inventory packaging failed: {error}\n")


if __name__ == "__main__":
    main()
