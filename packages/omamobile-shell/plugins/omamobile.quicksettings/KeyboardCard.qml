// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "HwKeyboardModel.js" as HwKeyboardModel

// The hardware keyboard card at the top of the notification shade, drawn as
// MediaCard.qml: while a Bluetooth or USB keyboard is connected the on-screen
// keyboard no longer pops up on a text field (omamobile-osk-guard owns that
// and lists the keyboards in ~/.local/state/omamobile/osk-hwkbd.json). One
// row per keyboard, "<name> connected", with Disconnect for a Bluetooth one;
// Show / Hide on-screen keyboard set the guard's mode for all of them.
BorderSurface {
  id: card

  property color foreground: Commons.Color.popups.text
  property var keyboards: []
  property string mode: "auto"

  readonly property int inner: Style.spacing.lg

  visible: keyboards.length > 0
  implicitHeight: visible ? column.implicitHeight + inner * 2 : 0
  radius: Style.cornerRadius
  color: Style.normalFillFor(card.foreground, Commons.Color.accent)
  borderSpec: Border.controlSpec("normal", card.foreground, Commons.Color.accent)

  Accessible.role: Accessible.Grouping
  Accessible.name: HwKeyboardModel.accessibleName(keyboards)

  function load(text) {
    var s = HwKeyboardModel.parse(text)
    keyboards = s.keyboards
    mode = s.mode
  }

  FileView {
    id: stateFile
    path: Quickshell.env("HOME") + "/.local/state/omamobile/osk-hwkbd.json"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: card.load(text())
    onLoadFailed: card.load("")
  }

  // The guard replaces the file (rename); each reload watches it again, and
  // this catches a watch that was lost.
  Timer { interval: 5000; repeat: true; running: true; onTriggered: stateFile.reload() }

  Column {
    id: column
    x: card.inner
    y: card.inner
    width: card.width - card.inner * 2
    spacing: Style.spacing.md

    Repeater {
      model: card.keyboards

      Item {
        required property var modelData
        width: column.width
        height: Math.max(rowText.implicitHeight, disconnectButton.visible ? disconnectButton.height : 0)

        Text {
          id: rowText
          anchors.left: parent.left
          anchors.right: disconnectButton.visible ? disconnectButton.left : parent.right
          anchors.rightMargin: disconnectButton.visible ? Style.spacing.md : 0
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "󰌌  " + HwKeyboardModel.rowText(modelData)
          color: card.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }

        SheetButton {
          id: disconnectButton
          visible: modelData.canDisconnect
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(96, Style.space(120))
          label: "Disconnect"
          foreground: card.foreground
          onTapped: {
            var cmd = HwKeyboardModel.disconnectCommand(modelData)
            if (cmd) Quickshell.execDetached(cmd)
          }
        }
      }
    }

    SheetButton {
      width: column.width
      label: "Show on-screen keyboard"
      primary: card.mode === "show"
      foreground: card.foreground
      onTapped: Quickshell.execDetached(HwKeyboardModel.modeCommand("show"))
    }

    SheetButton {
      width: column.width
      label: "Hide on-screen keyboard"
      primary: card.mode === "hide"
      foreground: card.foreground
      onTapped: Quickshell.execDetached(HwKeyboardModel.modeCommand("hide"))
    }
  }
}
