<!-- SPDX-License-Identifier: MIT -->
# Review lessons

What reviewing pull requests on Omarchy Mobile has taught us, one lesson
per entry: the rule, why it matters, how to check it, and the review it came
from. The reviewer agent (`.claude/agents/omamobile-reviewer.md`) reads this
file before every review, and a human reviewer can use it as a checklist.

**How it grows.** Each review ends with candidate lessons: a pattern that
caught a real problem, or a mistake the review made. The maintainer confirms
or corrects them, and confirmed ones are added here in the same commit as
the change that prompted them (`docs/review: …`). A lesson that turns out
wrong is corrected in place, with the date and why, never silently deleted:
the corrections are lessons too. Keep entries short; link the evidence.

Entries are grouped by area, newest first within a group. `L-<n>` numbers
never change, so reviews can cite them.

## Safety model (AGENTS.md section 1)

- **L-298. A retry path is exercised on the phone by holding its dependency
  down, not by breaking hardware.** #99's screen-on retry can be forced by
  keeping neard stopped across a screen-on. *Check:* first confirm the daemon
  isn't D-Bus-activatable (`/usr/share/dbus-1/system-services`, `BusName=`),
  hold it with `systemctl mask --runtime` (gone at reboot), and give the step
  an unmask rollback. *From:* #99, round 27.
- **L-297. A gotcha that adds an unproven alternative to a proven safety step
  says which one to run.** #137's "the hook should power the adapter off" sat
  next to a 0-of-1 wake record, while stopping the poll loop was 35 of 35.
  *Check:* every "should" in a safety gotcha points at the variant with the
  passing record, and the untested one is marked "under test, attended".
  Extends L-188 and L-284. *From:* #137, round 28.
- **L-296. A crash-survival measurement uses a reset that skips shutdown, and
  guards the replug.** #124's `.shutdown` turns the boost off, so the
  runbook's `systemctl reboot` couldn't answer what a crash leaves behind, and
  a boost that does survive meets the laptop's VBUS on replug. *Check:* for
  every "measure after a reboot" step, list the `.shutdown` hooks of the
  drivers involved and reset with `echo b > /proc/sysrq-trigger`; if the state
  under test can source VBUS, a meter check with a stop condition comes before
  any replug. Extends L-88 and L-81. *From:* #136 with kernel #124, round 28.
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
  the reset" and "back up after a stock boot". *From:* #42, round 14.
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


## Shared code and the reference device

- **L-301. A shared-driver branch gated on what callers send counts as match
  data under CONTRIBUTING §6.2 only if no reference-phone consumer sends it,
  on the base and on `omamobile-int`.** Kernel #125's DCS-read path runs only
  when a panel asks for a read, but inlining still changes the hot function's
  machine code. *Check:* `git grep` the consumer drivers for the new API's
  callers on `github/omamobile` and `omamobile-int`, and prefer a boot when
  one is already planned. Extends L-206 and L-228. *From:* kernel #125, round
  28.
- **L-300. A touch-scaling change is cheetah-neutral only when the axis
  maximum plus one equals the panel size.** On #135 the synaptics probe line
  (`…, 1440x3120, 10 objects`) and no `touchscreen-size-*` in the board DT
  showed that `scale()` is the identity on cheetah. *Check:* grep `logs/` for
  the probe's `app fw` line and `git grep touchscreen-size` in the DTS before
  calling such a change neutral. *From:* #135, round 28.
- **L-299. A per-device constant given "as before" in a shared runner is
  checked against that device's notes, not the line it replaced.** #135's
  "cheetah 60 Hz, as before" repeated the old `op_hz`, but NOTES 2026-10-12
  and DEVICES.md say cheetah runs at 120 Hz by default. *Check:* `grep -n` the
  value in `device/<codename>/NOTES.md`, the subsystem plan's status line and
  DEVICES.md. Extends L-280. *From:* #135, round 28.
- **L-282. An env-default variable in a shared build library is an input to
  the maintainer's builds too.** #79's `ALARM_LOCAL_KEY=${ALARM_LOCAL_KEY:-}`
  in `tools/lib/alarm.sh` lets a leftover export widen trust in a build
  without `--local`. *Check:* for each new `VAR=${VAR:-}` in `tools/lib/`,
  confirm the maintainer's path sets or clears it explicitly. Extends L-7 and
  L-171. *From:* #79, round 26.
- **L-280. A per-device flag that gates new behaviour in a shared runner is
  checked by building the command line under both values.** #101's
  `MAP_STORES` adds storageproxyd arguments through an array, and an empty
  `"${maps[@]}"` must vanish under `set -u`; a grep test can't show that. Run
  with both images present, cheetah got the same 9 arguments as main and tegu
  15. *Check:* extract the argument-building block and run it under `set -euo
  pipefail` with each flag value and the triggering files present. Extends L-8
  and L-234. *From:* #101, round 26.
