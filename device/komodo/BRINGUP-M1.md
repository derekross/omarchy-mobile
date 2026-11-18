<!-- SPDX-License-Identifier: MIT -->
# Pixel 9 Pro XL (komodo): first-light plan

**Status — 2026-11-18:** research and planning only on Omarchy Mobile branch
`bringup/komodo-stage0` (PR #914). No kernel DTS, device descriptor, or image
has been built. Nothing from Omarchy Mobile has been booted or flashed. The
phone remains stock Android 17, build `CP4A.261105.040.A1`, on slot A with its
bootloader locked and verified boot green. A targeted ADB read after the stock
update also confirms `MP1.0` and `dtbo_idx=34`; no personal content was queried.
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
- **[V]** Both the initial and post-update captures report `ro.boot.dtbo_idx=34`.
  In G/'s `constants.bzl`, zero-based entry 34 is `zumapro-komodo-mp.dtbo`; its source
  declares board ID `0x60806`, revision `0x010000`, and Komodo compatibility.
  (G/ `constants.bzl:42`, `dts/zumapro-komodo-mp.dts:16-24`.)
- **[V]** The named fastboot reads found A/B boot partitions and the device
  returned to stock Android on slot A, locked and verified boot green. No slot
  selection or partition write was issued. (R/ `fastboot-vars.txt`,
  `post-fastboot-state.txt`.)
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
  `dmesg`. No verified memory map, framebuffer reservation, USB gadget path,
  or exact boot-chain/recovery analysis is available yet.
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
5. Ask for approval for that exact boot attempt. Never unlock, erase userdata,
   write slot A, write firmware/modem/persist/devinfo, or change slot metadata
   outside the documented installer workflow.

## 4. Risks and gates

| Gate | Action | Pass condition | Stop condition | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| M1.0 | Offline public-source comparison | Exact Android 17 DTB/DTBO mapping, image format and matching board revision recorded | Source unavailable or unexplained DTBO index | None; read-only | Low |
| M1.1 | Offline minimal DTS and kernel build | Clean validation/build; no unrelated device changes; first-light nodes only | Missing memory map, unresolved ABL requirement, new schema/build warning | Discard isolated worktree/output | Low |
| M1.2 | Attended slot-B boot, only after separate approval | Boots to framebuffer and USB SSH; A remains untouched | Any unexpected slot, bootloader, screen, USB, or storage behavior | Use documented fastboot recovery to restore stock A; no improvised writes | High |

## 5. Results and open questions

- 2026-11-18: M1.0 research found a strong Google Android 16 MP-overlay
  candidate at DTBO index 34. Exact Android 17 artifact correspondence is
  unresolved.
- No code, kernel image, DTB/DTBO, or phone-side test has been produced.
- Open: matching Android 17 source; live DT and memory map; framebuffer handoff;
  safe stock recovery route after a slot-B first-light attempt; and USB gadget
  support requirements for this hardware.
