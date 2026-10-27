<!-- SPDX-License-Identifier: MIT -->
# Road map

Where Omarchy Mobile stands, what a good everyday phone still needs, and the order we plan to get there. Last updated 2026-10-26, from the subsystem plans in [`device/cheetah/`](../device/cheetah) and [NOTES.md](../device/cheetah/NOTES.md). The reference device is the Pixel 7 Pro (`cheetah`, gs201); other devices are in [DEVICES.md](DEVICES.md).

**In one paragraph:** the Pixel 7 Pro boots mainline Linux and Omarchy from slot B and runs Omarchy on the phone: 120 Hz display with brightness and real screen-off, GPU acceleration, touch, Wi-Fi (now across s2idle), Bluetooth audio, battery level, wired charging under a temperature guard, haptics, torch, sensors with auto-rotate, GPS with an outdoor fix, NFC tags (read, write, tap to open a link), fingerprint unlock with a PIN or password, all four cameras in our own camera app, and the built-in speakers and microphones. Calls, SMS and mobile data are next: the modem boots and answers requests without a SIM, and the next step, registration (M4.2), needs one. It doesn't yet sleep by itself when the screen is off. The modem is the long pole, and calls come weeks to months after registration. On the software side the phone still needs a finished home screen, more quick settings, notifications that matter, Android apps and over-the-air updates.

Effort figures below are quoted from the plans, which assume one developer writing code and the human running each gated step on the phone. They are estimates, not promises: every stage so far has turned up at least one surprise.

## 1. Where things stand

Statuses: **works** (on by default, verified on the phone), **partial** (works, with a known gap), **in progress** (some gates passed on the phone, or code built and waiting for its runbook), **not started**.

