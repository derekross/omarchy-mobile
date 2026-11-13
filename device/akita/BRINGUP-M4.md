<!-- SPDX-License-Identifier: MIT -->
# akita M4: battery and charging

**Status (2026-11-13):** **M4 is complete on the phone.** The fuel gauge reads the 8a's ATL pack with its own model, the bootloader's charger state is recorded, the USB link survives an unplug, Linux charged the battery under the dead-man tool on a laptop port and a wall charger (gate h), and the PMIC's interrupt gives the RTC an alarm ([Results](#results)).

The kernel side is linux-omarchy-mobile#246 (the gauge and PMIC, the pack's EEPROM and the PMIC's interrupt), open as of 2026-11-13. Until it merges, the published kernel has no `hsi2c_11` on akita, so the gauge, the USB rescue and the dead-man tool have nothing to talk to.

M3 is complete ([BRINGUP-M3](BRINGUP-M3.md)).

## Goal

1. **See the battery:** level, voltage, current and temperature in the status bar and UPower, from the fuel gauge, with the 8a's own battery model.
2. **Know what charges it:** read what the bootloader leaves the charger doing, without changing it.
3. **Charge under Linux, safely:** the charger driver loaded only under a dead-man tool, with a person at the phone, at limits below stock's.

Out of scope:
- USB-C host mode and VBUS out;
- PD fast charging;
- the PCA9468 direct charger;
- wireless charging;
- suspend.

Slot A stays stock. Only slot B's boot images and `userdata` are written.

## What akita inherits

The 8a's battery hardware is the 8 Pro's: the same chips, at the same addresses, on the same bus, with the same interrupt lines. So most of the work is husky's, merged or documented:

