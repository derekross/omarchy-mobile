<!-- SPDX-License-Identifier: MIT -->
# Tensor G4 FAR_ALIVE GPIO preparation

## Provider bound, 2026-10-27 (FA1)

[V] `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`, DTB only
(`b23624ed`): clk_summary first showed the APM gate on as ABL leaves it
(hardware enable Y, no consumer). With `pinctrl_far_alive` okay and no bank
interrupts, `154e0000.pinctrl` binds, gpiochip52 has GPA5's 8 lines, every
pin reads CON 0 (input), DAT 0, PUD 1 (pull-down), DRV 0. Wi-Fi, audio,
sensors, NFC, charger and torch came up as before; no UFS errors.
Logs: `logs/tegu-int-dt-20261026-fa1/`.

FA2 (DTB `f7920ee8`): GPA5 advertises its EINTs, GIC SPI 60-67. All eight
parents are mapped at boot (Linux IRQs 45-52, hardware IRQs 92-99, chained,
no action), as gpa8's 76-79 are; every pin stays masked with no consumer.
Wi-Fi, audio, sensors and NFC came up as before. Logs:
`logs/tegu-int-dt-20261026-fa2/`. This settles the bank-wide ownership
question for Linux: the bank is ours, and the modem (pins 0-2), WLAN (3),
GNSS (4) and Bluetooth (6) consumers request their pins one at a time.

Earlier status, 2026-10-24, superseded by FA1 and FA2 above: offline
source and object-build checks passed, before anything ran on the palmtop.

Source branch `omamobile-tegu-far-alive-source-review-20261024`, worktree
`out/tegu-far-alive-source-review-20261024/kernel`, maclab VM output
`~/tegu/far-alive-source-20261024/out`. Evidence:
`logs/tegu-far-alive-source-review-20261024/`. Preserve the qualified 7e
Image/modules and 792 board tree; these additions are not installed.

## Reuse and exact board facts

The existing G4 pinctrl driver already describes controller index 2 and
its eight-pin GPA5 bank. Reuse it without a new driver or runtime change.
WLAN HOST_WAKE is GPA5[3]; Bluetooth HOST_WAKE is GPA5[6]. They share the
provider, so its eventual ownership must accommodate both consumers.

Pinned Google GPL sources, inspected locally on maclab:

