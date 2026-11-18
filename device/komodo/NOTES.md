<!-- SPDX-License-Identifier: MIT -->
# Pixel 9 Pro XL (komodo) bring-up notes

Stage 0 started 2026-11-18. This is a read-only stock capture from one retail
Pixel 9 Pro XL. Nothing from Omarchy Mobile has been booted or flashed. Raw
captures remain private; only non-identifying facts are recorded here.

Tracking issue: [#913](https://github.com/derekross/omarchy-mobile/issues/913).

## Stage 0: stock Android capture

`R/` means the contributor's private capture made with `bin/omamobile capture
komodo-stock` over ADB on 2026-11-18. It was unrooted, so there is no live DT,
`dmesg`, `/proc/iomem`, or root-only kernel state. The capture contains device
identifiers and is not in this repository.

### Identity and current boot

- **Pixel 9 Pro XL, `komodo`, Tensor G4 (`zumapro`), hardware revision MP1.0**
  [V] (R/ `getprop.txt:675,677,872,878,926`).
- **Android 17, build `CP3A.261005.005`, security patch 2026-10-05** [V]
  (R/ `getprop.txt:764,778,783`).
- **Currently running slot B; bootloader locked and verified boot green** [V]
  (R/ `getprop.txt:666,695,709,732`). This says nothing about the other slot's
  bootloader version or slot health.
- **Bootloader property `ripcurrentpro-17.0-15819938`; `dtbo_idx` 34** [V]
  (R/ `getprop.txt:655,664`). Fastboot variables have not been
  read; doing so requires an attended reboot to the bootloader.

### CPU, memory, and partition names

- **Eight CPUs** [V] (R/ `proc.txt:7-70`): four with CPU part `0xd80`, three
  with `0xd81`, and one with `0xd82`. Part names are not inferred here.
- **`MemTotal` 15,957,128 kB** [V] (R/ `proc.txt:73`).
- **A/B names exist for `boot`, `init_boot`, `vendor_boot`,
  `vendor_kernel_boot`, and `dtbo`; `super` and `userdata` are also present**
  [V] (R/ `partitions-by-name.txt:11-12,18-19,30-31,51,57,64-67`). Partition
  sizes and fastboot slot metadata remain unknown.

## Interpretation and open questions

- The Pixel 9a (`tegu`) is the current Tensor G4 bring-up, but it is a different
  board. Do not copy its board DTS or panel, touch, GPIO, regulator, or firmware
  assumptions onto `komodo` without evidence from this device.
- The modem package already notes that Pixel 9 Pro XL needs its PHY brought up
  before its PCIe host. This is a lead for a separate hardware investigation,
  not a verified result from this phone.
- Still needed before any device descriptor or kernel DTS: stock fastboot
  variables and partition sizes; the live device tree and memory map; the exact
  factory-image DTB/DTBO for this build; boot-chain and recovery analysis; and
  board-specific display, touch, storage, Wi-Fi and modem evidence.
- No device-specific kernel tree is present on the contributor's host yet.
  Kernel DTS work belongs in `linux-omarchy-mobile`, not this repository.

## Safety boundary

The capture used only unrooted ADB reads. No reboot, bootloader unlock, slot
change, flash, root operation, or partition write was performed. Keep the phone
on stock until the boot chain, exact partitions, rollback behavior, recovery
path, and a gated first-light plan have been reviewed.
