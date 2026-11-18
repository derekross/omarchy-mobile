-- SPDX-License-Identifier: MIT
-- Pixel 8 Pro Hyprland settings. omamobile-shell's hypr/phone.lua loads this
-- file under pcall after the shared rules, when it is there (#204).
--
-- Screen look stopgap (#537): on some units the panel's mid-tones look flat
-- (washed out) after boot, cause unknown. A screen shader puts them back.
-- It is off by default. To turn it on, create
-- ~/.config/omamobile/screen-look-on and reload Hyprland (hyprctl reload) or
-- log in again; remove the file and reload to turn it off. Without the file
-- this does not touch screen_shader, so a line of your own still applies.
local shader = "/usr/share/omamobile/device-husky/screen-look.frag"
local opt_in = (os.getenv("HOME") or "") .. "/.config/omamobile/screen-look-on"
local marker = io.open(opt_in, "r")
if marker then
  marker:close()
  local ok, err = pcall(hl.config, { decoration = { screen_shader = shader } })
  if not ok then print("omamobile-device-husky: screen look: " .. tostring(err)) end
end
