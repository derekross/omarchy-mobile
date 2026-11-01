// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.voice/VoiceModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.voice/VoiceModel.js"))
const L = require(path.join(__dirname, "../plugins/omamobile.launcher/LauncherModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])

test("every start passes --no-osd: typing, the agent's file, either model", () => {
  for (const mode of ["type", "file"]) {
    for (const fast of [false, true]) {
      const argv = M.startArgv(mode, "/run/user/1000/omamobile-voice.txt", fast)
      assert.deepStrictEqual(argv.slice(0, 4), ["voxtype", "record", "start", "--no-osd"])
      assert.strictEqual(argv.includes("--model"), fast)
      if (fast) assert.strictEqual(argv[argv.indexOf("--model") + 1], "tiny.en")
    }
  }
  assert.deepStrictEqual(M.startArgv("type", "", false), ["voxtype", "record", "start", "--no-osd", "--type"])
  assert.deepStrictEqual(M.startArgv("file", "/r/omamobile-voice.txt", true),
    ["voxtype", "record", "start", "--no-osd", "--file=/r/omamobile-voice.txt", "--model", "tiny.en"])
})

test("the agent's recording removes the old transcript first, in one process, nothing interpolated", () => {
  const p = "/run/user/1000/it's \"odd\"; rm -rf ~/omamobile-voice.txt"
  const argv = M.fileStartArgv(p, false)
  assert.deepStrictEqual(argv.slice(0, 3), ["sh", "-c", 'rm -f -- "$1"; shift; exec "$@"'])
  assert.strictEqual(argv[3], "sh")
  assert.strictEqual(argv[4], p)
  assert.deepStrictEqual(argv.slice(5), M.startArgv("file", p, false))
  assert.ok(!argv[2].includes(p))
})

test("stop, cancel and the transcript's path", () => {
  assert.deepStrictEqual(M.STOP_ARGV, ["voxtype", "record", "stop"])
  assert.deepStrictEqual(M.CANCEL_ARGV, ["voxtype", "record", "cancel"])
  assert.strictEqual(M.transcriptPath("/run/user/1000"), "/run/user/1000/omamobile-voice.txt")
  assert.strictEqual(M.fastModelPath("/home/u"), "/home/u/.local/share/voxtype/models/ggml-tiny.en.bin")
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
