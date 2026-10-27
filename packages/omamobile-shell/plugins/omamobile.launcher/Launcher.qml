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
  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    query = typeof payload.query === "string" ? payload.query : ""
    if (appLibrary) appLibrary.refreshIcons()
    refreshApps()
    opened = true
  }

  // Host-initiated close (`shell hide`).
  function close() {
    opened = false
    query = ""
  }

  function dismiss() {
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
  // No dock under an app: while the focused workspace has a window, the
  // dock (and its exclusive zone) goes away and the app gets the whole
  // screen, as on a phone. Home (an empty workspace) brings it back.
  readonly property bool appOnScreen: !!Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.toplevels.values.length > 0

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  // How far the drawer is pulled down by a finger (pull to close), the pull
  // that closes it, and the first pixels a tap's jitter may move.
  // pulling: a finger is pulling now; pullMoved: this touch moved the
  // drawer, so it is not also a tap on an app.
  property real pull: 0
  property bool pulling: false
  property bool pullMoved: false
  readonly property int pullToClose: Math.max(80, Style.space(80))
  readonly property int pullSlop: 8
  Behavior on pull {
    enabled: !root.pulling
    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
  }

  // ---------------------------------------------------------------- dock

  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData

      // Hidden while the drawer is open, so the on-screen keyboard takes the
      // bottom edge and the drawer's input sits right above it.
      visible: !root.opened && !root.appOnScreen
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

  // Over an app, where the dock is hidden: a thin strip with a pill, as on
  // iOS. Swipe up on it to go home (the empty workspace, where the dock is
  // back); swipe up and hold (or a long swipe) for recent apps, as on
  // Android. It claims no exclusive zone, so the app keeps the whole screen.
  //
  // It sits on the Overlay layer, so it would take touches from anything
  // below it: it gives way to the on-screen keyboard and to fullscreen
  // windows (video, the screensaver), and its input mask leaves only the
  // middle of the strip to the pill. The back gesture (omamobile.back) has
  // the side edges.
  //
  // While the keyboard is up, the pill moves into a strip of its own under
  // the keyboard instead, as Android's gesture bar does: a bar-coloured
  // strip on the Bottom layer that reserves its height (an exclusive zone).
  // Hyprland arranges the layers that reserve space from the Bottom layer
  // up, so the strip takes the screen's bottom edge first and squeekboard
  // (the Top layer, which reserves its own height) sits right above it, the
  // way it sits above the dock on the home screen. The strip covers no key,
  // and a swipe that starts in it stays its own as the finger crosses the
  // keyboard.
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

  function showRecents() {
    // Through the CLI, like the dock's swipe: a plugin may only summon
    // panels it owns, and the switcher is its own plugin.
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "omamobile.switcher", "{}"])
  }

  // The keyboard's strip: tall enough to start a swipe in, short enough to
  // keep the app's view of what is being typed.
  readonly property int oskStripHeight: 32

  // Not under the lock screen's keyboard: the strip isn't drawn over the
  // lock, but its reserved height would still lift the keyboard and leave a
  // gap. Asked each time the keyboard comes up (it folds and unfolds as the
  // lock takes and gives back the focus); the lock service isn't one a
  // third-party plugin can bind to.
  property bool sessionLocked: false
  onOskOpenChanged: if (oskOpen && !lockCheck.running) lockCheck.running = true

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
      id: indicator
      required property var modelData
      screen: modelData

      visible: root.appOnScreen && !root.opened && !root.oskOpen && !root.fullscreenOnScreen
      anchors { bottom: true; left: true; right: true }
      // A full touch target tall (TOUCH-PLAN 2.5): the swipe may start
      // anywhere in the 240x44 px strip around the pill, not only on its
      // bottom 18 px. The app loses taps in that strip, as on iOS.
      implicitHeight: root.touch
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.namespace: "omamobile-home-indicator"
      WlrLayershell.layer: WlrLayer.Overlay
      // Only the middle of the strip takes touches; the rest passes through.
      mask: Region { item: hitArea }

      Item {
        anchors.fill: parent

        HomePill {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 3
        }

        HomeSwipe {
          id: hitArea
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 240
          strip: "pill"
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: keyboardStrip
      required property var modelData
      screen: modelData

      visible: root.appOnScreen && !root.opened && root.oskOpen && !root.sessionLocked && !root.fullscreenOnScreen
      anchors { bottom: true; left: true; right: true }
      implicitHeight: root.oskStripHeight
      // Auto: it reserves its height, which lifts the keyboard (and the app
      // above it) clear of the strip.
      exclusionMode: ExclusionMode.Auto
      color: Commons.Color.bar.background
      WlrLayershell.namespace: "omamobile-home-strip"
      // Bottom, under the keyboard's Top: see the comment above.
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Item {
        anchors.fill: parent

        HomePill { anchors.centerIn: parent }

        // The whole strip: it is below every key, and the side edges'
        // back strips stop at the keyboard.
        HomeSwipe {
          anchors.fill: parent
          strip: "keyboard"
        }
      }
    }
  }

  // ---------------------------------------------------------------- drawer

  PanelWindow {
    id: drawer

    visible: root.opened || root.reveal > 0
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

    onVisibleChanged: {
      if (visible) Qt.callLater(function() { input.forceActiveFocus() })
      else root.pull = 0
    }

    Rectangle {
      id: sheet
      objectName: "drawer"
      width: parent.width
      height: parent.height
      y: Math.round((1 - root.reveal) * Style.space(80) + root.pull)
      opacity: root.reveal * Math.max(0.5, 1 - root.pull / Math.max(1, height))
      color: Commons.Color.menu.background

      // Pull down to close (TOUCH-PLAN 1.8), as on Android: a drag down that
      // starts on the header, or on the grid while it is scrolled to its
      // top, moves the drawer with the finger, and letting go past
      // pullToClose closes it (less springs back). A PointHandler only
      // watches (a passive grab), so the grid still scrolls and the app
      // cells still take taps; the grid can't scroll further up from its
      // top (StopAtBounds), so it stays put while the drawer follows.
      PointHandler {
        id: pullPoint
        readonly property real dy: active ? point.scenePosition.y - point.scenePressPosition.y : 0
        onActiveChanged: {
          if (active) {
            var at = point.pressPosition
            var onHeader = at.y < header.y + header.height
            var onGridTop = !root.hasQuery && grid.atYBeginning
              && at.y >= grid.y && at.y < grid.y + grid.height
            root.pullMoved = false
            root.pulling = root.opened && (onHeader || onGridTop)
            return
          }
          var close = root.pulling && root.pull > root.pullToClose
          root.pulling = false
          if (close) root.dismiss()
          else root.pull = 0
        }
        onDyChanged: {
          if (!root.pulling || !active) return
          root.pull = Math.max(0, dy - root.pullSlop)
          if (root.pull > 0) root.pullMoved = true
        }
      }

      // ---------- Header: count and a collapse control
      Item {
        id: header
        objectName: "drawerHeader"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.spacing.panelPadding
        anchors.rightMargin: Style.spacing.sm
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

        Button {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: root.touch
          height: root.touch
          objectName: "collapse"
          iconText: "󰅀"
          iconSize: Style.font.iconLarge
          foreground: root.foreground
          onClicked: root.dismiss()
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
  // still down, as Android's gesture navigation does. strip names the
  // surface in the log: "pill" over an app, "keyboard" under the keyboard.
  component HomeSwipe: Item {
    id: swipeArea
    property string strip: "pill"

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
