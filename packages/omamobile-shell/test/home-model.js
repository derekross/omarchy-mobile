// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.home/HomeModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.home/HomeModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])
const grid = { columns: 4, rows: 6 }
const app = (id, x, y, extra) => Object.assign({ id, kind: "app", app: id + ".app", x, y, w: 1, h: 1 }, extra || {})
const widget = (id, type, x, y, w, h) => ({ id, kind: "widget", type, x, y, w, h, config: {} })
const layoutOf = (...pages) => M.normalize({ grid, pages: pages.map((items) => ({ items })) })
const ids = (layout, page) => layout.pages[page].items.map((i) => i.id).sort()

// ---------------------------------------------------------------- placement

test("free spots are found in reading order", () => {
  const items = [widget("w1", "clock", 0, 0, 4, 2), app("a1", 0, 2)]
  assert.deepStrictEqual(M.freeSpot(items, grid, 1, 1), { x: 1, y: 2 })
  assert.deepStrictEqual(M.freeSpot(items, grid, 2, 2), { x: 1, y: 2 })
  assert.deepStrictEqual(M.freeSpot(items, grid, 4, 1), { x: 0, y: 3 })
  assert.strictEqual(M.freeSpot([widget("w", "notes", 0, 0, 4, 6)], grid, 1, 1), null)
})

test("overlap and fit", () => {
  assert.ok(M.overlaps({ x: 0, y: 0, w: 2, h: 2 }, { x: 1, y: 1, w: 1, h: 1 }))
  assert.ok(!M.overlaps({ x: 0, y: 0, w: 2, h: 2 }, { x: 2, y: 0, w: 1, h: 1 }))
  assert.ok(M.fits(grid, { x: 3, y: 5, w: 1, h: 1 }))
  assert.ok(!M.fits(grid, { x: 3, y: 5, w: 2, h: 1 }))
  assert.ok(!M.fits(grid, { x: -1, y: 0, w: 1, h: 1 }))
})

test("nearest free spot to a drop", () => {
  const items = [app("a1", 1, 1), app("a2", 2, 1)]
  assert.deepStrictEqual(M.nearestFreeSpot(items, grid, 1, 1, 1, 1, "x"), { x: 1, y: 0 })
  assert.deepStrictEqual(M.nearestFreeSpot(items, grid, 1, 1, 1, 1, "a1"), { x: 1, y: 1 })
})

test("a drag point maps to a cell on the grid", () => {
  assert.deepStrictEqual(M.cellForPoint(130, 160, 120, 150, 1, 1, grid), { x: 1, y: 1 })
  assert.deepStrictEqual(M.cellForPoint(-40, 9999, 120, 150, 2, 2, grid), { x: 0, y: 4 })
  assert.deepStrictEqual(M.cellForPoint(470, 0, 120, 150, 2, 1, grid), { x: 2, y: 0 })
  assert.strictEqual(M.pageShift(-0.7, 1, grid), -1)
  assert.strictEqual(M.pageShift(3.6, 1, grid), 1)
  assert.strictEqual(M.pageShift(2.9, 1, grid), 0)
})

// ---------------------------------------------------------------- persistence

test("the default layout uses only installed apps", () => {
  const l = M.defaultLayout(["foot.desktop", "chromium", "something-else"], grid)
  const apps = l.pages[0].items.filter((i) => i.kind === "app").map((i) => i.app)
  assert.deepStrictEqual(apps, ["chromium", "foot"])
  assert.strictEqual(l.pages.length, 2)
  assert.deepStrictEqual(M.parse(M.serialize(l)), l)
})

test("garbage reads as no layout", () => {
  for (const bad of ["", "{", "null", "[]", "{}", '{"pages": 3}'])
    assert.strictEqual(M.parse(bad), null, bad)
})

test("a stored layout round-trips", () => {
  const l = layoutOf([widget("w1", "clock", 0, 0, 4, 2), app("a2", 3, 5)], [widget("w3", "notes", 1, 1, 2, 2)])
  l.home = 1
  const again = M.parse(M.serialize(l))
  assert.deepStrictEqual(again, l)
  assert.strictEqual(again.home, 1)
  assert.strictEqual(again.pages[1].items[0].config.text, "")
})

test("serialize keeps only stored fields", () => {
  const l = M.addApp(layoutOf([]), 0, "foot")
  assert.ok(l.placed)
  const raw = JSON.parse(M.serialize(l))
  assert.strictEqual(raw.placed, undefined)
  assert.deepStrictEqual(Object.keys(raw.pages[0].items[0]).sort(), ["app", "h", "id", "kind", "w", "x", "y"])
})

test("normalize repairs what it can", () => {
  const l = M.normalize({
    grid: { columns: 99, rows: "x" },
    nextId: 2,
    home: 7,
    pages: [{ items: [
      widget("w1", "clock", 0, 0, 9, 9),            // too big: clamped to clock's max 4x3
      widget("w2", "nonsense", 0, 0, 1, 1),         // unknown type: dropped
      { kind: "app", app: "", x: 0, y: 0 },          // no app: dropped
      { kind: "app", app: "foot.desktop", x: 0, y: 0, id: "a9" }, // overlaps the clock: moved
      app("a9", 5, 5),                               // duplicate id: renumbered
      "junk", null
    ] }, { items: "nope" }]
  })
  assert.deepStrictEqual(l.grid, { columns: 6, rows: 6 })
  const clock = M.findItem(l, "w1").item
  assert.deepStrictEqual([clock.w, clock.h], [4, 3])
  assert.strictEqual(M.findItem(l, "w2"), null)
  const foot = l.pages[0].items.find((i) => i.app === "foot")
  assert.ok(foot && !M.overlaps(foot, clock))
  const idsSeen = l.pages[0].items.map((i) => i.id)
  assert.strictEqual(new Set(idsSeen).size, idsSeen.length)
  assert.ok(l.nextId > 9)
  assert.strictEqual(l.home, 1)
  assert.deepStrictEqual(l.pages[1].items, [])
})

