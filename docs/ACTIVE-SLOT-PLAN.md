<!-- SPDX-License-Identifier: MIT -->
# Release installs on the running slot (development keeps slot B)

Status (2026-11-16): **approved by the maintainer; not built.** Decided on 2026-11-16: "eventually we don't even install it to slot b because we're using slot a. we're only using slot b now in development stages. end users will not do this." This plan is how. Facts are marked [V] (seen in the repository or the notes), [D] (documented elsewhere) or [I] (inferred, to be measured by the runbook in §6).

## 0. The idea, and what shapes it

A release install writes the five boot images of the slot the phone runs from now (`current-slot`), then `userdata`, then sends `reboot`. It sends no `set_active`. The bootloader that starts Omarchy Mobile is the one that just answered fastboot, and its version is the `version-bootloader` the build index already matches. So the bootloader-version check, the owner's `--bootloader-slots-match` statement, the slot probe and the "what does slot B hold?" question all leave the release write path. A first install from stock Android becomes as simple as a reinstall, in the desktop app and the web page as well as on the command line.

What the code says:

1. **The kernel-update hook already writes the running slot.** On today's release phones that is B. Updating in place on A is the same risk with a different letter.
2. **The storage guard hard-codes `_b`** [V]: `initramfs/init` `ufs_rw_load` (the `boot_b|…|dtbo_b|userdata` list), `descriptor.sh` `BU_UFS_RW_ALLOWED`, `bin/omamobile`'s `UFS_RW_ALLOWED`, `tools/install-phone`'s `UFS_RW` check and `tools/phone-smoke`'s allowed list. A slot-A release booted by today's initramfs would leave `_a` read-only and slot B writable, the wrong way round. **The guard learns the running slot before any slot-A release ships.**
3. **`manifest.json` carries the slot-B contract** [V]: the writes are `<image>_b`, `after` is `["set-active b","reboot"]` and `require_matching_bootloader_slots` is true, enforced in the installer's `core/src/manifest.rs`, in `tools/install-phone` and `tools/bundle-manifest`. **A new manifest format is the switch**, and it fails closed: every existing installer refuses it.
4. **The modem uses `modem_a` whatever slot boots** [V] (`packages/omamobile-modem/modem/props.conf`, `profiles/modem.conf`). Right for a slot-A install; on a phone whose stock moved to B after an update it would pair slot A's modem image with firmware from a newer build.
5. **A phone's other slot is often stale** [V, cheetah NOTES 2026-10-28: the second 7 Pro's `vbmeta_b` and radio on B were older builds]. The running-slot model never starts that slot on purpose; only the bootloader's own fallback can (Risks).

## 1. What a release first install writes, and in what order (7 Pro on slot A)

**Manifest format 2, "install on the running slot":** the writes name images, not partitions; `install.slot: "active"`; `install.accept_current_slots` from the device descriptor (cheetah: `["a"]` until the modem follows the slot, §4, then `["a","b"]`); `after: ["reboot"]`; no `require_matching_bootloader_slots`. The partition suffix is read from the phone at run time, never taken from the manifest.

