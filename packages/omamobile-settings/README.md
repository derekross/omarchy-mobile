<!-- SPDX-License-Identifier: MIT -->
# Native Settings foundation

A native Qt Quick application with mobile navigation, search, a live Omarchy
palette and a read-only About page. It shows the model, operating system, kernel,
architecture, memory, root-filesystem capacity and installed package versions.
Unknown values remain unavailable. It opens from the desktop launcher.

This package contains the read-only foundation and two settings pages. Display
is brightness and, where the monitor lists more than one, the refresh rate (the
refresh rate changes the running session only: turning the phone makes
auto-rotate apply the monitor's preferred mode again, and a session restart or a
reload of Hyprland's config does too). Change PIN changes
the lock screen PIN, which is the account password (the lock checks it with pam_unix, and sudo does too): `backends/pin.sh` runs the
system's own `/usr/bin/passwd` in a pseudo-terminal, as the user, with the three entries on stdin (never an argument,
never in the environment, never logged or printed), digits only for the new PIN, 4 to 8 long, and passwd is what
checks the current PIN and any other rule. passwd runs with `LC_ALL=C` so its prompts are the ones the script
matches, and it is killed after 12 seconds: before the retype nothing has changed, after it the result says the PIN
may or may not have changed. The entries are held as text in the page until the call returns, then cleared; the
session's memory is not wiped. A change that finishes while the page is gone is reported when the page is opened again (the runner keeps its last result); quitting the app mid-change loses it. The page is for a phone that unlocks with a PIN and has one (`omamobile-set-pin --type` and `passwd -S` say so); for a password phone or a phone without one it says where to go instead. The pages run
`backends/display.sh` and `backends/pin.sh` through a fixed-argument runner, with no shell string.
Omarchy's existing tools continue to provide the other settings changes. Network, wallpaper, app management and
recording controls are separate future contributions with their own runtime
contracts and tests; this catalog does not offer those routes.

Back (Escape, which the phone shell's edge swipe sends, and the Back button)
leaves a search, then goes up one page. At the top level Escape shows the home
screen through the shell's `omamobile-home` and Settings stays open; it used to
close the app. Without that command nothing happens.

Build with `bin/build`, test with `test/all`, and stage with `install DESTDIR`.
Checked-in application sources live in `app/`; `src/` remains makepkg’s
extracted-source directory.
The build and test directories can be selected using
`OMAMOBILE_SETTINGS_BUILD_DIR` and `OMAMOBILE_SETTINGS_TEST_BUILD_DIR`.
`omamobile-settings --check` validates the catalog without opening a window.
`--version` prints the version from the package build.
`--preview` displays neutral fictional device information; `--page about` opens
the implemented detail page directly.

The application reads the current theme's colors.toml and observes atomic theme
replacements. Rounded corners follow Hyprland's read-only decoration:rounding
option. Apart from the Display page's live refresh rate it does not change compositor settings. A session D-Bus service handles
repeat launches.

Copyright 2026 Marsel Nenaj, MIT; see LICENSE. Extracted from my own native
Settings worktree, with Codex assistance; the application code is my MIT-licensed
work. Omarchy's theme and desktop APIs
remain the work of their upstream authors, including David Heinemeier Hansson;
this package does not claim authorship of those interfaces.

Tests run the D-Bus entrypoint in a separately compiled fixture which supplies
neutral data through DeviceInfoController's preview constructor. The D-Bus
registration and repeat-launch paths stay unchanged. Tests do not read real
hardware/model paths or run the host's package query.
