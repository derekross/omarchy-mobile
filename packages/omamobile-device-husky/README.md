# omamobile-device-husky

Omarchy Mobile's first userspace package for the Google Pixel 8 Pro (codename husky, Tensor G3 / zuma). Like the Pixel Fold's, it hides the Android partitions from desktop tools, holds the USB address, and gives pacman the same `[omamobile]` repository as the Pixel 7 Pro. It does not drive the radio, the charger, or a camera, and it does not mark a boot slot successful.

| Path | Installs to | What it does |
| --- | --- | --- |
| `vendor/udev/rules.d/10-omamobile-storage.rules` | `/usr/lib/udev/rules.d` | Hides `sda` and every Android partition except `userdata` from desktop tools. Same rule as the Pixel 7 Pro. The initramfs stops its guard loop before `switch_root`; the kernel's read-only flags are what remain |
| `vendor/systemd/network/20-usb-gadget.network` | `/usr/lib/systemd/network` | Sets usb0 to 172.16.42.1/24 after handover. A replug needs the USB rescue below: without it the link stays dead until a reboot |
| `vendor/systemd/logind.conf.d/10-omamobile-power-key.conf` | `/usr/lib/systemd/logind.conf.d` | A short power press does not power the phone off. Same drop-in as the Pixel 7 Pro. On husky the forced reset is Power + Volume Up held 15-30 s ([BRINGUP-M1](../../device/husky/BRINGUP-M1.md) test 23) |
| `vendor/NetworkManager/conf.d/10-omamobile-usb.conf` | `/usr/lib/NetworkManager/conf.d` | Keeps NetworkManager off that link |
| `bin/omamobile-husky-display-start` + `vendor/systemd/system/omamobile-husky-display.service` + `display-manager.service.d/10-omamobile-husky.conf` | `/usr/bin`, `/usr/lib/systemd/system` | Loads gs-decon (kernel display PR) before the display manager, hang-safe: a synced marker that a start which never returns leaves behind keeps it off on the next boot, until `--retry`. First it allows the panel's DSI commands (`gs_dsim_cmd.allow_tx=1`, for brightness and 120 Hz), but only when the bootloader names the `google-hk3` panel on the command line, as the Pixel 9a's graphics start does for its panel. Then it sends the brightness systemd restored at boot again, which the panel could only take once `allow_tx` is on. On a kernel without the display PR (derekross/linux-omarchy-mobile#160) the DTB has no DECON0, so the unit is skipped by its condition and the screen stays on simple-framebuffer. With another panel name, `allow_tx` stays off and gs-decon runs read-only at 60 Hz |
| `vendor/modprobe.d/omamobile-husky-display.conf` | `/usr/lib/modprobe.d` | Blacklists gs_decon's autoload, so the display start loads it after `allow_tx`: gs-decon decides on 120 Hz at probe. Sets `screen_off=2`, as cheetah and tegu do: on DPMS off DECON stops its frames and the panel goes to sleep, and DPMS on wakes it |
| `vendor/modprobe.d/omamobile-husky-clk-acpm.conf` | `/usr/lib/modprobe.d` | Lets the GPU's ACPM clock move up to 890 MHz, stock's top (`zuma_gpu_max_khz`, kernel #157). The GPU thermal zone throttles it from 85 C. Without it the GPU stays at the bootloader's 150 MHz |
| `bin/omamobile-usb-rescue` + `vendor/systemd/system/omamobile-usb-rescue.service` | `/usr/bin`, `/usr/lib/systemd/system` (enabled by a vendor wants link) | Keeps the USB link across an unplug. The MAX77759's Type-C side opens its USB2 data switch (TCPC 0x25, register 0x93) on unplug and, with no Type-C driver, nothing closes it again until the bootloader runs: the phone stays off the bus after a replug. While VBUS is valid the script writes 0x09 back (the only register it writes) and logs every change of the switch, VBUS and the UDC state to the journal. It stands aside once a Type-C driver owns 0x25. It needs the hsi2c_11 bus (kernel #163, enabled by a bring-up overlay): without it the script says so and exits. Tested on a Pixel 8 Pro: unplug, replug, the link was back in two seconds with no reboot. Same logic as the Pixel 7 Pro's, on husky's bus |
| `vendor/modprobe.d/omamobile-max77759.conf` | `/usr/lib/modprobe.d` | Keeps max77759_charger, gpio_max77759, nvmem_max77759 and tcpci_maxim from autoloading: binding the PMIC creates the charger cell, which programs charge limits from the battery node. Blacklist only, so a runbook can still load them by hand. The fuel gauge and the MFD core are not blacklisted |
| `etc/omamobile-mirrorlist` | `/etc/pacman.d/omamobile-mirrorlist` | Where pacman finds the `[omamobile]` repository. Same file as the Pixel 7 Pro package |
| `omamobile-device-husky.install` | pacman hook | Adds `[omamobile]` to `pacman.conf` before `[omarchy]`, once. Same script as the Pixel 7 Pro package |
| `src/reboot-to.c` | `/usr/bin/reboot-to` | Reboot with a reason the bootloader understands. Same bytes as the Pixel 7 Pro package; the test checks |
| `device.conf` | `/usr/share/omamobile/device.conf` | The descriptor, the same bytes as `device/husky/device.conf` |

`./build [DIR]` compiles `reboot-to` from this directory, `./install DESTDIR [DIR]` stages the files, and `test/all` checks the copies when it is run from the repository.

Not in this package: the boot-success marker, the charger, cameras, and the slot-B image hook. Those stay out until each one has its own runbook. There is no lid drop-in: husky has no hinge.

## Firmware the phone needs

Nothing here is in the package. Wi-Fi needs four files from Google's firmware for the BCM4398 D0, which `tools/extract-vendor-firmware -d husky -s SKU` takes from the owner's own factory image or OTA `vendor.img`. They're installed under `/usr/lib/firmware/updates/brcm`, with the board-suffixed names brcmfmac loads first:

- `brcmfmac4398d0-pcie.google,zuma-husky.bin`: the firmware;
- `.txt`: the NVRAM for the phone's region, which `-s` picks from the hardware SKU (`grep hardware.sku /proc/bootconfig`);
- `.clm_blob`: the regulatory data;
- `.txcap_blob`: the TX capabilities.

The kernel side is [kernel #156](https://github.com/derekross/linux-omarchy-mobile/pull/156) (a draft). Nothing in this package starts or configures Wi-Fi: NetworkManager finds `wlp1s0` on its own.
