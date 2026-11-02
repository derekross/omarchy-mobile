// SPDX-License-Identifier: MIT
// dodge: turn the screen off after inactivity, no lock (Martin's choice
// for now). A separate Quickshell instance next to omarchy-shell. After
// OMAMOBILE_IDLE_OFF_SECONDS (default 150) without input it runs
// `omarchy-brightness-display off` (DPMS off plus bl_power 4); the first
// input after that (touch, key) runs `omarchy-brightness-display on`.
// Honours idle inhibitors (video, `noidle` windows) and Omarchy's
// stay-awake toggle.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
  id: root
  readonly property int seconds: {
    var v = parseInt(Quickshell.env("OMAMOBILE_IDLE_OFF_SECONDS") || "150")
    return v > 0 ? v : 150
  }
  property bool turnedOff: false

  function run(cmd) {
    proc.command = ["bash", "-lc", cmd]
    proc.running = true
  }

  IdleMonitor {
    id: monitor
    timeout: root.seconds
    respectInhibitors: true
    onIsIdleChanged: {
      if (isIdle) {
        console.log("omamobile-idle-off: idle " + root.seconds + " s, screen off")
        root.turnedOff = true
        root.run("[[ -f $HOME/.local/state/omarchy/indicators/stay-awake ]] && exit 0; omarchy-brightness-display off")
      } else if (root.turnedOff) {
        console.log("omamobile-idle-off: activity, screen on")
        root.turnedOff = false
        root.run("omarchy-brightness-display on")
      }
    }
  }

  Process { id: proc }

  Component.onCompleted: console.log("omamobile-idle-off: ready, " + root.seconds + " s")
}
