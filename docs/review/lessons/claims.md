<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Claims and evidence (part 1 of 3)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-775. A new modem request's payload is compared with the research notes
  and the sibling ports' plans before it is called "qualified".** #669 sends
  SET_MODEM_CONFIG 0 as "single modem", while MODEM-SIT-RESEARCH reads the
  byte as the stack count and raven's plan records stock sending 1. *Check:*
  `git grep -n '<request name>\|<id>' origin/main -- device/` for every SIT
  id a PR adds to the allow-list, and lay the PR's bytes next to each
  recorded value. Extends L-61 and L-544. *From:* #669, round 52, 2026-11-11.
- **L-774. A docs line that names another PR's or the kernel's state is
  checked against that state at merge time, in both directions, and main is
  grepped for a PR's number before it is closed.** #98's "not yet in a
  published kernel" went wrong once `kernel-2026.11.08` took the commit; #505
  calls kernel #220 "in review" though our order merges #220 first; DEVICES.md
  still says "in review (#25)". *Check:* `git -C <kernel> log <newest kernel-*
  tag> --oneline --grep '<subject>'` and
  `packages/linux-omamobile/prebuilt/SOURCE`; `git grep -n '#<N>\|pull/<N>'
  origin/main -- docs README.md device`. Extends L-28 and L-645. *From:* #98,
  #505, #25, round 52, 2026-11-11.
- **L-751. A notes PR that turns an open question into a result is diffed for the caveat it removes.** #650 replaced "larger than the glass, so no size goes into the board file yet" with "the board file carries it"; the removed half was the reason the value had been held, and it still applied. *Check:* `git diff origin/main <head> -- device/<x>/NOTES.md | grep '^-'`, and for every removed "so … not yet" sentence find the line that answers it. Extends L-339 and L-486. *From:* #650 with kernel #241, round 51, 2026-11-11.
- **L-750. A provenance clause added to a results sentence is read for which run the remaining numbers belong to.** #655 put "the report pasted on #453 is from a later boot" in front of "every required check ok, … hottest zone 54 C", which were the lost run's figures; the pasted report reads 51 C. *Check:* after any "this came from another run" edit, compare each number left in the sentence with the cited report. Extends L-648 and L-313. *From:* #655, round 51, 2026-11-11.
- **L-749. When a fix makes a silent path audible, every trigger of that path is listed, and a proof by a stand-in event names which trigger it used.** #389's crash notice had never reached a session, so nobody saw that the watcher takes the same branch on a clean stop; the contributor proved the fix with a stop, and the proof was the bug: "The modem crashed" on every deliberate stop. *Check:* read the condition that fires the notice and list the ordinary events that satisfy it (stop, reboot, suspend); ask for the marker that tells them apart. Extends L-564 and L-298. *From:* #389 with issue #532, round 51, 2026-11-11.
- **L-748. On a rebase-merged PR, test claims are read in the commit messages and compared with the description.** Kernel #242's description reported a hardware run that two of its commit messages said had not happened ("has not been exercised on hardware"); the description never lands, the messages do. *Check:* grep each commit body for "not exercised", "untested" and "tested", set it against the description's test section, and ask for one account with the kernel release. Extends L-341 and L-29. *From:* kernel #242, round 51, 2026-11-11.
- **L-747. An A/B run on local plugin copies is void unless the shell was restarted between the sides.** The shell's local-plugin reload keeps the component it compiled first (AGENTS "Quickshell plugins"), so #658's first measurements compared a switcher with itself; the author withdrew them. *Check:* for every on-phone comparison of two plugin versions, look for `omarchy-restart-shell` before each run in the description, and ask when it's missing. Extends L-392. *From:* #658, round 51, 2026-11-11.
- **L-746. A no-wake reported from the laptop side is not a data point until that boot's journal shows what started the sleep.** From the laptop, a sleep with no alarm and a hang look the same: on kernel #224 a silent USB link at the 94th sleep was reported as the hang and corrected eight hours later, when the journal showed `omamobile-sleepd` putting a dark resume back to sleep with no alarm armed. *Check:* ask for the boot's last `PM: suspend entry` with the requester's line before it, whether auto-sleep was on and whether a block inhibitor was held between cycles; hold the count until then. Extends L-345. *From:* kernel #224 with #659, round 51, 2026-11-11.
- **L-724. A contributor's test table is read with its screenshots, and each
  row for whether its fixture could show the failure.** #553's "hardware test"
  was simulated touch (uinput), said only in the images; "drag from the last
  network scrolls" ran with three networks, where nothing scrolls; and its two
  fails started on the home pill, outside the surface under test. *Check:*
  open one image per kind of scenario, name the state that would make the bug
  visible and whether the picture shows it, and find which surface owns the
  touched pixels before blaming the PR. Extends L-29 and L-454. *From:* #553,
  round 50.
