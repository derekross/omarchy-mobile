<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Reviews and merging (part 4 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
