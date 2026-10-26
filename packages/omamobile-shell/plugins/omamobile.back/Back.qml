// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "BackModel.js" as BackModel

// The back gesture, as on Android (TOUCH-PLAN 1.2): swipe in from the left
// or right edge of the screen and let go to go back. "Back" is Escape, sent
// to whatever has the keyboard focus (BackModel.js has how): it closes app
// dialogs, menus and popovers that have no other way out on a touch screen,
// and the shell's own sheets and drawer, which all close on Escape.
//
// Each edge is a thin strip on the Overlay layer, like the home pill: its
// window is wide enough to draw the arrow that follows the finger, but its
// input mask leaves only the outer few pixels to the gesture, and everything
// else passes through to what is below. Normal exclusion keeps the strips
// between the status bar and the on-screen keyboard (or the dock), so they
// never take the keyboard's edge keys. They hide for a real fullscreen
// window (video, the screensaver), as the home pill does, and they are not
// drawn over the lock screen (hypr/phone.lua gives them no above_lock rule).
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  // Nothing to summon: the strips are always there.
  function open(payloadJson) {
    Qt.callLater(function() {
      if (root.shell && typeof root.shell.hide === "function") root.shell.hide((root.manifest && root.manifest.id) || "omamobile.back")
    })
  }
  function close() {}

  // `shell call omamobile.back back ''`: the same as the gesture.
  function back() {
    Quickshell.execDetached(BackModel.ESCAPE_ARGV)
    return "ok"
  }

  // `shell call omamobile.back state ''`
  function state() {
    return JSON.stringify({ fullscreen: fullscreenOnScreen, strips: !fullscreenOnScreen, edge: edge, threshold: BackModel.THRESHOLD })
  }

  // The touchable strip at each edge, and the width its window draws in.
  readonly property int edge: 14
  readonly property int arrowSize: Math.max(40, Style.space(40))
  readonly property int reach: arrowSize + 24

  // A real fullscreen window (mode bit 2; a maximized one reports 1) on the
  // focused workspace, debounced as the home pill does it
  // (omamobile.launcher): Hyprland's events arrive before its IPC answer.
  property int hyprRevision: 0
  readonly property bool fullscreenOnScreen: {
    var revision = hyprRevision
    var workspace = Hyprland.focusedWorkspace
    if (!workspace) return false
    var windows = workspace.toplevels ? workspace.toplevels.values : []
    for (var i = 0; i < windows.length; i++) {
      var ipc = windows[i].lastIpcObject || {}
      if ((Number(ipc.fullscreen) & 2) !== 0) return true
    }
    return false
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      switch (event.name) {
      case "fullscreen": case "openwindow": case "closewindow": case "movewindowv2":
      case "activewindowv2": case "workspacev2": case "focusedmonv2": case "changefloatingmode":
        hyprRefresh.restart()
      }
    }
  }

  Timer {
    id: hyprRefresh
    interval: 100
    onTriggered: { Hyprland.refreshToplevels(); hyprSettle.restart() }
  }

  Timer {
    id: hyprSettle
    interval: 250
    onTriggered: root.hyprRevision++
  }

  Variants {
    model: Quickshell.screens
    EdgeWindow {
      required property var modelData
      screen: modelData
      rightEdge: false
    }
  }

  Variants {
    model: Quickshell.screens
    EdgeWindow {
      required property var modelData
      screen: modelData
      rightEdge: true
    }
  }

  component EdgeWindow: PanelWindow {
    id: win

    property bool rightEdge: false

    visible: !root.fullscreenOnScreen
    anchors { top: true; bottom: true; left: !win.rightEdge; right: win.rightEdge }
    implicitWidth: root.reach
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    WlrLayershell.namespace: "omamobile-back"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Only the strip at the very edge takes touches.
    mask: Region { item: strip }

    Item {
      anchors.fill: parent

      Item {
        id: strip
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        x: win.rightEdge ? parent.width - width : 0
        width: root.edge

        // The touch stays with this surface once it lands on the strip,
        // so the drag keeps arriving after the finger leaves it.
        DragHandler {
          id: swipe
          target: null
          readonly property real inward: active ? BackModel.inwardFor(win.rightEdge, activeTranslation.x) : 0
          readonly property real across: active ? activeTranslation.y : 0
          readonly property real progress: BackModel.progress(inward, BackModel.THRESHOLD)
          readonly property bool armed: BackModel.fires(inward, across, BackModel.THRESHOLD)
          property real atY: 0
          property bool wasArmed: false
          onCentroidChanged: if (active) atY = centroid.position.y
          onArmedChanged: if (active) wasArmed = armed
          onActiveChanged: {
            if (active) { atY = centroid.position.y; wasArmed = false; return }
            console.log("omamobile-back: swipe", win.rightEdge ? "right" : "left", wasArmed ? "back" : "")
            if (wasArmed) root.back()
          }
        }
      }

      // The arrow: comes in with the finger and fills in once letting go
      // would go back.
      Rectangle {
        id: arrow
        readonly property real shown: swipe.progress
        visible: swipe.active && shown > 0
        width: root.arrowSize
        height: root.arrowSize
        radius: width / 2
        x: win.rightEdge ? parent.width - shown * (width + 12) : -width + shown * (width + 12)
        y: Math.max(0, Math.min(parent.height - height, swipe.atY - height / 2))
        opacity: 0.4 + 0.55 * shown
        color: swipe.armed ? Commons.Color.accent : Commons.Color.bar.background
        border.width: 1
        border.color: Qt.rgba(Commons.Color.bar.text.r, Commons.Color.bar.text.g, Commons.Color.bar.text.b, 0.3)

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          // nf-md-chevron_left / chevron_right: pointing back at the edge
          text: String.fromCodePoint(win.rightEdge ? 0xF0142 : 0xF0141)
          color: swipe.armed ? Commons.Color.background : Commons.Color.bar.text
          font.family: Style.font.family
          font.pixelSize: Math.round(root.arrowSize * 0.6)
        }
      }
    }
  }
}
