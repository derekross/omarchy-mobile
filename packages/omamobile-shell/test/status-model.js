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
