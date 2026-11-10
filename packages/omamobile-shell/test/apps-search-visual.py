#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Actual Search component, genuine Omarchy UI tokens, neutral offscreen data.

This is a component preview: no native layer-shell/OSK or phone is exercised.
Frames carry capture timestamps; their rate is not a device performance claim.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
PLUGIN = HERE.parent / 'plugins/omamobile.launcher'
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--theme', choices=('light', 'dark'), required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--record', action='store_true')
p.add_argument('--width', type=int, default=420)
p.add_argument('--height', type=int, default=900)
p.add_argument('--omarchy-shell', type=Path, default=Path('/usr/share/omarchy/shell'))
a = p.parse_args()
assert 320 <= a.width <= 1440 and 320 <= a.height <= 1440
out = a.output.resolve()
out.mkdir(parents=True, exist_ok=False)
frames = out / 'frames'
if a.record:
    frames.mkdir()
short = Path(tempfile.gettempdir()) / 'omamobile-search-preview'
short.mkdir(mode=0o700, exist_ok=True)
s = short.lstat()
assert stat.S_ISDIR(s.st_mode) and s.st_uid == os.geteuid() and stat.S_IMODE(s.st_mode) == 0o700
palette = {'dark': {'background': '#14171c', 'foreground': '#e5e9f0', 'accent': '#8ec5ff', 'red': '#ff99a5'},
           'light': {'background': '#f7f5ef', 'foreground': '#20252d', 'accent': '#2355a4', 'red': '#9d253a'}}[a.theme]
