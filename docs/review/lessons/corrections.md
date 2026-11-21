<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Corrections (where a review was wrong)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **C-55 (2026-11-20). Round 61 asked kernel #255 for a `memory-region`
  restricted pool on the Wi-Fi endpoint's node; ath11k's PCI probe treats any
  `memory-region` there as fixed firmware memory** (`of_property_present()`),
  so the property would have switched the driver's firmware path, with the
  pool enabled or not. For a PCI device the pool can sit on the host
  controller's node: `of_dma_set_restricted_buffer()` falls back to the DMA
  parent. *Lesson:* `git grep -n '"memory-region"' drivers/<the endpoint's
  driver>` before asking for the property on an endpoint, and name the
  controller node as the alternative. Extends L-239, L-777 and C-4. *From:*
  kernel #255, rounds 61 and 63.
- **C-54 (2026-11-20, a near miss). A `while read` loop in a review script
  ran `patch` in its body, which read the rest of the loop's list as its own
  input: the libcamera series check "applied" one patch and reported no
  failure.** The listing showed the tuning files missing. *Lesson:* a loop
  whose body runs anything that reads stdin takes its list on another
  descriptor (`while read -r p <&3; ...; done 3< list`), and its result is
  confirmed by a file the last step creates. Extends L-293. *From:* #934,
  round 63.
- **C-53 (2026-11-20, a near miss). Two mutations of `omamobile-osk` in
  #896's review proved nothing.** The first, a `sed` on `exec squeekboard`,
  also hit the plain start path, so the suite failed in an early group; the
  second changed nothing the test could see and "passed". Redone as a
  replacement of one exact multi-line string, each failed on the `not ok`
  line of the case under review. *Lesson:* a mutation is applied at one exact
  anchor, with an assertion that the anchor was found, and the `not ok` line
  that fires is read for its name before the result is used. Extends L-419
  and L-742. *From:* #896, round 63.
- **C-52 (2026-11-20, a near miss). Looking for `default/hypr/input.lua`
  in the `omarchy` 4.5 package found nothing, which read as "the file does
  not exist".** Omarchy 4.5's Hyprland defaults and input-method scripts are
  in the `omarchy-settings` package. *Lesson:* `bsdtar -tf` both cached
  packages before quoting or doubting a 4.5 path. Extends L-652 and L-498.
  *From:* #892, round 63.
- **C-51 (2026-11-18). Round 61's comment on #864 asked again for two
  things the contributor had answered fifteen minutes before it was posted.**
  The draft was written against one head; a push and a reply came between
  the draft and the posting. *Lesson:* every draft records the head it read,
  and the posting step compares it with `gh pr view N --json headRefOid` and
  the newest comment's time with the draft's, and holds a draft whose PR
  moved. Extends L-124 and L-480. *From:* #864, rounds 61-62.
- **C-50 (2026-11-18, a near miss). A probe for #898 sourced
  `revoked_file_check` into the review shell, where `grep` was a shell
  function wrapping another grep that accepts a CRLF line; for a few minutes
  that read as a hole in main's revocation check.** `/usr/bin/grep` refuses
  the line, and so does the tool, which runs as a script and inherits no
  unexported function. *Lesson:* `type -t grep sed awk` before trusting a
  sourced probe (anything but `file` is a stand-in), and run such probes as
  `env -i PATH=/usr/bin bash --noprofile --norc -c 'source <lib>; <call>'`;
  a result that contradicts the PR's own tests is re-run that way before it
  is written down. Extends L-454 and L-681. *From:* #898, round 62.
- **C-49 (2026-11-18, a near miss). With `TMPDIR` set to a path with a `..`
  component, `tests/install-phone` and `tests/install-guided` failed on
  main's own files, and we nearly reported a regression from the morning's
  merges.** The installer prints canonical paths and the tests grep for
  `$t/...` as `mktemp` spelled it; with the same directory written out, all
  cases pass. *Lesson:* give every suite a canonical `TMPDIR`
  (`TMPDIR=$(readlink -f ...)`), and before blaming a PR or main for a local
  failure CI doesn't show, run the same suite on main's files in the same
  shell (L-42) and print the tool's output beside the pattern it missed.
  Extends L-674 and L-42. *From:* #877, round 62.
