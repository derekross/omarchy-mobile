<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Reviews and merging (part 2 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-940. Open PRs that each add "the next patch number" merge with no
  conflict and leave several files with one number.** #879, #610 and #924 each
  add `patches/0032-...` under different names: git sees new files, all apply,
  the `version` file is equal in two of them, and the series' order is no
  longer unique. *Check:* each round, list `patches/NNNN-*` added by every
  open PR for the package (`gh pr list --json files`, or `gh api
  .../pulls/N/files`), flag equal numbers, grep each PR's tests and docs for
  the number, and give the order and the rename, with the version, in every
  one of the reviews. Extends L-426 and L-550. *From:* #879 with #610 and
  #585, round 61, and #924, round 63, 2026-11-20.
- **L-936. A rework that answers a review is checked for which runs in the
  description still describe it.** #866's description still reported a value
  "about 2 s later" and a lock "30 s later without a shell restart" from the
  first version; neither behaviour existed at the new head, and the squash
  would have published three superseded commit bodies. *Check:* after a
  rework, strike each sentence of the description's test section that names a
  value or step the diff removed (`git diff <old head> <new head> | grep '^-'`
  for the numbers), and list what is left as evidence. Extends L-340, L-436
  and L-312. *From:* #866, round 61, 2026-11-18.
- **L-934. A merge order or future number we promise between two PRs is
  re-derived each round, and said on the thread of every PR it renumbers.**
  Round 60 told #860 and #866 "I expect #866 first"; a day later #866 waited
  on a new patch PR and two phone runs while #860 had become inert. A comment
  on #879 said "#610 then takes 0.1.50 and 0033" while #610's own thread said
  only "0.1.49 is right today", so its author re-confirmed the old numbers,
  and two newer PRs had made the promised ones wrong too. *Check:* for each "X
  first" in our last comments, list what each PR still waits for today and say
  when the order flips; when a draft names another PR's future number, add the
  same sentence to that PR's draft, or say "the next free number, set at
  merge" in both. Extends L-519, L-551 and L-426. *From:* #860 with #866 and
  #879, round 61, and #610 with #879, #920 and #924, round 63, 2026-11-20.
- **L-927. A package PR's line count is split into vendored, generated,
  fetched-at-build and new code before anything is read, and the review says
  what it read of each.** #888's 13,384 lines held no vendored source: 11,700
  were new C, 7,100 of them inside patches against an upstream fetched at
  build time, where "new" hides behind diff context. *Check:* per file, `wc
  -l`, and for a patch `grep -c '^+'`, `'^-'` and `'^ '`; grep every added
  line for
  `g_spawn|system|popen|exec|fopen|g_file_|soup_|socket|getenv|dlopen`; read
  in full whatever handles input, text or files; list the rest as unread.
  *From:* #888, round 61, 2026-11-18.
- **L-923. A fix PR is searched against the open PRs for the same symptom
  before its code is read, our own open promises included.** #886 arrived five
  days after #727 for the same portal bug with the same fix; #727 was waiting
  on a Pixel 7 Pro run we had promised, so the second contributor spent a day
  on a bug whose fix sat unmerged because of us. *Check:* `gh pr list --state
  open --search "<the user-facing words>"` and the open heads' file lists for
  the file the fix edits; when there is a twin, say so in both threads, name
  which lands and why, and credit the first report in the squash body. Extends
  L-720 and L-480. *From:* #886 with #727, round 61, 2026-11-18.
- **L-922. A draft whose author named their own missing check is asked for
  that check first.** #745's body ended "nobody has watched the screen ...
  I'll look at it in the morning"; five days later nothing was posted and the
  timings were still the only evidence. *Check:* read a draft's body for "not
  tested", "I'll look" and "tomorrow", and put each at the top of the reply
  with the date it was promised. Extends L-360 and L-480. *From:* #745, round
  61, 2026-11-18.
- **L-921. An open PR that edits a function main has since copied behind a
  switch is reviewed as "which copy, under which switch value", before any
  rebase.** #577 left `omamobile-keys` with two `wake_locked` definitions (the
  new order, and the old one behind the switch); #745's hunk predates both,
  and part of what it proposes for every phone is what main deliberately keeps
  off on the reference phone. *Check:* `grep -n '^<fn>() ' <file>` on today's
  main for every function the PR's diff touches; when there are two, name the
  switch, say what the PR does under each value, and ask for the test under
  both. Extends L-773 and L-615. *From:* #745 with #577, round 61, 2026-11-18.
- **L-919. A request to "leave out" a sentence is checked for the code that
  sentence described.** We asked #582 to drop a README line about personal
  clones; the rebuild kept the idea and moved it into `Back.qml` as a Loader
  with a readiness gate in front of the registry, plus a test file for it.
  *Check:* for each "leave out X" in our last comment, grep the new head for
  X's nouns in code and tests, not only in the file we named. Extends L-183
  and L-688. *From:* #582, round 61, 2026-11-18.
