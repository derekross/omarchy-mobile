<!-- SPDX-License-Identifier: MIT -->
# Review lessons: The gates themselves (part 1 of 3)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-1220. A rebuild-only pkgrel bump is shown resolvable on today's indexes,
  and its version compared with every repository's copy, because a "sorts
  above" rationale goes stale.** *Check:* a fake-root `pacman -Sp` on today's
  indexes, the new entry made by editing the published `desc` (copy the old
  entry, change `%VERSION%` and the one soname, repack), run once with the
  real index as a control; then `vercmp` the new version against every
  repository's copy. Extends L-524 and L-512. *From:* #1124, 2026-11-27.
- **L-1219. A process-list exception added to a "no other X is running" guard
  is mutation-tested rule by rule, because the rules overlap.** #1063's zombie
  rule passed its test with the line removed: the fixture's only zombie was
  the caller's child, which the descendant rule skips first. *Check:* remove
  each skip rule alone and run the test; a rule whose removal changes nothing
  either goes or gets a fixture only it covers (here a zombie with another
  parent). Extends L-1001 and L-684. *From:* #1063, round 69.
- **L-1218. A package test that fetches its pinned source is a network test
  even when the PR changes only its socket lines, and it is run offline or
  left to CI.** `omamobile-install-link/test/all` calls `./fetch-source` (a
  GitHub archive download) and `cargo build` whenever it can; running it to
  check #1090's socket change made the review machine fetch, before the
  reviewer read that far. *Check:* `grep -n 'fetch-source\|curl\|cargo\|git
  clone\|pip install' packages/<p>/test/all` before the first run, and set the
  package's offline switches (`OMAMOBILE_LINK_SRC=<an existing tree>`,
  `OMAMOBILE_LINK_NO_CARGO=1`) or leave that suite to CI. Extends L-681 and
  L-454. *From:* #1090, round 69, 2026-11-26.
- **L-1217. A package suite run in a container to reproduce CI is run on
  main's files in the same container before a red line in it is read as the
  PR's.** On #1014's merge, `test/sleepd.sh` failed in `omamobile-build:24.04`
  and passed on the laptop; main's own file failed the same way in the same
  container, so the line said something about the image, not the PR. *Check:*
  for each `not ok` in a container run, `docker exec` the same file from a
  worktree of `origin/main`, and compare with CI's log for that line. Extends
  L-42 and C-49. *From:* #1014, round 69, 2026-11-26.
- **L-1216. A new package's "test/all passes" is rerun from a clean checkout,
  because an ignored or unadded file passes on the author's tree.** #1101's
  `build` and test need `src/reboot-to.c`, which the commit doesn't contain;
  the author's run passed and a scratch merge failed at the first `cmp`.
  *Check:* for a new `packages/<p>/`, `git ls-files packages/<p>` against
  every path its `build`, `install`, README and `test/all` name (`grep -o
  'src/[^ "]*\|bin/[^ "]*\|vendor/[^ "]*'`), then run `test/all` on a worktree
  of the head; `git check-ignore -v` names a rule that hid a file
  (`packages/.gitignore` ignores `src/`). Extends L-586 and L-1120. *From:*
  #1101, round 69, 2026-11-26.
- **L-1215. `tests/grep-q-pipes` doesn't scan `device/*/` scripts either.**
  #1099's `device/tangorpro/extract-touch-fw` pipes into `grep -qE` under
  `pipefail` and the lint passed (its `scan` list is `tests
  'packages/*/test/*' bin tools rootfs`). *Check:* `git grep -nE
  '\|[[:space:]]*grep[[:space:]]+-[[:alnum:]]*q' <head> -- 'device/*'` on
  device PRs until the lint covers them. Extends L-817 and L-683. *From:*
  #1099, round 69, 2026-11-26.
