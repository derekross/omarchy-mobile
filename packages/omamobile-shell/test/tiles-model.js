// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.quicksettings/TilesModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.quicksettings/TilesModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])

test("the catalog has unique ids and every default is in it", () => {
  const ids = M.CATALOG.map((t) => t.id)
  assert.strictEqual(new Set(ids).size, ids.length)
  for (const id of M.DEFAULT_LAYOUT) assert.ok(M.known(id), id)
  assert.strictEqual(new Set(M.DEFAULT_LAYOUT).size, M.DEFAULT_LAYOUT.length)
})

test("the sheet has a backend for every catalog tile", () => {
  const qml = fs.readFileSync(path.join(__dirname, "../plugins/omamobile.quicksettings/QuickSettings.qml"), "utf8")
  const block = qml.slice(qml.indexOf("readonly property var backends:"), qml.indexOf("})", qml.indexOf("readonly property var backends:")))
  for (const { id } of M.CATALOG) assert.ok(block.includes(`"${id}":`), `backend for ${id}`)
})

test("the default keeps the old ten tiles and leads with the most used", () => {
  for (const id of ["wifi", "bluetooth", "mobile-data", "rotation-lock", "torch", "dnd", "location", "nfc", "fingerprint", "keyboard"])
    assert.ok(M.DEFAULT_LAYOUT.includes(id), id)
  assert.deepStrictEqual(M.quickRow(M.defaults()), ["wifi", "bluetooth", "dnd", "torch"])
})

test("Clipboard and Dictation close the default's second page and Reminder opens a third, leaving the earlier pages as they were", () => {
  assert.deepStrictEqual(M.pages(M.defaults())[0],
    ["wifi", "bluetooth", "dnd", "torch", "mobile-data", "rotation-lock", "airplane", "location"])
  assert.deepStrictEqual(M.pages(M.defaults())[1],
    ["battery-saver", "dark-theme", "night-light", "nfc", "fingerprint", "keyboard", "clipboard", "dictation"])
  assert.deepStrictEqual(M.DEFAULT_LAYOUT.slice(-3), ["clipboard", "dictation", "reminder"])
  assert.strictEqual(M.pages(M.defaults()).length, 3)
  assert.strictEqual(M.label("clipboard"), "Clipboard")
  assert.strictEqual(M.label("dictation"), "Dictation")
  assert.strictEqual(M.label("reminder"), "Reminder")
  assert.strictEqual(M.label("night-light"), "Night light")
})

test("defaults() is a copy", () => {
  const list = M.defaults()
  list.push("hotspot")
  assert.ok(!M.DEFAULT_LAYOUT.includes("hotspot"))
})

test("sanitize drops unknown ids, non-strings and duplicates, keeping order", () => {
  assert.deepStrictEqual(M.sanitize(["torch", "bogus", 3, null, "wifi", "torch"]), ["torch", "wifi"])
  assert.deepStrictEqual(M.sanitize([]), [])
  assert.deepStrictEqual(M.sanitize("wifi"), M.DEFAULT_LAYOUT)
  assert.deepStrictEqual(M.sanitize(null), M.DEFAULT_LAYOUT)
})

test("parseConfig falls back to the default on anything unreadable", () => {
  assert.deepStrictEqual(M.parseConfig(""), M.DEFAULT_LAYOUT)
  assert.deepStrictEqual(M.parseConfig("{"), M.DEFAULT_LAYOUT)
  assert.deepStrictEqual(M.parseConfig("[]"), M.DEFAULT_LAYOUT)
  assert.deepStrictEqual(M.parseConfig('{"tiles": "wifi"}'), M.DEFAULT_LAYOUT)
  assert.deepStrictEqual(M.parseConfig('{"version": 1, "tiles": ["mic", "nope", "wifi"]}'), ["mic", "wifi"])
  assert.deepStrictEqual(M.parseConfig('{"version": 1, "tiles": []}'), [])
})

test("serialize round-trips through parseConfig", () => {
  const text = M.serialize(["hotspot", "wifi", "bogus"])
  assert.ok(text.endsWith("\n"))
  assert.deepStrictEqual(JSON.parse(text), { version: 1, tiles: ["hotspot", "wifi"] })
  assert.deepStrictEqual(M.parseConfig(text), ["hotspot", "wifi"])
})

test("parseList takes JSON or space- and comma-separated ids", () => {
  assert.deepStrictEqual(M.parseList("wifi torch  dnd"), ["wifi", "torch", "dnd"])
  assert.deepStrictEqual(M.parseList("wifi,torch"), ["wifi", "torch"])
  assert.deepStrictEqual(M.parseList('["mic","x"]'), ["mic"])
  assert.deepStrictEqual(M.parseList("[]"), [])
  assert.strictEqual(M.parseList(""), null)
  assert.strictEqual(M.parseList("[nope"), null)
  assert.strictEqual(M.parseList("wifi; rm"), null)
})

test("available lists the hidden tiles in catalog order", () => {
  const spare = M.available(M.defaults())
  assert.deepStrictEqual(spare, ["hotspot", "stay-awake", "mic", "screenshot", "screen-record"])
  assert.strictEqual(M.available([]).length, M.CATALOG.length)
  assert.deepStrictEqual(M.available(M.CATALOG.map((t) => t.id)), [])
})

test("move reorders and clamps", () => {
  assert.deepStrictEqual(M.move(["wifi", "bluetooth", "dnd"], 0, 2), ["bluetooth", "dnd", "wifi"])
  assert.deepStrictEqual(M.move(["wifi", "bluetooth", "dnd"], 2, 0), ["dnd", "wifi", "bluetooth"])
  assert.deepStrictEqual(M.move(["wifi", "bluetooth", "dnd"], 1, 99), ["wifi", "dnd", "bluetooth"])
  assert.deepStrictEqual(M.move(["wifi", "bluetooth"], 5, 0), ["wifi", "bluetooth"])
})

