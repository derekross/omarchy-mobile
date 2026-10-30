<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a sleep: why s2idle drains so much

Status (2026-10-29): s2idle works (RTC and power-key wakes; NFC and Wi-Fi
have their own notes in NOTES and AGENTS), but the drain in sleep is high.
This plan gathers what's measured, an audit from stock's device tree and
a read-only snapshot of the palmtop, the candidates ranked, and a
measurement runbook.

Kernel: `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty` (the
integration tree), the palmtop's bring-up DTB. The code the runbook boots
is on the bring-up branch `tegu-sleep-bringup` of the kernel fork (not for
merge):

- the MIF module, `tegu-mif-sleep`:
  <https://github.com/W4HO-ham/linux-omarchy-mobile/commit/adbca4c88a21c32ed2fdf3454dc048a50bccd8dd>;
- the bring-up DT as it runs (the dtsi included at the end of
  `zumapro-tegu.dts` in the integration tree):
  <https://github.com/W4HO-ham/linux-omarchy-mobile/commit/af56e6307ddd4d332dec252917add74645101225>;
- S2's change, the four rails no longer always-on:
  <https://github.com/W4HO-ham/linux-omarchy-mobile/commit/054ee78086fbce5881f82eafc65bd19301853ef4>.

## What's measured

The figures are from the 2026-10-27 and 10-28 NOTES entries
(<https://github.com/derekross/omarchy-mobile/pull/100>).

- **s2idle with the cable out: about 140 mA** (59 minutes, 2026-10-27).
- **MIF in sleep** (cable in, buck off, Bluetooth blocked, 600 s RTC-woken
  freezes): 371-373 mA at MIF 2028 MHz, 314 mA at 421 MHz, so lowering MIF
  for sleep saves about 57 mA. With the cable in, the USB link keeps the
  SoC busy, so this can't reproduce the cable-out figure. A PM-notifier
  module (`tegu-mif-sleep`: 421 MHz at suspend-prepare, the old rate after
  resume; the commit above) is the policy to measure with the cable out.
- **Cluster power-down was tried** (2026-10-28) through the hint Google's
  `exynos-cpupm` writes on each idle entry (`CPU_INFORM`, PMU 0x860 + 4 x
  cpu; 1 = C2, 2 = cluster power-down). The C2 hint was stable but saved
  nothing measurable. Cluster power-down on all three clusters stopped
  ACPM's DVFS channel within a second, then I2C and UFS stalled and the
  watchdog reset the palmtop (Google never powers down cluster 0:
  `cpd_cl0` has no `entry-allowed`). Clusters 1 and 2 alone were stable,
  but no saving was measurable, screen on or off. Dropped.
  For the record, what wrote the hints: a bring-up kernel module,
  `tegu-cpuinform` (a `cpu_pm` notifier, out of tree, on the laptop only;
  it was dropped with the result and isn't published), writing each
  core's `CPU_INFORM` word with the PMU register-write SMC (function
  0x82000504, the call the kernel's `gs101-pmu` regmap write uses) from
  the notifier, not through the `exynos-pmu` regmap and not from
  userspace. If SICD ever becomes a step, its PMU sequence goes through the
  kernel's `exynos-pmu` regmap.

## Candidates

1. **MIF in sleep: about 57 mA**, measured with the cable in. Next is the
   cable-out measurement with `tegu-mif-sleep`.
2. **GNSS rails always on.** LDO9S-11S (`gnss-core` 1.2 V, `gnss-rf` 1.8 V,
   `gnss-aux` 1.8 V) are `regulator-always-on` in the bring-up DTB, so the
   S5300's GNSS supplies stay up through sleep, with the modem off too. In
   stock's DT they carry `channel-mux-selection` (subsys GPS): the GNSS
   core switches them itself. Off unless the modem's GNSS runs.
3. **Fingerprint rail always on.** `udfps-3v3` (LDO15S) is also
   `regulator-always-on` in the bring-up DTB. The sensor only needs it
   while an operation runs.
4. **The system idle state (SICD).** Google's `cpupm` has a system state
   (`sicd`, idle clock-down, 10 ms target residency) beside the cluster
   ones. It hasn't been tried, and it would need the same PMU sequence.
   Given the cluster results, it's lower than 1-3.
5. **Smaller and unmeasured:** the eUSB2 repeater rails (`eusb-vdd`,
   `eusb-vdda12`), touch (on for touch wake), the AoC and its sensors (on
   by design), the NFC clock pad (always enabled while NFC is bound), and
   the modem when it has been started (no suspend is allowed then, by the
   inhibitor).

The CPUs' own idle state works: cpu0's `c2` was entered about a million
times by 2026-10-29, with 1304 rejected (EINVAL); cpu4 1148 of 46339, cpu7
576 of 33173. The firmware's PSCI is v1.1 with no OS-initiated mode.

### Stock's consumers of the four rails (checked 2026-10-29)

Before S2 turns LDO9S, LDO10S, LDO11S and LDO15S off, the question was
whether anything else on stock draws from them. Checked in stock's base
DT (the DTB in stock's `vendor_kernel_boot`, decompiled) and in all ten
board overlays of stock's `dtbo`: none of the four nodes carries a
`phandle`, so no node names any of them as a supply (a consumer would
force one; LDO12S, `L12S_CAMIO`, has one, from the cameras), and no
overlay fixup names them either. The three GNSS rails are `subsys-name
"GPS"` with `channel-mux-selection` 0x29-0x2b, so stock's GNSS core
switches them through the PMIC's channel mux; LDO15S is `L15S_SPARE`,
`regulator-always-on` on stock, subsys Spare, with no consumer in the DT
(the fingerprint sensor node has no supply; FINGERPRINT-PLAN). So the
four feed GNSS and the fingerprint sensor only, by stock's DT.

A phandle finds every DT supply reference, but the regulator core also
looks a supply up by `regulator-name` when a driver asks for one the DT
doesn't give it, so stock's kernel source was grepped for the four names
too (`L15S_SPARE`, `L9S_GNSS_CORE`, `L10S_GNSS_RF`, `L11S_GNSS_AUX`, and
`S2MPG15_LDO9`-`11`/`15`): `devices/google/tegu`, `devices/google/zuma*`
and `google-modules`. They appear only in device tree sources
(`zumapro-pmic.dtsi`, `zuma-pmic.dtsi`, the GNSS board dtsi files, and
tegu's udfps dtsi, which makes LDO15S always-on at 3.3 V) and in the
S2MPG15 register header. No vendor module asks for any of them by name:
the GNSS module uses no regulator at all, and the fingerprint tree's
`regulator_get` by name is in the FPC driver, not tegu's Goodix one. The
gap is closed.

## Runbook (attended for the cable)

Preconditions for the whole runbook:

- **Slot B.** Stop if slot B isn't marked successful; this runbook doesn't
  mark it (on the 9a marking is a `devinfo` write, under the rules being
  settled on <https://github.com/derekross/omarchy-mobile/pull/125>). An unmarked
  B burns an ABL retry on every boot, and a cycle that resets the palmtop
  counts as one.
- **NFC.** S1 and S2 run `systemctl suspend` cycles, and on the 9a a
  suspend with neard polling reset the palmtop (2026-10-27; AGENTS,
  "Suspend and modem"). Before the first cycle: the stop-poll sleep hook
  (`omamobile-tegu-nfc` on the palmtop, not in the repository yet) is
  installed and its unit active, or polling is stopped by hand. Either
  way, read neard's `Polling` property before each run (a neard restart
  starts polling again):

  ```sh
  tools/phone-ssh 'busctl get-property org.neard /org/neard/nfc0 org.neard.Adapter Polling'
  ```

  It must read `b false`. The
  palmtop's current kernel carries the nxp-nci change of
  <https://github.com/derekross/linux-omarchy-mobile/pull/131> (its
  `core.c` is in the running tree, blob 77fc35b61da5), which turns the
  ST54L's NFC mode on after init; it doesn't lift the rule. NFC still
  loses its NCI state across s2idle
  (<https://github.com/derekross/omarchy-mobile/issues/132>,
  <https://github.com/derekross/omarchy-mobile/pull/137>), so NFC must not
  poll through these cycles.
- **If a cycle doesn't come back** (no wake within 5 minutes, no answer on
  the cable): Power held about 30 s, then Power. Then, before anything
  else, read `/sys/fs/pstore` (systemd-pstore moves it to
  `/var/lib/systemd/pstore` at boot) and quote the end of the console log
  in this plan.

**S1. Baseline, then MIF (risk low; attended for the cable).** Screen off,
Wi-Fi as it runs, modem not started, cable out. The run is `tools/power-ab`
with the systemd suspend mode of
<https://github.com/derekross/omarchy-mobile/pull/157>, so S1 waits for
#157 to merge:

```sh
tools/phone-ssh 'power-ab --detach --unplug 180 --phase 1800 --rounds 2 --suspend systemd s2idle'
```

`--suspend systemd` arms the RTC with `rtcwake -m no` and runs `systemctl
suspend`, so the NFC sleep hook runs (a freeze written to
`/sys/power/state` would skip it). Phase A is awake with the screen off,
phase B is the 30-minute sleep, two rounds. The 9a's gauge has no
`charge_counter`, so the figure is the `charge_now` column of the CSV
(column 7, `charge_now_uah`): the gauge's model-corrected remaining
charge, coarser than a coulomb counter, hence the long phases. Repeat with
`tegu-mif-sleep` loaded (the module commit above, built against the running
kernel). Expect about 140 mA, then less. Stop: the palmtop doesn't come
back on the cable within 5 minutes of the end (power key). Rollback:
`rmmod tegu-mif-sleep` (the module changes nothing while awake: it sets the
rate at suspend-prepare and puts the old one back at resume), or a reboot.

**S2. Rails (risk low).** As S1 with the three GNSS rails and `udfps-3v3`
not always-on: the running DTB with `regulator-always-on` removed from
LDO9S-11S and LDO15S, nothing else (the S2 commit above). Not in or around
a G3 (GNSS) session: GNSS is off for this boot.

S2 turns LDO15S off on purpose, for this one boot, although
FINGERPRINT-PLAN's Risks table says our S2MPG15 description must not
switch it off as unused: the sensor is unpowered for the boot, and that
is the point of the measurement. FINGERPRINT-PLAN (on
<https://github.com/derekross/omarchy-mobile/pull/138>'s branch) gets the
matching note as a follow-up once it is on main. Steps:

1. **Before (read-only).** On the running DTB, 60 s or more after boot,
   save `/sys/kernel/debug/regulator/regulator_summary` to
   `logs/tegu-sleep-s2/summary-before.txt`.
2. **The image.** Build the images from the S2 commit. `bin/omamobile
   push` writes every image in `BOOT_IMAGES`; check first that only
   `vendor_kernel_boot.img` differs from the running set (sha256 of each
   image against the running kit), so the push changes the DTB and
   nothing else. Stop if any other image differs.
3. **Push and boot.** Precondition, before the push: the fingerprint
   stack stays stopped in that boot. `omamobile-fp.service` and anything
   that starts the trusted app or `storageproxyd` (the `omamobile-fp-stage`
   transient unit, `omamobile-fp-chroot start …` by hand, fprintd) are
   disabled or masked before the push and put back after the rollback.
   F6c is still writing secure objects, and nothing in Trusty should meet
   a sensor with no power while the calibration question is open. Check
   after the boot: `systemctl list-units 'omamobile-fp*'` empty, no
   `storageproxyd` process. Don't start the modem in this boot: the
   S5300's GNSS supplies are off. Nothing on the palmtop starts the modem
   at boot (it is started by hand with `omamobile-tegu-modem-up`,
   MODEM-PLAN), so there is nothing to mask; just don't run it.
4. **After (read-only).** 60 s or more after boot, save the summary again
   and diff it against the before file. Expect: LDO9S, LDO10S, LDO11S and
   LDO15S read disabled, and nothing else changed. All four are off at
   hand-off and without `regulator-always-on` nothing turns them on, so
   they read disabled whether or not the regulator core's 30 s unused-rail
   cleanup has run (which matters if the S2MPG15 regulators ever register
   after it). Stop if anything other than those four changed: push the
   running DTB's image back before any suspend.
5. **Measure.** S1's cycles. Expect S1 minus the four rails' share.

Rollback: push the running DTB's image back (the before/after check of
step 2 in reverse).

## Not known yet

- What the GNSS and fingerprint rails cost in sleep (S2).
- What MIF in sleep saves with the cable out (S1).
