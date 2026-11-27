<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Claims and evidence (part 1 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-1237. A descriptor set to `ram-only` turns "later writes go through the
  project's tools" into "no tool will write it", and the review says so.** On
  #993 the decision asked for project tools for every later `boot`/`userdata`
  write, while `bin/omamobile` refuses `initramfs-config`, `images`, `flash`
  and `push` for `BOOT_METHOD=ram-only` (lines 640, 691, 908, 1282, 1348).
  *Check:* for a device whose notes promise tool-only writes, `DEVICE=<x>
  bin/omamobile initramfs-config <scratch>` and grep `bin/omamobile` for the
  method's refusals; name the descriptor change that turns the tools on and
  what the owner uses until then. Extends L-1029 and L-82. *From:* #993, round
  69.
- **L-1228. A soname-rebuild PR is checked against the issue tracker and every
  channel the old build is on, not only the channel the description names.**
  #1124 missed #1098, which showed stable phones blocked; merging feeds
  development only. *Check:* `gh issue list --search '<library>'`, then
  `bsdtar -tf` each channel's `omamobile.db` for the old version. *From:*
  #1124, 2026-11-27.
- **L-1227. A fix that seeds an upstream tool's state file is checked by
  running the upstream tool on every content the seed leaves alone, not only
  on the content it writes.** #1045 seeds Omarchy's per-source profile file
  only when it is empty, and Omarchy's `omarchy-powerprofiles-set` falls back
  to Performance on AC for any value that isn't a profile name, so a non-empty
  but unusable file keeps the behaviour the seed exists to prevent. *Check:*
  extract the upstream script from the signed package, run it under `env -i`
  with stand-ins for each file state (missing, empty, the seeded value, a
  stale or malformed value, the owner's choice) and tabulate what it picks;
  ask the seed to test for the values the reader accepts. Extends L-1184 and
  L-716. *From:* #1045, round 69.
- **L-1226. A check that a kernel "has fix X" by finding X's function or log
  text in a module is checked against the match data that decides whether the
  code runs on the target SoC.** #912's 9a relied on
  `omamobile-modem-sleep-policy`, which greps `pcie_gs201_cp.ko` for #232's
  notifier; the text is compiled in for every SoC, but zumapro's `sleep_guard`
  came a day later with kernel #258, so `kernel-2026.11.15` passes the test on
  a 9a with no early refusal registered. *Check:* for a userspace "does the
  kernel have it" test, find the code's gate (`git grep -n '<function>'
  <driver>` and the `if` around its registration), list each SoC's match data
  at each release tag (`git show <tag>:<file> | grep -n '<flag> ='`), and ask
  what the test says on the tag between the two commits. Extends L-1006 and
  L-1129. *From:* #912, round 69, 2026-11-26.
- **L-1225. A "the package checks the running kernel" answer is read for which
  commit the check really proves, when the fix is several commits.** #997's
  regmap `access` probe proves the write-table commit of kernel #262 and not
  the power-off commit that is the actual fix; it holds only because both
  always land together. *Check:* for each proposed probe, name the one commit
  whose presence it shows (`git log -S'<the probed text>'`), list the fix's
  commits, and write in the review when a kernel could have one without the
  other (a cherry-pick, a revert). Extends L-1129 and L-1006. *From:* #997,
  round 69, 2026-11-26.
- **L-1224. A smoke report attached to one PR is read for failures that belong
  to main, and they are named apart from the PR's verdict.** #887's report
  from the 9a showed `omamobile-bt-addr@hci0:11.service` failed, the
  per-connection device that L-469 (round 40) described, and every device
  package on main still carries the same `KERNEL=="hci[0-9]*"` rule. *Check:*
  for each failed unit in a report's "systemd units" row, `git grep -n '<unit
  name>' origin/main -- packages` and ask whether the PR could cause it; if
  not, put it on the maintainer's list with the lesson that already explains
  it. Extends L-469 and L-433. *From:* #887, round 69.
- **L-1223. A smoke report from a boot that skipped the descriptor's overlays
  is evidence for the package, not for the overlays, and the review checks the
  running tree for them.** #914's 11-25 boot passed its required checks while
  the touchscreen node read `disabled` in `/proc/device-tree`, though the
  descriptor names `synaptics-touch-test`; its author noticed only afterwards.
  *Check:* for a report from a device whose descriptor has `DTB_OVERLAYS`, ask
  for one `status` read per overlay node from `/proc/device-tree` (read-only),
  and list the results that depend on each. Extends L-1062 and L-315. *From:*
  #914, round 69.
- **L-1222. A decision posted mid-session is laid against the record's boot
  times for the trials just after it, and a reply written minutes after a
  trial is read for whether it mentions that trial.** #1002's v71 booted 1 h
  40 min after the backup-freshness decision on the old copy, and the author's
  reply twelve minutes later spoke only of "the next session". *Check:* take
  the decision's `created_at`, list every trial row whose boot request is
  later (`grep -n 'requested at\|boot request' <plan>`), and check each row's
  backup column against the rule; read the next reply for each such trial.
  Extends L-1024 and L-1180. *From:* #1002, round 69.
- **L-1221. A contributor's thanks for evidence nobody posted is asked about
  before the change it motivated is reviewed.** #202's author fixed the DSC
  PPS "after that PPS comparison" and asked for "your userspace test"; no
  comment in either repository since the last review held such a comparison,
  so the "60 of 128 bytes" had no source. *Check:* `gh api
  "repos/<r>/issues/comments?since=<last review>"` in both repositories,
  grepped for the noun the thanks names; if absent, ask in the draft where it
  came from and put the answer in the commit message. Extends L-838 and L-61.
  *From:* kernel #202, round 69.
- **L-1180. When a reply lists trials that ran after a "before the next boot"
  request, the trial rows are asked for times, and the source commits' dates
  bound the window.** #1002's notes record v21 to v28 on the phone with no
  dates; v21's source commit is from 17:46Z the day before and the provenance
  commits from 05:05Z, so the boots fall on either side of our 01:11Z request
  and the record can't say which. *Check:* for each trial a reply adds, `gh
  api repos/<fork>/commits/<sha> --jq .commit.author.date` for its source
  commit, lay those beside our comment's `submitted_at` in UTC, and ask for
  the boot times when the window straddles it. Extends L-1024 and L-557.
  *From:* #1002, round 67, 2026-11-24.
- **L-1179. A table assembled from several threads is checked cell by cell
  against the comment each row links, and a figure found only in another
  thread gets that link.** #1029's 9a row carried a night-before mean that is
  in kernel #280's description and not in the #867 comment its Source cell
  names. *Check:* for each row, fetch the linked comment (`gh api
  repos/<r>/issues/comments/<id>`) and grep it for every number in the row;
  for each miss, search the author's other threads (`gh api
  repos/<r>/pulls/<n> --jq .body`) and ask for the second link. Extends L-438
  and L-1023. *From:* #1029, round 67, 2026-11-24.
- **L-1178. A generated overlay that "carries what stock writes" rather than
  the source file's values is checked against the stock driver's types, not
  only its arithmetic.** #1023's nMiscCfg differs from Google's battery file
  because Google's driver ORs `fus << 12` into a `u16`; reading
  `max77779_fg.h` for the field's type is what showed that 0xf870 is the value
  the gauge really gets. *Check:* for each value a generator rewrites "as the
  driver does", fetch the driver function and the struct field it lands in on
  the same branch (`?format=TEXT | base64 -d`), and compute the stored value
  with the field's width. Extends L-985 and L-441. *From:* #1023, round 67,
  2026-11-24.
- **L-1159. A plan finding written the same day as the fix that answers it is
  checked against main's log for that afternoon.** #711's §11.1 says the
  extraction tools sort with the locale's collation; #712 had made all four
  sorts `LC_ALL=C` and merged half an hour after the record was written, so
  the PR's own base already had the fix and the "open" item was closed.
  *Check:* for each open item in a draft's body or plan, `git log -S'<the
  fix's token>' <the record's date>..origin/main -- <the files it names>`, and
  `git grep` the PR's base for it. Extends L-971 and L-936. *From:* #711,
  round 66, 2026-11-23.
- **L-1158. A page over an existing radio feature waits on a run of the
  feature itself on the reference phone, before the page's own run.** #539's
  NetworkManager hotspot path had waited two weeks for its 7 Pro run while two
  other brcmfmac phones showed that the tile's AP mode doesn't start at all
  (#523), and nothing on main records the 7 Pro's AP mode. *Check:* `git grep
  -n -i '<feature>' origin/main -- device/cheetah docs/DEVICES.md` for a
  recorded run of what the page drives; if there is none, the phone test's
  first step is main's own path, with a stop and a decision written for "it
  doesn't start". Extends L-651 and L-574. *From:* #539 with #523, round 66,
  2026-11-23.
- **L-1157. A GPU cell is read against the session's renderer environment, not
  the kernel driver.** #993's row said the PowerVR GPU "works" because
  `pvrsrvkm` binds, while its own `uwsm/env.d` file forced llvmpipe for every
  session. *Check:* `git grep -n
  'LIBGL_ALWAYS_SOFTWARE\|GALLIUM_DRIVER\|QT_QUICK_BACKEND' <head> --
  packages/omamobile-device-<x>` before accepting a GPU "works"; if the
  session falls back to software, the legend's word is "boots". Extends L-28
  and L-1015. *From:* #993, round 66, 2026-11-23.
- **L-1156. A draft titled "stage 0" is read by its commit subjects before its
  title, because a day of flashes can arrive as notes commits.** #1002 opened
  as read-only stock facts on a locked phone; 33 commits the next day recorded
  an unlock and about thirteen slot B flashes and boots, while the title,
  description and Wanted row stayed "stock facts". *Check:* `git log
  --format='%cI %s' origin/main..<head> | grep -i -E
  'flash|stag|boot|hardware|trial|unlock|verify'`; any hit turns a docs draft
  into a bring-up record, read against L-109 and CONTRIBUTING §3.2 and §3.3.
  Extends L-486 and L-922. *From:* #1002, round 66, 2026-11-23.
- **L-1155. A notes table of slot bytes is read across every boot it skips,
  not only the rows it shows.** #1011's two diagnostic rows were consistent
  with Fastboot, but the bytes just before the write (0x35 `04`, from `0c`)
  and the retry count Fastboot read afterwards could only come from an
  unrecorded step between them. *Check:* lay each recorded byte from every
  read (rows, preflight copies, "differed only at") in boot order, apply what
  each boot and Fastboot visit should change, and ask for every step a jump
  needs. Extends L-884 and L-1082. *From:* #1011, round 66, 2026-11-23.
- **L-1154. A record of "an image built from this branch" is read for its
  "plus" clauses before it counts as a boot of the branch.** #931's RAM boot
  carried the owner's local disk-encryption unlock in the init, needed because
  that phone's root is LUKS2, so the shared init that ran was not the PR's,
  and the merged descriptor can't boot that phone. *Check:* `grep -n -i
  'plus\|not part of\|local\|on top' <the record>` around each boot a PR
  cites, and name which shared files ran as written. Extends L-802, L-436 and
  L-361. *From:* #931, round 66, 2026-11-23.
- **L-1119. A notes entry that explains how two packages got onto a phone is
  read through the newer package's `depends=`.** #970 answered "which of the
  two came from where" exactly, and the locally installed device package's
  versioned dependency on `omamobile-audio` shows a third package had to move
  with it, from the phone's channel. *Check:* `git show
  <commit>:packages/<p>/PKGBUILD | grep depends` for the locally installed
  package, compare each versioned entry with the date of the image the entry
  names, and ask for `pacman -Q` of whatever must have come along. Extends
  L-1075 and L-358. *From:* #970, round 65, 2026-11-21.
- **L-1118. When a contributor's reply says "fixed, and here is a short run",
  the run's stop point is compared with the lines the fix changed.** #953's
  run of the new head ended before its second part, while the commit rewrote
  that part's sampling line; the description still offered the first commit's
  full run as the evidence. *Check:* for each on-phone run named in a reply,
  list which numbered steps of the tool it reached, and `git diff <old head>
  <new head>` for hunks in the steps it didn't; ask for the run that reaches
  them. Extends L-936 and L-109. *From:* #953, round 65, 2026-11-21.
- **L-1107. A hardware request written as a list is answered clause by clause
  from each record, with "seen" kept apart from "read back".** Kernel #218's
  description shows the panel lit once on an unidentified tree, and on the
  exact merge shows state values for brightness and blanking that nobody
  watched; laid in a table against the five things asked, the gap is two
  observations, not "a test". *Check:* split our own request at its commas,
  give each record a column, and mark each cell seen, read back or absent;
  then ask only for the absent cells, and say which later PR could carry them.
  Extends L-811, L-380 and L-724. *From:* kernel #218, round 64, 2026-11-21.
- **L-1106. Two reports "from the same running session" are compared field by
  field before the claim "no boot in between" is carried forward.** #714's two
  `phone-smoke` reports, two and a half hours apart, went from six `dmesg`
  error lines to none, and a third comment named the session differently; each
  said no boot was started. *Check:* diff the two reports' kernel-health,
  package and thermal rows; where a boot-time line disappears, ask for
  `/proc/sys/kernel/random/boot_id` and uptime with every later report from a
  phone under a hold, and ask that `tools/phone-smoke` print both in its
  header. Extends L-1086, L-1011 and L-557. *From:* #714, round 64,
  2026-11-21.
- **L-1105. A `g<hash>` in a contributor's kernel release that is on no branch
  can be GitHub's own test merge of an open PR.** #500's and kernel #218's
  records name one such hash; `gh api repos/<r>/commits/<hash>` answers "Merge
  <PR head> into <base>", which says the tested tree was exactly the published
  base plus that PR, and the file's blob id can be read from the same ref.
  *Check:* before calling a release's hash unpublished, ask the API for the
  commit in the upstream repository as well as the fork, and read its two
  parents. Extends L-202 and L-65. *From:* #500 with kernel #218, round 64,
  2026-11-21.
- **L-1090. A claim about a third-party type's behaviour across suspend is
  settled by reading its source at the packaged commit, timer by timer.** #924
  said Quickshell's `SystemClock` shows the old time for up to a minute after
  a wake; `clock.cpp` at the packaged commit has one `QTimer` armed for the
  time to the next tick and no re-read on resume, and `setEnabled(true)` reads
  the time at once, which is both the bug and the fix. *Check:* fetch the file
  at the commit in `pacman -Q`'s version, find every `timer.start` and what
  recomputes the time, and confirm the property the fix toggles exists there
  before accepting a stub that declares it. Extends L-737 and C-30. *From:*
  #924, round 63, 2026-11-20.
- **L-1086. A "did you reboot or restart?" answer is checked against a log
  line only the new code prints.** On #626 the contributor proved the copied
  files were loaded at boot, not by a restart of the modem stack, with one
  sitd PID for the whole boot and a log line that exists only in the branch.
  *Check:* when asking how hand-copied code came to run, ask for the daemon's
  PID and start time for that boot and one line the new code alone prints;
  then `git grep -n '<the line>' origin/main <head>`. Extends L-183 and L-564.
  *From:* #626, round 63, 2026-11-20.
- **L-1084. An offer to test a "clear a stray bit" fix on a phone whose bit is
  clear is weighed against what that boot can show.** On kernel #261 an 8 Pro
  owner offered a boot check; with a cached regmap the write is skipped when
  the bit is clear, the phone's package doesn't enable the path, and its
  charger limits are undecided, so the run would add risk and prove a log
  line. *Check:* before accepting a second phone's run of a conditional fix,
  name the condition on that phone (the register read), whether its package
  enables the path, and what open decision the run would step into; ask
  instead for the read from the triggering state. Extends L-612 and L-440.
  *From:* kernel #261, round 63, 2026-11-20.
- **L-1075. A notes entry's package list is checked against each version's
  merge date, even in a docs-only PR.** #928's entry pairs a shell from 11-09
  with a device package merged on the day of the test and calls the set
  "published packages"; the dates show they can't have come from one update.
  *Check:* `git log -S'<version>' origin/main -- packages/<p>/version` for
  each version an entry names, and compare the dates with the entry's own date
  and the nightly publish. Extends L-358 and L-436. *From:* #928, round 63,
  2026-11-20.
- **L-1074. A matrix cell a contributor rewrites in their own words is run
  through the site's `parseCell` regex, not only read.** #871's reworded cell
  (`WIP ([link](...)). Sentences ... [link](...).`) reads fine on GitHub, but
  the parser's bracket group is greedy to the cell's last `)`, so the final
  link lost its closing bracket; round 60 had checked only the form we
  suggested. *Check:* cut the changed cell out with `awk -F'|'`, run
  `devices.ts`'s regex on it in `node`, and read the detail string for a link
  without its `)`; a cell with text after the bracket must not end in a link.
  Extends L-197 and L-66. *From:* #871, round 63, 2026-11-20.
- **L-1051. A "later images have the fix" sentence written while a PR waits is
  checked against the releases cut since.** #633's plan line said images after
  2026.11.08 mask the unit; two releases shipped without it while the PR was
  open. *Check:* `git tag -l 'release-*'` and `ls docs/release-notes` against
  every release name a diff uses as a boundary. Extends L-774 and L-653.
  *From:* #633, round 63, 2026-11-20. (Extended 2026-11-25: the mirror case,
  kernel tags. #1028 wrote "not in any release tag yet" for its minimum kernel
  on 11-24, and `kernel-2026.11.24`, tagged that evening, carries half of it
  (#289). Run `git -C <kernel> tag --contains <commit> 'kernel-*'` for each PR
  a minimum-kernel line names, at every round the PR stays open. Extends
  L-774. *From:* #1028, round 68.)
- **L-1046. A comment or upgrade message that names another package's version
  or behaviour goes stale while the PR waits.** #440's "once omamobile-omarchy
  0.1.34 is installed: it writes the same line" described a plan for the 4.5
  port that landed differently (the port preserves the file and writes
  nothing). *Check:* `git grep -n '<package> [0-9]\+\.[0-9]'` in a PR's added
  lines, and read that package's file on main for the behaviour claimed.
  Extends L-463 and L-774. *From:* #440, round 63, 2026-11-20.
- **L-1043. When a contributor withdraws an earlier statement ("stock did
  boot" becomes "it did not"), the withdrawal is accepted on evidence the
  withdrawn event would have changed, and any capture the correction newly
  cites is asked into the record.** #203's correction rests on nine
  byte-identical partitions across the interval, which a stock boot can't
  leave, and on a capture the notes had never named. *Check:* list what the
  withdrawn event writes (stock: `efs`, `persist`, `modem_userdata`; a slot
  change: `devinfo`), find the before and after copies, and grep the old notes
  for each capture time the new text uses. Extends L-168, L-593 and L-592.
  *From:* #203, round 63, 2026-11-20.
- **L-1023. Evidence for a shared-package PR that is written into a sibling
  draft's notes lands only when the draft does.** #500's best record (the
  exact archive, kernel release, boot image hash) is in #714's `NOTES.md`;
  merged alone, #500 leaves main with the weaker entry and a thread comment.
  *Check:* for each run the PR's description cites, `git show <head>:<notes> |
  grep` its hash or date; if it is only in another open PR's head, ask for the
  section to move or say in the squash body where it is. Extends L-106 and
  L-201. *From:* #500 with #714, round 63, 2026-11-20.
- **L-1015. A matrix row whose features sit behind bring-up overlays is
  checked against the descriptor's `DTB_OVERLAYS`.** #931 claimed camera,
  torch, fingerprint and call audio "works" with an empty overlay list.
  *Check:* `grep DTB_OVERLAYS device/<x>/device.conf` beside `ls
  device/<x>/overlays`. Extends L-28 and L-438. *From:* #931, round 63,
  2026-11-20.
- **L-1011. A bring-up record that names a state for "the boot" is checked
  against every later sentence that needs another state.** #926's table ran
  with "the modem off for the boot", and its reset left "one unclean end
  counted", which needs the modem up. *Check:* list each state the record
  fixes per boot (modem, cable, charger, kernel) and grep the same section for
  consequences that contradict it; ask which boot each event was in. Extends
  L-313 and L-345. *From:* #926, round 63, 2026-11-20.
- **L-1009. Phone evidence gathered on another open PR's package with this
  PR's files copied over it fixes the merge order.** #921's runs were #864's
  0.2.11-1 plus its own files, the shared runner being #864's with #921's
  hunk. *Check:* grep the body for "copied over", "installed from #N" and
  "with this branch's files"; the tested combination is the one that may
  merge, in that order, or the head gets its own run. Extends L-646 and L-361.
  *From:* #921 with #864, round 63, 2026-11-20.
- **L-1006. A "verified on the published branch" default is checked against
  the newest release tag, because the declaration reaches every kernel.**
  #912's `auto-sleep-default` is installed unconditionally, while the fix it
  rests on (kernel #247) is in no `kernel-*` tag. *Check:* for each fix a
  default-on cites, `git -C <kernel> merge-base --is-ancestor <fix> $(git tag
  -l 'kernel-*' | tail -1)`; if it fails, the default waits for the tag or is
  gated on the kernel, and the README names the minimum kernel. Extends L-774
  and L-444. *From:* #912, round 63, 2026-11-20.
- **L-999. "Stock does this in its thermal HAL too" is checked in Google's
  public thermal configuration for the device, sensor by sensor.** #946 capped
  clocks at 60 C on the SoC zones; `device/google/shusky`'s
  `thermal/thermal_info_config_husky.json` throttles from `VIRTUAL-SKIN-*`
  sensors at 37 to 55 C and gives `BIG`, `MID`, `LITTLE` and `G3D` no
  threshold at all, so the claim held for "in userspace" and not for the
  sensor or the number. *Check:* fetch the file from the device's repository
  on android.googlesource.com (`?format=TEXT | base64 -d`; strip `//` comments
  before parsing), list each sensor's `HotThreshold` and `BindedCdevInfo`, and
  compare the PR's sensor and threshold with the one stock binds to the same
  cooling device. Extends L-61 and L-113. *From:* #946, round 63, 2026-11-20.
