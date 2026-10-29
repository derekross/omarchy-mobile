# omamobile-device-panther

Omarchy Mobile's first userspace package for the Google Pixel 7 (codename panther, Tensor G2 / gs201). It hides the Android partitions from desktop tools, holds the USB address, and gives pacman the same `[omamobile]` repository as the Pixel 7 Pro. It does not drive the radio, the charger, or a camera, and it does not mark a boot slot successful.

| Path | Installs to | What it does |
| --- | --- | --- |
| `vendor/udev/rules.d/10-omamobile-storage.rules` | `/usr/lib/udev/rules.d` | Hides `sda` and every Android partition except `userdata` from desktop tools. Same rule as the Pixel 7 Pro. The initramfs stops its guard loop before `switch_root`; the kernel's read-only flags are what remain |
| `vendor/udev/rules.d/20-omamobile-gpu-always-on.rules` | `/usr/lib/udev/rules.d` | Keeps the Mali-G710 powered while Panthor drives it: powering its domain back up needs a secure call our kernel doesn't make yet. Same rule as the Pixel 7 Pro |
| `vendor/udev/rules.d/72-omamobile-feedbackd.rules` | `/usr/lib/udev/rules.d` | Lets feedbackd drive the CS40L26 haptics (`cs40l26_vibra`). Same rule as the Pixel 7 Pro; the driver needs the phone's own `cs40l26.wmfw` (`tools/extract-vendor-firmware -d panther`) |
| `vendor/systemd/network/20-usb-gadget.network` | `/usr/lib/systemd/network` | Sets usb0 to 172.16.42.1/24 after handover. A replug may need a reboot: this package does not close the USB2 switch again |
| `vendor/systemd/logind.conf.d/10-omamobile-power-key.conf` | `/usr/lib/systemd/logind.conf.d` | A short power press does not power the phone off. Same drop-in as the Pixel 7 Pro. The long press stays the PMIC reset |
| `vendor/systemd/sleep.conf.d/10-omamobile.conf` | `/usr/lib/systemd/sleep.conf.d` | Suspend means suspend-to-idle: the kernel offers `deep`, but Linux has no gs201 sleep sequence, and the phone doesn't wake from it. No hibernation. Same drop-in as the Pixel 7 Pro |
| `vendor/NetworkManager/conf.d/10-omamobile-usb.conf` | `/usr/lib/NetworkManager/conf.d` | Keeps NetworkManager off that link |
| `etc/omamobile-mirrorlist` | `/etc/pacman.d/omamobile-mirrorlist` | Where pacman finds the `[omamobile]` repository. Same file as the Pixel 7 Pro package |
| `omamobile-device-panther.install` | pacman hook | Adds `[omamobile]` to `pacman.conf` before `[omarchy]`, once. Same script as the Pixel 7 Pro package |
| `src/reboot-to.c` | `/usr/bin/reboot-to` | Reboot with a reason the bootloader understands. Same bytes as the Pixel 7 Pro package; the test checks. On this phone `reboot-to bootloader` does not reach fastboot yet (device/panther/NOTES.md) |
| `device.conf` | `/usr/share/omamobile/device.conf` | The descriptor, the same bytes as `device/panther/device.conf` |

`./build [DIR]` compiles `reboot-to` from this directory, `./install DESTDIR [DIR]` stages the files, and `test/all` checks the copies when it is run from the repository.

Not in this package: the boot-success marker, Wi-Fi, the charger, cameras, and the slot-B image hook. Those stay out until each one has its own runbook.
