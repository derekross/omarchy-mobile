<!-- SPDX-License-Identifier: MIT -->
# Xiaomi Mi 8 (`dipper`) single-slot install plan

Status (2026-11-21): **design only; no persistent installer or updater is
approved.** The device descriptor remains `BOOT_METHOD=ram-only`. The
maintainer asked that no further writes be made to the handset while the
existing boot-partition questions are open. This plan does not authorize a
phone operation.

## 1. Goal and constraints

Install Omarchy Mobile on `userdata` and boot it from the phone's single
`boot` partition. Keep a guarded rescue image on the laptop as the first
return path.
The install must never write `dtbo`, bootloader, `vbmeta`, radio/modem,
`persist`, `modemst*`, or any other calibration or identity partition.

Unlike the A/B phones, Dipper has no alternate slot. A torn or bad `boot`
write cannot fall back to another OS image. The installer must therefore
require the §3.1 backup, use an explicitly serial-pinned fastboot session,
check the product and unlocked state, display a dry run, and require the
operator to type `dipper` before writing. A recovery from a failed boot uses
Volume Down + Power to reach fastboot, then `fastboot boot` of the verified
guarded rescue image without another partition write. A working installed
system needs a verified install image or a separately reviewed restore of
`userdata` and `boot`; the 11-09 `boot` image alone cannot supply one after
`userdata` is replaced. There is no automatic reboot into stock and no
unsuffixed write through a generic command-line partition argument.

## 2. Facts and evidence

- `CONTRIBUTING.md` §3.1 names `boot` as the only boot partition a Dipper
  install may write. The stock `dtbo` stays untouched. Volume Down + Power
  enters fastboot; holding Power alone for 10 seconds restarted the phone
  under the Omarchy Mobile kernel.
- The bootloader reports product `dipper`, unlocked, a 64 MiB `boot`, and no
  `has-slot:boot` or `current-slot` variable. The current device descriptor is
  RAM-only and has an empty UFS writable allowlist.
- The 2026-11-09 backup contains all 84 GPT partitions except `userdata`
  (there is no `super`). A guarded read-only comparison on 2026-11-19 matched
  83 of 84; only `logfs` differed. The mismatch's cause is unknown, so that
  set alone is not the required pre-install backup. Capture and verify a new
  full set before any first install. Keep hashes and images off-repository.
- The 11-09 `boot` backup came from the phone's pre-existing installation,
  which fell back to an older writable ext4 `userdata` system. Its kernel
  string is unknown. Once `userdata` is replaced, restoring only that image
  is not expected to start a usable system.