test("widget config keeps known keys of the right type", () => {
  const c = M.mergeConfig(M.REGISTRY.weather.config, { enabled: "yes", place: "Oslo", latitude: 59.9, extra: 1 })
  assert.deepStrictEqual(c, { enabled: false, useLocation: true, place: "Oslo", latitude: 59.9, longitude: null, units: "celsius" })
})

test("missing apps stay on the layout and are reported", () => {
  const l = layoutOf([app("gone", 0, 0), app("here", 1, 0)])
  assert.deepStrictEqual(M.missingApps(l, ["here.app.desktop"]), ["gone.app"])
  assert.strictEqual(l.pages[0].items.length, 2)
})

// ---------------------------------------------------------------- edits

test("adding fills the page, then the next, then a new page", () => {
  let l = layoutOf([widget("w1", "notes", 0, 0, 4, 5)], [widget("w2", "notes", 0, 0, 4, 6)])
  l = M.addApp(l, 0, "a")
  assert.deepStrictEqual(l.placed, { page: 0, x: 0, y: 5, id: l.placed.id })
  for (let i = 0; i < 3; i++) l = M.addApp(l, 0, "b" + i)
  l = M.addApp(l, 0, "c")
  assert.strictEqual(l.placed.page, 2)
  assert.strictEqual(l.pages.length, 3)
  l = M.addWidget(l, 1, "clock")
  assert.strictEqual(l.placed.page, 2)
  assert.strictEqual(M.addWidget(l, 0, "nope"), null)
})

test("adding does not change the argument", () => {
  const l = layoutOf([])
  const before = M.serialize(l)
  M.addWidget(l, 0, "battery")
  assert.strictEqual(M.serialize(l), before)
})

test("moves snap to the nearest free cell, or across pages", () => {
  let l = layoutOf([app("a1", 0, 0), app("a2", 1, 0)], [])
  l = M.moveItem(l, "a1", 0, 1, 0)               // onto a2: the two swap
  assert.ok(l.moved)
  assert.deepStrictEqual([M.findItem(l, "a1").item.x, M.findItem(l, "a2").item.x], [1, 0])
  let w = layoutOf([widget("w1", "notes", 0, 0, 2, 2), app("a1", 2, 0)])
  w = M.moveItem(w, "a1", 0, 1, 1)               // onto a bigger item: nearest free
  assert.deepStrictEqual([M.findItem(w, "a1").item.x, M.findItem(w, "a1").item.y], [2, 1])
  assert.ok(w.moved)
  const a1 = M.findItem(l, "a1").item
  l = M.moveItem(l, "a1", 1, 3, 5)
  assert.deepStrictEqual(M.findItem(l, "a1"), { page: 1, index: 0, item: Object.assign({}, a1, { x: 3, y: 5 }) })
  l = M.moveItem(l, "a1", 1, 99, -4)              // clamped to the grid
  assert.deepStrictEqual([M.findItem(l, "a1").item.x, M.findItem(l, "a1").item.y], [3, 0])
})

test("a move onto a full page is refused", () => {
  const full = []
  for (let y = 0; y < 6; y++) for (let x = 0; x < 4; x++) full.push(app("f" + x + y, x, y))
  const l = layoutOf([app("a1", 0, 0)], full)
  const out = M.moveItem(l, "a1", 1, 0, 0)
  assert.strictEqual(out.moved, false)
  assert.strictEqual(M.findItem(out, "a1").page, 0)
})

test("resizing respects the widget's limits, the grid and neighbours", () => {
  let l = layoutOf([widget("w1", "notes", 0, 0, 2, 2), app("a1", 3, 0)])
  l = M.resizeItem(l, "w1", 3, 3)
  assert.deepStrictEqual([M.findItem(l, "w1").item.w, M.findItem(l, "w1").item.h], [3, 3])
  const blocked = M.resizeItem(l, "w1", 4, 3)    // a1 is at (3, 0)
  assert.deepStrictEqual([M.findItem(blocked, "w1").item.w], [3])
  l = M.resizeItem(l, "w1", 0, 99)               // notes: min 1x1, max 4x6
  assert.deepStrictEqual([M.findItem(l, "w1").item.w, M.findItem(l, "w1").item.h], [1, 6])
  let c = layoutOf([widget("c", "clock", 0, 4, 4, 2)])
  c = M.resizeItem(c, "c", 1, 3)                 // clock: min 2x1, and only 2 rows left
  assert.deepStrictEqual([M.findItem(c, "c").item.w, M.findItem(c, "c").item.h], [2, 2])
  const a = layoutOf([app("a1", 0, 0)])
  assert.strictEqual(M.resizeItem(a, "a1", 2, 2), a)   // apps are 1x1
})

test("remove and config", () => {
  let l = layoutOf([widget("w1", "weather", 0, 0, 4, 1)])
  l = M.setConfig(l, "w1", { enabled: true, place: "Paris", latitude: 48.85, bogus: 1 })
  assert.deepStrictEqual(M.findItem(l, "w1").item.config,
    { enabled: true, useLocation: true, place: "Paris", latitude: 48.85, longitude: null, units: "celsius" })
  l = M.removeItem(l, "w1")
  assert.deepStrictEqual(l.pages[0].items, [])
})

