<!-- SPDX-License-Identifier: MIT -->
# Install experience plan: a one-step, guided install

Status (2026-11-02): **design only.** Nothing here has been built or run on
a phone. Today's install is the manual guide in [INSTALL.md](INSTALL.md):
about an hour of terminal commands, a factory image the user finds and
downloads by hand, a USB network connection set up by hand, a radio backup
and a provisioning run. This plan is how that becomes one guided install
that a person with no Linux or Android knowledge can finish, from a web
page or a desktop app, without fetching drivers, firmware or files from
anywhere else.

The safety model in [CONTRIBUTING.md](../CONTRIBUTING.md) §3 and
[AGENTS.md](../AGENTS.md) §1 doesn't change: only slot B and `userdata` are
written, stock Android stays on slot A, and Google's firmware is never
hosted by the project. Where this plan builds on a decision already taken,
it points to [RELEASES](RELEASES.md) §6 and §12 (bundles, `manifest.json`,
hosting, one core for the web flasher and the desktop installer) and
[SECURITY-PLAN](SECURITY-PLAN.md) (encryption, our own boot key, locking).

Facts are marked **[V]** (verified in this repository or on the phone),
**[D]** (stated in public documentation) or **[I]** (inferred, to be
checked).

## Contents

1. [The goal, from the user's side](#1-the-goal-from-the-users-side)
2. [What stays fixed](#2-what-stays-fixed)
3. [Today's install, step by step](#3-todays-install-step-by-step)
4. [What the installer automates](#4-what-the-installer-automates)
5. [Provisioning: on the computer or on the phone](#5-provisioning-on-the-computer-or-on-the-phone)
6. [Google's factory image](#6-googles-factory-image)
7. [Recovery and going back to stock](#7-recovery-and-going-back-to-stock)
8. [How it fits the security plan](#8-how-it-fits-the-security-plan)
9. [Firmware updates later](#9-firmware-updates-later)
10. [Gaps found in the 2026-11-02 test install](#10-gaps-found-in-the-2026-11-02-test-install)
11. [Milestones](#11-milestones)
12. [Decisions for the maintainer](#12-decisions-for-the-maintainer)

## 1. The goal, from the user's side

What the person does:

1. Opens the installer: a page on omamobile.org in a browser with WebUSB
   (Chromium-based browsers), or the Omarchy Mobile Installer app on an
   Omarchy computer. Both are the same installer with the same steps and the
   same checks (§11, M3).
2. Picks their phone from the list, or plugs it in and lets the installer
   recognise it.
3. Follows plain steps, each one screen with a picture: turn on Developer
   options and OEM unlocking, allow the computer, confirm the unlock on the
   phone with the volume keys. This is the only part done on the phone
   itself.
4. Reads what will happen (the phone is erased, Android stays on the phone
   as the way back, Google's terms for the firmware) and accepts.
5. Chooses a user name, a PIN or password, the phone's name, the time zone
   and optionally a Wi-Fi network, in the installer window.
6. Waits. The installer downloads the release and the phone's own firmware,
   checks everything, writes the phone, waits for its first start, backs up
   the radio partitions to the computer, puts the firmware on the phone and
   restarts it.
7. Sees one screen: "Your phone is ready", with a short list (display,
   touch, Wi-Fi, sound, cameras, sensors, battery) each ticked, and where
   the radio backup was saved.

On the first start that the person sees, Wi-Fi, Bluetooth, sound, haptics,
sensors and the cameras work, and the modem's per-phone data (board id, NV
checksums) is in place, so the modem can start without any further step.
After that the phone updates itself through the Updater (the update sheet
in the shell, `omamobile-update` underneath, RELEASES §5.4), including its
firmware (§9).

What the person never does: install `fastboot` or Android's tools, open a
terminal, find Google's factory image page, match a build number, set up a
USB network connection, run a backup or a provisioning tool by hand, or
download anything from a site other than omamobile.org and Google's own
servers (and the download from Google happens inside the installer).

## 2. What stays fixed

- **Google's firmware is never hosted by the project** (RELEASES §12.7). Not
  in a bundle, not in a package, not on `pkgs.omamobile.org`, not through a
  proxy or cache of ours. The installer fetches the user's own phone's
  factory image straight from Google's servers to the user's machine (or the
  phone fetches it itself, §9), after the user has accepted Google's terms
  in the installer, and the files the phone needs are extracted locally. No
  byte of Google's passes through a server of ours.
- **The factory image is the one that matches the phone**: the build whose
  bootloader and radio versions equal the ones the phone reports in fastboot
  (`version-bootloader`, `version-baseband`). §6 covers what happens when
  that build is no longer on Google's site.
- **Only slot B's five boot images and `userdata` are written**, through the
  checks `manifest.json` states as data (RELEASES §6). Stock Android stays on
  slot A. No installer, web or desktop, gets a code path for any other
  partition, `-w`, `--slot`, or an unsuffixed `fastboot flash`. The
  `flashing lock` step and the two writes it needs come only with secure
  mode (§8) and only after the maintainer approves them (SECURITY-PLAN D2).
- **Every install is checked before anything is written**: the bundle's
  signature by the release key, every file against the signed `SHA256SUMS`,
  the root image against the digest the signed `MANIFEST` names, the phone's
  product, the unlock state and the bootloader slots.
- **The radio backup is the user's.** It holds the IMEI and serial numbers.
  It is saved on the user's computer, never uploaded, never shown in a log
  or a bug report.
- **The installer's own code and the release are open and reproducible**, as
  everything else in the project (RELEASES §9).

## 3. Today's install, step by step

From [INSTALL.md](INSTALL.md) and [REINSTALL-RUNBOOK](../device/cheetah/REINSTALL-RUNBOOK.md),
which passed a clean reinstall on 2026-11-02 **[V]**:

| Step | Today | Tool |
| --- | --- | --- |
| Install the host tools | `pacman -S android-tools e2fsprogs zstd ...` by hand | none |
| Unlock | Developer options, OEM unlocking, `adb reboot bootloader`, `fastboot flashing unlock` | by hand |
| Download | the `.tar` (about 2.8 GB) from omamobile.org; Google's factory zip from Google's page, the right build chosen by hand | by hand |
| Check | `sha256sum -c`, optionally `gpg --verify`; the installer checks the signature itself | `install` |
| Install | `bash install --dry-run`, then `bash install`, answers typed in the terminal, codename typed | `tools/install-phone` |
| First start | grows the root, runs `omamobile-firstboot`, shows the lock screen | on the phone |
| USB network | `nmcli connection add ...` by hand | by hand |
| Radio backup | `tools/nv-backup DIR` | `tools/nv-backup` |
| Firmware | a Python venv for the camera, then `tools/phone-provision --nv-backup DIR FACTORY.zip` | `tools/phone-provision`, `tools/extract-*` |
| Restart | `tools/phone-ssh 'reboot-to omamobile'` | by hand |
| Check | none for the user; `tools/phone-smoke` for developers | `tools/phone-smoke` |

Every piece already exists and is tested. What's missing is the glue, a UI,
and a way to get the factory image without the user's help.

## 4. What the installer automates

Each step, with the tool it comes from and what changes.

### 4.1 Preflight on the computer

- **Host tools:** the desktop app ships its own `fastboot` implementation
  (or links libusb directly), `zstd` and the extraction code; the web
  flasher speaks fastboot over WebUSB. Nothing to install by hand, except on
  Linux a udev rule so the browser or the app may open the phone (the
  Omarchy package installs it; the web page shows the one-line rule for
  other distributions).
- **Disk space:** checked up front (today about 35 GB, INSTALL.md; less if
  extraction moves to the phone, §5).
- **The release:** `latest.json` for the device, then the bundle's files and
  the root image, each checked against the signed `SHA256SUMS` as it
  arrives (RELEASES §6). Downloads resume.

### 4.2 Unlock guidance (the one step on the phone)

Today: INSTALL.md step 1, by hand.

The installer detects which state the phone is in and shows only the steps
left:

- **Android running, USB debugging off:** pictures for Settings > About
  phone > Build number (seven taps), then Developer options > OEM unlocking
  and USB debugging. A note that OEM unlocking is greyed out on many carrier
  phones, and that then the phone can't be used.
- **Android running, USB debugging on:** the installer sends `reboot
  bootloader` over adb (the desktop app; the web flasher too, through an adb
  implementation over WebUSB **[I]**), or shows the button combination
  (Volume Down + Power) as the fallback.
- **Fastboot, locked:** `fastboot flashing get_unlock_ability` (read-only)
  says whether OEM unlocking is on. If it reads 0, back to the previous
  screen. If 1, the installer explains the wipe in one sentence ("Unlocking
  erases everything on this phone. Copy off photos, messages and two-factor
  codes first.") and asks the user to confirm in the installer, then sends
  `fastboot flashing unlock`; the user confirms again on the phone with the
  volume keys and Power. The phone erases itself and restarts.
- **Fastboot, unlocked:** on to the checks.

`flashing unlock` is a request the bootloader asks the person to confirm on
the phone, and it writes nothing of ours; it is the one `flashing` command
the installer sends, and only from this screen. After the unlock the phone
has to start Android once and be put back into fastboot; the installer
walks through that.

### 4.3 Phone checks

Today: `tools/install-phone`, "Checking the phone" **[V]**.

The same checks, read from `manifest.json` as data: one phone, product
equals the bundle's codename, unlocked, each image fits its `_b` partition
(an AVB footer image exactly). Two checks need work before they can be
automated without the user's help: the bootloader slots (gap G4, §10) and
which slot stock Android lives on (gap G5).

### 4.4 The owner's answers

Today: typed into `install-phone` on standard input, written as
`firstboot.conf` into a local copy of the root image with `debugfs`
**[V]**.

In the installer they are form fields with the same validation rules
(`install-phone`'s `USERNAME_RE`, `HOSTNAME_RE`, the reserved names, PIN or
password). The SSH key becomes optional: a user who never uses a terminal
doesn't need one, and the installer offers "Allow this computer to reach
the phone over USB" (the app's own key) as a checkbox for developers.
`firstboot.conf` stays data, never sourced. How it reaches the phone depends
on §5: in the image copy (today), or over the install link at first boot.

### 4.5 Signature and manifest checks

Today: `install-phone` checks `SHA256SUMS.sig` against the keys it carries,
every checksum, the root image against the signed `MANIFEST`, and
`manifest.json` against the descriptor and its own rules **[V]**.

The installer core does the same, with the release key's fingerprint built
into the installer (the web page and the app are themselves served or
packaged by us, so a changed key needs a new installer version, never a
change on the server). `latest.json` stays only a pointer.

### 4.6 Writing slot B and `userdata`

Today: `fastboot flash <image>_b` for each `BOOT_IMAGES` entry, `fastboot
flash userdata` with the root image, `--set-active=b`, `reboot` **[V]**.

The same writes, in the same order, from `manifest.json`. The confirmation
step (today: typing the codename) becomes a screen that lists the six
partitions in plain words ("the Omarchy Mobile system: boot images on slot
B, and the user data area, which is erased") with a button that needs a
deliberate press (hold to confirm, or type the phone's name). The
`userdata` image is streamed: zstd decompressed and cut into sparse chunks
no larger than the phone's `max-download-size`, so neither the browser nor
the app holds the whole image in memory.

### 4.7 The radio backup

Today: `tools/nv-backup DIR` after the first start, over USB SSH, by hand
**[V]**.

The installer takes it automatically at the first start, before the
provisioning step, into a folder on the user's computer that it names and
shows (and, in the web flasher, offers as a download the browser saves).
The install itself never writes the radio partitions; what matters is that
the backup exists before anything on the phone may touch them, and the
modem can't start before it: the modem profile starts only from copies of
the partitions that match the checksums `phone-provision` writes from this
backup **[V]** (REINSTALL-RUNBOOK §4a). Taking it before `userdata` is
written would need a RAM boot of our images (`fastboot boot`), which hasn't
been tried on cheetah; an open question, not a requirement.

The backup is about 430 MB and took 15 chunk retries on `modem_b` in the
2026-11-02 run over USB NCM **[V]**; the installer shows progress and
retries silently, as `nv-backup` does.

### 4.8 Provisioning

Today: `tools/phone-provision --nv-backup DIR FACTORY.zip` after the first
start: the `extract-*` tools on the computer, then pushes over USB SSH, then
the board id read on the phone **[V]**. §5 weighs folding this into the
install on the computer against doing it on the phone.

### 4.9 First-boot setup

Today: `omamobile-firstboot` reads `firstboot.conf`, creates the user, SSH,
ufw, runs Omarchy's setup and our user setup, and deletes the file **[V]**.
`systemd-firstboot` fails once on that boot (gap G3).

Unchanged in substance. The installer shows the phone's progress (growing
the root, creating the user, setting up Omarchy) from the install link
(§5.3) instead of the user watching a dark screen.

### 4.10 The health check

Today: `tools/phone-smoke` (`--json` for a machine) **[V]**, a developer
tool.

The installer runs it at the end and shows the result as a pass screen: the
required rows (boot slot, storage guard, root, kernel health, USB, session)
must pass, and the evidence rows (display, GPU, touch, Wi-Fi, Bluetooth,
battery, sound, sensors, cameras) are shown as ticks, or as a plain sentence
when one fails ("Cameras: not working yet. This is a known issue on this
release" when the release notes list it). A failed required row turns into
"Something went wrong" with a button that saves a report with identifiers
removed (§7).

## 5. Provisioning: on the computer or on the phone

Two ways to put the phone's own files on it. Both keep Google's files off
our servers; they differ in where the extraction runs and how the factory
image reaches it.

### 5.1 Option A: extract on the computer

What today's tools do. The installer downloads the factory image to the
computer, runs the extraction there and either writes the result into the
local root image copy before flashing (RELEASES §6 step 2-3, designed but
not built) or pushes it after the first start (today's `phone-provision`).

- For: it exists and works; nothing new on the phone; Wi-Fi works at the
  very first start.
- Against: the extraction needs `unzip`, `simg2img`, `lpunpack`,
  `fsck.erofs`, `debugfs` and, for the cameras, Python with unicorn and
  pyelftools (an AArch64 emulator running the camera HAL's functions,
  `tools/extract-camera-data`) **[V]**. In a desktop app that is a lot to
  bundle; in a browser all of it would have to be rewritten for
  WebAssembly. It uses many GB on the user's computer. And firmware updates
  later (§9) need the same extraction on the phone anyway, so this option
  means keeping two extraction paths.

### 5.2 Option B: extract on the phone

The phone runs the extraction at first boot. Its root image carries the
extraction tools as a package (`omamobile-provision`; Arch Linux ARM has
`android-tools`, `erofs-utils` and `e2fsprogs` for aarch64), and the same
code later serves firmware updates (§9).

- For: one extraction path for install and updates. The camera step may not
  need an emulator at all on an AArch64 phone: the HAL's functions could run
  natively in a vendor chroot, as the fingerprint, GNSS and modem chroots
  already do **[I]**. The computer, and the browser, only move a file.
  `userdata` has about 110 GB of room for the unpacking.
- Against: Wi-Fi needs its firmware, and the firmware is in the factory
  image, so the phone can't download the factory image over Wi-Fi at its
  first start. The image has to come over the USB cable from the computer.
  Some of the extraction tools need packaging and testing on aarch64
  (unicorn's Python module, if the camera step stays emulated). A failure
  during first boot needs a clear way back (§7).

### 5.3 Recommendation: B, with the image carried over an install link

The computer downloads the factory image from Google (it is the only side
with a network at that point), and hands it to the phone over USB at first
boot; the phone checks its SHA-256 and extracts it. The channel is an
**install link**: a small USB function the phone offers only in first-boot
install mode (FunctionFS in the gadget the initramfs already sets up, with
WebUSB and Microsoft OS 2.0 descriptors so browsers and Windows bind it
without a driver **[I]**). It speaks a few fixed messages and nothing else:

- status (first-boot progress, the release, the kernel);
- receive `firstboot.conf` and the optional SSH key (instead of `debugfs`
  into the image copy, so the web flasher needs no ext4 writer);
- send the radio backup, partition by partition with checksums (what
  `nv-backup` does over SSH today, the same read-only rules);
- receive the factory image, check its SHA-256 against the value the
  installer sends, and run the extraction and the board id step (what
  `phone-provision` does today);
- run `phone-smoke --here --json` and send the report;
- restart the phone.

It never offers a shell, never accepts a path or a command, stops for good
when first boot finishes, and is absent on a phone that was installed
before it existed. Because it doesn't use the USB network, the user's
computer needs no network setup at all (no `nmcli`, no addresses), and the
web flasher can use it, which it couldn't with SSH.

Until the install link exists (M2), the guided CLI (M1) does the same steps
over USB SSH, with option A's extraction on the computer, because that is
what works today.

## 6. Google's factory image

### 6.1 Picking the build

The phone reports `version-bootloader` and `version-baseband` in fastboot
**[V]** (install-phone reads the first). Each factory image's
`android-info.txt` names the bootloader and baseband it requires **[D]**.
The installer needs the build whose pair equals the phone's.

Google's factory images page lists each build with its download URL and
SHA-256 **[D]**, but not the bootloader and baseband versions. So the
project keeps a small **build index** per device: build id, Google's URL,
Google's SHA-256, the bootloader and baseband versions from that build's
`android-info.txt`, and whether a release has been tested with that build's
firmware. It holds metadata only, no file of Google's, and it is signed
by the release key (unlike `latest.json`, which is only a pointer): the
installer trusts the SHA-256 in the signed index, so a factory zip that doesn't match is refused before
extraction. The maintainer's tool that fills the index downloads each build
once on the maintainer's own machine to read `android-info.txt` (or reads
only that member with HTTP range requests, if the zip layout allows it
**[I]**).

### 6.2 When the phone's build is gone from Google's site

Google keeps many old builds on the page, but not forever **[I]**. In
order:

1. **The exact build** (bootloader and baseband both match): use it.
2. **A tested build with the same bootloader** but another baseband: the
   files we extract (Wi-Fi, Bluetooth, the AoC, haptics, amplifiers, camera
   data, the vendor chroots) are loaded by Linux, not by the bootloader; the
   modem's firmware is read from the phone's own `modem` partition, not from
   the factory image. Whether a newer build's AoC or Wi-Fi firmware works
   against an older bootloader and radio is untested **[I]**; the camera
   extraction gave the same five files from CP2A and CP3A builds **[V]**.
   Allowed only for builds the index marks tested with that pair.
3. **Otherwise:** the installer stops and explains that stock Android needs
   updating first (Settings > System > System update in Android, then come
   back), and why. Gap G5 matters here: an Android update moves stock to the
   other slot.

Which builds count as tested, and how many combinations the project tests,
is an open question (D3).

### 6.3 Google's terms

Google's page asks the visitor to acknowledge terms before it shows the
download links **[D]**. The installer shows those terms, linked to Google's
own page, with a checkbox the user must tick before the download starts,
and records that it was ticked (on the computer only). Whether a third-party
installer may present the acknowledgement this way, or must send the user
to Google's page to click through, needs checking before M1 ships (D2). The
fallback is honest and still simple: a button that opens Google's page at
the right build, and a file picker (or a watched Downloads folder) for the
zip the user saved.

### 6.4 Downloading in a browser

Google's download host must allow cross-origin reads for the web flasher to
fetch the zip itself **[I]**; Google's own browser flasher downloads from
its own origin, which proves nothing for ours. If it doesn't, the web
flasher uses 6.3's fallback (the user saves the zip, the page reads it from
disk with the File System Access API or a file input). A proxy of ours is
not an option (§2). The desktop app has no such limit.

### 6.5 Shipping Google's files ourselves

This is our reading of Google's published terms, not legal advice.

Google's [factory images page](https://developers.google.com/android/images)
says the images "are for use only on your personal Nexus or Pixel devices"
and "may not be disassembled, decompiled, reverse engineered, modified or
redistributed by you", and that downloading them is subject to Google's
Terms of Service **[D]**.

- **So the design stays as it is:** the user's own machine (or the user's
  own phone, §9) downloads the factory image from Google, for that user's
  own Pixel, and the files the phone needs are extracted locally. That is
  the most defensible reading of those terms we have. It isn't spotless:
  "modified" makes any extraction a grey area, one that every system other
  than Google's running on a Pixel shares.
- **Bundling or hosting Google's vendor files ourselves is out**, in a
  bundle, a package or anywhere on our servers, unless Google gives written
  permission, or a lawyer's opinion says otherwise. The maintainer may ask
  Google (D7).
- **If permission came,** the provisioning step shrinks: the release would
  carry the device's firmware and vendor files itself (a firmware package
  per device in `[omamobile]`, installed in the root image), so the install
  needs no factory image, no terms screen, no build index and no extraction,
  and the first start has everything. M5 then becomes ordinary package
  updates through the Updater. The per-phone data (the radio backup, the
  board id, the NV checksums) would still come from the phone itself.

## 7. Recovery and going back to stock

In the same installer, as first-class screens:

- **Go back to Android:** `fastboot --set-active=a` and `reboot` (INSTALL.md,
  "Going back to Android"), with the explanation that Android will show its
  recovery screen and needs "Factory data reset" because `userdata` now
  holds Omarchy Mobile. A reminder that a stock boot rewrites `efs`,
  `persist` and `modem_userdata`, so a later reinstall takes a new radio
  backup (AGENTS §1).
- **Remove Omarchy Mobile completely:** a link to Google's own flashing
  tools for the phone's factory image. The installer doesn't flash stock
  itself: that writes the bootloader and radio, which no tool of ours does.
  A clear warning not to lock the bootloader unless both slots hold Google's
  images (until secure mode exists, §8).
- **Repair:** rewrite slot B's boot images from the release, keeping
  `userdata` (the same five writes, no `userdata` flash), for a phone that
  stops in fastboot after a bad update. Needs a narrow mode in the core, a
  dry run and its own confirmation screen; `bin/omamobile flash` is today's
  developer equivalent. A per-device rule from the descriptor applies here:
  on the Pixel 9a a fastboot write to slot B clears its successful mark
  (AGENTS §4), so a device whose descriptor says so gets a warning and the
  maintainer's procedure, not an automatic repair.
- **Reinstall:** the full install again, which erases `userdata`; offered
  with a restore of the radio backup's checksums from the folder the first
  install saved.
- **The phone isn't answering:** button combinations with pictures (Volume
  Down + Power about 20 s for fastboot; Power about 30 s to force a
  restart), per device from the descriptor, and the "choose neither" rule
  for Android's recovery screen (AGENTS §4).
- **Ask for help:** a report (installer log, `phone-smoke` JSON, release,
  phone model) with serial numbers, IMEI, MAC addresses and the Wi-Fi name
  removed, which the user reads before attaching it to an issue. Never the
  radio backup.

## 8. How it fits the security plan

[SECURITY-PLAN](SECURITY-PLAN.md) makes the release install the place where
a phone becomes secure: LUKS2 on `userdata` with the PIN entered on the
phone, our key in `avb_custom_key`, `vbmeta_b` with our chain, and
`fastboot flashing lock` (§5.4 there, phases S6-S7, decisions D1-D2). This
installer is that release installer:

- **Secure mode is a step in the same flow**, not a separate tool: after the
  slot B writes, the installer writes `pkmd.bin` and `vbmeta_b`, sets slot B
  active and asks for the lock, then shows our key's fingerprint so the user
  can compare it with the yellow screen. None of it ships before the
  maintainer approves the exceptions (SECURITY-PLAN D2).
- **No `userdata` flash in secure mode.** The root image goes over USB into
  the phone's setup mode, which writes it into the new LUKS2 volume only if
  its digest matches the one built into the verified `init_boot`. The
  install link (§5.3) and that setup-mode stream should be one protocol, so
  the provisioning payload (the factory image, `firstboot.conf`) rides the
  same channel and lands inside the encrypted volume.
- **The PIN never crosses the cable**: it is chosen on the phone's own PIN
  pad in setup mode. The installer's form asks for it only on a development
  install (today's `firstboot.conf` password).
- **Development mode** is an advanced choice in the installer ("I build or
  test Omarchy Mobile"): unlocked, plain ext4 or LUKS2, today's flow.
  Switching a secure phone to development mode means unlocking, which
  wipes; the installer says so.
- **Going back to stock from a locked phone** needs a different screen:
  Google's images on slot A still boot on a locked phone with our key
  **[I]** (SECURITY-PLAN §3), but unlocking again wipes `userdata`. Written
  with S7's results, not before.

## 9. Firmware updates later

When Google publishes a new factory image for the phone, the phone can get
the matching firmware without its owner doing anything, through the
Updater:

1. **The project's build index** (§6.1) gains the new build once a release
   has been tested with its firmware on the device. The index is metadata,
   delivered with the `[omamobile]` repository or beside `latest.json`.
2. **The Updater sees a newer tested build** whose bootloader and baseband
   are compatible with the phone's (read on the phone; the phone's
   bootloader and radio never change under Linux, because nothing of ours
   writes them).
3. **It asks once, the first time,** to accept Google's terms (§6.3); the
   owner can choose to be asked every time instead. Then, on Wi-Fi, on the
   charger or above a battery level, and with enough free space (the zip
   plus room to unpack, several GB **[I]**), it downloads the factory image
   straight from Google to the phone, checks the SHA-256 from the signed
   index, and extracts it with the same `omamobile-provision` code as the
   install (§5.2).
4. **It installs the new firmware set beside the old one**
   (`/usr/lib/firmware/updates` and the vendor chroots in versioned
   directories with a link to the current one, instead of overwritten in
   place as `phone-provision` does today), asks for a restart like a kernel
   update does, and keeps the previous set for a rollback if the next boot's
   health check fails.
5. **It deletes the factory image** afterwards.

Constraints:

- Only files Linux loads can be updated this way. The bootloader, the radio
  and the modem firmware on the `modem` partitions stay at whatever stock
  last wrote; updating those means updating stock Android, which is outside
  this plan (and moves stock to the other slot, G5).
- A firmware set from a newer build may not match an older bootloader or
  radio (§6.2). Only builds the index marks tested for a compatible pair are
  offered.
- The AoC firmware is authenticated by the security chip **[V]** (AGENTS
  §4); a mismatch would show as audio and sensors failing to start, which the
  health check after the restart must catch.
- The camera data is recomputed per HAL build; the tool searches a few
  layouts per build **[V]**, so a new build can fail extraction, and the
  Updater then keeps the old set and reports it.
- On a secure phone the firmware lives inside the encrypted root, so nothing
  changes for the verified boot chain.
- Google's terms, and whether automatic downloads on the owner's behalf are
  acceptable under them, is part of D2.

## 10. Gaps found in the 2026-11-02 test install

From the 2026-11-02 reinstall and release test install on the reference
phone (REINSTALL-RUNBOOK §10, RELEASES §11). M0 fixes them before anything
else.

- **G1. `phone-provision` needs a separately downloaded factory zip, and
  picks its mode by guessing.** It takes the zip as an argument, and decides
  between a first install and a reinstall by whether `phone-config.tar`
  exists in its default backup directory (`~/android/reference/phone-backup-20261013`)
  **[V]**. On the maintainer's machine a first install looks like a
  reinstall; on anyone else's, every install is a first install. Fix: an
  explicit mode (`--first-install` with `--nv-backup DIR`, or `--restore
  DIR`), no default backup path in the bundle's copy, and the factory image
  fetched by the tool itself (§6) when none is given.
- **G2. The stable channel must exist before a release's first update.**
  `tools/release`'s `test-install` stage runs before `promote`, and a
  release install follows `stable`, so the test-installed phone's first
  `omarchy update` finds no stable index. Fix: promote a first stable index
  once, before the first release's test install (later releases find the
  previous release there, which is correct); and `omamobile-update` reports
  "this channel has no updates yet" as a normal state, not an error.
- **G3. `systemd-firstboot` fails once on first boot.** It wants to ask for
  settings on a console the phone doesn't have. Fix: the root image provides
  what it asks for (locale, keymap, time zone from `firstboot.conf`, machine
  id policy) and masks `systemd-firstboot.service`, as
  `omamobile-device-dodge` already does **[V]**; `phone-smoke` gets a "no
  failed units after first boot" row so it can't come back unnoticed.
- **G4. The bootloader slot check can only read the current slot's
  version.** On cheetah fastboot reports `version-bootloader` for the
  current slot only, so `install-phone` stops and asks the user to confirm
  the other slot with `--bootloader-slots-match` **[V]**. A guided installer
  can't ask a non-technical user that. Options: (a) the installer switches
  to the other slot, restarts into fastboot, reads its version and switches
  back (only the bootloader's own slot flags change, the same kind of write
  as the install's `--set-active=b`, but a maintainer decision, D4); (b) it
  compares the current slot with the factory image's required bootloader
  and trusts Google's flashing tools to have written both slots **[I]**;
  (c) it reads both versions from Android before the reboot to fastboot, if
  Android exposes the other slot's **[I]**. Option (a) is the only one that
  measures.
- **G5. Found while writing this plan, not in the test install: no check
  that stock lives on slot A.** `install-phone` reads `current-slot` and
  prints it but doesn't refuse slot B **[V]**. After an Android system
  update stock runs from slot B, so an install would overwrite the running
  stock, and slot A would hold the older build. On a reinstall slot B is
  ours and current, which is fine. The installer has to tell the two apart
  (asking the user, `slot-successful` and `slot-unbootable` hints, the
  install's own record on the computer) and, when stock is on B, guide the
  user to put it on slot A first.

## 11. Milestones

In order. Each can ship on its own, and each removes manual steps for
real users.

### M0. Fix the test install's gaps

- **What:** G1-G3 and G5's refusal; G4's option chosen (D4) and built into
  `install-phone`.
- **Needs:** small changes to `tools/phone-provision`, `tools/release`,
  `omamobile-update`, the root image and `tools/install-phone`, with tests
  in `tests/`.
- **Open:** G4 (D4).

### M1. A guided CLI, end to end

- **What:** the bundle's `install` grows into one command that runs the
  whole install with today's tools: preflight, unlock guidance from the
  phone's state (§4.2), the build index lookup and the factory image
  download from Google after the terms prompt (§6), the checks and writes
  (`install-phone`), the USB network connection set up with the user's
  consent (a NetworkManager profile for `cdc_ncm`, shown before it is
  added), waiting for the first start, `nv-backup` into a named folder,
  `phone-provision` in first-install mode, the restart, and `phone-smoke`
  shown as a pass list. A state file lets it resume after any failure from
  the step that failed.
- **Needs:** M0; the build index (§6.1) and the maintainer tool that fills
  it; the camera's Python modules handled by the tool (its own venv) or the
  camera step moved to the phone early.
- **Open:** Google's terms in a third-party tool (D2); still Linux only,
  still a terminal; what the index marks as tested (D3).

### M2. Install mode and the install link on the phone

- **What:** first-boot install mode with the USB install link (§5.3), and
  `omamobile-provision` on the phone, extracting the delivered factory image
  there. The CLI switches to the link: no USB network setup, no SSH, and the
  extraction tools leave the computer.
- **Needs:** FunctionFS in the initramfs gadget or in the root's first boot
  (whichever owns USB at that point); the extraction tools packaged for
  aarch64 and tested against today's output byte for byte; the camera step
  natively in a chroot or under unicorn on the phone; a protocol spec with
  tests on both sides.
- **Open:** browser and Windows binding through WebUSB and Microsoft OS 2.0
  descriptors **[I]**; time and space for extraction on the phone; whether
  the link and SECURITY-PLAN's setup-mode stream are built as one from the
  start (recommended).

### M3. The shared core and the desktop app

- **What:** one installer core (state machine, `manifest.json` rules,
  signature and checksum checks, fastboot, the sparse streamer, the install
  link, the build index) used by both front ends. The Omarchy Mobile
  Installer app for Omarchy first (an Omarchy package with its udev rule),
  then other Linux distributions; macOS and Windows later.
- **Needs:** a language that builds both to WebAssembly and to a native
  binary (Rust is the obvious candidate; TypeScript with a native USB
  backend is the other) and one UI shared by the app and the web page (a
  web UI in a native window, so the two look and behave the same). The CLI
  from M1 stays as the scriptable front end of the same core.
- **Open:** language and UI toolkit (D5); signing and distributing the app
  outside Omarchy.

### M4. The web flasher

- **What:** omamobile.org/install, the same UI in a Chromium-based browser
  over WebUSB.
- **Needs:** M3's core in WebAssembly; streaming everything (the root image
  is about 2.7 GB compressed, RELEASES §6), with zstd decompression and
  sparse chunking in the browser and downloads cached in the origin's
  private storage so a failed install doesn't download again; the fastboot
  transfer cut to `max-download-size`; a page served from our own server
  with a strict content security policy, no third-party scripts, and the
  release key's fingerprint built in.
- **Open:** WebUSB only exists in Chromium-based browsers **[D]**; browser
  storage quotas for several GB **[I]**; Google's download host and
  cross-origin reads (§6.4), with the save-and-pick fallback if it refuses;
  Windows needs a driver for fastboot itself (Google's USB driver)
  **[I]**; Linux needs the udev rule.

### M5. Firmware updates through the Updater

- **What:** §9: the build index in the Updater, the phone downloading and
  extracting new firmware from Google, versioned firmware sets with
  rollback.
- **Needs:** M2's `omamobile-provision` on the phone; the index process
  with a tested flag per build and device; a health check after the
  restart that can roll back.
- **Open:** compatibility between newer firmware and older bootloaders and
  radios (§6.2); D2 for automatic downloads.

### M6. Secure installs

- **What:** SECURITY-PLAN's S6 inside this installer (§8): encryption,
  `avb_custom_key`, `vbmeta_b`, the lock, the key fingerprint screen.
- **Needs:** SECURITY-PLAN's phases up to S7 passed on the reference phone,
  and its D2 approved.
- **Open:** everything SECURITY-PLAN lists as open.

### Across all milestones: more devices

Every device rule comes from the device's `device.conf` and its bundle's
`manifest.json`, never from installer code (RELEASES §3): the codename and
product, the boot images, the NV partitions, the button combinations and
pictures, the extraction map (which files, under which names), and quirks
such as the Pixel 9a's slot mark (AGENTS §4). A device is offered in the
installer only when its descriptor can be installed by `install-phone`
(today's check: `BOOT_METHOD` android-v4 and a `SOC_IDS` or
`SOC_COMPATIBLE`) and it has a published release. A device whose install
needs a partition table write (the Pixel 4 family, CONTRIBUTING §3.1) is
never offered: that write stays a manual, named exception.

## 12. Decisions for the maintainer

- **D1. Provisioning:** on the phone with the install link (recommended,
  §5.3), or on the computer (option A) for the long term too.
- **D2. Google's terms:** check whether the installer may show Google's
  acknowledgement itself and download on the user's behalf, and whether the
  Updater may download later firmware automatically after one acceptance.
  Until then, M1 uses the open-Google's-page-and-pick-the-file fallback.
- **D3. Tested builds:** which factory builds the index marks tested, and
  how a build earns it (a `phone-smoke` pass on the reference phone with
  that build's firmware is the proposal).
- **D4. The other bootloader slot (G4):** switch slots in fastboot to read
  it (measured, but the installer changes slot flags twice), or trust a
  factory flash and the user's word.
- **D5. Core language and UI** for M3.
- **D6. The build index's home:** beside `latest.json` on our server,
  inside a package in `[omamobile]`, or both; signed by the release key
  either way.
- **D7. Shipping Google's files ourselves (§6.5):** keep fetching from
  Google and extracting locally (the plan's design), and optionally ask
  Google for written permission to redistribute the vendor files, or get a
  lawyer's opinion first. Nothing is bundled or hosted unless one of those
  says it may be.
