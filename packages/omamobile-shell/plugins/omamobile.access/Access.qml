// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "AccessModel.js" as AccessModel

// The phone's permission question, in place of xdg-desktop-portal-gtk's
// desktop dialog: "Allow Camera to use the camera?" as a bottom sheet with
// the app's icon and two large buttons.
//
// omamobile-portal-access (the portal's Access backend) shows a request with
// `omarchy-shell shell call omamobile.access request '<json>'` (only while the
// phone is unlocked) and takes it back with `dismiss '{"id": ...}'` when it
// times out or the app gives up. A tap answers over D-Bus
// (AccessModel.answerArgv: busctl, org.omamobile.AccessSheet.Answer), and the
// service hands the portal its response. Requests queue: one sheet at a time.
//
// The window is on the overlay layer, over apps, the bar and quick settings,
// but not over the lock screen: a sheet left open when the phone locks
// waits under the lock.
Item {
  id: root

  // Injected by the host.
  property var shell: null
  property var manifest: null

  property var queue: []
  readonly property var current: queue.length > 0 ? queue[0] : null
  readonly property bool opened: current !== null
  // What the sheet last showed, so it doesn't go blank while it slides away.
  property var shown: null
  onCurrentChanged: if (current) shown = current

  // ---------------------------------------------------------------- host API

  function request(json) {
    var r = AccessModel.parseRequest(json)
    if (!r) return "bad request"
    queue = AccessModel.enqueue(queue, r)
    return "ok"
  }

  function dismiss(json) {
    queue = AccessModel.remove(queue, AccessModel.idOf(json))
    return "ok"
  }

  // `shell call omamobile.access snapshot ''`, for tests and debugging.
  function snapshot() {
    return JSON.stringify({ opened: opened, pending: queue.length, current: current })
  }

  // The host's summon/hide: nothing to open without a request.
  function open(payloadJson) {}
  function close() {}

  function answer(allow) {
    var r = current
    if (!r) return
    Quickshell.execDetached(AccessModel.answerArgv(r.id, allow))
    queue = AccessModel.remove(queue, r.id)
  }

  // Back (omamobile.back's BackLink.js): the sheet never takes the keyboard,
  // so Escape went to the app under it. Back closes the request without an
  // answer: nothing is remembered, and the app asks again next time. Only a
  // tap on a button allows or refuses for good.
  function back() {
    var r = current
    if (!r) return false
    Quickshell.execDetached(AccessModel.dismissArgv(r.id))
    queue = AccessModel.remove(queue, r.id)
    return true
  }

  Loader {
    source: Qt.resolvedUrl("../omamobile.back/BackLinkClient.qml")
    onLoaded: {
      item.name = "permission sheet"
      item.handler = function() { return root.back() }
      item.active = Qt.binding(function() { return root.opened })
    }
  }

  // ---------------------------------------------------------------- surface

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

  PanelWindow {
    id: sheetWindow

    visible: root.opened || root.reveal > 0
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "omamobile-access"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    AccessSheet {
      anchors.fill: parent
      request: root.shown
      reveal: root.reveal
      onAnswered: function(allow) { root.answer(allow) }
    }
  }
}
