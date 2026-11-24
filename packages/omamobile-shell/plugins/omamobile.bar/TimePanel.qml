// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Readable.js" as Readable

// The small card a tap on the bar's clock opens: the date and the time,
// built from Omarchy's own panel parts as its power card is.
Panel {
  id: root
  moduleName: "omamobile.time"
  ipcTarget: "omamobile.time"

  readonly property var locale: Qt.locale(Commons.I18n.formatLocale)

  // The system's time zone: its name in the time zone database and its
  // abbreviation, both read from the system each time the card opens, so any
  // zone file works, one made locally included, and a zone redefined under
  // the same name shows its new abbreviation (Qt keeps a zone's data by name).
  property string zone: ""
  property string zoneAbbreviation: ""
  onOpenedChanged: if (opened && !zoneProc.running) zoneProc.running = true

  Process {
    id: zoneProc
    command: ["sh", "-c", "timedatectl show -p Timezone --value; date +%Z"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.split("\n")
        root.zone = (lines[0] || "").trim()
        root.zoneAbbreviation = (lines[1] || "").trim()
      }
    }
  }

  SystemClock { id: clock; precision: SystemClock.Seconds }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
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
      implicitHeight: hero.implicitHeight + (zoneRow.visible ? Style.space(14) + zoneRow.implicitHeight : 0)
      onCloseRequested: root.close()

      // ---------- Hero: clock glyph · day and date · the time ----------
      Item {
        id: hero
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroTime.implicitHeight)

        Text {
          id: heroIcon
          textFormat: Text.PlainText
          text: "\u{f0150}"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.display
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          id: heroLabels
          anchors.left: heroIcon.right
          anchors.leftMargin: Style.space(14)
          anchors.right: heroTime.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: clock.date.toLocaleDateString(root.locale, "dddd")
            textFormat: Text.PlainText
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            text: clock.date.toLocaleDateString(root.locale, "d MMMM yyyy").toUpperCase()
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

        Text {
          id: heroTime
          textFormat: Text.PlainText
          text: clock.date.toLocaleTimeString(root.locale, "HH:mm")
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.displayLarge
          font.bold: true
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      // ---------- The time zone ----------
      Row {
        id: zoneRow
        visible: root.zone !== ""
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: hero.bottom
        anchors.topMargin: Style.space(14)
        spacing: Style.space(8)

        Text {
          id: zoneLabel
          text: "Time zone"
          textFormat: Text.PlainText
          color: root.bar.foreground
          opacity: 0.6
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Item { width: Math.max(0, zoneRow.width - zoneLabel.implicitWidth - zoneValue.implicitWidth - zoneRow.spacing * 2); height: 1 }
        Text {
          id: zoneValue
          text: root.zone.replace(/_/g, " ") + (root.zoneAbbreviation ? " (" + root.zoneAbbreviation + ")" : "")
          textFormat: Text.PlainText
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
