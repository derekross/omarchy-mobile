// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "CallModel.js" as CallModel

// The full-screen call card: a ringing call on a locked phone ("incoming"),
// and a call in progress over the lock ("in-call"). Call.qml puts it in its
// layer-shell window above the lock; test/call-render.qml draws it
// offscreen. It offers call actions only: nothing here opens an app or
// reaches past the lock.
//
// Ringing: the caller's initials pulse in a ring, the name is large, and a
// handle at the bottom answers when swiped up and declines when swiped
// down (a swipe, not a tap, so a pocket can't answer). "Reply" declines
// with one of omatel's canned messages.
//
// In a call: the elapsed time, mute and speaker toggles, and a wide red
// end button; the chevron folds the card to a strip at the top so the
// lock's own PIN pad is reachable.
//
// On its side (TOUCH-PLAN 2.4: 1040x480, where the 420 px column of ring
// controls doesn't fit under the caller) the caller takes the left half
// and the controls the right, each centred in the height; the swipe
// threshold, the targets and the reply sheet are the same.
Item {
  id: card

  // A call as CallModel.parseLine gives it, and what to show for it.
  property var call: null
  property string mode: "incoming"
  property double nowMs: Date.now()
  property bool muted: false
  property string route: "earpiece"
  property var replies: []

  signal answer()
  signal decline()
  signal hangup()
  signal toggleMute()
  signal toggleSpeaker()
  signal reply(string text)
  signal fold()

  readonly property bool ringing: mode === "incoming"
  readonly property color foreground: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  // Answer and end are the colours every phone uses for them; the rest
  // comes from the Omarchy theme.
  readonly property color answerColor: "#1e9e53"
  readonly property color endColor: "#d9362b"
  property bool showReplies: false
  readonly property bool wide: width > height

  // ---------------------------------------------------------------- backdrop

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.background
  }

  // A soft wash of the theme's accent from the top, the expressive part.
  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.32) }
      GradientStop { position: 0.55; color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.06) }
      GradientStop { position: 1.0; color: "transparent" }
    }
  }

  // The card takes every touch: nothing reaches the lock beneath it.
  MouseArea { anchors.fill: parent }

  // ---------------------------------------------------------------- caller

  Column {
    id: caller
    objectName: "caller"
    readonly property real column: card.wide ? card.width / 2 : card.width
    x: Math.round((column - width) / 2)
    y: card.wide ? Math.round((card.height - height) / 2) : Math.round(card.height * 0.13)
    width: column - 48
    spacing: 14

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: CallModel.stateLabel(card.call, card.nowMs)
      color: card.foreground
      opacity: 0.8
      font.family: Style.font.family
      font.pixelSize: 17
      font.letterSpacing: 0.4
    }

    Item { width: 1; height: 10 }

    // The avatar, with rings that breathe while it rings.
    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 196
      height: 196

      Repeater {
        model: card.ringing ? 2 : 0
        Rectangle {
          id: ring
          required property int index
          anchors.centerIn: parent
          width: 136
          height: 136
          radius: width / 2
          color: "transparent"
          border.width: 2
          border.color: card.accent
          opacity: 0
          SequentialAnimation on scale {
            running: card.ringing
            loops: Animation.Infinite
            PauseAnimation { duration: ring.index * 900 }
            NumberAnimation { from: 1.0; to: 1.42; duration: 1800; easing.type: Easing.OutCubic }
          }
          SequentialAnimation on opacity {
            running: card.ringing
            loops: Animation.Infinite
            PauseAnimation { duration: ring.index * 900 }
            NumberAnimation { from: 0.55; to: 0; duration: 1800; easing.type: Easing.OutCubic }
          }
        }
      }

      Rectangle {
        anchors.centerIn: parent
        width: 136
        height: 136
        radius: width / 2
        color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.22)
        border.width: 1
        border.color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.45)

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: CallModel.initials(card.call)
          color: card.foreground
          font.family: Style.font.family
          font.pixelSize: 54
          font.bold: true
        }
      }
    }

    Item { width: 1; height: 6 }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: CallModel.title(card.call)
      color: card.foreground
      font.family: Style.font.family
      font.pixelSize: 38
      font.bold: true
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: text !== ""
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: CallModel.subtitle(card.call)
      color: card.foreground
      opacity: 0.72
      font.family: Style.font.family
      font.pixelSize: 19
    }
  }

  // ---------------------------------------------------------------- ringing

  Item {
    id: ringControls
    visible: card.ringing
    x: card.wide ? Math.round(card.width / 2) : 0
    y: card.height - height
    width: card.width - x
    height: card.wide ? card.height : 420

    // "Reply": decline with a canned message.
    Pill {
      id: replyButton
      anchors.horizontalCenter: parent.horizontalCenter
      y: card.wide ? track.y - height - 16 : 0
      visible: card.replies.length > 0 && !!card.call && card.call.number !== ""
      glyph: String.fromCodePoint(0xF0368)
      label: "Reply"
      fill: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.10)
      ink: card.foreground
      onTapped: card.showReplies = true
    }

    // The swipe track: answer at the top, decline at the bottom.
    Rectangle {
      id: track
      objectName: "ringTrack"
      anchors.horizontalCenter: parent.horizontalCenter
      y: card.wide ? Math.round((ringControls.height - height) / 2) : 84
      width: 104
      height: 288
      radius: width / 2
      color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.07)
      border.width: 1
      border.color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.12)

      readonly property real travel: (height - handle.height) / 2 - 8
      readonly property real fraction: -(handle.y - restY) / travel
      readonly property real restY: (height - handle.height) / 2

      Glyph { anchors.horizontalCenter: parent.horizontalCenter; y: 14; code: 0xF0143; size: 26; ink: card.answerColor; opacity: 0.4 + Math.max(0, track.fraction) * 0.6 }
      Glyph { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 14; code: 0xF0140; size: 26; ink: card.endColor; opacity: 0.4 + Math.max(0, -track.fraction) * 0.6 }

      Rectangle {
        id: handle
        objectName: "answerHandle"
        anchors.horizontalCenter: parent.horizontalCenter
        y: track.restY
        width: 88
        height: 88
        radius: width / 2
        color: track.fraction < -0.15 ? card.endColor : card.answerColor
        Behavior on color { ColorAnimation { duration: 120 } }

        Glyph {
          anchors.centerIn: parent
          code: track.fraction < -0.15 ? 0xF03F5 : 0xF03F2
          size: 40
          ink: "white"
          rotation: track.fraction < -0.15 ? 0 : -14 * Math.sin(wiggle.phase)
        }

        // A small wiggle while ringing, to say "move me".
        QtObject { id: wiggle; property real phase: 0 }
        NumberAnimation on y {
          id: springBack
          running: false
          to: track.restY
          duration: 220
          easing.type: Easing.OutBack
        }
        SequentialAnimation {
          running: card.ringing && !drag.active
          loops: Animation.Infinite
          NumberAnimation { target: wiggle; property: "phase"; from: 0; to: Math.PI * 4; duration: 900 }
          PauseAnimation { duration: 1400 }
        }

        DragHandler {
          id: drag
          xAxis.enabled: false
          yAxis.minimum: track.restY - track.travel
          yAxis.maximum: track.restY + track.travel
          onActiveChanged: {
            if (active) return
            var result = CallModel.swipeResult(track.fraction, 0.62)
            if (result === "answer") card.answer()
            else if (result === "decline") card.decline()
            springBack.start()
          }
        }
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: track.bottom
      anchors.topMargin: 16
      textFormat: Text.PlainText
      text: "Swipe up to answer · down to decline"
      color: card.foreground
      opacity: 0.6
      font.family: Style.font.family
      font.pixelSize: 15
    }
  }

  // ---------------------------------------------------------------- in a call

  Item {
    id: inCall
    visible: card.mode === "in-call"
    x: card.wide ? Math.round(card.width / 2) : 0
    y: card.height - height
    width: card.width - x
    height: card.wide ? card.height : 360
    readonly property real stack: toggles.height + 44 + endButton.height + 22 + unlockHint.height

    Row {
      id: toggles
      objectName: "callToggles"
      anchors.horizontalCenter: parent.horizontalCenter
      y: card.wide ? Math.round((inCall.height - inCall.stack) / 2) : 0
      spacing: 28

      Toggle {
        objectName: "muteToggle"
        glyph: 0xF036D
        label: card.muted ? "Muted" : "Mute"
        on: card.muted
        onTapped: card.toggleMute()
      }
      Toggle {
        objectName: "speakerToggle"
        glyph: 0xF057E
        label: "Speaker"
        on: card.route === "speaker"
        onTapped: card.toggleSpeaker()
      }
    }

    Rectangle {
      id: endButton
      objectName: "endButton"
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: toggles.bottom
      anchors.topMargin: 44
      width: 236
      height: 72
      radius: height / 2
      color: endTap.pressed ? Qt.darker(card.endColor, 1.2) : card.endColor
      Glyph { anchors.centerIn: parent; code: 0xF03F5; size: 36; ink: "white" }
      MouseArea { id: endTap; anchors.fill: parent; onClicked: card.hangup() }
    }

    Text {
      id: unlockHint
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: endButton.bottom
      anchors.topMargin: 22
      textFormat: Text.PlainText
      text: "Unlock to open Phone"
      color: card.foreground
      opacity: 0.55
      font.family: Style.font.family
      font.pixelSize: 15
    }
  }

  // Fold the in-call card away, so the lock's PIN pad can be used.
  Rectangle {
    visible: card.mode === "in-call"
    objectName: "foldButton"
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 18
    width: 52
    height: 52
    radius: 26
    color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, foldTap.pressed ? 0.18 : 0.08)
    Glyph { anchors.centerIn: parent; code: 0xF0140; size: 28; ink: card.foreground }
    MouseArea { id: foldTap; anchors.fill: parent; onClicked: card.fold() }
  }

  // ---------------------------------------------------------------- replies

  Rectangle {
    anchors.fill: parent
    visible: card.showReplies
    color: Commons.Color.menu.scrim
    MouseArea { anchors.fill: parent; onClicked: card.showReplies = false }
  }

  Rectangle {
    objectName: "replySheet"
    visible: card.showReplies
    x: (card.wide ? Math.round(card.width / 2) : 0) + 12
    width: card.width - x - 12
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 12
    height: replyColumn.implicitHeight + 32
    radius: 28
    color: Commons.Color.popups.background
    border.width: 1
    border.color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.12)
    MouseArea { anchors.fill: parent }

    Column {
      id: replyColumn
      x: 16
      y: 16
      width: parent.width - 32
      spacing: 10

      Text {
        textFormat: Text.PlainText
        text: "Decline and send"
        color: card.foreground
        opacity: 0.7
        font.family: Style.font.family
        font.pixelSize: 15
        leftPadding: 8
      }

      Repeater {
        model: card.replies
        Rectangle {
          required property string modelData
          width: replyColumn.width
          height: 56
          radius: 18
          color: replyTap.pressed ? Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.14)
                                  : Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.06)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            x: 18
            width: parent.width - 36
            textFormat: Text.PlainText
            text: parent.modelData
            color: card.foreground
            font.family: Style.font.family
            font.pixelSize: 17
            elide: Text.ElideRight
          }
          MouseArea {
            id: replyTap
            anchors.fill: parent
            onClicked: { card.showReplies = false; card.reply(parent.modelData) }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- pieces

  component Glyph: Text {
    property int code: 0
    property int size: 24
    property color ink: "white"
    textFormat: Text.PlainText
    text: String.fromCodePoint(code)
    color: ink
    font.family: Style.font.family
    font.pixelSize: size
  }

  component Pill: Rectangle {
    id: pill
    property string glyph: ""
    property string label: ""
    property color fill: "transparent"
    property color ink: "white"
    signal tapped()
    width: pillRow.implicitWidth + 44
    height: 52
    radius: height / 2
    color: pillTap.pressed ? Qt.darker(pill.fill, 1.4) : pill.fill
    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: 10
      Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: pill.glyph; color: pill.ink; font.family: Style.font.family; font.pixelSize: 22 }
      Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: pill.label; color: pill.ink; font.family: Style.font.family; font.pixelSize: 18; font.bold: true }
    }
    MouseArea { id: pillTap; anchors.fill: parent; onClicked: pill.tapped() }
  }

  component Toggle: Column {
    id: toggle
    property int glyph: 0
    property string label: ""
    property bool on: false
    signal tapped()
    spacing: 10
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 84
      height: 84
      // Expressive: a circle that becomes a rounded square when on.
      radius: toggle.on ? 26 : 42
      Behavior on radius { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      color: toggle.on ? card.accent : Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, toggleTap.pressed ? 0.18 : 0.10)
      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: String.fromCodePoint(toggle.glyph)
        color: toggle.on ? Commons.Color.background : card.foreground
        font.family: Style.font.family
        font.pixelSize: 34
      }
      MouseArea { id: toggleTap; anchors.fill: parent; onClicked: toggle.tapped() }
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: toggle.label
      color: card.foreground
      font.family: Style.font.family
      font.pixelSize: 15
    }
  }
}
