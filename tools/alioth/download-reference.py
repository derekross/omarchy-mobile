#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Fetch the pinned reference kernel/runtime archive; never access a phone."""
import argparse
import hashlib
from pathlib import Path
import shutil
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
NAME = "xiaomi-alioth-2026-09-28.zip"
URL = "https://github.com/Sucharek233/pmos-alioth-builds/releases/download/2026-09-28_935d1cb/xiaomi-alioth.zip"
SHA256 = "17901fd0f9a96284c42b93ad1c9093aaf9bf79db62d084d80ee72afb4b29bb84"
MEMBERS = {"boot-xiaomi-alioth.img", "rootfs-xiaomi-alioth.img"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs", type=Path, default=ROOT / "out/alioth/inputs")
    parser.add_argument("--archive", type=Path, help="use an already downloaded archive")
    args = parser.parse_args()
    args.inputs.mkdir(parents=True, exist_ok=True)
    archive = args.inputs / NAME
    if args.archive:
        if args.archive.resolve() != archive.resolve():
            shutil.copyfile(args.archive, archive)
    elif not archive.exists():
        temporary = archive.with_suffix(".zip.part")
        with urllib.request.urlopen(URL, timeout=60) as src, temporary.open("wb") as dst:
            shutil.copyfileobj(src, dst, 1024 * 1024)
        temporary.replace(archive)
    with archive.open("rb") as src:
        actual = hashlib.file_digest(src, "sha256").hexdigest()
    if actual != SHA256:
        raise SystemExit("Reference SHA-256 differs; nothing extracted")
    destination = args.inputs / "linux-reference"
    destination.mkdir(exist_ok=True)
    with zipfile.ZipFile(archive) as src:
        if set(src.namelist()) != MEMBERS or len(src.namelist()) != len(MEMBERS):
            raise SystemExit("Unexpected reference archive members")
        for name in sorted(MEMBERS):
            with src.open(name) as source, (destination / name).open("wb") as target:
                shutil.copyfileobj(source, target, 1024 * 1024)
    print("Pinned reference verified and extracted locally; no phone accessed")


if __name__ == "__main__":
    main()
