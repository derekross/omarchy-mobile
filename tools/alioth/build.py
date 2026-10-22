#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build an owner's private alioth images locally; never flash or query a phone."""
import argparse
import datetime
import os
import re
from pathlib import Path
import subprocess
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--username", required=True)
    parser.add_argument("--timezone", default="UTC")
    parser.add_argument("--reference-archive", type=Path)
    parser.add_argument("--version", default="alioth-" + datetime.date.today().isoformat())
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z_][a-z0-9_-]{0,31}', args.username):
        parser.error('username must be a valid local login')
    if not re.fullmatch(r'[0-9A-Za-z._-]+', args.version):
        parser.error('version may contain only letters, digits, dot, underscore and hyphen')
    try:
        ZoneInfo(args.timezone)
    except (ValueError, KeyError):
        parser.error('timezone must be an installed IANA timezone')
    reference_archive = args.reference_archive.resolve() if args.reference_archive else None
    os.chdir(ROOT)
    os.umask(0o077)
    env = dict(os.environ, DEVICE="alioth", OMARCHY_CHANNEL=os.environ.get("OMARCHY_CHANNEL", "stable"),
               OMAMOBILE_KEYRING_DIR=str(ROOT / "keys/build-keyring"), KERNEL_OUT=str(ROOT / "out/alioth/reference"))

    def run(*command):
        subprocess.run(command, env=env, check=True)

    run("python3", "tools/alioth/init-keys.py")
    download = ["python3", "tools/alioth/download-reference.py"]
    if reference_archive:
        download += ["--archive", str(reference_archive)]
    run(*download)
    run("python3", "tools/alioth/prepare-reference.py", "--inputs", "out/alioth/inputs", "--out", "out/alioth/reference")
    run("python3", "tools/alioth/prepare-overlay.py")
    profile = (ROOT / "rootfs/packages.omamobile-alioth").read_text().splitlines()
    packages = [line.split("#", 1)[0].strip() for line in profile]
    packages = list(dict.fromkeys([p for p in packages if p] + ["omamobile-device-alioth"]))
    run("tools/build-packages", *("packages/" + name for name in packages))
    run("tools/build-rootfs", "--keep-raw", "--version", args.version, "--overlay", "out/alioth/root-overlay.tar")
    run("python3", "tools/alioth/provision-image.py", "--root-image",
        f"out/omamobile-rootfs-{args.version}-aarch64.img", "--username", args.username, "--timezone", args.timezone)
    run("python3", "tools/alioth/build-boot.py")
    run("python3", "tools/alioth/verify-image.py")
    run("tools/alioth/test-initramfs-ssh.sh")
    print("Private images validated in out/alioth/images. No phone accessed.")
    print("Next: read device/alioth/FLASH-RUNBOOK.md. Building does not authorize flashing.")


if __name__ == "__main__":
    main()