1. **Look (read only).** `getvar all`: product, unlocked, `current-slot` (in the accepted list, or stop `current-slot-not-accepted`), `version-bootloader` and `version-baseband` (looked up in the build index: a tested build), `partition-size:<image>_<cur>` for each `BOOT_IMAGES` entry (AVB images exactly the `AVB_FOOTERS` size), and both slots' flags (logged only).
2. **Answers** into the placeholders; `boot-update.conf` gets `AUTO_WRITE=yes` and `SLOT=<cur>`.
3. **Confirmation.** It lists `boot_a init_boot_a vendor_boot_a vendor_kernel_boot_a dtbo_a userdata` and says plainly that Android on this phone is replaced and the way back is Google's factory image (§3).
4. **Gate.** Just before the first flash, `serialno` and `current-slot` are read again; a change stops it.
5. **Boot images:** `flash <image>_<cur>` in the descriptor's order (boot, init_boot, vendor_boot, vendor_kernel_boot with the owner's key in its ramdisk, dtbo).
6. **Root:** `flash userdata` (sparse, streamed).
7. **Read back** `getvar all`, read only: `current-slot` unchanged; the slot flags after the writes are logged (does a flash clear the slot's successful mark on cheetah? [I]).
8. **`reboot`.**

**Order:** boot images, then `userdata`, as today. Cut off after the boot images, our initramfs meets a `userdata` that isn't `omamobile-root` and stops in its rescue path; it never formats [V]. The other order would let stock's `boot_a` start on our ext4 `userdata`: recovery's "Factory data reset", and a stock start that rewrites `efs`, `persist` and `modem_userdata`.

**`vbmeta_a` and AVB footers:** nothing new is written. Stock's `vbmeta_a` stays; it chains `boot` and `init_boot` [V], so the images need their footers from the first boot, which the bundle's already carry (`AVB_FOOTERS`, the test key, `AVB_ROLLBACK_INDEX=1783209600`). The other images' hash mismatches are allowed while unlocked, as on B today (the orange screen). No `vbmeta` write, so no new safety-rule exception.

**What boots:** slot A stays active, so the bootloader loads our `_a` images. If the flash cleared A's successful mark (as a flash of B did on the 9a [V]; on cheetah [I]), A runs on retries until `omamobile-boot-success` marks it at the first good boot; that script already marks whichever slot booted [V]. If the first boots fail, the bootloader falls back to slot B, whatever is there (Risks).

**First install or reinstall:** the writes are the same either way. For the steps after the write the installer stops asking: it always takes a fresh radio backup into a new folder and provisions with `--first-install`, and offers `--restore` of settings only when its own record on this computer holds a `phone-config.tar` for this phone. The slot-B question, the `runs-from-slot-b` stop, `--reinstall`, the probe and the override stay for format-1 releases only.

**A phone that ran Omarchy Mobile on slot B in development:** running from A, it is a first install on A, and slot B is left as it is (the confirmation says so when B reads successful). Running from B: with `b` accepted, an install on B; with `a` only, the stop "not supported yet", never advice to `--set-active=a` (that starts A's bootloader at an unknown version). Both slots share one `userdata`.

## 2. Kernel and boot updates after such an install

**In place on the running slot. A/B alternation is rejected.**

`omamobile-boot-update` writes `<image>_<SLOT>` and keeps every safety it has [V]: `AUTO_WRITE=yes`; the board check; the descriptor rules; each image found by GPT name on the main LUN, on `UFS_RW`, reading `ro` 0; battery at 30 % or charging; the previous images and modules kept in `/var/lib/omamobile/boot/previous`; `dd conv=fsync` and a sha256 read-back; `rollback`; `omamobile-update`'s `preflight` before the download; never a reboot. New: `SLOT=` in `boot-update.conf`, default `b` when absent (so every phone installed before this behaves as now); the running suffix must equal `SLOT`, so a release on A that fell back to a development system on B doesn't write B; and a hook from before this change refuses a `SLOT=` line ("anything else is an error"), failing closed.

**A bad kernel** costs what it costs today (RELEASES §5.3): the phone stops in fastboot or resets, and the fix is the five writes from the computer: the installer's **Repair** (the running slot's five images, no `userdata`, no `set_active`; INSTALL-EXPERIENCE-PLAN §7), or `bin/omamobile flash` with the previous bundle's images or `previous/`. **Repair is built with format 2**: with stock gone, it and Google's tool are the ways back from a bad kernel.

**Why not alternation:** every update would start the other slot's bootloader, at a version nothing of ours can read without a switch, which is the problem this change removes; it boots against the other slot's possibly stale `vbmeta`; it needs a `set_active` from Linux (a `devinfo` write) and a guard open on both slots; and its one gain, automatic fallback, falls back into that unknown bootloader. Later improvements stay on the running slot (an initramfs boot counter, a known-good kernel kept on `userdata` for kexec). Revisit only if a device's two bootloaders can be proven equal.

## 3. The way back, the docs, and the AGENTS rule

**The way back** is Google's Android Flash Tool or the factory image's `flash-all` (the bootloader is still unlocked); it writes the current slot and wipes `userdata`. The installer still never flashes stock itself. Owners are told not to lock the bootloader unless both slots hold Google's images. An install that is cut off leaves no system that starts until the installer runs again or Android is reinstalled; Fastboot Mode is still reachable with the keys.

**Docs to change:** INSTALL.md (the opening, the stuck-after-an-update advice that runs `--set-active=a`, "Going back to Android"); the bundle's README.txt; INSTALL-EXPERIENCE-PLAN §1, §2, §4.6 and §7; RELEASES §5.3, §6 and a §12 decision; SECURITY-PLAN §3.2 and §5 (secure mode later writes `vbmeta_<cur>`, and stock on A is no longer the way back on a locked phone); CONTRIBUTING §3. Superseded for format 2: INSTALL-EXPERIENCE-PLAN G4, G5 and D4, and the installer's GO-LIVE run 5.

**AGENTS.md §1** ("Only slot B and `userdata` are ours") becomes, in its own change once the guard and the hook support it:

> **Only the running slot's boot images and `userdata` are ours.** In development that is slot B: write only `<image>_b`, only through `bin/omamobile flash|push`, and stock on slot A is the way back. A release install (manifest format 2, from `tools/install-phone`, `omamobile-install`, the app or the web page) writes the five boot images of the slot the phone runs from and `userdata`, with no `set_active`, never the other slot; the way back is Google's factory image. On the phone, `omamobile-boot-update` writes only `<image>_<SLOT>` (`SLOT` from `boot-update.conf`, default `b`, and only while running from it). The storage guard leaves writable only the running slot's images and `userdata`.

The bullet on the two named slot-flag changes stays for format-1 releases only; the probe stays off and goes when format 1 retires. Nothing else in §1 changes: never the bootloader, radio, `vbmeta`, `devinfo` (but the boot-success mark), `persist`, `efs*` or `modem*`.

## 4. Radio backup, provisioning, the boot-success mark, the storage guard

- **Radio backup:** the same partitions and the same read-only `nv-backup`, at the first start before provisioning, **always into a new folder**: a first install comes straight after a stock start, which rewrites `efs`, `persist` and `modem_userdata` [V]. Older backups are kept; a `--check` against one is reported, never fatal.
- **Provisioning:** `phone-provision --first-install --nv-backup DIR FACTORY.zip`, unchanged; the factory build now matches the running slot by construction.
- **The modem's slot:** before `b` is accepted, `omamobile-modem` takes its slot from `androidboot.slot_suffix` (`props.conf`, `profiles/modem.conf`, the NV overlay's image list). The six NV checksums already cover both `modem_a` and `modem_b`.
- **The boot-success mark:** no change [V]; it marks the slot that booted, and it closes the window in which a failed boot falls back to the other slot.
- **The storage guard opens the running slot:** `initramfs/init` reads `androidboot.slot_suffix` from `/proc/bootconfig`, then `/proc/cmdline`, maps each packed `X_b` to `X_<running>`, keeps `userdata`, and leaves the other slot read-only. No readable suffix: every boot partition stays read-only and `userdata` writable. The packed list keeps the `_b` notation ("slot form") for now. `bin/omamobile initramfs` packs a marker (`/etc/omamobile-ufs-rw-slot` = `running`), and `make-bundle`, `install-phone` and the installer refuse a format-2 bundle whose ramdisk lacks it. A development phone on B is unchanged; `push` to a release phone on A refuses, plainly; `phone-smoke` accepts the slot `boot-update.conf` names.

