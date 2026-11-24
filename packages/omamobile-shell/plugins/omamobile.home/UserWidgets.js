// SPDX-License-Identifier: MIT
// Pure logic for the user's own home-screen widgets: reading
// `omamobile-widget scan`, the catalog HomeModel sizes them by, the argv of
// every helper call, the prompt for the coding agent, settings values and
// the rules of WidgetHost.run(). Node runs it in test/home-model.js through
// the module.exports at the end, so nothing here touches QML.
//
// Folders, manifests and the code checks belong to bin/omamobile-widget;
// this side only reads its verdicts.

var PREFIX = "user:"
// Must match bin/omamobile-widget and HomeModel.USER_ID_RE (a test checks).
var ID_RE = /^[a-z0-9][a-z0-9_-]*(\.[a-z0-9][a-z0-9_-]*)*$/
var TOOL = "omamobile-widget"
var CONTRACT = "/usr/share/omamobile/shell/WIDGETS.md"

var MIN_INTERVAL_MS = 2000
var DEFAULT_TIMEOUT = 10
var MAX_TIMEOUT = 30
var MAX_OUTPUT = 65536

// ---------------------------------------------------------------- the scan

function emptyScan() {
  return { ok: false, dir: "", contract: CONTRACT, widgets: [], examples: [], error: "" }
}

// `omamobile-widget scan` output -> { ok, dir, widgets, examples, error }.
// Records keep the tool's fields: id, source, dir, status ("ok"/"error"),
// errors, warnings, hash, manifest (null when unusable), detected,
// undeclared, lint.
function parseScan(text) {
  var out = emptyScan()
  var raw
  try { raw = JSON.parse(String(text || "")) } catch (e) { out.error = "the widget scan failed"; return out }
  if (!raw || typeof raw !== "object" || !Array.isArray(raw.widgets)) { out.error = "the widget scan failed"; return out }
  out.ok = true
  out.dir = String(raw.dir || "")
  if (typeof raw.contract === "string" && raw.contract) out.contract = raw.contract
  out.widgets = raw.widgets.filter(validRecord).map(cleanRecord)
  out.examples = (Array.isArray(raw.examples) ? raw.examples : []).filter(validRecord).map(cleanRecord)
  return out
}

function validRecord(r) {
  return !!r && typeof r === "object" && typeof r.id === "string" && ID_RE.test(r.id)
}

function cleanRecord(r) {
  var m = r.manifest && typeof r.manifest === "object" ? r.manifest : null
  return {
    id: r.id,
    source: r.source === "example" ? "example" : "user",
    dir: String(r.dir || ""),
    status: r.status === "ok" && (m || (r.kind === "owl" && r.owl)) ? "ok" : "error",
    errors: strings(r.errors),
    warnings: strings(r.warnings),
    hash: String(r.hash || ""),
    manifest: m,
    detected: strings(r.detected),
    undeclared: strings(r.undeclared),
    // An OWL widget (widget.owl, no manifest): the home screen compiles it.
    kind: r.kind === "owl" ? "owl" : "qml",
    owl: r.kind === "owl" && r.owl && typeof r.owl.text === "string" ? { text: r.owl.text, sha256: String(r.owl.sha256 || "") } : null,
    // Where an OWL widget was copied from the store: { id, version, sha256 }.
    store: r.store && typeof r.store.id === "string" ? { id: r.store.id, version: String(r.store.version || ""), sha256: String(r.store.sha256 || "") } : null
  }
}

function strings(list) {
  return Array.isArray(list) ? list.map(function(s) { return String(s) }) : []
}

function findRecord(scan, id) {
  var list = scan && scan.widgets ? scan.widgets : []
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
  return null
}

function findExample(scan, id) {
  var list = scan && scan.examples ? scan.examples : []
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
  return null
}

// Specs in HomeModel.REGISTRY's shape, keyed by widget id: what sizes and
// settings a placed user widget gets. A widget with errors but a readable
// manifest keeps its sizes, so a broken edit doesn't reshape the page.
// OWL widgets take their spec from `owlSpecs` (id -> spec), which the home
// screen builds by compiling them (owl/catalog.js).
function catalog(scan, owlSpecs) {
  var out = {}
  ;(scan && scan.widgets ? scan.widgets : []).forEach(function(r) {
    if (r.kind === "owl") {
      if (owlSpecs && owlSpecs[r.id]) out[r.id] = owlSpecs[r.id]
      return
    }
    var m = r.manifest
    if (!m) return
    out[r.id] = {
      name: String(m.name || r.id), icon: String(m.icon || "󰕰"),
      min: pair(m.min, [1, 1]), max: pair(m.max, [6, 8]), size: pair(m.size, [2, 1]),
      network: (m.capabilities || []).indexOf("network") >= 0,
      capabilities: (m.capabilities || []).slice(),
      config: m.defaults && typeof m.defaults === "object" ? JSON.parse(JSON.stringify(m.defaults)) : {},
      schema: Array.isArray(m.schema) ? m.schema : [],
      user: true
    }
  })
  return out
}

