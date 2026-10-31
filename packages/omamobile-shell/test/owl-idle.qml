// SPDX-License-Identifier: MIT
// OWL widgets stop when nobody can see them (test/owl-idle runs this): the
// real scheduler, widget and view, glued as OwlCell glues them, `shown`
// standing in for Home.qml's pageShown. The host answers every command
// from a fixture and counts them; its clock is the test's (fixture.t), so
// periods and catch-up are exact.
import QtQuick
import QtTest
import "owl"
import "owl/phone.js" as Phone

Item {
  id: top
  width: 400
  height: 300

  QtObject {
    id: fixture
    property real t: 1000
    property int runs: 0
    function now() { return fixture.t }
    function interval(spec) { return spec.every }
    function runSource(widget, spec, arg, headers, done) { fixture.runs++; done({ ok: true, out: "hi", err: "", code: 0 }) }
    function android(widget, kind, done) { done({ value: null }) }
    function act(widget, name, args) {}
    function runInto(widget, command, done) { done("") }
    function stream(widget, spec, arg, onValue) { return null }
    function watch(widget, spec, arg, onValue) { return null }
    function loadState(key) { return null }
    function saveState(key, data) {}
    function report(widget, message) { console.log("owl report: " + message) }
  }

  // Whether its page shows and nothing covers the home screen.
  property bool shown: false
  property int frames: 0

  OwlScheduler { id: scheduler }

  OwlWidget {
    id: owl
    text: 'widget "idle" {\n  meta { owl: 4 }\n  source n = cmd("echo hi") every 2s\n  state ticks = 0\n  every 1s { ticks = ticks + 1 }\n  Text { text: fixed(time, 1) }\n}'
    host: fixture
    active: top.shown
  }

  OwlView {
    id: view
    width: 200
    height: 100
    tree: owl.tree
  }

  // As OwlCell's client, with the fixture's clock for ticks.
  readonly property var client: ({
    key: "idle@w1",
    tick: function(now) { owl.tick(fixture.t) },
    frame: function(t) { owl.frame(t); view.frame++; top.frames++ },
    cost: function() { return view.takeWork() },
    get active() { return owl.active }
  })
  readonly property bool animates: owl.active && view.animating
  onAnimatesChanged: scheduler.setAnimating(top.client, top.animates)
  Component.onCompleted: scheduler.add(top.client)

  function ticks() { return owl.stateValue("ticks") }

  TestCase {
    name: "OwlIdle"
    when: windowShown

    function initTestCase() {
      tryVerify(function() { return owl.tree !== null }, 3000, "the widget loads: " + owl.error)
    }

    function test_1_hidden_runs_nothing() {
      verify(owl.animating, "the widget reads time")
      compare(owl.active, false)
      for (let i = 0; i < 5; i++) { fixture.t += 1; scheduler.tick() }
      compare(fixture.runs, 0, "no command while its page isn't shown")
      compare(top.ticks(), 0, "no `every` while hidden")
      compare(scheduler.framesWanted, false)
      compare(scheduler.framing, false, "no frame clock for a hidden widget")
      wait(300)
      compare(top.frames, 0)
    }

    function test_2_shown_catches_up_and_animates() {
      fixture.t = 1000
      top.shown = true
      compare(fixture.runs, 1, "shown, its source runs at once")
      tryVerify(function() { return scheduler.framing }, 1000, "the frame clock starts")
      fixture.t = 1001
      scheduler.tick()
      compare(top.ticks(), 1, "`every 1s` runs while shown")
      compare(fixture.runs, 1, "a 2 s source waits for its period")
      // 20 fps untouched: about 20 frames a second, never 120.
      const before = top.frames
      wait(1000)
      const n = top.frames - before
      verify(n >= 10 && n <= 22, n + " frames in 1 s at the idle rate")
    }

    function test_3_hidden_again_stops() {
      top.shown = false
      tryVerify(function() { return !scheduler.framing }, 500, "the frame clock stops")
      const frames = top.frames
      fixture.t = 1003; scheduler.tick()
      fixture.t = 1010; scheduler.tick()
      wait(300)
      compare(top.frames, frames, "no frames while hidden")
      compare(fixture.runs, 1, "no command while hidden")
      compare(top.ticks(), 1, "no `every` while hidden")
    }

    function test_4_catch_up_runs_only_what_fell_due() {
      // Hidden from 1001 to 1010: the source's period turned over and the
      // `every` passed (nine times, but it runs once).
      fixture.t = 1010
      top.shown = true
      compare(fixture.runs, 2, "the overdue source runs once")
      compare(top.ticks(), 2, "the overdue `every` runs once")
      top.shown = false
      fixture.t = 1010.5
      top.shown = true
      compare(fixture.runs, 2, "nothing due: nothing runs")
      compare(top.ticks(), 2)
      tryVerify(function() { return scheduler.framing }, 1000)
    }

    function test_5_paused_home_stops_frames_and_slows_the_tick() {
      verify(scheduler.tickInterval <= Phone.CLOCK.tickMs + 5)
      // tickDelay() returns the time to the next boundary, so in the last
      // second of a hidden period the paused delay is legitimately shorter
      // than a tick. Step over that boundary before pausing, or the check
      // below asserts something untrue about one second in every
      // hiddenTickMs (it failed in CI that way).
      if (Phone.tickDelay(Date.now(), true) <= Phone.CLOCK.tickMs + 5)
        wait(Phone.CLOCK.tickMs + 20)
      scheduler.paused = true
      tryVerify(function() { return !scheduler.framing }, 500, "covered or off: no frames")
      verify(scheduler.tickInterval > Phone.CLOCK.tickMs + 5, "the tick slows while paused (" + scheduler.tickInterval + " ms)")
      const frames = top.frames
      wait(300)
      compare(top.frames, frames)
      scheduler.paused = false
      tryVerify(function() { return scheduler.framing }, 1000, "uncovered: frames again")
      verify(scheduler.tickInterval <= Phone.CLOCK.tickMs + 5)
    }

    function test_6_touch_raises_the_rate_for_a_moment() {
      compare(scheduler.frameInterval, Phone.CLOCK.idleMs)
      compare(Phone.CLOCK.idleMs, 50)
      scheduler.touched()
      compare(scheduler.frameInterval, Phone.CLOCK.touchMs)
      verify(Phone.CLOCK.touchMs >= 33, "never faster than 30 fps")
      tryCompare(scheduler, "frameInterval", Phone.CLOCK.idleMs, Phone.CLOCK.touchHoldMs + 2000)
    }

    function test_7_a_slow_widget_gets_every_other_frame() {
      top.shown = false
      tryVerify(function() { return !scheduler.framing }, 500)
      scheduler.paused = true
      let fast = 0, slow = 0
      const quick = { key: "quick", active: true, frame: function() { fast++ }, cost: function() { return 1 } }
      // Its paints take 30 ms, over the 20 ms budget.
      const heavy = { key: "heavy", active: true, frame: function() { slow++ }, cost: function() { return 30 } }
      scheduler.setAnimating(quick, true)
      scheduler.setAnimating(heavy, true)
      for (let i = 0; i < 20; i++) scheduler.frame()
      compare(fast, 20)
      verify(slow >= 9 && slow <= 11, slow + " of 20 frames for the slow widget")
      scheduler.setAnimating(quick, false)
      scheduler.setAnimating(heavy, false)
      scheduler.paused = false
    }
  }
}
