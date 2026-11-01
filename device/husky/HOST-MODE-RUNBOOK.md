<!-- SPDX-License-Identifier: MIT -->
# Pixel 8 Pro (husky): sourcing 5 V on the USB-C port from userspace, stage (a) runbook

Last updated: 2026-11-02. Draft, for review. **Nothing in this document runs until the maintainer says go.** The one sourcing run that has happened (2026-11-01, before the review, over Wi-Fi with nothing attached; the undo brought the port to 0 V within a second) is described in [BATTERY-NOTES.md](BATTERY-NOTES.md) and in the pull request; it used an earlier version of the tool and is not a result of this runbook.

Tags, on every claim: **[verified]** read in the file at the line given, or in a log; **[inferred]** follows from a verified fact, with what settles it; **[unknown]** in no file we have, with the test that answers it.

Paths: `G/` = Google's GPL charger code, `kernel/google-modules/bms`, branch `android-gs-shusky-6.1-android16` (`max77759_usecase.c`, `max77759_charger.c`, the register headers `max77759_A1_regs.h` and `max77759_v0p65_121919_regs.h`); `L/` = our kernel tree (linux-omarchy-mobile, the c6 base); `S/` = the stock husky device tree (the factory image's `dtbo`, decompiled, `ov8.dts`); `P/` = `tools/husky-deadman-phone` in this repository.

## 0. Scope

Stage (a) only: VBUS on, **nothing attached** but a passive inline USB-C meter, a 30 s soak under the 1 s guard, then the tool's own undo switches VBUS off **in the same run**: a hot port is never left standing without the guard (`P/run`, the `b5-host` case after the soak). The dwc3 controller stays in device role, so nothing could enumerate anyway, and the only overcurrent detection is the tool's 1 s voltage poll. Attached devices (a keyboard, a flash drive, an Ethernet dongle) are **not** done from userspace: they go through the kernel path in section 7, with its own runbook next to that kernel pull request. The `--device` mode of the earlier tool is removed; `husky-deadman-phone` refuses the option.

What stage (a) answers: does Google's external-boost sequence, replayed from userspace with the bypass registers programmed, put about 5 V on the port, and does it go away on the undo. What it does not answer: anything about load, overcurrent behaviour, or the data path.

## 1. Google's sequence, the functions to read

Stock husky's charger node has `max77759,ext-otg-only`, `max77759,bst-on = <max777x9_gpio 4>` (GPIO5), `max77759,extbst-ctl = <max77759_tcpc_gpio 0>` (the TCPC's `VENDOR_EXTBST_CTRL`), `max77759,extbst-mode = <s2mpg14_gpio 4>` and `max77759,bst-lsw-sequence`; no `max77759,usb-otg-mv`, no `max77759,vin-is-valid`. **[verified: S/:3368-3380]**

`G/max77759_usecase.c`, the on path:

| Step | Function | What it does | Lines |
| --- | --- | --- | --- |
| 0 | `gs101_standby_to_otg()` | `mode = EXT_MODE_OTG_5_0V` (because `ext_otg_only`), calls `gs101_otg_enable(uc_data, mode)`, then `gs101_ext_bst_mode(uc_data, 1)` when `ext_otg_only && !wlc_otg_extbst_en`, then 5 ms | 985-996 |
| 1 | `gs101_otg_enable()` default branch (`vin_is_valid < 0`, as on husky) | `gs101_otg_bypass_enable(uc_data, uc_data->otg_value)`; `gs101_ext_mode(uc_data, mode)`; 5 ms; `gs101_ls_mode(uc_data, 1)`; 30 ms ("time for VBUS to be on") | 789-875, default branch 833-857 |
| 1a | `gs101_otg_bypass_enable()` | write `CHG_CNFG_11` = `vbyp`; set `OTG_V_PGM` in `CHG_CNFG_18` | 370-383 |
| 1b | `gs101_ext_mode(EXT_MODE_OTG_5_0V)` | `bst_on` GPIO high (no `bst_sel` on husky) | 220-250 |
| 1c | `gs101_ls_mode(1)` | `gpio_set_value_cansleep(ext_bst_ctl, 1)`: the TCPC's `EXTBST_CTRL` 0x92 bit 0 `EXT_BST_EN`, written as a whole byte by Google's TCPC driver (`ext_bst_en_gpio_set`); the load-switch readback is skipped because husky's node has no `lsw1-is-closed`/`lsw1-is-open` | 144-160; `tcpci_max77759.c:611-618`, `tcpci_max77759_vendor_reg.h:91-92` |
| 2 | `gs101_ext_bst_mode(1)` | s2mpg14 GPIO4 ("extbst mode", FCCM) high | 920-940 |
| – | `gs101_otg_mode()` | returns 0 at once with `ext_otg_only` ("no transition needed if only use external boost OTG"): the charger `MODE` register is **not** switched to the internal boost; the use-case comment for this path reads "5-1: mode=0x0 in MW, EXT_B=1, LS1=1" | 729-737; 945-955 |

