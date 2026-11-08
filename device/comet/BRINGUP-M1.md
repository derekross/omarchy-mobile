<!-- SPDX-License-Identifier: MIT -->
# Comet first-port gates

Prepared 2026-11-08 and rebased onto main on 2026-11-17: descriptor and
inert boot policy only. Preparing it contacted no phone; the hardware
history it relies on, from 2026-10-28 on, is in [NOTES.md](NOTES.md) by
date. The comet board DTS (`dt-bindings` commit first, new nodes
disabled) and the USB glue are their own linux-omarchy-mobile pull
requests, linux-omarchy-mobile#273 and #271; this descriptor builds
from public code only once they land.
Kernel #80 is closed, not a merge dependency. A later owner-approved
enablement and qualification is still required.

The goal is a reviewable descriptor, storage policy and evidence record.
Kernel worktrees and output directories belong to the separate kernel
submission. No kernel was built or phone contacted for this change.

**Slot state.** Since 2026-11-07 both slots carry stock CP3A.261005.005,
and Linux runs from slot B (NOTES, 2026-11-07/08). Slot A is bootable
stock: a slot B that exhausts its tries falls back to it.

| Step | Command / action | Expect / Pass | Stop condition | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| Offline policy | `tools/pr-check upstream/main` | identifier, blob and script checks pass | any failure | edit or exclude before publication | low |
| Offline package | `tests/packages omamobile-device-comet` | staged descriptor matches; no service wants links; no devinfo writer is staged | any failure | retain prior package; do not install | low |
| Slot read | `fastboot -s <SERIAL> getvar current-slot`, `slot-successful:b`, `slot-retry-count:b`, `slot-unbootable:a`, `slot-unbootable:b`, `version-bootloader` | B current, A not unbootable, one bootloader version | any other state | none (read-only) | none |
| Future hardware | No command authorized here | separately agreed runbook, read-only first, fresh protected backups, log stream and watchdog before driver loads, one change per boot | lost transport, refusal or unexpected state | stop; R1 or R2 below with the owner present; no speculative commands | high |

No `devinfo` write or boot-success enablement is admitted; the
boot-success policy for comet is the maintainer's decision. Keep reboots
few: with B unmarked, each boot spends one of its tries.

## Recovery procedures

Both run from fastboot on the laptop, with the owner present and the
owner's go for each write. `<SERIAL>` is the phone's serial. Neither
touches slot A, the bootloader, radio, `devinfo`, `persist`, `efs*`,
`modem*` or `vbmeta`, and neither runs an unsuffixed `flash`.
Approval: the owner, in a private working session on 2026-10-30 (R1);
there is no public record, so the procedures are written out here in full
for review.

### R1: slot B boots but is broken (bad kernel, lost USB)

Used on 2026-10-30 after the i-touch2 USB loss, through our development
tree's `bin/omamobile flash --keep-active` (not on main), which runs the
`current-slot` check, the five writes and the reboot below. `SET` is the
last saved slot-B set that booted, with its five images and their
checksums; the matching modules must be on the root.

```sh
# Reach fastboot: Volume Down + Power held about 20 s.
fastboot -s <SERIAL> getvar current-slot     # must print b; stop otherwise
(cd "$SET" && shasum -a 256 -c SHA256SUMS)    # stop on any mismatch
fastboot -s <SERIAL> flash boot_b               "$SET/boot.img"
fastboot -s <SERIAL> flash init_boot_b          "$SET/init_boot.img"
fastboot -s <SERIAL> flash vendor_boot_b        "$SET/vendor_boot.img"
fastboot -s <SERIAL> flash vendor_kernel_boot_b "$SET/vendor_kernel_boot.img"
fastboot -s <SERIAL> flash dtbo_b               "$SET/dtbo.img"
fastboot -s <SERIAL> reboot
```

No `--set-active`: B is already current. Stop at the first write that
fails and write the set again before any reboot; never boot a half-written
slot B. A fastboot flash may clear B's successful flag, so B then has its
three tries and a failure falls back to stock (R2).

### R2: slot B exhausted its tries and stock booted on A

What happened three times on 2026-11-07 (NOTES).

1. If stock offers a factory data reset or to wipe data, **decline**: it
   would erase the Linux root on `userdata`. Power the phone off instead.
2. Reach fastboot (Volume Down + Power about 20 s) and read, without
   writing: `fastboot -s <SERIAL> getvar current-slot`, then
   `slot-successful:b`, `slot-retry-count:b`, `slot-unbootable:b`.
3. If B's images are suspect, run R1's checksum and five `flash ..._b`
   lines first, without its `reboot`.
4. With the owner's go (a slot flag write), return to B. This is how B
   was reselected after each 2026-11-07 fallback:

   ```sh
   fastboot -s <SERIAL> --set-active=b
   fastboot -s <SERIAL> reboot
   ```

5. On Linux, before any radio, PMIC, AoC or Trusty start: a fresh
   read-only backup of `efs`, `efs_backup`, `modem_userdata`, `persist`
   and `modem_a/b` (AGENTS.md §1), because stock's modem stack rewrites
   them. The 2026-11-07 capture is described in NOTES.

Stop at any unexpected `getvar` value, any refused or failed write, or a
phone that stops answering; don't guess at its state. A full factory
restore is a separate owner/maintainer decision outside this runbook.

Results: local preparation only; the package is a curated boot-policy
snapshot, version 0.1.0. Later subsystem startup policies and their
unmerged candidate runbooks are intentionally deferred.
