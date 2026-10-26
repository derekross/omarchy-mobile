// SPDX-License-Identifier: MIT
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Readable.js" as Readable

// A tile in the quick settings' edit mode: glyph and name, with a badge in
// the corner that says what a tap does (− removes from the sheet, + adds
// to it). It draws only; the edit grid owns the touch handling so a hold can
// turn into a drag that reorders.
BorderSurface {
  id: root

  property string icon: ""
  property string label: ""
  property bool adding: false
  property bool lifted: false

  property color foreground: Commons.Color.popups.text
  property color accent: Commons.Color.accent

  implicitHeight: Math.max(56, Style.space(60))
  radius: Style.cornerRadius
  scale: lifted ? 1.06 : 1
  z: lifted ? 10 : 0

  color: lifted ? Util.alpha(accent, Style.selectedFillAlpha) : Style.normalFillFor(foreground, accent)
  borderSpec: lifted
    ? Border.flat(accent, Math.max(1, Style.selectedBorderWidth || Style.normalBorderWidth))
    : Border.controlSpec("normal", foreground, accent)

  Behavior on scale { NumberAnimation { duration: 100 } }

  Column {
    anchors.centerIn: parent
    width: parent.width - Style.spacing.lg * 2
    spacing: Style.spacing.xxs

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.icon
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.iconLarge
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.label
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Readable.px(Style.font.caption)
      elide: Text.ElideRight
    }
  }

  // The badge: a filled circle in the top-right corner.
  Rectangle {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.spacing.xs
    width: Math.max(18, Style.space(20))
    height: width
    radius: width / 2
    color: root.adding ? root.accent : Util.alpha(root.foreground, 0.75)

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.adding ? "+" : "−"
      color: Commons.Color.popups.background
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }
}
