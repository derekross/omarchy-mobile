<!-- SPDX-License-Identifier: MIT -->
# Pixel 7 (panther) touch: the supplies, then the chip ID

Status (2026-10-27): T0-T3 and T5 passed (T2 stopped on its voltage rule, which T2b fixed): the FT3658 answers with chip ID 0x56 once its supplies are on. T4 (touches) waits for the owner.

The touch controller is a FocalTech FT3658 (chip ID 0x56) on USI0 SPI,
wired as the Pixel 7 Pro's S3908. A local driver
(`drivers/input/touchscreen/focaltech_ft3658.c`, kernel branch
`panther-first-light`) reads only zeros from it. BRINGUP-M1.md (boots 7
and 8) ruled out the driver's timing, the SPI mode and speed, the
controller, the AP/AoC bus select (`gph1-0` reads AP) and the reset line.
What is left are the supplies. This plan switches them on through the
S2MPG12 regulator driver, then reads the chip ID.

## What is known

| Fact | Evidence |
| --- | --- |
| VDD is S2MPG12 LDO25M, AVDD is LDO26M, and the touch controller is their only consumer | stock live DT: `vdd-supply` and `avdd-supply` of `focaltech,ts` are the only references to `S2MPG12_LDO25` and `S2MPG12_LDO26` [V] |
| Stock ranges: LDO25M 1.6-1.95 V, LDO26M 2.5-3.0 V | stock live DT `regulator-min/max-microvolt` [V] |
| The Pixel Fold uses the same two LDOs for its cover touch at 1.8 V and 3.3 V. Panther's stock range for LDO26M stops at 3.0 V, so **felix's voltages are not copied** | `gs201-felix.dts` on `omamobile` [V] |
| On the Fold, ABL leaves both off, and the cover controller answers once its driver enables them | device/felix/NOTES.md, 2026-10-23 [V] |
| On panther, ABL hands the touch over held in reset (`gpp23-2` output low) | BRINGUP-M1.md, boot 8 [V] |
| On panther, ABL leaves LDO25M/LDO26M off | [I], read in T2 |
| Google's power-on: reset low, AVDD on, VDD on, 1 ms, reset high; power-off: reset low, 1 ms, AVDD off, VDD off. No voltage is set | Google's GPL `focaltech_core.c`, `fts_power_source_ctrl()` [V] |
| The S2MPG12 LDO driver exists: linux-omarchy-mobile#27, merged into `omamobile` but not in the `omamobile-int` snapshot. It registered all 28 LDOs read-only on the Pixel 7 Pro, and drives the Fold's cover touch rails | device/cheetah/NOTES.md, 2026-10-23; device/felix/NOTES.md [V] |
| #27's PM regmap can write only the interrupt masks and L1M_CTRL-LDO_CTRL2 (0x2b-0x49); buck control and SW_RESET stay outside | #27, `mfd: sec: s2mpg12: open the LDO control registers` [V] |
| Without `regulator-min/max-microvolt`, the regulator core never sets a voltage; without `regulator-always-on`, a consumer may switch the rail | `drivers/regulator/of_regulator.c` (`apply_uV`, `REGULATOR_CHANGE_STATUS`) [V] |
| The core's unused-rail cleanup runs once, about 30 s after boot, and only switches off rails that are on, unused and switchable | `drivers/regulator/core.c` [V] |

## The changes (local kernel branch, laptop only)

- **K1.** Cherry-pick #27's three driver commits from `omamobile` onto
  `panther-first-light`: `dt-bindings: mfd: samsung,s2mpg12: describe the
  LDO regulators`, `mfd: sec: s2mpg12: open the LDO control registers`,
  `regulator: s2mps11: add S2MPG12 LDOs`. They apply cleanly (checked in
  a temporary worktree).
