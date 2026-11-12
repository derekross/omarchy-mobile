<!-- SPDX-License-Identifier: MIT -->
# Review lessons: The gates themselves (part 1 of 2)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-336. A binding commit that follows its first DTS user shows up as
  checkpatch `UNDOCUMENTED_DT_STRING` on a compatible the head documents.**
  Since L-80's fix, each commit is checked against its own bindings, and
  #115's `oneplus,dodge` binding is commit 44 while the DTS is commit 10.
  *Check:* when the gate names a compatible as undocumented, `git grep` the
  head's bindings first: if it's there, the fix is commit order; if it's
  absent (here `oneplus,dodge-panel`, `synaptics,tcm-spi-hbp`,
  `oplus,dhall-ak09970`), it's a real gap that `dtbs_check` will repeat.
  Extends L-80. *From:* kernel #115, round 29.
- **L-335. Per-commit device-tree builds of a board-only stack need no
  worktree.** When only the board file changes between commits, take `git show
  <c>:<board>.dts` for each commit, run `cpp` with the gate's include paths
  (`include`, `arch/arm64/boot/dts`) and the build's own `scripts/dtc/dtc -@`
  in the project container (a minute for five commits), and compare the
  warnings with the base's. Extends L-179. *From:* kernel #134, round 29.
- **L-334. A package test that compares with a sibling package keeps every
  such comparison inside the sibling guard.** `phone-install-package` and
  `build-packages --container-check` hand makepkg the package directory alone,
  and `check()` runs `test/all` there. #145's new `cmp` against cheetah's udev
  rules sat after the `if [[ -f ../omamobile-device-cheetah/… ]]` block, so
  the package couldn't be built on a phone while CI, in the tree, stayed
  green. *Check:* copy the package directory alone to a temp dir and run its
  `test/all`; every `../omamobile-device-` line in `test/all` falls inside the
  guard. Extends L-64 and L-234. *From:* #145, round 29.
- **L-333. A package PR that edits a local `source=` file updates its
  `sha256sums`, and CI can't tell.** #142 changed libfprint's patch and
  `omamobile-udfps.c` but kept 1.6's sums, so makepkg would refuse the first
  build; libfprint has no `test/all`, so `tests/packages` never builds it and
  CI stayed green. *Check:* for every changed file in `source=`, `git show
  <head>:packages/<p>/<file> | sha256sum` against the PKGBUILD's entry (check
  the method on main's files first). `tools/pr-check` could do this for every
  touched PKGBUILD. Extends L-103 and L-268. *From:* #142, round 29.
  Again in round 45: #502's SPDX line on `udev.rules`, added to answer a
  licensing request, changed its sha256; after any round that asks for headers
  on package files, recompute every local `source=` sum.
