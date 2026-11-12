<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Reviews and merging (part 2 of 2)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-353. A same-day notes PR on one device conflicts with its sibling.**
  Both add their section at the top of NOTES (#208, #209). *Check:*
  merge-tree the second PR onto the first one's squash and plan the order
  before merging the first. *From:* #208 and #209, 2026-10-31.
- **L-354. A contributor's "kept your rows" after merging the maintainer's
  push is checked by a merge simulation, and so is the maintainer's own
  pass.** #165's merge brought back old husky and panther rows; then, rebased
  onto our DEVICES pass, it dropped its own works/testing row because it
  assumed the pass carried it, and the 9a read WIP everywhere until the row
  was restored from the PR's force-push history. *Check:* word-diff
  `origin/main` against the merge-tree result for every line outside the
  PR's own row, and after a contributor "reduces" a PR to what the pass
  lacks, diff the pass against their previous head. *From:* #165,
  2026-10-31.
- **L-355. A stacked PR whose author merges main instead of rebasing still
  carries its bottom's old head.** #115 and #117 carried an old #99, so they
  conflicted once #99 landed. *Check:* `git merge-base --is-ancestor <bottom
  head> <PR head>`; hand over (or land) a file-level rebuild from the PR's
  own files, checked to reproduce its tree. *From:* #115 and #117,
  2026-10-31.
- **L-356. A version renumbered by a merge leaves the title on the old
  version.** #115, #117, #124 and #183 all named older versions than their
  `version` files. *Check:* compare every title with the head's version on
  each push, and write the squash subject from the file. *From:* round of
  2026-10-31.
- **L-357. A contributor's merge of main can resolve to main's tree and drop
  the PR.** #99's b3ceaf1 left the branch identical to main; the push of the
  maintainer's merge was then rejected as non-fast-forward. *Check:* `git
  diff origin/main <head>` is not empty before reviewing or pushing on top.
  *From:* #99, 2026-10-31.
- **L-423. Cross-PR interactions are re-checked on every round, including a PR's diff against another's tracked sources.** Round 38 said #324's `repo-publish` would auto-merge with #320; a follow-up then made them collide on one option line. #326 edits `device/cheetah/device.conf`, one of #320's boot-file sources, so merged after the staging it would make the nightly skip device-cheetah. *Check:* rerun `git merge-tree` for related PRs each round, intersect each diff with the other's source list (`tools/stage-boot-files --sources <codename>`), and order staging after both merge. Extends L-253. *From:* #320 with #324 and #326, rounds 38b-38c, 2026-11-02.
- **L-424. A shared tool that gains a required input breaks every open PR whose test calls the real tool with its own fixture.** #326 made `release-upload` require the `.tar`; #324's `tests/release` builds a bundle by hand and runs the real tool, so the pair turns main red though each is green alone. *Check:* `git grep -n '<tool>' <each open PR head> -- tests/`, rebuild those fixtures against the new tool, and give the merge order in both reviews. Extends L-104 and L-214. *From:* #326 with #324, round 38, 2026-11-02.
- **L-426. Two open PRs that bump a package to the same version merge
  silently, in either order.** Both write the same `version` line, so `git
  merge-tree` shows no conflict and the second merge ships new contents
  under a published version: #407 and #403 (device-tegu 0.2.9), #389 and
  #403 (omamobile-modem 0.1.17), #400 and #403 (device-raven 0.1.31). And a
  "merging at version X" in our own comment goes stale: #373 took the 0.3.29
  we had promised #367. *Check:* each round, list `packages/*/version` on
  every open PR head and flag equal values; before every squash, compare the
  branch's file and subject with `git show
  origin/main:packages/<p>/version`. Extends L-12, L-217 and L-404. *From:*
  #407, #389, #400, #367, round 39, 2026-11-03.
  Again in round 46, in most of the round's reviews: #553 and #557 both claim
  omamobile-shell 0.2.108 with a clean `merge-tree` including `version`; #539
  and #542 claim 0.2.107, which main already shipped; #371 collided on four
  packages at once. The rule since: the maintainer sets every version by hand
  at merge (file and squash subject), and each review lists the collisions it
  found rather than asking the contributor to renumber.

- **L-427. A change under a boot-files device package's `src/` makes its
  staged boot files stale, and that strands a sibling's new dependency on
  it.** `tools/stage-boot-files` hashes `packages/<device>/src`, so #403's
  `reboot-to.c` holds device-cheetah back from the nightly until the
  maintainer restages; #371 makes modem-sit require a policy only the new
  device-cheetah provides, so publishing #371 first would break `omarchy
  update` on every 7 Pro. *Check:* `tools/stage-boot-files --sources
  <codename> | grep <touched path>`; if listed, put the restage in the merge
  plan before any dependent PR. Extends L-420 and L-423. *From:* #403 with
  #371, round 39, 2026-11-03.
  Again in round 45: overlays count too. #517 renamed two nodes in cheetah's
  `aoc-sound-test.dtso` (listed in `DTB_OVERLAYS`) and bumped nothing because
  the package directory didn't change; the merge plan pairs such a PR with the
  device package's next version and a restage, and names the boot that checks
  the new DTB.
- **L-428. `Fixes #N` on a PR that answers part of an issue closes the rest
  at merge.** #403 deferred #390's second point (an inhibitor left after a
  failed start) and still said "Fixes #390". *Check:* read the issue's
  comments for each distinct report; ask for "Part of #N" or a new issue.
  *From:* #403, round 39, 2026-11-03.
- **L-429. One author's PRs with the same head commit are one PR, and a fix
  they say is done may sit on another branch of their fork.** #412 and #231
  both pointed at `8f2dc60d`, so #412's sources couldn't be in it; #231's
  format fix had been committed a day earlier on a side branch and reached
  the PR only as a merge. *Check:* at the start of a round compare
  `headRefOid` across an author's open PRs, and when "done" isn't in the
  head, `git ls-remote <fork>` for the commit. Extends L-29 and L-248.
  *From:* #412 with #231, round 39, 2026-11-03.
- **L-430. Siblings that add blocks to one board file get `merge-tree`
  re-run every round, with and without the disputed commit.** Kernel #162's
  sound card and #187's Wi-Fi regulator both add a root block at the end of
  `zumapro-tegu.dts`; an earlier "merges cleanly" held only without the
  card. *Check:* `git merge-tree` of each pair on today's base, both ways,
  and keep the resolved file in the review. Extends L-253 and L-423. *From:*
  kernel #162 with #187, round 39, 2026-11-03.
  Again in round 45: round 44's "#503 and #484 merge cleanly" stopped holding
  after #503's rework, whose `sda` branch conflicts with #484's whole-disk
  rule; a "merges cleanly" in our own comment is re-checked after every
  rework.
- **L-431. A conflict resolution that keeps both sides' tests runs both
  suites in the order they end up in.** Resolving #288 by appending main's
  `--no-checkpatch` test after #288's checker tests left it running on a
  tree with no commits to check, and it failed; the same blocks in the other
  order pass. *Check:* after any resolution that keeps both sides, run the
  touched suites on the merged tree, and read what state each block leaves
  for the next. Extends L-184. *From:* the merges of #287 and #288, round
  39, 2026-11-03.
- **L-432. A squash merge carries a body that says why.** Three round-39
  merges went in with `--body ""` and landed with a subject only; main isn't
  rewritten for that. *Check:* every `gh pr merge --squash` gets
  `--body-file` written from the PR's own commit message (with record ids or
  merge noise removed, L-372), and no squash runs without one. Extends
  L-372. *From:* #408, #369, #411, round 39, 2026-11-03.
- **L-477. A rebase over a merged PR that took the same version can drop or
  equal a stacked PR's bump, and its dependency is then met by the wrong
  package.** #371's device-cheetah stayed at 0.1.44 with a new `provides`
  after #416 shipped 0.1.44 without it, and its device-tegu bump vanished
  after #407 shipped 0.2.9, so its own `>=0.2.9` dependency is met by the
  published package without the feature. *Check:* in every range-diff after
  a rebase, grep the changed commits for removed or equal `version` hunks,
  and confirm each changed package's version is above main's. Extends L-404,
  L-426 and L-427. *From:* #371 with #416 and #407, rounds 40-41.
- **L-478. Two open PRs that edit the same package test file pass CI
  separately but are never tested together.** #389 and #424 both edit
  `omamobile-modem/test/all`, and CI builds each against main only. *Check:*
  run the suite on `git merge-tree --write-tree <A> <B>` before merging the
  second. Extends L-431. *From:* #389 with #424, round 40, 2026-11-04.
- **L-479. Every round, open PRs on one SoC are checked for new clock IDs in
  the same CMU block, not only for textual conflicts.** #200's CMU_TOP 22-27
  and #157's 22-34 share a block of `google,zuma.h`, and `merge-tree`
  auto-merged it with both. *Check:* `git diff <base> <head> --
  include/dt-bindings/clock/<soc>.h | grep '^+#define'` per open PR, grouped
  by CMU block. Extends L-384. *From:* kernel #200 with #157, round 41,
  2026-11-05.
- **L-480. A promise in our own comment ("I'll approve CI", "still needs X")
  is re-checked at the next round and before posting.** Kernel #192's run
  was still `action_required` a day after we said we'd approve it, and our
  #374 comment, drafted a day before posting, asked for a #378 rebase that
  had already happened. *Check:* `gh run list --branch <head>` for each PR
  whose last comment promised an approval, and re-read each "still needs"
  against the head at posting time. Extends L-59, L-124 and L-281. *From:*
  kernel #192 and #378, rounds 40-41.
- **L-481. A hand-written squash body keeps the PR's attribution trailers.**
  Three of round 41's four squashes (#396, #395, #410) dropped their
  commits' `Co-Authored-By:` lines, which CONTRIBUTING §6.3 asks for.
  *Check:* `git log --format='%(trailers:only)' base..head` on the PR, and
  carry each distinct trailer into `--body-file`. Extends L-432. *From:* the
  2026-11-04 merges, round 41, 2026-11-05.
- **L-519. A request or merge order that rests on another decision is
  re-derived when that decision changes.** Round 41 asked #431 to move to the
  4.5 port, then phones were pinned to 4.0.6; #371 was ordered after #403 only
  for a restage, and #403 went on hold. *Check:* write down why for each "redo
  for" or "after X", and re-check it when a pin, hold or channel lands.
  Extends L-250 and L-427. *From:* #431 and #371, round 42, 2026-11-07.
- **L-520. A general call to affected users is checked against the thread
  above it.** Our pin announcement on #434 asked owners to speak up three
  hours after one had, and his report went unanswered. *Check:* read the
  comments since our last post and answer them first. Extends L-124. *From:*
  issue #434, round 42, 2026-11-07.
- **L-521. A hand-written squash subject is checked against the PR's own
  files.** #231 was merged as "the Pixel 8 Pro's sibling"; kodiak is the Pixel
  11 Pro XL. *Check:* read the device descriptor or plan the PR touches before
  typing a device name. *From:* #231, round 42, 2026-11-07.
- **L-522. A GitHub comment draft is reflowed, never inside code fences.** A
  draft wrapped at 120 columns renders its hard line breaks. *Check:* join
  each paragraph's lines before posting, leaving fenced and indented code
  blocks as written. *From:* round 42's posts, round 42, 2026-11-07.
- **L-523. When a series selector accepts exact versions, removing a pin moves
  the hold rather than lifting it.** #471's `default_series` refuses anything
  but 4.0.6 or 4.5.0, so dropping the pin would hand phones whatever 4.5.x
  shipped that day. *Check:* read what the selector accepts, and plan to
  replace the pinned files with the rehearsed version. *From:* #471, round 42,
  2026-11-07.
- **L-550. A series split, or any rename of a directory, moves every open PR's
  new file under the old path into the new meaning of that path.** #471 makes
  `patches/` the Omarchy 4.5 family and moves 4.0.6's to `legacy-4.0.6/`;
  #420's new `patches/0029-…` (a 4.0.6 patch) then merges into the 4.5 family
  with only a `version` conflict, misses every 4.0.6 phone and probably breaks
  the 4.5 family's all-or-nothing apply. *Check:* for each open PR that adds
  files under a directory another open PR renames or repurposes, simulate the
  merge both ways, `git ls-tree` where each new file lands, apply each new
  file to the family it was written for, and give the merge order and the move
  in both reviews. Extends L-104, L-423, L-424 and L-426. *From:* #420 with
  #471, round 44, 2026-11-08.
  Again in round 46: #471 against main after #420 conflicted only on
  `version`, yet the plain resolution dropped 0029 from every 4.0.6 phone, and
  CI couldn't see it because its 0029 assertion sits in the real-package block
  CI skips (L-548). For each file main added under the repurposed directory
  since the PR's base, run `test/all` with `OMARCHY_PKG` for each family on
  the resolved tree.

- **L-551. A version we write into "I'll title it X" goes stale like any other
  promise; check it again when merging.** On 11-05 we promised #421 the title
  `shell 0.2.101`; #464 shipped 0.2.101 two days later, and the branch's
  identical bump would have merged silently. *Check:* before every squash,
  `git show origin/main:packages/<p>/version` and the versions on the open PR
  heads (`gh api …/contents/packages/<p>/version?ref=<sha>`), then write the
  next free number into the subject. Extends L-217, L-426 and L-480. *From:*
  #421, round 44, 2026-11-08.
- **L-552. A sibling's descriptor list that changes between rounds is compared
  with the PR's copy.** #456 took the 7 Pro's `NV_BACKUP_EXTRA="devinfo"`. Two
  hours after our round asked about akita's NV list, husky's #449 added
  `trusty_persist trusty_userdata` on the same SoC, and the reply's new NOTES
  list still left `trusty_userdata` out. *Check:* every round, `git log <PR
  base>..origin/main -- packages/omamobile-device-<same-SoC
  sibling>/device.conf device/<sibling>/device.conf`, and diff each key the PR
  sets against the sibling's current value. Extends L-195 and L-257. *From:*
  #456 with #449, round 44, 2026-11-08.
- **L-553. A fix found in a builder copied from a sibling is checked in the
  sibling's builder.** Akita's `build-u3-root` is husky's with the names
  changed; the depmod gap #456's second tester found is in both, and only
  akita's was fixed. *Check:* `diff <(sed s/<a>/X/g A) <(sed s/<b>/X/g B)` for
  any device script the PR says it copied, then list the sibling's copy for
  the maintainer. Extends L-492. *From:* #456, round 44, 2026-11-08.
- **L-554. A promised pre-merge build of a new package is checked against the
  state of the output it writes.** With `out/repo` pinned as a release index,
  `tools/build-packages` (which iterates `packages/*/`) would have added
  #463's packages to it. *Check:* before advising "build it through
  build-packages", read the current release state; use `--local <name>` (its
  own `out/<name>/` and key) or the publish machine. Extends L-7. *From:*
  #463, round 44, 2026-11-08.
- **L-555. "No phone test while phones stay on version X" is checked against
  the phones that already left X.** #471's selector applies the 4.5 family to
  any phone on Omarchy 4.5.0. #434 records a Pixel 7 Pro that took 4.5.0-3
  before the pin, and pacman won't move it back, so the merge is that phone's
  first hardware run of an unqualified series. *Check:* for a selector or gate
  keyed on an installed version, grep the pin's issue and the device threads
  for phones already past the pin, and plan their first run before publishing.
  Extends L-444, L-519 and L-523. *From:* #471, round 44, 2026-11-08.
- **L-556. A stacked PR's conflict can belong to its merged bottom's
  commits.** #371's DEVICES.md conflict came from #367's old commits
  underneath, and main already held their text. *Check:* before asking the
  contributor to resolve, merge only the PR's own range (`git merge-tree
  --merge-base=<bottom head> origin/main <head>`), and grep main for the
  strings the bottom's commits added. Extends L-275 and L-355. *From:* #371,
  round 44, 2026-11-08.
- **L-557. A contributor's "I won't run it until I hear from you" is a hold we
  track.** Somnius asked on #472 at 18:04Z, then reported modem power-line
  steps on kernel #187 at 22:20Z, in the other repository, with no answer in
  between. *Check:* before replying in any thread from that contributor, list
  their hardware results posted after the hold, with times (`gh api
  repos/<r>/issues/comments?since=<hold time>` in both repositories, filtered
  to the user). Extends L-109 and L-124. *From:* kernel #187 with #472, round
  44, 2026-11-08.
- **L-590. "Merge, then run it on a phone before it's published" doesn't exist
  while the development channel publishes `origin/main` daily.**
  `omamobile-publish.timer` runs at 04:00 from a clean `origin/main`, so a
  merged package is on `pkgs.omamobile.org/development` the next morning.
  *Check:* when a review puts a phone run "before publishing", either make it
  a before-merge gate or say that the maintainer pauses the timer (`systemctl
  --user stop omamobile-publish.timer` on the build machine) until the run.
  Extends L-444 and L-250. *From:* #471, round 45, 2026-11-08.
- **L-591. A record without a time zone is placed in UTC before it is compared
  with thread times.** #514's stage times read as if the modem steps came
  after the 22:20Z report (S5e ending "23:21"); the contributor's commits are
  `+0200`, which puts S3 at 19:15Z, 71 minutes after the hold question.
  *Check:* take the zone from the contributor's commit dates (`git log
  --format=%ci`) or the log's own stamps, convert every step to UTC, and lay
  it next to the thread's times before saying what ran before or after what.
  Extends L-344 and L-557. *From:* #514, round 45, 2026-11-08.
- **L-592. A follow-up report is counted against the full record when it
  arrives.** The kernel #187 report described three power-on phases; the plan
  written afterwards shows five power-ups, two with the charger in and music
  playing. *Check:* when a contributor's plan follows a thread report,
  tabulate the plan's write steps and compare the count with the report before
  replying to either. Extends L-345 and L-488. *From:* #514 with kernel #187,
  round 45, 2026-11-08.
- **L-641. Parallel reviewers work under a per-review topic, in ref names and
  in a per-review scratch subfolder, and never glob-delete shared names.** In
  round 46 one reviewer deleted others' refs with a `review/*-r46-*` glob and
  ran `rm -f merge-*` in the round's shared folder; another lost
  `review/pr471-r46-om` mid-review ("om" is too generic) and went on from the
  commit id; a third wrote `threads.txt` and `pr-check-main` at the round
  folder's top level, where other reviews keep files of the same names.
  *Check:* `ls` the round folder and `git branch --list "review/*-<topic>"`
  first (both empty for a topic unique to the run), write only under
  `round<N>/<topic>/`, delete only by the exact names recorded at creation,
  and pass commit ids to every later command. Extends L-43, L-127 and L-364.
  *From:* #471, #530 and the round's cleanup, round 46, 2026-11-09.
- **L-642. After a maintainer fixup to a contributor branch, run the touched
  package's whole `test/all`, not a subset.** The #371 fixup changed a
  version and `depends` line, and that package's own test hard-coded the old
  value, so CI failed. *Check:* for each package directory
  the fixup touches, `packages/<p>/test/all` (and `tests/packages` for the
  depends graph) on the fixed-up head before pushing it. Extends L-408.
  *From:* #371, round 46, 2026-11-09.
- **L-643. A maintainer fixup on a contributor's branch is a new commit on
  top, not an amend.** An amended commit that is already on the branch can
  only be pushed with a force push, which rewrites the contributor's history.
  *Check:* `git merge-base --is-ancestor <branch's remote head> HEAD` before
  every push to someone else's branch; if it fails, redo the change as a new
  commit. *From:* #371, round 46, 2026-11-09.
- **L-644. A stacked branch under a squash-merged base is rebased with
  `--onto <base head>`, and the review says so.** #540 and #541 each carry
  #493's four commits; after a squash merge none of them is patch-identical to
  main's squash commit, so a plain `git rebase origin/main` replays them and
  conflicts. *Check:* when a contributor says "I'll rebase once X merges",
  give them `git rebase --onto origin/main <X's head> <branch>`. *From:* #493
  with #540 and #541, round 46, 2026-11-09.
- **L-645. An expectation we write into one PR about another PR's head goes
  stale when that PR is fixed, and the contributor may copy it into a
  runbook.** Round 45 told #505 "the screen will most likely go dark" because
  of kernel #220's supply move; #220 was fixed 40 minutes later, and #505's
  runbook now expects the old fault. *Check:* each round, for every cross-PR
  expectation in our last comments, re-derive it on the other PR's current
  head before reading the runbook that quotes it, and own the correction.
  Extends L-250 and L-403. *From:* #505 with kernel #220, rounds 45-46,
  2026-11-09.
- **L-646. "The tested tree carries over" is checked per file by blob against
  a reconstructed tested tree, when the tested kernel was a local merge.**
  For kernel #187 the 7 Pro ran `a3e96faa` plus #191; `git merge-tree
  --write-tree <#191's merged commit> <tested head>` rebuilt it, and every
  non-zuma file the PR touches had the same blob at the rebased head, which
  answered "does the run stand?" without a rebuild or a reboot. *Check:*
  rebuild the tested combination with `merge-tree`, then `git rev-parse
  <tree>:<f>` against `<head>:<f>` for each touched file. Extends L-45, L-483
  and L-547. *From:* kernel #187, round 46, 2026-11-09.
