// SPDX-License-Identifier: MIT
// The setup sheet's pure parts: the pages of each flow, what each asks, the
// scripts' argv, and what their answers mean. No QML here, so
// test/onboarding-model.js runs it under Node through the module.exports.
//
// Two flows: "onboarding" (the first run: name and email, then a PIN or
// password unless there is one, then Omarchy's agent invitation) and "pin"
// (System > PIN: choose PIN or password, set it). Each asks what the
// terminal prompts in omamobile-onboarding and omamobile-set-pin ask, in
// their order, and every answer goes to those scripts.

var STATUS_ARGV = ["omamobile-onboarding", "--status", "--json"]
var INVITE_ARGV = ["omamobile-onboarding", "--invite-agent"]

function identityArgv(name, email) {
  return ["omamobile-onboarding", "--identity", String(name || "").trim(), String(email || "").trim()]
}

// `omamobile-set-pin --apply TYPE`: the current and the new secret go to
// its stdin, never here.
function applyArgv(type) {
  return ["omamobile-set-pin", "--apply", type === "password" ? "password" : "pin"]
}

function parseJson(text) {
  try {
    var value = JSON.parse(String(text || ""))
    return value && typeof value === "object" ? value : null
  } catch (e) {
    return null
  }
}

// `omamobile-onboarding --status --json`, with every field present.
function parseStatus(text) {
  var raw = parseJson(text) || {}
  var pin = raw.pin && typeof raw.pin === "object" ? raw.pin : {}
  return {
    name: String(raw.name || ""),
    email: String(raw.email || ""),
    identity: !!raw.identity,
    pin: { set: pin.set === true, type: pin.type === "password" ? "password" : "pin" },
    agent: String(raw.agent || "")
  }
}

var CHOICES = {
  pin: { id: "pin", title: "PIN", detail: "Numbers only: the lock screen opens on a number pad" },
  password: { id: "password", title: "Password", detail: "Letters, numbers and symbols: the lock screen opens on the keyboard; 123 switches to a number pad" }
}

// The two ways to unlock, the current choice first, as `gum choose` lists them.
function typeChoices(currentType) {
  return currentType === "password" ? [CHOICES.password, CHOICES.pin] : [CHOICES.pin, CHOICES.password]
}

var FLOWS = {
  onboarding: ["identity", "credential", "done"],
  pin: ["pin-choice", "pin-entry", "done"]
}

function firstPage(flow) {
  return flow === "pin" ? "pin-choice" : "identity"
}

// The page after `page`. In the first run, the credential step is a note
// when a PIN or password exists already ("credential-exists", as the
// terminal flow says), else the choice and the entry.
function nextPage(flow, page, status) {
  var hasPin = !!(status && status.pin && status.pin.set)
  if (flow === "pin") {
    if (page === "pin-choice") return "pin-entry"
    return "done"
  }
  if (page === "identity") return hasPin ? "credential-exists" : "pin-choice"
  if (page === "credential-exists") return "done"
  if (page === "pin-choice") return "pin-entry"
  return "done"
}

// What the entry asks, in passwd's order: the current one first when the
// account has one.
function entrySteps(hasCurrent) {
  return hasCurrent ? ["current", "new", "retype"] : ["new", "retype"]
}

function stepText(step, type) {
  var what = type === "password" ? "password" : "PIN"
  if (step === "current") return { title: "Enter your current " + what, hint: "" }
  if (step === "retype") return { title: "Enter it again", hint: "" }
  return {
    title: "Choose a " + what,
    hint: type === "password" ? "The lock screen opens on the keyboard; 123 switches to a number pad." : "Use digits only: the lock screen opens on a number pad."
  }
}

// What `omamobile-set-pin --apply` said (its exit code and stdout).
function applyOutcome(exitCode, text) {
  var reason = String(text || "").trim().split("\n")[0] || ""
  switch (exitCode) {
  case 0: return { result: "set", reason: "" }
  case 3: return { result: "wrong-current", reason: "" }
  case 5: return { result: "refused", reason: reason || "The new one was refused" }
  default: return { result: "error", reason: reason || "omamobile-set-pin failed (exit " + exitCode + ")" }
  }
}

// The words for a failed attempt, by what the entry goes back to.
function failureText(outcome, type) {
  var what = type === "password" ? "password" : "PIN"
  if (outcome.result === "wrong-current") return { step: "current", text: "Wrong " + what + ". Try again." }
  if (outcome.result === "refused") return { step: "new", text: outcome.reason + ". Choose another." }
  return { step: "new", text: outcome.reason }
}

function doneText(flow, type, changed, agent) {
  var what = type === "password" ? "Password" : "PIN"
  var title = changed ? what + " set." : "All set."
  var body = changed ? "Your phone now locks after it starts." : ""
  if (flow === "onboarding" && !agent) body += (body ? " " : "") + "Omarchy will invite you to pick a default agent."
  return { title: title, body: body }
}

if (typeof module !== "undefined") {
  module.exports = {
    STATUS_ARGV: STATUS_ARGV, INVITE_ARGV: INVITE_ARGV, FLOWS: FLOWS, CHOICES: CHOICES,
    identityArgv: identityArgv, applyArgv: applyArgv, parseJson: parseJson, parseStatus: parseStatus,
    typeChoices: typeChoices, firstPage: firstPage, nextPage: nextPage, entrySteps: entrySteps,
    stepText: stepText, applyOutcome: applyOutcome, failureText: failureText, doneText: doneText
  }
}
