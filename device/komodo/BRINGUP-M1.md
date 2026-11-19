<!-- SPDX-License-Identifier: MIT -->
# Pixel 9 Pro XL (komodo): first-light plan

**Status — 2026-11-18:** this work targets **native Omarchy Mobile** (Arch Linux
ARM, Hyprland, mainline Linux), not the separate unofficial Omarchy-in-Termux/
PRoot project. The upstream Omarchy Mobile device matrix lists the Pixel 9
family as wanted; only the Pixel 9a (`tegu`) is in its supported-device work.
Thus Komodo/Pixel 9 Pro XL is a custom port, not a supported installer target.
Stage-0 capture plus a minimal board-DTS and kernel build exist on isolated
kernel branch `omamobile-komodo-m1`. The DTS only identifies Komodo and
public-source SoC selectors; it does not enable display or USB and is not an
installable first-light image. Nothing from Omarchy Mobile has been booted or
flashed. With the user's authorization, the bootloader was unlocked; the
resulting factory reset completed and Android setup was finished. The phone is
currently in fastboot on slot A. It remains stock Android 17, build
`CP4A.261105.040.A1`; no personal content was queried.
Planned kernel branch/worktree/output: `omamobile-komodo-m1`,
`~/omamobile-kernel/wt-komodo-m1`, `~/omamobile-kernel/out-komodo-m1`.

## 1. Goal

Build a minimal, reviewable first-light kernel for the Pixel 9 Pro XL that
boots only from slot B, preserves stock Android on A, displays the bootloader
framebuffer, and provides USB gadget SSH. Do not enable UFS, radios, the panel,
touch, or other peripherals until first light and recovery are proven.

## 2. Evidence and source paths

- `R/` — private, owner-only read-only capture at
  `~/android/reference/komodo-stock/`; never commit raw captures.
