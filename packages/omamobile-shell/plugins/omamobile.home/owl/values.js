.pragma library
// SPDX-License-Identifier: MIT
// OWL values for Omamobile's own OWL runtime (docs/WIDGET-INTEROP-PLAN.md).
//
// A value is null, a number, a string, a boolean, a list (JS array), a map
// (JS Map, which keeps keys in the order they came, "10" before "2" too), or
// one of the three classes below. Everything here is plain JS with no QML,
// so node runs it in the tests (tests/owl/load.js).
//
// How values print, compare and convert follows the language guide and the
// decisions in owl/SPEC-NOTES.md (N1-N9), which record what the reference
// implementation does where the guide is silent.

// A colour. `name` is the theme name it came from ("accent"), or null for a
// literal; the host resolves names when it draws. `alpha` multiplies the
// colour's own alpha (alpha(accent, 0.5) keeps the name: SPEC-NOTES N4).
function Color(name, argb, alpha) {
  this.name = name
  this.argb = argb >>> 0
  this.alpha = alpha === undefined ? 1 : alpha
}

// A gradient for Canvas fills: linear (x0, y0, x1, y1) or radial (cx, cy, r).
function Gradient(radial, coords, colors) {
  this.radial = radial
  this.coords = coords
  this.colors = colors
}

// An arrow function value. `invoke(args)` runs it.
function Lambda(arity, invoke) {
  this.arity = arity
  this.invoke = invoke
}

// What a theme name stands for until a host resolves it (SPEC-NOTES N4).
var UNRESOLVED = 0xFF888888

// An error in the widget while it runs: the value shows "…" and the message
// goes to .errors/.
function RuntimeError(message) {
  this.message = message
}
RuntimeError.prototype.toString = function() { return this.message }

function isMap(v) { return v instanceof Map }
function isList(v) { return Array.isArray(v) }

function truthy(v) {
  if (v === null || v === undefined || v === false) return false
  if (typeof v === "number") return v === v && v !== 0
  if (typeof v === "string") return v !== ""
  if (Array.isArray(v)) return v.length > 0
  if (v instanceof Map) return v.size > 0
  return true
}

// ------------------------------------------------------------------ numbers

// Numeric text: "81", " 4.5 ", "81%", "1e3", "2.5f" (SPEC-NOTES N1).
var NUMERIC = /^[+-]?(?:NaN|Infinity|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)[fFdD]?$/

function toNumber(v) {
  switch (typeof v) {
  case "number": return v
  case "boolean": return v ? 1 : 0
  case "string": {
    var s = v.trim()
    if (s.length && s.charAt(s.length - 1) === "%") s = s.slice(0, -1).trim()
    if (!NUMERIC.test(s)) return null
    return parseFloat(s.replace(/[fFdD]$/, ""))
  }
  default: return null
  }
}

// Kotlin's Double.toInt: towards zero, NaN as 0, clamped to 32 bits.
function toInt32(x) {
  if (x !== x) return 0
  if (x >= 2147483647) return 2147483647
  if (x <= -2147483648) return -2147483648
  return Math.trunc(x)
}

function truncate(x) { return x !== x ? 0 : Math.trunc(x) }

// How a number prints (SPEC-NOTES N2): whole numbers below 10^15 as
// integers, others as Java's Double.toString does (0.5, 1.0E-4, 1.5E7).
function numberText(x) {
  if (x !== x) return "NaN"
  if (x === Infinity) return "Infinity"
  if (x === -Infinity) return "-Infinity"
  var a = Math.abs(x)
  if (Math.floor(x) === x && a < 1e15) return x === 0 ? "0" : String(x)
  if (a >= 1e-3 && a < 1e7) {
    var plain = String(x)
    return /[.e]/.test(plain) ? plain : plain + ".0"
  }
  return scientific(x.toExponential())
}

// "1.5e+7" -> "1.5E7", "1e-4" -> "1.0E-4"
function scientific(js) {
  var at = js.indexOf("e")
  var mantissa = js.slice(0, at)
  var exponent = js.slice(at + 1)
  if (mantissa.indexOf(".") < 0) mantissa += ".0"
  if (exponent.charAt(0) === "+") exponent = exponent.slice(1)
  return mantissa + "E" + exponent
}

