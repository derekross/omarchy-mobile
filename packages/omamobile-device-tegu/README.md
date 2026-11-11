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
| `bin/omamobile-tegu-graphics-start` + `vendor/systemd/system/omamobile-tegu-graphics.service` + `display-manager.service.d/10-omamobile-tegu.conf` | `/usr/bin`, `/usr/lib/systemd/system` (enabled by a vendor wants link) | Loads the GPU (panthor), the display controller (gs_decon), haptics (cs40l26_vibra), the torch (leds_lm3644), the battery gauge (max77779_battery), the Bluetooth controller (hci_uart), NFC (nxp_nci_i2c) and Wi-Fi (the PCIe host, `phy_zuma_pcie` and `pcie_gs201` on a node that says `google,zuma-pcie`, else `pcie_zumapro`, then `brcmfmac`, only with the host's node, the Wi-Fi DMA pool and the board's BCM4383 firmware, `updates/brcm/brcmfmac4383-pcie.google,zumapro-tegu.bin` as `tools/extract-vendor-firmware` installs it) at boot, in that order, after writing and syncing a marker. Each step keys on its own device node (`1f000000.gpu`, `19470000.display-controller`, the device-tree nodes of the rest), and the unit runs when the GPU or the display controller exists, so a DTB with the display but no GPU still gets its display. A load or bind that returns but fails (panthor without `mali_csffw.bin`, say) is logged and skipped, the rest still loads, and the marker is cleared; the unit then ends failed, and `--retry` tries the skipped steps again. Only a boot that hangs in a step leaves the marker, and there is one marker for every step: a hang in the last step, Wi-Fi, also keeps the GPU and the display off on the next boot, so a boot with no display after a Wi-Fi hang is this marker, not a display fault. The next boot keeps all of them off and says so, and `omamobile-tegu-graphics-start --retry` goes on from the step that failed (on the same boot too: the drivers already loaded stay as they are). Before `gs_decon`, and only when the command line says `exynos_drm.panel_name=google-tg4c`, it turns `gs_dsim_cmd.allow_tx` on, so the panel's DSI commands (brightness, sleep, 120 Hz; kernel #90) go to the panel the bring-up tested and no other: on another panel the display stays read-only at 60 Hz. The display manager waits for it. It also writes `/run/omamobile-tegu-display-card` (the display controller's DRM node by path, since the GPU may take card0) and, when the GPU came up, `/run/omamobile-tegu-gpu-ready.json` |
| `uwsm/env.d/omamobile-tegu-graphics` | `/usr/share/uwsm/env.d` | The session's side of the graphics start, sourced by uwsm (it walks `XDG_DATA_DIRS` too; a user's `~/.config/uwsm/env` runs after it): the KMS device from `/run/omamobile-tegu-display-card`, hardware GL when `/run/omamobile-tegu-gpu-ready.json` exists and llvmpipe otherwise, so a phone whose GPU did not come up still gets a desktop |
| `vendor/modprobe.d/omamobile-tegu-guards.conf` | `/usr/lib/modprobe.d` | Keeps those drivers (and the Wi-Fi, PCIe and NFC ones, for the day they are in tree) from autoloading ahead of the guard. No `install` lines: they would break the guard's own modprobe |
| `vendor/modprobe.d/omamobile-tegu-display.conf`, `omamobile-tegu-clk-acpm.conf` | `/usr/lib/modprobe.d` | 120 Hz as the ceiling and the panel really off on DPMS (the DSI commands themselves are allowed by the graphics start, for google-tg4c only); the GPU DVFS ceiling at 890 MHz |
| `bin/omamobile-tegu-aoc-start` + `vendor/systemd/system/omamobile-tegu-aoc.service` + `vendor/modprobe.d/omamobile-tegu-aoc.conf` | `/usr/bin`, `/usr/lib/systemd/system` (enabled; also `omamobile-aoc.service`), `/usr/lib/modprobe.d` | Boots the AoC (audio and sensor DSP) hang-safe: Trusty, the GSA, the AoC drivers, `aoc-tegu.bin`, waits for its 93 services, then loads the TAS2572 amplifiers. See below |
| `bin/omamobile-bt-addr` + `vendor/systemd/system/omamobile-bt-addr@.service` + `vendor/udev/rules.d/80-omamobile-bt-addr.rules` | `/usr/bin`, `/usr/lib/systemd/system`, `/usr/lib/udev/rules.d` | Gives the BCM4383 its real Bluetooth address from the bootloader's device tree when the controller appears, powering it on once first (set on a never-powered controller, the kernel withdraws the index for good). The Pixel 7 Pro's script, with the extra waits the 9a needed |
| `bin/omamobile-tegu-usb-rescue` + `src/tegu-tcpc-switch.c` + `vendor/systemd/system/omamobile-tegu-usb-rescue.service` | `/usr/bin`, `/usr/lib/systemd/system` (enabled by a vendor wants link) | Closes the MAX77779's USB data switch after a cable replug while no Type-C driver owns the chip, also when the gadget still reads "configured" from before the unplug (dwc3 never hears of one without a Type-C driver, so the switch is read every 10 s while configured); with one loaded it exits. The helper reads the chip's identity and VBUS before its one write and never forces an address a driver holds |
| `bin/omamobile-tegu-charge-limit` + `vendor/udev/rules.d/75-omamobile-tegu-charger.rules` | `/usr/bin`, `/usr/lib/udev/rules.d` | Applies `/etc/omamobile/charge-limit` (a percentage, say `80`): charging stops there and starts again 5 below. With the kernel's `max77779-charger` driver, which has charge inhibit and no end threshold, udev runs it on every battery change and it switches `charge_behaviour` between `inhibit-charge` and `auto` by the battery's capacity. No file: charge to 100 % |
| `bin/omamobile-setup-system` | `/usr/bin` | System setup for Omarchy's lifecycle (omamobile-firstboot runs it): UTF-8 locale, timezone, NTP, and enables the sensor proxy and the NFC link opener (`omamobile-nfc-open`). Not the fingerprint service, speaker protection or the GNSS socket yet (see the script) |
| `vendor/systemd/system-sleep/omamobile-tegu-wifi` | `/usr/lib/systemd/system-sleep` | Keeps Wi-Fi loaded across s2idle when `/etc/omamobile/wifi-keep-across-sleep` exists (the chip reloads its firmware on resume and iwd reconnects; the hook checks that from a transient unit, `omamobile-tegu-wifi-check`, so the lock screen doesn't wait for it), otherwise unloads and reloads brcmfmac around the sleep; after a sleep that lost Wi-Fi it unloads for the rest of the boot. It reloads the in-tree `brcmfmac`; a phone still running an out-of-tree build of it keeps its own hook until the Wi-Fi series lands |
| `vendor/systemd/system-sleep/omamobile-tegu-nfc` | `/usr/lib/systemd/system-sleep` | Stops neard's poll loop before a sleep (polling through s2idle reset the palmtop; with it stopped, 35 of 35 cycles woke), reads `Polling` back and logs it, and starts the loop again after the wake if it was on. Powering the ST54L off as well, the workaround for a controller that did not answer on I2C after a wake (issue #132; fixed by linux-omarchy-mobile #131), runs only while `/etc/omamobile/nfc-power-off-across-sleep` exists: off by default, since its record is one wake that needed the power key and one that worked. Log: `/var/log/omamobile/nfc-sleep.log` |
| `vendor/systemd/system-sleep/omamobile-tegu-cpuidle` | `/usr/lib/systemd/system-sleep` | Keeps the cores out of the core power-down state (C2) through a sleep: with every core in C2 during s2idle the palmtop sometimes never woke (6 to 135 sleeps), and with C2 off for the sleep 300 of 300 came back. Disables every idle state deeper than state0 before the sleep and enables the ones it disabled after the wake, so the cores still power down while awake; does nothing on a kernel without deeper states, or while `/etc/omamobile/cpuidle-keep-across-sleep` exists (for testing C2 in the sleep). A sleep written straight to `/sys/power/state` skips it. [SLEEP-PLAN](../../device/tegu/SLEEP-PLAN.md) S1 |
| `vendor/systemd/system/linux-modules-cleanup.service.d/10-omamobile-tegu.conf` | `/usr/lib/systemd/system` | Holds off Arch's old-module cleanup: our kernels come as module tarballs, not pacman packages, and the next-boot and rollback trees must stay |
| `vendor/systemd/system.conf.d/10-omamobile-reboot-watchdog.conf`, `sleep.conf.d/10-omamobile.conf` | `/usr/lib/systemd` | A hung shutdown resets the phone after a minute; suspend means s2idle (no SoC sleep sequence yet, and `deep` does not wake), written to the kernel as one state (`SuspendState=freeze`), so a sleep a driver refused isn't tried a second time |
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
works on the 9a) and does not start the modem. NFC and Wi-Fi come up from
the graphics start when the device tree describes them, and the charger and
the cameras load from the device tree on their own. It carries no vendor
files and no per-phone data.

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

