<!-- SPDX-License-Identifier: MIT -->
# akita M1: first light on zuma

**Status (2026-11-03):** stage 0 done ([NOTES.md](NOTES.md), #308). Kernel branch `omamobile-zuma-akita-dts` (the binding, then the first-light DTS; not yet pushed): `zuma-akita.dtb` builds with `W=1`, `dtbs_check` reports only the two eUSB2-PHY supply warnings husky's board has, `dt_binding_check` passes, `checkpatch --strict` finds no errors, and `tools/kernel-pr-check` passes. M1.1 and M1.2 are done: the images are built and checked, and the phone's slots are as stage 0 left them. **M1 is complete (2026-11-03).** M1.3 passed gate (a): our kernel boots from slot B, with the USB gadget and SSH up 0.38 s into boot, and the bootloader's framebuffer and DECON0's trigger read exactly as on husky. M1.4 passed gate (b): `simple-framebuffer` and the trigger write put Omarchy's splash, and then console text, on the panel ([Results](#results)). The framebuffer change is tested but not yet committed.

## Goal

1. Our kernel starts from slot B and is **visible**: a USB gadget on the laptop, then `ssh root@172.16.42.1` (CONTRIBUTING §5.4 stage 1).
2. Read the bootloader framebuffer's address and DECON0's trigger register on the running phone, then add `simple-framebuffer` (gate b), as husky did.
3. Slot A stays stock throughout. Only `*_b` boot images are written, and only by `bin/omamobile flash`.

## What akita inherits from husky's M1

Husky's first light found and fixed what a zuma phone needs, and all of it is in today's tree, so akita's M1 starts where [husky's](../husky/BRINGUP-M1.md) ended:

