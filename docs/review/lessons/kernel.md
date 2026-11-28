<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Kernel (linux-omamobile) (part 1 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-1214. A driver change that drops old compatibles, beside an overlay that
  moves a board to the new one, is checked against the omamobile overlays that
  use the old ones, applied to the published kernel's DTB to read which driver
  binds, and checked for a version tie between the packages that carry each
  half.** Kernel #193 removed the old compatibles as "nothing published uses
  them", true of the kernel tree only: the 7 Pro's card lives in an omamobile
  overlay in `DTB_OVERLAYS`. #1091's overlay and #193 each apply and build
  with the other's old half, and the card then binds to nothing; on a release
  7 Pro the overlay ships in `omamobile-device-cheetah` and the DTB and driver
  in `linux-omamobile`, with no versioned dependency between them, so a kernel
  package that reaches phones ahead of the device package (the boot-update
  path rebuilds their DTBs) leaves them without call audio. *Check:* `git grep
  -n '<old compatible>' origin/main -- 'device/*/overlays'` and the device's
  `DTB_OVERLAYS`; `fdtoverlay` the whole `DTB_OVERLAYS` onto the published
  board DTB with the new overlay, then `git grep '\.compatible = ' <published>
  <PR head> -- <driver>` for the compatibles each side matches. If neither
  side keeps the other's, the merge plan names the device package version that
  must reach phones no later than the kernel, and "a versioned pair or a
  one-release fallback" goes to the maintainer in both reviews. Extends L-678,
  L-679, L-827 and L-37. *From:* kernel #193 with #1091, round 69, 2026-11-26.
- **L-1213. A gate that fails any W=1 warning in a touched C file turns a
  pre-existing warning into the PR's red check whenever a PR touches that file
  for anything else.** #193 dropped an OF match table at line 953 of
  `aoc_alsa_compr.c`, and two `-Wformat` warnings at lines 671-672 on the base
  failed CI, while CONTRIBUTING §6.2 asks only for no new warnings. *Check:*
  for a red `W=1 builds` line, `git diff <base>...<head> -- <file> | grep
  '^@@'` against the warning's line numbers, and `git show <base>:<file> | sed
  -n '<line>p'` with the types it names; if the line is untouched, say so,
  offer the one-line fix as its own commit, and put the tool's rule (compare
  with the base's warnings, as the device-tree check does) to the maintainer.
  Extends L-30 and L-246. *From:* kernel #193, round 69.
- **L-1212. A "the rail stayed at use count 1 across the sleep" result is read
  through the controller's suspend code before it is called "not powered
  down".** dwc3 in device mode calls `dwc3_core_exit()` on every system sleep,
  so the PHY chain's `phy_exit()`/`phy_init()` ran each time and left the same
  count; the reading alone looked like "nothing calls phy_exit". *Check:* for
  a "use count unchanged across suspend", read the consumer's `suspend_common`
  for the role the board runs in and the PHY driver's exit for its child PHYs,
  and say which calls ran in between. Extends L-116. *From:* kernel #107,
  round 69.
- **L-1211. A driver that writes a new mode for a feature is walked through
  the next probe after a reset that skips its shutdown, for each mode it can
  leave behind.** #124's probe knew the inhibit (mode 4) survives a warm reset
  and handled it, but the new standby mode (0), written while sourcing VBUS,
  only got a warning, and every later write path was gated on flags a fresh
  probe clears, so charging never resumed. The question had been asked as
  "read the boost after a reset", which the hardware answered, and the charger
  side sat in the same code. *Check:* list every value the driver writes to a
  persistent PMIC register, then for each one read probe's handling and every
  later writer's condition (`git grep -n 'set_mode('`), and say what the boot
  after a `sysrq b` does with it. Extends L-213 and L-628. *From:* kernel
  #124, round 69.
- **L-1210. An energy model split away from idle states is asked for its own
  idle measurement, because the EM's inefficient-OPP marking raises a
  cluster's floor and, with no idle state, the cores wait in WFI at that
  floor.** Kernel #300's figures (560 to 464 mA) were taken with #280's C2
  states on; alone, its table keeps the 9a's A520s at 1197 MHz and above, and
  the published 9a tree has no idle states. *Check:* when a PR carries only
  part of a measured set, list which of the measured effects each part can
  cause; for an EM, recompute the inefficient OPPs (L-1139) and ask for the
  idle current from a boot of the part alone, beside the base. Extends L-1139,
  L-482 and C-12. *From:* kernel #300 with #280, round 69, 2026-11-26.
- **L-1209. A driver change that starts reporting the hardware's rate to
  devfreq is read for every governor line that uses `previous_freq`, because
  those lines now see the report, not the request.** Kernel #299's `target()`
  reports a floor-held MIF rate so `trans_stat` counts it, while
  `get_target()`'s hold still compares the new request with
  `devfreq->previous_freq`. *Check:* `grep -n previous_freq <driver>` and
  `drivers/devfreq/devfreq.c` (`devfreq_update_target`,
  `devfreq_monitor_resume`), and for each use say whether it meant "what we
  asked" or "what runs"; then name the floors that can hold the rate above the
  request on each board (`git grep clk_set_min_rate` for the clock, and their
  values against the lowest OPP). Extends L-1068 and L-206. *From:* kernel
  #299, round 69, 2026-11-26.
- **L-1208. When a contributor confirms an assistant co-wrote their commits in
  one repository, their kernel PRs of the same series are checked for
  `Assisted-by:` before the rebase merge.** The johannSo series restored
  `Co-Authored-By` on every omamobile commit after round 66's question, while
  the kernel commits (#282, #283) carry no `Assisted-by:`, and
  `kernel-pr-check` doesn't look for it. *Check:* `git log --format='%h
  %(trailers:key=Assisted-by)' base..head` on each kernel PR of an author who
  answered yes elsewhere. Extends L-216 and L-510. *From:* kernel #282 and
  #283 with #931, round 69.
- **L-1207. A ported driver whose message names another author is checked for
  that author in the commit's `Author:` and sign-offs, not only in the file's
  copyright.** Kernel #304's modemsmem driver kept Richard Acayan's copyright
  and `MODULE_AUTHOR`, while the commit's author and only sign-off were the
  porter's, and the gate said "signed off by their authors". *Check:* `git log
  --format='%an%n%B' base..head | grep -n -i "is .*'s from\|taken from\|ported
  from\|based on"`, and for each hit ask whether the named person is the
  commit author with a sign-off. Extends L-62 and L-594. *From:* kernel #304,
  round 69, 2026-11-26.
- **L-1206. An imported RFC's missing author sign-off is looked for in the
  RFC's own thread before the contributor is asked to get one.** Kernel #302
  carried a driver patch without Joel Selvaraj's `Signed-off-by` and asked how
  to handle it; Joel had posted it in a reply to the RFC two days after it
  went out ("You can include them in future revisions"). *Check:*
  `https://patchwork.kernel.org/api/1.3/patches/<id>/comments/` for the patch
  the gate names, grep the replies for `Signed-off-by:` from the author, and
  hand over the line with a `Link:`. Extends L-594 and L-1146. *From:* kernel
  #302, round 69, 2026-11-26.
- **L-1189. A firmware-written address read through a sliding BAR window is
  range-checked before it is read.** Kernel #295 read a trap record at the
  address the BCM4389 left in its shared area; `brcmf_pcie_tcm_addr()` moves
  the BAR1 window to any address it is given, so an unwritten or corrupt
  pointer reaches an arbitrary backplane address, where a powered-down domain
  faults, on the reference phone's Wi-Fi. *Check:* for each new
  `read_tcm*`/`copy_dev_tomem` whose address came from the device, look for
  `brcmf_pcie_valid_ram_range()` (or the bus's equivalent) before it, and read
  `tcm_addr()` for whether the window follows the address. Extends L-542 and
  L-875. *From:* kernel #295, round 68, 2026-11-25.
- **L-1173. A retry loop whose first step is "nothing to do if the state is
  already good" can skip the cleanup a failed previous attempt left undone.**
  In kernel #294, an attempt that loaded the model but failed to lock is
  followed by one that sees POR clear and returns success without locking.
  *Check:* for each retried function with an early "already done" return, walk
  the case where the previous attempt finished the main work and failed its
  last step, and see whether the early return restores that step. Extends
  L-727 and L-757. *From:* kernel #294, round 67, 2026-11-24.
- **L-1172. A guard-state fix tabulated for the rows its thread names is also
  run for a mid-charge miss followed by a neighbour band's edge.** Kernel
  #290's table (boot, in-band, hot and cold inhibits) was right, and a harness
  row the thread hadn't named showed that a miss while charging lets the next
  reading skip the inter-band hysteresis once, less restrictive than both the
  base and a run with no miss. *Check:* for each band, a row "inside band k
  near its edge, miss, just across into the less restrictive neighbour", run
  on base and head, and say in the review whether the result is the PR's
  stated intent. Extends L-1138 and L-1001. *From:* kernel #290, round 67,
  2026-11-24.
- **L-1146. An out-of-tree patch carried from another downstream tree is
  looked up on patchwork by its subject before its code is reviewed, because a
  newer posting may fix it.** Kernel #285 carried the 2023 v1 of a glink
  wakeup patch; a v2 posted the day before the review fixed a NULL and
  freed-`rpdev` dereference in the rx interrupt and a `CONFIG_PM_SLEEP=n`
  build break, both in the one line the PR adds. *Check:*
  `https://patchwork.kernel.org/api/1.3/patches/?project=<list>&q=<subject
  words>`, list every version with its date and state, diff the newest against
  the PR, and read its changelog for bugs the PR still has. Extends L-580,
  L-581 and L-140. *From:* kernel #285, round 66, 2026-11-23.
- **L-1145. A buffer registered with firmware is kept, not freed, when its
  deregistration fails, and a deregistration the author marks unverified is
  read as one that can fail.** Kernel #283 freed a listener's carve-out pages
  after an unconfirmed deregister call failed, so QSEE could write into the
  next allocation. *Check:* for each register/deregister pair with firmware,
  read the deregister's failure path to the free; the memory stays referenced
  (leaked until reboot, with a log line) unless the firmware confirmed the
  release. Extends L-304 and L-757. *From:* kernel #283, round 66, 2026-11-23.
- **L-1144. A name allow-list in front of a firmware "load this image" call is
  checked for whether the firmware call takes the name at all.** Kernel #283's
  TA allow-list compared the caller's `img_name`, while QSEE's `APP_START`
  takes only lengths and a physical address and names the app from its signed
  image, so any signed TA could load under an allowed name. *Check:* for every
  allow-list a PR puts in front of a firmware or SCM call, write out the
  call's arguments; if the checked field isn't among them, ask for a read-back
  after the call (here `qcom_scm_qseecom_app_get_id()` against the returned
  id) that ties the two together. Extends L-2 and L-458. *From:* kernel #283,
  round 66, 2026-11-23.
- **L-1143. A ramoops size that is not a power of two is rounded down at
  probe, so a layout argument built on it is checked against
  `ramoops_probe()`.** Kernel #282's `pmsg-size = <0x201000>` was meant to
  absorb downstream's extra zone; the kernel runs it as 0x200000 and grows the
  dmesg area instead. *Check:* for each `*-size` in a ramoops node,
  `is_power_of_2`; if not, recompute the zone offsets the way
  `ramoops_probe()` and `ramoops_init_przs()` do and compare with the comment.
  Extends L-245. *From:* kernel #282, round 66, 2026-11-23.
- **L-1142. "Without the property nothing changes" is read against where the
  PR sets the property: a SoC dtsi sets it for every board of that SoC.**
  Kernel #282 gated an RPMh read refusal on a new DT flag and then set the
  flag in `sm8150.dtsi`, so five other SM8150 boards changed on one phone's
  evidence; the binding and driver commits read as inert. *Check:* `git grep
  -n '<property>' <head> -- arch/`, and for each hit in a `.dtsi` list the
  boards that include it (`git grep -l '#include "<dtsi>"'`) and decompile one
  sibling's head DTB for the property. Extends L-849 and L-206. *From:* kernel
  #282, round 66, 2026-11-23.
- **L-1141. A new compatible a board adds to a shared SoC driver's match table
  is checked against the open PRs that change the same driver's data struct,
  which may already give the per-board choice.** Kernel #276 added
  `google,zumapro-komodo-decon` to carry a panel's modes while #181 was
  turning `modes` into per-SoC mode sets chosen by the bootloader's scanout
  size and #202 chose by the panel compatible: three mechanisms for one table,
  and only the new one changes the binding. *Check:* `gh pr list --json
  number,files` filtered to the driver file, `git diff <base> <head> --
  <driver> | grep '^[-+]struct\|^[-+].*_data = {'` per open PR, and name the
  mechanism the board should use. Extends L-104 and L-479. *From:* kernel #276
  with #181 and #202, round 66, 2026-11-23.
- **L-1140. A "the hardware does X whatever we program" claim in a
  shared-driver fix is checked against the vendor driver's register options
  for the same block before the workaround is accepted.** Kernel #291 changed
  s5p-mfc's VP9 NV12 layout because the v15 core "writes rows aligned to 16,
  whatever DPB stride it is given"; Google's
  `mfc_core_set_dec_codec_buffers()` writes a two-bit VP9 stride-alignment
  field in `D_INIT_BUFFER_OPTIONS` (2 when the DT's `vp9_stride_align` feature
  is set, as on gs201 and zuma), and 16 is that field's default. *Check:* grep
  the vendor driver's register setup (`mfc_core_reg_api.c`) for the codec with
  "align" or "stride", then the vendor DT for the feature flag that enables
  the branch; when there is one, ask for it to be tried before the layout
  changes. Extends L-61, L-113 and L-542. *From:* kernel #291, round 66,
  2026-11-23.
- **L-1139. An energy model added from a vendor profile is run through
  `em_compute_costs()` before its numbers are called "only an estimate".**
  Kernel #280's cl0 values give a cost per MHz of 45.1 at 324-820 MHz and 35.9
  at 1197, so the EM marks five OPPs inefficient and schedutil's
  `CPUFREQ_RELATION_LE` skips them: the little cores' floor moves from 324 to
  1197 MHz, a scheduling change the message didn't mention. *Check:* per
  cluster, `power / freq` from the top OPP down, flagging each state whose
  cost is not below the running minimum (an `awk` over the DTB's `opp-hz` and
  `opp-microwatt`), compare with the sibling SoC's table, and read the release
  config's default governor. Extends L-208 and L-823. *From:* kernel #280,
  round 66, 2026-11-23.
- **L-1138. A reset of a guard's state variable is tabulated from every prior
  state, the protective one included, before it is called a fix.** Kernel #290
  sent "no reading" to the "first reading" state so a boot near a band edge
  would charge, and from the out-of-range state the same line dropped the hot
  and cold hysteresis; a third party's harness found it the same day. *Check:*
  for a change to how a state machine leaves an error, write the table prior
  state x event -> next state for base and head (here -2, a band and -1, each
  followed by a miss and an in-band reading near an edge), and mark every row
  where the head is less restrictive than the base. Extends L-866, L-859 and
  L-1001. *From:* kernel #290, round 66, 2026-11-23.
- **L-1137. A new writable `power_supply` property is checked against the open
  PRs on the same driver for a property that serves the same purpose.** Kernel
  #281's `charge_behaviour` and kernel #266's `charge_control_*_threshold`
  both stop charging at a user's limit on the same `max77759-charger` supply;
  they conflict as text, but the design conflict (two writers of one inhibit)
  would survive a clean rebase. *Check:* `gh pr list --state open --json
  number,files` for the driver's path, then `git diff <base>...<head> | grep
  '^+.*POWER_SUPPLY_PROP_'` on each, and put the choice to the maintainer in
  every PR involved. Extends L-720, L-923 and L-104. *From:* kernel #281 with
  #266, round 66, 2026-11-23.
- **L-1136. An edge-triggered listener that reads its pin in a threaded
  handler is checked for edges it counts as nothing.** Kernel #274's boot
  record had `/proc/interrupts` at 1 on two lines while the driver's own count
  stayed 0: a rising edge whose level was gone by the read, which the driver
  drops silently. *Check:* for a GPIO-interrupt driver that decides on
  `gpiod_get_value()` in its handler, compare the `/proc/interrupts` count
  with the driver's event count in the same report; a difference is a short
  pulse or a pinmux latch, and which one is asked before the driver is trusted
  to act on real events. Extends L-380 and L-1064. *From:* kernel #274, round
  66, 2026-11-23.
- **L-1112. A "return early unless the board has X" fix for new PM hooks is
  confirmed in three places: the statements above the test, which tables set
  X, and what the base did with the same work item.** For kernel #267 that was
  one `dev_get_drvdata()` line above the test, one table with the field, and a
  base with no PM ops and an autocancelled delayed work on `system_wq`; the
  three together are what "unchanged on the reference phone" means, and they
  also answered the author's own follow-up question (the work keeps running
  across sleep there, as published). *Check:* `awk '/^static int
  <driver>_suspend/,/^}/'` on the head, `grep -n '<field>'` for the tables,
  and `git grep -c 'PM_OPS\|dev_pm_ops' <base> -- <file>`. Extends L-997 and
  L-206. *From:* kernel #267, round 65, 2026-11-21.
- **L-1098. A message-only push that answers a wording request is checked for
  the wrapping it had before.** Kernel #249's body gained the requested
  sentence and lost every line break in the same amend; the tree was
  identical, CI stayed green, and only checkpatch's `COMMIT_LOG_LONG_LINE`
  warning, printed under an `ok` line, showed it. *Check:* `git log -1
  --format=%B <old> | awk '{print length}' | sort -n | tail -1` against the
  new head's, and read the warnings under "checkpatch --strict: no errors" on
  every message-only push. Extends L-743 and L-216. *From:* kernel #249, round
  64, 2026-11-21.
- **L-1079. A restricted DMA pool is checked against the driver's largest
  single coherent allocation, not only against total size.** swiotlb serves at
  most `IO_TLB_SEGSIZE` x 2 KiB (256 KiB) per allocation, and ath11k's MHI
  download asks for 512 KiB segments, so no pool size makes it work. *Check:*
  grep the driver and its transport for `dma_alloc_coherent` sizes (`seg_len`,
  `sbl_size`, ring sizes) and compare the largest with 256 KiB before asking a
  board for a pool. Extends L-777. *From:* kernel #255 with #822, round 63,
  2026-11-20.
- **L-1078. A flag test asked out of a shared interrupt handler is best met by
  compiling the handler twice.** On kernel #254 an `__always_inline` body with
  a constant `bool` argument, and the handler chosen once at registration from
  the match data, removed the per-interrupt read on the reference phone's path
  entirely; the review then only has to confirm which handler `host_init`
  installs for each compatible. *Check:* when a per-SoC flag is read on a hot
  shared path, ask whether the choice can be made once at setup, and read the
  registration line for each match-data entry. Extends L-206 and L-301.
  *From:* kernel #254, round 63, 2026-11-20.
- **L-1072. "The other board's DTB is the same before and after" for a table
  moved into a shared dtsi is re-run with `dtc -s` on both gate outputs, and
  every sibling DTB is compared in the same loop.** For kernel #264 the gate's
  `build` and `build-base` trees gave all ten boards in one pass: eight
  byte-identical, the 8 Pro identical after sorting, the 8a alone changed;
  node order alone changes the blob's hash, so a sha256 compare would have
  read as a difference. *Check:* for each `*.dtb` in the SoC directory of both
  output trees, compare sha256 first, then `diff <(dtc -s -I dtb -O dts base)
  <(... head)`, and print each side's line count. Extends L-505 and L-293.
  *From:* kernel #264, round 63, 2026-11-20.
- **L-1071. "The firmware doesn't expose X" as the reason for a probe-skip is
  checked against who registers X in our tree and against a sibling consumer
  of the same provider on the same board.** Kernel #202's prepared branch
  skipped DECON's two ACPM clocks on the 7a for that reason, while `clk-acpm`
  registers them per SoC and the same PR enables the 7a's GPU on the same
  provider. *Check:* `git grep` the provider's registration table for the
  names, list the board's other consumers of that provider (`git grep
  '&<provider>' <soc>.dtsi`), and ask for `lsmod`, `devices_deferred` and the
  modprobe blacklists from a boot without the skip; where the board really
  lacks the clock, prefer `/delete-property/` in the board file to a flag in
  the shared driver. Extends C-1, L-399 and L-402. *From:* kernel #202, round
  63, 2026-11-20.
- **L-1068. A "the clock core returns without asking the firmware" comment is
  checked in `clk.c` for each call, and each `clk_get_rate()` on a NOCACHE
  clock is counted per second.** In kernel #279 the every-period
  `clk_set_rate()` is free (it compares the cached rate), while the GPU's
  `clk_get_rate()` every 50 ms is an ACPM query, 20 a second, because the
  device package keeps the GPU powered. *Check:* `clk_core_set_rate_nolock()`
  and `clk_core_get_rate_recalc()` on the base, the provider's flags, the
  polling interval, and the device package's runtime-PM rules for the device
  the driver treats as "suspended most of the time". Extends L-326. *From:*
  kernel #279, round 63, 2026-11-20.
- **L-1067. A driver that starts scaling a firmware DVFS domain the bootloader
  set is checked against the vendor's reboot and suspend rates.** Stock's
  gs201 MIF node carries `freq_info = <initial default_qos suspend min max
  reboot>` and sets 1014 MHz before a restart; kernel #279 restarts at
  whatever rate its governor left, and its only restore is a devm action that
  no reboot, panic or sysrq reset runs. *Check:* grep the vendor devfreq node
  for `freq_info`, `reboot_freq` and `suspend_freq`, list the driver's
  `.shutdown` and reboot notifier, and ask for the restart count so far plus
  one attended `sysrq b` from the lowest level. Extends L-213 and L-474.
  *From:* kernel #279, round 63, 2026-11-20.
- **L-1066. A new `MFD_CELL_OF` on a PMIC the reference phone binds is walked
  through `mfd_add_device()` for a board without the child node.** Kernel
  #278's two meter cells make the MFD core print "Failed to locate of_node"
  and register a dead device at every boot of the 7 Pro, the 7a and the Fold;
  a disabled child node makes the core skip the cell silently. *Check:* `git
  grep -n '"<pmic compatible>"' arch/` plus each device's `DTB_OVERLAYS` for
  boards that bind the parent, then read `mfd-core.c`'s three outcomes
  (matched, disabled, missing) for each, and the new driver's first lines for
  what it does without a firmware node. Extends L-50 and L-49. *From:* kernel
  #278, round 63, 2026-11-20.
- **L-1065. "Tested with a shim" means the device-tree probe path has not
  run.** Kernel #274's phone test handed the driver its GPIOs through a
  platform-data hook, so the property names, flags, phandle lookup and
  autoload of the merged file were untested, and the board node was enabled
  anyway. *Check:* grep the description for "shim", "hook", "out-of-tree" and
  "test-only"; diff the tested path against the PR's probe; ask for one boot
  of the PR's own DTB (kexec is enough for a probe, L-1062) or `status =
  "disabled"`. Extends L-45 and L-131. *From:* kernel #274, round 63,
  2026-11-20.
- **L-1064. A listener for a PMIC warning pin is read against what the vendor
  driver does around its pin read.** Kernel #274 polls the MAX77759's vdroop
  pins and releases on a clear level; Google's `google_irq_triggered_work()`
  clears `CHG_INT2` before it reads the pin and again on release, and names
  its handler `latched_irq_handler`, which suggests the pin follows latched
  bits a write-nothing driver never clears. *Check:* in the vendor driver,
  list every register write between the interrupt and the pin read and at
  release; if there is a clear, ask for a recorded real assertion with its
  release, or a bound, before a "polls until clear" design merges. Extends
  L-472 and L-542. *From:* kernel #274, round 63, 2026-11-20.
- **L-1063. When two vendor kernels for one phone disagree on a link timing,
  the `lspci -vv` of both link ends says which value the link runs at.** For
  kernel #269 the PCI core programs the larger of the two advertised
  T_POWER_ON values; the Wi-Fi function advertised 50 us, so the root port's
  constant decided, and the capability word in the driver's log could be
  recomputed from the constants. *Check:* ask for `L1SubCap` and `L1SubCtl2`
  of the root port and the function, and recompute the logged capability word
  (value << 19, scale << 16, common-mode time << 8). Extends L-210, L-441 and
  L-848. *From:* kernel #269, rounds 60 and 63, 2026-11-20.
- **L-1062. A kexec boot is accepted for what it shows and named for what it
  can't.** For kernel #268 it showed the device-tree probe on a tree without
  kernel #195 (pin controller on, driver bound, data flowing); it could not
  show Trusty or the fingerprint sensor (FF-A buffers stay mapped from the
  previous kernel), nor a cold power-on. The author found that the default
  `kexec_file_load` silently keeps the running DTB, and caught it by the FDT
  size. *Check:* for a kexec record ask for `kexec -c --dtb=`, the proof the
  new DTB is live (a node's `status` read from `/proc/device-tree`), and a
  list of what the previous kernel's state could have carried over; ask for a
  cold boot only for those. *From:* kernel #268, round 63, 2026-11-20.
- **L-1058. A board PR that is "a baseline, not bootable" is checked against
  the companion PR's records for the boots that already tried that shape, and
  for where the booting description lives.** Kernel #276's 41-line board file
  enables nothing; #914's plan shows two watchdog resets with such a file and
  SSH only after uncommitted board changes, with node descriptions in
  omamobile overlays. *Check:* count the enabled nodes of the head's DTB
  (`dtc -I dtb -O dts | grep -c 'status = "okay"'`), grep the companion's plan
  for `watchdog`, `-dirty` and "board DTS now", and ask for the description to
  move into the board file before the overlay PR is read. Extends L-109, L-149
  and L-71. *From:* kernel #276 with #914, round 63, 2026-11-20.
- **L-1057. A count of a per-controller driver message in a boot report is
  checked against the published driver's controller table.** Kernel #273 and
  #275 report five "irq number not available" lines on zumapro; the published
  `zumapro_pin_ctrl[]` still gives ALIVE an `eint_gpio_init` and its node has
  no `interrupts`, so the published driver should print six. A count that
  disagrees says the test kernel's driver isn't the published one, or a line
  was missed. *Check:* count the controllers whose data has the init hook and
  whose dtsi node lacks the property, compare with the report, and ask what
  the test kernel carries in that driver. Extends L-65, L-314 and L-345.
  *From:* kernel #273 with #275, round 63, 2026-11-20.
- **L-1056. `status = "disabled"` on a Samsung pin bank node removes the bank
  from the driver's view; it does not park its interrupts.** Kernel #273
  disabled `&gpa8` "to hold the TCPC's interrupt inactive".
  `samsung_banks_node_get()` iterates available children only, so the bank
  logs "Missing node for bank gpa8 - invalid DTB" and registers its GPIO chip
  without a node, and `dtbs_check` says nothing. *Check:* `grep -n -B10
  'status = "disabled"' <board files> | grep '&gp[a-z][0-9]* {'`; compare with
  the merged same-SoC sibling's bank, and ask for the dmesg line. Extends
  L-306 and L-239. *From:* kernel #273, round 63, 2026-11-20.
- **L-1022. `DTC_FLAGS_<board> += -@` is a size change on boards with a
  bootloader limit.** Kernel #249's Makefile line grew one board's DTB by 37 %
  (106 to 145 kB). *Check:* build the board's DTB with and without the flag
  using the build's own `dtc`, and put the two sizes in the review when the
  device's notes mention a kernel or image size limit. *From:* kernel #249,
  round 63, 2026-11-20.
- **L-1010. A userspace frequency floor is checked against the thermal cap in
  the governor's range code.** For #922's devfreq `min_freq`,
  `devfreq_get_freq_range()` clamps the minimum to the maximum, so the cooling
  device wins. *Check:* read the range function on the published branch for
  which of QoS min and max wins, and find the board's cooling map for the
  device; for cpufreq the same question is `freq_qos`. *From:* #922, round 63,
  2026-11-20.
