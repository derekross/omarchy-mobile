<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Shell and scripts (part 4 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-621. A surface condition that adds "or the keyboard is up" is checked
  against every client that raises the keyboard, not only the one the PR is
  about.** #557 meant the dock's and drawer's search, but `oskOpen` follows
  squeekboard's visibility for any surface, so the strip (and its
  drawer-opening swipe) also appears under quick settings' Wi-Fi password on
  the home screen. *Check:* find where the flag comes from
  (`omamobile-osk-watch`), list the surfaces with text fields that can be up
  on the home screen (Wi-Fi, Bluetooth, Hotspot, the lock), and walk the new
  branch for each. Extends L-160. *From:* #557, round 46, 2026-11-09.
- **L-622. Relaxing one term of a visibility condition can expose an old race
  that the term used to mask.** In #557, `appOnScreen` kept the strip off
  under a lock taken from the home screen whatever `sessionLocked` said; with
  `|| oskOpen`, the asynchronous lock query's stale answer now matters there
  too. *Check:* for each term a PR loosens, list the other terms that are
  asynchronous or cached and ask what they read in the window the old term
  covered. *From:* #557, round 46, 2026-11-09.
- **L-623. When a fix removes an error, check what that error was stopping.**
  `omamobile-update` run as root over SSH had no `OMARCHY_PATH`, and Omarchy
  4.0.6's `omarchy-update-dev` died on the unbound variable before anything
  ran; #548's first change passed `OMARCHY_PATH` on, which would have let a
  root run go on to Omarchy's migrations, and Omarchy keeps the per-user
  record of which ran in `$HOME`, so a root run re-runs every one as root (59
  on the 11-09 test install, through the NOTES gotcha's `OMARCHY_PATH=…`).
  #548 now refuses root. *Check:* for a fix that makes a failing path
  succeed, run the path with the fix and list what now executes after the old
  failure point, as which user and with which `$HOME`, and ask which of those
  steps keep per-user state. Extends L-29 and L-499. *From:* #548 with #560,
  round 46, 2026-11-09.
- **L-624. A fix that refuses a command is grepped against our own runbooks
  for that command.** #548 refuses `omarchy update` as root, while
  `tools/release`'s test-install steps print it under "over USB SSH", where
  the login is root, and that runbook is what led to the 11-09 run.
  *Check:* for any new refusal, `git grep` the command in `tools/release`,
  `docs/`, `device/*/*-PLAN.md` and the NOTES gotchas, and check the user each
  one runs as (`tools/phone-ssh` is root). *From:* #548 with #560, round 46,
  2026-11-09.
- **L-625. A sleep test run through a direct `/sys/power/state` freeze doesn't
  cover hooks added in the same PR.** #556's cycles were `rtcwake` runs, which
  skip `system-sleep` hooks (AGENTS §4, the 9a NFC gotcha). *Check:* compare
  each hook's commit time with the runs, and ask for cycles through
  `systemctl suspend` for any new or changed `system-sleep` hook. Extends
  L-392. *From:* #556, round 46, 2026-11-09.
