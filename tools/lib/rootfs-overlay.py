#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Extract a local runtime overlay with Python's path/link containment checks."""
from pathlib import Path, PurePosixPath
import sys
import tarfile


def extract(archive, target):
    target = Path(target).resolve()
    if target == Path('/') or not target.is_dir():
        raise ValueError('An existing staging directory is required')
    with tarfile.open(archive) as source:
        for entry in source:
            path = PurePosixPath(entry.name)
            if path.is_absolute() or '..' in path.parts:
                raise ValueError('Unsafe overlay path')
            if not (entry.isdir() or entry.isfile() or entry.issym()):
                raise ValueError('Overlay may contain only files, directories and symlinks')
        source.extractall(target, filter='data')


if __name__ == '__main__':
    if len(sys.argv) != 4 or sys.argv[1] != 'extract':
        raise SystemExit('Usage: rootfs-overlay.py extract ARCHIVE STAGING_DIRECTORY')
    extract(sys.argv[2], sys.argv[3])