## The AoC start at boot

`omamobile-tegu-aoc-start` is the Pixel 7 Pro's AoC start with the 9a's
names (`154b0000.aoc`, `aoc-tegu.bin`, 93 services, the sensors' USF
channel through `aoc_channel_dev`), plus the TAS2572 amplifiers once the
AoC is online. It runs at every boot (a wants link) and answers to
`omamobile-aoc.service`, the name the sensor proxy and the fingerprint
service order themselves after. It needs a kernel whose device tree
enables the AoC, GSA and Trusty nodes (the kernel branch `tegu-dt-aoc`);
on a device tree without the AoC node the unit's condition skips it, so
the bring-up's overlay boots are unaffected. A step that returns and fails is
named in the journal and clears the marker (a load that came back is not a
hang; `test/aoc-start` checks this). Only a boot that hangs in the start
leaves the marker, and then the next boot leaves the AoC off until
`omamobile-tegu-aoc-start --retry`.

## Firmware the phone needs

Nothing here is in the package; `tools/extract-vendor-firmware` and
`tools/phone-provision` take it from the owner's own factory image:

- `aoc-tegu.bin` (the AoC), `Top-tas2572RCA1.bin` and
  `Bottom-tas2572RCA1.bin` (the speaker amplifiers);
- `brcm/brcmfmac4383-pcie.google,zumapro-tegu.bin`, `.clm_blob`, `.txcap_blob`
  and `.txt` (Wi-Fi, the board-suffixed names brcmfmac loads first);
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

