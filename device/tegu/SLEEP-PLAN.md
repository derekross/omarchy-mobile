<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a sleep: why s2idle drains so much

Status (2026-10-31): s2idle usually works (RTC and power-key wakes; ten of
ten 30-second cycles on 10-31 with the console kept through the freeze),
but not always: four sleeps have never woken (two direct freezes, one
30-minute systemd sleep with `tegu-mif-sleep` loaded, and the sixth
30-second cycle of a boot on 10-30, which left the USB bus and needed a
forced restart), and one more woke with UFS dead (`link startup failed` x5,
then I/O errors and `emergency_ro`, 10-30 afternoon). The drain in sleep is
high. Sleep tests are attended and unattended sleep stays off. The shell's auto-sleep (the `omamobile-sleep` toggle) is
off on the palmtop since the 2026-10-30 shell reinstall (the package ships
it off), so it doesn't sleep unattended at present; while it was on, its
systemd-path sleeps without the module all woke, and turning it back on is
the owner's call.
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

- **s2idle with the cable out: about 300 mA** (302 mA over two 30-minute
  sleeps on 2026-10-29, S1 below; the 140 mA read on 2026-10-27 didn't
  hold up and is retired there).
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
2b. **What S2 can and cannot change, now that GNSS works (read from the
   running DTB, 2026-10-30 night).** The four rails are declared with
   labels (`gnss_core: ldo9s`, `gnss_rf: ldo10s`, `gnss_aux: ldo11s`,
   `udfps_3v3: ldo15s`) and **no consumer anywhere in the device tree**:
   nothing names them as a supply, which is why they need
   `regulator-always-on` to stay up at all. So removing that property does
   not move the cost to the user of the rail, it simply lets the regulator
   core's unused-rail cleanup turn all four off about 30 s after late init.
   That is still a valid one-boot measurement, and it is what S2 asks for,
   but it is not a shippable policy: GNSS needs its three rails for a
   session (the Kepler RF front end cannot calibrate without them, which is
   why they are on as stock has them), and the fingerprint sensor needs
   LDO15S for an operation. Now that a GNSS session works end to end, the
   policy S2 should lead to is a consumer rather than an absence: the GNSS
   path claiming its three rails when a session starts and dropping them
   when it ends, and the fingerprint path doing the same around an
   operation, so the drain is paid only while something uses the hardware.
   That needs a supply property on the consumer's node and driver support
   on both paths, neither of which exists upstream yet, so the order is:
   measure with S2 to learn the number, then decide whether the number
   justifies the driver work.
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
`/sys/power/state` would skip it). On the 9a always pass it: `power-ab`'s
default, `--suspend rtcwake`, is a direct freeze, the path that fails to
wake (the S1 result below), and a detached cable-out run is the worst place
for one. Phase A is awake with the screen off,
phase B is the 30-minute sleep, two rounds. The 9a's gauge has no
`charge_counter`, so the figure is the `charge_now` column of the CSV
(column 7, `charge_now_uah`): the gauge's model-corrected remaining
charge, coarser than a coulomb counter, hence the long phases. Repeat,
attended, with `tegu-mif-sleep` loaded (the module commit above, built
against the running kernel): that is the configuration that once didn't
wake. Expect about 300 mA, then less. Stop: the palmtop doesn't come
back on the cable within 5 minutes of the end (power key). Rollback:
`rmmod tegu-mif-sleep` (the module changes nothing while awake: it sets the
rate at suspend-prepare and puts the old one back at resume), or a reboot.

**S1 result (2026-10-29, `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`,
device-tegu 0.2.0).** The baseline ran as written (cable out, screen off,
Wi-Fi kept, modem not started, two 30-minute `systemctl suspend` rounds
through `power-ab --suspend systemd`), then the pieces were pulled apart
with the cable in.

- **Cable out: 311 mA awake with the screen off, 302 mA asleep** (phase A
  3434 samples of `current_now`; phase B 302.5 mAh of `charge_now` over
  3604 s, two rounds, both woken by the RTC through the PMIC, `success` 2).
  Sleep saves nothing over the awake screen-off state. The 140 mA of
  2026-10-27 is the outlier: a cable-out A/B on 2026-10-28
  (`logs/tegu-morning-20261028/sleep-ab-20261028b.log`) already read 434
  and 445 mA asleep as-is and 374 and 389 mA with MIF at 421 MHz.