test("undo puts a removed item back with its settings", () => {
  let l = layoutOf([app("a1", 0, 0), widget("w1", "weather", 0, 1, 4, 1), app("a2", 1, 0)])
  l = M.setConfig(l, "w1", { enabled: true, place: "Paris" })
  const removed = M.findItem(l, "w1")
  const before = M.serialize(l)
  const gone = M.removeItem(l, "w1")
  // In its old cell, at its old place in the page's list
  const back = M.restoreItem(gone, removed)
  assert.deepStrictEqual(back.placed, { page: 0, x: 0, y: 1 })
  delete back.placed
  assert.strictEqual(M.serialize(back), before)
  // Something else took the cell meanwhile: the nearest free one
  const occupied = layoutOf([app("a1", 0, 0), app("a2", 1, 0), app("b", 2, 1)])
  const near = M.restoreItem(occupied, removed)
  assert.deepStrictEqual(near.placed, { page: 0, x: 0, y: 2 })
  assert.strictEqual(M.findItem(near, "w1").item.config.place, "Paris")
  assert.ok(M.findItem(near, "b"))
  // Its page is full: the next page with room
  const full = layoutOf([widget("big", "notes", 0, 0, 4, 6)], [])
  const onNext = M.restoreItem(full, { page: 0, index: 0, item: app("z", 0, 0) })
  assert.deepStrictEqual(onNext.placed, { page: 1, x: 0, y: 0 })
  // Its page was removed: the last page
  const lastPage = M.restoreItem(layoutOf([]), { page: 3, index: 0, item: app("y", 1, 1) })
  assert.deepStrictEqual(lastPage.placed, { page: 0, x: 1, y: 1 })
  // Already back, or bigger than the grid now: nothing to do
  assert.strictEqual(M.restoreItem(back, removed), null)
  assert.strictEqual(M.restoreItem(layoutOf([]), { page: 0, index: 0, item: widget("w9", "notes", 0, 0, 6, 1) }), null)
  assert.strictEqual(M.restoreItem(gone, null), null)
})

test("pages: add, remove, reorder, home follows", () => {
  let l = layoutOf([app("a", 0, 0)], [app("b", 0, 0)], [app("c", 0, 0)])
  l = M.setHome(l, 1)
  l = M.addPage(l, 0)
  assert.strictEqual(l.pages.length, 4)
  assert.strictEqual(l.home, 2)
  assert.deepStrictEqual(ids(l, 2), ["b"])
  l = M.movePage(l, 2, 3)
  assert.deepStrictEqual(ids(l, 3), ["b"])
  assert.strictEqual(l.home, 3)
  l = M.movePage(l, 1, 3)
  assert.deepStrictEqual(ids(l, 2), ["b"])
  assert.strictEqual(l.home, 2)
  l = M.removePage(l, 0)
  assert.strictEqual(l.home, 1)
  l = M.removePage(l, 1)
  assert.strictEqual(l.home, 1)
  assert.deepStrictEqual(ids(l, 0), ["c"])
  assert.deepStrictEqual(ids(l, 1), ["a"])
  const one = layoutOf([])
  assert.strictEqual(M.removePage(one, 0), one)
})

test("a smaller grid re-places what no longer fits", () => {
  const l = layoutOf([widget("w1", "notes", 0, 0, 4, 6), app("a1", 0, 0)])
  const small = M.setGrid(l, 3, 4)
  assert.deepStrictEqual(small.grid, { columns: 3, rows: 4 })
  const notes = M.findItem(small, "w1").item
  assert.deepStrictEqual([notes.w, notes.h], [3, 4])
  assert.strictEqual(M.findItem(small, "a1").page, 1)
})

// ---------------------------------------------------------------- widgets

test("weather requests carry only a rounded place", () => {
  assert.strictEqual(M.geocodeUrl(" São Paulo "),
    "https://geocoding-api.open-meteo.com/v1/search?count=1&format=json&name=S%C3%A3o%20Paulo")
  const u = M.forecastUrl(59.91273, 10.74609, "fahrenheit")
  assert.ok(u.startsWith("https://api.open-meteo.com/v1/forecast?latitude=59.91&longitude=10.75&"))
  assert.ok(u.endsWith("&temperature_unit=fahrenheit"))
  assert.ok(!M.forecastUrl(1, 2, "celsius").includes("fahrenheit"))
})

test("weather responses", () => {
  assert.deepStrictEqual(M.parseGeocode('{"results":[{"name":"Oslo","latitude":59.9,"longitude":10.7}]}'),
    { name: "Oslo", latitude: 59.9, longitude: 10.7 })
  assert.strictEqual(M.parseGeocode('{"generationtime_ms":0.1}'), null)
  assert.strictEqual(M.parseGeocode("<html>"), null)
  assert.deepStrictEqual(M.parseForecast(JSON.stringify({ current: { temperature_2m: 11.6, weather_code: 3 },
    daily: { temperature_2m_max: [14.2], temperature_2m_min: [6.5] } })), { temperature: 12, code: 3, high: 14, low: 7 })
  assert.strictEqual(M.parseForecast("{}"), null)
  assert.strictEqual(M.weatherText(0).text, "Clear")
  assert.strictEqual(M.weatherText(63).text, "Rain")
  assert.strictEqual(M.weatherText(1234).text, "")
})

test("agenda lines from khal", () => {
  const out = M.parseAgenda("2026-10-13\t09:30\tStand-up\n2026-10-14\t\tHoliday\tall day\n\nbroken line\n", 8)
  assert.deepStrictEqual(out, [{ date: "2026-10-13", time: "09:30", title: "Stand-up" },
                               { date: "2026-10-14", time: "", title: "Holiday all day" }])
  assert.strictEqual(M.parseAgenda("a\tb\tc\n".repeat(20), 5).length, 5)
})

test("month grid", () => {
  const cells = M.monthGrid(2026, 9, new Date(2026, 9, 13), 1) // October 2026, weeks from Monday
  assert.strictEqual(cells.length, 42)
  assert.deepStrictEqual(cells.slice(0, 4).map((c) => [c.day, c.inMonth]), [[28, false], [29, false], [30, false], [1, true]])
  assert.strictEqual(cells.filter((c) => c.today).length, 1)
  assert.strictEqual(cells.find((c) => c.today).day, 13)
})

test("command output", () => {
  assert.strictEqual(M.commandText("one\ntwo\nthree\n\n", 2), "one\ntwo")
  assert.strictEqual(M.commandText("", 3), "")
})

