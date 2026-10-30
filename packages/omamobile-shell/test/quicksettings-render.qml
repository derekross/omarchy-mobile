// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "quicksettings" as QS

// Offscreen review shots of quick settings (test/quicksettings-render):
// the real QuickSettings.qml at the phone's 480x1040 logical px and on
// its side at 1040x480, over an app stand-in, each shot in $QS_JOB
// (collapsed, expanded, editing, the reminder page) saved as a PNG with
// the geometry of the sheet, the tiles, the handle, the shade and the
// page's parts printed for the checks. Then it quits.
ShellRoot {
  id: shell

  FileView { id: jobFile; path: Quickshell.env("QS_JOB"); blockLoading: true }
  readonly property var job: JSON.parse(jobFile.text())
  property int index: -1
  readonly property var shot: shell.index >= 0 && shell.index < shell.job.shots.length ? shell.job.shots[shell.index] : null

  FloatingWindow {
    id: win
    implicitWidth: 1040
    implicitHeight: 1040
    color: "black"

    Item {
      id: screen
      width: shell.shot ? shell.shot.w : 480
      height: shell.shot ? shell.shot.h : 1040

      // An app behind the sheet: a bar and a dark window.
      Rectangle { width: parent.width; height: 44; color: Commons.Color.bar.background
        Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "13:27"; color: Commons.Color.bar.text; font.family: Style.font.family; font.pixelSize: 15 } }
      Rectangle { y: 44; width: parent.width; height: parent.height - 44; color: "#202020"
        Text { anchors.centerIn: parent; text: "app"; color: "#808080"; font.pixelSize: 30 } }

      QS.QuickSettings {
        id: qs
        anchors.fill: parent
        // The pages (Wi-Fi, Bluetooth, record, reminder) are windows of
        // their own on the phone; their stand-ins fill the screen here.
        Component.onCompleted: {
          for (var i = 0; i < qs.children.length; i++) {
            var page = qs.children[i]
            if (page.opened === undefined || page.backRequested === undefined) continue
            page.width = Qt.binding(function() { return qs.width })
            page.height = Qt.binding(function() { return qs.height })
          }
        }
      }
    }
  }

  function rectOf(item) {
    var p = item.mapToItem(screen, 0, 0)
    return { x: Math.round(p.x), y: Math.round(p.y), w: Math.round(item.width), h: Math.round(item.height) }
  }

  // The named parts that are shown, as {name: {x, y, w, h}} in screen px.
  // A name used more than once (a tile's label and status) is numbered
  // from its second use; a text's colour (a field's placeholder colour)
  // comes along for the contrast checks.
  // A part cut off by a clipping ancestor (the sheet's scrolling content)
  // is marked `clipped`, so the checks don't read what isn't drawn.
  function describe(item, out, clipRect) {
    if (!item || !item.visible || item.opacity === 0) return out
    var rect = shell.rectOf(item)
    if (item.clip === true) clipRect = clipRect ? shell.intersect(clipRect, rect) : rect
    if (item.objectName) {
      var key = item.objectName
      for (var n = 2; out[key] !== undefined; n++) key = item.objectName + "#" + n
      var r = rect
      if (item.placeholderTextColor !== undefined) r.color = String(item.placeholderTextColor)
      else if (item.color !== undefined && item.text !== undefined) r.color = String(item.color)
      if (clipRect && !shell.within(rect, clipRect)) r.clipped = true
      out[key] = r
    }
    for (var i = 0; i < item.children.length; i++) shell.describe(item.children[i], out, clipRect)
    return out
  }

  function intersect(a, b) {
    var x = Math.max(a.x, b.x), y = Math.max(a.y, b.y)
    return { x: x, y: y, w: Math.max(0, Math.min(a.x + a.w, b.x + b.w) - x), h: Math.max(0, Math.min(a.y + a.h, b.y + b.h) - y) }
  }

  function within(a, b) {
    return a.x >= b.x - 1 && a.y >= b.y - 1 && a.x + a.w <= b.x + b.w + 1 && a.y + a.h <= b.y + b.h + 1
  }

  function next() {
    shell.index++
    if (shell.index >= shell.job.shots.length) { Qt.quit(); return }
    var s = shell.shot
    qs.close()
    Qt.callLater(function() {
      qs.open(JSON.stringify({ expanded: s.expanded === true, page: s.edit ? "edit" : (s.page || "") }))
      settle.restart()
    })
  }

  Timer { id: settle; interval: 1500; onTriggered: shell.capture() }

  function capture() {
    var s = shell.shot
    var parts = shell.describe(qs, {})
    console.log("geometry " + s.name + " " + screen.width + "x" + screen.height
                + " " + JSON.stringify({ parts: parts, columns: qs.tileColumns, expanded: qs.expanded, edit: qs.editing, page: s.page || "", notifications: qs.notifications.length }))
    screen.grabToImage(function(result) {
      result.saveToFile(s.png)
      console.log("shot " + s.png)
      Qt.callLater(shell.next)
    })
  }

  Timer { interval: 800; running: true; onTriggered: shell.next() }
}
