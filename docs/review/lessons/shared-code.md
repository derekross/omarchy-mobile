<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Shared code and the reference device (part 1 of 3)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-1094. A draft that adds a module for a device node is grepped on main
  for another module of the same name or node.** #374's `aoc_tuning.py` in
  `omamobile-modem-sit` and main's `aoc_tuning.py` in
  `omamobile-speaker-tuning` both open the AoC's audio tuning node and its
  bulk nodes, each with its own in-process lock or none; four rounds of
  reviews never set the two side by side. *Check:* `git ls-tree -r --name-only
  origin/main | grep '<basename>'` and `git grep -n '<device node>'
  origin/main -- packages` for every new file that opens a `/dev` node; list
  which packages a phone can have installed together, and ask for a shared
  port or a sentence saying why they can't meet. Extends L-709, L-987 and
  L-720. *From:* #374, round 64, 2026-11-21.
- **L-1070. A unit ordered after a service that only one device package ships
  is unordered everywhere else.** `omamobile-fp.service` relied on
  `After=omamobile-aoc.service` to have Trusty's device; panther has no such
  unit, so the ordering was empty there and a path condition raced udev.
  *Check:* for each `After=` in a shared package's unit, `git ls-tree -r
  origin/main packages | grep <unit>` and list the device packages without it.
  Extends L-607. *From:* #903, round 63, 2026-11-20.
- **L-1039. "It changes no driver" is not true of a hardening option: a config
  line that adds run-time checks is a change to every driver the check covers,
  and gets a boot on the reference phone with those drivers exercised.**
  #939's four lines turn silent overruns in the AoC, CPIF and Trusty user-copy
  paths into a `BUG()` at boot. *Check:* diff the built `.config` at base and
  head; for each new `=y`, name what it does at run time and the failure it
  produces (BUG, WARN, cost only), list our drivers on that path from the
  base's own additions grepped for `copy_to_user` and the like, compare with
  Google's `gki_defconfig`, and write the dmesg grep into the runbook. Extends
  L-369, L-393 and L-51. *From:* #939, round 63, 2026-11-20.
- **L-1038. A config line for an unmerged kernel PR is inert only until that
  PR merges, so it is reviewed as "what does the first release kernel after
  the merge do on each phone", and it merges after the kernel PR.** #938's two
  symbols change nothing on the published kernel (identical `.config`), yet on
  main they would have turned kernel #279's devfreq on for the Pixel 7 at the
  next release without a decision here. *Check:* build `defconfig` plus the
  fragment at base and head on `github/omamobile` and diff the `.config`; if
  it is empty, read the kernel PR for how the driver binds on each board (an
  MFD cell with a platform alias loads the module on the reference phone even
  with no DT node; an OF-only alias behind a disabled node doesn't) and name
  the phone that changes. Extends L-394, L-149 and L-50. *From:* #938 with
  kernel #278 and #279, round 63, 2026-11-20.
- **L-1019. A new tuning file or sensor helper is checked against every phone
  that lists the same sensor model, not only the reference phone.** #934's
  `imx481.yaml` serves one phone's ultrawide and another's telephoto. *Check:*
  `git grep -n -i '<model>' origin/main -- device docs/DEVICES.md` for each
  model a libcamera patch names. Extends L-534. *From:* #934, round 63,
  2026-11-20.
- **L-1014. A drop-in for a daemon every image has, shipped in a package only
  some images install, is named as a coverage question.** #942 fixes GeoClue's
  start in `omamobile-gnss`, which two device lists install, while GeoClue
  comes with `omamobile-apps` everywhere. *Check:* `git grep -n '<daemon>'
  origin/main -- 'packages/*/PKGBUILD' rootfs 'device/*/device.conf'` for who
  installs the daemon and who installs the fix, and list the phones left
  without it. Extends L-442. *From:* #942, round 63, 2026-11-20.
- **L-1008. A change to a shared runner's supervision is checked against every
  profile that has a `profile_stop`, not only the one the PR adds.** #921's "a
  daemon ended on purpose during stop" branch would have changed the 7 Pro's
  modem stop if the modem's profile had used the same signal file; it ends
  rfsd in `profile_stop` too. *Check:* `git grep -n 'profile_stop' origin/main
  -- 'packages/*/profiles'`, read each for a daemon it ends, and grep for the
  new file's name under each profile's run directory. Extends L-206 and L-606.
  *From:* #921, round 63, 2026-11-20.
- **L-1000. A default-on governor is read against the phone's own idle and
  charging temperatures in the PR and the notes.** #946's floor sat 3 to 7 C
  above idle and below the 61 to 62 C its own description reports on the
  charger, so "floor at 60 C" meant "lowest clocks whenever plugged in".
  *Check:* list every temperature the PR and `device/<x>/NOTES.md` report
  (idle, charging, load) beside each threshold, and say which everyday state
  sits above each one. Extends L-703 and L-714. *From:* #946, round 63,
  2026-11-20.
- **L-989. "Behind the switch main already has" is checked for which device
  packages set that switch, and whether the contributor's phone is one of
  them.** Asked on #745 to choose between a switch and the default, the author
  put an 8 Pro measurement behind `OMAMOBILE_POWER_KEY_ANDROID`, which only
  the Pixel 7's package sets: the planned phone run would have exercised the
  old path, and the merge would have changed one phone, another owner's.
  *Check:* `git grep -n '<SWITCH>' origin/main -- 'packages/*/vendor'
  'packages/*/etc'` before accepting a switch as the answer; name the phones
  it reaches, ask how the test phone gets it, and what else the switch changes
  there. Extends L-608 and L-651. *From:* #745, round 63, 2026-11-20.
- **L-988. When main turns a one-phone tool into a per-board tool under an
  open PR, the PR's new steps are checked at every entry point, not only at
  `run`.** Main gave `husky-deadman-phone` a per-board `STEPS` list checked in
  `preflight`, which only `run` calls; #282's merge put its two new steps in
  the 8 Pro's list, and their `undo` (register and GPIO writes) and the
  `baseline` read stayed reachable on the 8a, with no test naming the second
  board. *Check:* list the tool's dispatch (`case "$cmd"`), and for each
  command say which board check it passes through; ask for one test case per
  refused board with an empty write log. Extends L-13, L-699 and L-730.
  *From:* #282 with #718, round 63, 2026-11-20.
- **L-958. A "keep it awake" answer for one phone is laid beside how the
  sibling phones with the same driver handle the same gap.** The 7 Pro's plan
  accepts a charge guard that is blind in s2idle, with the chip's JEITA as the
  backstop; #899 blocks sleep on husky instead, and nobody had read JEITA on
  husky. *Check:* `git grep -n -i 's2idle\|sleep' device/<reference>/*PLAN.md`
  for the mechanism, and put the difference and the missing read before the
  maintainer. Extends L-492 and L-461. *From:* #899, round 62, 2026-11-18.
- **L-957. A policy file copied from the reference phone is read against what
  the same options do on the new phone's published kernel.** #899's
  `omamobile-charger.conf` repeats the 7 Pro's "stock's bands from the gauge's
  temperature", while on husky's published kernel the table is the gs201
  default, the gauge temperature is constant and the float comes from a node
  at 4.20 V. *Check:* for each option line a device package copies, read the
  parameter's code on `github/omamobile` for per-board data, list the open
  kernel PRs the comment silently assumes, and ask the comment to name them.
  Extends L-299, L-528 and L-774. *From:* #899 with kernel #265 to #267, round
  62, 2026-11-18.
- **L-950. A safety net rewritten inside a feature PR is reviewed as its own
  change for every phone.** #892 folded a new owner of
  `screen-keyboard-enabled`, a udev follower and a lock poll into the 40-line
  guard that AGENTS tells people to check first when the keyboard stops
  appearing. *Check:* `git diff --stat` for files AGENTS section 4 names; for
  each, list what a phone without the feature's hardware now runs at login,
  and ask for the split and a reference-phone run of the no-hardware path.
  Extends L-491 and L-608. *From:* #892, round 62, 2026-11-18.
- **L-948. A feature written against the pinned-away Omarchy version is
  checked against what the current version already ships for the same setting,
  before its code is read.** #892 edits the user's `input.lua` for keyboard
  layouts, designed on 4.0.6; Omarchy 4.5 has `omarchy-setup-keyboard`, a
  store in `~/.config/omarchy/keyboard-layouts`, a Latin-first rule in
  `default/hypr/input.lua` and a bar widget, and the PR's block overrides all
  of it. *Check:* when a description says "on Omarchy 4.0.6", `bsdtar -tf` the
  pinned `omarchy` and `omarchy-settings` packages for the feature's nouns,
  read the `default/` file that sets the same keys, and run the PR's backend
  on that version's stock user file to see which store wins. Extends L-32,
  L-667 and L-499. *From:* #892, round 62, 2026-11-18.
- **L-938. A blacklist step that precedes "one explicit driver load" is
  checked against the form the device package uses.** oriole's bring-up file
  pairs `blacklist X` with `install X /bin/false`, which also refuses the hand
  `modprobe` the next step of #872's runbook needs. *Check:* `grep -n
  '^install .* /bin/false' packages/omamobile-device-<x>/vendor/modprobe.d/*`,
  and say in the runbook which form the new line takes and how the module is
  then loaded. Extends L-402 and L-393. *From:* #872, round 61, 2026-11-18.
- **L-935. A settings page whose write triggers an upstream fault turns a
  rare fault into a button, so the page's merge is ordered after the fix and
  tied to it by a versioned dependency.** #866 writes `idle.lock` on a running
  shell; with the monitor fault behind #879, each tap left the phone with no
  idle lock until a shell restart, and the page reported success. *Check:*
  when a contributor's own reading shows "the value arrives but nothing
  happens", name what the page's write then leaves the phone doing, find the
  PR that fixes it, and ask for `depends` on that package's version; "works
  after the other PR" is not an order by itself. Extends L-37, L-442 and
  L-623. *From:* #866 with #879, round 61, 2026-11-18.
- **L-932. `systemctl enable --no-reload` in a first-boot script is judged
  per unit against what the image already enabled.** In #839 five of the eight
  units were already enabled by `rootfs/build-inside`, so the change is empty
  for them; the other three are first enabled at first boot, and only those
  can behave differently in the first session. *Check:* lay the script's unit
  list beside the `systemctl --root=... enable` lines in
  `rootfs/build-inside`, and ask for `is-active` of the difference in the
  first session, with and without the change. Extends L-668 and L-758. *From:*
  #839, round 61, 2026-11-18.
- **L-931. A first-boot prompt that blocks one port is checked against the
  base system's own switch for it before a package-side condition is
  reviewed.** #839 added an `ExecCondition` drop-in to skip
  `systemd-firstboot.service`; `systemd.firstboot=off` on the kernel command
  line does that per device, and Pixels never see the prompt because their
  bootloader forces `console=null`. *Check:* `man <the unit's tool> | grep -n
  -A6 'KERNEL COMMAND LINE\|systemd\.'` for a documented switch, and ask which
  phones have a live console (`grep -n 'console=' device/*/device.conf`)
  before accepting a shared-package workaround. Extends L-11, L-233 and L-32.
  *From:* #839, round 61, 2026-11-18.
- **L-917. A fix that only acts where the next line always fails can merge
  without the reference phone's run, once that "always" is shown from the
  code.** #881 clears a record in a state where `activate()`'s ownership check
  refuses on every phone, so no working path changes. *Check:* write down the
  condition of the new branch, find the first check after it on main, and show
  that check fails for every value the condition allows (a damaged record
  included); then run the PR's test against main's file to see it fail.
  Narrows L-206 and L-444 for dead-end fixes. *From:* #881, round 61,
  2026-11-18.
- **L-908. A start-up cleanup written for "the earlier process stopped" is
  re-read when main learns that the same state arises while running.** #376's
  `clear_stale()` keys on "the modem lists no bearer"; since
  omamobile-modem-sit 0.3.42 and #881 that is also what a network drop looks
  like to a running sitd, and another contributor was about to write the same
  repair in `reconnect()`. *Check:* for a draft's state test, `git log <its
  base>..origin/main -- <package>` for code that now produces or handles that
  state, and name the overlap to both authors. Extends L-730 and L-720.
  *From:* #376 with #881, round 61, 2026-11-18.
- **L-904. A "source and evidence" PR for one handset is first a question of
  what main should carry.** #821's runner is pinned to one kernel release,
  needs a private profile, binary and controllers, and adds a suite to
  `tests/all` for code only its author can run. *Check:* for a bring-up
  directory whose README says it can't be run from the public files, list what
  it adds to CI and what goes stale with the next kernel, and put "plan on
  main, runner on the fork" to the maintainer before reviewing the code line
  by line. Extends L-667 and L-704. *From:* #821, round 61, 2026-11-18.
- **L-889. A new early stop in a start path is checked against the logs for
  the message it replaces.** #874 turned `check`'s note "no /dev/goodix_fp:
  only stages before 'hal' can run" into a stop; 30 logs with the runner's
  lines never show that note, so the node has been there by `check` on every
  recorded boot, and the phones without logs are named as first runs. *Check:*
  `grep -rl '<the old note>' logs/ | wc -l` against the count of logs that
  have the unit's lines at all. Extends L-493 and L-444. *From:* #874, round
  61, 2026-11-18.
- **L-888. Tightening a board selector from "everything else is the reference
  phone" to "the reference phone by its compatible" is checked against what
  the running phone's device tree really says.** #874 made cheetah an explicit
  match; a bootloader overlay that rewrote the root `compatible` (stock's does
  on some Pixels) would have turned fingerprint off on every 7 Pro. It doesn't
  here: cheetah's DTBO is empty and `initramfs/init` compares the same string
  at every boot. *Check:* read `device/<codename>/<dtbo source>` for a root
  `compatible`, and find an existing runtime match on the same string
  (`board_matches` with the descriptor's `COMPATIBLE`) before calling a strict
  match safe. Extends L-757 and L-13. *From:* #874, round 61, 2026-11-18.
- **L-874. A default-on visual correction for a fault with an intermittent
  second state is walked through that state.** The panel in issue #537 has
  been seen "deeper" by both owners with nothing changed; #880's shader, tuned
  on the washed state, would darken the deep one further, and its opt-out is a
  file the owner has no reason to know. *Check:* list every state the thread
  records for the thing being corrected, apply the correction to each, and ask
  for opt-in until a second unit has run it. Extends L-491 and L-703. *From:*
  #880 with issue #537, round 61, 2026-11-18.
- **L-871. A config file a package drops into a running daemon's `conf.d` is
  asked "when does the daemon read it", and the README says from when an
  updated phone has the setting.** #836's own installed-package run showed
  NetworkManager kept `Power save: off` after `pacman -U` until a reload; the
  README's "applies when a connection comes up" was true only after the next
  start. *Check:* for each new `conf.d` file, name the daemon's reload trigger
  (start, SIGHUP, `nmcli general reload`) and whether the package's `.install`
  may run it (the device packages' scripts are `cmp`-pinned to cheetah's), and
  ask the phone run for the value before and after a reconnect without a
  reload. Extends L-433 and L-758. *From:* #836, round 61, 2026-11-18.
- **L-818. A "re-arm" through another feature's IPC is read in that feature's
  source for what it persists.** #866 made a new lock time take effect with
  `omarchy-shell idle disable` then `enable`; in Omarchy 4.5 `disable` is
  `setIdleEnabled(false)`, which turns Stay awake on and writes its state
  file, so an interrupted re-arm leaves a phone that never locks or sleeps,
  across reboots. *Check:* for every `omarchy-shell <target> <verb>` or toggle
  a PR calls as a side step, read the handler in the pinned package (`bsdtar
  -xOf` its `Service.qml`) for `persist`, state files and indicators; list
  every way the caller can end between the two calls (a kill timer, the app
  closing, session end) and the state left; look for the call Omarchy's own
  writers use. Extends L-161, L-734 and L-705. *From:* #866, round 60,
  2026-11-17.
- **L-816. A new row in the Settings catalog is opened on a phone without the
  feature, and on a phone that has the feature another way.** #860's row would
  show on every phone and open "not available on this phone", also on the 9a,
  which has a file-based charge limit. *Check:* for each catalog row a PR
  adds, list DEVICES.md's phones and what the page shows on each; `git grep -n
  -i '<feature>' origin/main -- 'packages/omamobile-device-*'` for an existing
  mechanism. Extends L-707 and L-667. *From:* #860, round 60, 2026-11-17.
- **L-815. A page in a shared app that keys "available" on a sysfs attribute
  is live on every phone whose driver gains that attribute, so the attribute's
  kernel PR is read for which boards get it.** #860's Battery page was "for
  husky", but only its boot path checked the device tree; kernel #266 adds
  `charge_control_end_threshold` to `max77759-charger` on every board, so the
  page would have gone live on the Pixel 7 Pro with the next kernel, with a
  limit that doesn't survive a reboot. *Check:* for each `[[ -r /sys/... ]]`
  availability test in a shared package, `git grep` the attribute's driver on
  the base and the open kernel heads for a per-board condition; run every verb
  of the helper in a scratch root with the reference phone's `compatible`;
  prefer a declaration shipped by the device package. Extends L-608, L-730 and
  L-612. *From:* #860 with kernel #266, round 60, 2026-11-17.
- **L-813. A NetworkManager default shipped in
  `/usr/lib/NetworkManager/conf.d` is checked against omarchy-settings' files
  in `/etc/NetworkManager/conf.d`, which are read later and win.** #836 found
  that only a file in `/etc` whose name sorts after
  `omarchy-wifi-powersave.conf` changes `wifi.powersave`; a sibling device
  package ships the same setting from `/usr/lib`, where it most likely does
  not apply. *Check:* `bsdtar -tf` the pinned omarchy-settings package for
  `NetworkManager`, then run `NetworkManager --print-config --config
  <scratch>/NetworkManager.conf --config-dir <scratch>/etc --system-config-dir
  <scratch>/lib` with both files in place (it needs no root), and `git grep -n
  'NetworkManager/conf.d' origin/main -- 'packages/*/install'` for siblings
  shipping the same key. Extends L-32, L-63 and L-492. *From:* #836, round 60,
  2026-11-17.
- **L-808. A test that makes the prebuilt know a new option turns the merge
  into a rebuild and a reference-phone change.** #874's `opts="$opts
  --sensor"` fails `check()` on the build machine until the maintainer
  rebuilds the fingerprint bridge, and the rebuilt bridge ships to every
  phone. *Check:* when a PR touches `fingerprint/bridge` or a bionic source,
  grep its `test/all` for the prebuilt assertions, and put "rebuild the
  prebuilt, boot it on the 7 Pro" in the merge plan before the merge. Extends
  L-268, L-310 and L-590. *From:* #874, round 60, 2026-11-17.
