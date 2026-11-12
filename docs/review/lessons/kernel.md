<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Kernel (linux-omarchy-mobile) (part 1 of 2)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
- **L-77. A vendor CAL's version switch is narrower than the function it
  sits in.** Google's eUSB2 init gates only the charge-pump bias clear on
  the revision; the rest runs for every version, so "0x701's sequence"
  overstated it. *Check:* list which writes are actually inside the version
  test before accepting a per-revision claim. *From:* kernel #33.
- **L-78. Balancing a shared PHY child's init count turns a once-per-boot
  init into one that runs every cycle.** *Check:* list every board that
  binds the wrapper, open DT PRs included, and ask for one boot with an
  unbind/bind on one of them (L-51). *From:* kernel #33 (Pixel 8 Pro).
- **L-79. Check linux-next for the same function before accepting a fix to
  a shared driver.** It showed #33's coming conflict, and an upstream change
  to cheetah's PIPE3 path that our next base move will bring (an L-51
  event). *From:* kernel #33.
- **L-83. A `Fixes:` id that CI calls `UNKNOWN_COMMIT_ID` may still be
  right.** CI's clone holds only our squashed base; a clone with the upstream
  remote resolves it. *Check:* `git log -1 <id>` there (or git.kernel.org),
  and confirm it introduced the code being fixed (extends L-30). *From:*
  kernel #33, round 2.
- **L-84. For a rebased series, compare the preimages as well as the
  results.** Identical blobs at both heads *and* both bases mean earlier
  object comparisons (L-8) still hold without a rebuild; matching results on
  a moved base mean they must be redone (extends L-69). *From:* kernel #33,
  round 2.
- **L-92. On Exynos CMUs the gate enable bit (CG_VAL, bit 21) means "on"
  only in manual mode.** MANUAL is bit 20, auto-gating bit 28, and the CMU's
  controller option has a global auto bit. *Check:* a read-only gate follows
  the mode, as Google's `ra_get_gate()` does, or the PR shows the handoff
  values; a vendor `HWACG_VCLK`/`_QCH` clock is a hint it's automatic.
  *From:* kernel #34 (a wrong read would leave the watchdogs unowned).
- **L-93. The unused-regulator cleanup acts only on regulators the DT
  describes without `regulator-always-on`.** Undescribed outputs are never
  switched off; a described one with no consumer is, about 30 s in.
  *Check:* "keeps it out of the cleanup" claims against `of_regulator.c` and
  `regulator_late_cleanup()`; inherited rails a board describes carry
  always-on until a consumer owns them. Extends C-1. *From:* kernel #35.
- **L-94. Find a vendor rail's consumer in the board dtsi's `&node {
  …-supply }` overrides, not from its schematic name.** G4's `L8M_USB` rails
  belong to Google's HSI0 power-domain helper, not the PHY. *From:* kernel
  #35.
- **L-95. A regulator node without voltage limits can't change state.** So
  "no other rail changed" on a new PMIC regulator driver comes down to which
  DT nodes have constraints. *From:* kernel #32, round 5.
- **L-96. A binding describes the hardware, not Linux's power policy.** No
  `power-domains: false` for a block stock gives a domain; match the sibling
  SoC's rule and put "no domain because firmware leaves it on" as a comment
  on the board node. *From:* kernel #40.
- **L-97. dtschema's core schema rejects a string property named
  `description`.** *Check:* when a binding types a vendor node, validate the
  vendor's exact node against the base's schemas and the head's, and ask
  whether the firmware needs what the schema makes the board drop. *From:*
  kernel #37, kernel #13.
- **L-98. A binding that requires a clock is usable only once the clock
  provider exports it.** *Check:* grep the SoC's clock header and the open
  clock PRs; name the missing provider as the next step. *From:* kernel #39.
- **L-99. Read the vendor driver's read path, not only its register map.**
  Google reports a fixed 22 °C on MAX77779 gauge firmware below 1.15, so the
  Temp register isn't trusted there. *From:* kernel #38.
- **L-100. Check a per-board scale value in three public places:** the board
  node or the vendor default, the battery model's name, and a design value
  it implies (`nDesignCap` × LSB = the rated mAh). *From:* kernel #38 (the
  2 mΩ shunt).
- **L-101. A Kconfig `default` tied to another symbol doesn't follow it
  under fragment merging,** because defconfig has already written "is not
  set". *Check:* the merged `.config`, made the way `bin/omamobile kernel`
  makes it. *From:* #23 (`DETECT_HUNG_TASK`).
- **L-113. Before accepting "Google's driver for <SoC> does X", find the
  driver that SoC's defconfig builds.** soc/gs has two USB PHY drivers
  matching `samsung,exynos-usbdrd-phy`; #42 cited `phy-exynos-usb3p1.c`, but
  zuma builds `CONFIG_PHY_EXYNOS_USBDRD_EUSB`, and the cited function only
  acts on USBCON v3.0 (zuma is 0x600). *Check:* the defconfig and module
  list, the module's files in `Kbuild`, then any version test in the cited
  function against the stock DT. Extends L-56 and L-77. *From:* kernel #42.