test("add appends or inserts, once, known ids only", () => {
  assert.deepStrictEqual(M.add(["wifi"], "mic"), ["wifi", "mic"])
  assert.deepStrictEqual(M.add(["wifi", "dnd"], "mic", 1), ["wifi", "mic", "dnd"])
  assert.deepStrictEqual(M.add(["wifi"], "wifi"), ["wifi"])
  assert.deepStrictEqual(M.add(["wifi"], "bogus"), ["wifi"])
})

test("remove takes a tile out and leaves the rest in order", () => {
  assert.deepStrictEqual(M.remove(["wifi", "mic", "dnd"], "mic"), ["wifi", "dnd"])
  assert.deepStrictEqual(M.remove(["wifi"], "absent"), ["wifi"])
})

test("isDefault and sameLayout compare order too", () => {
  assert.ok(M.isDefault(M.defaults()))
  assert.ok(!M.isDefault(M.move(M.defaults(), 0, 1)))
  assert.ok(M.sameLayout(["a"], ["a"]))
  assert.ok(!M.sameLayout(["a", "b"], ["b", "a"]))
  assert.ok(!M.sameLayout(["a"], null))
})

test("pages split by eight and keep one empty page for an empty layout", () => {
  const all = M.CATALOG.map((t) => t.id)
  const pages = M.pages(all)
  assert.strictEqual(pages.length, Math.ceil(all.length / 8))
  assert.deepStrictEqual(pages[0], all.slice(0, 8))
  assert.deepStrictEqual([].concat(...pages), all)
  assert.deepStrictEqual(M.pages([]), [[]])
  assert.deepStrictEqual(M.pages(["wifi", "dnd", "mic"], 2), [["wifi", "dnd"], ["mic"]])
})

test("parseProbe reads key=value lines and ignores the rest", () => {
  const values = M.parseProbe("airplane=off\nhotspot=on\n\ngarbage\nBAD=x\ntheme_name=tokyo-night\ndata_status=Op LTE\nairplane=on\n")
  assert.deepStrictEqual(values, { airplane: "on", hotspot: "on", theme_name: "tokyo-night", data_status: "Op LTE" })
  assert.deepStrictEqual(M.parseProbe(""), {})
})

test("status helpers", () => {
  assert.strictEqual(M.powerStatus("power-saver"), "On")
  assert.strictEqual(M.powerStatus("balanced"), "Off")
  assert.strictEqual(M.powerStatus("performance"), "Off · performance")
  assert.strictEqual(M.powerStatus("none"), "No power profiles")
  assert.strictEqual(M.themeName("catppuccin-latte"), "Catppuccin Latte")
  assert.strictEqual(M.themeName(""), "")
  assert.strictEqual(M.label("dnd"), "Do not disturb")
  assert.strictEqual(M.dictationStatus("on"), "Listening")
  assert.strictEqual(M.dictationStatus("busy"), "Transcribing…")
  assert.strictEqual(M.dictationStatus("off"), "Off")
  assert.strictEqual(M.dictationStatus("down"), "Not running")
  assert.strictEqual(M.dictationStatus("none"), "Not installed")
  assert.strictEqual(M.dictationStatus(undefined), "Not installed")
})

test("reminders: Omarchy's minutes rule, its argv, what it lists, the tile's status", () => {
  assert.strictEqual(M.validMinutes("10"), 10)
  assert.strictEqual(M.validMinutes(" 5 "), 5)
  assert.strictEqual(M.validMinutes("0"), 0)
  assert.strictEqual(M.validMinutes("-3"), 0)
  assert.strictEqual(M.validMinutes("1.5"), 0)
  assert.strictEqual(M.validMinutes(""), 0)
  assert.strictEqual(M.validMinutes(undefined), 0)
  assert.deepStrictEqual(M.reminderArgv("30", "Check the oven"), ["omarchy-reminder", "30", "Check the oven"])
  assert.deepStrictEqual(M.reminderArgv(5, "  "), ["omarchy-reminder", "5"])
  assert.strictEqual(M.reminderArgv("abc", "x"), null)
  const listed = M.parseReminders(JSON.stringify({ count: 2, active: true, tooltip: "2 reminders", reminders: [
    { unit: "omarchy-reminder-30m-1", minutes: 30, message: "Check the oven", label: "Check the oven", remaining: "12m 3s", at: 1, atTime: "14:35" },
    { unit: "omarchy-reminder-5m-2", minutes: 5, message: "", label: "5-min reminder", remaining: "40s", at: 2, atTime: "14:24" }] }))
  assert.deepStrictEqual(listed, [{ label: "Check the oven", atTime: "14:35", remaining: "12m 3s" }, { label: "5-min reminder", atTime: "14:24", remaining: "40s" }])
  assert.deepStrictEqual(M.parseReminders('{"count":0,"reminders":[]}'), [])
  assert.deepStrictEqual(M.parseReminders("not json"), [])
  assert.deepStrictEqual(M.parseReminders(""), [])
  assert.strictEqual(M.reminderStatus("none"), "Not installed")
  assert.strictEqual(M.reminderStatus(undefined), "Not installed")
  assert.strictEqual(M.reminderStatus("0"), "None set")
  assert.strictEqual(M.reminderStatus("1"), "1 set")
  assert.strictEqual(M.reminderStatus("3"), "3 set")
})

let failed = 0
for (const [name, fn] of tests) {
  try {
    fn()
    console.log(`ok - tiles model: ${name}`)
  } catch (error) {
    failed++
    console.log(`not ok - tiles model: ${name}\n  ${error.message}`)
  }
}
process.exit(failed ? 1 : 0)
