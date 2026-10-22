<!-- SPDX-License-Identifier: MIT -->
# Install native Omarchy on a POCO F3

Experimental, for **POCO F3 / fastboot product `alioth`**. Read the
[hardware status](BRINGUP-M1.md) first. This installs native Arch Linux ARM
and Omarchy. Calls, SMS/MMS, mobile data, GPS, cameras, audio and vibration
are not supported by this initial profile. Suspend is disabled.

Installation **erases all Android userdata**, including encryption metadata.
Slot A's boot images are preserved, but its Android installation will need
a factory reset to use the replaced userdata. Never relock the bootloader.
The installer does not unlock it or write radio, bootloader, vbmeta or NV.

All commands below run from the repository root on a Linux computer. The
build phase does not access a phone. A dry run does not even query fastboot.
Every hardware-changing step is a separate decision: read its plan before
running it, and be ready to recover the phone with the physical buttons.

## Prepare the computer and build — low risk

Use an unlocked F3 and a reliable USB cable. Back up wanted Android files
before unlocking or installing. Keep the correct Xiaomi factory archive
for the phone's installed regional build as a recovery resource; do not
substitute an older firmware or run its bulk flashing scripts.

The build host needs Docker access and an aarch64 binfmt handler
(`qemu-aarch64` under `/proc/sys/fs/binfmt_misc`), Python 3.12+, Bash, GnuPG,
OpenSSH, OpenSSL, curl, tar, zstd, cpio, e2fsprogs (`debugfs`, `e2fsck`,
`dumpe2fs`), Android sparse-image tools (`simg2img`, `img2simg`), AOSP
`mkbootimg` and `avbtool`, and `adb`/`fastboot`. The existing package builder
also needs `repo-add`, `bsdtar` and a C compiler. For an x86 host, the rootfs
build uses QEMU user emulation. Allow at least 80 GB of free disk space;
package caches and image validation copies can require more.

An Omarchy host supplies `/usr/share/pacman/keyrings/omarchy{.gpg,-trusted,-revoked}`.
On another distribution, obtain and verify the official Omarchy keyring
first, then set `OMARCHY_KEYRING_DIR` to its directory. Do not disable package
signature checks to get a build through.

```sh
python3 tools/alioth/build.py --username mobile --timezone UTC
```

