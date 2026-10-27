// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "access" as Access

// Offscreen review shots of the permission sheet (test/access-render), at
// the phone's 480x1040 logical px and on its side at 1040x480: each request
// in $ACCESS_JOB over an app stand-in, saved as a PNG, with the buttons'
// geometry printed for the checks. Then it quits.
ShellRoot {
  id: shell

  FileView { id: jobFile; path: Quickshell.env("ACCESS_JOB"); blockLoading: true }
  readonly property var job: JSON.parse(jobFile.text())
  property int index: -1
  readonly property var shot: index >= 0 && index < job.shots.length ? job.shots[index] : null

  FloatingWindow {
    id: win
    implicitWidth: 1040
    implicitHeight: 1040
    color: "black"

    Item {
      id: screen
      width: shell.shot && shell.shot.w ? shell.shot.w : 480
      height: shell.shot && shell.shot.h ? shell.shot.h : 1040

      // An app behind the sheet: a bar and a dark viewfinder.
      Rectangle { width: parent.width; height: 44; color: Commons.Color.bar.background
        Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "13:27"; color: Commons.Color.bar.text; font.family: Style.font.family; font.pixelSize: 15 } }
      Rectangle { y: 44; width: parent.width; height: parent.height - 44; color: "#202020"
        Text { anchors.centerIn: parent; text: "app"; color: "#808080"; font.pixelSize: 30 } }

      Access.AccessSheet {
        id: sheet
        anchors.fill: parent
        request: shell.shot ? shell.shot.request : null
        reveal: 1
        onAnswered: function(allow) { console.log("answered " + allow) }
      }
    }
  }

  function describe(item, depth, out) {
    if (!item) return out
    if (item.label !== undefined && item.primary !== undefined && item.visible) {
      var p = item.mapToItem(screen, 0, 0)
      out.push({ label: item.label, x: Math.round(p.x), y: Math.round(p.y), w: Math.round(item.width), h: Math.round(item.height) })
    }
    for (var i = 0; i < item.children.length; i++) describe(item.children[i], depth + 1, out)
    return out
  }

  function next() {
    index++
    if (index >= job.shots.length) { Qt.quit(); return }
    settle.restart()
  }

  Timer { id: settle; interval: 700; onTriggered: shell.capture() }

  function capture() {
    var s = shell.shot
    console.log("geometry " + s.name + " " + screen.width + "x" + screen.height + " " + JSON.stringify(shell.describe(sheet, 0, [])))
    screen.grabToImage(function(result) {
      result.saveToFile(s.png)
      console.log("shot " + s.png)
      Qt.callLater(shell.next)
    })
  }

  Timer { interval: 300; running: true; onTriggered: shell.next() }
}
