#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Generate local build/SSH keys without changing the committed keyring."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def run(command, **kwargs):
    return subprocess.check_output(command, stderr=subprocess.PIPE, **kwargs)


def main():
    os.umask(0o077)
    private = ROOT / "keys/alioth"
    private.mkdir(mode=0o700, parents=True, exist_ok=True)
    private.chmod(0o700)
    ssh = private / "alioth_ed25519"
    if not ssh.exists():
        run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "alioth-local", "-f", str(ssh)])
    public = run(["ssh-keygen", "-y", "-f", str(ssh)])
    ssh.with_suffix(".pub").write_bytes(public)
    gnupg = private / "gnupg"
    gnupg.mkdir(mode=0o700, exist_ok=True)
    prefix = ["gpg", "--homedir", str(gnupg), "--batch"]
    fingerprint = private / "fingerprint"
    if not fingerprint.exists():
        existing = run(prefix + ["--with-colons", "--list-secret-keys"])
        if b"sec:" in existing:
            raise SystemExit("Existing signing keys without a selected fingerprint; choose one explicitly")
        run(prefix + ["--pinentry-mode", "loopback", "--passphrase", "", "--quick-gen-key",
                      "Local Omarchy Mobile build", "ed25519", "sign", "1y"])
        listing = run(prefix + ["--with-colons", "--list-secret-keys"]).decode()
        fingerprint.write_text(next(line.split(":")[9] for line in listing.splitlines()
                                    if line.startswith("fpr:")) + "\n")
    key = fingerprint.read_text().strip()
    run(prefix + ["--list-secret-keys", key])
    ring = private / "build-keyring"
    ring.mkdir(mode=0o700, exist_ok=True)
    (ring / "omamobile.gpg").write_bytes(run(prefix + ["--export-options", "export-minimal", "--export", key]))
    (ring / "omamobile-trusted").write_text(key + ":6:\n")
    (ring / "omamobile-revoked").write_text("")
    print("Local keys ready in ignored keys/alioth/. Set OMAMOBILE_KEYRING_DIR=$PWD/keys/alioth/build-keyring")
    print("Do not publish keys/, personalized images, backups or downloaded firmware")


if __name__ == "__main__":
    main()
