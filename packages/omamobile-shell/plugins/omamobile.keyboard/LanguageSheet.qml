// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "KeyboardModel.js" as KeyboardModel

// The language sheet itself: the scrim, and a card at the bottom with one
// full-width row per language the keyboard has (the current one marked), and
// "Add a language", which turns the card into the list of the keyboard's
// other layouts. LanguageWindow.qml puts it in its layer-shell window over
// the keyboard; test/keyboard-render.qml draws it offscreen.
//
// A tap on a row switches and closes; a tap on the scrim, or a swipe down
// on the card, closes. Rows take their taps with a passive TapHandler (as
// the quick-settings tiles do), so a swipe that starts on a row still
// reaches the card's swipe underneath and never switches.
Item {
  id: sheet

  // KeyboardModel.parseListing's result (null: nothing loaded yet).
  property var listing: null
  // 0 hidden .. 1 shown: the card slides up from the bottom edge.
  property real reveal: 1
  // "languages" or "add"
  property string page: "languages"
  signal picked(string name)
  signal removed(string name)
  signal dismissed()

  readonly property int pad: Style.spacing.panelPadding
  readonly property color foreground: Commons.Color.popups.text
  readonly property bool wide: width > height
  // TOUCH-PLAN: rows at least 48 logical px, taller with a larger font
  readonly property int rowHeight: Math.max(56, Style.space(56))
  readonly property var rows: sheet.page === "add" ? KeyboardModel.addRows(sheet.listing) : KeyboardModel.languageRows(sheet.listing)

  function reset() { page = "languages"; swipe.offset = 0 }

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.menu.scrim
    opacity: sheet.reveal
  }

  // A tap outside the card closes the sheet.
  MouseArea {
    anchors.fill: parent
    onClicked: sheet.dismissed()
  }

  BorderSurface {
    id: card

    width: sheet.wide ? Math.min(parent.width - Style.gapsOut * 2, 600) : parent.width - Style.gapsOut * 2
    x: Math.round((parent.width - width) / 2)
    // Up to most of the screen; a longer list scrolls inside.
    readonly property real most: Math.round(sheet.height * (sheet.wide ? 0.9 : 0.75))
    readonly property real chrome: header.height + content.spacing + card.contentTopInset + card.contentBottomInset
    height: Math.min(most, chrome + list.contentHeight)
    y: sheet.height - height - Style.gapsOut + Math.round((1 - sheet.reveal) * (height + Style.gapsOut)) + Math.max(0, swipe.offset)
    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
    radius: Style.cornerRadius
    padding: sheet.pad

    // Swallows taps on the card (they never reach the scrim) and turns a
    // downward swipe anywhere on it into a close. Under the content, so the
    // list still scrolls when it is longer than the card.
    MouseArea {
      id: swipe
      anchors.fill: parent
      property real startY: 0
      property real offset: 0
      onPressed: function(mouse) { startY = mouse.y; offset = 0 }
      onPositionChanged: function(mouse) { offset = Math.max(0, mouse.y - startY) }
      onReleased: {
        if (offset > Style.space(60)) sheet.dismissed()
        else offset = 0
      }
      onCanceled: offset = 0
    }

    Column {
      id: content
      x: card.contentLeftInset
      y: card.contentTopInset
      width: card.width - card.contentLeftInset - card.contentRightInset
      height: card.height - card.contentTopInset - card.contentBottomInset
      spacing: Style.spacing.lg

      Item {
        id: header
        width: parent.width
        height: Math.max(48, Style.space(48))

        // The grabber: says "swipe me down"
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          width: 40
          height: 4
          radius: 2
          color: sheet.foreground
          opacity: 0.25
        }

        // Back, on the add page: a thumb-wide target
        Item {
          id: back
          visible: sheet.page === "add"
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: visible ? Math.max(48, Style.space(48)) : 0
          height: parent.height

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "󰁍"
            color: sheet.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.display
          }

          TapHandler {
            gesturePolicy: TapHandler.DragThreshold
            onTapped: sheet.page = "languages"
          }
        }

        Text {
          anchors.left: back.right
          anchors.leftMargin: back.visible ? 0 : Style.spacing.lg
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: 3
          textFormat: Text.PlainText
          text: sheet.page === "add" ? "Add a language" : "Keyboard language"
          color: sheet.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
          elide: Text.ElideRight
        }
      }

      ListView {
        id: list
        width: parent.width
        height: parent.height - header.height - content.spacing
        model: sheet.rows
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Only when it is cut short: a list with nothing to scroll would
        // take the swipe that closes the sheet.
        interactive: contentHeight > height + 1
        onModelChanged: positionViewAtBeginning()

        delegate: Item {
          id: rowItem
          required property var modelData
          readonly property var row: modelData

          width: list.width
          height: sheet.rowHeight

          Rectangle {
            anchors.fill: parent
            anchors.topMargin: Style.spacing.xxs
            anchors.bottomMargin: Style.spacing.xxs
            radius: Style.cornerRadius
            color: rowTap.pressed ? Style.pressedFillFor(sheet.foreground, Commons.Color.accent)
              : rowItem.row.current ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
              : "transparent"
          }

          // The current language's check, the add row's plus
          Text {
            id: mark
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            width: Style.font.display
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: rowItem.row.kind === "add" ? "󰐕" : rowItem.row.current ? "󰄬" : ""
            color: Commons.Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.iconLarge
          }

          Text {
            anchors.left: mark.right
            anchors.leftMargin: Style.spacing.lg
            anchors.right: remove.visible ? remove.left : parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: rowItem.row.label
            color: rowItem.row.current || rowItem.row.kind === "add" ? Commons.Color.accent : sheet.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: rowItem.row.current
            elide: Text.ElideRight
          }

          // The row's tap, left of the remove target (its own item, so a
          // tap there is never also a switch)
          Item {
            anchors.left: parent.left
            anchors.right: remove.visible ? remove.left : parent.right
            height: parent.height

            TapHandler {
              id: rowTap
              gesturePolicy: TapHandler.DragThreshold
              onTapped: {
                if (rowItem.row.kind === "add") sheet.page = "add"
                else sheet.picked(rowItem.row.name)
              }
            }
          }

          // Take a language off the list (not the current one, never the
          // last): its own thumb-wide target at the right edge.
          Item {
            id: remove
            visible: !!rowItem.row.removable
            anchors.right: parent.right
            width: Math.max(48, Style.space(48))
            height: parent.height

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "󰅖"
              color: sheet.foreground
              opacity: removeTap.pressed ? 1 : 0.55
              font.family: Style.font.family
              font.pixelSize: Style.font.iconLarge
            }

            TapHandler {
              id: removeTap
              gesturePolicy: TapHandler.DragThreshold
              onTapped: sheet.removed(rowItem.row.name)
            }
          }
        }
      }
    }
  }
}
