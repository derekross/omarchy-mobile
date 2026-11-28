<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Safety model (AGENTS.md section 1) (part 4 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
