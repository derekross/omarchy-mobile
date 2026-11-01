-- SPDX-License-Identifier: MIT
-- Omarchy Mobile's Hyprland rules for a phone, loaded after Omarchy's defaults
-- (from the user's looknfeel.lua). Package updates reach them.

-- Apps fill the screen between the bar and the dock, like Android. Omarchy's
-- floating windows (its terminal, btop, dialogs) are sized for a desktop and
-- would land mostly off a 480 px wide screen.
-- Omarchy floats them through its floating-window tag, so drop the tag.
hl.window_rule({ match = { class = ".*" }, tag = "-floating-window" })
hl.window_rule({ match = { class = ".*" }, maximize = true })
-- ...except the screensaver, which Omarchy shows fullscreen over the bars.
hl.window_rule({ match = { class = "^org.omarchy.screensaver$" }, maximize = false })
hl.window_rule({ match = { class = "^org.omarchy.screensaver$" }, fullscreen = true })

-- Edge to edge (TOUCH-PLAN 2.2): Omarchy's gaps (5 and 10) and 2 px border
-- cost about 24 px of a 480 px wide screen, so none on the phone.
hl.config({ general = { gaps_in = 0, gaps_out = 0, border_size = 0 } })
-- ...and every window fully opaque: at Omarchy's 0.985/0.96 the home
-- screen's widgets (a layer below) showed through apps. Dropping the tag
-- stops Omarchy's default-opacity rule; the explicit 1 1 also covers the
-- browsers' own 1.0/0.985.
hl.window_rule({ match = { class = ".*" }, tag = "-default-opacity", opacity = "1 1" })

-- Maximize is a fullscreen state, and only one window per workspace holds it
-- (TOUCH-PLAN 2.3). When the maximized window closed, the others stayed
-- dwindle tiles (240 px wide with two); with this the next one takes the
-- screen again. (The scrolling layout at column width 1.0 never splits at
-- all and pairs with an edge-swipe gesture: a later option, not this one.)
hl.config({ misc = { exit_window_retains_fullscreen = true } })
-- Modal dialogs ("Save changes?", an app's preferences) keep their own size,
-- centred over their app and never bigger than the screen, rather than being
-- stretched to it by the maximize rule above.
hl.window_rule({
  match = { modal = true },
  maximize = false,
  float = true,
  center = true,
  max_size = { "(monitor_w)", "(monitor_h)" },
})
-- File dialogs (open, save, choose a folder) come from Nautilus through the
-- portal (portal/hyprland-portals.conf). One with a parent window would float
-- at its desktop size; tiled and maximized, it fills the screen between the
-- bar and the on-screen keyboard, like a phone sheet. After the modal rule,
-- so a modal chooser is a sheet too. Nautilus's own windows tile anyway.
hl.window_rule({ match = { class = "^org.gnome.Nautilus$" }, float = false, maximize = true })

-- Picture-in-picture (TOUCH-PLAN 3.5): Omarchy floats it, pinned, at 600x338,
-- wider than the screen, and the maximize rule above made it fill the
-- screen. A small window in the top-right corner, below the bar, instead.
hl.window_rule({
  match = { tag = "pip" },
  maximize = false,
  size = { 300, 169 },
  move = { "(monitor_w-window_w-8)", "(monitor_h*0.08)" },
})

-- Lock after boot, like a phone: the session logs in automatically, then
-- Omarchy's lock comes up with its PIN pad. Only once a PIN is set (the
-- lock-on-start toggle), since a lock with no password can't be opened.
o.launch_on_start(
  "bash -c 'omarchy-toggle-enabled lock-on-start || exit 0; "
    .. "for _ in $(seq 100); do omarchy-shell lock status >/dev/null 2>&1 && break; sleep 0.2; done; "
    .. "omarchy-system-lock'"
)

-- Hardware keys, like Android: a short power press locks and turns the
-- screen off (or wakes a locked phone), holding power opens Omarchy's system
-- menu, and power + volume down takes a screenshot. omamobile-keys works out
-- which gesture it was.
hl.unbind("XF86PowerOff")
o.bind("XF86PowerOff", "Power key", "omamobile-keys power-down", { locked = true })
o.bind("XF86PowerOff", "System menu", "omamobile-keys power-up", { locked = true, release = true })
-- Volume down is also half of the screenshot chord, so it can't lower the
-- volume the moment it goes down: take over Omarchy's binding and let
-- omamobile-keys decide (a short wait for power, as on Android).
hl.unbind("XF86AudioLowerVolume")
o.bind("XF86AudioLowerVolume", "Volume down", "omamobile-keys volume-down", { locked = true, repeating = true })
-- Volume up goes through omamobile-keys too, so both volume keys can take a
-- photo while the Camera app is in front (and raise the volume otherwise).
hl.unbind("XF86AudioRaiseVolume")
o.bind("XF86AudioRaiseVolume", "Volume up", "omamobile-keys volume-up", { locked = true, repeating = true })
-- Its release ends Power + Volume Up push-to-talk (voice input, off unless
-- turned on in the voice settings); omamobile-keys ignores every other one.
o.bind("XF86AudioRaiseVolume", "Volume up released", "omamobile-keys volume-up-release", { locked = true, release = true })

-- A fresh phone (no name and email, or no PIN): a notification offers the
-- onboarding that Omarchy's installer does on a computer.
o.launch_on_start("omamobile-onboarding --nudge")

-- The screensaver turns the on-screen keyboard off while it runs and back on
-- when it exits (patches/omarchy/0006). A session restart, a reboot or the
-- lock can end it before it does, which left the keyboard off for good. No
-- screensaver runs at login, so turn it on here.
o.launch_on_start("gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true")

-- Hardware keys don't wake the screen, as on Android: power wakes it through
-- omamobile-keys, which decides from the screen's state when it is released.
-- With Omarchy's key_press_enables_dpms, the press itself lit the screen and
-- the release then turned it off again. Touch still wakes it.
hl.config({ misc = { key_press_enables_dpms = false } })

-- The fingerprint target (omamobile.fingerprint) is drawn above the lock
-- screen too, where the lock runs its fingerprint conversation. 1, not 2: on
-- the lock it needs no touches (the bridge reads the touchscreen itself),
-- and the lock's PIN pad keeps clear of the sensor (patches/omarchy/0003).
hl.layer_rule({ match = { namespace = "^omamobile-fingerprint$" }, above_lock = 1, no_anim = true })

-- The on-screen keyboard (squeekboard, namespace "osk") above the lock screen
-- too, taking touches (2): a password user's lock opens on the text field
-- (patches/omarchy/0011), and a session lock otherwise hides every other
-- surface, keyboards included.
hl.layer_rule({ match = { namespace = "^osk$" }, above_lock = 2 })

-- Calls (omamobile.call) above the lock too, taking touches (2): a ringing
-- call is answered from the lock screen, and the in-call controls stay
-- reachable while it's locked. The card offers call actions only.
hl.layer_rule({ match = { namespace = "^omamobile-call(-top)?$" }, above_lock = 2 })

-- The on-screen keyboard's own keys (squeekboard/keyboards/: the action row
-- Talk, Ask, Paste, Emoji and Hide). squeekboard can't run a command, so
-- each key sends an XF86 keysym and these binds act on it. squeekboard puts
-- every key on a keycode of a keymap it generates, and Hyprland resolves a
-- bind's keysym through kb_layout unless the device resolves binds by its
-- own keymap, so its virtual keyboard (named after the process) does. The
-- binds take keys from squeekboard only: a hardware keyboard's XF86Paste
-- still pastes.
local osk_device = "hl-virtual-keyboard-squeekboard"
local osk_only = { inclusive = true, list = { osk_device } }
local not_osk = { inclusive = false, list = { osk_device } }
hl.device({ name = osk_device, resolve_binds_by_sym = true })
local function voice(method)
  return "omarchy-shell shell call omamobile.voice " .. method .. " ''"
