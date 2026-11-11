// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.update/UpdateModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.update/UpdateModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])

test("events: kind and text; result carries its JSON", () => {
  assert.deepStrictEqual(M.parseEvent("step\tUpdate system packages"), { kind: "step", text: "Update system packages" })
  assert.deepStrictEqual(M.parseEvent("line\ta\tb"), { kind: "line", text: "a\tb" })
  assert.strictEqual(M.parseEvent("garbage"), null)
  assert.strictEqual(M.parseEvent(""), null)
  const r = M.parseEvent('result\t{"result": "ok", "needs_reboot": false}')
  assert.strictEqual(r.kind, "result")
  assert.strictEqual(r.result.result, "ok")
  assert.strictEqual(M.parseEvent("result\tnot json").result, null)
})

test("details keep the last lines, as a new array", () => {
  let lines = []
  for (let i = 0; i < M.MAX_DETAIL_LINES + 25; i++) {
    const before = lines
    lines = M.appendDetail(lines, "l" + i)
    assert.notStrictEqual(lines, before)
  }
  assert.strictEqual(lines.length, M.MAX_DETAIL_LINES)
  assert.strictEqual(lines[lines.length - 1], "l" + (M.MAX_DETAIL_LINES + 24))
})

test("overview: an Omarchy release", () => {
  const o = M.overview({ ok: true, omarchy: "4.0.4-2", omarchy_update: "omarchy 4.0.4-2 -> 4.0.5-1", update_count: 37, blockers: [] })
  assert.strictEqual(o.title, "Omarchy 4.0.5-1")
  assert.ok(o.body.includes("4.0.4-2") && o.body.includes("37 packages"))
  assert.strictEqual(o.canUpdate, true)
})

test("overview: a kernel update says whether slot B is written", () => {
  const base = { ok: true, omarchy: "4.0.4-2", omarchy_update: "", update_count: 2, blockers: [] }
  const w = M.overview(Object.assign({ kernel: { version: "7.3.0rc6.r4521.g0123456789ab-1", boot_update: "write", problem: "" } }, base))
  assert.ok(w.body.includes("7.3.0rc6.r4521") && w.body.includes("restart boots it"), w.body)
  const s = M.overview(Object.assign({ kernel: { version: "7.3.0rc6.r4521.g0123456789ab-1", boot_update: "skip", problem: "" } }, base))
  assert.ok(s.body.includes("keeps the kernel it has"), s.body)
  assert.ok(!M.overview(Object.assign({ kernel: null }, base)).body.includes("kernel"))
})

test("overview: packages only, up to date, blocked, not checked yet", () => {
  assert.strictEqual(M.overview({ ok: true, omarchy: "4.0.4-2", update_count: 1, blockers: [] }).title, "1 package update")
  const current = M.overview({ ok: true, omarchy: "4.0.4-2", update_count: 0, blockers: [] })
  assert.strictEqual(current.title, "Up to date")
  assert.strictEqual(current.canUpdate, false)
  const blocked = M.overview({ ok: false, update_count: 3, blockers: ["Battery at 12%"] })
  assert.strictEqual(blocked.canUpdate, false)
  assert.deepStrictEqual(blocked.blockers, ["Battery at 12%"])
  assert.strictEqual(M.overview(null).canUpdate, false)
})

test("battery line", () => {
  assert.strictEqual(M.batteryText({ battery: { present: true, percent: 64, charging: false } }), "64%")
  assert.strictEqual(M.batteryText({ battery: { present: true, percent: 18, charging: true } }), "18%, charging")
  assert.strictEqual(M.batteryText({ battery: { present: false } }), "No battery")
  assert.strictEqual(M.batteryText(null), "No battery")
})

test("patches line: in place, upstream, failed", () => {
  assert.strictEqual(M.patchesText({ result: "ok", applied: ["a", "b"], upstream: [] }), "Phone patches in place: 2 patches")
  assert.ok(M.patchesText({ result: "ok", applied: ["a"], upstream: ["0000"] }).includes("1 now part of Omarchy"))
  const failed = M.patchesText({ result: "failed", failed: "0003-x.patch", log: "/var/log/omamobile/omarchy-patches.log" })
  assert.ok(failed.includes("PIN pad") && failed.includes("0003-x.patch") && failed.includes("/var/log/omamobile/omarchy-patches.log"))
  assert.ok(M.patchesText(null).includes("not applied yet"))
})

test("result: updated, restart, patches failed, wrong PIN, refused, stopped", () => {
  const ok = M.resultView({ result: "ok", needs_reboot: false, omarchy_before: "4.0.4-2", omarchy_after: "4.0.5-1", log: "/x/update.log" })
  assert.strictEqual(ok.title, "Updated")
  assert.ok(ok.body.includes("4.0.4-2 to 4.0.5-1"))
  assert.strictEqual(ok.restart, false)
  assert.strictEqual(ok.log, "/x/update.log")
  const reboot = M.resultView({ result: "ok", needs_reboot: true, reasons: ["Hyprland was updated"] })
  assert.strictEqual(reboot.title, "Updated: restart to finish")
  assert.strictEqual(reboot.restart, true)
  assert.ok(reboot.body.includes("Hyprland was updated"))
  const patches = M.resultView({ result: "patches-failed", message: "Updated, but ...", patches: { result: "failed" } })
  assert.strictEqual(patches.tone, "warn")
  assert.ok(patches.patches.includes("PIN pad"))
  assert.strictEqual(M.resultView({ result: "auth-failed" }).title, "Wrong PIN or password")
  assert.strictEqual(M.resultView({ result: "refused", message: "Battery at 12%" }).body, "Battery at 12%")
  const stopped = M.resultView({ result: "failed", message: "The update stopped (exit 1)", needs_reboot: true })
  assert.strictEqual(stopped.tone, "bad")
  assert.strictEqual(stopped.restart, false)
  const held = M.resultView({ result: "ok", held: [["1790000001.sh", "limine", "Rebuild the Limine entries"]] })
  assert.deepStrictEqual(held.held, ["1790000001.sh (Rebuild the Limine entries)"])
})

test("start's exit codes", () => {
  assert.strictEqual(M.startOutcome(0), "started")
  assert.strictEqual(M.startOutcome(3), "auth-failed")
  assert.strictEqual(M.startOutcome(4), "running")
  assert.strictEqual(M.startOutcome(5), "refused")
  assert.strictEqual(M.startOutcome(1), "error")
})

test("commands: omamobile-update's, the PIN never in argv", () => {
  assert.deepStrictEqual(M.START_ARGV, ["omamobile-update", "start"])
  assert.deepStrictEqual(M.CHECK_ARGV, ["omamobile-update", "check", "--json"])
  assert.deepStrictEqual(M.REBOOT_ARGV, ["omamobile-reboot"])
})

let failed = 0
for (const [name, fn] of tests) {
  try {
    fn()
    console.log("ok - update model: " + name)
  } catch (e) {
    failed++
    console.log("not ok - update model: " + name + "\n  " + e.message)
  }
}
process.exit(failed ? 1 : 0)
