<!-- SPDX-License-Identifier: MIT -->
# omamobile-device-tegu

Omarchy Mobile's system support for the Google Pixel 9a (codename tegu,
Tensor G4 / zumapro). It sits beside Omarchy's own packages the way
`omarchy-mac` adds Apple Silicon support, and does for the 9a what
`omamobile-device-cheetah` does for the Pixel 7 Pro, with one difference:
the 9a's kernel is still being upstreamed, so part of its bring-up cannot be
packaged yet. What is here is what runs on in-tree drivers.

| Path | Installs to | What it does |
| --- | --- | --- |
| `bin/omamobile-tegu-graphics-start` + `vendor/systemd/system/omamobile-tegu-graphics.service` + `display-manager.service.d/10-omamobile-tegu.conf` | `/usr/bin`, `/usr/lib/systemd/system` (enabled by a vendor wants link) | Loads the GPU (panthor), the display controller (gs_decon), haptics (cs40l26_vibra), the torch (leds_lm3644), the battery gauge (max77779_battery) and the Bluetooth controller (hci_uart) at boot, in that order, after writing and syncing a marker. Each step keys on its own device node (`1f000000.gpu`, `19470000.display-controller`, the device-tree nodes of the rest), and the unit runs when the GPU or the display controller exists, so a DTB with the display but no GPU still gets its display. A load or bind that returns but fails (panthor without `mali_csffw.bin`, say) is logged and skipped, the rest still loads, and the marker is cleared; the unit then ends failed, and `--retry` tries the skipped steps again. Only a boot that hangs in a step leaves the marker: the next boot keeps all six off and says so, and `omamobile-tegu-graphics-start --retry` goes on from the step that failed (on the same boot too: the drivers already loaded stay as they are). Before `gs_decon`, and only when the command line says `exynos_drm.panel_name=google-tg4c`, it turns `gs_dsim_cmd.allow_tx` on, so the panel's DSI commands (brightness, sleep, 120 Hz; kernel #90) go to the panel the bring-up tested and no other: on another panel the display stays read-only at 60 Hz. The display manager waits for it. It also writes `/run/omamobile-tegu-display-card` (the display controller's DRM node by path, since the GPU may take card0) and, when the GPU came up, `/run/omamobile-tegu-gpu-ready.json` |
| `uwsm/env.d/omamobile-tegu-graphics` | `/usr/share/uwsm/env.d` | The session's side of the graphics start, sourced by uwsm (it walks `XDG_DATA_DIRS` too; a user's `~/.config/uwsm/env` runs after it): the KMS device from `/run/omamobile-tegu-display-card`, hardware GL when `/run/omamobile-tegu-gpu-ready.json` exists and llvmpipe otherwise, so a phone whose GPU did not come up still gets a desktop |
| `vendor/modprobe.d/omamobile-tegu-guards.conf` | `/usr/lib/modprobe.d` | Keeps those drivers (and the Wi-Fi, PCIe and NFC ones, for the day they are in tree) from autoloading ahead of the guard. No `install` lines: they would break the guard's own modprobe |
| `vendor/modprobe.d/omamobile-tegu-display.conf`, `omamobile-tegu-clk-acpm.conf` | `/usr/lib/modprobe.d` | 120 Hz as the ceiling and the panel really off on DPMS (the DSI commands themselves are allowed by the graphics start, for google-tg4c only); the GPU DVFS ceiling at 890 MHz |
| `bin/omamobile-tegu-aoc-start` + `vendor/systemd/system/omamobile-tegu-aoc.service` + `vendor/modprobe.d/omamobile-tegu-aoc.conf` | `/usr/bin`, `/usr/lib/systemd/system` (not enabled), `/usr/lib/modprobe.d` | Boots the AoC (audio and sensor DSP) hang-safe: Trusty, the GSA, the AoC drivers, `aoc-tegu.bin`, then waits for its 93 services. Ships disabled: see below |
| `bin/omamobile-bt-addr` + `vendor/systemd/system/omamobile-bt-addr@.service` + `vendor/udev/rules.d/80-omamobile-bt-addr.rules` | `/usr/bin`, `/usr/lib/systemd/system`, `/usr/lib/udev/rules.d` | Gives the BCM4383 its real Bluetooth address from the bootloader's device tree when the controller appears, powering it on once first (set on a never-powered controller, the kernel withdraws the index for good). The Pixel 7 Pro's script, with the extra waits the 9a needed |
| `bin/omamobile-tegu-usb-rescue` + `src/tegu-tcpc-switch.c` + `vendor/systemd/system/omamobile-tegu-usb-rescue.service` | `/usr/bin`, `/usr/lib/systemd/system` (enabled by a vendor wants link) | Closes the MAX77779's USB data switch after a cable replug while no Type-C driver owns the chip; with one loaded it exits. The helper reads the chip's identity and VBUS before its one write and never forces an address a driver holds |
| `bin/omamobile-tegu-charge-limit` + `vendor/udev/rules.d/75-omamobile-tegu-charger.rules` | `/usr/bin`, `/usr/lib/udev/rules.d` | Applies `/etc/omamobile/charge-limit` (a percentage, say `80`) to the charger when it appears; charging stops there and starts again 5 below. No file: charge to 100 % |
| `vendor/systemd/system-sleep/omamobile-tegu-wifi` | `/usr/lib/systemd/system-sleep` | Keeps Wi-Fi loaded across s2idle when `/etc/omamobile/wifi-keep-across-sleep` exists (the chip reloads its firmware on resume and iwd reconnects), otherwise unloads and reloads brcmfmac around the sleep; after a sleep that lost Wi-Fi it unloads for the rest of the boot. It reloads the in-tree `brcmfmac`; a phone still running an out-of-tree build of it keeps its own hook until the Wi-Fi series lands |
| `vendor/systemd/system-sleep/omamobile-tegu-nfc` | `/usr/lib/systemd/system-sleep` | Stops neard's poll loop before a sleep (polling through s2idle reset the palmtop; with it stopped, 35 of 35 cycles woke), reads `Polling` back and logs it, and starts the loop again after the wake if it was on. Powering the ST54L off as well, the workaround for a controller that did not answer on I2C after a wake (issue #132; fixed by linux-omarchy-mobile #131), runs only while `/etc/omamobile/nfc-power-off-across-sleep` exists: off by default, since its record is one wake that needed the power key and one that worked. Log: `/var/log/omamobile/nfc-sleep.log` |
| `vendor/systemd/system/linux-modules-cleanup.service.d/10-omamobile-tegu.conf` | `/usr/lib/systemd/system` | Holds off Arch's old-module cleanup: our kernels come as module tarballs, not pacman packages, and the next-boot and rollback trees must stay |
| `vendor/systemd/system.conf.d/10-omamobile-reboot-watchdog.conf`, `sleep.conf.d/10-omamobile.conf` | `/usr/lib/systemd` | A hung shutdown resets the phone after a minute; suspend means s2idle (no SoC sleep sequence yet, and `deep` does not wake) |
| `vendor/udev/rules.d/10-omamobile-storage.rules` | `/usr/lib/udev/rules.d` | Continues the initramfs storage guard: Android partitions stay hidden and the whole-disk node unusable |
| `vendor/udev/rules.d/20-omamobile-torch.rules`, `70-omamobile-dma-heap.rules`, `72-omamobile-feedbackd.rules` | `/usr/lib/udev/rules.d` | The torch tile may set the LED's brightness; libcamera's software ISP gets the DMA-BUF heaps; feedbackd gets the haptics |
| `vendor/systemd/network/20-usb-gadget.network`, `vendor/NetworkManager/conf.d/10-omamobile-usb.conf` | `/usr/lib/systemd/network`, `/usr/lib/NetworkManager/conf.d` | USB networking to a host (172.16.42.1, the host as a fallback route behind Wi-Fi); NetworkManager stays off the link |
| `src/reboot-to.c` | `/usr/bin/reboot-to` | Reboot with a reason the bootloader understands. One source with the cheetah package |
| `device.conf`, `etc/omamobile-mirrorlist` | `/usr/share/omamobile`, `/etc/pacman.d` | The device descriptor (a copy of `device/tegu/device.conf`) and the `[omamobile]` repository |