- **L-981. A phone run on a local build that combines several open PRs under
  a made-up version is credited per file, and the made-up version is a
  follow-up for that phone.** #866's run used "omamobile-settings 0.1.7"
  carrying #629, #630 and #892; its backend and unit are this PR's alone, so
  the results stand, but the page ran with another PR's runner, and pacman
  will not replace 0.1.7 with the published 0.1.4. *Check:* `git diff <tested
  commit> <head>` for the files the run exercised; list which shared files
  (the runner, `Main.qml`) came from other PRs; and tell the contributor how
  the phone gets back onto published packages. Extends L-358, L-361 and L-755.
  *From:* #866, round 63, 2026-11-20.
- **L-980. "Needs release N or later" for a tool with its own releases names
  the tool's version as well.** #843 ties three installers to release
  2026.11.15; a manifest format that fails closed means the app's published
  v0.1.0 can't install the next release format, and nothing in the sentence
  says so. *Check:* for each front end a docs line names, compare its newest
  tag's date with the commit that added the format it must read (`gh release
  view`, `git log -1 --format=%cI -- <manifest parser>`). Extends L-640.
  *From:* #843, round 62, 2026-11-18.
- **L-979. A docs PR on hold "until X ships" is reviewed against the plan for
  X, sentence by sentence, each round it stays open.** #843's table is true of
  today's releases and wrong in five places for the first running-slot
  release, the event it waits for; one row names, as the app's only supported
  phone, the phone the new installer will stop on. *Check:* for a held docs
  PR, find the plan of what it is held for (`git grep -l '<the feature>'
  origin/main -- docs/*PLAN.md`), list each added sentence with the plan
  section that keeps or breaks it, and say whether it merges now as interim
  text or is rewritten at the event. Extends L-774 and L-519. *From:* #843
  with ACTIVE-SLOT-PLAN, round 62, 2026-11-18.
- **L-945. A merge that waits for "X is in a published package" is checked
  against the published index, not against X's merge.** Kernel #259 waits for
  device-panther 0.1.17 to be published; #827 merged at 02:06Z, and 13 hours
  later the development index was still the one from the morning before, with
  0.1.16. *Check:* fetch `<channel>/aarch64/omamobile.db` into an empty
  scratch folder, `bsdtar -tf` it for the package, and read the
  `Last-Modified` header; say the date in the review. Extends L-259 and L-590.
  *From:* #788 with #827 and kernel #259, round 61, 2026-11-18.
- **L-943. A firmware map "following the DTS" is checked against
  `firmware-name` on the published branch and through the driver that builds
  the request.** #714's `extract-vendor-firmware -d dipper` staged into
  `qcom/sdm845/dipper/` while `github/omamobile` asks for
  `qcom/sdm845/Xiaomi/dipper/`, and the README repeated the tool's paths as
  the DTS's. On #917, btqca prefixes `qca/` to the DT's name and takes the
  rampatch from its own table unless a second name is given, so two files
  staged at the DT's literal path would never be opened; two more had no
  `firmware-name` at all. *Check:* `git grep -n firmware-name github/omamobile
  -- arch/arm64/boot/dts/<vendor>/<board>*` next to the tool's `MAP`, then
  read the driver's `snprintf`/`request_firmware` for that property and its
  default when the property is absent. Extends L-149, L-187 and L-242. *From:*
  #714, round 61; #917, round 63, 2026-11-20.
- **L-941. A draft kernel PR that says "nothing was built from this commit"
  is checked against the device's notes on omamobile's main, and a commit
  they pin is compared with the head by blob.** Kernel #249's body disclaims
  any test, while `device/dipper/NOTES.md` records two RAM boots of the same
  node and pins the PR at an older head; the dtsi blob was identical, so the
  evidence carries and the message can cite it. *Check:* `git grep -n
  '#<N>\|<file>' origin/main -- device/<codename>` in omamobile, then
  `git rev-parse <pinned>:<file> <head>:<file>`. Extends L-106, L-373 and
  L-131. *From:* kernel #249, round 61, 2026-11-18.
- **L-939. An Omarchy patch tested on a phone that has not yet updated is
  evidence for the legacy family, and a copy in `legacy-4.0.6/` is the sign.**
  #879's run was on Omarchy 4.0.6-1 six days after stable moved to 4.5; the
  4.5 patch that reaches release phones had not run anywhere. *Check:* read
  `pacman -Q omarchy` in the PR's evidence against `rootfs/packages.pinned`;
  any new file under `legacy-4.0.6/` is checked against AGENTS' rule for that
  directory, and the 4.5 copy gets its own run. Extends L-555 and L-361.
  *From:* #879, round 61, 2026-11-18.
- **L-929. A data file's licence is read at the commit the PKGBUILD pins, not
  on the default branch, and again when the pin moves.** #888's word list came
  from a repository whose README said CC-BY-SA-3.0 at the pinned 2019 commit
  and 4.0 from 2020; the PR cited 4.0. The pin then moved to the first commit
  that states 4.0, and the unchanged sha256 was the proof that only the
  provenance changed. *Check:* fetch the README or LICENSE and the file at
  `<pinned commit>` into an empty scratch folder, grep the licence sentence
  and compare the sum with the PKGBUILD's; when the cited licence appears only
  later and the bytes are equal, ask for a pin at a commit that states it.
  Extends L-221. *From:* #888, rounds 61 and 62, 2026-11-18.
- **L-928. A patch that rewrites an upstream file is grepped for removed
  copyright and author lines.** #888's patch 0005 replaced most of a GPL file
  and dropped its three notices while 238 lines of the original remained.
  *Check:* `grep -n '^-.*\(Copyright\|Author\|SPDX\|based on\)'
  patches/*.patch`; any hit is a request to keep the notice and add to it.
  Extends L-62 and L-221. *From:* #888, round 61, 2026-11-18.
