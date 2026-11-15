// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.quicksettings/NotificationsModel.js, the
// quick-settings notification shade. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.quicksettings/NotificationsModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])

// One line per file, as Omarchy's serializePopup writes them.
// The file name's stem is <timestamp>-<originalId>, which follows the id here.
const file = (o) => JSON.stringify(Object.assign({
  id: 3, app: "Signal", appIcon: "", summary: "Ana", body: "See you <b>soon</b> &amp; bye",
  image: "", glyph: "", execArgv: "", urgency: 1, expireTimeout: 0, timestamp: 1760000000000
}, o, { originalId: (o && o.id) || 3 }))

test("parse reads Omarchy's files newest first, with plain-text bodies", () => {
  const raw = [file({ timestamp: 1000, id: 1, summary: "old" }), file({ timestamp: 3000, id: 2, summary: "new" }),
               file({ timestamp: 2000, id: 7, summary: "mid" })].join("\n") + "\n"
  const rows = M.parse(raw)
  assert.deepStrictEqual(rows.map((r) => r.summary), ["new", "mid", "old"])
  assert.strictEqual(rows[0].key, "3000-2")
  assert.strictEqual(M.parse(file({})).at(0).body, "See you soon & bye")
})

test("parse skips torn lines, empty entries and the same notification read twice", () => {
  const raw = [file({ timestamp: 5, id: 1 }), "{\"summary\": \"torn", "", "[1,2]", "null",
               file({ timestamp: 5, id: 1 }), file({ timestamp: 6, id: 2, summary: "", body: "" })].join("\n")
  assert.strictEqual(M.parse(raw).length, 1)
  assert.deepStrictEqual(M.parse(""), [])
  assert.deepStrictEqual(M.parse(undefined), [])
})

test("parse keeps Omarchy's ten, or the limit given", () => {
  const raw = Array.from({ length: 14 }, (_, i) => file({ timestamp: 100 + i, id: i })).join("\n")
  assert.strictEqual(M.parse(raw).length, M.LIMIT)
  assert.strictEqual(M.parse(raw)[0].timestamp, 113)
  assert.strictEqual(M.parse(raw, 3).length, 3)
})

test("plainBody strips markup and decodes entities once", () => {
  assert.strictEqual(M.plainBody("a<br/>b\n\n<i>c</i>"), "a b c")
  assert.strictEqual(M.plainBody("&amp;lt; &lt;tag&gt; &quot;q&quot; it&#39;s"), "&lt; <tag> \"q\" it's")
  assert.strictEqual(M.plainBody(null), "")
})

test("execArgv takes only a well-formed argv, as Omarchy's own check", () => {
  assert.deepStrictEqual(M.execArgv('["omarchy-launch-wifi"]'), ["omarchy-launch-wifi"])
  assert.deepStrictEqual(M.execArgv('["bash","-c","x"]'), ["bash", "-c", "x"])
  for (const bad of ["", "nope", "[]", '["-rf"]', '[""]', '["a", 1]', '{"a":1}', "null"])
    assert.strictEqual(M.execArgv(bad), null, bad)
})

test("a tap runs the toast's action, else focuses the sender, else nothing", () => {
  const [withAction] = M.parse(file({ execArgv: '["omarchy-launch-wifi"]' }))
  assert.deepStrictEqual(M.tapArgv(withAction), ["omarchy-launch-wifi"])
  const [plain] = M.parse(file({}))
  assert.deepStrictEqual(M.tapArgv(plain), ["omarchy-hyprland-focus-app", "Signal"])
  const [anonymous] = M.parse(file({ app: "", execArgv: '["-x"]' }))
  assert.strictEqual(M.tapArgv(anonymous), null)
  assert.strictEqual(M.tapArgv(null), null)
})

test("newest, ago and the title", () => {
  assert.strictEqual(M.newest(M.parse([file({ timestamp: 9, id: 1 }), file({ timestamp: 40, id: 2 })].join("\n"))), 40)
  assert.strictEqual(M.newest([]), 0)
  const now = 1760000000000
  assert.strictEqual(M.ago(now - 20 * 1000, now), "now")
  assert.strictEqual(M.ago(now - 5 * 60000, now), "5 min")
  assert.strictEqual(M.ago(now - 3 * 3600000, now), "3 h")
  assert.strictEqual(M.ago(now - 50 * 3600000, now), "2 d")
  assert.strictEqual(M.ago(now + 60000, now), "now", "a clock that stepped back")
  assert.strictEqual(M.ago(0, now), "")
  assert.strictEqual(M.title(0), "Notifications")
  assert.strictEqual(M.title(3), "Notifications · 3")
})

