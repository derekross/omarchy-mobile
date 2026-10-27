// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "UpdateModel.js" as UpdateModel
import "Readable.js" as Readable

// The phone's update sheet, in place of Omarchy's terminal update (gum and
// the ASCII logo don't fit 480 px with the keyboard up). Opened from the
// "Update available" toast, the menu's Update > Omarchy, or
// `omarchy-shell shell summon omamobile.update '{}'`.
//
// Pages: overview (what's new, battery, phone patches, Update), auth (the
// PIN or password for sudo), progress (the current step, with the output
// under Details), result (updated / restart needed / patches failed /
// stopped, with the log's path). Everything runs through omamobile-update
// (package omamobile-omarchy): `check --json` for the overview, `start` for
// the run (the PIN goes to its stdin, never argv or a file), and the events
// file it writes, followed with tail -F, for progress. The run is a systemd
// user unit, so it outlives the shell restart at the end of every update;
// the new shell's instance of this plugin finds it through `status --json`
// and shows its progress or its result.
//
// The window sits on the top layer with normal exclusion, like the Wi-Fi
// picker, so it fits between the status bar and the on-screen keyboard:
// the PIN field and the buttons stay above the keys.
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string page: "overview"   // overview | auth | progress | result
  property bool checking: false
  property var info: null
  property var lastResult: null
  property string stepText: ""
  property string progressText: ""
  property var detailLines: []
  property bool detailsOpen: false
  property string authError: ""
  property bool submitting: false
  property bool digits: true
  property string eventsPath: ""
  property bool updateAvailable: false
  property string availableText: ""

  readonly property var summary: UpdateModel.overview(info)
  readonly property var outcome: UpdateModel.resultView(lastResult)
  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int pad: Style.spacing.panelPadding
  readonly property color foreground: Commons.Color.popups.text

  // ---------------------------------------------------------------- host API

  // The payload is ignored: every way in starts on the overview, or on the
  // run's progress or result when there is one.
  function open(payloadJson) {
    opened = true
    authError = ""
    if (page === "progress" || page === "result") return
    page = "overview"
    statusProc.openAfter = true
    refreshStatus()
    recheck()
  }

  function close() {
    if (!opened) return
    opened = false
    pinField.text = ""
    if (page === "auth") page = "overview"
    if (page === "result") {
      Quickshell.execDetached(UpdateModel.ACK_ARGV)
      page = "overview"
    }
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omamobile.update")
    else root.close()
  }

  // `shell call omamobile.update snapshot ''`: page and progress, never the PIN.
  function snapshot() {
    return JSON.stringify({ opened: opened, page: page, step: stepText, progress: progressText,
                            available: updateAvailable, result: lastResult ? lastResult.result : null })
  }

  // ---------------------------------------------------------------- actions

  function recheck() {
    if (checkProc.running) return
    checking = true
    checkProc.running = true
  }

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }

  function askPin() {
    authError = ""
    pinField.text = ""
    digits = !info || info.credential !== "password"
    page = "auth"
    Qt.callLater(function() { pinField.forceActiveFocus() })
  }

  function submitPin() {
    if (submitting || pinField.text.length === 0) return
    submitting = true
    authError = ""
    startProc.secret = pinField.text
    pinField.text = ""
    startProc.running = true
  }

  function followEvents(path) {
    eventsPath = path
    detailLines = []
    stepText = "Starting"
    progressText = ""
    page = "progress"
    tailProc.running = false
    Qt.callLater(function() { tailProc.running = true })
  }

  function handleEvent(line) {
    var ev = UpdateModel.parseEvent(line)
    if (!ev) return
    if (ev.kind === "step") {
      stepText = ev.text
      progressText = ""
      detailLines = UpdateModel.appendDetail(detailLines, "== " + ev.text)
    } else if (ev.kind === "line") {
      progressText = ev.text
      detailLines = UpdateModel.appendDetail(detailLines, ev.text)
    } else if (ev.kind === "progress") {
      progressText = ev.text
    } else if (ev.kind === "result") {
      lastResult = ev.result
      page = "result"
      tailProc.running = false
      updateAvailable = false
      if (!opened && root.shell && typeof root.shell.summon === "function")
        root.shell.summon((root.manifest && root.manifest.id) || "omamobile.update", "{}")
    }
  }

  // ---------------------------------------------------------------- processes

  Process {
    id: checkProc
    command: UpdateModel.CHECK_ARGV
    stdout: StdioCollector { id: checkOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.checking = false
      var parsed = UpdateModel.parseJson(checkOut.text)
      if (parsed) root.info = parsed
      else root.info = { ok: false, blockers: ["omamobile-update is not installed or failed (exit " + exitCode + ")"], update_count: 0 }
    }
  }

  Process {
    id: statusProc
    property bool openAfter: false
    command: UpdateModel.STATUS_ARGV
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: {
      var st = UpdateModel.parseJson(statusOut.text)
      var recent = false
      if (!st) return
      if (st.running) {
        root.followEvents(st.events)
        if (!root.opened && root.shell && typeof root.shell.summon === "function")
          root.shell.summon((root.manifest && root.manifest.id) || "omamobile.update", "{}")
        return
      }
      if (st.unseen && st.last && st.last.finished) {
        recent = Date.now() - Date.parse(st.last.finished) < 30 * 60 * 1000
        if (recent || statusProc.openAfter) {
          root.lastResult = st.last
          root.page = "result"
          if (!root.opened && root.shell && typeof root.shell.summon === "function")
            root.shell.summon((root.manifest && root.manifest.id) || "omamobile.update", "{}")
        }
      }
      statusProc.openAfter = false
    }
  }

  Process {
    id: startProc
    property string secret: ""
    command: UpdateModel.START_ARGV
    stdinEnabled: true
    stdout: StdioCollector { id: startOut; waitForEnd: true }
    onStarted: {
      startProc.write(startProc.secret + "\n")
      startProc.secret = ""
    }
    onExited: function(exitCode) {
      var how = UpdateModel.startOutcome(exitCode)
      root.submitting = false
      startProc.secret = ""
      if (how === "started" || how === "running") {
        root.refreshStatus()
      } else if (how === "auth-failed") {
        root.authError = root.digits ? "Wrong PIN. Try again." : "Wrong password. Try again."
        Qt.callLater(function() { pinField.forceActiveFocus() })
      } else {
        root.refreshStatus()
        root.page = "overview"
        root.recheck()
      }
    }
  }

  Process {
    id: tailProc
    command: ["tail", "-n", "+1", "-F", root.eventsPath]
    stdout: SplitParser { onRead: function(line) { root.handleEvent(line) } }
  }

  // An update available: one toast per release (omamobile-update keeps
  // track), checked a while after login and every six hours.
  Process {
    id: notifyProc
    command: UpdateModel.NOTIFY_ARGV
    stdout: SplitParser {
      onRead: function(line) {
        var text = String(line)
        if (text.indexOf("available") === 0) {
          root.updateAvailable = true
          root.availableText = text.replace(/^available( \(already notified\))?: /, "")
        } else if (text === "up to date") {
          root.updateAvailable = false
        }
      }
    }
  }

  Timer {
    interval: 21600000
    running: true
    repeat: true
    onTriggered: if (!notifyProc.running) notifyProc.running = true
  }

  Timer {
    interval: 120000
    running: true
    onTriggered: if (!notifyProc.running) notifyProc.running = true
  }

  // Omarchy's own update calls `omarchy-shell omarchy.system-update
  // refresh|clear` at its end; the phone bar has no Omarchy update widget, so
  // this sheet answers.
  IpcHandler {
    target: "omarchy.system-update"

    function refresh(): void {
      if (!notifyProc.running) notifyProc.running = true
    }

    function clear(): void {
      root.updateAvailable = false
    }
  }

  Component.onCompleted: refreshStatus()

  // ---------------------------------------------------------------- surface

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  PanelWindow {
    id: sheetWindow

    visible: root.opened || root.reveal > 0
    anchors { top: true; bottom: true; left: true; right: true }
    // Normal: between the status bar and the on-screen keyboard.
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-update"
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
      onClicked: if (root.page !== "auth") root.dismiss()
    }

    BorderSurface {
      id: card
      objectName: "updateCard"

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
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // ---------- Header: title and close
        Item {
          id: headerRow
          objectName: "updateHeader"
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.touchSize

          Text {
            anchors.left: parent.left
            anchors.right: closeButton.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Omarchy update"
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

        // ---------- Overview
        Flickable {
          id: overviewFlick
          visible: root.page === "overview"
          anchors.top: headerRow.bottom
          anchors.topMargin: Style.spacing.lg
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: overviewButtons.top
          anchors.bottomMargin: Style.spacing.lg
          contentHeight: overviewColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: overviewColumn
            width: overviewFlick.width
            spacing: Style.spacing.xl

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.checking && !root.info ? "Checking for updates..." : root.summary.title
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
              text: root.checking ? "Asking the repositories (this takes a few seconds)." : root.summary.body
              color: root.foreground
              opacity: 0.8
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }

            SheetAction {
              width: parent.width
              visible: !!root.info && !!root.info.omarchy_update
              label: "What's new in Omarchy"
              onTapped: {
                Quickshell.execDetached(["omamobile-launch", "url", root.info.release_notes])
                root.dismiss()
              }
            }

            InfoRow {
              width: parent.width
              glyph: root.info && root.info.battery && root.info.battery.charging ? "󰂄" : "󰁹"
              text: "Battery: " + UpdateModel.batteryText(root.info) +
                (root.info ? " (updates need " + root.info.min_battery + "% or the charger)" : "")
              urgent: !!root.info && root.info.battery_ok === false
            }

            InfoRow {
              width: parent.width
              glyph: "󰌾"
              text: UpdateModel.patchesText(root.info ? root.info.patches : null)
              urgent: !!root.info && !!root.info.patches && root.info.patches.result === "failed"
            }

            Repeater {
              model: root.summary.blockers
              delegate: InfoRow {
                required property var modelData
                width: parent ? parent.width : 0
                glyph: "󰀦"
                text: String(modelData)
                urgent: true
              }
            }

            // The one thing to know before starting: body size, full
            // strength and a warning glyph, like the rows above it.
            InfoRow {
              width: parent.width
              visible: root.summary.canUpdate
              glyph: "󰀦"
              text: "The update can't be stopped once it starts. Keep the phone on; the shell restarts at the end."
              foreground: root.foreground
            }
          }
        }

        Row {
          id: overviewButtons
          visible: root.page === "overview"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.touchSize
          spacing: Style.spacing.lg
          layoutDirection: Qt.RightToLeft

          SheetAction {
            width: (parent.width - parent.spacing) / 2
            label: "Update"
            primary: true
            enabled: root.summary.canUpdate && !root.checking
            onTapped: root.askPin()
          }

          SheetAction {
            width: (parent.width - parent.spacing) / 2
            label: root.checking ? "Checking..." : "Check again"
            enabled: !root.checking
            onTapped: root.recheck()
          }
        }

        // ---------- Auth: the PIN or password, above the keyboard
        Column {
          id: authColumn
          visible: root.page === "auth"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.spacing.xl

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.digits ? "Enter your PIN to update" : "Enter your password to update"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            wrapMode: Text.Wrap
          }

          Text {
            width: parent.width
            visible: text !== ""
            textFormat: Text.PlainText
            text: root.submitting ? "Checking..." : root.authError
            color: root.submitting ? root.foreground : Commons.Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }

          Item {
            width: parent.width
            height: root.touchSize

            TextField {
              id: pinField
              anchors.left: parent.left
              anchors.right: modeSwitch.left
              anchors.rightMargin: Style.spacing.lg
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              verticalAlignment: TextInput.AlignVCenter
              font.pixelSize: Style.font.title
              foreground: root.foreground
              placeholderText: root.digits ? "PIN" : "Password"
              password: true
              enabled: !root.submitting
              inputMethodHints: root.digits
                ? (Qt.ImhDigitsOnly | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText)
                : (Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase)
              onAccepted: root.submitPin()
              onTextEdited: root.authError = ""
              Keys.onEscapePressed: root.page = "overview"
            }

            SheetAction {
              id: modeSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: root.touchSize + Style.space(16)
              label: root.digits ? "ABC" : "123"
              onTapped: {
                root.digits = !root.digits
                pinField.focus = false
                Qt.callLater(function() { pinField.forceActiveFocus() })
              }
            }
          }

          Row {
            width: parent.width
            height: root.touchSize
            spacing: Style.spacing.lg
            layoutDirection: Qt.RightToLeft

            SheetAction {
              width: (parent.width - parent.spacing) / 2
              label: "Update"
              primary: true
              enabled: pinField.text.length > 0 && !root.submitting
              onTapped: root.submitPin()
            }

            SheetAction {
              width: (parent.width - parent.spacing) / 2
              label: "Cancel"
              enabled: !root.submitting
              onTapped: {
                pinField.text = ""
                root.page = "overview"
              }
            }
          }
        }

        // ---------- Progress
        Column {
          id: progressColumn
          visible: root.page === "progress"
          anchors.top: headerRow.bottom
          anchors.topMargin: Style.spacing.xl
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.spacing.lg

          Row {
            width: parent.width
            spacing: Style.spacing.lg

            Text {
              id: spinner
              textFormat: Text.PlainText
              text: "󰑐"
              color: Commons.Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.iconLarge
              RotationAnimator on rotation {
                running: root.page === "progress" && root.opened
                from: 0
                to: 360
                duration: 1200
                loops: Animation.Infinite
              }
            }

            Text {
              width: parent.width - spinner.width - parent.spacing
              anchors.verticalCenter: spinner.verticalCenter
              textFormat: Text.PlainText
              text: root.stepText
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
              wrapMode: Text.Wrap
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.progressText
            color: root.foreground
            opacity: 0.75
            font.family: Style.font.family
            font.pixelSize: Readable.px(Style.font.caption)
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "You can close this; the update keeps running and this sheet comes back with the result."
            color: root.foreground
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Readable.px(Style.font.caption)
            wrapMode: Text.Wrap
          }
        }

        // ---------- Result
        Flickable {
          id: resultFlick
          visible: root.page === "result"
          anchors.top: headerRow.bottom
          anchors.topMargin: Style.spacing.lg
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: detailsBox.visible ? detailsBox.top : resultButtons.top
          anchors.bottomMargin: Style.spacing.lg
          contentHeight: resultColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: resultColumn
            width: resultFlick.width
            spacing: Style.spacing.xl

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.outcome.title
              color: root.outcome.tone === "bad" ? Commons.Color.urgent : root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              wrapMode: Text.Wrap
            }

            Text {
              width: parent.width
              visible: text !== ""
              textFormat: Text.PlainText
              text: root.outcome.body
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }

            InfoRow {
              width: parent.width
              visible: !!root.outcome.patches
              glyph: "󰌾"
              text: root.outcome.patches || ""
              urgent: !!root.lastResult && !!root.lastResult.patches && root.lastResult.patches.result === "failed"
            }

            Repeater {
              model: root.outcome.held || []
              delegate: InfoRow {
                required property var modelData
                width: parent ? parent.width : 0
                glyph: "󰏤"
                text: "Held for review (boot-related on a desktop): migration " + String(modelData)
              }
            }

            Repeater {
              model: root.outcome.warnings || []
              delegate: InfoRow {
                required property var modelData
                width: parent ? parent.width : 0
                glyph: "󰀦"
                text: String(modelData)
                urgent: true
              }
            }

            TextEdit {
              width: parent.width
              visible: root.outcome.log !== ""
              readOnly: true
              selectByMouse: true
              textFormat: TextEdit.PlainText
              text: "Log: " + root.outcome.log
              color: root.foreground
              opacity: 0.7
              font.family: Style.font.family
              font.pixelSize: Readable.px(Style.font.caption)
              wrapMode: TextEdit.WrapAnywhere
            }
          }
        }

        Row {
          id: resultButtons
          visible: root.page === "result"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.touchSize
          spacing: Style.spacing.lg
          layoutDirection: Qt.RightToLeft

          SheetAction {
            width: root.outcome.restart ? (parent.width - parent.spacing) / 2 : parent.width
            label: "Done"
            primary: !root.outcome.restart
            onTapped: root.dismiss()
          }

          SheetAction {
            visible: root.outcome.restart
            width: (parent.width - parent.spacing) / 2
            label: "Restart now"
            primary: true
            onTapped: {
              Quickshell.execDetached(UpdateModel.ACK_ARGV)
              Quickshell.execDetached(UpdateModel.REBOOT_ARGV)
            }
          }
        }

        // ---------- Details: the run's output, collapsed (progress and result)
        Item {
          id: detailsBox
          visible: root.page === "progress" || (root.page === "result" && root.detailLines.length > 0)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: root.page === "progress" ? progressColumn.bottom : undefined
          anchors.topMargin: Style.spacing.xl
          anchors.bottom: root.page === "progress" ? parent.bottom : resultButtons.top
          anchors.bottomMargin: root.page === "progress" ? 0 : Style.spacing.lg
          height: root.page === "result" ? (root.detailsOpen ? parent.height / 2 : root.touchSize) : 0
          z: 1

          SheetAction {
            id: detailsToggle
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            label: (root.detailsOpen ? "Hide details" : "Details") + " (" + root.detailLines.length + " lines)"
            onTapped: root.detailsOpen = !root.detailsOpen
          }

          Flickable {
            id: detailsFlick
            visible: root.detailsOpen
            anchors.top: detailsToggle.bottom
            anchors.topMargin: Style.spacing.lg
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            contentHeight: detailsText.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            onContentHeightChanged: if (contentHeight > height) contentY = contentHeight - height

            Rectangle {
              width: detailsFlick.width
              height: Math.max(detailsFlick.height, detailsText.implicitHeight)
              radius: Style.cornerRadius
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            }

            Text {
              id: detailsText
              width: detailsFlick.width
              padding: Style.spacing.lg
              textFormat: Text.PlainText
              text: root.detailLines.join("\n")
              color: root.foreground
              font.family: "monospace"
              font.pixelSize: Readable.px(Style.font.caption - 1)
              wrapMode: Text.WrapAnywhere
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- pieces

  // Inline components have their own scope: no `root` in here.
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
