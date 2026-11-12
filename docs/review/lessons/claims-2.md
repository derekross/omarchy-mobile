<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Claims and evidence (part 2 of 3)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-192. "The builder's keys give root on every installation" is checked
  against the init and the installer.** The initramfs `authorized_keys`
  never reaches the Arch root (`install-phone` writes the owner's key
  there), and the initramfs console (`getty -n -l /bin/sh` on `ttyGS0`)
  already gives anyone with the cable root at that stage. #75's change is
  right for §5.2's reason; the review says what the exposure is so the
  squash body doesn't overstate it. *Check:* `grep -n 'authorized\|getty'
  initramfs/init tools/install-phone`. *From:* #75, round 20.
- **L-200. Check a cited commit range's member ids, not only its
  endpoints.** #52's base `6963e3800a8e` and "three commits past the tag"
  were right; the two intermediate ids it listed don't exist, and their
  subjects belong to commits before the tag. *Check:* the GitLab or GitHub
  compare API, `from=<tag>&to=<base>`, and compare each listed id. Extends
  L-76. *From:* #52, round 21.
- **L-201. "That's recorded in the other PR" is checked by grep on the other
  PR's head, and both PRs get the finding.** Kernel #72's reply said the
  DPP0 read and the `/proc/iomem` line were in #82's notes; #82's NOTES had
  the kernel release only, and the PR that would carry them was already
  "all done" in its own thread. *Check:* for every cross-PR "it's in #N",
  `git show <N's head>:<file> | grep` the named items before closing the
  request on either side. Extends L-106 and L-183. *From:* kernel #72 with
  #82, round 21.
- **L-202. A `-dirty` release's hash can be a PR commit that the base has
  since taken under a new id.** #82's `g485f83c27e5c` resolved to nothing on
  `github/omamobile`; a subject search found it as the kernel #48 series'
  commit, rebase-merged as `095e451d8660`. *Check:* `git log --all --oneline
  | grep <hash>` across the review refs, then `git log --grep=<subject>` on
  the base, before calling the tested tree unpublished. Extends L-65 and
  L-182. *From:* #82, round 20.
- **L-203. A "before X" register read on stock also says whether the domain
  was cold.** Issue #36's stock "pre-BHI" values came from a chip whose
  always-on domain had completed a PBL run since the buck came up
  (`TCSR_PBL_LOGGING` retained across the WLAN_EN cycle), and we had asked
  for "before the first BHI" without saying "cold". *Check:* when asking for
  a chip-state read, name the rail history (which supplies were dropped and
  for how long) and ask for the retained-state marker alongside. *From:*
  issue #36, round 21.
- **L-204. A contributor's reading of a vendor log is re-derived from the
  vendor driver's sequence before it becomes a premise.** "Stock's very
  first cold cycle already passes auth" on issue #36 stood for a day; cnss2's
  probe powers on, enumerates and powers off before the first BHI, and
  `wlan_buck_enable` logs `Enter` on every power-on, so the timing was most
  likely measured from the second cycle. *Check:* find the one-per-boot line
  (`BUCK GPIO: [0]` and `drive it HIGH`) and count the power-on lines before
  the event. Extends L-61 and L-190. *From:* issue #36, round 21 (C-8).
- **L-218. A filter that printed nothing doesn't show an address was
  unreserved.** `grep fac00000 /proc/iomem` can't match a range that only
  contains it. *Check:* the enclosing range (`awk` on the bounds), or another
  read; don't hold a PR to a capture that no longer exists. *From:* #82,
  round 22.
- **L-219. A promise made in one thread is checked in the PR meant to keep
  it.** On #59 the contributor promised `mem_sleep_default=s2idle` in the
  board bootargs; #80's don't have it. *Check:* before a device's first board
  PR, grep our earlier threads for that device ("when I post", "bootargs")
  and list each promise. Extends L-34 and L-183. *From:* kernel #80, round 22.
