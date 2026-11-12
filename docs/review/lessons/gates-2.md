<!-- SPDX-License-Identifier: MIT -->
# Review lessons: The gates themselves (part 2 of 2)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-195. A follow-up round re-gates the merge first, even when the new
  commits only touch docs, because the base moves under the PR between
  rounds.** #82's first review found "none of the moved commits touch
  `bin/omamobile`"; four hours later the Pixel 6 Pro port had landed in
  `initramfs_config`, the PR went `CONFLICTING`, and that means no CI at all
  (L-165). *Check:* `gh pr view N --json mergeable` and `git merge-tree
  --write-tree origin/main <head>` at the start of every round; on a
  conflict, resolve it in a scratch worktree, run the suites and the cheetah
  comparison on the result, and hand the contributor the resolution. Extends
  L-34, L-73 and L-165. *From:* #82, round 20.
- **L-214. Stacked or un-rebased heads are gated on today's main and the
  combined tree, not pairwise.** #87's CI failed on a compatible that its
  sibling #86 documents (merged, zero messages); #72, left un-rebased while
  #70 and #78 were, conflicted with main and got no CI, and `merge-tree`
  between heads on different bases reported conflicts that weren't real.
  *Check:* `git merge-base` and `git merge-tree origin/main <head>` per PR
  first; `git grep` open PR heads for a compatible a failure names; give the
  merge order and the resolved hunk. Extends L-73, L-104, L-165 and L-196.
  *From:* kernel #87 with #86, #72, round 22.
- **L-420. A per-package check that `alarm_die`s the whole build stops every phone's publish.** #320's `stage-boot-files --check` covers all of `initramfs/`, so any device-package bump after any shared init change would hold the development channel until the maintainer staged again. *Check:* for a new gate in `build-packages` or `repo-publish`, ask whether skipping that package (non-zero exit at the end) is as safe, and grep for versioned dependencies on it. Related to L-259. *From:* #320, round 38, 2026-11-02.
- **L-421. A hard-coded list of another tool's outputs is re-checked against that tool at the same head, after every merge of main.** #324's identifiers stage named make-bundle's files; #317, merged between rounds, added `INSTALL.md` and `tools/*`, so the stage would refuse every real bundle, and its test set the stage's result by hand. *Check:* `git log origin/main --since=<proof date> -- <producing tool>`, then run the allowlist on a bundle from `tests/make-bundle`'s fixture. *From:* #324 (and seen on #326), round 38, 2026-11-02.
- **L-422. A new signature or artifact is checked for a consumer before it is shipped.** #324 wrote `<rootfs>.sha256.sig`, but the installer trusts only the signed MANIFEST, release-upload doesn't upload it, and it sat next to a different copy of the image. *Check:* grep the installer, uploader and flasher for the new file; if nothing reads it, ask to drop it. *From:* #324, round 38, 2026-11-02.
- **L-452. The prefix gate checks that a prefix exists, not that it is the
  file's own.** Kernel #152 passed with `firmware: exynos-acpm:` while the
  file's history, ours and mainline's, is `firmware: samsung: acpm:`.
  *Check:* `git log --oneline -5 github/omamobile -- <file>` for each
  touched file against each subject; the gate could compare with the file's
  last subjects. Extends L-18. *From:* kernel #152, round 39, 2026-11-03.
- **L-455. A cross-repository CI token is judged by everything its
  permission grants, against the target's branch protection, and its trigger
  matches what the consumer reads.** #404's `repository_dispatch` needs
  Contents: write, which also writes files, and the website's unprotected
  `main` deploys on every push; the existing `workflow_dispatch` needs only
  Actions: write. The trigger also fired on NOTES.md, which the site never
  reads. *Check:* read the fine-grained permission's other endpoints and
  `branches/<b>` protection on the target, prefer an endpoint that can't
  change code, and grep the consumer and its checkout for the files `paths:`
  names. *From:* #404 with omamobile-website #1, round 39, 2026-11-03.
- **L-475. The sign-off check reads the whole message, so a sign-off outside
  the trailer block passes.** #194's `Signed-off-by:` sat above a blank line
  and a `Co-Authored-By:`, so git's trailer block held only the co-author;
  our gate and checkpatch both found the sign-off by grep. *Check:* `git log
  -1 --format=%B <c> | git interpret-trailers --parse` lists the author's
  sign-off; `kernel-pr-check` should parse trailers. Extends L-119 and L-18.
  *From:* kernel #194, round 40, 2026-11-04.
