# omamobile-shell

Omarchy Mobile's phone profile for Omarchy's own shell. It isn't a fork: these are ordinary Omarchy shell plugins plus a phone `shell.json`, linked into the user's config by `omamobile-setup-user`.

| Path | What it is |
| --- | --- |
| `plugins/omamobile.bar` | Phone status bar (a full `bar` plugin) |
| `plugins/omamobile.quicksettings` | Pull-down quick settings: tiles (a page behind Wi-Fi, Bluetooth, Screen record and Reminder), brightness and volume, the notification shade |
| `plugins/omamobile.launcher` | Home bar: app search, app grid and a prompt to the user's Omarchy default agent |
| `plugins/omamobile.switcher` | Recent apps: swipe up on the dock, or swipe up and hold on the home pill over an app; hold a card to show the app with another one, or give it its own screen again |
| `plugins/omamobile.home` | Home screens: pages of apps and widgets on the wallpaper, with an edit mode. The built-ins include every widget in Simon Schubert's [omarchy-widgets](https://github.com/SimonSchubert/omarchy-widgets) `widgets/simonschubert/` (MIT): the OWL originals, from the `omamobile-owl-widgets` package, run by our own OWL runtime (`owl/`, see `owl/SPEC-NOTES.md`). `widgets/OWL.md` is his OWL language guide (MIT, `widgets/LICENSE-owl-guide`) |
| `plugins/omamobile.keyboard` | Hide button above the on-screen keyboard |
| `plugins/omamobile.back` | The back gesture: swipe in from a side edge for Escape |
| `plugins/omamobile.update` | The update sheet: Omarchy's update for a phone, through `omamobile-update` (package `omamobile-omarchy`) |
| `plugins/omamobile.onboarding` | The setup sheet: the first run's questions (name and email, a PIN or password, Omarchy's agent invitation) and System > PIN, through `omamobile-onboarding` and `omamobile-set-pin`, which keep their terminal prompts as the fallback |
| `plugins/omamobile.access` | The permission sheet: "Allow Camera to use the camera?" with the app's icon and two large buttons, in place of xdg-desktop-portal-gtk's desktop dialog |
| `plugins/omamobile.fingerprint` | The under-display fingerprint sensor: target during verification, enrollment screen |
| `profile/shell.json` | The phone layout the setup seeds once |
| `bin/omamobile-setup-user` | Omarchy Mobile's per-user setup (Omarchy lifecycle `setup-user`) |
| `bin/omamobile-onboarding`, `bin/omamobile-set-pin` | First-run setup and the PIN or password: the sheet above when the shell runs it, gum prompts in a terminal otherwise; `--status --json`, `--identity`, `--invite-agent` and `--apply TYPE` (secrets on stdin) are what the sheet calls |
| `bin/omamobile-launch` | One app per screen: every launch from the shell (drawer, home screen, widgets, links, the agent) gets a new empty workspace through a per-launch Hyprland exec rule, or focuses the app's open window; and the switcher's "Show with…" and "Move to its own screen" |
| `bin/omamobile-osk-watch` | Reports squeekboard's visibility (sm.puri.OSK0) to the fingerprint plugin |
| `bin/omamobile-osk-guard` | Turns the on-screen keyboard (`screen-keyboard-enabled`) back on when it was left off with no screensaver running (a user unit for every graphical session) |
| `bin/omamobile-sleepd` | Sleep (s2idle) once the screen has been off behind a secure lock for `OMAMOBILE_SLEEP_AFTER_OFF` s (30), and again 5 s after a dark resume; `now` for the power key (`omamobile-keys`), `check` to see what holds it awake. Refuses with the screen on, Stay awake on, an SSH session open, a logind sleep block inhibitor (calls, GNSS) or a RUNNING PipeWire sink. A user unit for every graphical session, **off until `omarchy-toggle omamobile-sleep on`** (device/cheetah/SUSPEND-PLAN.md 6.2) |
| `bin/omamobile-fp-enroll` | fprintd enrollment helper the fingerprint screen runs (JSON lines) |
| `bin/omamobile-bt-agent` | BlueZ pairing agent and discovery helper the quick-settings Bluetooth panel runs while open |
| `bin/omamobile-portal-access` | The xdg-desktop-portal Access backend (`org.freedesktop.impl.portal.desktop.omamobile`, a D-Bus-activated user unit) that shows the permission sheet and answers the portal |
| `portal/` | `omamobile.portal`, its D-Bus activation file, and `/etc/xdg/xdg-desktop-portal/hyprland-portals.conf`, which picks it for Access and xdg-desktop-portal-gnome for FileChooser only (everything else stays `hyprland;gtk`) |
| `systemd/user/xdg-desktop-portal-gnome-omamobile.conf` | The file chooser's drop-in: xdg-desktop-portal-gnome on plain Wayland (`GDK_BACKEND=wayland`), since with Omarchy's `wayland,x11,*` it serves Settings only |
| `bin/omamobile-widget` | The user's own home-screen widgets: scan and check them, make one from the template, copy an example, remove one, start Omarchy's default agent in a widget's folder |
| `widgets/WIDGETS.md` | The contract for user widgets, for people and coding agents (installed to `/usr/share/omamobile/shell/`) |
| `widgets/template`, `widgets/examples` | The starter **Create a widget with AI** copies, and examples to copy (`widget-template/`, `widget-examples/`) |

