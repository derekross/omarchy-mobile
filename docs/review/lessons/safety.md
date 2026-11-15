<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Safety model (AGENTS.md section 1) (part 1 of 3)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
- **L-659. A default-on descriptor key for a phone-changing step reaches every
  descriptor the tool accepts, and a guarded phone may be kept out only by an
  unrelated refusal.** #639's `BOOTLOADER_SLOT_PROBE` default covered ten
  devices; the 9a was out only because its descriptor has no `SOC_*` key.
  *Check:* run the tool's early refusals (`BOOT_METHOD`,
  `SOC_IDS`/`SOC_COMPATIBLE`) over `device/*/device.conf`, list who passes,
  name for each phone with an "ask first" rule the refusal that keeps it out,
  and prefer opt-in after an attended run. Extends L-44, L-444 and L-601.
  *From:* #639, round 49, 2026-11-10.
- **L-658. A check that measures a hazard by doing the hazardous thing is
  reviewed as that thing.** #639's installer read the other slot's bootloader
  version by setting that slot active and restarting into its bootloader, the
  event the "slots must match" check exists to prevent; Google's factory
  images page warns of an unbootable state for an older bootloader in the
  inactive slot (Pixel 6 and 8 families). *Check:* for any "measure X by
  switching to it", write down what the guard protects against and whether the
  measurement triggers it, and read Google's warnings for the device's family.
  Extends L-3 and L-284. *From:* #639, round 49, 2026-11-10.
- **L-324. A review reads the PR thread for identifiers, not only the diff.**
  A contributor's evidence comments on kernel #98 quoted `bluetoothctl show`
  with the phone's public Bluetooth address twice, and `tools/pr-check` sees
  commits only. *Check:* every round, run the MAC pattern
  (`[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}`) and the serial and IMEI patterns over
  `gh pr view N --json comments,reviews` and the inline review comments, and
  ask for an edit. Extends L-29; see C-22. *From:* kernel #98, round 29.
- **L-323. A device that drops its forked init for the shared one also changes
  its `INITRAMFS_INIT` to an absolute value.** A value without a leading `/`
  is relative to `device/<codename>/`, so #111's unchanged `initramfs/init`
  pointed at the file the same push deleted; `tests/boot-method` passed
  because `images` stops at "build the kernel first" before the initramfs.
  *Check:* `grep INITRAMFS_INIT device/<x>/device.conf`, then `git cat-file -e
  <head>:device/<x>/<value>`, or run `bin/omamobile initramfs` with a scratch
  `KERNEL_OUT` (it dies at the init check before any download). Extends L-134.
  *From:* #111, round 29.
- **L-322. Accepting a new `BOOT_METHOD` in `bin/omamobile` opens `flash` and
  `push` too, and `flash` switches the slot.** On Qualcomm A/B, `fastboot
  --set-active` hands slot state to ABL, which (as we understand it) resets
  the successful flag; with the GPT mark allowed only by hand under a §3.1
  entry, `flash` forces the next GPT write or a fallback. *Check:* for a new
  method, list what each of `images`, `flash` and `push` does on that
  bootloader, and refuse the ones whose follow-up isn't approved. Extends
  L-284. *From:* #111, round 29.
- **L-321. "The shared init covers this device" is checked against the LUNs on
  any non-Pixel UFS.** `initramfs/init` leaves allowlisted partitions writable
  only on `sda`, `boot_arch` finds `userdata` only there, and `cmd_push` finds
  slot B's images only there. Pixels keep them on LUN 0; multi-LUN Qualcomm
  layouts may not. The no-USB-host `sysrq c` fallback is a Tensor-era
  assumption too. *Check:* ask for the read-only `PARTNAME` to `sdX` map of
  every `UFS_RW` entry from sysfs before accepting "push updates `boot_b`",
  and ask what a panic does on that bootloader. Extends L-1 and L-232. *From:*
  #111, round 29.
- **L-320. A one-boot helper a PR adds needs install, enable and removal steps
  in its runbook.** #136's H5 created the early read's marker, but no step
  installed or enabled the unit, so the run's main reading would silently not
  happen. *Check:* for each script or unit a PR adds under `device/<x>/`, find
  the runbook line that copies it and runs `systemctl enable`, and the one
  that undoes it. *From:* #136, round 29.
- **L-319. A meter check or stop rule written for one reset applies to every
  reset that reaches the same state.** #136's "VBUS still up two minutes after
  the reset" was attached to H5's planned `echo b`, but H4's swap timer and a
  forced restart with the drive attached are the same crash with host mode on.
  *Check:* for each stop rule that depends on hardware state, list the other
  ways the runbook can reach that state (timers, dead-man, forced restart) and
  state the rule once, at the top. Extends L-296 and L-133. *From:* #136,
  round 29.
