// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "BluetoothModel.js" as BluetoothModel
import "Readable.js" as Readable

// The Bluetooth panel behind the quick-settings tile, after Android's: a
// Bluetooth switch, the phone's own name with "Make visible to other
// devices", the paired devices (connected first, with battery), then the
// devices discovery finds, named ones by signal and the address-only ones
// folded behind "Show unnamed devices".
//
// Tap an available device to pair, trust and connect; a paired one to
// connect; the connected one for its actions. Long-press a paired device for
// Connect/Disconnect, Rename and Forget.
//
// Quickshell.Bluetooth (BlueZ over D-Bus) is the device list, power state,
// visibility, disconnect, forget and rename. It has no pairing agent and no
// RSSI or device class, so while the panel is open it runs
// omamobile-bt-agent: a small BlueZ agent that answers numeric comparison,
// passkey and PIN requests through this panel's sheets, holds the discovery
// session, reports RSSI/appearance/class, and pairs and connects so failures
// come back with BlueZ's reason. Without the helper the panel still lists,
// pairs (Just Works only) and connects through Quickshell.
//
// The window sits on the top layer with normal exclusion, like the Wi-Fi
// picker, so the rename and PIN fields stay above the on-screen keyboard.
Item {
  id: root

  property bool opened: false
  property var adapter: null
  property bool powerPending: false
  property color foreground: Commons.Color.popups.text

  // The back glyph: the owner closes this and brings quick settings back.
  signal backRequested()
  // The switch: the owner turns the radio on or off (omarchy-bluetooth-power).
  signal powerToggleRequested()

  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int pad: Style.spacing.panelPadding
  readonly property int visibleSeconds: 120

  // ---------------------------------------------------------------- lifecycle

  function open() {
    if (opened) return
    opened = true
    holdSync = false
    showUnnamed = false
    failureAddress = ""
    failureText = ""
    pairing = BluetoothModel.pairingStep(null, { event: "reset" })
    cancelSheet()
    helperError = ""
    agent.running = true
    syncRows(true)
  }

  function close() {
    if (!opened) return
    opened = false
    cancelSheet()
    pairing = BluetoothModel.pairingStep(null, { event: "reset" })
    // Ending the helper ends its agent and its discovery session.
    agent.running = false
    if (actionKind !== "") finishAction()
    // Visibility belongs to the panel, as on Android.
    if (madeVisible && adapter && adapter.discoverable) adapter.discoverable = false
    madeVisible = false
  }

  // `shell call omamobile.quicksettings bluetoothPanel` returns this. Never
  // carries a PIN or passkey the user typed.
  function snapshot() {
    var lists = BluetoothModel.buildLists(currentRows())
    var brief = function(row) {
      return { label: row.label, address: row.address, type: row.deviceType, connected: row.connected,
               battery: row.battery, rssi: row.rssi === -999 ? null : row.rssi }
    }
    return JSON.stringify({
      opened: opened,
      adapter: adapter ? adapter.name : null,
      enabled: enabled,
      discovering: !!adapter && adapter.discovering,
      visible: !!adapter && adapter.discoverable,
      helper: helperReady ? "ready" : (helperError || (agent.running ? "starting" : "stopped")),
      paired: lists.paired.map(brief),
      available: lists.available.map(brief),
      unnamed: lists.unnamed.length,
      showUnnamed: showUnnamed,
      action: actionKind ? { kind: actionKind, address: actionAddress } : null,
      failure: failureText ? { address: failureAddress, text: failureText } : null,
      sheet: activeSheet,
      pairing: { phase: pairing.phase, address: pairing.address, request: pairing.request ? pairing.request.type : null }
    })
  }

  // ---------------------------------------------------------------- state

  readonly property bool enabled: !!adapter && adapter.enabled
  readonly property var deviceObjects: adapter && adapter.devices ? adapter.devices.values : []

  property var entries: []
  property bool showUnnamed: false
  property bool holdSync: false

  // address -> { rssi, appearance, class } from the helper. Kept outside the
  // binding system; syncRows reads it on its own schedule.
  property var extras: ({})

  property string actionKind: ""   // "pair" | "connect" | "disconnect" | "forget"
  property string actionAddress: ""
  property string failureAddress: ""
  property string failureText: ""

  // The agent's state machine (BluetoothModel.pairingStep).
  property var pairing: ({ phase: "idle", address: "", request: null, error: "" })
  readonly property var agentSheet: pairing.request ? BluetoothModel.requestSheet(pairing.request) : null

  // "" | "actions" | "rename"; an agent request takes over as "agent".
  property string sheet: ""
  property string sheetAddress: ""
  property string sheetLabel: ""
  property bool sheetConnected: false
  property bool sheetPaired: false
  property string sheetError: ""
  readonly property string activeSheet: agentSheet ? "agent" : sheet

  property bool madeVisible: false
  property int visibleRemaining: 0

  onDeviceObjectsChanged: syncRows(false)
  onEnabledChanged: syncRows(true)

  function currentRows() {
    var rows = []
    var list = deviceObjects || []
    for (var i = 0; i < list.length; i++) {
      var device = list[i]
      if (!device) continue
      var row = BluetoothModel.deviceRow(device, extras[String(device.address).toUpperCase()])
      if (row) rows.push(row)
    }
    return rows
  }

  function syncRows(force) {
    if (!opened) return
    if (holdSync && !force) return
    var next = BluetoothModel.listEntries(BluetoothModel.buildLists(currentRows()), showUnnamed, enabled)
    if (JSON.stringify(next) !== JSON.stringify(entries)) entries = next
    checkAction()
  }

  // RSSI, battery and names change without touching `values`.
  Timer {
    interval: 2000
    repeat: true
    running: root.opened
    onTriggered: root.syncRows(false)
  }

  function deviceFor(address) {
    var list = deviceObjects || []
    for (var i = 0; i < list.length; i++)
      if (list[i] && String(list[i].address).toUpperCase() === String(address).toUpperCase()) return list[i]
    return null
  }

  function labelFor(address) {
    var device = deviceFor(address)
    var row = device ? BluetoothModel.deviceRow(device, null) : null
    return row ? row.label : address
  }

  // ---------------------------------------------------------------- the agent helper

  property bool helperReady: false
  property string helperError: ""

  Process {
    id: agent
    command: ["omamobile-bt-agent"]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { root.helperEvent(BluetoothModel.parseHelperLine(line)) }
    }
    onRunningChanged: if (!running) root.helperReady = false
    onExited: function(exitCode) {
      root.helperReady = false
      if (exitCode !== 0 && root.opened && !root.helperError) root.helperError = "Pairing helper stopped"
    }
  }

  function send(command) {
    if (agent.running) agent.write(JSON.stringify(command) + "\n")
  }

  function helperEvent(event) {
    if (!event) return
    switch (event.event) {
    case "ready":
      helperReady = true
      helperError = ""
      break
    case "error":
      helperReady = false
      helperError = String(event.message || "Pairing helper failed")
      break
    case "device":
      extras[String(event.address).toUpperCase()] = { rssi: event.rssi, appearance: event.appearance, "class": event["class"] }
      break
    case "removed":
      delete extras[String(event.address).toUpperCase()]
      break
    case "request":
      event.label = labelFor(event.address)
      pairing = BluetoothModel.pairingStep(pairing, event)
      if (event.type === "pin" || event.type === "passkey")
        Qt.callLater(function() { codeField.forceActiveFocus() })
      break
    case "cancel":
      var wasOurs = pairing.phase !== "idle" && pairing.address !== ""
      pairing = BluetoothModel.pairingStep(pairing, event)
      if (wasOurs && actionKind === "pair") fail(pairing.address, pairing.error)
      break
    case "result":
      helperResult(event)
      break
    }
  }

  function helperResult(event) {
    if (event.op === "pair") {
      pairing = BluetoothModel.pairingStep(pairing, event)
      if (pairing.phase === "done") return finishAction()
      // Paired, but the connect after it failed: say why, keep it paired.
      var text = event.stage === "connect" ? BluetoothModel.errorMessage("connect", event.error, event.message) : pairing.error
      pairing = BluetoothModel.pairingStep(null, { event: "reset" })
      fail(event.address, text)
      return
    }
    if (event.ok || BluetoothModel.isHarmless(event.error)) finishAction()
    else fail(event.address, BluetoothModel.errorMessage("connect", event.error, event.message))
  }

  // If the helper failed, discovery is Quickshell's: keep it on while open and
  // take it down after (the session is held by the shell's own connection,
  // so nothing else ends it).
  property bool owesDiscoveryStop: false

  Timer {
    interval: 1500
    repeat: true
    triggeredOnStart: true
    running: root.opened && root.helperError !== "" && root.enabled && !root.adapter.discovering
    onTriggered: {
      root.owesDiscoveryStop = true
      root.adapter.discovering = true
    }
  }

  Timer {
    interval: 1000
    repeat: true
    property int attempts: 0
    running: !root.opened && root.owesDiscoveryStop && !!root.adapter && root.adapter.discovering
    onRunningChanged: if (running) attempts = 0
    onTriggered: {
      if (++attempts > 3) { root.owesDiscoveryStop = false; return }
      root.adapter.discovering = false
    }
  }

  Connections {
    target: root.adapter
    ignoreUnknownSignals: true
    function onDiscoveringChanged() { if (!root.adapter.discovering && !root.opened) root.owesDiscoveryStop = false }
    function onDiscoverableChanged() { if (!root.adapter.discoverable) root.visibleRemaining = 0 }
  }

  // The refresh glyph: restart discovery so stale devices drop off.
  function rescan() {
    if (!enabled) return
    if (helperReady) {
      send({ cmd: "discover", on: false })
      send({ cmd: "discover", on: true })
    } else if (adapter) {
      adapter.discovering = false
    }
  }

  // ---------------------------------------------------------------- visibility

  function setVisible(on) {
    if (!adapter || !enabled) return
    if (on) {
      adapter.discoverableTimeout = visibleSeconds
      adapter.pairable = true
      adapter.discoverable = true
      madeVisible = true
      visibleRemaining = visibleSeconds
    } else {
      adapter.discoverable = false
      visibleRemaining = 0
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.visibleRemaining > 0
    onTriggered: root.visibleRemaining = Math.max(0, root.visibleRemaining - 1)
  }

  // ---------------------------------------------------------------- actions

  function runAction(kind, address) {
    if (actionKind !== "") return false
    actionKind = kind
    actionAddress = address
    failureAddress = ""
    failureText = ""
    actionTimeout.interval = kind === "pair" ? 95000 : 45000
    actionTimeout.restart()
    syncRows(true)
    return true
  }

  function finishAction() {
    actionTimeout.stop()
    actionKind = ""
    actionAddress = ""
    syncRows(true)
  }

  function fail(address, text) {
    actionTimeout.stop()
    actionKind = ""
    actionAddress = ""
    failureAddress = address
    failureText = text || "Something went wrong"
    syncRows(true)
  }

  // Quickshell-side completion, for the actions it runs itself (and for the
  // fallback pair/connect when the helper isn't there).
  function checkAction() {
    if (actionKind === "") return
    var device = deviceFor(actionAddress)
    if (actionKind === "forget" && (!device || !(device.paired || device.bonded))) return finishAction()
    if (!device) return
    if (actionKind === "disconnect" && !device.connected) finishAction()
    else if (!helperReady && actionKind === "connect" && device.connected) finishAction()
    else if (!helperReady && actionKind === "pair" && (device.paired || device.bonded)) {
      if (!device.trusted) device.trusted = true
      if (device.connected) finishAction()
      else if (!fallbackConnectSent) { fallbackConnectSent = true; device.connect() }
    }
  }

  property bool fallbackConnectSent: false

  Timer {
    id: actionTimeout
    onTriggered: {
      if (root.actionKind === "pair") root.pairing = BluetoothModel.pairingStep(null, { event: "reset" })
      root.fail(root.actionAddress, root.actionKind === "pair" ? "Pairing timed out" : "Timed out. Is it in range?")
    }
  }

  function tapRow(row) {
    if (!row || actionKind !== "") return
    if (row.kind === "more") {
      showUnnamed = !showUnnamed
      syncRows(true)
      return
    }
    var action = BluetoothModel.tapAction(row)
    if (action === "actions") openActions(row)
    else if (action === "connect") connectDevice(row.address)
    else if (action === "pair") pairDevice(row.address)
  }

  function longPressRow(row) {
    if (!row || actionKind !== "") return
    if (BluetoothModel.longPressActions(row).length > 0) openActions(row)
  }

  function pairDevice(address) {
    if (!runAction("pair", address)) return
    if (helperReady) {
      pairing = BluetoothModel.pairingStep(pairing, { event: "start", address: address })
      send({ cmd: "pair", address: address })
      return
    }
    var device = deviceFor(address)
    if (!device) return fail(address, "Device out of range")
    fallbackConnectSent = false
    device.pair()
  }

  function connectDevice(address) {
    if (!runAction("connect", address)) return
    if (helperReady) return send({ cmd: "connect", address: address })
    var device = deviceFor(address)
    if (!device) return fail(address, "Device out of range")
    device.connect()
  }

  function disconnectSheet() {
    var address = sheetAddress
    cancelSheet()
    var device = deviceFor(address)
    if (device && runAction("disconnect", address)) device.disconnect()
  }

  function connectSheet() {
    var address = sheetAddress
    cancelSheet()
    connectDevice(address)
  }

  // Forget unpairs the device, so it takes two taps (TOUCH-PLAN 3.7): the
  // first turns it into "Forget <device>?" for a few seconds.
  property bool confirmForget: false

  Timer {
    id: disarmForget
    interval: 4000
    onTriggered: root.confirmForget = false
  }

  function requestForget() {
    if (!confirmForget) {
      confirmForget = true
      disarmForget.restart()
      return
    }
    forgetSheet()
  }

  function forgetSheet() {
    var address = sheetAddress
    cancelSheet()
    var device = deviceFor(address)
    if (device && runAction("forget", address)) device.forget()
  }

  function submitRename() {
    var name = renameField.text.trim()
    if (!name) {
      sheetError = "Enter a name"
      return
    }
    var device = deviceFor(sheetAddress)
    if (device) device.name = name
    cancelSheet()
    syncRows(true)
  }

  // ---------------------------------------------------------------- agent answers

  function answerAgent(accept) {
    var request = pairing.request
    if (!request) return
    if (/^display/.test(request.type)) {
      // Nothing to answer; cancelling stops the pairing itself.
      if (!accept) send({ cmd: "cancel-pair", address: request.address })
      pairing = BluetoothModel.pairingStep(pairing, { event: "answered", accept: accept })
      if (!accept) fail(request.address, "Pairing canceled")
      return
    }
    var value = codeField.text
    if (accept && agentSheet.input && !BluetoothModel.validInput(agentSheet.input, value)) {
      sheetError = agentSheet.input === "passkey" ? "Enter up to 6 digits" : "Enter 1 to 16 characters"
      return
    }
    send(JSON.parse(BluetoothModel.replyCommand(request, accept, value)))
    value = ""
    codeField.text = ""
    sheetError = ""
    pairing = BluetoothModel.pairingStep(pairing, { event: "answered", accept: accept })
    if (!accept && actionKind === "pair") fail(request.address, "Pairing canceled")
  }

  // ---------------------------------------------------------------- sheets

  function openActions(row) {
    sheet = "actions"
    sheetAddress = row.address
    sheetLabel = row.label
    sheetConnected = !!row.connected
    sheetPaired = !!row.paired
    sheetError = ""
  }

  function openRename() {
    sheet = "rename"
    sheetError = ""
    renameField.text = sheetLabel
    Qt.callLater(function() { renameField.forceActiveFocus(); renameField.selectAll() })
  }

  function cancelSheet() {
    if (agentSheet) return answerAgent(false)
    sheet = ""
    sheetError = ""
    confirmForget = false
    disarmForget.stop()
    renameField.text = ""
    codeField.text = ""
    if (opened) panel.forceActiveFocus()
  }

  // ---------------------------------------------------------------- surface

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  PanelWindow {
    id: window

    visible: root.opened || root.reveal > 0
    anchors { top: true; bottom: true; left: true; right: true }
    // Normal: fit between the status bar and the on-screen keyboard.
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-bluetooth"
    WlrLayershell.layer: WlrLayer.Top
    // OnDemand, not Exclusive, or the on-screen keyboard gets no touches.
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
      opacity: root.reveal
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: panel

      x: Style.gapsOut
      width: parent.width - Style.gapsOut * 2
      height: parent.height - Style.gapsOut * 2
      y: Style.gapsOut + Math.round((1 - root.reveal) * Style.space(60))
      opacity: root.reveal
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      padding: root.pad

      focus: root.opened
      Keys.onEscapePressed: {
        if (root.activeSheet) root.cancelSheet()
        else root.close()
      }

      // Swallow taps so they don't reach the scrim.
      MouseArea { anchors.fill: parent }

      Item {
        id: body
        anchors.fill: parent
        anchors.topMargin: panel.contentTopInset
        anchors.rightMargin: panel.contentRightInset
        anchors.bottomMargin: panel.contentBottomInset
        anchors.leftMargin: panel.contentLeftInset

        // ---------- Header: back, title, rescan
        Item {
          id: header
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.touchSize

          GlyphButton {
            id: back
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰁍"
            onTapped: root.backRequested()
          }

          Text {
            anchors.left: back.right
            anchors.leftMargin: Style.spacing.lg
            anchors.right: refresh.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Bluetooth"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          GlyphButton {
            id: refresh
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰑐"
            spinning: root.enabled && !!root.adapter && root.adapter.discovering
            enabled: root.enabled
            onTapped: root.rescan()
          }
        }

        // ---------- The radio switch
        SwitchRow {
          id: powerRow
          anchors.top: header.bottom
          anchors.topMargin: Style.spacing.lg
          anchors.left: parent.left
          anchors.right: parent.right
          label: "Use Bluetooth"
          detail: root.powerPending ? (root.enabled ? "Turning off…" : "Turning on…") : ""
          checked: root.enabled
          available: !!root.adapter && !root.powerPending
          onToggled: root.powerToggleRequested()
        }

        // ---------- The phone's own name and visibility
        SwitchRow {
          id: visibleRow
          visible: root.enabled
          anchors.top: powerRow.bottom
          anchors.topMargin: visible ? Style.spacing.lg : 0
          anchors.left: parent.left
          anchors.right: parent.right
          height: visible ? implicitHeight : 0
          label: "Make visible to other devices"
          detail: root.adapter && root.adapter.discoverable && root.visibleRemaining > 0
            ? "\"" + root.adapter.name + "\" · " + BluetoothModel.visibilityText(root.visibleRemaining)
            : "This phone is \"" + (root.adapter ? root.adapter.name : "") + "\""
          checked: !!root.adapter && root.adapter.discoverable
          onToggled: root.setVisible(!checked)
        }

        // ---------- Errors: the last failure, tap to dismiss
        BorderSurface {
          id: banner
          readonly property string message: root.failureText
            ? (root.failureAddress ? root.labelFor(root.failureAddress) + ": " : "") + root.failureText
            : (root.helperError && root.enabled ? root.helperError + ". Only simple pairing works." : "")
          visible: message !== ""
          anchors.top: visibleRow.bottom
          anchors.topMargin: visible ? Style.spacing.lg : 0
          anchors.left: parent.left
          anchors.right: parent.right
          height: visible ? Math.max(44, bannerText.implicitHeight + Style.spacing.xl * 2) : 0
          radius: Style.cornerRadius
          color: Util.alpha(Commons.Color.urgent, 0.15)
          borderSpec: Border.flat(Commons.Color.urgent, Math.max(1, Style.normalBorderWidth))

          Text {
            id: bannerText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Style.spacing.xxl
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: banner.message
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }

          MouseArea {
            anchors.fill: parent
            onClicked: { root.failureText = ""; root.failureAddress = "" }
          }
        }

        // ---------- Off: say so instead of an empty list
        Text {
          visible: !root.enabled
          anchors.top: banner.bottom
          anchors.topMargin: Style.spacing.huge
          anchors.left: parent.left
          anchors.right: parent.right
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: root.adapter ? "Turn on Bluetooth to see devices" : "No Bluetooth adapter"
          color: Readable.secondary(root.foreground, Commons.Color.popups.background)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }

        // ---------- Devices
        ListView {
          id: list
          visible: root.enabled
          anchors.top: banner.bottom
          anchors.topMargin: Style.spacing.lg
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          clip: true
          model: root.entries
          boundsBehavior: Flickable.DragOverBounds

          readonly property real pullThreshold: Style.space(70)
          onDragEnded: if (contentY < originY - pullThreshold) root.rescan()

          delegate: Item {
            id: entryItem

            required property var modelData
            readonly property var row: modelData
            readonly property bool isHeader: row.kind === "header"
            readonly property bool isEmpty: row.kind === "empty"
            readonly property bool isMore: row.kind === "more"
            readonly property bool busy: root.actionKind !== "" && root.actionAddress === row.address
            readonly property string failure: root.failureAddress !== "" && root.failureAddress === row.address ? root.failureText : ""

            width: list.width
            height: isHeader ? Math.max(32, Style.space(36)) : (isEmpty || isMore) ? root.touchSize : Math.max(56, Style.space(64))

            Text {
              visible: entryItem.isHeader
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.lg
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.spacing.sm
              textFormat: Text.PlainText
              text: entryItem.row.text
              color: Commons.Color.accent
              font.family: Style.font.family
              font.pixelSize: Readable.px(Style.font.caption)
              font.bold: true
            }

            Text {
              visible: entryItem.isEmpty
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: entryItem.row.text
              color: Readable.secondary(root.foreground, Commons.Color.popups.background)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            // "Show N unnamed devices"
            Rectangle {
              visible: entryItem.isMore
              anchors.fill: parent
              anchors.topMargin: Style.spacing.xxs
              anchors.bottomMargin: Style.spacing.xxs
              radius: Style.cornerRadius
              color: moreTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent) : "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.xl
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: (root.showUnnamed ? "󰅃  " : "󰅀  ") + entryItem.row.text
                color: Commons.Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: moreTouch
                anchors.fill: parent
                enabled: entryItem.isMore
                onClicked: root.tapRow(entryItem.row)
              }
            }

            // A device
            Rectangle {
              visible: entryItem.row.kind === "device"
              anchors.fill: parent
              anchors.topMargin: Style.spacing.xxs
              anchors.bottomMargin: Style.spacing.xxs
              radius: Style.cornerRadius
              color: rowTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
                : entryItem.row.connected ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
                : "transparent"

              Text {
                id: kindGlyph
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.xl
                anchors.verticalCenter: parent.verticalCenter
                width: Style.font.display
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: BluetoothModel.kindGlyph(entryItem.row.deviceType)
                color: entryItem.row.connected ? Commons.Color.accent : root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.display
              }

              Column {
                anchors.left: kindGlyph.right
                anchors.leftMargin: Style.spacing.xl
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.xl
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xxs

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: entryItem.row.label
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: entryItem.row.connected
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  visible: text !== ""
                  textFormat: Text.PlainText
                  text: BluetoothModel.rowStatus(entryItem.row, entryItem.busy ? root.actionKind : "", entryItem.failure)
                  color: entryItem.failure ? Commons.Color.urgent : Readable.secondary(root.foreground, Commons.Color.popups.background)
                  font.family: Style.font.family
                  font.pixelSize: Readable.px(Style.font.caption)
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                id: rowTouch
                anchors.fill: parent
                enabled: entryItem.row.kind === "device"
                cursorShape: Qt.PointingHandCursor
                pressAndHoldInterval: 450
                onPressedChanged: root.holdSync = pressed
                onClicked: root.tapRow(entryItem.row)
                onPressAndHold: root.longPressRow(entryItem.row)
              }
            }
          }
        }

        // ---------- Sheets over the list
        Rectangle {
          anchors.fill: parent
          visible: root.activeSheet !== ""
          color: Commons.Color.menu.scrim

          MouseArea {
            anchors.fill: parent
            onClicked: root.cancelSheet()
          }
        }

        BorderSurface {
          id: sheetCard
          visible: root.activeSheet !== ""
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: sheetContent.implicitHeight + sheetCard.contentTopInset + sheetCard.contentBottomInset
          color: Commons.Color.popups.background
          borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
          radius: Style.cornerRadius
          padding: root.pad

          MouseArea { anchors.fill: parent }

          Column {
            id: sheetContent
            anchors.fill: parent
            anchors.topMargin: sheetCard.contentTopInset
            anchors.rightMargin: sheetCard.contentRightInset
            anchors.bottomMargin: sheetCard.contentBottomInset
            anchors.leftMargin: sheetCard.contentLeftInset
            spacing: Style.spacing.xxl

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.agentSheet ? root.agentSheet.title : root.sheetLabel
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              wrapMode: Text.Wrap
            }

            Text {
              width: parent.width
              visible: text !== ""
              textFormat: Text.PlainText
              text: root.agentSheet ? root.agentSheet.body : ""
              color: Readable.secondary(root.foreground, Commons.Color.popups.background)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }

            // The code to compare or type; digits already typed on a
            // keyboard light up.
            Row {
              visible: !!root.agentSheet && root.agentSheet.display !== ""
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.spacing.lg

              Repeater {
                model: root.agentSheet && root.agentSheet.display ? root.agentSheet.display.split("") : []

                Text {
                  required property var modelData
                  required property int index
                  textFormat: Text.PlainText
                  text: modelData
                  color: root.agentSheet && index < (root.agentSheet.entered || 0) ? Commons.Color.accent : root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.displayLarge
                  font.bold: true
                }
              }
            }

            Text {
              width: parent.width
              visible: text !== ""
              textFormat: Text.PlainText
              text: root.sheetError
              color: Commons.Color.urgent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }

            // PIN or passkey entry.
            TextField {
              id: codeField
              visible: !!root.agentSheet && root.agentSheet.input !== ""
              width: parent.width
              height: visible ? root.touchSize : 0
              verticalAlignment: TextInput.AlignVCenter
              font.pixelSize: Style.font.title
              foreground: root.foreground
              placeholderText: root.agentSheet && root.agentSheet.input === "passkey" ? "Passkey" : "PIN"
              placeholderTextColor: Readable.secondary(root.foreground, Readable.flatten(Style.controlFill(activeFocus, hovered || hasCursor, foreground, accent), Commons.Color.popups.background))
              maximumLength: root.agentSheet && root.agentSheet.input === "passkey" ? 6 : 16
              inputMethodHints: root.agentSheet && root.agentSheet.input === "passkey"
                ? Qt.ImhDigitsOnly | Qt.ImhNoPredictiveText
                : Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
              onAccepted: root.answerAgent(true)
              onTextEdited: root.sheetError = ""
              Keys.onEscapePressed: root.cancelSheet()
            }

            // Rename.
            TextField {
              id: renameField
              visible: root.activeSheet === "rename"
              width: parent.width
              height: visible ? root.touchSize : 0
              verticalAlignment: TextInput.AlignVCenter
              font.pixelSize: Style.font.title
              foreground: root.foreground
              placeholderText: "Name"
              placeholderTextColor: Readable.secondary(root.foreground, Readable.flatten(Style.controlFill(activeFocus, hovered || hasCursor, foreground, accent), Commons.Color.popups.background))
              maximumLength: 248
              onAccepted: root.submitRename()
              onTextEdited: root.sheetError = ""
              Keys.onEscapePressed: root.cancelSheet()
            }

            // Agent and rename sheets: Cancel / the answer, side by side.
            Row {
              visible: root.activeSheet === "agent" || root.activeSheet === "rename"
              width: parent.width
              height: visible ? root.touchSize : 0
              spacing: Style.spacing.lg
              layoutDirection: Qt.RightToLeft

              readonly property string acceptLabel: root.activeSheet === "rename" ? "Rename"
                : root.agentSheet ? root.agentSheet.accept : ""

              SheetButton {
                visible: parent.acceptLabel !== ""
                width: (parent.width - parent.spacing) / 2
                label: parent.acceptLabel
                primary: true
                onTapped: root.activeSheet === "rename" ? root.submitRename() : root.answerAgent(true)
              }

              SheetButton {
                width: parent.acceptLabel !== "" ? (parent.width - parent.spacing) / 2 : parent.width
                label: "Cancel"
                onTapped: root.cancelSheet()
              }
            }

            // Actions: Connect or Disconnect / Rename / Forget / Cancel.
            SheetButton {
              visible: root.activeSheet === "actions" && root.sheetPaired
              width: parent.width
              label: root.sheetConnected ? "Disconnect" : "Connect"
              onTapped: root.sheetConnected ? root.disconnectSheet() : root.connectSheet()
            }

            SheetButton {
              visible: root.activeSheet === "actions" && root.sheetPaired
              width: parent.width
              label: "Rename"
              onTapped: root.openRename()
            }

            SheetButton {
              visible: root.activeSheet === "actions" && root.sheetPaired
              width: parent.width
              label: root.confirmForget ? "Forget " + root.sheetLabel + "?" : "Forget"
              danger: true
              onTapped: root.requestForget()
            }

            SheetButton {
              visible: root.activeSheet === "actions"
              width: parent.width
              label: "Cancel"
              onTapped: root.cancelSheet()
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- parts

  // A tile-like row with a label, a detail line and a switch; the whole row
  // is the touch target.
  component SwitchRow: BorderSurface {
    id: switchRow

    property string label: ""
    property string detail: ""
    property bool checked: false
    property bool available: true
    signal toggled()

    implicitHeight: Math.max(56, Style.space(60))
    height: implicitHeight
    radius: Style.cornerRadius
    opacity: available ? 1 : 0.6
    color: switchTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
      : checked ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
      : Style.normalFillFor(root.foreground, Commons.Color.accent)
    borderSpec: Border.controlSpec(checked ? "selected" : "normal", root.foreground, Commons.Color.accent)

    Column {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.xxl + switchRow.borderLeft
      anchors.right: knob.left
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xxs

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: switchRow.label
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: text !== ""
        textFormat: Text.PlainText
        text: switchRow.detail
        color: Readable.secondary(root.foreground, Commons.Color.popups.background)
        font.family: Style.font.family
        font.pixelSize: Readable.px(Style.font.caption)
        elide: Text.ElideRight
      }
    }

    ToggleSwitch {
      id: knob
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.xl + switchRow.borderRight
      anchors.verticalCenter: parent.verticalCenter
      checked: switchRow.checked
      interactive: false
      foreground: root.foreground
    }

    MouseArea {
      id: switchTouch
      anchors.fill: parent
      enabled: switchRow.available
      cursorShape: Qt.PointingHandCursor
      onClicked: switchRow.toggled()
    }
  }
}