- **C-48 (2026-11-18). Our reproduction of #890's signal-handler deadlock
  ran under a plain `timeout 5` and outlived the command's own limit, and the
  `pkill -f <path>` meant to end it matched the review's shell.** A process
  stuck that way ignores SIGTERM. *Lesson:* a reproduction of a hang runs
  under `timeout -s KILL N`, and is ended with `kill -KILL <pid>` after
  reading `pgrep -f`'s list. *From:* #890, round 62.
- **C-47 (2026-11-18, a near miss). The first draft on #892 said its guard
  could leave a locked phone without its keyboard for 10 s after every
  power-key lock, because the lock poll slows to 10 s with the screen off.**
  `next_deadline()` fixes the interval when the poll is scheduled, while the
  screen is still on, so an ordinary lock is seen within 2 s; only a poll
  that lands between "backlight 0" and "locked" gets the slow interval.
  *Lesson:* before writing "up to N seconds" about a poller, write the
  timeline (the last poll, when the next was scheduled and with which
  interval, the event, the next poll) and find the line that assigns the
  deadline. Extends C-41 and L-573. *From:* #892, round 62.
- **C-46 (2026-11-17, a near miss). Round 59's unposted draft on #832 said a
  lower clock ceiling could leave the package's `test/all` as it was.** The
  suite also compares the 8a's settings with the 8 Pro's file and fails on
  any other value. *Lesson:* before a draft offers "or lower the number",
  `sed` the offered value into a scratch worktree and run `test/all`, and
  list every `../omamobile-device-<sibling>` comparison that pins the value.
  Extends L-270 and L-64. *From:* #832, rounds 59-60.
- **C-45 (2026-11-17). Round 58's comment on #812 said "set it to 0.1.17",
  and round 59's comment on #827 gave the same package the same number.**
  #812's head still read 0.1.15 when the second check ran, since its author
  had not pushed yet, and both authors did as asked. *Lesson:* a version a
  draft names is checked against the versions we named in our other comments,
  not only against open heads: `gh pr list --search "<package>"`, then grep
  our own last comment on each hit for a version; a number promised anywhere
  is taken. Extends L-217, L-426 and L-551. *From:* #827 with #812, round 60.