test("the clock follows the system's 12- or 24-hour choice", () => {
  assert.strictEqual(M.systemTimeFormat("ddd MMM d  h:mm AP"), "h:mm AP")
  assert.strictEqual(M.systemTimeFormat("hh:mm ap"), "h:mm AP")
  assert.strictEqual(M.systemTimeFormat("dddd HH:mm"), "HH:mm")
  assert.strictEqual(M.systemTimeFormat("HH:mm 'h'"), "HH:mm")
  assert.strictEqual(M.systemTimeFormat(""), "HH:mm")
  assert.strictEqual(M.widgetSpec("clock").config.timeFormat, "")
})

// ---------------------------------------------------------------- the user's own widgets

const U = require(path.join(__dirname, "../plugins/omamobile.home/UserWidgets.js"))

const record = (id, extra) => Object.assign({
  id, source: "user", dir: "/home/u/.config/omamobile/widgets/" + id, status: "ok", errors: [], warnings: [], hash: "h-" + id,
  manifest: { id, name: "Widget " + id, icon: "x", entry: "Widget.qml", size: [2, 1], min: [1, 1], max: [3, 2],
              capabilities: [], defaults: { text: "hi", count: 3 }, schema: [{ key: "count", type: "integer", min: 1, max: 9 }] },
  detected: [], undeclared: [], lint: null
}, extra || {})
const scanOf = (...widgets) => U.parseScan(JSON.stringify({ version: 1, dir: "/home/u/.config/omamobile/widgets", widgets, examples: [] }))

test("user widget discovery: the scan's verdicts, bad records dropped", () => {
  const scan = scanOf(record("u.ok"), record("u.bad", { status: "error", errors: ["no manifest.json"], manifest: null }),
    { id: "../escape" }, { id: "Upper" }, null, "junk")
  assert.ok(scan.ok)
  assert.deepStrictEqual(scan.widgets.map((r) => r.id), ["u.ok", "u.bad"])
  assert.strictEqual(U.findRecord(scan, "u.ok").status, "ok")
  // "ok" without a manifest is not ok.
  assert.strictEqual(scanOf(record("u.x", { manifest: null })).widgets[0].status, "error")
  for (const bad of ["", "{", "[]", '{"widgets": 3}'])
    assert.strictEqual(U.parseScan(bad).ok, false, bad)
})

test("the catalog sizes user widgets by their manifests", () => {
  const cat = U.catalog(scanOf(record("u.ok"), record("u.bad", { status: "error", errors: ["x"] }), record("u.none", { manifest: null })))
  assert.deepStrictEqual(Object.keys(cat).sort(), ["u.bad", "u.ok"])
  assert.deepStrictEqual([cat["u.ok"].size, cat["u.ok"].min, cat["u.ok"].max], [[2, 1], [1, 1], [3, 2]])
  assert.deepStrictEqual(cat["u.ok"].config, { text: "hi", count: 3 })
  assert.ok(cat["u.ok"].user)
  assert.strictEqual(M.widgetSpec("user:u.ok", cat), cat["u.ok"])
  assert.strictEqual(M.widgetSpec("user:u.none", cat), null)
  assert.strictEqual(M.widgetSpec("u.ok", cat), null)          // only through the prefix
  assert.strictEqual(M.widgetSpec("user:clock", cat), null)     // never a built-in
  assert.ok(M.isUserType("user:a.b-c_d"))
  for (const bad of ["user:", "user:../x", "user:A", "user:a/b", "clock", "user:" + "a".repeat(65)])
    assert.ok(!M.isUserType(bad), bad)
})

test("user widgets persist by id, with their settings", () => {
  const cat = U.catalog(scanOf(record("u.ok")))
  let l = layoutOf([])
  l = M.addWidget(l, 0, "user:u.ok", cat)
  const id = l.placed.id
  assert.deepStrictEqual([M.findItem(l, id).item.w, M.findItem(l, id).item.h], [2, 1])
  l = M.setConfig(l, id, { count: 7, extra: "kept" }, cat)
  const again = M.parse(M.serialize(l), cat)
  const item = M.findItem(again, id).item
  assert.strictEqual(item.type, "user:u.ok")
  assert.deepStrictEqual(item.config, { text: "hi", count: 7, extra: "kept" })
  // A value of the wrong type for a default is dropped, the default kept.
  assert.deepStrictEqual(M.mergeUserConfig({ count: 3 }, { count: "seven" }), { count: 3 })
})

test("a user widget the scan doesn't know stays, with its size and settings", () => {
  // Read before the first scan, or while its folder is gone or broken.
  const raw = { grid, pages: [{ items: [{ id: "w1", kind: "widget", type: "user:u.gone", x: 0, y: 0, w: 3, h: 2, config: { a: 1 } },
                                        { id: "w2", kind: "widget", type: "user:../bad", x: 0, y: 3, w: 1, h: 1 }] }] }
  const l = M.normalize(raw, {})
  const kept = M.findItem(l, "w1").item
  assert.deepStrictEqual([kept.w, kept.h, kept.config], [3, 2, { a: 1 }])
  assert.strictEqual(M.findItem(l, "w2"), null)                 // not a valid id: dropped
  assert.deepStrictEqual(M.sizeLimits(kept, grid, {}), { minW: 1, minH: 1, maxW: 4, maxH: 6 })
  // Once it is known again, its manifest's limits apply.
  const cat = U.catalog(scanOf(record("u.gone")))
  const clamped = M.findItem(M.normalize(raw, cat), "w1").item
  assert.deepStrictEqual([clamped.w, clamped.h], [3, 2])
  const tight = U.catalog(scanOf(record("u.gone", { manifest: Object.assign({}, record("u").manifest, { max: [2, 1] }) })))
  const smaller = M.findItem(M.normalize(raw, tight), "w1").item
  assert.deepStrictEqual([smaller.w, smaller.h], [2, 1])
  // A just-created widget can be placed before the scan has seen it.
  const placed = M.addWidget(layoutOf([]), 0, "user:u.new", {})
  assert.ok(placed.placed)
  assert.deepStrictEqual(M.findItem(placed, placed.placed.id).item.w, M.MISSING_SPEC.size[0])
})

