<!-- SPDX-License-Identifier: MIT -->
# Pixel 7 (panther) battery: the fuel gauge, then its model

Status (2026-10-31): B0, B1 and B1b passed: the gauge runs stock's Coslight 1 kOhm model and reports 4326 mAh, the battery's temperature and a real percentage; upower and the shell show it. The interrupt bursts are explained and fixed by a driver change (kernel F, below). Kernel: [linux-omarchy-mobile#171](https://github.com/derekross/linux-omarchy-mobile/pull/171) (the gauge and the model) and [#170](https://github.com/derekross/linux-omarchy-mobile/pull/170) (the driver fix), both in review. Next: the charger, later.

The battery level comes from the MAX77759's own fuel gauge ("M5", at 0x36
on USI13). Its I2C bus is enabled since U1 (NOTES.md, 2026-10-29;
[linux-omarchy-mobile#167](https://github.com/derekross/linux-omarchy-mobile/pull/167)).
Upstream's `max17042_battery` drives it (`maxim,max77759-fg`) and, given a
model in the device tree, loads it. The Pixel 7 Pro already runs it that way
(device/cheetah/WIFI-BATTERY-PLAN.md, B1 and B1b). This plan does the
same on panther, in two steps: first the gauge with no model, then the model.
The charger and the Type-C port stay out of it.

[V] is verified on this phone or in the source; [I] is inferred.

## What is known

| Fact | Evidence |
| --- | --- |
| The gauge sits at 0x36 on USI13 (`10d60000`, `i2c-1` on our kernel), with its interrupt on gpa9-3, low, pulled up, and `maxim,rsense-default = <500>` (5 mOhm) | stock live DT (`max77759fg@36`, `if-pmic-fg-irq`: function 0xf, pud 3, drv 0) [V] |
| Stock has three battery models, picked by the battery's ID resistor: 0 kOhm (default), Coslight 1 kOhm (`cos-a1-1k`) and Lishen 3 kOhm (`lsn-a1-3k`), plus a fake-battery one | stock live DT, `maxim,fg-data` [V] |
| This phone's pack is the Coslight 1 kOhm one: the gauge's TempCo (0x39) read 0x1a02 under Google's driver, which is `cos-a1-1k`'s value; `lsn-a1-3k`'s is 0x1802 | the gauge's register dump in this phone's own capture from Android (`~/android/reference/`, not committed) [V] |
| The pack is 4277 mAh, charged to at most 4.45 V (cv limits 4.2/4.3/4.45 V); the models' VEmpty is 0xa561 (3.3 V) | stock live DT: `google,chg-battery-capacity`, `google,fv-max-uv`, `google,chg-cv-limits`, `maxim,fg-params` [V] |
| The gauge is in POR now: Status 0x0082, DesignCap 0x0bb8 (3000), TaskPeriod 0x1680, FullCapRep 0x0b48; VCell 4.30 V, RepSOC about 98 % | B0, below [V] |
| With no `maxim,fg-model`, the driver loads nothing: its init worker runs on POR but has nothing to write, and POR stays set | `max17042_battery.c`, `max17042_init_worker()` [V] |
| At probe, with `shunt-resistor-micro-ohms` and an interrupt, the driver writes only the alert settings: Config's alert enable and SALRT_Th; the interrupt handler clears Status bits other than POR | `max17042_probe()`, `max17042_thread_handler()` [V] |
| Without `shunt-resistor-micro-ohms`, probe would write CGAIN 0, MiscCFG and LearnCFG (voltage-only mode), so the property is required here | `max17042_probe()` [V] |
| The MAX77759 PMIC (0x66) is not described, so the charger, GPIO and NVMEM cells don't bind and charging stays as ABL left it | `gs201-panther.dts` [V] |
| The gauge's interrupt is armed for wake in suspend; on the Pixel 7 Pro this may wake s2idle | device/cheetah/SUSPEND-PLAN.md [V] |

## Gates

### B0. Read-only, before any new image (done)

`i2cget -y 1 0x36 <reg> w` on the running kernel, with no driver bound.
Status, RepSOC, VCell, Current, AvgCurrent, FullCapRep, DesignCap, DevName,
TaskPeriod and FullCapNom only. No PMU registers, no writes.

### B1. The gauge with no model (low risk)

Kernel D = kernel C plus "gs201-panther: add the fuel gauge and the
battery", the first commit of
[linux-omarchy-mobile#171](https://github.com/derekross/linux-omarchy-mobile/pull/171):
the `fuel-gauge@36` node with no model, its interrupt pin, and a
`simple-battery`. One change from C. Modules first (`modules-push`), then a
push or flash.

**Pass:**
- USB, SSH, touch, GPU and haptics as in C.
- `max17042_battery` binds to `1-0036`, with no errors in `dmesg`.
- `/sys/class/power_supply/max77759-fg*` exists, with `voltage_now` about
  3.6-4.4 V, and `capacity` about what B0 read.
- `current_now` changes sign when the cable is pulled (optional: needs the
  user to unplug, and the rescue brings USB back).
- The interrupt on gpa9-3 does not storm (`/proc/interrupts` twice, 10 s
  apart).
- The shell shows a battery.

**Expected:** `temp` is wrong (stuck, as on the Pixel 7 Pro before its
model), `charge_full` is the default model's, and Status keeps POR.

**Stop if:** I2C errors, an interrupt storm, or USB drops.

### B1b. The Coslight 1 kOhm model (low-medium risk: writes the gauge's RAM)

Kernel E = kernel D plus "gs201-panther: give the fuel gauge its battery
model", the second commit of #171. It adds `cos-a1-1k`'s
`maxim,fg-model` (48 words) and `maxim,fg-params` (27 words), as the
Pixel 7 Pro does.

**Where the values come from:**
- They are Google's `gs201-panther-battery-data.dtsi` (GPL,
  `kernel/devices/google/pantah`, `dts/`, branch
  `android-gs-pantah-6.1-android16` at f72c062f05ee, "Update kernel to
  ab/13436313").
- RelaxCfg is 0x143b instead of 0x0839: stock writes that value over the
  model at boot (`maxim,r_regval_1720x = <0x2a143b>` in the live tree).
- FilterCfg 0xc613 is the model's and stock's `filtercfg-default`.
- All three of Google's models (0, 1 and 3 kOhm) match the live tree's
  word for word.

**Why this pack:** TempCo is 0x1a02 in `cos-a1-1k`, 0x223e in
`default-a1-0k` and 0x1802 in `lsn-a1-3k`. The gauge read 0x1a02 under
stock's driver.

**What it writes:** POR is still set after B1, so at probe the driver writes
the model into the gauge's RAM and its parameters, sets LdMdl, waits for
the load, checks FullCapRep against FullCapNom, then clears POR. Everything
it writes is volatile: a POR loses it, and stock's driver loads its own
model on its boot.

**Pass:**
- `dmesg` shows `battery model loaded (DesignCap 0x873, TaskPeriod 0x2d00)`.
- `charge_full_design` reads about 4326 mAh, and `charge_full` is near it.
- `temp` moves away from 22.0 °C toward room or battery temperature.
- `capacity` stays plausible next to B1's.
- No I2C errors and no interrupt storm. Everything from D is unchanged.

**Stop if:** "battery model load failed" or "FullCapRep differs", I2C
errors, or USB drops. In each case the gauge goes on reporting from its
default model, as in B1.

### Later

- **Charger (B3 on the Pixel 7 Pro, medium risk):** with no charger
  driver, the charger keeps ABL's settings: it stopped in top-off at about
  4.33 V (92 %) on the cable, and at CHG_CNFG_09 0x13 its input limit was
  below what the phone drew with the screen on, so the battery drained
  slowly on the cable (86 %, -175 mA, in fast-charge mode). Upstream's
  `max77759_charger` turns charging off until a `tcpm-source` reports a
  source, unless it is loaded with `default_ilim_ua`. The Pixel 7 Pro's
  USB-C-PLAN covers it.
- **Type-C (B4, high risk):** TCPM would take over the USB link.

## Results

### 2026-10-31: B0

On kernel C (`7.3.0-rc6-omamobile-push1-ge57e346e9b71`), on the cable:

| Register | Value | Reading |
| --- | --- | --- |
| Status (0x00) | 0x0082 | POR set: no model loaded |
| RepSOC (0x06) | 0x61dd | about 98 % |
| VCell (0x09) | 0xd712 | 4.30 V |
| Current (0x0a) | 0xff40 | about -60 mA |
| AvgCurrent (0x0b) | 0x0233 | about +176 mA |
| FullCapRep (0x10) | 0x0b48 | 2888 mAh at 1 mAh/LSB (the default model) |
| DesignCap (0x18) | 0x0bb8 | 3000: the default |
| DevName (0x21) | 0x6200 | |
| FullCapNom (0x23) | 0x0b80 | |
| TaskPeriod (0x3c) | 0x1680 | the default |

The same state as the Pixel 7 Pro's gauge before its B1b.

### 2026-10-31: B1

Kernel D (`7.3.0-rc6-omamobile-push1-g549fddfe41cc`), pushed after its modules:

- `max17042_battery` bound to `1-0036` and registered `max170xx_battery`.
  On the cable it read Charging, 99 %, 4.327 V, +169 mA (avg +147 mA),
  health Good, `temp` 22.0 °C (stuck, as expected), `charge_full`
  2912 mAh and `charge_full_design` 3000 mAh (the default model's).
- No I2C errors. The interrupt on gpa9-3 stayed at 0.
- upower: `battery_max170xx_battery`, charging, 99 %, energy-full
  13.06 Wh of 13.35 Wh design. The shell's bar and btop show the battery.
- With the cable out for a minute, btop showed a discharge of about 1.3 W.
  On the replug, `omamobile-usb-rescue` closed the data switch.
  Right after it, the gauge read Discharging at -310 mA, then Charging
  again a little later (+73 mA). The charger read CHG_DETAILS_01 0xb1
  (fast charge, constant current), CHG_CNFG_00 0x05 and CHG_CNFG_09
  0x13, read-only.
- Touch, GPU, haptics, the USB rescue and s2idle are unchanged.

### 2026-10-31: B1b

Kernel E (`7.3.0-rc6-omamobile-push1-ge654d41e556f`), flashed after its
modules (slot B back at 3, then 2):

- `dmesg`: `max17042 1-0036: battery model loaded (DesignCap 0x873,
  TaskPeriod 0x2d00)`, with no "FullCapRep differs" and no I2C errors.
- On the cable it read Charging, 92 % (99 % in B1), 4.326 V, +199 mA (avg
  +144 mA), 33.1 °C (stuck at 22.0 °C in B1), `charge_full` 4324 mAh,
  `charge_full_design` 4326 mAh, `charge_now` 3986 mAh, health Good.
- upower: 92 %, charging, energy-full 19.24 Wh of 19.25 Wh design, 33.1 °C.
  The shell's bar shows 92 %.
- With the cable out for a minute, btop showed a discharge of 1.38-1.67 W.
  On the replug, the USB rescue closed the data switch and the gauge read
  Charging again (91 %, +135 mA).
- **The interrupt on gpa9-3 fires in bursts:** about 1277 times in the first
  seconds (the model load), 0 in the next 10 s, then about 429 more around
  the unplug, then 0 in 15 s. There's no storm, but the cause isn't known.
  It may be the SoC alerts the driver re-arms on each 1 % step, or a Status
  bit the handler leaves set. Check it before suspend work, since the
  interrupt is armed for wake (device/cheetah/SUSPEND-PLAN.md).
- Touch, GPU, haptics and the USB rescue are unchanged.

### 2026-10-31: the interrupt bursts (kernel F)

**Cause.** On kernel E, with the cable out, every 1 % step of RepSOC fired
the gauge's interrupt 424, 429 and 453 times within half a second (92 → 91,
91 → 90, 90 → 89), and Status read 0 after each burst. Nothing fired in
between. AvSOC crossed 92 % several times on the cable without firing,
so the alert isn't AvSOC's. Google's GPL driver for this gauge
(`google-modules/bms`, `max1720x_battery.c`, `android-gs-pantah-6.1-android16`)
explains it at the end of `max1720x_fg_irq_thread_fn()`: "oneshot w/o
filter will unmask on return but gauge will take up to 351 ms to clear
ALRM1", followed by `msleep(500)`. Upstream's handler doesn't wait, so the
level interrupt reran about once a millisecond until the gauge released
ALRT at its next task period (351 ms with the model's TaskPeriod 0x2d00).

**Fix.** "power: supply: max17042_battery: wait out the MAX77759's alert",
[linux-omarchy-mobile#170](https://github.com/derekross/linux-omarchy-mobile/pull/170). On the MAX77759, the thread handler now
sleeps one task period (`TaskPeriod` / 32768 s) after clearing Status.

**Kernel F** (`7.3.0-rc6-omamobile-push1-g51074200c999`, E plus the fix),
pushed after its modules:
- The model survived the reboot: POR was clear, so the driver didn't load it again.
- With the logger running 18 minutes, there were five alerts: RepSOC reaching
  90 % on the cable, then four steps down to 86 % with the cable out (a video
  playing). **Each one fired the interrupt once**, and SALRT_Th followed each
  step.
- Touch, GPU, haptics, the USB rescue and the battery readings are as on E.
- The log is in `~/android/reference/panther-fg-irq/` (not committed).

This affects the Pixel 7 Pro too: it uses the same driver and gauge.
