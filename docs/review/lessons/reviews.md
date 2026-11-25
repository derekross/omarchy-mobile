<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Reviews and merging (part 1 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-1177. When main is merged into a contributor's branch after another bump
  of the same package, the version file is read again before the squash.**
  #905 was merged as `omamobile-shell` 0.2.143, but in the merge its version
  file had silently taken main's 0.2.142 (#1036 fixed it). *Check:* after the
  merge and before `gh pr merge --squash`, compare `git show
  HEAD:packages/<p>/version` with `git show origin/main:packages/<p>/version`
  and with the number the PR names; the head's must be the higher. Extends
  L-404 and L-12. *From:* #905 and #1036, the maintainer's assistant,
  2026-11-24.
- **L-1176. When a decision and the contributor's reply cross by minutes, the
  next comment says so and turns the decision into the exact edit.** #1005's
  author wrote "I'll wait for your call; say so and I'll split" four minutes
  after the decision was posted, so a bare "see the decision" would cost a
  round; the edit itself (two variables in two files, and why the AoC still
  has Trusty) is what lets him act on it. *Check:* compare the decision
  comment's `createdAt` with each later author comment; when the reply doesn't
  refer to it, put the decision's consequence into concrete file changes in
  the draft, tried once in scratch. Extends L-124 and L-520. *From:* #1005,
  round 67, 2026-11-24.
- **L-1175. When the maintainer says in one twin's thread which twin he
  expects to take, the same sentence goes into the other twin's thread in the
  same round, and a later rework of the other is read as a sign it didn't.**
  On 11-18 #886's review said "I expect to take this one and credit #727's
  find"; #727's thread heard nothing, and its author reworked it on 11-24 to
  the round-56 points. *Check:* for each pair L-923 finds, `gh api
  repos/<r>/issues/<n>/comments --jq
  '.[]|select(.user.login=="<maintainer>")|.created_at'` on both, and compare
  the last maintainer comment's date on each with the twin decision. Extends
  L-923 and L-910. *From:* #727 with #886, round 67, 2026-11-24.
- **L-1153. A device plan's "before X comes to a PR" item is grepped when X
  arrives from another contributor.** The tegu SLEEP-PLAN's "What is left"
  item 4 asked for zuma's missing `pmu_cpuhp` handshake to be compared with
  gs101's before idle states reached a PR; kernel #280 brought them without
  it, and the plan's own sentence made that a question for the maintainer, not
  a note. *Check:* `git grep -n -i 'before .* comes\? to a PR\|before .*
  lands' origin/main -- device/<codename>/` for the feature's words at the
  start of any board PR on that device. Extends L-845 and L-723. *From:*
  kernel #280, round 66, 2026-11-23.
- **L-1152. A package comment that names a driver option's effect is re-read,
  in every open PR that repeats it, when a kernel issue shows the option isn't
  enforced.** Kernel #288 (the 8a's input limit not kept, `NO_AUTOIBUS` clear)
  landed between #899's push and this round; the same author fixed the
  sentence in `tools/husky-deadman` (#1008) that evening, while #899's
  `omamobile-charger.conf` and README still call `default_ilim_ua` a 500 mA
  input limit. *Check:* for a new kernel issue about a module parameter, `gh
  pr list --search '<parameter>'` and `git grep -n '<parameter>'` over the
  open heads' `packages/*/vendor/modprobe.d` and READMEs, and carry the issue
  into each review of the round. Extends L-1046 and L-957. *From:* #899 with
  #1008 and kernel #288, round 66, 2026-11-23.
- **L-1151. Two open PRs that place a new item at the same QML anchor
  expression collide on screen, whatever git says.** #994 moves the unread
  count to `callChipPill.visible ? callChipPill.right : clockText.right`;
  #1014 puts a recording chip at the identical expression with `z: 2`. Git
  reported a conflict only because #994 also moved a block; a resolution that
  kept both PRs' lines would compile and draw one item over the other.
  *Check:* for a shell PR that adds or moves an item by `anchors.*:`, `git
  grep -nF '<the anchor expression>'` over every open head that touches the
  same QML file, and write the chained anchor into both reviews. Extends L-104
  and L-722. *From:* #994 with #1014, round 66, 2026-11-23.
- **L-1117. Agreeing on "one helper for both" moves three things besides the
  code: an optional dependency becomes a versioned one, the helper's
  exit-status protocol has to be mapped to the caller's result format, and the
  merge order is fixed.** On #630 the page's `optdepends` on the shell, the
  runner's JSON-only reading of results and #954's status 75 would each have
  surfaced one round apart if only "drop the page's own copy" had been
  confirmed. *Check:* when confirming a consolidation, list the caller's
  `depends`, how it reads results, and each exit status and stream of the
  helper, in the same comment. Extends L-987, L-819 and L-911. *From:* #630
  with #954, round 65, 2026-11-21.
- **L-1116. When a contributor declines to delete a secret from an edit
  history, the review stops asking and puts the admin's own delete to the
  maintainer, with the author's reason beside it.** #630's author answered the
  third request with a plain no (a throwaway value on a development phone); a
  fourth request would only repeat the earlier rounds, while L-930 already
  says an admin can remove one revision without the author. *Check:* re-read
  the history through the API with the digits masked, name the revision by its
  timestamp, and write the two options (delete it yourself, or close the point
  on the author's word) into the maintainer's list, not into another request.
  Extends L-930 and L-688. *From:* #630, round 65, 2026-11-21.
- **L-1104. Two follow-ups invited in one review, on one function, conflict
  with each other; say the order when inviting them.** Round 63 named two gaps
  in `scan_identifiers`; the two PRs arrived an hour apart, each clean against
  main, and conflict on the line both needed. *Check:* when a review invites
  more than one follow-up in the same function, name which goes first, and at
  the next round build the combination once and run both PRs' tests on it.
  Extends L-104 and L-253. *From:* #959 with #961, round 64, 2026-11-21.
- **L-1103. A request for a run on a contributor's phone is checked against
  every hold we have placed on that phone.** Kernel #218's "one more boot" and
  #839's first-boot test both wait behind the pause asked on #714; a review
  that repeats the request without naming the hold asks for something its own
  author has forbidden. *Check:* before writing "please run", `gh pr list
  --author <login>` in both repositories and grep our last comments for
  "don't", "pause" and "until I"; name the hold and the order in the comment.
  Extends L-1044, L-557 and L-284. *From:* kernel #218 with #714 and #839,
  round 64, 2026-11-21.
- **L-1102. When a contributor repairs an undone commit by cherry-picking it
  back, the proof is the patch id, and the squash body is written by hand.**
  #917's re-applied commit and main's original have one `git patch-id
  --stable`, which closes L-1028's point in one line; but a COMMIT_MESSAGES
  squash would then land that commit's subject, body and trailers a second
  time under another PR's title, and credit its author for a change main
  already has. *Check:* `git show <c> | git patch-id --stable` for both; `git
  log --format='%an %s%n%(trailers:only)' base..head`; leave the re-applied
  commit's message and trailers out of the squash body. Extends L-1028, L-312
  and L-481. *From:* #917, round 64, 2026-11-21.
- **L-1101. A conflict in a one-line-per-device table is first asked "which
  row did main change?"; it can be the neighbour's.** #912's `docs/DEVICES.md`
  conflict read as "#912 and something else both changed the 9a's row";
  per-cell hashes at the base, main and the head showed main had changed no
  cell of it, only the Pixel 8 Pro's row on the next line, which git folds
  into the same hunk. *Check:* `git diff <merge-base> origin/main --
  docs/DEVICES.md | grep '^[-+]' | cut -c1-60` before writing who collides
  with whom, then the per-cell compare of L-836; the resolution is then
  "main's file with the PR's row". Extends L-836 and C-43. *From:* #912, round
  64, 2026-11-21.
- **L-1085. A round's brief can call a PR unreviewed when an earlier round
  posted on it; the thread decides.** Kernel #261 was listed as "no review";
  its thread held a posted review of the same head from two days before.
  *Check:* `gh api repos/<r>/pulls/N/reviews` and the earlier rounds' posted
  files before starting a full first review, then review what changed since.
  Extends L-34. *From:* kernel #261, round 63, 2026-11-20.
- **L-1080. A contributor's "refresh against upstream" merge commit is proved
  by comparing its tree with the automatic merge.** `git merge-tree
  --write-tree <old head> <merged main>` gives the tree git would make; `git
  diff --stat <that tree> <new head>` then lists exactly what was resolved or
  changed by hand (for #581, four README lines), and identical blobs for the
  PR's own files carry the earlier phone runs over without a re-test. *Check:*
  run both commands for every merge commit a contributor adds after a "ready"
  review, before reading anything else. Extends L-45, L-287 and L-357. *From:*
  #581, round 63, 2026-11-20. (Extended 2026-11-24: the same proof works for a
  contributor's own rebase that follows our prepared resolution, even when the
  base moved in between. On kernel #195, `git merge-tree --write-tree <new
  base> <our rebuilt commit>` gave a tree identical to the author's head two
  merges later, so our DTB comparison and gate carried over in one command;
  `git diff --stat <that tree> <head>` empty means the rebase is ours. *From:*
  kernel #195, round 67.)
- **L-1073. A new commit on a PR is checked against the list of open points
  before it is read as progress, and a commit that answers the sibling PR's
  question says nothing about this one's.** #829 gained a commit a day after
  three numbered requests; it answered a question from kernel #202 and left
  the overlay file byte-identical. *Check:* `git rev-parse <old head>:<file>
  <new head>:<file>` for each file a request named, before reading the new
  commit. Extends L-287 and L-688. *From:* #829 with kernel #202, round 63,
  2026-11-20.
- **L-1059. A new-device issue that asks "is anyone already working on this?"
  is answered the day it is opened, after a search for the codename.** #913
  asked and said its author would pause; #567 had added the same
  `device/<codename>/` nine days earlier; nobody replied, and two days later a
  second port of the directory existed, with a descriptor that disagrees and a
  lost `userdata` that #567's notes had already explained. *Check:* at issue
  intake and at the start of each round, `gh pr list --state open --search
  "<codename>"` in both repositories and `gh issue list --search
  "<codename>"`; link the two owners before either flashes. Extends L-720,
  L-557 and L-520. *From:* #914 with #913 and #567, round 63, 2026-11-20.
- **L-1052. A rebase-only push on a PR we called ready is proved by blob ids
  for the files that carry the work, and by diffing the two diffs for a hunk
  whose surroundings main changed.** On #651, three `git rev-parse <old>:<f>
  <new>:<f>` pairs and `diff <(git diff oldbase old -- f | grep '^[-+]') <(git
  diff newbase new -- f | grep '^[-+]')` carried three rounds of mutation
  tests over in a minute. *Check:* GraphQL's `HeadRefForcePushedEvent` for the
  old head, then those two commands; re-run only the suite, not the mutations.
  Extends L-122, L-274 and L-646. *From:* #651, round 63, 2026-11-20.
- **L-1049. A guard rule change is checked against open PRs that assert the
  old rule in a checker, not only against those that conflict.** #916's
  `phone-smoke` row requires disk `ro` 1, merges cleanly with #484 and would
  fail on every phone #484 targets afterwards. *Check:* `gh pr list --search
  "<guard term>"`, then grep each head's `tools/phone-smoke` and tests for
  `/ro` reads on whole disks. Extends L-721 and L-424. *From:* #484 with #916
  and #919, round 63, 2026-11-20.
- **L-1045. A PR held for a reporter's rerun is re-read against that rerun and
  against the upstream version phones moved to in the meantime, before it is
  "brought up to date".** #440 was merged up to main and renumbered with two
  negative reruns on its issue and Omarchy 4.5's lock, which pauses
  fingerprint retries while blank, now on every phone; there the change only
  lengthens the claim held after blanking. *Check:* for every PR whose body
  says "the reporter's measurement decides", read the issue's comments since
  the PR's first push, and re-derive the change's effect in the pinned
  upstream version (`bsdtar -xf` the cached signed package, read the handler).
  Extends L-435, L-519 and L-555. *From:* #440 with issue #422, round 63,
  2026-11-20.
- **L-1035. A "don't fail on a missing directory" request made of a default-on
  check is re-read when the check becomes opt-in.** What was fail-safe for
  everyone is fail-open for the one who asked for the check. *Check:* when a
  rework changes who a check runs for, list our earlier requests about its
  failure behaviour and re-derive each for the new audience. Extends L-31 and
  L-519. *From:* #855, rounds 60 and 63, 2026-11-20.
- **L-1031. Two open PRs that state opposite rules for one flag are a design
  conflict even where a third case lets them coexist; the review of each names
  the state the other leaves.** #484 says "no disk's own flag is ever set";
  #919 sets `sda`'s when the allowlist is closed, and #916 then checks every
  disk's flag on a RAM-only phone, which #484's boot LUNs would fail. *Check:*
  for each open PR touching `ufs_ro_pass`, write the (node, disk flag,
  partition flag) triple it leaves per LUN for each mode (allowlist, closed,
  NFS), and lay the tables side by side before giving a merge order. Extends
  L-430 and L-721. *From:* #919 with #484 and #916, round 63, 2026-11-20.
- **L-1028. A PR's diff against its merge base is read for hunks that undo a
  commit already in that base, and a clean `merge-tree` says nothing about
  it.** #917's base contained a day-old fix; the head had the file as it was
  before it, so GitHub showed "mergeable", CI was green (the tests that would
  have failed were removed in the same diff) and the fix would have been
  reverted under a title about another phone. *Check:* `git log --format=%h
  <merge-base> -5 -- <each touched file>`, then for each of those commits `git
  show <c> -- <file> | grep '^+'` against the head's file; or try `git
  cherry-pick -n <c>` on the head: a commit that is in the base and still
  applies cleanly has been undone. Extends L-252 and L-357. *From:* #917,
  round 63, 2026-11-20.
- **L-1021. A PR that was "message only" last round is diffed by stat against
  the reviewed head before its message is read.** Kernel #249's five
  force-pushes after the review were described as message fixes with identical
  trees, which was true of the last push and of the DTS; an earlier push had
  added a Makefile line that turns on DTB symbols for the board. *Check:* take
  the reviewed head from the last round's file, `git diff --stat <reviewed
  head> <head>`, and for every file not in the previous list read the hunk and
  look for its sentence in the commit message; GraphQL's
  `HeadRefForcePushedEvent` lists the pushes in between. Extends L-274, L-287
  and L-743. *From:* kernel #249, round 63, 2026-11-20.
- **L-1004. Two pull requests with the same fix are compared by what else they
  carry (version, kind of test, evidence), and the one that doesn't land is
  credited in the other's squash body.** #904 and #911 change one line
  identically; they differ in a behavioural check against a source grep and in
  the version bump. *Check:* `git diff <A> <B> -- <the fixed file>` to confirm
  only comments differ, then compare tests and `version`, and carry a
  `Co-authored-by` for the earlier author. Extends L-720 and L-481. *From:*
  #904 with #911, round 63, 2026-11-20.
- **L-1003. Before suggesting a simpler form of a contributor's guard, run the
  simpler form once.** That `Qt.callLater(f)` folds repeated calls is in Qt's
  documentation, but whether it holds for a QML-declared function reached as
  `root.f` was worth ten lines: a core-application QML file run with `qml
  --apptype core` printed one rebuild for ten signals on Qt 6.12.0. *Check:* a
  QML file with no window under the review's scratch folder, and the result
  quoted in the comment with the Qt version. Extends C-34 and L-229. *From:*
  #905, round 63, 2026-11-20.
- **L-1002. The head a posted review is attached to can be newer than the head
  the review read.** Round 62's file for #888 named one head; GitHub recorded
  the review on the next, pushed in between, and the seven lines between them
  had no reader until the following round. *Check:* at the start of a
  follow-up round compare the earlier review file's head with `gh api
  repos/<r>/pulls/N/reviews --jq '.[].commit_id'`, and diff the two when they
  differ, before diffing "since the last review". Extends L-34 and L-274.
  *From:* #888, round 63, 2026-11-20.
- **L-987. When a tool gains a mode "for the tests" beside a page that
  carries its own copy of the same logic, the review asks which one is the
  writer.** #954's `--change` and #630's `pin.py` both drive `passwd` in a
  pty, with different length limits and different rules for a slow `passwd`.
  *Check:* `git grep -n 'pty.fork\|/usr/bin/passwd'` over the open heads of
  one author's PRs for the feature, lay the limits and timeouts side by side,
  and put the question of one helper to the maintainer in both reviews.
  Extends L-709 and L-720. *From:* #954 with #630, round 63, 2026-11-20.
- **L-977. Notes for a release that didn't ship are closed with their PR and
  removed from main when the respin's notes land.** #479 sat open for eleven
  days after 2026.11.08 shipped, and main still carried `2026.11.03.md` with a
  download address that answers 404. *Check:* when a release-notes PR merges,
  `git ls-tree origin/main docs/release-notes/` against `git ls-remote --tags
  origin 'release-*'`, and `gh pr list --search "release notes"` for open
  notes PRs of versions that have no tag; each extra file or PR is closed or
  marked "never published". Extends L-653 and L-774. *From:* #479, round 62,
  2026-11-18.
- **L-972. A docs line we ask a contributor to change is merge-tested against
  the maintainer's own open docs PRs.** The requested edit to INSTALL.md's
  programs line sat directly under a line #843 rewrites, and the two conflict;
  the same information one paragraph down merges cleanly. *Check:* `gh pr list
  --json number,files` for the doc, then `git merge-tree` of the PR with the
  requested change applied against each. Extends L-104 and L-184. *From:* #877
  with #843, round 62, 2026-11-18.
- **L-971. A request from an earlier round is checked against what main
  merged since, before it is repeated or pushed.** Round 61 asked #877 for a
  program guard in `tests/install-slot-descriptor`; #893 merged the same
  afternoon with exactly that, so repeating the request (or pushing it) would
  have conflicted with main for nothing. *Check:* `git log <last round's
  main>..origin/main -- <each file a request names>` at the start of the
  round. Extends L-147 and L-423. *From:* #877 with #893, round 62,
  2026-11-18.
- **L-969. A "your branch conflicts with #N" example in a posted review is
  re-derived the next round; the example can go stale while the point
  stands.** Round 61 cited #652 for the `tests/all` loop-line conflict; hours
  later #652 conflicted with main by itself, and the live example was a PR
  opened since. *Check:* `gh pr list --json number,files` filtered to the hot
  file, then `git merge-tree` of the head with each, with and without the
  requested change. Extends L-549 and L-430. *From:* #875, round 62,
  2026-11-18.
- **L-967. A version commit pushed to a branch whose base predates main's own
  bump conflicts with main; merge main first.** #204's base had the shell at
  0.2.133, main moved to 0.2.134 and the branch needed 0.2.135: a `version`
  commit straight on the branch gives three different lines and a conflict,
  where the branch as it stood (equal to main) merged silently with no bump at
  all. *Check:* before writing a "push version X" step, simulate it (`git
  hash-object -w`, `update-index --cacheinfo`, `commit-tree`, then `git
  merge-tree --write-tree origin/main <commit>`); when it conflicts, make the
  step "merge main, then set the version", with `git diff --stat origin/main`
  listing the `version` file as the proof. Extends L-745 and L-426. *From:*
  #204 with #890, round 62, 2026-11-18.
- **L-959. A new package directory is published by default; "opt-in" in a
  PKGBUILD's comment is about phones, not about the build machine.** #888 came
  back with every request met and would still have been fetched, built, tested
  and signed by the next nightly, because `tools/build-packages` iterates
  `packages/*/` and leaves out only `NAMED_ONLY`. *Check:* for a PR that adds
  `packages/<new>/`, read `NAMED_ONLY` and the nightly's command at the same
  head, list the hosts its `source=` adds, and put "named only until the first
  watched build" into the merge plan as an explicit step when the maintainer
  asked for it. Extends L-554 and L-420. *From:* #888, round 62, 2026-11-18.
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