test("resizing a user widget keeps to its manifest", () => {
  const cat = U.catalog(scanOf(record("u.ok")))
  let l = M.addWidget(layoutOf([]), 0, "user:u.ok", cat)
  const id = l.placed.id
  l = M.resizeItem(l, id, 9, 9, cat)
  assert.deepStrictEqual([M.findItem(l, id).item.w, M.findItem(l, id).item.h], [3, 2])
  const small = M.setGrid(l, 3, 4, cat)
  assert.deepStrictEqual([M.findItem(small, id).item.w, M.findItem(small, id).item.h], [3, 2])
})

test("removing a user widget takes it off every page", () => {
  const cat = U.catalog(scanOf(record("u.ok")))
  let l = layoutOf([], [])
  l = M.addWidget(l, 0, "user:u.ok", cat)
  l = M.addWidget(l, 1, "user:u.ok", cat)
  l = M.addWidget(l, 1, "clock", cat)
  l = M.removeWidgetType(l, "user:u.ok")
  assert.deepStrictEqual(l.pages.map((p) => p.items.map((i) => i.type)), [[], ["clock"]])
})

test("broken widgets become cards with the message", () => {
  const scan = scanOf(record("u.ok"), record("u.bad", { status: "error", errors: ["Widget.qml:3: Syntax error", "second"] }))
  assert.deepStrictEqual(U.cardState(scan, "u.ok"), { state: "ok", message: "" })
  assert.deepStrictEqual(U.cardState(scan, "u.bad"), { state: "error", message: "Widget.qml:3: Syntax error\nsecond" })
  assert.strictEqual(U.cardState(scan, "u.gone").state, "missing")
  assert.strictEqual(U.cardState(U.emptyScan(), "u.ok").state, "waiting")
  const undeclared = record("u.net", { status: "error", undeclared: ["network"], errors: ["uses the network, but..."] })
  assert.ok(U.statusLine(undeclared).includes("uses the internet without declaring it"))
  assert.ok(U.statusLine(record("u.cmd", { manifest: Object.assign({}, record("u").manifest, { capabilities: ["commands"] }) })).includes("runs commands"))
  assert.strictEqual(U.tildePath("/home/u/.config/x", "/home/u"), "~/.config/x")
  assert.strictEqual(U.tildePath("/home/user2/x", "/home/u"), "/home/user2/x")
})

test("new widget ids and names", () => {
  assert.strictEqual(U.slug("Show the moon phase, please!"), "moon-phase-please")
  assert.strictEqual(U.slug("Café ☕ timer"), "caf-timer")
  assert.strictEqual(U.slug("!!!"), "widget")
  assert.strictEqual(U.newId("moon phase", "Alice", []), "alice.moon-phase")
  assert.strictEqual(U.newId("moon phase", "alice", ["alice.moon-phase", "alice.moon-phase-2"]), "alice.moon-phase-3")
  assert.strictEqual(U.newId("x", "", []), "my.x")
  assert.strictEqual(U.newId("sunrise and sunset", "omamobile", []), "my.sunrise-sunset")
  assert.strictEqual(U.newId("clock", "omarchy", []), "my.clock")
  for (const id of [U.newId("$(rm -rf ~); `x`", "a b", []), U.newId("a".repeat(200), "b".repeat(200), [])]) {
    assert.ok(U.ID_RE.test(id) && id.length <= 64, id)
    assert.ok(M.isUserType(U.typeFor(id)), id)
  }
  assert.strictEqual(U.nameFrom("  a big button that starts a timer. "), "A big button that")
  assert.strictEqual(U.nameFrom(""), "My widget")
  assert.strictEqual(String(U.ID_RE), String(M.USER_ID_RE))
})

test("the description reaches the agent as one argument, verbatim", () => {
  const nasty = 'moon phase; $(touch /tmp/x) `id` "q" \'s\' & | > ~/f\nsecond line -- --inline'
  const prompt = U.createPrompt(nasty, "/home/u/.config/omamobile/widgets/u.moon", "/usr/share/omamobile/shell/WIDGETS.md")
  assert.ok(prompt.endsWith("The user asked for: " + nasty.trim()))
  assert.ok(prompt.includes("/usr/share/omamobile/shell/WIDGETS.md"))
  assert.ok(prompt.includes("work only inside this folder"))
  assert.ok(prompt.includes("omamobile-widget check ."))
  assert.ok(!prompt.startsWith("-"))                           // never read as an option
  const argv = U.agentArgv("u.moon", prompt)
  assert.deepStrictEqual(argv, ["omamobile-widget", "agent", "u.moon", prompt])
  assert.strictEqual(argv.length, 4)
  const edit = U.editPrompt("", "/w/u.moon", "", "Moon", ["Widget.qml:3: Syntax error"])
  assert.ok(edit.includes("- Widget.qml:3: Syntax error") && edit.includes("Ask the user what to change."))
  assert.ok(U.editPrompt("bigger", "/w", "", "Moon", []).endsWith("The user asked for: bigger"))
  assert.deepStrictEqual(U.newArgv("u.moon", "Moon; rm"), ["omamobile-widget", "new", "u.moon", "Moon; rm"])
})

test("what the agent's launch means to the phone", () => {
  assert.strictEqual(U.agentOutcome(0, "").kind, "launched")
  const none = U.agentOutcome(3, "No coding agent is chosen in Omarchy yet. Pick one in the menu that opened, then try again.\n")
  assert.strictEqual(none.kind, "no-agent")
  assert.ok(none.message.includes("No coding agent"))
  assert.strictEqual(U.agentOutcome(3, "").kind, "no-agent")
  const missing = U.agentOutcome(4, "codex is not installed. Choose an installed agent with: omarchy default agent <name>\n")
  assert.deepStrictEqual(missing, { kind: "failed", message: "codex is not installed. Choose an installed agent with: omarchy default agent <name>" })
  assert.ok(U.agentOutcome(2, "").message.includes("status 2"))
})