## The modem at boot (opt-in)

`omamobile-tegu-modem-up` starts the CP once per boot: the kernel's own
drivers when it carries them (`cpif`, `pcie_gs201_cp` and the device tree's
`cpif` node), else the bring-up modules in `/var/lib/omamobile-tegu/modem`.
In order, it:

1. takes a sleep inhibitor (suspend with the CP up isn't qualified on the
   9a, so nothing sleeps until the reboot);
2. writes and syncs a latch, `/var/lib/omamobile/modem-bringup-started`;
3. loads the drivers (refusing a `pcie_gs201_cp` already loaded without
   `allow_hw`);
4. runs the modem profile's read-only NV check, which needs CPIF loaded;
5. starts the profile and waits for CP ONLINE;
6. with `--phone`, starts `omamobile-sitd` and, when installed,
   `omamobile-mmd` for Phone and Messages.

The latch stays from step 2 until the profile's unit stops at shutdown
with the evidence of a clean stop. The latch names the profile unit's
invocation once the CP is ONLINE. At the stop, the profile's ExecStop
(`omamobile-vendor-chroot modem stop`, from `omamobile-modem` 0.1.18 on)
powers the CP off and, once it has seen it OFFLINE, writes its invocation ID
to `/run/omamobile-modem/stop-<invocation>`, the stop witness; the unit's
ExecStopPost (`omamobile-tegu-modem-up --stopped`) removes the latch only
when it finds that witness for the invocation the latch names and systemd's
result is success. A stop that failed or timed out, a hang, a reset or a held
power key leaves the latch (the witness lives in `/run`, so a reset leaves
none). The starter refuses to load anything when the installed
`omamobile-modem` lacks the witness
(`/usr/lib/omamobile-vendor/modem/stop-witness-version`, 1), since no stop
could then remove the latch.

