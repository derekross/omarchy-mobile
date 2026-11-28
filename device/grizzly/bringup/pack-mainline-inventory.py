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


def arm64_module(path, name):
    content = path.read_bytes()
    if (len(content) < 64 or content[:6] != b"\x7fELF\x02\x01"
            or struct.unpack_from("<HH", content, 16) != (1, 183)
            or f"\0name={name}\0".encode("ascii") not in content):
        raise ValueError(f"expected the ARM64 {name} kernel module")
    return content


def build_read_only_root(output, busybox, loader):
    with TemporaryDirectory(dir=output) as scratch:
        root = Path(scratch)
        for directory in ("bin", "lib", "etc"):
            (root / directory).mkdir(mode=0o755)
        for name, data, mode in (
            ("bin/busybox", busybox, 0o755),
            (LOADER, loader, 0o755),
            ("etc/grizzly-release", b"grizzly-read-only-test-v1\n", 0o644),
            ("root-smoke", (HERE / "read-only-root-smoke").read_bytes(), 0o644),
        ):
            path = root / name
            path.write_bytes(data)
            path.chmod(mode)
        (root / "lib/libc.musl-aarch64.so.1").symlink_to(Path(LOADER).name)
        image = output / "test-root.ext4"
        subprocess.run(["mke2fs", "-q", "-t", "ext4", "-b", "4096", "-m", "0",
                        "-O", "^has_journal", "-E", "root_owner=0:0",
                        "-d", root, image, "1024"], check=True)
    return image


def pack(rescue, output, device_query_only=False, single_lun_only=False,
         single_disk_only=False, gpt_scan_only=False, read_only_test_root=False,
         dsi0_phy_scaffold=None, require_dsi0_sibling_votes=False,
         require_dsi0_selector3_gate=False, dc9x00_binding=None,
         require_dc9x00_be_gate=False):
    if require_dsi0_selector3_gate and not require_dsi0_sibling_votes:
        raise ValueError("DSI0 selector 3 gate checks require sibling vote checks")
    if require_dsi0_sibling_votes and dsi0_phy_scaffold is None:
        raise ValueError("DSI0 sibling vote checks require the PHY scaffold")
    if require_dc9x00_be_gate and dc9x00_binding is None:
        raise ValueError("DC9x00 BE gate checks require the masked binding fixture")
    busybox = arm64_member(rescue, "bin/busybox")
    loader = arm64_member(rescue, LOADER)
    output.mkdir(mode=0o700)
    archive = output / "inventory.cpio"
    compressed = output / "inventory.cpio.lz4"
    root_image = build_read_only_root(output, busybox, loader) if read_only_test_root else None
    gpt_scan_only = (gpt_scan_only or read_only_test_root
                     or dsi0_phy_scaffold is not None or dc9x00_binding is not None)
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
        if root_image:
            files["grizzly-inventory/test-root.ext4"] = (root_image.read_bytes(), 0o400)
            files["grizzly-inventory/read-only-test-root.sh"] = (
                (HERE / "read-only-test-root.sh").read_bytes(), 0o644)
        if dsi0_phy_scaffold is not None:
            module = arm64_module(dsi0_phy_scaffold, "phy_google_malibu_cdphy")
            files["grizzly-inventory/phy-google-malibu-cdphy.ko"] = (module, 0o400)
            files["grizzly-inventory/dsi0-phy-scaffold.sh"] = (
                (HERE / "dsi0-phy-scaffold.sh").read_bytes(), 0o644)
        if require_dsi0_sibling_votes:
            files["grizzly-inventory/dsi0-sibling-votes"] = (b"", 0o644)
        if require_dsi0_selector3_gate:
            files["grizzly-inventory/dsi0-selector3-gate"] = (b"", 0o644)
        if dc9x00_binding is not None:
            module = arm64_module(dc9x00_binding, "malibu_dc9x00")
            files["grizzly-inventory/malibu-dc9x00.ko"] = (module, 0o400)
            files["grizzly-inventory/dc9x00-binding.sh"] = (
                (HERE / "dc9x00-binding.sh").read_bytes(), 0o644)
        if require_dc9x00_be_gate:
            files["grizzly-inventory/dc9x00-be-gate"] = (b"", 0o644)
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
        for path in (archive, compressed, *((root_image,) if root_image else ())):
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
    mode.add_argument("--read-only-test-root", action="store_true",
                      help="add a RAM-backed read-only ext4 smoke test after the v73 read")
    mode.add_argument("--dsi0-phy-scaffold", type=Path, metavar="PHY_MODULE",
                      help="bind the isolated DSI0 PHY module after the v73 storage guard")
    mode.add_argument("--dc9x00-binding", type=Path, metavar="DC_MODULE",
                      help="bind the masked DC9x00 IRQ scaffold after the v73 storage guard")
    parser.add_argument("--require-dsi0-sibling-votes", action="store_true",
                        help="require sibling MBFS samples around the scaffold vote")
    parser.add_argument("--require-dsi0-selector3-gate", action="store_true",
                        help="require read-only selector 3 gate samples alongside sibling votes")
    parser.add_argument("--require-dc9x00-be-gate", action="store_true",
                        help="require selector 4 gate samples around the masked DC9x00 binding")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        pack(args.rescue_cpio, args.output, args.device_query_only,
             args.single_lun_only, args.single_disk_only, args.gpt_scan_only,
             args.read_only_test_root, args.dsi0_phy_scaffold, args.require_dsi0_sibling_votes,
             args.require_dsi0_selector3_gate, dc9x00_binding=args.dc9x00_binding,
             require_dc9x00_be_gate=args.require_dc9x00_be_gate)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"mainline inventory packaging failed: {error}\n")


if __name__ == "__main__":
    main()
