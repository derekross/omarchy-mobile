// SPDX-License-Identifier: MIT
import QtQuick
import "phone.js" as Phone

// One clock for every OWL widget on the home screen (plan §2.6): a tick on
// each second boundary for sources, `every` and `at` triggers, and a frame
// clock that runs only while a shown widget animates and the home screen
// isn't paused (covered by an app, the drawer or the switcher, or off).
// Frames come at 20 fps, 30 while a widget is touched (touched()), and a
// widget whose frames cost more than the budget gets every other one
// (Phone.CLOCK). While paused, the tick slows to every 10 s: only `at`
// triggers run then, and resuming ticks at once.
// Widgets register with add() and leave with remove().
Item {
  id: scheduler

  property bool paused: false
  property var clients: []
  property var animating: ({})
  readonly property bool framesWanted: Object.keys(scheduler.animating).length > 0
  // The frame clock is running (tests and the status read it).
  readonly property bool framing: frames.running
  // Milliseconds to the next tick (tests read it).
  readonly property int tickInterval: seconds.interval
  // `time` for animations: seconds since the shell started (small numbers
  // keep sin() and friends precise).
  readonly property real epoch: Date.now() / 1000
  property int frameCount: 0
  // A finger is on a widget, or was in the last 3 s: frames at 30 fps.
  property bool touchActive: false
  readonly property int frameInterval: Phone.frameInterval(scheduler.touchActive)

  // A client is { tick(now), frame(time), cost(), active, key }; cost()
  // returns the milliseconds its last frame took outside frame() (layout,
  // Canvas paints) and starts counting again.
  function add(client) {
    if (scheduler.clients.indexOf(client) < 0) scheduler.clients = scheduler.clients.concat([client])
  }
  function remove(client) {
    scheduler.clients = scheduler.clients.filter(function(c) { return c !== client })
    scheduler.setAnimating(client, false)
  }
  function setAnimating(client, on) {
    const id = String(client.key)
    if (!!scheduler.animating[id] === on) return
    const next = Object.assign({}, scheduler.animating)
    if (on) next[id] = client
    else delete next[id]
    scheduler.animating = next
    if (!on) { delete scheduler.slow[id]; delete scheduler.spent[id] }
  }
  // A tap, drag or value from a widget.
  function touched() {
    scheduler.touchActive = true
    touchHold.restart()
  }
  Timer { id: touchHold; interval: Phone.CLOCK.touchHoldMs; onTriggered: scheduler.touchActive = false }

  // Resuming runs a tick at once, so nothing shows hours-old data.
  onPausedChanged: {
    if (!scheduler.paused) scheduler.tick()
    scheduler.armTick()
  }

  function tick() {
    const now = Date.now() / 1000
    const list = scheduler.clients
    for (let i = 0; i < list.length; i++) {
      try { list[i].tick(now, scheduler.paused) } catch (e) { console.warn("owl: tick: " + e) }
    }
  }
  function armTick() {
    seconds.interval = Phone.tickDelay(Date.now(), scheduler.paused)
    seconds.restart()
  }

  Timer {
    id: seconds
    running: true
    // Restarted on the next boundary each time.
    interval: Phone.tickDelay(Date.now(), scheduler.paused)
    onTriggered: {
      scheduler.tick()
      scheduler.armTick()
    }
  }

  // Per client: drawing every other frame, and what its last frame() took.
  property var slow: ({})
  property var spent: ({})
  Timer {
    id: frames
    interval: scheduler.frameInterval
    repeat: true
    running: !scheduler.paused && scheduler.framesWanted
    onTriggered: scheduler.frame()
  }
  function frame() {
    scheduler.frameCount++
    const t = Date.now() / 1000 - scheduler.epoch
    for (const id in scheduler.animating) {
      const client = scheduler.animating[id]
      if (!client.active) continue
      // The last frame's whole cost: its frame() and what came after it
      // (layout, Canvas paints), once that has happened.
      const after = typeof client.cost === "function" ? client.cost() : 0
      if (scheduler.spent[id] !== undefined) {
        scheduler.slow[id] = Phone.frameSlow(scheduler.spent[id] + after)
        delete scheduler.spent[id]
      }
      if (Phone.frameSkipped(scheduler.slow[id], scheduler.frameCount)) continue
      const began = Date.now()
      try { client.frame(t) } catch (e) { console.warn("owl: frame: " + e) }
      scheduler.spent[id] = Date.now() - began
    }
  }
}
