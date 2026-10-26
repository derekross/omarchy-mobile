// SPDX-License-Identifier: MIT
// The notification shade under the quick-settings sheet: Omarchy's
// notification history, read from the files its notification service keeps.
// Pure functions, so QuickSettings.qml can render plain objects and Node can
// test them in test/notifications-model.js through module.exports.
//
// Omarchy's service (shell/plugins/notifications/Service.qml) writes one
// single-line JSON file per notification: in ~/.local/state/omarchy/
// notifications/ while its toast is on screen, then moved into history/
// when it expires, is dismissed or is acted on, trimmed to the newest ten.
// "This directory IS the history", as the service says; its IPC can replay
// it as toasts (showHistory) but has no call that returns it. Each file is
// named <timestamp>-<id>.json, the timestamp in milliseconds since the epoch.

var LIMIT = 10

function str(value) {
  return value === undefined || value === null ? "" : String(value)
}

// The body as one line of plain text. Omarchy keeps the sender's markup
// (b, i, u, a and entities) and styles it when it draws a toast; the shade
// shows text only.
function plainBody(body) {
  return str(body)
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/<[^>]*>/g, "")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"")
    .replace(/&#39;|&apos;/g, "'").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim()
}

// Omarchy's own toasts carry their click action as a JSON argv (the
// omarchy-exec-argv hint), which the files keep. The same structural check
// as Omarchy's parseExecArgv: a non-empty array of strings whose program is
// not empty and doesn't start with a dash. Null for anything else.
function execArgv(value) {
  var text = str(value)
  if (!text) return null
  var list = null
  try { list = JSON.parse(text) } catch (error) { return null }
  if (!Array.isArray(list) || list.length === 0) return null
  for (var i = 0; i < list.length; i++)
    if (typeof list[i] !== "string") return null
  if (list[0] === "" || list[0].charAt(0) === "-") return null
  return list
}

function entry(value) {
  var v = value || {}
  var timestamp = Number(v.timestamp || 0)
  if (!isFinite(timestamp) || timestamp < 0) timestamp = 0
  var id = v.originalId || v.id || 0
  return {
    key: String(timestamp) + "-" + String(id),
    app: str(v.app),
    summary: str(v.summary).trim(),
    body: plainBody(v.body),
    glyph: str(v.glyph),
    execArgv: str(v.execArgv),
    urgency: typeof v.urgency === "number" ? v.urgency : 1,
    timestamp: timestamp
  }
}

// The concatenation of every history and on-screen file (`awk 1` over both
// directories), newest first, each notification once (a toast moving into
// history can be read in both places), at most `limit`. Torn lines from a
// crash mid-write are skipped, as Omarchy skips them.
function parse(raw, limit) {
  var max = typeof limit === "number" ? Math.max(0, limit) : LIMIT
  var lines = str(raw).split("\n")
  var seen = {}
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var value = null
    try { value = JSON.parse(line) } catch (error) { continue }
    if (!value || typeof value !== "object" || Array.isArray(value)) continue
    var e = entry(value)
    if (!e.summary && !e.body) continue
    if (seen[e.key]) continue
    seen[e.key] = true
    out.push(e)
  }
  out.sort(function(a, b) { return b.timestamp - a.timestamp })
  return out.slice(0, max)
}

function newest(entries) {
  var most = 0
  var list = entries || []
  for (var i = 0; i < list.length; i++)
    if (list[i] && list[i].timestamp > most) most = list[i].timestamp
  return most
}

// What a tap on a row runs: the toast's own action when Omarchy gave it one,
// otherwise Omarchy's focus helper for the sending app (what a click on a
// toast without a live action does). Null when there is nothing to do.
function tapArgv(e) {
  if (!e) return null
  var argv = execArgv(e.execArgv)
  if (argv) return argv
  if (e.app) return ["omarchy-hyprland-focus-app", e.app]
  return null
}

// How long ago, in a few characters: "now", "5 min", "3 h", "2 d".
function ago(timestamp, now) {
  var ms = Number(now) - Number(timestamp)
  if (!isFinite(ms) || Number(timestamp) <= 0) return ""
  var minutes = Math.floor(Math.max(0, ms) / 60000)
  if (minutes < 1) return "now"
  if (minutes < 60) return minutes + " min"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + " h"
  return Math.floor(hours / 24) + " d"
}

function title(count) {
  return count > 0 ? "Notifications · " + count : "Notifications"
}

if (typeof module !== "undefined") {
  module.exports = {
    LIMIT: LIMIT,
    plainBody: plainBody,
    execArgv: execArgv,
    entry: entry,
    parse: parse,
    newest: newest,
    tapArgv: tapArgv,
    ago: ago,
    title: title
  }
}
