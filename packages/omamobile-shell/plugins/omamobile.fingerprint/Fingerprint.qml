// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "SensorModel.js" as SensorModel

// The under-display fingerprint sensor in the shell, after Android.
//
// * The target: while a fingerprint is enrolled or checked (the lock
//   screen's fingerprint conversation, fprintd-verify, sudo through
//   pam_fprintd), a faint fingerprint sits exactly over the sensor, and
//   touches inside its circle stay away from the shell.
// * The desktop guard: while any such operation runs, the desktop itself
//   (the wallpaper, under every window) takes no touches, so a finger held
//   on the sensor can't open its long-press menu.
// * Enrollment: a full-screen flow (intro, live progress around the sensor,
//   hints, a second stage for the finger's edges, success or a readable
//   error), opened from the Fingerprint tile in quick settings, Omarchy's
//   Setup > Security > Fingerprint, or
//   `omarchy-shell shell summon omamobile.fingerprint '{"page":"enroll"}'`.
//
// Data. omamobile-fp-bridge (omamobile-fingerprint) has one client, fprintd,
// which keeps the user's prints. So enrollment goes through fprintd's D-Bus
// API (bin/omamobile-fp-enroll: Claim, EnrollStart, EnrollStatus, polkit
// asks first), and the finer detail fprintd doesn't carry comes from the
// bridge's state file, /run/omamobile-fp-ui/state.json: the operation, a
// finger on the sensor, the sensor circle in panel pixels, the HAL's last
// acquired hint and the samples still needed. The panel lights the circle
// itself while a finger is down (LHBM), so the glyph steps aside then; that
// follows the bridge's touch state, not LHBM.
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "omamobile.fingerprint"
  // OMAMOBILE_FP_UI_STATE points the desktop harness at a fake bridge.
  readonly property string statePath: Quickshell.env("OMAMOBILE_FP_UI_STATE") || "/run/omamobile-fp-ui/state.json"

  // ---------------------------------------------------------------- lifecycle

  // `shell summon omamobile.fingerprint '{"page":"enroll"}'` (any payload)
  // opens enrollment. The screen keeps its own lifecycle (Cancel, Done), so
  // the host is told we're closed again at once, as quick settings does
  // for its pages.
  function open(payloadJson) {
    showEnroll()
    Qt.callLater(function() {
      if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    })
  }

  // Host-initiated close (`shell hide`): the screen stays until its own
  // buttons end it.
  function close() {}

  // `shell call omamobile.fingerprint state ''` for scripts and tests.
  function state() {
    return JSON.stringify({
      op: sensor ? sensor.op : "none",
      finger: sensor ? sensor.finger : false,
      screen: panelScreen ? String(panelScreen.name) + " " + screenWidth + "x" + screenHeight : "none",
      screens: Quickshell.screens.length,
      spot: spot,
      transform: outputTransform,
      target: target.visible,
      osk: oskOpen,
      oskWatch: oskWatch.running,
      lastLayerEvent: lastLayerEvent,
      contact: contactDown,
      holdGuard: holdGuard,
      inhibit: inhibitPath,
      guard: guard.visible,
      enroll: screenOpen ? page : "closed",
      authPending: authPending,
      enrollWindow: enrollWindow.visible,
      helper: enrollProc.running || deleteProc.running,
      progress: progress,
      hint: hint,
      fingers: enrolledFingers
    })
  }

  // ---------------------------------------------------------------- the bridge's state

  property var sensor: null
  readonly property bool active: SensorModel.active(sensor)
  readonly property bool fingerDown: !!sensor && sensor.finger

  // Shown while active, and for a moment after: between a failed match and
  // fprintd's next attempt the bridge is idle for a few hundred ms, and the
  // target should not blink.
  property bool shown: false
  onActiveChanged: {
    if (active) {
      lingerTimer.stop()
      releaseTimer.stop()
      shown = true
      Hyprland.refreshMonitors()
    } else {
      lingerTimer.restart()
      // The finger that unlocked the phone is often still down when the lock
      // goes away, and the same touch went on as a long press on the
      // wallpaper. Hold the desktop guard until it lifts.
      holdGuard = true
      holdMaxTimer.restart()
      if (!contactDown) releaseTimer.restart()
    }
  }

  // The bridge's "contact": a touch that reached the sensor is still down.
  readonly property bool contactDown: !!sensor && sensor.contact === true
  property bool holdGuard: false
  onContactDownChanged: {
    if (!holdGuard) return
    if (contactDown) releaseTimer.stop()
    else releaseTimer.restart()
  }

  // Released this long after the finger lifts (an older bridge that does
  // not report contact: after the operation ends).
  Timer {
    id: releaseTimer
    interval: root.sensor && root.sensor.contact === null ? 2000 : 500
    onTriggered: { root.holdGuard = false; holdMaxTimer.stop() }
  }

  // Never stuck: a hold ends after this, whatever the state file says.
  Timer {
    id: holdMaxTimer
    interval: 10000
    onTriggered: { root.holdGuard = false; releaseTimer.stop() }
  }

  // The on-screen keyboard (squeekboard's "osk" layer) covers the sensor:
  // while it is up the target steps aside, as Android hides its icon behind
  // the bouncer's keyboard (on the lock, a password user types on it while
  // the fingerprint conversation runs).
  //
  // Visibility comes from squeekboard itself (sm.puri.OSK0's Visible on the
  // session bus, through bin/omamobile-osk-watch): Hyprland's layer events
  // did not reach the plugin while the session was locked, which is when a
  // password is typed over the sensor. They are kept for the state call only.
  property bool oskOpen: false
  property string lastLayerEvent: ""
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && (event.name === "openlayer" || event.name === "closelayer"))
        root.lastLayerEvent = event.name + " " + String(event.data || "")
    }
  }

  Process {
    id: oskWatch
    command: ["omamobile-osk-watch"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var words = String(line).trim().split(" ")
        if (words[0] === "visible") root.oskOpen = words[1] === "true"
      }
    }
    onExited: {
      root.oskOpen = false
      oskWatchRestart.restart()
    }
  }

  // The watcher should never end; if it does, start it again.
  Timer {
    id: oskWatchRestart
    interval: 3000
    onTriggered: oskWatch.running = true
  }

  // ...and the bridge must not take its keys there for a finger: it reads
  // the touchscreen itself. While the keyboard is up this keeps a file fresh
  // in the bridge's inhibit directory (omamobile-fp-chroot makes it, sticky
  // and world-writable); the bridge ignores files older than 15 s, so a
  // shell that dies cannot leave fingerprint captures off.
  readonly property string inhibitPath: statePath.replace(/[^\/]*$/, "") + "inhibit/osk-"
    + (Quickshell.env("USER") || "user")
  onOskOpenChanged: {
    if (oskOpen) Quickshell.execDetached(["touch", inhibitPath])
    else Quickshell.execDetached(["rm", "-f", inhibitPath])
  }
  Timer {
    interval: 5000
    repeat: true
    running: root.oskOpen
    onTriggered: Quickshell.execDetached(["touch", root.inhibitPath])
  }
  Component.onCompleted: Quickshell.execDetached(["rm", "-f", inhibitPath])

  Timer {
    id: lingerTimer
    interval: 900
    onTriggered: root.shown = root.active
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.sensor = SensorModel.parse(text())
    // The stack is not running, or it stopped: no capture.
    onLoadFailed: root.sensor = null
  }

  // The file is replaced with rename(2) on every change; a quick re-read
  // while anything shows makes sure a missed change cannot leave it stale.
  Timer {
    interval: root.screenOpen ? 500 : 2000
    repeat: true
    running: root.shown || root.screenOpen
    onTriggered: stateFile.reload()
  }

  // ---------------------------------------------------------------- geometry

  // The phone's own panel (DSI), else the first screen of the panel's shape
  // (a desktop harness may also have a fallback output), else the first.
  readonly property var panelScreen: {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name).indexOf("DSI") === 0) return screens[i]
    for (var j = 0; j < screens.length; j++) {
      var w = screens[j].width, h = screens[j].height
      if (SensorModel.place(stockSensor, w > h ? 1 : 0, w, h)) return screens[j]
    }
    return screens.length > 0 ? screens[0] : null
  }

  // Hyprland's transform for that screen (omamobile-autorotate changes it).
  readonly property var monitor: panelScreen ? Hyprland.monitorFor(panelScreen) : null
  readonly property int outputTransform: {
    var ipc = monitor ? monitor.lastIpcObject : null
    return ipc && ipc.transform !== undefined ? Number(ipc.transform) : 0
  }
  readonly property real screenWidth: panelScreen ? panelScreen.width : 0
  readonly property real screenHeight: panelScreen ? panelScreen.height : 0
  onScreenWidthChanged: Hyprland.refreshMonitors()
  onScreenHeightChanged: Hyprland.refreshMonitors()

  // Before the bridge has run once there is no state file; enrollment still
  // needs the circle, so it falls back to stock cheetah's sensor.
  readonly property var stockSensor: ({ x: 717, y: 2360, r: 121, w: 1440, h: 3120 })
  readonly property var spot: SensorModel.place(sensor || stockSensor, outputTransform, screenWidth, screenHeight)
  // The bridge starts a capture for a touch within 1.5 radii.
  readonly property real hitRadius: spot ? Math.ceil(spot.r * 1.5) : 0

  readonly property color ink: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property string fingerprintGlyph: String.fromCodePoint(0xF0237)   // nf-md-fingerprint, as Omarchy's lock
  readonly property string checkGlyph: String.fromCodePoint(0xF012C)         // nf-md-check
  readonly property string alertGlyph: String.fromCodePoint(0xF0026)         // nf-md-alert

  // ---------------------------------------------------------------- the target

  PanelWindow {
    id: target

    screen: root.panelScreen
    visible: root.shown && root.spot !== null && !root.screenOpen && !root.oskOpen
    anchors { top: true; left: true }
    margins {
      left: root.spot ? Math.round(root.spot.x - root.hitRadius) : 0
      top: root.spot ? Math.round(root.spot.y - root.hitRadius) : 0
    }
    implicitWidth: Math.max(1, root.hitRadius * 2)
    implicitHeight: Math.max(1, root.hitRadius * 2)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // hypr/phone.lua draws this namespace above the lock screen (above_lock
    // 1: drawn, but no input there, so the lock's own keys keep working).
    WlrLayershell.namespace: "omamobile-fingerprint"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Touches inside the circle land here and go no further.
    mask: Region { item: hitArea; shape: RegionShape.Ellipse }

    Item {
      id: hitArea
      anchors.fill: parent

      // Accept the press so nothing in the shell sees it; the bridge reads
      // the touchscreen itself.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        preventStealing: true
      }

      Item {
        anchors.centerIn: parent
        width: root.spot ? root.spot.r * 2 : 0
        height: width
        // faint, as Android's hint
        opacity: root.active && !root.fingerDown ? 0.45 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: Qt.rgba(0, 0, 0, 0.25)
          border.width: Math.max(1, Math.round(width / 40))
          border.color: root.ink
        }

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.fingerprintGlyph
          color: root.ink
          font.family: Style.font.family
          font.pixelSize: Math.round(parent.width * 0.62)
        }
      }
    }
  }

  // ---------------------------------------------------------------- the desktop guard

  // The desktop's long-press menu belongs to the wallpaper (the background
  // layer). A transparent surface on the bottom layer, just above it, in the
  // area the bar and dock leave free, takes those touches while an operation
  // runs. Windows, the bar, the dock and panels sit above it and work as
  // usual.
  PanelWindow {
    id: guard

    screen: root.panelScreen
    visible: (root.shown || root.holdGuard) && !root.screenOpen
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-fingerprint-guard"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Item {
      anchors.fill: parent
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        preventStealing: true
      }
    }
  }

  // ---------------------------------------------------------------- enrollment: state

  property bool screenOpen: false
  // intro, waiting (polkit, claim), enrolling, done, error
  property string page: "intro"
  property var enrolledFingers: []
  property bool fingersKnown: false
  property bool sensorAvailable: true
  property string addedFinger: ""
  property string failure: ""
  property bool userCanceled: false
  property bool deleting: false
  // fprintd's Claim is waiting on polkit: Omarchy's password prompt and the
  // on-screen keyboard are up, and the keyboard is drawn under an overlay
  // layer, so the enrollment screen steps aside until the helper says the
  // claim is through (or failed).
  property bool authPending: false

  // progress: the bridge's samples-left count when it has one, else
  // fprintd's stages (our driver reports 20, the HAL needs fewer samples)
  property int baseSeq: 0
  property int firstRemaining: -1
  property int secondRemaining: -1
  property int stagesPassed: 0
  property int stagesTotal: 20
  property int hintSeq: -1
  property string hint: ""
  property bool gotDone: false

  readonly property real progress: page === "done" ? 1
    : firstRemaining >= 0 && sensor && sensor.remaining >= 0
      ? SensorModel.enrollProgress(sensor.remaining, firstRemaining, secondRemaining)
      : stagesTotal > 0 ? Math.min(1, stagesPassed / stagesTotal) : 0
  readonly property bool touchedOnce: firstRemaining >= 0 || stagesPassed > 0
  readonly property var stageText: SensorModel.enrollText(touchedOnce, progress)

  function showEnroll() {
    if (screenOpen && (page === "waiting" || page === "enrolling")) return
    screenOpen = true
    page = "intro"
    failure = ""
    refreshFingers()
    Hyprland.refreshMonitors()
  }

  function refreshFingers() {
    if (!listProc.running) listProc.running = true
  }

  property bool startPending: false

  function startEnroll() {
    // "Add another" right after a success: the last helper is still
    // releasing the device; start once it has gone.
    if (enrollProc.running) { startPending = true; return }
    startPending = false
    page = "waiting"
    authPending = true
    failure = ""
    hint = ""
    userCanceled = false
    gotDone = false
    addedFinger = ""
    baseSeq = sensor ? sensor.seq : 0
    hintSeq = baseSeq
    firstRemaining = -1
    secondRemaining = -1
    stagesPassed = 0
    enrollProc.running = true
  }

  function cancelEnroll() {
    userCanceled = true
    if (enrollProc.running) {
      enrollProc.write(JSON.stringify({ cmd: "cancel" }) + "\n")
      killTimer.restart()
    } else {
      closeScreen()
    }
  }

  // A helper that doesn't answer a cancel within 2 s is stopped (SIGTERM;
  // it cancels on that too, even while polkit is still asking).
  Timer {
    id: killTimer
    interval: 2000
    onTriggered: {
      if (enrollProc.running) enrollProc.running = false
      if (deleteProc.running) deleteProc.running = false
    }
  }

  // Back (omamobile.back's BackLink.js): the screen never takes the keyboard,
  // so Escape went to the app under it. Back is the screen's own way out:
  // Done after an enrollment, Cancel everywhere else (which stops one that
  // is running).
  function back() {
    if (!screenOpen) return false
    if (page === "done") closeScreen()
    else cancelEnroll()
    return true
  }

  Loader {
    source: Qt.resolvedUrl("../omamobile.back/BackLinkClient.qml")
    onLoaded: {
      item.name = "fingerprint setup"
      item.handler = function() { return root.back() }
      // Not while polkit asks: its prompt has the keyboard and takes Escape.
      item.active = Qt.binding(function() { return root.screenOpen && !root.authPending })
    }
  }

  function closeScreen() {
    if (enrollProc.running) {
      userCanceled = true
      enrollProc.write(JSON.stringify({ cmd: "cancel" }) + "\n")
      killTimer.restart()
    }
    startPending = false
    authPending = false
    screenOpen = false
    page = "intro"
  }

  function fail(text) {
    failure = text
    page = "error"
  }

  function helperEvent(line) {
    var ev = null
    try { ev = JSON.parse(line) } catch (e) { return }
    if (!ev || typeof ev.event !== "string") return
    if (ev.event === "claimed") {
      authPending = false
    } else if (ev.event === "fingers") {
      enrolledFingers = Array.isArray(ev.fingers) ? ev.fingers : []
      fingersKnown = true
      sensorAvailable = true
      if (ev.stages > 0) stagesTotal = ev.stages
    } else if (ev.event === "started") {
      authPending = false
      addedFinger = String(ev.finger || "")
      page = "enrolling"
    } else if (ev.event === "status") {
      if (ev.result === "enroll-stage-passed") {
        stagesPassed++
        hint = ""
      } else if (SensorModel.retryHint(ev.result) && !(sensor && sensor.seq > hintSeq)) {
        // the bridge's own hint is finer; this one only when it has none
        hint = SensorModel.retryHint(ev.result)
      }
    } else if (ev.event === "done") {
      gotDone = true
      authPending = false
      if (ev.ok) {
        page = "done"
        refreshFingers()
      } else if (userCanceled) {
        screenOpen = false
        page = "intro"
      } else {
        fail(SensorModel.failureText(ev.result, "", sensor, baseSeq))
      }
    } else if (ev.event === "error") {
      gotDone = true
      authPending = false
      if (ev.kind === "no-device") sensorAvailable = false
      if (userCanceled) { screenOpen = false; page = "intro" }
      else fail(SensorModel.failureText("", ev.kind, sensor, baseSeq))
    } else if (ev.event === "deleted") {
      authPending = false
      enrolledFingers = []
    }
  }

  // The bridge's events during an enrollment: the samples left, and the
  // HAL's hint for the last touch.
  onSensorChanged: {
    if (!screenOpen || page !== "enrolling" || !sensor || sensor.seq <= baseSeq) return
    if (sensor.remaining >= 0) {
      if (firstRemaining < 0) firstRemaining = sensor.remaining
      else if (secondRemaining < 0 && sensor.remaining < firstRemaining) secondRemaining = sensor.remaining
    }
    if (sensor.seq !== hintSeq) {
      hintSeq = sensor.seq
      if (sensor.acquired === 1) hint = ""          // GOOD: the stage's own words
      else {
        var h = SensorModel.acquiredHint(sensor.acquired)
        if (h) hint = h
      }
    }
  }

  Process {
    id: enrollProc
    command: ["omamobile-fp-enroll", "enroll"]
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.helperEvent(line) } }
    onExited: function(exitCode) {
      root.authPending = false
      if (root.startPending) { Qt.callLater(root.startEnroll); return }
      if (root.gotDone) return
      if (root.userCanceled) { root.screenOpen = false; root.page = "intro"; return }
      if (root.screenOpen && (root.page === "waiting" || root.page === "enrolling"))
        root.fail("Fingerprint setup stopped unexpectedly. Try again")
    }
  }

  Process {
    id: listProc
    command: ["omamobile-fp-enroll", "list"]
    stdout: SplitParser { onRead: function(line) { root.helperEvent(line) } }
    onExited: function(exitCode) {
      if (exitCode !== 0) { root.fingersKnown = false; root.sensorAvailable = false }
    }
  }

  Process {
    id: deleteProc
    command: ["omamobile-fp-enroll", "delete-all"]
    stdout: SplitParser { onRead: function(line) { root.helperEvent(line) } }
    onExited: { root.deleting = false; root.authPending = false; root.refreshFingers() }
  }

  // ---------------------------------------------------------------- enrollment: screen

  PanelWindow {
    id: enrollWindow

    screen: root.panelScreen
    visible: root.screenOpen && !root.authPending
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "omamobile-fingerprint-enroll"
    // Top, not Overlay: Omarchy's polkit prompt (patched to Top) and
    // squeekboard (Top) map after this page, so they stack above it.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // The whole screen takes touches, the sensor circle included: the
    // bridge reads the touchscreen itself, so nothing below needs them.
    Item {
      id: screenBody
      anchors.fill: parent

      readonly property real pad: Math.max(20, Style.space(24))
      readonly property real topInset: Math.max(56, Style.space(64))
      // The sensor in this window; centred low if it can't be placed.
      readonly property real cx: root.spot ? root.spot.x : width / 2
      readonly property real cy: root.spot ? root.spot.y : height * 0.72
      readonly property real sr: root.spot ? root.spot.r : 40

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        preventStealing: true
      }

      Rectangle {
        anchors.fill: parent
        color: Commons.Color.menu.background
        opacity: 0.98
      }

      // ---------- Words
      Column {
        id: words
        anchors.top: parent.top
        anchors.topMargin: screenBody.topInset
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: screenBody.pad
        anchors.rightMargin: screenBody.pad
        spacing: Style.spacing.huge

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          color: root.ink
          font.family: Style.font.family
          font.pixelSize: Style.font.displayLarge
          font.bold: true
          text: root.page === "intro" ? "Fingerprint unlock"
            : root.page === "waiting" ? "Getting ready"
            : root.page === "enrolling" ? root.stageText.title
            : root.page === "done" ? "Fingerprint added"
            : "Couldn't add the fingerprint"
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          color: Qt.darker(root.ink, 1.25)
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          lineHeight: 1.15
          text: root.page === "intro"
            ? "Unlock the phone, and approve sudo and other prompts, with a touch. The sensor is under the screen, inside the circle below.\n\n"
              + (!root.sensorAvailable ? "No fingerprint sensor is available. Is omamobile-fp running?"
                 : !root.fingersKnown ? ""
                 : root.enrolledFingers.length === 0 ? "No fingerprints added yet."
                 : root.enrolledFingers.length === 1 ? "1 fingerprint added."
                 : root.enrolledFingers.length + " fingerprints added.")
            : root.page === "waiting" ? "If asked, confirm with your password first."
            : root.page === "enrolling" ? root.stageText.body
            : root.page === "done"
              ? "Your " + SensorModel.fingerLabel(root.addedFinger) + " can now unlock the phone. Touch the sensor when you see the fingerprint icon."
            : root.failure
        }

        // The HAL's hint for the last touch
        Text {
          width: parent.width
          visible: root.page === "enrolling" && root.hint.length > 0
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          color: root.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          text: root.hint
        }
      }

      // ---------- The sensor: glyph and progress ring
      Item {
        id: sensorMark
        x: screenBody.cx - width / 2
        y: screenBody.cy - height / 2
        width: screenBody.sr * 3.4
        height: width

        readonly property real ringRadius: screenBody.sr * 1.55
        readonly property real ringWidth: Math.max(4, screenBody.sr * 0.14)

        Canvas {
          id: ring
          anchors.fill: parent
          property real value: root.progress
          property color track: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.15)
          property color fill: root.page === "error" ? Commons.Color.urgent : root.accent
          visible: root.page !== "intro"
          Behavior on value { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
          onValueChanged: requestPaint()
          onFillChanged: requestPaint()
          onVisibleChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var c = width / 2, r = sensorMark.ringRadius
            ctx.lineWidth = sensorMark.ringWidth
            ctx.lineCap = "round"
            ctx.strokeStyle = track
            ctx.beginPath()
            ctx.arc(c, c, r, 0, Math.PI * 2)
            ctx.stroke()
            if (value > 0) {
              ctx.strokeStyle = fill
              ctx.beginPath()
              ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * value)
              ctx.stroke()
            }
          }
        }

        // the circle itself, as the target draws it
        Rectangle {
          anchors.centerIn: parent
          width: screenBody.sr * 2
          height: width
          radius: width / 2
          color: "transparent"
          border.width: Math.max(1, Math.round(width / 40))
          border.color: root.ink
          opacity: root.page === "intro" || root.page === "waiting" ? 0.35 : 0
        }

        Text {
          id: mark
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.page === "done" ? root.checkGlyph : root.page === "error" ? root.alertGlyph : root.fingerprintGlyph
          color: root.page === "done" || root.page === "enrolling" ? root.accent
            : root.page === "error" ? Commons.Color.urgent : root.ink
          font.family: Style.font.family
          font.pixelSize: Math.round(screenBody.sr * 1.3)
          // The panel lights the circle under a finger: step aside then.
          opacity: root.fingerDown && root.page === "enrolling" ? 0
            : root.page === "intro" ? 0.55 : 0.9
          Behavior on opacity { NumberAnimation { duration: 120 } }

          // Breathes until the first touch, to say "here".
          SequentialAnimation on scale {
            running: root.screenOpen && (root.page === "waiting" || (root.page === "enrolling" && !root.touchedOnce))
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { from: 1; to: 1.12; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.12; to: 1; duration: 700; easing.type: Easing.InOutSine }
          }
        }
      }

      // ---------- Buttons
      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: screenBody.pad
        anchors.rightMargin: screenBody.pad
        anchors.bottomMargin: screenBody.pad
        spacing: Style.spacing.xxl

        FpButton {
          width: parent.width
          visible: root.page === "intro" && root.enrolledFingers.length > 0
          enabled: !root.deleting
          danger: true
          label: root.deleting ? "Deleting…" : "Delete all fingerprints"
          onTapped: { root.deleting = true; root.authPending = true; deleteProc.running = true }
        }

        Row {
          width: parent.width
          spacing: Style.spacing.xxl
          readonly property real half: (width - spacing) / 2

          FpButton {
            width: root.page === "waiting" || root.page === "enrolling" ? parent.width : parent.half
            label: root.page === "done" ? "Add another" : "Cancel"
            onTapped: root.page === "done" ? root.startEnroll() : root.cancelEnroll()
          }

          FpButton {
            width: parent.half
            visible: root.page === "intro" || root.page === "done" || root.page === "error"
            enabled: root.page !== "intro" || root.sensorAvailable
            primary: true
            label: root.page === "intro" ? "Start" : root.page === "done" ? "Done" : "Try again"
            onTapped: root.page === "done" ? root.closeScreen() : root.startEnroll()
          }
        }
      }
    }
  }
}
