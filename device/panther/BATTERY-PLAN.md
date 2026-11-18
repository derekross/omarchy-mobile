<!-- SPDX-License-Identifier: MIT -->
# Pixel 7 (panther) battery: the fuel gauge, then its model

Status (2026-11-15): B0, B1, B1b, the charger (B3.1-B3.3, B3g G1-G2) and D1 passed on 2026-11-01. The gauge runs stock's Coslight 1 kOhm model and reports 4326 mAh, the battery's temperature and a real percentage; upower and the shell show it ([linux-omarchy-mobile#171](https://github.com/derekross/linux-omarchy-mobile/pull/171) and [#170](https://github.com/derekross/linux-omarchy-mobile/pull/170), merged). The charger: device-panther ships its options and blacklist from 0.1.17; the kernel side, the `pmic@66` node, is linux-omarchy-mobile#259, in review.

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

### B3. The charger (medium risk: it rewrites charger settings)

**What it gains, and what it doesn't.** Without a charger driver the
MAX77759 keeps ABL's settings (B3.0 below). Its float voltage is 4350 mV,
so charging ends near 92 %, and nothing applies stock's temperature bands.
Upstream's `max77759_charger`, as on the Pixel 7 Pro (device/cheetah/USB-C-PLAN.md
B3 and B3g), changes three things:
- it charges to 4.45 V (100 %);
- it caps the fast-charge current at 0.3 C;
- with `temp_guard=1`, it applies stock's step-charging bands from the
  gauge's temperature and voltage.

**The input current stays at 500 mA,** the same as ABL's, so with the
screen on the phone can still drain on a laptop's port. More input needs
the Type-C side (B4), so a source can advertise more.

**What is known** (besides the table at the top):

| Fact | Evidence |
| --- | --- |
| ABL hands over: mode 5 (charger and buck), fast charge 1933 mA (CNFG_02 sel 29), float voltage 4350 mV (CNFG_04 sel 35), input 500 mA (CNFG_09 sel 19), protected registers unlocked (CNFG_06 3), JEITA on (CNFG_08 bit 2), USB input selected (CNFG_12 bit 5), no charger watchdog (CNFG_18 0). These are the Pixel 7 Pro's values too | B3.0 below [V]; device/cheetah/USB-C-PLAN.md R0 [V] |
| Stock's bands on panther are the guard's tables exactly: temperatures 0/10/20/42/46/48/55 °C, float voltages 4.2/4.3/4.45 V, and charge currents in % of capacity {30,10,0} {50,30,30} {100,70,50} {80,50,50} {50,50,0} {30,0,0} | stock live DT `google,chg-temp-limits`, `chg-cv-limits`, `chg-cc-limits`; `max77759_charger.c` `guard_temp_decic`, `guard_cv_mv`, `guard_cc_pct` [V] |
| The PMIC at 0x66 interrupts on gpa9-4, low, pulled up | stock live DT `if-pmic-irq` (function 0xf, pud 3, drv 0) [V] |
| The charger is an MFD cell of `pmic@66`, which carries its `monitored-battery`. At probe the driver turns charging off unless it is loaded with `default_ilim_ua`, and then programs the float voltage and current from the battery | the Pixel 7 Pro's `pmic@66` node; `max77759_charger_init()` [V] |
| `tools/usbc-deadman` finds the bus by `10d60000.i2c`, which is panther's too. Before `b3-charger` it saves the charger's registers, and `undo b3-charger` writes them back | `tools/usbc-deadman-phone` [V] |

**The changes:**
- **Kernel** (linux-omarchy-mobile#259; test kernel B3,
  `7.3.0-rc6-omamobile-push1-g801b1e5b4a16`, is D4 plus that commit):
  the `pmic@66` node with its GPIO child, the `if_pmic_int` pin group, and
  the battery's `constant-charge-voltage-max-microvolt` (4450000) and
  `constant-charge-current-max-microamp`. The current is 1266670: 0.3 C of
  4277 mAh is 1283 mA, and the highest charger step at or below that is
  sel 19.
- **Repo:** a bring-up file for the first boot. Later, device-panther ships
  the Pixel 7 Pro's charger options (`default_ilim_ua=500000 temp_guard=1`,
  after the gauge) and blacklists `gpio_max77759`, `nvmem_max77759` and
  `tcpci_maxim`.