## 5. Other devices

- **Pixel 9a:** no release, unchanged. An install on A would move its costly fallback (a fastboot flash clears the mark, every boot spends a try while marking is on hold, and at zero the bootloader starts B: if that's stock, the cost is `userdata`). It stays development on slot B; "ask the maintainer before any fastboot write to slot B" becomes "to the slot being written". A release waits for the maintainer's decision on how its slot is marked.
- **Pixel 6, 8 and 10 families** (Google's inactive-slot warning [D]): the running slot suits them better; their remaining exposure is a fallback before the mark, the same as stock's after any update. Each is qualified on its own.
- **Qualcomm A/B phones:** writing the active slot may remove the need for the GPT attribute write [I]. Their boot methods are outside the release installer; recorded as an option for their plans.
- **Phones without slots:** the case where the suffix is empty (`SLOTS=none`); a named exception to "never an unsuffixed flash" for such a device. Not part of this change.

## 6. The attended runbook on the reference 7 Pro

Before: the radio-backup check passes; the home folder and settings are copied off; every step is the maintainer's go; the slot flags are recorded before and after every fastboot step; the tested build CP2A.260705.006 (bootloader `cloudripper-17.0-15199429`, both slots' version on this phone [V, NOTES 2026-11-09 and 11-12]).

| Step | What | Pass | Stop | Rollback |
| --- | --- | --- | --- | --- |
| R0 | `getvar all` in Fastboot Mode (today on B) | the version above | another version | none |
| R1 | stock back on A: `--set-active=a`, `reboot bootloader`, `current-slot` a with the same version, then the owner's own `flash-all` of CP2A (wipes `userdata`) | Android's first screen | another version on A; the phone not seen back on its bootloader screen; `flash-all` fails | `--set-active=b` and a known-good `bin/omamobile flash` |
| R2 | stock starts; setup skipped; back to Fastboot Mode; flags | `a` successful | | |
| R3 | dry runs of a format-2 bundle: `bash install --dry-run` and `omamobile-install install --dry-run` | `<image>_a` ×5, `userdata`, `reboot`; no `set_active`, no slot question, no probe, no bootloader stop | any `_b` or `set_active` | none |
| R4 | the write: the app, or `omamobile-install install --write` | read-back `current-slot` a; A's flags recorded | any failed flash (still in fastboot) | run again, or `flash-all` |
| R5 | first boot | the orange screen; the guard's "allowlist: boot_a … userdata", `_b` read-only; firstboot done; "slot a marked successful" | ends in fastboot ("BL1 requested": the footers); endless resets; Android recovery (neither choice: Volume Down + Power about 20 s); a fallback to slot B (write nothing, record it) | run the install again, or `flash-all` |
| R6 | radio backup into a new folder, `phone-provision --first-install`, restart, `phone-smoke` | every required row; boot slot a; guard `_a` and `userdata` | the modem against the wrong checksums | |
| R7 | kernel update in place: `omamobile-boot-update write --dry-run` lists `_a`; a real update, a restart, `rollback`, a restart | read-back OK; the new release runs | `_b` shown; a `SLOT` refusal | `rollback` |
| R8 | Repair drill: the installer's Repair writes the five `_a` images and keeps `userdata` | it boots; the root is intact | | |
| R9 | optional, last: the way back with Google's tool | Android starts | | |

When every step passes, the maintainer adds the format-2 and accepted-slot lines to cheetah's descriptor and notes, and the next release is format 2.

### 6.1 The running-slot guard on a development phone (slot B), before any of the above

Step 2 of §7 changes what every phone boots (the init is in device-cheetah's boot files and in every `bin/omamobile initramfs`), so one development boot of it comes first. The 7 Pro on slot B, as today; every step is the maintainer's go; the device-cheetah version is set by the maintainer only after this boots.

| Step | What | Pass | Stop | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| G0 | read only: `grep slot_suffix /proc/bootconfig`; for every `sd*` partition its `PARTNAME` and `ro` | `_b`; the five `_b` boot images and `userdata` `ro` 0, everything else 1 | another slot | none | none |
| G1 | `bin/omamobile initramfs`, `images`, then `systemctl stop omamobile-modem` and `bin/omamobile push` | SSH back on the new boot id | no SSH after about a minute (the safety net crashes back to fastboot or slot A) | `bin/omamobile flash` of the last known-good set (built by the current tool, footers included); after a fallback to stock on slot A (`current-slot` a), `bin/omamobile flash --from-slot-a`, which warns before writing | low: the guard is the only change |
| G2 | read only: `dmesg \| grep ufs-ro:`, G0's list again, `tools/phone-smoke` | "running from slot b", "allowlist: boot_b init_boot_b vendor_boot_b vendor_kernel_boot_b dtbo_b userdata"; the same `ro` values as G0; the boot and storage guard rows ok | any `_a` partition `ro` 0, or a `_b` boot image `ro` 1: write nothing, flash back | as G1 | none |
| G3 | a second `bin/omamobile push` of the same images | it writes and verifies through the guard, as before | a read-only refusal | as G1 (`flash`, or `flash --from-slot-a` after a fallback to slot A) | low |

## 7. The changes, in order

**First, changing no existing phone:**

1. This plan; after it, the AGENTS §1 change (§3), CONTRIBUTING §3, a RELEASES §12 decision.
2. **The guard:** `initramfs/init` (`ufs_rw_load`, `ufs_ro_pass`, `ufs_unguarded`) maps the running slot; `bin/omamobile initramfs` packs the marker; `tests/storage-guard` covers suffixes a, b and none. A development phone's boot of it gets its own short runbook (it changes what boots).
3. **`packages/omamobile-boot-update`:** `SLOT=a|b` (default b), the running-slot check, `<image>_$SLOT` in finding and checking partitions and in `previous/`; tests; version bump, and the device packages' dependency on it.
4. **Phone-side checks:** `tools/phone-smoke`'s boot and guard rows; a plain refusal in `bin/omamobile push|flash` when the phone runs from A.
5. **`packages/omamobile-modem`:** the slot from the boot configuration (gates accepting `b`).

**Then, behind a descriptor line no device has:**

6. **Descriptor keys** `INSTALL_SLOT=active|b` (default b) and `INSTALL_ACTIVE_SLOTS`, validated alike in `bin/omamobile`, `lib/descriptor.sh`, `tools/install-phone` and the installer's `device_conf.rs`/`bundle.rs`.
7. **`tools/bundle-manifest` and `tools/make-bundle`:** format 2 when `INSTALL_SLOT=active`, the guard-marker check, README.txt's way back.
8. **`tools/install-phone`:** format 2 targets `current-slot` from the accepted list, checks it again before the first flash, writes `SLOT=`, sends no `set_active`, new texts.
9. **`tools/install-guided`:** no slot-B question or slot check for format 2; always a fresh radio backup into a new folder.
10. **The installer** (derekross/omamobile-installer): `core/src/manifest.rs` (format 1 or 2), `core/src/fastboot.rs` (the slot read at connect and at the last gate; writes granted per target slot; no `set_active` and no probe in a format-2 session; the read-back), `core/src/flow.rs` and `text.rs` (no slot-B, probe or bootloader-slots steps; the `current-slot-not-accepted` stop; the new confirmation and warning), `core/src/firstboot.rs` (`SLOT=`), the tests, DESIGN §6 and §11, WRITE-RUNBOOK (§6 here), GO-LIVE, the app's screens, a "Go back to Android" screen, and Repair.

**Then:** the attended run (§6) on a format-2 release built with 2, 3 and 7; the cheetah descriptor flip; first installs in the app and on the web page. **Later:** remove the probe, `--bootloader-slots-match`, the override and the slot-B question once no format-1 release is offered; rename the `_b` notation.

**Order constraints:** 2 and 3 are in the root image and the device package of any format-2 release; the installer (10) and `install-phone` (8) agree on the manifest before the flip; 5 comes before `b` is accepted.

## Risks

1. **A fastboot flash may clear A's successful mark on cheetah** [I]; if the first boots then fail, the phone falls back to B (older stock, a development system or nothing). Mitigated by the mark at the first good boot and measured in R4 and R5.
2. **An interrupted install leaves no system that starts** (today stock on A survives). The bootloader is untouched and Fastboot Mode reachable: run it again, or Google's tool. The texts and the resume record say so.
3. **No quick way back to Android:** a computer and Google's tool. The warning says so.
4. **The footers' rollback index** (2026-07-05) is below the stored index on phones with newer stock; tolerated while unlocked [D], on this bootloader [I]; not new. Never raise it.
5. **A guard regression could open the wrong slot:** tests, the bundle's marker check and `phone-smoke`'s row.
6. **Version skew** fails closed both ways: old installers refuse format 2, old hooks refuse `SLOT=`; existing slot-B phones keep `SLOT=b` by default.
7. **The modem's slot** while `b` is accepted (§4).
8. **The reference phone ends with the release on A and the development system on B sharing one `userdata`.** How development continues is the maintainer's choice (likely `bin/omamobile flash` to B over the release root, or a separate development phone).
9. **A RAM boot (`fastboot boot`) with stock active on slot A now opens stock's `_a` boot images**: the bootloader names `_a`, and the running-slot guard maps the list to it. Before, such a boot opened slot B's. Nothing of ours writes there from a RAM boot (`push` requires `_b`, `omamobile-boot-update` requires its `SLOT`), but the guard no longer keeps stock's boot images read-only on it.
10. **Secure mode later** writes `vbmeta_<cur>` and the custom key with no stock fallback on a locked phone: SECURITY-PLAN's wording changes, not its design.
