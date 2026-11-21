<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Kernel (linux-omarchy-mobile) (part 1 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
  omarchy-mobile overlays. *Check:* count the enabled nodes of the head's DTB
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
- **L-881. Before calling an ungated fix "another phone's", grep the
  reference phone's logs for its error line.** `ak7375_vcm_resume I2C failure:
  -6` was in a 7 Pro log from three days before kernel #272, which turned
  "gate it on the Fold" into "a 7 Pro change with a 7 Pro reason: run it
  there". *Check:* `grep -rh '<the message>' logs/ | sed 's/^.*kernel: //' |
  sort | uniq -c`, and read which code path prints it. Extends L-565 and
  L-493. *From:* kernel #272, round 61, 2026-11-18.
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
