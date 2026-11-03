.pragma library
.import "values.js" as V
// SPDX-License-Identifier: MIT
// OWL's functions. Each entry is { min, max, pure, run(a) } where `a` reads
// the evaluated arguments (ArgReader below). `pure` functions with constant
// arguments are folded at compile time. What each function does with null,
// text and odd input follows the guide and SPEC-NOTES N10-N16.

var MAX_LIST = 1000

function ArgReader(values, ctx) {
  this.values = values
  this.ctx = ctx
  this.count = values.length
}

ArgReader.prototype = {
  at: function(i) {
    var v = i < this.values.length ? this.values[i] : null
    return v === undefined ? null : v
  },
  // A number; 0 when it isn't one (or `fallback` when given, also for a
  // missing argument).
  number: function(i, fallback) {
    if (fallback === undefined) {
      var n = V.toNumber(this.at(i))
      return n === null ? 0 : n
    }
    if (i >= this.values.length) return fallback
    var m = V.toNumber(this.at(i))
    return m === null ? fallback : m
  },
  integer: function(i, fallback) {
    if (i >= this.values.length) return fallback
    var n = V.toNumber(this.at(i))
    return n === null ? fallback : V.toInt32(n)
  },
  text: function(i) {
    var v = this.at(i)
    return v === null ? "" : V.display(v)
  },
  list: function(i) { return V.listOf(this.at(i)) },
  lambda: function(i) {
    var f = this.at(i)
    if (!(f instanceof V.Lambda)) throw new V.RuntimeError("argument " + (i + 1) + " must be a function like x => x.name")
    return f
  },
  spend: function(steps) { if (this.ctx && this.ctx.spend) this.ctx.spend(steps) }
}

function capped(list) { return list.length > MAX_LIST ? list.slice(0, MAX_LIST) : list }
function between(x, lo, hi) {
  var top = hi < lo ? lo : hi
  return x < lo ? lo : x > top ? top : x
}
function call(f, args) { return f.invoke(args) }

// null in, null out: the guide's "math and formatting pass null through".
function nullSafe(run) { return function(a) { return a.at(0) === null ? null : run(a) } }

function fn(min, max, run, pure) { return { min: min, max: max, run: run, pure: pure !== false } }
function unaryMath(f) { return fn(1, 1, nullSafe(function(a) { return f(a.number(0)) })) }

function stableSort(items, cmp) {
  return items.map(function(v, i) { return { v: v, i: i } })
    .sort(function(p, q) { return cmp(p.v, q.v) || p.i - q.i })
    .map(function(p) { return p.v })
}

function indexIn(list, v) {
  for (var i = 0; i < list.length; i++) if (V.same(list[i], v)) return i
  return -1
}

// ---------------------------------------------------------------- time

// The first day of the week (0 Sunday, 1 Monday) for `e`/`c` day numbers.
// Monday on the phone, as the store's calendar widget is drawn for it; the
// conformance walk sets Sunday, as the reference oracle runs in en_US.
var firstDayOfWeek = 1
function setFirstDayOfWeek(day) { firstDayOfWeek = day }

var DAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
var MONTH_NAMES = ["January", "February", "March", "April", "May", "June", "July", "August",
                   "September", "October", "November", "December"]

function zeros(n, width) {
  var s = String(n)
  while (s.length < width) s = "0" + s
  return s
}

// java.time pattern letters, in local time and English (SPEC-NOTES N12).
function formatTime(seconds, pattern) {
  var d = new Date(Math.floor(seconds * 1000))
  var out = ""
  for (var i = 0; i < pattern.length;) {
    var c = pattern.charAt(i)
    if (c === "'") {
      var close = pattern.indexOf("'", i + 1)
      if (close < 0) throw new V.RuntimeError("bad time pattern")
      out += close === i + 1 ? "'" : pattern.slice(i + 1, close)
      i = close + 1
      continue
    }
    if (!/[A-Za-z]/.test(c)) { out += c; i++; continue }
    var n = 1
    while (pattern.charAt(i + n) === c) n++
    i += n
    out += timeField(d, c, n)
  }
  return out
}

