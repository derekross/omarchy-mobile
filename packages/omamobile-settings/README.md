<!-- SPDX-License-Identifier: MIT -->
# Native Settings foundation

A native Qt Quick application with mobile navigation, search, a live Omarchy
palette and a read-only About page. It shows the model, operating system, kernel,
architecture, memory, root-filesystem capacity and installed package versions.
Unknown values remain unavailable. It opens from the desktop launcher.

This package contains the read-only foundation and one settings page, Display
(brightness and, where the monitor lists more than one, the refresh rate; the
refresh rate changes the running session only: turning the phone makes
auto-rotate apply the monitor's preferred mode again, and a session restart or a
reload of Hyprland's config does too). The page runs
`backends/display.sh` through a fixed-argument runner, with no shell string.
A second page, Battery, sets the charge limit (80, 85, 90, 95 or 100 %), only
on a phone whose device package declares one in
`/usr/share/omamobile/charge-limit.conf` (a line `supply=NAME`;
omamobile-device-husky ships it for `max77759-charger`) and only while that
supply has `charge_control_end_threshold`. Everywhere else the Battery row is
hidden (the catalog row's `"requires": "charge"`: Settings runs
`backends/charge.sh get` at start and shows the row only on
`{"available":true}`), and the backend and the helper write nothing. The row
appears only if the charger was there when Settings started: a charger that
shows up later needs Settings to be started again. The page
runs `backends/charge.sh`, which starts `omamobile-charge-limit@N.service`; the
polkit rule `50-omamobile-charge-limit.rules` lets the active local user start
those five instances only. The service runs `libexec/charge-limit` as root,
which checks the declaration, writes the charger (start threshold 0, then the
end threshold) and only then saves the value to `/etc/omamobile/charge-limit`.
The device package that declares the limit also ships the udev rule and
`omamobile-charge-limit-apply.service`, which run the same helper without an
argument when the charger appears, to apply the saved value at boot. The
Pixel 9a's limit (`omamobile-device-tegu`, from `/etc/omamobile/charge-limit`
by its own script) is not declared, so Settings leaves it alone. On husky the
row stays hidden today: omamobile-device-husky blacklists `max77759_charger`
(`omamobile-max77759.conf`), so there is no `max77759-charger` power supply
until that blacklist is lifted on a kernel with
derekross/linux-omamobile#266.

A third page, Security & privacy, turns the UFW firewall on or off and shows the SSH server. The page runs
`backends/security.sh`, which reads `ENABLED=` in `/etc/ufw/ufw.conf`, the port 22 rules in `/etc/ufw/user.rules` and
`user6.rules` (read only; `ufw status` needs root and is not called) and `systemctl is-active|is-enabled` for
`sshd.service` and `omamobile-hotspot.service`. A switch starts `omamobile-firewall@on|off.service`, which runs
`libexec/firewall` (installed as `/usr/lib/omamobile-settings/firewall`) as root: `ufw --force enable` or `ufw disable`,
then reads `ufw.conf` back. The polkit rule `50-omamobile-firewall.rules` lets the active local user start those two
instances only, and both On and Off ask for the PIN through the shell's polkit prompt (`auth_admin_keep`), so no
other process in the session can switch the firewall without the owner. A cancelled PIN leaves the firewall as it was
and the page says so. On is refused, by
the backend and again by the root helper, while `sshd.service` or `sshd.socket` is running or enabled (or its state
can't be read) and no rule lets port 22 in on `usb0` ahead of any rule that could drop it (ufw is first match; IPv4,
and IPv6 when ufw uses it, read from `IPV6=` in `/etc/default/ufw` and then `/etc/ufw/ufw.conf` as ufw does), since
that could cut SSH over USB, and while `omamobile-hotspot.service` is running or starting. Only port 22 is checked: an
SSH server on another port isn't. A `ufw limit` rule for SSH on `usb0` doesn't count as the USB allow (On is
refused), and neither does a usb0 allow behind a deny with any source, a `!` or a port name. "On" means `ENABLED=yes` in `ufw.conf`. Off asks first and is never refused. The
UFW rules are never changed. SSH is shown, not switched.
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
