<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Shell and scripts (part 1 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-1171. A test that reads the real machine (a fixed system path, the real
  `systemctl`) passes on a laptop and fails on a provisioned phone, where
  `tools/phone-install-package` runs `check()`, and a test that leans on the
  host's speed fails on the slower build host.** #933's "not installed" case
  read `/usr/lib/omamobile-vendor/gnss/root`, which a provisioned phone has;
  the set-pin keeper test forked once per `/proc` entry and raced on the build
  host (#1017). *Check:* `grep -n '"/usr/\|"/etc/\|"/var/\|/proc\|systemctl'
  <test>` for every path or command the test doesn't point at a stand-in, and
  say what a provisioned phone holds there; for a test that waits on a scan or
  a loop of forks, ask for a bound that doesn't depend on the host's speed.
  Extends L-933, L-1132 and L-454. *From:* #933 and #1017, the maintainer's
  assistant, 2026-11-24.
- **L-1170. A test that binds a Unix socket under its temporary folder fails
  where that path passes about 108 bytes (`AF_UNIX path too long`), and a
  phone's build folder does.** `tools/phone-install-package
  packages/omamobile-shell` could not install any shell on the Pixel 7 Pro
  until #1037 bound the install-hook test's socket by its short name from
  inside the folder; the tests of install-link, mmd, modem-sit and libfprint
  still bind full paths. *Check:* for a test that makes a socket (`AF_UNIX`,
  `UNIX-LISTEN`, `nc -lU`, `QLocalServer`), ask for a short name bound from
  inside the folder, or run it once with `TMPDIR` set to a folder whose path
  is 100 bytes long. Extends L-589 and L-334. *From:* #1037, the maintainer's
  assistant, 2026-11-24.
- **L-1169. A fix that relies on the parent-death signal is checked against
  how the parent's supervisor restarts it: an in-place restart under the same
  PID sends no signal.** #998's `setpriv --pdeathsig` covered the shell's end
  and an ordinary restart, and the author's palmtop run found that
  Quickshell's crash handler restarts the shell under its own PID, so the old
  helpers stayed and a second set started. *Check:* for a `pdeathsig`,
  `PR_SET_PDEATHSIG` or `prctl` change, find out whether the parent can
  restart without exiting (an `exec` of itself, a crash handler), and ask for
  a run of that path with the children counted. Extends L-734 and L-468.
  *From:* #998, round 67, 2026-11-24.
- **L-1168. An idempotency guard added on a review's suggestion is walked
  through the failure of the step between the saved state and the new one.**
  #995's `was_off = self.cfun == 0` made a repeated `radio on` harmless, and
  also made a `radio on` after a failed `AT+CFUN=0` (IMS already withdrawn,
  level unchanged) skip the restore that the earlier head would have run.
  *Check:* for a guard keyed on a state variable, list each step between
  reading the variable and updating it, make each raise in turn in the
  simulator, and ask what the next call does; a side effect done before the
  failing step needs its own flag. Extends L-1133 and L-757. *From:* #995,
  round 67, 2026-11-24.
- **L-1167. An Omarchy patch that changes layout by width is computed with the
  rounding of both sides and the phone's margin before a reference-phone run
  is asked for.** #1026's condition compares two rounded values
  (`fittedContentWidth` and `Style.space`), so it is false at full width by
  construction; with `availableCardWidth = screenW - 2 * Style.gapsOut`, the 7
  Pro's 480 px keeps the old branch. *Check:* read the helper that produces
  each side of the comparison in the pinned package (`bsdtar -xOf` the signed
  package), write the reference phone's value of each, and say which branch it
  takes; ask for a run only if it takes the new one. Extends L-703 and L-491.
  *From:* #1026, round 67, 2026-11-24.
- **L-1166. A shell PR that loads an upstream component unchanged is reviewed
  for everything that component offers, not only what the PR's description
  shows.** #1024 loads Omarchy's power, network and Bluetooth panels for their
  cards; with them come power profiles, a DNS changer, Wi-Fi sharing and a
  speed test, none named in the description. *Check:* `bsdtar -xOf` the signed
  package's file, list its buttons and the commands behind them (`grep -n
  'onClicked\|command:\|execDetached\|bar.run'`), and put each that changes
  system state or reaches a network on the maintainer's list. Extends L-818
  and L-1125. *From:* #1024, round 67, 2026-11-24.
- **L-1165. A daemon's test that sets `HOME` for a scratch config also sets
  every `XDG_*` variable the code prefers over `HOME`, or it reads the
  tester's own files.** #1025's `test/dozed.sh` set `HOME`, the daemon reads
  `${XDG_CONFIG_HOME:-$HOME/.config}`, and on a desktop session 7 of 52 checks
  read the reviewer's real `~/.config/omamobile/`. *Check:* `grep -n
  'XDG_[A-Z_]*HOME' <the code>` against the variables the test exports; run
  the suite once with `XDG_CONFIG_HOME` set to an empty folder outside the
  scratch tree, once unset, and compare. Extends L-1034 and L-454. *From:*
  #1025, round 67, 2026-11-24.
- **L-1164. A value a backend adds to its answer is grepped for in the page
  before the code that computes it is reviewed.** #1022's `get` returns
  `active`, computed by a new name list of "real keyboards" and a `hyprctl -j
  devices` call at every read; `KeyboardPage.qml` never reads it, so the only
  effect of the code was a third keyboard rule against the maintainer's
  one-writer decision. *Check:* for each key in a backend's JSON
  (`out({...})`, `state()`), `grep -n '<key>' app/*.qml` on the head; a key no
  page reads is asked out with its helper. Extends L-983 and L-1094. *From:*
  #1022, round 67, 2026-11-24.
- **L-1135. A Dockerfile branch on a BuildKit automatic argument is read for
  what the legacy builder leaves in it.** #1016's `TARGETARCH` test picks the
  non-amd64 branch when the argument is empty, which `DOCKER_BUILDKIT=0` and
  older builders give, so an x86 machine would build the arm64 image. *Check:*
  `grep -n 'TARGET\|BUILDPLATFORM' docker/Dockerfile`, and for each test name
  the value when the argument is unset; prefer `dpkg --print-architecture` (or
  `uname -m`) inside the `RUN`, with a refusal for anything unplanned. Extends
  L-282 and L-783. *From:* #1016, round 66, 2026-11-23.
- **L-1134. A tile that toggles from another package's published state is
  walked with that package at main's version: does the second tap undo the
  first?** #996's tile sends `radio off` and then reads `modem.radio`, which
  main's sitd takes from the modem's indications and which didn't follow
  `AT+CFUN=0` on the 9a; with sitd 0.3.44 every tap would read "off" and send
  `radio off` again, so the radio could be turned off from the tile and never
  back on. Its test set the state file by hand. *Check:* for each
  `*-state.sh`/`*-action.sh` pair, find the writer of the field the state
  reads (`git grep -n '<field>' origin/main -- packages/<writer>`), run the
  action and then the state against what main's writer would publish after it,
  and ask for a guard keyed on a field only the new writer has, or a versioned
  `depends`. Extends L-911, L-616 and L-161. *From:* #996 with #995, round 66,
  2026-11-23.
- **L-1133. A new state-restoring action is checked for being idempotent: run
  it twice in the state it restores to.** #995's `radio on` calls
  `radio_back()` whatever the previous level was, so a repeat while IMS is
  registered withdraws and re-sends the registration. *Check:* for each new
  "after X comes back, set Y up again" hook, read the guard that decides
  whether X actually went away, and write the repeat case into the test.
  Extends L-757 and L-913. *From:* #995, round 66, 2026-11-23.
- **L-1132. A simulator change that makes the fake modem end bearers (or raise
  any new event) is run with a logging stand-in for `systemctl` first on
  `PATH`, because the real daemon's recovery paths call the host's systemd.**
  #995's `sit-sim` now ends every bearer at `AT+CFUN=0`, so `test_sim` reached
  `reconnect()`, which stops and starts `omamobile-sit-data.service` on the
  machine running the test; main's suite never got there, and
  `tools/phone-install-package` runs `check()` on a phone. *Check:* `grep -n
  'subprocess.run(\[.systemctl' <daemon>` for every recovery path a new
  simulated event can reach, then run base and head with `PATH=<logging
  stand-in>:$PATH` and compare the logs. Extends L-410, L-454 and L-681.
  *From:* #995, round 66, 2026-11-23.
- **L-1131. A test case that hides a stand-in to test "the program is missing"
  reaches the host's copy when the stand-ins sit in front of the host's
  `PATH`, and a package that depends on the program has it on every phone that
  runs `check()`.** #1014's "no wf-recorder" case hid its fake recorder; with
  any `wf-recorder` later on `PATH`, the script started it on the screen's
  output and the cleanup killed only the fake's path. *Check:* for every
  `hide`, `mv`, `rm` or `chmod -x` of a stand-in in a test, grep the package's
  `depends` for the program; if it is listed, put a stand-in "host" copy later
  on `PATH` and run the case, which must not start it. Ask for the program's
  path in a variable the test sets. Extends L-961 and L-454. *From:* #1014,
  round 66, 2026-11-23.
- **L-1130. An exception raised from a signal handler is caught by every
  `except Exception` in the code it interrupts, so a "handle SIGTERM like the
  normal exit" fix is read for those blocks.** #932's `Stop(Exception)` is
  swallowed inside the iio-sensor-proxy calls ("keep the last state"), and the
  tool runs on until SIGKILL. *Check:* `grep -n 'signal.signal' -A3` for a
  handler that raises, then `grep -n 'except Exception\|except:'` in the same
  module and ask whether each wraps a blocking call; prefer a `BaseException`
  subclass or a flag the loop reads. Extends L-734 and L-960. *From:* #932,
  round 66, 2026-11-23.
- **L-1111. A helper that replaces several "check, then read again" call sites
  is reviewed as a per-caller table of what a failed read decided before and
  after, and each caller gets two mutations: "ignores the result" and "goes on
  after the helper fails".** #969's four callers each had a different old
  shape (one with no check at all), and only the table showed that none got
  weaker; the two mutations per caller showed that each is held by its own
  test, not only the helper. *Check:* `git grep -n '<file>' <base> -- tools
  bin` for the old readers, one table row each, then `sed` the caller's `||
  die` into `|| var=` and its match into `if false`, and read the `not ok`
  line for that caller's name. Extends L-1097 and L-742. *From:* #969, round
  65, 2026-11-21.
- **L-1110. A pipe from a producer into a remote "unpack, then swap" is asked
  what the producer writes when it fails.** GNU tar exits 1 or 2 on a source
  file it can't read and still closes a valid, shorter archive, so the
  consumer's own exit status says nothing, and `pipefail` reports the failure
  only after the remote swap has happened: `tools/repo-push` would have
  replaced the phone's repository with a partial one and deleted the old copy.
  *Check:* `git grep -n 'tar c.* | .*ssh\|tar c.* | tools/phone-ssh' -- tools
  bin` for other pushes of this shape, and for each ask whether the receiving
  side replaces something on success; the fix is to finish and check the
  archive before the link is opened. Extends L-15. *From:* #965, round 65,
  2026-11-21.
- **L-1109. A measuring tool that takes its sleep inhibitor after its first
  readings measures whatever auto-sleep leaves.** #953's first run was
  suspended for four seconds during its first part and lost its Wi-Fi line to
  the sleep hook; the author found it in the journal only because we asked why
  one line was empty. *Check:* in any on-phone measuring script, find the line
  that takes the inhibitor and list every reading above it; ask for a suspend
  count over the whole run in the output (`/sys/power/suspend_stats/success`
  at start and end). Extends L-1013 and L-725. *From:* #953, rounds 63 and 65,
  2026-11-21.
- **L-1097. A hardening of one reader of a checked file is followed by a grep
  for the other readers of the same file after the same check.** #960 closed
  `fetch-published`'s read-after-check gap on `omamobile-revoked`;
  `signing_key_load`, `release-upload` and `repo-publish` keep the same
  `2>/dev/null` read that fails towards "not revoked". *Check:* `git grep -n
  '<file>' -- tools bin` and, for each reader, what a failed read decides;
  name the follow-up or a shared helper. Extends L-788, L-803 and L-716.
  *From:* #960, round 64, 2026-11-21.
- **L-1096. A test runner that ends in `exec` never runs its own `trap ...
  EXIT`, and a PR that calls it from a second path doubles the leftovers.**
  `test/lock-glance` makes a work folder, sets the trap, then `exec`s
  qmltestrunner, so each run leaves the folder; #957 added a second caller.
  *Check:* `grep -n '^exec \|trap .* EXIT' <runner>` for both in one script,
  and list `TMPDIR` after a run made with a scratch `TMPDIR`. Extends L-468
  and L-734. *From:* #957, round 64, 2026-11-21.
- **L-1095. A fix that stops a session service "so the other one gets there
  first" is run with the other one failing to start.** #763's `on` began
  stopping squeekboard before restarting fcitx5; under `set -e` a failed
  fcitx5 restart then ended the script with no keyboard and no message, where
  the previous head left the keyboard running. *Check:* for each new `stop X;
  start Y; start X` in a `set -e` script, run it with Y's start exiting 1 (the
  test's stand-ins usually allow it) and read the order log for X's start; ask
  for an EXIT trap set right after the stop. Extends L-1087, L-962 and L-733.
  *From:* #763, round 64, 2026-11-21.
- **L-1088. A fix that restores state wiring is reviewed for every consumer of
  the restored state, not only the symptom in the title.** #920 restores three
  properties to the 4.5 lock view to fix a stale battery level; the same
  properties gate the dark-touch rule (0029), the wake guard, the glance's
  return and the media ticker, so the merge changes what a touch on a dark
  locked phone does on every phone. *Check:* `grep -n '<each restored
  property>'` over the patched files of the real package, list each consumer
  and what it did while the value was stuck at its default, and ask for the
  one that changes user input on a phone. Extends L-535 and L-491. *From:*
  #920, round 63, 2026-11-20.
- **L-1087. A cleanup step added to an `off` path under `set -e` is placed, or
  guarded, so that its failure can't stop the rest of `off`.** #763's
  `remove_language` runs between "switch removed" and "daemons stopped"; with
  a `gsettings` that exits 1 the script ends there, and `status` says off
  while fcitx5 still holds the input method. *Check:* for each new command in
  a teardown path, run the path with that command's stand-in exiting 1 and
  list which later steps didn't happen; ask for the new step last or behind
  `|| warn`. Extends L-468 and L-733. *From:* #763, round 63, 2026-11-20.
- **L-1081. A change that swaps the key Back sends to one class of window is
  checked against the states of that window where the old key did something.**
  #582 sends Alt+Left to a browser instead of Escape; Escape also leaves
  fullscreen and closes in-page overlays, which the test plan (edges, dialog,
  keyboard) did not name. *Check:* list what the replaced key does in the
  target app besides the case the PR is about, and put each on the phone run.
  Extends L-160 and L-722. *From:* #582, round 63, 2026-11-20.
- **L-1069. A `Condition*=` turned into a waiting `ExecCondition=` makes the
  unit's start job last as long as the wait on every phone where the awaited
  thing never appears.** #903's 10 s wait is free on a normal boot, but on a 7
  Pro whose AoC start was skipped it holds `multi-user.target`, and the units
  ordered after it (`omamobile-boot-success`, the camera start), for 10 s.
  *Check:* list the unit's `WantedBy=` targets and `git grep -n
  'After=.*<target>'` over the device packages; name the phones and boots
  where the wait runs to its end; reproduce the line with `systemd-run --user
  -p ExecCondition=...` (it also shows whether systemd leaves the shell's
  `$(...)` alone). Extends L-467 and L-670. *From:* #903, round 63,
  2026-11-20.
- **L-1054. A redraw flag set on every loop pass is traced through the output
  that has its own wake-up source.** #771's countdown sets `dirty` each pass,
  meant for a 500 ms poll timeout; on DRM the page-flip event wakes the poll,
  so the loop runs at the flip rate, and the tests' memory output has no such
  event. *Check:* for each `dirty = 1` outside an event handler, list the fds
  in the `poll` set and ask which of them the draw itself makes readable.
  Extends L-454 and L-618. *From:* #771, round 63, 2026-11-20.
- **L-1050. A journal query for "the boot in which unit X ran" must not match
  `UNIT=X`: a unit whose `Condition*=` fails logs a skip entry with that field
  on every boot.** #633's first-boot row matched `_SYSTEMD_UNIT=... +
  UNIT=...` for a `ConditionPathExists=` unit wanted by `multi-user.target`,
  so "the first boot" was the oldest boot in the journal, and its stand-in
  `journalctl` returned nothing for a rotated journal. *Check:* read the
  unit's `Condition*=` and `WantedBy=`; on any systemd host, `journalctl -b -o
  json --output-fields=UNIT,MESSAGE -g 'unmet condition' -n 1` shows the
  field; match `_SYSTEMD_UNIT=` (the process's own output) or the start
  message's ID instead, and write the opposite stand-in. Extends L-685 and
  L-454. *From:* #633, round 63, 2026-11-20.
- **L-1042. A report that names columns by position from one listing and reads
  values from another is fed a listing with a hole.** #953 named Part B's zone
  temperatures from Part A's order, and a failed zone read shifts every later
  name; a status of two words shifts the awk fields the same way. *Check:* one
  fixture with a missing middle element and one with a space inside a field,
  and read the summary line against the raw block. Extends L-16. *From:* #953,
  round 63, 2026-11-20.
- **L-1041. A redaction test whose two secrets contain each other tests one of
  them.** #953's fixture used a user name that is a prefix of its host name;
  with the host replacement removed the test still passed. *Check:* delete
  each replacement in turn and rerun; fixtures use names that share no
  substring. Extends L-419. *From:* #953, round 63, 2026-11-20.
- **L-1040. A tool that hides names by pasting them into a `sed` program is
  run once with a name that is a sed command.** #953's `sed
  "s/\b$user\b/<user>/g"`, with the name read from a file in the run folder,
  executed `touch` through GNU sed's `e`; the same quoting gap leaves a name
  with `/` or a regex character in the published report. *Check:* `grep -n
  'sed "s/.*\$' <tool>` for variables inside a sed script, find where each
  value comes from (a file the tool re-reads counts as outside input), and run
  the tool on a fixture whose value is `a/b/;e touch <scratch>/made-by-sed;#`.
  Extends L-716 and L-454. *From:* #953, round 63, 2026-11-20.
- **L-1037. A package test that opens a Unix socket under `$TMPDIR` fails with
  "path must be shorter than SUN_LEN" when the scratch folder is deep.**
  omamobile-install-link's `test/all` did under a review folder several levels
  down, on a PR that doesn't touch it. *Check:* read the failure message
  before blaming the PR; such a suite is run with a short scratch path, or
  left to CI. Extends L-674. *From:* #907, round 63, 2026-11-20.
- **L-1034. An XDG fallback is run with only `HOME` set.**
  `${XDG_DATA_HOME:-$HOME}` is the home directory, not `~/.local/share`, and a
  test that sets the XDG variable can't see it. *Check:* `env -i
  HOME=<scratch> <tool>` and list the scratch home afterwards. Extends L-681.
  *From:* #855, round 63, 2026-11-20.
- **L-1033. A new value of an existing option that is "extracted as a mode"
  before the option is used is followed through every later test of that
  option.** #855 emptied `known` for `tofu`, and the line that decides whether
  a call is a custom context (`-n $key$known$alias...`) then treated a pinned
  call as the default policy: the same control path, so a shared master opened
  unchecked carried it. *Check:* `grep -n '\$<var>'` below the extraction for
  every use of the cleared variable, and run the tool with a stand-in `ssh`
  under each mode with `OMAMOBILE_SSH_SHARE=1`, comparing `ControlPath`.
  Extends L-450 and L-454. *From:* #855, round 63, 2026-11-20.
- **L-1026. A call added to an essential step of a failure-tolerant runner is
  read against the fallbacks of its neighbours.** #839's `systemctl
  daemon-reload` sits in a function where every other `systemctl` ends in `||
  echo` or `|| true`; alone without one, it turns a slow reload into a skipped
  firewall setup, and the test's fake `systemctl` never fails. *Check:* for
  each new command in a `step ... essential` function, `grep -n '||'` its
  siblings; if they tolerate failure and the new one doesn't, list what
  follows it in the function and ask for the fallback and a failing-fake case.
  Extends L-468 and L-761. *From:* #839, round 63, 2026-11-20.
- **L-1020. A check script whose tests all run in a "config only" mode has no
  test of its hardware block, and a PR that extends that block inherits the
  gap.** #935 added an msm branch to `omamobile-waydroid-check` beside a
  Panthor branch no test reaches. *Check:* for each environment switch the
  tests set (`CONFIG_FILE`), list the blocks it skips, and ask the PR that
  edits one for a sysfs override and a case per branch, the old one included.
  Extends L-234 and L-454. *From:* #935, round 63, 2026-11-20.
- **L-1017. A marker file that makes the lock path stand aside is checked for
  every way its writer can die.** #932's "dark for the ear" marker is removed
  in a Python `finally`, which SIGTERM skips, and `omamobile-keys
  dark-unlocked` trusts the bare file. *Check:* for each `[[ -e <marker> ]] &&
  exit 0` added before `omarchy-system-lock`, find the writer's signal
  handlers and its start-up cleanup, and ask for a liveness check on the
  reader's side. Extends L-161 and L-734. *From:* #932, round 63, 2026-11-20.
- **L-1005. A "skip the expensive poll" fast path is walked against every duty
  of the full poll, not only the one it is meant to save.** #915's quiet poll
  saved the refusal checks and, with them, skipped the `suspend_stats` read
  that is the daemon's documented fallback for an unannounced resume. *Check:*
  list what the full iteration reads and does before the point the fast path
  jumps past, mark each "still covered by" or "skipped", and for each skipped
  one inject its event into the PR's own harness with the fast path active and
  compare the reaction time on main and on the head. Extends L-715, L-573 and
  L-468. *From:* #915, round 63, 2026-11-20.
- **L-995. A delayed child start is injected with a `sitecustomize.py` on
  `PYTHONPATH` that keys on `sys.argv[0]`.** #948's test starts Python tools
  with its own environment, so a three-line `sitecustomize` outside the
  worktree that sleeps only when `argv[0]` ends in the tool's name delayed
  just the tool: main's test then failed with the reported return code and the
  head passed, with neither file touched. *Check:* for a "the child wasn't
  ready yet" fix, run base and head with the child's start delayed past the
  old sleep, and compare the base's failure with the reported one by its
  values. Extends L-706. *From:* #948, round 63, 2026-11-20.
- **L-994. A script that restarts a unit is checked against that unit's own
  start limits.** sddm ships `StartLimitBurst=2` in 30 s; the `systemctl
  restart` of #947's default-on guard counts against it, so a restart right
  after sddm's own two leaves the display manager stopped. *Check:* `systemctl
  cat <target>` (or the package's unit file) for `StartLimit*`, `Restart=` and
  `PartOf=` before accepting a script that restarts it. Extends L-174 and
  L-670. *From:* #947, round 63, 2026-11-20.
- **L-993. `n=$(grep -c PATTERN FILE)` in a `set -e` test ends the test
  silently when the count is 0.** In #947 the assertion `(( n == 1 )) || fail
  "..."` on the next line never ran: with the feature removed the suite exited
  1 with no `not ok` line. *Check:* `grep -n '=\$(grep -c' <test>` in new test
  code, and run the mutation that makes the count 0; ask for `|| true` inside
  the substitution. Extends L-14 and L-41. *From:* #947, round 63, 2026-11-20.
- **L-992. A watchdog that restarts a service "once per cooldown" is run
  against a failure the restart doesn't cure, for an hour of its clock, and
  the restarts are counted.** #947's guard bounds the rate (one per 600 s) and
  its test asserts three restarts in 30 minutes as correct; the 300 s grace
  applies only to the first, since the loop is seen again within seconds.
  *Check:* feed the PR's own fake journal a loop of an hour, count the restart
  calls and read each one's reason; ask for a per-boot cap and for what the
  device is left with at the cap. Extends L-302 and L-377. *From:* #947, round
  63, 2026-11-20.
- **L-991. A guard written as a header is compiled alone and run against
  made-up environments, and its "as written" branches get the inputs
  canonicalisation would have changed.** #930's `home_guard.h` has no Qt in
  it, so a five-line `main` and `env -i` cases showed that it refuses the real
  home in every spelling, and where it disagrees with its own runner: a
  `TMPDIR` through a symlink makes `test/all` refuse itself, and a
  non-existent path with `..` in it passes. *Check:* for a path guard, list
  which inputs are resolved and which are compared as text, then feed it a
  symlinked parent and a `..` path for each text-compared one; a refusal test
  in the committed suite uses a fixture outside a scratch `TMPDIR`, never the
  real home. Extends L-454 and L-664. *From:* #930, round 63, 2026-11-20.
- **L-990. A QML `Text` given a fixed height for N lines is sized `N *
  Math.ceil(lineSpacing)`, and a probe counts `lineCount` at several font
  sizes.** #894 reserved `Math.ceil(lineSpacing * 3)`; Qt lays each line out
  at a whole pixel height, so at seven of ten sizes the third line no longer
  fit and `maximumLineCount: 3` with `elide` silently showed two. The render
  test checks button geometry only, and the request ("reserve three lines")
  was ours. *Check:* copy the `Text` into a `qmltestrunner` case, set a string
  long enough for N+1 lines, and read `lineCount` and `contentHeight` against
  `height` at sizes 10 to 20 with the shell's font; ask the phone run for a
  string that needs all N lines. Extends L-618 and L-229. *From:* #894, round
  63, 2026-11-20.
- **L-986. A test that identifies a process by a `/proc/<pid>/fd` link
  compares paths the container spells differently.** #954's keeper check
  wanted `fd/0` to read `/dev/ptmx`; in CI's container `/dev/ptmx` is a
  symlink to `pts/ptmx`, the same pty reads `/dev/pts/ptmx`, and the test
  failed every time there while passing on every desktop. *Check:* for a test
  that reads `/proc/*/fd`, `/proc/*/exe` or `/dev` paths, run its scenario
  once in the project container (no network, the scratch folder mounted
  read-only) and print what it sees before blaming the code or the runner;
  `bash -c 'exec 9<>/dev/ptmx; readlink /proc/$$/fd/9'` shows the two
  spellings. Extends L-674 and L-454. *From:* #954, round 63, 2026-11-20.
- **L-984. An indicator driven by an event stream with no "removed" event is
  walked through the disconnect.** #949 reads devices on a new keyboard's
  first event, and Hyprland's socket never says a keyboard left, so the label
  outlives the keyboard. *Check:* for each state a PR sets from an event, name
  the event that clears it; if none exists, ask for a bounded re-read while
  the state shows. Extends L-235 and L-614. *From:* #949, round 63,
  2026-11-20.
- **L-983. A "hardware keyboard" test by device name is checked against the
  names the phones' own keys have, and against a sibling PR that answers the
  same question another way.** #949 filters Hyprland's keyboards with a name
  list (`gpio-keys`, `power-button`, ...) taken from a desktop widget, while
  #866 from the same author counts real keyboards by bus and key capabilities;
  a phone key under another name would make the bar label permanent. *Check:*
  ask for `hyprctl -j devices` keyboard names from each supported phone with
  nothing attached, and `git grep -n 'ID_INPUT_KEYBOARD\|bustype\|untyped'`
  over the author's open heads for a second definition. Extends L-469 and
  L-720. *From:* #949 with #866, round 63, 2026-11-20.
