// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "call" as Call

// Offscreen review shots of the call card (test/call-render), at the
// phone's 480x1040 logical px and on its side at 1040x480: each state in
// $CALL_JOB over a stand-in for what lies beneath (the lock, or an app),
// saved as a PNG, with the geometry of the controls and the named parts
// printed for the checks. Then it quits.
ShellRoot {
  id: shell

  FileView { id: jobFile; path: Quickshell.env("CALL_JOB"); blockLoading: true }
  readonly property var job: JSON.parse(jobFile.text())
  property int index: -1
  readonly property var shot: index >= 0 && index < job.shots.length ? job.shots[index] : null
  readonly property double now: 1760000000000

  FloatingWindow {
    id: win
    implicitWidth: 1040
    implicitHeight: 1040
    color: "black"

    Item {
      id: screen
      width: shell.shot && shell.shot.w ? shell.shot.w : 480
      height: shell.shot && shell.shot.h ? shell.shot.h : 1040
      readonly property bool wide: width > height

      // Beneath: the lock (a clock and a PIN pad, side by side on a phone
      // on its side) or an app.
      Rectangle {
        anchors.fill: parent
        color: shell.shot && shell.shot.under === "app" ? "#202020" : Commons.Color.background
        Text {
          visible: !!shell.shot && shell.shot.under !== "app"
          x: screen.wide ? Math.round(screen.width / 4 - width / 2) : Math.round((screen.width - width) / 2)
          y: screen.wide ? 180 : 240
          text: "13:27"
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: 84
        }
        Grid {
          visible: !!shell.shot && shell.shot.under !== "app"
          x: screen.wide ? Math.round(screen.width * 0.75 - width / 2) : Math.round((screen.width - width) / 2)
          y: screen.wide ? 40 : 560
          columns: 3
          spacing: 18
          Repeater {
            model: 12
            Rectangle { width: 84; height: 84; radius: 42; color: Qt.rgba(1, 1, 1, 0.08)
              Text { anchors.centerIn: parent; text: ["1","2","3","4","5","6","7","8","9","","0",""][index]; color: Commons.Color.foreground; font.pixelSize: 30 } }
          }
        }
        Text {
          visible: !!shell.shot && shell.shot.under === "app"
          anchors.centerIn: parent
          text: "app"
          color: "#808080"
          font.pixelSize: 30
        }
      }

      Call.CallCard {
        id: full
        anchors.fill: parent
        visible: !!shell.shot && (shell.shot.mode === "incoming" || shell.shot.mode === "in-call")
        call: shell.shot ? shell.shot.call : null
        mode: shell.shot ? shell.shot.mode : "incoming"
        nowMs: shell.now
        muted: !!shell.shot && shell.shot.muted === true
        route: shell.shot && shell.shot.route ? shell.shot.route : "earpiece"
        replies: shell.shot && shell.shot.replies ? shell.shot.replies : []
        showReplies: !!shell.shot && shell.shot.showReplies === true
      }

      Call.EmergencyInfo {
        id: emergencyInfo
        anchors.fill: parent
        visible: !!shell.shot && shell.shot.mode === "emergency"
      }

      Call.HeadsUp {
        id: top
        width: parent.width
        visible: !!shell.shot && (shell.shot.mode === "heads-up" || shell.shot.mode === "mini")
        call: shell.shot ? shell.shot.call : null
        mode: shell.shot && shell.shot.mode === "mini" ? "mini" : "heads-up"
        nowMs: shell.now
      }
    }
  }

  // The named controls and parts, as {name: {x, y, w, h}} in screen px.
  function describe(item, out) {
    if (!item) return out
    if (item.objectName && item.visible && item.opacity > 0) {
      var p = item.mapToItem(screen, 0, 0)
      out[item.objectName] = { x: Math.round(p.x), y: Math.round(p.y), w: Math.round(item.width), h: Math.round(item.height) }
    }
    for (var i = 0; i < item.children.length; i++) describe(item.children[i], out)
    return out
  }

  function next() {
    index++
    if (index >= job.shots.length) { Qt.quit(); return }
    settle.restart()
  }

  Timer { id: settle; interval: 900; onTriggered: shell.capture() }

  function capture() {
    var s = shell.shot
    var target = s.mode === "emergency" ? emergencyInfo : (s.mode === "heads-up" || s.mode === "mini") ? top : full
    console.log("geometry " + s.name + " " + screen.width + "x" + screen.height + " " + JSON.stringify(shell.describe(target, {})))
    screen.grabToImage(function(result) {
      result.saveToFile(s.png)
      console.log("shot " + s.png)
      Qt.callLater(shell.next)
    })
  }

  Timer { interval: 300; running: true; onTriggered: shell.next() }
}
