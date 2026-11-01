// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.voice/VoiceModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.voice/VoiceModel.js"))
const L = require(path.join(__dirname, "../plugins/omamobile.launcher/LauncherModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])

test("one recording mode: --no-osd to the transcript file, the old one removed first, nothing interpolated", () => {
  const p = "/run/user/1000/it's \"odd\"; rm -rf ~/omamobile-voice.txt"
  const argv = M.startArgv(p)
  assert.deepStrictEqual(argv.slice(0, 4), ["sh", "-c", 'rm -f -- "$1"; shift; exec "$@"', "sh"])
  assert.strictEqual(argv[4], p)
  assert.deepStrictEqual(argv.slice(5), ["voxtype", "record", "start", "--no-osd", "--file=" + p])
  assert.ok(!argv[2].includes(p))
  for (const flag of ["--type", "--model", "--auto-submit", "--smart-auto-submit", "--clipboard"]) assert.ok(!argv.includes(flag), flag)
})

test("stop, cancel and the transcript's path", () => {
  assert.deepStrictEqual(M.STOP_ARGV, ["voxtype", "record", "stop"])
  assert.deepStrictEqual(M.CANCEL_ARGV, ["voxtype", "record", "cancel"])
  assert.strictEqual(M.transcriptPath("/run/user/1000"), "/run/user/1000/omamobile-voice.txt")
})

test("the daemon's state file", () => {
  assert.strictEqual(M.voxState("recording\n"), "recording")
  assert.strictEqual(M.voxState("streaming"), "streaming")
  assert.strictEqual(M.voxState(" transcribing "), "transcribing")
  assert.strictEqual(M.voxState(""), "idle")
  assert.strictEqual(M.voxState("garbage"), "idle")
})

test("the bar's recording: starting, listening, transcribing, then read once", () => {
  assert.deepStrictEqual(M.step("starting", true, "idle"), { phase: "starting", read: false }, "a start the daemon hasn't seen yet waits")
  assert.deepStrictEqual(M.step("starting", true, "recording"), { phase: "listening", read: false })
  assert.deepStrictEqual(M.step("listening", true, "transcribing"), { phase: "transcribing", read: false })
  assert.deepStrictEqual(M.step("transcribing", true, "idle"), { phase: "transcribing", read: true })
  assert.deepStrictEqual(M.step("listening", true, "idle"), { phase: "transcribing", read: true }, "stopped without transcribing still reads")
  assert.deepStrictEqual(M.step("result", true, "idle"), { phase: "result", read: false })
  assert.deepStrictEqual(M.step("error", true, "idle"), { phase: "error", read: false })
  assert.deepStrictEqual(M.step("idle", true, "idle"), { phase: "idle", read: false })
})

test("a recording the bar didn't start shows nothing and delivers nothing", () => {
  assert.deepStrictEqual(M.step("idle", false, "recording"), { phase: "idle", read: false })
  assert.deepStrictEqual(M.step("idle", false, "transcribing"), { phase: "idle", read: false })
})

test("push-to-talk: a short press keeps listening, a hold stops on release", () => {
  assert.strictEqual(M.releaseStops("listening", M.HOLD_MS - 1), false)
  assert.strictEqual(M.releaseStops("listening", M.HOLD_MS), true)
  assert.strictEqual(M.releaseStops("starting", 5000), true)
  assert.strictEqual(M.releaseStops("transcribing", 5000), false)
})

test("the destination follows what is in front", () => {
  assert.strictEqual(M.contextDestination(true, true), "agent")
  assert.strictEqual(M.contextDestination(true, false), "type")
  assert.strictEqual(M.contextDestination(false, false), "ask")
  assert.strictEqual(M.contextDestination(false, true), "ask", "no app on screen: the home screen")
  assert.strictEqual(M.isAgent("org.omarchy.agent"), true)
  assert.strictEqual(M.isAgent("foot"), false)
  assert.strictEqual(M.isAgent(undefined), false)
})

test("the chip's list: the context's own, then Copy and Search", () => {
  assert.deepStrictEqual(M.destinations(true, true), ["agent", "type", "copy", "search"])
  assert.deepStrictEqual(M.destinations(true, false), ["type", "copy", "search"])
  assert.deepStrictEqual(M.destinations(false, false), ["ask", "copy", "search"])
})

test("words: the chip, the list's notes, the verb, the agent hint", () => {
  const name = L.agentName("claude")
  assert.strictEqual(M.destinationLabel("type", name), "Type here")
  assert.strictEqual(M.destinationLabel("agent", name), "Send to Claude Code")
  assert.strictEqual(M.destinationLabel("ask", name), "Ask Claude Code")
  assert.strictEqual(M.destinationLabel("ask", ""), "Ask your agent")
  assert.strictEqual(M.destinationLabel("copy", name), "Copy to clipboard")
  assert.strictEqual(M.destinationLabel("search", name), "Search apps")
  assert.strictEqual(M.destinationNote("ask"), "new prompt")
  assert.strictEqual(M.destinationNote("copy"), "paste anywhere")
  assert.strictEqual(M.destinationNote("search"), "launcher")
  assert.deepStrictEqual(["type", "agent", "ask", "copy", "search"].map(M.doneVerb), ["type it", "send", "ask", "copy", "search"])
  assert.strictEqual(M.destinationHint("agent"), "Types what you say into the prompt and presses Enter.")
  assert.strictEqual(M.destinationHint("type"), "")
})

test("delivery: the text on stdin or one argv element, never in a shell string", () => {
  const text = "it's $(whoami) \"quoted\""
  for (const dest of ["type", "agent", "copy"]) {
    const argv = M.deliveryArgv(dest, text)
    assert.strictEqual(argv[0], "sh")
    assert.ok(!argv[2].includes(text))
    assert.strictEqual(argv[4], text)
  }
  assert.ok(M.deliveryArgv("type", "x")[2].includes("wtype -"))
  assert.ok(!M.deliveryArgv("type", "x")[2].includes("Return"), "Type here never presses Enter")
  assert.ok(M.deliveryArgv("agent", "x")[2].endsWith("exec wtype -k Return"), "Send to the agent: typed, then Enter")
  assert.ok(M.deliveryArgv("copy", "x")[2].includes("wl-copy"))
  assert.deepStrictEqual(M.deliveryArgv("search", text), ["omarchy-shell", "shell", "summon", "omamobile.launcher", JSON.stringify({ query: text })])
  assert.strictEqual(M.deliveryArgv("ask", "x"), null, "Ask has its own step")
})

test("after the transcript: Ask checks first (or sends with the check off), the rest deliver at once", () => {
  const a = M.afterRead("ask", "  Check the battery\ndrain.  ", true)
  assert.deepStrictEqual(a, { phase: "result", text: "Check the battery drain.", error: "", argv: null, send: false })
  assert.deepStrictEqual(M.afterRead("ask", "Hi", false), { phase: "delivered", text: "Hi", error: "", argv: null, send: true })
  const t = M.afterRead("type", "hello", true)
  assert.strictEqual(t.phase, "delivered", "the final words show for a moment, then the bar closes")
  assert.deepStrictEqual(t.argv, M.deliveryArgv("type", "hello"))
  assert.strictEqual(t.send, false)
  const e = M.afterRead("agent", "  \n", true)
  assert.strictEqual(e.phase, "error")
  assert.strictEqual(e.argv, null)
  assert.strictEqual(e.error, M.NOTHING_HEARD)
})

test("Ask is the launcher's prompt: one argv element, no shell", () => {
  const text = M.cleanTranscript("  look at $(rm -rf ~) and `this`\n")
  assert.deepStrictEqual(L.promptArgv(text), ["omamobile-launch", "cmd", "--", "omarchy-agent-prompt", "look at $(rm -rf ~) and `this`"])
  assert.strictEqual(M.permissionText("Claude Code"), "Claude Code runs with full permissions on this phone. Check the words before it starts.")
})

test("the clock, and the 60 s cap near its end", () => {
  assert.strictEqual(M.clock(7.9), "0:07")
  assert.strictEqual(M.elapsedText(49), "0:49")
  assert.strictEqual(M.elapsedText(50), "0:50 · stops at 1:00")
  assert.strictEqual(M.elapsedText(75), "1:00 · stops at 1:00")
  assert.strictEqual(M.statusText("listening"), "listening")
  assert.strictEqual(M.statusText("idle"), "")
  assert.strictEqual(M.modelShort("tiny.en"), "tiny")
})

test("the level meter", () => {
  let levels = []
  for (let i = 0; i < M.LEVEL_BARS + 10; i++) {
    const before = levels
    levels = M.pushLevel(levels, i % 2 ? 0.2 : 5)
    assert.notStrictEqual(levels, before)
  }
  assert.strictEqual(levels.length, M.LEVEL_BARS)
  assert.ok(levels.every((v) => v >= 0 && v <= 1))
  const bars = M.meterBars([0.5, 2], true)
  assert.strictEqual(bars.length, M.LEVEL_BARS)
  assert.deepStrictEqual(bars[M.LEVEL_BARS - 1], { value: 1, lit: true })
  assert.deepStrictEqual(bars[0], { value: 0, lit: false })
  assert.ok(M.meterBars([0.5], false).every((b) => !b.lit))
  assert.deepStrictEqual(M.parseLevel('{"peak":0.421,"rms":0.180,"vad":1,"ts_ms":1234567}'), { rms: 0.18, peak: 0.421, vad: true })
  assert.strictEqual(M.parseLevel('{"status":"connected"}'), null)
})

test("the theme's warning colour, from colors.toml", () => {
  assert.strictEqual(M.themeWarning('accent = "#7aa2f7"\nred = "#f7768e"\nyellow = "#e0af68"\n'), "#e0af68")
  assert.strictEqual(M.themeWarning('color3 = "#ddaa00"\n'), "#ddaa00")
  assert.strictEqual(M.themeWarning('bright_yellow = "#ff9e64"\n'), "", "only the role itself")
  assert.strictEqual(M.themeWarning(""), "")
})

test("settings: three switches, earlier keys dropped, the preview on unless turned off", () => {
  const d = M.parseSettings("")
  assert.deepStrictEqual(d, { version: 3, powerVolumeUp: false, confirmSend: true, livePreview: true })
  const old = M.parseSettings('{"version": 2, "holdPill": false, "micKey": false, "agentMic": true, "agentSubmit": "say", "powerVolumeUp": true, "confirmSend": false, "sayToSend": true}')
  assert.deepStrictEqual(old, { version: 3, powerVolumeUp: true, confirmSend: false, livePreview: true }, "0.2.58-0.2.62 files: the keys that still mean something stay, the preview gets its default")
  assert.strictEqual(M.parseSettings('{"livePreview": false}').livePreview, false)
  assert.strictEqual(M.withSetting(d, "livePreview", false).livePreview, false)
  assert.strictEqual(M.parseSettings('{"powerVolumeUp": "yes"}').powerVolumeUp, false)
  const t = M.withSetting(d, "powerVolumeUp", true)
  assert.strictEqual(t.powerVolumeUp, true)
  assert.strictEqual(d.powerVolumeUp, false, "a copy")
  assert.deepStrictEqual(M.withSetting(d, "holdPill", true), d)
  assert.deepStrictEqual(M.parseSettings(M.serializeSettings(t)), t)
  assert.ok(!M.serializeSettings(old).includes("holdPill"))
})

test("models: the config's [whisper] model, what is downloaded, the rows", () => {
  assert.strictEqual(M.configModel('[audio]\nmodel = "x"\n[whisper]\nmodel = "tiny.en"\n'), "tiny.en")
  assert.strictEqual(M.configModel(""), "base.en")
  assert.deepStrictEqual(M.installedModels("ggml-tiny.en.bin\nggml-base.en.bin\nsilero.onnx\n"), ["tiny.en", "base.en"])
  const rows = M.modelRows("tiny.en", ["tiny.en", "base.en"])
  assert.deepStrictEqual(rows.map((r) => r.name), ["Fast", "Balanced", "Accurate"])
  assert.deepStrictEqual(rows.map((r) => r.chosen), [true, false, false])
  assert.strictEqual(rows[2].line, "small · 466 MB · download")
})

test("models: Voxtype's own download and switch, nothing interpolated", () => {
  assert.deepStrictEqual(M.downloadArgv("small.en"),
    ["voxtype", "setup", "--download", "--model", "small.en", "--no-post-install", "--progress-format", "json"])
  const sw = M.switchArgv("small.en; rm -rf ~")
  assert.ok(sw[2].includes('voxtype config set whisper.model "$1"'))
  assert.strictEqual(sw[4], "small.en; rm -rf ~")
  assert.deepStrictEqual(M.parseProgress('{"percent": 41.6}'), { percent: 42, text: "42%" })
  assert.deepStrictEqual(M.parseProgress('{"downloaded": 25, "total": 100}'), { percent: 25, text: "25%" })
  assert.strictEqual(M.parseProgress("Downloading..."), null)
})

test("the delivered words stay through the daemon's idle, then the timer closes the bar", () => {
  assert.deepStrictEqual(M.step("delivered", true, "idle"), { phase: "delivered", read: false })
  assert.deepStrictEqual(M.step("delivered", false, "idle"), { phase: "delivered", read: false })
  assert.deepStrictEqual(M.step("delivered", true, "recording"), { phase: "listening", read: false }, "a new recording takes over")
  assert.ok(M.DELIVERED_MS >= 500 && M.DELIVERED_MS <= 1500, "a moment, not a wait")
})

test("live preview: the helper's lines, when it runs, what the bar's line shows", () => {
  assert.deepStrictEqual(M.PREVIEW_ARGV, ["omamobile-voice-preview"])
  assert.deepStrictEqual(M.parsePartial('{"text": "  open the\\nvoice plan ", "secs": 2.4, "ms": 600}'), { text: "open the voice plan" })
  assert.deepStrictEqual(M.parsePartial('{"status": "no-model"}'), { status: "no-model" })
  assert.strictEqual(M.parsePartial("not json"), null)
  assert.strictEqual(M.parsePartial('{"peak": 1}'), null)
  assert.strictEqual(M.previewRuns("listening", true, true), true)
  assert.strictEqual(M.previewRuns("listening", true, undefined), true, "on by default")
  assert.strictEqual(M.previewRuns("listening", true, false), false, "the setting turns it off")
  assert.strictEqual(M.previewRuns("transcribing", true, true), false, "it stops when listening ends, so the daemon has the CPU")
  assert.strictEqual(M.previewRuns("starting", true, true), false, "not before the daemon listens")
  assert.strictEqual(M.previewRuns("listening", false, true), false, "not for a recording the bar didn't start")
  assert.deepStrictEqual(M.liveLine("listening", "open the", ""), { text: "open the", final: false })
  assert.deepStrictEqual(M.liveLine("transcribing", "open the voice", ""), { text: "open the voice", final: false }, "the last preview stays while the daemon works")
  assert.deepStrictEqual(M.liveLine("delivered", "open the voice", "Open the voice plan."), { text: "Open the voice plan.", final: true }, "the final words replace it")
  assert.deepStrictEqual(M.liveLine("result", "x", "y"), { text: "", final: false }, "the check before Ask has its own text")
  assert.deepStrictEqual(M.liveLine("idle", "x", "y"), { text: "", final: false })
})

test("live preview: a long preview keeps its newest words, cut at a word", () => {
  assert.strictEqual(M.partialTail("short words", 90), "short words")
  const long = "one two three four five six seven eight nine ten eleven twelve"
  const tail = M.partialTail(long, 20)
  assert.ok(tail.startsWith("…") && long.endsWith(tail.slice(1)), tail)
  assert.ok(tail.length <= 21, tail)
  assert.ok(!tail.slice(1).startsWith(" ") && long.split(" ").includes(tail.slice(1).split(" ")[0]), "starts on a whole word: " + tail)
})

test("haptic ticks: listening starting and ending", () => {
  assert.strictEqual(M.ticks("starting", "listening"), true)
  assert.strictEqual(M.ticks("listening", "transcribing"), true)
  assert.strictEqual(M.ticks("listening", "listening"), false)
  assert.strictEqual(M.ticks("transcribing", "idle"), false)
  assert.ok(M.HAPTIC_ARGV[2].includes("fbcli -E button-pressed"))
})

let failed = 0
for (const [name, fn] of tests) {
  try {
    fn()
    console.log("ok - voice model: " + name)
  } catch (e) {
    failed++
    console.log("not ok - voice model: " + name + "\n  " + (e && e.message))
  }
}
process.exit(failed ? 1 : 0)
