// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "VoiceModel.js" as VoiceModel
import "VoiceLink.js" as VoiceLink
import "Readable.js" as Readable
import "../omamobile.launcher/LauncherModel.js" as LauncherModel

// Voice input for the phone (docs/VOICE-PLAN.md), through Voxtype's user
// daemon (voxtype.service, Omarchy's Install > AI > Dictation): speech is
// turned into text on the phone.
//
// Two ways in:
//
// * Ask your agent. Hold the home pill (omamobile.launcher: the dock's
//   search pill on the home screen, the thin strip over an app): this
//   sheet opens and listens; letting go stops, and Voxtype writes the
//   transcript to $XDG_RUNTIME_DIR/omamobile-voice.txt. A press shorter
//   than VoiceModel.HOLD_MS keeps listening until Stop. Then the
//   check-and-send page: the transcript to edit, the agent (a tap opens
//   Omarchy's agent picker), the auto-permissions warning, and Send (the
//   launcher's promptArgv: a terminal running the agent with the text as
//   its first prompt), Say again, Cancel, Copy and Type into last app.
//   `omarchy-shell shell summon omamobile.voice '{}'` opens it listening.
//
// * Follow-up in an agent. While an agent's terminal (org.omarchy.agent)
//   is in front and the keyboard is down, a round mic floats at the bottom
//   right: hold to talk, tap to toggle. Voxtype types into the agent and,
//   with "Say 'send' to press Enter" on, presses Enter when the speech ends
//   in "send" (--smart-auto-submit).
//
// * Power + Volume Up (omamobile-keys, off until turned on in the settings):
//   push-to-talk into the app in front, or the agent sheet on the home
//   screen.
//
// * Settings (`shell summon omamobile.voice '{"page":"settings"}'`, the
//   Dictation tile's long press, Omarchy's Setup > Voice): the speech model
//   (downloaded through Voxtype and switched with `voxtype config set`), the
//   triggers, "Say 'send'", and the check before sending to an agent, kept
//   in ~/.config/omamobile/voice.json.
//
// * Dictation into any app. The mic key at the left end of the keyboard's
//   strip (omamobile.launcher), or the Dictation tile in quick settings:
//   Voxtype types into the focused window, and while it listens a strip
//   above the keyboard shows the level, the time, Cancel and Done. The
//   strip shows for any recording the shell didn't start for the agent,
//   so the tile's recordings get it too.
//
// The model is the daemon's own (omamobile-setup-user sets tiny.en once it
// is downloaded; a per-recording --model is ignored unless prepared).
// Voxtype checks for wtype and wl-copy with `which` (a dependency).
// Every recording the shell starts passes --no-osd (VoiceModel.startArgv):
// Voxtype's GTK overlay would sit over the dock. The daemon's state file
// ($XDG_RUNTIME_DIR/voxtype/state) says what it is doing; the level comes
// from voxtype-audio-bridge (NDJSON from the daemon's audio socket). The
// screen stays on while listening and transcribing (an idle inhibitor on
// whichever surface shows). The other plugins reach this one through
// VoiceLink.js (a press and its release need no process in between).
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "omamobile.voice"

  // ---------------------------------------------------------------- state

  property bool opened: false
  // idle | starting | listening | transcribing | review | error
  property string phase: "idle"
  // "ask" (this sheet), "type" (mic key, tile), "" (not started here)
  property string owner: ""
  property bool pushToTalk: false
  property bool fingerDown: false
  property real pressedAt: 0
  property bool pendingStop: false
  property real listenStart: 0
  property real elapsed: 0
  property var levels: []
  property real lastLevelAt: 0
  property string transcript: ""
  property string errorText: ""
  property int readTries: 0
  property bool copied: false

  readonly property bool busy: phase === "starting" || phase === "listening" || phase === "transcribing"
  readonly property bool listening: phase === "listening"
  // The Listening strip is for typing into an app; the agent sheet and the
  // floating agent mic show their own state.
  readonly property bool stripShown: owner !== "ask" && owner !== "agent" && (busy || phase === "error")
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string transcriptPath: VoiceModel.transcriptPath(runtimeDir)
  readonly property string statePath: runtimeDir + "/voxtype/state"
  readonly property bool appOnScreen: !!Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.toplevels.values.length > 0
  // The app in front is an agent's terminal (Omarchy's one class for them).
  readonly property bool agentInFront: appOnScreen && !!ToplevelManager.activeToplevel
    && VoiceModel.isAgent(ToplevelManager.activeToplevel.appId)

  // ---------------------------------------------------------------- settings

  property var settings: VoiceModel.defaultSettings()
  readonly property string configDir: Quickshell.env("HOME") + "/.config/omamobile"
  readonly property string settingsPath: configDir + "/voice.json"
  property bool settingsOpen: false

  FileView {
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.settings = VoiceModel.parseSettings(text())
    onLoadFailed: root.settings = VoiceModel.defaultSettings()
  }

  function setSetting(key, value) {
    settings = VoiceModel.withSetting(settings, key, value)
    settingsWrite.running = false
    settingsWrite.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" >"$1.new" && mv -f "$1.new" "$1"',
                             "sh", settingsPath, VoiceModel.serializeSettings(settings)]
    settingsWrite.running = true
  }

  Process { id: settingsWrite }

  // The speech model: the daemon's, from the user's voxtype config, and
  // what is downloaded.
  property string modelId: "base.en"
  property var installed: []
  property string downloading: ""
  property string downloadText: ""
  property string modelError: ""
  readonly property var modelRows: VoiceModel.modelRows(modelId, installed)
  readonly property string modelsDir: Quickshell.env("HOME") + "/.local/share/voxtype/models"

  FileView {
    path: Quickshell.env("HOME") + "/.config/voxtype/config.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.modelId = VoiceModel.configModel(text())
    onLoadFailed: root.modelId = "base.en"
  }

  Process {
    id: modelsList
    command: ["ls", "-1", root.modelsDir]
    stdout: StdioCollector { id: modelsOut; waitForEnd: true }
    onExited: root.installed = VoiceModel.installedModels(modelsOut.text)
  }

  function refreshModels() {
    modelsList.running = false
    modelsList.running = true
  }

  function chooseModel(id) {
    if (downloading || id === modelId) return
    modelError = ""
    if (installed.indexOf(id) >= 0) { switchModel(id); return }
    downloading = id
    downloadText = "Starting"
    downloadProc.command = VoiceModel.downloadArgv(id)
    downloadProc.running = true
  }

  function switchModel(id) {
    modelId = id
    switchProc.command = VoiceModel.switchArgv(id)
    switchProc.running = true
  }

  Process {
    id: downloadProc
    stdout: SplitParser {
      onRead: function(line) {
        var p = VoiceModel.parseProgress(line)
        if (p) root.downloadText = p.text
      }
    }
    onExited: function(exitCode) {
      var id = root.downloading
      root.downloading = ""
      root.downloadText = ""
      root.refreshModels()
      if (exitCode === 0) root.switchModel(id)
      else root.modelError = "The download stopped (exit " + exitCode + "). Check the connection and try again."
    }
  }

  Process {
    id: switchProc
    onExited: function(exitCode) {
      if (exitCode !== 0) root.modelError = "Voxtype didn't take the model (exit " + exitCode + ")."
    }
  }

  function openSettings() {
    settingsOpen = true
    refreshModels()
    if (!opened && shell && typeof shell.summon === "function") shell.summon(pluginId, JSON.stringify({ page: "settings" }))
    else opened = true
    return "ok"
  }

  // The on-screen keyboard: the floating agent mic gives way to the
  // keyboard strip's mic key while it is up.
  property bool oskOpen: false

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
    onExited: { root.oskOpen = false; oskRestart.restart() }
  }

  Timer { id: oskRestart; interval: 3000; onTriggered: oskWatch.running = true }

  // The floating mic over an agent: its own recording keeps it on screen
  // (unmapping it under a held finger would lose the release).
  readonly property bool agentMicShown: (owner === "agent" && busy)
    || (settings.agentMic && agentInFront && !oskOpen && !opened && !busy)

  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int pad: Style.spacing.panelPadding
  readonly property color foreground: Commons.Color.popups.text
  readonly property color recording: Commons.Color.urgent

  // The agent, as the launcher reads it: Omarchy's default agent
  // (omarchy-default-agent writes ~/.config/omarchy/defaults/agent), unset
  // until the user picks one.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string agentId: ""
  readonly property string agentName: LauncherModel.agentName(agentId)
  readonly property bool hasAgent: agentId.length > 0
  readonly property string agentIcon: hasAgent
    ? Util.fileUrl(omarchyPath + "/shell/plugins/agents/assets/" + agentId + ".svg") : ""

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/defaults/agent"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.agentId = LauncherModel.agentId(text())
    onLoadFailed: root.agentId = ""
  }

  // ---------------------------------------------------------------- host API

  // A summon from elsewhere (`shell summon omamobile.voice '{}'`) starts
  // listening, hands free; the long press has started already.
  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") || ({}) } catch (e) { payload = ({}) }
    opened = true
    if (payload.page === "settings") {
      settingsOpen = true
      refreshModels()
      return
    }
    if (settingsOpen) return
    if (phase === "idle" || (phase === "error" && owner !== "ask")) beginAsk(false)
  }

  // Closing the sheet while it listens or transcribes throws the
  // recording away; closing the review or the error leaves nothing behind.
  function close() {
    if (!opened) return
    opened = false
    settingsOpen = false
    editor.focus = false
    if (owner === "ask") {
      if (busy) Quickshell.execDetached(VoiceModel.CANCEL_ARGV)
      reset()
    }
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function reset() {
    phase = "idle"
    owner = ""
    pendingStop = false
    pushToTalk = false
    fingerDown = false
    levels = []
    startTimeout.stop()
  }

  // `shell call omamobile.voice snapshot ''`
  function snapshot() {
    return JSON.stringify({ opened: opened, phase: phase, owner: owner, pushToTalk: pushToTalk,
                            elapsed: Math.floor(elapsed), agent: agentId, chars: transcript.length,
                            agentInFront: agentInFront, model: modelId, settings: settings })
  }

  // ---------------------------------------------------------------- calls (VoiceLink.js and IPC)

  // The home pill's long press, and its release.
  function askPress() {
    if (busy && owner === "ask") return "busy"
    beginAsk(true)
    return "ok"
  }

  function askRelease() {
    return release("ask")
  }

  // The search pill's mic button: a tap opens the sheet listening, hands
  // free (Stop, or a tap on the sheet's mic, ends it); a tap while it
  // listens stops.
  function askTap() {
    if (busy && owner === "ask") { stop(); return "stopping" }
    beginAsk(false)
    return "ok"
  }

  // The sheet's mic circle: stops while listening, listens again after an
  // error.
  function micTapped() {
    if (phase === "listening" || phase === "starting") stop()
    else if (phase === "error") sayAgain()
  }

  // The floating mic over an agent: held, a push-to-talk; tapped, on and
  // off. Types into the agent, Enter on "send" when that setting is on.
  function agentPress() {
    if (busy) return "busy"
    begin("agent", true)
    return "ok"
  }

  function agentRelease() {
    return release("agent")
  }

  function agentTap() {
    if (busy && owner === "agent") { stop(); return "stopping" }
    if (busy) return "busy"
    begin("agent", false)
    return "ok"
  }

  // Power + Volume Up (omamobile-keys), when turned on in the settings:
  // the agent sheet on the home screen, typing into the app otherwise.
  function keyPress() {
    if (!settings.powerVolumeUp) return "off"
    if (busy) return "busy"
    if (VoiceModel.keyTarget(appOnScreen) === "ask") beginAsk(true)
    else begin("type", true)
    return "ok"
  }

  function keyRelease() {
    if (owner === "ask" || owner === "type") return release(owner)
    return "idle"
  }

  // The mic key: held, a push-to-talk; tapped, on and off.
  function dictatePress() {
    if (busy) return "busy"
    begin("type", true)
    return "ok"
  }

  function dictateRelease() {
    return release("type")
  }

  function dictateTap() {
    if (busy && owner !== "ask") { stop(); return "stopping" }
    if (busy) return "busy"
    begin("type", false)
    return "ok"
  }

  function stop() {
    if (phase === "starting") { pendingStop = true; return "pending" }
    if (phase !== "listening") return "idle"
    Quickshell.execDetached(VoiceModel.STOP_ARGV)
    return "ok"
  }

  function cancel() {
    if (busy) Quickshell.execDetached(VoiceModel.CANCEL_ARGV)
    var wasAsk = owner === "ask"
    reset()
    if (wasAsk && opened) dismiss()
    return "ok"
  }

  // ---------------------------------------------------------------- recording

  function beginAsk(hold) {
    transcript = ""
    editor.text = ""
    copied = false
    begin("ask", hold)
    if (!opened && shell && typeof shell.summon === "function") shell.summon(pluginId, "{}")
    else opened = true
  }

  function begin(who, hold) {
    if (busy) Quickshell.execDetached(VoiceModel.CANCEL_ARGV)
    owner = who
    phase = "starting"
    errorText = ""
    pushToTalk = hold
    fingerDown = hold
    pressedAt = Date.now()
    pendingStop = false
    levels = []
    elapsed = 0
    startProc.running = false
    // Enter on "send" only where it means something: typing into an agent.
    var submit = settings.sayToSend && (who === "agent" || agentInFront)
    startProc.command = who === "ask" ? VoiceModel.fileStartArgv(transcriptPath)
                                      : VoiceModel.startArgv("type", "", submit)
    startProc.running = true
    startTimeout.restart()
    stateFile.reload()
  }

  // Letting go: stops a push-to-talk; a short press keeps listening.
  function release(who) {
    if (owner !== who || !fingerDown) return "idle"
    fingerDown = false
    if (VoiceModel.releaseStops(phase, Date.now() - pressedAt)) return stop()
    pushToTalk = false
    return "listening"
  }

  function fail(text) {
    startTimeout.stop()
    phase = "error"
    errorText = text
    pushToTalk = false
    fingerDown = false
    if (owner !== "ask") errorClear.restart()
  }

  function handleVox(text) {
    var vox = VoiceModel.voxState(text)
    var was = phase
    var r = VoiceModel.step(phase, owner, vox)
    if (VoiceModel.ticks(was, r.phase, owner)) Quickshell.execDetached(VoiceModel.HAPTIC_ARGV)
    if (r.phase === "listening" && was !== "listening") {
      startTimeout.stop()
      listenStart = Date.now()
      // Push-to-talk counts from here: the press may have reached the
      // daemon late.
      if (fingerDown) pressedAt = Date.now()
      elapsed = 0
      if (pendingStop) {
        pendingStop = false
        Quickshell.execDetached(VoiceModel.STOP_ARGV)
      }
    }
    phase = r.phase
    owner = r.owner
    if (r.phase === "idle") { pushToTalk = false; fingerDown = false }
    if (r.read) {
      readTries = 0
      readTimer.restart()
    }
  }

  function applyTranscript(text) {
    var r = VoiceModel.afterRead(text)
    if (r.phase === "error" && readTries < 4) {
      readTries++
      readTimer.restart()
      return
    }
    phase = r.phase
    errorText = r.error
    transcript = r.text
    editor.text = r.text
    pushToTalk = false
    // "Ask before sending to an agent" off: straight to the agent.
    if (r.phase === "review" && !settings.confirmSend && hasAgent) send()
  }

  // ---------------------------------------------------------------- review actions

  readonly property string finalText: VoiceModel.cleanTranscript(editor.text)

  function send() {
    if (!hasAgent) { pickAgent(); return }
    if (!finalText) return
    Util.execArgv(LauncherModel.promptArgv(finalText))
    dismiss()
  }

  function pickAgent() {
    Util.execArgv(LauncherModel.PICK_AGENT_ARGV)
  }

  function copyText() {
    if (!finalText) return
    Quickshell.execDetached(VoiceModel.copyArgv(finalText))
    copied = true
  }

  // After the sheet has gone, so the app has the keyboard focus again.
  function typeIntoApp() {
    if (!finalText) return
    var argv = VoiceModel.typeArgv(finalText)
    dismiss()
    Quickshell.execDetached(argv)
  }

  function sayAgain() {
    beginAsk(false)
  }

  // The review page is the only one that types: leaving it takes the
  // focus and the on-screen keyboard away, as the update sheet does.
  onPhaseChanged: {
    if (phase === "review" || owner !== "ask") return
    if (editor.activeFocus) {
      editor.focus = false
      Quickshell.execDetached(["qs", "ipc", "-p", Quickshell.shellDir, "call", "shell", "call",
                               "omamobile.keyboard", "hideKeyboard", ""])
    }
  }

  // ---------------------------------------------------------------- processes

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.handleVox(text())
    onLoadFailed: root.handleVox("")
  }

  // The state file's watch can miss a daemon that (re)created it: read it
  // again while something is under way.
  Timer {
    interval: 500
    repeat: true
    running: root.busy
    onTriggered: stateFile.reload()
  }

  Process {
    id: startProc
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.phase === "starting")
        root.fail("Voxtype isn't running. Install it with Install > AI > Dictation, or start voxtype.service.")
    }
  }

  Timer {
    id: startTimeout
    interval: 4000
    onTriggered: if (root.phase === "starting") root.fail("Voxtype didn't start listening. Is voxtype.service running?")
  }

  Timer {
    id: errorClear
    interval: 4000
    onTriggered: if (root.phase === "error" && root.owner !== "ask") root.reset()
  }

  Timer {
    id: readTimer
    interval: 200
    onTriggered: { readProc.running = false; readProc.running = true }
  }

  Process {
    id: readProc
    command: ["cat", "--", root.transcriptPath]
    stdout: StdioCollector { id: readOut; waitForEnd: true }
    onExited: root.applyTranscript(readOut.text)
  }

  Process {
    id: levelBridge
    command: ["voxtype-audio-bridge"]
    running: root.listening && (root.opened || root.stripShown)
    stdout: SplitParser {
      onRead: function(line) {
        var frame = VoiceModel.parseLevel(line)
        if (!frame) return
        var now = Date.now()
        if (now - root.lastLevelAt < 50) return
        root.lastLevelAt = now
        root.levels = VoiceModel.pushLevel(root.levels, frame.rms)
      }
    }
  }

  Timer {
    interval: 250
    repeat: true
    running: root.listening
    onTriggered: root.elapsed = (Date.now() - root.listenStart) / 1000
  }

  IpcHandler {
    target: "omamobile.voice"
    function askPress(): string { return root.askPress() }
    function askRelease(): string { return root.askRelease() }
    function askTap(): string { return root.askTap() }
    function agentTap(): string { return root.agentTap() }
    function keyPress(): string { return root.keyPress() }
    function keyRelease(): string { return root.keyRelease() }
    function openSettings(): string { return root.openSettings() }
    function dictatePress(): string { return root.dictatePress() }
    function dictateRelease(): string { return root.dictateRelease() }
    function dictateTap(): string { return root.dictateTap() }
    function stop(): string { return root.stop() }
    function cancel(): string { return root.cancel() }
    function snapshot(): string { return root.snapshot() }
  }

  Component.onCompleted: VoiceLink.publish(root)
  Component.onDestruction: VoiceLink.withdraw(root)

  // ---------------------------------------------------------------- the sheet

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  readonly property string page: settingsOpen ? "settings" : phase === "review" ? "review" : phase === "error" ? "error" : "listen"

  PanelWindow {
    id: sheetWindow

    visible: root.opened || root.reveal > 0
    anchors { top: true; bottom: true; left: true; right: true }
    // Normal: between the status bar and the on-screen keyboard, so the
    // transcript stays above the keys while it is edited.
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-voice"
    WlrLayershell.layer: WlrLayer.Top
    // The keyboard only for the review page's text; listening, the app
    // underneath keeps it (Type into last app types there).
    WlrLayershell.keyboardFocus: root.opened && root.page === "review" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    IdleInhibitor {
      window: sheetWindow
      enabled: root.opened && root.owner === "ask" && root.busy
    }

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
      opacity: root.reveal
    }

    MouseArea {
      anchors.fill: parent
      onClicked: {
        if (root.page === "settings") root.dismiss()
        else if (root.page !== "review") root.cancel()
      }
    }

    BorderSurface {
      id: card
      objectName: "voiceCard"

      x: Style.gapsOut
      width: parent.width - Style.gapsOut * 2
      // The settings take the whole height; the rest is a bottom sheet.
      height: root.page === "settings" ? parent.height - Style.gapsOut * 2
        : Math.min(parent.height - Style.gapsOut * 2, Math.max(Style.space(520), parent.height * 0.6))
      y: parent.height - height - Style.gapsOut + Math.round((1 - root.reveal) * Style.space(60))
      opacity: root.reveal
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      padding: root.pad

      focus: root.opened
      Keys.onEscapePressed: root.page === "settings" ? root.dismiss() : root.cancel()

      MouseArea { anchors.fill: parent }

      Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // ---------- Header: title and the agent
        Item {
          id: headerRow
          objectName: "voiceHeader"
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.touchSize

          Text {
            anchors.left: parent.left
            anchors.right: root.page === "settings" ? settingsClose.left : agentChip.left
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.page === "settings" ? "Voice" : root.page === "review" ? "Send to your agent?" : "Ask your agent"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          GlyphTap {
            id: settingsClose
            objectName: "settingsClose"
            visible: root.page === "settings"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰅖"
            Accessible.name: "Close"
            onTapped: root.dismiss()
          }

          AgentChip {
            id: agentChip
            objectName: "agentChip"
            visible: root.page !== "settings"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            name: root.hasAgent ? root.agentName : "Choose agent"
            icon: root.agentIcon
            onTapped: root.pickAgent()
          }
        }

        // ---------- Settings (Settings in the design)
        Flickable {
          id: settingsFlick
          objectName: "voiceSettings"
          visible: root.page === "settings"
          anchors.top: headerRow.bottom
          anchors.topMargin: Style.spacing.lg
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          contentHeight: settingsColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: settingsColumn
            width: settingsFlick.width
            spacing: Style.spacing.lg

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Speech is turned into text on this phone. Nothing you say leaves it."
              color: root.foreground
              opacity: 0.8
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }

            SectionLabel { text: "Speech model" }

            Repeater {
              model: root.modelRows
              delegate: ModelRow {
                required property var modelData
                width: settingsColumn.width
                objectName: "model-" + modelData.id
                title: modelData.name
                line: root.downloading === modelData.id ? modelData.size + " · downloading " + root.downloadText : modelData.line
                chosen: modelData.chosen
                badge: modelData.chosen ? "In use" : root.downloading === modelData.id ? root.downloadText
                  : modelData.downloaded ? "" : "Download"
                enabled: root.downloading === ""
                onTapped: root.chooseModel(modelData.id)
              }
            }

            InfoRow {
              width: parent.width
              visible: root.modelError !== ""
              glyph: "󰀦"
              text: root.modelError
              urgent: true
            }

            SectionLabel { text: "Start listening with" }

            SettingRow { objectName: "setting-holdPill"; title: "Hold the home pill"; note: "or the search bar; the mic in the search bar always works"; checked: root.settings.holdPill === true; onToggled: root.setSetting("holdPill", !checked) }
            SettingRow { objectName: "setting-micKey"; title: "Mic key under the keyboard"; checked: root.settings.micKey === true; onToggled: root.setSetting("micKey", !checked) }
            SettingRow { objectName: "setting-agentMic"; title: "Mic over agents"; note: "a round mic while an agent is in front"; checked: root.settings.agentMic === true; onToggled: root.setSetting("agentMic", !checked) }
            SettingRow { objectName: "setting-powerVolumeUp"; title: "Power + Volume Up"; note: "hold both to talk; not on the lock screen"; checked: root.settings.powerVolumeUp === true; onToggled: root.setSetting("powerVolumeUp", !checked) }

            SectionLabel { text: "Sending" }

            SettingRow { objectName: "setting-sayToSend"; title: "Say “send” to press Enter"; note: "in agents"; checked: root.settings.sayToSend === true; onToggled: root.setSetting("sayToSend", !checked) }
            SettingRow { objectName: "setting-confirmSend"; title: "Ask before sending to an agent"; note: "off: what you say goes to the agent as soon as it is text"; checked: root.settings.confirmSend === true; onToggled: root.setSetting("confirmSend", !checked) }
          }
        }

        // ---------- Listen: the mic, the time, the level
        Item {
          id: listenPage
          visible: root.page === "listen"
          anchors.top: headerRow.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: listenButtons.top
          anchors.bottomMargin: Style.spacing.lg

          Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: Style.spacing.xl

            Item {
              id: micCircle
              objectName: "micCircle"
              readonly property int size: Math.max(72, Math.min(Style.space(168), listenPage.height - Style.space(150)))
              anchors.horizontalCenter: parent.horizontalCenter
              width: size
              height: size
              Accessible.role: Accessible.Button
              Accessible.name: root.listening ? "Stop listening" : "Ask by voice"

              // A tap on the mic stops listening, as Stop does.
              TapHandler {
                onTapped: root.micTapped()
              }

              Rectangle {
                id: ring
                anchors.centerIn: parent
                width: parent.width
                height: width
                radius: width / 2
                color: Qt.rgba(0, 0, 0, 0)
                border.width: Math.max(1, Style.space(2))
                border.color: root.listening ? root.recording : Commons.Color.accent
                opacity: 0.5
                SequentialAnimation on scale {
                  running: root.listening && root.opened
                  loops: Animation.Infinite
                  NumberAnimation { from: 0.8; to: 1.0; duration: 800; easing.type: Easing.OutCubic }
                  NumberAnimation { from: 1.0; to: 0.8; duration: 800; easing.type: Easing.InCubic }
                }
              }

              Rectangle {
                anchors.centerIn: parent
                width: Math.round(parent.width * 0.57)
                height: width
                radius: width / 2
                color: root.listening ? root.recording : Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)

                Text {
                  id: micGlyph
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  // nf-md-microphone; the reload glyph while transcribing
                  text: root.phase === "transcribing" ? "󰑐" : "󰍬"
                  color: root.listening ? Commons.Color.popups.background : Commons.Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Math.round(parent.width * 0.42)
                  RotationAnimator on rotation {
                    running: root.phase === "transcribing" && root.opened
                    from: 0
                    to: 360
                    duration: 1200
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) micGlyph.rotation = 0
                  }
                }
              }
            }

            StatusLine {
              anchors.horizontalCenter: parent.horizontalCenter
              phase: root.phase
              owner: root.owner
              elapsed: root.elapsed
            }

            LevelMeter {
              anchors.horizontalCenter: parent.horizontalCenter
              width: Math.min(parent.width, Style.space(260))
              height: Style.space(26)
              levels: root.levels
              active: root.listening
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: VoiceModel.askHint(root.phase, root.pushToTalk)
              color: root.foreground
              opacity: 0.7
              font.family: Style.font.family
              font.pixelSize: Readable.px(Style.font.caption)
              wrapMode: Text.Wrap
            }
          }
        }

        Row {
          id: listenButtons
          visible: root.page === "listen"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.touchSize
          spacing: Style.spacing.lg
          layoutDirection: Qt.RightToLeft

          SheetAction {
            width: (parent.width - parent.spacing) / 2
            label: "Stop"
            primary: true
            tone: root.recording
            enabled: root.phase === "listening" || root.phase === "starting"
            onTapped: root.stop()
          }

          SheetAction {
            width: (parent.width - parent.spacing) / 2
            label: "Cancel"
            onTapped: root.cancel()
          }
        }

        // ---------- Error: nothing heard, or Voxtype missing
        Column {
          visible: root.page === "error"
          anchors.top: headerRow.bottom
          anchors.topMargin: Style.spacing.xl
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.spacing.xl

          InfoRow {
            width: parent.width
            glyph: "󰍭"
            text: root.errorText
            urgent: true
          }
        }

        Row {
          id: errorButtons
          visible: root.page === "error"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.touchSize
          spacing: Style.spacing.lg
          layoutDirection: Qt.RightToLeft

          SheetAction {
            width: (parent.width - parent.spacing) / 2
            label: "Say again"
            primary: true
            onTapped: root.sayAgain()
          }

          SheetAction {
            width: (parent.width - parent.spacing) / 2
            label: "Cancel"
            onTapped: root.cancel()
          }
        }

        // ---------- Review: check and send
        Text {
          id: editLabel
          visible: root.page === "review"
          anchors.top: headerRow.bottom
          anchors.topMargin: Style.spacing.lg
          anchors.left: parent.left
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: "What you said · tap to edit"
          color: root.foreground
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: Readable.px(Style.font.caption)
          elide: Text.ElideRight
        }

        Flickable {
          id: editFlick
          objectName: "transcript"
          visible: root.page === "review"
          anchors.top: editLabel.bottom
          anchors.topMargin: Style.spacing.md
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: warning.top
          anchors.bottomMargin: Style.spacing.lg
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Controls.TextArea.flickable: Controls.TextArea {
            id: editor
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.PlainText
            color: root.foreground
            selectionColor: Style.selectionFillFor(root.foreground, Commons.Color.accent)
            selectedTextColor: root.foreground
            placeholderText: "Say or type what to ask"
            placeholderTextColor: Qt.darker(root.foreground, 1.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            leftPadding: Style.spacing.controlPaddingX + Math.max(1, Style.space(2))
            rightPadding: leftPadding
            topPadding: Style.spacing.lg
            bottomPadding: Style.spacing.lg
            background: BorderSurface {
              color: Style.controlFill(editor.activeFocus, false, root.foreground, Commons.Color.accent)
              borderSpec: Border.controlSpec(editor.activeFocus ? "focus" : "selected", root.foreground, Commons.Color.accent)
              radius: Style.cornerRadius
            }
            onTextChanged: root.copied = false
          }
        }

        InfoRow {
          id: warning
          objectName: "permissionWarning"
          visible: root.page === "review" && root.hasAgent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: alsoRow.top
          anchors.bottomMargin: Style.spacing.lg
          height: visible ? implicitHeight : 0
          glyph: "󰀦"
          text: VoiceModel.permissionText(root.agentName)
        }

        Row {
          id: alsoRow
          visible: root.page === "review"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: reviewButtons.top
          anchors.bottomMargin: Style.spacing.lg
          height: root.touchSize
          spacing: Style.spacing.lg

          Text {
            id: alsoLabel
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Also:"
            color: root.foreground
            opacity: 0.7
            font.family: Style.font.family
            font.pixelSize: Readable.px(Style.font.caption)
          }

          SheetAction {
            width: (parent.width - alsoLabel.width - parent.spacing * 2) * 0.4
            label: root.copied ? "Copied" : "Copy"
            small: true
            enabled: root.finalText.length > 0
            onTapped: root.copyText()
          }

          SheetAction {
            width: (parent.width - alsoLabel.width - parent.spacing * 2) * 0.6
            label: "Type into last app"
            small: true
            enabled: root.finalText.length > 0 && root.appOnScreen
            onTapped: root.typeIntoApp()
          }
        }

        Row {
          id: reviewButtons
          visible: root.page === "review"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.touchSize
          spacing: Style.spacing.lg
          layoutDirection: Qt.RightToLeft

          SheetAction {
            id: sendButton
            objectName: "send"
            width: (parent.width - sayAgainButton.width - parent.spacing * 2) * 2 / 3
            label: VoiceModel.sendLabel(root.hasAgent ? root.agentName : "")
            primary: true
            enabled: !root.hasAgent || root.finalText.length > 0
            onTapped: root.send()
          }

          SheetAction {
            width: (parent.width - sayAgainButton.width - parent.spacing * 2) / 3
            label: "Cancel"
            onTapped: root.cancel()
          }

          GlyphTap {
            id: sayAgainButton
            objectName: "sayAgain"
            glyph: "󰍬"
            framed: true
            onTapped: root.sayAgain()
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- the listening strip

  // Above the on-screen keyboard while Voxtype types into an app (Main in
  // the design): the level, the time, Cancel and Done. It reserves its
  // height (an exclusive zone), so the app's text field ends above it
  // rather than under it, and it never takes the keyboard focus, so the
  // text keeps going to the app.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: stripWindow
      required property var modelData
      screen: modelData

      visible: root.stripShown
      anchors { bottom: true; left: true; right: true }
      implicitHeight: stripCard.implicitHeight + Style.gapsOut * 2
      exclusionMode: ExclusionMode.Auto
      color: "transparent"
      WlrLayershell.namespace: "omamobile-voice-strip"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      IdleInhibitor {
        window: stripWindow
        enabled: root.stripShown && root.busy
      }

      // Main in the design. Written out here rather than as an inline
      // component, which couldn't see root.
      BorderSurface {
        id: stripCard
        anchors.fill: parent
        anchors.margins: Style.gapsOut
        objectName: "listeningStrip"
        implicitHeight: stripColumn.implicitHeight + Style.spacing.xl * 2
        color: Commons.Color.popups.background
        borderSpec: Border.flat(root.phase === "error" ? Commons.Color.urgent : root.busy ? root.recording : Commons.Color.popups.border,
                                Math.max(1, Style.space(2)))
        radius: Style.cornerRadius

        Column {
          id: stripColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.spacing.xl
          spacing: Style.spacing.lg

          Item {
            width: parent.width
            height: Math.max(stripStatus.implicitHeight, stripTime.implicitHeight)
            visible: root.phase !== "error"

            StatusLine {
              id: stripStatus
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              phase: root.phase
              owner: root.owner
              elapsed: -1
            }

            Text {
              id: stripTime
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: VoiceModel.elapsedText(root.elapsed) + " · on this phone"
              visible: root.listening
              color: root.foreground
              opacity: 0.7
              font.family: Style.font.family
              font.pixelSize: Readable.px(Style.font.caption)
            }
          }

          InfoRow {
            width: parent.width
            visible: root.phase === "error"
            glyph: "󰍭"
            text: root.errorText
            urgent: true
          }

          LevelMeter {
            width: parent.width
            height: Style.space(26)
            visible: root.phase !== "error"
            levels: root.levels
            active: root.listening
          }

          Row {
            width: parent.width
            height: root.touchSize
            spacing: Style.spacing.lg
            layoutDirection: Qt.RightToLeft
            visible: root.phase !== "error"

            SheetAction {
              width: (parent.width - parent.spacing) * 2 / 3
              label: root.phase === "transcribing" ? "Typing..." : "Done · type it"
              primary: true
              tone: root.recording
              enabled: root.phase === "listening" || root.phase === "starting"
              onTapped: root.stop()
            }

            SheetAction {
              width: (parent.width - parent.spacing) / 3
              label: "Cancel"
              onTapped: root.cancel()
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- the mic over an agent

  // FollowUp in the design: a round mic at the bottom right while an
  // agent's terminal is in front and the keyboard is down (the keyboard
  // strip's mic key covers typing with it up). Hold to talk, tap to start
  // and tap again to stop; Voxtype types into the agent. Normal exclusion,
  // so it sits above the home strip; it never takes the keyboard focus.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: agentMicWindow
      required property var modelData
      screen: modelData

      visible: root.agentMicShown
      anchors { bottom: true; right: true }
      margins { bottom: Style.gapsOut + Style.spacing.xl; right: Style.gapsOut + Style.spacing.xl }
      implicitWidth: agentMic.width
      implicitHeight: agentMic.height
      exclusionMode: ExclusionMode.Normal
      color: "transparent"
      WlrLayershell.namespace: "omamobile-voice-agent-mic"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      IdleInhibitor {
        window: agentMicWindow
        enabled: root.owner === "agent" && root.busy
      }

      BorderSurface {
        id: agentMic
        objectName: "agentMic"
        property bool held: false
        readonly property bool live: root.owner === "agent" && (root.phase === "listening" || root.phase === "starting")
        width: Math.max(56, Style.space(60))
        height: width
        radius: Math.min(Style.cornerRadius, width / 2)
        color: agentMic.live ? root.recording
          : agentMicTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
          : Commons.Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", agentMic.live ? root.recording : Commons.Color.popups.border, Math.max(1, Style.space(2)))
        Accessible.role: Accessible.Button
        Accessible.name: agentMic.live ? "Stop talking to the agent" : "Talk to the agent"

        Text {
          id: agentMicGlyph
          anchors.centerIn: parent
          textFormat: Text.PlainText
          // nf-md-microphone; the reload glyph while transcribing
          text: root.owner === "agent" && root.phase === "transcribing" ? "󰑐" : "󰍬"
          color: agentMic.live ? Commons.Color.popups.background : root.foreground
          font.family: Style.font.family
          font.pixelSize: Math.round(agentMic.width * 0.42)
          RotationAnimator on rotation {
            running: root.owner === "agent" && root.phase === "transcribing"
            from: 0
            to: 360
            duration: 1200
            loops: Animation.Infinite
            onRunningChanged: if (!running) agentMicGlyph.rotation = 0
          }
        }

        TapHandler {
          id: agentMicTouch
          longPressThreshold: 0.3
          onPressedChanged: {
            if (pressed) { agentMic.held = false; return }
            if (agentMic.held) root.agentRelease()
          }
          onLongPressed: {
            agentMic.held = true
            root.agentPress()
          }
          onTapped: root.agentTap()
        }
      }
    }
  }

  // ---------------------------------------------------------------- pieces

  // "● Listening · 0:05" (elapsed < 0 leaves the time out).
  component StatusLine: Row {
    id: statusItem
    property string phase: "idle"
    property string owner: ""
    property real elapsed: 0
    spacing: Style.spacing.md

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(8)
      height: width
      radius: width / 2
      color: statusItem.phase === "listening" ? Commons.Color.urgent : Commons.Color.accent
      SequentialAnimation on opacity {
        running: statusItem.phase === "listening"
        loops: Animation.Infinite
        NumberAnimation { from: 1; to: 0.45; duration: 600 }
        NumberAnimation { from: 0.45; to: 1; duration: 600 }
      }
    }

    Text {
      textFormat: Text.PlainText
      text: VoiceModel.statusText(statusItem.phase, statusItem.owner) +
        (statusItem.elapsed >= 0 && statusItem.phase === "listening" ? " · " + VoiceModel.elapsedText(statusItem.elapsed) : "")
      color: statusItem.phase === "listening" ? Commons.Color.urgent : Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }

  // The last LEVEL_BARS loudness values as bars, newest at the right; the
  // rest stay flat dots in the muted colour.
  component LevelMeter: Item {
    id: meter
    property var levels: []
    property bool active: false
    objectName: "levelMeter"
    // One entry per bar: its height (0..1) and whether it is lit.
    readonly property var bars: VoiceModel.meterBars(meter.levels, meter.active)

    Row {
      anchors.centerIn: parent
      height: meter.height
      spacing: Math.max(2, Style.space(3))
      Repeater {
        model: meter.bars
        delegate: Rectangle {
          required property var modelData
          y: parent ? Math.round((parent.height - height) / 2) : 0
          width: Math.max(3, Style.space(4))
          height: Math.max(width, Math.round((parent ? parent.height : 0) * modelData.value))
          radius: Math.min(Style.cornerRadius, width / 2)
          color: modelData.lit ? Commons.Color.urgent : Commons.Color.muted
        }
      }
    }
  }

  component SectionLabel: Text {
    width: parent ? parent.width : 0
    topPadding: Style.spacing.md
    textFormat: Text.PlainText
    color: Commons.Color.popups.text
    opacity: 0.7
    font.family: Style.font.family
    font.pixelSize: Readable.px(Style.font.caption)
    font.bold: true
  }

  // A speech model: its name and line, a tap chooses it (downloading it
  // first when it isn't there).
  component ModelRow: BorderSurface {
    id: modelItem
    property string title: ""
    property string line: ""
    property string badge: ""
    property bool chosen: false
    signal tapped()
    readonly property int touchSize: Math.max(44, Style.space(56))
    height: modelItem.touchSize
    radius: Style.cornerRadius
    opacity: enabled || chosen ? 1 : 0.6
    color: modelTouch.pressed ? Style.pressedFillFor(Commons.Color.popups.text, Commons.Color.accent)
      : modelItem.chosen ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
      : Style.normalFillFor(Commons.Color.popups.text, Commons.Color.accent)
    borderSpec: Border.controlSpec(modelItem.chosen ? "selected" : "normal", Commons.Color.popups.text, Commons.Color.accent)
    Accessible.role: Accessible.RadioButton
    Accessible.name: modelItem.title + ", " + modelItem.line
    Accessible.checked: modelItem.chosen

    Column {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.right: modelBadge.left
      anchors.rightMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: modelItem.title
        color: modelItem.chosen ? Commons.Color.accent : Commons.Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: modelItem.line
        color: Commons.Color.popups.text
        opacity: 0.7
        font.family: Style.font.family
        font.pixelSize: Readable.px(Style.font.caption)
        elide: Text.ElideRight
      }
    }

    Text {
      id: modelBadge
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: modelItem.badge
      color: modelItem.chosen ? Commons.Color.accent : Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Readable.px(Style.font.caption)
    }

    MouseArea {
      id: modelTouch
      anchors.fill: parent
      enabled: modelItem.enabled
      onClicked: modelItem.tapped()
    }
  }

  // One switch in the settings: the caller binds checked and saves on
  // toggled (inline components can't see root).
  component SettingRow: Item {
    id: settingItem
    property string title: ""
    property string note: ""
    property bool checked: false
    signal toggled()
    width: parent ? parent.width : 0
    height: Math.max(Math.max(44, Style.space(48)), settingText.implicitHeight + Style.spacing.md * 2)
    Accessible.role: Accessible.CheckBox
    Accessible.name: settingItem.title
    Accessible.checked: settingItem.checked

    Column {
      id: settingText
      anchors.left: parent.left
      anchors.right: settingSwitch.left
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: settingItem.title
        color: Commons.Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
      }
      Text {
        width: parent.width
        visible: settingItem.note !== ""
        textFormat: Text.PlainText
        text: settingItem.note
        color: Commons.Color.popups.text
        opacity: 0.7
        font.family: Style.font.family
        font.pixelSize: Readable.px(Style.font.caption)
        wrapMode: Text.Wrap
      }
    }

    // The whole row toggles, as on Android; the switch shows the state.
    MouseArea {
      anchors.fill: parent
      onClicked: settingItem.toggled()
    }

    ToggleSwitch {
      id: settingSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: settingItem.checked
      interactive: false
    }
  }

  component AgentChip: BorderSurface {
    id: chip
    property string name: ""
    property string icon: ""
    signal tapped()
    readonly property int touchSize: Math.max(44, Style.space(48))
    height: chip.touchSize
    width: chipRow.implicitWidth + Style.spacing.controlPaddingX * 2
    radius: Style.cornerRadius
    color: chipTouch.pressed ? Style.pressedFillFor(Commons.Color.popups.text, Commons.Color.accent)
      : Style.normalFillFor(Commons.Color.popups.text, Commons.Color.accent)
    borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.spacing.md

      Image {
        anchors.verticalCenter: parent.verticalCenter
        // A fixed size: a width that followed `visible` changed sourceSize,
        // which reloaded the image, which hid it again (a binding loop).
        visible: chip.icon !== "" && status === Image.Ready
        width: Style.space(18)
        height: Style.space(18)
        sourceSize.width: Style.space(18) * 3
        sourceSize.height: Style.space(18) * 3
        fillMode: Image.PreserveAspectFit
        source: chip.icon
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: chip.name
        color: Commons.Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        // nf-md-chevron_down
        text: "󰅀"
        color: Commons.Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    MouseArea {
      id: chipTouch
      anchors.fill: parent
      onClicked: chip.tapped()
    }
  }

  // Inline components have their own scope: no `root` in here.
  component GlyphTap: BorderSurface {
    id: glyphItem
    property string glyph: ""
    property bool framed: false
    property color foreground: Commons.Color.popups.text
    readonly property int touchSize: Math.max(44, Style.space(48))
    signal tapped()
    width: glyphItem.touchSize + (glyphItem.framed ? Style.space(8) : 0)
    height: glyphItem.touchSize
    radius: Style.cornerRadius
    color: glyphTouch.pressed ? Style.pressedFillFor(glyphItem.foreground, Commons.Color.accent)
      : glyphItem.framed ? Style.normalFillFor(glyphItem.foreground, Commons.Color.accent) : "transparent"
    borderSpec: glyphItem.framed ? Border.controlSpec("normal", glyphItem.foreground, Commons.Color.accent) : Border.none()

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: glyphItem.glyph
      color: glyphItem.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.iconLarge
    }

    MouseArea {
      id: glyphTouch
      anchors.fill: parent
      onClicked: glyphItem.tapped()
    }
  }

  // The update sheet's action button; `tone` colours a primary one (the
  // recording colour on Stop and Done), `small` for the secondary row.
  component SheetAction: BorderSurface {
    id: actionItem
    property string label: ""
    property bool primary: false
    property bool small: false
    property color tone: Commons.Color.accent
    property color foreground: Commons.Color.popups.text
    readonly property int touchSize: Math.max(44, Style.space(48))
    signal tapped()
    height: visible ? actionItem.touchSize : 0
    radius: Style.cornerRadius
    opacity: enabled ? 1 : 0.45
    color: actionTouch.pressed ? Style.pressedFillFor(actionItem.foreground, actionItem.tone)
      : actionItem.primary ? Util.alpha(actionItem.tone, Style.selectedFillAlpha)
      : Style.normalFillFor(actionItem.foreground, Commons.Color.accent)
    borderSpec: actionItem.primary ? Border.flat(actionItem.tone, Math.max(1, Style.normalBorderWidth))
      : Border.controlSpec("normal", actionItem.foreground, Commons.Color.accent)

    Text {
      anchors.centerIn: parent
      width: parent.width - Style.spacing.lg * 2
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: actionItem.label
      color: actionItem.primary ? actionItem.tone : actionItem.foreground
      font.family: Style.font.family
      font.pixelSize: actionItem.small ? Style.font.body : Style.font.subtitle
      font.bold: !actionItem.small
      elide: Text.ElideRight
    }

    MouseArea {
      id: actionTouch
      anchors.fill: parent
      enabled: actionItem.enabled
      onClicked: actionItem.tapped()
    }
  }

  component InfoRow: Row {
    id: infoItem
    property string glyph: ""
    property string text: ""
    property bool urgent: false
    property color foreground: Commons.Color.popups.text
    spacing: Style.spacing.lg

    Text {
      id: infoGlyph
      textFormat: Text.PlainText
      text: infoItem.glyph
      color: infoItem.urgent ? Commons.Color.urgent : infoItem.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.iconLarge
    }

    // Top-aligned, so a warning that wraps grows downwards only.
    Text {
      width: infoItem.width - infoGlyph.width - infoItem.spacing
      textFormat: Text.PlainText
      text: infoItem.text
      color: infoItem.urgent ? Commons.Color.urgent : infoItem.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
    }
  }
}
