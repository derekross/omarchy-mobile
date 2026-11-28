// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "TextSizeModel.js" as Model

// The Text size page: one size for the whole phone, as a phone's Larger
// Text setting. Five rows, Smaller to Largest, each label drawn at its own
// size; a preview line at the chosen size; and a note on what changes now
// and what when reopened. Opened from Setup > Text size in Omarchy's menu,
// or `omarchy-shell shell summon omamobile.textsize '{}'`.
//
// A tap runs `omamobile-text-size set STEP` (bin/), which sets the shell's
// base size (the page itself grows or shrinks with it), GTK's text scaling,
// the terminal's font size and Chromium's and Grok Bot's scale. Taps while
// one runs are kept, and the last one runs next.
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  property bool opened: false
  property var steps: Model.FALLBACK_STEPS
  // The step the command reports, and the one tapped (shown at once).
  property string current: "default"
  property string pending: ""
  property string queued: ""
  property bool failed: false

  readonly property string shown: pending !== "" ? pending : current
  readonly property string pluginId: (manifest && manifest.id) || "omamobile.textsize"

  // ---------------------------------------------------------------- host API

  function open(payloadJson) {
    opened = true
    failed = false
    refresh()
  }

  function close() {
    opened = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
  }

  // Back: this page closes and Omarchy's Setup menu, which it was opened
  // from, comes back.
  function goBack() {
    dismiss()
    Quickshell.execDetached(["omarchy-menu", "summon", "setup"])
  }

  // `shell call omamobile.textsize snapshot ''`
  function snapshot() {
    return JSON.stringify({ opened: opened, step: shown, steps: steps.map(function(s) { return s.name }) })
  }

  // ---------------------------------------------------------------- actions

  function refresh() {
    if (!getProc.running) getProc.running = true
  }

  function choose(name) {
    failed = false
    pending = name
    if (setProc.running) { queued = name; return }
    setProc.command = Model.setArgv(name)
    setProc.running = true
  }

  Process {
    id: getProc
    command: Model.GET_ARGV
    stdout: StdioCollector { id: getOut; waitForEnd: true }
    onExited: {
      var parsed = Model.parse(getOut.text)
      if (parsed) {
        root.steps = parsed.steps
        root.current = parsed.step
      }
    }
  }

  Process {
    id: setProc
    onExited: function(exitCode) {
      if (exitCode !== 0) root.failed = true
      if (root.queued !== "") {
        var next = root.queued
        root.queued = ""
        setProc.command = Model.setArgv(next)
        setProc.running = true
        return
      }
      root.pending = ""
      root.refresh()
    }
  }

  // ---------------------------------------------------------------- surface

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  PanelWindow {
    id: sheetWindow

    visible: root.opened || root.reveal > 0
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-textsize"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    TextSizeSheet {
      anchors.fill: parent
      steps: root.steps
      shown: root.shown
      failed: root.failed
      opened: root.opened
      reveal: root.reveal
      onChosen: function(name) { root.choose(name) }
      onBack: root.goBack()
      onDismissed: root.dismiss()
    }
  }
}
