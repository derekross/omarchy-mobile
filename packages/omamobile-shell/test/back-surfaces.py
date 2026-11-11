#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Every surface's place in Back's list, and Back's order, in Qt.

Back asks omamobile.back's BackLink.js before it sends Escape: the
on-screen keyboard, then the topmost registered shell surface, then the
focused window. Each surface registers through a Loader of
BackLinkClient.qml. This test takes those Loader blocks out of the plugins
as they are written, runs each beside stand-ins for the names it uses
(root, languageWindow, owl, owlCell), with the real BackLink.js,
BackLinkClient.qml, BackModel.js and HomeModel.js, and Back.qml's own
back(), under qmltestrunner (offscreen; Quickshell is test/qml-stubs, which
records commands instead of running them). Exit 77 without qmltestrunner.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

here = Path(__file__).parent
plugins = here.parent / "plugins"
MARK = 'source: Qt.resolvedUrl("../omamobile.back/BackLinkClient.qml")'

# file -> the names its blocks register under, in file order
EXPECT = {
    "omamobile.keyboard/Keyboard.qml": ["keyboard languages", "keyboard"],
    "omamobile.access/Access.qml": ["permission sheet"],
    "omamobile.fingerprint/Fingerprint.qml": ["fingerprint setup"],
    "omamobile.voice/Voice.qml": ["voice settings", "voice result"],
    "omamobile.home/Home.qml": ["home screen"],
    "omamobile.home/OwlCell.qml": ["widget screen"],
}


def block_end(text, start):
    depth = 0
    for at in range(start, len(text)):
        if text[at] == "{":
            depth += 1
        elif text[at] == "}":
            depth -= 1
            if depth == 0:
                return at + 1
    raise AssertionError("unterminated block")


def loaders(text):
    out, at = [], 0
    while True:
        mark = text.find(MARK, at)
        if mark < 0:
            return out
        start = text.rfind("Loader {", 0, mark)
        end = block_end(text, start)
        out.append(text[start:end])
        at = end


def body_of(text, head):
    start = text.index(head) + len(head) - 1
    return text[start:block_end(text, start)]


blocks = {}
for name, wanted in EXPECT.items():
    found = loaders((plugins / name).read_text())
    names = [b.split('item.name = "')[1].split('"')[0] for b in found]
    assert names == wanted, "%s registers %s, expected %s" % (name, names, wanted)
    for label, block in zip(names, found):
        blocks[label] = block.replace("../omamobile.back/", "omamobile.back/")
# Nothing else loads the client unseen by this test.
for path in plugins.glob("*/*.qml"):
    rel = str(path.relative_to(plugins))
    if rel not in EXPECT and rel != "omamobile.back/BackLinkClient.qml":
        assert MARK not in path.read_text(), "%s registers with Back but isn't tested here" % rel

FAKES = '''
  property alias fake: root
  property alias languages: languageWindow
  property alias screen: owl
  property alias cell: owlCell
  QtObject {
    id: root
    property bool oskOpen: false
    property bool languagesOpen: false
    property bool opened: false
    property bool screenOpen: false
    property bool authPending: false
    property string phase: "idle"
    property bool homeShown: false
    property string backLevel: ""
    property var layersOver: ({})
    property var calls: []
    function note(n) { calls = calls.concat([n]) }
    function hideKeyboard() { note("hideKeyboard"); oskOpen = false }
    function closeLanguages() { note("closeLanguages"); languagesOpen = false }
    function back() { note("back"); opened = false; screenOpen = false; return true }
    function dismissSettings() { note("dismissSettings"); opened = false }
    function reset() { note("reset"); phase = "idle" }
    function backOneLevel() { note("backOneLevel"); backLevel = ""; return true }
  }
  QtObject {
    id: languageWindow
    property bool onAdd: false
    function back() { if (!onAdd) return false; onAdd = false; root.note("languages page"); return true }
  }
  QtObject {
    id: owl
    property bool screenOpen: false
    function closeScreen() { root.note("closeScreen"); screenOpen = false }
  }
  QtObject {
    id: owlCell
    property bool editing: false
    property var home: root
  }
'''

back_source = (plugins / "omamobile.back/Back.qml").read_text()
back_fn = body_of(back_source, "  function back() {")

