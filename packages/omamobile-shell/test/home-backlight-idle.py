#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Real Qt bindings/Timer from Home; fake FileView, no processes or hardware."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import sys

HERE = Path(__file__).resolve().parent
PLUGIN = HERE.parent / 'plugins/omamobile.home'
runner = shutil.which('qmltestrunner6') or shutil.which('/usr/lib/qt6/bin/qmltestrunner') or shutil.which('qmltestrunner')
if not runner:
    print('home-backlight-idle: no qmltestrunner', file=sys.stderr)
    sys.exit(77)
source = (PLUGIN / 'Home.qml').read_text()
# Extract production visibility bindings and the complete existing polling block.
app = re.search(r'^  readonly property bool appOnScreen:.*$', source, re.M).group()
shown = re.search(r'^  readonly property bool homeShown:.*$', source, re.M).group()
a = source.index('  // The panel is off when its backlight')
b = source.index('  // An OWL Input', a)
block = source[a:b]
# Discovery is unrelated to polling and would execute a host command: omit it.
x = block.index('  Process {'); y = block.index('  FileView {', x)
block = block[:x] + block[y:]
assert block.count('FileView {') == 1 and block.count('interval: 2000') == 1
block = block.replace('  FileView {', '  MockFileView {').replace('    interval: 2000', '    objectName: "backlightPoll"\n    interval: 30')
with tempfile.TemporaryDirectory(prefix='home-backlight-idle-') as tmp:
    work = Path(tmp)
    (work / 'MockFileView.qml').write_text('''import QtQuick
QtObject {
 property string path:""; property bool printErrors:false
 property int reads:0; property string value:"0"
 signal loaded()
 function text(){return value}
 function reload(){reads++;loaded()}
}
''')
    module = work / 'TestHyprland'; module.mkdir()
    (module / 'qmldir').write_text('module TestHyprland\nsingleton Hyprland 1.0 Hyprland.qml\n')
    (module / 'Hyprland.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var focusedWorkspace:null }\n')
    for name in ('HomeModel.js', 'owl/phone.js', 'owl/values.js'):
        shutil.copyfile(PLUGIN / name, work / Path(name).name)
    (work / 'HomePoll.qml').write_text('''import QtQuick
import TestHyprland
import "phone.js" as OwlPhone
import "HomeModel.js" as HomeModel
Item { id:root
 property var coveringLayers:({}); property real drawerProgress:0
 property alias reads:blPower.reads; property alias value:blPower.value
''' + app + '\n' + shown + '\n' + block + '\n}\n')
    shutil.copyfile(HERE / 'home-backlight-idle.qml', work / 'tst_home.qml')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
               QML_DISABLE_DISK_CACHE='1', GSETTINGS_BACKEND='memory')
    sys.exit(subprocess.run([runner, '-import', str(work), '-input', str(work / 'tst_home.qml')],
                           env=env, timeout=20).returncode)
