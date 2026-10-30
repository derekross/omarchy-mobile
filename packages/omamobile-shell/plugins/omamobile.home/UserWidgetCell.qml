// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "UserWidgets.js" as UserWidgets
import "Readable.js" as Readable

// One placed user widget. Its code is loaded only when `omamobile-widget
// scan` calls the folder ok (manifest valid, capabilities declared, qmllint
// clean); a URL with the folder's hash in it makes a changed widget load
// fresh. Anything that goes wrong (the scan's errors, a component that
// fails to compile or to be created) becomes an error card with the
// message, in this cell only: the home screen and the other widgets carry
// on. A tap on the card opens the widget's settings, with Edit with AI.
Item {
  id: frame

  // Set by Home.qml's cell, like every widget.
  property var home: null
  property var entry: null
  property bool editing: false
  // Someone can see it (set by Home.qml); the widget gets it as `shown`
  // when it declares that, and as host.shown.
  property bool shown: true

  readonly property string widgetId: entry ? UserWidgets.idOf(entry.type) : ""
  readonly property var card: home && widgetId ? home.userCard(widgetId) : ({ state: "waiting", message: "", url: "", record: null })
  readonly property var record: card.record || null
  readonly property var manifest: record && record.manifest ? record.manifest : null
  readonly property string url: card.state === "ok" ? card.url : ""

  property var component: null
  property string builtUrl: ""
  // Set when the home screen rebuilds this cell (a layout change), so no
  // late compile result is applied to a Loader that is going away.
  property bool gone: false
  Component.onDestruction: { gone = true; if (home && widgetId) home.guardEnd(widgetId) }

  // The crash guard (Home.qml) holds this widget until it has run a moment.
  Timer {
    id: settled
    interval: 3000
    onTriggered: if (frame.home) frame.home.guardEnd(frame.widgetId, true)
  }

  onUrlChanged: build()
  Component.onCompleted: build()

  // Compiled here first, so a QML error becomes this card's message; then
  // the Loader creates it with the contract's properties already set, so
  // the widget has them in its Component.onCompleted.
  function build() {
    component = null
    content.source = ""
    builtUrl = url
    if (!url) return
    var wanted = url
    // Compiled synchronously: a widget is one small local file, and an
    // asynchronous compile that finished after this cell was rebuilt
    // called setSource on a destroyed Loader and crashed the shell.
    if (home) home.guardBegin(widgetId, record ? record.hash : "")
    var c = Qt.createComponent(url)
    var finish = function() {
      if (frame.gone || frame.builtUrl !== wanted) return
      if (c.status === Component.Ready) {
        frame.component = c
        content.setSource(wanted, {
          host: host,
          settings: frame.entry && frame.entry.config ? frame.entry.config : ({}),
          editing: frame.editing,
          cellsWide: frame.entry ? frame.entry.w : 1,
          cellsHigh: frame.entry ? frame.entry.h : 1
        })
        settled.restart()
      } else if (c.status === Component.Error && frame.home) {
        frame.home.noteRuntimeError(frame.widgetId, c.errorString().trim())
        frame.home.guardEnd(frame.widgetId)
      }
    }
    if (c.status === Component.Loading) c.statusChanged.connect(finish)
    else finish()
  }

  WidgetHost {
    id: host
    home: frame.home
    instanceId: frame.entry ? frame.entry.id : ""
    widgetId: frame.widgetId
    dir: frame.record ? frame.record.dir : ""
    capabilities: frame.manifest && frame.manifest.capabilities ? frame.manifest.capabilities : []
    shown: frame.shown
  }

  Loader {
    id: content
    anchors.fill: parent
    active: frame.component !== null && frame.card.state === "ok"
    onLoaded: {
      // Kept up to date from here on, for the properties the widget
      // declares (WIDGETS.md lists them).
      var w = item
      var bind = function(name, value) { if (name in w) w[name] = value }
      bind("settings", Qt.binding(function() { return frame.entry && frame.entry.config ? frame.entry.config : ({}) }))
      bind("editing", Qt.binding(function() { return frame.editing }))
      bind("cellsWide", Qt.binding(function() { return frame.entry ? frame.entry.w : 1 }))
      bind("cellsHigh", Qt.binding(function() { return frame.entry ? frame.entry.h : 1 }))
      bind("shown", Qt.binding(function() { return frame.shown }))
    }
    onStatusChanged: {
      if (status === Loader.Error && frame.home)
        frame.home.noteRuntimeError(frame.widgetId, "It compiled but couldn't be created (a required property, or an error in its root object)")
    }
  }

  // ---------- the error card (also "looking for widgets" at startup)
  Column {
    visible: frame.card.state !== "ok"
    anchors.fill: parent
    anchors.margins: Style.spacing.xl
    spacing: Style.spacing.xs

    Row {
      width: parent.width
      spacing: Style.spacing.md
      Text {
        id: glyph
        textFormat: Text.PlainText
        text: frame.card.state === "waiting" ? (frame.manifest ? frame.manifest.icon : "󰕰") : "󰀦"
        color: frame.card.state === "waiting" ? Commons.Color.accent : Commons.Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.iconLarge
      }
      Text {
        width: parent.width - glyph.width - parent.spacing
        anchors.verticalCenter: glyph.verticalCenter
        textFormat: Text.PlainText
        text: frame.manifest ? frame.manifest.name : frame.widgetId
        color: frame.home ? frame.home.foreground : Commons.Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }
    }
    Text {
      width: parent.width
      height: Math.max(0, parent.height - glyph.height - hint.height - parent.spacing * 2)
      visible: height >= Readable.px(Style.font.caption)
      textFormat: Text.PlainText
      text: frame.card.message
      color: frame.home ? frame.home.dimForeground : Commons.Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Readable.px(Style.font.caption)
      wrapMode: Text.Wrap
      elide: Text.ElideRight
    }
    Text {
      id: hint
      width: parent.width
      visible: frame.card.state === "error" || frame.card.state === "missing"
      textFormat: Text.PlainText
      text: frame.card.state === "error" ? "Tap to fix with AI" : "Tap for settings"
      color: Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Readable.px(Style.font.caption)
      elide: Text.ElideRight
    }
  }

  MouseArea {
    anchors.fill: parent
    visible: frame.card.state !== "ok"
    enabled: !frame.editing
    onClicked: if (frame.home && frame.entry) frame.home.openSettings(frame.entry.id)
  }
}
