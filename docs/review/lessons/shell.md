<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Shell and scripts (part 1 of 2)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-765. `date +%s%3N` is not a millisecond clock everywhere: take milliseconds from `%s%N`.**
  uutils' `date` (0.10.0, on the build machine) drops the nanoseconds' leading
  zeros before it takes three digits, so 3 ms into a second reads as 365 and one
  reading in ten is wrong by up to 900 ms. `omamobile-keys`' one-second wait
  ended at 605 and 791 ms there and failed `test/keys.sh` about one run in six,
  which stopped a publish; GNU `date` on the laptop and in CI never showed it.
  *Check:* `git grep -n '%[0-9]N'`; a timing test that fails on one machine
  only is run there in a loop with the clock printed, before the code is blamed.
  See L-710. *From:* #640's test on ms01, round 52, 2026-11-11.
- **L-764. A new tool that reaches the phone goes through `tools/phone-ssh`
  and passes on why a transfer failed.** #666's `tools/ncm-transfer` called
  `ssh` itself in batch mode, so the key, host-key and interface settings
  from `OMAMOBILE_SSH_*` didn't apply and the contributor's own run needed an
  uncommitted wrapper; against a fake `ssh` that printed "Host key
  verification failed." it showed only "FAIL: SSH, size or digest check".
  *Check:* `grep -n "'ssh'\|\bssh " <new tool>`, read the body for "wrapper"
  and "locally", and run the tool against a stand-in that fails with a
  message. Extends L-41, L-89 and L-276. *From:* #666, round 52, 2026-11-11.
- **L-763. When we ask for "refuse first", every line above the first refusal
  is read for a write, the log's truncation included.** #659 put its refusals
  before the trap as asked, but below `: > $L`, and the log is one fixed file,
  so a start refused because the modem is up wipes the previous series'
  record (that day the 313-sleep one). *Check:* `sed -n '1,/<first
  refusal>/p' <script> | grep -n '>\|rm \|mv \|echo .* >'`, and ask for the
  truncation below the refusals or the old log kept aside. Extends L-468.
  *From:* #659, round 52, 2026-11-11.
- **L-762. A check moved ahead of a tool's "nothing written yet" point brings
  its scratch files and cleanup trap with it.** #648 moved `install-phone`'s
  ramdisk read before the phone, and with it the work directory's setup and
  `trap cleanup EXIT`, so a files-only `--verify-only` and every early refusal
  emptied a directory another install was using. *Check:* list the paths the
  moved step writes and the traps set before it, plant files at each shared
  path, run every exit that now passes the step and list the directory
  afterwards; ask for a private `mktemp -d` directory. Extends L-468 and
  L-539. *From:* #648, rounds 51 and 52, 2026-11-11.
- **L-761. An optional key in an associative array is expanded with `:-` under
  `set -u`, and a step runner that tolerates failures gets a test that reads
  the step's result, not the run's exit.** #662's
  `${C[FULL_NAME]//[[:space:]]/}` died with "unbound variable" in firstboot's
  optional user-setup step whenever the installer wrote no name; the test's
  no-name run passed because the step is optional. *Check:* `grep -n
  '\${C\[[A-Z_]*\][^:}]' <script>` for keys the writer omits
  (`tools/install-phone` writes `FULL_NAME`, `EMAIL` and `WIFI_*` only when
  given), and have the test grep the output for `FAILED` and `with warnings`.
  Extends L-14, L-454 and L-468. *From:* #662 (commit review), round 52,
  2026-11-11.