- **L-476. A patch test that lives inside the real-package block is skipped
  on CI.** omamobile-omarchy's patch checks run from `real_package()`, and
  CI has no Omarchy package, so its green says nothing about a new patch.
  *Check:* `gh run view --log | grep -E 'SKIP.*(omarchy package|bsdtar)'` on
  every omamobile-omarchy PR, and rely on (or re-run) a local run with
  `OMARCHY_PKG`. Extends L-103. *From:* #431, round 41, 2026-11-05.
- **L-510. Agent identities and session trailers on every commit are a finding
  `tools/pr-check` doesn't catch.** #466, #467, #468 and #470 were authored
  and committed as `codex@openai.com`/`codex@local.invalid` throughout, so a
  squash leaves no human; #98 ended with a `Claude-Session:` link to a private
  session. *Check:* `git log --format='%an <%ae> / %cn <%ce>%n%B' base..head`
  for agent domains, `*.invalid` and `https?://…(session|chat|share)`. Extends
  L-271 and L-312. *From:* #466, #467, #98, round 42, 2026-11-07.
- **L-511. A `| grep -q` flake that never shows on CI is reproduced with an
  unbuffered writer.** A block-buffered Python pipe hides L-15's race; with
  `PYTHONUNBUFFERED=1` `omamobile-modem`'s NV-overlay test failed 10 of 10.
  *Check:* rerun with `PYTHONUNBUFFERED=1` before calling a failure
  machine-specific, and grep tests for `| *grep -q` fed by Python. Extends
  L-15 and L-346. *From:* issue #457, round 42, 2026-11-07.
- **L-512. A package without `test/all` gets its patch series applied by hand
  in review.** CI's green on #446 never touched Hyprland. *Check:* for
  PKGBUILD-only packages (hyprland, mesa, libfprint), check each `source=`
  sha256 and apply the patches in `prepare()` order with `--fuzz=0`. Extends
  L-333 and L-60. *From:* #446, round 42, 2026-11-07.
- **L-513. A package test that skips without the repository can skip the
  assertion the fix adds.** In `omamobile-telephony-tegu` alone, 3 of 23 tests
  skip, the `ExecCondition` one among them. *Check:* run with `-v` from a tree
  with the sibling packages, and confirm the covering test ran. Extends L-334.
  *From:* #371, round 42, 2026-11-07.
- **L-514. A refused-method test entry a random string would also pass tests
  nothing about the device.** `tests/boot-method` builds a probe descriptor,
  so `android-v0` passes as `unknown` does. *Check:* ask for the shipped
  descriptor to go through the refusal, as for flame. Extends L-454. *From:*
  #445, round 42, 2026-11-07.
- **L-515. A gate is checked for who creates its precondition in the product,
  not in the test.** #471 needs the exact archive in pacman's cache; nothing
  in the updater downloads it, `test/prospective.py` puts it there. *Check:*
  `git grep` the shipped code for each required file's writer; a fixture that
  creates it hints nothing else does. Extends L-454. *From:* #471, round 42,
  2026-11-07.
- **L-516. A plan check whose failure falls back to a plain list says "ok" for
  the case it exists to catch.** `pending_updates()` ignores `pacman -Sup`'s
  exit status and uses checkupdates' lines. *Check:* run it against a fake
  root whose plan fails and expect a blocker. Extends L-161. *From:* issue
  #433, round 42, 2026-11-07.
- **L-517. A migration hold list is run over the release's real migrations and
  checked against the holds we promised.** #469 held 23 of 4.5's 98 new
  migrations, but not the titlebars one promised on #433. *Check:* run the
  wrapper with a fake runner over `migrations/`, the old set marked done, and
  grep threads for promised holds. *From:* #469 and #471, round 42,
  2026-11-07.
- **L-518. A test that greps a tool's source for an implementation detail
  proves nothing about behaviour.** `tests/stage-boot-files` broke on #289's
  rewrite of a pathspec that behaved the same. *Check:* test what the tool
  does, and when replacing a filter, compare old and new outputs on real data.
  Extends L-454. *From:* #289, round 42, 2026-11-07.
