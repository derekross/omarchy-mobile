// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Readable.js" as Readable

// The mobile network card a tap on the bar's signal opens, built from
// Omarchy's own panel parts (Panel, KeyboardPanel, ToggleSwitch and the
// label/value rows of its power and network cards), since Omarchy has no
// cellular card of its own. It reads omamobile-sitd's public state, and its
// switch turns the cellular radio on and off with omamobile-sit, as the Wi-Fi
// card's switch does Wi-Fi (mobile data stays on its quick-settings tile).
Panel {
  id: root
  moduleName: "omamobile.cellular"
  ipcTarget: "omamobile.cellular"

  property string glyph: ""
  property var modem: ({})
  property bool dataOn: false
  // The radio switch: the state sitd publishes lags the command by a few
  // seconds, so the switch shows what was asked until the state agrees.
  property bool radioBusy: false
  property bool radioWant: true
  property int radioWaits: 0

  readonly property bool present: !!modem && modem.present === true
  readonly property bool radioOff: present && modem.radio === "off"
  readonly property bool registered: present && (modem.registration === "home" || modem.registration === "roaming")
  readonly property int signal: registered ? Math.max(0, Math.min(100, Number(modem.signal) || 0)) : 0

  // sitd gives the network's name when the network sends one; otherwise the
  // name comes from mobile-broadband-provider-info by the network code
  // (carrier-name.py, beside this file).
  property string lookedUpName: ""
  property string lookedUpCode: ""
  readonly property string carrierScript: String(Qt.resolvedUrl("carrier-name.py")).replace(/^file:\/\//, "")

  function title() {
    if (!present) return "Mobile network"
    if (modem.operator_name) return modem.operator_name
    if (lookedUpName && lookedUpCode === modem.plmn) return lookedUpName
    return "Mobile network"
  }

  onModemChanged: {
    var code = modem && modem.plmn ? String(modem.plmn) : ""
    if (!modem.operator_name && /^[0-9]{5,6}$/.test(code) && code !== lookedUpCode && !nameProc.running) {
      nameProc.command = ["python3", "-I", root.carrierScript, code]
      nameProc.running = true
    }
  }

  Process {
    id: nameProc
    stdout: StdioCollector {
      onStreamFinished: {
        var parts = text.trim().split("\t")
        if (parts.length === 2) { root.lookedUpCode = parts[0]; root.lookedUpName = parts[1] }
      }
    }
  }

  function status() {
    if (!present) return "No modem"
    var sim = modem.sim || {}
    if (sim.state === "absent") return "No SIM"
    if (sim.state === "locked" || sim.state === "pin") return "SIM locked"
    if (radioOff) return "Cellular off"
    if (!registered) return "Searching"
    // As Omarchy's Wi-Fi card says "Not connected" with its switch off.
    if (!dataOn) return modem.registration === "roaming" ? "Roaming · mobile data off" : "Mobile data off"
    return modem.registration === "roaming" ? "Roaming" : "Connected"
  }

  function yesNo(value) { return value === true ? "Yes" : (value === false ? "No" : "—") }

  function refresh() {
    if (!stateFile.running) stateFile.running = true
    if (!dataProc.running) dataProc.running = true
  }

  function setRadio(on) {
    if (radioBusy) return
    radioBusy = true
    radioWant = on
    radioWaits = 0
    radioSet.command = ["omamobile-sit", "radio", on ? "on" : "off"]
    radioSet.running = true
  }

  onOpenedChanged: if (opened) refresh()

  Process {
    id: stateFile
    command: ["cat", Quickshell.env("OMAMOBILE_SIT_STATE") || "/run/omamobile-sit/state.json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.modem = JSON.parse(text).modem || {} } catch (e) { root.modem = {} }
      }
    }
  }

  Process {
    id: dataProc
    command: ["systemctl", "is-active", "--quiet", "omamobile-sit-data.service"]
    onExited: function(code) { root.dataOn = code === 0 }
  }

  Process {
    id: radioSet
    onExited: function(code) {
      if (code !== 0) { root.radioBusy = false; root.refresh(); return }
      radioWait.start()
    }
  }

  // Until sitd's state shows the radio as asked, or 15 s
  Timer {
    id: radioWait
    interval: 1000
    repeat: true
    onTriggered: {
      root.refresh()
      root.radioWaits += 1
      if (root.radioOff === !root.radioWant || root.radioWaits >= 15) { stop(); root.radioBusy = false }
    }
  }

  Timer { interval: 3000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    tooltipText: ""
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: signal glyph · carrier and state · data switch ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, cellSwitch.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.glyph
            color: root.bar.foreground
            opacity: root.registered && root.dataOn ? 1.0 : 0.5
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: cellSwitch.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: root.title()
              textFormat: Text.PlainText
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: root.status().toUpperCase()
              textFormat: Text.PlainText
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Readable.px(Style.font.caption)
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          ToggleSwitch {
            id: cellSwitch
            visible: root.present
            checked: root.radioBusy ? root.radioWant : !root.radioOff
            busy: root.radioBusy
            foreground: root.bar.foreground
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.setRadio(root.radioOff)
          }
        }

        // ---------- Signal bar, as the power card's charge bar ----------
        Item {
          visible: root.present
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          }

          Rectangle {
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.bar.foreground
            visible: root.signal > 0
            width: Math.max(barTrack.height, barTrack.width * root.signal / 100)
            Behavior on width { NumberAnimation { duration: Style.duration(320); easing.type: Easing.OutCubic } }
          }
        }

        // ---------- Details ----------
        Column {
          visible: root.present
          width: parent.width
          spacing: Style.spacing.labelGap

          InfoPair { label: "Network"; value: root.registered ? (modem.tech || "—") : "—" }
          InfoPair { label: "Signal"; value: root.registered ? root.signal + "%" : "—" }
          InfoPair { label: "Calls"; value: root.yesNo(modem.voice) }
          InfoPair { label: "Texts"; value: root.yesNo(modem.sms) }
          InfoPair { label: "Mobile data"; value: root.dataOn ? (modem.data ? "On" : "Connecting") : "Off" }
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
