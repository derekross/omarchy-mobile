<!-- SPDX-License-Identifier: MIT -->
# Pixel Tablet (tangorpro) battery: the fuel gauge and its model

**Status (2026-11-26):** kernel side on linux-omamobile branch `omamobile-tangorpro-battery` (worktree `wt-tangorpro-battery`, output `out-tangorpro-battery`, on top of `omamobile-tangorpro` `caf6d3989`): the MAX77759's I2C bus, on; the fuel gauge with the tablet's 1 kOhm pack model, disabled. In this repository: `overlays/battery.dtso` (turns the gauge on) and `overlays/battery-5k.dtso` (the 5 kOhm pack's model instead). checkpatch `--strict` clean but for the missing human sign-off; `W=1` and `dt-validate` add no warning on the DTB, alone, with `battery`, and with `battery battery-5k`; both models compared word for word with Google's file by script (and `battery-5k.dtso` with `tools/gen-gauge-overlay.py --compare`). **Not run on the tablet yet.** The charger, the Type-C port and the dock stay out of it.

This is the Pixel 7's path ([panther BATTERY-PLAN](../panther/BATTERY-PLAN.md) B0, B1, B1b; Pixel 7 Pro [WIFI-BATTERY-PLAN](../cheetah/WIFI-BATTERY-PLAN.md) B1, B1b), with the tablet's own numbers. Upstream's `max17042_battery` drives the gauge (`maxim,max77759-fg`), with the omamobile patches already on the base branch: the model load on POR, the wait after an alert (linux-omamobile#170, the Pixel 7's interrupt bursts), dSOCi alerts, and the load retry.

[V] verified in the source named; [I] inferred. Nothing here is verified on the tablet.

## Path abbreviations

- `GT/` = Google's tablet DT, `/mnt/data/omamobile/reference/google-tangorpro-dt/dts/` (android.googlesource.com `kernel/devices/google/tangorpro`, branch `android-gs-tangorpro-6.1-android16`, cd669ce "Update kernel to ab/13436313"). GPL-2.0-only.
- `G2/` = Google's shared gs201 DT, `google-gs201-dt/dts/` (`kernel/devices/google/gs201`, same branch, 606d434).
- `L/` = our kernel, branch `omamobile-tangorpro-battery`.

## What is known

