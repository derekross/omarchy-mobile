<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Kernel (linux-omamobile) (part 2 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-997. New `dev_pm_ops` in a shared driver are read hook by hook for what
  runs before the board test.** Kernel #267's suspend hook gated its float
  step on the husky table but disabled the guard work for every board, and its
  resume hook queued a guard run for every board, while the message said other
  boards were unchanged; the object differs either way, so only reading shows
  it. *Check:* for each new `.suspend`, `.resume` and `.shutdown`, list the
  statements above the first board or match-data test, and say what each does
  on the reference phone at every sleep and wake (the 7 Pro wakes every few
  minutes with the modem up). Extends L-206 and L-627. *From:* kernel #267 and
  #277, round 63, 2026-11-20.
- **L-996. When a split moves commits to a new PR, re-list what the remaining
  PR's reference-phone run no longer covers.** Kernel #266's 7 Pro run was
  planned for seven commits, one of which added a `.shutdown` that stops the
  guard work on every board; after the split that hunk sits in kernel #277,
  behind a "husky" title, and the planned run of #266 doesn't exercise it.
  *Check:* `git diff <old head> <new head of the remaining PR>` for removed
  hunks outside the board's own gate (`grep -n 'of_machine_is_compatible'` and
  the board's table name around each), and carry each ungated one into the new
  PR's review as its own reference-phone point. Extends L-610 and L-665.
  *From:* kernel #266 with #277, round 63, 2026-11-20.
- **L-903. A disabled PCIe endpoint node is still read for its DMA
  confinement, because the overlay that enables it is written from the node as
  merged.** Kernel #255's `wifi@0,0` met "disabled behind an overlay", but
  nothing confined it, and the bench runs it records connected to a network
  with the chip able to reach all RAM. *Check:* for each new endpoint node,
  `grep -n 'memory-region\|iommus'` in it and its controller, compare with the
  reference phone's node, and ask for the confinement in the same commit even
  when `status = "disabled"`; where the pool goes is C-55's question.
  Extends L-777. *From:* kernel #255 with #822, round 61, 2026-11-18.
- **L-902. An "optional" call from a generic driver into a SoC driver's
  exported symbol is a module dependency for every board that loads the
  generic driver.** Kernel #253's check returns 0 without the DT property, but
  `pwrseq-qcom-wcn.ko` would still depend on `aoc_core.ko`, so the 7a's
  Bluetooth and the SDM845 phones would load the AoC core at boot (kernel #254
  did the same to the reference phone's Wi-Fi controller); a blacklist doesn't
  stop that. *Check:* for each new cross-subsystem call, find the exporting
  module (`obj-$(CONFIG_...)` in its Makefile) and both symbols' values in the
  built `.config`; if both are `m`, list the boards whose DT loads the caller
  (`git grep '<caller compatible>' arch/`) and what the callee's load does
  there. Extends L-20, L-238 and L-393. *From:* kernel #253 and #254, round
  61, 2026-11-18.
- **L-901. "Driver X already owns this range" in a commit message is checked
  against the published DTs for a second node on that address.** Kernel #252
  dropped the AoC's claim of `0x10000000` because exynos-chipid "already owns"
  it; on `github/omamobile` no gs201 or zumapro node but the AoC's names that
  range, so the conflict lived only in the author's test tree. *Check:* `git
  grep -n '<address>' <base> -- arch/arm64/boot/dts/exynos/google/` and the
  claiming driver's match table against the compatibles those nodes carry.
  Extends L-314 and L-489. *From:* kernel #252, round 61, 2026-11-18.
- **L-900. A driver that calls `set_dma_ops()` works on arm64 only while Xen
  is configured, and nothing says so.** `ARCH_HAS_DMA_OPS` is selected by
  arm64 only `if XEN`; elsewhere `set_dma_ops()` is an empty inline. Our
  Trusty transport hands Trusty its buffer ids through such ops, and
  `drivers/trusty/Kconfig` has no dependency on it, so a config without Xen
  would pass kernel addresses instead, silently. *Check:* `git grep -n
  set_dma_ops drivers/` on the base; for each hit on a phone's path, `grep
  ARCH_HAS_DMA_OPS` in the built `.config` and the driver's Kconfig for a
  dependency. Extends L-20 and L-238. *From:* kernel #251, round 61,
  2026-11-18.
- **L-898. A branch that a probe-time table lookup keeps dead goes live when
  another PR adds a matching row, and the rebase onto that PR is its first
  run.** Kernel #202's panel-modes branch needs `dc->dsim`, which survives
  only for timers in `gs_dsim_rates[]`; kernel #181 adds the Pixel 7's row,
  and the 7a's bootloader pair is the same, so the rebase turns on a path no
  boot has taken, with a 90 Hz mode the DECON refuses. *Check:* when a PR is
  to be rebased onto another, `git diff <base> <other head>` for new rows in
  every table the PR's gating pointer depends on, and compare each new row
  with the PR's own board values. Extends L-490 and L-730. *From:* kernel #202
  with #181, round 61, 2026-11-18.
- **L-883. A first board file with its only link disabled is a build
  artifact, not a first light, and the review says "don't flash it" in
  words.** Kernel #273 disabled USB pending a glue PR; with our init's
  no-USB-host panic and a marked slot B, booting it means a reset loop and the
  buttons. *Check:* for a new board, find the node that carries the link
  (`&usb` and its PHYs) and read its `status` in the built DTB; if it is
  disabled, the draft comment says not to boot it and names the PR that
  settles how it is enabled. Extends L-28, L-158 and L-31. *From:* kernel #273
  with #271, round 61, 2026-11-18.
- **L-882. Google publishes a device-tree repository per Pixel 9 family
  device too.** `kernel/devices/google/comet` (branch
  `android-gs-caimito-6.1-android16`) has `dts/zuma-comet-camera.dtsi`,
  `-hall-sensor.dtsi`, `-usb.dtsi` and the `zumapro-comet-*.dts` boards, which
  settled kernel #272's power order and shared reset and #273's board id.
  *Check:* `git ls-remote
  https://android.googlesource.com/kernel/devices/google/<codename>`, then
  `.../+/<commit>/dts/<file>?format=TEXT | base64 -d`. Extends L-177 and
  L-220. *From:* kernel #272 and #273, round 61, 2026-11-18.
- **L-881. Before calling an ungated fix "another phone's", grep the reference
  phone's logs for its error line.** `ak7375_vcm_resume I2C failure: -6` was
  in a 7 Pro log from three days before kernel #272, which turned "gate it on
  the Fold" into "a 7 Pro change with a 7 Pro reason: run it there". *Check:*
  `grep -rh '<the message>' logs/ | sed 's/^.*kernel: //' | sort | uniq -c`,
  and read which code path prints it. Extends L-565 and L-493. *From:* kernel
  #272, round 61, 2026-11-18. (Extended 2026-11-23: the evidence can also be
  in the commit message of the code the fix changes. "Every boot of a Pixel 7
  Pro starts with no reading" in `1a9d1d4e9289` made kernel #290 a 7 Pro fix
  with a 7 Pro reason, while the review laptop's logs had no such line; read
  `git log --format=%B -3 -- <file>` or `git log -L` for the touched function
  before writing "another phone's fix". *From:* kernel #290, round 66.)
- **L-880. "Nothing changes for existing boards" for a media driver is
  checked against the reference phone's overlays and its camera start, not the
  board DTS's `status`.** Kernel #272 read as a Fold-only PR, but cheetah's
  `DTB_OVERLAYS` enable the IMX386 and both ak7375 nodes and
  `omamobile-camera-start` loads the modules at every boot, so an ungated 1 ms
  wait in `ak7375_vcm_resume()` and a changed endpoint parse were 7 Pro
  changes. *Check:* `git grep -n '<compatible>' <base> --
  arch/arm64/boot/dts/exynos/google/`, then `grep DTB_OVERLAYS
  device/cheetah/device.conf` and the blacklist's comment for who loads the
  module. Extends L-49, L-206 and L-348. *From:* kernel #272, round 61,
  2026-11-18.
- **L-879. A binding's `then:` is fed the SoC dtsi's own node.** Kernel
  #271's schema demanded a clock name the SoC description doesn't use, so the
  "one-line board follow-up" would have failed `dtbs_check`; a hand-made node
  with the dtsi's names showed it in a minute. *Check:* copy the dtsi node,
  change only the compatible, compile it and `dt-validate` it against the PR's
  processed schema. Extends L-102 and L-236. *From:* kernel #271, round 61,
  2026-11-18.
- **L-878. A dwc3 glue built on `dwc3_core_probe()` is checked for the
  runtime PM callbacks the core expects.** The core enables runtime PM itself;
  a glue with only sleep callbacks leaves a device that userspace can mark
  runtime-suspended with no resume path, and the gadget then disables its own
  interrupt. *Check:* `grep -n 'RUNTIME_PM_OPS\|pm_runtime' <glue>` against
  `dwc3-generic-plat.c`, and `grep -n 'pm_runtime_suspended'
  drivers/usb/dwc3/gadget.c` for what a suspended status does. *From:* kernel
  #271, round 61, 2026-11-18.
- **L-877. A glue driver that orders a PHY before its core is checked against
  how the same-SoC sibling's board node solves it, and against the PHY
  driver's history for the hang it names.** Kernel #271 initialises the USB2
  PHY before `dwc3_core_probe()` and holds it powered across sleep; the 9a's
  merged node gives plain `snps,dwc3` the sub-control clock for exactly that
  early register access, and `da56cbe9ff2f` had already fixed the zuma hang in
  the PHY's exit, with a measured A/B that contradicts the PR's reasoning.
  *Check:* `git grep -n -B6 -A12 '^&usb {' <base> --
  arch/arm64/boot/dts/exynos/google/<soc>-*.dts`, `git log <base> --
  drivers/phy/samsung/phy-exynos5-usbdrd.c` for the words of the hang, and ask
  for one boot on the published base with the sibling's node before a second
  compatible for the same block. Extends L-105, L-113 and L-116. *From:*
  kernel #271, round 61, 2026-11-18.
- **L-876. A fix for a warning is checked for whether any published board can
  raise it.** The `gpiolib.c` warning kernel #270 fixed needs a GPIO shared by
  two DT nodes; no board on `omamobile` has one and 1,051 logs have no such
  line, so the patch had no user on the base and no test there. *Check:* grep
  `logs/` for the warning's file:line, and name the DT construct that triggers
  it and the PR that brings it. Extends L-317 and L-489. *From:* kernel #270,
  round 61, 2026-11-18.
- **L-875. Adding a gpiolib callback to a shared `gpio_chip` is read through
  every gpiolib call site that tests for it, registration first.** Kernel
  #270's `get_direction()` looked like "one read when the proxy asks", but
  `gpiochip_add_data_with_key()` calls it for every line of every bank at
  probe, `gpiod_request_commit()` on every request, and
  `gpiochip_lock_as_irq()` starts refusing outputs, which
  `exynos_irq_request_resources()` calls before it sets the EINT function.
  *Check:* `git grep -n '->get_direction' <base> -- drivers/gpio/gpiolib*.c`
  (the same for any new `gpio_chip` or `pinctrl_ops` member), list what each
  caller now does on the reference phone, and for a new probe-time register
  read walk every enabled controller of every SoC against AGENTS' "registers
  that abort" list (gs101's `pinctrl_gsactrl` is enabled in `gs101.dtsi`).
  Extends L-465, L-206 and L-51. *From:* kernel #270, round 61, 2026-11-18.
- **L-866. A change from "round up" to "round down" on a linear-range lookup
  is checked at the top of the range and for the caller's "property missing"
  value.** `linear_range_get_selector_low_array()` returns the highest
  selector, with no error, for any value above the range, where the `_high_`
  variant with `found` refused it; kernel #266's rounding commit so turned a
  battery node without `constant-charge-current-max-microamp` (`-EINVAL`
  copied into a `u32`) from a failed probe into a 4 A charge current. *Check:*
  read both helpers' out-of-range returns in `lib/linear_ranges.c`, feed the
  setter `(u32)-EINVAL`, max + 1 and min - 1 (by reading or a KUnit case) and
  compare with the base; `git grep -n 'get_battery_info' <driver>` for fields
  copied without a `>= 0` test. Extends L-208 and L-52. *From:* kernel #266,
  round 61, 2026-11-18.
- **L-865. "As stock does" for an end-of-charge rule is read at the vendor's
  tier test as well as its margin.** Kernel #267 copied `max77759_is_full()`'s
  50 mV and 200 mV but acted only in the last tier, where stock's function
  returns false for every other tier; the vendor's own comment names the
  small-adapter case the PR's phone was in. *Check:* list the vendor
  function's early returns and what each means for the caller, and compare
  with the new code's `DONE_NONE` paths. Extends L-542 and L-77. *From:*
  kernel #267, round 60, 2026-11-17.
- **L-864. State that a PR resets "per plug-in" is traced to the event that
  resets it, on the board the feature is for.** Kernel #267's restart budget
  was cleared by a flag set only from the `tcpm-source` notifier, and husky's
  Type-C node is disabled, so "five per plug-in" was five per boot. *Check:*
  `grep -n '<flag> = true'`, follow the caller to its trigger, and read that
  trigger's node status in the board DTS. Extends L-438 and L-396. *From:*
  kernel #267, round 60, 2026-11-17.
- **L-863. A guard that reads another supply is checked on a unit running the
  published device tree, not the author's.** Kernel #267's temperature tiers
  read the gauge; the author's 8 Pro had a local gauge model and read 37-39 C,
  while a second 8 Pro on the published kernel read 22.0 C in 2450 samples.
  *Check:* name the supply and property each guard input comes from, read the
  published DTS for what configures it (a model, a thermistor setting), and
  search the device's issues for another owner's log of that property; a
  constant input is a blind guard. Extends L-99, L-629 and L-169. *From:*
  kernel #267 with #761, round 60, 2026-11-17.
- **L-862. A float voltage in a battery node is checked against three places
  in the vendor's GPL data: the board maximum, the top of the step table, and
  the aging schedule.** Kernel #267's 4.45 V for husky was "a bit under
  stock"; Google's `fv-max-uv` and top tier are 4.48 V, and
  `aafv-ref-cycles`/`aafv-ref-offset` in `zuma-husky-battery.dtsi` lower the
  float 20 mV per 200 cycles to 4.38 V. *Check:* fetch
  `<soc>-<board>-battery.dtsi` and `-charging.dtsi` from
  `kernel/devices/google/<device>`, grep `fv-max-uv`, `chg-cv-limits`, `aafv`
  and `aact`, read `gbms_aafv_get_offset()` for how the schedule indexes, and
  ask for the unit's `cycle_count`; the DTS comment cites the file. Extends
  L-52, L-100 and L-208. *From:* kernel #267, round 60, 2026-11-17.
- **L-861. A charge limit or defender polled by a work item is asked "what
  happens asleep on the charger" before its settings page is reviewed.**
  Kernel #266's thresholds run from the guard's delayed work, which s2idle
  stops while the chip charges on; the author's phone held a sleep inhibitor
  that no PR ships, and #860's "held at 90 % overnight" rested on it. *Check:*
  find what schedules the limit's check and whether it runs in s2idle; grep
  the dependent userspace PR's evidence for an inhibitor or a local unit; ask
  for the decision (stay awake, wake for it, or say so). Extends L-367 and
  L-651. *From:* kernel #266 with #860, round 60, 2026-11-17.
- **L-860. Marking registers volatile in an MFD's regmap is a change for every
  board that binds the chip, whatever the commit that needs it gates on.**
  Kernel #266 made CHG_CNFG_00..04 volatile for a husky read-back; with it
  every `regmap_update_bits()` on mode, current and float reads the chip first
  on the 7 Pro too. *Check:* `git grep` the MFD's compatible across board DTS
  files, list each driver call on the range, and say for the reference phone
  what used to come from the cache; grep open PRs for messages that rely on
  "the cache skips the write". Extends L-151 and L-369. *From:* kernel #266
  with #261, round 60, 2026-11-17.
- **L-859. "This board's value is an exact step, so nothing changes there" is
  checked through every value the driver computes, not only the one it
  reads.** Kernel #266's round-down left cheetah's 1466730 uA alone at probe,
  but the temperature guard computes percentages of the capacity, and 10 % of
  4926 mAh sits between two steps: the 7 Pro's 0-10 C tier went from 533 to
  467 mA. *Check:* list every caller of the changed setter, feed each board's
  capacity through each table cell old and new (a ten-line script), and print
  the cells that differ. Extends L-447 and L-27. *From:* kernel #266, round
  60, 2026-11-17.
- **L-858. A restructured shared function can't be shown unchanged by an
  object diff: say so and name the cheapest reference-phone run.** Kernel #265
  moved the 7 Pro's charge arithmetic into helpers behind a table pointer, so
  "identical objects" was out and a per-function diff meaningless. *Check:*
  read old and new side by side for the default data (loop bounds, array
  cells, the order of `min()`), find the test that pins the default numbers,
  and put one attended boot on the reference phone (the log line and the
  registers the code writes) in the merge plan. Extends L-8 and L-307. *From:*
  kernel #265, round 60, 2026-11-17.
- **L-854. A command table transcribed from a vendor DT byte string is checked
  for its radix against the code that parses it.** Kernel #260's panel table
  had `39` and `15` in decimal where the vendor's hex string means 0x39 and
  0x15, and the parser's `switch` tests the hex values, so every command took
  the default branch. *Check:* for each field the parser switches on, grep the
  table for a value that reaches each case; a case nothing reaches is the
  finding. Extends L-508 and L-61. *From:* kernel #260, round 60, 2026-11-17.
- **L-853. A second part added to a shared input driver is checked for the
  device name it reports, against every package that matches that name.**
  Kernel #260 changed `focaltech_ft3658`'s input name to "FocalTech
  FT3658/FT8756" for all devices, and the Pixel 7's fingerprint service finds
  its touchscreen by the exact string "FocalTech FT3658". *Check:* `git diff`
  the driver for `input->name`, `dev_info` and `MODULE_ALIAS` changes, then
  `git grep -n '<old name>' origin/main -- packages tools` in omamobile;
  a per-part name goes in match data. Extends L-8 and L-277. *From:* kernel
  #260, round 60, 2026-11-17.
- **L-850. A "Sources:" or "Tested-on:" paragraph added below the trailers
  takes the sign-off out of the trailer block on every commit it is added
  to.** Kernel #202 answered "message bodies need the sources and the kernel
  release" by appending both after `Signed-off-by:` on all seven commits, and
  the gate still said "signed off". *Check:* when we ask for sources or a test
  note, say "in the body, above the trailers", and run `git interpret-trailers
  --parse` on every commit of the next head. Extends L-119, L-216 and L-585.
  *From:* kernel #202, round 60, 2026-11-17.
- **L-849. A shared-driver feature keyed on a generic DT property is called
  "inert" only after grepping every board's DT for the property.**
  `supports-clkreq` is on no Exynos board, so kernel #269 changes no phone,
  and the first board to add it carries the phone test. *Check:* `git grep -n
  '<property>' <base> -- arch/arm64/boot/dts` and the devices' overlays in
  omamobile. Extends L-206. *From:* kernel #269, round 60, 2026-11-17.
- **L-848. "The value Google's driver uses" is read on every kernel branch the
  phone shipped with, and in both repositories.** For kernel #269 the Pixel
  7's 5.10 driver (`kernel/gs`) writes T_POWER_ON 130 us in
  `exynos_pcie_rc_set_l1ss()`; the 6.1 driver (`kernel/google-modules/soc/gs`)
  writes 200 us and keeps 130 us only in an uncalled function. One branch read
  alone calls the claim right, the other wrong. *Check:* list the device's
  branches (`+refs?format=TEXT`) in both trees, fetch the cited function from
  the oldest and the newest, diff the constants, and ask the commit message to
  name the branch. Extends L-113, L-152 and L-596. *From:* kernel #269, round
  60, 2026-11-17.
- **L-847. A disabled board node meant for an overlay is checked for every
  provider its GPIOs and pin groups hang on, and the overlay PR is read for
  each one the board leaves disabled.** Kernel #268's `gnss@0` uses gph2,
  whose controller `pinctrl_hsi2` is disabled in `gs201.dtsi`; neither the
  board commit nor #861's overlay enabled it, and the contributor's phone
  bound the driver only because its tree also carried kernel #195. *Check:*
  decompile the head DTB with the build's dtc; for each `&bank` in the node's
  `*-gpios` and each `&pinctrl_x { group }` block read the controller's
  `status`, grep the overlay for that controller's path, and ask for a boot of
  the PR's own tree with the overlay. Extends L-306, L-471 and L-314. *From:*
  kernel #268 with #861 and kernel #195, round 60, 2026-11-17.
- **L-845. A board PR that does what a shared dtsi's comment says a board must
  not do changes the comment in the same commit.** `zuma.dtsi` says a board
  with lower BCL caps "needs tables of its own"; kernel #264 added marks by
  node path instead. *Check:* grep the included dtsi for comments that say
  what "a board" does and read them against the PR's approach. Extends L-244
  and L-545. *From:* kernel #264, round 60, 2026-11-17.
- **L-843. A shared-driver change extended to a second chip is checked against
  that chip's own regmap tables, and a comment that says "stays read-only" is
  grepped across the driver family for the registers the change writes.**
  Kernel #262 took #233's SMPL/WTSR clear to the S2MPG14, whose RTC write
  table excludes both registers by name; the write still lands through
  `reg_update_bits` on an uncached map (L-163's note), so the phone test
  passes and the comment becomes false. Our request named the table comment in
  `sec-acpm.c` and missed "no GPIO or protection writes" in `sec-common.c`,
  from the same commit. *Check:* for each `regmap_*_bits()` extended to a new
  `device_type`, read that type's `regmap_config` (`wr_table`, `cache_type`,
  the bus's `reg_update_bits`); `git log -S'<phrase>' -- drivers/mfd` for the
  commit that wrote the rule and name every sentence it added. Extends L-163,
  L-176 and L-545. *From:* kernel #262, rounds 60 and 61, 2026-11-18.
- **L-842. A fix that clears a "manual" bit so a chip chooses for itself
  changes what the driver's own limit parameter means, and every decision that
  quotes the parameter is re-read.** With NO_AUTOIBUS clear on the MAX77759,
  `default_ilim_ua=500000` is a start value and the sysfs limit under-reports;
  an open decision for another Pixel quoted it as "the 7 Pro's limits".
  *Check:* for a change to an auto/manual control bit, find the parameter or
  property that sets the manual value, `git grep` the plans, AGENTS and open
  PR threads for it, and say what it means after the change. Extends L-529 and
  L-519. *From:* kernel #261, round 60, 2026-11-17.
- **L-822. A "no limiter, so stay under stock's limiter caps" rule is checked
  against every key of the limiter table, and against the clock ceiling the
  device package sets.** Kernel #264 marked each CPU level above
  `zuma-akita-bcl.dtsi`'s caps turbo-mode, while the same `freq_qos` blocks
  cap the GPU at 580 to 723 MHz and #832 copied the 8 Pro's
  `zuma_gpu_max_khz=890000`; the 8 Pro's vdroop1 row allows 890, no row of the
  8a's does. *Check:* fetch `<soc>-<device>-bcl.dtsi` for the board and the
  sibling it copies, tabulate each `freq_qos` child per row (cpucl*, gpu,
  tpu), and compare the board's top OPPs and every `*_gpu_max_khz` in the
  device package with the row maximum; grep the PR's plan for its own stated
  rule. Extends L-386 and L-208. *From:* kernel #264 with #832, rounds 59-60,
  2026-11-17.
- **L-777. A device that runs vendor firmware on untrusted input, enabled with
  its IOMMU in bypass, is a security decision for the maintainer, and stock's
  device tree says what confines it.** #250's MFC parses browser video with
  Google's closed firmware and DMA to all RAM below 4 GiB; stock's
  `gs201-mfc.dtsi` puts two System MMUs and `samsung,tzmp` in front of it, and
  `gs201-s2mpu.dtsi` two S2MPUs. The maintainer's decision (2026-11-15): such a
  node stays `disabled`, and an omamobile overlay turns it on, until the
  IOMMU is described. *Check:* for any new DMA master a board enables, grep
  Google's SoC dtsi for its `iommus`, `s2mpu` and `tzmp` lines, say what
  confines it in our tree (an IOMMU, a restricted pool, nothing), and ask for
  the node disabled with an overlay unless something confines it. Extends the
  Wi-Fi restricted-pool decision and L-2. *From:* kernel #250, round 57,
  2026-11-14.
- **L-766. A boot argument a board PR adds for safety is grepped against that
  device's bring-up overlays, because an overlay's `/chosen/bootargs` replaces
  the whole string.** Husky's `klog.dtso` and `panic-probe.dtso` (and akita's
  `ufs-probe.dtso`) set their own `bootargs` without `mem_sleep_default`, so
  a boot with one of them loses what kernel #244 adds. *Check:* `git grep -l
  'bootargs =' origin/main -- device/<codename>` in omamobile, look for
  the new argument in each hit, and name in the review the overlays that
  reach the Arch session without it. Extends L-49, L-207 and L-315. *From:*
  kernel #244, round 52, 2026-11-11.
- **L-741. A panel size "from Google's panel driver" is checked against the diagonal and the same tree's touch node.** For akita, `panel-google-ak3b.c` says 70 x 149 mm, while 6.1 inches at 1080x2400 is about 64 x 141, and `zuma-akita-touch.dtsi` has `goodix,panel-height-mm = <141>`; the device's NOTES had held the value back for that reason. *Check:* compute `sqrt(w² + h²) / 25.4` against the marketed diagonal, grep the stock touch dtsi for `panel-height-mm`, and grep the device NOTES for an earlier hold. Narrows L-352. *From:* kernel #241 with #650, round 51, 2026-11-11.
- **L-678. An enabled board node whose driver the shared config doesn't build
  is inert only until the config PR, and its blacklist must reach phones
  first.** Kernel #237 adds enabled GNSS nodes; #594 adds
  `CONFIG_EXYNOS_GNSS_IF_SPI=m` and the blacklist together, but the kernel
  package and the device package ship separately. *Check:* for each new
  enabled node, grep the driver's Kconfig symbol in `kernel/configs/` and the
  device's `kernel.config`; if absent, find the PR that adds it and the
  modprobe guard, and put "device package no later than the kernel" in the
  merge plan. Extends L-37 and L-387. *From:* kernel #237 with #594, round 49,
  2026-11-10.
- **L-332. A delayed "auto-off" work in a driver is checked for re-arm, cancel
  and remove order.** Kernel #126's LHBM timer used `schedule_delayed_work()`,
  a no-op while the work is pending, and never cancelled it on off, so an
  off-on within 3 s was cut short; its `remove()` cancelled before removing
  the sysfs attribute that queues the work, and could leave a lit circle with
  no timer. *Check:* off cancels, on uses `mod_delayed_work()`, and remove
  goes attributes away, state off, cancel sync, detach. The Pixel 7 Pro's
  s6e3hc4 LHBM on `omamobile-int` is the local precedent. *From:* kernel #126,
  round 29.
- **L-331. A fixed sleep between NCI commands while the controller resets is
  checked against the core's request pairing.** Kernel #131 sends
  PROP_NFC_MODE_SET, sleeps 200 ms, then sends CORE_INIT. The core's
  `nci_core_reset_ntf_packet()` completes the pending request unconditionally,
  so a late CORE_RESET_NTF completes whatever is pending, and every later
  request takes the previous one's response; the vendor HAL waits for the
  notification, with a 500 ms timer. *Check:* for any `msleep` between NCI
  commands, find which notification the vendor HAL waits for there and whether
  the core completes requests from it (`ntf.c`, `rsp.c`); prefer leaving the
  request pending until the notification arrives. Extends L-61. *From:* kernel
  #131, round 29.
- **L-330. A board that reuses a shared pin group for a different part
  inherits the reference phone's pulls.** Panther's touch node uses gs201's
  `ts_irq` (`PULL_NONE`, cheetah's), while Google's `gs201-panther-touch.dtsi`
  overrides `&ts_irq` to pull-up for the FT3658. *Check:* for each shared
  pinctrl label a board PR references, `grep -n '&<label> {'` in the device's
  stock touch, common and board dtsi files; an override goes in the board DTS,
  never in the shared group. Extends L-75 and the tegu GPA5 pull gotcha.
  *From:* kernel #134, round 29.
- **L-329. Before telling a contributor that a controller DMAs, read the board
  node in our DT and the driver's DMA condition.** gs201's USI SPI nodes have
  no `dmas`, so `spi-s3c64xx` runs in polling mode (`polling` is set when the
  node has no `dmas` property); stock adds `dmas` in its board files. For a
  DMA-safe buffer inside a struct on arm64, `____cacheline_aligned` (64 bytes)
  is below `ARCH_DMA_MINALIGN` (128): suggest `__aligned(ARCH_DMA_MINALIGN)`.
  *Check:* `dmas` in our board's node, the driver's `can_dma` path, then the
  alignment macro. See C-20. *From:* kernel #109 and #133, round 29.
- **L-308. An out-of-tree module installed under `updates/` disappears with
  every kernel push.** #136's runbook put a regulator module in
  `/usr/lib/modules/$(uname -r)/updates`, and the charger and TCPC wait for
  that regulator through DT supply links, so the next `push` boots without
  them. *Check:* grep runbooks for `updates/`, trace the DT consumers of the
  module's nodes, and require the runbook to say what boots without it and to
  reinstall it after each `push`. *From:* #136, round 28.
