<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a sleep: why s2idle drains so much

Status (2026-11-10): Two causes are known and fixed, and a third failure is open. Dead storage after a wake: the UFS pads came back as plain inputs; [linux-omarchy-mobile#224](https://github.com/derekross/linux-omarchy-mobile/pull/224), in review, re-applies the pin state at resume. A silent no-wake with C2 entered through s2idle's own path: with C2 disabled for the sleep (#96) or left to the ordinary idle path (#98) the RTC alarm woke the palmtop 300 of 300 times each; [omarchy-mobile#591](https://github.com/derekross/omarchy-mobile/pull/591) is the sleep hook for it. Open: on the published kernel, which has no idle states, a sleep still fails to wake now and then: one in 22 on 2026-11-09 (a boot without modules, no console), none in two re-runs of 36 with modules loaded, and one in 213 overnight on 2026-11-10 on the newest tip with the fixes. That one left a console: the kernel stayed alive, and CPU 7 answered nothing from just after the device suspend until the owner's reset (an RCU stall on CPU 7 every 63 s; neither the alarm nor the Power key got through); what that core was doing isn't known. The main PMIC's interrupt, and with it the RTC alarm, came to the published `zumapro-tegu.dts` with [linux-omarchy-mobile#236](https://github.com/derekross/linux-omarchy-mobile/pull/236), merged 2026-11-10; a kernel from before it has no alarm (`rtcwake` fails and a sleep ends only on a key), so check that `/sys/class/rtc/rtc0/wakealarm` exists before any RTC-woken sleep. Evidence: 300 of 300 RTC-woken 60 s sleeps twice (#96 WFI-only, #98 C2 at runtime, 2026-11-07/08), 15 of 15 wakes on the everyday path, the shell's auto-sleep behind the lock, twelve of them half-hour sleeps (#99, 2026-11-08), 12 of 12 half-hour auto-sleeps on #100 (11-09), and on the published tree with #224 and the PMIC interrupt 307 wakes and two no-wakes (11-09 and 11-10). The attended-first rule (S1, AGENTS.md) stands; the 11-10 run did not keep it (the run table says how it ran).
S1 is the condensed account: the two causes, the fix, a run table, what is
left and what was ruled out. The dated working notes that led there follow
it, oldest first.

## S1, condensed (2026-11-09): the two failures, the fixes, the runs

**What failed.** Every long s2idle series on the Pixel 9a since 10-28 ended in
one of two ways, at random, after 6 to 215 clean wakes (a third, seen with a
console once on the published kernel on 11-10, follows them):

1. **Dead storage after a wake.** The palmtop woke on its alarm, the kernel
   ran, SSH answered from memory, but UFS link startup failed every time
   (`link startup failed 1`, `Host init failed 1` five times,
   `ufshcd_wl_resume failed`), ext4 went `emergency_ro`, and nothing on disk
   could be read until a reboot. Cause: the UFS pads gph5-0 (the device's
   reference clock) and gph5-1 (its reset), on `13060000.pinctrl`, came back
   from the suspend as plain inputs (`CON 0x0`, read from the pin
   controller's debugfs with the palmtop in that state; `0x2` is the UFS
   function). The device then gets no clock and no reset edge, so no
   host-side retry can reach it. pinctrl-samsung's own save and restore of
   the bank writes the pads back as `0x22` at every wake, so whatever takes
   the function away does it after that restore.
2. **A silent no-wake.** The suspend side completed and nothing followed: no
   alarm, no power key, no USB, nothing in pstore; only Power + Volume Up
   brought the palmtop back. Caught on #97 by keeping the cluster watchdog
   counting through the sleep (a diagnostic): the console shows
   `PM: suspend entry`, the last CPU going down, and then the watchdog's
   reset. It happened only with the cores in C2 (the integration DT's
   `psci-suspend-param 0x10000`) during the sleep; with WFI for the sleep
   the RTC alarm woke the palmtop every time. The PMU's wake-up masks,
   which Google's `exynos-cpupm` programs and this kernel does not, decide
   what brings the SoC back once every core is down; the PMIC interrupt
   (the alarm's path, GIC SPI 74) evidently does not. The root cause below
   the masks (the missing `pmu_cpuhp` handshake on zuma, the maintainer's
   pointer) is open.
3. **One core stops answering, on the published kernel (2026-11-10).** With
   both fixes below and no idle states at all (the published device tree
   has none, so the cores only take WFI), the 213th sleep of an overnight
   series never woke, and this time the console survived: the kernel was
   alive for the two hours and forty minutes until the owner's reset, and
   CPU 7 answered nothing from just after the device suspend on (an RCU
   stall on CPU 7 reported every 63 s, the backtrace IPI unanswered each
   time, nothing of a resume printed, the alarm and two Power-key presses
   without effect). What CPU 7 was doing isn't known. Whether the 22nd
   sleep of 11-09 (no console) was the same isn't either. The last note
   below has the lines.

**The fixes.**

- [kernel #224](https://github.com/derekross/linux-omarchy-mobile/pull/224): `exynos_ufs_resume()` selects the UFS node's pin
  state again whenever it resumes with the link down (hibern8 included), and
  `exynos_ufs_suspend()` selects a new "sleep" state, which the zumapro
  device tree gives the UFS node (the same pin groups as the default, so
  there is a state to switch away from). Two commits, driver and DT.
- The sleep takes WFI while C2 stays available awake. In the runs below this
  was a `google,no-s2idle` idle-state property read by `dt_idle_states`
  (#98 to #100); the maintainer's reading of `kernel/sched/idle.c` is that
  with `enter_s2idle` cleared the cores still take C2 through the ordinary
  entry, without `tick_freeze()`, so what #98 measured may be C2 with the
  tick running rather than WFI, and the property is dropped from #224. The
  shipping form is a sleep hook in `omamobile-device-tegu` that disables
  `cpuidle/state1` on every CPU before the sleep and enables it after (both
  `find_deepest_state()` paths skip a disabled state), which is what #96 had
  for the whole run. The published zumapro device tree has no idle states
  yet, so on the published kernel the question doesn't arise until they come.

**Runs** (all on the palmtop, on the charger, cable in, modem off for the
boot unless said; `systemctl suspend` with an RTC alarm, 60 s unless said;
"attended" means a person at the laptop watching the loop with the owner at
home for a button press; the first run of every new kernel was watched that
way, and the long unattended stretches ran under the loop's recovery budget,
with one exception, the last row: a new build's first run went overnight
with the owner asleep, started by hand over SSH and followed only by a poll
that could report, which is not what the rule asks):

| Kernel (`uname -v`) | Change under test | Cores in sleep | Result | Attended |
| --- | --- | --- | --- | --- |
| daily (11-03, S1-W) | none, WFI-only | WFI | 80 clean, the 81st dead storage | first runs yes, then watched |
| daily (11-03, S1-U) | UFS `spm_lvl` 3 | WFI | 34 clean, the 35th dead storage | yes |
| #91 | link-startup retries after a failed attempt | WFI | 12 and 15 clean, then dead storage; the retries didn't help | yes |
| #92 | a real VCC power cycle on a failed attempt | WFI | 130 clean in three runs, three dead | first run yes |
| #93, #94 | the kernel kept alive on a dead wake, readbacks | WFI | 17 and 35 clean, then dead; the pads read `CON 0x0` | yes |
| #95 | the pin state re-applied at resume | WFI | 129 clean, the 130th dead: the pads now read `0x2` but the host had already given up (a wait too short) | first run yes |
| #96 | #95 with the resume order fixed | WFI | **300 of 300** | first run yes, then the loop overnight |
| #96, S2 | the same kernel, C2 allowed | C2 (s2idle entry) | 18 clean, then a silent no-wake | yes |
| #97 | #96 plus the watchdog kept through the sleep | C2 (s2idle entry) | silent no-wake at the 7th sleep, caught on the console | yes |
| #98 | #97 plus `google,no-s2idle` on the C2 states | C2 awake, WFI (or C2 without the tick) asleep | **300 of 300** | first run yes, then the loop |
| #99 | #98 with the watchdog diagnostic off | as #98 | the everyday path: a Power-key wake, a 30-minute and a one-hour sleep, twelve half-hour auto-sleeps: **15 of 15** | yes, through the shell's own auto-sleep |
| #100 | #99 plus kernel #172 and #150 (the modem fixes the test tree lacked) | as #98 | a 6-hour auto-sleep series: **12 of 12** half-hour sleeps (11-09) | the first hour yes |
| published `1a9d1d4e9` + #224 (`push1-gf693b36e62ce`) | the published tree as it is | WFI (no idle states) | no series: no RTC alarm (the main PMIC has no interrupt in `zumapro-tegu.dts`), `rtcwake` failed, the first sleep lasted 31 minutes until a key press | yes |
| published `abcd6aac5` + #224 + the PMIC interrupt (kernel #236), build #1, no modules installed | the alarm | WFI | 21 woke, the 22nd never did (no ramoops on that boot, nothing on the console) | yes |
| the same sources (`push1-g6c9420bfa77f`), modules installed, ramoops on | the re-run | WFI | **36 of 36** (60 s, `pm_wakeup_irq` 52 each, no UFS line) | yes |
| the same sources, build #2 with `CONFIG_PHY_ZUMA_PCIE=m` (#274) | the same with Wi-Fi up and kept across the sleeps | WFI | **36 of 36**, wlan0 passing traffic after | the start yes, then the loop |
| published `2f890a533` (11-10) + #224 + #236 + #237 (`push1-gff4fdf58035e`, build #4), modules installed, Wi-Fi kept, the hook of #591 installed | the newest tip, overnight | WFI | a 27-minute sleep ended by the Power key, then 212 woke and the 213th never did: CPU 7 stopped answering, the console kept | no (the owner asleep; his reset in the morning) |

Before #96, one wake in 15 to 215 lost the storage; before #98, C2 in the
sleep lost the palmtop after 6 to 135 cycles.

**Ruled out** (each tried on the dead-storage path and failed the same way):
a host reset, a longer (1 ms) reset pulse, a PHY power cycle, link-startup
retries with waits of up to 1.6 s, a real VCC power cycle (#92), the UFS IO
coherency setting (135 wakes with no dead storage on the coherency kernel
and then a silent no-wake, so not the cause), the breadcrumb module in the
PMIC RTC (dropped), systemd's runtime watchdog (it reset the palmtop on a
dead wake before the capture, #93). On the no-wake path: Volume Up's
missing pull, NFC polling (stopped by the hook throughout), the modem
(off), Wi-Fi (kept, as the hook does).

**What is left.**

1. The no-wake on the published kernel. On that tree 307 sleeps have woken
   (21, 36, 36, two ended by the Power key, 212) and two have not: the 22nd
   of 11-09's first run, with no console, and the 213th of 11-10's, whose
   console shows CPU 7 not answering while the rest of the kernel runs
   (failure 3 above). Next: the same series on a build that can show what
   that core is doing and that recovers by itself, with pseudo-NMI
   (`CONFIG_ARM64_PSEUDO_NMI=y`, `irqchip.gicv3_pseudo_nmi=1`), so the
   stall report's backtrace reaches a core with interrupts masked, and
   `kernel.panic_on_rcu_stall=1`, so the stall becomes a panic, a reboot
   through `panic=10` and a console in pstore with no buttons. If the
   core doesn't answer an NMI either, it is stuck below the kernel or
   stopped, and the series goes on with the PMIC commits alone, without
   #224's two.
2. The sleep hook ([omarchy-mobile#591](https://github.com/derekross/omarchy-mobile/pull/591)): its series is in (the
   last note below, 40 of 40); it waits for its merge.
3. Sleep with the modem up (M6): never run with the fixes; the one try
   before them (10-27) also had NFC polling.
4. The root cause under the masks: zuma's PMU data without `pmu_cpuhp`,
   compared with gs101/gs201 before idle states come to a PR.
5. The DEVICES cell to "works" once item 1's no-wake is found and fixed,
   and #224, the PMIC interrupt (kernel #236) and the hook are merged and
   have run from the published kernel.

**Scripts** (`device/tegu/bringup/`): `sleep-series.sh` (on the palmtop:
N RTC-woken `systemctl suspend` cycles of S s, records each wake),
`sleep-series-loop.sh` (laptop: polls the series, captures a dead wake,
recovers with sysrq under a budget of MAXREC recoveries per 24 hours,
records the next boot's ext4 recovery, restarts the series; it unmasks `sleep.target` and `suspend.target` for the run and puts them back as it found them when it exits),
`sleep-kernel-run.sh` (laptop: a rewrite of the owner's kit launcher, pushes a built kernel and starts the loop),
`sleep-autosleep-series.sh` and `sleep-autosleep-watch.sh` (the everyday
path: the shell's auto-sleep does the sleeping, the script only arms the
alarms).

The dated working notes that led here follow, oldest first; they are the
long story and the record of what each day tried.

Historical status (2026-11-03): s2idle usually works (RTC and power-key wakes; ten of
ten 30-second cycles on 10-31 with the console kept through the freeze;
126 of 127 120-second sleeps overnight on 11-01 to 11-02), but not always:
seven sleeps have never woken: two direct freezes, one 30-minute systemd
sleep with `tegu-mif-sleep` loaded, the sixth 30-second cycle of a boot
on 10-30 (it left the USB bus and needed a forced restart), the 21st of
11-01's thirty cycles, the overnight series' 127th, and the tenth of
11-02 evening's series with Wi-Fi unloaded around each sleep. Two more
woke with UFS dead (`link startup failed` x5, then I/O errors and
`emergency_ro`: 10-30 afternoon, and S1-W's 81st on 11-03), and one boot
reset after a brcmfmac oops (S1-W, 11-03). The drain in sleep is
high. Sleep tests are attended. The shell's auto-sleep (the `omamobile-sleep`
toggle, which the package ships off) has been on on the palmtop since
2026-11-01 by the owner's choice, and every sleep it took that day woke
(see "A day of use with auto-sleep on" below).
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

  **Thirty 120 s sleeps with core power-down on (2026-11-01, same release,
  device-tegu 0.2.4).** Screen off through Hyprland's DPMS before each
  `systemctl suspend`, `printk.console_suspend=N`, NFC polling stopped by
  its hook, Wi-Fi kept: thirty of thirty woke on the PMIC line (IRQ 56,
  the S2MPG14's, which the RTC alarm shares with other PMIC events).
  Measured by the RTC (`since_epoch` before and after, less about 15 s
  of the cycle that isn't sleep), 27 lasted 118-123 s, the alarm's time;
  one lasted 106 s, one 112 s and one 64 s, too early for the 120 s alarm.
  The series recorded only the wake IRQ, not the `rtc-alarm0` count or
  INT2, so what woke those three isn't known: count them as early PMIC
  wakes, as on the 7 Pro, not as alarm wakes. The dmesg delta read 1.5-1.6 s
  every time, so the correction above holds. `suspend_stats` 36 to 66
  successes, 0 failures; no UFS errors and no ACPM timeouts. At the
  earlier rate of about one hang in 21, thirty clean sleeps would still
  happen by chance about one time in four, so this narrows the hang but
  doesn't retire it.

  **A day of use with auto-sleep on (2026-11-01, same release).** The
  owner turned the shell's auto-sleep back on in the morning: sleep 30 s
  after the screen goes off behind the secure lock, wake by the power key,
  cable in or out. A temporary hook logged each sleep's real length by the
  RTC. Seven sleeps in real use between 11:15 and 12:57 (1021, 1300, 11,
  266, 61, 700 and 1065 s) all woke, with no UFS errors. Later that day, a 30 s sleep with an RTC
  alarm and a power-key wake on #268's 0.2.68 build of the shell also woke clean. One
  morning wake looked like a hang to the owner ("pressed Power, no
  reaction") and was taken for one at the time. It wasn't: the journal
  shows the press woke the palmtop at 12:11:04, and sleepd took the wake
  for a dark resume (the 9a's power key is `Power` in
  `/proc/interrupts`, not `KEY_POWER`) and slept again 5 s later. The
  owner's next press, part of a Power + Volume Up hold, woke it again and
  lit the screen. #268 (omamobile-shell, not merged when this was written;
  the palmtop ran its 0.2.68 build) recognises the 9a's power key, and #275 cut the time from the press to a lit screen from about
  1.2 s to about 0.25 s; before that, a second press often looked
  necessary. So none of the day's sleeps hung. This adds to the evidence
  but doesn't retire the hang of 10-28 to 10-30 either.

  **An overnight series, 2026-11-01 to 11-02 (same release, unattended
  through the night).** Two hundred 120 s sleeps were planned through
  `systemctl suspend` with an RTC alarm, auto-sleep off for the run, the
  console kept through the freeze (`printk.console_suspend=N`), cable in,
  modem never loaded, NFC polling stopped by the sleep hook, Wi-Fi kept
  loaded. 126 sleeps woke: `suspend_stats` success 126 and fail 0, wake IRQ
  56 every time, no UFS or ACPM lines, and Wi-Fi came back after each
  (brcmfmac re-probes after every wake: "device lost its state in sleep").
  The 127th didn't wake (about 22:42 by the palmtop's clock): no SSH over
  USB or Tailscale for nine hours, and the owner's Power + Volume Up in the
  morning restarted it. It entered that sleep like the 126 before it, with
  the same NFC notifications, hooks and timings, and the journal stops at
  `Reached target Sleep` and the user slice's freeze. Nothing was kept:
  `/var/lib/systemd/pstore` held only an older entry, so with the console
  kept through the freeze, a Power + Volume Up reset doesn't keep the
  ramoops region either (the console never reached it, or the reset
  cleared it). That makes it one hang in 127 here, against one in 21 on
  11-01 and about one in 40 before; the rate varies too much to compare
  conditions with short runs. Logs: `logs/tegu-sleep-overnight-20261102/`
  (the series script, `after-hang.txt`).

  **Wi-Fi unloaded around each sleep, 2026-11-02 evening (same release).**
  The one change from the night before: the Wi-Fi keep flag moved aside
  for the run, so the sleep hook unloaded brcmfmac before each sleep and
  loaded it after, instead of keeping it loaded through a re-probe at every
  wake. Otherwise the same series: 90 s RTC-woken `systemctl suspend`
  sleeps, screen off through Hyprland's DPMS, the console kept through the
  freeze, auto-sleep off, cable in, modem never loaded, NFC polling stopped
  by its hook, core power-down on (every `state1/disable` read 0 after the
  wake). Nine woke: 94-95 s by the RTC each, wake IRQ 56, no UFS or ACPM
  lines, `suspend_stats` success 9 and fail 0. The tenth didn't (entered
  20:30:33 by the palmtop's clock): its journal ends at
  `PM: suspend entry (s2idle)`, and the palmtop stayed off the bus until
  the owner's Power + Volume Up the next morning. Again nothing was kept:
  the only pstore record since is the console of a later clean reboot
  (with ABL's own log after it), which confirms that a warm reboot keeps
  ramoops and the buttons' reset doesn't. So the hang is not brcmfmac's
  re-probe either; with 11-02's one in 127, that is one in 10 here.
  Logs: `logs/tegu-sleep-overnight-20261103/`.
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

**S1-W. WFI only, a long series (risk low; attended, cable in).** Core
power-down saves nothing measurable in sleep (302 mA asleep against 311 mA
awake with the screen off, S1 result), so if the hang lives in the PSCI
core power-down path, sleeping on WFI alone would cost nothing and avoid
it. The 11-01 correction above showed a WFI-only sleep is shallower (the
tick isn't frozen), not that it hangs or doesn't; twenty such sleeps woke
that day, too few against a rate between one in 10 and one in 127. So:
300 sleeps of 60 s with every CPU's `cpuidle/state1/disable` at 1 for the
whole run, everything else as the overnight series. At one hang in 40,
300 clean sleeps would happen by chance about one time in 2000; at the
overnight rate of one in 127, about one time in 11. The script is
`device/tegu/bringup/sleep-series-wfi`.

```sh
# Before: the modem must not run this boot (its inhibitor blocks suspend, and suspend with the modem up is unqualified).
# omamobile-tegu-modem-boot is #372's unit (not on main yet; on the palmtop from that branch): with it off, start the
# AoC, Trusty and Wi-Fi by hand after the boot (systemd-run /usr/local/bin/omamobile-tegu-audio-up), as the hung runs had them.
tools/phone-ssh 'systemctl disable omamobile-tegu-modem-boot.service && systemctl reboot'
# After the boot: auto-sleep off, the modem not started, the hook from #255 absent.
tools/phone-ssh 'pgrep -f omamobile-modem-start; ls /usr/lib/systemd/system-sleep/'
#   Expect: no modem process, no omamobile-tegu-cpuidle
tools/phone-ssh 'cat > /root/sleep-wfi.sh' < device/tegu/bringup/sleep-series-wfi
tools/phone-ssh 'systemd-run --unit=x-sleep-wfi bash /root/sleep-wfi.sh'
# Each check (read-only):
tools/phone-ssh 'tail -3 /var/log/omamobile/sleep-wfi-20261103.log'
#   Expect: one line per cycle, rtc about 60 s, wake irq 56, ufs 0, acpm 0, oops 0, state1 all 1, fail 0
#   Stop: UFS errors or an oops (the script stops itself; after UFS errors, echo b > /proc/sysrq-trigger), or no SSH 3 minutes past a cycle's alarm
#   (a hang: Power + Volume Up by the owner, then the journal of that boot)
# Rollback: the script's EXIT puts state1 back and re-enables the modem boot unit; after a hang, a reboot puts state1 back
# (sysfs), and the unit is enabled again by hand: systemctl enable omamobile-tegu-modem-boot.service
```

Pass: 300 of 300 woke. Then the drain on WFI alone against core power-down
(S1's buck-off coulomb counts, 240 s sleeps each way) decides whether the
device package should sleep on WFI. Fail: a hang on WFI alone retires core
power-down as the cause.

**S1-W, first runs (2026-11-03, same release).** The first start had
none of the AoC, Trusty or Wi-Fi up: on the palmtop the modem boot unit
(#372) now runs `omamobile-tegu-audio-up`, and with that unit off for the
series nothing else did. Its 22 sleeps all woke (wake IRQ 56, no UFS or
ACPM lines), but it isn't the hung runs' setup, so the series restarted
after `omamobile-tegu-audio-up` by hand. That boot reset itself on its
third sleep, and for the first time pstore kept the console, because the
watchdog, not the buttons, reset it: brcmfmac's escan timeout worker had
oopsed a minute earlier on a NULL channel (a BSS on 5 GHz channel 177,
which the band table lacks; kernel #191), inside cfg80211's RCU read-side
section. The next suspend couldn't freeze khugepaged (stuck in
`lru_add_drain_all()`), ACPM's DVFS and thermal channels timed out
(`Timeout! ch:0`, `ch:9`, then `RX front can not keep up with TX front`),
the suspend was retried, and the watchdog reset the SoC. None of the
silent hangs had an oops in its journal, so that is a second failure, not
the hang. The series now stops on any oops, and runs again from
2026-11-03 10:49.

**S1-W result (2026-11-03, same release): 80 woke, the 81st woke with UFS
dead.** The run from 10:49 (the AoC, Trusty and Wi-Fi up, every CPU on WFI
alone) had 80 clean sleeps: wake IRQ 56 each, no UFS, ACPM or oops lines,
Wi-Fi re-probed after every wake. The 81st (12:19) woke on its alarm, but
UFS didn't come back: `resume-trace: wl resume begins (pm_op 1, link 0,
dev 3)`, then `link startup failed 1` and `Host init failed 1` five times
within 20 ms, then I/O errors and ext4 `emergency_ro`, the 10-30 afternoon
shape. A good resume shows a first link attempt that fails in
`zumapro_ufs_pre_link()` on `dme-set: attr-id 0x4021` (T_PeerDeviceID) and
a retry that works; the bad one has no such line, and the link startup
command itself failed on every try. brcmfmac's re-probe over PCIe ran at
the same moment as on every other wake. `echo b > /proc/sysrq-trigger`
brought the palmtop back, and the next boot mounted the root read-write.
So WFI alone doesn't prevent the dead-storage wake: that failure is in the
UFS resume from `spm_lvl` 5 (device powered down, link off), which runs a
full link startup at every wake. No silent hang in 102 WFI-only sleeps
today (22 + 80), which against one in 10 to one in 127 says little.

**S1-U. UFS at `spm_lvl` 3 for system sleep (risk medium; attended, cable
in).** At runtime this palmtop's UFS idles at `rpm_lvl` 3 (device sleep,
link in hibern8) many times an hour without an error (kernel #99), and a
resume from it is a hibern8 exit, not a link startup. At `spm_lvl` 3 system
sleep uses the same states. The 7 Pro needed 5 because its first hibern8
exit after a freeze failed once at 3 (S1-S3 of its SUSPEND-PLAN), so this
is the 9a's own question. The same series as S1-W with `spm_lvl` 3 and the
CPUs' idle states left as they ship (core power-down on), so it is the
setup the package would ship; the script puts 5 back on EXIT. Medium, not
low: on the 7 Pro, `spm_lvl` 3 needed a host reset on its first resume. The
script is `device/tegu/bringup/sleep-series-spm3`.

```sh
# Before: as S1-W (the modem boot unit off for the boot, the AoC, Trusty and Wi-Fi by hand). Read the levels:
tools/phone-ssh 'u=/sys/devices/platform/soc/13200000.ufs; cat $u/spm_lvl $u/rpm_lvl'
#   Expect: 5 and 3
tools/phone-ssh 'cat > /root/sleep-spm3.sh' < device/tegu/bringup/sleep-series-spm3
tools/phone-ssh 'systemd-run --unit=x-sleep-spm3 bash /root/sleep-spm3.sh'
tools/phone-ssh 'head -1 /var/log/omamobile/sleep-spm3-20261103.log'
#   Expect: spm_lvl 3 (SLEEP/HIBERN8), state1 disable all 0
# Each check (read-only):
tools/phone-ssh 'tail -3 /var/log/omamobile/sleep-spm3-20261103.log; dmesg | grep -c ufshcd_err_handler'
#   Expect: one line per cycle, rtc about 60 s, wake irq 56, ufs 0, acpm 0, oops 0, spm 3, fail 0; the error-handler
#   count recorded (a recovered hibern8-exit error is a finding, not a stop)
#   Stop: UFS errors or an oops (the script stops itself; after UFS errors, echo b > /proc/sysrq-trigger), or no SSH
#   3 minutes past a cycle's alarm (a hang: Power + Volume Up by the owner, then the journal of that boot)
# Rollback: the script's EXIT writes spm_lvl 5 and re-enables the modem boot unit. spm_lvl doesn't persist, so after a hang
# or a sysrq reboot the boot comes up at 5; enable the unit by hand as in S1-W.
```

Pass: 300 of 300 woke at `spm_lvl` 3 with no UFS errors. Then `spm_lvl` 3 for
system sleep goes into the device package (a udev rule or the sleep hook)
for a longer run in daily use. Fail: a dead-storage wake at 3 too moves the
question into the hibern8 path itself.

**S1-U result (2026-11-03, same release): 34 woke, the 35th woke with UFS
dead.** At `spm_lvl` 3 every one of the 35 wakes logged `pwr ctrl cmd 0x18
… failed, host upmcrs:0x5`: the hibern8 exit never worked, and the error
handler's host reset (a device reset and a full link startup) recovered 34
of them. `exynos_ufs_suspend()` powers the UFS PHY off whenever the link
isn't active, hibern8 included, and `gs101_ufs_suspend()` holds the
device's reset line low through the sleep, so a hibern8 exit has nothing
to come back to. The 35th wake's link startup in that reset failed, as at
5. So `spm_lvl` 3 isn't a fix on this driver: every wake ends in the same
full link startup.

**A good wake's first link attempt fails too.** In S1-W's boot all 80 good
wakes logged `dme-set: attr-id 0x4021 val 0x1 failed 0 retries`
(T_PeerDeviceID, written in `zumapro_ufs_pre_link()`), and the core's
retry then worked. The dead wakes are the ones where every retry failed.
T_PeerDeviceID is the host's own UniPro attribute, so the first write
failing points at the host side not being ready, not the device.

**S1-R, a wait after the device reset (2026-11-03, attended by the
operator, not the owner; risk low).** The test: the daily kernel with
`usleep_range(10000, 11000)` after `exynos_ufs_dev_hw_reset()` releases
RST_n (Image only, same release), ten 60 s sleeps at `spm_lvl` 5. Result:
`dme-set 0x4021` failed on all ten wakes, as without the wait. That wait did
not resolve the observed local DME error; it does not rule out every device
readiness or reset-timing issue. Other candidates include the zumapro host
clocks after the CMU gates and UniPro's own reset state. The daily Image went back the same afternoon.

**A gap against stock: IO coherency after resume.** Google's driver
re-applies the UFS IO-coherency bits in the HSI2 sysreg
(`exynos_ufs_config_externals()`, at every resume); ours sets them once, in
`exynos_ufs_shareability()` at probe. With `dma-coherent` they must read
set (0x13020710, bits 0 and 1): 0x13 after a boot with no sleep, and 0x13
after one wake. Reading the register from userspace isn't safe after a wake
(below), so the test is a kernel that sets them again at resume, as stock
does (`ufs-exynos-iocc-resume` on the owner's fork), and a long series on it.

**Two resets at screen-on after a wake, caused by the test itself
(2026-11-03 15:28 and 15:34).** For the coherency question the series read
0x13020710 through `/dev/mem` after every wake. Twice, after the second and
then the first wake, the palmtop woke cleanly, the script's DPMS enable
switched the display to 120 Hz, the console ended there with no oops or
panic, and the SoC watchdog reset the palmtop a minute later (ramoops kept
it). The read comes right after that DPMS enable, and the 114 earlier wakes
of the day, without it, never hung there. The HSI2 sysreg's clock can be
gated after a wake, and AGENTS.md forbids reading a block that isn't known
powered and clocked: these resets are the read's, not sleep failures. The
read is out of the scripts. Logs: `logs/tegu-ufs-iocc-20261103/`.

**The coherency kernel, a long series (2026-11-03 15:38 to 18:47, owner
present for the end).** The daily kernel with `exynos_ufs_shareability()`
also at resume (Image only, same release; the commit is
`ufs-exynos-iocc-resume` on the owner's fork), the same series as S1-R at
`spm_lvl` 5 with the CPUs' idle states as shipped, the AoC, Trusty and
Wi-Fi up, no register reads: 135 sleeps woke, every one with UFS fine (no
link-startup, host-init or I/O lines; the first-attempt `dme-set 0x4021`
on each wake as always), against dead storage at the 81st (S1-W) and 35th
(S1-U) earlier the same day. The 136th never woke: the journal ends at
`Performing sleep operation 'suspend'`, the power key didn't light the
screen, the owner's Power + Volume Up restarted it, and pstore had nothing
new. So one run of 135 without a dead-storage wake, which is suggestive
for the coherency fix and no more (at one in 80, 135 clean wakes happen by
chance about one time in five), and a silent no-wake that the fix doesn't
touch and that still needs a record that survives the buttons' reset.

**A record that survives the buttons (next).** The silent no-wake leaves
nothing: the watchdog is stopped in s2idle and a Power + Volume Up reset
loses ramoops. The S2MPG14 RTC is battery-backed and its alarm 1 is unused
(`rtc-s5m` arms alarm 0 only), so a bring-up module (owner's logs,
`tegu-sleep-crumbs`, not for merge) writes a stage code to A1SEC and a
sleep count to A1MIN at each suspend and resume phase, the enable bits
always clear, each write committed to the RTC block with AUDR, and prints
the previous boot's last stage at load. Its first run is attended: check
alarm 0 and the time still work, that the crumb survives a reboot, and
that it survives one Power + Volume Up reset; only then a long series
with it.

**The breadcrumbs' first night (2026-11-03 20:06-20:37).** On the
coherency kernel the module loaded and read alarm 1 as zero; a 60 s sleep
with it loaded woke, but after a warm reboot the next load still read
0x00, so as built it doesn't leave anything readable across even a warm
reboot (the commit to the RTC block, the read-back or ABL; not known which).
The series that followed, with the module loaded, had nine clean wakes,
and the tenth never woke (journal ends at `Performing sleep operation
'suspend'`; the owner's Power + Volume Up; pstore had nothing new; the
module again read 0x00). The module's ACPM writes in the noirq phases may
also change what they're meant to observe, so the series went on without
it, and the module gets a write-and-read-back test within one boot first.

**The night of 11-03 to 11-04, counted.** On the coherency kernel without
the breadcrumbs, the second wake found UFS dead again (link startup failed
at once, five times; no first-attempt `dme-set` failure, as on every dead
wake), so setting the coherency bits again at resume isn't the fix and the
135 before it were luck. A debug kernel (the daily plus a dump of the
standard and vendor HCI and two UniPro ranges whenever a link startup
fails, Image only, same release) then ran under a loop that would capture
each dead-storage wake and recover it with sysrq; its first series had 18
clean wakes and the 19th never woke. The day's tally of silent no-wakes,
all on `spm_lvl` 5 with core power-down on: after 135, 9 and 18 clean
wakes; of dead-storage wakes: after 80, 34 (`spm_lvl` 3) and 1.

**Two failures, two settings (as of 11-04).** The silent no-wakes and
the dead-storage wakes look separate. Every silent no-wake on 11-03 and
11-04 came with core power-down on (after 135, 9 and 18 clean wakes, about
one in 55), and 102 WFI-only wakes the same day had none (at one in 55,
about one chance in ten). Dead storage came on both (WFI: after 80; core
power-down: after 34 at `spm_lvl` 3 and after 1). Next, one setup for both
questions: WFI only, on the debug kernel, under the capture loop. If WFI
removes the silent no-wake, nothing stops the loop, and every dead-storage
wake leaves a register dump and is recovered with sysrq.

**Recovery preparation (2026-11-04).** A fresh read-only SSH check found the
daily `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty` build #7
running, root mounted read-write, and no current UFS link-startup, host-init
or I/O errors. The modem boot unit is disabled, though the unit is active.
The interrupted push log records verified writes to `boot_b`, `init_boot_b`
and `vendor_boot_b` only. It does not establish the current contents of the
other two partitions. Do not reboot until the image set is restored.

The daily backup is in `logs/tegu-night-20261104/kit-backup-night/`, not the
`logs/tegu-review-20261029/runners/kit-backup-night/` path that `kit_restore
night` uses. A separate copy of the kit at
(a local scratch directory, not in the repository) has the backup's daily Image
(`7f3674d21e92d758...`) and has been packed twice; all five images matched
between packs. Compared with the interrupted debug pack, only `boot.img`
differs. The copied push descriptor has been aligned with the pack descriptor.
The current kernel's installed module tar marker matches the copied kit's
tarball. This is preparation only; the partitions have not been rewritten.

**Daily restored (2026-11-04).** With the owner's approval the prepared daily
images were pushed, all five slot-B writes verified by sha256, and the
palmtop rebooted into the daily build #7. A fresh SSH check found root
read-write, the modem boot unit enabled and active, and no UFS link-startup,
host-init or I/O errors in the new boot's dmesg. The audio unit was still
activating at that check.

The old night loop is not a gated test: it reboots automatically after either
an inactive service or a UFS error, and the series does screen and disk work
before checking dmesg for UFS errors. Do not run it as-is. The debug Image's
saved UFS diff does not contain the advertised register-dump changes, and
the current omb tree no longer contains them either. Recover and review the
exact instrumentation source before booting it; in particular, establish
which registers are safe to read at the point where link startup has failed.
The v2 RTC breadcrumb module has not passed the separate selftest and reset
survival checks, and its ACPM writes can perturb suspend; do not combine its
first test with the UFS capture.

The existing failure log alone does not show which side failed. In this tree,
`ufshcd_link_startup()` ignores the return from its PRE_CHANGE callback and
then issues `DME_LINK_STARTUP`. The `link startup failed 1` line can report
a result from that command or from a later step, so it does not by itself
prove that the device failed to answer or that RST_n or refclk was wrong.
The recurring `0x4021` error is also emitted by the host's local DME
set and is not a record of a peer transaction. A useful capture must separate
the callback's first error, each link-startup result, and host/PHY state,
without assuming a failing register block is safe to read.

**S1-T, command-result tracing (prepared 2026-11-04).** A temporary patch to
`ufshcd_link_startup()` logs the existing PRE_CHANGE callback's result, the
existing `DME_LINK_STARTUP` result and retries remaining; the callback result
remains ignored, as it was before. It adds no register reads and leaves the
driver's control flow unchanged. Source and patch are in the laptop's
(a local scratch directory, not in the repository); the omb integration tree's original
`ufshcd.c` is saved as `ufshcd.c.before-suspend-trace-20261104`.
The `W=1` Image build passed with no warnings attributed to the UFS core or
Exynos host source; it reported 1,143 warnings elsewhere, mainly generated
syscall initializers, without a baseline comparison. The Image's sha256 is
`6b7492cbb5db6d1ec5fc6809e3144bc97899f9487c36269dc246d860c38cda01`.
All five images matched across two packs; only boot differs from the daily
pack. No phone test has run on it yet.

Gates, risk medium (a failed wake may need the buttons):

1. Build the trace kernel on omb with `W=1`; record the Image hash and warnings.
   Pack it with the daily kit and verify all five images before pushing.
   Stop if the build, module identity or any image check fails. Rollback: the
   separately packed daily kit at (a local scratch directory, not in the repository).
2. With a sleep inhibitor held, disable the modem boot unit for the test boot;
   push the trace image set and verify the new boot, root, trace and UFS health.
   Stop on any failed write, missing SSH or unexpected kernel. Rollback: enable
   the modem boot unit and push the verified daily image set.
3. Start a live kernel journal stream to the laptop, then run the temporary
   `series.sh` from (a local scratch directory, not in the repository) on the palmtop. It
   selects s2idle, disables CPU state1 for the run, checks UFS immediately
   after each wake, stops on UFS error or missing suspend, and re-enables the
   modem boot unit on a clean exit. Expect 300 RTC-woken 60-second sleeps with
   no UFS errors. Stop on an error, oops or lost SSH; preserve the stream.
   For dead storage, use the approved sysrq reboot only after capture, then
   verify the next boot. Rollback: re-enable the modem boot unit and push the
   daily kit; on a silent hang, ask for the buttons and do not send more
   commands to the unresponsive palmtop. Do not load RTC breadcrumbs in this
   run.

**S1-T first run (2026-11-04, trace kernel `#41`, same release).** All five
image writes were verified and the palmtop booted with root read-write, no UFS
error and the modem unit disabled and inactive. The trace was present at boot;
the Wi-Fi module was loaded. The audio unit's start script had finished and
its post-start data retry was still running. The series selected s2idle and
disabled state1. The laptop lost its streams and fresh SSH timed out, but the
palmtop had **not** hung: the previous boot's journal, recovered after the
owner's button reset, records ten completed sleep cycles, RTC elapsed 56-66 s,
with no UFS errors and no state1 s2idle entries. The last recorded cycle
resumed successfully. The owner also reported that Power lit the screen before
the reset. The lost USB/SSH connection is a separate observation and the
missing stream must not be counted as a silent no-wake. No UFS failure was
captured. A good resume includes `pre=6 startup=1 retries=3`, followed by
`pre=0 startup=0 retries=2`; `6` is the UIC locked-attribute result, consistent
with the recurring `0x4021` message. The full previous boot's kernel and
series journals are kept locally under `logs/tegu-suspend-trace-20261104/`.
The daily image set was then pushed and all five images verified. It rebooted
on build `#7` with root read-write, the modem boot unit enabled and active,
and no UFS errors in the new boot. The audio unit was still starting at the
first check.

Future test monitors must not infer a hang from a lost USB stream alone: the
ten cycles continued and were recorded in the local journal while both live
streams were silent. Arrange a second observation path or a detached run and
check its journal when the link returns. A true RTC/power-key no-wake still
needs separate evidence.

**S1-T2, preserve a dead-storage record (prepared 2026-11-04).** The daily
boot has persistent journal, an active ramoops backend and `kernel.panic=10`.
Wi-Fi is connected, Tailscale is active, and a fresh SSH connection over the
tailnet worked independently of USB. A test-only kernel adds a panic only if
the zumapro UFS host's full reset-and-restore fails during system resume; the
failure is already unrecoverable for the mounted root at that point. The
existing panic timeout should reboot and leave the command trace in ramoops,
even if both networks are down. It adds no register reads. This is a capture
mechanism, not a fix. Stop after one such panic and save pstore before another
test; do not restart the series automatically after a boot. Risk medium:
the intentional panic can lose in-flight userdata writes, the capture may not
survive, and a broken test image can require button recovery. Rollback: enable
the modem boot unit and push the staged daily image set. Verify a build and
both network paths first, and run the same WFI-only, one-change test runner.
The `W=1` incremental build passed with no warning lines. Its Image sha256
is `4f84374b0794f7cba3132e71e2185f4a795bcee560913a67158ec41461eb6e37`;
all five images matched across two packs. The first trace kernel (`#41`) and
its original source remain saved locally for comparison.

**S1-T2 started (2026-11-04, build `#42`).** All five slot-B images were
verified, root was read-write, `kernel.panic` was 10, the ramoops backend was
registered, and the modem unit was disabled and inactive. A fresh SSH check
over Tailscale worked before the test. The WFI-only series was started as a
transient service with a 60 s RTC alarm. Both live streams stopped reporting
and one later fresh tailnet SSH attempt timed out; the laptop also has no USB
network interface. As S1-T showed, this does not establish a hang. Leave the
detached series alone and read its journal when a connection returns. A failed
UFS reset-and-restore should panic once, leave a pstore record and reboot; it
must not automatically start another series. No result can be claimed until
the service journal or pstore is recovered.
After the run started the laptop twice briefly saw its USB route return, but
each fresh SSH attempt timed out and the route disappeared again. This is
consistent with a short wake window but does not establish a completed cycle.
The laptop watched the local route and connected immediately at the next USB
reappearance. The service journal then showed **15 completed cycles**, no UFS
errors, and the service still active; pstore was empty. A later check showed
**20 completed cycles**, again with no UFS errors and an empty pstore. The
series stopped after reporting cycle 22: its cycle-23 counter check ran just
before `systemd-sleep` logged the corresponding resume and the kernel updated
`suspend_stats`. The journal and final counter show **23 successful sleeps**,
zero failed sleeps, no UFS errors and no kernel oops. The runner's counter
check was corrected to wait up to 30 seconds for that update, checking UFS
errors while it waits. This was a runner race, not a failed suspend.
The corrected script was copied to `/run/tegu-suspend-trace-series2.sh`, its
hash verified, and started as `x-suspend-pstore2.service` on the same `#42`
boot. The modem boot unit was disabled again for this run. A laptop monitor
checks it at five observed USB wake windows and stops if SSH fails or the
service is no longer active; a separate passive monitor watches for a
sustained USB route or a reachable tailnet peer after a possible reboot.
An independent temporary `x-suspend-ufs-guard.service` checks the same
unrecoverable-error patterns after wake and writes SysRq `b` immediately if
one appears, as required by the dead-storage recovery procedure. It runs
only while this series is active and does not start another test. This guard
can reboot before the diagnostic panic finishes collecting pstore; storage
recovery takes precedence over that capture. Its active state was verified
again after a suspend and wake.
An additional `x-suspend-kmsg-guard.service` keeps `dmesg --follow` and a
shell reader resident so an error can trigger SysRq without first loading a
new executable from the failing root filesystem. It was active after another
wake; an offline simulation verified its three match patterns without issuing
SysRq. Unlike the first guard, it remains active after a clean series exit;
stop it explicitly when the test ends or before returning the daily setup.
The first 180 cycles of the corrected series completed without unrecovered
UFS errors;
the service remained active and pstore was empty. Together with the earlier
23 successes this is 203 completed sleeps on `#42`, not yet the long-run result.
Of the 180 corrected-series reported RTC intervals, 178 were 61-68 s and two
were 6 s and 7 s. The corresponding kernel journal entries show suspend entry
to exit of about 60 s in both cases (cycles 65 and 136), so the short values
do not establish early wakes. The discrepancy in the runner's RTC measurement
is under investigation; keep the raw records and do not count those two as
verified RTC-duration measurements.
The initial timing-summary command compared numeric strings lexicographically
and incorrectly reported zero intervals under 55 s; its numeric conversion
was fixed before recording these counts.

**A candidate to distinguish, not yet a fix.** In the generic core,
`ufshcd_link_startup()` deliberately performs a second link startup when the
device is not yet active, unless `UFSHCD_QUIRK_PERFORM_LINK_STARTUP_ONCE` is
set. On every recorded good S1-T wake, the first command succeeded, then a
second attempt returned the locked-attribute/pre-change failure and link
startup failure, and a host reset plus retry succeeded. If a dead wake's
preserved trace has the same initial success but fails all later retries, the
extra startup/reset is a concrete candidate: a separate test of the existing
one-startup quirk would isolate it. Do not assume the quirk is safe merely
because the first command succeeds; the core's second startup exists to bring
an inactive device to active state, and a clean series and storage checks are
required.
The second PRE_CHANGE also repeats zumapro's PCS lane programming before it
reaches the locked `T_PEERDEVICEID` write; the generic core then proceeds to
the second link-startup command even though that callback returned an error.
Avoiding this repeated programming is another observable effect of the quirk,
but its contribution to the rare failure is not established.
An independently submitted [upstream UFS driver patch](https://lkml.iu.edu/2611.0/07046.html)
uses the same quirk where PRE_CHANGE would repeat PHY initialization on an
established link. This is precedent for the mechanism, not evidence about
zumapro's particular failure.

If the WFI-only runs qualify that mitigation, the removed package hook is
available in commit `f8eab50` along with its package test. Its original
comment and commit message rely on the disproved early-wake interpretation;
they must not be reused as the rationale. Recheck state restoration, partial
failure handling and power cost before considering the hook for shipping.
The 302 mA asleep versus 311 mA awake comparison in S1-W above is not a
matched measurement of WFI against core power-down and cannot establish that
the workaround has no power cost. Use the planned like-for-like measurement.
The palmtop runs systemd `262.1-1-arch`. The corresponding
[upstream systemd 262.1 sleep code](https://github.com/systemd/systemd/blob/v262.1/src/sleep/sleep.c)
ignores system-sleep hook errors before entering sleep, so a failed cpuidle
write cannot by itself enforce WFI-only operation. Check any distribution
patches and design and test a fail-closed path before relying on such a hook.
One candidate design is a `sleep.target` prerequisite ordered before the
target, with a oneshot start that verifies every state and restores any
partially changed states on failure, plus a stop action after resume. Check
the actual unit dependency and stop ordering, failed-start cleanup, repeated
sleeps and CPU hotplug with tests before claiming it prevents unsafe sleep.
Another candidate may avoid the CPU-hotplug and state-restoration race:
the 7.3 kernel's `cpu_wakeup_latency_qos_limit()` bounds s2idle state
selection, and `/dev/cpu_wakeup_latency` supplies that limit while its file
descriptor stays open. A zero limit should exclude the nonzero-latency C2
state, and closing the descriptor removes that request while leaving other
clients' constraints in force. The kernel's `Documentation/admin-guide/pm/cpuidle.rst`
also says the wakeup limit affects normal CPU idle while it is held, so the
service must release it promptly after resume.
`CONFIG_PM_QOS_CPU_SYSTEM_WAKEUP` is **off** in the running diagnostic and
initial clean build configs,
so this path is not present or tested on the palmtop yet. If pursued, enable
it in a separate build, verify the device and the state counters with one
guarded sleep first, then measure and qualify it. A fail-closed sleep-target
prerequisite must keep the descriptor open through suspend and report ready
only after its write succeeds. `/dev/cpu_dma_latency` is a different QoS
interface and does not supply this s2idle limit.
An uninstalled helper and notify-type unit draft are in
(a local scratch directory, not in the repository). A local test confirmed the descriptor survives
`exec`, and that missing-device and bad-readback paths do not signal ready.
That test caught an initial bug: Bash's `<>` can create a missing regular
file, so the draft now verifies a character device both before and after the
open. `systemd-analyze verify` accepted the draft unit with a temporary
executable path. This is not a test of the kernel QoS interface or of unit
ordering. The [systemd unit documentation](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html)
also says `Requires=` alone does not propagate a required service's clean
spontaneous exit. The uninstalled draft therefore includes a `BindsTo=` plus
`After=` drop-in on `sleep.target`; an isolated parser check found no ordering
error. Two temporary user services with a fake device confirmed real systemd
notification, descriptor retention and that `BindsTo=` stops a dependent
service when the helper exits spontaneously. A second disposable three-unit
test on systemd `262.1-1-arch` modeled the helper, sleep target and suspend
service (including the real service's `Requires=` dependency): a missing
device prevented the parent from starting, spontaneous
helper exit stopped the parent, and stopping the parent caused the target and
helper to stop. A oneshot parent that exited normally also released both,
matching the suspend service's lifecycle more closely. The temporary units
and links were removed afterwards. This
checks unit lifecycle with a fake device, not actual s2idle or the kernel QoS.
The test-only `qos-snapshot.sh` in that draft directory is also prepared;
fixtures verified that it rejects changes to either idle counter, a missing
online CPU, a changed online set and a nonzero QoS reading.
An independent config in (a local scratch directory, not in the repository) differs from
the clean-source build only by enabling that option. A low-priority `W=1`
Image/DTB/modules build has started with `LOCALVERSION=-s2mpg15-m1-qos1`,
giving it a different module release from the unmodified-config build. It is
untested; do not boot it without a matching, verified daily-restore path.
For a first QoS test, use temporary runtime units with a rollback reboot and
the existing UFS guard. Verify the character device exists and its baseline
constraint is nonzero, then verify a held zero request reads back zero and
closing it restores the baseline; if another client changes the constraint,
mark the check inconclusive. Leave
the CPUs' C2 `disable` values at their original enabled values, record each
`state1/usage` and `state1/s2idle/usage` counter, and perform one RTC-woken
suspend through systemd. For an unambiguous interval, use test-only
`ExecStartPost` and `ExecStop` snapshots: both run while the helper still
holds the zero request, before sleep and after wake respectively. The normal
usage counter matters as well as the s2idle counter because the kernel can
fall back to a regular idle entry. Pass only if the helper activated and
stopped, neither C2 counter grew between snapshots, storage stays readable
and the request is released after wake.
Stop on missing readiness, unexpected state or UFS error. A series on this
mechanism must use the same checks each wake; the current WFI script disables
C2 directly and therefore cannot establish that QoS did the work.
The candidate patch is staged at
(a local scratch directory, not in the repository): it adds the existing
quirk to zumapro's driver data only. The integration tree's original host
source was backed up before applying it for a `W=1` comparison build; it has
not been run on the palmtop. Checkpatch found no code-style issues (the
standalone patch has no commit description). The `W=1` incremental Image build
passed without warning lines; its sha256 is
`3cda0b2deb579ca45d2275c3b2eff36a79aec79795e76c6aab1e935cc49774dc`.
The build log shows `ufs-exynos.o` and the kernel version objects rebuilt,
followed by relinking; it did not rebuild other driver objects. The running
baseline remains the earlier `#42` Image.

**S1-T3, compare the one-startup candidate (prepared, not run).** After S1-T2
has ended and its result has been saved, pack `#43` with the same descriptor,
DTB, initramfs and module archive as `#42`; verify two packs and confirm only
`boot.img` differs. Risk medium, rollback the verified daily kit. Keep the
same `spm_lvl` 5, WFI-only setting, 60 s RTC alarm, services and stop rules.
The isolated kit is staged at (a local scratch directory, not in the repository): both packs
matched, and only `boot.img` differs from the `#42` pack.
On a clean boot and the first wake, check that the trace shows one successful
startup, that the root filesystem is read-write, and that ordinary storage
reads succeed. Stop on a boot failure, unexpected UFS error or missing wake;
preserve pstore and restore the daily kit. Then compare at least 300 completed
sleep cycles with S1-T2, recording early wakes, UFS errors, pstore and the
exact kernel release. A clean comparison supports the workaround; it does not
alone identify the electrical cause or qualify core power-down.
If neither arm reproduces the rare failure, the comparison can establish
whether the repeated failed startup disappears and bound the observed failure
rate; it cannot establish that the rare dead-storage cause was fixed.

Before marking suspend as working, remove the temporary trace and panic,
rebuild from citable published or proposed source, and qualify that actual
build over a long series plus RTC and physical power-key wakes. Include a
longer RTC-timed sleep as well as the repeated short cycles, and adjust the
observation-loss timer for that deliberate sleep duration. The current
integration tree has additional uncommitted UFS and device changes, so a
result on `#43` alone does not establish that a clean source branch produces
the same kernel. Identify its prerequisites without modifying another
session's kernel branches.
Read-only source audit (2026-11-04): UFS prerequisites [#57](https://github.com/derekross/linux-omarchy-mobile/pull/57)
and [#99](https://github.com/derekross/linux-omarchy-mobile/pull/99) are merged
to `omamobile`. At published kernel commit
`0a6f97a2eb5bf12f860e4c551c5bf4f8c4f3cb89`, the zumapro descriptor already
has the clock-stop ordering and suspend callback; its initialization enables
the same clock-gating capabilities as the diagnostic tree. The published
driver differs in other platform organization, so this source comparison does
not replace testing a build from the published base.
An independent shallow clone of that exact published commit is prepared on
maclab's omb at (a local scratch directory, not in the repository); it has a separate object
store and does not use the other session's branches, worktrees or output.
The candidate flag is staged there on the new local branch
`omamobile-tegu-suspend`; checkpatch reports zero errors and warnings. It is
uncommitted and awaits the comparison and a full clean-build test. With a
copy of the integration config and `olddefconfig`, a separate output directory
(a local scratch directory, not in the repository) compiled `drivers/ufs/host/ufs-exynos.o`
using `ARCH=arm64 LLVM=-21 W=1` without warnings.
The full low-priority `W=1` Image/DTB/modules build completed successfully;
`zumapro-tegu.dtb` is present and the Image SHA-256 is
`59704ad15da869c408523a37935f5e40c516a9c4599dc138da76a43ec4780ecf`.
The full log contains 1,155 warning lines in unchanged files, mostly clang
initializer-override warnings; this is not a warning-free full kernel build.
The changed UFS driver compiled separately without warnings. This build is
untested and must not be confused with the running diagnostic kernel.
Its current release string is `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g0a6f97a2eb5b-dirty`,
different from the diagnostic builds. The prepared daily restore script only
accepts `#41`-`#43` on the old release. Before booting any clean-source build,
prepare and verify a daily restore preflight for its exact final release and
matching modules, then pack and check the images. Committing the candidate
will itself change the release string, so rebuild and recheck it afterwards.

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

### S1-T2 interrupted; S1-T3 comparison and module audit (2026-11-04)

The WFI-only `#42` run recorded 211 successful wakes in two consecutive
series (23 plus 188). The next sleep had an entry but no recorded exit before
an external reset. Firmware reported `PIN_RESET`; the available logs do not
establish what caused that reset or whether the pending RTC wake would have
succeeded. The captured console and previous journal contain no UFS failure
or kernel panic before it. The intended 300-cycle baseline was interrupted,
not passed. The private journal and archived pstore were saved locally.

The `#43` comparison, with the one-startup quirk and otherwise the same kit,
booted with a writable root. Its first RTC-woken sleep passed: the trace showed
one successful UFS startup instead of the baseline's successful startup,
failed redundant startup and recovered retry. A guarded 300-cycle series is
under way. At the last recorded check, 13 cycles had passed with no UFS error;
subsequent traces also showed only successful first startups. A temporary
watcher holds sleep after the run ends to permit evidence capture. No
conclusion about the rare dead-storage failure is warranted yet.

An offline QoS-enabled clean-source build passed `W=1` and a repeat make, but
is **not safe to push as staged**. The live module directory contains ten
added modules and ten modified module files compared with its original archive,
including device-specific display and USB drivers that the clean build does
not all supply. All twenty added or changed modules report the currently
running release in their vermagic. The clean-build launcher is blocked. A
full backup of the live module directory and verification of its file hashes
are required before any test kernel is pushed.

To investigate a test that retains those modules, a separate output build
from the authorized integration source changes only
`CONFIG_PM_QOS_CPU_SYSTEM_WAKEUP=n` to `y` and retains the current kernel
release. The kernel uses no module version CRCs, so a matching release and
module vermagic are necessary but do not prove binary compatibility. Its two
UFS source files match those saved for `#43`; verify the remaining kernel
build and the live module backup before a boot. This QoS build remains
unbooted and cannot establish a fix until the runtime constraint, CPU-state
counters, repeated sleeps, longer sleeps and physical wake are tested.

The prior `#42` journal showed console suspension during all 211 completed
wakes. The `#43` boot also initially had `console_suspend=Y`, risking loss of
resume evidence before consoles normally resume. Continuous console capture
was enabled after approximately 43 completed comparison cycles; the journal
has a timestamped marker. The remaining part of the series is therefore a
different test condition. Count the two segments separately, and extend the
continuous-capture segment to 300 completed cycles before claiming a
300-cycle result under that condition.

### RTC read inconsistency (2026-11-04, investigation)

The comparison runner records uptime around each RTC read. In its first 66
cycles, 10 of 65 consecutive inter-cycle gaps disagreed with uptime by more
than two seconds: nine by about -5 seconds and one by about +55 seconds. One
RTC start read repeated the preceding cycle's end value about five seconds
later; another read was about 55 seconds ahead of the uptime-consistent time.
All 66 measured cycle spans were 60.97–62.95 seconds by uptime, so these
records do not establish an early or late alarm. The value `elapsed_rtc=7s`
for one cycle is therefore not evidence that the palmtop woke after seven
seconds.

The integration `s5m_rtc_read_time()` sets the RTC read-update bit and reads
the time buffer immediately. Google's GPL S2MPG14 driver at
[057ab18a9cc0](https://android.googlesource.com/kernel/google-modules/soc/gs/+/057ab18a9cc0e318538b419eafc565a7fbe1d320/drivers/rtc/rtc-s2mpg14.c)
clears the update bit, waits 50–51 microseconds, sets it, and waits about one
millisecond before reading. This device-specific difference is a plausible
explanation for stale or mixed reads; it has not been tested as a fix, and no
connection to the silent no-wake is proven. `rtcwake` uses an RTC reading to
calculate its relative alarm, so verify the separate read used to program an
alarm before deciding whether these anomalies affect its timing. Before any
PMIC/RTC hardware test, verify protected partitions against the off-repository
backup. Use driver interfaces, never raw userspace PMIC register access, and
leave the active UFS comparison undisturbed.

The off-repository backup's local image copies match their SHA-256 manifest;
the phone-to-backup check is still pending until the series ends. The
installed `rtcwake` is util-linux 2.42.4. Its [tagged source](https://github.com/util-linux/util-linux/blob/v2.42.4/sys-utils/rtcwake.c)
reads the RTC to calculate a relative alarm; its dry-run path skips alarm
programming and cancellation but still invokes the RTC read operation. The
current runner reads the RTC once just before invoking `rtcwake`, which may
prime a delayed refresh and mask an unreliable first read. Check that
hypothesis after the live backup check, without a preceding RTC read, and do
not infer an alarm failure from the separate recorded value alone.

**S1-once result (2026-11-04, diagnostic kernel #43): failed after one
separate preflight and 99 completed long-series wakes.** On the next wake the first UFS link startup failed on
all four retries and on five host reset attempts. The diagnostic panic
captured the failure in the persistent console before reboot; the previous
journal stopped earlier. Eliminating the redundant startup is therefore not
sufficient. The phone rebooted with root read-write and the evidence was saved
privately; the 300-cycle target did not pass. The full installed module
folder was separately saved and verified (1,798 module files). The live
protected-partition check against the post-Android backup passed.

An awake RTC dry-run baseline without a preceding RTC read then showed
system-minus-RTC deltas of -1 s twice, 0 s fifteen times, 4 s once, 5 s five
times and 9 s once (24 readings). This reproduces stale readings through the
ordinary driver, but does not prove an alarm failure or cause for a silent
no-wake. A subsequent first ten-alarm awake run accidentally used `rtcwake
-m show` before each alarm; that command also reads RTC time, so it primed
the next read and must not be treated as an unprimed baseline. A corrected
awake test uses the `wakealarm` status interface, whose `rtc_read_alarm`
reads the framework's timer state without calling the time-read operation.

An isolated, unbooted RTC-only candidate for S2MPG14 pulses the read-update
bit and waits using the vendor timing. The W=1 RTC object and strict
checkpatch pass; full W=1 kernel build is underway. It does not claim to fix
UFS. A separate, unbuilt UFS hypothesis retains the device reset and PHY
through a system hibern8 transition so the requested hibern8 exit can work;
it needs its own careful power, clock, error-path and hardware tests. Do not
combine the two changes in their first experiments.

**A real relative alarm was programmed late (2026-11-05 UTC).** In an awake
`rtcwake -m no -s 15` test using the same alarm mode as the suspend runner,
the first alarm fired after 15.65 s of uptime. On the next attempt, the RTC
read used for programming was 55 s ahead of system time: the process read
00:35:56 at system 00:35:01 and set the alarm for 00:36:12, about 71 s away.
It remained armed after 30 s and was canceled by the test; its actual firing
time was not observed. Uptime shows only 20.66 s between the two attempts,
which is inconsistent with the RTC advancing 76 s under a stable clock.
This establishes an incorrect alarm calculation and a missed 30 s deadline;
it does not by itself explain a multi-minute no-wake or UFS restore failure.
The remote test failed correctly but its local wrapper incorrectly printed a
completion line; the private log and saved hash are authoritative. A corrected
runner now propagates exit status and waits up to 90 s to observe a late alarm.

**Early delivery reproduced:** the corrected awake real-alarm test failed on
sample 8 after seven normal samples. The RTC read was five seconds stale
(00:39:51 at system 00:39:56), and its requested 15-second alarm fired after
11.12 s of uptime. This confirms that stale reads affect actual alarm timing;
the earlier future RTC read's alarm was canceled after 30 seconds rather than
observed to fire. Neither result establishes the cause of the UFS restore
failure, and the RTC candidate has not yet been tested.

The published kernel already pulses RUDR and waits for its shadow copy on
S2MPG10. This older diagnostic kernel predates that change, and the published
code does not apply the workaround to S2MPG14. Extending the existing path
is a small production candidate; at that point the private draft passed
`git apply --check` and strict checkpatch but had not been built or tested.
Its existing 50–100 us
first delay differs slightly from #44's 50–51 us, so qualify the production
form itself rather than assuming the diagnostic result transfers unchanged.

**Published RTC draft rechecked (2026-11-07).** The current published kernel
tip `29a7a9326bf0` still limits the RUDR clear-and-wait sequence to S2MPG10;
S2MPG14 uses the same register layout but does not receive those waits. Its
RTC source matches the earlier draft's base, and the earlier production
candidate is byte-identical to the candidate rebuilt against this tip. The
patch applies cleanly and passes strict checkpatch. A fixture compiling the
actual candidate read function checks both supported paths, unchanged other
devices and the clear, set and read error exits. On maclab, the published
baseline and patched RTC object both built with `W=1` and no diagnostics.
The full `W=1` Image, DTB and modules build subsequently succeeded in the
isolated (a local scratch directory, not in the repository); the source was still at published
tip with only `rtc-s5m.c` modified. The Image SHA256 is
`11e1d4dd8f4cb32ae66dea8e7477cbd1595d7276811c8c5c34b45429fd50d3f5`.
The build log has 1,155 warning lines, including 1,138 initializer overrides
(946 in generated syscall tables); no error lines were found. The independently compared RTC object
had no diagnostics. The output remains marked do not boot: production timing
is untested on the palmtop, and this change alone does not solve the separate
UFS resume failure.

**RTC candidate and independent hibern8 trial (2026-11-05 UTC).** The
RTC-only diagnostic kernel `#44`, `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`,
returned zero system-minus-RTC delta in 24 unprimed dry reads and delivered
20 real awake 15-second relative alarms in 15.43–16.10 s. One guarded,
WFI-only s2idle with UFS `spm_lvl=5` then woke after a 61 s RTC interval;
its NFC pre-sleep log was confirmed, no UFS or kernel-fault pattern was
observed, and idle settings were restored. These results support the RTC
workaround but do not qualify the production form or the whole sleep path.

After returning to #43 and verifying its boot, installed modules and
protected-partition backup, an independently built #45 changed only the UFS
host hibern8 handling and added a test-only panic on hibern8-exit failure.
The candidate boot and its checks passed. A single WFI-only hibern8 sleep
was then armed with a 60 s RTC alarm, storage-error guards and an evidence
watcher. The USB link stopped responding and had not recovered after several
minutes. The #45 kernel does not contain the RTC fix, so the available
observations do not distinguish an incorrect alarm from another wake failure;
the hibern8 change has not passed. The host log shows no storage error before
the link went quiet. A normal Power wake was requested to preserve the
on-device evidence; no further device state should be assumed until recovered.

The published-tree UFS host draft applies cleanly, passes strict checkpatch,
and compiles with `W=1` without warnings; unlike #45 it contains no diagnostic
panic. This is build evidence only. A separate combined RTC and UFS test build
and a second output with `CONFIG_PM_QOS_CPU_SYSTEM_WAKEUP=y` are in progress;
qualify each change in the appropriate guarded hardware test. The wakeup-QoS
option also affects generic power-domain and regular idle decisions while held,
so measure its power cost and test its complete service lifecycle before use.

**Correction after the Power wake request.** The #45 test had already
completed one hibern8 cycle: 62.02 s elapsed by uptime, followed by a UFS
system resume from hibern8 and no new full link startup. Its NFC pre-sleep
record was confirmed, no storage or kernel-fault patterns were found, and
the phone remained on the same boot with root read-write. The unpatched RTC
snapshots differed by 93 s over that interval; the alarm was no longer armed.
A single cycle is not a reliability result. The SSH attempt near the expected
wake timed out, but no later attempts were made before the Power press, so it
is unknown when USB networking recovered or whether the press caused it. Host
logs show USB re-enumeration about a minute after suspend disconnected it.

**Twenty-cycle follow-up.** The same #45 boot then completed 20/20 further
WFI-only, `spm_lvl=3`, 60 s RTC-woken hibern8 cycles, with each NFC
stop-polling record confirmed. The service's elapsed-uptime intervals were
61.27–61.98 s. Across the single and 20-cycle tests, the kernel journal shows
21 system resumes from hibern8 and only the original boot-time full-link
startup; no matching UFS or kernel-fault patterns were found. This supports
the retention hypothesis but does not establish 300-cycle reliability,
proper power use, or a fix for the separate C2 no-wake problem.

**Combined candidate, first wake (2026-11-05 UTC).** The #46 diagnostic
kernel combines the isolated S2MPG14 RTC workaround with the separately
tested zumapro UFS hibern8 retention change. Its configuration and release
match the existing diagnostic kernel, its 417 required custom-module symbols
match, and its existing installed module directory was preserved. The source,
W=1 warning comparison, two image packs, five slot-B readbacks, protected
backup and post-boot smoke checks passed. One guarded, WFI-only, `spm_lvl=3`
cycle then passed: 61.43 s elapsed by uptime and 61 s by RTC, with one
confirmed NFC stop and one hibern8 resume, no post-boot full-link startup,
and no detected storage or kernel-fault patterns. This single cycle is not
a reliability or battery result. The test-only panic on hibern8-exit failure
is present in #46 and must not be included in production code.

The guarded 300-cycle follow-up failed as recorded below. The #47 test build adds only
`CONFIG_PM_QOS_CPU_SYSTEM_WAKEUP=y` and is staged but unbooted: the wakeup
QoS service still needs separate on-device tests with CPU C2 enabled,
snapshot and failure checks, and a power comparison. The published-tree
production draft excludes the diagnostic panic and remains unqualified.

### Combined RTC and hibern8 candidate: long run failed (2026-11-04)

The #46 diagnostic kernel combined the RTC read-update experiment with the
zumapro UFS hibern8-retention experiment. Its one-cycle preflight passed,
but the following 300-cycle run did not: after three completed long-run
suspends, the fourth long-run wake failed. The UFS `DME_HIBER_EXIT`
power-control command returned status 5. The diagnostic
kernel panicked deliberately and preserved the failure in the persistent
console. Thus retaining the PHY and deasserting reset is insufficient, and
neither this hibern8 candidate nor the production draft based on it is ready
to ship. The RTC change remains separately supported by its earlier awake
alarm tests and has not been cleared as the cause of this storage failure.

The phone recovered into the same diagnostic kernel. The archived console,
previous journals, NFC log and host log were saved privately; the protected
partition backup checksum passed again on the current boot. An awake inhibitor
holds the phone while the failure is investigated. The persistent console
shows the preflight plus three long-run suspend exits before the failed exit;
USB re-enumerations alone were not a pass count. The later boot reported an
APC watchdog; it followed the captured diagnostic panic and an additional boot,
so it must not be substituted for the directly captured UFS failure.

**Next PHY experiment (prepared, not yet tested).** Google's GPL zuma UFS
[calibration](https://android.googlesource.com/kernel/google-modules/soc/gs/+/refs/tags/android-16.0.0_r0.0/drivers/ufs/zuma/ufs-cal.h) has nonempty Hibern8 entry and exit sequences, including a 10 us
wait, but the older integration kernel used for #46 has no Tensor G4
Hibern8 table. The current published kernel already has this table and the
10 us wait. Google runs the entry sequence before gating the host's internal
clocks; both the older integration and current published host gate first.
The isolated #49 diagnostic adds the table to its older base and changes the
order for `google,zumapro-ufs`. The vendor's squelch writes are limited to
connected RX lanes; this phone reports two active RX lanes and the host driver
allows at most two available lanes. Any general-purpose version must retain
the distinction for other devices. A source comparison found only the four
intended UFS/PHY files changed from #46; strict checkpatch and W=1 object
compiles passed, and the full W=1 build is in progress. This is a hypothesis,
not a proven fix, and the diagnostic-only panic must not ship.

**#49 first hardware test (2026-11-05 UTC).** The experimental kernel built
with `W=1`; the source differed from #46 only in the intended four UFS/PHY
files, its config and release were unchanged, strict checkpatch passed, and
all 417 required module symbols matched. The five slot-B images were written
and read back, and the subsequent boot passed protected-partition, installed
module and smoke checks. It ran awake for over two minutes under a UFS-error
guard without a detected fault. One guarded WFI-only hibern8 wake then passed:
61.70 s by uptime, 61 s by RTC, one NFC pre-sleep confirmation, one system
resume from hibern8 and no post-boot full link startup. This remains a single
sample; the PHY hypothesis and separate C2 wake problem are not yet solved.

A 300-cycle guarded follow-up is running with the same kernel and WFI-only
setting. It syncs the service journal and NFC log after each cycle, and a
post-test inhibitor preserves ordinary failure or success evidence. Host USB
re-enumerations are only a passive activity signal, not a pass count.

**Production module inventory.** The separate published-tree build completed,
but its module index supplies only 91 of the 102 module names observed on the
running development phone; eleven remain unresolved. Name matches alone do
not prove ABI or behavior. The currently installed modules and the separately
loaded bring-up modules have private verified backups, but a production
migration still needs the missing module sources, compatible rebuilds and a
verified recovery path. The build contains the published Hibern8 table but
has not been tested with the #49 host clock-gating order, so it is not a
production candidate.

The eleven missing development modules' recorded build directories were
located from the backed-up modules' debug metadata. Each directory contains
its source and dependency record, and each saved build-directory `.ko`
matched the backed-up binary by SHA-256; timestamps are consistent with the
source and local headers predating the binary. These checks do not prove the
source alone reproduces it. Ten unmodified source copies compiled with `W=1`
against the production-source build. The remaining audio activation helper
expected the development kernel's reset-array field; an isolated adaptation
uses the production driver's single-reset field and explicitly requires one
reset GPIO, and also compiles with `W=1`. All eleven resulting module names
and vermagic match the production build, with no warnings in their successful
build logs. None was installed or exercised; compilation and vermagic do not
establish ABI or hardware behavior, and the underlying production UFS draft
remains unqualified.

For a stronger provenance check, unmodified copies of all eleven recorded
sources were also rebuilt against the development integration kernel. Each
rebuilt `.ko` matched its backed-up counterpart byte for byte after removing
debug sections and `.note.gnu.build-id`; all eleven builds succeeded. This
supports the recorded source/build match without asserting that the
production-source rebuilds behave correctly on hardware.
The other 91 observed module names each map to exactly one production build
output, and all 91 report the production kernel release; their declared module
dependencies are present in that build or in the recovered source set. This
is an inventory check, not a device test or proof that drivers and firmware
will behave the same after migration.

A subsequent build-ID audit found that the installed module archive matches
86 of the 102 captured loaded module IDs. Thirteen names did not resolve to
an installed path, and three loaded modules (`aoc_core`, `aoc_char_dev` and
`brcmfmac`) had a different build ID from the same-named installed file.
The separately archived bring-up modules contain build-ID matches for all 16,
so the two verified archives together cover all 102 captured loaded IDs.
This matters for migration: a same-named production module is not evidence
that it contains the development module's changes, particularly for AoC and
Wi-Fi. Compare those sources and test their behavior before replacing them.
The saved build-directory binaries for the three differing variants also
match their backed-up loaded build IDs and hashes. A read-only comparison of
their recorded source directories with the published tree found six changed
and two missing AoC source/header files, plus three changed Wi-Fi source
files. The changes include substantial AoC and PCIe differences; reconciling
and qualifying them is a separate prerequisite for a production migration.
Isolated copies of the saved AoC and Wi-Fi variant sources also compile with
`W=1` against the production-source kernel, with their declared dependencies
available. Against the development kernel, the rebuilt AoC core matched its
saved binary after debug/build-ID removal. The AoC character and Wi-Fi modules
had matching executable-section bytes and relocation listings, but their full
non-debug files differed; their read-only data includes different embedded
kernel-source paths, and the remaining differences have not been fully
explained. These are offline comparisons, not evidence of correct device
behavior, and no module has been installed.

**The longer #49 Hibern8 run failed (2026-11-05 UTC).** The independent
journal and NFC audit found 91 completed cycles of the planned 300, in
addition to the earlier single-cycle preflight. The next sleep reached the
RTC wake and the UFS system resume from Hibern8; its Hibern8-exit command
returned UPMCRS `0x5`, followed by the diagnostic-only panic and reboot.
The previously captured kernel journal ends before the failure, but the
archived persistent console contains it. Therefore the calibration table and
clock-gating order together did not make this Hibern8 path reliable, and the
current published-source draft must not be shipped as a fix on this evidence.
After the reboot, the protected-partition backup and installed module manifest
matched, and the read-only smoke test passed.

A one-cycle comparison on the same diagnostic kernel with `spm_lvl=5` used
link-off and a full link startup instead. It passed in 61.91 s by uptime and
62 s by RTC, with one NFC confirmation and one successful post-boot link
startup. A 40-cycle comparison is running; one wake is not a reliability or
battery result. An active-link (`spm_lvl=0`) candidate also needs its own
kernel guard: in the current G4 host callback, even an active link would
otherwise reach the device-reset write during system suspend. The untested
diagnostic draft skips that reset only for an active system-suspend link.

One more difference warrants observation. Google's
[UFS host driver](https://android.googlesource.com/kernel/google-modules/soc/gs/+/refs/tags/android-16.0.0_r0.0/drivers/ufs/ufs-exynos.c)
clears the PHY APB automatic-stop enable before running calibration; this
host's clock-stop mask does not include that bit. A separate, untested
diagnostic logs the relevant bits from values the driver already reads,
without adding an MMIO read or changing clock policy. That distinction is a
hypothesis, not an established cause, and logging can itself alter timing.

A separate RTC-only draft on the published kernel at `0a6f97a2e` extends the
existing S2MPG10 read-update sequence to S2MPG14. It passes strict checkpatch
and a warning-enabled build of the changed RTC object; a full build is in
progress. This published-source version uses a 50–100 µs clear interval,
while the tested integration diagnostic used 50–51 µs. It has not been run on
the phone. The production kernel's loaded-module variants and the RTC change
both need device testing before treating it as a replacement for the current
diagnostic kernel.

**Forty link-off comparisons passed (2026-11-05 UTC).** The #49 diagnostic
completed all 40 WFI-only RTC wakes at `spm_lvl=5`: the service's ordered
suspend-success counters and the RTC/uptime intervals agree; all 40 have an
NFC pre-sleep confirmation, one system resume from link-off, one successful
full link startup and one suspend exit. No checked UFS or kernel fault was
reported. A guarded 300-cycle run of the same configuration has started.
These are diagnostic results; they do not establish the cause of the previous
silent no-wake or measure battery consumption, and #49 is not a release kernel.

The 40/40 result does not qualify an arbitrary normal sleep with NFC polling
on: the diagnostic refuses to sleep unless neard reports `Polling=false`.
The packaged NFC hook attempts to stop polling, but systemd 262.1 ignores
sleep-hook failures and the hook logs failures while returning success. A
production solution must either demonstrate an independently enforced NFC
precondition or make preparation fail closed, including an explicit policy for
an absent or unresponsive neard, restoration after an aborted sleep, and a
check for a new poll between preparation and suspend. The diagnostic has not
tested that normal-use path.

An offline NFC guard draft addresses the known case where the ST54L is still
polling at sleep entry. The I2C system-suspend callback checks the NFC core's
polling flag under its device lock and returns `-EBUSY` on the 9a if polling
remains active. In the examined kernel, userspace is frozen before device
suspend callbacks, and the NFC core's poll-start path takes that same lock.
The draft passes strict checkpatch and a warning-enabled module build. The
saved NFC transport's recorded source and header reproduce its executable
code and non-debug relocations; the draft module uses that recorded header.
This is only a proposed guard: the lock ordering, failed-stop/controller
state, suspend-abort behavior, NFC restoration and actual hardware still
need testing. A kernel polling flag alone cannot prove the controller stopped.
The NFC core's `nfc_stop_poll()` calls the driver's void `stop_poll` operation
and then clears its logical polling flag. NCI's implementation discards the
`nci_request()` return, and an error response can also set its state to idle.
Consequently, the proposed polling-flag guard cannot detect every failed
controller deactivation. Its scope is a guard against an explicitly active
core poll, not a complete fail-closed NFC solution; a reliable error path or
independent controller-state evidence is still needed.

A separate draft retains NCI RF start/stop request errors until a successful
stop or reinitialization and has the 9a ST54L suspend guard reject polling,
a non-idle active NCI state or a retained error. Both changed objects and a
matched NCI/transport module pair build without warnings; a mocked test of
the actual functions covers request failures and recovery. DWARF shows all
48 pre-existing NCI member offsets unchanged, though the structure grows.
The installed NCI module was reproduced using the integration commit's
original notification source, which differs from that checkout's uncommitted
logging change. This draft is uninstalled: its complete ABI, lock ordering,
error recovery and behavior on the controller remain untested, and a sticky
error could prevent sleep until NFC is reinitialized. It is not evidence
that every possible controller failure is detected.

The offline published-branch RTC candidate’s tegu DTB is byte-identical to
its production baseline (SHA-256 `87777ee4e9ac3028f7a2c828fdfdf0de9fc85f90ed982a2be7d263aae3fc4f1c`).
`dt-validate` (dtschema 2026.9) against the candidate bindings emitted no
diagnostics. This does not qualify the candidate for a device boot.

**The link-off comparison did not qualify (2026-11-05, diagnostic #49).**
The 300-cycle WFI-only run completed 102 cycles, each confirmed by the
NFC record, ordered suspend counters, RTC/uptime agreement and UFS link-off
resume/startup evidence. On the next wake, the saved persistent console
records `lane 0 calibration timed out`, repeated failed UFS link startups
and the diagnostic `UFS restore failed 1` panic. The phone returned to slot B;
the protected backup and module manifest matched, and required smoke checks
passed with additional NFC, pinctrl and overlay messages flagged for review.
The calibration timeout preceded the failure; its underlying cause is still
unknown. Link-off and WFI alone are not a reliable mitigation.

**Active-link preflight failed (2026-11-05, diagnostic #51).** The
first WFI-only `spm_lvl=0` wake reached UFS resume with link and device active,
but the host reported a generic PHY-adapter LINERESET and recovery could not
complete its device commands. The storage guard reset the phone; no cycle
passed. Slot B booted again, protected backup and installed modules matched,
and required smoke checks passed. A backlight restore unit was briefly
failed on the prior boot; no units were failed on the post-reset smoke check.
Active-link suspend is not a demonstrated mitigation.
### PHY timeout on every recorded link-off wake (2026-11-05)

Re-auditing the link-off journal changed the interpretation of the earlier
passes: all 143 completed `spm_lvl=5`, WFI-only wakes in the previous-boot
kernel journal each logged one `phy poweron failed --> -110` after a lane 0
calibration timeout, yet also logged a successful subsequent link startup and
completed resume. The separate one-cycle and 40-cycle captures show the same
pattern; they overlap the 143, rather than adding independent cycles. Thus
completed resumes do not establish a clean PHY power-on, and the fatal next
wake is not the first occurrence of this timeout. The earlier 102/300 and
40/40 counts remain accurate as counts of completed wakes with their checked
RTC, NFC and link-startup evidence, but must not be presented as clean PHY
calibrations.

Source review found that `samsung_ufs_phy_calibrate()` advances its state even
when the wait-for-calibration callback returns an error. Consequently an
immediate retry of `phy_power_on()` can skip `CFG_PRE_INIT` calibration and
return success without retrying calibration. The staged retry build `#57` is
therefore **not safe to test as a calibration retry**. Keep the state at the
failed stage, test the provider and caller together, and rebuild before a
guarded trial. Even then the cause of the systematic timeout and whether any
retry can recover it remain unproven.
### Failed genuine PHY retries reveal an APB clock difference (2026-11-05)

The corrected `#58` diagnostic kernel preserved the failed calibration stage
and retried link-off PHY power-on up to three times; it contained no earlier
test-only panic paths. One WFI-only 60-second RTC test reached its scheduled
wake, but all three lane-0 calibration attempts returned `-ETIMEDOUT` and the
UFS workload-resume callback returned `-110`. The storage-error guard then
reset the phone. It is a failed single cycle, not a 300-cycle pass. The
persistent console, journals and NFC record were saved privately. On reboot,
both sleep masks remained active, the protected-partition backup and installed
module manifest matched, and the checksum-verified daily `#7` images were
restored. The modem and sleep daemon returned to their original running states,
and protected checksums matched again after modem start.

Immediately before the failed calibration, the powered UFS host reported
`HCI_MISC=0xd10` and `HCI_CLKSTOP_CTRL=0`. Bit 10 in `HCI_MISC` enables PHY
APB clock auto-gating. Google's GPL host driver clears that bit and bit 5
around its PHY calibration call; bit 5 was already clear in this observation.
This supports a scoped next experiment that clears bit 10 during the resume
power-on/calibration sequence and restores its previous value afterward while
preserving unrelated bits. It does not prove that auto-gating caused the
timeout, that the hardware honors the control as expected, or that a successful
calibration fixes the other C2 wake issue. A fixture compiled from the actual
provider and host callbacks checks the temporary bit change, restoration on
success and failure, unrelated bit preservation, retries, and the non-target
paths; physical testing remains necessary.
### PHY APB auto-gate experiment did not fix calibration (2026-11-05)

`#59` kept the #58 calibration-state fix and retry/error behavior, and
temporarily cleared HCI_MISC bit 10 around link-off system-resume PHY power-on.
Its strict checkpatch and W=1 baseline passed after a clean no-op repeat: the
first incremental link reported a 0.14-second VM clock-skew warning, and the
repeat reported none and produced the identical Image. Its 417 required
custom-module symbols and saved non-boot images matched.

The single WFI-only 60-second RTC wake failed. The pstore console recorded
`misc=0xd10`, readback `forced=0x910`, all three lane-0 calibration attempts
timing out, and `restored=0xd10` before WL resume returned `-110`; the
storage guard reset the phone after userspace thawed. The bit write and
restoration therefore took effect in the observed register, but are not
sufficient to make calibration complete. No 300-cycle series was attempted.
Evidence is saved privately under `phy-apb-retry-one-unexpected-reboot/`.
The protected backup and module manifest matched after the reset. Daily #7 was
restored and verified, both sleep targets remain masked, the original sleep
daemon and modem service are active again, and the protected backup matched
again after modem start. Continue with the calibration sequence and PHY/host
state analysis; do not claim this gate change as a fix.
### Deferred PHY initialization: one clean wake, endurance running (2026-11-05)

The `#60` diagnostic kernel tests whether the link-off resume was calibrating
too early. For zumapro system link-off resume it checks that the suspended
PHY has one initialization reference and no power reference, balances that
initialization with `phy_exit()`, and leaves PHY initialization to the existing
pre-link path after the UFS host reset. A test-only UFS-core guard stops if
that pre-link callback fails instead of issuing link startup anyway. The #58
provider fix keeps its calibration state unchanged on errors. The #59 APB
auto-gate experiment is not included. Strict checkpatch, W=1 warning baseline,
source/image checks and the 417-symbol inventory passed. Fixtures compiled
from the real callbacks model three balanced cycles and check that a failed
pre-link never sends UIC startup; these do not substitute for hardware tests.

One WFI-only, `spm_lvl=5`, 60-second RTC-woken sleep completed without a PHY
power-on timeout. The preserved kernel log shows `phy-resume-defer: init=1
power=0`, `phy-deferred-prelink: result=0 init=1 power=1`, successful link
startup and suspend exit in that order. NFC was confirmed stopped; RTC and
uptime agreed (62 s and 61.85 s). The test cleanup restored the sleep masks
and the sleep daemon. Private evidence is in a local scratch directory (not in the repository).

After this independent single-wake audit, a guarded 300-cycle WFI-only series
was launched at 60 seconds per RTC alarm. Every cycle checks for a fresh,
balanced deferred PHY initialization, successful link startup, no storage
errors, NFC pre-hook confirmation, the uptime interval and unchanged C2
counters; it also records RTC readings for independent audit. A seven-hour
fallback and an exit cleanup close the temporary sleep
gate; the original persistent masks remain in place on reboot. Until the
series and its separate evidence audit complete, this is one clean wake, not
a 300-cycle pass or a complete fix for normal C2-enabled sleep.

### Deferred PHY initialization: fourth endurance wake failed (2026-11-05)

The #60 WFI-only link-off endurance series completed **3 of 300** verified
cycles. The fourth wake rebooted. The private previous-boot journal and pstore
console are preserved under `deferred-series-unexpected-reboot/`, with their
checksums. This supersedes the running status above. Pstore shows that on the
fourth wake deferred PHY initialization returned success with balanced
references, but the subsequent DME link startup returned `1` on all retries;
host reset and restore failed repeatedly and WL resume failed. The following
bootloader log reports an early application-processor watchdog reboot. The
saved evidence does not prove what first caused the link startup failure or
whether the watchdog was triggered by the storage guard; do not conflate a
successful calibration with a recovered link. A count of three excludes the
separate preflight wake.

After the reboot the protected partition backup and installed module manifest
matched, and a read-only smoke test passed. The previously verified daily #7
images were then written to slot B with checksums and the palmtop rebooted;
the protected backup, installed modules and smoke checks passed again after
the daily boot. The original sleep daemon and modem service are active, and
the protected backup matched once more after modem start. Sleep targets remain
masked while this is investigated.

### Test: de-isolate before host reset, calibrate after it (2026-11-05)

The fourth #60 wake gave a successful PHY callback but repeated link-startup
failures. A source comparison shows a sequencing difference worth testing:
Google's host resume disables PHY isolation before HCE host/device reset, and
its link-startup pre-change callback calibrates after the reset. #60 kept PHY
isolation on until the pre-link callback. This is a hypothesis, not proof of
the cause of the failed link.

The test-only #62 kernel uses a private diagnostic notification to power and
de-isolate the zumapro PHY during system link-off resume without calibrating;
it calibrates at pre-link without toggling PHY isolation again, repeats that
calibration on link retries, and clears its diagnostic state only after a
successful post-link callback. The Samsung callback rejects a different
Samsung PHY variant, but the generic PHY API returns success when the callback
is absent, so the diagnostic does not reject every mismatched provider.
This modifies the generic notification enum and examines PHY reference counts
without the generic PHY lock: it is not a proposed production interface.
Modeled fixtures compile the actual callbacks and exercise powered-before-reset
ordering, three balanced cycles, calibration failure, retry, wrong provider,
unsafe reference counts and non-target Hibern8. Strict checkpatch and W=1
passed against the baseline; the unchanged module requirements matched all
417 audited symbols. No diagnostic panic strings are present in the staged
Image. The source, debug symbols, image and build logs are archived with
checksums on the isolated omb suspend tree.

The phone booted #62 with protected backup, module manifest and read-only
smoke checks passing. One guarded WFI-only RTC wake passed: 60.69 s by uptime
and 61 s by RTC, with NFC polling stopped and one correctly ordered PHY
pre-reset power observation, a zero-return pre-link PHY calibration call and
link startup. Private
logs and checksums are under `phy-isolation-retry-one/`. The first independent
NFC audit failed because its START timestamp had subsecond precision while the
NFC pre-sleep record had only whole seconds; both occurred in the same second.
A corrected, fixture-tested audit accepts that boundary and requires exactly
one safe record; the test runner also checks the hook's new log bytes. Both
the initial and corrected audit results are preserved.

A guarded 300-cycle WFI-only series was subsequently started with a seven-hour
fallback. The host monitors USB without sending traffic. Passive USB activity
is not a verified pass count. An independent per-cycle kernel audit will reject
any hidden failed startup or retry even if the runner later sees a successful
one. The single clean wake and ongoing series say nothing yet about normal
C2-enabled sleep, power-button wake or power consumption.

**NFC guard lock-order finding.** The draft suspend callback cannot safely
solve the queued-RX race merely by flushing the NCI RX workqueue while
holding `nfc_dev->dev.mutex`. The RX worker dispatches notifications, and
`nfc_tm_activated()` and `nfc_targets_found()` both acquire that mutex; the
flush could wait for a worker waiting for the caller's lock. Moreover, NCI
registers the RX queue with `create_singlethread_workqueue()`, so it is not
established that system-sleep's freezing of freezable workqueues serializes
that worker against the device callback. A safe design must specify the order
of IRQ quiescing, workqueue draining, locking, state inspection and re-enabling
on both an aborted suspend and resume; it also needs evidence about controller
notifications arriving after a successful RF-deactivate response. Do not add
an in-lock flush or treat `nfc->polling == false` as controller proof.

**C2 restriction detail.** On this kernel, removing a deep state's
`enter_s2idle` callback alone is not a WFI guarantee. `cpuidle_idle_call()`
first tries `cpuidle_enter_s2idle()` but, when that chooses no deep state,
falls back to `cpuidle_find_deepest_state()` with the same wake-latency
limit and can enter an ordinary idle callback. Any WFI-only design must
exclude C2 from both selection paths; the QoS candidate's zero system-wakeup
latency is intended to do that but still needs both usage counters checked
on real hardware. A userspace QoS holder also has a possible exit/start race;
the systemd lifecycle fixtures do not prove an atomic guarantee through
kernel suspend entry.

**QoS follow-up build (prepared, not booted).** The diagnostic #63 Image uses
exactly the #62 sources and configuration except for
`CONFIG_PM_QOS_CPU_SYSTEM_WAKEUP=y`. The full W=1 build completed with no new
warning lines against the baseline, its 417 audited custom-module symbols
match, and the staged boot image and unchanged non-boot images were packed
twice and checked. Debug symbols, source and build logs are saved with hashes
on omb. This build is not a fix and has not been put on the phone.
A fixture compiled from the actual `find_deepest_state()` implementation
confirms that a zero limit selects state 0 in both s2idle and ordinary-idle
fallback, whereas merely removing a state's s2idle callback does not. The
actual QoS interface, helper lifecycle through a real freeze, C2 counters,
physical wake, repeated sleeps and battery use remain untested.

A possible power-off alternative also needs lock-order work before it is a
safe replacement. In this tree `nfc_dev_down()` holds the NFC device mutex
while calling `nci_dev_down()`, and `nci_close_device()` eventually flushes
`rx_wq`. Some notification handlers in that queue acquire the same device
mutex through `nfc_targets_found()` or `nfc_tm_activated()`. This creates a
potential wait cycle when such work is queued during device-down; no device
test here establishes that it occurred. In addition `nfc_dev_down()` ignores
its driver's return value. Do not treat a reported `Powered=false` as a
complete controller or lock-order proof, and do not make the optional
power-off hook mandatory without resolving and testing these paths.

**A possible in-kernel wakeup-QoS lease (offline design only).** The
userspace QoS helper's held file descriptor can be closed if that helper dies
between its readiness notification and the actual system sleep, so its unit
ordering alone is not a proof that C2 stays excluded. The investigated kernel
has `cpu_wakeup_latency_qos_limit()` and a userspace request implementation,
but no public in-kernel add/update/remove interface for that constraint. If a
C2 restriction proves necessary, one possible follow-up is an upstream-style
in-kernel request API and a narrowly matched platform PM notifier that holds a
zero-latency request from `PM_SUSPEND_PREPARE` through `PM_POST_SUSPEND`.
The kernel source shows the prepare notifier runs before the process freezer;
normal completion calls post after thaw, and the robust notifier call and
freezer failure path perform their own post cleanup. The robust chain calls post only for the notifiers before the one that
failed, in chain order, so a failing notifier must undo its own partial work.
The design would need to handle repeated and failed requests,
preserve other clients' constraints, be unavailable when the QoS config is
disabled rather than silently degrade, and prove the request remains active
through every tested suspend path. Holding the constraint may affect ordinary
idle during preparation and recovery. This is not implemented, built or
hardware-tested, and it does not establish that C2 caused any no-wake or that
its restriction is an acceptable power policy.

The NCI data-exchange timer can also queue `rx_work` independently of the
transport interrupt (`nci_data_timer()`), and the close path documents that
RX work can acquire the request lock via `nci_deactivate_target()`. Therefore
masking the I2C interrupt and flushing the workqueue is not by itself proof
that no later RX work can run; a correct quiescence design must account for
all producers and pending requests, and avoid waiting on controller responses
whose interrupt it has disabled. No such IRQ or workqueue change has been
made or tested.

**Isolated calibration-state correction on published source (offline).** The
published Samsung UFS PHY calibration routine advances its state even when a
lane's calibration or lock wait returns an error. If the caller retries, the
next call can therefore select the next stage instead of retrying the failed
one. A three-line draft against published `0a6f97a2eb5b` keeps the state on
error while retaining the existing successful and absent-table behavior. A
fixture compiling the actual published provider with the diagnostic retry
callback rejects the unpatched source and passes with the draft, including
timeout/retry and post-power lock failure. The isolated provider-only worktree is
(a local scratch directory, not in the repository); its separate output is
(a local scratch directory, not in the repository). Strict checkpatch and
its `W=1` changed-object build pass without diagnostics. This is an
independently reviewable error-handling fix, not proof of the UFS resume root
cause; it has not been tested alone on the phone, and is not a release kernel.
The running #62 diagnostic also contains this state correction along with
other changes, so its results cannot isolate the correction's contribution.

**Independent timing audit added while #62 runs.** The on-device runner
records both RTC and uptime intervals but only rejects an out-of-range uptime;
the previous description of it as checking RTC agreement was too strong.
The host collector now independently checks all ordered cycle records for
RTC arithmetic, RTC/uptime agreement, plausible 60-second intervals and a
single increment of the suspend-success counter. It saves raw checksummed
evidence before any audit. The C2 follow-up refuses to arm unless this audit,
the NFC audit and kernel sequence audit all pass, and its own collector also
runs the timing audit. A synthetic 300-cycle collector fixture passes the
good case and rejects incorrect RTC, skipped success counters, a failed link
startup and a missing NFC record; a separate timing fixture covers malformed,
out-of-order and incomplete records. No phone-side test was restarted or
changed for this correction. USB wake hints remain observations, not passes.

**Next C2 endurance stage (prepared, not started).** If the current 300 WFI
cycles pass all independent audits and the separately gated one-cycle C2 test
also passes NFC, timing, kernel and C2 audits on the same boot, a further
300-cycle C2-enabled RTC series can be run with the same NFC and storage
checks, per-cycle C2-entry counters, a seven-hour on-device fallback, sleep
gate and daemon-lease cleanup. Its install gate checks the single-wake evidence
hashes, repeats the four audits, verifies the boot and the exact runner hash,
and stops the single-test fallback before staging the longer one. Its unit
keeps the `x-suspend-pstore2` name because the existing UFS guard explicitly
monitors that unit; a journal cursor distinguishes the runs. The host USB
monitor accepts a recorded new monotonic start so hints for this series do not
include earlier wakes. Lifecycle and collector fixtures check fallback and
cleanup ordering, stale boot IDs, bad RTC, missing C2, missing NFC and link
errors. This plan is not evidence of a C2 pass. A hard freeze prevents the
on-device fallback from executing; if USB remains absent, stop sending phone
commands and continue offline until the owner can recover it. Even a clean
C2 series would not independently qualify a physical power-key wake, normal
use with the modem, NFC polling during sleep or sleep power consumption.

The prepared C2 runner records an eight-element per-CPU delta as well as the
aggregate C2 entries for each cycle. Its independent audit checks that the
eight values sum to the recorded total and reports accumulated per-CPU counts;
a positive aggregate alone does not prove every core was exercised. This
runner and its audits have only fixture coverage and have not been installed
on the phone.


**WFI endurance failure and recovery (2026-11-05).** The #62 diagnostic
rebooted during the 90th wake of its guarded 300-cycle series, after 89
runner-recorded passes. These counts are not yet independently audited; USB
enumerations alone are not passes. Saved pstore shows PHY de-isolation and
a zero-return pre-link PHY calibration call, followed by repeated DME link startup
failures and host reset attempts that did not recover the UFS link. Thus the
#62 combination, including PHY de-isolation before host reset and the
calibration-state correction described above, did not eliminate this failure.
Its longer run than earlier failures does not establish an improvement.

The logs, pstore and checksum manifest were captured privately before restoring
the previously known daily #7 kernel through verified slot-B push. The protected
partition backup check, module manifest and phone smoke test passed after the
reboot and after the daily-kernel return; the protected check passed again
after restoring the modem service. The recorded sleep-daemon and modem service
states were restored. Sleep and suspend remain masked. The temporary awake
and UFS reboot guards were later stopped before the owner used the palmtop.
The planned C2 stages are blocked by the failed WFI gate; neither #62 nor the
provider-only draft is a qualified suspend fix.


**Partial-series audit (2026-11-05).** The preserved monotonic journal was
retrieved from the diagnostic boot and added to the private checksum manifest.
Independent checks found 89 ordered cycles with matching RTC and uptime
intervals, successive suspend-success counters, one reported stopped-NFC
record each and the expected PHY and UFS startup sequence. The 90th attempt
has a suspend entry without a journaled exit; pstore shows its UFS startup
failure. The NFC check confirms the logged software state, not independent
proof of controller quiescence. These checks do not qualify the failed series.


### Local UniPro pre-link access experiment (prepared 2026-11-05)

The #62 pstore record reports a zero-return pre-link PHY calibration call before
its link startup returned result 1. The saved console contains 84 earlier
successful startups whose pre-link-to-result log intervals are 23.070–23.212
ms, versus 104.996–105.341 ms for 20 failed retries. Result 1 is returned by
the completed UIC command; the core's completion timeout is 500 ms and would
return `-ETIMEDOUT`. This distinguishes a controller-reported failure from a
Linux completion timeout, but does not identify whether host or device first
failed. The console is a ring and these 84 do not include the earliest wakes.
A burst of 166 Wi-Fi firmware channel-warning lines fell between the pre-link
and result logs for the first failure, whereas no such lines appeared in that
interval for its 19 later failed retries or the 84 retained successes. The
same 166 warnings also appear in each of the 84 complete post-wake windows
following successful suspends, after the suspend-exit log and before the next
entry. Their overlap with the first failure is therefore not a unique Wi-Fi
notification; the longer failed startup changes the timing window. This is
log correlation, not proof for or against a Wi-Fi-related state change.

Google's GPL `zuma/ufs-cal.h` writes five local UniPro attributes through the
host's mapped register window before PHY calibration. The diagnostic driver
programs the same values through DME_SET commands instead. A narrowly scoped
follow-up based on #62 writes those five attributes through the mapped window
only in its existing deferred system-resume path; initial boot and other paths
retain DME_SET. Both EVT tables were checked against its values, offsets and
order; the offsets fit the 0x8000-byte UniPro resource. These are kernel
accesses in the existing pre-link path after host clock ungating, not userspace
register reads. A fixture compiling the modified callback verifies scope,
order, invalid lanes and earlier errors; strict checkpatch passes with the
commit-message/sign-off checks omitted for the unsigned diagnostic. An
independent audit fixture rejects missing, duplicate and failed startup events.

This is a diagnostic hypothesis: #62 already reported that its pre-link
callback succeeded on the failed wake, so the difference does not prove that
the five accesses caused the failure. A separate #64 source and output are
being built on maclab; there is no hardware result yet. Keep the one-cycle,
endurance, NFC and C2 gates separate, and preserve the verified daily rollback.

**#64 runbook (prepared; no hardware test yet).** Risk: medium; a UFS or
SoC hang may require the palmtop's recovery buttons. Slot B has a verified
daily image set, and protected partitions stay under the storage guard. Stop
on any failed check, unexpected boot, new storage error, missing USB, unsafe
NFC state or missing trace; preserve journals and pstore before any retry.

1. Complete the isolated W=1 `Image dtbs modules` build. Check the #62
   source baseline, #64 source and Image hashes, configuration and release,
   new warnings, trace strings, unchanged custom-module symbol inventory and
   reproducible image packing with `stage-direct-mib.sh`. Expect all checks
   to pass. Rollback: no phone state has changed; discard only our draft build.
2. Verify the protected backup and current boot, kernel, modules, modem and
   sleep masks. Start a laptop kernel-log stream and a phone awake guard;
   record the original modem and sleep-daemon state before disabling the
   modem for the diagnostic boot. Use `push-direct-mib-retry.sh`, which writes
   and verifies only the permitted slot-B images and reboots. Expect #64 and
   the same modules. If its boot cannot be reached, do not guess at the
   device's state. Rollback once reachable: the checksum-verified daily kit
   with `restore-daily-from-direct-mib-guarded.sh`.
3. `verify-direct-mib-boot.sh` checks the diagnostic boot, protected backup,
   modules and smoke test before clearing its boot marker. Confirm the screen
   and NFC have reached stopped-polling state, install the checked boot-local
   helpers, arm the UFS/kmsg guards, sleep gate and five-minute cleanup, and
   run one 60-second WFI-only RTC wake with `arm-direct-mib-one.sh`. The
   collector saves raw checksummed evidence before independently checking
   NFC log, RTC/uptime, exactly one direct-write marker, PHY ordering and
   first-attempt link success. Expect all checks to pass. Rollback: restore
   the daily kit and recorded daemon states; on a failed wake capture pstore
   and journals before restoring. A single pass is not an endurance result.
4. Only after that independent single-wake audit, prepare a separately gated
   long WFI series and verify every cycle. Keep C2, physical power-key wake,
   normal modem operation, NFC controller quiescence and sleep power as
   independent unresolved qualifications. Even a 300-cycle pass would be
   evidence for this experiment, not proof the suspend bug is gone.

**Further pre-link observation (source only).** `exynos_ufs_pre_link()` calls
`exynos_ufs_config_unipro()` before its platform callback and PHY calibration.
For zumapro that function writes the GS101 option-suite 1 and 2 values with
`ufshcd_dme_set()`, but does not check either return value. Google's GPL host
source programs the same named suite values through its local UniPro window
before its calibration call. #62's successful `phy-deferred-prelink` trace
therefore does not report whether these two DME commands succeeded; #64 does
not change or instrument them. The exact diagnostic core logs failed DME_SET
commands as errors, and the saved #62 failure console contains no such error;
that is useful negative evidence, subject to the console ring's coverage. If
the present experiment fails, checking those return values and the vendor
mapping is a separate possible diagnostic, not evidence that the suite
settings caused the failure.

**#64 first wake and endurance in progress (2026-11-05).** The isolated
`W=1` build passed its baseline-warning, release, config and source audits;
the candidate matched all 417 required installed-module symbols. Offline image
packing was reproducible and the non-boot images matched the daily rollback.
After the authorized slot-B push, the boot, protected backup, installed modules
and phone smoke checks passed. One guarded 60-second WFI-only cycle passed
independent NFC software-log, RTC/uptime, suspend-counter, first-attempt
link-startup and ordered direct-write/PHY trace audits. A separate guarded
300-cycle run has now started, with a seven-hour cleanup timer; its outcome
is not yet known. The modem remains held off for the diagnostic and the
previous service states are recorded for restoration.

**Interrupted endurance run and harness correction (2026-11-05).** The first
#64 300-cycle run was stopped by the earlier single-cycle five-minute fallback
during wake 5. Four cycles have runner PASS records and matching NFC software
records; the fifth had a pre-sleep NFC record but no recorded PASS. The phone
remained reachable on the same boot, with sleep masked and the evidence awake
guard active. The original logs and checksums are in the private
`direct-mib-series-early-timer` evidence directory. This was a harness stop,
not a qualified 300-cycle result and not evidence of a storage failure.

The preparation now stops and checks the single-cycle timer, and the long-run
arm explicitly refuses an active one. Additional negated shell preconditions
were changed to explicit failure branches because Bash `set -e` does not stop
after a failed top-level `!` command. Retry preparation verifies the old
evidence, same boot, masks, storage, NFC state and boot-local helper hashes;
transfers the awake guard before retiring the old one; and records a fresh
journal cursor. Collector fixtures require that cursor so the previous partial
run cannot be mistaken for the retry. Negative fixtures cover a live old
timer, a running modem or test service, failed timer stop, bad checksums, bad
boot ID, bad cursor, bad RTC/NFC/link evidence and a missing direct trace.
After those checks, the corrected 300-cycle run was started from zero. Its
outcome remains unknown. Its seven-hour `OnActiveSec` fallback uses systemd's
monotonic clock, which can pause across suspend: it is not a guaranteed
seven-hour wall-clock deadline, and it cannot recover a hard freeze. The host
observer and RTC cycle records remain the independent progress checks.

**C2 runner draft (offline only).** A separate #64 C2-enabled runner was
prepared from the earlier C2 runner plus the direct-UniPro trace check. Its
fixtures reject a disabled or unobserved C2 state, invalid timing or alarm,
unsafe or missing NFC confirmation, storage errors, missing PHY ordering and
missing direct-programming traces. It has not been installed and is not a
C2 test result. #64-specific launcher and collector drafts now pass fixtures
for incomplete or altered WFI evidence, active old timers, wrong boot, missing
C2/NFC/direct-write evidence, RTC errors and storage faults. A separate
300-cycle C2 draft also checks the single-C2 evidence and removes its
five-minute timer before arming a seven-hour fallback; its launch, collection
and reboot-evidence fixtures pass. These scripts remain offline: the
independent 300-cycle WFI gate and review of actual captured evidence remain
prerequisites before staging or running them.

**Elapsed-time backstop draft (offline only).** A small separate guard using
`CLOCK_BOOTTIME` was drafted and tested with simulated service state and clock
progress. Unlike `OnActiveSec`, it would count suspended time without setting
another RTC wake alarm; it could request the test service to stop on a later
normal wake. A disposable host user-systemd service also stopped at a short
elapsed deadline and ran its `ExecStopPost` cleanup; that test did not suspend
the host. The guard cannot recover a hard freeze. It is not installed or wired
into any run; its behavior through real suspend, scheduling overhead and
interaction with the phone cleanup and failure paths still need review.

**PHY callback qualification (source review).** In the exact #64 generic PHY
core, `phy_notify_state()` and `phy_calibrate()` return zero when the relevant
callback is absent. The trace proves those calls returned zero, not by itself
that a provider executed either operation. The built #64 config includes the
Samsung UFS PHY, and the staged device tree names the zumapro PHY, but the
live binding and host-to-PHY reference have not yet been captured for this
boot. The exact built source wires a nonempty zumapro pre-init table and a
calibration-wait callback. In the staged base DTB, the host's `phys` phandle
matches the zumapro PHY node and its PHY cell count is zero; overlays and live
binding still need confirmation. A read-only sysfs/device-tree checker and
negative fixtures are prepared for verification after the WFI run; both C2
staging gates require it.
This is also a production-interface constraint: any design that depends on
notification or calibration must positively establish provider support.


### #64 direct-UniPro endurance failure (2026-11-05)

The corrected 300-cycle WFI-only run recorded 66 ordered passes with matching
NFC software stop records before a 67th attempt. The preserved console shows
that attempt woke, de-isolated the PHY, performed the direct UniPro writes
and received a zero return from the pre-link PHY call, then the link startup
returned 1 repeatedly and host reset did not recover it. The following boot's
bootloader log reports APC Watchdog Early. The 300-cycle run failed; this is
not evidence that the direct writes fixed suspend. The live host-to-PHY device
tree reference and Samsung zumapro PHY binding were separately verified via
read-only sysfs. The NFC log records a software state, not independent proof
that the controller was electrically quiescent.

Previous and current journals, persistent console, the captured run cursor,
and protected-backup and module checks are private under
`logs/tegu-suspend-trace-20261104/direct-mib-series-unexpected-reboot/`.
The phone returned to the checksum-verified daily #7 kernel. The protected
backup and installed module manifest matched, the required smoke test passed,
and the recorded modem and sleep daemon states were restored; the protected
backup matched again after modem start. Sleep and suspend remain masked.
C2 qualification remains blocked. The next candidate needs a new hypothesis
and an independent gated test, rather than repeating this failed sequence.

**Calibration wait timing hypothesis (source comparison).** Google's zuma
calibration loop waits 40 microseconds *before* its first read of each lane's
completion bit; its driver installs the `udelay` callback. The #64 Samsung
PHY uses `readl_poll_timeout()` with a 40-microsecond interval, whose first
read is immediate. This is a real ordering difference; neither source proves
that the bit is stale or that the delay fixes the failed startup. Google's
Linux path also returns success after exhausting that wait, so this experiment
retains the stricter timeout error instead of copying that behavior.

A test-only #65 source draft adds only a 40-microsecond delay before the
existing per-lane poll. A fixture compiles the modified callback and checks
both lane addresses, delay-before-read ordering, and success/error return
propagation. The separate W=1 kernel build is underway; it is not yet a device
result. Before any deployment, verify the build, unchanged source/config,
warning baseline, installed-module ABI and independently packed rollback.
First run a single guarded RTC wake with the modem held off and NFC stop
confirmed; stop and preserve the console on any failure. A separate gated
endurance run is required afterward. Restore the daily kernel, modem and sleep
daemon on completion or failure. Sleep stays masked outside the test.

The watchdog-reboot kernel journal records the ext4 root mounted read-write;
it contains no ext4 recovery, orphan or error message. This is a journal
observation, not an offline filesystem check. The 66 completed cycles also
passed independent RTC/uptime and successive-counter checks.

The strict style check reports the expected `USLEEP_RANGE` check for the
40-us `udelay`; this test uses the same busy wait as Google's driver to keep
the timing comparison narrow. With that check and the unsigned-draft commit
message warning explicitly ignored, checkpatch reports no other findings.
The separately fetched current upstream PHY also takes its first poll
immediately. The #65 source tree comparison against #64 found only the delay
and its include. These checks do not constitute a hardware result.

**Unattended recovery budget draft (offline only).** A boot-bound reservation
draft is in the separate suspend worktree at
`device/tegu/bringup/sleep-recovery-budget-draft`. It records a reservation
on persistent storage before a test, refuses duplicate arms, refuses active
tests, open sleep gates and existing UFS/kernel faults, and only releases the
reservation on the same boot after the test has stopped cleanly with both
gates masked. A reset leaves it in place and blocks another reservation.
Fixtures cover these conditions, including a changed boot. It is not installed
or integrated with any runner, and does not implement a nightly time window or
a post-reset review procedure. An in-tree UFS recovery guard draft requires
the same-boot reservation and has fixtures for storage faults, retry limits,
oopses and missing or stale reservations. Before issuing SysRq it also creates
a boot-local marker that prevents a same-boot clean-up from releasing the
reservation after recovery was attempted. Neither draft has been installed or
hardware-tested; the time cap, post-reset review, guard liveness and runner
integration must be validated before an unattended endurance run.

A disposable host user-systemd fixture confirmed that an `ExecStopPost`
cleanup can stop a test service when a guard service fails. This validates a
service-lifecycle pattern only; the real guard, its interaction with the
phone's system manager and suspend, and the complete runner are untested.

The #65 post-reset recovery draft also saves the root ext4 boot-journal lines,
requires the root to be mounted read-write, rejects matching filesystem error
lines and checks that the boot did not change during the backup, module and
smoke reviews. Its read-only filesystem check passed against the present daily
boot. It is not an offline filesystem repair or a completed reset test.

**#65 build and offline kit (2026-11-06).** The full separate W=1 Image,
devicetree and modules build completed. Source hashes were unchanged during
the build; config, release, version and W=1 warning baseline matched, and the
Image contains the expected diagnostic traces and no test panic. The compiled
PHY callback places `__const_udelay` before the first status load. All 417
required installed-module symbols, including 10 custom exports, matched.
The offline kit packed reproducibly and its non-boot images and module archive
matched the saved baseline. This is build evidence, not a device result.

**#65 initial wakes and endurance (2026-11-06).** The diagnostic boot
passed the protected-backup, module and smoke checks. One 60-second WFI-only
RTC wake passed the NFC software-log, timing, suspend-counter and ordered
PHY/direct-UniPro/first-link-startup audits. After a simulated on-phone guard
failure and a separate supervised one-cycle validation with the new guarded
recovery setup, the second wake passed independent checks too. This is two
wakes, not yet a reliability result. The now-retired single-cycle fallback
was removed before the longer run.

The 300-cycle WFI-only series is running with a fresh journal cursor. Its
boot-local guard scripts match the drafts in the separate suspend worktree;
they require a persistent same-boot recovery reservation, and all three
automatic reset paths first create a boot-local fired marker. A reset leaves
the reservation in place and no test service is automatically rearmed. Each
guard's service cleanup requests that the test stop if the guard exits. This
reservation has no automatic post-reset review or nightly time-window reset;
keep it after any reset, inspect pstore and the ext4 journal and honor the
per-night recovery cap before any further hardware test. The seven-hour
OnActiveSec fallback can pause during suspend and is not a wall-clock bound;
it cannot recover a hard freeze. Host USB transitions are hints only, and
the final counts require independent journal, NFC, timing and kernel audits.
C2, physical-key wake and modem-on suspend remain unqualified.

**Production interface question (source review, not a patch).** #65 retains
the diagnostic-only notification and direct reads of generic PHY reference
counts from #62, so a good series would not make that code release-ready. In
the current published generic PHY core, `phy_configure()` and `phy_validate()`
return `-EOPNOTSUPP` when their callbacks are missing and execute callbacks
under the PHY mutex; `phy_notify_state()` and `phy_calibrate()` instead
silently return success when absent. A typed UFS-specific configuration and
validation interface is one possible way to make a phase transition fail
closed, but it would require an appropriate upstream API, positive provider
identification, balanced host-owned references and explicit cold-boot, retry,
error and Hibern8 semantics. A different provider's unrelated configure
callback must not be mistaken for support. No such interface has been
implemented or shown to fix the hardware.

### Calibration-delay endurance result (2026-11-05)

The #65 WFI-only 300-cycle series did not pass. The service journal records
16 completed cycles, independently audited against their RTC and uptime
intervals, NFC stop-polling records and ordered storage events. Negative
fixtures reject a missing cycle, a failed link startup and unsafe NFC state.
On the next wake the persistent console shows a
zero-return pre-link PHY calibration followed by repeated UFS link-startup
failures and a recovery-triggered reset. The initial 40-us delay therefore
does not by itself fix the observed storage failure in this diagnostic
combination. Successful calibration is not proof of a working link. The
protected-partition checksum check, installed-module manifest, root ext4
boot-journal review and read-only smoke test passed after the reset.
The captured failed wake contains 20 zero-return pre-link callbacks, 20
link-startup results of `1` across five failed host initializations, and then
`sysrq: Resetting`. The callback-to-result intervals were approximately
105 ms. This is a controller-reported failure, not the core's 500-ms UIC
completion timeout; it still does not identify which side of the link failed.

The private evidence, including the captured persistent console and journal
checksums, is in `logs/tegu-suspend-trace-20261104/cal-delay-series-unexpected-reboot/`.
The cross-boot recovery reservation remains in place: preserve it and review
the recovery budget before any further test. Restore the known daily kernel
and leave system suspend blocked while investigating the link failure.

**Offline failure-history diagnostic.** A draft based on #65 prints the UFS
core's existing IRQ-recorded PHY-adapter, data-link and DME event histories
only after the first failed link startup of a zumapro system-resume attempt.
It uses the core's existing history printer and adds no register reads. A
`W=1` build of the changed UFS core object and strict checkpatch (excluding
the unsigned draft's sign-off and commit-message requirements) passed; a
fixture compiling the actual diagnostic condition checked successful startup,
later retries, other devices, non-system resume and the three history types.
Source and isolated output are (a local scratch directory, not in the repository) and
(a local scratch directory, not in the repository) on maclab. The draft has not been
booted, and an empty history would not prove that no hardware error occurred.
History can include earlier events and can change concurrently; compare its
timestamps and counters with the failed attempt, and do not treat an event as
causal solely because it appears in the history. Logging after a failure can
alter retry timing. A subsequent test still needs a reviewed recovery budget,
normal single-wake qualification and a full build and image audit.

**Further source comparison: PCS access path (offline).** Google's
`ufs_cal_pre_link()` uses `init_cfg_evt0/1`, whose `PHY_PCS_COMN`,
`PHY_PCS_RX` and `PHY_PCS_TX` entries are written through the mapped local
UniPro window; for lane-specific entries `__set_pcs()` sets the auxiliary
write strobe and selector, writes the PCS offset, then restores the strobe.
Its table iterates each entry across lanes before moving to the next entry.
The #65 zumapro host instead uses `ufshcd_dme_set()` for those PCS entries,
groups RX and TX writes in lane-major loops and checks their return values.
The previous direct-MIB experiment covered five UniPro entries, not the PCS
entries or Google's auxiliary selector. This difference is a hypothesis,
not evidence that DME writes are wrong or that direct writes would repair the
link. Any diagnostic needs a complete table, lane-selector, clock and ordering
audit against both source versions, bounded access through the driver's
already-mapped and clocked window, and separate failure-path validation before
hardware use. Source references are Google's GPL [host](https://android.googlesource.com/kernel/google-modules/soc/gs/+/refs/tags/android-16.0.0_r0.0/drivers/ufs/ufs-exynos.c),
[table](https://android.googlesource.com/kernel/google-modules/soc/gs/+/refs/tags/android-16.0.0_r0.0/drivers/ufs/zuma/ufs-cal.h)
and [table interpreter](https://android.googlesource.com/kernel/google-modules/soc/gs/+/refs/tags/android-16.0.0_r0.0/drivers/ufs/zuma/ufs-cal-if.c).
An offline source-table audit finds the same pre-PMA table for EVT0 and EVT1
with the vendor source's 38.4-MHz selection, and the same eight RX and seven
TX per-lane PCS attribute IDs as #65. Their per-direction order matches;
the vendor interleaves RX and TX table entries and iterates lanes per entry,
whereas #65 groups directions and iterates entries per lane. Fixtures reject
a changed vendor attribute or selector. This ID comparison does not establish
equal values, effective runtime clock, access equivalence or safe concurrent
use of the auxiliary selector; no direct PCS hardware access is proposed yet.
An additional fixture compiles #65's actual PCS portion and compares the
attribute/selector/value multisets with the vendor table for one and two
lanes at four modeled clock rates; it also checks invalid lane counts and
an injected DME error. Those modeled values match. This does not establish
the running clock, write ordering, concurrent access or equivalence of the
two hardware access paths.
Separately, an offline table audit compared the PMA calibration writes:
both vendor EVT tables have the same 36 ordered common/transceiver entries
as #65, including the lane stride, and expand to the same write sequence for
one or two lanes. Negative fixtures reject an altered vendor value and an
altered PHY address calculation. This comparison does not prove the writes
reached hardware, the calibration-done bit was fresh, or the overall
host/PHY sequence was equivalent; polling behavior is a separate difference.
The published kernel tip checked on 2026-11-05 is `29a7a9326bf0`; its
`drivers/ufs/` and Samsung UFS PHY files have no diff from the previously
reviewed `0a6f97a2eb5b` baseline. That is a source comparison only, not a
test of the published kernel on the palmtop.

**Host clock-control reset question (source comparison).** Google's
`exynos_ufs_init_host()` calls `exynos_ufs_config_host()` after a successful
host software reset, and that configuration clears the enable bit in
`HCI_IOP_ACG_DISABLE` on every host initialization. In #65,
`zumapro_ufs_drv_init()` clears the same bit at driver initialization, while
`exynos_ufs_hce_enable_notify()` does not explicitly reapply it after its
later host resets. Both drivers access the HCI block in their existing host
paths. It is not yet known whether the bit survives a zumapro host reset or
power transition, whether another actor changes it, or whether it has any
bearing on the link failure. A separately scoped kernel diagnostic could
record that one known HCI register after successful host reset during a
deferred system resume, using the normal log stream and watchdog; establish
the clock/power and serialization preconditions and compare successful and
failed wakes before proposing a write. No userspace MMIO probe or hardware
test has been run for this question.

**Separate host core-clock discrepancy (source and prior capture).** Google's
host reset path clears `HCI_CORECLK_STOP_EN` (bit 4 of `HCI_FORCE_HCS`), and
its later `CLK_STOP_CTRL_EN_ALL` mask does not set that bit. The #65 zumapro
host instead explicitly sets the same bit (`HCI_CORECLK_CTRL_EN`) in its
post-HCE callback, because its options do not include the broken-auto-control
flag. A separate earlier #58 failure capture recorded `HCI_MISC=0xd10` before
PHY calibration, with bit 4 set; that is not a direct observation from #65's
failed wake. An offline source-path audit and negative fixtures check the
respective bit definitions, Google reset flow, Google mask and #65's callback.
This differs from the IOP ACG bit discussed above, and from the UFS core's
`clkgate_enable` setting tested in S3. The source and prior observation make
it a candidate for a narrowly scoped test, not proof that it caused the link
failure. Check the reset sequence and preserve all other HCI bits.

A separate offline diagnostic draft samples only `HCI_IOP_ACG_DISABLE` after
a successful host reset on the existing deferred zumapro system-resume path;
it does not write the setting. The actual conditional passed fixtures for a
failed reset, non-deferred and non-system paths, another device and a single
read on the intended path. Its changed host object compiled with `W=1`, and
strict checkpatch passed for the unsigned draft. Maclab source and output are
(a local scratch directory, not in the repository) and
(a local scratch directory, not in the repository). The host reset already accesses
the HCI mapping and Google reads this register in normal initialization, but
neither proves all read side effects or post-reset clock conditions on this
device. This is not yet hardware-qualified; test it separately from the error
history draft, with the normal first-probe and recovery safeguards.
A separate, unbuilt test-only follow-up reapplies the existing probe-time ACG
bit clear after a successful host reset on that same deferred path; an offline
fixture checks the scope and preservation of unrelated bits. Its log records
the value read and the value requested, not a readback. It must not be used
as a fix or tested ahead of the observation and its safety review.

**Rolling recovery allowance (offline draft).** A second budget draft keeps
a root-only, persistent ledger of reservations and permits at most three in
any rolling 24-hour window when the clock reports synchronized. It reserves
an allowance before arming and refunds it only after a clean same-boot
release; a reset leaves both the reservation and its allowance in place.
Fixtures cover the limit, clean refund, a cross-boot refusal, old-window
expiry, clock rollback, unsynchronized time, incomplete records and symlinks.
This is not installed or integrated. In particular, it has no post-reset
review command or migration for the existing pre-ledger reservation, and
wall-clock synchronization alone cannot prove a clock never jumped forward.
The existing reservation stays in place. A separately reviewed migration,
an auditable post-reset review and actual service-lifecycle validation are
needed before this draft can govern another unattended run.
The checksummed persistent-console archive contains nine distinct captured
SysRq resets. A private offline audit estimates their UTC times from nearby
kernel audit timestamps and adds a two-minute margin. For the proposed
three-per-24-hour rule, the latest three captured resets put the earliest
eligible time no earlier than `2026-11-06T15:33:54Z`. This supersedes an
earlier lower bound derived from only three selected captures. The captured
history may omit resets and the clock estimates require review. The audit does
not seed a ledger, clear a reservation or authorize a hardware test.

**UniPro clock-rate lifetime (source comparison).** Google refreshes its
UniPro `clk_get_rate()` in the host configuration that follows each successful
reset; #65 stores the rate in `exynos_ufs_get_clk_info()` during UFS driver
initialization and uses it for pre-link PCS timing later. In the staged tree,
the zumapro UniPro clock is a gate on a user mux fed by an oscillator or a
top-level UFS divider;
the mux and divider are registered read-only, and the gate has no
`CLK_GET_RATE_NOCACHE` flag. In this kernel, `clk_get_rate()` normally returns
the clock framework's cached rate. A different later framework-reported rate
would demonstrate a stale driver value; an equal value would not prove the
hardware's mux or divider stayed unchanged outside the framework. No runtime
rate change or causal link to the observed startup failure has been shown.
The current Exynos UFS host does not set `UFSHCD_CAP_CLK_SCALING`, so the
core's clock-scaling path is not enabled by this driver; this weakens the
case for a framework-driven rate change but does not rule out parent or
firmware changes. A separate diagnostic compares the stored rate with a fresh
framework query after host reset; its actual conditional passed offline
fixtures, its changed UFS host object compiled with `W=1`, and strict
checkpatch passed for the unsigned draft. It has not run on the device.
Maclab source and output are (a local scratch directory, not in the repository) and
(a local scratch directory, not in the repository).
Three saved clock-framework summaries from earlier 2026-11-01 boots report
177.664 MHz for `sclk_unipro_main`; that historical value was added to the
modeled PCS comparison. These snapshots are not measurements from the failed
#65 boot and do not establish whether the clock changes across suspend.
Do not read the clock-controller registers from userspace; any future
measurement needs explicit power, clock and access-safety review.

**Core-clock experiment (offline only).** An isolated #65-based draft clears
only the host core auto-clock bit after a successful host reset, before the
device reset, and omits its usual post-HCE re-enable only for the deferred
zumapro system-resume path. This follows the particular bit's ordering in the
Google source; it does not apply the broader broken-auto-clock option. A
fixture compiles the actual modified HCE callback and bit-mask helper against
mock registers and checks the target, ordering, reset and callback failures,
bit preservation, and unchanged non-target paths. This is a behavioral
experiment, not a demonstrated fix. It has not been run on hardware. It needs
build and ABI checks, a first-probe risk review, and the recovery-history and
reservation review before any device test.

The exact #65 UFS core source was also checked for the experiment's call
sequence: its workload resume marks `pm_op_in_progress`, invokes the variant
resume, and performs host reset and restoration while that flag remains set.
The zumapro variant sets `test_phy_deferred` only for system resume with the
link off, and its link-startup callback clears it after successful post-link.
The ordinary clock-stop mask excludes the core-clock bit. These source facts
support the intended scope, but do not establish the physical register state.
The same core ignores the HCE variant callback's return value in its HCE
initialization flow, even though the Exynos callback can return a host-reset
error. The callback fixture verifies its own returns, not propagation through
the UFS core. No captured host-reset timeout connects that separate error
handling limitation to the observed failure; it needs an independent review.

A second offline reset-history audit uses each post-reboot archive's recorded
time, rather than the earlier estimated reset time, as the upper bound for
that event. It places the lower bound at `2026-11-06T15:34:11Z`, 17 seconds
later than the calculation above, subject to the same unknown completeness,
clock and timezone limitations. Its negative fixtures pass; neither audit
changes the reservation or authorizes a test.
The #69 core-clock draft's changed UFS host object compiled with `W=1` and
strict unsigned-draft checkpatch reported no warnings; a separate full kernel
and module build is in progress on maclab. Passing these checks does not
qualify the experiment for hardware or prove a fix.

**Single-cycle recovery helper correction (offline).** The older
`series-direct-mib-draft.sh` single-cycle runner writes SysRq directly on a
storage fault without first claiming the shared fired marker. The 300-cycle
runner used for #65 has the marker and reservation checks. The offline
single-cycle installer now selects that guarded long runner with `N=1`, instead
of the older runner; do not deploy the older runner. The existing guarded-runner
fixtures pass, and a new disposable concurrent fixture exercises its actual
recovery function: twenty competing calls produce one harmless test write;
stale or symlink reservations and an existing marker prevent a write. This
change is local test preparation only and does not clear the existing
reservation, install a helper or qualify another run.

The separate #66 failure-history diagnostic completed its full `W=1` build.
Its configuration, release, build version, warning baseline, complete exported
symbol table and diagnostic strings passed the build audit. Its offline kit was
packed twice with identical checksums; the non-boot images and module archive
match the reference, and 417 needed custom module symbols match. This kit is
staged only; it has not been booted or tested on hardware.
A separate #69 one-or-more-cycle runner draft uses the shared guarded recovery
path and requires a fresh core-clock request message on each wake, alongside
the existing RTC, NFC, PHY and link checks. Its offline fixtures pass,
including a missing-marker failure. The message records the request, not a
hardware readback. The runner is not installed or authorized by these tests.
The offline #69 runner, its dedicated kmsg guard, its ordered audit, and both
recovery-budget drafts also recognize `timeout host sw-reset` as a fault, so
the ignored HCE callback return cannot silently count as a clean wake.
Disposable fixtures exercise the guard, runner, preflight and audit failure
paths. These modified helpers are not yet installed or integrated.
A #69 single-wake installer and arm draft have now been exercised against a
disposable fake phone. The installer checks the boot ID and selects the #69
runner and kmsg guard; fixtures cover a boot mismatch, missing helper and
transfer failure. The arm fixtures cover guard/fallback order and cleanup on
failure. This is preparation only, not a hardware test or recovery review.

A read-only journal boot inventory provides another cross-check of recovery
history. All nine captured reset archives temporally match journal boot starts,
but the 51 listed starts include 42 that lack one of those nine archives; many
may be ordinary planned reboots, and neither journal nor archive proves the
cause of an unmatched start. The lower-bound time above alone therefore cannot
establish a complete rolling budget. A separate checker matches an archive to
the nearest preceding boot and fails on duplicate or malformed input; its
fixtures cover close boots and ambiguous matches. The private report contains
no boot identifiers. Review the unmatched starts and evidence before seeding
any budget or changing the retained reservation.
An additional read-only comparison of the 24 recent journal boot build numbers
found that 12 of the 14 unmatched starts within the reviewed 24-hour interval
followed a change in build number. In particular the latest four boots report
#7, #65, #65 and #7, matching the recorded candidate push, captured recovery,
and daily restoration sequence. The other two unmatched recent starts retained
their previous build number. Build-number changes support the recorded push
history, but neither equal nor different numbers prove reboot cause or journal
completeness. A separate fixture checks the comparison and rejects malformed,
duplicate or missing entries. The reservation still requires review.
The retained root-only reservation was checked read-only and matches the #65
boot immediately preceding the captured reset. For the three later or nearby
planned swaps, the recorded build transitions (#64 to #7, #7 to #65, and #65
to #7) match host pre-push streams that end in storage shutdown and disconnect
within five seconds of the corresponding journal boot times. A separate
fixture checks missing streams, missing shutdown evidence, wrong build and
time mismatch. This strengthens the recorded push history, but file times and
incomplete logs cannot prove that no other reset occurred.

An offline seed draft combines the nine archived reset times with all other
listed boot starts as possible resets, excluding only the three recent swaps
corroborated by matching build transitions and host streams. Each event uses a
post-reset boot/archive time plus a two-minute margin. It generates a
root-only-formatted ledger in private scratch without touching the phone. Its
fixtures reject duplicate archives, changed push evidence and overwrites; a
disposable integration test runs the actual generated seed through the v2
budget parser and confirms the limit is closed one second before the resulting
`2026-11-06T15:34:11Z` bound. The exclusions, missing-boots possibility and
clock accuracy remain assumptions, and no seed or reservation change is
installed. A separate migration and post-reset review are still required.
The verified seed was regenerated after checking the source archive manifest and
the individual captured-console hashes; it is byte-identical to the earlier
seed. An offline migration draft checks the current boot and old reservation,
installs the ledger and a review receipt without overwriting, and syncs them
before removing the reservation. Disposable failure-path fixtures leave the
reservation in place on unsafe inputs or an interrupted receipt write and
verify that a matching partial migration can be retried. It remains uninstalled:
its external health/evidence review, all possible older reservation entry
points, time-jump defense and service integration are not yet qualified.
A separate offline clock gate records a private host boot/monotonic anchor only
when both host and phone report synchronized time and agree within five seconds.
It requires the original host boot and enough monotonic elapsed time as well as
UTC, with an additional two-minute margin. Fixtures reject a forward wall
clock jump, host reboot, skew, unsynchronized clocks and early passage. The
real check currently refuses; it cannot prove that either clock was correct at
the anchor, and it does not perform migration or authorize a device test.
The v2 budget and migration drafts now require correctly hyphenated boot IDs;
negative fixtures reject malformed IDs. On the restored daily boot, a read-only
inventory found no boot-local `/run/tegu*` test helpers or loaded `x-suspend*`,
`x-tegu*` or `x-phy*` units. A filename inventory of common persistent helper
and unit directories did not find a recovery-budget helper. This is not an
exhaustive proof that no older entry point exists; no migration was performed.
For the traced `DME_LINK_STARTUP` command, the kernel's UFS result definitions
name result `0x01` as generic command failure. The same numeric value is also
used for an invalid attribute in attribute commands, but this trace is a link
startup command and does not identify an invalid attribute or the failing end
of the link.
The #67 IOP ACG observation diagnostic also completed its full `W=1` build and
passed the configuration, warning-baseline, exported-symbol and image-string
audit. Its offline kit passed the 417 custom-symbol check, non-boot image and
module-archive comparisons, and reproducible packing. It has not been booted
or tested on hardware.
The offline #69 single-wake arm now requires the same-boot reservation to match
the most recent root-only rolling-ledger entry, with synchronized time and a
nonfuture, nonstale timestamp. Its installer selects the v2 budget helper and
the #69-specific runner and guard. A disposable integration fixture runs the
actual v2 reserve, the arm/cleanup fixtures, and the same-boot refund against
fake services. This qualifies those simulated paths only; no helper was
installed and the existing device reservation remains unchanged.
The simulated integration also checks that a changed boot or an existing shared
recovery-fired marker blocks both the #69 arm and budget refund.
The offline clock gate additionally rejects a host wall-clock movement more
than ten seconds away from the elapsed monotonic interval since its anchor,
so a synchronized forward jump later cannot silently age out ledger entries.
This gate still requires independent evidence review and is not yet installed
or wired into the phone's budget helper.
Two further older drafts, `start-direct-mib-awake-guard.sh` and
`collect-direct-mib-one.sh`, also contain direct SysRq writes outside the
shared recovery marker; neither is active on the restored phone, and neither
is suitable for reuse. A separate offline #69 one-wake collector contains no
reset command, stops on storage faults or an unreadable log, rechecks the boot
ID after collecting, and checks the new clock-request marker alongside RTC,
NFC, PHY and startup evidence. Fake-phone fixtures cover good evidence,
changed boot, missing markers, timeout/fault, failed log search and bad timing.
It has not been run against the phone.
A #69-specific awake-period guard draft now uses the same boot reservation and
exclusive fired marker as the sleep guards. Its startup requires the latest
same-boot ledger entry, a synchronized clock, an awake inhibitor and a clean
kernel log; the #69 arm and collector require that guard active. Simulated
lifecycle tests cover reserving, starting the awake guard, refusing a refund
while it is active, arming, stopping it and then refunding. These are still
uninstalled drafts, and the earlier direct-SysRq awake helper remains unsafe.
A separate read-only migration preflight draft checks the clock gate both
before and after collecting evidence, verifies that the current boot matches
the captured inventory and the retained reservation matches the recorded failed
boot, and checks the daily kernel, masked sleep targets, stopped guards, pstore,
read-write ext4 root, protected backups, smoke test and kernel fault patterns.
It produces a private checksummed review only on success and does not migrate
or start a test. Fake-phone fixtures reject clock changes, changed boot,
wrong kernel/reservation/state, failed backup/smoke checks, ext4 faults and
failed log search. The actual clock gate is still closed.
A #69 single-wake retirement draft independently rechecks the complete
checksummed evidence manifest, NFC, timing and ordered kernel events before
stopping the awake guard and asking v2 to refund a clean same-boot reservation.
Fake-phone tests reject corrupted or incomplete evidence, a changed boot,
wrong helper, unsafe state and failed guard shutdown or refund. It has not
been run on the device; sleep remains masked throughout this draft path.
A #69 300-cycle path has been prepared offline. Its host preflight re-audits
the single-wake evidence, checks the clock gate, same-boot marker, log stream,
ledger and installed helper hashes, reserves the budget, starts the shared
awake guard, and records a journal cursor before arming. On failure after
reservation it leaves that reservation for review. Simulated services exercise
those failure paths. The independent series collector and retirement drafts
require all 300 WFI-only cycles, NFC/timing and ordered kernel evidence before
refunding a clean reservation; their fake-phone tests cover corrupted evidence,
missing markers, changed boot, and guard/refund failures. None was run on the
device. The series log-stream draft allows nine hours, but a USB/SSH interruption
can still end the stream early and must be monitored, not treated as a pass.
A separate #69 push draft requires the checksummed read-only review, matching
migration receipt and untouched seed ledger, current daily boot, protected
backup and module manifests, active host log stream and clock gate. It retains
slot-B-only push and the boot-pending marker. A fake writer/phone fixture
rejects bad review, receipt, ledger, boot, modules and clock evidence; a late
clock failure restores the temporarily changed modem boot setting. The draft
has not pushed the candidate and the real recovery gate is still closed.
The migration apply draft requires a fresh, checksummed read-only review, the
clock gate before and after staging, the verified seed hash and the same boot;
it verifies the resulting ledger and receipt after the phone-side migration.
Fake-phone tests cover clock failure, stale/tampered review, boot changes,
transfer and migration failures and uncertain post-migration verification.
A post-migration verification failure is left for review, not blindly retried.
This remains unrun on the device.
A separate #69 post-boot verification draft checks the new build, masked sleep,
unchanged recovery ledger, protected backup, module manifest, kernel/filesystem
health and smoke test on the same new boot. It clears the boot marker and
updates the private verified-boot ID only after those checks and a checksum
manifest succeed. Unlike the older helper, it does not start an unbudgeted
awake guard. Fake-phone fixtures cover bad/mismatched boots, backup, modules,
kernel and smoke failures and a failed marker operation. It has not run on the
phone.
The #69 single-wake host preflight draft requires a complete candidate-boot
manifest, matching verified boot, active host stream, unchanged seed ledger,
clock gate and installed helper hashes before reserving the budget and starting
the shared awake guard. It rechecks the clock and boot before arming; failures
after reservation leave it for review. Its fake-phone fixture covers bad
boot evidence, clock/boot/preflight/helper failures, failed reservation or
guard start and failed arm. It has not been run on the phone.
The #69 core-clock candidate completed its full `W=1` kernel and module build.
The build audit found the same configuration, release, warning baseline and
complete exported symbol table as the #65 baseline; expected diagnostic strings
were present. The offline image kit passed all 417 custom-symbol checks,
non-boot image and module archive comparisons, and repeatable packing. It has
not been pushed, booted or tested on hardware.
For a clean #69 run, an offline daily-return draft requires the unchanged
ledger, no outstanding reservation, inactive test guards, a fresh protected
checksum check, matching modules and a live log stream before pushing the
verified daily kit. A separate post-return verifier checks the #7 build,
protected backup, modules, kernel and same boot before clearing boot-pending.
A further unrun service-restoration draft checks the systemd hardware watchdog,
protected backup, same boot and log stream, reserves the rolling budget before
restoring the prior modem/sleepd state, and checks protected data again before
clean release. Fake-phone tests cover bad boot, backup, ledger, watchdog/state,
service and release paths. These are not qualified on hardware and do not
apply to an unreviewed crash recovery.
For the series draft, the phone-side host-log process now writes a private
boot/PID/start-time identity before streaming. A dedicated test service checks
that identity and stops the series if the process exits or changes; its
`ExecStopPost` also requests a series stop if the guard itself exits. Arming
requires the guard, and v2 refuses a refund while it is active. Fake tests cover
missing, stale, reused and unsafe identities and a failed guard launch. A
stalled TCP connection can leave the phone-side process alive even after the
host stream has failed, so the host must still monitor its own stream and must
not treat this guard as proof of continuous delivery.
The host-side draft now snapshots the live stream PID/start time, log inode and
byte offset immediately before arming. A separate watcher reads only newly
appended log data, checks paired suspend entry/exit events and stops watching
on a storage fault, lost/reused stream process, changed/truncated log or lack
of progress. It makes no phone calls; observed exits still require the
independent collector and audit. Disposable tests cover one and 300 paired
exits, faults, stalls, stale PIDs and unsafe logs. A stalled remote TCP process
can still outlive local delivery; on a host watch failure, do not assume the
phone's state or issue repeated commands to an unresponsive device.
A brief awake-device check confirmed that `stdbuf -oL -eL dmesg --follow`
over a fresh SSH stream delivered a newly written, nonidentifying test log
marker promptly. The first short attempt expired during setup and was
inconclusive; the repeated single-session check passed. This does not prove
that USB or SSH will remain connected across suspend.
A short awake-device probe also verified that an SSH-launched, line-buffered
`dmesg --follow` process has the expected same-boot root-owned PID and process
start time; the temporary identity file and process were removed afterward.
This supports the guard's identity assumptions but does not qualify its
behavior during a real suspend or a stalled TCP connection.
The 16 audited #65 series passes correspond to exactly 16 paired kernel
entry/exit events when the stream is measured from the 300-cycle series start;
two earlier single-cycle tests account for the extra events in the wider log.
An unrun independent heartbeat draft now closes the stalled-TCP gap: a phone
reader expects host pulses and requests a series stop on EOF, a malformed
pulse or a 180-second timeout; the host stops sending when the controller exits
or acknowledgements fail. Arming checks a fresh same-boot reader identity.
Disposable fixtures exercise those failures, controller exit, stale identity,
and guard refusal. A short awake-device probe confirmed acknowledgement,
the reader identity check and EOF detection; its temporary files were removed.
A separate phone guard also checks for a missing or stale heartbeat while the
series is active. Its behavior across suspend is still unqualified, and this
safeguard is not proof of a fix.
On 2026-11-06, 33 offline suites covering the recovery budget, candidate
preflight, heartbeat, one-wake/series audits and daily return passed. A local
user timer was scheduled for 15:40 UTC, after the conservative recovery wait,
to run the candidate under those gates. Its launcher checks a pinned manifest
of the test inputs, repeats the history and clock review, and stops on any
failed check. The phone remains on daily #7 with suspend masked until then.
The scheduled experiment is WFI-only; even 300 passes would not qualify C2.
The first timer was stopped before it ran when its preflight was found to use
the default cheetah backup descriptor. The replacement timer uses an explicitly
tegu-targeted backup check, tested with an argument-checking fixture, and a
new pinned input manifest.
The separate `x-tegu-coreclk-offline-followup.timer` inspects saved host logs
after the experiment service stops and writes a private, one-time summary of
its phase, stream hashes, suspend-event counts and storage faults. It never
contacts the phone; it does not replace the independent test audits or infer
the state of an unreachable device. Its scheduling and failure fixtures passed.
Separately, maclab built a #70 diagnostic in new source and output
directories, combining #69's core-clock change with the earlier failure-only
UFS event-history logging. The independent audit passed the baseline
configuration, warning comparison, complete module symbol table, reviewed
source hashes and diagnostic strings. Image SHA256:
`5ac1acb242ff50fe8f364fbd0184758c0ea6dec019b0f449b455faa8546933a`.
This gives a possible next investigation if #69 fails; it is not part of the
scheduled phone test and has not been qualified or booted.

**Earlier #69 retry preparation (2026-11-06).** The previous three-per-24-hour
recovery limit and its wait were conservative choices, not a known hardware
cooldown. After the owner's request to continue sooner, a separate reviewed
draft keeps the complete conservative boot history and permits six recovery
reservations per rolling 24 hours. Five events were in the reviewed window at
preflight, leaving one additional automatic-recovery allowance if this test
fails; a clean same-boot run refunds its allowance. The same-boot reservation,
shared one-shot reset marker, protected-backup checks, log streams, NFC gate,
watchdog and post-reset review remain required. The modified clock gate still
checks synchronized phone/host clocks, the original host boot and monotonic
continuity, but does not impose the prior selected wait. Its 33 simulated
suites and a fresh read-only phone, protected-backup and filesystem review
passed. Recovery paths and the budget are recorded in
`device/tegu/bringup/ufs-recovery-coreclk/`; the installer checks its copies
against them. This is preflight evidence, not a phone test or a suspend fix.
The original later timer was stopped before it ran, to prevent duplicate tests.
The #69 candidate was then pushed and booted; the protected-backup, module,
kernel and smoke checks passed. Its first wake did not start: arming found a
`sleepd-owned` record left by the previous #65 boot. The record predates the
candidate boot, while the mobile sleep daemon is already active, its unit is
not runtime-masked and both system sleep targets are masked. The recovery
reservation and awake UFS guard remain in place. A separate recovery draft
preserves the old log and record, rechecks the same boot, running services,
root and protected backups, and only then releases the stale sleepd lease and
refunds the unused same-boot reservation. It reinstalls the checked helpers
and reruns the normal one-wake preflight; failure fixtures passed. No sleep
cycle or successful wake has yet been recorded on #69.

**#69 wake and series (2026-11-06).** The stale sleepd lease was released only
after the separately tested recovery procedure verified the old record, same
boot, masked sleep targets, running sleep daemon, protected backups and pinned
helpers. The unused recovery reservation was refunded, and the normal
preflight was repeated. One 60-second RTC wake then passed the independent
collector: NFC prehook, elapsed times, balanced PHY events, the core-clock
request, first link startup and suspend exit all matched expectations. The
host log stream disconnected during that wake; the independent capture did
not show a storage failure. The host
SSH client had a 15-second keepalive and three missed responses, while the
frozen phone session could not respond during the sleep; the journal showed a
connection reset after thaw. This is a likely explanation, not a proven cause.

A series-specific SSH wrapper disables those keepalives for the test's log and
heartbeat connections. It leaves the independent host progress checks and
on-device stall and recovery guards active. Its transport and failure fixtures
passed. After the audited single wake and clean refund, the isolated
`x-tegu-coreclk-series.service` began 300 RTC-driven, WFI-only 60-second sleep
cycles on #69. Early host logs show paired entries and exits without the UFS
fault patterns; a running count is not a completed independent audit. A
host-only follow-up records saved evidence when the service stops. A successful
series still requires its independent cycle audit, restoration and smoke checks;
C2/deep sleep, power-key wake, modem-on sleep and battery drain remain
unqualified.

**#69 C2 runner preparation (offline only).** A separate draft in
(a local scratch directory, not in the repository) adapts the #69 WFI runner to leave C2 enabled
and record eight per-CPU s2idle counter deltas, while retaining its NFC,
storage and same-boot one-shot recovery checks. Twenty simulated cases pass,
including missing or stale recovery reservation and a previously fired reset.
It has not been installed or tested on the palmtop. Its launcher, full guard
lifecycle, collector and evidence gate still need work. In particular, the
current WFI controller restores daily #7 after its audit, so the old C2
launcher's same-boot WFI gate cannot simply be reused after that restoration.
A host-only preliminary archival verifier for the WFI evidence is also
fixture-tested against a valid synthetic 300-cycle series, missing or changed
files, missing core-clock events and fault records. It does not establish the
identity of a later boot and cannot authorize a C2 test by itself.
The series journal cursor has been checked against the boot ID in the saved
candidate verification. A separate host-only history check also verifies that
boot evidence's checksums, the five pinned candidate images and the recorded
verified slot-B writes; ten synthetic cases and the current saved records
pass. This is historical evidence, not a current-boot readback or a 300-cycle
result.

**#69 series interrupted by heartbeat (2026-11-06).** The 300-cycle runner
recorded 20 complete cycles. During the next wake the on-device guard stopped
the runner because its host heartbeat was stale; the host heartbeat later
reported an acknowledgement timeout, and the host progress monitor stopped.
The kernel log contains the 21st suspend exit and a successful first UFS link
startup, but the runner was stopped before recording or auditing that cycle.
No matching UFS fault was found in the captured kernel log. A fresh read-only
check found the palmtop reachable on the same #69 boot, root read-write, no
pstore files, sleep and suspend targets masked, sleepd active, and no fired
recovery marker. The same-boot recovery reservation and awake UFS guard remain
in place for review.

A separate partial-run auditor checks the 20 recorded cycles' RTC and uptime,
NFC prehooks and ordered kernel events including the core-clock request. Its
first version incorrectly counted the unrecorded 21st exit in the last
completed interval; the corrected copy bounds the kernel evidence by the
last recorded cycle's end, passes six positive and negative fixtures, and
passes the saved 20-cycle records. This is not a 300-cycle pass. The last
on-device heartbeat timestamp coincided with the 18th wake, and the persistent
SSH heartbeat later timed out. The reason for the missing acknowledgements is
not yet established; disabling SSH keepalives alone was insufficient. Preserve
all captures and resolve or redesign the heartbeat without weakening the
storage, host-progress, or one-shot recovery guards before another series.

**Heartbeat transport draft (offline only).** A separate authenticated UDP
receiver and host sender are being explored to avoid depending on one SSH
session surviving repeated USB sleeps. Packets carry the candidate boot ID,
a sequence, a timestamp and a per-run HMAC; stale packets and replays are
rejected. A root-owned receiver identity and a separate monitor check process
identity and heartbeat age. Five protocol and five loopback process tests
pass, including host and receiver exits. The reason the SSH acknowledgements
stopped remains unknown. The UDP code has not run on the palmtop and lacks
its installer, guard integration, recovery lifecycle and clock preflight; it
must first pass a guarded single RTC wake without an early network wake.
An awake-only USB probe of that draft has since passed with two successive
pulse sequence numbers. It removed its temporary service, timer and files;
the existing awake UFS guard remained active and sleep remained masked. Nine
launcher fixtures cover invalid paths, preflight, timer, upload, startup,
stale-sequence and cleanup failures. The transport still has not been tested
through a sleep, and the guarded test's complete launcher and rollback remain
to be adapted.
The UDP heartbeat then passed one separately guarded 60-second RTC/WFI
sleep on the same #69 boot: the independent collector found one NFC prehook,
62 seconds by RTC, consistent uptime, ordered core-clock request and UFS
startup, and no captured fault. Heartbeat sequence advanced from 1 to 11,
including a pulse after wake. Temporary receiver, host guard, fallback and
files were removed; sleep and suspend are masked, sleepd and the awake UFS
guard are active, and the original recovery reservation remains. This is one
wake, not proof of a reliable long run.

**UDP-monitored #69 endurance retry (2026-11-06).** After rechecking the
single-wake evidence, its candidate boot and image history, and the 20-cycle
partial evidence, `x-tegu-udp-series-20261106.service` started a new
300-cycle WFI-only RTC series. Its controller rechecked the protected
backups, original same-boot recovery reservation and helper hashes; the new
seven-hour fallback was armed before the superseded fallback was stopped.
The receiver, host-progress watcher, UFS fault guards, independent cycle
collector and clean-return path have simulated failure coverage. On a clean
300-cycle audit the controller retires the reservation, restores daily #7,
checks the protected backups and smoke report, and restores the prior modem
and sleepd state. Suspend remains masked after restoration. The first host
stream wake was paired; that is not a completed run. The arm helper still
prints a stale "single cycle" message, but its launched runner explicitly
uses `N=300`, and the independent collector requires all 300 records.
A separate host-only follow-up timer summarizes the saved logs if the service
stops. Normal C2, physical-key wake, modem-on sleep and battery use are still
unqualified.

**UDP endurance interruption and fresh-socket retry (2026-11-06).** The
UDP-monitored 300-cycle attempt stopped when the heartbeat became stale after
four service-recorded passes. An independent partial audit passed those four;
the kernel also recorded a successful fifth wake, which the stopped runner
had not recorded as a pass. No matching storage fault was found, and the
palmtop remained reachable on the same boot with root read-write. The failed
run's logs, receiver state and host network evidence were saved with hashes;
its temporary receiver and cleanup timer were removed while retaining the
same-boot recovery reservation, awake UFS guard and active fallback.

The host USB network device disappears in every sleep and is re-created with
a new interface index on each wake. That is a plausible cause of stale routing
on a persistent UDP socket, but the missing pulses' exact cause is not yet
proved. A revised sender opens a fresh socket for each authenticated pulse,
tries once per second, and logs transport transitions; the 180-second
on-device staleness guard remains. Protocol, loopback, recreated-socket and
failure-path tests pass, as did an awake USB probe. A separately gated
10-cycle WFI/RTC qualification was started in
`x-tegu-udp-v2-ten-20261106.service`; its collector requires 10 complete
NFC, timing and kernel audits. The existing fallback is replaced only after
the new fallback is active. A pass would qualify this monitoring approach
for a new endurance attempt, not establish the suspend fix.
A host-only timer now checks the 10-cycle service every two minutes. It starts
`x-tegu-udp-v2-full-20261106.service` exactly once only after that service
exits successfully and its ten-cycle, candidate-identity and heartbeat
records pass fresh independent audits. The 300-cycle controller repeats those
gates, uses the fresh-socket sender, and on a clean complete audit restores
the daily kernel and prior services. The autostart refuses a failed, incomplete
or altered qualification; its six simulated cases pass. A separate host-only
follow-up summarizes the full run after it stops. No result is implied by
scheduling these services.
A separate #71 fallback build is running on maclab from #70 in new source and
output directories. Its only additional kernel changes record the UFS host's
existing `HCI_MISC` value before and after the core-clock request, before
pre-link and after successful pre-link; the original request marker remains.
Those reads are in the driver's already powered host block. The reviewed patch
passes strict checkpatch. A host-only watcher will compare configuration,
W=1 warnings, module symbols, source hashes and diagnostic strings after the
build. This instrumentation may affect timing, has not been staged or run on
the palmtop, and is only a fallback if the present candidate needs more
investigation.
A separate host-only prerequisite for future C2 work now verifies synthetic
full-run evidence, the original candidate boot and image history, heartbeat,
and checksummed daily/modem restoration records, including a distinct daily
boot ID. Negative fixtures reject altered or incomplete cycles, faults,
heartbeat and restoration evidence. It still needs live-boot, current recovery
ledger and backup checks and a fully tested repush/guard/cleanup launcher
before it can be used for a real C2 attempt.
The fresh-socket 10-cycle qualification completed and passed independent
NFC, timing, per-cycle kernel, checksum and heartbeat audits. Its temporary
receiver and cleanup timer were removed, while its same-boot recovery
reservation, awake guard and fallback were retained. The gated host timer
then started `x-tegu-udp-v2-full-20261106.service`; its preflight rechecked
the single and ten-cycle evidence, previous partial runs, pinned images,
clock, recovery state and protected backups. The 300-cycle run has been armed;
it is not yet a result. On a clean 300-cycle audit the controller restores
and verifies daily #7 and the prior modem and sleepd state.
A future read-only daily-kernel C2 preflight is also drafted and passes
11 simulated success/failure cases. It checks the completed full-run proof,
current boot, clocks, safety state, ledger, protected backups, smoke and kernel
log; it has not been run on the palmtop. The separate image push, post-boot
reservation and C2 test lifecycle remain to be built and tested.
A separate future slot-B repush draft now gates on that daily review and the
full result, rechecks the current boot, recovery ledger, verified image/module
files and a live host stream, and records boot/service state before using the
existing writer. Twelve simulated gate/failure cases and local filesystem
checks for marker symlinks and existing files pass. It has not run on the
palmtop and still lacks the connected post-boot and C2 lifecycle.
The future #69 post-boot C2 verification draft passes 12 mocked cases, and a
separate C2 single-wake lifecycle draft passes its simulated arm, cleanup,
stream-guard and C2-counter checks. These are offline only: helper installation,
new-boot reservation, host orchestration, independent collection and rollback
remain incomplete, so no C2 run is armed.

The isolated #71 fallback build and its independent offline audit completed:
configuration, release, version, W=1 warning baseline, module symbols, source
hashes and diagnostic strings passed. Its Image SHA-256 is
`be45ba8f1bda6585e7ca2d5f7c412616b779dce30d64a89f4356bbac2516d32b`.
At build completion it had not yet been staged or booted; the extra register
reads may affect timing. The ongoing #69 endurance run, not #71, is the current hardware test.

Further C2 preparation remains offline. Helper installation and a fresh
same-boot recovery reservation with an awake guard and fallback have mocked
success and failure coverage, including ambiguous reservation results. A
single-cycle collector now checks NFC, RTC, ordered storage events, observed
C2 entries and kernel faults; nine fixtures pass. Stream identity, PID reuse,
stalls and faults also have simulated checks. The end-to-end host launcher
and rollback are incomplete, so no C2 test is armed or qualified.

**#69 full run interrupted by reboot (2026-11-06).** The guarded fresh-socket
300-cycle run recorded 24 passes, independently checked for NFC, RTC/uptime,
per-cycle storage event order and captured kernel faults. The next kernel log
records a 25th `PM: suspend entry (s2idle)` at palmtop 08:01:11 MST, with no
recorded corresponding exit before the next boot began at 08:02:27 MST. The
host stream disconnected as the palmtop rebooted; the controller then stopped
with a lost-stream error. That error describes the observation, not the cause
of the reboot. The last captured entry does not establish whether the hang
was during suspend entry, sleep or resume. Live `/sys/fs/pstore` was empty
after boot; the systemd-pstore archive was not checked. No matching storage
failure was captured, so this is not proof of either a UFS fault or a
fix. The same candidate #69 booted again, root is read-write, sleep and suspend
are masked, and protected-partition checks match the saved backup. The prior
boot's recovery reservation was reviewed as consumed, not refunded. After a
checksummed health and ledger review, its stale marker was retired with a
durable receipt; the ledger is unchanged. Boot-local guards are gone. The stale sleepd ownership marker was cleared
after verifying its running service and the masked sleep targets; install new
safety nets before any further device test. The complete 300-cycle and C2
prerequisites did not pass. #71 remains an unbooted diagnostic fallback.
The subsequent boot's bootloader bootconfig reports
`androidboot.bootreason = "watchdog", "apc", "early"`. This establishes the
reported reset type, not the device or suspend phase that stalled. The captured
ledger matches the previously verified seed plus the old boot's reservation;
clock synchronization and host monotonic continuity also passed a read-only
check. A new-boot recovery review is still required before clearing any stale
marker or reserving another attempt.
The #71 diagnostic Image is now staged in a separate, unbooted kit. A
complete source-tree comparison found only `ufshcd.c` and `ufs-exynos.c`
differ from #69; both are built in. Configuration, exported symbols and module
order are identical, and the kit retains the previously installed module
archive. Two independent image packs matched, and the four non-kernel boot
images match the #69 kit. These checks do not establish that #71 will boot or
identify where the watchdog hang occurs. No diagnostic image has been pushed.

**#71 diagnostic boot and single wake (2026-11-06).** The separately staged
readback Image was pushed to slot B and booted; all five image writes were
verified, and the new boot passed module, protected-partition, sleep-mask and
health checks. A same-boot recovery reservation and fallback were armed. The
first awake-guard start rejected the new inhibitor name before any suspend;
a tested guard with corrected inhibitor names was installed, and the guard
then remained active. A separate guarded one-cycle WFI/RTC test has started;
its result is not yet known. Its collector checks NFC, timing, ordered UFS
resume events and the HCI_MISC core auto-clock bit before/after the request
and around pre-link. These diagnostics can alter timing and cannot locate a
hang if no resume messages survive.
The #71 single WFI wake completed and passed independent NFC, RTC/uptime,
ordered storage and kernel-fault audits. Its driver readbacks were `0xd10`
before the core-clock request, `0xd00` immediately afterward, `0xd00` before
pre-link and `0xd00` after successful pre-link. Bit 4 was therefore clear at
all three later readbacks on this successful wake. This verifies one observed
request, not its behavior on the watchdog-reset cycle or a durable fix. The
host heartbeat advanced, sleep is masked, and the same-boot reservation, awake
UFS guard and replacement fallback remain active. The arm helper's inherited
console message incorrectly says C2; this run used the WFI-only runner, not
C2. All evidence is checksummed in the private `readback71-one-evidence` log.
A separately gated 300-cycle #71 WFI run is now active. Its launcher rechecks
the one-wake audit, boot identity, five image hashes, heartbeat, current
same-boot recovery reservation, awake guard, fallback and protected backups.
It captures the clock readbacks on each wake and replaces the short fallback
only after the longer one is active. The first host stream entry and exit were
paired; this is not a completed or independently audited run. On a complete
clean audit the controller refunds the unused same-boot reservation, restores
and verifies daily #7 and prior modem/sleepd state, leaving suspend masked.
A failed or partial run retains evidence and stops for review. The host-only
follow-up timer summarizes saved logs after the service exits.

An offline comparison of the #69 watchdog run found the same Wi-Fi P2P
interface-creation timeout after each of the 24 completed wakes, roughly three
seconds before the next suspend entry. It also occurred before the final
entry, so its presence does not distinguish that failure from the successful
cycles and does not establish it as the cause. The driver reports this when
it does not receive the firmware's P2P interface-add event; ordinary Wi-Fi
was present in the subsequent smoke report. This is a separate observation
for later Wi-Fi diagnosis, not a justification to alter the active sleep run.
The post-watchdog review checked `/sys/fs/pstore`, which was empty after boot,
but did not inspect the systemd-pstore archive under `/var/lib/systemd/pstore`.
The boot did start systemd-pstore, so that archive still needs a read-only
check after the active series; an empty live pstore alone does not exclude an
archived record.
If the #71 long controller fails, a separate host timer waits at least five
minutes after observing the failure and makes one bounded read-only SSH capture
of the boot state, logs and both live and archived pstore. It never retries an
unanswered device and makes no connection while the series is active. A
separate host-only summary timer handles the saved stream.
Offline preparation for a possible later #71 C2 test now has a future gate
that requires the actual 300-cycle audit, readbacks, candidate history,
heartbeat and clean daily/service restoration. A read-only future daily
preflight also records the archived pstore data and rechecks the post-watchdog
ledger. Their success/failure fixtures pass, as do the C2 runner's simulated
counter and fault cases. The next C2 lifecycle is incomplete and has not run
on the palmtop; none of these drafts changes the current WFI-only series.

The later C2 lifecycle is now prepared and scheduled behind that independent
300-cycle and daily-restoration gate. It pushes #71, runs one guarded C2
cycle, audits it and restores daily #7 and prior services; simulated failures
retain markers and recovery safeguards. The C2 test has not yet run. A
separate post-failure observer waits at least five minutes and makes one
read-only capture attempt, including live and archived pstore. The WFI
observer likewise attempts only once; if that attempt cannot connect, a
host-only timer sends Dave one Grok request for a cable check and brief Power
press. No host observer contacts the palmtop during the active WFI run.

The gated C2 follow-on was extended to 300 cycles after the single wake. It
independently verifies the single-wake evidence before arming, audits every
long-run cycle, and restores daily #7 and the prior services only after a
same-boot clean finish. The host launcher and its checksummed inputs, guard,
recovery budget, failure capture and notification paths passed simulated
success and failure cases; none of those results qualifies actual C2 sleep.
`x-tegu-c2-endurance-awake.service` keeps the host awake for this follow-on.

The observed S2MPG14 stale alarm read and the separate #44 diagnostic's
24 unprimed reads and 20 awake alarms were reported to Derek in
[linux-omarchy-mobile#201](https://github.com/derekross/linux-omarchy-mobile/pull/201#issuecomment-6691845697).
That report explicitly distinguishes #44's 50–51 µs delay from the
published path's 50–100 µs delay and makes no UFS-fix claim.

**#71 WFI stream interrupted (2026-11-06).** The host watcher stopped
when its diagnostic log process ended. The saved stream after the pinned
start offset contains 111 paired PM entries and exits, with no captured
matching UFS or kernel-fault patterns. A host-only readback audit found
`0xd00` before and after the request, before link and after link on each of
the 111 observed wakes. A separate host-stream audit also found the expected
ordered UFS resume events on all 111. These checks do not audit NFC or elapsed
time. The last recorded exit precedes the connection reset;
the saved stream does not prove what happened after the connection ended.
The full NFC, timing and device-side kernel audits remain pending. The C2
launcher stopped because the 300-cycle WFI gate failed; no C2 run began.
A separate observer will make one bounded read-only capture after waiting
at least five minutes from its failure observation. No second connection
attempt should compete with it or follow an unanswered attempt until a
physical change is reported.

**#71 112th wake: UFS failure, captured recovery (2026-11-06).** The
one-shot observer reached a new boot; its bootloader reported `watchdog,
apc, early`, root was read-write, the sleep targets remained masked, and the
new kernel tail had no matched UFS or kernel-fault pattern. A separate
read-only capture of the old boot found 111 recorded passes. Independent audit
confirmed their NFC prehooks, RTC/uptime intervals and ordered UFS events.
All 111 had HCI_MISC `0xd00` at the four readback points.

The observer also found an archived `console-ramoops-0`. Its last eight
completed suspend exits align with the old boot's last eight journal exits
within 0.4 seconds, strongly associating the archive with this run. It
records a 112th suspend entry 6.409 seconds after the last completed exit.
On its wake, the deferred PHY pre-link returned zero in all 20 attempts,
while `DME_LINK_STARTUP` returned 1 in all 20 across five failed host
initializations. In this kernel, a positive UIC result comes from the
command's result field; `1` is `UIC_CMD_RESULT_FAILURE`, whereas a command
completion timeout returns `-ETIMEDOUT`. The captured failure contains no UIC
completion-timeout or controller-not-ready message. This is a generic failure,
not a unique diagnosis of either side of the link. The core-clock bit was
clear at every before, after, pre-link and link-ready readback. Each host-failure snapshot said there was
no saved PA, DL or DME error-history record; that is not proof that no
hardware error occurred. The archived console's eight retained successes took
23.073–23.129 ms from link-ready to startup result; the 20 failures took
104.961–105.068 ms, matching the broad timing pattern of the earlier #62
failure. That similarity does not establish a common physical cause. The
console then records `sysrq: Resetting`, 61.957 seconds after the unjournaled
entry: the reset was a deliberate recovery,
not evidence of an unexplained spontaneous watchdog. Which guard issued it
has not yet been established. The bootloader's watchdog reason alone did
not distinguish that recovery from a spontaneous reset.

The old boot's recovery reservation and sleepd ownership marker persist,
and the reservation must be accounted as consumed. Further device changes
need the normal fresh health, protected-partition and ledger review. The
previous #69 watchdog reset remains a separate unexplained event. The
private capture and independent failure audit are checksummed in
`logs/tegu-suspend-trace-20261104/readback71-partial-capture-20261106/`;
the analysis rejected clock-bit, missing-reset, missing-command and
unrelated-boot mutations. The 300-cycle test and C2 gate did not pass.

**Daily restoration and budget correction.** The post-failure review
verified the new boot, protected partitions, current kernel health and the
ledger as the preceding reviewed ledger plus the #71 reservation. That old
reservation was recorded as consumed and retired with a durable receipt; no
ledger entry was refunded. The stale sleepd ownership marker was cleared only
after verifying its service active and both sleep targets masked. The #7 daily
images were then pushed and read back, followed by boot, module-inventory,
protected-partition and smoke checks. The prior modem and sleepd states were
restored under a fresh same-boot recovery reservation, which was released on
a clean restore. A final comparison confirmed the ledger is byte-identical
to the post-failure review, the transient markers are gone, both services are
active and sleep remains masked.

An intermediate status incorrectly applied the older proposed three-event
limit. The current reviewed rule, changed after the owner's request, allows
six reservations per rolling 24 hours; the reviewed ledger showed three
within that window before the clean service restoration. The temporary
restoration reservation was released, leaving those three events intact.
Any further hardware test still needs its own health, evidence, clock, budget
and recovery gates; an available allowance is not proof of a fix.

**Deferred pre-link PHY APB-clock draft (2026-11-06, offline).** The #71
readbacks show HCI_MISC `0xd00` around its failing pre-link calls: the core
auto-clock bit was clear, while bit 10, the PHY APB auto-stop enable in
Google's register definitions, was set at those snapshots. Google's GPL
`ufs_call_cal()` clears bits 10 and 5 around its calibration callback and
sets bit 10 afterward. #71 snapshots show bit 5 already clear; they do not
prove the register's value throughout the callback. The earlier #59 test
cleared bit 10 around an earlier resume-time PHY power-on that timed out;
#71 instead defers calibration to pre-link after host reset. A separate
#71-based draft clears bit 10 only around that deferred calibration and
restores its previous value while preserving other bits, checking both
readbacks and propagating failures. A fixture compiled from the actual
callback covers the target and non-target paths, changed unrelated bits,
calibration errors and failed force/restore readbacks. Strict checkpatch
passed for the unsigned draft; the W=1 object built without warnings on
maclab. An independent whole-tree comparison found only the intended host
driver change against #71, and the configuration matches #71.
This is a narrowly scoped hypothesis, not a proven cause or a tested fix;
register serialization, the power/clock preconditions and failure handling
need independent review before any device trial.

The original draft also matched runtime PM. It has been narrowed to require
`is_sys_suspended`, and an added compiled fixture verifies that runtime PM
does not change the register. Strict checkpatch passes for this unsigned draft
with message and sign-off checks disabled; the revised full W=1 build
completed. Its independent audit passed the source, configuration, release,
build version, complete symbol table, palmtop DTB, warning baseline and image
diagnostics, and confirmed that the revised host object was rebuilt; eleven
negative fixtures pass. The revised full-tree comparison again found only the
intended host driver change across 102,607 paths.
In #71, system suspend holds `host_sem` across workload resume, takes a
clock-gating hold before suspend, and restores host power and clocks before
the deferred pre-link callback. That is evidence for the normal path, not a
complete serialization proof: the error worker can call link recovery while
`pm_op_in_progress` before acquiring `host_sem`, and other host paths also
modify HCI_MISC with read/modify/write operations. Review concurrent recovery
and register writers before testing; fresh read/modify/write alone does not
exclude a race. The full build and source checks do not resolve that race.

The error workqueue is ordered but not marked freezable. On an error IRQ,
the worker may enter `ufshcd_link_recovery()` while PM is in progress, before
the `host_sem` acquisition; link recovery can reset the host and use the
existing HCI_MISC save/restore. An offline fixture compiled from the actual
draft helper and existing full-register restore demonstrates two possible
interleavings: a previously saved value can re-enable bit 10 during
calibration, and a value saved during calibration can clear it after the
helper restores it. This establishes a source-level race if those operations
overlap, not that #71 experienced it. The revised #74 draft is not ready for
device testing until the overlap is excluded or safely serialized; a clean
build cannot establish that property.

An offline #75 follow-up drafts a zumapro-only mutex around HCI_MISC writers
and deferred calibration. A fixture compiled from the actual helper and
writers checks three concurrent writer paths and a non-target path; removing
the mutex makes the fixture fail. The helper fixture also tests a forced bit
change during calibration, and a W=1 object build passed. This only addresses
the demonstrated register-write interleavings: device reset and PHY state
notification occur outside the new lock, so it does not serialize the entire
recovery operation. The sleepability of every lock caller, lock ordering with
the PHY mutex, reset timing and error paths need independent review. This is
an unbooted diagnostic draft, not a complete UFS fix or a device-test kit.

**Additional deferred-PHY state race (offline, 2026-11-06).** The #75
HCI_MISC mutex does not cover `PHY_UFS_TEST_PRE_LINK` notification, which
sets the Samsung PHY state to `CFG_PRE_INIT` before the helper takes that
mutex. The generic PHY core separately locks each notification and each
calibration, rather than the pair. If two recovery paths reach this point
concurrently, both can set `CFG_PRE_INIT`, the first calibration can advance
it to `CFG_POST_INIT`, and the second can return zero after applying the
post-init table instead of the intended pre-init table. A compiled fixture at
(a local scratch directory, not in the repository)
extracts the actual Samsung notify and calibration functions and demonstrates
this ordering. Other calibration call sites must be considered too, not only
the HCI_MISC writers. The known non-freezable error worker's PM path makes
concurrent recovery a source-level concern; the #71 capture does not prove
that this interleaving happened. A successful calibration return alone does
not identify which state table ran. Do not boot #75 without resolving or
excluding the full recovery and PHY-state overlap and checking lock ordering.

**Why a whole-reset mutex is not yet safe (offline, 2026-11-06).** In the
#75 kernel, `ufshcd_link_recovery()` calls `ufshcd_host_reset_and_restore()`,
which calls `ufshcd_device_init()` and then `ufshcd_verify_dev_init()`. The
latter synchronously executes a NOP management request through
`blk_execute_rq()` on the SCSI pseudo-device. Both SCSI block-mq operation
tables use `scsi_timeout()`, which calls the UFS `eh_timed_out` callback;
while PM is in progress, that callback calls `ufshcd_link_recovery()` before
completing the timed-out request. Therefore a blocking mutex held across the
whole reset-and-restore and acquired again by that timeout recovery can make
the original reset wait for the request while its timeout handler waits for
the mutex. A mutex around all of `__ufshcd_wl_resume()` has the analogous
problem for its synchronous START STOP UNIT command. These are source-level
deadlock paths for those proposed designs, not a diagnosis of #71 and not a
claim that either proposed mutex exists in the running kernel. Any replacement
must allow timed-out requests to complete or otherwise make progress without
concurrent hardware reset, with the relevant SCSI and block completion
semantics reviewed and tested. The #75 HCI_MISC mutex covers neither the full
reset nor this re-entry problem and remains an unbooted diagnostic only.

A nonblocking whole-reset lock alone is not a safe replacement either. In
the reviewed UFS core, `ufshcd_eh_timed_out()` ignores the return from
`ufshcd_link_recovery()` and then completes the request; for a normal SCSI
command it calls `ufshcd_release_scsi_cmd()`, which unmaps its DMA. If a
new trylock made recovery return early while hardware still owned that
request, the existing timeout path would have no demonstrated controller
quiescence before that unmap. A fixture compiling the actual #76 timeout
handler simulates a busy recovery and a still-owned request, and confirms that
the handler calls the release path and completes the command. The simulation
does not establish that this happened on hardware. Fixture:
(a local scratch directory, not in the repository).
The same completion path also needs review for MCQ. This is a source-level hazard in a proposed design, not evidence of a
trylock in the running kernel or the cause of #76. A safe serialization
scheme must account for request ownership and completion as well as lock
progress.

**#71 overlap evidence limit (2026-11-06).** Rechecking the archived console
from the final suspend entry through the recorded SysRq reset found one
workload-resume start and no `ufshcd_err_handler`, `ufshcd_eh_timed_out`,
`ufshcd_link_recovery`, or `resume-trace: tag` lines. The error worker logs
at entry, so its absence weakens the hypothesis that it overlapped the
recorded failure, assuming those messages were retained. The timeout handler
logs only after recovery returns; its missing completion line does not exclude
an in-flight timeout. No recorded tag after the entry also does not prove
that an earlier request could not time out. Thus the archived log supplies no
positive evidence of concurrent recovery, and the source races must not be
presented as the established cause.

**Recovery-overlap observation draft #76 (offline, 2026-11-06).** A separate
#71-based UFS core draft counts and logs entry and exit of host reset/restore
and device reset while a zumapro UFS host is system-suspended. It records the
current task, active reset counts and result; it adds no reset, lock, hardware
register access or changed recovery return. Counters are decremented using the
entry-time decision even if the PM state changes. The compile fixture uses the
actual draft functions and checks host/host and host/device overlaps, balanced
counters and a non-target device; removing a counter makes it fail. Strict
checkpatch passed and an isolated W=1 core-object build passed against the
#71 warning baseline (one pre-existing kernel-doc warning); the object SHA256
is `1b3fa75b411658800da50fe759a32ff712c890592e27b1085abd794fb4d609e6`.
The source and fixture are in
(a local scratch directory, not in the repository); maclab's isolated tree
and output are (a local scratch directory, not in the repository) and
(a local scratch directory, not in the repository), marked DO-NOT-PUSH. A complete
kernel build and independent audit are running. The trace can show an
observed overlap, but missing lines or overlapping activity outside the
system-suspended filter mean a lack of logged overlap cannot prove none
occurred. Logging may also change timing. This is observation, not a fix or
an approved hardware-test kit.

**#71 timing comparison (2026-11-07, offline).** The eight retained successful
attempts and 20 failed attempts have overlapping intervals from reset to the
pre-link log (success 1.123–1.167 ms, failure 1.112–1.203 ms) and from the
pre-link log to the successful calibration return (success 2.102–2.536 ms,
failure 2.172–2.484 ms). The interval from link-ready to UIC result was
23.073–23.129 ms for successful attempts and 104.961–105.068 ms for failed
attempts. These are printk intervals from one
captured run, not measurements of every PHY operation or proof of a timeout
inside the controller. The comparison and missing, corrupt and reordered
record fixtures are under (a local scratch directory, not in the repository).

The recorded #71 failure also has a consistent ordered sequence: five host
failures, each containing four attempts with reset readback, pre-link
readback, successful calibration, link-ready readback and failed startup, with
retry counts 3, 2, 1, 0. The new offline sequence audit accepts the captured
archive and rejects missing, reordered, wrong-result and incomplete fixtures.
This ordering is consistent with the ordinary retry path; because the old log
has no task identities, it does not exclude an unlogged concurrent operation.

The complete #76 W=1 build subsequently finished. The independent audit
verified the source hash, #71 configuration, release and module symbols,
palmtop DTB, warning baseline, build version and diagnostic strings; its Image
SHA256 is `411e20857cb9402c0d305417c8c033e3f201f3b0990c8e0a668dda4d6a5c6ae1`.
A post-build comparison of 102,607 paths found only the intended UFS core
source change. An isolated packing tool first reproduced all five #71 images
byte for byte. The #76 kit was then packed twice identically: its four
non-kernel images still match #71, its kernel decompresses to the audited
Image, and its 64 MiB boot image has a valid AVB footer and the expected AOSP
test key. A separate kit audit passed six corrupted or unsafe negative
fixtures. The kit remains at `out/tegu-suspend-recovery-overlap-20261106`,
marked DO-NOT-PUSH, and both wrappers refuse device writes. The current-boot
preflight and audits are checksummed under
`logs/tegu-suspend76-preflight-20261106/`. These checks establish the offline
artifact, not the full current-boot recovery lifecycle or a suspend fix.

**#76 rollout gates (offline, 2026-11-06).** The proposed diagnostic writer
now checks calls, systemd, all five partition identities, permissions and
sizes, and the exact AVB boot boundary before the first write; it checks each
readback and calls for an orderly systemd reboot so the existing modem stop
runs. Its device operations are disabled. A fake-device suite exercises partial
writes, bad readbacks, calls arriving before or after writes, and a lost SSH
reply after reboot. The writer still needs a complete, independently tested
rollout and rollback controller before it can be used.

Two new read-only gates cover the states around that controller. The armed
pre-write gate requires the modem to remain online while its next-boot starter
is disabled, the persistent recovery records and sleep inhibitor to be present,
and the original boot, recovery ledger and partition mapping to match the
fresh preflight. The candidate-boot gate checks for a new #76 boot, an offline
modem, masked sleep, intact recovery records and budget, the protected partition
backup, exact installed module inventory, required smoke results and a clean
storage log. It retains the boot marker. Fake unsafe snapshots and changing
state are rejected, and both collectors have been exercised read-only on the
daily kernel. These checks do not establish that #76 is safe to push or that
suspend is fixed; the guarded device lifecycle remains unfinished.
A further offline lifecycle test stops at each failed phase and treats a lost
preparation response or any attempted write as uncertain: it preserves the
marker and evidence instead of trying to undo them. Cleanup before a write is
allowed only through a backend that verifies ownership and the same boot; that
live backend and the complete rollback are not implemented yet. A fresh
read-only review on the daily kernel passed with four recovery events in the
rolling 24-hour window; repeat it at the time of any actual operation.

**#76 recovery-state corrections (2026-11-06).** The candidate boot checker
previously required `/sys/bus/platform/devices/cpif/modem_state` to say
OFFLINE. With the modem boot service disabled the CPIF driver can be unloaded,
so that file may not exist. The checker now distinguishes an unloaded driver
from an explicit OFFLINE state and from uncertain or online states. An unloaded
driver does not itself prove the CP is off: the checker also requires journal
evidence that the exact modem service invocation from the preflight reported
CP OFFLINE and a successful stop on the previous boot. It validates that
sequence against the palmtop's real previous orderly shutdown, using the
journal's 32-character boot ID format. The same-boot preflight now records
and checks the modem invocation.

The offline preparation and transition drafts use a shared lock and a durable
`write-started` record bound to the old boot ID. Pre-write cleanup refuses to
run once that record exists; the writer checks the record before and after
partition writes. Their fake-device tests cover missing or stale records,
partial preparation, active calls, concurrent transitions, and failed writes.
The candidates remain explicitly disabled: a live backend, complete rollback
and verified post-boot helper lifecycle are still needed. A fresh read-only
preflight passed with the palmtop on its daily kernel.
The draft backend now connects preflight, kernel streaming, preparation,
write-intent marking, the disabled image writer and independent candidate-boot
verification; fake-backend tests check script hashes and argument handling.
For the clean return path, an offline daily writer checks the disabled modem,
the candidate kernel, the return marker, every slot-B target and each image
readback. A separate locked transition makes the return marker atomic and
refuses a live modem, pending recovery, stale RTC alarm, pstore evidence or
active test guard. The candidate verifier can also check the subsequent daily
boot against both prior boot IDs. These components passed fake-device tests;
service restoration and a complete integrated rollback test remain before
any live rollout.

**#76 boot and unexpected shutdown watchdog (2026-11-06).** A fresh read-only
preflight passed, the prepared slot-B images were written and read back, and
#76 booted. Its independent verifier stopped: the previous modem service
journal had no CP OFFLINE or successful-stop record. The previous journal
ends at the systemd reboot request and the next boot began about 59 seconds
later; the one-minute shutdown watchdog is the likely reset path. The reboot
reason also says watchdog, but that field alone does not distinguish a normal
reboot on this device. This was a boot qualification only: no suspend cycle
was attempted and it does not establish a UFS fix.

The #76 boot was responsive, its protected partitions matched their backups,
the installed module inventory matched the saved daily inventory, sleep targets
remained masked, and the current kernel log had no matched storage fault.
CPIF had not loaded and the modem boot service was disabled. Since that does
not prove a clean modem shutdown, the always-powered gpa5 PHONE_ACTIVE and
CP_PS_HOLD inputs were each observed low through an as-is GPIO request after
checking their chip, ownership and input direction under a live kernel stream.
The previous modem latch still named the previous boot and recorded ONLINE;
the private modem-log review found no CP crash or boot-failure signature.
The unexpected watchdog was conservatively added to the recovery ledger,
raising its rolling 24-hour count from four to five.

The saved daily images and their readbacks were then verified, and #7 booted
with the modem still disabled. Protected partitions and required health checks
passed, the module inventory matched, and both modem status inputs were again
low. Under a fresh same-boot recovery reservation and live kernel stream, the
old modem latch was copied to the root-only
`/var/lib/omamobile/suspend-test/modem-latch-before-watchdog76` before it was
cleared; the modem was started once on the fresh boot. CP returned ONLINE,
the modem and phone services became active, protected backups and required
health checks passed, and the clean same-boot reservation was released.
The prior modem boot policy and sleep-daemon state were restored, the test
markers were cleared, both sleep targets remain masked, and the recovery ledger
retains five recent events. The archived prior latch and private evidence under
`logs/tegu-suspend76-qualification-4048696f330f/` are kept for review.
Investigate the shutdown stall before another diagnostic reboot with the modem
up; the missing clean-stop record must not be treated as a successful shutdown.
The streamed kernel log ended as USB went away, so its final PCIe PHY line is
not a shutdown hang trace. systemd's `RebootWatchdogSec` covers its second
shutdown phase after the normal service shutdown; the 59-second interval does
not establish that it fired while the modem unit was stopping. The separate
runtime watchdog applies during the first phase. Preserve the ambiguity until
evidence identifies the phase and the CP's actual stop result.

The offline #76 cycle runner also only searched for the generic
`omamobile-modem-start` process, missing the 9a's separate transient modem
unit. It now refuses if CPIF is loaded or its state path exists, or if any
9a modem, generic modem, sitd or mmd unit is active or cannot be queried;
it rechecks immediately before each suspend. Simulated active, unknown,
loaded-driver and late-start cases all stop, alongside the existing 22
runner fixtures. An unloaded driver is still not proof of a clean CP stop:
the independent previous-boot shutdown verification remains mandatory. This
runner is an offline draft; no further suspend cycle has been attempted.

**Shutdown evidence draft (2026-11-06/07).** To retain evidence before USB
and the journal go away, an offline observer draft would run after the modem
unit stops and before shutdown and its filesystem unmount. Synthetic
`Before=`/`Conflicts=` shutdown transactions on the palmtop confirmed that
ordering for both a successful and a failed modem stop. The observer records
the exact boot and service invocation, systemd's stop and stop-post results,
CPIF's reported state, latch presence and matching ordered journal messages;
it also checks that automatic modem restart and the boot starter are off,
then fsyncs an exclusive root-only record. A reader checks file ownership,
permissions, process-independent attempt ID, preflight monotonic time and a
recomputed verdict. Missing or conflicting evidence is unconfirmed.

The enabled-copy draft additionally requires a root-owned arm record binding
the script hash, boot, modem invocation, observer invocation, attempt and
preflight time. On the palmtop, real systemd and journal fixtures with fake
services passed clean and failed stops, including arming and durable-record
verification. The actual observer remains disabled and uninstalled, and it
has not observed a real reboot. In particular, its snapshot cannot itself
exclude a modem restart after capture. Integrate an independently checked
arming and cleanup lifecycle and account for later restarts before using it
as a substitute for the current previous-boot journal gate. The draft and
fixtures are under (a local scratch directory, not in the repository).
The observer draft now also requires systemd's manager state to be
`stopping` both before and after capture. [systemd 262's manager](https://raw.githubusercontent.com/systemd/systemd/v262/src/core/manager.c)
reports that state when `shutdown.target` is active or queued; the fake-shutdown tests substitute
that state and therefore do not prove the real reboot path will report it.
An offline arming/cleanup state machine treats a lost response after any
mutation as uncertain and retains the attempt record; pre-write cleanup must
independently reject a possible image write. Its failure fixtures pass, but
the lifecycle is not yet integrated with the rollout.
In a further palmtop fixture, a normal replace-mode shutdown transaction
could be displaced by a fake modem restart, whereas the same request failed
while a replace-irreversibly transaction was pending. `systemctl reboot`
normally uses that irreversible mode, but the jobs can still be explicitly
cancelled ([systemctl 262](https://www.freedesktop.org/software/systemd/man/262/systemctl.html)).
The observer's `stopping` check does not prove the transaction mode or rule
out a later cancellation, so a verified writer and post-capture checks are
still needed before relying on its record.
On 2026-11-07, fake-service tests on both fw12 and the palmtop (systemd
262.1) established the remaining race directly: an observer first recorded
the fake modem's clean stop, then `systemctl cancel` removed the pending
`replace-irreversibly` shutdown job, and the fake modem started again.
No real shutdown or modem stop occurred. This demonstrates that even the
irreversible job mode and a clean observer snapshot do not establish what
happened after that snapshot; keep the full previous-boot journal gate.
Runtime masking is not a sufficient substitute either: on both systemd
262.1 managers, `systemctl mask --runtime` returned success for a running
fake transient service, but after stopping it a fresh `systemd-run` with the
same name started it again. No real service was masked or stopped. Do not
use a successful mask command alone as proof that the modem cannot be
recreated after an observer snapshot.
The installed modem profile also has a one-start-per-boot guard. On fw12,
a fake service using byte-identical guard functions refused a normal second
start after canceling a fake shutdown; a read-only checksum of the installed
palmtop functions matched the tested functions. This mitigates a normal
profile restart, but does not prove the marker cannot be removed or bypassed
after the observer records it. The fixture itself was not run on the
palmtop: automatic approval review rejected it over possible interaction with
the live modem marker. The real marker remained present, and the modem
services remained active.
The running daily kernel's read-only `/proc/filesystems` inspection did not
list tracefs, and neither standard UFS trace-event directory was present.
Existing ftrace UFS events therefore were not available through those paths
on this boot; this does not establish the configuration of a future kernel.
The disabled arming draft now checks the recovery ledger, same boot and
modem invocation, CP ONLINE, masked sleep, pending markers, no active calls,
the owned inhibitor and fresh preflight time before creating an exclusive
attempt record and a checksum-bound transient unit. A separate disabled
pre-write cleanup draft stops only the verified unit, retains the resulting
unconfirmed observation and refuses cleanup after a possible image write.
Tests on the palmtop used fake modem services and disposable files, including
actual systemd collection of the stopped transient unit: systemd cleared its
invocation ID and unloaded it, so the durable observation now carries the
observer invocation for independent verification. The running modem was not
stopped, and these scripts remain uninstalled and gated.
An offline rollout draft now orders the independently checked observer arm
before any image-write intent and disarms it before pre-write cleanup. Its
five fake-backend tests cover failures before and after an uncertain arm and
retain state after a possible write. It remains an offline draft; the original
previous-boot journal gate remains in force.
A companion offline candidate-verification adapter reads the retained,
root-owned observation for the exact boot, modem invocation, observer
invocation and attempt, and recomputes its verdict. Fixtures reject stale,
mismatched and incomplete records. The adapter still requires the original
full previous-boot journal verification: an observer snapshot cannot exclude
a later restart or shutdown cancellation. Neither adapter has been used on
the running palmtop.
An offline #76 backend variant now uses the heartbeat-monitored kernel
stream, whose read-only palmtop check passed, before any candidate write. Its
fixtures reject a stale stream and changed source, and it still inherits the
strict previous-boot journal verifier. It does not yet monitor the writer
through the expected reboot or provide a complete live rollout.
An additional offline writer-monitor draft now watches the kernel stream while
the writer runs, terminates its process group if the stream fails before the
reboot announcement, and treats a later disconnect only as an unconfirmed
reboot gap. It drains the stream reader before accepting its log and refuses
kernel faults, missing announcements and incomplete reader output. Six local
fixtures pass, including faults on both sides of the announcement and a fault
discovered while the final stream output is drained. This is not
proof that remote writes stopped when a host process was killed. A disabled
backend now connects that monitor to the pinned writer and preserves the
inherited strict previous-boot journal verifier; fake-backend tests pass. It
has not run against the palmtop and does not authorize another diagnostic
reboot.

**Previous-boot journal gap (2026-11-07, offline).** The existing verifier
rejects a later `Started [systemd-run]` or CP ONLINE message, but it accepts
a later start that fails before the `Started` message. A disposable local
systemd oneshot produced a real `Starting` event followed by failure; when
placed after synthetic clean-stop records, the old verifier accepted it.
No real modem was stopped or restarted. A separate stricter verifier retains
the original checks and also rejects later structured start or restart events
and any subsequent unit-process message. Unit tests and the real failed-start
fixture pass; an isolated full #76 verifier fixture confirms that such a log
cannot create a success result. A separate disabled backend connects that
verifier to the existing monitored writer and shutdown observer, with four
fake-backend tests. These remain offline, and even the stricter journal cannot
prove that events absent from the retained journal never happened.

The on-demand GNSS work leaves the Location socket enabled, while the #76
series only checked that the modem was quiet. A disabled series draft now
also requires the GNSS services idle with no queued jobs or hang marker, and
the Location socket inactive and disabled or masked, both before changing
sleep policy and immediately before each suspend. Four fake-systemd tests
cover enabled, active, pending, unknown and failed-query cases. This prevents
normal socket activation during the test but does not rule out a direct
manual service start after the check. A reviewed way to record and restore
the Location policy across the diagnostic reboot is still needed; the draft
does not change that policy or run on the palmtop.
An offline Location-policy lifecycle now records the original enabled state
before disabling the idle socket and retains that record on uncertain
outcomes. Its restore path requires the modem online and independently checks
the enabled socket before retiring the record. Six fake-backend tests cover
normal ordering, a lost disable or enable response, changed policy and an
offline modem. It has no device backend and does not yet supply the persistent
record validation or integrate with the diagnostic reboot and rollback.
An offline record library now validates the original socket unit hash,
package version, boot, modem invocation and enable-link identity, writes a
root-only record exclusively with fsync, and refuses to retire a changed or
replaced record. Eight scratch-directory tests cover unsafe permissions,
symlinks, malformed records, replacement and uncertain writes. Retirement
still relies on cooperating writers for the final pathname check; the library
has no device backend and has not changed Location on the palmtop.
A separate read-only context checker now verifies the installed 0.2.12 GNSS
package, the live modem and GNSS state, the Location socket and its original
enable-link identity before preparing that record. Five scratch tests cover
changed links, package and service failures, unsafe directories and an
existing record. It also passed against the palmtop without writing a record
or changing services. The disable and restoration backends remain unbuilt.
The current palmtop boot unit was also checked read-only: it still runs
`omamobile-tegu-modem-up --phone --gnss`, and its installed 0.2.12 device
starter loads the GNSS modules and passes the eager-GNSS flag to the modem.
The existing #76 rollback restarts that boot unit, so it would bring `gnssd`
back outside the guarded on-demand session after the return boot. The new
Location-policy restore cannot assume the current sleeping GNSS wrapper will
survive a reboot. Coordinate the separately drafted 9a boot integration and
modem stop-witness packages, or provide an independently guarded post-boot
daemon transition, before treating #76 rollback as restoring the tested GNSS
state. None of these boot-path changes has yet been installed or qualified.
The installed `omamobile-device-tegu` 0.2.12 package has two altered files:
the modem starter and `reboot-to`. Their current bytes have been saved
privately under `logs/tegu-rollback-source-audit-20261107/`; they are not the
package's original files. The installed starter matches a later unversioned
source revision and supplies the active transient modem unit's `--stopped`
handler, so replacing it blindly could change shutdown behavior. The installed
modem 0.1.11 package has no altered files. Exact old package archives were
not found in the palmtop's checked caches or the checked official channels.
Its modem package source matches the installed manifest; the device package
manifest matches a mixture of historical source revisions, apart from two
compiled tools. A rollback must preserve the actual current helpers and
confirm the complete package and boot behavior before either boot-integration
package is installed.
Recovery-only packages have now been rebuilt on maclab with tests enabled,
without network access. The modem 0.1.11 payload and install hook match the
captured installed manifest. A separately versioned device 0.2.12-2 recovery
package matches the captured original manifest except that it deliberately
includes the two exact helpers that are currently installed; it also preserves
the original package's install hook and mirrorlist backup declaration. A
separate audit checked the complete payloads, modes, symlinks and package
metadata. The source, packages and audit are retained under
`out/tegu-modem-rollback-reconstruction-20261107/` with a `DO-NOT-INSTALL`
marker. This recreates the current development behavior, including its known
unconfirmed-stop latch weakness; it is a fallback artifact, not a qualified
release or authorization to install the new boot-integration packages.
An offline package comparison found that the proposed device 0.2.14 package
has the same payload file set as the original 0.2.12 package, with changes to
the modem starter, modem boot unit, device descriptor and version. Its
`reboot-to` matches the original packaged binary, rather than the currently
hand-replaced helper. The proposed modem 0.1.18 package also adds the NV
overlay and modem-policy files and changes the modem profile and CP helper;
the overlay is opt-in. These comparisons do not establish safe behavior when
the currently running modem is stopped after an upgrade: its transient unit
would call the newly installed stop code. That transition and a rollback
controller must be reviewed and tested before changing the live packages.
The running modem's existing latch has the current boot and `online`, but no
invocation ID. The proposed confirmed-stop handler requires that ID as well
as a matching stop witness and successful service result, so installing it
unchanged would leave the latch in place at shutdown and block the next modem
start even after a clean stop. Scratch tests of the actual old and proposed
handlers show that adding the correct invocation lets the proposed handler
accept a witnessed clean stop, while a different invocation, missing witness
or failed stop keeps the latch. The old handler also accepts the added line.
This is evidence for a possible migration, not a live migration or proof of
the actual modem stop: an atomic, guarded migration and package rollback
still need to be implemented and tested before installation.
An offline scratch-only migration primitive now saves the old latch and an
intent record before replacing it with an invocation-bound copy. Nine tests
cover changed or unsafe latch files, existing pending files, failed durable
writes, lost checks before and after replacement, and a successful migration.
It has no device backend or control-stream monitor. Its last check and rename
are not an atomic compare-and-swap, so it also requires serialization against
shutdown and all other latch writers; checking service state alone does not
provide that guarantee. No live latch was changed.
A second scratch-only prototype opens the existing latch without creating it
and appends through that open descriptor after recording the original. Unlike
pathname replacement, it cannot recreate a latch that the stop handler has
unlinked during the append. Ten tests cover that race, replacement by another
writer, partial append, changed data, failed checks and durable-write errors.
A partial append or loss of confirmation remains an uncertain result requiring
recovery; the routine has no live monitoring backend. A read-only palmtop
check confirmed the present latch has the expected old format, owner, mode and
link count and that the modem unit is running with a valid invocation ID.
The composed read-only preflight also passed on the palmtop: the original
shutdown helpers and installed package versions match the captured baseline,
the transient unit still calls those helpers, and modem and Location state
match the previously checked boot. It did not append to the latch or change
either package.
The running modem was started with the old profile, which supervises the
`rfsd | sed` log pipeline. Installing a new profile cannot change that
already-running shell. A real isolated systemd fixture using the old pipeline
and the proposed stop handler reproduced a shutdown failure when rfsd exited
during CP power-off: the old supervisor exited early, systemd reported
`exit-code`, and the latch stayed. With the new supervisor the same test
completed and cleared the latch. Therefore latch adoption alone is not enough
to qualify the transition. On the palmtop, read-only checks found one rfsd
and one matching log-pipe reader. Holding a separate write descriptor on the
old pipeline during the simulated stop also let the old fixture stop cleanly,
but this was only a host fixture: a bounded, independently monitored holder
and its failure behavior have not been designed for live use. In particular,
holding that pipe while the modem is normally running could hide an rfsd
failure from its supervisor. No pipe or service on the palmtop was changed.
A scratch-only bounded holder now watches separate process handles for the
supervisor and rfsd. It releases the pipe if rfsd exits before an observed
stop, the stop is aborted, a check is uncertain, or its deadline expires;
after an observed stop it holds until the supervisors exit. Twelve local tests
exercise those cases with real processes and a pipe. In a separate real
systemd fixture, that lifecycle held the old supervisor through the simulated
power-off and the proposed handler cleared the latch, while the unheld old
supervisor failed. The palmtop also has a separate namespace supervisor, so
the holder now tracks both supervisors and waits for both to exit; a nested
systemd fixture also passed. This is still a host
simulation: device-side pipe identity,
systemd state verification, startup, shutdown and recovery integration have
not been qualified for a live holder. A separate read-only palmtop check did
verify the modem unit's two supervisors, one rfsd and its one `sed` reader,
including matching pipe identities and live process handles. It opened no
write descriptor and did not start a holder.
An offline classifier now accepts only the same boot and modem invocation,
the expected running state, or a confirmed systemd `stop` job. Its local
fixtures cover changed identities and ambiguous jobs; a live-systemd fixture
exposed the `stop-post` substate, which is now covered too. The running-state
check passed read-only on the palmtop. A separate user-systemd test started
the holder after the modem and verified that `Before=modem` orders its stop
after the modem when both are stopped together. That test did not shut down
the machine or prove the ordering of an actual palmtop reboot.
The holder prototype now also requires a caller-supplied control check before
the stop: loss of control releases the pipe while the modem is running. Once
a stop is confirmed, it no longer depends on the host connection, which can
disappear during shutdown. Both branches passed process-and-pipe tests. The
live control channel and holder launcher remain to be implemented.
The scratch pipe-opening primitive also checks the actual open descriptor
against the expected pipe and revalidates the process identities. A local
fixture found that opening an anonymous pipe through `/proc` can succeed
even after its reader has gone, despite `O_NONBLOCK`; the primitive therefore
checks `POLLERR` for a lost reader before and after validation. Seven pipe
fixtures pass, including reader loss and pathname replacement. There is still
a race after those checks, so the holder now also monitors the reader's
process handle and releases the pipe if it exits. This primitive alone is not
a live launcher.
A combined local fixture now runs the holder in its own transient systemd
service, ordered after the modem at stop, using a nested old supervisor and
the real draft stop functions. It completed a simulated clean shutdown and
cleared the matching latch. A separate run removed its control signal before
shutdown: the holder stopped, while the simulated modem and latch remained
up. The fixture now uses a private Unix socket and the existing sequenced
heartbeat gate, with the same two outcomes. Separate socket tests cover peer
credentials, token errors, disconnect, unsafe directories and replacement.
The fixture's identities and heartbeat producer are scratch substitutes, not
the device's hardened launcher or its host-verified kernel-stream monitor.
The composed holder backend now takes a fixed snapshot binding the boot,
modem invocation, both supervisors, rfsd, reader and pipe; it repeats the
full checks before and after opening the pipe and owns all descriptors through
cleanup. Five backend tests cover changed identity, control loss, descriptor
cleanup and a simulated stop. It also passes the combined host-systemd and
socket fixtures. Its read-only context and bounded systemd query passed on the
palmtop, but no live launcher has been enabled.
The current effective pacman hook inventory also shows that the proposed
modem/device transaction matches the system udev-reload and enqueue-marked
hooks. The former would issue `udevadm trigger -c change` for the whole
system because the palmtop has no suppressing file; the latter can restart
marked services. No marked services were found in a read-only check, but that
can change. In a disposable, network-isolated maclab Arch ARM container,
explicit later `--hookdir` entries containing `/dev/null` overrides suppressed
those two hooks for a test upgrade while an unrelated daemon-reload hook and
the test package's own reload script still ran. The candidate modem package's
install hook independently requests a udev reload; applying new rules to
already-present devices remains deferred until a reboot. This is a container
fixture, not a live package transaction or authorization to bypass other
hooks; the actual effective hook inventory and service markers must be checked
again and the temporary hook directory must be controlled and verified.
The configured `/etc/pacman.d/hooks` directory is absent on the palmtop;
passing that nonexistent directory explicitly as `--hookdir` makes pacman
refuse the transaction. A second offline container fixture instead supplied
only the later temporary `--hookdir`, with the configured directory absent:
the two overrides still took effect and the unrelated system hook still ran.
A private root-owned `/run/tegu-modem-transition-hooks-20261107` now contains
only those two `/dev/null` hook overrides. Pacman's print-only checks with
that exact hook directory resolved both staged pairs, and the installed
package versions still match the original baseline. The directory affects
only transactions explicitly given its path and disappears at reboot; no
package transaction has been run on the palmtop.
A separate read-only audit checks the exact staged file set, package hashes,
owner, mode, link count, warning and receipt, as well as both hook symlinks.
Eight scratch fixtures reject replacement, unsafe permissions, extra files,
changed packages and changed manifests; the audit passed on the palmtop.
The four audited candidate and recovery packages are now staged, root-owned
in a new private (a local scratch directory, not in the repository) directory on the
palmtop, with a `DO-NOT-INSTALL` marker. Independent checks confirmed their
four hashes and permissions. Pacman's print-only dependency resolution listed
the intended candidate pair and, separately, the intended recovery pair; the
installed device and modem versions remain 0.2.12-1 and 0.1.11-1. Staging and
print-only resolution did not change the live packages or modem.
The exact four staged archives also passed a disposable offline maclab
container transaction: the recovery pair installed, the candidate pair
upgraded it, and the recovery pair then reinstalled. Pacman's full file
checks passed at each step, and the recovery starter matched the captured live
helper after rollback. The container lacked the palmtop's dependencies, so
that fixture skipped dependency checks; the separate palmtop print-only
resolution covered the real dependency set. No service or hardware stop was
tested by the container transaction.
A disabled transition-ordering prototype now records latch adoption first,
arms and verifies the Location recovery timer before masking the socket, and
holds the existing guard across the paired install and verification. It
restores Location and retires the timer only after the candidate checks pass.
Nine failure-order fixtures cover lost control, uncertain install, failed
post-install checks and failed restoration; none attempts automatic rollback
after an uncertain package operation. It has no live device backend and has
not changed the latch, socket or installed packages.
An isolated copy of the previously exercised Location recovery sources now
checks the installed GNSS 0.2.12 package and uses a separate runtime recovery
directory. Its nested source hashes and six guard/restore fixtures pass, and
the package-check adapter passed read-only on the palmtop. The recovery source
set has not been staged or armed; the modem transition still needs a complete
device backend, fresh protected-backup review and monitored one-shot runner.
The paired-package verifier now checks each installed version, `pacman -Qkk`
result and installed manifest. A container test with a modified local-channel
mirrorlist exposed that pacman prints legitimate backup-file notices on
stdout; the verifier now accepts only notices for that specific backup and
still requires zero altered package files. The actual upgrade and rollback
fixture passes with the local-channel file unchanged and no leftover channel
marker or `.pacnew`. A separate channel snapshot check passed read-only on the
palmtop, where the local channel is active; it will need to match again after
any package transaction.
The exact old-to-new shutdown transition was also simulated under local
systemd: it started the old nested supervisor and old helper, adopted the
scratch latch, replaced the stop files as an upgrade would, reloaded systemd,
and stopped with the separate monitored holder. The same fixture exercised
lost control. A separate baseline checker now requires the original installed
package manifests and permits exactly the two captured altered helpers; its
read-only palmtop check and four scratch tests passed. These are independent
checks, not a live modem-package upgrade.
A source-pinned one-shot runner and read-only host coordinator have now
passed their local boundary and source-integrity fixtures. The coordinator
then ran a full read-only palmtop preflight with the live kernel stream and a
fresh protected-partition comparison; it reviewed both prior GNSS recovery
attempts, the staged pair, existing modem and channel state, and stopped
before creating a new recovery directory or changing the latch. Evidence is
under `logs/tegu-gnss-ondemand-20261107/modem-transition-preflight-ff01e4efacb342b59d164119b52b4f49/`.
The independent post-transition review is prepared and its evidence checks
have local failure fixtures; it has not yet reviewed a real transition.
The monitored one-shot transition on 2026-11-07 stopped during latch
adoption: its final service-queue snapshot saw the unit list change. The
failure occurred after the latch append and fsync but before writing the
adoption completion record. An independent read-only review confirmed the
same boot and active modem, the invocation-bound latch matching its saved
original and intent, the original modem and device packages, active Location,
an untouched `safe` socket guard with no mask, and no package-install intent.
The prior and new recovery source sets remain intact. The one-shot claim is
retained and must not be rerun; finish or recover this specific attempt only
after reviewing its durable evidence and the cause of the queue change.
Evidence: `logs/tegu-gnss-ondemand-20261107/modem-transition-c0cdb6abf7e04a96b869b53b4bc27f67/`.
Three later read-only unit-inventory samples were stable, so they do not
identify what changed during the interrupted check. A bounded read-only retry
wrapper now retries only that specific inventory-change error, checks the
original boot and control stream around every attempt, and stops immediately
for marked units, other errors or lost control. Six scratch tests pass; the
wrapper has not been used for a live mutation.
The specifically reviewed interrupted attempt was then continued once under a
fresh protected-partition review and live kernel stream. Its reconciliation
record was written after rechecking the saved latch and the untouched guard;
the bounded queue wrapper handled only read-only inventory instability. The
guarded package transaction completed, Location was restored and the timer
retired. Independent post-checks confirmed the two installed package
manifests and files, unchanged local channel, matching latch and recovery
records, active modem and Location, and protected partitions matching their
backups. The palmtop now has development `omamobile-device-tegu 0.2.14-1`,
`omamobile-modem 0.1.18-1` and `omamobile-gnss 0.2.12-1`; it has not rebooted,
so the modem still runs the old in-memory supervisor. The package transition
does not qualify its next shutdown, modem-on suspend or the #76 test.
Evidence: `logs/tegu-gnss-ondemand-20261107/modem-resume-771103c1699d46cc92d49e8857eb8ab9/`.
After the upgrade, the independent transition review and two fresh read-only
modem pipe-context checks passed again. A separately supervised shutdown
holder, its pinned sources and its private control identity are staged under
`/run/tegu-modem-holder-20261107`; an independent audit verified the staged
files and context. A monitored one-shot test started it with the intended
systemd ordering, then deliberately closed its control channel. The holder
exited as designed; the modem and Location remained active and the protected
partitions still matched their backups. This checks control loss without a
modem stop or reboot; a clean shutdown remains unqualified.
Evidence: `logs/tegu-gnss-ondemand-20261107/holder-smoke-366afbb19d45491e92f67068b0de75d3/`.
An offline host-side writer barrier now waits until the verified holder is
ready before allowing a reboot request. Seven process fixtures cover a failed
start, loss before reboot, premature announcement and stream loss. An
offline copy of the diagnostic writer now contains that barrier, with a
separate one-shot holder controller. Shell and controller fixtures passed;
the composition has not been used to write images or reboot. An announcement
still cannot prove a successful shutdown.
The separate reboot holder was then staged and independently audited under a
live kernel stream. The modem remained online and protected partitions
matched their backups before and after staging; the holder was not started.
Evidence: `logs/tegu-gnss-ondemand-20261107/holder-reboot-stage-4ce0872d118d4601a9706854253c20e2/`.

**#76 diagnostic boot (2026-11-07).** The guarded writer verified all five
slot B image readbacks, the holder passed its readiness check and the palmtop
booted #76. The separately ordered observer recorded a clean modem stop, and
the strict previous-boot journal check agreed. The first post-boot verifier
stopped at 13 seconds because the desktop shell had not started; the
backlight service had also failed briefly and then restarted successfully.
After the desktop was up, a separate read-only verifier passed the candidate
boot, protected-partition backups, modules, smoke check and shutdown journal.
The boot marker remains in place, the modem boot service is disabled, and
sleep is still masked. No suspend cycle was attempted. The first verification
failure is retained alongside the later pass; neither is evidence of a UFS
fix. Evidence: `logs/tegu-gnss-ondemand-20261107/diagnostic76-2b2a40e275604f0b84f7ed2ba3cd4bff/`.
Location's on-demand socket is now temporarily masked in `/run` for the
modem-off test; its persistent enable link is unchanged. An eight-hour
same-boot timer will remove the runtime mask and restart the socket. The
independent post-check confirmed the mask, timer and original enable link;
no suspend has started. Evidence: `logs/tegu-gnss-ondemand-20261107/location76-6b51bdb704c847b99894935186250a93/`.
The first recovery-guard start failed because its helper still named the #71
inhibitor; no sleep occurred. A corrected helper was tested and started under
the same reservation and fallback. One guarded #76 WFI-only RTC cycle then
passed: the device reported 62 seconds elapsed, the host saw a paired suspend
entry and exit, and the recovery trace had paired host and device events with
no recorded overlap. Sleep masks and sleepd were restored afterward; the
recovery reservation and temporary Location mask remain. One wake does not
establish suspend reliability. Evidence:
`logs/tegu-gnss-ondemand-20261107/run76-one-2b027b894c944212b67b79c005180f44/`.
The completed one-wake network helpers were then retired under a fresh
fallback. A separate 300-cycle #76 WFI-only diagnostic series stopped after
35 paired wakes when the host log connection reset. The host stream contains
35 entries and exits, and independent trace checks found balanced host and
device events and the expected clock readbacks on all 35. No captured line
establishes why monitoring stopped; the 300-cycle test did not pass. The
modem was intentionally off, so these wakes do not qualify everyday suspend.
Evidence: `logs/tegu-gnss-ondemand-20261107/run76-series-bdbec611250742d98198c4c084870b57/`.
The automatic restoration watcher stopped on the uncertain result. A separate
single-shot observer owns the one delayed response check; preserve the
reservation and do not compete with that check or start a new test.

**#76 36th wake: repeated UFS failure (2026-11-07).** The delayed observer
found a new boot. The archived console's last eight completed exits match the
old boot journal within 0.059 seconds; after those 35 series passes, it records
another suspend entry followed by 20 failed `DME_LINK_STARTUP` attempts
across five host initializations and one SysRq reset. Every pre-link PHY
calibration returned zero, and all 20 sets of HCI_MISC readbacks were `0xd00`.
The failure segment recorded five paired device resets and five paired host
resets, with no host/host or host/device overlap in the recorded trace. This
does not exclude unlogged activity or identify why startup failed. The
recorded reset entries and exits all name the same task; each device-reset
callback returned `-95`, and each host reset returned generic result `1`.
The palmtop was responsive on a new #76 boot, root was read-write, sleep remained
masked, and the protected NV partitions matched their backups. Its old-boot
recovery reservation and sleepd ownership record were retained for review.
Evidence: `logs/tegu-gnss-ondemand-20261107/collect76-failure-dd20006355c74456b87f4ab261227d6b/`.
An independently checksummed review confirmed the new boot, unchanged slot B
mapping, clean current kernel, matching protected backups and five recovery
events in the rolling 24-hour window. The consumed reservation was recorded
with a durable receipt and retired without refunding its ledger entry; the
stale sleepd lease was cleared only after confirming the daemon active and
sleep targets masked. The ledger is unchanged. Evidence:
`logs/tegu-gnss-ondemand-20261107/reconcile76-failure-0d0e42f235bf4e0db1c423355d29c455/`.
The saved daily #7 images were then written and read back, and the daily boot
passed the strict original modem-shutdown, module and protected-partition
checks. Under a fresh one-use recovery reservation, the modem and sleep
daemon were restored and verified; the reservation was cleanly released and
the temporary recovery markers cleared. Location's enabled socket is active.
The protected NV backup and required desktop smoke checks passed after the
modem start. The ledger retains the consumed #76 event; suspend remains
masked because this failure is unresolved. Evidence:
`logs/tegu-gnss-ondemand-20261107/restore76-failure-446297fdf0e84ac8a34198b78e411892/`.

A separate timestamp audit compared the #76 preflight and 35 completed series
wakes with all 20 failed link attempts. From the pre-link snapshot to the
link-ready snapshot, the successful range was 2.191–3.356 ms and the failed
range 2.481–2.744 ms; the first failed attempt was 2.549 ms. From link-ready
to the controller result, successful attempts took 23.086–23.198 ms and failed
attempts 104.977–105.025 ms. These are log timestamp differences, not direct
hardware measurements: the overlap in the first interval does not prove the
PHY was in the same state. The audit rejects missing entries, exits or results
and an altered success result. Evidence:
`logs/tegu-gnss-ondemand-20261107/timing76-analysis-20261107/`.

An offline PHY-state prototype combines the deferred pre-link state change
and calibration in one PHY notification, under the generic PHY mutex. A
fixture compiled from the Samsung PHY callbacks shows that two concurrent
notifications each use the pre-init table, and checks wrong-device, unpowered
and calibration-error paths. This addresses the demonstrated state-table
interleaving only: it does not serialize the host-controller reset itself,
prove the APB clock hypothesis, or qualify a kernel for device testing.
Fixture: (a local scratch directory, not in the repository).
An isolated three-file source prototype uses that atomic notification only
for the diagnostic zumapro system-resume path and retains the existing
fallback elsewhere. The generated host callback passed clock readback and
failure-injection fixtures, and both changed ARM64 objects built with `W=1`
on maclab without warnings using the same configuration as #75. Source and
output: (a local scratch directory, not in the repository) and
(a local scratch directory, not in the repository). This remains an unbooted
experiment: concurrent host resets and their lock ordering still need review.
A whole-tree comparison found only the three intended source changes among
102,607 paths. Strict checkpatch reported no code-style issues with the
commit-message check disabled for this uncommitted draft.
The generic `phy_notify_state()` helper returns success when a provider lacks
the callback, so this prototype also needs a fail-closed provider capability
check before it could be tested; a successful notification alone does not
prove calibration ran.

A second unbooted prototype replaces that optional notification with a new
`phy_calibrate_state()` provider operation. It fails with `-EOPNOTSUPP` when
the PHY or operation is absent, and its Samsung implementation checks the
zumapro provider, requested state and PHY counts while holding the generic
PHY mutex. Fixtures compiled from the actual helper and provider exercise a
missing PHY or operation, wrong state or provider, bad power count, callback
errors and two simultaneous calls. Host fixtures cover target selection,
fallback, clock readback and failures. All pass. The four changed source
files build as ARM64 objects on maclab with `W=1`, without warnings and with
the same configuration as #75; strict checkpatch finds no code-style issues
with commit-message checking disabled. A whole-tree audit found exactly the
four intended changes among 102,607 paths. Source and output:
(a local scratch directory, not in the repository) and
(a local scratch directory, not in the repository); fixtures and patch:
(a local scratch directory, not in the repository). This diagnostic API is a research
prototype, not an upstream proposal or a device-ready fix. It does not prove
the APB hypothesis or serialize the whole HBA reset; the earlier defer-init
notification also retains its optional-callback semantics. Lock ordering and
all capability checks need review before any device test.

The Samsung provider caches its lane count at PHY init, while a later
`phy_set_bus_width()` changes a separate generic attribute. Its calibration
loop returns success without per-lane work if that cached count is zero. A
fixture compiled from the experimental provider reproduced that zero-lane
success before adding a target-only check. The revised callback rejects zero,
more than two, or a cached count different from the generic bus width, and
its fixture checks valid one- and two-lane cases as well as the failures.
It also rejects a missing pre-init table or calibration-complete callback;
the unguarded provider returns success for an absent table, demonstrated in
the fixture. These null cases are hypothetical for the compiled zumapro
provider, which supplies both. The revised ARM64 provider object builds with
`W=1` without warnings; strict checkpatch passes. This identifies a conditional
source-level gap, not the observed #76 cause: its log did not record the cached PHY lane count. The
generic bus-width setter itself is not protected by the PHY mutex, so this
check alone does not serialize a concurrent bus-width change.

**Failed lane-query error path (offline, 2026-11-07).** The #76 Exynos host
initializer ignores both available-lane DME_GET return values. The UFS core
sets the output to zero on a failed local DME_GET, and the Samsung PHY caches
the bus width during init. A fixture compiled from the actual #76 host, PHY
init and PHY calibration callbacks reproduces a failed RX query followed by
zero-lane calibration returning success and advancing state when the initializer
is called in isolation. A later call-path review found that zumapro's preceding
pre-link callback queries and validates both counts before calling that
initializer. Without concurrent changes, that normal path cannot reach the
fixture's failed-query case; reachability has not been established. The #76
captured kernel log has no matching available-lane DME_GET failure line, though
absence of a line is limited by the captured log's completeness.

An isolated #76-based zumapro-only draft returns a failed RX or TX query and
rejects zero, mismatched or greater-than-two lane counts before changing the
PHY, without issuing the existing WARN for an invalid zumapro count. A fixture
compiling the actual draft covers both failed queries, invalid counts, warning
behavior, cached counts, deferred calibration, notify and power-on failures,
and the unchanged non-target behavior. Strict checkpatch passes. Its source
and output are (a local scratch directory, not in the repository) and
(a local scratch directory, not in the repository) on maclab, with local scripts in
(a local scratch directory, not in the repository). The changed host object built on maclab
with `W=1` and no warnings, and a whole-tree audit found only that host change
and its safety marker across 102,607 paths. This draft is unbooted and is not
a fix for the recorded UFS failure.

The published kernel tip `29a7a9326bf0` has the same unchecked calls inside
the initializer, and the same preceding zumapro lane validation. A separate
fixture compiles the public host and Samsung PHY callbacks in isolation and
reproduces the zero-lane success, without demonstrating a reachable normal
call path; a narrow public-source draft passes the
query failure, invalid-count and non-target fixtures. Source and scripts:
(a local scratch directory, not in the repository). The separate maclab checkout is at
that exact commit, and its modified host object builds with `W=1` without
warnings; `git diff --check` passes and only the host source and untracked
safety marker differ. The build's `olddefconfig` updated the #76 configuration
for the newer source, so it is not byte-identical to the diagnostic config.
Source and output are (a local scratch directory, not in the repository) and
(a local scratch directory, not in the repository). The public-source draft is
unbooted and unsubmitted; its practical effect and relevance to suspend have
not been established.

**PHY lane observation draft (offline, 2026-11-07).** An isolated #76-based
provider change logs the already available state, cached lane count, generic
bus width, pre-init table presence, completion-callback presence and return
code. It adds no register read or write, but printk can affect timing. A
fixture compiles the actual callback and checks two-lane success, zero lanes,
timeout, absent table and a non-zumapro provider without changing their tested
return or state behavior. A second fixture compiles both baseline and changed
callbacks and compares their return, state and simulated writes across 96
combinations; all match. The ARM64 object builds with `W=1` and strict
checkpatch passes. An offline evidence parser matches each observation to a
pre-link attempt and rejects missing, extra or malformed observations;
synthetic records inserted into the #76 capture test the parser only, not the
actual lane count in that run. Source and output are
(a local scratch directory, not in the repository) and
(a local scratch directory, not in the repository) on maclab; scripts are in
(a local scratch directory, not in the repository). A whole-tree audit found only the
provider change and a `DO-NOT-PUSH` marker across 102,607 paths. The full
build completed with a unique fixed #77 identity. The first independent audit
correctly stopped because the release suffix was missing; rebuilding with the
exact #76 release fixed that mismatch. The second audit stopped on one
parallel-build warning split across lines; the reconstructed source line and
warning match the previous build, and both logs have 1,138 warnings of that
class. The audit was extended to reconstruct only that attributable split and
reject an unattributed one. It then passed configuration, release, build
identity, warning baseline, module symbols, device tree and image checks. The
Image SHA256 is `29a5332ff421ec7d8de3c263b3086d2d1e8a9a547a8bbf874cfa46c5f8a1d29d`.
An offline packing script passed disposable-image tests for bad checksums,
unchanged images, deterministic packing and disabled device operations. The
real image was packed twice identically into
`out/tegu-suspend-lane-observe-20261107`, and an independent kit audit passed
AVB, checksum and guard checks. The manifest and audit also cover the release
file used by the writer; a changed release is rejected even if its manifest
hash is recomputed. Negative fixtures reject missing guards or manifest
entries, altered images, an enabled push and an invalid AVB footer.
This is unbooted observation, not a fix or a device-ready kit. A returned calibration-complete
bit can still be stale, and logging does not
prove that a physical write reached the PHY or exclude untraced activity.

**Current-boot modem shutdown preparation (2026-11-07).** The restored daily
boot runs `omamobile-modem 0.1.18-1`; `pacman -Qkk` reports no altered package
files. Its active modem service started after the installed profile's file
mtime. The launcher sources that profile, whose installed code includes the
per-invocation orderly-stop intent and keeps the rfsd supervisor alive on an
expected exit. The persistent modem latch matches the current boot and service
invocation and records ONLINE. The exact installed profile's three supervisor
fixtures and four stop-witness fixtures pass. A user-systemd fixture using
the installed profile's actual start/stop functions and installed stop
verifier, fake rfsd and fake CP passed a clean stop without a separate holder
and retained the latch for a simulated failed CP stop. This supports reviewing
a simpler orderly reboot on this fresh supervisor; it does not prove how the
real CP or kernel will behave. Keep the modem running until systemd shutdown,
retain the live stream and independent previous-boot journal check, and treat
an unconfirmed stop or reboot as uncertain. Scripts and copied public package
code: (a local scratch directory, not in the repository).

A read-only preflight now checks the installed profile, launcher and stop
verifier hashes, package integrity, current modem process identity and start
time, current-boot invocation-bound latch, CP ONLINE state and a stable
service snapshot. Its ten failure fixtures pass, as did a read-only check on
the current daily boot. The timestamp and source checks support provenance;
they do not prove the process's memory or a successful hardware shutdown.
An alternate offline #77 adapter uses that check and the already tested
monitored writer, shutdown observer and strict previous-boot journal gate,
without the old-supervisor holder. A scratch-only simulation receipt is
checksummed and independently audited; the one-shot controller refuses missing
or invalid simulation evidence, retains an uncertain result, and refuses
retries. The earlier writer polled SSH after requesting reboot, contrary to the
unresponsive-device rule. The #77 writer draft instead makes one reboot
request and waits without reconnecting; a fixture checks both success and
failure of that request. The host monitor still treats stream loss as
unconfirmed and requires a separate new-boot check. The verifier waits a
further 80 seconds before one candidate observation to allow the desktop to
start. Composition, monitoring and one-shot failure fixtures pass. None of these adapters has
written or rebooted the palmtop; a fresh full preflight and rolling recovery
budget review remain required before any live test.

An offline #77 lifecycle adapter retains the earlier strict shutdown verifier,
requires #77's exact `uname -v`, and selects the separately audited #77 kit.
Its fixtures reject the #76 identity and the previous modem, backup, kernel,
ledger, boot and shutdown failures. Mocked composition checks the #77 kit
audit, stream checks, verified holder barrier and uncertain-writer cleanup.
Scripts: (a local scratch directory, not in the repository). These are disabled drafts;
they do not establish a fresh current-boot preflight, holder smoke, recovery
reservation or live writer safety. The pre-existing
monitored writer terminates the local process group on stream failure, but
an in-flight remote I/O may already be running and a partial image remains an
uncertain write. The draft has not been run against the palmtop.

The separate #77 single-wake preparation is also offline. Its helper bundle
pins the #76 source bundle, uses #77-specific boot and unit names, and uses
the corrected 15-minute one-wake fallback. The previous recovery-budget
helper checked several host guards but omitted the `x-tegu-udp71-long` host
guard. That guard stops the sleep test; it is not itself a reset command, but
an active leftover could interfere with another test. The #77 draft refuses
a reservation or refund while either that old guard or the new #77 host guard
is active. The first generated #77 bundle also inherited stale #71 inhibitor
names inside the awake kernel-log guard, the same mismatch that blocked the
first #76 attempt. It has been corrected to #77, and the actual guard's
storage-fault fixture and bundle reproducibility checks pass. Disposable
fixtures cover both host guard names, recovery-ledger and clock failures,
guard startup, arming, cleanup, Location restoration and same-boot evidence. The host-side one-wake draft also requires one complete, balanced
two-lane calibration observation and successful link startup before it can
record a pass. Source and fixtures are in
(a local scratch directory, not in the repository); the helper bundle is
(a local scratch directory, not in the repository). Nothing has been staged on the palmtop. A full
lifecycle review and fresh recovery-budget check remain before live use.

An additional offline write-sequencing prototype checks the host-verified
stream gate before and after each bounded image chunk, sync and readback. It
verifies all source hashes before the first write and checks each complete
readback before the next image; it never requests a reboot or clears a write
marker. Eight fixtures using temporary regular files cover a lost stream
during a write or sync, a short write, a bad readback, a changed target and
an invalid source. One uses the real control-heartbeat reader and closes its
pipe while a fake write is blocked; no subsequent chunk was submitted after
the write returned. A stream failure can be observed only after an in-flight
I/O returns, and a partial image must be treated as an uncertain write. This
prototype has no block-device backend, pinned device identity, live rollout or
reboot authorization, and does not replace the previous-boot journal gate.

The offline #77 lifecycle has since been extended with a per-wake lane gate,
a separate 300-wake trace/timing audit, recovery-reservation retirement and
a guarded daily-kernel/service return. The daily writer's post-reboot SSH
polling was removed; a delayed independent verifier must establish the new
boot. The controller stops at any unconfirmed phase, retains evidence, and
uses at most one delayed connectivity probe if it needs physical help. Fake
service, slot-B writer, marker, audit and ordering fixtures pass. This remains
an unbooted, WFI-only modem-off diagnostic, not a demonstrated suspend fix.
The previous recovery ledger had five recent events; a fresh synchronized
clock and ledger check must pass before any live action.

**Interpretation of the #76 reset trace (offline source review).** The
`device exit ... ret=-95` entries report `-EOPNOTSUPP` because the Exynos
variant supplies no `device_reset` callback; they do not report an electrical
reset failure. Separately, the Exynos HCE-enable path pulses the UFS device
reset through `HCI_GPIO_OUT`. The trace's generic device-reset counter does
not surround that HCE-specific pulse. The balanced counters therefore do not
prove that every physical reset pulse was serialized, and they do not explain
the link-startup failure. This is a source-level interpretation, not a new
hardware observation.

**Limit of the public lane-query draft (offline, 2026-11-07).** The draft
returns an error from Exynos pre-link before initializing the PHY when a lane
query fails, but the published `ufshcd_link_startup()` ignores the PRE_CHANGE
callback's return and still issues link startup. A fixture compiling that
actual public core function, with hardware calls mocked, confirms it can even
return success if the subsequent mocked link startup succeeds; POST_CHANGE
errors are propagated. The host draft alone therefore prevents invalid lane
initialization, but does not guarantee the whole startup fails closed. The
fixture is (a local scratch directory, not in the repository); it
is source-level evidence, not a reproduced hardware failure. The #77 test
kernel separately checks this callback on its target resume path.
An offline core-only candidate propagates PRE_CHANGE errors for zumapro before
issuing a link command, while retaining the existing behavior on other hosts.
A fixture compiling the actual modified core function checks a failed target
callback, unchanged non-target behavior, link retries and POST_CHANGE errors.
It is an unbuilt source draft at
(a local scratch directory, not in the repository); it does not
establish whether all zumapro callback errors should be fatal, and has not
been combined with a device test or a proposed patch.
A subsequent call-path review further narrows the lane hypothesis: both #76
and the public zumapro descriptor call `zumapro_ufs_pre_link()` first. It
returns on a failed query or invalid counts, and the only call to
`exynos_ufs_phy_init()` follows it. Without concurrent mutation, successful
validation leaves nonzero cached lane counts, so the initializer's unchecked
query branch is not entered. The isolated zero-lane fixture did not model that
caller. Concurrent mutation has not been established either; do not present
the initializer-only fixture or its draft as a demonstrated reachable fix.
The generic core's ignored PRE_CHANGE return remains separately established.
A combined fixture now compiles the actual public zumapro pre-link callback,
Exynos caller and PHY initializer together with mocked hardware. RX and TX
query failures and invalid counts stop before PHY init; a valid query reaches
PHY init using the cached values with no extra query. This confirms the
sequential call-path limitation; it does not model concurrent callers. See
(a local scratch directory, not in the repository).
The broad target-specific core candidate must not be used as a fix: the earlier
S1-T traces recorded `T_PEERDEVICEID` failing in the second PRE_CHANGE on good
wakes, after the first link startup succeeded. Treating every such callback
error as fatal could turn that currently recoverable sequence into failure.
The candidate is retained only as a fixture for the propagation mechanism.
The same combined fixture against #76 also passes its normal and deferred PHY
paths: (a local scratch directory, not in the repository).
A separate fixture replays that first-success, second-PRE_CHANGE-error,
second-link-error, retry-success shape using the actual public core function.
The original core returns success in this mocked sequence; the broad candidate
returns the second callback's error before issuing its link command. This is
a control-flow demonstration, not a hardware reproduction:
(a local scratch directory, not in the repository).
The #77 zumapro descriptor sets `UFSHCD_QUIRK_PERFORM_LINK_STARTUP_ONCE`,
so its core skips the automatic second startup after a successful first one.
A fixture compiling the actual #77 core confirms that distinction and also
confirms that a failed first startup still retries and a later PRE_CHANGE
error still stops the target diagnostic. The earlier second-start example
therefore illustrates the broad public change's risk, but not an automatic
second start on the #77 configuration. It does not prove live retry behavior
or make the broad change safe. Fixture:
(a local scratch directory, not in the repository).

**Later CPU-idle comparison, offline only.** While the #77 WFI series runs,
a disabled C2 runner draft was derived from its pinned single-wake script. It
retains the lane, storage, NFC, RTC, modem and GNSS gates, refuses to change
CPU-idle controls, and requires all eight state1 controls enabled plus at least
one new s2idle state1 entry on each cycle. Disposable counter fixtures reject
disabled, invalid, decreasing and unchanged counters and an offline CPU;
`bash -n` passes and a top-level guard prevents any live execution. It is not
integrated, is not a device-ready test, and cannot advance until the current
WFI run and its independent audit pass, the daily system is restored and a
fresh safety review is completed. Source and fixtures:
(a local scratch directory, not in the repository).

**#77 WFI series failure (2026-11-07).** The diagnostic kernel completed one
separate wake and 15 of the planned 300 modem-off wakes. The 16th series wake
failed during UFS link startup and the recovery guard reset the palmtop. Its
archived console records five host initialization attempts, each with four
failed link startups. All 20 corresponding PHY observations reported state 0,
two cached lanes, bus width two and a successful calibration callback. Thus a
zero cached lane count does not explain these recorded attempts; the log does
not prove that the hardware accepted every write or identify the physical
cause. The recorded host and device-reset intervals did not overlap, but this
does not exclude activity that was not instrumented.

Reusing the #71 timing analyzer on the #77 archived console found 16 complete
successful startup records and 20 failed ones. The reset-to-pre-link intervals
overlap (1.119–1.211 ms successful; 1.140–1.194 ms failed), as do the
pre-link-to-calibration-return intervals (2.090–2.598 ms successful;
2.451–2.777 ms failed). Link-ready to reported result was 23.095–23.157 ms
on the successes and 104.977–105.444 ms on the failures. These are printk
intervals from one run, and a UIC result of 1 is a reported command failure,
not proof of a software completion timeout or of a particular physical fault.

The post-reset protected-partition backup check passed and slot B remained
marked good. The failed wake consumed a recovery-ledger entry; it must remain
in the ledger. Captures and the independently checked failure audit are under
`logs/tegu-gnss-ondemand-20261107/collect77-failure-*`; the audit's negative
fixtures are in (a local scratch directory, not in the repository). The palmtop is currently
available for Dave to use, with the diagnostic kernel, suspend disabled and
the modem offline. Restore and revalidate the daily system after he returns it;
do not start the C2 comparison on the strength of this failed WFI series.

An offline return-review helper verifies the checksummed #77 failure capture
and requires a newly collected same-boot state with the actual rolling recovery
count at most four. Its fixtures reject the historical count of five, missing
or active guards, changed boot or ledger and failed health gates; they do not
rewrite the count. The helper has no device entry point. It is preparation,
not proof that the device state is unchanged or a substitute for fresh backup,
marker, clock and live-state checks after Dave returns it. Source and tests:
(a local scratch directory, not in the repository).

**PCS write-order experiment (offline, 2026-11-07).** Google’s G4 pre-link
table interleaves RX and TX PCS entries and visits both lanes for each entry;
the #77 host groups the writes by direction and lane. An isolated #77-based
draft changes only their order when the existing deferred-resume flag is set.
It retains the existing DME access path, values, error returns and original
non-deferred path. A compiled callback fixture compares the complete PCS
attribute/selector/value sequence against the 38.4 MHz vendor table for one
and two lanes at four modeled clock rates, checks every injected DME-write
failure, and compares non-deferred calls against the original. The original
two-lane sequence and an altered write fail the ordered comparison. Strict
checkpatch and an isolated `W=1` host-object build on maclab passed without
warnings; its configuration matches #77. An independent comparison of
102,608 source-tree paths found only the UFS host source changed. The first
full build completed but failed the independent audit: its source snapshot
lacked the previous release suffix, even though configuration and module
symbols matched. Its image was not staged. A corrective build supplies the
exact #77 suffix explicitly. It completed and passed the independent audit:
both build logs, final release and #78 identity, module symbols, device tree,
diagnostic strings and warning baseline matched the requirements. Its Image
SHA-256 is `8d79cc8877a9f6e1dfe8e028265873cf9cb054e2823e7db832f447328d0ab9b2`.

This is an unbooted diagnostic hypothesis, not a suspend fix. The vendor
uses direct PCS accesses with an auxiliary selector, whereas this draft still
uses DME commands; equal modeled sequences do not establish equivalent hardware
effects, a safe selector, or the cause of #77. In particular, pre-link errors
and the core's existing retry behavior still need review before any device
test. The local draft and fixtures are in (a local scratch directory, not in the repository);
maclab uses the separate (a local scratch directory, not in the repository) and
(a local scratch directory, not in the repository) directories, marked DO-NOT-PUSH.
The audited image was packed twice identically into an offline kit at
`out/tegu-suspend-pcs-order-20261107`. Its independent audit verified the
kernel inside the boot image, AVB signature and unchanged non-kernel images;
device-writing commands remain disabled. The packer and kit auditor also
passed disposable-image, bad-checksum, missing-guard, altered partition-image
and broken-AVB fixtures. This establishes the offline artifact, not a
successful device boot, suspend result or fix.

The 2026-11-07 14:08 UTC repository poll found the public kernel tip at
`fe12fd24f7f8`, five commits after `29a7a9326bf0`. The comparison lists only
board device-tree changes for akita, panther, husky and oriole; it lists no
UFS driver, Samsung UFS PHY, generic PHY header or zumapro change. This is a
source comparison, not a build or device test of the newer tip.

**PHY reference-count limitation (offline source review).** An upstream
[Exynos UFS patch discussion](https://lkml.iu.edu/hypermail/linux/kernel/2604.3/11839.html)
points out that `power_count` is shared by PHY consumers and read without the
PHY mutex; it proposes tracking the host's own reference instead. The #77
diagnostic also reads `init_count` and `power_count` without holding that
mutex, so its observed values are not proof of exclusive ownership or of a
stable value throughout calibration. The #77 and #78 overlaid device trees
match; an offline audit finds one `phys` reference to their UFS PHY, from the
UFS host. Its missing, duplicated and wrong-provider fixtures pass. That
weakens a second device-tree consumer hypothesis for this artifact, but does
not exclude concurrent operations by the same consumer, runtime changes or
unlogged activity. Neither the upstream API concern nor the reference counts
establish the cause of the recorded failed wake. Audit:
(a local scratch directory, not in the repository).

**Deferred flag after a failed wake (offline source review).** In #77 and the
unbooted #78 draft, the system-resume callback sets `test_phy_deferred`; the
host clears it only after successful post-link configuration. On an exhausted
link-startup failure the resume path calls the variant's suspend callback,
clears `pm_op_in_progress` and returns the error without clearing that flag.
The #77 console records the failed resume returning before the guard reset,
but does not show a subsequent UFS recovery attempt before the reset.

If a later non-PM recovery did reach pre-link with that flag still set and
PHY counts of init=1, power=0, the diagnostic's PHY initializer would return
`-EBUSY`; outside PM the #77 core ignores the pre-link callback's error and
still issues the link command. Separate fixtures compiling the actual host
and core functions exercise those two conditional paths with mocked hardware:
(a local scratch directory, not in the repository). This is a
recovery-path hazard to resolve before another diagnostic deployment, not a
demonstrated cause of the 20 failed link attempts or proof that the subsequent
recovery occurred. The host fixture also compiles the actual variant suspend
callback: in a modeled link-off failure with one powered PHY reference, its
PRE_CHANGE does nothing, POST_CHANGE powers the PHY down and leaves the flag
set, and a later non-PM pre-link rejects the resulting modeled counts. It does
not establish that those counts were observed after the live failure. The
#78 offline kit stays disabled. Simply clearing the flag is not a sufficient
repair: with modeled init=1 and power=0, the ordinary host path calls
`phy_init()` again. The actual #78 generic `phy_init()` increments the init
count to two without invoking the provider's initialization callback, as an
independent compiled fixture confirms. The modeled host path likewise retains
the old reference. An ownership-balanced recovery design and failure-path
tests are needed; neither fixture establishes a live PHY state or a fix.
Fixture: (a local scratch directory, not in the repository).
Two more fixtures compile the actual generic reference functions and Samsung
provider callbacks. With a modeled post-init state and an existing init
reference, an extra init leaves that state unchanged; Samsung power-on in
that state skips pre-init calibration. The modeled last exit and a fresh init
reset the provider state, but these fixtures do not prove that an arbitrary
live reference belongs to this host or authorize dropping it. They demonstrate
why a fix must track ownership, not just balance global counts by inspection.
Fixtures: `test-phy-reset-state.py` and `test-phy-poweron-state.py` in the
same directory.

### The retry loop resets the device every 108 ms: the link-wait experiment (2026-11-07)

Re-reading the two newest archived failure consoles (`/var/log/omamobile/ramoops/console-1107-025025.txt`, `console-1107-063153.txt`, both from Codex's #77-lineage diagnostics) against the core's `ufshcd_link_startup()` gives one mechanism that fits every dead wake recorded so far, on every kernel tried:

- A wake's first link startup after the host and device reset fails with result 1 after about 105 ms (the host's own link-startup timer; the good wakes link in about 23 ms).
- The core's retry (`if (ret && retries && ufshcd_hba_enable(hba))`) runs `ufshcd_hba_enable()` at once: a host software reset and, through `exynos_ufs_hce_enable_notify()`, the device's RST_n pulse (`exynos_ufs_dev_hw_reset()`, 5 µs low). The trace shows the next reset in the same millisecond as the failure, pre-link 1.1 ms after it and the next DME_LINKSTARTUP 1.4 ms after that.
- So the device gets about 108 ms between two resets, twenty times in a row (four attempts per host init, five host inits), and the host's PA, DL and DME error histories stay empty: the host hears nothing from the device at all. A UFS device still booting after its reset answers nothing, and is reset again before it can.

Hypothesis: on some wakes the Micron device (MT128GBCAV2U31) needs longer than the link-startup timer to come out of its power-down reset; the retry loop then resets it again before it is ready, every time, and the "dead" storage is a device that never got the time. This fits the intermittence (no software difference between a good and a bad wake), the identical 105 ms failures, the empty error histories, and the spm_lvl 3 case (a failed hibern8 exit also ends in `ufshcd_reset_and_restore`, the same loop). It is a hypothesis; the test below decides it.

Experiment, kernel `#90` (`uname -v`): the daily tree ((a local scratch directory, not in the repository) on omb, as it built #7 plus the 11-03 UFS resume trace and register dump, copied to (a local scratch directory, not in the repository), output (a local scratch directory, not in the repository)) with one change in `drivers/ufs/core/ufshcd.c`: after a failed link startup's `ufshcd_hba_enable()`, the loop sleeps before the next attempt, 100 ms, then 400 ms, then 1600 ms, and logs `link-wait: N ms after the reset before link startup`. Nothing else changes; a good wake runs exactly as before. The diff is `logs/tegu-linkwait-20261107/linkwait.diff`.

Expected if the hypothesis holds: a wake that would have died logs `startup=1` once or twice, then `link-wait: 100` or `400`, then a successful startup, and the series goes on (the cycle line shows `linkfail 1 linkwait 1`). Expected if it doesn't: the same 20 failures, each a little later, and dead storage as before; then the device really is unreachable and the cause is elsewhere (power, reset line, refclk).

Series: `device/tegu/bringup/sleep-series.sh` on the palmtop (300 RTC-woken 60 s `systemctl suspend` sleeps, spm_lvl 5, `WFI=1`: core power-down off, as the runs without silent no-wakes; Wi-Fi kept, NFC hook, modem not started; the modem boot unit's state is recorded at the start and put back as found; the modem check is `systemctl is-active omamobile-modem`), driven by `device/tegu/bringup/sleep-series-loop.sh` on the laptop (captures the kernel journal and dmesg on a dead-storage wake, recovers with sysrq, restarts the series, at most 3 recoveries per run; a silent hang messages Dave and stops; a count every 25 wakes). Push and start: `logs/tegu-linkwait-20261107/run.sh` (the kit, `kit_restore night` first, the backup `kit-backup-linkwait`). First wake attended at the laptop. Rules: AGENTS.md section 1, and Derek's three conditions on #409 (one attended run of anything new, a capped automatic recovery with the next boot's ext4 recovery recorded, the recovery script in `device/tegu/bringup/`).

State found on the palmtop before the run (2026-11-07 ~08:00 MST): Codex's #77 diagnostic kernel (same release string as the daily), `sleep.target` and `suspend.target` masked, `omamobile-tegu-modem-boot` disabled, `omamobile-modem` masked at runtime, boot reason `watchdog` (the #77 recovery), pstore empty, root rw, `/var/lib/omamobile/suspend-test/auto-recovery-ledger` with five entries in 24 h (Codex's ledger, left as it is; this run counts its own recoveries).

Progress, 2026-11-07 11:07 MST (palmtop clock): #90 pushed at 08:21, the series started 08:23; 147 of 147 wakes clean (RTC wake every time, no UFS error, no `link-wait` yet, so no retry has been needed, root rw). Past the longest earlier clean stretch (135 on the daily, 11-03). Two watcher mistakes on the laptop side, neither touching the palmtop's run: a truncated poll read as "series ended" (a reboot was sent but landed in a sleep window; fixed: only a complete answer counts), and seven minutes of missed polls read as a silent hang (the USB link is up for only about 9 s of each 67 s cycle; fixed: the watcher pings once a second and asks inside the window, and the hang threshold is 15 minutes). The daily kernel's run 1 log is `logs/tegu-linkwait-20261107/series-run1.log` (cycles 1-61; the series kept running in the same boot).

**Cycle 214 on #90 (2026-11-07 12:21 MST): the wait did not help.** After 213 clean wakes the 214th failed link startup as before, and the new code ran: attempt, 100 ms, attempt, 400 ms, attempt, 1600 ms, attempt, then the host reset and the same again, five host inits, 20 attempts over 13 s (console in `/var/log/omamobile/ramoops/console-1107-122313.txt` on the palmtop; a copy comes to `logs/tegu-linkwait-20261107/`). Every attempt failed with result 1, so the device did not answer for 13 s with up to 1.6 s between a reset and the next try. The hypothesis "the device is merely slow to boot after its reset" is not supported in that form: either it needs much longer still, or it is not answering for another reason (the reset pulse not registering, power, or the host's PHY not driving the lanes). The test kernel's deliberate panic on a failed UFS restore (`panic=10`, from the 11-03 trace) rebooted the palmtop by itself; ramoops kept the console and ext4 mounted clean. The loop then sent one needless `systemctl reboot` into that fresh boot (fixed: a palmtop up less than 10 minutes is left alone). Run 2 started at 12:25 on #90 while #91 builds.

**#91 (building):** two labelled retry paths, both only after a failed attempt, so a good wake is unchanged: (a) the link startup re-issued without any reset, every 500 ms, six times (a slow device would answer here); then (b) the usual host and device reset, but with RST_n held low 1 ms instead of 5 µs (`hba->link_retry`, read by `exynos_ufs_dev_hw_reset`), and 100 then 400 ms before the next try. Each failure line also logs the host status register (HCS, device-present bit) and the PHY-adapter error code (UECPA), both host registers. About 9.5 s of retries per failed wake in all, under the 13 s that passed without a watchdog reset on cycle 214.

**#91, run 1 (2026-11-07, pushed 12:35 MST palmtop clock):** 12 clean wakes, then the 13th sleep never woke: the journal ends at `PM: suspend entry (s2idle)` 12:50:34, no panic, no reboot, no USB, no ping for 22 minutes (the s3c2410 watchdogs are stopped while asleep, so nothing resets a palmtop that hangs inside the sleep or the first part of the wake). Dave's Power + Volume Up at 13:12 was a cold reset (`bootreason reboot, longkey, pmic_cold`), which wiped ramoops: no console of that boot. WFI-only (state1 disabled), spm_lvl 5, modem off. So the silent no-wake is not tied to CPU core power-down; it has now happened in WFI-only on #91 (after 12) as it did with C2 on (after 135, 9 and 18). The #91 retry paths were never exercised in this run. Next run: #91 again with the breadcrumb module v2 loaded by the loop at each start (its selftest decides), so a silent hang leaves its last stage in the PMIC RTC alarm 1 and the next boot's load line reports it, if the register survives the cold reset.

Side effect of the watcher's needless reboot (12:23): it cut `omamobile-tegu-graphics-start` off mid-way (at haptics), so the next boots' hang-safe guard refused to bring up the GPU, display, haptics, torch, gauge, Bluetooth and NFC ("the last start never finished"), `/dev/dri` did not exist, sddm started no session, and the palmtop sat on the boot splash through #91's run 1 and the first cycles of run 2. Found 2026-11-07 13:24 MST; `omamobile-tegu-graphics-start --retry` brought everything up and sddm started the session at once. So #91's 12 wakes and the silent no-wake happened without the GPU, display and Wi-Fi (the audio unit's Wi-Fi start had nothing to work with), a different condition from every earlier series; the no-wake still counts as one, the 12 wakes do not compare. The breadcrumb module's selftest failed on this kernel (A1SEC/A1MIN read back 0 after the write), so it unloaded itself; the loop records that and goes on without it. Run 2 of #91 restarted 13:26 with the shell up; the loop now waits for Hyprland before a boot's first sleep.

**#91, run 3 (clean boot 13:30 MST, shell and Wi-Fi up): 15 clean wakes, the 16th failed, both retry paths exercised, neither helped.** Console `/var/log/omamobile/ramoops/console-1107-135023.txt` (copy in `logs/tegu-linkwait-20261107/`). Per host init: six link startups re-issued without any reset, 500 ms apart (3 s), all failed; then three resets with RST_n low 1 ms and 100/400/400 ms waits, all failed; five host inits, 25 s in all; then the panic and the reboot. So the device is not merely slow, and the 5 µs reset pulse is not what it misses. The registers logged on every attempt are the first real difference between a good and a bad wake: good wakes show `hcs=0xf` (UTRLRDY, UTMRLRDY, UCRDY and **DP, device present**), the bad wake shows `hcs=0x8` on all 45 attempts: UIC ready, **no device present**. `uecpa=0x80000010` (the generic PHY-adapter error, the LINERESET indication the core clears after link startup) reads the same on good and bad wakes, and no per-lane PHY error is set. The host's M-PHY receiver never senses the device at all on a bad wake. Two readings remain: the device's transmitter is silent (power or an internal state a reset does not clear), or the host's PHY came up wrong at this wake and nothing in the retry loop re-powers it: `ufshcd_hba_enable` resets the host controller and the device, but the PHY keeps its one power-on from `exynos_ufs_resume` (`phy_power_on` is reference-counted, so the later `exynos_ufs_phy_init` is a no-op), so every attempt of a bad wake runs on the same PHY state, and the next boot's fresh PHY init works. Google's suspend differs in one more way: it writes `HCI_GPIO_OUT` 0 at suspend, holding the device in reset through the sleep, and the HCE path's pulse is the reset exit. Next: #92, a full PHY power-off/power-on (isolation and calibration again) on a retry, before the host and device reset.

**The VCC that never goes off (2026-11-07 14:10 MST).** The UFS device reports `power_on_wpe=false` (no power-on write protection), so at `spm_lvl` 5 the core's `ufshcd_vreg_set_lpm()` takes the branch that turns off VCC (and VCCQ/VCCQ2, which this DT does not describe) and `ufshcd_vreg_set_hpm()` turns it on again at the wake: the core believes the device is power-cycled across every sleep. On the 9a the `ufs-vcc` regulator is a fixed regulator on gpp0-1 with `regulator-always-on` (`zumapro-tegu.dts`; the 7 Pro's `gs201-cheetah.dts` says the same), so that off/on is a no-op and the device sits powered, in power-down, with RST_n held low (`gs101_ufs_suspend`) for the whole sleep, and the wake can only reset it. A bad wake's device is one that a reset does not bring back (25 s, 1 ms pulses, no device present), while a reboot through the bootloader does. Google's host driver has no rail handling of its own, so what stock does depends on its DT, which is not among our captures. **#92**: the #91 Image with a DTB whose `ufs-vcc` is no longer always-on (`logs/tegu-linkwait-20261107/linkwait92-dts.diff`, DTB sha f6e980bf87b433a7; `regulator-boot-on` stays, the UFS host holds it enabled while awake), so the suspend really cuts VCC and the wake really powers the device up again; `rpm_lvl` 1 for the run, so runtime suspend does not also cut VCC (that would be a second new behaviour); the first attempts after a wake may now fail while VCC ramps, which #91's retries cover and the log shows. If the dead wakes stop, the device needed a power cycle; if one still comes with `hcs=0x8`, the device's power was not the problem and the host's PHY receiver is next.

#92 pushed 14:10 MST (palmtop clock): `uname -v` #91, DTB f6e980bf87b433a7 (`/proc/device-tree/regulator-ufs-vcc/regulator-always-on` absent), `rpm_lvl` 1 for the run, `spm_lvl` 5, WFI-only, shell and Wi-Fi up. The regulator shows one user (`13200000.ufs-vcc`, `use_count` 1; with always-on it was 2, the core's own reference), so ufshcd's `regulator_disable()` at suspend takes it to zero and the GPIO goes low: the device is really power-cycled at every sleep now. The first wakes linked on the first attempt (no `link-wait` line), so the device is up again within the resume's own timing. Series running; the dead-wake rate before this change was about one in 15 to 215.

**#92 result (2026-11-07 14:10 to 17:04 MST): the power cycle does not fix it.** Three runs, 130 clean wakes in all, three dead wakes, each ended by the test kernel's panic and reboot (the loop stopped at its cap of three). With the device really power-cycled at every sleep (VCC off at suspend, on at the wake), a bad wake still shows no device present (`hcs=0x8`) through all retries. So the device's power and state are not what's wrong: a freshly powered device is not detected by the host. What's left is on the host side of the link, or between them: the host PHY receiver, the reference clock to the device, the reset and refclk pads (gph5-0/1 on `pinctrl_hsi2ufs`), or the PMU's isolation. Next, #93: the same kernel without the panic, so a dead wake stays inspectable over SSH, and the loop's capture reads the host-side state before the sysrq reboot: that pin controller's pins (one controller only), the UFS clocks in the clock summary, the regulator summary, the GPIO debugfs, the UFS sysfs power info, and the kernel log.

**#93, first dead wake (2026-11-07 18:49 MST palmtop clock, 17 clean wakes before it):** the kernel stayed alive as intended, but systemd's hardware watchdog (`RuntimeWatchdogSec=10s`, fed by PID 1, which blocks on the dead disk) reset the palmtop before the laptop's capture ran; the capture caught the next boot (a useful baseline: gph5-0 CON 0x2 DAT 1 PUD 0 DRV 2, gph5-1 CON 0x2 DAT 1 PUD 0 DRV 0, both CON_PDN 3; `ufs-vcc` GPIO out high). The dead wake's console (ramoops `console-1107-185007.txt`): 25 s of failed attempts as before, then `ufshcd_wl_resume failed`, I/O errors, and 0.1 s later `exynos-acpm-protocol: Timeout! ch:0`, `RX front can not keep up with TX front`, and the PMIC RTC unreadable (-110): the power-management firmware stopped answering after the storage died. The earlier dead-storage consoles (10-30, the 11-04 iocc one, #90's cycle 214) have no ACPM timeout, so this is a consequence of the long dead state (or of what the fallout asked of ACPM), not the cause. For the rest of the #93 run `/etc/systemd/system.conf.d/x-sleep-test-watchdog.conf` sets `RuntimeWatchdogSec=0` (the kernel keeps feeding the hardware watchdog itself with `tmr_atboot=1`, so a kernel hang still resets); the loop captures the host state first and never sends a sysrq to a palmtop that already rebooted. Remove that drop-in when the palmtop goes back to stock.

### The UFS pads come back as inputs: the cause of the dead storage (2026-11-07 19:59 MST)

#94 (the #91 kernel without the panic, VCC switching, readbacks on every attempt, systemd's runtime watchdog off) hit its dead wake after 35 clean ones, and this time the palmtop stayed up for the capture (`logs/tegu-linkwait-20261107/capture-1-hoststate.txt`). The UFS pads, read from their own pin controller (`13060000.pinctrl`, `pinctrl_hsi2ufs`, the only one read):

| | good boot (baseline, 18:50) | dead wake (19:59) |
| --- | --- | --- |
| gph5-0, UFS refclk | `CON(0x2) DAT(0x1) PUD(0x0) DRV(0x2)` | `CON(0x0) DAT(0x1) PUD(0x0) DRV(0x2)` |
| gph5-1, UFS reset | `CON(0x2) DAT(0x1) PUD(0x0) DRV(0x0)` | `CON(0x0) DAT(0x0) PUD(0x0) DRV(0x0)` |

CON 2 is the UFS function (`samsung,pin-function = <2>` in `zumapro.dtsi`); CON 0 is a GPIO input. On the bad wake both pads are disconnected from the host controller: the device gets no reference clock and no reset edge, so it never drives the line, the host sees no device (`hcs=0x8`), and no host reset, device reset pulse, PHY power cycle, VCC power cycle or waiting can reach it, because every one of those acts through pads that are not connected. The bootloader programs the pads again at the next boot, which is why a reboot always cured it, and why the 7 Pro, whose pads are on a different controller, never saw it. The rest of the host state read normal: UFS clocks on at their rates, `ufs-vcc` enabled and high, PHY isolation released, PMIC answering before the resume. The two unreported rails (VCCQ, VCCQ2) are not implicated.

Why the pads change: `pinctrl-samsung` saves every bank with a power-down config at `suspend_late` and writes the saved values back at `resume_early`, with the controller's bus clock on (`zumapro_gpio_hsi2ufs`, otherwise gated). Either the save read zeros because the HSI2 pad block had already lost its state by then (the UFS host had suspended, clocks gated and PHY isolated, some time before), or the restore's write was lost because the block was not powered yet at `resume_early`, before the UFS host's resume turned its clocks on. The `pin-con-pdn 3` ("previous state") setting is what the vendor uses. Whichever it is, the fix is the same: the UFS host must apply its pin state itself at resume, once its clocks are on. The #95 kernel logs what the pin controller saved and read back for that bank (`pins-save gph5 con=…`, `pins-restore gph5 con=… read back …`) to settle which.

**#95**: `pinctrl-names = "default", "sleep"` with the same two pin groups for both on the UFS node, `pinctrl_pm_select_sleep_state()` in `exynos_ufs_suspend()` and `pinctrl_pm_select_default_state()` in `exynos_ufs_resume()` for a link-off suspend, so the default is written again at resume (`pinctrl_select_state()` is a no-op when the state is unchanged, hence the second state). Plus the bank logging above. Everything else as #94. If the dead wakes stop over a long series, this is the fix to propose; the proper form (a pinctrl-driver fix, or the host re-applying its pins) is for the PR discussion with the log's answer in hand.

**#95 (pads re-applied at resume), first dead wake after 129 clean (2026-11-07 22:14 MST palmtop clock):** the re-apply works: in the dead state both UFS pads read `CON(0x2)` (`capture-1-hoststate.txt` of this run), and the pin controller's own save and restore read `0x22` on every wake, so the pads were not what killed this one. What the capture shows instead: `gpio-1 (regulator-ufs-vcc) out lo` while the regulator framework counts `ufs-vcc` as enabled (use 1): the GPIO write that turns the device's VCC back on at the wake (`ufshcd_vreg_set_hpm()` → `regulator_enable()` → gpp0-1 high) was lost, and the device sat unpowered through all the retries. In #94's dead wake that GPIO read high (and the UFS pads read 0), in #95's it reads low (and the pads read 2). Two GPIO banks on two controllers (`pinctrl_hsi2ufs` for gph5, `pinctrl_peric0` for gpp0), one pattern: a GPIO register written during the wake, or saved across the sleep, does not hold on a bad wake. The VCC switching introduced in #92 (a wake now depends on a GPIO write) created a second way to lose the device; the daily's always-on VCC never toggles that pin. **#96**: VCC `regulator-always-on` again (never toggled), the UFS pin state re-applied at resume as in #95 (DTB sha below), Image #95 unchanged. If the dead wakes stop: the fix is the re-apply, and the underlying GPIO-bank state loss across s2idle on this SoC is the thing to understand and report (which banks, and whether a pad-retention or block-reset event is involved).
#96 DTB sha256 6db11ff438e8b6ce (zumapro-tegu.dts identical to the daily again; zumapro.dtsi carries the UFS "sleep" pin state). Pushed 2026-11-07 22:40 MST (laptop clock); rpm_lvl left as found (3), spm_lvl 5, WFI-only.

### #96: 300 of 300 (2026-11-07 22:19 to 2026-11-08 03:55 MST, palmtop clock)

The first full series on the 9a: 300 RTC-woken 60 s `systemctl suspend` sleeps, every wake clean, no UFS error, no retry, no `link-wait` line, root rw throughout, one boot. Conditions: Image #95 (the daily tree plus: the UFS host re-applies its pin state at resume, the retry paths and readbacks of #91/#94, the deliberate panic removed), DTB 6db11ff438e8b6ce (`zumapro.dtsi` with the UFS "sleep" pin state; `zumapro-tegu.dts` as the daily, VCC always-on), `spm_lvl` 5, `rpm_lvl` 3, WFI-only (cpuidle state1 disabled), modem off, Wi-Fi reloaded around each sleep by the hook, NFC poll stopped by the hook, shell up, cable in. Logs: `logs/tegu-linkwait-20261107/series-run1.log` (this run's copy), `loop.log`. The pin controller's own save and restore read `con=0x22` on all 300 wakes.

So the dead-storage wake was the UFS pads (gph5-0 refclk, gph5-1 reset) losing their function across the sleep, and re-applying the UFS node's pin state in `exynos_ufs_resume()` for a link-off resume prevents it: 300 clean against a previous rate of one dead wake in 15 to 215. What this run does not yet cover: CPU core power-down on (the shipped setting, and the only one that showed the silent no-wake), longer sleeps, auto-sleep through the shell, the power key as the wake source, the modem on. Next: S2, the same kernel with `WFI=0`.

**S2 (#96, `WFI=0`: cpuidle state1 enabled, as shipped) started 2026-11-08 03:57 MST.** Reading note: with core power-down on, the kernel's printk clock stops during the sleep, so the series' `dmesg` column reads about 0.2 s; the `rtc` column (60 s) and the 86 s cycle spacing show the sleeps are real, and `suspend_stats/success` counts them. The WFI-only runs showed about 60 s there because the architected timer kept the clock running.

**S2 result: silent no-wake after 18 clean wakes (2026-11-08 ~04:40 MST).** Same kernel and DTB as the 300-wake WFI-only pass; the only change `WFI=0` (cpuidle state1 enabled). No USB, no ping, no tailnet, no SSH; the watcher declared it at 04:56. Tally of silent no-wakes with core power-down on, across kernels: after 135, 9, 18 (earlier) and 18 (#96). WFI-only: 300 of 300 on #96; the one WFI-only no-wake (#91 run 1, after 12) was on a boot without GPU, display or Wi-Fi, so it is not the same condition. The dead-storage fix (pads) does not touch this. Waits for Power + Volume Up; a cold reset wipes ramoops, so no console will be available from this hang either.

**#97 (building, 2026-11-08 04:50 MST laptop):** #96 plus `s3c2410_wdt.keep_in_suspend=1` (default on in this build): in the watchdog driver's system-suspend callback the cluster watchdogs are no longer stopped; they are set to their longest timeout (about 87 s: 24.576 MHz source, 16-bit count, prescaler 256, divider 128) and left counting, and the resume callback restores the normal setting as before. A sleep that never wakes is then reset by the watchdog about 87 s after the suspend, a warm reset that keeps ramoops (the #93 and #77 watchdog resets did), so the console of the hang's boot can be read and the series resumes on its own. A 60 s sleep plus the resume fits well inside 87 s; for longer sleeps the parameter must be 0 (this is a diagnostic, not the shipped setting). Open question the first hang answers: whether the watchdog counter runs at all while the cluster is powered down in C2; if it does not, the hang simply waits for the buttons as now. The loop saves the newest ramoops console after a self-reboot (`capture-N-ramoops.txt`).

**The pad fix in PR form (offline, 2026-11-08 05:45 MST laptop):** the two changes rebased onto the published kernel tip `d349a61dd91b` (worktree (a local scratch directory, not in the repository), output (a local scratch directory, not in the repository) on omb; diff in `logs/tegu-linkwait-20261107/ufs-pins-published-draft.diff`): `exynos_ufs_resume()` selects the default pin state again before powering the PHY on for a link-off resume, `exynos_ufs_suspend()` selects the "sleep" state after powering it off, and `zumapro.dtsi`'s UFS node gets `pinctrl-1` = the same two groups as "sleep". `W=1` on the host object: 0 warnings; `zumapro-tegu.dtb`: 0 warnings; `checkpatch --strict`: clean. Not committed yet: the PR should also carry what settles the silent no-wake, and the published tip has not booted the palmtop in this form (the series ran on the integration tree), so a run on it is still owed before a PR.

### The silent no-wake, caught by the watchdog (2026-11-08 07:06 MST, #97, cycle 7)

`s3c2410_wdt.keep_in_suspend=1` works: the watchdogs were armed at 87 s through each sleep (`kept running through suspend: timeout 87 s`), the normal wake restored them, and when the seventh sleep never woke the watchdog reset the palmtop (`bootreason watchdog, apc, early`), ramoops survived (`logs/tegu-linkwait-20261107/capture-1-ramoops.txt`, from `/var/log/omamobile/ramoops/console-1108-070750.txt`), and the loop restarted the series on its own. The console: the suspend side runs to its end (freeze, wake IRQs armed, PHY isolated, watchdogs kept, `pins-save gph5 con=0x22`) and then nothing, not one line of a wake. In a good cycle the next line is the pin controller's restore on the wake. So the SoC entered the sleep with every core in C2 and the RTC alarm 60 s later did not bring it back; the storage, pins and resume code never ran. Not the UFS, not the pads, not the device power. This is where the WFI-only setting differs: in WFI the cores never power down, the GIC and the cores are live, and the alarm interrupt is taken directly.

A difference from the 7 Pro in the pin controller driver: the gs101 alive controllers have `.suspend = gs101_pinctrl_suspend` and `.resume = gs101_pinctrl_resume`, which write the EINT wake-up mask into the PMU (which external interrupts may wake the SoC from a deep power state); the zumapro controller table has no such hooks, so on the 9a the PMU's wake-up mask is whatever the bootloader left. If the firmware powers the SoC down further once all cores are in C2 (a system idle state), the PMU's mask decides whether the RTC alarm EINT wakes it, and a stale or partial mask would give exactly this: most wakes fine, some lost, never in WFI. Being read now.

**What the no-wake needs, and what it gets (2026-11-08 07:50 MST).** Wake sources on the 9a as the kernel arms them: through the pin controller only the Power key (irq 59) and the Wi-Fi host-wake (irq 73) get `wake enabled` at suspend; the PMIC's interrupt, which carries the RTC alarm, is GIC SPI 74 (irq 56, `s2mpg14-pmic`), not an EINT, so no pin-controller mask could cover it, and `enable_irq_wake()` on a GIC line changes nothing in hardware. In WFI none of this matters: the cores stay live and the GIC delivers the alarm. With every core in C2 the firmware can take the SoC into its system-idle state, and which interrupts may wake it from there is set by the PMU's WAKEUP_MASK registers; in Google's kernel `drivers/soc/google/exynos-cpupm.c` writes them (offsets from their device tree; the PCIe driver's header shows the family: `WAKEUP_MASK 0x3944`, bit 16 for the Wi-Fi PCIe) before allowing that state, and `exynos-pm.c` the EINT masks. Our kernel has neither, so the masks are the bootloader's and the deep state is entered on the firmware's own judgement with whatever they allow: a wake that is usually taken and sometimes lost, never in WFI. The zumapro pin controllers also lack the gs101 suspend/resume hooks (EINT wake-up mask); that is a real gap too but not this failure's cause.

Decision: the fix to ship now is to keep C2 for everyday idle and use WFI for s2idle, which is the configuration that passed 300 of 300; the system-idle wake masks are a later improvement (power in sleep). The kernel change: a vendor property on the idle-state node (`google,no-s2idle`) that makes `dt_idle_states` leave `enter_s2idle` unset for that state, so `cpuidle_enter_s2idle()` falls back to WFI; runtime cpuidle is untouched. #98 = #97 plus that, run with `WFI=0` (state1 enabled) so the shipped runtime setting is what is tested. Google's tree for reference: `git clone --depth 1 --branch android-16.0.0_r0.0 https://android.googlesource.com/kernel/google-modules/soc/gs` (34 MB, on maclab at (a local scratch directory, not in the repository)).

**#98 pushed 2026-11-08 07:37 MST (palmtop clock):** Image 8d980819a8c898a4 (#97 plus `dt_idle_states`: a `google,no-s2idle` idle state keeps `enter_s2idle` unset), DTB 398aeafa9bac1fb7 (the three C2 states carry `google,no-s2idle`), `WFI=0` (cpuidle state1 enabled for runtime), spm_lvl 5, rpm_lvl 3, VCC always-on, pads re-applied, watchdog kept through suspend as a safety net. The series log now carries `c2-s2idle` (cpu0's state1 `s2idle/usage`, must stay flat) and `c2-run` (state1 `usage`, must grow) per cycle. The #97 C2 run before it: 6 clean wakes, a no-wake caught by the watchdog (console `logs/tegu-linkwait-20261107/console-97-c2-nowake-cycle7.txt`), then run 2 from 07:26 was stopped for the push.

### #98: 300 of 300 in the shipped configuration (2026-11-08 07:22 to 13:05 MST, palmtop clock)

Image 8d980819a8c898a4, DTB 398aeafa9bac1fb7: the daily tree plus the UFS pad re-apply at resume, the C2 idle states marked `google,no-s2idle`, the watchdog kept through suspend (diagnostic), the UFS retry and readback logging (diagnostic). Conditions: cpuidle state1 (C2) **enabled**, used while awake (`c2-run` grew from 15 298 to over 340 000 across the run) and never for s2idle (the state has no s2idle entry); spm_lvl 5, rpm_lvl 3, VCC always-on; modem off; Wi-Fi reloaded around each sleep by the hook; NFC polling stopped by the hook; shell up; cable in; 60 s RTC-woken `systemctl suspend` sleeps, 86 s apart. Every wake clean: no UFS error, no retry, no `link-wait` line, root rw, one boot. Logs: `logs/tegu-linkwait-20261107/series-98-c2run-300.log`, `loop-98-c2run.log`; on the palmtop `/var/log/omamobile/sleep-98-c2run-300.log`.

Together with #96 (300 of 300 WFI-only, the same two fixes minus the s2idle change) this closes the two failures that defined the suspend problem: dead storage after a wake (the UFS pads) and the silent no-wake (C2 in s2idle). Not yet covered, in order: the same run on the published kernel tip; the power key as the wake source and auto-sleep through the shell (the everyday path); longer sleeps (hours); the modem on. The diagnostic pieces (`keep_in_suspend`, the retry waits, the readbacks, the trace) come out before the PR.

Right after the series the palmtop rebooted (12:58 MST palmtop clock, `bootreason watchdog`): with no series waking it every minute, the shell's auto-sleep put it to sleep with no alarm, and the 87 s watchdog diagnostic did what it does. Expected from the diagnostic's design, harmless, and a reboot loop if left: a sleep inhibitor holds the palmtop awake until #99 (the same kernel with `keep_in_suspend` off by default) is on. Lesson for the loop: with that diagnostic on, hold an inhibitor the moment a series ends.

**#99 (2026-11-08 13:20 MST palmtop clock):** #98 with `keep_in_suspend` off by default (Image 03dd06055bb5bda7, DTB 398aeafa9bac1fb7): the two fixes plus the harmless logging. The everyday-path tests start here, one at a time: a 30-minute RTC-woken `systemctl suspend` (13:27), then an hour-long one taken by the shell's auto-sleep, then the power key as the wake source with Dave, then a night. The kernel commits in PR form are on the fork branch `tegu-suspend-fixes` (on `d349a61dd91b`): the UFS pad re-apply and the `google,no-s2idle` property; the #409 branch has the plan and the series scripts (e834af2).

**#99, long sleep 1 (2026-11-08 13:05 to 13:35 MST palmtop clock):** one `systemctl suspend` with a 30-minute RTC alarm: woke on the alarm (irq 56), 1801 s by the RTC, no UFS error, root rw. Next: an hour's sleep taken by the shell's auto-sleep itself, alarm set at 13:37 for 14:37.
Note (13:37): Dave's Power press and a cable tap on the screen lit the lock screen of an awake palmtop (one suspend this boot); not a wake from sleep. The shell's rule: sleep 30 s after the screen goes off behind a secure lock.
13:40: the `omamobile-sleep` toggle was off (Codex's series scripts turned it off and left `sleepd-owned`/`sleepd-before-retry: active` in `/var/lib/omamobile/suspend-test`); turned back on, Dave's setting. With the screen off behind a secure lock the daemon now sleeps the palmtop 30 s later.

**#99, everyday path (2026-11-08, palmtop clock):** auto-sleep put the palmtop down at 13:41:07 (30 s after the screen went off behind the lock), the Power key woke it at 13:42:24 (wake IRQ 60, `Power`), no UFS error, root rw. Then a 6-hour series the way the palmtop really sleeps (`device/tegu/bringup/sleep-autosleep-series.sh`, N=12, S=1800): the daemon sleeps it, an RTC alarm every 30 minutes wakes it, the script arms the next alarm within the daemon's 5 s dark-resume grace. Started 14:00.
14:36 (palmtop clock): the hour-long auto-sleep woke on its alarm (irq 56), no UFS error, suspends 3 this boot. The 6-hour auto-sleep series started 14:37 (`sleep-autosleep-series.sh`, N=12, S=1800; watcher `sleep-autosleep-watch.sh` on the laptop, hang threshold 45 min).
Auto-sleep series, cycle 1 (15:06 palmtop clock): 1802 s, alarm wake, no UFS error. The systemd runtime-watchdog drop-in (`x-sleep-test-watchdog.conf`) is removed again at the next awake window: #99 has no watchdog diagnostic, so stock applies.
16:10 (laptop): kernel PR opened, [linux-omarchy-mobile#224](https://github.com/derekross/linux-omarchy-mobile/pull/224) (`tegu-suspend-fixes` at 0fc569e7b, signed off by Dave), linked from #409.
Auto-sleep series: cycles 1-3 clean (1802 s each); cycle 4 ended after 72 s by the Power key (16:08 palmtop clock, a press at the palmtop), counted as a short clean wake; the alarm re-armed for cycle 5.

20:25 (palmtop clock, 2026-11-08): the 6-hour auto-sleep series is done, 12 of 12 cycles clean (`sleep-autosleep-series.sh`, N=12, S=1800, `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty` #99: C2 at runtime, WFI in s2idle, UFS pins re-applied on resume). Every cycle: the RTC alarm woke the palmtop after 1801-1803 s (wake irq 56, the PMIC), the storage came back (0 UFS link or I/O errors), no oops; cycle 4 was the power key (irq 60, 72 s in). With the one-hour sleep and the three before the series, 15 wakes this boot, all clean, the everyday path (the shell's auto-sleep behind the lock, no series script sleeping): the same kernel's 300 of 300 from the series script now stands on the path the owner uses.

20:32 (palmtop clock, 2026-11-08): #100 pushed, the kernel on the palmtop from here: #99 plus kernel #172 (the PERIC0 GPIO gate critical) and kernel #150 (the SPI flush order), which the sleep-test tree had lacked (NOTES 2026-11-08); nothing in the sleep path changed. The first wake on it (auto-sleep, the power key, irq 60) came back with the storage intact.

**The published tip plus #224 (2026-11-09, 12:40 MST palmtop clock).** `omamobile` at 1a9d1d4e9 with #224's two commits (the driver and the zumapro "sleep" pin state), built with defconfig + `kernel/configs/omamobile.config`: `7.3.0-rc6-omamobile-push1-gf693b36e62ce`, build #1, Image sha256 d6894572039e235d, the published `zumapro-tegu.dtb` with no overlays (the published descriptor applies none; the kit's overlay list is for the integration device tree, and two of its overlays name labels the published tree doesn't have). Pushed with the kit's `bin/omamobile push` after the #100 auto-sleep series (12 of 12 clean, 13 wakes that boot). The boot: SSH back after 60 s, root read-write, `spm_lvl` 5, no `cpuidle` directory under the CPUs (the published tree has no idle states, so the sleep is WFI and the C2 question doesn't arise), 0 UFS error lines, the modem boot unit disabled. Hyprland was not up 425 s after the boot (the published kernel's graphics stack isn't the daily's; the series needs no session), so the loop started the series after its wait. The run: `sleep-series-loop.sh` with N=36, S=60, MAXREC=2, started 12:47; then one Power-key wake from a sleep with a 15-minute safety alarm. Results follow.

**Result of the published-tip run on 1a9d1d4e9 (2026-11-09, 12:30 to 13:01 MST palmtop clock): no RTC alarm on the published kernel, so no series.** The boot was clean, but the first 60 s sleep never woke on its alarm: the palmtop slept 31 minutes (`PM: suspend entry` 12:30:31, `suspend exit` 13:01:15 on the owner's key, `pm_wakeup_irq` 54, a GPA pin). The boot log says why: `sec-pmic-acpm firmware:power-management:pmic-1: no interrupt, so no RTC alarm`, `rtc0` (`s2mpg14-rtc`) has no `wakealarm`, and the series' `rtcwake -m no -s 60` failed with `set rtc wake alarm failed: Invalid argument` (the script went on and slept anyway). The published `zumapro-tegu.dts` gives `pmic-1` no interrupt; the integration tree's `pmic_main` has `interrupts = <GIC_SPI 74 IRQ_TYPE_LEVEL_HIGH>`, `google,vgpio2ap-sysreg = <&sysreg_vgpio2ap>` (a syscon at 0x15090000) and `wakeup-source`, as the gs201 boards' nodes do, and the `samsung,s2mpg14-pmic` binding in the published tree already allows all three. So the UFS fix was not exercised, and the published kernel cannot run an RTC-woken series until its device tree carries the main PMIC's interrupt: a small board commit, proposed to the maintainer with #224. After the key wake the second sleep's `rtcwake` read the RTC as `-62` (`Failed to prepare registers for time reading`) with an `exynos-acpm-protocol ... Timeout! ch:2` (the PMIC channel), and the owner reset the palmtop with Power + Volume Up (console: `console-pub224-oldtip-noalarm.txt`, journal: `journal-pub224-oldtip-noalarm.txt`, both under the run's log directory). #100 was pushed back at 13:21 MST. The loop declared "silent hang: stop" after 15 minutes without an answer, which was right for the wrong reason: the palmtop was asleep with no alarm, not hung.

**The published tip plus #224 plus the PMIC interrupt (2026-11-09, 14:02 MST palmtop clock).** `omamobile` at abcd6aac51cf (today's tip, with the 9a's PCIe nodes from kernel #187) plus #224's two UFS commits plus three board commits that give the main PMIC its interrupt (the `google,zumapro-vgpio2ap-sysreg` compatible, the VGPIO2AP syscon at 0x15090000 in `zumapro.dtsi`, and `interrupts = <GIC_SPI 74 IRQ_TYPE_LEVEL_HIGH>`, `google,vgpio2ap-sysreg`, `wakeup-source` on `pmic-1`): `7.3.0-rc6-omamobile-push1-g6c9420bfa77f`, Image sha256 05283d33b59b3791, the published DTB (b244f20dddd932db), `CHECK_DTBS=y` quiet on it. The boot: clean, `rtc0` now has `wakealarm`, no "no RTC alarm" line, `spm_lvl` 5, 0 UFS lines; the modem boot unit masked for the run. `sleep-series-loop.sh`, N=36, S=60, started 14:04; a Power-key wake follows, then #100 goes back. Results follow.

**Result so far (14:47 MST palmtop clock):** the alarm now wakes the published kernel: 21 RTC-woken 60 s sleeps in a row came back (the first after 60.6 s by dmesg, `pm_wakeup_irq` 52, the PMIC's line on this kernel's numbering, 0 UFS lines), then the 22nd sleep, at about 14:32, never answered: no ping, no USB device on the laptop, for 15 minutes, and the loop stopped. The modem was masked, no idle states (WFI). (Corrected the same evening: no module was loaded on this boot. The kit pushed the Image and DTB only, and `/usr/lib/modules` had no folder for this release, so there was no Wi-Fi, no GPU and no session, and 16 units failed; the earlier line here said Wi-Fi was loaded, which was not checked.) Whether the SoC never woke or the kernel is alive with a dead USB link waits for the owner's reset and the ramoops console. The owner's integration kernel #96, WFI-only, had done 300 of 300 on 11-07/08; the published kernel differs in its device tree (the PCIe and Wi-Fi nodes among others) and in what it lacks.

**What the run showed, and what it didn't (2026-11-09, evening).** The series boot's journal has 22 `PM: suspend entry` lines and 21 `suspend exit` lines: the 22nd sleep, entered 14:13:31 MST with its alarm armed (no `rtcwake` error, no ACPM timeout that boot), never came back, and the laptop saw no USB device from then until the owner's reset at 16:04. So it is a silent no-wake on the published kernel in WFI, after 21 clean wakes, and not a UFS failure (a dead-storage wake brings USB back). No console survives it: the published device tree has no ramoops node (the kit's `public-ramoops` overlay wasn't applied), and the console file saved at the next boot is the earlier #100 boot's. The boot was also not a fair published install, since no module was loaded (above). The reset two minutes into the boot after the owner's reset was this session's own interrupted `run-restore100.sh` pushing #100, not a fault. Next run: the same kernel with its modules installed (`modules-push`, the kit's `kernel.release` swapped for the push) and the `public-ramoops` overlay alone, so a no-wake leaves a console.

**The cpuidle counters across one sleep (2026-11-09, 16:27 MST, #100; the maintainer's read-only check from kernel #224's review).** `device/tegu/bringup/sleep-cpuidle-check.sh` reads each CPU's `cpuidle/state0` and `state1` `usage` and `time` just before and just after a 60 s RTC-woken `systemctl suspend`, twice. (A) As #100 ships, C2 enabled with `google,no-s2idle` on the C2 states: over the 61 s between the snapshots every core spent most of the sleep in state1, 19.9 to 57.1 s per core in 99 to 210 entries, and the rest in state0 (419 to 1580 entries); `state1` has no `s2idle` directory. So with `enter_s2idle` cleared the cores did take C2 through the ordinary idle path during the sleep, with timers still waking them, exactly as the maintainer read `do_idle()`: #98's 300 of 300 and #99's and #100's everyday-path sleeps ran C2 this way, not WFI. (B) With `state1/disable` set on every CPU for the sleep and cleared after: 0 entries and 0.0 s of state1 on every core, 61.8 to 62.0 s of state0. Both sleeps woke on the alarm (irq 56) with no UFS line. The failing configuration was therefore only C2 entered through s2idle's own path (`enter_s2idle`, with the tick frozen): 18, 6 and up to 135 sleeps before a no-wake; C2 through the ordinary path, and WFI, each did 300 of 300.

**Run 3 on the published tree: 36 of 36 (2026-11-09, 17:06 to 17:46 MST palmtop clock).** The same kernel as the run that went silent at its 22nd sleep, `7.3.0-rc6-omamobile-push1-g6c9420bfa77f` (today's `omamobile` tip abcd6aac51cf, kernel #224's two UFS commits, the three PMIC-interrupt commits; defconfig + `kernel/configs/omamobile.config`), this time a fair published install: its own modules installed by `modules-push` (1823 built; 72 loaded at boot, panthor among them), the published DTB with the `public-ramoops` overlay alone, the session up (Hyprland), `omamobile-device-tegu` with the cpuidle hook installed (it does nothing here: the published tree has no deeper idle states, so the sleep is WFI). `omamobile-tegu-graphics-start` brought up the GPU, display, haptics, torch, gauge, Bluetooth and NFC from the in-tree drivers and failed Wi-Fi: the shared config doesn't build the zuma PCIe PHY until omarchy-mobile#274 merges. The modem boot unit was masked. `sleep-series-loop.sh`, N=36, S=60: 36 `systemctl suspend` sleeps of 60 s (59.7 to 60.2 s by dmesg), every one woken by the RTC alarm (`pm_wakeup_irq` 52, the PMIC's line on this kernel), 0 UFS link or I/O error lines in the whole boot, no oops, `suspend_stats` 36 successes and 0 failures. So the UFS fix runs clean on the published tree for 36 wakes, and the earlier 22nd-sleep no-wake did not recur with the modules loaded; that one stays unexplained, on a boot with 16 failed units and no console.

Two faults of this session's own tooling on the way, both fixed in the scripts: the first start of this series ran 14 "cycles" in which no sleep happened at all, because the push script's keep-awake inhibitor (block mode) refused every `systemctl suspend` (`sleep-series.sh` now stops when `suspend_stats/success` doesn't advance, and the loop releases that inhibitor before a series); and the loop took a series that had failed to start on a young boot for a self-reboot.

Run 4, the same sources built with #274's `CONFIG_PHY_ZUMA_PCIE=m` so that Wi-Fi comes up (the maintainer's request on kernel #224: sleep as it will land, with the PCIe nodes in use), follows.

**Run 4 on the published tree, with Wi-Fi: 36 of 36 (2026-11-09, 17:50 to 18:31 MST palmtop clock).** The same sources as run 3 (`7.3.0-rc6-omamobile-push1-g6c9420bfa77f`, build #2), built with omarchy-mobile#274's `CONFIG_PHY_ZUMA_PCIE=m` on top of `kernel/configs/omamobile.config`, so the 9a's PCIe link and Wi-Fi come up from the in-tree drivers: `omamobile-tegu-graphics-start` reported GPU, display, haptics, torch, gauge, Bluetooth, NFC and Wi-Fi (wlan0, BCM4383 on `13120000.pcie`, Gen2 x1), 78 modules loaded, the session up, the modem masked, the published DTB with the ramoops overlay alone. `sleep-series-loop.sh`, N=36, S=60, Wi-Fi kept loaded across the sleeps (`/etc/omamobile/wifi-keep-across-sleep` is set on the palmtop): 36 sleeps of 59.1 to 60.5 s by dmesg, every one woken by the RTC alarm (`pm_wakeup_irq` 52), 0 UFS link or I/O error lines in the whole boot, no oops, `suspend_stats` 36 and 0. After the series wlan0 was up and passed traffic (ping over wlan0, 13 ms). brcmfmac probed the chip again after each wake, as the Wi-Fi hook's header describes (the chip loses its firmware in the sleep), and each probe logged one `brcmf_p2p_create_p2pdev: timeout` pair; nothing else from the driver. The Power-key wake on this kernel follows when the owner is back.

**The Power-key wake on the published tree (2026-11-09, 19:23 MST palmtop clock, attended).** `7.3.0-rc6-omamobile-push1-g773b4102f5ec`: the tree of runs 3 and 4 plus one device tree commit, the 9a's GNSS nodes (linux-omarchy-mobile#237), with their modules blacklisted and the modem off for the boot, Wi-Fi up. One `systemctl suspend` with a 20-minute RTC alarm as the net; the owner pressed Power once after about 75 s. `pm_wakeup_irq` 57, the gpio-keys Power line (the RTC wakes read 52), `PM: suspend exit` 74.3 s after the entry, the lock screen lit on that press, no UFS line, `suspend_stats` 1 and 0. With runs 3 and 4 that is 73 sleeps on the published tree with #224 and the PMIC interrupt, all woken.

**A series through the sleep hook: 40 of 40 (2026-11-09, 19:32 to 20:17 MST palmtop clock).** `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty` build #100 (the kernel with C2), the hook of omarchy-mobile#591 installed with the palmtop's package, no keep flag, modem off for the boot, Wi-Fi kept. `sleep-series-loop.sh` with `WFI=0`, N=40, S=60, so the series set nothing by hand (`state1/disable` `00000000` at the start): 40 sleeps of 59.0 to 60.5 s by dmesg, each woken by the RTC alarm (`pm_wakeup_irq` 56), no UFS line, no oops, `suspend_stats` 40 and 0. The hook's log has 40 "8 deeper idle states disabled for the sleep" and 40 "8 idle states enabled again" lines and nothing else; afterwards `state1/disable` read `00000000` on all eight CPUs, the note was gone, and the runtime C2 counter had kept counting between the sleeps (27758 entries before the first, 83252 after the last).

**The newest tip, overnight: 212 woke, the 213th left a console (2026-11-10, 00:27 to 07:38 MST palmtop clock).** `omamobile` at 2f890a533 (the tip of 2026-11-10 04:19Z, with kernel #222's spi-s3c64xx change) plus the six commits of kernel #224, #236 and #237, built as published (defconfig + `kernel/configs/omamobile.config` + `CONFIG_PHY_ZUMA_PCIE=m` + `CONFIG_EXYNOS_GNSS_IF_SPI=m`): `7.3.0-rc6-omamobile-push1-gff4fdf58035e`, build #4, its own modules installed (78 loaded, brcmfmac and panthor among them), the published DTB with the `public-ramoops` and `modem-cpif` overlays, `wakealarm` present, `spm_lvl` 5. The modem was stopped by a clean reboot first (confirmed) and its boot unit masked for this boot; Wi-Fi up and kept; the sleep hook of #591 installed (it has no idle state to disable on this kernel). Unattended: the owner was asleep, and reset the palmtop in the morning.

- An unplanned first sleep. This series was not started by `sleep-series-loop.sh` but by hand, one SSH command that released the keep-awake inhibitor (`x-awake`) and then ran `systemd-run` with the script's path as the command; the loop starts it through `bash`, and the copy on the palmtop has no execute bit, so the unit failed at once (203/EXEC), and nothing checked. With the inhibitor gone the shell's auto-sleep took the palmtop at 00:30:15 with no alarm set. It slept 27 minutes 23 seconds, until the owner's Power key: `PM: suspend exit` 00:57:39, `pm_wakeup_irq` 57 (`Power`), no UFS line, wlan0 up. The second start, also by hand, went through `bash` and released the inhibitor only after the unit was active and its log had a header. The scripts here now do it the safe way round themselves, which that night's start did not use: `sleep-series.sh` releases `x-awake` itself, after its first alarm is armed, and `sleep-series-loop.sh` no longer releases it and stops if the unit failed at its start. That change has not run on the palmtop yet; its first run is the next series, attended.
- The series (N=230, S=60, `WFI=0`), 00:59 to 04:56: 212 sleeps, each woken by its alarm after 57.6 to 60.5 s by dmesg (`pm_wakeup_irq` 53, the PMIC's line on this build), with no UFS line, no ACPM timeout and no oops in any of them. Six cycles logged an RTC difference a minute short and one a minute long, each read within six seconds after a minute rolled over (the read tear of the 11-04 note); the kernel's clock has those sleeps at 60 s like the rest.
- The 213th sleep, entered at 04:56:10, never came back: no USB device on the laptop from then on. Two presses of the Power key at about 07:35 did nothing. Power + Volume Up reset the palmtop at 07:37 (the bootloader's record of it: `Long Press Power Key Reboot (PMIC COLD)`); the next boot's ext4 came up clean, with no UFS line.

The console of that boot (ramoops, saved by systemd-pstore on the next boot and copied before anything else ran). The reset was a cold one, so the buffer has bit errors all through it; these are the lines as they read across their many copies, with the seconds as printed:

```
[16140.03] PM: suspend entry (s2idle)
[16141.05] Freezing remaining freezable tasks completed (elapsed 0.001 seconds)
[16141.5]  samsung-pinctrl ...: wake enabled for irq ...     (three lines, the last ones every sleep prints)
[16401.33] rcu: INFO: rcu_preempt detected stalls on CPUs/tasks:
[16401.33] rcu:  7-...0: (3 GPs behind) idle=8274/1/0x4000000000000000 softirq=113577/113579
[16401.33] rcu:  (detected by 1, t=5252 jiffies, g=275353, ncpus=8)
[16401.33] Sending NMI from CPU 1 to CPUs 7:
[16411.33] After 10 seconds, these CPUs still haven't responded to the NMI: 7
[16411.33] rcu: rcu_preempt kthread starved for 2500 jiffies! g275353 f0x0 RCU_GP_DOING_FQS(6) ->state=R ->cpu=0
[16411.33] rcu:  Unless rcu_preempt kthread gets sufficient CPU time, OOM is now expected behavior.
[16411.33] NMI backtrace for cpu 0 skipped: idling at default_idle_call+0x24/0x30
  ... the same report about every 63 s, detected by one core or another, the kthread on CPUs 0, 4 and 5 ...
[25831.60] rcu:  7-...0: (3 GPs behind) idle=8274/1/0x4000000000000000 softirq=113577/113579
[25831.62] NMI backtrace for cpu 5 skipped: idling at default_idle_call+0x24/0x30
```

What it says:

- The kernel was alive for 9,690 s after the suspend entry, until the reset: other cores kept taking their ticks, detecting the stall and printing.
- CPU 7 answered nothing in that time. It didn't take the backtrace IPI in any report, its softirq count never moved, and RCU's record of it reads as not idle (nesting 1), so by that record it wasn't sitting in WFI in the idle loop.
- The first report came 261 s after the suspend entry, for a grace period that began about 240 s after it. The alarm was due about 60 s after it. So the core stopped somewhere in the first four minutes, and nothing in the log narrows it further.
- Nothing of a resume was printed: no `watchdog enabled`, no `wake disabled`, no `PM: suspend exit`. The alarm and the two key presses either never reached the suspend path, or it couldn't run.
- The grace-period kthread was reported starved on CPUs 0, 4 and 5 in turn, each of which answered the IPI as idle. Why a runnable kthread doesn't run on an idle core that answers IPIs isn't explained here.

So this no-wake isn't the SoC staying down, which is what failure 2 looked like on #97 (the last CPU going down, then the watchdog's reset). It is one core locked up with the rest of the kernel running, and nothing watches for that during a sleep: the cluster watchdog is stopped for it and systemd is frozen.

What it doesn't say: what CPU 7 was doing. The backtrace IPI is an ordinary interrupt on this build (`CONFIG_ARM64_PSEUDO_NMI` is off), so a core with interrupts masked, or one stuck below the kernel, can't answer it. Nor whether the 22nd sleep of 11-09 was the same thing: that boot had no ramoops. "What is left" item 1 has the next run.
