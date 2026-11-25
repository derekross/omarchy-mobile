// SPDX-License-Identifier: MIT
import QtQuick
import "StatusModel.js" as StatusModel

// The battery in the status bar, in the style shell.json's bar.batteryStyle
// picks (StatusModel.batteryStyle):
//   icon               the upright glyph (Omarchy's power panel set)
//   percent            the number only
//   icon-percent       the glyph and the number (the default)
//   horizontal         a drawn battery lying on its side
//   horizontal-percent the same, a little wider, with the number inside
// While charging the bolt is always shown, whatever the style: the charging
// glyphs carry it, and the styles without one get a bolt beside them.
// A pure view: the bar hands it the reading and the colours, so the render
// test can draw every style without a battery.
Row {
  id: root

  property string style: "icon-percent"
  property int percent: -1
  property bool charging: false
  property bool full: false
  property color foreground: "white"
  property color background: "black"
  property color urgent: "red"
  property string fontFamily: ""
  property int iconPx: 22
  property int textPx: 14
  // Height of the strip the indicator sits in (the bar's 44 px).
  property int barSize: 44

  readonly property bool low: StatusModel.batteryLow(percent, charging)
  readonly property color tint: low ? urgent : foreground
  readonly property bool horizontal: style === "horizontal" || style === "horizontal-percent"
  readonly property bool withGlyph: style === "icon" || style === "icon-percent"
  readonly property bool withText: style === "percent" || style === "icon-percent"
  readonly property bool boltBeside: charging && !withGlyph
  readonly property real level: Math.max(0, Math.min(1, percent / 100))

  spacing: Math.max(2, Math.round(textPx * 0.25))

  Text {
    objectName: "batteryBolt"
    visible: root.boltBeside
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: StatusModel.boltGlyph()
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.horizontal ? root.textPx + 2 : root.textPx
  }

  Text {
    objectName: "batteryGlyph"
    visible: root.withGlyph
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: StatusModel.batteryIcon(root.percent, root.charging, root.full)
    color: root.tint
    font.family: root.fontFamily
    font.pixelSize: root.iconPx
  }

  // The battery lying down: an outline, a fill as long as the charge, and
  // the terminal nub on the right. With the number inside it is drawn
  // twice, clipped at the fill's edge: the background colour over the fill,
  // the foreground over the empty part, so it reads at any charge.
  Item {
    id: body
    objectName: "batteryHorizontal"
    visible: root.horizontal
    anchors.verticalCenter: parent.verticalCenter
    readonly property bool withNumber: root.style === "horizontal-percent"
    readonly property int bodyH: withNumber ? Math.round(root.barSize * 0.40) : Math.round(root.barSize * 0.30)
    readonly property int bodyW: withNumber ? Math.round(bodyH * 2.1) : Math.round(bodyH * 2.0)
    readonly property int stroke: Math.max(1, Math.round(bodyH / 9))
    readonly property int nubW: Math.max(2, Math.round(bodyH * 0.16))
    width: bodyW + nubW
    height: bodyH

    Rectangle {
      id: outline
      width: body.bodyW
      height: body.bodyH
      radius: Math.round(body.bodyH * 0.25)
      color: "transparent"
      border.width: body.stroke
      border.color: root.tint
    }

    Rectangle {
      id: fill
      objectName: "batteryFill"
      readonly property int inset: body.stroke + Math.max(1, Math.round(body.stroke * 0.8))
      readonly property int room: body.bodyW - inset * 2
      x: inset
      y: inset
      height: body.bodyH - inset * 2
      // A sliver stays visible at 1-4 % so an almost flat battery still
      // shows a red mark, and nothing at all for no reading.
      width: root.percent < 0 ? 0 : Math.max(Math.round(body.stroke), Math.round(room * root.level))
      radius: Math.max(0, outline.radius - inset)
      color: root.tint
    }

    Rectangle {
      x: body.bodyW
      anchors.verticalCenter: parent.verticalCenter
      width: body.nubW
      height: Math.round(body.bodyH * 0.42)
      radius: Math.round(width / 2)
      color: root.tint
    }

    // The number inside: in the foreground colour over the whole body, then
    // again in the background colour clipped to the fill's rectangle, so the
    // part of a digit over the fill reads dark-on-light (or the reverse) and
    // the part over the empty body or the outline keeps the foreground.
    Text {
      id: number
      visible: body.withNumber && root.percent >= 0
      width: body.bodyW
      height: body.bodyH
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      textFormat: Text.PlainText
      text: String(root.percent)
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Math.round(body.bodyH * 0.68)
      font.bold: true
    }
    Item {
      visible: number.visible
      x: fill.x
      y: fill.y
      width: fill.width
      height: fill.height
      clip: true
      Text {
        x: -parent.x
        y: -parent.y
        width: number.width
        height: number.height
        horizontalAlignment: number.horizontalAlignment
        verticalAlignment: number.verticalAlignment
        textFormat: Text.PlainText
        text: number.text
        color: root.background
        font: number.font
      }
    }
  }

  Text {
    objectName: "batteryPercent"
    visible: root.withText
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.percent + "%"
    color: root.style === "percent" ? root.tint : root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.textPx
    font.bold: root.style === "percent"
  }
}
