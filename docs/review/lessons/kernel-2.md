<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Kernel (linux-omarchy-mobile) (part 2 of 2)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-144. A vendor kernel may program what our read-only driver leaves
  alone.** Google's `gs_tmu_v2.c` sends every non-passive DT trip to ACPM as
  a TMU threshold; under our driver the hardware trip is whatever the
  bootloader set. "INIT doesn't change them" isn't "they're set": ask for the
  decoded values. Extends L-23. *From:* kernel #7, round 12.
- **L-151. An access table on shared driver data is checked against open
  PRs on every SoC that falls back to it.** Kernel #49 limited
  `google,zuma-pmu`'s regmap; Tensor G4 binds the same data through its
  fallback, and open #40 reads PMU `0x2a84` there, which the table left out:
  tegu's HSI0 clocks, and with them its only USB link, would have failed.
  *Check:* `git grep` the compatible's fallback users, then grep open PR heads
  for reads and writes through that regmap. *From:* kernel #49, round 13.
- **L-152. "Both SoCs use the same Google source" is proven by blob ids.**
  The gitiles JSON listing of `drivers/ufs/zuma/` gave identical blob ids on
  the Pixel 8 and Pixel 9a branches. *From:* kernel #51, round 13.
- **L-153. A per-function object diff normalises `adrp` pages, relocation
  addends and `.altinstr_replacement` before naming changed functions.** The
  raw diff of #42 showed 28 changed functions where one changed. Extends
  L-110. *From:* kernel #42, round 13.
- **L-163. A regmap table for a new block allows writes only to what its
  client driver writes,** not the vendor's register enum. #54's RTC table
  could write the PMIC's SMPL, WTSR and oscillator trim. Note that
  `update_bits` on a volatile register skips the write table when the bus has
  `reg_update_bits`. Extends L-25. *From:* kernel #54, round 14.
- **L-164. Re-validate an approved binding PR against every board merged
  since.** #13's `soc_compatible: false` rule began rejecting lynx's real node
  once #43 merged. *From:* kernel #13, round 14.
- **L-176. A new register written through a Tensor PMU regmap goes into
  that SoC's access table, and the write's return is checked.** #62 wrote
  `PMU_INFORM0` on `google,zuma-pmu`, whose `wr_table` (kernel #49) lists
  eight other registers; regmap returns -EIO before the SMC, and the PR
  dropped the return, so on the base it would silently do nothing while the
  phone test (from an older integration tree) showed it working. *Check:* for
  every new `regmap_write`/`update_bits` on a `pmu_secure` regmap, find the
  offset in `gs101-pmu.c`'s `*_pmu_registers` for that compatible, and ask
  for the blob id of `gs101-pmu.c` in the tree that produced the evidence.
  Extends L-151 and L-163. *From:* kernel #62, round 20.
- **L-177. Google publishes per-device device-tree repositories for the
  zuma-era phones, and their `*-isp-event-info.dtsi` gives every interrupt
  register's offset.** `kernel/devices/google/zuma` (`dts/zuma-isp.dtsi`,
  `zuma-isp-event-info.dtsi`) and `kernel/devices/google/tegu`
  (`dts/zuma-tegu-camera.dtsi`), with the bit names in `soc/gs`'s
  `include/dt-bindings/lwis/platform/zuma/isp_fe.h`. Kernel #63 attributed
  the zumapro LoCH layout to the HAL's register table; the event-info DT
  confirms the ISR/IMR offsets, and the camera DT gives the sensor power
  sequence the commit called "stock's". *Check:* for a "from the HAL"
  register claim, fetch the block's event-info node (`irq-src-reg`,
  `irq-mask-reg`) and the LWIS header; for a power sequence, the device's
  `*-camera.dtsi` `power-up-seqs`. Ask for the citation. Extends L-61 and
  L-152. *From:* kernel #63, round 20.
- **L-193. A CMU table's parent list is checked for registration, not only
  for order.** Kernel #73's three CMU_TOP G3D muxes name four
  `zumapro_shared*_d2/_d3` parents in the CAL's order, but nothing in
  `clk-zumapro.c` registers them, so a mux left on one of them is an orphan
  at 0 Hz; the boot evidence didn't show it because the GPU rates come from
  the local PLLs. *Check:* extract every registered name (second argument of
  `MUX*`/`DIV*`/`GATE`/`FFACTOR`/`FRATE`, third of `PLL`) and every name in
  `PNAME` lists and parent fields; the difference must be only board-level
  inputs (`oscclk`, `*-alt`, `*-tcxo`) and deliberate omissions, each named
  in the message. The CAL's `FIXEDRATE(PLL_SHAREDn_Dm, …)` lines are the
  factors to add. *From:* kernel #73 with #78, round 21.
