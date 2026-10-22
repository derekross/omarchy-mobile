#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Make this owner's local first-boot image from the checked generic F3 root."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import secrets
import subprocess
import os
import tempfile
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[2]


def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as src:
        for chunk in iter(lambda: src.read(4 * 1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--root-image", type=Path, required=True)
    p.add_argument("--out", type=Path, default=ROOT / "out/alioth/images")
    p.add_argument("--username", help="Owner login, required on the first local provisioning run")
    p.add_argument("--timezone", help="IANA timezone (default UTC for a new owner)")
    args = p.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    out.chmod(0o700)
    private = ROOT / "keys"
    private.mkdir(mode=0o700, exist_ok=True)
    private.chmod(0o700)
    settings = private / "alioth-credentials.json"
    if settings.exists():
        owner = json.loads(settings.read_text())
        if args.username and args.username != owner["username"]:
            p.error("username differs from the existing private owner settings")
        if args.timezone and args.timezone != owner["timezone"]:
            p.error("timezone differs from the existing private owner settings")
    else:
        if not args.username or not re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", args.username):
            p.error("--username must be a valid local login")
        try:
            ZoneInfo(args.timezone or "UTC")
        except (ValueError, KeyError):
            p.error("--timezone must name an installed IANA timezone")
        owner = {"username": args.username, "temporary_pin": str(100000 + secrets.randbelow(900000)),
                 "hostname": "poco-f3-omarchy", "timezone": args.timezone or "UTC"}
    try:
        ZoneInfo(owner["timezone"])
    except (ValueError, KeyError):
        p.error("saved timezone is not an installed IANA timezone")
    password_hash = subprocess.check_output(["openssl", "passwd", "-6", "-stdin"],
                                             input=owner["temporary_pin"] + "\n", text=True).strip()
    public_key = (private / "alioth_ed25519.pub").read_text().strip()
    conf = private / "alioth-firstboot.conf"
    conf.write_text(f"USERNAME={owner['username']}\nPASSWORD_HASH={password_hash}\n"
                    f"HOSTNAME={owner['hostname']}\nTIMEZONE={owner['timezone']}\n"
                    f"SSH_KEY={public_key}\nCREDENTIAL=pin\n")
    conf.chmod(0o600)
    # Validate against the target's accounts, not the build host's users.
    with tempfile.TemporaryDirectory() as directory:
        fixture = Path(directory)
        (fixture / "etc").mkdir()
        passwd = subprocess.check_output(["debugfs", "-R", "cat /etc/passwd", str(args.root_image.resolve())],
                                         stderr=subprocess.DEVNULL)
        (fixture / "etc/passwd").write_bytes(passwd)
        zone = fixture / "usr/share/zoneinfo" / owner["timezone"]
        zone.parent.mkdir(parents=True, exist_ok=True)
        zone.touch()
        checked_conf = subprocess.run(["bash", str(ROOT / "packages/omamobile-firstboot/bin/omamobile-firstboot"),
                                       "--check", str(conf)], capture_output=True, text=True,
                                      env={**os.environ, "OMAMOBILE_FIRSTBOOT_ROOT": str(fixture)})
    if checked_conf.returncode:
        raise SystemExit("Firstboot rejected the owner settings; no root image changed: " + checked_conf.stderr.strip())
    if not settings.exists():
        settings.write_text(json.dumps(owner, indent=2) + "\n")
        settings.chmod(0o600)
    target = out / "rootfs.img"
    subprocess.run(["cp", "--sparse=always", "--reflink=auto", str(args.root_image.resolve()), str(target)], check=True)
    target.chmod(0o600)
    commands = private / "alioth-provision.debugfs"
    def quoted(path):
        value = str(path)
        if any(ord(c) < 32 for c in value):
            raise ValueError("Control characters are unsupported in image paths")
        return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'
    commands.write_text("\n".join([
        "mkdir /etc/omamobile", "mkdir /root/.ssh",
        f"write {quoted(conf)} /etc/omamobile/firstboot.conf",
        f"write {quoted(private / 'alioth_ed25519.pub')} /root/.ssh/authorized_keys",
        "set_inode_field /etc/omamobile/firstboot.conf mode 0100600",
        "set_inode_field /etc/omamobile/firstboot.conf uid 0",
        "set_inode_field /etc/omamobile/firstboot.conf gid 0",
        "set_inode_field /root/.ssh mode 040700",
        "set_inode_field /root/.ssh uid 0", "set_inode_field /root/.ssh gid 0",
        "set_inode_field /root/.ssh/authorized_keys mode 0100600",
        "set_inode_field /root/.ssh/authorized_keys uid 0",
        "set_inode_field /root/.ssh/authorized_keys gid 0", ""]))
    commands.chmod(0o600)
    result = subprocess.run(["debugfs", "-w", "-f", str(commands), str(target)], capture_output=True, text=True)
    (private / "alioth-provision.log").write_text(result.stdout + result.stderr)
    if result.returncode:
        raise SystemExit("Could not provision local image; inspect private log")
    for source, name in ((conf, "/etc/omamobile/firstboot.conf"),
                         (private / "alioth_ed25519.pub", "/root/.ssh/authorized_keys")):
        content = subprocess.check_output(["debugfs", "-R", f"cat {name}", str(target)], stderr=subprocess.DEVNULL)
        if content != source.read_bytes():
            raise SystemExit(f"Image read-back differs for {name}")
    checked = subprocess.run(["e2fsck", "-fn", str(target)], capture_output=True, text=True)
    (out / "rootfs-fsck.txt").write_text(checked.stdout + checked.stderr)
    if checked.returncode:
        raise SystemExit("Personalized root image did not pass e2fsck")
    sparse = out / "rootfs-sparse.img"
    subprocess.run(["img2simg", str(target), str(sparse), "4096"], check=True)
    sparse.chmod(0o600)
    manifest = {"device": "alioth", "personalized": True, "username": owner["username"],
                "hostname": owner["hostname"], "timezone": owner["timezone"],
                "ssh_public_key_sha256": hashlib.sha256((public_key + "\n").encode()).hexdigest(),
                "generic_root_sha256": sha256(args.root_image),
                "rootfs_bytes": target.stat().st_size, "rootfs_sha256": sha256(target),
                "rootfs_sparse_bytes": sparse.stat().st_size, "rootfs_sparse_sha256": sha256(sparse),
                "filesystem_checked": True, "hardware_boot_tested": False, "phone_accessed": False}
    (out / "ROOT-MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("Owner image prepared; temporary PIN remains in gitignored keys/alioth-credentials.json", flush=True)


if __name__ == "__main__":
    main()