with tempfile.TemporaryDirectory(prefix='search-preview-', dir=short) as directory:
    root = Path(directory)
    app = root / 'app'
    app.mkdir()
    (app / 'launcher').mkdir()
    shutil.copytree(HERE / 'fixtures/apps-search-icons', app / 'icons')
    for name in ('AppsSearch.qml', 'SearchFocus.qml'):
        shutil.copyfile(PLUGIN / name, app / 'launcher' / name)
    for name in ('Commons', 'Ui'):
        target = a.omarchy_shell.resolve() / name
        assert target.is_dir(), f'Genuine Omarchy {name} is required'
        (app / name).symlink_to(target, target_is_directory=True)
    home = root / 'home'
    theme = home / '.local/state/omarchy/current/theme'
    theme.mkdir(parents=True)
    (theme / 'colors.toml').write_text(''.join(f'{key} = "{value}"\n' for key, value in palette.items()))
    (theme / 'shell.toml').write_text('[font]\nbase-size = 12\n')
    runtime = root / 'run'
    runtime.mkdir(mode=0o700)
    bindir = root / 'bin'
    bindir.mkdir()
    stub = bindir / 'hyprctl'
    stub.write_text('#!/usr/bin/python3\nimport sys,json\nvalues={"decoration:rounding":{"int":12},"animations:enabled":{"bool":True},"general:gaps_out":{"custom":"10 10 10 10"}}\nassert sys.argv[-1] in values\nprint(json.dumps(values[sys.argv[-1]]))\n')
    stub.chmod(0o700)
    qml = r'''
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.Commons as Commons
import "launcher"
ShellRoot {
  id: root
  property bool capturing: false
  property bool captureBusy: false
  property int frame: 0
  property double captureStart: Date.now()
  property string launched: ""
  QtObject {
    id: library
    property var entries: [({id:"example.calendar",name:"Calendar",comment:"Your plans at a glance",icon:"calendar"}),({id:"example.files",name:"Files",comment:"Browse and organise files",icon:"files"}),({id:"example.notes",name:"Notes",comment:"Ideas, lists and reminders",icon:"notes"}),({id:"example.photos",name:"Photos",comment:"Browse your pictures",icon:"photos"}),({id:"example.weather",name:"Weather",comment:"Today and the days ahead",icon:"weather"})]
    function sortedEntries(query) { return entries.filter(function(entry){return entry.name.toLowerCase().indexOf(query.toLowerCase())>=0}).map(function(entry){return {entry:entry}}) }
    function entryName(entry) { return entry.name }
    function iconSource(icon) { return Qt.resolvedUrl("icons/"+icon+".svg") }
  }
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: WIDTH
    implicitHeight: HEIGHT
    color: Commons.Color.menu.background
    Item {
      id: screen
      anchors.fill: parent
      // Neutral test scenery under the actual translucent component. This
      // is not a compositor blur or a capture of a private wallpaper.
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0; color: SCENERYTOP }
          GradientStop { position: 1; color: SCENERYBOTTOM }
        }
        Rectangle { x: -parent.width*.3; y: parent.height*.4; width: parent.width*1.8; height: parent.height; rotation: -23; radius: width*.4; color: SCENERYHILL }
      }
      SearchFocus { id: prime; opened: search.opened; backingWindowVisible: true; requestGeneration: search.focusGeneration }
      AppsSearch {
        id: search
        anchors.fill: parent
        anchors.bottomMargin: caption.height
        appLibrary: library
        // Offscreen fixtures cannot grant native layer-shell focus. Observe
        // component intent only; the phone must qualify that integration.
        surfaceActive: true
        inputReady: prime.inputReady
        onActivated: function(entry) { root.launched=entry.id }
      }
      Rectangle {
        id: caption
        anchors.bottom: parent.bottom
        width: parent.width
        height: 28
        color: Commons.Color.menu.background
        Text {
          anchors.fill: parent
          text: "Offscreen component · neutral fixtures"
          textFormat: Text.PlainText
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: Commons.Color.menu.text
          font.family: Commons.Style.font.family
          font.pixelSize: 11
        }
      }
      SignalSpy { id: inputSpy; target: search; signalName: "inputRequested" }
      TestCase {
        name: "SearchPreview"
        when: true
        property bool captured: false
        function shot(path) { captured=false;screen.grabToImage(function(image){verify(image.saveToFile(path));captured=true});tryCompare(this,"captured",true,2000) }
        function initTestCase() {
          qtest_results.startLogging()
          tryVerify(function(){return Commons.Color.menu.background.toString()===Quickshell.env("SEARCH_EXPECTED_BG")},3000)
          tryCompare(Commons.Style,"cornerRadius",12,3000)
        }
        function test_flow_and_theme() {
          root.capturing=Quickshell.env("SEARCH_RECORD")==="1"
          search.open("")
          tryCompare(inputSpy,"count",1,3000)
          tryCompare(prime,"mode","on-demand",1000)
          compare(search.entries.length,3)
          wait(220)
          var header=findChild(search,"searchHeader")
          verify(header.height <= Commons.Style.space(56))
          var inputField=findChild(search,"appsSearchInput")
          verify(inputField.mapToItem(search,0,0).y < Commons.Style.space(80))
          verify(inputField.height >= 44)
          verify(findChild(search,"searchResults").height > 100)
          shot(OPENSHOT)
          var field=findChild(search,"appsSearchInput")
          keyClick(Qt.Key_N);wait(170);keyClick(Qt.Key_O);wait(170)
          compare(search.query,"no")
          compare(search.entries.length,1)
          compare(search.entries[0].id,"example.notes")
          wait(300)
          shot(FILTERSHOT)
          keyClick(Qt.Key_A,Qt.ControlModifier);keyClick(Qt.Key_Z);keyClick(Qt.Key_Z)
          compare(search.entries.length,0)
          wait(120)
          shot(EMPTYSHOT)
          keyClick(Qt.Key_Return);compare(root.launched,"")
          keyClick(Qt.Key_A,Qt.ControlModifier);keyClick(Qt.Key_N);keyClick(Qt.Key_O)
          keyClick(Qt.Key_Return)
          compare(root.launched,"example.notes")
          verify(!search.opened)
          wait(220)
          search.open("")
          tryCompare(prime,"mode","on-demand",1000)
          tryVerify(function(){return field.activeFocus},1000)
          wait(250)
          var close=findChild(search,"searchClose")
          mouseClick(close,close.width/2,close.height/2)
          verify(!search.opened)
          search.open("")
          tryCompare(prime,"mode","on-demand",1000)
          wait(150)
          compare(field.font.family,Commons.Style.font.family)
          var inputSurface=findChild(search,"searchInputSurface")
          compare(inputSurface.radius,Commons.Style.cornerRadius)
          Commons.Style.applyRoundingJson('{"int":0}');compare(inputSurface.radius,0)
          Commons.Style.applyRoundingJson('{"int":12}');compare(inputSurface.radius,12)
          if (typeof Commons.Style.styleAlpha === "function") {
            var previousStyle=Commons.Style.styleOverrides
            Commons.Style.styleOverrides={"mobile-search-backdrop-alpha":0.73,"mobile-search-card-alpha":0.81}
            compare(search.backdropAlpha,0.73)
            compare(search.cardAlpha,0.81)
            Commons.Style.styleOverrides=previousStyle
          }
          if (typeof Commons.Style.duration === "function") {
            Commons.Style.reduceMotion=true;compare(search.transitionDuration,0)
            Commons.Style.reduceMotion=false
          } else compare(search.transitionDuration,140)
          wait(160)
        }
        function cleanupTestCase() {
          root.capturing=false
          tryCompare(root,"captureBusy",false,2000)
          console.log("SEARCH_PREVIEW_RESULT",qtest_results.failCount,qtest_results.passCount)
          qtest_results.stopLogging()
          Qt.quit()
        }
      }
    }
  }
  Timer {
    interval:33;repeat:true;running:root.capturing
    onTriggered: {
      if(root.captureBusy||root.frame>=300)return
      root.captureBusy=true
      var index=root.frame++
      screen.grabToImage(function(image){image.saveToFile(Quickshell.env("SEARCH_FRAME_DIR")+"/frame"+String(index).padStart(4,"0")+".png");console.log("SEARCH_FRAME",index,Date.now()-root.captureStart);root.captureBusy=false})
    }
  }
  Timer { interval:20000;running:true;onTriggered:Qt.quit() }
}
'''
    qml = qml.replace('WIDTH', str(a.width)).replace('HEIGHT', str(a.height))
    scenery = ('#283248', '#51415b', '#71647e') if a.theme == 'dark' else ('#d4e0e5', '#c7b8c8', '#afbdcc')
    for token, color in zip(('SCENERYTOP', 'SCENERYBOTTOM', 'SCENERYHILL'), scenery):
        qml = qml.replace(token, json.dumps(color))
    qml = qml.replace('OPENSHOT', json.dumps(str(out / 'search-open.png'))).replace('FILTERSHOT', json.dumps(str(out / 'search-filtered.png'))).replace('EMPTYSHOT', json.dumps(str(out / 'search-empty.png')))
    (app / 'shell.qml').write_text(qml)
    env = os.environ | {'HOME': str(home), 'XDG_CONFIG_HOME': str(home / '.config'), 'XDG_DATA_HOME': str(root / 'data'),
                        'XDG_CACHE_HOME': str(root / 'cache'), 'XDG_RUNTIME_DIR': str(runtime), 'QT_QPA_PLATFORM': 'offscreen',
                        'QT_QPA_PLATFORMTHEME': '', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QT_QUICK_BACKEND': 'software',
                        'QML_DISABLE_DISK_CACHE': '1', 'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/nonexistent',
                        'DBUS_SYSTEM_BUS_ADDRESS': 'unix:path=/nonexistent', 'PATH': str(bindir) + ':/usr/bin:/bin',
                        'SEARCH_RECORD': '1' if a.record else '0', 'SEARCH_EXPECTED_BG': palette['background'], 'SEARCH_FRAME_DIR': str(frames)}
    for name in ('WAYLAND_DISPLAY', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE'):
        env.pop(name, None)
    result = subprocess.run(['/usr/bin/quickshell', '--path', str(app / 'shell.qml'), '--no-color'], env=env, capture_output=True, text=True, timeout=25)
    log = result.stdout + result.stderr
    (out / 'qml-ui.log').write_text(log)
    print(log[-10000:])
    assert result.returncode == 0 and 'SEARCH_PREVIEW_RESULT 0 2' in log
    assert not any(word in log for word in ('ReferenceError:', 'TypeError:', 'Failed to load configuration'))
    captured = [(int(i), int(t)) for i, t in re.findall(r'SEARCH_FRAME (\d+) (\d+)', log)]
    if a.record:
        assert len(captured) > 15 and len(list(frames.glob('frame*.png'))) == len(captured)
        assert all(b[1] > a[1] for a, b in zip(captured, captured[1:]))
        (out / 'frames.json').write_text(json.dumps(captured) + '\n')
    (out / 'RESULT.json').write_text(json.dumps({'result': 'PASS', 'theme': a.theme, 'palette': palette, 'viewport': [a.width, a.height],
                                               'frames': len(captured), 'offscreen': True, 'phoneCapture': False, 'nativeLayerFocusQualified': False}, indent=2) + '\n')
