<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Safety model (AGENTS.md section 1) (part 2 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-1012. A kernel module that reaches a protected block past the driver's
  own tables is a rule question even when AGENTS' wording says
  "userspace".** #926's bring-up modules map the PMU and make the regmap's
  EL3 write call directly. *Check:* `grep -n
  'ioremap\|arm_smccc_smc\|writel'` over the `.c` files of any PR that adds
  a bring-up module under `device/*/bringup/`, compare each address with
  AGENTS section 1's blocks (PMU, AoC, modem BAR, GSA pinctrl), and send it
  to the maintainer apart from the docs verdict. Extends L-2 and L-456.
  *From:* #926, round 63, 2026-11-20.
- **L-1007. A run row that names a helper script is grepped for the script.**
  #912's row cited `touch-log.py`, which was in no tree and ran unattended on
  its first day. *Check:* `git grep -n '<script>' origin/main <head>`; a
  helper outside the tree is asked into `device/<x>/bringup/`, and its first
  run is read against the attended-first rule. Extends L-694 and L-109.
  *From:* #912, round 63, 2026-11-20.
- **L-978. When one step of a runbook gets a guard check, the other steps
  that arm the same thing get it too.** #815's fix put `is-active
  omamobile-modem` in front of K1b.4's watchdog-armed write; K1b.1 and K1b.2
  arm the same watchdog two steps earlier with only "(Setup)" to lean on, and
  a reset there boots with the modem up because the mask comes later.
  *Check:* list every step that runs the guarded tool (`grep -n` the tool's
  name in the plan), and for each one the boots that can precede it; the
  precondition is checked in all of them, or set once before the first.
  Extends L-319 and L-725. *From:* #815, round 62, 2026-11-18.
- **L-966. A vendor download's terms are read on the vendor's page before the
  tool is reviewed as "just a fetch".** #900's tool fetched Google's NDK,
  whose page asks for agreement before the download; the project already has
  a rule for Google's factory images. *Check:* open the download page, grep
  for "terms" and "agree", and compare with how `tools/install-guided`
  handles the same vendor (the owner accepts, never the tool or an agent).
  *From:* #900, round 62, 2026-11-18.
- **L-944. A plan's own "must never" is counted in the results the same PR
  adds.** #714's BRINGUP-M1 says an NFS boot must never fall through to
  writable `userdata`, and its notes recorded at least eight such falls in
  four days, each followed by another attempt. *Check:* grep the plan for
  `must never\|stop` and the new results for the event's words ("restarted
  into", "returned to the existing"); a stop rule hit and passed is reported
  to the maintainer apart from the diff. Extends L-445 and L-663. *From:*
  #714, round 61, 2026-11-18.
- **L-937. A bring-up plan written beside a private stack is read for every
  noun that only the private stack defines.** #872's gate said "the
  qualified deployment and rollback procedure", "the existing watchdog" and
  "private address provisioning"; none exists in the public package, so the
  public runbook had no dead-man and no way to write the image. *Check:* for
  each definite noun in a runbook step ("the existing X", "the qualified
  Y"), `git grep` it in the device's package and tools on main; a miss
  becomes a command from the public tree or a named gap. Extends L-567, L-157
  and L-82. *From:* #872, round 61, 2026-11-18.
- **L-930. Editing a secret out of a PR description leaves it in the
  description's public edit history, and "please delete that revision" is
  re-read through the API at the next round.** #630's secrets were removed
  from the text on request; the earlier revision still showed them to anyone
  who opened the "edited" menu, and two days after we asked it was still
  listed with no `deletedAt`. *Check:* `gh api graphql` for
  `pullRequest(number:N){userContentEdits(first:30){nodes{createdAt
  deletedAt diff}}}`, test each `diff` for the secret's shape with the
  digits masked (never print it), name the revision by its timestamp, and ask
  the author to "Delete revision from history"; a repository admin can do it
  without waiting, and a credential also gets changed. Extends L-324, L-563
  and L-688. *From:* #630, rounds 61 and 63, 2026-11-20.
- **L-916. An offer in a thread to "send a script that fetches a pinned X" is
  answered in the review, not left to arrive.** A new download URL and
  checksum gets its own pull request and review, the more so while the
  project's servers are being probed. *Check:* grep the thread for "fetch",
  "download", "pinned" and "script" in contributors' offers, and say where
  such a change should go. Extends L-224 and L-632. *From:* #864, round 61,
  2026-11-18.
- **L-909. A subprocess timeout is its own exception class: a handler that
  lists `RuntimeError` and `OSError` doesn't catch it.** #626's speaker
  switch ran `amixer` through `subprocess.run(timeout=10)` inside a socket
  request whose handler caught `(ValueError, KeyError, TypeError,
  RuntimeError, OSError)`; `subprocess.TimeoutExpired` passes through, ends
  the daemon's loop and hangs up the call (main's mute had the same gap).
  *Check:* `grep -n 'timeout=' <module>` for `subprocess.run`, then read the
  `except` tuple of every caller up to the main loop; `python3 -c 'import
  subprocess; print(subprocess.TimeoutExpired.__mro__)'` settles what it is.
  Extends L-776. *From:* #626, round 61, 2026-11-18.
- **L-907. A PR next to a "never restart X" rule is placed on one side of the
  rule by naming the layer it restarts, and its docs carry that sentence.**
  #376 restarts the phone service on a live CP; AGENTS forbids restarting the
  modem profile. The code was on the allowed side, but its unit comment ("a
  second start-up on the same CP ... sets up again") read across to the modem
  unit, and the device's own plan still listed "no ... sitd restart".
  *Check:* grep the diff for the process, unit and power calls the rule names
  (`omamobile-modem`, `cbd`, `modprobe`, CP power); if none, ask for one
  sentence in the shipped comment that separates the two, and reconcile the
  device plan's own rule. Extends L-661, L-662 and L-445. *From:* #376, round
  61, 2026-11-18.
- **L-905. A record of a radio's first traffic says what confined its DMA,
  and the notes PR is where to ask.** #751 and #822 recorded a PCIe Wi-Fi
  chip associating and carrying HTTPS, with autoconnect on, and neither said
  the endpoint had no restricted pool; the kernel node (kernel #255) then
  arrived without one. *Check:* for a notes PR that records a PCIe or other
  bus-master radio passing traffic, `git grep -n
  'restricted\|memory-region\|iommus'` in the record and the board node, and
  ask for the sentence and the gate. Extends L-777 and L-486. *From:* #822
  with kernel #255, round 61, 2026-11-18.
- **L-893. An installer PR that removes a fallback is reviewed as a table of
  what each kind of computer sends the phone before and after.** For #877
  that table showed one variant removed (the raw `userdata` image from a
  computer without `img2simg`) and none added, which made "no phone test
  needed" a finding and not an assumption. *Check:* list the host conditions
  the changed branch tests, and for each write the exact fastboot lines from
  the suite's expected output on main and on the head. Extends L-223 and
  L-668. *From:* #877, round 61, 2026-11-18.
- **L-885. A backup "taken after the stock boots, before any Trusty start" is
  placed in UTC next to the author's other threads.** #203's reference backup
  was dated the night between two days on which the same author's #874 says
  the phone's first storage proxy start ran. *Check:* convert the backup's
  time with the zone of the author's commits, search the author's open PRs
  for dated hardware starts in that window, and ask which came first.
  Extends L-591, L-168 and L-559. *From:* #203 with #874, round 61,
  2026-11-18.
- **L-884. An answer to "what do the slot flags read?" is decoded against the
  last recorded bytes, and a "successful: yes" where we last agreed "no
  marking" is a write to find.** #203's reply gave slot B as successful; the
  earlier record and the restore since meant a new mark had to exist: a hand
  `devinfo` write three days after "don't write `devinfo` again", disclosed
  only when asked. *Check:* lay each reported byte of 0x30-0x37 next to the
  previous record with the layout's bits (0x01 unbootable, 0x02 successful,
  0x04 active, 0x08 fastboot-ok), list every bit that moved, ask for each
  what wrote it and when, and compare the dates with every hold in the
  device issue. Extends L-36, L-359 and L-756. *From:* #203 with issue #143,
  round 61, 2026-11-18.
- **L-870. A stop-condition grep that must come back empty is not where an
  "expected line" goes.** #835 made the UFS `dme-set` line expected, and the
  contributor offered to add it to the `after` helper's grep, whose Pass is
  "empty"; that would have failed every later stage. *Check:* when a plan
  excuses a log line, read each helper that greps for errors and its Pass
  wording; an excused line gets its own counted check beside the helper,
  never an entry in the must-be-empty pattern. Extends L-756 and L-183.
  *From:* #835, round 61, 2026-11-18.
- **L-868. A raised limit carried in a device tree follows the kernel image
  wherever it boots; a limit raised by a running guard doesn't.** Kernel #267
  put husky's 4.45 V float in the battery node; the author's daily kernel,
  built from the same tree, then charged at 4.45 V on a morning when he had
  promised no raised-float runs. *Check:* for a DT value that is only safe
  with a driver option or a userspace file, ask what a boot without that
  option does (L-458), and prefer the value being applied by the code path
  that provides the protection. Extends L-458, L-411 and L-284. *From:*
  kernel #267 with #761, round 61, 2026-11-18.
- **L-867. A contributor's hold on a hardware state is checked against the
  kernel each new report ran on, and a second passing gets a mechanism, not a
  second reminder.** On kernel #266 and #836 the smoke report's release was
  the local kernel with the raised float, about 80 minutes before the author
  noticed it himself: the evidence for one PR had been gathered inside the
  state another thread had put on hold. *Check:* for every report from a
  contributor with an open hold, compare its `uname -r` with the kernel the
  hold names; when a hold is passed by accident, ask for a safeguard that
  doesn't depend on memory (a distinct `LOCALVERSION`, a read before the
  step, an option set by hand). Extends L-557, L-694 and L-378. *From:*
  kernel #266 with #836 and #761, round 61, 2026-11-18.
- **L-856. A safety account that says "restored, verified" or "revalidated the
  backup" is asked where the bytes were read from.** fastboot doesn't
  normally read a partition back, so kernel #260's md5 check was either a
  read from Linux with the unguarded eMMC enabled or a check of the files
  that were sent; #714's revalidation re-hashed the backup files on the
  laptop and said nothing about the phone's partitions after boots of an
  unguarded install. *Check:* for every "verified" in a restore or backup
  report, name the tool that read the partition, the kernel it ran under and
  whether that boot was guarded, or say that only the archive was hashed.
  Extends L-649, L-600 and L-168. *From:* kernel #260, round 60, 2026-11-17;
  #714, round 61, 2026-11-18.
- **L-831. An undo that writes back a saved register is run with another field
  changed in between.** #815's steps change one bit and say so, but the undo
  restored the whole byte, the input-limit field included; the stub run
  showed it only when that field was changed by hand between apply and undo.
  *Check:* in the stub, change every other field of the register after the
  apply and run the undo; ask for a restore of the changed bits alone.
  Extends L-419 and L-727. *From:* #815, round 60, 2026-11-17.
- **L-830. A runbook that masks a boot-started unit "after boot" leaves it
  running for that boot.** #815's K1b.3 masked `omamobile-modem-boot.target`
  after the push's reboot had started the modem, so the next step's
  watchdog-armed write would have run with the modem up, against the plan's
  own Setup. *Check:* for each `mask` or `disable` in a runbook, name the
  boot it first takes effect on and the step that needs the unit down; if
  they are the same boot, the mask goes before the reboot, or a stop is
  written into the step. Extends L-564 and L-445. *From:* #815, round 60,
  2026-11-17.
- **L-825. A fallback that "landed in stock recovery" is asked whether Android
  itself started.** #852 recorded a slot A fallback ending in recovery and
  `adb reboot bootloader`, with no word on a backup; CONTRIBUTING §3.3's rule
  is about a stock Android boot, and a recovery screen alone doesn't run the
  modem stack. *Check:* grep a docs PR for "recovery", "fell to" and "slot
  A", and ask which of the two it was. Extends L-726 and L-186. *From:* #852,
  round 60, 2026-11-17.
- **L-812. "One stage per go-ahead" in a runbook names whose go-ahead.**
  #835's H1 ran twenty minutes after H0b on the go-ahead given for H0b; the
  plan's rule didn't say the maintainer's. *Check:* for each per-stage
  consent rule in a plan, find the comment that gave it for the stage
  recorded, by time (author dates in UTC against the thread), and ask that
  the rule name the person. Extends L-663 and L-694. *From:* #835, round 60,
  2026-11-17.
- **L-809. A "default for every new device" is checked at the selector's
  fall-through, not only at the variable's default.** #874's
  `FIRST_START=${FIRST_START:-owner}` was the default for a new `case` entry,
  but `fp_device` mapped every unknown board to cheetah, whose entry says
  `auto`. *Check:* run the tool with the selector unreadable and with an
  unknown board, and read the value it prints (here `first_start=auto`).
  Extends L-757 and L-13. *From:* #874, round 60, 2026-11-17.
- **L-807. Moving a module load from a unit's `ExecStartPre` into a tolerant
  line of the script moves the failure past whatever the script does next.**
  #874 replaced `ExecStartPre=modprobe goodix_fp` (the unit fails before the
  runner) by the runner's `modprobe ... || true`, so a missing sensor driver
  would let storageproxyd start before the HAL stage died. *Check:* for each
  removed `ExecStartPre=`, `Requires=` or `Condition*=`, name the first
  irreversible step of `ExecStart` and where the same failure now stops.
  Extends L-754 and L-415. *From:* #874, round 60, 2026-11-17.
