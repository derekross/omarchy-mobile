// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TilesModel.js" as TilesModel
import "NotificationsModel.js" as NotificationsModel
import "Readable.js" as Readable

// Pull-down quick settings for the phone. The sheet drops from the top edge
// over the status bar, collapsed as on Android: a clock header, the first
// four tiles and brightness. A pull down on the sheet (or a tap on its
// handle) expands it to every tile, a page of eight at a time with a
// sideways swipe between pages, and volume. Tap outside it, swipe it up, or
// press Escape to put it away. The Wi-Fi and Bluetooth tiles' chevrons (or a
// long-press) open the panels in WifiPanel.qml and BluetoothPanel.qml.
//
// Under the sheet, a second card is the notification shade: Omarchy's
// notification history, newest first, with Clear all (NotificationsModel.js);
// a row swipes sideways to take that one notification away (NotificationRow).
// The gear in the header opens Omarchy's menu at its root (Settings).
//
// The pencil under the expanded grid enters edit mode: tap a tile to remove
// it, hold and drag one to move it, tap one under "Add tiles" to add it.
// The layout is per user, in ~/.config/omamobile/quicksettings.json
// (TilesModel.js has the format and the default).
//
// On its side (TOUCH-PLAN 2.4: 1040x480) the sheet keeps to the left 58%
// of the width with the shade beside it, the tile grids take as many
// columns as fit 180 px each, and a sheet taller than the screen scrolls.
//
// Backends are the same ones Omarchy's desktop panels drive: Quickshell's
// NetworkManager and BlueZ services, omarchy-bluetooth-power, PipeWire, the
// notification service's do-not-disturb, and brightnessctl for the panel
// backlight. Tiles with no backend on this device render dimmed and do
// nothing; see the STUB notes below.
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  property bool opened: false
  readonly property string pluginId: (manifest && manifest.id) || "omamobile.quicksettings"

  // ---------------------------------------------------------------- lifecycle

  // A payload of {"page": "wifi"} or {"page": "bluetooth"} opens that panel
  // instead of the sheet.
  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (error) {}
    if (payload.page === "wifi" || payload.page === "bluetooth") {
      openPage(payload.page)
      // Let the host finish delivering this open before it hears a hide.
      Qt.callLater(root.dismiss)
      return
    }
    wifiPicker.close()
    bluetoothPanelItem.close()
    if (editing) finishEditing()
    expanded = payload.expanded === true
    if (payload.page === "edit") startEditing()
    opened = true
    refreshProbe()
    refreshDnd()
    brightness.refresh()
    torch.refresh()
    rotationLock.refresh()
    location.refresh()
    nfc.refresh()
    fingerprint.refresh()
    keyboard.refresh()
    refreshNotifications()
    clockFormatRead.running = true
  }

  // Host-initiated close (`shell hide`).
  function close() {
    if (editing) finishEditing()
    confirmClear = false
    opened = false
  }

  // User-initiated close routes through the host so its open state stays in step.
  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  // `shell call omamobile.quicksettings state` for scripts and tests.
  function state() {
    return JSON.stringify({
      opened: opened,
      expanded: expanded,
      editing: editing,
      tiles: layout,
      wifi: wifi.enabled,
      bluetooth: bluetooth.enabled,
      doNotDisturb: dnd.enabled,
      torch: torch.available ? torch.enabled : null,
      brightness: brightness.available ? brightness.percent : null,
      volume: audio.available ? Math.round(audio.volume * 100) : null,
      wifiPanel: wifiPicker.opened,
      bluetoothPanel: bluetoothPanelItem.opened,
      notifications: notifications.length
    })
  }

  // `shell call omamobile.quicksettings notificationRows ''`: the shade's rows
  // as JSON (as last read; the sheet re-reads them when it opens).
  // `clearNotifications ''` is Clear all without its confirming second tap.
  function notificationRows() {
    return JSON.stringify(notifications)
  }

  function clearNotifications() {
    clearAllNotifications()
    return "ok"
  }

  // `dismissNotification <key>`: a swipe away without the finger, for one
  // row by its key (notificationRows lists them).
  function dismissNotification(key) {
    for (var i = 0; i < notifications.length; i++)
      if (notifications[i].key === String(key)) return forgetNotification(notifications[i]) ? "ok" : "none"
    return "none"
  }

  // `shell call omamobile.quicksettings openSettings ''`: the header's gear.
  function openSettings() {
    root.dismiss()
    Quickshell.execDetached(["omarchy-menu", "summon", "root"])
    return "ok"
  }

  // `shell call omamobile.quicksettings openBluetooth ''`: the same as the
  // Bluetooth tile's chevron. `bluetoothPanel ''` returns its state as JSON.
  function openBluetooth() {
    if (!bluetooth.available) return "unavailable"
    openBluetoothPanel()
    return bluetoothPanelItem.snapshot()
  }

  function bluetoothPanel() {
    return bluetoothPanelItem.snapshot()
  }

  // `shell call omamobile.quicksettings openWifi ''`: the same as the tile's
  // chevron. `wifiPanel ''` returns the picker's state as JSON.
  function openWifi() {
    if (!wifi.available) return "unavailable"
    openWifiPanel()
    return wifiPicker.snapshot()
  }

  function wifiPanel() {
    return wifiPicker.snapshot()
  }

  // `shell call omamobile.quicksettings toggleTile <name>`: the same
  // action as tapping a tile (any TilesModel id, shown or not). Returns the
  // new state() or "unknown".
  function toggleTile(name) {
    var target = backends[String(name || "")]
    if (!target) return "unknown"
    if (!target.available) return "unavailable"
    target.toggle()
    return state()
  }

  // `shell call omamobile.quicksettings tiles ''` lists every tile with its
  // state; `setTiles 'wifi torch dnd'` saves a layout (space-separated ids,
  // since qs ipc splits its arguments on commas; unknown ids are dropped),
  // `resetTiles ''` the default.
  function tiles() {
    var out = []
    for (var i = 0; i < TilesModel.CATALOG.length; i++) {
      var id = TilesModel.CATALOG[i].id
      var b = backends[id]
      out.push({ id: id, shown: TilesModel.indexOf(layout, id) >= 0, available: !!b && b.available,
                 enabled: !!b && b.enabled, status: b ? b.status : "" })
    }
    return JSON.stringify(out)
  }

  function setTiles(ids) {
    var list = TilesModel.parseList(ids)
    if (!list) return "invalid"
    saveLayout(list)
    return JSON.stringify(layout)
  }

  // `showPage <n>`: the expanded grid's page n (from 0), for scripts and
  // screenshots.
  function showPage(n) {
    expanded = true
    pager.currentIndex = Math.max(0, Math.min(tilePages.length - 1, parseInt(n, 10) || 0))
    return String(pager.currentIndex)
  }

  function resetTiles() {
    saveLayout(TilesModel.defaults())
    return JSON.stringify(layout)
  }

  // Every tile's backend by TilesModel id. Each has available, enabled,
  // status, icon and toggle(); details (a chevron and a page) or longPress
  // (related settings) come with openDetails().
  readonly property var backends: ({
    "wifi": wifi, "bluetooth": bluetooth, "mobile-data": mobileData, "airplane": airplane,
    "hotspot": hotspot, "dnd": dnd, "torch": torch, "rotation-lock": rotationLock,
    "location": location, "nfc": nfc, "battery-saver": batterySaver, "dark-theme": darkTheme,
    "night-light": nightLight, "stay-awake": stayAwake, "mic": mic, "screenshot": screenshot,
    "screen-record": screenRecord, "fingerprint": fingerprint, "keyboard": keyboard,
    "clipboard": clipboard, "dictation": dictation
  })

  // ---------------------------------------------------------------- layout

  property bool expanded: false
  property bool editing: false
  property var layout: TilesModel.defaults()
  // Collapsed: the first tiles, in whole rows (four upright at two
  // columns, six on the side at three).
  readonly property var quickTiles: TilesModel.quickRow(layout, Math.ceil(TilesModel.QUICK_COUNT / tileColumns) * tileColumns)
  readonly property var tilePages: TilesModel.pages(layout)
  readonly property var spareTiles: TilesModel.available(layout)

  // HOME, not XDG_CONFIG_HOME: the same place omamobile-set-pin keeps its
  // record, and Omarchy's shell finds shell.json the same way.
  readonly property string configDir: Quickshell.env("HOME") + "/.config/omamobile"
  property string pendingLayoutText: ""

  FileView {
    id: layoutFile
    path: root.configDir + "/quicksettings.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.layout = TilesModel.parseConfig(text())
    onLoadFailed: function(error) { root.layout = TilesModel.defaults() }
    onFileChanged: reload()
  }

  // The directory may not exist yet on a fresh account; write once it does.
  Process {
    id: configDirMake
    command: ["mkdir", "-p", root.configDir]
    onExited: {
      if (root.pendingLayoutText === "") return
      layoutFile.setText(root.pendingLayoutText)
      root.pendingLayoutText = ""
    }
  }

  function saveLayout(next) {
    var clean = TilesModel.sanitize(next)
    if (!TilesModel.sameLayout(clean, layout)) layout = clean
    pendingLayoutText = TilesModel.serialize(clean)
    if (!configDirMake.running) configDirMake.running = true
  }

  function startEditing() {
    editModel.clear()
    for (var i = 0; i < layout.length; i++) editModel.append({ tileId: layout[i] })
    expanded = true
    editing = true
  }

  function editModelLayout() {
    var out = []
    for (var i = 0; i < editModel.count; i++) out.push(editModel.get(i).tileId)
    return out
  }

  function finishEditing() {
    saveLayout(editModelLayout())
    editing = false
  }

  function removeTileAt(index) {
    if (index < 0 || index >= editModel.count) return
    editModel.remove(index, 1)
    saveLayout(editModelLayout())
  }

  function addTile(id) {
    if (TilesModel.indexOf(editModelLayout(), id) >= 0) return
    editModel.append({ tileId: id })
    saveLayout(editModelLayout())
  }

  // Reset throws away the user's arrangement and sits beside Done, so it
  // takes two taps: the first turns it into "Reset?" for a few seconds.
  property bool confirmReset: false
  onEditingChanged: confirmReset = false

  Timer {
    id: disarmReset
    interval: 4000
    onTriggered: root.confirmReset = false
  }

  function requestReset() {
    if (!confirmReset) {
      confirmReset = true
      disarmReset.restart()
      return
    }
    confirmReset = false
    resetLayout()
  }

  function resetLayout() {
    var list = TilesModel.defaults()
    editModel.clear()
    for (var i = 0; i < list.length; i++) editModel.append({ tileId: list[i] })
    saveLayout(list)
  }

  ListModel { id: editModel }

  // Probe once at load so the first open doesn't show every probed tile
  // dimmed while the pass runs.
  Component.onCompleted: refreshProbe()

  // ---------------------------------------------------------------- probed tiles

  // Tiles with no Quickshell service read their state through one shell
  // pass (tile-state.sh) and switch through tile-action.sh, both beside this
  // file. A tap shows its result at once; the next probe confirms it.
  property var probed: ({})
  property var optimistic: ({})

  function scriptPath(name) {
    return decodeURIComponent(String(Qt.resolvedUrl(name)).replace(/^file:\/\//, ""))
  }

  function refreshProbe() {
    if (!probeProc.running) probeProc.running = true
  }

  function probedOn(id, key) {
    if (optimistic[id] !== undefined) return optimistic[id]
    return probed[key] === "on"
  }

  function probedHas(key) {
    return probed[key] !== undefined && probed[key] !== "none" && probed[key] !== ""
  }

  function setOptimistic(id, on) {
    var next = {}
    for (var key in optimistic) next[key] = optimistic[key]
    if (on === undefined) delete next[id]
    else next[id] = on
    optimistic = next
  }

  // One action at a time, in order; the probe runs after the last.
  property var actionQueue: []

  function runTileAction(id, on) {
    setOptimistic(id, on)
    actionQueue = actionQueue.concat([[id, on ? "on" : "off"]])
    if (!actionProc.running) nextTileAction()
  }

  function nextTileAction() {
    if (actionQueue.length === 0) { refreshProbe(); return }
    var job = actionQueue[0]
    actionQueue = actionQueue.slice(1)
    actionProc.command = ["sh", scriptPath("tile-action.sh"), job[0], job[1]]
    actionProc.running = true
  }

  Process {
    id: probeProc
    command: ["sh", root.scriptPath("tile-state.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.probed = TilesModel.parseProbe(text)
        if (root.actionQueue.length === 0 && !actionProc.running) root.optimistic = ({})
      }
    }
  }

  Process {
    id: actionProc
    onExited: root.nextTileAction()
  }

  // Detached actions (a recorder that outlives its launcher) check back later.
  Timer {
    id: probeLater
    interval: 1500
    onTriggered: { root.optimistic = ({}); root.refreshProbe() }
  }

  // Airplane mode: Wi-Fi, Bluetooth and WWAN rfkill switches together.
  // The modem's own radio (omamobile-sit radio) is not touched: turning it
  // back on needs a reboot today.
  QtObject {
    id: airplane
    readonly property bool available: root.probedHas("airplane")
    readonly property bool enabled: available && root.probedOn("airplane", "airplane")
    readonly property string icon: enabled ? "󰀝" : "󰀞"
    readonly property string status: !available ? "No radios" : enabled ? "On" : "Off"
    function toggle() { if (available) root.runTileAction("airplane", !enabled) }
  }

  // A Wi-Fi hotspot through NetworkManager. Long-press opens the Wi-Fi panel.
  QtObject {
    id: hotspot
    readonly property bool available: wifi.backendAvailable && !!wifi.device && root.probedHas("hotspot")
    readonly property bool enabled: available && root.probedOn("hotspot", "hotspot")
    readonly property string icon: "󰀂"
    readonly property string status: !available ? "No Wi-Fi radio" : enabled ? "On" : "Off"
    readonly property bool longPress: true
    function toggle() { if (available) root.runTileAction("hotspot", !enabled) }
    function openDetails() { root.openWifiPanel() }
  }

  // Battery saver: power-profiles-daemon's power-saver profile.
  QtObject {
    id: batterySaver
    readonly property bool available: root.probedHas("powerprofile")
    readonly property bool enabled: available && (root.optimistic["battery-saver"] !== undefined
      ? root.optimistic["battery-saver"] : root.probed.powerprofile === "power-saver")
    readonly property string icon: enabled ? "󰂃" : "󰁹"
    readonly property string status: !available ? "No power profiles"
      : root.optimistic["battery-saver"] !== undefined ? (enabled ? "On" : "Off")
      : TilesModel.powerStatus(root.probed.powerprofile)
    function toggle() { if (available) root.runTileAction("battery-saver", !enabled) }
  }

  // Dark theme: swaps between the last light and last dark Omarchy theme.
  // Long-press opens Omarchy's theme picker.
  QtObject {
    id: darkTheme
    readonly property bool available: root.probedHas("theme_mode")
    readonly property bool enabled: available && (root.optimistic["dark-theme"] !== undefined
      ? root.optimistic["dark-theme"] : root.probed.theme_mode !== "light")
    readonly property string icon: enabled ? "󰖔" : "󰖙"
    readonly property string status: !available ? "No theme" : TilesModel.themeName(root.probed.theme_name) || (enabled ? "On" : "Off")
    readonly property bool longPress: true
    function toggle() { if (available) root.runTileAction("dark-theme", !enabled) }
    function openDetails() {
      root.dismiss()
      Quickshell.execDetached(["omarchy-theme-switcher"])
    }
  }

  // Night light through Omarchy's hyprsunset toggle.
  QtObject {
    id: nightLight
    readonly property bool available: root.probedHas("nightlight")
    readonly property bool enabled: available && root.probedOn("night-light", "nightlight")
    readonly property string icon: "󰌵"
    readonly property string status: !available ? "No hyprsunset" : enabled ? "On" : "Off"
    function toggle() { if (available) root.runTileAction("night-light", !enabled) }
  }

  // Stay awake: Omarchy's idle indicator, which keeps the screen on and
  // the phone out of sleep (omamobile-sleepd refuses while it is on).
  QtObject {
    id: stayAwake
    readonly property bool available: root.probedHas("stayawake")
    readonly property bool enabled: available && root.probedOn("stay-awake", "stayawake")
    readonly property string icon: "󰅶"
    readonly property string status: enabled ? "Screen stays on" : "Off"
    function toggle() { if (available) root.runTileAction("stay-awake", !enabled) }
  }

  // The default microphone's mute, through PipeWire.
  QtObject {
    id: mic
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool available: !!source && !!source.audio
    readonly property bool enabled: available && !source.audio.muted
    readonly property string icon: enabled ? "󰍬" : "󰍭"
    readonly property string status: !available ? "No microphone" : enabled ? "On" : "Muted"
    function toggle() { if (available) source.audio.muted = !source.audio.muted }
  }

  PwObjectTracker { objects: mic.source ? [mic.source] : [] }

  // Screenshot: the sheet slides away first so it isn't in the picture.
  QtObject {
    id: screenshot
    readonly property bool available: true
    readonly property bool enabled: false
    readonly property string icon: "󰹑"
    readonly property string status: "Capture"
    function toggle() {
      root.dismiss()
      screenshotLater.restart()
    }
  }

  Timer {
    id: screenshotLater
    interval: 450
    onTriggered: Quickshell.execDetached(["omarchy-capture-screenshot", "fullscreen"])
  }

  // Screen recording through omamobile-screenrecord (wf-recorder; Omarchy's
  // gpu-screen-recorder can't drive the phone's GPU). A tap while off opens
  // the Screen record page to choose the sound; a tap while recording stops.
  QtObject {
    id: screenRecord
    readonly property bool available: root.probedHas("record")
    readonly property bool enabled: available && root.probedOn("screen-record", "record")
    readonly property string icon: enabled ? "󰻃" : "󰕧"
    readonly property string status: !available ? "No recorder" : enabled ? "Recording" : "Off"
    function toggle() {
      if (!available) return
      if (!enabled) { root.openPage("record"); root.dismiss(); return }
      root.setOptimistic("screen-record", false)
      Quickshell.execDetached(["sh", root.scriptPath("tile-action.sh"), "screen-record", "off"])
      probeLater.restart()
    }
    function start(audio) {
      recordPanelItem.close()
      root.setOptimistic("screen-record", true)
      root.dismiss()
      Quickshell.execDetached(["sh", root.scriptPath("tile-action.sh"), "screen-record", "on", audio])
      probeLater.restart()
    }
  }

  // Clipboard history: Omarchy's own clipboard overlay (omarchy.clipboard),
  // which the desktop opens with Super+Ctrl+V. The sheet goes away first so
  // a pick pastes into the app underneath. Summon, not the binding's
  // toggle: from here it is never already open.
  QtObject {
    id: clipboard
    readonly property bool available: true
    readonly property bool enabled: false
    readonly property string icon: "󰅌"
    readonly property string status: "History"
    function toggle() {
      root.dismiss()
      Quickshell.execDetached(["omarchy-shell", "shell", "summon", "omarchy.clipboard", "{}"])
    }
  }

  // Dictation through voxtype (an optional Omarchy install; Super+Ctrl+X on
  // the desktop). A tap starts recording and puts the sheet away, so what
  // voxtype types lands in the app underneath; a tap while listening stops
  // it and voxtype transcribes. Dimmed with the reason when voxtype isn't
  // installed or its user service isn't running.
  QtObject {
    id: dictation
    readonly property string probe: root.probed.dictation || "none"
    readonly property bool available: probe === "on" || probe === "off" || probe === "busy"
    readonly property bool busy: root.optimistic["dictation"] === undefined && probe === "busy"
    readonly property bool enabled: available && (root.optimistic["dictation"] !== undefined
      ? root.optimistic["dictation"] : probe !== "off")
    readonly property string icon: enabled ? "󰍬" : "󰍭"
    readonly property string status: root.optimistic["dictation"] !== undefined
      ? (enabled ? "Listening" : "Off") : TilesModel.dictationStatus(probe)
    function toggle() {
      if (!available || busy) return
      var start = !enabled
      root.runTileAction("dictation", start)
      if (start) root.dismiss()
    }
  }

  // ---------------------------------------------------------------- clock

  // The header follows the bar clock's 12/24-hour choice (Omarchy's clock
  // 12-hour formats all carry "AP"), read from shell.json on open.
  property bool twelveHour: false

  Process {
    id: clockFormatRead
    command: ["sh", "-c", "grep -o '\"clockFormat\": *\"[^\"]*\"' \"${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json\" | head -1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var format = String(text || "").replace(/^"clockFormat": *"/, "").replace(/"\s*$/, "")
        root.twelveHour = /AP/i.test(format)
      }
    }
  }


  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  readonly property var battery: UPower.displayDevice
  readonly property bool hasBattery: !!battery && battery.isPresent === true

  // ---------------------------------------------------------------- Wi-Fi

  QtObject {
    id: wifi

    readonly property bool backendAvailable: Networking.backend === NetworkBackendType.NetworkManager
    readonly property var devices: Networking.devices ? Networking.devices.values : []
    readonly property var device: {
      for (var i = 0; i < devices.length; i++)
        if (devices[i] && devices[i].type === DeviceType.Wifi) return devices[i]
      return null
    }
    readonly property var network: {
      var networks = device && device.networks ? device.networks.values : []
      for (var i = 0; i < networks.length; i++)
        if (networks[i] && networks[i].connected) return networks[i]
      return null
    }
    readonly property bool available: backendAvailable && !!device && Networking.wifiHardwareEnabled !== false
    readonly property bool enabled: available && Networking.wifiEnabled
    readonly property string icon: enabled ? "󰤨" : "󰤭"
    readonly property bool details: true
    function openDetails() { root.openWifiPanel() }
    readonly property string status: {
      if (!backendAvailable) return "NetworkManager not running"
      if (!device) return "No Wi-Fi radio"
      if (!Networking.wifiEnabled) return "Off"
      return network ? network.name : "Not connected"
    }

    function toggle() {
      if (available) Networking.wifiEnabled = !Networking.wifiEnabled
    }
  }

  // The picker behind the tile's chevron or a long-press. It is its own
  // window, so the sheet goes away and the picker stays up on its own; its
  // back glyph brings the sheet back.
  function openWifiPanel() {
    openPage("wifi")
    root.dismiss()
  }

  function openBluetoothPanel() {
    openPage("bluetooth")
    root.dismiss()
  }

  // One page at a time.
  function openPage(page) {
    if (page !== "wifi") wifiPicker.close()
    if (page !== "bluetooth") bluetoothPanelItem.close()
    if (page !== "record") recordPanelItem.close()
    if (page === "wifi") wifiPicker.open()
    else if (page === "bluetooth") bluetoothPanelItem.open()
    else if (page === "record") recordPanelItem.open()
  }

  RecordPanel {
    id: recordPanelItem
    onBackRequested: root.backToSheet(recordPanelItem)
    onStartRequested: function(audio) { screenRecord.start(audio) }
  }

  // A page's back glyph: close it and bring the sheet back.
  function backToSheet(page) {
    page.close()
    var summoned = root.shell && typeof root.shell.summon === "function" && root.shell.summon(root.pluginId, "{}")
    if (!summoned) root.open("{}")
  }

  WifiPanel {
    id: wifiPicker
    device: wifi.device
    onBackRequested: root.backToSheet(wifiPicker)
  }

  // ---------------------------------------------------------------- Bluetooth

  QtObject {
    id: bluetooth

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: !!adapter
    readonly property bool enabled: available && adapter.enabled
    property bool pending: false
    readonly property bool busy: pending
    readonly property string icon: enabled ? (connected ? "󰂱" : "󰂯") : "󰂲"
    readonly property bool details: true
    function openDetails() { root.openBluetoothPanel() }
    readonly property var connected: {
      var devices = Bluetooth.devices ? Bluetooth.devices.values : []
      for (var i = 0; i < devices.length; i++)
        if (devices[i] && devices[i].connected) return devices[i]
      return null
    }
    readonly property string status: {
      if (!available) return "No adapter"
      if (pending) return enabled ? "Turning off…" : "Turning on…"
      if (!enabled) return "Off"
      return connected ? (connected.name || "Connected") : "On"
    }

    onEnabledChanged: pending = false

    // Same path as Omarchy's Bluetooth panel: the rfkill block persists across
    // reboots, BlueZ's Powered does not. Ask for a direction, not a toggle, so
    // a second tap while BlueZ catches up cannot undo the first.
    function toggle() {
      if (!available || pending) return
      pending = true
      bluetoothPendingTimeout.restart()
      Quickshell.execDetached(["omarchy-bluetooth-power", enabled ? "off" : "on"])
    }
  }

  // The panel behind the Bluetooth tile's chevron or a long-press; its own
  // window, like the Wi-Fi picker.
  BluetoothPanel {
    id: bluetoothPanelItem
    adapter: bluetooth.adapter
    powerPending: bluetooth.pending
    onBackRequested: root.backToSheet(bluetoothPanelItem)
    onPowerToggleRequested: bluetooth.toggle()
  }

  Timer {
    id: bluetoothPendingTimeout
    interval: 6000
    onTriggered: bluetooth.pending = false
  }

  // ---------------------------------------------------------------- do not disturb

  // A panel plugin gets no handle on omarchy.notifications (the host only
  // proxies it to full bars), so read and set DND through the notification
  // service's own IPC target on this shell instance. Quickshell.shellDir and
  // the inherited WAYLAND_DISPLAY pin the call to this shell, never the desktop's.
  QtObject {
    id: dnd

    property bool enabled: false
    readonly property bool available: true
    readonly property string icon: enabled ? "󰂛" : "󰂚"
    readonly property string status: enabled ? "On" : "Off"

    function toggle() {
      enabled = !enabled
      dndProc.command = ["qs", "ipc", "-p", Quickshell.shellDir, "call", "notifications", "setDnd", enabled ? "on" : "off"]
      dndProc.running = true
    }
  }

  function refreshDnd() {
    if (dndProc.running) return
    dndProc.command = ["qs", "ipc", "-p", Quickshell.shellDir, "call", "notifications", "dndState"]
    dndProc.running = true
  }

  Process {
    id: dndProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = String(text || "").trim()
        if (value === "on" || value === "off") dnd.enabled = value === "on"
      }
    }
  }

  // ---------------------------------------------------------------- notifications

  // Omarchy's notification service keeps its history as files, one per
  // notification (NotificationsModel.js has the format); its IPC can replay
  // them as toasts but returns none of them, so the shade reads the files:
  // the toasts on screen in the directory itself, the rest in history/.
  // Clear all goes through the service's own IPC, on this shell instance like
  // the DND tile: dismissAll moves the toasts on screen into history, then
  // clear empties history (both run in order on the service's file queue).
  readonly property string notificationsDir: Quickshell.env("HOME") + "/.local/state/omarchy/notifications"
  // Where the bar's unread count starts from: the newest notification the
  // shade has shown (omamobile.bar reads it at start and hears it by IPC).
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omamobile"
  property var notifications: []
  property double nowMs: Date.now()
  property double seenStamp: 0
  property double seenWritten: 0

  function refreshNotifications() {
    nowMs = Date.now()
    if (!notificationsRead.running) notificationsRead.running = true
  }

  // Swiping a row away forgets that one notification through the service's
  // forget call (omamobile-omarchy patch 0019): a toast still on screen
  // closes without moving into history, and the history entry is deleted,
  // on the service's file queue. Deleting the file from here could race an
  // archive the service still has queued and come back. The row leaves the
  // list at once; its key stays in hiddenNotifications until a read no
  // longer finds the file (NotificationsModel.shown). The bar's unread count
  // follows on its own: it counts the history files newer than the mark,
  // and a forget only takes one away.
  property var hiddenNotifications: ({})
  property var forgetQueue: []

  function forgetNotification(entry) {
    if (!entry || !entry.key || !entry.file) return false
    var marks = Object.assign({}, hiddenNotifications)
    marks[entry.key] = Date.now()
    hiddenNotifications = marks
    forgetQueue = forgetQueue.concat([entry.file])
    // Later, not now: the row asking is a delegate of this list.
    Qt.callLater(function() {
      root.notifications = NotificationsModel.without(root.notifications, entry.key)
      root.runForget()
    })
    return true
  }

  function runForget() {
    if (forgetProc.running || forgetQueue.length === 0) return
    forgetProc.command = ["sh", "-c",
      "dir=$1; shift; for name; do qs ipc -p \"$dir\" call notifications forget \"$name\"; done; exit 0",
      "sh", Quickshell.shellDir].concat(forgetQueue)
    forgetQueue = []
    forgetProc.running = true
  }

  Process {
    id: forgetProc
    onExited: {
      root.runForget()
      notificationsLater.restart()
    }
  }

  Process {
    id: notificationsRead
    command: ["sh", "-c", "for f in \"$1\"/*.json \"$1\"/history/*.json; do [ -f \"$f\" ] && awk 1 \"$f\"; done; exit 0",
              "sh", root.notificationsDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var view = NotificationsModel.shown(text, root.hiddenNotifications, Date.now())
        root.hiddenNotifications = view.hidden
        // Only a change replaces the rows: a new list rebuilds every row, and
        // one being swiped would be dropped from under the finger.
        if (JSON.stringify(view.entries) !== JSON.stringify(root.notifications))
          root.notifications = view.entries
        var newest = NotificationsModel.newest(root.notifications)
        if (root.opened && newest > root.seenStamp) {
          root.seenStamp = newest
          root.writeSeen()
        }
      }
    }
  }

  // Keep the shade current while it is on screen (and its "5 min" true).
  Timer {
    interval: 3000
    repeat: true
    running: root.opened
    onTriggered: root.refreshNotifications()
  }

  function writeSeen() {
    if (seenWrite.running || seenWritten === seenStamp) return
    seenWritten = seenStamp
    seenWrite.command = ["sh", "-c",
      "mkdir -p \"$1\" && printf '%s\\n' \"$2\" >\"$1/notifications-seen.new\" && mv -f \"$1/notifications-seen.new\" \"$1/notifications-seen\"; "
      + "qs ipc -p \"$3\" call omamobile.bar notificationsSeen \"$2\" >/dev/null 2>&1; exit 0",
      "sh", root.stateDir, String(seenStamp), Quickshell.shellDir]
    seenWrite.running = true
  }

  Process {
    id: seenWrite
    onExited: root.writeSeen()
  }

  // Clear all takes two taps, like the other destructive actions here: the
  // first turns it into "Clear all?" for a few seconds.
  property bool confirmClear: false

  Timer {
    id: disarmClear
    interval: 4000
    onTriggered: root.confirmClear = false
  }

  function requestClearNotifications() {
    if (!confirmClear) {
      confirmClear = true
      disarmClear.restart()
      return
    }
    confirmClear = false
    clearAllNotifications()
  }

  function clearAllNotifications() {
    notifications = []
    if (clearProc.running) return
    clearProc.command = ["sh", "-c",
      "qs ipc -p \"$1\" call notifications dismissAll; qs ipc -p \"$1\" call notifications clear",
      "sh", Quickshell.shellDir]
    clearProc.running = true
  }

  Process {
    id: clearProc
    // The service's file queue runs after the IPC answers; read once it has.
    onExited: notificationsLater.restart()
  }

  Timer {
    id: notificationsLater
    interval: 600
    onTriggered: root.refreshNotifications()
  }

  // A row's tap: the toast's own action, or Omarchy's focus helper for the
  // app that sent it, with the sheet out of the way.
  function openNotification(entry) {
    var argv = NotificationsModel.tapArgv(entry)
    if (!argv) return
    root.dismiss()
    Quickshell.execDetached(argv)
  }

  // ---------------------------------------------------------------- stubs

  // Mobile data over omamobile-modem-sit: the tile is the cellular bearer
  // (omamobile-sit data on|off, which starts or stops
  // omamobile-sit-data.service through polkit). "No modem" until
  // omamobile-sitd publishes its state.
  QtObject {
    id: mobileData
    readonly property bool available: root.probedHas("data")
    readonly property bool enabled: available && root.probedOn("mobile-data", "data")
    readonly property string icon: "󰞃"
    readonly property string status: !available ? "No modem"
      : !enabled ? "Off" : (root.probed.data_status || "On")
    function toggle() { if (available) root.runTileAction("mobile-data", !enabled) }
  }

  // Rotation lock over omamobile-autorotate (omamobile-sensors): it rotates
  // the screen while the sensor proxy has an accelerometer, unless
  // ~/.local/state/omamobile/rotation-lock exists. Turning the lock off also
  // enables the service, so auto-rotate stays on after a reboot.
  QtObject {
    id: rotationLock

    property bool available: false
    property bool enabled: false
    readonly property string icon: "󰑵"
    readonly property string status: !available ? "No sensor" : enabled ? "Locked" : "Auto-rotate"

    function refresh() {
      if (!rotationRead.running) rotationRead.running = true
    }

    function toggle() {
      if (!available || rotationWrite.running) return
      rotationWrite.command = enabled
        ? ["sh", "-c", "rm -f \"$HOME/.local/state/omamobile/rotation-lock\"; systemctl --user enable --now omamobile-autorotate.service"]
        : ["sh", "-c", "mkdir -p \"$HOME/.local/state/omamobile\" && touch \"$HOME/.local/state/omamobile/rotation-lock\""]
      rotationWrite.running = true
    }
  }

  Process {
    id: rotationRead
    // none: no accelerometer; locked: the lock file, or the service is off
    command: ["sh", "-c",
      "busctl get-property net.hadess.SensorProxy /net/hadess/SensorProxy net.hadess.SensorProxy HasAccelerometer 2>/dev/null | grep -q true || { echo none; exit 0; }; "
      + "[ -e \"$HOME/.local/state/omamobile/rotation-lock\" ] && { echo locked; exit 0; }; "
      + "systemctl --user is-active --quiet omamobile-autorotate.service && echo auto || echo locked"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = String(text || "").trim()
        rotationLock.available = value === "auto" || value === "locked"
        rotationLock.enabled = value === "locked"
      }
    }
  }

  Process {
    id: rotationWrite
    onExited: rotationLock.refresh()
  }

  // Location over omamobile-gnss (package omamobile-gnss): on lets apps ask
  // GeoClue for positions and runs the receiver only while one does; off
  // stops it and lets nothing start it. As the user, on/off go through
  // polkit. "No GNSS" when the command or the vendor files are missing.
  QtObject {
    id: location

    property bool available: false
    property bool enabled: false
    property bool running: false
    readonly property string icon: enabled ? "󰍎" : "󰍐"
    readonly property string status: !available ? "No GNSS" : !enabled ? "Off" : running ? "In use" : "On"

    function refresh() {
      if (!locationRead.running) locationRead.running = true
    }

    function toggle() {
      if (!available || locationWrite.running) return
      locationWrite.command = ["omamobile-gnss", enabled ? "off" : "on"]
      enabled = !enabled
      locationWrite.running = true
    }
  }

  Process {
    id: locationRead
    command: ["omamobile-gnss", "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var info = null
        try { info = JSON.parse(String(text || "").trim()) } catch (error) {}
        location.available = !!info && info.installed === true
        location.enabled = !!info && info.location === "on"
        location.running = !!info && info.running === "yes"
      }
    }
    onExited: function(exitCode) { if (exitCode !== 0) location.available = false }
  }

  Process {
    id: locationWrite
    onExited: location.refresh()
  }

  // NFC through its rfkill switch, which the kernel's NFC core registers for
  // each controller (type "nfc"); the session may write /dev/rfkill. "No NFC"
  // until a controller has probed.
  QtObject {
    id: nfc

    property bool available: false
    property bool enabled: false
    readonly property string icon: "󰎖"
    readonly property string status: !available ? "No NFC" : enabled ? "On" : "Off"

    function refresh() {
      if (!nfcRead.running) nfcRead.running = true
    }

    function toggle() {
      if (!available || nfcWrite.running) return
      nfcWrite.command = ["rfkill", enabled ? "block" : "unblock", "nfc"]
      enabled = !enabled
      nfcWrite.running = true
    }
  }

  Process {
    id: nfcRead
    command: ["rfkill", "-rn", "-o", "TYPE,SOFT"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n").filter(function(line) { return /^nfc\s/.test(line) })
        nfc.available = lines.length > 0
        nfc.enabled = lines.length > 0 && lines.every(function(line) { return /\sunblocked$/.test(line) })
      }
    }
    onExited: function(exitCode) { if (exitCode !== 0) nfc.available = false }
  }

  Process {
    id: nfcWrite
    onExited: nfc.refresh()
  }

  // Fingerprint unlock (omamobile-fingerprint + fprintd): the tile opens the
  // enrollment screen of omamobile.fingerprint; its status counts this
  // user's fingerprints through fprintd (omamobile-fp-enroll list).
  QtObject {
    id: fingerprint

    property bool available: false
    property int count: 0
    readonly property bool enabled: available && count > 0
    readonly property string icon: "󰈷"
    readonly property string status: !available ? "No sensor"
      : count === 0 ? "Set up" : count === 1 ? "1 added" : count + " added"

    function refresh() {
      if (!fingerprintRead.running) fingerprintRead.running = true
    }

    function toggle() {
      if (!available) return
      root.dismiss()
      // Through the CLI, like the launcher's switcher: a plugin may only
      // summon panels it owns.
      Quickshell.execDetached(["omarchy-shell", "shell", "summon", "omamobile.fingerprint", "{\"page\":\"enroll\"}"])
    }
  }

  Process {
    id: fingerprintRead
    command: ["omamobile-fp-enroll", "list"]
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var ev = JSON.parse(line)
          if (ev && ev.event === "fingers") {
            fingerprint.available = true
            fingerprint.count = Array.isArray(ev.fingers) ? ev.fingers.length : 0
          }
        } catch (error) {}
      }
    }
    onExited: function(exitCode) { if (exitCode !== 0) fingerprint.available = false }
  }

  // The on-screen keyboard (squeekboard, sm.puri.OSK0 on the session bus):
  // show it on demand, or fold it. Showing closes the sheet so the keys can
  // be used.
  QtObject {
    id: keyboard

    property bool available: false
    property bool enabled: false
    readonly property string icon: "󰌌"
    readonly property string status: !available ? "No keyboard" : enabled ? "Shown" : "Hidden"

    function refresh() {
      if (!keyboardRead.running) keyboardRead.running = true
    }

    function toggle() {
      if (!available) return
      var show = !enabled
      Quickshell.execDetached(["busctl", "--user", "call", "sm.puri.OSK0", "/sm/puri/OSK0",
                               "sm.puri.OSK0", "SetVisible", "b", show ? "true" : "false"])
      enabled = show
      if (show) root.dismiss()
    }
  }

  Process {
    id: keyboardRead
    command: ["busctl", "--user", "get-property", "sm.puri.OSK0", "/sm/puri/OSK0", "sm.puri.OSK0", "Visible"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        keyboard.available = t.indexOf("b ") === 0
        keyboard.enabled = t === "b true"
      }
    }
    onExited: function(exitCode) { if (exitCode !== 0) keyboard.available = false }
  }

  // The rear flash LED in torch mode (leds-lm3644, white:torch). "100%" is
  // the device tree's torch cap, not the chip's maximum. brightnessctl goes
  // through logind's SetBrightness when it can't write sysfs itself, which
  // the active session may do for leds devices.
  QtObject {
    id: torch

    property bool available: false
    property bool enabled: false
    readonly property string icon: "󰉄"
    readonly property string status: !available ? "No flash LED" : enabled ? "On" : "Off"

    function refresh() {
      if (!torchRead.running) torchRead.running = true
    }

    function toggle() {
      if (!available || torchWrite.running) return
      torchWrite.command = ["brightnessctl", "--device=white:torch", "--quiet", "set", enabled ? "0" : "100%"]
      torchWrite.running = true
    }
  }

  Process {
    id: torchRead
    command: ["brightnessctl", "--device=white:torch", "--machine-readable", "info"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // device,class,current,percent%,max
        var parts = String(text || "").trim().split(",")
        var current = parts.length >= 3 ? parseInt(parts[2], 10) : NaN
        torch.available = isFinite(current)
        torch.enabled = isFinite(current) && current > 0
      }
    }
    onExited: function(exitCode) { if (exitCode !== 0) torch.available = false }
  }

  Process {
    id: torchWrite
    onExited: torch.refresh()
  }

  // ---------------------------------------------------------------- brightness

  // The panel backlight through brightnessctl's backlight class, the device
  // a phone actually has. No backlight (a desktop with only external
  // monitors) leaves the row dimmed.
  QtObject {
    id: brightness

    property bool available: false
    property int percent: 0
    property int pendingPercent: -1

    function refresh() {
      if (!brightnessRead.running) brightnessRead.running = true
    }

    function set(fraction) {
      percent = Math.max(1, Math.round(fraction * 100))
      pendingPercent = percent
      if (!brightnessWrite.running) flush()
    }

    function flush() {
      if (pendingPercent < 0) return
      brightnessWrite.command = ["brightnessctl", "--class=backlight", "--quiet", "set", pendingPercent + "%"]
      pendingPercent = -1
      brightnessWrite.running = true
    }
  }

  Process {
    id: brightnessRead
    command: ["brightnessctl", "--class=backlight", "--machine-readable", "info"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // device,class,current,percent%,max
        var parts = String(text || "").trim().split(",")
        var value = parts.length >= 4 ? parseInt(parts[3], 10) : NaN
        brightness.available = isFinite(value)
        if (isFinite(value)) brightness.percent = value
      }
    }
    onExited: function(exitCode) { if (exitCode !== 0) brightness.available = false }
  }

  Process {
    id: brightnessWrite
    onExited: brightness.flush()
  }

  // ---------------------------------------------------------------- volume

  QtObject {
    id: audio

    // PipeWire names no default sink until something uses one (a volume key
    // through wpctl did), which left the row "No audio output" after boot.
    // Fall back to the first audio sink until it does.
    readonly property var sink: Pipewire.defaultAudioSink || firstSink()

    function firstSink() {
      var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
      for (var i = 0; i < nodes.length; i++) {
        var node = nodes[i]
        if (node && node.isSink && !node.isStream && node.audio) return node
      }
      return null
    }
    readonly property bool available: !!sink && !!sink.audio
    readonly property real volume: available ? Math.min(1, sink.audio.volume) : 0
    readonly property bool muted: available ? sink.audio.muted : false
    readonly property string icon: {
      if (!available) return "󰖁"
      if (muted) return "󰖁"
      if (volume >= 0.67) return "󰕾"
      if (volume >= 0.34) return "󰖀"
      return "󰕿"
    }

    function setVolume(value) {
      if (!available) return
      sink.audio.volume = Math.max(0, Math.min(1, value))
      if (sink.audio.muted && value > 0) sink.audio.muted = false
    }

    function toggleMute() {
      if (available) sink.audio.muted = !sink.audio.muted
    }
  }

  PwObjectTracker { objects: audio.sink ? [audio.sink] : [] }

  // ---------------------------------------------------------------- surface

  // 0 = tucked above the screen, 1 = fully down. Driving the window's
  // visibility from this lets the sheet finish sliding up before it unmaps.
  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

  readonly property color foreground: Commons.Color.popups.text
  readonly property int pad: Style.spacing.panelPadding
  readonly property int gap: Style.spacing.lg
  readonly property int tileHeight: Math.max(64, Style.space(68))
  readonly property int editTileHeight: Math.max(56, Style.space(60))
  readonly property int editColumns: 3
  // Wider than tall: the phone on its side.
  readonly property bool wide: window.width > window.height
  // Tile columns from the sheet's width: two upright, three on its side.
  readonly property int tileColumns: Math.max(2, Math.min(4, Math.floor(content.width / 180)))
  readonly property int pageRows: {
    var most = 0
    for (var i = 0; i < tilePages.length; i++) most = Math.max(most, tilePages[i].length)
    return Math.max(1, Math.ceil(most / tileColumns))
  }
  // Edit mode scrolls past this, so the sheet stays on screen.
  readonly property real editMaxHeight: Math.max(200, window.height - Style.gapsOut * 2 - root.pad * 4 - Math.max(44, Style.space(48)) - Style.space(40))

  PanelWindow {
    id: window

    visible: root.opened || root.reveal > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omamobile-quicksettings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
      opacity: root.reveal
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: sheet
      objectName: "sheet"

      x: Style.gapsOut
      width: root.wide ? Math.round((parent.width - Style.gapsOut * 2 - Style.spacing.lg) * 0.58) : parent.width - Style.gapsOut * 2
      // No taller than the screen: past that the content scrolls, above
      // the handle.
      readonly property real handleRoom: handleRow.visible ? handleRow.height + root.pad : 0
      height: Math.min(content.implicitHeight + handleRoom + sheet.contentTopInset + sheet.contentBottomInset, window.height - Style.gapsOut * 2)
      y: Style.gapsOut - (height + Style.gapsOut * 2) * (1 - root.reveal) + drag.offset
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      padding: root.pad

      focus: root.opened
      Keys.onEscapePressed: root.editing ? root.finishEditing() : root.dismiss()

      // Swallow taps inside the sheet so they don't reach the scrim, and turn
      // an upward swipe anywhere on it into a dismiss. Tiles take their taps
      // with a passive TapHandler (Tile.qml), so a swipe that starts on a
      // tile lands here too. A DragHandler above the content would steal the
      // edit list's scrolling and the sliders, so this stays underneath.
      MouseArea {
        id: drag
        anchors.fill: parent
        property real startY: 0
        property real offset: 0
        onPressed: function(mouse) { startY = mouse.y; offset = 0 }
        onPositionChanged: function(mouse) {
          offset = Math.min(0, mouse.y - startY)
          if (mouse.y - startY > Style.space(40) && !root.expanded) root.expanded = true
        }
        onReleased: {
          if (offset < -Style.space(60)) root.dismiss()
          offset = 0
        }
        onCanceled: offset = 0
      }

      Flickable {
        id: sheetFlick
        anchors.fill: parent
        anchors.topMargin: sheet.contentTopInset
        anchors.rightMargin: sheet.contentRightInset
        anchors.bottomMargin: sheet.contentBottomInset + sheet.handleRoom
        anchors.leftMargin: sheet.contentLeftInset
        contentWidth: width
        contentHeight: content.implicitHeight
        // Only once the sheet is cut to the screen: a Flickable with nothing
        // to scroll would still take the swipe that closes the sheet.
        interactive: contentHeight > height + 1
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: sheetFlick.width
          spacing: root.pad

          // ---------- Edit mode's header
          Item {
            visible: root.editing
            width: parent.width
            height: visible ? doneButton.height : 0

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Edit tiles"
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.lg

              SheetButton {
                width: Math.max(80, Style.space(88))
                label: root.confirmReset ? "Reset?" : "Reset"
                danger: root.confirmReset
                foreground: root.foreground
                enabled: !TilesModel.sameLayout(root.layout, TilesModel.DEFAULT_LAYOUT)
                onTapped: root.requestReset()
              }

              SheetButton {
                id: doneButton
                width: Math.max(80, Style.space(88))
                label: "Done"
                primary: true
                foreground: root.foreground
                onTapped: root.finishEditing()
              }
            }
          }

          // ---------- Header: time and date, battery on the right
          Item {
            visible: !root.editing
            width: parent.width
            implicitHeight: visible ? Math.max(headerClock.implicitHeight, headerBattery.implicitHeight, settingsButton.height) : 0

            Column {
              id: headerClock
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xxs

              Text {
                textFormat: Text.PlainText
                text: Qt.formatDateTime(clock.date, root.twelveHour ? "h:mm AP" : "HH:mm")
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.displayLarge
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                color: Qt.darker(root.foreground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }

            Text {
              id: headerBattery
              visible: root.hasBattery
              anchors.right: settingsButton.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.hasBattery
                ? (UPower.onBattery ? "󰁹 " : "󰂄 ") + Math.round(root.battery.percentage * 100) + "%"
                : ""
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
            }

            // Omarchy's menu at its root: Setup, Style, Install and the rest
            // (TOUCH-PLAN 1.3). Summon, not toggle: it opens even if the menu
            // was left open under the sheet.
            GlyphButton {
              id: settingsButton
              objectName: "settingsButton"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              glyph: "󰒓"
              foreground: root.foreground
              onTapped: root.openSettings()
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---------- Collapsed: the first row of tiles
          Grid {
            id: quickGrid
            objectName: "quickGrid"
            visible: !root.expanded && !root.editing && root.quickTiles.length > 0
            width: parent.width
            columns: root.tileColumns
            columnSpacing: root.gap
            rowSpacing: root.gap
            readonly property real tileWidth: (width - columnSpacing * (columns - 1)) / columns

            Repeater {
              model: root.quickTiles
              delegate: BoundTile {
                host: root
                tileId: modelData
                width: quickGrid.tileWidth
              }
            }
          }

          // ---------- Expanded: every tile, eight to a page
          ListView {
            id: pager
            objectName: "tilePager"
            visible: root.expanded && !root.editing
            width: parent.width
            height: visible ? root.pageRows * root.tileHeight + (root.pageRows - 1) * root.gap : 0
            orientation: ListView.Horizontal
            snapMode: ListView.SnapOneItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            model: root.tilePages

            delegate: Item {
              width: pager.width
              height: pager.height

              Grid {
                id: pageGrid
                width: parent.width
                columns: root.tileColumns
                columnSpacing: root.gap
                rowSpacing: root.gap
                readonly property real tileWidth: (width - columnSpacing * (columns - 1)) / columns

                Repeater {
                  model: modelData
                  delegate: BoundTile {
                    host: root
                    tileId: modelData
                    width: pageGrid.tileWidth
                  }
                }
              }

              Text {
                visible: modelData.length === 0
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "No tiles. Tap 󰏫 to add some."
                color: Qt.darker(root.foreground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }
          }

          // ---------- Page dots and the pencil
          Item {
            visible: root.expanded && !root.editing
            width: parent.width
            height: visible ? editButton.height : 0

            Row {
              anchors.centerIn: parent
              spacing: Style.spacing.md
              visible: root.tilePages.length > 1

              Repeater {
                model: root.tilePages.length
                delegate: Rectangle {
                  width: Math.max(6, Style.space(7))
                  height: width
                  radius: width / 2
                  color: index === pager.currentIndex ? Commons.Color.accent : Util.alpha(root.foreground, 0.3)
                }
              }
            }

            GlyphButton {
              id: editButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              glyph: "󰏫"
              foreground: root.foreground
              onTapped: root.startEditing()
            }
          }

          // ---------- Edit mode: the shown tiles, then the ones to add
          Flickable {
            id: editFlick
            visible: root.editing
            width: parent.width
            height: visible ? Math.min(contentHeight, root.editMaxHeight) : 0
            contentWidth: width
            contentHeight: editColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
              id: editColumn
              width: editFlick.width
              spacing: Style.spacing.lg

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "Tap a tile to remove it. Hold and drag to move it."
                color: Qt.darker(root.foreground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Readable.px(Style.font.caption)
                wrapMode: Text.WordWrap
              }

              // The grids reach half a gap past the sheet's padding on each
              // side, so the tiles' outer edges line up with the separators.
              Item {
                x: -root.gap / 2
                width: parent.width + root.gap
                height: editGrid.height

                GridView {
                  id: editGrid
                  width: parent.width
                  height: Math.max(1, Math.ceil(count / root.editColumns)) * cellHeight
                  interactive: false
                  cellWidth: width / root.editColumns
                  cellHeight: root.editTileHeight + root.gap
                  model: editModel
                  property int dragIndex: -1

                  move: Transition { NumberAnimation { properties: "x,y"; duration: 140; easing.type: Easing.OutCubic } }
                  moveDisplaced: Transition { NumberAnimation { properties: "x,y"; duration: 140; easing.type: Easing.OutCubic } }
                  removeDisplaced: Transition { NumberAnimation { properties: "x,y"; duration: 140 } }

                  delegate: Item {
                    width: editGrid.cellWidth
                    height: editGrid.cellHeight

                    EditTile {
                      x: root.gap / 2
                      width: parent.width - root.gap
                      height: root.editTileHeight
                      icon: root.backends[model.tileId] ? root.backends[model.tileId].icon : ""
                      label: TilesModel.label(model.tileId)
                      lifted: editGrid.dragIndex === index
                    }
                  }
                }

                Text {
                  visible: editModel.count === 0
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "No tiles on the sheet"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                // One touch handler over the whole grid: a tap removes, a hold
                // lifts the tile and moving the finger walks it through the grid.
                MouseArea {
                  id: editTouch
                  anchors.fill: parent
                  pressAndHoldInterval: 350
                  property bool dragging: false

                  onPressAndHold: function(mouse) {
                    var index = editGrid.indexAt(mouse.x, mouse.y)
                    if (index < 0) return
                    editGrid.dragIndex = index
                    dragging = true
                    editFlick.interactive = false
                  }
                  onPositionChanged: function(mouse) {
                    if (!dragging) return
                    var index = editGrid.indexAt(Math.max(0, Math.min(editGrid.width - 1, mouse.x)),
                                                 Math.max(0, Math.min(editGrid.height - 1, mouse.y)))
                    if (index >= 0 && index !== editGrid.dragIndex) {
                      editModel.move(editGrid.dragIndex, index, 1)
                      editGrid.dragIndex = index
                    }
                  }
                  onReleased: editTouch.drop()
                  onCanceled: editTouch.drop()
                  onClicked: function(mouse) {
                    if (dragging) return
                    root.removeTileAt(editGrid.indexAt(mouse.x, mouse.y))
                  }

                  function drop() {
                    if (dragging) root.saveLayout(root.editModelLayout())
                    dragging = false
                    editGrid.dragIndex = -1
                    editFlick.interactive = true
                  }
                }
              }

              PanelSeparator { foreground: root.foreground }

              Text {
                textFormat: Text.PlainText
                text: "Add tiles"
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              Text {
                visible: root.spareTiles.length === 0
                textFormat: Text.PlainText
                text: "Every tile is on the sheet"
                color: Qt.darker(root.foreground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Readable.px(Style.font.caption)
              }

              Grid {
                id: spareGrid
                x: -root.gap / 2
                width: parent.width + root.gap
                columns: root.editColumns

                Repeater {
                  model: root.spareTiles
                  delegate: Item {
                    width: spareGrid.width / root.editColumns
                    height: root.editTileHeight + root.gap

                    EditTile {
                      x: root.gap / 2
                      width: parent.width - root.gap
                      height: root.editTileHeight
                      icon: root.backends[modelData] ? root.backends[modelData].icon : ""
                      label: TilesModel.label(modelData)
                      adding: true
                      opacity: spareTouch.pressed ? 0.7 : 1
                    }

                    MouseArea {
                      id: spareTouch
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.addTile(modelData)
                    }
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground; visible: !root.editing }

          // ---------- Sliders: brightness always, volume when expanded
          Column {
            visible: !root.editing
            width: parent.width
            spacing: Style.spacing.sm

            SliderRow {
              width: parent.width
              icon: "󰃠"
              value: brightness.percent / 100
              available: brightness.available
              unavailableText: "No backlight"
              onMoved: function(value) { brightness.set(value) }
            }

            SliderRow {
              visible: root.expanded
              width: parent.width
              icon: audio.icon
              value: audio.volume
              available: audio.available
              unavailableText: "No audio output"
              onMoved: function(value) { audio.setVolume(value) }
              onIconClicked: audio.toggleMute()
            }
          }

        }
      }

      // ---------- Handle: a visible cue that the sheet swipes back up
      // Collapsed, a tap on it (or a pull down anywhere) expands the sheet.
      // Under the scrolling part, so it stays in reach when the sheet is
      // taller than the screen.
      Item {
        id: handleRow
        visible: !root.editing
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: sheet.contentBottomInset
        anchors.leftMargin: sheet.contentLeftInset
        anchors.rightMargin: sheet.contentRightInset
        height: visible ? Math.max(28, Style.space(28)) : 0

        Rectangle {
          anchors.centerIn: parent
          width: Style.space(48)
          height: Math.max(4, Style.space(4))
          radius: height / 2
          color: Util.alpha(root.foreground, 0.35)
        }

        // A thumb-high target (44 px) over the 28 px row: it reaches into
        // the padding above and below, so the layout doesn't move.
        MouseArea {
          objectName: "handle"
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(96, Style.space(120))
          height: Math.max(44, parent.height)
          cursorShape: Qt.PointingHandCursor
          onClicked: root.expanded = !root.expanded
        }
      }
    }

    // ---------- The notification shade: a card under the sheet that slides
    // with it and takes the room left below it, scrolling past that. On
    // its side, beside the sheet, the height of the screen.
    BorderSurface {
      id: shade
      objectName: "shade"

      // Not "top": every Item already has a FINAL top anchor line, and
      // Qt 6.12 refuses to load a file that redeclares it.
      readonly property real shadeTop: root.wide ? sheet.y : sheet.y + sheet.height + Style.spacing.lg
      readonly property real room: window.height - shadeTop - Style.gapsOut
      readonly property real insets: shade.contentTopInset + shade.contentBottomInset
      readonly property real listHeight: root.notifications.length > 0 ? shadeList.contentHeight : shadeEmpty.implicitHeight
      readonly property real natural: insets + shadeHeader.height + shadeColumn.spacing + listHeight

      visible: !root.editing && root.reveal > 0 && room >= insets + shadeHeader.height
      x: root.wide ? sheet.x + sheet.width + Style.spacing.lg : sheet.x
      y: shadeTop
      width: root.wide ? window.width - Style.gapsOut - x : sheet.width
      height: Math.min(natural, room)
      opacity: root.reveal
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      padding: root.pad

      // Taps on the card stay off the scrim, which would close the sheet.
      MouseArea { anchors.fill: parent }

      Column {
        id: shadeColumn
        anchors.fill: parent
        anchors.topMargin: shade.contentTopInset
        anchors.rightMargin: shade.contentRightInset
        anchors.bottomMargin: shade.contentBottomInset
        anchors.leftMargin: shade.contentLeftInset
        spacing: Style.spacing.md

        Item {
          id: shadeHeader
          width: parent.width
          height: clearButton.touchSize

          Text {
            anchors.left: parent.left
            anchors.right: clearButton.left
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: NotificationsModel.title(root.notifications.length)
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          SheetButton {
            id: clearButton
            objectName: "clearNotifications"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(104, Style.space(112))
            label: root.confirmClear ? "Clear all?" : "Clear all"
            danger: root.confirmClear
            foreground: root.foreground
            enabled: root.notifications.length > 0
            onTapped: root.requestClearNotifications()
          }
        }

        Text {
          id: shadeEmpty
          visible: root.notifications.length === 0
          width: parent.width
          textFormat: Text.PlainText
          text: "No notifications"
          color: Qt.darker(root.foreground, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Flickable {
          id: shadeList
          visible: root.notifications.length > 0
          width: parent.width
          height: Math.max(0, shade.height - shade.insets - shadeHeader.height - shadeColumn.spacing)
          contentWidth: width
          contentHeight: shadeRows.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          clip: true

          Column {
            id: shadeRows
            width: shadeList.width
            spacing: Style.spacing.xs

            Repeater {
              model: root.notifications
              delegate: NotificationRow {
                host: root
                entry: modelData
                width: shadeRows.width
                swipeEnabled: !shadeList.moving
              }
            }
          }
        }
      }
    }
  }

  // A tile bound to its backend by TilesModel id. `host` is this sheet:
  // inline components don't see the document's ids.
  component BoundTile: Tile {
    property var host: null
    property string tileId: ""
    objectName: "tile-" + tileId
    readonly property var backend: host && host.backends[tileId] ? host.backends[tileId] : null

    icon: backend ? backend.icon : ""
    label: TilesModel.label(tileId)
    status: backend ? backend.status : ""
    active: !!backend && backend.enabled
    available: !!backend && backend.available
    busy: !!backend && backend.busy === true
    details: !!backend && backend.details === true
    longPress: !!backend && backend.longPress === true
    onClicked: if (backend) backend.toggle()
    onDetailsRequested: if (backend && typeof backend.openDetails === "function") backend.openDetails()
  }
}
