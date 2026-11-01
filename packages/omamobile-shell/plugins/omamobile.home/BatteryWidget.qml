// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Commons
import qs.Commons as Commons

// Battery level, charging state and time left, from UPower's display device.
Item {
  id: widget

  property var home: null
  property var entry: null
  property bool editing: false

  readonly property var battery: UPower.displayDevice
  readonly property bool present: !!battery && battery.isPresent === true
  readonly property int percent: present ? Math.round(battery.percentage * 100) : -1
  readonly property bool charging: present && !UPower.onBattery
  readonly property bool full: present && battery.state === UPowerDeviceState.FullyCharged
  readonly property real seconds: !present ? 0 : (charging ? battery.timeToFull : battery.timeToEmpty)

  function duration(s) {
    if (!s || s <= 0) return ""
    var h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60)
    return h > 0 ? h + " h " + m + " min" : m + " min"
  }

  readonly property string detail: !present ? "No battery"
    : full ? "Full"
    : charging ? (duration(seconds) ? "Full in " + duration(seconds) : "Charging")
    : (duration(seconds) ? duration(seconds) + " left" : "On battery")

  readonly property color levelColor: percent >= 0 && percent <= 15 && !charging ? Commons.Color.urgent : Commons.Color.accent
  readonly property bool compact: width < 100

  Row {
    anchors.centerIn: parent
    spacing: Style.spacing.xl
    visible: !widget.compact

    // A battery outline filled to the level.
    Item {
      width: 22
      height: 40
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 10; height: 4; y: 0
        radius: Math.min(Style.cornerRadius, 1)
        color: widget.home ? widget.home.dimForeground : "white"
      }
      Rectangle {
        id: shell
        y: 4; width: parent.width; height: parent.height - 4
        radius: Math.min(Style.cornerRadius, 4)
        color: "transparent"
        border.width: 2
        border.color: widget.home ? widget.home.dimForeground : "white"

        Rectangle {
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottomMargin: 4
          width: parent.width - 8
          height: Math.max(0, (parent.height - 8) * Math.max(0, widget.percent) / 100)
          radius: Math.min(Style.cornerRadius, 2)
          color: widget.levelColor
        }
      }
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xxs

      Text {
        textFormat: Text.PlainText
        text: (widget.percent >= 0 ? widget.percent + "%" : "–") + (widget.charging && !widget.full ? " 󱐋" : "")
        color: widget.home ? widget.home.foreground : "white"
        font.family: Style.font.family
        font.pixelSize: Style.font.displayLarge
      }
      Text {
        textFormat: Text.PlainText
        text: widget.detail
        color: widget.home ? widget.home.dimForeground : "white"
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }

  // One cell: just the number over a level bar.
  Column {
    anchors.centerIn: parent
    visible: widget.compact
    spacing: Style.spacing.sm

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: widget.percent >= 0 ? widget.percent + "%" : "–"
      color: widget.home ? widget.home.foreground : "white"
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
    }
    Rectangle {
      width: widget.width * 0.6; height: 4; radius: Math.min(Style.cornerRadius, 2)
      color: Qt.rgba(1, 1, 1, 0.2)
      Rectangle { width: parent.width * Math.max(0, widget.percent) / 100; height: parent.height; radius: Math.min(Style.cornerRadius, 2); color: widget.levelColor }
    }
  }
}
