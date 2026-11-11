<!-- SPDX-License-Identifier: MIT -->
# Native Settings foundation

A native Qt Quick application with mobile navigation, search, a live Omarchy
palette and a read-only About page. It shows the model, operating system, kernel,
architecture, memory, root-filesystem capacity and installed package versions.
Unknown values remain unavailable. It opens from the desktop launcher.

This initial package contains the read-only foundation. Omarchy's existing tools
continue to provide settings changes. Network, wallpaper, app management and
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
option. It does not change compositor settings. A session D-Bus service handles
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
