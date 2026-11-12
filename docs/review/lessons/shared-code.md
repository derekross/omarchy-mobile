<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Shared code and the reference device (part 1 of 2)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-760. A new `syscon`-only node in a shared SoC dtsi is neutral on sibling
  boards, because a syscon regmap is made on first lookup, not at boot; say
  that rather than asking for `disabled`.** L-465's request is for nodes that
  bind a driver and touch registers at probe; kernel #243's
  `google,zuma-vgpio2ap-sysreg` binds none. *Check:* the compatible list ends
  in `syscon` and `git grep '"<compatible>"' drivers/` is empty, nothing on
  the sibling references the label, and `clk-<soc>.c` has no gate for the
  block. Narrows L-465. *From:* kernel #243, round 52, 2026-11-11.
- **L-759. When the image's package list follows upstream's, every package a
  new upstream version adds is read for its licence and against our held
  migrations.** Omarchy 4.5's composed list adds `superwhisper-bin`
  (`LicenseRef-proprietary`), and `owe` and Fcitx add-ons whose migrations we
  hold on updated phones, so a fresh image would differ from an updated phone.
  *Check:* compose both versions' lists with `omarchy_packages`, `comm` them,
  `pacman -Si` each addition for `Licenses`, and grep `omarchy-migrate`'s hold
  list; additions go to `rootfs/packages.omarchy-skip` or get a line saying
  why not. Extends L-233 and L-584. *From:* #665 with #670 (commit review),
  round 52, 2026-11-11.
