<!-- SPDX-License-Identifier: MIT -->
# Comet first-port gates

Prepared 2026-11-08: descriptor and inert boot policy only. The separate
`upstream-comet/board-dts` and `upstream-comet/usb-dwc3-pm` kernel branches
are prerequisites. Kernel #80 is closed, not a merge dependency. The
prepared board subset leaves USB disabled and is not a recovery image.
A later owner-approved enablement/qualification is still required. Historical
observations and exact kernel release are in [NOTES.md](NOTES.md).

The goal is a reviewable descriptor, storage policy and evidence record.
Kernel worktrees and output directories belong to the separate kernel
submission. No kernel was built or phone contacted for this change.

| Step | Command / action | Expect / Pass | Stop condition | Rollback | Risk |
| --- | --- | --- | --- | --- | --- |
| Offline policy | `tools/pr-check upstream/main` | identifier, blob and script checks pass | any failure | edit or exclude before publication | low |
| Offline package | `tests/packages omamobile-device-comet` | staged descriptor matches; no service wants links; no devinfo writer is staged | any failure | retain prior package; do not install | low |
| Recovery review | Read NOTES and issue #143 with maintainer | buttons-only recovery accepted; slot A version remains explicitly unknown | missing stock recovery agreement | remain offline | none |
| Future hardware | No command authorized here | separately agreed runbook, read-only first, fresh protected backups, log stream and watchdog before driver loads, one change per boot | lost transport, refusal or unexpected state | stop and use owner-attended buttons recovery; no speculative commands | high |

No `devinfo` write or boot-success enablement is admitted. If an unmarked
slot B exhausts retries, use the separately approved guarded slot-B
recovery procedure; never select the unbootable slot A. If a future stock
boot occurs, decline any userdata reset and refresh protected backups
before any further radio, PMIC, AoC or Trusty work. A full factory restore
is a separate owner/maintainer decision, outside this runbook.

Results: local preparation only; the package is a curated boot-policy
snapshot, version 0.1.60. Later subsystem startup policies and their
unmerged candidate runbooks are intentionally deferred.
