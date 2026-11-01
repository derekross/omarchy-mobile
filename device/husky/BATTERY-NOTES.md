<!-- SPDX-License-Identifier: MIT -->
# Pixel 8 Pro (husky) battery, charging and USB-C: bring-up notes and results

Last updated: 2026-11-01. One phone, one person (Lef), one day of hands-on tests, written up in full so that others can check it and reuse it. Everything here is tagged:

- **Verified** means it was read from a file, a log or the phone and the source is named.
- **Not verified** means it is an inference, or comes from memory of a datasheet, and says what would settle it.

Nothing in this document contains a serial number, IMEI, MAC address, IP address of a person's network, or a Wi-Fi name. Raw partition backups exist locally and are never published.

## 1. Where things stand

| Item | State on 2026-11-01 |
| --- | --- |
| I2C bus hsi2c_11 (USI11, CMU_PERIC1) | Works. Needs kernel #163 and a bring-up overlay. |
| Fuel gauge (0x36, `max17042_battery`) | Works: percentage, voltage, current, temperature, in the status bar, the home widget and UPower. |
| Gauge battery model | Google's ATL model (the pack's real ID, read from its EEPROM), loaded through an overlay. The temperature reads about 35 C and moves; replacing the fallback model with the right one dropped the reported level by 10 points (section 5.6). |
| MFD core (PMIC at 0x66, `max77759`) | Binds, no interrupt storm, loads at boot. |
| Charger (0x69, `max77759_charger`) | Loaded by hand under a dead-man tool, three runs: 500 mA and 900 mA on a desktop USB port, and a wall charger. The driver charges the battery, slowly (see section 7). |
| Type-C controller (0x25, `tcpci_maxim`) | No driver loaded: it stays disabled and blocked. The only access to the chip is its USB data switch register (0x25:0x93), read and written by the rescue service (section 8). |
| USB link across an unplug | Lost until a reboot, because the Type-C chip opens the USB data switch. Fixed with `omamobile-usb-rescue`. |
| Slot B boot retries | A hazard: each boot of slot B uses one retry (3 after a flash or `set_active`), and when they run out the bootloader falls back to GrapheneOS, whose first boot wiped `userdata`. A cure exists (section 9). |
| PCA9468 direct charger (0x57) | No mainline driver. Not touched. |
| Charge-limit step table, JEITA, a reset restoring the charger registers, why charging is so slow | Open. See section 11. |

## 2. Hardware, as found

All of this is from Google's stock device tree (a copy of the GrapheneOS husky images; the Pixel 8 Pro's own overlay is `ov8.dts`, the retail MP one with the 4950 mAh pack; `ov16.dts` is the Pixel 8 with a smaller pack and different ATL, COS and LSN model nodes, do not use it for husky), Google's GPL kernel source (`android-gs-shusky-6.1-android16` for the clocks, the shusky `bms` repository for the gauge) and reads on the phone.

- **Bus:** hsi2c_11 at 0x10CB0000, GIC SPI 659, on USI11 at 0x10cb00c0. USI11 needs CMU_PERIC1 at 0x10c00000 and the PERIC1 sysreg at 0x10c21000 (SW_CONF at offset 0xc). Pins gpp21-0 and gpp21-1.
- **Devices on the bus:** fuel gauge 0x36 (`maxim,max77759-fg`, interrupt gpa7-7), PMIC 0x66 (`maxim,max77759`, interrupt gpa8-0), the charger's registers at 0x69 (a dummy I2C client created by the PMIC driver), the Type-C controller 0x25 (interrupt gpa8-3), and a PCA9468 direct charger at 0x57 with no driver.
- **Chip identity:** the PMIC driver binds only if `PMIC_ID` is 59 (0x3b). Read back on the phone: PMIC_ID 0x3b, PMIC_REVISION 0x02, OTP_REVISION 0x31. So the chip at 0x66 is a MAX77759, not the MAX77729 that Google's device tree names on the same interrupt.
- **Pack:** 4950 mAh in our device tree (`simple-battery`). The pack's EEPROM says ATL (section 5.6). Husky's ATL model carries a design capacity of 0x09cf, which the gauge reports as 5,022,000 uAh (0.5 mAh per unit), and its fallback model `default-a1-0k` 0x0994 (4,904,000 uAh). With the ATL model loaded the kernel reports `charge_full` 4,978,000 uAh and `charge_full_design` 5,022,000 uAh.
- **Bootloader state at boot (before any Linux driver):** charger mode 0x5 (charge and buck on), float voltage 4350 mV, fast charge 1,933,420 uA, input limit 500 mA. Read from the register dump and from the charger driver's own probe line.
- **Stock charging steps:** 4.20, 4.30, 4.35 and 4.48 V by temperature (`google,chg-cv-limits`, edges at 0, 10, 20, 42, 46, 48, 55 C). Our device tree is deliberately more conservative: 4.2 V and 0.3 C (1.485 A). Raising it needs a review (section 11).

