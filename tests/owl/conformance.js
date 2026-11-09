// SPDX-License-Identifier: MIT
// OWL conformance, L1-L3 (docs/WIDGET-INTEROP-PLAN.md §7.1), inside the
// conformance container (tests/owl/Dockerfile; tools/owl-conformance runs it).
//
//   L1 compile        accepted or rejected alike, rejects at the same line:column
//   L2 capabilities   the same commands list, in the same order; the same
//                     capability set derived from it
//   L3 evaluation     the same walk JSON (numbers alike to 1e-9)
//
// The reference runtime is the pinned checkout under /ref, used as a black
// box: its compile() through tests/owl/oracle/ref-compile.js's loader and
// its own test walker. Nothing from it is written into this repository
// except its outputs, recorded as our expectations (--record).
//
//   node conformance.js [--record] [--live] [--all] --out DIR
"use strict"
const fs = require("fs"), path = require("path"), cp = require("child_process"), Module = require("module")
const HERE = __dirname
const { load } = require(path.resolve(HERE, "../../packages/omamobile-shell/test/owl-load.js"))
const { walk } = require(path.resolve(HERE, "../../packages/omamobile-shell/test/owl-walk.js"))
const C = load("compiler.js"), P = load("phone.js")
const G = require("./geometry.js")
const cases = require("./cases.json")

const REF = "/ref/omarchy-widgets"
const REF_RUNTIME = REF + "/runtimes/quickshell"
const args = process.argv.slice(2)
const record = args.includes("--record")
const live = record || args.includes("--live")
const all = args.includes("--all")
const outDir = args.includes("--out") ? args[args.indexOf("--out") + 1] : "/tmp/owl-conformance"
fs.mkdirSync(outDir, { recursive: true })
const expectedDir = path.join(HERE, "expected")

let refOwl = null
function reference() {
  if (refOwl) return refOwl
  const file = REF_RUNTIME + "/Owl.js"
  const m = new Module(file)
  m.filename = file
  m._compile(fs.readFileSync(file, "utf8").replace(/^\.pragma library/, "//"), file)
  refOwl = m.exports
  return refOwl
}

function lineCol(src, at) {
  const p = C.position(src, at)
  return p.line + ":" + p.column
}

// What a compiler says about a file, in a shape both sides share.
function summary(program) {
  // Derived from the commands list alone, by the same function on both
  // sides (the vibration and torch asks come from our compiler's actions,
  // which the reference doesn't list).
  const caps = P.capabilities(program)
  caps.devices = []
  return { ok: true, name: program.name, size: program.size || null, minSize: program.minSize || null,
           commands: program.commands, requires: program.requires,
           capabilities: P.capabilityList(caps) }
}
function ours(src) {
  try { return summary(C.compile(src)) } catch (e) {
    if (!(e instanceof C.CompileError)) return { ok: false, at: "internal", message: String(e && e.stack || e) }
    return { ok: false, at: lineCol(src, e.at), message: e.message }
  }
}
function theirs(src) {
  const Owl = reference()
  try { return summary(Owl.compile(src)) } catch (e) {
    return { ok: false, at: typeof e.pos === "number" ? lineCol(src, e.pos) : "?", message: String(e.message) }
  }
}
function theirWalk(file, fixtureFile) {
  const r = cp.spawnSync("node", ["walk.js", "../Owl.js", file, fixtureFile], { cwd: REF_RUNTIME + "/test", encoding: "utf8", env: Object.assign({}, process.env, { TZ: "Europe/Berlin" }) })
  if (r.status !== 0) return { error: (r.stderr || "").split("\n").slice(-4).join(" ") }
  return JSON.parse(r.stdout)
}
function ourWalk(src, fixture) {
  try { return JSON.parse(walk(src, fixture)) } catch (e) { return { error: String(e && e.message || e) } }
}

// The reference's own rule for "the same JSON": numbers within 1e-9
// (relative), and strings equal word for word with their numbers close.
function close(x, y) { return Math.abs(x - y) <= 1e-9 * Math.max(1, Math.abs(x), Math.abs(y)) }
function parts(s) { return s.split(/(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)/) }
function same(a, b) {
  if (typeof a === "number" && typeof b === "number") return close(a, b)
  if (typeof a === "string" && typeof b === "string") {
    if (a === b) return true
    const p = parts(a), q = parts(b)
    return p.length === q.length && p.every((s, i) => i % 2 ? close(+s, +q[i]) : s === q[i])
  }
  if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((v, i) => same(v, b[i]))
  if (a && b && typeof a === "object" && typeof b === "object") {
    const k = Object.keys(a)
    return k.length === Object.keys(b).length && k.every((n) => n in b && same(a[n], b[n]))
  }
  return a === b
}
// A value for the report; a member one side lacks is undefined, which
// JSON.stringify returns as undefined rather than as text.
function shown(v) { return v === undefined ? "(missing)" : JSON.stringify(v).slice(0, 160) }
// The first place two walks differ, for the report.
function firstDifference(a, b, at) {
  at = at || "$"
  if (same(a, b)) return null
  if (a && b && typeof a === "object" && typeof b === "object") {
    const keys = Array.from(new Set(Object.keys(a).concat(Object.keys(b))))
    for (const k of keys) {
      const d = firstDifference(a[k], b[k], at + (Array.isArray(a) ? "[" + k + "]" : "." + k))
      if (d) return d
    }
  }
  return { at, expected: shown(a), ours: shown(b) }
}

