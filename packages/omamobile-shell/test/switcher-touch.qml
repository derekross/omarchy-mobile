// SPDX-License-Identifier: MIT
// Touch taps on recent apps (test/switcher-touch runs this). A finger, not
// a mouse: with a mouse, the bug these pin never showed.
import QtQuick
import QtTest
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "switcher"

Item {
  id: top
  width: 10
  height: 10
  // Where test/switcher-touch saves a picture of the landscape case, if asked.
  property string shotDir: ""

  // A foreign-toplevel: close() takes it off the list, unless the app
  // ignores the request.
  Component {
    id: fakeWindow
    QtObject {
      id: fake
      property string appId: "foot"
      property string title: "~"
      property bool honoursClose: true
      property int closes: 0
      property int activations: 0
      function activate() { activations++ }
      function close() {
        closes++
        if (honoursClose) top.drop(fake)
      }
    }
  }

  function drop(w) {
    ToplevelManager.toplevels.values = ToplevelManager.toplevels.values.filter(function(x) { return x !== w })
  }

  Switcher { id: sw }

  TestCase {
    id: test
    name: "SwitcherTouch"
    when: windowShown

    property var overlay: null

    function initTestCase() {
      for (var i = 0; i < sw.data.length; i++)
        if (sw.data[i] && sw.data[i].contentItem !== undefined) overlay = sw.data[i]
      verify(overlay, "the switcher's window")
    }

    function init() {
      sw.close()
      ToplevelManager.toplevels.values = []
      Hyprland.toplevels.values = []
      Quickshell.executed = []
    }

    function openWith(windows) {
      ToplevelManager.toplevels.values = windows
      sw.open("")
      tryVerify(function() { return overlay.visible })
      waitForRendering(overlay.contentItem)
    }

    function findText(item, text) {
      if (item.text === text && item.visible) return item
      for (var i = 0; i < item.children.length; i++) {
        var hit = findText(item.children[i], text)
        if (hit) return hit
      }
      return null
    }

    // The centre of the button whose label reads text, in window coordinates.
    function buttonAt(text) {
      var label = findText(overlay.contentItem, text)
      verify(label, "a button reading " + text)
      var button = label.parent
      return button.mapToItem(overlay.contentItem, button.width / 2, button.height / 2)
    }

    function tap(x, y) {
      var t = touchEvent(overlay.contentItem)
      t.press(0, overlay.contentItem, x, y).commit()
      t.release(0, overlay.contentItem, x, y).commit()
      wait(20)
    }

    function dispatched(fragment) {
      return Quickshell.executed.some(function(argv) { return argv.join(" ").indexOf(fragment) >= 0 })
    }

    function test_clear_all_takes_two_taps_and_closes() {
      var foot = fakeWindow.createObject(top)
      openWith([foot])
      var p = buttonAt("Clear all")
      tap(p.x, p.y)
      verify(sw.opened, "the first tap leaves recent apps open")
      verify(sw.confirmClear, "the first tap arms Clear all")
      compare(foot.closes, 0)
      p = buttonAt("Close 1 app?")
      tap(p.x, p.y)
      compare(foot.closes, 1, "the second tap closes the window")
      compare(foot.activations, 0, "and doesn't switch to it")
      verify(!sw.opened, "then recent apps close")
    }

    function test_clear_all_closes_every_window() {
      var a = fakeWindow.createObject(top), b = fakeWindow.createObject(top, { appId: "chromium" })
      openWith([a, b])
      var p = buttonAt("Clear all")
      tap(p.x, p.y)
      p = buttonAt("Close 2 apps?")
      tap(p.x, p.y)
      compare(a.closes + b.closes, 2)
      compare(ToplevelManager.toplevels.values.length, 0)
    }

    function test_tap_between_the_buttons_keeps_recents() {
      openWith([fakeWindow.createObject(top)])
      var label = findText(overlay.contentItem, "Clear all")
      var button = label.parent
      var gap = button.mapToItem(overlay.contentItem, button.width + 12, button.height / 2)
      tap(gap.x, gap.y)
      verify(sw.opened, "a near miss on the bottom actions doesn't dismiss")
    }

    function test_tap_on_empty_space_still_dismisses() {
      var foot = fakeWindow.createObject(top)
      openWith([foot])
      tap(20, 40)
      verify(!sw.opened)
      compare(foot.closes, 0)
    }

    function test_home_goes_home_once() {
      var foot = fakeWindow.createObject(top)
      openWith([foot])
      var p = buttonAt("Home")
      tap(p.x, p.y)
      verify(dispatched('hl.dsp.focus({ workspace = "empty" })'), "Home focuses an empty workspace")
      verify(!sw.opened)
      compare(foot.activations, 0, "Home doesn't also switch to the app")
    }

    function test_a_window_that_stays_is_closed_through_hyprland() {
      var stubborn = fakeWindow.createObject(top, { honoursClose: false })
      Hyprland.toplevels.values = [{ wayland: stubborn, address: "0xa2", title: "~", lastIpcObject: { "class": "foot" } }]
      openWith([stubborn])
      var p = buttonAt("Clear all")
      tap(p.x, p.y)
      p = buttonAt("Close 1 app?")
      tap(p.x, p.y)
      compare(stubborn.closes, 1)
      verify(!dispatched("hl.dsp.window.close"), "not straight away")
      tryVerify(function() { return test.dispatched('hl.dsp.window.close({ window = "address:0xa2" })') }, 4000,
                "Hyprland closes what is still open")
    }

    function test_a_closed_window_is_not_closed_again() {
      var foot = fakeWindow.createObject(top)
      Hyprland.toplevels.values = [{ wayland: foot, address: "0xa3", title: "~", lastIpcObject: { "class": "foot" } }]
      openWith([foot])
      var p = buttonAt("Clear all")
      tap(p.x, p.y)
      p = buttonAt("Close 1 app?")
      tap(p.x, p.y)
      wait(2500)
      verify(!dispatched("hl.dsp.window.close"))
    }

    function test_card_tap_switches() {
      var foot = fakeWindow.createObject(top)
      openWith([foot])
      tap(overlay.contentItem.width / 2, overlay.contentItem.height / 2)
      compare(foot.activations, 1)
      verify(!sw.opened)
    }

    // The window's first child with an id-like role: the cards list is the
    // ListView, the action row the Row with the two buttons.
    function findKind(item, kind) {
      if (item.toString().indexOf(kind) === 0) return item
      for (var i = 0; i < item.children.length; i++) {
        var hit = findKind(item.children[i], kind)
        if (hit) return hit
      }
      return null
    }

    function onScreen(item) {
      var p = item.mapToItem(overlay.contentItem, 0, 0)
      return p.x >= 0 && p.y >= 0 && p.x + item.width <= overlay.width + 0.5 && p.y + item.height <= overlay.height + 0.5
    }

    // On its side (TOUCH-PLAN 2.4): a card keeps the screen's shape instead
    // of 72% of the width, so it fits above the bottom actions.
    function test_cards_fit_on_their_side() {
      overlay.width = 1040
      overlay.height = 480
      var a = fakeWindow.createObject(top), b = fakeWindow.createObject(top, { appId: "chromium" })
      openWith([a, b])
      var cards = findKind(overlay.contentItem, "QQuickListView")
      verify(cards, "the cards list")
      tryVerify(function() { return cards.count === 2 && cards.currentItem !== null })
      var card = cards.currentItem
      verify(card.width <= 1040 * 0.72 - 1, "narrower than 72% of the width: " + card.width)
      verify(Math.abs(card.width / (card.height - 28) - 1040 / 480) < 0.15, "the screen's shape: " + card.width + "x" + card.height)
      verify(onScreen(card), "the card is on screen")
      var clear = findText(overlay.contentItem, "Clear all"), home = findText(overlay.contentItem, "Home")
      verify(onScreen(clear.parent) && onScreen(home.parent), "the bottom actions are on screen")
      verify(clear.parent.mapToItem(overlay.contentItem, 0, 0).y >= card.mapToItem(overlay.contentItem, 0, card.height).y, "under the card")
      var dir = String(top.shotDir)
      if (dir) {
        waitForRendering(overlay.contentItem)
        var image = grabImage(overlay.contentItem)
        image.save(dir + "/switcher-landscape.png")
      }
      overlay.width = 412
      overlay.height = 892
    }
  }
}
