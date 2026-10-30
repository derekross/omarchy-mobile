// SPDX-License-Identifier: MIT
// The lock's glance view (patch 0023) under qmltestrunner; test/lock-glance
// runs this against the patched Omarchy shell. A LockView as the lock
// Service makes it on a phone (keypad on, fingerprints set up), with the
// field's text kept here as the Service keeps it.
import QtQuick
import QtTest
import Quickshell
import "plugins/lock"
import "TestEnv.js" as TestEnv

Item {
  id: harness
  width: 480
  height: 1040

  property string password: ""
  property var submitted: []
  property string notificationsRaw: ""
  property var view: null

  readonly property string home: TestEnv.HOME
  readonly property double minute: 60 * 1000

  Component {
    id: lockComponent
    LockView {
      anchors.fill: parent
      keypad: true
      fingerprintConfigured: true
      inputEnabled: true
      loadBackground: false
      passwordText: harness.password
      onPasswordTextEdited: function(value) { harness.password = value }
      onSubmitPassword: function(value) { harness.submitted = harness.submitted.concat([value]) }
    }
  }

  function writeFile(rel, text) {
    var files = Quickshell.files
    files[home + "/" + rel] = text
    Quickshell.files = files
    Quickshell.diskChanged()
  }

  function entry(app, ago, id, summary, body) {
    var ts = test.glance().now - ago
    return JSON.stringify({ id: id, originalId: id, app: app, appIcon: "", summary: summary, body: body,
                            image: "/tmp/avatar-" + id + ".png", glyph: "", urgency: 1, timestamp: ts })
  }

  TestCase {
    id: test
    name: "LockGlance"
    when: windowShown

    function findAll(item, pred, out) {
      out = out || []
      if (!item) return out
      if (pred(item)) out.push(item)
      var kids = item.children || []
      for (var i = 0; i < kids.length; i++) findAll(kids[i], pred, out)
      return out
    }

    function byName(name) { return findAll(harness.view, function(i) { return i.objectName === name }) }
    function one(name) { var l = byName(name); verify(l.length > 0, "found " + name); return l[0] }
    function glance() { return one("lockGlanceView").parent }

    // Everything of the PIN view that draws: the pad's digits, the field and
    // its placeholder, the hint above it and the emergency call.
    readonly property var pinTexts: ["1", "2", "5", "9", "0", "Enter PIN", "ABC", "Emergency call",
                                     "Touch the fingerprint sensor or enter your PIN"]
    function visiblePinParts() {
      return findAll(harness.view, function(i) {
        return i.visible && i.opacity > 0 && i.text !== undefined && pinTexts.indexOf(String(i.text)) >= 0
          && i.objectName !== "lockGlanceTime"
      }).map(function(i) { return String(i.text) })
    }
    function visibleGlanceParts() {
      return findAll(harness.view, function(i) {
        return i.visible && /^lockGlance(Time|Date|Hint|Card|Quiet|More)$/.test(i.objectName)
      }).map(function(i) { return i.objectName })
    }

    function settle() { wait(400) }

    function init() {
      harness.password = ""
      harness.submitted = []
      harness.notificationsRaw = ""
      Quickshell.vars = { HOME: harness.home }
      Quickshell.responder = function(argv) {
        var cmd = argv.join(" ")
        return cmd.indexOf("/.local/state/omarchy/notifications/") >= 0 ? harness.notificationsRaw : null
      }
      writeFile(".local/state/omarchy/toggles/lock-hide-notification-text", "")
      writeFile(".local/state/omarchy/notifications.json", "")
      writeFile(".local/state/omamobile/weather.json", "")
      writeFile(".config/omarchy/shell.json", "")
      writeFile(".local/state/omarchy/toggles/credential-password", "")
      harness.view = createTemporaryObject(lockComponent, harness)
      verify(harness.view)
      settle()
    }

    function show() {
      harness.view.wakeSerial += 1
      settle()
    }

    function test_glance_first_and_alone() {
      compare(glance().showing, true)
      verify(one("lockGlanceView").visible)
      verify(one("lockGlanceTime").visible)
      compare(one("lockGlanceHint").text, "Touch the fingerprint sensor or swipe up")
      compare(visiblePinParts(), [], "nothing of the PIN view shows under the glance")
      compare(one("lockPinClock").visible, false)
      compare(one("inputSwitch").visible, false)
      compare(one("lockEmergencyCall").visible, false)
      compare(one("keypadFingerprintHint").visible, false)
    }

    function test_tap_shows_pin_view_alone() {
      mouseClick(harness.view, 240, 300)
      settle()
      compare(glance().showing, false)
      compare(one("lockGlanceView").visible, false, "the glance is hidden, not just transparent")
      compare(visibleGlanceParts(), [])
      verify(visiblePinParts().indexOf("5") >= 0, "the pad shows")
      verify(visiblePinParts().indexOf("Enter PIN") >= 0, "the field shows")
      verify(one("lockEmergencyCall").visible)
      verify(one("lockPinClock").visible)
      verify(one("lockPinClock").y < one("keypadFingerprintHint").y, "the small clock sits above the hint")
    }

    function test_tap_on_the_sensor_does_nothing() {
      mouseClick(harness.view, 240, 1040 - 120)
      settle()
      compare(glance().showing, true)
    }

    function test_swipe_up() {
      mousePress(harness.view, 240, 600)
      for (var y = 590; y >= 400; y -= 10) mouseMove(harness.view, 240, y, -1, Qt.LeftButton)
      mouseRelease(harness.view, 240, 400)
      settle()
      compare(glance().showing, false)
    }

    function test_digit_on_glance_is_kept() {
      harness.view.forcePasswordFocus()
      verify(glance().activeFocus, "the glance holds the keys while it is up")
      keyClick(Qt.Key_5)
      settle()
      compare(harness.password, "5")
      compare(glance().showing, false)
      keyClick(Qt.Key_7)
      compare(harness.password, "57", "the next digit goes to the pad")
    }

    function test_idle_returns_to_glance() {
      var idle = findChild(glance(), "lockGlanceIdle")
      verify(idle)
      idle.interval = 800
      mouseClick(harness.view, 240, 300)
      wait(100)
      compare(glance().showing, false)
      tryCompare(glance(), "showing", true, 3000)
      settle()
      compare(visiblePinParts(), [])
    }

    function test_idle_waits_for_a_typed_pin() {
      var idle = findChild(glance(), "lockGlanceIdle")
      idle.interval = 300
      mouseClick(harness.view, 240, 300)
      settle()
      harness.password = "12"
      wait(800)
      compare(glance().showing, false, "a half-typed PIN keeps the PIN view")
    }

    function test_wake_returns_to_glance_and_clears() {
      mouseClick(harness.view, 240, 300)
      settle()
      harness.password = "12"
      harness.view.wakeSerial += 1
      settle()
      compare(glance().showing, true)
      compare(harness.password, "")
      compare(visiblePinParts(), [])
    }

    function test_failed_attempt_keeps_pin_view() {
      mouseClick(harness.view, 240, 300)
      settle()
      harness.view.authenticatingPassword = true
      harness.view.authenticatingPassword = false
      harness.view.failureMessage = "Authentication failed (1)"
      settle()
      compare(glance().showing, false)
    }

    function test_notifications_grouped() {
      harness.notificationsRaw = [
        entry("Messages", 2 * minute, 1, "Sam", "Running late\nsecond line"),
        entry("Messages", 5 * minute, 2, "Sam", "Earlier"),
        entry("Updates", 18 * minute, 3, "4 updates ready", "omamobile-shell and 3 more"),
        entry("Calendar", 60 * minute, 4, "Standup at 10:00", "Video call"),
        entry("Mail", 120 * minute, 5, "Invoice", "Attached"),
        entry("Mail", 121 * minute, 6, "Invoice 2", "Attached"),
        entry("GitHub", 150 * minute, 7, "New pull request", "tools"),
        entry("omarchy-action", 1 * minute, 8, "Theme changed", ""),
        entry("Old", 30 * 60 * minute, 9, "Yesterday's", "news")
      ].join("\n") + "\n"
      show()
      var g = glance().groups
      compare(g.length, 5, "one group per app, Omarchy's action toasts and old ones left out")
      compare(g[0].app, "Messages")
      compare(g[0].count, 2)
      compare(g[0].detail, "2 new, 2m")
      compare(g[0].body, "Running late", "one line of the newest body")
      compare(g[2].detail, "1h")
      var cards = byName("lockGlanceCard").filter(function(c) { return c.visible })
      compare(cards.length, 3)
      compare(cards[0].summary, "Sam")
      compare(cards[0].bodyLines, 1)
      compare(cards[0].swipeEnabled, false)
      compare(cards[0].closeButtonShown, false)
      compare(one("lockGlanceMore").text, "3 more from Mail and GitHub")
      compare(one("lockGlanceQuiet").visible, false)
      var hint = one("lockGlanceHint")
      var last = cards[2]
      verify(last.mapToItem(harness, 0, last.height).y < hint.mapToItem(harness, 0, 0).y, "the cards stay above the hint")
      // A card asks for the PIN, nothing else (the pad folds the on-screen
      // keyboard, as before).
      Quickshell.executed = []
      mouseClick(cards[0], 20, 10)
      settle()
      compare(glance().showing, false)
      compare(Quickshell.executed.filter(function(a) { return a[0] !== "busctl" }), [])
    }

    function test_hide_text_toggle() {
      harness.notificationsRaw = entry("Messages", 2 * minute, 1, "Sam", "Secret") + "\n"
      writeFile(".local/state/omarchy/toggles/lock-hide-notification-text", "1\n")
      show()
      var card = byName("lockGlanceCard")[0]
      compare(card.summary, "Messages")
      compare(card.body, "Unlock to read")
      compare(card.image, "", "no sender picture")
      writeFile(".local/state/omarchy/toggles/lock-hide-notification-text", "")
      settle()
      compare(byName("lockGlanceCard")[0].summary, "Sam")
    }

    function test_do_not_disturb_hides_cards() {
      harness.notificationsRaw = entry("Messages", 2 * minute, 1, "Sam", "Hi") + "\n"
      writeFile(".local/state/omarchy/notifications.json", '{"version": 3, "dnd": true}\n')
      show()
      compare(byName("lockGlanceCard").filter(function(c) { return c.visible }).length, 0)
      writeFile(".local/state/omarchy/notifications.json", '{"version": 3, "dnd": false}\n')
      settle()
      compare(byName("lockGlanceCard").filter(function(c) { return c.visible }).length, 1)
    }

    function test_no_notifications() {
      show()
      verify(one("lockGlanceQuiet").visible)
      compare(one("lockGlanceMore").visible, false)
    }

    function test_weather_line() {
      var w = one("lockGlanceWeather")
      compare(w.visible, false, "no reading, no line")
      writeFile(".local/state/omamobile/weather.json",
                JSON.stringify({ at: Date.now() - 10 * minute, temperature: 12.4, unit: "°C", text: "Partly cloudy" }))
      settle()
      verify(w.visible)
      compare(w.text, "12°, partly cloudy")
      writeFile(".local/state/omamobile/weather.json",
                JSON.stringify({ at: Date.now() - 4 * 60 * minute, temperature: 12, unit: "°C", text: "Clear" }))
      settle()
      compare(w.visible, false, "a reading over 3 h old is not shown")
    }

    function test_clock_follows_bar_format() {
      writeFile(".config/omarchy/shell.json", JSON.stringify({ bar: { clockFormat: "h:mm AP" } }))
      settle()
      verify(/^\d{1,2}:\d\d$/.test(one("lockGlanceTime").text), one("lockGlanceTime").text)
      verify(/^\d{1,2}:\d\d (AM|PM)$/i.test(one("lockPinClock").text), one("lockPinClock").text)
      writeFile(".config/omarchy/shell.json", JSON.stringify({ bar: { clockFormat: "HH:mm" } }))
      settle()
      verify(/^\d\d:\d\d$/.test(one("lockGlanceTime").text), one("lockGlanceTime").text)
      verify(/^\d\d:\d\d$/.test(one("lockPinClock").text), one("lockPinClock").text)
    }

    function test_password_first_reveals_the_field() {
      writeFile(".local/state/omarchy/toggles/credential-password", "1\n")
      settle()
      compare(harness.view.passwordFirst, true)
      keyClick(Qt.Key_A)
      settle()
      compare(harness.password, "a", "a letter goes into a password")
      compare(glance().showing, false)
      verify(visiblePinParts().indexOf("123") < 0)
      writeFile(".local/state/omarchy/toggles/credential-password", "")
    }

    function test_computer_lock_unchanged() {
      harness.view.keypad = false
      settle()
      compare(glance().visible, false)
      compare(one("lockGlanceView").visible, false)
      compare(harness.view.pinOpacity, 1)
      compare(harness.view.pinVisible, true)
      compare(one("lockPinClock").visible, false)
      compare(one("lockEmergencyCall").visible, false)
      verify(findAll(harness.view, function(i) { return i.visible && String(i.text) === "Enter Password" }).length > 0)
    }
  }
}
