// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The page behind the Hotspot tile's chevron, like the Wi-Fi picker: the
// hotspot's switch, its network name and password (the pencil edits them),
// a QR code that joins a phone to it, and the "Share VPN" box: devices on
// the hotspot may use the phone's VPN connection as well, while the hotspot
// runs; off unless the box is ticked, and shown only where the hotspot
// backend supports it. Data and actions come from hotspot-panel.sh next to
// this file, which knows the hotspot backends (see its header).
Item {
  id: root

  property bool opened: false
  property color foreground: Commons.Color.popups.text
  // From the tile, so the switch follows a tap at once
  property bool hotspotOn: false

  signal backRequested()
  signal toggleRequested()

  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int pad: Style.spacing.panelPadding
  readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("hotspot-panel.sh")).replace(/^file:\/\//, ""))

  property string ssid: ""
  property string psk: ""
  property string qrPath: ""
  property bool vpnOn: false
  property bool shareOn: false
  property bool preferShare: false
  property bool shareAvailable: true
  property bool allTraffic: false
  property bool allTrafficAvailable: false
  property bool editable: true
  property int clients: 0
  property bool showPassword: false
  property int qrStamp: 0
  property real qrRev: 0
  property bool editing: false
  property bool saving: false
  property string saveError: ""
  property string saveStatus: ""

  function open() { opened = true; showPassword = false; editing = false; saveError = ""; saveStatus = ""; refresh() }

  // Editing the name and password: hotspot-panel.sh set applies them; a
  // running hotspot restarts with them.
  function startEdit() {
    nameField.text = ssid; pwField.text = psk
    saveError = ""; saveStatus = ""; editing = true
    Qt.callLater(function() { nameField.forceActiveFocus() })
  }
  function cancelEdit() { editing = false; saveError = ""; panel.forceActiveFocus() }
  function saveEdit() {
    var n = nameField.text, p = pwField.text
    if (n.length < 1 || n.length > 32) { saveError = "The network name must be 1 to 32 characters."; return }
    if (p.length < 8 || p.length > 63) { saveError = "The password must be 8 to 63 characters."; return }
    saving = true; saveError = ""; saveStatus = "Saving. A running hotspot restarts with the new values."
    setProc.command = ["bash", root.helper, "set", n, p]
    setProc.running = true
  }

  Process {
    id: setProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.saving = false
        var t = String(text).trim()
        if (t.indexOf("error") === 0) {
          root.saveError = t.replace(/^error:\s*/, "")
        } else {
          root.editing = false
          root.showPassword = false
          root.saveStatus = t.replace(/^ok:\s*/, "")
          panel.forceActiveFocus()
        }
        root.refresh()
      }
    }
  }
  function close() { opened = false }
  function refresh() { if (!stateProc.running) stateProc.running = true }
  function snapshot() {
    return JSON.stringify({ opened: opened, hotspot: hotspotOn, ssid: ssid, vpn: vpnOn, share: shareOn, preferShare: preferShare, clients: clients })
  }

  Process {
    id: stateProc
    command: ["bash", root.helper, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var s = JSON.parse(text)
          root.ssid = String(s.ssid || "")
          root.psk = String(s.psk || "")
          root.vpnOn = s.vpn === "on"
          root.shareOn = s.share === "on"
          root.preferShare = s.prefer_share === true
          root.shareAvailable = s.share_available !== false
          root.allTrafficAvailable = s.all_traffic_available === true
          root.allTraffic = s.all_traffic === true
          root.editable = s.editable !== false
          root.clients = Number(s.clients || 0)
          var rev = Number(s.qr_rev || 0)
          if (root.qrPath !== String(s.qr || "") || rev !== root.qrRev) { root.qrPath = String(s.qr || ""); root.qrRev = rev; root.qrStamp++ }
        } catch (e) {}
      }
    }
  }

  Process {
    id: shareProc
    onExited: root.refresh()
  }

  function setShare(on) {
    root.preferShare = on
    if (!on) root.allTraffic = false
    shareProc.command = ["bash", root.helper, "share", on ? "on" : "off"]
    shareProc.running = true
  }
  function setAllTraffic(on) {
    root.allTraffic = on
    shareProc.command = ["bash", root.helper, "alltraffic", on ? "on" : "off"]
    shareProc.running = true
  }

  Timer {
    running: root.opened
    interval: 3000
    repeat: true
    onTriggered: root.refresh()
  }

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  PanelWindow {
    id: window

    visible: root.opened || root.reveal > 0
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-hotspot"
    WlrLayershell.layer: WlrLayer.Top
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
      Keys.onEscapePressed: root.close()

      MouseArea { anchors.fill: parent }

      Item {
        id: body
        anchors.fill: parent
        anchors.topMargin: panel.contentTopInset
        anchors.rightMargin: panel.contentRightInset
        anchors.bottomMargin: panel.contentBottomInset
        anchors.leftMargin: panel.contentLeftInset

        // ---------- Header: back and title
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
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Hotspot"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }
        }

        Flickable {
          anchors.top: header.bottom
          anchors.topMargin: root.pad
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          contentHeight: column.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: column
            width: parent.width
            spacing: Style.spacing.md

            // ---------- The switch
            BorderSurface {
              width: parent.width
              height: Math.max(root.touchSize, switchText.implicitHeight + Style.spacing.lg * 2)
              radius: Style.cornerRadius
              color: root.hotspotOn ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha) : Style.normalFillFor(root.foreground, Commons.Color.accent)
              borderSpec: Border.controlSpec(root.hotspotOn ? "selected" : "normal", root.foreground, Commons.Color.accent)

              Text {
                id: switchGlyph
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "󰀂"
                color: root.hotspotOn ? Commons.Color.accent : root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
              }

              Column {
                id: switchText
                anchors.left: switchGlyph.right
                anchors.leftMargin: Style.spacing.lg
                anchors.right: switchMark.left
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xs
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.hotspotOn ? "On" : "Off"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  wrapMode: Text.Wrap
                  text: root.hotspotOn
                    ? (root.clients === 1 ? "1 device connected" : root.clients + " devices connected") + ". Shares mobile data only."
                    : "Shares the phone's mobile data over Wi-Fi."
                  color: root.foreground
                  opacity: 0.7
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }

              Text {
                id: switchMark
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.hotspotOn ? "󰔡" : "󰨙"
                color: root.hotspotOn ? Commons.Color.accent : root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
              }

              MouseArea {
                anchors.fill: parent
                onClicked: root.toggleRequested()
              }
            }

            // ---------- Name and password; the pencil makes them editable
            BorderSurface {
              width: parent.width
              height: credentials.implicitHeight + Style.spacing.lg * 2
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.foreground, Commons.Color.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, Commons.Color.accent)

              Column {
                id: credentials
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.spacing.lg
                spacing: Style.spacing.sm

                Item {
                  width: parent.width
                  height: root.touchSize
                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: "Network name"
                    color: root.foreground
                    opacity: 0.7
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }
                  GlyphButton {
                    visible: root.editable
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: root.editing ? "󰅖" : "󰏫"
                    foreground: root.foreground
                    onTapped: root.editing ? root.cancelEdit() : root.startEdit()
                  }
                }
                Text {
                  visible: !root.editing
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.ssid !== "" ? root.ssid : "–"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  elide: Text.ElideRight
                }
                TextField {
                  id: nameField
                  visible: root.editing
                  width: parent.width
                  height: root.touchSize
                  verticalAlignment: TextInput.AlignVCenter
                  font.pixelSize: Style.font.subtitle
                  foreground: root.foreground
                  placeholderText: "Network name"
                  inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                  onTextEdited: root.saveError = ""
                  Keys.onEscapePressed: root.cancelEdit()
                }
                Item { width: 1; height: Style.spacing.sm }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "Password"
                  color: root.foreground
                  opacity: 0.7
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                Item {
                  width: parent.width
                  height: root.touchSize
                  Text {
                    id: pwText
                    visible: !root.editing
                    anchors.left: parent.left
                    anchors.right: pwEye.left
                    anchors.rightMargin: Style.spacing.md
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: root.psk === "" ? "–" : (root.showPassword ? root.psk : "••••••••••••")
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  TextField {
                    id: pwField
                    visible: root.editing
                    anchors.left: parent.left
                    anchors.right: pwEye.left
                    anchors.rightMargin: Style.spacing.md
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: Style.font.subtitle
                    foreground: root.foreground
                    placeholderText: "Password, 8 to 63 characters"
                    password: !root.showPassword
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase
                    onAccepted: root.saveEdit()
                    onTextEdited: root.saveError = ""
                    Keys.onEscapePressed: root.cancelEdit()
                  }
                  GlyphButton {
                    id: pwEye
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: root.showPassword ? "󰈈" : "󰈉"
                    foreground: root.foreground
                    onTapped: root.showPassword = !root.showPassword
                  }
                }
                Text {
                  visible: root.saveError !== "" || root.saveStatus !== ""
                  width: parent.width
                  textFormat: Text.PlainText
                  wrapMode: Text.Wrap
                  text: root.saveError !== "" ? root.saveError : root.saveStatus
                  color: root.saveError !== "" ? Commons.Color.urgent : root.foreground
                  opacity: root.saveError !== "" ? 1 : 0.7
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                Row {
                  visible: root.editing
                  width: parent.width
                  height: visible ? root.touchSize : 0
                  spacing: Style.spacing.md
                  SheetButton {
                    width: (parent.width - Style.spacing.md) / 2
                    label: "Cancel"
                    foreground: root.foreground
                    onTapped: root.cancelEdit()
                  }
                  SheetButton {
                    width: (parent.width - Style.spacing.md) / 2
                    label: root.saving ? "Saving…" : "Save"
                    primary: true
                    enabled: !root.saving
                    foreground: root.foreground
                    onTapped: root.saveEdit()
                  }
                }
              }
            }

            // ---------- QR code: scan to join
            BorderSurface {
              width: parent.width
              height: qrColumn.implicitHeight + Style.spacing.lg * 2
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.foreground, Commons.Color.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, Commons.Color.accent)
              visible: root.qrPath !== ""

              Column {
                id: qrColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.spacing.lg
                spacing: Style.spacing.sm

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "Scan to join"
                  color: root.foreground
                  opacity: 0.7
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: Math.min(parent.width, Style.space(220))
                  height: width
                  radius: Style.cornerRadius
                  color: "white"
                  Image {
                    anchors.fill: parent
                    anchors.margins: Style.spacing.md
                    source: root.qrPath !== "" ? "file://" + root.qrPath + "?" + root.qrStamp : ""
                    cache: false
                    smooth: false
                    fillMode: Image.PreserveAspectFit
                  }
                }
              }
            }

            // ---------- Share VPN (only where the backend can)
            BorderSurface {
              id: shareRow
              visible: root.shareAvailable
              width: parent.width
              height: Math.max(root.touchSize, shareText.implicitHeight + Style.spacing.lg * 2)
              radius: Style.cornerRadius
              color: shareTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
                : root.preferShare ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
                : Style.normalFillFor(root.foreground, Commons.Color.accent)
              borderSpec: Border.controlSpec(root.preferShare ? "selected" : "normal", root.foreground, Commons.Color.accent)

              Text {
                id: shareMark
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.preferShare ? "󰄵" : "󰄱"
                color: root.preferShare ? Commons.Color.accent : root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
              }

              Column {
                id: shareText
                anchors.left: shareMark.right
                anchors.leftMargin: Style.spacing.lg
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xs
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "Share VPN"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  wrapMode: Text.Wrap
                  text: {
                    if (!root.preferShare) return "Let devices on this hotspot reach the devices behind your VPN."
                    if (!root.hotspotOn) return "Applies once the hotspot is on."
                    if (!root.vpnOn) return "Waiting for the VPN to connect."
                    if (root.shareOn) return "On. Devices on this hotspot can reach the devices behind your VPN."
                    return "Turning on…"
                  }
                  color: root.foreground
                  opacity: 0.7
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }

              MouseArea {
                id: shareTouch
                anchors.fill: parent
                onClicked: root.setShare(!root.preferShare)
              }
            }

            // ---------- Route all traffic through the VPN (needs Share VPN)
            BorderSurface {
              id: allRow
              visible: root.shareAvailable && root.allTrafficAvailable
              width: parent.width
              height: Math.max(root.touchSize, allText.implicitHeight + Style.spacing.lg * 2)
              radius: Style.cornerRadius
              opacity: root.preferShare ? 1 : 0.5
              color: allTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
                : root.allTraffic ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
                : Style.normalFillFor(root.foreground, Commons.Color.accent)
              borderSpec: Border.controlSpec(root.allTraffic ? "selected" : "normal", root.foreground, Commons.Color.accent)

              Text {
                id: allMark
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.allTraffic ? "󰄵" : "󰄱"
                color: root.allTraffic ? Commons.Color.accent : root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
              }

              Column {
                id: allText
                anchors.left: allMark.right
                anchors.leftMargin: Style.spacing.lg
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xs
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "Route all traffic through the VPN"
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  wrapMode: Text.Wrap
                  text: {
                    if (!root.preferShare) return "Turn on Share VPN first."
                    if (!root.allTraffic) return "Also send their internet traffic through the VPN. They then appear online with the VPN's address."
                    if (!root.vpnOn) return "Waiting for the VPN to connect."
                    return "On. Their internet traffic goes through the VPN."
                  }
                  color: root.foreground
                  opacity: 0.7
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }

              MouseArea {
                id: allTouch
                anchors.fill: parent
                enabled: root.preferShare
                onClicked: root.setAllTraffic(!root.allTraffic)
              }
            }
          }
        }
      }
    }
  }
}