## 3. Safety model used

These notes follow CONTRIBUTING sections 3.1 to 3.6. In short: back up first, read before write, one change per boot where possible, a way back at every step, and a person at the phone for anything that charges.

- **Backups.** A read-only backup of ten partitions (`persist`, `modem_a`, `modem_b`, `efs`, `efs_backup`, `modem_userdata`, `devinfo`, `pinfo`, `trusty_persist`, `trusty_userdata`) was taken in the guarded initramfs before the battery work and again after the only Android boot of the day, each copy accepted only if its SHA-256 equalled one computed on the phone from the partition. Several partitions differ between the backups, as they do after any Android boot. They hold IMEI and serials and are never published.
- **Rollback.** Every flashed image set was copied to a `known-good` directory first, so any step can be undone with `omamobile flash` of the previous set.
- **Rule on userspace register access (AGENTS.md section 1).** The rule is about the SoC's own PMU registers, which are secure-only. This work never used `devmem` or `debugfs/regmap`. It did read and write registers of the external MAX77759 chips over I2C with `i2cget` and `i2cset`, for the dead-man tool, the USB rescue and the gauge tests in section 6. That is what cheetah's and raven's tools already do, and it is listed here so nobody has to find it.
- **One change per boot.** Mostly kept. The exceptions: the panel-size overlay (for the on-screen keyboard) rode along with the battery overlay in one boot, and the gauge-model overlay and the pull-up test overlay were separate boots. Said here for honesty, not as a recommendation.

## 4. Runbook and results, step by step

Each step is: what, expected result, stop condition, rollback. Kernel: Brett's c6 plus the four battery commits of kernel #163, booted release `7.3.0-rc6-omamobile-push1-gc7a0b2ef2f66-dirty`. (`c7a0b2ef2` is Brett's c6 commit. The four commits were applied before the build and committed afterwards, hence "dirty". The same four commits are `husky-battery-i2c` in the published kernel branch.)

**M1, read-only baseline.** Expected: no I2C devices, no power supply, no PERIC1 nodes. Result: as expected.

**M2, boot the new kernel with the nodes disabled.** Expected: nothing changes. Result: booted first time, no failed units; `cmu_peric1`, sysreg and USI11 nodes present, disabled.

**M2b, clocks only** (overlay enabling CMU_PERIC1 and the sysreg). Result: the PERIC1 clock tree comes up as Google's tables say (peric1_noc 532.992 MHz, divided to 66.624 MHz for the NoC-user, sysreg, GPIO and USI11 PCLK gates; USI11 source and IPCLK at 399.36 MHz); all consumers off.

**M3, the bus** (overlay enabling USI11 and hsi2c_11; a `modprobe.d` file on the phone keeping `max77759`, `max77759_charger`, `tcpci_maxim`, `gpio_max77759`, `nvmem_max77759` and `max17042_battery` from loading). Result: `10cb0000.i2c` binds to `exynos5-hsi2c`, adapter `i2c-0`, clients 0x36 and 0x66 present and unbound. USI11's gates are enabled by the drivers (enable count 1), so the automatic gating works and no MANUAL bit is needed. No I2C probe tools were run in this step.

**M4a, the gauge.** The driver's model load only runs with a `maxim,fg-model` property, so without one the probe writes only the alert-enable bit and the alert thresholds. Loaded by hand. Result: percentage, voltage, current and temperature appear, UPower shows the battery. It loads at boot once its block line is removed.

**M4b, the MFD.** Read the driver first. It reads PMIC_ID, creates the dummy client at 0x69, and registers the PMIC, MaxQ, TOPSYS and charger interrupt chips with everything masked. Result: binds, five interrupt lines with counts of 0 or 1 that stay flat, no I2C timeouts or NACKs. Two kernel messages are not understood: `max77759-gpio: DMA mask not set` and `max77759-nvmem: Failed to locate of_node`; the GPIO and NVMEM drivers themselves stay blocked.

