<!-- SPDX-License-Identifier: MIT -->
# Review lessons: Safety model (AGENTS.md section 1) (part 4 of 4)

Part of [the review lessons](../LESSONS.md), which says how they are used and how they grow.

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
