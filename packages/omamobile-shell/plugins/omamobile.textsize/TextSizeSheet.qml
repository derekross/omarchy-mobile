// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TextSizeModel.js" as Model
import "Readable.js" as Readable

// The Text size page itself: the scrim and a card with the preview line at
// the chosen size, one row per step with its label drawn at that step's
// size (the chosen one ticked), and the note on what changes when.
// TextSize.qml puts it in its layer-shell window; test/textsize-render.qml
// draws it offscreen.
Item {
  id: sheet

  // [{ name, label, px }] (TextSizeModel.parse)
  property var steps: Model.FALLBACK_STEPS
  // The step shown as chosen
  property string shown: "default"
  property bool failed: false
  property bool opened: true
  // 0 hidden .. 1 shown
  property real reveal: 1
  signal chosen(string name)
  signal back()
  signal dismissed()

  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int pad: Style.spacing.panelPadding
  readonly property color foreground: Commons.Color.popups.text

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.menu.scrim
    opacity: sheet.reveal
  }

  MouseArea {
    anchors.fill: parent
    onClicked: sheet.dismissed()
  }

  BorderSurface {
    id: card
    objectName: "textSizeCard"

    x: Style.gapsOut
    width: parent.width - Style.gapsOut * 2
    height: parent.height - Style.gapsOut * 2
    y: Style.gapsOut + Math.round((1 - sheet.reveal) * Style.space(60))
    opacity: sheet.reveal
    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
    radius: Style.cornerRadius
    padding: sheet.pad

    focus: sheet.opened
    Keys.onEscapePressed: sheet.back()

    MouseArea { anchors.fill: parent }

    Item {
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset

      Item {
        id: headerRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: sheet.touchSize

        GlyphTap {
          id: backButton
          objectName: "textSizeBack"
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          glyph: "󰁍"
          onTapped: sheet.back()
        }

        Text {
          anchors.left: backButton.right
          anchors.leftMargin: Style.spacing.lg
          anchors.right: closeButton.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Text size"
          color: sheet.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }

        GlyphTap {
          id: closeButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          glyph: "󰅖"
          onTapped: sheet.dismissed()
        }
      }

      Flickable {
        id: flick
        anchors.top: headerRow.bottom
        anchors.topMargin: Style.spacing.lg
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: column
          width: flick.width
          spacing: Style.spacing.xl

          // ---------- The preview, at the chosen size
          Rectangle {
            objectName: "textSizePreview"
            width: parent.width
            height: previewText.implicitHeight + Style.spacing.xl * 2
            radius: Style.cornerRadius
            color: Util.alpha(sheet.foreground, 0.06)

            Text {
              id: previewText
              x: Style.spacing.xl
              width: parent.width - Style.spacing.xl * 2
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: Model.PREVIEW
              color: sheet.foreground
              font.family: Style.font.family
              font.pixelSize: Model.previewPx(sheet.steps, sheet.shown)
              wrapMode: Text.Wrap
            }
          }

          // ---------- The steps, each at its own size
          Column {
            width: parent.width

            Repeater {
              model: sheet.steps

              delegate: Item {
                id: stepRow
                required property var modelData
                readonly property bool isCurrent: modelData.name === sheet.shown

                objectName: "textSizeStep-" + modelData.name
                width: parent.width
                height: Math.max(sheet.touchSize, stepLabel.implicitHeight + Style.spacing.md * 2)
                Accessible.role: Accessible.RadioButton
                Accessible.name: modelData.label
                Accessible.checked: isCurrent

                Rectangle {
                  anchors.fill: parent
                  anchors.topMargin: Style.spacing.xxs
                  anchors.bottomMargin: Style.spacing.xxs
                  radius: Style.cornerRadius
                  color: stepTap.pressed ? Style.pressedFillFor(sheet.foreground, Commons.Color.accent)
                    : stepRow.isCurrent ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
                    : "transparent"
                }

                Text {
                  id: mark
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.lg
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.font.iconLarge
                  horizontalAlignment: Text.AlignHCenter
                  textFormat: Text.PlainText
                  text: stepRow.isCurrent ? "󰄬" : ""
                  color: Commons.Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.iconLarge
                }

                Text {
                  id: stepLabel
                  anchors.left: mark.right
                  anchors.leftMargin: Style.spacing.lg
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.lg
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: stepRow.modelData.label
                  color: stepRow.isCurrent ? Commons.Color.accent : sheet.foreground
                  font.family: Style.font.family
                  font.pixelSize: Model.labelPx(stepRow.modelData.px)
                  font.bold: stepRow.isCurrent
                  elide: Text.ElideRight
                }

                // A passive tap, as on the quick-settings tiles: a swipe
                // that starts on a row scrolls the page and picks nothing.
                TapHandler {
                  id: stepTap
                  gesturePolicy: TapHandler.DragThreshold
                  onTapped: sheet.chosen(stepRow.modelData.name)
                }
              }
            }
          }

          Text {
            objectName: "textSizeNote"
            width: parent.width
            textFormat: Text.PlainText
            text: Model.NOTE
            color: sheet.foreground
            opacity: 0.7
            font.family: Style.font.family
            font.pixelSize: Readable.px(Style.font.bodySmall)
            wrapMode: Text.Wrap
          }

          Text {
            width: parent.width
            visible: sheet.failed
            textFormat: Text.PlainText
            text: "Not every app could be changed. omamobile-text-size in a terminal says which."
            color: Commons.Color.urgent
            font.family: Style.font.family
            font.pixelSize: Readable.px(Style.font.bodySmall)
            wrapMode: Text.Wrap
          }
        }
      }
    }
  }

  // Inline components have their own scope: no `root` in here.
  component GlyphTap: Item {
    id: glyphItem
    property string glyph: ""
    property color foreground: Commons.Color.popups.text
    readonly property int touchSize: Math.max(44, Style.space(48))
    signal tapped()
    width: glyphItem.touchSize
    height: glyphItem.touchSize

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: glyphTouch.pressed ? Style.pressedFillFor(glyphItem.foreground, Commons.Color.accent) : "transparent"
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: glyphItem.glyph
      color: glyphItem.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.iconLarge
    }

    MouseArea {
      id: glyphTouch
      anchors.fill: parent
      onClicked: glyphItem.tapped()
    }
  }
}
