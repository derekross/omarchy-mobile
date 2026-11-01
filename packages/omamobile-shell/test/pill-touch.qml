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

    function test_holding_the_pill_asks_the_agent_until_it_lets_go() {
      var strip = find(harness, "pillStrip")
      var t = touchEvent(strip)
      t.press(0, strip, strip.width / 2, strip.height / 2).commit()
      wait(800)
      compare(voiceCalls("askPress"), 1, JSON.stringify(Quickshell.executed))
      compare(voiceCalls("askRelease"), 0, "still listening while the finger is down")
      t.release(0, strip, strip.width / 2, strip.height / 2).commit()
      wait(30)
      compare(voiceCalls("askRelease"), 1, JSON.stringify(Quickshell.executed))
      compare(keyboardCalls("Keyboard"), 0, "a hold is no tap")
      compare(calls("hl.dsp.focus"), 0, "nor a swipe home")
    }

    function test_the_voice_call_goes_through_the_plugins_ipc() {
      var strip = find(harness, "pillStrip")
      hold(strip, strip.width / 2, strip.height / 2, 800)
      compare(JSON.stringify(Quickshell.executed[0]),
              JSON.stringify(["qs", "ipc", "-p", "/stub/shell", "call", "shell", "call", "omamobile.voice", "askPress", ""]))
    }

    function test_holding_the_keyboard_strip_asks_the_agent_too() {
      var strip = find(harness, "keyboardStrip")
      hold(strip, strip.width / 2, strip.height / 2, 800)
      compare(voiceCalls("askPress"), 1, JSON.stringify(Quickshell.executed))
      compare(voiceCalls("askRelease"), 1)
    }

    function test_a_tap_and_a_double_tap_never_ask() {
      var strip = find(harness, "pillStrip")
      tap(strip, strip.width / 2, strip.height / 2)
      tap(strip, strip.width / 2, strip.height / 2)
      wait(700)
      compare(voiceCalls("ask"), 0, JSON.stringify(Quickshell.executed))
    }

    function test_a_swipe_after_a_hold_stops_listening_and_stays() {
      var strip = find(harness, "pillStrip")
      var x = strip.width / 2, y = strip.height / 2
      var t = touchEvent(strip)
      t.press(0, strip, x, y).commit()
      wait(800)
      for (var dy = 6; dy <= 72; dy += 6) {
        t.move(0, strip, x, y - dy).commit()
        wait(5)
      }
      t.release(0, strip, x, y - 72).commit()
      wait(30)
      compare(voiceCalls("askPress"), 1, JSON.stringify(Quickshell.executed))
      compare(voiceCalls("askRelease"), 1, "listening stops")
      compare(calls("hl.dsp.focus"), 0, "a held finger that moves doesn't go home")
      compare(calls("omamobile.switcher"), 0, "nor to recent apps")
    }

    function test_the_mic_key_shows_only_with_the_keyboard_at_the_left_end() {
      verify(!find(find(harness, "pillStrip"), "micKey").visible, "no mic over an app")
      var strip = find(harness, "keyboardStrip")
      var key = find(strip, "micKey")
      verify(key.visible)
      verify(key.width >= 44 && key.height >= 44, key.width + "x" + key.height)
      var p = key.mapToItem(strip, 0, 0)
      verify(p.x <= 8, "at the left end: " + p.x)
    }

    function test_tapping_the_mic_key_toggles_dictation() {
      var strip = find(harness, "keyboardStrip")
      var key = find(strip, "micKey")
      var c = key.mapToItem(strip, key.width / 2, key.height / 2)
      tap(strip, c.x, c.y)
      compare(voiceCalls("dictateTap"), 1, JSON.stringify(Quickshell.executed))
      compare(voiceCalls("ask"), 0)
      tap(strip, c.x, c.y)
      compare(voiceCalls("dictateTap"), 2)
      compare(keyboardCalls("toggleKeyboard"), 0, "two taps on the mic are no double tap")
    }

    function test_holding_the_mic_key_is_push_to_talk() {
      var strip = find(harness, "keyboardStrip")
      var key = find(strip, "micKey")
      var c = key.mapToItem(strip, key.width / 2, key.height / 2)
      hold(strip, c.x, c.y, 800)
      compare(voiceCalls("dictatePress"), 1, JSON.stringify(Quickshell.executed))
      compare(voiceCalls("dictateRelease"), 1)
      compare(voiceCalls("dictateTap"), 0, "a hold is no tap")
      compare(voiceCalls("ask"), 0, "the mic's hold is its own, not the strip's")
    }

    // The dock's search pill on the home screen: tap opens the drawer
    // (with the keyboard), hold asks by voice, the mic at its right end
    // listens on a tap and talks on a hold, a swipe opens recent apps.
    function test_a_tap_on_the_search_pill_opens_the_drawer() {
      var dock = find(harness, "dock")
      tap(dock, dock.width / 2, dock.height / 2)
      wait(600)
      compare(calls("expand"), 1, JSON.stringify(Quickshell.executed))
      compare(voiceCalls("ask"), 0, "a tap is no voice")
    }

    function test_holding_the_search_pill_asks_by_voice() {
      var dock = find(harness, "dock")
      hold(dock, dock.width / 2, dock.height / 2, 800)
      compare(voiceCalls("askPress"), 1, JSON.stringify(Quickshell.executed))
      compare(voiceCalls("askRelease"), 1)
      compare(calls("expand"), 0, "a hold doesn't open the drawer")
    }

    function test_the_search_pill_has_a_mic_at_its_right_end() {
      var dock = find(harness, "dock")
      var mic = find(dock, "pillMic")
      verify(mic && mic.visible, "a mic button")
      verify(mic.width >= 44 && mic.height >= 44, mic.width + "x" + mic.height)
      compare(mic.Accessible.name, "Ask by voice")
      var p = mic.mapToItem(dock, 0, 0)
      verify(dock.width - (p.x + mic.width) <= Style.spacing.xxl + 8, "at the right end: " + p.x)
    }

    function test_tapping_the_mic_listens_hands_free() {
      var dock = find(harness, "dock")
      var mic = find(dock, "pillMic")
      var c = mic.mapToItem(dock, mic.width / 2, mic.height / 2)
      tap(dock, c.x, c.y)
      wait(600)
      compare(voiceCalls("askTap"), 1, JSON.stringify(Quickshell.executed))
      compare(calls("expand"), 0, "the mic's tap doesn't open the drawer")
    }

    function test_holding_the_mic_is_push_to_talk() {
      var dock = find(harness, "dock")
      var mic = find(dock, "pillMic")
      var c = mic.mapToItem(dock, mic.width / 2, mic.height / 2)
      hold(dock, c.x, c.y, 800)
      compare(voiceCalls("askPress"), 1, JSON.stringify(Quickshell.executed))
      compare(voiceCalls("askRelease"), 1)
      compare(voiceCalls("askTap"), 0)
      compare(calls("expand"), 0)
    }

    function test_a_swipe_on_the_dock_opens_recent_apps() {
      var dock = find(harness, "dock")
      swipeUp(dock, dock.width / 2, dock.height / 2)
      compare(calls("omamobile.switcher"), 1, JSON.stringify(Quickshell.executed))
      compare(calls("expand"), 0, "a swipe is no tap")
      compare(voiceCalls("ask"), 0)
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

    function test_the_hide_key_shows_only_with_the_keyboard() {
      var key = find(find(harness, "pillStrip"), "hideKeyboard")
      verify(key && !key.visible, "no hide key over an app")
      verify(find(find(harness, "keyboardStrip"), "hideKeyboard").visible)
    }

    function test_two_taps_where_the_hidden_key_sits_are_a_double_tap() {
      var strip = find(harness, "pillStrip")
      tap(strip, strip.width - 20, strip.height / 2)
      tap(strip, strip.width - 20, strip.height / 2)
      compare(keyboardCalls("toggleKeyboard"), 1, JSON.stringify(Quickshell.executed))
      compare(keyboardCalls("hideKeyboard"), 0)
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

    function test_the_hide_key_is_a_touch_target_at_the_strips_right_end() {
      var strip = find(harness, "keyboardStrip")
      var key = find(strip, "hideKeyboard")
      verify(key, "the strip has a hide key")
      verify(key.width >= 44 && key.height >= 44, key.width + "x" + key.height)
      verify(strip.height >= 44, "the strip holds a whole touch target: " + strip.height)
      var p = key.mapToItem(strip, 0, 0)
      verify(p.y >= 0 && p.y + key.height <= strip.height, "inside the strip")
      verify(strip.width - (p.x + key.width) <= 8, "at its right end")
    }

    function test_tapping_the_hide_key_hides_the_keyboard() {
      var strip = find(harness, "keyboardStrip")
      var key = find(strip, "hideKeyboard")
      var c = key.mapToItem(strip, key.width / 2, key.height / 2)
      tap(strip, c.x, c.y)
      compare(keyboardCalls("hideKeyboard"), 1, JSON.stringify(Quickshell.executed))
      compare(keyboardCalls("toggleKeyboard"), 0)
      compare(calls("hl.dsp.focus"), 0)
    }

    function test_two_taps_on_the_hide_key_are_no_double_tap() {
      var strip = find(harness, "keyboardStrip")
      var key = find(strip, "hideKeyboard")
      var c = key.mapToItem(strip, key.width / 2, key.height / 2)
      tap(strip, c.x, c.y)
      tap(strip, c.x, c.y)
      compare(keyboardCalls("toggleKeyboard"), 0, JSON.stringify(Quickshell.executed))
    }

    function test_a_swipe_from_the_hide_key_goes_home() {
      var strip = find(harness, "keyboardStrip")
      var key = find(strip, "hideKeyboard")
      var c = key.mapToItem(strip, key.width / 2, key.height / 2)
      swipeUp(strip, c.x, c.y)
      compare(calls("hl.dsp.focus"), 1, JSON.stringify(Quickshell.executed))
      compare(keyboardCalls("hideKeyboard"), 0, "the swipe doesn't also hide the keyboard")
    }

    function test_swipe_in_the_keyboard_strip_goes_home() {
      var strip = find(harness, "keyboardStrip")
      swipeUp(strip, 60, strip.height / 2)
      compare(calls("hl.dsp.focus"), 1, JSON.stringify(Quickshell.executed))
    }
  }
}