Bluetooth comes up powered at every boot, as on the Pixel 7 Pro
(`omamobile-bt-addr@` powers the controller on to set its address, and
leaves it on).

`./build [DIR]` compiles the C tools, `./install DESTDIR [DIR]` stages
everything and enables nothing beyond the two wants links, and `test/all`
runs the package tests in a scratch root (`OMAMOBILE_TEGU_ROOT`), with no
phone and no hardware.

The package does not mark the boot slot successful (Derek decides how that
works on the 9a), does not start Wi-Fi, NFC, the modem, the charger driver
or the cameras, and carries no vendor files and no per-phone data.

## What the kernel command line has to stop carrying

The bring-up boots with a command line that masks units and gates its own
start scripts. The package's units cannot run under it. For the package to
take over, `/chosen/bootargs` has to lose:

- `systemd.unit=multi-user.target` (graphical.target is the default again);
- every `systemd.mask=` for `sddm`, `display-manager`, `NetworkManager`,
  `bluetooth`, the `omamobile-*` units and the `tegu-*` units;
- `systemd.wants=tegu-curated-root-guard.service`,
  `systemd.wants=tegu-curated-autostart.service` and
  `systemd.wants=bluetooth.service`;
- the flags `omamobile.tegu-curated-root`, `omamobile.tegu-curated-autostart`,
  `omamobile.tegu-standard-reboot` and `omamobile.tegu-native-bluetooth`;