- **K2. DTS.** `&acpm_ipc { pmic-1 }` as felix's (`samsung,s2mpg12-pmic`,
  GIC SPI 72, `google,vgpio2ap-sysreg`), with only `ldo25m`
  (`vdd-ts`) and `ldo26m` (`avdd-ts`) under `regulators`, **with no
  voltage properties and no `regulator-always-on`**: the PMIC keeps
  whatever voltage it holds. The touch node gets `vdd-supply` and
  `avdd-supply`. The bootargs blacklist `sec_acpm` too, so the regulators
  register only when loaded by hand, after the 30 s cleanup.
- **K3. Driver.** Google's sequence instead of `devm_regulator_bulk_get_enable()`
  (which switches both at once, in no set order): reset held asserted,
  AVDD on, VDD on, 1 ms, release reset, then the 200 ms boot wait. A devm
  action powers off in the reverse order, reset asserted first, so unbind
  never drops the rails under a running chip.
- **K4. Checks.** checkpatch, a W=1 build, and the DTB decompiled: the two
  LDO nodes with no voltage or `always-on` property, the touch supplies,
  `modprobe.blacklist=focaltech_ft3658,sec_acpm`.

## Gates

Slot B's retry budget (BRINGUP-M1.md): three boots per `--set-active`,
and nothing marks the slot successful. T2 is one boot.

### T0. Read-only, before any new image

Hash `efs`, `efs_backup`, `modem_userdata`, `persist`, `modem_a` and
`modem_b` on the phone and compare them with
`~/android/reference/panther-backup-20261026-linux/SHA256SUMS`. The sums
stay out of the repository.

Then read slot B's five boot partitions (boot 8, the last good boot) into
`~/android/mainline/known-good-boot8/`, as the rollback set.

**Pass:** every sum matches. **Stop:** any mismatch. **Risk:** none.

### T1. Build and check the images (laptop)

K1-K4, then `DEVICE=panther bin/omamobile kernel`, `modules`, `images`.

**Pass:** K4's checks. **Risk:** none.

### T2. Boot, then register the regulators read-only

`DEVICE=panther bin/omamobile flash` from fastboot by the buttons (it
restores the retry budget), or `push` if the budget allows. On the
laptop, start a log first: `tools/phone-ssh 'dmesg -w' > <scratch>/t2.log &`.
On the phone, at least 40 s after boot:

```sh
mount -t debugfs none /sys/kernel/debug 2>/dev/null
cat /sys/kernel/debug/regulator/regulator_summary > /tmp/reg-0.txt
modprobe sec_acpm
sleep 2
cat /sys/kernel/debug/regulator/regulator_summary > /tmp/reg-1.txt
diff /tmp/reg-0.txt /tmp/reg-1.txt
grep -A1 -E 'vdd-ts|avdd-ts' /tmp/reg-1.txt
```

**Expect / pass:** `s2mpg12-regulator` binds; `vdd-ts` and `avdd-ts`
appear with no users, their voltages inside the stock ranges (1.6-1.95 V
and 2.5-3.0 V); nothing else in the summary changes; no
`ufshcd_err_handler`; USB and SSH stay up. Record whether the two rails
read **disabled** (the hypothesis) or enabled.

**Stop:** a voltage outside the stock range; any rail other than the two
appearing as switched; a UFS error; USB dropping. Do not load the touch
driver.

**Rollback:** `rmmod` is not used on the PMIC. Flash
`~/android/mainline/known-good-boot8/` to slot B from fastboot.

**Risk:** low. The driver registers the rails and switches none.

### T3. Load the touch driver

```sh
cp /sys/kernel/debug/regulator/regulator_summary /tmp/reg-2.txt
modprobe focaltech_ft3658
cp /sys/kernel/debug/regulator/regulator_summary /tmp/reg-3.txt
diff /tmp/reg-2.txt /tmp/reg-3.txt
dmesg | grep -E 'ft3658|s2mpg12'
```

