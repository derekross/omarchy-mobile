// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.onboarding/OnboardingModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.onboarding/OnboardingModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])

test("status: every field present, from the script's JSON or nothing", () => {
  const s = M.parseStatus('{"name": "Ada", "email": "ada@example.com", "identity": true, "pin": {"set": true, "type": "password"}, "agent": "claude"}')
  assert.deepStrictEqual(s, { name: "Ada", email: "ada@example.com", identity: true, pin: { set: true, type: "password" }, agent: "claude" })
  assert.deepStrictEqual(M.parseStatus(""), { name: "", email: "", identity: false, pin: { set: false, type: "pin" }, agent: "" })
  assert.deepStrictEqual(M.parseStatus("{bad").pin, { set: false, type: "pin" })
  assert.strictEqual(M.parseStatus('{"pin": {"set": "yes", "type": "x"}}').pin.set, false)
})

test("the first run asks what the prompts ask, in their order", () => {
  const fresh = M.parseStatus("")
  assert.strictEqual(M.firstPage("onboarding"), "identity")
  assert.strictEqual(M.nextPage("onboarding", "identity", fresh), "pin-choice")
  assert.strictEqual(M.nextPage("onboarding", "pin-choice", fresh), "pin-entry")
  assert.strictEqual(M.nextPage("onboarding", "pin-entry", fresh), "done")
  // With a PIN already: the note the terminal flow prints, then the agent.
  const has = M.parseStatus('{"pin": {"set": true, "type": "pin"}}')
  assert.strictEqual(M.nextPage("onboarding", "identity", has), "credential-exists")
  assert.strictEqual(M.nextPage("onboarding", "credential-exists", has), "done")
  // System > PIN: the choice, the entry, done.
  assert.strictEqual(M.firstPage("pin"), "pin-choice")
  assert.strictEqual(M.nextPage("pin", "pin-choice", has), "pin-entry")
  assert.strictEqual(M.nextPage("pin", "pin-entry", has), "done")
})

test("the choice lists the current way first, as gum choose did", () => {
  assert.deepStrictEqual(M.typeChoices("pin").map((c) => c.id), ["pin", "password"])
  assert.deepStrictEqual(M.typeChoices("password").map((c) => c.id), ["password", "pin"])
  assert.ok(M.CHOICES.pin.detail.includes("number pad"))
})

test("the entry asks for the current one only when there is one, then the new one twice", () => {
  assert.deepStrictEqual(M.entrySteps(false), ["new", "retype"])
  assert.deepStrictEqual(M.entrySteps(true), ["current", "new", "retype"])
  assert.strictEqual(M.stepText("current", "pin").title, "Enter your current PIN")
  assert.strictEqual(M.stepText("new", "password").title, "Choose a password")
  assert.ok(M.stepText("new", "pin").hint.includes("digits"))
  assert.strictEqual(M.stepText("retype", "pin").title, "Enter it again")
})

test("the scripts' argv: the secret never in it", () => {
  assert.deepStrictEqual(M.STATUS_ARGV, ["omamobile-onboarding", "--status", "--json"])
  assert.deepStrictEqual(M.INVITE_ARGV, ["omamobile-onboarding", "--invite-agent"])
  assert.deepStrictEqual(M.identityArgv(" Ada ", "ada@example.com "), ["omamobile-onboarding", "--identity", "Ada", "ada@example.com"])
  assert.deepStrictEqual(M.applyArgv("password"), ["omamobile-set-pin", "--apply", "password"])
  assert.deepStrictEqual(M.applyArgv("anything"), ["omamobile-set-pin", "--apply", "pin"])
})

test("what --apply's exit codes mean, and where the entry goes back to", () => {
  assert.deepStrictEqual(M.applyOutcome(0, ""), { result: "set", reason: "" })
  assert.deepStrictEqual(M.applyOutcome(3, ""), { result: "wrong-current", reason: "" })
  assert.deepStrictEqual(M.applyOutcome(5, "it is too short\n"), { result: "refused", reason: "it is too short" })
  assert.strictEqual(M.applyOutcome(5, "").reason, "The new one was refused")
  assert.strictEqual(M.applyOutcome(1, "").result, "error")
  assert.deepStrictEqual(M.failureText(M.applyOutcome(3, ""), "pin"), { step: "current", text: "Wrong PIN. Try again." })
  assert.deepStrictEqual(M.failureText(M.applyOutcome(5, "it is too short"), "password"), { step: "new", text: "it is too short. Choose another." })
  assert.strictEqual(M.failureText(M.applyOutcome(1, ""), "pin").step, "new")
})

test("done: what was set, and the agent invitation on the first run", () => {
  assert.deepStrictEqual(M.doneText("pin", "pin", true, ""), { title: "PIN set.", body: "Your phone now locks after it starts." })
  assert.deepStrictEqual(M.doneText("pin", "password", true, "claude"), { title: "Password set.", body: "Your phone now locks after it starts." })
  const first = M.doneText("onboarding", "pin", true, "")
  assert.ok(first.body.includes("locks after it starts") && first.body.includes("default agent"))
  assert.deepStrictEqual(M.doneText("onboarding", "pin", false, "claude"), { title: "All set.", body: "" })
})

let failed = 0
for (const [name, fn] of tests) {
  try {
    fn()
    console.log("ok - setup sheet model: " + name)
  } catch (e) {
    failed++
    console.log("not ok - setup sheet model: " + name + "\n  " + e.message)
  }
}
process.exit(failed ? 1 : 0)