// Java's Float.toString, for gradient coordinates as they print: the
// shortest decimal that reads back as the same 32-bit float.
function floatText(x) {
  var f = Math.fround(x)
  if (f !== f || !isFinite(f)) return numberText(f)
  if (f === 0) return 1 / f < 0 ? "-0.0" : "0.0"
  var digits = null
  for (var p = 1; p <= 9; p++) {
    var candidate = f.toPrecision(p)
    if (Math.fround(parseFloat(candidate)) === f) { digits = candidate; break }
  }
  if (digits === null) digits = f.toPrecision(9)
  var n = parseFloat(digits)
  var a = Math.abs(n)
  if (a >= 1e-3 && a < 1e7) {
    var s = decimalDigits(a)
    if (s.indexOf(".") < 0) s += ".0"
    return (n < 0 ? "-" : "") + s
  }
  return scientific(n.toExponential())
}

// A non-negative number's shortest decimal form, never with an exponent.
function decimalDigits(x) {
  var s = String(x)
  var e = s.indexOf("e")
  if (e < 0) return s
  var mantissa = s.slice(0, e)
  var exp = parseInt(s.slice(e + 1), 10)
  var dot = mantissa.indexOf(".")
  var digits = mantissa.replace(".", "")
  var point = (dot < 0 ? mantissa.length : dot) + exp
  if (point <= 0) return "0." + new Array(-point + 1).join("0") + digits
  while (digits.length < point) digits += "0"
  return point < digits.length ? digits.slice(0, point) + "." + digits.slice(point) : digits
}

// fixed(x, n): n decimals, rounding the shortest decimal form half up as
// Java's String.format does (1.005 -> "1.01"; SPEC-NOTES N3).
function fixedText(x, places) {
  if (x !== x) return "NaN"
  if (!isFinite(x)) return x > 0 ? "Infinity" : "-Infinity"
  var n = Math.max(0, Math.min(10, places))
  var negative = x < 0 || (x === 0 && 1 / x < 0)
  var s = decimalDigits(Math.abs(x))
  var dot = s.indexOf(".")
  var whole = dot < 0 ? s : s.slice(0, dot)
  var frac = dot < 0 ? "" : s.slice(dot + 1)
  while (frac.length <= n) frac += "0"
  var kept = (whole + frac.slice(0, n)).split("").map(Number)
  if (frac.charCodeAt(n) >= 53) {           // "5"
    var i = kept.length - 1
    for (; i >= 0 && kept[i] === 9; i--) kept[i] = 0
    if (i < 0) kept.unshift(1)
    else kept[i]++
  }
  var all = kept.join("")
  var intPart = all.slice(0, all.length - n) || "0"
  return (negative ? "-" : "") + intPart + (n > 0 ? "." + all.slice(all.length - n) : "")
}

// ------------------------------------------------------------------ colours

function hex8(argb) {
  var s = (argb >>> 0).toString(16)
  return "#" + "00000000".slice(s.length) + s
}

// "#rgb", "#rrggbb" or "#rrggbbaa" (CSS order, alpha last) -> ARGB, or null.
function parseHex(text) {
  var h = String(text).charAt(0) === "#" ? String(text).slice(1) : String(text)
  if (!/^[0-9a-fA-F]+$/.test(h)) return null
  var rgba
  if (h.length === 3) rgba = h.charAt(0) + h.charAt(0) + h.charAt(1) + h.charAt(1) + h.charAt(2) + h.charAt(2) + "ff"
  else if (h.length === 6) rgba = h + "ff"
  else if (h.length === 8) rgba = h
  else return null
  var rgb = parseInt(rgba.slice(0, 6), 16)
  var a = parseInt(rgba.slice(6), 16)
  return ((a << 24) | rgb) >>> 0
}