test("user widget settings are typed by the schema", () => {
  assert.strictEqual(U.coerceSetting({ type: "integer", min: 1, max: 9 }, "42"), 9)
  assert.strictEqual(U.coerceSetting({ type: "integer" }, "x"), null)
  assert.strictEqual(U.coerceSetting({ type: "number" }, "2.5"), 2.5)
  assert.strictEqual(U.coerceSetting({ type: "boolean" }, true), true)
  assert.strictEqual(U.coerceSetting({ type: "enum", options: ["a", "b"] }, "b"), "b")
  assert.strictEqual(U.coerceSetting({ type: "enum", options: ["a", "b"] }, "c"), null)
  assert.strictEqual(U.coerceSetting({ type: "string" }, 12), "12")
  assert.strictEqual(U.coerceSetting(undefined, "x"), null)
})

test("host.run: declared, one at a time, rate-limited, with a timeout", () => {
  assert.ok(U.runCheck(["df"], false, false, 1e9).includes('"commands"'))
  assert.strictEqual(U.runCheck(["df"], true, false, 1e9), "")
  assert.ok(U.runCheck(["df"], true, true, 1e9).includes("still running"))
  assert.ok(U.runCheck(["df"], true, false, 500).includes("rate limit"))
  assert.strictEqual(U.runCheck(["df"], true, false, 1500, 1000), "")
  for (const bad of [[], "df -h", [{}], null]) assert.ok(U.runCheck(bad, true, false, 1e9) !== "", JSON.stringify(bad))
  assert.strictEqual(U.runTimeout(), 10)
  assert.strictEqual(U.runTimeout({ timeout: 300 }), 30)
  assert.strictEqual(U.runTimeout({ timeout: 0 }), 1)
  assert.deepStrictEqual(U.timeoutArgv(["sh", "-c", "x; y"], 5), ["timeout", "-k", "2", "5", "sh", "-c", "x; y"])
  const r = U.runResult(124, "a".repeat(70000), null)
  assert.ok(r.timedOut && r.stdout.length === 65536 && r.stderr === "")
})

// ---------------------------------------------------------------- the registry

const fs = require("fs")
const HOME_DIR = path.join(__dirname, "../plugins/omamobile.home")
const FIELD_TYPES = ["string", "path", "integer", "number", "boolean", "enum"]

test("every built-in is valid, sized inside its limits, and has its QML", () => {
  assert.deepStrictEqual([...M.WIDGET_ORDER].sort(), Object.keys(M.REGISTRY).sort())
  assert.strictEqual(new Set(M.WIDGET_ORDER).size, M.WIDGET_ORDER.length)
  const names = new Set()
  for (const type of M.WIDGET_ORDER) {
    const s = M.REGISTRY[type]
    assert.ok(/^[a-z][A-Za-z0-9]*$/.test(type) || /^owl:simonschubert\.[a-z0-9-]+$/.test(type), type)
    assert.ok(typeof s.name === "string" && s.name.length > 0 && s.name.length <= 40, type)
    assert.ok(!names.has(s.name), "two built-ins are called " + s.name)
    names.add(s.name)
    assert.ok(typeof s.icon === "string" && s.icon.length > 0 && s.icon.length <= 4, type)
    for (const k of ["min", "max", "size"]) {
      assert.ok(Array.isArray(s[k]) && s[k].length === 2 && s[k].every((n) => Number.isInteger(n) && n >= 1), type + " " + k)
    }
    assert.ok(s.min[0] <= s.size[0] && s.size[0] <= s.max[0] && s.min[1] <= s.size[1] && s.size[1] <= s.max[1], type + " size")
    assert.ok(s.max[0] <= M.GRID.columns && s.max[1] <= M.GRID.rows, type + " fits the default grid")
    assert.strictEqual(typeof s.network, "boolean", type)
    assert.ok(s.config && typeof s.config === "object" && !Array.isArray(s.config), type)
    if (M.isOwlType(type)) continue        // drawn by OwlCell.qml; the internet waits for its approval
    const file = type.charAt(0).toUpperCase() + type.slice(1) + "Widget.qml"
    assert.ok(fs.existsSync(path.join(HOME_DIR, file)), file)
    // Network widgets are opt-in: off until the user turns them on.
    if (s.network) assert.strictEqual(s.config.enabled, false, type + " starts off")
  }
})

test("the OWL built-ins replace the 47 ports, named and sized as before", () => {
  assert.strictEqual(M.OWL_ORDER.length, 47)
  assert.ok(!fs.existsSync(path.join(HOME_DIR, "ported")) && !fs.existsSync(path.join(HOME_DIR, "PortedWidget.qml")))
  for (const port of M.PORTED_ORDER) {
    const type = M.owlTypeFor(port)
    const s = M.REGISTRY[type], p = M.PORTED[port]
    assert.ok(s && M.WIDGET_ORDER.includes(type) && !M.REGISTRY[port], port)
    assert.deepStrictEqual([s.name, s.icon, s.min, s.max, s.size, s.network, s.credit], [p.name, p.icon, p.min, p.max, p.size, p.network, p.credit], port)
    assert.strictEqual(M.owlStoreId(type), p.credit)
    assert.ok(!fs.existsSync(path.join(HOME_DIR, port.charAt(0).toUpperCase() + port.slice(1) + "Widget.qml")), port + " has no QML left")
    assert.strictEqual(s.location, M.PORT_LOCATION.includes(port))
    if (s.location) assert.deepStrictEqual(s.schema.map((f) => f.key), ["useLocation"])
    const l = M.addWidget(M.emptyLayout(grid), 0, type)
    assert.deepStrictEqual(M.parse(M.serialize(l)).pages[0].items[0].config, s.config, type)
  }
})

// The owner's real layout, by shape: apps one per cell along the bottom of
// two pages, our clock and weather (with location), the Bitcoin widget
// (the crypto port, internet on), today with location, and a few ports.
// (test/owner-layout.json, also used by owl-core.js and the render harness)
const OWNER = require("./owner-layout.json")