**Every gate's rollback** ends in one of two places:
- `tools/usbc-deadman undo b3-charger`, which writes back the registers
  it saved;
- a reboot into a kernel without `pmic@66` (the previous image set by
  fastboot), after which ABL programs its own values again. B3.1 checks
  that this is so.

#### B3.0. Read-only (done)

`i2cget` on 0x69, with no charger driver: see Results.

#### B3.1. The PMIC node, with every MAX77759 module held back (low risk)

**Before the boot:** a bring-up file on the phone,
`/etc/modprobe.d/omamobile-charger-bringup.conf`, that blacklists
`max77759`, `max77759_charger`, `gpio_max77759`, `nvmem_max77759` and
`tcpci_maxim`. Then modules, fastboot and flash.

**Pass:**
- nothing new binds;
- the charger registers read as in B3.0;
- USB, the gauge and the display are unchanged.

**Stop if:** any MAX77759 module loads, or a register changed.
**Rollback:** the previous image set by fastboot.

#### B3.2. The MFD core and its GPIO (low risk)

`tools/usbc-deadman b2-core`, under its dead-man switch.

**Pass:**
- `max77759` binds, with a `max77759-gpio` gpiochip of 2 lines;
- gpa9-4 doesn't storm (`/proc/interrupts` twice, 10 s apart);
- nothing requests GPIO5 or GPIO6.

**Stop if:** an interrupt storm, or USB drops.
**Rollback:** the dead-man reverts by itself; otherwise reboot.

#### B3.3. The charger at a 500 mA input (medium risk)

`tools/usbc-deadman b3-charger --ilim 500000` saves the registers first,
then loads the charger under the dead-man.

**Pass:**
- `dmesg` shows "found: mode 0x5, float voltage 4350 mV …", then "probed:
  mode 0x5, float voltage 4450 mV, fast charge 1266670 uA, input limit
  500000 uA";
- the dump shows CNFG_04 sel 45, CNFG_02 sel 19 and CNFG_09 sel 19;
- `max77759-charger` reports `online` 1 and Charging;
- the gauge's current is positive and at most about 550 mA;
- over 10 minutes the battery warms by less than 5 °C, there are no
  over-current lines, and the link stays up.

**Stop if:** charging stops, the link drops, or the battery warms fast.
**Rollback:** `tools/usbc-deadman undo b3-charger`, then a dump: CNFG_04
should be back at sel 35.

#### B3.4. To full (attended)

Leave the phone on the cable.

**Pass:** the voltage reaches about 4.45 V in CV, then CHG_DTLS 3 or 4
(top-off or done) with the capacity at 100 %.
**Rollback:** as in B3.3.

#### B3g. The temperature guard

As on the Pixel 7 Pro (USB-C-PLAN.md B3g):
- **G0:** JEITA on, read-only. Already seen in B3.0.
- **G1:** `temp_guard=1` at room temperature.
- **G2:** a simulated read failure, with the gauge unloaded for a minute:
  charging must stop.

Hot and cold bands are optional and attended.
**Rollback:** `temp_guard` off, or undo B3.3.

#### D1. By default

device-panther ships the options and blacklists, the bring-up file goes,
and a reboot must bring it all back on its own.
**Rollback:** the previous package, or the bring-up file again.

### Later

- **Type-C (B4, high risk):** TCPM would take over the USB link. It is
  needed for more than 500 mA of input.

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

### 2026-11-01: B3.0