test("each row carries the service's file name, which forget takes", () => {
  const [row] = M.parse(file({ timestamp: 1760000000123, id: 42 }))
  assert.strictEqual(row.file, "1760000000123-42.json")
  assert.match(row.file, /^[0-9]+-[0-9]+\.json$/, "the shape patch 0019 accepts")
  const [noId] = M.parse(JSON.stringify({ summary: "x", timestamp: 7 }))
  assert.strictEqual(noId.file, "7-0.json", "popupFileName's originalId || 0")
})

test("shown hides a swiped row until its file is gone, and only that row", () => {
  const raw = [file({ timestamp: 1000, id: 1, summary: "a" }), file({ timestamp: 2000, id: 2, summary: "b" }),
               file({ timestamp: 3000, id: 3, summary: "c" })].join("\n")
  const now = 50000
  let view = M.shown(raw, { "2000-2": now - 100 }, now)
  assert.deepStrictEqual(view.entries.map((r) => r.summary), ["c", "a"])
  assert.deepStrictEqual(view.hidden, { "2000-2": now - 100 }, "kept while the file is still read")
  const after = [file({ timestamp: 1000, id: 1, summary: "a" }), file({ timestamp: 3000, id: 3, summary: "c" })].join("\n")
  view = M.shown(after, view.hidden, now)
  assert.deepStrictEqual(view.hidden, {}, "dropped once the service has deleted it")
  assert.strictEqual(view.entries.length, 2)
})

test("a forget that never happened lapses and the row comes back", () => {
  const raw = file({ timestamp: 1000, id: 1 })
  const view = M.shown(raw, { "1000-1": 0 }, 16000, 15000)
  assert.strictEqual(view.entries.length, 1)
  assert.deepStrictEqual(view.hidden, {})
  assert.strictEqual(M.shown(raw, { "1000-1": 0 }, 14000, 15000).entries.length, 0)
})

test("shown still shows ten after one is hidden", () => {
  const raw = Array.from({ length: 11 }, (_, i) => file({ timestamp: 100 + i, id: i })).join("\n")
  const view = M.shown(raw, { "110-10": 1 }, 2)
  assert.strictEqual(view.entries.length, M.LIMIT)
  assert.strictEqual(view.entries[0].timestamp, 109)
  assert.strictEqual(M.shown("", undefined, 0).entries.length, 0)
})

test("without takes one row out", () => {
  const rows = M.parse([file({ timestamp: 1, id: 1 }), file({ timestamp: 2, id: 2 })].join("\n"))
  assert.deepStrictEqual(M.without(rows, "1-1").map((r) => r.key), ["2-2"])
  assert.deepStrictEqual(M.without(null, "x"), [])
})

test("swipeOutcome: past 35% or a flick goes that way, else back", () => {
  const w = 400, fling = 900
  assert.strictEqual(M.swipeOutcome(140, 0, w, fling), 1)
  assert.strictEqual(M.swipeOutcome(-140, 0, w, fling), -1)
  assert.strictEqual(M.swipeOutcome(139, 0, w, fling), 0, "short of 35% springs back")
  assert.strictEqual(M.swipeOutcome(50, 1200, w, fling), 1, "a flick")
  assert.strictEqual(M.swipeOutcome(-50, -1200, w, fling), -1)
  assert.strictEqual(M.swipeOutcome(30, 1200, w, fling), 0, "a flick needs a tenth of the width")
  assert.strictEqual(M.swipeOutcome(50, -1200, w, fling), 0, "flicked back the other way")
  assert.strictEqual(M.swipeOutcome(50, 800, w, fling), 0, "too slow")
  assert.strictEqual(M.swipeOutcome(0, 2000, w, fling), 0)
  assert.strictEqual(M.swipeOutcome(300, 0, 0, fling), 0, "no width yet")
})

// Omarchy 4.5's files (shell/plugins/notifications/Store.js): live.json and
// history.json, each one line, a JSON array of rows as Store.persistable and
// Store.closedEntry write them. These rows were made by 4.5.0-3's own
// Store.js (snapshot, persistable, closedEntry, serialise); a verification
// code is stored redacted.
const row45 = (o) => Object.assign({
  key: "nmgx1a2b3", originalId: 3, senderPid: 0, execArgv: "[\"omarchy-launch-wifi\"]", execActions: "", glyph: "",
  app: "Signal", appIcon: "signal-desktop", summary: "Ana", body: "See you <b>soon</b> &amp; bye", rawBody: "",
  source: "Signal", groupKey: "app:signal", urgency: 1, expireTimeout: 0, duration: 0, ts: 1760000000.123
}, o)
const closed45 = (o) => Object.assign(row45(o), { closed_ts: 1760000060.5, closed_reason: "dismissed" }, o)
const store45 = (live, history) => JSON.stringify(live) + "\n" + JSON.stringify(history) + "\n"

