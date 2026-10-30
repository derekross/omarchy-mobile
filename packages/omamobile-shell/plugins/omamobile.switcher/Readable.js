// SPDX-License-Identifier: MIT
// Text that can be read on the phone (docs/TOUCH-PLAN.md 2.1 and 2.7).
// Plugins are separate directories with no shared import, so each one that
// needs this carries this same file (test/all checks they match).
//
// Size: Omarchy's type scale is a desktop's (caption 10 px, body 12 px); on
// the phone's 480 px wide screen, held at arm's length, nothing read goes
// under 12 px. A floor here rather than theme font overrides, which a theme
// change would drop.
//
// Contrast: secondary text (a status line, a placeholder, a hint) used to
// be the foreground darkened by a fixed factor or drawn at 60-75% opacity,
// which on a dark theme came to 3-4:1 against the surface. `secondary`
// mixes the foreground toward the surface only as far as WCAG's 4.5:1
// minimum for text allows, on any theme.

var MIN_PX = 12
var MIN_CONTRAST = 4.5
// How far secondary text may be mixed toward its surface at most (the
// share of the surface), so it still reads as secondary on a theme with
// plenty of contrast to spare.
var MAX_MIX = 0.6

function px(size) { return Math.max(MIN_PX, size) }

// Colours are {r, g, b[, a]} in 0..1, which a QML color is in JavaScript.

function channel(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }

// WCAG relative luminance.
function luminance(c) {
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
}

// WCAG contrast ratio, 1..21.
function contrast(a, b) {
  var la = luminance(a), lb = luminance(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

// `top` (with its alpha) laid over an opaque `under`.
function flattenRgb(top, under) {
  var a = top.a === undefined ? 1 : top.a
  return { r: top.r * a + under.r * (1 - a), g: top.g * a + under.g * (1 - a), b: top.b * a + under.b * (1 - a), a: 1 }
}

// The foreground mixed toward the surface as far as MIN_CONTRAST allows
// (never past MAX_MIX); the foreground itself when even that falls short.
function secondaryRgb(fg, bg, minRatio) {
  var want = minRatio || MIN_CONTRAST
  var under = flattenRgb(bg, { r: 0, g: 0, b: 0 })
  for (var t = MAX_MIX; t >= 0; t = Math.round((t - 0.02) * 100) / 100) {
    var mix = { r: fg.r * (1 - t) + under.r * t, g: fg.g * (1 - t) + under.g * t, b: fg.b * (1 - t) + under.b * t, a: 1 }
    if (contrast(mix, under) >= want) return mix
  }
  return { r: fg.r, g: fg.g, b: fg.b, a: 1 }
}

// For QML: a color. Under Node (no Qt) the {r, g, b, a} object.
function secondary(fg, bg) {
  var c = secondaryRgb(fg, bg)
  return typeof Qt !== "undefined" ? Qt.rgba(c.r, c.g, c.b, 1) : c
}

function flatten(top, under) {
  var c = flattenRgb(top, under)
  return typeof Qt !== "undefined" ? Qt.rgba(c.r, c.g, c.b, 1) : c
}

if (typeof module !== "undefined") {
  module.exports = { MIN_PX: MIN_PX, MIN_CONTRAST: MIN_CONTRAST, MAX_MIX: MAX_MIX, px: px, luminance: luminance, contrast: contrast,
                     flattenRgb: flattenRgb, secondaryRgb: secondaryRgb, secondary: secondary, flatten: flatten }
}
