# omamobile-device-dipper

Omarchy Mobile support for the Xiaomi Mi 8 (dipper, Snapdragon 845). It hides Android partitions from desktop tools and configures USB networking, device identity and optional Tailscale startup. Qualcomm Wi-Fi userspace and firmware are included in the image; radio startup remains a gated hardware bring-up step.

| Path | Installs to | What it does |
| --- | --- | --- |
| `vendor/udev/rules.d/10-omamobile-storage.rules` | `/usr/lib/udev/rules.d` | Hides `sda` and every Android partition except `userdata` from desktop tools. Same rule as the Pixel 7 Pro. The initramfs stops its guard loop before `switch_root`; the kernel's read-only flags are what remain |
| `vendor/systemd/network/20-usb-gadget.network` | `/usr/lib/systemd/network` | Sets usb0 to 172.16.42.1/24 after handover. A replug may need a reboot: this package does not close the USB2 switch again (as on the Pixel Fold; dipper's replug is untested) |
| `vendor/systemd/logind.conf.d/10-omamobile-power-key.conf` | `/usr/lib/systemd/logind.conf.d` | A short power press does not power the phone off. Same drop-in as the Pixel 7 Pro. On dipper the forced reset is Power + Volume Up held 15-30 s ([BRINGUP-M1](../../device/dipper/BRINGUP-M1.md) test 23) |
| `vendor/NetworkManager/conf.d/10-omamobile-usb.conf` | `/usr/lib/NetworkManager/conf.d` | Keeps NetworkManager off that link |
| `etc/omamobile-mirrorlist` | `/etc/pacman.d/omamobile-mirrorlist` | Where pacman finds the `[omamobile]` repository. Same file as the Pixel 7 Pro package |
| `omamobile-device-dipper.install` | pacman hook | Adds `[omamobile]` to `pacman.conf` before `[omarchy]`, once. Same script as the Pixel 7 Pro package |
| `src/reboot-to.c` | `/usr/bin/reboot-to` | Reboot with a reason the bootloader understands. Same bytes as the Pixel 7 Pro package; the test checks |
| `device.conf` | `/usr/share/omamobile/device.conf` | The descriptor, the same bytes as `device/dipper/device.conf` |
| `src/reboot-to.c` | build input | Compiles `reboot-to`, which requests a reboot to the bootloader |

`./build [DIR]` compiles `reboot-to` from this directory, `./install DESTDIR [DIR]` stages the files, and `test/all` checks the copies when it is run from the repository.

Not in this package: the boot-success marker, automatic modem/Wi-Fi startup, the charger, cameras, and the slot-B image hook. Automatic radio startup stays disabled until its hardware runbook passes. There is no lid drop-in: dipper has no hinge.