The off path (OTG to standby with `ext_otg_only`): `gs101_ext_bst_mode(0)`, `gs101_ls_mode(0)`, `gs101_ext_mode(0)`. **[verified: 1199-1204]** `gs101_otg_bypass_disable()` clears `OTG_V_PGM`. **[verified: 385-389]** Google's TCPC driver also clears 0x92 on every toggle restart. **[verified: tcpci_max77759.c:2021-2022]**

What the tool does with this: steps 1a, 1b, 1c in that order with those delays, `MODE` = 0x00 before them (section 5), and step 2 **not done** (no mainline access to that s2mpg14 GPIO was checked). **[inferred: whether 5 V appears without step 2 is what the meter says in stage (a)]**

## 2. The meter is the measurement

Stage (a) is gated on an **independent** USB-C meter inline on the port, with nothing on its far side: it must read **0 V before** the run, **about 5 V during** (4.75 to 5.25 V is the pass window), and **0 V after** the undo. The TCPC's own `VBUS_VOLTAGE` register (0x70, 25 mV per LSB, **[verified: L/include/linux/usb/tcpci.h:159-161]**) is read and logged by the tool once a second, but it comes from the chip we are driving and is not the check. **[verified: this is the maintainer's review condition]**

The tool refuses `b5-host` without `--meter`, which is the operator's statement that the meter is on and read 0 V. The tool cannot check the meter; the person can.

The same meter answers the charging-current question of issue #1 (how much the charger draws from a source at the 500 mA step): one meter, both measurements. The meter must be passive on CC: if `husky-deadman-phone dump` shows a CC partner with only the meter plugged in, that meter presents a termination of its own and cannot be used for stage (a). **[inferred: the dump's CC line before the run settles it]**

## 3. A hot port, and a reset that leaves it hot

Sourcing from userspace skips Type-C's attach detection: VBUS is on whatever is plugged in. GPIO5 and 0x92 are registers of the MAX77759, not of the SoC (GPIO5 is a PMIC MaxQ register, **[verified: L/drivers/gpio/gpio-max77759.c:99-107, 198-216]**; 0x92 is a TCPC vendor register), so a SoC reset is expected to leave them as they were and the port hot through the reboot. **[inferred: no reset with the boost on has been observed on this phone; the a6 drill is the test]** Three lines of defence, in the order they act:

**Rule (the person).** During a stage, **nothing that can source** is plugged into the port or the meter's far side: no charger, no desktop cable, no powered hub, no meter with its own power. On any trouble, **the load comes out first**, then the software undo. The desktop cable stays out for the whole stage; the way in is Wi-Fi.

