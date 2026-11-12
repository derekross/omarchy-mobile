<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Shared code and the reference device (part 2 of 2)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-207. A gs101/gs201 device package carries the s2idle drop-in.** Cheetah
  and raven ship `sleep.conf.d/10-omamobile.conf`; felix and lynx don't, so
  Omarchy's Suspend enters `deep`, which never wakes on gs201. *Check:* `git
  ls-tree -r origin/main packages/ | grep sleep.conf` for every such device
  package, and `mem_sleep_default` in the board's bootargs. *From:* #88,
  round 22.

- **L-348. A shared driver's change is judged against every user of it on
  `omamobile-int`, not only on `omamobile`.** Kernel #150 (spi-s3c64xx) has
  one SPI user on the published base (touch) but three on the integration
  line the 7 Pro runs (touch, both CS35L41 amplifiers, the BCM4775 GNSS).
  *Check:* list the bus's consumers in the int tree's DT before writing the
  7 Pro test, and exercise each one. *From:* kernel #150, 2026-10-31.
- **L-349. A board pin group is checked against every stock user of those
  pins.** Kernel #151 gave SPI21 the gpp22 pins, which Google's tegu tree uses
  as SPI15 for the eSE. *Check:* grep the pin bank and number across Google's
  device repository for the board (not only the SoC's), and confirm the
  controller's USI block and the pin bank's block agree. *From:* kernel #151,
  2026-10-31.
- **L-413. "Booted" or "known good" is a fact about the partitions since this boot, not a tool's record, and a guard that reads a tool's own state is walked through every other writer.** #320 first read `current/RELEASE`, which `bin/omamobile flash` (the documented recovery) and `push` never update, so after the recovery preflight refused every update. Its `save_previous` also treated slot B as booted with no record, a stale record or a record naming the running release; each can hold a set written in this boot (the hook's own same-release write, a half push), so the only recovery copy became a never-booted set marked `BOOTED=yes`. *Check:* list every way the thing can change after boot (the tool itself at the same version, fastboot, push, rollback's no-op branch, partial writes), run each in the package's fake root and then call preflight; prefer the kernel's evidence (`/sys/block/*/<part>/stat` write counters) over a record. Extends L-284 and L-363. *From:* #320, rounds 38 and 38b, 2026-11-02.
- **L-414. A counter that proves "nothing happened" needs the mechanism that counts to be on.** #320's partition write counters stay 0 when `queue/iostats` is off, which turned the fail-safe back into the original bug. *Check:* for any "zero means unchanged" signal, find the switch that disables it and ask that "off" counts as "changed"; ask for one read on the phone that the counter rises after a known write and is zero after a fresh boot (C-1). *From:* #320, round 38c, 2026-11-02.
- **L-415. Whether a check refuses or proceeds depends on where it runs relative to the irreversible step.** A refusal in a post-transaction hook (pacman has already removed the old modules) leaves a half-applied update; the same condition in the pre-transaction preflight costs only a restart. *Check:* when asking a hook to refuse, ask whether what it protects still exists at that point, and move the refusal to the earliest read-only gate when it doesn't. *From:* #320, round 38c, 2026-11-02.
- **L-416. A packing change is a boot change.** #320's reproducible cpio dropped the `.` entry, so the initramfs root stayed at tmpfs's 1777 instead of 0755; the commit proved byte reproducibility and nothing about what the kernel unpacks. *Check:* diff both archives' listings with modes (`cpio -itv`), root entry included, and ask for one boot with `tools/phone-smoke`. *From:* #320, round 38b, 2026-11-02.
- **L-446. An upgrade message in a shared package is scoped to the phones
  whose default changed.** #416's first draft told every phone to "set card
  = auto"; on the 9a that opts into an experimental speakerphone route, on
  the 6 Pro into an unverified one, and it printed even when there was no
  line to change. *Check:* for each `.install` echo that suggests a value,
  ask which devices it is safe on, and gate the echo on the file's actual
  content. Extends L-162. *From:* #416 (its review), round 39, 2026-11-03.
- **L-449. A new "supported state" in one daemon is checked against the
  units another PR starts at boot.** #373 made "no internet APN" a normal
  state; #398 starts sit-data at every boot, which then waits 60 s, fails
  and restarts every 70 s all boot, never reaching the start limit. *Check:*
  for each new non-error state, list the units that `Requires=` or start the
  daemon with `Restart=on-failure` and read what each does in that state.
  Extends L-174. *From:* #373 with #398 (commit review), round 39,
  2026-11-03.
- **L-450. A new configuration layer is checked against every reader that
  parses the file itself.** #416's device defaults sit before
  `/etc/omamobile/modem-sit.conf`, but omamobile-mmd and the shell read
  `[network]` and `[data]` from `/etc` directly and would never see a device
  value there; the layer was limited to `[audio]`. *Check:* `git grep` the
  config path across packages, list the sections each reader uses, and limit
  the layer to those, or share the loader. Extends L-233. *From:* #416 (its
  review), round 39, 2026-11-03.
- **L-461. A device package that copies the reference phone's boot-time
  radio start also copies, or answers for, its sleep handling of that
  radio.** #419 took cheetah's Wi-Fi start, unit and blacklist but not
  `omamobile-sleep`, which unloads Wi-Fi around s2idle by default and falls
  back after a failed D3. *Check:* for each radio a device package starts at
  boot, `git grep` the reference package's `system-sleep/` and `bin/*sleep*`
  for that radio's modules, and ask for the hook or a sleep result. *From:*
  #419, round 40, 2026-11-04.
- **L-462. A change to how one surface reads a shared state is checked
  against every other surface that shows it, and the reason each gives.**
  #421 moved the bar to the battery's reported state, while the lock (patch
  0026) uses charger-online on purpose and promises the bar's glyph.
  *Check:* `git grep` the state across the shell plugins and the Omarchy
  patch series, read each one's comment for its reasoning, and name the
  disagreement the PR creates. *From:* #421, round 40, 2026-11-04.
- **L-463. A file under `backup=` that another tool also writes gets an
  upgrade message that doesn't blame the user.** omarchy-apply-lock rewrites
  `/etc/pam.d/omarchy-lock-fingerprint` without our header, so pacman sees
  it as edited; #440's first message said "your file was changed". Check the
  other writer's text on main, not the text a pending PR will give it.
  *Check:* `git grep` the path across packages and the Omarchy series before
  writing any `.install` message about it. Extends L-450 and L-446. *From:*
  #440, round 41, 2026-11-05.
- **L-464. A quirk keyed on a SoC-level compatible is a reference-phone
  change, whatever the PR's board.** #202's 32-bit DMA clamp for lynx
  matched `google,gs201-mali`, the GPU in `gs201.dtsi` that the 7 Pro
  enables. *Check:* for every `of_device_is_compatible()` or match entry a
  board PR adds to a shared driver, `git grep '"<compatible>"' arch/` and
  see which boards carry it. Extends L-206. *From:* kernel #202, round 41,
  2026-11-05.
- **L-465. A new controller node in a shared SoC dtsi is checked against
  every board that includes it, first-light boards too.** #200 added
  `pinctrl_hsi1` enabled in `zuma.dtsi`, so the 8a's first-light board
  probes it untested, and gpiolib reads bank registers at registration.
  *Check:* `git grep -l '"<soc>.dtsi"' arch/arm64/boot/dts/` for each new
  node without `status`, and ask for `disabled` plus a board enable unless
  every board has run it. Extends L-206 and L-306. *From:* kernel #200,
  round 41, 2026-11-05.
- **L-466. A new call with arguments can make the compiler un-specialise a
  shared function on the reference phone's path.** #194's one
  `DISABLE_REPORT` call with a payload changed `tcm_command`'s machine code
  for every 7 Pro command, though the source path is the same. *Check:* the
  per-function object diff names each changed function; for one the PR
  didn't touch, read whether only argument setup changed. Extends L-301.
  *From:* kernel #194, round 40, 2026-11-04.
- **L-489. A per-SoC flag keyed on a compatible is checked for that
  compatible's existence on the base.** Kernel #203 gated AoC behaviour on
  `google,zuma-aoc`, which nothing on `omamobile` or in an open PR carries; it
  came from a 132-commit test tree. *Check:* `git grep '"<compatible>"'` on
  the base and open heads; if absent, hold the PR for the series that adds it.
  Extends L-149 and L-189. *From:* kernel #203, round 42, 2026-11-07.
- **L-490. A shared-path change gated on a pointer a probe-time table lookup
  can clear runs only on boards in that table.** #202's panel-mode path needs
  `dc->dsim`, which survives only for the 7 Pro's and 9a's DSIM timers
  (`gs_dsim_rates[]`), so it changed the reference phones and never ran on
  lynx. *Check:* trace which boards reach each new branch, and ask for the
  dmesg line proving the board under test took it. Extends L-206 and L-464.
  *From:* kernel #202, round 42, 2026-11-07.
- **L-491. A compositor or shell patch that changes what every phone shows is
  a reference-phone change, even when it fixes a bug the 7 Pro probably has.**
  #446's rotation hold is untested at 120 Hz. *Check:* for patches to
  `packages/hyprland`, `quickshell` or the shell, ask for a per-device switch
  the contributor's device package sets, until the 7 Pro has run it. Extends
  L-206. *From:* #446, round 42, 2026-11-07.
- **L-492. A contributor's finding on one device's guard is checked against
  the same rule on the reference phone.** #372's hold (the latch cleared
  whatever the unit's result) is what the 7 Pro's `omamobile-modem-start
  --stopped` does on main, as the script's comment credits. *Check:* open code
  a guard comment cites ("as on the Pixel 7 Pro"); if the finding applies
  there, it is a separate cheetah change with its own run. Extends L-444.
  *From:* #372, round 42, 2026-11-07.
- **L-493. A "no-op on cheetah" premise is checked against the reference
  phone's logs, not a plan table, and a runbook's Expect is not a result.** On
  kernel #116 we said the bootloader leaves MIF at 3172 MHz, from ACPM-PLAN's
  ECT table and A2's Expect line; the A2 run and all 332 gs-decon probes in
  `logs/` read 2028 MHz. *Check:* `grep -rh '<driver>.*<rate>' logs/ | sort |
  uniq -c`, and the plan's dated result rather than its expectation. See C-31.
  *From:* kernel #116, round 42, 2026-11-07.
- **L-494. A link constraint one PR documents for a shared C source is checked
  against every open PR editing that file.** #459 found the no-bootctl
  initramfs links `reboot-to` against musl without compiler builtins, so the
  printf family doesn't link, while #403 adds `snprintf` to the same file.
  *Check:* `gh pr list` for PRs touching the file, grep their heads for
  `printf`/`strto*`, and build a no-bootctl device's initramfs. Extends L-104
  and L-423. *From:* #459 with #403, round 42, 2026-11-07.
- **L-534. A tuning-file change is cheetah-neutral when the file's name is a
  sensor model only another board's compatible produces.** libcamera picks
  `<model>.yaml` by the subdev name, which `s5kgn1.c` takes from the match
  data's `model`. *Check:* the driver's `v4l2_i2c_subdev_set_name` argument,
  the match table, and `git grep` of the compatible in the gs201 DTs. Extends
  L-206. *From:* #494, round 44, 2026-11-08.
- **L-565. An error-path-only fix in a shared driver is cheetah-neutral in
  behaviour only while that error never happens, and its object still
  changes.** Kernel #222's one `break` reallocated registers across
  `s3c64xx_spi_transfer_one` (and moved the readl pool into `runtime_resume`'s
  last line), and the 7 Pro has three SPI users that chunk in PIO. *Check:*
  grep `logs/` for the error line the new branch follows (`I/O Error: rx-`: 0
  in 1000 logs) before calling the change invisible, and let the 7 Pro run
  record "not exercised" with that count rather than "the fix works". Extends
  L-51, L-206 and L-440. *From:* kernel #222, round 45, 2026-11-08.
- **L-566. A doc change we ask for in a shared package's plan is checked for
  which phone it claims.** On #376 we asked that the 7 Pro's MODEM-PLAN stop
  saying "a second start isn't supported" once the code changed; the reworded
  line states the new behaviour as a 7 Pro fact, measured only on the 9a.
  *Check:* for each sentence a PR changes under `device/<x>/`, find the run on
  that device that supports it, or ask for "on the <other phone>; not yet run
  here". Extends L-188 and L-31. *From:* #376, round 45, 2026-11-08.
- **L-567. A public device package tested next to a private companion is
  checked for which safety nets live only in the companion.** #222's oriole
  package installed cleanly, but only alongside a private package carrying the
  reboot watchdog and a boot check, and `device.conf`'s `PACKAGE=` makes the
  public one alone the image's device package. *Check:* when a smoke report's
  package list names a `*-local-*` or private package, ask what it ships, and
  map each safety file to the public package or to a "not supported yet" line
  in the README. Extends L-61, L-158 and L-358. *From:* #222, round 45,
  2026-11-08.
- **L-568. L-8 runs without touching anyone's build directory.** Copy a kernel
  output's `arch/arm64/boot/Image`, the device's DTBs,
  `scripts/dtc/{dtc,fdtoverlay}`, `initramfs.cpio.lz4` and
  `include/config/kernel.release` (and `initramfs.release`) into a scratch
  `KERNEL_OUT`, then run `DEVICE=cheetah images` with main's `bin/omamobile`
  (`git show origin/main:bin/omamobile`) and the PR's from the same worktree.
  `images` writes only `$KERNEL_OUT/images`, and a stale build is fine for a
  before/after compare. *Check:* six equal sha256s. Extends L-8 and L-194.
  *From:* #507, round 45, 2026-11-08.
- **L-569. A fix that updates every `cmp`-pinned copy of a shared source goes
  stale when a new package with the same pin merges first, and then it turns
  main red.** #459 updated seven `reboot-to.c` copies; akita's package, with
  the same `cmp` against cheetah's file, merged two days later (#456), so #459
  as it stands fails akita's `test/all` and needs an akita version that #509
  is about to take. *Check:* each round, for every open PR that edits a file
  other packages pin, `git grep -l '<pinned path>' origin/main --
  'packages/*/test/all'` against the PR's file list, and put the missing
  packages and their next free versions in the merge plan. Extends L-257 and
  L-426. *From:* #459 with #456 and #509, round 45, 2026-11-08.