- AVB hash footers on `boot` and `init_boot` (husky tests 6-8): `AVB_FOOTERS` in the descriptor, written by `bin/omamobile images`.
- The eUSB2 PHY and USB DRD PHY drivers (tests 16-18), built in (`CONFIG_PHY_SNPS_EUSB2=y` in `kernel/configs/omamobile.config`), with their nodes in `zuma.dtsi`.
- The zuma watchdog driver (tests 18-19). Without it, ABL's cluster watchdogs reset the phone about 80 s into each boot.
- `syscon-reboot-mode` and `reboot=warm` (test 22): `reboot-to bootloader` reaches fastboot.
- The PHY exit fix (linux-omarchy-mobile#42, tests 23-29) and the PMU tables (#49, test 30).

## Path abbreviations

`R/` = `~/android/reference/akita-stock-cp3a.261005.005` (the clean stock capture) and `F/` = `~/android/reference/akita-factory-facts-cp3a.261005.005` (the factory image's facts), both private. `G/` and `S/` = Google's GPL akita and zuma device trees at `android-16.0.0_r0.10` ([NOTES.md](NOTES.md)). `L/` = our kernel tree, `~/omamobile-kernel/wt-zuma-akita-dts`.

## Facts behind the DTS

| Item | Value | Evidence |
| --- | --- | --- |
| Base DTB match | `/soc_compatible` children `B0_IPOP` and `B1_IPOP` (`product_id` 0x9865, `pkg_mode` 1); husky's are FOPLP | R/live.dts, F/ base DTB 3, S/`zuma-b0-ipop.dts` [V] |
| Memory | ABL adds the DRAM banks to the base DTB's first (`zuma.dtsi`'s `memory@80000000`): 4 × 2 GiB on akita | R/live.dts [V] |
| Reservations | `zuma.dtsi`'s 15 fixed regions contain every fixed DRAM region of akita's live tree, at husky's addresses, except the four ABL inserts itself (`pkvm_guest_firmware`, `sec_dram`, `sec_pt`, `debug_kinfo_reserved`); three more lie outside DRAM (`cp_aoc_rmem` and two xHCI buffers) | R/live.dts against L/`zuma.dtsi` [V] |
| USB | DWC3 0x11210000, USB DRD PHY 0x11100000 (the eUSB2 PHY at 0x11110000 inside it), at `zuma.dtsi`'s addresses | R/live.dts [V] |
| PMU, reboot | `system-controller@15460000`, `reboot-cmd-offset` 0x810 | R/live.dts [V] |
| Watchdogs | `watchdog_cl0@10060000`, `watchdog_cl1@10070000`, the two `google,zuma-wdt` nodes in `zuma.dtsi` | R/live.dts [V] |
| Console | `uart@10870000`; stock's `earlycon=exynos4210,0x10870000` | R/live.dts, F/ `vendor_boot` [V] |
| Type-C | the MAX77759 on `hsi2c_11` (TCPC 0x25, fuel gauge 0x36, PMIC 0x66, charger 0x69), as on husky | R/ buses [V] |
| Panel | 1080x2400, `google,ak3b`, on the DSIM at 0x19440000; DECON0 0x19470000, DPP0 0x19900000 | R/ kernel log, R/live.dts, G/ [V] |
| Framebuffer | **0xfac00000** (DPP0 `RDMA_BASEADDR_P0` on the booted phone), as on husky (test 20) and gs201; the booted tree names no splash carve-out | M1.3 [V] |
| Trigger | DECON0 `TRIG_CON` 0x19470030 reads **0x3070** at handover (masked), as on husky. The ak3b panel is DSI command mode: no mode in Google's driver sets `MIPI_DSI_MODE_VIDEO` | M1.3, G/'s repository `display/panel-google-ak3b.c` [V] |

## Design

- **Husky's first-light tree with akita's identity:** the model, the compatible, the IPOP `/soc_compatible` children, husky's `bootargs`, and USB (`usb_dwc3`, `usb_hsphy`, `usbdrd_phy`) switched on. No UFS, buttons, PMIC, touch, MAX77759 or EEPROM nodes: each comes later, one per boot, once it has run here.
- **No guessed framebuffer** (husky's rule): the first boot has none. The address and the trigger are read on the running phone first (M1.3), and `simple-framebuffer` with its carve-out comes in a separate commit (M1.4).
- **No register write from the initramfs:** the descriptor has no `SIMPLEFB_TRIG_CON` until M1.3's read (the review of #308).
- **Kernel options:** `kernel/configs/omamobile.config` plus [kernel.config](kernel.config), the lockup detectors the `bootargs` rely on, as husky's.

## Risks

- **A black screen with no USB tells us little:** zuma's ABL keeps no ramoops (husky test 11). The bootloader's splash stays frozen on the panel while our kernel runs, since there's no framebuffer driver yet, so the panel shows nothing new either way. The laptop's USB log is the evidence.
- **Slot B falls back by itself:** `bin/omamobile flash` makes B active with three tries. Each failed boot uses one, and then ABL boots stock slot A, which is untouched and marked successful. Don't mark slot B successful during M1. `userdata` holds stock's (empty) Android data, and M1 doesn't touch it.
- **Unplugging the cable loses USB until a reboot:** the MAX77759 opens its USB2 data switch on unplug, and nothing closes it while no Type-C driver owns the chip (AGENTS.md, USB). Keep the cable in during M1; if USB drops, reboot.
- **Buttons:** on husky, Power + Volume Up held 15-30 s resets the phone under our kernel, Power alone does nothing (test 23), and Volume Down + Power then reaches fastboot. Akita has the same PMIC family [I].

## Runbook

Ask the human before every flash and reboot (AGENTS.md §1).

### M1.1 Build (laptop only)

`DEVICE=akita KERNEL_DIR=~/omamobile-kernel/wt-zuma-akita-dts KERNEL_OUT=~/omamobile-kernel/out-zuma-akita-dts bin/omamobile kernel`, then `modules`, `initramfs` and `images` the same way.

- **Pass:** `zuma-akita.dtb` builds; `dtbs_check` reports only the two eUSB2-PHY supply warnings husky's board has; `images` builds all five, with AVB footers on `boot` and `init_boot`, and accepts the DTB's `/soc_compatible` against `SOC_COMPATIBLE`; the initramfs packs akita's `UFS_RW` and "Pixel 8a", and no register write.
- **Risk:** none.

### M1.2 Before the flash (laptop, and a read-only look at the phone)

1. The phone's two backups (`akita-backup-prewipe-20261101`, `akita-backup-clean-20261102`) have a second copy offline (CONTRIBUTING §3.3).
2. The laptop's side of the USB network, once: the `omamobile-phone` NetworkManager profile from [INSTALL](../../docs/INSTALL.md) §5 (172.16.42.2/24 on the `cdc_ncm` link).
3. The SSH key in an agent, since `tools/phone-ssh` can't ask for its passphrase: for example `systemctl --user enable --now ssh-agent.socket`, then `SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/ssh-agent.socket ssh-add`.
4. `adb reboot bootloader`, then `~/android/akita/bin/akita-state`: `current-slot:b`, both slots `slot-successful:yes`, `unlocked:yes`, `version-bootloader:akita-17.0-15681527`.

- **Stop if:** there's no offline copy, or slot A isn't `slot-successful:yes`.
- **Risk:** none (one reboot to fastboot).

### M1.3 First boot, slot B (gate a: USB)

`DEVICE=akita bin/omamobile flash` with the M1.1 images: the five `*_b` images, `--set-active=b`, reboot. Slot B's Magisk-patched `init_boot_b` is replaced, as planned; slot A isn't written.

- **Expect:** the orange-state warning, the Google logo frozen on the panel, then a USB gadget on the laptop (`lsusb`, and a new `cdc_ncm` interface) within about 30 s.
- **Pass:** `ping 172.16.42.1`, then `ssh root@172.16.42.1`. Save `dmesg` to a private file under `~/android/reference/`. Then, with the logo still on the panel and from the ssh shell, **once each, read only, one register per call**: DPP0 `RDMA_BASEADDR_P0` (`/usr/local/bin/devmem 0x19900040`), DECON0 `GLOBAL_CON` (`/usr/local/bin/devmem 0x19470020`) and `TRIG_CON` (`/usr/local/bin/devmem 0x19470030`). `devmem` takes no width: a second argument is a value to **write**, so a read never has one. Record the three values here and in [NOTES.md](NOTES.md).
- **Stop if:** nothing is on USB after 2 minutes. Let slot B's three tries run out until ABL boots stock slot A, or reset with the buttons (Power + Volume Up for 15-30 s on husky). Don't send more commands to a phone that has stopped answering. Skip the reads if the logo is gone before them (the display block may be off), and stop if a read hangs or panics.
- **Rollback:** `fastboot --set-active=a`; slot A is untouched.
- **Risk:** medium (unknown hangs), with writes only to `*_b`; low for the reads (a powered, clocked block, read once).

### M1.4 A console on the panel (gate b)

With M1.3's address: a kernel commit that adds `simple-framebuffer` (1080x2400 `a8r8g8b8`) and its `no-map` carve-out at that address, as `zuma-husky.dts` has them; and `SIMPLEFB_TRIG_CON="0x19470030 <value>"` in the descriptor if `TRIG_CON` shows the trigger masked (husky reads 0x3070 and writes 0x3061). Rebuild (M1.1), then `bin/omamobile flash` again.

- **Expect / Pass:** the init's lines (`first light`, `USB gadget up`, `ssh`, `ready`) on the panel. With `splash` on the kernel command line, as on akita, you see Omarchy's splash instead, and the lines go only to the kernel log.
- **Stop if:** the panel stays frozen on the logo with USB up (the trigger), or USB doesn't come back (then as M1.3's stop).
- **Rollback:** the change is in slot B's images only; `fastboot --set-active=a` returns to stock.
- **Risk:** low (one register write, as on husky and cheetah, undone by any reset).

## Results

### 2026-11-03: images built, not flashed (M1.1)

- Kernel `7.3.0-rc6-omamobile-push1-gce160abd9ffc`, from `omamobile-zuma-akita-dts` at its DTS commit (no `-dirty`), built by `bin/omamobile kernel` in the container: `kernel/configs/omamobile.config` plus [kernel.config](kernel.config). `SOFTLOCKUP_DETECTOR`, `HARDLOCKUP_DETECTOR` (the buddy detector), `PHY_SNPS_EUSB2` and `USB_DWC3` are built in, and there are 1815 modules [V]. The only compiler warnings are two `-Wformat` ones in the base branch's AoC sound driver (`aoc_alsa_compr.c`), outside akita's commits.
- `tools/kernel-pr-check` on the two commits: 8 ok, 0 not ok. The 10 Google device trees build with `W=1` and `dtbs_check` with no new warnings, and `dt_binding_check` passes [V].
- The DTB in `vendor_kernel_boot` (one copy, 24.5 KiB) is the build's `zuma-akita.dtb` [V]:
  - model "Google Pixel 8a", compatible `google,zuma-akita`, `google,zuma`;
  - `/soc_compatible` `B0_IPOP` and `B1_IPOP` (0x9865, `pkg_mode` 1), which `bin/omamobile images` accepted against `SOC_COMPATIBLE`;
  - the DTS's `bootargs`, and the ECT at 0x90000000 (0x53000);
  - `__symbols__` kept; `usb_dwc3`, `usb_hsphy` and `usbdrd_phy` okay;
  - no `simple-framebuffer`.
- Headers (`unpack_bootimg`) [V]:
  - Both vendor images are header v4 with page size 0x800.
  - `vendor_boot` carries `VENDOR_CMDLINE` and no DTB.
  - `vendor_kernel_boot` carries the DTB and our initramfs (6.3 MiB).
  - `init_boot` carries 17.0.0 / 2026-10 with an empty ramdisk.
  - `boot.img` holds an 18 MiB kernel (partition 64 MiB).
- AVB hash footers on `boot` and `init_boot` (`avbtool info_image`) [V]:
  - padded to 64 MiB and 8 MiB;
  - SHA256_RSA4096, rollback index 1791158400;
  - `os_version` 17 and `security_patch` 2026-10-05 props, as on stock's footers. Stock's also carry the build fingerprint.
- `dtbo`: one entry, the empty overlay, with board id 0x40406 and rev 0x10000 [V].
- The initramfs packs akita's `UFS_RW` (`boot_b init_boot_b vendor_boot_b vendor_kernel_boot_b dtbo_b userdata`), the USB product string "Pixel 8a" and the laptop's SSH key for root. It has no `SIMPLEFB_TRIG_CON`, compatible or probe marker, so it writes no display register [V].
- sha256:

  | Image | sha256 |
  | --- | --- |
  | `boot` | `c1075d688638f9219ed21dcbd1826d6158bd22429404c3d8908736577f3b3e31` |
  | `init_boot` | `51a29b2a0d48efd6412f47e818f62b7c69416c5f9e175c2a7400bb8b0686d474` |
  | `vendor_boot` | `1b6e52c10fdb22c6a3c172b6b873e75d07a642bf4abe30fe2a59cab5fb74a53e` |
  | `vendor_kernel_boot` | `1f49f9d4b4a6f9c4d8128e29ca1c353b585927c52c6543bc5b9c5bc68940d2d8` |
  | `dtbo` | `53685bafbdfbb5fde12c0248e2dc6b79043fb9312783c16530e397a75661bc58` |

### 2026-11-03: the phone before the first flash (M1.2)

- Both backups have an offline copy. The laptop has the `omamobile-phone` profile (with `dnsmasq` for its shared mode), and the SSH key is in an agent.
- `fastboot getvar all` [V]:
  - `current-slot:b`;
  - slots A and B both `slot-successful:yes` and `slot-unbootable:no`, with `slot-retry-count` 2, unchanged since stage 0 ended;
  - `unlocked:yes`, `version-bootloader:akita-17.0-15681527`;
  - the four anti-rollback counters still at 3.

### 2026-11-03: first boot on slot B (M1.3)

All writes went to `*_b` only, through `bin/omamobile flash`. Slot A wasn't written.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 1 | `bin/omamobile flash` with the M1.1 images: the five `*_b` images, `--set-active=b`, reboot | Five `OKAY`s. SSH answered 27 s after the flash started, at 4.96 s of kernel uptime. The init's log: storage guard (akita's allowlist), `first light`, `USB gadget up on 11210000.usb` (0.37 s), `ssh` (0.38 s), `ready`, then `arch: no userdata partition`. The UDC reads `configured` | **gate (a) passed:** ABL boots our five images, and USB and SSH come up |
| 2 | With the Google logo still on the panel (seen by eye), from the SSH shell, once each: DPP0 `RDMA_BASEADDR_P0` (0x19900040), DECON0 `GLOBAL_CON` (0x19470020), `TRIG_CON` (0x19470030) | `0xfac00000`, `0x00000133`, `0x00003070`. The phone stayed up: USB `configured`, no new kernel messages | husky's three values (test 20): ABL's splash is at 0xfac00000 and the trigger is masked |

Findings:

- **The boot is quiet.** All nine CPUs come up, `MemTotal` is 7.3 GiB, and both cluster watchdogs are stopped at 0.13 s (`watchdog inactive, reset disabled`). Three lines stand out:
  - the eUSB2 PHY's two missing supplies, which get dummy regulators (the same as `dtbs_check`'s two warnings);
  - `exynos-clkout … failed with error -22`, which husky's log has too (H/);
  - `unable to open an initial console`, likely because ABL replaces every `console=` with `console=null` (NOTES.md) [I].
- **The kernel command line is our `bootargs`, then `VENDOR_CMDLINE`, then ABL's arguments** (NOTES.md). The booted tree adds only ABL's usual nodes: the RAM banks, the four reservations, `kaslr-seed` and the initrd range.
- **The phone stays up with the cable in.** After 10 minutes it is idle (load 0.00) with USB still `configured`, and slot B is not marked successful.
- These images are kept as akita's known-good set (`~/omamobile-kernel/known-good/akita-m1.3-gce160abd9ffc`).

### 2026-11-03: the console on the panel (M1.4)

Kernel: the first-light commit plus the framebuffer change, still uncommitted, so the release ends in `-dirty`. The change adds `simple-framebuffer` at 0xfac00000 (1080x2400, `a8r8g8b8`, stride 1080 × 4) with a `no-map` carve-out, `cont_splash_mem`. It follows husky's board file and the 1080x2400 gs201 boards (lynx, panther), and passes `W=1`, `dtbs_check` (the two eUSB2 warnings only) and `checkpatch --strict` (0 errors, 0 warnings). Descriptor: `SIMPLEFB_TRIG_CON="0x19470030 0x3061"`. The incremental rebuild took 3 minutes.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 3 | `bin/omamobile fastboot` from our running kernel | `reboot-to bootloader` reached fastboot in 25 s. `getvar`: slot B `slot-successful:no` with 2 tries left; slot A unchanged | The reboot mode works as on husky (test 22). Our first boot used one of slot B's tries, as designed |
| 4 | `bin/omamobile flash` with the M1.4 images | Five `OKAY`s; SSH at 4.92 s of uptime. Kernel log: the splash carve-out reserved, `simpledrm` on `chosen:framebuffer`, fbcon at 67x75, `fb0` 1080x2400 with stride 4320, and no trigger error from the init. Panel (seen by eye): Omarchy's splash, the green logo centred on dark blue | **Gate (b) passed:** frames reach the panel with the right address, size, stride and colours |
| 5 | From SSH, the init's log lines written to `/dev/tty0` | The text appears at the top of the panel, over the splash | fbcon draws on the panel, and the panel keeps following later writes |

Findings:

- **A splash instead of the init's lines.** `VENDOR_CMDLINE` carries `splash`, and akita's ABL keeps the vendor command line (NOTES.md). So the init sends its status lines to `/dev/null` and draws Omarchy's splash on `fb0` (`#1a1b26`, logo centred), the screen Plymouth shows when Arch starts. The colours on the panel match the image, so `a8r8g8b8` is the right byte order.
- These images are kept as `~/omamobile-kernel/known-good/akita-m1.4-gce160abd9ffc-dirty`, with their DTS.

## Open questions

- B0 or B1: which `/soc_compatible` child ABL matches. Our kernel has no `/sys/devices/soc0` yet (no chip-id driver for zuma), and the booted tree keeps both children.
- The panel's physical size for `width-mm` and `height-mm`: Google's ak3b driver gives 70 × 149 mm, the source of stock's reported DPI (391.9 × 409.1). That is too large for a 6.1-inch panel, so no value is used yet.
- Akita's reset and fastboot button combinations under our kernel.