**Guard (the tool, once a second).** `CC_STATUS` (TCPC 0x1d): bit 5 `TOGGLING`, bit 4 `TERM` (1 = this port presents Rd, as a sink does), bits 3:2 CC2 and 1:0 CC1; with Rd presented, the values 1/2/3 mean the partner shows Rp default / 1.5 A / 3 A, 0 is open **[verified: L/include/linux/usb/tcpci.h:87-93, and the decode `tcpci_to_typec_cc()` at 246-261, as `tcpci_get_cc()` in tcpci.c uses it]**. A partner Rp is a source on the port; the tool refuses to start with one, and trips the undo at once if one appears while sourcing (`P/cc_partner`, `P/host_guard`). `TERM` = 0 (this port presenting Rp) or the toggling bit set are treated as "not valid": a refusal before the step, a trip after three such reads. Whether the MAX33359 reports a partner Rp in this register while it is itself the one putting 5 V on VBUS: **[inferred from the TCPCI layout; the register is logged every second during stage (a), and a check with a known Rp (a charger) is *not* part of stage (a), see the rule above]**.

**Undo at the next boot (the tool, by itself).** Before its first register write, `b5-host` writes a marker (`/var/lib/husky-deadman/undo-pending`, holding the saved registers and the boot id) and installs `/etc/systemd/system/husky-deadman-undo.service`: `Type=oneshot`, `ConditionPathExists=` that marker, `DefaultDependencies=no`, `After=sysinit.target systemd-udev-settle.service`, `Before=basic.target`, `ExecStart=husky-deadman-phone boot-undo`, enabled for `basic.target`. The unit is written and enabled first, the marker last, so a failed install leaves no marker. It has `TimeoutStartSec=180` (boot-undo waits up to 60 s for the I2C bus and 10 s for the gpiochip) and `RequiresMountsFor=/var/lib/husky-deadman /usr/local/bin`. At the next boot it writes TCPC 0x92 = 0x00 and GPIO5 = 0 and reads both back: that is the port **cold**, and only then the marker and the unit go. Then it clears `OTG_V_PGM` and restores 0xc4 and 0xb9 from the marker; if it cannot (the charger driver loaded, a readback wrong), the saved values go to `/var/lib/husky-deadman/registers-not-restored`, which `b5-host` refuses on until the person has restored them by hand, and the marker still goes (it exists for the hot port, not for the registers, and must not fire at every boot for writes it cannot make). If the port is **not** proven cold, the marker stays and the unit runs again at the following boot (`P/undo_unit_install`, `P/boot_undo`). A clean undo in the same boot removes both as well. The unit cannot run on a normal boot: without the marker the condition fails, and `boot-undo` itself exits at once without the marker. All of this is checked against stubs in `tests/husky-deadman`, not on the phone. **[verified against stubs only, tests/husky-deadman; not run on the phone]**

Unverified about the boot undo: **[unknown]** whether `max77759`, the I2C host and `gpio-max77759` are up by `basic.target` on the phone (the unit waits up to 60 s for the bus and 10 s for the chip, and loads `gpio_max77759` itself; its modprobe block is a `blacklist` line, which an explicit modprobe ignores **[verified: BATTERY-NOTES section 4, M3]**); **[unknown]** whether `libgpiod` is installed on the phone (the device package depends on bash, systemd and the keyring only **[verified: packages/omamobile-device-husky/PKGBUILD]**; `pacman -S libgpiod` first, and the preflight refuses without it).

**Manual fallback (the person, second).** If the phone froze, no software undo ran at all. Then, in this order:

