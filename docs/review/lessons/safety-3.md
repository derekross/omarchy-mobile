<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Safety model (AGENTS.md section 1) (part 3 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

- **L-295. `tools/usbc-deadman` is cheetah's MAX77759 tool,** with that
  phone's I2C bus and registers built in. For another phone's USB-C step, the
  dead-man we name is the generic `systemd-run --on-active=… systemctl reboot`
  plus a `tools/phone-ssh --fresh` login. *Check:* any draft that names a
  device tool for a step on another phone reads the tool for hard-coded buses,
  addresses and compatibles. Extends L-276 and L-81. *From:* #131, round 27.
- **L-294. A regulator that sources VBUS is checked for every path that
  enables it outside the Type-C state machine.** Those are DT
  `regulator-boot-on` or `regulator-always-on` (the core enables it at
  registration), fast role swap (no vSafe0V wait), and state left over from a
  warm reset (a boost whose watchdog is off). *Check:* the binding forbids the
  two properties, the TCPC sets `vbus_vsafe0v`, and we ask for a warm-reboot
  read of the boost before any driver loads. *From:* kernel #124, round 27.
- **L-285. "The approved tool did the write" is checked for what made the
  target writable.** `omamobile-bootctl` only opens `devinfo` for writing; the
  guard bypass (`--setrw` on the partition and its parent for 30 s) was in the
  owner's laptop script around it. An approval that names the tool leaves the
  wrapper unreviewed. *Check:* for any write outside the allowlist, find who
  lifts the read-only flag and whether that code was reviewed. Extends L-2 and
  L-261. *From:* #125, round 26.
- **L-284. A hold on a safety step is checked for what it forces next.**
  Telling the 9a owner "don't mark B" without also saying "don't `flash`"
  would have led straight to the next fallback, because `flash` unmarks B and
  the marking is what keeps the root. *Check:* for any "don't do X until I
  decide", walk the owner's next routine step with X missing, and give the
  safe interim path (here, `push` only). Extends L-81 and L-158. *From:* #125,
  round 26 (a near miss in drafting).
- **L-267. A recovery report that says "marked again" is a `devinfo`
  question.** On the 9a, marking slot B successful is a `devinfo` write,
  agreed only through `omamobile-bootctl` with a fresh backup and a full
  before/after compare. A thread or an AGENTS rule that cites another tool, or
  one outside the repository (`logs/…py`), is a second writer. *Check:* `git
  grep` the tool's name, then the device NOTES for the agreed operation and
  its preconditions. Extends L-36 and L-186. *From:* issue #28 with #125,
  round 25.
- **L-261. A safety rule that prescribes a protected-partition write is held
  to the exact approval on record.** #125 turned the one approved tegu
  `devinfo` operation (`omamobile-bootctl mark-successful`, with a fresh
  backup and before/after bytes) into a standing "after every flash" step, run
  by an unreviewed script. *Check:* for any AGENTS or CONTRIBUTING text that
  tells people to write `devinfo`, the GPT or `persist`, find the approving
  review and diff the tool and conditions against it; ask whether writes
  already made met it. Extends L-2 and L-224. *From:* #125, round 25.
- **L-223. An installer step that writes the phone runs after the typed
  codename and is listed in the "only these commands" banner.** #111's
  `install-phone` RAM-booted a bootloader copy straight after `getvar`, before
  the questions and the banner. *Check:* list every command that can write
  (including ones a helper runs over SSH) and its line relative to the
  codename prompt; a dry-run test that skips the helper proves nothing about
  the order. Extends L-2 and L-5. *From:* #111, round 24.
- **L-224. A policy exception written by the PR that needs it is a finding,
  however well specified.** #111 added its own CONTRIBUTING §3.1 entry and
  AGENTS line for a 33-partition firmware copy. *Check:* `git diff base head
  -- CONTRIBUTING.md AGENTS.md` on every device PR; a new exception goes to the
  maintainer and out of the PR. Extends L-2 and L-31. *From:* #111, round 24.
- **L-225. A pinned AVB rollback index is held to the oldest stock any owner
  runs.** #104 pinned a newer build's index for every cheetah, above the
  maintainer's slot A; rollback locations are device-wide, and libavb stores
  any higher non-zero index once a slot is marked successful, which
  `omamobile-boot-success` does. *Check:* `avbtool info_image` on each
  owner's stock `boot.img` (or ask for the build) against
  `AVB_ROLLBACK_INDEX`, `AVB_SECURITY_PATCH` and `OS_PATCH_LEVEL`; prefer the
  oldest, or 0 where a phone has shown it boots (#74). Extends L-169.
  *From:* #104, round 24.
- **L-226. `fastboot-info.txt` syntax isn't fastboot command-line
  syntax.** Told to follow felix's file exactly, #35 copied `flash
  --apply-vbmeta vbmeta` into a CLI line that fastboot rejects, mid-way
  through a slot A write. *Check:* every hand-written `fastboot` line in a
  runbook uses only options in `fastboot --help`. Extends L-205 and C-13.
  *From:* #35, round 24.
- **L-227. `ln -sf` or `mv -f` onto a state path is a delete; in Trusty or
  calibration code it's a finding.** #101's `ln -sfn` over `persist-ss/0`
  would remove cheetah's provisioned copy if one existed. *Check:* grep the
  diff for `ln -sf`, `mv -f`, `rm` and `>` onto the package's state
  directory, and find who creates those files (`tools/phone-provision`, the
  plans). Extends L-2. *From:* #101, round 24.
- **L-1. Shared boot code runs under busybox, not util-linux.** The Pixel
  initramfs has busybox only: `blkid -s LABEL -o value` prints the whole
  `LABEL=… UUID=…` line there, so a label check that works on a device whose
  initramfs adds util-linux fails on every Pixel. *Check:* any new command or
  option in `initramfs/init`, against busybox 1.37's applets; prefer tools
  `init` already uses (`dumpe2fs -h`). A test that stubs the command
  (a shell function named `blkid`) proves nothing about it. *From:* #25.
- **L-2. Writes past the storage guard are a policy decision, not a code
  review.** Raw SCSI WRITE through `SG_IO` on a read-only partition fd, an
  unsuffixed `fastboot flash userdata`, a `devinfo` write: each needs the
  maintainer's explicit go and a named exception, however well guarded.
  *Check:* `grep -nE 'SG_IO|0x2285|fastboot( -s [^ ]+)? (flash|erase) [a-z_]+( |$)|devinfo'`
  in the diff, and every `flash`/`erase` target ends in `_b` or is
  `userdata` through the guarded path. *From:* #17, #24.
- **L-3. Mismatched slot firmware is stop-and-ask (CONTRIBUTING §3.1).**
  A kernel workaround that's needed only on a phone with different
  bootloaders on its two slots (HCRX_EL2 with KVM off) is most likely the
  old firmware, not the SoC. Ask for both slots' bootloader versions, both
  slots on one build, and a re-test without the workaround before any of it
  reaches the kernel. *From:* #24.
- **L-4. A display-register write in a descriptor must be the device's own
  address, behind the COMPATIBLE gate.** `SIMPLEFB_TRIG_CON` is the one
  register write the initramfs makes. *Check:* the address is that SoC's
  DECON base (from the device's own live DT or Google's GPL CAL for that SoC)
  plus the `TRIG_CON` offset, not cheetah's `0x1c240030`; the value is the
  same bit change cheetah's pair makes (DISPLAY-PLAN); `COMPATIBLE` is
  unique to the board, so `board_matches()` in `initramfs/init` means
  something. *From:* #23 (correct: husky's `0x19470030 0x3061`).
- **L-5. Tools that talk to fastboot pin the serial.** With two phones in
  fastboot (the maintainer's Pixel on the desk), checks and writes without
  `-s <serial>` can reach different devices. *Check:* every `fastboot` call in
  an installer passes `-s`. *From:* #25.
- **L-6. A device whose buttons don't reset it under our kernel needs a way
  out of a hang.** Once a watchdog driver stops ABL's watchdogs, a hang that
  never panics lasts until the battery is flat. *Check:* panic-on-lockup
  arguments (`softlockup_panic`, `hung_task_panic`, `panic=`) in the shipped
  bootargs, or the watchdog left armed and fed. *From:* #23.
- **L-7. Contributors' builds stay out of the maintainer's keys and
  outputs.** A port that reuses `keys/gnupg`, rebuilds `omamobile-keyring`
  into `out/repo`, or names its root images `out/omamobile-rootfs-*` mixes
  into what `tools/repo-push` publishes and what `install-phone` picks by
  default. *Check:* new build scripts write under `out/<device>/` and
  `keys/<device>/`. *From:* #25.
- **L-35. A changed `vbmeta` flags byte on slot A means slot A was
  written.** The flags field starts at offset 120 of the vbmeta header;
  byte 123 = 3 is what `fastboot --disable-verity --disable-verification`
  writes, and it also breaks the signature. Treat it as a CONTRIBUTING §3.1
  event: record it, correct any "no verification-state change" claim, and
  have the OTA-twice equalisation restore flags 0 on both slots, then a
  read-only check and a fresh backup. *From:* #24, round 2.
- **L-36. Evidence that a `devinfo` layout matches comes from ABL's own
  reads and writes.** The version (3.15) alone doesn't prove the slot bytes
  mean the same on another SoC. *Check:* `fastboot getvar slot-successful`,
  `slot-unbootable` and `slot-retry-count` for both slots next to
  `omamobile-bootctl dump`'s bytes 0x30-0x37 for the same state, then again
  across a change ABL makes itself (a retry spent on an unmarked boot). Ask
  for those eight bytes and the version only, never a full dump. *From:* #24,
  round 2.
- **L-47. Every tool that talks to fastboot pins the serial, ours too.**
  L-5 covered installers; `bin/omamobile flash` and `capture` didn't pin
  either (fixed in c202b6d: one phone or `FASTBOOT_SERIAL`). *Check:* every
  `fastboot` call passes `-s`, and several phones are refused. *From:* #24,
  round 4.
- **L-48. When a PMU readback surprises, ask which write path ran and
  whether the restore was masked.** Mainline writes through atomic
  set/clear aliases (offset | 0xc000 / 0x8000), Google through a
  read-modify-write SMC; only a masked restore tells hardware status bits
  from stored ones. *Check:* the probe's call, the restore's mask, and
  Google's own users of that `pmu-offset`. *From:* issue #28.
- **L-81. A request that cycles USB comes with its own way back.** The
  gadget is the phone's only link, so "unbind and rebind dwc3" ends the
  session that would rebind it. *Check:* any requested step that touches
  dwc3, the USB PHY or the gadget gives one detached job (`systemd-run
  --unit=…`), a dead-man reboot armed first, the configfs `UDC` re-attach, a
  fresh SSH login to confirm, and a stop condition (AGENTS.md section 1).
  *From:* kernel #33, round 2 (correcting round 1's bare request).
- **L-82. A runbook that avoids `bin/omamobile flash|push` needs a reason we
  can trace to the code.** #34's plan had the operator write slot B by hand,
  blaming `push` for a slot A fallback that comes from the initramfs USB-host
  safety net (no host in 45 s, crash, ABL falls back), whatever wrote the
  images. *Check:* grep plans for "do not use … flash/push" and hand-written
  `dd` or `fastboot flash` steps; if the tool really is wrong, fix the tool.
  *From:* #34, round 2.
- **L-88. A dead-man for a driver-cycle test must not go through the path
  under test.** `reboot-to` runs `device_shutdown`, which husky's DWC3 cycle
  hung. *Check:* the runbook arms an independent `echo b >
  /proc/sysrq-trigger` job (it skips driver shutdown), is run attended, and
  has a view that isn't USB (`printk` at 8 on the panel). Extends L-81.
  *From:* kernel #33, husky test 23. (See C-3: the cycle froze the SoC; it
  didn't hang shutdown.)
- **L-89. A guarded tool that contributors can't use gets bypassed.** With
  an SSH key that needs a tap per connection, `push` asked for about 25
  taps, so the felix contributor wrote slot B by hand. *Check:* when a
  runbook avoids a tool, find the friction and fix the tool, not only the
  rule. Extends L-82. *From:* #34, round 3.
- **L-90. A touch controller's firmware update can erase its calibration.**
  FTM5's `flash_burn` erases the on-chip flash that also holds CX (whether it
  survives depends on `keep_cx`). *Check:* a plan for such a part says that
  nothing writes or erases that flash without the maintainer's go, and asks
  its firmware questions read-only. *From:* #35.
- **L-91. A button finding names the exact combination, and the recovery
  docs follow it.** On husky Power alone does nothing; Power + Volume Up for
  15-30 s resets it, so CONTRIBUTING's "hold Power" fails there. *Check:* a
  new device's recovery keys reach CONTRIBUTING §3.4 and AGENTS.md. *From:*
  #23.
- **L-108. A touch controller can rewrite its own calibration without a
  firmware flash.** ST FTM5 built with `COMPUTE_INIT_METHOD` (felix's
  `fts.h`) runs a full panel init when the AFE versions differ or the MP flag
  isn't a factory value, saving new CX and the MP flag to the chip's flash.
  *Check:* a "no flash writes" rule for such a part also forbids panel init,
  CX tuning or save commands and MP flag writes; read the init-method
  `#define` in the vendor header. Extends L-90. *From:* #35, round 10.
- **L-109. Phone results posted ahead of the plan are recorded, and their
  code published, before the next boot.** #35's plan said "no phone step"
  while its comments reported reads from a kernel in no repository. *Check:*
  the boot goes into Results with `uname -r`, the tree and how slot B was
  written, and the code is pushed (branch or draft PR) with a runbook before
  it boots again. Extends L-34. *From:* #35, round 10.
- **L-133. A dead-man's confirmation comes after the risky step.** felix's
  cover-touch step 8 armed the timer, confirmed over a fresh login, then
  loaded the driver and stopped the timer, so the timer could never fire on
  the load. *Check:* every runbook goes arm → act → confirm with
  `tools/phone-ssh --fresh` → stop the timer, and a driver load streams kmsg
  to the laptop first, because an unbind timer can't undo a hang. Extends
  L-81 and L-88. *From:* #35, round 12.
- **L-134. A device's own `INITRAMFS_INIT` is a fork of the storage guard.**
  raven's copy predated the final `ufs_unguarded` check and the fail-closed
  allowlist, and `tests/storage-guard` tests the shared script only.
  *Check:* `grep INITRAMFS_INIT device/*/device.conf`; for a value without a
  leading `/`, diff that init against `initramfs/init` and list each guard
  commit (`git log -- initramfs/init`) it lacks. Ask for the shared init with
  descriptor-driven steps. *From:* #41, round 12.
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
