-- SPDX-License-Identifier: MIT
-- hypr/display-scale.lua: the scale sums for the three phones and for other
-- screens, then its rules under a stub of Hyprland's Lua API (hl.*) that
-- resolves them as Hyprland 0.57 does (a rule naming an output beats the
-- one for every output, a later rule for a name replaces an earlier one).
-- Run from the package directory: lua test/display-scale.lua [monitors.lua]
-- With a monitors.lua (test/setup-user.sh passes the one it set up), that
-- file is evaluated too, on each phone.
local M = dofile("hypr/display-scale.lua")

local failed = false
local function check(ok, what)
  print((ok and "ok - " or "not ok - ") .. what)
  if not ok then failed = true end
end
local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 1e-9 end

-- Hyprland's own test of a scale (CMonitor::applyMonitorRule, 0.57): taken
-- silently when it divides the mode into whole pixels after rounding to
-- 120ths; otherwise it looks for the nearest clean one (warning about it)
-- and returns that.
local function hyprland_takes(s, w, h)
  local k = math.floor(s * 120 + 0.5)
  local function clean(k) return (w * 120) % k == 0 and (h * 120) % k == 0 end
  if clean(k) then return true, k / 120 end
  for i = 1, 89 do
    if clean(k + i) then return false, (k + i) / 120 end
    if clean(k - i) then return false, (k - i) / 120 end
  end
  return false, nil
end

-- ------------------------------------------------------------ the phones

