// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.back/BackModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.back/BackModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])

test("Escape goes through a virtual keyboard, with Hyprland's dispatcher (down then up, one process) as the fallback", () => {
  assert.strictEqual(M.ESCAPE_DOWN, 'hl.dsp.send_key_state({ mods = "", key = "code:9", state = "down" })')
  assert.strictEqual(M.ESCAPE_UP, 'hl.dsp.send_key_state({ mods = "", key = "code:9", state = "up" })')
  const [sh, c, script, name, down, up, terminals] = M.ESCAPE_ARGV
  assert.deepStrictEqual([sh, c, name, down, up], ["sh", "-c", "sh", M.ESCAPE_DOWN, M.ESCAPE_UP])
  assert.strictEqual(terminals, M.TERMINALS.join(" "))
  // The dispatches are positional arguments, never spliced into the script.
  assert.ok(!script.includes("send_key_state"))
  // wtype first, and nothing after it when it is there (exec): Hyprland says
  // "ok" to the dispatches and the app never sees the key (7 Pro, 2026-11-10)
  assert.ok(script.includes("if command -v wtype >/dev/null 2>&1; then exec wtype -k Escape; fi; "))
  assert.ok(script.indexOf("exec wtype -k Escape") < script.indexOf('hyprctl dispatch "$1"'))
  assert.ok(script.indexOf('hyprctl dispatch "$1"') < script.indexOf("sleep 0.05"))
  assert.ok(script.indexOf("sleep 0.05") < script.indexOf('hyprctl dispatch "$2"'))
})

// The script itself, against stand-ins on a private PATH: what runs for a
// terminal, for another app, with nothing focused, and without wtype.
test("a terminal gets no Escape: Back goes home; every other window gets the virtual keyboard's Escape", () => {
  const fs = require("fs"), os = require("os"), path = require("path"), cp = require("child_process")
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "back-esc-"))
  const log = path.join(dir, "log")
  const stub = (name, body) => { fs.writeFileSync(path.join(dir, name), "#!/bin/sh\n" + body + "\n", { mode: 0o755 }) }
  const real = n => cp.execSync("command -v " + n, { shell: "/bin/sh" }).toString().trim()
  for (const n of ["sh", "jq", "sleep"]) fs.symlinkSync(real(n), path.join(dir, n))
  stub("hyprctl", 'if [ "$1" = activewindow ]; then printf %s "$ACTIVE"; else echo "hyprctl $*" >> "$LOG"; fi')
  stub("omamobile-home", 'echo home >> "$LOG"')
  const run = (active, withWtype) => {
    fs.writeFileSync(log, "")
    if (withWtype) stub("wtype", 'echo "wtype $*" >> "$LOG"'); else fs.rmSync(path.join(dir, "wtype"), { force: true })
    cp.execFileSync(M.ESCAPE_ARGV[0], M.ESCAPE_ARGV.slice(1), { env: { PATH: dir, LOG: log, ACTIVE: active } })
    return fs.readFileSync(log, "utf8").trim().split("\n").filter(Boolean)
  }
  try {
    for (const t of M.TERMINALS) assert.deepStrictEqual(run(JSON.stringify({ class: t }), true), ["home"], t)
    assert.deepStrictEqual(run('{"class":"org.omamobile.Settings"}', true), ["wtype -k Escape"])
    // a class that only contains a terminal's name is not a terminal
    assert.deepStrictEqual(run('{"class":"footnotes"}', true), ["wtype -k Escape"])
    assert.deepStrictEqual(run('{"class":"my kitty"}', true), ["wtype -k Escape"])
    // nothing focused (a shell sheet has the keyboard), or no answer: Escape, never home
    assert.deepStrictEqual(run("{}", true), ["wtype -k Escape"])
    assert.deepStrictEqual(run("Invalid", true), ["wtype -k Escape"])
    // without wtype: the dispatches, down then up; a terminal still goes home
    assert.deepStrictEqual(run('{"class":"org.omamobile.Settings"}', false),
                           ["hyprctl dispatch " + M.ESCAPE_DOWN, "hyprctl dispatch " + M.ESCAPE_UP])
    assert.deepStrictEqual(run('{"class":"foot"}', false), ["home"])
  } finally { fs.rmSync(dir, { recursive: true, force: true }) }
  assert.ok(M.isTerminal("foot") && M.isTerminal("org.omarchy.terminal") && !M.isTerminal("") && !M.isTerminal("Foot"))
})

test("home is the shell's one command, with nothing of Hyprland in it", () => {
  assert.deepStrictEqual(M.HOME_ARGV, ["omamobile-home"])
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