- **L-273. A before-merge Pixel 7 Pro run on `omamobile-int` compares the
  touched file on int with the base first.** Where they differ, the run covers
  the PR's hunk inside int's code, and the runbook and merge comment say
  "tested on int + the commit"; where the cherry-pick conflicts, show that the
  untestable commit is neutral on gs201. Kernel #82's `synaptics_tcm.c` and
  #71's `net/nfc/core.c` differ between int and the base, and #88's gs-decon
  commit doesn't apply to int. *Check:* `git rev-parse omamobile-int:<f>
  github/omamobile:<f>`, then `git merge-tree --merge-base <c>^ omamobile-int
  <c>`. Extends L-206 and L-45. *From:* kernel #82, #71, #88, round 25.
- **L-268. A package that installs a hand-built prebuilt publishes a stale
  binary when only its source changes.** fingerprint 0.1.9 changed the
  bridge's C source, but the package installs `prebuilt/omamobile-fp-bridge`
  as it finds it; gnss 0.2.4 builds without the 9a client and says so only in
  the log. *Check:* for a package PR that touches a prebuilt's source, ask
  whether the build machine rebuilt the prebuilt, and prefer a test that
  compares the prebuilt's build ID or date with its source. Extends L-259.
  *From:* issue #109, round 25.
- **L-228. A board DT property that only the contributor's board sets counts
  as its match data under CONTRIBUTING §6.2.** It holds when no base DTS,
  cheetah overlay in `DTB_OVERLAYS` or open PR sets it, and the object diff
  shows every new instruction behind the field it fills; for board wiring
  (#94's REG_ON flip-flop) it's stricter than the compatible. *Check:* `git
  grep '<property>'` on the base's `arch/` and `device/*/overlays/`, then the
  per-function object diff. Extends L-206 and L-49. *From:* kernel #94, #95,
  round 23; confirmed by the maintainer.
- **L-229. An alternative we offer in a draft is held to CONTRIBUTING like
  the main request.** Round 22 offered kernel #88 "or keep the shared lookup
  and I'll run it on my phone"; §6.2 lets a Pixel 7 Pro run stand in only for
  a deliberate cheetah change with a cheetah reason, and the contributor took
  the offer. *Check:* every "or, if you prefer, …" against §6.2 before
  posting; if the rule doesn't cover the case, fix the rule first. Extends
  L-31. *From:* kernel #88, round 23; confirmed by the maintainer.
- **L-230. Inserting into the middle of a shared struct or enum changes
  cheetah's objects outside the touched function.** #62's hook in `struct
  exynos_pmu_data` shifted later fields by 8 bytes; #101's new
  `sec_device_type` renumbered every later type. *Check:* read each flagged
  function's changed instructions (offset-only loads; compares only against
  values after the insertion), confirm the reference phone's values sit
  before it, and compare data symbols' bytes and relocations base vs head.
  Extends L-110, L-111 and L-153. *From:* kernel #62, round 23; kernel #101,
  round 24.
- **L-231. A registration that opts out is not a no-op when the core's
  default is "needed unless everyone opts out".** gs-decon's
  `pm_vt_switch_required(dev, false)` turns the suspend VT switch off on
  cheetah, because the PM core switches only while its list is empty or one
  entry requires it. *Check:* for a new opt-out registration in a shared
  driver, read the core's aggregate rule and list what else registers on the
  reference phone. Extends L-206. *From:* kernel #116, round 24.
- **L-232. Before calling a forked guard's behaviour a defect, diff it
  against the shared original.** dodge's watcher skips disks with a
  `/run/ufs-ro` marker, which looked like a gap; `initramfs/init` does the
  same by design. *Check:* `diff` the fork's function against
  `initramfs/init` before naming a gap. Extends L-134 and C-1. *From:* #111,
  round 24 (a near miss).
- **L-233. A device package's workaround for an Omarchy service is checked
  against Omarchy's package list before it stays device-local.** #74
  disables `linux-modules-cleanup` for tegu, but the service comes from
  `omarchy-base.packages` and is enabled by Omarchy's installer, so it likely
  runs on every phone. *Check:* grep the unit's package in
  `/usr/share/omarchy/install/omarchy-base.packages`, `enable-services.sh` and
  `rootfs/packages.omarchy-skip`, then ask for one read on cheetah. Extends
  L-11 and L-32. *From:* #74, round 24.
- **L-234. A shared script that branches on `/proc/device-tree` makes its
  package test host-dependent.** #117's test passes on CI and the laptop,
  fails in `makepkg check` on the Pixel 9a it's for, and never runs that
  branch. *Check:* every new DT read in a package script has an override the
  test uses, and the test runs each branch. *From:* #117, round 24.
- **L-8. "Nothing changes for cheetah" is checked by building it.** For any
  change to `bin/omamobile`, `initramfs/`, `rootfs/`, `tools/` or a shared
  package: build cheetah's images with main's tool and the PR's, in separate
  scratch output directories, and compare sha256s. *From:* #27 (all six
  images and every DTB identical).
- **L-9. A test whose baseline is `origin/main` stops testing once it
  merges.** Pin the baseline (a commit, or recorded checksums). *From:* #27.
- **L-10. Parsers of decompiled DTBs must allow labels.** Our DTBs are built
  with `-@`, so dtc restores labels (`x: node {`) from `__symbols__`; a
  regex for `^\t\tNAME {` misses a labelled child and passes a DTB with an
  extra one. *Check:* feed the parser a labelled node and an extra child.
  *From:* #27.
- **L-11. Shared root-image changes need their own commit and a Pixel
  rationale.** Masking `systemd-firstboot`, a coredump drop-in, a
  `clock-epoch` file or `Wants=time-set.target` in `rootfs/build-inside`
  changes every device's image. (systemd.special(7): order after
  `time-set.target`, never pull it in.) *From:* #25.
- **L-12. Package versions can collide with main.** A PR bumping a package
  to a version main already shipped (with different contents), plus a
  dependency `>=` that version, installs without the PR's change. *Check:*
  `git show origin/main:packages/<p>/version` against the PR's. *From:* #17.
- **L-13. Device-specific tool stages must refuse other devices.** A raven-only
  AoC stage (`cycle`, `tzpc`, `pd`, `s2mpu`) accepted on cheetah power-cycles
  the reference phone's AoC; a stage the PR's own notes say aborts the SoC
  unless another ran first must enforce that order (a per-boot marker).
  *From:* #22.

- **L-32. Know what Omarchy already sets before claiming a userspace
  default.** `omarchy-settings` ships `/etc/systemd/logind.conf.d` drop-ins
  (`HandlePowerKey=ignore`), and Omarchy's Hyprland config binds the
  `switch:` named "Lid Switch" to its clamshell logic. *Check:* `pacman -Ql
  omarchy omarchy-settings | grep -E 'logind|lid'`, and on the phone
  `busctl get-property org.freedesktop.login1 /org/freedesktop/login1
  org.freedesktop.login1.Manager Handle…`. *From:* #29.
- **L-37. A kernel change that needs a userspace companion merges after
  it.** A new `SW_LID`, wakeup source, or any node whose default userspace
  policy is harmful (logind suspending a folded phone) waits for the
  omarchy-mobile change that handles it, so no build ever has one without
  the other. *From:* kernel #12 with #29.

- **L-49. "Disabled" means disabled in the DTB the phone runs: the DTS plus
  its `DTB_OVERLAYS`.** Cheetah's DTS has `pmic-1` disabled, but its
  `suspend-pmic-test` overlay enables it, so a new S2MPG12 cell binds on
  the reference phone. *Check:* grep the device's `DTB_OVERLAYS` for every
  node a PR's code binds to. *From:* kernel #27 (correction C-2).
- **L-50. A new MFD cell binds wherever an overlay enables its parent;
  for cheetah, ask for a read-only boot first.** Code reading said the
  S2MPG12 regulator driver only reads; one boot with `regulator_summary`,
  dmesg and `tools/phone-smoke` proves it. *From:* kernel #27.
- **L-51. Error-propagation fixes in shared drivers change the reference
  phone's failure modes.** A UFS PHY error ignored before became fatal at
  boot, reset and resume. *Check:* list which callbacks can now fail, grep
  cheetah's logs for those errors, and boot it once. *From:* kernel #19,
  #22.
- **L-67. A rail a PR touches on another phone may feed something on
  cheetah.** felix's cover-touch LDO25M/LDO26M are cheetah's main touch
  rails (and LDO27M/LDO28M its display rails). *Check:* look the rail up in
  NOTES and the plans, and name those peripherals in the read-only cheetah
  boot's Expect line. *From:* kernel #27, round 3.
- **L-87. A new installer refusal fed by bootloader variables is checked
  against the reference phone's real `getvar all` capture,** line endings
  included, before it can refuse cheetah. *From:* #27, round 3 (cheetah's ABL
  lists `partition-size` for all five `_b` partitions, so the refusal holds).
- **L-110. A shared-driver change confined to one static function is
  proven cheetah-neutral by comparing the object function by function.**
  Build the `.o` at base and head with the same config and diff the
  disassembly per function: for #42 only `exynos2200_usbdrd_phy_exit`
  changed. Extends L-8. *From:* kernel #42.
- **L-111. When a shared driver moves constants into per-SoC match data,
  prove "unchanged on cheetah" with a table and a boot, not an object diff.**
  Loads through `dc->soc` change the object anyway. *Check:* each new field's
  gs201 value next to the constant it replaced, each new branch's gs201
  condition, then one boot with before/after reads of the driver's own
  counters. *From:* kernel #46.
- **L-112. A core change that makes a reserved value valid updates the
  binding that reserved it, and names the boards that change.** reboot-mode
  has skipped a zero magic since 2016 and its binding says "non-zero".
  *Check:* `git log -S` on the binding for the rule's origin, `git grep` for
  the value across all DTs (`da850-lego-ev3`'s zero `mode-normal`, written `<0x00000000>`), and both
  in the commit message. *From:* kernel #45.
- **L-136. A probe's default pin or register is a per-board fact.**
  `bt-uart-test --wake` defaulted to cheetah's gpp16:3 on every phone; on
  gs101 that is a USI8 pin. *Check:* a tool that drives a GPIO or register
  on the phone takes its default from the board's compatible, or refuses an
  unknown board without an explicit value. Extends L-13. *From:* #22,
  round 12.
- **L-137. A device package's wants links can override another package's
  "installed, not enabled" policy.** raven's package enabled the modem and
  SIM units at boot. *Check:* for each `vendor/systemd/**/*.wants/*` link,
  find the package that owns the unit and read its install message and unit
  comments; turning a radio on by default is the maintainer's call. *From:*
  #41, round 12.
- **L-160. Hiding a shell surface removes every gesture on it, and a new
  edge surface is checked against the keyboard and fullscreen windows.** #43
  hid the dock over apps, its swipe-up the switcher's only entry point; its
  new full-width pill sat on the Overlay layer with no input mask. *Check:*
  `git grep` the surface's handlers; for a new layer surface, its layer,
  input region, the keyboard's layer and fullscreen apps. *From:* #43,
  round 14.
- **L-161. A lock-path check that fails open is a finding.** `jq -e
  'all(.dpmsStatus)'` read a failed `hyprctl` query as "screen off", so Power
  would stop locking. Test for the positive state, failing towards locking.
  *From:* #43, round 14.
- **L-162. A per-board audio file is only as safe as the shared fallback,
  and node-name filters apply to every board with that name.** If tegu's card
  name changed, alsa-ucm-conf would fall back to cheetah's profile, whose mic
  list takes tegu's AoC down; cheetah's loudness filter matches any sink named
  `sound-aoc`. "Stage ceilings" are cheetah's CS35L41 bound: a new amplifier
  needs its own. *From:* #44, round 14.
- **L-172. An NFC core change is a cheetah change: the Pixel 7 Pro polls
  through neard at boot.** `omamobile-nfc-open` is enabled by
  `omamobile-setup-system` and starts a poll loop, so every `net/nfc`
  behaviour tied to polling (rfkill block, poll ownership, proprietary
  notifications) runs on the reference phone at every boot; the NFC tile's
  "Off" had been a no-op there too. *Check:* `git grep -n nfc-open
  packages/omamobile-device-cheetah` before saying "cheetah unaffected" for
  an NFC change. Extends L-51. *From:* kernel #71 with #78, round 20.
- **L-173. A shared `initramfs/init` change is cheetah-neutral by its
  gates, not by a byte comparison.** The init text changes for every device,
  so the packed image differs by construction. *Check:* list each new path's
  marker file, show that `bin/omamobile initramfs-config` packs none of them
  for cheetah and felix (byte-identical `etc`), read each path's early
  return, and let the next routine cheetah push be the boot. Extends L-8 and
  L-134. *From:* #41, round 20.
- **L-206. Shared drivers leave the Pixel 7 Pro unchanged by construction
  (CONTRIBUTING §6.2).** New behaviour sits behind the contributor's own match
  data; a deliberate cheetah change needs a reason that holds on cheetah and a
  run on the maintainer's phone before merge. Where a flag is tested inside a
  shared function (#57's `UNGATE_POST_CHANGE` in `exynos_ufs_setup_clocks()`),
  the object can't be byte-identical: accept a per-function object diff plus a
  flag table showing cheetah's path unchanged (L-111). Per-SoC data also
  reaches every board that binds it through a fallback compatible (#83's
  `zumapro_ufs_drvs` is zuma's too). *Check:* cheetah's objects before and
  after, function by function where they differ; `git grep '"<compatible>"'
  arch/` for every board listing the data's compatible, fallbacks included,
  and those boards' plans for statements the change falsifies. Extends L-151.
  *From:* kernel #57, #82, #83, #88, round 22.
- **L-207. A gs101/gs201 device package carries the s2idle drop-in.** Cheetah
  and raven ship `sleep.conf.d/10-omamobile.conf`; felix and lynx don't, so
  Omarchy's Suspend enters `deep`, which never wakes on gs201. *Check:* `git
  ls-tree -r origin/main packages/ | grep sleep.conf` for every such device
  package, and `mem_sleep_default` in the board's bootargs. *From:* #88,
  round 22.


## Shell and scripts

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

## Kernel (linux-omarchy-mobile)

- **L-308. An out-of-tree module installed under `updates/` disappears with
  every kernel push.** #136's runbook put a regulator module in
  `/usr/lib/modules/$(uname -r)/updates`, and the charger and TCPC wait for
  that regulator through DT supply links, so the next `push` boots without
  them. *Check:* grep runbooks for `updates/`, trace the DT consumers of the
  module's nodes, and require the runbook to say what boots without it and to
  reinstall it after each `push`. *From:* #136, round 28.
- **L-307. A per-function object diff ends each function at its symbol size
  and normalises absolute branch targets.** With inline alternatives, arm64's
  readl replacement pool sits after the last function in `.text`, so new
  readls elsewhere "changed" `gs_dsim_wait_fifo`; unstripped `0x… <fn+off>`
  targets flagged two more. *Check:* cut each function at its `llvm-nm -S`
  size (or treat a trailing `dmb osh`/`ldar` block as the pool), and first
  check the normaliser reproduces a known result (base to #88). Extends L-153
  and L-247. *From:* kernel #125, round 28.
- **L-306. A provider merged as `status = "disabled"` turns a board's `&label`
  reference into a silent runtime defer.** `dtc` and `dt-validate` both pass
  the lynx draft without `&pinctrl_hsi2 { status = "okay"; }`. *Check:* for
  every `&bank` or `&provider` a board PR references, read the provider node's
  status in the dtsi at the base, and require the board to enable it. Extends
  L-240. *From:* kernel #98 with #123, round 27.
- **L-305. When a driver swallows a provider's `-EPROBE_DEFER` and falls back,
  follow the fallback's own lookups before calling the result unpowered.**
  hci_qca drops `pwrseq_get()`'s defer, but its fallback asks for regulators
  that point at the PMU's `ldo` nodes, which nothing registers, so
  `of_regulator_dev_lookup()` defers anyway. *Check:* for each supply phandle
  in the fallback path, find who registers that node; a node with no regulator
  device defers, and only a missing property falls back to a dummy. *From:*
  kernel #98, round 27.
- **L-304. A devm action that uses a resource is registered after that
  resource is acquired.** Devres unwinds in reverse, so #124's restore action,
  registered before `devm_regulator_get_optional()`, ran after
  `regulator_put()` had freed the boost: a use-after-free on unbind with host
  mode on. *Check:* when a commit adds a resource that an earlier devm action
  or `.remove` uses, list the devm registrations in order, confirm each action
  comes after everything it touches, and read any "unwound in reverse" comment
  against that order. *From:* kernel #124, round 27.
- **L-269. A power sequencer keeps a shared supply up only while another of
  its targets has a consumer.** `pwrseq-qcom-wcn` reference-counts its
  regulators across the Bluetooth and Wi-Fi targets; with Bluetooth as the
  only consumer (lynx has no PCIe Wi-Fi node), Bluetooth off still drops the
  buck. *Check:* read the sequencer's unit dependencies and the core's
  `enable_count`, then list which targets have a consumer in that board's DT.
  Corrects L-241's advice; see C-16. *From:* kernel #98, round 25.
- **L-236. A binding's numeric constraints are checked against the stock
  value of every phone that may use the property, the reference phone
  first.** #95's `multipleOf: 47000` rejects stock cheetah's
  `cirrus,vpbr-thld-uv = <3000000>`, which Google's driver rounds down.
  *Check:* `grep -rn <property>` in the stock live DTs, then feed that value
  through dt-validate. Extends L-52 and L-102. *From:* kernel #95, round 23.
- **L-237. Before accepting a per-compatible constant for a firmware layout,
  check whether the vendor driver reads it from the device.** #93's 14-byte
  GT9895 record is right, but Google's driver takes it from
  `point_struct_len` in the IC info goodix-berlin already parses. *Check:*
  grep the vendor driver for where the value comes from before agreeing to
  match data. Extends L-53 and L-72. *From:* kernel #93, round 23.
- **L-238. A Kconfig `select` of a symbol that doesn't exist is silent, and a
  sibling that selects the right one hides it.** #114 selects `CS_DSP` (the
  symbol is `FW_CS_DSP`); it built because cs40l26-vibra and the CS35L41
  codec select the real one. *Check:* `git grep -n '^config <SYM>$'` for
  every selected symbol, then build with the siblings off. Extends L-20 and
  L-143. *From:* kernel #114, round 24.
- **L-239. A board DT is checked against the condition its binding text
  states.** Raven's DSIM got `google,decon` ("when no KMS driver runs it") in
  the commit that enabled gs-decon's KMS on that DECON, leaving two drivers
  doing unlocked read-modify-writes of `TRIG_CON`. *Check:* for each optional
  property a board sets, read its binding description and confirm the board
  meets it. *From:* kernel #116, round 24.
- **L-240. A board PR is built against the published branch's labels, not
  the author's tree.** #98 references `&gph2`, which gs201 has only on the
  integration branch. *Check:* for every `&label` a board PR adds, `git grep
  '<label>:' github/omamobile -- arch/arm64/boot/dts/`; if missing, `git log
  -S` on `omamobile-int` for the owner. Extends L-149 and C-10. *From:*
  kernel #98, round 24.
- **L-241. A supply shared by two radios is checked for what each driver does
  at power-off.** hci_qca's WCN6855 path disables every supply when Bluetooth
  goes down, so a fixed regulator on lynx's shared buck drops Wi-Fi with it;
  Google's driver never drops that pin. *Check:* read each consumer's
  power-off and runtime-PM paths, compare with the vendor driver, and prefer
  the upstream power sequencer (`qcom,wcn6855-pmu`). Extends C-9 and L-67.
  *From:* kernel #98, round 24. *Corrected 2026-10-28:* the sequencer keeps
  the buck up only while Wi-Fi is also its consumer (L-269, C-16).
- **L-242. A firmware-naming driver can pick different files for two
  revisions of one chip.** btqca adds a `g` NVM variant for some `soc_id`
  values, so lynx's two revisions load different files; one phone's
  "tested" covers one. *Check:* compute the file names from each owner's
  reported version. *From:* kernel #98, round 24.
- **L-243. "Clock gating with Hibern8 as gs101 does" needs the PHY's Hibern8
  hooks too.** gs101's PHY carries Google's `post_h8_enter`/`pre_h8_exit`
  tables, zumapro's doesn't. *Check:* `git grep cfgs_hibern8
  drivers/phy/samsung/` for the PHY the board binds, against the vendor's
  tables. Extends L-77 and L-113. *From:* kernel #99, round 24.
- **L-244. A hunk inserted right after a block comment leaves the comment
  describing the wrong code.** #104 and #119 did this; checkpatch doesn't
  see it. *Check:* for each hunk, a closing `*/` on the line above its first
  `+` line means it split a comment from its code. *From:* kernel #104,
  #119, round 24.
- **L-245. A ramoops node is checked against stock's sizes and the siblings',
  not only its address.** `record-size` puts a dmesg zone first and moves the
  console zone, while the bootloader writes its log at stock's offset.
  *Check:* stock's reserved-memory DT and `git grep -A4 '"ramoops"'
  arch/arm64/boot/dts/exynos/google`. *From:* kernel #106, round 24.
- **L-18. Check every commit for a human `Signed-off-by:`.** Three PRs at
  once came without one, while their bodies said "checkpatch clean": it was
  run on a diff, where the sign-off check can't fire. `tools/kernel-pr-check`
  checks it now. *From:* kernel #10, #11, #12.
- **L-19. Clock fixes belong in the clock driver's field description, not
  in a DT override.** `assigned-clock-parents` on a mux the driver describes
  at the wrong bit writes a reserved bit. *Check:* the mux's shift and width
  in `clk-gs101.c`/`clk-gs201.c` against Google's CMUCAL `cmucal-sfr.c`
  (`SFR_ACCESS(..._SELECT, shift, width, ...)`) for that SoC; CMU_APM is the
  ACPM firmware's own clock block, so prefer read-only there. *From:*
  kernel #6 (gs101 APM_FUNC: driver bit 4, Google bits [1:0]).
- **L-20. Kconfig `depends on` must cover every bus the driver registers
  on.** A driver that calls `spi_register_driver()` unconditionally with
  `depends on I2C` fails to link with `CONFIG_SPI=n`; our config has SPI on,
  so we'd never see it. *From:* kernel #8.
- **L-21. No wildcard compatibles** (`samsung,s6sy79x`): name the real part.
  *From:* kernel #8.
- **L-22. Power domains: follow the upstream series, and leave live
  co-processors alone.** A `google,gs101-pd` that differs from André
  Draszik's pending upstream series (domains as PMU children,
  `domain-supply`, the EL3 DTZPC call around every power change) will
  conflict; without the DTZPC call a domain powered back on comes up with
  its TrustZone settings reset. Powering off the AoC's domain while the AoC
  runs, with no handshake, belongs to the AoC series. *From:* kernel #9.
- **L-23. Thermal: the hardware trip is the last line of defence.** A driver
  that sends ACPM's TMU init must show the firmware's hardware thermal trip
  survives it; blocks with only a 110 °C critical trip need a reason.
  *From:* kernel #7.
- **L-24. Alive pin banks have no power-down configuration.**
  `samsung,pin-con-pdn`/`pin-pud-pdn` on an alive bank (gpa*) return -EINVAL,
  which `samsung_pinconf_group_set()` ignores, so the DT describes a sleep
  state that's never applied. *From:* kernel #12.
- **L-25. A regmap without a read table exposes the whole block through
  debugfs.** On gs201 one PMU read crashed the phone; a PMU regmap should
  list the offsets it uses (`rd_table`/`wr_table`). *From:* kernel #15.
- **L-26. A hall sensor reported as `SW_LID` makes logind treat a folded
  phone as a closed lid** (suspend by default). Fine in the kernel; the
  device's userspace must handle it. *From:* kernel #12.
- **L-27. gs101 and gs201 numbers differ.** Interrupts, sysreg offsets and
  EINT numbering (gs201 skips EINT19) must come from that SoC's stock DT or
  Google's tree for it, never from the other SoC. *Check:* compare against
  stock's node (USI6 on gs201: GIC SPI 679, `0x1014`). *From:* kernel #10
  (correct).

- **L-52. Regulator nodes use the stock board's voltage, min = max.** A full
  selector range lets any consumer set any voltage; min = max also means
  registering writes nothing when the rail is already there. *Check:* the
  stock board dtsi's `regulator-min/max-microvolt`. *From:* kernel #27.
- **L-53. Identical driver data calls for a binding fallback, not a driver
  match.** A new SoC whose block is the same as an older one's gets
  `items: [new, old]` in the binding and no driver change; upstream expects
  it, and stock zumapro itself uses the zuma compatibles. *From:* kernel
  #29, #30, #31.
- **L-54. Diff a new SoC's stock dtsi against the file it includes.** That
  is where its overrides hide (zumapro's `phy_eusb_version` 0x701 over
  zuma's 0x700). *From:* kernel #29.
- **L-55. When a driver hands chip select to the SPI core, its own transfer
  path must stop driving it.** Otherwise it re-asserts on every transfer and
  overrides the core's `cs_off`. *From:* kernel #21.
- **L-56. Google sometimes ships more than one driver for the same chip;
  check which one the board builds** (`BUILD.bazel` under
  `kernel/devices/google/<board>`). Cheetah's and tegu's S3908 drivers
  power the supplies in opposite orders. *From:* kernel #26.
- **L-57. On arm64 a divide-by-zero guard changes nothing observable.**
  UDIV by zero returns 0 without trapping; disassemble before and after
  before calling such a patch a behaviour change or a hidden bug. *From:*
  kernel #25.
- **L-58. Google's `soc/gs` tree is one tree for every Pixel, and CMUCAL's
  `OSCCLK_* = 26 MHz` is nominal.** G4 builds from zuma sources, so a zuma
  citation for a G4 block can be right; and work out a PLL table entry
  before accepting a 26 MHz input (the real oscillator is 24.576 MHz).
  *From:* kernel #19, #23.
- **L-68. Narrowing a regulator to min = max writes nothing if the rail is
  already there.** `of_regulator` sets `apply_uV` for any range, but the
  core only moves a rail that is out of range, so a test made with the wider
  range still stands. *Check:* the measured voltage is an exact selector
  (min + n × step, n < n_voltages). *From:* kernel #27, round 3.
- **L-72. A chip id the vendor driver checks belongs in the compatible's
  match data, not in a DT property.** Google keeps `st,dchip_id` because one
  `st,fts` compatible serves two parts (`36 40` SALIXP, `36 48` ALIX).
  *Check:* grep the vendor header for every value the property takes; name
  the part (L-21). *From:* kernel #32.
- **L-74. A Tensor PMU binding without `syscon` is a safety property.**
  With `syscon`, a consumer that probes before the PMU driver gets a plain
  MMIO regmap, where PMU writes are silently ignored (AGENTS.md section 1);
  without it, the lookup defers until the SMC-backed regmap exists. *Check:*
  new Tensor PMU bindings and board nodes leave `syscon` out, even though
  stock DTs have it. *From:* kernel #31, round 2 (for #22).
- **L-75. Map every property of a cited vendor block to its upstream
  equivalent.** Stock tegu's touch `controller-data` also has
  `cs-clock-delay = <2>`, a 2 µs CS-to-clock wait, which upstream spells
  `spi-cs-setup-delay-ns`. *Check:* read the whole block, not only the
  property the PR cites, and say why each one is or isn't needed. *From:*
  kernel #21, round 2.
- **L-77. A vendor CAL's version switch is narrower than the function it
  sits in.** Google's eUSB2 init gates only the charge-pump bias clear on
  the revision; the rest runs for every version, so "0x701's sequence"
  overstated it. *Check:* list which writes are actually inside the version
  test before accepting a per-revision claim. *From:* kernel #33.
- **L-78. Balancing a shared PHY child's init count turns a once-per-boot
  init into one that runs every cycle.** *Check:* list every board that
  binds the wrapper, open DT PRs included, and ask for one boot with an
  unbind/bind on one of them (L-51). *From:* kernel #33 (Pixel 8 Pro).
- **L-79. Check linux-next for the same function before accepting a fix to
  a shared driver.** It showed #33's coming conflict, and an upstream change
  to cheetah's PIPE3 path that our next base move will bring (an L-51
  event). *From:* kernel #33.
- **L-83. A `Fixes:` id that CI calls `UNKNOWN_COMMIT_ID` may still be
  right.** CI's clone holds only our squashed base; a clone with the upstream
  remote resolves it. *Check:* `git log -1 <id>` there (or git.kernel.org),
  and confirm it introduced the code being fixed (extends L-30). *From:*
  kernel #33, round 2.
- **L-84. For a rebased series, compare the preimages as well as the
  results.** Identical blobs at both heads *and* both bases mean earlier
  object comparisons (L-8) still hold without a rebuild; matching results on
  a moved base mean they must be redone (extends L-69). *From:* kernel #33,
  round 2.
- **L-92. On Exynos CMUs the gate enable bit (CG_VAL, bit 21) means "on"
  only in manual mode.** MANUAL is bit 20, auto-gating bit 28, and the CMU's
  controller option has a global auto bit. *Check:* a read-only gate follows
  the mode, as Google's `ra_get_gate()` does, or the PR shows the handoff
  values; a vendor `HWACG_VCLK`/`_QCH` clock is a hint it's automatic.
  *From:* kernel #34 (a wrong read would leave the watchdogs unowned).
- **L-93. The unused-regulator cleanup acts only on regulators the DT
  describes without `regulator-always-on`.** Undescribed outputs are never
  switched off; a described one with no consumer is, about 30 s in.
  *Check:* "keeps it out of the cleanup" claims against `of_regulator.c` and
  `regulator_late_cleanup()`; inherited rails a board describes carry
  always-on until a consumer owns them. Extends C-1. *From:* kernel #35.
- **L-94. Find a vendor rail's consumer in the board dtsi's `&node {
  …-supply }` overrides, not from its schematic name.** G4's `L8M_USB` rails
  belong to Google's HSI0 power-domain helper, not the PHY. *From:* kernel
  #35.
- **L-95. A regulator node without voltage limits can't change state.** So
  "no other rail changed" on a new PMIC regulator driver comes down to which
  DT nodes have constraints. *From:* kernel #32, round 5.
- **L-96. A binding describes the hardware, not Linux's power policy.** No
  `power-domains: false` for a block stock gives a domain; match the sibling
  SoC's rule and put "no domain because firmware leaves it on" as a comment
  on the board node. *From:* kernel #40.
- **L-97. dtschema's core schema rejects a string property named
  `description`.** *Check:* when a binding types a vendor node, validate the
  vendor's exact node against the base's schemas and the head's, and ask
  whether the firmware needs what the schema makes the board drop. *From:*
  kernel #37, kernel #13.
- **L-98. A binding that requires a clock is usable only once the clock
  provider exports it.** *Check:* grep the SoC's clock header and the open
  clock PRs; name the missing provider as the next step. *From:* kernel #39.
- **L-99. Read the vendor driver's read path, not only its register map.**
  Google reports a fixed 22 °C on MAX77779 gauge firmware below 1.15, so the
  Temp register isn't trusted there. *From:* kernel #38.
- **L-100. Check a per-board scale value in three public places:** the board
  node or the vendor default, the battery model's name, and a design value
  it implies (`nDesignCap` × LSB = the rated mAh). *From:* kernel #38 (the
  2 mΩ shunt).
- **L-101. A Kconfig `default` tied to another symbol doesn't follow it
  under fragment merging,** because defconfig has already written "is not
  set". *Check:* the merged `.config`, made the way `bin/omamobile kernel`
  makes it. *From:* #23 (`DETECT_HUNG_TASK`).
- **L-113. Before accepting "Google's driver for <SoC> does X", find the
  driver that SoC's defconfig builds.** soc/gs has two USB PHY drivers
  matching `samsung,exynos-usbdrd-phy`; #42 cited `phy-exynos-usb3p1.c`, but
  zuma builds `CONFIG_PHY_EXYNOS_USBDRD_EUSB`, and the cited function only
  acts on USBCON v3.0 (zuma is 0x600). *Check:* the defconfig and module
  list, the module's files in `Kbuild`, then any version test in the cited
  function against the stock DT. Extends L-56 and L-77. *From:* kernel #42.
- **L-114. Reserve a stock address only if Google's dtsi gives the region
  a `reg`.** A `size` + `alloc-ranges` pool (`tui`, `mfc_fw`, `famodel`) has
  an address only because stock allocated it there on that boot. *From:*
  kernel #43.
- **L-115. When a PHY driver picks its settings from `clk_get_rate()`, the
  board's nominal fixed clocks become PHY configuration.**
  `phy-snps-eusb2.c` takes FSEL and the PLL divider from an exact-rate table,
  so a CAL nominal rate or a mux reading the other way decides whether the
  PHY initialises. *Check:* trace the clock to its root and ask for the mux
  selections and the `clk_summary` rate at handoff. Extends L-58. *From:*
  kernel #40.
- **L-116. A fix in a PHY's exit path also covers resume.** dwc3 calls
  `phy_exit()` on device-mode suspend and touches the core in
  `dwc3_phy_setup()` before `phy_init()`. *Check:* list the consumer's
  `phy_exit` callers and the first register access after each, and name the
  untested paths in the review. *From:* #23 tests 24-29, kernel #42.
- **L-117. A comment that says "all variants" is checked against every
  variant's vendor driver.** tegu ships three panels (`panel-gs-tg4a/b/c`);
  TG4A's porches and size differ. *Check:* the device's `BUILD.bazel` for the
  list, then each file. Extends L-56. *From:* kernel #46.
- **L-118. On Tensor, SYSIP_DAT0 0x00 means "normal" in Google's reboot
  driver** (`pixel-gs201-reboot.c`, `pixel-zuma-reboot.c` in
  kernel/google-modules/power/reset). Check reboot-mode claims against that
  file, not a contributor's harness. *From:* kernel #45.
- **L-119. A blank line before `Signed-off-by:` takes `Link:` out of the
  trailer block.** checkpatch doesn't flag it. *Check:* `git log -1
  --format=%B <c> | git interpret-trailers --parse` lists every intended
  trailer. *From:* kernel #35, round 10.
- **L-138. "Stop where stock repairs" covers every error poll on stock's
  path to the write decision.** FTM5's `fts_crc_check` polls config CRC
  events 0x20/0x21 and `fts_fw_update` reflashes on them; kernel #48 read
  and logged them, then scanned. *Check:* trace stock from probe to each
  write decision and list every event or status that leads to a repair; the
  driver must fail on each. Extends L-129 and L-108. *From:* kernel #48,
  round 12.
- **L-139. A PR that moves a compatible into its own binding is merged with
  every open PR that uses it as a fallback, and the schemas rebuilt.** #9
  moved `google,gs101-pmu` out of exynos-pmu.yaml while #47 added
  `[gs201-pmu, gs101-pmu]` there: both merged as text, and dt-validate failed
  on all four Google boards (`Duplicate compatible` from `dt-mk-schema`).
  *Check:* `git grep` open PR heads for the moved compatible, test-merge,
  `dt-mk-schema` and `dt-validate`. Extends L-126. *From:* kernel #9 with
  #47, round 12.
- **L-140. Compare an imported series against patchwork's mboxes when lore
  is blocked.** `https://patchwork.kernel.org/api/1.3/patches/?q=<term>`
  lists the message ids and `/project/<list>/patch/<msgid>/mbox/` gives each
  patch; compare each commit's lines per file, and where only hunks differ,
  apply to the base and compare the file. Extends L-62. *From:* kernel #9,
  round 12.