## Gestures

What a finger does on the phone shell (docs/TOUCH-PLAN.md), by surface. Destructive actions take two taps: the first turns the button into a question ("Clear all?", "Forget <name>?", "Reset?") for a few seconds.

| Where | Gesture | What it does |
| --- | --- | --- |
| Anywhere | Swipe in from the left or right edge | Back (Escape to the app), never over the lock or a fullscreen window |
| Home pill (over an app) | Swipe up | Home (an empty workspace, then the home page) |
| Home pill | Swipe up and hold, or a long swipe | Recent apps |
| Dock (home screen) | Swipe up | Recent apps |
| Dock | Tap the search pill | The app drawer with the keyboard |
| App drawer | Pull down from the top, or the chevron | Close it |
| App drawer | Long-press an app | Put it on the home page ("Added to home") |
| Home page | Swipe sideways | The next or previous page |
| Home page | Long-press (upright) | Edit mode: drag to move, handles to resize, tap the gear for a widget's settings; a notice says to turn the phone upright in landscape |
| Home page | Tap a dimmed "Not installed" tile | A notice; hold to edit and remove it |
| Status bar | Pull down | Quick settings, collapsed |
| Quick settings | Pull down again, or tap the handle | Expand to every tile, with the volume slider |
| Quick settings | Swipe up, tap outside, or Escape | Close |
| Quick settings | Swipe sideways on the tiles | The next page of tiles |
| Quick-settings tile | Tap | Toggle (or open: Clipboard, Dictation, Reminder) |
| Quick-settings tile | Long-press, or its chevron | The page behind it (Wi-Fi, Bluetooth, Reminder's list, theme picker) |
| Quick settings, pencil | Tap a tile | Remove it; hold and drag to move; tap one under Add tiles to add it |
| Notification shade | Swipe a row sideways | Forget that notification |
| Notification shade | Tap a row | Open it |
| Recent apps | Swipe sideways | Through the cards |
| Recent apps | Tap a card | Switch to it |
| Recent apps | Flick a card up | Close it |
| Recent apps | Long-press a card | Show it with another app, or give it its own screen |
| Incoming call | Swipe the control up or down | Answer or decline |
| Keyboard | Tap the button at its top-left | Hide it |

## AI Agent shortcut

**AI Agent** in the app drawer opens Omarchy's default agent with
`omarchy-agent --pick`. If no agent is chosen, it opens the existing
**Setup > Default Agent** chooser, which installs the user's selection.
The shortcut does not choose or preinstall an agent. Existing choices are
preserved, and it can be added to a home screen like any other app.
Tapping it focuses the most recently used open agent window, including a
widget-building session, instead of starting another session. To start a
separate task, use Omarchy's normal agent command.
Foot and `xdg-terminal-exec` already ship in Omarchy's base package list,
which normal root images install. The explicit dependencies are a guard
for hand-built or partial installations: both agent launch and installing
a selection need Omarchy's terminal launcher.

## File dialogs

Open, save and choose-a-folder requests through the portal (Qt, GTK, Electron and Flatpak apps alike) get Nautilus's libadwaita file chooser from xdg-desktop-portal-gnome, not xdg-desktop-portal-gtk's GTK 3 desktop chooser, whose Places sidebar took half of the 480 px width. Nautilus's chooser folds its sidebar away at phone width and has touch-sized rows; `hypr/phone.lua` tiles it, even when it has a parent window, so it fills the screen between the bar and the on-screen keyboard. Only FileChooser goes to the gnome backend: its other interfaces need gnome-shell. It runs without gnome-shell (its Mutter service channel is missing, so it falls back to a plain Wayland connection). xdg-desktop-portal-gtk stays as the fallback and for its other interfaces. GTK apps that would draw their own chooser in-process are sent to the portal too (`GTK_USE_PORTAL=1` for GTK 3, `GDK_DEBUG=portals` for GTK 4, in `environment.d/20-omamobile-osk.conf`); Qt Widgets apps keep Omarchy's `QT_QPA_PLATFORMTHEME=gtk3` for now.

## Windows on a phone screen

`hypr/phone.lua` maximizes every app between the bar and the dock, with no gaps, no border and full opacity (Omarchy's 0.96-0.985 let the home widgets show through). When the maximized window closes, the next one takes the screen (`misc:exit_window_retains_fullscreen`). Modal dialogs float centred at their own size, never bigger than the screen; picture-in-picture is 300x169 in the top-right corner. `omamobile-setup-user` sets the monitor scale to 3 with `GDK_SCALE` to match, gives foot 6 px padding, a scrollback multiplier of 3 and a 300 ms long press, and adds Chromium's Wayland input-method flags, each once and only over Omarchy's own values.

The package contract follows omarchy-mac's: `./install DESTDIR` stages files and enables nothing, `test/all` runs the package's own tests, and `version` holds the version.

Develop on a desktop with `phone/dev/run-desktop` from the repo root.