TEST = r'''import QtQuick
import QtTest
import Quickshell
import "omamobile.back/BackLink.js" as BackLink
import "omamobile.back/BackModel.js" as BackModel
import "omamobile.back"

TestCase {
  id: test
  name: "BackSurfaces"

  // Back.qml's own back(), as written.
  function back() BACK_FN

  function names() { return BackLink.names().join(",") }
  function sent() { return Quickshell.executed.length }

  Component { id: kb; SurfKeyboard {} }
  Component { id: lang; SurfKeyboardLanguages {} }
  Component { id: perm; SurfPermissionSheet {} }
  Component { id: finger; SurfFingerprintSetup {} }
  Component { id: vset; SurfVoiceSettings {} }
  Component { id: vres; SurfVoiceResult {} }
  Component { id: home; SurfHomeScreen {} }
  Component { id: wscreen; SurfWidgetScreen {} }
  Component { id: plain; BackLinkClient {} }

  function init() { BackLink.clear(); Quickshell.executed = [] }

  function make(c) { var o = createTemporaryObject(c, test); verify(o); return o }

  // One surface alone: on the list only while open; Back closes it, sends
  // nothing, and the Back after that is Escape.
  function alone(o, label, open, call) {
    compare(names(), "")
    open(o)
    compare(names(), label)
    compare(back(), label)
    compare(o.fake.calls.join(","), call)
    compare(names(), "", label + " is off the list once closed")
    compare(sent(), 0, "nothing went to the app under " + label)
    compare(back(), "ok")
    compare(sent(), 1)
    compare(JSON.stringify(Quickshell.executed[0]), JSON.stringify(BackModel.ESCAPE_ARGV))
  }

  function test_keyboard() { alone(make(kb), "keyboard", function(o) { o.fake.oskOpen = true }, "hideKeyboard") }
  function test_permissionSheet() { alone(make(perm), "permission sheet", function(o) { o.fake.opened = true }, "back") }
  function test_fingerprintSetup() { alone(make(finger), "fingerprint setup", function(o) { o.fake.screenOpen = true }, "back") }
  function test_voiceSettings() { alone(make(vset), "voice settings", function(o) { o.fake.opened = true }, "dismissSettings") }
  function test_voiceResult() { alone(make(vres), "voice result", function(o) { o.fake.phase = "result" }, "reset") }
  function test_homeScreen() {
    alone(make(home), "home screen", function(o) { o.fake.homeShown = true; o.fake.backLevel = "page" }, "backOneLevel")
  }
  function test_widgetScreen() {
    alone(make(wscreen), "widget screen", function(o) { o.fake.homeShown = true; o.screen.screenOpen = true }, "closeScreen")
  }

  function test_languageSheetGoesBackAPageThenCloses() {
    var o = make(lang)
    o.fake.languagesOpen = true
    o.languages.onAdd = true
    compare(back(), "keyboard languages")
    compare(o.fake.calls.join(","), "languages page")
    compare(names(), "keyboard languages", "still open, on its list")
    compare(back(), "keyboard languages")
    compare(o.fake.calls.join(","), "languages page,closeLanguages")
    compare(names(), "")
    compare(sent(), 0)
  }

  function test_closedByItsOwnButtonNeverSwallowsBack() {
    var o = make(perm)
    o.fake.opened = true
    o.fake.opened = false
    compare(names(), "")
    compare(back(), "ok")
    compare(o.fake.calls.length, 0)
    compare(sent(), 1)
  }

  function test_destroyedSurfaceIsOffTheList() {
    var o = perm.createObject(test)
    o.fake.opened = true
    compare(names(), "permission sheet")
    o.destroy()
    tryCompare(test, "listed", "")
  }
  readonly property string listed: { tick; return BackLink.names().join(",") }
  property int tick: 0
  Timer { interval: 20; repeat: true; running: true; onTriggered: test.tick++ }

  function test_voiceErrorClosesTooAndListeningIsLeftAlone() {
    var o = make(vres)
    o.fake.phase = "listening"
    compare(names(), "", "the app keeps Back while the words are typed into it")
    o.fake.phase = "error"
    compare(back(), "voice result")
  }

  function test_fingerprintLeavesBackToThePolkitPrompt() {
    var o = make(finger)
    o.fake.screenOpen = true
    o.fake.authPending = true
    compare(names(), "")
    o.fake.authPending = false
    compare(names(), "fingerprint setup")
  }

  function test_homeOnlyWhenItShowsWithNothingOverIt() {
    var o = make(home)
    o.fake.backLevel = "page"
    compare(names(), "", "under an app")
    o.fake.homeShown = true
    compare(names(), "home screen")
    o.fake.layersOver = ({ "omamobile-quicksettings": 1 })
    compare(names(), "", "quick settings is open over it")
    o.fake.layersOver = ({})
    o.fake.backLevel = ""
    compare(names(), "", "at rest on its home page")
    var w = make(wscreen)
    w.fake.homeShown = true
    w.screen.screenOpen = true
    w.cell.editing = true
    compare(names(), "")
    w.cell.editing = false
    w.fake.layersOver = ({ "omarchy-menu": 1 })
    compare(names(), "")
  }

  // The order: the keyboard, then the topmost surface, then Escape.
  function test_keyboardThenSurfaceThenEscape() {
    var sheet = make(perm), keys = make(kb), setup = make(finger)
    setup.fake.screenOpen = true
    sheet.fake.opened = true
    keys.fake.oskOpen = true
    compare(names(), "keyboard,permission sheet,fingerprint setup")
    compare(back(), "keyboard")
    compare(sheet.fake.calls.length + setup.fake.calls.length, 0, "hiding the keyboard closes nothing")
    compare(back(), "permission sheet", "opened last, on top")
    compare(setup.fake.calls.length, 0)
    compare(back(), "fingerprint setup")
    compare(sent(), 0)
    compare(back(), "ok")
    compare(sent(), 1)
  }

  function test_keyboardOverAnAppSendsNothingThenEscape() {
    var keys = make(kb)
    keys.fake.oskOpen = true
    compare(back(), "keyboard")
    compare(sent(), 0)
    compare(back(), "ok")
    compare(sent(), 1)
  }

  function test_languageSheetBeforeTheKeyboardUnderIt() {
    var l = make(lang), keys = make(kb)
    l.fake.languagesOpen = true
    keys.fake.oskOpen = true
    compare(back(), "keyboard languages")
    compare(back(), "keyboard")
  }

  // The client itself.
  function test_clientNeedsAHandlerAndFollowsActive() {
    var c = make(plain)
    c.name = "x"
    c.active = true
    verify(!c.registered, "no handler, not listed")
    var hits = 0
    c.handler = function() { hits++; return hits < 2 }
    verify(c.registered)
    compare(back(), "x")
    compare(back(), "ok", "a handler that says false passes Back on")
    compare(hits, 2)
    c.active = false
    verify(!c.registered)
    compare(names(), "")
  }
}
'''