- **L-311. The same test failing across unrelated PRs within minutes points at
  the CI runner's packages, not the diffs.** On 2026-10-29 Arch moved
  `simdjson` to 5.0.8 before `nodejs` was rebuilt, so from about 01:55Z node
  couldn't load `libsimdjson.so.34` and four docs-only PRs failed the Node
  package tests (fixed by #139). *Check:* `gh run list --workflow checks.yml`
  across branches for a shared start time, `gh run view --log-failed | grep
  'error while loading shared libraries'`, and compare the install step's
  package versions in a passing and a failing run. Extends L-42. *From:* #131,
  #136, #137, #138, round 28.
- **L-310. #129's prebuilt option check can't see a behaviour-only change.**
  #135 changed the fingerprint bridge's scaling and call order with no new
  option, so its test passed with main's stale prebuilt. *Check:* rebuild the
  base source and confirm it matches the installed prebuilt byte for byte,
  then build the head and confirm the hashes differ; better, have the Makefile
  embed the source's sha256 and `test/all` compare it. Extends L-268. *From:*
  #135, round 28.
- **L-309. `dt-validate` runs on the host from a scratch venv when the
  container has no dtschema.** `python3 -m venv $S/venv && $S/venv/bin/pip
  install dtschema` gave working `dt-mk-schema` and `dt-validate`. *Check:*
  build the DTB in the container, validate base and head on the host, and feed
  a known failure to prove the validator bites; that turns "bindings unchecked
  until CI" into a local check. Extends L-103 and L-156. *From:* kernel #98,
  round 27.
- **L-293. An empty diff is checked for empty inputs.** Comparing the gs201
  DTBs before and after kernel #123 with the host's `dtc` printed no
  difference, because the host has no `dtc` and both sides decompiled to
  nothing. *Check:* confirm each side of a comparison is non-empty (or use the
  build's own `scripts/dtc/dtc`) before reading "no change". Extends L-102.
  *From:* kernel #123, 2026-10-28.
- **L-288. A stack with several tops is gated once on a combined commit.**
  Combine the heads with `git merge-tree --write-tree` and `commit-tree` into
  one commit (the gate skips merge commits in its commit checks) and gate
  that, which covers how the tops interact; gate the landing PR on its own
  too, since its DTB differs. Extends L-196. *From:* the tegu stack, round 26.
- **L-281. A re-push can leave CI at `action_required`, so "rebased, CI should
  be green" means nothing until the run is approved.** #79's re-push sat with
  no checks reported. *Check:* `gh run list --branch <head>` on every
  follow-up round, and say in the draft that the maintainer will approve the
  run. Extends L-59 and L-38. *From:* #79, round 26.
- **L-271. An AI author address on an early commit of a squash-merged PR lands
  on main as `Co-authored-by:`,** even after later commits fix the identity,
  and `tools/pr-check` checks only `Signed-off-by:`. *Check:* `git log
  --format='%an <%ae>' base..head` on omarchy-mobile PRs; ask for a
  self-squash or strip the trailer at merge. *From:* #98, round 25.
- **L-262. An AGENTS or CONTRIBUTING line links only tracked files.** #125
  linked `docs/HANDOFF.md`, which doesn't exist, and a script under the
  gitignored `logs/`. *Check:* `git ls-files --error-unmatch <path>` for every
  path the line names; `tools/pr-check` could do this for both files. *From:*
  #125, round 25.
- **L-246. A base build is asked only for targets the base has, with `make
  -k`, and a stopped base build is reported, never hidden.** On kernel #108
  the gate asked the base for a new board's DTB it had no source for; make
  stopped and `|| true` hid it, so how far the base got depended on `-j`,
  existing warnings on unbuilt boards (husky's eUSB2 supplies) read as new,
  and a message the new board's siblings already carry (`soc_id`) counted as
  new. *Check:* a new board's messages are compared with its siblings' at the
  base. Fixed in `tools/kernel-pr-check` (#119) and at the cause (kernel
  #121). Extends L-30. *From:* kernel #108, 2026-10-28.
- **L-247. Normalise `adrp` symbol labels and trailing blanks before naming
  changed functions.** `llvm-objdump -r` labels an `adrp` page with whichever
  symbol starts it, so any layout shift renames it: #94's first diff named
  five untouched functions. *Check:* `/adrp/ s/ <[^>]*>//; s/[[:space:]]+$//`
  in the normaliser. Extends L-153. *From:* kernel #94, round 23.
- **L-30. A gate failure can be the tool's own.** `tools/kernel-pr-check`
  compared device-tree warnings with their line numbers, so a PR that added
  two comment lines above an existing warning failed as if it were new
  (fixed 2026-10-22: positions are stripped). *Check:* reproduce any gate
  failure by hand before blaming the PR, and report a tool fault as a
  finding for the maintainer. *From:* kernel #11, round 2.

- **L-38. "No checks reported" is not a pass.** A pull request pushed
  before a CI workflow reached its base branch never ran it. *Check:*
  compare the push time with the workflow commit; until CI runs, call its
  checks (`dtbs_check`, the package suites) unchecked. *From:* kernel #10,
  #12.

- **L-40. Tools resolve their path arguments before they `cd`.** Our own
  `kernel-pr-check` changed into `-C` and then passed the same relative path
  on, so CI's `-C linux` looked for `linux/linux` and failed every kernel
  PR; a relative `--build` would have built, and deleted, inside the kernel
  checkout. *Check:* call a tool from another directory with relative
  arguments, as CI does, and test that once. *From:* #30, kernel #12.
- **L-41. A gate that wraps another tool must show why that tool failed.**
  Filtering a sub-tool's output to its `not ok` lines hid a `cd` error, so
  CI failed with no reason. *Check:* when a CI failure has no `not ok` line,
  reproduce it the way the workflow runs it before blaming the PR (L-30).
  *From:* #30, kernel #12.
- **L-42. A package test that fails on a PR that doesn't touch the package
  is reproduced on main first.** #24's red CI was a race in
  `omamobile-shell`'s portal test (a log read then truncated, losing a line
  written between), and a retry block that exited silently. *From:* #24,
  round 3.

- **L-59. "No checks reported" can mean CI is waiting for approval.** A
  first-time contributor's runs stop at `action_required` until the
  maintainer approves them (`gh run list --status action_required`). Approve,
  then judge (extends L-38). *From:* kernel #18-#31.
- **L-60. Mesa changes are checked through the generated packers.** Mesa has
  no package test, so CI's green says nothing about it: run `gen_pack.py` on
  each touched `vN.xml` before and after, and grep every caller of a changed
  builder. *From:* #32.
- **L-64. A package file `cmp`-tested against cheetah's copy can carry
  checks the original lacks.** felix's test caught `HandlePowerKey=poweroff`;
  cheetah's own test passed with it. *Check:* mutation-test the original too,
  and give both packages the content checks. *From:* #33.
- **L-69. Compare a renumbered or reworded patch series by the source it
  produces.** Apply the old and the new series to two fresh copies of the
  release and `diff -r` the trees: empty means the earlier review (and any
  test of the earlier build) still applies (L-45 for package patches).
  *From:* #32, round 2.
- **L-70. A gate's "N device trees" can leave out a new overlay.** Neither
  `kernel-pr-check` nor CI built `.dtso` files until kernel #32. *Check:*
  compile every touched overlay with `-@`, apply it to its base with
  `fdtoverlay`, and `dt-validate` the result (`kernel-pr-check --build` now
  does this). *From:* kernel #32.
- **L-73. Gate a PR on its merge, not only on its head, when another PR
  landed in the same files after it branched.** CI checks out the PR head,
  so #20 was never built with #27's S2MPG12 changes. *Check:* `git
  merge-tree --write-tree`, `git commit-tree`, then `kernel-pr-check
  --build` on that commit; after a batch of merges, gate the whole new
  range once. *From:* kernel #20, round 2.
- **L-80. checkpatch reported every compatible a PR documents itself as
  undocumented, and showed warnings only as a count.** It read bindings
  from the clone's checked-out tree, not the commit under test. Fixed:
  `kernel-pr-check` now gives checkpatch each commit's own bindings and
  MAINTAINERS, and prints the warnings (extends L-30). *From:* kernel #21,
  #28, #33, rounds 1 and 2.
- **L-102. Feed a gate a known failure.** The device-tree comparison kept
  only lines saying "warning" or "error"; dt-validate's say neither, so
  every "dtbs_check, no new warnings" (ours and CI's) was blind until
  476901b. A reused `--build` OUT also kept an earlier tree's processed
  schema. Extends L-30. *From:* kernel #13 (found by its author). **Also
  (kernel #192, round 39):** a first-light board validated against the
  base's schema is a known failure for free: rejected on its compatible at
  the base, accepted at the head, which proves both that dt-validate ran and
  that the binding commit carries the fix.
- **L-103. A passing gate log can hide a skipped check.** The project
  container has no dtschema, so its runs print "# no dt-validate … skipped"
  and still pass. *Check:* grep the log for `SKIP` and `skipped` before
  quoting "dtbs_check passes"; run it where dtschema is installed. *From:*
  round 9.
- **L-120. For a new board, `kernel-pr-check` counts every message the
  board inherits as new.** The base has no such DTB, so gs201.dtsi's four
  undocumented compatibles failed lynx. *Check:* `dt-validate -m` a sibling
  board on the same dtsi at the base and subtract its messages before calling
  one new (the tool could do this itself). Extends L-30. *From:* kernel #43.
- **L-121. When a test merge conflicts, check which tree it used before
  asking anyone to rebase.** Our gs201 bindings branch "conflicted" with
  zuma only on the unrelated local integration history; against
  `github/omamobile` and #13 it merged cleanly. *Check:* `git merge-base` and
  `git merge-tree` against the published branch and each open PR's head.
  Extends L-104. *From:* kernel #13, round 10.
- **L-122. "Same tree as before" is checked with the tree object.** `git
  rev-parse A^{tree} B^{tree}` on the same base carries the earlier boot and
  builds over to a reworded commit. Extends L-45 and L-84. *From:* kernel
  #41, #35, round 10.
- **L-145. CI checks a PR that edits a gate with that edit.** `checks.yml`
  runs the PR's own `tools/pr-check`, so #41's new MAC exemption passed
  itself. *Check:* run main's gate too, and review an exemption as a policy
  change: test a line that mixes an exempt value with a real one. (Ours
  dropped whole lines for the all-zeros exemption; since round 12 each
  address is judged on its own.) Extends L-30. *From:* #41, round 12.
- **L-146. CI doesn't parse UCM:** the runner has no `alsaucm`, and the test
  skips silently. *Check:* parse UCM changes locally with `alsaucm` on a
  virtual card, once per `If` branch. Extends L-103. *From:* #41,
  round 12.
- **L-154. `kernel-pr-check` builds the PR's own commits against their
  merge base, so a fix that lands on the base after a PR branched never
  reaches its CI until the PR is rebased.** A fresh `base.sha` doesn't change
  the merge base, and a re-run replays the event's stale one. *Check:* gate
  the PR rebased onto the current base (L-73) before asking for a rebase, and
  say whether the rebase is needed for the code or only for CI. *From:*
  kernel #43, round 13.
- **L-155. A gate runs under every awk it will meet.** Round 12's MAC regex
  used `(…){5}`, which mawk 1.3.4 (Debian, Ubuntu, our build container)
  rejects, so `pr-check` failed every change there while CI's gawk passed.
  *Check:* after any edit to a gate, run its tests in `omamobile-build:24.04`
  too. Extends L-30. *From:* round 13.
- **L-156. A bindings-only PR gets no `dtbs_check`** from CI or
  `kernel-pr-check` ("device trees: none touched"), so no board's DTB is
  checked against the new schema. *Check:* validate the affected boards'
  DTBs by hand; dtschema's schema checks run in the container with a stub
  `libfdt`, only `dt-validate` needs the real one. Extends L-126. *From:*
  kernel #51, round 13.
- **L-178. A rejected property in a dt-validate known-failure feed can read
  "False schema does not allow 0", without the property's name.** A `prop:
  false` under `then:` reports the value, not the key, so grepping the output
  for the property name says "not rejected" when it was. *Check:* grep the
  feed's output by node name and compare base against head line by line.
  Extends L-102. *From:* kernel #63, round 20.
- **L-179. Neither CI nor `kernel-pr-check` builds a series commit by
  commit, and kernel PRs land commit by commit.** CONTRIBUTING §6.2 says each
  commit must build; the gate builds the head's touched files only. *Check:*
  for a rebase-merged series, check out each commit in a worktree on the
  host and build that commit's touched objects in the container (a
  worktree's `.git` file points at the host path, so `git checkout` inside
  the container fails). Done by hand for #63's 14 commits. Extends L-123.
  *From:* kernel #63, round 20.
- **L-180. The gate's test-merge commits don't exist in the clone,** since
  the container builds them in its own copy, so a later schema or DTB
  comparison "on the test merge" makes its own tree with `git merge-tree
  --write-tree` (`git archive` takes a tree id). *From:* round 20.
- **L-181. Grep a CI job's log for the gate's own `ok -`/`not ok` lines, not
  for the check's name.** The kernel job is named "Kernel (sign-offs,
  checkpatch, W=1, dtbs_check)" and `gh run view --log` prefixes every line
  with it, so a grep for `dtbs_check` matches everything and hides whether
  dt-validate ran. Extends L-103. *From:* round 20.
- **L-194. A review's clone goes on disk, and a gate's worktree is sparse:
  the scratch `/tmp` is a 16 GB tmpfs shared by every parallel review.** A
  `--depth 60` clone of the SM8150 tree for #52 and three full checkouts of
  omarchy-mobile (about 1 GB each, `phone/screenshots` and all) each filled
  it, and a command of another review lost its output. *Check:* `df -h` the
  scratch volume before any clone or build over a few hundred MB; trees go
  under `~/android/mainline/wt-review-<topic>`; a gate's checkout is `git
  worktree add --no-checkout --detach`, `git sparse-checkout set --cone bin
  device initramfs tests packages/<the ones the tests compare>`, `reset
  --hard` (3.5 MB, and `tests/storage-guard`, `tests/simplefb-trigger` and
  the package tests all run from it). *From:* #52, round 21.
