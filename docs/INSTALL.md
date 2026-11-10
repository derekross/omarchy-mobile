<!-- SPDX-License-Identifier: MIT -->
# Installing Omarchy Mobile on a Pixel 7 Pro

This guide installs a release of Omarchy Mobile on a Pixel 7 Pro (codename `cheetah`). Releases are developer previews, named by date (for example `2026.11.15`). Releases are listed at [omamobile.org/download](https://omamobile.org/download), and each phone's page lists what works and what doesn't yet ([Pixel 7 Pro](https://omamobile.org/devices/cheetah), from [DEVICES.md](https://github.com/derekross/omarchy-mobile/blob/main/docs/DEVICES.md)).

Omarchy Mobile is a community project built on [Omarchy](https://omarchy.org). It isn't an official Omarchy or Basecamp product.

It takes about an hour, most of it downloads and waiting. You type a few commands in a terminal on your computer; each step says what you should see.

Today these steps are manual. Where the install is going, one guided step from a web page or a desktop app with the phone's firmware fetched for you, is in the [install experience plan](https://github.com/derekross/omarchy-mobile/blob/main/docs/INSTALL-EXPERIENCE-PLAN.md).

## Before you start: what happens to your phone

- **Installing erases the phone's data.** Unlocking the bootloader erases it, and the installer replaces the user data partition (`userdata`) with Omarchy Mobile. Copy off anything you want to keep first: photos, messages, two-factor codes.
- **Android stays on the phone as your way back.** A Pixel has two copies of its system, slot A and slot B. The installer writes only slot B and `userdata`. Stock Android stays on slot A, untouched, and [Going back to Android](#going-back-to-android) shows how to switch back.
- **The installer never touches the bootloader, the radio, or the partitions that hold your phone's identity and calibration** (`persist`, `efs`, `modem`, `devinfo`, `vbmeta`). It checks the phone before writing anything, shows every command it will run, and waits for you to type the phone's codename.
- **This is a developer preview.** Calls, SMS and mobile data work on the one network tested so far (a Verizon-network SIM), with the carrier's APNs set by hand after the install (the release notes say how), and the phone doesn't yet go to sleep by itself when the screen turns off. Check the [device page](https://omamobile.org/devices/cheetah) for the current list.

## What you need

- **A Pixel 7 Pro** whose bootloader can be unlocked. Phones sold locked to a carrier often can't be. In Android, go to Settings > About phone and tap Build number seven times to turn on Developer options, then check that Settings > System > Developer options > **OEM unlocking** can be switched on. If it's greyed out, the phone can't be unlocked.
- **A computer running Linux** (Omarchy, Arch Linux or another distribution), and a USB-C cable that carries data. The installer is a shell script for Linux; installing from a web page or a desktop app is planned.
- **These programs on the computer:** `fastboot` and `adb` (Android platform tools), `e2fsprogs`, `zstd`, `lz4`, `cpio`, `openssl`, `gnupg`, `python3`, `unzip`, and `binutils`. On Omarchy or Arch Linux:

  ```sh
  sudo pacman -S --needed android-tools e2fsprogs zstd lz4 cpio openssl gnupg python unzip binutils erofs-utils
  ```

  On other distributions, install the packages with the same names (Android's tools are often split into `fastboot`, `adb` and a "libsparse" package for `img2simg` and `simg2img`).
- **Free disk space:** about 35 GB (the downloads, Google's factory image and a working copy of the system image while installing).
- **An SSH key.** The installer puts your public key on the phone so your computer can reach it over USB later. If `~/.ssh/id_ed25519.pub` doesn't exist, make one:

  ```sh
  ssh-keygen -t ed25519
  ```

- **The release,** from [omamobile.org/download](https://omamobile.org/download), in one of two ways:
  - **one file** (the easy way): `omamobile-cheetah-<version>.tar` (about 2.8 GB) and its checksum file `omamobile-cheetah-<version>.tar.sha256`, downloaded into the same folder (and `omamobile-cheetah-<version>.tar.sha256.sig` too, for step 2's optional signature check). Step 2 checks and unpacks it.
  - **file by file:** the bundle (a folder named `omamobile-cheetah-<version>`) and the root image (`omamobile-rootfs-cheetah-<version>-aarch64.img.zst`), side by side in the same folder. Downloads often lose the files' execute permission, so run `chmod +x tools/*` once inside the bundle folder (`tools/phone-provision` runs the other tools there directly).
- **Google's factory image for your phone,** from [Google's factory images page](https://developers.google.com/android/images#cheetah): the build your phone runs now (Settings > About phone > Build number). Check its SHA-256 against the one on Google's page (`sha256sum cheetah-*.zip`). Omarchy Mobile never ships Google's files: after the install, a tool copies the firmware your phone needs (Wi-Fi, Bluetooth, audio, haptics, the camera) out of this image, on your computer, and onto your phone.

## 1. Unlock the bootloader (this erases the phone)

Skip this step if your bootloader is already unlocked.

1. In Android, turn on **OEM unlocking** and **USB debugging** in Developer options.
2. Connect the phone to your computer, allow USB debugging on the phone when it asks, and run:

   ```sh
   adb reboot bootloader
   ```

   The phone restarts into **Fastboot Mode** (a screen with an Android robot and "Fastboot Mode" in red).
3. Unlock:

   ```sh
   fastboot flashing unlock
   ```

   On the phone, use the volume keys to choose "Unlock the bootloader" and press Power. The phone erases itself and starts Android again.

From now on the phone shows a warning that its bootloader is unlocked each time it starts. That is normal. **Never lock the bootloader again** (`fastboot flashing lock`) while Omarchy Mobile is on the phone: a locked bootloader refuses to start anything that isn't Google's.

## 2. Check the release

If you downloaded the one `.tar` file, check that it arrived whole, then unpack it, in the folder you downloaded it to:

```sh
sha256sum -c omamobile-cheetah-<version>.tar.sha256
tar -xf omamobile-cheetah-<version>.tar
```

The first command should print `omamobile-cheetah-<version>.tar: OK`. If it says `FAILED`, download the `.tar` again. Unpacking gives the bundle folder and the root image side by side, as the installer expects; you can delete the `.tar` afterwards. The `.tar.sha256` is itself signed with Omarchy Mobile's release key (`omamobile-cheetah-<version>.tar.sha256.sig`, key fingerprint `2056 7593 566E EEE2 DD88 6460 8632 C807 5EB9 4673`): if you already have that key in `gpg`, `gpg --verify omamobile-cheetah-<version>.tar.sha256.sig` checks it too.

Either way, the installer checks the release by itself before it touches the phone: the bundle's signature (Omarchy Mobile's release key, which it carries), every file's checksum, and that the root image is the one the signed bundle names. If anything doesn't match, it stops.

If you downloaded file by file and want to check the downloads yourself first, compare their SHA-256 with the ones on the download page:

```sh
sha256sum omamobile-rootfs-cheetah-<version>-aarch64.img.zst
```

## 3. Install

Stock Android must be running from slot A, because Omarchy Mobile goes on slot B and stock stays on A as your way back. An Android system update can leave stock running from slot B; the installer refuses such a phone and says so. Then, in Fastboot Mode, make slot A active (`fastboot --set-active=a`), flash Google's factory image for your phone onto it with Google's own `flash-all` script (it erases Android's data: back up anything you want to keep first), check that Android starts, and come back to this step. The installer then may ask you to confirm the other slot's bootloader version with `--bootloader-slots-match`, as it explains. Reinstalling over an earlier Omarchy Mobile install, which runs from slot B, is the one case for `bash install --reinstall`.

1. Put the phone in Fastboot Mode. Either run `adb reboot bootloader` while Android is running, or, with the phone off, hold **Volume Down**, then also hold **Power**, and keep both held until "Fastboot Mode" appears (up to about 20 seconds).
2. Connect the phone and check that the computer sees it:

   ```sh
   fastboot devices
   ```

   You should see one line with a serial number and `fastboot`.
3. Go into the bundle folder and do a **dry run** first. It reads the phone's details, asks its questions, prepares everything and prints every command it would run, but writes nothing to the phone:

   ```sh
   cd omamobile-cheetah-<version>
   bash install --dry-run
   ```

   (`bash install` works even when the download lost the file's execute permission; `./install` does the same when it hasn't.)

   It asks for:
   - **a user name** (lower case, for example `alex`);
   - **a password or a PIN.** It unlocks the phone and is your password for `sudo`. Digits only gives you a PIN pad on the lock screen; anything else gives a password field;
   - **a host name** (the phone's name on a network), a **time zone**, and optionally a name and email for `git`;
   - **a Wi-Fi network and its password** (optional, but the first start finishes setting up faster with internet);
   - **your SSH public key** (Enter takes `~/.ssh/id_ed25519.pub`).

   Then it shows the plan: five `fastboot flash` lines, each for a partition ending in `_b`, one `fastboot flash userdata`, then `fastboot --set-active=b` and `fastboot reboot`. Nothing else. Type `cheetah` when it asks, and it prints the commands instead of running them.

   **If it stops about the bootloader slots** (both slots must carry the same bootloader version, and on some phones the bootloader only reports one of them), don't work around it: [open an issue](https://github.com/derekross/omarchy-mobile/issues) and we'll help.
4. Install for real:

   ```sh
   bash install
   ```

   Answer the same questions, read the plan, and type `cheetah`. Each image is written in a few seconds. The system (`userdata`) takes several minutes over USB. Then the phone restarts by itself.

If a step fails, the installer stops and says why. The phone stays in Fastboot Mode, and Android on slot A is untouched. Read the message, fix the cause and run `bash install` again. Don't run it over and over in a loop; if you're unsure, ask in an issue.

## 4. The first start

After the unlocked-bootloader warning, the first start does three things by itself, and takes a few minutes:

1. It grows the system to fill the whole `userdata` partition (about 110 GB).
2. It sets up your user account, the firewall and Omarchy.
3. It shows the lock screen. Unlock it with the password or PIN you chose.

Leave the phone connected and alone until the lock screen appears.

## 5. Connect to the phone over USB

The next two steps run from your computer and reach the phone over the USB cable, as a small network: the phone is `172.16.42.1`, and your computer needs the address `172.16.42.2`. With NetworkManager (Omarchy and most desktops use it), add a connection for the phone's USB network once:

```sh
nmcli connection add type ethernet con-name omamobile-phone match.driver cdc_ncm \
  ipv4.method shared ipv4.addresses 172.16.42.2/24 ipv6.method disabled
```

Then, from the bundle folder, check that you can reach the phone:

```sh
tools/phone-ssh 'uname -r'
```

You should see the phone's kernel version (it contains `omamobile`). If it says it can't connect, unplug the cable, plug it back in, wait ten seconds and try again.

## 6. Back up the phone's radio partitions

Before the phone ever starts its modem, make a copy of the partitions that hold its radio calibration and identity (including the IMEI), and keep it. Nothing Omarchy Mobile does writes these partitions (they're read-only while it runs), but stock Android writes some of them, and this copy is what tells the phone later that they're still the ones it expects. This step only reads from the phone.

**This backup is private.** It holds your phone's IMEI and serial numbers. Keep it on your own storage (a second copy elsewhere is a good idea), and never post, share or attach it, not even in a bug report.

From the bundle folder, run `tools/nv-backup` with a new folder for the backup:

```sh
B=~/omamobile-backup/nv-backup-$(date +%Y%m%d-%H%M)
bash tools/nv-backup "$B"
```

It first finds the seven partitions (`efs`, `efs_backup`, `modem_userdata`, `persist`, `modem_a`, `modem_b` and `devinfo`) and checks that each one is read-only and unused; if one isn't, it stops before copying anything. Then it copies each one (about 430 MB in all) in small pieces, reading a piece again if the USB connection drops it, reads the whole partition again on the phone and compares, and writes the checksums to `SHA256SUMS`. It never writes anything to the phone. The folder and its files are readable only by you.

You should see `verified against the phone` for each partition, then `Backup done` and a reminder that the backup is private. **If it stops with an error about a partition (not found, writable or mounted), don't work around it: ask in an issue.** If it stops for any other reason (a USB hiccup, a copy that didn't match the phone), it removes what it had copied, so running the same command again is safe: it only ever reads the phone. If that keeps happening, ask. Remember the folder's name (`echo $B` prints it): the next step needs it.

Later, before anything that touches the radio, `bash tools/nv-backup --check "$B"` compares the phone with the backup again, read-only: it prints `SAME` for each partition (`devinfo` may differ: it holds the bootloader's slot flags, which change after a flash, a fallback to slot A or the boot-success mark).

**If the phone ever starts Android again** (on purpose, or because it fell back to slot A), take a new backup into a new folder afterwards, and keep the old one too, because Android rewrites some of these partitions.

## 7. Add your phone's firmware

Now copy the firmware your phone needs out of Google's factory image. `tools/phone-provision` (in the bundle) unpacks the image on your computer and copies only what's needed onto your phone; nothing of Google's goes anywhere else. It also puts the backup's checksums on the phone, and reads the phone's board id on the phone itself (it is never shown or copied off).

The camera's data needs two Python modules. Install them once, in a folder of their own:

```sh
python3 -m venv ~/.cache/omamobile-venv
~/.cache/omamobile-venv/bin/pip install unicorn pyelftools
```

Without them everything else still works, but the cameras won't.

From the bundle folder, do a dry run first (it unpacks nothing and doesn't contact the phone), then the real run. Replace the path with the factory image you downloaded:

```sh
bash tools/phone-provision --dry-run --first-install --nv-backup "$B" ~/Downloads/cheetah-<build>-factory-<id>.zip
bash tools/phone-provision --first-install --nv-backup "$B" ~/Downloads/cheetah-<build>-factory-<id>.zip
```

`--first-install` says there is no earlier Omarchy Mobile system whose data should be put back. `--nv-backup DIR` alone means the same, so the command a bundle up to 2026.11.08 prints still works; those bundles don't know `--first-install`, so leave it out there.

The real run takes several minutes. Each copy to the phone ends with `verified`. If it stops with an error, nothing half-done is left behind: fix the cause and run it again (it's safe to repeat).

Then restart the phone, from the phone's menu or with:

```sh
tools/phone-ssh '(sleep 1; reboot-to omamobile) >/dev/null 2>&1 &'
```

After the restart, Wi-Fi, Bluetooth, sound, haptics, the sensors and the cameras work.

**Fingerprint unlock starts automatically after this restart.** The phone offers "Add a fingerprint" (or find it later in Setup > Security > Fingerprint): touch the sensor under the bright circle until it's done, and the finger unlocks the phone alongside your PIN or password. Its first start writes the phone's secure storage (Trusty's area in the UFS RPMB), the same kind of write Android makes at a factory reset; before that it makes read-only copies of the data it needs from `persist` and the factory calibration (`mfg_data`), which it never writes. If those copies can't be made or later don't match, fingerprint stays off and the PIN unlocks. If fingerprint stops, restart the phone rather than the service. To keep fingerprint off, run `sudo systemctl mask omamobile-fp` before this restart (`disable` isn't enough).

## Getting updates

The phone updates like Omarchy: run `omarchy update` in a terminal, or use the update notice and Update in the phone's menu. It updates Omarchy's packages and Omarchy Mobile's own, including the kernel, from the signed `[omamobile]` repository at `pkgs.omamobile.org`. It refuses to start on a low battery unless the phone is charging. When an update needs a restart, the phone tells you; it never restarts by itself.

There are two channels:

- **stable** (the default for a release install): what has been tested on the Pixel 7 Pro;
- **development:** every day's build, first. For people who build and test.

See which one the phone follows with `omamobile-update check`, and switch with `sudo omamobile-update channel development` (or `stable`).

Use `omarchy update`, never `sudo pacman -Syu`, `omarchy-channel-set` or `omarchy-refresh-pacman` on the phone: those would replace the phone's own settings with a laptop's.

## Going back to Android

Stock Android is still on slot A.

1. Put the phone in Fastboot Mode: hold **Volume Down** and **Power** until "Fastboot Mode" appears (up to about 20 seconds).
2. On your computer:

   ```sh
   fastboot --set-active=a
   fastboot reboot
   ```

3. Android starts into its recovery screen, because its data was erased. Choose "Factory data reset", and Android starts as a new phone. Fingers enrolled on Omarchy Mobile don't carry over: Android's setup asks for fingerprints as usual, and after you come back you enroll them again (reinstalling erases them).

To remove Omarchy Mobile completely, flash Google's factory image for your phone with Google's own tools (the [Android Flash Tool](https://flash.android.com) or the `flash-all.sh` script in the factory image). Don't lock the bootloader afterwards unless you're sure both slots hold Google's images; if in doubt, ask in an issue first.

To come back to Omarchy Mobile later, run the installer again (step 3). Take a new radio backup (step 6) after the first start, because Android rewrote some of those partitions.

## If something goes wrong

- **The phone shows Android's recovery screen with "Try again" and "Factory data reset" while you expected Omarchy Mobile:** choose neither. Hold **Volume Down** and **Power** for about 20 seconds to reach Fastboot Mode, and ask in an issue.
- **A restart seems stuck:** wait a minute; the phone resets itself. If it's still stuck, hold **Power** for about 30 seconds, then press it again.
- **The phone doesn't answer at all:** hold **Volume Down** and **Power** for about 20 seconds to reach Fastboot Mode. From there you can run the installer again, or go back to Android.
- **To ask for help,** [open an issue](https://github.com/derekross/omarchy-mobile/issues) with what you ran and what it printed. Remove serial numbers, your IMEI, your Wi-Fi network's name and MAC addresses before you post, and never attach the radio backup.

The full developer runbook behind this guide, with every check, is [device/cheetah/REINSTALL-RUNBOOK.md](https://github.com/derekross/omarchy-mobile/blob/main/device/cheetah/REINSTALL-RUNBOOK.md).