def component(label):
    return "Surf" + "".join(w.capitalize() for w in label.split())


runner = (shutil.which("qmltestrunner6")
          or shutil.which("/usr/lib/qt6/bin/qmltestrunner")
          or shutil.which("/usr/lib64/qt6/bin/qmltestrunner"))
if not runner:
    raise SystemExit(77)
with tempfile.TemporaryDirectory(prefix="back-surfaces-") as temporary:
    work = Path(temporary)
    (work / "runtime").mkdir(mode=0o700)
    (work / "omamobile.back").mkdir()
    for name in ("BackLink.js", "BackLinkClient.qml", "BackModel.js"):
        shutil.copy(plugins / "omamobile.back" / name, work / "omamobile.back" / name)
    shutil.copy(plugins / "omamobile.home/HomeModel.js", work / "HomeModel.js")
    for label, block in blocks.items():
        (work / (component(label) + ".qml")).write_text(
            'import QtQuick\nimport "HomeModel.js" as HomeModel\n\nItem {\n' + FAKES + "\n  " + block + "\n}\n")
    (work / "tst_back_surfaces.qml").write_text(TEST.replace("BACK_FN", back_fn))
    env = os.environ.copy()
    env.update(QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QT_QPA_PLATFORMTHEME="generic",
               QML_DISABLE_DISK_CACHE="1", XDG_RUNTIME_DIR=str(work / "runtime"))
    env.pop("QT_PLUGIN_PATH", None)
    env.pop("QT_QPA_GENERIC_PLUGINS", None)
    result = subprocess.run([runner, "-import", str(here / "qml-stubs"), "-input", str(work / "tst_back_surfaces.qml")],
                            env=env, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        sys.stdout.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(1)
    passed = [line for line in result.stdout.splitlines() if line.startswith("PASS")]
    print("ok - back surfaces: %d checks in Qt (each surface on and off the list, the order, Back.qml's back)" % len(passed))
