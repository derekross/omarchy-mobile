// SPDX-License-Identifier: MIT
import QtQuick
import "layout.js" as Layout

// Draws one OWL render tree (runtime.js render()) in the space it is given.
// layout.js places every node; this keeps one item per node, keyed by its
// place in the tree (and a `for`'s key), and updates them in place, so a
// source that changes a number redraws that number and nothing is rebuilt.
//
// No Quickshell types here: the conformance harness loads it in plain
// qml6, offscreen (tests/owl/render/).
Item {
  id: view

  property var tree: null
  // Theme names to "#aarrggbb" for the defaults nodes draw with
  // (foreground, muted, accent, surface, border, background).
  property var colors: ({})
  property real dp: 1
  property real corners: 0
  property string monoFamily: "monospace"
  property string sansFamily: "sans-serif"
  property string iconFamily: view.monoFamily
  property string homeDir: ""
  property bool interactive: true
  // Starts a Terminal node's session: start(command, onOutput, onExit) ->
  // { write(text), stop() }. Set by the host; null: terminals stay empty.
  property var terminals: null
  // Bumped by the scheduler (30 fps at most) while something animates.
  property int frame: 0
  // Milliseconds spent laying out and painting since the scheduler last
  // asked (takeWork()): what a frame costs after the widget's own JS, so a
  // heavy Canvas drops to half rate.
  property real workMs: 0
  function addWork(ms) { view.workMs += Math.max(0, ms) }
  function takeWork() { const ms = view.workMs; view.workMs = 0; return ms }
  readonly property real devicePixelRatio: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1

  property int inkVersion: 0
  onColorsChanged: { view.inkVersion++; view.schedule() }

  // A node reads `time` (the tree or a Canvas): the scheduler runs frames.
  readonly property bool animating: (!!view.tree && view.tree.readsTime === true) || view.animatingCount > 0
  property int animatingCount: 0
  property var animatingItems: ({})

  // Handlers the nodes call; the widget wires them to its instance.
  signal handlerRun(var handler, var args)
  signal keyboardWanted(bool on)

  function tapped(handler, x, y) { if (view.interactive && handler) view.handlerRun(handler, [x, y]) }
  function dragged(handler, dx, dy, x, y) { if (view.interactive && handler) view.handlerRun(handler, [dx, dy, x, y]) }
  function changedValue(handler, value) { if (view.interactive && handler) view.handlerRun(handler, [value]) }
  function fieldFocused(on) { view.keyboardWanted(on) }

  function ink(name) {
    const v = view.colors ? view.colors[name] : null
    return v ? v : "#ff888888"
  }
  function family(font) {
    if (font === "sans") return view.sansFamily
    if (font === "serif") return "serif"
    if (font === "icon") return view.iconFamily
    return view.monoFamily
  }
  // Local pictures only: ~/..., /..., or an embedded asset (data:).
  function imageUrl(src) {
    if (src === undefined || src === null) return ""
    const s = String(src)
    if (s.indexOf("~/") === 0) return view.homeDir ? "file://" + view.homeDir + s.slice(1) : ""
    if (s.charAt(0) === "/") return "file://" + s
    if (s.indexOf("data:image/") === 0) return s
    return ""
  }

  function noteAnimating(item, on) {
    const id = String(item)
    const next = Object.assign({}, view.animatingItems)
    if (on) next[id] = true
    else delete next[id]
    view.animatingItems = next
    view.animatingCount = Object.keys(next).length
  }

  // ---------------------------------------------------------------- measuring

  FontMetrics { id: monoMetrics; font.family: view.monoFamily; font.pixelSize: 100 }
  FontMetrics { id: monoBoldMetrics; font.family: view.monoFamily; font.pixelSize: 100; font.bold: true }
  FontMetrics { id: sansMetrics; font.family: view.sansFamily; font.pixelSize: 100 }
  FontMetrics { id: iconMetrics; font.family: view.iconFamily; font.pixelSize: 100 }

  // Pictures' own sizes (dp), learnt as they load, for layout.
  property var imageSizes: ({})
  function noteImage(src, w, h) {
    if (w <= 0 || h <= 0) return
    const known = view.imageSizes[src]
    if (known && known[0] === w / view.dp && known[1] === h / view.dp) return
    const next = Object.assign({}, view.imageSizes)
    next[src] = [w / view.dp, h / view.dp]
    view.imageSizes = next
    view.schedule()
  }

  property var widthCache: ({})
  readonly property var measure: ({
    width: function(text, size, bold, font) {
      const key = (bold ? "b" : "") + (font || "") + "|" + text
      let at100 = view.widthCache[key]
      if (at100 === undefined) {
        const m = font === "icon" ? iconMetrics : font === "sans" || font === "serif" ? sansMetrics : bold ? monoBoldMetrics : monoMetrics
        at100 = m.advanceWidth(text)
        view.widthCache[key] = at100
      }
      // Text draws at whole pixel sizes (OwlText), so measure at those.
      return at100 * Math.max(1, Math.round(size * view.dp)) / 100 / view.dp
    },
    // Lines are 1.17 em of the whole-pixel font size text is drawn at.
    lineHeight: function(size) { return Math.max(1, Math.round(size * view.dp)) * 1.17 / view.dp },
    fontHeight: function(size) { return monoMetrics.height * size / 100 },
    pixel: view.dp,
    image: function(src) { return view.imageSizes[String(src)] || null }
  })

  // ---------------------------------------------------------------- items

  property var boxes: null
  property var items: ({})
  readonly property var kinds: ({
    Column: "OwlBlock.qml", Row: "OwlBlock.qml", Flow: "OwlBlock.qml", Box: "OwlBlock.qml", Grid: "OwlBlock.qml",
    Spacer: "OwlBlock.qml", Text: "OwlText.qml", Button: "OwlButton.qml", Progress: "OwlProgress.qml",
    Ring: "OwlRing.qml", Sparkline: "OwlSparkline.qml", Canvas: "OwlCanvas.qml", Image: "OwlImage.qml",
    Shader: "OwlShader.qml", Terminal: "OwlTerminal.qml", Slider: "OwlSlider.qml", Input: "OwlInput.qml"
  })
  property var components: ({})

  function componentFor(kind) {
    const file = view.kinds[kind] || "OwlBlock.qml"
    if (!view.components[file]) {
      const c = Qt.createComponent(Qt.resolvedUrl(file))
      if (c.status !== Component.Ready) console.warn("owl: " + file + ": " + c.errorString())
      view.components[file] = c
    }
    return view.components[file]
  }

  function schedule() { Qt.callLater(view.rebuild) }
  onTreeChanged: view.schedule()
  onWidthChanged: view.schedule()
  onHeightChanged: view.schedule()
  onDpChanged: { view.widthCache = ({}); view.schedule() }
  onMonoFamilyChanged: { view.widthCache = ({}); view.schedule() }

  function rebuild() {
    const began = Date.now()
    const seen = {}
    if (view.tree && view.width > 0 && view.height > 0 && view.dp > 0) {
      view.boxes = Layout.layout(view.tree.children || [], view.width / view.dp, view.height / view.dp, view.measure)
      view.place(view.boxes, view, seen, 0)
    } else {
      view.boxes = null
    }
    const keep = {}
    for (const key in view.items) {
      if (seen[key]) keep[key] = view.items[key]
      else view.items[key].destroy()
    }
    view.items = keep
    view.addWork(Date.now() - began)
  }

  function place(box, parentItem, seen, z) {
    const key = String(box.key) + "|" + box.kind
    let item = view.items[key]
    if (!item) {
      item = view.componentFor(box.kind).createObject(parentItem, { view: view, box: box })
      if (!item) return
      view.items[key] = item
    } else {
      if (item.parent !== parentItem) item.parent = parentItem
      item.box = box
    }
    item.z = z
    seen[key] = true
    for (let i = 0; i < box.children.length; i++) view.place(box.children[i], item.container, seen, i)
  }

  // Every node's box on the tile, in dp: the L4 conformance dump.
  function dump() { return view.boxes ? Layout.flatten(view.boxes) : [] }
}
