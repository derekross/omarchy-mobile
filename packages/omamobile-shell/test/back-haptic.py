#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise exact candidate handlers in Qt; never invoke hardware feedback."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

p = Path(__file__).parent
parser = argparse.ArgumentParser()
parser.add_argument("--negative", action="store_true")
args = parser.parse_args()
source = (p.parent / "plugins/omamobile.back/Back.qml").read_text()


def handler(name):
    start = source.index(name + ": {") + len(name + ": ")
    depth = 0
    for end in range(start, len(source)):
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
            if depth == 0:
                return source[start:end + 1]
    raise AssertionError("unterminated handler")


h = {"armed": handler("onArmedChanged"), "active": handler("onActiveChanged")}
if args.negative:
    h["armed"] = h["armed"].replace("armed && !feedbackSent", "armed")

qml='''import QtQuick
import QtTest
TestCase {
 id:root;name:"BackThresholdFeedback";when:windowShown;visible:true;width:100;height:100
 property int ticks:0
 property int backs:0
 function haptic(){ticks++}
 function back(){backs++}
 QtObject {id:win;property bool rightEdge:false}
 QtObject {id:centroid;property point position:Qt.point(0,20)}
 QtObject {
 id:swipe
 property bool active:false
 property bool armed:false
 property bool wasArmed:false
 property bool feedbackSent:false
 property real atY:0
 onArmedChanged: ARMED
 onActiveChanged: ACTIVE
 }
 function init(){swipe.armed=false;swipe.active=false;ticks=0;backs=0;win.rightEdge=false}
 function test_oncePerGesture(){swipe.active=true;swipe.armed=true;compare(ticks,1);swipe.armed=false;swipe.armed=true;compare(ticks,1);swipe.active=false;compare(backs,1)}
 function test_unarmedAndInactive(){swipe.active=true;compare(ticks,0);swipe.active=false;compare(backs,0);swipe.armed=true;compare(ticks,0)}
 function test_nextGestureAndBothEdges(){for(var edge=0;edge<2;edge++){win.rightEdge=edge===1;swipe.active=true;swipe.armed=true;compare(ticks,edge+1);swipe.active=false;compare(backs,edge+1);swipe.armed=false}}
 function test_retreatBeforeRelease(){swipe.active=true;swipe.armed=true;swipe.armed=false;swipe.active=false;compare(ticks,1);compare(backs,0)}
}
'''.replace('ARMED',h['armed']).replace('ACTIVE',h['active'])
runner = (shutil.which("qmltestrunner6")
          or shutil.which("/usr/lib/qt6/bin/qmltestrunner")
          or shutil.which("/usr/lib64/qt6/bin/qmltestrunner"))
if not runner:
    raise SystemExit(77)
with tempfile.TemporaryDirectory(prefix="back-feedback-") as temporary:
    directory = Path(temporary)
    (directory / "runtime").mkdir(mode=0o700)
    (directory / "tst_back.qml").write_text(qml)
    env = os.environ.copy()
    env.update(
        QT_QPA_PLATFORM="offscreen",
        QT_QUICK_BACKEND="software",
        QT_QPA_PLATFORMTHEME="generic",
        XDG_RUNTIME_DIR=str(directory / "runtime"),
    )
    env.pop("QT_PLUGIN_PATH", None)
    env.pop("QT_QPA_GENERIC_PLUGINS", None)
    result = subprocess.run(
        [runner, "-input", str(directory / "tst_back.qml")],
        env=env, capture_output=True, text=True, timeout=5,
    )
    print(result.stdout + result.stderr, end="")
    raise SystemExit(result.returncode)
