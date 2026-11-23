// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The page behind the Screen record tile, after the Wi-Fi and Bluetooth
// pickers: choose what to record (full screen, or an area picked by touch
// after Start) and the sound (none, the phone's sound + the microphone,
// the phone's sound, the microphone), and start. Call recording is listed
// greyed out until it can work (omamobile-screenrecord call-status). Start
// is disabled while the phone is above the start limit (59 C). The owner records through omamobile-screenrecord; a
// tap on the tile while recording stops it without this page.
Item {
  id: root

  property bool opened: false
  property color foreground: Commons.Color.popups.text
  // "none" | "both" | "system" | "mic"; the last choice is kept for the next time.
  property string audio: "mic"
  // "full" | "pick"
  property string area: "full"
  // From omamobile-screenrecord heat / call-status, read when the page opens.
  property int heat: -1
  property int heatStart: 59
  readonly property bool tooWarm: heat > heatStart
  property var callState: ({ state: "needs-modem", reason: "Needs the modem" })

  // The back glyph: the owner closes this and brings quick settings back.
  signal backRequested()
  // Start: the owner starts recording with `audio` and puts everything away.
  signal startRequested(string audio, string area)

  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int pad: Style.spacing.panelPadding

  function open() {
    opened = true
    if (!heatProc.running) heatProc.running = true
    if (!callProc.running) callProc.running = true
  }
  function close() { opened = false }

  readonly property var areas: [
    { id: "full", glyph: "󰍹", title: "Full screen", detail: "Everything on the screen" },
    { id: "pick", glyph: "󰩭", title: "Pick an area", detail: "After Start, drag a box over the part to record" }
  ]
  readonly property var choices: [
    { id: "none", glyph: "󰝟", title: "No audio", detail: "Video only" },
    { id: "both", glyph: "󰕾", title: "Apps and microphone", detail: "What the phone plays, and your voice" },
    { id: "system", glyph: "󰓃", title: "Apps only", detail: "What the phone plays: videos, apps, games" },
    { id: "mic", glyph: "󰍬", title: "Microphone only", detail: "Your voice, for narration" }
  ]

  Process {
    id: heatProc
    command: ["omamobile-screenrecord", "heat"]
    stdout: StdioCollector {
      waitForEnd: true
      // "<hottest C> <start limit>"
      onStreamFinished: {
        var f = String(text).trim().split(/\s+/)
        var n = parseInt(f[0], 10), g = parseInt(f[1], 10)
        root.heat = isNaN(n) ? -1 : n
        if (!isNaN(g)) root.heatStart = g
      }
    }
  }
  Process {
    id: callProc
    command: ["omamobile-screenrecord", "call-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.callState = JSON.parse(String(text).trim()) }
        catch (e) { root.callState = { state: "needs-modem", reason: "Needs the modem" } }
      }
    }
  }

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  PanelWindow {
    id: window

    visible: root.opened || root.reveal > 0
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-record"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
      opacity: root.reveal
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: panel

      x: Style.gapsOut
      width: parent.width - Style.gapsOut * 2
      height: parent.height - Style.gapsOut * 2
      y: Style.gapsOut + Math.round((1 - root.reveal) * Style.space(60))
      opacity: root.reveal
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      padding: root.pad

      focus: root.opened
      // Back to quick settings, as the header's back button.
      Keys.onEscapePressed: root.backRequested()

      // Swallow taps so they don't reach the scrim.
      MouseArea { anchors.fill: parent }

      Item {
        id: body
        anchors.fill: parent
        anchors.topMargin: panel.contentTopInset
        anchors.rightMargin: panel.contentRightInset
        anchors.bottomMargin: panel.contentBottomInset
        anchors.leftMargin: panel.contentLeftInset

        // ---------- Header: back and title
        Item {
          id: header
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.touchSize

          GlyphButton {
            id: back
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰁍"
            onTapped: root.backRequested()
          }

          Text {
            anchors.left: back.right
            anchors.leftMargin: Style.spacing.lg
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Screen record"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }
        }

        Flickable {
          id: optionsFlick
          anchors.top: header.bottom
          anchors.topMargin: root.pad
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: startButton.top
          anchors.bottomMargin: root.pad
          contentHeight: options.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: options
            width: optionsFlick.width
            spacing: Style.spacing.md

            SectionLabel { text: "Record"; fg: root.foreground }
            Repeater {
              model: root.areas
              delegate: ChoiceRow {
                required property var modelData
                fg: root.foreground
                minHeight: root.touchSize
                choice: modelData
                selected: root.area === modelData.id
                onPicked: root.area = modelData.id
              }
            }

            SectionLabel { text: "Sound"; fg: root.foreground }
            Repeater {
              model: root.choices
              delegate: ChoiceRow {
                required property var modelData
                fg: root.foreground
                minHeight: root.touchSize
                choice: modelData
                selected: root.audio === modelData.id
                onPicked: root.audio = modelData.id
              }
            }

            // Call recording: greyed out until the modem works, and where
            // the law does not allow it; a consent notice where unknown.
            ChoiceRow {
              objectName: "callRecordingRow"
              fg: root.foreground
              minHeight: root.touchSize
              choice: ({ glyph: "󰏻", title: "Call recording",
                detail: root.callState.state === "needs-modem" ? "Needs the modem"
                  : root.callState.state === "blocked" ? "Unavailable for legal reasons: " + root.callState.reason
                  : root.callState.state === "consent" ? root.callState.reason
                  : "Records both sides of a call" })
              selected: false
              enabled: false
              opacity: 0.45
            }

            Text {
              objectName: "heatNote"
              visible: root.tooWarm
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: "The phone is warm (" + root.heat + " C). Recording starts at " + root.heatStart + " C or cooler."
              color: Commons.Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }
        }

        SheetButton {
          id: startButton
          enabled: !root.tooWarm
          opacity: enabled ? 1 : 0.45
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          label: "Start recording"
          primary: true
          foreground: root.foreground
          onTapped: if (enabled) root.startRequested(root.audio, root.area)
        }
      }
    }
  }

  component SectionLabel: Text {
    property color fg: "white"
    width: parent ? parent.width : 0
    textFormat: Text.PlainText
    color: fg
    opacity: 0.7
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.bold: true
  }

  component ChoiceRow: BorderSurface {
    id: choiceRow
    property var choice: ({})
    property color fg: "white"
    property int minHeight: 44
    property bool selected: false
    signal picked()
    width: parent ? parent.width : 0
    height: Math.max(minHeight, choiceText.implicitHeight + Style.spacing.lg * 2)
    radius: Style.cornerRadius
    color: choiceTouch.pressed ? Style.pressedFillFor(fg, Commons.Color.accent)
      : choiceRow.selected ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
      : Style.normalFillFor(fg, Commons.Color.accent)
    borderSpec: Border.controlSpec(choiceRow.selected ? "selected" : "normal", fg, Commons.Color.accent)

    Text {
      id: choiceGlyph
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: choiceRow.choice.glyph || ""
      color: choiceRow.selected ? Commons.Color.accent : fg
      font.family: Style.font.family
      font.pixelSize: Style.font.title
    }

    Column {
      id: choiceText
      anchors.left: choiceGlyph.right
      anchors.leftMargin: Style.spacing.lg
      anchors.right: choiceMark.left
      anchors.rightMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xs
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: choiceRow.choice.title || ""
        color: fg
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: choiceRow.choice.detail || ""
        color: fg
        opacity: 0.7
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    Text {
      id: choiceMark
      visible: choiceRow.enabled
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: choiceRow.selected ? "󰄵" : "󰄱"
      color: choiceRow.selected ? Commons.Color.accent : fg
      font.family: Style.font.family
      font.pixelSize: Style.font.title
    }

    MouseArea {
      id: choiceTouch
      anchors.fill: parent
      enabled: choiceRow.enabled
      onClicked: choiceRow.picked()
    }
  }
}
