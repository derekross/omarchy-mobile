<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Safety model (AGENTS.md section 1) (part 4 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
