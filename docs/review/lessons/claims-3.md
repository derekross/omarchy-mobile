<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Claims and evidence (part 3 of 3)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-435. "Tn ran" or "Passed" is checked against the step's own
  definition, a dated results row, the PR's later fixes and the linked
  issue's newer results.** FINGERPRINT-PLAN's status said T1-T3 ran with
  only part of T1 evidenced; #372's step 4 kept "Passed" after a later
  commit fixed the reboot it described; #395's "Next" had already run and
  been reported on #77. *Check:* grep the plan for each step's definition
  and a results row with `uname -r`, grep the record for behaviour each
  later fix commit changes, and read the linked issue's comments since the
  last push. Extends L-28, L-188, L-266, L-313 and L-341. *From:* #405,
  #372, #395, round 39, 2026-11-03.
- **L-436. A smoke report with a hand-edited package list, or one older than
  the head, isn't evidence for the head.** #389's report listed
  "omamobile-modem-sit (number set at merge)-1" and predated two rebases.
  *Check:* every version in the report can exist; the report is newer than
  the head's last commit, or the PR names the tested commit and `git diff
  <tested> <head> -- <files>` is empty. Extends L-358 and L-379. *From:*
  #389, round 39, 2026-11-03.
- **L-437. A byte dump of a persistent bootloader record is decoded byte by
  byte, read after its write path ran, and contradicting runs ask what wrote
  it in between.** Kernel #176's `00 00 00 80` was read as the bootloader
  record but is `0x80000000` (VALID | NORMAL, what stock writes for an
  ordinary reboot), taken before the reboot notifier wrote anything; runs on
  11-01 and 11-03 disagreed on a record that survives reboots and that stock
  rewrites on each. *Check:* write the expected value's bytes out (`fc 00 00
  80` for `0x800000fc`), confirm the read came after the notifier or hook,
  and for any non-volatile bootloader input ask for a read before the first
  try and the boots in between. Extends L-29, L-168 and C-12. *From:* kernel
  #176, round 39, 2026-11-03.
- **L-438. A DEVICES cell's count is tied to the run that produced it, and a
  helper it names is checked against the published DT.** #406 put a
  10-minute session's 538 of 556 fixes on a first boot that only bound the
  driver, and credited the 8 Pro's USB rescue to a helper whose I2C bus is
  disabled in the published `zuma-husky.dts`. *Check:* quote the notes
  sentence around each number with its kernel, and for each helper find the
  bus or node it opens and its `status` on `github/omamobile`. Extends L-28,
  L-49 and L-345. *From:* #406, round 39, 2026-11-03.
- **L-439. When a clean baseline lands, every "value X is always there" it
  bears on is re-checked, and a guard that compares a field the step itself
  drives trips on that step.** #282's round 1 accepted "0xb1 in every dump,
  cable out"; the baseline shows 0xb1 only with a source on CHGIN, which
  made the 11-01 trip the charger charging from the phone's own boost, and
  the planned a4 guard compares CHGIN with a cable-out baseline right after
  the phone puts 5 V on it. *Check:* decode the baseline field by field with
  the driver's enums next to every value the runbook calls normal, re-read
  review points built on it, and list a guaranteed trip as the expected
  first outcome. Extends L-31 and L-147. *From:* #282 with #272, round 39,
  2026-11-03.
- **L-440. The test plan for a fix that acts on a late answer needs a late
  answer.** Kernel #152 releases a timed-out ACPM slot when the answer
  finally arrives; the planned 9a stall was a channel that stopped
  answering, where the fix is invisible by design. *Check:* write a Pass
  that needs the event (a `Timeout!`, then the abandoned bit cleared and no
  "pool exhausted") and a rule that records "not exercised" when it never
  comes. Extends L-85. *From:* kernel #152, round 39, 2026-11-03.
- **L-441. "Stock does this on every chip" is checked by decoding the
  reference phone's recorded flags through stock's own selector.** On kernel
  #187, the 7 Pro's `0x70050107` against stock's SEQNUM-then-XORCSUM choice
  in Google's bcm4389 `dhd_msgbuf.c` (0x20000 clear, 0x40000 set) confirmed
  stock already uses XORCSUM there. *Check:* fetch the stock file on the
  board's branch, find the selector, and decode the recorded word bit by
  bit. Extends L-61 and L-113. *From:* kernel #187, round 39, 2026-11-03.
- **L-482. A run whose instrument may cause the failure it records is
  counted on its own, and a clean streak is re-computed when the next result
  lands.** #409 counted a no-wake from a run with a module writing the RTC
  that wakes every series; #395's "15 of 15, strong evidence" became 1 in
  16, about one time in seven at the old rate, with uptime differing between
  the good and bad boots. *Check:* for each rate, list the runs in it and
  what differed; count instrumented runs separately; compute the binomial
  tail against the baseline, and tabulate each run's conditions. Extends
  C-12, C-26 and L-345. *From:* #409 and #395, round 40, 2026-11-04.
- **L-483. A test-kernel release that names a local commit is checked
  through the blob, rebuilt from the stated recipe, and a NOT FOR MERGE test
  branch is diffed against the head.** #191's `g63aa17cc8b81` wasn't on
  GitHub, but `merge-tree` of "#187 on today's omamobile, then this PR" gave
  the exact blob reported; #189's test branch, fetched, differed from the
  head only by the named flag. *Check:* rebuild the recipe with
  `merge-tree`/`commit-tree` and compare `rev-parse <tree>:<file>`; fetch a
  named test branch and `git diff <head> <test> -- <files>`. Extends L-131
  and L-436. *From:* kernel #191 and #189, round 40, 2026-11-04.
- **L-484. "A single touch does nothing on a dark screen" is checked in the
  compositor's input path.** Hyprland 0.57 sends every touch to the focused
  surface with DPMS off, and `misc:mouse_move_enables_dpms` only adds a
  wake, so #420's change made touches on a dark unlocked screen act blind on
  apps. *Check:* read `onTouchDown` and the touch listeners at the packaged
  tag, and list who consumes a touch on each surface (lock, app, shell
  layer). *From:* #420, round 40, 2026-11-04.
- **L-485. A decision quoted in AGENTS.md is checked against the comment
  itself: its date and every condition, the accepted ones included.** #441's
  first draft dated #409's decision a day early and listed only the
  maintainer's three conditions, not the contributor's that the decision
  accepted, one of which ("slot B marked") clashed with AGENTS. *Check:*
  quote from the thread, and reconcile each accepted condition with AGENTS
  before writing it in. *From:* #441, round 41, 2026-11-05.
- **L-524. A package claim about installed phones, or a way back we suggest,
  is simulated per image against the live repository order.** Our #433 reply
  said installed phones keep aquamarine 0.16, but pre-11-03 images have
  0.15.1, and [omarchy]'s 0.15.1-1.3 wins by repo order; round 41's `pacman
  -Syuu` way back from 4.5 stops on `libaquamarine.so=15`. *Check:* fake-root
  `pacman -Sup`/`-Suup` per supported image with today's databases in the
  phone's order. Extends L-433, L-46 and L-31. *From:* issues #433 and #434,
  round 42, 2026-11-07.
- **L-525. A negative control that fails only through `failOnWarning` proves a
  warning, not a failure.** #466's control passes all eight cases on main with
  the switch off. *Check:* rerun on main without it and read which assertions
  fail; if none, the change is log hygiene. Extends L-454. *From:* #466, round
  42, 2026-11-07.
- **L-526. An IPC reply quoted as an acknowledgment is checked against when
  the handler returns it.** #468 called `notifications forget`'s `ok` a
  deletion acknowledgment; patch 0019 returns it right after enqueuing the
  `rm`. *Check:* read where the return is set relative to the side effect.
  Extends L-29. *From:* #468, round 42, 2026-11-07.
- **L-527. A devinfo row whose retry byte disagrees with `getvar` for "the
  same state" is a disagreement, not evidence.** #436's 3.11 bytes gave retry
  0 beside `slot-retry-count:b 1`. *Check:* decode each new row with the
  verified layout beside the verified table, and ask when each read was taken.
  Extends L-36. *From:* #436, round 42, 2026-11-07.
- **L-528. A comment copied from a sibling board is checked against the PR's
  own results.** Akita measured the disks attaching before PID 1, while kernel
  #206's DTS comment, copied from husky, says the guard runs first. *Check:*
  grep each copied claim against the results section. Extends L-187 and L-313.
  *From:* #456 with kernel #206, round 42, 2026-11-07.
- **L-529. A matrix number is checked for whether it was measured or
  configured.** #472's "1.485 A" was the DT charge cap and "3 A" the source's
  advertisement; the cited comment measured +0.33 to +0.52 A and +1.50 A.
  *Check:* look for "cap", "limit", "advertis" or a DT property next to the
  value. Extends L-397 and L-438. *From:* #472, round 42, 2026-11-07.
- **L-530. A result that needs the Arch session can't come from a command line
  that stays in the initramfs.** #445 filed firstboot, ufw and compositor
  results under a RAM-only boot whose `CMDLINE` has `omamobile.initramfs`.
  *Check:* for each result needing `switch_root`, match it to the named
  command line and slot history. Extends L-28 and L-109. *From:* #445, round
  42, 2026-11-07.
- **L-558. A port of a patch series is diffed header by header against the
  series it ports, not only applied.** #471's 4.5 family applied with fuzz 0
  and passed every test, yet eight of its 26 headers had lost their
  explanation and their spaces ("to4.5auth", "privatepixel.lock"), one of them
  carrying the private-lock reference we had asked about twice elsewhere in
  the same PR; two of our reviews checked application and blobs and missed it.
  *Check:* per patch, compare the header line counts of the two families (`awk
  '/^(diff|--- )/{exit}'`), and grep the new headers for `[a-z]4\.[0-9]`,
  words over 18 letters, `private` and `coordinator`. Extends L-69 and L-183.
  *From:* #471, round 44, 2026-11-08.
- **L-559. A record written as "still X until the owner's next step" is
  checked against the owner's other threads since the push.** #488 said Lef's
  slot B "is still marked … until his next `flash`"; six hours later the same
  author reported a dozen flashes on #252 and #369, with retry counts that
  show B unmarked. *Check:* `gh api "repos/<r>/issues/comments?since=<head
  time>"` filtered to the author, before calling a present-tense state record
  ready. Extends L-266 and L-435. *From:* #488, round 44, 2026-11-08.
