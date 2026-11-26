<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Reviews and merging (part 4 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
