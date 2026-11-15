<!-- SPDX-License-Identifier: MIT -->
# Exact revised-kernel development startup

Attended development startup qualified on one Pixel 6a on November 14, 2026.
Nothing here is installed or enabled by the device package. See
[the baseline plan](../../DAILY-BASELINE-PLAN.md) for the two corrected boot
results, retained failed attempts, bounded attended runbook and recovery
boundary. Keep historical startup helpers pinned. This source publication
does not provide a general installer or a reusable copy of the private lab
controllers, handset profile, snapshots or consumed qualification launchers.

`start.py` is a new implementation for signed kernel `720a495`, not a launcher
for old consumed probes. `modules.json` records exact previously tested module
bytes. The separate private `/etc/omamobile/bluejay-revised.json` supplies the
actual serial, complete B/protected/devinfo hashes, firmware hashes, qualified
DT properties and boot arguments. The profile is absent from this repository.
Missing inputs fail closed; they must never be filled by accepting whatever
happens to be present on the phone.

The root gate validates all guards and full hashes without loading hardware.
The host opens a new pinned log stream and proves a unique kernel marker before
writing the current boot's `host-log.json`. The acknowledgment unit waits at
most 45 seconds, then acknowledges only that boot's root marker. The stage
chain automatically runs GPU/readbacks, touch, PCIe, Wi-Fi and provisional
gauge monitoring. The desktop starts only after all stages pass. Each stage
keeps a durable pending marker on failure and retains complete boot journals.
There is no failure reboot, module unload, recovery writer or same-boot retry.

The fallback for any failed stage is the answering USB root, with later stages
and the revised desktop held. The independent graphics environment defaults to
software rendering unless this boot has an active completed GPU unit and
render node. Private root receipts remain unreadable by the desktop user.
It does not make a failed stage safe to ignore or claim a software
desktop tested. Preserve pending markers as evidence rather than deleting
them to make startup try again.

Install locations, after the live/staging gates pass:

| Source | Private development-root destination |
| --- | --- |
| `start.py`, `modules.json` | `/usr/local/lib/omamobile/bluejay-revised/` |
| `units/*.service` | `/etc/systemd/system/` |
| `graphics-env` | user's `uwsm/env.d/99-bluejay-revised` after exact-path snapshot |
| generated private profile | `/etc/omamobile/bluejay-revised.json` |

An opt-in file `/etc/omamobile/bluejay-revised-enable` and explicit enablement
of the revised root and desktop units are required. Every unit has a bounded
deadline and `Restart=no`. The opt-in applies only to this known image set.
The initial candidate retains the tested `bluejay.gpu_evening=1` bootargs token;
its presence is provenance, not permission to replay the former trial scripts.
The historical `/usr/share/uwsm/env.d/90-omamobile-bluejay-graphics` stays intact.
The late user override does nothing on the historical release. Verify installed
UWSM source loads the user override last before deployment. No command in this
README stages files.

This startup requires an attached logging host for qualification. Host-free
startup, battery calibration, charging, Type-C, sleep and daily carry remain
open. Gauge startup configures alerts and is a hardware operation even with no
model configured. The bounded charger/model audit is separate.
