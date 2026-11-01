// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "HomeModel.js" as HomeModel
import "Readable.js" as Readable

// Your own text, or the output of your own command. With a command set, it
// runs through `sh -c` when the widget appears and every `interval` seconds
// (at least 30; 0 runs it once), killed after 10 s, and the first lines of
// its output are shown. A tap runs the `tap` command, if any. Commands come
// only from the user's own home.json; the widget runs nothing by default.
Item {
  id: widget

  property var home: null
  property var entry: null
  property bool editing: false
  // Someone can see it (set by Home.qml): its timers wait while not.
  property bool shown: true
  readonly property var config: entry && entry.config ? entry.config : ({})

  readonly property color fg: home ? home.foreground : "white"
  readonly property color dim: home ? home.dimForeground : "white"

  readonly property string command: String(config.command || "").trim()
  readonly property int interval: Number(config.interval) > 0 ? Math.max(30, Number(config.interval)) : 0
  readonly property var cached: home && entry ? home.widgetCache(entry.id) : null
  property string output: cached && cached.key === command ? cached.data : ""

  Process {
    id: proc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        widget.output = String(text || "")
        if (widget.home) widget.home.setWidgetCache(widget.entry.id, { key: widget.command, at: Date.now(), data: widget.output })
      }
    }
  }

  function run(force) {
    if (!command || proc.running) return
    var c = home ? home.widgetCache(entry.id) : null
    if (!force && c && c.key === command && (interval === 0 || Date.now() - c.at < interval * 1000)) return
    // Set here, not bound: a binding may not have caught up with a
    // command that changed in the same breath.
    proc.command = ["timeout", "10", "sh", "-c", command]
    proc.running = true
  }

  onCommandChanged: run(false)
  Component.onCompleted: run(false)
  Timer { interval: Math.max(30, widget.interval) * 1000; repeat: true; running: widget.shown && widget.interval > 0 && !!widget.command; onTriggered: widget.run(true) }
  // Shown again: run(false) runs only when the last output is older than the interval.
  onShownChanged: if (shown) run(false)

  readonly property string title: String(config.title || "")
  readonly property string body: command ? HomeModel.commandText(output, 12) : String(config.text || "")

  Column {
    anchors.fill: parent
    anchors.margins: Style.spacing.xl
    spacing: Style.spacing.xs

    Text {
      id: titleText
      width: parent.width
      visible: widget.title.length > 0
      textFormat: Text.PlainText
      text: widget.title
      color: widget.dim
      font.family: Style.font.family
      font.pixelSize: Readable.px(Style.font.caption)
      font.bold: true
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      height: parent.height - (titleText.visible ? titleText.height + parent.spacing : 0)
      textFormat: Text.PlainText
      text: widget.body.length > 0 ? widget.body
        : (widget.command ? "…" : "Tap to set text or a command")
      color: widget.body.length > 0 ? widget.fg : widget.dim
      font.family: Style.font.family
      font.pixelSize: widget.command ? Style.font.body : Style.font.title
      wrapMode: Text.Wrap
      elide: Text.ElideRight
      fontSizeMode: Text.Fit
      minimumPixelSize: Readable.px(Style.font.caption)
      verticalAlignment: widget.command ? Text.AlignTop : Text.AlignVCenter
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: !widget.editing
    onClicked: {
      var tap = String(widget.config.tap || "").trim()
      // Through omamobile-launch: a window the tap opens gets its own screen.
      if (tap) Quickshell.execDetached(HomeModel.commandLaunchArgv(["sh", "-c", tap]))
      else if (!widget.command && !widget.config.text && widget.home) widget.home.openSettings(widget.entry.id)
      else widget.run(true)
    }
  }
}