**M4c, the gauge model** (section 5).

**M5, the charger under a dead-man tool** (sections 6 to 8).

## 5. The gauge model and the temperature

### 5.1 The symptom

After a reinstall the gauge's temperature read exactly 22.0 C (`TEMP` register 0x08 = 0x1600) and never moved, not even under a sustained load. Before that, the same gauge on the same kernel read 32 to 34 C and moved. The dead-man tool refuses to start if the temperature is exactly 22.0 C, and it caught this before any charge.

### 5.2 What the gauge looked like

Verified, read with `i2cget` on 0x36: `Status` 0x0002 (the power-on-reset bit set), `Config` 0x2354, `TGAIN` 0xeb8d, `TOFF` 0x20aa. Google's register header (`max_m5_reg.h`, shusky `bms`) gives the power-on defaults as `Config` 0x2350, `Status` 0x02, `TGAIN` 0xeb8d, `TOFF` 0x20aa. So the live gauge was the power-on defaults plus the one alert bit the Linux driver sets: Google's model load had never run. The Linux driver loads a model only while `Status` bit 1 is set and only if the device tree carries `maxim,fg-model` and `maxim,fg-params`. Ours had neither.

What put the gauge back in that state is **not known**. Candidates: a 30-second power-key hold to reach the bootloader, or the GrapheneOS boot that preceded the reinstall. Neither was tested.

### 5.3 Hand calibration, three tests

All rolled back to the starting state each time (config, TGAIN, TOFF, and `TEMP` rewritten to 0x1600, because after restoring the config `TEMP` stays latched at the last measured value).

| Test | Writes | Reading |
| --- | --- | --- |
| 1 | `Config` 0x4217 only | 66.5 C, 66.4 C: impossible |
| 2 | stock TGAIN 0xed51, TOFF 0x1eba, `Config` 0x2254 (TEX cleared) | 53.5 C: still impossible |
| 3 | Google's whole stock triple: `Config` 0x4217, TGAIN 0xed51, TOFF 0x1eba | **warm test**, after about 20 minutes of a guarded 6-core load at about 800 mA (phone "a bit hot" to the hand): 47.2 to 47.4 C at idle, then a smooth rise to 49.3 C over 3 minutes of load. **Cold test**, 15 minutes idle, the phone at room temperature to the hand ("a tiny bit warm"): 46.5 to 47.2 C, not falling. |