- **The CPUs do sleep.** A 60 s `systemctl suspend` with the cable in ran
  with `Timekeeping suspended for 60.059 seconds` and each cluster's deep
  state entered once in s2idle (`cpuidle/state1/s2idle/usage` +1 per CPU),
  so no interrupt keeps the cores up. What stays on is everything below
  them: MIF and the buses at full rate, and the always-on rails. Google's
  kernel has a system idle state (SICD) for this; ours has none.
- **The radios cost nothing at idle** (cable in, buck off through
  `CHG_CNFG_00` 0x00 under a dead-man restore, screen off, 45 s means of
  `current_now`): baseline 351 mA, Bluetooth off 355, NFC driver unbound
  356, Wi-Fi link down 360. All within noise.
- **MIF at 421 MHz in sleep saves about 60-75 mA.** Cable in, buck off,
  240 s `systemctl suspend` sleeps measured by the gauge's coulomb counter
  (`QH`, register 0x4d of the fuel gauge at 0x36 on bus 24; 2.5 mAh per
  count, checked against 60 s of `current_now`): as-is 12 counts, 446 mA;
  with `tegu-mif-sleep.ko` 10 counts, 371 mA (one count is 37 mA at this
  length). This matches the 2026-10-28 figure (57 mA). The module loads,
  unloads and wakes cleanly; the palmtop now loads it at boot from a hand
  unit, `/etc/systemd/system/tegu-mif-sleep.service`
  (`insmod /var/lib/omamobile-tegu/tegu-mif-sleep.ko`, the module built
  from `adbca4c88a21` above against this release), until the policy is in
  the kernel or the device package. Rollback: `systemctl disable --now
  tegu-mif-sleep; rmmod tegu_mif_sleep` (nothing changes while awake), and
  the module must be rebuilt for every kernel push. Cable-in figures sit about
  140 mA above cable-out ones (the USB link keeps the SoC busy).