function compileMatch(exp, got) {
  if (exp.ok !== got.ok) return { pass: false, why: exp.ok ? "we reject it: " + got.at + " " + got.message : "we accept what the reference rejects at " + exp.at }
  if (!exp.ok) return { pass: exp.at === got.at, why: exp.at === got.at ? "" : "rejected at " + got.at + ", reference at " + exp.at }
  for (const k of ["name", "size", "minSize"]) if (!same(exp[k], got[k])) return { pass: false, why: k + " differs" }
  return { pass: true, why: "" }
}
function capsMatch(exp, got) {
  if (!exp.ok || !got.ok) return { pass: exp.ok === got.ok, why: "" }
  if (!same(exp.commands, got.commands)) return { pass: false, why: "commands differ: " + JSON.stringify(firstDifference(exp.commands, got.commands)) }
  if (!same(exp.capabilities, got.capabilities)) return { pass: false, why: "capabilities differ" }
  return { pass: true, why: "" }
}

const report = { date: new Date().toISOString(), reference: "", cases: [], store: null, probes: [], themes: [] }
try { report.reference = cp.execSync("git -c safe.directory='*' -C " + REF + " log --format='%h %cs' -1", { encoding: "utf8" }).trim() } catch (e) { report.reference = "unknown" }

// ---------------------------------------------------------------- the milestone's widgets
for (const c of cases.widgets) {
  const file = path.join(REF, "widgets", c.id, "widget.owl")
  const src = fs.readFileSync(file, "utf8")
  const fixtureFile = path.join(HERE, "fixtures", c.id.replace("/", ".") + ".json")
  const fixture = JSON.parse(fs.readFileSync(fixtureFile, "utf8"))
  const base = path.join(expectedDir, c.id.replace("/", "."))
  let expCompile, expWalk
  if (live) {
    expCompile = theirs(src)
    expWalk = theirWalk(file, fixtureFile)
    if (record) {
      fs.mkdirSync(expectedDir, { recursive: true })
      fs.writeFileSync(base + ".compile.json", JSON.stringify(expCompile, null, 1) + "\n")
      fs.writeFileSync(base + ".walk.json", JSON.stringify(expWalk) + "\n")
    }
  } else {
    expCompile = JSON.parse(fs.readFileSync(base + ".compile.json", "utf8"))
    expWalk = JSON.parse(fs.readFileSync(base + ".walk.json", "utf8"))
  }
  const gotCompile = ours(src)
  const gotWalk = ourWalk(src, fixture)
  const l1 = compileMatch(expCompile, gotCompile)
  const l2 = capsMatch(expCompile, gotCompile)
  const d = firstDifference(expWalk, gotWalk)
  fs.writeFileSync(path.join(outDir, c.id.replace("/", ".") + ".ours.walk.json"), JSON.stringify(gotWalk) + "\n")
  report.cases.push({ id: c.id, covers: c.covers, cells: fixture.cells, l1, l2, l3: { pass: !d, why: d ? JSON.stringify(d) : "" },
                      commands: gotCompile.commands || [], capabilities: gotCompile.capabilities || [] })
}

