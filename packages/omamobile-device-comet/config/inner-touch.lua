-- SPDX-License-Identifier: MIT
-- CT3B: native touch is 2076x2152; inherited DSI-1 scanout is 2152x2076.
-- Include from both the SDDM and desktop Hyprland Lua configurations.
hl.device({ name = "goodix-berlin-capacitive-touchscreen", output = "DSI-1", transform = 1 })
-- CT3D remains dark: its touchscreen must not drive the inner desktop.
hl.device({ name = "synaptics-touchcomm-touchscreen", enabled = false })
