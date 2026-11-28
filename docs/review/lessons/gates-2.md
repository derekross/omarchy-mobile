<!-- SPDX-License-Identifier: MIT -->
# Review lessons: The gates themselves (part 2 of 3)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
- **L-780. A gate fallback for "this file can't be checked the usual way" is
  fed a file that is simply broken, on the real build, and the summary line is
  read for what it counts.** #851 built an included `.c` through its includer;
  a decoy that can't compile, included under `#if 0`, first passed as "ok -
  W=1 builds of 2 touched C files". Its suite fakes the compiler and writes
  its own `.cmd`, so whether the tool reads kbuild's real one (absolute paths,
  `$(wildcard ...)` tokens, a separate output directory) showed only in the
  container. *Check:* for each new branch of a gate, make a throwaway commit
  that takes it (a temporary index and `git commit-tree`, no checkout
  touched), run main's tool and the PR's on it in the project container, each
  in its own output directory, and require that anything not compiled appears
  as `# SKIP`, not in the ok count. Extends L-102, L-103 and L-145. *From:*
  #851, rounds 60 and 61, 2026-11-18.
- **L-779. A hyphen-joined MAC pattern also matches a `YY-MM-DD-hh-mm-ss` name,
  and whether it is reported depends on the year.** The locally administered
  exemption passes a first field of 26 or 27 and reports 25, 28 and 29.
  *Check:* feed a new separator form a timestamp-shaped name for several years
  before calling its false-hit rate measured. Extends L-633. *From:* #842,
  round 60, 2026-11-17.