- **L-220. A table "from our capture of stock" is looked for in Google's
  per-device DT repos first.** #84's GPU table is Google's public
  `gpu_dvfs_table_v2` (tegu's `dts/zumapro` links to a dtsi that includes
  zuma's), citable by commit. *Check:* follow `dts/<soc>` links in
  `kernel/devices/google/<device>` and diff the capture against the public
  dtsi. Extends L-61 and L-177. *From:* kernel #84, round 22.
- **L-221. Cite the licence a vendor file states.** Google's panel drivers
  under `google-modules/display/panels` are SPDX MIT, not GPL. *From:* kernel
  #89, round 22.
- **L-222. "Driver X has no suspend handling" as a cause is checked against
  the reference phone's driver for the same role.** #72 blamed nxp-nci's
  missing PM ops, but st-nci on cheetah has none and suspends. *Check:* `git
  grep dev_pm_ops` across sibling drivers. *From:* #72, round 22.

- **L-358. A smoke report's package list is evidence about the tree.**
  Versions not on main, `*-<codename>` packages or a rebuilt keyring mean an
  unpublished stack (#200). *Check:* diff the list against
  `packages/*/version` and ask for the provenance before matrix cells cite
  it. *From:* #200, 2026-10-31.
- **L-359. "Owner-authorized" in a contributor's record means the
  contributor approved their own exception.** #200 recorded a flags-3
  `vbmeta_b` and a `devinfo` boot-success write as owner-authorized, never
  approved by the maintainer. *Check:* treat it as a CONTRIBUTING §3.1 event:
  ask what lifted the guard, for the before/after bytes, and say no further
  writes without the maintainer's go. *From:* #200, 2026-10-31.
- **L-360. A promised fix is checked against the head's commit times; named
  test tags are checked on the remote.** #153's ACPM fix was promised at
  13:00 with the last commit at 11:55; #157/#158 cite tags absent from the
  fork. *Check:* `git log -1 --format=%cI <head>` against the promise, and
  `git ls-remote --tags <fork>`. *From:* kernel #153, #157, #158,
  2026-10-31.
- **L-361. A file swap into an older installed package tests the files in
  that old context only.** #193's phone check swapped five files into shell
  0.2.12, 33 versions behind main. *Check:* for a shared package, ask for
  (or run) the head installed on the reference phone. *From:* #193,
  2026-10-31.
- **L-362. A gotcha that blames a stale per-user file is checked against the
  package's own per-login repair first.** #243 blamed stale plugin links, but
  `omamobile-setup-user.service` re-links them at every login; the fault was
  the service not running because its profile marker was missing. *Check:*
  `git grep` the package for a unit or script that rewrites the file, read its
  `Condition*=` lines and ask whether it ran. *From:* #243, 2026-11-01.
- **L-363. A new fact about what unmarks a boot slot is walked through the
  recovery path the same gotcha prescribes.** #224's "a plain fastboot flash
  unmarks B" turns the gotcha's own fastboot recovery into an unmark while
  marking is on hold. Extends L-284. *From:* #224, 2026-11-01.
- **L-364. Review ref names are unique per run, not per device.** Two
  parallel reviewers both used `review/prN-r1-tegu` and deleted each other's
  refs. *Check:* `git branch --list "review/*-<topic>"` is empty before the
  first fetch. Extends L-43 and L-127. *From:* the 2026-11-01 round.
- **L-365. A new device descriptor's `BRINGUP_PROBE` is checked against the
  SoC its addresses were written for.** #231 (kodiak) kept an initramfs probe
  that reads gs201 watchdog and DPP addresses on any board whose
  `COMPATIBLE` matches. Also, `DTBO_BOARD_ID` is never `dtbo_idx`. *From:*
  #231, 2026-11-01.
- **L-366. A stop added to a detached phone tool is checked for where its
  message goes.** `power-ab --detach` discards stderr, so #226's new stop
  explained itself to nobody. *Check:* ask for the reason in the output file.
  *From:* #226, 2026-11-01.
- **L-367. A userspace limit driven by a freezable poll stops during
  s2idle.** #230's charge limit follows max77779-battery change events from a
  30 s poll on `system_freezable_wq`. *Check:* the workqueue of the driver's
  `power_supply_changed()` callers. *From:* #230, 2026-11-01.
- **L-368. A config-fragment PR that grows by commits keeps its first
  title.** *Check:* compare the title and body with every commit (#227).
  Extends L-340 and L-356. *From:* #227, 2026-11-01.
- **L-369. Moving a mailbox or firmware-protocol option from module to
  built-in in the shared fragment is a cheetah change when cheetah's DT
  enables that driver's node** (#227: `acpm_ipc`). *Check:* `git grep` the
  compatible in `gs201*.dts*`. Extends L-8 and L-206. *From:* #227,
  2026-11-01.
- **L-370. A shared-fragment PR and a device `kernel.config` PR that set the
  same options are reconciled together** (#227 with #240). Extends L-337.
  *From:* #227, #240, 2026-11-01.
- **L-371. A clock floor taken from a file's mtime is checked against every
  step that writes that file.** #97 took it from the keyring's mtime.
  *Check:* grep `tools/` for `SOURCE_DATE_EPOCH` and `touch -d`. *From:* #97,
  2026-11-01.
- **L-372. A contributor's merge of main puts a "Merge remote-tracking
  branch" body into a COMMIT_MESSAGES squash** (#75). *Check:* `git log
  --merges base..head`, and write the squash body by hand. Extends L-312 and
  L-355. *From:* #75, 2026-11-01.
- **L-373. A notes entry that pins a tested kernel commit is range-diffed
  against the kernel PR's current head before the matrix cites it.** #216
  pinned `f47c5bd34`; kernel #156 was rebased after. *From:* #216,
  2026-11-01.
- **L-374. A per-SKU firmware map copied from Google's table is checked for
  the regions it sends to the default.** #214 sent the JPN and EU SKUs to the
  default; Google also tries `_<rev>_<sku>` names. *From:* #214, 2026-11-01.
- **L-375. Device PRs from one contributor that each append to
  `device/<codename>/kernel.config` conflict with each other** (#214 and
  #228). *Check:* say in the merge order who rebases. Extends L-353. *From:*
  #214, #228, 2026-11-01.
- **L-376. A "cap kept below a threshold" change is checked in every
  orientation of the reference phone.** #124's `tile.width > 128` caught the
  7 Pro's landscape cells and shrank icons from 51 to 49 px. Prefer
  `max(old, new)` when a change should only grow. Extends L-300 and L-8.
  *From:* #124, 2026-11-01.
- **L-377. A crash guard relaxed for "the system went down" is checked
  against causes that take the system down.** Under #217 a widget that causes
  a watchdog reset would load at every boot. *Check:* ask for one retry
  rather than a free pass. *From:* #217, 2026-11-01.
- **L-378. When a safety paragraph cites a mask, marker or guard, check it
  exists on the phone that ran the steps.** #202 cited #114's mask, which had
  been dropped from the contributor's boot set. Extends L-284 and L-188.
  *From:* #202 with #114, 2026-11-01.
- **L-379. A "Tested" paragraph carried into a reopened PR is checked against
  the head that ran.** Kernel #155 cited a run of #139's v1 head. Extends
  L-45, L-86 and L-131. *From:* kernel #155, 2026-11-01.
- **L-380. "Interrupt path works" needs a non-zero `/proc/interrupts` count
  and the condition that raised it.** Extends L-29. *From:* kernel #155,
  2026-11-01.
- **L-381. A new interrupt-controller binding for a PMIC block is checked
  against sibling bindings that already promise an interrupt "through the
  PMIC"** (kernel #155 against `maxim,max77779-charger.yaml`). Extends L-53
  and L-164. *From:* kernel #155, 2026-11-01.
- **L-382. Stock's `cs-clock-delay` applies only with a GPIO chip select or
  manual CS mode in Google's spi-s3c64xx.** *Check:* read stock's `cs-gpios`
  first (kernel #166; the check passed). Extends L-75. *From:* kernel #166,
  2026-11-01.
- **L-383. `power-supplies` in a board DT is a fw_devlink supplier link:** the
  consumer waits for the supplier's probe. *Check:* say which device now waits
  on which. *From:* kernel #161, 2026-11-01.
- **L-384. Two PRs that add clock ids to the same block of a dt-bindings
  header can merge without a conflict and leave duplicate numbers** (kernel
  #157 and #163 in `google,zuma.h`). *Check:* after merging, look for
  duplicate values and the `nr_clk_ids` value. *From:* kernel #157, #163,
  2026-11-01.
- **L-385. "Tag X has the same commits" is checked by fetching the tag.**
  Extends L-360. *From:* kernel #163, 2026-11-01.
- **L-386. A new CPU OPP table is checked against the board's BCL `freq_qos`
  caps, as the merged sibling's table is;** mark OPPs above the caps
  `turbo-mode`. Extends L-208. *From:* kernel #158 against #169, 2026-11-01.
- **L-387. A DTS comment that promises userspace protection (a blacklist) is
  checked against that device's package.** *Check:* list the MFD's cells.
  *From:* kernel #163, 2026-11-01.
- **L-388. A stock pin value is the last one in include order.** Kernel #163:
  `hsi2c11_bus` is `PULL_NONE`, then `PULL_UP` in `zuma-typec.dtsi`. Extends
  L-330. *From:* kernel #163, 2026-11-01.
- **L-389. Scratch conflict resolutions chain the marker check into the
  continue:** `script && ! grep -q '^<<<<<<<' f && git add f && git
  cherry-pick --continue`. A reviewer committed conflict markers once.
  Extends L-254. *From:* the 2026-11-01 round.

- **L-390. A dmesg delta across s2idle is not a sleep length:** the kernel
  log's clock stops while the SoC is suspended, so the delta reads about
  1.5 s whatever the real sleep was. *Check:* take sleep lengths from the RTC
  (`/sys/class/rtc/rtc0/since_epoch` before and after), wall-clock journal
  times or `suspend_stats/last_hw_sleep`. *From:* #244, #255, #256,
  2026-11-01.
- **L-391. A reader of `/sys/class/power_supply` skips `scope=Device`
  supplies** and takes status only from the battery that gave the level.
  HID and controller batteries are type `Battery` with `present` 1 and sort
  before the Tensor gauges. *Check:* a test with a Device-scope battery at
  Full and the charger offline. *From:* #267, 2026-11-01.
- **L-392. A mode that skips "only the risky steps" is probed for what the
  other steps write:** run the PR's test and dump the touched files.
  *From:* #259, 2026-11-01.
- **L-393. A shared-fragment `=m` to `=y` change is checked against every
  package, plan and AGENTS line that loads or blacklists that module;** a
  built-in module ignores `blacklist` and load order. *Check:* `git grep -n
  '<module>' packages device/*/*-PLAN.md AGENTS.md`. *From:* #227,
  2026-11-01.
- **L-394. Every symbol added to the shared fragment exists on the published
  kernel branch;** merge_config drops unknown ones silently. *Check:* `git
  grep -n '^config <SYM>$' github/omamobile`. *From:* #227, 2026-11-01.
- **L-395. A descriptor PR is checked with the loader, not only CI:**
  `tests/device-overlays` sources the file, so CI showed one shell error
  where `bin/omamobile` had four refusals. *Check:* `DEVICE=x bin/omamobile
  initramfs-config <tmp>`. *From:* #231, 2026-11-01.
- **L-396. Before answering "may I enable node X", check its parent bus,
  USI and CMU in the published DTS.** *From:* issue #1 (husky
  `usb-typec@25` under a disabled `hsi2c_11`), 2026-11-01.
- **L-397. A charge-rate claim is checked against the percentage change in
  the same report** (pack capacity x delta % / time against the quoted
  current). *From:* issue #1, 2026-11-01.
- **L-398. Sibling PRs that each carry a copy of the same commit conflict
  pairwise in `git merge-tree`;** simulate the real order with
  `--merge-base` before asking anyone to resolve. Extends L-214. *From:*
  kernel #136 and #161, 2026-11-01.
- **L-399. A contributor's "it can't work on your branch" is checked against
  the base's driver, our fragment, the PR's own match table and the boot's
  `lsmod` before we answer.** *From:* kernel #174, 2026-11-01.
- **L-400. A PR retargeted after its last push gets no CI until it is pushed
  again.** *From:* kernel #174, 2026-11-01.
- **L-401. Supplies named in a board comment are checked against Google's
  `<board>-display.dtsi` and `-pmic.dtsi`,** and a driver that follows a
  sibling is compared with the sibling's current version. *From:* kernel
  #177, 2026-11-01.

- **L-402. Before asking for a phone run of a DT node whose driver is a
  module, check the device package's `modprobe.d` for a blacklist of that
  driver or its provider;** a blacklisted provider leaves the consumer
  deferred and the run passes without testing anything. *From:* kernel #176
  (`nvmem_max77759` on cheetah), 2026-11-01.
- **L-403. Wording we suggest on a companion PR is checked against what we
  told the contributor on the kernel PR.** *From:* #262 with kernel #174,
  2026-11-01.
- **L-404. A branch whose version file equals main's merges without a
  conflict;** treat an equal version as taken. Extends L-12. *From:* #267,
  #124, 2026-11-01.
- **L-405. A PR with a merge conflict gets no CI;** "no checks" means run
  `git merge-tree` and the package tests yourself. Related to L-400.
  *From:* #259, #268, 2026-11-01.
- **L-406. A sleep hook that moves its check into the background can
  overlap the next sleep;** ask what `pre` does while that unit is still
  active. *From:* #275, 2026-11-01.
- **L-407. A hook that stands aside for upstream's copy is checked against
  the exact path upstream installs it to.** *From:* #269 (Omarchy's
  `fprintd-resume`), 2026-11-01.
- **L-408. A maintainer-added commit at landing is validated against
  today's bindings at the landed head,** not the tested branch's: the PR's
  CI never builds it. *From:* the kernel #104 landing (gs201 PMU clocks
  against the split `google,gs101-pmu.yaml`), 2026-11-01.
- **L-409. A rail list in a gotcha is checked against each rail's
  `regulator-name` and consumers in the DT the phone runs.** *From:* #270,
  2026-11-01.
- **L-410. A package test must not read the running system's
  `/sys/firmware/devicetree` (or any real hardware path):** on a phone build
  it takes the real branch. Stub every such path. *From:* #114 (a 7 Pro
  build ran the real `modprobe`), 2026-11-01.
- **L-411. A runbook that turns a supply on from userspace says what holds
  that state across a SoC reset and undoes it early in the next boot, and
  its register sequence is checked against Google's GPL driver.** Extends
  C-3. *From:* issue #272, 2026-11-01.
- **L-412. For stock DT values, ask for Google's GPL board source before a
  decompiled image.** *From:* #249, 2026-11-01.
- **L-425. Staging a non-reproducible artifact on two machines under one version makes two packages.** cheetah's boot-file initramfs (`find | cpio`, unpinned order and mtimes) would be staged by the nightly machine and again by #324's release `images` stage. *Check:* build any staged input twice and compare bytes; if they differ, name the one machine and step that produces it. Extends L-268 and L-310. *From:* #320 with #324, round 38, 2026-11-02.
- **L-433. A shipped default that a working feature needs is checked on a
  fresh install, not on the reference phone.** modem-sit shipped `[audio]
  card = none` in its packaged `/etc` file and its built-in default, and
  pacman keeps an edited `backup=` file, so the maintainer's hand-set `auto`
  made "calls work" true on one phone only; the release notes and DEVICES
  said it for everyone. *Check:* for each "works" claim in release notes or
  DEVICES, `git show origin/main:<package>/etc/...` for the keys the feature
  needs, and `git grep` the test that pins the default. Extends L-46.
  *From:* #387 and #405 (commit review), fixed by #416, round 39,
  2026-11-03.
- **L-434. "It didn't happen at shutdown" can't be read from the next boot's
  `dmesg`.** The modem-off UFS error-handler pass follows the CP power-off
  in the unit's stop, and each check grepped the next boot's fresh log, so a
  count of 0 was certain. *Check:* for any "count 0 across reboots", find
  when the event would fire and ask for `journalctl -b -1 -k` (if journald
  outlives the unit) or pstore. Extends L-85 and L-414. *From:* #398 and
  #405 (commit review), round 39, 2026-11-03.
