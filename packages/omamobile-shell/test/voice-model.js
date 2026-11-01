// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.voice/VoiceModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.voice/VoiceModel.js"))
const L = require(path.join(__dirname, "../plugins/omamobile.launcher/LauncherModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])

test("every start passes --no-osd, and no per-recording --model (voxtype ignores one it hasn't prepared)", () => {
  for (const mode of ["type", "file"]) {
    const argv = M.startArgv(mode, "/run/user/1000/omamobile-voice.txt")
    assert.deepStrictEqual(argv.slice(0, 4), ["voxtype", "record", "start", "--no-osd"])
    assert.ok(!argv.includes("--model"))
  }
  assert.deepStrictEqual(M.startArgv("type", ""), ["voxtype", "record", "start", "--no-osd", "--type"])
  assert.deepStrictEqual(M.startArgv("file", "/r/omamobile-voice.txt"),
    ["voxtype", "record", "start", "--no-osd", "--file=/r/omamobile-voice.txt"])
})

test("the agent's recording removes the old transcript first, in one process, nothing interpolated", () => {
  const p = "/run/user/1000/it's \"odd\"; rm -rf ~/omamobile-voice.txt"
  const argv = M.fileStartArgv(p)
  assert.deepStrictEqual(argv.slice(0, 3), ["sh", "-c", 'rm -f -- "$1"; shift; exec "$@"'])
  assert.strictEqual(argv[3], "sh")
  assert.strictEqual(argv[4], p)
  assert.deepStrictEqual(argv.slice(5), M.startArgv("file", p))
  assert.ok(!argv[2].includes(p))
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
  assert.strictEqual(M.voxState("idle"), "idle")
  assert.strictEqual(M.voxState(""), "idle")
  assert.strictEqual(M.voxState(undefined), "idle")
  assert.strictEqual(M.voxState("garbage"), "idle")
})

test("the agent flow: starting, listening, transcribing, then read the transcript once", () => {
  let s = { phase: "starting", owner: "ask" }
  s = M.step(s.phase, s.owner, "idle")
  assert.deepStrictEqual(s, { phase: "starting", owner: "ask", read: false }, "a start the daemon hasn't seen yet waits")
  s = M.step(s.phase, s.owner, "recording")
  assert.deepStrictEqual(s, { phase: "listening", owner: "ask", read: false })
  s = M.step(s.phase, s.owner, "transcribing")
  assert.deepStrictEqual(s, { phase: "transcribing", owner: "ask", read: false })
  s = M.step(s.phase, s.owner, "idle")
  assert.deepStrictEqual(s, { phase: "transcribing", owner: "ask", read: true })
  // Reading happens; the page then moves to review, which the daemon's idle leaves alone.
  assert.deepStrictEqual(M.step("review", "ask", "idle"), { phase: "review", owner: "ask", read: false })
  assert.deepStrictEqual(M.step("error", "ask", "idle"), { phase: "error", owner: "ask", read: false })
})

test("a recording that stops without transcribing still reads (and finds nothing)", () => {
  assert.strictEqual(M.step("listening", "ask", "idle").read, true)
})

test("typing: idle again when the daemon is; nothing to read", () => {
  assert.deepStrictEqual(M.step("starting", "type", "recording"), { phase: "listening", owner: "type", read: false })
  assert.deepStrictEqual(M.step("listening", "type", "transcribing"), { phase: "transcribing", owner: "type", read: false })
  assert.deepStrictEqual(M.step("transcribing", "type", "idle"), { phase: "idle", owner: "", read: false })
})

test("a recording the shell didn't start (the tile, a script) shows as listening with no owner", () => {
  assert.deepStrictEqual(M.step("idle", "", "recording"), { phase: "listening", owner: "", read: false })
  assert.deepStrictEqual(M.step("listening", "", "idle"), { phase: "idle", owner: "", read: false })
})

test("transcripts: tidied, and nothing heard is an error", () => {
  assert.strictEqual(M.cleanTranscript("  Look at the\nspeaker plan.  \n"), "Look at the speaker plan.")
  assert.deepStrictEqual(M.afterRead("Hello there\n"), { phase: "review", text: "Hello there", error: "" })
  const e = M.afterRead("  \n")
  assert.strictEqual(e.phase, "error")
  assert.ok(e.error.length > 0)
  assert.strictEqual(M.afterRead(undefined).phase, "error")
})

test("push-to-talk: a short press keeps listening, a hold stops on release", () => {
  assert.strictEqual(M.releaseStops("listening", M.HOLD_MS - 1), false)
  assert.strictEqual(M.releaseStops("listening", M.HOLD_MS), true)
  assert.strictEqual(M.releaseStops("starting", 5000), true)
  assert.strictEqual(M.releaseStops("transcribing", 5000), false, "already stopped")
  assert.strictEqual(M.releaseStops("review", 5000), false)
})

test("the clock, and the 60 s cap near its end", () => {
  assert.strictEqual(M.clock(0), "0:00")
  assert.strictEqual(M.clock(7.9), "0:07")
  assert.strictEqual(M.clock(60), "1:00")
  assert.strictEqual(M.elapsedText(5), "0:05")
  assert.strictEqual(M.elapsedText(49), "0:49")
  assert.strictEqual(M.elapsedText(50), "0:50 · stops at 1:00")
  assert.strictEqual(M.elapsedText(75), "1:00 · stops at 1:00")
  assert.strictEqual(M.MAX_SECONDS, 60)
})

test("the level meter keeps the last bars, as a new array, within 0..1", () => {
  let levels = []
  for (let i = 0; i < M.LEVEL_BARS + 10; i++) {
    const before = levels
    levels = M.pushLevel(levels, i % 2 ? 0.2 : 5)
    assert.notStrictEqual(levels, before)
  }
  assert.strictEqual(levels.length, M.LEVEL_BARS)
  assert.ok(levels.every((v) => v >= 0 && v <= 1))
  assert.strictEqual(M.pushLevel([], -1)[0], 0)
  assert.ok(M.pushLevel([], 0.05)[0] > 0.05, "quiet speech still shows")
})

test("the meter: every bar, newest at the right, lit only while listening", () => {
  const bars = M.meterBars([0.5, 2], true)
  assert.strictEqual(bars.length, M.LEVEL_BARS)
  assert.deepStrictEqual(bars[M.LEVEL_BARS - 1], { value: 1, lit: true })
  assert.deepStrictEqual(bars[M.LEVEL_BARS - 2], { value: 0.5, lit: true })
  assert.deepStrictEqual(bars[0], { value: 0, lit: false })
  assert.ok(M.meterBars([0.5], false).every((b) => !b.lit))
  assert.strictEqual(M.meterBars(undefined, true).length, M.LEVEL_BARS)
})

test("voxtype-audio-bridge lines", () => {
  assert.deepStrictEqual(M.parseLevel('{"peak":0.421,"rms":0.180,"vad":1,"ts_ms":1234567}'), { rms: 0.18, peak: 0.421, vad: true })
  assert.strictEqual(M.parseLevel('{"status":"connected"}'), null)
  assert.strictEqual(M.parseLevel("not json"), null)
  assert.strictEqual(M.parseLevel(""), null)
})

test("words: status, hints, the warning and Send", () => {
  assert.strictEqual(M.statusText("listening", "ask"), "Listening")
  assert.strictEqual(M.statusText("transcribing", "type"), "Typing")
  assert.strictEqual(M.statusText("transcribing", "ask"), "Transcribing")
  assert.strictEqual(M.statusText("idle", ""), "")
  assert.ok(M.askHint("listening", true).startsWith("Let go of the pill to stop"))
  assert.ok(M.askHint("listening", false).startsWith("Tap Stop"))
  assert.strictEqual(M.permissionText("Claude Code"),
    "Claude Code runs with auto permissions here, so it acts on this without asking again.")
  assert.strictEqual(M.sendLabel(L.agentName("claude")), "Send to Claude Code")
  assert.strictEqual(M.sendLabel(""), "Choose an agent")
})

test("Send is the launcher's prompt: one argv element, no shell", () => {
  const text = M.cleanTranscript("  look at $(rm -rf ~) and `this`\n")
  const argv = L.promptArgv(text)
  assert.deepStrictEqual(argv, ["omamobile-launch", "cmd", "--", "omarchy-agent-prompt", "look at $(rm -rf ~) and `this`"])
})

test("copy and type: the text on stdin, never in the shell string", () => {
  const text = "it's $(whoami) \"quoted\""
  for (const argv of [M.copyArgv(text), M.typeArgv(text)]) {
    assert.strictEqual(argv[0], "sh")
    assert.strictEqual(argv[1], "-c")
    assert.ok(!argv[2].includes(text))
    assert.strictEqual(argv[3], "sh")
    assert.strictEqual(argv[4], text)
  }
  assert.ok(M.copyArgv("x")[2].includes("wl-copy"))
  assert.ok(M.typeArgv("x")[2].includes("wtype -"))
  assert.ok(M.typeArgv("x")[2].startsWith("sleep "), "after the sheet has gone")
})

test("typing into an agent: Enter after the text, on a spoken 'send', or never", () => {
  assert.deepStrictEqual(M.startArgv("type", "", "auto"), ["voxtype", "record", "start", "--no-osd", "--type", "--auto-submit"])
  assert.deepStrictEqual(M.startArgv("type", "", "say"), ["voxtype", "record", "start", "--no-osd", "--type", "--smart-auto-submit"])
  assert.deepStrictEqual(M.startArgv("type", "", "off"), ["voxtype", "record", "start", "--no-osd", "--type"])
  assert.deepStrictEqual(M.startArgv("type", ""), ["voxtype", "record", "start", "--no-osd", "--type"])
  for (const sub of ["auto", "say"]) {
    const a = M.startArgv("file", "/r/t.txt", sub)
    assert.ok(!a.includes("--auto-submit") && !a.includes("--smart-auto-submit"), "never for the agent sheet's transcript")
  }
  assert.strictEqual(M.isAgent("org.omarchy.agent"), true)
  assert.strictEqual(M.isAgent("foot"), false)
  assert.strictEqual(M.isAgent(undefined), false)
})

test("settings: defaults, only known booleans, round trip", () => {
  const d = M.parseSettings("")
  assert.deepStrictEqual(d, { version: 2, holdPill: true, micKey: true, agentMic: true, powerVolumeUp: false, agentSubmit: "auto", confirmSend: true })
  assert.strictEqual(M.parseSettings("{not json").powerVolumeUp, false)
  const s = M.parseSettings('{"powerVolumeUp": true, "holdPill": "no", "evil": true, "confirmSend": false}')
  assert.strictEqual(s.powerVolumeUp, true)
  assert.strictEqual(s.holdPill, true, "a non-boolean keeps the default")
  assert.strictEqual(s.evil, undefined)
  assert.strictEqual(s.confirmSend, false)
  const t = M.withSetting(d, "agentSubmit", "say")
  assert.strictEqual(t.agentSubmit, "say")
  assert.strictEqual(d.agentSubmit, "auto", "a copy")
  assert.strictEqual(M.withSetting(d, "agentSubmit", "always").agentSubmit, "auto", "only the three choices")
  assert.deepStrictEqual(M.withSetting(d, "nope", true), d)
  assert.deepStrictEqual(M.parseSettings(M.serializeSettings(t)), t)
  assert.ok(M.serializeSettings(t).endsWith("\n"))
})

test("settings: 0.2.59's Say 'send' switch moves to the agent choice", () => {
  assert.strictEqual(M.parseSettings('{"version": 1, "sayToSend": true}').agentSubmit, "auto", "on (the default) becomes Send automatically")
  assert.strictEqual(M.parseSettings('{"version": 1, "sayToSend": false}').agentSubmit, "off")
  assert.strictEqual(M.parseSettings('{"agentSubmit": "say", "sayToSend": false}').agentSubmit, "say", "a choice wins over the old switch")
  assert.strictEqual(M.parseSettings('{"agentSubmit": 3}').agentSubmit, "auto")
  assert.strictEqual(M.serializeSettings(M.parseSettings('{"sayToSend": true}')).includes("sayToSend"), false, "the old key is dropped")
  assert.deepStrictEqual(M.SUBMIT_CHOICES.map((c) => c.id), ["auto", "say", "off"])
  assert.strictEqual(M.SUBMIT_CHOICES[0].name, "Send automatically")
  assert.strictEqual(M.SUBMIT_CHOICES[1].name, "Say \u201csubmit\u201d to send", "Voxtype's trigger word is submit")
})

test("submitting: the agent mic and the key chord over an agent follow the setting; other dictation never", () => {
  const s = M.defaultSettings()
  assert.strictEqual(M.submitFor("agent", false, true, s), "auto")
  assert.strictEqual(M.submitFor("agent", false, true, M.withSetting(s, "agentSubmit", "say")), "say")
  assert.strictEqual(M.submitFor("type", true, true, s), "auto", "Power + Volume Up over an agent")
  assert.strictEqual(M.submitFor("type", true, false, s), "off", "Power + Volume Up over another app")
  assert.strictEqual(M.submitFor("type", false, true, s), "off", "the keyboard's mic key, even over an agent")
  assert.strictEqual(M.submitFor("type", false, false, s), "off")
  assert.strictEqual(M.submitFor("ask", true, true, s), "off", "the agent sheet sends itself")
})

test("models: the config's [whisper] model, what is downloaded, the rows", () => {
  assert.strictEqual(M.configModel('state_file = "auto"\n[audio]\nmodel = "x"\n[whisper]\nmodel = "tiny.en"\nlanguage = "en"\n'), "tiny.en")
  assert.strictEqual(M.configModel('[whisper]\nlanguage = "en"\n'), "base.en")
  assert.strictEqual(M.configModel(""), "base.en")
  assert.deepStrictEqual(M.installedModels("ggml-tiny.en.bin\nggml-base.en.bin\nsilero.onnx\n"), ["tiny.en", "base.en"])
  const rows = M.modelRows("tiny.en", ["tiny.en", "base.en"])
  assert.deepStrictEqual(rows.map((r) => r.id), ["tiny.en", "base.en", "small.en"])
  assert.deepStrictEqual(rows.map((r) => r.name), ["Fast", "Balanced", "Accurate"])
  assert.deepStrictEqual(rows.map((r) => r.chosen), [true, false, false])
  assert.deepStrictEqual(rows.map((r) => r.downloaded), [true, true, false])
  assert.strictEqual(rows[2].line, "small · 466 MB · download")
  assert.strictEqual(M.modelFile("small.en"), "ggml-small.en.bin")
})

test("models: Voxtype's own download and switch, nothing interpolated", () => {
  assert.deepStrictEqual(M.downloadArgv("small.en"),
    ["voxtype", "setup", "--download", "--model", "small.en", "--no-post-install", "--progress-format", "json"])
  const sw = M.switchArgv("small.en; rm -rf ~")
  assert.strictEqual(sw[0], "sh")
  assert.ok(sw[2].includes('voxtype config set whisper.model "$1"'))
  assert.ok(sw[2].includes("systemctl --user try-restart voxtype.service"))
  assert.strictEqual(sw[4], "small.en; rm -rf ~")
  assert.ok(!sw[2].includes("small.en"))
})

test("download progress lines", () => {
  assert.deepStrictEqual(M.parseProgress('{"percent": 41.6}'), { percent: 42, text: "42%" })
  assert.deepStrictEqual(M.parseProgress('{"progress": 0.5}'), { percent: 50, text: "50%" })
  assert.deepStrictEqual(M.parseProgress('{"downloaded": 25, "total": 100}'), { percent: 25, text: "25%" })
  assert.deepStrictEqual(M.parseProgress('{"bytes": 10485760}'), { percent: -1, text: "10 MB" })
  assert.strictEqual(M.parseProgress('{"event": "done"}'), null)
  assert.strictEqual(M.parseProgress("Downloading..."), null)
})

test("haptic ticks: listening starting and ending, the shell's recordings only", () => {
  assert.strictEqual(M.ticks("starting", "listening", "type"), true)
  assert.strictEqual(M.ticks("listening", "transcribing", "agent"), true)
  assert.strictEqual(M.ticks("listening", "idle", "ask"), true)
  assert.strictEqual(M.ticks("listening", "listening", "ask"), false)
  assert.strictEqual(M.ticks("transcribing", "idle", "type"), false)
  assert.strictEqual(M.ticks("idle", "listening", ""), false, "not a recording someone else started")
  assert.ok(M.HAPTIC_ARGV[2].includes("fbcli -E button-pressed"), "feedbackd: the user's profile decides")
  assert.ok(M.HAPTIC_ARGV[2].startsWith("command -v fbcli"))
})

test("Power + Volume Up: the agent sheet on the home screen, typing over an app", () => {
  assert.strictEqual(M.keyTarget(false), "ask")
  assert.strictEqual(M.keyTarget(true), "type")
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
