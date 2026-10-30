// SPDX-License-Identifier: MIT
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "NotificationsModel.js" as NotificationsModel
import "Readable.js" as Readable

// A row of the notification shade (QuickSettings.qml): the sender's glyph,
// app and age, summary, and two lines of the body. A tap runs what a tap on
// the toast would have. A sideways swipe moves the row with the finger and
// fades it; let go past 35% of the width, or flick it, and it flies off that
// side, the gap closes, and the host forgets that one notification (a toast
// still on screen goes with it). Short of that it springs back. Both
// gestures start only past a drag threshold, so a tap still taps, and the
// swipe takes sideways movement only, so the list still scrolls.
Item {
  id: row

  // The quick-settings sheet: foreground, nowMs, openNotification(entry)
  // and forgetNotification(entry).
  property var host: null
  property var entry: ({})
  // Off while the list is scrolling.
  property bool swipeEnabled: true
  readonly property bool actionable: !!NotificationsModel.tapArgv(entry)
  readonly property color foreground: host ? host.foreground : Commons.Color.popups.text

  // How far the row has been swiped sideways (px), and the finger's speed
  // when it was let go (px/s).
  property real swipeOffset: 0
  property real swipeVelocity: 0
  property bool dismissing: false
  // 1 in the list; down to 0 as the gap closes after a swipe away.
  property real fold: 1
  readonly property bool swiping: swipeHandler.active || swipeAnimation.running || dismissing

  readonly property real naturalHeight: Math.max(44, rowText.implicitHeight + Style.spacing.md * 2)
  height: naturalHeight * fold
  visible: fold > 0
  clip: fold < 1

  function finishSwipe() {
    var way = NotificationsModel.swipeOutcome(swipeOffset, swipeVelocity, width, Style.space(900))
    swipeAnimation.dismiss = way !== 0
    swipeAnimation.to = way * (width + Style.space(24))
    if (way !== 0) dismissing = true
    swipeAnimation.restart()
  }

  Item {
    id: card
    width: row.width
    height: row.naturalHeight
    transform: Translate { x: row.swipeOffset }
    opacity: 1 - 0.6 * Math.min(1, Math.abs(row.swipeOffset) / Math.max(1, row.width))

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: rowTap.pressed ? Style.pressedFillFor(row.foreground, Commons.Color.accent) : "transparent"
    }

    Text {
      id: rowGlyph
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.md
      anchors.top: parent.top
      anchors.topMargin: Style.spacing.md
      width: Style.font.iconLarge
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: row.entry.glyph || "󰂚"
      color: row.entry.urgency === 2 ? Commons.Color.urgent : row.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.iconLarge
    }

    Column {
      id: rowText
      anchors.left: rowGlyph.right
      anchors.leftMargin: Style.spacing.lg
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.md
      anchors.top: parent.top
      anchors.topMargin: Style.spacing.md
      spacing: Style.spacing.xxs

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: [row.entry.app, NotificationsModel.ago(row.entry.timestamp, row.host ? row.host.nowMs : Date.now())]
          .filter(function(part) { return !!part }).join(" · ")
        color: Readable.secondary(row.foreground, Commons.Color.popups.background)
        font.family: Style.font.family
        font.pixelSize: Readable.px(Style.font.caption)
        elide: Text.ElideRight
      }

      Text {
        visible: text !== ""
        width: parent.width
        textFormat: Text.PlainText
        text: row.entry.summary || ""
        color: row.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        visible: text !== ""
        width: parent.width
        textFormat: Text.PlainText
        text: row.entry.body || ""
        color: row.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }
    }
  }

  // A tap, not a drag: the tap is cancelled once the finger moves past the
  // threshold, and the swipe or the list's scroll takes over.
  TapHandler {
    id: rowTap
    enabled: row.actionable && !row.dismissing
    gesturePolicy: TapHandler.DragThreshold
    onTapped: if (row.host) row.host.openNotification(row.entry)
  }

  HoverHandler {
    enabled: row.actionable
    cursorShape: Qt.PointingHandCursor
  }

  // Sideways only: a vertical drag is left to the list, which scrolls.
  DragHandler {
    id: swipeHandler
    target: null
    yAxis.enabled: false
    dragThreshold: Style.space(12)
    enabled: row.swipeEnabled && !row.dismissing
    onActiveChanged: {
      if (active) {
        swipeAnimation.stop()
        row.swipeVelocity = 0
      } else {
        row.finishSwipe()
      }
    }
    onActiveTranslationChanged: {
      if (!active) return
      row.swipeOffset = activeTranslation.x
      row.swipeVelocity = centroid.velocity.x
    }
  }

  SequentialAnimation {
    id: swipeAnimation
    property real to: 0
    property bool dismiss: false
    NumberAnimation {
      target: row
      property: "swipeOffset"
      to: swipeAnimation.to
      duration: swipeAnimation.dismiss ? 140 : 200
      easing.type: swipeAnimation.dismiss ? Easing.InQuad : Easing.OutBack
    }
    ScriptAction {
      script: if (swipeAnimation.dismiss) foldAnimation.start()
    }
  }

  // The gap closes, then the host takes the entry out of the list (which
  // replaces this row) and forgets the notification.
  SequentialAnimation {
    id: foldAnimation
    NumberAnimation {
      target: row
      property: "fold"
      to: 0
      duration: 160
      easing.type: Easing.OutCubic
    }
    ScriptAction {
      script: if (row.host) row.host.forgetNotification(row.entry)
    }
  }
}
