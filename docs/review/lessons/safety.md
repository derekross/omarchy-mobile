<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Safety model (AGENTS.md section 1) (part 1 of 3)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-1108. A stop rule that says "before the next boot, mask X" is walked for
  the hang case, where nobody can type before that boot.** #929's section 6
  lists "a reboot or a hang" among its stops and then prescribes a mask; that
  works for the stages that run with the unit already masked, and not for the
  one where the unit starts at boot. *Check:* for each stop condition that
  includes a hang or a reset, name the stage in which the guarded unit is
  boot-started, and ask what the following boot does there: a hang marker, or
  the unit kept out of the boot for the first run. Extends L-830, L-1076 and
  L-170. *From:* #929, round 65, 2026-11-21.
- **L-1093. A plan that keeps the boot partition read-only on the phone is
  walked through a package update of the kernel.** #964's host-only boot
  writer leaves a pacman transaction able to replace the modules of the kernel
  that is still in `boot`. *Check:* for any design where the kernel image and
  its modules are written by different actors, list what each update leaves on
  disk between the two writes and what the next start finds; ask what holds
  the kernel package and where the previous modules stay. Extends L-415 and
  L-308. *From:* #964, round 64, 2026-11-21.
- **L-1092. A single-slot install plan is read for a verification step that
  fastboot cannot perform.** #964 asked its installer to "read back and hash
  the complete `boot` partition" before rebooting; fastboot has no partition
  read on that bootloader, and the same author's record on #714 could only
  hash through a later Linux boot. *Check:* for every "read back", "verify" or
  "hash" in a plan's fastboot stage, name the command (`fastboot fetch` exists
  only in fastbootd); if there is none, the plan gets a RAM boot of a guarded
  image as its own step, with `boot` read-only and a stop condition. Extends
  L-856 and L-226. *From:* #964, round 64, 2026-11-21.
- **L-1091. A "restore the backup image" step is asked what that image boots,
  and into what.** #714's documented way back writes a saved `boot` image
  which, by the same notes, started an older install with a writable main disk
  and whose kernel was never identified; #964 calls it the "stock boot image".
  *Check:* for every restore step in a single-slot plan, find the notes entry
  that identifies the image (kernel string, ramdisk, whether the storage guard
  is in it) and the root it expects on `userdata` after the planned writes;
  "restores the previous state" is not automatically "safe". Extends L-698,
  L-186 and L-205. *From:* #714 with #964, round 64, 2026-11-21.
- **L-1083. A loss of the USB link at the last boot try needs its own line in
  a runbook.** On Tensor phones an unplug ends the link until a Type-C driver
  owns the charger chip (AGENTS "USB"), so the owner's natural next step is a
  reboot, which is the boot the retry rule forbids. *Check:* where a runbook
  has a "no reboot at one try" rule, look for what it tells the owner to do
  when SSH is gone at that point; if nothing, ask for the buttons-to-fastboot
  path. Extends L-284 and L-318. *From:* #821, round 63, 2026-11-20.
- **L-1082. A recovery record's slot table is read row by row against the
  plan's own stop rules and the last ruling on the device's issue.** #821's
  table showed slot B going from one try to zero across "the owner's
  reboot", while the same plan's step 6 said "No further reboot at B1" and
  the ruling on #252 asked for a known-good flash before the boot that uses
  the last try; the prose called it a reboot and nothing more. *Check:* for
  each row where a retry count drops, name the boot that spent it and what
  was flashed before it, then `grep -n -i 'reboot\|retry\|last try'` the
  plan's runbook and the device issue's latest maintainer comment for the
  rule that boot fell under. Extends L-663, L-445 and L-756. *From:* #821,
  round 63, 2026-11-20.
- **L-1077. A regmap debugfs read in a plan is cleared by the map's read
  table, not by the word "read-only".** For #929's S2 the S2MPG15 `pmic`
  regmap lists seven LDO control registers, so the file can't reach an
  interrupt or status register. *Check:* `git grep -n 'rd_table' <mfd
  driver>` for the map the plan names, list its ranges, and say in the review
  what the file can show. Extends L-25. *From:* #929, round 63, 2026-11-20.
