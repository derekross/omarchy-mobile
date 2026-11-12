<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Shell and scripts

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
