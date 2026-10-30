// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "HomeModel.js" as HomeModel
import "Readable.js" as Readable

// Today and what's next. With khal (the local calendar that vdirsyncer
// keeps in step with CalDAV) the next seven days' events are listed;
// without it, or with nothing on, the month is shown. Nothing here goes on
// the network: syncing is khal's and vdirsyncer's business.
Item {
  id: widget

  property var home: null
  property var entry: null
  property bool editing: false
  // Someone can see it (set by Home.qml): its timers wait while not.
  property bool shown: true

  readonly property color fg: home ? home.foreground : "white"
  readonly property color dim: home ? home.dimForeground : "white"

  SystemClock {
    id: clock
    enabled: widget.shown
    precision: SystemClock.Hours
  }

  property var events: []
  property bool hasKhal: false

  Process {
    id: agendaProc
    command: ["sh", "-c", "command -v khal >/dev/null || exit 3; exec \"$@\"", "sh"].concat(HomeModel.AGENDA_ARGV)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: widget.events = HomeModel.parseAgenda(text, 12)
    }
    onExited: function(code) { widget.hasKhal = code !== 3 }
  }

  property real lastRefresh: 0
  function refresh() { if (!agendaProc.running) { widget.lastRefresh = Date.now(); agendaProc.running = true } }
  Component.onCompleted: refresh()
  Connections { target: clock; function onDateChanged() { if (widget.shown) widget.refresh() } }
  Timer { interval: 15 * 60 * 1000; repeat: true; running: widget.shown; onTriggered: widget.refresh() }
  // Shown again: once, if 15 minutes passed.
  onShownChanged: if (shown && HomeModel.overdue(lastRefresh, 15 * 60 * 1000, Date.now())) refresh()

  readonly property bool listMode: hasKhal && events.length > 0
  readonly property string todayIso: Qt.formatDate(clock.date, "yyyy-MM-dd")

  Column {
    anchors.fill: parent
    anchors.margins: Style.spacing.xl
    spacing: Style.spacing.md

    Text {
      id: heading
      width: parent.width
      textFormat: Text.PlainText
      text: Qt.formatDate(clock.date, widget.listMode ? "dddd d MMMM" : "MMMM yyyy")
      color: widget.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      font.bold: true
      elide: Text.ElideRight
    }

    // Events.
    Column {
      width: parent.width
      visible: widget.listMode
      spacing: Style.spacing.sm
      clip: true
      height: parent.height - heading.height - parent.spacing

      Repeater {
        model: widget.events
        delegate: Row {
          required property var modelData
          width: parent.width
          spacing: Style.spacing.lg

          Rectangle {
            width: 3; height: label.height; radius: Math.min(Style.cornerRadius, 1.5)
            color: modelData.date === widget.todayIso ? Commons.Color.accent : widget.dim
          }
          Column {
            id: label
            width: parent.width - 3 - Style.spacing.lg
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: modelData.title
              color: widget.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: (modelData.date === widget.todayIso ? "Today" : modelData.date) + (modelData.time ? "  " + modelData.time : "  all day")
              color: widget.dim
              font.family: Style.font.family
              font.pixelSize: Readable.px(Style.font.caption)
              elide: Text.ElideRight
            }
          }
        }
      }
    }

    // The month, weeks from Monday.
    Grid {
      id: month
      visible: !widget.listMode
      columns: 7
      width: parent.width
      readonly property real cellW: width / 7
      readonly property real cellH: Math.min(cellW, (widget.height - heading.height - Style.spacing.xl * 2 - Style.spacing.md) / 7)

      Repeater {
        model: ["M", "T", "W", "T", "F", "S", "S"]
        delegate: Text {
          required property var modelData
          width: month.cellW; height: month.cellH
          horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          text: modelData
          color: widget.dim
          font.family: Style.font.family
          font.pixelSize: Readable.px(Style.font.caption)
          font.bold: true
        }
      }
      Repeater {
        model: HomeModel.monthGrid(clock.date.getFullYear(), clock.date.getMonth(), clock.date, 1)
        delegate: Item {
          required property var modelData
          width: month.cellW; height: month.cellH
          Rectangle {
            anchors.centerIn: parent
            visible: modelData.today
            width: Math.min(parent.width, parent.height) - 2; height: width; radius: Math.min(Style.cornerRadius, width / 2)
            color: Commons.Color.accent
          }
          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: modelData.day
            color: modelData.today ? Commons.Color.background : modelData.inMonth ? widget.fg : Qt.rgba(widget.dim.r, widget.dim.g, widget.dim.b, 0.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }
}