- **L-1076. A plan's "disable the unit before the next boot" is checked
  against where the unit's wants link lives.** #929's stop rule used
  `systemctl disable` on `omamobile-sensor-proxy`, which the package enables
  with a link under `/usr/lib/systemd/system/multi-user.target.wants/`;
  `disable` leaves that link, so the failed step would repeat at the next
  boot. *Check:* for every `systemctl disable <unit>` in a runbook's stop or
  rollback, `git grep -n '<unit>' origin/main -- 'packages/*/install'
  'packages/*/vendor/systemd'` for a packaged wants link, and ask for `mask`.
  Extends L-607 and L-754. *From:* #929, round 63, 2026-11-20.
- **L-1061. Notes that say "the owner authorized, so backups and the way back
  are not gates" are checked for radio, PMIC or Trusty work after that
  sentence, and for the descriptor key the backup tool needs.** #914's notes
  waived backups, then powered a PCIe Wi-Fi host and loaded an out-of-tree
  driver, with stock boots in between; its descriptor had no `NV_PARTS`, so
  `tools/nv-backup` could not have run. *Check:* `grep -n -i
  'backup\|recovery\|not .*gate' device/<x>/*.md`, `grep NV_PARTS
  device/<x>/device.conf`, then list the §3.3 subsystems the record touches
  after the waiver; ask for the backup now, labelled with what preceded it
  (L-198). Extends L-359, L-486 and L-168. *From:* #914, round 63,
  2026-11-20.
- **L-1060. A descriptor's `DTB_OVERLAYS` is read as "what every builder of
  this device gets enabled", so a test overlay in it is a default.** #914's
  list included a Wi-Fi host test overlay (a PCIe function with vendor
  firmware and a `shared-dma-pool`), which made the L-777 decision by default
  for the model; `tests/device-overlays` checks only that each name exists
  and compiles. *Check:* for each name in a new or changed `DTB_OVERLAYS`,
  list the nodes the overlay sets to `okay`, and for each DMA master say
  what confines it; a descriptor whose own header says "temporary" or "do
  not commit" is a finding by itself (`grep -n -i 'temporary\|do not
  commit\|test' device/<x>/device.conf`). Extends L-777, L-49 and L-679.
  *From:* #914, round 63, 2026-11-20.
- **L-1053. A program that runs only on a first boot with no account can't be
  tested through its unit on a development phone, so its runbook reproduces
  the unit's sandbox by hand, and the review asks for that run by name.**
  #771's unit is conditioned on no first-boot `done`; its runbook's `--demo`
  alone would pass with a sandbox that later refuses the DRM device.
  *Check:* for a unit with `Condition*=!<a file every used phone has>`, find
  the runbook line that runs the binary under the unit's own properties
  (`systemd-run -p ...` copied from the unit), and list the `DeviceAllow=`
  and capability lines it must prove. Extends L-320 and L-754. *From:* #771,
  round 63, 2026-11-20.
- **L-1048. Two changes to one boot-time guard that are each "waiting for the
  7 Pro" are sequenced explicitly, the merged one first.** Main's
  running-slot allowlist and #484's boot-LUN guard were both unbooted, and an
  image from the PR carries both, against one change per boot. *Check:* for
  a PR whose phone run changes `initramfs/init`, `git log <last booted
  image's commit>..origin/main -- initramfs/init`, and name each unbooted
  change and its own runbook. Extends L-173 and CONTRIBUTING §3.6. *From:*
  #484, round 63, 2026-11-20.
- **L-1047. A runbook written before a safety rule is re-read against AGENTS
  when the PR is revived, command by command.** #484's plan of 11-07 pushes
  and `reboot-to`s the 7 Pro with the modem up; the stop-the-modem rule is
  from 11-08, and a newer plan in the same tree already has it. *Check:* `git
  log --since=<plan date> -- AGENTS.md`, then grep the runbook for `push`,
  `reboot-to`, `flash` and each version number it expects. Extends L-250,
  L-564 and L-723. *From:* #484, round 63, 2026-11-20.