- **L-723. Before a long-running plan PR merges, its "what is left" list is
  read against today's merges and the author's other threads, though no round
  diff touches it.** #409's list still said a hook "waits for its merge" (#591
  had merged that day) and that sleep with the modem up was "never run with
  the fixes", while the author's #601 recorded 25 such requests. *Check:* `gh
  pr view` each PR an item names, and search the author's open PRs and issues
  for each item's subject. Extends L-559 and L-435. *From:* #409 with #601,
  round 50.
- **L-693. A restored record of a protected write is checked against what the
  named tool could have done.** #436's notes say device-lynx 0.2.0's
  `omamobile-bootctl` changed byte `0x35` on a 3.11 unit; 0.2.0 refuses 3.11,
  and the bytes quoted are the test fixture's. *Check:* `git show <that
  version>:<tool>` for the guard, and compare the quoted bytes with the unit's
  other readings and with the test fixtures. Extends L-267, L-285 and L-488.
  *From:* #436, round 49, 2026-11-10.
- **L-692. An agent or cloud-client integration is reviewed from the process
  it starts, and a run against an inert stand-in doesn't verify it against the
  client.** For #614 the answers came from the bridge's imports (no network
  module), the exact argv and where the binary is found, and the flags that
  set sandbox and approval; its 55 test cases used a stand-in that accepts any
  argv. *Check:* `grep -n 'Popen\|subprocess.run\|execDetached'`, write down
  argv, cwd and env, confirm nothing lands in `depends`, `ROOTFS_PACKAGES` or
  an installer, and ask for one recorded run with the real binary and its
  version. Extends L-454 and L-651. *From:* #614, round 49, 2026-11-10.
- **L-691. A discharge record for a low-battery fix gives the cell voltage at
  0 % and the consumer's reaction, not only the percentage curve.** Kernel
  #234's default-model gauge read 10 % five minutes before 0 %, yet reached
  0 % at 3.2 V with the phone running, so a percentage-keyed shutdown still
  comes in time; but the run was plugged in a minute later and nothing shows
  UPower acting. *Check:* ask for `voltage_now` and the load at the last
  non-zero sample and at 0 %, and the consumer's log line there (journal,
  `upower -d`). Extends L-629 and L-414. *From:* kernel #234, round 49,
  2026-11-10.
- **L-344. A console quoted as "just before" a failure is checked against
  that console's own timestamps.** The 9a's owner cited ACPM channel timeouts as
  preceding the 9a's UFS resume failure in #152; that console has no ACPM
  timeout at all, and the 25 s before its failing suspend hold only PAM and
  audit lines. The timeouts were from a different boot of the same day.
  *Check:* grep the file you are citing for the line, and compare the
  bracketed uptimes, before writing "before" or "then" in a PR. *From:*
  kernel #152, written and corrected the same night.
- **L-345. "The Nth of a series failed" is counted from the console, not
  from the session you remember.** The 9a's UFS failure was called a late
  sleep in a long boot; the console shows nine suspend entries and the
  third one failing, which retired the sleep-count theory the record had
  just acquired. *Check:* count the `PM: suspend entry` lines before the
  failure. *From:* #166, 2026-10-31.
- **L-346. A flaky check is read for what it asserts before it is blamed on
  the machine.** `test/owl-idle`'s paused-tick check failed on four PRs that
  don't touch the home plugin, and under parallel load locally, which looked
  like a slow runner. `tickDelay()` returns the time to the next boundary,
  so the assertion is false for one second in every ten by construction,
  and the CI message's own figure (554 ms) placed the clock 9451 ms into a
  10000 ms period. *Check:* work the printed value back through the function
  before calling a check timing-sensitive; 30 local runs that pass prove
  nothing against a 10 % window. *From:* #207.
- **L-347. "A shared static means the instances collide" is checked against
  how its index is assigned.** `eint_wake_mask_values[]` in
  `pinctrl-exynos.c` is file-scope and written by three wake-capable
  controllers on the 9a, which reads like a collision; `eint_num` is also
  file-scope and never reset, so the numbering is continuous and the shared
  array is the point. *Check:* find where the index comes from before
  reporting the sharing. *From:* the 9a's sleep hang, 2026-10-30, a
  candidate dropped before it reached a PR.
- **L-343. A `-dirty` release that stays the same across a fix doesn't
  identify the tested build.** The 9a's NFC runs without the fix (10-28) and
  with it (10-29) report the same `…-dirty` release, and #137 quoted that
  release as evidence for the fix. *Check:* when two results that should
  differ report the same release, ask for the tested file's blob id (`git
  hash-object` in the dirty tree) and compare it with the head's. Extends L-65
  and L-202. *From:* kernel #131 with #137, round 29.
- **L-342. An "each call wakes X" claim is checked against the call rate in
  the PR's own numbers and against the handler.** #148 said every CP status
  request wakes the 9a's PCIe link, yet at 12 requests a minute on a held fd
  the link came up 5-6 times, and our CPIF's `IOCTL_GET_CP_STATUS` only reads
  `mc->phone_state`. The per-poll wake most likely came from the open and
  close the PR also removed, so the interval change (which alters cheetah's
  crash timing) may be unnecessary. *Check:* divide the reported side effects
  by the calls after the change, read the ioctl, open and release handlers in
  the tree the phone runs, and ask for a one-variable A/B before a shared
  default moves. Extends L-29 and C-12. *From:* #148, round 29.
- **L-341. A "Tested" paragraph in an intermediate commit of a stack is
  checked against what exists at that commit.** Kernel #134's LDO25M commit
  reports the touch controller as the rail's only user, but `pmic-1` is still
  disabled and there is no touch node until two commits later; a bisect reader
  would take it as a test of that commit. *Check:* for each stacked DT commit,
  confirm the nodes its test names are present and enabled there (`git show
  <c>:<file> | grep`), and ask for "tested with X on top" where they aren't.
  Extends L-123 and L-251. *From:* kernel #134, round 29.
- **L-317. A host capability whose stated user is a sibling PR is checked
  against that sibling's diff.** Kernel #125 says LHBM needs DCS reads; #126,
  the LHBM PR, issues none. *Check:* grep the sibling's head for the new API's
  callers (`mipi_dsi_dcs_read`, `_generic_read`, `rx_len`) before accepting
  the motivation. Extends L-201 and L-219. *From:* kernel #125 with #126,
  round 28.
- **L-316. An `FF=` line in a haptics report is decoded before it's
  accepted.** With memless force feedback, FF_RUMBLE alone shows as `107030000
  0` on arm64, because the memless layer adds the periodic, waveform and gain
  bits; any other value means the driver changed its capabilities. *From:*
  kernel #96, round 28.
- **L-315. A boot report is read against the DTB's bootargs for blacklists and
  masks of the drivers under test.** #96's test overlay blacklisted `gs_decon`
  and `panthor` and masked the display and GPU units, so those rows couldn't
  pass the way they will for users. *Check:* diff the booted command line
  against the head DTB's `/chosen/bootargs` (decompiled with the build's own
  dtc) for `modprobe.blacklist`, `systemd.mask` and `systemd.unit`, and ask
  for the default path. Extends L-276. *From:* kernel #96, round 28.
- **L-314. "The driver isn't in this stack" is checked against the base the
  stack sits on.** #96's boot report blamed missing #84 and #89, which had
  merged before the rebase; a build that reuses another tree's config through
  `olddefconfig` leaves a new symbol with no default off. *Check:* `git
  merge-base --is-ancestor <driver commit> <head>`, the symbol's `default` in
  Kconfig, and `/proc/config.gz` and `lsmod` from the boot. A gap in our own
  build goes in `device/<codename>/kernel.config`, not the shared fragment
  (tegu's arrives with #74). Extends L-182 and L-61. *From:* kernel #96, round
  28.
- **L-313. A rewrite that answers "what did that boot run?" is re-read for
  every sentence that pointed back at the old text.** #125's answer replaced
  the 10-26 kernel line, which left the 10-28 paragraph's "the same kernel"
  pointing at Google's kernel on the day that carries the rule. *Check:* `git
  diff <old head> <new head>` on the record, and for each removed noun (a
  release, a tool, an image) grep the rest of the section for "the same",
  "that kernel" and "it". *From:* #125, round 27.
- **L-290. A "stop the radio" change is verified at the controller, not only
  through the daemon's property.** On the 9a, neard's `Polling` and the kernel
  disagreed after a neard restart (EBUSY). *Check:* compare the controller's
  `/proc/interrupts` total across main's code and the PR's with the screen
  dark (a one-variable A/B), and record `nfctool -l`; where the chip doesn't
  interrupt while idle, a tag tap is the functional proof. Extends L-85 and
  C-12. *From:* #99, round 26.
- **L-286. A cause attributed to stock is checked against what the failing
  boot itself ran.** #125's 10-26 loss came after a "Google-kernel" boot on
  slot B that no notes describe; stock's own ramdisk on B could explain the
  overwrite as well as stock on A. *Check:* ask for the failing boot's kernel,
  its ramdisk and whether the storage guard was present before accepting
  "stock on slot A did it". Extends L-186 and C-12. *From:* #125, round 26.
- **L-283. A board merged without the boot argument we suggested moves the
  guard into the device package.** The merged `gs201-panther.dts` has no
  `mem_sleep_default=s2idle`, so panther's `sleep.conf.d` drop-in, an
  "optional, later" request on #79, is now its only guard against `deep`.
  *Check:* after a board PR merges, re-read its bootargs against L-207 and
  update the device PR's request. Extends L-219. *From:* #79 with kernel #108,
  round 26.
- **L-276. Evidence we ask for must exist in the tool we name.** Our #80
  comment asked for `tools/phone-smoke`'s haptics section; phone-smoke never
  vibrates or lights the torch and has none. *Check:* `grep -n -i
  '<subsystem>' tools/phone-smoke`; where it has no section, name a read-only
  check (probe lines, input or LED class entries). Extends L-31; see C-17.
  *From:* kernel #80 and #96, round 25.
- **L-272. A device's notes are checked against what our DT calls a block.**
  lynx's NOTES and WIFI-PLAN called `0x10840000` "PERIC1, not described", but
  `gs201.dtsi` has `pinctrl_peric0` there with `gpp16`. *Check:* `git grep
  '@<addr>'` and the bank label in `<soc>-pinctrl.dtsi` for any controller a
  plan names. *From:* #98, round 25.
- **L-266. A plan PR merged mid-thread is checked afterwards for the results
  that came later.** #88 merged with lynx's WIFI-PLAN as of the 27th, so the
  `fs_ready` stall reported that night never reached it, and main still calls
  that boot "next". *Check:* for every thread result after the PR's last push,
  `git grep` its key strings on main's plan and ask for a follow-up PR for any
  that are missing. Extends L-34 and L-201. *From:* issue #36 with #88, round
  25.
- **L-260. A gotcha that changes recovery behaviour is checked against the
  author's other open PRs, not only main.** #125 said stock on slot A
  "reformats" `userdata`; the same author's #100 records that stock stops in
  recovery and only a chosen factory reset wipes it, which turns the rule from
  "mark the slot" into "never choose the reset". *Check:* `git grep -i` the
  claim's key words (recovery, reformat, wipe, fallback) over that author's
  open PR heads for the device. Extends L-188 and L-191. *From:* #125, round
  25.
- **L-256. An "inactive slot" install mode is walked for what a reinstall
  does.** With `OMAMOBILE_SLOT=inactive`, rerunning #111's installer on a
  phone already in Omarchy flashes the stock slot unless `--reflash` is
  remembered. *Check:* name the slot written from each starting state. Extends
  L-205. *From:* #111, round 24.
- **L-257. A fix that "covers every device package" is re-counted at review
  time.** #102 changed four copies of a file; lynx's package landed a fifth
  after it opened. *Check:* `git grep -l '<changed line>' origin/main --
  packages/` against the PR's file list. Extends L-164 and L-195. *From:*
  #102, issue #103, round 24.
- **L-258. A first-owner path is tested without the maintainer's private
  inputs.** `phone-provision` defaulted to the maintainer's backup, so the
  README quick start failed for every new owner. *Check:* `grep -n
  'android/reference' tools/<tool>` for every tool the README names; each
  such default needs a first-install path or a clear refusal. *From:* issue
  #106, round 24.
- **L-259. "Not in the published repository" is checked against the last
  publish before it's read as policy.** The husky package was missing
  because publishes had failed since its merge. *Check:* the publish tree's
  last commit, the index's date, and open "publish failed" issues. *From:*
  issue #1, round 24.
- **L-28. "Works" needs merged notes and the phone it ran on.** A matrix row
  claiming works/testing from a private kernel, or from an install of a
  different branch, should say WIP or testing and link the notes.
  *From:* #24, #25.
- **L-29. PR bodies written with an AI over-claim.** "checkpatch clean",
  "dtbs_check clean", "tested" were each untrue at least once this week.
  Re-run the claim; never quote it. *From:* kernel #10-#12, #27.
- **L-45. A rebased companion's evidence still counts if the tested commit
  and the new head don't differ.** *Check:* `git diff <tested> <head> --
  <files the test exercised>`; empty means the test stands, otherwise ask
  for a re-test. *From:* #29, round 2 (994dd90 against d773f62: identical).
  **Also (kernel #222, round 46):** a message-only re-push (`git diff <old>
  <new>` empty, same parent) carries the evidence over only while the base's
  blob for each touched file is unchanged too (`git rev-parse <old base>:<f>
  <new base>:<f>`).
- **L-46. A phone's settings reflect that phone's image, not the one we
  build.** A contributor's `busctl` value (`HandlePowerKey=suspend`) came from
  a local drop-in, while our image's `omarchy-settings` sets `ignore`.
  *Check:* compare reported values with what `rootfs/packages.base`
  installs before accepting or correcting a note about a default (with
  L-32). *From:* #29, round 2.
- **L-61. "Private kernel" evidence isn't evidence.** Ask for the public
  source (Google's GPL tree, the stock DT lines, upstream) behind each value.
  *From:* kernel #28-#31.
- **L-62. Check a claimed upstream backport against that commit's own
  `.patch`,** and list the file's later commits to find where any extra
  lines came from; authorship and trailers must survive. *From:* #32
  (0005 was two upstream commits with no `From:` line).
- **L-65. A `-dirty` release means the tested code is in no commit.** Look
  up its hash (`git log -1 <sha>`); if it predates the PR's code, the notes
  must say the evidence came from an unpublished tree and name the
  differences the PR admits. Hardware facts stand; claims about the PR's
  code path don't (extends L-45). *From:* #34 with kernel #32.
- **L-66. A matrix cell's word needs the qualifier its neighbours use and a
  link to the notes entry.** "Touch: WIP" for a chip-id read reads as touch
  input. *From:* #34.
- **L-76. Fetch each `Link:` anchor and read the line it points at.**
  *Check:* `curl -s '<url>?format=TEXT' | base64 -d | sed -n Np`. #29's was
  two lines off: cosmetic there, but a wrong commit or file wouldn't be.
  *From:* kernel #29, round 2.
- **L-85. "Nothing else changed" needs a "before" from the same boot.** A
  stop condition such as "no other rail changed" with only an after-read of
  `regulator_summary` can't fail. *Check:* every "X didn't change" condition
  has a snapshot step before the action and a diff after. *From:* #34,
  round 2.
- **L-86. When a revised driver keeps the protocol but changes the power
  sequence, the earlier boot covers the protocol only.** Compare the trees
  (L-69): a changed probe or remove order (rails, reset) needs its own boot,
  even when the read path is identical. *From:* kernel #32, round 4.
- **L-106. One PR's hardware evidence can land in another PR's commits.**
  Husky test 23, the result #33 asked for, was in #23's BRINGUP-M1. *Check:*
  read the companion PRs before saying "no evidence yet". Extends L-34.
  *From:* kernel #33 with #23.
- **L-107. A plan's claim about the DEVICES.md matrix is checked against
  the open PRs that change that row.** Extends L-28 and L-44. *From:* #35
  with #34.
- **L-128. Read the host's USB log before interpreting a phone's
  "re-enumeration".** The laptop's `journalctl -k` timestamps the gadget
  leaving and arriving, and survives a phone whose RAM log is lost: husky
  test 23's "re-enumerated after 22 s" was the boot itself. *From:* kernel
  #33, round 10.
- **L-129. A CRC "clear" covers only what that register checks.** FTM5's
  CRC register is the base check; config and CX errors come as events after a
  reset. *Check:* which check covers the calibration area, and whether it
  needs a reset, before a plan says a read answers "is it valid". *From:*
  #35, round 10.
