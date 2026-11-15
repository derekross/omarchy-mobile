<!-- SPDX-License-Identifier: MIT -->
# Pixel 8 Pro GNSS plan (husky, Broadcom BCM4775x on spi21)

Status (2026-11-15): nothing of this has run on the phone, and I have no record that the chip has ever been powered.
This is the runbook @derekross asked for on
[linux-omarchy-mobile#239](https://github.com/derekross/linux-omarchy-mobile/pull/239) before the bring-up overlay:
what the first boots do, in which order, and what stops them. It changes no device tree and runs nothing.
Changed on 2026-11-15 after his review on #739: `sec_acpm` is built in, so the late-load stage and its blacklist are
gone, and stages 2 to 4 run with the SoC watchdog armed, except stage 3's first read, which is before the 30 s cleanup
and so before the watchdog can be armed (only the panics cover it).

[V] = read in source, in a maintainer's comment or in a capture of mine. [I] = inferred, with the step that would
settle it. [U] = unknown. References like `linux-omarchy-mobile#210` are the kernel repository; a bare `#578` is
this one.

## Where it stands

- The bus: `linux-omarchy-mobile#210` (merged) added the CMU_HSI0 USI3 clocks and a disabled `spi21` in
  `zuma.dtsi`. [I] the gate offsets are Google's and have not been exercised on hardware; a wrong one can hang the
  phone. The controller's probe in stage 2 and a first transfer settle it, not a clock listing: the published
  bootargs carry `clk_ignore_unused` and `pd_ignore_unused` [V: `zuma-husky.dts`, and `VENDOR_CMDLINE` in
  `device/husky/device.conf`], so the clocks can be on without the controller having enabled them.
- The rails: `linux-omarchy-mobile#211` (merged) added the S2MPG15 sub-PMIC as `pmic-2`, disabled, with the three
  GNSS rails (LDO9S core 725 to 1300 mV, LDO10S RF and LDO11S AUX 1600 to 1950 mV). [V] zuma-husky.dts on
  `omamobile` says that stock keeps them always on, so nothing sets a voltage at probe and the GNSS driver will
  switch them. [V] `sec_acpm` is built in: `kernel/configs/omamobile.config` has `CONFIG_MFD_SEC_ACPM=y` (since
  #227, for the 9a's USB PHY rails) and the kernel's defconfig has `CONFIG_REGULATOR_S2MPS11=y`. So once `pmic-2`
  is enabled the three rails register at boot, and the regulator core's cleanup, 30 s after late init, turns off
  any of them that is on and has no consumer. A `blacklist sec_acpm` does nothing, `lsmod` never lists it and
  `modprobe sec_acpm` is a no-op. The 7 Pro is the same (the unused-rails gotcha in `AGENTS.md`), and it is
  harmless there because LDO9S to LDO11S feed only GNSS; the board file's comment names husky's three as the GNSS
  core, RF and AUX rails too.
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
- Whether the bootloader leaves the three GNSS rails on is [U]; stage 3 answers it.

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
  configures the USB gadget in time, which is a reset and a spent retry) and `panic=5`, and it needs
  `DETECT_HUNG_TASK`, `WQ_WATCHDOG`, `PANIC_ON_OOPS` and `DYNAMIC_DEBUG` in the kernel.
- The watchdog, for stages 2, 3 and 4. The 190 s uptime rule below is a stop, not a reset: [V] the watchdog driver
  stops the bootloader's watchdogs (the comment over the bootargs in `zuma-husky.dts`, BRINGUP-M1 test 19), so a
  hang that does not panic lasts until the buttons. Two things reset the phone by themselves:
  - Panics. [V] the published bootargs have `panic=10 softlockup_panic=1 nmi_watchdog=panic
    sysctl.kernel.panic_on_rcu_stall=1`, and `device/husky/kernel.config` builds the soft and hard lockup
    detectors. An oops that panics, a soft or hard lockup and an RCU stall end in a reset 10 s later. I read
    `/proc/cmdline` in stage 1 to see them on the phone.
  - The SoC watchdog with a feeder. Before the first command of the stage I run `tools/husky-deadman noop --soak
    <seconds>` on the desktop, in its own terminal. [V in the tool's source] it copies `tools/husky-deadman-phone`
    to the phone, streams `/dev/kmsg` to `logs/`, and starts `husky-deadman-phone run noop` detached; that opens
    `/dev/watchdog0` and feeds it every 2 s, and `noop` applies nothing. The desktop half confirms over a new ssh
    login; with no confirmation in 90 s and a 60 s grace the phone stops feeding on purpose and resets, so the
    stage's commands start only after the `confirmed` line. If the feeder or all of userspace stops, the watchdog
    resets the phone (the tool says in about 15 s; per derekross's review its `wd-drill` reset a Pixel 8a in 26 s
    in akita's test 43; [U] the time on husky, I found no drill time for it in the tree).
  - Stopping it: the tool has no stop command. The feeder runs for the soak, then writes the magic close and logs
    `watchdog: disarmed`, and the result reads `soaked`. So the soak is set longer than the stage's reads (600 s
    is the default), and after the reads I wait for `soaked` and that log line before the reboot to the
    bootloader. A `refused`, `tripped` or `failed` result means no watchdog: the stage does not start, or stops.
    [U] whether `noop`'s checks pass on the stage's image: they want the `10cb0000.i2c` bus, `i2c-tools`, the
    gauge's power supply and a configured gadget, and its guard reads the battery every 2 s.
  - Not covered: a freeze of every CPU. The lockup detectors need a CPU that still runs, and I count the watchdog
    out too (derekross's review; BRINGUP-M1 test 24 had every CPU stop on this phone, and neither the panic nor
    the fallback reset it). Only the buttons undo that: Power + Volume Up for 15 to 30 s. Also not covered by the
    watchdog: the boot before it is armed and the time after it is stopped; there only the panics act.
  - Every one of these resets spends one of slot B's tries, like any other.
- The kernel is a published one, or a branch built from it with the exact commit named.
- Modules: the driver is blacklisted, `blacklist bcm4775x_gnss`, in a file under `/etc/modprobe.d/` that I `cat`
  back before flashing, for every stage up to the one that loads it. Nothing else is blacklisted: `sec_acpm` is
  built in, so a blacklist line for it would do nothing. The file is in the shared rootfs: after a recovery from
  fastboot it is still there, until the revert removes it.
- Never open `/dev/ttyBCM`, never write `nstandby` or `sspmcureq`, and never read the driver's debugfs `probe` file.
  Reading `probe` powers the chip, so once the driver is loaded no recursive `grep` or `cat *` anywhere under
  `/sys/kernel/debug`. Pin states come from `/sys/kernel/debug/gpio`, or the driver's `pins` file.

## Stages, one change per boot, each on top of the one before

Each stage is a boot of the same kernel with one more thing changed, ends with its checks, and the next stage starts
only after the previous one passed. The bus is not called `spi21` in sysfs: the number comes from an alias or from
the order of registration, and `spi20` (touch) is already enabled. [V in source] I identify the controller by its
address, `readlink /sys/class/spi_master/spi*/device` ending in `111e0000.spi`: [V] the node is `spi21:
spi@111e0000` with `reg = <0x111e0000 0xc0>`, inside `usi3_hsi0: usi@111e00c0` (`zuma.dtsi`). Below `spiN` means
the number I read there. The earlier draft's stage 3 (a late `modprobe sec_acpm`) is dropped, because the driver is
built in and the stage would have passed without testing anything; its stages 4 and 5 are 3 and 4 here.

1. **Plain** (control), nothing enabled. No GNSS controller, no `vdd_gnss` regulator lines, the regulator count
   equals the reference boot's. First boot of a session only, read only: `cat /proc/cmdline` (the panic
   arguments above must be there); `grep sec-acpm /lib/modules/$(uname -r)/modules.builtin` (it must list it: the
   running kernel has the driver built in); `pacman -Q omamobile-gnss`; a grep of `/etc/modprobe.d`,
   `/usr/lib/modprobe.d`, `/etc/modules-load.d` and `/usr/lib/modules-load.d` for `bcm4775`; `grep -rs ttyBCM
   /etc/udev/rules.d /usr/lib/udev/rules.d /etc/systemd /usr/lib/systemd`. [V] the initramfs carries no module:
   `device/husky/device.conf` sets no `INITRAMFS_MODULES`, and `bin/omamobile` packs only what that names. Nothing
   may open `/dev/ttyBCM` the moment the driver creates it: if anything like `lhd` or a rule that does is
   installed, stop here.
2. **Bus**: `usi3_hsi0` and the controller enabled with `num-cs = <1>`, the receiver's node still disabled (the
   controller reads `num-cs` at its own probe, so it belongs to this stage). Watchdog armed first. The proof is
   the probe: `/sys/class/spi_master` lists the new controller, bound to its driver, with no error from it in the
   log; no new child under `/sys/bus/spi/devices`. I still note the USI3 pclk and ip lines of `clk_summary`, but
   with `clk_ignore_unused` in the bootargs they do not show who enabled the clocks. The first transfer comes with
   the receiver's driver at the earliest ([U] whether its probe transfers anything while the chip is in standby).
   Covered here: a lockup or stall at the probe (panic, reset), a dead userspace (watchdog). Not covered: the
   probe itself runs at boot, before the watchdog is armed, so a gate that freezes every CPU there needs the
   buttons.
