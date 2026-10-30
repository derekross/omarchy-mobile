// SPDX-License-Identifier: MIT
import QtQuick
import "values.js" as V
import "compiler.js" as Compiler
import "runtime.js" as Runtime

// One live OWL widget: compiles its text, keeps its instance (state,
// source values, history), runs its sources and triggers when the
// scheduler ticks, and hands the render tree to an OwlView.
//
// Everything that leaves the widget goes through `host` (OwlPhoneHost on
// the phone, a fixture host in tests): commands, web requests, files,
// actions, persisted state. So the phone's limits and checks live in one
// place, and this file needs no Quickshell types.
//
// host: runSource(widget, spec, arg, headers, done), android(widget, kind, done),
//       act(widget, name, args), runInto(widget, command, done),
//       loadState(key), saveState(key, data), report(widget, message)
Item {
  id: widget

  property string text: ""
  // Persisted state belongs to the placement (plan §1.4: settings per placement).
  property string stateKey: ""
  property var host: null
  // Theme name -> ARGB.
  property var themeColors: ({})
  // cols, rows, tileWidth, tileHeight, screenWidth, screenHeight, corners, linux.
  property var tileVars: ({})
  // Sources, `every` and the frame clock run only while the widget can be
  // seen: its page shows (a neighbour too while the pages move) and nothing
  // covers the home screen. The host sets it.
  property bool active: false
  // State to start with when nothing is saved yet: { name: value }.
  property var seedState: ({})
  // The approval this widget runs under ({ commands, network }), for the host.
  property var approval: null

  property var program: null
  property var instance: null
  property var tree: null
  property string error: ""
  property var problems: []
  readonly property bool animating: (!!widget.tree && widget.tree.readsTime === true)
    || (widget.screenOpen && !!widget.screenTree && widget.screenTree.readsTime === true)
  // The widget's `screen { }`, shown in place of the tile while open (as
  // our built-ins switch to their longer view), with its title.
  property bool screenOpen: false
  property var screenTree: null
  readonly property bool hasScreen: !!widget.program && !!widget.program.screen

  // ---------------------------------------------------------------- loading

  // Once every binding has its value (stateKey, host), not mid-way.
  onTextChanged: Qt.callLater(widget.load)
  Component.onCompleted: Qt.callLater(widget.load)

  function load() {
    widget.stopLive()
    widget.screenOpen = false
    widget.screenTree = null
    widget.instance = null
    widget.tree = null
    widget.error = ""
    widget.problems = []
    widget.lastRun = ({})
    widget.lastEvery = ({})
    if (!widget.text) return
    try {
      widget.program = Compiler.compile(widget.text)
    } catch (e) {
      widget.program = null
      widget.error = Compiler.formatError(widget.text, e)
      return
    }
    const saved = Object.assign({}, widget.seedState || {}, widget.host && widget.stateKey ? widget.host.loadState(widget.stateKey) || {} : {})
    widget.instance = new Runtime.Instance(widget.program, widget.bridge, saved)
    widget.render()
    if (widget.active) { widget.refresh(); widget.startLive() }
  }

  // What the instance calls back into.
  readonly property var bridge: ({
    theme: function(name) {
      const v = widget.themeColors[name]
      return v === undefined ? null : v
    },
    tile: function(name) { return widget.tileVars ? widget.tileVars[name] : null },
    act: function(name, args) { widget.act(name, args) },
    runInto: function(command, slot) {
      if (widget.host) widget.host.runInto(widget, command, function(out) { if (widget.instance) widget.instance.setState(slot, out) })
    },
    report: function(message) { widget.report(message) },
    changed: function() { widget.changed() },
    allowTrigger: function(i) { return widget.allowTrigger(i) }
  })

  onThemeColorsChanged: if (widget.instance) { widget.instance.invalidate(); widget.render() }
  onTileVarsChanged: if (widget.instance) { widget.instance.invalidate(); widget.render() }
  // Sources keep running while the screen is open, whatever page shows.
  readonly property bool live: widget.active || widget.screenOpen
  // Shown again, it catches up once: what fell due while it was hidden runs
  // now (a source whose period turned over, an `every` that passed), and
  // nothing else; the frame clock picks up at the current `time`.
  onLiveChanged: {
    if (widget.live) { widget.catchUp(); widget.startLive() }
    else widget.stopLive()
  }
  Component.onDestruction: { widget.stopLive(); widget.saveNow() }

  // ---------------------------------------------------------------- drawing

  function changed() {
    widget.saveSoon()
    Qt.callLater(widget.render)
  }

  function render() {
    if (!widget.instance) return
    widget.tree = widget.instance.render(false)
    if (widget.screenOpen) widget.screenTree = widget.instance.render(true)
  }

  function openScreen() {
    if (!widget.hasScreen) { widget.report("screen(): this widget has no screen { }"); return }
    widget.screenOpen = true
    widget.render()
  }
  function closeScreen() {
    widget.screenOpen = false
    widget.screenTree = null
  }

  function frame(seconds) {
    if (!widget.instance) return
    widget.instance.frame(seconds)
    if (widget.animating) widget.render()
  }

  // Handlers from the view: taps, drags, slider and input values.
  function runHandler(handler, args) {
    if (typeof handler !== "function") return
    handler.apply(null, args)
    // After an action, the widget refreshes its sources (the guide).
    widget.refreshSoon()
  }

  // ---------------------------------------------------------------- errors

  function report(message) {
    const line = String(message)
    const next = widget.problems.filter(function(p) { return p !== line })
    next.push(line)
    widget.problems = next.slice(-20)
    if (widget.host) widget.host.report(widget, line)
  }

  // ---------------------------------------------------------------- triggers

  // At most 10 runs of one trigger a second; more is held back and reported.
  property var triggerRuns: ({})
  function allowTrigger(i) {
    const now = Date.now()
    const runs = (widget.triggerRuns[i] || []).filter(function(t) { return now - t < 1000 })
    if (runs.length >= 10) {
      widget.report("a trigger ran more than 10 times in a second and was held back")
      return false
    }
    runs.push(now)
    widget.triggerRuns[i] = runs
    return true
  }

  // ---------------------------------------------------------------- sources

  property var lastRun: ({})
  property var lastEvery: ({})
  property var running: ({})

  // Called by the scheduler about once a second. `at` triggers tick even
  // while the widget is hidden; sources and `every` only while it shows.
  function tick(now) {
    if (!widget.instance) return
    widget.instance.tick(now)
    if (!widget.live) return
    const specs = widget.instance.sources()
    for (let i = 0; i < specs.length; i++) {
      const s = specs[i]
      if (s.kind === "stream" || s.kind === "file") continue
      const every = widget.host ? widget.host.interval(s) : s.every
      const last = widget.lastRun[s.slot]
      // Aligned to the period: `every 1m` turns over on the minute.
      if (last === undefined || Math.floor(now / every) !== Math.floor(last / every)) widget.runSource(s, now)
    }
    const triggers = widget.instance.everyTriggers()
    for (let k = 0; k < triggers.length; k++) {
      const t = triggers[k]
      const before = widget.lastEvery[t.index]
      if (before === undefined) { widget.lastEvery[t.index] = now; continue }
      if (now - before >= t.seconds) {
        widget.lastEvery[t.index] = now
        widget.instance.fire(t.index)
      }
    }
  }

  function refresh() {
    widget.lastRun = ({})
    widget.catchUp()
  }
  // A host may fix the clock (the screenshot harness does).
  function catchUp() { widget.tick(widget.host && widget.host.now ? widget.host.now() : Date.now() / 1000) }
  function refreshSoon() { refreshTimer.restart() }
  Timer { id: refreshTimer; interval: 250; onTriggered: widget.refresh() }

  function runSource(s, now) {
    widget.lastRun[s.slot] = now
    if (s.kind === "clock") {
      widget.instance.setSource(s.slot, Math.floor(now))
      return
    }
    if (!widget.host || widget.running[s.slot]) return
    widget.running[s.slot] = true
    const finish = function(result) {
      widget.running[s.slot] = false
      if (!widget.instance || !result) return
      if (result.error) { widget.report(s.name + ": " + result.error); return }
      if (result.value !== undefined) { widget.instance.setSource(s.slot, V.fromPlain(result.value)); return }
      if (s.status) {
        let out = result.out
        if (s.json) { try { out = V.parseJson(String(out).trim()) } catch (e) { out = null } }
        else out = String(out).replace(/\s+$/, "")
        widget.instance.setSource(s.slot, new Map([["out", out], ["err", String(result.err || "").replace(/\s+$/, "")],
                                                   ["code", result.code], ["ok", !!result.ok]]))
        return
      }
      if (!result.ok && result.err) widget.report(s.name + ": " + String(result.err).split("\n")[0])
      widget.instance.setSource(s.slot, String(result.out === undefined ? "" : result.out))
    }
    if (s.kind.indexOf("android.") === 0) widget.host.android(widget, s.kind.slice(8), finish)
    else widget.host.runSource(widget, s, s.arg(), s.headers(), finish)
  }

  // A state's value by name (undefined: no such state), and setting one as
  // a tap would: what reads it redraws, and it is saved if it persists.
  function stateValue(name) {
    if (!widget.instance) return undefined
    const slot = widget.instance.stateSlot(name)
    return slot < 0 ? undefined : V.toPlain(widget.instance.values[slot])
  }
  function setStateValue(name, value) {
    if (!widget.instance) return
    const slot = widget.instance.stateSlot(name)
    if (slot >= 0) { widget.instance.setState(slot, V.fromPlain(value)); widget.refreshSoon() }
  }

  // ---------------------------------------------------------------- live sources

  // `stream(...)` (a line is a value) and `file(...)` (read again when it
  // changes): started while the widget shows, stopped when it doesn't.
  property var liveHandles: []
  function startLive() {
    if (!widget.instance || !widget.host || widget.liveHandles.length) return
    const specs = widget.instance.sources()
    const handles = []
    for (let i = 0; i < specs.length; i++) {
      const s = specs[i]
      if (s.kind !== "stream" && s.kind !== "file") continue
      const slot = s.slot
      const onValue = function(text) { if (widget.instance) widget.instance.setSource(slot, String(text)) }
      const h = s.kind === "stream" ? widget.host.stream(widget, s, s.arg(), onValue)
        : widget.host.watch(widget, s, s.arg(), onValue)
      if (h) handles.push(h)
    }
    widget.liveHandles = handles
  }
  function stopLive() {
    const handles = widget.liveHandles
    widget.liveHandles = []
    for (let i = 0; i < handles.length; i++) handles[i].stop()
  }

  // ---------------------------------------------------------------- actions

  function act(name, args) {
    if (name === "refresh") { widget.refreshSoon(); return }
    if (name === "screen") { widget.openScreen(); return }
    if (name === "close") { widget.closeScreen(); return }
    if (widget.host) widget.host.act(widget, name, args)
  }

  // ---------------------------------------------------------------- persisted state

  function saveSoon() { if (widget.stateKey) saveTimer.restart() }
  Timer {
    id: saveTimer
    interval: 1000
    onTriggered: if (widget.instance && widget.host && widget.stateKey) widget.host.saveState(widget.stateKey, widget.instance.persisted())
  }
  function saveNow() {
    if (widget.instance && widget.host && widget.stateKey && saveTimer.running) widget.host.saveState(widget.stateKey, widget.instance.persisted())
  }
}
