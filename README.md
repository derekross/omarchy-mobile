# Omarchy Mobile

Native Omarchy on Google Pixel phones: Arch Linux ARM, Hyprland and Omarchy's own packages running directly on the phone with a mainline kernel, with Android apps in Waydroid as a later goal. First device: Pixel 7 Pro (cheetah, gs201).

**Status (2026-10-19):** a pocket computer, not yet a phone. Each item's detail and the notes behind it: [docs/DEVICES.md](docs/DEVICES.md); what's missing and the plan to get there: [docs/ROADMAP.md](docs/ROADMAP.md).

- **Works:** display at 120 Hz, GPU, touch, buttons, USB networking, Wi-Fi, Bluetooth audio, battery, charging (on at boot under a battery temperature guard), haptics, torch, sensors with auto-rotate, GNSS (Location tile, GeoClue), NFC (reading and writing tags, opening a tag's link) and fingerprint unlock alongside the PIN pad or password, which keeps working across sleep (opt-in, because its first run writes Trusty's secure storage).
- **Partial:** the speakers and microphones work but sound quiet and thin, with occasional static; a new speaker filter is built and not yet tuned on the phone. All four cameras work in omacam ("Camera", [our own camera app](https://github.com/derekross/omacam), the default since omamobile-apps 0.2.0: one zoom control from the ultrawide to the telephoto, full-resolution photos, tap to focus) through libcamera (basic quality): main, ultrawide, front and telephoto, at full size by default (`cam` with no options); the telephoto can't focus yet (its lens holds its I2C bus when driven).
- **In progress:** the modem boots Google's firmware and answers our IPC (SIM and radio state), but registration, SMS, data and calls need a SIM test that hasn't happened yet. Sleep on screen-off: s2idle passes repeated sleep and wake cycles with Wi-Fi staying connected (31 of 31 on 2026-10-19); the AoC and sensors across sleep, battery numbers and the screen-off policy come before it is on by default.
- **New this week (2026-10-19):** the Pixel Fold boots to its cover screen and the Pixel 6 builds, both community ports ([docs/DEVICES.md](docs/DEVICES.md)), and the Pixel 4 runs a read-only first-light probe; the Tensor phones share one initramfs, with each phone's quirks packed from its descriptor; our first kernel patch went upstream (the battery's charging status) and was reviewed; first login invites you to pick an AI agent, with none preinstalled.
- **New on 2026-10-13:** home screens with 47 built-in widgets (Simon Schubert's MIT-licensed omarchy-widgets, his OWL originals run by our own OWL runtime since 2026-10-14, plus an OWL widget Store tab with an approval sheet for what each widget may run) and your own widgets made with "Create with AI" through Omarchy's default agent, behind a crash guard; 19 quick-settings tiles with an editor; one app per screen, with a "Show with…" action; the phone's screen and input on a computer over USB (`omamobile-mirror`, `tools/phone-mirror`); a device descriptor (`device.conf`) for more than one phone; and a first installer (below), which passed its first clean reinstall.

## Quick start

**POCO F3 (`alioth`), experimental:** use the dedicated
[build, backup and flashing guide](device/alioth/FLASH-RUNBOOK.md) and read
its [hardware limits](device/alioth/BRINGUP-M1.md). Its Android-v0 boot layout
uses a separate guarded installer; the Pixel commands below do not apply.

The installer is new: expect rough edges. You need a Pixel 7 Pro with an unlocked bootloader, an Omarchy (Arch) laptop with Docker, `android-tools` and `e2fsprogs`, and Google's factory image for the phone. Stock Android stays on slot A as the way back; installing erases `userdata`.

```sh
tools/build-packages                 # Omarchy Mobile's packages for aarch64 (out/repo)
tools/build-rootfs                   # the root image: Arch Linux ARM, Omarchy, our packages
tools/install-phone --dry-run        # phone in fastboot: checks it, asks for your user, shows every command
tools/install-phone                  # writes only slot B's boot images and userdata
tools/phone-provision FACTORY.zip    # after the first boot: firmware from your own factory image
```

The kernel and boot images come from `bin/omamobile kernel`, `modules`, `initramfs` and `images` (CONTRIBUTING.md §4). Step by step, with what to expect at each point: [device/cheetah/REINSTALL-RUNBOOK.md](device/cheetah/REINSTALL-RUNBOOK.md).

## Layout

| Path | What it is |
| --- | --- |
| `bin/omamobile` | Build and flash tooling: `capture`, `kernel`, `modules`, `initramfs`, `images`, `flash`, `push`, `kexec`, `fastboot` |
| `tools/build-packages`, `tools/build-rootfs`, `tools/install-phone`, `tools/phone-provision`, `tools/make-bundle` | The installer: aarch64 packages and the root image built on the laptop, the narrow fastboot installer, per-phone provisioning, release bundles (`rootfs/` holds the image's package lists; `tests/` their tests) |
| `tools/` | Staged bring-up and capture tools, on-phone probes, firmware extraction from the user's factory image, package and repository helpers |
| `packages/` | pacman packages: `omamobile-shell` (the phone profile for Omarchy's shell), `omamobile-apps` (the mobile apps desktop Omarchy lacks: Camera, Maps, NFC), `omacam` (the camera app, built from its own repository), `omamobile-device-cheetah` (Pixel 7 Pro support), `omamobile-sensors` (sensors and auto-rotate through the AoC), `omamobile-gnss` (location on demand), `omamobile-mirror` (the phone's screen and input on a computer over USB, VNC), `omamobile-audio` (PipeWire and speaker protection), `omamobile-speaker-tuning` (stock's speaker tuning, off by default), `omamobile-fingerprint` with a patched `libfprint`, `omamobile-modem` (the modem's vendor chroot profile), `omamobile-modem-sit` (the SIT client daemon; talks to the modem, registration untested), `omamobile-mmd` (ModemManager's D-Bus API in front of it, for GNOME Calls, Chatty and NetworkManager), `neard`, `omamobile-keyring` (the `[omamobile]` repository's signing key), patched `mesa` and `hyprland`. `tools/phone-install-package` builds one on the phone and installs it |
| `patches/omarchy/` | Changes to Omarchy for touch devices, to send upstream (`bridge-*` ones are stopgaps for the phone's older Omarchy); a link to `packages/omamobile-omarchy/patches`, whose pacman hook re-applies them after every Omarchy upgrade |
| `bin/lineage-ref` | Builds LineageOS for the phone. Used as a rooted reference Android (M0) and, later, for Waydroid images |
| `kernel/configs/` | Our kernel config fragment, merged on top of arm64 `defconfig` |
| `device/cheetah/` | Pixel 7 Pro bring-up notes, one plan per subsystem, overlays, the initramfs and the device descriptor (`device.conf`) |
| `omamobile.conf` | Shared settings (source dir, jobs, container image). Override in `omamobile.local.conf` |
| `docker/` | Ubuntu 24.04 build environment |
| `docs/DEVICES.md` | Supported-devices matrix |
| `docs/ROADMAP.md` | Where things stand and the plan to a working phone |
| `docs/RELEASES.md` | How builds and releases work for several devices: device descriptors, the kernel package, release bundles |

Large trees live outside the repo, under `~/android/`:

| Path | Contents |
| --- | --- |
| `~/android/omamobile` | LineageOS 24.0 source. Includes Google's GPL Pixel 7 kernel at `out-kernel/google/gs-6.1` |
| `~/android/mainline/linux` | Our kernel repo: branch `omamobile` on mainline v7.3-rc6 (remote `upstream` is Linus's tree), one commit per subsystem so patches can go upstream. Published to [derekross/linux-omarchy-mobile](https://github.com/derekross/linux-omarchy-mobile) by `tools/publish-kernel` (a squashed upstream base, our commits unchanged on top) |
| `~/android/mainline/pmos-tensor` | postmarketOS Tensor kernel, for reference |
| `~/android/reference` | Captures from the phone. Contains serial numbers and partition backups: never commit |
| `~/android/factory` | Verified stock factory images, used to restore the phone |

## Ground rules

- We only ever flash the boot images and userdata. Never `bootloader`, `radio`, `devinfo`, `persist` or calibration partitions.
- **Licensing:** this repository is MIT ([LICENSE](LICENSE)) except where a file's SPDX header says otherwise. Kernel patches (and the board dtbo source) are GPL-2.0. The port of Google's Apache-2.0 boot-control code keeps that licence and Google's notice (`packages/omamobile-device-cheetah/src/omamobile-bootctl.c`). Every file we write carries an SPDX header.
- Google's proprietary firmware and binaries are never committed: our scripts extract them from the user's own factory image.
- No code from unlicensed sources. Google's GPL kernel, upstream Linux, postmarketOS and Mesa are fine.

## Contributing

Bringing up another Pixel, fixing a driver or improving the phone shell: start with [CONTRIBUTING.md](CONTRIBUTING.md). It covers the safety model (stock Android stays on slot A, the read-only storage guard, backups, dead-man switches), the build and flash loop, a step-by-step guide to bringing up a new device, and how to submit kernel and package changes. AI coding agents should also read [AGENTS.md](AGENTS.md). The status of each device is in [docs/DEVICES.md](docs/DEVICES.md), and what's next in [docs/ROADMAP.md](docs/ROADMAP.md).