- `G/` — public Google GPL reference checkout at
  `~/omamobile-kernel/google-caimito`, branch
  `android-gs-caimito-6.1-android16`, commit `38a058681d6c`.
  Public sources: [`zumapro-komodo-mp.dts`](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/dts/zumapro-komodo-mp.dts)
  and [`constants.bzl`](https://android.googlesource.com/kernel/devices/google/caimito/+/38a058681d6cefbb95200dc8a5348939773eb9d6/constants.bzl).
- `L/` — `linux-omarchy-mobile`, branch `omamobile`, commit `26867fc4e826`.

### Verified facts

- **[V]** Pixel 9 Pro XL, codename `komodo`, SoC platform `zumapro`, hardware
  revision `MP1.0`. Initial capture was Android 17 build `CP3A.261005.005`,
  kernel `6.1.162-android14-11`; a targeted read after the stock update
  confirmed Android 17 build `CP4A.261105.040.A1`, kernel
  `6.1.172-android14-11`, slot A, and `dtbo_idx=34`. (R/ `getprop.txt`,
  `kernel-version.txt`, `post-update-targeted.txt`.)
- **[V]** A second targeted read reports `ro.boot.hw.soc.pkg_mode=0` and
  `ro.boot.hw.soc.rev=1`; `ro.boot.hw.soc.product_id`, `.major`, and `.minor` were
  empty. Google's public Zumapro source's `0x9875`, major-0 FOPLP A0/A1
  tuples are candidate DTS selectors, not live-read selector values. No
  personal content was queried.
- **[V]** Both the initial and post-update captures report `ro.boot.dtbo_idx=34`.
  In G/'s `constants.bzl`, zero-based entry 34 is `zumapro-komodo-mp.dtbo`; its source
  declares board ID `0x60806`, revision `0x010000`, and Komodo compatibility.
  (G/ `constants.bzl:42`, `dts/zumapro-komodo-mp.dts:16-24`.)
- **[V]** The named fastboot reads found A/B boot partitions and the device
  returned to stock Android on slot A, locked and verified boot green. No slot
  selection or partition write was issued. (R/ `fastboot-vars.txt`,
  `post-fastboot-state.txt`.)
- **[V]** A fresh read-only fastboot inventory on 2026-11-18 reports product
  `komodo`, bootloader `ripcurrentpro-17.0-16433847`, `unlocked=yes`, and
  current slot A. A is successful/not-unbootable; B is successful/unbootable;
  both report two retries. Each A/B image partition exists with these sizes:
  `boot` 64 MiB, `init_boot` 8 MiB, `vendor_boot` 64 MiB,
  `vendor_kernel_boot` 64 MiB, and `dtbo` 16 MiB. `userdata` is
  `0x1b5e215000` bytes. No slot or partition was changed. The bootloader does
  not expose `dtbo_idx` through `getvar`; the earlier ADB read reported 34.
  (R/ `fastboot-postupdate-targeted.txt`, `post-unlock-targeted.txt`, and
  `fastboot-inventory-2026-11-18.txt`.)
- **[V]** User authorized bootloader unlock, its factory reset, and experimental
  device operations. The reset completed and Android setup was finished. The
  phone is currently in fastboot. No Omarchy image has been written.
- **[V]** `fastboot fetch boot_a` failed while locked and was refused again
  after unlock with `Fetching restricted partition: boot_a is not allowed`.
  The later failed attempt left a zero-byte local placeholder, which was
  removed. No phone partition was written or fetched. Google's official
  factory image for this exact `komodo` build is now downloaded locally at
  `~/android/factory/komodo/CP4A.261105.040.A1/komodo-factory.zip`; its SHA-256
  matches Google's published value
  `ef15b7ca51ba393a836cbb07727d9b24aeecec80a9a40b11d5fe0dcef63a3aa5`.
  This provides the exact stock package, but does not replace the required
  read-only partition backups or finish the attended recovery runbook.
- **[V]** After the authorized reset and setup, Android reports `ro.build.type=user`
  and `sys.boot_completed=1`. ADB shell cannot read device-tree property files
  under `/sys/firmware/devicetree/base` or `/proc/iomem` (`Permission denied`),
  so the live memory map and chosen-node handoff are still unavailable. The
  phone was returned to fastboot afterward.
- **[V]** L/ already has `gs201.dtsi`, `zumapro.dtsi` and the Tegu board DTS,
  but no Komodo board DTS. The SoC description and drivers exist, so the first
  kernel task is a board-specific DTS adapted to L/'s upstream APIs rather than
  copying an Android DTS verbatim.

### Inferences and limits

- **[I]** The MP overlay is the best available board-source candidate because
  its index and board family match the initial capture. It is not proven to be
  the overlay used by the installed Android 17 build: G/ is an Android 16
  branch, and the exact Android 17 factory DTBO was not obtained.
- **[I]** `MP1.0` likely corresponds to the MP source variant; confirm through
  the exact factory image or live DT before treating the mapping as definitive.
- The unrooted capture could not read live DT properties, `/proc/iomem`, or
  `dmesg`. No verified memory map, framebuffer reservation, working USB gadget
  path, or exact boot-chain/recovery analysis is available yet. A source-derived
  USB2 test overlay now compiles and applies to the Komodo DTB, but it has not
  been schema-validated or tested on the phone.
- The Pixel 9a (`tegu`) is the same SoC family but a different board. Do not
  reuse its board-specific panel, touch, GPIO, regulator, storage, or radio
  values without evidence.

## 3. Design and order

1. Locate the matching Android 17 public kernel/device source and record the
   base DTB, selected overlay, boot image format, kernel command line and board
   revision. Do not disassemble, decompile, reverse engineer or redistribute
   factory binaries; if the matching source is unavailable, document the gap
   and stop before making board-specific assumptions.
2. Compare Google's MP overlay and Zumapro SoC description with L/'s existing
   driver/binding support. Port only the minimal CPU, timer, interrupt,
   reserved-memory, framebuffer handoff and USB-gadget nodes needed for first
   light. Keep unproven peripherals disabled.
3. Build and validate entirely offline in the isolated kernel worktree/output
   above. Run `checkpatch`, `W=1`, binding checks, DT schema checks, and the
   project's `tools/kernel-pr-check`; record all logs privately.
4. Write the attended first-boot runbook only after build artifacts and the
   A/B/recovery analysis are complete. It must state exact slot-B images,
   expected display/network results, stop conditions, rollback, and the
   specific recovery buttons/commands.
5. The user has already authorized unlocking, its associated wipe, and
   experimental device operations. Do not ask for that authorization again.
   Before flashing, finish the image and recovery analysis. Preserve slot A;
   never write firmware/modem/persist/devinfo or change slot metadata outside
   the documented installer workflow.

## 4. Risks and gates

| Gate | Action | Pass condition | Stop condition | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| M1.0 | Offline public-source comparison | Exact Android 17 DTB/DTBO mapping, image format and matching board revision recorded | Source unavailable or unexplained DTBO index | None; read-only | Low |
| M1.1 | Offline minimal DTS and kernel build | Clean validation/build; no unrelated device changes; first-light nodes only | Missing memory map, unresolved ABL requirement, new schema/build warning | Discard isolated worktree/output | Low |
| M1.2 | Attended slot-B boot after image and recovery gates (user authorization already granted) | Boots to framebuffer and USB SSH; A remains untouched | Any unexpected slot, bootloader, screen, USB, or storage behavior | Use documented fastboot recovery to restore stock A; no improvised writes | High |

## 5. Results and open questions

- 2026-11-18: M1.0 research found a strong Google Android 16 MP-overlay
  candidate at DTBO index 34. Exact Android 17 artifact correspondence is
  unresolved.
- 2026-11-18: `linux-omarchy-mobile` worktree
  `~/omamobile-kernel/wt-komodo-m1`, branch `omamobile-komodo-m1`, now contains
  a minimal `zumapro-komodo.dts`, Makefile entry, and Google compatible enum.
  The DTS builds; focused Google binding validation and `dt-validate` on the
  Komodo DTB reported no diagnostics. A full arm64 `Image` and all arm64 DTBs
  built with `W=1`; baseline warnings from unrelated kernel code and DTBs were
  present. This is compile evidence only, not a boot test.
- 2026-11-18: `device/komodo/overlays/usb2-gadget-test.dtso` now enables a
  USB2-only peripheral candidate using Google Caimito's HSI2C6/TCPC pin and IRQ
  mapping, the mainline Zumapro USB2 path, and a Tegu-derived S2MPG14 PMIC
  setup. `dtc -@` compiled the overlay and `fdtoverlay` applied it to the
  Komodo DTB. `dt-validate` 2026.9 against the kernel's processed schemas found
  zero findings in both the base and merged DTBs; the overlay added none. DTC
  emitted zero warnings. This is static validation only. The overlay is not
  named by a device descriptor and has not been run on Komodo. The PMIC IRQ
  remains a Tegu-derived candidate pending Komodo evidence.
- 2026-11-18: The kernel's `tcpm`, `tcpci`, and `tcpci_maxim` modules built
  successfully. Their vermagic matches the kernel release in
  `out-komodo-m1`; this is a targeted module build, not a complete module set.
- 2026-11-18: Downloaded Google's exact `komodo` factory package for
  `CP4A.261105.040.A1` (4,329,100,709 bytes) outside the repository, in an
  owner-only directory. SHA-256 matches Google's published checksum
  `ef15b7ca51ba393a836cbb07727d9b24aeecec80a9a40b11d5fe0dcef63a3aa5`.
  It is a verified stock image source; no phone restore was attempted.
- 2026-11-18: `tools/kernel-pr-check` passed on the Komodo board-DTS commits:
  checkpatch reported no errors (one standard MAINTAINERS warning), all 11
  device trees built with `W=1`/`dtbs_check` with no new warnings, and the
  touched DT binding passed `dt_binding_check`.
- The output is a 42 MiB uncompressed arm64 `Image` and a 45 KiB Komodo DTB.
  No Android boot image, initramfs, device package, or phone-side test has been
  produced. The USB test overlay is only a local DTBO source/build artifact.
- Open: matching Android 17 source; live DT and memory map; framebuffer handoff;
  an attended recovery runbook and required read-only partition backups; and a
  hardware-tested USB gadget path. Unlock is complete, but the bootloader
  blocks reading `boot_a`; static overlay validation does not resolve its
  candidate wiring values. Preserve slot A and do not test-flash until the
  image, rollback and recovery gates are complete.
