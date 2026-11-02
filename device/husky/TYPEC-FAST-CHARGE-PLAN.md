<!-- SPDX-License-Identifier: MIT -->
# Pixel 8 Pro (husky): Type-C and fast charging, plan

Last updated: 2026-11-02. Written 2026-11-01 from source reading and that day's measurements; stages 0, 3 and 4 have run (results in [BATTERY-NOTES.md](BATTERY-NOTES.md) section 7.2). Claims: **[V]** checked in a file or on the phone, **[I]** inferred, with what settles it.

## 1. Where things stood before the Type-C step (2026-11-01, kernel `7.3.0-rc6-omamobile-push1-g5899fec2bd28`)

- Charging works: `max77759_charger` loaded under `tools/husky-deadman` (`b3-charger`, 500 mA), status `Charging`. On a USB-A wall charger with an A-to-C cable, screen off: net battery current +30..+70 mA, voltage rising, 35 C. On the desktop port: about -40..-80 mA. On a 30 W USB-PD charger with a C-to-C cable, screen off: +1.50 A, 4.004 V, 33 C, TCPC `CC_STATUS` 0x1c (CC2 at the 3.0 A level by the TCPCI layout **[I]**), charger input limit 0xc2 still 0x13 (500 mA), 0xbb 0x17; no Type-C driver loaded. About 49 mAh per percent, so about 1 % per hour on the weak sources. **[V: the charge logs, kept locally]**
- With the USB-A sources the TCPC read `CC_STATUS` 0x11 (default Rp only) and `POWER_STATUS` 0x0c (VBUS present). No TCPM driver ran, so no PD messages were sent or seen. **[V]**
- `tcpci_maxim`: the DT node `usb-typec@25` is complete (sink-only, `pd-disable`, sink PDOs 5 V 3 A / 9 V 2.2 A / PPS) but `status = "disabled"`; the module is built and blocked by the device package. **[V: zuma-husky.dts, the package's modprobe file]**
- The earlier wall-charger run at 900 mA (input register 0x23 on all 180 samples) averaged only +22 mA, so 500 to 900 mA barely changed the battery current: either the phone's own draw takes most of it or the source limits. **[I: an inline meter settles it]**

## 2. The limiter chain

There is no single limiter to lift. In order: what the source advertises (CC Rp, or PD) -> the current TCPM hands to the charger -> the input limit register 0xc2 (500 mA = 0x13, 900 mA = 0x23; the driver clamps at 900 mA when TCPM reports 0 because Rp is default) -> the battery current cap (DT 1.485 A, float 4.2 V) -> the PCA9468 direct charger (no driver). A default-Rp source gives no reason to raise 0xc2 by hand. The float, the 1.485 A cap, the temperature table and the PCA9468 are the maintainer's call: keep 4.2 V and 1.485 A, raise nothing before the Type-C step and its temperature guard are reviewed. **[V: the maintainer on issue #1]**

What "fast" could mean here: default Rp only, no gain; Rp 1.5/3 A, up to the 1.485 A battery cap inside the 1.7 A / 45 C trips; PD fixed 9 V without the direct charger, about 1.485 A at 4.2 V into the pack, about 6 W; stock-style fast charge needs PPS plus a PCA9468 driver that does not exist.

## 3. Stages

| # | Stage | Cost | State |
| --- | --- | --- | --- |
| 0 | Read-only 1 Hz log (`i2cget` only, no scans) of TCPC 0x10/0x11/0x1a/0x1d/0x1e/0x2f/0x93 and charger 0xb5-0xb9/0xc2, desktop port then charger. Stop on anything that needs a write. Rollback: unplug | none | done 2026-11-01 (section 1) |
| 1 | Idle-power check: charger loaded, 500 vs 900 mA on the same source, screen off, Wi-Fi on | one reboot between `b3` runs | not done; the inline meter answers it better (HOST-MODE-RUNBOOK section 2) |
| 2 | Wi-Fi-only drill: SSH over Wi-Fi with the USB cable out, replug, the rescue restores the data switch | none | done (BATTERY-NOTES section 8) |
| 3 | Enable the Type-C node, module still blocked: overlay `overlays/typec-test.dtso` sets `usb-typec@25` to `okay`. Pass: `/sys/bus/i2c/devices/<bus>-0025` exists with no driver, USB and the rescue fine | one reboot | done 2026-11-01 20:06 (BATTERY-NOTES 7.2) |
| 4 | Load `tcpci_maxim` with `pd-disable` under the dead-man (`b4-tcpm`, the port of cheetah's `b4a-tcpm`): desktop port first, Wi-Fi as the way in, rescue stopped first. Undo: `modprobe -r tcpci_maxim tcpci tcpm`, 0x93 = 0x09 if VBUS is valid, rescue restarted. Stop: a hard reset or contaminant state in the tcpm log, 0x93 not 0x09 with VBUS valid, both links dead, the battery guard | none by itself | done 2026-11-01 20:09, and with the charger loaded 20:21 (BATTERY-NOTES 7.2) |
| 5 | A charger on the Type-C stack: worthwhile only if it shows Rp 1.5/3 A; the input then follows TCPM inside the guard | none | the desktop port already showed 3.0 A and drove 0xc2 to 0x77 (BATTERY-NOTES 7.2); a wall charger not yet |
| 6 | PD on (drop `pd-disable`, fixed 9 V, the PPS APDO removed from the sink list), after the maintainers sign off (9 V into the MAX77759's default input OVP; float stays 4.2 V) | one reboot | not started |
| 7 | Not now: PCA9468, PPS direct charge, any limit above 4.2 V / 1.485 A, `devinfo` or boot-success writes | | each needs the maintainers |

Host mode (sourcing VBUS) is its own plan: [HOST-MODE-PLAN.md](HOST-MODE-PLAN.md) and [HOST-MODE-RUNBOOK.md](HOST-MODE-RUNBOOK.md).

## 4. Retry budget

Every reboot of slot B spends one of its three tries, and at zero the bootloader falls back to slot A (BATTERY-NOTES section 9). Stages 1, 3 and 6 each cost a reboot; re-flash the known-good image set to refill to three before them.