On kernel D4 (`7.3.0-rc6-omamobile-push1-gb118de9c207d`), on the cable,
with no charger driver, `i2cget` on 0x69 only:

| Register | Value | Reading |
| --- | --- | --- |
| CHG_DETAILS_00 (0xb5) | 0x60 | VBUS valid |
| CHG_DETAILS_01 (0xb6) | 0xb4 | CHG_DTLS 4 (done), battery OK |
| CHG_CNFG_00 (0xb9) | 0x05 | mode 5: charger and buck on |
| CHG_CNFG_02 (0xbb) | 0x1d | fast charge sel 29: 1933 mA |
| CHG_CNFG_04 (0xbd) | 0x23 | float voltage sel 35: **4350 mV** |
| CHG_CNFG_06 (0xbf) | 0x0c | protected registers unlocked |
| CHG_CNFG_08 (0xc1) | 0x05 | JEITA on |
| CHG_CNFG_09 (0xc2) | 0x13 | input limit sel 19: 500 mA |
| CHG_CNFG_12 (0xc5) | 0x6a | USB input selected |
| CHG_CNFG_18 (0xcb) | 0x00 | no charger watchdog |

The gauge read 92 %, 4.306 V and -8 mA at 31.7 °C. Charging was done at
ABL's 4350 mV.

### 2026-11-01: B3.1 to B3.3

**B3.1.** Kernel B3 (`7.3.0-rc6-omamobile-push1-g801b1e5b4a16`), flashed
after its modules, with the bring-up file blacklisting every MAX77759
module:
- No MAX77759 module loaded. `1-0066` exists, unbound.
- The charger read exactly as in B3.0, so ABL programs its values again at
  every boot.
- The gauge, USB, the rescue and the display (90 Hz) were unchanged.

**B3.2.** `tools/usbc-deadman b2-core`, confirmed:
- `max77759` and `gpio_max77759` loaded, with a gpiochip of 2 lines
  (GPIO5, GPIO6) that nothing requested.
- The PMIC's interrupt on gpa9-4 stayed at 3 over 10 s.
- `max77759-nvmem` logged "Failed to locate of_node" (no DT node, module
  blacklisted).
- The charger was unchanged, the TCPC read vendor 0x6a 0x0b and
  `USBSW_CTRL` 0x09, and USB stayed up.

**B3.3.** `tools/usbc-deadman b3-charger --ilim 500000`, confirmed:
- **The tool saved** `0xb9 0x05 0xbb 0x1d 0xbd 0x23 0xc2 0x13`.
- **The driver logged** "found: mode 0x5, float voltage 4350 mV, fast
  charge 1933420 uA, input limit 500000 uA", then "probed: mode 0x5, float
  voltage 4450 mV, fast charge 1266720 uA, input limit 500000 uA".
- `max77759-charger` was online and Charging, and the chip locked its
  protected registers.
- **Over ten minutes** on the laptop's port (a ThinkPad T480, USB-A beside
  the RJ45 jack), charging went from CC into CV (CHG_DTLS 1, then 2):
  - `charge_now` rose from 3998 to 4120 mAh, about 730 mA on average,
    which matches the gauge's averaged current (773 falling to 509 mA in
    CV);
  - the capacity rose from 92 to 95 % and the voltage to 4.417 V;
  - the battery warmed from 31.9 to 32.6 °C;
  - there were no over-current or fault lines, and USB and the rescue
    stayed up.
- **Why more than 500 mA came in:** the TCPC's `BC_STATUS1` (0x87) read
  0x02, so BC1.2 detected a CDP port, which may supply 1.5 A, and
  CC_STATUS 0x11 shows Type-C default current. CNFG_09 stays at sel 19 with
  NO_AUTOIBUS 0, so the chip raises the effective input limit to what BC1.2
  found. That is the open K1 point on the Pixel 7 Pro (USB-C-PLAN.md):
  Google's driver sets NO_AUTOIBUS with the limit. It isn't a violation,
  since a CDP port allows 1.5 A, and it is what lets the phone charge with
  the screen on.