function pair(value, fallback) {
  return Array.isArray(value) && value.length === 2 ? [Number(value[0]) || fallback[0], Number(value[1]) || fallback[1]] : fallback
}

function typeFor(id) { return PREFIX + id }
function idOf(type) { return typeof type === "string" && type.indexOf(PREFIX) === 0 ? type.slice(PREFIX.length) : "" }

// What a placed user widget shows: "ok" loads its QML; anything else is an
// error card with `message`.
function cardState(scan, id) {
  if (!scan || !scan.ok) return { state: "waiting", message: "Looking for your widgets…" }
  var r = findRecord(scan, id)
  if (!r) return { state: "missing", message: "No widget called " + id + " in ~/.config/omamobile/widgets" }
  if (r.status !== "ok") return { state: "error", message: r.errors.length ? r.errors.join("\n") : "This widget has an error" }
  return { state: "ok", message: "" }
}

// A folder as the user knows it: ~/.config/... rather than /home/<name>/...
function tildePath(path, home) {
  var p = String(path || ""), h = String(home || "").replace(/\/+$/, "")
  return h && (p === h || p.indexOf(h + "/") === 0) ? "~" + p.slice(h.length) : p
}

var CAPABILITY_WORDS = { commands: "runs commands", network: "uses the internet" }

function capabilityText(caps) {
  return (caps || []).map(function(c) { return CAPABILITY_WORDS[c] || c }).join(", ")
}

// The line under a user widget in the Widgets sheet.
function statusLine(r) {
  if (!r) return ""
  var m = r.manifest
  var parts = []
  if (m && m.size) parts.push(m.size[0] + "×" + m.size[1])
  if (r.undeclared.length) parts.push("⚠ " + capabilityText(r.undeclared) + " without declaring it")
  else if (r.status !== "ok") parts.push("⚠ " + (r.errors[0] || "has an error"))
  else if (m && m.capabilities && m.capabilities.length) parts.push(capabilityText(m.capabilities))
  return parts.join("  ·  ")
}

// ---------------------------------------------------------------- new widgets

function slug(text) {
  // Letters outside a-z (accents too) just separate words: ids stay ASCII.
  var words = String(text || "").toLowerCase()
  var parts = words.replace(/[^a-z0-9]+/g, " ").trim().split(/\s+/).filter(function(w) {
    return w && ["a", "an", "the", "that", "which", "with", "of", "for", "to", "and", "my", "me", "show", "shows", "widget"].indexOf(w) < 0
  }).slice(0, 3)
  var s = parts.join("-").slice(0, 32).replace(/-+$/, "")
  return s || "widget"
}

// A fresh id: <user>.<words from the description>, like Omarchy's own
// <username>.<name> for plugins a user makes, numbered when taken.
var RESERVED_OWNERS = ["omarchy", "omamobile", "omandroid"]

function newId(description, user, existing) {
  var owner = String(user || "").toLowerCase().replace(/[^a-z0-9_-]+/g, "").replace(/^[-_]+/, "").slice(0, 24) || "my"
  // omarchy.* and omamobile.* are the system's own ids (omamobile-widget
  // refuses them), and a phone's account may well be called omamobile.
  if (RESERVED_OWNERS.indexOf(owner) >= 0) owner = "my"
  var base = owner + "." + slug(description)
  var taken = {}
  ;(existing || []).forEach(function(id) { taken[id] = true })
  var id = base
  for (var n = 2; taken[id]; n++) id = base + "-" + n
  return id
}

function nameFrom(description) {
  var words = String(description || "").replace(/\s+/g, " ").trim().split(" ").slice(0, 4).join(" ")
  var name = words.charAt(0).toUpperCase() + words.slice(1)
  name = name.replace(/[.,;:!?]+$/, "")
  return (name.length > 40 ? name.slice(0, 39) + "…" : name) || "My widget"
}

// The agent's prompt. The description goes in verbatim; the whole prompt is
// one argv element from here to the agent (agentArgv), never a shell string.
function createPrompt(description, dir, contract) {
  return "Build an Omamobile home-screen widget in this folder (" + dir + ").\n"
    + "First read " + (contract || CONTRACT) + ", the widget contract, and follow it exactly.\n"
    + "The folder already holds a working starter: edit manifest.json (keep its id) and Widget.qml.\n"
    + "Rules: work only inside this folder; don't create, change or delete anything outside it; never use sudo or any other root tool; "
    + "don't install packages. Take colors, fonts and spacing only from Omarchy's theme (qs.Commons). "
    + "Declare every capability the widget uses in manifest.json. When done, run `" + TOOL + " check .` and fix every error it reports.\n"
    + "The user asked for: " + String(description || "").trim()
}

