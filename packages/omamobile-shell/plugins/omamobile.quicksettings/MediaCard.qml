// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "MediaModel.js" as MediaModel
import "Readable.js" as Readable

// The media card at the top of the notification shade, as a phone has it:
// the album art (or the app's icon when the player has none), the title,
// the artist and the app's name; a seek bar with the elapsed time and the
// length when the player reports its position; previous, play/pause and
// next. A tap on the card (not on a control) asks the host to bring the
// player's app up (`opened`). Drawn as Omarchy's media popup draws its art
// and controls (shell/plugins/services/media/BarWidget.qml), in the popup
// palette of the applied theme.
BorderSurface {
  id: card

  // An MprisPlayer, or null (the card then hides).
  property var player: null
  property color foreground: Commons.Color.popups.text
  // Art from the network (an https:// URL the player gives); local art
  // always loads. The shade allows it (MediaModel.artSource).
  property bool allowRemoteArt: true

  signal opened()

  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int artSize: Math.max(64, Style.space(72))
  readonly property int inner: Style.spacing.lg
  readonly property bool timeline: MediaModel.hasTimeline(player)
  readonly property string artUrl: player ? MediaModel.artSource(player.trackArtUrl, allowRemoteArt) : ""
  readonly property string appName: MediaModel.appName(player)
  readonly property bool isPlaying: MediaModel.playing(player)
  readonly property var desktopEntry: {
    if (!player) return null
    var names = [player.desktopEntry, player.identity]
    for (var i = 0; i < names.length; i++) {
      var n = String(names[i] || "")
      if (!n) continue
      var e = typeof DesktopEntries.heuristicLookup === "function" ? DesktopEntries.heuristicLookup(n) : DesktopEntries.byId(n)
      if (e) return e
    }
    return null
  }
  readonly property string iconSource: {
    var icon = desktopEntry && desktopEntry.icon ? String(desktopEntry.icon) : ""
    if (!icon) return ""
    if (icon.charAt(0) === "/") return "file://" + icon
    return typeof Quickshell.iconPath === "function" ? Quickshell.iconPath(icon, true) : ""
  }

  visible: !!player
  implicitHeight: visible ? column.implicitHeight + inner * 2 : 0
  radius: Style.cornerRadius
  color: openTap.pressed ? Style.pressedFillFor(card.foreground, Commons.Color.accent)
    : Style.normalFillFor(card.foreground, Commons.Color.accent)
  borderSpec: Border.controlSpec("normal", card.foreground, Commons.Color.accent)

  Accessible.role: Accessible.Grouping
  Accessible.name: MediaModel.accessibleName(player)

  // A tap that is not a drag (the shade's list scrolls under it) on the card
  // outside its controls: those take their own taps first.
  TapHandler {
    id: openTap
    gesturePolicy: TapHandler.DragThreshold
    onTapped: card.opened()
  }

  Column {
    id: column
    x: card.inner
    y: card.inner
    width: card.width - card.inner * 2
    spacing: Style.spacing.md

    Item {
      width: parent.width
      height: Math.max(card.artSize, info.implicitHeight)

      BorderSurface {
        id: artFrame
        objectName: "mediaArt"
        width: card.artSize
        height: card.artSize
        anchors.verticalCenter: parent.verticalCenter
        radius: Style.cornerRadius
        clip: true
        color: Style.normalFillFor(card.foreground, Commons.Color.accent)
        borderSpec: Border.controlSpec("normal", card.foreground, Commons.Color.accent)

        Image {
          id: art
          anchors.fill: parent
          anchors.margins: artFrame.borderLeft
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize.width: card.artSize * 2
          sourceSize.height: card.artSize * 2
          source: card.artUrl
          visible: status === Image.Ready
        }

        Image {
          id: appIcon
          anchors.centerIn: parent
          width: Math.round(card.artSize * 0.6)
          height: width
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          source: art.visible ? "" : card.iconSource
          visible: !art.visible && status === Image.Ready
        }

        Text {
          anchors.centerIn: parent
          visible: !art.visible && !appIcon.visible
          textFormat: Text.PlainText
          text: "󰝚"
          color: card.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.display
        }
      }

      Column {
        id: info
        anchors.left: artFrame.right
        anchors.leftMargin: card.inner
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        Text {
          objectName: "mediaApp"
          width: parent.width
          textFormat: Text.PlainText
          text: card.appName
          visible: text !== ""
          color: Qt.darker(card.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Readable.px(Style.font.caption)
          elide: Text.ElideRight
        }

        Text {
          objectName: "mediaTitle"
          width: parent.width
          textFormat: Text.PlainText
          text: card.player ? String(card.player.trackTitle || "") : ""
          color: card.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          objectName: "mediaArtist"
          width: parent.width
          textFormat: Text.PlainText
          text: MediaModel.artist(card.player)
          visible: text !== ""
          color: card.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }
    }

    // The seek bar: elapsed, the track, the length. A drag or a tap seeks
    // when the player can; otherwise it only shows where the track is.
    Item {
      id: timelineRow
      objectName: "mediaTimeline"
      visible: card.timeline
      width: parent.width
      height: visible ? Math.max(32, Style.space(36)) : 0

      Text {
        id: elapsed
        objectName: "mediaElapsed"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: MediaModel.timeText(seek.dragging ? seek.liveValue * (card.player ? card.player.length : 0)
                                                : (card.player ? card.player.position : 0))
        color: card.foreground
        font.family: Style.font.family
        font.pixelSize: Readable.px(Style.font.caption)
      }

      PanelSlider {
        id: seek
        objectName: "mediaSeek"
        anchors.left: elapsed.right
        anchors.leftMargin: Style.spacing.lg
        anchors.right: total.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        height: card.touchSize
        enabled: !!card.player && !!card.player.canSeek
        value: card.player ? MediaModel.fraction(card.player.position, card.player.length) : 0
        minimum: 0
        maximum: 1
        step: 0.02
        trackHeight: Math.max(4, Style.space(4))
        knobSize: enabled ? Math.max(18, Style.space(18)) : 0
        trackColor: Style.selectedFillFor(card.foreground, Commons.Color.accent)
        fillColor: Commons.Color.accent
        knobColor: card.foreground
        Accessible.role: Accessible.Slider
        Accessible.name: "Seek"
        onReleased: function(value) {
          if (card.player && card.player.canSeek) card.player.position = value * card.player.length
        }
      }

      Text {
        id: total
        objectName: "mediaLength"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: MediaModel.timeText(card.player ? card.player.length : 0)
        color: Qt.darker(card.foreground, 1.4)
        font.family: Style.font.family
        font.pixelSize: Readable.px(Style.font.caption)
      }
    }

    Row {
      id: controls
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.spacing.xxl

      MediaButton {
        objectName: "mediaPrevious"
        glyph: "󰒮"
        name: "Previous track"
        enabled: !!card.player && !!card.player.canGoPrevious
        onTapped: card.player.previous()
      }

      MediaButton {
        objectName: "mediaPlayPause"
        glyph: card.isPlaying ? "󰏤" : "󰐊"
        name: MediaModel.playPauseName(card.player)
        primary: true
        enabled: MediaModel.canPlayPause(card.player)
        onTapped: {
          var p = card.player
          if (p.isPlaying && p.canPause) p.pause()
          else if (!p.isPlaying && p.canPlay) p.play()
          else p.togglePlaying()
        }
      }

      MediaButton {
        objectName: "mediaNext"
        glyph: "󰒭"
        name: "Next track"
        enabled: !!card.player && !!card.player.canGoNext
        onTapped: card.player.next()
      }
    }
  }

  // A thumb-sized transport button: Omarchy's control fill and border, the
  // accent's selected fill for play/pause.
  component MediaButton: BorderSurface {
    id: button
    property string glyph: ""
    property string name: ""
    property bool primary: false
    signal tapped()

    width: primary ? Math.round(card.touchSize * 1.4) : card.touchSize
    height: card.touchSize
    radius: Style.cornerRadius
    opacity: enabled ? 1 : 0.4
    color: buttonTouch.pressed ? Style.pressedFillFor(card.foreground, Commons.Color.accent)
      : primary ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha) : "transparent"
    borderSpec: primary ? Border.controlSpec("selected", card.foreground, Commons.Color.accent) : Border.none()

    Accessible.role: Accessible.Button
    Accessible.name: button.name
    Accessible.onPressAction: if (button.enabled) button.tapped()

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: button.glyph
      color: button.primary ? Commons.Color.accent : card.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.iconLarge
    }

    MouseArea {
      id: buttonTouch
      anchors.fill: parent
      enabled: button.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: button.tapped()
    }
  }
}
