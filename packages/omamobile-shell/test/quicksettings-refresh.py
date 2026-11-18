#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the production open-refresh queue with real Qt bindings."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--burst-negative", action="store_true")
    args = parser.parse_args()
    source = args.source.read_text()
    start = source.index("  // Open-time reads wait for presentation to settle.")
    end = source.index("  // Host-initiated close", start)
    scheduler = source[start:end]
    if args.burst_negative:
        scheduler = scheduler.replace("openRefreshTimer.start()", "root.runOpenRefresh()")
    template = Path(__file__).with_name("quicksettings-refresh.qml.in").read_text()
    if template.count("SCHEDULER") != 1:
        raise RuntimeError("Unexpected scheduler template")
    runner = shutil.which("qmltestrunner6") or shutil.which("/usr/lib/qt6/bin/qmltestrunner") or shutil.which("/usr/lib64/qt6/bin/qmltestrunner") or shutil.which("qmltestrunner")
    if not runner:
        print("quicksettings-refresh: no qmltestrunner")
        return 77
    with tempfile.TemporaryDirectory(prefix="qs-refresh-") as directory:
        root = Path(directory)
        runtime = root / "runtime"
        runtime.mkdir(mode=0o700)
        test = root / "tst_queue.qml"
        test.write_text(template.replace("SCHEDULER", scheduler))
        env = os.environ.copy()
        env.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_QPA_PLATFORMTHEME="generic", XDG_RUNTIME_DIR=str(runtime))
        env.pop("QT_PLUGIN_PATH", None)
        env.pop("QT_QPA_GENERIC_PLUGINS", None)
        result = subprocess.run([runner, "-input", str(test)], env=env, capture_output=True, text=True, timeout=12)
        print(result.stdout + result.stderr, end="")
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