- A guarded rescue is currently in `boot`. The original manual flash command
  and serial pinning were not retained. Its current whole-partition hash and
  the limits of that evidence are recorded in the [Dipper device PR](https://github.com/derekross/omarchy-mobile/pull/714),
  but the hash was not measured immediately after the write. The maintainer has
  not approved restoring or replacing it.
- The latest current-main smoke used an already-running NFS/overlay root. It
  reached Hyprland with touch and an MSM render node, but `/` was not
  `userdata`, and the physical panel was not observed. The first smoke report
  had six kernel error lines; the second had none, without retained boot IDs
  or uptimes to explain the difference. Neither is a clean installed-system boot.

## 3. Proposed implementation

### 3.1 Separate image format from install target

The existing `BOOT_METHOD` describes how a boot image is built. Dipper's
builder emits Android boot header v1 with its DTB appended to the kernel;
`android-v0` and `qcom-abl` describe different layouts. Add an `android-v1`
image method for that format and an independent `INSTALL_SLOT=single` target
for installation. Neither value exists in the descriptor yet. `INSTALL_SLOT`
already has `active` for manifest format 2; do not overload that contract for
Dipper. If the maintainer chooses a new release format, the proposed
single-target bundle is format 3, with `install.slot` set
to `single`, direct install writes for `boot` and `userdata`, no
accepted/current-slot list, no `set-active`, and a runtime storage-guard
allowlist containing only `userdata`. The external `omamobile-installer`
consumer must implement this format before any format-3 bundle is published,
and must refuse it until then. The maintainer will decide whether that format
is needed now or a development install through `bin/omamobile` and
`tools/install-phone` comes first. Do not publish a format-3 bundle before
that decision and its consumer are complete.
Keep the published Dipper descriptor `BOOT_METHOD=ram-only` until the shared
path is implemented and reviewed.
Two policy prerequisites are the maintainer's wording changes to `AGENTS.md`
and `CONTRIBUTING.md`: a device-scoped exception for an unsuffixed `boot`
flash and the single-slot rule that replaces `push`. The maintainer also has
to decide whether laptop-only kernel writes apply to other single-slot phones.

For a persistent Dipper descriptor, allow exactly `BOOT_IMAGES="boot"` and
`UFS_RW="userdata"`; reject every other unsuffixed partition. The installed
initramfs must leave `boot` read-only: only the host-side fastboot installer
and manual updater write it. `boot` is an explicit, device-scoped install
target, never a partition name accepted from a command line. Shared
descriptor readers must permit this boot image outside the runtime guard only
for `BOOT_METHOD=android-v1` with `INSTALL_SLOT=single`; the on-device
`omamobile-boot-update` hook must refuse it. A manifest must identify the
device, `INSTALL_SLOT=single`, the exact `boot` image and the `userdata` root
image. Its install write set is `boot` plus `userdata`, while its runtime
storage-guard allowlist is only `userdata`. There is no slot query, slot
switch, or `set-active` operation.

The change has to reach every reader and writer of the descriptor: `bin/omamobile`
and its image/fastboot/flash/push paths; `tools/install-phone`,
`tools/install-guided`, `tools/bundle-manifest` and `tools/make-bundle`;
`packages/omamobile-boot-update` and the initramfs storage/root selection;
release documentation and the external `omamobile-installer` bundle consumer.
Their descriptor parsers, generated manifests and dry-run output must agree
on the install write set and the separate runtime allowlist. Add fixtures for
every changed reader; do not add Dipper to only one parser and call the device
installable.

The initramfs allowlist for an installed system may open only `userdata`.
`boot`, every other UFS partition and all whole disks remain read-only;
`persist`, modem and calibration partitions are never mounted. RAM rescue
images continue to use an empty allowlist. NFS-root remains a bring-up tool,
not the persistent install path. Tests must prove the Dipper runtime
allowlist, the host-side `boot`/`userdata` write set and that existing A/B
descriptor decisions and fixtures do not change.

### 3.2 Install and update writers

Use `tools/install-phone` with a Dipper-only, serial-pinned fastboot
writer for first install. It must check exactly one attached serial,
`getvar product=dipper`, `unlocked=yes`, the `boot` partition's actual size,
and every image checksum before its dry run. It must then show the exact
`boot` and `userdata` writes, the userdata erase consequence, and the
guarded-rescue recovery command before requiring the typed codename. Write
`userdata` first, after verifying that the old ext4 root lacks the expected
new root label,
then write `boot`. The new initramfs must refuse the old label, so an
interruption after the first write cannot start the old root with the new
kernel. An interruption during either write leaves no assumed bootable
system; enter fastboot by buttons and RAM-boot the guarded rescue. Fastboot
on this bootloader cannot read `boot` back. After fastboot confirms the write,
RAM-boot the rescue, keep `boot` read-only there, hash the entire 64 MiB
partition over SSH, and compare it with the padded image. A failed RAM boot,
missing SSH, or hash mismatch stops before a normal reboot. No tool accepts a
partition name from the caller.

Do not add an automatic pacman hook that writes the single boot partition in
this implementation. No Dipper kernel package is selected by the current
RAM-only descriptor. Before installing `linux-omamobile` or another kernel
package for Dipper, define a package hold so `omarchy update` cannot replace
the running kernel's modules ahead of the host flash. A kernel update stages
the new image and modules on the laptop; it keeps the old modules installed
until the new `boot` image has been written, verified through rescue, and
started successfully. Only then may the old modules be removed. A reboot
alone does not install the new kernel. Preserve `userdata` on kernel updates;
only first install may replace it. Keep this manual update as a documented
limitation until its recovery policy and failure tests are reviewed.

### 3.3 First boot and loss of USB

Build a production initramfs that mounts the installed ext4 root from
`userdata`, verifies its expected label, and has the exact Dipper boot image's
modules. The no-USB-host behavior must not reboot into the same unverified
single-slot image. On a missing USB host, failed root mount, or failed
firstboot, stay in the initramfs rescue state with the console and USB SSH
available where possible; do not fall through to an older root or request
NFS. Review the watchdog and timeout behavior against the phone's measured
`qcom_wdt` limit before the first persistent boot.

## 4. Gated runbook

No step below is approved to run on the phone yet. The maintainer's current
no-write request remains in force. Commands, images, serial and checksums
must be reviewed for the exact image before a future attended run.

### L1. Offline validation (no phone; risk none)

Build the exact kernel, initramfs, rootfs and `boot.img` from reviewed
commits. Check the Android v1 header, appended Dipper DTB, 64 MiB size limit,
module release, root label, descriptor parity and the storage allowlist.
Run descriptor-parity tests for `bin/omamobile`, boot-update and installer
readers; dry-run fixtures for missing, duplicate and wrong-device partitions,
and for a cut-off between the `userdata` and `boot` writes with the old root
label;
bundle manifest and release-bundle checks; storage-guard tests for Dipper and
existing A/B devices; and the full PR gate. Check the downstream desktop
installer against the new manifest before publishing a release. Stop on any
mismatch; no generated image or private key goes in Git.

### L2. Backup gate (future read-only device step; risk none)

From guarded RAM rescue, confirm all UFS disks and partitions report
read-only. Re-capture every non-`userdata`, non-`super` GPT partition and
compare each complete phone-side SHA-256 with the off-device copy. Include
the current guarded-rescue `boot` image and retain the older 11-09 image as
separate historical evidence. Stop on any mismatch, missing partition, size change,
or `ro=0`. Store the complete backup and checksum manifest off-repository.

### L3. Attended install (persistent write; high risk; maintainer approval
required)

