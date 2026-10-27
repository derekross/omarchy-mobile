// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import qs.services as OmarchyServices
import Quickshell.Hyprland
import "HomeModel.js" as HomeModel
import "UserWidgets.js" as UserWidgets
import "owl/catalog.js" as OwlCatalog
import "owl/phone.js" as OwlPhone
import "owl" as Owl
import "Readable.js" as Readable

// Home screens, after Android launchers (Omalauncher, Pixel Launcher): pages
// of app shortcuts and widgets on the wallpaper, swiped sideways, with page
// dots. Long-press anywhere for edit mode: drag to move (past a page edge to
// move to the next page), the corner handle to resize, the cross to remove;
// the toolbar adds widgets and apps, opens Omarchy's style menu (wallpaper,
// theme) and manages pages.
//
// One layer surface on the bottom layer: above the wallpaper (Omarchy's
// background plugin, on the background layer), below windows, between the
// status bar and the dock (normal exclusion). Apps cover it when open, and
// it shows on every empty workspace. Pages are this surface's own, not
// Hyprland workspaces; the README says why.
//
// The layout is the user's, in ~/.config/omamobile/home.json (HomeModel.js
// has the format). External edits are picked up live.
//
// Besides the built-in widgets, the user's own: folders under
// ~/.config/omamobile/widgets/<id>/ (WIDGETS.md is the contract), listed
// and checked by `omamobile-widget scan`, watched with inotifywait the way
// Omarchy's shell watches ~/.config/omarchy/plugins, and loaded only when
// the scan calls them ok. A broken one is an error card, never a broken
// home screen. The Widgets sheet creates and changes them with Omarchy's
// default coding agent.
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "omamobile.home"
  readonly property var appLibrary: shell && shell.appLibrary ? shell.appLibrary : localLibrary.item

  // As in omamobile.launcher: a panel plugin gets no application library
  // from the host, so run Omarchy's own type here.
  Loader {
    id: localLibrary
    active: !!root.shell && !root.shell.appLibrary
    sourceComponent: Component { OmarchyServices.AppLibrary { } }
  }

  // ---------------------------------------------------------------- look

  readonly property color foreground: Commons.Color.menu.text
  readonly property color dimForeground: Util.alpha(Commons.Color.menu.text, 0.68)
  readonly property color cardColor: Util.alpha(Commons.Color.menu.background, 0.8)
  readonly property int touch: Math.max(44, Style.space(44))
  readonly property int gap: Style.spacing.md

  // ---------------------------------------------------------------- state

  property var layout: HomeModel.emptyLayout(HomeModel.GRID)
  property bool loaded: false
  property bool editing: false
  property int currentPage: 0
  // "", "widgets", "apps", "pages", "settings", "create"
  property string sheet: ""
  property string settingsId: ""
  property string notice: ""
  // The item removed last, as findItem saw it, while its Undo chip shows.
  property var undoRemoved: null
  readonly property bool wantsKeyboard: sheet === "apps" || sheet === "settings" || sheet === "create" || owlTyping

  // Bumped when desktop entries change, so app tiles look themselves up again.
  property int appsRevision: 0
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      root.appsRevision += 1
      if (root.waitingForApps) root.makeDefault(false)
    }
  }

  function availableAppIds() {
    var values = DesktopEntries.applications.values || []
    return values.map(function(e) { return String(e.id || "") })
  }

  function entryFor(appId) {
    var revision = appsRevision // re-evaluated when apps change
    return DesktopEntries.byId(appId) || DesktopEntries.byId(appId + ".desktop") || null
  }

  // Per-widget data that outlives a rebuild (every layout change rebuilds
  // the page's delegates): the weather answer, a command's output.
  property var cache: ({})
  function widgetCache(id) { return cache[id] || null }
  function setWidgetCache(id, value) { cache[id] = value }

  // ---------------------------------------------------------------- storage

  readonly property string configDir: Quickshell.env("HOME") + "/.config/omamobile"
  readonly property string layoutPath: configDir + "/home.json"
  property string lastWritten: ""
  property bool corrupt: false
  property bool waitingForApps: false

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.configDir]
    onExited: store.path = root.layoutPath
  }
  Component.onCompleted: { mkdirProc.running = true; widgetsInit.running = true }

  FileView {
    id: store
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadText(text())
    onLoadFailed: root.makeDefault(true)
  }

  function loadText(text) {
    if (loaded && text === lastWritten) return
    // Ports from before the OWL built-ins: kept once as home.json.before-owl,
    // approved where their OWL original needs no more than they had.
    var ports = []
    try { ports = HomeModel.portPlacements(JSON.parse(text)) } catch (e) { ports = [] }
    if (ports.length) { owlBackupProc.running = true; migratePorts(ports) }
    var parsed = HomeModel.parse(text, userCatalog)
    if (!parsed) {
      // Unreadable (a hand edit gone wrong): keep showing what we have (the
      // default at startup), and keep the file as home.json.bad before the
      // next save replaces it.
      corrupt = true
      if (!loaded) makeDefault(false)
      return
    }
    corrupt = false
    layout = parsed
    if (ports.length) saveTimer.restart()
    if (!loaded) { loaded = true; goToPage(layout.home, false) }
    else if (currentPage >= viewLayout.pages.length) goToPage(viewLayout.pages.length - 1, false)
  }

  // A first start: a clock and a few installed apps. Waits for the desktop
  // entries to be read (they arrive after the shell starts), at most 5 s.
  function makeDefault(save) {
    var ids = availableAppIds()
    if (ids.length === 0 && !defaultTimeout.fired) {
      waitingForApps = true
      defaultTimeout.start()
      return
    }
    waitingForApps = false
    layout = HomeModel.defaultLayout(ids, HomeModel.GRID)
    loaded = true
    goToPage(0, false)
    if (save && !corrupt) flush()
  }

  Timer {
    id: defaultTimeout
    property bool fired: false
    interval: 5000
    onTriggered: { fired = true; if (root.waitingForApps) root.makeDefault(true) }
  }

  Timer { id: saveTimer; interval: 300; onTriggered: root.flush() }

  // The layout as it was before its ports became OWL widgets, kept once.
  Process {
    id: owlBackupProc
    command: ["sh", "-c", "[ -e \"$1.before-owl\" ] || cp -p \"$1\" \"$1.before-owl\"", "sh", root.layoutPath]
  }

  Process {
    id: backupProc
    command: ["cp", "-f", root.layoutPath, root.layoutPath + ".bad"]
    onExited: { root.corrupt = false; root.flush() }
  }

  function flush() {
    if (!loaded) return
    if (corrupt) { if (!backupProc.running) backupProc.running = true; return }
    lastWritten = HomeModel.serialize(layout)
    store.path = layoutPath
    store.setText(lastWritten)
  }

  // Every edit goes through here.
  function commit(next) {
    if (!next) return false
    layout = next
    if (currentPage >= viewLayout.pages.length) goToPage(viewLayout.pages.length - 1, false)
    saveTimer.restart()
    return true
  }

  // ---------------------------------------------------------------- the system's clock format

  // Widgets that show a time follow the 12/24-hour choice the status bar
  // uses (shell.json's bar.clockFormat), as the clock widget does.
  property string barClockFormat: ""
  readonly property string systemTimeFormat: HomeModel.systemTimeFormat(barClockFormat)
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var shellConfig = JSON.parse(text())
        root.barClockFormat = shellConfig.bar && shellConfig.bar.clockFormat ? String(shellConfig.bar.clockFormat) : ""
      } catch (e) { root.barClockFormat = "" }
    }
  }

  // ---------------------------------------------------------------- the user's own widgets

  // The last good scan (UserWidgets.parseScan) and the specs HomeModel sizes
  // user widgets by.
  property var userScan: UserWidgets.emptyScan()
  readonly property var userCatalog: UserWidgets.catalog(userScan, owlEnabled ? owlSpecs : null)
  readonly property string widgetsDir: userScan.dir || (Quickshell.env("HOME") + "/.config/omamobile/widgets")
  // Errors widgets hit when the home screen built them (QML that loads
  // badly), by widget id and hash: shown on their card and by widgetStatus.
  property var runtimeErrors: ({})
  // Crash guard. An error card catches a widget's QML errors, but a widget
  // that crashes Quickshell itself takes the shell down, and the crash-loop
  // restarts with it. So each user widget is recorded in widget-guard.json
  // (written synchronously) while it loads and for its first seconds; an
  // entry still there at the next start was running when the shell died,
  // and that widget stays off until its files change (a new hash).
  readonly property string guardPath: configDir + "/widget-guard.json"
  property var guardLoading: ({})
  property var guardCrashed: ({})
  FileView {
    id: guardFile
    path: root.guardPath
    blockLoading: true
    blockWrites: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var data = {}
      try { data = JSON.parse(text() || "{}") || {} } catch (e) { data = {} }
      root.guardCrashed = Object.assign({}, data.crashed || {}, data.loading || {})
      root.guardLoading = ({})
      Object.keys(data.loading || {}).forEach(function(id) {
        console.warn("omamobile.home: widget " + id + " was loading when the shell stopped; it stays off until it changes")
      })
      root.guardWrite()
    }
  }
  function guardWrite() {
    guardFile.setText(JSON.stringify({ loading: guardLoading, crashed: guardCrashed }) + "\n")
  }
  function guardBegin(widgetId, hash) {
    var next = Object.assign({}, guardLoading); next[widgetId] = hash
    guardLoading = next; guardWrite()
  }
  // `ran`: the widget has now run cleanly, so an older crash of it is forgotten.
  function guardEnd(widgetId, ran) {
    var crashed = ran && (widgetId in guardCrashed)
    if (!(widgetId in guardLoading) && !crashed) return
    var next = Object.assign({}, guardLoading); delete next[widgetId]
    guardLoading = next
    if (crashed) { var c = Object.assign({}, guardCrashed); delete c[widgetId]; guardCrashed = c }
    guardWrite()
  }

  // A widget to place once the scan has seen it (just created or copied).
  property string pendingAdd: ""

  // Omarchy's default coding agent (omarchy-default-agent's file), for the
  // words on the Create sheet; launching goes through Omarchy's own scripts.
  property string agentId: ""
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/defaults/agent"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.agentId = String(text() || "").trim().split("\n")[0].trim()
    onLoadFailed: root.agentId = ""
  }

  Process {
    id: widgetsInit
    command: [UserWidgets.TOOL, "init"]
    onExited: { widgetWatcher.running = true; root.scanWidgets() }
  }

  // Same watch as Omarchy's PluginRegistry on ~/.config/omarchy/plugins.
  Process {
    id: widgetWatcher
    command: ["inotifywait", "-m", "-r", "-q", "-e", "close_write,create,delete,move", "--format", "%w%f", root.widgetsDir]
    stdout: SplitParser {
      onRead: function(path) { widgetScanTimer.restart() }
    }
    onExited: widgetWatcherRestart.restart()
  }
  Timer { id: widgetWatcherRestart; interval: 2000; onTriggered: widgetWatcher.running = true }
  Timer { id: widgetScanTimer; interval: 400; onTriggered: root.scanWidgets() }

  property bool scanPending: false
  Process {
    id: widgetScan
    command: UserWidgets.SCAN_ARGV
    stdout: StdioCollector { id: widgetScanOut; waitForEnd: true }
    onExited: {
      var scan = UserWidgets.parseScan(widgetScanOut.text)
      if (scan.ok) root.applyScan(scan)
      else console.warn("omamobile.home: " + scan.error)
      if (root.scanPending) { root.scanPending = false; root.scanWidgets() }
    }
  }

  function scanWidgets() {
    if (widgetScan.running) { scanPending = true; return }
    widgetScan.running = true
  }

  function applyScan(scan) {
    // Changed code is loaded fresh: Qt keeps components by URL, so the
    // URL carries the hash, and the cache is cleared for files a widget
    // imports from its own folder. (Omarchy's plugin reload does the same.)
    var changed = false
    scan.widgets.forEach(function(r) {
      var before = UserWidgets.findRecord(userScan, r.id)
      if (before && before.hash !== r.hash) changed = true
    })
    if (changed && typeof Qt.clearComponentCache === "function") Qt.clearComponentCache()
    userScan = scan
    if (loaded) {
      // Re-clamp placed user widgets to what their manifests now allow.
      var next = HomeModel.normalize(layout, userCatalog)
      if (next && HomeModel.serialize(next) !== HomeModel.serialize(layout)) commit(next)
    }
    if (pendingApprove && UserWidgets.findRecord(scan, pendingApprove)) {
      const approve = pendingApprove
      pendingApprove = ""
      Qt.callLater(function() { root.openOwlApproval(approve) })
    }
    if (pendingAdd) {
      var r = UserWidgets.findRecord(scan, pendingAdd)
      // Placed behind the Create sheet, which stays up for the agent's outcome.
      if (r) { var id = pendingAdd; pendingAdd = ""; addWidgetHere(UserWidgets.typeFor(id), sheet === "create") }
    }
  }

  // What a placed user widget shows: { state, message, url, record }.
  function userCard(widgetId) {
    var card = UserWidgets.cardState(userScan, widgetId)
    var r = UserWidgets.findRecord(userScan, widgetId)
    card.record = r
    card.url = ""
    if (card.state === "ok") {
      var runtime = runtimeErrors[widgetId]
      if (runtime && runtime.hash === r.hash) return { state: "error", message: runtime.message, url: "", record: r }
      if (guardCrashed[widgetId] === r.hash)
        return { state: "error", message: "This widget crashed the shell, so it's off. Edit it to try again.", url: "", record: r }
      card.url = "file://" + r.dir + "/" + r.manifest.entry + "?v=" + r.hash
    }
    return card
  }

  function noteRuntimeError(widgetId, message) {
    var r = UserWidgets.findRecord(userScan, widgetId)
    var next = Object.assign({}, runtimeErrors)
    next[widgetId] = { hash: r ? r.hash : "", message: String(message || "It failed to load") }
    runtimeErrors = next
    console.warn("omamobile.home: widget " + widgetId + ": " + message)
  }

  // ---------------------------------------------------------------- OWL widgets

  // Widgets in OWL, the language of the Omalauncher widget store, run by our
  // own runtime (owl/, docs/WIDGET-INTEROP-PLAN.md). Behind a flag that is
  // off by default: ~/.config/omamobile/features.json {"owlWidgets": true}.
  // A folder with a widget.owl is listed by the scan; it runs once the user
  // has approved its exact list of commands, URLs and files.
  property bool owlEnabled: false
  FileView {
    path: root.configDir + "/features.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      let features = {}
      try { features = JSON.parse(text() || "{}") || {} } catch (e) { features = {} }
      root.owlEnabled = features.owlWidgets === true
    }
    onLoadFailed: root.owlEnabled = false
  }

  readonly property string homeDir: Quickshell.env("HOME")
  // Geometry: the pager (one page) and the surface, in logical px.
  property real owlPageWidth: 480
  property real owlPagerHeight: 908
  property real owlScreenWidth: 480
  property real owlScreenHeight: 924
  // The screen the surface is on (the offscreen renders put a stand-in
  // here), and its shorter side: the portrait page width, whichever way the
  // phone is held (the surface itself loses the bar and the dock).
  property var screenInfo: surface.screen || null
  readonly property real owlShortSide: screenInfo && screenInfo.width > 0 && screenInfo.height > 0
    ? Math.min(screenInfo.width, screenInfo.height) : Math.min(owlPageWidth, owlScreenHeight)
  // One OWL dp from that side (Omalauncher's 6 columns of 69 dp), so a
  // widget draws at one size in both orientations. From the landscape width
  // it drew 2.2 times larger into cells 2.6 times shorter, and its rows
  // landed on each other (#85).
  readonly property real owlDp: OwlPhone.dpFor(landscape ? owlShortSide : owlPageWidth)
  // The portrait page's height, which the catalog sizes widgets in (the
  // file's grid is portrait): in landscape, this pager's height plus the
  // screen's long side less its short one, since the bar and the dock take
  // the same room either way.
  readonly property real owlPortraitPagerHeight: landscape ? owlPagerHeight + Math.max(0, Math.max(owlScreenWidth, owlScreenHeight) - owlShortSide) : owlPagerHeight
  readonly property real owlCellHeight: owlPortraitPagerHeight / Math.max(1, layout.grid.rows)

  // ---------------------------------------------------------------- landscape (TOUCH-PLAN 2.4)

  // A page wider than tall (the phone on its side, Hyprland transform 1 or
  // 3) shows the layout turned with it: columns and rows swap, and each
  // item's place and box turn too, kept to its size in pixels and to its
  // limits (HomeModel.transposeLayout). `layout` and the file stay portrait;
  // the view derives this and never saves it. Edit mode moves and resizes on
  // the portrait grid, so it waits for portrait; the sheets still open.
  readonly property bool landscape: owlPageWidth > owlPagerHeight
  readonly property var viewLayout: landscape
    ? HomeModel.transposeLayout(layout, userCatalog, { portrait: [owlShortSide, owlPortraitPagerHeight], landscape: [owlPageWidth, owlPagerHeight] })
    : layout
  onLandscapeChanged: if (landscape && editing) setEditing(false)

  // What each OWL widget compiles to, its sizes and what it may do.
  readonly property var owlInfo: {
    const out = {}
    if (!owlEnabled) return out
    userScan.widgets.forEach(function(r) {
      if (r.kind === "owl" && r.owl) out[r.id] = OwlCatalog.describe(r.id, r.owl.text, root.layout.grid, root.owlCellHeight, root.owlDp)
    })
    return out
  }
  readonly property var owlSpecs: {
    const out = {}
    for (const id in owlInfo) if (owlInfo[id].ok) out[id] = owlInfo[id].spec
    return out
  }
  function isOwlType(type) {
    const r = UserWidgets.findRecord(userScan, UserWidgets.idOf(type))
    return !!r && r.kind === "owl"
  }

  // Approvals: { id: { commands: [...], network: bool, at } }. An approval
  // holds for one exact list; a widget whose list changes asks again.
  readonly property string approvalsPath: configDir + "/widget-approvals.json"
  property var owlApprovals: ({})
  FileView {
    id: approvalsFile
    // Read before the layout, which may approve migrated ports into it.
    blockLoading: true
    path: root.approvalsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      let data = {}
      try { data = JSON.parse(text() || "{}") || {} } catch (e) { data = {} }
      root.owlApprovals = data
      Qt.callLater(root.recheckApprovals)
    }
  }
  function approveOwl(widgetId, network) {
    const info = HomeModel.isOwlType(widgetId) ? owlBuiltinInfo(widgetId) : owlInfo[widgetId]
    if (!info || !info.ok) return "unknown"
    const next = Object.assign({}, owlApprovals)
    next[widgetId] = { commands: info.program.commands.slice(), devices: info.caps.devices.slice(), network: network === true, at: new Date().toISOString() }
    owlApprovals = next
    approvalsFile.setText(JSON.stringify(next, null, 2) + "\n")
    return "approved"
  }
  function revokeOwl(widgetId) {
    const next = Object.assign({}, owlApprovals)
    delete next[widgetId]
    owlApprovals = next
    approvalsFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  // What a placed OWL widget shows: { state, message, record, info, approval }.
  // ---------- built-ins: the OWL originals of the old ports

  // Their files, from the omamobile-owl-widgets package (read once each).
  property var owlBuiltinCache: ({})
  Component { id: builtinFile; FileView { blockLoading: true; printErrors: false } }
  function owlBuiltinInfo(type) {
    if (owlBuiltinCache[type]) return owlBuiltinCache[type]
    const storeId = HomeModel.owlStoreId(type)
    const view = builtinFile.createObject(root, { path: owlStoreDir + "/widgets/" + storeId + "/widget.owl" })
    const text = view.text()
    view.destroy()
    const info = text ? OwlCatalog.describe(type, text, layout.grid, owlCellHeight, owlDp)
      : { ok: false, error: "The widget store package (omamobile-owl-widgets) doesn't have " + storeId, program: null, caps: null, refusals: [], name: storeId }
    // Named and sized as the built-in always was.
    const spec = HomeModel.widgetSpec(type, null)
    if (spec) info.name = spec.name
    info.text = text
    owlBuiltinCache[type] = info
    return info
  }
  // A port's placement becomes its OWL original (HomeModel.normalize); this
  // approves it, without asking, only when it needs no more than the port had.
  function migratePorts(ports) {
    const r = OwlCatalog.migrationApprovals(ports, owlApprovals, owlBuiltinInfo, HomeModel.portCapabilities)
    r.decisions.forEach(function(d) {
      if (d.verdict === "asks") console.warn("omamobile.home: " + d.to + " needs your OK: " + d.extra.join("; "))
    })
    saveApprovals(r)
  }
  // Earlier automatic approvals, checked again with today's rules.
  function recheckApprovals() {
    saveApprovals(OwlCatalog.recheckAutoApprovals(owlApprovals, owlBuiltinInfo, HomeModel.portCapabilities))
  }
  function saveApprovals(r) {
    if (!r.changed) return
    const stamped = r.approvals
    Object.keys(stamped).forEach(function(k) { if (stamped[k].auto && !stamped[k].at) stamped[k].at = new Date().toISOString() })
    owlApprovals = stamped
    approvalsFile.setText(JSON.stringify(stamped, null, 2) + "\n")
  }

  function owlCard(widgetId) {
    if (HomeModel.isOwlType(widgetId)) {
      const bi = owlBuiltinInfo(widgetId)
      const ba = owlApprovals[widgetId] || null
      const record = { id: widgetId, status: bi.text ? "ok" : "error", errors: bi.text ? [] : [bi.error], hash: "builtin",
                       kind: "owl", owl: { text: bi.text } }
      // Built-ins are always on: they are the home screen's own widgets.
      const bc = OwlCatalog.cardState(true, true, record, bi, ba, guardCrashed[widgetId] === "builtin" ? "builtin" : "")
      bc.record = record
      bc.info = bi
      bc.approval = ba
      return bc
    }
    const r = UserWidgets.findRecord(userScan, widgetId)
    const info = owlInfo[widgetId] || null
    const approval = owlApprovals[widgetId] || null
    const card = OwlCatalog.cardState(owlEnabled, userScan.ok, r, info, approval, r ? guardCrashed[widgetId] : "")
    card.record = r
    card.info = info
    card.approval = approval
    return card
  }

  // Sources run while the widget's page or a neighbour shows and no app
  // covers the home screen (an app on this workspace).
  readonly property bool owlPaused: owlPanelOff || (!!Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.toplevels.values.length > 0)

  // The panel is off when its backlight's bl_power isn't 0, read the way
  // omamobile-keys reads it (the device from omarchy-hw-display). sysfs has
  // no change events, so it is read every 2 s, a cheap file read.
  property bool owlPanelOff: false
  property string owlBacklight: ""
  Process {
    command: ["omarchy-hw-display"]
    running: root.owlEnabled
    stdout: StdioCollector { id: displayName; waitForEnd: true; onStreamFinished: root.owlBacklight = String(displayName.text || "").trim().split("\n")[0] }
  }
  FileView {
    id: blPower
    path: root.owlBacklight ? "/sys/class/backlight/" + root.owlBacklight + "/bl_power" : ""
    printErrors: false
    onLoaded: root.owlPanelOff = OwlPhone.panelOff(text())
  }
  Timer {
    interval: 2000
    repeat: true
    running: root.owlEnabled && root.owlBacklight !== ""
    onTriggered: blPower.reload()
  }

  // An OWL Input has focus: the surface takes the keyboard.
  property bool owlTyping: false
  function owlKeyboard(on) { owlTyping = !!on }
  function owlActive(entryId) {
    const found = HomeModel.findItem(layout, entryId)
    return !!found && Math.abs(found.page - currentPage) <= 1 && !owlPaused
  }

  // The palette OWL names resolve to: the Omarchy theme, with the names that
  // must read on our card taken from the shell (plan §4.1).
  property var owlThemeColors: ({})
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.owlThemeColors = OwlPhone.parseColorsToml(text())
  }
  function argbOf(c) {
    return ((Math.round(c.a * 255) << 24) | (Math.round(c.r * 255) << 16) | (Math.round(c.g * 255) << 8) | Math.round(c.b * 255)) >>> 0
  }
  readonly property var owlPalette: OwlPhone.cardPalette(OwlPhone.palette(owlThemeColors), {
    foreground: argbOf(foreground), dimForeground: argbOf(dimForeground), background: argbOf(Commons.Color.menu.background),
    border: argbOf(Commons.Color.menu.border), accent: argbOf(Commons.Color.accent), urgent: argbOf(Commons.Color.urgent)
  })
  readonly property var owlInk: {
    const out = {}
    for (const k in owlPalette) {
      const s = (owlPalette[k] >>> 0).toString(16)
      out[k] = "#" + "00000000".slice(s.length) + s
    }
    return out
  }

  OwlPhoneHost { id: owlHostObject; home: root }
  // Not readonly: the offscreen renders (test/home-render.qml) put a host
  // that answers from fixtures in its place, so no widget runs a command.
  property var owlHost: owlHostObject
  Owl.OwlScheduler { id: owlSchedulerObject; paused: root.owlPaused }
  readonly property var owlScheduler: owlSchedulerObject

  // ---------- the Store tab (omamobile-owl-widgets, plan §5.1)

  // The package's index, and what "Check the store now" downloaded, if anything.
  readonly property string owlStoreDir: Quickshell.env("OMAMOBILE_OWL_STORE") || "/usr/share/omamobile/owl-widgets"
  readonly property string owlStoreCache: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/omamobile/owl-store"
  property var owlStoreIndex: ({ widgets: [] })
  property var owlStoreFetched: ({ widgets: [] })
  FileView {
    path: root.owlEnabled ? root.owlStoreDir + "/index.json" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.owlStoreIndex = JSON.parse(text()) } catch (e) { root.owlStoreIndex = { widgets: [] } } }
  }
  FileView {
    id: fetchedIndex
    path: root.owlEnabled ? root.owlStoreCache + "/index.json" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.owlStoreFetched = JSON.parse(text()) } catch (e) { root.owlStoreFetched = { widgets: [] } } }
  }
  readonly property var owlStoreRows: OwlCatalog.storeRows(owlStoreIndex, owlStoreFetched,
    userScan.widgets.filter(function(r) { return r.kind === "owl" }), layout.grid, owlCellHeight, owlDp)
  property string owlStoreDetail: ""
  property string owlStoreMessage: ""
  // A widget just copied from the store: its approval sheet opens once the scan sees it.
  property string pendingApprove: ""

  function openStoreWidget(storeId) {
    owlStoreDetail = String(storeId)
    setEditing(true)
    sheet = "owl-store"
  }
  // Copies the store's file into the widgets folder, then asks for approval.
  function addFromStore(storeId) {
    const id = String(storeId).replace("/", ".")
    if (UserWidgets.findRecord(userScan, id)) { openOwlApproval(id); return id }
    runHelper(UserWidgets.storeCopyArgv(storeId), function(code, out, err) {
      if (code !== 0) { root.flash(err.trim() || "Couldn't copy it"); return }
      root.pendingApprove = id
      root.scanWidgets()
    })
    return id
  }
  function updateFromStore(widgetId) {
    runHelper(UserWidgets.storeUpdateArgv(widgetId), function(code, out, err) {
      root.flash(code === 0 ? "Updated; if it runs anything new, it asks again" : (err.trim() || "Couldn't update it"))
      root.scanWidgets()
    })
  }
  // Only when the user taps "Check the store now": the one network fetch of
  // widget code, every file checked against the store's index.
  function fetchStore() {
    owlStoreMessage = "Checking the store\u2026"
    runHelper(UserWidgets.STORE_FETCH_ARGV, function(code, out, err) {
      root.owlStoreMessage = code === 0 ? "Checked: " + out.trim() : (err.trim().split("\n").slice(-1)[0] || "Couldn't reach the store")
      fetchedIndex.reload()
    })
  }

  // The approval sheet.
  property string owlApproveId: ""
  function openOwlApproval(widgetId) {
    owlApproveId = String(widgetId)
    setEditing(true)
    sheet = "owl-approve"
  }

  // ---------- the helper (omamobile-widget new | copy-example | remove | agent)

  property var helperDone: null
  property bool helperBusy: false
  Process {
    id: helper
    stdout: StdioCollector { id: helperOut; waitForEnd: true }
    stderr: StdioCollector { id: helperErr; waitForEnd: true }
    onExited: function(code) {
      var done = root.helperDone
      root.helperDone = null
      root.helperBusy = false
      if (done) done(code, String(helperOut.text || ""), String(helperErr.text || ""))
    }
  }

  function runHelper(argv, done) {
    if (helperBusy) { flash("Still busy with the last one"); return false }
    helperBusy = true
    helperDone = done
    helper.command = argv
    helper.running = true
    return true
  }

  // The Create sheet's state: "create" a new widget, or "edit" createTarget.
  property string createMode: "create"
  property string createTarget: ""
  property string createText: ""
  property string createError: ""

  function openCreate(mode, widgetId) {
    createMode = mode === "edit" ? "edit" : "create"
    createTarget = createMode === "edit" ? String(widgetId || "") : ""
    createError = ""
    setEditing(true)
    sheet = "create"
  }

  function userIds() {
    return userScan.widgets.map(function(r) { return r.id })
  }

  // Create: a folder from the template, placed as soon as the scan sees it,
  // and the agent started in it with the description.
  function createWidgetNow(description) {
    var text = String(description || "").trim()
    if (!text) { createError = "Describe the widget first"; return "empty" }
    // A second try (say, after choosing an agent) reuses the folder made by
    // the first.
    if (createTarget && UserWidgets.findRecord(userScan, createTarget)) {
      startAgent(createTarget, UserWidgets.createPrompt(text, widgetsDir + "/" + createTarget, userScan.contract))
      return createTarget
    }
    var id = UserWidgets.newId(text, Quickshell.env("USER"), userIds())
    createError = ""
    runHelper(UserWidgets.newArgv(id, UserWidgets.nameFrom(text)), function(code, out, err) {
      if (code !== 0) { root.createError = err.trim() || "Couldn't create the widget folder"; return }
      root.createTarget = id
      root.pendingAdd = id
      root.scanWidgets()
      root.startAgent(id, UserWidgets.createPrompt(text, root.widgetsDir + "/" + id, root.userScan.contract))
    })
    return id
  }

  function editWidget(widgetId, description) {
    var r = UserWidgets.findRecord(userScan, widgetId)
    if (!r) { createError = "No widget called " + widgetId; return "unknown" }
    var name = r.manifest ? r.manifest.name : widgetId
    var errors = r.errors.slice()
    var runtime = runtimeErrors[widgetId]
    if (runtime && runtime.hash === r.hash) errors.push(runtime.message)
    startAgent(widgetId, UserWidgets.editPrompt(description, r.dir, userScan.contract, name, errors))
    return widgetId
  }

  function startAgent(widgetId, prompt) {
    var started = runHelper(UserWidgets.agentArgv(widgetId, prompt), function(code, out, err) {
      var outcome = UserWidgets.agentOutcome(code, err)
      if (outcome.kind === "launched") {
        if (root.createMode === "create") root.createTarget = ""
        root.createText = ""
        root.createError = ""
        root.setEditing(false)
        root.flash("Opening " + (root.agentId || "the agent") + "…")
      } else {
        root.createError = outcome.message
        if (root.sheet !== "create") root.flash(outcome.message.split("\n")[0])
      }
    })
    if (started) createError = ""
  }

  function removeUserWidget(widgetId) {
    runHelper(UserWidgets.removeArgv(widgetId), function(code, out, err) {
      if (code !== 0) { root.flash(err.trim() || "Couldn't remove it"); return }
      root.commit(HomeModel.removeWidgetType(root.layout, UserWidgets.typeFor(widgetId)))
      root.flash("Removed; the folder is in ~/.local/share/omamobile/removed-widgets")
      root.scanWidgets()
    })
  }

  // An installed example becomes the user's own copy, then goes on the page.
  function copyExample(widgetId) {
    if (UserWidgets.findRecord(userScan, widgetId)) return addWidgetHere(UserWidgets.typeFor(widgetId))
    runHelper(UserWidgets.copyArgv(widgetId), function(code, out, err) {
      if (code !== 0) { root.flash(err.trim() || "Couldn't copy it"); return }
      root.pendingAdd = widgetId
      root.scanWidgets()
    })
    return widgetId
  }

  // ---------------------------------------------------------------- the fingerprint guard

  // No long-press while a fingerprint operation runs, or while the finger
  // that reached the sensor is still down: that touch is not meant for the
  // home screen. omamobile.fingerprint's desktop guard covers this surface
  // too (it maps above it); this is the same rule from our side.
  readonly property string fpStatePath: Quickshell.env("OMAMOBILE_FP_UI_STATE") || "/run/omamobile-fp-ui/state.json"
  property bool fpBusy: false
  property real fpQuietUntil: 0

  FileView {
    path: root.fpStatePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var s = null
      try { s = JSON.parse(text()) } catch (e) { s = null }
      var busy = !!s && (s.op === "enroll" || s.op === "auth" || s.contact === true)
      if (root.fpBusy && !busy) root.fpQuietUntil = Date.now() + 1500
      root.fpBusy = busy
    }
    onLoadFailed: root.fpBusy = false
  }

  function longPressAllowed() {
    return !fpBusy && Date.now() >= fpQuietUntil
  }

  // ---------------------------------------------------------------- actions

  function goToPage(index, animate) {
    var i = Math.max(0, Math.min(viewLayout.pages.length - 1, Number(index) || 0))
    currentPage = i
    if (pager) {
      pager.highlightMoveDuration = animate === false ? 0 : 250
      pager.currentIndex = i
    }
  }

  function setEditing(on) {
    editing = !!on && !landscape
    if (!editing) { sheet = ""; settingsId = "" }
  }

  function requestEdit() {
    if (!longPressAllowed()) return "busy"
    if (landscape) { flash("Turn the phone upright to edit"); return "landscape" }
    setEditing(true)
    return "editing"
  }

  // Through omamobile-launch, as the drawer does: the app starts the way
  // Omarchy starts it (uwsm-app -- gtk-launch) on a new empty workspace, or
  // is focused on its own if it is already open.
  function launch(appId) {
    var entry = entryFor(appId)
    if (!entry || !entry.id) return false
    if (appLibrary && typeof appLibrary.beginLaunchFeedback === "function")
      appLibrary.beginLaunchFeedback(appLibrary.entryName(entry))
    Quickshell.execDetached(HomeModel.appLaunchArgv(entry.id))
    return true
  }

  function addWidgetHere(type, keepSheet) {
    var next = HomeModel.addWidget(layout, currentPage, type, userCatalog)
    if (!next) return "unknown"
    if (!next.placed) { flash("No room for that"); return "full" }
    commit(next)
    goToPage(next.placed.page, true)
    if (keepSheet !== true) sheet = ""
    var spec = HomeModel.widgetSpec(type, userCatalog)
    // Built-in network widgets start off and ask for their settings; an OWL
    // built-in asks on its approval sheet instead.
    if (HomeModel.isOwlType(type)) { if (owlCard(type).state === "approve") openOwlApproval(type) }
    else if (spec && spec.network && !spec.user) openSettings(next.placed.id)
    return next.placed.id
  }

  function addAppHere(appId, page) {
    var next = HomeModel.addApp(layout, page === undefined ? currentPage : page, appId)
    if (!next || !next.placed) { flash("No room for that"); return "full" }
    commit(next)
    goToPage(next.placed.page, true)
    sheet = ""
    return next.placed.id
  }

  // Removing takes one tap (or Remove's two in the settings sheet), so it
  // can be undone for a few seconds (TOUCH-PLAN 1.10): the chip puts the
  // item back with its settings (a weather place, a note), in its cell or
  // the nearest free one, even after other edits.
  function removeItem(id) {
    var found = HomeModel.findItem(layout, id)
    if (!found) return
    commit(HomeModel.removeItem(layout, id))
    if (settingsId === id) { sheet = ""; settingsId = "" }
    undoRemoved = found
    notice = found.item.kind === "app" ? "App removed" : "Widget removed"
    noticeTimer.interval = 5000
    noticeTimer.restart()
  }

  function undoRemove() {
    var removed = undoRemoved
    undoRemoved = null
    notice = ""
    noticeTimer.stop()
    if (!removed) return "none"
    var next = HomeModel.restoreItem(layout, removed)
    if (!next) { flash("No room to put it back"); return "full" }
    commit(next)
    goToPage(next.placed.page, true)
    return removed.item.id
  }

  function moveItem(id, page, x, y) {
    if (page >= layout.pages.length) commit(HomeModel.addPage(layout))
    var next = HomeModel.moveItem(layout, id, page, x, y)
    if (next.moved === false) { flash("No room on that page"); return }
    commit(next)
    var found = HomeModel.findItem(next, id)
    if (found && found.page !== currentPage) goToPage(found.page, true)
  }

  function resizeItem(id, w, h) {
    commit(HomeModel.resizeItem(layout, id, w, h, userCatalog))
  }

  function setConfig(id, patch) {
    commit(HomeModel.setConfig(layout, id, patch, userCatalog))
  }

  function openSettings(id) {
    var found = HomeModel.findItem(layout, id)
    if (!found || found.item.kind !== "widget") return
    settingsId = id
    sheet = "settings"
  }

  function openStyleMenu() {
    // The desktop's long-press menu before the home screen covered it
    // (patches/omarchy/0005): Omarchy's Style menu, wallpaper and theme.
    Quickshell.execDetached(["omarchy-menu", "summon", "style"])
    setEditing(false)
  }

  function flash(text) {
    undoRemoved = null
    notice = text
    noticeTimer.interval = 2200
    noticeTimer.restart()
  }
  Timer { id: noticeTimer; interval: 2200; onTriggered: { root.notice = ""; root.undoRemoved = null } }

  // ---------------------------------------------------------------- host lifecycle and IPC

  // `shell summon omamobile.home '{"edit":true}'` enters edit mode,
  // '{"page":N}' shows a page. The surface itself is always there, so the
  // host is told we're closed again at once.
  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    if (payload.edit === true) setEditing(true)
    if (typeof payload.page === "number") goToPage(payload.page, true)
    Qt.callLater(function() {
      if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    })
  }

  function close() { setEditing(false) }

  // `shell call omamobile.home <method> <arg>`:
  function goHome() { setEditing(false); goToPage(layout.home, true); return String(layout.home) }
  function page(n) { goToPage(Number(n), true); return String(currentPage) }
  function edit(on) { return String(on) === "off" || String(on) === "false" ? (setEditing(false), "done") : requestEdit() }
  function addApp(appId) { return addAppHere(String(appId || "")) }
  function addWidget(type) {
    var t = String(type)
    return HomeModel.widgetSpec(t, userCatalog) || HomeModel.isUserType(t) ? addWidgetHere(t) : "unknown"
  }
  // `shell call omamobile.home owlStatus <id>`: what the home screen makes of
  // an OWL widget (compiles, problems, commands, approval), for an agent.
  function owlStatus(id) {
    const info = owlInfo[String(id)]
    if (!info) return owlEnabled ? "unknown" : "off"
    const card = owlCard(String(id))
    return JSON.stringify({ id: String(id), status: card.state, message: card.message, compiles: info.ok, error: info.error,
                            commands: info.ok ? info.program.commands : [], capabilities: info.ok ? info.spec.capabilities : [],
                            risks: info.caps ? info.caps.risks : [], approved: card.state === "ok" })
  }
  function showSheet(name) {
    if (["widgets", "apps", "pages", "create", ""].indexOf(String(name)) < 0) return "unknown"
    if (name === "create") { openCreate("create", ""); return sheet }
    setEditing(true); sheet = String(name); return sheet
  }
  // User widgets: `widgets ''` lists them with their verdicts, `widgetStatus
  // <id>` is one (what an agent checks after saving), `rescanWidgets ''`
  // scans now, `createWidget <description>` and `editWidget <id>` start the
  // agent as the sheet does, `copyExample <id>` copies and places one.
  function widgets() {
    return JSON.stringify(userScan.widgets.map(function(r) { return root.widgetSummary(r) }))
  }
  function widgetStatus(id) {
    var r = UserWidgets.findRecord(userScan, String(id))
    return r ? JSON.stringify(widgetSummary(r)) : "unknown"
  }
  function widgetSummary(r) {
    var card = userCard(r.id)
    var placed = 0
    layout.pages.forEach(function(p) { p.items.forEach(function(i) { if (i.type === UserWidgets.typeFor(r.id)) placed++ }) })
    return { id: r.id, name: r.manifest ? r.manifest.name : "", status: card.state, errors: card.state === "ok" ? [] : card.message.split("\n"),
             warnings: r.warnings, capabilities: r.manifest ? r.manifest.capabilities : [], undeclared: r.undeclared,
             hash: r.hash, dir: r.dir, placed: placed }
  }
  function rescanWidgets() { scanWidgets(); return "ok" }
  function createWidget(description) { openCreate("create", ""); createText = String(description || ""); return createWidgetNow(createText) }
  function settings(id) { openSettings(String(id)); return sheet === "settings" ? settingsId : "none" }
  function state() {
    return JSON.stringify({
      loaded: loaded, path: layoutPath, page: currentPage, pages: layout.pages.length, home: layout.home,
      grid: layout.grid, landscape: landscape, viewGrid: viewLayout.grid, editing: editing, sheet: sheet, settings: settingsId, fpBusy: fpBusy,
      items: layout.pages.map(function(p) { return p.items.length }),
      missing: HomeModel.missingApps(layout, availableAppIds())
    })
  }
  function dump() { return HomeModel.serialize(layout) }
  function undo() { return undoRemove() }

  // ---------------------------------------------------------------- the surface

  PanelWindow {
    id: surface

    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    anchors { top: true; bottom: true; left: true; right: true }
    // Normal: between the bar and the dock, which reserve their space.
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-home"
    // Bottom: above the wallpaper, below every window.
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: root.wantsKeyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Item {
      id: screenItem
      anchors.fill: parent
      focus: true
      onWidthChanged: root.owlScreenWidth = width
      onHeightChanged: root.owlScreenHeight = height
      Keys.onEscapePressed: {
        if (root.sheet) root.sheet = ""
        else root.setEditing(false)
      }

      // ---------- pages
      ListView {
        id: pager
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: dots.top
        anchors.topMargin: Style.spacing.lg
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        highlightMoveDuration: 250
        boundsBehavior: Flickable.StopAtBounds
        // In edit mode a drag moves items; pages change by swiping empty
        // space or tapping the dots.
        interactive: !root.editing && root.sheet === ""
        flickDeceleration: 4000
        cacheBuffer: width * 2
        model: root.viewLayout.pages.length
        onCurrentIndexChanged: root.currentPage = currentIndex

        delegate: Page { }
        onWidthChanged: root.owlPageWidth = width
        onHeightChanged: root.owlPagerHeight = height
      }

      // ---------- page dots
      Row {
        id: dots
        objectName: "pageDots"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: toolbar.visible ? toolbar.top : parent.bottom
        height: root.viewLayout.pages.length > 1 || root.editing ? 28 : Style.spacing.lg
        spacing: 0

        Repeater {
          model: root.viewLayout.pages.length > 1 || root.editing ? root.viewLayout.pages.length : 0
          delegate: Item {
            required property int index
            width: 22; height: 28
            Rectangle {
              anchors.centerIn: parent
              width: index === root.currentPage ? 9 : 7
              height: width
              radius: width / 2
              color: index === root.currentPage ? root.foreground : root.dimForeground
              opacity: index === root.currentPage ? 1 : 0.6
              border.width: index === root.layout.home && root.editing ? 1 : 0
              border.color: Commons.Color.accent
            }
            // 44 px tall, reaching past the 28 px row so the layout stays.
            MouseArea {
              anchors.centerIn: parent
              width: parent.width
              height: Math.max(44, parent.height)
              onClicked: root.goToPage(index, true)
            }
          }
        }
      }

      // ---------- edit toolbar
      Row {
        id: toolbar
        objectName: "editToolbar"
        visible: root.editing
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: Style.spacing.sm
        height: visible ? root.touch + Style.spacing.lg : 0
        spacing: Style.spacing.sm

        Repeater {
          model: [
            { label: "Widgets", glyph: "󰕰", act: "widgets" },
            { label: "Apps", glyph: "󰀻", act: "apps" },
            { label: "Style", glyph: "", act: "style" },
            { label: "Pages", glyph: "󰓩", act: "pages" },
            { label: "Done", glyph: "󰄬", act: "done" }
          ]
          delegate: BorderSurface {
            required property var modelData
            width: Math.floor((screenItem.width - Style.spacing.lg * 2 - Style.spacing.sm * 4) / 5)
            height: root.touch + Style.spacing.lg
            radius: Style.cornerRadius
            color: barTap.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
              : modelData.act === "done" ? Commons.Color.accent : Commons.Color.menu.background
            borderSpec: Border.controlSpec("normal", root.foreground, Commons.Color.accent)

            Column {
              anchors.centerIn: parent
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: modelData.glyph
                color: modelData.act === "done" ? Commons.Color.background : root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.iconLarge
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: modelData.label
                color: modelData.act === "done" ? Commons.Color.background : root.foreground
                font.family: Style.font.family
                font.pixelSize: Readable.px(Style.font.caption)
              }
            }
            MouseArea {
              id: barTap
              anchors.fill: parent
              onClicked: {
                var a = modelData.act
                if (a === "done") root.setEditing(false)
                else if (a === "style") root.openStyleMenu()
                else root.sheet = root.sheet === a ? "" : a
              }
            }
          }
        }
      }

      // ---------- long-press anywhere: edit mode
      // On top of everything and passive (DragThreshold takes no grab), so
      // apps and widgets still get their taps and the pager its swipes; a
      // drag cancels it.
      Item {
        anchors.fill: pager
        z: 50
        TapHandler {
          enabled: !root.editing && root.sheet === ""
          gesturePolicy: TapHandler.DragThreshold
          longPressThreshold: 0.5
          onLongPressed: root.requestEdit()
        }
      }

      // ---------- a short notice, with Undo after a remove
      Rectangle {
        id: noticePill
        objectName: "notice"
        z: 60
        visible: root.notice !== ""
        readonly property bool canUndo: root.undoRemoved !== null
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: dots.top
        anchors.bottomMargin: Style.spacing.lg
        width: noticeText.implicitWidth + Style.spacing.xxl * 2 + (canUndo ? undoChip.width + Style.spacing.md : 0)
        height: canUndo ? root.touch : noticeText.implicitHeight + Style.spacing.lg * 2
        radius: height / 2
        color: Commons.Color.menu.background
        Text {
          id: noticeText
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.xxl
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.notice
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        // A full touch target, though the chip looks smaller.
        Item {
          id: undoChip
          visible: noticePill.canUndo
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: undoText.implicitWidth + Style.spacing.xxl * 2
          height: root.touch
          Rectangle {
            anchors.fill: parent
            anchors.margins: Style.spacing.xs
            radius: height / 2
            color: undoTap.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent) : "transparent"
          }
          Text {
            id: undoText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "Undo"
            color: Commons.Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
          // A MouseArea, as the remove cross: it keeps the tap from the
          // page below, where a tap would leave edit mode.
          MouseArea {
            id: undoTap
            anchors.fill: parent
            onClicked: root.undoRemove()
          }
        }
      }

      // ---------- sheets
      HomeSheets {
        z: 100
        anchors.fill: parent
        home: root
      }
    }
  }

  // ---------------------------------------------------------------- one page

  component Page: Item {
    id: page

    required property int index
    width: pager.width
    height: pager.height

    readonly property var items: root.viewLayout.pages[index] ? root.viewLayout.pages[index].items : []
    readonly property int columns: root.viewLayout.grid.columns
    readonly property int rows: root.viewLayout.grid.rows
    readonly property real cellW: width / columns
    readonly property real cellH: height / rows
    // Where a dragged item would land, in cells (null: not dragging).
    property var preview: null

    // Empty space in edit mode: a tap leaves it, a swipe changes page.
    Item {
      anchors.fill: parent
      TapHandler {
        enabled: root.editing
        onTapped: root.setEditing(false)
      }
      DragHandler {
        enabled: root.editing
        target: null
        yAxis.enabled: false
        property real dx: 0
        onActiveTranslationChanged: dx = activeTranslation.x
        onActiveChanged: {
          if (active) { dx = 0; return }
          if (dx < -60) root.goToPage(page.index + 1, true)
          else if (dx > 60) root.goToPage(page.index - 1, true)
        }
      }
    }

    // The grid, faintly, while editing.
    Repeater {
      model: root.editing ? page.columns * page.rows : 0
      delegate: Rectangle {
        required property int index
        x: (index % page.columns) * page.cellW + root.gap
        y: Math.floor(index / page.columns) * page.cellH + root.gap
        width: page.cellW - root.gap * 2
        height: page.cellH - root.gap * 2
        radius: Style.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: Util.alpha(root.foreground, 0.14)
      }
    }

    Rectangle {
      visible: !!page.preview
      x: page.preview ? page.preview.x * page.cellW + root.gap : 0
      y: page.preview ? page.preview.y * page.cellH + root.gap : 0
      width: page.preview ? page.preview.w * page.cellW - root.gap * 2 : 0
      height: page.preview ? page.preview.h * page.cellH - root.gap * 2 : 0
      radius: Style.cornerRadius
      color: Util.alpha(Commons.Color.accent, 0.22)
      border.width: 2
      border.color: Commons.Color.accent
    }

    Repeater {
      model: page.items
      delegate: Cell { owner: page }
    }
  }

  // ---------------------------------------------------------------- one item

  component Cell: Item {
    id: cell

    required property var modelData
    property var owner: null
    readonly property bool isWidget: modelData.kind === "widget"

    property real dragX: 0
    property real dragY: 0
    property bool dragging: false
    property real growX: 0
    property real growY: 0
    property bool resizing: false

    readonly property var limits: HomeModel.sizeLimits(modelData, root.viewLayout.grid, root.userCatalog)
    readonly property bool isUser: isWidget && HomeModel.isUserType(modelData.type)
    x: modelData.x * owner.cellW + dragX
    y: modelData.y * owner.cellH + dragY
    width: Math.max(limits.minW * owner.cellW, Math.min(limits.maxW * owner.cellW, modelData.w * owner.cellW + growX))
    height: Math.max(limits.minH * owner.cellH, Math.min(limits.maxH * owner.cellH, modelData.h * owner.cellH + growY))
    z: dragging || resizing ? 20 : 1

    // The widget's card. Plain and opaque enough to read on any wallpaper;
    // no blur or shadow, to keep the 120 Hz panel smooth.
    Rectangle {
      id: card
      anchors.fill: parent
      anchors.margins: root.gap
      visible: cell.isWidget
      radius: Math.max(Style.cornerRadius, 12)
      color: root.cardColor
    }

    Loader {
      id: content
      anchors.fill: cell.isWidget ? card : parent
      clip: cell.isWidget
      // A user widget goes through UserWidgetCell, which loads its code
      // only when the scan calls it ok and shows an error card otherwise.
      source: (cell.isUser && root.isOwlType(cell.modelData.type)) || HomeModel.isOwlType(cell.modelData.type) ? Qt.resolvedUrl("OwlCell.qml")
        : cell.isUser ? Qt.resolvedUrl("UserWidgetCell.qml")
        : cell.isWidget ? Qt.resolvedUrl(cell.modelData.type.charAt(0).toUpperCase() + cell.modelData.type.slice(1) + "Widget.qml")
        : Qt.resolvedUrl("AppTile.qml")
      onLoaded: {
        item.home = root
        item.entry = Qt.binding(function() { return cell.modelData })
        item.editing = Qt.binding(function() { return root.editing })
      }
    }

    // ---------- edit mode
    Rectangle {
      anchors.fill: parent
      anchors.margins: root.gap / 2
      visible: root.editing
      radius: Math.max(Style.cornerRadius, 12)
      color: cell.dragging ? Util.alpha(Commons.Color.accent, 0.12) : "transparent"
      border.width: cell.dragging || cell.resizing ? 2 : 1
      border.color: Commons.Color.accent
    }

    // Drag to move; a tap on a widget opens its settings.
    MouseArea {
      anchors.fill: parent
      enabled: root.editing
      preventStealing: true
      property point start
      onPressed: function(mouse) {
        start = mapToItem(cell.owner, mouse.x, mouse.y)
      }
      onPositionChanged: function(mouse) {
        var p = mapToItem(cell.owner, mouse.x, mouse.y)
        var dx = p.x - start.x, dy = p.y - start.y
        if (!cell.dragging && Math.abs(dx) + Math.abs(dy) < 10) return
        cell.dragging = true
        cell.dragX = dx
        cell.dragY = dy
        cell.owner.preview = cell.target()
      }
      onReleased: {
        if (cell.dragging) {
          var t = cell.target()
          cell.owner.preview = null
          cell.dragging = false
          cell.dragX = 0; cell.dragY = 0
          root.moveItem(cell.modelData.id, t.page, t.x, t.y)
        } else if (cell.isWidget) {
          root.openSettings(cell.modelData.id)
        }
      }
      onCanceled: { cell.dragging = false; cell.dragX = 0; cell.dragY = 0; cell.owner.preview = null }
    }

    // Where the dragged item lands: { page, x, y, w, h }.
    function target() {
      var grid = root.viewLayout.grid
      var cx = (modelData.x * owner.cellW + dragX) / owner.cellW
      var shift = HomeModel.pageShift(cx, modelData.w, grid)
      var cellAt = HomeModel.cellForPoint(modelData.x * owner.cellW + dragX, modelData.y * owner.cellH + dragY,
                                          owner.cellW, owner.cellH, modelData.w, modelData.h, grid)
      var p = owner.index + shift
      if (p < 0) { p = 0; shift = 0 }
      if (shift !== 0) cellAt.x = shift < 0 ? grid.columns - modelData.w : 0
      return { page: p, x: cellAt.x, y: cellAt.y, w: modelData.w, h: modelData.h, shift: shift }
    }

    // Remove.
    Item {
      visible: root.editing && !cell.dragging
      anchors.left: parent.left
      anchors.top: parent.top
      width: root.touch
      height: root.touch
      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        width: 24; height: 24; radius: 12
        color: Commons.Color.urgent
        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "󰅖"
          color: "white"
          font.family: Style.font.family
          font.pixelSize: 14
        }
      }
      MouseArea { anchors.fill: parent; onClicked: root.removeItem(cell.modelData.id) }
    }

    // Resize (widgets that can change size).
    Item {
      visible: root.editing && cell.isWidget && !cell.dragging
        && (cell.limits.maxW > cell.limits.minW || cell.limits.maxH > cell.limits.minH)
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      width: root.touch
      height: root.touch
      Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 26; height: 26; radius: 13
        color: Commons.Color.accent
        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "󰁃"
          rotation: 0
          color: Commons.Color.background
          font.family: Style.font.family
          font.pixelSize: 15
        }
      }
      MouseArea {
        anchors.fill: parent
        preventStealing: true
        property point start
        onPressed: function(mouse) { start = mapToItem(cell.owner, mouse.x, mouse.y); cell.resizing = true }
        onPositionChanged: function(mouse) {
          var p = mapToItem(cell.owner, mouse.x, mouse.y)
          cell.growX = p.x - start.x
          cell.growY = p.y - start.y
          cell.owner.preview = { x: cell.modelData.x, y: cell.modelData.y,
                                w: Math.max(1, Math.round(cell.width / cell.owner.cellW)),
                                h: Math.max(1, Math.round(cell.height / cell.owner.cellH)) }
        }
        onReleased: {
          var w = Math.round(cell.width / cell.owner.cellW)
          var h = Math.round(cell.height / cell.owner.cellH)
          cell.growX = 0; cell.growY = 0; cell.resizing = false
          cell.owner.preview = null
          root.resizeItem(cell.modelData.id, w, h)
        }
        onCanceled: { cell.growX = 0; cell.growY = 0; cell.resizing = false; cell.owner.preview = null }
      }
    }
  }
}
