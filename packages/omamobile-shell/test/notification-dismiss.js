// SPDX-License-Identifier: MIT
// Actual QS functions/callback; the process and display boundaries are inert.
"use strict"
const fs = require("fs")
const path = require("path")
const vm = require("vm")
const assert = require("assert")
const source = fs.readFileSync(process.env.NOTIFICATION_SOURCE ||
  path.join(__dirname, "../plugins/omamobile.quicksettings/QuickSettings.qml"), "utf8")
const Model = require("../plugins/omamobile.quicksettings/NotificationsModel.js")

function block(start) {
  const begin = source.indexOf("{", start)
  let end = begin + 1, depth = 1
  while (depth) {
    if (source[end] === "{") depth++
    if (source[end] === "}") depth--
    end++
  }
  return source.slice(begin, end)
}
function actualFunction(name) {
  const start = source.indexOf("  function " + name + "(")
  assert(start >= 0, "missing actual function: " + name)
  return source.slice(start, source.indexOf("{", start)) + block(start)
}
const processStart = source.indexOf("    id: forgetProc")
assert(processStart >= 0)
const callback = "function(code) " + block(source.indexOf("onExited:", processStart))
const first = { key: "1000-1", file: "1000-1.json", summary: "Fixture one", timestamp: 1000 }
const second = { key: "1001-2", file: "1001-2.json", summary: "Fixture two", timestamp: 1001 }

function fixture() {
  const later = []
  let refreshes = 0
  const c = {
    Object, Date, notifications: [first, second], hiddenNotifications: {},
    forgetQueue: [], pendingForget: null, notificationDeleteError: "",
    editing: false, confirmClear: false, opened: true,
    forgetProc: { running: false, command: [] }, forgetResult: { text: "" },
    NotificationsModel: Model,
    Quickshell: {
      shellDir: "/owned-shell",
      execDetached() { throw Error("delete must never invoke sender action") }
    },
    Qt: { callLater: fn => later.push(fn) },
    notificationsLater: { restart() { refreshes++ } }
  }
  c.root = c
  vm.createContext(c)
  vm.runInContext(["forgetNotification", "runForget", "close"].map(actualFunction).join("\n") +
    "\nvar finishForget=" + callback, c)
  return {
    c,
    drain() { while (later.length) later.shift()() },
    finish(code, text) {
      c.forgetProc.running = false
      c.forgetResult.text = text
      c.finishForget(code)
    },
    refreshes: () => refreshes
  }
}
let count = 0
function test(name, fn) { fn(); count++; console.log("PASS " + name) }

test("request uses a literal IPC argument and preserves pending identity", () => {
  const s = fixture()
  assert(s.c.forgetNotification(first))
  s.drain()
  assert.equal(s.c.pendingForget.key, first.key)
  assert.deepEqual([...s.c.forgetProc.command], ["qs", "ipc", "-p", "/owned-shell",
    "call", "notifications", "forget", first.file])
  assert.equal(s.c.notifications.length, 1)
})

test("two queued rows receive separate acknowledgments in order", () => {
  const s = fixture()
  s.c.forgetNotification(first); s.drain()
  s.c.forgetNotification(second); s.drain()
  assert.equal(s.c.pendingForget.key, first.key)
  assert.equal(s.c.forgetQueue.length, 1)
  s.finish(0, "ok\n")
  assert.equal(s.c.pendingForget.key, second.key)
  assert.equal(s.c.forgetQueue.length, 0)
  s.finish(0, "ok")
  assert.equal(s.c.pendingForget, null)
  assert.equal(s.refreshes(), 2)
})

test("failed IPC restores visibility on refresh and reports an error", () => {
  const s = fixture()
  s.c.forgetNotification(first); s.drain(); s.finish(1, "")
  assert(!Object.hasOwn(s.c.hiddenNotifications, first.key))
  assert.equal(s.c.notificationDeleteError, "Couldn't dismiss notification")
  const raw = JSON.stringify({ timestamp: 1000, originalId: 1, summary: "Fixture one" })
  assert.equal(Model.shown(raw, s.c.hiddenNotifications, Date.now()).entries.length, 1)
})

test("a successful process without acceptance restores the row", () => {
  for (const reply of ["none", "busy", "unexpected", ""]) {
    const s = fixture()
    s.c.forgetNotification(first); s.drain(); s.finish(0, reply)
    assert(!Object.hasOwn(s.c.hiddenNotifications, first.key))
    assert(s.c.notificationDeleteError)
  }
})

test("accepted request stays hidden during the pending file write", () => {
  const s = fixture()
  s.c.forgetNotification(first); s.drain(); s.finish(0, "ok")
  assert(Object.hasOwn(s.c.hiddenNotifications, first.key))
  const raw = JSON.stringify({ timestamp: 1000, originalId: 1, summary: "Fixture one" })
  assert.equal(Model.shown(raw, s.c.hiddenNotifications, Date.now()).entries.length, 0)
  assert.equal(s.c.notificationDeleteError, "")
})

test("failure of one row does not abort the next queued delete", () => {
  const s = fixture()
  s.c.forgetNotification(first); s.drain()
  s.c.forgetNotification(second); s.drain()
  s.finish(1, "")
  assert.equal(s.c.pendingForget.key, second.key)
  s.finish(0, "ok")
  assert(!Object.hasOwn(s.c.hiddenNotifications, first.key))
  assert(Object.hasOwn(s.c.hiddenNotifications, second.key))
})

test("an invalid entry cannot start a process or hide any row", () => {
  for (const entry of [null, {}, { key: "key-only" }, { file: "file-only" }]) {
    const s = fixture()
    assert.equal(s.c.forgetNotification(entry), false)
    s.drain()
    assert.equal(s.c.forgetProc.running, false)
    assert.equal(s.c.notifications.length, 2)
  }
})

// Closing the shade clears presentation state without touching pending requests.
test("closing shade clears an old error while preserving the queue", () => {
  const s = fixture()
  s.c.notificationDeleteError = "Couldn't dismiss notification"
  s.c.forgetNotification(first)
  s.drain()
  const pending = s.c.pendingForget
  s.c.close()
  assert.equal(s.c.notificationDeleteError, "")
  assert.equal(s.c.opened, false)
  assert.strictEqual(s.c.pendingForget, pending)
})

console.log("PASS " + count + " actual notification dismissal cases")
