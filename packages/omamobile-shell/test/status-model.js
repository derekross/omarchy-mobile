// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.bar/StatusModel.js: the mobile network
// and the call chip. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.bar/StatusModel.js"))
const cp = (c) => String.fromCodePoint(c)

assert.strictEqual(M.cellGlyph(null), "", "no watcher, no icon")
assert.strictEqual(M.cellGlyph(M.parseCell('{"modem":false,"state":"none"}')), "", "no modem, no icon")
const c = (o) => Object.assign({ modem: true, state: "registered", strength: -1, tech: "LTE", roaming: false }, o)
assert.strictEqual(M.cellGlyph(c({ state: "no-sim" })), cp(0xF0783))
assert.strictEqual(M.cellText(c({ state: "no-sim" })), "No SIM")
assert.strictEqual(M.cellText(c({ state: "locked" })), "SIM locked")
assert.strictEqual(M.cellGlyph(c({ state: "off" })), cp(0xF001D), "radio off is the airplane")
assert.strictEqual(M.cellGlyph(c({ state: "searching" })), cp(0xF08BF))
assert.strictEqual(M.cellText(c({ state: "searching" })), "")
assert.strictEqual(M.cellGlyph(c({})), cp(0xF08BF), "registered with no reading: empty bars, not off")
assert.strictEqual(M.cellGlyph(c({ strength: 90 })), cp(0xF08BE))
assert.strictEqual(M.cellText(c({})), "LTE")
assert.strictEqual(M.cellText(c({ roaming: true })), "LTE R")
assert.strictEqual(M.cellText(c({ tech: "", roaming: true })), "R")
assert.strictEqual(M.parseCell("nope"), null)
assert.strictEqual(M.cellGlyph(c({ state: "connected", strength: 90, data: false })), cp(0xF0783), "mobile data off: crossed out, as the tile")
assert.strictEqual(M.cellGlyph(c({ state: "connected", strength: 90, data: true })), cp(0xF08BE))
assert.strictEqual(M.cellGlyph(M.parseCell('{"modem":true,"state":"connected","strength":90,"tech":"LTE"}')), cp(0xF08BE), "a watcher without data: the bars")
assert.strictEqual(M.parseCell('{"modem":true,"state":"connected","data":false}').data, false)
assert.strictEqual(M.cellText(c({ state: "connected", data: false })), "LTE", "the network type stays beside it")
console.log("ok - status model: the mobile network's icon and words")

const now = 1760000000000
const line = (calls) => JSON.stringify({ agent: true, calls: calls })
assert.strictEqual(M.callChip(line([]), now), "")
assert.strictEqual(M.callChip(line([{ id: "a", state: "ringing-in" }]), now), "", "a ringing call has the card, not the chip")
assert.strictEqual(M.callChip(line([{ id: "a", state: "active", answeredMs: now - 83000 }]), now), "1:23")
assert.strictEqual(M.callChip(line([{ id: "a", state: "dialing" }]), now), "Calling")
assert.strictEqual(M.callChip(line([{ id: "a", state: "held" }]), now), "On hold")
assert.strictEqual(M.callChip(JSON.stringify({ agent: false, calls: [{ id: "a", state: "active", answeredMs: 1 }] }), now), "")
assert.strictEqual(M.callChip("bad", now), null, "a bad line keeps the chip as it was")
assert.strictEqual(M.elapsed(3725000), "1:02:05")
console.log("ok - status model: the call chip")

assert.strictEqual(M.stampOf("1760000000123-4.json"), 1760000000123)
assert.strictEqual(M.stampOf("notes.json"), 0)
assert.strictEqual(M.parseStamp(" 1760000000000\n"), 1760000000000)
assert.strictEqual(M.parseStamp("junk"), 0)
assert.strictEqual(M.parseStamp(undefined), 0)
const files = ["1000-1.json", "2000-2.json", "3000-3.json", "3000-3.json.tmp"]
assert.strictEqual(M.unreadCount(files, 0), 3, "nothing seen yet: every history file")
assert.strictEqual(M.unreadCount(files, "2000"), 1, "only what arrived after the newest one the shade showed")
assert.strictEqual(M.unreadCount(files, 3000), 0)
assert.strictEqual(M.unreadCount([], 0), 0)
// A swipe in the shade forgets one history file: the count follows the
// directory, one fewer if that one was unread, the same if it was seen.
assert.strictEqual(M.unreadCount(files.filter((f) => f !== "3000-3.json"), "2000"), 0, "the unread one forgotten")
assert.strictEqual(M.unreadCount(files.filter((f) => f !== "1000-1.json"), "2000"), 1, "a seen one forgotten")
console.log("ok - status model: unread notifications")

