// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "launcher" as L

// Offscreen review shots of the app drawer (test/launcher-render): the
// real Launcher.qml at the phone's 480x1040 logical px and on its side at
// 1040x480, its application library a stand-in over the job's apps, each
// shot in $LAUNCHER_JOB (the drawer open, a search, a search with no
// match) saved as a PNG with the sheet's, the header's, the input's and
// every cell's geometry (and the named texts' colours) printed for the
// checks. Then it quits.
ShellRoot {
  id: harness

  FileView { id: jobFile; path: Quickshell.env("LAUNCHER_JOB"); blockLoading: true }
  readonly property var job: JSON.parse(jobFile.text())
  property int index: -1
  readonly property var shot: harness.index >= 0 && harness.index < harness.job.shots.length ? harness.job.shots[harness.index] : null

  // What Omarchy's AppLibrary gives the drawer, over the job's apps: an
  // object, since the drawer connects to the library's signals.
  readonly property QtObject library: QtObject {
    signal appsChanged()
    function sortedEntries(query) {
      var q = String(query || "").toLowerCase()
      return harness.job.apps.filter(function(a) { return !q || a.name.toLowerCase().indexOf(q) >= 0 }).map(function(a) { return { entry: a } })
    }
    function entryName(entry) { return entry ? String(entry.name) : "" }
    function iconSource(icon) { return icon ? "file://" + icon : "" }
    function refreshIcons() {}
    function beginLaunchFeedback() {}
  }

  FloatingWindow {
    id: win
    implicitWidth: 1040
    implicitHeight: 1040
    color: "black"

    Item {
      id: screen
      width: harness.shot ? harness.shot.w : 480
      height: harness.shot ? harness.shot.h : 1040

      // The status bar above the drawer (it reserves its space).
      Rectangle { width: parent.width; height: 44; color: Commons.Color.bar.background
        Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "13:27"; color: Commons.Color.bar.text; font.family: Style.font.family; font.pixelSize: 15 } }

      L.Launcher {
        id: launcher
        y: 44
        width: screen.width
        height: screen.height - 44
        shell: ({ appLibrary: harness.library })
      }
    }
  }

  function rectOf(item) {
    var p = item.mapToItem(screen, 0, 0)
    return { x: Math.round(p.x), y: Math.round(p.y), w: Math.round(item.width), h: Math.round(item.height) }
  }

  // The named parts that are shown, as {name: {x, y, w, h}} in screen px;
  // a text's colour (a field's placeholder colour) comes along for the
  // contrast checks.
  function describe(item, out) {
    if (!item || !item.visible || item.opacity === 0) return out
    if (item.objectName) {
      var r = harness.rectOf(item)
      if (item.placeholderTextColor !== undefined) r.color = String(item.placeholderTextColor)
      else if (item.color !== undefined && item.text !== undefined) r.color = String(item.color)
      out[item.objectName] = r
    }
    for (var i = 0; i < item.children.length; i++) harness.describe(item.children[i], out)
    return out
  }

  function next() {
    harness.index++
    if (harness.index >= harness.job.shots.length) { Qt.quit(); return }
    var s = harness.shot
    launcher.close()
    if (launcher.screenInfo !== undefined) launcher.screenInfo = { width: s.w, height: s.h }
    Qt.callLater(function() {
      launcher.open("{}")
      launcher.query = s.query || ""
      settle.restart()
    })
  }

  Timer { id: settle; interval: 1500; onTriggered: harness.capture() }

  function capture() {
    var s = harness.shot
    var parts = harness.describe(launcher, {})
    console.log("geometry " + s.name + " " + screen.width + "x" + screen.height + " "
                + JSON.stringify({ parts: parts, columns: launcher.drawerColumns ? launcher.drawerColumns(parts["drawerGrid"] ? parts["drawerGrid"].w : 0) : 0,
                                   apps: launcher.apps.length, query: s.query || "" }))
    screen.grabToImage(function(result) {
      result.saveToFile(s.png)
      console.log("shot " + s.png)
      Qt.callLater(harness.next)
    })
  }

  Timer { interval: 800; running: true; onTriggered: harness.next() }
}
