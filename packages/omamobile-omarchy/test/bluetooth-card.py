#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Patch 0036's pairing helper in the bar's Bluetooth card, with real Qt
bindings: the section of the patched Panel.qml from "the phone's pairing
helper" to its end, spliced into test/bluetooth-card.qml.in with the patched
Model.js, run by qmltestrunner offscreen against a stand-in adapter and
helper process. Exits 77 without qmltestrunner.
  test/bluetooth-card.py SHELL_DIR"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

here = Path(__file__).resolve().parent
START = "  // ---------------------------------------------------------------- the phone's pairing helper\n"
END = "  // ---------------------------------------------------------------- end of the pairing helper\n"


def main():
    card = Path(sys.argv[1]) / "plugins" / "panels" / "bluetooth"
    source = (card / "Panel.qml").read_text()
    start = source.index(START)
    end = source.index(END, start)
    template = (here / "bluetooth-card.qml.in").read_text()
    if template.count("\n    @SECTION@\n") != 1:
        raise RuntimeError("Unexpected template")
    runner = (shutil.which("qmltestrunner6") or shutil.which("/usr/lib/qt6/bin/qmltestrunner")
              or shutil.which("/usr/lib64/qt6/bin/qmltestrunner") or shutil.which("qmltestrunner"))
    if not runner:
        print("bluetooth-card: no qmltestrunner")
        return 77
    with tempfile.TemporaryDirectory(prefix="bt-card-") as directory:
        root = Path(directory)
        (root / "bluetooth").mkdir()
        shutil.copy(card / "Model.js", root / "bluetooth")
        runtime = root / "runtime"
        runtime.mkdir(mode=0o700)
        test = root / "tst_bluetooth_card.qml"
        test.write_text(template.replace("\n    @SECTION@\n", "\n" + source[start:end] + "\n"))
        env = os.environ.copy()
        env.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_QPA_PLATFORMTHEME="generic",
                   XDG_RUNTIME_DIR=str(runtime), QML_DISABLE_DISK_CACHE="1", LC_ALL="C", LANG="C")
        env.pop("QT_PLUGIN_PATH", None)
        env.pop("QT_QPA_GENERIC_PLUGINS", None)
        result = subprocess.run([runner, "-input", str(test)], env=env, capture_output=True, text=True, timeout=60)
        print(result.stdout + result.stderr, end="")
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
