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
