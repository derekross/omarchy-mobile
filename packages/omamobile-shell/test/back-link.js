// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.back/BackLink.js, the list Back asks
// before it sends Escape: the on-screen keyboard first, then the topmost
// registered shell surface, then (back() === "") Escape. Run by test/all.
// The file is a QML `.pragma library`; that line is dropped to load it here.
"use strict"
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const file = path.join(__dirname, "../plugins/omamobile.back/BackLink.js")
const source = fs.readFileSync(file, "utf8")
assert.ok(/^\.pragma library$/m.test(source), "one instance per engine")
function load() {
  const box = {}
  vm.createContext(box)
  vm.runInContext(source.replace(/^\.pragma library$/m, ""), box, { filename: file })
  return box
}

const tests = []
const test = (name, fn) => tests.push([name, fn])

// A surface: registers under `name`, counts its Backs, and closes (takes
// itself off the list) when it gets one, as a real sheet does.
function surface(L, name, tier, log) {
  const s = { name, backs: 0, open: false }
  s.show = () => { s.open = true; L.register(s, () => { s.backs++; log.push(name); s.hide() }, tier, name) }
  s.hide = () => { s.open = false; L.unregister(s) }
  return s
}

test("nothing registered: Back is Escape", () => {
  const L = load()
  assert.strictEqual(L.back(), "")
  assert.deepStrictEqual(Array.from(L.names()), [])
})

test("the topmost surface closes, one per Back, and then Escape", () => {
  const L = load(), log = []
  const a = surface(L, "permission sheet", "surface", log), b = surface(L, "voice settings", "surface", log)
  a.show(); b.show()
  assert.deepStrictEqual(Array.from(L.names()), ["voice settings", "permission sheet"], "opened last, asked first")
  assert.strictEqual(L.back(), "voice settings")
  assert.deepStrictEqual(log, ["voice settings"], "one Back, one surface")
  assert.strictEqual(L.back(), "permission sheet")
  assert.strictEqual(L.back(), "", "both closed: the app gets Escape")
  assert.deepStrictEqual([a.backs, b.backs], [1, 1])
})

test("a surface that closed never swallows a later Back", () => {
  const L = load(), log = []
  const a = surface(L, "fingerprint setup", "surface", log)
  a.show(); a.hide()
  assert.strictEqual(L.back(), "")
  assert.strictEqual(a.backs, 0)
  // Open, closed by its own button, open again and closed by Back: still one each time.
  a.show(); a.hide(); a.show()
  assert.strictEqual(L.back(), "fingerprint setup")
  assert.strictEqual(L.back(), "")
  assert.strictEqual(a.backs, 1)
  assert.strictEqual(L.unregister(a), false, "already off the list")
})

test("the keyboard goes first, whatever opened when", () => {
  const L = load(), log = []
  const keys = surface(L, "keyboard", "keyboard", log), sheet = surface(L, "permission sheet", "surface", log)
  keys.show(); sheet.show()
  assert.deepStrictEqual(Array.from(L.names()), ["keyboard", "permission sheet"])
  assert.strictEqual(L.back(), "keyboard")
  assert.strictEqual(sheet.backs, 0, "the keyboard's Back closes nothing else")
  assert.strictEqual(L.back(), "permission sheet", "the next Back does what it would have done")
  assert.strictEqual(L.back(), "")
  // The keyboard coming up over an open sheet is still first.
  sheet.show(); keys.show()
  assert.strictEqual(L.back(), "keyboard")
  assert.strictEqual(L.back(), "permission sheet")
})

test("the keyboard up over an app: hidden, and nothing is sent", () => {
  const L = load(), log = []
  const keys = surface(L, "keyboard", "keyboard", log)
  keys.show()
  assert.strictEqual(L.back(), "keyboard", "no Escape this time")
  assert.strictEqual(L.back(), "", "then Escape, for the app")
})

test("the language sheet sits on the keyboard and goes before it", () => {
  const L = load(), log = []
  const keys = surface(L, "keyboard", "keyboard", log), lang = surface(L, "keyboard languages", "on-keyboard", log)
  lang.show(); keys.show()
  assert.strictEqual(L.back(), "keyboard languages")
  assert.strictEqual(L.back(), "keyboard")
  assert.strictEqual(L.back(), "")
})

test("registering again keeps the place and takes the new handler", () => {
  const L = load()
  const a = {}, b = {}
  let hit = ""
  L.register(a, () => { hit = "old" }, "surface", "a")
  L.register(b, () => { hit = "b" }, "surface", "b")
  L.register(a, () => { hit = "new" }, "surface", "a")
  assert.deepStrictEqual(Array.from(L.names()), ["b", "a"], "a did not jump over b")
  L.unregister(b)
  L.back()
  assert.strictEqual(hit, "new")
})

test("a handler that says false, or throws, passes the Back on", () => {
  const L = load()
  const a = {}, b = {}, c = {}
  let reached = 0
  L.register(a, () => { reached++ }, "surface", "a")
  L.register(b, () => false, "surface", "b")
  L.register(c, () => { throw new Error("broken") }, "surface", "c")
  assert.strictEqual(L.back(), "a")
  assert.strictEqual(reached, 1)
  L.unregister(a)
  assert.strictEqual(L.back(), "", "nobody used it: Escape")
})

test("a handler that closes another surface too: that one isn't asked", () => {
  const L = load()
  const a = {}, b = {}
  let asked = 0
  L.register(a, () => { asked++ }, "surface", "a")
  L.register(b, () => { L.unregister(a); return false }, "surface", "b")
  assert.strictEqual(L.back(), "")
  assert.strictEqual(asked, 0)
})

test("no owner or no handler is refused; an unknown tier is a surface", () => {
  const L = load()
  assert.strictEqual(L.register(null, () => {}, "surface", "x"), false)
  assert.strictEqual(L.register({}, "close", "surface", "x"), false)
  const keys = {}, odd = {}
  L.register(odd, () => {}, "sideways", "odd")
  L.register(keys, () => {}, "keyboard", "keyboard")
  assert.deepStrictEqual(Array.from(L.names()), ["keyboard", "odd"])
  L.clear()
  assert.deepStrictEqual(Array.from(L.names()), [])
})

let failed = 0
for (const [name, fn] of tests) {
  try { fn(); console.log("ok - back link: " + name) } catch (e) { failed++; console.log("not ok - back link: " + name + "\n  " + (e.stack || e)) }
}
process.exit(failed ? 1 : 0)
