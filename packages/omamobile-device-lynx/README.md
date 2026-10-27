# omamobile-device-lynx

Omarchy Mobile's first userspace package for the Google Pixel 7a (codename lynx, Tensor G2 / gs201). It hides the Android partitions from desktop tools, holds the USB address, and gives pacman the same `[omamobile]` repository as the Pixel 7 Pro. It marks the booted slot successful after each boot. It does not drive the radio, the charger, or a camera.

| Path | Installs to | What it does |
| --- | --- | --- |
| `vendor/udev/rules.d/10-omamobile-storage.rules` | `/usr/lib/udev/rules.d` | Hides `sda` and every Android partition except `userdata` from desktop tools. Same rule as the Pixel 7 Pro. The initramfs stops its guard loop before `switch_root`; the kernel's read-only flags are what remain |
| `vendor/systemd/network/20-usb-gadget.network` | `/usr/lib/systemd/network` | Sets usb0 to 172.16.42.1/24 after handover. A replug may need a reboot: this package does not close the USB2 switch again |
| `vendor/systemd/logind.conf.d/10-omamobile-power-key.conf` | `/usr/lib/systemd/logind.conf.d` | A short power press does not power the phone off. Same drop-in as the Pixel 7 Pro. The long press stays the PMIC reset |
| `vendor/systemd/sleep.conf.d/10-omamobile.conf` | `/usr/lib/systemd/sleep.conf.d` | Suspend means suspend-to-idle, and hibernation is off. The firmware offers PSCI system suspend, so the kernel offers `deep` (lynx reads `s2idle [deep]`), which never wakes on gs201. Same drop-in as the Pixel 7 Pro. Suspend itself is untested on lynx |
| `vendor/NetworkManager/conf.d/10-omamobile-usb.conf` | `/usr/lib/NetworkManager/conf.d` | Keeps NetworkManager off that link |
| `etc/omamobile-mirrorlist` | `/etc/pacman.d/omamobile-mirrorlist` | Where pacman finds the `[omamobile]` repository. Same file as the Pixel 7 Pro package |
| `omamobile-device-lynx.install` | pacman hook | Adds `[omamobile]` to `pacman.conf` before `[omarchy]`, once. Same script as the Pixel 7 Pro package |
| `bin/omamobile-boot-success` + `vendor/systemd/system/omamobile-boot-success.service` | `/usr/bin`, `/usr/lib/systemd/system` (enabled by a vendor wants link) | Marks the booted A/B slot successful after each boot, as Android's boot-control service does. Without it, the bootloader burns one of slot B's three retries per boot and then falls back to slot A. Same files as the Pixel 7 Pro package |
| `src/omamobile-bootctl.c` | `/usr/bin/omamobile-bootctl` | Reads and updates the slot flags in `devinfo` (`sdd1`, layout 3.15 on lynx as on the Pixel 7 Pro). Only ever changes bytes 0x30-0x37, verified. Same source as the Pixel 7 Pro package |
| `src/reboot-to.c` | `/usr/bin/reboot-to` | Reboot with a reason the bootloader understands. Same bytes as the Pixel 7 Pro package; the test checks |
| `device.conf` | `/usr/share/omamobile/device.conf` | The descriptor, the same bytes as `device/lynx/device.conf` |

`./build [DIR]` compiles `omamobile-bootctl` and `reboot-to` from this directory, `./install DESTDIR [DIR]` stages the files, and `test/all` checks the two copies when it is run from the repository.

Not in this package: Wi-Fi, the charger, cameras, and the slot-B image hook. Those stay out until each one has its own runbook.

Licences: MIT, except `omamobile-bootctl`, which is Apache-2.0 and keeps Google's notice.
