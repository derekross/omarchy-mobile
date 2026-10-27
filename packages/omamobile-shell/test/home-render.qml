// SPDX-License-Identifier: MIT
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "home" as Home

// Offscreen review shots of the home screen (test/home-render): the real
// Home.qml at the phone's 480x1040 logical px and on its side at 1040x480,
// between a status bar and a dock drawn as stand-ins, each shot in $HOME_JOB
// saved as a PNG with the items' geometry printed for the checks. Its OWL
// widgets get a host that answers from the job's fixtures. Then it quits.
ShellRoot {
  id: harness

  FileView { id: jobFile; path: Quickshell.env("HOME_JOB"); blockLoading: true }
  readonly property var job: JSON.parse(jobFile.text())
  property int index: -1
  readonly property var shot: harness.index >= 0 && harness.index < harness.job.shots.length ? harness.job.shots[harness.index] : null

  // The fixture for a widget, by the id its state key starts with.
  function fixtureFor(widget) {
    var key = String(widget && widget.stateKey ? widget.stateKey : "")
    for (var id in harness.job.widgets) if (key.indexOf(id + "@") === 0) return harness.job.widgets[id]
    return null
  }

  // What OwlPhoneHost does on the phone, answered from the fixtures: no
  // command, request, file or action runs.
  readonly property var fixtureHost: ({
    now: function() { return harness.job.time },
    interval: function(spec) { return spec.every },
    runSource: function(widget, spec, arg, headers, done) {
      var fx = harness.fixtureFor(widget)
      var e = fx && fx.sources ? fx.sources[spec.name] : null
      if (!e) { done({ error: "no fixture for " + spec.name }); return }
      if (e.value !== undefined) done({ value: e.value })
      else done({ code: 0, ok: true, out: String(e.text), err: "" })
    },
    android: function(widget, kind, done) {
      var fx = harness.fixtureFor(widget)
      done({ value: fx && fx.android && fx.android[kind] !== undefined ? fx.android[kind] : null })
    },
    act: function() {},
    runInto: function(widget, text, done) { done("") },
    stream: function() { return null },
    watch: function() { return { stop: function() {} } },
    loadState: function() { return ({}) },
    saveState: function() {},
    report: function(widget, message) { console.log("owl report " + widget.stateKey + ": " + message) },
    terminalFor: function() { return { start: function() { return { write: function() {}, stop: function() {} } } } }
  })

  // The host's application library: names from the desktop entries, icons
  // from the job.
  readonly property var library: ({
    iconSource: function(icon) { var p = harness.job.icons[String(icon)]; return p ? "file://" + p : "" },
    entryName: function(entry) { return entry ? String(entry.name || entry.id || "") : "" },
    beginLaunchFeedback: function() {}
  })

  FloatingWindow {
    id: win
    implicitWidth: 1040
    implicitHeight: 1040
    color: "black"

    Item {
      id: screen
      width: harness.shot ? harness.shot.w : 480
      height: harness.shot ? harness.shot.h : 1040

      // Wallpaper stand-in: the theme's background with a little accent.
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0; color: Commons.Color.background }
          GradientStop { position: 1; color: Qt.tint(Commons.Color.background, Util.alpha(Commons.Color.accent, 0.25)) }
        }
      }

      // Status bar stand-in.
      Rectangle {
        width: parent.width
        height: 44
        color: Commons.Color.bar.background
        Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "13:27"; color: Commons.Color.bar.text; font.family: Style.font.family; font.pixelSize: 15 }
        Text { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: "󰁹 80%"; color: Commons.Color.bar.text; font.family: Style.font.family; font.pixelSize: 15 }
      }

      Home.Home {
        id: home
        y: 44
        width: screen.width
        height: screen.height - 44 - 72
        shell: ({ appLibrary: harness.library })
        Component.onCompleted: home.owlHost = harness.fixtureHost
      }

      // Dock stand-in: the launcher's search pill.
      Rectangle {
        y: parent.height - 72
        width: parent.width
        height: 72
        color: Commons.Color.bar.background
        Rectangle {
          anchors.fill: parent
          anchors.margins: 12
          color: "transparent"
          border.width: 1
          border.color: Util.alpha(Commons.Color.bar.text, 0.4)
          radius: Style.cornerRadius
          Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "󰍉  Search apps…"; color: Util.alpha(Commons.Color.bar.text, 0.6); font.family: Style.font.family; font.pixelSize: 15 }
        }
      }
    }
  }

  // ---------------------------------------------------------------- geometry

  function rectOf(item) {
    var p = item.mapToItem(screen, 0, 0)
    return { x: Math.round(p.x), y: Math.round(p.y), w: Math.round(item.width), h: Math.round(item.height) }
  }

  // The Text nodes of an OWL view's box tree, in screen px (layout.js's
  // flatten, with the text).
  function owlTexts(box, ox, oy, dp, origin, out) {
    var p = box.node && box.node.p ? box.node.p : ({})
    var off = Array.isArray(p.offset) ? p.offset : [0, 0]
    var x = ox + box.x + (Number(off[0]) || 0), y = oy + box.y + (Number(off[1]) || 0)
    var visible = p.visible === undefined || p.visible === null || p.visible === true
    if (!visible) return out
    if (box.kind === "Text")
      out.push({ x: Math.round(origin.x + x * dp), y: Math.round(origin.y + y * dp), w: Math.round(box.w * dp), h: Math.round(box.h * dp),
                 text: String(p.text === undefined || p.text === null ? "" : p.text).slice(0, 40) })
    for (var i = 0; i < box.children.length; i++) owlTexts(box.children[i], x, y, dp, origin, out)
    return out
  }

  // Walks the home item: its cells on the shown page (with the OWL text
  // rows under each) and the named parts.
  function collect(item, out, cell) {
    if (!item || !item.visible) return
    if (item.modelData !== undefined && item.isWidget !== undefined && item.owner !== undefined && item.owner) {
      if (item.owner.index !== home.currentPage) return
      cell = { id: item.modelData.id, kind: item.modelData.kind, type: item.modelData.type || item.modelData.app, rect: harness.rectOf(item), texts: [] }
      out.cells.push(cell)
    }
    if (cell && item.boxes !== undefined && typeof item.dump === "function" && item.boxes)
      harness.owlTexts(item.boxes, 0, 0, item.dp, item.mapToItem(screen, 0, 0), cell.texts)
    if (item.objectName) out.named[item.objectName] = harness.rectOf(item)
    for (var i = 0; i < item.children.length; i++) harness.collect(item.children[i], out, cell)
  }

  function next() {
    harness.index++
    if (harness.index >= harness.job.shots.length) { Qt.quit(); return }
    var s = harness.shot
    // The screen's size, as the surface's PanelWindow would report it.
    if (home.screenInfo !== undefined) home.screenInfo = { width: s.w, height: s.h }
    home.sheet = ""
    home.setEditing(false)
    Qt.callLater(function() {
      home.goToPage(s.page || 0, false)
      if (s.sheet) home.showSheet(s.sheet)
      if (s.hold) hold.restart()
      settle.restart()
    })
  }

  Timer { id: settle; interval: 3000; onTriggered: harness.capture() }
  // A long press a second before the shot: its notice shows for about two.
  Timer { id: hold; interval: 2000; onTriggered: home.requestEdit() }

  function capture() {
    var s = harness.shot
    var out = { w: screen.width, h: screen.height, landscape: home.landscape === true, grid: home.viewLayout ? home.viewLayout.grid : home.layout.grid,
                pages: home.viewLayout ? home.viewLayout.pages.length : home.layout.pages.length, page: home.currentPage,
                sheet: s.sheet || "", hold: s.hold === true, cells: [], named: {} }
    harness.collect(home, out, null)
    console.log("geometry " + s.name + " " + JSON.stringify(out))
    screen.grabToImage(function(result) {
      result.saveToFile(s.png)
      console.log("shot " + s.png)
      Qt.callLater(harness.next)
    })
  }

  // The layout file is read once the config directory exists (a process):
  // a moment for that, the widget scan and the widgets' first render.
  Timer { interval: 2500; running: true; onTriggered: harness.next() }
}