- **L-911. A versioned `depends` on a number that is not yet on main is a
  claim on that number, re-checked every round and at the squash.** #697's
  bridge asks for `omamobile-modem-sit>=0.3.37`, the branch's own number; main
  reached 0.3.43 without the feature, so the published package satisfies it.
  #866 requires `omamobile-omarchy>=0.1.49`, the version two other open PRs
  carry; if the wrong one lands first, the line is met by a package without
  the fix, with every `merge-tree` clean. *Check:* for each `'<pkg>>=<v>'` a
  PR adds, compare `<v>` with `git show origin/main:packages/<pkg>/version`
  and list every open PR that claims `<v>` (`gh pr list --search`); put "the
  providing PR merges as `<v>` first" in the merge plan of all of them.
  Extends L-639, L-477 and L-426. *From:* #697, round 61, and #866 with #879
  and #610, round 62, 2026-11-18.
- **L-910. When a draft's author hands it over in the thread, the review says
  who was asked, whether they answered, and what the other draft must drop.**
  #626's hand-over was offered by the maintainer and accepted by its author
  four days later, with no word from the other contributor and #374 still
  carrying the competing route. *Check:* read both threads for the last
  comment of each party after the offer, and put the open acceptance in the
  draft comment as a direct question. Extends L-720 and L-688. *From:* #626
  with #374, round 61, 2026-11-18.
- **L-906. A conflict in a defaults table is resolved key by key, because the
  PR's side is a snapshot of the table from before main's additions.** #374's
  `lib/paths.py` side lacked `follow_screen`, which main added for the 7 Pro's
  sleep with the modem up; "take ours" would silently remove a default every
  phone reads. *Check:* for a conflict inside a dict of defaults, diff each
  side against the merge base and keep every key main added; hand over the
  resolved lines. Extends L-184 and L-773. *From:* #374 and #376 against #791,
  round 61, 2026-11-18.
- **L-899. A branch a contributor prepares on their fork for after a
  dependency merges is read and gated in the round that hears of it, against
  the dependency's head.** Kernel #202's side branch for the rebase onto #181
  was on the fork a day before it could be pushed; gating it twice caught a 90
  Hz mode the DECON refuses (L-898) and a clock skip (L-1071) before either
  reached the PR or a phone run that would have had to be repeated. *Check:*
  `git ls-remote <fork>` for the branch a reply names, fetch it into a review
  ref, and run `kernel-pr-check --build` with the dependency's head as BASE.
  Extends L-429 and L-196. *From:* kernel #202, rounds 61 to 63, 2026-11-20.
- **L-887. A "lands together with X" in our own comment is re-derived when
  the PR is cut down.** Round 52 tied #204 to #203 because it seeded a
  descriptor value; the cut-down hook reads nothing from #203, yet the
  coupling would have held an inert, tested change behind a PR waiting on
  decisions and a kernel. *Check:* after a rework, `git grep` the sibling PR's
  head for each path and key the reworked PR still reads; if none, say the
  coupling is gone and let the maintainer choose. Extends L-519 and L-250.
  *From:* #204 with #203, round 61, 2026-11-18.
- **L-852. When a fix adds the right lookup, grep for the wrong one it
  replaces.** Kernel #202 added `gs_decon_pick_lynx_soc()` in probe and left
  the broken `of_graph_get_remote_node()` test from the round before in
  `gs_decon_get_dsim()`, dead, on a path every board runs. *Check:* `git grep
  -n '<the compatible or symbol the fix keys on>' <head> -- <file>` and expect
  one hit. Extends L-183. *From:* kernel #202, round 60, 2026-11-17.
- **L-846. A review written but not posted is re-run against the head and the
  base, and its draft says how long the contributor has waited.** Kernel
  #264's file was held for two days; the head was unchanged, the base had
  moved under it, and the gate and the vendor's values were re-checked before
  reuse. *Check:* `git rev-parse` the head against the file's first line, `git
  diff --stat <old base> <new base> -- <the PR's directories>`, rerun the
  gate, then reuse. Extends L-195 and L-480. *From:* kernel #264, round 60,
  2026-11-17.