- **L-803. A fix to a file that names a process or a path is reviewed through
  every reader of that file, in every package, because each of them has been
  failing closed.** #864 corrected the vendor runner's `ns.pid`;
  omamobile-modem's stop-time NV capture, its `nv-overlay diff|capture` and
  the overlay timer read the same file and returned quietly on a dead PID, so
  the fix turns a never-run, safety-gated feature on with a GNSS package
  update. *Check:* `git grep -n '<file name>\|<its variable>' origin/main --
  packages tools`; for each reader write down what it did with the broken
  value and what it will do with the right one; anything a plan gates behind
  an attended runbook goes to the maintainer before merge. Extends L-623 and
  L-413. *From:* #864 with issue #862, round 60, 2026-11-17.
- **L-795. A configuration key that a second package starts reading is checked
  against how its owner documents the default.** `omamobile-boot-update` says
  of `SLOT=` "Absent means b"; #850 made the modem read a present `SLOT=b` as
  "a format-2 install on B". *Check:* `git grep -n '<KEY>=' --
  'packages/*/etc' 'packages/*/README.md' tools docs` for the owner's wording
  and for every writer, then walk the new reader with the default written out
  explicitly, on a phone installed the old way. Extends L-450 and L-608.
  *From:* #850, round 60, 2026-11-17.