end
-- Talk dictates into the focused app and Ask opens the agent's listening
-- sheet (omamobile.voice), both push-to-talk: squeekboard presses a keysym
-- key on touch-down and releases it on lift-off; a short tap keeps listening
-- hands free, as the strip's mic key and the home pill do.
o.bind("XF86Dictate", "Keyboard: dictate", voice("dictatePress"), { device = osk_only })
o.bind("XF86Dictate", "Keyboard: dictate released", voice("dictateRelease"), { device = osk_only, release = true })
o.bind("XF86Assistant", "Keyboard: ask the agent", voice("askPress"), { device = osk_only })
o.bind("XF86Assistant", "Keyboard: ask released", voice("askRelease"), { device = osk_only, release = true })
-- Paste opens Omarchy's clipboard history (a tap pastes an entry), Emoji its
-- emoji picker (a tap types one; its search needs typed letters), and Hide
-- puts the keyboard away through omamobile.keyboard.
o.bind("XF86Paste", "Keyboard: clipboard", "omarchy-menu-clipboard", { device = osk_only })
o.bind("XF86EmojiPicker", "Keyboard: emoji", "omarchy-menu-emoji", { device = osk_only })
o.bind("XF86Keyboard", "Keyboard: hide", "omarchy-shell shell call omamobile.keyboard hideKeyboard ''", { device = osk_only })
-- Resolving squeekboard's binds by keysym also lets its Ctrl, Alt, Tab,
-- Delete and F-keys reach Omarchy's own binds, which they never did: Ctrl +
-- Alt + Delete would close every window, F9 would start Voxtype instead of
-- reaching the terminal, Alt + Tab would switch windows. Those binds are
-- taken back here and given again to every keyboard but squeekboard
-- (Omarchy's default/hypr/bindings/tiling.lua and voxtype.lua). hl.unbind
-- takes a key's every bind, so a user's own bind on one of these keys in
-- bindings.lua goes too. squeekboard has no Super key, so SUPER binds are
-- out of its reach.
local function not_from_osk(keys, binds)
  hl.unbind(keys)
  for _, b in ipairs(binds) do
    local opts = b[3] or {}
    opts.device = not_osk
    o.bind(keys, b[1], b[2], opts)
  end
end
not_from_osk("CTRL + ALT + DELETE", { { "Close all windows", "omarchy-hyprland-window-close-all" } })
not_from_osk("ALT + TAB", {
  { "Focus on next window", hl.dsp.window.cycle_next() },
  { "Reveal active window on top", hl.dsp.window.bring_to_top() },
})
not_from_osk("ALT + SHIFT + TAB", {
  { "Focus on previous window", hl.dsp.window.cycle_next({ next = false }) },
  { "Reveal active window on top", hl.dsp.window.bring_to_top() },
})
not_from_osk("CTRL + ALT + TAB", { { "Focus on next monitor", hl.dsp.focus({ monitor = "+1" }) } })
not_from_osk("CTRL + ALT + SHIFT + TAB", { { "Focus on previous monitor", hl.dsp.focus({ monitor = "-1" }) } })
if o.cmd_present("voxtype") then
  not_from_osk("F9", {
    { "Start dictation (push-to-talk)", "voxtype record start" },
    { "Stop dictation (push-to-talk)", "voxtype record stop", { release = true } },
  })
end
