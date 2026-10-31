<!-- SPDX-License-Identifier: MIT -->
# omamobile-device-comet

Boot policy for the Google Pixel 9 Pro Fold (codename comet, Tensor G4 / zumapro) once its Arch root is on `userdata`. It hides the Android partitions from desktop tools, gives the USB link its address, keeps a hung shutdown from lasting more than a minute, keeps the power key and a closed fold from suspending or powering off the phone, and keeps the modules of tarball-installed kernels. It drives no radio, charger, sensor, camera or display, and installs a disabled boot-success helper (below). Physical support beyond boot, USB and the storage guard is unvalidated, and the package is not a release profile (`status`: `INSTALLABLE_PROFILE=no`).

| Path | Installs to | What it does |
| --- | --- | --- |
| `vendor/udev/rules.d/10-omamobile-storage.rules` | `/usr/lib/udev/rules.d` | Hides `sda` and every Android partition except `userdata` from desktop tools. Same rule as the other device packages. The initramfs stops its guard loop before `switch_root`; the kernel's read-only flags are what remain |
| `vendor/systemd/network/20-usb-gadget.network` | `/usr/lib/systemd/network` | Gives usb0 172.16.42.1/24. The initramfs builds the gadget (its product string is the descriptor's `USB_PRODUCT`, else `NAME`: "Pixel 9 Pro Fold") and it survives `switch_root`; this file only addresses the link after handover |
| `vendor/NetworkManager/conf.d/10-omamobile-usb.conf` | `/usr/lib/NetworkManager/conf.d` | Keeps NetworkManager off usb0 |
| `vendor/systemd/logind.conf.d/10-omamobile-power-key.conf` | `/usr/lib/systemd/logind.conf.d` | The power key is ignored by logind (a short press opens Omarchy's menu; the long press stays the PMIC reset) |
| `vendor/systemd/logind.conf.d/10-omamobile-lid.conf` | `/usr/lib/systemd/logind.conf.d` | A closed fold does not suspend. Same drop-in as the Pixel Fold; comet's hinge switch is not described yet, and once it is, logind's default would suspend and drop the USB gadget |
| `vendor/systemd/system.conf.d/10-omamobile-reboot-watchdog.conf` | `/usr/lib/systemd/system.conf.d` | `RebootWatchdogSec=1min`: a hung shutdown resets the phone by watchdog |
| `vendor/systemd/system/linux-modules-cleanup.service.d/10-omamobile-comet.conf` | `/usr/lib/systemd/system/...` | Arch's old-kernel module cleanup is skipped while this package is installed: our modules arrive as tarballs, not pacman packages, and the running, next-boot and rollback sets must stay (device-tegu 0.1.1 does the same) |
| `src/reboot-to.c` | `/usr/bin/reboot-to` | Reboot with a reason the bootloader understands (`reboot-to omamobile`). Same bytes as the other device packages; the test checks |
| `src/omamobile-bootctl.c` | `/usr/bin/omamobile-bootctl` | Reads and updates the slot flags in `devinfo`; Apache-2.0, ported from Google's boot-control code. It refuses to write any devinfo layout but 3.15, which is the layout of comet's own protected backup |
| `bin/omamobile-boot-success` + `vendor/systemd/system/omamobile-boot-success.service` | `/usr/bin`, `/usr/lib/systemd/system` | Retained for future explicit enablement; disabled by default pending maintainer agreement on #143 |
| `device.conf` | `/usr/share/omamobile/device.conf` | The descriptor, the same bytes as `device/comet/device.conf`; `test/all` checks the two. Copy it again after changing the descriptor |
| `etc/omamobile-mirrorlist`, `omamobile-device-comet.install` | `/etc/pacman.d`, pacman hook | `[omamobile]` is added to `pacman.conf` before `[omarchy]`, once. Same files as the other device packages |

## Boot-success paused (0.1.20)

The maintainer requested that Comet stop writing `devinfo` in
[issue #143](https://github.com/derekross/omarchy-mobile/issues/143).
The package installs the script and unit but creates no wants link.
Do not run or enable it until marking policy is agreed there. An existing
owner-created enablement must also be disabled or masked by the owner;
installing this package does not remove administrator overrides.
The earlier 0.1.4 automatic policy is superseded. Layout version alone is
not approval to write another phone's slot metadata.

This first PR retains the earlier boot-policy package; the local 0.1.19
subsystem startup work is deferred. Version 0.1.20 prevents a version
collision with that local package. It is not a supported install profile.

The retained helper, if explicitly admitted later:

1. **Refuses slot A.** Booted from anything but `_b`, it exits non-zero before touching `devinfo`.
2. **Reads `devinfo` read-only** with `O_DIRECT` (the page cache can't vouch for it). If slot B is already successful it exits silently.
3. **Checks health**, waiting up to two minutes for it: `comet-storage-guard` running, whole-disk `/dev/sda` absent and `devinfo` and its disk read-only, `sshd` up, `usb0` up with the gadget bound to a UDC, no failed unit, `sddm` up with a Hyprland session and an enabled display connector, and 60 s of uptime. Any failure exits non-zero and logs which check.
4. **Takes the copy of record**, `/var/lib/omamobile/devinfo-before-<boot_id>.img`, and requires the verified 3.15 layout with B's successful bit clear.
5. **Writes**: opens `devinfo`'s disk and partition read-write, runs `omamobile-bootctl mark-successful` (it re-reads and refuses if the partition moved, and changes only bytes 0x30-0x37), and locks both read-only again. The storage guard sets them read-only again within a fraction of a second, so a write that loses that race is retried (up to 8 times).
6. **Verifies** by a second `O_DIRECT` read, `devinfo-after-<boot_id>.img`: exactly byte 0x35 differs from the copy, by exactly 0x02. Any other difference, an unchanged partition, or a wrong value is refused and logged, and nothing is written to put it back (the two copies are there for the owner).

`omamobile-bootctl dump /dev/<devinfo>` shows the result; the unit's journal says why a boot was not marked. If a health check keeps failing, no slot is ever marked, which is the safe side: the retries run down and the phone lands in fastboot, where `omamobile flash --keep-active` resets the budget.

An already successful slot needs nothing. Not in this package: Wi-Fi, charger, sensors, cameras, touch and the modem. Each stays out until it has its own runbook. What is in it beyond boot policy: the AoC blacklist (`modprobe.d`) and, since 0.1.2, `modules-load.d/omamobile-comet-display.conf`, which loads `gs_dsim_cmd`, `gs_decon` and `panthor` early in boot so SDDM finds the inner display (DISPLAY-PLAN.md).

`./build [DIR]` compiles the C tools, `./install DESTDIR [DIR]` stages the files, and `test/all` checks the package, including the boot-success script against a synthetic `devinfo`, sysfs, proc and systemd (slot A, already successful, each failing health check, an unverified layout, the guard race, an unexpected byte difference, and the happy path changing only 0x35).

Inner touch trial (0.1.1): `config/inner-touch.lua` installs to
`/usr/share/omamobile/device-comet/inner-touch.lua`. Include it with
`dofile("/usr/share/omamobile/device-comet/inner-touch.lua")` in both
`/usr/share/sddm/hyprland.lua` and the desktop's `hypr/input.lua`.
It binds Goodix Berlin to inherited CT3B DSI-1, initially transform 1,
and disables the dark cover touchscreen. Confirm corner placement on the
physical phone before accepting the transform; dimensions alone cannot
prove its direction. The kernel/overlay is an attended bring-up trial.

## M18 AoC startup (0.1.3)

Ships a static, disabled `omamobile-aoc.service` and Comet-only start script.
It requires explicit stage admission, a G4 core match and a reviewed
`comet_aoc_rails` helper before loading anything. Those two kernel ports are
not delivered yet, so startup refuses even with an approval file. The future
rail helper must implement `enable=1 cycle=1` with 150 ms sensor off-time.
No gs201 PMIC helper is substituted. Named channel and ALSA consumers load
before the catch-all character driver. Failed persistent and per-boot
markers survive failure; no retry or unload option exists. See
`device/comet/AOC-PLAN.md`; shipping this unit does not admit a firmware load.
