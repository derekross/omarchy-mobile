# omamobile-shell

Omarchy Mobile's phone profile for Omarchy's own shell. It isn't a fork: these are ordinary Omarchy shell plugins plus a phone `shell.json`, linked into the user's config by `omamobile-setup-user`.

| Path | What it is |
| --- | --- |
| `plugins/omamobile.bar` | Phone status bar (a full `bar` plugin) |
| `plugins/omamobile.quicksettings` | Pull-down quick settings |
| `plugins/omamobile.launcher` | Home bar: app search, app grid and a prompt to the user's Omarchy default agent; over an app, the home pill in a 44 px strip that reserves its height, so apps end above it (as on Android it is just the pill: double-tap for the keyboard, hold for the voice bar) |
| `plugins/omamobile.switcher` | Recent apps: swipe up on the dock, or swipe up and hold on the home pill over an app; hold a card to show the app with another one, or give it its own screen again |
| `plugins/omamobile.home` | Home screens: pages of apps and widgets on the wallpaper, with an edit mode. The built-ins include every widget in Simon Schubert's [omarchy-widgets](https://github.com/SimonSchubert/omarchy-widgets) `widgets/simonschubert/` (MIT): the OWL originals, from the `omamobile-owl-widgets` package, run by our own OWL runtime (`owl/`, see `owl/SPEC-NOTES.md`). `widgets/OWL.md` is his OWL language guide (MIT, `widgets/LICENSE-owl-guide`) |
| `plugins/omamobile.keyboard` | The on-screen keyboard's show and hide calls, for the home pill (double-tap it), the keyboard's Hide key and scripts; a keyboard shown by hand goes away when the home screen comes up; the language sheet for the keyboard's globe key |
| `squeekboard/keyboards/` | squeekboard's layouts (GPL-3.0-or-later, portrait and landscape) with an action row of Mic, Paste, Emoji and Hide, XF86 keysyms that `hypr/phone.lua` binds for squeekboard's virtual keyboard only (docs/VOICE-PLAN.md): the US terminal layout by hand, every language's (and the email and URL layouts) made from squeekboard 1.43.1's own by `squeekboard/generate`; `squeekboard/generate --check` (in `test/all`) proves each is upstream's plus the row and the globe key, which sends `XF86MediaLanguageMenu` (the language sheet) instead of opening squeekboard's popover |
| `bin/omamobile-keyboard-languages` | The keyboard's languages for the language sheet: lists `org.gnome.desktop.input-sources` `sources` with xkeyboard-config's names and the layouts that can be added, and switches by moving one to the front, as squeekboard's own popover does. How to pick, add or change a layout: [docs/KEYBOARD-LAYOUTS.md](../../docs/KEYBOARD-LAYOUTS.md) |
| `bin/omamobile-keyboard-theme` | squeekboard in the applied Omarchy theme: a stylesheet from `colors.toml` and Omarchy's monospace font, imported from `~/.config/gtk-3.0/gtk.css`; rewritten at login and, with a squeekboard restart, by Omarchy's theme-set hook (`hooks/theme-set-keyboard`) |
| `plugins/omamobile.back` | The back gesture: swipe in from a side edge for Escape |
| `plugins/omamobile.update` | The update sheet: Omarchy's update for a phone, through `omamobile-update` (package `omamobile-omarchy`) |
| `plugins/omamobile.voice` | The voice bar, through Voxtype: hold the pill in an app or the search bar on the home screen (or the keyboard's Mic key, Power + Volume Up, the Dictation tile, whose chevron opens the settings); it types into the app, sends to the agent in its terminal, or asks it from the home screen (docs/VOICE-PLAN.md) |
| `bin/omamobile-voice-preview` | The voice bar's live preview: a second capture of the microphone (in memory only), transcribed in chunks with tiny.en (base.en when tiny.en isn't downloaded) and Whisper's context cut to the chunk while Voxtype records, one JSON line per pass; the bar shows the words in the theme's muted colour until the daemon's final text replaces them. Voxtype 1.1.1 can't hand its own partial text over (docs/VOICE-PLAN.md, phase 3) |
| `plugins/omamobile.access` | The permission sheet: "Allow Camera to use the camera?" with the app's icon and two large buttons, in place of xdg-desktop-portal-gtk's desktop dialog |
| `plugins/omamobile.fingerprint` | The under-display fingerprint sensor: target during verification, enrollment screen |
| `profile/shell.json` | The phone layout the setup seeds once |
| `bin/omamobile-setup-user` | Omarchy Mobile's per-user setup (Omarchy lifecycle `setup-user`); at every login it also enables and starts the Phone and Messages agent's user unit (`omatel-agent.service`, when installed), so calls and texts notify with no app open; `--adopt`, for a user set up by hand rather than by firstboot, marks the once-only steps that would overwrite or repeat what that user has (the shell profile, the monitor scale, the cursor and keyboard lines, the screensaver, Files' click policy) done without running them; the other steps run as for a new user (missing phone plugins and an idle block go into `shell.json`, Chromium's flags are written), and the setup service then runs at each login |
| `bin/omamobile-launch` | One app per screen: every launch from the shell (drawer, home screen, widgets, links, the agent) gets a new empty workspace through a per-launch Hyprland exec rule, or focuses the app's open window; and the switcher's "Show with…" and "Move to its own screen" |
| `bin/omamobile-home` | The home screen, as the home pill's swipe shows it (an empty workspace and the home page). An app runs it when Back (Escape, from the edge swipe) reaches its top level, so Back is phone-wide and no app needs a Hyprland call: [plugins/README.md](plugins/README.md#omamobileback) |
| `bin/omamobile-osk-watch` | Reports squeekboard's visibility (sm.puri.OSK0) to the fingerprint, keyboard and launcher plugins |
| `bin/omamobile-screenshot-open` | What a screenshot toast's tap ("Tap to view", patch 0020) opens on a phone (`OMARCHY_SCREENSHOT_EDITOR`, set in `environment.d/30-omamobile-screenshot.conf`; Omarchy passes the saved file's path): the screenshot in Loupe (omamobile-apps), fitted, with touch zoom, pan and swipe, and Loupe's copy, share and delete. Tensaku, Omarchy's default, can't be panned or zoomed by touch; without Loupe it is the fallback, through `omamobile-screenshot-edit` |
| `bin/omamobile-screenshot-edit` | Tensaku as Omarchy opens a screenshot in it (`tensaku-edit`), with GTK's simple input-method context so the on-screen keyboard doesn't come up over the image (show it by hand for the text tool). `omamobile-setup-user` gives Tensaku's own entry (drawer, Loupe's Open With) the same context once, and `hypr/phone.lua` maximizes its window, which Omarchy floats by class |
| `bin/omamobile-osk-guard` | Turns the on-screen keyboard (`screen-keyboard-enabled`) back on when it was left off with no screensaver running (a user unit for every graphical session) |
| `bin/omamobile-doubletap` | Double tap to wake, as on Android: two taps within 0.4 s and about 150 px of each other (14 % of the touchscreen's width) on a dark phone wake it as a short power press does (`omamobile-keys double-tap`, which leaves a lit screen alone). `hypr/phone.lua` turns Hyprland's `misc:mouse_move_enables_dpms` off, so a single touch no longer lights the screen; on the lock no touch wakes it either (patch 0029), and this daemon wakes it through `omamobile-keys double-tap`. With the phone in a pocket (proximity near, through iio-sensor-proxy, claimed only from the first dark tap until 2 s after the last) the double tap is skipped; without a proximity sensor it wakes as before. A screen that goes dark while unlocked (an idle blank, the panel powered off by hand) is locked at once (`omamobile-keys dark-unlocked`), as on Android: Hyprland sends a touch to the window under it whatever the screen's state, so on a dark unlocked phone it reached an app no one could see. It works while the phone is awake: a double tap can't wake it from sleep (with the sleep toggle on, the first 30 s after the screen goes off). It times a double tap from one lift to the next touch, and it only wakes: the lock itself ignores touches while dark (0029). The touchscreen is the first input device with `INPUT_PROP_DIRECT`, `BTN_TOUCH` and `ABS_MT_POSITION_X`, read without a grab (the user is in the `input` group). A user unit for every graphical session |
| `bin/omamobile-sleepd` | Sleep (s2idle) once the screen has been off behind a secure lock for `OMAMOBILE_SLEEP_AFTER_OFF` s (30), and again 5 s after a dark resume; `now` for the power key (`omamobile-keys`), `check` to see what holds it awake. Refuses with the screen on, Stay awake on, an SSH session open, a logind sleep block inhibitor (calls, GNSS) or a RUNNING PipeWire sink. A user unit for every graphical session, **off until `omarchy-toggle omamobile-sleep on`** (device/cheetah/SUSPEND-PLAN.md 6.2) |
| `bin/omamobile-weather` | The current weather for the lock screen's glance (`~/.local/state/omamobile/weather.json`, with the `source` it used) from Open-Meteo, at login and every 30 minutes (`omamobile-weather.timer`, a user unit for every graphical session). Where, in order: the phone's position from GeoClue at city accuracy, at most every 3 h and only while the Location switch is on and GeoClue has an agent for the user (omamobile-gnss's unit, or any other instance of GeoClue's demo agent the user runs; never a prompt); the setting `~/.config/omamobile/weather.json` (`omamobile-weather set "State College, PA" F`, or `{"latitude", "longitude"}`; `"location": "fixed"` puts it before the position); the home screen's today widget's city, or the weather widget's named place. Unit: the setting's, else the locale's. A failure keeps the old reading; a run that starts before the network is back (login, or the catch-up run on resume) tries again with backoff for up to 75 s and then gives up without failing the unit. `omamobile-weather show` says where it would look |
| `bin/omamobile-fp-enroll` | fprintd enrollment helper the fingerprint screen runs (JSON lines) |
| `bin/omamobile-bt-agent` | BlueZ pairing agent and discovery helper the quick-settings Bluetooth panel runs while open |
| `bin/omamobile-portal-access` | The xdg-desktop-portal Access backend (`org.freedesktop.impl.portal.desktop.omamobile`, a D-Bus-activated user unit) that shows the permission sheet and answers the portal |
| `portal/` | `omamobile.portal`, its D-Bus activation file, and `/etc/xdg/xdg-desktop-portal/hyprland-portals.conf`, which picks it for Access and xdg-desktop-portal-gnome for FileChooser only (everything else stays `hyprland;gtk`) |
| `systemd/user/xdg-desktop-portal-gnome-omamobile.conf` | The file chooser's drop-in: xdg-desktop-portal-gnome on plain Wayland (`GDK_BACKEND=wayland`), since with Omarchy's `wayland,x11,*` it serves Settings only |
| `bin/omamobile-widget` | The user's own home-screen widgets: scan and check them, make one from the template, copy an example, remove one, start Omarchy's default agent in a widget's folder |
| `widgets/WIDGETS.md` | The contract for user widgets, for people and coding agents (installed to `/usr/share/omamobile/shell/`) |
| `widgets/template`, `widgets/examples` | The starter **Create a widget with AI** copies, and examples to copy (`widget-template/`, `widget-examples/`) |

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

## Voice input

Voice works out of the box on a fresh install: no Install > AI > Dictation
step and no download. The root image installs Voxtype (`voxtype-bin` from
[omarchy], in `rootfs/packages.base`) and Whisper's base.en speech model
(`packages/omamobile-voice`, 141 MiB in `/usr/share/omamobile/voice/models`).
The model counts twice in the image: the image also carries its own copy of
the [omamobile] repository (`/var/lib/omamobile/repo`, for offline
reinstalls), where the package archive is another 141 MiB that won't
compress. With voxtype-bin (71 MB installed, its archive is in Omarchy's
repository, not ours) the root image grows by about 370 MB unpacked and
about 325 MB compressed (2.8 GB before).

At the user's first setup `omamobile-setup-user` does what Omarchy's
`omarchy-voxtype-install` does, minus the download: it copies Omarchy's
Voxtype config, links the shipped model into
`~/.local/share/voxtype/models` (the only place Voxtype looks), enables
the packaged `voxtype.service` user daemon (it starts with the graphical
session) and marks Omarchy's "Install Dictation" invitation done. The
config and the link happen once per user, and a config or model the user
already has stays; the enable is retried at each login until it works
(firstboot may run without a user manager). The settings' Fast (tiny.en,
75 MB) and Accurate (small.en) models still download on request; without
tiny.en the live preview uses base.en, with a pass every 2.5 s instead of
1.2 s. Phones installed before this keep their setup: `omamobile-voice` is
an optional dependency, and Omarchy's own install works as before.

