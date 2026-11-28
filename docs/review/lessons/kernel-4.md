<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Kernel (linux-omamobile) (part 4 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