- **L-570. A test kernel for `bin/omamobile push` needs four steps into its
  `KERNEL_OUT`: `kernel`, `initramfs`, `images` (with `DEVICE=cheetah`) and
  `modules`.** `push` refuses before any write when one is missing ("holds
  images for … an unknown device", "build the initramfs first", the missing
  modules tarball), so a skipped step costs a round trip, not the phone.
  *Check:* a runbook that hands the human a test kernel lists all four with
  the same `KERNEL_DIR`/`KERNEL_OUT`, in that order. *From:* the 2026-11-08 7
  Pro session.
- **L-606. A shared stop-path fix proven on one phone's unit is checked
  against the other phone's unit settings.** #372's rfsd hold makes the 9a's
  modem stop end in `success`, but the 9a's transient unit sends SIGINT to the
  whole control group, while the 7 Pro's `omamobile-modem.service` uses
  `KillMode=mixed` with SIGTERM to `unshare`, which issue #532 found doesn't
  exit. *Check:* for a "now ends in success on both phones" claim, compare
  `KillMode`, `KillSignal`, `TimeoutStopSec` and the main process of each unit
  that runs the shared code, and ask for (or do) a stop on each. Extends L-206,
  L-348 and L-492. *From:* #372 with issue #532, round 46, 2026-11-09.
