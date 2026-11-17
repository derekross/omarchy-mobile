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
  const start = qml.indexOf("readonly property var builtinBackends:")
  assert.ok(start >= 0, "builtinBackends")
  const block = qml.slice(start, qml.indexOf("})", start))
  for (const { id } of M.CATALOG) assert.ok(block.includes(`"${id}":`), `backend for ${id}`)
})

test("the default keeps the old ten tiles and leads with the most used", () => {
  for (const id of ["wifi", "bluetooth", "mobile-data", "rotation-lock", "torch", "dnd", "location", "nfc", "fingerprint", "keyboard"])
    assert.ok(M.DEFAULT_LAYOUT.includes(id), id)
  assert.deepStrictEqual(M.quickRow(M.defaults()), ["wifi", "bluetooth", "dnd", "torch"])
})

test("Clipboard and Dictation close the default's second page, leaving the first as it was", () => {
  assert.deepStrictEqual(M.pages(M.defaults())[0],
    ["wifi", "bluetooth", "dnd", "torch", "mobile-data", "rotation-lock", "airplane", "location"])
  assert.deepStrictEqual(M.DEFAULT_LAYOUT.slice(-2), ["clipboard", "dictation"])
  assert.strictEqual(M.pages(M.defaults()).length, 2)
  assert.strictEqual(M.label("clipboard"), "Clipboard")
  assert.strictEqual(M.label("dictation"), "Dictation")
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

test("user tile ids: user: and [a-z0-9-]+, known before their files are listed", () => {
  for (const id of ["user:solar-time", "user:a", "user:2"]) {
    assert.ok(M.isUser(id), id)
    assert.ok(M.known(id), id)
    assert.ok(!M.builtIn(id), id)
  }
  for (const id of ["user:", "user:Solar", "user:a_b", "user:a.b", "user:../x", "user:a b", "solar", "User:a", "xuser:a", null, 3])
    assert.ok(!M.isUser(id), String(id))
  assert.ok(!M.known("user:BAD"))
  assert.ok(M.builtIn("wifi") && !M.isUser("wifi"))
  assert.strictEqual(M.userTileId("solar"), "user:solar")
  assert.strictEqual(M.userTileId("user:solar"), "user:solar")
  assert.strictEqual(M.userTileId("Solar"), "")
  assert.strictEqual(M.userTileId(""), "")
  assert.strictEqual(M.userTileId(undefined), "")
  // The pattern is user-tiles.py's.
  const py = fs.readFileSync(path.join(__dirname, "../plugins/omamobile.quicksettings/user-tiles.py"), "utf8")
  assert.ok(py.includes(`ID_RE = re.compile(r"${M.USER_ID_RE.source}")`), "the same id pattern as user-tiles.py")
})

test("the layout keeps user tiles: sanitize, parseConfig, parseList, add, serialize", () => {
  assert.deepStrictEqual(M.sanitize(["wifi", "user:solar", "user:BAD", "user:solar", "user:"]), ["wifi", "user:solar"])
  assert.deepStrictEqual(M.parseConfig('{"version": 1, "tiles": ["user:solar", "torch"]}'), ["user:solar", "torch"])
  assert.deepStrictEqual(M.parseList("wifi user:solar-time user:2"), ["wifi", "user:solar-time", "user:2"])
  assert.deepStrictEqual(M.parseList('["user:solar"]'), ["user:solar"])
  assert.strictEqual(M.parseList("user:solar; rm"), null)
  assert.deepStrictEqual(M.add(["wifi"], "user:solar", 0), ["user:solar", "wifi"])
  assert.deepStrictEqual(M.add(["user:solar"], "user:solar"), ["user:solar"])
  assert.deepStrictEqual(M.remove(["user:solar", "wifi"], "user:solar"), ["wifi"])
  assert.deepStrictEqual(M.parseConfig(M.serialize(["user:solar", "dnd"])), ["user:solar", "dnd"])
  assert.ok(!M.isDefault(M.defaults().concat(["user:solar"])))
})

test("available offers the user's tiles after the catalog, once, minus the shown ones", () => {
  const spare = M.available(M.defaults(), ["solar", "user:lights", "BAD", "user:solar", "lights"])
  assert.deepStrictEqual(spare, ["hotspot", "stay-awake", "mic", "screenshot", "screen-record", "user:solar", "user:lights"])
  assert.deepStrictEqual(M.available(M.defaults().concat(["user:solar"]), ["solar", "lights"]).slice(-1), ["user:lights"])
  assert.deepStrictEqual(M.available(M.defaults(), null), M.available(M.defaults()))
  assert.deepStrictEqual(M.available(M.defaults(), "solar"), M.available(M.defaults()))
})

test("parseUserTiles fills every field and drops what it can't use", () => {
  assert.deepStrictEqual(M.parseUserTiles(""), [])
  assert.deepStrictEqual(M.parseUserTiles("{"), [])
  assert.deepStrictEqual(M.parseUserTiles('{"id": "a"}'), [])
  const list = M.parseUserTiles(JSON.stringify([
    { id: "solar", label: "Solar time", icon: "x", status: "Rustica", active: false, hasChoices: true, hasAction: false, error: "",
      choices: [{ value: "Tempus_Solaris_Rustica", label: "Rustica" }, { value: "v2" }, { value: "" }, { label: "no value" }, null] },
    { id: "BAD", label: "x" },
    { id: "../x", label: "x" },
    { id: "solar", label: "again" },
    { id: "broken", error: "not valid JSON (line 2)" },
    "junk",
    { id: "lamp", label: "Lamp", active: "yes", hasAction: true, status: 5 }
  ]))
  assert.deepStrictEqual(list.map((t) => t.id), ["solar", "broken", "lamp"])
  assert.deepStrictEqual(list[0].choices, [{ value: "Tempus_Solaris_Rustica", label: "Rustica" }, { value: "v2", label: "v2" }])
  assert.strictEqual(list[0].hasChoices, true)
  assert.deepStrictEqual(list[1], { id: "broken", label: "broken", icon: M.USER_ICON, status: "", active: false, choices: [],
                                    hasChoices: false, hasAction: false, error: "not valid JSON (line 2)" })
  assert.strictEqual(list[2].active, false, "only true is on")
  assert.strictEqual(list[2].status, "")
  assert.strictEqual(list[2].hasAction, true)
})

test("a user tile's tap, lookup and current choice", () => {
  const tiles = M.parseUserTiles(JSON.stringify([
    { id: "solar", label: "Solar time", status: "Bashley Safe House", hasChoices: true,
      choices: [{ value: "Tempus_Solaris_Rustica", label: "Rustica" }, { value: "Tempus_Solaris_Bashley_Safe_House", label: "Bashley Safe House" }] },
    { id: "lamp", label: "Lamp", hasAction: true, status: "On" },
    { id: "uptime", label: "Uptime", status: "3 days" },
    { id: "broken", label: "x", hasAction: true, error: "label is missing" }
  ]))
  assert.strictEqual(M.findUserTile(tiles, "user:solar").label, "Solar time")
  assert.strictEqual(M.findUserTile(tiles, "lamp").label, "Lamp")
  assert.strictEqual(M.findUserTile(tiles, "user:none"), null)
  assert.strictEqual(M.findUserTile(null, "lamp"), null)
  assert.strictEqual(M.userTap(M.findUserTile(tiles, "solar")), "choose")
  assert.strictEqual(M.userTap(M.findUserTile(tiles, "lamp")), "run")
  assert.strictEqual(M.userTap(M.findUserTile(tiles, "uptime")), "")
  assert.strictEqual(M.userTap(M.findUserTile(tiles, "broken")), "")
  assert.strictEqual(M.userTap(null), "")
  assert.strictEqual(M.currentChoice(M.findUserTile(tiles, "solar")), "Tempus_Solaris_Bashley_Safe_House")
  const byValue = Object.assign({}, tiles[0], { status: "Tempus_Solaris_Rustica" })
  assert.strictEqual(M.currentChoice(byValue), "Tempus_Solaris_Rustica")
  assert.strictEqual(M.currentChoice(Object.assign({}, tiles[0], { status: "Elsewhere" })), "")
  assert.strictEqual(M.currentChoice(Object.assign({}, tiles[0], { status: "" })), "")
  assert.strictEqual(M.currentChoice(null), "")
})

test("the sheet asks for user tiles' labels and backends, and a missing file is Not installed", () => {
  const qml = fs.readFileSync(path.join(__dirname, "../plugins/omamobile.quicksettings/QuickSettings.qml"), "utf8")
  assert.ok(qml.includes('readonly property var backend: host ? host.backendFor(tileId) : null'), "tiles take backendFor")
  assert.ok(qml.includes('label: host ? host.tileLabel(tileId) : TilesModel.label(tileId)'), "tiles take tileLabel")
  assert.ok(qml.includes('status: userTilesLoaded ? "Not installed" : ""'), "a missing user tile")
  assert.ok(qml.includes('readonly property var spareTiles: TilesModel.available(layout, userTileIds)'), "Add tiles offers them")
  assert.ok(!/label: TilesModel\.label\((model\.tileId|modelData)\)/.test(qml), "edit mode asks tileLabel too")
  // Never through a shell: the helper and the value are argv elements.
  assert.ok(qml.includes('["python3", "-I", root.scriptPath("user-tiles.py"), "list"]'))
  assert.ok(qml.includes('["python3", "-I", scriptPath("user-tiles.py"), "run", id].concat(value === null ? [] : [String(value)])'))
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

test("the Mobile data icon shows bars, crossed out only with no modem, data off or no network", () => {
  const S = require(path.join(__dirname, "../plugins/omamobile.bar/StatusModel.js"))
  const crossed = String.fromCodePoint(0xF0783)
  assert.strictEqual(M.dataIcon(false, false, "80"), crossed, "no modem")
  assert.strictEqual(M.dataIcon(true, false, "80"), crossed, "data off")
  assert.strictEqual(M.dataIcon(true, true, "-1"), crossed, "no network")
  assert.strictEqual(M.dataIcon(true, true, undefined), crossed, "an older probe without data_signal")
  assert.strictEqual(M.dataIcon(true, true, "junk"), crossed, "garbage")
  assert.strictEqual(M.dataIcon(true, true, "0"), String.fromCodePoint(0xF08BF), "registered, no reading: empty bars")
  // The same bars as the status bar's cellular icon, at every strength.
  for (let s = 0; s <= 100; s++) assert.strictEqual(M.dataIcon(true, true, String(s)), S.cellularIcon(s), `strength ${s}`)
  assert.strictEqual(M.dataIcon(true, true, "250"), S.cellularIcon(100), "capped")
  assert.notStrictEqual(M.dataIcon(true, true, "100"), crossed)
  const qml = fs.readFileSync(path.join(__dirname, "../plugins/omamobile.quicksettings/QuickSettings.qml"), "utf8")
  assert.ok(/icon: TilesModel\.dataIcon\(available, enabled, root\.probed\.data_signal\)/.test(qml), "the tile uses it")
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