- `modprobe.blacklist=gs_decon,panthor,cs40l26_vibra,hci_uart,leds_lm3644`
  (`omamobile-tegu-guards.conf` does this now).

`mem_sleep_default=s2idle`, `panic=10`, `s3c2410_wdt.tmr_atboot=1` and
`cs40l26_vibra.max_buzz_ms=100` stay. Whether and when that DTB change
happens is the owner's call.

`s3c2410_wdt.tmr_atboot=1` is what resets the palmtop after a hang: the
watchdog runs from boot, so a hung graphics start ends in a reset and the
marker. The public tegu DTS carries `panic=10` but not that, so on it a
hang that does not panic ends at the power key (held about 30 s).

## The AoC start ships disabled

`omamobile-tegu-aoc-start` is the Pixel 7 Pro's AoC start with the 9a's
names (`154b0000.aoc`, `aoc-tegu.bin`, 93 services, the sensors' USF
channel through `aoc_channel_dev`). It needs a kernel whose device tree
enables the AoC, GSA and Trusty nodes; today the bring-up turns them on
with out-of-tree overlay modules, and so `omamobile-tegu-aoc.service` has
no wants link. Once a kernel enables them, `systemctl enable
omamobile-tegu-aoc.service` and reboot. A step that returns and fails is
named in the journal and clears the marker (a load that came back is not a
hang; `test/aoc-start` checks this). Only a boot that hangs in the start
leaves the marker, and then the next boot leaves the AoC off until
`omamobile-tegu-aoc-start --retry`.

## Firmware the phone needs

Nothing here is in the package; `tools/extract-vendor-firmware` and
`tools/phone-provision` take it from the owner's own factory image:

- `aoc-tegu.bin` (the AoC), `Top-tas2572RCA1.bin` and
  `Bottom-tas2572RCA1.bin` (the speaker amplifiers);
