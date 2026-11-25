<!-- SPDX-License-Identifier: MIT -->
# Pixel 8 Pro sensors plan (husky, through the AoC)

Status (2026-11-18): stage 0 only. This plan names husky's sensors, the pieces each one needs and the order of the
first runs. Nothing in it has run on a phone apart from one read-only sysfs read (section 1). It changes no
device tree and no package. Sensors need the zuma AoC, which is on test trees only (Lef's, see
[AOC-PLAN](AOC-PLAN.md)), so every stage after 1 waits for that series. Owner: Colin (@gitColinX), agreed with Lef on
[#1](https://github.com/derekross/omamobile/issues/1); Lef will say there when his AoC branch is up as a PR, and
Colin's unit then takes the read-only USF stages as a second unit.

[V] = read in source, in the owner's own stock image or on the phone. [I] = inferred, with the step that would
settle it. [U] = unknown. `linux-omamobile#N` is the kernel repository; a bare `#N` is this one.

The 7 Pro's [AOC-PLAN](../cheetah/AOC-PLAN.md) (stages C6a to C6d) and [USF-PROTOCOL](../cheetah/USF-PROTOCOL.md)
are the protocol reference. The Pixel 9a (tegu) is the template for zuma-family rails, because its AoC already
takes its sensor supplies from the device tree.

## 1. What husky has

The sensors belong to the AoC, as on the 7 Pro, the 6 Pro and the 9a. Linux sees them only through Google's USF
service on `/dev/acd-com.google.usf`. Stock Android's sensor HAL is `sensors.usf.so` plus
`sensors.dynamic_sensor_hal.so` [V: `/vendor/etc/sensors/hals.conf`, CP3A.261005.005].

Parts, buses and interrupts, from the AoC's sensor registry in the owner's vendor image
(`/vendor/etc/sensors/registry`, CP3A.261005.005) [V]:

| Sensor | Part | AoC bus, address | AoC interrupt | Same part on the 7 Pro? |
|---|---|---|---|---|
| Accelerometer, gyroscope (also temperature, motion, stationary and free-fall detect) | TDK ICM45631 | i3c0, static 0x68, I3C 0xa | 43 | no (LSM6DSV) |
| Magnetometer 0 (hidden, fused) | MEMSIC MMC5633NJ | i2c0, 0x30 | none | yes |
| Magnetometer 1 (hidden, fused) | MEMSIC MMC5633NJ | i3c0, static 0x30, I3C 0x14 | none | yes, on another bus |
| Barometer (and temperature) | TDK ICP20100 | i2c0, 0x63 | 47 | yes |
| Ambient light and proximity, under the display | ams TMD3719 | i2c0, 0x39 | 45 | yes |
| Rear spectral, flicker and rear light sensor | ST VD6282 | i2c0, 0x20, and PDM input 4 | none | yes |
| Infrared thermometer | Melexis MLX90632 | i2c0, 0x3b | none | no |

There is no hinge, hall or SAR sensor [V: no such node in any registry file]. The registry also hands the AoC
the touch controller (ST FTM5 on its spi2, interrupt 14) for screen-off tap and long-press gestures, and four
camera VSYNC inputs (interrupts 56 to 59) [V]. The orientation transform of the accelerometer and gyroscope is
`-1 -2 3` [V].

Which registry files apply [V]. The scripts filter on the board's CDT (`0xPPPPSJIV`: product, stage, major, minor,
variant), read from `/chosen/plat`. On Colin's phone, published kernel `82f31d3a7`, that node reads product 2,
stage 6, major 1, minor 0, variant 0, so the CDT is 0x26100 (MP 1.0) [V: sysfs, 2026-11-18]. That selects
`husky_common.reg` (any product-2 board) and `husky_dvt.reg` (product 2 except proto and EVT), plus the two
unfiltered append files. `husky_evt.reg` and the two proto files drop out. The stages differ only in calibration
and tuning values; no part, bus, address or interrupt changes [V]. Unlike the 7 Pro, two files apply at once:
`husky_dvt.reg` adds properties to nodes that `husky_common.reg` creates. `omamobile-sensors` already loads every
`*.reg` file with the board's CDT and lets the AoC filter them, so the loader needs no change for this [V:
`lib/usf.py`, `load_registry`].