-- Their panels (owl/phone.js BOARDS: pixels and px/in), and the size in mm
-- DRM reports where it has been read on the phone: 71x155 on the 7 Pro
-- (hyprctl monitors -j), 70x155 on the 8 Pro (kernel #154). For the 9a, the
-- size its density gives, and a range around it.
local phones = {
  { "cheetah", "Pixel 7 Pro", 1440, 3120, 512, { 71, 155 }, 3, "480x1040", 100 },
  { "tegu", "Pixel 9a", 1080, 2424, 422, false, 2.4, "450x1010", 97 },
  { "husky", "Pixel 8 Pro", 1344, 2992, 489, { 70, 155 }, 8 / 3, "504x1122", 93 },
}
local unpack = table.unpack or unpack
for _, p in ipairs(phones) do
  local code, model, w, h, dpi, mm, want, logical, size = unpack(p)
  local from_dpi = { w / dpi * 25.4, h / dpi * 25.4 }
  for _, size_mm in ipairs(mm and { from_dpi, mm } or { from_dpi }) do
    local s = M.scale_for("DSI-1", w, h, size_mm[1], size_mm[2])
    check(near(s, want), string.format("%s (%s) at %.0fx%.0f mm: scale %.4g", model, code, size_mm[1], size_mm[2], s or 0))
  end
  local s = M.scale_for("DSI-1", w, h, from_dpi[1], from_dpi[2])
  check(string.format("%dx%d", w / s, h / s) == logical and w % 1 == 0 and (w / s) % 1 == 0 and (h / s) % 1 == 0,
    model .. ": " .. logical .. " whole logical pixels")
  check(math.floor(100 * s * M.PHONE_PPI / dpi + 0.5) == size, model .. ": the UI at " .. size .. "% of the 7 Pro's size")
  check((hyprland_takes(s, w, h)), model .. ": Hyprland takes " .. string.format("%.4g", s) .. " without a warning")
  check(M.gdk_for(s) == 3, model .. ": GDK_SCALE 3")
end
-- A panel driver reports whole millimetres: a millimetre either way of the
-- 9a's 65x146 still gives 2.4, of the 8 Pro's 70x155 still 8/3, and of the
-- 7 Pro's 71x155 still 3.
local steady = true
for dw = -1, 1 do for dh = -1, 1 do
  steady = steady and near(M.scale_for("DSI-1", 1080, 2424, 65 + dw, 146 + dh), 2.4)
    and near(M.scale_for("DSI-1", 1344, 2992, 70 + dw, 155 + dh), 8 / 3)
    and near(M.scale_for("DSI-1", 1440, 3120, 71 + dw, 155 + dh), 3)
end end
check(steady, "a millimetre either way changes no phone's scale")
-- What one scale for every phone did: 3 isn't clean on the 8 Pro (Hyprland
-- warned and moved it to 3.2), and made the 9a 360 px wide.
local ok, moved = hyprland_takes(3, 1344, 2992)
check(not ok and near(moved, 3.2), "the old scale 3 on the 8 Pro: Hyprland moves it to 3.2, with a warning")
check(1080 / 3 == 360, "the old scale 3 on the 9a: 360 px wide")
-- 8/3 is passed as the closest double; Hyprland rounds to 120ths first, so
-- a shortened 2.66667 (autorotate.py's {scale:g}) lands on it too.
check((hyprland_takes(2.66667, 1344, 2992)) and (hyprland_takes(2.66667, 1080, 2424)), "a scale printed short still rounds to the clean 8/3")

-- ------------------------------------------------------------ other screens

check(near(M.scale_for("DP-1", 3840, 2160, 597, 336), 1.5), "27-inch 4K on DP: 1.5")
check(near(M.scale_for("DP-1", 2560, 1440, 597, 336), 1), "27-inch 1440p: 1")
check(near(M.scale_for("HDMI-A-1", 1920, 1080, 531, 299), 1), "24-inch 1080p: 1, never below")
check(near(M.scale_for("HEADLESS-1", 1920, 1080, 0, 0), 1), "a headless output (no size): 1")
check(M.scale_for("DSI-1", 1080, 2424, 0, 0) == nil, "a panel that reports no size keeps monitors.lua's scale")
check(M.scale_for("DSI-1", 1080, 2424, 16, 9) == nil and near(M.scale_for("DP-1", 1920, 1080, 16, 9), 1),
  "an EDID's aspect ratio in place of a size counts as no size")
check(near(M.scale_for("Unknown-1", 1440, 3120, 71, 155), 3), "the boot framebuffer (simpledrm, Unknown-1) is the panel")
check(M.scale_for("DSI-1", 0, 0, 71, 155) == nil, "an output without a mode gets no rule")
check(near(M.scale_for("DSI-1", 3120, 1440, 155, 71), 3) and near(M.scale_for("DSI-1", 2424, 1080, 146, 65), 2.4),
  "turned on its side, the same scale")
check(near(M.scale_for("DSI-1", 1644, 3840, 65, 152), M.snap(643 / M.PHONE_PPI, 1644, 3840)) and M.scale_for("DSI-1", 1644, 3840, 65, 152) > 3,
  "a denser panel than the 7 Pro's goes above 3")
check(near(M.snap(9, 1440, 3120), 4) and near(M.snap(0.2, 1440, 3120), 1), "scales stay between 1 and 4")
local all_clean = true
for w = 720, 1600, 8 do
  local s = M.snap(2.7, w, 2 * w + 120)
  all_clean = all_clean and (hyprland_takes(s, w, 2 * w + 120))
end
check(all_clean, "every snapped scale is one Hyprland takes as it is")
check(M.handheld("DSI-1") and M.handheld("Unknown-1") and not M.handheld("DP-1") and not M.handheld("HEADLESS-2")
  and not M.handheld("eDP-1"), "a panel in the hand is DSI (or simpledrm's Unknown)")
check(M.gdk_for(2) == 2 and M.gdk_for(1.5) == 2 and M.gdk_for(1) == 1 and M.gdk_for(3.2) == 4, "GDK_SCALE rounds up")

-- ------------------------------------------------------------ in Hyprland

local panels = {
  cheetah = { name = "DSI-1", width = 1440, height = 3120, physical_width = 71, physical_height = 155 },
  tegu = { name = "DSI-1", width = 1080, height = 2424, physical_width = 65, physical_height = 146 },
  husky = { name = "DSI-1", width = 1344, height = 2992, physical_width = 70, physical_height = 155 },
  blind = { name = "DSI-1", width = 1080, height = 2424, physical_width = 0, physical_height = 0 },
  dp = { name = "DP-1", width = 3840, height = 2160, physical_width = 597, physical_height = 336, refresh_rate = 59.94 },
}
local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end

-- A Hyprland with these outputs, before the config runs (`connected`, as on
-- a reload) or after (`later`, as on a cold start or a hotplug).
local current
function H_rules() return current.rules end
local function hyprland(connected)
  local H = { rules = {}, handlers = {}, timers = {}, commands = {}, env = {}, outputs = {} }
  current = H
  for _, m in ipairs(connected or {}) do H.outputs[#H.outputs + 1] = copy(m) end
  hl = {
    get_monitors = function() return H.outputs end,
    get_monitor = function(name) for _, m in ipairs(H.outputs) do if m.name == name then return m end end end,
    monitor = function(spec)
      local kept = {}
      for _, r in ipairs(H.rules) do if r.output ~= spec.output then kept[#kept + 1] = r end end
      kept[#kept + 1] = spec
      H.rules = kept
    end,
    on = function(event, fn) H.handlers[event] = H.handlers[event] or {}; table.insert(H.handlers[event], fn) end,
    timer = function(fn) H.timers[#H.timers + 1] = fn end,
    exec_cmd = function(cmd) H.commands[#H.commands + 1] = cmd end,
    env = function(k, v) H.env[k] = v end,
  }
  -- the rule Hyprland picks for an output, and the scale it applies
  function H.rule(name)
    for i = #H.rules, 1, -1 do if H.rules[i].output == name then return H.rules[i] end end
    for _, r in ipairs(H.rules) do if r.output == "" then return r end end
  end
  function H.connect(m)
    m = copy(m)
    local r = H.rule(m.name)
    m.scale = r and tonumber(r.scale) or 1
    H.outputs[#H.outputs + 1] = m
    for _, fn in ipairs(H.handlers["monitor.added"] or {}) do fn(m) end
  end
  function H.start() for _, fn in ipairs(H.handlers["hyprland.start"] or {}) do fn() end end
  function H.run_timers() local t = H.timers; H.timers = {}; for _, fn in ipairs(t) do fn() end end
  function H.reloads()
    local n = 0
    for _, c in ipairs(H.commands) do if c:find("hyprctl reload", 1, true) then n = n + 1 end end
    return n
  end
  return H
end

-- monitors.lua as setup-user leaves it: the module first, Omarchy's rule for
-- every output with the panel's scale, then GDK_SCALE (Omarchy's order).
-- `o` adds what a user may have: a rule for the panel copied from Omarchy's
-- line with another mode (copied), one with a number (rule), a number in
-- omarchy_monitor_scale (pinned).
local function config(o)
  o = o or {}
  local D = dofile("hypr/display-scale.lua").setup()
  -- the module never makes a rule for the panel itself
  for _, r in ipairs(H_rules()) do
    if r.output == "DSI-1" then error("the module made a rule for the panel") end
  end
  local omarchy_monitor_scale = o.pinned or D.monitor_scale(3)
  hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
  if o.copied then hl.monitor({ output = "DSI-1", mode = "1440x3120@60", position = "auto", scale = omarchy_monitor_scale }) end
  if o.rule then hl.monitor({ output = "DSI-1", mode = "preferred", position = "auto", scale = o.rule }) end
  -- the battery's 60 Hz line with a number for the scale
  if o.literal60 then hl.monitor({ output = "DSI-1", mode = "1440x3120@60", position = "auto", scale = o.literal60 }) end
  local omarchy_gdk_scale = D.gdk_scale(3)
  hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
  return D
end

for code, want in pairs({ cheetah = 3, tegu = 2.4, husky = 8 / 3 }) do
  local H = hyprland({ panels[code] })
  config()
  local r = H.rule("DSI-1")
  check(near(r.scale, want) and r.output == "" and #H.rules == 1,
    code .. ", a reload: the panel takes " .. string.format("%.4g", want) .. " through Omarchy's rule for every output")
  check(H.env.GDK_SCALE == "3", code .. ": GDK_SCALE 3")
  H.start(); H.run_timers()
  check(H.reloads() == 0, code .. ": a panel the config already saw needs no reload")
end

-- What a user adds still works, and wins where it says so
do
  for code, want in pairs({ cheetah = 0, tegu = 1 }) do
    -- the 60 Hz line with scale = 3: its mode stays at a reload and after a
    -- cold start, and so does its 3 (on the 9a too: a number wins)
    local R = hyprland({ panels[code] })
    config({ literal60 = 3 })
    local r = R.rule("DSI-1")
    check(r.mode == "1440x3120@60" and r.scale == 3, code .. ": the 60 Hz line with scale = 3 keeps its mode and its scale")
    local C = hyprland({})
    config({ literal60 = 3 })
    C.connect(panels[code]); C.start(); C.run_timers()
    check(C.reloads() == want and C.rule("DSI-1").mode == "1440x3120@60",
      code .. ", cold start with that line: 60 Hz from the first frame" .. (want == 0 and ", no reload" or ", one reload that changes nothing"))
  end

  local H = hyprland({ panels.tegu })
  config({ copied = true })
  local r = H.rule("DSI-1")
  check(r.mode == "1440x3120@60" and near(r.scale, 2.4), "a rule copied from Omarchy's line (60 Hz) keeps the panel's own scale")
  H = hyprland({ panels.tegu })
  config({ rule = 8 / 3 })
  check(near(H.rule("DSI-1").scale, 8 / 3), "a rule with a number of the user's for the panel wins")
  H = hyprland({ panels.tegu })
  config({ pinned = 2 })
  check(near(H.rule("DSI-1").scale, 2), "a number in omarchy_monitor_scale wins")
end

-- Cold start: the config runs with no outputs, the panel comes up at the
-- fallback 3; where that's wrong, one reload, after which the panel has its
-- own scale.
for code, want in pairs({ cheetah = 0, tegu = 1, husky = 1 }) do
  local H = hyprland({})
  config()
  check(H.env.GDK_SCALE == "3" and #H.rules == 1 and H.rules[1].scale == 3, code .. ", cold start: 3 at first")
  H.connect(panels[code]); H.start(); H.run_timers()
  check(H.reloads() == want, code .. ", cold start: " .. (want == 0 and "no reload (3 is its scale)" or "one reload, though both the event and the start ran"))
  check(not H.commands[1] or H.commands[1]:find("omarchy-hyprland-reload-guard paused", 1, true) ~= nil,
    code .. ": no reload while Omarchy holds reloads back")
end
do
  local H = hyprland({})
  config({ pinned = 2 })
  H.connect(panels.tegu); H.start(); H.run_timers()
  check(H.reloads() == 0, "cold start with the user's own number: nothing to reload for")
  H = hyprland({})
  config({ copied = true })
  H.connect(panels.tegu); H.start(); H.run_timers()
  local R = hyprland({ panels.tegu })
  config({ copied = true })
  check(H.reloads() == 1 and near(R.rule("DSI-1").scale, 2.4) and R.rule("DSI-1").mode == "1440x3120@60",
    "cold start with a copied 60 Hz rule: one reload, then 60 Hz at the panel's own scale")
end
-- A panel with no size: nothing to reload for, it keeps 3
do
  local H = hyprland({})
  config()
  H.connect(panels.blind); H.start(); H.run_timers()
  local R = hyprland({ panels.blind })
  config()
  check(H.reloads() == 0 and R.rule("DSI-1").scale == 3 and R.env.GDK_SCALE == "3",
    "a panel that reports no size: no reload, it keeps 3")
end
-- An external screen plugged in, and a foldable's second panel
do
  local H = hyprland({ panels.cheetah })
  config()
  H.connect(panels.dp); H.run_timers()
  check(H.reloads() == 1, "an external screen plugged in: a reload")
  local R = hyprland({ panels.cheetah, panels.dp })
  config()
  check(near(R.rule("DP-1").scale, 1.5) and R.rule("DP-1").output == "DP-1" and near(R.rule("DSI-1").scale, 3)
    and R.env.GDK_SCALE == "3", "...after which it has its own 1.5, the panel keeps 3, and GDK_SCALE follows the panel")
  check(R.rule("DP-1").mode == "3840x2160@59.94", "...in the mode it already had, not \"preferred\"")
  local nohz = copy(panels.dp); nohz.refresh_rate = nil
  local P = hyprland({ panels.cheetah, nohz })
  config()
  check(P.rule("DP-1").mode == "preferred", "an output that reports no mode gets \"preferred\"")
  local inner = { name = "DSI-2", width = 2208, height = 1840, physical_width = 148, physical_height = 123 }
  local F = hyprland({ panels.tegu, inner })
  config()
  local s2 = M.scale_for("DSI-2", 2208, 1840, 148, 123)
  check(near(F.rule("DSI-1").scale, 2.4) and F.rule("DSI-2").output == "DSI-2" and near(F.rule("DSI-2").scale, s2) and not near(s2, 2.4),
    "a second panel (a foldable's) gets a rule of its own, at its own scale")
end

-- A Hyprland whose API has moved on: monitors.lua still runs, with its
-- fallbacks
do
  local H = hyprland({ panels.tegu })
  hl.get_monitors = function() error("no such option: all") end
  hl.on = function(event) error("unknown event " .. event) end
  local printed = print
  print = function() end
  local ran = pcall(config)
  print = printed
  check(ran and H.rule("DSI-1").scale == 3 and H.env.GDK_SCALE == "3", "a Hyprland whose API has changed: monitors.lua runs, at 3")
end

-- ------------------------------------------------------------ setup-user's file

local path = arg and arg[1]
if path then
  for code, want in pairs({ cheetah = 3, tegu = 2.4, husky = 8 / 3 }) do
    local H = hyprland({ panels[code] })
    local chunk, err = loadfile(path)
    check(chunk ~= nil, path .. " is valid Lua" .. (err and (": " .. err) or ""))
    if chunk then
      local ran, run_err = pcall(chunk)
      check(ran, path .. " runs on the " .. code .. (run_err and (": " .. tostring(run_err)) or ""))
      local r = H.rule("DSI-1")
      check(r and near(r.scale, want), path .. " on the " .. code .. ": scale " .. string.format("%.4g", want))
      check(H.env.GDK_SCALE == "3", path .. " on the " .. code .. ": GDK_SCALE 3")
    end
  end
end

os.exit(failed and 1 or 0)