- **L-208. An OPP table is checked against the stock cpufreq domain's
  limits, not only the firmware's rate list.** #87's little table ended at
  1950-1954 MHz, above Google's `max-freq = <1950000>`, and `clk-acpm`
  forwards any rate. *Check:* each cluster's top and bottom OPP against
  `cpufreq_domainN` `min-freq`/`max-freq` in the SoC's `*-cpu.dtsi`; points a
  few MHz apart are table entries, not frequencies. Extends L-52. *From:*
  kernel #87, round 22.
- **L-209. Google's ACPM DVFS ids come from the `acpm_dvfs_id` enum, not
  `acpm_vclk_list`.** The zuma enum has 17 domains with AOC at 15; the list
  leaves AOC out, and counting it would have called #84's ids wrong.
  *Check:* count the enum from `MIF = ACPM_VCLK_TYPE`. *From:* kernel #84,
  round 22 (a near miss).
- **L-210. A register value that "follows the vendor's formula" is checked
  by recomputing the formula for that panel.** `dsim_calc_underrun()`
  reproduces cheetah's ABL pair but not tegu's, so #88's 120 Hz value left
  0.98 ms of slack, not 2.46 ms. *Check:* the vendor function with the panel
  driver's `underrun_param`, DSC and lane rate, at every rate. Extends L-61.
  *From:* kernel #88, round 22.
- **L-211. A board that names one panel for a model shipped with several
  needs the identification path.** Tegu's connector lists three panels chosen
  by ABL's `panel_name`, with different rate-switch sequences. *Check:* the
  device's `*-connector.dtsi` and `BUILD.bazel` panel list; ask owners for the
  panel name, and gate commands in userspace where the kernel can't read the
  ID. Extends L-117 and L-169. *From:* kernel #90, round 22.
- **L-212. A panel backlight's range matches the vendor's brightness
  capability.** #89 exposed 0-4095 with a 4095 default; Google's normal range
  ends at 3628, and 0x0FFF is HBM2, pushed on the first wake. *Check:*
  `brightness_capability` and `default_brightness` in the vendor panel file
  against the driver's `max` and default. *From:* kernel #89, round 22.
- **L-213. A driver that changes PMIC or charger state on userspace request
  restores it at `.shutdown` and reads it back at probe.** #92's inhibit
  survived reboot, and probe's "auto" default made `auto` a no-op. *Check:*
  for every write path, what the next boot finds and how userspace undoes it.
  *From:* kernel #92, round 22.

- **L-350. A flag that hands off ownership is set under the lock its
  consumer holds, after rechecking completion.** #152's first "abandon" flag
  was set outside `rx_lock`, so an answer drained just before the timeout
  still leaked the slot. *Check:* for any timed-out-request cleanup, find the
  lock the completion path holds and the order of check and set. *From:*
  kernel #152, 2026-10-31.
- **L-351. A helper node under `/chosen` fails dtbs_check.** dtschema's
  `chosen.yaml` allows only `framebuffer*` and `pinctrl-N` children (#154's
  `panel`). *Check:* run dt-validate on the DTB for any node a PR adds under
  `/chosen`; a node at the root validates, and fw_devlink still skips it.
  *From:* kernel #154, 2026-10-31.
- **L-352. A per-panel constant a contributor calls "approximate" may be in
  Google's panel driver.** The 8 Pro's 70 x 155 mm is `HK3_WIDTH_MM`/
  `HK3_HEIGHT_MM` in `panel-gs-hk3.c`. *Check:* `kernel/devices/google/
  <device>/display/panel-gs-*.c` before accepting an estimate. *From:*
  kernel #154, 2026-10-31.
