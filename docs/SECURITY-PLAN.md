<!-- SPDX-License-Identifier: MIT -->
# Security plan: an encrypted disk and a verified boot chain, with a development mode

Status (2026-11-01): **design only. Nothing here has run on a phone, and no
code, key or partition has changed.** Today the root file system on
`userdata` is plain ext4 and slot B boots unverified, with the bootloader
unlocked (orange state). This plan covers how a release phone gets full-disk
encryption and a locked bootloader with our own key, while development mode
stays as it is. The reference device is the Pixel 7 Pro (`cheetah`). Other
Pixels follow once cheetah has passed, each with its own runbook. Several
steps need exceptions to the safety rules in [AGENTS.md](../AGENTS.md) §1 and
[RELEASES](RELEASES.md) (writing `vbmeta_b` and `avb_custom_key`, running
`fastboot flashing lock`). None of them is approved: they are listed in §7
for the maintainer to decide on.

Facts are marked **[V]** (verified in this repository or on the phone),
**[D]** (stated in public documentation, cited) or **[I]** (inferred, to be
checked on hardware).

## Contents

1. [The model](#1-the-model)
2. [What exists today](#2-what-exists-today)
3. [Facts: Pixel verified boot with a custom key](#3-facts-pixel-verified-boot-with-a-custom-key)
4. [Facts: encrypting the root](#4-facts-encrypting-the-root)
5. [Design](#5-design)
6. [Phases](#6-phases)
7. [Decisions for the maintainer](#7-decisions-for-the-maintainer)
8. [Runbook for the reference phone (later)](#8-runbook-for-the-reference-phone-later)
9. [Risks](#9-risks)
10. [Sources](#10-sources)

## 1. The model

| Mode | Who | Disk | Bootloader | Boot images | How you get there |
| --- | --- | --- | --- | --- | --- |
| **Secure** (release default) | People who flash a release | LUKS2 on `userdata`, unlocked by a PIN or passphrase on the touchscreen at boot | Locked, with Omarchy Mobile's key in `avb_custom_key` (yellow state) | Signed on the build machine and delivered pre-signed by the Updater | The release installer |
| **Development** | Builders and testers | Plain ext4 as today, or LUKS2 if the owner wants it | Unlocked (orange state) | Built anywhere, footers signed with AOSP's public test key as today | `fastboot flashing unlock` (wipes `userdata`), then the development install |
| **Bring your own key** | Builders who want a locked phone with their own builds | LUKS2 | Locked, with the builder's own key in `avb_custom_key` | Signed by the builder | The release installer with the builder's key and images |

Going from development back to secure means reinstalling from a release
bundle. That wipes `userdata`, because locking erases it (§3.4).

What this protects against:

- **A lost or stolen phone, powered off or rebooted:** the data is encrypted
  with a key derived from the owner's PIN or passphrase. An attacker can't
  boot their own kernel to get round the PIN prompt, because the bootloader
  refuses unsigned images when locked. They can't unlock the bootloader
  without wiping `userdata`.
- **Someone with brief physical access (an "evil maid"):** with the
  bootloader unlocked, they could flash an initramfs that records the PIN.
  Locked, they can't. This is why encryption alone isn't enough, and why the
  release initramfs must have no unauthenticated shell (§5.3).

What it doesn't protect against:

- **A phone that is on with the disk unlocked.** The key is in RAM. The lock
  screen, ufw and key-only SSH on `usb0` protect it, as they do today.
- **An offline guess of a short PIN after someone reads the UFS chip
  directly** (chip-off). There is no hardware-backed throttling (§4.3). A
  6-digit PIN slows a thief down; it won't stop a well-equipped attacker. A
  passphrase will.
- **Changes to the root file system's ciphertext.** LUKS gives
  confidentiality, not integrity (no dm-integrity, §4.4). The boot images
  are verified; the root is protected only because an attacker can't read
  it or change it meaningfully without the key.

## 2. What exists today

Checked on `main` at `cf019f84` (2026-11-01) with
`git grep -n -i "luks\|cryptsetup\|dm-crypt\|encrypt"` and by reading the
files below. **[V]**

- **No encryption anywhere in the boot or install path.**
  [`tools/build-rootfs`](../tools/build-rootfs) and
  [`rootfs/build-inside`](../rootfs/build-inside) make a plain ext4 image
  labelled `omamobile-root` (`mkfs.ext4 -L omamobile-root -d`).
  [`tools/install-phone`](../tools/install-phone) writes it to `userdata`
  with `fastboot flash userdata`, after putting `firstboot.conf` into a
  local copy with `debugfs`. [`initramfs/init`](../initramfs/init)
  (`boot_arch`) finds `userdata` by `PARTNAME`, runs `e2fsck`, grows the file
  system (`grow_root`) and mounts it as ext4 directly, then calls
  `switch_root`. The initramfs has no cryptsetup: `bin/omamobile initramfs`
  fetches only Alpine's `dropbear`, `kexec-tools`, `e2fsprogs` and
  `e2fsprogs-extra` (and `i2c-tools` where needed).
  [`packages/omamobile-firstboot`](../packages/omamobile-firstboot) creates
  the user, the password hash, SSH and the lock, and has nothing about disk
  keys.
- **The kernel can't do dm-crypt yet.** In `out-int`'s `.config`
  (`7.3.0-rc6-omamobile-push1-00571-gd40c36abfc0d`): `CONFIG_DM_CRYPT` is not
  set, `CONFIG_BLK_DEV_DM=m`, `CONFIG_CRYPTO_XTS=m`,
  `CONFIG_CRYPTO_USER_API_SKCIPHER` is not set, and
  `CONFIG_CRYPTO_AES_ARM64_CE_BLK=y` (the ARMv8 AES instructions are there).
  `kernel/configs/omamobile.config` enables `CONFIG_BLK_INLINE_ENCRYPTION`
  and `CONFIG_SCSI_UFS_CRYPTO`, but only so the UFS host driver sets the FMP
  descriptor type as stock does. Nothing uses inline encryption.
- **The phone says so itself.** `omamobile-setup-user` hides Omarchy's
  *Style > Unlock* menu ("The phone has no encrypted disk").
- **The only other matches** are unrelated: the VNC mirror's transport
  encryption, the modem's IMSI-encryption message names, Google's encrypted
  Trusty apps, stock Android's own `userdata` encryption (which we never
  read), and coral's note that its root is "unencrypted ext4".

**The boot chain today [V]:** the bootloader is unlocked (BRINGUP-M1 facts
table; `install-phone` refuses a locked one, and its bundle manifest must
say `require_unlocked_bootloader`). `vbmeta_b` is stock's (on the reference
phone it is byte-identical to `vbmeta_a`: CP2A's, chaining `boot` and
`init_boot` at rollback index locations 2 and 4; NOTES 2026-10-30). Because
the unlocked bootloader still refuses a chained partition with no footer at
all, `bin/omamobile images` gives `boot` and `init_boot` hash footers signed
with AOSP's public test key (`testkey_rsa4096.pem`), with stock's rollback
index (`AVB_ROLLBACK_INDEX=1783209600`) and security patch
(device.conf). `vendor_boot`, `vendor_kernel_boot` and `dtbo` are hash
descriptors inside stock's `vbmeta_b`; their hashes don't match our images,
which an unlocked bootloader allows. PR #320 (open) moves image building onto
the phone (`omamobile-boot-update`) and ships the same test key, so
phone-built images match laptop-built ones byte for byte.

## 3. Facts: Pixel verified boot with a custom key

### 3.1 The custom root of trust

- Pixel 2 and later have a virtual partition, `avb_custom_key`. Flashing and
  erasing it work only when unlocked: `avbtool extract_public_key --key
  key.pem --output pkmd.bin`, then `fastboot flash avb_custom_key pkmd.bin`;
  `fastboot erase avb_custom_key` removes it. **[D]** (AVB README, "Device
  Specific Notes")
- "When the custom key is set and the device is in the LOCKED state it will
  boot images signed with both the built-in key as well as the custom key.
  All other security features (including rollback-protection) are in effect,
  e.g. the **only** difference is the root of trust to use." **[D]** (same
  section) So slot A's stock Android, signed by Google, still boots (green)
  and slot B, signed by us, boots too (yellow). One custom key per phone.
- **Yellow state** (`androidboot.verifiedbootstate=yellow`): locked with a
  user-settable root of trust. A yellow screen is shown at every boot with an
  "OS fingerprint", the first eight hex digits of the SHA-256 of the
  libavb public key. It is dismissed after ten seconds; Power pauses it.
  **[D]** (AOSP boot flow) Orange is unlocked, which is what the phone shows
  today.
- The key the bootloader checks is the key that signed the top-level
  `vbmeta` of the slot. Partitions can be signed by other keys through
  *chain partition descriptors*, which name the partition, its rollback
  index location and the public key that must have signed its footer.
  **[D]** (AVB README, "The VBMeta struct"; `avbtool make_vbmeta_image
  --chain_partition part:location:key.bin`)

### 3.2 What the bootloader verifies on slot B

- **Locked, every error is fatal:** only `AVB_SLOT_VERIFY_RESULT_OK` boots;
  a rejected key, a bad hash or a rollback index below the stored one stops
  the boot. Unlocked, these are allowed. **[D]** (AVB README, "Locked and
  Unlocked mode")
- **What slot B needs, then:** a `vbmeta_b` signed by our key, whose
  descriptors cover every partition the bootloader loads for slot B. Ours are
  `boot_b`, `init_boot_b`, `vendor_boot_b`, `vendor_kernel_boot_b` and
  `dtbo_b` **[V]** (`BOOT_IMAGES`). The bootloader may also load `pvmfw_b`
  (stock's `vbmeta` carries a descriptor for it; BRINGUP-M1 lists `pvmfw` as
  an A/B partition) and may expect `vbmeta_system_b`/`vbmeta_vendor_b`
  chains. **[I] Unknown, and the most important open fact:** which
  partitions the Pixel 7 Pro bootloader requests when locked, and what it
  does with a requested partition that no descriptor in our `vbmeta_b`
  covers. It can only be read from a locked boot (H3, §8).
- **Stock's `vbmeta_b` can't stay:** it is signed by Google, and its
  descriptors hold Google's hashes for `vendor_boot`, `vendor_kernel_boot`
  and `dtbo`, which ours don't match. A locked slot B needs our own
  `vbmeta_b`. **Writing `vbmeta_b` is forbidden by AGENTS §1 and RELEASES
  today**, so this needs an explicit, reviewed exception (§7, D2).

### 3.3 Rollback indexes

- `vbmeta` and each chained partition carry a rollback index and a rollback
  index location. The bootloader keeps `stored_rollback_index[n]` and
  refuses metadata whose index is below it. **[D]** (AVB README, "Rollback
  Protection", "Updating Stored Rollback Indexes")
- On A/B devices, the stored indexes "should only be updated from slots that
  are marked as SUCCESSFUL", by the bootloader on the next boot into that
  slot. **[D]** (same) Our `omamobile-boot-success` marks slot B successful
  **[V]**, so after a locked boot of slot B the stored indexes would rise to
  whatever slot B's metadata says.
- **The locations are shared by both slots.** Stock uses location 0 for
  `vbmeta`, 2 for `boot` and 4 for `init_boot` **[V]** (NOTES 2026-10-30),
  and AOSP's example puts `vbmeta_system` on location 1 **[D]**. If slot B's
  metadata stores a value above stock's at a location stock uses, **stock
  Android on slot A stops booting**, and that is our way back. This is the
  same rule device.conf already states for the footers ("A pull request
  never raises them"). So:
  - `vbmeta_b`'s own index (location 0) must equal stock's, never more.
  - Our chained partitions should use locations stock doesn't use. Which
    locations are free, and how many locations this bootloader stores, is
    **[I]**: read stock's metadata with `avbtool info_image` on the owner's
    own `vbmeta` backup or factory image (read-only, on the laptop; R2).
  - A stored rollback index can't be lowered from Linux. Raising one of ours
    ends rollback to any older image at that location.
- **Lock and unlock clear the stored indexes**, according to the AVB README
  ("all `stored_rollback_index[n]` locations must be cleared ... Similar
  action ... shall also happen when transitioning from UNLOCKED to LOCKED").
  **[D]** Whether the Pixel 7 Pro does this is **[I]**.

### 3.4 Locking, unlocking and wiping

- **Unlock wipes `userdata`:** "the device should perform a factory data
  reset" **[D]** (AOSP locking/unlocking), and "All user data must be cleared
  when transitioning from the LOCKED to the UNLOCKED state" **[D]** (AVB
  README). This is what keeps a stolen locked phone's data safe from a
  reflash.
- **Lock wipes too:** the AVB README says the same clearing "shall also
  happen when transitioning from UNLOCKED to LOCKED" **[D]**. That the Pixel
  7 Pro erases `userdata` on `fastboot flashing lock` is **[I]**, expected.
  **Consequence for the installer:** the root can't be flashed before locking
  (it would be erased) and can't be flashed after (a locked bootloader
  refuses `fastboot flash`, §3.5). The root must be written by our own
  initramfs after the lock (§5.4).
- **Unlocking needs `get_unlock_ability` = 1**, which is Android's "OEM
  unlocking" switch in Developer options, and it "persists across reboots and
  factory data resets" **[D]**. Read with `fastboot flashing
  get_unlock_ability`. If it reads 0 on a locked phone, only stock Android
  on slot A can turn it back on. The installer must refuse to lock unless it
  reads 1.
- **State changes need the owner at the phone:** the bootloader asks for
  confirmation on the buttons. **[D]** (AVB README) A lock can't be scripted
  without a person, which is right.

### 3.5 What a locked phone does with a bad image

- **It refuses to boot it.** Locked, a bad signature or hash is fatal (§3.2).
  The AOSP boot flow shows a red "no valid OS found" screen when nothing
  bootable is left. **[D]**
- **It can't be flashed:** locked, "users can't flash the bootloader or
  device partitions". **[D]** (AOSP locking/unlocking) Fastboot itself stays
  reachable (Volume Down + Power), and so do `flashing unlock` and, **[I]**,
  `--set-active`.
- **Slot fallback still works [I]:** if slot B is not marked successful and
  its tries run out, the bootloader boots slot A. Stock, signed by Google,
  boots green, finds a `userdata` it can't read and offers recovery's "Try
  again" or "Factory data reset" (NOTES 2026-10-30; choose neither). It also
  rewrites `efs`, `persist` and `modem_userdata` (AGENTS §1: take a fresh
  backup after any stock boot).
- **Once slot B is marked successful, the bootloader no longer falls back**
  (AGENTS §4, Pixel 9a entry: "a broken pushed image means fastboot by the
  buttons"). On a locked phone, fastboot can't repair slot B.
- **So the way out of a broken signed image on a locked phone is
  `fastboot flashing unlock`, which wipes `userdata`**, then a reinstall.
  Every image the release process signs must be one the reference phone has
  booted locked, and the phone must check signatures before writing (§5.5).

## 4. Facts: encrypting the root

### 4.1 LUKS2 with cryptsetup

- cryptsetup's compiled-in defaults (Arch's build, `cryptsetup --help` on
  the laptop) **[V]**: LUKS2, `aes-xts-plain64` with a 512-bit key, PBKDF
  `argon2id`, an iteration time of 2000 ms, 1 GiB memory, 4 threads.
- `--pbkdf-memory` is a maximum: "PBKDF benchmark or available physical
  memory can decrease it". Benchmarked values stay between 64 MiB and 1 GiB;
  up to 4 GiB only by setting it. `--pbkdf-parallel` is at most 4. **[D]**
  (cryptsetup-luksFormat(8))
- Each keyslot benchmarks its cost **on the phone that makes it**. A slot
  made on the laptop and opened on the phone takes as long as the laptop
  needed times the speed ratio, so keyslots are made on the phone (§5.4).

### 4.2 The phone's CPU

- AES-XTS runs on the ARMv8 Crypto Extensions (`CRYPTO_AES_ARM64_CE_BLK=y`)
  **[V]**. On the big cores that is expected to be well above UFS speed
  **[I]**: `cryptsetup benchmark` in the initramfs (E0) gives the number.
- Argon2id with 1 GiB and 4 threads, at 2 s on the phone, is the starting
  point; the phone has 12 GB of RAM **[I]** (stock's spec). The cost is a
  decision (D5): more memory slows an attacker's offline guessing more than
  more time does.

### 4.3 No sealed key: the PIN is the key

- Android protects a short screen-lock PIN with hardware that throttles
  guesses (the TEE and the security chip). We don't use them: the Trusty and
  security-chip interfaces for that are Google's, and binding a disk key to
  them is research for later (§6, S9). **The PIN or passphrase alone is the
  key material**, stretched by Argon2id.
- What that means, plainly: 10^6 six-digit PINs at about 2 s each is about 23
  days on one phone, but an attacker with the chip contents runs many
  guesses in parallel on bigger machines. A 6-digit PIN protects against
  casual theft; a passphrase of four or more random words protects against
  an offline attack. The installer says so and offers both (D4).
- The disk PIN and the lock-screen PIN don't have to be the same. Making them
  the same is convenient and is what Omarchy laptops do with one user
  password. If they are the same, the lock screen's password hash (in
  `/etc/shadow`, inside the encrypted root) is no extra exposure, since it
  is readable only after unlock.

### 4.4 Integrity

- dm-crypt with XTS is not authenticated: a changed ciphertext block
  decrypts to garbage, undetected. LUKS2 can add dm-integrity
  (`--integrity`), at a cost in space and write speed and with a full
  initial wipe. Not planned for the first version (D6).

### 4.5 Input in the initramfs

- The touchscreen driver is built in (`CONFIG_TOUCHSCREEN_SYNAPTICS_TCM_SPI=y`,
  "Built in, as the Arch root has no modules for this kernel"), and so are
  `CONFIG_INPUT_EVDEV` and `CONFIG_KEYBOARD_GPIO` **[V]** (`out-int`).
  So `/dev/input/event*` for touch and the keys should exist in the
  initramfs **[I]** (H5: check with `omamobile.initramfs`).
- The display in the initramfs is ABL's framebuffer through simplefb
  (`/dev/fb0`), kept refreshing by the `SIMPLEFB_TRIG_CON` write; the splash
  is drawn there today with `zcat > /dev/fb0` **[V]** (`initramfs/init`).
  There's no on-screen keyboard, and Plymouth's password prompt expects a
  keyboard, so the PIN pad is our own (§5.3).
- The USB safety net in the initramfs crashes the phone after 45 s without
  a configured USB host, unless `switch_root` has happened **[V]**. A PIN
  prompt that waits for a person must disarm it (§5.3).

## 5. Design

### 5.1 Keys

AVB keys are plain RSA keys, with no certification hierarchy of their own.
We get the split the package key has (an offline primary and a subkey on the
build machine, RELEASES §10) from chain descriptors:

| Key | Where it lives | Signs | Trusted through |
| --- | --- | --- | --- |
| **AVB root key** (RSA-4096) | Offline, like the release key's primary: made once on a tmpfs, kept in the password manager | `vbmeta_b` only | `avb_custom_key` on each phone |
| **AVB boot key** (RSA-4096) | The build machine, beside `keys/gnupg.release` | The hash footers of `boot`, `init_boot`, `vendor_boot`, `vendor_kernel_boot`, `dtbo` | The chain descriptors in `vbmeta_b` |
| AOSP test key | Public, in AOSP | Development images, as today | Nothing: unlocked phones accept any key |

The public part of the root key goes in the release bundle as `pkmd.bin`,
and into `omamobile-keyring` (or a small `omamobile-avb-keys` package) with
the boot key's public part, so the phone can check images before writing
them. A `tools/avb-key-init` makes both once, as `tools/release-key-init`
does. Neither secret key ever enters a repository or CI.

### 5.2 `vbmeta_b`: chain everything, write it rarely (design A)

`vbmeta_b` holds five chain descriptors, one per slot-B boot image, each
naming the boot key and a rollback index location of ours. Each image
carries its own hash footer signed by the boot key (what `avb_footers` in
`bin/omamobile` does today with the test key, for two images). Then:

- a kernel update rewrites the boot images only. `vbmeta_b` doesn't change,
  so **the phone never needs to write `vbmeta_b` for an update**;
- `vbmeta_b` is written by the installer through fastboot while the phone is
  still unlocked, and afterwards only to rotate the boot key (D3);
- `vbmeta_b`'s rollback index (location 0) equals stock's, as
  `AVB_ROLLBACK_INDEX` does today;
- `pvmfw_b` and any other partition the bootloader requires are covered as
  H3 finds necessary (D7).

The alternative (design B) keeps `vendor_boot`, `vendor_kernel_boot` and
`dtbo` as hash descriptors inside `vbmeta_b`. That needs no free rollback
locations, but every kernel update then rewrites `vbmeta_b` from the phone,
so `vbmeta_b` would join the storage guard's allowlist, a much larger change
to the safety model. Design A is the recommendation; B is the fallback if
the bootloader has too few free locations (R2).

**Our rollback indexes:** a date, as stock's is (`AVB_ROLLBACK_INDEX` is
2026-07-05 as seconds). Raised only for a security fix that must not be
rolled back, never per release, because raising one ends
`omamobile-boot-update rollback` to older images (D8).

### 5.3 The release initramfs: unlock

The same shared `initramfs/init`, with a release mode (the
`bin/omamobile initramfs --release` of RELEASES §5.2):

1. **Storage guard first, unchanged.** `userdata` stays the only writable
   data partition.
2. **No unauthenticated shell.** The getty on `ttyGS0` runs `/bin/sh` with
   no login, and the `tty1` loop keeps a shell on the screen. On a locked
   phone either one lets a person with a cable record the PIN or write the
   boot partitions. Release builds drop both. Release builds already drop
   developer SSH keys (RELEASES §5.2), and **the per-phone
   `authorized_keys` cpio that RELEASES §5.2 appends on the phone can't be
   used in secure mode**: it changes `init_boot`'s bytes, and the phone
   can't sign. SSH into the initramfs is development-only.
3. **The PIN pad.** A small statically linked program draws a numeric pad
   (and a letter keyboard for a passphrase) on `/dev/fb0` and reads touch
   from evdev, with the Volume keys and Power as a fallback for picking
   digits. It pipes what was typed to `cryptsetup open --key-file=-`, and
   never writes it anywhere else. Its look follows Omarchy's unlock screen
   (the theme's colours and logo, as *Style > Unlock* sets on a laptop), so
   the menu entry `omamobile-setup-user` hides today can come back. Written
   in C against the framebuffer and evdev, with no library beyond libc.
   That keeps it auditable and small enough for the initramfs.
4. **The USB safety net waits.** The no-USB-host crash is disarmed while
   the PIN pad is up, and re-armed only in development builds.
5. **Unlock, then the existing path:** `cryptsetup open` the LUKS2 header on
   `userdata` to `/dev/mapper/root`, then `e2fsck`, `mount` and
   `switch_root` as today. `grow_root` becomes `cryptsetup resize`
   (online) plus `resize2fs` where the root was installed smaller.
6. **Wrong PIN:** a growing delay after five tries, shown on screen. No
   wipe after N tries in the first version (D4).
7. **No LUKS header on `userdata`:** the phone goes to setup mode (§5.4),
   and in a release build only if `userdata` is blank (all zeros or
   discarded in the first megabytes, as after a lock).

Kernel: `CONFIG_DM_CRYPT=y`, `CONFIG_BLK_DEV_DM=y`, `CONFIG_CRYPTO_XTS=y`
and `CONFIG_CRYPTO_USER_API_SKCIPHER=y` in `kernel/configs/omamobile.config`
(built in: the initramfs carries no modules on cheetah). Initramfs: Alpine's
`cryptsetup` and its libraries (argon2, json-c, libdevmapper), fetched by
`bin/omamobile initramfs` as the other packages are.

### 5.4 Installing a secure phone

Because locking erases `userdata` and a locked phone can't be flashed
(§3.4, §3.5), the secure install runs in two halves.

**On the laptop, phone unlocked in fastboot** (`tools/install-phone
--secure`; the bundle's manifest.json states it as data):

1. The existing checks (product, both bootloader slots on the same version,
   image sizes), plus: `fastboot flashing get_unlock_ability` reads 1; the
   bundle carries `pkmd.bin`, a `vbmeta.img` signed by the root key and
   images whose footers `avbtool verify_image` accepts against that
   `vbmeta.img` and the boot key, before anything is written.
2. `fastboot flash avb_custom_key pkmd.bin` (exception, D2).
3. `fastboot flash <image>_b` for each `BOOT_IMAGES` entry, pre-signed from
   the bundle; `fastboot flash vbmeta_b vbmeta.img` (exception, D2).
4. `fastboot --set-active=b`.
5. `fastboot flashing lock`. The owner confirms on the phone; the phone
   wipes `userdata`.
6. The phone boots slot B (yellow screen with our key's fingerprint, which
   the installer prints so the owner can compare).

No `fastboot flash userdata` in secure mode.

**On the phone, in the initramfs's setup mode:**

7. `userdata` is blank, so setup mode starts. The PIN pad asks the owner to
   choose the disk PIN or passphrase, twice. It never crosses the cable.
8. `cryptsetup luksFormat --type luks2` on `userdata` (keyslot cost
   benchmarked on the phone, D5), `cryptsetup open`.
9. The installer, waiting on the laptop, streams the root image over the
   USB network into setup mode. Setup mode accepts a connection only on
   `usb0`, only in setup mode, and only while `userdata` is the volume it
   just made. **It writes the stream only if its SHA-256 equals the root
   image digest built into the initramfs**: the release's `init_boot`
   carries the digest of the release's root image, and `init_boot` is
   verified by the bootloader, so the chain of trust reaches the first root
   without GnuPG in the initramfs. That means the release pipeline builds the
   root image before the initramfs (RELEASES §11 order changes).
10. The installer then sends `firstboot.conf` and the owner's SSH key, which
    setup mode writes into the new root, as `debugfs` does today in the
    image copy.
11. `switch_root`; `omamobile-firstboot` runs as today.

Nothing here touches any partition but slot B's boot images, `vbmeta_b`,
`avb_custom_key` and `userdata`.

**A development install** stays as it is (`fastboot flash userdata`, plain
ext4). `install-phone --encrypt` without `--secure` can use the same setup
mode on an unlocked phone, with the test key, which is how §6 tests
encryption before any lock.

### 5.5 Updates on a secure phone (the Updater, PR #320)

PR #320's `omamobile-boot-update` builds the images on the phone and signs
the footers with the public test key. On a locked phone that would make
slot B unbootable at the next boot. In secure mode:

- **Images are built and signed on the build machine**, in the release
  pipeline, from the same `linux-omamobile` and the device's boot files, and
  shipped pre-signed in a package (`omamobile-boot-images-<codename>`, one
  per device and kernel release; signed by the release key like every
  package).
- **The phone checks before it writes:** `omamobile-boot-update` runs
  `avbtool verify_image` on each image against the boot key in
  `omamobile-keyring` (or `omamobile-avb-keys`), checks each image's
  rollback index against the one in the phone's `vbmeta_b`'s chain
  (read from the partition, read-only), and refuses if any image fails.
  Then the existing guarded write (by `PARTNAME`, `ro` 0, `dd conv=fsync`,
  read-back checksum) and saved previous images.
- **It knows the mode.** The bootloader passes
  `androidboot.verifiedbootstate` (green, yellow, orange) in the boot
  configuration **[I]** (read `/proc/bootconfig` on the phone, R3). When it
  says yellow, `omamobile-boot-update` refuses images it built itself or any
  image not signed by the boot key; when orange, today's behaviour.
- **Development phones are unchanged:** orange, phone-built images, the test
  key, `bin/omamobile push`.
- **Bring your own key:** the builder's own `omamobile-boot-images` package,
  their own boot key's public part in `/etc/omamobile/avb/` (installed by
  their installer), and their own `[omamobile]` mirror or local repository
  (RELEASES §10's contributor builds). The release packages then refuse to
  install their images on that phone, because the key doesn't match.
- **Rollback** (`omamobile-boot-update rollback`) keeps working while the
  previous images' rollback indexes are still at or above the stored ones,
  which holds while we don't raise them (§5.2).

### 5.6 What changes for the owner

- At boot: the yellow screen for ten seconds (Power pauses it), then the PIN
  pad, then the session logs in on its own and locks, as now. That matches
  an Omarchy laptop: one unlock at boot.
- Fingerprint enrollment probably has to be redone after the switch to a
  locked bootloader **[I]**: Trusty's keys can depend on the verified boot
  state, and locking erases `userdata`. The AoC also starts through Trusty
  (AGENTS §4); a locked yellow boot is untested for Trusty, the GSA and the
  AoC (H6).
- Stock Android on slot A stays the way back, but booting it on a locked
  phone with our encrypted `userdata` leads to its recovery screen; don't
  choose either option there (AGENTS §4).

## 6. Phases

Each phase is offline work first, then gated runbook steps (§8). Effort is a
guess for one developer.

| Phase | What | Risk | Effort |
| --- | --- | --- | --- |
| **S0** | This plan; the maintainer's decisions (§7); amendments to AGENTS §1, RELEASES §1 and §6 and CONTRIBUTING §3 for the exceptions that are approved, each named and narrow | none | 1 day |
| **S1** | Read-only facts: stock's rollback locations and descriptors (`avbtool info_image` on the owner's backup), `get_unlock_ability`, `/proc/bootconfig`, touch in the initramfs, `cryptsetup benchmark` (R1-R5) | low | 1 day |
| **S2** | Kernel options (§5.3), cryptsetup in the initramfs, the PIN pad program with tests on a framebuffer file and recorded evdev input | low (offline); medium on the phone (new initramfs, test boot with `push`) | 1-2 weeks |
| **S3** | Encryption in development mode: setup mode, `install-phone --encrypt`, `grow_root` for LUKS, firstboot unchanged. Tested on an unlocked phone (E1-E3) | medium: a reinstall of `userdata` | 1 week |
| **S4** | Release signing: `tools/avb-key-init`, design A's `vbmeta.img` and footers signed by the two keys in `bin/omamobile images --release`, `avbtool verify_image` in `tests/` against throwaway keys | none (no phone) | 3-5 days |
| **S5** | The Updater in secure mode: pre-signed `omamobile-boot-images-<codename>`, the verify-before-write step and the mode check in `omamobile-boot-update` (after PR #320), fake-root tests that a test-key image is refused when yellow | low (offline) | 1 week |
| **S6** | `install-phone --secure` and the bundle: `pkmd.bin`, `vbmeta.img`, the lock step, setup mode's stream with the built-in root digest, manifest.json fields | low offline | 1 week |
| **S7** | First locked boot, on a spare Pixel 7 Pro if one can be had (L1-L6) | **high**: a wipe, `vbmeta_b` and `avb_custom_key` written, lock, possible stock fallback | 2-3 days attended |
| **S8** | Documentation: secure, development and bring-your-own-key modes in CONTRIBUTING and the release README; the release gate (RELEASES §11) gains "the release images booted locked on the reference phone" | none | 2 days |
| **S9** (later) | Research: binding the disk key to hardware (Trusty KeyMint or the security chip's throttling), dm-integrity, inline encryption through the UFS controller, other Pixels | none until a plan | - |

S2-S3 give encryption on development phones without any bootloader change
and can ship on their own. S4-S7 are the verified boot chain.

## 7. Decisions for the maintainer

- **D1. Ship order.** Encryption first (S2-S3, development mode included),
  verified boot after it (S4-S7); or both together for the first secure
  release. Recommended: encryption first.
- **D2. Exceptions to the safety rules.** The secure install needs three
  writes the rules forbid today: `fastboot flash avb_custom_key`,
  `fastboot flash vbmeta_b` and `fastboot flashing lock`, all from
  `tools/install-phone --secure` only, with the phone unlocked, the codename
  typed, a dry run first, and nothing on slot A. Approve, narrow or refuse
  each. Writing `vbmeta_b` from the phone (design B, or key rotation in D3)
  is a separate decision.
- **D3. Key layout.** The two keys of §5.1 (offline root, boot key on the
  build machine), or a single offline key that signs every release by hand.
  With design A, a leaked boot key can't be revoked without rewriting
  `vbmeta_b` on every phone. Choose one: rotation by reinstall only, or let
  the phone write `vbmeta_b` when the new image is signed by the root key
  (an allowlist change).
- **D4. PIN or passphrase.** A 6-digit PIN by default (convenient, weak
  offline), a passphrase by default, or the owner's choice with the
  trade-off shown at install. Same as the lock-screen PIN or separate. Wipe
  after N wrong tries: no (recommended for the first version, since a wipe
  can't be undone).
- **D5. Argon2id cost.** Proposed: 1 GiB, 4 threads, 2 s measured on the
  phone in setup mode. More memory (2-4 GiB) costs boot time and RAM for a
  moment and slows offline guessing more.
- **D6. dm-integrity.** Not in the first version (recommended), or LUKS2
  with `--integrity` from the start.
- **D7. Partitions outside our five.** If H3 shows the bootloader needs
  `pvmfw_b` or `vbmeta_system_b` covered, how: a hash descriptor computed
  from the factory image's `pvmfw` for the pinned stock build (metadata
  only, no Google file in the bundle), or something else.
- **D8. Rollback indexes of our own.** Raise them only for security fixes
  (recommended), every release, or never.
- **D9. Test phone.** S7 on the reference phone (its Linux root is erased by
  the lock; it needs a full backup and a reinstall; stock boots are likely)
  or on a spare Pixel 7 Pro first. Recommended: a spare.
- **D10. Development mode encryption.** Offered by `install-phone
  --encrypt` (recommended), or plain ext4 only.

## 8. Runbook for the reference phone (later)

Read-only steps first. Each step: commands, **Expect**, **Pass**, **Stop**,
**Rollback**, risk. None of these is to run before S0's decisions and the
code of the matching phase. Before any step that may boot stock (L3-L6),
check the off-repo backup of `efs`, `efs_backup`, `modem_userdata`,
`persist` and `modem_a/b` (MODEM-PLAN M0.1), and take a fresh one after.

### R: read-only

- **R1. Unlock ability** (fastboot, low). `fastboot flashing
  get_unlock_ability`. **Expect:** 1. **Pass:** 1. **Stop:** 0: no lock may
  ever be tried on this phone until stock turns OEM unlocking on.
  **Rollback:** none needed.
- **R2. Stock's AVB layout** (laptop only, none). `avbtool info_image
  --image <owner's vbmeta backup>`, and the same for the factory image's
  `vbmeta`, `boot`, `init_boot`, `vendor_boot`, `vendor_kernel_boot`,
  `dtbo`, `pvmfw`, `vbmeta_system`, `vbmeta_vendor`. **Expect:** every
  descriptor, chain and rollback location stock uses. **Pass:** the list of
  used locations, recorded here (no hashes or identifiers). **Stop:** fewer
  than five unused locations below 32: design B (D2). **Rollback:** none.
- **R3. Boot configuration** (SSH, low). `cat /proc/bootconfig; tr ' '
  '\n' < /proc/cmdline | grep androidboot`. **Expect:**
  `androidboot.verifiedbootstate = "orange"` and the vbmeta digest fields.
  **Pass:** the mode can be read from Linux. **Stop:** no boot state passed:
  §5.5's mode check needs another source. **Rollback:** none.
- **R4. Input in the initramfs** (one boot with `omamobile.initramfs` in
  the bootargs through `push`, low). Over SSH: `cat
  /proc/bus/input/devices`, then a few touches with `hexdump -C
  /dev/input/eventN | head`. **Expect:** the Synaptics touchscreen and
  `gpio-keys` listed, events on touch. **Pass:** both. **Stop:** no touch
  device: the PIN pad needs the keys only, or touch in the initramfs needs
  work first. **Rollback:** `bin/omamobile push` of the previous images
  (reboot).
- **R5. Crypto speed** (initramfs or Linux, low, after S2's kernel).
  `cryptsetup benchmark`. **Expect:** aes-xts at several hundred MB/s or
  more, an argon2id figure for 1 GiB. **Pass:** recorded. **Stop:** none.
  **Rollback:** none.

### E: encryption on an unlocked phone (S3)

- **E1. Setup mode on a scratch install** (medium). Full read-only backup of
  the Linux root first (`rsync` to the laptop). Then `tools/install-phone
  --encrypt --dry-run`, then for real. **Expect:** the PIN pad asks for a
  new PIN twice, the root streams in, firstboot runs, the session comes up.
  **Pass:** `lsblk -f` shows `crypto_LUKS` on `userdata` and ext4 on
  `/dev/mapper/root`; `cryptsetup luksDump` shows argon2id with the cost of
  D5. **Stop:** setup mode never appears, or the stream is refused for its
  digest. **Rollback:** a development install (`tools/install-phone`), then
  restore the root backup.
- **E2. Unlock at boot** (low). Reboot, type the PIN. Also: a wrong PIN
  five times, then the right one. **Expect:** the pad on the boot splash,
  the delay after five tries, then the session. **Pass:** unlock in under
  about 4 s after the last digit; the USB safety net doesn't fire while the
  pad waits. **Stop:** a panic or reboot at the pad. **Rollback:** as E1.
- **E3. No plaintext leftovers** (low). `strings` over the first and last
  megabytes of the raw `userdata` from the initramfs shell
  (development build). **Expect:** only the LUKS2 header text. **Pass:** no
  file contents. **Stop:** anything else: the stream wrote outside the
  mapping. **Rollback:** as E1.

### L: the verified boot chain (S7; exceptions D2 approved first)

- **L1. Set the custom key** (unlocked, medium). `fastboot flash
  avb_custom_key pkmd.bin` (a throwaway test root key for this run, not the
  release key). **Expect:** OKAY. **Pass:** the phone still boots slot B
  (orange). **Stop:** an error. **Rollback:** `fastboot erase
  avb_custom_key`.
- **L2. Our `vbmeta_b` and signed images, still unlocked** (medium).
  `fastboot flash vbmeta_b`, then `bin/omamobile flash` of design A's
  images. **Expect:** orange, boots as before. **Pass:** boots;
  `avbtool verify_image` on the laptop passes for the same files.
  **Stop:** no boot: the layout is wrong even unlocked. **Rollback:** flash
  stock's `vbmeta_b` from the owner's backup (another named exception) and
  the previous images.
- **L3. Lock** (**high**). Fresh backups (root, modem partitions). Slot B
  unmarked, so a failed boot falls back to slot A. `fastboot flashing lock`;
  confirm on the phone. **Expect:** `userdata` wiped, a yellow screen with
  the test key's fingerprint, setup mode. **Pass:** setup mode up; R3 reads
  `yellow`. **Stop:** red screen, a stop in fastboot, or stock boots (the
  tries ran out): record the bootloader's message, choose nothing on stock's
  recovery, Volume Down + Power for fastboot. **Rollback:** `fastboot
  flashing unlock` (wipes `userdata`), `fastboot erase avb_custom_key`,
  stock's `vbmeta_b`, a development reinstall, the root backup.
- **L4. Install and live locked** (high). Setup mode as E1, then a day of
  use: Wi-Fi, the AoC and sensors, fingerprint enrollment, the modem
  without a SIM, suspend. **Pass:** every `tools/phone-smoke` check as on an
  unlocked phone. **Stop:** Trusty, the GSA or the AoC fail only when
  locked (H6). **Rollback:** as L3.
- **L5. An update** (high). One `omamobile-boot-images` update through
  `omarchy update`, reboot. Also, first, the same command with a test-key
  image, which must be refused. **Pass:** the refusal before any write, then
  the signed update boots yellow. **Stop:** any write of a refused image.
  **Rollback:** `omamobile-boot-update rollback`; if slot B doesn't boot,
  as L3.
- **L6. Back to development** (high). `fastboot flashing unlock`.
  **Expect:** the wipe, orange. **Pass:** a development install works.
  **Rollback:** none needed.

Hardware questions this runbook answers: **H1** does lock wipe `userdata`
(L3); **H2** are stored rollback indexes cleared on lock and unlock (L3,
L6, by R2's values); **H3** which partitions the locked bootloader requires
(L3); **H4** does `--set-active` work locked; **H5** touch in the initramfs
(R4); **H6** Trusty, the GSA and the AoC in yellow state (L4).

## 9. Risks

- **A locked phone with a broken signed image can only be repaired by
  unlocking, which wipes `userdata`** (§3.5). Mitigations: images are
  verified on the phone before writing; the release gate requires a locked
  boot of the exact images on the reference phone; kernel updates stay
  rare; the owner keeps a backup. Slot A's stock Android is a way to a
  working phone, not to the data.
- **The first locked boot depends on facts we can't read unlocked** (H3).
  If `vbmeta_b` lacks a descriptor the bootloader needs, the boot fails and
  the phone falls back to stock (if B is unmarked) or stops in fastboot.
  Mitigation: L3 with B unmarked, on a spare phone (D9).
- **Rollback indexes can lock stock out of slot A** if any of ours lands at
  a location stock uses with a higher value (§3.3). Mitigation: R2 first;
  `vbmeta_b` at stock's index; our partitions at unused locations; tests
  that refuse a stock-used location in the build.
- **OEM unlocking switched off by stock** while the phone is locked leaves
  no unlock until stock turns it back on, and booting stock means its
  recovery screen. Mitigation: R1 before any lock, and the installer refuses
  to lock without it.
- **Exceptions to the safety model** (`vbmeta_b`, `avb_custom_key`, lock).
  Each widens what a bug in the installer can do. Mitigation: named,
  narrow, installer-only, dry run first, the codename typed, tested on a
  fake fastboot in `tests/install-phone`.
- **A weak PIN** gives weak protection against an offline attack (§4.3).
  Mitigation: the installer explains it and offers a passphrase.
- **The initramfs shells** become a hole on a locked phone if a release
  build keeps them (§5.3). Mitigation: `tools/make-bundle` refuses an
  initramfs with a getty shell, a `tty1` shell or SSH keys, as it already
  refuses SSH keys.
- **Fingerprint, Trusty and the AoC** may behave differently locked (H6);
  the fingerprint state is lost with the wipe. Mitigation: L4 before any
  release depends on it.
- **A forgotten PIN means the data is gone.** No recovery key in the first
  version (a second LUKS keyslot with a printed recovery key is a small
  addition if wanted).

## 10. Sources

- AOSP, *Android Verified Boot 2.0* README, `platform/external/avb`
  (Apache-2.0): "The VBMeta struct", "Rollback Protection", "Locked and
  Unlocked mode", "Updating Stored Rollback Indexes", "Device Specific Notes
  / Pixel 2 and later".
  <https://android.googlesource.com/platform/external/avb/+/refs/heads/main/README.md>
- Android Open Source Project, *Boot flow* (verified boot states, the yellow
  screen and its OS fingerprint).
  <https://source.android.com/docs/security/features/verifiedboot/boot-flow>
- Android Open Source Project, *Lock and unlock the bootloader*
  (`get_unlock_ability`, the factory reset on unlock, no flashing when
  locked). <https://source.android.com/docs/core/architecture/bootloader/locking_unlocking>
- cryptsetup, *cryptsetup-luksFormat(8)* (PBKDF memory, threads and
  iteration time). <https://man7.org/linux/man-pages/man8/cryptsetup-luksFormat.8.html>
- Our own: [NOTES](../device/cheetah/NOTES.md) 2026-10-30 (stock's
  `vbmeta_b`, rollback locations 2 and 4, footers required);
  [device.conf](../device/cheetah/device.conf) (`AVB_FOOTERS`,
  `AVB_ROLLBACK_INDEX`); [BRINGUP-M1](../device/cheetah/BRINGUP-M1.md)
  (bootloader state, A/B partitions); [RELEASES](RELEASES.md) §5, §6, §10,
  §12; `bin/omamobile` (`avb_footers`); `out-int`'s kernel configuration.