function timeField(d, letter, n) {
  var hour = d.getHours()
  var day = d.getDay()
  switch (letter) {
  case "y": case "u": return n === 2 ? zeros(d.getFullYear() % 100, 2) : zeros(d.getFullYear(), n)
  case "M": case "L":
    if (n >= 4) return MONTH_NAMES[d.getMonth()]
    if (n === 3) return MONTH_NAMES[d.getMonth()].slice(0, 3)
    return zeros(d.getMonth() + 1, n)
  case "d": return zeros(d.getDate(), n)
  case "E":
    if (n === 5) return DAY_NAMES[day].charAt(0)
    return n === 4 ? DAY_NAMES[day] : DAY_NAMES[day].slice(0, 3)
  case "e": case "c":
    if (n >= 4) return DAY_NAMES[day]
    if (n === 3) return DAY_NAMES[day].slice(0, 3)
    return String((day - firstDayOfWeek + 7) % 7 + 1)
  case "H": return zeros(hour, n)
  case "k": return zeros(hour === 0 ? 24 : hour, n)
  case "h": return zeros(hour % 12 === 0 ? 12 : hour % 12, n)
  case "K": return zeros(hour % 12, n)
  case "m": return zeros(d.getMinutes(), n)
  case "s": return zeros(d.getSeconds(), n)
  case "S": return zeros(d.getMilliseconds(), 3).slice(0, n)
  case "a": return hour < 12 ? "AM" : "PM"
  case "D": {
    var jan1 = new Date(d.getFullYear(), 0, 1)
    var midnight = new Date(d.getFullYear(), d.getMonth(), d.getDate())
    return zeros(Math.round((midnight - jan1) / 86400000) + 1, n)
  }
  case "Q": case "q": return String(Math.floor(d.getMonth() / 3) + 1)
  case "Z": case "x": case "X": {
    var offset = -d.getTimezoneOffset()
    var sign = offset < 0 ? "-" : "+"
    offset = Math.abs(offset)
    var colon = letter === "Z" ? (n >= 4 ? ":" : "") : (n >= 3 ? ":" : "")
    return sign + zeros(Math.floor(offset / 60), 2) + colon + zeros(offset % 60, 2)
  }
  }
  throw new V.RuntimeError("bad time pattern")
}

// Omarchy's weather glyphs (Nerd Font) for World Weather Online's weatherCode
// (the codes wttr.in served; our Open-Meteo copies map WMO codes onto them).
function weatherGlyph(code, night) {
  var groups = [
    [[113], "", ""],
    [[116], "", ""],
    [[143, 248, 260], "", ""],
    [[176, 263, 353], "", ""],
    [[179, 227, 230, 323, 326, 368], "", ""],
    [[182, 185, 281, 284, 311, 314, 317, 320, 350, 362, 365, 374, 377], "", ""],
    [[200, 386, 389, 392, 395], "", ""],
    [[266, 293, 296, 299, 302, 305, 308, 356, 359], "", ""],
    [[329, 332, 335, 338, 371], "", ""]
  ]
  for (var i = 0; i < groups.length; i++)
    if (groups[i][0].indexOf(code) >= 0) return night ? groups[i][2] : groups[i][1]
  return ""
}

// ---------------------------------------------------------------- colours

// The names a colour can be given by, as the guide lists them.
var THEME_NAMES = ["accent", "background", "foreground", "muted", "surface", "border", "red", "green", "yellow",
  "blue", "magenta", "cyan", "orange", "purple", "brown", "white", "black", "bright_red", "bright_green",
  "bright_yellow", "bright_blue", "bright_magenta", "bright_cyan", "bright_foreground", "dark_foreground",
  "lighter_background", "dark_background", "selection", "cursor"]
for (var c16 = 0; c16 < 16; c16++) THEME_NAMES.push("color" + c16)

// A value as a colour, theme names unresolved; null when it isn't one.
function asColor(v) {
  if (v instanceof V.Color) return v
  if (typeof v !== "string") return null
  if (v.charAt(0) === "#") {
    var argb = V.parseHex(v)
    return argb === null ? null : new V.Color(null, argb, 1)
  }
  return THEME_NAMES.indexOf(v) >= 0 ? new V.Color(v, V.UNRESOLVED, 1) : null
}

