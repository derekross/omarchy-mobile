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

## What @derekross wrote for the overlay (three optional notes and the first-boot rules, on #239)

1. `spi21` has no `num-cs`, so the SPI driver will log "number of chip select lines not specified, assuming 1" at
   probe; `num-cs = <1>` in the overlay (or in the node) quiets it. [V] In this tree the message is a `dev_dbg`, so
   it only shows with dynamic debug.
2. The overlay needs `usi3_hsi0` enabled next to `spi21` and `pmic-2` (its mode is already SPI in `zuma.dtsi`).
3. Stock sets `swap-mode` and `dma-mode` on this bus, which our tree doesn't model, and our `google,zuma-spi` uses
   zumapro's port configuration. If the first frames come back short or shifted, look there before the pins. And
   since stock keeps the three rails always on while our driver switches them, load the driver before reading
   anything from the chip.
4. The usual rules for the first boot apply: the driver blacklisted before the DTB that enables its node, a log
   stream and the watchdog first, one change per boot, and a runbook in `device/husky` before it runs.

## Open questions of mine

- Chip select. [V] stock's `samsung,spi-chip-select-mode = 0` for this bus is not read by this tree, and
  `google,zuma-spi` uses `manual_native_cs`. [I] `linux-omarchy-mobile#204` (mine, open) acts only for a device on a
  GPIO chip select, and the BCM4775x is on the native one, so I don't expect it to matter. The first frames settle
  it.
- Which `pmic-1` consumers wait while `sec_acpm` is not loaded (the touch rails `touch_vdd` and `touch_avdd` are
  two) is [U]; stage 3 notes what is missing.

## Gates for every boot

I am at the phone, the cable on the desktop (USB ssh, never Wi-Fi only), and each boot is one go-ahead. A
session is one sitting: from a plain boot, through the stages that sitting reaches, to the revert.

- Exactly one fastboot device, product husky, and every fastboot command is `fastboot -s <serial>` with the serial
  read at that moment and never printed. Over ssh, `/proc/device-tree/model` must read Google Pixel 8 Pro before
  any other command, before the modprobe file is written and before anything is loaded: the USB address is the
  same for every phone model.
- `slot-retry-count:b` is read in the bootloader and the phone boots only if it reads 3: refill with `fastboot -s
  <serial> set_active b` alone first (it needs no flash), and read it again. This holds after any recovery reboot
  too. The phone's own shutdown spends a retry (#578), so count it. If the count is not 3 after the refill, flash
  the known-good image set instead of booting. A boot that then leaves fewer than 2 tries ends the series.
- Battery at least 20 %, the hottest thermal zone at most 50 C with the screen off before a boot (the flash limit
  is 62 C, and a hot phone is not the moment to start), PipeWire and WirePlumber stopped and the speaker route off
  (a reboot hung once in `aoc_alsa_remove` while they held the card), no Chromium, backups current, no
  `THERMAL-PAUSE` file.
- A live kernel log: `ssh root@172.16.42.1 'dmesg -w'` (or `journalctl -kf`) into a file on the desktop, started
  before the first command of the stage and kept open through the modprobe and the reads. [U] a record that survives
  a hang or a watchdog reset: the kernel's ramoops with `systemd-pstore` masked for the boot kept one across the
  poweroff restart in #578, but `device/husky/overlays/klog.dtso`'s own header says zuma's bootloader clears ramoops.
  I do not use `klog.dtso` in this series: it sets `omamobile.deadman=20` (the init crashes on purpose if no host
  configures the USB gadget in time, which is a reset and a spent retry), `panic=5`, `clk_ignore_unused` and
  `pd_ignore_unused` (which change the clocks this test is about), and it needs `DETECT_HUNG_TASK`, `WQ_WATCHDOG`,
  `PANIC_ON_OOPS` and `DYNAMIC_DEBUG` in the kernel. The watchdog I have is the 190 s uptime rule below.
- The kernel is a published one, or a branch built from it with the exact commit named.
- Modules: the driver is blacklisted, `blacklist bcm4775x_gnss`, in a file under `/etc/modprobe.d/` that I `cat`
  back before flashing, for every stage up to the one that loads it. `sec_acpm` is blacklisted as well in the stages
  from 3 on (it autoloads at boot because `pmic-1` is on, and the regulator core's one-shot cleanup 30 s after boot
  would switch off any GNSS rail the bootloader left on). Stages 1 and 2 expect it loaded. The file is in the shared
  rootfs: after a recovery from fastboot it is still there, and the next boot of another kernel has no touch until it
  is removed.
- Never open `/dev/ttyBCM`, never write `nstandby` or `sspmcureq`, and never read the driver's debugfs `probe` file.
  Reading `probe` powers the chip, so once the driver is loaded no recursive `grep` or `cat *` anywhere under
  `/sys/kernel/debug`. Pin states come from `/sys/kernel/debug/gpio`, or the driver's `pins` file.

## Stages, one change per boot, each on top of the one before

Each stage is a boot of the same kernel with one more thing changed, ends with its checks, and the next stage starts
only after the previous one passed. The bus is not called `spi21` in sysfs: the number comes from an alias or from
the order of registration, and `spi20` (touch) is already enabled. [V in source] I identify the controller by its
address, `readlink /sys/class/spi_master/spi*/device` ending in the `spi21` node's `reg` (read it from the live
device tree; [I] it is the controller at 111e0000, USI3's own block being 111e00c0), and below `spiN` means the
number I read there.

