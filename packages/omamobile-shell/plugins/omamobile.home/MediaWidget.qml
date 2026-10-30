// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.Commons
import qs.Commons as Commons

// Now playing, from MPRIS: cover, title and artist, previous / play-pause /
// next. Follows the player that is playing, else the last one that was.
Item {
  id: widget

  property var home: null
  property var entry: null
  property bool editing: false

  readonly property var players: Mpris.players ? Mpris.players.values : []
  property var lastPlayer: null
  readonly property var player: {
    for (var i = 0; i < players.length; i++)
      if (players[i] && players[i].isPlaying) return players[i]
    if (lastPlayer && players.indexOf(lastPlayer) >= 0) return lastPlayer
    return players.length > 0 ? players[0] : null
  }
  onPlayerChanged: if (player) lastPlayer = player

  readonly property color fg: home ? home.foreground : "white"
  readonly property color dim: home ? home.dimForeground : "white"
  readonly property int touch: Math.max(44, Style.space(44))

  Text {
    anchors.centerIn: parent
    visible: !widget.player
    textFormat: Text.PlainText
    text: "󰝛  Nothing playing"
    color: widget.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.title
  }

  Item {
    anchors.fill: parent
    anchors.margins: Style.spacing.xl
    visible: !!widget.player

    Rectangle {
      id: cover
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(parent.height, Style.space(96))
      height: width
      radius: Style.cornerRadius
      color: Qt.rgba(1, 1, 1, 0.08)
      clip: true

      Text {
        anchors.centerIn: parent
        visible: art.status !== Image.Ready
        textFormat: Text.PlainText
        text: "󰝚"
        color: widget.dim
        font.family: Style.font.family
        font.pixelSize: parent.width * 0.45
      }
      Image {
        id: art
        anchors.fill: parent
        source: widget.player && widget.player.trackArtUrl ? widget.player.trackArtUrl : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
      }
    }

    Column {
      anchors.left: cover.right
      anchors.leftMargin: Style.spacing.xl
      anchors.right: controls.left
      anchors.rightMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xxs

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: widget.player ? (widget.player.trackTitle || widget.player.identity || "") : ""
        color: widget.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: widget.player ? (widget.player.trackArtist || widget.player.identity || "") : ""
        color: widget.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }

    Row {
      id: controls
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter

      Repeater {
        model: [
          { glyph: "󰒮", act: "previous" },
          { glyph: widget.player && widget.player.isPlaying ? "󰏤" : "󰐊", act: "toggle" },
          { glyph: "󰒭", act: "next" }
        ]
        delegate: Item {
          required property var modelData
          width: widget.touch
          height: widget.touch
          readonly property bool usable: !!widget.player && (modelData.act === "toggle" ? widget.player.canTogglePlaying
            : modelData.act === "next" ? widget.player.canGoNext : widget.player.canGoPrevious)
          opacity: usable ? 1 : 0.35

          Rectangle {
            anchors.centerIn: parent
            width: parent.width - 4; height: width; radius: Math.min(Style.cornerRadius, width / 2)
            color: tap.pressed ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
          }
          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: modelData.glyph
            color: widget.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.iconLarge + 4
          }
          MouseArea {
            id: tap
            anchors.fill: parent
            enabled: parent.usable && !widget.editing
            onClicked: {
              var p = widget.player
              if (modelData.act === "toggle") p.togglePlaying()
              else if (modelData.act === "next") p.next()
              else p.previous()
            }
          }
        }
      }
    }
  }
}