A start that never reached ONLINE leaves the latch, and every later start
refuses until you've read `/var/log/omamobile/modem.log` and that boot's
journal and removed it. A boot that ended with the modem up and no
confirmed stop had a working bring-up, so the next boot moves its latch
aside (`modem-bringup-started.unclean-<time>`) and starts the modem; only a
second unclean end in a row, with that copy still there, holds until you've
looked (`rm /var/lib/omamobile/modem-bringup-started*`, then
`systemctl start omamobile-tegu-modem-boot`). A confirmed clean stop removes
the copies. It also refuses a second start in a boot that already loaded
CPIF. Never stop the modem by hand; the reboot's shutdown stops it.

With #403, a `reboot-to` (and so `bin/omamobile push`) with the CP ONLINE
notes the boot it ends, and the next boot clears that boot's latch and
starts the modem on its own: a deliberate restart, asked for and recorded
before the reboot, isn't the reset loop the latch guards against, and the
reboot takes the CP down with the SoC. On the 9a that path passed once, on
2026-11-03 (TELEPHONY-PLAN 2.7).

The in-tree driver branch (the kernel's `cpif` and `pcie_gs201_cp`, taken
when the device tree has a `cpif` node) first ran through this script on
2026-11-09, on a published-style kernel with the device's `modem-cpif`
overlay: three boots by the boot unit, two confirmed stops and four GNSS
sessions (TELEPHONY-PLAN 2.9).

### Starting it at boot

`omamobile-tegu-modem-boot.service` runs `omamobile-tegu-modem-up --phone
--gnss` at boot. The package installs it disabled: it is opt-in while
marking slot B on the 9a is on hold, because the unit can't tell whether B
is marked and a reset with B unmarked spends one of ABL's three tries.
Before enabling it:

- **Slot B marked successful.** Otherwise every reset spends one of ABL's
  three tries, and at zero it boots stock on slot A, which has overwritten
  `userdata`.
- **A kernel with linux-omarchy-mobile#172** (the PERIC0 GPIO bus clock
  kept on). Without it the modem's GPIO writes hang the palmtop within
  minutes. The published kernel has it; a test kernel built from an older
  tree may not: check that
  `/sys/kernel/debug/clk/zumapro_gpio_peric0/clk_flags` reads
  `CLK_IS_CRITICAL`.
- **The charger in** for the first boots.

Then `systemctl enable omamobile-tegu-modem-boot`. With it on the battery
drains as if awake, since the palmtop no longer suspends.

An enabled unit is skipped, not failed, on a phone that can't run it:
without the three files `tools/phone-provision` puts on the phone (the modem
chroot, the NV checksums, the board properties), or without CP drivers.
The drivers are the kernel's when the device tree has a `cpif` node, or else
the owner's bring-up modules in `/var/lib/omamobile-tegu/modem`. The board's
own device tree has only the `modem` node under the PCIe link; the `cpif`
node comes from the device's `modem-cpif` overlay, which
`bin/omamobile images` applies from the descriptor's `DTB_OVERLAYS`.

**Rollback:** `systemctl disable omamobile-tegu-modem-boot`, then reboot.
If the palmtop resets before you can log in, the latch does the work: the
boot after a reset with the modem up starts it once more, and the boot
after a second reset in a row finds the latch and its copy and doesn't
start the modem, so log in then, disable the unit and remove both. On a 9a
whose slot B isn't marked successful, disable the unit after the first reset
instead of letting the retry run: every reset spends one of ABL's three
tries, and the retry would spend a second. If it still doesn't come up, hold
Volume Down + Power for fastboot and boot a known-good image set.

## Optional Phone and Messages attachment

`omamobile-telephony-tegu` is an opt-in companion package; it installs the
ModemManager-compatible bridge and session agent without enabling or
starting the radio. Its attended helper attaches only to a running tegu
modem and sitd. See its [runbook](../omamobile-telephony-tegu/README.md).

This device package supplies sitd's modem-unit policy under
`omamobile-sitd.service.d/10-device-modem.conf`: Requisite and ordering on
`omamobile-tegu-modem.service`, with a CP ONLINE check before any future
sitd start. It supplies no CP starter and enables neither service. It
also prevents the generic modem runtime unit from starting on tegu.
Remove any old full sitd unit copy in `/etc` using the runbook's attended
migration; the package does not delete human overrides.