1. **Plain** (control), nothing enabled. No GNSS controller, no `vdd_gnss` regulator lines, the regulator count
   equals the reference boot's, `sec_acpm` loaded because of `pmic-1`. First boot of a session only, read only:
   `cat /proc/cmdline`; `pacman -Q omamobile-gnss`; a grep of `/etc/modprobe.d`, `/usr/lib/modprobe.d`,
   `/etc/modules-load.d` and `/usr/lib/modules-load.d` for `sec_acpm` and `bcm4775`; `grep -rs ttyBCM
   /etc/udev/rules.d /usr/lib/udev/rules.d /etc/systemd /usr/lib/systemd`; and whether the initramfs carries either
   module [U: how to list it on this image]. Nothing may open `/dev/ttyBCM` the moment the driver creates it: if
   anything like `lhd` or a rule that does is installed, stop here.
2. **Bus**: `usi3_hsi0` and the controller enabled with `num-cs = <1>`, the receiver's node still disabled (the
   controller reads `num-cs` at its own probe, so it belongs to this stage). `/sys/class/spi_master` lists the new
   controller; no new child under `/sys/bus/spi/devices`; the USI3 pclk, ip and source clocks show enabled in
   `clk_summary` (read the command line first: `clk_ignore_unused` would make this prove less); no error from it.
3. **Late `sec_acpm`** (`sec_acpm` blacklisted, `pmic-2` still disabled): the bus DTB of stage 2. Before the
   modprobe, `lsmod | grep sec_acpm` is empty and uptime is past 60 s (the regulator cleanup is one-shot, so after
   that it cannot fire on a late load); note what is missing meanwhile (touch is). Then one `modprobe sec_acpm`,
   and note whether touch comes back. This boot changes only when `sec_acpm` loads, so a failure here is not
   confused with the rails.
4. **Rails** (still blacklisted): `pmic-2` enabled too. Same sequence as stage 3, then read `state`, `microvolts`
   and `num_users` of the three rails, and through the regmap debugfs the S2MPG15 chip ID and the LDO9S to LDO11S
   control registers. [I] the chip ID is register 0x0b and the controls are 0x37 to 0x39 in the `pmic-2` regmaps
   (list `/sys/kernel/debug/regmap/` first and use the names it shows); the 7 Pro's 0x34 to 0x36 are S2MPG13's, do
   not reuse them. Read only. [U] reading a regmap `registers` file reads every register: whether any clears on
   read is not checked, so read `registers` of the three LDOs' regmap only as far as the plan names them.
5. **Receiver**: the node enabled on top of stage 4, `sec_acpm` blacklisted here too. Only if stage 4's reads worked
   and touch came back: repeat the late `modprobe sec_acpm` and the rail reads; check that `lsmod | grep bcm4775x`
   is empty and the node's `spiN.0` is listed; then ONE command, `modprobe bcm4775x-gnss`. After it read the kernel
   log tail, the pin states as above, `ls -l /sys/bus/spi/drivers/bcm4775x-gnss/`, `ls /dev/ttyBCM /dev/bbd_*`, and
   `cat /sys/bus/spi/devices/spiN.0/nstandby` (expect 0; a plain read does not power the chip). Nothing else: the
   chip stays unopened.

## Stop at once

An oops, BUG, panic or hang; no ssh within 90 s of a boot, a visible reboot, or an uptime drop inside the first
190 s; a retry count that is not 3 at a gate (read in the bootloader; the stop is for the boot that follows a refill that did not take); the driver or `sec_acpm` loaded before its manual modprobe; any
`vdd_gnss_*: disabling` line (it means `sec_acpm` loaded early); `sec_acpm` or S2MPG15 errors, or a failing rail or
chip-ID read (do not load the driver); USB or ssh lost when `spi21` probes; a hot phone (over 62 C) or a battery
under 20 %. Between 50 C and 62 C during a stage: finish the reads, do not start the next stage. Touch not back
within 10 s of the late `sec_acpm` is stricter than my earlier runbook, which only noted it: finish the step's
reads, then revert. If ssh still answers, `reboot-to bootloader` first (it spends no try, but the next boot still has to pass the gate:
read 3 or refill); if not, a forced restart (Power + Volume Up for 15 to 30 s, as in `tools/husky-deadman`) and
then Power + Volume Down to the bootloader. A reset loop: bootloader by the buttons and flash from there, never from the resetting system,
and never power-cycle a half-written slot B. Every reset spends one of slot B's three tries.

## Revert

Remove the modprobe file and confirm it is gone, even if it was removed earlier. Flash the plain image set (known
good: `cmp` it against the set and read `DEVICE`, which must say husky), `fastboot -s <serial> set_active b` and
read 3, boot, watch the uptime to 190 s, check `uname -r`, then `modprobe sec_acpm` if it is absent and check touch.
A second boot to prove the normal path goes through `reboot-to bootloader` first, with `set_active b` and a read of
3 again, because two boots from 3 leave 1, and one poweroff restart after that (#578) leaves 0. The phone is left at
the count that read after the last boot: I write it down. The flash goes through `fastboot -s <serial>` after a
check that exactly one device is there, never through a helper that falls back to crashing the running kernel.

## Still unknown (only the phone settles it)

The USI3 gate offsets on hardware; the rail state the bootloader leaves; the chip ID; whether the native chip select
works at 26 MHz as it is; whether touch re-binds after a late `sec_acpm`; whether `swap-mode` and `dma-mode` matter
on this bus; which `pmic-1` consumers are missing while `sec_acpm` waits.
