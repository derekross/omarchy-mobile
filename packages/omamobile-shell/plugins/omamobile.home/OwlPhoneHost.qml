// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import "HomeModel.js" as HomeModel
import "owl/phone.js" as Phone
import "owl/terminal.js" as Term

// Everything an OWL widget reaches outside itself goes through here
// (docs/WIDGET-INTEROP-PLAN.md §2.5, §3.3, §3.4): its commands (`bash -c`,
// as the language defines them, under `timeout`, output cut at 64 KiB),
// web requests (GET, timeout, 1 MB), files (1 MB), the android.* sources
// answered from Linux, actions, persisted state and the error log. One
// instance serves the whole home screen; the checks and limits live here.
//
// A widget only gets here once its exact list of commands, URLs and files
// is approved (OwlCell). Commands and requests that use the internet run
// only when that approval turned the internet on.
QtObject {
  id: host

  // Set by Home.qml.
  property var home: null
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omamobile/owl"

  // ---------------------------------------------------------------- policy

  function approvalOf(widget) { return widget && widget.approval ? widget.approval : null }
  function networkAllowed(widget) {
    const a = host.approvalOf(widget)
    return !!a && a.network === true
  }
  // Whether a command reaches the network (curl, wget, ...): then it waits
  // for the internet to be turned on.
  function usesNetwork(command) {
    return Phone.capabilities({ commands: [String(command)], requires: {} }).network
  }

  // The phone's minimum intervals (plan §3.3).
  function interval(spec) { return Phone.sourceLimits(spec, false).every }

  // ---------------------------------------------------------------- sources

  property int streams: 0

  function runSource(widget, spec, arg, headers, done) {
    if (spec.kind === "http") {
      if (!host.networkAllowed(widget)) { done({ error: "the internet is off for this widget" }); return }
      host.get(arg, headers, Phone.sourceLimits(spec, false).timeout, spec, done)
      return
    }
    if (spec.kind === "file") { host.readFile(arg, done); return }
    if (spec.kind === "cmd") {
      if (host.usesNetwork(arg) && !host.networkAllowed(widget)) { done({ error: "the internet is off for this widget" }); return }
      host.command(widget, arg, Phone.sourceLimits(spec, false).timeout, done)
      return
    }
    done({ error: "unknown source " + spec.kind })
  }

  function command(widget, text, seconds, done) {
    const proc = processComponent.createObject(host, {
      command: ["timeout", "-k", "2", String(Math.max(1, Math.min(Phone.LIMITS.timeoutMax, seconds))), "bash", "-c", String(text)]
    })
    proc.done = function(code, out, err) {
      done({ code: code, ok: code === 0, out: out.slice(0, Phone.LIMITS.cmdOutput), err: err.slice(0, Phone.LIMITS.cmdOutput) })
    }
    proc.running = true
  }

  function get(url, headers, seconds, spec, done) {
    const xhr = new XMLHttpRequest()
    let finished = false
    const timer = timerComponent.createObject(host, { interval: seconds * 1000 })
    timer.triggered.connect(function() {
      if (finished) return
      finished = true
      xhr.abort()
      timer.destroy()
      done(spec.status ? { code: 124, ok: false, out: "", err: "timed out" } : { error: "timed out" })
    })
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE || finished) return
      finished = true
      timer.destroy()
      const body = String(xhr.responseText || "")
      if (body.length > Phone.LIMITS.bodyBytes) { done({ error: "the answer is over 1 MB" }); return }
      const ok = xhr.status >= 200 && xhr.status < 300
      done({ code: xhr.status, ok: ok, out: body, err: ok ? "" : "HTTP " + xhr.status })
    }
    xhr.open("GET", url)
    for (const name in headers) xhr.setRequestHeader(name, String(headers[name]))
    timer.start()
    xhr.send()
  }

  function readFile(path, done) {
    const p = String(path).indexOf("~/") === 0 ? Quickshell.env("HOME") + String(path).slice(1) : String(path)
    const reader = fileComponent.createObject(host, { path: p })
    reader.done = function(text) {
      done({ code: 0, ok: true, out: text.slice(0, Phone.LIMITS.bodyBytes), err: "" })
      reader.destroy()
    }
  }

  // ---------------------------------------------------------------- live sources

  // stream(...): one long-running command, a line is a value, restarted 5 s
  // after it exits. At most two across the home screen (plan §3.3).
  property int streamCount: 0
  function stream(widget, spec, text, onLine) {
    if (host.usesNetwork(text) && !host.networkAllowed(widget)) { widget.report(spec.name + ": the internet is off for this widget"); return null }
    if (host.streamCount >= Phone.LIMITS.streams) { widget.report(spec.name + ": two streams already run on the home screen"); return null }
    host.streamCount++
    const proc = streamComponent.createObject(host, { command: ["bash", "-c", String(text)] })
    proc.line = function(l) { onLine(String(l).slice(0, Phone.LIMITS.cmdOutput)) }
    proc.running = true
    return { stop: function() { if (proc.stopped) return; proc.stopped = true; host.streamCount--; proc.running = false; proc.destroy() } }
  }

  // file(...): read now and again whenever it changes (inotify through
  // FileView), at most 1 MB.
  function watch(widget, spec, path, onText) {
    const p = String(path).indexOf("~/") === 0 ? Quickshell.env("HOME") + String(path).slice(1) : String(path)
    const view = watchComponent.createObject(host, { path: p })
    view.changedText = function(t) { onText(String(t).slice(0, Phone.LIMITS.bodyBytes)) }
    return { stop: function() { view.destroy() } }
  }

  // A Terminal node's session (owl/OwlTerminal.qml).
  function terminalFor(widget) {
    return {
      start: function(command, onOutput, onExit) {
        const proc = terminalComponent.createObject(host, { command: Term.argv(command) })
        proc.output = onOutput
        proc.ended = onExit
        proc.running = true
        return { write: function(t) { if (proc.running) proc.write(t) }, stop: function() { proc.running = false; proc.destroy() } }
      }
    }
  }

  // android.*, answered from Linux: battery from the kernel's power supply,
  // volume from wpctl, media from playerctl (MPRIS), modes from the torch LED
  // and mako's modes, system from /proc and df.
  function android(widget, kind, done) {
    const fromCommand = function(text, parse) {
      host.command(widget, text, 5, function(r) { done({ value: parse(String(r.out || "")) }) })
    }
    if (kind === "volume") { fromCommand("wpctl get-volume @DEFAULT_AUDIO_SINK@", Phone.volumeFrom); return }
    if (kind === "media") { fromCommand("playerctl metadata --format " + JSON.stringify(Phone.MEDIA_FORMAT) + " 2>/dev/null", Phone.mediaFrom); return }
    if (kind === "modes") { fromCommand("brightnessctl --device=white:torch get 2>/dev/null || echo; makoctl mode 2>/dev/null", Phone.modesFrom); return }
    if (kind === "system") {
      fromCommand("cat /proc/meminfo; echo '@@'; cat /proc/uptime; echo '@@'; uname -r; echo '@@'; df -B1 --output=size,used / | tail -1; echo '@@@'; " + Phone.DEVICE_COMMAND, function(t) {
        const halves = t.split("@@@\n")
        const parts = halves[0].split("@@\n")
        return Phone.systemFrom(parts[0], parts[1], parts[2], parts[3], Phone.boardFrom(halves[1]))
      })
      return
    }
    if (kind === "battery") { fromCommand(Phone.BATTERY_COMMAND, Phone.batteryFrom); return }
    if (kind === "alarm") { done({ value: { set: false, time: null, app: null } }); return }
    if (kind === "notifications") { done({ value: { available: false, count: 0, items: [] } }); return }
    if (kind === "device") {
      fromCommand(Phone.DEVICE_COMMAND, function(t) {
        const b = Phone.boardFrom(t)
        return { model: b.model, maker: b.maker, android: null, sdk: null, soc: b.soc }
      })
      return
    }
    done({ value: null })
  }

  // ---------------------------------------------------------------- actions

  // One action start per second per widget (plan §3.3).
  property var lastAction: ({})
  function act(widget, name, args) {
    const key = widget ? widget.stateKey : ""
    const now = Date.now()
    if (now - (host.lastAction[key] || 0) < Phone.LIMITS.actionGap * 1000) {
      if (widget) widget.report(name + ": held back (one action a second)")
      return
    }
    host.lastAction[key] = now
    const a = args || []
    const s = function(i) { return a[i] === undefined || a[i] === null ? "" : String(a[i]) }
    switch (name) {
    case "url":
      if (/^https?:\/\//i.test(s(0))) Quickshell.execDetached(HomeModel.urlLaunchArgv(s(0)))
      else if (widget) widget.report("url: only web links open here for now")
      return
    case "terminal":
      Quickshell.execDetached(HomeModel.commandLaunchArgv(["xdg-terminal-exec", "bash", "-c", s(0)]))
      return
    case "app":
      Quickshell.execDetached(HomeModel.commandLaunchArgv(["bash", "-c", s(0)]))
      return
    case "run":
      if (host.usesNetwork(s(0)) && !host.networkAllowed(widget)) { if (widget) widget.report("run: the internet is off for this widget"); return }
      host.command(widget, s(0), Phone.LIMITS.timeoutMax, function() { if (widget) widget.refreshSoon() })
      return
    case "haptic": case "torch":
      // Asked for on the approval sheet; never without it.
      if (!host.approvalOf(widget) || (host.approvalOf(widget).devices || []).indexOf(name) < 0) {
        if (widget) widget.report(name + ": not allowed for this widget")
        return
      }
      host.execute(Phone.actionArgv(name, a))
      return
    case "notify": case "copy": case "volume": case "media":
      host.execute(Phone.actionArgv(name, a))
      return
    case "share":
      Quickshell.execDetached(["wl-copy", "--", s(0)])
      Quickshell.execDetached(["notify-send", "Copied", "Sharing isn't here yet, so it's on the clipboard"])
      return
    case "launcher":
      if (host.home && (s(0) === "store" || s(0) === "drawer")) host.home.showSheet("widgets")
      else if (s(0) === "style" || s(0) === "themes") Quickshell.execDetached(["omarchy-menu", "summon", "style"])
      return
    default:
      // androidApp, notification: no Android here (Waydroid later).
      if (widget) widget.report(name + ": not available on this phone yet")
    }
  }

  function runInto(widget, text, done) {
    if (host.usesNetwork(text) && !host.networkAllowed(widget)) { widget.report("run: the internet is off for this widget"); return }
    host.command(widget, text, Phone.LIMITS.timeoutMax, function(r) { done(String(r.out || "").replace(/\s+$/, "")) })
  }

  // Every phone action starts here: tests replace it to see the argv.
  property var execute: function(argv) { if (argv) Quickshell.execDetached(argv) }

  // ---------------------------------------------------------------- state and errors

  function statePath(key) { return host.stateDir + "/" + key.replace(/[^A-Za-z0-9._-]/g, "_") + ".json" }

  function loadState(key) {
    const view = stateComponent.createObject(host, { path: host.statePath(key) })
    let data = {}
    try { data = JSON.parse(view.text() || "{}") || {} } catch (e) { data = {} }
    view.destroy()
    return data
  }

  function saveState(key, data) {
    host.ensureDir()
    const view = stateComponent.createObject(host, { path: host.statePath(key) })
    view.setText(JSON.stringify(data) + "\n")
    view.destroy()
  }

  // The last 20 problems per widget, for its card and for an agent fixing it
  // (~/.local/state/omamobile/owl/errors/<id>.txt; outside the widget's
  // folder, so writing it doesn't trigger a rescan).
  function report(widget, message) {
    if (!widget || !widget.stateKey) return
    console.warn("omamobile.home: owl " + widget.stateKey + ": " + message)
    host.ensureDir()
    const view = stateComponent.createObject(host, { path: host.stateDir + "/errors/" + widget.stateKey.replace(/[^A-Za-z0-9._-]/g, "_") + ".txt" })
    view.setText(widget.problems.join("\n") + "\n")
    view.destroy()
  }

  property bool madeDir: false
  function ensureDir() {
    if (host.madeDir) return
    host.madeDir = true
    Quickshell.execDetached(["mkdir", "-p", host.stateDir + "/errors"])
  }

  // ---------------------------------------------------------------- parts

  property Component processComponent: Component {
    Process {
      id: proc
      property var done: null
      stdout: StdioCollector { id: out; waitForEnd: true }
      stderr: StdioCollector { id: err; waitForEnd: true }
      onExited: function(code) {
        const finish = proc.done
        proc.done = null
        if (finish) finish(code, String(out.text || ""), String(err.text || ""))
        proc.destroy()
      }
    }
  }

  property Component timerComponent: Component { Timer { } }

  property Component streamComponent: Component {
    Process {
      id: streamProc
      property var line: null
      property bool stopped: false
      stdout: SplitParser { onRead: function(data) { if (streamProc.line) streamProc.line(data) } }
      onExited: if (!streamProc.stopped) restart.restart()
      property Timer restart: Timer { interval: 5000; onTriggered: if (!streamProc.stopped) streamProc.running = true }
    }
  }

  property Component watchComponent: Component {
    FileView {
      id: watched
      property var changedText: null
      watchChanges: true
      printErrors: false
      onFileChanged: reload()
      onLoaded: if (watched.changedText) watched.changedText(watched.text())
      onLoadFailed: if (watched.changedText) watched.changedText("")
    }
  }

  property Component terminalComponent: Component {
    Process {
      id: termProc
      property var output: null
      property var ended: null
      stdinEnabled: true
      stdout: SplitParser {
        splitMarker: ""
        onRead: function(data) { if (termProc.output) termProc.output(data) }
      }
      onExited: if (termProc.ended) termProc.ended()
    }
  }

  property Component fileComponent: Component {
    FileView {
      id: file
      property var done: null
      printErrors: false
      onLoaded: if (file.done) file.done(file.text())
      onLoadFailed: if (file.done) file.done("")
    }
  }

  property Component stateComponent: Component {
    FileView {
      blockLoading: true
      blockWrites: true
      atomicWrites: true
      printErrors: false
    }
  }
}
