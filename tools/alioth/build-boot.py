#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Pack the pinned F3 kernel and custom initramfs into an Android v0 image."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=ROOT / "out/alioth")
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    out.chmod(0o700)
    ref = out / "reference"
    key = ROOT / "keys/alioth_ed25519.pub"
    if not key.read_text().startswith("ssh-ed25519 "):
        raise SystemExit("Dedicated SSH PUBLIC key missing")
    metadata = json.loads((ref / "REFERENCE.json").read_text())
    for name, expected in metadata["boot_sha256"].items():
        if hashlib.sha256((ref / name).read_bytes()).hexdigest() != expected:
            raise SystemExit(f"Reference input changed: {name}")
    subprocess.run(["docker", "pull", "--platform", "linux/arm64", "alpine:3.22"], check=True)
    digest = json.loads(subprocess.check_output(["docker", "image", "inspect", "alpine:3.22"]))[0]["RepoDigests"][0]
    subprocess.run(["docker", "run", "--rm", "--platform", "linux/arm64",
                    "-v", f"{ROOT}:/src:ro", "-v", f"{ref}:/reference:ro",
                    "-v", f"{key}:/input/key.pub:ro", "-v", f"{out}:/out",
                    "-e", f"OUT_UID={os.getuid()}", "-e", f"OUT_GID={os.getgid()}",
                    digest, "sh", "/src/tools/alioth/build-initramfs.sh"], check=True)
    images = out / "images"
    images.mkdir(exist_ok=True)
    images.chmod(0o700)
    pack = ["mkbootimg", "--header_version", "0", "--base", "0x00000000",
                    "--kernel_offset", "0x00008000", "--ramdisk_offset", "0x01000000",
                    "--second_offset", "0x00f00000", "--tags_offset", "0x00000100",
                    "--pagesize", "4096", "--kernel", str(ref / "Image.gz-dtb"),
                    "--ramdisk", str(out / "initramfs.cpio.gz")]
    cmdline = "console=tty0 rdinit=/init panic=10 printk.devkmsg=on rootwait"
    subprocess.run(pack + ["--cmdline", cmdline, "--output", str(images / "boot.img")], check=True)
    subprocess.run(pack + ["--cmdline", cmdline + " omamobile.initramfs omamobile.noresize",
                           "--output", str(images / "boot-rescue.img")], check=True)
    boot = (images / "boot.img").read_bytes()
    if boot[:8] != b"ANDROID!" or struct.unpack_from("<I", boot, 40)[0] != 0:
        raise SystemExit("Unexpected generated Android header")
    if len(boot) > 192 * 1024 * 1024:
        raise SystemExit("Boot image exceeds the documented alioth boot partition")
    (images / "DEVICE").write_text("alioth\n")
    manifest = {"device": "alioth", "kernel_release": metadata["kernel_release"],
                "reference": metadata, "alpine_builder": digest,
                "ssh_public_key_sha256": hashlib.sha256(key.read_bytes()).hexdigest(),
                "initramfs_sha256": hashlib.sha256((out / "initramfs.cpio.gz").read_bytes()).hexdigest(),
                "init_source_sha256": hashlib.sha256((ROOT / "initramfs/init").read_bytes()).hexdigest(),
                "builder_source_sha256": hashlib.sha256((ROOT / "tools/alioth/build-initramfs.sh").read_bytes()).hexdigest(),
                "boot_bytes": len(boot), "boot_sha256": hashlib.sha256(boot).hexdigest(),
                "rescue_boot_bytes": (images / "boot-rescue.img").stat().st_size,
                "rescue_boot_sha256": hashlib.sha256((images / "boot-rescue.img").read_bytes()).hexdigest(),
                "phone_accessed": False, "hardware_boot_tested": False}
    (images / "BOOT-MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Packed alioth boot.img ({len(boot)} bytes)", flush=True)


if __name__ == "__main__":
    main()
