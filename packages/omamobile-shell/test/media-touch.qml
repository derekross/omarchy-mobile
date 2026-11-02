// SPDX-License-Identifier: MIT
// The shade's media card (test/media-touch): MediaSource picks the player,
// MediaCard shows it and calls it. Players are made up here, shaped as
// Quickshell's MprisPlayer, and record what they are asked.
import QtQuick
import QtTest
import Quickshell.Services.Mpris
import "quicksettings"

Item {
  id: harness
  width: 470
  height: 600

  property int opens: 0

  component FakePlayer: QtObject {
    property string identity: "Music"
    property string desktopEntry: ""
    property string dbusName: "org.mpris.MediaPlayer2.music"
    property string trackTitle: "Song"
    property string trackArtist: "Band"
    property var trackArtists: []
    property string trackArtUrl: ""
    property bool isPlaying: true
    property int playbackState: isPlaying ? 1 : 2
    property bool canPlay: true
    property bool canPause: true
    property bool canTogglePlaying: true
    property bool canGoNext: true
    property bool canGoPrevious: true
    property bool canSeek: true
    property bool canRaise: false
    property bool positionSupported: true
    property bool lengthSupported: true
    property real position: 50
    property real length: 200
    property var calls: []
    signal trackChanged()
    function note(name) { calls = calls.concat([name]) }
    function play() { note("play"); isPlaying = true }
    function pause() { note("pause"); isPlaying = false }
    function togglePlaying() { note("toggle"); isPlaying = !isPlaying }
    function next() { note("next") }
    function previous() { note("previous") }
    function raise() { note("raise") }
  }
  Component { id: playerComponent; FakePlayer {} }

  MediaSource { id: source; ticking: true }

  MediaCard {
    id: card
    width: harness.width
    height: implicitHeight
    player: source.player
    onOpened: harness.opens += 1
  }

  TestCase {
    id: test
    name: "MediaCard"
    when: windowShown

    function find(item, name) {
      if (!item) return null
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var hit = find(item.children[i], name)
        if (hit) return hit
      }
      return null
    }

    function make(props) { return playerComponent.createObject(harness, props || {}) }

    function init() {
      harness.opens = 0
      source.order = ({})
      Mpris.players.values = []
      source.players = Qt.binding(function() { return Mpris.players.values })
    }

    function test_hidden_without_a_player() {
      compare(source.player, null)
      compare(card.visible, false)
      compare(card.implicitHeight, 0)
      Mpris.players.values = [make({ isPlaying: false, playbackState: 0 })]
      compare(source.player, null, "a stopped player shows nothing")
    }

    function test_the_playing_one_then_the_most_recent() {
      var a = make({ dbusName: "a", trackTitle: "A", isPlaying: false })
      var b = make({ dbusName: "b", trackTitle: "B", isPlaying: false })
      Mpris.players.values = [a, b]
      a.trackChanged()
      b.trackChanged()
      compare(source.player, b, "the paused one that changed track last")
      a.isPlaying = true
      compare(source.player, a, "one that plays wins")
      b.isPlaying = true
      compare(source.player, b, "of two playing, the one that started last")
      b.isPlaying = false
      compare(source.player, a)
    }

    function test_controls_call_the_player() {
      var p = make({})
      Mpris.players.values = [p]
      verify(card.visible)
      compare(find(card, "mediaTitle").text, "Song")
      compare(find(card, "mediaArtist").text, "Band")
      compare(find(card, "mediaApp").text, "Music")
      var prev = find(card, "mediaPrevious"), play = find(card, "mediaPlayPause"), next = find(card, "mediaNext")
      verify(prev.height >= 44 && play.height >= 44 && next.height >= 44, "touch-sized")
      compare(play.Accessible.name, "Pause")
      mouseClick(play)
      compare(p.calls, ["pause"])
      compare(play.Accessible.name, "Play", "the name follows the state")
      compare(source.player, p, "a paused player stays on the card")
      mouseClick(play)
      mouseClick(next)
      mouseClick(prev)
      compare(p.calls, ["pause", "play", "next", "previous"])
      compare(harness.opens, 0, "a control's tap doesn't open the app")
      compare(prev.Accessible.name, "Previous track")
      compare(next.Accessible.name, "Next track")
    }

    function test_a_player_that_only_toggles() {
      var p = make({ canPlay: false, canPause: false })
      Mpris.players.values = [p]
      mouseClick(find(card, "mediaPlayPause"))
      compare(p.calls, ["toggle"])
    }

    function test_what_it_cannot_do_is_dimmed_and_does_nothing() {
      var p = make({ canGoNext: false, canGoPrevious: false })
      Mpris.players.values = [p]
      var next = find(card, "mediaNext")
      compare(next.enabled, false)
      verify(next.opacity < 1)
      mouseClick(next)
      mouseClick(find(card, "mediaPrevious"))
      compare(p.calls, [])
    }

    function test_seek_bar() {
      var p = make({ position: 50, length: 200 })
      Mpris.players.values = [p]
      compare(find(card, "mediaElapsed").text, "0:50")
      compare(find(card, "mediaLength").text, "3:20")
      var seek = find(card, "mediaSeek")
      verify(seek.visible)
      compare(seek.value, 0.25)
      mouseClick(seek, seek.width * 0.75, seek.height / 2)
      verify(Math.abs(p.position - 150) < 3, "a tap at three quarters seeks there: " + p.position)
      p.canSeek = false
      p.position = 10
      mouseClick(seek, seek.width * 0.75, seek.height / 2)
      compare(p.position, 10, "no seek on a player that can't")
      p.positionSupported = false
      compare(find(card, "mediaTimeline").visible, false, "no seek bar without a position")
    }

    function test_position_ticks_while_playing() {
      var p = make({})
      var ticks = 0
      p.positionChanged.connect(function() { ticks += 1 })
      Mpris.players.values = [p]
      wait(2300)
      verify(ticks >= 2, "asked for the position each second: " + ticks)
      p.isPlaying = false
      var before = ticks
      wait(1300)
      compare(ticks, before, "not while paused")
    }

    function test_a_tap_on_the_card_opens() {
      Mpris.players.values = [make({})]
      mouseClick(card, card.width - 20, 20)
      compare(harness.opens, 1)
    }

    function test_art_or_the_glyph() {
      var p = make({ trackArtUrl: "https://example.invalid/cover.jpg" })
      Mpris.players.values = [p]
      compare(card.artUrl, "https://example.invalid/cover.jpg", "the shade loads network art")
      card.allowRemoteArt = false
      compare(card.artUrl, "", "not where it isn't allowed")
      card.allowRemoteArt = true
      p.trackArtUrl = "file:///nonexistent/cover.png"
      compare(card.artUrl, "file:///nonexistent/cover.png")
    }

    function test_long_title_elides() {
      Mpris.players.values = [make({ trackTitle: "A very long title ".repeat(10) })]
      var t = find(card, "mediaTitle")
      compare(t.elide, Text.ElideRight)
      verify(t.width < card.width, "the title keeps to the card")
      verify(card.Accessible.name.indexOf("Playing: A very long title") === 0)
    }
  }
}