Choose your own non-system username and IANA timezone. The script generates
dedicated SSH and local package-signing keys, downloads the
[pinned F3 reference release](https://github.com/Sucharek233/pmos-alioth-builds/releases/tag/2026-09-28_935d1cb),
checks its SHA-256, extracts its unmodified kernel/DTB and matching runtime,
and builds the Omarchy root and private boot images. It uses stable Omarchy
by default; distribution package versions are recorded in the root manifest.
An already downloaded reference can be supplied with `--reference-archive`.
The F3 builder uses a signing-key-specific cache below
`out/alioth/build-cache/` (or below `ALARM_CACHE` when supplied), avoiding
same-version packages left over from another local signing key.

Expect: all build, image, filesystem, sparse round-trip and ARM Dropbear
login checks pass. Stop on any failure. Rollback: discard the failed local
outputs; no phone has been accessed. These are not bit-for-bit reproducible
distribution package builds: repositories can advance between builds.

Images are in `out/alioth/images/`. The random initial PIN is stored locally
in `keys/alioth-credentials.json`. Keep **all `keys/` and `out/` private**:
boot images contain your SSH authorization and private rescue host identity;
root images contain your initial credential and downloaded runtime firmware.
Do not attach these files, backups, logs or screenshots to a public PR.
Only source is published by this port; it does not offer a public prebuilt
image or redistribute the reference firmware.

## Preserve the original partitions — moderate risk

Download `twrp-3.7.1_12-0-alioth.img` from the
[official Team Win download page](https://dl.twrp.me/alioth/twrp-3.7.1_12-0-alioth.img.html)
into `out/alioth/inputs/`. The helper accepts only SHA-256
`bf5bf3300da28abbef0493829a35fcd703424c1255172f5613789a7e2cfed2e3`.

```sh
python3 tools/alioth/prepare-recovery-ramboot.py
```

This removes padding to fit the bootloader's RAM-download limit. Original
boot payload, AVB metadata and footer must remain identical, and avbtool's
embedded hash check must pass. No recovery is installed persistently.

Enter FASTBOOT with Volume Down + Power. The following queries are read-only:

```sh
fastboot getvar product
fastboot getvar unlocked
fastboot getvar current-slot
```

Expect `alioth`, unlocked, slot A. Stop otherwise. Do not paste full fastboot
dumps into an issue: they contain identifiers. Then explicitly choose to
temporarily boot recovery:

```sh
fastboot boot out/alioth/inputs/twrp-3.7.1_12-0-alioth-ramboot-96MiB.img
```

Keep recovery read-only. Do not install TWRP, format data or enable ADB
sideload. When root ADB is available, capture and verify original partitions:

```sh
python3 tools/alioth/backup-recovery.py
```

Record the printed **manifest file** path, for example:

```sh
BACKUPS=keys/backups/alioth-YYYYMMDD-HHMMSS/BACKUP-MANIFEST.json
```

Expect A/B boot, dtbo, vendor_boot and all required/discovered NV backups,
with phone and host SHA-256 agreeing. Stop if any backup fails. Rollback:
return to FASTBOOT and boot slot A; recovery was never flashed. After any
stock Android boot, take fresh backups before continuing because Android
changes NV state. These backups do not include personal Android userdata.

## Prove rescue access before erasing Android — moderate risk

Return to FASTBOOT. Review the plan, then choose the temporary rescue trial:

```sh
DEVICE=alioth bin/omamobile flash --probe --dry-run
DEVICE=alioth bin/omamobile flash --probe --flash --backups "$BACKUPS"
```

This **erases `dtbo_b`**, selects B and RAM-boots the rescue image. It does
not flash or mount userdata. The rescue command line disables root mounting
and resizing. This is not a zero-write probe: original dtbo_b is backed up.

```sh
python3 tools/alioth/phone-client.py host-up
python3 tools/alioth/phone-client.py doctor
python3 tools/alioth/phone-client.py shell
```

Expect key-authenticated rescue SSH at 172.16.42.1, kernel 6.15.1-sm8250,
userdata unmounted, protected partitions read-only and the main whole-disk
node absent. `host-up` configures only the image's synthetic USB interface,
without a default route. Check guards from the shell before proceeding:

```sh
test ! -e /dev/sda
cat /proc/mounts
for p in /sys/class/block/*; do
  [ -r "$p/partition" ] || continue
  cat "$p/uevent" "$p/ro"
done
```

Only userdata may be writable in this rescue build. Stop on a guard failure,
repeated watchdog resets, overheating or missing SSH. Rollback before a
userdata flash: hold Volume Down + Power, select slot A and reboot. This
retains Android data but invalidates the NV backup for the next attempt.

## Flash the reviewed image — high risk; erases Android data

From FASTBOOT, select A **without booting Android**, so the initial-install
preflight can check the same starting state as the backup:

```sh
fastboot --set-active=a
DEVICE=alioth bin/omamobile flash --dry-run
DEVICE=alioth bin/omamobile flash --flash --confirm-erase-userdata --backups "$BACKUPS"
```

Preflight checks product, unlock state, slot, actual partition sizes, pinned
recovery, personalized-image hashes and the original backup manifest bound
to this phone. Write targets are literals in code: userdata (64 MiB sparse
transfers), dtbo_b erase, then boot_b. No manifest can redirect writes to
another partition. Slot A, vendor_boot, vbmeta, radio and NV are never written.

Stop on the first failed command. Do not blindly rerun a long transfer.
If USB bulk transfer stalls, physically restart FASTBOOT and try another
cable/USB port or a USB 2.0 hub. A successful `fastboot devices` listing alone
does not reset a stalled bulk connection.

If userdata finished but boot installation was interrupted, preserve the
same images and backups. RAM-boot rescue again, verify the entire unmounted
root, return to FASTBOOT, select A without booting Android, then finish:

```sh
python3 tools/alioth/verify-device-root.py --backups "$BACKUPS"
# After returning to FASTBOOT and selecting A without booting Android:
DEVICE=alioth bin/omamobile flash --finish-boot --dry-run
DEVICE=alioth bin/omamobile flash --finish-boot --flash \
  --backups "$BACKUPS" --verified-root keys/alioth-userdata-verified.json
```

Completion requires a phone-bound full root readback less than 30 minutes
old. It does not resend userdata. Mounting/changing userdata invalidates it.

## First login and recovery

Keep USB attached while the root grows and firstboot provisions the account.
Unlock with the PIN in your private credentials file, then change it using
the native Omarchy Mobile credential controls. Connect Wi-Fi in quick
settings. Controls are in the top bar; later custom Settings/keyboard work
is not part of this initial port.

```sh
python3 tools/alioth/phone-client.py doctor
python3 tools/alioth/phone-client.py screenshot out/alioth/desktop.png
python3 tools/alioth/phone-client.py shell
```

Capture private logs before further experiments. Do not publish them raw.
Automatic Xiaomi A/B boot-success marking is not implemented. Avoid repeated
failed boots; if the bootloader changes slots, use physical FASTBOOT and
reselect B. Software reboot-to-bootloader is unreliable on this kernel.

To return to stock, use FASTBOOT to select A, then the original Android
recovery's factory reset to recreate Android userdata. That destroys the
Omarchy root. If slot A does not boot, stop and construct a restore plan from
your own verified originals and correct factory build. Restoring NV or
relocking the bootloader is never a routine recovery step.
