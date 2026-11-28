// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "StatusModel.js" as StatusModel

// What the status bar shows: the clock, the call chip and the unread count
// on the left, the status row on the right, kept off the front camera's
// hole. A view of `bar` (Bar.qml hands itself in; test/bar-cutout-render
// hands a stand-in with the same properties, so its checks see this layout).
//
// The hole is a zone of the strip no item may reach (StatusModel.cutout and
// cutoutZone): the left group ends before it and the right row starts after
// it. Where a side has no room, it sheds items in StatusModel's order
// (LEFT_SHED, RIGHT_SHED) rather than run into the hole, and finds them
// again when the text size, the items or the width change. A shed item is
// hidden, so its tap (bar.cardsOnTap) goes with it.
Item {
  id: strip

  property var bar: null
  // The cutout to keep clear ({ center, width }, or null) and the screen's
  // size, which says whether it is in the bar at all.
  property var cutout: StatusModel.CUTOUT_DEFAULT
  property real screenWidth: width
  property real screenHeight: 0

  readonly property var zone: StatusModel.cutoutZone(cutout, width, screenWidth, screenHeight)
  readonly property int margin: Style.spacing.huge
  readonly property real chipWidth: chipGlyph.implicitWidth + Style.spacing.xs + chipTime.implicitWidth + Style.spacing.lg * 2

  // Each item's width from its own text (never a Row's, which follows what
  // is shown), 0 where it has nothing to show.
  readonly property var leftItems: [
    { id: "clock", w: clockText.implicitWidth },
    { id: "call", w: bar && bar.callChip !== "" ? chipWidth : 0 },
    { id: "unread", w: bar && bar.showUnread && bar.unread > 0 ? unreadPill.width : 0 }
  ]
  readonly property var rightItems: [
    { id: "dnd", w: bar && bar.showDnd && bar.doNotDisturb ? dndGlyph.implicitWidth : 0 },
    { id: "bluetooth", w: bar && bar.showBluetooth && bar.bluetoothEnabled ? bluetoothGlyph.implicitWidth : 0 },
    { id: "cell", w: bar && bar.showCell && bar.cellGlyph !== "" ? cellGlyphText.implicitWidth : 0 },
    { id: "cellText", w: cellWords.text !== "" ? Style.spacing.xs + cellWords.implicitWidth : 0, attach: true },
    { id: "wifi", w: bar && bar.showWifi && bar.networkIcon !== "" ? networkGlyph.implicitWidth : 0 },
    { id: "battery", w: bar && bar.hasBattery ? batteryItem.compactWidth : 0 },
    { id: "batteryText", w: bar && bar.hasBattery ? batteryItem.textWidth : 0, attach: true }
  ]
  readonly property var fit: StatusModel.fitBar({
    width: width, margin: margin, zone: zone, groupGap: Style.spacing.xl,
    leftSpacing: Style.spacing.lg, rightSpacing: Style.spacing.xl,
    left: leftItems, right: rightItems
  })

  Item {
    id: content
    anchors.fill: parent
    anchors.leftMargin: strip.margin
    anchors.rightMargin: strip.margin

    Text {
      id: clockText
      objectName: "barClock"
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: bar.clockText
      color: bar.foreground
      font.family: bar.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    // The time card (TimePanel.qml), unseen but for its popup, opened by a
    // tap on the clock; a pull still opens quick settings.
    Loader {
      id: timeCard
      anchors.fill: clockText
      active: bar.cardsOnTap
      // By file, not as an inline TimePanel, so the strip loads where no
      // window backend is (test/bar-cutout-render).
      source: "TimePanel.qml"
      onLoaded: { item.bar = strip.bar; item.opacity = 0 }
    }

    MouseArea {
      x: clockText.x - Style.space(8)
      // Nothing past the clock's right edge: the unread count and the
      // call chip sit there and take their own taps.
      width: clockText.width + Style.space(8)
      height: parent.height
      enabled: bar.cardsOnTap
      property real pressY: 0
      property bool pulled: false
      onPressed: function(mouse) { pressY = mouse.y; pulled = false }
      onPositionChanged: function(mouse) {
        if (!pulled && mouse.y - pressY > Style.space(14)) { pulled = true; bar.openQuickSettings() }
      }
      onClicked: if (!pulled && timeCard.item) timeCard.item.toggle()
      function triggerPress(button) { if (timeCard.item) timeCard.item.toggle() }
      Component.onCompleted: bar.clickTargets = bar.clickTargets.concat([this])
      Component.onDestruction: bar.clickTargets = bar.clickTargets.filter(function(t) { return t !== this }, this)
    }

    // The call in progress, beside the clock; a tap opens the Phone
    // app's in-call screen (the bar is never shown over the lock).
    Rectangle {
      id: callChipPill
      objectName: "callChip"
      visible: bar.callChip !== "" && strip.fit.show.call
      z: 2
      anchors.left: clockText.right
      anchors.leftMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      height: Math.round(bar.barSize * 0.66)
      width: strip.chipWidth
      radius: height / 2
      color: chipTap.pressed ? Qt.darker("#1e9e53", 1.2) : "#1e9e53"

      Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: Style.spacing.xs
        Text { id: chipGlyph; anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: String.fromCodePoint(0xF03F2); color: "white"; font.family: bar.fontFamily; font.pixelSize: Style.font.body }
        Text { id: chipTime; anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: bar.callChip; color: "white"; font.family: bar.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
      }

      // The bar's full height (44 px), not the 29 px pill, so a tap
      // just above or below the chip opens the call, not quick settings.
      MouseArea {
        id: chipTap
        anchors.centerIn: parent
        width: parent.width
        height: Math.max(parent.height, bar.barSize)
        onClicked: Quickshell.execDetached(["omaphone", "--in-call"])
      }
    }

    // Notifications not yet seen in the quick-settings shade: a count in
    // an accent pill, beside the clock (after the call chip). Not in the
    // right-hand row: that row grows leftwards with every glyph, and on a
    // phone with Bluetooth, a modem, Wi-Fi and the battery's percentage
    // its first item ended under the camera cutout. The strip's tap
    // opens the shade.
    Rectangle {
      id: unreadPill
      objectName: "unreadNotifications"
      visible: bar.showUnread && bar.unread > 0 && strip.fit.show.unread
      anchors.left: callChipPill.visible ? callChipPill.right : clockText.right
      anchors.leftMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(18, Math.round(bar.barSize * 0.45))
      width: Math.max(height, unreadText.implicitWidth + Style.spacing.md * 2)
      radius: height / 2
      color: Commons.Color.accent

      Text {
        id: unreadText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: String(bar.unread)
        color: bar.background
        font.family: bar.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }

    Row {
      id: status
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xl

      StatusGlyph {
        id: dndGlyph
        objectName: "barDnd"
        visible: bar.showDnd && bar.doNotDisturb && strip.fit.show.dnd
        text: "󰂛"
      }

      Item {
        objectName: "barBluetooth"
        visible: bar.showBluetooth && bar.bluetoothEnabled && strip.fit.show.bluetooth
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: bluetoothGlyph.implicitWidth
        implicitHeight: strip.height

        StatusGlyph {
          id: bluetoothGlyph
          text: bar.bluetoothConnected ? "󰂱" : "󰂯"
        }

        // With bar.cardsOnTap, a tap opens quick settings' Bluetooth panel
        // (not Omarchy's card: the phone's panel makes the phone visible
        // while it is open and shows the code a pairing asks to confirm);
        // a pull opens quick settings.
        MouseArea {
          anchors.fill: parent
          anchors.leftMargin: -Style.space(8)
          anchors.rightMargin: -Style.space(8)
          enabled: bar.cardsOnTap
          property real pressY: 0
          property bool pulled: false
          onPressed: function(mouse) { pressY = mouse.y; pulled = false }
          onPositionChanged: function(mouse) {
            if (!pulled && mouse.y - pressY > Style.space(14)) { pulled = true; bar.openQuickSettings() }
          }
          onClicked: if (!pulled) bar.openBluetoothPanel()
          function triggerPress(button) { bar.openBluetoothPanel() }
          Component.onCompleted: bar.clickTargets = bar.clickTargets.concat([this])
          Component.onDestruction: bar.clickTargets = bar.clickTargets.filter(function(t) { return t !== this }, this)
        }
      }

      Item {
        objectName: "barCell"
        visible: bar.showCell && bar.cellGlyph !== "" && strip.fit.show.cell
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: cellRow.implicitWidth
        implicitHeight: strip.height

        Row {
          id: cellRow
          spacing: Style.spacing.xs
          anchors.verticalCenter: parent.verticalCenter
          opacity: bar.cellSearching ? 0.55 : 1

          StatusGlyph { id: cellGlyphText; text: bar.cellGlyph }
          Text {
            id: cellWords
            objectName: "barCellText"
            visible: text !== "" && strip.fit.show.cellText
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: bar.cellText
            color: bar.foreground
            font.family: bar.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        // The mobile network card (CellularPanel.qml), unseen but for its popup.
        Loader {
          id: cellCard
          anchors.fill: parent
          active: bar.cardsOnTap
          source: "CellularPanel.qml"
          onLoaded: {
            item.bar = strip.bar
            item.glyph = Qt.binding(function() { return strip.bar.cellGlyph })
            item.opacity = 0
          }
        }

        // With bar.cardsOnTap, a tap opens the card; a pull opens quick settings.
        MouseArea {
          anchors.fill: parent
          anchors.leftMargin: -Style.space(8)
          anchors.rightMargin: -Style.space(8)
          enabled: bar.cardsOnTap
          property real pressY: 0
          property bool pulled: false
          onPressed: function(mouse) { pressY = mouse.y; pulled = false }
          onPositionChanged: function(mouse) {
            if (!pulled && mouse.y - pressY > Style.space(14)) { pulled = true; bar.openQuickSettings() }
          }
          onClicked: if (!pulled && cellCard.item) cellCard.item.toggle()
          function triggerPress(button) { if (cellCard.item) cellCard.item.toggle() }
          Component.onCompleted: bar.clickTargets = bar.clickTargets.concat([this])
          Component.onDestruction: bar.clickTargets = bar.clickTargets.filter(function(t) { return t !== this }, this)
        }
      }

      Item {
        objectName: "barWifi"
        visible: bar.showWifi && bar.networkIcon !== "" && strip.fit.show.wifi
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: networkGlyph.implicitWidth
        implicitHeight: strip.height

        StatusGlyph {
          id: networkGlyph
          text: bar.networkIcon
          opacity: bar.networkDim ? 0.55 : 1
        }

        // Omarchy's network panel, unseen but for its popup.
        Loader {
          id: networkPanel
          anchors.fill: parent
          active: bar.cardsOnTap
          source: "file://" + bar.omarchyPath + "/shell/plugins/panels/network/Panel.qml"
          onLoaded: { item.bar = strip.bar; item.opacity = 0 }
        }

        // With bar.cardsOnTap, a tap opens the card; a pull opens quick settings.
        MouseArea {
          anchors.fill: parent
          anchors.leftMargin: -Style.space(8)
          anchors.rightMargin: -Style.space(8)
          enabled: bar.cardsOnTap
          property real pressY: 0
          property bool pulled: false
          onPressed: function(mouse) { pressY = mouse.y; pulled = false }
          onPositionChanged: function(mouse) {
            if (!pulled && mouse.y - pressY > Style.space(14)) { pulled = true; bar.openQuickSettings() }
          }
          onClicked: if (!pulled && networkPanel.item) networkPanel.item.toggle()
          function triggerPress(button) { if (networkPanel.item) networkPanel.item.toggle() }
          Component.onCompleted: bar.clickTargets = bar.clickTargets.concat([this])
          Component.onDestruction: bar.clickTargets = bar.clickTargets.filter(function(t) { return t !== this }, this)
        }
      }

      Item {
        objectName: "barBattery"
        visible: bar.hasBattery
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: batteryItem.implicitWidth
        implicitHeight: strip.height

        // The charging bolt shows in every style (BatteryIndicator).
        BatteryIndicator {
          id: batteryItem
          objectName: "battery"
          anchors.verticalCenter: parent.verticalCenter
          style: bar.batteryStyle
          percent: bar.batteryPercent
          charging: bar.charging
          full: bar.batteryFull
          foreground: bar.foreground
          background: bar.background
          urgent: bar.urgent
          fontFamily: bar.fontFamily
          iconPx: Style.font.iconLarge
          textPx: Style.font.body
          barSize: bar.barSize
          // The number goes before any glyph where the row has no room.
          showText: strip.fit.show.batteryText === true
        }

        // Omarchy's power panel, unseen but for its popup.
        Loader {
          id: powerPanel
          anchors.fill: parent
          active: bar.cardsOnTap
          source: "file://" + bar.omarchyPath + "/shell/plugins/panels/power/Panel.qml"
          onLoaded: { item.bar = strip.bar; item.opacity = 0 }
        }

        // With bar.cardsOnTap, a tap opens the card; a pull opens quick settings.
        MouseArea {
          anchors.fill: parent
          anchors.leftMargin: -Style.space(8)
          anchors.rightMargin: -Style.space(8)
          enabled: bar.cardsOnTap
          property real pressY: 0
          property bool pulled: false
          onPressed: function(mouse) { pressY = mouse.y; pulled = false }
          onPositionChanged: function(mouse) {
            if (!pulled && mouse.y - pressY > Style.space(14)) { pulled = true; bar.openQuickSettings() }
          }
          onClicked: if (!pulled && powerPanel.item) powerPanel.item.toggle()
          function triggerPress(button) { if (powerPanel.item) powerPanel.item.toggle() }
          Component.onCompleted: bar.clickTargets = bar.clickTargets.concat([this])
          Component.onDestruction: bar.clickTargets = bar.clickTargets.filter(function(t) { return t !== this }, this)
        }
      }
    }
  }

  component StatusGlyph: Text {
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    textFormat: Text.PlainText
    color: strip.bar ? strip.bar.foreground : "white"
    font.family: strip.bar ? strip.bar.fontFamily : ""
    font.pixelSize: Style.font.iconLarge
  }
}
