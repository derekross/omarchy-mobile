<!-- SPDX-License-Identifier: MIT -->
# Pixel 8 Pro GNSS plan (husky, Broadcom BCM4775x on spi21)

Status (2026-11-13): nothing of this has run on the phone, and I have no record that the chip has ever been powered.
This is the runbook @derekross asked for on
[linux-omarchy-mobile#239](https://github.com/derekross/linux-omarchy-mobile/pull/239) before the bring-up overlay:
what the first boots do, in which order, and what stops them. It changes no device tree and runs nothing.

[V] = read in source, in a maintainer's comment or in a capture of mine. [I] = inferred, with the step that would
settle it. [U] = unknown. References like `linux-omarchy-mobile#210` are the kernel repository; a bare `#578` is
this one.

## Where it stands

- The bus: `linux-omarchy-mobile#210` (merged) added the CMU_HSI0 USI3 clocks and a disabled `spi21` in
  `zuma.dtsi`. [I] the gate offsets are Google's and have not been exercised on hardware; a wrong one can hang the
  phone. Stage 2 below settles it.
- The rails: `linux-omarchy-mobile#211` (merged) added the S2MPG15 sub-PMIC as `pmic-2`, disabled, with the three
  GNSS rails (LDO9S core 725 to 1300 mV, LDO10S RF and LDO11S AUX 1600 to 1950 mV). [V] zuma-husky.dts on
  `omamobile` says that stock keeps them always on, so nothing sets a voltage at probe and the GNSS driver will
  switch them.
- The receiver: `linux-omarchy-mobile#239` (merged) added the BCM4775x node on `spi21`, disabled: the stock pin
  groups, 26 MHz, mode 3, feedback delay 1 and the three rails; nstandby is active high. [V] per derekross's
  comment there, it matches Google's `zuma-board-gps.dtsi`. The driver is `drivers/misc/bcm4775x` on `omamobile`,
  compatible `brcm,bcm4775-gnss`, module `bcm4775x-gnss`.
- [I] The chip also needs Google's `lhd` and `gpsd` and their configuration from a vendor image before it gives a
  fix. This plan touches none of that: it can show the bus, the rails and the chip's answer, not a position.
  Stage 1's userspace check settles whether anything on the phone would open the chip.

## What @derekross wrote for the overlay (on #239, in his words as closely as I can)

1. `spi21` has no `num-cs`, so the SPI driver will log "number of chip select lines not specified, assuming 1" at
   probe; `num-cs = <1>` in the overlay (or in the node) quiets it.
2. The overlay needs `usi3_hsi0` enabled next to `spi21` and `pmic-2` (its mode is already SPI in `zuma.dtsi`).
3. Stock sets `swap-mode` and `dma-mode` on this bus, which our tree doesn't model, and our `google,zuma-spi` uses
   zumapro's port configuration. If the first frames come back short or shifted, look there before the pins.
4. Stock keeps the three rails always on while our driver switches them, so load the driver before reading
   anything from the chip.
5. The usual rules for the first boot apply: the driver blacklisted before the DTB that enables its node, a log
   stream and the watchdog first, one change per boot, and a runbook in `device/husky` before it runs.

## Open questions of mine

- Chip select. [V] stock's `samsung,spi-chip-select-mode = 0` for this bus is not read by this tree, and
  `google,zuma-spi` uses `manual_native_cs`. [I] `linux-omarchy-mobile#204` (mine, open) acts only for a device on a
  GPIO chip select, and the BCM4775x is on the native one, so I don't expect it to matter. The first frames settle
  it.
- Which `pmic-1` consumers wait while `sec_acpm` is not loaded (the touch rails `touch_vdd` and `touch_avdd` are
  two) is [U]; stage 3 notes what is missing.

## Gates for every boot

I am at the phone, the cable on the desktop (USB ssh, never Wi-Fi only), and each boot is one go-ahead.

- Exactly one fastboot device, product husky. `slot-retry-count:b` is read in the bootloader and the phone boots
  only if it reads 3: refill with `fastboot set_active b` alone first (it needs no flash), and read it again. The
  phone's own shutdown spends a retry (#578), so count it. If the count is not 3 after the refill, flash the known
  good image set instead of booting. A boot that then leaves fewer than 2 tries ends the series.
- Battery at least 20 %, the hottest thermal zone at most 50 C with the screen off before a boot (the flash limit
  is 62 C, and a hot phone is not the moment to start), PipeWire and WirePlumber stopped and the speaker route off
  (a reboot hung once in `aoc_alsa_remove` while they held the card), no Chromium, backups current, no
  `THERMAL-PAUSE` file.
- The kernel is a published one, or a branch built from it with the exact commit named. [I] the log setup is the
  kernel's ramoops with `systemd-pstore` masked for the boot, so the record survives a reset (as in #578).
  `device/husky/overlays/klog.dtso` is a second overlay with its own needs (it sets `clk_ignore_unused` and
  `pd_ignore_unused`, which change the clocks this test is about, and it wants `DETECT_HUNG_TASK`, `WQ_WATCHDOG`
  and `PANIC_ON_OOPS` in the kernel): use it only after reading its header, and say so in the boot's notes.
- Modules: the driver is blacklisted, `blacklist bcm4775x_gnss`, in a file under `/etc/modprobe.d/` that I `cat`
  back before flashing; for the stages that enable `pmic-2`, `blacklist sec_acpm` as well (it autoloads at boot
  because `pmic-1` is on, and the regulator core's one-shot cleanup 30 s after boot would switch off any GNSS rail
  the bootloader left on). That file is in the shared rootfs: after a recovery from fastboot it is still there, and
  the next boot of another kernel has no touch until it is removed.
- Never open `/dev/ttyBCM`, never write `nstandby`, never read the driver's debugfs `probe` file, and never
  `grep -r` or `cat *` in its debugfs directory: each of them powers the chip. The pin states are read from
  `/sys/kernel/debug/gpio`, or the driver's `pins` file.

## Stages, one change per boot, each on top of the one before

Each stage is a boot of the same kernel with one more thing enabled, ends with its checks, and the next stage
starts only after the previous one passed. Between sessions the phone goes back to the plain DTB (see Revert).

1. **Plain** (control), nothing enabled. No `spi21`, no `vdd_gnss` regulator lines, the regulator count equals the
   reference boot's, `sec_acpm` loaded because of `pmic-1`. Boot 1 only, read only: `cat /proc/cmdline`,
   `pacman -Q omamobile-gnss` and a grep of `/etc/modprobe.d`, `/usr/lib/modprobe.d`, `/etc/modules-load.d` and
   `/usr/lib/modules-load.d` for `sec_acpm` and `bcm4775`, and whether the initramfs carries either module [U: how
   to list it on this image]. Nothing may open `/dev/ttyBCM` the moment the driver creates it: if anything like
   `lhd` is installed, stop here.
2. **Bus**: `usi3_hsi0` and `spi21` enabled, the receiver's node still disabled. `/sys/class/spi_master` lists
   `spi21`; no new child under `/sys/bus/spi/devices`; the USI3 pclk, ip and source clocks show enabled in
   `clk_summary` (with `clk_ignore_unused` on the command line this proves less, so read the command line first);
   no `spi21` error.
3. **Rails** (`sec_acpm` blacklisted): `pmic-2` enabled too. Before the modprobe, `lsmod | grep sec_acpm` is empty,
   no `vdd_gnss` regulator exists and uptime is past 60 s (the regulator cleanup is one-shot, so after that it
   cannot fire on a late load); note what is missing meanwhile (touch is). Then one `modprobe sec_acpm`; read
   `state`, `microvolts` and `num_users` of the three rails, and through the regmap debugfs the S2MPG15 chip ID and
   the LDO9S to LDO11S control registers. [I] the chip ID is register 0x0b and the controls are 0x37 to 0x39 in the
   `pmic-2` regmaps (list `/sys/kernel/debug/regmap/` first and use the names it shows); the 7 Pro's 0x34 to 0x36
   are S2MPG13's, do not reuse them. Read only. Note whether touch comes back.
4. **Receiver**: the node enabled with `num-cs = <1>` on top of stage 3, so `sec_acpm` is blacklisted here too.
   Only if stage 3's reads worked and touch came back: repeat stage 3's late `modprobe sec_acpm` and read the
   three rails again; then check that `lsmod | grep bcm4775x` is empty and `spi21.0` is listed; then ONE command,
   `modprobe bcm4775x-gnss`. After it read the kernel log tail, the pin states as above, `ls -l
   /sys/bus/spi/drivers/bcm4775x-gnss/`, `ls /dev/ttyBCM /dev/bbd_*`, and `cat /sys/bus/spi/devices/spi21.0/nstandby`
   (expect 0; a plain read does not power the chip). Nothing else: the chip stays unopened.

## Stop at once

An oops, BUG, panic or hang; no ssh within 90 s of a boot, a visible reboot, or an uptime drop inside the first
190 s; the retry count below what the gate allows; the driver or `sec_acpm` loaded before its manual modprobe; any
`vdd_gnss_*: disabling` line (it means `sec_acpm` loaded early); `sec_acpm` or S2MPG15 errors, or a failing rail or
chip-ID read (do not load the driver); USB or ssh lost when `spi21` probes; a hot phone (over 62 C) or a battery
under 20 %. Between 50 C and 62 C during a stage: finish the reads, do not start the next stage. Touch not back
within 10 s of the late `sec_acpm` is stricter than my earlier runbook, which only noted it: finish the step's
reads, then revert. If ssh still answers, `reboot-to bootloader` first; if not, the buttons (Volume Down + Power)
to the bootloader. A reset loop: bootloader by the buttons and flash from there, never from the resetting system,
and never power-cycle a half-written slot B. Every reset spends one of slot B's three tries.

## Revert

Remove the modprobe file and confirm it is gone, even if it was removed earlier. Flash the plain image set (known
good: `cmp` it against the set and read `DEVICE`, which must say husky), read the retry count, boot, watch the uptime
to 190 s, check `uname -r`, then `modprobe sec_acpm` if it is absent and check touch, and boot once more so the
normal path is proven. The flash goes through `fastboot -s <serial>` after a check that exactly one device is
there, never through a helper that falls back to crashing the running kernel.

## Still unknown (only the phone settles it)

The USI3 gate offsets on hardware; the rail state the bootloader leaves; the chip ID; whether the native chip select
works at 26 MHz as it is; whether touch re-binds after a late `sec_acpm`; whether `swap-mode` and `dma-mode` matter
on this bus; which `pmic-1` consumers are missing while `sec_acpm` waits.
