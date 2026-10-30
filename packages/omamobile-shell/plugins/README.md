<!-- SPDX-License-Identifier: MIT -->
# Omarchy Mobile plugins

Phone surfaces for Omarchy's own shell, written as ordinary third-party
Omarchy plugins. Nothing in Omarchy is patched: each directory here is a
plugin with a `manifest.json`, discovered from `~/.config/omarchy/plugins/`
and switched on by `phone/profile/shell.json`. They draw with the shell's
`qs.Commons` (Color, Style, Border) and `qs.Ui` components, so they follow
the current Omarchy theme: fonts, colours, borders, corner rounding, spacing.

All touch targets are at least 44 logical px (the Pixel 7 Pro is 480x1040
logical at scale 3).

| Plugin | Kind | What it is |
| --- | --- | --- |
| `omamobile.bar` | `bar` | Status bar: clock, connectivity, battery; tap or pull down for quick settings |
| `omamobile.quicksettings` | `panel` (keepLoaded) | Pull-down sheet: up to 21 tiles the user arranges, brightness and volume, a Settings gear and the notification history; Wi-Fi picker and Bluetooth panel |
| `omamobile.launcher` | `panel` (keepLoaded) | Home bar: app search, app grid and coding-agent prompt in one input |
| `omamobile.home` | `panel` (keepLoaded) | Home screens: pages of apps and widgets on the wallpaper, with an edit mode |
| `omamobile.fingerprint` | `panel` (keepLoaded) | Fingerprint target over the sensor during verification, desktop guard, and the enrollment screen |
| `omamobile.keyboard` | `panel` (keepLoaded) | A hide button right above the on-screen keyboard while it is up (also over the lock) |
| `omamobile.update` | `panel` (keepLoaded) | The update sheet: Omarchy's update for a phone, in place of its terminal update |
| `omamobile.access` | `panel` (keepLoaded) | The permission sheet: xdg-desktop-portal's "Allow Camera to use the camera?", in place of GTK's desktop dialog |
| `omamobile.back` | `panel` (keepLoaded) | The back gesture: swipe in from the left or right edge for Escape |
| lockpad | none | Not built; see [Lock screen](#lock-screen-pin-pad) for why and what upstream needs |

## Enabling

`phone/profile/shell.json` already does this:

```json
{
  "bar": { "id": "omamobile.bar", "clockFormat": "HH:mm", "showBatteryPercent": true,
           "quickSettings": "omamobile.quicksettings" },
  "plugins": [
    { "id": "omamobile.quicksettings" },
    { "id": "omamobile.launcher" }
  ]
}
```

It also lists `omarchy.idle` under `disabledPlugins`. An idle timeout of `0`
means "act immediately" to that service, not "never", so the old profile ran
the screensaver and `omarchy-system-lock` the moment the session went idle.
The phone has no touch lock yet (below), so idle stays off for now.

## omamobile.bar

A full bar that replaces `omarchy.bar`. It is 44 px tall (or the theme's bar
size if larger), anchored to the top, and reserves its height so windows tile
below it. Left: the clock. Right: the unread notification count (when
there is one), do-not-disturb (when on), Bluetooth (when on), cellular
signal (when a modem exists), Wi-Fi or Ethernet, battery glyph and
percentage. The centre is left empty for the camera cutout.

The whole strip is one touch target: a tap toggles quick settings, a downward
pull past ~14 px opens it.

Sources: `Quickshell.Networking` (NetworkManager) for Wi-Fi/Ethernet,
`Quickshell.Bluetooth`, `UPower.displayDevice`, and the do-not-disturb flag
through the host's `omarchy.notifications` proxy (only full bars get that).
Glyphs are the same sets Omarchy's network and power panels use.

Settings live on the `bar` object in `shell.json`:

| Key | Default | |
| --- | --- | --- |
| `clockFormat` | `"HH:mm"` | Qt date format |
| `showBatteryPercent` | `true` | |
| `quickSettings` | `"omamobile.quicksettings"` | Plugin id the bar opens |

**Unread notifications:** an accent pill with the number of files in
Omarchy's notification history (`~/.local/state/omarchy/notifications/history/`,
one `<timestamp>-<id>.json` per notification, at most ten) newer than the
newest notification the quick-settings shade has shown. The notification
service has no count to read through the host's proxy, so the bar watches
the directory (`Qt.labs.folderlistmodel`, a file system watcher, not a poll).
The shade records its mark in `~/.local/state/omamobile/notifications-seen`
and calls `notificationsSeen` below. A toast that was acted on also lands in
history, so it counts until the shade has been opened.

**Mobile network and calls:** the cellular icon and the call chip come from
`omamobile-cell-watch` and `omamobile-call-watch --observe` (see
omamobile.call below); without a modem or omatel's agent they don't show.

IPC (`omarchy-shell omamobile.bar <method>`), for scripts and tests; no
gesture or key binds it yet:

| Method | Effect |
| --- | --- |
| `pullDown` | Open quick settings |
| `toggleQuickSettings` | Open or close it |
| `notificationsSeen <timestamp>` | Notifications up to this one (milliseconds) have been seen; returns the unread count |
| `unread` | The unread count |

## omamobile.quicksettings

A sheet that slides down from the top edge over the status bar, styled as an
Omarchy popup (popups background and border). It opens collapsed, as on
Android: a clock and date header, the first four tiles and brightness. A pull
down on the sheet (or a tap on the handle at its foot) expands it to every
tile, eight to a page in two columns with a sideways swipe between pages,
then brightness and volume. Tap the scrim, swipe the sheet up, or press Escape
to close it.

The pencil under the expanded grid opens edit mode: tap a tile to remove it,
hold one and drag to move it, tap one under "Add tiles" to add it; Reset (two taps) puts
the default back, Done (or Escape) leaves. The layout is per user, in
`~/.config/omamobile/quicksettings.json` (`{"version": 1, "tiles": [ids]}`,
rules and default in `TilesModel.js`, tests in `test/tiles-model.js`). Edits
to the file by hand show on the next refresh.

Default order: Wi-Fi, Bluetooth, Do not disturb, Torch (the collapsed row),
Mobile data, Rotation lock, Airplane mode, Location, Battery saver, Dark
theme, Night light, NFC, Fingerprint, Keyboard, Clipboard, Dictation.
Hotspot, Stay awake, Microphone, Screenshot and Screen record start under
"Add tiles". A user who saved a layout before Clipboard and Dictation
existed finds them under "Add tiles" too.