- **L-791. A check added for a new format is looked for in the old format's
  path too.** #848 put the image and allowlist checks inside the manifest's
  format 2 branch while every shipped bundle is format 1. *Check:* for each
  `if <new mode>:` block a PR adds to a manifest or plan writer, list the
  checks inside it and ask which also hold for the mode every device uses
  today. Extends L-608. *From:* #848, found by #841, round 60, 2026-11-17.
- **L-760. A new `syscon`-only node in a shared SoC dtsi is neutral on sibling
  boards, because a syscon regmap is made on first lookup, not at boot; say
  that rather than asking for `disabled`.** L-465's request is for nodes that
  bind a driver and touch registers at probe; kernel #243's
  `google,zuma-vgpio2ap-sysreg` binds none. *Check:* the compatible list ends
  in `syscon` and `git grep '"<compatible>"' drivers/` is empty, nothing on
  the sibling references the label, and `clk-<soc>.c` has no gate for the
  block. Narrows L-465. *From:* kernel #243, round 52, 2026-11-11.
- **L-759. When the image's package list follows upstream's, every package a
  new upstream version adds is read for its licence and against our held
  migrations.** Omarchy 4.5's composed list adds `superwhisper-bin`
  (`LicenseRef-proprietary`), and `owe` and Fcitx add-ons whose migrations we
  hold on updated phones, so a fresh image would differ from an updated phone.
  *Check:* compose both versions' lists with `omarchy_packages`, `comm` them,
  `pacman -Si` each addition for `Licenses`, and grep `omarchy-migrate`'s hold
  list; additions go to `rootfs/packages.omarchy-skip` or get a line saying
  why not. Extends L-233 and L-584. *From:* #665 with #670 (commit review),
  round 52, 2026-11-11.