| Subsystem | Status | Why | Plan |
| --- | --- | --- | --- |
| Boot, storage, USB networking | works | Slot B with stock kept on slot A, the read-only storage guard, Arch on `userdata`; USB reconnects after a replug through `omamobile-usb-rescue` until the Type-C driver lands | [BRINGUP-M1](../device/cheetah/BRINGUP-M1.md), [USB-C-PLAN](../device/cheetah/USB-C-PLAN.md) |
| Display | works | Our flip-only KMS driver at 120 Hz, brightness, DPMS, the panel really off with the screen | [DISPLAY-PLAN](../device/cheetah/DISPLAY-PLAN.md) |
| GPU | works | Mali-G710 on Panthor and patched Mesa, DVFS through ACPM | [GPU-PLAN](../device/cheetah/GPU-PLAN.md), [ACPM-PLAN](../device/cheetah/ACPM-PLAN.md) |
| Touch, buttons | works | Our Synaptics TouchComm driver; `gpio-keys` | [NOTES](../device/cheetah/NOTES.md) |
| Wi-Fi | works | brcmfmac behind a restricted DMA pool. The D3 handshake keeps it up across s2idle (S5b-3; the S5c soak passed 31 of 31 freezes, 2026-10-19) | [WIFI-BATTERY-PLAN](../device/cheetah/WIFI-BATTERY-PLAN.md), [SUSPEND-PLAN](../device/cheetah/SUSPEND-PLAN.md) S5 |
| Bluetooth | works | Pairing and A2DP audio; headset calls (HFP) need the chip's SCO routing changed, not yet done | [BLUETOOTH-PLAN](../device/cheetah/BLUETOOTH-PLAN.md), [AUDIO-PLAN](../device/cheetah/AUDIO-PLAN.md) |
| Battery | works | MAX77759 fuel gauge with the stock battery model; it reads Charging and Full on the cable since our max17042 status fix (2026-10-18), now sent upstream | [WIFI-BATTERY-PLAN](../device/cheetah/WIFI-BATTERY-PLAN.md) |
| Charging | works | The charger driver and its temperature guard load at boot (device-cheetah 0.1.33; G1, G2 and D1 passed, replug included, 2026-10-19). Type-C (B4a, B4b) not yet run | [USB-C-PLAN](../device/cheetah/USB-C-PLAN.md) |
| Haptics, torch | works | CS40L26 through feedbackd; LM3644 with a quick-settings tile | [HAPTICS-TORCH-PLAN](../device/cheetah/HAPTICS-TORCH-PLAN.md) |
| AoC (audio and sensor DSP) | works | Starts at boot through the GSA and Trusty | [AOC-PLAN](../device/cheetah/AOC-PLAN.md) |
| Sensors | works | Accelerometer, light, proximity and compass at every boot; auto-rotate | [AOC-PLAN](../device/cheetah/AOC-PLAN.md) C6, [USF-PROTOCOL](../device/cheetah/USF-PROTOCOL.md) |
| Speakers, microphones | partial | Both speakers in stereo under Google's speaker protection, mics at stock gain. The everyday level (stage `media`, 737/10) is about 17 dB below stock and sounds thin; stock's 817/17 still trips the coil temperature (C9d-3..6). Next: a measured speaker filter (C9g), the V/I feedback and impedance work (C9d-7/8), and stock's Waves processing on the AoC (T3b/T4) | [AOC-PLAN](../device/cheetah/AOC-PLAN.md) C8-C10, [AOC-TUNING-RESEARCH](../device/cheetah/AOC-TUNING-RESEARCH.md) |
| CPU idle, power | partial | C2 idle on all cores is in the default DTB; screen-off drain measured off the cable (S7: 434 mA awake, 312 mA in s2idle), the B0 baseline and the C2 A/B (`power-ab c2`) not yet | [POWER-PLAN](../device/cheetah/POWER-PLAN.md) |
| Suspend | in progress | s2idle freezes and wakes cleanly (S1-S4), with Wi-Fi up across sleep (S5b-3; S5c, 31 of 31) and the AoC and sensors working across it (S6). Screen off it draws 312 mA in s2idle against 434 mA awake, about 16 h of standby (S7, 2026-10-19). Not on by default: the screen-off policy (S8: Power to sleep and wake, idle sleep, a day of use) is next. Deep sleep (SYS_SLEEP), which stock's 32-50 mA standby needs, is research and not started | [SUSPEND-PLAN](../device/cheetah/SUSPEND-PLAN.md) |
| GNSS | works | Google's GNSS stack in a chroot behind GeoClue, on demand from the Location tile; first outdoor fix (G4b), GNOME Maps through GeoClue (G5-2) | [GNSS-PLAN](../device/cheetah/GNSS-PLAN.md) |
| NFC | works | ST54J through st-nci with our plain-NCI link, loaded at boot; neard reads and writes tags, and a tag with a web link opens it. Card emulation and payments are out of scope | [RADIOS-CAMERA-PLAN](../device/cheetah/RADIOS-CAMERA-PLAN.md) §3 |
| Fingerprint | works | Google's HAL and Trusty TA on mainline (F3-F9), fprintd and our libfprint driver; the lock screen unlocks with a finger, PIN or password is the user's choice, enrollment from the shell (F10-F18); a verify survives system sleep and an enrollment interrupted by sleep fails cleanly (libfprint 1.6) | [FINGERPRINT-PLAN](../device/cheetah/FINGERPRINT-PLAN.md) |
| Modem | in progress | The S5300 boots Google's firmware from RAM copies of its NV to ONLINE on a Gen3 x2 link and serves the SIT IPC (SIM state, radio state, AT): M3.4.5b-M4.1i, 2026-10-13. Registration, SMS, data and calls (M4.2+) need a SIM. Without a SIM, `omamobile-mmd` (a ModemManager-compatible bridge) shows the modem to NetworkManager, GNOME Calls and Chatty (T0/T1, 2026-10-14). Our own Phone and Messages apps (omatel) are built and tested offline. A reboot with the modem up hung once (M4.1i); the fix passed on the phone (M4.1j, M4.1k, 2026-10-13). Next: the first SIM test, ready to run | [MODEM-PLAN](../device/cheetah/MODEM-PLAN.md) |
| Cameras | partial | Ultrawide (Sony IMX386) works through libcamera (CAM5); front (S5K3J1) gives real images, raw and through libcamera (F.5-F.7); main (Samsung S5KGN1) and telephoto (S5KGM5), both C-PHY, stream through libcamera since the sensors keep each line under the CSIS DMA's limit; the telephoto is fixed-focus (sharp at a distance, soft up close), because its lens (SEM1215) holds its I2C bus when driven, so it isn't driven yet. 30 and 60 fps on the main and telephoto (CAM5.5), autofocus on the main camera, tuning through libcamera 0.7.2-4.18, and omacam, our camera app with zoom, lens switching and video, as the default (omamobile-apps 0.2.0). Picture quality ([CAMERA-QUALITY-PLAN](CAMERA-QUALITY-PLAN.md)): chroma noise reduction and defective pixel correction in libcamera, and Night and HDR in omacam 0.3.3, merged from raw frames on the phone | [CAMERA-PLAN](../device/cheetah/CAMERA-PLAN.md) |
| Phone shell | partial | Status bar, swipeable home screens with apps and widgets and an edit mode, quick settings with 19 tiles and a tile editor, launcher, switcher, the lock screen with PIN pad and fingerprint, squeekboard on demand. OWL widget support merged (the user's own widgets behind a feature flag); Omarchy's default-agent invitation at first login (omamobile-shell 0.2.8); a home pill (swipe up for Home, swipe and hold for recents), the dock hidden under apps and Power waking a dark screen (0.2.17, #43); the touch audit's quick wins (0.2.18, #46, [TOUCH-PLAN](TOUCH-PLAN.md)); desktop-shaped system dialogs | [`packages/omamobile-shell`](../packages/omamobile-shell), [NOTES](../device/cheetah/NOTES.md) "Phone UX to-dos" |
| Android apps (Waydroid) | in progress | Planned and packaged offline: the kernel options are found and checked, `omamobile-waydroid` is drafted with the container kept away from debugfs, the camera nodes and every block device. Nothing run on the phone yet | [WAYDROID-PLAN](../device/cheetah/WAYDROID-PLAN.md) |
| Installer | testing | `tools/build-rootfs` builds the root image, `tools/install-phone` checks the phone and writes only slot B and `userdata`, first boot sets the phone up and `tools/phone-provision` adds the user's own firmware. First clean reinstall on 2026-10-13 ([REINSTALL-RUNBOOK](../device/cheetah/REINSTALL-RUNBOOK.md)); builds from source only so far, no downloadable images yet | [RELEASES](RELEASES.md) |
| Updates | partial | Packages ship through a signed `[omamobile]` pacman repository and `omarchy update`, but the repository is copied to the phone over USB (`tools/repo-push`): `pkgs.omamobile.org` is set up with development and stable channels (`tools/repo-publish`), and nothing is published there yet; kernel updates go through `bin/omamobile push` | [CONTRIBUTING](../CONTRIBUTING.md) §4 |
| Upstream kernel | in progress | `omamobile` is published on GitHub (146 commits on v7.3-rc6) and moves forward without rewrites (`tools/publish-kernel`). First patch sent upstream: the max17042 status fix, reviewed by Hans de Goede on 2026-10-19, waiting for the maintainer | [KERNEL-PUBLISH](../device/cheetah/KERNEL-PUBLISH.md) |

## 2. What an everyday phone still needs

In priority order: the first four make it a phone, the rest make it a good one.

| Need | Today | What's missing |
| --- | --- | --- |
| **Calls** | no | Registration and IMS (VoLTE: most networks have no 2G/3G left) with a SIM (M4.2, ready to run), then the AoC voice path and an earpiece mode under the speaker protection (M5, T4). The front end (`omamobile-mmd`) and the dialers (GNOME Calls, omaphone) exist |
| **SMS** | no | The SIM test (M4.4, over IMS); `omamobile-sitd`, the bridge, Chatty and omamessages exist |
| **Mobile data** | no | The SIM test (M4.3, IPv4 on `rmnet0`), NetworkManager integration and IPv6 (T3), then suspend with the modem online (M6) |
| **Standby and battery life** | 312 mA in s2idle (S7), about 16 h; sleep only when asked for | Sleep on screen-off by default (S8). s2idle alone won't reach Android's standby (the plan quotes about 274-286 mA in s2idle against 32-50 mA in deep sleep): deep sleep (SYS_SLEEP) is the real fix |
| **A phone home screen** | pages, apps, built-in widgets | Touch testing, folders, user-built widgets (in progress) |
| **Notifications** | desktop-style | Phone-shaped banners, a shade with actions, heads-up on the lock screen, do-not-disturb; incoming calls and SMS once the modem works |
| **Quick settings** | 19 tiles, editable | On-phone checks of airplane, hotspot and mobile data; mobile data needs the modem's M4 |
| **Loud, full speakers** | about 17 dB below stock, thin | C9g filter, then stock gains with verified protection (C9), or Waves on the AoC (T3b-T6) |
| **Cameras** | all four, in omacam, with Night and HDR | Single-shot quality (measured colour, Q3; the merge on the GPU, Q5.4), driving the telephoto's lens (SEM1215 holds its I2C bus when driven, so the telephoto is fixed-focus) |
| **Updates over the air** | over USB | Publish the `[omamobile]` repository on `pkgs.omamobile.org` (set up, empty) so `omarchy update` reaches it on Wi-Fi; a phone-friendly update notice; kernel updates as a package instead of `bin/omamobile push` |
| **Apps: store and updates** | pacman in a terminal | A touch app store front end (GNOME Software or a small one of ours over pacman and Flathub), updates included |
| **Android apps** | no | Waydroid ([WAYDROID-PLAN](../device/cheetah/WAYDROID-PLAN.md), W0-W8) |
| **Safe charging by default** | on at boot, with the guard | Type-C (B4) for USB that survives a replug without the rescue service |
| **Accessibility** | none phone-specific | Font and display scaling from settings, the screen reader (Orca) with touch exploration, high contrast, larger touch targets in our plugins |
| **System dialogs, first run** | desktop-shaped | Keyring, polkit and portal dialogs, the screensaver, Omarchy's first run ([NOTES](../device/cheetah/NOTES.md), "Phone UX to-dos") |
| **Installer** | for developers | Downloadable images and a one-command install for people who don't build from source (§3.8, steps 5-7) |

## 3. The plan

Tracks in rough priority order. Most are independent and run in parallel; the arrows inside a track are hard dependencies. "Next" is the next concrete step, usually a gated runbook already written in the plan.

### 3.1 Telephony: modem, data, SMS, calls

The highest-value track and the longest. [MODEM-PLAN](../device/cheetah/MODEM-PLAN.md), [MODEM-CLIENT](../device/cheetah/MODEM-CLIENT.md):

```
M2.5, M3.1, M3.3-B, M3.4 CP ONLINE, M4.1 SIT IPC and clean reboots (passed) ─> M3.6 SysMMU
                                   │
                                   └─> M4.2-M4.4 with a SIM: registration, data, SMS ─> T2 bridge on the phone: Calls, Chatty, omaphone, omamessages
                                              │
                                              ├─> IMS (VoLTE) registration ─> M5 calls with audio ◄─ AoC voice path + earpiece mode (T4)
                                              └─> M4.6 modem at boot, M6 suspend with the modem online
```

| Milestone | Effort (from the plans) | Next concrete step |
| --- | --- | --- |
| M3.4: Google's boot loader for the modem in the RAM-only NV chroot, firmware over PCIe, CP ONLINE | Done 2026-10-13: ONLINE on a Gen3 x2 link (M4.1d), 10 min clean, NV unchanged | - |
| M4.1: the CP serves SIT; reboots with the modem up | Done 2026-10-13: the IPC init handshake completes and the CP answers SIT without a SIM once it has the phone's board id (M4.1h, M4.1i); a reboot with the modem up no longer hangs (M4.1j) or warns (M4.1k) | - |
| M3.6: the HSI1 SysMMU confines the modem's DMA | 1 week | Offline |
| M4.2-M4.4: registration, a data call and SMS | `omamobile-sitd` 0.3.3 is written and passes against a simulator (locked SIM, IMS failure and no-audio cases included); on the phone, days if the carrier behaves like the one the IMS values came from, weeks if not | The SIM: MODEM-PLAN "M4.2-M4.7: the first SIM test"; which SIM in MODEM-CLIENT 1.4 |
| IMS (VoLTE) registration | Part of M4.2's start-up; its values are proven on one network only (a T-Mobile-network MVNO). Since 0.3.2 a failure keeps data | The SIM test; another network may need its own IMS values |
| Front end | Done offline: `omamobile-mmd` serves ModemManager's API and passed on the phone without a SIM (T1, 2026-10-14) | T2: GNOME Calls, Chatty, omaphone and omamessages against the real modem (runbook S11) |
| Calls and messages UI | omatel (Phone, Messages, their agent) and the shell's call card and lock-screen calls are built and tested offline | After T2; MMS is T3 |
| M5: calls with audio | 14-25 days (TELEPHONY-APPS-PLAN T4): the earpiece mode under speaker protection, a Voice Call UCM verb, speakerphone, Bluetooth | Design only; until then calls connect silent (`[audio] card = none`) |
| M6: suspend with the modem online | after S8 and M4 | Design only |

The modem's NV is never written from Linux: the chroot works on checksum-verified RAM copies.

### 3.2 Standby and battery

[SUSPEND-PLAN](../device/cheetah/SUSPEND-PLAN.md), [POWER-PLAN](../device/cheetah/POWER-PLAN.md), [USB-C-PLAN](../device/cheetah/USB-C-PLAN.md):

1. **S5c** (Wi-Fi across sleep, soaked: passed 2026-10-19, 31 of 31), **S6** (AoC and sensors across sleep: passed), **S7** (battery numbers: 434 mA awake, 312 mA in s2idle, screen off), **S8** (screen-off sleep on by default: Power to sleep and wake, idle sleep, a day of use; the sleep hook and `sleep.conf` drop-in already ship in `omamobile-device-cheetah` and keep Wi-Fi up). Next: S8.
2. **Measure drain** off the cable: POWER-PLAN's B0 baseline and `power-ab c2`.
3. **Deep sleep (SYS_SLEEP)**: the gs201 SoC sleep sequence through the PMU and ACPM, as stock does. Researched in SUSPEND-PLAN §5, no estimate yet. This is what gets standby near Android's, and the single biggest battery item.
4. **Safe charging by default**: the temperature guard (B3g) and the charger at boot (D1) are done. Next: G3-G6 (optional, attended), then Type-C with role switching (B4a, B4b), under the dead-man switch.
5. **Power UX**: battery saver (CPU and refresh-rate caps, Wi-Fi power save), a short power-key press that sleeps, wake on the fingerprint sensor if the hardware allows it.

### 3.3 Speakers and audio

[AOC-PLAN](../device/cheetah/AOC-PLAN.md) C9-C10, [AUDIO-PLAN](../device/cheetah/AUDIO-PLAN.md):

1. **C9g**: `omamobile-audio` 0.4.0's speaker filter, measured with the phone's own microphone and checked by ear. Lowest risk, fixes "thin" first.
2. **C9d-7/C9d-8**: the V/I feedback stream stock runs and the firmware's own impedance reading, for the runaway at analog gain 17; then stock's gains as the default (C9e, C9f).
3. **Waves on the AoC** ([AOC-TUNING-RESEARCH](../device/cheetah/AOC-TUNING-RESEARCH.md)): T3b (one exchange during a tone), then T4-T6.
4. **Bluetooth HFP**: route the BCM4389's SCO over HCI (AUDIO-PLAN A1).
5. **Earpiece and call audio**: designed in AOC-PLAN; built with the modem's M5.

### 3.4 Cameras

[CAMERA-PLAN](../device/cheetah/CAMERA-PLAN.md): all four cameras stream through libcamera's simple pipeline and software ISP (ultrawide CAM5, front F.5-F.7, main and telephoto through the line-throughput limit). The main camera focuses through its AK7375 actuator, the main and telephoto run at 30 and 60 fps (CAM5.5), and omacam ([CAMERA-APP-PLAN](CAMERA-APP-PLAN.md)) is the default camera app, with zoom, lens switching and video; GNOME Snapshot stays optional. Next: more image tuning in `packages/libcamera`, the telephoto's SEM1215 lens (it holds its I2C bus when driven, so the telephoto is fixed-focus), and QR scanning.

### 3.5 Shell and UX

The phone's own software, all offline-heavy and parallel to the hardware tracks. Omarchy changes go upstream first ([`patches/omarchy/`](../patches/omarchy)); the running list is "Phone UX to-dos" in [NOTES.md](../device/cheetah/NOTES.md).

1. **Home screen** (`omamobile-shell` 0.1.42): swipeable pages of apps and widgets (clock, weather, battery, media, calendar, note, toggles, command) with an edit mode. Next: user-built widgets made with Omarchy's default agent, folders, and touch testing.
2. **Quick settings** (`omamobile-shell` 0.1.42): a collapsed and an expanded sheet, 19 tiles, an editor to add, remove and reorder them; long-press opens the full setting.
3. **Notifications**: phone-shaped banners and shade with actions and inline reply, grouping per app, lock-screen privacy, do-not-disturb with exceptions; the incoming-call screen (full screen over the lock) for 3.1.
4. **Settings for a phone**: display (scale, font size, refresh rate), sound (volume steps per stream, ringtone), battery, mobile network and SIM, about phone; mostly front ends to what Omarchy already has.
5. **Accessibility**: scaling and font size first, then Orca with touch exploration, high contrast, and a pass over our plugins' touch targets and labels.
6. **System dialogs, screensaver, first run**: keyring, polkit and portal dialogs sized and styled for the phone; a portrait screensaver; Omarchy's whole user install at first boot, with phone-specific first-run steps (Wi-Fi, PIN, fingerprint).

### 3.6 Android apps (Waydroid)

[WAYDROID-PLAN](../device/cheetah/WAYDROID-PLAN.md): LineageOS (Android 13) in Waydroid's LXC container, each Android app in its own Hyprland window from our launcher, GLES on the Mali-G710, sound through PipeWire, networking behind ufw.

- **Kernel (W1):** binder, binderfs, PSI, memfd, cgroups and the container network were already on; Android's netd needs legacy iptables and ip6tables with its xt matches and targets, and policy routing (`IP_MULTIPLE_TABLES`, `IPV6_MULTIPLE_TABLES`, `INET_DIAG_DESTROY`). The block is in `kernel/configs/omamobile.config`, verified against `omamobile-int`'s configuration. No new driver code.
- **GPU:** the image's Mesa has no G710 row; `omamobile-waydroid` patches a copy into Waydroid's vendor overlay until the row is upstream.
- **Safety:** Waydroid's container is privileged and binds debugfs and the camera nodes; the package removes those binds and denies every block device, so Android can never reach the UFS or undo the storage guard.
- **Next:** W0 (read-only check on the current kernel), then W1-W5 on the phone; W6-W8 make Android apps behave like phone apps (back gesture, keyboard, notifications, power).

### 3.7 Distribution: updates, app store, installer, upstream

- **OTA: host the `[omamobile]` repository** publicly, so `omarchy update` updates the phone on Wi-Fi (signing and the keyring package already exist; `pkgs.omamobile.org` is set up with development and stable channels, nothing published yet). Then an update notice in the shell, and the kernel and its modules as a package with a safe slot-B install path, so `bin/omamobile push` becomes a developer tool.
- **App store**: a touch front end for installing and updating apps (pacman packages, Flathub, web apps), probably GNOME Software with a phone-shaped layout or a small plugin of ours; updates and the OTA notice in one place.
- **An installer** that sets up slot B and `userdata` with the safety model built in ([CONTRIBUTING](../CONTRIBUTING.md) §3): `tools/install-phone`, in testing (§1); downloadable images are 3.8's step 7.
- **Publish the kernel and go upstream**: `omamobile` is published and fast-forwards with each curation pass ([KERNEL-PUBLISH](../device/cheetah/KERNEL-PUBLISH.md)). The first patch (max17042 status) is on linux-pm with a Reviewed-by; next, send ready series the same way, with the Mesa G710 row and the Omarchy patches.

The kernel package, the update path for slot B and the installer are designed together in 3.8.

### 3.8 Multi-device builds and releases

[RELEASES.md](RELEASES.md): one kernel `Image` and module set for every Pixel with each board's DTB beside it, a descriptor per device (`device/<codename>/device.conf`), the kernel as a package, slot B written by a pacman hook instead of `bin/omamobile push`, and per-device bundles with a one-command installer that only touches slot B and `userdata`. Google's firmware stays extracted on the user's side. In order:

1. **Device descriptor and `DEVICE=`** (done 2026-10-13): `device/cheetah/device.conf`; `bin/omamobile` reads the DTB, `soc_id`s, dtbo, boot image values and storage-guard allowlist from it, and checks the allowlist against the initramfs. Cheetah's images came out byte-identical.
2. **Shared initramfs**: one `init` with the per-device quirks (the guard list, cheetah's display trigger write, the USB name) generated from the descriptor, release builds without developer keys or bring-up probes, packed reproducibly; `bin/omamobile overlay` replaces the hand-written `ov` helper. **Mostly done 2026-10-19:** one shared `initramfs/init` for cheetah, felix and oriole, with the display trigger, the guard's allowlist and the USB name packed from the descriptor (test boot on cheetah passed). Left: the main LUN, release builds without developer keys, and `bin/omamobile overlay`.
3. **Kernel package**: `linux-omamobile` (`Image`, modules, every DTB) from a tagged `omamobile-int` snapshot, release `LOCALVERSION`, in `[omamobile]`; `omamobile-device` as the virtual package the device packages provide.
4. **Device package hook**: `omamobile-boot-update` in `omamobile-device-cheetah` builds the images on the phone and writes slot B through the same guarded, verified path as `push`, keeps the previous set for rollback, never reboots, and is opt-in so development phones keep `bin/omamobile push`. Firmware maps move from the extraction scripts into per-device files.
5. **Release bundles and the installer**: per-device slot-B images, a shared Arch root image, signed checksums, and an `install` script that checks the phone and the factory image, adds the user's own firmware and SSH key to a local copy of the root image, and flashes only `<image>_b` and `userdata`. Replaces the "Installer: not started" row in §1.
6. **CI**: lint and package tests on every push; kernel, DTB validation and twice-built images per device on kernel tags; unsigned bundles on release. Pinned container and toolchain, so the maintainer can rebuild and compare before signing.
7. **Downloadable images**: build the per-device bundles and the shared root image in CI from a release tag, sign them, and host them (GitHub Releases or our own server) with the `install` script, so people flash a release without building anything. No Google file is ever in a download: the installer still extracts each user's firmware from their own factory image.
8. **Builds local by default**: every package (Mesa and Hyprland included) and every image builds on the builder's own machine from the repos alone (`tools/build-packages` in the arm64 container, ccache, native arm64 CI runners for speed). Building on a connected phone (`tools/repo-build`) stays an opt-in shortcut, never a requirement.
9. **Second device bring-up as the proof**: a second Pixel (a gs201 sibling first, or a gs101 phone to test the smaller boot image set) built, packaged and installed by the same tools with nothing but its descriptor, DTS, firmware map and device package added. Under way, all community work: the Pixel Fold (felix) boots to its cover screen with its keys and GPU, the Pixel 6 Pro (raven) runs Omarchy on our kernel (its package in review), the Pixel 8 Pro (husky, zuma) boots with USB and SSH and its UFS plan in review, the Pixel 9a (tegu, zumapro) reached first light, the Pixel 7a (lynx) boots to its initramfs, the Pixel 6 (oriole) has its descriptor from a retail phone, and the Pixel 4 (flame, Snapdragon) boots from RAM; board packages now come from each descriptor's `ROOTFS_PACKAGES`, so a non-cheetah image no longer pulls cheetah's.

Alongside every release, **keep linux-omarchy-mobile's branches honest**: publish `omamobile-int` as a tagged snapshot for builders, and run a curation pass that moves what has passed on the phone into the upstream-ready `omamobile` branch (the `omamobile-next` process) and publishes it, so the gap between the two shrinks release by release.

## 4. How to help

- **Start with [CONTRIBUTING.md](../CONTRIBUTING.md).** It has the safety model, the build and flash loop and how to submit changes. AI coding agents also read [AGENTS.md](../AGENTS.md).
- **Pick a plan.** Each subsystem's plan in [`device/cheetah/`](../device/cheetah) has a status line, the evidence, and a gated runbook with the next step. Offline work (drivers, reviews, checkpatch and `dt-validate` runs, packaging, shell UX, accessibility) needs no phone.
- **Bring up another device.** [DEVICES.md](DEVICES.md) lists the devices we'd like and their closest starting point; CONTRIBUTING §5 is the bring-up guide. Most gs201 phones need mainly a board DTS.
- **Upstream review.** Kernel series from `omamobile-next` and the Mesa and Omarchy patches benefit from review by people who know those subsystems.