- `brcm/brcmfmac4383-pcie.bin`, `.clm_blob`, `.txcap_blob` and `.txt` (Wi-Fi);
- `updates/brcm/BCM.google,zumapro-tegu.hcd` (Bluetooth);
- `updates/cs40l26.wmfw` and `cs40l26.bin` (haptics);
- `arm/mali/arch11.8/mali_csffw.bin` (the GPU's firmware, from Mesa's
  packaging or the factory image).

## Moving from the bring-up

The bring-up on the first 9a lives in `/usr/local` and `/etc`, outside any
package. After installing 0.2.0 and before the reboot that drops the
command line above, take these off the phone by hand; the package cannot,
and a leftover copy in `/etc` wins over the package's file of the same name.

- Units and drop-ins in `/etc/systemd/system`: `tegu-curated-autostart`,
  `tegu-curated-root-guard`, `tegu-curated-session`,
  `tegu-curated-bluetooth-prepare`, `bluetooth.service.d/20-tegu-curated.conf`,
  `omamobile-tegu-audio` (keep it only while the AoC still needs the
  out-of-tree start; it conflicts with nothing in the package),
  `tegu-dtb-deadman`, `tegu-rt9470-early-read`, and the retired
  `tegu-battery`, `tegu-battery-hold`, `tegu-display`, `tegu-display-confirm`,
  `tegu-gpu`, `tegu-touch` (with `tegu-touch.service.d`), `tegu-normal-reboot`,
  `tegu-native-root-verify`, `tegu-native-root-deadman`, with their links
  in `multi-user.target.wants`, `graphical.target.wants` and
  `sysinit.target.wants`. `systemctl disable` each first.
- `/etc/modprobe.d/omamobile-tegu-*.conf` and
  `tegu-battery-gauge-bringup.conf` (the package's `omamobile-tegu-guards.conf`,
  `-display.conf` and `-clk-acpm.conf` replace them;
  `omamobile-tegu-fp-lhbm.conf` belongs to omamobile-fingerprint).
- `/etc/udev/rules.d/20-omamobile-tegu-gpu-always-on.rules` (the GPU's
  runtime suspend is qualified), `20-omamobile-tegu-torch-bringup.rules` and
  `70-omamobile-dma-heap.rules` (the package has them).
- `/etc/systemd/system.conf.d/10-tegu-bringup-watchdog.conf` (the package
  sets the reboot watchdog; the 10 s runtime watchdog was the bring-up's).
- `/etc/systemd/network/20-usb-gadget.network` (same content as the package's).
- `/usr/lib/systemd/system-sleep/omamobile-tegu-wifi` and `-nfc` (the
  package installs its own under the same names: pacman will refuse to
  overwrite unowned files, so remove them first).
- `/usr/local/bin/reboot-to`, `g7-*`, `nfc-ab`; `/usr/local/sbin/tegu-*`;
  `/usr/local/libexec/tegu-*`; `/usr/local/lib/omamobile-tegu`
  (`tegu-tcpc-switch` is `/usr/bin/tegu-tcpc-switch` now) and
  `/usr/local/lib/omamobile-tegu-curated`.
- `/var/lib/omamobile-tegu/curated` and the old per-kernel state
  directories (`battery`, `display`, `gpu`, `touch`, `keys`, `pmu`, `time`,
  `ui`, `wifi*`, `module-backup`); keep `audio`, `nfc` and `modem` while
  `omamobile-tegu-audio-up` and `omamobile-tegu-modem-up` still load from them.

`omamobile-tegu-audio-up`, `omamobile-tegu-modem-up` and the out-of-tree
modules they load stay until the kernel carries their drivers and device
tree nodes; the package's guards and theirs do not load the same modules.
So when a smoke report from the palmtop (`tools/phone-smoke`) lists Wi-Fi
and NFC as loaded beside this package, it was `omamobile-tegu-audio-up`
that loaded them, from its own staged copies, not the package: the package
blacklists both and starts neither.

Licence: MIT.