- **L-740. A string-replacement patch on a shared script is read as the resulting text, also when it implements our own optional suggestion.** #505's anchor covered half of a `cmd && say …` line, so the new block inherited the old line's tail (`fi 2>/dev/null && say "ssh: …"`) and the claimed fix didn't happen; it came from a "suggestion, not a condition" in our round-50 comment. *Check:* apply the patch step to today's shared file in scratch and read the lines around each anchor. Extends L-244 and L-183. *From:* #505, round 51, 2026-11-11.
- **L-739. A change that narrows a container's mounts is checked against every path the container command and its script open.** #505 replaced the repository mount with four file mounts and kept `sh /src/tools/…/initramfs-inside.sh` as the command; `bash -n` and CI stayed green. *Check:* list the `-v` targets, then grep the command line and the inside script for `/src/` and `/input/` paths and match them one by one. Extends L-497 and L-454. *From:* #505, round 51, 2026-11-11.
- **L-738. A feature that refuses on a cached, asynchronous flag is walked through the feature's own path that sets the flag.** #612 refuses to open Search while `sessionLocked` is true; the flag is re-read only on keyboard changes, the lock path ends with the keyboard down, and Search is what raises the keyboard, so after an unlock the dock tap is dead. *Check:* for every `if (<cached flag>) return` a PR adds, list what refreshes the flag, then walk from the state the feature leaves behind to its next use; a test that sets the flag by hand proves nothing about that. Extends L-622. *From:* #612, round 51, 2026-11-11.
- **L-737. A test stub of a third-party QML type is checked for signals the real type declares but never emits.** #658's first restart waited for `ScreencopyView.stopped`; Quickshell 0.3.2 declares it in `view.hpp` and nothing emits it, while the stub did, so the test passed and the feature never ran on a phone. *Check:* for every signal or property of a stubbed type the code reacts to, grep the upstream source at the phone's version for `emit this-><name>` or the setter, and make the stub fail the way the real type does. Extends L-454 and L-618. *From:* #658, round 51, 2026-11-11.
- **L-736. A window rule that floats a fixed-size dialog is tested with the window's `at` and `size` and a screenshot, on the narrowest phone.** #602's rule passed its Lua test ("floating, centred, not maximized"), but on the 405 px wide 9a the 634 and 729 px dialogs sat at x = -229 and -324 with controls off screen, and a floating window can't be dragged back. *Check:* for any rule that takes a window out of maximize, ask for `hyprctl -j clients` and a screenshot of the widest dialog; a negative `at.x`, or `at.x + size.w` past the screen, hides controls. *From:* #602, round 51, 2026-11-11.
- **L-735. A secret taken from the environment is removed from the environment the tool hands to its children.** #652 passed its sudo password variable on to a terminal it keeps open for an hour. *Check:* for any `*_PW` or `*_TOKEN` variable, find every `env=` and `Popen`; for `sudo -S`, ask what reads the piped password when sudo already has a ticket and asks nothing. *From:* #652, round 51, 2026-11-11.
- **L-734. A tool whose cleanup lives in `try/finally` is checked for the signals that skip it, SIGHUP first.** #652 handled Ctrl-C and SIGTERM, but a dropped SSH session, the likely failure on a phone whose only link is USB, sends SIGHUP, and Python then exits without `finally`: do-not-disturb would stay on with nothing to notice it. *Check:* `grep -n 'signal\.\|trap ' <tool>`, list each state the tool changes, and ask for a leftover check at start. Extends L-468 and L-613. *From:* #652, round 51, 2026-11-11.
- **L-733. A script that changes a safety setting sets its restore trap first, and every early `exit` is read against what has already been changed.** #659 turned the runtime watchdog off and `panic_on_rcu_stall` on 20 lines above a refusal and 35 lines above `trap restore EXIT`, and its restore put back one of the five switches. *Check:* list each write to `/proc/sys`, `/sys/power`, tracefs or systemd's manager properties with its line, then the line of the trap and of every `exit` between them, and tick each write off in the restore function. Extends L-613 and L-468. *From:* #659, round 51, 2026-11-11.
- **L-716. A check whose input can fail to be read is walked for what the
  failed read decides.** #596's `cpio -it 2>/dev/null | grep -c … || true`
  read a broken archive as "no keys" (key appended, then flashed) and a late
  failure as "keys present"; `extract-vendor-firmware` compares
  `ro.product.vendor.device` only `if` `build.prop` could be read, so a failed
  read stages another phone's firmware. *Check:* take the producer's status
  alone (`out=$(cmd) || die`), test the text from a here-string, try a
  truncated input, and grep `if get_file` and `2>/dev/null` above each
  compare. Extends L-161 and L-635. *From:* #623 (after #596) and #625, round
  50.
- **L-715. Folding independent once-only steps into one helper makes them all
  wait for its precondition.** #581 moved `--no-first-run`, the user agent and
  the input-method flags, which need no geometry, into a helper that returns
  early when geometry is unknown. *Check:* list each step's own inputs and
  confirm an early return for one input skips only the steps that need it.
  Extends L-468. *From:* #581, round 50.
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