- **L-1174. A mutation whose replacement text holds an `rm` on a variable is
  kept in a script file, not typed into the shell command.** In #1033's review
  the session's safety check refused a `python3 - <<'PY'` mutation because the
  anchor string contained `rm -f -- "$dir/$file"`, though nothing would run
  it; the same four mutations from a small script under the review folder ran
  at once. *Check:* write mutations as a `{name: (anchor, replacement)}` table
  in a file under the review's own folder and call it by name; the shell
  command then carries no destructive text. Extends C-53 and C-44. *From:*
  #1033, round 67, 2026-11-24.
- **L-1150. A staging or packaging check is run against a copy of a real
  artifact rewritten into each state the PR names, with main's tool and the
  head's side by side.** For #979, a 30-line newc rewrite of the last release
  initramfs (swap `init`, add or omit one `etc/` file) turned "fixtures pass"
  into a table: identical `SHA256SUMS` for the good build, and main staging a
  stale build and another phone's build that the head refuses. *Check:* copy
  the artifact to scratch, rewrite members with a script outside the worktree
  (key on the name without `./`), run both tools with `DEST` in scratch, and
  diff their outputs for the pass case. Extends L-1115 and L-896. *From:*
  #979, round 66, 2026-11-23.
- **L-1149. A protected-write PR built with a compile-time switch is proved by
  running every build it produces (with the switch, without it, and main's)
  over the whole input space in scratch, and diffing exit status and written
  bytes.** For #1011, three binaries over 11,520 synthetic `devinfo` cases
  (five layout versions, all 256 flag pairs, every verb on each slot, dry and
  confirmed) showed in seconds that lynx, the initramfs copy and the reference
  phone's 3.15 path are unchanged and that the new write is exactly the 32
  flag pairs the description names; six mutations of the condition then each
  failed the PR's own test. *Check:* `git show` main's and the head's source
  into scratch, `cc` each with and without the PR's `-D`, loop over generated
  images with each binary on its own copy, and print only the cases where
  status or bytes differ. Extends L-664, L-457 and L-8. *From:* #1011, round
  66, 2026-11-23.
- **L-1148. Two open PRs that each change a generator's output format are
  merged together in review, and the generator's own `--check` modes run on
  the merge.** #952 finds the end of the generated header by one exact line,
  which #977 rewraps; each PR is green with main, `merge-tree` reports only
  two docs conflicts, and the combination fails `--check-xkb` with a
  `ValueError`. *Check:* for open PRs touching one generator (`gh pr list
  --json files`), `git merge --no-commit` the heads in a scratch worktree and
  run every check mode the generator has; look for `.index("<literal line>")`
  against text another PR rewrites. Extends L-721 and L-478. *From:* #952 with
  #977, round 66, 2026-11-23.
- **L-1147. A contributor's "the gate rejects the prefix upstream uses" is
  checked against the regex and upstream's log, and fixed in the tool.**
  Kernel #279's author kept `PM/devfreq:` because `kernel-pr-check` refuses
  `PM / devfreq:`, which 68 of the last 80 `drivers/devfreq` commits in `v7.0`
  use. *Check:* read the subject rule in `tools/kernel-pr-check`, and `git log
  --oneline -80 <upstream tag> -- <dir> | sed 's/^[0-9a-f]* //' | cut -d: -f1
  | sort | uniq -c`; a mismatch is a tool finding for the maintainer, not a
  request to the author. Extends L-30 and L-452. *From:* kernel #279, round
  66, 2026-11-23.
- **L-1115. A tool that gains a refusal is fed the real inputs it will meet
  before it merges: every released bundle for an installer, the repository's
  own file for a publish tool.** #968's new size refusal was answered for
  seven released bundles on the review laptop by `stat` against each bundle's
  own `device.conf`, with no installer run and no phone; #969 makes the
  nightly `repo-publish` die on a malformed `omamobile-revoked`, and the
  helper called on main's actual file returned cleanly, which is what makes
  the stop safe to land. *Check:* for a refusal keyed on a file's size, magic
  or name, list `out/bundle/*/images/` and compare with each bundle's
  descriptor, where one mismatch means a published release would be stopped;
  for a stop on a tracked file, source the helper from the head and call it on
  a worktree of `origin/main`. Extends L-778, L-420 and L-893. *From:* #968
  and #969, round 65, 2026-11-21.
- **L-1114. A per-commit scanner is fed the two histories its range arithmetic
  can skip: a side commit dropped by an `-s ours` merge, and a head that is
  only a merge of base commits.** Both passed #966's suite with the rule
  removed, and the second passed main's tool as "no commits to check".
  *Check:* `git merge -s ours <side with a finding>` on the branch, and `git
  commit-tree <tree with a finding> -p <base> -p <base>~1`; run the tool on
  each and mutate `--full-history` and the empty-range condition. Extends
  L-684 and L-742. *From:* #966, round 65, 2026-11-21.
- **L-1113. A gate that moves from `git diff` to `git log` is run under the
  `log.*` settings a user can have, a root commit in the range included.**
  #966's per-commit scan lost a root commit's patch under `log.showRoot=false`
  (reachable through a merge of an unrelated history), where main's `git diff`
  was immune; its explicit options held against ten other settings. *Check:*
  build one scratch repository with `GIT_CONFIG_GLOBAL=/dev/null`, then run
  the old and the new tool with `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=<setting>
  GIT_CONFIG_VALUE_0=<value>` for `log.showRoot`, `log.showSignature`,
  `diff.noprefix`, `diff.mnemonicPrefix`, `diff.renames` and `color.ui`, and
  compare the results. Extends L-155 and L-896. *From:* #966, round 65,
  2026-11-21.
- **L-1100. A wide mechanical replacement is proved by applying the stated
  rule to the base by script and comparing with the head, then by reading only
  for what the rule can't know.** For #962 (no pipe into `head` under
  pipefail) a ten-line script showed 20 files equal to "main with the rule
  applied", which left one question per site: `head` returns after N lines and
  `sed -n` reads to the end, so a writer that never ends would hang. *Check:*
  `re.sub` the rule over `git show <base>:<file>` and compare with `git show
  <head>:<file>`; then list each pipeline's first command and look for `-f`,
  `-w`, `monitor`, device nodes and commands without their own end. Extends
  L-896 and L-69. *From:* #962, round 64, 2026-11-21.