- **C-44 (2026-11-17). A scratch probe in #850's review ran `rm -rf
  "$t/proc"` in a loop, and the session's safety check refused it, rightly.**
  With `$t` empty the path is `/proc`. *Lesson:* a probe never removes a path
  built from a variable: every case gets its own numbered folder under the
  review's scratch folder, nothing is removed in the loop, and the scratch
  folder is removed once, by its literal path. Extends L-641. *From:* #850's
  review, round 60.
- **C-43 (2026-11-11). Round 50 told #226's author that the sampler test sat
  "on its own line in `tests/all`, clear of the loop that everyone else
  appends to".** It sits directly above that loop line, git merges adjacent
  changed lines as one hunk, and `git merge-tree` with #374 conflicts there.
  *Lesson:* before calling a placement conflict-free, run `git merge-tree`
  against one open PR that edits the hot line, and point new suites at the
  "one suite per line" block at the end of `tests/all`. Extends L-549.
  *From:* #226 against #374, round 52.
- **C-42 (2026-11-11). We merged #670, the move of the Omarchy pin to
  4.5.0-3, on an update test from a Pixel 7 Pro that had been pushed a new
  boot image first.** A phone still on an older boot image has `/run` at mode
  1777, which Omarchy 4.5's sudo migration refuses (issue #447), so the
  development channel carried a broken update for a few hours, until #673's
  tmpfiles.d rule set `/run` to 0755. *Lesson:* an update test starts from the
  state a user's phone is in (the last release's install and boot images, no
  pushes), not the state the test phone was prepared into. See L-433 and
  L-500. *From:* #670 with #437 and #673, round 52.
- **C-41 (2026-11-10). Round 49 asked #562 to document that without the
  SSH-ready helper "every second boot stays in RAM".** A held boot never
  removes `/var/lib/omamobile/root-boot-pending` (the PR's own test asserts
  it), so it is every boot after the first, until the marker is removed by
  hand; the wrong sentence went into RELEASES twice. *Lesson:* for every
  behaviour sentence in a draft comment, find the line that makes it true or
  the test that asserts it before the contributor copies it. Extends C-4.
  *From:* #562, round 50.
- **C-40 (2026-11-10). Our 11-09 comment on #330 credited "the first boot of
  #505's own image, `/dev/sda` removed"; the image behind it was a different
  build, with `/dev/sda` present and writable.** The contributor found it by
  booting it again. *Lesson:* before crediting a boot to a PR's image, ask for
  the tie between its hash and the PR head (the builder's
  `BOOT-MANIFEST.json`, the commit); for a mislabelled image that still
  exists, ask for its ramdisk's `init` diffed against `initramfs/init`,
  readable without a phone; then take the earlier claim back. Extends L-645
  and L-600. *From:* #330 with #505, round 49.
- **C-39 (2026-11-10). Round 48 told #567's author that the 9a ships no AVB
  footers, so there was no precedent, from `device/tegu/device.conf`.**
  `device/tegu/NOTES.md` records a second 9a that stopped in fastboot without
  footers and booted with index-0 footers. *Lesson:* `git grep -n -i footer
  device/<sibling>/` (the notes and plans, not only the descriptor) before
  writing what a sibling does. Extends L-31 and L-187. *From:* #567, round 49.
- **C-38 (2026-11-10). Round 48 asked #567 to take `AVB_ROLLBACK_INDEX` from
  stock's `boot` footer; komodo's reads "Algorithm NONE, rollback index 0",
  which says the partition isn't chained.** The request produced a lower index
  than the phone had already booted marked, while its siblings' stock footers
  carry the patch date. *Lesson:* when asking for stock AVB values, ask first
  for `avbtool info_image` on `vbmeta_<slot>` (chain or hash descriptors,
  rollback locations, flags), and take the index from the structure the
  bootloader verifies. Extends L-225 and L-169. *From:* #567, round 49.
- **C-37 (2026-11-10). Our round 46 request on #553 named the panel's bottom
  inset and `Style.gapsOut` as the swipe strip's size; `hypr/phone.lua` sets
  `gaps_out = 0`, so the strip built from them was too thin to hit.** Only the
  owner's hand try found it, though L-619 used that value in the same review.
  *Lesson:* before suggesting a size "from the inset and the gap", compute it
  with `phone.lua`'s values and compare it with the 28 px floor the shell's
  other strips use. Extends L-619 and L-229. *From:* #553, round 49.
- **C-36 (2026-11-10). Round 48 told #571's author to turn
  `omarchy.remote-session` off on every phone because "a remote desktop
  listening on a phone shouldn't be the default"; the plugin only detects a
  gliff session for Omarchy's bar indicator.** Nothing listens unless someone
  starts `gliff-server` (the package ships no unit), and the contributor
  copied our reason into a shipped comment. *Lesson:* before a draft gives a
  security reason for a switch, read the component's manifest and list its
  consumers (`grep -rn '<id>'` over Omarchy's shell and ours); name what
  actually listens and what starts it. Extends L-31 and L-229. *From:* #571,
  round 49.
- **C-1 (2026-10-22). We blamed the 30 s unused-regulator cleanup for the
  felix cover touch's dead rails (issue #3).** We have no S2MPG12 regulator
  driver at all (cheetah's `s2mpg12-pmic` node is RTC and interrupt masks
  only, and disabled), so nothing in Linux can turn those LDOs off: the rails
  are off as ABL left them. *Lesson:* before blaming a kernel mechanism,
  check the driver for it is actually bound on that device
  (`/sys/kernel/debug/regulator/regulator_summary`, the DT node's status).
- **C-2 (2026-10-23). C-1 said cheetah's `s2mpg12-pmic` node is disabled;
  that is true of the DTS, but the `suspend-pmic-test` overlay in cheetah's
  `DTB_OVERLAYS` enables it.** C-1's conclusion (no regulator driver, so no
  Linux cleanup of those LDOs) still stood then. *Lesson:* L-49. *From:*
  kernel #27.
- **C-3 (2026-10-24). L-88 said husky's DWC3 cycle hung `device_shutdown`
  under `reboot-to`; it didn't.** The laptop's log shows the gadget left at
  the unbind and never returned: the phone froze at the bind, so the fallback
  never ran (#23 tests 23-28). L-88's rule stands, but a freeze that stops
  every CPU defeats every software dead-man, sysrq included. *Lesson:* for a
  step that can freeze the SoC, only the buttons or a hardware watchdog left
  unfed bring it back; the runbook says so and is run attended. *From:*
  kernel #33, round 10.
- **C-4 (2026-10-24). Round 9 told #35's author that LDO11M-LDO13M are CPU
  cluster rails; LDO13M is the TPU rail** (`L13M_VDD_TPU_M`), and our wording
  went into a commit message. *Lesson:* a fact we hand a contributor for a
  commit needs the line-level source we'd ask of them. *From:* kernel #35,
  round 10.
- **C-5 (2026-10-26). Round 11 asked kernel #48's author for `Assisted-by:
  AGENT_NAME:MODEL_VERSION`; the `coding-assistants.rst` on `omamobile` gives
  `Assisted-by: LLM [TOOL1] [TOOL2]`,** which the author used. *Lesson:*
  quote kernel process docs from the branch the PR targets (`git show
  github/omamobile:Documentation/process/…`), not from memory. Extends C-4.
  *From:* kernel #48, round 12.
- **C-6 (2026-10-26). Round 11's request that `aoc-stage s2mpu` require
  `cycle` and a `tzpc` restore was wrong.** raven's AUDIO-PLAN R2.1c/d record
  both DTZPC SMCs hanging the SoC, and R2.1g makes the read safe through the
  `pd` stage. *Lesson:* L-147. *From:* #22, round 12.
- **C-7 (2026-10-27). Round 12 told kernel #9's author to boot with
  `pd_ignore_unused` and read `pm_genpd_summary` to see whether a warm reset
  re-powers the gs101 domains; on 7.3 that can't answer it.** The flag only
  skips `genpd_power_off_unused()`; genpd's `of_genpd_sync_state()` still
  powers off every unused domain of the provider early in boot, so the
  summary reads "off" either way. The contributor answered the question with
  each domain's `active_time` in `debugfs/pm_genpd/`, which starts from the
  STATUS the driver reads at probe. *Lesson:* when we prescribe a test
  through a kernel parameter, read what it does in the tree the PR targets
  before posting it, and say which observable answers the question. L-135
  corrected in place. Extends C-5. *From:* kernel #9, round 20.
- **C-8 (2026-10-27). Our 2026-10-26 comments on issue #36 accepted a
  contributor's reading of stock's log, "the very first cold cycle already
  passes auth", and built a request on it; the vendor driver's sequence
  contradicts it.** cnss2's probe powers the chip on, enumerates it and
  powers it off before the first BHI, and `wlan_buck_enable` logs on every
  power-on, so the first cycle in the log is the probe's and the auth most
  likely came from the second. No existing lesson was wrong; the gap was
  that no lesson asked for the re-derivation. *Lesson:* L-204 (with L-203
  for the rail history the read needed). *From:* issue #36, round 21.
- **C-9 (2026-10-27). Our 2026-10-26 comment on issue #36 said lynx has no
  BT_EN, XO-clock or bootstrap GPIO, after reading only the Wi-Fi node.**
  Stock's Bluetooth node names the Wi-Fi buck pin as its `xo-clk-gpio`, reads
  WLAN_EN and powers the chip's Bluetooth side before the first Wi-Fi load.
  *Lesson:* a pin's role is read from every stock DT node that names it
  (`grep -rn` the pin across the device's DTs, then each consumer's driver).
  Extends L-94 and L-190. *From:* issue #36, round 22.
- **C-10 (2026-10-27). Our 14:50Z comment on kernel #56 asked for a rebase
  onto the BCM4389 series because its ID commit was on `omamobile`; nine
  functions and fields the PR builds on exist only in `omamobile-int`.**
  *Lesson:* before asking for a rebase onto published work, `git grep` the
  base for each identifier the PR's hunks use as context, and compare `git
  log github/omamobile -- <dir>` with `github/omamobile..omamobile-int`.
  Extends L-121 and L-154. *From:* kernel #56, round 22.
- **C-11 (2026-10-28). Round 20 asked kernel #63 for `google,wdma-input:
  false` in the zumapro branch of `google,gs201-csis.yaml`; no such property
  exists.** The slot is `google,ebuf`, and the branch already set it to
  false; we named the property from its description. The contributor caught
  it. *Lesson:* a property we ask about is quoted from `git grep` on the
  head's binding and the driver's `device_property_read_*` calls, with its
  rule in each `if/then` branch read. Extends C-4. *From:* kernel #63, rounds
  20 and 24.
- **C-12 (2026-10-28). Our issue #36 comment said the stock-kernel
  diagnostic ruled out the host side; it couldn't on its own.** The
  diagnostic and step 6 each differed from the passing Android boot in a
  different variable (host, timing), so both stalls left "both missing" open,
  and the same comment built a Bluetooth lead the thread's data had ruled
  out. *Lesson:* a negative run excludes a variable only if it differs from
  a passing run in that variable alone; tabulate each run against the passing
  one first. L-215 corrected in place. Extends L-190 and L-204. *From:* issue
  #36, round 23.
- **C-13 (2026-10-28). Our restore ruling on #35 listed stock slot A's
  partitions from memory and missed `pvmfw`.** The factory image's
  `fastboot-info.txt` is the exact list `fastboot update` writes, and every
  fastbootd logical flash first resizes the partition, rewriting `super`'s
  metadata, which a "nothing unsuffixed" rule forbids word for word.
  *Lesson:* take the list from `unzip -p image-*.zip fastboot-info.txt`, and
  name the resize in any exception that allows logical writes. Extends L-205;
  see L-226. *From:* #35, round 23.
- **C-14 (2026-10-28). L-130 said cheetah boots footer-less images under a
  stock vbmeta that chains boot and init_boot; it compared the factory vbmeta,
  not the phone's `vbmeta_b`.** That `vbmeta_b` isn't stock (another key,
  hash descriptors, no chains). In libavb a chained partition with no footer
  is invalid metadata, which unlocked ABL doesn't override, so every cheetah
  with a stock `vbmeta_b` needs footers (#104, issue #11). *Lesson:* compare
  the vbmeta of the slot that boots, read from the phone or its backup, and
  look for `Chain Partition descriptor` before blaming the bootloader. L-130
  corrected in place. *From:* #104, round 24.
- **C-15 (2026-10-28). We advised admin-merging kernel #108 past a red check
  before reproducing the failure.** It happened to be right (the gate's
  fault, L-246), but L-30 says reproduce first: a gate failure can be the
  tool's fault, and can't be assumed to be. *Lesson:* no merge advice past a
  red check until the failure is reproduced and its cause named. Extends
  L-30. *From:* kernel #108, 2026-10-28.
- **C-16 (2026-10-28). Our round 24 review of kernel #98 made two wrong
  offers.** It said a `qcom,wcn6855-pmu` node "avoids all of this", but the
  sequencer reference-counts across targets, so with Bluetooth its only
  consumer the buck still drops (L-269); and it offered "keep the fixed
  regulator, say so in the message", which can't pass `dtbs_check` against the
  binding's eight required supplies (L-270). Both withdrawn on the PR. L-241
  corrected in place. *From:* kernel #98, round 25.
- **C-17 (2026-10-28). Our 17:53 comment on kernel #80 asked for
  `tools/phone-smoke`'s haptics section, which doesn't exist.** The #96
  comment corrected it with read-only probe checks. *Lesson:* L-276. *From:*
  kernel #80 and #96, round 25.
- **C-18 (2026-10-28). Our 14:17 review of #74 missed that its
  `omamobile-tegu-display.conf` sets `gs_dsim_cmd allow_tx=1` for every
  panel,** against the `google-tg4c`-only guard that kernel #90's acceptance
  leaned on. *Lesson:* L-277. *From:* kernel #90 with #74, round 25.
- **C-19 (2026-10-29). Our round 27 comments on #131 and kernel #124 asked for
  the RT9470 bring-up module and TCPC DT "on a branch or as a draft PR"
  without naming the repository,** and #136 put a kernel module and a DT
  fragment in omarchy-mobile, against CONTRIBUTING §6.1; the fragment also
  references `&hsi2c10`, which no published tree defines. The round 28 draft
  on #136 owned the mistake and asked for a branch on linux-omarchy-mobile.
  *Lesson:* L-71 (and L-240 for the labels). *From:* #131, #136 and kernel
  #124, rounds 27-28.
- **C-20 (2026-10-29). Our kernel #109 comment told the FT3658 author that the
  90-byte report is long enough for the Exynos SPI driver to use DMA, and
  suggested `____cacheline_aligned`; kernel #133 copied both.** gs201's USI
  SPI nodes have no `dmas`, so `spi-s3c64xx` polls and never DMAs; the claim
  came from stock's DT, which adds `dmas` in its board files. On arm64
  `____cacheline_aligned` is 64 bytes, below `ARCH_DMA_MINALIGN` (128).
  *Lesson:* L-329 (and C-4: a fact we hand a contributor needs the line-level
  source). *From:* kernel #109 and #133, round 29.
- **C-21 (2026-10-29). Our kernel #109 review asked for
  `CONFIG_TOUCHSCREEN_FOCALTECH_FT3658=m` in panther's `kernel.config`,** and
  #149 followed it, though RELEASES keeps that fragment for options that would
  break another device and the release kernel is built from the shared
  fragment alone. L-314's "a gap in our own build goes in
  `device/<codename>/kernel.config`" pointed the same way. The round 29 draft
  on #149 owned the request and asked for the shared fragment. *Lesson:*
  L-337. *From:* kernel #109 with #149, round 29.
- **C-22 (2026-10-29). Our 00:53 review of kernel #98 read the evidence
  comment that quoted the phone's public Bluetooth address without flagging
  it;** a second comment repeated it. The round 29 draft asked for both to be
  edited. *Lesson:* L-324. *From:* kernel #98, round 29.
- **C-23 (2026-10-31). Our 10-28 comment on kernel #107 suggested
  `tools/usbc-deadman` for the 9a's repeater test,** but the tool is
  hard-wired to the 7 Pro's MAX77759; the 31st's round corrected it to a
  `systemd-run` reboot timer plus a fresh SSH login. *Lesson:* L-295 (a
  tool's device scope before recommending it). *From:* kernel #107.
- **C-24 (2026-10-31). Our earlier lynx rounds let `CONFIG_BT_BNEP` sit in a
  lynx-only `kernel.config`,** which the release kernel never reads; an
  option that breaks no phone belongs in `kernel/configs/omamobile.config`.
  *Lesson:* L-337. *From:* #98 and kernel #98.
- **C-25 (2026-11-01). Our round 32 comment asked kernel #165 to pin LDO15S
  at min = max "so the core sets 3.3 V before enabling it".** #101's
  `s2mpg14_ldo_ops` has no `set_voltage_sel`, so the pin either writes
  nothing or fails registration, and `s2mps11` then fails its whole probe.
  The wording reached the contributor's commit message; round 33 owned it
  and asked for the hand-off voltage. *Lesson:* before asking for min = max,
  read the regulator's ops on the target branch. *From:* kernel #165 with
  #101.
- **C-26 (2026-11-03, provisional). Our 10-27 reply on issue #77, and L-190,
  ruled out a longer BT_REG_ON hold because raven's plan had already held
  the line low for seconds.** Those holds were with the driver unbound and
  the UART closed; `power_on_delay_ms` holds it low with the UART open right
  before power-up, and 100 ms gave 0 silent chips in 15 clean reboots (about
  1 in 5 before). Google's driver holds 30 ms; the 100 ms is the HAL's.
  *Lesson:* "we already tried it longer" rules out a timing change only if
  the earlier try had the same sequence around it (which lines were driven,
  the UART open or closed, what ran right after). L-190 is corrected in
  place once the tally holds. *From:* issue #77 with #395.
- **C-27 (2026-11-03). L-326 said clk-acpm registers the gs101 clocks with
  `CLK_GET_RATE_NOCACHE`.** On the base only `acpm_clk_gs201` and
  `acpm_clk_zumapro` set the flag; `acpm_clk_gs101` has none, though gs201
  reuses `gs101_acpm_clks`, so gs101's `clk_get_rate()` is cached. L-326's
  cheetah conclusion stands; its text is corrected. *Lesson:* read the
  per-SoC `acpm_clk_driver_data.flags`, not the clock list it points at.
  *From:* kernel #189.
- **C-28 (2026-11-03). Our round 1 point on #282 started from the
  contributor's "0xb1 in every dump of the day, cable out".** The first
  read-only baseline decodes to no input, battery only, charger off (`0x00 /
  0xf8 / 0x00`); 0xb1 appears only with a source on CHGIN, so the 11-01 trip
  was the charger charging from the phone's own boost, not noise. The
  guard's design stands; the runbook's text and the a4 expectations changed.
  *Lesson:* see L-439. *From:* #282 with #272.
- **C-29 (2026-11-04). Our round-39 requests on #403 and #372 asked for "no
  UFS errors" after a `reboot-to`, read from the next boot's journal.**
  `reboot-to` skips systemd's shutdown, so an error-handler pass in
  `device_shutdown` happens after the last journal write, and a count of 0
  is certain. *Lesson:* L-434 applies to the evidence we ask for, not only
  to what contributors report: before asking for a shutdown-time count, name
  the log that outlives the event (the pstore console), or say "not
  observable". *From:* #403 with #372.
- **C-30 (2026-11-07). Round 41 told #425's author that Quickshell's
  `FileView::reload()` doesn't re-arm its file watch; it does.** `reload()`
  calls `updatePath()`, which calls `updateWatchedFiles()` (`fileview.cpp` at
  2b4501a), and the contributor caught it. *Lesson:* before saying "X never
  calls Y", follow each entry point down to Y in the version the phone runs
  and quote the call chain. Extends C-4 and C-11. *From:* #425.
- **C-31 (2026-11-07). On 10-29 we told kernel #116's author the MIF restore
  is a no-op on cheetah because the bootloader leaves MIF at 3172 MHz.** The 7
  Pro's MIF reads 2028 MHz at probe in every log; the number came from a plan
  table and an Expect line, and went into the contributor's commit. *Lesson:*
  see L-493; ACPM-PLAN and DISPLAY-PLAN were corrected in #480. *From:*
  kernel #116.
- **C-32 (2026-11-08). Round 44 told #471's and #420's authors that #420's
  0029, a 4.0.6 patch, would most likely break the 4.5 family; it applies at
  fuzz 0 to the real omarchy 4.5.0-3 package.** The real risk was 4.0.6 phones
  losing 0029 and an untested 4.5 behaviour, and Omarchy's packages are signed
  and public. *Lesson:* for a claim about a fuzz-0 apply on a version we don't
  have cached, download the package from `pkgs.omarchy.org/<channel>/aarch64/`
  into its own scratch directory, verify it with `gpgv --keyring
  /etc/pacman.d/gnupg/pubring.gpg`, run the package's `test/patches.py` with
  `OMARCHY_PKG` set, and report the result, not "most likely". Extends L-548.
  *From:* #471 with #420, rounds 44-45.
- **C-33 (2026-11-08). Round 44 told kernel #219's author the FTS5 series was
  probably developed on other SDM845 phones; its upstream cover letter says it
  was tested on a Xiaomi Mi 8.** *Lesson:* before doubting a "tested on X"
  claim about an upstream series, read the cover letter (patch 0/N) and the
  maintainer's apply mail, not only the patches. Extends C-4. *From:* kernel
  #219 with #330, rounds 44-45.
- **C-34 (2026-11-09). Our 11-02 comment on #290 suggested `mapfile -t apks <
  <(…) || die` as the explicit stop; it can never fail.** The `||` tests
  mapfile's status (0), and a process substitution's exit status is lost,
  under `set -e -o pipefail` too; the contributor caught it in #535.
  *Lesson:* a shell error-handling form we suggest is run once with a failing
  command before we post it (`bash -c 'set -euo pipefail; mapfile -t a <
  <(false) || echo caught; echo went on'` prints "went on"). Extends C-4 and
  L-229. *From:* #290 with #535, round 46.
- **C-35 (2026-11-09). Round 45 told #505's author "I ran `tests/dipper-probe`
  … and they pass" without checking that anything calls it;** `tests/all`
  doesn't, so CI never has, and round 45 wrote L-586 for #471 the same day.
  *Lesson:* L-586 applies to every new file under `tests/` too, not only
  package tests: `git grep -n '<basename>' <head> -- tests .github` before
  saying a test guards anything. *From:* #505, rounds 45-46.
