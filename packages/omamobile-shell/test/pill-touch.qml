// SPDX-License-Identifier: MIT
// Touches on the home pill and its keyboard strip (test/pill-touch runs
// this). A finger, not a mouse: TapHandler and DragHandler share a touch
// differently from a mouse press.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "launcher"

Item {
  id: top
  width: 412
  height: 300

  PillHarness { id: harness }

  TestCase {
    id: test
    name: "PillTouch"
    when: windowShown

    function find(item, name) {
      if (item.objectName === name) return item
      for (var i = 0; i < item.children.length; i++) {
        var hit = find(item.children[i], name)
        if (hit) return hit
      }
      return null
    }

    function init() {
      // Longer than the double-tap interval, so no test's taps count
      // towards the next one's.
      wait(600)
      Quickshell.executed = []
    }

    function calls(fragment) {
      return Quickshell.executed.filter(function(argv) { return argv.join(" ").indexOf(fragment) >= 0 }).length
    }

    function keyboardCalls(method) {
      return Quickshell.executed.filter(function(argv) {
        return argv.indexOf("omamobile.keyboard") >= 0 && argv.indexOf(method) >= 0
      }).length
    }

    function tap(item, x, y) {
      var t = touchEvent(item)
      t.press(0, item, x, y).commit()
      t.release(0, item, x, y).commit()
      wait(30)
    }

    function swipeUp(item, x, y) {
      var t = touchEvent(item)
      t.press(0, item, x, y).commit()
      for (var dy = 6; dy <= 72; dy += 6) {
        t.move(0, item, x, y - dy).commit()
        wait(5)
      }
      t.release(0, item, x, y - 72).commit()
      wait(30)
    }

    // Each case's bottom windows: what each reserves, in all what the app
    // above them loses (squeekboard reserves its own height on top), and
    // how many reserve at once.
    function zones(state) {
      harness.appOnScreen = !!state.app
      harness.opened = !!state.drawer
      harness.oskOpen = !!state.osk
      harness.fullscreenOnScreen = !!state.fullscreen
      harness.sessionLocked = !!state.locked
      return { dock: harness.dockZone, strip: harness.stripZone,
               total: harness.dockZone + harness.stripZone,
               reserving: (harness.dockZone > 0 ? 1 : 0) + (harness.stripZone > 0 ? 1 : 0) }
    }

    function voiceCalls(method) {
      return Quickshell.executed.filter(function(argv) {
        return argv.indexOf("omamobile.voice") >= 0 && argv.join(" ").indexOf(method) >= 0
      }).length
    }

    // A finger that stays still for ms, then lets go.
    function hold(item, x, y, ms) {
      var t = touchEvent(item)
      t.press(0, item, x, y).commit()
      wait(ms)
      t.release(0, item, x, y).commit()
      wait(30)
    }

    // The pill, as on Android: a tap does nothing, a double tap toggles the
    // keyboard, a hold opens the voice bar (with a tick), a swipe goes home.
    function ticks() {
      return Quickshell.executed.filter(function(argv) { return argv.join(" ").indexOf("fbcli -E button-pressed") >= 0 }).length
    }

    function test_holding_the_pill_opens_the_voice_bar_with_a_tick() {
      var strips = ["pillStrip", "keyboardStrip"]
      for (var i = 0; i < strips.length; i++) {
        Quickshell.executed = []
        var strip = find(harness, strips[i])
        var t = touchEvent(strip)
        t.press(0, strip, strip.width / 2, strip.height / 2).commit()
        wait(300)
        compare(voiceCalls("start"), 0, strips[i] + ": not before the hold takes")
        wait(400)
        compare(voiceCalls("start"), 1, strips[i] + ": " + JSON.stringify(Quickshell.executed))
        compare(ticks(), 1, strips[i] + ": a tick as it takes")
        t.release(0, strip, strip.width / 2, strip.height / 2).commit()
        wait(30)
        compare(keyboardCalls("Keyboard"), 0, strips[i] + ": a hold is no tap")
        compare(calls("hl.dsp.focus"), 0, strips[i] + ": nor a swipe")
        wait(600)
      }
    }

    function test_the_voice_call_goes_through_the_plugins_ipc() {
      var strip = find(harness, "pillStrip")
      hold(strip, strip.width / 2, strip.height / 2, 700)
      var call = Quickshell.executed.filter(function(argv) { return argv.indexOf("omamobile.voice") >= 0 })[0]
      compare(JSON.stringify(call), JSON.stringify(["qs", "ipc", "-p", "/stub/shell", "call", "shell", "call", "omamobile.voice", "start", ""]))
    }

    function test_a_swipe_after_the_hold_is_still_a_swipe() {
      var strip = find(harness, "pillStrip")
      var x = strip.width / 2, y = strip.height / 2
      var t = touchEvent(strip)
      t.press(0, strip, x, y).commit()
      wait(700)
      for (var dy = 6; dy <= 72; dy += 6) {
        t.move(0, strip, x, y - dy).commit()
        wait(5)
      }
      t.release(0, strip, x, y - 72).commit()
      wait(30)
      compare(voiceCalls("start"), 1, "the hold took: " + JSON.stringify(Quickshell.executed))
      compare(calls("hl.dsp.focus"), 1, "and the swipe still goes home")
    }

    function test_a_swipe_cancels_the_hold() {
      var strip = find(harness, "pillStrip")
      var x = strip.width / 2, y = strip.height / 2
      var t = touchEvent(strip)
      t.press(0, strip, x, y).commit()
      wait(100)
      for (var dy = 6; dy <= 72; dy += 6) {
        t.move(0, strip, x, y - dy).commit()
        wait(5)
      }
      wait(600)
      t.release(0, strip, x, y - 72).commit()
      wait(30)
      compare(voiceCalls("start"), 0, "moved past the threshold first: no voice, " + JSON.stringify(Quickshell.executed))
      compare(ticks(), 0)
    }

    function test_a_tap_and_a_double_tap_never_open_voice() {
      var strip = find(harness, "pillStrip")
      tap(strip, strip.width / 2, strip.height / 2)
      tap(strip, strip.width / 2, strip.height / 2)
      wait(700)
      compare(voiceCalls("start"), 0, JSON.stringify(Quickshell.executed))
      compare(keyboardCalls("toggleKeyboard"), 1, "the double tap is the keyboard's")
    }

    function test_the_strip_is_just_the_pill() {
      var strips = ["pillStrip", "keyboardStrip"]
      for (var i = 0; i < strips.length; i++) {
        var strip = find(harness, strips[i])
        verify(!find(strip, "voiceKey") && !find(strip, "keyboardKey") && !find(strip, "hideKeyboard"), strips[i] + ": no buttons")
      }
    }

    // The dock's search pill on the home screen: a tap opens the drawer
    // (with the keyboard), a hold opens the voice bar, a swipe recent apps.
    function test_a_tap_on_the_search_pill_opens_the_drawer() {
      var dock = find(harness, "dock")
      tap(dock, dock.width / 2, dock.height / 2)
      wait(600)
      compare(calls("expand"), 1, JSON.stringify(Quickshell.executed))
      compare(voiceCalls("start"), 0, "a tap is no voice")
    }

    function test_holding_the_search_pill_opens_the_voice_bar() {
      var dock = find(harness, "dock")
      hold(dock, dock.width / 2, dock.height / 2, 700)
      compare(voiceCalls("start"), 1, JSON.stringify(Quickshell.executed))
      compare(ticks(), 1)
      compare(calls("expand"), 0, "a hold doesn't open the drawer")
    }

    function test_a_swipe_on_the_dock_opens_recent_apps() {
      var dock = find(harness, "dock")
      swipeUp(dock, dock.width / 2, dock.height / 2)
      compare(calls("omamobile.switcher"), 1, JSON.stringify(Quickshell.executed))
      compare(calls("expand"), 0, "a swipe is no tap")
      compare(voiceCalls("start"), 0)
    }

    function test_over_an_app_the_strip_reserves_its_height() {
      var z = zones({ app: true })
      compare(z.strip, harness.touch, JSON.stringify(z))
      verify(z.strip >= 44, "a whole touch target")
      compare(z.total, z.strip, "nothing else reserves: " + JSON.stringify(z))
    }

    function test_the_keyboard_never_changes_what_the_strip_reserves() {
      var before = zones({ app: true })
      var typing = zones({ app: true, osk: true })
      var after = zones({ app: true })
      compare(typing.total, before.total, "keyboard up: " + JSON.stringify(typing))
      compare(after.total, before.total, "keyboard down: " + JSON.stringify(after))
      verify(harness.keyboardStripShown === false)
      zones({ app: true, osk: true })
      verify(harness.keyboardStripShown, "the strip is the keyboard's while it is up")
    }

    function test_never_two_reserving_bottom_windows_at_once() {
      var keys = ["app", "drawer", "osk", "fullscreen", "locked"]
      for (var bits = 0; bits < 32; bits++) {
        var state = {}
        for (var k = 0; k < keys.length; k++) state[keys[k]] = (bits >> k) & 1
        var z = zones(state)
        verify(z.reserving <= 1, JSON.stringify(state) + " " + JSON.stringify(z))
      }
    }

    function test_home_reserves_nothing() {
      // The dock shows on home but reserves nothing (the home screen keeps
      // its height free), so the drawer opening over it resizes no window.
      var z = zones({})
      compare(z.total, 0, JSON.stringify(z))
      compare(zones({ drawer: true }).total, 0, "nor with the drawer open")
      compare(zones({ osk: true }).strip, 0, "nor the strip with the keyboard on home")
    }

    function test_a_fullscreen_window_keeps_the_whole_screen() {
      compare(zones({ app: true, fullscreen: true }).total, 0)
      compare(zones({ app: true, fullscreen: true, osk: true }).total, 0)
    }

    function test_nothing_reserves_under_the_drawer_or_the_locks_keyboard() {
      compare(zones({ app: true, drawer: true }).total, 0, "the drawer")
      compare(zones({ drawer: true }).total, 0)
      compare(zones({ app: true, osk: true, locked: true }).total, 0, "the lock's keyboard")
    }

    function test_two_taps_at_the_strips_end_are_a_double_tap() {
      var strip = find(harness, "keyboardStrip")
      tap(strip, 20, strip.height / 2)
      tap(strip, 20, strip.height / 2)
      compare(keyboardCalls("toggleKeyboard"), 1, JSON.stringify(Quickshell.executed))
      compare(voiceCalls("o"), 0)
    }

    function test_single_tap_on_the_pill_does_nothing() {
      var strip = find(harness, "pillStrip")
      tap(strip, strip.width / 2, strip.height / 2)
      wait(500)
      compare(Quickshell.executed.length, 0, JSON.stringify(Quickshell.executed))
    }

    function test_double_tap_on_the_pill_toggles_the_keyboard() {
      var strip = find(harness, "pillStrip")
      tap(strip, strip.width / 2, strip.height / 2)
      tap(strip, strip.width / 2, strip.height / 2)
      compare(keyboardCalls("toggleKeyboard"), 1, JSON.stringify(Quickshell.executed))
      compare(calls("hl.dsp.focus"), 0, "a double tap doesn't go home")
      compare(calls("omamobile.switcher"), 0, "nor to recent apps")
    }

    function test_the_keyboard_call_goes_through_the_plugins_ipc() {
      var strip = find(harness, "pillStrip")
      tap(strip, strip.width / 2, strip.height / 2)
      tap(strip, strip.width / 2, strip.height / 2)
      compare(JSON.stringify(Quickshell.executed[0]),
              JSON.stringify(["qs", "ipc", "-p", "/stub/shell", "call", "shell", "call", "omamobile.keyboard", "toggleKeyboard", ""]))
    }

    function test_swipe_on_the_pill_still_goes_home() {
      var strip = find(harness, "pillStrip")
      swipeUp(strip, strip.width / 2, strip.height / 2)
      compare(calls("hl.dsp.focus"), 1, JSON.stringify(Quickshell.executed))
      compare(keyboardCalls("Keyboard"), 0, "a swipe is no tap")
    }

    function test_double_tap_in_the_keyboard_strip_toggles_the_keyboard() {
      var strip = find(harness, "keyboardStrip")
      tap(strip, strip.width / 2, strip.height / 2)
      tap(strip, strip.width / 2, strip.height / 2)
      compare(keyboardCalls("toggleKeyboard"), 1, JSON.stringify(Quickshell.executed))
      compare(calls("hl.dsp.focus"), 0)
    }

    function test_swipe_in_the_keyboard_strip_goes_home() {
      var strip = find(harness, "keyboardStrip")
      swipeUp(strip, 60, strip.height / 2)
      compare(calls("hl.dsp.focus"), 1, JSON.stringify(Quickshell.executed))
    }
  }
}