// The ARGB with an alpha factor applied (truncating, as 32-bit floats do).
function applyAlpha(argb, factor) {
  if (factor >= 1) return argb >>> 0
  var a = Math.floor(((argb >>> 24) & 0xff) * Math.fround(factor))
  return ((a << 24) | (argb & 0xffffff)) >>> 0
}

function mixArgb(x, y, t) {
  var out = 0
  for (var shift = 24; shift >= 0; shift -= 8) {
    var c = Math.floor(((x >>> shift) & 0xff) * (1 - t) + ((y >>> shift) & 0xff) * t + 0.5)
    out = (out | (c << shift)) >>> 0
  }
  return out >>> 0
}

// ------------------------------------------------------------------ printing

// How a value prints inside other text and in the conformance walk
// (SPEC-NOTES N2): null as "null", lists and maps with their items.
function display(v) {
  if (v === null || v === undefined) return "null"
  switch (typeof v) {
  case "number": return numberText(v)
  case "string": return v
  case "boolean": return v ? "true" : "false"
  }
  if (Array.isArray(v)) return "[" + v.map(display).join(", ") + "]"
  if (v instanceof Map) {
    var parts = []
    v.forEach(function(value, key) { parts.push(key + ": " + display(value)) })
    return "{" + parts.join(", ") + "}"
  }
  if (v instanceof Color) return v.name !== null ? v.name : hex8(v.argb)
  if (v instanceof Gradient)
    return "Gradient(radial=" + v.radial + ", coords=[" + v.coords.map(floatText).join(", ")
      + "], colors=[" + v.colors.map(display).join(", ") + "])"
  if (v instanceof Lambda) return "<fn>"
  return String(v)
}

// How a value reads on a tile: null is "…" (not loaded yet), and text loses
// trailing whitespace and leading line breaks (command output).
function textOf(v) {
  if (v === null || v === undefined) return "…"
  if (typeof v === "string") return v.replace(/\s+$/, "").replace(/^[\r\n]+/, "")
  return display(v)
}

// ------------------------------------------------------------------ comparing

function same(a, b) {
  if (a === b) return typeof a !== "number" || a === a
  if (typeof a === "number" && typeof b === "number") return a !== a && b !== b
  if (a === null || b === null || a === undefined || b === undefined) return false
  if (Array.isArray(a)) {
    if (!Array.isArray(b) || a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) if (!same(a[i], b[i])) return false
    return true
  }
  if (a instanceof Map) {
    if (!(b instanceof Map) || a.size !== b.size) return false
    var it = a.entries()
    for (var e = it.next(); !e.done; e = it.next()) {
      if (!b.has(e.value[0]) || !same(e.value[1], b.get(e.value[0]))) return false
    }
    return true
  }
  if (a instanceof Color)
    return b instanceof Color && a.name === b.name && a.argb === b.argb && Math.fround(a.alpha) === Math.fround(b.alpha)
  if (a instanceof Gradient)
    return b instanceof Gradient && a.radial === b.radial && same(a.coords, b.coords) && same(a.colors, b.colors)
  return false
}

// `==`: the same value, or a number and the text of that number.
function equalish(a, b) {
  if (same(a, b)) return true
  var mixed = (typeof a === "number" && typeof b === "string") || (typeof a === "string" && typeof b === "number")
  if (!mixed) return false
  var x = toNumber(a), y = toNumber(b)
  return x !== null && y !== null && x === y
}

// Sorting order: numbers (and numeric text) by value, anything else by its text.
function order(a, b) {
  var x = toNumber(a), y = toNumber(b)
  if (x !== null && y !== null) return x < y ? -1 : x > y ? 1 : 0
  var s = display(a), t = display(b)
  return s < t ? -1 : s > t ? 1 : 0
}

// ------------------------------------------------------------------ JSON

