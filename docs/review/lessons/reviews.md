<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Reviews and merging (part 1 of 2)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-773. A PR that keeps a "switch off" copy of main's functions is merged
  by hand onto today's main and tested under both switch values, even when
  GitHub shows no conflict in that file.** #577's off block copies the old
  `short_press`, so git applied #640's hunk (a new `panel_dark` and
  `wait_screen_off`) to the copy: two `panel_dark` definitions, the helper
  missing with the switch on, and main's new test failing there. *Check:* `git
  merge --no-commit` in a scratch worktree, `grep -n '^[a-z_]*() '` for a name
  defined twice, and each test with the switch on and off. Extends L-423 and
  L-280. *From:* #577 with #640, round 52, 2026-11-11.
- **L-772. A document an agent is told to read in full is kept small enough
  to read in one go, and the reader reports what it actually read.**
  `docs/review/LESSONS.md` had outgrown one read, and six of round 52's eight
  reviewers read only its first 700 or 2,250 lines, which showed only when
  they reported it. The lessons are now split into `docs/review/lessons/*.md`,
  each fitting one read. *Check:* `tests/review-lessons` (it fails on a file
  over 40 kB, a number used twice or missing, and an unlisted file), and each
  review lists the lesson files it read, with their line counts. *From:*
  round 52, 2026-11-11.
- **L-745. "I'll set the version when I merge" is a push to the branch, not a merge option.** A squash lands the branch's files as they are, and a `version` equal to main's raises no conflict; #628 came back with both requests met and the version still at the number main had taken, as we had told its author to leave it. *Check:* when a draft promises a version at merge, the merge plan carries an explicit "push `<version>` to `<owner>:<branch>`" step before the squash, and the next round compares `git show <head>:packages/<p>/version` with main again. Extends L-426, L-404 and L-551. *From:* #628, #640, #642, round 51, 2026-11-11.
- **L-722. A conflict with a same-day redesign of the same handler is reviewed
  as "what does the PR still add", never resolved in a scratch merge.** #582
  and #612 conflict with #643's Back (`BackLink.js`); taking #582's side drops
  keyboard-first and terminals-go-home, and keeping both in #612 compiles and
  puts Search ahead of the keyboard. *Check:* per conflicted file, list main's
  behaviours the PR's side lacks, read main's header comment and the tests
  that enumerate participants (`test/back-surfaces.py`'s `EXPECT`), and ask
  for a rebuild on main with the PR's additions named. Extends L-184 and
  L-431. *From:* #582 and #612 with #637 and #643, round 50.
- **L-721. Two open PRs where one parses a line of a user's file and the other
  rewrites it are a design conflict git doesn't show.** #581 reads `local
  omarchy_monitor_scale = <number>` with a regex; #635 turns that line into a
  function call, after which #581's helper defers at every login and writes no
  defaults. *Check:* `git grep -n '<the line's left-hand side>'` over every
  open PR head that touches the script seeding it, and say in both reviews
  which merges first. Extends L-424 and L-478. *From:* #581 with #635, round
  50.
- **L-720. A second contributor's feature for a phone is checked against the
  first owner's open draft for the same thing.** #626 and #374 both add a 9a
  earpiece route, 10 dB apart and with different tuning. *Check:* `gh pr list
  --search "<device> <feature>"`, grep the open drafts' diffs for the controls
  the PR writes, and name the difference for the maintainer before either
  merges. Extends L-169 and L-277. *From:* #626 with #374, round 50.
- **L-719. A merge condition that waits for a rare failure to recur gets a
  bound for the case where it doesn't.** We held kernel #224 for "one console
  that places the core"; at about 1 in 150 sleeps the hang may not return for
  nights, and absence can't meet a condition phrased as a console. *Check:*
  when setting such a condition, say in the same comment how many clean cycles
  with the instrumentation on are enough to merge without it. Extends L-440
  and L-482. *From:* kernel #224, round 50.
- **L-718. A guard change left without a version bump "for the merge" is
  re-checked when its trigger merges.** #594's two blacklist lines had no
  bump, harmless until kernel #237 merged the nodes that make udev load the
  modules, the same day. *Check:* for a guard change without a version, list
  what triggers the guarded thing (a DT node, a config line) and whether it
  merged since the last round; if so, the bump and the merge go first. Extends
  L-37 and L-442. *From:* #594 with kernel #237, round 50.
- **L-690. A third party's failure report on a draft is checked against main
  before the design discussion goes on.** On #582 a 9a owner reported that the
  Escape dispatch main ships answers "key not found" under Hyprland 0.57,
  after our round-48 comment had said every phone runs it and asked the author
  to prove the failure. *Check:* grep main for the failing command
  (`BackModel.js`), compare the version its comment names (0.56) with what
  phones run (0.57.0), and put a reference-phone reproduction in the round's
  decisions; a bug on main gets its own issue or PR. Extends L-520 and L-492.
  *From:* #582, round 49, 2026-11-10.
- **L-689. A commit-body line that starts with `#N` is deleted when a rebase
  re-edits the message.** Git takes it for a comment: #389's `76dc2a29` lost a
  line beginning "#398 added …" and now reads as a broken sentence. *Check:*
  read the message hunks of every range-diff after a rebase; with
  `COMMIT_MESSAGES` squashes the broken body lands on main unless the squash
  body is written by hand. Extends L-312. *From:* #389, round 49, 2026-11-10.
- **L-688. Requests left unanswered after a contributor's push are re-listed
  in full in the numbered list, wording points included.** #330's four points
  were posted five minutes before an unrelated correction and went unanswered
  through two more pushes; "stock" was corrected on neither #330 nor #505
  after round 48, having sat under "two wording points" at the end. *Check:*
  `git grep -n` the exact strings each open point asked for (hashes, phrases,
  the word) on the head, in the sibling PR's files too; when all are missing,
  compare timestamps for a crossing before reading it as a refusal. Extends
  L-648 and L-124. *From:* #330 and #505, round 49, 2026-11-10.
- **L-687. A merge condition "shown not to be this PR's" names its
  discriminator when it is set.** Kernel #224 waited on a comparison run
  without its commits; at a failure rate near 1 in 150, with the unfixed bug
  ending the comparison first, that run can't answer in a night, and the
  thread drifted to "it isn't against this PR" by inference. *Check:* when a
  merge waits on attributing a rare failure, estimate the runs needed from the
  observed rate, and prefer evidence one failure can give (`pm_print_times`,
  `pm_debug_messages`, `panic_on_rcu_stall`, a stack). Extends L-482. *From:*
  kernel #224, round 49, 2026-11-10.
- **L-686. A lesson that names an open PR is run as a check in that PR's next
  round, not left as a note.** L-494 had named #403's `snprintf` in
  `reboot-to.c` since round 42, but the thread never got it; linking the file
  the no-bootctl way (two minutes, no network) made it a blocking finding.
  *Check:* at the start of a later round, `grep -rn '#<N>'
  docs/review/lessons` and run each check the hits name. *From:* #403, round
  49, 2026-11-10.
- **L-340. After a rework that narrows a PR to one device, the description and
  the first commit still describe the old scope, and a squash publishes
  them.** #135's body and first commit say the reorder and the rate in `state`
  apply to every phone (cheetah 60 Hz); the second commit made both 9a-only.
  *Check:* after a narrowing rework, read the body and every commit message
  against the head's code, and have the maintainer write the squash body.
  Extends L-279 and L-312. *From:* #135, round 29.
- **L-339. A docs PR that grows after "ready to merge" is re-read push by
  push, with a duplicate check.** #138 gained eight commits (166 lines) after
  our near-final comment: the title went stale again, one paragraph landed
  twice verbatim, and the new "next step" was an unattended run that accepts
  watchdog resets with the modem up. *Check:* `git log <last reviewed
  head>..<head>`, then `awk 'length>200' <file> | sort | uniq -d` for repeated
  paragraphs, and grep the new text for "hands-free", "unattended" and "at the
  price of". Offer a split when the late commits are another subject. Extends
  L-274 and L-34. *From:* #138, round 29.
- **L-338. A survey across open PRs uses `gh` or `ls-remote`, never a wildcard
  fetch into the shared clone.** In round 29 a `git fetch origin
  '+refs/pull/*/head:refs/remotes/origin-pr/*'` created 122 refs in the
  maintainer's checkout (removed again, each checked by its reflog's creation
  line). *Check:* survey with `gh api repos/<r>/contents/<path>?ref=<sha>`, or
  fetch per-PR `review/prN-rR-<topic>` refs that go on the cleanup list.
  Extends L-127 and L-194. *From:* round 29 (a near miss).
- **L-337. A request to put an option in a device `kernel.config` is checked
  against RELEASES first.** That fragment is for options that would break
  another device, and only during bring-up: the release kernel (§4) is one
  build from the shared fragment. We asked panther for `FT3658=m` there, which
  no other phone minds, so a release kernel would have shipped panther without
  touch. *Check:* before asking for a device-only config line, ask whether the
  option can break another phone; if not, ask for it in
  `kernel/configs/omamobile.config`, or say it's bring-up only and when it
  moves. Extends L-31 and narrows L-314's last sentence; see C-21. *From:*
  kernel #109 with #149, round 29.
- **L-312. With `squash_merge_commit_message: COMMIT_MESSAGES`, a squash
  carries every commit's body, including wording the review rejected.** #125's
  first commit says "mark B successful on the first good boot after a flash",
  the standing permission round 25 turned down. *Check:* `gh api repos/<r>
  --jq .squash_merge_commit_message`, then read each commit body on a safety
  PR; any body the final text contradicts means writing the squash body by
  hand. Extends L-279. *From:* #125, round 27.
- **L-292. Merge only after every check has finished, not on the first
  green.** #126 was merged with the policy job passed and the tests job still
  pending; the tests passed afterwards, but the merge didn't know that.
  *Check:* `gh pr checks N` shows no pending job (or `gh run watch
  --exit-status`) before `gh pr merge`. Extends C-15. *From:* #126,
  2026-10-28.
- **L-291. When the bottom of a squash-merged stack moves after we've posted a
  cherry-pick plan, re-simulate the plan.** #115 and #117 still carry #99's
  old head, and #117's list grew from two commits to three. *Check:* squash
  the new bottom onto main, cherry-pick the listed commits, and diff the
  result against the top head, expecting only the bottom's new change. Extends
  L-195 and L-214. *From:* #99, #115, #117, round 26.
- **L-287. A silent re-push is diffed per PR before any reply.** The tegu
  stack's 20:38Z push looked like an answer to everything but carried only the
  Makefile resolution; #106's and #122's points were untouched. *Check:* `git
  range-diff` against the last round's refs, then one status line per open
  point rather than a re-post. Extends L-183 and L-248. *From:* kernel #80 to
  #122, round 26.
- **L-279. A PR that carries a merged fix PR's commits is diffed against main,
  and its squash body written by hand.** #101 still carried #107's audio
  commits; `git diff origin/main <head> -- packages/omamobile-audio` was
  empty, but GitHub's default squash body would still list "omamobile-audio
  0.5.5" under the fingerprint title. *Check:* after the fix PR merges, diff
  each rider against main for the fix's package. Extends L-255. *From:* #101,
  round 26.
- **L-278. A re-pushed stack with identical sources is proved once.** Where
  every PR's tree id equals the old head's, the review is tree ids plus a
  range-diff per PR, then one gate on a scratch rebase of the top; DTB hashes
  of old head and rebased head carry the earlier content review over. *From:*
  the tegu stack, round 25 (12 heads, one message change).
- **L-277. A promised userspace guard is checked in every open package for
  that device, other owners' included.** Kernel #90 was accepted on W4HO's
  promise that `allow_tx` is set only for `google-tg4c`; h4rkl's #74 sets
  `allow_tx=1` for every panel, and our #74 review missed it (C-18). *Check:*
  `git grep -n '<option>'` across the open omarchy-mobile PR heads for
  `packages/omamobile-device-<codename>`. Extends L-219. *From:* kernel #90
  with #74, round 25.
- **L-275. Squash-merged stacks always conflict on the package `version` file,
  and a PR carrying a merged fix's commits can't simply be rebased.** #115
  carried #107's three commits, which main has as one squash. *Check:*
  simulate the chain with `git merge-tree --write-tree` and `commit-tree`, one
  squash after another, then hand over a cherry-pick of only the PR's own
  commits, verified to reproduce the head's package tree. Extends L-39, L-214
  and L-255. *From:* #115 and #117, round 25.
- **L-274. A PR we marked "nothing more needed" is checked push by push from
  the head our comment named.** Kernel #82 was pushed at 21:43Z without a
  comment and again at 01:04Z; comparing only the last two heads would skip
  the one we reviewed. *Check:* list every force-push event since our comment
  and range-diff each. Extends L-34 and L-166. *From:* kernel #82, round 25.
- **L-270. An "or keep X and say so" we offer must pass the gates the same
  review names.** Round 24 on kernel #98 asked for the eight required
  supplies, which `dtbs_check` enforces, and also offered keeping the fixed
  regulator, which can't pass CONTRIBUTING's no-new-warnings rule. *Check:*
  run each alternative in a draft past every blocking point in the same draft
  and §6's gates. Extends L-229; see C-16. *From:* kernel #98, round 25.
- **L-265. A bare `#N` links to the repository the comment is in.** W4HO's
  tables on issue #28 named kernel PRs as `#119` and `#122`, which link to an
  omarchy-mobile PR and issue. *Check:* write
  `derekross/linux-omarchy-mobile#N` when a comment names the other
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
