// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The page behind a user tile that has choices (TILES.md), drawn as the
// Screen record page: one row per choice, the current one marked. A tap on
// a row picks it; the owner runs the tile's choose command with it and puts
// this page away. The list scrolls when it is longer than the screen.
Item {
  id: root

  property bool opened: false
  property color foreground: Commons.Color.popups.text
  // The tile this page is for (its bare id), its label and its choices as
  // TilesModel.parseUserTiles gives them: [{ value, label }].
  property string tileId: ""
  property string title: ""
  property var choices: []
  // The value of the choice the tile's status names, or "".
  property string current: ""

  // The back glyph: the owner closes this and brings quick settings back.
  signal backRequested()
  // A row's tap: the owner runs the choose command with `value`.
  signal chosen(string value)

  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int pad: Style.spacing.panelPadding

  function open() { opened = true }
  function close() { opened = false }

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  PanelWindow {
    id: window

    visible: root.opened || root.reveal > 0
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-tile-choice"
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
          id: titleRow
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
            text: root.title
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }
        }

        Text {
          visible: root.choices.length === 0
          anchors.top: titleRow.bottom
          anchors.topMargin: root.pad
          anchors.left: parent.left
          anchors.right: parent.right
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          text: "Nothing to choose from"
          color: root.foreground
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        ListView {
          id: list
          anchors.top: titleRow.bottom
          anchors.topMargin: root.pad
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.spacing.md
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.choices

          delegate: BorderSurface {
            id: choiceRow
            required property var modelData
            readonly property bool selected: root.current !== "" && root.current === choiceRow.modelData.value
            width: list.width
            height: Math.max(root.touchSize, choiceLabel.implicitHeight + Style.spacing.lg * 2)
            radius: Style.cornerRadius
            color: choiceTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
              : choiceRow.selected ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
              : Style.normalFillFor(root.foreground, Commons.Color.accent)
            borderSpec: Border.controlSpec(choiceRow.selected ? "selected" : "normal", root.foreground, Commons.Color.accent)

            Text {
              id: choiceLabel
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.lg
              anchors.right: choiceMark.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: choiceRow.modelData.label
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: choiceRow.selected
              elide: Text.ElideRight
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

            // Lets go once the touch turns into a scroll of the list.
            TapHandler {
              id: choiceTouch
              gesturePolicy: TapHandler.DragThreshold
              onTapped: root.chosen(choiceRow.modelData.value)
            }
          }
        }
      }
    }
  }
}