- **L-1099. A rule tightened in one branch of a matcher can wake up a later
  branch that the old rule short-circuited.** #959 changed only which first
  octets of an address are exempt, yet 63 of its new reports were follow-up
  addresses behind a date-shaped value that main had exempted by its bit
  before the timestamp step ran. *Check:* in the old-against-new corpus run of
  L-896, group the added values by the branch that reported them, not only by
  the property the PR names, and explain each group. Extends L-896. *From:*
  #959, round 64, 2026-11-21.
- **L-1089. A test suite reached from only one of two version-selected paths
  stops testing when phones move to the other.** omamobile-omarchy's
  `test/lock-glance` (57 cases) is called on the 4.0.6 path only; since the
  move to 4.5 it runs against no shipped family, one of its cases fails on
  4.5, and a first-time contributor found both. *Check:* for each test file
  under a package with selected families, `grep -n '<basename>'` the runner
  and name the family each call reaches; run it once by hand against the
  family phones run. Extends L-586 and L-476. *From:* #920 with #924, round
  63, 2026-11-20.
- **L-1055. A CI log that prints one `ok` per package hides that package's
  skips; a failure recorded in a commit message can be the only evidence a
  block ran.** #771's CI line is `ok - omamobile-install-link`, while its
  `test/all` has seven skip paths (no compiler, no source, no cargo, no
  `systemd-analyze`); that the render tests ran on CI is known only from an
  earlier "no font" failure. *Check:* `grep -n 'skip' packages/<p>/test/all`,
  and ask that `tests/packages` print a package's skip lines even when it
  passes. Extends L-103 and L-513. *From:* #771, round 63, 2026-11-20.
