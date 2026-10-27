// SPDX-License-Identifier: MIT
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Readable.js" as Readable

// Recent apps, after Android: every open window as a card with a live
// preview. Swipe sideways through them, tap one to switch to it, flick it up
// to close it. Home shows the home screen (an empty workspace) and leaves the
// apps open. Summoned by swiping up on the dock (omamobile.launcher).
//
// Every app has a screen (workspace) of its own (omamobile-launch). Hold a
// card for the two ways to change that: "Show with…" puts the app on another
// app's screen, where the two tile as Omarchy tiles them, and "Move to its
// own screen" gives it one back.
//
// On its side (TOUCH-PLAN 2.4: 1040x480) a card keeps the screen's shape,
// so its preview isn't stretched, and the bottom actions keep their row.
//
// Windows come from the Wayland foreign-toplevel list, which gives each one
// activate() and close(). Home and the hold actions need Hyprland: the
// actions find a window's Hyprland address and workspace through
// Quickshell.Hyprland and run omamobile-launch with them.
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "omamobile.switcher"

  property bool opened: false

  // Newest first, like Android's recents.
  readonly property var windows: {
    var list = ToplevelManager.toplevels.values.slice()
    list.reverse()
    return list
  }

  // Host lifecycle (`shell summon` / `shell hide`).
  function open(payloadJson) {
    opened = true
    confirmClear = false
  }
  function close() {
    opened = false
    confirmClear = false
    closeActions()
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function switchTo(toplevel) {
    if (toplevel) toplevel.activate()
    dismiss()
  }

  function goHome() {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"empty\" })"])
    // ...and the home screens (omamobile.home) back on their home page.
    Quickshell.execDetached(["qs", "ipc", "-p", Quickshell.shellDir, "call", "shell", "call", "omamobile.home", "goHome", ""])
    dismiss()
  }

  // Clear all: ask every window to close (the Wayland foreign-toplevel
  // close, which Hyprland turns into the app's own close request), then go
  // back to whatever is left, as Android does. A window still open a couple
  // of seconds later gets the same request again through Hyprland, by its
  // address; an app that asks about unsaved work keeps asking.
  function closeAll() {
    confirmClear = false
    var list = ToplevelManager.toplevels.values.slice()
    var pending = []
    for (var i = 0; i < list.length; i++) pending.push({ toplevel: list[i], address: addressOf(list[i]) })
    console.log("omamobile-switcher: clear all, closing " + list.length + (list.length === 1 ? " window" : " windows"))
    for (var j = 0; j < list.length; j++) list[j].close()
    clearAllPending = pending
    clearAllCheck.restart()
    dismiss()
  }

  property var clearAllPending: []

  Timer {
    id: clearAllCheck
    interval: 2000
    onTriggered: {
      var open = ToplevelManager.toplevels.values
      var left = root.clearAllPending.filter(function(item) { return open.indexOf(item.toplevel) >= 0 })
      root.clearAllPending = []
      if (left.length === 0) return
      console.log("omamobile-switcher: clear all, " + left.length + " still open, closing through Hyprland")
      for (var i = 0; i < left.length; i++) {
        if (left[i].address)
          Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.close({ window = \"address:" + left[i].address + "\" })"])
      }
    }
  }

  // Clear all closes every app, unsaved work included, so it takes two taps:
  // the first turns it into "Close N apps?", which disarms after a few
  // seconds or when the switcher closes. Both taps must reach the button
  // alone: see the bottom actions' TapHandler.
  property bool confirmClear: false

  function clearAll() {
    if (!confirmClear) {
      confirmClear = true
      disarmClear.restart()
      return
    }
    closeAll()
  }

  Timer {
    id: disarmClear
    interval: 4000
    onTriggered: root.confirmClear = false
  }

  // ---------------------------------------------------------------- hold actions

  // The window whose actions are open, and which page: "menu" or "pick"
  // (the apps it can share a screen with).
  property var actionTarget: null
  property string actionPage: "menu"
  readonly property bool actionsOpen: actionTarget !== null && windows.indexOf(actionTarget) >= 0

  // Hyprland's view of a Wayland toplevel: its address and workspace. By the
  // toplevel mapping when Hyprland offers it, else by class and title.
  function hyprlandFor(toplevel) {
    if (!toplevel) return null
    var list = Hyprland.toplevels.values
    var fallback = null
    for (var i = 0; i < list.length; i++) {
      const candidate = list[i]
      if (candidate.wayland === toplevel) return candidate
      const ipc = candidate.lastIpcObject || ({})
      if (!fallback && candidate.title === toplevel.title && ipc["class"] === toplevel.appId) fallback = candidate
    }
    return fallback
  }

  function addressOf(toplevel) {
    var hypr = hyprlandFor(toplevel)
    return hypr && hypr.address ? String(hypr.address) : ""
  }

  function workspaceOf(toplevel) {
    var hypr = hyprlandFor(toplevel)
    return hypr && hypr.workspace ? hypr.workspace.id : null
  }

  // Other open windows on the same screen.
  function screenMates(toplevel) {
    var ws = workspaceOf(toplevel)
    if (ws === null || ws === undefined) return []
    return windows.filter(function(other) { return other !== toplevel && workspaceOf(other) === ws })
  }

  // Windows on other screens, which this one can join.
  function partners(toplevel) {
    var ws = workspaceOf(toplevel)
    return windows.filter(function(other) {
      return other !== toplevel && (ws === null || ws === undefined || workspaceOf(other) !== ws)
    })
  }

  function openActions(toplevel) {
    if (!toplevel) return
    Hyprland.refreshToplevels()
    actionPage = "menu"
    actionTarget = toplevel
  }

  function closeActions() {
    actionTarget = null
    actionPage = "menu"
  }

  // This window onto other's screen: omamobile-launch moves it there by
  // address and tiles the two.
  function showWith(toplevel, other) {
    var a = addressOf(toplevel)
    var b = addressOf(other)
    if (a && b) Quickshell.execDetached(["omamobile-launch", "show-with", a, b])
    closeActions()
    dismiss()
  }

  function moveToOwnScreen(toplevel) {
    var a = addressOf(toplevel)
    if (a) Quickshell.execDetached(["omamobile-launch", "own-screen", a])
    closeActions()
    dismiss()
  }

  function windowLabel(toplevel) {
    if (!toplevel) return ""
    return (toplevel.appId || "App") + (toplevel.title ? "  " + toplevel.title : "")
  }

  readonly property color foreground: Commons.Color.menu.text
  readonly property int touch: Math.max(44, Style.space(44))

  PanelWindow {
    id: overlay

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "omamobile-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    onVisibleChanged: if (visible) cards.positionViewAtBeginning()

    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.background
      opacity: 0.94
    }

    // Tapping empty space goes back to whatever was on screen.
    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      anchors.fill: parent
      focus: root.opened
      Keys.onEscapePressed: {
        if (root.actionsOpen) root.closeActions()
        else root.dismiss()
      }
    }

    Text {
      anchors.centerIn: parent
      visible: root.windows.length === 0
      textFormat: Text.PlainText
      text: "No recent apps"
      color: Qt.darker(root.foreground, 1.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
    }

    ListView {
      id: cards

      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: -Style.space(24)
      height: Math.round(parent.height * 0.68)

      orientation: ListView.Horizontal
      spacing: Style.space(18)
      snapMode: ListView.SnapToItem
      highlightRangeMode: ListView.StrictlyEnforceRange
      preferredHighlightBegin: (width - cardWidth) / 2
      preferredHighlightEnd: (width + cardWidth) / 2
      boundsBehavior: Flickable.StopAtBounds
      model: root.windows

      // 72% of the width upright; on its side, no wider than the screen's
      // shape gives the card's height (the title sits above the card).
      readonly property real previewAspect: overlay.height > 0 ? overlay.width / overlay.height : 1
      readonly property int cardWidth: overlay.width > overlay.height
        ? Math.round(Math.min(width * 0.72, (height - Style.font.body * 1.4 - Style.space(8)) * previewAspect))
        : Math.round(width * 0.72)

      delegate: Item {
        id: slot
        required property var modelData
        required property int index

        width: cards.cardWidth
        height: cards.height

        // Title row: app and window title.
        Text {
          id: title
          anchors.left: card.left
          anchors.right: card.right
          anchors.bottom: card.top
          anchors.bottomMargin: Style.space(8)
          opacity: card.opacity
          textFormat: Text.PlainText
          text: (slot.modelData.appId || "") + (slot.modelData.title ? "  " + slot.modelData.title : "")
          elide: Text.ElideRight
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Rectangle {
          id: card

          width: parent.width
          height: parent.height - title.height - Style.space(8)
          y: title.height + Style.space(8) + drag.lift
          radius: Style.cornerRadius
          clip: true
          color: Commons.Color.background
          border.width: 2
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
          opacity: 1 - Math.min(0.8, Math.abs(drag.lift) / height)

          ScreencopyView {
            anchors.fill: parent
            anchors.margins: card.border.width
            captureSource: root.opened ? slot.modelData : null
            live: true
          }

          // Tap to switch; hold for "Show with…" and "Move to its own screen".
          TapHandler {
            onTapped: root.switchTo(slot.modelData)
            onLongPressed: root.openActions(slot.modelData)
          }

          // Flick up to close; anything shorter springs back.
          DragHandler {
            id: drag
            target: null
            xAxis.enabled: false
            property real lift: 0
            onActiveTranslationChanged: lift = Math.min(0, activeTranslation.y)
            onActiveChanged: {
              if (active) return
              if (lift < -card.height * 0.25) {
                closeOut.start()
              } else {
                springBack.start()
              }
            }
          }

          NumberAnimation {
            id: springBack
            target: drag; property: "lift"; to: 0
            duration: 160; easing.type: Easing.OutCubic
          }

          SequentialAnimation {
            id: closeOut
            NumberAnimation { target: drag; property: "lift"; to: -card.height * 1.2; duration: 160; easing.type: Easing.InCubic }
            ScriptAction { script: { slot.modelData.close(); drag.lift = 0 } }
          }
        }
      }
    }

    // Bottom actions: clear everything (urgent colour, two taps), or go
    // home. Set well apart, so a near miss on Home doesn't arm Clear all.
    //
    // The band they sit in is the switcher's own: it swallows touches, so a
    // tap on or between the buttons never reaches the tap-to-dismiss area
    // underneath. That area is a MouseArea filling the window, and a touch
    // tap reached it as well as the button's TapHandler (a DragThreshold
    // TapHandler only grabs passively, so the press went on down; with a
    // mouse it doesn't). The MouseArea fired first: dismiss() closed the
    // switcher and disarmed Clear all, and the TapHandler then armed it
    // again instead of closing anything. Hyprland saw the switcher close and
    // the app take the focus back, and no window close.
    Item {
      id: actionBand
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: actionRow.height + Style.space(28) * 2
      z: 1

      MouseArea { anchors.fill: parent }
    }

    Row {
      id: actionRow
      z: 2
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(28)
      spacing: Style.space(40)

      Repeater {
        // A fixed model: one that read root.windows rebuilt both buttons
        // whenever a window opened or closed, under a finger too.
        model: [
          { label: "Clear all", action: "clear" },
          { label: "Home", action: "home" }
        ]

        delegate: BorderSurface {
          id: bottomButton
          required property var modelData
          readonly property bool danger: modelData.action === "clear"
          readonly property bool armed: danger && root.confirmClear
          // Opaque over the cards, so the pressed fill is tinted onto it.
          readonly property color base: armed ? Commons.Color.urgent
            : danger ? Qt.tint(Commons.Color.background, Util.alpha(Commons.Color.urgent, 0.18))
            : Commons.Color.background
          visible: !danger || root.windows.length > 0
          width: Math.max(root.touch * 2.6, label.implicitWidth + Style.space(32))
          height: root.touch
          radius: Style.cornerRadius
          color: tap.pressed ? Qt.tint(base, Style.pressedFillFor(root.foreground, Commons.Color.accent)) : base

          Text {
            id: label
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: !bottomButton.armed ? bottomButton.modelData.label
              : root.windows.length === 1 ? "Close 1 app?" : "Close " + root.windows.length + " apps?"
            color: bottomButton.armed ? Commons.Color.background
              : bottomButton.danger ? Commons.Color.urgent : root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: bottomButton.armed
          }

          // Exclusive: the press stops here, so nothing under the button
          // sees the tap (a release off the button is no tap).
          TapHandler {
            id: tap
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: bottomButton.modelData.action === "home" ? root.goHome() : root.clearAll()
          }
        }
      }
    }

    // Hold actions: a sheet over the cards. Tapping outside it closes it.
    Item {
      id: actionLayer
      anchors.fill: parent
      visible: root.actionsOpen
      z: 3

      Rectangle {
        anchors.fill: parent
        color: Commons.Color.menu.background
        opacity: 0.6
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.closeActions()
      }

      BorderSurface {
        id: actionCard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(16)
        anchors.bottomMargin: Style.space(28)
        height: actionColumn.implicitHeight + Style.space(24)
        radius: Style.cornerRadius
        color: Commons.Color.background

        // Swallows taps between the rows, so they don't close the sheet.
        MouseArea { anchors.fill: parent }

        Column {
          id: actionColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(12)
          spacing: Style.space(6)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.actionPage === "pick" ? "Show with…" : root.windowLabel(root.actionTarget)
            elide: Text.ElideRight
            color: Qt.darker(root.foreground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            bottomPadding: Style.space(6)
          }

          // The menu.
          SheetRow {
            visible: root.actionPage === "menu"
            enabled: root.actionsOpen && root.partners(root.actionTarget).length > 0
            text: "Show with…"
            hint: enabled ? "Share the screen with another open app" : "No other app is open"
            onActivated: root.actionPage = "pick"
          }

          SheetRow {
            visible: root.actionPage === "menu" && root.actionsOpen && root.screenMates(root.actionTarget).length > 0
            text: "Move to its own screen"
            hint: "Stop sharing the screen"
            onActivated: root.moveToOwnScreen(root.actionTarget)
          }

          // The apps to share a screen with.
          Repeater {
            model: root.actionPage === "pick" && root.actionsOpen ? root.partners(root.actionTarget) : []

            delegate: SheetRow {
              required property var modelData
              text: modelData.appId || "App"
              hint: modelData.title || ""
              onActivated: root.showWith(root.actionTarget, modelData)
            }
          }

          SheetRow {
            text: root.actionPage === "pick" ? "Back" : "Cancel"
            onActivated: {
              if (root.actionPage === "pick") root.actionPage = "menu"
              else root.closeActions()
            }
          }
        }
      }
    }
  }

  // One row of the hold-actions sheet: a label over a hint.
  component SheetRow: Rectangle {
    id: sheetRow

    property string text: ""
    property string hint: ""
    signal activated()

    width: parent ? parent.width : 0
    height: Math.max(root.touch, rowText.implicitHeight + (rowHint.visible ? rowHint.implicitHeight : 0) + Style.space(16))
    radius: Style.cornerRadius
    color: rowTap.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent) : "transparent"
    opacity: enabled ? 1 : 0.45

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)

      Text {
        id: rowText
        width: parent.width
        textFormat: Text.PlainText
        text: sheetRow.text
        elide: Text.ElideRight
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
      }

      Text {
        id: rowHint
        width: parent.width
        visible: sheetRow.hint.length > 0
        textFormat: Text.PlainText
        text: sheetRow.hint
        elide: Text.ElideRight
        color: Qt.darker(root.foreground, 1.4)
        font.family: Style.font.family
        font.pixelSize: Readable.px(Style.font.caption)
      }
    }

    MouseArea {
      id: rowTap
      anchors.fill: parent
      enabled: sheetRow.enabled
      onClicked: sheetRow.activated()
    }
  }
}