function editPrompt(description, dir, contract, name, errors) {
  var ask = String(description || "").trim()
  return "Change the Omamobile home-screen widget \"" + (name || "") + "\" in this folder (" + dir + ").\n"
    + "First read " + (contract || CONTRACT) + ", the widget contract, and follow it exactly.\n"
    + "Rules: work only inside this folder; don't create, change or delete anything outside it; never use sudo or any other root tool; "
    + "don't install packages. Keep the manifest's id. When done, run `" + TOOL + " check .` and fix every error it reports.\n"
    + ((errors && errors.length) ? "The home screen currently reports:\n" + errors.map(function(e) { return "- " + e }).join("\n") + "\n" : "")
    + (ask ? "The user asked for: " + ask : "Ask the user what to change.")
}

function newArgv(id, name) { return [TOOL, "new", String(id), String(name)] }
function storeCopyArgv(storeId) { return [TOOL, "store-copy", String(storeId)] }
function storeUpdateArgv(id) { return [TOOL, "store-update", String(id)] }
var STORE_FETCH_ARGV = [TOOL, "store-fetch"]
function copyArgv(id) { return [TOOL, "copy-example", String(id)] }
function removeArgv(id) { return [TOOL, "remove", String(id)] }
function agentArgv(id, prompt) { return [TOOL, "agent", String(id), String(prompt)] }
var SCAN_ARGV = [TOOL, "scan"]

// `omamobile-widget agent` exit code and stderr -> what the phone says.
function agentOutcome(code, stderr) {
  var message = String(stderr || "").trim().split("\n").filter(function(l) { return l.trim() }).slice(-3).join("\n")
  if (code === 0) return { kind: "launched", message: "" }
  if (code === 3) return { kind: "no-agent", message: message || "No coding agent is chosen in Omarchy yet. Pick one in the menu that opened, then try again." }
  return { kind: "failed", message: message || "The agent didn't start (status " + code + ")" }
}

// ---------------------------------------------------------------- settings

// A settings field's typed value from what the form holds (text from a
// field, a bool from a switch). null: leave the stored value alone.
function coerceSetting(field, value) {
  if (!field) return null
  var t = field.type
  if (t === "boolean") return value === true || value === "true"
  if (t === "integer" || t === "number") {
    var n = t === "integer" ? parseInt(value, 10) : parseFloat(value)
    if (!isFinite(n)) return null
    if (typeof field.min === "number") n = Math.max(field.min, n)
    if (typeof field.max === "number") n = Math.min(field.max, n)
    return n
  }
  if (t === "enum") return (field.options || []).indexOf(String(value)) >= 0 ? String(value) : null
  return String(value === undefined || value === null ? "" : value).slice(0, 2000)
}

// ---------------------------------------------------------------- WidgetHost.run

// "" when argv may run now, else why not.
function runCheck(argv, allowed, busy, sinceLastMs, minIntervalMs) {
  if (!allowed) return 'the manifest does not declare "commands"'
  if (!Array.isArray(argv) || argv.length === 0 || argv.some(function(a) { return typeof a !== "string" && typeof a !== "number" }))
    return "argv must be a non-empty list of strings"
  if (busy) return "another command of this widget is still running"
  if (sinceLastMs < (minIntervalMs === undefined ? MIN_INTERVAL_MS : minIntervalMs)) return "too soon after the last one (rate limit)"
  return ""
}

function runTimeout(options) {
  var t = options && typeof options.timeout === "number" ? options.timeout : DEFAULT_TIMEOUT
  if (!isFinite(t)) t = DEFAULT_TIMEOUT
  return Math.max(1, Math.min(MAX_TIMEOUT, Math.round(t)))
}

function timeoutArgv(argv, seconds) {
  return ["timeout", "-k", "2", String(seconds)].concat(argv.map(String))
}

function runResult(code, stdout, stderr) {
  return {
    code: code,
    stdout: String(stdout || "").slice(0, MAX_OUTPUT),
    stderr: String(stderr || "").slice(0, MAX_OUTPUT),
    timedOut: code === 124 || code === 137
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    PREFIX: PREFIX, ID_RE: ID_RE, TOOL: TOOL, CONTRACT: CONTRACT, SCAN_ARGV: SCAN_ARGV,
    MIN_INTERVAL_MS: MIN_INTERVAL_MS, DEFAULT_TIMEOUT: DEFAULT_TIMEOUT, MAX_TIMEOUT: MAX_TIMEOUT, MAX_OUTPUT: MAX_OUTPUT,
    emptyScan: emptyScan, parseScan: parseScan, findRecord: findRecord, findExample: findExample, catalog: catalog,
    typeFor: typeFor, idOf: idOf, tildePath: tildePath, cardState: cardState, capabilityText: capabilityText, statusLine: statusLine,
    slug: slug, newId: newId, nameFrom: nameFrom, createPrompt: createPrompt, editPrompt: editPrompt,
    newArgv: newArgv, storeCopyArgv: storeCopyArgv, storeUpdateArgv: storeUpdateArgv, STORE_FETCH_ARGV: STORE_FETCH_ARGV, copyArgv: copyArgv, removeArgv: removeArgv, agentArgv: agentArgv, agentOutcome: agentOutcome,
    coerceSetting: coerceSetting, runCheck: runCheck, runTimeout: runTimeout, timeoutArgv: timeoutArgv, runResult: runResult
  }
}
