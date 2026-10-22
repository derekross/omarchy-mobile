#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Extract the checksum-pinned F3 kernel and matching runtime files, offline."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import zlib

EXPECTED = "17901fd0f9a96284c42b93ad1c9093aaf9bf79db62d084d80ee72afb4b29bb84"
RELEASE = "6.15.1-sm8250"


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def cpio_files(data):
    pos = 0
    while pos + 110 <= len(data):
        header = data[pos:pos + 110]
        if header[:6] not in (b"070701", b"070702"):
            raise ValueError("invalid newc header")
        fields = [int(header[6 + i * 8:14 + i * 8], 16) for i in range(13)]
        size, namesize = fields[6], fields[11]
        name = data[pos + 110:pos + 110 + namesize - 1].decode()
        start = (pos + 110 + namesize + 3) & ~3
        if name == "TRAILER!!!":
            return
        yield name.removeprefix("./"), fields[1], data[start:start + size]
        pos = (start + size + 3) & ~3


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--inputs", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    args = p.parse_args()
    archive = args.inputs / "xiaomi-alioth-2026-09-28.zip"
    if digest(archive) != EXPECTED:
        raise SystemExit("Reference archive checksum mismatch")
    out = args.out.resolve()
    (out / "include/config").mkdir(parents=True, exist_ok=True)
    (out / "include/config/kernel.release").write_text(RELEASE + "\n")
    marker = out / "REFERENCE.json"
    if marker.exists():
        old = json.loads(marker.read_text())
        if old.get("source_sha256") == EXPECTED and all(
            digest(out / f) == s for f, s in old["boot_sha256"].items()
        ):
            print("Pinned reference already prepared", flush=True)
            return
        raise SystemExit("Existing reference outputs differ; use a fresh output directory")
    out.mkdir(parents=True, exist_ok=True)
    source = args.inputs / "linux-reference"
    boot = (source / "boot-xiaomi-alioth.img").read_bytes()
    if boot[:8] != b"ANDROID!":
        raise SystemExit("No Android boot header")
    fields = struct.unpack_from("<10I", boot, 8)
    kernel_size, ramdisk_size, page, version = fields[0], fields[2], fields[7], fields[8]
    if page != 4096 or version != 0:
        raise SystemExit("Unexpected reference boot format")
    kernel = boot[page:page + kernel_size]
    z = zlib.decompressobj(31)
    image = z.decompress(kernel) + z.flush()
    tail = z.unused_data
    if image[56:60] != b"ARM\x64" or tail[:4] != bytes.fromhex("d00dfeed"):
        raise SystemExit("Expected an ARM64 gzip Image with appended DTB")
    if b"Linux version " + RELEASE.encode() + b" " not in image:
        raise SystemExit("Unexpected kernel release")
    if b"xiaomi,alioth\0" not in tail or b"qcom,sm8250\0" not in tail:
        raise SystemExit("Reference DTB is not alioth/SM8250")
    (out / "Image.gz-dtb").write_bytes(kernel)
    (out / "alioth.dtb").write_bytes(tail[:struct.unpack_from(">I", tail, 4)[0]])
    start = image.index(b"IKCFG_ST") + 8
    end = image.index(b"IKCFG_ED", start)
    config = gzip.decompress(image[start:end])
    (out / "kernel.config").write_bytes(config)
    for option in ("USB_CONFIGFS_NCM", "USB_CONFIGFS_ACM", "USB_DWC3_QCOM",
                   "SCSI_UFS_QCOM", "EXT4_FS", "DEVTMPFS", "TYPEC_QCOM_PMIC"):
        if f"CONFIG_{option}=y\n".encode() not in config:
            raise SystemExit(f"Early-boot prerequisite is not built in: {option}")
    ramdisk_offset = ((page + kernel_size + page - 1) // page) * page
    ramdisk = gzip.decompress(boot[ramdisk_offset:ramdisk_offset + ramdisk_size])
    fw = out / "boot-firmware"
    for name, mode, data in cpio_files(ramdisk):
        if not name.startswith("usr/lib/firmware/"):
            continue
        relative = Path(name).relative_to("usr/lib/firmware")
        if relative.is_absolute() or ".." in relative.parts:
            raise SystemExit("Unsafe firmware archive path")
        dest = fw / relative
        if mode & 0o170000 == 0o040000:
            dest.mkdir(parents=True, exist_ok=True)
        elif mode & 0o170000 == 0o100000:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
        elif mode & 0o170000 == 0o120000:
            raise SystemExit("Unexpected firmware symlink; inspect before importing")
    raw = out / "reference.raw"
    ext4 = out / "reference-root.ext4"
    subprocess.run(["simg2img", str(source / "rootfs-xiaomi-alioth.img"), str(raw)], check=True)
    with raw.open("rb") as src:
        src.seek(4096)
        header = src.read(4096)
        if header[:8] != b"EFI PART":
            raise SystemExit("No GPT at 4096-byte sector boundary")
        table, count, entrysize = struct.unpack_from("<QII", header, 72)
        if count > 256 or entrysize != 128:
            raise SystemExit("Unexpected GPT layout")
        src.seek(table * 4096)
        entries = src.read(count * entrysize)
        root = entries[entrysize:2 * entrysize]
        start, end = struct.unpack_from("<QQ", root, 32)
        if not (start == 124928 and end == 847615):
            raise SystemExit("Reference root partition changed")
        src.seek(start * 4096)
        remaining = (end - start + 1) * 4096
        with ext4.open("wb") as dst:
            while remaining:
                chunk = src.read(min(4 * 1024 * 1024, remaining))
                if not chunk:
                    raise SystemExit("Truncated root partition")
                dst.write(chunk)
                remaining -= len(chunk)
    for name, directory in (("modules", "/usr/lib/modules"),
                            ("firmware", "/usr/lib/firmware"),
                            ("ucm2", "/usr/share/alsa/ucm2")):
        destination = out / name
        destination.mkdir(exist_ok=True)
        quoted_destination = '"' + str(destination).replace('\\', '\\\\').replace('"', '\\"') + '"'
        result = subprocess.run(["debugfs", "-R", f"rdump {directory} {quoted_destination}", str(ext4)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        (out / f"extract-{name}.log").write_text(result.stdout + result.stderr)
        if result.returncode or "File not found" in result.stderr:
            raise SystemExit(f"Could not extract {name}; inspect log")
    # rdump includes the named directory beneath its destination.
    modules = out / "modules/modules" / RELEASE
    if not (modules / "kernel/drivers/watchdog/qcom-wdt.ko").exists():
        raise SystemExit("Matching qcom watchdog module missing")
    modules_out = out / f"modules-{RELEASE}.tar.zst"
    tar = subprocess.Popen(["tar", "--owner=0", "--group=0", "-C", str(modules.parent), "-cf", "-", RELEASE], stdout=subprocess.PIPE)
    with modules_out.open("wb") as dst:
        subprocess.run(["zstd", "-q", "-T2", "-6"], stdin=tar.stdout, stdout=dst, check=True)
    tar.stdout.close()
    if tar.wait():
        raise SystemExit("Module archive failed")
    raw.unlink()
    ext4.unlink()
    metadata = {"source_release": "https://github.com/Sucharek233/pmos-alioth-builds/releases/tag/2026-09-28_935d1cb",
                "source_sha256": EXPECTED, "kernel_release": RELEASE,
                "boot_sha256": {n: digest(out / n) for n in ("Image.gz-dtb", "alioth.dtb", "kernel.config")},
                "modules_sha256": digest(modules_out), "phone_accessed": False}
    marker.write_text(json.dumps(metadata, indent=2) + "\n")
    print("Prepared pinned alioth kernel, modules, firmware and ALSA configuration", flush=True)


if __name__ == "__main__":
    main()