**Expect / pass:** `FT3658, chip id 0x56, firmware 0x..`; the diff shows
only `vdd-ts` and `avdd-ts` enabled, one user each, voltages unchanged;
a `FocalTech FT3658` input device.

**Stop:** no chip ID (unbind at once, T5); a rail other than those two
changing; a voltage changing; a UFS error; USB dropping; an interrupt
storm (`/proc/interrupts` climbing with no touch).

**Risk:** medium. This is the first write to the PMIC on this phone: the
enable bits of LDO25M and LDO26M, at the voltages the PMIC already holds.

### T4. Touches

Capture `event` of the new input device with `timeout 30 cat
/dev/input/eventN > /tmp/ts.bin` while the owner touches the four
corners, then decode it; then unlock the lock screen with the PIN on the
on-screen keyboard.

**Pass:** the corners read near (0, 0), (1079, 0), (0, 2399),
(1079, 2399); slots go up on release; the lock screen accepts the PIN.

**Stop:** axes swapped or inverted (record and fix in the DT with
`touchscreen-swapped-x-y` / `-inverted-x/y`, a new boot), an interrupt
storm.

### T5. Unbind

```sh
echo spi0.0 > /sys/bus/spi/drivers/ft3658/unbind
grep -A1 -E 'vdd-ts|avdd-ts' /sys/kernel/debug/regulator/regulator_summary
```

**Pass:** both rails disabled, no users; `gpp23-2` low.
**Stop:** either rail still enabled, or another rail changed.

## After the gates

