// SPDX-License-Identifier: MIT
// Touches on the home pill and its keyboard strip (test/pill-touch runs
// this). A finger, not a mouse: TapHandler and DragHandler share a touch
// differently from a mouse press.
import QtQuick
import QtTest
import Quickshell
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
