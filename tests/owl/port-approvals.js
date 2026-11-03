// SPDX-License-Identifier: MIT
// For each of the 47 old ports: what its OWL original needs, what the port
// had, and whether a migrated layout approves it without asking (the same
// rule the home screen applies, owl/catalog.js portApproval). Prints a
// Markdown table for docs/owl-review; exits 1 if the owner's layout's
// widgets don't come out as the review says. Our own copies of store widgets
// (packages/omamobile-owl-widgets/overrides/, what the package ships) are
// read in place of the store's.
//   node port-approvals.js <store widgets dir>
"use strict"
const fs = require("fs"), path = require("path")
const { load } = require(path.resolve(__dirname, "../../packages/omamobile-shell/test/owl-load.js"))
const H = require(path.resolve(__dirname, "../../packages/omamobile-shell/plugins/omamobile.home/HomeModel.js"))
const K = load("catalog.js")
const dir = process.argv[2]
const rows = [], verdicts = {}
for (const port of H.PORTED_ORDER) {
  const store = H.PORTED[port].credit
  const ours = path.resolve(__dirname, "../../packages/omamobile-owl-widgets/overrides", store, "widget.owl")
  const info = K.describe(port, fs.readFileSync(fs.existsSync(ours) ? ours : path.join(dir, store, "widget.owl"), "utf8"), H.GRID, 908 / 6, 480 / 6 / 69)
  const had = H.portCapabilities(port)
  const v = K.portApproval(had, info, true)
  verdicts[port] = !!v.approve
  const hadText = [had.commands ? "commands" : "", had.network ? "internet (" + (had.hosts === null ? "any you listed" : had.hosts.join(", ")) + ")" : "",
                   had.notifications ? "notifications" : ""].filter(Boolean).join(", ") || "nothing"
  rows.push(`| ${H.PORTED[port].name} | ${store} | ${hadText} | ${K.summary(info.caps)} | ${v.approve ? "**approved**" : "asks: " + v.extra.join("; ")} |`)
}
console.log("| Built-in | OWL original | The port had | The original needs | After migration |")
console.log("| --- | --- | --- | --- | --- |")
rows.forEach((r) => console.log(r))
const expect = { crypto: true, today: true, earthquakes: false, habits: false, forecast: true }
const wrong = Object.keys(expect).filter((k) => verdicts[k] !== expect[k])
if (wrong.length) { console.error("unexpected verdicts: " + wrong.join(", ")); process.exit(1) }
console.error(Object.values(verdicts).filter(Boolean).length + " of 47 approved without asking")