- **L-607. "Enabled" read from `systemctl is-enabled`, or from "not masked",
  is wrong for a unit started by a vendor wants link in one device package
  and by nothing on the others.** #555's status line did that for a shared
  unit. *Check:* for a switch over a shared unit, list each device package's
  `*.target.wants/` links for it, and read `systemctl show -p WantedBy` rather
  than `is-enabled`. Extends L-137 and L-206. *From:* #555, round 46,
  2026-11-09.
- **L-608. A feature split into "opt-in" and "helper" parts is checked for
  which parts are actually behind the opt-in.** #556's inhibitor waits for
  `modem-suspend-enable`, but sitd's screen-state reporting, written as M6's
  helper, runs on every phone with sitd. *Check:* for each new behaviour in
  the PR, find the condition that gates it in the shipped unit or script, and
  list the devices it reaches with the opt-in off. Extends L-206 and L-458.
  *From:* #556, round 46, 2026-11-09.
- **L-609. A hand copy that one PR's record reveals is checked against the
  package another open PR ships for that phone.** #514's "Current state"
  listed an AoC blacklist in `/etc/modprobe.d` on the 8 Pro, while #453's
  first packaged boot was meant to test the package's own blacklist. *Check:*
  for each hand-installed file a contributor's notes list on a phone, `git
  grep` its role (modprobe, UCM, unit) across that author's open package PRs
  for the device, and add it to that PR's "remove the hand copies" step.
  Extends L-46. *From:* #453 with #514, round 46, 2026-11-09.
- **L-610. A stacked draft that carries another open PR's commits inherits
  that PR's pending reference-phone run, and the review says whose run it
  is.** Kernel #164's per-function diff showed 24 changed functions in
  cheetah's `gs201-csis.o` and 16 in `imx386.o`, all from #63 and #103, whose
  promised 7 Pro capture (10-28) the maintainer still owed. *Check:* map each
  changed cheetah object to the commit and PR it comes from (patch-id against
  the open heads), and grep those threads for the promised run before asking
  the contributor for anything. Extends L-196 and L-480. *From:* kernel #164,
  round 46, 2026-11-09.
- **L-611. A consumer-side "re-apply the pins" fix in a shared driver is shown
  cheetah-neutral through the pinctrl core's early returns, node by node.**
  For kernel #224, gs201's UFS has no `pinctrl-0`, so `dev->pins` is NULL;
  gs101 and zuma have "default" only, so the sleep select is `IS_ERR` and the
  default select hits `p->state == state`. *Check:* the reference phone's node
  and overlays for `pinctrl-*`, then `pinctrl_bind_pins()` and
  `pinctrl_select_bound_state()` on the base. Extends L-228. *From:* kernel
  #224, round 46, 2026-11-09.
- **L-612. Before planning a contributor's own test of a shared-driver path,
  check that their board's DT takes it.** Kernel #223's code runs only with
  `maxim,fg-model`, which on our tree only cheetah and panther have, so the
  author's Pixel 6 can't exercise it with the public tree. *Check:* `git grep
  '<property that gates the path>' github/omamobile -- arch/`, and name the
  phones that can test it. Extends L-490. *From:* kernel #223, round 46,
  2026-11-09.