// Omarchy 4.5: history.json, a JSON array of rows with `ts` in seconds (as
// 4.5.0-3's Store.closedEntry writes them); the shade's mark is the newest
// ts it showed, in milliseconds.
const hist45 = JSON.stringify([{ key: "n3", ts: 3, closed_ts: 9, closed_reason: "dismissed" },
                               { key: "n2", ts: 2.0004, closed_ts: 8, closed_reason: "expired" },
                               { key: "n1", ts: 1, closed_ts: 7, closed_reason: "dismissed" }]) + "\n"
assert.strictEqual(M.unreadStored(hist45, 0), 3, "nothing seen yet: every history row")
assert.strictEqual(M.unreadStored(hist45, "2000"), 1, "only what arrived after the newest one the shade showed")
assert.strictEqual(M.unreadStored(hist45, 3000), 0)
assert.strictEqual(M.unreadStored(JSON.stringify([{ ts: 1.9996 }]), 2000), 0, "rounded as the shade rounds")
assert.strictEqual(M.unreadStored("", 0), 0, "the empty file the service creates")
assert.strictEqual(M.unreadStored("[]\n", 0), 0)
assert.strictEqual(M.unreadStored("{\"ts\": 5}", 0), 0, "not an array")
assert.strictEqual(M.unreadStored(JSON.stringify({ length: 1, 0: { ts: 5 } }), 0), 0, "not an array, even one that looks like it")
assert.strictEqual(M.unreadStored("[{\"ts\": 5", 0), 0, "torn")
assert.strictEqual(M.unreadStored(JSON.stringify([null, 4, { ts: "x" }, { ts: -1 }, {}, { ts: 5 }]), 0), 1)
assert.strictEqual(M.unreadStored(undefined, 0), 0)
console.log("ok - status model: unread notifications on Omarchy 4.5")
// shell.json bar.batteryStyle and bar.statusIcons.
assert.strictEqual(M.batteryStyle(undefined), "icon-percent", "no config: icon and number, as before")
assert.strictEqual(M.batteryStyle({}), "icon-percent")
assert.strictEqual(M.batteryStyle({ showBatteryPercent: false }), "icon", "the older switch still counts")
assert.strictEqual(M.batteryStyle({ showBatteryPercent: true }), "icon-percent")
for (const s of ["icon", "percent", "icon-percent", "horizontal", "horizontal-percent"])
  assert.strictEqual(M.batteryStyle({ batteryStyle: s, showBatteryPercent: false }), s, "the style wins over the older switch")
assert.strictEqual(M.batteryStyle({ batteryStyle: "round" }), "icon-percent", "an unknown style is the default")
assert.strictEqual(M.batteryStyle({ batteryStyle: 3, showBatteryPercent: false }), "icon")
assert.strictEqual(M.iconShown(undefined, "bluetooth"), true)
assert.strictEqual(M.iconShown({ statusIcons: { bluetooth: false } }, "bluetooth"), false)
assert.strictEqual(M.iconShown({ statusIcons: { bluetooth: false } }, "wifi"), true)
assert.strictEqual(M.iconShown({ statusIcons: { wifi: "no" } }, "wifi"), true, "only false hides")
assert.strictEqual(M.iconShown({ statusIcons: null }, "cell"), true)
// Every charging glyph differs from the plain one at the same level (it
// carries the bolt), so the icon styles show it without a side bolt.
for (let p = 0; p <= 100; p += 5)
  assert.notStrictEqual(M.batteryIcon(p, true, false), M.batteryIcon(p, false, false), "charging glyph at " + p)
assert.strictEqual(M.boltGlyph(), cp(0xF140B))
assert.strictEqual(M.batteryLow(10, false), true)
assert.strictEqual(M.batteryLow(10, true), false, "charging is never the low colour")
assert.strictEqual(M.batteryLow(11, false), false)
assert.strictEqual(M.batteryLow(-1, false), false, "no reading is not low")
console.log("ok - status model: battery styles, icon switches, the bolt")

