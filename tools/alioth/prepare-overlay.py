#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepare local-only F3 firmware/ALSA inputs. Never download or touch a phone."""
import json
from pathlib import Path
import shutil
import tarfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "out/alioth"


def main():
    reference = OUT / "reference"
    overlay = OUT / "root-overlay"
    # Rebuild our staging tree, including firmware alias symlinks, from the
    # immutable reference. copytree cannot overwrite an existing symlink.
    if overlay.exists():
        shutil.rmtree(overlay)
    overlay.mkdir(exist_ok=True)
    firmware = overlay / "usr/lib/firmware"
    shutil.copytree(reference / "firmware/firmware", firmware, dirs_exist_ok=True, symlinks=True)
    ucm = overlay / "usr/share/alsa/ucm2"
    shutil.copytree(reference / "ucm2/ucm2/Xiaomi/alioth", ucm / "Xiaomi/alioth", dirs_exist_ok=True)
    (ucm / "conf.d/sm8250").mkdir(parents=True, exist_ok=True)
    link = ucm / "conf.d/sm8250/xiaomi-alioth.conf"
    if not link.exists() and not link.is_symlink():
        link.symlink_to("../../Xiaomi/alioth/alioth.conf")
    (overlay / "etc").mkdir(exist_ok=True)
    (overlay / "etc/fstab").write_text("# POCO F3 Omarchy: userdata only\nLABEL=omamobile-root / ext4 rw,noatime 0 1\n")
    # The Pixel device package supplied this common pacman include. Keep the
    # F3 image's local signed repository usable without installing that package.
    mirror = overlay / "etc/pacman.d/omamobile-mirrorlist"
    mirror.parent.mkdir(parents=True, exist_ok=True)
    mirror.write_text("# Local signed Omarchy Mobile packages\nServer = file:///var/lib/omamobile/repo/$arch\n")
    # No addresses, calibration dumps, accounts or credentials enter this overlay.
    with tarfile.open(OUT / "root-overlay.tar", "w") as archive:
        for path in sorted(overlay.rglob("*")):
            info = archive.gettarinfo(str(path), arcname=str(path.relative_to(overlay)))
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            if path.is_file() and not path.is_symlink():
                with path.open("rb") as source:
                    archive.addfile(info, source)
            else:
                archive.addfile(info)
    print("Prepared local F3 firmware and ALSA overlay", flush=True)


if __name__ == "__main__":
    main()
