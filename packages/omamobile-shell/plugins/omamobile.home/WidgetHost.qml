// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import "HomeModel.js" as HomeModel
import "UserWidgets.js" as UserWidgets

// What a user widget gets as `host` (WIDGETS.md is the contract): who it is,
// colours that read on its card, the system's clock format, its settings and
// a cache that outlive layout edits, and commands with a timeout and a rate
// limit, allowed only when its manifest declares "commands". It is a narrow
// facade: the home screen itself is not handed to widget code.
QtObject {
  id: host

  // Set by Home.qml.
  property var home: null
  property string instanceId: ""
  property string widgetId: ""
  property string dir: ""
  property var capabilities: []
  // Someone can see the widget: its page shows, no app, drawer or recent
  // apps covers the home screen, and the panel is on. Poll only then.
  property bool shown: true

  readonly property color foreground: home ? home.foreground : "white"
  readonly property color dimForeground: home ? home.dimForeground : "white"
  readonly property string timeFormat: home ? home.systemTimeFormat : "HH:mm"
  readonly property bool canRunCommands: capabilities.indexOf("commands") >= 0

  // ---------- settings and cache

  function saveSettings(patch) {
    if (home && instanceId) home.setConfig(instanceId, patch || {})
  }
  function openSettings() {
    if (home && instanceId) home.openSettings(instanceId)
  }
  // Whatever the widget wants back after the page is rebuilt (every layout
  // edit rebuilds it): the last command output, a fetched answer.
  readonly property var cached: home && instanceId ? home.widgetCache("user:" + instanceId) : null
  function setCached(value) {
    if (home && instanceId) home.setWidgetCache("user:" + instanceId, value)
  }

  // ---------- commands

  property var lastStart: 0
  property var running: null
  readonly property bool busy: running !== null

  // run(argv, callback, { timeout: seconds }) runs argv (no shell unless you
  // name one) as you, killed after `timeout` s (default 10, at most 30).
  // One command at a time and one start per 2 s per widget; returns false
  // (and calls nothing) when refused. callback({ code, stdout, stderr,
  // timedOut }); output is cut at 64 KiB.
  function run(argv, callback, options) {
    var verdict = UserWidgets.runCheck(argv, canRunCommands, busy, Date.now() - lastStart)
    if (verdict !== "") {
      console.warn("omamobile.home: widget " + widgetId + ": run refused: " + verdict)
      return false
    }
    var seconds = UserWidgets.runTimeout(options)
    lastStart = Date.now()
    var proc = processComponent.createObject(host, { command: UserWidgets.timeoutArgv(argv, seconds) })
    proc.done = function(result) {
      host.running = null
      if (typeof callback === "function") {
        try { callback(result) } catch (e) { console.warn("omamobile.home: widget " + host.widgetId + ": " + e) }
      }
    }
    running = proc
    proc.running = true
    return true
  }

  // launch(argv): start something detached (an app, a terminal), at most
  // once a second. Also needs "commands".
  property var lastLaunch: 0
  function launch(argv) {
    var verdict = UserWidgets.runCheck(argv, canRunCommands, false, Date.now() - lastLaunch, 1000)
    if (verdict !== "") {
      console.warn("omamobile.home: widget " + widgetId + ": launch refused: " + verdict)
      return false
    }
    lastLaunch = Date.now()
    // Through omamobile-launch: what it opens gets a screen of its own.
    Quickshell.execDetached(HomeModel.commandLaunchArgv(argv))
    return true
  }

  // openUrl(url): open a web link in the browser, on its own screen (the
  // browser's, if it is running). Needs no capability, like a link would;
  // at most once a second.
  property var lastOpen: 0
  function openUrl(url) {
    var text = String(url || "").trim()
    if (!/^https?:\/\/\S+$/i.test(text) || Date.now() - lastOpen < 1000) return false
    lastOpen = Date.now()
    Quickshell.execDetached(HomeModel.urlLaunchArgv(text))
    return true
  }

  property Component processComponent: Component {
    Process {
      id: proc
      property var done: null
      stdout: StdioCollector { id: out; waitForEnd: true }
      stderr: StdioCollector { id: err; waitForEnd: true }
      onExited: function(code) {
        var result = UserWidgets.runResult(code, out.text, err.text)
        var finish = proc.done
        proc.done = null
        if (finish) finish(result)
        proc.destroy()
      }
    }
  }

  // A widget that goes away takes its command with it.
  Component.onDestruction: {
    if (running) { running.done = null; running.running = false }
  }
}
