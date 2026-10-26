// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.back/BackModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.back/BackModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])

test("Escape goes through Hyprland's Lua dispatcher, down then up, in one process", () => {
  assert.strictEqual(M.ESCAPE_DOWN, 'hl.dsp.send_key_state({ mods = "", key = "Escape", state = "down" })')
  assert.strictEqual(M.ESCAPE_UP, 'hl.dsp.send_key_state({ mods = "", key = "Escape", state = "up" })')
  const [sh, c, script, name, down, up] = M.ESCAPE_ARGV
  assert.deepStrictEqual([sh, c, name, down, up], ["sh", "-c", "sh", M.ESCAPE_DOWN, M.ESCAPE_UP])
  // The dispatches are positional arguments, never spliced into the script.
  assert.ok(!script.includes("Escape"))
  assert.ok(script.indexOf('hyprctl dispatch "$1"') < script.indexOf("sleep 0.05"))
  assert.ok(script.indexOf("sleep 0.05") < script.indexOf('hyprctl dispatch "$2"'))
})

test("inward travel from each edge", () => {
  assert.strictEqual(M.inwardFor(false, 30), 30)
  assert.strictEqual(M.inwardFor(true, -30), 30)
  assert.strictEqual(M.inwardFor(true, 30), -30)
  assert.strictEqual(M.inwardFor(false, undefined), 0)
})

test("progress fills from the edge to the threshold", () => {
  assert.strictEqual(M.progress(0, 56), 0)
  assert.strictEqual(M.progress(-20, 56), 0)
  assert.strictEqual(M.progress(28, 56), 0.5)
  assert.strictEqual(M.progress(200, 56), 1)
  assert.strictEqual(M.progress(28), 28 / M.THRESHOLD)
})

test("a swipe in past the threshold goes back; short, outward or mostly vertical ones don't", () => {
  assert.ok(M.fires(56, 0, 56))
  assert.ok(M.fires(80, 60, 56))
  assert.ok(!M.fires(55, 0, 56))
  assert.ok(!M.fires(-80, 0, 56))
  assert.ok(!M.fires(60, 70, 56))
  assert.ok(!M.fires(60, -70, 56))
  assert.ok(M.fires(M.THRESHOLD, 0))
})

let failed = 0
for (const [name, fn] of tests) {
  try { fn(); console.log("ok - back model: " + name) } catch (e) { failed++; console.log("not ok - back model: " + name + "\n  " + (e.stack || e)) }
}
process.exit(failed ? 1 : 0)
