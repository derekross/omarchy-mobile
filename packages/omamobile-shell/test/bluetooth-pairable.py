#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""The Bluetooth panel's pairing window with real Qt bindings: the panel's
code from its lifecycle section to its surface, spliced into
test/bluetooth-pairable.qml.in, run by qmltestrunner offscreen. Exits 77
without qmltestrunner."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

here = Path(__file__).resolve().parent
plugin = here.parent / "plugins" / "omamobile.quicksettings"


def main():
    source = (Path(sys.argv[1]) if len(sys.argv) > 1 else plugin / "BluetoothPanel.qml").read_text()
    start = source.index("  // ---------------------------------------------------------------- lifecycle")
    end = source.index("  // ---------------------------------------------------------------- surface", start)
    template = (here / "bluetooth-pairable.qml.in").read_text()
    if template.count("\n    @PANEL@\n") != 1:
        raise RuntimeError("Unexpected template")
    runner = (shutil.which("qmltestrunner6") or shutil.which("/usr/lib/qt6/bin/qmltestrunner")
              or shutil.which("/usr/lib64/qt6/bin/qmltestrunner") or shutil.which("qmltestrunner"))
    if not runner:
        print("bluetooth-pairable: no qmltestrunner")
        return 77
    with tempfile.TemporaryDirectory(prefix="bt-pairable-") as directory:
        root = Path(directory)
        (root / "quicksettings").mkdir()
        shutil.copy(plugin / "BluetoothModel.js", root / "quicksettings")
        runtime = root / "runtime"
        runtime.mkdir(mode=0o700)
        test = root / "tst_pairable.qml"
        test.write_text(template.replace("\n    @PANEL@\n", "\n" + source[start:end] + "\n"))
        env = os.environ.copy()
        env.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_QPA_PLATFORMTHEME="generic",
                   XDG_RUNTIME_DIR=str(runtime), QML_DISABLE_DISK_CACHE="1")
        env.pop("QT_PLUGIN_PATH", None)
        env.pop("QT_QPA_GENERIC_PLUGINS", None)
        result = subprocess.run([runner, "-input", str(test)], env=env, capture_output=True, text=True, timeout=30)
        print(result.stdout + result.stderr, end="")
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
