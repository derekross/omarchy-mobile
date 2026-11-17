#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run quick settings' user-tiles section (QuickSettings.qml, from its
"user tiles" rule to the next) under qmltestrunner, with stand-ins for
Quickshell's Process and the choice page: the backends it builds, a missing
file, a tap, the chooser and the helper's argv. Exit 77 without
qmltestrunner."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

START = "  // ---------------------------------------------------------------- user tiles\n"
END = "  // ---------------------------------------------------------------- clock\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    source = args.source.read_text()
    start = source.index(START)
    section = source[start:source.index(END, start)]
    template = Path(__file__).with_name("quicksettings-user-tiles.qml.in").read_text()
    if template.count("SECTION") != 1:
        raise RuntimeError("Unexpected user-tiles template")
    runner = shutil.which("qmltestrunner6") or shutil.which("/usr/lib/qt6/bin/qmltestrunner") or shutil.which("/usr/lib64/qt6/bin/qmltestrunner") or shutil.which("qmltestrunner")
    if not runner:
        print("quicksettings-user-tiles: no qmltestrunner")
        return 77
    with tempfile.TemporaryDirectory(prefix="qs-user-tiles-") as directory:
        root = Path(directory)
        runtime = root / "runtime"
        runtime.mkdir(mode=0o700)
        shutil.copy(args.source.with_name("TilesModel.js"), root / "TilesModel.js")
        (root / "tst_user_tiles.qml").write_text(template.replace("SECTION", section))
        env = os.environ.copy()
        env.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_QPA_PLATFORMTHEME="generic", XDG_RUNTIME_DIR=str(runtime))
        env.pop("QT_PLUGIN_PATH", None)
        env.pop("QT_QPA_GENERIC_PLUGINS", None)
        result = subprocess.run([runner, "-input", str(root / "tst_user_tiles.qml")], env=env, capture_output=True, text=True, timeout=20)
        print(result.stdout + result.stderr, end="")
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