- **L-787. A cleanup added to a tool that takes a caller-named folder is run
  once on the folder the next tool in the flow writes.** #824's removal was
  exact in its own download folder; pointed at `out/<codename>/repo/aarch64`
  it removed the port's own package and left the index that lists it.
  *Check:* list the folders the neighbouring tools create (`out/repo`,
  `out/<codename>/repo`, the bundle folder), run the new cleanup on a fixture
  of each with one marker file per kind, and ask for a refusal keyed on a
  file only that folder has (`omamobile.db`). Extends L-7, L-227 and L-554.
  *From:* #824, round 60, 2026-11-17.
- **L-776. A helper that "falls back to the old path on failure" is checked
  against every exception the transport under it raises, not only the ones
  the tests inject.** #754's `reconcile()` caught `ModemError`, `TimeoutError`
  and `OSError`, while `Sit.request()` also raises a bare `RuntimeError` and
  `EOFError`; either one skipped the unconfirmed release's radio-off that the
  helper sits in front of, and all of the PR's tests stayed green. *Check:*
  `grep -n 'raise ' <transport>` for every exception class the helper's call
  can raise, then run the PR's fixture with each as the side effect and count
  the safety calls on main and on the head; prefer `except Exception`
  returning "not handled". Extends L-757 and L-716. *From:* #754, round 57,
  2026-11-14.
