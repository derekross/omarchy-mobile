<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Safety model (AGENTS.md section 1) (part 1 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-1200. A "microphone off" switch built on device-node permissions is
  checked against the root daemons that open the same PCM.** #1066 locks every
  capture PCM away from the session, while the 7 Pro's phone service, running
  as root, opens the AoC capture PCM itself for every call, so a call with the
  switch "off" still carries the microphone. *Check:* `git grep -n
  'snd_pcm_open\|hw:{\|arecord\|CapturePCM' origin/main -- packages` outside
  the session's own audio, and for each hit read the unit's `User=`; a root
  holder is either made to honour the switch or named in the switch's text.
  Extends L-1128 and L-608. *From:* #1066, round 69, 2026-11-26.
- **L-1199. A privacy fix that keeps the old source as a fallback is read for
  when the fallback runs and what it gives with no input.** #1073's Bluetooth
  address used `systemd-id128` as asked, but fell back to `sha256` of the
  serial, and of the empty string when there is none, which gives every such
  device one address. *Check:* for each `|| fallback` around an identifier,
  run the fallback with its input absent and print the result. Extends L-563.
  *From:* #1073, round 69.
- **L-1198. A fetch tool's docstring that says "verifying" is read against the
  code before a PR adds a security component through it.**
  `tools/alpine-fetch.py` says "verifying checksums" and compares sizes only,
  with the index's signature unread; #1103 would bring cryptsetup, the program
  the disk PIN goes into, through it. *Check:* for every new package a PR adds
  to an existing fetch, `grep -n 'sha\|sign\|verify\|gpg\|SIGN' <fetcher>` and
  say what the downloaded bytes are compared with (a pinned hash, a signed
  index, a size, nothing). Extends L-632 and L-895. *From:* #1103, round 69.
- **L-1197. A marker that a later change will read as "the owner proved who
  they are" lands with its reader, not before.** #1103's init writes
  `/run/omamobile/disk-unlocked` for a lock skip that is still decision PD3.
  *Check:* `git grep` each new `/run` or `/var/lib` marker in the head for its
  readers; a security marker with none is asked out until the reader comes.
  Extends L-1017. *From:* #1103, round 69.
- **L-1196. Before mutating away a refusal that stands in front of phone I/O,
  read which phone tools the test puts first on `PATH`, and run the mutation
  under `timeout -s KILL`.** Removing `cmd_fastboot`'s `qcom-abl-v2` refusal
  sent #1102's test into `fastboot`'s `adb get-state` loop;
  `tests/boot-method` stubs `adb`, `fastboot`, `ssh` and `docker` in `$t/bin`,
  so nothing reached the Pixel 7 Pro on the review machine's cable, but only
  because of the stubs, and the run hung rather than failed. *Check:* `grep -n
  'for cmd in .*adb\|PATH=' <test>` before the mutation; if a phone tool is
  not stubbed, don't run it. Extends L-963 and L-1029. *From:* #1102, round
  69.
- **L-1195. A device PR that carries a writer the maintainer has put on hold
  is asked what merges of it, not only what runs.** #931's hold covers running
  `slot-a-mark write` and `restore`; the merge itself would ship the GPT
  writer to main with no §3.1 entry. *Check:* for each hold on a write, `git
  grep -n '<the tool>' <head>` and ask whether the writing verbs are in what
  merges; prefer the read-only verbs now and the writer with its entry.
  Extends L-224 and L-284. *From:* #931, round 69.
- **L-1194. A kexec flow that sets `androidboot.slot_suffix` by hand opens the
  storage guard's slot B allowlist without slot B having booted.** #1099's
  boot 3 did so to `dd` slot B's images from a kexec'd initramfs. *Check:*
  grep a bring-up record for `slot_suffix=` on a hand-written command line,
  and name the writer it enabled; a flow the tools can't serve is a tool
  request, not a precedent. Extends L-82 and L-89. *From:* #1099, round 69,
  2026-11-26.
- **L-1193. A device PR's "before step 2" prep is read for a write to a
  partition our rules forbid, however it is worded.** #1099 recorded `fastboot
  --slot=b flash bootloader` as the step that made the slots' bootloaders
  match, "with the owner's yes", in the results of a first light; CONTRIBUTING
  §3.1 forbids exactly that fix and gives the OTA-twice path. *Check:* `grep
  -n -i 'fastboot .*flash\|--slot\|flash bootloader\|flash radio\|flashing'
  device/<x>/*.md` on every new device PR, and for each target that isn't slot
  B's boot images or `userdata` through the installer, report it apart from
  the verdict as a §3.1 event. Extends L-359 and L-2. *From:* #1099, round 69,
  2026-11-26.
- **L-1192. A device package's storage rule is diffed against the reference
  phone's for mode, not only for presence.** #1073 had a
  `10-omamobile-storage.rules` (L-1120's file check passes) whose
  `MODE="0440"` left the whole eMMC readable by group `disk`, where cheetah's
  whole-disk rule is `0000`, and whose `SUBSYSTEM=="block"` can't reach the
  eMMC's RPMB node (`mmc_rpmb`). *Check:* `diff` the new rule with
  `packages/omamobile-device-cheetah/vendor/udev/rules.d/10-omamobile-storage.rules`,
  read each `MODE=` and `UDISKS_IGNORE`, and list the device's protected nodes
  that are not block devices. Extends L-1120. *From:* #1073, round 69.
- **L-1191. A new device's storage-guard work is searched for a twin across
  every open device and guard PR, not only the device's own, because each new
  SoC family brings its own copy and a split-out fix can restate an older
  one.** #1072 (eMMC for a MediaTek tablet) and #1070 (eMMC for the Pixel 3a)
  arrived two hours apart and rewrite the same three functions differently;
  #1074 restates #919's fix with one difference (the node), a week after #919
  was reviewed as ready, and neither mentions the other. *Check:* `gh pr list
  --state open --json number,files` filtered to `initramfs/init` (and
  `--search "initramfs in:title"` for the older ones), `git diff
  origin/main...<head> -- initramfs/init | grep '^+.*mmcblk\|^+.*nvme'` on
  each, then the L-1030 base-versus-head run for each twin on the same fake;
  name the twin in both reviews and say which cells differ. Extends L-923,
  L-720 and L-1031. *From:* #1072 with #1070, and #1074 with #919, round 69.
- **L-1190. A storage-guard extension for a new bus is probed with the device
  at the index the code doesn't name.** #1072 guarded `mmcblk0` by name;
  mainline takes the number from the DT `mmc` alias or probe order, so an eMMC
  at `mmcblk1` (no alias, or a microSD host first) was entirely writable and
  the hand-over check reported nothing, while the suite passed. *Check:* for
  any new disk family in `ufs_ro_pass`, run the head's guard on a fake with
  the internal device at index 1 and a removable one at 0, plus every
  sub-device the driver creates (`boot0/1`, `gp0-3`, `rpmb`); the internal
  device must end read-only or allowlisted, and `ufs_unguarded` must name
  anything left writable. Extends L-1030 and L-321. *From:* #1072, round 69.
- **L-1188. A plan that ends every trial with a stock boot makes its backup
  older than the next trial by construction.** #1002's backup was taken in a
  rescue; v40 and v41 each followed a return to stock on slot A, and a stock
  boot rewrites `efs`, `persist` and `modem_userdata`. *Check:* for a bring-up
  plan whose return step boots stock, list each trial with the stock boot
  before it, and ask which backup or `tools/nv-backup --check` covers the
  PMIC, CPM or radio work in it. Extends L-168 and L-1061. *From:* #1002,
  round 68, 2026-11-25.
- **L-1187. A device draft's commits are checked for shared paths every round,
  because a bring-up branch can pick up a guard change on the way.** #1002's
  round-68 head gained `initramfs/init` and `tools/nv-backup` commits under
  device-sounding subjects, while the phone ran neither (its rescue used a
  stock kernel and a device ramdisk). *Check:* `git diff --stat
  origin/main...<head> -- bin tools initramfs rootfs tests packages AGENTS.md
  CONTRIBUTING.md` at the start of each round, and for each hit ask whether
  the record's boots ran that file. Extends L-1121 and L-1156. *From:* #1002,
  round 68, 2026-11-25.
- **L-1186. A bind mount added to a vendor chroot is judged by what every
  process in the chroot can then open, not only by what our helper needs.**
  #1055 bound the host's whole `/dev/input` read-only so the bridge could find
  a rebound touchscreen; read-only still lets Google's HAL and storage proxy
  read every key and keyboard. *Check:* `git diff origin/main...<head> --
  'packages/*/lib/*chroot*' | grep '^+.*bind '`, list for each new bind the
  device nodes it exposes and the processes the runner starts in that root,
  and offer the narrowest node the helper needs, bound by the host-side
  runner. Extends L-571 and L-1126. *From:* #1055, round 68, 2026-11-25.
- **L-1185. A package step that turns on an upstream unit "as upstream's first
  run does" is read for the safety condition in that unit's own comment, and
  the condition is checked on a phone.** #1054 enables Omarchy's
  `bt-agent.service`, whose comment calls auto-accepting pairings safe because
  the adapter is pairable only while Omarchy's panel scans; the PR's own
  reading on a 9a was `Pairable: yes`. *Check:* `bsdtar -xOf` the signed
  package's unit, list each "safe because" clause, and ask for the read-only
  state that tests it (here `bluetoothctl show | grep -E
  'Pairable|Discoverable'`, never the full output, which holds the address) on
  the reference phone. Extends L-1166 and L-1126. *From:* #1054, round 68,
  2026-11-25.
- **L-1162. A driver that starts writing a PMIC function's shadow registers is
  checked against the vendor's load for any command that commits them to
  non-volatile memory, and the write table is compared with the vendor's list
  register by register.** Kernel #294 turned the 9a's read-only gauge driver
  into a model loader at the chip's second address; reading Google's
  `max77779_update_custom_parameters()` beside the PR's `max77779_nvm_reg()`
  showed the same 21 shadow registers, at the addresses Google's
  `max77779_v20240115_regs.h` gives, and no NV-copy command, which is what
  makes "writes only shadow registers" true rather than assumed. *Check:*
  `grep -n 'COMMAND\|CMD\|COPY\|0xe904\|_nv' <vendor file>` and list every
  register the vendor writes at the second address against the PR's
  `writeable_reg`; any extra register or a commit command goes to the
  maintainer as a write to non-volatile memory. Extends L-2, L-163 and L-542.
  *From:* kernel #294, round 67, 2026-11-24.
- **L-1161. A new early branch in `cmd_flash` or `cmd_push` is listed against
  every check the normal path runs before its first write.** #1002's
  `--stage-only` returns before `load_device`, so `BOOT_METHOD`'s refusals,
  `check_avb_image_sizes`, `in_fastboot` and `slot_b_allowed` don't run, with
  a device script's own checks in their place. *Check:* `awk '/^cmd_flash\(\)
  \{/,/^}/' bin/omamobile`, list each `die` or check above the first `fastboot
  … flash`, and mark which ones the new branch reaches; a branch that sources
  a file under `device/` is a device path in a shared tool. Extends L-1029 and
  L-1121. *From:* #1002, round 67, 2026-11-24.
- **L-1160. A generated list of people in a shipped app is read for the
  guesses that made it, not only for emails.** #1030's credits generator kept
  emails out and printed its guesses, but one of them links a commit name to a
  GitHub login by matching letters alone, and the result goes to every phone.
  *Check:* for a PR that adds contributor names to a package, read the
  generator for every rule that joins two identities, name the data behind
  each (GitHub's email-to-login mapping is data, a spelling match is not), and
  put "ship it, and how" to the maintainer under the privacy rule. Extends
  L-563 and L-324. *From:* #1030, round 67, 2026-11-24.
- **L-1126. A polkit rule copied from an accepted one is judged by what its
  action does when a process outside the page starts it, not by the
  precedent.** #1009's firewall rule has the shape of main's charge-limit
  rule, but where that one moves a battery threshold, this one turns the
  phone's inbound filter off, silently and across reboots, for any process in
  the session; the page's confirm dialog doesn't count, since the rule
  bypasses it. *Check:* for each new `polkit.Result.YES`, write down what the
  unit does with each allowed instance, whether it lowers a security default,
  whether it persists, and whether anything tells the user. Extends L-171 and
  L-285. *From:* #1009 and #1015, round 66, 2026-11-23.
- **L-1125. A device PR that fills an empty `DTB_OVERLAYS` is read overlay by
  overlay for which ones its title names.** #1005's title is "the AoC's sound
  and sensors", and three of its six overlays (fingerprint, Trusty, torch),
  plus a package in `ROOTFS_PACKAGES`, turn other subsystems on by default,
  one of them an RPMB writer at first start. *Check:* `git diff origin/main
  <head> -- device/<x>/device.conf | grep
  '^+.*\(DTB_OVERLAYS\|ROOTFS_PACKAGES\)'`, list each added name with the
  subsystem it enables and whether the title or a commit subject names it;
  anything unnamed goes to the maintainer as its own default-on decision.
  Extends L-1060, L-137 and L-340. *From:* #1005, round 66, 2026-11-23.
- **L-1124. A plan's "first UFS probe" is read for the one write mainline's
  UFS core makes to the device on its own: `bRefClkFreq`.**
  `ufshcd_set_dev_ref_clk()` (`drivers/ufs/core/ufshcd.c`, before the gear-up)
  reads the attribute and writes it when it differs from the rate of the
  host's `ref_clk` clock in the device tree; the storage guard can't stop a
  query UPIU, and #1002's next step was a first probe with a newly described
  host. *Check:* for a new board's UFS node, name its `ref_clk` rate, compare
  it with stock's (the live DT or the stock driver's log), and put that
  comparison in the runbook's Expect before the first probe. Extends L-1077
  and CONTRIBUTING §3.2. *From:* #1002, round 66, 2026-11-23.
- **L-1123. A record that boots another device's release root image on a new
  phone is checked for what that image's device package does once storage
  appears.** #1002 ran the 7 Pro's 2026.11.15 root as PID 1 on a Pixel 11 Pro
  with no disks; with UFS up, `omamobile-device-cheetah`'s boot-success unit
  would make another phone's `devinfo` and its LUN writable, and write it if
  the layout read 3.15. *Check:* for any "reference root" in a new port's
  notes, list the reference device package's boot-started units (`git ls-tree
  -r origin/main packages/omamobile-device-<ref>/vendor/systemd/system | grep
  wants`) and say which of them write storage. Extends L-567 and L-285.
  *From:* #1002, round 66, 2026-11-23.
- **L-1122. `CONFIG_STRICT_DEVMEM` turned off in a device fragment is a
  security change to the installed system, and the code that wanted it is
  found.** #993's `kernel.config` paired `DEVMEM=y` and no `STRICT_DEVMEM`
  with a userspace program that writes display, PHY and GPIO registers through
  `/dev/mem` at every boot. *Check:* `git grep -n 'DEVMEM\|IO_STRICT_DEVMEM'
  <head> -- 'device/*/kernel.config' kernel/configs`, then `git grep -n
  '/dev/mem' <head>` for its user. Extends L-1012 and L-1039. *From:* #993,
  round 66, 2026-11-23.
- **L-1121. A device's own builder that patches `initramfs/init` by string
  replacement is a fork of the storage guard, and is reviewed as one.** #993's
  `patch-init.py` rewrote the guard loop, the allowlist disk test and
  `boot_arch` for eMMC; its `assert` only proves the anchors still match, and
  `tests/storage-guard` runs the unpatched file. *Check:* `git grep -n
  'initramfs/init' <head> -- tools device` for any tool that copies or edits
  it, list each replaced line by function, and ask for the change in the
  shared init with a test case, under the guard's own review. Extends L-134
  and L-855. *From:* #993, round 66, 2026-11-23.
- **L-1120. A new device package is diffed by file list against its siblings
  on the same SoC, because its own test checks only what it ships.** #914's
  `omamobile-device-komodo` passed its test and every suite while missing
  `10-omamobile-storage.rules`, which all nine device packages on main carry
  and which is the Arch half of CONTRIBUTING §3.2's guard; without it the main
  LUN's whole-disk node was left to udev. *Check:* `comm -13` of the new
  package's and a sibling's `git ls-tree -r --name-only` lists with the
  package directory cut off, and for each file the sibling has and the new one
  lacks, name the rule it serves (storage, sleep, reboot watchdog, boot
  success) or the reason it doesn't apply. Extends L-567, L-207 and L-442.
  *From:* #914, round 66, 2026-11-23.
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
  L-856 and L-226. *From:* #964, round 64, 2026-11-21. (Extended 2026-11-23:
  when a plan is corrected for one such step, every other read in the same
  fastboot stage is checked too; #964's round 64 fix moved the `boot` readback
  into a RAM boot of the rescue, while the same paragraph's new "stop if the
  old root already has that label" still sat in the fastboot install. Grep the
  stage for `label\|hash\|read\|already\|verify` and name the stage and
  command for each. *From:* #964, round 66.)
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
