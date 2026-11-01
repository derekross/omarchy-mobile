// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "HomeModel.js" as HomeModel

// Clock and date. Formats are Qt date formats from the widget's settings;
// without a time format the clock follows the system's 12- or 24-hour
// choice, the bar's clockFormat in shell.json.
Item {
  id: widget

  property var home: null
  property var entry: null
  property bool editing: false
  // Someone can see it (set by Home.qml): its timers wait while not.
  property bool shown: true
  readonly property var config: entry && entry.config ? entry.config : ({})

  property string barFormat: ""

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var shell = JSON.parse(text() || "{}")
        widget.barFormat = shell.bar && shell.bar.clockFormat ? String(shell.bar.clockFormat) : ""
      } catch (e) { widget.barFormat = "" }
    }
  }

  readonly property string timeFormat: widget.config.timeFormat || HomeModel.systemTimeFormat(widget.barFormat)

  // Stopped while hidden; it reads the time again when enabled.
  SystemClock {
    id: clock
    enabled: widget.shown
    precision: SystemClock.Minutes
  }

  readonly property bool wide: width > height * 1.6

  Column {
    anchors.centerIn: parent
    width: widget.width - Style.spacing.xxl * 2
    spacing: Style.spacing.xs

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: Qt.formatDateTime(clock.date, widget.timeFormat)
      color: widget.home ? widget.home.foreground : "white"
      font.family: Style.font.family
      font.pixelSize: Math.max(Style.font.display, Math.min(widget.height * 0.46, widget.width * 0.26))
      font.weight: Font.Light
      fontSizeMode: Text.HorizontalFit
      minimumPixelSize: Style.font.title
    }

    Text {
      width: parent.width
      visible: widget.height >= 80
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: Qt.formatDateTime(clock.date, widget.config.dateFormat || "dddd d MMMM")
      color: widget.home ? widget.home.dimForeground : "white"
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      elide: Text.ElideRight
    }
  }
}
