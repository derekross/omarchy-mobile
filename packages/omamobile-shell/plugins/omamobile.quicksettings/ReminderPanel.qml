// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TilesModel.js" as TilesModel
import "Readable.js" as Readable

// The page behind the Reminder tile (TOUCH-PLAN 1.12): Omarchy's reminders
// for a thumb. The desktop sets one with Super+Ctrl+R and a keyboard
// flow; here a row of minute presets (or a typed number), a message, and
// Set, which runs `omarchy-reminder <minutes> [message]`: the timer, its
// toast when it fires and the confirmation are Omarchy's own. Above the
// form, what is pending (`omarchy-reminder show --json`) with a two-tap
// Clear all (`omarchy-reminder clear`). The form keeps to the bottom of
// the card, so it stays above the on-screen keyboard while a field has
// focus, as the Wi-Fi password and the update sheet's PIN do.
Item {
  id: root

  property bool opened: false
  property color foreground: Commons.Color.popups.text
  // The minutes field's text; a preset chip sets it.
  property string minutes: "10"
  property var reminders: []
  property bool listed: false
  property bool confirmClear: false

  // The back glyph: the owner closes this and brings quick settings back.
  signal backRequested()
  // A reminder was set (omarchy-reminder ran): the owner closes this and
  // re-reads its tile's count.
  signal reminderSet()
  // Clear all ran: the owner re-reads the count.
  signal clearedAll()

  readonly property int touchSize: Math.max(44, Style.space(48))
  readonly property int pad: Style.spacing.panelPadding
  readonly property var presets: [5, 10, 15, 30, 60]
  readonly property int validMinutes: TilesModel.validMinutes(minutes)

  function open() {
    opened = true
    confirmClear = false
    refresh()
  }

  function close() {
    opened = false
    confirmClear = false
    disarmClear.stop()
  }

  function refresh() {
    if (!showProc.running) showProc.running = true
  }

  function setReminder() {
    var argv = TilesModel.reminderArgv(minutes, messageField.text)
    if (!argv) return
    Quickshell.execDetached(argv)
    messageField.text = ""
    reminderSet()
  }

  // Clear all takes two taps, like the other destructive actions in quick
  // settings: the first turns it into "Clear all?" for a few seconds.
  function requestClear() {
    if (!confirmClear) {
      confirmClear = true
      disarmClear.restart()
      return
    }
    confirmClear = false
    Quickshell.execDetached(["omarchy-reminder", "clear"])
    reminders = []
    relist.restart()
    clearedAll()
  }

  Timer {
    id: disarmClear
    interval: 4000
    onTriggered: root.confirmClear = false
  }

  Timer {
    id: relist
    interval: 1200
    onTriggered: root.refresh()
  }

  Process {
    id: showProc
    command: ["omarchy-reminder", "show", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.reminders = TilesModel.parseReminders(text)
        root.listed = true
      }
    }
  }

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  PanelWindow {
    id: window

    visible: root.opened || root.reveal > 0
    anchors { top: true; bottom: true; left: true; right: true }
    // Normal: fit between the status bar and the on-screen keyboard.
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-reminder"
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
      objectName: "reminderPanel"

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

      // Swallow taps so they don't reach the scrim.
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
            text: "Reminder"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }
        }

        // ---------- What is pending, with Clear all
        Flickable {
          id: pending
          anchors.top: header.bottom
          anchors.topMargin: root.pad
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: form.top
          anchors.bottomMargin: root.pad
          contentHeight: pendingColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: pendingColumn
            width: pending.width
            spacing: Style.spacing.md

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.reminders.length === 0 ? (root.listed ? "Nothing pending" : "") : (root.reminders.length === 1 ? "1 pending" : root.reminders.length + " pending")
              color: Readable.secondary(root.foreground, Commons.Color.popups.background)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Repeater {
              model: root.reminders
              delegate: Item {
                id: pendingRow
                required property var modelData
                width: parent.width
                height: Math.max(root.touchSize, pendingText.implicitHeight + Style.spacing.lg)

                Column {
                  id: pendingText
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xxs

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: pendingRow.modelData.label
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: "At " + pendingRow.modelData.atTime + " (in " + pendingRow.modelData.remaining + ")"
                    color: Readable.secondary(root.foreground, Commons.Color.popups.background)
                    font.family: Style.font.family
                    font.pixelSize: Readable.px(Style.font.caption)
                    elide: Text.ElideRight
                  }
                }
              }
            }

            SheetButton {
              objectName: "reminderClear"
              visible: root.reminders.length > 0
              width: parent.width
              label: root.confirmClear ? "Clear all?" : "Clear all"
              danger: root.confirmClear
              foreground: root.foreground
              onTapped: root.requestClear()
            }
          }
        }

        // ---------- The form, above the keyboard
        Column {
          id: form
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.spacing.lg

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "Remind me in"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Flow {
            width: parent.width
            spacing: Style.spacing.md

            Repeater {
              model: root.presets
              delegate: BorderSurface {
                id: chip
                required property var modelData
                readonly property bool selected: root.validMinutes === chip.modelData
                objectName: "reminderPreset-" + chip.modelData
                width: Math.max(root.touchSize, chipText.implicitWidth + Style.spacing.xl * 2)
                height: root.touchSize
                radius: Style.cornerRadius
                color: chipTouch.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
                  : chip.selected ? Util.alpha(Commons.Color.accent, Style.selectedFillAlpha)
                  : Style.normalFillFor(root.foreground, Commons.Color.accent)
                borderSpec: Border.controlSpec(chip.selected ? "selected" : "normal", root.foreground, Commons.Color.accent)

                Text {
                  id: chipText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: chip.modelData + " min"
                  color: chip.selected ? Commons.Color.accent : root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.bold: chip.selected
                }

                MouseArea {
                  id: chipTouch
                  anchors.fill: parent
                  onClicked: root.minutes = String(chip.modelData)
                }
              }
            }
          }

          Item {
            width: parent.width
            height: root.touchSize

            TextField {
              id: minutesField
              objectName: "reminderMinutes"
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: Math.round(parent.width * 0.32)
              verticalAlignment: TextInput.AlignVCenter
              font.pixelSize: Style.font.title
              foreground: root.foreground
              placeholderText: "Minutes"
              placeholderTextColor: Readable.secondary(root.foreground, Readable.flatten(Style.controlFill(activeFocus, hovered || hasCursor, foreground, accent), Commons.Color.popups.background))
              text: root.minutes
              inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhNoPredictiveText
              onTextEdited: root.minutes = text
              Keys.onEscapePressed: root.close()
            }

            TextField {
              id: messageField
              objectName: "reminderMessage"
              anchors.left: minutesField.right
              anchors.leftMargin: Style.spacing.lg
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              verticalAlignment: TextInput.AlignVCenter
              font.pixelSize: Style.font.title
              foreground: root.foreground
              placeholderText: "What for (optional)"
              placeholderTextColor: Readable.secondary(root.foreground, Readable.flatten(Style.controlFill(activeFocus, hovered || hasCursor, foreground, accent), Commons.Color.popups.background))
              inputMethodHints: Qt.ImhNoPredictiveText
              onAccepted: root.setReminder()
              Keys.onEscapePressed: root.close()
            }
          }

          SheetButton {
            objectName: "reminderSet"
            width: parent.width
            label: root.validMinutes > 0 ? "Set for " + root.validMinutes + (root.validMinutes === 1 ? " minute" : " minutes") : "Set"
            primary: true
            enabled: root.validMinutes > 0
            foreground: root.foreground
            onTapped: root.setReminder()
          }
        }
      }
    }
  }
}
