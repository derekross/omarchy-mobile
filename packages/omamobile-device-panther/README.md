# omamobile-device-panther

Omarchy Mobile's first userspace package for the Google Pixel 7 (codename panther, Tensor G2 / gs201). It hides the Android partitions from desktop tools, holds the USB address and brings USB back after a replug, and gives pacman the same `[omamobile]` repository as the Pixel 7 Pro. It loads the camera drivers after the boot has settled. It does not drive the radio or the charger, and it does not mark a boot slot successful.

| Path | Installs to | What it does |
| --- | --- | --- |
| `vendor/udev/rules.d/10-omamobile-storage.rules` | `/usr/lib/udev/rules.d` | Hides `sda` and every Android partition except `userdata` from desktop tools. Same rule as the Pixel 7 Pro. The initramfs stops its guard loop before `switch_root`; the kernel's read-only flags are what remain |
| `vendor/udev/rules.d/20-omamobile-gpu-always-on.rules` | `/usr/lib/udev/rules.d` | Keeps the Mali-G710 powered while Panthor drives it: powering its domain back up needs a secure call our kernel doesn't make yet. Same rule as the Pixel 7 Pro |
| `vendor/udev/rules.d/72-omamobile-feedbackd.rules` | `/usr/lib/udev/rules.d` | Lets feedbackd drive the CS40L26 haptics (`cs40l26_vibra`). Same rule as the Pixel 7 Pro; the driver needs the phone's own `cs40l26.wmfw` (`tools/extract-vendor-firmware -d panther`) |
| `vendor/udev/rules.d/70-omamobile-dma-heap.rules` | `/usr/lib/udev/rules.d` | Lets the video group (and the seat's user) use the general DMA-BUF heaps, which libcamera's software ISP needs in a user session. Same rule as the Pixel 7 Pro |
| `bin/omamobile-camera-start` + `vendor/systemd/system/omamobile-camera.{service,timer}` + `vendor/modprobe.d/omamobile-camera.conf` | `/usr/bin`, `/usr/lib/systemd/system` (the timer enabled by a vendor wants link), `/usr/lib/modprobe.d` | Loads the camera drivers 40 s into the boot (PMIC supplies, the three sensors and the main camera's lens, the DC-PHY and CSIS), skipping them on the next boot if a load never finished, and only when the DTB enables the camera receiver (`1a450000.csis`). The modules are blacklisted for autoload so only this guard (or a runbook) loads them. The Pixel 7 Pro's script, unit and list, with panther's CSIS and without the telephoto's `sem1215` |
| `vendor/systemd/network/20-usb-gadget.network` | `/usr/lib/systemd/network` | Sets usb0 to 172.16.42.1/24 after handover |
| `bin/omamobile-usb-rescue`, `vendor/systemd/system/omamobile-usb-rescue.service` | `/usr/bin`, `/usr/lib/systemd/system` (enabled for `multi-user.target`) | Brings USB back after a replug: the MAX77759 opens its USB2 data switch on unplug, and with no Type-C driver nothing closes it. While VBUS is valid, puts the switch back to 0x09 on the chip's I2C bus (USI13, which the board file enables). Reads two registers and writes that one; stands aside once a Type-C driver owns the chip. Same script and unit as the Pixel 7 Pro; needs `i2c-tools` |
| `vendor/systemd/logind.conf.d/10-omamobile-power-key.conf` | `/usr/lib/systemd/logind.conf.d` | A short power press does not power the phone off. Same drop-in as the Pixel 7 Pro. The long press stays the PMIC reset |
| `vendor/modprobe.d/omamobile-display.conf` | `/usr/lib/modprobe.d` | Lets `gs_dsim_cmd` send DCS packets to the panel (`allow_tx=1`), so the panel driver can set the brightness and turn the display off and on. The driver ships with sending off; brightness passed DISPLAY-PLAN gate D2 on the Pixel 7 |
| `vendor/modprobe.d/omamobile-fingerprint.conf` | `/usr/lib/modprobe.d` | Keeps `sg` and `goodix_fp` from autoloading: omamobile-fp loads them (the RPMB LUN, the sensor). Trusty is left to the DT's `/trusty` node, since this package has no sound start that loads it as the 7 Pro's does (device/panther/FINGERPRINT-PLAN.md) |
| `vendor/systemd/sleep.conf.d/10-omamobile.conf` | `/usr/lib/systemd/sleep.conf.d` | Suspend means suspend-to-idle: the kernel offers `deep`, but Linux has no gs201 sleep sequence, and the phone doesn't wake from it. No hibernation. Same drop-in as the Pixel 7 Pro |
| `vendor/NetworkManager/conf.d/10-omamobile-usb.conf` | `/usr/lib/NetworkManager/conf.d` | Keeps NetworkManager off that link |
| `etc/omamobile-mirrorlist` | `/etc/pacman.d/omamobile-mirrorlist` | Where pacman finds the `[omamobile]` repository. Same file as the Pixel 7 Pro package |
| `omamobile-device-panther.install` | pacman hook | Adds `[omamobile]` to `pacman.conf` before `[omarchy]`, once. Same script as the Pixel 7 Pro package |
| `src/reboot-to.c` | `/usr/bin/reboot-to` | Reboot with a reason the bootloader understands. Same bytes as the Pixel 7 Pro package; the test checks. On this phone `reboot-to bootloader` does not reach fastboot yet (device/panther/NOTES.md) |
| `device.conf` | `/usr/share/omamobile/device.conf` | The descriptor, the same bytes as `device/panther/device.conf` |

`./build [DIR]` compiles `reboot-to` from this directory, `./install DESTDIR [DIR]` stages the files, and `test/all` checks the copies when it is run from the repository.

Not in this package: the boot-success marker, Wi-Fi, the charger, and the slot-B image hook. Those stay out until each one has its own runbook.
