// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.quicksettings/MediaModel.js, the shade's
// media card. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.quicksettings/MediaModel.js"))

const tests = []
const test = (name, fn) => tests.push([name, fn])

const player = (o) => Object.assign({
  identity: "Music", desktopEntry: "org.example.Music", dbusName: "org.mpris.MediaPlayer2.music",
  trackTitle: "Song", trackArtist: "Band", trackArtUrl: "", isPlaying: true, playbackState: M.PLAYING,
  positionSupported: true, lengthSupported: true, position: 10, length: 200
}, o)

test("no players, or none with something to show, is no card", () => {
  assert.strictEqual(M.pick([], {}), null)
  assert.strictEqual(M.pick(null, {}), null)
  assert.strictEqual(M.pick([player({ trackTitle: "" })], {}), null, "no title")
  assert.strictEqual(M.pick([player({ isPlaying: false, playbackState: 0 })], {}), null, "stopped")
})

test("a paused player shows", () => {
  const p = player({ isPlaying: false, playbackState: M.PAUSED })
  assert.strictEqual(M.pick([p], {}), p)
})

test("playing wins over paused, whatever the order", () => {
  const paused = player({ dbusName: "a", isPlaying: false, playbackState: M.PAUSED })
  const playing = player({ dbusName: "b" })
  assert.strictEqual(M.pick([paused, playing], { a: 9, b: 1 }), playing)
})

test("among several playing or several paused, the most recent", () => {
  const a = player({ dbusName: "a" }), b = player({ dbusName: "b" })
  assert.strictEqual(M.pick([a, b], { a: 1, b: 2 }), b)
  assert.strictEqual(M.pick([a, b], { a: 3, b: 2 }), a)
  const c = player({ dbusName: "c", isPlaying: false, playbackState: M.PAUSED })
  const d = player({ dbusName: "d", isPlaying: false, playbackState: M.PAUSED })
  assert.strictEqual(M.pick([c, d], { c: 5 }), c, "a player never seen counts as oldest")
})

test("playerctld only when it is the only one", () => {
  const proxy = player({ dbusName: "org.mpris.MediaPlayer2.playerctld" })
  const real = player({ dbusName: "x", isPlaying: false, playbackState: M.PAUSED })
  assert.strictEqual(M.pick([proxy, real], { "org.mpris.MediaPlayer2.playerctld": 9 }), real)
  assert.strictEqual(M.pick([proxy], {}), proxy)
})

test("the app's name: identity, desktop entry, then the bus name", () => {
  assert.strictEqual(M.appName(player({})), "Music")
  assert.strictEqual(M.appName(player({ identity: "" })), "org.example.Music")
  assert.strictEqual(M.appName(player({ identity: "", desktopEntry: "", dbusName: "org.mpris.MediaPlayer2.chromium.instance4242" })), "chromium")
  assert.strictEqual(M.appName(null), "")
})

test("the artist, or the list of artists", () => {
  assert.strictEqual(M.artist(player({})), "Band")
  assert.strictEqual(M.artist(player({ trackArtist: "", trackArtists: ["A", "", "B"] })), "A, B")
})

test("art: local always, the network only where allowed, nothing else", () => {
  assert.strictEqual(M.artSource("file:///tmp/a.png", false), "file:///tmp/a.png")
  assert.strictEqual(M.artSource("/tmp/my art.png", false), "file:///tmp/my%20art.png")
  assert.strictEqual(M.artSource("data:image/png;base64,AAAA", false), "data:image/png;base64,AAAA")
  assert.strictEqual(M.artSource("https://i.example/cover.jpg", true), "https://i.example/cover.jpg")
  assert.strictEqual(M.artSource("https://i.example/cover.jpg", false), "", "the lock never fetches")
  assert.strictEqual(M.artSource("http://i.example/cover.jpg", false), "")
  for (const u of ["qrc:/x.png", "image://icon/x", "ftp://h/x.png", "javascript:1", "", null, undefined])
    assert.strictEqual(M.artSource(u, true), "", String(u))
})

test("a timeline only with a position and a length", () => {
  assert.strictEqual(M.hasTimeline(player({})), true)
  assert.strictEqual(M.hasTimeline(player({ positionSupported: false })), false)
  assert.strictEqual(M.hasTimeline(player({ length: 0 })), false)
  assert.strictEqual(M.hasTimeline(player({ length: Infinity })), false)
  assert.strictEqual(M.fraction(50, 200), 0.25)
  assert.strictEqual(M.fraction(500, 200), 1)
  assert.strictEqual(M.fraction(5, 0), 0)
})

test("times read m:ss, then h:mm:ss", () => {
  assert.strictEqual(M.timeText(0), "0:00")
  assert.strictEqual(M.timeText(83.7), "1:23")
  assert.strictEqual(M.timeText(3725), "1:02:05")
  assert.strictEqual(M.timeText(-3), "0:00")
  assert.strictEqual(M.timeText(NaN), "0:00")
})

test("names for a screen reader", () => {
  assert.strictEqual(M.accessibleName(player({})), "Playing: Song, Band, Music")
  assert.strictEqual(M.accessibleName(player({ isPlaying: false, playbackState: M.PAUSED, trackArtist: "" })), "Paused: Song, Music")
  assert.strictEqual(M.playPauseName(player({})), "Pause")
  assert.strictEqual(M.playPauseName(player({ isPlaying: false, playbackState: M.PAUSED })), "Play")
})

test("the names a tap focuses, taken literally", () => {
  assert.deepStrictEqual(M.focusNames(player({})), ["org\\.example\\.Music", "Music"])
  assert.deepStrictEqual(M.focusNames(player({ desktopEntry: "firefox", identity: "Firefox" })), ["firefox"])
  assert.deepStrictEqual(M.focusNames(player({ desktopEntry: "", identity: "mpv (a+b)" })), ["mpv \\(a\\+b\\)"])
  assert.deepStrictEqual(M.focusNames(null), [])
})

let failed = 0
for (const [name, fn] of tests) {
  try { fn(); console.log("ok - " + name) } catch (e) { failed++; console.log("not ok - " + name + "\n  " + e.message) }
}
process.exit(failed ? 1 : 0)