- **Sleeps that never wake, three so far, and no single cause.** Not
  woken by the RTC alarm, nor by the power key, and reset by hand with
  Power + Volume Up: a direct `rtcwake -m freeze` of 10 min on 2026-10-28
  (MIF as it was, after two 421 MHz sleeps that woke); a direct freeze of
  240 s on the night of 2026-10-29 (NFC blocked, polling already stopped);
  and on 2026-10-30 a `systemctl suspend` of 30 min, cable out, through
  `power-ab --suspend systemd` with `tegu-mif-sleep` loaded (the A phase
  ran at about 300 mA, the B freeze was logged, nothing after; the owner's
  65-minute timer ran out with the palmtop dark). Woke: 35 short systemd
  cycles on 2026-10-27, two 30-minute and four 240 s systemd sleeps on
  2026-10-29 (one of the four with the module), two 10-minute direct
  freezes with the module on 2026-10-28. So neither the entry method nor
  the module alone explains it. Until it is understood: every sleep test
  is attended, the cable-out run's sleep phase is kept to what the owner
  can watch, `power-ab` still runs with `--suspend systemd` (the sleep
  hooks run that way), and the hand unit that loaded `tegu-mif-sleep` at
  boot is disabled (2026-10-30). Nothing in pstore for any of the three: a
  held power key is a pin reset, and the console log doesn't survive it.
  The cheap test ran the same morning: a cable-in 30-minute `systemctl
  suspend` with the module loaded, the RTC alarm logged as armed before
  (`alarm_IRQ: yes`, 1800 s ahead), woke on the alarm to the second
  (`PM: Triggering wakeup from IRQ 56`, the PMIC's RTC; `suspend_stats`
  success 1). The same afternoon the cable-out run was repeated with the
  module loaded by hand (`power-ab --suspend systemd`, one round, the
  owner away for an hour) and woke on its alarm: awake with the screen off
  273 mA (1715 samples), asleep 259.7 mA (130.0 mAh of `charge_now` over
  1802 s). Against the previous day's 302 mA asleep without the module
  that is about 40 mA saved, in line with the cable-in coulomb-counter
  figure given the gauge's coarseness. So neither the module, nor the
  30-minute systemd sleep, nor the cable being out reproduces the no-wake
  on its own; the three failures' common factor is still open, and sleeps
  stay attended. One more observation the same afternoon, cable in, module
  still loaded from the drain run: during a forced 10-minute systemd sleep
  the owner's tap and power-key press did not wake the palmtop; the kernel
  came up once at about 112 s (`Timekeeping suspended for 112.557 seconds`)
  and went straight back to s2idle until the RTC alarm woke it at 10
  minutes (IRQ 56). The power key woke s2idle on 10-27 without the module,
  so the next cheap test is a sleep without the module and a power-key
  press, then the same with the module: if the key wakes only without it,
  the module is in the no-wake story after all (a key wake that doesn't
  register would look exactly like an RTC alarm that doesn't).
- **Found the same afternoon: UFS failed to come back from an s2idle, and
  that is what a "no-wake" looks like from outside.** The forced 10-minute
  systemd sleep above (cable in, module loaded) did wake on its RTC alarm
  at uptime 10801 s, but the UFS link did not come back: the console in
  pstore shows `exynos-ufshc 13200000.ufs: link startup failed 1` and
  `ufshcd_host_reset_and_restore: Host init failed 1` five times in a row,
  then `ufshcd_wl_resume failed: 1`, `PM: failed to resume async: error 1`,
  and from the first write after resume `I/O error, dev sda` with
  `hostbyte=0x07`, `EXT4-fs … failed to convert unwritten extents …
  potential data loss`, and the root filesystem went `emergency_ro`. The
  palmtop answered SSH for a while from what was already in memory, but
  nothing on disk could be read: `systemctl suspend` and `systemctl
  reboot` did nothing, `coredumpctl` and `df` returned EIO, the power key
  reached the kernel (its interrupt count rose) and the shell could not
  light the screen. A sysrq `b` reset brought it back with a clean ext4
  journal recovery (`spm_lvl` was 5 throughout, `rpm_lvl` 3). So a
  palmtop that "never wakes" and whose power key does nothing may have
  woken with its storage dead, which the three no-wake records cannot
  distinguish from a missed alarm: none of them had a console. UFS resume
  was qualified on 32 of 32 cycles with the reset held in suspend (kernel
  #83) and on the S1 sleeps; this is the first failure, 1 of about 50
  systemd-path resumes. Rule until understood: after every s2idle on the
  9a, `dmesg | grep -E "link startup failed|Host init failed|I/O error"`
  before anything else, and reboot at once if it matches; unattended
  sleep stays off. Next: the UFS resume path with the kmsg stream, and the
  question whether the three dark no-wakes left ext4 recovery lines in
  their next boot's journal (`journalctl -b -N -k | grep EXT4`).
- **2026-10-30 night, s2idle with the cable in, 20 cycles asked for, 6
  taken, 1 hang.** Attended RTC-woken 30-second cycles on the daily boot
  (release `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`, the
  modem never loaded in that boot, NFC's sleep hook in place, `spm_lvl` 5,
  `rpm_lvl` 3), each checked for `link startup failed`, `Host init failed`,
  `I/O error` and `ufshcd_err_handler` before the next one, and for a
  writable root. Cycles 1-5: all woke, all four counters zero, one suspend
  entry and one exit each, root writable, the wake each time the RTC with
  the power key and Wi-Fi's host-wake disarmed again on resume (`wake
  disabled for irq 59`, `irq 73`). `/sys/power/suspend_stats` read
  `success=5` with every failure counter zero. The sixth cycle of the same
  boot did not come back, and this time the palmtop left the USB bus
  entirely (no gadget, the laptop's interface gone), so it is not the dead-
  storage shape of the 10-30 afternoon (which kept answering SSH from
  memory): the SoC itself is hung or down, and nothing can be read until a
  forced restart. Waiting on that to read the console from pstore.
- **What the forced restart left, and how the cycles slept (for the
  rule).** After the sixth-cycle hang of 10-30 and the morning's forced
  restart, `/sys/fs/pstore` held nothing from the hung boot: the kept
  console (`console-1030-205427.txt`) has that boot's bootloader log and
  then the next boot's, with no kernel lines from the hang, because printk
  had suspended the consoles at the freeze (below). Every 30-second cycle,
  that night and this morning, entered sleep the systemd way: `rtcwake -m
  no -s 30` to arm the alarm, then `systemctl suspend`, so the sleep hooks
  (NFC's poll stop, Wi-Fi's) ran each time; none was a direct write to
  `/sys/power/state`.
- **2026-10-31 morning: ten of ten cycles clean, and the console now
  survives the freeze.** The reason every earlier hang left no kernel
  evidence is that printk suspends the consoles at the freeze ("Suspending
  console(s) (use no_console_suspend to debug)"), so nothing reached
  ramoops after that line. It does not need a boot argument:
  `/sys/module/printk/parameters/console_suspend` is writable, and `echo N`
  into it keeps the console alive through s2idle. With that set, ten
  30-second RTC-woken cycles on the daily boot all woke with the storage
  counters, the ACPM timeout count and the watchdog count at zero,
  `suspend_stats` reading `success=10 fail=0`, and the kernel log streamed
  to the laptop for the whole run (10086 lines,
  `logs/tegu-review-20261029/runners/13b-20261031-0807-kmsg.txt`, not
  committed), with all ten entry and exit pairs in it and each wake showing
  the power key and Wi-Fi host-wake disarmed again (irq 59 and irq 73).
  So the next hang will leave its last words, which is the one thing the
  10-30 night could not give.
- **Read back from the afternoon's own console (2026-10-30 night, offline):
  the failing suspend was the third of its boot, not a late one.** The
  console holds nine suspend entries (387.7 s, 4746.9 s, 10798.6 s, then
  14328.9 s onwards once the filesystem was already read-only), and the
  third one, at 10798.6 s, is the one whose resume failed at 10799.8 s. The
  25 seconds before it contain nothing but PAM and audit lines from an SSH
  login: no ACPM timeout, no thermal error, no UFS warning. (An earlier
  note of mine tied that failure to the ACPM timeouts; those are from a
  different boot, the 18:31 console of the same day, and the link is
  withdrawn. The ACPM slot leak found while reading that path is real and
  is linux-omarchy-mobile#152, but it is a separate defect.) So the
  afternoon failure was the third sleep of its boot at about 3 hours of
  uptime, and tonight's hang the sixth of its boot at about 10 minutes:
  neither "the Nth sleep" nor "a long boot" fits both, and what they share
  is only that neither was the first sleep of its boot.
- **The failing resume compared with the two clean ones in the same
  console (2026-10-30 night, offline).** Lined up on their suspend entry,
  the three resumes of that boot differ in one step:

  | | clean (387.7 s) | clean (4746.9 s) | failed (10798.6 s) |
  | --- | --- | --- | --- |
  | `wl resume begins` | +0.754 | +0.741 | +0.717 |
  | `dme-set attr-id 0x4021` | +0.803 | +0.800 | never |
  | `Power mode changed to FAST series_B G_4 L_2` | +0.859 | +0.866 | never |
  | `link startup failed 1` | - | - | +1.198, then +1.655, +2.143, +2.622, +3.058 |
  | `reset_and_restore` | 0 | 0 | 1 |

  So the failure is not in the hibern8 exit or in the device's power mode:
  it is link startup itself, which never got as far as the first DME set.
  Each attempt took about 430-490 ms, the UIC command timeout, and five of
  them in a row exhausted `ufshcd_host_reset_and_restore()`. In the clean
  resumes the whole link came up in 50 to 90 ms with the DME set and the
  power-mode change present. The wake-interrupt disarm of irq 73 (Wi-Fi's
  host wake, on the 154e0000 controller) lands either side of the DME set
  in the clean runs, so its ordering against the UFS resume is not the
  difference.

  What that points at for the next run: the link-startup path on resume,
  which at `spm_lvl` 5 is a full re-init, so the PHY power-on and the
  release of the device reset line (`HCI_GPIO_OUT`, asserted in
  `gs101_ufs_suspend()`) rather than anything in hibern8. Worth reading
  next to the one-sample caveat: this is a single failure against two clean
  resumes in that boot and five clean cycles tonight.
- **A hypothesis for that link startup, from comparing the driver with
  Google's (offline).** Both drivers pulse the device reset in the
  controller-enable notifier before link startup, with the same 5 us, so
  that is not the difference. What our gs201 and zumapro descriptions carry
  and Google's does not express the same way is idle clock gating:
  `EXYNOS_UFS_OPT_CLKSTOP_PRE_CHANGE | EXYNOS_UFS_OPT_UNGATE_POST_CHANGE`,
  and the driver's own comment says zumapro's CMU gates really stop the host
  clocks, so the clock-stop registers can only be written with the gates
  open. A resume at `spm_lvl` 5 is a full re-init: if the core's clock
  gating lands anywhere inside it, the DME commands that link startup sends
  would time out exactly as the failing console shows, with no first DME
  set and no power-mode change. That is a hypothesis, not a finding: the
  ordering in `exynos_ufs_setup_clocks()` is meant to prevent it.
  The test, as a runbook step (attended, cable in, modem never loaded in
  the boot, console kept through the freeze; risk: low):

  ```sh
  # S3. UFS idle clock gating off for a run of cycles
  tools/phone-ssh 'echo N > /sys/module/printk/parameters/console_suspend'
  tools/phone-ssh 'u=/sys/devices/platform/soc/13200000.ufs; cat $u/clkgate_enable; echo 0 > $u/clkgate_enable; cat $u/clkgate_enable'
  #   Expect: 1 then 0
  # ten cycles, each: rtcwake -m no -s 30; systemctl suspend; after the wake:
  tools/phone-ssh 'dmesg | grep -cE "link startup failed|Host init failed|I/O error|ufshcd_err_handler"; cat /sys/power/suspend_stats/success'
  #   Expect: 0, and success counting up by one per cycle
  #   Stop: any count above 0, or no SSH 120 s after the alarm (forced restart, read pstore and the kept console)
  #   Rollback: echo 1 > clkgate_enable, or a reboot (the setting does not persist)
  ```

  One failure in about 50 resumes means a clean run of ten proves nothing
  by itself, so run it both ways and count.

  **S3 result, 2026-10-31 (`7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`):**
  clock gating off (`clkgate_enable` 0), console kept, modem never loaded
  that boot, ten 30-second RTC cycles: ten of ten woke, `suspend_stats`
  success 10 and fail 0, no UFS error-handler, link-startup or I/O lines,
  no ACPM timeouts. With gating on, 10-31's earlier run was also ten of ten,
  so this does not yet separate the two; the count both ways goes on until
  one side fails.

  **S1 on the clock-fix kernel, 2026-11-01 (same release, the daily kernel
  with the PERIC0 GPIO clock kept on, linux-omarchy-mobile #172).** That
  gate hung the SoC under the modem's GPIO traffic (MODEM-PLAN G3-L1), so
  it was a candidate for these no-wakes too. Cable in, modem never loaded,
  NFC polling off before every cycle, UFS clock gating on (the default),
  thirty 30-second RTC cycles planned: cycles 1-20 woke (47-80 s from
  suspend to SSH, `suspend_stats` success 20 and fail 0, no UFS or ACPM
  lines, wake IRQ 56 each time), and cycle 21 did not wake: no SSH 160 s
  after the suspend, and it needed Power + Volume Up. So the clock gate is
  not the sleep hang; one in 21 here, against about one in 40 before.
  After the reset (2026-11-01 morning), nothing from the hung sleep was
  kept: `/sys/fs/pstore` was empty, and the persistent journal of that
  boot ends on `PM: suspend entry (s2idle)` with nothing after it. That
  run didn't keep the console through sleep (`printk.console_suspend=N`
  went into the script after it), and a Power + Volume Up reset may not
  keep the ramoops region anyway. The next run keeps the console, and
  whether the SoC watchdog still runs in s2idle (a watchdog reset keeps
  ramoops; the buttons were needed every time so far) is the next thing
  to check.

  **A watchdog through s2idle, tried 2026-11-01 (same release): it breaks
  the sleep, so it can't catch the hang.** `s3c2410_wdt` stops both
  watchdogs in its suspend callback, so a hang in s2idle never resets the
  palmtop. A bring-up module (`tegu-wdt-s2idle`, source in [e761ba793](https://github.com/W4HO-ham/linux-omarchy-mobile/commit/e761ba793) on the owner's kernel fork, not for merge)
  restarted the cluster 0 watchdog in the noirq phase with the PMU reset
  path unmasked and the counter enabled, as the driver's own enable does,
  and stopped it in resume_noirq. Armed, three sleeps of three ended in a
  reset: the s2idle wake came within 60 ms of arming, and after resume
  ACPM stopped answering (`Timeout! ch:2`, then `RX front can not keep up
  with TX front` and `sec-pmic-acpm … Failed to read IRQ status: -110`
  every 0.5 s) until the restored 10 s watchdog reset the SoC; ramoops
  kept all of it. Loaded but disarmed, two sleeps of two woke (after 1.5
  and 1.6 s, wake IRQ 56, no ACPM timeouts). So a running cluster 0
  watchdog (or its PMU counter enable) during s2idle upsets the APM, and
  this module is not a way to record the real hang. The real hang's
  console is still unknown; what this run does show is what an APM that
  stops answering after resume looks like, which matches the stall seen
  in G3-L1's CPU-sleep run (MODEM-PLAN).

  **Correction (2026-11-01, same day): the sleeps were not short.** The
  paragraphs that stood here said the PMIC woke every s2idle about a
  second in, and that disabling CPU core power-down fixed it (a hook was
  proposed as device-tegu 0.2.5, #255, now closed). That was a
  measurement error: the length of each sleep was taken from
  `PM: suspend entry` to `PM: suspend exit` in dmesg, and the kernel log's
  clock does not advance while the SoC is suspended. The RTC shows the
  real length. After a sleep with a 120 s alarm, `since_epoch` read 4 s
  past the alarm, so the palmtop slept the whole 120 s and woke on it.
  The PMIC registers read at each wake agree once read that way: INT2
  bit 2 (alarm 0) for the alarm wakes, and INT1 bit 1 (power key
  released) for the one sleep with no alarm, which the owner ended by
  pressing the key minutes later. The journal's wall-clock times give
  28-30 s for the 30 s cycles of 10-31. With core power-down disabled the
  dmesg deltas grew to the alarm time only because with WFI alone the
  s2idle loop doesn't freeze the tick, so timekeeping kept running: a
  shallower sleep, not a fixed one. So S1's wake counts (and AGENTS' 9a
  gotcha) stand as written, and the same error affects the watchdog
  paragraph above: "within 60 ms of arming" and "after 1.5 and 1.6 s" are
  dmesg deltas, not the sleeps' real lengths. The rest of that paragraph
  (ACPM stopping after the wake with the watchdog armed, three of three)
  stands. To measure a sleep, read the RTC
  (`/sys/class/rtc/rtc0/since_epoch`) before and after, not dmesg (this
  kernel has no `suspend_stats/last_hw_sleep`). Twenty more 120 s sleeps the same day with core power-down off
  all woke, but they don't speak to the hang with core power-down on.
- **What the five clean cycles rule out, and what they don't.** Five in a
  row with the storage counters at zero says the UFS resume path is not
  broken per se; the afternoon failure and this hang are both the sixth or
  later sleep of a long-running boot (the afternoon one at uptime 10801 s,
  this one after five sleeps), so the first guess was the number of sleeps
  in a boot; the console read below retires that guess, since the afternoon
  failure was only the third sleep of its boot. The
  three dark no-wakes left no ext4 recovery line in their next boot's
  journal (checked tonight across 25 boots: no boot recovered a journal),
  so they were not the dead-storage shape either, which fits a hang like
  tonight's.
- A later note on the method: `power-ab`'s CSV columns are
  `voltage_uv,current_ua,current_avg_ua,charge_counter_uah,charge_now_uah`;
  the gauge's `current_avg` is a long filter and says little about a
  30-minute window, so read `charge_now` (or `QH`) across the sleep.

**S1 method, cable in (the steps the measurements above used; S2 reuses
them).** Each goes into the runbook before it runs; the charger write ran
tonight before it was written here, which is not the order the plan asks
for.

```sh
# 1. Buck off: the palmtop runs on its battery with USB data up (risk low; charger in, battery above 30 %).
#    First the dead-man that puts the buck back. For awake measurements a monotonic timer is enough:
tools/phone-ssh 'systemd-run --unit=x-buck-restore --on-active=600 /usr/bin/i2cset -f -y 24 0x69 0xbc 0x05'
#    For sleeps, monotonic timers don't run in suspend, so use the wall clock, and have the script restore on EXIT too:
tools/phone-ssh 'systemd-run --unit=x-buck-cal --on-calendar="$(date -d "+25 min" "+%Y-%m-%d %H:%M:%S")" /usr/bin/i2cset -f -y 24 0x69 0xbc 0x05'
tools/phone-ssh 'i2cset -f -y 24 0x69 0xbc 0x00; sleep 3; i2cget -f -y 24 0x69 0xbc; cat /sys/class/power_supply/max77779-battery/current_now'
#    Expect: 0x00, current_now negative (discharging, about -350 mA screen off). Stop: current_now stays positive
#    (the buck is still on: don't measure), or the dead-man refuses to arm. Rollback: the write of 0x05 below.
# 2. Measure. Awake: 45 s means of current_now. Asleep: the gauge's coulomb counter across the sleep,
tools/phone-ssh 'i2cget -f -y 24 0x36 0x4d w'     # QH, 2.5 mAh per count; mA = counts * 2.5 * 3600 / seconds
#    (checked 2026-10-29: 3 counts in 60 s at a 357 mA mean of current_now; one count is 37 mA over 240 s).
#    The sleep itself: rtcwake -m no -s 240; systemctl suspend. Never rtcwake -m freeze (the result above).
# 3. Buck back on, then the read-back:
tools/phone-ssh 'i2cset -f -y 24 0x69 0xbc 0x05; systemctl stop x-buck-restore.timer x-buck-cal.timer 2>/dev/null; sleep 3; i2cget -f -y 24 0x69 0xbc; cat /sys/class/power_supply/max77779-battery/status'
#    Expect: 0x05 and current_now positive again (status reads Unknown on this driver). Stop: 0x05 doesn't read
#    back: write it again; if it still doesn't, replug the charger (the chip's power-on default is 0x05).
```

Next: S2 (the four rails), attended. The cable-out number with the module
is in (260 mA, S1 result); any further run with the module is attended too.

**S2. Rails (risk low).** As S1 with the three GNSS rails and `udfps-3v3`
not always-on: the running DTB with `regulator-always-on` removed from
LDO9S-11S and LDO15S, nothing else (the S2 commit above). Not in or around
a G3 (GNSS) session: GNSS is off for this boot.

S2 turns LDO15S off on purpose, for this one boot, although
FINGERPRINT-PLAN's Risks table says our S2MPG15 description must not
switch it off as unused: the sensor is unpowered for the boot, and that
is the point of the measurement. FINGERPRINT-PLAN's Risks table names this exception. Steps:

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
   An enrolled template lives in Trusty, and nothing in Trusty should
   meet a sensor with no power. Check
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

- Why a boot's sixth or later s2idle hangs or loses its storage while the
  first five are clean (2026-10-30 night, above). Next: the cycles again
  from a fresh boot with the kmsg stream to the laptop, counting sleeps,
  and the console from the forced restart of tonight's hang.
- Which PMIC event ends an early RTC cycle, and now how to read it. The
  record says it has never been read; the driver names the register. In
  `rtc-s5m.c`, `s5m_check_pending_alarm_interrupt()` reads
  `S2MPG14_PMIC_STATUS2` on zumapro (`S2MPG12_PMIC_STATUS2` on gs201) and
  takes the alarm from `RTCA0E`, bit 2 (`RTCA1E`, bit 1, is the second
  alarm). So after a cycle that woke early, that register says whether the
  alarm fired at all, and its other bits name what else the PMIC latched.
  Reading PMIC registers from userspace is allowed (the rule that forbids
  it is about the PMU), through that chip's regmap in debugfs, and a single
  register rather than a whole dump (lesson from the amplifier regmap). Is
  `STATUS2` cleared on read, so that a userspace read could take the alarm
  away from the RTC driver? Not by the driver's own account: in the
  S2MPG14 regmap only `INT1` to `INT5` are marked precious ("clear on
  read"), and `STATUS2` is listed as volatile ("RTC alarm flag") and not
  precious, so it is a level flag that a read does not change, and regmap's
  debugfs refuses precious registers anyway.
  kernel #149 is the same readback for gs101's S2MPG10, which this tree
  gets wrong today; zumapro's and gs201's cases are already right, so that
  PR doesn't change what the 9a or the 7 Pro report.
- What the GNSS and fingerprint rails cost in sleep (S2).
- What MIF in sleep saves with the cable out (S1).
