// SPDX-License-Identifier: MIT
// Copyright (c) David Heinemeier Hansson
import QtQuick

// Focus prime adapted from Omarchy's Ui/KeyboardPanel.qml (MIT), present in
// both supported Omarchy families. See LICENSE.omarchy. OnDemand alone cannot
// acquire focus when an already-mapped Search window is opened again.
QtObject {
  id: root
  property bool opened: false
  property bool backingWindowVisible: false
  property bool focusPrimed: false
  property int requestGeneration: 0
  onRequestGenerationChanged: {
    if (opened) { focusPrimed = false; beginFocusPrime() }
  }
  readonly property string mode: !opened ? "none" : focusPrimed ? "on-demand" : "exclusive"
  readonly property bool inputReady: opened && backingWindowVisible && focusPrimed
  function beginFocusPrime() {
    if (opened && backingWindowVisible) focusPrimeTimer.restart()
  }
  onBackingWindowVisibleChanged: beginFocusPrime()
  onOpenedChanged: {
    focusPrimed = false
    if (opened) beginFocusPrime()
    else focusPrimeTimer.stop()
  }
  property Timer focusPrimeTimer: Timer {
    interval: 75
    onTriggered: if (root.opened) root.focusPrimed = true
  }
}
