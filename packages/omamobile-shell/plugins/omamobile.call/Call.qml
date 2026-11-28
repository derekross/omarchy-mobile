// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "CallModel.js" as CallModel

// Calls in the shell (TELEPHONY-APPS-PLAN §7.1): the incoming-call card
// over the lock screen, a heads-up card on an unlocked phone, and the
// in-call controls over the lock. omatel's agent owns the calls;
// bin/omamobile-call-watch reports them (and lights the screen when one
// rings), and a tap here asks the agent through busctl (CallModel's argv).
//
// Two windows on the overlay layer, both allowed over the lock by
// hypr/phone.lua (above_lock 2): "omamobile-call", full screen, for a
// ringing call on a locked phone and the in-call controls; and
// "omamobile-call-top", a strip at the top, for the heads-up card and the
// folded in-call card. Over the lock they offer call actions only: the
// Phone app opens only on an unlocked phone, and the lock stays put.
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  property var callState: CallModel.emptyState()
  property bool locked: false
  // The in-call card folded to the top strip, for this call.
  property bool folded: false
  property string foldedFor: ""
  property double nowMs: Date.now()
  // The lock's "Emergency call" button (Omarchy patch 0014) asked for the
  // warning; a ringing or live call takes the screen over it.
  property bool showEmergency: false

  readonly property string mode: CallModel.mode(callState, locked, folded)
  readonly property var ringingCall: CallModel.ringing(callState.calls)
  readonly property var currentCall: CallModel.current(callState.calls)
  readonly property var shownCall: ringingCall || currentCall
  readonly property bool anyCall: !!shownCall

  onCurrentCallChanged: {
    if (!currentCall || currentCall.id !== foldedFor) folded = false
  }

  // ---------------------------------------------------------------- host API

  function open(payloadJson) {}
  function close() {}

  // `shell call omamobile.call emergency ''`: from the lock's "Emergency
  // call" button. Until emergency calling has passed its test on a carrier
  // (TELEPHONY-APPS-PLAN §3.3), the warning, never a dialpad.
  function emergency() {
    showEmergency = true
    return "ok"
  }

  // `shell call omamobile.call state ''`, for tests and debugging (no
  // numbers or names: only what's shown and why).
  function state() {
    return JSON.stringify({ mode: mode, locked: locked, folded: folded, emergency: showEmergency, agent: callState.agent,
                            calls: callState.calls.map(function(c) { return c.state }), watcher: watch.running })
  }

  // ---------------------------------------------------------------- requests

  function run(argv) { Quickshell.execDetached(argv) }

  function answer() {
    var c = ringingCall
    if (!c) return
    run(CallModel.answerArgv(c.id))
    // Unlocked: the Phone app has the full in-call screen.
    if (!locked) run(CallModel.openPhoneArgv(null))
  }
  function decline() { if (ringingCall) run(CallModel.declineArgv(ringingCall.id)) }
  function hangup() { run(CallModel.hangupArgv(currentCall ? currentCall.id : "")) }
  function toggleMute() { run(CallModel.muteArgv(!callState.muted)) }
  function toggleSpeaker() { run(CallModel.routeArgv(callState.route === "speaker" ? "earpiece" : "speaker")) }
  function reply(text) {
    var c = ringingCall
    if (!c || !c.number) return
    run(CallModel.replyArgv(c.number, text))
    run(CallModel.declineArgv(c.id))
  }
  function openPhone() { if (!locked) run(CallModel.openPhoneArgv(shownCall)) }
  function fold() { folded = true; foldedFor = currentCall ? currentCall.id : "" }
  function unfold() { folded = false }

  // ---------------------------------------------------------------- inputs

  Process {
    id: watch
    command: ["omamobile-shell-child", "omamobile-call-watch"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var s = CallModel.parseLine(line)
        if (!s) return
        root.callState = s
        if (root.anyCall) lockCheck.check()
      }
    }
    onExited: {
      root.callState = CallModel.emptyState()
      restart.restart()
    }
  }

  Timer {
    id: restart
    interval: 3000
    onTriggered: watch.running = true
  }

  // The lock's state, asked afresh while a call is shown (the lock service
  // isn't one a third-party plugin can bind to).
  Process {
    id: lockCheck
    command: ["omarchy-shell", "lock", "isLocked"]
    function check() { if (!running) running = true }
    stdout: SplitParser {
      onRead: function(line) { root.locked = String(line).trim() === "true" }
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.anyCall
    triggeredOnStart: true
    onTriggered: {
      root.nowMs = Date.now()
      lockCheck.check()
    }
  }

  // ---------------------------------------------------------------- surfaces

  PanelWindow {
    id: fullWindow
    visible: root.mode === "incoming" || root.mode === "in-call" || root.showEmergency
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "omamobile-call"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    EmergencyInfo {
      anchors.fill: parent
      visible: root.showEmergency && root.mode !== "incoming" && root.mode !== "in-call"
      onClosed: root.showEmergency = false
    }

    CallCard {
      anchors.fill: parent
      visible: root.mode === "incoming" || root.mode === "in-call"
      call: root.shownCall
      mode: root.mode === "in-call" ? "in-call" : "incoming"
      nowMs: root.nowMs
      muted: root.callState.muted
      route: root.callState.route
      replies: root.callState.replies
      onAnswer: root.answer()
      onDecline: root.decline()
      onHangup: root.hangup()
      onToggleMute: root.toggleMute()
      onToggleSpeaker: root.toggleSpeaker()
      onReply: function(text) { root.reply(text) }
      onFold: root.fold()
    }
  }

  PanelWindow {
    id: topWindow
    visible: root.mode === "heads-up" || root.mode === "in-call-mini"
    anchors { top: true; left: true; right: true }
    implicitHeight: headsUp.implicitHeight
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "omamobile-call-top"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    HeadsUp {
      id: headsUp
      anchors.left: parent.left
      anchors.right: parent.right
      call: root.mode === "in-call-mini" ? root.currentCall : root.ringingCall
      mode: root.mode === "in-call-mini" ? "mini" : "heads-up"
      nowMs: root.nowMs
      onAnswer: root.answer()
      onDecline: root.decline()
      onHangup: root.hangup()
      onOpen: root.mode === "in-call-mini" ? root.unfold() : root.openPhone()
    }
  }
}