// A value as ARGB with theme names resolved through `resolve(name)`.
function resolveArgb(v, resolve) {
  if (v instanceof V.Color) {
    var base = v.name !== null && resolve ? resolve(v.name) : null
    return V.applyAlpha(base === null || base === undefined ? v.argb : base, v.alpha)
  }
  if (typeof v === "string") {
    if (v.charAt(0) === "#") return V.parseHex(v)
    var named = resolve ? resolve(v) : null
    return named === undefined ? null : named
  }
  return null
}

function channel(x) { return Math.floor(between(x, 0, 255) + 0.5) }
function rgbColor(r, g, b, a) {
  return new V.Color(null, ((channel(a * 255) << 24) | (channel(r) << 16) | (channel(g) << 8) | channel(b)) >>> 0, 1)
}
function hslColor(h, s, l, a) {
  var sector6 = (((h % 360) + 360) % 360) / 60
  var chroma = (1 - Math.abs(2 * l - 1)) * s
  var second = chroma * (1 - Math.abs(sector6 % 2 - 1))
  var rgb = [[chroma, second, 0], [second, chroma, 0], [0, chroma, second], [0, second, chroma],
             [second, 0, chroma], [chroma, 0, second]][Math.min(V.toInt32(sector6), 5)]
  var m = l - chroma / 2
  return rgbColor((rgb[0] + m) * 255, (rgb[1] + m) * 255, (rgb[2] + m) * 255, a)
}

function gradientOf(radial, a, coordCount) {
  var colors = a.list(coordCount).map(asColor).filter(function(c) { return c !== null })
  if (colors.length < 2) throw new V.RuntimeError("a gradient needs at least two colors")
  var coords = []
  for (var i = 0; i < coordCount; i++) coords.push(Math.fround(a.number(i)))
  return new V.Gradient(radial, coords, colors)
}

// ---------------------------------------------------------------- text

var regexCache = {}
function regex(pattern) {
  if (!Object.prototype.hasOwnProperty.call(regexCache, pattern)) regexCache[pattern] = new RegExp(pattern)
  return regexCache[pattern]
}
function matchResult(m) {
  if (m.length < 2) return m[0]
  var groups = []
  for (var i = 1; i < m.length; i++) groups.push(m[i] === undefined ? "" : m[i])
  return groups
}
function splitText(s, sep) {
  if (sep !== "") return s.split(sep)
  return [""].concat(s.split(""), [""])
}
function memberOf(v, name) {
  if (v instanceof Map) {
    var f = v.get(name)
    return f === undefined ? null : f
  }
  if (Array.isArray(v)) {
    if (/^-?[0-9]+$/.test(name)) {
      var i = parseInt(name, 10)
      var item = v[i < 0 ? v.length + i : i]
      if (item !== undefined) return item
    }
    return name === "length" ? v.length : null
  }
  if (typeof v === "string") return name === "length" ? v.length : null
  return null
}

// sh(x): x as one single-quoted shell word.
function shellWord(v) {
  return "'" + (v === null ? "" : V.textOf(v)).split("'").join("'\\''") + "'"
}

function minOrMax(isMax) {
  return fn(1, 16, function(a) {
    var pick = isMax ? Math.max : Math.min
    if (a.count === 1) {
      var ns = a.list(0).map(V.toNumber).filter(function(n) { return n !== null })
      return ns.length ? ns.reduce(function(p, q) { return pick(p, q) }) : null
    }
    return a.values.map(function(v) {
      var n = V.toNumber(v)
      return n === null ? (isMax ? -Number.MAX_VALUE : Number.MAX_VALUE) : n
    }).reduce(function(p, q) { return pick(p, q) })
  })
}

function sumWith(a) {
  var f = a.count > 1 ? a.lambda(1) : null
  return a.list(0).reduce(function(total, v) {
    var n = V.toNumber(f ? call(f, [v]) : v)
    return total + (n === null ? 0 : n)
  }, 0)
}