- **L-141. A gs101 power domain turned off without its DTZPC save needs the
  save before anything powers it back on.** André's driver skips the EL3
  save and restore for a `google,gs101-pd` without `samsung,dtzpc`, so the
  first consumer finds the block's TrustZone settings reset, and its
  registers SError. *Check:* a new `power-domains = <&pd_…>` on gs101 comes
  with `samsung,dtzpc` and the block's CMU in the same series. *From:*
  kernel #9, round 12.
- **L-142. An enable commit before the fix for a known-bad first version is
  a bisect hazard.** #7's raven enable commit came before the tuning that
  stopped boot-time thermal power-offs (3 of 4 boots). *Check:* when a body
  says "the first version did X on the phone", find that commit and ask for
  the board enable to land last. Extends L-123. *From:* kernel #7,
  round 12.
- **L-143. A Kconfig guard is checked by building with the guarded symbol
  off.** `kernel-pr-check` builds with our config (SPI on), and a
  single-object build compiles even a driver whose symbol is off. *Check:*
  `scripts/config -d SPI`, build the object, and `llvm-nm | grep -i spi` is
  empty. Extends L-20. *From:* kernel #8, round 12.
- **L-144. A vendor kernel may program what our read-only driver leaves
  alone.** Google's `gs_tmu_v2.c` sends every non-passive DT trip to ACPM as
  a TMU threshold; under our driver the hardware trip is whatever the
  bootloader set. "INIT doesn't change them" isn't "they're set": ask for the
  decoded values. Extends L-23. *From:* kernel #7, round 12.
