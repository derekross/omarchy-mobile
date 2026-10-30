// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Readable.js" as Readable
import "AccessModel.js" as AccessModel

// The permission sheet itself: the scrim, and the card at the bottom with the
// app's icon, the question and two large buttons. Access.qml puts it in its
// layer-shell window; test/access-render.qml draws it offscreen.
//
// On its side (TOUCH-PLAN 2.4: 1040x480) the card keeps to 600 px, centred,
// and the two buttons sit side by side, Allow on the right, so the question
// and both answers fit 480 px of height.
Item {
  id: sheet

  // A request as AccessModel.parseRequest gives it (null: nothing to show).
  property var request: null
  // 0 hidden .. 1 shown: the card slides up from the bottom edge.
  property real reveal: 1
  signal answered(bool allow)

  readonly property int pad: Style.spacing.panelPadding
  readonly property color foreground: Commons.Color.popups.text
  readonly property bool wide: width > height

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.charAt(0) === "/") return "file://" + value
    return Quickshell.iconPath(value, true)
  }

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.menu.scrim
    opacity: sheet.reveal
  }

  // The scrim takes touches and does nothing: a question needs an answer.
  MouseArea { anchors.fill: parent }

  BorderSurface {
    id: card

    readonly property var r: sheet.request || ({})

    width: sheet.wide ? Math.min(parent.width - Style.gapsOut * 2, 600) : parent.width - Style.gapsOut * 2
    x: Math.round((parent.width - width) / 2)
    height: content.implicitHeight + card.contentTopInset + card.contentBottomInset
    y: parent.height - height - Style.gapsOut + Math.round((1 - sheet.reveal) * (height + Style.gapsOut))
    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
    radius: Style.cornerRadius
    padding: sheet.pad

    MouseArea { anchors.fill: parent }

    Column {
      id: content
      x: card.contentLeftInset
      y: card.contentTopInset
      width: card.width - card.contentLeftInset - card.contentRightInset
      spacing: Style.spacing.xxl
      topPadding: Style.spacing.xl

      // The app's icon (or its initial), with the permission's glyph.
      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 72
        height: 72

        Rectangle {
          anchors.fill: parent
          radius: Math.max(Style.cornerRadius, 18)
          color: Qt.rgba(sheet.foreground.r, sheet.foreground.g, sheet.foreground.b, 0.06)
        }

        Image {
          id: appIcon
          anchors.centerIn: parent
          width: 56
          height: 56
          fillMode: Image.PreserveAspectFit
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          source: sheet.iconSource(card.r.appIcon)
        }

        Text {
          anchors.centerIn: parent
          visible: appIcon.status !== Image.Ready
          textFormat: Text.PlainText
          text: AccessModel.initial(card.r.appName)
          color: sheet.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.displayLarge
          font.bold: true
        }

        Rectangle {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: -8
          anchors.bottomMargin: -8
          width: 32
          height: 32
          radius: 16
          color: Commons.Color.accent
          border.width: 2
          border.color: Commons.Color.popups.background

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: card.r.glyph || ""
            color: Commons.Color.popups.background
            font.family: Style.font.family
            font.pixelSize: Style.font.iconLarge
          }
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: card.r.title || ""
        color: sheet.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.display
        font.bold: true
        wrapMode: Text.Wrap
      }

      Text {
        width: parent.width
        visible: text !== ""
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: card.r.body || ""
        color: Readable.secondary(sheet.foreground, Commons.Color.popups.background)
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        lineHeight: 1.15
        wrapMode: Text.Wrap
      }

      Item { width: 1; height: Style.spacing.sm }

      // Stacked, Allow above; side by side on a wide screen, Allow on the
      // right (right to left puts the first child there).
      Grid {
        id: answers
        width: parent.width
        columns: sheet.wide ? 2 : 1
        columnSpacing: Style.spacing.lg
        rowSpacing: Style.spacing.xxl
        layoutDirection: sheet.wide ? Qt.RightToLeft : Qt.LeftToRight
        readonly property real buttonWidth: sheet.wide ? (width - columnSpacing) / 2 : width

        AnswerButton {
          width: answers.buttonWidth
          label: card.r.grantLabel || "Allow"
          primary: true
          onTapped: sheet.answered(true)
        }

        AnswerButton {
          width: answers.buttonWidth
          label: card.r.denyLabel || "Don't allow"
          onTapped: sheet.answered(false)
        }
      }
    }
  }

  // ---------------------------------------------------------------- pieces

  component AnswerButton: BorderSurface {
    id: button
    property string label: ""
    property bool primary: false
    property color foreground: Commons.Color.popups.text
    readonly property int touchSize: Math.max(56, Style.space(56))
    signal tapped()
    height: button.touchSize
    radius: Style.cornerRadius
    color: touch.pressed ? Style.pressedFillFor(button.foreground, Commons.Color.accent)
      : button.primary ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
      : Style.normalFillFor(button.foreground, Commons.Color.accent)
    borderSpec: Border.controlSpec(button.primary ? "selected" : "normal", button.foreground, Commons.Color.accent)

    Text {
      anchors.centerIn: parent
      width: parent.width - Style.spacing.lg * 2
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: button.label
      color: button.primary ? Commons.Color.accent : button.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      font.bold: true
      elide: Text.ElideRight
    }

    MouseArea {
      id: touch
      anchors.fill: parent
      onClicked: button.tapped()
    }
  }
}
