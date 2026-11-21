// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.fingerprint/SensorModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.fingerprint/SensorModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-6, a + " != " + b)

const line = '{"op":"auth","finger":false,"x":717,"y":2360,"r":121,"w":1440,"h":3120}\n'

test("parses the bridge's state line", () => {
  const s = M.parse(line)
  assert.deepStrictEqual(s, { op: "auth", finger: false, x: 717, y: 2360, r: 121, w: 1440, h: 3120,
                             seq: 0, acquired: 0, remaining: -1, error: 0, last: "none", contact: null,
                             illuminate: false })
  assert.ok(M.active(s))
  assert.ok(M.active(M.parse(line.replace("auth", "enroll"))))
  assert.ok(!M.active(M.parse(line.replace("auth", "idle"))))
  assert.strictEqual(M.parse(line.replace("false", "true")).finger, true)
})

test("a panel without LHBM asks the shell for the light", () => {
  const lit = M.parse(line.replace("}", ',"illuminate":true}'))
  assert.strictEqual(lit.illuminate, true)
  assert.strictEqual(M.parse(line.replace("}", ',"illuminate":"yes"}')).illuminate, false)
})

test("rejects anything else", () => {
  for (const bad of ["", "{", "null", "[]", '{"op":"auth"}', line.replace("auth", "verify"),
                     line.replace('"r":121', '"r":0'), line.replace('"x":717', '"x":"717"')])
    assert.strictEqual(M.parse(bad), null, bad)
  assert.ok(!M.active(null))
})

test("portrait at scale 3: panel pixels / 3", () => {
  const p = M.place(M.parse(line), 0, 480, 1040)
  near(p.x, 239); near(p.y, 2360 / 3); near(p.r, 121 / 3)
})

test("other scales follow the screen's size", () => {
  const p = M.place(M.parse(line), 0, 720, 1560)
  near(p.x, 358.5); near(p.y, 1180); near(p.r, 60.5)
})

test("rotations, as omamobile-autorotate names them", () => {
  const s = M.parse(line)
  let p = M.place(s, 1, 1040, 480)          // left side up: sensor towards the left
  near(p.x, (3120 - 2360) / 3); near(p.y, 239)
  p = M.place(s, 2, 480, 1040)              // upside down: near the top
  near(p.x, (1440 - 717) / 3); near(p.y, (3120 - 2360) / 3)
  p = M.place(s, 3, 1040, 480)              // right side up: towards the right
  near(p.x, 2360 / 3); near(p.y, (1440 - 717) / 3)
})

test("cannot place: flipped, wrong shape, no screen", () => {
  const s = M.parse(line)
  assert.strictEqual(M.place(s, 5, 480, 1040), null)
  assert.strictEqual(M.place(s, 0, 1040, 480), null)   // transform and size disagree
  assert.strictEqual(M.place(s, 0, 0, 0), null)
  assert.strictEqual(M.place(null, 0, 480, 1040), null)
})

test("parses the enrollment detail, with defaults for an older bridge", () => {
  const s = M.parse('{"op":"enroll","finger":true,"x":717,"y":2360,"r":121,"w":1440,"h":3120,"seq":7,"acquired":11,"remaining":24,"error":0,"last":"none"}')
  assert.strictEqual(s.seq, 7); assert.strictEqual(s.acquired, 11); assert.strictEqual(s.remaining, 24)
  assert.strictEqual(s.finger, true); assert.strictEqual(s.last, "none")
  const old = M.parse(line)
  assert.strictEqual(old.seq, 0); assert.strictEqual(old.remaining, -1); assert.strictEqual(old.last, "none")
  assert.strictEqual(M.parse(line.replace("}", ',"last":"bogus"}')).last, "none")
  assert.strictEqual(M.parse(line.replace("}", ',"contact":true}')).contact, true)
  assert.strictEqual(M.parse(line.replace("}", ',"contact":false}')).contact, false)
})

test("enrollment progress counts the first touch", () => {
  near(M.enrollProgress(28, 28, -1), 2 / 30)       // step assumed 2 until a second count
  near(M.enrollProgress(26, 28, 26), 4 / 30)
  near(M.enrollProgress(0, 28, 26), 1)
  near(M.enrollProgress(18, 19, 18), 2 / 20)        // a sensor stepping by 1
  assert.strictEqual(M.enrollProgress(-1, -1, -1), 0)
  assert.strictEqual(M.enrollStage(0.49), "center")
  assert.strictEqual(M.enrollStage(0.5), "edges")
  assert.strictEqual(M.enrollText(false, 0).title, "Touch the sensor")
  assert.strictEqual(M.enrollText(true, 0.2).title, "Lift, then touch again")
  assert.strictEqual(M.enrollText(true, 0.6).title, "Now place the edges of your finger")
})

test("hints for the HAL's acquired codes and fprintd's retries", () => {
  assert.strictEqual(M.acquiredHint(1), "")          // GOOD: the stage's own words
  assert.strictEqual(M.acquiredHint(2), "Press your whole finger on the sensor")
  assert.strictEqual(M.acquiredHint(3), "Press your whole finger on the sensor")
  assert.ok(/Clean/.test(M.acquiredHint(4)))
  assert.strictEqual(M.acquiredHint(8), "Keep your finger still")
  assert.strictEqual(M.acquiredHint(11), "Move your finger slightly each time")
  for (const c of [5, 6, 9, 10, 13]) assert.ok(M.acquiredHint(c).length > 0, c)
  assert.strictEqual(M.acquiredHint(0), "")
  assert.ok(M.retryHint("enroll-finger-not-centered").length > 0)
  assert.strictEqual(M.retryHint("enroll-stage-passed"), "")
})

test("failures prefer the HAL's reason from this enrollment", () => {
  const err = { seq: 9, last: "error", error: 3 }
  assert.strictEqual(M.failureText("enroll-failed", "", err, 5), "Time's up. Try again")
  assert.strictEqual(M.failureText("enroll-failed", "", err, 9), M.errorText(0))   // an older error
  assert.strictEqual(M.failureText("enroll-duplicate", "", null, 0), "This fingerprint is already added")
  assert.ok(/busy/.test(M.failureText("", "busy", null, 0)))
  assert.ok(/permission/.test(M.failureText("", "denied", null, 0)))
  assert.strictEqual(M.errorText(5), "Fingerprint setup was canceled")
  assert.strictEqual(M.fingerLabel("right-index-finger"), "right index finger")
  assert.strictEqual(M.fingerLabel("left-thumb"), "left thumb")
})

let failed = 0
for (const [name, fn] of tests) {
  try {
    fn()
    console.log("ok - sensor model: " + name)
  } catch (error) {
    failed++
    console.error("not ok - sensor model: " + name + "\n  " + String(error && error.message || error).split("\n").join("\n  "))
  }
}
process.exit(failed ? 1 : 0)
