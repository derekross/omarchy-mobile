# Touch and mobile usability plan

Status: 2026-10-27. Batches 0-3 (#48, #61, #62) are merged and on the reference phone: omamobile-shell 0.2.29, omamobile-omarchy 0.1.12. Batch 4 (omamobile-shell 0.2.30, checked on the phone 2026-10-27) is 2.4, the landscape layouts, and fixes #85 (the home widgets collapsed in landscape); what it does and what remains are under [Batch 4](#batch-4-landscape) below. The audit was taken 2026-10-26 on `main` at 30052e8 (omamobile-shell 0.2.16, Omarchy 4.0.6, Hyprland 0.56.2).

Fixed in omamobile-shell 0.2.18 (built and tested offline, not yet checked on the phone): 1.4 (tiles tap through a TapHandler, so a swipe on a tile closes or expands the sheet); 1.5 (the hide-keyboard button is 44 px tall, at the keyboard's top left); 1.9 (press feedback and a two-tap, urgent-coloured Clear all, further from Home); 1.10's settings Remove (two taps, at the far right; the Undo chip is still open); 2.1 without theme overrides (a 12 px floor, `Readable.js`, for every caption-sized label but the home tiles' label, which #43 raises; the update warning at body size with a glyph); 2.6 (44 px hit areas for the quick-settings handle, the page dots and the call chip); 2.7's tiles (only the glyph and name of an unavailable tile are dimmed); 3.7's quick-settings Reset (two taps); and the stale gesture comment in `Bar.qml` from 1.2.

The phone is 480x1040 logical px (scale 3). Targets used: touch targets at least 44 px (Material's 48 dp is about 51 px here), 8 px between targets, body text 14 px, nothing that has to be read under 12 px, contrast 4.5:1 for text.

What already works: the call card, the lock screen's PIN pad (84 px keys), the access sheet, the OWL widgets' 44 px minimum hit areas, and the panels that resize above the on-screen keyboard (launcher, Wi-Fi, Bluetooth, update sheet). libadwaita and Qt Quick apps (Phone, Messages, Contacts, Camera, Files, Papers, Maps, Omacalc, LocalSend) fit the phone.

Priorities: **P1** broken, unsafe, or a dead end on a phone; **P2** noticeably awkward; **P3** polish. Each item names where it comes from and the fix.

## Phase 0: things that break the phone or its safety (do first)

| # | Problem | Where | Fix |
| --- | --- | --- | --- |
| 0.1 | **The screen lock never engages on a phone installed from our image.** Omarchy's lock refuses without `/etc/pam.d/omarchy-lock-password` (`lock-denied: missing-pam`); only Omarchy's installer writes it, and our image doesn't. The maintainer's phone has a hand-made copy. | Omarchy `shell/plugins/lock/Service.qml:139-142`; `rootfs/build-inside`, firstboot | Firstboot (or an install hook) writes Omarchy's stanza when the file is missing. Don't run `omarchy-apply-lock` as is: it deletes `omarchy-lock-fingerprint`, which `omamobile-fingerprint` owns. `phone-smoke` reports `lock status` (`secure`, `passwordPam`). |
| 0.2 | **Menu > Update > Channel replaces the phone's pacman.conf** with Omarchy's x86 one (no `[omamobile]`, no Arch Linux ARM), then upgrades. | `omarchy-menu.jsonc` `update.channel.*` → `omarchy-channel-set` → `omarchy-refresh-pacman` | Hide `update.channel`; make `omamobile-omarchy` divert both scripts so they refuse on the phone and point at RELEASES §5.4. |
| 0.3 | **Menu > Update > Config > Hyprland / Shell wipe the phone setup** (phone.lua, squeekboard autostart, scale 3, the omamobile plugins); `omamobile-setup-user` won't redo them because its markers are set. | `omarchy-refresh-hyprland`, `omarchy-refresh-shell` | Hide both rows now. Later, move phone additions out of user files (a platform hook; upstreamable), and have setup-user check content, not only markers. |
| 0.4 | **System menu > Logout strands the user at SDDM's password prompt** with no keyboard (autologin without `Relogin=true`). Inferred, strong. | `/etc/sddm.conf.d/` autologin drop-in | `Relogin=true`; hide or relabel Logout. |
| 0.5 | **The on-screen keyboard can stay switched off.** Patch 0006 turns the global `screen-keyboard-enabled` off for the screensaver and relies on its exit paths to turn it back on; the screensaver's early exit when the lock is already up skips that. The maintainer's phone is in this state now. | `packages/omamobile-omarchy/patches/0006-*`; `omarchy-launch-screensaver` | Restore the setting on unlock/wake whenever no screensaver runs, and in the early-exit path; better, stop toggling the global setting. 1.6 below removes most of the trigger. |
| 0.6 | **Disks is in the launcher** and offers Format/Edit on the phone's UFS (the guard keeps it read-only, but it shouldn't be offered). | `.desktop` list | NoDisplay for `org.gnome.DiskUtility` (see 3.4). |

## Phase 1: core touch navigation

| # | Pri | Problem | Where | Fix |
| --- | --- | --- | --- | --- |
| 1.1 | P1 | **Notifications can't be dismissed by touch.** A tap runs the action; closing is right-click only; critical ones (Omarchy's first-run invitations) never expire; history has no UI. | Omarchy `notifications/components/NotificationCard.qml:78-115`, `Service.qml:104, 881-897` | Omarchy patch: swipe to dismiss (past ~35% of the width) and a 44 px close glyph. Shell: a notification shade with history and Clear all (`showHistory`, `dismissAll`), an unread dot in the bar. Point "Setup Wi-Fi" at our quick settings. |
| 1.2 | P1 | **No system back.** Esc is the only way out of many dialogs, TUIs and menus, and Esc exists only on the terminal keyboard layout. `Bar.qml:157` mentions gesture binds that don't exist. | shell; `hypr/phone.lua` | An edge-swipe back (narrow masked Overlay strips on the left/right edges, like #43's pill) that sends Escape, or a back glyph beside the home pill. |
| 1.3 | P2 | **Omarchy's menu has no touch back**, and its root (Settings) isn't reachable by tap. | Omarchy `menu/Menu.qml:703, ~1098, ~1160` | Omarchy patch: back chevron in the header, swipe right to go back. A Settings entry (launcher or quick-settings gear) running `omarchy-menu toggle root`. |
| 1.4 | P2 | **A swipe that starts on a quick-settings tile toggles it**, and swipe-up to close works only in the gaps. | `Tile.qml:93-102`, `QuickSettings.qml:1103-1118` | `TapHandler { gesturePolicy: DragThreshold }` plus long-press instead of the MouseArea. |
| 1.5 | P2 | **The hide-keyboard button covers app buttons** (bottom right, where Send/Next sit) and is 35 px tall. | `omamobile.keyboard/Keyboard.qml:76-88` | A hide key in the squeekboard layout, or a 44 px button at the keyboard's top-left edge. |
| 1.6 | P2 | **Screensaver after 2.5 min, lock after 5 min**: a lit, animated screen on an OLED phone. | no `idle` block in `shell.json` | Seed `"idle": {"screensaver": 0, "lock": 60}` and the `screensaver-off` toggle. |
| 1.7 | P2 | **Focused fields aren't scrolled above the keyboard** in home sheets and notes; Save sits below the fields. | `HomeSheets.qml:786, 1069, 1218-1230` | A scroll-into-view helper on each Flickable (`cursorRectangle`), and Save/Remove pinned in a footer. |
| 1.8 | P2 | **The app drawer closes only from the top-right chevron.** | `Launcher.qml:331-340` | Pull down to close when the grid is at its top. |
| 1.9 | P2 | **Recents: Clear all closes every app, unconfirmed, 16 px from Home**; the press highlight never shows (a colour token that doesn't exist). | `Switcher.qml:67-69, 304-341, 323, 444` | Two-tap confirm and danger styling; `Style.pressedFillFor(...)` for the press state. |
| 1.10 | P2 | **Home: Remove has no undo; widget settings' Remove is unconfirmed, 8 px from Save.** | `Home.qml:1349-1371`, `HomeSheets.qml:1366-1385` | An Undo chip for ~5 s; the existing two-tap `confirming` pattern. |
| 1.11 | P2 | **gum prompts need arrow keys and Enter; taps do nothing** (onboarding, PIN setup, the 143 menu rows that open a terminal). The terminal keyboard's arrow row is ~33 px tall. | `omamobile-onboarding:44-56`, `omamobile-set-pin:49-63`; squeekboard `terminal/us.yaml:20` | Onboarding and PIN setup as shell sheets (the update sheet already has the pieces). Later, a gum shim that uses the shell's dmenu mode. Make that keyboard row 36-40 units. |
| 1.12 | P2 | **Keyboard-only features**: clipboard history, dictation (voxtype runs but nothing starts it), notification history, nightlight, reminders, zoom. | Omarchy binds | Quick-settings tiles for Clipboard, Dictation, Nightlight, Reminder. |

## Phase 2: legibility and layout

| # | Pri | Problem | Where | Fix |
| --- | --- | --- | --- | --- |
| 2.1 | P2 | **Desktop-sized text**: 35 labels at 10 px, body at 12 px. The update sheet's "can't be stopped" warning is its smallest, dimmest text. | `Style.font.caption` across the plugins; `Update.qml:443-452` | Seed per-token font overrides (caption/body-small/body/subtitle → 12/13/14/15), after checking they survive a theme change; the warning in body at full opacity. |
| 2.2 | P2 | **Gaps (5/10), a 2 px border and 0.96-0.985 window opacity** cost ~5% of the width and let home widgets show through apps. | Omarchy `looknfeel.lua`, `windows.lua` | phone.lua: gaps 0, border 0, opacity 1. |
| 2.3 | P2 | **More than one window falls back to 240 px tiles**, and dialogs are stretched to full screen (inferred, strong). | phone.lua `maximize = true` on dwindle; `exit_window_retains_fullscreen = false` | `exit_window_retains_fullscreen = true`; no maximize for modal dialogs; consider the scrolling layout at column width 1.0. |
| 2.4 | P2 | **No landscape layouts**: the call card (420 px of ring controls) doesn't fit 480 px of height; the home grid stays 4x6 and its OWL widgets collapse (#85). | `CallCard.qml:95-96, 184`, `HomeModel.js:21` | Done in batch 4 (shell 0.2.30, offline): landscape layouts for the home, the call card, quick settings, the drawer, recents and the permission sheet; the update sheet already fit. See Batch 4. |
| 2.5 | P2 | **Home pill (#43)**: swipes register only in an 18 px strip; the pale pill is nearly invisible over light apps. | PR #43 | A 44 px masked hit strip, a contrasting outline. |
| 2.6 | P3 | Small hit areas: quick-settings handle 28 px, home page dots 28 px, the bar's call chip 29 px. | `QuickSettings.qml:1511-1530`, `Home.qml:1036-1061`, `Bar.qml:222` | 44 px hit areas; the visuals can stay. |
| 2.7 | P3 | Contrast: placeholder and secondary text ~3:1; unavailable tiles dimmed twice ("No modem" barely legible). | `Launcher.qml:325, 380, 556`; `Tile.qml:35, 81-88` | 4.5:1 for anything read; dim only the glyph. |
| 2.8 | P3 | `GDK_SCALE=2` with monitor scale 3: X11 GTK apps render small. | `~/.config/hypr/monitors.lua` | `omarchy_gdk_scale = 3` in setup-user. |
| 2.9 | P3 | Foot: 14 px padding each side; jumpy drag-scroll (multiplier 7). | foot.ini | `pad=6x6`, multiplier 3, `long-press-delay=300`. |

## Phase 3: apps, browser and polish

- **3.1 Chromium (P2):** add `--enable-wayland-ime --wayland-text-input-version=3` so web text fields raise the keyboard (test first). The global mobile user agent probably breaks the WhatsApp and Google Messages web apps: a per-site flag patch to `omarchy-launch-webapp`. Its tabs and menus stay desktop-sized; GNOME Web (Epiphany) is the phone-shaped option.
- **3.2 File pickers (P2):** GTK3 and Qt Widgets apps open the desktop chooser. Add `GTK_USE_PORTAL=1` and `GDK_DEBUG=portals`; test `QT_QPA_PLATFORMTHEME=xdgdesktopportal`.
- **3.3 Menu rows that can't work here (P2):** x86-only installers (Steam, Chrome, Edge, Dropbox, Spotify, the Windows VM), Direct boot (EFI), the drive password, bar position, keybinding guides. Hide them through a package-owned menu-extension directory (an upstreamable Omarchy patch), not sed edits.
- **3.4 Launcher clean-up (P2):** hide Disks, Evince (Papers stays), Snapshot (omacam is the camera), Fcitx 5 Configuration, CMake, lstopo, the printing apps, Foot Server/Client. LibreOffice, OBS, Kdenlive and the dev tools are unusable at 480 px; leave them installable but consider hiding.
- **3.5 PiP and About (P2):** PiP at 300x169 in a corner, not maximized; a compact About layout under 600 px.
- **3.6 Haptics (P3):** none in the shell. A small helper for long-press, the switcher hold and the answer threshold (cs40l26 exists). It buzzes: announce before testing.
- **3.7 Polish (P3):** QS edit mode's "−" badges and Reset confirm; Wi-Fi/Bluetooth Forget confirm or undo; "Added to home" feedback after a drawer long-press; the missing-app tile says "Not installed" instead of its raw id; switcher cards show the app's name, not its id; OWL slider drags only on their own axis; a fade on the drawer's clipped last row; a safe-area token for the rounded corners; a pull-down strip over fullscreen apps; a Gestures table in the shell README.

## Omarchy patches this needs (upstreamable)

1. Notifications: swipe to dismiss and a touch close button (1.1). Patch 0017, omamobile-omarchy 0.1.10 (built and tested offline, not yet checked on the phone). The shade under quick settings lists the toasts and history, and a sideways swipe on a row forgets that one notification through the service (patch 0019, omamobile-omarchy 0.1.11, omamobile-shell 0.2.28; offline as above).
2. Menu: back chevron and swipe back (1.3). Patch 0018, omamobile-omarchy 0.1.10 (offline as above); the Settings entry is still open.
3. Menu: a platform extension directory (`$XDG_DATA_DIRS/omarchy/menu.d`) so packages hide rows without editing user files (0.2, 0.3, 3.3).
4. Refresh scripts keep platform additions (0.3).
5. Web apps: per-site browser flags (3.1).
6. Later: a gum shim that uses the shell's dmenu mode on touch (1.11).
7. Notifications: platform phrasing. On a touch platform `omarchy-notification-send` says "Tap to" for "Click to", "Tap to edit/open" for the screenshot and recording toasts' "Super + Alt + , (or click this)", points Voxtype's "Hold F9" at the Dictation tile (1.12), and drops parenthesised or whole-line "Super + …" hints; a desktop sends what it did before. Patch 0020, omamobile-omarchy 0.1.12 (offline as above).

## Batch 4: landscape

Hyprland transform 1 or 3 gives a 1040x480 logical px output (portrait is 480x1040). omamobile-shell 0.2.30 (built and tested offline; the phone check is open):

- **Home** (#85): a page wider than tall shows the layout turned on its side: the grid's columns and rows swap and each item's place and box turn with them, scaled by the cells' ratio to keep its size in pixels (the landscape cells are 173x87 against 120x151), then clamped to the widget's limits and re-placed where it overlaps (`HomeModel.transposeLayout`). The view derives this; `home.json` stays portrait and nothing is saved. The OWL dp comes from the screen's shorter side (from the landscape width it drew 2.2 times larger into cells 2.6 times shorter, which is what collapsed the widgets), the catalog keeps the portrait cell height, and edit mode (drag, resize, the toolbar) waits for portrait, which a long press says; the sheets still open.
- **Call card:** the caller on the left half, the ring controls or the in-call controls on the right, each centred; the reply sheet over the controls' half. Same swipe threshold, same targets.
- **Quick settings:** the sheet keeps to 58% of the width with the notification shade beside it; tile columns follow the sheet's width (two upright, three on the side, the collapsed row in whole rows); a sheet taller than the screen scrolls above a pinned handle.
- **App drawer:** as many columns of the portrait cell width as fit (four upright, eight on the side), so the icons keep their size.
- **Recents:** a card keeps the screen's shape instead of 72% of the width, so the preview isn't stretched.
- **Permission sheet:** the card keeps to 600 px, centred, with Allow and Don't allow side by side.
- **Update sheet:** fit already (the card fills the screen, its pages scroll, the PIN sits above the keyboard); now drawn in both orientations by its render.
- **Tests:** offscreen renders in the OWL container of the real plugins, upright and on their side, with geometry checks (`test/home-render` with the today and fetch built-ins fed from fixtures, `call-render`, `quicksettings-render`, `launcher-render`, `access-render`, `update-render`; `test/all` runs each when `OMAMOBILE_*_RENDER` names an output directory), the home model's transposition under node, and recents' landscape case in `test/switcher-touch` (qmltestrunner). Against `origin/main`'s plugins the home render reproduces #85.
- **Not touched:** the on-screen keyboard (squeekboard's own layouts), the lock screen (Omarchy's; held portrait by omamobile-sensors 0.2.1, #54), the Wi-Fi, Bluetooth and record panels (height-adaptive lists; not yet rendered on their side).

**To check on the phone** (shell 0.2.30, rotated with the sensors or `hyprctl keyword monitor ...,transform,3`): the home page turns with the phone with every widget readable and nothing saved to `home.json` (`shell call omamobile.home state` says `landscape: true`, `viewGrid` 6x4); a long press in landscape says to turn the phone upright; quick settings opens with the shade beside it and the expanded page scrolls above the handle; the drawer shows eight columns; recents' cards keep their shape; an incoming call shows the caller left and the swipe track right (needs a SIM: TELEPHONY-APPS-PLAN).

**Checked on the Pixel 7 Pro (2026-10-27, shell 0.2.30, `7.3.0-rc6-omamobile-push1-00588-gcd72ae58ee47`, rotated with `hyprctl`):** the home widgets lay out side by side with every row readable (#85 fixed), the saved layout file is unchanged, the drawer shows eight columns at the portrait icon size, and quick settings and recents behave as rendered. Two follow-ups seen there, for batch 5: a row of four app icons in portrait becomes a column at the right edge in landscape (the transposition should keep rows of icons as rows, placing them below the widgets), and the landscape view showed four page dots where the layout has three pages (items that no longer fit were pushed to a new page; prefer re-placing them on their own page).

**What remains after batch 4:** 1.11 (gum prompts as sheets: onboarding, PIN setup), 1.12's Nightlight and Reminder tiles, 2.1's per-token font seeds (the 12 px floor is in; the overrides need a theme-change check), 2.7 contrast (4.5:1 for placeholder and secondary text), 3.1 per-site web-app flags, 3.3's upstreamable `menu.d` patch (the rows are hidden by `omamobile-setup-user` for now), 3.5 About, 3.6 haptics, 3.7 polish, and the Omarchy patches 3-6 below.

## Suggested order

1. Phase 0 (one `omamobile-omarchy` and firstboot release, plus a `phone-smoke` lock check).
2. Quick wins, each under an hour: 1.4, 1.9 (colour token and confirm), 1.10, 1.6, 2.1, 2.2, 2.6, 3.4, 2.8, 2.9.
3. Notifications (1.1) and back (1.2): the two biggest gaps.
4. The rest of Phase 1, then Phase 2's layout items, then Phase 3. Batches 0-3 covered Phase 0, 1.1-1.10, 1.12 (Clipboard and Dictation), 2.1 (the floor), 2.2, 2.3, 2.5, 2.6, 2.8, 2.9, 3.2, 3.4, 3.5's PiP and the patches 1, 2 and 7; batch 4 covered 2.4.

Each change that alters how the phone looks or feels is announced before it reaches the reference phone, and checked with a screenshot.
