// SPDX-License-Identifier: MIT
// The lock's glance view (patch 0023) under qmltestrunner; test/lock-glance
// runs this against the patched Omarchy shell. A LockView as the lock
// Service makes it on a phone (keypad on, fingerprints set up), with the
// field's text kept here as the Service keeps it, and the display lit again
// by a wake request as the Service's runWake lights it.
import QtQuick
import QtTest
import Quickshell
import "plugins/lock"
import "plugins/lock/LockGlance.js" as Glance
import "TestEnv.js" as TestEnv

Item {
  id: harness
  width: 480
  height: 1040

  property string password: ""
  property var submitted: []
  property int wakes: 0
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
      onWakeRequested: { displayDark = false; harness.wakes += 1 }
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

    // A clear swipe up from (x, y): 200 px, about a fifth of the screen.
    function swipeUp(item, x, y) {
      mousePress(item, x, y)
      for (var d = 10; d <= 200; d += 10) mouseMove(item, x, y - d, -1, Qt.LeftButton)
      mouseRelease(item, x, y - 200)
    }

    // A drag sideways by dx from (x, y), and up by dy as it goes.
    function drag(item, x, y, dx, dy) {
      mousePress(item, x, y)
      for (var i = 1; i <= 20; i++) mouseMove(item, x + dx * i / 20, y + dy * i / 20, -1, Qt.LeftButton)
      mouseRelease(item, x + dx, y + dy)
    }

    function visibleCards() { return byName("lockGlanceCard").filter(function(x) { return x.visible }) }
    function centre(card) { return card.mapToItem(harness.view, card.width / 2, card.height / 2) }
    function forgets() {
      return Quickshell.started.filter(function(a) { return a.join(" ").indexOf("call notifications forget") >= 0 })
    }

    // To the PIN view, as a person gets there: a swipe up.
    function toPin() {
      swipeUp(harness.view, 240, 700)
      settle()
    }

    function init() {
      harness.password = ""
      harness.submitted = []
      harness.wakes = 0
      harness.notificationsRaw = ""
      Quickshell.vars = { HOME: harness.home }
      Quickshell.started = []
      Quickshell.responder = function(argv) {
        var cmd = argv.join(" ")
        // The notifications service's forget: the file goes.
        if (cmd.indexOf("call notifications forget") >= 0) {
          var names = argv.slice(5)
          harness.notificationsRaw = harness.notificationsRaw.split("\n").filter(function(line) {
            if (!line) return false
            var e = JSON.parse(line)
            return names.indexOf(e.timestamp + "-" + e.originalId + ".json") < 0
          }).join("\n") + "\n"
          return ""
        }
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

    // A wake, and past the moment after it in which a touch only wakes.
    function show() {
      harness.view.wakeSerial += 1
      wait(500)
    }

    // The screen goes dark as the lock Service has it go: the serial, and
    // dark until a wake request lights it.
    function blank() {
      harness.view.blankSerial += 1
      harness.view.displayDark = true
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

    function test_swipe_shows_pin_view_alone() {
      toPin()
      compare(glance().showing, false)
      compare(one("lockGlanceView").visible, false, "the glance is hidden, not just transparent")
      compare(visibleGlanceParts(), [])
      verify(visiblePinParts().indexOf("5") >= 0, "the pad shows")
      verify(visiblePinParts().indexOf("Enter PIN") >= 0, "the field shows")
      verify(one("lockEmergencyCall").visible)
      verify(one("lockPinClock").visible)
      verify(one("lockPinClock").y < one("keypadFingerprintHint").y, "the small clock sits above the hint")
    }

    function test_tap_on_empty_glance_does_nothing() {
      mouseClick(harness.view, 240, 300)
      settle()
      compare(glance().showing, true, "a tap never shows the PIN view")
      mouseClick(harness.view, 240, 120)
      settle()
      compare(glance().showing, true)
    }

    // Short, slow drags (a scroll that went nowhere) don't count.
    function test_a_short_drag_does_nothing() {
      mousePress(harness.view, 240, 600)
      for (var y = 595; y >= 560; y -= 5) { mouseMove(harness.view, 240, y, -1, Qt.LeftButton); wait(50) }
      mouseRelease(harness.view, 240, 560)
      settle()
      compare(glance().showing, true)
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
      idle.returnAfter = 800
      swipeUp(harness.view, 240, 700)
      wait(100)
      compare(glance().showing, false)
      tryCompare(glance(), "showing", true, 3000)
      settle()
      compare(visiblePinParts(), [])
    }

    function test_idle_waits_for_a_typed_pin() {
      var idle = findChild(glance(), "lockGlanceIdle")
      idle.returnAfter = 300
      toPin()
      harness.password = "12"
      wait(1600)
      compare(glance().showing, false, "a half-typed PIN keeps the PIN view")
    }

    function test_wake_returns_to_glance_and_clears() {
      toPin()
      harness.password = "12"
      harness.view.wakeSerial += 1
      settle()
      compare(glance().showing, true)
      compare(harness.password, "")
      compare(visiblePinParts(), [])
    }

    // The countdown is on the wall clock: a sleep froze the timer, but not
    // the clock, and the PIN view has been up 20 s by the time it resumes.
    function test_frozen_timer_returns_by_wall_clock() {
      var idle = findChild(glance(), "lockGlanceIdle")
      compare(idle.returnAfter, 15000)
      toPin()
      compare(glance().showing, false)
      idle.since = Date.now() - 20000
      tryCompare(glance(), "showing", true, 2500)
    }

    function test_blank_on_pin_view_returns_to_glance() {
      toPin()
      harness.password = "12"
      compare(glance().showing, false)
      blank()
      compare(glance().showing, true, "the screen went dark: back to the glance")
      compare(harness.password, "", "a half-typed PIN is cleared")
      compare(visiblePinParts(), [])
    }

    function test_wake_tap_on_dark_display_only_wakes() {
      toPin()
      blank()
      harness.wakes = 0
      mouseClick(harness.view, 240, 300)
      settle()
      compare(glance().showing, true, "the tap that woke the screen doesn't show the PIN view")
      compare(harness.view.displayDark, false, "it lit the screen through the lock")
      compare(harness.wakes, 1)
      wait(200)
      toPin()
      compare(glance().showing, false, "a swipe up on the lit glance shows the PIN view")
    }

    function test_wake_swipe_on_dark_display_only_wakes() {
      blank()
      mousePress(harness.view, 240, 600)
      for (var y = 590; y >= 400; y -= 10) mouseMove(harness.view, 240, y, -1, Qt.LeftButton)
      mouseRelease(harness.view, 240, 400)
      settle()
      compare(glance().showing, true)
      compare(harness.view.displayDark, false)
    }

    function test_touch_right_after_a_wake_only_wakes() {
      // The power button lit the screen; a finger lands on it at once.
      blank()
      harness.view.wakeSerial += 1
      harness.view.displayDark = false
      swipeUp(harness.view, 240, 700)
      wait(100)
      compare(glance().showing, true, "a swipe that starts within the guard doesn't show the PIN view")
      wait(500)
      toPin()
      compare(glance().showing, false)
    }

    function test_failed_attempt_keeps_pin_view() {
      toPin()
      harness.view.authenticatingPassword = true
      harness.view.authenticatingPassword = false
      harness.view.failureMessage = "Authentication failed (1)"
      settle()
      compare(glance().showing, false)
    }

    function test_notifications_as_cards() {
      harness.notificationsRaw = [
        entry("Messages", 2 * minute, 1, "Sam", "Running late\nsecond line\nthird line"),
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
      var c = glance().cards
      compare(c.length, 9, "one card per notification, as the shade lists them: Omarchy's own and old ones included")
      compare(c[0].app, "Omarchy", "Omarchy's own messages (omarchy-action) go by Omarchy")
      compare(c[0].summary, "Theme changed")
      compare(c[1].app, "Messages")
      compare(c[1].detail, "2m", "the detail is the age, nothing more")
      compare(c[2].summary, "Sam")
      compare(c[2].detail, "5m")
      compare(c[4].detail, "1h")
      compare(c[8].app, "Old")
      compare(c[8].detail, "30h", "no age limit, as in the shade")
      var cards = byName("lockGlanceCard").filter(function(x) { return x.visible })
      compare(cards.length, 3)
      compare(cards[0].summary, "Theme changed")
      compare(cards[1].summary, "Sam")
      compare(cards[2].summary, "Sam", "two from one app are two cards")
      compare(cards[1].summaryLines, 1)
      compare(cards[1].bodyLines, 1)
      compare(cards[1].swipeEnabled, false)
      compare(cards[1].closeButtonShown, false)
      compare(one("lockGlanceMore").text, "6 more from Updates, Calendar and 3 others")
      compare(one("lockGlanceQuiet").visible, false)
      var hint = one("lockGlanceHint")
      var last = cards[2]
      verify(last.mapToItem(harness, 0, last.height).y < hint.mapToItem(harness, 0, 0).y, "the cards stay above the hint")
      // A tap on a card opens it to more of its text and runs nothing; a
      // second tap closes it. The PIN view stays away.
      Quickshell.executed = []
      var closedHeight = cards[1].height
      mouseClick(cards[1], cards[1].width / 2, 10)
      settle()
      compare(glance().showing, true, "a tap on a card doesn't show the PIN view")
      compare(cards[1].summaryLines, 2)
      compare(cards[1].bodyLines, 4)
      verify(cards[1].height > closedHeight, "the open card is taller")
      compare(cards[0].bodyLines, 1, "only that card opens")
      compare(Quickshell.executed.filter(function(a) { return a[0] !== "busctl" }), [])
      mouseClick(cards[1], cards[1].width / 2, 10)
      settle()
      compare(cards[1].bodyLines, 1)
      // A swipe up that starts on a card shows the PIN view.
      var p = cards[0].mapToItem(harness.view, cards[0].width / 2, cards[0].height / 2)
      swipeUp(harness.view, p.x, p.y)
      settle()
      compare(glance().showing, false, "a swipe up from a card shows the PIN view")
    }

    function test_an_open_card_closes_when_the_glance_comes_back() {
      harness.notificationsRaw = entry("Messages", 2 * minute, 1, "Sam", "Hi\nthere") + "\n"
      show()
      var card = byName("lockGlanceCard")[0]
      mouseClick(card, card.width / 2, 10)
      settle()
      compare(card.bodyLines, 4)
      blank()
      compare(card.bodyLines, 1)
    }

    function test_three_from_one_app_are_three_cards() {
      harness.notificationsRaw = [
        entry("omarchy-action", 1 * minute, 1, "Theme changed", ""),
        entry("omarchy-action", 2 * minute, 2, "Wallpaper changed", ""),
        entry("omarchy-action", 3 * minute, 3, "Update available", "")
      ].join("\n") + "\n"
      show()
      var cards = byName("lockGlanceCard").filter(function(x) { return x.visible })
      compare(cards.length, 3)
      compare(cards.map(function(x) { return x.summary }), ["Theme changed", "Wallpaper changed", "Update available"])
      compare(one("lockGlanceMore").visible, false)
    }

    function test_five_are_three_cards_and_a_line() {
      harness.notificationsRaw = [
        entry("Messages", 1 * minute, 1, "Sam", "One"),
        entry("Messages", 2 * minute, 2, "Sam", "Two"),
        entry("Mail", 3 * minute, 3, "Invoice", "Three"),
        entry("Mail", 4 * minute, 4, "Invoice 2", "Four"),
        entry("GitHub", 5 * minute, 5, "Review", "Five")
      ].join("\n") + "\n"
      show()
      compare(byName("lockGlanceCard").filter(function(x) { return x.visible }).length, 3)
      compare(one("lockGlanceMore").text, "2 more from Mail and GitHub")
    }

    function test_swipe_a_card_sideways_dismisses_it() {
      harness.notificationsRaw = [
        entry("Messages", 1 * minute, 1, "Sam", "One"),
        entry("Mail", 2 * minute, 2, "Invoice", "Two"),
        entry("GitHub", 3 * minute, 3, "Review", "Three"),
        entry("Calendar", 4 * minute, 4, "Standup", "Four")
      ].join("\n") + "\n"
      show()
      compare(visibleCards().length, 3)
      compare(one("lockGlanceMore").text, "1 more from Calendar")
      var file = glance().cards[1].file
      var p = centre(visibleCards()[1])
      drag(harness.view, p.x, p.y, 300, 10)
      wait(800)
      compare(glance().showing, true, "a sideways swipe doesn't show the PIN view")
      var calls = forgets()
      compare(calls.length, 1, "one forget")
      verify(calls[0].indexOf(file) > 0, "the forget names that notification: " + calls[0].join(" "))
      verify(/^[0-9]+-2\.json$/.test(file), "its file name carries its id: " + file)
      compare(Quickshell.executed.filter(function(a) { return a[0] !== "busctl" }), [], "nothing of it runs")
      tryCompare(one("lockGlanceMore"), "visible", false, 2000)
      compare(visibleCards().map(function(c) { return c.summary }), ["Sam", "Review", "Standup"],
              "the next one moves up from the more line")
    }

    function test_a_short_sideways_swipe_springs_back() {
      harness.notificationsRaw = entry("Messages", 1 * minute, 1, "Sam", "One") + "\n"
      show()
      var p = centre(visibleCards()[0])
      mousePress(harness.view, p.x, p.y)
      for (var i = 1; i <= 10; i++) { mouseMove(harness.view, p.x + 4 * i, p.y, -1, Qt.LeftButton); wait(30) }
      mouseRelease(harness.view, p.x + 40, p.y)
      wait(600)
      compare(forgets().length, 0)
      compare(visibleCards().length, 1)
      compare(visibleCards()[0].swipeOffset, 0)
    }

    function test_a_mostly_vertical_swipe_from_a_card_shows_the_pin_view() {
      harness.notificationsRaw = entry("Messages", 1 * minute, 1, "Sam", "One") + "\n"
      show()
      var p = centre(visibleCards()[0])
      drag(harness.view, p.x, p.y, 60, -200)
      settle()
      compare(glance().showing, false)
      compare(forgets().length, 0, "nothing dismissed")
    }

    function test_dismiss_the_last_one_with_hidden_text() {
      writeFile(".local/state/omarchy/toggles/lock-hide-notification-text", "1\n")
      harness.notificationsRaw = entry("Messages", 1 * minute, 1, "Sam", "Secret") + "\n"
      show()
      compare(visibleCards()[0].body, "Unlock to read")
      var p = centre(visibleCards()[0])
      drag(harness.view, p.x, p.y, -300, 0)
      wait(800)
      compare(forgets().length, 1)
      tryCompare(one("lockGlanceQuiet"), "visible", true, 2000)
      compare(visibleCards().length, 0)
      compare(glance().showing, true)
      writeFile(".local/state/omarchy/toggles/lock-hide-notification-text", "")
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

    // Do-not-disturb as the toasts have it: only what still toasts shows
    // (Omarchy's own messages, a critical notify-send).
    function test_do_not_disturb_shows_what_still_toasts() {
      harness.notificationsRaw = [
        entry("Messages", 2 * minute, 1, "Sam", "Hi"),
        entry("omarchy-action", 3 * minute, 2, "Theme changed", ""),
        entry("notify-send", 4 * minute, 3, "Ping", "")
      ].join("\n") + "\n"
      writeFile(".local/state/omarchy/notifications.json", '{"version": 3, "dnd": true}\n')
      show()
      var cards = byName("lockGlanceCard").filter(function(c) { return c.visible })
      compare(cards.length, 1)
      compare(cards[0].summary, "Theme changed")
      writeFile(".local/state/omarchy/notifications.json", '{"version": 3, "dnd": false}\n')
      settle()
      compare(byName("lockGlanceCard").filter(function(c) { return c.visible }).length, 3)
      compare(glance().cards[2].app, "Notifications", "a bare notify-send goes by Notifications")
    }

    // The shade's ten: the newest ten notifications, whatever their age.
    function test_the_shades_ten() {
      var lines = []
      for (var i = 0; i < 12; i++) lines.push(entry("App" + i, (i + 1) * minute, 10 + i, "Note " + i, "body"))
      lines.push(JSON.stringify({ id: 99, originalId: 99, app: "Empty", summary: "", body: "", timestamp: test.glance().now }))
      harness.notificationsRaw = lines.join("\n") + "\n"
      show()
      var g = glance().cards
      compare(g.length, 10)
      compare(g[0].app, "App0", "a row with no text is skipped, as in the shade")
      compare(g[9].app, "App9")
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
      verify(/^([1-9]|1[0-2]):\d\d$/.test(one("lockGlanceTime").text), one("lockGlanceTime").text)
      verify(/^([1-9]|1[0-2]):\d\d (AM|PM)$/i.test(one("lockPinClock").text), one("lockPinClock").text)
      writeFile(".config/omarchy/shell.json", JSON.stringify({ bar: { clockFormat: "HH:mm" } }))
      settle()
      verify(/^\d\d:\d\d$/.test(one("lockGlanceTime").text), one("lockGlanceTime").text)
      verify(/^\d\d:\d\d$/.test(one("lockPinClock").text), one("lockPinClock").text)
    }

    // The maintainer's bar: a day, a date and a 12-hour time. The lock reads
    // it at once, whether or not the glance is up yet (keypad off here, as
    // before the lock-keypad toggle is read), and the session's locale (C,
    // test/lock-glance) has no say.
    function test_the_bars_12_hour_format_before_the_glance_is_up() {
      compare(Qt.locale().name, "C", "the test runs under the C locale, as the shell does")
      writeFile(".config/omarchy/shell.json", JSON.stringify({ version: 1, bar: { position: "top", clockFormat: "ddd MMM d  h:mm AP" } }))
      var view = createTemporaryObject(lockComponent, harness, { keypad: false })
      var g = findAll(view, function(i) { return i.objectName === "lockGlanceView" })[0].parent
      compare(g.active, false)
      compare(g.twelveHour, true, "12-hour from the bar's format, before the glance is up")
      view.keypad = true
      compare(g.twelveHour, true)
      var pin = findAll(view, function(i) { return i.objectName === "lockPinClock" })[0]
      var big = findAll(view, function(i) { return i.objectName === "lockGlanceTime" })[0]
      verify(/^\d{1,2}:\d\d (AM|PM)$/i.test(pin.text), "the small clock keeps AM/PM: " + pin.text)
      verify(/^([1-9]|1[0-2]):\d\d$/.test(big.text), "the big time is 12-hour without AM/PM: " + big.text)
    }

    function test_a_failed_read_keeps_the_format() {
      writeFile(".config/omarchy/shell.json", JSON.stringify({ bar: { clockFormat: "h:mm AP" } }))
      settle()
      compare(glance().twelveHour, true)
      writeFile(".config/omarchy/shell.json", "{\"bar\": {\"clockF")
      settle()
      compare(glance().twelveHour, true, "a half-written file keeps the last format")
      writeFile(".config/omarchy/shell.json", "")
      settle()
      compare(glance().twelveHour, true, "a file being replaced keeps the last format")
      writeFile(".config/omarchy/shell.json", JSON.stringify({ bar: { clockFormat: "HH:mm" } }))
      settle()
      compare(glance().twelveHour, false)
    }

    // The same 12/24-hour rule as the bar and the home clock
    // (HomeModel.systemTimeFormat in omamobile-shell), and a big time that is
    // really 12-hour.
    function test_the_rule_and_the_big_time() {
      verify(Glance.twelveHour("ddd MMM d  h:mm AP"))
      verify(Glance.twelveHour("hh:mm"))
      verify(Glance.twelveHour("h:mm ap"))
      verify(!Glance.twelveHour("HH:mm"))
      verify(!Glance.twelveHour("'h' HH:mm"), "quoted literals don't count")
      verify(!Glance.twelveHour(""), "no format: the bar's default, HH:mm")
      compare(Glance.timeFormat(true), "h:mm AP")
      compare(Glance.timeFormat(false), "HH:mm")
      compare(Glance.glanceTime(new Date(2026, 9, 30, 14, 2), true), "2:02")
      compare(Glance.glanceTime(new Date(2026, 9, 30, 0, 5), true), "12:05")
      compare(Glance.glanceTime(new Date(2026, 9, 30, 12, 30), true), "12:30")
      compare(Glance.glanceTime(new Date(2026, 9, 30, 9, 41), true), "9:41")
      compare(Glance.glanceTime(new Date(2026, 9, 30, 14, 2), false), "14:02")
      compare(Glance.glanceTime(new Date(2026, 9, 30, 0, 5), false), "00:05")
      compare(Glance.barClockFormat('{"bar": {"clockFormat": "h:mm AP"}}'), "h:mm AP")
      compare(Glance.barClockFormat('{"bar": {}}'), "")
      compare(Glance.barClockFormat('{"bar": {"clo'), null)
    }

    // No clockFormat: the bar shows its default, HH:mm, and so does the lock.
    function test_no_bar_format_is_the_bars_default() {
      writeFile(".config/omarchy/shell.json", JSON.stringify({ version: 1, bar: { position: "top" } }))
      settle()
      compare(glance().twelveHour, false)
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
      harness.view.blankSerial += 1
      harness.view.displayDark = true
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
