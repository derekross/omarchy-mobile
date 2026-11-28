<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Shell and scripts (part 2 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
- **L-982. A test that waits for a background job with `kill -0` hangs in CI's
  container.** A job reparented to the container's PID 1 is never reaped, and
  `kill -0` succeeds on a zombie; #866's race test waited forever in CI and
  passed on a desktop, where systemd reaps. *Check:* `grep -n 'kill -0'` in
  new tests; ask for a done file or `wait` on a child of the test's own shell,
  and a bound. Extends L-453 and L-674. *From:* #866 (found and fixed by its
  author), round 63, 2026-11-20. (Extended 2026-11-23: the mirror case fails
  instead of hanging. #998's `kill -0` asserting that a helper had ended after
  its parent-death signal passed where systemd reaps and failed in GitHub's
  job container, whose PID 1 (`tail`) left the helper as `Z` with parent 1.
  Where the expectation is "gone", ask for a state check (`/proc/<pid>/stat`
  field 3 not `Z`); reproduce with `docker run -d <image> sleep 600` and
  `docker exec`, against `docker run --init`. *From:* #998, round 66.)
  (Extended 2026-11-25: shipped code too. #1014's `alive()` watched a
  re-parented `wf-recorder` with `kill -0` and waited forever in the job
  container, where it was a zombie; the laptop and the phone reap, so every
  local run passed. For a shipped script, `git grep -n 'kill -0' <head> --
  'packages/*/bin' 'packages/*/libexec'` and ask whether the watched process
  is the script's own child (`wait` works) or was started by another run with
  `setsid ... &`; run the package's test both ways as above. *From:* #1014,
  round 68.)
- **L-975. A service that exits 0 with "nothing to do" behind a socket a
  daemon reconnects to at once turns "not ready yet" into a start-limit
  failure for the boot.** On the 9a, `omamobile-gnss-start` returns while
  gnssd is still inside its start delay, GeoClue reconnects five times in a
  second, and the NMEA socket stays failed until a toggle. *Check:* for each
  early `exit 0` in a socket-activated unit's start script, ask what the
  client does next and how fast, and whether the unready state ends by itself;
  a bounded wait before the hang marker beats an instant exit. Extends L-449
  and L-302. *From:* a second owner's run on #864, round 62, 2026-11-18.
- **L-965. A fetch tool's "print the path" mode is checked for whether it
  fetches.** #900's `--print` downloads 740 MB silently when the cache is
  empty, inside the `$(...)` its own docs recommend. *Check:* run each
  read-looking option of a download tool against an empty cache with a fake
  `curl`, and count the calls. Extends L-539. *From:* #900, round 62,
  2026-11-18.
- **L-962. A fallback for "not installed" is asked about "installed and
  exits".** #896's keyboard chooser returns to squeekboard when the chosen
  keyboard is removed, but `exec`s one that may crash at start, and a session
  without a keyboard can't type a lock password. *Check:* for every `exec
  "$(chosen)"`-style launcher of something the session can't do without, run
  the PR's fixture with the chosen program replaced by `exit 1` and see what
  is left running. Extends L-161 and L-712. *From:* #896, round 62,
  2026-11-18.
- **L-961. When a review finds a host-reading test in one file of a PR, every
  other test the same PR adds is grepped for the same `PATH`.** We asked #888
  to take `/usr/bin` out of `test/osk.sh`; the re-push did, and its new block
  in `test/setup-user.sh` ran the start line with
  `PATH="<fakes>:/usr/bin:/bin"`, where an installed `omamobile-osk` answers
  for "the script is gone" and can start the real keyboard inside `check()`.
  *Check:* `git diff base...head -- 'packages/*/test' | grep -n
  '^+.*PATH=.*/usr/bin'`; for each hit, name the command the case expects to
  be missing and ask whether the package under test installs it. Extends L-454
  and L-681. *From:* #896, round 62, 2026-11-18.
- **L-960. A signal handler in a Python tool is read for every lock it can
  take, `threading.Event.set()` first.** In #890, `Event.set()` takes the
  event's non-reentrant lock, the same thread's `Event.wait()` holds it
  between bytecodes, and a handler runs in the main thread, so a SIGTERM at
  the wrong bytecode deadlocks the process, which then ignores SIGTERM too.
  *Check:* `grep -n 'signal.signal' -A6 <tool>` and list each handler's calls
  that lock (`Event.set`, `Queue.put`, `logging`, `print` to a full pipe); ask
  for a plain assignment, and for a limit the kernel keeps (`signal.alarm`
  with `SIG_DFL`) where a script promises "ends after N seconds whatever
  happens". Reproduce under `timeout -s KILL`: a plain `timeout` can't end it.
  Extends L-734 and L-468. *From:* #890, round 62, 2026-11-18.
- **L-956. A sleep or wake lock that follows a sysfs value is probed with the
  read failing while the file exists.** #899's blocker tests `"$(cat online)"
  = 1`, and `online` is two I2C reads in the driver; with a directory in place
  of the file the lock was dropped within a second, the unsafe side for a lock
  that exists because a guard stops in sleep. *Check:* run the script against
  a stand-in `systemd-inhibit` that logs take and release, swap the watched
  file for a directory mid-hold, and ask that only an explicit off value
  releases. Extends L-161 and L-716. *From:* #899, round 62, 2026-11-18.
- **L-954. A follow-the-end list is probed with the PR's own handlers before
  a phone run is asked for, and the probe names what it can't show.** For #894
  a 50-line `qmltestrunner` case with the PR's `stick` handlers over a growing
  Text answered "does it follow, stop on a scroll up, and follow again" in two
  seconds at the phones' Qt version, which left the phone run the things only
  a finger and a panel show (jumps when the line above changes height,
  reopening mid-run). *Check:* copy the changed Flickable's handlers into a
  scratch test outside the worktree, drive append, drag, hide and show, then
  list for the phone run what the probe skipped. Extends L-618 and L-619.
  *From:* #894, round 62, 2026-11-18.
- **L-951. A "failed write is retried next login" fix in a once-only step is
  checked on every write in the step, with the marker's state read after
  each.** #895 took the marker back when the `cat` into `foot.ini` failed, but
  a failing `sed -i` in the other branch, or a failing `mktemp`, ends the
  script under `set -e` with the marker set and the later steps skipped.
  *Check:* cut the step out, run it under `set -euo pipefail` with a scratch
  `HOME` and the real `omarchy-done`, make each write fail in turn (read-only
  file, read-only directory), and list the marker and whether the script went
  on. Extends L-468 and L-613. *From:* #895, round 62, 2026-11-18.
- **L-949. An allow-list that guards a credential path is run over the
  system's real catalogue, both ways.** #892's 35 "Latin" layouts refused
  `jp`, `al`, `vn`, `mt` and `kr` and accepted `us:rus` and `us:chr`; its
  test's rules file had four layouts. *Check:* run the backend with the host's
  `/usr/share/X11/xkb/rules/base.lst` (stand-ins for everything it would
  write), feed five layouts from outside the list and the variants upstream
  calls out, and compare with the upstream rule if one exists. Extends L-454
  and L-633. *From:* #892, round 62, 2026-11-18.
- **L-947. A change handler added to a QML service fires during the
  component's first binding evaluation, so a "when X changes" fix is also an
  "at every start" change.** #879's `onFirstIdleTimeoutSecondsChanged` re-arms
  the idle monitor on a timeout change and, by the same handler, at every
  shell start on every phone; the contributor's phone cases all began after a
  start. *Check:* for each `on<Property>Changed` a patch adds, model it in a
  ten-line QML file with a stand-in for the object it gates (`qml6`
  offscreen), log the gated property from creation, read the output for
  "Binding loop detected", and ask for the fresh-start case by name. Extends
  L-618 and L-444. *From:* #879, round 62, 2026-11-18.
- **L-933. A Qt test that builds the app's own runner or backend object runs
  whatever that object runs on the host, and an assertion written for "nothing
  installed here" fails on the phone the feature is for.** #860's page test
  ran the real `charge get` from `/usr/lib/omamobile-settings/backends` and
  asserted "not available"; on a phone with the package installed and the
  charger live it fails, and `tools/phone-install-package` runs `check()`.
  *Check:* in every new test, list the objects constructed (`ActionRunner`,
  `Backend`) and the fixed paths they open (`grep -n '"/usr/' app/*.cpp`),
  find the test's override for each, and read every "absent here" comment as a
  claim about the build host. Extends L-454, L-410 and L-234. *From:* #860,
  round 61, 2026-11-18.
- **L-926. When a "hide if we showed it" rule becomes "hide whatever is
  there", the trigger's false positives are re-read.** `homeOnScreen` (no
  window on the focused workspace) was a safe trigger while it could only hide
  a keyboard the plugin itself had raised; applied to every keyboard in #887,
  a transient empty workspace costs the user their keyboard in an app.
  *Check:* list the events that make the trigger true (a window closing as
  another opens, a new empty workspace during a launch) and ask for each
  during the phone run. Extends L-622 and L-738. *From:* #887, round 61,
  2026-11-18.
- **L-925. A gesture threshold a PR removes is traced to what it was
  compensating for.** The pill's "past 120 px: recent apps" looked like a
  design choice; it existed because the hold timer restarted on every pixel of
  movement and never fired under a real finger. #887 is right only because it
  fixes the hold in the same change. *Check:* `git log -S'<the threshold>'`
  for where it came from, then read the sibling path to the same destination
  (here the `hold` timer) and ask whether it works without the threshold on
  real glass, not only at the test's exact coordinates. Extends L-160 and
  L-620. *From:* #887, round 61, 2026-11-18.
- **L-924. `sed -i` on a user's config replaces a symlink with a regular
  file.** #727 appended with `>>`, which writes through a link; #886 inserts
  with `sed -i`, which renames a new file over the name, so a dotfiles link is
  silently broken, and the failure for an unwritable directory moves from the
  file to the directory. *Check:* run the step once against a symlinked target
  and once in a `chmod 555` directory, and read what `set -e` skips after it
  by the step's position in the script. Extends L-227 and L-468. *From:* #886,
  round 61, 2026-11-18.
- **L-920. A registry read moved behind a Loader gains a "not ready" branch
  that skips every participant.** `BackLink.back()` was unconditional on main;
  behind `backLink.item` in #582 it is skipped when the item is null, and the
  first thing skipped is the keyboard-first rule. *Check:* for any
  `Loader`-mediated call a PR puts in front of an ordered handler list, read
  what runs when `item` is null and compare with main's first step. Extends
  L-161 and L-617. *From:* #582, round 61, 2026-11-18.
- **L-913. A flag set before a fallible step and cleared after it is walked
  through the paths where the step's subject disappears by itself.** #837's
  `ipv6_release_owed` is cleared only by a later successful release; when the
  modem drops the bearer on its own after a failed release, the flag survives
  and a later, deliberately kept bearer gets one release it wasn't owed
  (probed: 2 releases became 3). *Check:* for every "owed" or "pending" flag,
  list each branch of the next pass (the thing listed, not listed, listed
  without its record), say what clears the flag in each, and run the PR's
  fixture through the branch that doesn't. Extends L-614 and L-502. *From:*
  #837, round 61, 2026-11-18.
- **L-897. `| head -1` under `pipefail` is the `grep -q` gotcha with another
  reader, and it only shows with a `head` that writes twice.** uutils 0.10.0's
  `head -c` splices again at end of file; GNU's doesn't, so CI and laptops
  never saw it and the build machine did, about once in 3,000 runs. *Check:*
  `git grep -n '| *head -n\?1\b'` in scripts under `set -o pipefail`, outside
  failure messages; test such a line with a stand-in writer that writes once
  more after a delay. Extends L-15, L-511 and L-765. *From:* #884 (after
  #842), round 61, 2026-11-18.
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
