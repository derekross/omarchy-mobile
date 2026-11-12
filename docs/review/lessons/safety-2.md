<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Safety model (AGENTS.md section 1) (part 2 of 2)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-135. "Can't test on stock" is a §3.1 finding about the contributor's
  phone.** A device without a bootable slot A has no way back. Ask for stock
  back on slot A, and offer a read-only proxy for the test it blocks.
  (Corrected 2026-10-27, C-7: this entry offered a `pd_ignore_unused` boot
  after a warm reset for gs101 power domains; on 7.3 `of_genpd_sync_state()`
  powers the unused domains off regardless, so read each domain's
  `active_time` in `debugfs/pm_genpd/` instead.) *From:* kernel #9, round 12.
- **L-157. A runbook that relies on a watchdog names what arms and feeds
  it.** `s3c2410_wdt` stops ABL's watchdogs at probe and nothing feeds
  `/dev/watchdog0`, so felix's step 8 ("the watchdogs are the reset") had
  nothing to reset a hang. *Check:* a feeder such as `--watchdog`, or the
  button recovery and "run attended" in the step. Extends L-6 and L-133.
  *From:* #35, round 14.
- **L-158. A device package without boot-success makes the slot A fallback
  part of every root-image runbook.** ABL falls back after three unmarked
  boots; stock then offers to reset an Arch `userdata`, and its boot writes
  `efs`/`persist`. *Check:* the runbook says how to get back to B, "decline
  the reset" and "back up after a stock boot". *From:* #42, round 14. **Also
  (#414, round 39):** say what the third boot does on a phone with no
  boot-success marker (the tries run out and stock boots on slot A), and
  when a device's bootloader keeps `VENDOR_CMDLINE`, read that line word by
  word against the DTB bootargs: arguments that were dead text on other
  Pixels (`splash`, `printk.devkmsg=on`, `bootconfig` on akita) take effect.
- **L-159. A storage power test runs where the root isn't on the device
  under test, and reads with `iflag=direct`,** or the page cache answers and
  the device never wakes. *From:* #42, round 14.
- **L-168. A partition compare that differs needs a boot timeline, not a
  new baseline.** #35 took a fresh backup after `efs`, `efs_backup`,
  `modem_userdata` and `persist` differed from the last one, and said the
  compare "does not say which boot changed them". Without a stock Android
  boot in the interval the change came from Linux, and that is a guard
  failure. *Check:* before accepting a new baseline, list every boot between
  the two backups with its slot and install; name the Android boot that
  explains the change, or stop. Extends L-35. *From:* #35, round 20.
- **L-169. A second owner of a device checks every pinned value in its
  descriptor against the first owner's recorded evidence.** #74 replaced the
  `OS_VERSION`/`OS_PATCH_LEVEL` that tegu's notes had verified on one phone's
  slot A with a newer stock build's, and added an AVB rollback index for it;
  the other phone runs the older build. A value verified on one slot A can
  lock the other phone out of its own. *Check:* `git log --
  device/<codename>/device.conf` for the authors, diff each changed value
  against the device's notes, and ask both owners. *From:* #74, round 20.
- **L-170. A device package that loads a PMIC or firmware driver from a boot
  timer needs a hang marker.** #74's `OnBootSec=` timer modprobes ACPM and
  the PMIC at every boot with nothing written first; cheetah's start scripts
  write a marker and skip the step when the previous boot left it behind.
  *Check:* `grep -l 'OnBootSec\|modprobe'
  packages/omamobile-device-*/vendor/systemd/system/* bin/*`, then look for
  the marker in each script. Extends L-6 and L-158. *From:* #74, round 20.
- **L-171. A contributor-key mechanism is judged by where the key can end
  up, not by its paths.** #25 kept keys and outputs out of `keys/` and
  `out/repo` as asked, but rebuilt `omamobile-keyring` with the contributor's
  key in it, so the image's trust list carried a key the real package never
  has; #79 trusts the key only in the build image and leaves the keyring
  package alone. *Check:* grep the diff for writes to `omamobile.gpg`,
  `omamobile-trusted`, `omamobile-revoked` or the keyring package's build
  directory; a contributor key may live in `keys/<codename>/` and the build
  image, nowhere else. Extends L-7. *From:* #25 with #79, round 20.
- **L-205. A stock-restore step for slot A names everything a stock slot A
  is, and takes its backup where it can be read.** #35's step wrote five boot
  images, forbade `vbmeta` and left `super`'s `_a` logical partitions as they
  were, and took the "after stock's first boot" backup before switching back,
  though stock has no root to read `efs`. *Check:* every partition the factory
  image writes for that slot (boot set, `vbmeta*_a`, `super` logical `_a`),
  `-s` on every fastboot command, stock's expected behaviour with a Linux
  `userdata` against its stop condition, and the backup taken from Linux
  after `--set-active=b`. Extends L-2, L-158 and L-198. *From:* #35, round 22.
- **L-442. A guard added only through a device's `ROOTFS_PACKAGES` reaches
  new installs, not updated phones.** #400 put omamobile-audio and its
  amplifier blacklist into raven's image, but device-raven neither depended
  on it nor blacklisted the driver itself, so an updated raven kept the
  unmuted autoload and got a wants link to a unit it didn't have. *Check:*
  for every vendor wants link or guard a device package relies on, find the
  package that ships it in that device package's `depends=`; the image list
  is no upgrade path. *From:* #400, round 39, 2026-11-03.
- **L-443. A shared "verified" stamp is checked for which device and which
  level it verified.** omamobile-audio's c9 accepted a phone's own C9a stamp
  without looking at `SYSTEM`; on raven the stamp was written at stage
  media, and c9 then ran at the 7 Pro's c9 levels, which raven's own R6
  shows the protection firmware misreads. *Check:* for each stage or mode a
  stamp unlocks, name the system and the levels the verification ran at, and
  add a test with another `SYSTEM`. Extends L-162. *From:* #401, round 39,
  2026-11-03.
- **L-444. A guard relaxation gets its first run on the phone where that
  guard was strictest.** #403's reboot note lets the next boot start the
  modem after a `reboot-to` that never powered it off; with #372 that
  includes the 9a, where a second modem start in one boot reset the palmtop.
  *Check:* for each device that reads the new signal, name the run that
  exercised the newly allowed path there, and ask for it before merge.
  Extends L-377. *From:* #403 with #372, round 39, 2026-11-03.
- **L-445. A plan step that relaxes an attended rule is checked against the
  plan's own earlier rules and runbook header, not only AGENTS.** #409
  labelled two 9a sleep series "unattended" 350 lines below the same plan's
  "unattended sleep stays off". Changing that rule is the maintainer's
  decision, not a plan edit. *Check:* `grep -n -i 'attended\|unattended'`
  across the plan and AGENTS for every new step. Extends L-224 and L-339.
  *From:* #409, round 39, 2026-11-03.
- **L-451. Two refusals in one installer are walked together from the
  starting state each one addresses.** #383's "sideload the full OTA twice"
  leaves stock on slot B, which #352 then refuses, and #352's own suggested
  fix (`flash-all` on slot A) writes bootloader and radio, which §3.1
  forbids. *Check:* for each new refusal, follow its suggested fix through
  the installer's other refusals and the safety rules from the state it
  starts in. Extends L-256. *From:* #352 with #383 (commit review), round
  39, 2026-11-03.
- **L-456. A register read added to an unattended series is a first probe,
  however safe the single read was.** #409's HSI2 sysreg read through
  `/dev/mem` passed once after a sleep-free boot, then ran after every wake
  and reset the palmtop twice (the block's clock can be gated after resume).
  *Check:* `git log -p` on a PR's bring-up scripts for `/dev/mem`, `mmap`,
  `devmem` and `debugfs/regmap`, even in commits a later one reverts, and
  ask for one attended read in each new state (after a wake, after a reset)
  before it goes into a loop. Extends L-199. *From:* #409, round 40,
  2026-11-04.
- **L-457. A device PR that edits a file a sibling's test keeps identical
  also edits the reference phone.** #436 widened lynx's devinfo layout
  check, and lynx's `test/all` compares its `omamobile-bootctl.c` with
  cheetah's, so the 7 Pro's copy changed too, and raven's third copy drifted
  silently. *Check:* for every touched file, `git grep -l "<path>"
  packages/*/test/all` and `git ls-tree -r origin/main | grep <basename>`;
  prefer a compile-time or descriptor switch that keeps the shared copy and
  the 7 Pro's binary unchanged. Extends L-8 and L-64. *From:* #436, round
  41, 2026-11-05.
- **L-458. An opt-in that relaxes a safety check is checked against every
  stage it reaches, and the relaxed check keys on what the service did, not
  on the setting.** #427's default-calibration mode left stage c9 reachable
  through a stamp, and its watchdog accepted "calibration not applied"
  whenever the setting was on, also on a phone with a calibration file.
  *Check:* list the stages and modes each relaxing switch can reach, ask for
  an explicit refusal where the relaxed state isn't verified, and have the
  checker read a run-state record. Extends L-161 and L-443. *From:* #427,
  round 41, 2026-11-05.
- **L-459. A file capability is reviewed for secure-execution mode and for
  where it is set.** A capability makes the kernel set `AT_SECURE`, which
  changes how glibc and `secure_getenv` users (sd-bus) read the environment,
  and a capability written inside a rootless build container may be
  namespaced and not count on the phone. *Check:* ask for a session check
  with the capability on, and `getcap` on a phone installed from a freshly
  built image. *From:* #429, round 41, 2026-11-05.
- **L-460. A port to an A/B phone with no stock left is held to the A/B
  rules, not the single-slot ones.** #432 proposed a Linux rescue root on
  slot A as its own exception, after #383 added rules for phones without
  slots. *Check:* `getvar all` lists `_a`/`_b`; if so, §3.1's slot-A rule
  stands, the way forward is stock restored under an approved plan, RAM-only
  until then, and on Qualcomm also the GPT slot-flag entry. Extends L-135,
  L-186, L-224 and L-322. *From:* issue #432, round 41, 2026-11-05.
- **L-486. A docs or roadmap PR is read for safety disclosures, not only for
  status words.** #472's roadmap said in one subordinate clause that the
  contributor's phone marks slot B at every boot with a local unit, a
  `devinfo` write under the #252 hold. *Check:* grep a docs PR's added lines
  for `successful`, `devinfo`, `bootctl`, `setrw`, `local unit`, `by hand` and
  `owner`, and send any hit through L-359. Extends L-267. *From:* #472, round
  42, 2026-11-07.
- **L-487. A guide that tells agents how to drive a phone carries AGENTS'
  shared-phone rules in its prompt.** #463's prompt unlocked, woke and kept
  the phone awake with no "tell the person first". *Check:* grep any doc with
  an agent prompt for the AGENTS §1 verbs (announce, ask, DPMS, reboot) and
  compare. *From:* #463, round 42, 2026-11-07.
- **L-488. A plan's account of a safety deviation is checked against what the
  contributor said in the thread.** #450's "short bursts at 817/8" was
  narrower than the same author's #1 comment (tens of minutes of music, analog
  12 to 17). *Check:* grep the author's comments on the device issue since
  that date and diff the extent (levels, durations, parts). Extends L-435.
  *From:* #450, round 42, 2026-11-07.
- **L-531. An isolation check we suggest never reads the node it makes.**
  Drafting W5's character-side check for #493 nearly suggested `head -c1` on a
  `c 1:1` node, which, if the rule failed, reads physical address 0 through
  `/dev/mem`. *Check:* every suggested proof of a device refusal stops at
  `mknod` or `open` of a harmless device; `/dev/mem`, `/dev/port` and
  register-backed nodes are tested by `mknod` only. Extends AGENTS.md section
  1 and L-454. *From:* #493, round 44 (a near miss in drafting); 2026-11-08.
- **L-532. A measuring tool we name for another phone is read for hard-coded
  register addresses first.** `tools/display-hz` `devmem`-reads cheetah's
  DECON at `0x1c24xxxx`; suggested for a 9a rate-switch check on kernel #212,
  it would have read an unknown zumapro block. *Check:* `grep -n
  'devmem\|0x[0-9a-f]\{8\}' tools/<tool>` before a draft names it for a phone
  that isn't cheetah; name a log line or a compositor query instead. Extends
  L-295 and L-276. *From:* kernel #212, round 44 (a near miss in drafting);
  2026-11-08.
  Again in round 45, the right way round: kernel #212's author counted the
  DECON frame-start interrupt in `/proc/interrupts` under a redrawing terminal
  (120/60/121 per second), read-only and device-neutral; name that (`grep -i
  decon /proc/interrupts` twice, a second apart) when asking another phone for
  a rate.
- **L-533. A lens or OIS controller at the same I2C address as the module's
  calibration EEPROM is a calibration part.** Stock's tegu DT puts
  `eeprom-nessie`, `act-nessie` and `ois-nessie` all at 0x24: the LC898129
  holds the module's calibration. *Check:* grep the device's `*-camera.dtsi`
  for nodes sharing the actuator's `i2c-addr`; if one is an EEPROM, the driver
  writes only the registers it names, and the notes list every register
  written during bring-up. Extends L-90 and L-108. *From:* kernel #213, round
  44, 2026-11-08.
- **L-562. A custom recovery or installer in a contributor's record is a slot
  question first.** Kodiak's notes said a step was "taken from" a third-party
  recovery and sat merged through two rounds; the answer, "installed to
  `vendor_boot` on both slots, may have mounted persist", means slot A was
  written, the fallback recovery is no longer stock's, and the calibration
  backup and slot B's rollback set may not be stock's either. *Check:*
  whenever a third-party recovery, root tool or installer appears, ask which
  partitions on which slots it wrote (`vbmeta` flags included), when relative
  to each backup, and what it mounted; record a slot A write as a §3.1 event
  and downgrade any backup taken under it (L-198). Extends L-186, L-198 and
  L-35. *From:* #511 with #489 and #231, round 45, 2026-11-08.
- **L-563. A locally administered MAC that a PR makes persistent is an
  identifier, and `tools/pr-check` exempts it and reads no commit message or
  PR body.** #510 saves a random address pair per phone, so the contributor's
  example in the body and commit now names their phone to every host it meets.
  *Check:* for a PR that stores generated addresses or IDs, grep the body,
  every commit message and the thread for them (the L-324 pattern without the
  locally-administered exemption), and ask for placeholders and a rotation.
  Extends L-324 and L-145. *From:* #510, round 45, 2026-11-08.
- **L-564. `reboot-to` (and `bin/omamobile push`) stops no unit, so with the
  modem up it leaves `/var/lib/omamobile/modem-up` behind and the next boot
  skips the modem once.** *Check:* a runbook or test plan that reboots a phone
  with the modem up stops it first (`systemctl stop omamobile-modem`; it takes
  about 40 s and ends as "failed" for now, issue #532), or uses `systemctl
  reboot`. To keep the modem off for a boot it is `systemctl mask
  omamobile-modem-boot.target`, not `/etc/omamobile/modem-hold`, which matters
  only after an unclean end. *From:* the 2026-11-08 7 Pro session, issue #532.
- **L-598. A code change that enables a protected-partition write waits until
  its evidence is called verified, not provisional.** #436 marked its 3.11
  table "provisional, not a same-state row" in the same push that kept the
  build flag enabling 3.11 writes at every boot. *Check:* for a PR that widens
  a `devinfo`, GPT or calibration write, grep its notes for "provisional", "not
  yet confirmed" and "still needs"; if one applies to the layout, ask for the
  enabling switch to come out (or a split) until it goes. Extends L-2, L-36 and
  L-527. *From:* #436, round 46, 2026-11-09.
- **L-599. (Provisional: from ABL's documented retry behaviour on 3.15, not
  yet seen on 3.11.) A same-state row for slot metadata has no slot boot
  between its two reads.** ABL spends a retry when it boots an unmarked slot,
  so `getvar` before a boot and Linux's bytes after it disagree on a correct
  layout. *Check:* when a row's retry byte is one below `getvar`, ask in which
  order the reads were taken, and prescribe the Linux read, then fastboot by
  the buttons, then `getvar`. Extends L-36 and L-527. *From:* #436, round 46,
  2026-11-09.
- **L-600. A "read-only check" a contributor reports is also read for what the
  phone is running now.** #330's check showed a live session of an unpublished
  image with `/sys/block/sda/ro` 0 on a single-slot phone. *Check:* for any
  reported `ro` values, read the whole-disk lines first, then ask what booted,
  how and since when, before reading the partition lines as a guard result.
  Extends L-321 and L-562. *From:* #330, round 46, 2026-11-09.
- **L-601. A guard change that makes a partition writable is checked for a
  writer in the same tree.** #530 opened enchilada's `boot_b` on `sde`, while
  `flash` and `push` refuse `android-v0`, `push` and `omamobile-boot-update`
  look on `sda` only, and a fastboot install never runs the guard, so the only
  possible writer was a hand `dd`. *Check:* for each partition a guard or
  allowlist change opens, grep `cmd_push`, `cmd_flash`, `omamobile-boot-update`
  and `tools/install-phone` for how they find it; if no tool reaches it, the
  opt-in waits for the writer's PR, and the mechanism can land inert. Extends
  L-321 and L-422. *From:* #530, round 46, 2026-11-09.
- **L-602. A contributor's note that a documented recovery path didn't work on
  their phone is checked against what the PR changes before it lands in the
  device's notes.** #554's NOTES said Volume Down + Power "ended in a normal
  boot", and kernel #233's fix, which runs only at power off, can't touch that
  path. *Check:* name the mechanism the fix changes and the one the claim
  uses; if they differ, ask for the hold, the starting state and the result,
  and keep AGENTS' instruction until it is re-run. Extends L-29 and L-91.
  *From:* #554 with kernel #233, round 46, 2026-11-09.
- **L-603. A boot that replaces `multi-user.target` as the default loses
  everything wanted only there:** `omamobile-boot-success`, ufw, logind (#554's
  off-mode charging target). *Check:* `grep -l 'WantedBy=multi-user'` over the
  image's units (Omarchy's included) and each device package's
  `multi-user.target.wants/`, and say for each whether the new boot needs it.
  *From:* #554, round 46, 2026-11-09.
- **L-604. A PR that touches AGENTS.md or CONTRIBUTING.md is word-diffed in
  full against its own parent, not only read where its topic is.** #409's
  9a-sleep commit replaced the whole AGENTS.md with what looks like a local
  copy: the first safety rule became "Reboots and pushes do not need advance
  approval", and three maintainer-only tool rows lost their "human's go"; the
  commit message mentioned none of it. *Check:* `git show <commit> --
  AGENTS.md CONTRIBUTING.md | grep '^[-+]'` for every commit; any hunk outside
  the PR's stated topic is blocking until explained. Extends L-224, L-339 and
  L-486. *From:* #409, round 46, 2026-11-09.
- **L-605. When a safety fix's only way back is a step the device can't take,
  the decision says so.** The 9a's gauge leaves POR only when Android reloads
  the model, and a stock boot there costs userdata, so "refuse until reloaded"
  meant "no battery for good". *Check:* for a refusal a PR relaxes, name what
  clears the refused state on that device and whether AGENTS §4 allows it.
  Extends L-284. *From:* kernel #234, round 46, 2026-11-09.