- **L-447. A crash fix that moves a decode out of its condition changes what
  the reference phone shows, and a reference-phone run lapses when the
  commit is reworked.** Kernel #191 decodes every scanned BSS and drops 6
  GHz ones, so a 7 Pro also loses the phantom 2.4/5 GHz entries its 6 GHz
  neighbours made; our 11-01 run on #56 covered only the NULL check.
  *Check:* for a new skip or early return on a shared path, list the inputs
  that used to pass with a wrong value, say what the reference phone stops
  showing, and diff a moved commit against the tested one. Extends L-86,
  L-206 and L-379. *From:* kernel #191 with #56, round 39, 2026-11-03.
- **L-448. Before accepting a driver-side way to move a second clock with a
  GPU's rate, grep the clock driver for an existing pairing.** Kernel #189
  added a panfrost `l2` clock and an undocumented per-OPP `l2-hz`, set L2
  first in both directions, while `clk-acpm` already pairs G3D and G3DL2 for
  gs201 and zumapro in the vendor's order (L2 up first, down last). *Check:*
  `git grep -n paired drivers/clk/samsung/clk-acpm.c` and the merged
  siblings' GPU nodes, and compare the set order with
  `gpu_dvfs_set_new_level()`. Extends L-104. *From:* kernel #189, round 39,
  2026-11-03.
- **L-471. A disabled board node that an overlay will enable later carries
  its pin states now.** #159's Bluetooth child had no `pinctrl-0`, and
  Samsung pinctrl refuses groups that arrive by runtime overlay. *Check:*
  for every disabled node meant for an overlay, compare with the same-SoC
  sibling's merged node and require the same `pinctrl-*` and groups in the
  board DTS. Extends L-240. *From:* kernel #159, round 40, 2026-11-04.
- **L-472. When a driver gives up where the vendor driver has a fallback,
  use the vendor's fallback.** #194 made up an identify record after a
  missing identify report; stock's `syna_tcm_v1_detect()` sends
  `CMD_IDENTIFY`, then `CMD_RESET`, for exactly that case, and that also
  reports the real firmware. *Check:* for any new "carry on without X" path,
  grep the vendor driver for what it does when X is missing. Extends L-237.
  *From:* kernel #194, round 40, 2026-11-04.
- **L-473. A bindings PR that documents a vendor driver's names is reviewed
  against the hardware, not the DTs it makes pass.** #193's schemas quieted
  `dtbs_check`, but six nodes had no resources, half the properties were
  DPCM flags, and two reinvented `model` and `sound-name-prefix`. Before
  saying a codec's binding "already allows" a common property through its
  `$ref`, read its last line: `additionalProperties: false` hides the ref's
  properties. *Check:* for each node, its DT resources; for each property,
  `git grep` the common sound schemas; list every DT, overlay and userspace
  matcher that would freeze the names. Extends L-96 and L-183. *From:*
  kernel #193, round 40, 2026-11-04.
