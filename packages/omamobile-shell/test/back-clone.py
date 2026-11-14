#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Qt clone-registry probe using the exact candidate Back.qml client Loader."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('package', type=Path, nargs='?', default=Path(__file__).resolve().parents[1])
parser.add_argument('--negative', action='store_true')
args = parser.parse_args()
src = args.package / 'plugins/omamobile.back'
source = (src / 'Back.qml').read_text()
client_id = source.index('id: backLink')
start = source.rindex('Loader {', 0, client_id)
depth = 0
for end in range(source.index('{', start), len(source)):
    depth += (source[end] == '{') - (source[end] == '}')
    if depth == 0:
        loader = source[start:end + 1]
        break
else:
    raise AssertionError('unterminated Loader')
if args.negative:
    loader = loader.replace('../omamobile.back/BackLinkClient.qml', 'BackLinkClient.qml')
runner = shutil.which('qmltestrunner6') or shutil.which('/usr/lib/qt6/bin/qmltestrunner')
if not runner:
    raise SystemExit(77)
with tempfile.TemporaryDirectory(prefix='back-clone-') as tmp:
    directory = Path(tmp)
    for name in ('omamobile.back', 'personal.back', 'runtime'):
        (directory / name).mkdir(mode=0o700)
    # The personal directory has its own copy, just as plugin clone creates.
    for name in ('omamobile.back', 'personal.back'):
        for filename in ('BackLink.js', 'BackLinkClient.qml'):
            shutil.copyfile(src / filename, directory / name / filename)
    (directory / 'personal.back/Reader.qml').write_text('import QtQuick\nItem {\n' + loader + '\nfunction back() { return backLink.item ? backLink.item.back() : "unknown" }\n}\n')
    (directory / 'tst_clone.qml').write_text('''import QtQuick
import QtTest
import "omamobile.back/BackLink.js" as Original
TestCase {
 name:"FixedCloneRegistry"; when:windowShown
 Loader { id:publisher; source:"omamobile.back/BackLinkClient.qml" }
 Loader { id:reader; source:"personal.back/Reader.qml" }
 function test_sameCanonicalClient() {
  var hits=0
  publisher.item.name="panel"
  publisher.item.handler=function(){hits++;return true}
  publisher.item.active=true
  compare(Original.names().join(","),"panel")
  compare(reader.item.back(),"panel")
  compare(hits,1)
  publisher.item.active=false
  compare(reader.item.back(),"")
 }
}
''')
    env = os.environ.copy()
    env.update(QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='generic', XDG_RUNTIME_DIR=str(directory / 'runtime'))
    env.pop('QT_PLUGIN_PATH', None)
    env.pop('QT_QPA_GENERIC_PLUGINS', None)
    result = subprocess.run([runner, '-input', str(directory / 'tst_clone.qml')], env=env, capture_output=True, text=True, timeout=10)
    print(result.stdout + result.stderr, end='')
    raise SystemExit(result.returncode)