- **L-778. A stricter identifier pattern is run over the last release's real
  inputs before it merges, and they are on the review laptop.** #842's author
  could test fixtures only; the last release's root image, its
  `out/release/<version>/rootfs-files.txt` and MANIFEST were enough to show
  that main's and the PR's scanners agree. *Check:* decompress the image into
  the review's scratch folder, `debugfs rdump` `/etc`, `/root`,
  `/usr/share/omamobile` and `/var/lib/omamobile` each under its own parent
  (as the identifiers stage does), run both versions of the scanner with a
  one-word identifiers file, and feed both a known address first so that an
  empty result means something; the dump is read-only, so `chmod -R u+w`
  before deleting it. Extends L-538, L-634 and L-102. *From:* #842, round 60,
  2026-11-17. (Extended 2026-11-24: a scanner that gains a new input kind is
  run with that kind counted, so "nothing found" is a number. #1031 starts
  reading symlink targets; the 2026.11.15 dump holds 1,036 links (`find <dump>
  -type l | wc -l`), and main's and the head's scans agreed on zero findings
  there next to a control link only the head reports; put the count and the
  control in the review. *From:* #1031, round 67.)
- **L-771. `tools/pr-check` doesn't read licence headers, so a file moved in
  from the kernel tree is checked for the SPDX line it brought along.**
  #666's `tools/ncm-transfer` arrived as `GPL-2.0` in an MIT repository.
  *Check:* `git diff --diff-filter=A base...head | grep -n 'SPDX'` against
  CONTRIBUTING §7. Extends L-221. *From:* #666, round 52, 2026-11-11.
- **L-770. Nothing in CI reads Markdown reference links, so a docs diff that
  changes a `[label]` is checked for its definition line.** #505 changed
  BRINGUP-M1's `[the notes PR #330]` to `[NOTES.md]` and deleted the old
  definition without adding one, so the link renders as bracketed text.
  *Check:* for each `[label]` without parentheses that a diff adds, `grep -n
  '^\[label\]:' <file>` at the head. Extends L-262. *From:* #505, round 52,
  2026-11-11.
- **L-769. A lint that lands on main turns open PRs written before it red at
  their next rebase, and a red `tests/all` hides the package suites.** #346's
  package was unchanged, yet its rebase failed on `tests/grep-q-pipes`, and
  CI stopped before `tests/packages`, so the package's own test never ran.
  *Check:* when a new lint merges, run it on each open PR's merge with main
  and hand each author the line; when `tests/all` fails, say that
  `tests/packages` didn't run, and run the touched package's `test/all` by
  hand. Extends L-195 and L-103. *From:* #346, round 52, 2026-11-11.
- **L-768. A non-passing CI check is read down to the step that ended it.**
  `gh pr checks` showed kernel #241's job as "fail" after an hour; the run
  was `cancelled` in its "Tools" step, before `tools/kernel-pr-check`
  started, so there was neither a failure of the PR nor a `dtbs_check` result
  for the new head. *Check:* `gh run view <id> --json conclusion,jobs` and
  name the step; when the gate step never ran, say "CI did not run on this
  head", list what stays unchecked locally (dtschema), and re-run instead of
  holding the PR to it. Extends L-30 and L-38. *From:* kernel #241, round 52,
  2026-11-11.
- **L-767. A known-failure feed for a new compatible needs `dt-validate
  -m`.** On kernel #243 the head DTB against the base's schemas printed
  nothing for `"google,zuma-vgpio2ap-sysreg", "syscon"`: an unknown compatible
  selects no schema, and without `-m` dt-validate is silent about such a
  node, so the feed read as "the validator doesn't bite". *Check:* for a
  binding commit that only adds a compatible to an enum, run the feed with
  `-m` and grep for the node's unit address ("failed to match any schema with
  compatible" at the base, gone at the head). Extends L-102, L-178 and L-293.
  *From:* kernel #243, round 52 (a near miss), 2026-11-11.
- **L-744. A CI run we approve after posting a review is read at the next round, even when the head hasn't moved.** #555's run was approved after our comment and failed on shellcheck (SC2206), which the local test run didn't have; nobody told the contributor. *Check:* every round, `gh pr checks N`, and compare each run's `headSha` with the head; for package tests run locally, note whether shellcheck was installed. Extends L-480 and L-281. *From:* #555, round 51, 2026-11-11.
- **L-743. A commit message is read to its last line after every rebase: a diff pasted into it passes every gate.** Kernel #181's rebased enable commit carried 77 lines of `diff --git` between `Assisted-by:` and `Signed-off-by:`; `kernel-pr-check` said "signed off" and checkpatch was clean. *Check:* `git log --format=%B base..head | grep -n '^diff --git\|^@@ \|^index [0-9a-f]'` is empty, and `git interpret-trailers --parse` lists the sign-off for every commit; `kernel-pr-check` could refuse both. Extends L-475 and L-585. *From:* kernel #181, round 51, 2026-11-11.
- **L-742. A mutation that changes a shared constant can be caught by an earlier test and prove nothing about the new one.** Setting `VERIFIED_VER_MINOR` to 14 failed lynx's suite at the `cmp` against cheetah's copy and, with both copies changed, at the 3.15 dry run, before #436's new 3.14 refusal ever ran. *Check:* read which `not ok` line a mutation produces; if it isn't the test under review, mutate the condition that test names (here an extra accepted minor in both pinned copies). Extends L-419 and L-454. *From:* #436, round 51, 2026-11-11.
- **L-717. A PR pushed while it conflicted can read "mergeable, clean" with no
  CI run at all.** #610's second commit came while `version` conflicted (no
  workflow); #632 then took the same 0.1.41, both sides became identical, and
  GitHub showed CLEAN with "no checks reported". *Check:* for a mergeable PR
  with no checks, `gh api "repos/<r>/actions/runs?head_sha=<head>"`; a count
  of 0 means run the touched suites on a scratch merge, compare `version` with
  main's, and grep the PR's docs for the old number. Extends L-405 and L-404.
  *From:* #610 with #632, round 50.
