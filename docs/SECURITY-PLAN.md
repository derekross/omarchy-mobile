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
11. [Proposal: LUKS2 and a touchscreen PIN in the initramfs (OnePlus 7T Pro, community)](#11-proposal-luks2-and-a-touchscreen-pin-in-the-initramfs-oneplus-7t-pro-community)

## 1. The model

| Mode | Who | Disk | Bootloader | Boot images | How you get there |
| --- | --- | --- | --- | --- | --- |
| **Secure** (release default) | People who flash a release | LUKS2 on `userdata`, unlocked by a PIN or passphrase on the touchscreen at boot | Locked, with Omamobile's key in `avb_custom_key` (yellow state) | Signed on the build machine and delivered pre-signed by the Updater | The release installer |
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
- **D9. Test phone.** Decided (2026-11-02): the reference Pixel 7 Pro. It is a
  test phone, not anyone's daily phone, so a wipe from locking or unlocking
  costs a reinstall and nothing more. Before S7: back up the home folder and
  settings, confirm OEM unlocking is on in stock Android, and have a fresh
  install ready. The calibration partitions (`efs`, `persist`, the modem's)
  are untouched by an unlock and stay under AGENTS' rules.
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
  Mitigation: L3 with B unmarked, with the backup and fresh install of D9 ready.
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

## 11. Proposal: LUKS2 and a touchscreen PIN in the initramfs (OnePlus 7T Pro, community)

Status (2026-11-25): **a proposal from the OnePlus 7T Pro port (#931),
for the maintainer to decide on (§11.11).** The code is in this pull
request; it has run on one phone, the port owner's OnePlus 7T Pro
(`hotdog`), whose root has been LUKS2 since 2026-11-19 (§11.9). Nothing
has run on the Pixel 7 Pro or any other phone. Sections 1-10 above are the
maintainer's plan and are unchanged; this section says which parts of them
the proposal implements, which it does differently and which it leaves
out. Ids here carry a P (PD1, PR1, PT1, PM1) so they don't collide with
§7's decisions and §8's steps.

### 11.1 What is proposed, and what exists

An encrypted root for development phones, without any bootloader change:
`userdata` holds a LUKS2 volume with the ext4 root inside, and the
initramfs asks for the owner's PIN on a full-screen pad on the touchscreen
at power-on, opens the volume and boots as today. The same PIN unlocks the
lock screen and sudo. A phone opts in through its descriptor; every other
phone builds and boots exactly as before (§11.3).

What this pull request adds:

| Piece | Where | Tests (no phone) |
| --- | --- | --- |
| The opt-in key | `INITRAMFS_CRYPT=yes` in `device/<codename>/device.conf` ([RELEASES](RELEASES.md) §3.1's table) | `tests/initramfs-root-policy.py` |
| The init's unlock, charging-boot wait, safety-net stop, hold and continue | `initramfs/init` (`charger_boot`, `crypt_open`, `crypt_unlock`, their call in `boot_arch`, PID 1's last loop) | `tests/crypt-unlock.py` (19) |
| The SSH unlock and PT2's self-test | `initramfs/omamobile-unlock` | through `tests/phone-encrypt` |
| The PIN pad | `initramfs/pinpad/pinpad.c`, its glyphs from `initramfs/pinpad/mkfont` | `tests/pinpad.py` (33) |
| The backup's tar digest | `initramfs/tarnorm/tarnorm.c` | `tests/phone-encrypt`, against the tool's Python twin |
| Packing all of it | `bin/omamobile initramfs` | the existing initramfs tests |
| Kernel options | `kernel/configs/omamobile.config` (§11.8) | - |
| Encrypt, decrypt, back up, restore | `tools/phone-encrypt` (`--keep`, `--fresh`, `--decrypt`, `--restore-plain`, `--backup-only`) | `tests/phone-encrypt` (24, a stand-in phone with the real GNU tar) |
| Unlock from the laptop | `tools/phone-unlock` | `tests/phone-encrypt` |
| On the phone: one PIN, and the hold | `packages/omamobile-crypt` 0.1.0 (`omamobile-pin`, `omamobile-encrypt-hold`), built by `tools/build-packages`, not in the root image | its `test/all` (8, a real LUKS2 file) |

Not in this pull request: the shell's skip of the lock right after an
unlocked boot (PD3; the init writes `/run/omamobile/disk-unlocked` for it,
and nothing reads it yet), and the OnePlus 7T Pro's descriptor lines
(`INITRAMFS_CRYPT=yes`, the touchscreen module in `INITRAMFS_MODULES`,
`deferred_probe_timeout=-1`), which go with that phone's own pull request.

### 11.2 How it maps onto this plan

- **§4 facts.** §4.1: keyslots are made on the phone, in the initramfs,
  as §4.1 says, but at a fixed cost rather than a benchmarked one (PD5,
  §11.6). §4.3: the PIN is the only key material, as there; the tool shows
  the numbers below and asks again under 8 digits. §4.4: no dm-integrity.
  §4.5: touch and keys in the initramfs, read again every 2 s so a late
  touch driver counts (on hotdog the driver is a module, §11.9), and the USB
  safety net stands down while the pad is up.
- **§5.3, the release initramfs's unlock.** Item 1: the storage guard runs
  first and is unchanged; `/dev/mapper/root` is not an `sd*` device, so
  `userdata` stays the only writable partition. Item 3: the PIN pad, C
  against fbdev and evdev with libc only, the volume keys and Power as the
  fallback, the PIN only on `cryptsetup`'s stdin; digits only, no letter
  keyboard yet (PD7), the theme's colours but no logo. Item 4: the safety
  net stands down while the pad is up and is not armed again. Item 5:
  `cryptsetup open`, then the existing label check, `e2fsck`, `grow_root`
  (`resize2fs` on the mapping: the volume already spans the partition, so
  no `cryptsetup resize`), mount and `switch_root`. Item 6: a growing delay
  from the sixth wrong PIN, no wipe. **Not done:** item 2 (the shells and
  SSH stay, so this is not a release initramfs for a locked phone) and item
  7 (no setup mode: a plain ext4 `userdata` boots as today). The kernel
  options of §5.3's last paragraph are in, plus `CRYPTO_USER_API_HASH`.
- **§5.4, installing.** Not done as designed. Instead of setup mode with
  the PIN chosen on the pad and a root stream checked against a digest in
  the verified `init_boot`, `tools/phone-encrypt --fresh` formats
  `userdata` from a held initramfs over development SSH, with the PIN typed
  on the laptop, and writes an already prepared root image into the
  volume, its SHA-256 checked on both ends. `--keep` does the same for a
  phone that already runs Omamobile, keeping its data (§11.6). The PIN
  crosses the cable here, which §5.4 step 7 avoids (PD12).
- **§6 phases.** S2 (kernel options, cryptsetup in the initramfs, the pad
  with tests against a framebuffer file and scripted evdev input) and the
  development half of S3 (encryption on an unlocked phone; `grow_root` for
  LUKS), in the shape above rather than through `install-phone --encrypt`.
  Nothing of S4-S9.
- **§7 decisions it assumes.** D1: encryption first. D4: digits, at least
  6, the same PIN as the lock screen and sudo, no wipe. D5: changed, a fixed
  cost (PD5). D6: no integrity. D10: development-mode encryption offered,
  here by `tools/phone-encrypt`. §9's last risk: a recovery key is always
  made (PD10).
- **§8 runbook.** Parts of R4 (input in the initramfs), R5 (crypto speed)
  and E2 (unlock at boot) ran on hotdog (§11.9). None of the L steps.

What it does **not** do: verify the boot chain or lock the bootloader
(§3, §5.1, §5.2, §5.5), so someone who has the phone, changes its boot
image and gives it back can record the PIN; bind the key to hardware (S9);
add dm-integrity; take a passphrase on the pad.

### 11.3 What changes for phones that don't opt in

- **At boot: nothing.** Without `INITRAMFS_CRYPT=yes`, `bin/omamobile
  initramfs` packs what it packed before (the same Alpine packages, no
  `cryptsetup`, no GNU `tar`, no pad, no `/etc/omamobile-crypt`); only
  `/init`'s text differs. Every new path in the init is behind
  `[ -e /etc/omamobile-crypt ]`: no features file, no `cryptsetup isLuks`
  (a LUKS `userdata` is mounted as ext4 and fails there, as it always
  did), no hold, the USB safety net's `sleep 20` as it was, and PID 1 keeps
  the shell on `tty1` in its own loop, as before. `tests/crypt-unlock.py`
  and `tests/initramfs-root-policy.py` check each of these, and that no
  shipped descriptor sets the key.
- **The kernel: five options in the shared fragment**, so every phone's
  release kernel gets them (§11.8). They add code to the kernel image and
  `/dev/mapper/control`, and set up nothing by themselves.
- **The package repository** gains `omamobile-crypt`, installed by nobody
  until an owner asks for it.

The contributor's first version packed all of this into every initramfs
and let the LUKS header alone decide; the descriptor key is new in this
pull request, so a port opts in on purpose and the other phones' initramfs
stay as they are.

### 11.4 Booting (`initramfs/init`)

The change sits in `boot_arch`, between finding `userdata` and the label
check:

1. Find `userdata`, as today.
2. `/etc/omamobile-crypt` and `cryptsetup isLuks`? If not: the plain path,
   unchanged.
3. **Charging boot** (`androidboot.mode = "charger"` in `/proc/bootconfig`
   or on the command line): no pad. The screen stays dark; Power held
   restarts into a normal boot, the cable out powers off (PD8). The wait
   stands the USB safety net down, since a wall charger is no USB host.
4. **Unlock.** Two ways race, and the first to open the volume wins: the
   pad (§11.5) and `omamobile-unlock` over SSH (development builds, which
   carry the developer's key; `tools/phone-unlock` calls it). Both pipe the
   PIN to `cryptsetup open … root --key-file=-`. A pad that stops is
   started again, at most five times; one that finds no display (exit 5)
   leaves the SSH unlock.
5. **While waiting:** the pad writes `/run/omamobile-pinpad`, and the
   safety net exits when it sees it. After 60 s with no input the pad
   blanks the screen; ten minutes with no input power the phone off
   (`reboot(2)`'s power-off, not busybox `poweroff`, AGENTS §4).
6. **Opened:** `dev=/dev/mapper/root`, and the existing path runs on it.
   `/run/omamobile/disk-unlocked` is written for the session (PD3).
7. **Shutdown:** nothing new; the mapping stays open until power-off.

Also behind the marker: `/run/omamobile/initramfs-features` says
`crypt hold`, which `omamobile-encrypt-hold` requires (§11.6), and PID 1
waits for `/run/omamobile-continue` to try the root again, even with
`omamobile.initramfs` on the command line, so `tools/phone-encrypt` (or a
human over SSH) can hand a held boot back.

### 11.5 The PIN pad (`omamobile-pinpad`)

- **Drawing:** laid out from fb0's own geometry (`FBIOGET_VSCREENINFO`,
  `FBIOGET_FSCREENINFO`; 16, 24 or 32 bits per pixel), round keys in the
  theme's colours, antialiased, a row of dots, a title and one message
  line. Glyphs come from `mkfont`, rendered at build time with ImageMagick
  at the panel's width (`PINPAD_FONT`, default the build machine's sans);
  without them the pad draws built-in capitals. While it is up the console
  is in `KD_GRAPHICS`, so kernel messages don't draw over it (PT2).
- **Touch:** multi-touch protocol A and B and single-touch, from every
  evdev device with positions, looked for again every 2 s; coordinates
  scaled from the device's ranges; a key fires on release inside its cell.
  `PINPAD_TOUCH_SWAP=x|y|xy` for a mirrored panel (none known yet).
- **Keys:** Volume Up and Down move a highlight, Power presses it.
- **The PIN in memory:** one `mlock`ed buffer, wiped after use, at most 64
  digits, written only to `cryptsetup`'s stdin: no log, file or kmsg.
- **Wrong PIN:** "Wrong PIN" and the dots shake; from the sixth, waits of
  5, 10, 20, 40 s up to 5 minutes, counted in RAM.
- **No stdio:** musl's `printf` needs 128-bit float helpers a plain clang
  has no library for on aarch64, so the pad formats its own numbers (289 KB
  static).
- `tests/pinpad.py` runs it against a framebuffer file and scripted evdev
  input with a stand-in `cryptsetup`: the exact bytes that reach it, that
  the trace, stdout and the screen never hold the PIN, delete, the keys
  alone, the back-off, blanking (the waking tap presses nothing), the idle
  power-off, the safety-net marker, no display, both fonts, `KD_GRAPHICS`
  and the charging wait's two exits.

### 11.6 On the disk, and encrypting a phone (`tools/phone-encrypt`)

```
userdata  ── LUKS2 (label omamobile-crypt, 16 MiB header)
             keyslot 0: the owner's PIN    (Argon2id, made on the phone)
             keyslot 1: the recovery key   (Argon2id, made on the phone)
             flags: allow-discards, no read/write workqueue (persistent)
   └─ /dev/mapper/root ── ext4, label omamobile-root (as today)
```

- **Cost (PD5):** `--pbkdf argon2id --pbkdf-memory 1048576
  --pbkdf-parallel 4 --pbkdf-force-iterations 4`, about 2 s on hotdog. Not
  `--iter-time 2000`: cryptsetup benchmarks at format time and cuts the
  memory when the phone runs slow then, and a console stalled by display
  errors gave 64 MiB (PT2). Both keyslots are checked with `luksDump` after
  the format; `omamobile-pin` uses the same cost.
- **The recovery key:** 48 random digits in eight groups of six (159 bits),
  made on the laptop, shown once, confirmed by its last group, typed on the
  same pad; never written to a file by the tools (on the phone it passes
  through `/run`, RAM, for `luksAddKey`, removed at once).
- **What a PIN is worth offline** (§4.3), for an attacker who copied
  `userdata` and tries about 50 guesses a second at 1 GiB each: 6 digits
  about 6 hours, 8 digits about 3 weeks, 10 digits about 6 years, four
  random words far beyond reach. The tool says so and asks again under 8.
- **Holding a boot:** `omamobile-encrypt-hold` on the running phone writes
  `/.omamobile-hold`; at the next boot the init mounts the root, sees the
  marker, deletes it, unmounts and stays in the initramfs. The reboot is
  the human's call. It refuses on a phone whose initramfs lacks
  `crypt hold`, which would ignore the marker and leave it for a later one.
- **`--keep BACKUP_DIR`:** checks (the initramfs has `/etc/omamobile-crypt`,
  the board is `DEVICE`'s, the root is unmounted ext4 labelled
  `omamobile-root` with a clean `e2fsck -f`, room for the backup); the
  phone's clock set from the laptop (hotdog's RTC said 1970); a read-only
  GNU tar backup (`--format=posix --sort=name --xattrs --acls
  --numeric-owner --sparse --one-file-system`) streamed into
  `BACKUP_DIR/root.tar.zst`; a second read on the phone whose SHA-256 must
  equal the received stream and the written file, and the entry count the
  phone's `find`. GNU tar names a sparse file's header after its own PID,
  so `omamobile-tarnorm` (and its Python twin) replace that number before
  hashing; the archive is kept as written. Then the owner types the
  codename and `erase` (the one irreversible step), the PIN twice, the
  format, the recovery key, `mkfs.ext4` inside, the restore, a read-back
  whose digest must be the backup's, `luksHeaderBackup` into `BACKUP_DIR`,
  and the boot handed back to the init, which shows the pad. The backup
  holds the whole unencrypted system; the tool says so and asks for it to
  be deleted once the phone has run well.
- **`--fresh USERDATA.img`:** a root image already prepared for the phone
  (`firstboot.conf` inside); the PIN must match its `PASSWORD_HASH`; the
  image is streamed gzip-compressed into `/dev/mapper/root` with plain `dd`
  (no `conv=sparse`: a skipped block reads back as noise under dm-crypt)
  and its SHA-256 checked on both ends; the first boot grows it.
- **`--decrypt BACKUP_DIR`** is the reverse of `--keep`, and
  **`--restore-plain BACKUP_DIR`** zeroes the LUKS header, makes ext4 and
  restores a backup: the way back.
- **What never changes:** the tool writes `userdata` only, only from the
  initramfs, through the storage guard. It flashes nothing.

### 11.7 Living with it

- `sudo omamobile-pin` asks for the old PIN and the new one twice, changes
  keyslot 0 (`luksChangeKey`), checks that the new PIN opens it, and only
  then the user's password (`chpasswd`). A plain `passwd` leaves the disk
  PIN as it was (PD2). `--recovery-key` makes a new recovery key.
- `tools/phone-unlock` waits for the initramfs's SSH and sends the PIN on
  stdin, asked on the laptop's terminal or from `OMAMOBILE_DISK_PIN_CMD`
  (a password manager's command). The tools never store it, and agents must
  never ask for, read or type it (an AGENTS §1 line, PD11).
- **What it costs:** before the PIN the phone does nothing, so after a
  restart at night no alarm and no call until someone unlocks it; the
  fingerprint can't unlock the disk; every reboot of an encrypted phone
  waits for a human; a forgotten PIN and a lost recovery key mean the data
  is gone.
- **Selling or giving the phone away:** `cryptsetup erase` destroys every
  keyslot; the backups and the header backup must go too.

### 11.8 Kernel and initramfs

`kernel/configs/omamobile.config`, the release kernel's fragment, so it
changes every phone's kernel configuration:

```
CONFIG_BLK_DEV_DM=y
CONFIG_DM_CRYPT=y
CONFIG_CRYPTO_XTS=y
CONFIG_CRYPTO_USER_API_HASH=y
CONFIG_CRYPTO_USER_API_SKCIPHER=y
```

Built in because most phones' initramfs carry no modules. `BLK_DEV_DM` and
`CRYPTO_XTS` were modules from the arm64 defconfig, the rest unset
(`CRYPTO_AES_ARM64_CE_BLK=y` was already in). AF_ALG is what cryptsetup
uses for the LUKS2 keyslot area and its checks. They are inert without an
encrypted root: the kernel sets up no device-mapper target by itself, and
at boot only the `cryptsetup` of an `INITRAMFS_CRYPT` initramfs opens one,
on a LUKS2 `userdata`. A per-device `kernel.config` can't carry them,
since the release kernel is one build for every device (RELEASES §3.1, §4).

`bin/omamobile initramfs`, only with `INITRAMFS_CRYPT=yes`: Alpine's
signed `cryptsetup` and GNU `tar` (the build stops if either is missing;
GNU tar replaces busybox's, because the restore needs xattrs, ACLs and file
capabilities), `omamobile-pinpad` and `omamobile-tarnorm` static against
Alpine's musl like `reboot-to` (the musl sysroot gains Alpine's
`linux-headers` for them), `omamobile-unlock`, `/etc/omamobile-crypt` and
the glyphs. The glyphs come from the build machine's font, as the splash
does from its theme, so two machines give the same initramfs only with the
same `PINPAD_FONT`. Measured for hotdog: `initramfs.cpio.lz4` from 6.7 MB
to 7.5 MB (2026-11-19, a scratch build). On cheetah the initramfs sits in
the 64 MiB `vendor_kernel_boot`; mkbootimg and avbtool already stop on an
image that doesn't fit.

Per device: cheetah's touchscreen is built in; hotdog's (`s6sy761`) is a
module, packed through `INITRAMFS_MODULES` (its I2C, pins and rail are
built in, and it loads no firmware), so a hotdog initramfs needs `omamobile
modules` from the same build first. Hotdog also needs
`deferred_probe_timeout=-1` (§11.9, PM2).

### 11.9 What has run, on which phone

On the port owner's OnePlus 7T Pro, with the contributor's earlier tree,
which packed the crypt pieces into every initramfs. This pull request adds
the `INITRAMFS_CRYPT` gates around the same unlock functions, and the
device-neutral `tests/phone-encrypt`.

- **2026-11-19, PR1** (`7.3.0-rc6-omamobile-push1`): the root on
  `userdata`, ext4, 30.8 GiB used; room on the laptop. Pass.
- **2026-11-19, PR2, partial,** read from the running root: fb0 is
  `msmdrmfb`, 1440x3120, 32 bpp, stride 5760; the power and volume keys and
  `DRM_MSM` built in, `s6sy761` a module; `pm8150b-charger` the power
  supply. From the PT1 boots: on a boot from flash fb0 exists in the
  initramfs (simpledrm's, then `msm`'s); in a RAM boot from the fastboot
  screen there was none about 9 s in, so the pad may find no display there
  and the SSH unlock remains.
- **2026-11-19, PT1** (`7.3.0-rc6-omamobile-crypt1-g7539ca3e06f6`: `boot_a`'s
  tree and config with the options of §11.8): the first RAM boot fell back
  to `boot_a` after about 15 s, no pstore record. A control RAM boot of
  `boot_a`'s own image wedged after the handover the same way (`[dpu
  error]enc34 frame done timeout`), so the wedges are hotdog's RAM-boot
  display problem. The second try passed: `crypt hold`, the root by 13 s,
  `/dev/mapper/control` and `xts(aes)` present, no `disk-unlocked`, the
  touchscreen loaded in the initramfs and working in the session,
  `tools/phone-smoke` as before.
- **2026-11-19, PT2** (RAM boot, `omamobile.initramfs`): first image, the
  pad drew and took touch, but the kernel's `[dpu error]enc35 frame done
  timeout` lines drew over it and stalled the phone, and the self-test
  volume's Argon2id came out at 64 MiB. Fixes: `KD_GRAPHICS` while the pad
  is up, and the fixed cost (PD5). Second image: no display errors, the
  volume at 1 GiB and 4 iterations, a wrong PIN refused, the test PIN
  accepted in about 2 s. PR3 from the same boots: aes-xts 512-bit 1357 MiB/s
  encrypt, 1419 MiB/s decrypt. The back-off, blanking and the 10-minute
  power-off were not run on the phone (`tests/pinpad.py` covers them).
- **2026-11-19, PM2, `--keep`** (the owner: a test phone). `boot_a` flashed
  first with the PT2-fixed image, which cleared slot A's successful mark;
  `omamobile-crypt` 0.1.0 installed. Found on the way: the RTC's 1970 clock
  (the tool now sets the clock and passes `--warning=no-timestamp` to the
  restore); with the cable in, hotdog switches itself on after a power-off
  with `androidboot.mode=normal`, so `charger_boot` never fires there (PD8
  open for it); warm restarts wedged the display, a cold start never did.
  The copy, 13.7 GB compressed, took about 18 minutes; erase, format,
  restore (about 8 MB/s) and the read-back check passed; the pad unlocked;
  Omarchy came up. **One failure, the cameras:** both CCIs failed at 6871 s
  with "deferred probe timeout, ignoring dependency" and -110, because the
  boot had waited hours in the initramfs and the default 10 s timeout fired
  before the root's modules supplied them; a failed probe isn't retried. A
  reprobe brought all four cameras back. Fix on hotdog's command line:
  `deferred_probe_timeout=-1`. No boot from a plain root had a device
  pending at the timeout; cheetah's boots are to be checked before it gets
  the same.
- **2026-11-21, a RAM boot for #931's review** (kernel
  `7.3.0-rc6-omamobile-crypt1-gf3a11a5f5062`, the Image and DTB those of
  `boot_a`, the initramfs from #931's tree plus this unlock): the pad at
  2.5 s, the root open at 23.5 s (the owner's PIN), the switch to Arch at
  23.6 s; `tools/phone-smoke` with no failed units, its two required "not
  ok" being slot A and a root on `/dev/mapper/root`, which the smoke test
  doesn't know yet. The owner then checked on the phone that it boots with
  no cable in ([hotdog BRINGUP-M1](../device/hotdog/BRINGUP-M1.md), in #931).
- **Not run:** PT3 on its own (it ran inside PM2), PM3 and PM4 (recorded
  as a whole), the recovery key at the pad, `omamobile-pin` on the phone,
  a charging boot.

### 11.10 Runbook and rollback

Read-only steps first. Each: **Expect**, **Pass**, **Stop**, **Rollback**,
risk. Every boot, flash and write is the human's call, asked each time
(AGENTS §1); steps that light or blank the screen are announced; on
cheetah, stop the modem before a `push` or `reboot-to` (AGENTS §2).

- **PR1. Room for the backup** (running phone, none): `df` of `/` and of
  the laptop's backup directory. Pass: used space plus 10 % free. Stop:
  not enough room.
- **PR2. What the initramfs sees** (one held boot, low): input devices,
  fb0's geometry, a few touches. Stop: no fb0, so the pad needs a display
  path first. Rollback: a normal reboot.
- **PR3. Crypto speed** (low): `cryptsetup benchmark` in the initramfs.
  Stop: Argon2id at 1 GiB far over 2 s, or failing for memory.
- **PR4. Charging boot** (phone off, a charger, low): what starts, and
  whether it charges without the root's charger driver (PD8).
- **PT1. The new initramfs on the plain root** (medium: a new boot image;
  `push` on cheetah, `fastboot boot` on hotdog). Expect: it boots as
  before, `initramfs-features` reads `crypt hold`. Pass:
  `tools/phone-smoke` as before, no `disk-unlocked`. Stop: any difference.
  Rollback: the previous image.
- **PT2. The pad against a scratch volume** (low, `userdata` not opened):
  held, `omamobile-unlock --selftest` makes a 64 MiB LUKS2 file in `/run`
  with the test PIN `135790`. Pass: wrong PINs refused, the back-off, the
  test PIN opens it in about 2 s, keys alone, blanking, no safety-net crash
  without a cable, the power-off at 10 minutes. Stop: a reset, a crash, or
  touch in the wrong place. Rollback: a reboot.
- **PT3. The backup's digest is stable** (read-only, low): held,
  `tools/phone-encrypt --backup-only BACKUP_DIR`. Stop: the two
  digests differ, so the backup can't be trusted and PM2 doesn't run.
- **PM1. A fresh backup on the day**, as PT3.
- **PM2. Encrypt** (**high**: `userdata` is overwritten; battery above
  50 % or a charger). `tools/phone-encrypt --keep BACKUP_DIR`. Pass: the
  PIN unlocks; `lsblk -f` shows `crypto_LUKS` on `userdata` and ext4 on
  `/dev/mapper/root`; `luksDump` shows two Argon2id keyslots and the
  persistent flags. Stop: any error, then leave the phone in the
  initramfs and change nothing more. Rollback: `tools/phone-encrypt
  --restore-plain BACKUP_DIR`, then a normal boot.
- **PM3. A day of use** (low): calls, texts, Wi-Fi, the modem, cameras,
  sensors, suspend, a `push` and `tools/phone-unlock` round trip. Pass:
  `tools/phone-smoke` as before. Rollback: as PM2.
- **PM4. The edges** (low): five reboots unlocked at the pad, one with the
  recovery key, one with `tools/phone-unlock`, a charging boot,
  `omamobile-pin` to a new PIN and back. Stop: a PIN or key that should
  work doesn't; unlock with the other one and stop.

### 11.11 Open decisions for the maintainer

The code follows the contributor's recommendations so that it had
something to follow; each is one place in the code.

- **PD1. PIN rules.** Digits, at least 6, a warning and a second question
  under 8 (as built); or at least 8; or a passphrase by default.
- **PD2. One PIN for the disk, the lock screen and sudo,** changed together
  by `omamobile-pin` (as built), or a separate disk PIN.
- **PD3. No lock right after an unlocked boot** (one PIN per power-on), or
  keep the lock (two). The init writes the marker either way; the shell's
  side is a separate change.
- **PD4. Wipe after N wrong PINs:** no (as built).
- **PD5. Argon2id cost:** fixed at 1 GiB, 4 threads, 4 iterations (as
  built), or §7 D5's benchmarked 2 s.
- **PD6. Discards** on (as built), or off.
- **PD7. Letters on the pad:** digits first (as built), letters later.
- **PD8. Charging boots:** the dark wait (as built where the bootloader
  says `androidboot.mode=charger`), or the pad. Open for hotdog, which never
  says it.
- **PD9. First phone:** decided 2026-11-19 by its owner, hotdog.
- **PD10. Recovery key:** always (as built), or offered.
- **PD11. Agents and the disk PIN:** an AGENTS §1 line that agents never
  ask for, store or type it, and that a reboot of an encrypted phone waits
  for the human.
- **PD12. The PIN over the cable.** `tools/phone-encrypt` and
  `tools/phone-unlock` take it on the laptop, which §5.4 avoids; keep that
  for development phones only, or move the format into the pad.
- **PD13. Where it is switched on:** per descriptor (`INITRAMFS_CRYPT`, as
  in this pull request), or in every initramfs, as the contributor first
  built it. And whether `--release` may set it while §5.3 item 2 is open.
- **PD14. The kernel options** in the shared fragment (as here), for every
  phone, with the reasons of §11.8.
- **PD15. What follows:** `omamobile-crypt` in the root image,
  `install-phone --encrypt` (or `--fresh` folded into it),
  `tools/phone-smoke` knowing `/dev/mapper/root`, and `omamobile-setup-user`
  showing *Style > Unlock* again on an encrypted phone.

### 11.12 Risks

- **Losing the data during `--keep`.** The format erases the only copy on
  the phone. Mitigations: two backup reads that must agree before the
  format, the typed confirmation, the read-back check, and
  `--restore-plain` as a tested way back.
- **A phone that can't be unlocked** (a pad bug, no touch, no display):
  the volume keys and Power, the SSH unlock in development builds, PT2
  before any real volume, the recovery key.
- **The digest check depends on `omamobile-tarnorm`** matching GNU tar; it
  changes only the name and prefix fields and their checksum, it is tested
  against its twin, and PT3 runs it on the phone before anything is erased.
- **A long wait at the pad changes later boot steps:** the cameras' deferred
  probe timeout on hotdog (PM2). Any driver with a timeout counted from
  boot can do the same; a phone gets its own check before it opts in.
- **The disk PIN and the lock PIN drifting apart** after a plain `passwd`:
  `omamobile-pin` and its README.
- **The unencrypted backup on the laptop:** the tool says what it holds
  and asks for it to be deleted.
- **No protection against a changed boot image** until §5's verified boot
  chain exists (§11.2).

### 11.13 Sources

- cryptsetup, *cryptsetup-luksFormat(8)* and *cryptsetup-open(8)* (header
  size, PBKDF options, key-file handling, persistent flags).
  <https://man7.org/linux/man-pages/man8/cryptsetup-luksFormat.8.html>,
  <https://man7.org/linux/man-pages/man8/cryptsetup-open.8.html>
- cryptsetup, the project's repository (the release in Alpine 3.24's
  `cryptsetup` 2.8.6 package, which the initramfs carries).
  <https://gitlab.com/cryptsetup/cryptsetup>
- Linux, `Documentation/admin-guide/device-mapper/dm-crypt.rst` (open
  flags, `no_read_workqueue`, `allow_discards`).
- GNU tar, *GNU tar manual*, "Storing sparse files" and "Controlling
  extended header keywords" (`--pax-option`, the `GNUSparseFile` name).
  <https://www.gnu.org/software/tar/manual/>
- Our own: `initramfs/init`, `bin/omamobile` (`initramfs`,
  `INITRAMFS_MODULES`, the splash), `tools/install-phone` (the PIN
  question), `rootfs/build-inside`, the hotdog notes in #931
  (`device/hotdog/BRINGUP-M1.md`, `device.conf`), and the kernel
  configuration of `out-hotdog-sensors` (2026-11-18).