| Tile | Backend |
| --- | --- |
| Wi-Fi | `Networking.wifiEnabled` (NetworkManager); status shows the SSID. The chevron or a long-press opens the Wi-Fi picker (below) |
| Bluetooth | `omarchy-bluetooth-power on/off`, the same rfkill path as Omarchy's Bluetooth panel. The chevron or a long-press opens the Bluetooth panel (below) |
| Mobile data | `omamobile-sit data on/off` (omamobile-modem-sit), which starts or stops `omamobile-sit-data.service` through polkit; on while that unit is active, with the operator and technology from `/run/omamobile-sit/state.json`. "No modem" until omamobile-sitd publishes that file |
| Airplane mode | Wi-Fi, Bluetooth and WWAN rfkill switches together; on when all are soft-blocked. Turning it off unblocks only the ones that were on (`~/.local/state/omamobile/airplane-restore`). NFC keeps its own tile, and the modem's radio (`omamobile-sit radio`) is not touched, since turning that back on needs a reboot today |
| Hotspot | `nmcli device wifi hotspot con-name Hotspot` (NetworkManager makes the SSID and password; the Wi-Fi client link drops while it runs) and `nmcli connection down Hotspot`. Long-press opens the Wi-Fi picker |
| Battery saver | power-profiles-daemon's `power-saver` profile, through `omarchy-powerprofiles-set autodetect power-saver/balanced` (remembered per AC or battery) |
| Dark theme | Swaps between the user's last dark and last light Omarchy theme (`omarchy-theme-set`; defaults Tokyo Night and Catppuccin Latte, choices kept in `~/.local/state/omamobile/theme-{dark,light}`). Long-press opens Omarchy's theme picker |
| Night light | `omarchy-toggle-nightlight` (hyprsunset); "No hyprsunset" without it |
| Stay awake | `omarchy-toggle-idle stay-awake/allow-idle`, Omarchy's idle indicator. It also keeps the phone out of sleep: `omamobile-sleepd` refuses while it is on, even with the screen off (a download, a long task) |
| Microphone | Mute of PipeWire's default source; "No microphone" without one |
| Screenshot | Puts the sheet away, then `omarchy-capture-screenshot fullscreen` (file, clipboard and a notification) |
| Screen record | `omarchy-capture-screenrecording --fullscreen`, a second tap `--stop-recording`; "No recorder" without gpu-screen-recorder |
| Location | `omamobile-gnss on` and `off` (omamobile-gnss), through polkit; "In use" while the receiver runs, "No GNSS" without the command or the vendor files |
| NFC | the controller's rfkill switch (`rfkill block nfc`, `rfkill unblock nfc`); "No NFC" until a controller probes (RADIOS-CAMERA-PLAN section 3) |
| Rotation lock | `omamobile-autorotate` (omamobile-sensors): locked by `~/.local/state/omamobile/rotation-lock`; unlocking also enables the service. "No sensor" while the sensor proxy has no accelerometer |
| Torch | The rear flash LED in torch mode (`brightnessctl --device=white:torch`); "No flash LED" without it |
| Do not disturb | The notification service's `notifications` IPC target on this shell instance |
| Clipboard | Puts the sheet away and opens Omarchy's clipboard history (`omarchy-shell shell summon omarchy.clipboard`, Super+Ctrl+V on the desktop); a pick pastes into the app underneath |
| Dictation | voxtype (`voxtype record start`, a second tap `record stop`); a start puts the sheet away so the words land in the app underneath. "Listening" while it records, "Transcribing…" after. voxtype is an optional Omarchy install (Install > AI > Dictation): "Not installed" without it, "Not running" while `voxtype.service` (user) is inactive |
| Keyboard | Shows or folds the on-screen keyboard (squeekboard's `sm.puri.OSK0` `SetVisible`); "No keyboard" without it on the session bus |
| Fingerprint | Opens fingerprint setup (`omamobile.fingerprint`); the status counts this user's fingerprints through fprintd (`omamobile-fp-enroll list`); "No sensor" without fprintd or its device |
| Brightness slider | `brightnessctl --class=backlight` (the panel backlight; dimmed when there is none) |
| Volume slider | PipeWire default sink; tap the speaker glyph to mute |

Tiles whose backend is missing render a dimmed glyph and name over a readable reason ("No modem",
"No sensor", "No flash LED") and ignore taps. The tiles without a Quickshell
service read their state in one pass of `tile-state.sh` each time the sheet
opens and after each change, and switch through `tile-action.sh`; both sit
beside the QML and are tested against fake commands in
`test/tile-scripts.sh`.

The plugin is `keepLoaded` so the sheet can animate out before it unmaps.

### Settings and the notification shade

The gear at the right of the sheet's header (44 px) puts the sheet away and
opens Omarchy's menu at its root (`omarchy-menu summon root`): Setup, Style,
Install, Update and the rest, which the phone otherwise reaches only from
Power's hold menu (TOUCH-PLAN 1.3).

Under the sheet, a second card is the notification shade (TOUCH-PLAN 1.1).
It lists Omarchy's notifications, newest first: the toasts on screen and the
history (Omarchy keeps ten), each with its glyph, app, age, summary and two
lines of body as plain text. Omarchy's notification IPC can replay the
history as toasts (`showHistory`) but returns none of it, so the shade reads
the files the service keeps, `~/.local/state/omarchy/notifications/*.json`
and `history/*.json` (format and rules in `NotificationsModel.js`, tests in
`test/notifications-model.js`), when the sheet opens and every 3 s while it
is open. A tap on a row puts the sheet away and runs what a tap on the toast
runs: Omarchy's own action for its toasts (the `omarchy-exec-argv` hint the
file keeps), otherwise `omarchy-hyprland-focus-app <app>`. Other senders'
live actions die with the toast, so they can't be run from history.

**Clear all** (44 px, two taps: the first turns it into "Clear all?" for 4 s)
calls the notification service on this shell instance, `dismissAll` (the
toasts on screen move into history) and then `clear` (history is emptied).
The card takes the room left under the sheet and scrolls past that; it hides
in edit mode, or when the sheet leaves no room for it.

### Wi-Fi picker

