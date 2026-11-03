// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell.Services.Mpris
import "MediaModel.js" as MediaModel

// The MPRIS player the shade's media card shows (MediaModel.pick): playing
// before paused, and among those the one that started playing or changed
// track last. Quickshell reports a player's position only when asked, so
// while one plays and the card is on screen (`ticking`) it asks once a
// second, as Quickshell's documentation says to.
Item {
  id: source

  // Every player on the session bus; a test or a harness may hand its own.
  property var players: Mpris.players ? Mpris.players.values : []
  // Whether to keep the position fresh (the card is on screen).
  property bool ticking: false

  // key -> when it last started playing or changed track (a growing serial)
  property var order: ({})
  property int serial: 0
  readonly property var player: MediaModel.pick(players, order)

  function touch(p) {
    var k = MediaModel.key(p)
    if (!k) return
    var next = {}
    for (var name in order) next[name] = order[name]
    serial += 1
    next[k] = serial
    order = next
  }

  // Players that are already playing when the shell starts count from then,
  // in the bus's order.
  Component.onCompleted: {
    for (var i = 0; i < players.length; i++) if (MediaModel.playing(players[i])) touch(players[i])
  }

  Instantiator {
    model: source.players
    delegate: Connections {
      required property var modelData
      target: modelData
      function onIsPlayingChanged() { if (MediaModel.playing(modelData)) source.touch(modelData) }
      function onTrackChanged() { source.touch(modelData) }
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: source.ticking && !!source.player && MediaModel.playing(source.player) && !!source.player.positionSupported
    onTriggered: if (source.player) source.player.positionChanged()
  }
}