test("an old layout's ports become their OWL originals, in place, idempotently", () => {
  const ports = M.portPlacements(OWNER)
  assert.deepStrictEqual(ports.map((p) => [p.id, p.from, p.to, p.internet]), [
    ["w3", "crypto", "owl:simonschubert.crypto", true],
    ["w4", "today", "owl:simonschubert.today", true],
    ["w9", "earthquakes", "owl:simonschubert.earthquakes", false],
    ["w10", "habits", "owl:simonschubert.habits", false],
    ["w11", "forecast", "owl:simonschubert.forecast", true],
    ["w13", "fetch", "owl:simonschubert.fetch", false],
    ["w14", "owl", "owl:simonschubert.owl", false],
    ["w15", "koiPond", "owl:simonschubert.koi-pond", false]])
  const catalog = { "derek.moon": { name: "Moon", icon: "x", min: [1, 1], max: [4, 4], size: [2, 2], network: false, config: {}, user: true } }
  const once = M.parse(JSON.stringify(OWNER), catalog)
  const by = {}
  once.pages.forEach((p, i) => p.items.forEach((it) => { by[it.id] = Object.assign({ page: i }, it) }))
  // Same page, place and size; apps and our own widgets untouched.
  for (const page of OWNER.pages) for (const it of page.items) {
    const now = by[it.id]
    assert.ok(now, it.id + " is still there")
    assert.deepStrictEqual([now.x, now.y, now.w, now.h], [it.x, it.y, it.w, it.h], it.id)
    if (it.kind === "app") assert.strictEqual(now.app, it.app)
  }
  assert.strictEqual(by.w1.type, "clock")
  assert.strictEqual(by.w2.type, "weather")
  assert.strictEqual(by.u12.type, "user:derek.moon")
  assert.strictEqual(by.w3.type, "owl:simonschubert.crypto")
  // Location stays on where it was on; a typed city and check-ins carry over as state.
  assert.deepStrictEqual(by.w4.config, { useLocation: true, locationText: "", owlState: {} })
  assert.deepStrictEqual(by.w11.config, { useLocation: false, locationText: "", owlState: { city: "Berlin" } })
  assert.deepStrictEqual(by.w10.config, { owlState: { done: ["read@2026-10-12"] } })
  assert.deepStrictEqual(by.w14.config, { owlState: { born: 1791800000, fed: 1791880000, pets: 4 } })
  // Idempotent: a migrated layout has no ports left and doesn't change again.
  assert.deepStrictEqual(M.portPlacements(once), [])
  const twice = M.parse(M.serialize(once), catalog)
  assert.strictEqual(M.serialize(twice), M.serialize(once))
})

test("what each port could do, for approving its original without asking", () => {
  assert.deepStrictEqual(M.portCapabilities("crypto"), { commands: false, network: true, hosts: ["coingecko.com"], files: false, notifications: false })
  assert.deepStrictEqual(M.portCapabilities("feeds"), { commands: true, network: true, hosts: null, files: false, notifications: false })
  assert.deepStrictEqual(M.portCapabilities("koiPond"), { commands: false, network: false, hosts: [], files: false, notifications: false })
  assert.strictEqual(M.portCapabilities("weather"), null)
})

// ---------------------------------------------------------------- landscape (TOUCH-PLAN 2.4, #85)

// Every item once, on the grid, overlapping nothing.
function tidy(layout, original) {
  const seen = []
  for (const page of layout.pages) {
    for (let i = 0; i < page.items.length; i++) {
      const a = page.items[i]
      assert.ok(M.fits(layout.grid, a), a.id + " fits " + JSON.stringify(a))
      for (let j = i + 1; j < page.items.length; j++) assert.ok(!M.overlaps(a, page.items[j]), a.id + " overlaps " + page.items[j].id)
      seen.push(a.id)
    }
  }
  const all = [].concat(...original.pages.map((p) => p.items.map((i) => i.id)))
  assert.deepStrictEqual(seen.sort(), all.sort())
}
const pixelPages = { portrait: [480, 908], landscape: [1040, 348] }
const byId = (layout) => { const o = {}; layout.pages.forEach((p, n) => p.items.forEach((i) => { o[i.id] = Object.assign({ page: n }, i) })); return o }

test("landscape swaps the grid and turns every widget with it; the tiles keep their row", () => {
  const l = layoutOf([widget("w1", "clock", 0, 0, 4, 2), app("a1", 1, 5), app("a2", 3, 5)])
  const before = M.serialize(l)
  const t = M.transposeLayout(l, {})
  assert.deepStrictEqual(t.grid, { columns: 6, rows: 4 })
  tidy(t, l)
  const at = byId(t)
  // 4x2 turned is 2x4; the clock's maximum (4x3) keeps it to 3 rows.
  assert.deepStrictEqual([at.w1.x, at.w1.y, at.w1.w, at.w1.h], [0, 0, 2, 3])
  // The tiles' portrait row (y 5) is a row under the clock, in order, not
  // a column at the right edge (the batch 4 phone check).
  assert.deepStrictEqual([at.a1.x, at.a1.y, at.a1.w, at.a1.h], [0, 3, 1, 1])
  assert.deepStrictEqual([at.a2.x, at.a2.y], [1, 3])
  assert.strictEqual(M.serialize(l), before, "the portrait layout is left alone")
  assert.strictEqual(t.home, l.home)
  assert.strictEqual(t.nextId, l.nextId)
})

