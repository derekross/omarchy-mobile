#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Actual complete UserWidgetCell+Loader, no backend or provider process."""
from pathlib import Path
import argparse,hashlib,os,re,shutil,subprocess,tempfile
here=Path(__file__).resolve().parent
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package-root',type=Path,default=here.parent);a=p.parse_args();package=a.package_root.resolve()
runner=shutil.which('qmltestrunner6') or '/usr/lib/qt6/bin/qmltestrunner'
if not Path(runner).is_file():print('SKIP no qmltestrunner');raise SystemExit(77)
plugin=package/'plugins/omamobile.home';actual=(plugin/'UserWidgetCell.qml').read_bytes();before=hashlib.sha256(actual).hexdigest()
with tempfile.TemporaryDirectory(prefix='widget-context-') as directory:
 root=Path(directory);work=root/'positive';work.mkdir();stubs=root/'stubs'
 shutil.copytree(package/'test/qml-stubs/qs/Commons',stubs/'qs/Commons')
 # Existing inert singleton, no Quickshell native plugin or executable.
 (stubs/'Quickshell').mkdir(parents=True)
 shutil.copyfile(package/'test/qml-stubs/Quickshell/Quickshell.qml',stubs/'Quickshell/Quickshell.qml')
 (stubs/'Quickshell/qmldir').write_text('module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n')
 for name in ['UserWidgetCell.qml','UserWidgets.js','Readable.js']:shutil.copyfile(plugin/name,work/name)
 (work/'WidgetHost.qml').write_text('import QtQuick\nQtObject{property var home:null;property string instanceId:"";property string widgetId:"";property string dir:"";property var capabilities:[];property bool shown:true}\n')
 for kind in ['readonly','writable']:
  shown='readonly property bool shown:host?host.shown:false' if kind=='readonly' else 'property bool shown:false'
  (work/(kind+'.qml')).write_text('import QtQuick\nItem{objectName:"loadedWidget";property var host:null;property var settings:({});property bool editing:false;property int cellsWide:1;property int cellsHigh:1;'+shown+'}\n')
 shutil.copyfile(here/'user-widget-context.qml',work/'tst_context.qml')
 env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QML_IMPORT_PATH=str(stubs),QML_DISABLE_DISK_CACHE='1',QT_QPA_PLATFORMTHEME='generic',GSETTINGS_BACKEND='memory',LC_ALL='C.UTF-8')
 def run(folder):return subprocess.run([runner,'-input',str(folder),'-o','-,txt'],env=env,capture_output=True,text=True,timeout=20)
 result=run(work)
 assert result.returncode==0 and 'Totals: 8 passed, 0 failed' in result.stdout and 'QWARN' not in result.stdout,result.stdout+result.stderr[-600:]
 # Historical blind Loader assignment is restored only in the TEMP copy.
 inverse=root/'inverse';shutil.copytree(work,inverse)
 source=(inverse/'UserWidgetCell.qml').read_text();fixed='var bind = function(name, value) { frame.bindContext(w, name, value) }'
 assert source.count(fixed)==1,'Test requires the actual optional-property compatibility fix'
 (inverse/'UserWidgetCell.qml').write_text(source.replace(fixed,'var bind = function(name, value) { if (name in w) w[name] = value }'))
 negative=run(inverse)
 assert negative.returncode!=0 and 'Cannot assign to read-only property' in negative.stdout and 'shown' in negative.stdout,negative.stdout
assert hashlib.sha256((plugin/'UserWidgetCell.qml').read_bytes()).hexdigest()==before,'Source changed during test'
print('PASS actual complete UserWidgetCell+Loader: 8 Qt checks, no warnings; blind shown assignment negative fails; other errors propagate')