- **L-151. An access table on shared driver data is checked against open
  PRs on every SoC that falls back to it.** Kernel #49 limited
  `google,zuma-pmu`'s regmap; Tensor G4 binds the same data through its
  fallback, and open #40 reads PMU `0x2a84` there, which the table left out:
  tegu's HSI0 clocks, and with them its only USB link, would have failed.
  *Check:* `git grep` the compatible's fallback users, then grep open PR heads
  for reads and writes through that regmap. *From:* kernel #49, round 13.
- **L-152. "Both SoCs use the same Google source" is proven by blob ids.**
  The gitiles JSON listing of `drivers/ufs/zuma/` gave identical blob ids on
  the Pixel 8 and Pixel 9a branches. *From:* kernel #51, round 13.
- **L-153. A per-function object diff normalises `adrp` pages, relocation
  addends and `.altinstr_replacement` before naming changed functions.** The
  raw diff of #42 showed 28 changed functions where one changed. Extends
  L-110. *From:* kernel #42, round 13.
- **L-163. A regmap table for a new block allows writes only to what its
  client driver writes,** not the vendor's register enum. #54's RTC table
  could write the PMIC's SMPL, WTSR and oscillator trim. Note that
  `update_bits` on a volatile register skips the write table when the bus has
  `reg_update_bits`. Extends L-25. *From:* kernel #54, round 14.
- **L-164. Re-validate an approved binding PR against every board merged
  since.** #13's `soc_compatible: false` rule began rejecting lynx's real node
  once #43 merged. *From:* kernel #13, round 14.
- **L-176. A new register written through a Tensor PMU regmap goes into
  that SoC's access table, and the write's return is checked.** #62 wrote
  `PMU_INFORM0` on `google,zuma-pmu`, whose `wr_table` (kernel #49) lists
  eight other registers; regmap returns -EIO before the SMC, and the PR
  dropped the return, so on the base it would silently do nothing while the
  phone test (from an older integration tree) showed it working. *Check:* for
  every new `regmap_write`/`update_bits` on a `pmu_secure` regmap, find the
  offset in `gs101-pmu.c`'s `*_pmu_registers` for that compatible, and ask
  for the blob id of `gs101-pmu.c` in the tree that produced the evidence.
  Extends L-151 and L-163. *From:* kernel #62, round 20.
- **L-177. Google publishes per-device device-tree repositories for the
  zuma-era phones, and their `*-isp-event-info.dtsi` gives every interrupt
  register's offset.** `kernel/devices/google/zuma` (`dts/zuma-isp.dtsi`,
  `zuma-isp-event-info.dtsi`) and `kernel/devices/google/tegu`
  (`dts/zuma-tegu-camera.dtsi`), with the bit names in `soc/gs`'s
  `include/dt-bindings/lwis/platform/zuma/isp_fe.h`. Kernel #63 attributed
  the zumapro LoCH layout to the HAL's register table; the event-info DT
  confirms the ISR/IMR offsets, and the camera DT gives the sensor power
  sequence the commit called "stock's". *Check:* for a "from the HAL"
  register claim, fetch the block's event-info node (`irq-src-reg`,
  `irq-mask-reg`) and the LWIS header; for a power sequence, the device's
  `*-camera.dtsi` `power-up-seqs`. Ask for the citation. Extends L-61 and
  L-152. *From:* kernel #63, round 20.
- **L-193. A CMU table's parent list is checked for registration, not only
  for order.** Kernel #73's three CMU_TOP G3D muxes name four
  `zumapro_shared*_d2/_d3` parents in the CAL's order, but nothing in
  `clk-zumapro.c` registers them, so a mux left on one of them is an orphan
  at 0 Hz; the boot evidence didn't show it because the GPU rates come from
  the local PLLs. *Check:* extract every registered name (second argument of
  `MUX*`/`DIV*`/`GATE`/`FFACTOR`/`FRATE`, third of `PLL`) and every name in
  `PNAME` lists and parent fields; the difference must be only board-level
  inputs (`oscclk`, `*-alt`, `*-tcxo`) and deliberate omissions, each named
  in the message. The CAL's `FIXEDRATE(PLL_SHAREDn_Dm, …)` lines are the
  factors to add. *From:* kernel #73 with #78, round 21.
- **L-208. An OPP table is checked against the stock cpufreq domain's
  limits, not only the firmware's rate list.** #87's little table ended at
  1950-1954 MHz, above Google's `max-freq = <1950000>`, and `clk-acpm`
  forwards any rate. *Check:* each cluster's top and bottom OPP against
  `cpufreq_domainN` `min-freq`/`max-freq` in the SoC's `*-cpu.dtsi`; points a
  few MHz apart are table entries, not frequencies. Extends L-52. *From:*
  kernel #87, round 22.
- **L-209. Google's ACPM DVFS ids come from the `acpm_dvfs_id` enum, not
  `acpm_vclk_list`.** The zuma enum has 17 domains with AOC at 15; the list
  leaves AOC out, and counting it would have called #84's ids wrong.
  *Check:* count the enum from `MIF = ACPM_VCLK_TYPE`. *From:* kernel #84,
  round 22 (a near miss).
- **L-210. A register value that "follows the vendor's formula" is checked
  by recomputing the formula for that panel.** `dsim_calc_underrun()`
  reproduces cheetah's ABL pair but not tegu's, so #88's 120 Hz value left
  0.98 ms of slack, not 2.46 ms. *Check:* the vendor function with the panel
  driver's `underrun_param`, DSC and lane rate, at every rate. Extends L-61.
  *From:* kernel #88, round 22.
- **L-211. A board that names one panel for a model shipped with several
  needs the identification path.** Tegu's connector lists three panels chosen
  by ABL's `panel_name`, with different rate-switch sequences. *Check:* the
  device's `*-connector.dtsi` and `BUILD.bazel` panel list; ask owners for the
  panel name, and gate commands in userspace where the kernel can't read the
  ID. Extends L-117 and L-169. *From:* kernel #90, round 22.
- **L-212. A panel backlight's range matches the vendor's brightness
  capability.** #89 exposed 0-4095 with a 4095 default; Google's normal range
  ends at 3628, and 0x0FFF is HBM2, pushed on the first wake. *Check:*
  `brightness_capability` and `default_brightness` in the vendor panel file
  against the driver's `max` and default. *From:* kernel #89, round 22.
- **L-213. A driver that changes PMIC or charger state on userspace request
  restores it at `.shutdown` and reads it back at probe.** #92's inhibit
  survived reboot, and probe's "auto" default made `auto` a no-op. *Check:*
  for every write path, what the next boot finds and how userspace undoes it.
  *From:* kernel #92, round 22.


## The gates themselves

