<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Reviews and merging (part 3 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-270. An "or keep X and say so" we offer must pass the gates the same
  review names.** Round 24 on kernel #98 asked for the eight required
  supplies, which `dtbs_check` enforces, and also offered keeping the fixed
  regulator, which can't pass CONTRIBUTING's no-new-warnings rule. *Check:*
  run each alternative in a draft past every blocking point in the same draft
  and §6's gates. Extends L-229; see C-16. *From:* kernel #98, round 25.
- **L-265. A bare `#N` links to the repository the comment is in.** W4HO's
  tables on issue #28 named kernel PRs as `#119` and `#122`, which link to an
  omamobile PR and issue. *Check:* write
  `derekross/linux-omamobile#N` when a comment names the other
  repository's PRs, and read cross-repository tables in a thread with that in
  mind. *From:* issue #28, round 25.
- **L-263. A squash title that names a package version must agree with the
  `version` file it lands.** #112 landed as "device-raven 0.1.26" with the
  file still at 0.1.25, so a publish would reuse a version with new contents
  (fixed by #126). *Check:* on each squash merge, and on the next PR for that
  package, compare `git show origin/main:packages/<p>/version` with the last
  squash subject that touched it. Extends L-12 and L-217. *From:* #112 with
  #113, round 25.
- **L-248. A reply that says "pushed" is checked against that PR's own head,
  not the stack's.** #87's reply described fixes that existed only below #90
  and #96; its own branch stayed put, with green CI. *Check:* `git ls-remote
  <remote> refs/pull/N/head` and `git range-diff` per PR; when every commit
  is `=`, grep the open heads above it for the fixed commits. Extends L-166
  and L-183. *From:* kernel #87, round 23.
- **L-249. A "tested blob" from an unpublished tree can be a blob from our
  own earlier review ref.** #88's and #89's tested files were the previous
  heads' blobs. *Check:* `git cat-file -t <blob>`, then `git diff <blob>
  <new head>:<path>`. Extends L-131. *From:* kernel #88, #89, round 23.
- **L-250. A merge plan carried over from an earlier round is re-read
  against the rules that landed since.** Round 20 planned #71's Pixel 7 Pro
  check after the merge; CONTRIBUTING §6.2 then made it a before-merge rule.
  *Check:* `git log --since=<our last comment> -- CONTRIBUTING.md AGENTS.md`,
  then every "merge, then check" in the plan. Extends L-31 and L-185.
  *From:* kernel #71, round 23.
- **L-251. When a stack is re-pushed onto one line, the landing PR moves to
  the top, and the boot is asked of the top.** With #84, #89 and #95 merged,
  #80-#96 became one chain; a boot of #80 alone would test a tree that never
  lands. *Check:* `git log base..head` per PR; ask for evidence on the commit
  that will be merged. Extends L-196. *From:* kernel #80-#96, round 24.
- **L-252. A "sync to the phone's tree" commit is diffed against the base
  for deletions the series never meant.** #115's last commit overwrote two
  Kconfig files with a private tree's copies and dropped two other phones'
  drivers. *Check:* `git diff --stat base head` against the PR's feature
  list, and `git log -S'<symbol>'` for every removed `config` line. *From:*
  kernel #115, round 24.
- **L-253. One contributor's board PRs that all append to one DTS conflict
  pairwise: build the combined resolution once and hand over an order.**
  *Check:* `git merge-tree` per pair; cherry-pick all onto the base, build
  and `dt-validate` that tree, and ask for a stack next time. Extends L-104
  and L-196. *From:* kernel #111-#116, round 24.
- **L-254. Scratch merges in the shared kernel clone run with rerere off.**
  The clone has `rerere.enabled=true`, so a review's scratch cherry-picks
  recorded resolutions (one wrong) that a later real merge could replay.
  *Check:* `git -c rerere.enabled=false cherry-pick|merge …`, or `git
  merge-tree` only. Extends L-43 and L-127. *From:* round 24.
- **L-255. A fix copied onto several squash-merged PRs merges first.**
  #107's audio 0.5.5 rode on #100, #101, #115 and #117; squashing any of
  those first lands the bump under the wrong title. *Check:* `git rev-parse
  <head>:packages/<p>` across the PRs, then merge the fix PR first. Extends
  L-12 and L-217. *From:* #107, round 24.
- **L-31. Our review requests must agree with CONTRIBUTING.** Round one of
  kernel #11 asked for a squash that §6.2's "disabled, then a separate
  enabling commit" rule contradicted. Since 2026-10-22 §6.2 allows a board
  node already proven on a same-SoC phone to be added enabled in one
  commit; otherwise, when a request and a rule disagree, fix one of them.
  *From:* kernel #11.
- **L-34. Before a second round, check the head moved.** Compare the PR's
  head with the `commit_id` of our last review and read the timeline:
  comments and cross-references also change the "updated" time. Answers
  given only in comments must still land in the files. *From:* #24,
  round 2.
- **L-39. A rebase or squash merge gives new commit ids, so a stacked PR
  must be rebased before it merges.** After #11 was rebase-merged, #12 still
  carried #11's old commit underneath and couldn't merge as it stood. *Check:*
  when merging a PR another one is stacked on, ask the second one's author to
  rebase onto the branch, and merge in order. *From:* kernel #11 and #12.
- **L-43. Parallel reviewers use unique ref names.** They share the kernel
  clone, and one deleted another's `review/pr12` mid-review. *Check:* name
  refs `review/prN-<round>` (now `review/prN-rR-<topic>`, L-127) and pass commit ids to the gates. *From:* kernel
  #12, round 3.
- **L-44. A staged descriptor's refusal depends on the tooling PRs in
  flight.** Tegu added `SOC_COMPATIBLE` while #27 was about to make either
  key acceptable, so merging both would have made tegu installable without
  the AVB footers its bootloader needs. *Check:* test a staged descriptor
  against the heads of open PRs that touch `bin/omamobile` or
  `tools/install-phone`. *From:* #24 with #27.
- **L-71. Our requests say which repository each piece goes in.** "A kernel
  PR … with an overlay that enables it" put a bring-up overlay in the kernel,
  against CONTRIBUTING §6.1 (extends L-31). *From:* issue #3 and kernel #32.
- **L-104. Run `git merge-tree` across every pair of open PRs that touch the
  same files,** one contributor's parallel PRs included, and give the merge
  order in each review. Look for duplicate mechanisms too (#34's
  `ro_gate_clks` beside #40's private read-only gates). Extends L-39 and
  L-73. *From:* kernel #34 with #40, #37 with #39.
- **L-105. When a contributor writes a private driver after we asked for
  the common helper, find what pushed them off it** (here a PMU check that
  can't defer inside the `__init` probe) and answer that, not only the
  request again. *From:* kernel #40.
- **L-123. A fix-up commit on a rebase-merged PR is folded in.** Kernel
  PRs land commit by commit, so #34's watchdog commit would have landed with
  the CG_VAL-only read (a bisect could stop there with the watchdogs
  unowned), and #38's driver commit claiming temperature. *Check:* `git
  range-diff` for a new commit that only changes lines an earlier commit of
  the same PR added; read the earlier messages against the new head.
  *From:* kernel #34, #35, #38, round 10.
- **L-124. Before asking again, check whether the contributor's report
  crossed our post.** The 23:11Z husky report answered round 9 before round 9
  was posted. *Check:* compare comment times with our post time. *From:*
  kernel #33, round 10.
- **L-125. Check a whitespace nit by column, not by counting tabs.**
  `expand` the hunk with its neighbours: `google,zumapro.h` gives every name
  of that length two tabs. *From:* kernel #34, round 10 (withdrawn nit).
- **L-126. A binding PR's SoC condition can reject another open board's
  DTB without a textual conflict.** #13's `soc_compatible: false` for
  non-zuma boards fails lynx (gs201 IPOP). *Check:* merge each open board PR
  with each open binding PR on the same schema and run `CHECK_DTBS=y`.
  Extends L-104. *From:* kernel #43 with #13 and #37.
- **L-127. Parallel reviewers suffix refs with their topic, and delete only
  refs they created.** In round 10 several used `review/prN-r10`, and one
  deleted (then restored) refs another was using. *Check:*
  `review/prN-r<round>-<topic>`; clean up from a list recorded at fetch time.
  Extends L-43. *From:* round 10.
- **L-147. Before re-checking an earlier round's request, re-derive it from
  what has landed since.** Round 11 asked #22 to gate `aoc-stage s2mpu` on a
  `tzpc` restore, from the tool's header alone; raven's plans (#41) show
  that SMC hung the SoC and that the `pd` stage made the read safe, so the
  gate could only be passed by a known hang (C-6). *Check:* for every safety
  gate we asked for, find the plan row it rests on and confirm the step it
  requires passed there. Extends L-31. *From:* #22, round 12.
- **L-148. `git merge-tree` exiting 1 can mean a missing ref, not a
  conflict.** Another reviewer deleted their refs mid-review. *Check:* read
  the message, and use commit ids for other reviewers' PRs. Extends L-127.
  *From:* round 12.
- **L-165. "No checks reported" can mean the PR conflicts with its base,**
  since GitHub runs no `pull_request` workflow then. *From:* kernel #53,
  round 14.
- **L-166. When a PR is force-pushed after its phone test, diff the old head
  against the new.** GraphQL's `HeadRefForcePushedEvent.beforeCommit` gives
  the old id; REST's timeline omits it. *From:* kernel #54, round 14.
- **L-167. Posting scripts split drafts by heading, never by line number,
  and each posted file is checked first.** Round 13's line ranges put #49's
  last bullet at the top of #50's comment. *From:* round 13 (found in 14).
- **L-182. "My merged PR isn't on the branch" after a rebase merge is
  checked by patch-id and the branch's push events, not by ancestor.** A
  rebase merge lands the commit under a new id, so the PR's head is never an
  ancestor and GitHub shows no merge commit; two merged commits came back as
  new PRs (kernel #67, #68), and merging a resubmission onto the base gives
  the base's own tree, which the gate can't tell from a real change.
  *Check:* `git show <merged id> | git patch-id` against the resubmission;
  `gh api repos/<r>/branches/<b>` for the head and `events` (or
  `activity?ref=`) for pushes since the merge, all fast-forwards; `git
  merge-base --is-ancestor <merge> <tip>`; and `git merge-tree --write-tree
  base head` compared with `base^{tree}`. Extends L-39. *From:* kernel #67,
  #68, round 20.
- **L-183. "I took the point" is checked against the code, not the reply,
  one request at a time.** #57's new head changed only its subject and
  message while the comment said the blocking request was taken; #40's
  rework followed a merged sibling's convention (#34's TOP table) and so
  dropped one offset we had asked for, without a word. *Check:* for every
  force-push after a review, `git diff <old head> <new head> -- <dir>` per
  touched file (L-166 gives the old id), tick each request off against that
  diff, and for a dropped one name the merged precedent and say which wins.
  Extends L-34, L-123 and L-166. *From:* kernel #57, #40, round 20. **Also
  (kernel #162, round 39):** an alternative offered instead of a requested
  split is checked against the reason we gave for the split, not only
  against the gates: two bindings that pass dtbs_check still documented the
  unprefixed names we split the card out to avoid.
  **Also (#409, round 46):** a "the script records X" claim is checked by
  finding the line that does it: #409's `sleep-series-loop.sh` had no ext4
  line, and its cap was per invocation, not the per-night cap the condition
  named.
- **L-184. When we tell a contributor how to resolve a conflict, derive the
  resolution from the file, and better, hand over the resolved hunk.** Rounds
  18 and 19 said "keep both lines in both lists" for
  `samsung,exynos-sysreg.yaml`, but the new compatible lives in the `clocks:
  false` branch, and adding it to the clocks-required list would have failed
  husky; the contributor caught it. *Check:* build the resolved file (`git
  merge-tree` tree plus the PR's hunk), run the schema and board validation
  on it, and attach it. Extends L-31 and L-104. *From:* kernel #39 with #60,
  round 20.
- **L-185. A rule can change between our comment and the contributor's
  push.** AGENTS' `userdata`-through-`install-phone` exception (`10daf5f`)
  landed after our follow-up on #25 and before its next push, so a PR that
  did everything asked now broke a rule its author never saw. *Check:* `git
  log --since=<our last comment> -- AGENTS.md CONTRIBUTING.md` before judging
  a re-push, and say in the comment which rule is new. Extends L-31 and
  L-124. *From:* #25, round 20.
- **L-196. A stack of N PRs is gated once at its top and read N times.**
  Kernel #73-#79 are one linear chain on today's base; `kernel-pr-check
  --build --merge` on each head rebuilt the same objects seven times, while
  the per-commit builds (L-179) and the parent-name audit (L-193) on the top
  head covered everything in one pass. *Check:* `git log base..headN` for
  each PR to prove the chain, gate the top head, build the chain commit by
  commit, and give one merge plan (merge the top PR, close the rest) next to
  the one-by-one order. *From:* kernel #73-#79, round 21.
- **L-197. A status word we ask for is checked against the legend and the
  site's parser before we post it.** Our "the matrix row says 'in review'"
  on #52 produced a row whose every cell the website renders as "no"
  (`devices.ts` `parseCell`). *Check:* `grep` the legend in DEVICES.md and
  `STATUS_WORDS` in `omamobile-website/src/lib/devices.ts` for any status
  wording we prescribe. Extends L-31 and L-66. *From:* #52, round 21.
- **L-198. When the contributor says the record doesn't exist, the file
  records that it doesn't, and a baseline taken over an unexplained change
  is downgraded, not adopted.** #35's reply gave a negative record (no date,
  tool, partition list or boot list) and accepted the hold, while the plan
  still said "the new baseline" and "a Linux slot A boot does not run the
  modem stack". *Check:* the negative facts land in NOTES and Risks in the
  contributor's words; the unexplained copy is "current contents, cause
  unknown"; the baseline becomes the backup after the next stock boot.
  Extends L-34, L-168 and L-186. *From:* #35, round 21.
- **L-199. A read point we prescribe is named relative to the driver's last
  write, not to a phase.** "Right after link-up, before MHI power-up" under
  ath11k is after `ath11k_pci_soc_global_reset()`, and the read hung; the
  same phase on stock (`linkup`, no reset) read fine six times. *Check:*
  before asking for a register read, list the driver's writes to the block
  up to that point in both trees, and name the read as "after write X,
  before write Y". Extends L-135 and C-7. *From:* issue #36, round 21.
- **L-215. A vendor-kernel A/B outranks host-side hypotheses.** On issue
  #36 the stock kernel stalled exactly like mainline, retiring every
  host-driver difference at once, while we were still asking for host-side
  changes. *Check:* before asking for one, ask whether the stock kernel ran in
  the failing shape, and list what differs between the stock run that works
  and the one that doesn't. Extends L-204. *From:* issue #36, round 22.
  (Corrected 2026-10-28, C-12: "a vendor-kernel A/B" means a one-variable
  A/B; a stock run that differs in host and timing at once rules out
  neither.)
- **L-216. A re-push that answers our requests is trailer-checked on every
  commit.** #77's re-push appended our sentence below its `Link:`, turning the
  trailer into body text. *Check:* `git interpret-trailers --parse` on each
  commit of the new head against the old head's. Extends L-119 and L-183.
  *From:* kernel #77, round 22. (Extended 2026-11-23: a trailer can also
  vanish. Every commit of #931 to #936 lost its `Co-Authored-By` line in one
  re-push, and the new sibling #974 had none; neither `tools/pr-check` nor a
  range-diff summary flags a removed trailer. Compare `git log --format='%h
  %(trailers:only,unfold)'` on the old and new heads for every PR of the
  author, and ask once for the series. *From:* #931 to #936 with #974, round
  66.)
- **L-217. A version we ask a contributor to take can be taken by main
  first.** We asked #78 for 0.2.30; #90 shipped it an hour after his push.
  *Check:* list the maintainer's open and local branches' versions of the
  package and ask for the first free one, or say "the next free version at
  merge" and set it ourselves. Extends L-12. *From:* #78, round 22.
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
