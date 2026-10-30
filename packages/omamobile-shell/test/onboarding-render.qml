// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "onboarding" as O

// Offscreen review shots of the setup sheet (test/onboarding-render): the
// real Onboarding.qml at the phone's 480x1040 logical px and on its side
// at 1040x480, each page in $SETUP_JOB set from the job's made-up status
// (nothing runs omamobile-onboarding or omamobile-set-pin), saved as a PNG
// with the card's, the header's, the fields' and every button's geometry
// printed for the checks. Then it quits.
ShellRoot {
  id: harness

  FileView { id: jobFile; path: Quickshell.env("SETUP_JOB"); blockLoading: true }
  readonly property var job: JSON.parse(jobFile.text())
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

      // The status bar above the sheet (it reserves its space).
      Rectangle { width: parent.width; height: 44; color: Commons.Color.bar.background
        Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "13:27"; color: Commons.Color.bar.text; font.family: Style.font.family; font.pixelSize: 15 } }

      O.Onboarding {
        id: setup
        y: 44
        width: screen.width
        height: screen.height - 44
      }
    }
  }

  function rectOf(item) {
    var p = item.mapToItem(screen, 0, 0)
    return { x: Math.round(p.x), y: Math.round(p.y), w: Math.round(item.width), h: Math.round(item.height) }
  }

  // The named parts, the buttons (anything with a label and `primary`) and
  // the fields (anything with a placeholder) that are shown.
  function describe(item, out) {
    if (!item || !item.visible || item.opacity === 0) return out
    if (item.objectName) out.parts[item.objectName] = harness.rectOf(item)
    if (item.label !== undefined && item.primary !== undefined) out.buttons.push(Object.assign({ label: String(item.label) }, harness.rectOf(item)))
    if (item.placeholderText !== undefined) out.fields.push(Object.assign({ placeholder: String(item.placeholderText) }, harness.rectOf(item)))
    for (var i = 0; i < item.children.length; i++) harness.describe(item.children[i], out)
    return out
  }

  function next() {
    harness.index++
    if (harness.index >= harness.job.shots.length) { Qt.quit(); return }
    var s = harness.shot
    setup.opened = true
    setup.flow = s.flow || "onboarding"
    setup.info = s.status || harness.job.status
    setup.infoLoaded = true
    setup.type = s.type || "pin"
    setup.changed = s.changed === true
    setup.entryError = s.error || ""
    setup.page = s.page
    if (s.page === "pin-entry") { setup.step = s.step || "new"; setup.digits = setup.type !== "password" }
    settle.restart()
  }

  Timer { id: settle; interval: 1500; onTriggered: harness.capture() }

  function capture() {
    var s = harness.shot
    var out = harness.describe(setup, { parts: {}, buttons: [], fields: [] })
    console.log("geometry " + s.name + " " + screen.width + "x" + screen.height + " " + JSON.stringify({ parts: out.parts, buttons: out.buttons, fields: out.fields, page: setup.page, step: setup.step }))
    screen.grabToImage(function(result) {
      result.saveToFile(s.png)
      console.log("shot " + s.png)
      Qt.callLater(harness.next)
    })
  }

  Timer { interval: 800; running: true; onTriggered: harness.next() }
}