3. **Rails**: `pmic-2` enabled too. The rails register at boot, so the first command is one ssh line with a
   deadline: the model check, `cat /proc/uptime` and the `state` of the three `vdd_gnss_*` regulators, before 30 s
   of uptime (the cleanup runs 30 s after late init). It comes before the watchdog because arming takes longer
   than the time left; only the panics cover it. [U] whether ssh answers that early: if the uptime it prints is
   past 30 s, the read is late and I say so. Then the watchdog, then after the cleanup `state`, `microvolts` and
   `num_users` of the three rails again, and the kernel log. A `vdd_gnss_*: disabling` line is not a stop: it is
   the answer to what the bootloader leaves (the rail was on with no consumer, and the core turned it off); no
   line for a rail means it was already off, or its state could not be read. After a `disabling` line the rail is
   off with no user, and stage 4's driver switches it. Then, through the regmap debugfs, the S2MPG15 chip ID and the LDO9S
   to LDO11S controls: [V] the chip-ID register is 0x0b in the `common` map and the controls are 0x37 to 0x39 in
   the `pmic` map (`include/linux/mfd/samsung/s2mpg15.h`; the value of the ID is [U] until read). List
   `/sys/kernel/debug/regmap/` first and use the names it shows; the 7 Pro's 0x34 to 0x36 are S2MPG13's, do not
   reuse them. Read only. [V] reading these `registers` files clears nothing: in `drivers/mfd/sec-acpm.c` the
   S2MPG15 read tables hold only the chip ID (`common`) and seven LDO control registers (`pmic`: 0x33, 0x35, 0x37
   to 0x39, 0x3a, 0x3d), with `REGCACHE_NONE`, so the file reads those from the chip and nothing else. Covered: a
   lockup in a read (panic), a dead userspace (watchdog). Not covered: the PMIC's probe and the cleanup's writes
   at boot before the watchdog is armed, beyond the panics, and a freeze of every CPU.
