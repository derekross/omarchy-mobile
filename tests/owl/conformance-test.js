// SPDX-License-Identifier: MIT
// tests/owl/conformance.js's report on the host, without the conformance
// container or the reference checkout under /ref: a preload hands the script
// one synthetic widget case (the colors probe standing in for a store
// widget) and edited expectations from a scratch directory, then each run's
// report.json is checked. Nothing under /ref or in this repository is
// written; the scratch directory is under $TMPDIR and removed afterwards.
//
//   node tests/owl/conformance-test.js
"use strict"
const fs = require("fs"), os = require("os"), path = require("path"), cp = require("child_process")
const HERE = __dirname
const probes = path.resolve(HERE, "../../packages/omamobile-shell/test/owl-probes")
const probe = JSON.parse(fs.readFileSync(path.join(probes, "colors.expected.json"), "utf8"))
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "owl-conformance-test-"))
let failed = 0
function ok(cond, name, detail) {
  if (cond) console.log("ok - " + name)
  else { failed++; console.log("not ok - " + name + (detail ? "\n  " + detail : "")) }
}

// Every path the script reads that this run replaces, to a scratch file.
const preload = path.join(tmp, "redirect.js")
fs.writeFileSync(preload, `"use strict"
const fs = require("fs")
const map = JSON.parse(process.env.OWL_TEST_REDIRECT)
const read = fs.readFileSync
fs.readFileSync = function (p, ...rest) { return read.call(this, typeof p === "string" && map[p] || p, ...rest) }
`)

// One run of the script with these expectations; its report, or the failure.
function run(walk, compile) {
  const dir = fs.mkdtempSync(path.join(tmp, "run-"))
  const file = (name, value) => { const f = path.join(dir, name); fs.writeFileSync(f, JSON.stringify(value)); return f }
  const map = {
    [path.join(HERE, "cases.json")]: file("cases.json", { widgets: [{ id: "test/colors", covers: [] }] }),
    "/ref/omarchy-widgets/widgets/test/colors/widget.owl": path.join(probes, "colors.owl"),
    [path.join(HERE, "fixtures", "test.colors.json")]: path.join(probes, "fixture.json"),
    [path.join(HERE, "expected", "test.colors.compile.json")]: file("compile.json", compile),
    [path.join(HERE, "expected", "test.colors.walk.json")]: file("walk.json", walk),
    [path.join(probes, "colors.expected.json")]: file("probe.json", { compile, walk }),
  }
  const out = path.join(dir, "out")
  const r = cp.spawnSync(process.execPath, ["-r", preload, path.join(HERE, "conformance.js"), "--out", out],
                         { encoding: "utf8", env: Object.assign({}, process.env, { OWL_TEST_REDIRECT: JSON.stringify(map) }) })
  const reportFile = path.join(out, "report.json")
  if (r.status !== 0 || !fs.existsSync(reportFile)) {
    // The thrown error's own line; the last lines of stderr are its stack.
    const err = (r.stderr || "").match(/^\w*Error\b.*$/m)
    return { error: "exit " + r.status + ", no report: " + (err ? err[0] : (r.stderr || "").trim().split("\n").slice(-3).join(" | ")) }
  }
  const report = JSON.parse(fs.readFileSync(reportFile, "utf8"))
  // The widget case and the probe this run edited.
  return [report.cases.find((x) => x.id === "test/colors"), report.probes.find((x) => x.probe === "colors.owl")]
}

// Both the widget case and the probe give `why` at `level`.
function expect(name, walk, compile, level, why) {
  const got = run(walk, compile)
  if (got.error) return ok(false, name, got.error)
  for (const [where, x] of [["widget", got[0]], ["probe", got[1]]])
    ok(x && x[level].why === why, name + " (" + where + ")", "got " + (x && x[level].why) + "\n  want " + why)
}
const l3 = (name, edit, want) => { const w = structuredClone(probe.walk); edit(w); expect(name, w, probe.compile, "l3", JSON.stringify(want)) }
// conformance.js's shown() for a value that is there.
const shown = (v) => JSON.stringify(v).slice(0, 160)
const children = probe.walk.root[0].children
const last = children.length - 1

try {
  // The control: the unedited expectations pass at every level.
  const same = run(probe.walk, probe.compile)
  if (same.error) ok(false, "unedited expectations run", same.error)
  else {
    const [c, p] = same
    ok(c && c.l1.pass && c.l2.pass && c.l3.pass && p && p.l1.pass && p.l3.pass, "unedited expectations pass L1-L3",
       JSON.stringify({ case: c, probe: p }))
  }

  l3("an ordinary difference names its path and both values",
    (w) => { w.root[0].children[0].props.text = "z" },
    { at: "$.root[0].children[0].props.text", expected: '"z"', ours: '"a"' })
  l3("a member only the reference has is missing from ours",
    (w) => { w.extra = 1 },
    { at: "$.extra", expected: "1", ours: "(missing)" })
  l3("a member only we have is missing from the reference",
    (w) => { delete w.root },
    { at: "$.root", expected: "(missing)", ours: shown(probe.walk.root) })
  l3("a nested member only the reference has",
    (w) => { w.root[0].children[1].props.extra = "x" },
    { at: "$.root[0].children[1].props.extra", expected: '"x"', ours: "(missing)" })
  l3("a nested member only we have",
    (w) => { delete w.root[0].children[0].props.text },
    { at: "$.root[0].children[0].props.text", expected: "(missing)", ours: '"a"' })
  l3("a longer array in the reference",
    (w) => { w.root[0].children.push({ kind: "Text" }) },
    { at: "$.root[0].children[" + (last + 1) + "]", expected: '{"kind":"Text"}', ours: "(missing)" })
  l3("a longer array in ours",
    (w) => { w.root[0].children.pop() },
    { at: "$.root[0].children[" + last + "]", expected: "(missing)", ours: shown(children[last]) })

  // capsMatch reports the first difference in the commands list too.
  const command = { id: "x", argv: ["true"] }
  expect("a command only the reference lists", probe.walk, Object.assign({}, probe.compile, { commands: [command] }), "l2",
    "commands differ: " + JSON.stringify({ at: "$[0]", expected: shown(command), ours: "(missing)" }))
} finally {
  fs.rmSync(tmp, { recursive: true, force: true })
}
if (failed) { console.log("not ok - " + failed + " conformance report check(s) failed"); process.exit(1) }
console.log("ok - conformance reports name missing members")
