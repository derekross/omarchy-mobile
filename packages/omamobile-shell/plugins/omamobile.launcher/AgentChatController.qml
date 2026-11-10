// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell.Io

// Owns one ephemeral backend session. Only explicit Send starts model work.
QtObject {
  id: root
  property string provider: ""
  property bool enabled: false
  property bool processWanted: true
  property bool transportEnabled: true // offline tests replace only the transport
  property bool available: false
  property bool installed: false
  property bool capabilityKnown: false
  property string reason: ""
  property bool busy: false
  property bool resetPending: false
  property bool activeAccepted: false
  property string submittedText: ""
  signal accepted(string prompt)
  property string error: ""
  property var messages: []
  property int generation: 0
  property int sequence: 0
  property string activeId: ""
  property string stoppingId: ""
  signal outbound(var message)

  function write(message) {
    outbound(message)
    if (transportEnabled && process.running) process.write(JSON.stringify(message) + "\n")
  }
  function probe() { write({op: "capabilities", provider: provider}) }
  function cancel() {
    var id = activeId
    activeId = "" // reject every late content event before cancellation
    activeAccepted = false
    submittedText = ""
    if (id) { stoppingId = id; busy = true; write({op: "cancel", id: id}) }
    else if (!stoppingId) busy = false
  }
  function reset() {
    cancel()
    ++generation
    messages = []
    error = ""
    resetPending = enabled
    available = false
    capabilityKnown = false
    if (enabled) { processWanted = true; write({op: "reset"}) }
  }
  function shutdown() {
    reset()
    available = false
    installed = false
    capabilityKnown = false
    reason = ""
  }
  function send(prompt) {
    var text = String(prompt || "").trim()
    if (text.length > 8192) { error = "This message is too long. Keep it under 8,192 characters."; return false }
    if (!enabled || busy || resetPending || !available || !installed || !text) return false
    error = ""
    activeId = String(generation) + "-" + String(++sequence)
    submittedText = text
    activeAccepted = false
    busy = true
    write({op: "send", id: activeId, provider: provider, prompt: text})
    return true
  }
  function receive(line) {
    if (typeof line === "string" && line.length > 262144) return
    var event
    try { event = typeof line === "string" ? JSON.parse(line) : line } catch (e) { return }
    if (!event || !enabled) return
    if (event.type === "reset") {
      if (resetPending) { resetPending = false; stoppingId = ""; busy = false; probe() }
      else if (event.reason === "account_changed") messages = []
      return // account-change reset may precede the current request's started
    }
    if (event.type === "capabilities") {
      if (resetPending) return
      if (event.provider !== provider) return
      capabilityKnown = true
      available = event.nativeChat === true && event.installed === true
      installed = event.installed === true
      reason = available ? "" : installed ? "This agent uses its terminal app. Your draft can continue there." : "This agent is not installed. Choose another agent or install its terminal app."
      return
    }
    if (stoppingId && String(event.id) === stoppingId) {
      if (event.type === "done" || event.type === "cancelled" || event.type === "error") { stoppingId = ""; busy = false }
      return
    }
    if (!activeId || String(event.id) !== activeId) return
    if (event.type === "started") {
      if (!activeAccepted) {
        activeAccepted = true
        messages = messages.concat([{role: "user", text: submittedText}, {role: "assistant", text: ""}]).slice(-100)
        accepted(submittedText)
      }
    } else if (event.type === "delta" || event.type === "reply") {
      if (!activeAccepted) return
      var rows = messages.slice()
      if (!rows.length) return
      var previous = rows[rows.length - 1]
      rows[rows.length - 1] = {role: "assistant", text: (event.type === "delta" ? previous.text + String(event.text || "") : String(event.text || "")).slice(0, 128000)}
      messages = rows
    } else if (event.type === "done" || event.type === "cancelled" || event.type === "error") {
      if (event.type === "error") {
        var errors = {
          auth_required: "Sign in using the agent's terminal app, then try again.",
          sandbox_failed: "The agent could not start its required sandbox. Continue in its terminal app.",
          approval_required: "This request needs approval in the agent's terminal app.",
          provider_changed: "The selected agent changed. Your draft was kept; try again.",
          busy: "The agent is still stopping its previous request. Your draft was kept; try again.",
          invalid_request: "The request was not accepted. Your draft was kept.",
          too_large: "This message is too long. Keep it under 8,192 characters."
        }
        error = errors[event.code] || "The agent could not complete this request. Try again or continue in its terminal app."
      }
      busy = false
      activeId = ""
    }
  }
  function ensureStarted() { if (enabled && !processWanted) reset() }
  function transportEnded() {
    if (!enabled) return
    cancel()
    processWanted = false
    stoppingId = ""
    busy = false
    resetPending = false
    available = false
    capabilityKnown = true
    error = "The agent service stopped. Continue in its terminal app or select another agent."
  }
  onProviderChanged: {
    // JSONL is ordered: reset precedes the new capability probe and Send.
    shutdown()
    // reset ACK, not capability arrival, unlocks a provider transition.
  }
  onEnabledChanged: {
    if (enabled) { if (!transportEnabled) probe() }
    else shutdown()
  }
  property Timer capabilityTimeout: Timer {
    interval: 5000
    running: root.enabled && !root.capabilityKnown && !root.resetPending
    onTriggered: {
      root.capabilityKnown = true
      root.available = false
      root.reason = "Native conversation is unavailable. Continue in the agent terminal app."
    }
  }
  property Process process: Process {
    command: ["omamobile-agent-chat", "serve"]
    running: root.enabled && root.transportEnabled && root.processWanted
    stdinEnabled: true
    onStarted: { if (root.resetPending) root.write({op:"reset"}); else root.probe() }
    stdout: SplitParser { onRead: function(line) { root.receive(line) } }
    // stderr may contain CLI diagnostics or account details; never display it.
    stderr: SplitParser { onRead: function(line) {} }
    onExited: function(code, status) { root.transportEnded() }
  }
}
