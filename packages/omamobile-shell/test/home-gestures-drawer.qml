// SPDX-License-Identifier: MIT
// A stand-in for omamobile.launcher's drawer in test/home-gestures: it
// publishes itself through the real DrawerLink.js, as Launcher.qml does,
// records the home screen's calls, and decides like the drawer, with the
// real LauncherModel.drawerEndsOpen over a 800 px travel.
import QtQuick
import "omamobile.launcher/DrawerLink.js" as DrawerLink
import "omamobile.launcher/LauncherModel.js" as LauncherModel

QtObject {
  id: drawer
  readonly property real travelPx: 800
  property int begins: 0
  property real travel: 0
  property var ends: []
  property bool opened: false
  property real progress: 0

  function reset() { begins = 0; travel = 0; ends = []; opened = false; progress = 0 }
  function gestureBegin() { begins++; return true }
  function gestureMove(px) { travel = px; progress = Math.min(1, px / travelPx) }
  function gestureEnd(speed) {
    ends = ends.concat([speed])
    opened = LauncherModel.drawerEndsOpen(progress, speed, false)
    return opened
  }

  Component.onCompleted: DrawerLink.publish(drawer)
  Component.onDestruction: DrawerLink.withdraw(drawer)
}
