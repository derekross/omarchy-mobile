// SPDX-License-Identifier: MIT
// Node tests for plugins/omamobile.access/AccessModel.js. Run by test/all.
"use strict"
const assert = require("assert")
const path = require("path")
const M = require(path.join(__dirname, "../plugins/omamobile.access/AccessModel.js"))

const good = JSON.stringify({ id: "ab12cd34ef56ab78", appName: "Camera", title: "Allow Camera to use the camera?", body: "", grantLabel: "" })
const r = M.parseRequest(good)
assert.strictEqual(r.appName, "Camera")
assert.strictEqual(r.grantLabel, "Allow", "an empty label falls back")
assert.strictEqual(r.denyLabel, "Don't allow")
assert.strictEqual(M.parseRequest("not json"), null)
assert.strictEqual(M.parseRequest(JSON.stringify({ id: "x y; rm" })), null, "ids are hex tokens only")
assert.strictEqual(M.parseRequest(JSON.stringify({ title: "no id" })), null)

let q = M.enqueue([], r)
q = M.enqueue(q, r)
assert.strictEqual(q.length, 1, "a repeated id is queued once")
const r2 = M.parseRequest(JSON.stringify({ id: "00112233aabbccdd" }))
q = M.enqueue(q, r2)
assert.deepStrictEqual(q.map((x) => x.id), ["ab12cd34ef56ab78", "00112233aabbccdd"], "first come, first shown")
assert.strictEqual(M.enqueue(q, null), q)
q = M.remove(q, M.idOf('{"id": "ab12cd34ef56ab78"}'))
assert.deepStrictEqual(q.map((x) => x.id), ["00112233aabbccdd"])
assert.strictEqual(M.idOf("00112233aabbccdd"), "00112233aabbccdd")

assert.deepStrictEqual(M.answerArgv("ab12", true), ["busctl", "--user", "call", "org.freedesktop.impl.portal.desktop.omamobile",
  "/org/omamobile/AccessSheet", "org.omamobile.AccessSheet", "Answer", "ss", "ab12", "allow"])
assert.strictEqual(M.answerArgv("ab12", false).slice(-1)[0], "deny")
// Back: the request ends unanswered (nothing is stored), never as "deny".
assert.deepStrictEqual(M.dismissArgv("ab12"), M.answerArgv("ab12", true).slice(0, -1).concat(["dismiss"]))
assert.strictEqual(M.initial(" camera"), "C")
assert.strictEqual(M.initial(""), "?")
console.log("ok - access model")
