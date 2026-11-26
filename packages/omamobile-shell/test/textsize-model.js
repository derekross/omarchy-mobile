// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.textsize/TextSizeModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.textsize/TextSizeModel.js"))

// The command's answer, as bin/omamobile-text-size prints it
const answer = JSON.stringify({ step: "larger", chosen: true, steps: [
  { name: "smaller", label: "Smaller", px: 11, scale: 0.9167 },
  { name: "default", label: "Default", px: 12, scale: 1 },
  { name: "large", label: "Large", px: 14, scale: 1.1667 },
  { name: "larger", label: "Larger", px: 16, scale: 1.3333 },
  { name: "largest", label: "Largest", px: 18, scale: 1.5 }] })

const parsed = M.parse(answer)
assert.strictEqual(parsed.step, "larger")
assert.deepStrictEqual(parsed.steps.map(s => s.name), ["smaller", "default", "large", "larger", "largest"])
assert.deepStrictEqual(parsed.steps, M.FALLBACK_STEPS, "the page's fallback steps are the command's")
for (const bad of ["", "not json", "{}", '{"steps":[]}', '{"steps":[{"name":"x","px":0}]}', "null"])
  assert.strictEqual(M.parse(bad), null, bad)
assert.strictEqual(M.parse('{"steps":[{"name":"default","label":"Default","px":12}]}').step, "default")

assert.strictEqual(M.previewPx(parsed.steps, "largest"), 18)
assert.strictEqual(M.previewPx(parsed.steps, "nope"), 12)
// Each row's label grows with its step: never two the same size
const sizes = parsed.steps.map(s => M.labelPx(s.px))
assert.deepStrictEqual(sizes, [15, 16, 19, 21, 24])
assert.deepStrictEqual(M.setArgv("large"), ["omamobile-text-size", "set", "large"])
assert.deepStrictEqual(M.GET_ARGV, ["omamobile-text-size", "get", "--json"])

// The command's STEPS table and the fallback agree
const command = fs.readFileSync(path.join(__dirname, "../bin/omamobile-text-size"), "utf8")
const rows = [...command.matchAll(/^    \("([a-z]+)", "([A-Za-z]+)", (\d+)\),$/gm)].map(m => ({ name: m[1], label: m[2], px: Number(m[3]) }))
assert.deepStrictEqual(rows, M.FALLBACK_STEPS)
console.log("ok - text size model")
