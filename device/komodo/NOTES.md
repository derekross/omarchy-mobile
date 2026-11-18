<!-- SPDX-License-Identifier: MIT -->
# Pixel 9 Pro XL (komodo) bring-up notes

Stage 0 started 2026-11-18. This is a read-only stock capture from one retail
Pixel 9 Pro XL. Nothing from Omarchy Mobile has been booted or flashed. Raw
captures remain private; only non-identifying facts are recorded here.

Tracking issue: [#913](https://github.com/derekross/omarchy-mobile/issues/913).

## Stage 0: stock Android capture

`R/` means the contributor's private capture made with `bin/omamobile capture
komodo-stock` over ADB on 2026-11-18, plus the named read-only follow-up queries
below. It was unrooted, so there is no live DT blob or property values,
`dmesg`, `/proc/iomem`, or other root-only kernel state. The capture contains
device identifiers and is not in this repository.

### Identity and current boot

- **Pixel 9 Pro XL, `komodo`, Tensor G4 (`zumapro`), hardware revision MP1.0**
  [V] (R/ `getprop.txt:675,677,872,878,926`).
- **Android 17, build `CP3A.261005.005`, security patch 2026-10-05** [V]
  (R/ `getprop.txt:764,778,783`).
- **Stock kernel `6.1.162-android14-11`** [V] (R/ `kernel-version.txt:1`).
- **At the initial ADB capture, Android was running slot B; bootloader locked
  and verified boot green** [V] (R/ `getprop.txt:666,695,709,732`).
- **The initial Android bootloader property was
  `ripcurrentpro-17.0-15819938`; `dtbo_idx` was 34** [V]
  (R/ `getprop.txt:655,664`).
- **A targeted read-only ADB check after returning from fastboot confirmed the
  stock update had booted on slot A:** Android 17, build
  `CP4A.261105.040.A1`, security patch 2026-11-05, kernel
  `6.1.172-android14-11`, hardware revision `MP1.0`, and `dtbo_idx=34` [V]
  (R/ `post-update-targeted.txt`). Bootloader remains locked and verified
  boot is green. No personal content was queried.

### Named fastboot reads and return to stock Android

With the owner's approval, the phone was rebooted into the bootloader on
2026-11-18. Only named `fastboot getvar` reads were run; `getvar all` was not
used. Results are in the private R/ capture.

- **Fastboot reported product `komodo`, revision MP1.0, current slot A, and
  bootloader `ripcurrentpro-17.0-16433847`** [V]
  (R/ `fastboot-vars.txt:3,7,11,15`).
- **At that read, slot A was `successful=no`, `unbootable=no`, with 3 tries;
  slot B was `successful=yes`, `unbootable=no`, with 2 tries** [V]
  (R/ `fastboot-vars.txt:26-47`).
- **The queried boot-image partition sizes** [V] (R/ `fastboot-vars.txt`):
  `boot_a/b`, `vendor_boot_a/b`, and `vendor_kernel_boot_a/b` were `0x4000000`
  each; `init_boot_a/b` were `0x800000` each; `dtbo_a/b` were `0x1000000` each.
  `userdata` was `0x1b5e215000` (R/ `fastboot-vars.txt:50-91`).
- **After the plain `fastboot reboot`, Android completed boot on slot A with
  build `CP4A.261105.040.A1`; bootloader remained locked and verified boot
  green** [V] (R/ `post-fastboot-state.txt:1-7`). The prior ADB capture was on
  slot B with build `CP3A.261005.005` (R/ `getprop.txt:764,695`).
- **No `set_active`, unlock, flash, or partition-write command was issued.**
  **Inference I1:** the pre-reboot state matches AOSP's documented
  "update applied, reboot pending" state: Android was on successful B while A
  was selected, bootable, but not yet marked successful. AOSP says the next
  reboot enters the new slot, which remains unsuccessful until its userspace
  verification completes ([A/B update flow](https://source.android.com/docs/core/ota/ab)).
  A stock OTA already staged to A is therefore the likely explanation for the
  `CP4A` build. No update logs were read, so its timing and source are unconfirmed.
  Do not perform further reboots or slot actions until the update state is
  reviewed.

### CPU, memory, and partition names

- **Eight CPUs** [V] (R/ `proc.txt:7-70`): four with CPU part `0xd80`, three
  with `0xd81`, and one with `0xd82`. Part names are not inferred here.
- **`MemTotal` 15,957,128 kB** [V] (R/ `proc.txt:73`).
- **An unrooted listing of `/proc/device-tree` returned 732 entries, but
  reading the root `compatible` property was denied** [V]
  (R/ `device-tree-nodes.txt:1-732`, `device-tree-nodes.err:1`). These names
  are not a substitute for the live DT property values.
- **A/B names exist for `boot`, `init_boot`, `vendor_boot`,
  `vendor_kernel_boot`, and `dtbo`; `super` and `userdata` are also present**
  [V] (R/ `partitions-by-name.txt:11-12,18-19,30-31,51,57,64-67`). Partition
  sizes are only partially captured; the queried sizes and slot flags are
  recorded above.

### Google GPL board-source match (candidate)

- The public Google `kernel/devices/google/caimito` branch
  `android-gs-caimito-6.1-android16` contains `zumapro-komodo-mp.dts`.
  Its `constants.bzl` places that overlay at zero-based DTBO index 34; the
  overlay declares board ID `0x60806`, revision `0x010000`, and compatible
  `google,ZUMA PRO KOMODO`. This matches the captured `dtbo_idx=34` and
  `zumapro`/`komodo` identity [V] **for that published branch**, not yet for
  the installed Android 17 image [G/ [`zumapro-komodo-mp.dts`](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/dts/zumapro-komodo-mp.dts):16-24,
  [`constants.bzl`](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/constants.bzl):42;
  R/ `getprop.txt:655,675,677`].
- The phone's reported `MP1.0` hardware revision is consistent with the
  overlay's `MP` name, but that label alone does not prove which DTS revision
  or source version the installed image used [I].
- **Source limitation:** this is an Android 16 Google source branch, while
  the current system build is Android 17. No matching Android 17 caimito
  branch or factory DTBO for the installed build was found in this review.
  Treat the overlay as a strong reference candidate, not a verified exact
  source match. No Google source files or binaries were copied into this
  repository.

## Interpretation and open questions

- The Pixel 9a (`tegu`) is the current Tensor G4 bring-up, but it is a different
  board. Do not copy its board DTS or panel, touch, GPIO, regulator, or firmware
  assumptions onto `komodo` without evidence from this device.
- The modem package already notes that Pixel 9 Pro XL needs its PHY brought up
  before its PCIe host. This is a lead for a separate hardware investigation,
  not a verified result from this phone.
- Still needed before any device descriptor or kernel DTS: remaining stock
  partition sizes and descriptor facts; the live device tree and memory map;
  the exact factory-image DTB/DTBO for this build; boot-chain and recovery
  analysis; and board-specific display, touch, storage, Wi-Fi and modem evidence.
- A public Google GPL source checkout is now available locally at
  `~/omamobile-kernel/google-caimito`. Kernel DTS work belongs in
  `linux-omarchy-mobile`, not this repository; see the initial gate plan in
  [`BRINGUP-M1.md`](BRINGUP-M1.md).

## Safety boundary

The initial capture used unrooted ADB reads. With the owner's approval, one
reboot to fastboot and a plain reboot back to Android were performed, with only
named `getvar` reads in fastboot. No slot-change, unlock, flash, root, or
partition-write command was issued by this session; a stock A/B update appears
to have been pending, but its installation time and source are unknown. The
phone is currently on stock Android, slot A, with verified boot green. No
update logs were read, and the new slot's final successful mark was not
checked. Do not perform further reboots or slot actions until the update state,
boot chain, rollback behavior, recovery path, and a gated first-light plan
have been reviewed.
