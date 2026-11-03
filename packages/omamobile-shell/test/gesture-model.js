// SPDX-License-Identifier: MIT
// Node tests for the home screen's and the drawer's gesture rules
// (HomeModel.js and LauncherModel.js). Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const H = require(path.join(__dirname, "../plugins/omamobile.home/HomeModel.js"))
const L = require(path.join(__dirname, "../plugins/omamobile.launcher/LauncherModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])

test("a slow release settles on the nearer page", () => {
  assert.strictEqual(H.pageAfterSwipe(0, 480, 3, 0), 0)
  assert.strictEqual(H.pageAfterSwipe(200, 480, 3, 0), 0)
  assert.strictEqual(H.pageAfterSwipe(260, 480, 3, 0), 1)
  assert.strictEqual(H.pageAfterSwipe(480 + 230, 480, 3, 100), 1)
  assert.strictEqual(H.pageAfterSwipe(480 - 260, 480, 3, -100), 0)
})

test("a flick turns the page its way, even a short one", () => {
  assert.strictEqual(H.pageAfterSwipe(40, 480, 3, 600), 1, "40 px forward")
  assert.strictEqual(H.pageAfterSwipe(480 - 40, 480, 3, -600), 0, "40 px back")
  assert.strictEqual(H.pageAfterSwipe(480 + 30, 480, 3, H.PAGE_FLING), 2)
  assert.strictEqual(H.pageAfterSwipe(40, 480, 3, H.PAGE_FLING - 1), 0, "just under the fling speed")
})

test("a flick back returns to the page it left; jitter turns nothing", () => {
  assert.strictEqual(H.pageAfterSwipe(300, 480, 3, -800), 0)
  assert.strictEqual(H.pageAfterSwipe(5, 480, 3, 900), 0, "under PAGE_FLING_MIN")
  assert.strictEqual(H.pageAfterSwipe(480 + 5, 480, 3, -900), 1)
})

test("pages stay within the first and the last", () => {
  assert.strictEqual(H.pageAfterSwipe(-30, 480, 3, -900), 0)
  assert.strictEqual(H.pageAfterSwipe(960 + 30, 480, 3, 900), 2)
  assert.strictEqual(H.pageAfterSwipe(10, 480, 1, 900), 0)
  assert.strictEqual(H.pageAfterSwipe(100, 0, 3, 900), 0, "no width yet")
})

for (const [M, span, longest, name] of [[H, 480, 250, "page"], [L, 900, 260, "drawer"]]) {
  test(name + " settles are short, ease out, and keep a flick's speed", () => {
    assert.strictEqual(M.settleMs(0, span, 0), 0)
    assert.strictEqual(M.settleMs(span, span, 0), longest, "the whole way, at rest")
    const half = M.settleMs(span / 2, span, 0)
    assert.ok(half > 160 && half < 210, "half the way: " + half)
    assert.ok(M.settleMs(span / 2, span, span * 10) < half, "a fast flick carries on faster")
    assert.strictEqual(M.settleMs(10, span, 100000), 120, "never under 120 ms")
    assert.strictEqual(M.settleMs(-span, span, 0), longest, "either way")
  })
}

test("finger speed counts the last 100 ms only", () => {
  let s = []
  for (let t = 0; t <= 80; t += 16) s = L.addSample(s, t, t * 2)
  assert.ok(Math.abs(L.speedOf(s, 80) - 2000) < 1, "2 px/ms: " + L.speedOf(s, 80))
  assert.strictEqual(L.speedOf(s, 400), 0, "a finger held still before letting go")
  assert.strictEqual(L.speedOf([{ t: 0, pos: 0 }], 0), 0, "one sample")
  assert.strictEqual(L.speedOf([{ t: 0, pos: 0 }, { t: 2, pos: 50 }], 2), 0, "too close together to tell")
  // Old samples are dropped as new ones come.
  for (let t = 100; t <= 1000; t += 16) s = L.addSample(s, t, 0)
  assert.ok(s.length < 20, "kept " + s.length)
  // The home screen's copy agrees.
  assert.strictEqual(H.speedOf(s, 1000), L.speedOf(s, 1000))
  assert.deepStrictEqual(H.addSample([], 5, 7), L.addSample([], 5, 7))
})

test("the drawer opens on a flick up or a quarter of the way", () => {
  assert.ok(L.drawerEndsOpen(0.05, -L.DRAWER_FLING, false), "a short flick up")
  assert.ok(!L.drawerEndsOpen(0.9, L.DRAWER_FLING, false), "a flick down wins")
  assert.ok(L.drawerEndsOpen(0.25, 0, false))
  assert.ok(!L.drawerEndsOpen(0.2, 0, false))
  assert.ok(!L.drawerEndsOpen(0.24, -100, false), "slow, short of a quarter")
})

test("the drawer closes on a flick down or a tenth of the way down", () => {
  assert.ok(!L.drawerEndsOpen(0.97, 800, true), "a short flick down")
  assert.ok(L.drawerEndsOpen(0.3, -800, true), "a flick back up keeps it")
  assert.ok(L.drawerEndsOpen(0.95, 0, true), "pulled 5 %, slowly")
  assert.ok(!L.drawerEndsOpen(0.85, 0, true), "pulled 15 %, slowly")
})

test("the swipe up is the home screen's only with nothing over it", () => {
  assert.ok(H.drawerSwipeAllowed(false, false, ""))
  assert.ok(!H.drawerSwipeAllowed(true, false, ""), "an app")
  assert.ok(!H.drawerSwipeAllowed(false, true, ""), "editing")
  assert.ok(!H.drawerSwipeAllowed(false, false, "widgets"), "a sheet")
})

test("without the drawer in reach, a long or quick swipe still opens it", () => {
  assert.ok(H.drawerFallbackOpens(80, 0))
  assert.ok(!H.drawerFallbackOpens(79, 0))
  assert.ok(H.drawerFallbackOpens(20, -400))
  assert.ok(!H.drawerFallbackOpens(200, 400), "ended going down")
})

let failed = 0
for (const [name, fn] of tests) {
  try { fn(); console.log("ok - gesture model: " + name) } catch (e) { failed++; console.log("not ok - gesture model: " + name + "\n  " + (e.stack || e)) }
}
process.exit(failed ? 1 : 0)
