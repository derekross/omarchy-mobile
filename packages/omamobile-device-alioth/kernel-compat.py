#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Limit pacman's legacy-kernel workaround to its filesystem sandbox."""
import ctypes
import errno
import os
from pathlib import Path

BLOCK = ("# omamobile-alioth: reference kernel lacks Landlock.\n"
         "# DownloadUser and syscall filtering remain enabled.\n"
         "DisableSandboxFilesystem\n")


def configure(text, abi):
    text = text.replace(BLOCK, "")
    if abi > 0:
        return text
    if "DisableSandboxFilesystem" in text:
        return text  # preserve a separately managed setting
    if text.count("[options]\n") != 1:
        raise ValueError("Expected one pacman [options] section")
    return text.replace("[options]\n", "[options]\n" + BLOCK, 1)


def main():
    if os.uname().machine != "aarch64":
        raise SystemExit("This helper requires the alioth ARM64 kernel")
    libc = ctypes.CDLL(None, use_errno=True)
    abi = libc.syscall(444, 0, 0, 1)
    if abi < 0 and ctypes.get_errno() != errno.ENOSYS:
        raise SystemExit("Unexpected Landlock query failure; pacman config unchanged")
    path = Path("/etc/pacman.conf")
    before = path.read_text()
    after = configure(before, abi)
    if before != after:
        backup = path.with_name("pacman.conf.before-alioth-compat")
        if not backup.exists():
            backup.write_text(before)
            backup.chmod(0o600)
        path.write_text(after)


if __name__ == "__main__":
    main()
