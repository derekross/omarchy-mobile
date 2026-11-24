#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise actual QuickSettings geometry expressions under real Qt bindings."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def expression(section, name):
    pattern = r"^      readonly property real " + name + r": (.+)$"
    match = re.search(pattern, section, re.MULTILINE)
    if not match:
        raise RuntimeError("Missing production property " + name)
    return match[1].replace("Style.", "style.")


def fixture(source, baseline):
    section = source[source.index("    // ---------- The notification shade:"):]
    position = re.search(r"^      y: (Style.gapsOut.+)$", source, re.MULTILINE)
    if not position:
        raise RuntimeError("Missing production sheet position")

    if baseline:
        resting = (
            "root.wide ? style.gapsOut : "
            "style.gapsOut + sheet.height + style.spacing.lg"
        )
        churn = "verify(root.roomChanges > 3);\n        verify(root.heightChanges > 3);"
        drag = "compare(shade.height, before + 50);"
    else:
        resting = expression(section, "restingTop")
        churn = "compare(root.roomChanges, 0);\n        compare(root.heightChanges, 0);"
        drag = "compare(shade.height, before);"

    replacements = {
        "POSITION": position[1].replace("Style.", "style."),
        "SHADETOP": expression(section, "shadeTop"),
        "RESTING": resting,
        "ROOM": expression(section, "room"),
        "CHURN": churn,
        "DRAG": drag,
    }
    template = Path(__file__).with_name("quicksettings-shade-layout.qml.in").read_text()
    for placeholder, value in replacements.items():
        if template.count(placeholder) != 1:
            raise RuntimeError("Unexpected template placeholder " + placeholder)
        template = template.replace(placeholder, value)
    return template


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--baseline", action="store_true")
    args = parser.parse_args()
    runner = (
        shutil.which("qmltestrunner6")
        or shutil.which("/usr/lib/qt6/bin/qmltestrunner")
        or shutil.which("/usr/lib64/qt6/bin/qmltestrunner")
        or shutil.which("qmltestrunner")
    )
    if not runner:
        print("quicksettings-shade-layout: no qmltestrunner")
        return 77
    qml = fixture(args.source.read_text(), args.baseline)

    with tempfile.TemporaryDirectory(prefix="public-shade-") as directory:
        root = Path(directory)
        runtime = root / "runtime"
        runtime.mkdir(mode=0o700)
        test = root / "tst_shade.qml"
        test.write_text(qml)

        environment = os.environ.copy()
        environment.update(
            QT_QPA_PLATFORM="offscreen",
            QT_QUICK_BACKEND="software",
            QT_QPA_PLATFORMTHEME="generic",
            GSETTINGS_BACKEND="memory",
            XDG_RUNTIME_DIR=str(runtime),
        )
        environment.pop("QT_QPA_GENERIC_PLUGINS", None)
        environment.pop("QT_PLUGIN_PATH", None)
        result = subprocess.run(
            [runner, "-input", str(test)],
            env=environment,
            capture_output=True,
            text=True,
            timeout=5,
        )
        print(result.stdout + result.stderr, end="")
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
