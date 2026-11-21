<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Reviews and merging (part 1 of 3)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
  #581, round 63, 2026-11-20.
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