- **L-474. A boot argument that changes every reboot is tested on every
  reboot path.** #198's `reboot=warm` was tested with `reboot-to bootloader`
  only; an ordinary reboot and the panic reset the initramfs safety net
  depends on weren't. *Check:* list the reboot paths (normal, `reboot-to
  <reason>`, panic, watchdog) and ask for each, or the device notes that
  cover them on that SoC. Extends L-284. *From:* kernel #198, round 41,
  2026-11-05.
- **L-503. "Appended at the end, so no offset moves" is checked for structs
  that embed the grown struct.** `struct aoc_chip` sits inside `struct
  snd_card_pdata`, so #203's appended bool shifted offsets in 15 functions.
  *Check:* `git grep 'struct <name> [a-z_]*;'`, then an object diff. Extends
  L-230. *From:* kernel #203, round 42, 2026-11-07.
- **L-504. A new `->set_cs` branch for GPIO chip selects is dead unless the
  controller sets `SPI_CONTROLLER_GPIO_SS`.** Kernel #204 added the same write
  to `set_cs` and to `set_native_cs`, which the core never calls for a
  `cs_gpiod` device here. *Check:* read `spi_set_cs()` in the target tree and
  grep the driver for `GPIO_SS`. *From:* kernel #204, round 42, 2026-11-07.
- **L-505. A board PR that moves a bring-up overlay into the DTS is proven by
  comparing DTBs, not by a new boot.** Kernel #205's base DTB with the overlay
  applied and its head DTB decompiled identical with `dtc -s`, so the
  overlay's boot record carries over. *Check:* build both with the build's
  `dtc -@`/`fdtoverlay` and compare; any difference names what the record
  doesn't cover. Extends L-122. *From:* kernel #205, round 42, 2026-11-07.
- **L-506. A vendor command borrowed for a fallback reads its answer where the
  vendor driver does.** #194 sent `IDENTIFY` and waited for a report, but
  Google's `syna_tcm_v1_detect()` parses the IDENTIFY response's payload,
  which the PR discarded. *Check:* find the vendor's read of each borrowed
  command's response and confirm the new code reads the same place. Extends
  L-237. *From:* kernel #194, round 42, 2026-11-07.
- **L-507. A board DT that gives a new node a GPIO or supply is checked
  against the board's other users of it.** Kernel #202 put the 7a panel's
  reset and supplies on the touchscreen's gpp23-2 and LDO25M/26M; the driver's
  "shared GPIO" workaround was the symptom. *Check:* `git grep` each new pin
  and rail in the board DTS and Google's `*-display.dtsi`/`*-touch.dtsi`.
  Extends L-67 and L-349. *From:* kernel #202, round 42, 2026-11-07.
- **L-508. A "new" panel driver is diffed against the closest merged one with
  names normalised.** #202's S6E3FC5 driver differed from S6E3HC4's in 137
  lines, and its init still set a 1440x3120 window. *Check:* `diff` both with
  the names `sed`-ed to one token, then compare CASET/PASET and the init with
  the vendor driver. Extends L-61 and L-117. *From:* kernel #202, round 42,
  2026-11-07.
- **L-509. A board added to the base after a PR's last gate inherits its
  shared-dtsi changes, so the re-gate validates it.** Akita (on `zuma.dtsi`)
  landed after #187's last CI, and `dtbs_check` had never seen the
  combination. *Check:* `git log <old base>..<new base> --
  arch/arm64/boot/dts` for boards including a touched dtsi; `dt-validate` each
  on the merge. Extends L-195 and L-309. *From:* kernel #187, round 42,
  2026-11-07.
- **L-542. "As Google's driver does" is traced to the end of the vendor
  function, including what it does with the answer.** Kernel #194's fallback
  follows `syna_tcm_v1_detect()` up to the `IDENTIFY`/`RESET` order, but
  `syna_tcm_v1_parse_idinfo()` rejects a zero-length record, so on the unit
  that needed the fix the stock driver would fail too: the empty-record path
  is our own, and the real difference is probably earlier, in stock's
  power-up. *Check:* follow the vendor function past the cited step to its
  parse and error returns, and ask which branch the contributor's unit would
  take under stock. Extends L-61 and L-77. *From:* kernel #194, round 44,
  2026-11-08.
- **L-543. A panel-ID guard relaxed for a new ID is checked against the byte
  the vendor driver keys its commands on, and tested with the commands the
  guard blocked.** Google's `tg4c_get_panel_rev()` reads only 0xDB, so kernel
  #212's new ID3 gets the same command set; the guard existed for the rate
  switch, which the PR hadn't run. *Check:* the vendor driver's
  `get_panel_rev`/`read_id` for which ID bytes select commands, then ask for
  the guarded paths (rate switch, DPMS) on the new panel. Extends L-117 and
  L-211. *From:* kernel #212, round 44, 2026-11-08.
- **L-544. A register map with no public source gets its provenance in the
  commit message.** LWIS DTs give a part's address and widths but leave
  register sequences to the HAL, so a driver whose registers can't be cited
  says how they were found. *Check:* grep Google's GPL tree for each register;
  if one is absent, ask. Extends L-61 and L-177. *From:* kernel #213, round
  44, 2026-11-08.
- **L-545. A sentence corrected on one board is grepped across every board
  that copied it.** Kernel #214 fixes akita's "the guard runs before the disks
  appear" (L-528). The same words are in `zuma-husky.dts` and
  `zumapro-tegu.dts`, and UFS is built in for every phone, so they are wrong
  there too; only husky's had been noticed. *Check:* when a review corrects
  copied text, `git grep -n '<the sentence>' github/omamobile -- arch/
  device/`, and judge each copy by the fact that made the first one wrong
  (here `CONFIG_SCSI_UFS_EXYNOS=y` in the shared config). Extends L-528 and
  L-257. *From:* kernel #214 with #206, round 44, 2026-11-08.
- **L-546. soc/gs is one tree, so an absent call in a shared driver says
  nothing about one SoC.** We nearly told kernel #187's author that zuma has
  no secure-ATU SMC because Google's `pcie-exynos-rc.c` has none; that file is
  the same on the gs201 branch, where the SMC is real, so it comes from
  another driver. *Check:* `cmp` the file across the board branches first, and
  find where the vendor actually issues the SMC before saying "SoC X doesn't
  use it". Extends L-58 and L-113. *From:* kernel #187, round 44 (a near miss
  in drafting); 2026-11-08.
- **L-547. A phone run on a test kernel carries over a new base conflict when
  the tested-to-resolved diff equals the base's own movement.** Kernel #187's
  `zuma.dtsi` aliases conflicted hours after we said "merges cleanly"; the two
  diffs matched exactly, which showed the 7 Pro kernel was still
  representative without a rebuild. *Check:* resolve in scratch, compare `git
  diff <tested tree> <resolved>` with `git diff <tested base> <new base>`, and
  grep the difference for any reference-phone path. Extends L-45, L-122 and
  L-195. *From:* kernel #187, round 44, 2026-11-08.
  Again in round 45: for kernel #187, `git diff <tested merge> <resolved
  merge> --stat` listed only zuma, husky and akita files, and a per-function
  object compare of the prebuilt base/test pair (same-source control objects
  first, at 0 changes) answered "what changes on cheetah" without a rebuild;
  give the contributor the expected tree id of the rebase.
- **L-577. A draft whose commits a sibling stack carries is checked by
  patch-id per commit, and closed with a note to its author, not merged.** 22
  of kernel #156's 25 remaining commits are patch-identical in #187 and the
  other 3 differ in context only; saying so, with ids, answers "is anything
  lost if we close it", and a request made on the draft (gate the split) is
  retired where the sibling's thread settled it. *Check:* `git cherry` against
  the base, then `git patch-id --stable` on both lists, and grep the sibling
  thread for each open request. Extends L-182 and L-429. *From:* kernel #156
  with #187, round 45, 2026-11-08.
- **L-578. A blob check that fails on one file is narrowed to the nodes the
  test used before we ask for another boot.** Kernel #209's tested
  `zuma-husky.dts` differed from the head only by other test nodes around it;
  the `nfc@8` node, its pin groups, the PMU's `#clock-cells`,
  `clk-exynos-clkout.c` and `nxp-nci/i2c.c` were identical. *Check:* for each
  differing file, extract the nodes or functions the test exercised (`sed -n
  '/<label>: /,/};/p'` on both blobs) and diff those; if they match, say so,
  and let the maintainer choose between the boot and the narrowed evidence.
  Extends L-45 and L-131. *From:* kernel #209 and #210, round 45, 2026-11-08.
