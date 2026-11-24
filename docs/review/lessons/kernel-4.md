<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Kernel (linux-omarchy-mobile) (part 4 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