- [CAL clock fields](https://android.googlesource.com/kernel/google-modules/soc/gs/+/204078758737776959ecc85c527a00fd2cabb62f/drivers/soc/google/cal-if/zuma/cmucal-sfr.c):
  APM FAR_ALIVE GPIO PCLK status at CMU_APM offset 0x20dc, bit 21.
- [CAL parents](https://android.googlesource.com/kernel/google-modules/soc/gs/+/204078758737776959ecc85c527a00fd2cabb62f/drivers/soc/google/cal-if/zuma/cmucal-node.c):
  this gate takes DIV_CLK_APM_NOC, already described by the APM provider.
- [SoC resources](https://android.googlesource.com/kernel/devices/google/zumapro/+/8831630eee2ad095b85ed452944e6353940966a5/dts/zumapro.dtsi):
  controller 2 at 0x154e0000, size 0x1000.
- [Bank table](https://android.googlesource.com/kernel/google-modules/soc/gs/+/204078758737776959ecc85c527a00fd2cabb62f/drivers/pinctrl/gs/pinctrl-gs.c):
  GPA5 has eight pins, bank/EINT/filter offsets all zero.
- [IRQ constants](https://android.googlesource.com/kernel/google-modules/soc/gs/+/204078758737776959ecc85c527a00fd2cabb62f/include/dt-bindings/interrupt-controller/zumapro.h):
  EINT50..57 map to GIC SPI60..67, hence GIC hardware IRQ92..99.
  Bluetooth pin 6 is SPI66, hardware IRQ98; WLAN pin 3 is SPI63,
  hardware IRQ95. Do not confuse these SPI numbers with the already
  qualified ALIVE parents whose hardware IRQs are 60..67.

These are source facts, not new hardware observations. The source series
adds one clock ID/read-only gate and one disabled GPIO-only controller.
It adds no bank interrupt-controller property, parent IRQ, pin defaults,
GPIO consumer or radio node. The existing G4 EINT code skips banks whose
interrupt ownership is not advertised; adding the provider description
does not assign its inherited interrupts to Linux.

### Shared-bank ownership, production source audit

The production MP include chain selects the S5300 SIT GPIO definitions,
the TAS2572 audio file and an S5400 phone-GNSS override. The source map is:

| GPA5 pin | Production source use |
| --- | --- |
| 0 | Modem CP PS_HOLD |
| 1 | Modem CP-to-AP wake |
| 2 | Modem PHONE_ACTIVE |
| 3 | WLAN host wake |
| 4 | GNSS-to-AP SPI request |
| 5 | TAS2572 audio interrupt |
| 6 | Bluetooth host wake |
| 7 | Not established by this audit; do not assume unused |

References are the pinned Tegu `zumapro-tegu-mp.dts` /
`zumapro-tegu-common.dtsi`, Zumapro `zumapro-board-cp-s5300-sit.dtsi`,
Tegu `zumapro-tegu-audio-common-tas2572.dtsi`, and the selected
[S5400 phone-GNSS description](https://android.googlesource.com/kernel/devices/google/zuma/+/42395e8adcb880aa336f0da6bb2a19ed53929c40/dts/zuma-cp-s5400-phone-gnss.dtsi).
These are source assignments, not claims that the peripherals are active.
Do not use an unused generic-board GNSS assignment to GPA5[3]; production
phone GNSS uses pin4 and WLAN retains pin3.

The current G4 EINT initialization masks every pin of an advertised bank
before installing its eight parent handlers. Consequently, advertising
GPA5 interrupts just to support Bluetooth would also take the other
lines' interrupt ownership. The new disabled GPIO-only node deliberately
does not do that. Before any wake gate, explicitly qualify ownership of
the whole bank or obtain a reviewed way to scope it; do not assume a
single consumer confines the existing bank-wide initialization. No new
interrupt-driver change is justified or installed by this finding alone.

## Offline results

Three local unsigned commits end at 9f565d43b1fd. Strict in-tree checks,
clock binding meta/lint checks and a clean maclab ARM64 W=1 clock-object
build pass (5.728 seconds). The existing real-kernel-structure renderer
confirms the new read-only entry and preserves every old APM entry. The
entire clock source otherwise differs only in the clock-ID bound; all old
IDs, manual register lists and probe logic are unchanged.

DTC and full schemas pass for the disabled tree and a host-only enabled
GPIO fixture. Missing clock and clock-name fixtures are rejected. Every
old device-tree property is preserved after phandle normalization; the
only additions are the controller, its two children and pinctrl2 alias.
All 37 fixed reservations and all three DPM policies are preserved.
The host baseline reproduces qualified DTB cf5c11809590 byte for byte.

No full Image/module-set build or hardware qualification follows from an
object build. An enabled future node needs the matching new Image/modules
because the existing 7e clock driver does not export clock ID17. These
three commits are outside the frozen twelve-commit DCO packet. No human
sign-off is inferred or added, and private parent history is not publishable.

## Ordered gates

| Gate | Expect / pass | Stop | Rollback / risk |
| --- | --- | --- | --- |
| Source only, completed | Exact pinned fields; clean object/schema checks; old data preserved | Any mismatch or warning | Leave isolated branch unused; low |
| Recover current pocket | Responsive physical fastboot, established Android-boot history, verified five-B restoration and native health | Protocol timeout or uncertain protected-backup history | Existing HOME-backed recovery runbook; attended |
| Clock observation, not prepared | Under fresh protected checksums, laptop kmsg, watchdog and recovery timer, observe only new fixed CMU_APM 0x20dc word after known APM prerequisites | Gate off, missing completion, SError or USB loss; no child MMIO | Inert reader removal or qualified reboot; medium |
| GPIO provider, not prepared | Matching full build, early-boot hang marker, one enabled provider, no EINT/consumer/default pin state; qualified snapshots unchanged | Changed inherited mux/pull/mask, fault or health loss | Exact five-B rollback through project CLI; attended/high |
| One wake consumer, not prepared | Independent source-backed ownership/trigger and input-only qualification | Unknown parent, unowned-line change or spurious IRQ | Disable only new consumer and restore known profile; attended/high |

Do not hot-add or rebind init-only pinctrl tables. Do not power WLAN or
Bluetooth as part of a GPIO gate. The Wi-Fi PHY isolation c1 stop remains
in force; this independent prerequisite does not resolve bits 6/7 or permit
another PMU write. No sounds or physical tests while the owner sleeps.