test("landscape keeps a widget's size in pixels on the short, wide cells", () => {
  // Portrait cells are 120x151 px, landscape ones 173x87: a 2x2 today (240x302)
  // turned is 2 columns by 3 rows (346x261), not 2x2 (346x174), so its content
  // still fits; the 1x1 apps stay 1x1.
  const l = layoutOf([widget("w1", "clock", 0, 0, 4, 2), widget("w2", "owl:simonschubert.today", 0, 2, 2, 2),
                      widget("w3", "battery", 2, 2, 2, 1), app("a1", 2, 3), app("a2", 3, 3), widget("w4", "owl:simonschubert.fetch", 0, 4, 4, 2)])
  const t = M.transposeLayout(l, {}, pixelPages)
  tidy(t, l)
  const at = byId(t)
  assert.deepStrictEqual([at.w2.w, at.w2.h], [2, 3])
  assert.deepStrictEqual([at.w4.w, at.w4.h], [2, 4])
  assert.deepStrictEqual([at.a1.w, at.a1.h, at.a2.w, at.a2.h], [1, 1, 1, 1])
  assert.deepStrictEqual([at.w1.x, at.w1.y, at.w1.w, at.w1.h], [0, 0, 2, 3])
  // The battery (2x1, turned and clamped to 1x2) found no room beside the
  // others at that size, so it takes its minimum (1x1) on its own page
  // rather than a page of its own; the tiles follow in the free cells.
  assert.strictEqual(t.pages.length, 1)
  assert.strictEqual(at.w3.page, 0)
  assert.deepStrictEqual([at.w3.w, at.w3.h], [1, 1])
  assert.strictEqual(at.a1.page, 0)
  assert.strictEqual(at.a2.page, 0)
  assert.strictEqual(at.a1.y, at.a2.y, "the two tiles share a row")
  // Settings travel with the item.
  assert.deepStrictEqual(at.w2.config, l.pages[0].items[1].config)
})

test("landscape keeps a row of four tiles a row under two 2x2 widgets, on the page they came from", () => {
  // Page 1 of two: the phone check's case (two widgets side by side, a dock
  // row of four icons at the bottom). The view has two pages, like the
  // layout, and page 1 keeps all six items with the icons in one row.
  const l = layoutOf([widget("w0", "clock", 0, 0, 4, 2)],
                     [widget("w1", "notes", 0, 0, 2, 2), widget("w2", "owl:simonschubert.today", 2, 0, 2, 2),
                      app("a1", 0, 5), app("a2", 1, 5), app("a3", 2, 5), app("a4", 3, 5)])
  const t = M.transposeLayout(l, {}, pixelPages)
  tidy(t, l)
  assert.strictEqual(t.pages.length, 2)
  const at = byId(t)
  for (const id of ["w1", "w2", "a1", "a2", "a3", "a4"]) assert.strictEqual(at[id].page, 1, id + " stays on page 1")
  assert.deepStrictEqual([at.w1.x, at.w1.y, at.w1.w, at.w1.h], [0, 0, 2, 3])
  assert.deepStrictEqual([at.w2.x, at.w2.y, at.w2.w, at.w2.h], [2, 0, 2, 3])
  assert.deepStrictEqual(["a1", "a2", "a3", "a4"].map((id) => [at[id].x, at[id].y]), [[0, 3], [1, 3], [2, 3], [3, 3]])
})

test("landscape keeps two portrait rows of tiles as two rows, in order", () => {
  const l = layoutOf([widget("w1", "clock", 0, 0, 4, 2), app("a1", 0, 4), app("a2", 1, 4), app("a3", 2, 4), app("a4", 3, 4),
                      app("b1", 0, 5), app("b2", 1, 5), app("b3", 2, 5)])
  const t = M.transposeLayout(l, {}, pixelPages)
  tidy(t, l)
  const at = byId(t)
  assert.deepStrictEqual(["a1", "a2", "a3", "a4"].map((id) => [at[id].x, at[id].y]), [[0, 3], [1, 3], [2, 3], [3, 3]])
  // No row below the fourth: the second row takes the first free cells.
  assert.deepStrictEqual(["b1", "b2", "b3"].map((id) => [at[id].x, at[id].y]), [[2, 0], [3, 0], [4, 0]])
})

test("landscape never has more pages than the layout: a full page re-places, shrinks, then leaves out", () => {
  // Four 2x2 notes (each 2x3 turned: 24 cells for a 24-cell page) and eight
  // tiles: the fourth note shrinks to a 2x1, four tiles find cells, four
  // are left out, and nothing goes to a second page.
  const l = layoutOf([widget("w1", "notes", 0, 0, 2, 2), widget("w2", "notes", 2, 0, 2, 2), widget("w3", "notes", 0, 2, 2, 2), widget("w4", "notes", 2, 2, 2, 2),
                      app("a1", 0, 4), app("a2", 1, 4), app("a3", 2, 4), app("a4", 3, 4), app("b1", 0, 5), app("b2", 1, 5), app("b3", 2, 5), app("b4", 3, 5)])
  const t = M.transposeLayout(l, {}, pixelPages)
  assert.strictEqual(t.pages.length, 1)
  const items = t.pages[0].items
  for (let i = 0; i < items.length; i++) {
    assert.ok(M.fits(t.grid, items[i]), items[i].id + " fits")
    for (let j = i + 1; j < items.length; j++) assert.ok(!M.overlaps(items[i], items[j]), items[i].id + " overlaps " + items[j].id)
  }
  const at = byId(t)
  for (const id of ["w1", "w2", "w3", "w4"]) assert.ok(at[id], id + " is shown")
  assert.ok(Math.min(at.w4.w * at.w4.h, at.w3.w * at.w3.h) < 6, "one note shrank")
  const shown = items.filter((i) => i.kind === "app").map((i) => i.id)
  assert.strictEqual(shown.length, 4, "four tiles fit: " + shown.join(" "))
  assert.deepStrictEqual(shown, ["a1", "a2", "a3", "a4"], "the first row's tiles come first")
  assert.strictEqual(M.serialize(l), M.serialize(M.normalize(JSON.parse(M.serialize(l)), {})), "the layout is untouched")
})

test("landscape of an empty layout is an empty layout on the turned grid", () => {
  const t = M.transposeLayout(M.emptyLayout(grid), {}, pixelPages)
  assert.deepStrictEqual(t.grid, { columns: 6, rows: 4 })
  assert.deepStrictEqual(t.pages, [{ items: [] }])
})

let failed = 0
for (const [name, fn] of tests) {
  try { fn(); console.log("ok - home model: " + name) } catch (e) { failed++; console.log("not ok - home model: " + name + "\n  " + (e.stack || e)) }
}
process.exit(failed ? 1 : 0)
