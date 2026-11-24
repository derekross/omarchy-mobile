<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Shell and scripts (part 4 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-575. A Mesa `pkgrel` bump moves `_omamobile` with it (1.3 with
  omamobile3, 1.4 with omamobile4).** The marker is what shows in `GL_VERSION`
  and the libgallium name, so a bump that leaves it reports the old build on
  the phone. *Check:* `git log -p -- packages/mesa/PKGBUILD | grep -E
  '^[-+](pkgrel|_omamobile)='` on every Mesa PR. *From:* #500, round 45
  (missed in round 44), 2026-11-08.
- **L-576. A build host that is not Arch runs the tools' pacman steps in the
  container, with that container's view of keys and users.** `repo-add` there
  ran as `-u $(id -u)`, which under rootless Docker can't read the release
  keyring (#544), and the Omarchy keyring isn't on the host at all (#547).
  *Check:* a dry run of `tools/repo-publish` on a new build host before its
  publish timer is enabled. *From:* #544, #547, 2026-11-08.
- **L-613. An `EXIT` trap that clears a hang marker also runs when systemd
  times the unit out.** Bash runs the EXIT trap on SIGTERM, also mid-write
  when the block is interruptible, so #510's cleanup that removes the marker
  turned a timed-out hang into "finished", and the next boot would repeat it.
  *Check:* for a boot script with a marker and `TimeoutStartSec=`, find which
  code paths remove the marker, then run the script with its slow step
  replaced by a FIFO open and `kill -TERM` it: the marker should survive.
  Extends L-170 and L-468. *From:* #510, round 46, 2026-11-09.
- **L-614. A flag that blocks a repeated user action is checked for where it
  is cleared.** #461's `releasing` stops a second hang-up while the first is
  outstanding, but nothing clears it after a refusal or a timeout, so the
  Phone app can then never end the call. *Check:* for every "in progress" flag
  a PR adds to a user-facing method, `grep -n` every assignment and list the
  states that clear it; a terminal error path with no clear is a question.
  Extends L-302 and L-502. *From:* #461, round 46, 2026-11-09.
- **L-615. When a PR serializes one caller of a shared state change, the
  review re-lists the callers on today's main, not on the PR's base.** #508
  locked the power key's short action; #420, merged a day later, added two
  more display transitions in the same script that don't take the lock.
  *Check:* `git diff <merge-base> origin/main -- <file>` for new entry points
  that reach the same helpers (`wake_*`, `lock_dark`, `omarchy-system-lock`),
  and ask whether each takes the lock. Extends L-462 and L-572. *From:* #508
  with #420, round 46, 2026-11-09.
- **L-616. Moving a UI removal behind an acknowledgment is checked against
  what the row's own animation leaves on screen while it waits.** In #533,
  `NotificationRow` folds to height 0 and only then calls
  `forgetNotification`, so the row stays in the model, invisible, until the
  reply; on a refusal it stays invisible until the next refresh, and a model
  reset during the wait re-creates the delegate at full height. *Check:* read
  the delegate's end-of-gesture code (the fold or fly-off) and the list's
  refresh timers, list what the user sees on success, on failure and when a
  refresh lands mid-wait, and ask the phone test to cover the last one.
  Extends L-573. *From:* #533, round 46, 2026-11-09.
- **L-617. A feature flag that a backend must report starts false in the
  UI.** #539's `shareAvailable: true` drew the VPN boxes on every open until
  the state line came, and kept them if parsing failed. *Check:* for each
  `*Available` property a page reads from a helper, its default and the
  `catch` path. Extends L-161 (fail towards not offering what isn't there).
  *From:* #539, round 46, 2026-11-09.
- **L-618. A Qt fixture that stands in for a production animation is checked
  for how that animation is declared.** #518's test gates on a free-standing
  `NumberAnimation` it starts by hand, while the real `revealAnimation` lives
  in `Behavior on reveal`; whether a Behavior's animation reports `running`,
  and when, decides whether the gate works on the phone (on Qt 6.12.0 it does,
  synchronously on the property change). *Check:* when a fixture rebuilds an
  animation, timer or handler outside its real context, write a ten-line
  qmltestrunner case with the production declaration (a Behavior with an
  `id`, plus a `Connections` on `runningChanged`) and log when the property
  changes before accepting the fixture's result. Extends L-454. *From:* #518,
  round 46, 2026-11-09.
- **L-619. A gesture strip at `z: 100` over a scrolling list is probed for
  which of the two takes an upward drag.** #553's 36 px DragHandler strip at
  the bottom of the Wi-Fi page overlapped the list's last ~18 px, and the
  probe showed the strip wins: the page closed and the list didn't scroll.
  *Check:* compute the overlap from the phone's real values (`gaps_out = 0` in
  `hypr/phone.lua`, the panel padding), then run a 30-line qmltestrunner probe
  with the same handler over a ListView and swipe once inside and once
  outside the overlap. Extends L-160. *From:* #553, round 46, 2026-11-09.
- **L-620. A drag handler that measures `mouse.y - startY` inside an item its
  own offset moves follows the finger at half speed.** Main's quick-settings
  sheet and #553's card both do; a probe gave offsets `-10,-10,-20,-20,…` for
  a finger moving 10 px a step, so a 60 px threshold needs 120 px. *Check:*
  for any new drag that moves its own parent, run the probe, or read whether
  the delta is taken in scene or window coordinates. *From:* #553, round 46,
  2026-11-09.
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
