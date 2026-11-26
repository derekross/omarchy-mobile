// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "textsize" as TextSize

// Offscreen review shots of the Text size page (test/textsize-render), at
// the phone's 480x1040 logical px and on its side at 1040x480: each shot in
// $TEXTSIZE_JOB with its step chosen, saved as a PNG, with the rows'
// geometry printed for the checks. Then it quits.
ShellRoot {
  id: shell

  FileView { id: jobFile; path: Quickshell.env("TEXTSIZE_JOB"); blockLoading: true }
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

      Rectangle { anchors.fill: parent; color: "#202020" }

      TextSize.TextSizeSheet {
        id: sheet
        anchors.fill: parent
        shown: shell.shot ? shell.shot.step : "default"
        onChosen: function(name) { console.log("chosen " + name) }
      }
    }
  }

  function describe(item, out) {
    if (!item) return out
    if (String(item.objectName).indexOf("textSize") === 0 && item.visible) {
      var p = item.mapToItem(screen, 0, 0)
      out.push({ name: item.objectName, current: item.isCurrent === true, x: Math.round(p.x), y: Math.round(p.y),
                 w: Math.round(item.width), h: Math.round(item.height) })
    }
    for (var i = 0; i < item.children.length; i++) describe(item.children[i], out)
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
    console.log("geometry " + s.name + " " + screen.width + "x" + screen.height + " " + JSON.stringify(shell.describe(sheet, [])))
    screen.grabToImage(function(result) {
      result.saveToFile(s.png)
      console.log("shot " + s.png)
      Qt.callLater(shell.next)
    })
  }

  Component.onCompleted: Qt.callLater(shell.next)
}
