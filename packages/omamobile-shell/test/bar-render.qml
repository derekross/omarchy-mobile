// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "bar" as Bar
import "bar/StatusModel.js" as StatusModel

// Offscreen review shots of the status bar's right side (test/bar-render):
// a 412 px strip at the bar's 44 px with the clock, the status glyphs and
// the real BatteryIndicator, per $BAR_JOB entry (a battery style, a reading,
// the icons shown). The glyph row stands in for Bar.qml's (which needs a
// layer-shell window and live services); the battery is the bar's own
// component, fed the colours the bar uses. Prints each indicator's size.
ShellRoot {
  id: shell
  FileView { id: jobFile; path: Quickshell.env("BAR_JOB"); blockLoading: true }
  readonly property var job: JSON.parse(jobFile.text())
  property int index: -1
  readonly property var shot: index >= 0 && index < job.shots.length ? job.shots[index] : null
  readonly property var cfg: shot ? shot.config : ({})

  FloatingWindow {
    implicitWidth: 412
    implicitHeight: 44
    color: "black"

    Rectangle {
      id: strip
      width: 412
      height: Math.max(44, Style.bar.sizeHorizontal)
      color: Commons.Color.bar.background

      Text {
        anchors.left: parent.left; anchors.leftMargin: Style.spacing.huge
        anchors.verticalCenter: parent.verticalCenter
        text: "13:27"; color: Commons.Color.bar.text
        font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true
      }
      Row {
        anchors.right: parent.right; anchors.rightMargin: Style.spacing.huge
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xl
        Rectangle {
          visible: StatusModel.iconShown(shell.cfg, "unread")
          anchors.verticalCenter: parent.verticalCenter
          height: 20; width: 20; radius: 10; color: Commons.Color.accent
          Text { anchors.centerIn: parent; text: "2"; color: Commons.Color.bar.background; font.pixelSize: Style.font.body; font.bold: true }
        }
        Glyph { visible: StatusModel.iconShown(shell.cfg, "dnd"); text: "󰂛" }
        Glyph { visible: StatusModel.iconShown(shell.cfg, "bluetooth"); text: "󰂱" }
        Glyph { visible: StatusModel.iconShown(shell.cfg, "cell"); text: StatusModel.cellularIcon(80) }
        Glyph { visible: StatusModel.iconShown(shell.cfg, "wifi"); text: StatusModel.wifiIcon(90) }
        Bar.BatteryIndicator {
          id: battery
          anchors.verticalCenter: parent.verticalCenter
          style: StatusModel.batteryStyle(shell.cfg)
          percent: shell.shot ? shell.shot.percent : 50
          charging: shell.shot ? shell.shot.charging === true : false
          foreground: Commons.Color.bar.text
          background: Commons.Color.bar.background
          urgent: Commons.Color.bar.active
          fontFamily: Style.font.family
          iconPx: Style.font.iconLarge
          textPx: Style.font.body
          barSize: strip.height
        }
      }
    }
  }

  component Glyph: Text {
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    color: Commons.Color.bar.text
    font.family: Style.font.family; font.pixelSize: Style.font.iconLarge
  }

  function next() {
    index++
    if (index >= job.shots.length) { Qt.quit(); return }
    settle.restart()
  }
  Timer { id: settle; interval: 400; onTriggered: shell.capture() }
  function capture() {
    var s = shell.shot
    var bolt = false
    for (var i = 0; i < battery.children.length; i++) {
      var c = battery.children[i]
      if (c.objectName === "batteryBolt" && c.visible) bolt = true
      if (c.objectName === "batteryGlyph" && c.visible && c.text !== StatusModel.batteryIcon(s.percent, false, false)) bolt = true
    }
    console.log("battery " + s.name + " style " + battery.style + " " + Math.round(battery.width) + "x" + Math.round(battery.height)
      + " bolt " + bolt + " low " + battery.low + " strip " + strip.height)
    strip.grabToImage(function(result) {
      result.saveToFile(s.png)
      console.log("shot " + s.png)
      Qt.callLater(shell.next)
    })
  }
  Timer { interval: 300; running: true; onTriggered: shell.next() }
}