### 2026-11-01: B3g (G1, G2)

On the same boot, with the charger loaded by B3.3:

**G1.** After `temp_guard` was set to 1 at runtime, the driver logged
"temperature guard on (max170xx_battery)", then "battery 32.9 C, 4418 mV:
band 20-42 C, float 4450 mV, charge 1266670 uA". Stock's top tier there
allows 50 % of capacity, which the battery's 0.3 C caps. Read back from
the chip: CNFG_04 0x2d (4450 mV), CNFG_02 0x13 (1266.7 mA), mode 5,
CHG_DTLS 2 (CV). Status Charging, health Good, the battery at 98 %.

**G2.** `modprobe -r max17042_battery` for 35 s: the guard logged "no
reading from max170xx_battery: charging inhibited", and the chip went to
mode 4 (buck only) with CHG_DTLS 8 (off). The charger reported
Discharging. After `modprobe max17042_battery` and 65 s, the guard read
33.1 °C and 4373 mV (band 20-42 °C again), the chip was back at mode 5
with CHG_DTLS 2, and the charger at Charging. The gauge kept its model
(`charge_full_design` 4326 mAh, no reload) and read 100 %.

### 2026-11-01: D1 (device-panther 0.1.6)

device-panther 0.1.6 (a local build; its two modprobe files ship from 0.1.17)
was installed on the phone, the charger's bring-up
file deleted, and the phone rebooted on kernel B3. After the reboot:
- `max77759`, `max77759_charger` and `max17042_battery` loaded on their
  own; `tcpci_maxim`, `gpio_max77759` and `nvmem_max77759` did not.
- The driver logged "found: mode 0x5, float voltage 4350 mV, …",
  "temperature guard on (max170xx_battery)", "battery 33.0 C, 4343 mV:
  band 20-42 C, float 4450 mV, charge 1266670 uA", then "probed: mode 0x5,
  float voltage 4450 mV, fast charge 1266720 uA, input limit 500000 uA".
- The chip read CNFG_04 0x2d, CNFG_02 0x13, CNFG_09 0x13 and mode 5. The
  charger was online and Charging, and the battery read 100 %, Charging, at
  32.9 °C.
- The MAX77759 interrupts were quiet over 10 s (the PMIC at 22, the
  charger's CC, CV and top-off events at 3, 3 and 1 from boot).
- USB, the rescue, the gauge and the display (90 Hz, no flip timeouts)
  were unchanged.

### 2026-11-01: the #170 follow-up, and two charger notes

Kernel `7.3.0-rc6-omamobile-push1-gd50ff8bdd671` is kernel B3 plus only
"power: supply: max17042_battery: wait out the alert after a failed read
too" (the sleep moved to a common exit, after derekross's review of
linux-omarchy-mobile#170). It was flashed after its modules.

- **The interrupt:** with the cable out for 15 minutes and the logger
  running, seven alerts (RepSOC reaching 99 % on the cable, then six
  steps down to 93 %) fired the gauge's interrupt once each.
- **The guard after a POR:** the gauge was in POR after the stop in
  fastboot and loaded its model at 5 s, after the charger had probed at
  3.7 s. The guard's first read found nothing and held charging off
  ("charging inhibited", mode 4). Its next read, 30 s later, found 32.5 °C
  and resumed charging (mode 5). On such a boot charging starts about
  30 s late, which is the safe side.
- **BC1.2 after a replug:** after the replug, TCPC `BC_STATUS1` read 0x00
  rather than the 0x02 (CDP) seen at boot. The input limit was therefore
  the register's 500 mA, and with a video playing the battery read
  -50 mA while the charger was in CC. Whether BC1.2 runs again on a
  replug without a Type-C driver is to be checked before the Type-C step.
