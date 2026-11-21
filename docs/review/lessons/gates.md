<!-- SPDX-License-Identifier: MIT -->
# Review lessons: The gates themselves (part 1 of 3)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
- **L-886. `tools/pr-check BASE HEAD` run from another directory checks the
  tool's own repository.** Called by its path from inside a review worktree it
  printed "ok - no commits to check against origin/main" for a head with one
  commit; it needs `-C <worktree>`. A passing line that means "nothing was
  checked" is easy to quote. *Check:* the output lists the seven checks by
  name; the tool could say which repository and range it read, and refuse
  `HEAD` when the caller's directory is another work tree. Extends L-40 and
  L-103. *From:* round 61, 2026-11-18.
- **L-873. A package test that fails when its tool is missing is checked
  against the CI workflow's package list as well as `checkdepends`.** #880
  added `glslang` and `lua` as `checkdepends`, which the package builders
  install, but `checks.yml` installs a fixed list and runs `test/all`
  directly, so CI failed on the missing tool once the PR's lint failure was
  out of the way; a red `tests/all` had hidden it. *Check:* for every `command
  -v X || fail` a test adds, `grep -n '<package>'
  .github/workflows/checks.yml`; if absent, the maintainer adds it (a workflow
  change is his) or the test skips visibly, and the review says which. Extends
  L-589 and L-769. *From:* #880, rounds 61 and 62, 2026-11-18.
- **L-857. A test file `#include`d into its driver is never compiled by the
  gate: its config has no `CONFIG_KUNIT`, and since #851 a `.c` built only
  through an include is a SKIP.** Kernel #265's `max77759_charger_test.c`
  first turned CI red with "W=1 builds" while the driver was clean; after #851
  the same PR goes green with the test uncompiled, and its only evidence is
  the contributor's UML run. *Check:* grep the CI log for `SKIP`; `git grep -n
  '#include "<file>"'` for the includer, build it at each commit with
  `scripts/config -e KUNIT -e <the test's symbol>` at W=1 in the gate's own
  output directory, and say in the review that the suite itself wasn't run and
  what stands in for it. Extends L-103, L-143 and L-179. *From:* kernel #265
  and #266 with #851, rounds 60 to 62, 2026-11-18.
- **L-834. Without the container, a board DTB for an overlay check builds from
  `git archive` of the dts and `dt-bindings` trees, `cpp`, and a `dtc` from
  any finished kernel output.** Both sides of #829's comparison (the published
  kernel and a kernel PR's head) took seconds and touched nobody's build
  directory. *Check:* `git archive <commit> arch/arm64/boot/dts/exynos
  include/dt-bindings | tar -x -C <scratch>`, `cpp -nostdinc -I include -I
  arch/arm64/boot/dts -undef -x assembler-with-cpp <board>.dts | dtc -@ -I dts
  -O dtb`, then `fdtoverlay`, and confirm both DTBs are non-empty. Extends
  L-335 and L-679. *From:* #829, round 60, 2026-11-17.
- **L-833. A red test on a PR that adds one data file is read to its `not ok`
  line, and a sibling PR pushed at the same time on the same base is the
  control.** #829's failure was `omamobile-shell`'s `test/keys.sh`: the fake
  panel acts after 0.4 s, the handler gives up at 1 s, and the CI log's order
  showed the fake ran late; another PR's run from the same second passed.
  *Check:* `gh run view <id> --log | grep 'not ok'`, name the package, read
  the test's own timings against the log's order, and compare with a run on
  the same base; the margin goes to the maintainer as a test finding. Extends
  L-42, L-346 and L-768. *From:* #829, round 60, 2026-11-17.
- **L-827. A new overlay outside `DTB_OVERLAYS` is still applied to the
  published kernel's DTB, to set the merge order.** #861's `gnss.dtso` applies
  to kernel #268's DTB and returns `FDT_ERR_NOTFOUND` on the published
  `omamobile`; CI can't see it. *Check:* `fdtoverlay` against both; if only
  the PR's kernel takes it, the review says "with or after" and the notes name
  the kernel PR. Extends L-679. *From:* #861 with kernel #268, round 60,
  2026-11-17.
- **L-817. `tests/grep-q-pipes` doesn't scan package `libexec`, `bin` or
  `backends` directories.** #860's root helper piped into `grep -qx` under
  `pipefail` and the lint passed. *Check:* until the lint's pathspecs cover
  them, `git grep -nE '\|[[:space:]]*grep -q' <head> -- 'packages/*/libexec'
  'packages/*/bin' 'packages/*/backends'` on every package PR. Extends L-683
  and L-15. *From:* #860, round 60, 2026-11-17.
- **L-796. A package test that runs a start script calling the host's `sync`
  fails under a loaded review machine.** `omamobile-modem`'s `test/all` gives
  three `sync`s 20 s; with parallel reviews building, one case ended with rc
  124 on #850's tree and passed on the next run. *Check:* on a timeout in a
  case the PR doesn't touch, read `uptime`, time a `sync`, and rerun on main
  and on the head before calling it the PR's; the script could take its `sync`
  from a variable the test overrides. Extends L-42 and L-346. *From:* #850,
  round 60, 2026-11-17.
- **L-793. A docs PR that adds a place to download a program is checked for
  what verifies the download.** The release bundle is verified by signature
  whatever its URL; the installer app's files had a checksum file beside them
  and nothing else. *Check:* for each new download link, name the file, what
  the reader is told to check it against, and whether that check is anchored
  in a key or only in the same page. Extends L-632 and L-422. *From:* #843,
  round 60, 2026-11-17.
- **L-785. A tool that starts keeping state under the user's home is run by the
  tests with that home in scratch.** #855's `mkdir` under `XDG_DATA_HOME` made
  `tests/phone-ssh` and `tests/make-bundle` write into the tester's real home,
  and made the tool exit under `set -u` where `HOME` is unset. *Check:* run
  the suite with `HOME` and `XDG_*` pointed at an empty scratch directory and
  list it afterwards; run the tool's first lines with both unset. Extends
  L-454 and L-681. *From:* #855, round 60, 2026-11-17.
- **L-783. A base image pinned by digest under a rolling-release `pacman -Syu`
  needs a keyring refresh and a named bump step.** The pin fixes the trust
  root and nothing else; without a refresh the job fails some months later on
  every PR at once. *Check:* for a digest pin of a rolling distribution's
  image, find who bumps it (Dependabot, a comment with the command) and
  whether the first package step updates the keyring. *From:* #853, round 60,
  2026-11-17.
- **L-782. A pin of a moving tag is compared with what the tag resolves to
  today, not only with the release the PR names.** #853 pinned
  `actions/checkout` to v5.0.0's commit, which is genuine, while `@v5` had
  been at v5.1.0 for four months, so "no behaviour change" moved CI back three
  commits, a security default among them. *Check:* `git ls-remote
  https://github.com/<owner>/<action> 'refs/tags/v<N>*'`: the pinned id is a
  tag's target in the action's own repository (a fork's commit also resolves
  under the parent's name) and equals the major tag's target unless the PR
  says why not; for a container digest, compare with the registry's
  `docker-content-digest` for the tag and read the index for its platforms and
  build date. *From:* #853, round 60, 2026-11-17.
- **L-781. "The builds are run by hand, so there is no test" is checked against
  the test file's own stand-ins.** `tests/kernel-pr-check` has had a stand-in
  `make` for `--build` since the device-tree comparison. *Check:* `grep -n
  'stand-in\|fake' tests/<the tool's test>` before accepting that a path can't
  be tested. Extends L-454. *From:* #851, round 60, 2026-11-17.
