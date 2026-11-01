// SPDX-License-Identifier: MIT
// The smallest size for text that has to be read. Omarchy's type scale is a
// desktop's (caption 10 px, body 12 px); on the phone's 480 px wide screen,
// held at arm's length, nothing read goes under 12 px (docs/TOUCH-PLAN.md
// 2.1). A floor here rather than theme font overrides, which a theme change
// would drop. Plugins are separate directories with no shared import, so
// each one that needs it carries this same file (test/all checks they match).

var MIN_PX = 12

function px(size) { return Math.max(MIN_PX, size) }

if (typeof module !== "undefined") {
  module.exports = { MIN_PX: MIN_PX, px: px }
}