var FUNCTIONS = {
  // numbers
  min: minOrMax(false),
  max: minOrMax(true),
  clamp: fn(3, 3, function(a) { return between(a.number(0), a.number(1), a.number(2)) }),
  lerp: fn(3, 3, function(a) { return a.number(0) + (a.number(1) - a.number(0)) * a.number(2) }),
  round: fn(1, 2, nullSafe(function(a) {
    var scale = Math.pow(10, a.integer(1, 0))
    return Math.floor(a.number(0) * scale + 0.5) / scale
  })),
  floor: unaryMath(Math.floor), ceil: unaryMath(Math.ceil), abs: unaryMath(Math.abs), sqrt: unaryMath(Math.sqrt),
  sin: unaryMath(Math.sin), cos: unaryMath(Math.cos), tan: unaryMath(Math.tan),
  rad: unaryMath(function(x) { return x / 180 * Math.PI }),
  deg: unaryMath(function(x) { return x * 180 / Math.PI }),
  sign: unaryMath(function(x) { return x !== x ? x : x > 0 ? 1 : x < 0 ? -1 : x }),
  pow: fn(2, 2, nullSafe(function(a) { return Math.pow(a.number(0), a.number(1)) })),
  atan2: fn(2, 2, function(a) { return Math.atan2(a.number(0), a.number(1)) }),
  num: fn(1, 2, function(a) {
    var n = V.toNumber(a.at(0))
    return n !== null ? n : a.count > 1 ? a.at(1) : null
  }),
  int: fn(1, 1, nullSafe(function(a) {
    var n = V.toNumber(a.at(0))
    return n === null ? null : V.truncate(n)
  })),

  // text
  str: fn(1, 1, function(a) { return a.text(0) }),
  len: fn(1, 1, function(a) {
    var v = a.at(0)
    if (Array.isArray(v) || typeof v === "string") return v.length
    return v instanceof Map ? v.size : 0
  }),
  trim: fn(1, 1, function(a) { return a.text(0).trim() }),
  upper: fn(1, 1, function(a) { return a.text(0).toUpperCase() }),
  lower: fn(1, 1, function(a) { return a.text(0).toLowerCase() }),
  lines: fn(1, 1, function(a) {
    return capped(a.text(0).split(/\r\n|\n|\r/).filter(function(l) { return l.trim() !== "" }))
  }),
  words: fn(1, 1, function(a) {
    return capped(a.text(0).trim().split(/\s+/).filter(function(w) { return w !== "" }))
  }),
  split: fn(2, 2, function(a) { return capped(splitText(a.text(0), a.text(1))) }),
  join: fn(1, 2, function(a) {
    var sep = a.count > 1 ? a.text(1) : ""
    return a.list(0).map(function(v) { return typeof v === "string" ? v : V.display(v) }).join(sep)
  }),
  replace: fn(3, 3, function(a) {
    var from = a.text(1)
    return splitText(a.text(0), from).join(a.text(2))
  }),
  sh: fn(1, 1, function(a) { return shellWord(a.at(0)) }),
  startsWith: fn(2, 2, function(a) { return a.text(0).indexOf(a.text(1)) === 0 }),
  endsWith: fn(2, 2, function(a) {
    var s = a.text(0), tail = a.text(1)
    return s.length >= tail.length && s.slice(s.length - tail.length) === tail
  }),
  contains: fn(2, 2, function(a) {
    var v = a.at(0)
    if (Array.isArray(v)) return indexIn(v, a.at(1)) >= 0
    if (v instanceof Map) return v.has(a.text(1))
    return a.text(0).indexOf(a.text(1)) >= 0
  }),
  sub: fn(2, 3, function(a) {
    var s = a.text(0)
    var f = a.integer(1, 0)
    var from = between(f < 0 ? s.length + f : f, 0, s.length)
    var t = a.integer(2, s.length)
    var to = between(t < 0 ? s.length + t : t, from, s.length)
    return s.slice(from, to)
  }),
  pad: fn(2, 3, nullSafe(function(a) {
    var s = a.text(0), width = a.integer(1, 0), filler = a.text(2)
    var c = filler.length ? filler.charAt(0) : " "
    var fill = new Array(Math.max(0, Math.abs(width) - s.length) + 1).join(c)
    return width >= 0 ? fill + s : s + fill
  })),
  fixed: fn(2, 2, nullSafe(function(a) { return V.fixedText(a.number(0), a.integer(1, 0)) })),

  // formatting
  fmtBytes: fn(1, 1, nullSafe(function(a) {
    var v = a.number(0)
    var units = ["B", "K", "M", "G", "T", "P"]
    var u = 0
    for (; Math.abs(v) >= 1024 && u < units.length - 1; u++) v /= 1024
    return u === 0 ? V.numberText(V.truncate(v)) + "B" : V.fixedText(v, v < 10 ? 1 : 0) + units[u]
  })),
  fmtDuration: fn(1, 1, nullSafe(function(a) {
    var s = Math.max(V.truncate(a.number(0)), 0)
    var days = Math.floor(s / 86400), hours = Math.floor(s % 86400 / 3600), minutes = Math.floor(s % 3600 / 60)
    if (days > 0) return days + "d " + hours + "h"
    if (hours > 0) return hours + "h " + minutes + "m"
    if (minutes > 0) return minutes + "m " + (s % 60) + "s"
    return s + "s"
  })),
  fmtTime: fn(2, 2, nullSafe(function(a) {
    try { return formatTime(a.number(0), a.text(1)) } catch (e) { throw new V.RuntimeError("bad time pattern '" + a.text(1) + "'") }
  })),
  weatherIcon: fn(1, 2, function(a) { return weatherGlyph(a.integer(0, 0), V.truthy(a.at(1))) }),

  // parsing
  match: fn(2, 2, function(a) {
    var m = regex(a.text(1)).exec(a.text(0))
    if (!m) return null
    return m.length > 1 ? capped(matchResult(m)) : m[0]
  }),
  matchAll: fn(2, 2, function(a) {
    var re = new RegExp(regex(a.text(1)).source, "g")
    var s = a.text(0)
    var out = []
    for (var m = re.exec(s); m !== null && out.length < MAX_LIST; m = re.exec(s)) {
      out.push(matchResult(m))
      if (m[0] === "") re.lastIndex++
    }
    return out
  }),
  parseJson: fn(1, 1, function(a) {
    var s = a.text(0)
    try { return V.parseJson(s.trim()) } catch (e) { return s }
  }),

  // lists
  range: fn(1, 3, function(a) {
    var from = a.count === 1 ? 0 : a.number(0)
    var to = a.count === 1 ? a.number(0) : a.number(1)
    var step = a.number(2, 1) || 1
    var out = []
    for (var x = from; ((step > 0 && x < to) || (step < 0 && x > to)) && out.length < MAX_LIST; x += step) out.push(x)
    return out
  }),
  map: fn(2, 2, function(a) {
    var f = a.lambda(1), list = a.list(0)
    a.spend(list.length)
    return capped(list.map(function(v, i) { return call(f, [v, i]) }))
  }),
  filter: fn(2, 2, function(a) {
    var f = a.lambda(1), list = a.list(0)
    a.spend(list.length)
    return capped(list.filter(function(v, i) { return V.truthy(call(f, [v, i])) }))
  }),
  find: fn(2, 2, function(a) {
    var f = a.lambda(1), list = a.list(0)
    for (var i = 0; i < list.length; i++) if (V.truthy(call(f, [list[i]]))) return list[i]
    return null
  }),
  any: fn(2, 2, function(a) {
    var f = a.lambda(1)
    return a.list(0).some(function(v) { return V.truthy(call(f, [v])) })
  }),
  all: fn(2, 2, function(a) {
    var f = a.lambda(1)
    return a.list(0).every(function(v) { return V.truthy(call(f, [v])) })
  }),
  count: fn(1, 2, function(a) {
    if (a.count < 2) return a.list(0).length
    var f = a.lambda(1)
    return a.list(0).filter(function(v) { return V.truthy(call(f, [v])) }).length
  }),
  sum: fn(1, 2, sumWith),
  avg: fn(1, 2, function(a) {
    var n = a.list(0).length
    return n ? sumWith(a) / n : null
  }),
  sort: fn(1, 1, function(a) { return capped(stableSort(a.list(0), V.order)) }),
  sortBy: fn(2, 2, function(a) {
    var f = a.lambda(1), list = a.list(0)
    a.spend(list.length * 4)
    var keyed = list.map(function(v) { return { v: v, k: call(f, [v]) } })
    return capped(stableSort(keyed, function(p, q) { return V.order(p.k, q.k) }).map(function(p) { return p.v }))
  }),
  reverse: fn(1, 1, function(a) { return capped(a.list(0).slice().reverse()) }),
  take: fn(2, 2, function(a) {
    var k = Math.max(a.integer(1, 0), 0)
    return typeof a.at(0) === "string" ? a.text(0).slice(0, k) : capped(a.list(0).slice(0, k))
  }),
  drop: fn(2, 2, function(a) {
    var k = Math.max(a.integer(1, 0), 0)
    return typeof a.at(0) === "string" ? a.text(0).slice(k) : capped(a.list(0).slice(k))
  }),
  first: fn(1, 1, function(a) { var l = a.list(0); return l.length ? l[0] : null }),
  last: fn(1, 1, function(a) { var l = a.list(0); return l.length ? l[l.length - 1] : null }),
  indexOf: fn(2, 2, function(a) { return indexIn(a.list(0), a.at(1)) }),
  unique: fn(1, 1, function(a) {
    var out = []
    a.list(0).forEach(function(v) { if (indexIn(out, v) < 0) out.push(v) })
    return capped(out)
  }),
  flatten: fn(1, 1, function(a) {
    var out = []
    a.list(0).forEach(function(v) { if (Array.isArray(v)) out = out.concat(v); else out.push(v) })
    return capped(out)
  }),
  keys: fn(1, 1, function(a) {
    var v = a.at(0)
    return v instanceof Map ? capped(Array.from(v.keys())) : []
  }),
  values: fn(1, 1, function(a) {
    var v = a.at(0)
    return v instanceof Map ? capped(Array.from(v.values())) : []
  }),
  entries: fn(1, 1, function(a) {
    var v = a.at(0)
    if (!(v instanceof Map)) return []
    var out = []
    v.forEach(function(value, key) { out.push(new Map([["key", key], ["value", value]])) })
    return capped(out)
  }),
  get: fn(2, 3, function(a) {
    var v = memberOf(a.at(0), a.text(1))
    return v !== null ? v : a.at(2)
  }),

  // colours
  rgb: fn(3, 4, function(a) { return rgbColor(a.number(0), a.number(1), a.number(2), a.number(3, 1)) }),
  hsl: fn(3, 4, function(a) { return hslColor(a.number(0), a.number(1), a.number(2), a.number(3, 1)) }),
  alpha: fn(2, 2, function(a) {
    var c = asColor(a.at(0))
    if (c === null) throw new V.RuntimeError("alpha() needs a color")
    var factor = Math.fround(between(Math.fround(a.number(1)), 0, 1))
    return new V.Color(c.name, c.argb, Math.fround(c.alpha * factor))
  }),
  // Not folded: it resolves theme names, which only a host knows.
  mix: fn(3, 3, function(a) {
    var resolve = a.ctx && a.ctx.theme ? a.ctx.theme : null
    var x = resolveArgb(a.at(0), resolve)
    var y = x === null ? null : resolveArgb(a.at(1), resolve)
    if (x === null || y === null) throw new V.RuntimeError("mix() needs colors")
    return new V.Color(null, V.mixArgb(x, y, between(a.number(2), 0, 1)), 1)
  }, false),
  linear: fn(5, 5, function(a) { return gradientOf(false, a, 4) }),
  radial: fn(4, 4, function(a) { return gradientOf(true, a, 3) }),

  // animation curves (for `animate prop: ...`)
  spring: fn(0, 2, function(a) {
    return new Map([["type", "spring"], ["damping", a.number(0, 0.6)], ["stiffness", a.number(1, 300)]])
  }),
  tween: fn(0, 2, function(a) {
    return new Map([["type", "tween"], ["duration", a.number(0, 0.3)], ["easing", a.count > 1 ? a.text(1) : "ease"]])
  })
}

if (typeof module !== "undefined") {
  module.exports = {
    FUNCTIONS: FUNCTIONS, ArgReader: ArgReader, THEME_NAMES: THEME_NAMES, MAX_LIST: MAX_LIST,
    asColor: asColor, resolveArgb: resolveArgb, memberOf: memberOf, formatTime: formatTime,
    setFirstDayOfWeek: setFirstDayOfWeek, shellWord: shellWord, weatherGlyph: weatherGlyph
  }
}
