// SPDX-License-Identifier: MIT
// How full a disk is. An example of running a command the safe way:
// host.run() with an argv list (no shell), a timeout, the cached answer
// shown at once after a layout edit, and a slow poll
// (/usr/share/omamobile/shell/WIDGETS.md).
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons

Item {
  id: widget

  property var host: null
  property var settings: ({})
  property bool editing: false
  property int cellsWide: 1
  property int cellsHigh: 1
  // Someone can see it: the poll waits while not (WIDGETS.md).
  property bool shown: true

  readonly property string path: {
    var p = String(settings.path || "~").trim()
    return p === "~" || p === "" ? Quickshell.env("HOME") : p.replace(/^~\//, Quickshell.env("HOME") + "/")
  }
  readonly property int minutes: Math.max(5, Number(settings.interval) || 30)

  // { used: percent, avail: "12G", at: ms } from the last run, kept by the
  // host across rebuilds.
  property var reading: host && host.cached ? host.cached : null
  property string failure: ""

  function refresh(force) {
    if (!host || host.busy) return
    if (!force && reading && reading.path === path && Date.now() - reading.at < minutes * 60000) return
    host.run(["df", "--output=pcent,avail", "-h", path], function(result) {
      var lines = result.stdout.trim().split("\n")
      var cols = lines.length > 1 ? lines[1].trim().split(/\s+/) : []
      if (result.code !== 0 || cols.length < 2) {
        widget.failure = result.timedOut ? "df took too long" : (result.stderr.trim() || "df failed")
        return
      }
      widget.failure = ""
      widget.reading = { path: widget.path, used: parseInt(cols[0], 10) || 0, avail: cols[1], at: Date.now() }
      widget.host.setCached(widget.reading)
    }, { timeout: 5 })
  }

  Component.onCompleted: refresh(false)
  onPathChanged: refresh(true)
  Timer { interval: widget.minutes * 60000; repeat: true; running: widget.shown; onTriggered: widget.refresh(true) }
  // Shown again: refresh(false) runs df only if the last answer is old.
  onShownChanged: if (shown) refresh(false)

  readonly property color fg: host ? host.foreground : Commons.Color.menu.text
  readonly property color dim: host ? host.dimForeground : Commons.Color.menu.text

  Column {
    anchors.fill: parent
    anchors.margins: Style.spacing.xl
    spacing: Style.spacing.md

    Row {
      width: parent.width
      spacing: Style.spacing.md
      Text {
        textFormat: Text.PlainText
        text: "󰋊"
        color: Commons.Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.iconLarge
      }
      Text {
        width: parent.width - x
        textFormat: Text.PlainText
        text: widget.failure !== "" ? widget.failure
          : widget.reading ? widget.reading.used + "% used · " + widget.reading.avail + " free" : "…"
        color: widget.failure !== "" ? Commons.Color.urgent : widget.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        elide: Text.ElideRight
      }
    }

    // The bar: plain rectangles, no effects.
    Rectangle {
      width: parent.width
      height: Math.max(6, Style.spacing.md)
      radius: height / 2
      color: Util.alpha(widget.fg, 0.15)
      Rectangle {
        width: parent.width * Math.min(1, (widget.reading ? widget.reading.used : 0) / 100)
        height: parent.height
        radius: parent.radius
        color: widget.reading && widget.reading.used >= 90 ? Commons.Color.urgent : Commons.Color.accent
      }
    }

    Text {
      width: parent.width
      visible: widget.cellsHigh >= 2
      textFormat: Text.PlainText
      text: widget.path
      color: widget.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: !widget.editing
    onClicked: widget.refresh(true)
  }
}