Factory calibration list [V: `/vendor/etc/sensors/device_cal_info`]: accel, ALS, baro, gyro, prox, rear light,
spectral. On husky, `persist` is f2fs [V: `file` on the owner's backup of it], so the proxy's read through
`debugfs` returns nothing and no calibration loads. It also logs nothing when that happens [V:
`lib/usf_backend.py`, `factory_calibration`].

Power. Stock's AoC node takes two sensor rails from the S2MPG15 sub-PMIC: `sensor_1v8` = LDO7S `L7S_SENSORS`
(1.60 to 1.95 V) and `sensor_3v3` = LDO5S `L5S_PROX` (2.50 to 3.30 V). Both are boot-on, not always-on [V: stock
dtbo entry "ZUMA HUSKY MP", board_id 0x40206, the same in all eight husky board overlays]. On `omamobile`:

- The S2MPG15 regulator driver already has `ldo5s` and `ldo7s`, added for the 9a [V: kernel 8b8235ec3]. Its
  ranges are wider than stock's (ldo5s 1.8 to 3.375 V, ldo7s 0.7 to 2.275 V), so a husky node must carry stock's
  limits [V].
- `zuma-husky.dts` has `pmic-2` (from `linux-omamobile#211`) disabled, and it describes only the three GNSS
  rails, not ldo5s or ldo7s [V].
- The AoC driver's ordered sensor-supply path (`aoc_sensor_power.c`: 1.8 V on before 3.3 V, off in reverse) is
  matched only for `google,zumapro-aoc` [V]. There is no zuma AoC node, binding or match in the published tree
  [V: `zuma.dtsi` has only the memory carve-out].

So on Lef's test tree the sensors run on whatever the bootloader left on [I: his `&aoc` sets no supplies]. Linux
never touches these rails on husky today.

## 2. What exists to reuse

- `packages/omamobile-sensors` runs unchanged on the 7 Pro, the 6 Pro and the 9a [V: DEVICES, tegu #234/#235,
  raven R5]. It has no board check. It loads the registry, exposes iio-sensor-proxy's D-Bus API (accelerometer
  orientation, light, proximity, compass, gyroscope stream) and drives auto-rotate through `hyprctl`.
- What a phone's device package does for it, on the three phones where it works: its AoC start loads
  `aoc_channel_dev` and waits for `/dev/acd-com.google.usf`; its AoC unit is, or is aliased to,
  `omamobile-aoc.service`, which the proxy `Requires=`; and the registry is staged from the owner's own image by
  `tools/extract-vendor-firmware`, never shipped [V].

What husky's side lacks [V unless marked]:

