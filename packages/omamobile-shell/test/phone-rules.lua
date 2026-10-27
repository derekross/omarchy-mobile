-- SPDX-License-Identifier: MIT
-- hypr/phone.lua under a stub of Hyprland's Lua API (hl.*) and Omarchy's
-- helpers (o.*): it has to load, and the window rules and settings the touch
-- layout depends on (TOUCH-PLAN 2.2, 2.3, 3.5) have to be there, with the
-- later rule winning where two set the same thing, as in Hyprland.
-- Run from the package directory: lua test/phone-rules.lua
local config, rules = {}, {}
local function merge(into, from)
  for k, v in pairs(from) do
    if type(v) == "table" and type(into[k]) == "table" then
      merge(into[k], v)
    else
      into[k] = v
    end
  end
end
local noop = function() end
hl = {
  config = function(t) merge(config, t) end,
  window_rule = function(t) rules[#rules + 1] = t end,
  layer_rule = noop,
  unbind = noop,
}
o = { bind = noop, launch_on_start = noop }
dofile("hypr/phone.lua")

local failed = false
local function check(ok, what)
  if ok then
    print("ok - " .. what)
  else
    print("not ok - " .. what)
    failed = true
  end
end

-- What a window whose match is exactly `match` ends up with: the last rule
-- with that match that sets the effect.
local function same(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end
local function effect(match, key)
  local value
  for _, r in ipairs(rules) do
    if same(r.match or {}, match) and r[key] ~= nil then value = r[key] end
  end
  return value
end
local function index(match, key)
  for i, r in ipairs(rules) do
    if same(r.match or {}, match) and r[key] ~= nil then return i end
  end
end

local g = config.general or {}
check(g.gaps_in == 0 and g.gaps_out == 0 and g.border_size == 0, "no gaps and no border")
local all = { class = ".*" }
check(effect(all, "opacity") == "1 1", "every window is fully opaque")
check(effect(all, "tag") ~= nil and effect(all, "tag"):find("-default-opacity", 1, true) ~= nil,
  "Omarchy's default-opacity tag is dropped")
check(effect(all, "maximize") == true, "apps still fill the screen")
check((config.misc or {}).exit_window_retains_fullscreen == true, "the next window takes the screen when one closes")
check(config.general.layout == nil, "the layout stays Omarchy's dwindle")

local modal = { modal = true }
check(effect(modal, "maximize") == false and effect(modal, "float") == true and effect(modal, "center") == true,
  "modal dialogs float centred, not maximized")
local max = effect(modal, "max_size")
check(type(max) == "table" and max[1] == "(monitor_w)" and max[2] == "(monitor_h)", "modal dialogs fit the screen")
local nautilus = { class = "^org.gnome.Nautilus$" }
check(effect(nautilus, "maximize") == true and effect(nautilus, "float") == false
  and index(nautilus, "maximize") > index(modal, "maximize"), "the portal's file chooser is still a full sheet")

local pip = { tag = "pip" }
local size, move = effect(pip, "size"), effect(pip, "move")
check(effect(pip, "maximize") == false and type(size) == "table" and size[1] == 300 and size[2] == 169,
  "picture-in-picture is 300x169, not maximized")
check(type(move) == "table" and move[1] == "(monitor_w-window_w-8)", "picture-in-picture sits in the right corner")

local saver = { class = "^org.omarchy.screensaver$" }
check(effect(saver, "maximize") == false and effect(saver, "fullscreen") == true, "the screensaver stays fullscreen")

os.exit(failed and 1 or 0)
