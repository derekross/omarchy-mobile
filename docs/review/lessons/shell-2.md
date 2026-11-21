<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Shell and scripts (part 2 of 3)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-892. A program that becomes required in the installer is added
  everywhere an owner is told what the install needs, with its package per
  distribution.** #877 made `img2simg` a hard requirement of
  `tools/install-phone`; the guided install's preflight table, the installer's
  own hint (Arch's package name only), INSTALL.md's program list and the
  bundle's README still described the old set. *Check:* for a new entry in a
  tool's `command -v` loop, `git grep -n '<a neighbouring program>'
  tools/install-guided tools/make-bundle docs/INSTALL*.md` and compare each
  list; read the refusal's hint as a Debian or Ubuntu owner would. Extends
  L-497 and L-589. *From:* #877, round 61, 2026-11-18.
- **L-872. A Hyprland screen shader is reviewed with three facts from the
  packaged version's source: an empty path turns it off, captures skip it, and
  a bad path raises the on-screen error overlay.** For #880,
  `applyScreenShader()` returns on an empty path and reports a non-regular
  file to the overlay, and `ScreenshareFrame.cpp` sets `blockScreenShader` for
  every capture, so screenshots, recordings and the VNC mirror can't show the
  look. *Check:* fetch `src/render/OpenGL.cpp` and
  `src/managers/screenshare/ScreenshareFrame.cpp` at the packaged tag, ask for
  a photo or the owner's statement rather than a screenshot, and compute the
  curve at 16, 128 and 255 for the review. Extends L-484 and L-724. *From:*
  #880, round 61, 2026-11-18.
- **L-829. A patch to an Omarchy launcher is run against fakes with a
  look-alike host.** #610's `case` on `https://web.whatsapp.com |
  https://web.whatsapp.com/*` was read as safe; running the patched launcher
  under `env -i` with fake `uwsm-app`, `setsid` and browser showed the exact
  argv, and that `web.whatsapp.com.evil.example` falls through. *Check:*
  extract the launcher from the signed package, apply the patch, and run it
  with a `PATH` of fakes for the matched URL, a prefix look-alike and an
  unrelated one. Extends L-692 and L-548. *From:* #610, round 60, 2026-11-17.
- **L-819. A backend's failure exit is checked against how the runner reads
  results.** #866's `lock.sh` "fails loudly" with exit 3 after it has printed
  its success JSON, and the Settings runner reports an error only when stdout
  isn't JSON. *Check:* for each non-zero exit a backend adds, read the
  caller's result handling (`actionrunner.cpp`: `obj.isEmpty() || st !=
  NormalExit`) and run the failing path with a stand-in to see what the page
  gets; an error must be the JSON, printed last and alone. Extends L-41 and
  L-761. *From:* #866, round 60, 2026-11-17.
- **L-806. A lookup helper that "prints the device or nothing" returns 1 when
  it finds nothing, and `x=$(helper)` on its own line under `set -e` ends the
  script.** #874 added `fpc=$(fpc_device)` to a path every phone runs; the
  helper's `for` loop ended on a failed `[[ -f ... ]]`, so the runner died on
  every phone but one, after the once-per-boot marker was set. Main's
  `touch_event` and `rpmb_sg` have the same shape and work only because their
  device is always there. *Check:* for each new `v=$(fn)` (not `local
  v=$(fn)`, not inside `if`) in a `set -e` script, read `fn`'s last command
  with the device absent, and run the calling function from base and head with
  the reference phone's values. Extends L-14, L-468 and L-280. *From:* #874,
  round 60, 2026-11-17.
- **L-805. `cmd /proc/self/...` in a script reads the child's file, not the
  script's.** Both vendor runners recorded `awk ... /proc/self/status`, so
  `ns.pid` named a dead process since they were written, and every reader
  failed closed or, after PID reuse, could enter another process's namespaces.
  *Check:* `git grep -n '/proc/self' -- packages tools bin` for an external
  command (awk, cat, sed, grep, readlink) reading it where the shell's
  identity is meant; a builtin `read ... < /proc/self/...` or `$BASHPID` is
  the shell. Then list the file's readers (L-623). *From:* #865 and #864 with
  issue #862, round 60, 2026-11-17.
- **L-804. A guard that returns 0 when it can't find its target hides a
  feature that never ran.** `modem_nv_capture`'s `kill -0 "$pid" || return 0`
  was written for "the profile isn't running" and also swallowed "the PID file
  is wrong" for two weeks. *Check:* for each silent early return in a stop or
  timer path, ask which log line tells "nothing to do" from "couldn't look",
  and whether any run on a phone ever showed the positive line. Extends L-434
  and L-440. *From:* #864, round 60, 2026-11-17.
- **L-799. A "release and retry" for an answer the network may always give
  needs a bound.** #837 releases an IPv6-only bearer and retries on a backoff
  that never ends; on an IPv6-only network that is a setup and a release every
  30 minutes for the whole boot, each holding the daemon's loop. *Check:* for
  each new retry, name the condition under which the retried answer never
  changes and count the calls per hour then. Extends L-302 and L-502. *From:*
  #837, round 60, 2026-11-17.
- **L-798. A wait removed for one case is checked against the reason the wait
  was added, in that case.** #837 dropped SleepHold's 10 s grace when Wi-Fi is
  off; the class's docstring says the grace exists because traffic at a wake
  brings answers that end the next sleeps early, which is as true with Wi-Fi
  off. *Check:* read the comment or commit that introduced the delay (`git log
  -S'<constant>'`), ask whether its reason depends on the condition the PR
  adds, and ask for the cost measured as the original was (wakes and refused
  sleeps per idle hour). Extends L-623 and L-235. *From:* #837, round 60,
  2026-11-17.
- **L-794. A rule written twice, in shell and in Python, is fed one table and
  the answers compared.** #850's `modem_slot_suffix` and `slot_suffix()` agree
  on the PR's cases and differ on a CRLF line, a CR in bootconfig and
  non-UTF-8 bytes: `Path.read_text()` translates newlines and `splitlines()`
  splits on more than `\n`, where `grep`, `sed` and `[[ =~ ]]` do not.
  *Check:* extract both functions, run each over the inputs a hand edit
  produces (`\r\n`, no final newline, `\xff`, a directory in the file's place)
  and print the rows that differ; ask for `read_bytes()` and `split('\n')`,
  and the table in the package's test. Extends L-701 and L-716. *From:* #850,
  round 60, 2026-11-17.
- **L-789. A check added in front of a list compare is probed with inputs the
  author's table lacks, and its file is read on main before the merge.** For
  #840 a NUL after the last newline, a BOM, a comment line and a FIFO were
  refused, and main's `omamobile-revoked` (0 bytes) passes, so the nightly
  publish keeps signing. *Check:* `git cat-file -s origin/main:<the checked
  file>` and one run of the new check on that exact content, then five inputs
  outside the PR's own cases. Extends L-454 and L-538. *From:* #840, round 60,
  2026-11-17.
- **L-788. When a fix removes the bad input, read the consumer for the same
  bug with hand-made input.** `build-packages --import` takes two versions of
  one package in glob order whoever put them there; #824 fixed the one
  producer. *Check:* find the consumer's loop (`add_to_repo`), feed it the bad
  input directly, and name the follow-up. Extends L-623. *From:* #824, round
  60, 2026-11-17.
- **L-786. A guard added in front of a destructive line is evaluated for each
  input its description names, with the lines above it read first.** #856's
  `realpath` check sat after a `mkdir -p` that makes two of its three terms
  always true and after the checks it claimed to precede; the named case
  (`/images`) passed it. *Check:* write down each bad input the PR names,
  trace it from where the variable is set (`grep -n '<VAR>=' <tool>`, a `:-`
  default included) through every `die` above the guard, and evaluate the
  guard's condition by hand; for `x=$(cmd)` under `set -e`, check the refusal
  message can still be reached when `cmd` fails. Extends L-454 and L-664.
  *From:* #856, round 60, 2026-11-17.
- **L-784. A host-key policy for the phone is checked against every SSH server
  that answers its address, and every event that changes a key.**
  `172.16.42.1` is the initramfs's dropbear (`-R`: a new key per boot, none in
  release images), the installed system's sshd (a new key per install) and any
  other phone on the same computer; #855's trust-on-first-use default would
  have pinned the first and refused the rest, and install-guided's first poll
  lands in the initramfs. *Check:* `git grep -n 'dropbear\|ssh_host'
  initramfs/init bin/omamobile rootfs/build-inside`, then walk a first
  install, a reinstall, an `omamobile.initramfs` boot and a second phone
  through the policy; count the callers that discard stderr, where a refusal
  reads as "no SSH". Extends L-764 and L-89. *From:* #855, round 60,
  2026-11-17.
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
