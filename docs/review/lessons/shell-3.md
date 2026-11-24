<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Shell and scripts (part 3 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-714. A "learn the user's choice" feature is probed with the sensor at
  its floor and its ceiling.** The 7 Pro's light sensor is under the panel, so
  a covered reading is common; one slider move while covered taught #636's
  curve 206 nits for the dark. *Check:* run the learning path at both ends and
  print what the learned curve then gives a decade either side. Extends L-536.
  *From:* #636, round 50.
- **L-713. A daemon that shares a sysfs value with an input handler is probed
  for a write landing between its read and its write.** #636 reads the
  backlight before each ramp step so the slider wins, but `omamobile-keys`'
  write of 0 in that gap is overwritten and the lock shows lit. *Check:* drive
  the controller on a fake device whose `write` hook changes the value first,
  and walk every other writer on main (`git grep -n
  'brightnessctl\|omarchy-brightness' packages`). Extends L-537 and L-615.
  *From:* #636, round 50.
- **L-712. A line a setup step writes into a user's config that loads a
  package file is checked for the package going away.** #635 puts a bare
  `dofile()` into `monitors.lua`; after a downgrade or a branch switch the
  rest of the file doesn't run and Hyprland's default scale (2) takes over.
  *Check:* evaluate the generated file with the target missing, and ask for a
  guarded load with the old values as fallback. Extends L-442. *From:* #635,
  round 50.
- **L-711. A shell PR that adds a surface is re-read against the Back rules
  main gained since its base; a clean merge hides them.** After #643, #539's
  Hotspot page still closed everything on Escape (the one page where Back
  skips a level), and #612's two always-mapped layers weren't in
  `HomeModel.BACK_FURNITURE`, which takes Back away from the home screen.
  *Check:* `git log <merge-base>..origin/main --
  packages/omamobile-shell/plugins/omamobile.back`; each close path of the new
  surface against the rule; `git grep -n 'namespace:' <head>` against
  `BACK_FURNITURE` and `COVERING_LAYERS`. Extends L-615. *From:* #539, #612
  and #582 with #643, round 50.
- **L-710. `EPOCHREALTIME` carries the locale's decimal separator.** #640's
  `${EPOCHREALTIME/./}` deadline became a comma expression under a comma
  locale: a nonsense end time, and an octal error that ended the loop at
  random. *Check:* `grep -n EPOCHREALTIME` in the diff; run the arithmetic
  under a scratch comma locale (`localedef -i de_DE -f UTF-8
  DIR/de_DE.UTF-8`, then `LOCPATH=DIR LC_ALL=de_DE.UTF-8`); prefer `date
  +%s%3N` or strip `[.,]`. *From:* #640, round 50.
- **L-709. A second writer of a credential is compared with the first one's
  bookkeeping.** `omamobile-set-pin` records pin-or-password and sets the
  lock's keypad toggle; #630's page calls the same `passwd` and knows nothing
  of the record, so a password phone can't use it. *Check:* `git grep -n
  passwd origin/main -- 'packages/*/bin'` and list every file the existing
  path writes besides the password. Extends L-450. *From:* #630, round 50.
- **L-708. A page that starts a credential change is checked for where the
  result goes when the page is destroyed.** #630's Change PIN page drops its
  result when Back, a relaunch (`navigate("root")`) or a D-Bus `Open` destroys
  it while `passwd` runs, so the PIN can change with nothing on screen.
  *Check:* list every way the page can go away mid-change, and ask that the
  result outlive the page (kept in the runner, or a notification). Extends
  L-616. *From:* #630, round 50.
- **L-707. A settings page is run once from the state most phones are in: its
  dependency missing.** #629's test covered "no theme: `get` says so" but not
  the buttons still tappable there; `set level off` changed the phone-wide
  profile and no button could change it back. *Check:* run every `set` verb of
  the backend in the "unavailable" state, and read the QML for what stays
  enabled after a failed first read. Extends L-617. *From:* #629, round 50.
- **L-706. A timing fix for a test is verified by forcing the order of events,
  not by loading the machine.** #638's "every loaded run failed" couldn't be
  reproduced: main passed 4 of 4 pinned to one core under 12 busy loops. A
  scratch wrapper that delayed the fake's `push()` 30 ms and stalled the
  client before each property read made main fail with exactly the two
  reported failures, and the head pass. *Check:* read the diagnosis for its
  order of events, inject it by patching the test helpers from a file outside
  the worktree, and compare the base's failures with the reported ones by
  name and message. Extends L-346 and L-418. *From:* #638, round 50.
- **L-677. Consent read from standard input is positional, and a caller that
  pipes answers gives it by accident.** #639's typed yes is the first line
  `tools/install-phone` reads; the `installer-m1a-tools` branch pipes its
  answers and silences the prompts, so the user name would answer the slot
  check. *Check:* for a new confirmation in a tool another tool drives, `git
  grep` the open branches for callers that pipe its stdin, and ask for an
  explicit option for callers, with `yes` read only from a terminal. Extends
  L-44. *From:* #639, round 49, 2026-11-10.
- **L-676. `debugfs mkdir` on an existing directory corrupts the image: it
  allocates the inode before it fails to link it.** `tools/install-phone` ran
  it unconditionally with output discarded and `|| true`; only its own
  `e2fsck` caught it, as a refusal on any root that already had the directory.
  *Check:* for every `debugfs -w` script (`git grep -n 'debugfs -w'`), run it
  on a fixture that already holds each path it creates, then `e2fsck -fn`.
  Extends L-635. *From:* #609 with issue #608, round 49, 2026-11-10.
- **L-675. A timeout change in a request/response transport is judged by what
  happens to an answer that did arrive, and per timer by whose clock it
  follows.** #595 discarded a matching reply once the deadline had passed, so
  the SMS path reported a sent message as "delivery uncertain"; and a request
  deadline on `CLOCK_BOOTTIME` fails every request in flight across a sleep,
  though its reply arrives on resume. *Check:* `git grep -n TimeoutError` the
  callers and write down what the user is told for each non-idempotent request
  (send, dial, hang up); mark every `monotonic()` deadline "our wait" or "the
  network's time". *From:* #595 with #556, round 49, 2026-11-10.
- **L-674. A stand-in server in a test applies its rules to the request, not
  to its own storage path.** #593's fake `curl` matched nginx's dot-name deny
  against `$S/<url path>`, so the test failed for anyone whose `$TMPDIR` had a
  dot component and never on CI. *Check:* run a test whose stand-in filters by
  name once with `TMPDIR` under a dot directory and once under one with a
  space. Extends L-454. *From:* #593 with #586, round 49, 2026-11-10.
- **L-673. A new shell surface is checked for how it draws icons and for new
  theme keys, not only for colours and spacing.** #612 used Commons tokens
  throughout but drew its marks as inline SVG data URIs, where the launcher's
  pill a tap away uses the icon font. *Check:* `grep -n 'data:image\|\.svg'
  <new qml>` against the neighbouring component's glyphs, and grep for
  `styleAlpha(`, `styleNum(` or `styleString(` with a key no Omarchy theme
  defines. *From:* #612, round 49, 2026-11-10.
- **L-672. Moving a row's removal behind a reply is probed with two rows in
  flight.** In #533 each acknowledgment replaced the JS-array model, the
  Repeater rebuilt every delegate, and a second swiped row still waiting came
  back at full height until its own reply; the PR's tests covered one row.
  *Check:* in the PR's Qt fixture swipe two rows, answer `ok` for the first,
  and read the second's `fold` and whether it is the same delegate; ask where
  a new delegate gets per-delegate state from. Extends L-616. *From:* #533,
  round 49, 2026-11-10.
- **L-671. A fix that makes a long-failing restore succeed applies whatever
  was saved before it started failing.** systemd-backlight saves in
  `ExecStop`, which never runs for a unit that failed at boot, so #600's first
  boot restores the level from the last shutdown at which the unit was active.
  *Check:* find when the state was last saved and what saves it from now on
  (here also a zero backlight behind the lock), and ask for one boot that
  shows it. Extends L-623. *From:* #600, round 49, 2026-11-10.
- **L-670. A blocking `systemctl start` inside a hang-marker phase inherits
  the started unit's timeout.** #600 starts `systemd-backlight@` (90 s) from
  the `display` phase of a start with `TimeoutStartSec=120`; a hung restore
  would leave the marker and turn the next boot's graphics and Wi-Fi off.
  *Check:* for every `systemctl start|restart` a boot script adds, read the
  target's `TimeoutStartSec` against the caller's and the marker phase it runs
  in; ask for `timeout N` or `--no-block`, and for cosmetic steps after the
  last guarded one. Extends L-170, L-174 and L-613. *From:* #600, round 49,
  2026-11-10.
- **L-303. Powering an NFC adapter off through neard needs the poll loop
  stopped first.** neard 0.20's `Powered=false` is a bare `NFC_CMD_DEV_DOWN`,
  which `nfc_dev_down()` refuses with EBUSY while the device polls, so a hook
  that only powers off leaves the radio polling through the sleep. *Check:*
  any "power the adapter off" in a gotcha, hook or script has a StopPollLoop
  (or rfkill) step before it and a read-back of `Powered` after. Extends L-235
  and L-290. *From:* #137 with issue #132, round 28.
- **L-302. A retry-until-success we suggest is checked against a failure that
  never clears.** Round 26 bounded #99's `StartPollLoop` retry because the
  9a's EBUSY persisted, but the power-on retry it suggested had no bound: a
  permanent refusal logs every 2 s while the screen is lit. *Check:* run the
  stub bus with a failure that never clears and count the log lines per
  minute, then bound the retry or accept it explicitly in the draft. Extends
  L-289 and L-229. *From:* #99, round 27.
- **L-289. A "retried" claim in a GLib timeout path is checked once per
  caller.** A helper's `True` return only reschedules when the helper is
  itself the registered callback: #99's `start_polling` returns True to retry,
  but `follow_screen` calls it once at screen-on and discards the result, so a
  failed power-on there stays off until the next dark/lit cycle. *Check:* list
  every caller of a function that returns "try again", confirm the value
  reaches GLib or the next tick calls it again, and run a stub bus whose call
  fails once. Extends L-14 and L-235. *From:* #99, round 26.
- **L-264. A udev `SYSTEMD_WANTS` hook fires only when the device first
  becomes active.** We nearly flagged #113's rule as restarting feedbackd on
  every `udevadm trigger` change event; systemd.device(5) says change events
  don't act on `Wants=`. *Check:* read systemd.device(5) before flagging
  repeat starts; a replay with `--action=add` is the test. *From:* #113, round
  25 (a near miss).
- **L-235. An edge-triggered "stop when X" is undone by every other actor
  that restarts the thing.** #99 stops neard polling once on the lit-to-dark
  transition; the sleep hook, its own unblock path and a neard restart all
  start polling again while dark. *Check:* list every writer of the state
  (AGENTS gotchas, device packages) and prefer a level check. *From:* #99,
  round 24.
- **L-14. `$(ls … | tail)` at the top level under `set -euo pipefail`
  exits the script** silently (status 2) when nothing matches, before any
  argument is parsed. *Check:* glob-and-pick at the top level of any script
  run by others; compute it inside the branch that needs it, tolerating no
  match. *From:* #22 (it broke `phone-provision` for every cheetah user).
- **L-15. `grep -q` under `pipefail` SIGPIPEs the writer** (AGENTS.md
  Userspace); use `grep -c … >/dev/null`. *From:* #22.
- **L-16. `read` with `IFS=$'\t'` collapses empty fields** (tab is IFS
  whitespace), shifting the next field into the empty one. Use a
  non-whitespace separator (`$'\x1f'`). *From:* our own `tools/phone-smoke`.
- **L-17. Unchecked files written to the boot path.** A splash or blob copied
  into the initramfs and written to `/dev/fb0` needs a build-time check
  (`gzip -t`, exact size W×H×4) and a logged sha256, so the image can be
  reproduced. *From:* #21.
- **L-33. A test that greps a systemd config's keys also greps its section
  header.** Keys under a misspelt section (`[Logind]`) are ignored with only a
  log warning, and a keys-only test still passes. *Check:* rename the
  section and run the package's `test/all`. *From:* #29.
- **L-63. logind ranks drop-ins by file name, not by directory.** Every
  `logind.conf.d/*.conf` in `/usr/lib`, `/run` and `/etc` is sorted by name
  and the last one wins; `/etc` only replaces a file of the same name. So a
  local `/etc` file "outranks" a package's only if its name sorts later.
  *Check:* `systemd-analyze cat-config systemd/logind.conf`, or compare the
  names. *From:* #33.
- **L-174. A service that restarts a unit it `Requires=` restarts itself.**
  systemd propagates a stop or restart of a required unit to its dependents
  (systemd.unit(5), `Requires=`), so `systemctl restart neard` from
  `omamobile-nfc-open`, which requires neard, re-ran the caller, which
  restarted neard again, until neard hit its start limit. *Check:* for any
  `systemctl restart|stop X` in a script a unit runs, read that unit's
  `Requires=`, `BindsTo=` and `PartOf=`; two user units under `systemd-run
  --user -p Requires=…` reproduce it in a minute. *From:* #78, round 20.
- **L-175. A "keep the job alive after the daemon exits" wrapper in a
  `set -e` script is tested with a non-zero exit.** #70's `spawn_optional`
  runs `daemon | sed` inside `{ …; exec sleep infinity; } &`; the group
  inherits errexit, so any exit but 0 kills the job before the sleep, and
  the supervisor powers the modem off, the very event the commit prevents.
  *Check:* run the block with `sh -c 'exit 3'` and `kill -TERM $$` in place
  of the daemon; only `|| true` or `set +e` in the group survives. Extends
  L-14. *From:* #70, round 20.
- **L-417. A tests-only switch added to shipped safety code is proved inert by comparing syntax trees, not by reading the diff.** On #327, main and head were parsed with `ast`, the hook removed and `if hook: ... else: X` replaced by `X`, and `ast.dump` compared (identical). *Check:* do that for any `os.environ.get(...)` switch in a watchdog or limit path; list every unit, `EnvironmentFile=` and drop-in that could set it, and what happens when the switch's command fails. *From:* #327, round 38, 2026-11-02.
- **L-418. A flaky test moved onto a synthetic clock is checked for each case's end state, not its exit status.** "Doesn't mute" cases pass whenever the event never lands. *Check:* run the suite with its keep switch (`KEEP=1` on #327) and read the end state of every case whose timing changed. Extends L-346. *From:* #327, round 38, 2026-11-02.
- **L-419. A "checked again afterwards" step in a safety tool is mutation-tested.** Removing `nv-backup`'s post-copy re-probe left its test green. *Check:* delete each safety re-check in turn and run the test; one no test notices needs a fixture that changes state between the two checks. Extends L-102. *From:* #326, round 38, 2026-11-02.
- **L-453. A parallel test runner writes each result atomically and accounts
  for every job it started.** #410's `echo $? > NAME.rc` could be read empty
  by a concurrent reporter, which printed `not ok` and deleted the real
  result, and a suite whose subshell died before writing was never counted,
  so the run passed. *Check:* results are written temp-then-rename, and the
  final tally compares the results with the list of jobs started. *From:*
  #410, round 39, 2026-11-03.
- **L-454. A test that can't fail, or that reads the host, is not a test.**
  Three in one round: device-raven's new line grepped a variable that
  doesn't exist in a file that doesn't exist, behind `2>/dev/null` (#401); a
  "not installed" case put `/usr/bin` after its fakes, so `shutil.which`
  found the phone's real binary (#408); and a proposed layout check would
  have read `/usr/share/X11/xkb` on the build machine (#413). *Check:* the
  path and the pattern exist at the head (mutate once); a probe's `PATH`
  holds only fakes; a generated-file check reads an input pinned in the
  repository with its version. Extends L-234 and L-410. *From:* #401, #408,
  issue #413, round 39, 2026-11-03.
  Again in round 44: a "some `c N:*` line exists" pattern on #493 matched
  unrelated wildcard lines (`c 5:*`, `c 136:*`); found by deleting the line
  under test.
  Again in round 45: #501's "reaches the MANIFEST" case read what its stub
  `docker` printed, so it proved the plumbing and not the producer, and #505's
  `tests/dipper-probe` checked that its needles are in `initramfs-inside.sh`,
  always true, instead of feeding the real `initramfs/init` through the patch
  step.
- **L-467. `RestartPreventExitStatus=` covers the main process only; a
  pre-start refusal that must not be retried uses `ExecCondition=`.** #371's
  `ExecStartPre=` check exited 3 with `RestartPreventExitStatus=3`; on
  systemd 262 that pair restarted five times, as without the line, while
  `ExecCondition=` with exit 3 skipped the start with no restart. *Check:*
  for any "a refusal isn't retried" claim, find which process exits, and
  reproduce it with `systemd-run --user -p Restart=on-failure …` in a
  minute. Extends L-174 and L-454. *From:* #371, round 40, 2026-11-04.
- **L-468. A cleanup added to one exit function covers only the exits that
  call it.** #424 released the modem's sleep block in `refuse()`, but a
  failing first `modprobe` exits through `set -e` before any driver loads
  and keeps the block, the #390 symptom. *Check:* list every exit of the
  script before the guarded step (refusals, `set -e` failures, `exit`) and
  ask which ones the cleanup misses. Extends L-14. *From:* #424, round 40,
  2026-11-04.
- **L-469. A udev rule keyed on a kernel name pattern is checked against
  every device the subsystem creates under that name.**
  `KERNEL=="hci[0-9]*"` also matched the per-connection `hci0:N` devices, so
  each Bluetooth connection started the address unit and left a failed one;
  `DRIVERS==` didn't help. *Check:* read the subsystem's `struct
  device_type` names and require `ENV{DEVTYPE}==` where there is more than
  one. *From:* #423, round 40, 2026-11-04.
- **L-470. A Quickshell `FileView` fix for a file that doesn't exist yet
  re-arms the watch, not just the first read; and a poll "until the file
  appears" is checked on phones where it never does.**
  `updateWatchedFiles()` runs only when `path` or `watchChanges` changes and
  a failed `addPath()` isn't retried, so #425's timer would load the state
  once and then follow nothing, while polling forever on phones without the
  fingerprint stack. *Check:* read `src/io/fileview.cpp` at the phone's
  Quickshell version and walk the scenario (no directory, file created, then
  a change), and list the devices where the awaited file is never created.
  Extends L-289 and L-302. *From:* #425, round 41, 2026-11-05.
- **L-495. A port of a hang-safe start script carries every guard of the
  original, not only the marker.** #453 kept cheetah's hang marker but dropped
  the "AoC already online" exit and the `/run` firmware marker, so a retry
  could load firmware into a running AoC. *Check:* list every early `exit` in
  the script the port follows and confirm each exists or is answered. Extends
  L-170 and L-232. *From:* #453, round 42, 2026-11-07.
- **L-496. A script that writes a module parameter at boot loads the module
  first or orders itself after it.** #438's unit wrote
  `/sys/module/gs_dsim_cmd/parameters/allow_tx` with nothing ordering it after
  udev's autoload. *Check:* for each `/sys/module/<m>/parameters/` write, find
  the `modprobe <m>` or `After=` before it, and what the failure path leaves.
  *From:* #438, round 42, 2026-11-07.
- **L-497. A helper added beside a bundled tool goes into the bundle with
  it.** #467 added `tools/phone-ssh-proxy` next to `phone-ssh`, which
  `tools/make-bundle` ships; the bundle's copy would lose the feature or fail.
  *Check:* for each new file a bundled tool calls, `grep -n provision_tools
  tools/make-bundle` and `tests/make-bundle-keys`. Extends L-421. *From:*
  #467, round 42, 2026-11-07.
- **L-498. An extracted Omarchy package is read through its own `usr/bin`.**
  `usr/share/omarchy/bin/*` are absolute links to `/usr/bin`, and the review
  laptop runs Omarchy, so a grep or patch on the extracted `bin/` reads, or
  writes, the host's files; one grep this round answered from the laptop.
  *Check:* replace each absolute link with the package's copy first (`find
  -type l -lname '/*'` empty). Extends L-454. *From:* #471, round 42,
  2026-11-07.
- **L-499. A stand-in named after an upstream stage replaces it in every
  release that calls that name, the pinned one included.** #471's
  `omarchy-update-system-pkgs` looked 4.5-only, but 4.0.6's `omarchy-update`
  calls it too. *Check:* grep each Omarchy version's `usr/bin` for callers,
  and compare the stand-in's environment with the original's (`LC_ALL=C`).
  Extends L-233. *From:* #471, round 42, 2026-11-07.
- **L-500. A base-system requirement a new upstream release adds is checked
  everywhere the release enforces it.** #447 reported one migration, but the
  same `/run 755` check guards 4.5's update inhibitor and an AbortOnFail hook
  on `omarchy-settings` (the downgrade path). *Check:* grep the release's
  packages, `libalpm/hooks` included, for the helper's callers before calling
  a workaround migration-only. *From:* issue #447 with #437, round 42,
  2026-11-07.
- **L-501. A file capability set during a rootless image build is checked by
  `CapEff` on the phone, not `getcap`.** #429's contributor showed a
  capability written under `unshare -Ur` is a namespaced v3 xattr: `getcap`
  lists it, the process gets `CapEff 0`. *Check:* a phone-side re-apply, or
  `CapEff` of the running process on an image-installed phone. Corrects
  L-459's check. *From:* #429, round 42, 2026-11-07.
- **L-502. A "keep it until confirmed" change in a bridge is checked for what
  clears an object whose confirmation can't arrive.** #461 keeps a call Active
  when sitd drops it mid-release, while sitd only drops ended calls. *Check:*
  list every way the daemon removes the object and the state the bridge is
  left in. Extends L-302. *From:* #461, round 42, 2026-11-07.
- **L-535. A patch that turns "a touch wakes" into "a touch is swallowed while
  dark" changes what a stale dark flag costs.** Before #420's 0029, a lock
  whose `displayDark` outlived the dark screen still woke on a touch; after
  it, every touch is ignored until the lock's own wake clears the flag.
  *Check:* list every path that can light the panel (power key, idle, call
  watcher, Hyprland's own DPMS wakes, package version skew) and confirm each
  clears the flag (here through `omarchy-shell lock wake`); where a skew can
  light it without clearing it, ask for a `conflicts=` between the packages.
  Extends L-161 and L-235. *From:* #420, round 44, 2026-11-08.
- **L-536. A guard that reads a display-synced sensor is checked for what the
  sensor does with the display off.** omamobile-sensors' TMD3719 converts only
  with the display state the HAL sends, the proxy sends "off" when the DSI
  connector is off, and it keeps `ProximityNear` across releases, so #420's
  pocket guard, claimed only while dark, may never read or may read stale.
  *Check:* grep the backend for `DISPLAY_SYNCED` or its equivalent and the
  proxy's `_release` before accepting a sensor-based guard, and ask for a
  covered and an uncovered run with the panel off. Extends C-1. *From:* #420,
  round 44, 2026-11-08.
- **L-537. "Reads the state before it acts" is checked for the time between
  the read and the act.** #463's `unlock` reads the lock state, then wakes,
  presses Return and waits 2 s before typing the PIN; an unlock in that window
  (fingerprint, the person holding the phone) sends the PIN and a Return to
  the focused app. *Check:* for any tool that injects input, list the sleeps
  and actions between its guard and the sensitive write, and ask for the guard
  again right before the write. Extends L-161. *From:* #463, round 44,
  2026-11-08.
- **L-538. A stricter check on a vendor tool's stderr is tried on a real input
  with the system tool alone.** #491 started failing a copy on any debugfs
  message outside a small allow-list, in a tool every install runs from the
  release bundle, and its tests used stand-ins and a synthetic image. *Check:*
  run only the host's tool (not the PR's) with the PR's exact command, as the
  same user, on a scratch copy of a real image; count the lines the filter
  would reject, then delete the copy. *From:* #491, round 44 (0 rejected on
  the 7 Pro's 260705 vendor image); 2026-11-08.
- **L-539. A `--dry-run` that still writes local state is walked through every
  runbook that pairs it with the real command.** `tools/release` runs
  `repo-publish --dry-run stable` and then `stable`. On main the dry run
  staged the new index, so the real promotion pruned stable's previous set at
  every release (local stable: 45 files for 45 index entries); #492's record
  fixes it, though the PR described only no-op dailies. *Check:* `git grep -n
  -- '--dry-run' tools/release docs/` for each tool a PR changes, and run the
  dry run and the real run back to back in the PR's test fixture. Extends
  L-392. *From:* #492, round 44, 2026-11-08.
- **L-540. LXC 7's cgroup2 device rules are one-polarity lists, so "allow
  before deny" is not a rule, and a global `a` after our include is the
  hazard.** In the default allowlist mode, `bpf_device_add()` drops every
  specific deny rule; a global `allow = a` or `deny = a` sets the mode and
  clears every earlier rule. Our request on issue #465 and #493's comment both
  assumed first-match order. *Check:* for any LXC device rule change, read
  `src/lxc/cgroups/cgroup2_devices.c` at the packaged LXC tag, and ask what
  mode the list is in, whether any `b` rule allows, and what in the generated
  config is processed after our include. Extends L-31 and C-1. *From:* #493
  with issue #465, round 44, 2026-11-08.
- **L-541. A dynamic char major hard-coded in a shipped package couples it to
  the kernel's built-in driver set.** Binder's 507 on cheetah comes from the
  extended dynamic range, so a kernel update that adds a built-in driver with
  a dynamic major moves it, and #493's fail-closed check then takes Waydroid
  down until the package changes. *Check:* any `major:minor` in package config
  at or above 234 and outside `Documentation/admin-guide/devices.txt`'s fixed
  list gets a path-based rule, a value generated at start, or an update plan.
  *From:* #493, round 44, 2026-11-08.
- **L-571. An allow line added because "Waydroid binds it" is checked for what
  the node lets the container do to the host.** #493's `/dev/uhid` creates HID
  devices that the host compositor reads, which is a way to inject input into
  the host session; Android booted without it and logged nothing about it.
  *Check:* for each new `lxc.cgroup2.devices.allow`, name the host object that
  opening the node creates or reaches (uhid and uinput are host input, `kvm`
  host CPU state, `mem` and `port` host memory and I/O), and ask for a failing
  Android feature without it before it goes in. Extends L-540 and L-454.
  *From:* #493, round 45, 2026-11-08.
- **L-572. A lock added to an input handler is checked for what a holder that
  hangs does to every later press.** #508's `flock` without `-w` made a stuck
  short-press action freeze the power key for the session, where main would
  have let the next press through. *Check:* for any new `flock`, mutex or
  queue in a key, touch or wake path, run the PR's harness with the slowest
  helper made to sleep past the press interval, measure when the next press
  acts on main and on the head, and ask for a bound. Extends L-161 (fail
  towards the user being able to act). *From:* #508, round 45, 2026-11-08.
- **L-573. Deferring a surface's "on open" reads is checked against what the
  surface shows first and what refreshes it while it's closed.** #518 queued
  the shade's notification read ninth, behind the reveal, and the shade's
  periodic read runs only while it's open (`running: root.opened`, first tick
  at 3 s), so every open showed the previous open's list for about 0.65 s.
  *Check:* for each read moved off the open path, `grep -n` its function for
  the timers and watchers that call it, note their `running:` condition, and
  compute when the first fresh value appears after opening; ask that what the
  first screen shows goes first. Extends L-235. *From:* #518, round 45,
  2026-11-08.
- **L-574. (Provisional, not yet checked on a phone.) A network-sharing
  feature is checked against the firewall the image turns on.** #525 makes the
  hotspot's dnsmasq start, but firstboot's ufw denies incoming and forwarded
  traffic, so a client's DHCP and DNS may never reach it, and the PR's test
  (the server side came up) can't show that. *Check:* `git grep -n 'ufw '
  packages/omamobile-firstboot` for the defaults, and ask for one client test
  (an address, then a ping out) before a "hotspot works" claim. Confirm or
  drop once a client test has run. *From:* #525, round 45, 2026-11-08.