If T3-T5 pass: autoload (drop the two blacklist entries, a boot of its
own), the binding for `focaltech,ft3658`, and the kernel pull request
against `omamobile` (board DTS split by subsystem, new nodes disabled,
the PMIC node as felix's). If T2 shows the rails already **on**, the
supplies were not the cause: stop and go back to the SPI side.

## Results

### 2026-10-27: T0

- `modem_a` and `modem_b` match the 2026-10-26 backup. `efs`,
  `efs_backup`, `modem_userdata` and `persist` do not: boot 6's fallback
  ran stock recovery on slot A, which mounted them. A byte compare against
  the backup shows only F2FS checkpoint areas (`efs`, `efs_backup`,
  `modem_userdata`) and the ext4 superblock and journal (`persist`, which
  now reads "needs journal recovery"); `devinfo` differs in slot B's retry
  byte (0x34) and 0x6e-0x6f. A fresh backup,
  `~/android/reference/panther-backup-20261027-linux`, is the baseline
  from here.
- Slot B's boot 8 images are saved in `~/android/mainline/known-good-boot8/`.

### 2026-10-27: T1

- K1: #27's three commits cherry-picked (`-x`) onto `panther-first-light`.
- K2, K3: two local commits (driver power sequence; the touch supplies).
- K4: checkpatch `--strict` clean; `W=1` builds of `focaltech_ft3658.o`,
  `s2mps11.o` and `sec-acpm.o` with no warning; the DTB has `ldo25m`
  (`vdd-ts`) and `ldo26m` (`avdd-ts`) with no voltage or `always-on`
  property, the touch node's two supplies, and
  `modprobe.blacklist=focaltech_ft3658,sec_acpm`.
- Kernel `7.3.0-rc6-omamobile-push1-g13a1ccd9ae5d` (a new release: its
  modules must be installed before the boot).

### 2026-10-27: T2 (stopped on the voltage rule)

Kernel `7.3.0-rc6-omamobile-push1-g13a1ccd9ae5d`, flashed from fastboot
(before: `slot-retry-count:b` 1, `slot-successful:b` no,
`slot-unbootable:b` no, matching the devinfo bytes). SSH 6.3 s into the
boot; `sec_acpm` and `focaltech_ft3658` not loaded (the blacklist works).

- `modprobe sec_acpm` at 45 s: `s2mpg12-regulator` registered all 28
  LDOs with no users; the regulator summary only gained entries, nothing
  changed or disappeared. No UFS error; USB up. The PMIC's RTC registered
  as `rtc0` and set the system clock, so the clock is right from here.
- **The hypothesis holds:** `vdd-ts` (LDO25M) and `avdd-ts` (LDO26M) are
  **disabled**. ABL leaves the touch supplies off on this phone too; that
  is why the FT3658 read zeros.
- **Stop:** `vdd-ts` holds 1.8 V, inside stock's 1.6-1.95 V, but
  `avdd-ts` holds **3.3 V**, above stock's 2.5-3.0 V. Stock's regulator
  core, with those constraints, lowers it to the range's maximum before
  the touch driver enables it, so on Android the FT3658 runs at 3.0 V
  [I: from the core's `machine_constraints_voltage()`, not measured]. The
  touch driver was not loaded.
- The other LDOs, for the record (read-only): enabled 1M-12M, 14M-18M,
  21M (3.3 V), 27M (3.025 V); disabled 13M, 19M, 20M, 22M-24M, 28M.

### T2b (proposed): AVDD at 3.0 V before it is switched on

One DT change: `regulator-min-microvolt` and `regulator-max-microvolt`
3000000 on `ldo26m` only. When `sec_acpm` registers the rail, the core
moves the selector of `L26M_CTRL` (0x45, bits 5:0, group 5: 1.8 V +
25 mV steps) from 60 (3.3 V) to 48 (3.0 V), with the enable bits (7:6)
untouched and the rail still off. LDO25M stays without constraints.

**Pass:** after `modprobe sec_acpm`, `avdd-ts` reads 3000000 µV and
disabled; nothing else changed. **Stop:** any other value, any other rail
changing. **Risk:** low to medium: the first PMIC write on this phone, one
voltage selector of an LDO that is off and has no other consumer.

### 2026-10-27: T2b

Kernel `7.3.0-rc6-omamobile-push1-g0e2cc7da7352` through `push`; SSH
5.4 s into the boot. `modprobe sec_acpm` at 46 s:
`avdd-ts: Bringing 3300000uV into 3000000-3000000uV`. `avdd-ts` reads
3000000 µV and **disabled**, `vdd-ts` 1800000 µV and disabled, both with
no users. The other 26 LDOs read exactly as in T2. No UFS error, oops or
BUG. **Passed.**

### 2026-10-27: T3

Same boot as T2b. `modprobe focaltech_ft3658`:
`FT3658, chip id 0x56, firmware 0x16` 0.2 s after the load, and the input
device `FocalTech FT3658` (`event1`). The regulator summary changed in
`vdd-ts` and `avdd-ts` only: enabled, one user each (`spi0.0-vdd`,
`spi0.0-avdd`), 1800000 and 3000000 µV as before. One interrupt at the
load, none in the next 5 s with no touch. No UFS error; USB up.
**Passed.** The supplies were the cause.

### 2026-10-27: T4, first try (no result)

A 60 s capture of `event1` came back empty and the interrupt count stayed
at 1: the owner was away and nobody touched the screen. To repeat.

- A read-only register dump from a debug build of the module (not
  committed; loaded with `insmod`, then replaced by the normal module):
  work mode (0x00) 0x00, normal; power mode (0xA5) 0x00, active; monitor
  (0x86) 0x01; heatmap (0x9E/0xED) 1/0, uncompressed, the firmware
  default; continuous report (0xE7) 1; vendor ID (0xA8) 0x8d; the scan
  counter (0x91) climbed 0x2d, 0x40, 0x54 at 100 ms steps. The chip is
  awake and scanning; with no touch it raises no interrupt.

### 2026-10-27: T5

`echo spi0.0 > /sys/bus/spi/drivers/ft3658/unbind`: `vdd-ts` and
`avdd-ts` disabled with no users, `gpp23-2` driven low (reset asserted),
the input device gone, no other rail changed. **Passed.** The driver was
loaded again afterwards, so the phone is left with touch powered.
