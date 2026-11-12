<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Shared code and the reference device (part 1 of 2)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-328. Moving a CPIF watcher from open-per-poll to a held fd changes the
  node's open count for the CP's lifetime; read open and release before
  calling it neutral.** On our CPIF, `bootdump_open` runs `init_comm` (which
  returns at once for SIT), `terminate_comm` is NULL, release purges the rx
  queue on cbd's close, and a holder that never reads takes none of cbd's
  frames, so #148 is neutral there by source. It still changes every phone's
  modem profile, so cheetah gets a maintainer run first. *Check:* the iod's
  open, release, poll and rx paths, and every reader of `iod->opened`. Extends
  L-206. *From:* #148, round 29.
- **L-327. A new `VENDOR_LIBS` entry in `extract-vendor-chroot` is unverified
  until the extractor has run on a real image.** Every entry's NEEDED closure
  is walked and any unresolved soname aborts the whole profile, so a GNSS-only
  addition could take a phone's modem chroot down with it; #141's libraries
  were copied by hand. *Check:* ask for one extractor run (its `==>` lines and
  the new MANIFEST paths), or run it on a factory image we have; binder
  clients often need `STUB_LIBS`. Extends L-29. *From:* #141, round 29.
- **L-326. A "read-only, no-op on cheetah" `clk_get_rate()` on an ACPM clock
  is a firmware call.** clk-acpm registers the gs201 and zumapro clocks with
  `CLK_GET_RATE_NOCACHE` (gs101's aren't: corrected 2026-11-03, C-27), so
  kernel #116's MIF restore adds one ACPM DVFS GET on cheetah at every drop
  from 120 Hz, though it never writes there (MIF is already at its top
  rate). *Check:* before calling a new `clk_get_rate()` on a shared path
  free, read the provider's `flags` and `recalc_rate`, and put the call
  count in the cheetah table. Extends L-111. *From:* kernel #116, round 29.
