// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "WifiModel.js" as WifiModel
import "Readable.js" as Readable

// The Wi-Fi picker behind the quick-settings tile, after Android's Internet
// panel: a Wi-Fi switch, the connected network, the networks in range by
// signal, and saved profiles that are out of range.
//
// Tap a network to connect: open and saved ones go straight through,
// secured new ones ask for a password first. Long-press a connected or saved
// one for Disconnect and Forget. Tap the connected one for the same sheet.
// Pull the list down or tap the refresh glyph to rescan.
//
// Everything goes through Quickshell.Networking (NetworkManager over D-Bus):
// connect(), connectWithPsk(), disconnect(), forget(), and the device's
// scanner. Two things it can't do fall back to nmcli: listing saved profiles
// that are out of range (and forgetting one), and connecting with a password
// on a Quickshell without connectWithPsk. The password never reaches argv
// or the log; the fallback feeds it to `nmcli --ask` on stdin.
//
// The window sits on the top layer with normal exclusion, like the launcher's
// drawer, so it fits between the status bar and the on-screen keyboard and the
// password sheet stays above the keys.
Item {
  id: root

  property bool opened: false
  property var device: null
  property color foreground: Commons.Color.popups.text

  // The back glyph: the owner closes this and brings quick settings back.
  signal backRequested()

  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int pad: Style.spacing.panelPadding

  // ---------------------------------------------------------------- lifecycle

  function open() {
    if (opened) return
    opened = true
    holdSync = false
    cancelSheet()
    failureSsid = ""
    failureText = ""
    syncRows(true)
    refreshSaved()
    rescan()
  }

  function close() {
    if (!opened) return
    opened = false
    cancelSheet()
    setScanner(false)
  }

  // `shell call omamobile.quicksettings wifiPanel` returns this. Names and
  // signal only; nothing secret is ever held here past a submit.
  function snapshot() {
    var rows = WifiModel.buildRows(networkObjects, WifiSecurityType.Open, WifiSecurityType.Owe)
    return JSON.stringify({
      opened: opened,
      device: device ? device.name : null,
      enabled: wifiOn,
      connected: rows.connected ? rows.connected.ssid : null,
      available: rows.available.map(function(row) { return { ssid: row.ssid, signal: row.signal, secured: row.secured, known: row.known } }),
      savedOutOfRange: savedRows.map(function(profile) { return profile.name }),
      action: actionKind ? { kind: actionKind, ssid: actionSsid } : null,
      failure: failureText ? { ssid: failureSsid, text: failureText } : null,
      sheet: sheet
    })
  }

  // ---------------------------------------------------------------- state

  readonly property bool wifiOn: !!device && Networking.wifiEnabled
  readonly property var networkObjects: device && device.networks ? device.networks.values : []

  // The list model: plain rows from WifiModel.listEntries.
  property var entries: []
  // Saved profiles from nmcli, and the ones of them nothing in range matches.
  property var savedProfiles: []
  property var savedRows: []

  // One action at a time, tracked by SSID; the live object is resolved again
  // whenever it's needed rather than kept.
  property string actionKind: ""   // "connect" | "disconnect" | "forget"
  property string actionSsid: ""
  property bool actionSecured: false
  property string failureSsid: ""
  property string failureText: ""

  // The sheet over the list: "" | "password" | "actions".
  property string sheet: ""
  property string sheetSsid: ""
  property string sheetUuid: ""     // set for a saved profile out of range
  property bool sheetConnected: false
  property bool sheetKnown: false
  property string sheetError: ""
  property bool showPassword: false

  property bool scanning: false
  // A finger is on a row: hold list rebuilds so its long-press survives.
  property bool holdSync: false

  readonly property var failReasons: ({
    NoSecrets: ConnectionFailReason.NoSecrets,
    WifiAuthTimeout: ConnectionFailReason.WifiAuthTimeout,
    WifiNetworkLost: ConnectionFailReason.WifiNetworkLost,
    WifiClientDisconnected: ConnectionFailReason.WifiClientDisconnected,
    WifiClientFailed: ConnectionFailReason.WifiClientFailed
  })

  onNetworkObjectsChanged: syncRows(false)
  onWifiOnChanged: {
    syncRows(true)
    if (wifiOn && opened) rescan()
  }

  function syncRows(force) {
    if (!opened) return
    if (holdSync && !force) return
    var rows = WifiModel.buildRows(networkObjects, WifiSecurityType.Open, WifiSecurityType.Owe)
    var visible = rows.available.slice()
    if (rows.connected) visible.push(rows.connected)
    savedRows = WifiModel.savedOutOfRange(savedProfiles, visible)
    var next = WifiModel.listEntries(rows, savedRows, wifiOn)
    if (!WifiModel.sameRows(next, entries)) entries = next
    checkAction()
  }

  // Signal strength changes don't touch `values`, so poll while open.
  Timer {
    interval: 2000
    repeat: true
    running: root.opened
    onTriggered: root.syncRows(false)
  }

  function networkForSsid(ssid) {
    var list = networkObjects || []
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].name === ssid) return list[i]
    return null
  }

  // ---------------------------------------------------------------- scanning

  // scannerEnabled is shared state on the device; remember which device this
  // panel turned it on for so closing (or a new device) releases the right one.
  property var scannerDevice: null

  function setScanner(enabled) {
    var next = opened ? device : null
    if (scannerDevice && scannerDevice !== next) scannerDevice.scannerEnabled = false
    scannerDevice = next
    if (scannerDevice) scannerDevice.scannerEnabled = enabled
  }

  // Off and on again asks NetworkManager for a fresh scan.
  function rescan() {
    if (!opened || !device || !wifiOn) return
    scanning = true
    setScanner(false)
    scanRestart.restart()
    refreshSaved()
  }

  Timer {
    id: scanRestart
    interval: 100
    onTriggered: {
      root.setScanner(true)
      scanDone.restart()
    }
  }

  Timer {
    id: scanDone
    interval: 4000
    onTriggered: root.scanning = false
  }

  Component.onDestruction: if (scannerDevice) scannerDevice.scannerEnabled = false

  // ---------------------------------------------------------------- saved profiles

  function refreshSaved() {
    if (!savedProc.running) savedProc.running = true
  }

  Process {
    id: savedProc
    command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE", "connection", "show"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.savedProfiles = WifiModel.parseSavedConnections(text)
        root.syncRows(true)
      }
    }
  }

  // ---------------------------------------------------------------- actions

  function runAction(kind, ssid, secured, callback) {
    if (actionKind !== "") return false
    var network = networkForSsid(ssid)
    if (!network) {
      fail(ssid, "Network out of range")
      return false
    }
    actionKind = kind
    actionSsid = ssid
    actionSecured = secured
    failureSsid = ""
    failureText = ""
    actionTimeout.restart()
    callback(network)
    syncRows(true)
    return true
  }

  function finishAction() {
    actionTimeout.stop()
    actionKind = ""
    actionSsid = ""
    refreshSaved()
    syncRows(true)
  }

  function fail(ssid, text) {
    actionTimeout.stop()
    actionKind = ""
    actionSsid = ""
    failureSsid = ssid
    failureText = text
    syncRows(true)
  }

  function checkAction() {
    if (actionKind === "") return
    var network = networkForSsid(actionSsid)
    if (!network) return
    if (actionKind === "connect" && network.connected) finishAction()
    else if (actionKind === "disconnect" && !network.connected && !network.stateChanging) finishAction()
    else if (actionKind === "forget" && !network.known && !network.stateChanging) finishAction()
  }

  // The network being acted on, for its failure signal.
  Connections {
    target: root.actionKind !== "" ? root.networkForSsid(root.actionSsid) : null
    ignoreUnknownSignals: true
    function onConnectionFailed(reason) {
      if (root.actionKind !== "connect") return
      var ssid = root.actionSsid
      var secured = root.actionSecured
      root.fail(ssid, WifiModel.failureMessage(reason, secured, root.failReasons))
      if (WifiModel.shouldReprompt(reason, secured, root.failReasons)) root.openPassword(ssid, root.failureText)
    }
    function onConnectedChanged() { root.checkAction() }
    function onKnownChanged() { root.checkAction() }
    function onStateChangingChanged() { root.checkAction() }
  }

  // Longer than NetworkManager's 25 s supplicant timeout, so a wrong saved
  // password still lands as "Wrong password" rather than a timeout.
  Timer {
    id: actionTimeout
    interval: 30000
    onTriggered: {
      var verb = root.actionKind === "connect" ? "connecting" : root.actionKind === "disconnect" ? "disconnecting" : "forgetting"
      root.fail(root.actionSsid, "Timed out " + verb)
    }
  }

  function tapRow(row) {
    if (!row || actionKind !== "") return
    if (row.kind === "saved") return openActions(row)
    var action = WifiModel.tapAction(row)
    if (action === "details") openActions(row)
    else if (action === "connect") connect(row.ssid, row.secured)
    else if (action === "password") openPassword(row.ssid, "")
  }

  function longPressRow(row) {
    if (!row || actionKind !== "") return
    if (row.kind === "saved" || WifiModel.longPressActions(row).length > 0) openActions(row)
  }

  function connect(ssid, secured) {
    runAction("connect", ssid, secured, function(network) { network.connect() })
  }

  function submitPassword() {
    var ssid = sheetSsid
    var psk = passwordField.text
    if (!ssid || psk.length === 0 || actionKind !== "") return
    // WPA passphrases are 8-63 characters; NetworkManager rejects others.
    if (psk.length < 8) {
      sheetError = "Passwords are at least 8 characters"
      return
    }
    passwordField.text = ""
    cancelSheet()
    runAction("connect", ssid, true, function(network) {
      if (typeof network.connectWithPsk === "function") {
        network.connectWithPsk(psk)
      } else {
        pskConnect.secret = psk
        pskConnect.ssid = ssid
        pskConnect.command = WifiModel.nmcliConnectArgv(ssid, root.device ? root.device.name : "")
        pskConnect.running = true
      }
    })
    psk = ""
  }

  // Fallback only. `--ask` makes nmcli prompt for the secret, which arrives on
  // stdin; argv carries the SSID and interface and nothing else.
  Process {
    id: pskConnect
    property string secret: ""
    property string ssid: ""
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
    }
    stderr: StdioCollector {
      id: pskConnectErrors
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.checkAction()
        return
      }
      var message = WifiModel.nmcliFailureMessage(pskConnectErrors.text)
      root.fail(ssid, message)
      if (message === "Wrong password") root.openPassword(ssid, message)
    }
  }

  function disconnectSheet() {
    var ssid = sheetSsid
    cancelSheet()
    runAction("disconnect", ssid, false, function(network) { network.disconnect() })
  }

  // Forget drops the saved password, so it takes two taps (TOUCH-PLAN 3.7):
  // the first turns it into "Forget <network>?" for a few seconds.
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
    var ssid = sheetSsid
    var uuid = sheetUuid
    cancelSheet()
    if (uuid) {
      // Out of range: there's no WifiNetwork to call forget() on.
      forgetProc.command = ["nmcli", "connection", "delete", "uuid", uuid]
      forgetProc.running = true
      return
    }
    runAction("forget", ssid, false, function(network) { network.forget() })
  }

  Process {
    id: forgetProc
    onExited: root.refreshSaved()
  }

  // ---------------------------------------------------------------- sheets

  function openPassword(ssid, error) {
    sheet = "password"
    sheetSsid = ssid
    sheetUuid = ""
    sheetError = error || ""
    showPassword = false
    passwordField.text = ""
    Qt.callLater(function() { passwordField.forceActiveFocus() })
  }

  function openActions(row) {
    sheet = "actions"
    sheetSsid = row.ssid
    sheetUuid = row.kind === "saved" ? row.uuid : ""
    sheetConnected = !!row.connected
    sheetKnown = !!row.known
    sheetError = ""
  }

  function cancelSheet() {
    sheet = ""
    sheetError = ""
    showPassword = false
    confirmForget = false
    disarmForget.stop()
    passwordField.text = ""
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
    WlrLayershell.namespace: "omamobile-wifi"
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
        if (root.sheet) root.cancelSheet()
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
            text: "Wi-Fi"
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
            spinning: root.scanning
            enabled: root.wifiOn
            onTapped: root.rescan()
          }
        }

        // ---------- The radio switch
        BorderSurface {
          id: switchRow
          anchors.top: header.bottom
          anchors.topMargin: Style.spacing.lg
          anchors.left: parent.left
          anchors.right: parent.right
          height: Math.max(56, Style.space(60))
          radius: Style.cornerRadius
          color: switchTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
            : root.wifiOn ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
            : Style.normalFillFor(root.foreground, Commons.Color.accent)
          borderSpec: Border.controlSpec(root.wifiOn ? "selected" : "normal", root.foreground, Commons.Color.accent)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.xxl + switchRow.borderLeft
            anchors.right: radioSwitch.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Use Wi-Fi"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
          }

          ToggleSwitch {
            id: radioSwitch
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.xl + switchRow.borderRight
            anchors.verticalCenter: parent.verticalCenter
            checked: root.wifiOn
            interactive: false
            foreground: root.foreground
          }

          MouseArea {
            id: switchTouch
            anchors.fill: parent
            enabled: !!root.device && Networking.wifiHardwareEnabled !== false
            cursorShape: Qt.PointingHandCursor
            onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
          }
        }

        // ---------- Errors: the last failure, tap to dismiss
        BorderSurface {
          id: banner
          visible: root.failureText !== ""
          anchors.top: switchRow.bottom
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
            text: root.failureSsid ? root.failureSsid + ": " + root.failureText : root.failureText
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }

          MouseArea {
            anchors.fill: parent
            onClicked: { root.failureText = ""; root.failureSsid = "" }
          }
        }

        // ---------- Off: say so instead of an empty list
        Text {
          visible: !root.wifiOn
          anchors.top: banner.bottom
          anchors.topMargin: Style.spacing.huge
          anchors.left: parent.left
          anchors.right: parent.right
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: root.device ? "Turn on Wi-Fi to see networks in range" : "No Wi-Fi radio"
          color: Readable.secondary(root.foreground, Commons.Color.popups.background)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }

        // ---------- Networks
        ListView {
          id: list
          visible: root.wifiOn
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

          // Pull-to-refresh cue, above the first row while overscrolled.
          header: Item {
            width: list.width
            height: 0
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              y: -height - Style.spacing.lg
              visible: list.contentY < list.originY - Style.space(10)
              textFormat: Text.PlainText
              text: list.contentY < list.originY - list.pullThreshold ? "Release to scan" : "Pull to scan"
              color: Readable.secondary(root.foreground, Commons.Color.popups.background)
              font.family: Style.font.family
              font.pixelSize: Readable.px(Style.font.caption)
            }
          }

          delegate: Item {
            id: entryItem

            required property var modelData
            readonly property var row: modelData
            readonly property bool isHeader: row.kind === "header"
            readonly property bool isEmpty: row.kind === "empty"
            readonly property bool isSaved: row.kind === "saved"
            readonly property bool busy: root.actionKind !== "" && root.actionSsid === row.ssid
            readonly property string failure: root.failureSsid === row.ssid ? root.failureText : ""

            width: list.width
            height: isHeader ? Math.max(32, Style.space(36)) : isEmpty ? root.touchSize : Math.max(56, Style.space(64))

            // Section header
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

            // Network or saved-profile row
            Rectangle {
              visible: !entryItem.isHeader && !entryItem.isEmpty
              anchors.fill: parent
              anchors.topMargin: Style.spacing.xxs
              anchors.bottomMargin: Style.spacing.xxs
              radius: Style.cornerRadius
              color: rowTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
                : entryItem.row.connected ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
                : "transparent"

              Text {
                id: signalGlyph
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.xl
                anchors.verticalCenter: parent.verticalCenter
                width: Style.font.display
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: entryItem.isSaved ? "󰤮" : WifiModel.wifiIcon(entryItem.row.signal)
                color: entryItem.row.connected ? Commons.Color.accent : root.foreground
                opacity: entryItem.isSaved ? 0.5 : 1
                font.family: Style.font.family
                font.pixelSize: Style.font.display
              }

              Column {
                anchors.left: signalGlyph.right
                anchors.leftMargin: Style.spacing.xl
                anchors.right: lockGlyph.left
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xxs

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: entryItem.row.ssid
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: entryItem.row.connected
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: entryItem.isSaved ? (entryItem.failure || "Saved")
                    : WifiModel.rowStatus(entryItem.row, entryItem.busy ? root.actionKind : "", entryItem.failure)
                  color: entryItem.failure ? Commons.Color.urgent : Readable.secondary(root.foreground, Commons.Color.popups.background)
                  font.family: Style.font.family
                  font.pixelSize: Readable.px(Style.font.caption)
                  elide: Text.ElideRight
                }
              }

              Text {
                id: lockGlyph
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.xl
                anchors.verticalCenter: parent.verticalCenter
                width: Style.font.iconLarge
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: entryItem.row.secured ? "󰌾" : ""
                color: Qt.darker(root.foreground, 1.3)
                font.family: Style.font.family
                font.pixelSize: Style.font.iconLarge
              }

              MouseArea {
                id: rowTouch
                anchors.fill: parent
                enabled: !entryItem.isHeader && !entryItem.isEmpty
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
          visible: root.sheet !== ""
          color: Commons.Color.menu.scrim

          MouseArea {
            anchors.fill: parent
            onClicked: root.cancelSheet()
          }
        }

        BorderSurface {
          id: sheetCard
          visible: root.sheet !== ""
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
              text: root.sheetSsid
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
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

            // Password: masked field with show/hide, then Cancel / Connect.
            Item {
              visible: root.sheet === "password"
              width: parent.width
              height: visible ? root.touchSize : 0

              TextField {
                id: passwordField
                anchors.left: parent.left
                anchors.right: reveal.left
                anchors.rightMargin: Style.spacing.lg
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                verticalAlignment: TextInput.AlignVCenter
                font.pixelSize: Style.font.title
                foreground: root.foreground
                placeholderText: "Password"
                placeholderTextColor: Readable.secondary(root.foreground, Readable.flatten(Style.controlFill(activeFocus, hovered || hasCursor, foreground, accent), Commons.Color.popups.background))
                password: !root.showPassword
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase
                onAccepted: root.submitPassword()
                onTextEdited: root.sheetError = ""
                Keys.onEscapePressed: root.cancelSheet()
              }

              GlyphButton {
                id: reveal
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyph: root.showPassword ? "󰈉" : "󰈈"
                onTapped: root.showPassword = !root.showPassword
              }
            }

            Row {
              visible: root.sheet === "password"
              width: parent.width
              height: visible ? root.touchSize : 0
              spacing: Style.spacing.lg
              layoutDirection: Qt.RightToLeft

              SheetButton {
                width: (parent.width - parent.spacing) / 2
                label: "Connect"
                primary: true
                enabled: passwordField.text.length > 0
                onTapped: root.submitPassword()
              }

              SheetButton {
                width: (parent.width - parent.spacing) / 2
                label: "Cancel"
                onTapped: root.cancelSheet()
              }
            }

            // Actions: Disconnect / Forget / Cancel.
            SheetButton {
              visible: root.sheet === "actions" && root.sheetConnected
              width: parent.width
              label: "Disconnect"
              onTapped: root.disconnectSheet()
            }

            SheetButton {
              visible: root.sheet === "actions" && (root.sheetKnown || root.sheetConnected)
              width: parent.width
              label: root.confirmForget ? "Forget " + root.sheetSsid + "?" : "Forget"
              danger: true
              onTapped: root.requestForget()
            }

            SheetButton {
              visible: root.sheet === "actions"
              width: parent.width
              label: "Cancel"
              onTapped: root.cancelSheet()
            }
          }
        }
      }
    }
  }
}
