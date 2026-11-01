<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 Pro (raven): USB

Status (2026-10-28): charging works at stock limits with the temperature guard (section 4, C0-C5 passed). USB 2 device mode works (NCM and ACM, SSH at
172.16.42.1) with a raven-only DT change that makes dwc3 a USB 2
peripheral and drops `orientation-switch` from the PHY. The PR review of
the boot glue (derekross/linux-omarchy-mobile#2) asked to keep upstream's
USB description in `gs101-pixel-common.dtsi`, so that change now lives
only in `omamobile-gs101-int`, as a NOT FOR MERGE commit. Open: U1, does
upstream's description work as it is?

## 1. Goal

USB device mode on raven with upstream's DT unchanged: dwc3 dual-role
behind the USB role switch, `orientation-switch` on the PHY, the MAX77759
TCPC described. Later, a TCPC driver that owns the port (host mode,
orientation, charging contracts), as cheetah's [USB-C-PLAN](../cheetah/USB-C-PLAN.md).

## 2. Facts

- [V] With upstream's DT and pmOS's 7.0.6 kernel (2026-10-14,
  [BRINGUP-M1](BRINGUP-M1.md) section 7), dwc3 ran dual-role at
  super-speed-plus, its SS link stayed `SS.Disabled` and USB 2 never
  connected.
- [V] `dr_mode = "peripheral"` without `usb-role-switch` made dwc3 defer
  forever ("failed to get extcon", through the PHY's port graph to the
  TCPC).
- [V] With `orientation-switch` on the PHY, phy-exynos5-usbdrd forced
  `UTMI_FORCE_VBUSVALID | UTMI_FORCE_BVALID` only once a TCPC reported an
  orientation, so dwc3's link stayed `Disconnected`.
- [V] `omamobile` now has `4d015fb82` ("phy: samsung: usbdrd: keep VBUS
  valid until Type-C reports a connection"): with an orientation switch,
  the PHY keeps forcing VBUS valid until the port controller first
  reports an orientation. None of the raven kernels above had it.
- [V] `tcpci_maxim` is blacklisted on raven (`omamobile-raven.conf`), so
  no TCPC driver runs; `omamobile-usb-rescue` closes the MAX77759 data
  switch after an unplug.
- [V] On a wall charger the rescue doesn't change charging (2026-10-27,
  `gb3d6253b0d61`, logged every 2 s with the cable out): `USBSW_CTRL` read
  0x09 the whole time, so the rescue never wrote it, and the battery
  charged at a median of 1.39 A with the rescue running, 1.45 A with it
  stopped and 1.62 A with it running again (rising as the battery warmed,
  40 to 45 %, screen on throughout). This charger never held the switch
  at 0x24, the case the rescue backs off from; that one is untested on
  raven.
- [A] With `4d015fb82`, upstream's description should enumerate as a USB 2
  device: the role switch defaults to peripheral and the PHY keeps VBUS
  valid. SuperSpeed may still not train; device mode over USB 2 is enough.

## 3. U1: upstream's USB description (boot B)

Kernel: `omamobile-gs101-int` without its NOT FOR MERGE USB commit (the
only difference from boot A, [GPU-PLAN](GPU-PLAN.md) G5). Run only after
G5 has passed, on a separate occasion, with time to recover.

**U1.0 (offline, before the day):** build the boot B images from `-int`
with the USB commit reverted, into their own output directory; keep the
boot A images as the rollback. Check that the DTB differs from boot A's
only in `usb@0` (`dr_mode`, `maximum-speed`, `phys`, `phy-names`,
`role-switch-default-mode`) and the PHY's `orientation-switch`.

**U1.1 (push, reboot; the human approves and stays at the phone):**

- **Screen:** the phone reboots.
- **Expect:** SSH within about 60 s as usual.
- **Stop:** no USB device on the laptop after 3 minutes. Do not send
  more commands.
- **Rollback (no USB):** Volume Down + Power about 20 s for fastboot,
  then `bin/omamobile flash` with boot A's `KERNEL_OUT`. Slot A's
  GrapheneOS can't boot over Omarchy's `userdata`, so fastboot is the only
  way back; check before U1.1
  that `fastboot devices` sees the phone from the bootloader.
- **Risk:** high: USB is the only link.

**U1.2 (read-only, if SSH came back):**

```sh
tools/phone-ssh 'dmesg | grep -iE "dwc3|usbdrd|role|extcon|orientation" | head -20
cat /sys/class/udc/*/state /sys/class/udc/*/current_speed
ls /sys/class/usb_role/ 2>/dev/null; cat /sys/class/usb_role/*/role 2>/dev/null'
```

- **Pass:** UDC `configured`, `high-speed` (or better), the role switch
  reads `device`; an unplug and replug still reconnects.
- **Result:** if U1 passes, the NOT FOR MERGE USB commit goes away and
  #2 needs no USB follow-up. If it fails, the peripheral setup stays a
  raven bring-up change, described in this plan.

## 4. Charging: the MAX77759 charger (raven's B3, after cheetah's)

**Why:** with no charger driver the chip runs on the bootloader's settings.
A wall charger charges (1.1-1.6 A into the battery, 2026-10-27 and -28),
but there is no battery temperature guard from Linux, the float voltage
is 4.35 V where stock goes to 4.45 V (cheetah's stopped at 93 % this way),
and the fast charge current is 1.93 A where stock's table allows 0.3 C at
10-20 degC. A laptop port doesn't keep up with the phone's load.

**What exists:** our kernel's `max77759_charger` has cheetah's
`default_ilim_ua` and `temp_guard` (USB-C-PLAN section 3, B3g). The MFD
creates the charger cell on raven too; it only lacked a battery
description. Kernel `omamobile-gs101-charging` (`83a07fa16` label the
PMIC, `75a486ca3` the battery: 4905 mAh, 4.45 V, 1466730 uA, from stock's
`google,battery`/`google,charger` in `dtbo_idx` 6), cherry-picked onto
`omamobile-gs101-int-power`; upstream as
derekross/linux-omarchy-mobile#112. checkpatch clean, W=1 device trees with no
new warning, dt-validate with no new finding (raven's one finding,
`soc_id`, is the base's). The package side (C4) adds
`omamobile-charge-guard` (cheetah's) and loads the charger at boot.
The guard's bands are raven's own, not only cheetah's: raven's stock
`google,chg-temp-limits`, `chg-cv-limits` and `chg-cc-limits` (`dtbo_idx` 6)
are identical to the table in the charger's temperature guard (checked in
review, derekross/linux-omarchy-mobile#112).

**C0 (2026-10-28, `g97f09c8cfada`, read-only, on the wall charger at
21 %): passed.** `i2cget -f -y 2` (bus `i2c-2`, `10d50000.i2c`):

| Reg | Value | Meaning |
|---|---|---|
| 0x69/0xb9 CHG_CNFG_00 | 0x05 | mode 5, charger and buck on |
| 0x69/0xbd CHG_CNFG_04 | 0x23 | float voltage 4350 mV |
| 0x69/0xbb CHG_CNFG_02 | 0x1d | fast charge 1933 mA |
| 0x69/0xc2 CHG_CNFG_09 | 0x13 | input limit 500 mA, NO_AUTOIBUS clear |
| 0x69/0xbf CHG_CNFG_06 | 0x0c | protected registers unlocked |
| 0x69/0xc5 CHG_CNFG_12 | 0x6a | CHGINSEL 1 |
| 0x69/0xcb CHG_CNFG_18 | 0x00 | no charger watchdog |
| 0x69/0xb5 CHG_DETAILS_00 | 0x60 | VBUS valid |
| 0x69/0xb6 CHG_DETAILS_01 | 0xb1 | CC phase, battery OK |
| 0x25/0x00-01 | 0x6a 0x0b | Maxim |
| 0x25/0x93 USBSW_CTRL | 0x09 | data switch closed |

The battery charged at 823 mA then (1.1-1.4 A earlier) with a 500 mA
input limit: with NO_AUTOIBUS clear the chip sets the input current from
its own charger detection. The driver writes only CHGIN_ILIM (bits 6:0)
and leaves that bit, so with `default_ilim_ua=500000` (the value already
there) a wall charger should still charge at the chip's own rate. C2
checks it.

**Runbook (each step the owner's go; the phone on the wall charger, the
session over Wi-Fi: the charger doesn't touch the USB data path,
USB-C-PLAN section 2):**

| Step | What | Expect / pass | Stop | Rollback | Risk |
|---|---|---|---|---|---|
| C1 | push the kernel with the battery description (`omamobile-gs101-int-power` + the two commits), reboot | boots as before; `/proc/device-tree/.../pmic@66/monitored-battery` present; `max77759_charger` still not loaded; charging as in C0 | boot failure | slot A, or the previous images | low |
| C2 | by hand: `modprobe max77759_charger default_ilim_ua=500000 temp_guard=1`, then the C0 dump and `omamobile-charge-guard status` | a `max77759-charger` power supply; CNFG_04 0x2d (4.45 V), CNFG_02 0x16 (1467 mA), CNFG_00 mode 5 within seconds, CNFG_09 0x13 with bit 7 clear; the battery still charging at about 1 A or more; the guard reading the gauge | mode not 5 after 30 s, the battery discharging on the wall charger, any driver error | reboot (the bootloader sets mode 5 again) | low-medium |
| C3 | G2 as cheetah: `modprobe -r max17042_battery` with the guard on | within 30 s the guard logs no reading and stops charging (mode 4); after reloading the gauge, charging comes back | charging continues without a reading | reload the gauge, or reboot | low |
| C4 | device-raven: drop the blacklist, `options max77759_charger default_ilim_ua=500000 temp_guard=1` and the gauge softdep, as cheetah's `omamobile-charger.conf`; reboot | the charger loads at boot; C2's readings | as C2 | blacklist again | low |
| C5 | attended, on the wall charger to full | CV phase, then done at 100 % (not 93 %) | battery over 45 degC | unplug | low |

**C1 (2026-10-28, `g3ba8c15c89b8`): passed.** Pushed from the build
checkout with the phone's own inputs (raven's `kernel.config`, its overlay
list, the splash file: 1809 modules, as before). Boot check `ok`;
`pmic@66` has `monitored-battery`; `max77759_charger` not loaded,
CHG_CNFG_00 still 0x05; haptics loaded. On the laptop port the battery
discharged at about 600 mA, as before.


**C2 (2026-10-28, `g3ba8c15c89b8`, on the wall charger at 26 %, 22 degC):
passed.** `modprobe max77759_charger default_ilim_ua=500000 temp_guard=1`:
`found: mode 0x5, float voltage 4350 mV, fast charge 1933420 uA, input
limit 500000 uA`, then `probed: mode 0x5, float voltage 4450 mV, fast
charge 1466730 uA`, `temperature guard on (max170xx_battery)`, `battery
22.0 C, 3834 mV: band 20-42 C, float 4450 mV, charge 1466730 uA`.
Registers: CNFG_00 0x05, CNFG_04 0x23 -> 0x2d, CNFG_02 0x1d -> 0x16,
CNFG_09 0x13 (bit 7 clear) unchanged, CNFG_06 0x0c -> 0x00 (locked),
CNFG_18 0x00. The battery charged at 1195-1438 mA over the next 30 s
(charger `Charging`, `Fast`, online): the chip's own input detection still
sets the input on a wall charger with the driver loaded.

**C3 (2026-10-28, the same boot, on the wall charger): passed.**
`modprobe -r max17042_battery` with the guard on: 25 s later (its next
30 s check) `no reading from max170xx_battery: charging inhibited`,
CNFG_00 0x05 -> 0x04 (buck only), DETAILS_01 0xb1 -> 0xb8, charger
`Discharging`. After `modprobe max17042_battery`, within 10 s CNFG_00
0x05 and the battery charging at 1440 mA, `band 20-42 C, float 4450 mV,
charge 1466730 uA`.

**C4 (2026-10-28, `g3ba8c15c89b8`, device-raven 0.1.23.3): passed.** The
charger loads at boot from `omamobile-charger.conf` (the blacklist
dropped): a minute after boot `omamobile-charge-guard status` showed the
guard on, 22 degC, `Charging (Fast, health Good)`, float 4450 mV, fast
charge 1466 mA, input limit 500 mA, and 1345 mA into the battery on the
wall charger; CNFG_00/04/02/09 0x05/0x2d/0x16/0x13. **Next: C5**, a full
charge on the wall charger (expect CV, then done at 100 %, not 93 %).

**C5 (2026-10-28, `gdd5e1655ef91`, on the wall charger): passed.** The
battery reached 100 % (not the 93 % the bootloader's 4.35 V stopped at), at
4411 mV and 22 degC, the charger then topping off in CV (`DETAILS_01` 0xb2,
873 mA).