- **L-758. A fix for a base-system requirement that a new upstream version
  enforces is checked for what delivers it to each phone before the pin
  moves.** #437 fixed `/run`'s mode in the initramfs, which reaches a phone
  only with new boot images and a reboot, and only the 7 Pro's device package
  carries boot files; #670 then moved every phone to Omarchy 4.5, whose sudo
  migration exits 1 on `/run` 1777 (issue #447). *Check:* for each such
  requirement, name what delivers the fix to a release-installed phone and to
  each device without packaged boot files; prefer a fix inside the transaction
  (tmpfiles.d, the update's preflight). Extends L-500, L-442 and L-415.
  *From:* #670 with #437 and #673 (commit review), round 52, 2026-11-11.
- **L-732. A table keyed on the bootloader's scanout size is checked for a second board of that size on the same SoC, open PRs included.** Kernel #181 picks gs201's modes by 1080x2400, which is also the Pixel 7a's size (kernel #202). *Check:* list the panel sizes of every board on the SoC, merged and open, before accepting size as a key. Extends L-464 and L-104. *From:* kernel #181 with kernel #202, round 51, 2026-11-11.
- **L-731. An opt-in shell feature is checked for the surfaces it maps with the option off.** #612's setting gates the dock tap, but its two full-screen Top-layer windows are `visible: true` on every phone. *Check:* grep the diff for `PanelWindow` and read each `visible:`; with the option off, `hyprctl layers` matches main's. Extends L-608 and L-491. *From:* #612, round 51, 2026-11-11.
- **L-730. An unchanged open PR is re-read each round against what the base gained under it: new compatibles in its driver's match table, and merged code that touches its open points.** Kernel #232's sleep callbacks bound one SoC until the base gave `pcie-gs201-cp` the Pixel 9a's compatible; #556's "screen state runs on every phone" was a caution until main got the 9a's own start-up "screen on" and a modem unit that can start at boot. Neither diff had changed. *Check:* `git log <old base>..<base> -- <each touched file>`, `git grep -n compatible <base>:<file>`, and grep main for what each open point names. Extends L-423, L-206 and L-608. *From:* kernel #232, #556, round 51, 2026-11-11.
- **L-705. A switch named after one feature that flips a shared daemon's
  profile is read for what else the profile governs.** #629's "keyboard
  haptics: off" set feedbackd's `silent` profile, which drops sound and
  vibration for every event, and omatel rings calls through feedbackd.
  *Check:* `git grep -n feedbackd origin/main -- 'packages/*/PKGBUILD'
  packages/omamobile-shell`, and the app repositories, for the other consumers
  before accepting a profile change. Extends L-462. *From:* #629, round 50.
- **L-704. A new file directly under `device/<codename>/` is checked against
  the names the build tools read by convention.** #565 added
  `device/bluejay/kernel.config` as the record of one build; `bin/omamobile
  kernel` merges that file into every non-release build, so its fixed
  `CONFIG_LOCALVERSION` would have named every Bluejay kernel after the tested
  one, defeating the helpers' `uname -r` pin. *Check:* `git grep -n
  'device/\$DEVICE/' bin tools` for the file's name, and grep any fragment for
  `LOCALVERSION`. Extends L-149 and L-337. *From:* #565, round 50.
- **L-703. A once-only step keyed on a default value reaches every device that
  still has the default, and "unchanged on the 7 Pro" covers the result, not
  the mechanism.** #635's step matches scale `= 3` or `"auto"`, so the 8 Pro
  would rescale at its next login; on the 7 Pro the scale stays 3 (71x155 mm,
  also at ±2 mm) but the session gains a rewritten user file and a module run
  at every reload. *Check:* a table of DEVICES.md's devices with each one's
  input and result, and a list of the side effects that don't depend on the
  result. Extends L-608 and L-299. *From:* #635, round 50.
- **L-702. A status key rewritten for one phone's new capability is evaluated
  with the other phones' object.** #626 changed `speaker` from "is the tegu
  route" to `output == 'speaker'`, and `output` defaults to `speaker`
  everywhere, so a 7 Pro earpiece call would report the loudspeaker; the test
  used `MagicMock(tegu=True, …)` throughout. *Check:* build the reference
  phone's object (`VoiceAudio.__new__` with `tegu = False`), diff `status()`
  at base and head, and `git grep` the key's readers. Extends L-206 and L-608.
  *From:* #626, round 50.
- **L-701. Two starters that read one signal are compared for what each
  clears.** #403's 7 Pro branch removes the counted `.refused-*` copies when
  it finds the reboot note; the 9a's `omamobile-tegu-modem-up` (#372) removes
  only the latch and the note, so a hang, a push and a second hang starts the
  modem on one phone and holds it on the other. *Check:* `git grep` the
  signal's path (`/var/lib/omamobile/deliberate-restart`) across `packages/`
  and lay each reader's `rm` line side by side. Extends L-492 and L-444.
  *From:* #403 with #372, round 50.
- **L-669. A build-time switch that changes what an initramfs boots is checked
  at the next consumer of the cached file.** #503's `OMAMOBILE_NFSROOT` is
  validated in `cmd_initramfs`, but `images`, `flash` and `push` read
  `initramfs.cpio.lz4` from `KERNEL_OUT` without knowing how it was built.
  *Check:* for each new build input, name the cached artifact it lands in and
  every command that reads it later, and ask for a visible line or a refusal
  there. Extends L-282. *From:* #503, round 49, 2026-11-10.
- **L-668. A fix that lets a new kind of input through the installer is
  followed to the first boot.** #609 lets a lived-in root pass
  `tools/install-phone`'s image check; the installer still writes
  `firstboot.conf` into it, and firstboot's answer to an existing user is to
  refuse and keep the file. *Check:* for each input an installer newly
  accepts, name what each first-boot unit does with it
  (`omamobile-firstboot`'s `validate`, the fingerprint runner's TD) and ask
  for that boot's log. Extends L-451. *From:* #609, round 49, 2026-11-10.
- **L-667. A new app is checked against the plan row for the app it
  duplicates.** #611 added a Files app without mentioning that
  `docs/TELEPHONY-APPS-PLAN.md` records "Files: reuse Nautilus", which sits in
  Home's dock and serves the portal chooser. *Check:* `git grep -n -i "<the
  app's role>" docs/*PLAN.md
  packages/omamobile-shell/plugins/omamobile.home/HomeModel.js`, and the
  `.desktop` `Name=` of what's installed; a duplicate name or a contradicted
  plan row is the maintainer's decision before any code review. *From:* #611,
  round 49, 2026-11-10.
- **L-666. `~/.local/share/omarchy` is Omarchy's legacy root, not a free data
  directory.** #610 put a browser profile (a login) under it;
  `omarchy-upgrade-to-quattro` moves that directory to a `.bak` and replaces
  it with a link to `/usr/share/omarchy`, and `omarchy-nvim-setup` reads it as
  `OMARCHY_PATH`. *Check:* grep a PR's added lines for `share/omarchy`,
  `config/omarchy` and `state/omarchy` paths it creates, then the signed
  Omarchy package's `usr/bin` for the same path (`mv`, `rm`, `ln -sfn`, `-d`
  tests); our own data goes under `omamobile/`. Extends L-32, L-227 and L-498.
  *From:* #610, round 49, 2026-11-10.
- **L-665. A shared-driver change accepted "by reading" in an early round is
  re-checked against CONTRIBUTING §6.2 at the merge round, and "rare" is
  traced to every caller.** Kernel #116's MIF restore passed round 29 as "one
  ACPM read" when leaving 120 Hz; `gs_decon_crtc_atomic_disable` drops to 60
  Hz first, so on the 7 Pro it runs at every screen-off, and it has never run
  there. *Check:* list each ungated hunk on a reference-phone path, the
  callers of its function and the user events that reach them, `git grep` the
  clone's branches for its symbol, then run it or record the waiver. Extends
  L-229, L-326 and L-342. *From:* kernel #116, round 49, 2026-11-10.
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