test("parse reads Omarchy 4.5's live.json and history.json, newest first", () => {
  const raw = store45([row45({ key: "nlive", summary: "on screen", ts: 1760000300.5 })],
                      [closed45({ key: "nnew", summary: "new", ts: 1760000200 }), closed45({ key: "nold", summary: "old", ts: 1760000100 }),
                       closed45({ key: "ncode", originalId: 9, app: "", appIcon: "", execArgv: "", source: "", groupKey: "",
                                  summary: "Verification notification", body: "[redacted]", ts: 1760000150, closed_reason: "expired" })])
  const rows = M.parse(raw)
  assert.deepStrictEqual(rows.map((r) => r.summary), ["on screen", "new", "Verification notification", "old"])
  assert.deepStrictEqual(rows.map((r) => r.key), ["nlive", "nnew", "ncode", "nold"])
  assert.strictEqual(rows[0].timestamp, 1760000300500, "ts in seconds, as milliseconds")
  const [one] = M.parse(store45([], [closed45({})]))
  assert.deepStrictEqual(one, { key: "nmgx1a2b3", file: "nmgx1a2b3", app: "Signal", summary: "Ana", body: "See you soon & bye",
                                glyph: "", execArgv: "[\"omarchy-launch-wifi\"]", urgency: 1, timestamp: 1760000000123 })
  assert.deepStrictEqual(M.tapArgv(one), ["omarchy-launch-wifi"])
})

test("on 4.5 each row carries its key, which forget takes", () => {
  const [row] = M.parse(store45([], [closed45({ key: "nabc_1-Z" })]))
  assert.strictEqual(row.file, "nabc_1-Z")
  assert.match(row.file, /^[A-Za-z0-9_-]{1,120}$/, "the shape 4.5's Store.KEY accepts")
})

test("4.5: a row in both files shows once; rows without a usable key or text are skipped", () => {
  const raw = store45([row45({ key: "nsame", summary: "live copy" })],
                      [closed45({ key: "nsame", summary: "history copy" }), closed45({ key: "bad key" }), closed45({ key: "" }),
                       closed45({ key: "x".repeat(121) }), closed45({ key: "nempty", summary: "", body: "" }), 7, null, [1], "n"])
  const rows = M.parse(raw)
  assert.deepStrictEqual(rows.map((r) => r.summary), ["live copy"])
  assert.deepStrictEqual(M.parse("\n\n"), [], "4.5's files as its service creates them: empty")
  assert.deepStrictEqual(M.parse("[]\n[]\n"), [])
  assert.strictEqual(M.parse(store45([], [closed45({ ts: "soon" })]))[0].timestamp, 0, "no usable ts: no age")
})

test("4.5: shown hides a swiped row until it is gone, and lists every key for Clear all", () => {
  const history = Array.from({ length: 12 }, (_, i) => closed45({ key: "n" + i, ts: 1760000000 + i }))
  let view = M.shown(store45([], history), { n11: 900 }, 1000)
  assert.strictEqual(view.entries.length, M.LIMIT)
  assert.strictEqual(view.entries[0].key, "n10")
  assert.deepStrictEqual(view.hidden, { n11: 900 })
  assert.strictEqual(view.files.length, 12, "every row read, not only the ten shown")
  view = M.shown(store45([], history.slice(0, 11)), view.hidden, 1000)
  assert.deepStrictEqual(view.hidden, {})
})

test("4.0: shown lists every file name for Clear all too", () => {
  const raw = Array.from({ length: 11 }, (_, i) => file({ timestamp: 100 + i, id: i })).join("\n")
  assert.strictEqual(M.shown(raw, {}, 0).files.length, 11)
  assert.strictEqual(M.shown(raw, {}, 0).files[0], "110-10.json")
})

let failed = 0
for (const [name, fn] of tests) {
  try {
    fn()
    console.log(`ok - notifications model: ${name}`)
  } catch (error) {
    failed++
    console.log(`not ok - notifications model: ${name}\n  ${error.message}`)
  }
}
process.exit(failed ? 1 : 0)
