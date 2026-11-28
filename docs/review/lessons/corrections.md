<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Corrections (where a review was wrong) (part 1 of 2)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **C-66 (2026-11-27). Round 68 told kernel #164's maintainer that nothing in
  the stack reached the 7 Pro beyond #63 and #103, because the commit's
  subject names the Tensor G4 chips;** #164 rewrote `gpio-s2mpg13.c`, which
  cheetah's DTS binds and `omamobile-camera-start` loads at every boot.
  *Lesson:* a board-titled stack's shared-driver hunks are checked against the
  reference phone's boot units every round, not only the first: for every
  `drivers/` file in the PR's own range (`git diff --stat <bottom head> <head>
  -- drivers`), `git grep -n '<its compatibles>' <base> --
  'arch/arm64/boot/dts/exynos/google/gs201*'`, and grep device-cheetah's
  `bin/` and `modprobe.d/` for the module name; any hit is a 7 Pro path that
  needs an object compare or a run. Extends L-880 and L-858. *From:* kernel
  #164, rounds 68 and 69.
- **C-65 (2026-11-25). Round 67 told #998's maintainer that ten Python
  wrappers would cost 80 to 100 MB, from 8 to 10 MB RSS each;** the author's
  `RssAnon` and `VmSwap` figures gave about 5 MB each, because the
  interpreter's shared pages are counted once. *Lesson:* a memory cost we
  estimate for a contributor's design is counted as the private (anonymous)
  memory each copy adds, not whole-process RSS: `python3 -c 'import time;
  time.sleep(60)' & grep -E 'Rss(Anon|File)|Pss' /proc/$!/status
  /proc/$!/smaps_rollup` before writing a figure, and quote `Pss` or
  `RssAnon`. Extends C-4. *From:* #998, rounds 67 and 68.
- **C-64 (2026-11-24). Round 66 told #1009's maintainer that there was no
  polkit agent on the phone, and offered options on that basis; Omarchy 4.5's
  shell has one.** `plugins/polkit/PolkitAgent.qml` ships in the signed
  `omarchy-4.5.0-3`, our patches 0010 and 0011 adapt it to the on-screen
  keyboard and the PIN pad, and `omamobile-shell`'s
  `49-omamobile-admin-self.rules` makes it ask the owner for their own PIN;
  the maintainer's decision used it. *Lesson:* before writing that a phone has
  no prompt or agent for something, `bsdtar -tf` the pinned Omarchy packages
  for it and `git grep -n -i '<it>' origin/main --
  packages/omamobile-omarchy/patches packages/*/polkit`. Extends C-52 and
  C-36. *From:* #1009, rounds 66 and 67.
- **C-63 (2026-11-23). Round 64 asked kernel #249 to drop the angle brackets
  around a 40-hex blob id in its commit message;** checkpatch exempts a 12-40
  hex word only inside `<...>` or `[...]`, so the change the author made as
  asked turned the gate red for two pushes. *Lesson:* a wording request on a
  kernel commit message that touches a hash is run through checkpatch before
  it is posted: rebuild the commit with the suggested message on its own tree
  (`git log -1 --format=%B <c> | sed ... | git commit-tree <c>^{tree} -p
  <c>^`), then `git format-patch -1 --stdout <new> | scripts/checkpatch.pl
  --strict -`. Extends L-1098, L-743 and C-4. *From:* kernel #249, rounds 64
  to 66.
- **C-62 (2026-11-23). Round 63 told #931 that its `depends` entry `libssc`
  had no provider;** it is in Arch's `extra` (the phone installed it from Arch
  Linux ARM's), and `iio-sensor-proxy` depends on it. L-639's grep of our tree
  and open PRs was all the review ran. *Lesson:* a "nothing provides it"
  finding is checked against the distribution's repositories too: `pacman -Si
  <name>` on the review laptop, and the Arch Linux ARM index if the package
  might be aarch64-only, before it is reported. Extends L-639. *From:* #931,
  rounds 63 and 66.
- **C-61 (2026-11-21). A round 65 reviewer read 9 of the 25 lesson files to
  save context,** and said so in its report, which is the only reason it is
  known. The index says which areas every review reads, and a lesson that was
  not read cannot be applied or cited. *Lesson:* a report that read fewer
  files than the index asks for names the ones it left out, as this one did,
  and each pull request those files bear on gets them read anyway before its
  review is used, by the same reviewer or a second one; to save context,
  review fewer pull requests per run, not fewer lessons. Extends L-772 and
  C-57. *From:* round 65.
- **C-60 (2026-11-21). Round 63 verified that #905's `Qt.callLater` handler
  folds ten signals in a row into one rebuild, and took the title's "once per
  rescan" with it;** a third party's run on the 7 Pro then showed three rounds
  of signals 200 ms apart and three rebuilds, because the fold covers one
  event-loop turn only. Our own suggestion of the simpler form (L-1003) rested
  on the same probe. *Lesson:* a "once per burst" fix is probed with the burst
  in the shape a phone delivers it (some signals at once, some from a 200 ms
  timer), and the phone run is asked for the signals' timestamps, not only the
  count of rebuilds. Extends L-1003, L-954 and L-724. *From:* #905, rounds 63
  and 65.
- **C-59 (2026-11-21, a near miss). Removing #968's moved ramdisk-footer
  refusal left `tests/install-phone` green on the review laptop, and the line
  was nearly reported as untested:** its case lives in
  `tests/install-phone-initramfs`, which prints `ok - # skip: no dtc` locally
  and ran in full in CI. *Lesson:* before calling a line untested, `git grep
  -n '<the refusal's words>' -- tests`, and for a suite that skips here read
  its own `ok` lines in CI's log (`gh run view <id> --log | grep -A8 '#
  tests/<suite>'`). Extends L-103 and L-742. *From:* #968, round 65.
- **C-58 (2026-11-21, a near miss). Comparing the added lines main's scanner
  and #966's read, four of 112 pull requests looked like lost lines:** a file
  added under one name and renamed later is listed under its first name by a
  per-commit scan and under its last by a range diff. The lines were all there
  once the comparison dropped the name. *Lesson:* when two scanners' dumps are
  compared, key on content before file name (`sed 's/^[^:]*: //'` on both
  before `comm -23`). Extends L-896. *From:* #966, round 65.
- **C-57 (2026-11-21, a near miss). A round 64 reviewer told to read "the
  lesson files" read the shared checkout's copies, which were 36 commits
  behind `origin/main`:** the index there listed 15 files where main had 24,
  from before the round 60 to 63 lessons and their re-split. It showed only
  because the reviewer listed what it read, and the missing entries were then
  read from `origin/main`. *Lesson:* `git diff --stat HEAD origin/main --
  docs/review` before the first Read; if it isn't empty, `git archive
  origin/main docs/review | tar -x` into the review's own folder and read from
  there. Extends L-953 and L-772. *From:* #957, round 64.
- **C-56 (2026-11-21). Round 63's review of the lint in #907 listed three
  `head` lines of #763 that the lint would turn red, and #763's comment of the
  same round didn't carry them,** though L-1036 says it should: the
  contributor pushed twice more with the lines still there and one added.
  #915's answer to its own review added a `| head -n 1` the same way, written
  after the list, on a base without the lint and on a branch whose conflict
  means no CI. *Lesson:* before posting, grep each listed PR's draft comment
  for the file names the lint's review lists for it; and for every re-push
  that touches `tests/` or `packages/*/test/`, run `tests/head-pipes` and
  `tests/grep-q-pipes` on a scratch merge with main and hand over the
  replacement line. Extends L-1036, L-680 and L-405. *From:* #763 and #915
  with #907, rounds 63 and 64.
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
