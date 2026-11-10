<!-- SPDX-License-Identifier: MIT -->
# Bluejay persistent desktop integration

Status (2026-11-08): verified persistent Arch Linux ARM on userdata. Normal
reboots automatically start USB SSH, polling ALIX touch, retained display
refresh, NetworkManager station Wi-Fi and Panfrost-backed Hyprland/Quickshell.
The owner confirmed unlock, app launch and scrolling. See [UPSTREAM.md](UPSTREAM.md)
for the tested source and the remaining release-packaging work.

## Root handover

The init checks the ext4 label `omamobile-root` before repair or a writable
mount. Only e2fsck results 0 and 1 continue. The explicit
`persistent-development` selector skips early filesystem growth, writes a
root-pending marker before handing over to systemd, and holds in the RAM rescue
environment after an incomplete boot. The installed USB SSH-ready service clears
that marker. The actual root was expanded online after persistent boot passed.

A development selector with an unknown value stays in RAM. The earlier RAM-only
qualification harness and its private control protocol are not installed by
this integration. The host's private qualification artifacts remain retained.

## Guarded startup

The package keeps drivers blacklisted and starts them through bounded services
after SSH is available. Each subsystem has a durable pending marker and a
volatile ready marker. A failed attempt remains held after reset; hardware
startup never loops through unload/rebind retries. Systemd owns watchdog0 at
20 seconds. Touch/display startup has a 25-second deadline, Wi-Fi 45 seconds
and GPU 30 seconds, with five-second stop deadlines.

SDDM waits for the hardware and GPU units. GPU initialization requires an
explicit `/etc/omamobile/bluejay-gpu-enable`. A held GPU leaves its ready marker
absent, and the session environment falls back to llvmpipe/software rendering.
The GPU's ACPM clock provider is registered only after holding the unrelated
`cpufreq-dt` consumer; CPU DVFS has not been qualified.

The package ships no automatic boot-success writer and sets `AUTO_WRITE=no`.
The installer must retain the descriptor's `BOOT_UPDATE_AUTO_WRITE=no` policy.
The existing project helper marked B successful once after the installed
system passed its original fresh-boot test. The boot-control write changed devinfo; its eight-byte before/after table
and the limits of the saved tool provenance are recorded in [NOTES](NOTES.md).
Further gs101 marking is on hold; no automatic marking service is shipped.

## Reproduction and recovery gates

1. Build the exact kernel source, module closure, device package and root in an
   isolated output directory. Inspect the actual packed images, both DT variants,
   module release/provenance, blacklists and automatic-write policy. Stop on an
   unexpected difference. This is offline and changes no phone.
2. Retain a host-held RAM rescue image set. The persistent selector automatically
   enters the installed root, so it is not a RAM rescue image. Use only the
   project's serial-pinned B-image helper and `tools/install-phone` for userdata.
   These steps replace the OS and require the owner's authorization.
3. Install after the actual installer dry run, with account secrets entered
   locally. Expect USB SSH, Arch PID 1, the 49-partition storage guard and the
   subsystem ready markers. Stop if transport or the guard fails. Never restore
   NV/calibration as a recovery shortcut.
4. Test one normal reboot and actual unlock/app use. Confirm matching kernel and
   modules, Panfrost rendering, Wi-Fi-bound TLS traffic, no new hardware faults
   and no pending markers. Buttons/Fastboot plus the retained RAM images are the
   recovery path if the device does not return.

The development handset's owner accepted loss of Android/userdata and retained
existing backups. That acceptance is specific to this test phone. Other owners
must use the project's own installation and recovery policy.

Native panel modesetting, full GPU/CPU DVFS, Power-key release, audio, modem,
Bluetooth, battery/charging, sensors, cameras and suspend remain unfinished.

## Review split, 2026-11-09

The tested implementation above is historical development evidence, not an
installed-package claim. Its code remains inspectable at the immutable #543
source linked in [UPSTREAM.md](UPSTREAM.md). The separate initramfs, installer
and bring-up changes are under review as #562, #563 and #565; passive-package
coordination with #346 remains pending. The neutral
initramfs proposal uses descriptor settings and `root-boot-pending`; the tested
Bluejay helper used `bluejay-root-pending`. Those paths must not be mixed.
No revised source has been booted. The shared no-USB crash is disabled only
by an explicit descriptor choice: a development phone may boot without a
host, and RAM rescue must stay reachable without consuming boot retries.