// ---------------------------------------------------------------- every store widget, no data (live only)
if (all) {
  const store = { total: 0, l1: 0, l2: 0, l3: 0, failures: [] }
  const blank = { theme: JSON.parse(fs.readFileSync(path.join(HERE, "fixtures", "simonschubert.calendar.json"), "utf8")).theme,
                  time: 12.5, canvas: [300, 200], sources: {},
                  tile: { cols: 3, rows: 3, tileWidth: 300, tileHeight: 280, screenWidth: 400, screenHeight: 860, linux: true, corners: 0 } }
  const blankFile = path.join(outDir, "blank.fixture.json")
  fs.writeFileSync(blankFile, JSON.stringify(blank))
  for (const author of fs.readdirSync(path.join(REF, "widgets")).sort()) {
    for (const name of fs.readdirSync(path.join(REF, "widgets", author)).sort()) {
      const file = path.join(REF, "widgets", author, name, "widget.owl")
      if (!fs.existsSync(file)) continue
      const src = fs.readFileSync(file, "utf8")
      store.total++
      const e = theirs(src), g = ours(src)
      const l1 = compileMatch(e, g), l2 = capsMatch(e, g)
      const d = firstDifference(theirWalk(file, blankFile), ourWalk(src, blank))
      if (l1.pass) store.l1++
      if (l2.pass) store.l2++
      if (!d) store.l3++
      if (!l1.pass || !l2.pass || d) store.failures.push({ id: author + "/" + name, l1: l1.why, l2: l2.why, l3: d ? JSON.stringify(d) : "" })
    }
  }
  report.store = store
}

// ---------------------------------------------------------------- probes and bad widgets
const probeDir = path.resolve(HERE, "../../packages/omamobile-shell/test/owl-probes")
const probeFiles = fs.readdirSync(probeDir).filter((n) => n.endsWith(".owl")).sort()
  .concat(fs.readdirSync(path.join(probeDir, "bad")).filter((n) => n.endsWith(".owl")).sort().map((n) => "bad/" + n))
for (const f of probeFiles) {
  const file = path.join(probeDir, f)
  const src = fs.readFileSync(file, "utf8")
  const fixtureFile = path.join(probeDir, "fixture.json")
  const fixture = JSON.parse(fs.readFileSync(fixtureFile, "utf8"))
  const expFile = file.replace(/\.owl$/, ".expected.json")
  let exp
  if (live) {
    const c = theirs(src)
    exp = { compile: c, walk: c.ok ? theirWalk(file, fixtureFile) : null }
    if (record) fs.writeFileSync(expFile, JSON.stringify(exp, null, 1) + "\n")
  } else exp = JSON.parse(fs.readFileSync(expFile, "utf8"))
  const g = ours(src)
  const l1 = compileMatch(exp.compile, g)
  const d = exp.walk ? firstDifference(exp.walk, ourWalk(src, fixture)) : null
  report.probes.push({ probe: f, l1, l2: capsMatch(exp.compile, g), l3: { pass: !d, why: d ? JSON.stringify(d) : "" } })
}

// ---------------------------------------------------------------- theme palettes
if (live && fs.existsSync("/themes")) {
  for (const t of fs.readdirSync("/themes").sort()) {
    const toml = path.join("/themes", t, "colors.toml")
    if (!fs.existsSync(toml)) continue
    const text = fs.readFileSync(toml, "utf8")
    const theirsP = reference().themeFromToml(text)
    const oursP = P.palette(P.parseColorsToml(text))
    const diff = Object.keys(theirsP).filter((k) => (theirsP[k] >>> 0) !== (oursP[k] >>> 0))
    report.themes.push({ theme: t, pass: diff.length === 0, differs: diff })
  }
}

fs.writeFileSync(path.join(outDir, "report.json"), JSON.stringify(report, null, 1) + "\n")
const n = (list, k) => list.filter((x) => x[k].pass).length
console.log("widgets: L1 " + n(report.cases, "l1") + "/" + report.cases.length + ", L2 " + n(report.cases, "l2") + "/" + report.cases.length + ", L3 " + n(report.cases, "l3") + "/" + report.cases.length)
for (const c of report.cases) if (!c.l1.pass || !c.l2.pass || !c.l3.pass) console.log("  not ok " + c.id + ": " + [c.l1.why, c.l2.why, c.l3.why].filter(Boolean).join("; "))
console.log("probes: L1 " + n(report.probes, "l1") + "/" + report.probes.length + ", L3 " + n(report.probes, "l3") + "/" + report.probes.length)
for (const c of report.probes) if (!c.l1.pass || !c.l3.pass) console.log("  not ok " + c.probe + ": " + [c.l1.why, c.l3.why].filter(Boolean).join("; "))
if (report.store) {
  console.log("store (" + report.store.total + " widgets, no data): L1 " + report.store.l1 + ", L2 " + report.store.l2 + ", L3 " + report.store.l3)
  for (const f of report.store.failures.slice(0, 40)) console.log("  not ok " + f.id + ": " + [f.l1, f.l2, f.l3].filter(Boolean).join("; ").slice(0, 300))
}
if (report.themes.length) console.log("themes: " + report.themes.filter((t) => t.pass).length + "/" + report.themes.length + " palettes match" +
  report.themes.filter((t) => !t.pass).map((t) => "\n  not ok " + t.theme + ": " + t.differs.join(", ")).join(""))