- **L-560. A follow-up PR that "documents the sources" is checked against each
  open question in the thread, not only the values.** #489 moved the existing
  "read-only `dd` from recovery" sentence into NOTES, which reads like an
  answer to the 11-03 question (RAM boot or flashed? anything mounted
  read-write?) but answers neither part. *Check:* list the maintainer's last
  questions on the parent PR and find each one's answer in the diff; a
  sentence that was already on main isn't an answer. Extends L-183. *From:*
  #489 with #231, round 44, 2026-11-08.
- **L-561. A feature whose DT node is in no PR doesn't get a matrix cell that
  names only the driver PR.** #494's cell gave kernel #213 "in review" as the
  missing piece, but the lens node sat in a notes code block waiting on #164,
  so with both merged no buildable kernel had autofocus. *Check:* for every
  "in review" a cell cites, list the DT nodes the feature needs and `git grep`
  them on the base and the open heads; a node in neither is named in the cell.
  Extends L-149 and L-28. *From:* #494, round 44, 2026-11-08.
- **L-593. A negative record that drops earlier positive facts is diffed
  against the contributor's earlier versions.** Asked to "record what
  happened", #330 rewrote a section as "not established", dropping a verified
  15-partition compare and the NV `ro=1` observations its first version had.
  *Check:* `git show <first version>:device/<x>/STATE.md` (or the old NOTES)
  for every fact the new paragraph calls unknown, and hand back the ones they
  already had (here the `backup-stock` list answered "is `logdump` backed
  up"). Extends L-198 and L-313. *From:* #330, round 45, 2026-11-08.
- **L-594. A PR description's "retaining … sign-offs" is checked per commit.**
  Kernel #219 and #220 both claimed it, and neither held. *Check:* `git log
  --format='%an%n%(trailers:key=Signed-off-by)'` over the PR's commits against
  the upstream originals. Extends L-29 and L-216. *From:* kernel #219 and
  #220, round 45, 2026-11-08.
- **L-595. A fix for a host-side prompt is tested on that host.** #510 was
  tested from a Linux laptop for a macOS "Allow accessories" prompt, and it
  keeps the random first enumeration the prompt may key on. *Check:* ask for a
  run on the reporter's OS with the reporter's setting, or reword the claim to
  what was measured. Extends L-29. *From:* #510, round 45, 2026-11-08.
- **L-596. "Stock" line numbers are checked against Google's file at the
  branch named.** #514 cited `modem_ctrl_s5100.c:874-903` and `:990-991` from
  a third-party copy of the shusky tree; Google's
  `android-gs-shusky-6.1-android16` file has those functions at 906-933 and
  1022-1027. *Check:* fetch the file from android.googlesource.com
  (`?format=TEXT | base64 -d`), grep the function names, and give the
  contributor the right lines. Extends L-76 and L-412. *From:* #514, round 45,
  2026-11-08.
- **L-597. A comment that says "the test fails if X" is checked against where
  X would actually appear.** #493's `allow = a` guard tests our own include
  file, while the hazard is a line after the include in Waydroid's generated
  config, which only `verify` sees at start. *Check:* for each hazard a
  comment names, find the file it would be in and the gate that reads that
  file. Extends L-540. *From:* #493, round 45, 2026-11-08.
- **L-647. A flag file for an app from `[omarchy]` is checked against that
  app's launcher in the signed package.** #542's whole fix rests on
  `/usr/bin/grok-bot` reading `~/.config/grok-bot-flags.conf`, and on the
  app's 512 px minimum. *Check:* `pacman -Sp <pkg>` for the URL, download the
  package and its `.sig` into an empty scratch directory, `gpgv --keyring
  /etc/pacman.d/gnupg/pubring.gpg <pkg>.sig <pkg>` (name both files: a glob
  like `*.pkg.tar.*` matches the `.sig` too and reports a BAD signature), then
  read the launcher and grep the `app.asar` for the claimed constant. Extends
  L-498 and C-32. *From:* #542, round 46, 2026-11-09.
- **L-648. A thread reply posted next to a notes commit is compared with the
  commit, fact by fact, in UTC.** #330's 11-09 entry (08:52Z) said "not
  compared, not complete, no reply"; the replies at 08:53Z said "matches,
  complete, reachable", and the record that would land was the older one.
  *Check:* `git log -1 --format=%cI` on the notes commit against each reply's
  `createdAt`, then list every fact the reply adds and ask for it in the file.
  Extends L-109 and L-591. *From:* #330 with #499 and #505, round 46,
  2026-11-09.
- **L-649. A tool's documentation isn't a record of a run, and a console that
  ends at the confirm prompt doesn't show the write.** Kodiak's "both slots"
  came from the installer's online description, through the contributor's
  assistant; the correction's evidence then ended at "Flash these images? …
  ^C". *Check:* for any "the installer wrote X" or "didn't write Y", ask for
  the run's own write lines (`install.log`, the `fastboot flash` output), and
  read a pasted console to its last step before accepting it as evidence of a
  write. Extends L-29 and L-562. *From:* #511, round 46, 2026-11-09.
- **L-650. A phone run in an app's preview or demo mode is checked for what
  the mode skips.** #526's `--preview` replaces the device reads with
  fictional data and skips the D-Bus registration, so the phone screenshot and
  smoke report covered neither the real About page nor the single-instance
  path, and the contributor's private app owned the same bus name. *Check:*
  `grep -n 'preview\|demo' main.*` for every branch the flag skips, and ask
  for the run on a phone where no other owner of the app's bus name or files
  is installed. Extends L-361 and L-567. *From:* #526, round 46, 2026-11-09.
- **L-651. A shell page with a pluggable backend is tested on the backend the
  repository ships, not only on a private one.** #539 ran on the 9a against an
  off-tree hostapd backend; NetworkManager, what every other phone gets, ran
  only against a fake `nmcli`. *Check:* `git grep` the hook path
  (`hotspot-backend`) on main and the open heads; if no shipped backend
  implements it, ask for a phone run of the default path and a README line on
  where a device's backend comes from. Extends L-61 and L-567. *From:* #539,
  round 46, 2026-11-09.
- **L-652. "Stopped after X" in a report about an upstream script is checked
  against that script's order at the version the phone runs.** #548's body
  and #549's known issue said `omarchy update` "stops after updating" in
  `omarchy-update-dev`, but Omarchy 4.0.6's `omarchy-update` calls
  `omarchy-update-dev` before `omarchy-update-system-pkgs`, so nothing was
  installed, and that decides what the user is told. *Check:* extract the
  pinned package
  (`~/.cache/omamobile-rootfs/pkg/omarchy-<ver>-aarch64.pkg.tar.zst`, reading
  its own `usr/bin` per L-498), then `grep -n` the failing step's
  position in the caller. Extends L-29 and L-499. *From:* #548 with #549,
  round 46, 2026-11-09.
- **L-653. Release notes started from the previous release's are grepped for
  that release's version and for every sentence that rested on its
  evidence.** #549's Installing section kept `omamobile-cheetah-2026.11.03.tar`
  and its URL, and the Updates line kept "the release was tested with a
  kernel update" from a run of the previous kernel; `tools/release tag` checks
  only the kernel tag and `uname -r`. *Check:* `grep -n '<previous version>'
  docs/release-notes/<new>.md`, `diff` the new notes against the previous
  ones, and for each unchanged claim find the dated NOTES entry for this
  release (or reword it to the date it was shown); the tag stage could refuse
  any other `YYYY.MM.DD` outside a "previous release" line. Extends L-433 and
  L-435. *From:* #549, round 46, 2026-11-09.
- **L-654. A "fixed" line in release notes is checked against the open issue
  and the notes' own known issues.** #549 said a flat battery "recovers by
  itself on most boots" while #169 was open, NOTES said the retry "waits for
  the next real flat battery", and the same notes' known issue told people to
  recover in fastboot. *Check:* for each "new" item that cites an issue, `gh
  issue view N --json state`, and grep NOTES for "not yet", "waits for" and
  "untested" next to the fix. Extends L-29 and L-435. *From:* #549, round 46,
  2026-11-09.
- **L-655. "A kernel update through the hook" is checked against which images
  the hook wrote.** On cheetah the kernel is in `boot` and the DTB and
  initramfs in `vendor_kernel_boot`; #560's record shows `boot_b` "already
  there" and only `vendor_kernel_boot_b` written, with one `linux-omamobile`
  in the release repository, so the "kernel update" was a rewrite of the same
  kernel. *Check:* for a hook or `push` claim, read the per-image "written" and
  "already there" lines and the package versions before and after; a changed
  kernel writes `boot_b`. Extends L-435. *From:* #549 with #560, round 46,
  2026-11-09.
- **L-656. A record of a hook or `push` write that names only some images is
  a reproducibility question.** With the same packages,
  `omamobile-boot-update`'s hook should find all five images "already there"
  on a fresh bundle install (RELEASES §11.4); #560's hook rewrote
  `vendor_kernel_boot_b` alone. *Check:* when a record shows a partial write
  on a fresh release install, ask for the package transaction and for which
  part of the image differs, and compare the hook's saved previous set with
  the bundle's image. Extends L-425. *From:* #560, round 46, 2026-11-09.
- **L-657. A NOTES entry that records harm from a step also updates the older
  gotcha that prescribes that step.** NOTES 11-03 says root over SSH "needs
  `OMARCHY_PATH=…`", the step that let 59 migrations run as root on 11-09
  (#560). *Check:* `grep -n` the older entries for the command the new entry
  warns about. See L-623. *From:* #560, round 46, 2026-11-09.