// JSON text to values. Objects become Maps in file order, which JSON.parse
// can't give ("10" would come before "2"), so this reads the text itself.
function parseJson(input) {
  var s = String(input)
  var at = 0
  function bad(why) { throw new RuntimeError("bad JSON: " + why) }
  function space() {
    while (at < s.length) {
      var c = s.charCodeAt(at)
      if (c === 32 || c === 9 || c === 10 || c === 13 || c === 12 || c === 11 || c === 0xa0 || c === 0xfeff) at++
      else break
    }
  }
  function str() {
    var out = ""
    at++
    while (at < s.length) {
      var c = s.charAt(at)
      if (c === "\"") { at++; return out }
      if (c === "\\") {
        var e = s.charAt(at + 1)
        if (e === "u") { out += String.fromCharCode(parseInt(s.substr(at + 2, 4), 16)); at += 6; continue }
        out += e === "n" ? "\n" : e === "t" ? "\t" : e === "r" ? "\r" : e === "b" ? "\b" : e === "f" ? "\f" : e
        at += 2
        continue
      }
      out += c
      at++
    }
    bad("unterminated string")
  }
  function value() {
    space()
    var c = s.charAt(at)
    if (c === "{") {
      at++
      var m = new Map()
      space()
      if (s.charAt(at) === "}") { at++; return m }
      for (;;) {
        space()
        if (s.charAt(at) !== "\"") bad("expected a key")
        var key = str()
        space()
        if (s.charAt(at) !== ":") bad("expected ':'")
        at++
        m.set(key, value())
        space()
        if (s.charAt(at) === ",") { at++; continue }
        if (s.charAt(at) === "}") { at++; return m }
        bad("expected ',' or '}'")
      }
    }
    if (c === "[") {
      at++
      var list = []
      space()
      if (s.charAt(at) === "]") { at++; return list }
      for (;;) {
        list.push(value())
        space()
        if (s.charAt(at) === ",") { at++; continue }
        if (s.charAt(at) === "]") { at++; return list }
        bad("expected ',' or ']'")
      }
    }
    if (c === "\"") return str()
    if (s.startsWith("true", at)) { at += 4; return true }
    if (s.startsWith("false", at)) { at += 5; return false }
    if (s.startsWith("null", at)) { at += 4; return null }
    var m2 = /^-?(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?/.exec(s.slice(at, at + 64))
    if (!m2) bad("unexpected '" + c + "'")
    at += m2[0].length
    return parseFloat(m2[0])
  }
  var result = value()
  space()
  if (at < s.length) bad("trailing text")
  return result
}

// Plain JS data (from JSON.parse, a fixture, persisted state) to values.
function fromPlain(j) {
  if (j === null || j === undefined) return null
  if (Array.isArray(j)) return j.map(fromPlain)
  if (typeof j === "object") {
    var m = new Map()
    Object.keys(j).forEach(function(k) { m.set(k, fromPlain(j[k])) })
    return m
  }
  return j
}

// Values to plain JS data, for persisted state (colours become their text).
function toPlain(v) {
  if (v === null || v === undefined) return null
  if (Array.isArray(v)) return v.map(toPlain)
  if (v instanceof Map) {
    var o = {}
    v.forEach(function(value, key) { o[key] = toPlain(value) })
    return o
  }
  if (typeof v === "number") return isFinite(v) ? v : null
  if (typeof v === "string" || typeof v === "boolean") return v
  return display(v)
}

// A value as a list: a map's values, or a single value in a list of one.
function listOf(v) {
  if (Array.isArray(v)) return v
  if (v instanceof Map) return Array.from(v.values())
  return v === null || v === undefined ? [] : [v]
}

if (typeof module !== "undefined") {
  module.exports = {
    Color: Color, Gradient: Gradient, Lambda: Lambda, RuntimeError: RuntimeError, UNRESOLVED: UNRESOLVED,
    isMap: isMap, isList: isList, truthy: truthy, toNumber: toNumber, toInt32: toInt32, truncate: truncate,
    numberText: numberText, floatText: floatText, decimalDigits: decimalDigits, fixedText: fixedText,
    hex8: hex8, parseHex: parseHex, applyAlpha: applyAlpha, mixArgb: mixArgb,
    display: display, textOf: textOf, same: same, equalish: equalish, order: order,
    parseJson: parseJson, fromPlain: fromPlain, toPlain: toPlain, listOf: listOf
  }
}