- **L-311. The same test failing across unrelated PRs within minutes points at
  the CI runner's packages, not the diffs.** On 2026-10-29 Arch moved
  `simdjson` to 5.0.8 before `nodejs` was rebuilt, so from about 01:55Z node
  couldn't load `libsimdjson.so.34` and four docs-only PRs failed the Node
  package tests (fixed by #139). *Check:* `gh run list --workflow checks.yml`
  across branches for a shared start time, `gh run view --log-failed | grep
  'error while loading shared libraries'`, and compare the install step's
  package versions in a passing and a failing run. Extends L-42. *From:* #131,
  #136, #137, #138, round 28.
- **L-310. #129's prebuilt option check can't see a behaviour-only change.**
  #135 changed the fingerprint bridge's scaling and call order with no new
  option, so its test passed with main's stale prebuilt. *Check:* rebuild the
  base source and confirm it matches the installed prebuilt byte for byte,
  then build the head and confirm the hashes differ; better, have the Makefile
  embed the source's sha256 and `test/all` compare it. Extends L-268. *From:*
  #135, round 28.
- **L-309. `dt-validate` runs on the host from a scratch venv when the
  container has no dtschema.** `python3 -m venv $S/venv && $S/venv/bin/pip
  install dtschema` gave working `dt-mk-schema` and `dt-validate`. *Check:*
  build the DTB in the container, validate base and head on the host, and feed
  a known failure to prove the validator bites; that turns "bindings unchecked
  until CI" into a local check. Extends L-103 and L-156. *From:* kernel #98,
  round 27.
- **L-293. An empty diff is checked for empty inputs.** Comparing the gs201
  DTBs before and after kernel #123 with the host's `dtc` printed no
  difference, because the host has no `dtc` and both sides decompiled to
  nothing. *Check:* confirm each side of a comparison is non-empty (or use the
  build's own `scripts/dtc/dtc`) before reading "no change". Extends L-102.
  *From:* kernel #123, 2026-10-28.
- **L-288. A stack with several tops is gated once on a combined commit.**
  Combine the heads with `git merge-tree --write-tree` and `commit-tree` into
  one commit (the gate skips merge commits in its commit checks) and gate
  that, which covers how the tops interact; gate the landing PR on its own
  too, since its DTB differs. Extends L-196. *From:* the tegu stack, round 26.
- **L-281. A re-push can leave CI at `action_required`, so "rebased, CI should
  be green" means nothing until the run is approved.** #79's re-push sat with
  no checks reported. *Check:* `gh run list --branch <head>` on every
  follow-up round, and say in the draft that the maintainer will approve the
  run. Extends L-59 and L-38. *From:* #79, round 26.
- **L-271. An AI author address on an early commit of a squash-merged PR lands
  on main as `Co-authored-by:`,** even after later commits fix the identity,
  and `tools/pr-check` checks only `Signed-off-by:`. *Check:* `git log
  --format='%an <%ae>' base..head` on omarchy-mobile PRs; ask for a
  self-squash or strip the trailer at merge. *From:* #98, round 25.
- **L-262. An AGENTS or CONTRIBUTING line links only tracked files.** #125
  linked `docs/HANDOFF.md`, which doesn't exist, and a script under the
  gitignored `logs/`. *Check:* `git ls-files --error-unmatch <path>` for every
  path the line names; `tools/pr-check` could do this for both files. *From:*
  #125, round 25.
- **L-246. A base build is asked only for targets the base has, with `make
  -k`, and a stopped base build is reported, never hidden.** On kernel #108
  the gate asked the base for a new board's DTB it had no source for; make
  stopped and `|| true` hid it, so how far the base got depended on `-j`,
  existing warnings on unbuilt boards (husky's eUSB2 supplies) read as new,
  and a message the new board's siblings already carry (`soc_id`) counted as
  new. *Check:* a new board's messages are compared with its siblings' at the
  base. Fixed in `tools/kernel-pr-check` (#119) and at the cause (kernel
  #121). Extends L-30. *From:* kernel #108, 2026-10-28.
- **L-247. Normalise `adrp` symbol labels and trailing blanks before naming
  changed functions.** `llvm-objdump -r` labels an `adrp` page with whichever
  symbol starts it, so any layout shift renames it: #94's first diff named
  five untouched functions. *Check:* `/adrp/ s/ <[^>]*>//; s/[[:space:]]+$//`
  in the normaliser. Extends L-153. *From:* kernel #94, round 23.
- **L-30. A gate failure can be the tool's own.** `tools/kernel-pr-check`
  compared device-tree warnings with their line numbers, so a PR that added
  two comment lines above an existing warning failed as if it were new
  (fixed 2026-10-22: positions are stripped). *Check:* reproduce any gate
  failure by hand before blaming the PR, and report a tool fault as a
  finding for the maintainer. *From:* kernel #11, round 2.

- **L-38. "No checks reported" is not a pass.** A pull request pushed
  before a CI workflow reached its base branch never ran it. *Check:*
  compare the push time with the workflow commit; until CI runs, call its
  checks (`dtbs_check`, the package suites) unchecked. *From:* kernel #10,
  #12.

- **L-40. Tools resolve their path arguments before they `cd`.** Our own
  `kernel-pr-check` changed into `-C` and then passed the same relative path
  on, so CI's `-C linux` looked for `linux/linux` and failed every kernel
  PR; a relative `--build` would have built, and deleted, inside the kernel
  checkout. *Check:* call a tool from another directory with relative
  arguments, as CI does, and test that once. *From:* #30, kernel #12.
- **L-41. A gate that wraps another tool must show why that tool failed.**
  Filtering a sub-tool's output to its `not ok` lines hid a `cd` error, so
  CI failed with no reason. *Check:* when a CI failure has no `not ok` line,
  reproduce it the way the workflow runs it before blaming the PR (L-30).
  *From:* #30, kernel #12.
- **L-42. A package test that fails on a PR that doesn't touch the package
  is reproduced on main first.** #24's red CI was a race in
  `omamobile-shell`'s portal test (a log read then truncated, losing a line
  written between), and a retry block that exited silently. *From:* #24,
  round 3.

- **L-59. "No checks reported" can mean CI is waiting for approval.** A
  first-time contributor's runs stop at `action_required` until the
  maintainer approves them (`gh run list --status action_required`). Approve,
  then judge (extends L-38). *From:* kernel #18-#31.
- **L-60. Mesa changes are checked through the generated packers.** Mesa has
  no package test, so CI's green says nothing about it: run `gen_pack.py` on
  each touched `vN.xml` before and after, and grep every caller of a changed
  builder. *From:* #32.
- **L-64. A package file `cmp`-tested against cheetah's copy can carry
  checks the original lacks.** felix's test caught `HandlePowerKey=poweroff`;
  cheetah's own test passed with it. *Check:* mutation-test the original too,
  and give both packages the content checks. *From:* #33.
- **L-69. Compare a renumbered or reworded patch series by the source it
  produces.** Apply the old and the new series to two fresh copies of the
  release and `diff -r` the trees: empty means the earlier review (and any
  test of the earlier build) still applies (L-45 for package patches).
  *From:* #32, round 2.
- **L-70. A gate's "N device trees" can leave out a new overlay.** Neither
  `kernel-pr-check` nor CI built `.dtso` files until kernel #32. *Check:*
  compile every touched overlay with `-@`, apply it to its base with
  `fdtoverlay`, and `dt-validate` the result (`kernel-pr-check --build` now
  does this). *From:* kernel #32.
- **L-73. Gate a PR on its merge, not only on its head, when another PR
  landed in the same files after it branched.** CI checks out the PR head,
  so #20 was never built with #27's S2MPG12 changes. *Check:* `git
  merge-tree --write-tree`, `git commit-tree`, then `kernel-pr-check
  --build` on that commit; after a batch of merges, gate the whole new
  range once. *From:* kernel #20, round 2.
- **L-80. checkpatch reported every compatible a PR documents itself as
  undocumented, and showed warnings only as a count.** It read bindings
  from the clone's checked-out tree, not the commit under test. Fixed:
  `kernel-pr-check` now gives checkpatch each commit's own bindings and
  MAINTAINERS, and prints the warnings (extends L-30). *From:* kernel #21,
  #28, #33, rounds 1 and 2.
- **L-102. Feed a gate a known failure.** The device-tree comparison kept
  only lines saying "warning" or "error"; dt-validate's say neither, so
  every "dtbs_check, no new warnings" (ours and CI's) was blind until
  476901b. A reused `--build` OUT also kept an earlier tree's processed
  schema. Extends L-30. *From:* kernel #13 (found by its author).
- **L-103. A passing gate log can hide a skipped check.** The project
  container has no dtschema, so its runs print "# no dt-validate … skipped"
  and still pass. *Check:* grep the log for `SKIP` and `skipped` before
  quoting "dtbs_check passes"; run it where dtschema is installed. *From:*
  round 9.
- **L-120. For a new board, `kernel-pr-check` counts every message the
  board inherits as new.** The base has no such DTB, so gs201.dtsi's four
  undocumented compatibles failed lynx. *Check:* `dt-validate -m` a sibling
  board on the same dtsi at the base and subtract its messages before calling
  one new (the tool could do this itself). Extends L-30. *From:* kernel #43.
- **L-121. When a test merge conflicts, check which tree it used before
  asking anyone to rebase.** Our gs201 bindings branch "conflicted" with
  zuma only on the unrelated local integration history; against
  `github/omamobile` and #13 it merged cleanly. *Check:* `git merge-base` and
  `git merge-tree` against the published branch and each open PR's head.
  Extends L-104. *From:* kernel #13, round 10.
- **L-122. "Same tree as before" is checked with the tree object.** `git
  rev-parse A^{tree} B^{tree}` on the same base carries the earlier boot and
  builds over to a reworded commit. Extends L-45 and L-84. *From:* kernel
  #41, #35, round 10.
- **L-145. CI checks a PR that edits a gate with that edit.** `checks.yml`
  runs the PR's own `tools/pr-check`, so #41's new MAC exemption passed
  itself. *Check:* run main's gate too, and review an exemption as a policy
  change: test a line that mixes an exempt value with a real one. (Ours
  dropped whole lines for the all-zeros exemption; since round 12 each
  address is judged on its own.) Extends L-30. *From:* #41, round 12.
- **L-146. CI doesn't parse UCM:** the runner has no `alsaucm`, and the test
  skips silently. *Check:* parse UCM changes locally with `alsaucm` on a
  virtual card, once per `If` branch. Extends L-103. *From:* #41,
  round 12.
- **L-154. `kernel-pr-check` builds the PR's own commits against their
  merge base, so a fix that lands on the base after a PR branched never
  reaches its CI until the PR is rebased.** A fresh `base.sha` doesn't change
  the merge base, and a re-run replays the event's stale one. *Check:* gate
  the PR rebased onto the current base (L-73) before asking for a rebase, and
  say whether the rebase is needed for the code or only for CI. *From:*
  kernel #43, round 13.
- **L-155. A gate runs under every awk it will meet.** Round 12's MAC regex
  used `(…){5}`, which mawk 1.3.4 (Debian, Ubuntu, our build container)
  rejects, so `pr-check` failed every change there while CI's gawk passed.
  *Check:* after any edit to a gate, run its tests in `omamobile-build:24.04`
  too. Extends L-30. *From:* round 13.
- **L-156. A bindings-only PR gets no `dtbs_check`** from CI or
  `kernel-pr-check` ("device trees: none touched"), so no board's DTB is
  checked against the new schema. *Check:* validate the affected boards'
  DTBs by hand; dtschema's schema checks run in the container with a stub
  `libfdt`, only `dt-validate` needs the real one. Extends L-126. *From:*
  kernel #51, round 13.
- **L-178. A rejected property in a dt-validate known-failure feed can read
  "False schema does not allow 0", without the property's name.** A `prop:
  false` under `then:` reports the value, not the key, so grepping the output
  for the property name says "not rejected" when it was. *Check:* grep the
  feed's output by node name and compare base against head line by line.
  Extends L-102. *From:* kernel #63, round 20.
- **L-179. Neither CI nor `kernel-pr-check` builds a series commit by
  commit, and kernel PRs land commit by commit.** CONTRIBUTING §6.2 says each
  commit must build; the gate builds the head's touched files only. *Check:*
  for a rebase-merged series, check out each commit in a worktree on the
  host and build that commit's touched objects in the container (a
  worktree's `.git` file points at the host path, so `git checkout` inside
  the container fails). Done by hand for #63's 14 commits. Extends L-123.
  *From:* kernel #63, round 20.
- **L-180. The gate's test-merge commits don't exist in the clone,** since
  the container builds them in its own copy, so a later schema or DTB
  comparison "on the test merge" makes its own tree with `git merge-tree
  --write-tree` (`git archive` takes a tree id). *From:* round 20.
- **L-181. Grep a CI job's log for the gate's own `ok -`/`not ok` lines, not
  for the check's name.** The kernel job is named "Kernel (sign-offs,
  checkpatch, W=1, dtbs_check)" and `gh run view --log` prefixes every line
  with it, so a grep for `dtbs_check` matches everything and hides whether
  dt-validate ran. Extends L-103. *From:* round 20.
- **L-194. A review's clone goes on disk, and a gate's worktree is sparse:
  the scratch `/tmp` is a 16 GB tmpfs shared by every parallel review.** A
  `--depth 60` clone of the SM8150 tree for #52 and three full checkouts of
  omarchy-mobile (about 1 GB each, `phone/screenshots` and all) each filled
  it, and a command of another review lost its output. *Check:* `df -h` the
  scratch volume before any clone or build over a few hundred MB; trees go
  under `~/android/mainline/wt-review-<topic>`; a gate's checkout is `git
  worktree add --no-checkout --detach`, `git sparse-checkout set --cone bin
  device initramfs tests packages/<the ones the tests compare>`, `reset
  --hard` (3.5 MB, and `tests/storage-guard`, `tests/simplefb-trigger` and
  the package tests all run from it). *From:* #52, round 21.
- **L-195. A follow-up round re-gates the merge first, even when the new
  commits only touch docs, because the base moves under the PR between
  rounds.** #82's first review found "none of the moved commits touch
  `bin/omamobile`"; four hours later the Pixel 6 Pro port had landed in
  `initramfs_config`, the PR went `CONFLICTING`, and that means no CI at all
  (L-165). *Check:* `gh pr view N --json mergeable` and `git merge-tree
  --write-tree origin/main <head>` at the start of every round; on a
  conflict, resolve it in a scratch worktree, run the suites and the cheetah
  comparison on the result, and hand the contributor the resolution. Extends
  L-34, L-73 and L-165. *From:* #82, round 20.
- **L-214. Stacked or un-rebased heads are gated on today's main and the
  combined tree, not pairwise.** #87's CI failed on a compatible that its
  sibling #86 documents (merged, zero messages); #72, left un-rebased while
  #70 and #78 were, conflicted with main and got no CI, and `merge-tree`
  between heads on different bases reported conflicts that weren't real.
  *Check:* `git merge-base` and `git merge-tree origin/main <head>` per PR
  first; `git grep` open PR heads for a compatible a failure names; give the
  merge order and the resolved hunk. Extends L-73, L-104, L-165 and L-196.
  *From:* kernel #87 with #86, #72, round 22.


## Reviews and merging

- **L-312. With `squash_merge_commit_message: COMMIT_MESSAGES`, a squash
  carries every commit's body, including wording the review rejected.** #125's
  first commit says "mark B successful on the first good boot after a flash",
  the standing permission round 25 turned down. *Check:* `gh api repos/<r>
  --jq .squash_merge_commit_message`, then read each commit body on a safety
  PR; any body the final text contradicts means writing the squash body by
  hand. Extends L-279. *From:* #125, round 27.
- **L-292. Merge only after every check has finished, not on the first
  green.** #126 was merged with the policy job passed and the tests job still
  pending; the tests passed afterwards, but the merge didn't know that.
  *Check:* `gh pr checks N` shows no pending job (or `gh run watch
  --exit-status`) before `gh pr merge`. Extends C-15. *From:* #126,
  2026-10-28.
- **L-291. When the bottom of a squash-merged stack moves after we've posted a
  cherry-pick plan, re-simulate the plan.** #115 and #117 still carry #99's
  old head, and #117's list grew from two commits to three. *Check:* squash
  the new bottom onto main, cherry-pick the listed commits, and diff the
  result against the top head, expecting only the bottom's new change. Extends
  L-195 and L-214. *From:* #99, #115, #117, round 26.
- **L-287. A silent re-push is diffed per PR before any reply.** The tegu
  stack's 20:38Z push looked like an answer to everything but carried only the
  Makefile resolution; #106's and #122's points were untouched. *Check:* `git
  range-diff` against the last round's refs, then one status line per open
  point rather than a re-post. Extends L-183 and L-248. *From:* kernel #80 to
  #122, round 26.
- **L-279. A PR that carries a merged fix PR's commits is diffed against main,
  and its squash body written by hand.** #101 still carried #107's audio
  commits; `git diff origin/main <head> -- packages/omamobile-audio` was
  empty, but GitHub's default squash body would still list "omamobile-audio
  0.5.5" under the fingerprint title. *Check:* after the fix PR merges, diff
  each rider against main for the fix's package. Extends L-255. *From:* #101,
  round 26.
- **L-278. A re-pushed stack with identical sources is proved once.** Where
  every PR's tree id equals the old head's, the review is tree ids plus a
  range-diff per PR, then one gate on a scratch rebase of the top; DTB hashes
  of old head and rebased head carry the earlier content review over. *From:*
  the tegu stack, round 25 (12 heads, one message change).
- **L-277. A promised userspace guard is checked in every open package for
  that device, other owners' included.** Kernel #90 was accepted on W4HO's
  promise that `allow_tx` is set only for `google-tg4c`; h4rkl's #74 sets
  `allow_tx=1` for every panel, and our #74 review missed it (C-18). *Check:*
  `git grep -n '<option>'` across the open omarchy-mobile PR heads for
  `packages/omamobile-device-<codename>`. Extends L-219. *From:* kernel #90
  with #74, round 25.
- **L-275. Squash-merged stacks always conflict on the package `version` file,
  and a PR carrying a merged fix's commits can't simply be rebased.** #115
  carried #107's three commits, which main has as one squash. *Check:*
  simulate the chain with `git merge-tree --write-tree` and `commit-tree`, one
  squash after another, then hand over a cherry-pick of only the PR's own
  commits, verified to reproduce the head's package tree. Extends L-39, L-214
  and L-255. *From:* #115 and #117, round 25.
- **L-274. A PR we marked "nothing more needed" is checked push by push from
  the head our comment named.** Kernel #82 was pushed at 21:43Z without a
  comment and again at 01:04Z; comparing only the last two heads would skip
  the one we reviewed. *Check:* list every force-push event since our comment
  and range-diff each. Extends L-34 and L-166. *From:* kernel #82, round 25.
- **L-270. An "or keep X and say so" we offer must pass the gates the same
  review names.** Round 24 on kernel #98 asked for the eight required
  supplies, which `dtbs_check` enforces, and also offered keeping the fixed
  regulator, which can't pass CONTRIBUTING's no-new-warnings rule. *Check:*
  run each alternative in a draft past every blocking point in the same draft
  and §6's gates. Extends L-229; see C-16. *From:* kernel #98, round 25.
- **L-265. A bare `#N` links to the repository the comment is in.** W4HO's
  tables on issue #28 named kernel PRs as `#119` and `#122`, which link to an
  omarchy-mobile PR and issue. *Check:* write
  `derekross/linux-omarchy-mobile#N` when a comment names the other
  repository's PRs, and read cross-repository tables in a thread with that in
  mind. *From:* issue #28, round 25.
- **L-263. A squash title that names a package version must agree with the
  `version` file it lands.** #112 landed as "device-raven 0.1.26" with the
  file still at 0.1.25, so a publish would reuse a version with new contents
  (fixed by #126). *Check:* on each squash merge, and on the next PR for that
  package, compare `git show origin/main:packages/<p>/version` with the last
  squash subject that touched it. Extends L-12 and L-217. *From:* #112 with
  #113, round 25.
- **L-248. A reply that says "pushed" is checked against that PR's own head,
  not the stack's.** #87's reply described fixes that existed only below #90
  and #96; its own branch stayed put, with green CI. *Check:* `git ls-remote
  <remote> refs/pull/N/head` and `git range-diff` per PR; when every commit
  is `=`, grep the open heads above it for the fixed commits. Extends L-166
  and L-183. *From:* kernel #87, round 23.
- **L-249. A "tested blob" from an unpublished tree can be a blob from our
  own earlier review ref.** #88's and #89's tested files were the previous
  heads' blobs. *Check:* `git cat-file -t <blob>`, then `git diff <blob>
  <new head>:<path>`. Extends L-131. *From:* kernel #88, #89, round 23.
- **L-250. A merge plan carried over from an earlier round is re-read
  against the rules that landed since.** Round 20 planned #71's Pixel 7 Pro
  check after the merge; CONTRIBUTING §6.2 then made it a before-merge rule.
  *Check:* `git log --since=<our last comment> -- CONTRIBUTING.md AGENTS.md`,
  then every "merge, then check" in the plan. Extends L-31 and L-185.
  *From:* kernel #71, round 23.
- **L-251. When a stack is re-pushed onto one line, the landing PR moves to
  the top, and the boot is asked of the top.** With #84, #89 and #95 merged,
  #80-#96 became one chain; a boot of #80 alone would test a tree that never
  lands. *Check:* `git log base..head` per PR; ask for evidence on the commit
  that will be merged. Extends L-196. *From:* kernel #80-#96, round 24.
- **L-252. A "sync to the phone's tree" commit is diffed against the base
  for deletions the series never meant.** #115's last commit overwrote two
  Kconfig files with a private tree's copies and dropped two other phones'
  drivers. *Check:* `git diff --stat base head` against the PR's feature
  list, and `git log -S'<symbol>'` for every removed `config` line. *From:*
  kernel #115, round 24.
- **L-253. One contributor's board PRs that all append to one DTS conflict
  pairwise: build the combined resolution once and hand over an order.**
  *Check:* `git merge-tree` per pair; cherry-pick all onto the base, build
  and `dt-validate` that tree, and ask for a stack next time. Extends L-104
  and L-196. *From:* kernel #111-#116, round 24.
- **L-254. Scratch merges in the shared kernel clone run with rerere off.**
  The clone has `rerere.enabled=true`, so a review's scratch cherry-picks
  recorded resolutions (one wrong) that a later real merge could replay.
  *Check:* `git -c rerere.enabled=false cherry-pick|merge …`, or `git
  merge-tree` only. Extends L-43 and L-127. *From:* round 24.
- **L-255. A fix copied onto several squash-merged PRs merges first.**
  #107's audio 0.5.5 rode on #100, #101, #115 and #117; squashing any of
  those first lands the bump under the wrong title. *Check:* `git rev-parse
  <head>:packages/<p>` across the PRs, then merge the fix PR first. Extends
  L-12 and L-217. *From:* #107, round 24.
- **L-31. Our review requests must agree with CONTRIBUTING.** Round one of
  kernel #11 asked for a squash that §6.2's "disabled, then a separate
  enabling commit" rule contradicted. Since 2026-10-22 §6.2 allows a board
  node already proven on a same-SoC phone to be added enabled in one
  commit; otherwise, when a request and a rule disagree, fix one of them.
  *From:* kernel #11.
- **L-34. Before a second round, check the head moved.** Compare the PR's
  head with the `commit_id` of our last review and read the timeline:
  comments and cross-references also change the "updated" time. Answers
  given only in comments must still land in the files. *From:* #24,
  round 2.
- **L-39. A rebase or squash merge gives new commit ids, so a stacked PR
  must be rebased before it merges.** After #11 was rebase-merged, #12 still
  carried #11's old commit underneath and couldn't merge as it stood. *Check:*
  when merging a PR another one is stacked on, ask the second one's author to
  rebase onto the branch, and merge in order. *From:* kernel #11 and #12.

- **L-43. Parallel reviewers use unique ref names.** They share the kernel
  clone, and one deleted another's `review/pr12` mid-review. *Check:* name
  refs `review/prN-<round>` (now `review/prN-rR-<topic>`, L-127) and pass commit ids to the gates. *From:* kernel
  #12, round 3.
- **L-44. A staged descriptor's refusal depends on the tooling PRs in
  flight.** Tegu added `SOC_COMPATIBLE` while #27 was about to make either
  key acceptable, so merging both would have made tegu installable without
  the AVB footers its bootloader needs. *Check:* test a staged descriptor
  against the heads of open PRs that touch `bin/omamobile` or
  `tools/install-phone`. *From:* #24 with #27.
- **L-71. Our requests say which repository each piece goes in.** "A kernel
  PR … with an overlay that enables it" put a bring-up overlay in the kernel,
  against CONTRIBUTING §6.1 (extends L-31). *From:* issue #3 and kernel #32.
- **L-104. Run `git merge-tree` across every pair of open PRs that touch the
  same files,** one contributor's parallel PRs included, and give the merge
  order in each review. Look for duplicate mechanisms too (#34's
  `ro_gate_clks` beside #40's private read-only gates). Extends L-39 and
  L-73. *From:* kernel #34 with #40, #37 with #39.
- **L-105. When a contributor writes a private driver after we asked for
  the common helper, find what pushed them off it** (here a PMU check that
  can't defer inside the `__init` probe) and answer that, not only the
  request again. *From:* kernel #40.
- **L-123. A fix-up commit on a rebase-merged PR is folded in.** Kernel
  PRs land commit by commit, so #34's watchdog commit would have landed with
  the CG_VAL-only read (a bisect could stop there with the watchdogs
  unowned), and #38's driver commit claiming temperature. *Check:* `git
  range-diff` for a new commit that only changes lines an earlier commit of
  the same PR added; read the earlier messages against the new head.
  *From:* kernel #34, #35, #38, round 10.
- **L-124. Before asking again, check whether the contributor's report
  crossed our post.** The 23:11Z husky report answered round 9 before round 9
  was posted. *Check:* compare comment times with our post time. *From:*
  kernel #33, round 10.
- **L-125. Check a whitespace nit by column, not by counting tabs.**
  `expand` the hunk with its neighbours: `google,zumapro.h` gives every name
  of that length two tabs. *From:* kernel #34, round 10 (withdrawn nit).
- **L-126. A binding PR's SoC condition can reject another open board's
  DTB without a textual conflict.** #13's `soc_compatible: false` for
  non-zuma boards fails lynx (gs201 IPOP). *Check:* merge each open board PR
  with each open binding PR on the same schema and run `CHECK_DTBS=y`.
  Extends L-104. *From:* kernel #43 with #13 and #37.
- **L-127. Parallel reviewers suffix refs with their topic, and delete only
  refs they created.** In round 10 several used `review/prN-r10`, and one
  deleted (then restored) refs another was using. *Check:*
  `review/prN-r<round>-<topic>`; clean up from a list recorded at fetch time.
  Extends L-43. *From:* round 10.
- **L-147. Before re-checking an earlier round's request, re-derive it from
  what has landed since.** Round 11 asked #22 to gate `aoc-stage s2mpu` on a
  `tzpc` restore, from the tool's header alone; raven's plans (#41) show
  that SMC hung the SoC and that the `pd` stage made the read safe, so the
  gate could only be passed by a known hang (C-6). *Check:* for every safety
  gate we asked for, find the plan row it rests on and confirm the step it
  requires passed there. Extends L-31. *From:* #22, round 12.
- **L-148. `git merge-tree` exiting 1 can mean a missing ref, not a
  conflict.** Another reviewer deleted their refs mid-review. *Check:* read
  the message, and use commit ids for other reviewers' PRs. Extends L-127.
  *From:* round 12.
- **L-165. "No checks reported" can mean the PR conflicts with its base,**
  since GitHub runs no `pull_request` workflow then. *From:* kernel #53,
  round 14.
- **L-166. When a PR is force-pushed after its phone test, diff the old head
  against the new.** GraphQL's `HeadRefForcePushedEvent.beforeCommit` gives
  the old id; REST's timeline omits it. *From:* kernel #54, round 14.
- **L-167. Posting scripts split drafts by heading, never by line number,
  and each posted file is checked first.** Round 13's line ranges put #49's
  last bullet at the top of #50's comment. *From:* round 13 (found in 14).
- **L-182. "My merged PR isn't on the branch" after a rebase merge is
  checked by patch-id and the branch's push events, not by ancestor.** A
  rebase merge lands the commit under a new id, so the PR's head is never an
  ancestor and GitHub shows no merge commit; two merged commits came back as
  new PRs (kernel #67, #68), and merging a resubmission onto the base gives
  the base's own tree, which the gate can't tell from a real change.
  *Check:* `git show <merged id> | git patch-id` against the resubmission;
  `gh api repos/<r>/branches/<b>` for the head and `events` (or
  `activity?ref=`) for pushes since the merge, all fast-forwards; `git
  merge-base --is-ancestor <merge> <tip>`; and `git merge-tree --write-tree
  base head` compared with `base^{tree}`. Extends L-39. *From:* kernel #67,
  #68, round 20.
- **L-183. "I took the point" is checked against the code, not the reply,
  one request at a time.** #57's new head changed only its subject and
  message while the comment said the blocking request was taken; #40's
  rework followed a merged sibling's convention (#34's TOP table) and so
  dropped one offset we had asked for, without a word. *Check:* for every
  force-push after a review, `git diff <old head> <new head> -- <dir>` per
  touched file (L-166 gives the old id), tick each request off against that
  diff, and for a dropped one name the merged precedent and say which wins.
  Extends L-34, L-123 and L-166. *From:* kernel #57, #40, round 20.
- **L-184. When we tell a contributor how to resolve a conflict, derive the
  resolution from the file, and better, hand over the resolved hunk.** Rounds
  18 and 19 said "keep both lines in both lists" for
  `samsung,exynos-sysreg.yaml`, but the new compatible lives in the `clocks:
  false` branch, and adding it to the clocks-required list would have failed
  husky; the contributor caught it. *Check:* build the resolved file (`git
  merge-tree` tree plus the PR's hunk), run the schema and board validation
  on it, and attach it. Extends L-31 and L-104. *From:* kernel #39 with #60,
  round 20.
- **L-185. A rule can change between our comment and the contributor's
  push.** AGENTS' `userdata`-through-`install-phone` exception (`10daf5f`)
  landed after our follow-up on #25 and before its next push, so a PR that
  did everything asked now broke a rule its author never saw. *Check:* `git
  log --since=<our last comment> -- AGENTS.md CONTRIBUTING.md` before judging
  a re-push, and say in the comment which rule is new. Extends L-31 and
  L-124. *From:* #25, round 20.
- **L-196. A stack of N PRs is gated once at its top and read N times.**
  Kernel #73-#79 are one linear chain on today's base; `kernel-pr-check
  --build --merge` on each head rebuilt the same objects seven times, while
  the per-commit builds (L-179) and the parent-name audit (L-193) on the top
  head covered everything in one pass. *Check:* `git log base..headN` for
  each PR to prove the chain, gate the top head, build the chain commit by
  commit, and give one merge plan (merge the top PR, close the rest) next to
  the one-by-one order. *From:* kernel #73-#79, round 21.
- **L-197. A status word we ask for is checked against the legend and the
  site's parser before we post it.** Our "the matrix row says 'in review'"
  on #52 produced a row whose every cell the website renders as "no"
  (`devices.ts` `parseCell`). *Check:* `grep` the legend in DEVICES.md and
  `STATUS_WORDS` in `omamobile-website/src/lib/devices.ts` for any status
  wording we prescribe. Extends L-31 and L-66. *From:* #52, round 21.
- **L-198. When the contributor says the record doesn't exist, the file
  records that it doesn't, and a baseline taken over an unexplained change
  is downgraded, not adopted.** #35's reply gave a negative record (no date,
  tool, partition list or boot list) and accepted the hold, while the plan
  still said "the new baseline" and "a Linux slot A boot does not run the
  modem stack". *Check:* the negative facts land in NOTES and Risks in the
  contributor's words; the unexplained copy is "current contents, cause
  unknown"; the baseline becomes the backup after the next stock boot.
  Extends L-34, L-168 and L-186. *From:* #35, round 21.
- **L-199. A read point we prescribe is named relative to the driver's last
  write, not to a phase.** "Right after link-up, before MHI power-up" under
  ath11k is after `ath11k_pci_soc_global_reset()`, and the read hung; the
  same phase on stock (`linkup`, no reset) read fine six times. *Check:*
  before asking for a register read, list the driver's writes to the block
  up to that point in both trees, and name the read as "after write X,
  before write Y". Extends L-135 and C-7. *From:* issue #36, round 21.
- **L-215. A vendor-kernel A/B outranks host-side hypotheses.** On issue
  #36 the stock kernel stalled exactly like mainline, retiring every
  host-driver difference at once, while we were still asking for host-side
  changes. *Check:* before asking for one, ask whether the stock kernel ran in
  the failing shape, and list what differs between the stock run that works
  and the one that doesn't. Extends L-204. *From:* issue #36, round 22.
  (Corrected 2026-10-28, C-12: "a vendor-kernel A/B" means a one-variable
  A/B; a stock run that differs in host and timing at once rules out
  neither.)
- **L-216. A re-push that answers our requests is trailer-checked on every
  commit.** #77's re-push appended our sentence below its `Link:`, turning
  the trailer into body text. *Check:* `git interpret-trailers --parse` on
  each commit of the new head against the old head's. Extends L-119 and
  L-183. *From:* kernel #77, round 22.
- **L-217. A version we ask a contributor to take can be taken by main
  first.** We asked #78 for 0.2.30; #90 shipped it an hour after his push.
  *Check:* list the maintainer's open and local branches' versions of the
  package and ask for the first free one, or say "the next free version at
  merge" and set it ourselves. Extends L-12. *From:* #78, round 22.


## Claims and evidence

- **L-317. A host capability whose stated user is a sibling PR is checked
  against that sibling's diff.** Kernel #125 says LHBM needs DCS reads; #126,
  the LHBM PR, issues none. *Check:* grep the sibling's head for the new API's
  callers (`mipi_dsi_dcs_read`, `_generic_read`, `rx_len`) before accepting
  the motivation. Extends L-201 and L-219. *From:* kernel #125 with #126,
  round 28.
- **L-316. An `FF=` line in a haptics report is decoded before it's
  accepted.** With memless force feedback, FF_RUMBLE alone shows as `107030000
  0` on arm64, because the memless layer adds the periodic, waveform and gain
  bits; any other value means the driver changed its capabilities. *From:*
  kernel #96, round 28.
- **L-315. A boot report is read against the DTB's bootargs for blacklists and
  masks of the drivers under test.** #96's test overlay blacklisted `gs_decon`
  and `panthor` and masked the display and GPU units, so those rows couldn't
  pass the way they will for users. *Check:* diff the booted command line
  against the head DTB's `/chosen/bootargs` (decompiled with the build's own
  dtc) for `modprobe.blacklist`, `systemd.mask` and `systemd.unit`, and ask
  for the default path. Extends L-276. *From:* kernel #96, round 28.
- **L-314. "The driver isn't in this stack" is checked against the base the
  stack sits on.** #96's boot report blamed missing #84 and #89, which had
  merged before the rebase; a build that reuses another tree's config through
  `olddefconfig` leaves a new symbol with no default off. *Check:* `git
  merge-base --is-ancestor <driver commit> <head>`, the symbol's `default` in
  Kconfig, and `/proc/config.gz` and `lsmod` from the boot. A gap in our own
  build goes in `device/<codename>/kernel.config`, not the shared fragment
  (tegu's arrives with #74). Extends L-182 and L-61. *From:* kernel #96, round
  28.
- **L-313. A rewrite that answers "what did that boot run?" is re-read for
  every sentence that pointed back at the old text.** #125's answer replaced
  the 10-26 kernel line, which left the 10-28 paragraph's "the same kernel"
  pointing at Google's kernel on the day that carries the rule. *Check:* `git
  diff <old head> <new head>` on the record, and for each removed noun (a
  release, a tool, an image) grep the rest of the section for "the same",
  "that kernel" and "it". *From:* #125, round 27.
- **L-290. A "stop the radio" change is verified at the controller, not only
  through the daemon's property.** On the 9a, neard's `Polling` and the kernel
  disagreed after a neard restart (EBUSY). *Check:* compare the controller's
  `/proc/interrupts` total across main's code and the PR's with the screen
  dark (a one-variable A/B), and record `nfctool -l`; where the chip doesn't
  interrupt while idle, a tag tap is the functional proof. Extends L-85 and
  C-12. *From:* #99, round 26.
- **L-286. A cause attributed to stock is checked against what the failing
  boot itself ran.** #125's 10-26 loss came after a "Google-kernel" boot on
  slot B that no notes describe; stock's own ramdisk on B could explain the
  overwrite as well as stock on A. *Check:* ask for the failing boot's kernel,
  its ramdisk and whether the storage guard was present before accepting
  "stock on slot A did it". Extends L-186 and C-12. *From:* #125, round 26.
- **L-283. A board merged without the boot argument we suggested moves the
  guard into the device package.** The merged `gs201-panther.dts` has no
  `mem_sleep_default=s2idle`, so panther's `sleep.conf.d` drop-in, an
  "optional, later" request on #79, is now its only guard against `deep`.
  *Check:* after a board PR merges, re-read its bootargs against L-207 and
  update the device PR's request. Extends L-219. *From:* #79 with kernel #108,
  round 26.
- **L-276. Evidence we ask for must exist in the tool we name.** Our #80
  comment asked for `tools/phone-smoke`'s haptics section; phone-smoke never
  vibrates or lights the torch and has none. *Check:* `grep -n -i
  '<subsystem>' tools/phone-smoke`; where it has no section, name a read-only
  check (probe lines, input or LED class entries). Extends L-31; see C-17.
  *From:* kernel #80 and #96, round 25.
- **L-272. A device's notes are checked against what our DT calls a block.**
  lynx's NOTES and WIFI-PLAN called `0x10840000` "PERIC1, not described", but
  `gs201.dtsi` has `pinctrl_peric0` there with `gpp16`. *Check:* `git grep
  '@<addr>'` and the bank label in `<soc>-pinctrl.dtsi` for any controller a
  plan names. *From:* #98, round 25.
- **L-266. A plan PR merged mid-thread is checked afterwards for the results
  that came later.** #88 merged with lynx's WIFI-PLAN as of the 27th, so the
  `fs_ready` stall reported that night never reached it, and main still calls
  that boot "next". *Check:* for every thread result after the PR's last push,
  `git grep` its key strings on main's plan and ask for a follow-up PR for any
  that are missing. Extends L-34 and L-201. *From:* issue #36 with #88, round
  25.
- **L-260. A gotcha that changes recovery behaviour is checked against the
  author's other open PRs, not only main.** #125 said stock on slot A
  "reformats" `userdata`; the same author's #100 records that stock stops in
  recovery and only a chosen factory reset wipes it, which turns the rule from
  "mark the slot" into "never choose the reset". *Check:* `git grep -i` the
  claim's key words (recovery, reformat, wipe, fallback) over that author's
  open PR heads for the device. Extends L-188 and L-191. *From:* #125, round
  25.
- **L-256. An "inactive slot" install mode is walked for what a reinstall
  does.** With `OMAMOBILE_SLOT=inactive`, rerunning #111's installer on a
  phone already in Omarchy flashes the stock slot unless `--reflash` is
  remembered. *Check:* name the slot written from each starting state. Extends
  L-205. *From:* #111, round 24.
- **L-257. A fix that "covers every device package" is re-counted at review
  time.** #102 changed four copies of a file; lynx's package landed a fifth
  after it opened. *Check:* `git grep -l '<changed line>' origin/main --
  packages/` against the PR's file list. Extends L-164 and L-195. *From:*
  #102, issue #103, round 24.
- **L-258. A first-owner path is tested without the maintainer's private
  inputs.** `phone-provision` defaulted to the maintainer's backup, so the
  README quick start failed for every new owner. *Check:* `grep -n
  'android/reference' tools/<tool>` for every tool the README names; each
  such default needs a first-install path or a clear refusal. *From:* issue
  #106, round 24.
- **L-259. "Not in the published repository" is checked against the last
  publish before it's read as policy.** The husky package was missing
  because publishes had failed since its merge. *Check:* the publish tree's
  last commit, the index's date, and open "publish failed" issues. *From:*
  issue #1, round 24.
- **L-28. "Works" needs merged notes and the phone it ran on.** A matrix row
  claiming works/testing from a private kernel, or from an install of a
  different branch, should say WIP or testing and link the notes.
  *From:* #24, #25.
- **L-29. PR bodies written with an AI over-claim.** "checkpatch clean",
  "dtbs_check clean", "tested" were each untrue at least once this week.
  Re-run the claim; never quote it. *From:* kernel #10-#12, #27.

- **L-45. A rebased companion's evidence still counts if the tested commit
  and the new head don't differ.** *Check:* `git diff <tested> <head> --
  <files the test exercised>`; empty means the test stands, otherwise ask
  for a re-test. *From:* #29, round 2 (994dd90 against d773f62: identical).
- **L-46. A phone's settings reflect that phone's image, not the one we
  build.** A contributor's `busctl` value (`HandlePowerKey=suspend`) came from
  a local drop-in, while our image's `omarchy-settings` sets `ignore`.
  *Check:* compare reported values with what `rootfs/packages.base`
  installs before accepting or correcting a note about a default (with
  L-32). *From:* #29, round 2.

- **L-61. "Private kernel" evidence isn't evidence.** Ask for the public
  source (Google's GPL tree, the stock DT lines, upstream) behind each value.
  *From:* kernel #28-#31.
- **L-62. Check a claimed upstream backport against that commit's own
  `.patch`,** and list the file's later commits to find where any extra
  lines came from; authorship and trailers must survive. *From:* #32
  (0005 was two upstream commits with no `From:` line).
- **L-65. A `-dirty` release means the tested code is in no commit.** Look
  up its hash (`git log -1 <sha>`); if it predates the PR's code, the notes
  must say the evidence came from an unpublished tree and name the
  differences the PR admits. Hardware facts stand; claims about the PR's
  code path don't (extends L-45). *From:* #34 with kernel #32.
- **L-66. A matrix cell's word needs the qualifier its neighbours use and a
  link to the notes entry.** "Touch: WIP" for a chip-id read reads as touch
  input. *From:* #34.
- **L-76. Fetch each `Link:` anchor and read the line it points at.**
  *Check:* `curl -s '<url>?format=TEXT' | base64 -d | sed -n Np`. #29's was
  two lines off: cosmetic there, but a wrong commit or file wouldn't be.
  *From:* kernel #29, round 2.
- **L-85. "Nothing else changed" needs a "before" from the same boot.** A
  stop condition such as "no other rail changed" with only an after-read of
  `regulator_summary` can't fail. *Check:* every "X didn't change" condition
  has a snapshot step before the action and a diff after. *From:* #34,
  round 2.
- **L-86. When a revised driver keeps the protocol but changes the power
  sequence, the earlier boot covers the protocol only.** Compare the trees
  (L-69): a changed probe or remove order (rails, reset) needs its own boot,
  even when the read path is identical. *From:* kernel #32, round 4.
- **L-106. One PR's hardware evidence can land in another PR's commits.**
  Husky test 23, the result #33 asked for, was in #23's BRINGUP-M1. *Check:*
  read the companion PRs before saying "no evidence yet". Extends L-34.
  *From:* kernel #33 with #23.
- **L-107. A plan's claim about the DEVICES.md matrix is checked against
  the open PRs that change that row.** Extends L-28 and L-44. *From:* #35
  with #34.
- **L-128. Read the host's USB log before interpreting a phone's
  "re-enumeration".** The laptop's `journalctl -k` timestamps the gadget
  leaving and arriving, and survives a phone whose RAM log is lost: husky
  test 23's "re-enumerated after 22 s" was the boot itself. *From:* kernel
  #33, round 10.
- **L-129. A CRC "clear" covers only what that register checks.** FTM5's
  CRC register is the base check; config and CX errors come as events after a
  reset. *Check:* which check covers the calibration area, and whether it
  needs a reset, before a plan says a read answers "is it valid". *From:*
  #35, round 10.
- **L-130. Before putting a bootloader requirement down to the SoC,
  compare the reference phone's stock images.** Cheetah's stock vbmeta chains
  `boot` and `init_boot` with the same rollback index and ABL build as lynx,
  yet boots footerless images: lynx's AVB footers are its ABL's
  configuration. *Check:* `avbtool info_image` on the stock vbmeta in
  `~/android/reference` (read-only). *From:* #37.
  (Corrected 2026-10-28, C-14: the comparison used the factory vbmeta, not
  the phone's non-stock `vbmeta_b`; a stock `vbmeta_b` needs footers on
  cheetah too.)
- **L-131. Evidence cites the tested file's blob id, not a commit id.**
  `git rev-parse <commit>:<path>` survives the folds and rebases we ask for,
  and ties an out-of-tree module to its source. Extends L-45. *From:* kernel
  #38 with #39.
- **L-132. A device can appear twice on DEVICES.md (matrix row and Wanted
  list); an edit to one must agree with the other**, and the plain words that
  say the evidence isn't public must survive. *Check:* `grep -n <codename>
  docs/DEVICES.md`. Extends L-28, L-66 and L-107. *From:* #39.
- **L-149. A descriptor's overlays and config symbols must exist in the
  published kernel or an open kernel PR.** raven's targeted nodes and
  options in neither, so its images can't be built from our trees. *Check:*
  `git grep` each overlay target and `CONFIG_` symbol against
  `github/omamobile` and the open PR heads; whatever is missing means the
  matrix cells name the port branch. Extends L-28 and L-61. *From:* #41,
  round 12.
- **L-150. Read every plan in the PR before quoting one plan's status.**
  raven's BLUETOOTH-PLAN said "broken" while a later POWER-PLAN result said it
  "works again". *Check:* `git grep -n` the subsystem across the PR's plans
  and go by the newest dated result. *From:* #41, round 12.
- **L-186. A slot A fallback record without Android symptoms makes "what is
  on slot A?" the first question.** #35's answer to "did the lock screen
  appear, did it offer to reset `userdata`" was "slot A is another Omarchy
  install", which the notes on main contradicted and which means the phone
  has no Android fallback and that slot A's images were written. *Check:*
  whenever a fallback is reported, ask for the OS on slot A, when and how it
  got there, and whether its initramfs has the storage guard; a Linux slot A
  is a §3.1 event (L-135) even when nothing else went wrong. *From:* #35,
  round 20.
- **L-187. Check a plan's prose against the descriptor at the same head.**
  #38's `BRINGUP-M1.md` still said `SIMPLEFB_TRIG_CON` is unset while the
  same commit's `device.conf` set it. *Check:* `grep -n <KEY>
  device/<x>/*.md device/<x>/device.conf` for every descriptor key a PR adds
  or removes. *From:* #38, round 20.
- **L-188. An AGENTS.md gotcha is checked against the plan it cites, in the
  same PR.** #72 added "on the 9a it never woke" to a shared gotcha with no
  plan line about suspend anywhere in its 1,220 lines. *Check:* `grep -i` the
  gotcha's key words over the PR's plans; a gotcha without a dated result and
  `uname -r` waits for them. Extends L-109. *From:* #72, round 20.
- **L-189. A supplier-based property's evidence names the supplier driver,
  and that driver's PR.** #66's "Charging / Full / Not charging" came from a
  MAX77779 charger driver that is in no tree or PR of ours; on our tree the
  property stays Unknown until it lands. *Check:* `git grep` the supplier's
  compatible or driver name across the base and the open heads before
  quoting the result. Extends L-61. *From:* kernel #66, round 20.
- **L-190. Before accepting a plan's "next" step, check the plan's own
  negative results and the device package for it.** Issue #77 proposed a
  longer `BT_REG_ON` hold and a boot-time power-cycle retry; raven's
  BLUETOOTH-PLAN had already held the line low for seconds without effect,
  and `omamobile-bt-addr` already rebinds the driver up to three times a
  boot. The vendor driver's own number (30 ms) is what kernel #6 copied; the
  HAL's 100 ms is a different step. *Check:* grep the plan's result tables
  and the package's `bin/` for the mechanism, and the vendor driver for the
  number, before asking for or agreeing to a change. Extends L-61 and L-147.
  *From:* issue #77, round 20.
- **L-191. A PR's premise about a phone is checked against that device's
  plans and the author's own words elsewhere.** #69 said husky "already shows
  the Omarchy clock" and kernel #64 that an `ioremap` "reset the phone",
  while DEVICES.md and UFS-PLAN show no session has run and the author said
  on the device's issue that nothing was flashed; #69 also hard-coded
  another contributor's kernel release. *Check:* grep the release string and
  the claims in `device/<codename>/*`, and read the author's comments on the
  device's issue. Extends L-61 and L-109. *From:* kernel #64, #69, round 20.
- **L-192. "The builder's keys give root on every installation" is checked
  against the init and the installer.** The initramfs `authorized_keys`
  never reaches the Arch root (`install-phone` writes the owner's key
  there), and the initramfs console (`getty -n -l /bin/sh` on `ttyGS0`)
  already gives anyone with the cable root at that stage. #75's change is
  right for §5.2's reason; the review says what the exposure is so the
  squash body doesn't overstate it. *Check:* `grep -n 'authorized\|getty'
  initramfs/init tools/install-phone`. *From:* #75, round 20.
- **L-200. Check a cited commit range's member ids, not only its
  endpoints.** #52's base `6963e3800a8e` and "three commits past the tag"
  were right; the two intermediate ids it listed don't exist, and their
  subjects belong to commits before the tag. *Check:* the GitLab or GitHub
  compare API, `from=<tag>&to=<base>`, and compare each listed id. Extends
  L-76. *From:* #52, round 21.
- **L-201. "That's recorded in the other PR" is checked by grep on the other
  PR's head, and both PRs get the finding.** Kernel #72's reply said the
  DPP0 read and the `/proc/iomem` line were in #82's notes; #82's NOTES had
  the kernel release only, and the PR that would carry them was already
  "all done" in its own thread. *Check:* for every cross-PR "it's in #N",
  `git show <N's head>:<file> | grep` the named items before closing the
  request on either side. Extends L-106 and L-183. *From:* kernel #72 with
  #82, round 21.
- **L-202. A `-dirty` release's hash can be a PR commit that the base has
  since taken under a new id.** #82's `g485f83c27e5c` resolved to nothing on
  `github/omamobile`; a subject search found it as the kernel #48 series'
  commit, rebase-merged as `095e451d8660`. *Check:* `git log --all --oneline
  | grep <hash>` across the review refs, then `git log --grep=<subject>` on
  the base, before calling the tested tree unpublished. Extends L-65 and
  L-182. *From:* #82, round 20.
- **L-203. A "before X" register read on stock also says whether the domain
  was cold.** Issue #36's stock "pre-BHI" values came from a chip whose
  always-on domain had completed a PBL run since the buck came up
  (`TCSR_PBL_LOGGING` retained across the WLAN_EN cycle), and we had asked
  for "before the first BHI" without saying "cold". *Check:* when asking for
  a chip-state read, name the rail history (which supplies were dropped and
  for how long) and ask for the retained-state marker alongside. *From:*
  issue #36, round 21.
- **L-204. A contributor's reading of a vendor log is re-derived from the
  vendor driver's sequence before it becomes a premise.** "Stock's very
  first cold cycle already passes auth" on issue #36 stood for a day; cnss2's
  probe powers on, enumerates and powers off before the first BHI, and
  `wlan_buck_enable` logs `Enter` on every power-on, so the timing was most
  likely measured from the second cycle. *Check:* find the one-per-boot line
  (`BUCK GPIO: [0]` and `drive it HIGH`) and count the power-on lines before
  the event. Extends L-61 and L-190. *From:* issue #36, round 21 (C-8).
- **L-218. A filter that printed nothing doesn't show an address was
  unreserved.** `grep fac00000 /proc/iomem` can't match a range that only
  contains it. *Check:* the enclosing range (`awk` on the bounds), or another
  read; don't hold a PR to a capture that no longer exists. *From:* #82,
  round 22.
- **L-219. A promise made in one thread is checked in the PR meant to keep
  it.** On #59 the contributor promised `mem_sleep_default=s2idle` in the
  board bootargs; #80's don't have it. *Check:* before a device's first board
  PR, grep our earlier threads for that device ("when I post", "bootargs")
  and list each promise. Extends L-34 and L-183. *From:* kernel #80, round 22.
- **L-220. A table "from our capture of stock" is looked for in Google's
  per-device DT repos first.** #84's GPU table is Google's public
  `gpu_dvfs_table_v2` (tegu's `dts/zumapro` links to a dtsi that includes
  zuma's), citable by commit. *Check:* follow `dts/<soc>` links in
  `kernel/devices/google/<device>` and diff the capture against the public
  dtsi. Extends L-61 and L-177. *From:* kernel #84, round 22.
- **L-221. Cite the licence a vendor file states.** Google's panel drivers
  under `google-modules/display/panels` are SPDX MIT, not GPL. *From:* kernel
  #89, round 22.
- **L-222. "Driver X has no suspend handling" as a cause is checked against
  the reference phone's driver for the same role.** #72 blamed nxp-nci's
  missing PM ops, but st-nci on cheetah has none and suspends. *Check:* `git
  grep dev_pm_ops` across sibling drivers. *From:* #72, round 22.


## Corrections (where a review was wrong)

- **C-1 (2026-10-22). We blamed the 30 s unused-regulator cleanup for the
  felix cover touch's dead rails (issue #3).** We have no S2MPG12 regulator
  driver at all (cheetah's `s2mpg12-pmic` node is RTC and interrupt masks
  only, and disabled), so nothing in Linux can turn those LDOs off: the rails
  are off as ABL left them. *Lesson:* before blaming a kernel mechanism,
  check the driver for it is actually bound on that device
  (`/sys/kernel/debug/regulator/regulator_summary`, the DT node's status).
- **C-2 (2026-10-23). C-1 said cheetah's `s2mpg12-pmic` node is disabled;
  that is true of the DTS, but the `suspend-pmic-test` overlay in cheetah's
  `DTB_OVERLAYS` enables it.** C-1's conclusion (no regulator driver, so no
  Linux cleanup of those LDOs) still stood then. *Lesson:* L-49. *From:*
  kernel #27.
- **C-3 (2026-10-24). L-88 said husky's DWC3 cycle hung `device_shutdown`
  under `reboot-to`; it didn't.** The laptop's log shows the gadget left at
  the unbind and never returned: the phone froze at the bind, so the fallback
  never ran (#23 tests 23-28). L-88's rule stands, but a freeze that stops
  every CPU defeats every software dead-man, sysrq included. *Lesson:* for a
  step that can freeze the SoC, only the buttons or a hardware watchdog left
  unfed bring it back; the runbook says so and is run attended. *From:*
  kernel #33, round 10.
- **C-4 (2026-10-24). Round 9 told #35's author that LDO11M-LDO13M are CPU
  cluster rails; LDO13M is the TPU rail** (`L13M_VDD_TPU_M`), and our wording
  went into a commit message. *Lesson:* a fact we hand a contributor for a
  commit needs the line-level source we'd ask of them. *From:* kernel #35,
  round 10.
- **C-5 (2026-10-26). Round 11 asked kernel #48's author for `Assisted-by:
  AGENT_NAME:MODEL_VERSION`; the `coding-assistants.rst` on `omamobile` gives
  `Assisted-by: LLM [TOOL1] [TOOL2]`,** which the author used. *Lesson:*
  quote kernel process docs from the branch the PR targets (`git show
  github/omamobile:Documentation/process/…`), not from memory. Extends C-4.
  *From:* kernel #48, round 12.
- **C-6 (2026-10-26). Round 11's request that `aoc-stage s2mpu` require
  `cycle` and a `tzpc` restore was wrong.** raven's AUDIO-PLAN R2.1c/d record
  both DTZPC SMCs hanging the SoC, and R2.1g makes the read safe through the
  `pd` stage. *Lesson:* L-147. *From:* #22, round 12.
- **C-7 (2026-10-27). Round 12 told kernel #9's author to boot with
  `pd_ignore_unused` and read `pm_genpd_summary` to see whether a warm reset
  re-powers the gs101 domains; on 7.3 that can't answer it.** The flag only
  skips `genpd_power_off_unused()`; genpd's `of_genpd_sync_state()` still
  powers off every unused domain of the provider early in boot, so the
  summary reads "off" either way. The contributor answered the question with
  each domain's `active_time` in `debugfs/pm_genpd/`, which starts from the
  STATUS the driver reads at probe. *Lesson:* when we prescribe a test
  through a kernel parameter, read what it does in the tree the PR targets
  before posting it, and say which observable answers the question. L-135
  corrected in place. Extends C-5. *From:* kernel #9, round 20.
- **C-8 (2026-10-27). Our 2026-10-26 comments on issue #36 accepted a
  contributor's reading of stock's log, "the very first cold cycle already
  passes auth", and built a request on it; the vendor driver's sequence
  contradicts it.** cnss2's probe powers the chip on, enumerates it and
  powers it off before the first BHI, and `wlan_buck_enable` logs on every
  power-on, so the first cycle in the log is the probe's and the auth most
  likely came from the second. No existing lesson was wrong; the gap was
  that no lesson asked for the re-derivation. *Lesson:* L-204 (with L-203
  for the rail history the read needed). *From:* issue #36, round 21.
- **C-9 (2026-10-27). Our 2026-10-26 comment on issue #36 said lynx has no
  BT_EN, XO-clock or bootstrap GPIO, after reading only the Wi-Fi node.**
  Stock's Bluetooth node names the Wi-Fi buck pin as its `xo-clk-gpio`, reads
  WLAN_EN and powers the chip's Bluetooth side before the first Wi-Fi load.
  *Lesson:* a pin's role is read from every stock DT node that names it
  (`grep -rn` the pin across the device's DTs, then each consumer's driver).
  Extends L-94 and L-190. *From:* issue #36, round 22.
- **C-10 (2026-10-27). Our 14:50Z comment on kernel #56 asked for a rebase
  onto the BCM4389 series because its ID commit was on `omamobile`; nine
  functions and fields the PR builds on exist only in `omamobile-int`.**
  *Lesson:* before asking for a rebase onto published work, `git grep` the
  base for each identifier the PR's hunks use as context, and compare `git
  log github/omamobile -- <dir>` with `github/omamobile..omamobile-int`.
  Extends L-121 and L-154. *From:* kernel #56, round 22.
- **C-11 (2026-10-28). Round 20 asked kernel #63 for `google,wdma-input:
  false` in the zumapro branch of `google,gs201-csis.yaml`; no such property
  exists.** The slot is `google,ebuf`, and the branch already set it to
  false; we named the property from its description. The contributor caught
  it. *Lesson:* a property we ask about is quoted from `git grep` on the
  head's binding and the driver's `device_property_read_*` calls, with its
  rule in each `if/then` branch read. Extends C-4. *From:* kernel #63, rounds
  20 and 24.
- **C-12 (2026-10-28). Our issue #36 comment said the stock-kernel
  diagnostic ruled out the host side; it couldn't on its own.** The
  diagnostic and step 6 each differed from the passing Android boot in a
  different variable (host, timing), so both stalls left "both missing" open,
  and the same comment built a Bluetooth lead the thread's data had ruled
  out. *Lesson:* a negative run excludes a variable only if it differs from
  a passing run in that variable alone; tabulate each run against the passing
  one first. L-215 corrected in place. Extends L-190 and L-204. *From:* issue
  #36, round 23.
- **C-13 (2026-10-28). Our restore ruling on #35 listed stock slot A's
  partitions from memory and missed `pvmfw`.** The factory image's
  `fastboot-info.txt` is the exact list `fastboot update` writes, and every
  fastbootd logical flash first resizes the partition, rewriting `super`'s
  metadata, which a "nothing unsuffixed" rule forbids word for word.
  *Lesson:* take the list from `unzip -p image-*.zip fastboot-info.txt`, and
  name the resize in any exception that allows logical writes. Extends L-205;
  see L-226. *From:* #35, round 23.
- **C-14 (2026-10-28). L-130 said cheetah boots footer-less images under a
  stock vbmeta that chains boot and init_boot; it compared the factory vbmeta,
  not the phone's `vbmeta_b`.** That `vbmeta_b` isn't stock (another key,
  hash descriptors, no chains). In libavb a chained partition with no footer
  is invalid metadata, which unlocked ABL doesn't override, so every cheetah
  with a stock `vbmeta_b` needs footers (#104, issue #11). *Lesson:* compare
  the vbmeta of the slot that boots, read from the phone or its backup, and
  look for `Chain Partition descriptor` before blaming the bootloader. L-130
  corrected in place. *From:* #104, round 24.
- **C-15 (2026-10-28). We advised admin-merging kernel #108 past a red check
  before reproducing the failure.** It happened to be right (the gate's
  fault, L-246), but L-30 says reproduce first: a gate failure can be the
  tool's fault, and can't be assumed to be. *Lesson:* no merge advice past a
  red check until the failure is reproduced and its cause named. Extends
  L-30. *From:* kernel #108, 2026-10-28.
- **C-16 (2026-10-28). Our round 24 review of kernel #98 made two wrong
  offers.** It said a `qcom,wcn6855-pmu` node "avoids all of this", but the
  sequencer reference-counts across targets, so with Bluetooth its only
  consumer the buck still drops (L-269); and it offered "keep the fixed
  regulator, say so in the message", which can't pass `dtbs_check` against the
  binding's eight required supplies (L-270). Both withdrawn on the PR. L-241
  corrected in place. *From:* kernel #98, round 25.
- **C-17 (2026-10-28). Our 17:53 comment on kernel #80 asked for
  `tools/phone-smoke`'s haptics section, which doesn't exist.** The #96
  comment corrected it with read-only probe checks. *Lesson:* L-276. *From:*
  kernel #80 and #96, round 25.
- **C-18 (2026-10-28). Our 14:17 review of #74 missed that its
  `omamobile-tegu-display.conf` sets `gs_dsim_cmd allow_tx=1` for every
  panel,** against the `google-tg4c`-only guard that kernel #90's acceptance
  leaned on. *Lesson:* L-277. *From:* kernel #90 with #74, round 25.
- **C-19 (2026-10-29). Our round 27 comments on #131 and kernel #124 asked for
  the RT9470 bring-up module and TCPC DT "on a branch or as a draft PR"
  without naming the repository,** and #136 put a kernel module and a DT
  fragment in omarchy-mobile, against CONTRIBUTING §6.1; the fragment also
  references `&hsi2c10`, which no published tree defines. The round 28 draft
  on #136 owned the mistake and asked for a branch on linux-omarchy-mobile.
  *Lesson:* L-71 (and L-240 for the labels). *From:* #131, #136 and kernel
  #124, rounds 27-28.