- **L-579. A provenance answer of "disassembled the vendor's binary" is judged
  against CONTRIBUTING §7 and the repository's precedents, not by reflex.**
  Kernel #213's register map came from Google's camera HAL; §7 allows a
  protocol described in our own words, and USF-PROTOCOL, MODEM-SIT-RESEARCH
  and CAMERA-PLAN were written the same way. *Check:* the diff holds no code,
  table, firmware or tuning from the binary (only register numbers and a
  command form), the message says "disassembled" and names the source, and
  what the registers do was measured; anything copied is the finding. Extends
  L-61 and L-544. *From:* kernel #213, round 45 (a near miss: the first
  reading was "proprietary source, hold"), 2026-11-08.
- **L-580. An import of an upstream series is taken from the maintainer's
  applied commits once they exist, not from the posted version.** Kernel #219
  imported v8 as posted, while the subsystem tree had applied a changed
  version two weeks earlier. *Check:* the patchwork state ("mainlined" or
  "accepted") and the maintainer's apply mail, then
  `git.kernel.org/<tree>/patch/?id=<id>` against the PR commit by commit
  (tree-identical first, then trailers). Extends L-62. *From:* kernel #219,
  round 45, 2026-11-08.
- **L-581. A board PR imported from an upstream posting is checked against
  that posting's review thread, bots included, for open points.** Kernel
  #220's v2 had a rejected compatible and an unanswered `tz_mem` question.
  *Check:* fetch the thread's mbox, list each reply's points, and say in the
  review which are still open upstream. Extends L-61 and L-79. *From:* kernel
  #220, round 45, 2026-11-08.
