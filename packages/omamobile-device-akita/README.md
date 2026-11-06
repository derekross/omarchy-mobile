# omamobile-device-akita

Omarchy Mobile's first userspace package for the Google Pixel 8a (codename akita, Tensor G3 / zuma). Like the Pixel 8 Pro's first package, it hides the Android partitions from desktop tools, holds the USB address, and gives pacman the same `[omamobile]` repository as the Pixel 7 Pro. It does not drive the radio, the charger, or a camera, and it does not mark a boot slot successful.

| Path | Installs to | What it does |
| --- | --- | --- |
| `vendor/udev/rules.d/10-omamobile-storage.rules` | `/usr/lib/udev/rules.d` | Hides `sda` and every Android partition except `userdata` from desktop tools. Same rule as the Pixel 7 Pro. The initramfs stops its guard loop before `switch_root`; the kernel's read-only flags are what remain ([BRINGUP-M2](../../device/akita/BRINGUP-M2.md) test 8) |
| `vendor/systemd/network/20-usb-gadget.network` | `/usr/lib/systemd/network` | Sets usb0 to 172.16.42.1/24 after handover, as the last gateway. A replug needs a reboot: this package does not close the MAX77759's USB2 switch again (the Pixel 8 Pro's rescue needs its `hsi2c_11` bus, which akita's board file doesn't have yet). Same file as the Pixel 8 Pro package |
| `vendor/systemd/logind.conf.d/10-omamobile-power-key.conf` | `/usr/lib/systemd/logind.conf.d` | A short power press does not power the phone off. Same drop-in as the Pixel 7 Pro. akita's forced-reset combination under our kernel is untested; on the Pixel 8 Pro it is Power + Volume Up held 15-30 s |
| `vendor/NetworkManager/conf.d/10-omamobile-usb.conf` | `/usr/lib/NetworkManager/conf.d` | Keeps NetworkManager off that link. Same file as the Pixel 8 Pro package |
| `etc/omamobile-mirrorlist` | `/etc/pacman.d/omamobile-mirrorlist` | Where pacman finds the `[omamobile]` repository. Same file as the Pixel 7 Pro package |
| `omamobile-device-akita.install` | pacman hook | Adds `[omamobile]` to `pacman.conf` before `[omarchy]`, once, and keeps the channel a phone follows. Same script as the Pixel 7 Pro package |
| `src/reboot-to.c` | `/usr/bin/reboot-to` | Reboot with a reason the bootloader understands (`reboot-to bootloader` reaches fastboot on akita, [BRINGUP-M1](../../device/akita/BRINGUP-M1.md) test 3). Same bytes as the Pixel 7 Pro package; the test checks |
| `device.conf` | `/usr/share/omamobile/device.conf` | The descriptor, the same bytes as `device/akita/device.conf` |

`./build [DIR]` compiles `reboot-to` from this directory, `./install DESTDIR [DIR]` stages the files, and `test/all` checks the copies when it is run from the repository.

Not in this package: the boot-success marker, Wi-Fi, the charger, cameras, the USB replug rescue, the display start and the slot-B image hook. Each one stays out until it has its own runbook. There is no lid drop-in: akita has no hinge. Whether Plymouth needs the Pixel 8 Pro's retain-splash drop-in on simpledrm is still open ([BRINGUP-M2](../../device/akita/BRINGUP-M2.md), open questions).