To remove dictation completely: Remove > Dictation (Omarchy's
`omarchy-voxtype-remove`) takes out voxtype-bin, the user's Voxtype config
and the model link, and setup leaves it removed; the shipped model stays
until `sudo pacman -R omamobile-voice` frees its 141 MiB. Installing
Dictation again through Omarchy's menu then downloads base.en itself.

Building `omamobile-voice` needs huggingface.co the first time on a build
machine: the model comes from a pinned commit of whisper.cpp's model
repository with a pinned sha256, and makepkg keeps it in its source cache
afterwards.

## File dialogs

Open, save and choose-a-folder requests through the portal (Qt, GTK, Electron and Flatpak apps alike) get Nautilus's libadwaita file chooser from xdg-desktop-portal-gnome, not xdg-desktop-portal-gtk's GTK 3 desktop chooser, whose Places sidebar took half of the 480 px width. Nautilus's chooser folds its sidebar away at phone width and has touch-sized rows; `hypr/phone.lua` tiles it, even when it has a parent window, so it fills the screen between the bar and the on-screen keyboard. Only FileChooser goes to the gnome backend: its other interfaces need gnome-shell. It runs without gnome-shell (its Mutter service channel is missing, so it falls back to a plain Wayland connection). xdg-desktop-portal-gtk stays as the fallback and for its other interfaces. GTK apps that would draw their own chooser in-process are sent to the portal too (`GTK_USE_PORTAL=1` for GTK 3, `GDK_DEBUG=portals` for GTK 4, in `environment.d/20-omamobile-osk.conf`); Qt Widgets apps keep Omarchy's `QT_QPA_PLATFORMTHEME=gtk3` for now.

## Windows on a phone screen

`hypr/phone.lua` maximizes every app between the bar and the dock, with no gaps, no border and full opacity (Omarchy's 0.96-0.985 let the home widgets show through). When the maximized window closes, the next one takes the screen (`misc:exit_window_retains_fullscreen`). Modal dialogs float centred at their own size, never bigger than the screen; picture-in-picture is 300x169 in the top-right corner. `omamobile-setup-user` sets the monitor scale to 3 with `GDK_SCALE` to match, gives foot 6 px padding, a scrollback multiplier of 3 and a 300 ms long press, and adds Chromium's Wayland input-method flags, each once and only over Omarchy's own values.

The package contract follows omarchy-mac's: `./install DESTDIR` stages files and enables nothing, `test/all` runs the package's own tests, and `version` holds the version.

Develop on a desktop with `phone/dev/run-desktop` from the repo root.