- **Kernel (merged on `omamobile`):**
  - CMU_PERIC1, USI11 and `hsi2c_11` (kernel #163, #175);
  - zuma-husky's gauge, PMIC and disabled Type-C nodes (#205);
  - the `simple-battery` node.

  The drivers are already in akita's build as modules: `MFD_MAX77759`, `BATTERY_MAX17042`, `CHARGER_MAX77759`, `TYPEC_TCPCI_MAXIM`, `GPIO_MAX77759`, `NVMEM_MAX77759`.
- **Method:** husky's [BATTERY-NOTES](../husky/BATTERY-NOTES.md), especially:
  - its runbook (M1 to M5);
  - the gauge-model lessons (§5: the fallback model read 10 points high);
  - the dead-man tool (§6, `tools/husky-deadman` and `-phone`);
  - the charger baseline (§10a).
- **The USB link after an unplug:** husky's `omamobile-usb-rescue` closes the Type-C chip's USB data switch (0x25:0x93) that the charger opens when VBUS drops. That's probably the cause of M2.7's lost link (BRINGUP-M2, not checked on akita), so it belongs here too.
- **The PMIC interrupt:** linux-omarchy-mobile#243 gave husky's S2MPG14 its interrupt (GIC SPI 74, the VGPIO2AP sysreg, `wakeup-source`), so its RTC has an alarm. The 8a's stock tree has the same interrupt (`<0 0x4a 4 0>`, `s2mpg14,wakeup = "enabled"`), and stock's `/proc/interrupts` shows `rtc-alarm0` on it. #243's author suggested akita take the same three lines.

## Facts

From G/ (`zuma-akita-battery.dtsi`, `zuma-akita-battery-data.dtsi`, `zuma-akita-charging.dtsi`, `zuma-akita-typec.dtsi`) and R/ (the stock live tree and `/sys/class/power_supply`, captured before the wipe):

| Item | akita | husky | Source |
| --- | --- | --- | --- |
| Bus | `hsi2c_11` at 400 kHz, pins `gpp21-0`/`gpp21-1` | the same | [V] G/ |
| Bus pins' pull | PULL_NONE in G/'s battery file, but **PULL_UP** in the stock phone's live tree (`pin-pud` 3) | **PULL_UP** in `omamobile` (Google's final husky value, kernel #163) | [V] G/, R/ (M4.0): the same, so akita needs no override |
| Fuel gauge | MAX77759 FG at 0x36, interrupt `gpa7-7` | the same | [V] G/ |
| PMIC | MAX77759 at 0x66 (Google names it `max77729pmic`), interrupt `gpa8-0`; PMIC_ID 0x3b, rev 0x02, OTP 0x31 | the same | [V] G/, M4.3 |
| Charger | 0x69 (the PMIC's dummy client) | the same | [V] G/ |
| Type-C | MAX77759 TCPC at 0x25; SBU mux on `gpa7-5` | 0x25, interrupt `gpa8-3`, disabled | [V] G/; the interrupt is [I] |
| Pack EEPROM | `at,24c08` at 0x50 on `hsi2c_9` (pins `gpp19-4`/`gpp19-5`, no pull) | the same | [V] G/, R/ |
| Gauge sense resistor | 5 mΩ (`maxim,rsense-default = <500>`, in 10 µΩ units) | 5 mΩ | [V] R/ |
| Pack | design 4486 mAh (gauge), `google,chg-battery-capacity = <4404>` | 4950 mAh | [V] R/ `charge_full_design` 4486000; G/ |
| Battery models | four, by the pack's ID (EEPROM byte 0x17): `default-a1-0k` (0), `atl-a1-1k` (1), `cos-a1-2k` (2), `lwn-a1-4k` (4); **this phone's pack reads 1, ATL** | ATL, after reading its EEPROM | [V] G/ `zuma-akita-battery-data.dtsi`, M4.2 |
| Stock's top charge voltage | 4.48 V (`google,fv-max-uv`) | 4.48 V | [V] G/ |
| On stock, plugged in (R/) | 67 %, Charging, 4.05 V, 28.4 C, 89 cycles, `charge_full` 4238 mAh; the main charger at a 1.5 A limit, 5 V | — | [V] R/ |

**The plan's own limits** are husky's conservative ones, scaled to the 8a: **4.2 V** and **0.3 C (1.32 A)**. Raising either needs a review.

**Private:** R/'s `power-supplies.txt` includes the battery's serial number. It's never quoted or committed.

## Design

1. **One board-file change per step,** each in its own commit. Nodes go in disabled where a step needs them off, and the drivers are blocked in `modprobe.d` until their step, as on husky:
   - `simple-battery` with the 8a's values;
   - `&hsi2c_11` with the gauge and PMIC, and the Type-C node disabled;
   - `&hsi2c_9` with the pack EEPROM.
2. **The gauge model** comes from Google's public `zuma-akita-battery-data.dtsi`, the model matching the pack's ID, never the fallback. husky's §5.6 shows why.
3. **The charger** is loaded only through a dead-man tool. That's `tools/husky-deadman`, which now tells the two phones apart by the device tree and guards each with its own current limit (M4.0). Whether it should be renamed, or akita should get a copy, is the maintainer's choice. It covers:
   - preflight checks;
   - a 2-second guard on voltage, temperature and current;
   - an undo that sets the charger to "system from USB, battery not charged";
   - a watchdog drill.
4. **The USB rescue comes before any charging** (M4.4), so moving the cable to a wall charger and back doesn't cut the laptop off. **The PMIC interrupt** is a small, separate change at the end (M4.7).

## Runbook

Each boot needs the human's go and changes one thing. **Each step's results end with slot B's tries left.** Before any step that can reset the phone, B must have at least 2 tries: `--set-active=b` first.

### M4.0 Laptop only
- **Read in full:** G/'s four battery files, and husky's merged nodes and BATTERY-NOTES §4 to §10a.
- **Settle the bus pull:** PULL_NONE (akita's G/) or PULL_UP (`omamobile`'s, from husky).
- **Read the dead-man tools,** and decide with the maintainer how akita gets one.
- **Back up again:** a fresh read-only backup of the NV partitions (`tools/nv-backup`), as husky did before battery work.

### M4.1 The bus, read only
- **Change:** `hsi2c_11` enabled, with the gauge and PMIC nodes present, and **every** `max77759*`, `max17042_battery` and `tcpci_maxim` module blocked in `modprobe.d`.
- **Pass:**
  - `exynos5-hsi2c` binds;
  - clients 0x36 and 0x66 appear, unbound;
  - no I2C errors in the log.
- **No I2C probe tools** are run in this step.

### M4.2 The gauge
- **Change:** load `max17042_battery` by hand, then with the pack's model.
- **Pass:**
  - percentage, voltage, current and temperature appear in UPower and the status bar;
  - the temperature moves, and isn't stuck at 22.0 C (husky's tell for a missing model);
  - the level is plausible against the voltage.
- **The pack ID:** read the EEPROM on `hsi2c_9` (read only) to pick the model.

### M4.3 The PMIC (MFD), and the charger's state, read only
- **Change:** bind `max77759`.
- **Pass:**
  - PMIC_ID reads 0x3b;
  - its interrupt lines stay flat.
- **Then record the bootloader's charger state** from the driver's probe and read-only register reads: mode, float voltage, fast-charge current, input limit. **This answers whether the phone is charging today.**

### M4.4 The USB rescue
- **Why it comes before charging:** every one of husky's charger runs had `omamobile-usb-rescue` running (BATTERY-NOTES §7). Moving the cable from the laptop to a wall charger and back opens the Type-C chip's USB data switch (0x25:0x93). Without the rescue, the link stays down until a reboot, so the laptop can't get back in to confirm the dead-man tool or read its log. This is probably M2.7's lost link too.
- **Change:** husky's `omamobile-usb-rescue` on akita's bus. It needs the MFD from M4.3 to read VBUS (`CHG_DETAILS_00`). While VBUS is valid, it writes 0x09 to 0x25:0x93 whenever the switch isn't 0x09, and logs each change.
- **Pass:**
  - unplug and replug the laptop's cable: the link comes back without the buttons, and the journal shows `usbsw=0x00` then `0x09`;
  - the same after a few minutes on a wall charger, then back on the laptop.

### M4.5 The dead-man drill
- **Change:** run the tool's `noop` and `wd-drill` steps, with no charger change.
- **Pass:** both undo cleanly. The drill's watchdog reset costs a try, so check B's tries first.

### M4.6 The charger, under the dead-man tool (gate h)
- **Change:** load `max77759_charger` through the tool, at 4.2 V / 1.32 A limits, with **a person at the phone** and the USB rescue running. A desktop USB port first, then a wall charger, then back to the laptop to confirm and read the guard's log.
- **Pass:**
  - the battery takes current on the wall charger, and the guard never trips;
  - the link comes back on the laptop after the wall charger;
  - the undo leaves "system from USB, battery not charged";
  - a reboot afterwards comes up the same.

### M4.7 The PMIC interrupt
- **Change:** the three lines from #243.
- **Pass:** the `s2mpg14-pmic` count stays flat at rest, and `rtcwake -m no -s 60` fires `rtc-alarm0` on time.

## Risks

- **Charging is the one step here that can hurt the hardware.** That's why it runs only under the dead-man tool, at limits below stock's, with a person present, and why every register write is read back and undone.
- **The wrong gauge model** reads the level wrong (husky: 10 points high), and the charger's decisions would follow it. Read the pack's ID first.
- **Slot B's tries:** the watchdog drill and reboots spend them.
- **Register access** is to the external MAX77759 over I2C only (`i2cget`/`i2cset`, as husky's tools do), never the SoC's own registers (AGENTS.md §1).

## Open questions

- ~~Is the phone charging today?~~ Yes: the bootloader leaves the charger charging, to a 4.35 V float with a 500 mA input limit (test 40).
- ~~Which pack?~~ ATL (`atl-a1-1k`), from its EEPROM (test 38).
- ~~The bus pins' pull?~~ Pulled up, as `omamobile` has it (M4.0).
- **One dead-man tool for husky and akita, or a copy?** It's one tool for now (M4.0); the maintainer chooses.
- ~~Does a reset restore the charger's registers?~~ A reboot through the bootloader does: the charger came back in its usual state after the undo had turned charging off (test 46).
- **The charge current reads higher than the input limit allows** (test 45). Not settled.
- **The charger driver's voltage units:** `constant_charge_voltage_max` reads `4200`, which looks like millivolts where sysfs uses microvolts (test 45). That's `max77759_charger`.

## Results

Test numbers continue from [BRINGUP-M3](BRINGUP-M3.md)'s. The logs are private (`~/android/reference/akita-m4.1-bus-20261112/`, `akita-m4.2a-gauge-20261112/`; the dead-man runs in `logs/`, not committed).

### 2026-11-12: the laptop, the bus and the gauge (M4.0 to M4.2)

- **M4.0:**
  - **The bus pull:** the stock phone's live tree has `hsi2c11-bus` pulled up (`pin-pud` 3), overriding G/'s `PULL_NONE`. That's `zuma-pinctrl.dtsi`'s value, so akita needs no override.
  - **The dead-man tool:** its husky-only parts were the compatible check, the names and the 1.7 A current guard (sized for husky's 1.485 A). The bus (`10cb0000.i2c`) and the gauge's power supply are the same. So `tools/husky-deadman` now picks the board from the device tree: the Pixel 8 Pro keeps 1.7 A, the Pixel 8a gets 1.5 A (for its 1.32 A), and any other board is refused.
  - **A fresh read-only NV backup** (`tools/nv-backup`), verified. The first try failed safely on SSH timeouts, with no cause found; the second completed.
- **The kernel:** `omamobile` at `2db2bc35b`, plus #246's commits as they were tested: `…g2a02a03a60cf` (the gauge and PMIC), then `…g27a64aba0dc3` (adds the pack's EEPROM).
- **The hold file:** a modprobe file on the phone blacklisted every battery driver for M4.1, and was narrowed one driver per step.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 36 | The bus, read only (M4.1) | `10cb0000.i2c` bound to `exynos5-hsi2c` under its USI. Clients 0x36 (`max77759-fg`) and 0x66 (`max77759`) present, unbound. No battery module loaded, no I2C errors, the bus's interrupt at 0. `tools/phone-smoke`: every row ok, 0 new | The bus works; nothing touched the chips |
| 37 | The gauge, loaded by hand, no model (M4.2a) | `max170xx_battery`: 93 %, 4.311 V, about 0 A, **22.0 C and not moving**, design capacity 3000 mAh (the driver's default). UPower shows it | husky's tell for a missing model. 4.31 V on the cable already suggests the bootloader keeps the pack charged |
| 38 | The pack's ID (M4.2b) | With `pack-eeprom-test.dtso`: "1024 byte 24c08 EEPROM, read-only" on `hsi2c_9`. Byte 0x17 read 1, three times | **The ATL pack** (`atl-a1-1k`) |
| 39 | The ATL model (M4.2c) | With `gauge-model-atl.dtso` too: before loading, the gauge's Status had its power-on-reset bit set and its registers were at their defaults. `modprobe max17042_battery`: "battery model loaded (DesignCap 0x8c3)". After: Status 0, design capacity 4486 mAh (stock's), **89 %** (93 % with the default model), 4.312 V, **35.9 to 36.0 C and moving**. UPower 89 %, 20.1 Wh | The gauge reads the 8a's pack with its own model |

Slot B: 2 tries left.

### 2026-11-12: the PMIC, the charger's state and the USB rescue (M4.3, M4.4)

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 40 | The PMIC, loaded by hand (M4.3) | `max77759` binds and creates its charger, GPIO and NVMEM cells, whose drivers stay blacklisted. The same two messages as on husky (the GPIO cell's DMA mask, the NVMEM cell's missing node). Its interrupt lines stay flat. PMIC_ID 0x3b, rev 0x02, OTP 0x31. **The charger, read only:** mode 0x05 (charging, with the buck on), fast charge 0x1d (about 1.93 A), float 0x23 (4.35 V), input limit 0x13 (500 mA). husky's bootloader leaves exactly the same | **The phone has been charging on the cable all along,** under the bootloader's settings |
| 41 | The USB rescue (M4.4): husky's script, unchanged, run as a test unit | **An unplug:** the journal shows `usbsw=0x00 vbus=0`. **The replug, 13 s later:** `usbsw=0x00 vbus=1`, then "closing the data switch", then `usbsw=0x09`; the laptop saw the phone again a second later. SSH works, no reboot | **The cause of M2.7's lost link is confirmed on akita:** the charger side opens the USB2 data switch when VBUS drops |
| 42 | The rescue across a wall charger | Laptop, then a wall charger for 3 minutes, then the laptop. The switch stayed at 0x09 this time, so the rescue wrote nothing, and the link came back | The switch opens only sometimes; the rescue covers it either way |

Slot B: 2 tries left.

### 2026-11-12 and 13: the dead-man tool and the charger (M4.5, M4.6, gate h)

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 43 | `tools/husky-deadman noop`, then `wd-drill` (M4.5) | **noop:** the guard tripped at once, on 4.3125 V against its 4.3 V limit (the bootloader's 4.35 V float), and the tool undid the step and disarmed the watchdog: exit 7. **wd-drill:** the watchdog reset the phone, which came back in 26 s with the charger driver unloaded and the charger at the bootloader's values | The trip path and the watchdog work on akita. The board check names the 8a and uses 1.5 A |
| 44 | `noop` again, at 65 % and 4.06 V (M4.6) | Confirmed over a new SSH login after 6 s, soaked 30 s with the guard at 4.07 V, 34.1 C, +1.0 A, then undone by hand | The confirm path works too |
| 45 | `tools/husky-deadman b3-charger --soak 1500` (gate h) | **The first try refused,** changing nothing: the PMIC driver wasn't loaded. (This boot had it blacklisted; the package's file doesn't.) **After `modprobe max77759`:** the charger driver logged "battery 34.4 C, 4099 mV: band 20-42 C, float 4200 mV, charge 1320000 uA", and the step confirmed after 5 s. **Over 25 minutes:** about 5 minutes on the laptop's port, then a wall charger for 10 minutes, then the laptop again. **The battery went from 65 % to 72 %,** at most 4.165 V and 34 to 35 C, with the current tapering from 1.0 A to 0.75 A near the float. **The guard never tripped.** The link came back by itself after the wall charger. **The undo:** the driver unloaded, mode 0x04 (no charging), the other registers back at the bootloader's values | **Gate (h) passed:** Linux charges the 8a within this battery node's limits |
| 46 | A reboot through fastboot | The bootloader set the charger back to its usual state (mode 0x05, 0x1d, 0x23, 0x13). The battery charging at 0.80 A, 72 %, 35.0 C. No failed units | The undo's "no charging" lasts only until the next reboot |

Slot B: 2 tries left.

### 2026-11-13: the PMIC's interrupt (M4.7)

The kernel: `…g8136602c700c`, #246's third commit added.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 47 | The PMIC's interrupt and the RTC alarm | No "no RTC alarm" line; `rtc0` has `wakealarm`. `s2mpg14-pmic` is on GIC 106 (SPI 74) with `rtc-alarm0` under it, both at 0 for about 90 s at rest. `rtcwake -m no -s 60` set 01:08:50; the alarm fired between 01:08:49 and 01:08:54 (`s2mpg14-pmic` 0 to 2, `rtc-alarm0` 0 to 1). No failed units, the 2 known error lines | The same as #243 on the 8 Pro: the RTC has an alarm |

Slot B: 2 tries left.

Findings:

- **The charge current reads higher than the input limit allows.** In test 45 the gauge read about +1.0 A into the battery, with the input limit at 500 mA. At 4.1 V that's about 4.1 W, more than 5 V × 0.5 A. The gauge's sense resistor matches stock's (5 mΩ), and the level rose about as fast as that current says (7 % of 4486 mAh in 25 minutes is about 0.75 A on average). So either the input limit isn't what register 0xc2 reads back as, or the port gives more than the limit. It needs settling before any higher limits. The guard errs on the safe side if the gauge over-reads.
- **The guard keeps only its latest reading,** so there's no record of the wall-charger phase beyond "it never tripped". A reading a minute in its log would fix that.
- **Before `b3-charger`, the PMIC driver must be loaded.** With the package's blacklist it autoloads, as on husky. The test boots here had it blacklisted by hand.
- **The USB link was lost once,** when the rescue wasn't running (its test unit wasn't enabled after a reboot). Holding Volume Down and Power for over a minute power-cycled the phone back into slot B, not into fastboot, and that boot cost a try. With the package, the rescue is enabled at every boot.
- **The kyber message:** Omarchy 4.5's `60-omarchy-io-scheduler.rules` fails to set `kyber` on some of the UFS units with "Device or resource busy" (`sda`, `sdc` and `sdd` in one boot; it varies). udev ignores it, and nothing else is affected.
