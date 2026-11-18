// SPDX-License-Identifier: MIT
// The permission sheet's queue and its answers, kept free of QML so
// test/access-model.js runs it under Node through the module.exports below.

var BUS_NAME = "org.freedesktop.impl.portal.desktop.omamobile"
var SHEET_PATH = "/org/omamobile/AccessSheet"
var SHEET_IFACE = "org.omamobile.AccessSheet"

// One request from omamobile-portal-access, checked; null when unusable.
function parseRequest(json) {
  var value
  try { value = JSON.parse(String(json || "")) } catch (e) { return null }
  if (!value || typeof value !== "object" || typeof value.id !== "string" || !/^[0-9a-f]{8,64}$/.test(value.id))
    return null
  function text(key, fallback) {
    var v = value[key]
    return typeof v === "string" && v.length > 0 ? v : fallback
  }
  return {
    id: value.id,
    appId: text("appId", ""),
    appName: text("appName", "An app"),
    appIcon: text("appIcon", ""),
    glyph: text("glyph", "󰒃"),
    title: text("title", "Allow this?"),
    body: text("body", ""),
    denyLabel: text("denyLabel", "Don't allow"),
    grantLabel: text("grantLabel", "Allow")
  }
}

// The queue with a request added at the end (a repeated id replaces nothing).
function enqueue(queue, request) {
  if (!request) return queue
  for (var i = 0; i < queue.length; i++) if (queue[i].id === request.id) return queue
  return queue.concat([request])
}

// The queue without the request `id`.
function remove(queue, id) {
  return queue.filter(function(r) { return r.id !== id })
}

// The id out of dismiss()'s argument: {"id": ...} or the bare id.
function idOf(json) {
  try {
    var v = JSON.parse(String(json || ""))
    if (v && typeof v.id === "string") return v.id
  } catch (e) {}
  return String(json || "")
}

// The reply to the service: busctl, never a shell.
function answerArgv(id, allow) {
  return ["busctl", "--user", "call", BUS_NAME, SHEET_PATH, SHEET_IFACE, "Answer", "ss", String(id), allow ? "allow" : "deny"]
}

// Back on the sheet: the request ends unanswered. The service then denies
// this one request and the portal stores nothing, so the app asks again next
// time; "deny" would be remembered as the app's permanent "no".
function dismissArgv(id) {
  return ["busctl", "--user", "call", BUS_NAME, SHEET_PATH, SHEET_IFACE, "Answer", "ss", String(id), "dismiss"]
}

// A first letter for the icon tile when the app has no icon.
function initial(name) {
  var s = String(name || "").trim()
  return s.length ? s.charAt(0).toUpperCase() : "?"
}

if (typeof module !== "undefined") {
  module.exports = {
    BUS_NAME: BUS_NAME, SHEET_PATH: SHEET_PATH, SHEET_IFACE: SHEET_IFACE,
    parseRequest: parseRequest, enqueue: enqueue, remove: remove, idOf: idOf,
    answerArgv: answerArgv, dismissArgv: dismissArgv, initial: initial
  }
}