Reading of test 3: the thermistor channel is alive and follows heating (it rose by about 2 C under load), but it sat about 20 C above what the hand felt at rest. A constant offset, not a dead sensor. Not verified: why. There is no second temperature sensor on the phone (the gauge's is the only thermal zone), so the reference was the hand.

### 5.4 The fix: load the whole model

Evidence from a sibling: on a Pixel 7, nesmeck's kernel PR #171 reports the same gauge reading a stuck 22.0 C without the model and 33.1 C once Google's model is loaded. The model load writes much more than the three registers above (the 48 table words and 27 parameter words, including config2, misc config and filter settings, then waits for the gauge's load bit).

Done on husky:

1. `device/husky/overlays/gauge-model.dtso` adds `maxim,fg-model` (48 u16) and `maxim,fg-params` (27 u16) to `fuel-gauge@36`. It is generated from Google's stock husky node by `tools/gen-gauge-overlay.py` (each stock u32 table cell split into two u16, high half first; the stock parameter bytes read as big-endian u16 in the order of `struct max77759_fg_params`), so no number is typed by hand. The leading words of the table and of the parameters matched an independently derived copy; the whole table was not re-compared by hand.
2. Model chosen: Google's `default-a1-0k`. In Google's driver the unknown-pack path sets the battery ID to 0 (`DEFAULT_BATTERY_ID`) and matches the node with `maxim,batt-id-kohm = 0`. The other nodes are `default-fake-batt` (ID 170, Google's dummy), `atl-a1-1k`, `cos-a1-2k` and `lsn-a1-3k`. (Replaced by the ATL model once the pack ID was read, section 5.6.)
3. Flashed through the images workflow (`DTB_OVERLAYS`), no kernel rebuild.

Result, verified: dmesg `max17042 0-0036: battery model loaded (DesignCap 0x994, TaskPeriod 0x2d00)`; `Status` 0x0000 (power-on bit cleared); `Config`, `TGAIN`, `TOFF` at 0x4217, 0xed51, 0x1eba; **TEMP 34.4 C**, drifting down slowly as a freshly booted phone cools, matching the hand (a hair above room temperature). The model survives reboots (no reload, the power-on bit stays clear). The gauge interrupt bursts on every 1 % step with the stock module, as kernel #170 describes: a logger on the phone reads the gauge's line in `/proc/interrupts` (summed over the CPUs) and the battery level every 30 s, and with a CPU load forcing steps the count rose by 466 for 75 to 74 % (803 to 1,269) and by 402 for 74 to 73 % (1,269 to 1,671). With #170's patch (applied cleanly to this tree, only `max17042_battery.ko` rebuilt with the release name pinned, swapped on the running phone with `rmmod` and `insmod`, the model staying loaded) the 73 to 72 % and 72 to 71 % steps each added 1 interrupt (1,671 to 1,672 and 1,672 to 1,673). The log is `work/logs-gauge-irq-170-test.txt`. Not tested: another pack or model, more than two patched steps.

### 5.5 Consequences, honestly

- The model is **sticky** until the gauge is reset. Google's reset is writing 0x000F to the gauge's command register (0x60) (`max1720x_full_reset()`); not tried on husky.
- A wrong table moves the percentage (often several percent) and the gauge's own full threshold. It does not change the charger's voltage limit, which comes from the device tree.
- Google's driver, if Android ever boots again on this gauge, compares a version byte with the model for the pack ID it reads and reloads Google's own model on a mismatch. The Linux driver never writes that byte. Not verified on a phone.
- The pack ID was found afterwards and the model replaced, see 5.6.

### 5.6 The pack ID, and switching to the ATL model

**Reading the ID.** Google's pack EEPROM is an `at,24c08` at 0x50 on hsi2c_9 (USI9, on CMU_PERIC1 like the battery bus, base 0x10c90000, GIC SPI 657, pins gpp19-4 and gpp19-5). Four kernel commits describe it: the USI9 clock ids, the USI9 path in `clk-zuma.c` (mux 0x690, divider 0x1824 and gates 0x2070, 0x2074, 0x20a0 in CMU_PERIC1, each checked against Google's cmucal tables and next to the USI11 set that already works), the `usi9` and `hsi2c_9` nodes with their pins, and a read-only `atmel,24c08` node in the board file (stock calls it `at,24c08`). `CONFIG_EEPROM_AT24=m` was already on. A bring-up overlay (`pack-eeprom-test.dtso`) switches the bus on. At boot the log shows `at24 0-0050: 1024 byte 24c08 EEPROM, read-only` and the three extra addresses (0x51 to 0x53) of the 24c08 appear. With the new bus the I2C adapter numbers move (the EEPROM bus became `i2c-0` and the battery chips `i2c-1`): look the bus up by its device path, as the tools here do.

Google's driver reads one byte at offset 0x17 (the battery ID, no checksum) and matches it exactly against `maxim,batt-id-kohm` of the model nodes: 170 is Google's dummy model, 0 `default-a1-0k`, 1 `atl-a1-1k`, 2 `cos-a1-2k`, 3 `lsn-a1-3k`. On this phone byte 0x17 is **1: an ATL pack** [verified: the byte read with `dd` from the nvmem file; the mapping is from Google's driver and the husky overlay]. An independent check: at the start of the day, before the gauge fell back to its power-on state, it reported a design capacity of 5,022,000 uAh, which is exactly the ATL model's 0x09cf times 2 mAh. The rest of the EEPROM holds the pack's part number, dates and history: only that one byte was ever read and printed, and nothing else of it is published.

**Switching the model.** The model is sticky (the driver loads it only while the gauge's Status bit 1, power-on reset, is set, and clears the bit), so replacing it needs a reset. Reviewed before doing it:

1. Set the power-on bit by hand: write 0x0002 to Status. The bit does **not** stick (read back 0x0000); the hardware owns it. Nothing changed.
2. Unload `max17042_battery`, write 0x000F to the gauge's register 0x60 (the `max1720x_full_reset()` code of Google's driver, which Google sends to this gauge itself when the model version changes; on this gauge's register map 0x60 is also the extra-config unlock, so this is not a documented command here), wait 0.4 s, read back, reload the driver. Read back right after the reset: Status 0x0002 (power-on set), Config 0x2350, TGAIN 0xeb8d, TOFF 0x20aa, DesignCap 0x0bb8, TEMP 0x1600: exactly the power-on defaults. After the reload: `battery model loaded (DesignCap 0x9cf, TaskPeriod 0x2d00)`; Status 0x0000, Config 0x4217, Config2 0x0090 (load bit clear), TGAIN 0xed51, TOFF 0x1eba, DesignCap and FullCapNom 0x09cf, TEMP about 35.3 C and steady.

The overlay for this is `gauge-model-atl.dtso`, generated by `tools/gen-gauge-overlay.py` from the husky MP overlay's `atl-a1-1k` node (model version 5, DesignCap 0x09cf). It has to be in the booted device tree before the reset (the driver reads the model from it at probe), so the switch was: flash the images with the ATL overlay, boot, reset, reload.

**What changed for the user.** The wrong table had been overstating the charge. At the same moment and about 3.95 V, the fallback model reported 70 % and the ATL model reports 60 %. The percentage after the load can jump (the driver writes RepCap to 0, loads, waits for it to become non-zero), and then settles.

**Not verified.** Whether the Status write ever works on another gauge state, and what Android does on a later boot (Google's driver compares a version byte stored in `TAlrtTh` and reloads its own model on a mismatch; the Linux loader does not write it). The 0x000F reset is Google's own code path but is documented nowhere for this chip, so the first time on a phone was done with the driver unloaded, a read-back at every step and the stop conditions above; it behaved as the reviewers expected.

## 6. The dead-man tool

`tools/husky-deadman` (desktop half) and `tools/husky-deadman-phone`, ported from cheetah's `tools/usbc-deadman`. A step runs detached on the phone and undoes itself unless the desktop gets back in over a new SSH login and confirms; a guard watches the battery; the SoC watchdog resets the phone if even the undo fails, and the phone then boots with the charger driver blocked.

- **Steps:** `noop`, `wd-drill` (stops feeding the watchdog on purpose), `b3-charger` (loads `max77759_charger` with `default_ilim_ua`, `temp_guard=1`, `guard_psy=max170xx_battery`).
- **Preflight (refuses otherwise):** gadget configured, MFD loaded, charger and Type-C driver not loaded, the charger blocked in `modprobe.d`, battery 30 to 80 %, at most 4.15 V, 10 to 40 C and not exactly 22.0 C, input limit at most 900 mA, no earlier `b3-charger` this boot (the MFD register cache goes stale after any `i2cset`).
- **Guard (every 2 s):** trips on more than 4.30 V or under 3.0 V, above 45 C or under 5 C, more than 1.7 A in either direction, or three bad reads.
- **Undo:** unload the module, restore registers 0xbb, 0xbd, 0xc2, set the mode to OFF and then 0x4 (system from USB, battery not charged), read the mode back. Registers 0xb9, 0xbf, 0xc5, 0xcb are recorded only (0xc5 and 0xcb need the CHGPROT unlock).
- **Reviews:** two review rounds before the first run (not by a maintainer), then a third on the final plan. They found: the driver's unload does not stop charging (it leaves mode 0x5), the desktop half exited at `confirmed` before the soak, the watchdog was off during the soak, an unchecked unload, stale state files, a race at the end of the soak, an undo that did not read back the mode, a dropped link not treated as the drill. All fixed before the first run.
- **Two bugs found only by running it on the phone:** (1) the block file's `install max77759_charger /bin/false` line made the tool's own `modprobe` run `/bin/false`; the load now uses `modprobe --ignore-install`. (2) After a load, the tool now also requires the `max77759-charger` power supply to exist, because a probe failure could otherwise leave charging on with no driver.
- **The temperature check earned its place:** it refused the first two real attempts because of the stuck 22.0 C.
- **Not verified:** whether a watchdog reset puts the charger registers back to the bootloader's values. The drill never changes them. A software reboot with the step applied would show it for the software path; the emergency watchdog path would need a combined drill.

## 7. The charger runs

Common setup: battery 76 to 78 %, 4.0 to 4.04 V, about 34 C, charger blocked at boot, MFD and gauge loaded, USB rescue running. Each run ended with the tool's own `undo` (after the extra watches described below), which unloaded the module, restored the registers (0xbb 0x1d, 0xbd 0x23, 0xc2 as at boot) and left mode 0x4.

What the driver does on probe, from its own log: it finds what the bootloader left (`mode 0x5, float voltage 4350 mV, fast charge 1933420 uA, input limit 500000 uA`), then reprograms to the device-tree limits (`float voltage 4200 mV, fast charge 1533400 uA`) with the temperature guard on (`band 20-42 C, float 4200 mV, charge 1485000 uA`). So the Linux driver is more conservative than the bootloader. Registers seen: 0xbb 0x1d to 0x17 (fast charge), 0xbd 0x23 to 0x14 (float 4.2 V), 0xc2 0x13 to 0x23 for 900 mA.

| Run | Source | Input limit | Duration | Voltage | Battery temperature | Net battery current | Result |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | desktop USB port, screen on | 500 mA | 10 min soak | 4.03 to 4.04 V | 34.3 to 34.6 C | -17 to -240 mA | clean |
| 1b | same, screen off, idle | 500 mA | 5.5 min, 33 samples | 4.03 to 4.04 V | 34.3 to 34.5 C | average -119 mA | clean |
| 2 | desktop USB port, screen off | 900 mA | 10 min soak | 4.03 to 4.04 V | 34.2 to 34.3 C | -19 to -234 mA | clean |
| 3 | wall charger (the stock fast-charge brick of a OnePlus 13; the Pixel cannot negotiate its protocols, so presumably plain 5 V, not measured), screen off | 900 mA | 14 min, 84 samples (78 in the window) | 4.01 to 4.05 V (mostly 4.04, a few load dips to 4.01) | 33.8 to 34.3 C | positive in 70 of 78 samples, typically +30 to +80 mA, average +18 mA with a few load spikes down to -425 mA | clean |

Reading, verified from the logs: raising the input limit from 500 to 900 mA changed nothing on the desktop port, so the port, not the phone, was the limit. On the wall charger the net current turned positive and the voltage went from 4.038 to 4.045 V between the first and last samples (a few load dips down to 4.01 V in between). The percentage stayed at 76 %: +40 mA for 13 minutes is under 10 mAh, and 1 % is about 49 mAh.

Not verified, and not claimed: how much current the charger actually draws from the input; the gauge says the battery's net current only. Without a Type-C driver the Pixel cannot negotiate USB-PD or the charger's own fast-charge protocols, so it presumably gets plain 5 V (not measured); that is for the Type-C step.

A note for UI authors: the charger power supply says `Charging` (fast charge) while the gauge's own power supply says `Discharging` whenever the net current is negative, so the status-bar icon (charger) and the fetch widget (gauge) can disagree. Both are telling the truth.

### 7.1 What stock does, decoded, and a first safe step (a proposal, nothing implemented)

Read-only research on Google's stock husky device tree (the MP overlay, capacity 0x1356 = 4950 mAh) and Google's GPL charger sources (shusky `bms` repository). The decoded tables were recomputed independently and match.

Stock's profile (`google,chg-temp-limits`, `google,chg-cv-limits`, `google,chg-cc-limits`; the current limits are percent of the 4950 mAh capacity). Bands 0 to 10, 10 to 20, 20 to 42, 42 to 46, 46 to 48 and 48 to 55 C; voltage tiers 4.20, 4.30, 4.35 and 4.48 V (`fv-max-uv` is 4.48 V):

| Band (C) | up to 4.20 V | 4.20 to 4.30 V | 4.30 to 4.35 V | 4.35 to 4.48 V |
| --- | --- | --- | --- | --- |
| 0 to 10 | 2475 mA (0.5 C) | 1485 mA (0.3 C) | no charge | no charge |
| 10 to 20 | 3465 mA (0.7 C) | 1485 mA | 1485 mA | 1485 mA |
| 20 to 42 | 5940 mA (1.2 C) | 5940 mA | 5940 mA | 2475 mA (0.5 C) |
| 42 to 46 | 4950 mA (1.0 C) | 4950 mA | 4950 mA | 2475 mA |
| 46 to 48 | 2475 mA | 2475 mA | 2475 mA | no charge |
| 48 to 55 | no charge | 1485 mA | no charge | no charge |

Adaptive charging by cycle count lowers the 20 to 42 C row from 120 % to 110 % at 300 cycles and 100 % at 1000. The battery defender starts after 21,600 s at 35 C or more and above 4.270 V, drains to 80 %, recharges at 4.250 V and 79 %, and resumes at 29 C or below.

What stock does not do, verified in the source: no JEITA registers are programmed in the charger chip (the hardware thermistor monitor THM2 is off on husky, and it is a USB-connector sensor in any case), and the fast-charge safety timer is disabled. All the bands are software, from the fuel gauge's temperature. Our driver's temperature guard already uses the same band edges (0, 10, 20, 42, 46, 48, 55 C); its tiers (4.20, 4.30 and 4.45 V) and percentages are from the Pixel 7 era and differ, and the log line `band 20-42 C, float 4200 mV, charge 1485000 uA` is its 100 % of 4950 mAh clamped by the device tree's 4.2 V and 1.485 A.

The PCA9468 (0x57) is a 2:1 direct charger fed by USB-PD PPS (10.5 V maximum, 3 A at the adapter), chosen by stock's power manager between 3.4 and 4.35 V battery voltage; it carries the rows above about 3 A, and wireless DC. Without a driver there is no fast charge; the MAX77759's own buck is what stock itself uses above 4.35 V. Not verified: the part's power-on default and the state of its enable GPIO under Linux, so check that before relying on "unconfigured is safe".

Input limit: the charger's `CHGIN_ILIM` code is 0x04 plus (uA minus 125,000) divided by 25,000. Stock votes 500 mA (USB 2) or 900 mA (USB 3) for a standard port and 1.5 A for a charging port after BC1.2 detection, and whatever the contract says for PD. Our 500 and 900 mA are the no-advertisement defaults; without BC1.2 or PD a higher limit on a plain 5 V source would be a guess.

A proposal for review, not implemented: keep the 4.20 V float, and band the current by temperature, for example 0.3 C at 0 to 10 C, 0.5 C at 10 to 20 C, 0.5 C or at most 0.7 C at 20 to 42 C, 0.5 C at 42 to 46 C, 0.3 C at 46 to 48 C, and no charge outside 0 to 48 C. Not to be raised without a review: the float above 4.2 V (it needs the tier switching, full detection, recharge logic, adaptive charging and the defender), the current above 0.7 C, the input limit beyond what the port advertises, and stock's odd 48 to 55 C row. Putting such a table in the driver is a kernel change (its table is hard-coded) for a later PR.

## 8. USB link lost after an unplug

Symptom: after unplugging and replugging the cable the phone does not come back on the USB link until it is rebooted. The kernel log of that boot shows nothing at the unplug. Cause (read from the cheetah and raven notes, then confirmed on husky): on unplug the MAX77759's Type-C side opens its USB2 data switch (TCPC 0x25, vendor register 0x93; 0x09 is closed, 0x00 open), and with no Type-C driver nothing closes it again; the bootloader does at the next boot.

Fix: `omamobile-usb-rescue`, the Pixel 7 Pro's service on husky's bus (`10cb0000.i2c`). While VBUS is valid (`CHG_DETAILS_00.CHGIN_DTLS` equal to 3) it writes 0x09 to 0x25:0x93 when the switch is not 0x09, and it logs each change of the switch, VBUS and the UDC state to the journal. It stands aside once a Type-C driver owns the chip.

Test, verified from its journal: unplug at 11:37:08 (`usbsw=0x00 vbus=0`), replug at 11:37:26 (`vbus=1`, the service wrote 0x09), 11:37:28 `usbsw=0x09`, link back on the desktop, no reboot. The same worked when the cable was moved to a wall charger and back. Shipped as part of `omamobile-device-husky` 0.1.3 together with the MAX77759 blocklist.

## 9. Slot B retries, and the cure that cheetah already has

Omarchy never marks slot B's boot successful, so every boot of slot B uses one of its three bootloader retries. At zero the bootloader falls back to slot A (GrapheneOS), and its first boot reformatted `userdata`: the Omarchy install was gone. It happened after a set of drills and reboots in one session. Observed with `fastboot getvar` after the fallback: current slot a; slot A successful, retry 1; slot B not successful, retry 0, not unbootable. `fastboot set_active b` sets the counter back to 3. Reading the count in the bootloader changes nothing; whether `reboot-to bootloader` itself uses a retry is not established (two of my readings disagree).

Recovery was a fresh read-only backup in the initramfs, then `tools/install-phone` (it asks for answers, so it has to run in a real terminal), then the keyring repair for the known clock issue (#188), then the battery images and modules.

**The cure exists.** Cheetah's package ships `omamobile-boot-success` and `omamobile-bootctl`, which mark the booted slot successful after a healthy boot by updating the slot bytes in `devinfo`. The husky package leaves them out on purpose ("until each one has its own runbook"). A check that can be done read-only: husky's `devinfo` has magic `DEVI`, version 3.15, and slot bytes at 0x30 that decode with the layout of `omamobile-bootctl`'s source (retry count, then flags: unbootable, successful, active, fastboot-ok). All three backups of the partition, taken at different times, hold the same slot bytes: slot A retry 1, flags 0x0a (successful, fastboot-ok); slot B retry 1, flags 0x04 (active, not successful).

What can and cannot be cross-checked against `fastboot getvar`:

- The flags agree with every reading I took: slot A successful, slot B not successful, and slot B the active one.
- The retry count agrees with one reading only: on 2026-10-31 at 13:54, right after the 13:35 backup and with no boot in between, `getvar` said retry 1 on both slots, as the file does. The counter moves with each boot of slot B, and between the other backups and my other readings slot B booted and was reset with `set_active`, so the file's retry value cannot be compared with those readings, and I am not using them.

So the layout is consistent with husky's [verified, read-only, on files]: the magic and version are right, the flags match every reading, and the retry counts match the one reading that can be compared. That is not proof that the marker works on husky. Marking the slot successful would write `devinfo`, which today is hidden by the storage guard and listed as never-touch in AGENTS.md, so that is a decision for the maintainer, with its own runbook and a test against a backup first. Dry run, read-only on files: cheetah's `omamobile-bootctl dump` run on all three backups of the partition prints `magic 0x49564544 "DEVI"`, `version: 3.15 (verified layout)` and the same slot bytes as above (slot A `01 0a 00 00`, slot B `01 04 00 00`). This document only reports that the layout looks the same.

## 10. What was combined, and what we did not do

- The bring-up used a modprobe block by hand and an overlay each time, not the package. Once the package ships `omamobile-max77759.conf`, delete the local `/etc/modprobe.d/omamobile-battery-test.conf`: a file in `/etc` of the same name would replace the package's and its later changes would not apply.
- `modprobe -r max77759_charger` was used four times (by the tool's undo). CONTRIBUTING warns about unloading bring-up modules; for this driver the unload worked every time, but note that the driver has no remove function and leaves charging on when unloaded, which is why the undo forces the mode to 0x4 explicitly.
- No Type-C work, no charger limits above the conservative ones, no JEITA, no PCA9468, no wireless, no OTG.

## 11. Open questions, in the order they matter

1. **The model in the board file.** The pack is ATL (section 5.6), so the ATL model can become a device-tree change (a kernel PR) instead of an overlay, once a second pack or phone shows whether the ID should still be read at runtime.
2. **A device-tree model.** Once the pack is known, the model belongs in the board file (a kernel PR), not in an overlay.
3. **Charge limits.** Our 4.2 V and 1.485 A are conservative on purpose; stock steps up to 4.48 V by temperature. Review before anything raises them. Also unknown: whether the charger chip's own thermistor and JEITA protection are armed by default (nothing in the Linux driver configures them; Google's driver disables the charger watchdog and the THM2 interrupt).
4. **Does a reset put the charger registers back?** The software-reboot case can be checked directly; the emergency watchdog case needs a combined drill.
5. **Type-C (the next step).** In this tree's `tcpci_maxim_core.c` the data switch is closed (0x09) on every attach (`max_tcpci_set_roles`) and a PD partner that is not USB-communications capable opens it again (`set_partner_usb_comm_capable`); nothing else in that file writes register 0x93. So the driver should end the replug problem, but it has not been run on husky. It also takes over the USB-C port we use for SSH, so do it under the dead-man tool, with a second way into the phone.
6. **The boot-success marker** (section 9).
7. **The two kernel messages in the MFD** (DMA mask, NVMEM `of_node`), and what UPower's charge-cycle count means.

## 12. Files

In this repository: `device/husky/overlays/battery-i2c-test.dtso`, `device/husky/overlays/gauge-model.dtso`, `tools/gen-gauge-overlay.py`, `tools/husky-deadman`, `tools/husky-deadman-phone`, and the package changes in `packages/omamobile-device-husky`. Kernel side: kernel #163 (the bus) and #154 (panel size, which the on-screen keyboard needs).

Kept locally, available on request, no serials: the dead-man tool's per-run kernel logs, the gauge test logs, the charge-watch logs, and the `tools/phone-smoke` report from this kernel.

## 13. Credits

Derek Ross reviewed the kernel changes against Google's tables. Brett (greenbrettmichael) provided the c6 kernel the work booted on. nesmeck's Pixel 7 gauge PRs (#170, #171) showed what a missing model looks like and what the load fixes. The cheetah and raven tools (`usbc-deadman`, `omamobile-usb-rescue`) are the pattern the husky versions follow.