1. Unplug anything on the port (the meter too).
2. Force a restart: hold Power + Volume Up for 15 to 30 s (Power alone does nothing under our kernel). This spends one of slot B's three boot tries: count them, and flash the known-good set first if only one is left (BATTERY-NOTES section 3).
3. First thing after the boot, over Wi-Fi, before anything is plugged in:

   ```sh
   OMAMOBILE_SSH_HOST=root@<wifi-ip> tools/husky-deadman boot-undo     # runs husky-deadman-phone boot-undo
   OMAMOBILE_SSH_HOST=root@<wifi-ip> tools/husky-deadman dump          # 0x92 must read 0x00, gpio5 0, no marker
   ```

   If the tool is not there or fails, by hand on the phone, as one script, so that nothing is deleted before every step has read back right (BUS is the adapter number of `10cb0000.i2c`, `ls -l /sys/bus/i2c/devices/ | grep 10cb0000`; CHIP is `/dev/gpiochipN` from `/sys/bus/platform/devices/max77759-gpio*/`; `max77759_charger` must NOT be loaded, `lsmod | grep max77759_charger` empty):

   ```sh
   set -u; BUS=<n>; CHIP=/dev/gpiochip<N>; M=/var/lib/husky-deadman/undo-pending
   lsmod | grep -q '^max77759_charger ' && { echo "charger driver loaded: stop"; exit 1; }
   i2cset -f -y $BUS 0x25 0x92 0x00 || exit 1
   [ "$(i2cget -f -y $BUS 0x25 0x92)" = 0x00 ] || { echo "0x92 not 0x00"; exit 1; }
   modprobe gpio_max77759; gpioset -c $CHIP GPIO5=0 & sleep 0.2; kill $!
   [ "$(gpioget --as-is -c $CHIP GPIO5)" = '"GPIO5"=inactive' ] || { echo "GPIO5 not 0"; exit 1; }
   # the port is cold. Now the registers, from the saved values in the marker
   cb=$(i2cget -f -y $BUS 0x69 0xcb) || exit 1
   i2cset -f -y $BUS 0x69 0xcb $(printf '0x%02x' $(( cb & 0xf7 ))) || exit 1   # bit 3 OTG_V_PGM clear
   [ $(( $(i2cget -f -y $BUS 0x69 0xcb) & 0x08 )) -eq 0 ] || { echo "0xcb bit 3 still set (CHGPROT 0xbf bits 3:2 = 11 unlocks; relock after)"; exit 1; }
   c4=$(awk '$1=="0xc4"{print $2}' $M); b9=$(awk '$1=="0xb9"{print $2}' $M)
   i2cset -f -y $BUS 0x69 0xc4 "$c4" && [ "$(i2cget -f -y $BUS 0x69 0xc4)" = "$c4" ] || { echo "0xc4"; exit 1; }
   i2cset -f -y $BUS 0x69 0xb9 "$b9" && [ "$(i2cget -f -y $BUS 0x69 0xb9)" = "$b9" ] || { echo "0xb9"; exit 1; }
   rm -f $M; systemctl disable husky-deadman-undo.service; rm -f /etc/systemd/system/husky-deadman-undo.service; systemctl daemon-reload
   echo "undone"
   ```

   Any line that stops leaves the marker, so the unit tries again at the next boot. Only after "undone" plug the meter back in and read 0 V. **[verified against the tool's own stub test for the same sequence; the script itself has not been run anywhere]**

## 4. The charger guard: baseline first

`CHG_DETAILS_01` read 0xb1 in every dump of the day (`BAT_DTLS` 3 = battery okay, `CHG_DTLS` 1 = fast-charge constant current, bit 7 set) with the bootloader's `MODE` 0x05 and the cable out, so a guard that trips on "CHG_DTLS says charging" says nothing: it tripped the first run at once. **[verified: the 2026-11-01 run's log, and the maintainer's review]**

Now:

1. `husky-deadman-phone baseline` (`tools/husky-deadman baseline`) is a new **read-only** step: cable out, Wi-Fi only, the charger driver not loaded, no write anywhere. It reads `CHG_DETAILS_00` 0xb5, `_01` 0xb6 and `_02` 0xb7 five times a second apart and keeps the values for this boot (`/run/husky-deadman/baseline`, with the boot id). A register that does not read the same five times makes the baseline "unstable" and `b5-host` refuses until a stable one is taken. **[verified: P/baseline]**
2. `b5-host` refuses without a stable baseline from **this** boot, and its guard trips on a **change from the baseline** in the fields mainline names: 0xb5 `CHGIN_DTLS` bits 6:5, 0xb6 `BAT_DTLS` bits 6:4 and `CHG_DTLS` bits 3:0, 0xb7 `CHGIN_STS` bit 5 **[verified: L/include/linux/mfd/max77759.h:83-89]**. The other bits are logged and never compared. **[verified: P/chg_vs_baseline, P/host_guard]**
3. The `MODE` 0x00 write (section 5) comes before the boost. Right after it, and before GPIO5, the tool reads the details again and compares with the cable-out baseline: **if MODE 0x00 alone moves them, the run stops there, before any VBUS**, logs the MODE-0 reading, and undoes (MODE back). That is a legitimate end of a first run: it gives the reading the maintainer asked for. The guard then has to be **re-derived against what the registers read with MODE 0x00**, as its own reviewed change, before the next run. **[verified: P/apply b5-host; what MODE 0x00 does to CHG_DTLS is unknown until that run]**

## 5. The bypass registers, and MODE

Google programs the charger's OTG bypass before `bst_on` (section 1, step 1a). The tool now does the same, with these values:

- `CHG_CNFG_11` 0xc4 = **0x00**. `otg_value` comes from `max77759,usb-otg-mv`, which stock husky's node does not have, so the default `GS101_OTG_DEFAULT_MV` = `MAX77759_OTG_5000_MV` = 5000 mV is used, and `max77759_otg_vbyp_mv_to_code()` gives `(5000 - 5000) / 50` = 0 (12000 mV and above gives 0x8c). **[verified: G/max77759_charger.c:40-41, 3331-3340; G/max77759_usecase.c:1281-1292; S/:3368-3380 has no usb-otg-mv]** (The earlier design note's 5100 mV / code 0x2 is `GS101_OTG_VBYPASS_DEFAULT_MV`, used for `otg_vbyp`, the wireless path, usecase.c:1372; not this one.) The register's power-on default is 0x00 as well **[verified: G/max77759_v0p65_121919_regs.h:1993-1996]**, so on a fresh boot this write changes nothing; it is still done and read back, so the sequence is Google's.
- `CHG_CNFG_18` 0xcb bit 3 `OTG_V_PGM` set, by a read-modify-write of that bit only; the undo clears it (as `gs101_otg_bypass_disable()` does) and restores 0xc4. **[verified: `MAX77759_CHG_CNFG_18_OTG_V_PGM (0x1 << 3)` in G/max77759_A1_regs.h:2380-2392 and in G/max77759_v0p65_121919_regs.h:2281-2303]** Google's shipping driver includes `max77759_regs.h`, which includes `max77759_A1_regs.h`; both headers give bit 3, so this is not a register-map version question. **[verified: G/max77759_regs.h:11]** The earlier design note said the bit's position was unknown; it was in these headers. Limit: the headers are machine-generated from a register-map CSV ("source MW_regmap_ds_v0p65_121919.csv"), and no datasheet was read; the bit is where Google's code writes it, which is what we replay.
- Whether 0xcb takes the write without the `CHGPROT` unlock (`CHG_CNFG_06` 0xbf bits 3:2 = 11, as mainline's probe does for `WDTEN` in the same register, **[verified: L/drivers/power/supply/max77759_charger.c:145-149, 642-657]**): **[unknown]**. The tool writes, reads back, and only if the readback disagrees unlocks `CHGPROT`, retries, and puts 0xbf back to what it was. 0xbf is saved before the step. (Google's `max77759_chgr_reg_update()` is not in the files we have, so whether Google unlocks here is **[unknown]** too.)
- Both registers are saved before the step and restored by the undo and by the boot undo. **[verified: P/host.saved, P/restore_bypass_mode; tests/husky-deadman]**
- The tool refuses `b5-host` while `max77759_charger` is loaded (unchanged): the MFD registers the charger regmap with a flat cache that is volatile only for 0xb0-0xb1 and 0xb4-0xb8, so an `i2cset` to 0xc4/0xcb behind a loaded driver would be written back stale by its next `regmap_update_bits`. **[verified: L/drivers/mfd/max77759.c:154-186]**