4. **Receiver**: the node enabled on top of stage 3. Only if stage 3's reads worked. Watchdog armed first, then
   repeat the rail reads; check that `lsmod | grep bcm4775x` is empty and the node's `spiN.0` is listed; then ONE
   command, `modprobe bcm4775x-gnss`. After it read the kernel
   log tail, the pin states as above, `ls -l /sys/bus/spi/drivers/bcm4775x-gnss/`, `ls /dev/ttyBCM /dev/bbd_*`, and
   `cat /sys/bus/spi/devices/spiN.0/nstandby` (expect 0; a plain read does not power the chip). Nothing else: the
   chip stays unopened. Covered: an oops, lockup or stall in the driver's probe (panic, reset in 10 s), and a hang
   that leaves the kernel alive but stops userspace (watchdog). Not covered: a probe that freezes every CPU, which
   only the buttons undo.

## Stop at once

An oops, BUG, panic or hang; no ssh within 90 s of a boot, a visible reboot, or an uptime drop inside the first
190 s; a retry count that is not 3 at a gate (read in the bootloader; the stop is for the boot that follows a refill that did not take); the driver loaded before its manual modprobe; a
watchdog that does not arm, or a `refused`, `tripped` or `failed` result from the tool; `sec_acpm` or S2MPG15
errors, a `couldn't disable` line, or a failing rail or chip-ID read (do not load the driver); touch gone after
`pmic-2` is enabled; USB or ssh lost when `spi21` probes; a hot phone (over 62 C) or a battery under 20 %. Between
50 C and 62 C during a stage: finish the reads, do not start the next stage. A `vdd_gnss_*: disabling` line is
not a stop (stage 3). If ssh still answers, `reboot-to bootloader` first (it spends no try, but the next boot still has to pass the gate:
read 3 or refill); if not, a forced restart (Power + Volume Up for 15 to 30 s, as in `tools/husky-deadman`) and
then Power + Volume Down to the bootloader. A reset loop: bootloader by the buttons and flash from there, never from the resetting system,
and never power-cycle a half-written slot B. Every reset spends one of slot B's three tries.

## Revert

Remove the modprobe file and confirm it is gone, even if it was removed earlier. Flash the plain image set (known
good: `cmp` it against the set and read `DEVICE`, which must say husky), `fastboot -s <serial> set_active b` and
read 3, boot, watch the uptime to 190 s, check `uname -r` and touch.
A second boot to prove the normal path goes through `reboot-to bootloader` first, with `set_active b` and a read of
3 again, because two boots from 3 leave 1, and one poweroff restart after that (#578) leaves 0. The phone is left at
the count that read after the last boot: I write it down. The flash goes through `fastboot -s <serial>` after a
check that exactly one device is there, never through a helper that falls back to crashing the running kernel.

## Still unknown (only the phone settles it)

The USI3 gate offsets on hardware; the rail state the bootloader leaves; the value of the chip ID; whether the
native chip select works at 26 MHz as it is; whether `swap-mode` and `dma-mode` matter on this bus; whether ssh is
up before the regulator cleanup; how long the watchdog takes to reset this phone, and whether `husky-deadman`'s
`noop` checks pass on these images.
