// SPDX-License-Identifier: MIT
// The update sheet's pure parts: omamobile-update's events and results in,
// what the sheet shows out. No QML here, so test/update-model.js runs it
// under Node through the module.exports below.

var CHECK_ARGV = ["omamobile-update", "check", "--json"]
var START_ARGV = ["omamobile-update", "start"]
var STATUS_ARGV = ["omamobile-update", "status", "--json"]
var ACK_ARGV = ["omamobile-update", "ack"]
var NOTIFY_ARGV = ["omamobile-update", "notify-check"]
var REBOOT_ARGV = ["omamobile-reboot"]
var MAX_DETAIL_LINES = 400

function parseJson(text) {
  try {
    var value = JSON.parse(String(text || ""))
    return value && typeof value === "object" ? value : null
  } catch (e) {
    return null
  }
}

// One "kind<TAB>text" line of the events file.
function parseEvent(line) {
  var s = String(line || "")
  var tab = s.indexOf("\t")
  if (tab <= 0) return null
  var kind = s.slice(0, tab)
  var text = s.slice(tab + 1)
  if (kind === "result") return { kind: kind, text: "", result: parseJson(text) }
  return { kind: kind, text: text }
}

// Details keep the last MAX_DETAIL_LINES lines: a new array (QML sees a
// change only on reassignment).
function appendDetail(lines, text) {
  var next = (lines || []).slice()
  next.push(String(text))
  if (next.length > MAX_DETAIL_LINES) next = next.slice(next.length - MAX_DETAIL_LINES)
  return next
}

function plural(n, one, many) {
  return n + " " + (n === 1 ? one : many)
}

// What the overview says about an update, from `omamobile-update check --json`.
function overview(info) {
  if (!info) return { title: "Checking for updates", body: "", canUpdate: false, blockers: [] }
  var title, body
  var line = String(info.omarchy_update || "")
  var parts = line.split(/\s+/)
  if (line && parts.length >= 4) {
    title = "Omarchy " + parts[parts.length - 1]
    body = "From " + parts[1] + ", with " + plural(info.update_count || 0, "package", "packages") + " in all."
  } else if ((info.update_count || 0) > 0) {
    title = plural(info.update_count, "package update", "package updates")
    body = "Omarchy " + (info.omarchy || "") + " stays; the system packages update."
  } else {
    title = "Up to date"
    body = "Omarchy " + (info.omarchy || "") + " and its packages are current."
  }
  // The phone's kernel package (omamobile-omarchy 0.1.28 and later): its
  // hook writes it to slot B, or a development phone leaves slot B alone
  var k = info.kernel
  if (k && k.version) {
    body += k.boot_update === "write"
      ? " Includes the kernel (" + k.version + "): it is written to the phone, and a restart boots it."
      : " Includes the kernel package (" + k.version + "); this phone keeps the kernel it has."
  }
  var blockers = (info.blockers || []).slice()
  return {
    title: title,
    body: body,
    canUpdate: !!info.ok && (info.update_count || 0) > 0,
    blockers: blockers,
    upToDate: (info.update_count || 0) === 0 && blockers.length === 0
  }
}

// The battery line: "64%", "18%, charging", "No battery".
function batteryText(info) {
  var b = info && info.battery
  if (!b || !b.present) return "No battery"
  return b.percent + "%" + (b.charging ? ", charging" : "")
}

// The phone patches' line, from the patch status in check or a result.
function patchesText(p) {
  if (!p || !p.result || p.result === "never") return "Phone patches: not applied yet"
  if (p.result === "failed")
    return "Phone patches could not be applied" + (p.failed ? " (" + p.failed + ")" : "") +
      ": the lock screen's PIN pad may be missing. Omarchy's own files are in place. Log: " + (p.log || "")
  if (p.result === "ok") {
    var n = (p.applied || []).length
    var up = (p.upstream || []).length
    return "Phone patches in place: " + plural(n, "patch", "patches") +
      (up ? ", " + plural(up, "now part of Omarchy", "now part of Omarchy") : "")
  }
  return "Phone patches: " + p.result
}

// The result page, from last.json.
function resultView(r) {
  if (!r) return { title: "", body: "", tone: "normal", restart: false, log: "" }
  var tone = "good", title, body = String(r.message || "")
  switch (r.result) {
  case "ok":
    title = r.needs_reboot ? "Updated: restart to finish" : "Updated"
    body = r.needs_reboot ? (r.reasons || []).join(". ") + "." : "Everything is current."
    if (r.omarchy_before && r.omarchy_after && r.omarchy_before !== r.omarchy_after)
      body = "Omarchy " + r.omarchy_before + " to " + r.omarchy_after + ". " + body
    break
  case "patches-failed":
    title = "Updated, but the phone patches failed"
    tone = "warn"
    break
  case "auth-failed":
    title = "Wrong PIN or password"
    tone = "bad"
    body = "Nothing was changed."
    break
  case "refused":
    title = "Not updated"
    tone = "warn"
    break
  default:
    title = "The update stopped"
    tone = "bad"
  }
  var held = (r.held || []).map(function(h) { return h[0] + (h[2] ? " (" + h[2] + ")" : "") })
  return {
    title: title,
    body: body,
    tone: tone,
    restart: !!r.needs_reboot && (r.result === "ok" || r.result === "patches-failed"),
    log: String(r.log || ""),
    patches: r.patches ? patchesText(r.patches) : "",
    held: held,
    warnings: (r.warnings || []).slice()
  }
}

// What `start` printed (and its exit code) means for the sheet.
function startOutcome(exitCode) {
  switch (exitCode) {
  case 0: return "started"
  case 3: return "auth-failed"
  case 4: return "running"
  case 5: return "refused"
  default: return "error"
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    CHECK_ARGV: CHECK_ARGV, START_ARGV: START_ARGV, STATUS_ARGV: STATUS_ARGV, ACK_ARGV: ACK_ARGV,
    NOTIFY_ARGV: NOTIFY_ARGV, REBOOT_ARGV: REBOOT_ARGV, MAX_DETAIL_LINES: MAX_DETAIL_LINES,
    parseJson: parseJson, parseEvent: parseEvent, appendDetail: appendDetail, overview: overview,
    batteryText: batteryText, patchesText: patchesText, resultView: resultView, startOutcome: startOutcome
  }
}