- **L-325. "Shares the register map" isn't "shares the device type": a PMIC
  change gated on `device_type` is checked against the reference phone's MFD
  data, not its registers.** rtc-s5m gives the S2MPG12 the S2MPG10's
  `s2mpg10_rtc_regs`, but sec-acpm's `s2mpg12_data` keeps `device_type =
  S2MPG12`, so kernel #132's `== S2MPG10` steps skip cheetah although the
  registers are the same; a condition on the regs pointer would have reached
  it. *Check:* for each new condition in a shared PMIC driver, read what it
  tests (type, regs, compatible), find cheetah's value in the MFD match data
  and probe, and confirm with the compare's immediate in the object. Extends
  L-206 and L-230. *From:* kernel #132, round 29.
- **L-301. A shared-driver branch gated on what callers send counts as match
  data under CONTRIBUTING §6.2 only if no reference-phone consumer sends it,
  on the base and on `omamobile-int`.** Kernel #125's DCS-read path runs only
  when a panel asks for a read, but inlining still changes the hot function's
  machine code. *Check:* `git grep` the consumer drivers for the new API's
  callers on `github/omamobile` and `omamobile-int`, and prefer a boot when
  one is already planned. Extends L-206 and L-228. *From:* kernel #125, round
  28.
- **L-300. A touch-scaling change is cheetah-neutral only when the axis
  maximum plus one equals the panel size.** On #135 the synaptics probe line
  (`…, 1440x3120, 10 objects`) and no `touchscreen-size-*` in the board DT
  showed that `scale()` is the identity on cheetah. *Check:* grep `logs/` for
  the probe's `app fw` line and `git grep touchscreen-size` in the DTS before
  calling such a change neutral. *From:* #135, round 28.
- **L-299. A per-device constant given "as before" in a shared runner is
  checked against that device's notes, not the line it replaced.** #135's
  "cheetah 60 Hz, as before" repeated the old `op_hz`, but NOTES 2026-10-12
  and DEVICES.md say cheetah runs at 120 Hz by default. *Check:* `grep -n` the
  value in `device/<codename>/NOTES.md`, the subsystem plan's status line and
  DEVICES.md. Extends L-280. *From:* #135, round 28.
- **L-282. An env-default variable in a shared build library is an input to
  the maintainer's builds too.** #79's `ALARM_LOCAL_KEY=${ALARM_LOCAL_KEY:-}`
  in `tools/lib/alarm.sh` lets a leftover export widen trust in a build
  without `--local`. *Check:* for each new `VAR=${VAR:-}` in `tools/lib/`,
  confirm the maintainer's path sets or clears it explicitly. Extends L-7 and
  L-171. *From:* #79, round 26.
- **L-280. A per-device flag that gates new behaviour in a shared runner is
  checked by building the command line under both values.** #101's
  `MAP_STORES` adds storageproxyd arguments through an array, and an empty
  `"${maps[@]}"` must vanish under `set -u`; a grep test can't show that. Run
  with both images present, cheetah got the same 9 arguments as main and tegu
  15. *Check:* extract the argument-building block and run it under `set -euo
  pipefail` with each flag value and the triggering files present. Extends L-8
  and L-234. *From:* #101, round 26.
- **L-273. A before-merge Pixel 7 Pro run on `omamobile-int` compares the
  touched file on int with the base first.** Where they differ, the run covers
  the PR's hunk inside int's code, and the runbook and merge comment say
  "tested on int + the commit"; where the cherry-pick conflicts, show that the
  untestable commit is neutral on gs201. Kernel #82's `synaptics_tcm.c` and
  #71's `net/nfc/core.c` differ between int and the base, and #88's gs-decon
  commit doesn't apply to int. *Check:* `git rev-parse omamobile-int:<f>
  github/omamobile:<f>`, then `git merge-tree --merge-base <c>^ omamobile-int
  <c>`. Extends L-206 and L-45. *From:* kernel #82, #71, #88, round 25.
- **L-268. A package that installs a hand-built prebuilt publishes a stale
  binary when only its source changes.** fingerprint 0.1.9 changed the
  bridge's C source, but the package installs `prebuilt/omamobile-fp-bridge`
  as it finds it; gnss 0.2.4 builds without the 9a client and says so only in
  the log. *Check:* for a package PR that touches a prebuilt's source, ask
  whether the build machine rebuilt the prebuilt, and prefer a test that
  compares the prebuilt's build ID or date with its source. Extends L-259.
  *From:* issue #109, round 25.
- **L-228. A board DT property that only the contributor's board sets counts
  as its match data under CONTRIBUTING §6.2.** It holds when no base DTS,
  cheetah overlay in `DTB_OVERLAYS` or open PR sets it, and the object diff
  shows every new instruction behind the field it fills; for board wiring
  (#94's REG_ON flip-flop) it's stricter than the compatible. *Check:* `git
  grep '<property>'` on the base's `arch/` and `device/*/overlays/`, then the
  per-function object diff. Extends L-206 and L-49. *From:* kernel #94, #95,
  round 23; confirmed by the maintainer.
- **L-229. An alternative we offer in a draft is held to CONTRIBUTING like
  the main request.** Round 22 offered kernel #88 "or keep the shared lookup
  and I'll run it on my phone"; §6.2 lets a Pixel 7 Pro run stand in only for
  a deliberate cheetah change with a cheetah reason, and the contributor took
  the offer. *Check:* every "or, if you prefer, …" against §6.2 before
  posting; if the rule doesn't cover the case, fix the rule first. Extends
  L-31. *From:* kernel #88, round 23; confirmed by the maintainer.
- **L-230. Inserting into the middle of a shared struct or enum changes
  cheetah's objects outside the touched function.** #62's hook in `struct
  exynos_pmu_data` shifted later fields by 8 bytes; #101's new
  `sec_device_type` renumbered every later type. *Check:* read each flagged
  function's changed instructions (offset-only loads; compares only against
  values after the insertion), confirm the reference phone's values sit
  before it, and compare data symbols' bytes and relocations base vs head.
  Extends L-110, L-111 and L-153. *From:* kernel #62, round 23; kernel #101,
  round 24.
- **L-231. A registration that opts out is not a no-op when the core's
  default is "needed unless everyone opts out".** gs-decon's
  `pm_vt_switch_required(dev, false)` turns the suspend VT switch off on
  cheetah, because the PM core switches only while its list is empty or one
  entry requires it. *Check:* for a new opt-out registration in a shared
  driver, read the core's aggregate rule and list what else registers on the
  reference phone. Extends L-206. *From:* kernel #116, round 24.
- **L-232. Before calling a forked guard's behaviour a defect, diff it
  against the shared original.** dodge's watcher skips disks with a
  `/run/ufs-ro` marker, which looked like a gap; `initramfs/init` does the
  same by design. *Check:* `diff` the fork's function against
  `initramfs/init` before naming a gap. Extends L-134 and C-1. *From:* #111,
  round 24 (a near miss).
- **L-233. A device package's workaround for an Omarchy service is checked
  against Omarchy's package list before it stays device-local.** #74
  disables `linux-modules-cleanup` for tegu, but the service comes from
  `omarchy-base.packages` and is enabled by Omarchy's installer, so it likely
  runs on every phone. *Check:* grep the unit's package in
  `/usr/share/omarchy/install/omarchy-base.packages`, `enable-services.sh` and
  `rootfs/packages.omarchy-skip`, then ask for one read on cheetah. Extends
  L-11 and L-32. *From:* #74, round 24.
- **L-234. A shared script that branches on `/proc/device-tree` makes its
  package test host-dependent.** #117's test passes on CI and the laptop,
  fails in `makepkg check` on the Pixel 9a it's for, and never runs that
  branch. *Check:* every new DT read in a package script has an override the
  test uses, and the test runs each branch. *From:* #117, round 24.
- **L-8. "Nothing changes for cheetah" is checked by building it.** For any
  change to `bin/omamobile`, `initramfs/`, `rootfs/`, `tools/` or a shared
  package: build cheetah's images with main's tool and the PR's, in separate
  scratch output directories, and compare sha256s. *From:* #27 (all six
  images and every DTB identical).
- **L-9. A test whose baseline is `origin/main` stops testing once it
  merges.** Pin the baseline (a commit, or recorded checksums). *From:* #27.
- **L-10. Parsers of decompiled DTBs must allow labels.** Our DTBs are built
  with `-@`, so dtc restores labels (`x: node {`) from `__symbols__`; a
  regex for `^\t\tNAME {` misses a labelled child and passes a DTB with an
  extra one. *Check:* feed the parser a labelled node and an extra child.
  *From:* #27.
- **L-11. Shared root-image changes need their own commit and a Pixel
  rationale.** Masking `systemd-firstboot`, a coredump drop-in, a
  `clock-epoch` file or `Wants=time-set.target` in `rootfs/build-inside`
  changes every device's image. (systemd.special(7): order after
  `time-set.target`, never pull it in.) *From:* #25.
- **L-12. Package versions can collide with main.** A PR bumping a package
  to a version main already shipped (with different contents), plus a
  dependency `>=` that version, installs without the PR's change. *Check:*
  `git show origin/main:packages/<p>/version` against the PR's. *From:* #17.
- **L-13. Device-specific tool stages must refuse other devices.** A raven-only
  AoC stage (`cycle`, `tzpc`, `pd`, `s2mpu`) accepted on cheetah power-cycles
  the reference phone's AoC; a stage the PR's own notes say aborts the SoC
  unless another ran first must enforce that order (a per-boot marker).
  *From:* #22.

- **L-32. Know what Omarchy already sets before claiming a userspace
  default.** `omarchy-settings` ships `/etc/systemd/logind.conf.d` drop-ins
  (`HandlePowerKey=ignore`), and Omarchy's Hyprland config binds the
  `switch:` named "Lid Switch" to its clamshell logic. *Check:* `pacman -Ql
  omarchy omarchy-settings | grep -E 'logind|lid'`, and on the phone
  `busctl get-property org.freedesktop.login1 /org/freedesktop/login1
  org.freedesktop.login1.Manager Handle…`. *From:* #29.
- **L-37. A kernel change that needs a userspace companion merges after
  it.** A new `SW_LID`, wakeup source, or any node whose default userspace
  policy is harmful (logind suspending a folded phone) waits for the
  omarchy-mobile change that handles it, so no build ever has one without
  the other. *From:* kernel #12 with #29.

- **L-49. "Disabled" means disabled in the DTB the phone runs: the DTS plus
  its `DTB_OVERLAYS`.** Cheetah's DTS has `pmic-1` disabled, but its
  `suspend-pmic-test` overlay enables it, so a new S2MPG12 cell binds on
  the reference phone. *Check:* grep the device's `DTB_OVERLAYS` for every
  node a PR's code binds to. *From:* kernel #27 (correction C-2).
- **L-50. A new MFD cell binds wherever an overlay enables its parent;
  for cheetah, ask for a read-only boot first.** Code reading said the
  S2MPG12 regulator driver only reads; one boot with `regulator_summary`,
  dmesg and `tools/phone-smoke` proves it. *From:* kernel #27.
- **L-51. Error-propagation fixes in shared drivers change the reference
  phone's failure modes.** A UFS PHY error ignored before became fatal at
  boot, reset and resume. *Check:* list which callbacks can now fail, grep
  cheetah's logs for those errors, and boot it once. *From:* kernel #19,
  #22.
- **L-67. A rail a PR touches on another phone may feed something on
  cheetah.** felix's cover-touch LDO25M/LDO26M are cheetah's main touch
  rails (and LDO27M/LDO28M its display rails). *Check:* look the rail up in
  NOTES and the plans, and name those peripherals in the read-only cheetah
  boot's Expect line. *From:* kernel #27, round 3.
- **L-87. A new installer refusal fed by bootloader variables is checked
  against the reference phone's real `getvar all` capture,** line endings
  included, before it can refuse cheetah. *From:* #27, round 3 (cheetah's ABL
  lists `partition-size` for all five `_b` partitions, so the refusal holds).
- **L-110. A shared-driver change confined to one static function is
  proven cheetah-neutral by comparing the object function by function.**
  Build the `.o` at base and head with the same config and diff the
  disassembly per function: for #42 only `exynos2200_usbdrd_phy_exit`
  changed. Extends L-8. *From:* kernel #42.
- **L-111. When a shared driver moves constants into per-SoC match data,
  prove "unchanged on cheetah" with a table and a boot, not an object diff.**
  Loads through `dc->soc` change the object anyway. *Check:* each new field's
  gs201 value next to the constant it replaced, each new branch's gs201
  condition, then one boot with before/after reads of the driver's own
  counters. *From:* kernel #46.
- **L-112. A core change that makes a reserved value valid updates the
  binding that reserved it, and names the boards that change.** reboot-mode
  has skipped a zero magic since 2016 and its binding says "non-zero".
  *Check:* `git log -S` on the binding for the rule's origin, `git grep` for
  the value across all DTs (`da850-lego-ev3`'s zero `mode-normal`, written `<0x00000000>`), and both
  in the commit message. *From:* kernel #45.
- **L-136. A probe's default pin or register is a per-board fact.**
  `bt-uart-test --wake` defaulted to cheetah's gpp16:3 on every phone; on
  gs101 that is a USI8 pin. *Check:* a tool that drives a GPIO or register
  on the phone takes its default from the board's compatible, or refuses an
  unknown board without an explicit value. Extends L-13. *From:* #22,
  round 12.
- **L-137. A device package's wants links can override another package's
  "installed, not enabled" policy.** raven's package enabled the modem and
  SIM units at boot. *Check:* for each `vendor/systemd/**/*.wants/*` link,
  find the package that owns the unit and read its install message and unit
  comments; turning a radio on by default is the maintainer's call. *From:*
  #41, round 12.
- **L-160. Hiding a shell surface removes every gesture on it, and a new
  edge surface is checked against the keyboard and fullscreen windows.** #43
  hid the dock over apps, its swipe-up the switcher's only entry point; its
  new full-width pill sat on the Overlay layer with no input mask. *Check:*
  `git grep` the surface's handlers; for a new layer surface, its layer,
  input region, the keyboard's layer and fullscreen apps. *From:* #43,
  round 14.
- **L-161. A lock-path check that fails open is a finding.** `jq -e
  'all(.dpmsStatus)'` read a failed `hyprctl` query as "screen off", so Power
  would stop locking. Test for the positive state, failing towards locking.
  *From:* #43, round 14.
- **L-162. A per-board audio file is only as safe as the shared fallback,
  and node-name filters apply to every board with that name.** If tegu's card
  name changed, alsa-ucm-conf would fall back to cheetah's profile, whose mic
  list takes tegu's AoC down; cheetah's loudness filter matches any sink named
  `sound-aoc`. "Stage ceilings" are cheetah's CS35L41 bound: a new amplifier
  needs its own. *From:* #44, round 14.
- **L-172. An NFC core change is a cheetah change: the Pixel 7 Pro polls
  through neard at boot.** `omamobile-nfc-open` is enabled by
  `omamobile-setup-system` and starts a poll loop, so every `net/nfc`
  behaviour tied to polling (rfkill block, poll ownership, proprietary
  notifications) runs on the reference phone at every boot; the NFC tile's
  "Off" had been a no-op there too. *Check:* `git grep -n nfc-open
  packages/omamobile-device-cheetah` before saying "cheetah unaffected" for
  an NFC change. Extends L-51. *From:* kernel #71 with #78, round 20.
- **L-173. A shared `initramfs/init` change is cheetah-neutral by its
  gates, not by a byte comparison.** The init text changes for every device,
  so the packed image differs by construction. *Check:* list each new path's
  marker file, show that `bin/omamobile initramfs-config` packs none of them
  for cheetah and felix (byte-identical `etc`), read each path's early
  return, and let the next routine cheetah push be the boot. Extends L-8 and
  L-134. *From:* #41, round 20.
- **L-206. Shared drivers leave the Pixel 7 Pro unchanged by construction
  (CONTRIBUTING §6.2).** New behaviour sits behind the contributor's own match
  data; a deliberate cheetah change needs a reason that holds on cheetah and a
  run on the maintainer's phone before merge. Where a flag is tested inside a
  shared function (#57's `UNGATE_POST_CHANGE` in `exynos_ufs_setup_clocks()`),
  the object can't be byte-identical: accept a per-function object diff plus a
  flag table showing cheetah's path unchanged (L-111). Per-SoC data also
  reaches every board that binds it through a fallback compatible (#83's
  `zumapro_ufs_drvs` is zuma's too). *Check:* cheetah's objects before and
  after, function by function where they differ; `git grep '"<compatible>"'
  arch/` for every board listing the data's compatible, fallbacks included,
  and those boards' plans for statements the change falsifies. Extends L-151.
  *From:* kernel #57, #82, #83, #88, round 22.
