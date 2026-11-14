#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run candidate routing and panel callbacks in Qt, with key injection stubbed."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

pkg = Path(__file__).resolve().parents[1]


def function(path, name):
    source = path.read_text()
    start = source.index("  function " + name + "(")
    brace = source.index("{", start)
    depth = 0
    for end in range(brace, len(source)):
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
            if depth == 0:
                return source[start:end + 1]
    raise AssertionError("unterminated function")


back = function(pkg / "plugins/omamobile.back/Back.qml", "back")
back = back.replace("ToplevelManager.activeToplevel", "manager.activeToplevel").replace("Hyprland.activeToplevel", "hyprSource.activeToplevel").replace("Quickshell.execDetached", "root.record")
quick = function(pkg / "plugins/omamobile.quicksettings/QuickSettings.qml", "navigationBack").replace("function navigationBack", "function quickBack")
drawer = function(pkg / "plugins/omamobile.launcher/Launcher.qml", "navigationBack").replace("function navigationBack", "function drawerBack")
recents = function(pkg / "plugins/omamobile.switcher/Switcher.qml", "navigationBack").replace("function navigationBack", "function recentsBack")
qml = r'''import QtQuick
import QtTest
import "BackLink.js" as BackLink
import "BackModel.js" as BackModel
TestCase {
 id: root; name: "BrowserBackRouting"; when: windowShown
 property var calls: []
 property bool opened: false
 property bool editing: false
 property string query: ""
 property bool actionsOpen: false
 property string actionPage: ""
 property int dismissals: 0
 property int returns: 0
 Loader { id: backLink; source: Qt.resolvedUrl("../omamobile.back/BackLinkClient.qml") }
 QtObject { id: manager; property var activeToplevel: null }
 QtObject { id: hyprSource; property var activeToplevel: null }
 QtObject { id: input; property bool activeFocus: false }
 QtObject { id: wifiPicker; property bool opened: false; property string sheet: ""; function cancelSheet(){sheet=""} function backRequested(){opened=false; root.opened=true; root.returns++} }
 QtObject { id: bluetoothPanelItem; property bool opened: false; property string activeSheet: ""; function cancelSheet(){activeSheet=""} function backRequested(){opened=false; root.opened=true; root.returns++} }
 QtObject { id: recordPanelItem; property bool opened: false; function backRequested(){opened=false; root.opened=true; root.returns++} }
 function record(argv) { calls.push(argv) }
 function dismiss(speed) { opened=false; dismissals++ }
 function finishEditing() { editing=false }
 function closeActions() { actionsOpen=false }
 BACK
 QUICK
 DRAWER
 RECENTS
 function browser() { var w={appId:"chromium",activated:true,parent:null}; manager.activeToplevel=w; hyprSource.activeToplevel={wayland:w}; return w }
 function init() {
  backLink.active=true; tryVerify(function(){return backLink.item!==null})
  BackLink.clear(); calls=[]; opened=false; editing=false; query=""; input.activeFocus=false; actionsOpen=false; actionPage=""; dismissals=0; returns=0
  wifiPicker.opened=false; wifiPicker.sheet=""; bluetoothPanelItem.opened=false; bluetoothPanelItem.activeSheet=""; recordPanelItem.opened=false; browser()
 }
 function history() { compare(calls.length,1); compare(JSON.stringify(calls[0]),JSON.stringify(BackModel.BROWSER_BACK_ARGV)) }
 function fallback() { compare(calls.length,1); compare(JSON.stringify(calls[0]),JSON.stringify(BackModel.ESCAPE_ARGV)) }
 function test_bothEdgesBack() { var w=browser(); back("left",w); history(); calls=[]; back("right",w); history() }
 function test_changedAndUnknownFocus() { var w=browser(); browser(); back("",w); fallback(); calls=[]; manager.activeToplevel=null; back(); fallback() }
 function test_modalAndInactiveBrowser() { manager.activeToplevel.parent={}; back(); fallback(); calls=[]; browser().activated=false; back(); fallback() }
 function test_otherAppAndDisagreement() { manager.activeToplevel.appId="foot"; back(); fallback(); calls=[]; browser(); hyprSource.activeToplevel=null; back(); fallback() }
 Window { id: shellWindow; visible:true; width:20; height:20 }
 function test_staleApplicationActiveDoesNotBlockBrowser() { shellWindow.requestActivate(); tryCompare(Qt.application,"state",Qt.ApplicationActive); browser(); back(); history() }
 function test_missingCanonicalReaderFallsBack() { backLink.active=false; tryVerify(function(){return backLink.item===null}); back(); fallback() }
 function test_keyboardBeforePanelBeforeHistory() {
  var keyboard={}, panel={}; var hidden=0,closed=0
  BackLink.register(panel,function(){closed++;BackLink.unregister(panel);return true},"surface","panel")
  BackLink.register(keyboard,function(){hidden++;BackLink.unregister(keyboard);return true},"keyboard","keyboard")
  compare(back(),"keyboard"); compare(hidden,1); compare(closed,0); compare(calls.length,0)
  compare(back(),"panel"); compare(closed,1); compare(calls.length,0)
  back(); history()
 }
 function test_quickSettingsNestedWifi() {
  wifiPicker.opened=true; wifiPicker.sheet="password"
  BackLink.register(root,root.quickBack,"surface","quick settings")
  back(); compare(wifiPicker.sheet,""); verify(wifiPicker.opened); compare(calls.length,0)
  back(); verify(!wifiPicker.opened); verify(opened); compare(returns,1)
  back(); compare(dismissals,1); compare(calls.length,0)
 }
 function test_quickSettingsBluetoothRecordAndEditing() {
  bluetoothPanelItem.opened=true; bluetoothPanelItem.activeSheet="confirm"
  BackLink.register(root,root.quickBack,"surface","quick settings")
  back(); compare(bluetoothPanelItem.activeSheet,""); back(); compare(returns,1)
  opened=false; recordPanelItem.opened=true; back(); compare(returns,2)
  editing=true; back(); verify(!editing); verify(opened); compare(calls.length,0)
 }
 function test_drawerSearchThenDismiss() {
  opened=true; query="apps"; input.activeFocus=true
  BackLink.register(root,root.drawerBack,"surface","app drawer")
  back(); compare(query,""); verify(opened); back(); verify(!opened); compare(dismissals,1); compare(calls.length,0)
 }
 function test_recentsPickThenMenuThenDismiss() {
  opened=true; actionsOpen=true; actionPage="pick"
  BackLink.register(root,root.recentsBack,"surface","recent apps")
  back(); compare(actionPage,"menu"); verify(actionsOpen)
  back(); verify(!actionsOpen); verify(opened)
  back(); verify(!opened); compare(dismissals,1); compare(calls.length,0)
 }
 function test_closedOrFailingHandlerUsesUpstreamFallbackOrder() {
  BackLink.register({},function(){return false},"surface","closed")
  BackLink.register({},function(){throw new Error("failed handler")},"surface","failed")
  back(); history()
 }
}
'''.replace("\n BACK\n", "\n" + back + "\n").replace("\n QUICK\n", "\n" + quick + "\n").replace("\n DRAWER\n", "\n" + drawer + "\n").replace("\n RECENTS\n", "\n" + recents + "\n")
runner = shutil.which("qmltestrunner6") or shutil.which("/usr/lib/qt6/bin/qmltestrunner")
if not runner:
    raise SystemExit(77)
with tempfile.TemporaryDirectory(prefix="browser-back-") as temporary:
    directory = Path(temporary)
    (directory / "runtime").mkdir(mode=0o700)
    source = directory / "omamobile.back"
    source.mkdir()
    for name in ("BackLink.js", "BackLinkClient.qml", "BackModel.js"):
        shutil.copyfile(pkg / "plugins/omamobile.back" / name, source / name)
    (source / "tst_back.qml").write_text(qml)
    env = os.environ.copy()
    env.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_QPA_PLATFORMTHEME="generic", XDG_RUNTIME_DIR=str(directory / "runtime"))
    env.pop("QT_PLUGIN_PATH", None)
    env.pop("QT_QPA_GENERIC_PLUGINS", None)
    result = subprocess.run([runner, "-input", str(source / "tst_back.qml")], env=env)
    raise SystemExit(result.returncode)