// The camera cutout: shell.json's bar.cutout over the device package's file
// over the default, which keeps the Pixels' centred holes clear.
assert.deepStrictEqual(M.cutout(undefined, ""), { center: 0.5, width: 40 }, "the default")
assert.deepStrictEqual(M.cutout({}, undefined), M.CUTOUT_DEFAULT)
assert.deepStrictEqual(M.cutout({ cutout: { center: 0.4, width: 30 } }, ""), { center: 0.4, width: 30 })
assert.deepStrictEqual(M.cutout({ cutout: { width: 52 } }, ""), { center: 0.5, width: 52 }, "one key; the other from below")
assert.strictEqual(M.cutout({ cutout: false }, ""), null, "false: no cutout")
assert.strictEqual(M.cutout({ cutout: { width: 0 } }, ""), null, "width 0: no cutout")
assert.deepStrictEqual(M.cutout({ cutout: { center: 2, width: -1 } }, ""), M.CUTOUT_DEFAULT, "out of range keeps what is below")
assert.deepStrictEqual(M.cutout({ cutout: { center: "0.25", width: "36" } }, ""), { center: 0.25, width: 36 }, "numbers as strings")
assert.deepStrictEqual(M.cutout({ cutout: { center: true, width: null } }, ""), M.CUTOUT_DEFAULT)
assert.deepStrictEqual(M.cutout({ cutout: "wide" }, ""), M.CUTOUT_DEFAULT, "not an object: ignored")
assert.deepStrictEqual(M.cutout({}, '{"center": 0.5, "width": 46}\n'), { center: 0.5, width: 46 }, "the device package's file")
assert.deepStrictEqual(M.cutout({ cutout: { width: 30 } }, '{"center": 0.3, "width": 46}'), { center: 0.3, width: 30 }, "shell.json over the device's file, key by key")
assert.strictEqual(M.cutout({}, "false"), null, "a device without a hole")
assert.deepStrictEqual(M.cutout({ cutout: { width: 30 } }, "false"), { center: 0.5, width: 30 }, "the owner's cutout on a device without one")
assert.deepStrictEqual(M.cutout({}, "{torn"), M.CUTOUT_DEFAULT, "a torn file: the default")
assert.deepStrictEqual(M.cutoutZone(M.CUTOUT_DEFAULT, 360, 360, 808), { left: 160, right: 200 }, "upright on the 9a at scale 3")
assert.deepStrictEqual(M.cutoutZone({ center: 0.25, width: 20 }, 400, 400, 900), { left: 90, right: 110 })
assert.strictEqual(M.cutoutZone(M.CUTOUT_DEFAULT, 808, 808, 360), null, "on its side the hole is at a short edge, not in the bar")
assert.strictEqual(M.cutoutZone(null, 360, 360, 808), null)
assert.deepStrictEqual(M.cutoutZone(M.CUTOUT_DEFAULT, 360, 360, 0), { left: 160, right: 200 }, "a screen of no known size keeps the zone")
assert.strictEqual(M.cutoutZone(M.CUTOUT_DEFAULT, 0, 360, 808), null, "no width yet")
console.log("ok - status model: the camera cutout's zone")

// Fitting the bar's two sides beside the zone (widths as the strip measures
// them at Large on the 9a, rounded). An attached item (the words beside a
// glyph) carries its own gap and goes with its glyph.
const right = (o) => [
  { id: "dnd", w: o.dnd || 0 }, { id: "bluetooth", w: o.bluetooth || 0 }, { id: "cell", w: o.cell || 0 },
  { id: "cellText", w: o.cellText || 0, attach: true }, { id: "wifi", w: o.wifi || 0 },
  { id: "battery", w: o.battery || 0 }, { id: "batteryText", w: o.batteryText || 0, attach: true }]
const left = (o) => [{ id: "clock", w: o.clock || 0 }, { id: "call", w: o.call || 0 }, { id: "unread", w: o.unread || 0 }]
const owner = { bluetooth: 13, cell: 17, cellText: 28, wifi: 21, battery: 14, batteryText: 29 }
assert.strictEqual(M.rowWidth(right(owner), {}, 12), 13 + 17 + 28 + 21 + 14 + 29 + 3 * 12, "four items, three gaps")
assert.strictEqual(M.rowWidth(right(owner), { cell: true }, 12), 13 + 21 + 14 + 29 + 2 * 12, "the words go with their glyph")
const bar = (o) => M.fitBar(Object.assign({ width: 360, margin: 21, zone: { left: 160, right: 200 }, groupGap: 12,
                                            leftSpacing: 9, rightSpacing: 12 }, o))
