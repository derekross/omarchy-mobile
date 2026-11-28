<!-- SPDX-License-Identifier: MIT -->
# omamobile-device-achilles6

Omamobile system support for the Lenovo Tab M10 FHD Plus (codename `achilles6`, TB-X606F, MediaTek Helio P22T / `MT6765` + `MT6357`).

| Path | Installs to | What it does |
| --- | --- | --- |
| `src/reboot-to.c` | `/usr/bin/reboot-to` | Reboot with a bootloader reason (`bootloader`, `recovery`, etc.) |
| `bin/omamobile-setup-system` | `/usr/bin` | System setup: UTF-8 locale, timezone, NTP (Omarchy lifecycle `setup-system`) |
| `bin/omamobile-bt-addr` + `vendor/udev/rules.d/80-omamobile-bt-addr.rules` + `vendor/systemd/system/omamobile-bt-addr@.service` | `/usr/bin`, `/usr/lib/udev/rules.d`, `/usr/lib/systemd/system` | Derives a stable locally-administered Bluetooth `BD_ADDR` via `systemd-id128 machine-id --app-specific=<UUID>` (without exposing `/etc/machine-id`) and programs it onto `hciN` via `btmgmt` |
| `bin/omamobile-wifi-start` + `vendor/systemd/system/omamobile-achilles6-wifi.service` | `/usr/bin`, `/usr/lib/systemd/system` (enabled by vendor wants link) | Brings up MediaTek CONSYS `gen4m` Wi-Fi (`wlan0`) at boot behind a synced hang marker (`/var/lib/omamobile/wifi-bringup-started`, retry with `--retry`) |
| `vendor/systemd/system/omamobile-achilles6-cpus.service` | `/usr/lib/systemd/system` (enabled by vendor wants link) | Onlines secondary CPU cores after boot (boot cmdline uses `maxcpus=4` during early init) |
| `vendor/udev/rules.d/10-omamobile-storage.rules` | `/usr/lib/udev/rules.d` | Continues the initramfs storage guard: makes `mmcblk*` whole disks, `boot0`/`boot1`, `gp0-3`, and `mmc_rpmb` mode `0000`, and hides non-`userdata` partitions from desktop automounters |
| `vendor/systemd/network/20-usb-gadget.network` | `/usr/lib/systemd/network` | Configures USB NCM gadget networking (`172.16.42.1/24`, `IgnoreCarrierLoss=yes`, `KeepConfiguration=yes`, no default route/DNS so Wi-Fi stays default) |
| `vendor/NetworkManager/conf.d/10-omamobile-usb.conf` | `/usr/lib/NetworkManager/conf.d` | Keeps NetworkManager off the `usb0` gadget link |
| `vendor/NetworkManager/conf.d/15-omamobile-achilles6-wifi.conf` | `/etc/NetworkManager/conf.d` | Marks MediaTek virtual `ap*`/`p2p*` interfaces unmanaged so NetworkManager uses `wlan0` |
| `vendor/NetworkManager/conf.d/zz-omamobile-wifi-powersave.conf` | `/etc/NetworkManager/conf.d` | Keeps Wi-Fi power save disabled for `gen4m` stability |
| `vendor/systemd/logind.conf.d/10-omamobile-power-key.conf` | `/usr/lib/systemd/logind.conf.d` | Short power press opens the shell menu instead of powering off |
| `vendor/systemd/sleep.conf.d/10-omamobile.conf` | `/usr/lib/systemd/sleep.conf.d` | Disables unverified suspend/hibernation states |
| `vendor/systemd/system-sleep/10-achilles6-wifi` | `/usr/lib/systemd/system-sleep` | Powers down `/dev/wmtWifi` before suspend (preventing `gen4m` IRQ 208 abort) and restores it on resume |
| `vendor/systemd/system.conf.d/10-omamobile-watchdog.conf` | `/usr/lib/systemd/system.conf.d` | Configures systemd hardware watchdog feeding |
| `uwsm/env.d/20-omamobile-achilles6-graphics` | `/usr/share/uwsm/env.d` | Forces software rendering (`WLR_RENDERER_ALLOW_SOFTWARE=1`) until PowerVR userspace support is available |
| `ucm2/conf.d/mt6765-mt6357/lenovo-tb-x606f.conf` + `ucm2/Lenovo/tb-x606f/HiFi.conf` | `/usr/share/alsa/ucm2` | ALSA UCM2 profile routing stereo speaker playback through `MT6357` `int_hp_buf` (`Headphone Left/Right Source = DAC`, `Headphone Switch = 1`, `Speaker Switch = 1`) |
| `etc/omamobile-mirrorlist` | `/etc/pacman.d/omamobile-mirrorlist` | Arch Linux ARM mirrorlist fallback |

`./build [DIR]` compiles `reboot-to`, `./install DESTDIR [DIR]` stages everything, and `test/all` runs the package staging tests.

Licence: MIT.
