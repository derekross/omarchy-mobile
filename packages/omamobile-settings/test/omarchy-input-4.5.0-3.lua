-- SPDX-License-Identifier: MIT
-- Lines 7-8, 10, 18 and 51 of Omarchy 4.5.0-3's default/hypr/input.lua (omarchy-settings 4.5.0-3,
-- MIT), pinned for test/keyboard-backend.sh. Update with the Omarchy version when theirs changes.
local non_latin_layouts =
  " af am ara bd bg by et ge gr il in iq ir kg kh kz la lk mk mm mn mv np rs ru sy th tj ua "
local non_latin_us_variants = " chr rus "
local kb_options = "omarchy:shift_caps_compose"
  kb_options = kb_options .. ",grp:alts_toggle"