Confirm the backup gate, one pinned fastboot serial, product, unlocked state,
and recovery-button procedure. Review the dry run and exact recovery command.
Only then may the approved installer write `userdata` followed by `boot`; no
other partition is in scope. RAM-boot the guarded rescue and hash the whole
read-only `boot` partition over SSH before a normal boot. If any step fails,
stop and use the buttons to reach fastboot, then RAM-boot rescue again. A
fastboot OKAY alone is not a readback check.

### L4. First persistent boot (high risk; separate approval required)

After the installer succeeds, boot once with the USB host attached and the
watchdog/log stream ready. Verify `/` is the expected `userdata` ext4 root,
all other UFS remains read-only, firstboot reaches the session, SSH stays up,
and the display, FD630 renderer, touch events and buttons work. Run the
sanitized `tools/phone-smoke` report and record `uname -r`, boot-image hash,
root source, panel/backlight behavior and kernel errors. Verify
`reboot-to bootloader` returns to fastboot. Stop on a watchdog reset, failed
USB link, black panel, unexpected writable partition, or any new kernel
error. With a dark screen and no SSH, hold Volume Down + Power to reach
fastboot and RAM-boot the verified rescue image. Do not call the device supported until this clean installed-system
run passes; a rescue/NFS overlay is not a substitute.

## 5. Risks and rollback

- `boot` is the only OS boot partition. An interrupted write may require the
  physical fastboot buttons and a laptop restore; there is no A/B fallback.
- Writing `userdata` replaces Android's data and the prior Linux root. The
  owner must decide what user data needs preserving before installation.
- The historical non-userdata backup has one unexplained mismatch and must
  not be treated as a verified restore set for a first install.
- The 11-09 `boot` image belongs to the old installation; restoring it alone
  after replacing `userdata` does not restore a working system.
- The boot update remains manual from fastboot until a safe single-slot
  updater has its own reviewed recovery protocol and failure tests.

The first recovery step is `fastboot boot` of the guarded rescue image, which
does not write a partition. Restoring a working system requires a separately
reviewed complete restore or a verified reinstall. Neither has run, and this
plan authorizes no phone operation.
