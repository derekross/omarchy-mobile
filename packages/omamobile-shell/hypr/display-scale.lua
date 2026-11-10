-- SPDX-License-Identifier: MIT
-- Each screen's scale, from its pixels and the millimetres DRM reports for
-- it, so the phone's UI is the same physical size on every model. The shell
-- was laid out on the Pixel 7 Pro: 1440x3120 at 512 px/in, scale 3, 480x1040
-- logical px. One scale for every phone made the Pixel 9a's UI 21% larger
-- (1080x2424 at 422 px/in: 360 px wide at 3) and the Pixel 8 Pro's 2992 px
-- not divisible by 3 at all (Hyprland moved it to 3.2, with a warning). A
-- handheld panel gets the 7 Pro's 170.7 logical px per inch instead, snapped
-- to the nearest clean scale: 3 on the 7 Pro, 2.4 on the 9a (450x1010, the
-- UI at 97% of the 7 Pro's size), 8/3 on the 8 Pro (504x1122, at 93%).
--
-- omamobile-setup-user loads this from the user's monitors.lua, once, at
-- the top, and makes omarchy_monitor_scale (the scale of Omarchy's rule for
-- every output) monitor_scale(3): the panel's scale, so a rule of the
-- user's that copies Omarchy's line (a 60 Hz mode, say) keeps it too. Every
-- other screen (an external one, a foldable's second panel) gets a rule of
-- its own here. A number in omarchy_monitor_scale, or a rule for one output
-- further down (Omarchy's display scaling writes one), still wins: in
-- Hyprland a rule that names an output beats the one for every output
-- wherever it is, and a later rule for the same name replaces an earlier
-- one. It is all in the config itself, so a reload (Omarchy writes its
-- config files often) keeps it; a rule set at runtime with `hyprctl eval`
-- would be lost at the next reload, and the scale would jump back and forth.
--
-- A fractional scale costs a little: a client without wp-fractional-scale-v1
-- (GTK 3, squeekboard) draws at 3 and Hyprland scales it down, 1.56 times
-- the panel's pixels on the 9a. The package README has the details.
--
-- The functions above setup() are plain Lua: test/display-scale.lua and the
-- omamobile-display-scale command run them outside Hyprland.

local M = {}

-- The 7 Pro's density at scale 3, for a panel held in the hand.
M.PHONE_PPI = 512 / 3
-- An external screen, further away: 27" 1440p is scale 1, 27" 4K 1.5.
M.DESKTOP_PPI = 110
-- Hyprland and wp-fractional-scale-v1 count scales in 120ths.
M.STEPS = 120
M.MIN_SCALE, M.MAX_SCALE = 1, 4

-- A panel in the hand: DSI (or DPI) on the board, or the boot framebuffer
-- that simpledrm drives before the panel's driver loads ("Unknown-1").
-- Anything else (DP, HDMI, a headless output) is a screen further away.
function M.handheld(name)
  name = tostring(name or "")
  return name:match("^DSI%-") ~= nil or name:match("^DPI%-") ~= nil or name:match("^Unknown%-") ~= nil
end

-- Pixels per inch along the diagonal, or nil when the size is missing or
-- can't be a screen's: 0x0 from a panel driver that sets none, or an EDID
-- that gives its aspect ratio ("16x9 mm"), which comes out at thousands of
-- pixels per inch.
function M.ppi(w, h, mm_w, mm_h)
  w, h, mm_w, mm_h = tonumber(w) or 0, tonumber(h) or 0, tonumber(mm_w) or 0, tonumber(mm_h) or 0
  if w <= 0 or h <= 0 or mm_w <= 0 or mm_h <= 0 then return nil end
  local ppi = math.sqrt(w * w + h * h) / (math.sqrt(mm_w * mm_w + mm_h * mm_h) / 25.4)
  if ppi < 50 or ppi > 1000 then return nil end
  return ppi
end

local function gcd(a, b)
  while b ~= 0 do a, b = b, a % b end
  return a
end

-- The clean scale nearest to `ideal`: a whole number of 120ths that divides
-- both sides of the mode into whole logical pixels (Hyprland refuses any
-- other), nearest by ratio, between MIN_SCALE and MAX_SCALE. 120/120
-- always divides, so there is always one.
function M.snap(ideal, w, h)
  w, h = tonumber(w) or 0, tonumber(h) or 0
  if not ideal or w <= 0 or h <= 0 then return nil end
  ideal = math.min(M.MAX_SCALE, math.max(M.MIN_SCALE, ideal))
  local g = gcd(w * M.STEPS, h * M.STEPS)
  local best, best_d
  for k = M.MIN_SCALE * M.STEPS, M.MAX_SCALE * M.STEPS do
    if g % k == 0 then
      local d = math.abs(math.log(k / M.STEPS / ideal))
      if not best or d < best_d then best, best_d = k, d end
    end
  end
  return best / M.STEPS
end

-- The scale for one output, or nil to leave it to the rule for every
-- output. A handheld panel gets the phone density and an external screen
-- the desktop one. A screen of unknown size gets 1 (a headless output, a
-- projector), except a handheld panel: guessing there could make the phone
-- unusable, so the phone's own default stays.
function M.scale_for(name, w, h, mm_w, mm_h)
  w, h = tonumber(w) or 0, tonumber(h) or 0
  if w <= 0 or h <= 0 then return nil end
  local ppi = M.ppi(w, h, mm_w, mm_h)
  if not ppi then
    if M.handheld(name) then return nil end
    return 1
  end
  return M.snap(ppi / (M.handheld(name) and M.PHONE_PPI or M.DESKTOP_PPI), w, h)
end

-- The mode an output already has ("1440x3120@60"), for a rule that is only
-- there for its scale: a 60 Hz mode chosen for the battery, or any other,
-- stays. "preferred" (what Omarchy's rule for every output asks for) only
-- when Hyprland reports none.
function M.mode_of(m)
  local w, h, hz = tonumber(m.width) or 0, tonumber(m.height) or 0, tonumber(m.refresh_rate) or 0
  if w <= 0 or h <= 0 or hz <= 0 then return "preferred" end
  return string.format("%dx%d@%s", w, h, (string.format("%.3f", hz):gsub("%.?0+$", "")))
end

-- GDK_SCALE, the factor X11 GTK apps draw at under XWayland (Omarchy leaves
-- them unscaled by Hyprland, so they stay sharp). GTK takes whole numbers
-- only: the panel's scale rounded up, so 2.4 and 8/3 give 3 as on the 7 Pro,
-- and an X11 app is a little larger than the rest on a touch screen rather
-- than smaller. It has no effect on Wayland apps.
function M.gdk_for(scale)
  return math.max(1, math.ceil(scale - 1e-6))
end

-- ---------------------------------------------------------------- Hyprland

-- Called from monitors.lua at every evaluation of the config, before
-- Omarchy's lines. The first handheld panel Hyprland has is the phone's
-- (monitor_scale() hands its scale to Omarchy's rule for every output, and
-- to any rule of the user's that says scale = omarchy_monitor_scale): this
-- makes no rule for it, so its mode is whatever those rules say. Every
-- other output gets a rule of its own, with the mode it already has; a rule
-- of the user's for it further down replaces that one, mode and all. Nothing
-- here sets a rule at runtime or writes a file. An output that appears later
-- (Hyprland reads the config before it has any outputs, so on a cold start
-- that is the panel too) is checked once its rule has been applied, and if
-- the config would give it another scale, or GDK_SCALE another value,
-- Hyprland reloads its config, once, so that it comes from the config, in
-- the config's order. On the 7 Pro the fallback 3 is its own scale and
-- nothing reloads.
function M.setup()
  M.seen, M.rules, M.panel, M.panel_name = {}, {}, nil, nil
  M.follows, M.gdk_follows, M.gdk = false, false, nil
  -- A Hyprland whose API has moved on (an option or an event renamed) must
  -- not take monitors.lua down with it: the fallbacks there still apply.
  local function guarded(what, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then print("omamobile display-scale: " .. what .. ": " .. tostring(err)) end
    return ok
  end
  guarded("outputs", function()
    for _, m in ipairs(hl.get_monitors({ all = true }) or {}) do
      if m.name then
        M.seen[m.name] = true
        local s = M.scale_for(m.name, m.width, m.height, m.physical_width, m.physical_height)
        if s and not M.panel and M.handheld(m.name) then
          M.panel, M.panel_name = s, m.name
        elseif s then
          hl.monitor({ output = m.name, mode = M.mode_of(m), position = "auto", scale = s })
          M.rules[m.name] = s
        end
      end
    end
  end)

  local reloading = false
  local function check(name)
    if reloading or not name or M.seen[name] then return end
    local m = hl.get_monitor(name)
    if not m then return end
    local s = M.scale_for(name, m.width, m.height, m.physical_width, m.physical_height)
    if not s then return end
    -- After a reload this output would be the panel: its scale comes from
    -- omarchy_monitor_scale, if that still asks this module for it
    local panel = M.handheld(name) and not M.panel
    local off = (M.follows or not panel) and math.abs((tonumber(m.scale) or 0) - s) > 0.001
    local gdk = panel and M.gdk_follows and M.gdk ~= M.gdk_for(s)
    if off or gdk then
      reloading = true
      -- Not while Omarchy's package transaction holds reloads back
      hl.exec_cmd("omarchy-hyprland-reload-guard paused >/dev/null 2>&1 || hyprctl reload >/dev/null")
    end
  end
  -- Once the new output's rule has been applied (its scale is then the one
  -- this compares against), as Omarchy defers its own monitor handlers.
  local function later(name)
    hl.timer(function() guarded("check " .. tostring(name), check, name) end, { type = "oneshot", timeout = 1 })
  end
  guarded("monitor.added", hl.on, "monitor.added", function(m) later(m and m.name) end)
  -- In case Hyprland's first outputs come before the handler above runs
  guarded("hyprland.start", hl.on, "hyprland.start", function()
    for _, m in ipairs(hl.get_monitors({ all = true }) or {}) do later(m.name) end
  end)
  return M
end

-- omarchy_monitor_scale: the panel's scale when Hyprland has the panel,
-- otherwise `fallback` (the value the line had before) until a reload.
function M.monitor_scale(fallback)
  M.follows = true
  return M.panel or fallback
end

-- GDK_SCALE for monitors.lua's hl.env line: from the panel's scale when
-- Hyprland has the panel, otherwise `fallback` (the line's value before).
function M.gdk_scale(fallback)
  M.gdk_follows = true
  M.gdk = M.panel and M.gdk_for(M.panel) or fallback
  return M.gdk
end

return M
