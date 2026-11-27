<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Reviews and merging (part 4 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
