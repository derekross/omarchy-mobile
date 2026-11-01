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
-- Binds as Hyprland keeps them: a list that hl.unbind empties per key.
local binds, devices = {}, {}
local function dsp(name) return function(arg) return { dsp = name, arg = arg } end end
hl = {
  config = function(t) merge(config, t) end,
  window_rule = function(t) rules[#rules + 1] = t end,
  layer_rule = noop,
  device = function(t) devices[#devices + 1] = t end,
  unbind = function(keys)
    local kept = {}
    for _, b in ipairs(binds) do if b.keys ~= keys then kept[#kept + 1] = b end end
    binds = kept
  end,
  dsp = { window = { cycle_next = dsp("cycle_next"), bring_to_top = dsp("bring_to_top") }, focus = dsp("focus") },
}
o = {
  bind = function(keys, description, dispatcher, opts)
    binds[#binds + 1] = { keys = keys, description = description, dispatcher = dispatcher, opts = opts or {} }
  end,
  launch_on_start = noop,
  cmd_present = function(cmd) return cmd == "voxtype" end,
}
-- Omarchy's own binds that squeekboard's keys could now reach (tiling.lua,
-- voxtype.lua), bound before phone.lua as in Hyprland
o.bind("CTRL + ALT + DELETE", "Close all windows", "omarchy-hyprland-window-close-all")
o.bind("ALT + TAB", "Focus on next window", hl.dsp.window.cycle_next())
o.bind("F9", "Start dictation (push-to-talk)", "voxtype record start")
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

-- The on-screen keyboard's keys: squeekboard's device resolves binds by
-- keysym, its action-row keysyms are bound for it alone, and Omarchy's binds
-- it could now reach are taken from it.
local osk = "hl-virtual-keyboard-squeekboard"
local dev
for _, d in ipairs(devices) do if d.name == osk then dev = d end end
check(dev ~= nil and dev.resolve_binds_by_sym == true, "squeekboard's binds resolve by keysym")
local function find(keys, release)
  local found = {}
  for _, b in ipairs(binds) do
    if b.keys == keys and (release == nil or (b.opts.release == true) == release) then found[#found + 1] = b end
  end
  return found
end
local function device_is(b, inclusive)
  local d = b.opts.device
  return d ~= nil and d.inclusive == inclusive and #d.list == 1 and d.list[1] == osk
end
local function one(keys, release, command)
  local f = find(keys, release)
  return #f == 1 and device_is(f[1], true) and f[1].dispatcher == command
end
check(one("XF86Dictate", false, "omarchy-shell shell call omamobile.voice press ''")
  and one("XF86Dictate", true, "omarchy-shell shell call omamobile.voice release ''"),
  "Mic: press opens the voice bar (push-to-talk), release stops a hold")
check(#find("XF86Assistant") == 0, "no Ask key any more: Mic is the one voice key")
check(one("XF86Paste", false, "omarchy-menu-clipboard"), "Paste opens Omarchy's clipboard")
check(one("XF86EmojiPicker", false, "omarchy-menu-emoji"), "Emoji opens Omarchy's emoji picker")
check(one("XF86Keyboard", false, "omarchy-shell shell call omamobile.keyboard hideKeyboard ''"), "Hide hides the keyboard")
for _, keys in ipairs({ "CTRL + ALT + DELETE", "ALT + TAB", "ALT + SHIFT + TAB", "CTRL + ALT + TAB", "CTRL + ALT + SHIFT + TAB", "F9" }) do
  local f = find(keys)
  local ok = #f > 0
  for _, b in ipairs(f) do ok = ok and device_is(b, false) end
  check(ok, keys .. " is bound for every keyboard but squeekboard")
end
check(#find("ALT + TAB") == 2 and find("ALT + TAB")[1].dispatcher.dsp == "cycle_next", "Alt + Tab keeps both of Omarchy's actions")
local f9 = find("F9", true)
check(#f9 == 1 and f9[1].dispatcher == "voxtype record stop", "F9 still stops Voxtype on release")

os.exit(failed and 1 or 0)
