<!-- SPDX-License-Identifier: MIT -->
# POCO F3 initial native port

Status (2026-10-21): experimental installed native desktop verified on one
POCO F3. The public source workflow has built and passed offline validation
in an independent checkout; it has not had a clean physical reflash. Use the
[installation runbook](FLASH-RUNBOOK.md), including its backup and rescue
gates. This is a source-build port, not a ready-to-download public image.

## Sources and layout

[V] Board: `alioth`, Qualcomm SM8250 family / Snapdragon 870, Adreno 650,
1080x2400 display. It uses an Android v0 boot image with an appended DTB.
The Pixel Android-v4 image/push helpers are unsuitable and remain blocked.
Only `DEVICE=alioth bin/omamobile flash` dispatches to the dedicated guarded
initial installer. No kernel driver or DTS patch is included here.

[V] The kernel, DTB, matching modules and runtime are extracted locally from
the checksum-pinned [2026-09-28 reference release](https://github.com/Sucharek233/pmos-alioth-builds/releases/tag/2026-09-28_935d1cb):
SHA-256 `17901fd0f9a96284c42b93ad1c9093aaf9bf79db62d084d80ee72afb4b29bb84`,
Linux `6.15.1-sm8250`. The source workflow is
[Sucharek233/alioth-nightly-builds](https://github.com/Sucharek233/alioth-nightly-builds/tree/935d1cb409341c17a40663167edd5c3c50c2e986).
Kernel source is [mainlining/linux, nikroks/alioth](https://github.com/mainlining/linux/tree/022f7f866a9377c34301e60ba131121c624d2e56).
Source provenance does not imply a bit-identical source rebuild. Credit to
the reference maintainers, postmarketOS/Nura, mainlining and upstream Linux.
This PR ships none of their binary images or runtime firmware.

[V] The shared initramfs is retained, with board-checked settings and the
Qualcomm panel/watchdog modules. Its in-kernel storage read-only flags
survive switch_root; the device package keeps the whole-disk node absent
and hides Android partitions from desktop tools. The root label must match
before fsck, resizing or mounting can run. Rescue explicitly skips all three.
No Pixel register probes or boot-success metadata writers are installed.

[V] `boot_b` is the only persistently flashed boot image. `dtbo_b` is erased
to avoid applying the original Android overlay to the appended mainline
DTB. The reference module archive is included in both the boot/root paths;
every embedded module must match the release before a build is accepted.

## Hardware evidence and limits

The observations below are from the installed test phone on reference
6.15.1-sm8250, including live firstboot fixes. They are not a claim that every
newly rebuilt byte or every F3 regional variant has been flashed.

| Feature | Evidence/status |
| --- | --- |
| Boot and root | Native Arch/Omarchy booted from userdata; PIN unlock and normal reboot verified |
| Storage | Whole main-disk node absent; 11 discovered NV/calibration partitions read-only and original backups unchanged |
| Display/GPU/touch | Hardware-rendered Omarchy, direct touch and remote keyboard input verified |
| USB | Rescue and installed-root SSH; separate host identities; reconnected after reboot |
| Wi-Fi | Connection and HTTPS verified; native nftables firewall preserves USB control access |
| Battery/charging | Battery readout and charging indication observed; no independent charging-safety/power characterization |
| Buttons | Kernel exposes keys; full mapping/long-press behavior remains to be evaluated |
| Torch | Standard LED worked manually; initial shell still needs its board-specific selector |
| Bluetooth/NFC | Later manual bring-up on the test phone is outside this initial package; not claimed ready here |
| Cameras/audio | Drivers/devices partly enumerate; no usable camera pipeline or verified playback/capture |
| Sensors | Measurements obtained manually, but cold-start registry discovery stalls; proxy masked |
| Calls/SMS/MMS/data/GPS | Unsupported |
| Haptics/fingerprint | Unsupported |
| Suspend | Disabled until tested; screen blanking is separate from system suspend |
| A/B success marking | Not implemented for Xiaomi; physical FASTBOOT remains the recovery path |

The stock build tested was global MIUI V14.0.8.0.TKHMIXM. Other bootloader/
firmware/regional combinations are untested. Original boot/dtbo/vendor_boot
and NV backups must belong to the phone being installed, regardless of build.

## Firstboot and kernel compatibility

[V] Interactive systemd-firstboot must be masked: otherwise the timezone
prompt blocks the noninteractive provisioning/access path. Seed a build-time
clock lower bound before package key initialization; do not write the RTC.
The device package supplies a native nftables firewall because the reference
kernel lacks expressions used by UFW. The generic firstboot hook uses the
device firewall when present and keeps the Pixel behavior otherwise.

[V] The reference kernel lacks Landlock. Pacman 7.1's filesystem sandbox
therefore needs `DisableSandboxFilesystem`; its download user and syscall
filtering remain enabled. The limited workaround passed a signed package
download on the phone. The package helper checks the ARM64 Landlock ABI and
removes only its own setting when a future supported kernel is used and the
helper is rerun. It never sets the broader `DisableSandbox` option.

Systemd 262's newer socket coredump collector requires Linux >=6.19;
the root builder gates those units while retaining the legacy collector.

The later Landlock/Waydroid kernel and Unexpected-style keyboard trials are
deliberately outside this first installation PR. Their success on one test
phone does not establish a public initial-install/release workflow.

## Offline checks and next hardware gate

Run `tests/all` for existing-device regressions and `tests/alioth` for the
F3's fixed targets, explicit wipe confirmation, backup/readback binding,
dry-run isolation, root-label guard, mirror timeout, device package and
overlay containment. `tools/alioth/build.py` additionally checks real ARM
payloads, module vermagic, the root filesystem, sparse round-trip and an
authenticated login to the packed ARM Dropbear in an isolated container.
It also mounts the personalized root read-only, parses firstboot settings,
runs ARM systemd/Hyprland/Quickshell version checks, resolves the desktop
and mobile-app shared libraries, and validates OpenSSH configuration.
QEMU user emulation cannot test OpenSSH's seccomp sandbox; verifying a login
to this new root still requires a real ARM kernel. These offline checks
never query a phone.

Local validation (2026-10-22 UTC, code commit `29ec52a52873`):

- [V] The documented build entrypoint completed on Linux/x86_64 with ARM
  emulation, dedicated local keys and all ten locally signed packages.
  The root contains stable Omarchy `4.0.6-1`, Hyprland `0.56.2-7`, the F3
  package `0.1.0-1` and matching `6.15.1-sm8250` modules. All 12 mobile
  Omarchy patches applied.
- [V] Generic root-image smoke, personalized ext4 consistency, byte-identical
  sparse round-trip, boot/rescue payload checks, ARM userspace/library
  checks, OpenSSH configuration and packed Dropbear authentication passed.
- [V] `tests/all` passed, including the 17 installer gates, provisioning
  fixture, storage guard, client/mirroring checks and overlay containment.
  The actual built-image installer dry run passed with a fastboot trap;
  no fastboot process was executed.
- [V] The pinned official TWRP image reduced to 96 MiB with identical boot
  payload, AVB metadata and footer; its embedded hash verification passed.
  No keys, images, firmware, backups or raw logs are included in the PR.

Next high-risk hardware gate: a clean install from this branch on an
unlocked alioth with verified original backups. Pass: fresh rescue SSH and
guards before the wipe, then a complete native firstboot, display/touch,
Wi-Fi and USB after a reboot. Stop: any identity/hash/guard failure, missing
USB, heat, repeated reset or failed flash. Rollback: preserved slot A and
the phone's own original images; Android recovery must reset replaced
userdata. Never restore NV or relock as part of routine rollback.
