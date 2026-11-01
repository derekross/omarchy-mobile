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

// Voice input for the phone (docs/VOICE-PLAN.md): one voice bar, through
// Voxtype's user daemon (voxtype.service, Omarchy's Install > AI >
// Dictation). Speech is turned into text on the phone.
//
// The ways in, as on Android: a hold on the pill (omamobile.launcher: the
// pill over an app, the search pill on the home screen), the keyboard's
// Mic key (squeekboard's XF86Dictate, bound in hypr/phone.lua), Power +
// Volume Up (omamobile-keys, when turned on) and the Dictation tile in
// quick settings (`omamobile-voice start`). All open the same bar.
//
// The bar rises above the keyboard when it is up, else above the bottom
// bar: the destination chip (where the words go; a tap lists the others),
// a pulsing dot and the time, the level from voxtype-audio-bridge, Cancel
// and "Done · <verb>". The destination follows what is in front: an
// agent's terminal (org.omarchy.agent), Send to the agent (typed into its
// prompt, then Enter); any other app, Type here; the home screen, Ask the
// agent (a new prompt). Copy to clipboard and Search apps work anywhere.
// Only Ask has a second step: the transcript to check and edit, in the
// theme's warning colour, with the full-permissions warning and Discard /
// Again / Ask. Everything else is delivered the moment it is text.
//
// Every recording is `voxtype record start --no-osd --file=<transcript>`
// (VoiceModel.startArgv): Voxtype's GTK overlay would sit over the bottom
// bar, and with the transcript in a file the shell delivers it to whatever
// destination is chosen when Done is tapped (wtype into the focused app,
// which keeps the keyboard focus because the bar never takes it; wl-copy;
// the launcher's search; the launcher's agent prompt). The daemon's state
// file says what it is doing; the screen stays on while the bar listens or
// transcribes (an idle inhibitor). The model is the daemon's own
// (omamobile-setup-user sets tiny.en once it is downloaded). Settings
// (`omamobile-voice settings`, the Dictation tile's long press, Setup >
// Voice): the model, Power + Volume Up, and the check before Ask, in
// ~/.config/omamobile/voice.json.
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "omamobile.voice"

  // ---------------------------------------------------------------- state

  // idle | starting | listening | transcribing | result | error
  property string phase: "idle"
  // The bar started the recording under way (one started elsewhere, such
  // as a desktop hotkey, shows nothing).
  property bool mine: false
  // type | agent | ask | copy | search
  property string dest: "type"
  property bool chooserOpen: false
  property bool pushToTalk: false
  property bool fingerDown: false
  property real pressedAt: 0
  property bool pendingStop: false
  property real listenStart: 0
  property real elapsed: 0
  property real spoke: 0
  property var levels: []
  property real lastLevelAt: 0
  property string transcript: ""
  property string errorText: ""
  property int readTries: 0

  readonly property bool busy: phase === "starting" || phase === "listening" || phase === "transcribing"
  readonly property bool listening: phase === "listening"
  readonly property bool barShown: busy || phase === "result" || phase === "error"
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string transcriptPath: VoiceModel.transcriptPath(runtimeDir)
  readonly property string statePath: runtimeDir + "/voxtype/state"
  readonly property bool appOnScreen: !!Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.toplevels.values.length > 0
  // The app in front is an agent's terminal (Omarchy's one class for them).
  readonly property bool agentInFront: appOnScreen && !!ToplevelManager.activeToplevel
    && VoiceModel.isAgent(ToplevelManager.activeToplevel.appId)
  readonly property var choices: VoiceModel.destinations(appOnScreen, agentInFront)

  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int pad: Style.spacing.panelPadding
  readonly property color foreground: Commons.Color.popups.text
  // Recording is the theme's urgent colour; the check before Ask its warning
  // colour (colors.toml's yellow), or the accent when the theme has none.
  readonly property color recording: Commons.Color.urgent
  property string warningHex: ""
  readonly property color warning: warningHex !== "" ? warningHex : Commons.Color.accent

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.warningHex = VoiceModel.themeWarning(text())
    onLoadFailed: root.warningHex = ""
  }

  // The agent, as the launcher reads it: Omarchy's default agent
  // (omarchy-default-agent writes ~/.config/omarchy/defaults/agent), unset
  // until the user picks one.
  property string agentId: ""
  readonly property string agentName: LauncherModel.agentName(agentId)
  readonly property bool hasAgent: agentId.length > 0

  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/defaults/agent"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.agentId = LauncherModel.agentId(text())
    onLoadFailed: root.agentId = ""
  }

  // Where the bar sits on the home screen: above the dock, which reserves
  // nothing (omamobile.launcher, through its DrawerLink.js). Over an app the
  // home strip reserves its height, and the keyboard its own, so the bar
  // lands above them without help.
  Loader {
    id: drawerLink
    source: Qt.resolvedUrl("../omamobile.launcher/DrawerLinkClient.qml")
  }
  readonly property var launcher: drawerLink.item ? drawerLink.item.drawer : null
  readonly property int dockGap: launcher && launcher.dockShown === true && launcher.oskOpen !== true
    && launcher.opened !== true ? Number(launcher.dockHeight) || 0 : 0

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

  // ---------------------------------------------------------------- host API

  // The host's panel is the settings sheet: `shell summon omamobile.voice
  // '{"page":"settings"}'`. Any other summon starts the bar and gives the
  // panel straight back, as the keyboard plugin does.
  property bool opened: false

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") || ({}) } catch (e) { payload = ({}) }
    if (payload.page === "settings") {
      opened = true
      settingsOpen = true
      refreshModels()
      return
    }
    Qt.callLater(function() {
      if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    })
    if (!busy) listen(false)
  }

  function close() {
    opened = false
    settingsOpen = false
  }

  function dismissSettings() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function openSettings() {
    if (shell && typeof shell.summon === "function") shell.summon(pluginId, JSON.stringify({ page: "settings" }))
    else open(JSON.stringify({ page: "settings" }))
    return "ok"
  }

  // `omamobile-voice snapshot`
  function snapshot() {
    return JSON.stringify({ phase: phase, mine: mine, dest: dest, choices: choices, chooser: chooserOpen,
                            pushToTalk: pushToTalk, elapsed: Math.floor(elapsed), agent: agentId,
                            agentInFront: agentInFront, appOnScreen: appOnScreen, chars: transcript.length,
                            model: modelId, settings: settings })
  }

  // ---------------------------------------------------------------- calls (VoiceLink.js, IPC, omamobile-voice)

  // `omamobile-voice toggle`: start, or finish what is under way (Done), or
  // close a result.
  function toggle() {
    if (busy) return done()
    if (phase === "result" || phase === "error") { reset(); return "closed" }
    listen(false)
    return "listening"
  }

  function start() {
    if (busy) return "busy"
    listen(false)
    return "listening"
  }

  // A held key (the keyboard's Mic, Power + Volume Up): push-to-talk;
  // letting go stops, a short press keeps listening, and a press while the
  // bar listens is Done.
  function press() {
    if (busy) return mine ? done() : "busy"
    listen(true)
    return "listening"
  }

  function release() {
    if (!mine || !fingerDown) return "idle"
    fingerDown = false
    if (VoiceModel.releaseStops(phase, Date.now() - pressedAt)) return done()
    pushToTalk = false
    return "listening"
  }

  // Power + Volume Up (omamobile-keys), when turned on in the settings.
  function keyPress() {
    if (!settings.powerVolumeUp) return "off"
    return press()
  }

  function keyRelease() {
    return release()
  }

  // Done: stop listening; the transcript goes where the chip says.
  function done() {
    chooserOpen = false
    if (phase === "starting") { pendingStop = true; return "pending" }
    if (phase !== "listening") return "idle"
    Quickshell.execDetached(VoiceModel.STOP_ARGV)
    return "ok"
  }

  function cancel() {
    if (busy && mine) Quickshell.execDetached(VoiceModel.CANCEL_ARGV)
    reset()
    return "ok"
  }

  function choose(d) {
    if (choices.indexOf(d) >= 0) dest = d
    chooserOpen = false
  }

  // ---------------------------------------------------------------- recording

  function listen(hold) {
    if (busy) return
    dest = VoiceModel.contextDestination(appOnScreen, agentInFront)
    mine = true
    phase = "starting"
    chooserOpen = false
    errorText = ""
    transcript = ""
    editor.text = ""
    pushToTalk = hold
    fingerDown = hold
    pressedAt = Date.now()
    pendingStop = false
    levels = []
    elapsed = 0
    startProc.running = false
    startProc.command = VoiceModel.startArgv(transcriptPath)
    startProc.running = true
    startTimeout.restart()
    stateFile.reload()
  }

  function reset() {
    phase = "idle"
    mine = false
    chooserOpen = false
    pendingStop = false
    pushToTalk = false
    fingerDown = false
    levels = []
    startTimeout.stop()
    editor.focus = false
  }

  function fail(text) {
    startTimeout.stop()
    phase = "error"
    errorText = text
    pushToTalk = false
    fingerDown = false
  }

  function handleVox(text) {
    var vox = VoiceModel.voxState(text)
    var was = phase
    var r = VoiceModel.step(phase, mine, vox)
    if (mine && VoiceModel.ticks(was, r.phase)) Quickshell.execDetached(VoiceModel.HAPTIC_ARGV)
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
    if (was === "listening" && r.phase !== "listening") spoke = elapsed
    phase = r.phase
    if (r.read) {
      readTries = 0
      readTimer.restart()
    }
  }

  function applyTranscript(text) {
    var r = VoiceModel.afterRead(dest, text, settings.confirmSend)
    if (r.phase === "error" && readTries < 4) {
      readTries++
      readTimer.restart()
      return
    }
    transcript = r.text
    editor.text = r.text
    errorText = r.error
    if (r.argv) Quickshell.execDetached(r.argv)
    if (r.send) sendAsk(r.text)
    phase = r.phase
    if (r.phase === "idle") reset()
  }

  // Ask: the launcher's prompt (a terminal with the agent and the text as
  // its first prompt), or Omarchy's agent picker when none is chosen yet.
  function sendAsk(text) {
    var t = VoiceModel.cleanTranscript(text)
    if (!t) return
    if (hasAgent) Util.execArgv(LauncherModel.promptArgv(t))
    else Util.execArgv(LauncherModel.PICK_AGENT_ARGV)
  }

  function askNow() {
    var t = VoiceModel.cleanTranscript(editor.text)
    reset()
    sendAsk(t)
  }

  function again() {
    var keep = dest
    reset()
    listen(false)
    dest = keep
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
    running: root.listening && root.mine
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
    function toggle(): string { return root.toggle() }
    function start(): string { return root.start() }
    function done(): string { return root.done() }
    function cancel(): string { return root.cancel() }
    function press(): string { return root.press() }
    function release(): string { return root.release() }
    function keyPress(): string { return root.keyPress() }
    function keyRelease(): string { return root.keyRelease() }
    function openSettings(): string { return root.openSettings() }
    function snapshot(): string { return root.snapshot() }
  }

  Component.onCompleted: VoiceLink.publish(root)
  Component.onDestruction: VoiceLink.withdraw(root)

  // ---------------------------------------------------------------- the voice bar

  PanelWindow {
    id: barWindow

    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: root.barShown
    anchors { bottom: true; left: true; right: true }
    margins { bottom: root.dockGap }
    implicitHeight: barCard.implicitHeight + Style.gapsOut * 2
    // It reserves its height, so the app's field ends above the bar rather
    // than under it.
    exclusionMode: ExclusionMode.Auto
    color: "transparent"
    WlrLayershell.namespace: "omamobile-voice-bar"
    WlrLayershell.layer: WlrLayer.Top
    // Never the keyboard while listening: the words are typed into the app,
    // which must keep the focus. The check before Ask edits its own text.
    WlrLayershell.keyboardFocus: root.phase === "result" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    IdleInhibitor {
      window: barWindow
      enabled: root.busy
    }

    BorderSurface {
      id: barCard
      objectName: "voiceBar"
      anchors.fill: parent
      anchors.margins: Style.gapsOut
      implicitHeight: barColumn.implicitHeight + Style.spacing.xl * 2
      color: Commons.Color.popups.background
      borderSpec: Border.flat(root.phase === "result" ? root.warning
                              : root.phase === "error" ? Commons.Color.urgent
                              : root.busy ? root.recording : Commons.Color.popups.border,
                              Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      Column {
        id: barColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.spacing.xl
        spacing: Style.spacing.lg

        // ---------- the destination and the time
        Item {
          width: parent.width
          height: root.touchSize

          DestChip {
            id: destChip
            objectName: "destChip"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            maxWidth: parent.width - timeRow.width - Style.spacing.lg
            label: VoiceModel.destinationLabel(root.dest, root.agentName)
            glyph: root.dest === "type" ? "󰌌" : root.dest === "copy" ? "󰆏" : root.dest === "search" ? "󰍉" : "󰚩"
            tone: root.phase === "result" ? root.warning : root.foreground
            open: root.chooserOpen
            enabled: root.busy
            Accessible.name: "Destination: " + label + ". Change"
            onTapped: root.chooserOpen = !root.chooserOpen
          }

          Row {
            id: timeRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.md

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.busy
              width: Style.space(8)
              height: width
              radius: width / 2
              color: root.listening ? root.recording : Commons.Color.accent
              SequentialAnimation on opacity {
                running: root.listening
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.45; duration: 600 }
                NumberAnimation { from: 0.45; to: 1; duration: 600 }
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.phase === "result" ? VoiceModel.clock(root.spoke) + " · " + VoiceModel.modelShort(root.modelId)
                : root.busy ? VoiceModel.elapsedText(root.elapsed) : ""
              color: root.listening ? root.recording : root.foreground
              opacity: root.listening ? 1 : 0.7
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: root.listening
            }
          }
        }

        // ---------- the level
        Item {
          width: parent.width
          height: Style.space(28)
          visible: root.busy

          LevelMeter {
            anchors.left: parent.left
            anchors.right: statusWord.left
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            levels: root.levels
            active: root.listening
          }

          Text {
            id: statusWord
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: VoiceModel.statusText(root.phase)
            color: root.foreground
            opacity: 0.7
            font.family: Style.font.family
            font.pixelSize: Readable.px(Style.font.caption)
          }
        }

        Text {
          width: parent.width
          visible: root.busy && text !== ""
          textFormat: Text.PlainText
          text: VoiceModel.destinationHint(root.dest)
          color: root.foreground
          opacity: 0.8
          font.family: Style.font.family
          font.pixelSize: Readable.px(Style.font.caption)
          wrapMode: Text.Wrap
        }

        // ---------- where else the words can go
        Column {
          id: chooser
          objectName: "destChooser"
          width: parent.width
          visible: root.busy && root.chooserOpen
          spacing: 0

          Repeater {
            model: root.choices
            delegate: OptionRow {
              required property var modelData
              width: chooser.width
              objectName: "dest-" + modelData
              title: VoiceModel.destinationLabel(modelData, root.agentName)
              note: VoiceModel.destinationNote(modelData)
              chosen: modelData === root.dest
              onTapped: root.choose(modelData)
            }
          }
        }

        // ---------- the check before Ask
        Flickable {
          id: editFlick
          objectName: "transcript"
          width: parent.width
          height: visible ? Math.min(Style.space(150), Math.max(Style.space(88), editor.implicitHeight)) : 0
          visible: root.phase === "result"
          contentHeight: editor.implicitHeight
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
            font.pixelSize: Style.font.subtitle
            leftPadding: Style.spacing.controlPaddingX + Math.max(1, Style.space(2))
            rightPadding: leftPadding
            topPadding: Style.spacing.lg
            bottomPadding: Style.spacing.lg
            background: BorderSurface {
              color: Style.controlFill(editor.activeFocus, false, root.foreground, Commons.Color.accent)
              borderSpec: Border.controlSpec(editor.activeFocus ? "focus" : "normal", root.foreground, Commons.Color.accent)
              radius: Style.cornerRadius
            }
          }
        }

        InfoRow {
          objectName: "permissionWarning"
          width: parent.width
          visible: root.phase === "result" && root.hasAgent
          glyph: "󰀦"
          text: VoiceModel.permissionText(root.agentName)
          foreground: root.warning
        }

        InfoRow {
          width: parent.width
          visible: root.phase === "error"
          glyph: "󰍭"
          text: root.errorText
          urgent: true
        }

        // ---------- the buttons
        Row {
          width: parent.width
          height: root.touchSize
          spacing: Style.spacing.lg
          layoutDirection: Qt.RightToLeft
          visible: root.busy

          SheetAction {
            objectName: "done"
            width: (parent.width - parent.spacing) * 2 / 3
            label: root.phase === "transcribing" ? "Turning it into text..." : "Done · " + VoiceModel.doneVerb(root.dest)
            primary: true
            tone: root.recording
            enabled: root.phase === "listening" || root.phase === "starting"
            onTapped: root.done()
          }

          SheetAction {
            width: (parent.width - parent.spacing) / 3
            label: "Cancel"
            onTapped: root.cancel()
          }
        }

        Row {
          width: parent.width
          height: root.touchSize
          spacing: Style.spacing.lg
          layoutDirection: Qt.RightToLeft
          visible: root.phase === "result"

          SheetAction {
            objectName: "ask"
            width: (parent.width - parent.spacing * 2) / 3
            label: root.hasAgent ? "Ask" : "Choose agent"
            primary: true
            tone: root.warning
            enabled: !root.hasAgent || VoiceModel.cleanTranscript(editor.text).length > 0
            onTapped: root.askNow()
          }

          SheetAction {
            width: (parent.width - parent.spacing * 2) / 3
            label: "Again"
            onTapped: root.again()
          }

          SheetAction {
            width: (parent.width - parent.spacing * 2) / 3
            label: "Discard"
            onTapped: root.reset()
          }
        }

        Row {
          width: parent.width
          height: root.touchSize
          spacing: Style.spacing.lg
          layoutDirection: Qt.RightToLeft
          visible: root.phase === "error"

          SheetAction {
            width: (parent.width - parent.spacing) / 2
            label: "Try again"
            primary: true
            onTapped: root.again()
          }

          SheetAction {
            width: (parent.width - parent.spacing) / 2
            label: "Close"
            onTapped: root.reset()
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- the settings sheet

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  PanelWindow {
    id: sheetWindow

    visible: root.opened || root.reveal > 0
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-voice"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
      opacity: root.reveal
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismissSettings()
    }

    BorderSurface {
      id: card
      objectName: "voiceCard"

      x: Style.gapsOut
      width: parent.width - Style.gapsOut * 2
      height: parent.height - Style.gapsOut * 2
      y: Style.gapsOut + Math.round((1 - root.reveal) * Style.space(60))
      opacity: root.reveal
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      padding: root.pad

      MouseArea { anchors.fill: parent }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Item {
          id: headerRow
          objectName: "voiceHeader"
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.touchSize

          Text {
            anchors.left: parent.left
            anchors.right: settingsClose.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Voice"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          GlyphTap {
            id: settingsClose
            objectName: "settingsClose"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰅖"
            Accessible.name: "Close"
            onTapped: root.dismissSettings()
          }
        }

        Flickable {
          id: settingsFlick
          objectName: "voiceSettings"
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
              text: "Speech is turned into text on this phone. Nothing you say leaves it. Hold the pill at the bottom of the screen to talk (double-tap it for the keyboard), or use the keyboard's Mic key or the Dictation tile."
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

            SectionLabel { text: "More" }

            SettingRow { objectName: "setting-powerVolumeUp"; title: "Power + Volume Up"; note: "hold both to talk; not on the lock screen"; checked: root.settings.powerVolumeUp === true; onToggled: root.setSetting("powerVolumeUp", !checked) }
            SettingRow { objectName: "setting-confirmSend"; title: "Check before asking the agent"; note: "off: on the home screen, what you say goes to the agent as soon as it is text"; checked: root.settings.confirmSend === true; onToggled: root.setSetting("confirmSend", !checked) }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- pieces

  // The destination chip: what it does, and a chevron for the others.
  component DestChip: BorderSurface {
    id: chip
    property string label: ""
    property string glyph: ""
    property color tone: Commons.Color.popups.text
    property bool open: false
    // The widest it may be (the caller's room); the label elides past it.
    property real maxWidth: 1000
    signal tapped()
    readonly property int touchSize: Math.max(44, Style.space(48))
    height: chip.touchSize
    width: chipRow.implicitWidth + Style.spacing.controlPaddingX * 2
    radius: Style.cornerRadius
    color: chipTouch.pressed ? Style.pressedFillFor(chip.tone, Commons.Color.accent)
      : Style.normalFillFor(chip.tone, Commons.Color.accent)
    borderSpec: Border.flat(Util.alpha(chip.tone, 0.5), Math.max(1, Style.normalBorderWidth))
    Accessible.role: Accessible.Button

    Row {
      id: chipRow
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      spacing: Style.spacing.md

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: chip.glyph
        color: chip.tone
        font.family: Style.font.family
        font.pixelSize: Style.font.iconLarge
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(implicitWidth, chip.maxWidth - Style.spacing.controlPaddingX * 2 - Style.font.iconLarge * 2 - Style.spacing.md * 3))
        textFormat: Text.PlainText
        text: chip.label
        color: chip.tone
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: chip.enabled
        textFormat: Text.PlainText
        // nf-md-chevron_down / up
        text: chip.open ? "󰅃" : "󰅀"
        color: chip.tone
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    MouseArea {
      id: chipTouch
      anchors.fill: parent
      enabled: chip.enabled
      onClicked: chip.tapped()
    }
  }

  // One destination in the chip's list: its name, and what it does.
  component OptionRow: Rectangle {
    id: optionItem
    property string title: ""
    property string note: ""
    property bool chosen: false
    signal tapped()
    height: Math.max(44, Style.space(44))
    radius: Style.cornerRadius
    color: optionTouch.pressed ? Style.pressedFillFor(Commons.Color.popups.text, Commons.Color.accent)
      : optionItem.chosen ? Commons.Color.menu.selectedBackground : "transparent"
    Accessible.role: Accessible.RadioButton
    Accessible.name: optionItem.title
    Accessible.checked: optionItem.chosen

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.right: optionNote.left
      anchors.rightMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: optionItem.title
      color: optionItem.chosen ? Commons.Color.menu.selectedText : Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      id: optionNote
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: optionItem.note
      color: Commons.Color.popups.text
      opacity: 0.7
      font.family: Style.font.family
      font.pixelSize: Readable.px(Style.font.caption)
    }

    MouseArea {
      id: optionTouch
      anchors.fill: parent
      onClicked: optionItem.tapped()
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
