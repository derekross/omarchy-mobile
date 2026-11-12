<!-- SPDX-License-Identifier: MIT -->
<!--
Thanks for contributing. CONTRIBUTING.md §6.5 explains each item; a reviewer
looks at the pull request once CI passes and this is filled in. Never paste
serials, MAC or Bluetooth addresses, IMEIs, Wi-Fi names, getprop dumps or
partition contents: use placeholders such as <SERIAL>.
-->

## What and why

<!-- What changes, why, and the plan section or issue it follows (e.g. device/cheetah/AOC-PLAN.md C9g, #3). -->

## Device and build

- **Phone:** <!-- e.g. Pixel 7 Pro (cheetah), or "none: docs/tools only" -->
- **Kernel release (`uname -r`):** <!-- e.g. 7.3.0-rc6-omamobile-push1-00543-g1f83c16c0aba -->
- **Packages changed, with versions:** <!-- e.g. omamobile-shell 0.2.11 -->

## Checks (no phone needed)

- [ ] `tools/pr-check origin/main` passes
- [ ] `tests/all` passes
- [ ] `tests/packages` passes (or the packages I touched: ...)
- [ ] No package `version` bumped: the version is counted at merge (`tools/pkg-version`, CONTRIBUTING §6.3)
- [ ] Commits have area prefixes and bodies that say why; any AI help is a `Co-Authored-By:` or `Assisted-by:` trailer, never a `Signed-off-by:`

## On the phone

- [ ] I ran this on my own phone, booted into this build
- [ ] Runbook steps passed (plan, step, result): <!-- e.g. AOC-PLAN C9g-2: pass, -3: pass -->
- [ ] What I did **not** test: <!-- be specific -->
- [ ] Nothing in this change writes outside slot B and `userdata`, weakens the storage guard, or reads registers from userspace (AGENTS.md §1)

<details>
<summary><code>tools/phone-smoke</code> report</summary>

<!-- Paste the whole report here. -->

</details>
