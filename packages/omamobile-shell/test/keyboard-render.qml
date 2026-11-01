// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "keyboard" as Keyboard

// Offscreen review shots of the keyboard's language sheet
// (test/keyboard-render), at the phone's 480x1040 logical px and on its side
// at 1040x480: each listing in $KEYBOARD_JOB over an app and a keyboard
// stand-in (squeekboard's 480x280 at the bottom), saved as a PNG, with the
// rows' geometry printed for the checks. Then it quits.
ShellRoot {
  id: shell

  FileView { id: jobFile; path: Quickshell.env("KEYBOARD_JOB"); blockLoading: true }
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

      Rectangle { width: parent.width; height: 44; color: Commons.Color.bar.background
        Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "13:27"; color: Commons.Color.bar.text; font.family: Style.font.family; font.pixelSize: 15 } }
      Rectangle { y: 44; width: parent.width; height: parent.height - 44; color: "#202020"
        Text { anchors.centerIn: parent; text: "app"; color: "#808080"; font.pixelSize: 30 } }
      Rectangle { y: parent.height - height; width: parent.width; height: parent.width > parent.height ? 200 : 280; color: "#303030"
        Text { anchors.centerIn: parent; text: "keyboard"; color: "#909090"; font.pixelSize: 24 } }

      Keyboard.LanguageSheet {
        id: sheet
        anchors.fill: parent
        listing: shell.shot ? shell.shot.listing : null
        page: shell.shot ? shell.shot.page : "languages"
        reveal: 1
        onPicked: function(name) { console.log("picked " + name) }
        onRemoved: function(name) { console.log("removed " + name) }
        onDismissed: console.log("dismissed")
      }
    }
  }

  function describe(item, out) {
    if (!item) return out
    if (item.row !== undefined && item.modelData !== undefined && item.visible) {
      var p = item.mapToItem(screen, 0, 0)
      out.push({ label: item.row.label, current: !!item.row.current, x: Math.round(p.x), y: Math.round(p.y),
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

  Timer { interval: 300; running: true; onTriggered: shell.next() }
}
