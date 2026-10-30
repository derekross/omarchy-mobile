// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Readable.js" as Readable

// The page behind the Screen record tile, after the Wi-Fi and Bluetooth
// pickers: choose the video's sound (what the phone plays, the microphone,
// or none) and start. The owner records through omamobile-screenrecord; a
// tap on the tile while recording stops it without this page.
Item {
  id: root

  property bool opened: false
  property color foreground: Commons.Color.popups.text
  // "system" | "mic" | "none"; the last choice is kept for the next time.
  property string audio: "mic"

  // The back glyph: the owner closes this and brings quick settings back.
  signal backRequested()
  // Start: the owner starts recording with `audio` and puts everything away.
  signal startRequested(string audio)

  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int pad: Style.spacing.panelPadding

  function open() { opened = true }
  function close() { opened = false }

  readonly property var choices: [
    { id: "system", glyph: "󰕾", title: "Device audio", detail: "What the phone plays: videos, apps, games" },
    { id: "mic", glyph: "󰍬", title: "Microphone", detail: "Your voice, for narration" },
    { id: "none", glyph: "󰝟", title: "No audio", detail: "Video only" }
  ]

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
      Keys.onEscapePressed: root.close()

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

        Column {
          anchors.top: header.bottom
          anchors.topMargin: root.pad
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.spacing.md

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: "Record the screen with"
            color: Readable.secondary(root.foreground, Commons.Color.popups.background)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.choices
            delegate: BorderSurface {
              id: choiceRow
              required property var modelData
              readonly property bool selected: root.audio === choiceRow.modelData.id
              width: parent.width
              height: Math.max(root.touchSize, choiceText.implicitHeight + Style.spacing.lg * 2)
              radius: Style.cornerRadius
              color: choiceTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
                : choiceRow.selected ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
                : Style.normalFillFor(root.foreground, Commons.Color.accent)
              borderSpec: Border.controlSpec(choiceRow.selected ? "selected" : "normal", root.foreground, Commons.Color.accent)

              Text {
                id: choiceGlyph
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: choiceRow.modelData.glyph
                color: choiceRow.selected ? Commons.Color.accent : root.foreground
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
                  text: choiceRow.modelData.title
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  wrapMode: Text.Wrap
                  text: choiceRow.modelData.detail
                  color: Readable.secondary(root.foreground, Commons.Color.popups.background)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }

              Text {
                id: choiceMark
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: choiceRow.selected ? "󰄵" : "󰄱"
                color: choiceRow.selected ? Commons.Color.accent : root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
              }

              MouseArea {
                id: choiceTouch
                anchors.fill: parent
                onClicked: root.audio = choiceRow.modelData.id
              }
            }
          }
        }

        SheetButton {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          label: "Start recording"
          primary: true
          foreground: root.foreground
          onTapped: root.startRequested(root.audio)
        }
      }
    }
  }
}