const shown = (fit, ids) => ids.filter((id) => fit.show[id])
let f = bar({ left: left({ clock: 48, unread: 22 }), right: right(owner) })
assert.strictEqual(f.rightRoom, 139)
assert.strictEqual(f.leftRoom, 139)
assert.deepStrictEqual(shown(f, ["bluetooth", "cell", "cellText", "wifi", "battery", "batteryText"]),
  ["bluetooth", "cell", "wifi", "battery", "batteryText"], "the owner's palmtop at Large: LTE goes first")
assert.ok(f.right <= f.rightRoom && f.fits)
assert.deepStrictEqual(shown(f, ["clock", "unread"]), ["clock", "unread"])
// Wider: each step sheds the next in the order, never the battery.
// All of it is 185 px; without the words 157, then 128, 103, 76, 43 and 14.
const steps = [[185, []], [160, ["cellText"]], [130, ["cellText", "batteryText"]], [110, ["cellText", "batteryText", "bluetooth"]],
               [80, ["cellText", "batteryText", "bluetooth", "dnd"]], [50, ["cellText", "batteryText", "bluetooth", "dnd", "wifi"]],
               [20, ["cellText", "batteryText", "bluetooth", "dnd", "wifi", "cell"]]]
const all = { dnd: 15, bluetooth: 13, cell: 17, cellText: 28, wifi: 21, battery: 14, batteryText: 29 }
for (const [room, gone] of steps) {
  const r = M.fitRow(right(all), room, 12, M.RIGHT_SHED)
  assert.deepStrictEqual(M.RIGHT_SHED.filter((id) => !r.show[id]), gone, "room " + room)
  assert.strictEqual(r.show.battery, true, "the battery stays at room " + room)
}
assert.strictEqual(M.fitRow(right(all), 10, 12, M.RIGHT_SHED).fits, false, "the battery alone is wider than 10: it stays all the same")
// What isn't there is not shed: with no words, Bluetooth is the first to go.
let r = M.fitRow(right({ bluetooth: 13, cell: 17, wifi: 21, battery: 14 }), 80, 12, M.RIGHT_SHED)
assert.deepStrictEqual(["bluetooth", "cell", "wifi", "battery"].filter((id) => !r.show[id]), ["bluetooth"])
assert.strictEqual(r.show.dnd, false, "absent, so not shown")
// The left: the unread count before the call; the clock always stays.
f = bar({ left: left({ clock: 48, call: 96, unread: 22 }), right: right(owner) })
assert.deepStrictEqual(shown(f, ["clock", "call", "unread"]), ["clock"], "a 96 px call chip doesn't fit beside a 48 px clock in 139")
f = bar({ left: left({ clock: 48, call: 70, unread: 22 }), right: right(owner) })
assert.deepStrictEqual(shown(f, ["clock", "call", "unread"]), ["clock", "call"], "the count goes first")
f = bar({ left: left({ clock: 200 }), right: right(owner) })
assert.strictEqual(f.show.clock, true, "the clock stays even where it can't fit")
assert.strictEqual(f.fits, false)
// On its side there is no zone: the right row keeps room for what it never
// sheds, the left side fits in the rest, and the two never meet.
f = bar({ width: 808, zone: null, left: left({ clock: 48, call: 96, unread: 22 }), right: right(all) })
assert.strictEqual(Object.values(f.show).every(Boolean), true, "808 px wide: everything")
assert.ok(f.left + 12 + f.right <= 808 - 2 * 21)
f = bar({ width: 200, zone: null, left: left({ clock: 48, call: 96, unread: 22 }), right: right(all) })
assert.ok(f.left + 12 + f.right <= 200 - 2 * 21 || !f.fits)
assert.strictEqual(f.show.battery && f.show.clock, true)
// A zone in a margin, or off the bar, is no zone for the content.
f = bar({ zone: { left: -40, right: 0 }, left: left({ clock: 48 }), right: right(owner) })
assert.strictEqual(f.zone, null)
// Off-centre: each side gets what is left of it.
f = bar({ zone: { left: 60, right: 100 }, left: left({ clock: 48, unread: 22 }), right: right(owner) })
assert.strictEqual(f.leftRoom, 39)
assert.strictEqual(f.rightRoom, 239)
assert.deepStrictEqual(shown(f, ["clock", "unread"]), ["clock"])
console.log("ok - status model: the bar sheds, in order, what doesn't fit beside the cutout")
