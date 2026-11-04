<!-- SPDX-License-Identifier: MIT -->
# omamobile-device-bluejay

Omarchy Mobile's first userspace package for the Google Pixel 6a (codename bluejay, Tensor / gs101), the package `device/bluejay/device.conf` names. It hides the Android partitions from desktop tools, holds the USB address, keeps suspend on suspend-to-idle, and gives pacman the same `[omamobile]` repository as the Pixel 7 Pro. It does not drive the radio, the charger, or a camera, it enables no service, it loads no driver, and it does not mark a boot slot successful.

**No Pixel 6a has run it.** Its board DTS ([kernel #179](https://github.com/derekross/linux-omarchy-mobile/pull/179)) is merged without a boot, and this package follows the same way: every file is a copy of one that runs on the Pixel 6 Pro (raven, the same SoC) or the Pixel 7 Pro, and `test/all` checks the copies. The first boot's `tools/phone-smoke` report goes to [issue #348](https://github.com/derekross/omarchy-mobile/issues/348), the 6a's own thread, and [device/bluejay/NOTES.md](../../device/bluejay/NOTES.md).

| Path | Installs to | What it does |
| --- | --- | --- |
| `vendor/udev/rules.d/10-omamobile-storage.rules` | `/usr/lib/udev/rules.d` | Hides `sda` and every Android partition except `userdata` from desktop tools. Same rule as the Pixel 7 Pro. The initramfs stops its guard loop before `switch_root`; the kernel's read-only flags are what remain |
| `vendor/systemd/network/20-usb-gadget.network` | `/usr/lib/systemd/network` | Sets usb0 to 172.16.42.1/24 after handover, as the last gateway. A replug may need a reboot: this package does not close the Type-C chip's USB2 switch again (raven's package does for its MAX77759, through a service; the 6a's chip, bus and address are unread) |
| `vendor/systemd/logind.conf.d/10-omamobile-power-key.conf` | `/usr/lib/systemd/logind.conf.d` | A short power press does not power the phone off. Same drop-in as the Pixel 7 Pro. The long press stays the PMIC reset |
| `vendor/systemd/sleep.conf.d/10-omamobile.conf` | `/usr/lib/systemd/sleep.conf.d` | Suspend means suspend-to-idle: the firmware advertises PSCI SYSTEM_SUSPEND, so the kernel offers `deep`, but Linux has no gs101 sleep sequence and the Pixel 6 Pro doesn't wake from it. No hibernation. Same drop-in as the Pixel 6 Pro package; bluejay's bootargs don't set `mem_sleep_default`, as oriole's don't, so this file is what keeps a `systemctl suspend` on s2idle |
| `vendor/NetworkManager/conf.d/10-omamobile-usb.conf` | `/usr/lib/NetworkManager/conf.d` | Keeps NetworkManager off that link |
| `etc/omamobile-mirrorlist` | `/etc/pacman.d/omamobile-mirrorlist` | Where pacman finds the `[omamobile]` repository. Same file as the Pixel 7 Pro package |
| `omamobile-device-bluejay.install` | pacman hook | Adds `[omamobile]` to `pacman.conf` before `[omarchy]`, once. Same script as the Pixel 7 Pro package |
| `src/reboot-to.c` | `/usr/bin/reboot-to` | Reboot with a reason the bootloader understands. On a first boot the reason most likely isn't stored: the descriptor lists no `INITRAMFS_MODULES`, and raven's records that without its PMIC and reboot-mode modules `reboot-to bootloader` just boots slot B again, so fastboot is by the buttons. Same bytes as the Pixel 7 Pro package; the test checks |
| `device.conf` | `/usr/share/omamobile/device.conf` | The descriptor, the same bytes as `device/bluejay/device.conf` |

`./build [DIR]` compiles `reboot-to` from this directory, `./install DESTDIR [DIR]` stages the files, and `test/all` checks the copies when it is run from the repository.

Not in this package: `omamobile-bootctl` and the boot-success marker (marking slot B on the gs101 phones is on hold, [#252](https://github.com/derekross/omarchy-mobile/issues/252); without the source, `bin/omamobile initramfs` builds its freestanding helpers, as for oriole), the USB rescue, Wi-Fi, the charger, haptics, the display's module options, cameras, any modprobe blacklist, and the slot-B image hook. Each comes in when a booted 6a has given it a runbook and the evidence.