- **L-758. A fix for a base-system requirement that a new upstream version
  enforces is checked for what delivers it to each phone before the pin
  moves.** #437 fixed `/run`'s mode in the initramfs, which reaches a phone
  only with new boot images and a reboot, and only the 7 Pro's device package
  carries boot files; #670 then moved every phone to Omarchy 4.5, whose sudo
  migration exits 1 on `/run` 1777 (issue #447). *Check:* for each such
  requirement, name what delivers the fix to a release-installed phone and to
  each device without packaged boot files; prefer a fix inside the transaction
  (tmpfiles.d, the update's preflight). Extends L-500, L-442 and L-415.
  *From:* #670 with #437 and #673 (commit review), round 52, 2026-11-11.
- **L-732. A table keyed on the bootloader's scanout size is checked for a second board of that size on the same SoC, open PRs included.** Kernel #181 picks gs201's modes by 1080x2400, which is also the Pixel 7a's size (kernel #202). *Check:* list the panel sizes of every board on the SoC, merged and open, before accepting size as a key. Extends L-464 and L-104. *From:* kernel #181 with kernel #202, round 51, 2026-11-11.
- **L-731. An opt-in shell feature is checked for the surfaces it maps with the option off.** #612's setting gates the dock tap, but its two full-screen Top-layer windows are `visible: true` on every phone. *Check:* grep the diff for `PanelWindow` and read each `visible:`; with the option off, `hyprctl layers` matches main's. Extends L-608 and L-491. *From:* #612, round 51, 2026-11-11.
- **L-730. An unchanged open PR is re-read each round against what the base gained under it: new compatibles in its driver's match table, and merged code that touches its open points.** Kernel #232's sleep callbacks bound one SoC until the base gave `pcie-gs201-cp` the Pixel 9a's compatible; #556's "screen state runs on every phone" was a caution until main got the 9a's own start-up "screen on" and a modem unit that can start at boot. Neither diff had changed. *Check:* `git log <old base>..<base> -- <each touched file>`, `git grep -n compatible <base>:<file>`, and grep main for what each open point names. Extends L-423, L-206 and L-608. *From:* kernel #232, #556, round 51, 2026-11-11.
- **L-705. A switch named after one feature that flips a shared daemon's
  profile is read for what else the profile governs.** #629's "keyboard
  haptics: off" set feedbackd's `silent` profile, which drops sound and
  vibration for every event, and omatel rings calls through feedbackd.
  *Check:* `git grep -n feedbackd origin/main -- 'packages/*/PKGBUILD'
  packages/omamobile-shell`, and the app repositories, for the other consumers
  before accepting a profile change. Extends L-462. *From:* #629, round 50.
- **L-704. A new file directly under `device/<codename>/` is checked against
  the names the build tools read by convention.** #565 added
  `device/bluejay/kernel.config` as the record of one build; `bin/omamobile
  kernel` merges that file into every non-release build, so its fixed
  `CONFIG_LOCALVERSION` would have named every Bluejay kernel after the tested
  one, defeating the helpers' `uname -r` pin. *Check:* `git grep -n
  'device/\$DEVICE/' bin tools` for the file's name, and grep any fragment for
  `LOCALVERSION`. Extends L-149 and L-337. *From:* #565, round 50.
- **L-703. A once-only step keyed on a default value reaches every device that
  still has the default, and "unchanged on the 7 Pro" covers the result, not
  the mechanism.** #635's step matches scale `= 3` or `"auto"`, so the 8 Pro
  would rescale at its next login; on the 7 Pro the scale stays 3 (71x155 mm,
  also at ±2 mm) but the session gains a rewritten user file and a module run
  at every reload. *Check:* a table of DEVICES.md's devices with each one's
  input and result, and a list of the side effects that don't depend on the
  result. Extends L-608 and L-299. *From:* #635, round 50.
