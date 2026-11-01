// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import qs.Commons
import qs.Commons as Commons

// A row of quick-settings toggles. Taps go through quick settings' own IPC
// (`toggleTile`), so each one does exactly what its tile does; "More" opens
// the sheet. Wi-Fi and Bluetooth state come straight from Quickshell;
// do-not-disturb is asked of the notification service when the widget
// appears, after a tap, and every 30 s.
Item {
  id: widget

  property var home: null
  property var entry: null
  property bool editing: false
  // Someone can see it (set by Home.qml): its timers wait while not.
  property bool shown: true

  readonly property color fg: home ? home.foreground : "white"
  property bool dnd: false

  readonly property var tiles: [
    { name: "wifi", label: "Wi-Fi", glyph: Networking.wifiEnabled ? "󰖩" : "󰖪", on: Networking.wifiEnabled === true },
    { name: "bluetooth", label: "Bluetooth", glyph: "󰂯",
      on: !!Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled === true },
    { name: "dnd", label: "Silence", glyph: widget.dnd ? "󰂛" : "󰂚", on: widget.dnd },
    { name: "more", label: "More", glyph: "󰒓", on: false }
  ]

  function ipc(args) {
    return ["qs", "ipc", "-p", Quickshell.shellDir, "call"].concat(args)
  }

  function tap(name) {
    if (name === "more") {
      Quickshell.execDetached(ipc(["shell", "summon", "omamobile.quicksettings", "{}"]))
      return
    }
    toggleProc.command = ipc(["shell", "call", "omamobile.quicksettings", "toggleTile", name])
    toggleProc.running = true
  }

  Process {
    id: toggleProc
    onExited: dndRead.restart()
  }

  Process {
    id: dndProc
    command: widget.ipc(["notifications", "dndState"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim().toLowerCase()
        widget.dnd = t === "on" || t === "true" || t === "1"
      }
    }
  }

  Timer { id: dndRead; interval: 400; onTriggered: if (!dndProc.running) dndProc.running = true }
  // Started again when shown, and triggeredOnStart reads it at once then.
  Timer { interval: 30000; repeat: true; running: widget.shown; triggeredOnStart: true; onTriggered: dndRead.restart() }

  Grid {
    anchors.centerIn: parent
    columns: widget.width >= widget.height * 1.8 ? 4 : 2
    readonly property real cell: Math.min((widget.width - Style.spacing.xl * 2) / columns,
                                          (widget.height - Style.spacing.lg * 2) / Math.ceil(4 / columns))

    Repeater {
      model: widget.tiles
      delegate: Item {
        required property var modelData
        width: parent.cell
        height: parent.cell

        Rectangle {
          anchors.centerIn: parent
          width: Math.min(56, Math.min(parent.width, parent.height) - Style.spacing.lg * 2)
          height: width
          radius: Math.min(Style.cornerRadius, width / 2)
          color: modelData.on ? Commons.Color.accent
            : touch.pressed ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.08)

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: modelData.glyph
            color: modelData.on ? Commons.Color.background : widget.fg
            font.family: Style.font.family
            font.pixelSize: Math.max(Style.font.iconLarge, parent.width * 0.42)
          }
        }

        MouseArea {
          id: touch
          anchors.fill: parent
          enabled: !widget.editing
          onClicked: widget.tap(modelData.name)
        }
      }
    }
  }
}