- **L-685. A fake phone encodes its author's assumptions about the bootloader;
  write the opposite fake.** #639's fake kept `current-slot` and the active
  flag apart and always left the bus at the first poll, so two mutations of
  the wait passed; with a fake whose `current-slot` follows the active flag
  and whose restart never happens, the installer reported a measured match for
  a slot that differed. *Check:* list each bootloader behaviour the fake
  models, find the note that measured it, and flip each unmeasured one in a
  scratch copy and rerun the happy path. Extends L-419 and L-454. *From:*
  #639, round 49, 2026-11-10.
- **L-684. "Each assertion fails when its code is broken" is extended to the
  lines no assertion names.** Round 48 told #503 that all three NFS assertions
  bite, which was true, but two new NFS-only lines (`ufs_unguarded`'s `sda`
  exemption, `boot_nfs`'s check before `kill -9 -1`) had no assertion at all.
  *Check:* list every line a mode adds inside the guard and hand-over
  functions (`git diff | grep '^+'`) and mutate each once. Extends L-587.
  *From:* #503, round 49, 2026-11-10.
- **L-683. A lint that collects its inputs by pathspec checks each pathspec
  separately, with its exclusions applied.** `tests/grep-q-pipes`' single
  "found some files" test passed while `'packages/*/test'` matched nothing,
  because the other pathspecs filled the list. *Check:* misspell each pathspec
  in turn and run the lint; each must fail with its name. Extends L-635 and
  L-419. *From:* #597 with #587, round 49, 2026-11-10.
- **L-682. Review media committed under `docs/` is asked out of the commit;
  `tools/pr-check`'s blob check passes images.** #612 and #614 added
  `docs/review-evidence/` (PNG and WebP captures) so the PR body could link
  them, and a squash keeps the blobs for good. *Check:* `git diff --stat
  base...head | grep -E '\.(png|webp|jpg|gif|mp4)'`; evidence for the review
  goes into the PR as an attachment. *From:* #612 and #614, round 49,
  2026-11-10.
- **L-681. A package test is run on the review laptop only after every command
  and sysfs path it reaches is faked.** `test/keys.sh` puts its fakes before
  the host's `PATH`, and `omamobile-keys` calls `omarchy-menu` and
  `omarchy-capture-screenshot`, real on an Omarchy laptop; #577's `panel_dark`
  also reads `/sys/class/backlight/*/bl_power`. *Check:* list the script's
  external commands and `/sys` reads against the test's fakes and `command -v`
  the rest; if any is real, leave the test to CI or run it under `env -i` with
  a scratch `HOME` and a `PATH` of fakes, and say which tests didn't run.
  Extends L-454, L-410 and L-498. *From:* #577, #539 and #553, round 49,
  2026-11-10.
- **L-680. A PR whose test files predate a new lint is linted on a scratch
  merge, and a conflicting PR never gets the CI that would say so.** #539's
  `test/hotspot-panel.sh` passed CI on 11-08; #587 added `tests/grep-q-pipes`
  on 11-10, and the PR's `version` conflict meant no run showed its eleven new
  failures. *Check:* each round, for every PR that adds a script under
  `tests/` or `packages/*/test/`, run the lints main gained since its last
  green CI on a scratch merge (`tests/grep-q-pipes` only reads `git grep`).
  Extends L-73, L-165 and L-511. *From:* #539, round 49, 2026-11-10.
- **L-679. An overlay added to a descriptor's `DTB_OVERLAYS` is applied to the
  last tagged kernel's DTB as well as the tip's; `tests/device-overlays` only
  compiles it.** #594's overlay disables a node kernel #187 added a day after
  `kernel-2026.11.08`, so on the tag's DTB `fdtoverlay` returns
  `FDT_ERR_NOTFOUND` and `bin/omamobile images` dies without a cause.
  *Check:* `scripts/dtc/dtc -@` then `fdtoverlay -i <dtb>` against
  `out-kernel-release` and a tip build; if they differ, the descriptor names
  the minimum kernel. Extends L-8 and L-70. *From:* #594, round 49,
  2026-11-10.
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
  --format='%an <%ae>' base..head` on omamobile PRs; ask for a
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
