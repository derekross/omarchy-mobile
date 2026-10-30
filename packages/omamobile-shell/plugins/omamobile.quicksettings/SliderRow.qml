// SPDX-License-Identifier: MIT
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Readable.js" as Readable

// A full-width slider row for the quick settings sheet: a 44px tappable glyph
// (mute for volume), Omarchy's PanelSlider stretched to a thumb-sized hit area,
// and the value as a percentage. Without a backend only the glyph is dimmed:
// the text in the slider's place says why, and has to be read (TOUCH-PLAN 2.7).
Item {
  id: root

  property string icon: ""
  property real value: 0
  property bool available: true
  property string unavailableText: ""
  property color foreground: Commons.Color.popups.text

  signal moved(real value)
  signal released(real value)
  signal iconClicked()

  readonly property int touchSize: Math.max(44, Style.space(44))

  implicitHeight: touchSize

  Item {
    id: iconButton
    width: root.touchSize
    height: root.touchSize
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    opacity: root.available ? 1 : 0.45

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: iconTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent) : "transparent"
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.icon
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.display
    }

    MouseArea {
      id: iconTouch
      anchors.fill: parent
      enabled: root.available
      onClicked: root.iconClicked()
    }
  }

  PanelSlider {
    id: slider
    visible: root.available
    anchors.left: iconButton.right
    anchors.leftMargin: Style.spacing.lg
    anchors.right: valueText.left
    anchors.rightMargin: Style.spacing.lg
    anchors.verticalCenter: parent.verticalCenter
    height: root.touchSize
    value: root.value
    minimum: 0
    maximum: 1
    step: 0.05
    trackHeight: Math.max(6, Style.space(6))
    knobSize: Math.max(22, Style.space(22))
    trackColor: Style.selectedFillFor(root.foreground, Commons.Color.accent)
    fillColor: Commons.Color.accent
    knobColor: root.foreground
    tickColor: Commons.Color.popups.background
    onMoved: function(value) { root.moved(value) }
    onReleased: function(value) { root.released(value) }
  }

  Text {
    objectName: "sliderStatus"
    visible: !root.available
    anchors.left: iconButton.right
    anchors.leftMargin: Style.spacing.lg
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.unavailableText
    color: Readable.secondary(root.foreground, Commons.Color.popups.background)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Text {
    id: valueText
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: root.available ? Style.space(40) : 0
    horizontalAlignment: Text.AlignRight
    textFormat: Text.PlainText
    text: root.available ? Math.round(slider.liveValue * 100) + "%" : ""
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
}
