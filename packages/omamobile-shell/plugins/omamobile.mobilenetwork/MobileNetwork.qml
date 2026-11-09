// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "MobileNetworkModel.js" as Model
import "Readable.js" as Readable

// The Mobile network page: the carrier, signal and registration, the
// Modem switch (on or off at boot), the mobile data and data roaming
// switches, the APN in use with a field to type one,
// the attach APN (the one the modem registers with) under Advanced, and
// whether the SIM's PIN lock is on. Opened from Setup > Mobile network
// in Omarchy's menu, the Mobile data tile's chevron, or
// `omarchy-shell shell summon omamobile.mobilenetwork '{}'`.
//
// Everything goes through omamobile-mobile-network (bin/): `status` while
// the page is open (every 3 s), `data on|off` (omamobile-sit data),
// `roaming on|off`, `apn auto|APN` and `attach-apn auto|APN`
// (omamobile-sit-config under pkexec, and `modem on|off` through
// omamobile-modem-switch under pkexec;
// polkit: the active user). An APN applies when the modem service next
// starts, which needs a restart of the phone: the page says so and offers
// one. Without the modem stack (the release image has none yet) the page
// says "No modem" and nothing else.
//
// The window sits on the top layer with normal exclusion, like the update
// sheet, so the APN field stays above the on-screen keyboard.
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  property bool opened: false
  property var status: null
  property string apnMessage: ""
  property bool apnError: false
  property bool apnSaved: false
  property bool busy: false
  property bool advancedOpen: false
  // Switches flip at once and settle on the next status read.
  property var optimistic: ({})

  readonly property var page: Model.view(status)
  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int pad: Style.spacing.panelPadding
  readonly property color foreground: Commons.Color.popups.text
  readonly property string pluginId: (manifest && manifest.id) || "omamobile.mobilenetwork"

  // ---------------------------------------------------------------- host API

  function open(payloadJson) {
    opened = true
    apnMessage = ""
    apnError = false
    apnSaved = false
    advancedOpen = false
    optimistic = ({})
    refresh()
  }

  function close() {
    if (!opened) return
    opened = false
    apnField.focus = false
    attachField.focus = false
    Quickshell.execDetached(["qs", "ipc", "-p", Quickshell.shellDir, "call", "shell", "call",
                             "omamobile.keyboard", "hideKeyboard", ""])
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
  }

  // `shell call omamobile.mobilenetwork snapshot ''`: what the page shows
  // (no numbers or SIM identifiers exist in it).
  function snapshot() {
    return JSON.stringify({ opened: opened, state: page.state, title: page.title,
                            data: page.dataText, apnSource: page.apnSource || "" })
  }

  // ---------------------------------------------------------------- actions

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function value(name, actual) {
    return optimistic[name] !== undefined ? optimistic[name] : actual
  }

  function setOptimistic(name, on) {
    var next = Object.assign({}, optimistic)
    next[name] = on
    optimistic = next
  }

  function setData(on) {
    if (actionProc.running || !page.dataAvailable) return
    setOptimistic("data", on)
    actionProc.command = Model.dataArgv(on)
    actionProc.running = true
  }

  // The modem stack at boot (omamobile-modem-switch through pkexec): off
  // from the next boot, on now if this boot's modem never started.
  function setModem(on) {
    if (actionProc.running) return
    setOptimistic("modem", on)
    actionProc.command = Model.modemArgv(on)
    actionProc.running = true
  }

  function setRoaming(on) {
    if (actionProc.running) return
    setOptimistic("roaming", on)
    actionProc.command = Model.roamingArgv(on)
    actionProc.running = true
  }

  // attach: the attach APN rather than the internet APN.
  function saveApn(text, attach) {
    var v = Model.apnValue(text)
    if (v === null) {
      apnError = true
      apnMessage = "That isn't an APN: letters, digits, dots and dashes only."
      return
    }
    if (actionProc.running) return
    apnError = false
    apnMessage = "Saving..."
    apnField.focus = false
    attachField.focus = false
    actionProc.apn = v
    actionProc.attach = attach === true
    actionProc.command = attach === true ? Model.attachArgv(v) : Model.apnArgv(v)
    actionProc.running = true
  }

  // ---------------------------------------------------------------- processes

  Process {
    id: statusProc
    command: Model.STATUS_ARGV
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: {
      var parsed = Model.parseJson(statusOut.text)
      root.status = parsed || { installed: false }
      root.optimistic = ({})
    }
  }

  Process {
    id: actionProc
    property string apn: ""
    property bool attach: false
    onExited: function(exitCode) {
      if (actionProc.apn !== "") {
        root.apnError = exitCode !== 0
        root.apnSaved = exitCode === 0
        root.apnMessage = exitCode === 0 ? Model.apnSavedText(actionProc.apn, actionProc.attach) : "Not saved (permission refused or the value was rejected)."
        if (exitCode === 0) { apnField.text = ""; attachField.text = "" }
        actionProc.apn = ""
      }
      root.refresh()
    }
  }

  Timer {
    interval: 3000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  // ---------------------------------------------------------------- surface

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  PanelWindow {
    id: sheetWindow

    visible: root.opened || root.reveal > 0
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-mobilenetwork"
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
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      objectName: "mobileNetworkCard"

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
      Keys.onEscapePressed: root.dismiss()

      MouseArea { anchors.fill: parent }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Item {
          id: headerRow
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.touchSize

          Text {
            anchors.left: parent.left
            anchors.right: closeButton.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Mobile network"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          GlyphTap {
            id: closeButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            glyph: "󰅖"
            onTapped: root.dismiss()
          }
        }

        Flickable {
          id: flick
          anchors.top: headerRow.bottom
          anchors.topMargin: Style.spacing.lg
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          contentHeight: column.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: column
            width: flick.width
            spacing: Style.spacing.xl

            // ---------- The carrier and the registration
            Row {
              width: parent.width
              spacing: Style.spacing.lg

              Text {
                id: bigGlyph
                textFormat: Text.PlainText
                text: root.page.state === "ready" ? ["󰞃", "󰢼", "󰢽", "󰢾", "󰣺"][Math.max(0, root.page.signalBars)] : "󰞃"
                color: root.page.state === "ready" ? Commons.Color.accent : root.foreground
                opacity: root.page.state === "ready" ? 1 : 0.6
                font.family: Style.font.family
                font.pixelSize: Style.font.iconLarge * 1.5
              }

              Column {
                width: parent.width - bigGlyph.width - parent.spacing
                anchors.verticalCenter: bigGlyph.verticalCenter
                Text {
                  width: parent.width
                  objectName: "mobileNetworkTitle"
                  textFormat: Text.PlainText
                  text: root.page.title
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
                  text: root.page.body || ""
                  color: root.foreground
                  opacity: 0.8
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  wrapMode: Text.Wrap
                }
              }
            }

            InfoRow {
              width: parent.width
              visible: root.page.state === "ready"
              glyph: "󰣺"
              text: "Signal: " + (root.page.signal || "")
            }

            // ---------- Switches
            SettingRow {
              objectName: "setting-modem"
              visible: (root.page.state === "ready" || root.page.state === "off")
                       && !!root.page.modem && root.page.modem.shown === true
              title: "Modem"
              note: root.page.modem ? (root.page.modem.note || "") : ""
              checked: root.value("modem", !!root.page.modem && root.page.modem.on === true)
              onToggled: root.setModem(!checked)
            }

            SheetAction {
              width: parent.width
              visible: !!root.page.modem && root.page.modem.restart === true
              label: "Restart now"
              onTapped: Quickshell.execDetached(Model.REBOOT_ARGV)
            }

            SettingRow {
              objectName: "setting-mobileData"
              visible: root.page.state === "ready"
              enabled: root.page.dataAvailable === true
              title: "Mobile data"
              note: root.page.dataText || ""
              checked: root.value("data", root.page.dataOn === true)
              onToggled: root.setData(!checked)
            }

            SettingRow {
              objectName: "setting-roaming"
              visible: root.page.state === "ready"
              title: "Data roaming"
              note: root.page.roamingText || ""
              checked: root.value("roaming", root.page.roamingAllowed === true)
              onToggled: root.setRoaming(!checked)
            }

            // ---------- APN
            SectionLabel {
              visible: root.page.state === "ready"
              text: "Access point (APN)"
            }

            Text {
              width: parent.width
              visible: root.page.state === "ready"
              textFormat: Text.PlainText
              text: root.page.apnInUse
                ? root.page.apnInUse + (root.page.apnSource ? "  ·  " + root.page.apnSource : "")
                : (root.page.apnSource || "Not chosen yet")
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }

            Item {
              width: parent.width
              height: root.touchSize
              visible: root.page.state === "ready"

              TextField {
                id: apnField
                anchors.left: parent.left
                anchors.right: saveButton.left
                anchors.rightMargin: Style.spacing.lg
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                verticalAlignment: TextInput.AlignVCenter
                font.pixelSize: Style.font.body
                foreground: root.foreground
                placeholderText: root.page.apnConfigured ? "Typed: " + root.page.apnConfigured : "Automatic (from the SIM)"
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase | Qt.ImhUrlCharactersOnly
                onAccepted: root.saveApn(text)
                onTextEdited: { root.apnMessage = ""; root.apnError = false }
              }

              SheetAction {
                id: saveButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(96)
                label: "Save"
                primary: true
                enabled: apnField.text.trim().length > 0
                onTapped: root.saveApn(apnField.text)
              }
            }

            SheetAction {
              width: parent.width
              visible: root.page.state === "ready" && root.page.apnConfigured !== ""
              label: "Use the APN from the SIM"
              onTapped: root.saveApn("auto")
            }

            Text {
              width: parent.width
              visible: text !== ""
              textFormat: Text.PlainText
              text: root.apnMessage
              color: root.apnError ? Commons.Color.urgent : root.foreground
              font.family: Style.font.family
              font.pixelSize: Readable.px(Style.font.caption)
              wrapMode: Text.Wrap
            }

            SheetAction {
              width: parent.width
              visible: root.apnSaved
              label: "Restart now"
              onTapped: Quickshell.execDetached(Model.REBOOT_ARGV)
            }

            // ---------- Advanced: the attach APN
            SettingRow {
              objectName: "setting-advanced"
              visible: root.page.state === "ready"
              title: "Advanced"
              note: "The APN the modem registers with"
              checked: root.advancedOpen
              onToggled: root.advancedOpen = !root.advancedOpen
            }

            Text {
              width: parent.width
              visible: root.page.state === "ready" && root.advancedOpen
              textFormat: Text.PlainText
              text: "Attach APN: " + (root.page.attachText || "")
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }

            Item {
              width: parent.width
              height: visible ? root.touchSize : 0
              visible: root.page.state === "ready" && root.advancedOpen

              TextField {
                id: attachField
                anchors.left: parent.left
                anchors.right: attachSave.left
                anchors.rightMargin: Style.spacing.lg
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                verticalAlignment: TextInput.AlignVCenter
                font.pixelSize: Style.font.body
                foreground: root.foreground
                placeholderText: root.page.attachConfigured ? "Typed: " + root.page.attachConfigured : "Automatic (from the SIM)"
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase | Qt.ImhUrlCharactersOnly
                onAccepted: root.saveApn(text, true)
                onTextEdited: { root.apnMessage = ""; root.apnError = false }
              }

              SheetAction {
                id: attachSave
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(96)
                label: "Save"
                primary: true
                enabled: attachField.text.trim().length > 0
                onTapped: root.saveApn(attachField.text, true)
              }
            }

            SheetAction {
              width: parent.width
              visible: root.page.state === "ready" && root.advancedOpen && root.page.attachConfigured !== ""
              label: "Use the attach APN from the SIM"
              onTapped: root.saveApn("auto", true)
            }

            // ---------- SIM
            InfoRow {
              width: parent.width
              visible: root.page.state === "ready"
              glyph: "󰌾"
              text: "SIM PIN lock: " + (root.page.pinText || "")
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- pieces

  // Inline components have their own scope: no `root` in here.
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

  component SettingRow: Item {
    id: settingItem
    property string title: ""
    property string note: ""
    property bool checked: false
    signal toggled()
    width: parent ? parent.width : 0
    height: visible ? Math.max(Math.max(44, Style.space(48)), settingText.implicitHeight + Style.spacing.md * 2) : 0
    opacity: enabled ? 1 : 0.55
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
      enabled: settingItem.enabled
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

  component GlyphTap: Item {
    id: glyphItem
    property string glyph: ""
    property color foreground: Commons.Color.popups.text
    readonly property int touchSize: Math.max(44, Style.space(48))
    signal tapped()
    width: glyphItem.touchSize
    height: glyphItem.touchSize

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: glyphTouch.pressed ? Style.pressedFillFor(glyphItem.foreground, Commons.Color.accent) : "transparent"
    }

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

  component SheetAction: BorderSurface {
    id: actionItem
    property string label: ""
    property bool primary: false
    property color foreground: Commons.Color.popups.text
    readonly property int touchSize: Math.max(44, Style.space(48))
    signal tapped()
    height: visible ? actionItem.touchSize : 0
    radius: Style.cornerRadius
    opacity: enabled ? 1 : 0.45
    color: actionTouch.pressed ? Style.pressedFillFor(actionItem.foreground, Commons.Color.accent)
      : actionItem.primary ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
      : Style.normalFillFor(actionItem.foreground, Commons.Color.accent)
    borderSpec: Border.controlSpec(actionItem.primary ? "selected" : "normal", actionItem.foreground, Commons.Color.accent)

    Text {
      anchors.centerIn: parent
      width: parent.width - Style.spacing.lg * 2
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: actionItem.label
      color: actionItem.primary ? Commons.Color.accent : actionItem.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      font.bold: true
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

    Text {
      width: infoItem.width - infoGlyph.width - infoItem.spacing
      anchors.verticalCenter: infoGlyph.verticalCenter
      textFormat: Text.PlainText
      text: infoItem.text
      color: infoItem.urgent ? Commons.Color.urgent : infoItem.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
    }
  }
}