- **L-548. CI skips the real-Omarchy run of `omamobile-omarchy`'s patch test,
  so a new Omarchy patch is gated only by its author's run.** "the real
  Omarchy package # SKIP no omarchy package (OMARCHY_PKG=...)" is in every CI
  log. *Check:* apply the series with main's `omamobile-omarchy-patches apply
  --root <tmp> --series <pr>/patches` to the matching Omarchy package from the
  pacman cache (the shell's files are arch-independent), and `diff -r` the
  trees with and without the new patch. Extends L-103. *From:* #420, round 44,
  2026-11-08.
- **L-549. Every PR that adds a suite to `tests/all`'s one-line loop conflicts
  with every other such PR.** #491 and #492 each appended to the same line and
  comment, and both were green alone. *Check:* `git merge-tree` each open pair
  that touches `tests/all`, and give the resolved line in both reviews.
  Extends L-104 and L-375. *From:* #491 and #492, round 44, 2026-11-08.
- **L-585. `kernel-pr-check`'s sign-off check accepts a `Signed-off-by:`
  anywhere in the message.** Kernel #218, and kernel #220's imported commits,
  had the sign-off outside the trailer block, and the gate said "signed off".
  *Check:* `git interpret-trailers --parse` per commit; the tool could take
  sign-offs from `--parse` output only. Extends L-119. *From:* kernel #218 and
  #220, round 45, 2026-11-08.
- **L-586. A package test file that nothing calls is not a test, and a new
  test file is checked by name against its runner.** #471 added
  `test/mobile-pam-preserve.py`, and neither `test/all`, `test/patches.py` nor
  `test/port45.py` calls it, so CI and every local run were green without it
  ever running. *Check:* for every new file under `packages/<p>/test/`, `git
  grep -n '<basename>' <head> -- packages/<p>` finds a caller other than the
  file itself; then run it once by hand against the input it was written for.
  Extends L-454. *From:* #471, round 45, 2026-11-08.
- **L-587. A fail-closed test of a new "lock everything" mode starts from a
  state where the lock matters.** #503's NFS case packed no allowlist, so the
  guard was read-only with or without the new code. *Check:* for every new
  mode that overrides an allowlist, have the test start with the allowlist
  present, mutate the mode to log and fall through, and the test must fail.
  Extends L-419. *From:* #503, round 45, 2026-11-08.
- **L-588. A new package dependency brings its upstream example config into
  the root image, and the release identifier scan reads it.** dnsmasq, added
  for the Hotspot tile (#525), installs an `/etc/dnsmasq.conf` whose examples
  tripped the scan (#550). *Check:* when a PR adds a dependency to a package
  the image installs, list the dependency's `/etc` files (`bsdtar -tf` on its
  package) and run `tools/release scan` on them before the next release.
  *From:* #525, #550, 2026-11-08.
- **L-589. A PKGBUILD test that runs a tool needs that tool in
  `checkdepends`.** CI's runner and the build image had node and a phone
  didn't, so `check()` failed only in `tools/phone-install-package` (#545).
  *Check:* for every interpreter or command a `check()` or `test/all` runs,
  find it in `depends`, `makedepends` or `checkdepends`, not on the CI host.
  *From:* #545, 2026-11-08.
- **L-631. A detached-signature tamper test changes a byte inside the signed
  data or the signature packet.** gpg ignores bytes appended after a
  signature, so an "append junk, expect BAD" case passes a check that verifies
  nothing new (#547). *Check:* for each negative signature test, flip a byte
  in the middle of the signed file (`printf '\xff' | dd conv=notrunc bs=1
  seek=<n>`) and, separately, one inside the `.sig`, and see both refused.
  Extends L-454. *From:* #547, round 46, 2026-11-09.
- **L-632. A signature check behind an unsigned index proves who signed the
  file, not that it is current.** #547's keyring fetch verifies the package
  against a pinned key, but takes the version from the unsigned `omarchy.db`
  and refetches on any difference, so an older signed keyring would pass, and
  a cache hit uses the extracted files without a re-check (unlike
  `alarm_fetch`, which re-verifies the tarball every run). *Check:* for every
  signed download, name where the version comes from (index or verified
  metadata), whether an older version is refused, and whether the cached copy
  is verified again on use; `curl -I <db>.sig` tells whether the index is
  signed at all. Extends L-371 and L-422. *From:* #547, round 46, 2026-11-09.
- **L-633. An identifier-scan exemption justified by IEEE address bits is
  checked against Bluetooth addressing, and scoped to the file that needed
  it.** #550 skipped group-bit MACs image-wide because "no network card has
  one", but a Bluetooth LE static random address has its two top bits set and
  arbitrary low bits, so the group and locally administered exemptions
  together skip three quarters of them, and a byte-reversed BD_ADDR dump
  likewise. *Check:* for each exemption, feed one of each identifier kind
  AGENTS §1 names (Wi-Fi, Bluetooth public and random, gadget pairs) through
  the rule; prefer a path-scoped or literal exemption to a bit rule, and use
  RFC 7042's `00:00:5e:00:53:xx` for test values. Extends L-145 and L-563.
  *From:* #550, round 46, 2026-11-09.
- **L-634. The release scan's MAC pattern has blind spots a reviewer of an
  exemption should know:** an address after a colon (`tag:`, `id:`, `mac:`)
  never matches the lookbehind, and hyphenated or bare 12-hex forms aren't
  matched at all. *Check:* feed the scan `tag:<mac>`, a hyphenated MAC and 12
  bare hex digits before calling a MAC gate complete. *From:* #550, round 46,
  2026-11-09.
- **L-635. A gate's input collection is checked to land, not only its
  matcher.** The identifiers stage's two `rdump`s into one folder collide on
  the name `omamobile`, debugfs refuses the second, and `>/dev/null 2>&1 ||
  true` hides it, so `/var/lib/omamobile` had never been scanned; two rounds
  of review read the exemptions and took the dump on trust. *Check:* for a gate
  that gathers files (rdump, cpio, tar, find), run the gathering on a fixture
  with one marker file per source and list what arrived, and grep for `2>&1 ||
  true` around it. Extends L-145 and L-421. *From:* #550, round 46 (second
  look, correcting the first-round review), 2026-11-09.
- **L-636. A path-scoped exemption is mutation-tested for its scope, not only
  its content.** #550's tests caught a widened group bit, but not the option
  rule applied in any file, or the path without its leading slash. *Check:* for
  each exemption with a path condition, delete the condition and re-run the
  tests; if nothing fails, ask for an "elsewhere it is found" case. Extends
  L-145 and L-466. *From:* #550, round 46, 2026-11-09.
- **L-637. A count assertion over a series directory is a merge hazard.**
  #471's `test/source-family.py` asserts `== 28`, which fails on the first
  legacy fix, whichever PR brings it. *Check:* grep a PR's new tests for
  literal counts of files that other PRs add to, and ask for a count derived
  from a pinned list. Extends L-454. *From:* #471, round 46, 2026-11-09.
- **L-638. `kernel-pr-check`'s base device-tree build races with itself.** It
  passes every board as an explicit `.dtb` target to one `make -j`, and the
  top-level `%.dtb` rule starts one sub-make per target in the same
  directory, so they race on the directory's `.cmd` files; a "base's device
  trees don't all build" note that names a `.cmd` file and "missing separator"
  is that race, not the base (kernel #220, base `1a9d1d4e9289`,
  `sc8280xp-microsoft-arcata.dtb.cmd:43`). *Check:* the named `.cmd` file is
  complete afterwards, and the same base set builds with `-j1` or as one `make
  $(build)=arch/arm64/boot/dts/<dir>` call; the tool could build the base and
  head lists through a single sub-make. Extends L-30 and L-102. *From:* kernel
  #220, round 46, 2026-11-09.
- **L-639. A new `depends` on a virtual name is checked for its `provides`.**
  #533 added `'omamobile-notification-snapshot>=1'`, and the only provider was
  a commit on the contributor's fork, stacked on an unmerged PR, at a package
  version main had already shipped; CI is green because nothing installs the
  package. *Check:* for every added `depends` or `makedepends` entry that isn't
  an Arch or Omarchy package name, `git grep -n "provides=.*<name>"
  origin/main` and each open PR head; if it isn't on main, put the providing
  PR first in the merge order and check its version against main. Extends
  L-12 and L-426. *From:* #533, round 46, 2026-11-09.
- **L-640. A package bump is checked for version strings the package's own
  code prints.** #536 bumped omamobile-remote to 0.1.2 and the guide's install
  line, but the script's `version` command still printed 0.1.1 (#513 had
  bumped both). *Check:* on every version bump, `git grep -n -F '<old
  version>' <head> -- packages/<p> docs/`, and ask for a test that ties any
  printed version to the `version` file. Extends L-12 and L-263. *From:* #536,
  round 46, 2026-11-09.