- **L-1036. When a lint PR is reviewed, the open PRs it will turn red are
  listed in that review, with file and line, from their diffs.** For #907, `gh
  pr diff N` over the 106 open PRs that touch `tests/` or `packages/*/test/`,
  filtered to added lines matching the lint's own pattern, took a few minutes
  and found eight PRs (26 lines); their CI is green and will not rerun.
  *Check:* `gh pr list --json number,files`, then per PR `gh pr diff N | awk`
  on `^+` lines of test paths with the lint's regex; put the list in the
  lint's review and in each listed PR's review of the same round. Extends
  L-769 and L-680. *From:* #907, round 63, 2026-11-20.
- **L-1032. A change on the signing path that only deletes is judged by what
  the consumer does without the file.** #944 removes a cached `.sig`; the
  question was not "is the delete right" but "what does pacman do with an
  archive whose signature is missing or is the new one over old bytes", and
  both answers are a re-fetch and a verify, or a stop. *Check:* for every `rm`
  of a signature, checksum or stamp a PR adds, name the reader of that file
  and its behaviour when the file is absent and when it no longer matches the
  data; a reader that proceeds without it is the finding. Extends L-422 and
  L-632. *From:* #944, round 63, 2026-11-20.
- **L-1027. A change that adds a mode to a shared checker is proved neutral
  for the other mode by running the base's test file against the head's
  tool.** #916's own test gained fixtures in the same commit, so its green
  says the new code agrees with the new expectations; main's
  `tests/phone-smoke`, copied over the head's and run against the head's tool,
  showed every Pixel row unchanged. *Check:* `git show origin/main:tests/<t> >
  tests/<t>` in a scratch worktree, run it, restore; then force the new mode's
  detection off and see the head's new case fail. Extends L-145 and L-454.
  *From:* #916, round 63, 2026-11-20.
- **L-1016. A sparse review worktree makes `tests/grep-q-pipes` fail on a
  pathspec that isn't checked out.** "the pathspec 'bin' matches a pipefail
  script" on #932 was the worktree, not the PR. *Check:* the sparse set holds
  every pathspec the lint names (bin, device, initramfs, rootfs, tools, tests,
  packages) before its result is read. Extends L-30, L-194 and L-683. *From:*
  #932, round 63, 2026-11-20.
- **L-1001. A rule a fix commit adds is mutated on its own line, even when the
  commit also adds a replay test.** #946's second commit added "the 58 C step
  never reaches the lowest level" and a 300-tick replay of the phone's night;
  the replay passes with the rule removed, because one 58 C tick in twenty
  never gets near the floor. *Check:* for each rule in a fix commit's message,
  change its condition and run the suite; a replay of the incident is not a
  test of the rule. Extends L-419 and L-684. *From:* #946, round 63,
  2026-11-20.
- **L-998. Image files a package PR adds are parsed chunk by chunk and one is
  compared with its cited source; `tools/pr-check` passes them unread.** #945
  added thirty PNGs to a device package; a 20-line reader gave each file's
  chunk list, CRCs, size and any bytes after `IEND`, and the frame the PR
  calls "Omarchy's logo unchanged" matched the blob in the signed
  `omarchy-settings` package. *Check:* `git diff --stat base...head | grep -E
  '\.(png|webp|jpg|svg)'`; for each, the chunk list (nothing but `IHDR`,
  `PLTE`, `tRNS`, `IDAT`, `IEND` unless explained) and no trailing bytes; for
  a file "copied from" a package, `gpgv` the package and compare `git
  hash-object`; open two of them. Extends L-682 and L-647. *From:* #945, round
  63, 2026-11-20.
- **L-985. A generator's pinned input from a distribution package is verified
  by regenerating it from that package, in scratch.** #952 pins five files
  extracted from an upstream tarball by URL and sum; the review laptop had the
  distribution's signed package of the same version, and the PR's own
  `--extract` on a copy of its files reproduced all five byte for byte, which
  says where the data came from without fetching anything. *Check:* `pacman -Q
  <pkg>` against the pinned version; copy the package's files to scratch, run
  the extract step there, and `sha256sum` against the pins; then mutate one
  input line and one output line and see the check name each; say which sum
  stays unverified (the tarball's). Extends L-454, L-102 and L-632. *From:*
  #952, round 63, 2026-11-20.
- **L-976. A red kernel check on a maintainer's own AI-assisted commit is
  read for the sign-off line first, and checked against the gate faults fixed
  since the run.** Kernel #261 sat red for three days beside a gate fix that
  concerned the same driver's files; the run's only `not ok` was "no human
  Signed-off-by", which the tool is right to print and only the maintainer can
  clear. *Check:* `gh run view <id> --log | grep -E 'ok - |not ok'` and name
  the one failing line; `git log origin/main --since=<run date> --
  tools/kernel-pr-check` for fixes since, and say for each whether the PR's
  files could have met it; then re-run with today's tool. Extends L-768 and
  L-30. *From:* kernel #261, round 62, 2026-11-18.
- **L-974. An accepted, bootloader-forced warning is counted in every tool
  that will report it, and the acceptance says how the gate gets past it.** We
  accepted kernel #260's unit-less `/memory` as one dtc warning; dt-validate
  adds a second line for the same node, and `kernel-pr-check` can't allow a
  named warning, so the check stays red until merge. *Check:* when accepting a
  warning, list dtc's and dt-validate's lines for the node, and write "merge
  past these N named lines" or add the allowance to the tool first. Extends
  L-270 and C-15. *From:* kernel #260, round 62, 2026-11-18.
- **L-973. A board's first run under dt-validate shows root-node vendor
  properties that dtc and the local container never report.** Kernel #260's
  `qcom,msm-name` and `qcom,pmic-name` passed two rounds of local gates (no
  dtschema) and appeared only when CI ran. *Check:* for a first-light board
  whose CI is waiting for approval, either approve the run before the first
  full review or run dt-validate from a scratch venv (L-309); read every root
  property that isn't `model`, `compatible`, `qcom,msm-id`/`qcom,board-id` or
  a standard node against `git grep` of the base's boards. Extends L-103,
  L-309 and L-97. *From:* kernel #260, round 62, 2026-11-18.
- **L-970. A green CI run on an unchanged head is read against each open
  request by asking whether the run could have failed for it.** #876's run was
  green with the weakened check in place, because the PR's test passes with or
  without the line; "can it merge now?" would have been answered wrongly from
  the checks page alone. *Check:* for each open point, name the test that
  would fail if the point were unmet (a mutation from the earlier round is the
  quickest proof); if none, the green run is not an answer, and the fix
  carries its own failing-first test case. Extends L-744, L-684 and L-419.
  *From:* #876 and #875, round 62, 2026-11-18.
- **L-968. A CI run approved hours or days after its push tests the merge
  made at the push, so a green "Tests" can sit on a PR that conflicts or that
  main has moved under.** #874's re-run finished on the base of 12 hours
  earlier though main had changed the package's own `test/all`; #203 showed
  two passes beside `mergeable: CONFLICTING`; #784's run was created three
  days and three package versions before it finished. *Check:* `gh run view
  <id> --log | grep -m1 'HEAD is now at'` and compare the "into" commit with
  `origin/main`; when they differ, say "green on the base of <time>", `git log
  <that base>..origin/main -- <touched files>`, and run `git merge-tree
  origin/main <head>` and the touched suites on a scratch merge before writing
  "CI green". The kernel workflow differs: it fetches the base at run time and
  merges. Extends L-154, L-165 and L-744. *From:* #874, #203 and #784, round
  62, 2026-11-18.
- **L-964. A checksum pin for a vendor archive is checked against the
  vendor's own published checksum, not only against today's download.** For
  #900 the lock's SHA-256 matched the file the vendor serves, which proves the
  contributor copied it faithfully; the SHA-1 of the same bytes matching the
  vendor's downloads page and release notes proves it is the published
  release. *Check:* download into an empty scratch folder, compare size and
  the pinned sum, then compute whatever digest the vendor lists (often SHA-1)
  and find it on two vendor pages. Extends L-632. *From:* #900, round 62,
  2026-11-18.
- **L-963. A "refuses another host" test is mutation-tested with the network
  in mind: without the refusal it must fail, not go and ask the other host.**
  #900's case passed with the host check removed, because `curl` then really
  requested the other URL and got nothing; the mutation run made that request
  from the review machine. *Check:* before removing a host or URL check in a
  mutation, read what the next line does with the URL; give the test a fake
  `curl` first on `PATH` that records and fails, and ask the PR for the same
  plus a match on the refusal message. Extends L-664, L-454 and L-742. *From:*
  #900, round 62, 2026-11-18.
- **L-955. A test that `test/all` calls only behind an environment switch is
  not in CI's green, and "fails without the fix" is then the author's run.**
  `omamobile-shell`'s `test/all` calls `test/update-render` only with
  `OMAMOBILE_UPDATE_RENDER` set and `test/call-render` only with
  `OMAMOBILE_CALL_RENDER`, so #894's CI never drew the sheet it changes and
  #911's new assertion never ran there. *Check:* for each test file a PR edits
  or leans on, `git grep -n '<basename>' <head> -- packages/<p>/test/all` and
  read the condition around the call; grep the CI log for the new `ok -` line
  by its words; if it is absent, say so and read the check against main's
  code. Extends L-586 and L-476. *From:* #894 and #911, rounds 62 and 63,
  2026-11-20.
- **L-953. A local gate run mounts `origin/main`'s tools, not the shared
  clone's working tree, and the export needs `kernel/configs/` beside
  `tools/`.** The clone's checked-out `main` was behind and its
  `tools/kernel-pr-check` predated #851, so our gate failed kernel #266 on a
  file CI had passed an hour before; with only main's `tools/` mounted,
  `--build` then stopped at "the kernel config doesn't configure", which reads
  like a PR or base fault. *Check:* before the container run, `git -C <clone>
  diff --stat origin/main -- tools kernel/configs`; if it isn't empty, `git
  archive origin/main tools kernel | tar -x` into the review's own folder and
  mount that. Extends L-30, L-41 and L-145. *From:* kernel #266 and #261,
  round 62, 2026-11-18.
- **L-952. A picture added under `docs/screenshots/` is grepped for a
  document that uses it, and compared with the head it sits on.** Main has
  documentation pictures there, so the directory alone doesn't make a picture
  review evidence; #895's and #892's five were linked only from the PR bodies,
  and #951's showed a layout from two weeks before its head, which
  `tools/pr-check` passes. *Check:* `git grep -n '<basename>' <head> --
  '*.md'`; no hit means "attach it to the PR"; otherwise compare one visible
  detail with the file it illustrates. Extends L-682. *From:* #895, #892 and
  #951, rounds 62 and 63, 2026-11-20.
- **L-946. A "this test now bites" answer is checked by repeating last
  round's mutation, not by reading the new case.** Round 61 found that `if
  false` in place of #860's supply-name check left the suite green; the reply
  added a fixture line, and the same mutation then failed with a named case.
  *Check:* keep the exact mutation from the round that found the gap (the
  `sed` line) in the review file, and run it again on the new head before
  writing "met". Extends L-419 and L-183. *From:* #860, round 62, 2026-11-18.
- **L-942. A change to `tools/phone-smoke`'s guard rows is run on a fake root
  shaped like the reference phone: `sda` at `ro` 0, the device package's
  installed `device.conf`, and a release on each slot.** #714's stricter row
  passed its own test and CI, and on a Pixel-shaped root it failed a healthy
  slot B phone on the main disk, failed a slot A release on its own boot
  images, and passed a writable `boot_b` on slot A that main refuses. *Check:*
  build the fixture from `initramfs/init`'s whole-disk comment and
  `device/cheetah/device.conf`, run main's and the head's tool with
  `--slot-from`, and compare the storage row for slot A, slot B and the other
  slot's image writable. Extends L-685, L-8 and L-145. *From:* #714, round 61,
  2026-11-18.
- **L-912. A new `source=` URL or host is verified by hash in review and then
  reported as a decision about the host, not about the hash.** #697's forge
  archive and both of #888's sources matched their sums, so the code is
  pinned; what the maintainer decides is whether the build machine fetches
  from that host nightly and what a regenerated archive does to the publish.
  *Check:* `git grep -n '<host>' origin/main -- 'packages/*/PKGBUILD' rootfs
  tools` for whether the host is new; download each source into its own empty
  scratch folder, compare the sum, delete; say whether the file is a signed
  release or a forge-generated archive, and what fails, and for whom, when the
  sum stops matching. Extends L-333, L-512 and L-420. *From:* #697 and #888,
  round 61, 2026-11-18.
- **L-896. A rewrite of a value a gate decides on, or of a matcher, is proved
  by running old and new over one generated corpus aimed at the boundaries,
  not by its own test list.** For #884 that was 4,000 seeded files around the
  64-byte window, NULs and newlines (0 differences, then the selected `case`
  arm under two locales); for #906 both scanners, extracted with `git show
  <rev>:<tool>`, read 19,137 lines, and the removed values were all
  timestamps. *Check:* extract both forms, generate inputs from the grammar's
  pieces that straddle every boundary the comment names, and compare value and
  decision; for a matcher require that what was removed is within the exempt
  set and what was added is what the description names, and lift any cap on
  printed findings (`tools/release` shows the first 40) in the extracted copy;
  then run the PR's suite with the base's tool to see the new case fail.
  Extends L-145, L-155 and L-636. *From:* #884 and #906, rounds 61 and 63,
  2026-11-20.
- **L-895. A change to a download path gets a five-row table before anything
  else: host and URL, pinned version and sum, fetch options, when the sum is
  checked, and what is consumed afterwards, each on the base and on the head;
  and each checksum line is deleted once to see a test fail.** On #883 the
  table showed a moved, unchanged URL and a check that only got earlier, and
  both deletions failed the suite, which let a download-path PR merge quickly.
  *Check:* `git diff base...head | grep -n 'https\?://\|sha256\|SUM='`, then
  the table, then one mutation per verification line. Extends L-632 and L-145.
  *From:* #883, round 61, 2026-11-18.
- **L-894. A "message only" change to a refusal is confirmed by running the
  base's tool through the head's suite and reading which checks fail.** #882's
  suite takes the tool's path from a variable; with main's tool four checks
  failed, all about the refusal's text, which showed in one run that the
  decision paths were untouched and that the new checks bite. *Check:* where a
  suite takes the tool's path from a variable, run it with `git show
  <base>:<tool>` saved to scratch; where it doesn't, copy the base's tool over
  the merge's in a scratch worktree, run, and restore. Extends L-145 and
  L-454. *From:* #882, round 61, 2026-11-18.
- **L-891. When a build moves its inspection from the published artifact to
  the artifact's source, ask what still ties the two together, and delete that
  line to see whether a test notices.** #876 pointed the root image's smoke
  test at `rootfs.img` and left the `.img.zst` with `sha256sum -c` against a
  checksum taken from the same file and `zstd -t`; removing `zstd -t` left
  `tests/build-rootfs` green. *Check:* for each artifact a build publishes,
  name the check that reads its content and the bytes its verdict covers;
  where the verdict is about another file, ask for a compare (`zstd -dc A |
  cmp - B` needs no disk) and a fixture case for it. Extends L-422, L-635 and
  L-684. *From:* #876, round 61, 2026-11-18.
- **L-890. A tool that gains a delete in a shared cache or state folder is
  checked against every test that runs the real tool without redirecting that
  folder.** #875 added a removal from `$ALARM_CACHE/pkg`;
  `tests/pinned-packages` and `tests/local-builds` run the real
  `tools/build-packages` with `ALARM_CACHE` unset, so they reach the user's
  real cache with a tool that deletes there, and only the fixture names keep
  it harmless. *Check:* `git grep -ln '<tool>' tests packages/*/test`, then in
  each hit look for the variable that moves the folder (`ALARM_CACHE=`,
  `HOME=`); before running such a suite in review, note the real folder's
  mtime and compare it afterwards. Extends L-454 and L-681. *From:* #875,
  round 61, 2026-11-18.