- **L-1044. Two holds on one device are walked together.** "No `devinfo`
  write" and "R2 stops before `--set-active=b`" each read as safe; together,
  after one bad flash, they leave the owner's phone on stock until the
  maintainer answers. *Check:* for every pair of holds on one device, walk
  the owner's most likely failure through both, and say in the comment how
  long the answer will take. Extends L-284 and L-451. *From:* #203, round 63,
  2026-11-20.
- **L-1030. A change to the storage guard is shown neutral on the reference
  phone by running the base's and the head's guard on one fake phone and
  diffing nodes, flags and log, case by case.** The head's own test can't
  show it, because its closed-case assertions changed with the code. For
  #919 a six-case table (three valid, three closed) answered "what does a 7
  Pro see" in a minute and went into the squash body. *Check:* extract
  `ufs_ro_log` to `ufs_ro_pass` from both inits as `tests/storage-guard`
  does, run each on the same fake sysfs with cheetah's packed list on slot
  B, slot A and no slot, then with no file, an empty file and a forbidden
  name, and `diff` the `ro` files, the `/dev` listing and kmsg. Extends L-173
  and L-8. *From:* #919, round 63, 2026-11-20.
- **L-1029. When a PR lets a boot method through `load_device`, the review
  tabulates every `cmd_*` that calls it and removes each new refusal once.**
  #918's five `die` lines are each one edit away from a write path; taking
  them out one at a time showed the test names every one (and, for
  `fastboot`, printed the crash line the guard exists to stop). *Check:* `awk
  '/^cmd_[a-z_]+\(\)/{fn=$1} /load_device/{print fn}' bin/omamobile`, then
  one mutation per refusal, and the test's `not ok` line read for its name.
  Extends L-322 and L-742. *From:* #918, round 63, 2026-11-20.
- **L-1025. A notes sentence that says a hold "remains" is checked against
  sections of the same day.** #714 said "NFS remains paused" three times
  under one date and recorded two NFS boots under the same date. *Check:*
  `grep -n -i 'remains paused\|still paused\|not resumed' <notes>` and read
  every same-dated or later-dated section for the act. Extends L-445 and
  L-663. *From:* #714, round 63, 2026-11-20.
- **L-1024. When a contributor asks "would X be acceptable?" about a write,
  the next round reads the notes for X in the past tense before anything
  else.** #714's question about replacing a phone's `boot` partition went
  unanswered; a commit nine hours later recorded the flash, the thread never
  said so, and a second question (resuming NFS boots) was followed by the
  boots within seven hours. *Check:* for every open "does this satisfy / may
  I" in a thread, `git log --since=<its time> --format='%cI %s'` on the PR
  and grep the notes for the verb (`flashed`, `booted`, `resumed`); lay the
  times in UTC beside the maintainer's last comment; and answer quickly,
  because an unanswered question ages into a decision. Extends L-557, L-694
  and L-486. *From:* #714, round 63, 2026-11-20.
- **L-1018. A request that makes a modem write its own NV is treated like a
  Linux write to NV: the code that sends it checks the partitions are
  read-only itself.** #933's `ENGINE_UNLOCK` relied on another package's
  `rmtfs -r`. *Check:* grep a Qualcomm port for QMI or AT requests that set
  modem state (`SET_`, `--dms-`, `--nas-set`, `--loc-set`), and for each find
  the `ro` check by `PARTNAME` before it. Extends L-458 and the AGENTS NV
  rule. *From:* #933, round 63, 2026-11-20.
- **L-1013. An experiment that leaves hardware in a hand-set state holds a
  sleep inhibitor, and a default-on auto-sleep makes that a rule.** #926's
  twelve switched-off power domains went through an unplanned 42-minute
  auto-sleep that was first taken for a hang. *Check:* for a runbook or
  README that changes a rail, domain or clock by hand, look for
  `systemd-inhibit --what=sleep --mode=block` (or the auto-sleep toggle off)
  before the first change on a phone whose package ships
  `auto-sleep-default`. Extends L-746. *From:* #926 with #912, round 63,
  2026-11-20.
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