- **L-757. A safety or recovery call that a PR puts behind a selector or a
  helper is run with the selector wrong and with a stop arriving mid-start,
  and the hardware calls are counted on main and on the head.** #669's profile
  lookup raised on an unknown value inside the `except` that swallows
  transport errors, so a typo turned the uncertain-call radio-off into nothing
  (0 AT calls, 1 on main); its `stopped()` test before the default path
  dropped main's AT off/on when a stop came during the state read, with every
  clean-start test green. *Check:* the selector unknown, for another board and
  unreadable, then each condition the helper tests; an unresolvable selector
  falls back to the old call. Extends L-161, L-458 and L-608. *From:* #669,
  round 52, 2026-11-11.
- **L-756. A decision that rested on a slot's or firmware's state, and every
  stop condition written about that state, are re-read when either changes.**
  On issue #143 comet "doesn't need B marked" was agreed while slot A was
  unbootable; the stock restore we then asked for lets it fall back to a stock
  that may reset `userdata`, and #203 still quotes the first answer. #567's
  step 1 still stops on "mismatched firmware" after the maintainer accepted
  both bootloader versions, so it can't pass. *Check:* after a restore or a
  decision, grep the device issue for answers naming a slot flag and the
  runbook for `stop\|confirm`; ask for `slot-successful` and
  `slot-retry-count`. Extends L-284 and L-519. *From:* #203 with issue #143,
  #567, round 52, 2026-11-11.
