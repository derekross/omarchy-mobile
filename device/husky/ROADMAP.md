<!-- SPDX-License-Identifier: MIT -->
# Pixel 8 Pro (husky) roadmap: from "boots" to an everyday phone

Written 2026-10-31 by Lef ([@Somnius](https://github.com/Somnius)). The original roadmap for this port stops at "boots" ([issue #1](https://github.com/derekross/omarchy-mobile/issues/1)), and that bar is met on the units tested so far: Omarchy runs from slot B and unlocks by touch. This page is the rest of it, one row per subsystem, in the order of the columns in [docs/DEVICES.md](../../docs/DEVICES.md). For each it says what works, who is on it, the closest finished work to copy from (the Pixel 9a, `tegu`, has a newer Tensor SoC (zumapro) than husky's zuma [I: neighbouring generations, so device-tree work should carry over in part], and the Pixel 7 Pro, `cheetah`, has a plan for almost everything), what is in the way, and a first step that is read-only (no flashing). Credits are at the end.

Facts are marked [V] (checked, with the source) or [I] (an inference, with what would settle it). Pull request states are as of 2026-10-31. Nothing here asks anyone to skip the safety rules: read-only first, one change per boot, a read-only backup of the modem and calibration partitions before radio, PMIC, AoC or Trusty work ([AGENTS.md](../../AGENTS.md) §1, [CONTRIBUTING.md](../../CONTRIBUTING.md) §3). Kernel PR numbers are in [derekross/linux-omarchy-mobile](https://github.com/derekross/linux-omarchy-mobile), written `kernel #N`.

## What works today

Two units are in play: Brett's (Samsung 128 GB UFS 3.1) and Lef's (Kioxia 256 GB UFS 4.0; see [NOTES.md](NOTES.md)). Results below say which unit unless both did them. Kernel: `omamobile` plus Brett's `husky-test-20261031-c6` tag.

- **Boot** from slot B, with stock or GrapheneOS on slot A as the way back. Slot B is deliberately never marked successful, so ABL gives it three boots ([BRINGUP-M1](BRINGUP-M1.md), [UFS-PLAN](UFS-PLAN.md)).
- **UFS** at HS-G4, two lanes, behind the read-only guard, on both device vendors ([UFS-PLAN](UFS-PLAN.md) U2 passed on the Kioxia unit).
- **USB gadget** networking and SSH, and the watchdog driver (no 80 s reset).
- **Display** as a simple framebuffer: console, lock screen and the shell at 1344x2992. Its physical size is reported wrong (355x791 mm instead of about 70x155) until [kernel #154](https://github.com/derekross/linux-omarchy-mobile/pull/154), which adds the panel size. With the wrong size the on-screen keyboard is far too short (105 px, 11% of the screen); with 70x155 mm it is 196 px (21%) [V: measured on the Kioxia unit].
- **Touch** (STMicroelectronics SALIXP over SPI) and **buttons** (`gpio-keys`) on the test tag: raw events decoded in the right corners, swipe, PIN pad, app launching, wake by tap and by Power (both units). In review as [kernel #153](https://github.com/derekross/linux-omarchy-mobile/pull/153) and [#148](https://github.com/derekross/linux-omarchy-mobile/pull/148).
- **Foundations those PRs added:** the ALIVE pin controller, the CMU_TOP and CMU_HSI0 clocks, the ACPM mailbox and protocol driver, the main PMIC (S2MPG14), USI2 and its SPI.

Touch and Buttons are "testing" in `docs/DEVICES.md` since #208, on test kernels with kernel #148 and #153.

## The table

Status words as in DEVICES.md. "9a" is the Pixel 9a (`tegu`) work. "Needs" lists what has to exist first.

| Subsystem | husky now | Who | Closest template | Needs / in the way | First safe step |
| --- | --- | --- | --- | --- | --- |
| Display (DRM driver) | simplefb only | Brett (next, per #1) | 9a: [#88](https://github.com/derekross/linux-omarchy-mobile/pull/88) 120 Hz and per-panel DSIM timers (merged), [#89](https://github.com/derekross/linux-omarchy-mobile/pull/89) panel `google,tg4c` (merged), [#90](https://github.com/derekross/linux-omarchy-mobile/pull/90) DECON0 and DSIM0 device tree (open); cheetah [DISPLAY-PLAN](../cheetah/DISPLAY-PLAN.md) | Google's stock husky overlay has the panel as `samsung,s6e3hc3` on DSIM0 (reset gpa6; vci LDO14M, vddi BUCKA, vddd LDO22M) and a `1344x2992` DSIM mode [V: `dtbo.img` of the GrapheneOS husky 2026102101 package, board "ZUMA HUSKY MP"; choosing that overlay by board id is [I]]. Still needed: zuma's DSIM and DECON windows and clocks, and a `s6e3hc3` panel driver (the 9a's is TG4C) | Read the DSIM/DECON nodes in the stock device tree; write `DISPLAY-PLAN.md`. No flashing |
| GPU | no | Brett (next, per #1) | 9a: [#84](https://github.com/derekross/linux-omarchy-mobile/pull/84) `clk-acpm` with a paired GPU clock (merged), [#85](https://github.com/derekross/linux-omarchy-mobile/pull/85) panthor on the Mali-G715 (open), [#87](https://github.com/derekross/linux-omarchy-mobile/pull/87) CPU DVFS, thermal zones, GPU top levels (open); cheetah [GPU-PLAN](../cheetah/GPU-PLAN.md) | CMU_G3D clocks for zuma (the clock driver in #153 has TOP and HSI0 only; `clk-zuma.c` exists, so this extends it); a **zuma variant of `clk-acpm`**: #153's ACPM match data names `zuma-acpm-clk`, but no driver registers it, and the phone's module aliases list gs101, gs201 and zumapro only [V]; an OPP table and a GPU thermal zone (enable the G3D clocks only after thermal zones and DVFS exist, as 9a #87 does); whether husky's GPU is the same Mali generation as the 9a's [I: check Google's tree] | Read Google's G3D node and clock tables; write `GPU-PLAN.md`. Today there is no render node (`tools/phone-smoke`: "GPU: no render node" [V]), so the shell is drawn in software by Mesa [I: not profiled; `phone-smoke` only shows the missing render node] |
| Touch | testing (c6) | [Brett](https://github.com/greenbrettmichael) | done | [#153](https://github.com/derekross/linux-omarchy-mobile/pull/153) in review; the ACPM probe order fix (Brett); W4HO's [#150](https://github.com/derekross/linux-omarchy-mobile/pull/150) fixes the SPI FIFO flush for every port (not needed for touch) | none: re-test after each kernel |
| Buttons | testing (c6) | Brett | done | [#148](https://github.com/derekross/linux-omarchy-mobile/pull/148) in review | none |
| USB net | testing | Brett (per his comments on #1) | done | USB host and Type-C are in Charging | none |
| Wi-Fi | no | Brett (per his comment on #1) | 9a [#56](https://github.com/derekross/linux-omarchy-mobile/pull/56) (BCM4383, open); cheetah [#143](https://github.com/derekross/linux-omarchy-mobile/pull/143) (BCM4389, open); [WIFI-BATTERY-PLAN](../cheetah/WIFI-BATTERY-PLAN.md) | BCM4398: the PCIe link comes up (Gen3 x1, `14e4:4444`), then `brcmfmac` stops at "chip backplane type 6 is not supported": the chip uses Broadcom's newer NCI interconnect, which Brett is porting from Google's GPL driver ([his status on #1](https://github.com/derekross/omarchy-mobile/issues/1#issuecomment-6543682102)) | Review and test his branches when they appear; read WIFI-BATTERY-PLAN W1 to W4 meanwhile |
| Bluetooth | no | unassigned | 9a [#122](https://github.com/derekross/linux-omarchy-mobile/pull/122) (open); cheetah [BLUETOOTH-PLAN](../cheetah/BLUETOOTH-PLAN.md) | The controller is probably the combo chip that does Wi-Fi [I]; its UART, power and wake lines [I: not known to me] | Find the Bluetooth node in Google's tree; write `BLUETOOTH-PLAN.md` |
| Battery | no | Lef | cheetah [POWER-PLAN](../cheetah/POWER-PLAN.md), [WIFI-BATTERY-PLAN](../cheetah/WIFI-BATTERY-PLAN.md); `gs201-cheetah.dts` has the same chip family. The 9a's [#119](https://github.com/derekross/linux-omarchy-mobile/pull/119) is the MAX77779 and does not apply as is | Stock overlay [V, same source as Display]: fuel gauge `maxim,max77759` @0x36, charger `max77759chrg` @0x69, Type-C `max77759tcpc` @0x25 and `max77729pmic` @0x66, all on `hsi2c_11`; also `nxp,pca9468` and the wireless charger `idt,p9412`. Zuma has no clock controller for that I2C block yet (CMU_PERIC, not in `clk-zuma.c`) and no I2C or USI nodes [V]. `tools/phone-smoke` reports "no battery power supply" [V] | Derive the PERIC clocks from Google's cmucal tables, add the I2C nodes, then probe the gauge read-only. **Do not poke the PMIC from userspace** (AGENTS.md §1) |
| Charging, USB-C | no | Lef | cheetah [USB-C-PLAN](../cheetah/USB-C-PLAN.md); 9a: [#97](https://github.com/derekross/linux-omarchy-mobile/pull/97) is `tcpci_maxim` for the MAX77779 (merged), so check what husky's MAX77759 needs [I] | Same I2C bus as Battery; the USB data switch closes on unplug (AGENTS.md gotcha) | As Battery |
| Haptics, Torch | no | unassigned | 9a [#96](https://github.com/derekross/linux-omarchy-mobile/pull/96) (CS40L26 and LM3644, open); cheetah [HAPTICS-TORCH-PLAN](../cheetah/HAPTICS-TORCH-PLAN.md) | The parts on husky [I: not known to me] | Find them in Google's tree |
| GNSS | no | unassigned | cheetah [GNSS-PLAN](../cheetah/GNSS-PLAN.md); the 9a's is parked | Google's userspace in a chroot built from the owner's own factory image; the regulator rule (PMIC modules must load after about 30 s of late init) | After the display and battery rows |
| AoC, Speakers/mics, Sensors | no | unassigned | cheetah [AOC-PLAN](../cheetah/AOC-PLAN.md), [AUDIO-PLAN](../cheetah/AUDIO-PLAN.md); 9a WIP | The AoC starts only through Trusty; the amplifiers need the speaker-protection calibration; high risk (AGENTS.md gotchas) | Read AOC-PLAN to size it |
| Modem | no | Lef, once a SIM is found ([Brett asked](https://github.com/derekross/omarchy-mobile/issues/1#issuecomment-6544100933)) | cheetah [MODEM-PLAN](../cheetah/MODEM-PLAN.md); 9a [MODEM-PLAN](../tegu/MODEM-PLAN.md) ("ONLINE with IPC, no SIM yet") | A SIM (a prepaid one is the plan; the phone's own SIM is a data-only eSIM); the baseband is `g5300i` [V: fastboot], the S5300 family like cheetah's [I]; the CP's PCIe link and the `cpif` driver; modem firmware from the owner's own factory image; the NV protections. **Lef has a private read-only backup of the modem and calibration partitions (checksummed, plus an encrypted second copy) [V: BUILD-SETUP log, not in this repository].** | Read cheetah's and the 9a's MODEM-PLAN M0 to M2 end to end. Stage 0 is read-only: partitions, and what a booted phone answers without starting the modem |
| NFC | no | unassigned | 9a [#105](https://github.com/derekross/linux-omarchy-mobile/pull/105), [#104](https://github.com/derekross/linux-omarchy-mobile/pull/104) (open) | The controller on husky [I: not known to me]; the 9a's NFC must not poll through s2idle (AGENTS.md) | After suspend |
| Cameras | no | unassigned | 9a [#103](https://github.com/derekross/linux-omarchy-mobile/pull/103) (open); cheetah [CAMERA-PLAN](../cheetah/CAMERA-PLAN.md) | The sensors, the MIPI receiver and the rest of the pipeline; large | After the rest |
| Suspend | no | unassigned | 9a [SLEEP-PLAN](../tegu/SLEEP-PLAN.md) (s2idle works, drain high); cheetah [SUSPEND-PLAN](../cheetah/SUSPEND-PLAN.md) | UFS hibern8 and system suspend ([UFS-PLAN](UFS-PLAN.md) U5 and U6); the ACPM and PMIC base from #153; the "UFS at `spm_lvl` 5", "only s2idle" and "regulators late" gotchas | UFS-PLAN U5 on the guarded initramfs boot |
| Thermal, CPU DVFS | no | unassigned | 9a [#87](https://github.com/derekross/linux-omarchy-mobile/pull/87) (open) | Zones and OPPs for zuma [I: not known to me]; needed before the GPU is enabled | Read Google's thermal and cpufreq nodes |
| USB host, Type-C | no | Lef (with Charging) | cheetah [USB-C-PLAN](../cheetah/USB-C-PLAN.md); 9a [#124](https://github.com/derekross/linux-omarchy-mobile/pull/124) (open) | The Type-C controller is the MAX77759 TCPC above | As Battery |
| Time, persistent storage | partly | unassigned | none yet | The clock starts wrong on first boot (omarchy-mobile #188); root is still behind the read-only guard, so everyday writes need a plan [I] | Write a short plan |
| Fingerprint | no | unassigned | cheetah [FINGERPRINT-PLAN](../cheetah/FINGERPRINT-PLAN.md); 9a [FINGERPRINT-PLAN](../tegu/FINGERPRINT-PLAN.md) | Trusty, `persist` and RPMB writes are irreversible and need the human's explicit go | Last, as a proposal |

## Order I would take them in

A proposal, not a verdict; Brett and Derek know the hardware better.

1. **Merge #148, #153, #154**, and write the missing plans (display, battery and USB-C, GPU) before any PMIC poking.
2. **Battery, charging and USB-C** (Lef, agreed on #1): today there is no battery power supply, which blocks daily use, and the phone should not be run flat unsupervised.
3. **Display driver** (Brett, next), because a render node alone still copies every frame through the simple framebuffer, and brightness, 120 Hz and power saving need it.
4. **GPU** (Brett, next): plan it in parallel, enable it after thermal zones and DVFS, and note that the zuma `clk-acpm` variant is missing.
5. **Suspend**, after UFS hibern8 and the regulators; then **Bluetooth** once the combo chip's firmware path is clear (it depends on the Wi-Fi work), then **audio, sensors, fingerprint**, each gated.
6. **Modem** once a SIM is found, after power, USB-C and the NV-protection steps in MODEM-PLAN.

Brett has Wi-Fi; coordinate on #1.

## How to help without risking a phone

- Read Google's `android-gs-shusky` trees and the stock device tree for each row's chips, and write the missing `*-PLAN.md` in the cheetah shape: status, facts with [V]/[I] and their source, design, a gated runbook, results.
- Test other people's branches on a second unit and say exactly what ran ([CONTRIBUTING.md](../../CONTRIBUTING.md) §6.5). That is how the touch, button and display-size results here were produced.
- Review pull requests against [docs/review/LESSONS.md](../../docs/review/LESSONS.md).
- Everything that boots a phone follows the staged rules: read-only first, a log stream to the laptop before touching hardware, one change per boot.

## Open questions

- Which Bluetooth, NFC and haptics parts does husky have, and which GPU generation? (The stock overlay already names the panel and the charger.) None is named in the husky files of this repository [V: searched `device/husky`].
- Is husky's GPU the same Mali generation as the 9a's, so that its device tree can be adapted? [I]
- Is a zuma variant of `clk-acpm` planned? Kernel [#84](https://github.com/derekross/linux-omarchy-mobile/pull/84) is the pattern.
- Should husky's slot B ever be marked successful (a `devinfo` write)? On the 9a that is on hold; for husky it has not been decided.

## Credits and sources

- **Brett-Michael Green** ([@greenbrettmichael](https://github.com/greenbrettmichael)) brought the Pixel 8 Pro up: the zuma device tree, UFS, USB, the watchdog, buttons (#148), touch (#153), the ACPM and PMIC base, the test tags, and he is on Wi-Fi now. Most of "What works today" rests on that work.
- **W4HO** ([@W4HO-ham](https://github.com/W4HO-ham)) authored the 9a pull requests linked above (all but #143, which is Derek's, and #56, whose author I did not check). Others may have co-authored; the pull requests have the full record.
- **Derek Ross** ([@derekross](https://github.com/derekross)) owns the project, the Pixel 7 Pro reference port and the cheetah `*-PLAN.md` files linked above, the kernel tree, the tools and the review lessons.
- **Lef** ([@Somnius](https://github.com/Somnius)) tested on a second unit (Kioxia UFS 4.0), traced the short keyboard to the wrong physical size and proposed the fix ([kernel #154](https://github.com/derekross/linux-omarchy-mobile/pull/154), open), and wrote this page.
- **Sources:** upstream Linux, Google's published GPL kernel trees (`android-gs-shusky-*`), and the plans and notes in this repository.
