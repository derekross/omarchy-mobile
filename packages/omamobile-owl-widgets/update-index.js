// SPDX-License-Identifier: MIT
// Builds index.json, the store index omamobile-owl-widgets ships, with our
// own OWL compiler (omamobile-shell's plugins/omamobile.home/owl/): for each
// widget the status lets ship, its id, name, author, description, category,
// version, language level, sizes, packages, the full commands list, the
// derived capabilities, and the sha256 of its file. Nothing is run.
// The index is committed with the package, so building the package needs
// no compiler: install only copies the files and checks their sha256.
// A widget we keep our own copy of in overrides/<author>/<name>/widget.owl
// (it diverges from the store: README.md) is indexed from that copy.
// Run it from the repository when the pinned commit, status.json or an
// override changes:
//
//   node update-index.js <store checkout> [owl runtime dir] [status.json] [overrides dir] > index.json
"use strict"
const fs = require("fs"), path = require("path"), crypto = require("crypto"), Module = require("module")
const store = process.argv[2]
const owlDir = process.argv[3] || path.join(__dirname, "../omamobile-shell/plugins/omamobile.home/owl")
const statusFile = process.argv[4] || path.join(__dirname, "status.json")
const overrides = process.argv[5] || path.join(__dirname, "overrides")

const cache = {}
function load(name) {
  if (cache[name]) return cache[name]
  const file = path.join(owlDir, name)
  const src = fs.readFileSync(file, "utf8").replace(/^\.pragma library[ \t]*$/m, "")
    .replace(/^\.import "([\w.-]+)" as (\w+)[ \t]*$/mg, (m, f, n) => `var ${n} = __owlLoad(${JSON.stringify(f)});`)
  const m = new Module(file)
  m.filename = file
  global.__owlLoad = load
  m._compile(src, file)
  cache[name] = m.exports
  return m.exports
}
const C = load("compiler.js"), P = load("phone.js")
const status = JSON.parse(fs.readFileSync(statusFile, "utf8"))

// The store's order (order.txt): listed ids first, in order; then the rest
// by name; the ids after "..." last.
function ordered(ids, orderText) {
  const lines = String(orderText || "").split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("#"))
  const cut = lines.indexOf("...")
  const first = (cut < 0 ? lines : lines.slice(0, cut)).filter((id) => ids.includes(id))
  const last = (cut < 0 ? [] : lines.slice(cut + 1)).filter((id) => ids.includes(id))
  const middle = ids.filter((id) => !first.includes(id) && !last.includes(id)).sort((a, b) => a.split("/")[1].localeCompare(b.split("/")[1]))
  return first.concat(middle, last)
}

const ids = []
for (const author of fs.readdirSync(path.join(store, "widgets")).sort())
  for (const name of fs.readdirSync(path.join(store, "widgets", author)).sort())
    if (fs.existsSync(path.join(store, "widgets", author, name, "widget.owl"))) ids.push(author + "/" + name)
const order = fs.existsSync(path.join(store, "order.txt")) ? fs.readFileSync(path.join(store, "order.txt"), "utf8") : ""

const widgets = []
for (const id of ordered(ids, order)) {
  const st = status.widgets[id] || { status: "unsupported", note: "not checked yet" }
  const ours = path.join(overrides, id, "widget.owl")
  const text = fs.readFileSync(fs.existsSync(ours) ? ours : path.join(store, "widgets", id, "widget.owl"), "utf8")
  const entry = { id, author: id.split("/")[0], status: st.status, note: st.note || "" }
  try {
    const p = C.compile(text)
    const caps = P.capabilities(p)
    const meta = p.meta || {}
    Object.assign(entry, {
      name: p.name, description: typeof meta.description === "string" ? meta.description : "",
      category: typeof meta.category === "string" ? meta.category : "", version: meta.version === undefined ? "" : String(meta.version),
      license: typeof meta.license === "string" ? meta.license : "", owl: p.level, size: p.size || [3, 2], minSize: p.minSize,
      requires: p.requires.pacman || [], commands: p.commands, capabilities: P.capabilityList(caps), hosts: caps.hosts,
      sha256: crypto.createHash("sha256").update(text).digest("hex")
    })
    if (caps.refusals.length) { entry.status = "unsupported"; entry.note = caps.refusals.join("; ") }
  } catch (e) {
    entry.status = "unsupported"
    entry.note = "doesn't compile here: " + (e && e.message)
  }
  widgets.push(entry)
}
const out = { version: 1, source: status.source || "", widgets }
process.stdout.write(JSON.stringify(out, null, 1) + "\n")
