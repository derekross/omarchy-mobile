#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Remove TWRP image padding offline, preserving every boot and AVB byte."""
import hashlib
import argparse
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "out/alioth/inputs/twrp-3.7.1_12-0-alioth.img"
EXPECTED = "bf5bf3300da28abbef0493829a35fcd703424c1255172f5613789a7e2cfed2e3"
SIZE = 96 * 1024 * 1024


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, default=SOURCE)
    args = parser.parse_args()
    source = args.image.resolve()
    original = source.read_bytes()
    if hashlib.sha256(original).hexdigest() != EXPECTED:
        raise SystemExit("Official recovery checksum mismatch; no image changed")
    magic, major, minor, payload, offset, metadata, reserved = struct.unpack(
        ">4sIIQQQ28s", original[-64:])
    if (magic != b"AVBf" or major != 1 or payload != 77209600
            or offset != payload or metadata != 704 or offset + metadata >= SIZE - 64):
        raise SystemExit("Unexpected recovery AVB layout; no image changed")
    target = source.with_name("twrp-3.7.1_12-0-alioth-ramboot-96MiB.img")
    # avbtool expects a file named boot.img when verifying the boot descriptor.
    with tempfile.TemporaryDirectory(dir=source.parent) as scratch:
        candidate = Path(scratch) / "boot.img"
        shutil.copyfile(source, candidate)
        subprocess.run(["avbtool", "resize_image", "--image", str(candidate),
                        "--partition_size", str(SIZE)], check=True)
        resized = candidate.read_bytes()
        if (len(resized) != SIZE or resized[:payload] != original[:payload]
                or resized[offset:offset + metadata] != original[offset:offset + metadata]
                or resized[-64:] != original[-64:]):
            raise SystemExit("Recovery contents changed; derived image rejected")
        subprocess.run(["avbtool", "verify_image", "--image", str(candidate)], check=True)
        candidate.replace(target)
    receipt = {
        "source": source.name, "source_sha256": EXPECTED,
        "derived": target.name, "derived_bytes": SIZE,
        "derived_sha256": hashlib.sha256(resized).hexdigest(),
        "operation": "avbtool resize_image to 96 MiB; only padding removed; "
                     "original boot payload, vbmeta, footer byte-identical",
        "original_payload_bytes": payload, "temporary_ram_boot_only": True,
    }
    target.with_suffix(".json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Verified RAM-boot recovery: {target}")


if __name__ == "__main__":
    main()