- **L-844. When the bottom of a stack is rebased, the PR above it is rebuilt
  on the new bottom with `git merge-tree --merge-base=<old bottom head>` and
  gated there, and the `--onto` command we hand over names the old bottom
  head.** Kernel #263 carried #181's previous head after #181's rebase; GitHub
  showed CONFLICTING with no CI, while the one commit applied cleanly on the
  new bottom with the same patch id. *Check:* `git merge-base --is-ancestor
  <bottom's current head> <top head>`; if it fails, find the old bottom head
  in the top's history, rebuild, compare `git patch-id --stable`, gate the
  rebuilt commit against the new bottom, and say whose conflict it is. Extends
  L-291, L-355 and L-644. *From:* kernel #263 with #181, round 60, 2026-11-17.
  (Extended 2026-11-24: the bottom can also move by a decision rather than a
  rebase. #1025 sat on #1015's `646f4e4e`, and #1015's `5594d02b` then removed
  the uninstall root helper and its polkit rule after the maintainer's
  decision, which #1025 still shipped; when the ancestor check fails, `git
  diff <bottom's current head> <head> --stat` lists the files the bottom
  deleted, and the review names each. *From:* #1025 with #1015, round 67.)
- **L-840. A PR that waits on our own phone run is given a merge slot ahead of
  sibling PRs on the same board file, and the wait is counted in rebases.**
  Kernel #181 had been ready for four days and was rebased again only because
  another PR landed in `gs201-panther.dts`; two more were queued behind the
  same file. *Check:* each round, for a PR whose only blocker is the
  maintainer's run, list the open PRs that touch its files and put it first in
  the round's merge order, or run the test before merging any of them. Extends
  L-253 and L-719. *From:* kernel #181, round 60, 2026-11-17.
- **L-839. A request left open on a PR at the top of an unmerged stack is
  re-listed when the stack's bottom is reviewed.** Kernel #120's message fix
  and our own 7 Pro capture sat for 20 days because #63 and #103 were the
  active threads. *Check:* when reviewing a stack's bottom PR, `gh pr list
  --search` for PRs whose head contains it and carry their open points into
  the same round. Extends L-196 and L-688. *From:* kernel #120 with #63 and
  #103, round 60, 2026-11-17.
- **L-838. "The contributor replied" is checked for who replied and whether
  the head moved.** On kernel #120 the new comment was a third party's data
  from another phone on an unpublished tree; the author's two open points, 20
  days old, were untouched. *Check:* `gh pr view --json comments` for each new
  comment's `author.login` against the PR's author, the force-push events
  since our last comment, and `git log -1 --format=%cI <head>`; list our open
  requests against the head before reading the new comment as an answer.
  Extends L-34 and L-688. *From:* kernel #120, round 60, 2026-11-17.
- **L-837. When main fixed the sentence a PR also fixes, the rebase drops the
  PR's hunk.** #98's WIFI-PLAN line and main's said the same thing in
  different words. *Check:* read both sides of a docs conflict for meaning
  before asking for "both"; name the side to keep. Extends L-184 and L-556.
  *From:* #98, round 60, 2026-11-17.
- **L-836. A one-line-per-device table row conflicts whenever two PRs change
  different cells of it, and the review hands over the answer cell by cell.**
  #98's Bluetooth cell and #751's Wi-Fi cell are the same line of DEVICES.md,
  and the Wanted row repeats both. *Check:* split the row on ` | ` at the
  base, main and the head, list which cells each side changed, and write
  "main's row with this PR's cell N" in the comment; do the same for the
  Wanted row (L-132). Extends L-184 and L-354. *From:* #98 with #751, round
  60, 2026-11-17.
- **L-828. A tested commit that a force-push took off the PR branch is fetched
  by its full id and diffed by tree.** #438's run was on a commit two pushes
  behind kernel #202's head; `gh api repos/<r>/commits/<short id>` gave the
  full id, `git fetch <remote> <full id>:<own ref>` brought it, and `git diff
  --stat <tested> <head>` showed two files, neither on the unit's path.
  *Check:* resolve the short id through the API, fetch it into a ref of your
  own, and compare blobs for the files the run exercised. Extends L-166, L-45
  and L-646. *From:* #438 with kernel #202, round 60, 2026-11-17.
- **L-814. Two PRs from one contributor that claim one version are also
  checked against what that contributor's phone has installed.** #806's test
  put a locally built `0.1.14-1` on the phone; #836's later package under the
  same number would not install as an upgrade there, whatever order they merge
  in. *Check:* read the sibling PR's test report for `pacman -Q` and give the
  second PR the next number in its review. Extends L-426 and L-755. *From:*
  #836 with #806, round 60, 2026-11-17.
- **L-797. A plan PR that merges on "the points are in" leaves a list of what
  its thread reported after the last push, and the safety part of that list
  goes to the maintainer the same day.** #758's branch stopped at 04:21Z; by
  15:01Z its thread held two SoC hangs on the published kernel, which #846 was
  already citing and no issue or AGENTS line recorded. *Check:* at the merge
  round, list every result posted after the head's commit time, ask for the
  follow-up by name, and for any hang, reset or data loss on a published
  kernel check that an issue exists (`gh issue list --search`) before the PR
  closes. Extends L-266, L-339 and L-657. *From:* #758 with #846, round 60,
  2026-11-17.
- **L-790. A PR that merged main after a redesign of its file is reviewed as
  `git diff origin/main <head>`, and its title and first commit are read
  against that diff.** #841's 31 lines after #848 were a hoist of #848's own
  checks; the commit body still said it replaced a check that main kept.
  *Check:* `git merge-base origin/main <head>` equal to main's tip means the
  two-dot diff is the whole change; then grep the first commit's body for
  "replaces", "removes" and "only" and test each against the head. Extends
  L-340 and L-372. *From:* #841 with #848, round 60, 2026-11-17.
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
  `git grep -n '<option>'` across the open omamobile PR heads for
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