| Fact | Evidence |
| --- | --- |
| The tablet takes the MAX77759 unchanged from the shared gs201 files: `GT/gs201-tangorpro-common.dtsi` includes `gs201-cloudripper-battery.dtsi`, and the tablet's own files override only the gauge's model data and the charger's options, never its bus, address, interrupt or sense resistor | `GT/gs201-tangorpro-common.dtsi:10-36`; `GT/...-battery.dtsi:14-19`, `GT/...-charging.dtsi:76-84` [V] |
| Bus USI13 (`10d60000`), 400 kHz, pins gpp25-0/1: fuel gauge 0x36, PMIC 0x66, charger 0x69, TCPC 0x25. **The same as the Pixel 7's** | `G2/gs201-cloudripper-battery.dtsi:134-216`, `G2/gs201-common-typec.dtsi:12-24` [V] |
| Gauge interrupt FG_INT_L on gpa9-3 (XEINT_23), low, pull-up, 2.5 mA; sense resistor `maxim,rsense-default = <500>` (10 uOhm units, 5 mOhm). The same as the Pixel 7's | `G2/...-cloudripper-battery.dtsi:116-121,189-201` [V] |
| PMIC and charger interrupt on gpa9-4; TCPC interrupt on gpa9-7 | `G2/...-cloudripper-battery.dtsi:126,172,216`; `G2/...-common-typec.dtsi:24,120` [V] |
| Two packs, picked by the ID resistor: 1 kOhm (`cos-a1-1k` in the gauge data, `batt-id-1-atl` in the charging tables) and 5 kOhm (`hpt-a1-5k`; `batt-id-5-hpt`). Plus `default-a1-0k`, the fallback for an unknown pack, and a fake-battery model | `GT/...-battery-data.dtsi:10,54,99,143`; `GT/...-battery.dtsi:60,74` [V] |
| `default-a1-0k` and `cos-a1-1k` have the same 48 table words and the same parameters except MiscCfg (0x3830 vs 0x3870). So the 1 kOhm model is also the fallback's | `tools/gen-gauge-overlay.py --compare` on `GT/...-battery-data.dtsi` [V] |
| The two packs differ in DesignCap (1 kOhm 0x0dcc, 5 kOhm 0x0de2), TempCo (0x1102 vs 0x0a02), RComp0 (0x06c0 vs 0x0760), QRTable00/10/30 and 32 of the 48 table words. TGain/TOff (thermistor) and VEmpty are the same | `GT/...-battery-data.dtsi:54-141`; the compare above [V] |
| With TaskPeriod 0x2d00 and 5 mOhm one capacity LSB is 2 mAh: 0x0dcc is 7064 mAh, 0x0de2 is 7108 mAh. The rated pack is 6900 mAh (`google,chg-battery-capacity`) | `GT/...-battery.dtsi:10`; the Pixel 7's B1b (0x873 read as 4326 mAh) [V] |
| VEmpty 0xa05f: empty at 3.20 V, recovery at 3.80 V. Charged to at most 4.4 V (`google,fv-max-uv`; cv limits 4.1 and 4.4 V); the charger's termination voltage is 4350 mV | `GT/...-battery-data.dtsi:78`; `GT/...-charging.dtsi:25,81`; `GT/...-battery.dtsi:28` [V] |
| RelaxCfg: the Pixel 7's live tree had stock write 0x143b over its model's value (`r_regval_1720x`). The tablet's tree has no such property, so the board file keeps the model's 0x2038 | grep of `GT/` and `G2/` [V]; what stock writes at runtime on the tablet [I] |
| No live DT or register capture of the tablet from Android exists yet, so which pack this tablet has is not known | `/mnt/data/omamobile/reference/tangorpro-stock/` has only `getvar all` [V] |
| The bootloader's own reading in fastboot (`getvar all`): battery-soc 97 %, battery-voltage 3916 mV, battery-current 1036 mA, off-mode-charge 1 | `tangorpro-stock/getvar-all.txt` [V] |
| With no `maxim,fg-model` loaded and the gauge in POR, the driver would run on the gauge's defaults; with a model and POR set, it writes the model into the gauge's RAM, loads it and clears POR. With POR clear it writes only the alert settings (Config's alert enable and the SOC alerts) and loads nothing | `L/drivers/power/supply/max17042_battery.c`, `max17042_probe()`, `max17042_init_worker()` [V] |
| Everything the driver writes is volatile: a POR loses it | the binding, `maxim,fg-model` [V] |
| `max17042_battery`, `max77759` and `max77759_charger` are modules (`CONFIG_BATTERY_MAX17042=m`) | `kernel/configs/omamobile.config` [V] |
| The upstream charger's temperature guard is hard-wired to the Pixel 7's tables, with a 4.45 V top tier. **The tablet's top is 4.4 V and its bands differ** (8/17/20/43/53 °C, four bands of {25,25} {50,50} {50,50} {50,0} % of capacity) | `L/drivers/power/supply/max77759_charger.c:62-71`; `GT/...-battery.dtsi:27-34` [V] |

### The dock (pogo pins): noted, not built

The Charging Speaker Dock powers the tablet through the pogo pins, not USB-C. In Google's tree that is the MAX77759's DCIN input, the one the phones use for wireless charging (`max77759,dcin-is-dock`, `dc-psy-type-dock`, power supply `dock`/`dc`). An OVP switch in front of it is enabled by the S2MPG12's GPIO2 (`POGO_OVP_EN_L`, active low), and `POGO_VOUT_SW_EN` on gpp0-2 (active low) switches power out to the pins. `pogo-transport` handles the dock's USB data: status gpa8-3, accessory detect gpa8-2 on LDO26M, mux gpp1-0, hub reset gpp0-0, hub select gpp2-0, hub supply LDO28S. Stock stops charging at 90 % on the dock and resumes at 87 % (`dd-charge-stop-level`, dock defend). Sources: `GT/...-charging.dtsi:20,45-84`, `GT/...-usecases.dtsi:21-23`, `GT/gs201-pogo-transport.dtsi:13-64`.

Whether the dock charges under our kernel depends on what the bootloader leaves in the charger (DCIN enabled or not, in CHG_CNFG_12). That is read in a later step (as the Pixel 7's B3.0), not here. [I]

## What the kernel branch adds

1. **"gs201-tangorpro: enable the MAX77759's I2C bus"**: USI13 as I2C at 400 kHz, no device described. On by default.
2. **"gs201-tangorpro: describe the fuel gauge and the battery"**:
   - `fuel_gauge: fuel-gauge@36` with the interrupt, the pin group `if_pmic_fg_int` (in the base DT: Samsung pinctrl takes groups only at its own probe), `shunt-resistor-micro-ohms = <5000>` (needed: without it the driver writes CGain, MiscCfg and LearnCfg for voltage-only mode), and the 1 kOhm model word for word, **`status = "disabled"`**;
   - a `simple-battery`: 6900 mAh, 4.4 V maximum, 3.2 V empty. It writes nothing to the gauge: `max17042_apply_battery_properties()` acts only on the MAX17055.

The battery current limiter (the Pixel 7's `ec056b384`, `08b049f6d`) is not ported. The tablet includes the same `G2/gs201-cloudripper-bcl.dtsi` and `G2/gs201-pmic.dtsi`, so the lines are the same (vdroop1 gpa5-5, vdroop2 gpa5-6, SMPL_WARN gpa5-0), but no config fragment builds `CONFIG_GS201_BCL`: it needs a line in `device/tangorpro/kernel.config` or `omamobile.config` first.

## Risks

- **Charging: none of these steps changes it** [V]. No charger, PMIC or Type-C node is described, so the MAX77759's charger keeps the bootloader's settings, as now.
- **The charger's JEITA and the gauge's temperature** [I]: the MAX77759's charger may take the battery temperature from the gauge. Before the model, the gauge reports a fixed 22 °C (as on the Pixel 7); with it, the thermistor's reading. Both models share TGain/TOff, so a wrong pack choice doesn't change the temperature. If anything, the charger gains a real temperature.
- **Thermal**: under our kernel nothing limits the charge current for heat but the charger's own JEITA, and there is no dock defend: a docked tablet sits at the bootloader's float voltage. Not acute, but watch the temperature the gauge now reports (stop condition below).
- **Wrong model**: a few percent of state-of-charge error, no damage. It lives in the gauge's RAM until the next POR; stock's driver checks and reloads its own model [I, as on the Pixel 7].
- **Interrupt storm**: the Pixel 7's bursts are fixed on the base branch (#170); still checked.
- **Suspend**: the gauge's interrupt is armed for wake. The tablet's bootargs don't select s2idle, so this matters only for later suspend work.
- **USB**: the gauge doesn't touch the USB link, and the I2C bus alone binds no device.
- **Never** load `max77759_charger` on the tablet with its current guard tables, and never set `temp_guard=1`: they would charge to 4.45 V, above the pack's 4.4 V.

## Runbook (gated; each step needs the human)

The I2C bus number is not fixed. Find it after each boot:
`B=$(basename /sys/bus/platform/devices/10d60000.i2c/i2c-*); echo $B` (prints `i2c-N`; use `N` below as `$N`, e.g. `N=${B#i2c-}`).

### B0. Read-only: the bus, and which pack (risk: low)

**Image:** kernel from `omamobile-tangorpro-battery`, DTB with the overlays the tablet runs now (`DTB_OVERLAYS="touch"`) and **not** `battery`. One change from the running kernel: the I2C bus. Modules first, as usual.

**Commands** (reads only; no `-f`, no `i2cset`):
```sh
dmesg | grep -i -E '10d60000|i2c'
N=$(basename /sys/bus/platform/devices/10d60000.i2c/i2c-*); N=${N#i2c-}
for r in 0x00 0x06 0x08 0x09 0x0a 0x0b 0x10 0x18 0x1d 0x21 0x23 0x2b 0x38 0x39 0x3c; do
  printf '%s %s\n' $r "$(i2cget -y $N 0x36 $r w)"; done
```
(Status, RepSOC, Temp, VCell, Current, AvgCurrent, FullCapRep, DesignCap, Config, DevName, FullCapNom, MiscCfg, RComp0, TempCo, TaskPeriod.)

**Pass:** `10d60000.i2c` probes with no errors; every read answers; DevName reads 0x6200 (the Pixel 7's); VCell (0x09, x 78.125 uV) is 3.5-4.4 V; USB, touch and the display as before.

**Which pack:**
| Status bit 1 (POR) | TaskPeriod | DesignCap | Then |
| --- | --- | --- | --- |
| clear | 0x2d00 | 0x0dcc | 1 kOhm pack (or the fallback, if MiscCfg reads 0x3830): `battery` only |
| clear | 0x2d00 | 0x0de2 | 5 kOhm pack: `battery battery-5k` |
| set | 0x1680 | 0x0bb8 | stock's model is gone and the pack can't be told from the gauge: `battery` only (Google's own fallback table) |

TempCo (0x1102 vs 0x0a02) should agree with DesignCap, but the gauge learns it, so DesignCap decides.

**Stop if:** I2C timeouts or NACKs at 0x36, the bus fails to probe, USB drops. **Rollback:** the previous image set (push or fastboot).

### B1. The gauge with the tablet's model (risk: low-medium; writes the gauge's RAM only if POR is set)

**Before the boot**, on the tablet: `echo 'blacklist max17042_battery' > /etc/modprobe.d/omamobile-battery-bringup.conf`.

**Image:** as B0, plus `battery` (and `battery-5k` if B0 said so). For this pack only, set `DTB_OVERLAYS="touch battery"` (or `"touch battery battery-5k"`) in `device/tangorpro/device.conf`, run `DEVICE=tangorpro bin/omamobile images`, then put the line back (don't commit it). **Expect:** the pack prints `DTB overlays: touch battery`. **Stop:** an overlay fails to apply.

**After the boot:** check nothing bound (`ls /sys/class/power_supply/` has no `max170xx_battery`), then
```sh
grep . /proc/interrupts | grep -i gpa9; modprobe max17042_battery; sleep 5
dmesg | grep -i -E 'max17042|1-0036|-0036'
cd /sys/class/power_supply/max170xx_battery && grep . status capacity voltage_now current_now current_avg temp charge_full charge_full_design charge_now health
sleep 10; grep -i max170xx /proc/interrupts
```

**Pass:**
- `max17042_battery` binds to `N-0036`, registers `max170xx_battery`, no I2C errors.
- If POR was set: `battery model loaded (DesignCap 0xdcc, TaskPeriod 0x2d00)` (0xde2 with `battery-5k`), and no `FullCapRep differs` or `model load failed`. If POR was clear: no load line (the driver keeps stock's model, which is fine).
- `voltage_now` 3500000-4400000 (uV); `capacity` 0-100 and near what B0 read; `charge_full_design` about 7064000 (uAh; 7108000 with `battery-5k`), `charge_full` near it; `temp` a real reading (about 200-400, tenths of °C, not stuck at 220); `current_now` positive on the cable, and negative with the cable out (optional: USB goes with it); `status` Charging or Full on the cable; `health` Good.
- The interrupt fires once per percent step, not in bursts (two reads of `/proc/interrupts` 10 s apart at rest stay equal or one apart).
- upower lists `battery_max170xx_battery`, and the shell shows the level.

**Stop if:** `model load failed` or `FullCapRep differs`, I2C errors, an interrupt storm (hundreds per second), `temp` at or above 430 (43 °C, where stock's charging tables cut back), USB drops.
**Rollback:** `modprobe -r max17042_battery` (the gauge keeps reporting from what it has); the next image without `battery`; the model in the gauge's RAM is harmless and goes at the next POR.

### B2. By default (later)

Once B1 passes on the tablet: a kernel commit drops `status = "disabled"` from `fuel-gauge@36` with B1's results, the bring-up blacklist goes, and a reboot must bring the battery up on its own. If the pack is the 5 kOhm one, the board file takes that model instead.

### Later, not in this plan

- **Charger (B3):** describe `pmic@66` and the charger as on the Pixel 7, but only with tablet guard tables (4.4 V top, four bands) and 0.3 C of 6900 mAh (2070 mA) or less. B3.0, a read-only dump of the charger's registers at 0x69 (as the Pixel 7's), comes first, including CHG_CNFG_12 for DCIN (the dock).
- **Dock charging:** DCIN, the pogo OVP (S2MPG12 GPIO2) and dock defend, above.
- **Battery current limiter:** the Pixel 7's node, once `CONFIG_GS201_BCL` is built.
- **Type-C (B4, high risk):** TCPM would take the USB link.

## Results

None yet.
