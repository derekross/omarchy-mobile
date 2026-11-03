-- SPDX-License-Identifier: MIT
-- Nested Hyprland that imitates the Pixel 7 Pro screen on a desktop.
-- 1440x3120 at scale 3 is 480x1040 logical. run-desktop sizes this window
-- to the screen, 6n x 13n at scale n/80 (600x1300 at 1.25 where it fits),
-- the same logical size, so layouts match the real phone.

local mode = os.getenv("PHONE_DEV_MODE") or "600x1300"
local scale = tonumber(os.getenv("PHONE_DEV_SCALE")) or 1.25
hl.monitor({ output = "WAYLAND-1", mode = mode, position = "0x0", scale = scale })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- Omarchy's theme colours for borders
local theme = os.getenv("HOME") .. "/.local/state/omarchy/current/theme/hyprland.lua"
local f = io.open(theme, "r")
if f then
  f:close()
  dofile(theme)
end

hl.config({
  general = { gaps_in = 4, gaps_out = 6, border_size = 2 },
  decoration = { rounding = 0 },
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true, disable_watchdog_warning = true },
})

-- The outer desktop owns SUPER, so the phone session uses ALT. The default
-- terminal, started directly rather than through uwsm, opens in this session
hl.bind("ALT + RETURN", hl.dsp.exec_cmd("xdg-terminal-exec"), { description = "Terminal" })

hl.on("hyprland.start", function()
  -- Omarchy's shell, from the dev copy, with the phone profile's home directory
  hl.exec_cmd(os.getenv("PHONE_DEV_SHELL_CMD"))
end)