`MODE` (`CHG_CNFG_00` 0xb9): written to 0x00 for the duration and restored by the undo. Google keeps the charger mode at 0 on this path (section 1); the first run, with the bootloader's 0x05 left on, saw CHG_DTLS in "charging" at once (section 4). **[verified: G/max77759_usecase.c:729-737, 945-955; the 2026-11-01 log]** Whether the charger's CHGIN sees the self-sourced 5 V at all (whether LSW1's output is isolated from CHGIN): **[unknown; the baseline comparison while sourcing is the test]**.

Writing 0x92 with `i2cset -f` while `tcpci_maxim` is bound is fine for research with the tool's "0x92 changed under us" guard (the maintainer's note): mainline's `tcpci_maxim` never touches 0x92 (its only vendor writes are to 0x93, and its regmap allows writes through 0x95), so nothing in our kernel races the byte. **[verified: L/drivers/usb/typec/tcpm/tcpci_maxim_core.c:25-27, 40-52]** The guard trips if 0x92 stops reading 0x01 while sourcing. This stays research: the kernel path (section 7) owns the byte for good.

## 6. The runbook: stage (a)

Preconditions the tool enforces (each a refusal, nothing applied): Pixel 8 Pro by compatible; Wi-Fi up; `max77759_charger` blocked in `modprobe.d` and not loaded; `max77759` loaded; `b4-tcpm` applied in this boot (`tcpci_maxim` bound, `typec/port0` with `power_role [sink]`); the `usb-role-test` overlay's dwc3 role file reading `device`; the USB gadget not configured (desktop cable out); `gpio-max77759` and libgpiod v2 (`gpioget --as-is`); GPIO5 reading 0; 0x92 reading 0x00; `POWER_CTRL` bit 6 clear (VBUS monitor on); `POWER_STATUS` bits 4/2/0 clear; TCPC VBUS reading at most 0.8 V; CHGIN not valid; `MODE` without a boost bit; no partner on CC; a stable baseline from this boot, and the details still matching it; no undo marker from an earlier boot; `--meter`; battery 3.0 to 4.15 V, 10 to 40 C and not exactly 22.0 C, 30 to 80 %; one `b5-host` per boot. **[verified: P/preflight, P/preflight_host]**

