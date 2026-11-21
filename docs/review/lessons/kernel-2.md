<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Kernel (linux-omarchy-mobile) (part 2 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
  `git grep -n '<old name>' origin/main -- packages tools` in omarchy-mobile;
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
  omarchy-mobile. Extends L-206. *From:* kernel #269, round 60, 2026-11-17.
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
  node stays `disabled`, and an omarchy-mobile overlay turns it on, until the
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
  'bootargs =' origin/main -- device/<codename>` in omarchy-mobile, look for
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
- **L-307. A per-function object diff ends each function at its symbol size
  and normalises absolute branch targets.** With inline alternatives, arm64's
  readl replacement pool sits after the last function in `.text`, so new
  readls elsewhere "changed" `gs_dsim_wait_fifo`; unstripped `0x… <fn+off>`
  targets flagged two more. *Check:* cut each function at its `llvm-nm -S`
  size (or treat a trailing `dmb osh`/`ldar` block as the pool), and first
  check the normaliser reproduces a known result (base to #88). Extends L-153
  and L-247. *From:* kernel #125, round 28.
- **L-306. A provider merged as `status = "disabled"` turns a board's `&label`
  reference into a silent runtime defer.** `dtc` and `dt-validate` both pass
  the lynx draft without `&pinctrl_hsi2 { status = "okay"; }`. *Check:* for
  every `&bank` or `&provider` a board PR references, read the provider node's
  status in the dtsi at the base, and require the board to enable it. Extends
  L-240. *From:* kernel #98 with #123, round 27.
- **L-305. When a driver swallows a provider's `-EPROBE_DEFER` and falls back,
  follow the fallback's own lookups before calling the result unpowered.**
  hci_qca drops `pwrseq_get()`'s defer, but its fallback asks for regulators
  that point at the PMU's `ldo` nodes, which nothing registers, so
  `of_regulator_dev_lookup()` defers anyway. *Check:* for each supply phandle
  in the fallback path, find who registers that node; a node with no regulator
  device defers, and only a missing property falls back to a dummy. *From:*
  kernel #98, round 27.
- **L-304. A devm action that uses a resource is registered after that
  resource is acquired.** Devres unwinds in reverse, so #124's restore action,
  registered before `devm_regulator_get_optional()`, ran after
  `regulator_put()` had freed the boost: a use-after-free on unbind with host
  mode on. *Check:* when a commit adds a resource that an earlier devm action
  or `.remove` uses, list the devm registrations in order, confirm each action
  comes after everything it touches, and read any "unwound in reverse" comment
  against that order. *From:* kernel #124, round 27.
- **L-269. A power sequencer keeps a shared supply up only while another of
  its targets has a consumer.** `pwrseq-qcom-wcn` reference-counts its
  regulators across the Bluetooth and Wi-Fi targets; with Bluetooth as the
  only consumer (lynx has no PCIe Wi-Fi node), Bluetooth off still drops the
  buck. *Check:* read the sequencer's unit dependencies and the core's
  `enable_count`, then list which targets have a consumer in that board's DT.
  Corrects L-241's advice; see C-16. *From:* kernel #98, round 25.
- **L-236. A binding's numeric constraints are checked against the stock
  value of every phone that may use the property, the reference phone
  first.** #95's `multipleOf: 47000` rejects stock cheetah's
  `cirrus,vpbr-thld-uv = <3000000>`, which Google's driver rounds down.
  *Check:* `grep -rn <property>` in the stock live DTs, then feed that value
  through dt-validate. Extends L-52 and L-102. *From:* kernel #95, round 23.
- **L-237. Before accepting a per-compatible constant for a firmware layout,
  check whether the vendor driver reads it from the device.** #93's 14-byte
  GT9895 record is right, but Google's driver takes it from
  `point_struct_len` in the IC info goodix-berlin already parses. *Check:*
  grep the vendor driver for where the value comes from before agreeing to
  match data. Extends L-53 and L-72. *From:* kernel #93, round 23.
- **L-238. A Kconfig `select` of a symbol that doesn't exist is silent, and a
  sibling that selects the right one hides it.** #114 selects `CS_DSP` (the
  symbol is `FW_CS_DSP`); it built because cs40l26-vibra and the CS35L41
  codec select the real one. *Check:* `git grep -n '^config <SYM>$'` for
  every selected symbol, then build with the siblings off. Extends L-20 and
  L-143. *From:* kernel #114, round 24.
- **L-239. A board DT is checked against the condition its binding text
  states.** Raven's DSIM got `google,decon` ("when no KMS driver runs it") in
  the commit that enabled gs-decon's KMS on that DECON, leaving two drivers
  doing unlocked read-modify-writes of `TRIG_CON`. *Check:* for each optional
  property a board sets, read its binding description and confirm the board
  meets it. *From:* kernel #116, round 24.
- **L-240. A board PR is built against the published branch's labels, not
  the author's tree.** #98 references `&gph2`, which gs201 has only on the
  integration branch. *Check:* for every `&label` a board PR adds, `git grep
  '<label>:' github/omamobile -- arch/arm64/boot/dts/`; if missing, `git log
  -S` on `omamobile-int` for the owner. Extends L-149 and C-10. *From:*
  kernel #98, round 24.
- **L-241. A supply shared by two radios is checked for what each driver does
  at power-off.** hci_qca's WCN6855 path disables every supply when Bluetooth
  goes down, so a fixed regulator on lynx's shared buck drops Wi-Fi with it;
  Google's driver never drops that pin. *Check:* read each consumer's
  power-off and runtime-PM paths, compare with the vendor driver, and prefer
  the upstream power sequencer (`qcom,wcn6855-pmu`). Extends C-9 and L-67.
  *From:* kernel #98, round 24. *Corrected 2026-10-28:* the sequencer keeps
  the buck up only while Wi-Fi is also its consumer (L-269, C-16).
- **L-242. A firmware-naming driver can pick different files for two
  revisions of one chip.** btqca adds a `g` NVM variant for some `soc_id`
  values, so lynx's two revisions load different files; one phone's
  "tested" covers one. *Check:* compute the file names from each owner's
  reported version. *From:* kernel #98, round 24.
- **L-243. "Clock gating with Hibern8 as gs101 does" needs the PHY's Hibern8
  hooks too.** gs101's PHY carries Google's `post_h8_enter`/`pre_h8_exit`
  tables, zumapro's doesn't. *Check:* `git grep cfgs_hibern8
  drivers/phy/samsung/` for the PHY the board binds, against the vendor's
  tables. Extends L-77 and L-113. *From:* kernel #99, round 24.
- **L-244. A hunk inserted right after a block comment leaves the comment
  describing the wrong code.** #104 and #119 did this; checkpatch doesn't
  see it. *Check:* for each hunk, a closing `*/` on the line above its first
  `+` line means it split a comment from its code. *From:* kernel #104,
  #119, round 24.
- **L-245. A ramoops node is checked against stock's sizes and the siblings',
  not only its address.** `record-size` puts a dmesg zone first and moves the
  console zone, while the bootloader writes its log at stock's offset.
  *Check:* stock's reserved-memory DT and `git grep -A4 '"ramoops"'
  arch/arm64/boot/dts/exynos/google`. *From:* kernel #106, round 24.
- **L-18. Check every commit for a human `Signed-off-by:`.** Three PRs at
  once came without one, while their bodies said "checkpatch clean": it was
  run on a diff, where the sign-off check can't fire. `tools/kernel-pr-check`
  checks it now. *From:* kernel #10, #11, #12.
- **L-19. Clock fixes belong in the clock driver's field description, not
  in a DT override.** `assigned-clock-parents` on a mux the driver describes
  at the wrong bit writes a reserved bit. *Check:* the mux's shift and width
  in `clk-gs101.c`/`clk-gs201.c` against Google's CMUCAL `cmucal-sfr.c`
  (`SFR_ACCESS(..._SELECT, shift, width, ...)`) for that SoC; CMU_APM is the
  ACPM firmware's own clock block, so prefer read-only there. *From:*
  kernel #6 (gs101 APM_FUNC: driver bit 4, Google bits [1:0]).
- **L-20. Kconfig `depends on` must cover every bus the driver registers
  on.** A driver that calls `spi_register_driver()` unconditionally with
  `depends on I2C` fails to link with `CONFIG_SPI=n`; our config has SPI on,
  so we'd never see it. *From:* kernel #8.
- **L-21. No wildcard compatibles** (`samsung,s6sy79x`): name the real part.
  *From:* kernel #8.
- **L-22. Power domains: follow the upstream series, and leave live
  co-processors alone.** A `google,gs101-pd` that differs from André
  Draszik's pending upstream series (domains as PMU children,
  `domain-supply`, the EL3 DTZPC call around every power change) will
  conflict; without the DTZPC call a domain powered back on comes up with
  its TrustZone settings reset. Powering off the AoC's domain while the AoC
  runs, with no handshake, belongs to the AoC series. *From:* kernel #9.
- **L-23. Thermal: the hardware trip is the last line of defence.** A driver
  that sends ACPM's TMU init must show the firmware's hardware thermal trip
  survives it; blocks with only a 110 °C critical trip need a reason.
  *From:* kernel #7.
- **L-24. Alive pin banks have no power-down configuration.**
  `samsung,pin-con-pdn`/`pin-pud-pdn` on an alive bank (gpa*) return -EINVAL,
  which `samsung_pinconf_group_set()` ignores, so the DT describes a sleep
  state that's never applied. *From:* kernel #12.
- **L-25. A regmap without a read table exposes the whole block through
  debugfs.** On gs201 one PMU read crashed the phone; a PMU regmap should
  list the offsets it uses (`rd_table`/`wr_table`). *From:* kernel #15.
- **L-26. A hall sensor reported as `SW_LID` makes logind treat a folded
  phone as a closed lid** (suspend by default). Fine in the kernel; the
  device's userspace must handle it. *From:* kernel #12.
- **L-27. gs101 and gs201 numbers differ.** Interrupts, sysreg offsets and
  EINT numbering (gs201 skips EINT19) must come from that SoC's stock DT or
  Google's tree for it, never from the other SoC. *Check:* compare against
  stock's node (USI6 on gs201: GIC SPI 679, `0x1014`). *From:* kernel #10
  (correct).
- **L-52. Regulator nodes use the stock board's voltage, min = max.** A full
  selector range lets any consumer set any voltage; min = max also means
  registering writes nothing when the rail is already there. *Check:* the
  stock board dtsi's `regulator-min/max-microvolt`. *From:* kernel #27.
- **L-53. Identical driver data calls for a binding fallback, not a driver
  match.** A new SoC whose block is the same as an older one's gets
  `items: [new, old]` in the binding and no driver change; upstream expects
  it, and stock zumapro itself uses the zuma compatibles. *From:* kernel
  #29, #30, #31.
- **L-54. Diff a new SoC's stock dtsi against the file it includes.** That
  is where its overrides hide (zumapro's `phy_eusb_version` 0x701 over
  zuma's 0x700). *From:* kernel #29.
- **L-55. When a driver hands chip select to the SPI core, its own transfer
  path must stop driving it.** Otherwise it re-asserts on every transfer and
  overrides the core's `cs_off`. *From:* kernel #21.
- **L-56. Google sometimes ships more than one driver for the same chip;
  check which one the board builds** (`BUILD.bazel` under
  `kernel/devices/google/<board>`). Cheetah's and tegu's S3908 drivers
  power the supplies in opposite orders. *From:* kernel #26.
- **L-57. On arm64 a divide-by-zero guard changes nothing observable.**
  UDIV by zero returns 0 without trapping; disassemble before and after
  before calling such a patch a behaviour change or a hidden bug. *From:*
  kernel #25.
- **L-58. Google's `soc/gs` tree is one tree for every Pixel, and CMUCAL's
  `OSCCLK_* = 26 MHz` is nominal.** G4 builds from zuma sources, so a zuma
  citation for a G4 block can be right; and work out a PLL table entry
  before accepting a 26 MHz input (the real oscillator is 24.576 MHz).
  *From:* kernel #19, #23.
- **L-68. Narrowing a regulator to min = max writes nothing if the rail is
  already there.** `of_regulator` sets `apply_uV` for any range, but the
  core only moves a rail that is out of range, so a test made with the wider
  range still stands. *Check:* the measured voltage is an exact selector
  (min + n × step, n < n_voltages). *From:* kernel #27, round 3.
- **L-72. A chip id the vendor driver checks belongs in the compatible's
  match data, not in a DT property.** Google keeps `st,dchip_id` because one
  `st,fts` compatible serves two parts (`36 40` SALIXP, `36 48` ALIX).
  *Check:* grep the vendor header for every value the property takes; name
  the part (L-21). *From:* kernel #32.
- **L-74. A Tensor PMU binding without `syscon` is a safety property.**
  With `syscon`, a consumer that probes before the PMU driver gets a plain
  MMIO regmap, where PMU writes are silently ignored (AGENTS.md section 1);
  without it, the lookup defers until the SMC-backed regmap exists. *Check:*
  new Tensor PMU bindings and board nodes leave `syscon` out, even though
  stock DTs have it. *From:* kernel #31, round 2 (for #22).
- **L-75. Map every property of a cited vendor block to its upstream
  equivalent.** Stock tegu's touch `controller-data` also has
  `cs-clock-delay = <2>`, a 2 µs CS-to-clock wait, which upstream spells
  `spi-cs-setup-delay-ns`. *Check:* read the whole block, not only the
  property the PR cites, and say why each one is or isn't needed. *From:*
  kernel #21, round 2.
