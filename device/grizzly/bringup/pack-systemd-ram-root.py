# SPDX-License-Identifier: MIT
"""Add the isolated systemd RAM-root receiver to a v73 inventory initramfs."""

import argparse
import os
from pathlib import Path
import re
import stat
import subprocess
from tempfile import TemporaryDirectory


HERE = Path(__file__).resolve().parent
TOOLS = ("usr/sbin/dropbear", "usr/bin/openssl", "usr/bin/zstd")
LIBRARIES = ("libcrypto.so.3", "libssl.so.3", "libutmps.so.0.1.3.3",
             "libskarnet.so.2.15.0.0", "libz.so.1.3.2", "libzstd.so.1.5.7")
ALIASES = {"libutmps.so.0.1": "libutmps.so.0.1.3.3",
           "libskarnet.so.2.15": "libskarnet.so.2.15.0.0",
           "libz.so.1": "libz.so.1.3.2", "libzstd.so.1": "libzstd.so.1.5.7"}
ROOT = b"11542724608 f7d74ed4b8e865ffb1caff2967d90b86a40a1d7f76c9720ba77d814c5845a40b\n"


def cpio_members(data):
    pos = 0
    while pos < len(data):
        if data[pos] == 0:
            pos += 1
            continue
        header = data[pos:pos + 110]
        if header[:6] != b"070701":
            raise ValueError("expected a concatenated newc archive")
        mode, size, namesize = (int(header[start:start + 8], 16) for start in (14, 54, 94))
        name = data[pos + 110:pos + 110 + namesize - 1].decode().removeprefix("./")
        pos = (pos + 110 + namesize + 3) & ~3
        if namesize < 1 or pos + size > len(data):
            raise ValueError("invalid newc member length")
        yield name, mode, data[pos:pos + size]
        pos = (pos + size + 3) & ~3


def elf(data):
    if len(data) < 64 or data[:6] != b"\x7fELF\x02\x01" or data[18:20] != b"\xb7\x00":
        raise ValueError("runtime member must be ARM64 ELF")
    return data


def pack(args):
    runtime = args.runtime_cpio.read_bytes()
    base = args.inventory_cpio.read_bytes()
    base_members = {name: data for name, _, data in cpio_members(base)}
    if ("grizzly-inventory/gpt-scan-only" not in base_members
            or "grizzly-inventory/test-root.ext4" in base_members
            or base_members.get("init") != (HERE / "stock-inventory-init").read_bytes()):
        raise ValueError("expected the current Grizzly GPT-only inventory initramfs")
    loader = "lib/ld-musl-aarch64.so.1"
    wanted = {*TOOLS, *(f"usr/lib/{name}" for name in LIBRARIES), loader}
    extracted = {name: elf(data) for name, mode, data in cpio_members(runtime)
                 if name in wanted and stat.S_ISREG(mode)}
    if extracted.keys() != wanted or extracted[loader] != base_members.get(loader):
        raise ValueError("archived runtime members or the matching musl loader are missing")
    client = args.client_public_key.read_text().strip().split()
    if len(client) < 2 or client[0] != "ssh-ed25519" or not re.fullmatch(r"[A-Za-z0-9+/=]+", client[1]):
        raise ValueError("expected an Ed25519 public client key")
    args.output.mkdir(mode=0o700)
    with TemporaryDirectory(dir=args.output) as temporary:
        root = Path(temporary)

        def put(name, data, mode=0o644):
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            path.chmod(mode)

        for name in TOOLS:
            put(f"grizzly-systemd/{Path(name).name}", extracted[name], 0o755)
        for name in LIBRARIES:
            put(f"grizzly-systemd/lib/{name}", extracted[f"usr/lib/{name}"], 0o755)
        for name, target in ALIASES.items():
            (root / "grizzly-systemd/lib" / name).symlink_to(target)
        put("grizzly-systemd/root.sh", (HERE / "systemd-ram-root.sh").read_bytes())
        put("grizzly-systemd/return", elf(args.return_executable.read_bytes()), 0o755)
        put("grizzly-systemd/root.raw.meta", ROOT)
        put("grizzly-systemd/host-key", args.host_key.read_bytes(), 0o600)
        put("grizzly-systemd/systemd/check.sh", (HERE / "systemd-root-check.sh").read_bytes())
        for name in ("grizzly-userspace.service", "grizzly-userspace.target"):
            put(f"grizzly-systemd/systemd/units/{name}", (HERE / name).read_bytes())
        if args.openssh_host_key:
            live = "grizzly-systemd/systemd"
            put(f"{live}/openssh-host-key", args.openssh_host_key.read_bytes(), 0o600)
            put(f"{live}/authorized_keys", (" ".join(client[:2]) + "\n").encode(), 0o600)
            put(f"{live}/sshd-live.conf", (HERE / "sshd-live.conf").read_bytes())
            name = "grizzly-live-ssh.service"
            put(f"{live}/units/{name}", (HERE / name).read_bytes())
            target = root / live / "units/grizzly-userspace.target"
            with target.open("a") as config:
                config.write(f"Wants={name}\nAfter={name}\n")
        (root / "grizzly-systemd/systemd/empty").mkdir()
        put("etc/passwd", b"root:x:0:0:root:/root:/bin/sh\n")
        put("etc/group", b"root:x:0:\n")
        put("root/.ssh/authorized_keys", (" ".join(client[:2]) + "\n").encode(), 0o600)
        for name in ("root", "root/.ssh"):
            (root / name).chmod(0o700)
        (root / "bin").mkdir()
        (root / "bin/sh").symlink_to("/grizzly-inventory/busybox")
        overlay = args.output / "systemd-overlay.cpio"
        subprocess.run(["bsdtar", "--format", "newc", "--uid", "0", "--gid", "0",
                        "-cf", overlay, "-C", root, "grizzly-systemd", "bin", "etc", "root"], check=True)
    archive = args.output / "inventory.cpio"
    compressed = args.output / "inventory.cpio.lz4"
    archive.write_bytes(base + overlay.read_bytes())
    subprocess.run(["lz4", "-l", "-12", archive, compressed], check=True)
    if subprocess.check_output(["lz4", "-dc", compressed]) != archive.read_bytes():
        raise ValueError("systemd RAM-root archive failed the LZ4 round-trip")


if __name__ == "__main__":
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ("inventory-cpio", "runtime-cpio", "return-executable", "host-key", "client-public-key"):
        parser.add_argument(f"--{option}", type=Path, required=True)
    parser.add_argument("--openssh-host-key", type=Path)
    parser.add_argument("output", type=Path)
    try:
        pack(parser.parse_args())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"systemd RAM-root packaging failed: {error}\n")
