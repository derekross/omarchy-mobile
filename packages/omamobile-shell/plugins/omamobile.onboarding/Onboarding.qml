// SPDX-License-Identifier: MIT
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "OnboardingModel.js" as Model
import "Readable.js" as Readable

// The phone's setup sheet (TOUCH-PLAN 1.11), in place of the gum prompts
// that omamobile-onboarding and omamobile-set-pin put in a terminal, which
// a touch screen can't answer. Opened by those scripts themselves
// (`omarchy-shell shell summon omamobile.onboarding '{}'` for the first
// run, '{"page":"pin"}' for System > PIN), by the login nudge, or by hand.
//
// It asks what the prompts ask, in their order: the first run is name and
// email, then a PIN or password unless there is one already (then a note,
// as the prompts say), then Omarchy's invitation to pick a default agent;
// System > PIN is the choice between a PIN and a password, then the entry.
// Every answer goes to the scripts, which keep the one definition of what
// it does: `--status --json` for what is set, `--identity NAME EMAIL`,
// `--invite-agent`, and `omamobile-set-pin --apply TYPE` with the current
// and the new secret on its stdin (never argv or a file), which drives
// passwd and records the choice. The scripts' terminal prompts stay as the
// fallback when the shell isn't running.
//
// The window sits on the top layer with normal exclusion, like the update
// sheet, so it fits between the status bar and the on-screen keyboard: the
// fields and their buttons keep to the bottom of the card, above the keys.
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string flow: "onboarding"   // onboarding | pin
  property string page: "identity"     // identity | credential-exists | pin-choice | pin-entry | applying | done
  property var info: Model.parseStatus("")
  property bool infoLoaded: false
  property string type: "pin"          // pin | password: the choice on pin-choice
  property string step: "new"          // current | new | retype
  property bool digits: true
  property string entryError: ""
  property bool changed: false         // a PIN or password was set in this visit
  property bool busy: false

  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int pad: Style.spacing.panelPadding
  readonly property color foreground: Commons.Color.popups.text
  readonly property color secondary: Readable.secondary(foreground, Commons.Color.popups.background)
  readonly property var steps: Model.entrySteps(info.pin.set)
  readonly property var stepWords: Model.stepText(step, type)
  readonly property string pluginId: (manifest && manifest.id) || "omamobile.onboarding"
  readonly property string title: flow === "pin" ? (type === "password" ? "Password" : "PIN") : "Set up your phone"

  // The secrets live only in these two strings and the field, until they
  // go to omamobile-set-pin's stdin; nothing logs them.
  property string currentSecret: ""
  property string newSecret: ""

  // ---------------------------------------------------------------- host API

  // '{}' or '{"page":"pin"}'.
  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (error) {}
    flow = payload.page === "pin" ? "pin" : "onboarding"
    opened = true
    changed = false
    entryError = ""
    clearSecrets()
    page = Model.firstPage(flow)
    infoLoaded = false
    refreshStatus()
    if (page === "pin-choice") type = info.pin.type
  }

  function close() {
    if (!opened) return
    opened = false
    clearSecrets()
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(pluginId)
    else close()
  }

  // `shell call omamobile.onboarding snapshot ''`: never a secret.
  function snapshot() {
    return JSON.stringify({ opened: opened, flow: flow, page: page, step: step, type: type, changed: changed })
  }

  // ---------------------------------------------------------------- flow

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }

  function clearSecrets() {
    currentSecret = ""
    newSecret = ""
    secretField.text = ""
  }

  function goTo(next) {
    entryError = ""
    page = next
    if (next === "pin-choice") type = info.pin.type
    if (next === "pin-entry") startEntry()
    if (next === "done" && flow === "onboarding") Quickshell.execDetached(Model.INVITE_ARGV)
    if (next === "identity") Qt.callLater(function() { nameField.forceActiveFocus() })
  }

  function advance() { goTo(Model.nextPage(flow, page, info)) }

  // Identity: saved when either answer is given, as the prompts do.
  function submitIdentity() {
    var name = nameField.text.trim(), email = emailField.text.trim()
    if (name || email) Quickshell.execDetached(Model.identityArgv(name, email))
    advance()
  }

  function startEntry() {
    clearSecrets()
    digits = type !== "password"
    step = steps[0]
    entryError = ""
    focusSecret()
  }

  function focusSecret() {
    Qt.callLater(function() { secretField.forceActiveFocus() })
  }

  // One step at a time, as passwd asks: the current one, the new one, the
  // new one again; a mismatch goes back to the new one.
  function submitSecret() {
    if (busy || secretField.text.length === 0) return
    var value = secretField.text
    secretField.text = ""
    entryError = ""
    if (step === "current") {
      currentSecret = value
      step = "new"
      focusSecret()
      return
    }
    if (step === "new") {
      newSecret = value
      step = "retype"
      focusSecret()
      return
    }
    if (value !== newSecret) {
      newSecret = ""
      step = "new"
      entryError = "They don't match. Try again."
      focusSecret()
      return
    }
    apply()
  }

  function backStep() {
    entryError = ""
    secretField.text = ""
    if (step === "retype") { newSecret = ""; step = "new"; focusSecret(); return }
    if (step === "new" && steps[0] === "current") { currentSecret = ""; step = "current"; focusSecret(); return }
    clearSecrets()
    goTo("pin-choice")
  }

  function apply() {
    busy = true
    page = "applying"
    applyProc.command = Model.applyArgv(type)
    applyProc.running = true
  }

  // ---------------------------------------------------------------- processes

  Process {
    id: statusProc
    command: Model.STATUS_ARGV
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: {
      root.info = Model.parseStatus(statusOut.text)
      root.infoLoaded = true
      if (root.page === "identity") {
        if (nameField.text === "") nameField.text = root.info.name
        if (emailField.text === "") emailField.text = root.info.email
      }
      if (root.page === "pin-choice") root.type = root.info.pin.type
    }
  }

  Process {
    id: applyProc
    stdinEnabled: true
    stdout: StdioCollector { id: applyOut; waitForEnd: true }
    onStarted: {
      applyProc.write(root.currentSecret + "\n" + root.newSecret + "\n")
      applyProc.stdinEnabled = false
      root.clearSecrets()
    }
    onExited: function(exitCode) {
      root.busy = false
      applyProc.stdinEnabled = true
      var outcome = Model.applyOutcome(exitCode, applyOut.text)
      if (outcome.result === "set") {
        root.changed = true
        root.refreshStatus()
        root.goTo("done")
        return
      }
      var back = Model.failureText(outcome, root.type)
      root.page = "pin-entry"
      root.step = back.step === "current" && root.steps[0] === "current" ? "current" : "new"
      root.entryError = back.text
      root.focusSecret()
    }
  }

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
    WlrLayershell.namespace: "omamobile-onboarding"
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
      onClicked: if (root.page !== "applying") root.dismiss()
    }

    BorderSurface {
      id: card
      objectName: "setupCard"

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
      Keys.onEscapePressed: if (root.page !== "applying") root.dismiss()

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
          objectName: "setupHeader"
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.touchSize

          Text {
            anchors.left: parent.left
            anchors.right: closeButton.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.title
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
            enabled: root.page !== "applying"
            onTapped: root.dismiss()
          }
        }

        // ---------- The page's words, under the header
        Column {
          id: words
          anchors.top: headerRow.bottom
          anchors.topMargin: Style.spacing.xl
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.spacing.lg
          visible: root.page !== "pin-entry" && root.page !== "applying"

          Text {
            objectName: "pageTitle"
            width: parent.width
            textFormat: Text.PlainText
            text: root.page === "identity" ? "Welcome to Omarchy Mobile."
              : root.page === "credential-exists" ? "Your phone already has a " + (root.info.pin.type === "password" ? "password" : "PIN") + "."
              : root.page === "pin-choice" ? "Choose how you unlock the phone."
              : root.page === "done" ? Model.doneText(root.flow, root.type, root.changed, root.info.agent).title : ""
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
            text: root.page === "identity" ? "Two quick steps: who you are, for git and your keyboard's shortcuts, then how you unlock the phone."
              : root.page === "credential-exists" ? "Change it, or switch between a PIN and a password, here or in System > PIN."
              : root.page === "pin-choice" ? "It is also used for sudo."
              : root.page === "done" ? Model.doneText(root.flow, root.type, root.changed, root.info.agent).body : ""
            color: root.secondary
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }

          // The two ways to unlock, the current one first.
          Repeater {
            model: root.page === "pin-choice" ? Model.typeChoices(root.info.pin.type) : []
            delegate: BorderSurface {
              id: choiceRow
              required property var modelData
              readonly property bool selected: root.type === choiceRow.modelData.id
              objectName: "choice-" + choiceRow.modelData.id
              width: parent ? parent.width : 0
              height: Math.max(root.touchSize, choiceText.implicitHeight + Style.spacing.lg * 2)
              radius: Style.cornerRadius
              color: choiceTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
                : choiceRow.selected ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
                : Style.normalFillFor(root.foreground, Commons.Color.accent)
              borderSpec: Border.controlSpec(choiceRow.selected ? "selected" : "normal", root.foreground, Commons.Color.accent)

              Text {
                id: choiceMark
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: choiceRow.selected ? "󰄴" : "󰄰"
                color: choiceRow.selected ? Commons.Color.accent : root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
              }

              Column {
                id: choiceText
                anchors.left: choiceMark.right
                anchors.leftMargin: Style.spacing.lg
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xs

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: choiceRow.modelData.title
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: choiceRow.modelData.detail
                  color: root.secondary
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  wrapMode: Text.Wrap
                }
              }

              MouseArea {
                id: choiceTouch
                anchors.fill: parent
                onClicked: root.type = choiceRow.modelData.id
              }
            }
          }
        }

        // ---------- Identity: the two fields, above the keyboard
        Column {
          id: identityForm
          visible: root.page === "identity"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.spacing.lg

          TextField {
            id: nameField
            objectName: "nameField"
            width: parent.width
            height: root.touchSize
            verticalAlignment: TextInput.AlignVCenter
            font.pixelSize: Style.font.title
            foreground: root.foreground
            placeholderText: "Your name"
            placeholderTextColor: Readable.secondary(root.foreground, Readable.flatten(Style.controlFill(activeFocus, hovered || hasCursor, foreground, accent), Commons.Color.popups.background))
            inputMethodHints: Qt.ImhNoPredictiveText
            onAccepted: emailField.forceActiveFocus()
            Keys.onEscapePressed: root.dismiss()
          }

          TextField {
            id: emailField
            objectName: "emailField"
            width: parent.width
            height: root.touchSize
            verticalAlignment: TextInput.AlignVCenter
            font.pixelSize: Style.font.title
            foreground: root.foreground
            placeholderText: "Your email"
            placeholderTextColor: Readable.secondary(root.foreground, Readable.flatten(Style.controlFill(activeFocus, hovered || hasCursor, foreground, accent), Commons.Color.popups.background))
            inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            onAccepted: root.submitIdentity()
            Keys.onEscapePressed: root.dismiss()
          }

          Row {
            width: parent.width
            height: root.touchSize
            spacing: Style.spacing.lg
            layoutDirection: Qt.RightToLeft

            SheetAction {
              width: (parent.width - parent.spacing) / 2
              label: "Continue"
              primary: true
              onTapped: root.submitIdentity()
            }

            SheetAction {
              width: (parent.width - parent.spacing) / 2
              label: "Skip"
              onTapped: root.advance()
            }
          }
        }

        // ---------- A PIN exists: keep it or change it
        Row {
          visible: root.page === "credential-exists"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.touchSize
          spacing: Style.spacing.lg
          layoutDirection: Qt.RightToLeft

          SheetAction {
            width: (parent.width - parent.spacing) / 2
            label: "Keep it"
            primary: true
            onTapped: root.advance()
          }

          SheetAction {
            width: (parent.width - parent.spacing) / 2
            label: "Change it"
            onTapped: root.goTo("pin-choice")
          }
        }

        // ---------- The choice made
        SheetAction {
          visible: root.page === "pin-choice"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          label: "Continue"
          primary: true
          onTapped: root.advance()
        }

        // ---------- The entry: one secret at a time, above the keyboard
        Column {
          id: entryColumn
          visible: root.page === "pin-entry"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.spacing.xl

          Text {
            objectName: "entryTitle"
            width: parent.width
            textFormat: Text.PlainText
            text: root.stepWords.title
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
            text: root.entryError !== "" ? root.entryError : root.stepWords.hint
            color: root.entryError !== "" ? Commons.Color.urgent : root.secondary
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }

          Item {
            width: parent.width
            height: root.touchSize

            TextField {
              id: secretField
              objectName: "secretField"
              anchors.left: parent.left
              anchors.right: modeSwitch.left
              anchors.rightMargin: Style.spacing.lg
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              verticalAlignment: TextInput.AlignVCenter
              font.pixelSize: Style.font.title
              foreground: root.foreground
              placeholderText: root.type === "password" ? "Password" : "PIN"
              placeholderTextColor: Readable.secondary(root.foreground, Readable.flatten(Style.controlFill(activeFocus, hovered || hasCursor, foreground, accent), Commons.Color.popups.background))
              password: true
              enabled: !root.busy
              inputMethodHints: root.digits
                ? (Qt.ImhDigitsOnly | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText)
                : (Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase)
              onAccepted: root.submitSecret()
              onTextEdited: root.entryError = ""
              Keys.onEscapePressed: root.backStep()
            }

            SheetAction {
              id: modeSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: root.touchSize + Style.space(16)
              label: root.digits ? "ABC" : "123"
              onTapped: {
                root.digits = !root.digits
                secretField.focus = false
                root.focusSecret()
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
              label: root.step === "retype" ? "Set" : "Next"
              primary: true
              enabled: secretField.text.length > 0 && !root.busy
              onTapped: root.submitSecret()
            }

            SheetAction {
              width: (parent.width - parent.spacing) / 2
              label: "Back"
              enabled: !root.busy
              onTapped: root.backStep()
            }
          }
        }

        // ---------- Applying
        Row {
          visible: root.page === "applying"
          anchors.top: headerRow.bottom
          anchors.topMargin: Style.spacing.xl
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.spacing.lg

          Text {
            id: spinner
            textFormat: Text.PlainText
            text: "󰑐"
            color: Commons.Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.iconLarge
            RotationAnimator on rotation {
              running: root.page === "applying" && root.opened
              from: 0
              to: 360
              duration: 1200
              loops: Animation.Infinite
            }
          }

          Text {
            anchors.verticalCenter: spinner.verticalCenter
            textFormat: Text.PlainText
            text: "Setting it..."
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
        }

        // ---------- Done
        SheetAction {
          visible: root.page === "done"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          label: "Done"
          primary: true
          onTapped: root.dismiss()
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
    opacity: enabled ? 1 : 0.45

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
      enabled: glyphItem.enabled
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
}
