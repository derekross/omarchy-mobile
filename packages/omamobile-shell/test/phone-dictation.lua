-- SPDX-License-Identifier: MIT
-- hypr/phone.lua's dictation keys under a stub of Omarchy 4.5's helpers
-- (o.dictation_installed, o.bind_hold) and binds: squeekboard's Alt + Space
-- and F9 go to the app in front, a hardware keyboard keeps Omarchy's
-- dictation keys, and an F9 the owner bound to something else is left alone.
-- SCENARIO: installed (a backend is installed, Omarchy's Alt + Space bound),
-- migrated (and bindings.lua has the F9 line 4.5's migration appends, read
-- from $HOME), own-f9 (bindings.lua binds F9 to something else), none (no
-- backend: Omarchy binds nothing).
-- Run from the package directory: SCENARIO=... HOME=... lua test/phone-dictation.lua
local scenario = os.getenv("SCENARIO")
local noop = function() end
local binds = {}
local function dsp(name) return function(arg) return { dsp = name, arg = arg } end end
hl = {
  config = noop, window_rule = noop, layer_rule = noop, device = noop,
  unbind = function(keys)
    local kept = {}
    for _, b in ipairs(binds) do if b.keys ~= keys then kept[#kept + 1] = b end end
    binds = kept
  end,
  dsp = { window = { cycle_next = dsp("cycle_next"), bring_to_top = dsp("bring_to_top") }, focus = dsp("focus") },
}
o = {
  bind = function(keys, description, dispatcher, opts)
    binds[#binds + 1] = { keys = keys, dispatcher = dispatcher, opts = opts or {} }
  end,
  bind_hold = function(keys, _, press, _, release, opts)
    binds[#binds + 1] = { keys = keys, dispatcher = press, release = release, opts = opts or {}, hold = true }
  end,
  launch_on_start = noop,
  cmd_present = function(cmd) return cmd == "voxtype" end,
  dictation_installed = function() return scenario ~= "none" end,
}
-- What Omarchy 4.5 and the owner's bindings.lua bound before phone.lua loads
if scenario ~= "none" then o.bind("ALT + SPACE", "Toggle dictation", "omarchy-dictation toggle") end
if scenario == "migrated" then
  o.bind_hold("F9", "Start dictation (push-to-talk)", "omarchy-dictation start", "Stop dictation (push-to-talk)", "omarchy-dictation stop")
elseif scenario == "own-f9" then
  o.bind("F9", "My own key", "my-own-command")
end
dofile("hypr/phone.lua")

local failed = false
local function check(ok, what)
  if ok then print("ok - " .. scenario .. ": " .. what) else print("not ok - " .. scenario .. ": " .. what); failed = true end
end
local function find(keys)
  local found = {}
  for _, b in ipairs(binds) do if b.keys == keys then found[#found + 1] = b end end
  return found
end
local function not_osk(b)
  local d = b.opts.device
  return d ~= nil and d.inclusive == false and #d.list == 1 and d.list[1] == "hl-virtual-keyboard-squeekboard"
end
local space, f9 = find("ALT + SPACE"), find("F9")
for _, b in ipairs(f9) do
  check(b.dispatcher ~= "voxtype record start", "Omarchy 4.0's Voxtype F9 bind is not added on 4.5")
end
if scenario == "none" then
  check(#space == 0 and #f9 == 0, "without a dictation backend nothing is bound")
else
  check(#space == 1 and not_osk(space[1]) and space[1].dispatcher == "omarchy-dictation toggle",
    "Alt + Space toggles dictation from every keyboard but squeekboard")
  if scenario == "installed" then
    check(#f9 == 0, "F9 is not bound when the owner's bindings.lua doesn't bind it")
  elseif scenario == "migrated" then
    check(#f9 == 1 and f9[1].hold and not_osk(f9[1]) and f9[1].dispatcher == "omarchy-dictation start"
      and f9[1].release == "omarchy-dictation stop", "the migration's F9 push-to-talk stays, for every keyboard but squeekboard")
  elseif scenario == "own-f9" then
    check(#f9 == 1 and f9[1].dispatcher == "my-own-command" and f9[1].opts.device == nil, "the owner's own F9 bind is left as it is")
  end
end
os.exit(failed and 1 or 0)