1. The zuma AoC itself on a published kernel: core, binding, System MMU v9 (Lef's series).
2. `pmic-2` enabled with `ldo5s` and `ldo7s` at stock's limits, and the zuma AoC match taking them as
   `sensor-1v8` and `sensor-3v3` the 9a's way.
3. In `omamobile-device-husky`: an `omamobile-aoc.service` alias for `omamobile-husky-aoc.service`, and a wait
   for `/dev/acd-com.google.usf` in its start script (today it waits for the sound card only).
4. `tools/extract-vendor-firmware -d husky` stages the registry. Today it skips it on purpose ("husky has no AoC
   driver yet").
5. In `omamobile-sensors`, three things to check on husky rather than change blind:
   - the gyroscope rate rounding assumes the LSM6DSV's 15 Hz x 2^n steps;
   - the display state sent to the TMD3719 is fixed at 60 Hz, while husky runs at 120 Hz;
   - factory calibration from an f2fs `persist` needs a read-only f2fs reader (`dump.f2fs`), never a mount.

## 3. Decisions to ask for before any load

- **Touch.** The registry gives the AoC the same FTM5 touch controller that Linux drives, and turns on its
  screen-off gestures and a touch bus negotiator (`/tbn`, mode 2). Linux has no negotiator. For the first load,
  either use a local copy of the registry without `/dev/ftm5/0`, `/tbn` and the `/vsc` gesture enables, or load
  stock's and watch touch closely. Owner of the decision: @derekross, with Lef. [U] whether the AoC's spi2 is the
  same pins as Linux's touch bus.
- **Rails.** The 9a's ordered DT supplies, or stock's `sensor_power_list`, and whether to power-cycle them before
  the first registry load. On the 7 Pro a warm reboot left the rails on and the I3C IMU then never appeared
  (AOC-PLAN C6d, `cycle=1`). husky's IMU and one magnetometer are on I3C too [I: the same can happen]. Owners:
  Lef's zuma AoC series and @derekross.
- **Which sensors to expose.** The proxy exposes accelerometer, light, proximity, compass and gyroscope. The
  barometer, the spectral and flicker sensor and the infrared thermometer stay out of scope here.

## 4. Gates for every stage

- One stage per go-ahead from @derekross, attended, phone on the USB cable. Before each stage read
  `slot-retry-count:b` in the bootloader, and when fewer than two tries are left refill slot B to 3 from there:
  `fastboot -s <serial> set_active b`, as in [SUSPEND-PLAN](SUSPEND-PLAN.md) and [GNSS-PLAN](GNSS-PLAN.md).
- Read-only first. A registry load happens at most once per AoC boot: the AoC probes its sensors only then, and a
  failed probe stays failed until the AoC restarts, which means a reboot [V: cheetah AOC-PLAN C6b to C6d].
- The proxy stays out of the boot until S4 has passed: `omamobile-sensors` is not installed yet, or
  `omamobile-sensor-proxy` is masked (`systemctl mask omamobile-sensor-proxy`). The proxy `Requires=`
  `omamobile-aoc.service` and `omamobile-sensors` ships its own wants link [V: `packages/omamobile-sensors/install`],
  so once the device package has that alias (section 2, item 3) and `omamobile-sensors` is installed, the proxy
  loads the registry at every boot. S3 does one `RegistryGet` with no load and S4 makes the one attended load, so
  both need the proxy masked or not installed.
- Never start the AoC twice. On the 7 Pro a second firmware write took it down until a reboot [V: C6c]. Always
  start it through the unit.
- No `rmmod` of AoC modules, no `devmem`, no PMU or AoC register reads from user space [V: cheetah AOC-PLAN; husky
  AOC-PLAN: a PCU read reset the phone].
- `persist` and Google's files stay private: staged only by the tool from the owner's image, never committed,
  never pasted. Any trimmed registry copy stays on the owner's PC and phone.
- UI sensors use the non-wakeup channel only, so a sensor never blocks suspend.
- Any PMIC rail work needs the read-only modem and calibration backup first (`tools/nv-backup -d husky --check`).
- The same AoC carries the speakers and microphone. Every stage checks sound afterwards, and a failed load costs
  sound until a reboot.

## 5. Stages

- **S0, offline (done 2026-11-18).** The registry, `hals.conf`, `device_cal_info` and the AoC's `.rc` files read
  from the owner's factory image on the PC; the stock rails read from its dtbo. Results are in section 1.
- **S1, read-only on the published kernel (done 2026-11-18).** `/chosen/plat` reads CDT 0x26100. Nothing else
  can be read before an AoC kernel.
- **S2, rails, read-only.** After `pmic-2` is enabled for GNSS (GNSS-PLAN stage 3) or by an overlay that enables
  it and nothing else: read S2MPG15 `L5S_CTRL` (0x33) and `L7S_CTRL` (0x35) through the regmap debugfs, after a
  cold boot and after a warm reboot, before the 30 s regulator cleanup and after it. Settles whether the bootloader
  leaves them on. The read needs only `pmic-2` enabled: the sub-PMIC's regmap already allows reads of both
  registers whether or not the device tree describes the rails [V: `drivers/mfd/sec-acpm.c`,
  `s2mpg15_regmap_config_pmic`]. An overlay that describes `ldo5s` and `ldo7s` just to read them is not read-only:
  a described rail with no consumer is switched off by the regulator core about 30 s into the boot [V:
  `drivers/regulator/core.c`, `regulator_late_cleanup`]. So the two rails stay undescribed until the AoC node takes
  them as supplies; the cleanup acts only on registered regulators, and the S2MPG15 driver registers only the
  rails the device tree describes [V: `drivers/regulator/s2mps11.c`, `s2mpg14_regulator_is_described`].
- **S3, the AoC test kernel, read-only.** On a kernel with Lef's zuma AoC: the AoC's services list includes
  `com.google.usf` (94 services expected on CP3A firmware), `/dev/acd-com.google.usf` and its `.non_wake_up` twin
  exist, and one `RegistryGet("/")` through `omamobile-usf`, with no load. Then sound still plays.
- **S4, one registry load.** Proxy masked or not installed (section 4). Rails on (and cycled if section 3 says
  so), then `omamobile-usf` loads the agreed registry once, with CDT 0x26100. Pass: the sensor list holds the
  ICM45631 accelerometer and gyroscope, the TMD3719 light and proximity, and the fused compass; touch still works;
  sound still plays. Fail or a partial list: stop, reboot, report.
- **S5, the proxy and auto-rotate.** `omamobile-sensors` with the alias and the start-script wait, and the proxy
  unmasked (`systemctl unmask omamobile-sensor-proxy`) if it was masked. Pass:
  `monitor-sensor` shows orientation, light and proximity changing as the phone turns and is covered; the rotation
  tile turns the display and the touch transform together (upright, left, right, upside down), with axes checked
  against the `-1 -2 3` transform; the gyroscope stream's reported rate matches what arrives.
- **S6, sleep with the proxy running.** One s2idle with the proxy up and nothing claiming a sensor (after
  SUSPEND-PLAN H4): no wakeups from the sensor channels, and sensors back after the wake.

## 6. Stop at once

An empty or partial physical sensor list after a load; any USF error; touch dead or doubled after a load; sound
gone; the AoC offline; a reboot or a hang. The only recovery is a reboot. Before the next boot, mask the proxy
(`systemctl mask omamobile-sensor-proxy`: `omamobile-sensors` ships its own wants link, which `disable` leaves in
place, so the next boot would start the proxy and load the registry again) and leave the registry unloaded until
the cause is read.

## 7. Still unknown

- [U] Whether Lef's zuma AoC test branch creates the USF nodes through `aoc_channel_dev` on husky.
- [U] Whether the AoC firmware needs the display's panel properties before it probes the TMD3719, and whether
  husky's panel needs an entry in the proxy's panel table.
- [U] Whether the AoC tick is still 24.576 MHz on zuma (the proxy falls back to the USF time server).
- [U] The calibration file names in husky's `persist` (listable offline from the owner's `persist` backup with an
  f2fs tool, without touching the phone).

## Results

- 2026-11-18, Colin's phone (published `82f31d3a7`, device-husky 0.1.16): S0 and S1 as above.
