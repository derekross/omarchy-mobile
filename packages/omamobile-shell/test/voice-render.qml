// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "omamobile.voice" as V

// Offscreen review shots of the voice bar (test/voice-render): the real
// Voice.qml at the phone's 480x1040 logical px and on its side, each state
// in $VOICE_JOB set by hand (nothing runs Voxtype), above a stand-in for
// what sits under it (the keyboard and the strip, the strip, the dock),
// saved as a PNG with the bar's, the chip's, the list's and every button's
// geometry printed for the checks. Then it quits.
ShellRoot {
  id: harness

  FileView { id: jobFile; path: Quickshell.env("VOICE_JOB"); blockLoading: true }
  readonly property var job: JSON.parse(jobFile.text())
  // The daemon state file Voice.qml follows, written for each shot.
  FileView { id: voxState; path: Quickshell.env("XDG_RUNTIME_DIR") + "/voxtype/state"; printErrors: false }
  property int index: -1
  readonly property var shot: harness.index >= 0 && harness.index < harness.job.shots.length ? harness.job.shots[harness.index] : null

  FloatingWindow {
    id: win
    implicitWidth: 1040
    implicitHeight: 1040
    color: "black"

    Item {
      id: screen
      width: harness.shot ? harness.shot.w : 480
      height: harness.shot ? harness.shot.h : 1040

      // An app under the bar: a conversation, so the bar reads against it.
      Rectangle { anchors.fill: parent; color: Commons.Color.background
        Column { x: 16; y: 70; spacing: 12
          Repeater { model: 6
            Rectangle { required property int index; width: 220 + (index % 3) * 40; height: 44; color: index % 2 ? Commons.Color.accent : Commons.Color.muted; opacity: 0.6 } } } }

      // The status bar above (it reserves its space).
      Rectangle { width: parent.width; height: 44; color: Commons.Color.bar.background
        Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "21:44"; color: Commons.Color.bar.text; font.family: Style.font.family; font.pixelSize: 15 } }

      // What sits under the bar: the keyboard over the strip, the strip, or
      // the dock, with the pill.
      Rectangle {
        visible: !!harness.shot && harness.shot.below > 0
        anchors.bottom: parent.bottom
        width: parent.width
        height: harness.shot ? harness.shot.below : 0
        color: Commons.Color.bar.background
        Text {
          anchors.centerIn: parent
          visible: !!harness.shot && harness.shot.below > 100
          text: harness.shot && harness.shot.below > 200 ? "keyboard" : "search apps"
          color: Commons.Color.muted
          font.family: Style.font.family
          font.pixelSize: 18
        }
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 19; width: 120; height: 6; radius: 3; color: Qt.rgba(1, 1, 1, 0.9) }
      }

      V.Voice {
        id: voice
        y: 44
        width: screen.width
        height: screen.height - 44 - (harness.shot ? harness.shot.below : 0)
      }
    }
  }

  function rectOf(item) {
    var p = item.mapToItem(screen, 0, 0)
    return { x: Math.round(p.x), y: Math.round(p.y), w: Math.round(item.width), h: Math.round(item.height) }
  }

  function describe(item, out) {
    if (!item || !item.visible || item.opacity === 0) return out
    if (item.objectName) out.parts[item.objectName] = harness.rectOf(item)
    if (item.label !== undefined && item.primary !== undefined) out.buttons.push(Object.assign({ label: String(item.label) }, harness.rectOf(item)))
    if (item.text !== undefined && String(item.text).indexOf("presses Enter") >= 0) out.hint = String(item.text)
    for (var i = 0; i < item.children.length; i++) harness.describe(item.children[i], out)
    return out
  }

  function next() {
    harness.index++
    if (harness.index >= harness.job.shots.length) { Qt.quit(); return }
    var s = harness.shot
    voice.reset()
    voice.agentId = "claude"
    voice.modelId = "tiny.en"
    voice.levels = [0.1, 0.3, 0.6, 0.9, 0.5, 0.7, 0.3, 0.6, 0.8, 0.4, 0.2, 0.6, 0.9, 0.4, 0.15, 0.5, 0.7, 0.3]
    voice.listenStart = Date.now() - 4000
    voice.elapsed = 4
    voice.spoke = 6
    var vox = "idle"
    if (s.state === "settings") {
      voice.installed = ["tiny.en", "base.en"]
      voice.settingsOpen = true
      voice.opened = true
    } else {
      voice.opened = false
      voice.settingsOpen = false
      voice.mine = true
      if (s.state === "type" || s.state === "agent" || s.state === "home") {
        voice.dest = s.state === "home" ? "ask" : s.state
        voice.phase = "listening"
        voice.chooserOpen = s.state === "home"
        vox = "recording"
      } else if (s.state === "transcribing") {
        voice.dest = "type"
        voice.phase = "transcribing"
        vox = "transcribing"
      } else if (s.state === "error") {
        voice.dest = "ask"
        voice.errorText = "Didn't catch that. Try again, a little closer to the phone."
        voice.phase = "error"
      } else {
        voice.dest = "ask"
        voice.phase = "transcribing"
        voice.readTries = 9
        voice.applyTranscript(harness.job.transcript)
      }
    }
    voxState.setText(vox + "\n")
    settle.restart()
  }

  Timer { id: settle; interval: 1500; onTriggered: harness.capture() }

  function capture() {
    var s = harness.shot
    var out = harness.describe(voice, { parts: {}, buttons: [], hint: "" })
    var area = harness.rectOf(voice)
    console.log("geometry " + s.name + " " + screen.width + "x" + screen.height + " " +
                JSON.stringify({ parts: out.parts, buttons: out.buttons, hint: out.hint, state: s.state, area: area }))
    screen.grabToImage(function(result) {
      result.saveToFile(s.png)
      console.log("shot " + s.png)
      Qt.callLater(harness.next)
    })
  }

  Timer { interval: 800; running: true; onTriggered: harness.next() }
}