- **L-755. A private package installed under a public package's name is a
  version question before it is a content question.** The working 6a reports
  `device-bluejay 0.1.1` from a local build while #346 proposes 0.1.0: the
  published package can't install over it, and the first higher version
  replaces it on `omarchy update` and deletes the blacklist and start-up units
  it owns. *Check:* when a record shows `pacman -Q <public name>` at a version
  main never had, ask what it owns (`pacman -Ql`), plan the move as an
  attended step, and hold the name (`IgnorePkg`) until then. Extends L-358,
  L-567 and L-609. *From:* #346, round 52, 2026-11-11.
- **L-754. A runbook's install set is read through each installed unit's
  `Requires=` and `Condition*=`, and the Expect is checked against them.**
  #565's root-gate section installed a display-manager drop-in requiring two
  units the same section says it doesn't stage, while expecting "the desktop
  ready". *Check:* for every unit or drop-in a runbook copies, `grep -n
  'Requires=\|Condition\|After=' <file>` and confirm each named unit and path
  is installed or created by the same step; otherwise the Expect names what
  won't start. Extends L-320. *From:* #565, round 52, 2026-11-11.
- **L-753. A contributor's "its first run will be attended" is checked against
  the record's start times and its "who was there" column.** #659's body
  promised an attended first run of the new `sleep-series.sh`; the plan pushed
  later shows 90 sleeps at 07:00 MST with the owner out, then a 310-sleep
  series without his yes, and kernel #224's thread quoted the count alone.
  *Check:* lay the record's start times in UTC beside the thread (L-591) and
  grep the plan for "attended"; a header that counts exceptions is re-read
  with every new row; an honest "it wasn't" goes to the maintainer as a rule
  question. Extends L-445. *From:* #659 with kernel #224, round 52,
  2026-11-11.
- **L-752. A phone tool's argument handling is read in its source before the
  tool is run, and a binary that can reboot, power off or write is never
  probed with `--help`.** While testing #403, a test build of `reboot-to` was
  run on the 7 Pro with `--help` to read its usage; `reboot-to` takes any
  argument as the reboot reason, so the phone restarted with the modem up and
  without the maintainer's go. *Check:* read `main()` in the tool's source
  (`packages/omamobile-device-*/src/reboot-to.c`) for what it does with
  `argv[1]` before its first run on a phone. See L-564. *From:* #403, round
  52, 2026-11-11.
- **L-729. A boot that replaces `multi-user.target` is re-checked against the wants links merged while its PR was open.** #554 was checked against main's units on 2026-11-09; two days later #510 had added `omamobile-usb-mac.service`, wanted only by `multi-user.target`, so the charger boot would have come up with other USB addresses. The textual conflict was elsewhere. *Check:* each round, `git diff <old base>..origin/main --name-only -- 'packages/*/vendor/systemd/system/*.wants/'`, and decide for each new link whether the alternate target needs it. Extends L-603. *From:* #554 with #510, round 51, 2026-11-11.
- **L-728. Before asking for a footer rollback index from stock, ask how the phone's vbmeta lists the boot images.** libavb reads a footer only for a partition the vbmeta chains; #567's phone lists all five images as hash descriptors on both slots, so the index we had asked to lower is compared with nothing. *Check:* for a new device's `AVB_FOOTERS` and `AVB_ROLLBACK_INDEX`, first get `avbtool info_image` on `vbmeta_a` and `vbmeta_b` read from Linux (flags, own index, chain or hash descriptor per image); for chained images L-225 applies, for hash descriptors keep what the phone has booted and change one thing per boot. Extends L-225 and L-169. *From:* #567, round 51, 2026-11-11.
- **L-727. A tool that writes several sectors in sequence is interrupted at each write in review, and then run again.** #651's `mark-slot-b` kept one GPT copy valid at every moment, but after a failed 2nd, 3rd or 4th write its own cross-checks refused every later run, which left a hand `dd` as the way forward. *Check:* wrap the test's fake SSH so the Nth write fails, for each N, then run the tool again (dry and `--write`); a state it refuses needs a resume or undo path, and the old sectors saved before the first write. Extends L-413 and L-419. *From:* #651, round 51, 2026-11-11.
- **L-726. An answer to "was that stock boot a fallback?" is read for what it flashed and for the rule it restates.** #436's reply said the factory images were flashed to slot B, and its NOTES concluded "no fresh backup was needed" because no radio work followed; CONTRIBUTING §3.3 asks for the backup after any stock boot, and a factory flash resets the slot metadata the PR's devinfo evidence is about. *Check:* grep the new text for "not needed", "no backup" and "flashed", compare it with §3.3, and ask which command ran, what each slot holds now, and whether the evidence was read before or after. Extends L-486, L-562 and L-168. *From:* #436, round 51, 2026-11-11.
- **L-725. A test script that sleeps past inhibitors checks the guard it bypasses at every cycle, not once at its start.** #659's sleep series refused to start with the modem up, then ran `systemctl suspend -i` for hours, past every block inhibitor, the modem's included if it started later. *Check:* grep bring-up scripts for `suspend -i`, `--ignore-inhibitors` and `--check-inhibitors`; for each, find where the modem (and any other blocker AGENTS names) is checked relative to the loop. Extends L-458 and AGENTS "Suspend with the modem on". *From:* #659, round 51, 2026-11-11.
- **L-700. An installer value added for one bootloader's gap is gated by that
  device's descriptor.** #616's `--bootloader-slots-match unreported` replaced
  a hard refusal ("the phone reports no version-bootloader") for every device.
  *Check:* run each new accepted value of a safety flag against the
  cheetah-shaped fixture and expect a refusal. Extends L-87 and L-458.
  *From:* #616, round 50.
- **L-699. A phone-side tool that takes `--device` and then writes checks the
  phone's own identity first.** `mark-slot-b` checked only the slot suffix,
  which every phone has, before making a disk node on whatever
  `tools/phone-ssh` reached. *Check:* find the compare of the first string of
  `/proc/device-tree/compatible` with the descriptor's `COMPATIBLE` before the
  tool's first `mknod`, write or register read. Extends L-13 and L-5. *From:*
  #616, round 50.
- **L-698. A rollback for a corrupted partition table is checked against where
  the bootloader and the rescue live.** #616's began "boot the rescue on slot
  A", with `boot_a` (and probably `abl`) on the LUN whose table would be
  invalid. *Check:* for each way back in a GPT or bootloader-data write, name
  the partitions it needs and their LUN; if they sit behind the thing being
  written, the way back is the vendor's download mode, and the owner's
  acceptance says so. Extends L-605 and L-135. *From:* #616, round 50.
- **L-697. A partition-table writer is reviewed as a whole-disk writer for
  everything else on that LUN.** #616's `tools/mark-slot-b` makes a block node
  for `sde` under `/run`; "`/dev/sde` is never recreated" was true of the path
  only, and `sde` is the firmware LUN with 72 partitions. *Check:* grep a
  write tool for `mknod`, `/sys/block/*/dev` and `blockdev`; list the LUN's
  other partitions by `PARTNAME`; ask that the exception's text name the node
  and what it reaches, and that the payload is staged and hashed on the phone
  before `dd`. Extends L-285 and L-601. *From:* #616, round 50.
- **L-696. A boot-pending marker is checked for who clears it on each exit,
  and for what else can stop the boot after it is written.** #562 writes its
  marker before the final guard check, so a guard stop reads next boot as a
  failed SSH, and a held boot never clears it, so every later boot stays in
  RAM. *Check:* list every `return 1` between the marker's write and
  `switch_root` in `initramfs/init`, and say what the next boot prints and
  does for each. Extends L-613 and L-170. *From:* #562, round 50.
- **L-695. A live-switch path added beside a "verify, then unmute" start keeps
  that order.** #626's `set_output` unmuted in a `finally` after unverified
  mixer writes, where `tegu_enter` refuses to unmute on a read-back mismatch,
  and a configured earpiece start unmuted on the loudspeaker first. *Check:*
  wrap the fixture's mixer to record the order of mute and gain writes for
  each entry (a start with each configured value, a switch, a switch whose
  write fails) and compare with the start path's rule. Extends L-162 and
  L-419. *From:* #626, round 50.
- **L-694. A rule that asks for the owner's yes before each run is not met by
  a standing word.** #601's five 9a sleep boots with the modem up ran on
  permission to "keep working through the night", the owner asleep; the record
  said only "on the charger" until round 49 asked who was there. *Check:*
  where a rule names per-run consent or attendance, ask who was at the phone,
  grep the record for "standing", "overnight", "kept working" and "away", and
  report a breach to the maintainer apart from the diff's verdict. Extends
  L-445 and L-109. *From:* #601, round 50.
- **L-664. A PR that turns a protected write off ships a test that it stays
  off, and a "must refuse" test is run against the accepting build.**
  `omamobile-bootctl`'s dry run exits 1 whether the layout is accepted or
  refused, so #436's "refuses 3.14" test passed on a build that accepted 3.14;
  and with the `-D` gone from `build`, its only 3.11 test still built the
  enabled variant. *Check:* build or fake the accepting variant and run the
  test's own command on it; ask for a match on the refusal message, and for
  the shipped binary against the newly refused input. Extends L-598 and L-454.
  *From:* #436, round 49, 2026-11-10.
- **L-663. A results section or run-table row says under which attended rule
  it ran, and it is read against the rule every round, not only when AGENTS.md
  changes.** #601 recorded 25 sleeps past the modem's inhibitor with no word
  on attendance; #409 recorded "Attended: no" for the first run of a new
  kernel under a legend saying every first run was watched, and a diff of
  AGENTS.md showed nothing. *Check:* `grep -n -i 'attended\|owner'` in each
  new section; for each new row, is the kernel, module or script new since its
  last attended row? Extends L-445 and L-109. *From:* #601 and #409, round 49,
  2026-11-10.
- **L-662. An exception clause in a tightening rule is read as a
  permission.** #601's "never … outside a test that ends in a reboot" licensed
  that test on every phone the bullet covers, the reference phone it opens
  with included. *Check:* for each "except", "outside" or "unless" a PR adds
  to AGENTS.md, name who may use the exception and on which phone. Extends
  L-224 and L-284. *From:* #601, round 49, 2026-11-10.
- **L-661. A rule that forbids passing a guard is written on the effect and
  names every path round it.** #601's AGENTS line forbade `systemctl suspend
  -i`, while `rtcwake -m` and a write to `/sys/power/state` skip sleep
  inhibitors entirely, as `omamobile-sleep`'s header on main says. *Check:*
  for a new "never pass X" line, `git grep` the guard's name and the mechanism
  (`/sys/power/state`, `rtcwake`, `--ignore-inhibitors`) for other ways past
  it. Extends L-297. *From:* #601, round 49, 2026-11-10.
- **L-660. "Writes nothing to storage" in a rule or a prompt is checked
  against where the bootloader keeps the state, and a slot-flag change is
  walked for both slots.** On our Pixels the slot flags live in `devinfo`, so
  `fastboot --set-active` is a `devinfo` write by the bootloader; #639's rule
  also named only slot B's mark, while its last `--set-active` is on stock's
  slot. *Check:* grep RELEASES and the device notes for where the flag is
  stored, write "flashes and erases nothing", and list both slots' flags after
  each `--set-active` and what next marks each. Extends L-36, L-261 and L-363.
  *From:* #639, round 49, 2026-11-10.