- **L-582. Moving a supply from a `simple-framebuffer` node to a disabled
  panel node leaves the rail with no consumer, and the late regulator cleanup
  turns it off about 30 s in.** Upstream boards put panel rails on the
  framebuffer node for that reason (kernel #220). *Check:* for every
  `*-supply` a board PR moves or removes, list the rail's consumers in nodes
  that are `okay` in the final DTB, read its
  `regulator-always-on`/`regulator-boot-on`, and check the cmdline for
  `regulator_ignore_unused`. Extends L-93 and C-1. *From:* kernel #220, round
  45, 2026-11-08.
- **L-583. A `Fixes:` id the author couldn't find is found with `git log -S`
  on the loop's own text, then confirmed by reading that commit's hunk.** For
  kernel #222, `-S'target_len'` before `1ee806718d5e` gave `0af7af7da651`
  (v4.18), whose loop already lacked the exit. Extends L-83. *From:* kernel
  #222, round 45, 2026-11-08.
- **L-584. A kernel option that turns on a feature upstream userspace will
  configure is checked against that userspace's next default, not only
  today's.** #515's zram is inert under the pinned Omarchy 4.0.6, but Omarchy
  4.5.0 ships `zram-size = ram` and `zram-generator` for aarch64, the setting
  the PR's own test hung the 9a with, so merging the driver turns the 4.5 move
  into the switch-on. *Check:* fetch the feature's config at the userspace
  version the image moves to next (here Omarchy's tag), and if the PR's
  evidence says that default is unsafe on phones, put the override in the
  migration plan as a condition of the move. Extends L-433 and L-37. *From:*
  #515, round 45, 2026-11-08.
- **L-626. A per-state "not for s2idle" switch is checked against the s2idle
  fallback, not only `find_deepest_state()`.** When no state above WFI has
  `enter_s2idle`, `do_idle()` calls `cpuidle_find_deepest_state()`, which
  ignores `enter_s2idle`, so kernel #224's state is still entered, through the
  ordinary `->enter` and without `tick_freeze()`. *Check:* read
  `kernel/sched/idle.c`'s s2idle branch down to `call_cpuidle()` for a table of
  WFI plus the marked state, and ask for each state's `time` delta across one
  sleep; an `s2idle_usage` the change makes impossible to increase isn't
  evidence (L-454). *From:* kernel #224, round 46, 2026-11-09.
- **L-627. A platform driver's sleep callback that "refuses before the PCI
  core suspends" its root port runs after it:** children's noirq callbacks
  complete before the parent's (kernel #232). *Check:* for any new refusal in a
  host controller's PM ops, name the devices below it and the phase, and read
  the `dpm_*_suspend_devices()` order (or ask for one `pm_print_times`
  cycle). *From:* kernel #232, round 46, 2026-11-09.
- **L-628. A PMIC register a fix clears at power off is checked for who sets
  it again at boot.** Kernel #233 clears WTSR at power off; our kernel never
  writes it on the S2MPG12, and the value read (0x0f) matches neither stock's
  probe (0x07) nor its restart (0x7f), so the bootloader re-arms it, and if it
  doesn't, a manual reset turns cold and pstore is lost. *Check:* `git grep`
  the register in the driver for every writer, decode the read value against
  the vendor's probe and restart values, and ask for one read after a cold
  boot. Extends L-213 and L-437. *From:* kernel #233, round 46, 2026-11-09.
- **L-629. A stopgap that publishes a sensor's fallback state publishes only
  the values the fallback gets right.** Kernel #234 accepted a MAX77779 with no
  model and, with it, five capacity and time values scaled by the default
  8.5 Ah for a 5 Ah pack. *Check:* for each property a relaxed readiness check
  now publishes, ask whether it depends on what's missing (the model, a
  calibration), and ask for `-ENODATA` for those. Extends L-99 and L-161.
  *From:* kernel #234, round 46, 2026-11-09.
- **L-630. A "logging only" change to a retry path is re-counted against the
  base's current retry count.** Kernel #223 was written against a driver that
  tried the model load once; the release kernel now tries 8 times with 3 inner
  retries per loop, so its two messages can print up to 48 times. *Check:* for
  a new message in a loop, find every loop that reaches it on today's base
  (`git log -L :<function>:<file>` on the callers) and give the worst-case
  count. Extends L-29. *From:* kernel #223 with `28bab7f602ca`, round 46,
  2026-11-09.