`WifiPanel.qml`, after Android's Internet panel. A tap on the Wi-Fi tile still
toggles the radio; the chevron at the tile's right edge, or a long-press
anywhere on it, swaps the sheet for the picker. It is its own window on the
top layer with normal exclusion (like the launcher's drawer), so it sits
between the status bar and the on-screen keyboard. The back glyph returns to
quick settings; tapping outside or Escape closes it.

* **Use Wi-Fi** switch, then the connected network, then everything in range
  strongest first, with a signal glyph and a lock on secured networks. Saved
  profiles show "Saved"; saved profiles out of range get their own section.
* **Rescans** on open, from the refresh glyph, and on a pull-down of the list.
* **Tap** an open or saved network to connect; a secured new one asks for the
  password in a sheet (masked, with show/hide, Connect/Cancel, Enter submits)
  above the on-screen keyboard. Failures show in a banner and on the row; a
  wrong password reopens the sheet.
* **Long-press** a connected or saved network (or tap the connected one) for
  Disconnect and Forget.

Backends: `Quickshell.Networking` for the device (found by type, never by
name), the scanner, `connect()`, `connectWithPsk()`, `disconnect()`,
`forget()` and `connectionFailed`. nmcli covers what it lacks: saved profiles
out of range (`nmcli -t -f NAME,UUID,TYPE connection show`, forgotten with
`nmcli connection delete uuid`), and connecting with a password on a
Quickshell without `connectWithPsk`, where the password goes to
`nmcli --ask` on stdin. The password is never in argv or the log. The pure
logic (sorting, signal buckets, sections, nmcli parsing, failure text) is in
`WifiModel.js`, tested by `test/wifi-model.js`.

Limits: hidden networks and 802.1X (enterprise) networks can't be joined from
here yet; an out-of-range saved profile is matched to its network by profile
name, which is the SSID unless someone renamed it.

### Bluetooth panel

`BluetoothPanel.qml`, built the same way: a tap on the Bluetooth tile still
toggles power (through `omarchy-bluetooth-power`), the chevron or a
long-press opens the panel, the back glyph returns to quick settings.

* **Use Bluetooth** switch, then **Make visible to other devices** with the
  phone's own name; visibility lasts two minutes (a countdown shows) and ends
  when the panel closes.
* **Paired devices**: connected first, then by name, with battery when BlueZ
  has it. **Available devices**: what discovery finds, named devices strongest
  first; address-only devices fold behind "Show N unnamed devices". Discovery
  runs only while the panel is open; the refresh glyph restarts it.
* Icons come from the LE appearance, then the class of device, then BlueZ's
  icon name: headphones, speaker, keyboard, mouse, gamepad, phone, computer,
  watch, or a plain Bluetooth glyph.
* **Tap** an available device to pair, trust and connect; a paired one to
  connect; the connected one for its actions. **Long-press** a paired device
  for Connect/Disconnect, Rename and Forget. Failures (pairing failed or
  rejected, connection refused, out of range, timeouts) show in a banner and
  on the row.
* **Pairing prompts**: Just Works needs nothing; numeric comparison shows the
  six digits with Pair/Cancel; a keyboard shows the passkey to type, lighting
  up digits as they're typed; a PIN or passkey request gets a field above the
  on-screen keyboard. A device pairing *to* the phone gets the same sheets.

Quickshell.Bluetooth provides the devices, power, visibility, disconnect,
forget and rename, but no pairing agent, RSSI, device class or failure
reasons. So while the panel is open it runs `omamobile-bt-agent` (python3
with python-dbus and python-gobject): it registers a KeyboardDisplay agent as
the default, holds the discovery session (BlueZ ends it when the helper
exits), reports RSSI/appearance/class, and runs Pair, Trusted and Connect so
errors come back with BlueZ's reason. It talks JSON lines on stdin/stdout;
PINs travel only over stdin and D-Bus and are never printed. If the helper
can't start, the banner says so and the panel falls back to Quickshell's own
discovery and Just Works pairing. The pure logic is in `BluetoothModel.js`
(`test/bluetooth-model.js`); the helper's pure parts are tested by
`test/bt-agent.py`.

Limits: no file transfer or per-profile toggles (media/calls); the panel only
answers the agent while it is open, so pairing *to* the phone needs the panel
up (which visibility does anyway).

IPC:

| Call | Effect |
| --- | --- |
| `omarchy-shell shell toggle omamobile.quicksettings '{}'` | Open or close |
| `omarchy-shell shell summon omamobile.quicksettings '{}'` / `hide omamobile.quicksettings` | Open / close |
| `omarchy-shell shell call omamobile.quicksettings state ''` | JSON: open state, Wi-Fi, Bluetooth, DND, brightness, volume |
| `omarchy-shell shell summon omamobile.quicksettings '{"page":"wifi"}'` | Open the Wi-Fi picker |
| `omarchy-shell shell call omamobile.quicksettings openWifi ''` | The same; returns the picker's state, or `unavailable` |
| `omarchy-shell shell call omamobile.quicksettings wifiPanel ''` | JSON: picker open, device, connected SSID, networks in range, saved out of range, action, failure, sheet |
| `omarchy-shell shell summon omamobile.quicksettings '{"page":"bluetooth"}'` | Open the Bluetooth panel |
| `omarchy-shell shell call omamobile.quicksettings openBluetooth ''` | The same; returns the panel's state, or `unavailable` |
| `omarchy-shell shell call omamobile.quicksettings bluetoothPanel ''` | JSON: panel open, adapter name, power, discovering, visible, helper, paired, available (with RSSI and type), unnamed count, action, failure, sheet, pairing phase |
| `omarchy-shell shell call omamobile.quicksettings toggleTile <name>` | Same as tapping a tile, shown or not. Names are the ids in `TilesModel.js`: `wifi`, `bluetooth`, `mobile-data`, `airplane`, `hotspot`, `dnd`, `torch`, `rotation-lock`, `location`, `nfc`, `battery-saver`, `dark-theme`, `night-light`, `stay-awake`, `mic`, `screenshot`, `screen-record`, `fingerprint`, `keyboard`, `clipboard`, `dictation`. Returns the new state, `unavailable` or `unknown` |
| `omarchy-shell shell summon omamobile.quicksettings '{"expanded":true}'` / `'{"page":"edit"}'` | Open expanded / in edit mode |
| `omarchy-shell shell call omamobile.quicksettings showPage <n>` | Expand and show page n (from 0) |
| `omarchy-shell shell call omamobile.quicksettings tiles ''` | JSON: every tile with shown, available, enabled and status |
| `omarchy-shell shell call omamobile.quicksettings setTiles 'wifi torch dnd'` | Save a layout (space-separated ids: `qs ipc` splits arguments on commas); `resetTiles ''` saves the default |
| `omarchy-shell shell call omamobile.quicksettings notificationRows ''` | JSON: the shade's rows as last read |
| `omarchy-shell shell call omamobile.quicksettings clearNotifications ''` | Clear all, without the confirming tap |
| `omarchy-shell shell call omamobile.quicksettings openSettings ''` | The gear: Omarchy's root menu |

## omamobile.launcher

The home surface, after Omalauncher: one bar along the bottom of the screen.

* **Dock (always on screen).** A search pill, "Search apps or ask Claude…",
  in a bar-coloured strip that reserves its height so windows tile above it.
  Tapping it opens the drawer.
* **Home pill (over an app, where the dock is hidden).** A light bar with a
  dark outline, so it shows over dark and light apps, at the bottom middle.
  Swipe up from it to go home; swipe up and hold, or further, for recent apps.
  The swipe may start anywhere in a 240x44 px strip around it (an input mask:
  the rest of the bottom edge stays the app's, but the app loses taps in that
  strip).
* **Under the keyboard.** While squeekboard is up over an app, the masked
  strip gives way (it would take the bottom row's keys) and the pill moves
  into a 32 px bar-coloured strip of its own under the keyboard, as Android's
  gesture bar does. The same swipes work from anywhere along it. Bottom to
  top:

  ```
  +-----------------------------+
  | app (resized above both)    |
  | [hide-keyboard button]      |  omamobile-osk-hide, overlay, normal exclusion
  +-----------------------------+
  | squeekboard                 |  "osk", top layer, reserves its height
  +-----------------------------+
  |         ==========          |  omamobile-home-strip, bottom layer, 32 px,
  +-----------------------------+  reserves its height
  ```

  The strip is on the bottom layer and reserves its height (an exclusive
  zone). Hyprland lays out the surfaces that reserve space layer by layer
  from the bottom, so the strip takes the screen's edge first and the
  keyboard sits right above it, as it sits above the dock on the home
  screen; the strip covers no key, and a swipe that starts in it stays its
  own as the finger crosses the keyboard. It isn't shown for a fullscreen
  window, with the drawer open, or under the lock screen's keyboard (asked
  through `omarchy-shell lock isLocked` each time the keyboard comes up).
  The log names where a swipe started:
  `omamobile-home-indicator: swipe -142 recents (keyboard)`, or `(pill)`.
* **Drawer.** The app grid (4 columns of 44 px icons with names) under the
  status bar, with the one input at the bottom, focused. Typing filters the
  grid; while searching, results stack upward from the input so the best match
  sits by your thumb, highlighted. Pull the header down, or the grid when it
  is scrolled to its top, past about 80 px to close it (the drawer follows the
  finger); the chevron at the top right still closes it too.
* **Ask the agent.** Any text also offers an "Ask Claude" row above the input.
  Text that reads as a prompt (3+ words, ends in `?`, `.` or `!`, or matches no
  app) makes that row the primary action: it is highlighted, the input glyph
  turns into the agent, and Enter asks the agent instead of launching the top
  app. Asking runs `terminalCommand + agentCommand + [prompt]`, with the prompt
  as a single argv element (no shell parsing), then closes the drawer.

Apps come from Omarchy's application library (`services/AppLibrary.qml`): the
same entries, hidden-entry filters and icon index as the Omarchy menu. They
start the same way too (`uwsm-app -- gtk-launch`), but through
`omamobile-launch`, so each app gets a screen of its own (below).

Settings: defaults are in `manifest.json` under `settings.defaults`; override
any of them on the plugin's entry in `shell.json`, which the launcher watches:

```json
{ "id": "omamobile.launcher", "agentName": "Codex", "agentCommand": ["codex"],
  "agentIcon": "shell/plugins/agents/assets/codex.svg" }
```

| Key | Default | |
| --- | --- | --- |
| `agentName` | `"Claude"` | Shown as "Ask <name>" |
| `agentCommand` | `["claude"]` | The prompt is appended as one argument |
| `agentIcon` | `"shell/plugins/agents/assets/claude.svg"` | Absolute, or relative to `$OMARCHY_PATH` (reuses the Agents plugin's marks) |
| `terminalCommand` | `["xdg-terminal-exec"]` | |
| `columns` | `4` | 3 to 6 |
| `sentenceWords` | `3` | Word count at which text counts as a prompt |

IPC:

| Call | Effect |
| --- | --- |
| `omarchy-shell shell summon omamobile.launcher '{"query":"fix the tests"}'` | Open the drawer, optionally pre-filled |
| `omarchy-shell shell hide omamobile.launcher` | Close the drawer (the dock stays) |
| `omarchy-shell shell call omamobile.launcher search <text>` | Open and type; returns the mode (`apps`/`agent`) and the top app ids |
| `omarchy-shell shell call omamobile.launcher ask <prompt>` | Ask the agent directly |
| `omarchy-shell shell call omamobile.launcher state ''` | JSON: open state, query, mode, app count, agent argv |

Long-press an app in the drawer to put it on the home screen
(`omamobile.home addApp`).

## One app per screen

As on Android, every app gets the whole screen. Each launch from the phone
shell goes to a new empty workspace, and an app that is already open is
brought back instead of opening a second window beside the one you're
looking at. `bin/omamobile-launch` does it for every path: the drawer and
search results, home-screen apps, widgets (`host.launch`, `host.openUrl`, the
ported widgets' links and "↗" buttons, a text widget's tap), the agent
prompt, NFC links and the Create-a-widget agent.

* **New apps** start through Hyprland's exec with a per-launch rule,
  `hyprctl eval 'hl.exec_cmd(CMD, { workspace = "empty" })'` (Hyprland 0.56's
  Lua API; `hl.exec_cmd(cmd, rules)` in `/usr/share/hypr/stubs/hl.meta.lua`).
  The rule follows the started process (Hyprland's `HL_EXEC_RULE_TOKEN` in its
  environment, through `uwsm-app` and `gtk-launch`), so the app's own dialogs
  open on its screen and nothing else moves. Apps that slip past the token
  (D-Bus activated ones such as Files) still land on an empty screen: a launch
  from a screen that holds windows first goes to an empty workspace.
* **Open apps** are focused on their own screen instead: a window whose class
  matches the desktop entry (`StartupWMClass`, the desktop id, its last
  reverse-DNS part, Exec's program; web apps by their `chrome-<host>_` class).
  Terminals (and `omamobile-launch app --new`) always open a new window, each
  on its own screen. Links open in the running browser, shown first.
* **Clear all** in recent apps takes two taps (the first turns it into
  "Close N apps?" for 4 s), closes every window, then leaves recent apps.
  Each window gets the foreign-toplevel close request; one still open 2 s
  later gets Hyprland's (`hl.dsp.window.close({ window = "address:…" })`).
  The log says `omamobile-switcher: clear all, closing N windows`, and
  `… N still open, closing through Hyprland` when the second request was
  needed. The bottom buttons take their taps with an exclusive TapHandler,
  in a band that swallows touches: under touch (not a mouse), a passive
  TapHandler let the tap reach the tap-to-dismiss area under them too, which
  closed recent apps and disarmed Clear all before it could close anything.
  `test/switcher-touch` taps them with a finger, offscreen.
* **Together on request.** In recent apps, hold a card: **Show with…** lists
  the apps on other screens and moves this one onto the one you pick, where
  the two tile as Omarchy tiles them; **Move to its own screen** (shown when
  the app shares one) gives it a new empty workspace. Both act on the
  window's Hyprland address (`hl.dsp.window.move({ window = "address:…",
  workspace = … })`). Empty workspaces go away as Hyprland's always do.
* **Keyboards** keep Omarchy's workspace bindings (Super+1…9, Super+Shift+1…9
  and the rest) unchanged.

## omamobile.home

Home screens, after Android launchers (Omalauncher's widget pages, the Pixel
Launcher's grid and edit mode): pages of app shortcuts and widgets on the
wallpaper, swiped sideways, with page dots above the dock.

![Home screens](../../../phone/screenshots/home-screens.png)
![Edit mode](../../../phone/screenshots/home-screens-edit.png)

* **Pages.** Swipe sideways; tap a dot to jump. The home page (Home in recent
  apps goes back to it) is marked in the Pages sheet.
* **Grid.** 4 columns by 6 rows by default (3-6 by 4-8, set in Pages). Apps
  take one cell, widgets a span within their own limits.
* **Apps** launch the way the drawer does (`omamobile-launch app`: Omarchy's
  `uwsm-app -- gtk-launch`, on a screen of their own). An app that is no longer
  installed stays, dimmed, until you remove it: its package may come back.
* **Edit mode.** Long-press anywhere (empty space, an app, a widget). Then
  drag an item to move it (dropped on an item of the same size, the two swap;
  on a bigger one, it takes the nearest free cell; dragged past the left or
  right edge, it moves to that page, making a new page on the right), drag
  the round corner handle to resize a widget, tap the cross to remove (an
  **Undo** chip stays for 5 seconds and puts the item back, with its
  settings, where it was or in the nearest free cell), tap a
  widget for its settings. The toolbar: **Widgets** and **Apps** add to the
  page on screen (or the next one with room), **Wallpaper** opens Omarchy's
  Style menu (what the desktop's long-press opened before this surface
  covered it, `patches/omarchy/0005`), **Pages** adds, removes, reorders and
  picks the home page and sets the grid size, **Done** (or a tap on empty
  space, or Escape) ends it. Swipe empty space to change page while editing.

| Widget | Sizes | What it shows |
| --- | --- | --- |
| Clock | 2x1-4x3 | Time and date, Qt formats in its settings |
| Weather | 2x1-4x2 | Off until turned on with a place; then Open-Meteo (below) |
| Battery | 1x1-4x2 | UPower's display device: level, charging, time left |
| Media | 3x1-4x2 | MPRIS: cover, title, artist; previous, play/pause, next |
| Calendar | 2x2-4x4 | The next 7 days from khal when it's installed, else the month |
| Note | 1x1-4x6 | Your text, kept in `home.json`; tap to edit |
| Quick toggles | 2x1-4x2 | Wi-Fi, Bluetooth, do-not-disturb (quick settings' own `toggleTile`) and More |
| Text or command | 1x1-4x6 | Fixed text, or the first lines of a command run every N s (at least 30, killed after 10 s); optional tap command |

Privacy. Only the weather widget uses the network, and only after you turn
it on in its settings: it asks Open-Meteo's geocoder for the place's
coordinates once, then for that point's forecast every 30 minutes, with the
coordinates rounded to about 1 km. No key or account. Location from GeoClue
(`omamobile-gnss`) is not used: a typed place needs no location permission
and no GNSS power. The calendar reads khal's local store; syncing it is
vdirsyncer's job. The text/command widget runs only what you typed into your
own `home.json`.

Storage. `~/.config/omamobile/home.json`, written atomically 300 ms after an
edit and watched, so a hand edit shows up at once. `HomeModel.js` documents
the format and repairs what it reads: unknown widgets and broken items are
dropped, sizes are clamped, overlapping items move to the first free cell.
An unreadable file is left alone and the default is shown; the next edit
saves the old file as `home.json.bad` first. The first start puts a clock and
the first four of a short list of installed apps on page 1, and the media and
battery widgets on page 2.

Why a layer surface and not Hyprland workspaces. Each page could be an empty
workspace with a widget layer per workspace, and Hyprland would animate the
swipe. But workspaces are where apps live: an app opened from page 2 would
land on "page 2" and vanish from page 1, the switcher and `goHome` (which
focuses an empty workspace) would fight over what a page is, and Hyprland's
workspace swipe follows the whole screen, not a finger on the wallpaper. So
there is one surface on the bottom layer (above the wallpaper on the
background layer, below every window, between the bar and the dock by
normal exclusion), it shows on whichever empty workspace you're on, and the
pages are a `ListView` inside it. Apps cover it when open; nothing renders
while they do.

Smoothness. Widgets are plain rectangles and text: no blur, shadow or
`layer.enabled`, and only the clock (once a minute), the media widget (while
playing) and the toggles' do-not-disturb poll (30 s) change while you look.
Every layout edit rebuilds the page's delegates, so the weather answer and
command output are cached per widget id and an edit is not a new request.

Fingerprint. No long-press while a fingerprint operation runs, or while the
finger that reached the sensor is still down, nor for 1.5 s after: the same
state file (`/run/omamobile-fp-ui/state.json`, or `OMAMOBILE_FP_UI_STATE`)
the fingerprint plugin reads. Its desktop guard also maps above this surface
on the bottom layer while an operation runs.

IPC (`omarchy-shell shell call omamobile.home <method> <arg>`):

| Method | Effect |
| --- | --- |
| `state ''` | JSON: loaded, path, page, pages, home page, grid, editing, sheet, items per page, missing apps |
| `dump ''` | The layout as stored |
| `goHome ''` / `page <n>` | Show the home page / page n (from 0) |
| `edit on` / `edit off` | Enter (returns `busy` during a fingerprint operation) or leave edit mode |
| `undo ''` | Put back the item removed last, while its Undo chip shows; `none` otherwise |
| `addApp <desktop id>` / `addWidget <type>` | Add to the page on screen; returns the new item's id or `full` |
| `showSheet widgets\|apps\|pages\|create` / `settings <item id>` | Open an edit sheet / a widget's settings |
| `widgets ''` / `widgetStatus <id>` | JSON: the user's widgets (or one) with status, errors, warnings, capabilities, undeclared capabilities, hash, folder and how often it is placed |
| `rescanWidgets ''` | Scan `~/.config/omamobile/widgets` now |
| `createWidget <description>` / `editWidget <id>` | What Create / Edit with AI do: make the folder, place it, start the agent |
| `copyExample <id>` / `removeUserWidget <id>` | Copy an installed example into your widgets and place it / move a widget folder out and take it off every page |
| `addWidget user:<id>` | Place one of your widgets |

`omarchy-shell shell summon omamobile.home '{"edit":true}'` and
`'{"page":1}'` do the same through the host. The pure logic (grid placement,
moves, swaps, resizes, pages, persistence, the weather and khal parsing) is
in `HomeModel.js`; the user widgets' side (the scan, prompts, helper argv,
settings, the command limits) in `UserWidgets.js`. Both are tested by
`test/home-model.js`, and `bin/omamobile-widget` by `test/widget-tool.py`.

### Your own widgets

![Your own widgets, one with an error](../../../phone/screenshots/home-user-widgets.png)
![The Widgets sheet](../../../phone/screenshots/home-user-widgets-sheet.png)
![Create a widget with AI](../../../phone/screenshots/home-widget-create.png)

Users build their own widgets the way Omarchy desktop users build their own
bar widgets and panels: a folder with a `manifest.json` (Omarchy's plugin
manifest, kind `home-widget`, with a `homeWidget` block shaped like
`barWidget`: sizes in cells, capabilities, `defaults` and a settings
`schema` in Omarchy's field format) and the QML it names, drawn with
`qs.Commons` so theme switches restyle it. [`WIDGETS.md`](../widgets/WIDGETS.md)
is the contract, written for people and for coding agents.

* **Where.** `~/.config/omamobile/widgets/<id>/`, not
  `~/.config/omarchy/plugins/`: a widget isn't a shell plugin (the home
  screen hosts it, in a card, once per placement), and a save under
  Omarchy's plugin folder reloads every plugin, quick settings included.
  The folder is watched the way Omarchy's `PluginRegistry` watches its own
  (`inotifywait -m -r`), so a saved file shows up in under a second.
  Nothing loads from anywhere else: examples in
  `/usr/share/omamobile/shell/widget-examples/` are copied in, not loaded
  in place, and no widget code is fetched from the network.
* **In edit mode.** **Widgets** lists them under *Yours* next to the
  built-ins, placeable and resizable within their manifest's limits, with
  their settings in the settings sheet. Each is stored in `home.json` as
  type `user:<id>` with its own settings. A robot button starts the agent
  on one (**Edit with AI**), the bin (twice) removes it: its folder moves
  to `~/.local/share/omamobile/removed-widgets/` and every placement goes.
  *Examples* lists the installed examples to copy.
* **Create a widget with AI.** Asks for a description (squeekboard comes
  up), makes `<user>.<words>` from the template, places it, and starts
  Omarchy's default coding agent (the one chosen in Omarchy's menu,
  `omarchy-default-agent`) through Omarchy's own `omarchy-agent-prompt`,
  in a terminal, in the widget's folder. The prompt is the contract's path,
  the rules (only this folder, no root, declare capabilities, run
  `omamobile-widget check .`) and the description verbatim, passed as one
  argv element from the sheet to the agent: no shell sees it. With no
  default agent, Omarchy's chooser opens (`omarchy-agent --pick`) and the
  sheet says so; a chosen agent that isn't installed shows Omarchy's own
  message. Omarchy runs agents unattended, so the prompt and the contract
  both keep it to the widget's folder.
* **Checks before a new or changed widget loads** (`omamobile-widget scan`,
  cached by a hash of the folder): the manifest is valid and sizes are
  clamped to the grid; files stay inside the folder (no links out, at most
  64 files, 1 MiB); capabilities the code uses (`commands`: `Process`,
  `execDetached`, `host.run`; `network`: `XMLHttpRequest`, URLs, `curl`)
  must be declared, or the widget is not loaded and the sheet and its card
  say which is missing; no root tools, no QML from outside the folder or a
  URL; `qmllint` with the shell's `qs.` imports resolved finds no syntax
  errors, unknown types or properties. Effects, fast timers and endless
  animations are warnings.
* **Isolation.** Each placed widget loads in `UserWidgetCell.qml`: the
  component is compiled first and created with its properties set; any
  failure (the scan's errors, a compile error, a creation error) becomes an
  error card with the message in that cell only, and a tap opens its
  settings with Edit with AI (which passes the errors to the agent). The
  URL carries the folder's hash and the component cache is cleared, so
  edited code really reloads. A user widget whose folder is missing or
  broken stays in `home.json` with its size and settings. Widgets get a
  narrow `host` (`WidgetHost.qml`), not the home screen: colours, the
  system clock format, settings, a cache that outlives layout edits, and
  `run()` / `launch()`, which refuse without a declared `"commands"`, run
  argv without a shell under `timeout` (10 s default, 30 s at most), one at
  a time and at most one every 2 s per widget. These are guard rails, not a
  sandbox: like any Omarchy plugin, a widget runs in the shell as the user
  (never root).

## omamobile.fingerprint

The under-display fingerprint sensor in the shell, after Android. Three
surfaces, all driven by `omamobile-fp-bridge` (omamobile-fingerprint):

* **Target.** While an enrollment or a verification runs (`fprintd-verify`,
  the lock screen's fingerprint conversation, `pam_fprintd` for sudo or
  polkit), a faint fingerprint in a ring sits exactly over the sensor. Its
  window's input region is the circle the bridge reacts to (1.5 sensor
  radii), so a finger there reaches nothing in the shell. When no operation
  runs, nothing is mapped.
* **Desktop guard.** While any operation runs, a transparent surface on the
  bottom layer (just above the wallpaper, in the area the bar and dock leave
  free) takes the touches that would reach the desktop, so its long-press
  menu can't open. Windows, the bar, the dock and panels sit above it. After
  an operation ends it stays until the touch that reached the sensor lifts
  (the bridge's `contact`) plus 500 ms, at most 10 s: the finger that
  unlocked the phone is often still down when the lock goes away.
* **Enrollment.** A full-screen flow on the overlay layer: an intro (how
  many fingerprints are added, Delete all), then "Touch the sensor" with the
  glyph breathing at the sensor, a progress ring around it, the stage's
  words ("Lift, then touch again"; past half, "Now place the edges of your
  finger"), the HAL's hint for the last touch, and "Fingerprint added" (Add
  another, Done) or a readable error (Try again). Cancel stops it. Opened
  from the Fingerprint tile in quick settings, Omarchy's Setup > Security >
  Fingerprint (`omamobile-setup-user` points it here), or
  `omarchy-shell shell summon omamobile.fingerprint '{"page":"enroll"}'`.

Data. The bridge serves one client, fprintd, which keeps each user's prints
(an enrollment made straight through the bridge is invisible to fprintd and
the lock). So enrollment goes through fprintd's D-Bus API:
`bin/omamobile-fp-enroll` claims the default device (polkit asks first),
reports `claimed` once polkit is answered (until then the enrollment
screen is unmapped, so Omarchy's password prompt and the on-screen keyboard,
which draws under overlay layers, stay usable; the same for Delete all),
picks the next free finger (index fingers, then thumbs, ...), runs
`EnrollStart` and reports `EnrollStatus` as JSON lines; `list` and
`delete-all` do the rest. What fprintd doesn't carry comes from the bridge's
state file, `/run/omamobile-fp-ui/state.json` (world-readable, replaced with
`rename(2)`, removed when the stack stops):

```json
{"op":"enroll","finger":false,"x":717,"y":2360,"r":121,"w":1440,"h":3120,
 "seq":7,"acquired":1,"remaining":24,"error":0,"last":"none"}
```

`op` is `idle`, `enroll` or `auth`; the circle is in panel pixels of the
portrait `w`x`h` panel; `acquired`, `remaining` and `error` are the HAL's last
AcquiredInfo, samples left and Error of the current or last operation, `seq`
counts them. The ring follows `remaining` (the HAL needs about 15 samples,
two counts each); without it, fprintd's stages (20, from our driver) stand
in. Hints follow `acquired` (PARTIAL/INSUFFICIENT: press your whole finger;
SENSOR_DIRTY: clean the screen; IMMOBILE: move your finger slightly; ...),
else fprintd's retry results. Errors use the HAL's code when this
enrollment produced one (TIMEOUT: "Time's up"), else fprintd's result. The
pure logic is in `SensorModel.js` (`test/sensor-model.js`), the helper's in
`test/fp-enroll.py`.

Placement. Panel pixels scale by the screen's logical size (480/1440 at
scale 3) and follow Hyprland's transform for the panel (0-3, as
`omamobile-autorotate` sets them); a flipped transform or a screen of another
shape hides the target. Before the bridge has written its file once, the
enrollment screen uses stock cheetah's sensor (717, 2360, radius 121).

On-screen keyboard. While squeekboard is unfolded (its `sm.puri.OSK0`
`Visible` on the session bus, through `bin/omamobile-osk-watch`; Hyprland's
layer events did not arrive while locked), the target hides
(it would sit on the keys) and the plugin keeps
`/run/omamobile-fp-ui/inhibit/osk-<user>` fresh (every 5 s; removed when the
keyboard hides), so the bridge takes no key over the sensor for a finger: no
LHBM, no capture, no failed attempt. The bridge ignores files older than
15 s.

Finger down. The panel lights its own circle (LHBM) under the finger, so
the glyph fades out; that follows the bridge's touch state, not LHBM, and
works the same with `allow_lhbm=0`.

Lock screen. Hyprland draws layer surfaces above a session lock only with
the `above_lock` layer rule; `hypr/phone.lua` sets it to 1 for the target's
namespace `omamobile-fingerprint`: drawn above the lock, but without input
there (2 would also take input). It needs none: the bridge reads the
touchscreen itself, and Omarchy's PIN pad (`patches/omarchy/0003`) keeps the
lower third of the screen clear once fingerprints are set up, with "Touch the
fingerprint sensor or enter your PIN" above the field. A touch on the sensor
lands on the lock's background, which only wakes the screen.

IPC:

| Call | Effect |
| --- | --- |
| `omarchy-shell shell summon omamobile.fingerprint '{"page":"enroll"}'` | Open enrollment |
| `omarchy-shell shell call omamobile.fingerprint state ''` | JSON: bridge op, finger, placed sensor, transform, target/guard shown, enrollment page, progress, hint, fingers |

The desktop harness can fake the bridge: `OMAMOBILE_FP_UI_STATE=<file>`
points the plugin at another state file, and a stub `omamobile-fp-enroll`
earlier in `PATH` stands in for fprintd.

## omamobile.keyboard

While squeekboard is unfolded (`sm.puri.OSK0` `Visible`, through
`bin/omamobile-osk-watch`), a 44 px keyboard-close button sits right above the
keyboard's top-left corner; a tap folds it (`SetVisible false`). It is on the
left because apps put Send and Next at the bottom right, where it used to
cover them. The window
is the button only (anchored bottom-left with normal exclusion, so the
compositor puts it just above the keyboard's reserved area), on the overlay
layer, without keyboard focus; `hypr/phone.lua` lets it work over the lock
(`above_lock = 2`). Quick settings has a Keyboard tile that shows or folds the
keyboard on demand (showing closes the sheet).

IPC: `omarchy-shell shell call omamobile.keyboard showKeyboard|hideKeyboard|toggleKeyboard|state ''`
(not `show`/`hide`: the IPC command line takes `show` for itself).

## omamobile.back

The back gesture, as on Android: swipe in from the left or right edge and let
go once the arrow fills in (about 56 px in, more across than along the edge).
Back is Escape, sent through Hyprland's own dispatcher
(`hl.dsp.send_key_state`, a key down and a key up 50 ms later, as Omarchy's
clipboard bindings send keys) to whatever has the keyboard focus: an app's
dialog, menu or popover, a terminal app, or a shell sheet or the drawer. A
sheet that doesn't take the keyboard (the home screen's Widgets and Pages
sheets) closes with a tap outside it instead.

Each edge is a 14 px strip on the overlay layer, masked like the home pill,
in a window wide enough to draw the arrow that follows the finger. Normal
exclusion keeps the strips between the status bar and the on-screen keyboard
(or the dock), so they never take the keyboard's edge keys. They hide for a
real fullscreen window, as the home pill does, and aren't shown over the
lock. A page swipe on the home screen that starts in the outer 14 px goes
back instead; start it further in.

IPC: `omarchy-shell shell call omamobile.back back ''` (the same as the
gesture) and `state ''`.

## omamobile.update

Omarchy's update in a sheet, since its terminal update (gum prompts and the
ASCII logo) doesn't fit 480 px with the keyboard up. Everything goes through
`omamobile-update` from `omamobile-omarchy` (its header and
[RELEASES.md](../../../docs/RELEASES.md) §5.4 list what it keeps and skips of
Omarchy's update).

* **Ways in:** an "Update available" toast once per Omarchy release
  (`omamobile-update notify-check`, two minutes after login and every six
  hours), Omarchy's menu Update > Omarchy (pointed here by
  `omamobile-setup-user`, which also hides Update > Firmware and Update >
  Config > Plymouth), and `omarchy-shell shell summon omamobile.update '{}'`.
  The plugin also answers Omarchy's `omarchy.system-update refresh|clear`.
* **Overview** (`omamobile-update check --json`): the Omarchy release and the
  package count, What's new (Omarchy's release notes, in the browser), the
  battery (updates need 30% or the charger), the phone patches' state, and
  anything blocking the update (battery, repository order, a kernel or
  bootloader package in the transaction, another update running).
* **PIN:** the account's PIN or password for sudo, with a 123/ABC switch,
  above the on-screen keyboard (top layer, normal exclusion). It goes to
  `omamobile-update start` on stdin, never argv or a file; a wrong one says
  so and nothing runs.
* **Progress:** the current step and line, with the whole output under
  Details. The run is a systemd user unit (`omamobile-update.service`), so
  closing the sheet doesn't stop it, and the shell restart at the end of every
  update doesn't either: the new shell's instance reopens the sheet on the
  run's progress or result.
* **Result:** updated; updated with a restart needed (Restart now runs
  `omarchy-system-reboot`); updated but the phone patches failed (the PIN pad
  may be missing; the log's path); refused; or stopped, with the log's path
  (`~/.local/state/omamobile/update/update.log`). Migrations held for review
  are listed.

IPC: `omarchy-shell shell call omamobile.update snapshot ''` (page, step,
result; never the PIN).

## omamobile.onboarding

The setup sheet (TOUCH-PLAN 1.11): the first run's questions and System >
PIN as sheets, in place of the gum prompts `omamobile-onboarding` and
`omamobile-set-pin` put in a terminal, which a touch screen can't answer
(arrow keys and Enter). `omarchy-shell shell summon omamobile.onboarding
'{}'` is the first run (name and email, then a PIN or password unless there
is one, then Omarchy's invitation to pick a default agent); `'{"page":"pin"}'`
is System > PIN (PIN or password, then the entry). The scripts open the sheet
themselves when the shell runs it (`summon` answers `ok`) and fall back to
the terminal prompts otherwise, or with `OMAMOBILE_PROMPTS=terminal`.

The scripts stay the one definition of what each answer does: the sheet
reads `omamobile-onboarding --status --json`, saves with `--identity NAME
EMAIL` (Omarchy's `git.sh` and `xcompose.sh`), invites with
`--invite-agent`, and sets the PIN with `omamobile-set-pin --apply TYPE`,
which takes the current and the new secret on its stdin (never argv, a
file or the log), drives `passwd` on a pty as the terminal flow's prompts
did, and records the choice and `lock-on-start`. Its exit code says what
happened (3 wrong current, 5 refused with the reason on stdout), and the
sheet goes back to the step that needs another answer. The fields keep to
the bottom of the card, above the on-screen keyboard, with the ABC/123
switch of the update sheet. `test/onboarding.sh` drives the entry points
against a fake `passwd`; `test/onboarding-render` draws every page.

## omamobile.access

The question xdg-desktop-portal asks before an app first uses the camera, the
location, screenshots or the wallpaper (and before a sandboxed app runs in
the background). xdg-desktop-portal-gtk asked it with a 476x920 desktop dialog
that touch didn't reach; the phone asks with a bottom sheet: the app's icon
(from its `.desktop` file) with the permission's glyph, the question in
sentence case ("Allow Camera to use the camera?"), the portal's reason, and
two full-width 56 px buttons, Allow over Don't allow (or the caller's
`grant_label`/`deny_label`, "Grant access"/"Deny access" for location).

* **The backend** is `omamobile-portal-access`, a small Python D-Bus service
  (`org.freedesktop.impl.portal.desktop.omamobile`, user unit
  `omamobile-portal-access.service`, started by D-Bus activation).
  `/etc/xdg/xdg-desktop-portal/hyprland-portals.conf` sets
  `org.freedesktop.impl.portal.Access=omamobile;gtk`; xdg-desktop-portal 1.22
  reads it before `/usr/share/xdg-desktop-portal/hyprland-portals.conf` and
  falls through to that file for every other interface, so its
  `default=hyprland;gtk` still holds (portals.conf(5)). A user's own
  `~/.config/xdg-desktop-portal/hyprland-portals.conf` comes first and can
  pick another backend.
* **The round trip:** `AccessDialog` in; `omarchy-shell lock isLocked` (a
  locked phone gets no sheet); `omarchy-shell shell call omamobile.access
  request '<json>'`; a tap runs `busctl --user call
  org.freedesktop.impl.portal.desktop.omamobile /org/omamobile/AccessSheet
  org.omamobile.AccessSheet Answer ss <id> allow|deny`; the service answers
  the portal with response 0 (Allow) or 1 (Don't allow) and the `choices`
  results at their defaults (no 1.22 portal passes any).
* **What is remembered:** the portal stores every response as the app's
  permission (0 as yes, anything else as no; `busctl --user call
  org.freedesktop.impl.portal.PermissionStore ... Lookup ss devices camera`
  shows them). So only a tap gives a response. No answer in 90 s, a locked
  phone, a shell that can't show the sheet, or the app closing its request
  gives the portal a D-Bus error instead: that request is denied, nothing is
  stored, and the app asks again next time. The sheet goes away with it
  (`shell call omamobile.access dismiss '{"id": ...}'`).
* **Where it draws:** the overlay layer, over apps, the bar and quick
  settings, but never over the lock screen (no `above_lock` rule): a sheet
  open when the phone locks waits under the lock until its 90 s run out.
  Requests queue, one sheet at a time. The scrim ignores taps: the question
  needs an answer. A shell restart loses the queue; the service's timeout
  ends those requests.

IPC: `omarchy-shell shell call omamobile.access snapshot ''`.

Tests: `test/portal-access.py` (the rewording, the `.desktop` lookup, and the
service on a private bus against a fake `omarchy-shell`: Allow, Don't allow,
choices, timeout, Close, locked, no shell), `test/access-model.js`, and
`test/access-render`, offscreen review shots in the OWL container (see its
header; `test/all` runs it when `OMAMOBILE_ACCESS_RENDER` names an output
directory).

## omamobile.call

Calls in the shell (TELEPHONY-APPS-PLAN §7.1), from omatel's agent
(`omatel-agent`, `org.omamobile.Phone1`) when it runs; without it the plugin
shows nothing. Modelled on Android's call screens in the Omarchy theme:

* **A ringing call on a locked phone** fills the screen over the lock: the
  state ("Incoming call"), the caller's initials pulsing in a ring, the name
  large with the number under it, and at the bottom a handle that **answers
  when swiped up and declines when swiped down**: a swipe, not a tap, so a
  pocket can't answer. "Reply" declines with one of omatel's canned
  messages (`quick_replies` in `~/.config/omatel/settings.toml`).
* **A ringing call on an unlocked phone**, or a second call waiting during
  one, is a heads-up card at the top with Decline and Answer; answering
  opens the Phone app's in-call screen, and a tap on the caller opens its
  answer page.
* **A call in progress on a locked phone** shows the elapsed time, mute and
  speaker toggles and a wide end button over the lock. The chevron folds it
  to a strip at the top (time and end button), so the lock's own PIN pad is
  reachable; a tap on the strip unfolds it. Unlocked, the call is the Phone
  app's.

Over the lock the plugin offers call actions only: it never opens an app
there, never dials (only the Phone app dials, with its emergency checks),
and the lock stays in place. Its windows are `omamobile-call` (full screen)
and `omamobile-call-top` (the strip), on the overlay layer, with
`above_lock = 2` in `hypr/phone.lua`.

* **Data:** `omamobile-call-watch` prints the agent's whole state (calls,
  mute, route, the replies) as a JSON line per change, lights the screen
  when a call rings (`omarchy-shell lock wake`, as the power key), and owns
  `org.omamobile.CallCard` while it runs, so the agent can tell the shell
  shows ringing calls itself. While a call rings or runs it holds a logind
  sleep inhibitor (block mode), so the phone never sleeps under a call
  (`omamobile-sleepd`, SUSPEND-PLAN 6.1). The plugin asks `omarchy-shell lock isLocked`
  once a second while a call exists.
* **Requests:** `busctl --user call org.omamobile.Phone1 … Answer|Decline|
  Hangup|SetMute|SetRoute` and `org.omamobile.Messages1 … Send` for a reply,
  never a shell (`CallModel.js`).
* **Ringing** is the agent's: feedbackd plays the sound theme's
  `phone-incoming-call` and drives the vibration motor (omatel-agent
  depends on both). During Omarchy's Do Not Disturb only starred contacts
  ring; the agent lists every other ringing call in `SilencedCalls`
  (omatel 0.2.3), and the card leaves those alone: no card, no wake, just
  the agent's quiet notification.

The status bar (`omamobile.bar`) shows the call in progress as a green chip
with its time beside the clock (a tap opens the Phone app's in-call screen),
from `omamobile-call-watch --observe` (no wake, no name), and the mobile
network from `omamobile-cell-watch`: ModemManager's API (omamobile-mmd on
the Pixel 7 Pro), as bars and the network type ("LTE", "5G", "R" when
roaming), "No SIM", "SIM locked", the airplane when the radio is off, and
nothing without a modem. Signal strength shows as empty bars until the
modem reports a reading (SIT signal strength is TELEPHONY-APPS-PLAN T8).

**Emergency call:** the lock screen's "Emergency call" button (Omarchy patch
0014, under the number pad on touch-only devices) calls `omarchy-shell shell
call omamobile.call emergency ''`, and the plugin shows, over the lock, the
warning TELEPHONY-APPS-PLAN §3.2 asks for until emergency calling has passed
its test on a carrier (§3.3): "Emergency calls (911, 112) don't work on this
phone yet. Keep another phone for emergencies." Never a dialpad, and only
Close.

IPC: `omarchy-shell shell call omamobile.call state ''` (modes and states,
no numbers or names) and `… emergency ''`.

Tests: `test/call-model.js` (modes, labels, requests, the swipe),
`test/call-watch.py` (the watcher against a fake agent on a private bus),
and `test/call-render`, offscreen shots of every state in a dark and a light
theme in the OWL container (`test/all` runs it when `OMAMOBILE_CALL_RENDER`
names an output directory).

## Testing in the desktop harness

`phone/dev/run-desktop` copies the shell and runs it in a nested Hyprland, so
point IPC at that copy and its Wayland display, never at
`/usr/share/omarchy/shell` (your real desktop):

```sh
HOME=~/android/phone-dev/home WAYLAND_DISPLAY=wayland-2 \
  quickshell ipc -p ~/android/phone-dev/shell call shell listPlugins
```

(`quickshell list --all` shows which `wayland-N` the nested shell is on.)
`WAYLAND_DISPLAY=wayland-2 grim out.png` screenshots the nested screen and
`WAYLAND_DISPLAY=wayland-2 wtype 'text'` types into the launcher.

Hot reload is not enough for every change. Relaunch the harness after:

* adding a new file to a plugin directory (Qt's type loader caches each
  directory's listing, so a file that appears later stays "No such file");
* editing a `keepLoaded` plugin (quick settings, launcher): the reload
  rebuilds it from the cached component;
* editing `phone/profile/shell.json` (it is copied at launch).

## Plugin API limits found

### Lock screen input: PIN or password

Omarchy's lock now takes a PIN on its number pad or a password on the
on-screen keyboard, with an ABC/123 switch (`patches/omarchy/0003`, `0011`);
`omamobile-set-pin` records the user's choice and sets Omarchy's
`credential-password` toggle. The polkit prompt follows the same choice
(`0010`, `0011`). The rest of this section is the history of why the lock
input lives in Omarchy rather than in a plugin.

### Lock screen PIN pad

There is no `lockpad` plugin, because a third-party plugin cannot provide the
lock screen's input without going around Omarchy's lock.

* `omarchy.lock` is a first-party `service` whose manifest carries
  `omarchy.capabilities: ["authentication"]`. The host stamps that capability
  only onto first-party manifests (and onto user clones made with
  `omarchy plugin clone`, which inherit it through `omarchy.clonedFrom`), keeps
  authentication services in a private store outside the QML object graph,
  and never hands them to other plugins' facades. Good, and intended.
* `LockView.qml` has one input: a fixed 381x67 password field driven by key
  events. There is no extension point for another input surface, and an
  on-screen keyboard is a layer-shell client that the compositor does not
  show over an `ext-session-lock` surface, so a phone with no hardware
  keyboard cannot unlock it at all.
* A plugin *could* import `Quickshell.Wayland` and `Quickshell.Services.Pam`
  and run its own `WlSessionLock`. That would be a second lock client
  competing with `omarchy.lock`: `omarchy-system-lock`, `omarchy.idle`, the
  stranded-lock recovery and the fingerprint flow all drive `omarchy.lock`, so
  the two would fight over the session. Shipping a plugin that declares
  `clonedFrom: omarchy.lock` just to inherit the capability would abuse the
  clone mechanism, which exists for a user's own copy.

What upstream needs instead, smallest first:

1. **A touch input mode in `LockView`.** A `lock.input` setting (`"password"`
   default, `"pin"`) in `shell.json` or the theme's `shell.lock.toml`. In PIN
   mode the view renders a numeric keypad (12 keys, at least 64 px on a phone)
   plus delete and enter, feeding the existing `passwordTextEdited` /
   `submitPassword` signals. PAM is unchanged: the PIN is a numeric password
   for `omarchy-lock-password`, or a separate `omarchy-lock-pin` PAM service if
   the PIN should differ from the login password. The keypad lives inside the
   session-lock surface, so no external keyboard client is needed.
2. **Or a `lock-input` plugin kind.** `omarchy.lock` loads a declared input
   component *inside* its own `WlSessionLockSurface`. The component gets a
   narrow facade (`append(char)`, `backspace()`, `submit()`, `failureMessage`,
   `authenticating`) and never the `PamContext` or the service, so the
   authentication boundary stays where it is while the input surface becomes
   replaceable.

### Smaller ones

* **Third-party `menu` plugins lose their shell facade.** In `shell.qml` the
  panel loader passes `modelData.manifest` from an `Instantiator` model to
  `pluginShellFor()`. Arrays inside `modelData` are not JS arrays
  (`Array.isArray()` is `false`), so `manifestHasKind(manifest, "menu")`
  fails: the facade is built without `appLibrary`, and on the next config
  change `prunePluginApis()` (which reads the registry's real manifest) sees a
  different capability profile and destroys the facade, leaving the plugin's
  `shell` null. The launcher therefore declares `panel` and instantiates
  Omarchy's `AppLibrary` type itself via `import qs.services`. Fix upstream:
  pass `shell.pluginRegistry.installedPlugins[panelEntry.pluginId]` to the
  loader's injections (or make `manifestHasKind` accept array-likes).
* **Panel plugins get no settings.** Inline settings on a `plugins[]` entry are
  only handed to bar widgets, so the launcher reads its own entry from
  `shell.json` with a `FileView`.
* **Panel plugins cannot reach do-not-disturb.** The host proxies
  `omarchy.notifications` only to full bars. Quick settings calls the
  `notifications` IPC target on its own shell instance (`qs ipc -p
  Quickshell.shellDir`) instead.