- **L-114. Reserve a stock address only if Google's dtsi gives the region
  a `reg`.** A `size` + `alloc-ranges` pool (`tui`, `mfc_fw`, `famodel`) has
  an address only because stock allocated it there on that boot. *From:*
  kernel #43.
- **L-115. When a PHY driver picks its settings from `clk_get_rate()`, the
  board's nominal fixed clocks become PHY configuration.**
  `phy-snps-eusb2.c` takes FSEL and the PLL divider from an exact-rate table,
  so a CAL nominal rate or a mux reading the other way decides whether the
  PHY initialises. *Check:* trace the clock to its root and ask for the mux
  selections and the `clk_summary` rate at handoff. Extends L-58. *From:*
  kernel #40.
- **L-116. A fix in a PHY's exit path also covers resume.** dwc3 calls
  `phy_exit()` on device-mode suspend and touches the core in
  `dwc3_phy_setup()` before `phy_init()`. *Check:* list the consumer's
  `phy_exit` callers and the first register access after each, and name the
  untested paths in the review. *From:* #23 tests 24-29, kernel #42.
- **L-117. A comment that says "all variants" is checked against every
  variant's vendor driver.** tegu ships three panels (`panel-gs-tg4a/b/c`);
  TG4A's porches and size differ. *Check:* the device's `BUILD.bazel` for the
  list, then each file. Extends L-56. *From:* kernel #46.
- **L-118. On Tensor, SYSIP_DAT0 0x00 means "normal" in Google's reboot
  driver** (`pixel-gs201-reboot.c`, `pixel-zuma-reboot.c` in
  kernel/google-modules/power/reset). Check reboot-mode claims against that
  file, not a contributor's harness. *From:* kernel #45.
- **L-119. A blank line before `Signed-off-by:` takes `Link:` out of the
  trailer block.** checkpatch doesn't flag it. *Check:* `git log -1
  --format=%B <c> | git interpret-trailers --parse` lists every intended
  trailer. *From:* kernel #35, round 10.
- **L-138. "Stop where stock repairs" covers every error poll on stock's
  path to the write decision.** FTM5's `fts_crc_check` polls config CRC
  events 0x20/0x21 and `fts_fw_update` reflashes on them; kernel #48 read
  and logged them, then scanned. *Check:* trace stock from probe to each
  write decision and list every event or status that leads to a repair; the
  driver must fail on each. Extends L-129 and L-108. *From:* kernel #48,
  round 12.
- **L-139. A PR that moves a compatible into its own binding is merged with
  every open PR that uses it as a fallback, and the schemas rebuilt.** #9
  moved `google,gs101-pmu` out of exynos-pmu.yaml while #47 added
  `[gs201-pmu, gs101-pmu]` there: both merged as text, and dt-validate failed
  on all four Google boards (`Duplicate compatible` from `dt-mk-schema`).
  *Check:* `git grep` open PR heads for the moved compatible, test-merge,
  `dt-mk-schema` and `dt-validate`. Extends L-126. *From:* kernel #9 with
  #47, round 12.
- **L-140. Compare an imported series against patchwork's mboxes when lore
  is blocked.** `https://patchwork.kernel.org/api/1.3/patches/?q=<term>`
  lists the message ids and `/project/<list>/patch/<msgid>/mbox/` gives each
  patch; compare each commit's lines per file, and where only hunks differ,
  apply to the base and compare the file. Extends L-62. *From:* kernel #9,
  round 12.
- **L-141. A gs101 power domain turned off without its DTZPC save needs the
  save before anything powers it back on.** André's driver skips the EL3
  save and restore for a `google,gs101-pd` without `samsung,dtzpc`, so the
  first consumer finds the block's TrustZone settings reset, and its
  registers SError. *Check:* a new `power-domains = <&pd_…>` on gs101 comes
  with `samsung,dtzpc` and the block's CMU in the same series. *From:*
  kernel #9, round 12.
- **L-142. An enable commit before the fix for a known-bad first version is
  a bisect hazard.** #7's raven enable commit came before the tuning that
  stopped boot-time thermal power-offs (3 of 4 boots). *Check:* when a body
  says "the first version did X on the phone", find that commit and ask for
  the board enable to land last. Extends L-123. *From:* kernel #7,
  round 12.
- **L-143. A Kconfig guard is checked by building with the guarded symbol
  off.** `kernel-pr-check` builds with our config (SPI on), and a
  single-object build compiles even a driver whose symbol is off. *Check:*
  `scripts/config -d SPI`, build the object, and `llvm-nm | grep -i spi` is
  empty. Extends L-20. *From:* kernel #8, round 12.