What stays as the review approved it: the battery and temperature limits and the 1.7 A trips, one run per boot with the latch (`b5-done`) left alone, runs started by hand with the person watching the meter and the kernel log, and the slot B tries refilled with a flash before a stage that can reset the phone.

| # | Step | Commands (desktop, over Wi-Fi) | Expect / pass | Stop | Rollback | Risk |
| --- | --- | --- | --- | --- | --- | --- |
| a0 | Image | `bin/omamobile flash` of the e1 images with `typec-test` and `usb-role-test` applied (refills slot B's tries) | boots, Wi-Fi up, `/sys/class/usb_role/11210000.usb-role-switch/role` reads `device` | no role file, no Wi-Fi | flash the known-good set | reboot (one try) |
| a1 | Read-only | `tools/husky-deadman dump` with the cable out and the meter in | 0x92 0x00, gpio5 0, CC partner none, VBUS at most 0.8 V, meter 0 V, no marker | CC partner shown with only the meter in (the meter is not passive) | none | none |
| a2 | Baseline | `tools/husky-deadman baseline` | `ok`, three registers each stable over 5 reads, written to the log | "unstable": wait, take it again | none (read-only) | none |
| a3 | Type-C driver | `tools/husky-deadman b4-tcpm` (its own preflight and soak) | `power_role [sink]`, USB not needed | any b4 trip | `tools/husky-deadman undo b4-tcpm` | as b4 |
| a4 | Source | `tools/husky-deadman b5-host --meter` (soak 30 s, then the tool's own undo) | **three outcomes are expected, and the first run very likely ends in the first:** (a4') the run stops right after MODE 0x00 because the charger details moved off the cable-out baseline (the baseline was taken at the bootloader's MODE 0x05, so `CHG_DTLS` is expected to change): the MODE-0 reading is in the log, MODE is restored, no VBUS was ever on; (a4'') the sequence completes and the TCPC reads under 4.5 V: "no 5 V from the external boost on this path" is logged and the undo runs; `gs101_ext_bst_mode` (s2mpg14 GPIO4) was skipped, so this is an allowed result, not a fault, and the next step is that GPIO as its own reviewed change; (a4) "VBUS up" 4500-5500 mV, **meter 4.75-5.25 V**, details unchanged, battery current up by tens of mA at most, CC no partner, then after 30 s "SOAKED and UNDONE" and the **meter at 0 V** | a trip, the meter disagreeing with 0x70 by more than 0.3 V (write both down), the meter not at 0 V after the undo, anything warm | automatic (the run ends in the undo in every outcome); if the meter still shows VBUS: unplug the meter, section 3 fallback | VBUS on the port with nothing attached; 1 s poll only; bst_on is high about 0.2 s before 0x92 (the tool's gpioset hold and readback), not Google's 5 ms, **[inferred: a longer settle in the same direction, logged]** |
| a5 | Check | `tools/husky-deadman dump` | 0x92 0x00, gpio5 0, 0xcb bit 3 clear, 0xc4 and 0xb9 as before, no marker, no `registers-not-restored`, **meter 0 V** | anything else: section 3 fallback | section 3 | none if a4 ended clean |
| a6 | Boot undo, drill | a later boot only, with the maintainer's go, and only once a4 has shown VBUS: run a4 with `--soak 120` and, during the soak, reboot the phone **by software** (`reboot-to omamobile`) with the meter in. The phone tool runs as a transient unit and has no signal trap **[verified: no `trap` in P/]**, so the reboot's SIGTERM kills it without an undo: the port stays as the PMIC keeps it and the boot undo is what switches it off | the meter reads 0 V after the boot; `journalctl -u husky-deadman-undo` shows it ran with "port cold: 1"; marker and unit gone | the meter still at 5 V after the boot: section 3 fallback (unplug first) | section 3 | a hot port through one reboot; one slot B try |

Record in the pull request: the log lines of a2, a4 (which outcome) and a5, the meter readings before/during/after, the kernel release, and the count of slot B tries left.

## 7. Attached devices: the kernel path, later

Not in this pull request, and not from userspace: a `regulator-fixed` on MAX77759 GPIO5 as the TCPC node's `vbus-supply` (never `regulator-boot-on` or `regulator-always-on`), the connector made dual role with `try-power-role = "sink"`, so that TCPM sources only after a sink (Rd) attaches and stops on detach, and `tcpci_maxim` taught to set and clear `EXTBST_CTRL` 0x92 bit 0 around the regulator enable and disable, with the register and bit cited from Google's driver in the same pull request (`tcpci_max77759_vendor_reg.h:91-92`, `tcpci_max77759.c:611-618, 2021-2022`) and a binding for it. The bypass registers of section 5 then belong in the charger driver, through its regmap. That pull request gets its own runbook alongside it (stage (b) with the meter and a 5 Ω test load question still open, then devices). Until then the connector stays sink-only and `b5-host` is the only thing that ever sources. **[verified: HOST-MODE-PLAN.md 1.1, 2.1, 2.2; L/drivers/usb/typec/tcpm/tcpci_maxim_core.c:210-251 for why `vbus-supply` must not be set before the 0x92 change exists]**

## 8. Unknowns in one place

1. Whether 5 V appears without `ext_bst_mode` (s2mpg14 GPIO4): the meter in a4.
2. Whether the MAX33359's 0x70 reading agrees with the meter: a4, both written down.
3. What MODE 0x00 does to CHG_DETAILS with the cable out: a4' (the expected first outcome); the guard is then re-derived against it.
4. Whether CHGIN sees the self-sourced VBUS: the baseline comparison in a4.
5. Whether 0xcb needs the CHGPROT unlock: the readback in a4.
6. VBUS fall time after the undo: a5, the meter.
7. Whether `basic.target` is late enough for the I2C bus and the gpiochip, and whether libgpiod is on the phone: a1 (`pacman -Q libgpiod`) and a6.
8. Whether `CC_STATUS` reports a partner Rp while this chip sources: not tested in stage (a) (the rule forbids a source on the port); the register is logged every second.
9. Whether GPIO5 and 0x92 keep their values across a SoC reset: a6.
10. Whether `VBUS_VOLTAGE` ever reports a non-zero TCPCI scale factor (bits 11:10) on this chip: the tool treats such a word as unreadable rather than scaling it; a4 shows whether it happens.

Not in this runbook: the read-only Baseus 500 mA re-run the maintainer asked for on issue #1 (the same meter, a separate note).
