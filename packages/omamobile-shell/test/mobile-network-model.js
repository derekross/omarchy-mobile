// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.mobilenetwork/MobileNetworkModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.mobilenetwork/MobileNetworkModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])

const ready = (over) => Object.assign({
  installed: true, running: true, stage: "running", carrier: "Example", registration: "home", tech: "LTE",
  signal: -1, sim: { state: "ready", pin_lock: "off" }, data: { enabled: true, up: true, available: true },
  roaming: { now: false, allowed: true }, apn: { in_use: "internet.example", source: "carrier-database", configured: "auto",
         attach_in_use: "internet.example", attach_source: "same", attach_configured: "auto" }
}, over || {})

test("no modem stack: the page says so and nothing else", () => {
  assert.strictEqual(M.view({ installed: false }).state, "none")
  assert.strictEqual(M.view({ installed: false }).title, "No modem")
  assert.strictEqual(M.view(null).state, "loading")
  assert.strictEqual(M.view({ installed: true, running: false }).state, "off")
})

test("registered: carrier, LTE, data on, APN from the SIM", () => {
  const v = M.view(ready())
  assert.strictEqual(v.title, "Example")
  assert.strictEqual(v.body, "Connected · LTE")
  assert.strictEqual(v.dataText, "On")
  assert.strictEqual(v.apnSource, "Chosen from your SIM")
  assert.strictEqual(v.apnConfigured, "")
  assert.strictEqual(v.signal, "Not reported yet")
  assert.strictEqual(v.pinText, "Off")
})

test("no APN for the SIM: data unavailable, pointed at the field", () => {
  const v = M.view(ready({ data: { enabled: false, up: false, available: false }, apn: { in_use: "", source: "none", configured: "auto" } }))
  assert.strictEqual(v.dataAvailable, false)
  assert.ok(v.dataText.indexOf("Type your carrier's APN") >= 0)
  assert.strictEqual(v.apnSource, "None found for this SIM")
})

test("SIM states, roaming and signal", () => {
  assert.strictEqual(M.view(ready({ registration: "searching", sim: { state: "absent" } })).title, "No SIM card")
  assert.ok(M.view(ready({ sim: { state: "ready", pin_lock: "on" } })).pinText.indexOf("another phone") >= 0)
  const r = M.view(ready({ registration: "roaming", roaming: { now: true, allowed: false } }))
  assert.strictEqual(r.roamingText, "Roaming now: mobile data paused")
  assert.strictEqual(r.roamingAllowed, false)
  assert.strictEqual(M.view(ready({ signal: 80 })).signal, "80%")
  assert.strictEqual(M.view(ready({ signal: 80 })).signalBars, 4)
  assert.strictEqual(M.view(ready({ registration: "searching" })).signal, "No signal")
})

test("APN field: auto, plain APNs, nothing else", () => {
  assert.strictEqual(M.apnValue(""), "auto")
  assert.strictEqual(M.apnValue(" Auto "), "auto")
  assert.strictEqual(M.apnValue("internet.example"), "internet.example")
  assert.strictEqual(M.apnValue("bad apn"), null)
  assert.strictEqual(M.apnValue("x\n[control]"), null)
  assert.strictEqual(M.apnValue("a".repeat(100)), null)
  assert.deepStrictEqual(M.apnArgv("auto"), ["omamobile-mobile-network", "apn", "auto"])
  assert.deepStrictEqual(M.dataArgv(true), ["omamobile-mobile-network", "data", "on"])
  assert.deepStrictEqual(M.roamingArgv(false), ["omamobile-mobile-network", "roaming", "off"])
  assert.ok(M.apnSavedText("auto").indexOf("restart") >= 0)
  assert.ok(M.apnSavedText("ims", true).indexOf("attach APN") >= 0)
  // attach_apn = none: no attach APN is sent (Verizon's network).
  assert.equal(M.attachText({ in_use: "VZWINTERNET", source: "override", attach_in_use: "none", attach_source: "override" }),
               "Not sent: the carrier profile's own  \u00b7  Chosen from your SIM")
  assert.equal(M.attachText({ in_use: "a.example", attach_in_use: "ims.example", attach_source: "manual" }),
               "ims.example  \u00b7  Typed in settings")
  assert.deepStrictEqual(M.attachArgv("ims"), ["omamobile-mobile-network", "attach-apn", "ims"])
})

test("attach APN: same as internet, or the carrier's", () => {
  assert.strictEqual(M.view(ready()).attachText, "Same as the internet APN")
  const v = M.view(ready({ apn: { in_use: "vzwinternet", source: "override", configured: "auto",
                                  attach_in_use: "vzwims", attach_source: "override", attach_configured: "auto" } }))
  assert.strictEqual(v.attachText, "vzwims  ·  Chosen from your SIM")
  assert.strictEqual(v.attachConfigured, "")
  assert.strictEqual(M.view(ready({ apn: { attach_configured: "ims", attach_in_use: "ims", attach_source: "manual" } })).attachConfigured, "ims")
})

let failed = 0
for (const [name, fn] of tests) {
  try { fn(); console.log("ok - " + name) } catch (e) { failed++; console.log("not ok - " + name + "\n  " + e.message) }
}
process.exit(failed ? 1 : 0)
