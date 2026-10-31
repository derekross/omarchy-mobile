// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import qs.services as OmarchyServices
import "LauncherModel.js" as LauncherModel
import "Readable.js" as Readable
import "DrawerLink.js" as DrawerLink

// The phone's home surface, after Omalauncher: one bar at the bottom of the
// screen that is app search, app grid and coding-agent prompt at once.
//
// Collapsed, it is a dock holding a single search pill. Tapping it raises the
// app drawer with the input focused. Typing filters the grid; text that reads
// like a sentence (or matches no app) offers "Ask <agent>" (the user's
// Omarchy default agent) instead, and Enter
// takes whichever is on top: the first app, or a terminal running the agent
// with the text as its first prompt.
//
// Apps come from Omarchy's application library (services/AppLibrary.qml: the
// same entries, hidden-entry filters, icons and launch path as the Omarchy
// menu). The host shares its instance with `menu` plugins; see the Loader
// below for why this one is a `panel` that runs its own for now.
Item {
  id: root

  // Injected by the host.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "omamobile.launcher"
  readonly property var appLibrary: shell && shell.appLibrary ? shell.appLibrary : localLibrary.item

  // The host hands its application library only to `menu` plugins, and in
  // this Omarchy build a third-party menu loses its whole shell facade on the
  // next config change (phone/plugins/README.md has the details). So the
  // launcher declares `panel` and runs Omarchy's own AppLibrary type here: the
  // same entries, hidden-entry filters, icon index and launch path, in a
  // second instance. If the host ever provides one, that wins.
  Loader {
    id: localLibrary
    active: !!root.shell && !root.shell.appLibrary
    sourceComponent: Component { OmarchyServices.AppLibrary { } }
  }

  // `opened` is the drawer; the dock is always on screen.
  property bool opened: false
  property string query: ""
  property var apps: []
  property int appsRevision: 0

  // ---------------------------------------------------------------- settings

  property var shellConfig: ({})
  readonly property var settings: LauncherModel.mergedSettings(
    manifest && manifest.settings ? manifest.settings.defaults : ({}), shellConfig, pluginId)

  // The coding agent is the user's choice, made the Omarchy way:
  // omarchy-default-agent stores it in ~/.config/omarchy/defaults/agent and
  // leaves it unset until the user picks one. Read it live so a choice made
  // in Omarchy's menu shows up here at once.
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

  readonly property int columns: Math.max(3, Math.min(6, Number(settings.columns) || 4))
  // The drawer's columns for a grid this wide: `columns` across the
  // screen's shorter side, more of the same width on its side (TOUCH-PLAN
  // 2.4), so the icons keep their size.
  // The screen (the offscreen renders put a stand-in here).
  property var screenInfo: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  function drawerColumns(gridWidth) {
    var shortSide = screenInfo && screenInfo.width > 0 && screenInfo.height > 0 ? Math.min(screenInfo.width, screenInfo.height) : 0
    return LauncherModel.drawerColumns(columns, gridWidth, shortSide, Style.spacing.lg)
  }
  readonly property int sentenceWords: Math.max(2, Number(settings.sentenceWords) || 3)

  // Plugin entries in shell.json carry their settings inline, but the host
  // only hands those to bar widgets, so read our own entry from the file.
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.shellConfig = JSON.parse(text() || "{}") } catch (e) { root.shellConfig = ({}) }
    }
  }

  // ---------------------------------------------------------------- results

  readonly property bool promptMode: LauncherModel.looksLikePrompt(query, apps.length, sentenceWords)
  readonly property bool hasQuery: query.trim().length > 0

  function refreshApps() {
    // sortedEntries() yields ranked rows of { entry, score, ... }; the grid
    // wants the DesktopEntry objects themselves.
    var rows = appLibrary ? appLibrary.sortedEntries(query) : []
    var entries = []
    for (var i = 0; i < rows.length; i++)
      if (rows[i] && rows[i].entry) entries.push(rows[i].entry)
    apps = entries
  }

  onQueryChanged: refreshApps()
  onAppLibraryChanged: refreshApps()

  Connections {
    target: root.appLibrary
    ignoreUnknownSignals: true
    function onAppsChanged() { root.refreshApps() }
  }

  // ---------------------------------------------------------------- actions

  // Not AppLibrary.launch: omamobile-launch starts the app the same way
  // (uwsm-app -- gtk-launch) on a new empty workspace, or focuses it on its
  // own if it is already open. Omarchy's "Launching…" feedback stays.
  function launchApp(entry) {
    if (!entry || !entry.id) return
    if (appLibrary && typeof appLibrary.beginLaunchFeedback === "function")
      appLibrary.beginLaunchFeedback(appLibrary.entryName(entry))
    Quickshell.execDetached(LauncherModel.appArgv(entry.id))
    dismiss()
  }

  // Long-press in the drawer: put the app on the home screen
  // (omamobile.home), on the page it shows, and go there, as on Android.
  // Through IPC, like the switcher: a plugin only summons its own panels.
  function addToHome(entry) {
    if (!entry) return
    Quickshell.execDetached(["qs", "ipc", "-p", Quickshell.shellDir, "call", "shell", "call",
                             "omamobile.home", "addApp", String(entry.id)])
    dismiss()
  }

  function askAgent(prompt) {
    var text = String(prompt || "").trim()
    if (!text) return "empty"
    if (!hasAgent) {
      Util.execArgv(LauncherModel.PICK_AGENT_ARGV)
      dismiss()
      return "pick-agent"
    }
    Util.execArgv(LauncherModel.promptArgv(text))
    dismiss()
    return "ok"
  }

  // Enter: the agent when the text reads as a prompt, else the top app.
  function activate() {
    if (!hasQuery) return
    if (promptMode || apps.length === 0) askAgent(query)
    else launchApp(apps[0])
  }

  // ---------------------------------------------------------------- lifecycle

  // `shell summon omamobile.launcher '{"query":"..."}'` opens the
  // drawer, optionally pre-filled.
  //
  // '{"gesture":true}' is the home screen's swipe letting go past the point
  // that opens (gestureEnd below): the drawer carries on from under the
  // finger at the finger's speed, the dock stays until it is fully open,
  // and the search field waits for a tap, so no keyboard comes up, as on
  // Android. Any other open (a tap on the dock, IPC) focuses the field.
  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    var gesture = payload.gesture === true
    query = typeof payload.query === "string" ? payload.query : ""
    refreshApps()
    opened = true
    focusInputOnShow = !gesture
    if (!gesture) dockAway = true
    focusDrawer()
    settleTo(true, gesture ? gestureSpeed : 0)
    gestureSpeed = 0
  }

  // Host-initiated close (`shell hide`): the drawer slides away from where
  // it is, at the speed of the finger that let it go (dismiss(speed)).
  function close() {
    opened = false
    query = ""
    homeSwipe = false
    pulling = false
    dockAway = false
    settleTo(false, gestureSpeed)
    gestureSpeed = 0
  }

  function dismiss(speed) {
    gestureSpeed = Number(speed) || 0
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function expand() {
    if (shell && typeof shell.summon === "function") shell.summon(pluginId, "{}")
    else open("{}")
  }

  // `shell call omamobile.launcher <method> <arg>` entry points.
  function search(text) {
    if (!opened) expand()
    query = String(text || "")
    return JSON.stringify({ mode: promptMode ? "agent" : "apps", apps: apps.slice(0, 8).map(function(e) { return e.id }) })
  }

  function ask(prompt) { return askAgent(prompt) }

  function state() {
    return JSON.stringify({
      opened: opened,
      query: query,
      mode: hasQuery ? (promptMode ? "agent" : "apps") : "idle",
      apps: apps.length,
      library: shell && shell.appLibrary ? "host" : (appLibrary ? "local" : "none"),
      agent: agentId,
      command: hasAgent ? LauncherModel.promptArgv("<prompt>") : LauncherModel.PICK_AGENT_ARGV
    })
  }

  // Anything that opens a window (an app, the screensaver) closes the drawer,
  // as on Android: left open, it stays on top and keeps the keyboard focus.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root.opened && event && event.name === "openwindow") root.dismiss()
    }
  }

  // ---------------------------------------------------------------- geometry

  readonly property color foreground: Commons.Color.menu.text
  readonly property int touch: Math.max(44, Style.space(44))
  readonly property int inputHeight: Math.max(48, Style.space(48))
  readonly property int dockHeight: inputHeight + Style.spacing.xxl * 2
  // The dock shows on the home screen unless the drawer has the bottom
  // edge (dockAway, below).
  readonly property bool dockShown: !dockAway && !appOnScreen
  // No dock under an app: while the focused workspace has a window, the
  // dock (and its exclusive zone) goes away and only the home pill's thin
  // strip stays at the bottom, as on a phone. Home (an empty workspace)
  // brings the dock back.
  readonly property bool appOnScreen: !!Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.toplevels.values.length > 0

  // ---------------------------------------------------------------- drawer position

  // Where the drawer is: 0 closed (its sheet just below its window) to 1
  // open, as a share of the sheet's height, so the sheet's top stays under
  // a finger whatever size the window has. A finger moves it directly (no
  // animation in between, so it never lags); letting go settles it with a
  // short ease that starts at the finger's speed (settleTo,
  // LauncherModel.settleMs: 120-260 ms, Easing.OutCubic, no overshoot).
  property real progress: 0
  // A finger moves the drawer: the home screen's swipe up (gestureBegin to
  // gestureEnd, reached through DrawerLink.js), or a pull down in the
  // drawer (the handle, the header, empty space, or the grid at its top).
  property bool homeSwipe: false
  property bool pulling: false
  readonly property bool fingerOnDrawer: homeSwipe || pulling
  // The sheet is drawn: open, moving or under a finger. Closed, nothing in
  // the (always mapped) drawer window is.
  readonly property bool drawerShown: opened || fingerOnDrawer || progress > 0 || settle.running
  // This touch moved the drawer, so it is not also a tap on an app.
  property bool pullMoved: false
  // The first pixels a tap's jitter may move before a pull starts.
  readonly property int pullSlop: 8
  // The pulling finger's recent positions, for its speed at release.
  property var pullSamples: []
  // The time (ms) finger speeds are measured by; the tests set their own.
  property var clock: function() { return Date.now() }
  // The speed (px/s, down positive) a finger let the drawer go at, for the
  // settle that follows through the host's summon or hide.
  property real gestureSpeed: 0
  // The drawer has the bottom edge: set once it has slid fully open (at
  // once for a tap on the dock, whose keyboard needs the edge), cleared as
  // soon as it leaves the open place (a pull starts, or it closes). The
  // dock's coming and going resizes the home screen (it sits between the
  // bar and the dock), so it happens only while the sheet still covers the
  // home screen, never while the home screen shows: with the dock back only
  // after the drawer had slid away, the widgets jumped as it settled.
  property bool dockAway: false
  // What takes the keyboard focus when the drawer shows: the search field
  // after a tap on the dock, the sheet after a swipe (open above).
  property bool focusInputOnShow: true
  // The sheet's travel: the drawer window's height once it has one, the
  // screen's before the compositor's first configure.
  readonly property real travel: Math.max(1, drawer.height > 0 ? drawer.height
    : screenInfo && screenInfo.height > 0 ? screenInfo.height : 1000)

  NumberAnimation {
    id: settle
    target: root
    property: "progress"
    easing.type: Easing.OutCubic
    property bool toOpen: false
    onFinished: root.settled(settle.toOpen)
  }

  // Ease to open or closed from wherever the drawer is; speed is the
  // finger's (px/s), if one let it go.
  function settleTo(open, speed) {
    settle.stop()
    var to = open ? 1 : 0
    var ms = LauncherModel.settleMs((to - progress) * travel, travel, speed)
    settle.toOpen = open
    if (ms <= 0) {
      progress = to
      settled(open)
      return
    }
    settle.from = progress
    settle.to = to
    settle.duration = ms
    settle.start()
  }

  function settled(open) {
    dockAway = open
    // New icons (an app installed since): after the slide, so the grid
    // doesn't rebuild under it.
    if (open && appLibrary) appLibrary.refreshIcons()
  }

  function focusDrawer() {
    if (focusInputOnShow) input.forceActiveFocus()
    else sheet.forceActiveFocus()
  }

  // The home screen's swipe up (omamobile.home, through DrawerLink.js):
  // begin once its finger turns out to be going up, move with how far it
  // has gone up (px), end with its speed (px/s, negative up). The drawer
  // decides there whether it opens (LauncherModel.drawerEndsOpen: a fling,
  // or a quarter of the way) and then opens through the host, as a tap does.
  function gestureBegin() {
    if (opened) return false
    settle.stop()
    pulling = false
    homeSwipe = true
    return true
  }

  function gestureMove(px) {
    if (!homeSwipe) return
    progress = Math.max(0, Math.min(1, (Number(px) || 0) / travel))
  }

  function gestureEnd(speed) {
    if (!homeSwipe) return false
    homeSwipe = false
    var v = Number(speed) || 0
    if (!LauncherModel.drawerEndsOpen(progress, v, false)) {
      settleTo(false, v)
      return false
    }
    gestureSpeed = v
    if (shell && typeof shell.summon === "function") shell.summon(pluginId, JSON.stringify({ gesture: true }))
    else open(JSON.stringify({ gesture: true }))
    return true
  }

  Component.onCompleted: DrawerLink.publish(root)
  Component.onDestruction: DrawerLink.withdraw(root)

  // ---------------------------------------------------------------- dock

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData

      // Hidden while the drawer has the bottom edge (dockAway), so the
      // on-screen keyboard takes it and the drawer's input sits right above.
      visible: root.dockShown
      anchors { bottom: true; left: true; right: true }
      implicitHeight: root.dockHeight
      exclusionMode: ExclusionMode.Auto
      color: Commons.Color.bar.background
      WlrLayershell.namespace: "omamobile-dock"
      // Bottom, not Top: its exclusive zone still keeps windows off it, and
      // fullscreen windows (the screensaver, video) cover it. On Top it was
      // drawn over a fullscreen window when it re-mapped after the drawer.
      WlrLayershell.layer: WlrLayer.Bottom

      // Swipe up on the dock for recent apps (omamobile.switcher), as on
      // Android; a tap still opens the drawer.
      Item {
        anchors.fill: parent

        DragHandler {
          target: null
          xAxis.enabled: false
          property real swipeY: 0
          onActiveTranslationChanged: swipeY = activeTranslation.y
          onActiveChanged: {
            if (active) swipeY = 0
            // Through the CLI, like Omarchy's background does: a plugin may
            // only summon panels it owns, and the switcher is its own plugin.
            else if (swipeY < -24)
              Quickshell.execDetached(["omarchy-shell", "shell", "summon", "omamobile.switcher", "{}"])
          }
        }

        SearchPill {
          anchors.fill: parent
          anchors.margins: Style.spacing.xxl
          placeholder: (root.hasAgent ? "Search apps or ask " + root.agentName + "…" : "Search apps…")
          onTapped: root.expand()
        }
      }
    }
  }

  // ---------------------------------------------------------------- home indicator

  // Over an app, where the dock is hidden: a thin bar-coloured strip with a
  // pill, as on iOS. Swipe up on it to go home (the empty workspace, where
  // the dock is back); swipe up and hold (or a long swipe) for recent apps,
  // as on Android.
  //
  // It reserves its height (an exclusive zone), as Android's gesture-nav
  // inset does, so windows end above it: with no zone, the pill covered the
  // controls apps keep at the very bottom (the Phone app's Favorites,
  // Recents, Contacts and Keypad tabs). The zone goes with the window: the
  // strip isn't mapped on the home screen (the dock reserves its own height
  // there), with the drawer open, under the lock screen's keyboard, or for
  // a fullscreen window (video, the screensaver), which keeps the whole
  // screen. Under the lock it isn't drawn (no above_lock rule in
  // hypr/phone.lua), and the session lock's surface covers the whole screen
  // whatever is reserved.
  //
  // While the keyboard is up, the same window is the keyboard's strip, as
  // Android's gesture bar does: it stays mapped with the same height, and
  // only its content changes (the hide key appears). One window, so the
  // space reserved at the bottom never changes while an app is shown and
  // the app only resizes by squeekboard's own height. With two windows (one
  // over the app, one under the keyboard) both were mapped for a moment at
  // each swap, an app resized to that 88 px and missed the final configure,
  // and the home screen showed through a 44 px gap above the strip.
  //
  // The strip is on the Bottom layer. Hyprland arranges the layers that
  // reserve space from the Bottom layer up, so it takes the screen's bottom
  // edge first and squeekboard (the Top layer, which reserves its own
  // height) sits right above it, the way it sits above the dock on the home
  // screen. The strip covers no key, a swipe that starts in it stays its own
  // as the finger crosses the keyboard, and the shell's sheets on the Top
  // and Overlay layers draw over it and keep their touches. The back
  // gesture's edge strips (omamobile.back) end above it.
  //
  // The keyboard's own controls live here too, so nothing floats over the
  // app: a keyboard-down key at the strip's right end hides the keyboard
  // (only while it is up), and a double tap on the strip shows or hides it.
  // Both go through omamobile.keyboard's IPC (keyboardCall). The floating
  // hide button that plugin drew above the keyboard covered a terminal's
  // input line, and Send and Next before that.
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
    onExited: {
      root.oskOpen = false
      oskRestart.restart()
    }
  }

  Timer {
    id: oskRestart
    interval: 3000
    onTriggered: oskWatch.running = true
  }

  // A real fullscreen window (mode bit 2; a maximized one reports 1) on the
  // focused workspace, from the windows' last IPC data. Hyprland's events
  // arrive before its IPC answer does, so the re-read is debounced and the
  // value settles a moment later, as Omarchy's notifications do it.
  property int hyprRevision: 0
  readonly property bool fullscreenOnScreen: {
    var revision = hyprRevision
    var workspace = Hyprland.focusedWorkspace
    if (!workspace) return false
    var windows = workspace.toplevels ? workspace.toplevels.values : []
    for (var i = 0; i < windows.length; i++) {
      var ipc = windows[i].lastIpcObject || {}
      if ((Number(ipc.fullscreen) & 2) !== 0) return true
    }
    return false
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      switch (event.name) {
      case "fullscreen": case "openwindow": case "closewindow": case "movewindowv2":
      case "activewindowv2": case "workspacev2": case "focusedmonv2": case "changefloatingmode":
        hyprRefresh.restart()
      }
    }
  }

  Timer {
    id: hyprRefresh
    interval: 100
    onTriggered: { Hyprland.refreshToplevels(); hyprSettle.restart() }
  }

  Timer {
    id: hyprSettle
    interval: 250
    onTriggered: root.hyprRevision++
  }

  function goHome() {
    // As the switcher's Home: an empty workspace, then the home page.
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"empty\" })"])
    Quickshell.execDetached(["qs", "ipc", "-p", Quickshell.shellDir, "call", "shell", "call", "omamobile.home", "goHome", ""])
  }

  // The on-screen keyboard's calls are omamobile.keyboard's (squeekboard's
  // sm.puri.OSK0 SetVisible): through IPC, as goHome reaches the home
  // screen, since a plugin only calls into its own panels. method:
  // hideKeyboard, showKeyboard or toggleKeyboard.
  function keyboardCall(method) {
    console.log("omamobile-home-indicator: keyboard", method)
    Quickshell.execDetached(["qs", "ipc", "-p", Quickshell.shellDir, "call", "shell", "call", "omamobile.keyboard", method, ""])
  }

  // Once per user, the first time the keyboard comes up under the pill
  // after the double tap arrived: say how it works, as a toast (Omarchy's
  // notifications). The marker is Omarchy's own done store
  // (~/.local/state/omarchy/done/, as omamobile-setup-user's steps), and
  // `ensure` claims it atomically, so the toast shows once even with two
  // screens or two shells.
  readonly property string keyboardHintText: "Double-tap the bar to show or hide the keyboard"
  function keyboardHint() {
    Quickshell.execDetached(["sh", "-c", "omarchy-done ensure omamobile-keyboard-pill-hint && exec omarchy-notification-send -g \"$2\" \"$1\"",
                             "sh", root.keyboardHintText, String.fromCodePoint(0xF030C)])
  }

  // A moment after the strip shows, so a keyboard that only flashes up (or
  // the lock's, before isLocked answers) gets no toast.
  onKeyboardStripShownChanged: keyboardStripShown ? hintDelay.restart() : hintDelay.stop()
  Timer {
    id: hintDelay
    interval: 1500
    onTriggered: if (root.keyboardStripShown) root.keyboardHint()
  }

  function showRecents() {
    // Through the CLI, like the dock's swipe: a plugin may only summon
    // panels it owns, and the switcher is its own plugin.
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "omamobile.switcher", "{}"])
  }

  // The strip: a full touch target tall (TOUCH-PLAN 2.5), and no taller,
  // for the swipe and for the hide key at its right end. That is all an app
  // gives up, over it and under the keyboard alike.
  readonly property int stripHeight: touch

  // Not under the lock screen's keyboard: the strip isn't drawn over the
  // lock, but its reserved height would still lift the keyboard and leave a
  // gap. Asked each time the keyboard comes up or goes (it folds and
  // unfolds as the lock takes and gives back the focus), and again a moment
  // after it goes, since at an unlock it folds before the lock has gone: a
  // stale "locked" would unmap the strip when the keyboard next comes up
  // over an app. The lock service isn't one a third-party plugin can bind
  // to.
  property bool sessionLocked: false
  onOskOpenChanged: {
    if (!lockCheck.running) lockCheck.running = true
    if (!oskOpen) lockRecheck.restart()
  }
  Timer {
    id: lockRecheck
    interval: 1500
    onTriggered: if (!lockCheck.running) lockCheck.running = true
  }

  // The strip is on screen (each screen's window shows with it), and it is
  // the keyboard's strip: the keyboard is up above it.
  readonly property bool stripShown: appOnScreen && !opened && !fullscreenOnScreen && !(oskOpen && sessionLocked)
  readonly property bool keyboardStripShown: stripShown && oskOpen

  Process {
    id: lockCheck
    command: ["omarchy-shell", "lock", "isLocked"]
    stdout: SplitParser {
      onRead: function(line) { root.sessionLocked = String(line).trim() === "true" }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: homeStrip
      required property var modelData
      screen: modelData

      // Never hidden for the keyboard: see the comment above.
      visible: root.stripShown
      anchors { bottom: true; left: true; right: true }
      implicitHeight: root.stripHeight
      // Auto: it reserves its height, so windows (and the keyboard, while it
      // is up) end above it.
      exclusionMode: ExclusionMode.Auto
      color: Commons.Color.bar.background
      WlrLayershell.namespace: "omamobile-home-strip"
      // Bottom, under the keyboard's Top: see the comment above.
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Item {
        anchors.fill: parent

        HomePill { anchors.centerIn: parent }

        // The whole strip: nothing of the app is under it, it is below
        // every key, and the side edges' back strips stop above it.
        HomeSwipe {
          anchors.fill: parent
          strip: root.oskOpen ? "keyboard" : "pill"
          ownTaps: hideKey
        }

        // Over the swipe's right end, only while the keyboard is up; a
        // swipe that starts on it still goes home (see HideKeyboardKey).
        HideKeyboardKey {
          id: hideKey
          visible: root.oskOpen
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.xs
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }

  // ---------------------------------------------------------------- drawer

  PanelWindow {
    id: drawer

    // Mapped for the life of the shell. Mapped on each open, a new layer
    // surface's first frames drew before the output's scale and the slide
    // applied (the grid at 3x, or faded at its final place, then a jump):
    // now opening, closing and dragging only move the sheet. Closed, the
    // window draws nothing (its content is hidden, so Qt renders no
    // frames), takes no touch (an empty input region) and no keyboard.
    visible: true
    mask: Region { item: root.opened ? sheet : null }
    anchors { top: true; bottom: true; left: true; right: true }
    // Normal: fit between the bar and the on-screen keyboard, like Android's
    // adjustResize.
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-launcher"
    WlrLayershell.layer: WlrLayer.Top
    // OnDemand, not Exclusive: Hyprland sends no touch to other layers while
    // one holds exclusive focus, and that includes the on-screen keyboard.
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // The home screen dims under the rising drawer: Omarchy's own menu
    // scrim (the theme's), as strong as the drawer is open. It shows only
    // above the sheet while it slides; open, the sheet covers it.
    Rectangle {
      objectName: "drawerScrim"
      anchors.fill: parent
      color: Commons.Color.menu.scrim
      opacity: root.progress
      visible: root.drawerShown && root.progress > 0 && root.progress < 1
    }

    Rectangle {
      id: sheet
      objectName: "drawer"
      width: parent.width
      height: parent.height
      // Moved, never re-laid out: only y changes with the finger. Opaque,
      // and clipped to itself, so nothing of it shows above its top edge
      // while it slides; the scrim does the dimming.
      y: Math.round((1 - root.progress) * height)
      visible: root.drawerShown
      clip: true
      color: Commons.Color.menu.background

      // After a swipe the sheet has the keyboard focus, not the field (no
      // on-screen keyboard until the field is tapped); typing on a real
      // keyboard still searches, and Escape closes.
      Keys.onEscapePressed: root.dismiss(0)
      Keys.onPressed: function(event) {
        if (!event.text || event.text < " " || (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) return
        input.forceActiveFocus()
        root.query = root.query + event.text
        event.accepted = true
      }

      // Pull down to close (TOUCH-PLAN 1.8), as on Android: a drag down that
      // starts anywhere above the search rows (the handle, the header, empty
      // space, or the grid while it is scrolled to its top) moves the drawer
      // with the finger; a grid scrolled down scrolls first, and the pull
      // takes over where it reaches its top. Letting go closes it on a
      // downward flick or past a tenth of the way
      // (LauncherModel.drawerEndsOpen); otherwise it springs back. A
      // PointHandler only watches (a passive grab), so the grid still
      // scrolls and the app cells still take taps; while the drawer follows
      // the finger the grid holds still.
      Item {
        // Over everything in the sheet, so the press reaches it before the
        // grid and its cells take it (a handler on the sheet itself never
        // saw a press on the grid).
        anchors.fill: parent
        z: 10

        PointHandler {
          id: pullPoint
          // This touch may become a pull, it started on the grid, and the dy
          // (scene px, down positive) the pull counts from.
          property bool candidate: false
          property bool onGrid: false
          property real base: 0
          onActiveChanged: {
            if (active) {
              var at = point.pressPosition
              var onHeader = at.y < header.y + header.height
              var searchTop = askRow.visible ? askRow.y : inputRow.y
              onGrid = !onHeader && at.y >= grid.y && at.y < grid.y + grid.height
              base = 0
              root.pullMoved = false
              candidate = root.opened && !root.homeSwipe && at.y < searchTop && (!onGrid || !root.hasQuery)
              return
            }
            candidate = false
            if (!root.pulling) return
            root.pulling = false
            var speed = LauncherModel.speedOf(root.pullSamples, root.clock())
            if (LauncherModel.drawerEndsOpen(root.progress, speed, true)) root.settleTo(true, speed)
            else root.dismiss(speed)
          }
          onPointChanged: {
            if (!active || !candidate) return
            var dx = point.scenePosition.x - point.scenePressPosition.x
            var dy = point.scenePosition.y - point.scenePressPosition.y
            if (!root.pulling) {
              // Sideways first: never a pull.
              if (Math.abs(dx) > root.pullSlop && Math.abs(dx) > Math.abs(dy - base)) { candidate = false; return }
              // While the grid scrolls, the pull counts from where it is.
              if (onGrid && !grid.atYBeginning) { base = dy; return }
              if (dy - base <= root.pullSlop || Math.abs(dy - base) < Math.abs(dx)) return
              settle.stop()
              base = dy
              root.pullSamples = []
              root.pulling = true
              root.pullMoved = true
              // The dock comes back under the sheet now, while it covers the
              // home screen, and the keyboard goes.
              root.dockAway = false
              sheet.forceActiveFocus()
            }
            root.progress = Math.max(0, Math.min(1, 1 - (dy - base) / root.travel))
            root.pullSamples = LauncherModel.addSample(root.pullSamples, root.clock(), point.scenePosition.y)
          }
        }
      }

      // ---------- Header: the count
      Item {
        id: header
        objectName: "drawerHeader"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.spacing.panelPadding
        anchors.rightMargin: Style.spacing.panelPadding
        height: root.touch + Style.spacing.sm

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.hasQuery ? (root.apps.length === 1 ? "1 app" : root.apps.length + " apps") : "Apps"
          color: Qt.darker(root.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
      }

      // ---------- The handle: a pill centred at the top, as the home pill
      // is at the bottom over an app. A tap closes the drawer; a drag moves
      // it down and back up with the finger (the pull above), and letting go
      // closes it or springs back. The pill is small; its touch target is
      // the header's full height (at least 44 px) and three targets wide.
      Item {
        id: handle
        objectName: "drawerHandle"
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.touch * 3
        height: header.height

        Rectangle {
          anchors.centerIn: parent
          width: Math.max(36, Style.space(40))
          height: Math.max(4, Style.space(5))
          radius: height / 2
          color: handleTap.pressed || root.pulling ? Commons.Color.accent : Util.alpha(root.foreground, 0.45)
        }

        TapHandler {
          id: handleTap
          onTapped: root.dismiss(0)
        }
      }

      // ---------- App grid
      GridView {
        id: grid
        objectName: "drawerGrid"
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: askRow.visible ? askRow.top : inputRow.top
        anchors.leftMargin: Style.spacing.lg
        anchors.rightMargin: Style.spacing.lg
        anchors.bottomMargin: Style.spacing.lg
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Still while a finger pulls the drawer.
        interactive: !root.pulling
        // While searching, results stack up from the input so the best match
        // sits nearest the thumb; the full list reads top-down.
        verticalLayoutDirection: root.hasQuery ? GridView.BottomToTop : GridView.TopToBottom
        cellWidth: Math.floor(width / root.drawerColumns(width))
        cellHeight: Math.max(96, Style.space(100))
        model: root.apps
        opacity: root.promptMode ? 0.5 : 1

        delegate: AppCell {
          required property var modelData
          required property int index
          width: grid.cellWidth
          height: grid.cellHeight
          entry: modelData
          highlighted: index === 0 && root.hasQuery && !root.promptMode
          onTapped: root.launchApp(modelData)
          onHeld: root.addToHome(modelData)
        }
      }

      Text {
        anchors.centerIn: grid
        visible: root.hasQuery && root.apps.length === 0
        textFormat: Text.PlainText
        text: "No apps match"
        color: Qt.darker(root.foreground, 1.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      // ---------- Ask the agent
      BorderSurface {
        id: askRow
        objectName: "askRow"
        visible: root.hasQuery
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: inputRow.top
        anchors.leftMargin: Style.spacing.xxl
        anchors.rightMargin: Style.spacing.xxl
        anchors.bottomMargin: Style.spacing.lg
        height: Math.max(root.touch, Style.space(52))
        radius: Style.cornerRadius
        color: askTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
          : root.promptMode ? Commons.Color.menu.selectedBackground : "transparent"
        borderSpec: root.promptMode
          ? Border.flat(Commons.Color.accent, Math.max(1, Style.normalBorderWidth))
          : Border.controlSpec("normal", root.foreground, Commons.Color.accent)

        Item {
          id: askIcon
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.xl
          anchors.verticalCenter: parent.verticalCenter
          width: Style.font.display
          height: Style.font.display

          Image {
            id: askImage
            anchors.fill: parent
            source: root.agentIcon
            visible: status === Image.Ready
            fillMode: Image.PreserveAspectFit
            sourceSize.width: width * Screen.devicePixelRatio
            sourceSize.height: height * Screen.devicePixelRatio
          }

          Text {
            anchors.centerIn: parent
            visible: askImage.status !== Image.Ready
            textFormat: Text.PlainText
            text: "󰚩"
            color: Commons.Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.display
          }
        }

        Column {
          anchors.left: askIcon.right
          anchors.leftMargin: Style.spacing.xl
          anchors.right: askEnter.left
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xxs

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.hasAgent ? "Ask " + root.agentName : "Choose your agent"
            color: root.promptMode ? Commons.Color.menu.selectedText : root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.query.trim()
            color: Qt.darker(root.foreground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Readable.px(Style.font.caption)
            elide: Text.ElideRight
          }
        }

        Text {
          id: askEnter
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.xl
          anchors.verticalCenter: parent.verticalCenter
          visible: root.promptMode
          textFormat: Text.PlainText
          text: "󰌑"
          color: Commons.Color.menu.selectedText
          font.family: Style.font.family
          font.pixelSize: Style.font.iconLarge
        }

        MouseArea {
          id: askTouch
          anchors.fill: parent
          onClicked: root.askAgent(root.query)
        }
      }

      // ---------- The one input
      Item {
        id: inputRow
        objectName: "inputRow"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.dockHeight
        // While a swipe slides the drawer up, the dock's own search pill is
        // still under it; the drawer's field shows once the dock has gone,
        // in its place.
        opacity: root.dockAway ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        TextField {
          id: input
          anchors.fill: parent
          anchors.margins: Style.spacing.xxl
          verticalAlignment: TextInput.AlignVCenter
          font.pixelSize: Style.font.title
          leftPadding: Style.spacing.controlPaddingX + Style.font.iconLarge + Style.spacing.xl
          placeholderText: (root.hasAgent ? "Search apps or ask " + root.agentName + "…" : "Search apps…")
          foreground: root.foreground
          text: root.query
          onTextEdited: root.query = text
          Keys.onReturnPressed: root.activate()
          Keys.onEnterPressed: root.activate()
          Keys.onEscapePressed: {
            if (root.query) root.query = ""
            else root.dismiss()
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.controlPaddingX + Border.left(input._borderSpec)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.promptMode ? "󰚩" : "󰍉"
            color: root.promptMode ? Commons.Color.accent : Qt.darker(root.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.iconLarge
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- parts

  // The collapsed bar: looks like the input it turns into.
  component SearchPill: BorderSurface {
    id: pill

    property string placeholder: ""
    signal tapped()

    radius: Style.cornerRadius
    color: pillTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent) : Style.normalFill
    borderSpec: Border.controlSpec("normal", root.foreground, Commons.Color.accent)

    Text {
      id: pillIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX + pill.borderLeft
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "󰍉"
      color: Qt.darker(root.foreground, 1.3)
      font.family: Style.font.family
      font.pixelSize: Style.font.iconLarge
    }

    Text {
      anchors.left: pillIcon.right
      anchors.leftMargin: Style.spacing.xl
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: pill.placeholder
      color: Qt.darker(root.foreground, 1.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      elide: Text.ElideRight
    }

    // A TapHandler, not a MouseArea: it lets go once the touch turns into a
    // drag, so the dock's swipe-up (recent apps) still sees it.
    TapHandler {
      id: pillTouch
      onTapped: pill.tapped()
    }
  }

  // The home pill: a light bar in a dark outline with a soft halo, so it
  // shows over a dark app and a white one (a browser page, a document) alike.
  component HomePill: Item {
    width: pillBar.width + 6
    height: pillBar.height + 6

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: Qt.rgba(0, 0, 0, 0.22)
    }

    Rectangle {
      id: pillBar
      anchors.centerIn: parent
      width: 120
      height: 6
      radius: height / 2
      color: Qt.rgba(1, 1, 1, 0.9)
      border.width: 1
      border.color: Qt.rgba(0, 0, 0, 0.55)
    }
  }

  // Where a home swipe starts. Swipe up and let go: home. Swipe up and hold
  // still for a moment (or swipe far up): recent apps, while the finger is
  // still down, as Android's gesture navigation does. Double-tap: show or
  // hide the on-screen keyboard. strip names the surface in the log: "pill"
  // over an app, "keyboard" under the keyboard.
  component HomeSwipe: Item {
    id: swipeArea
    property string strip: "pill"
    // An item over the strip whose taps are its own (the hide key): a tap
    // there is never half of a double tap, or tapping the key twice would
    // hide the keyboard and show it again.
    property Item ownTaps: null

    // A TapHandler with the default DragThreshold policy grabs only
    // passively: once the touch moves past the drag threshold the
    // DragHandler takes it over and the tap is cancelled, so a swipe is
    // never also a tap. A tap never moves that far, so the DragHandler never
    // activates and a double tap goes neither home nor to recent apps. A
    // single tap does nothing, as before (the app still loses it).
    TapHandler {
      id: doubleTap
      property bool lastOwn: false
      onTapped: function(eventPoint) {
        var own = swipeArea.ownTaps
        var onOwn = !!own && own.visible
          && own.contains(own.mapFromItem(swipeArea, eventPoint.position.x, eventPoint.position.y))
        var wasOwn = doubleTap.lastOwn
        doubleTap.lastOwn = onOwn
        if (doubleTap.tapCount === 2 && !onOwn && !wasOwn) root.keyboardCall("toggleKeyboard")
      }
    }

    DragHandler {
      id: swipe
      target: null
      xAxis.enabled: false
      property real swipeY: 0
      property bool recents: false
      onActiveTranslationChanged: {
        swipeY = activeTranslation.y
        if (recents) return
        if (swipeY < -120) {
          recents = true
          hold.stop()
          root.showRecents()
        } else if (swipeY < -24) {
          hold.restart()
        }
      }
      onActiveChanged: {
        if (active) { swipeY = 0; recents = false; return }
        hold.stop()
        console.log("omamobile-home-indicator: swipe", Math.round(swipeY), recents ? "recents" : "", "(" + swipeArea.strip + ")")
        if (!recents && swipeY < -24) root.goHome()
      }
    }

    Timer {
      id: hold
      interval: 350
      onTriggered: {
        if (!swipe.active || swipe.recents) return
        swipe.recents = true
        root.showRecents()
      }
    }
  }

  // The keyboard strip's hide key: a keyboard-down glyph in a full 44 px
  // touch target at the strip's right end, where Android's gesture bar puts
  // its keyboard-down button; it reads as part of the keyboard and covers
  // nothing in the app. Its TapHandler keeps the default DragThreshold
  // policy, a passive grab, so the press also reaches the HomeSwipe under
  // it: a swipe that starts on the key still goes home (and doesn't hide
  // the keyboard), as the switcher's cards let a drag through their tap.
  component HideKeyboardKey: Item {
    objectName: "hideKeyboard"
    width: root.touch
    height: root.touch

    Rectangle {
      anchors.centerIn: parent
      width: parent.width - 4
      height: parent.height - 8
      radius: height / 2
      color: Qt.rgba(Commons.Color.bar.text.r, Commons.Color.bar.text.g, Commons.Color.bar.text.b, 0.18)
      visible: hideTap.pressed
    }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      // nf-md-keyboard_close: a keyboard over a down chevron
      text: String.fromCodePoint(0xF030F)
      color: Commons.Color.bar.text
      font.family: Style.font.family
      font.pixelSize: 22
    }

    TapHandler {
      id: hideTap
      onTapped: root.keyboardCall("hideKeyboard")
    }
  }

  // One app in the grid: icon over a two-line name.
  component AppCell: Item {
    id: cell

    property var entry: null
    objectName: "app-" + (entry ? entry.id : "")
    property bool highlighted: false
    signal tapped()
    signal held()

    BorderSurface {
      anchors.fill: parent
      anchors.margins: Style.spacing.xs
      radius: Style.cornerRadius
      color: cellTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
        : cell.highlighted ? Commons.Color.menu.selectedBackground : "transparent"
      borderSpec: cell.highlighted ? Border.flat(Commons.Color.accent, Math.max(1, Style.normalBorderWidth)) : Border.none()
    }

    Image {
      id: icon
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Style.spacing.xl
      width: Math.max(40, Style.space(44))
      height: width
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      // Decode at physical pixels so PNG icons stay sharp at scale 3.
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      source: root.appLibrary && cell.entry ? root.appLibrary.iconSource(cell.entry.icon) : ""
    }

    Text {
      anchors.top: icon.bottom
      anchors.topMargin: Style.spacing.md
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.spacing.sm
      anchors.rightMargin: Style.spacing.sm
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.appLibrary && cell.entry ? root.appLibrary.entryName(cell.entry) : ""
      color: cell.highlighted ? Commons.Color.menu.selectedText : root.foreground
      font.family: Style.font.family
      font.pixelSize: Readable.px(Style.font.caption)
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }

    MouseArea {
      id: cellTouch
      anchors.fill: parent
      // Not when the touch pulled the drawer down instead.
      onClicked: if (!root.pullMoved) cell.tapped()
      onPressAndHold: if (!root.pullMoved) cell.held()
    }
  }
}
