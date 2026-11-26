// SPDX-License-Identifier: MIT
// The Text size page's model: what `omamobile-text-size get --json` says,
// and the sizes the page draws each step at. Pure functions, so
// test/textsize-model.js runs them under node.

var GET_ARGV = ["omamobile-text-size", "get", "--json"]

// What the page shows before the command answers, or if it can't run: the
// command's own steps (bin/omamobile-text-size STEPS).
var FALLBACK_STEPS = [
  { name: "smaller", label: "Smaller", px: 11 },
  { name: "default", label: "Default", px: 12 },
  { name: "large", label: "Large", px: 14 },
  { name: "larger", label: "Larger", px: 16 },
  { name: "largest", label: "Largest", px: 18 }
]

var PREVIEW = "Messages, menus and web pages will read like this."
var NOTE = "The bar, menus and this page change now. Apps that are open, the terminal and web apps pick it up when you reopen them."

function setArgv(name) { return ["omamobile-text-size", "set", String(name)] }

// { step, steps } from the command's JSON; null when it isn't usable.
function parse(text) {
  var data
  try { data = JSON.parse(String(text || "")) } catch (e) { return null }
  if (!data || !Array.isArray(data.steps) || data.steps.length === 0) return null
  var steps = []
  for (var i = 0; i < data.steps.length; i++) {
    var s = data.steps[i]
    if (!s || typeof s.name !== "string" || !(Number(s.px) > 0)) return null
    steps.push({ name: s.name, label: String(s.label || s.name), px: Number(s.px) })
  }
  var step = typeof data.step === "string" ? data.step : "default"
  return { step: step, steps: steps }
}

function find(steps, name) {
  for (var i = 0; i < steps.length; i++) if (steps[i].name === name) return steps[i]
  return null
}

// The preview line at the step's body size (the shell's base size is its
// body text), and each row's label at its heading size (base x 4/3), so the
// list itself shows how big each step is.
function previewPx(steps, name) {
  var s = find(steps, name)
  return s ? s.px : 12
}

function labelPx(px) { return Math.round(Number(px) * 4 / 3) }

if (typeof module !== "undefined") {
  module.exports = { GET_ARGV: GET_ARGV, FALLBACK_STEPS: FALLBACK_STEPS, PREVIEW: PREVIEW, NOTE: NOTE,
                     setArgv: setArgv, parse: parse, find: find, previewPx: previewPx, labelPx: labelPx }
}
