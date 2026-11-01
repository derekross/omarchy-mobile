// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.keyboard/KeyboardModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.keyboard/KeyboardModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])

// What Keyboard.qml does, step by step, with squeekboard's answers.
function plugin() {
  const p = { shownByHand: false, oskOpen: false, home: false, calls: [] }
  p.check = () => { if (M.shouldHide(p.shownByHand, p.oskOpen, p.home)) p.setVisible(false) }
  p.setVisible = (v) => { p.shownByHand = v; p.calls.push(v) }
  p.report = (v) => { p.oskOpen = v; p.shownByHand = M.shownByHandAfter(p.shownByHand, v); p.check() }
  p.goHome = (h) => { p.home = h; p.check() }
  return p
}

test("the home screen is a focused workspace with no windows", () => {
  assert.strictEqual(M.homeOnScreen({ toplevels: { values: [] } }), true)
  assert.strictEqual(M.homeOnScreen({ toplevels: { values: [{}] } }), false)
  assert.strictEqual(M.homeOnScreen(null), false)
  assert.strictEqual(M.homeOnScreen({}), false)
})

test("a keyboard shown by hand over an app is put away when going home", () => {
  const p = plugin()
  p.setVisible(true)          // the pill's double tap
  p.report(true)              // squeekboard: visible
  p.goHome(true)
  assert.deepStrictEqual(p.calls, [true, false])
})

test("the order doesn't matter: shown by hand just after home came up", () => {
  const p = plugin()
  p.goHome(true)
  p.setVisible(true)          // a late second double tap of the swipe
  p.report(true)
  assert.deepStrictEqual(p.calls, [true, false])
})

test("a keyboard squeekboard showed for a text field is left to squeekboard", () => {
  const p = plugin()
  p.report(true)              // a field took focus
  p.goHome(true)
  assert.deepStrictEqual(p.calls, [])
})

test("hiding ends 'shown by hand': a later automatic keyboard on home stays", () => {
  const p = plugin()
  p.setVisible(true); p.report(true)
  p.setVisible(false); p.report(false)   // the hide key
  p.goHome(true)
  p.report(true)              // the drawer's search field
  assert.deepStrictEqual(p.calls, [true, false])
})

test("the keyboard going away on its own also ends it", () => {
  const p = plugin()
  p.setVisible(true); p.report(true)
  p.report(false)             // squeekboard hid it (an input method change)
  p.goHome(true)
  p.report(true)
  assert.deepStrictEqual(p.calls, [true])
})

test("staying in an app keeps a keyboard shown by hand", () => {
  const p = plugin()
  p.setVisible(true); p.report(true)
  p.goHome(false)
  assert.deepStrictEqual(p.calls, [true])
})

test("the double tap: shows when down, hides when up", () => {
  const M = require(require("path").join(__dirname, "../plugins/omamobile.keyboard/KeyboardModel.js"))
  assert.strictEqual(M.toggleTarget(false, null, 1e9), true)
  assert.strictEqual(M.toggleTarget(true, null, 1e9), false, "a second double tap hides it")
  assert.strictEqual(M.toggleTarget(false, true, 300), false, "a second double tap before the show is reported still hides")
  assert.strictEqual(M.toggleTarget(true, false, 300), true, "and one before the hide is reported shows")
  assert.strictEqual(M.toggleTarget(true, true, M.TOGGLE_SETTLE_MS + 1), false, "later, the reported state decides")
  assert.strictEqual(M.toggleTarget(false, true, M.TOGGLE_SETTLE_MS + 1), true, "a keyboard that went away on its own shows again")
})

let failed = 0
for (const [name, fn] of tests) {
  try { fn(); console.log("ok - " + name) } catch (e) { failed++; console.log("not ok - " + name + "\n  " + e.message) }
}
process.exit(failed ? 1 : 0)
