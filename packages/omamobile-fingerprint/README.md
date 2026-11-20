<!-- SPDX-License-Identifier: MIT -->
# omamobile-fingerprint

Fingerprint unlock and `sudo` on the Pixel phones whose sensor works under
Omarchy Mobile: the Pixel 7 Pro (cheetah), the Pixel 9a (tegu) and the
Pixel 7 (panther). Google's own fingerprint HAL runs in a minimal Android
chroot, next to Trusty's storage proxy, KeyMint and Gatekeeper, and
fprintd reaches it through a small bridge. The bring-up is in
[device/cheetah/FINGERPRINT-PLAN.md](../../device/cheetah/FINGERPRINT-PLAN.md),
[device/tegu/FINGERPRINT-PLAN.md](../../device/tegu/FINGERPRINT-PLAN.md) and
[device/panther/FINGERPRINT-PLAN.md](../../device/panther/FINGERPRINT-PLAN.md);
the design in
[device/cheetah/FINGERPRINT-RESEARCH.md](../../device/cheetah/FINGERPRINT-RESEARCH.md).

## How it fits together

```
fprintd ── libfprint (omamobile_udfps driver, packages/libfprint)
              │  unix socket /run/omamobile-fp/sock/bridge.sock
              ▼
   omamobile-fp-bridge ── the fingerprint HAL (Google's, binder)
   (in the chroot)            │
                              ├── Trusty: the sensor's trusted app, KeyMint,
                              │   Gatekeeper (/dev/trusty-ipc-dev0)
                              └── storageproxyd: Trusty's secure storage
                                  (the RPMB, /dev/sg-rpmb)
```

- **`omamobile-fp.service`** runs `omamobile-fp-chroot start bridge` at
  boot. The package enables it (a vendor wants link), and it stays inert
  until `tools/phone-provision` has put Google's files in
  `/usr/lib/omamobile-fp/root`.
- **`omamobile-fp-chroot`** builds the chroot in a private mount and PID
  namespace: the vendor image read-only, a fake `/sys` and `/dev` with only
  what the HAL reads, the RPMB's SCSI generic node and nothing else, and the
  phone's properties (`props.conf`, then `props-DEVICE.conf`). It finds the
  phone by its board compatible and stops on a board it doesn't know.
- **`omamobile-fp-bridge`** and the property shim
  (`omamobile-fp-shim.so`) are bionic programs built on the computer
  (`fingerprint/Makefile`) and shipped prebuilt. The bridge turns the
  panel's local high-brightness circle on during a touch on the sensor
  (`omamobile-fingerprint-lhbm.conf` lets it).
- **fprintd** finds the bridge through `FP_OMAMOBILE_UDFPS`
  (`fprintd.service.d/omamobile-udfps.conf`); the lock screen uses
  `/etc/pam.d/omarchy-lock-fingerprint`, and a sleep hook restarts fprintd
  after a wake.
- **`omamobile-fp-ctl`** talks to the bridge by hand (enrol, verify, list)
  for bring-up and tests; **`omamobile-tipc-probe`** tells whether a
  trusted app is already loaded.

Google's Android files are never part of the package:
`tools/extract-fingerprint-vendor` makes them from the owner's own factory
image.

## Safety before the storage proxy

Every start runs `storageproxyd`, and Trusty's storage writes the RPMB, so
the runner checks before it (`omamobile-fp-chroot preflight`, which
`start` runs itself):

- **read-only copies**: on the 7 Pro and the 7, the first start copies
  `mfg_data` and `persist:/ss` into `/var/lib/omamobile-fp` with their
  hashes; both partitions must be read-only (the storage guard);
- **the TDP guard**: no storage proxy without the TDP copy, or once it, or
  `persist:/ss/0`, no longer matches its recorded hash;
- **once per boot**: a second storage proxy in the same boot can crash
  Trusty's storage app, so a second start is refused until a reboot, and
  there is no `Restart=`;
- **a start that never got running** makes the next boot skip fingerprint
  once;
- **the sensor**: the `hal` and `bridge` stages stop before preflight when
  the sensor's device isn't there after its driver's modprobe;
- **the first start** waits for the owner on any phone that isn't marked
  for an automatic one (below).

## The first start waits for the owner (0.1.19)

The first storage proxy start on a phone writes Trusty's secure storage in
the RPMB, which can't be undone. The runner's per-phone `case` marks the
phones whose install guides say fingerprint starts on its own after
provisioning with `FIRST_START=auto`: the 7 Pro, the 9a and the 7. Nothing
changes for them.

Any phone added to the `case` without `auto` gets the default, `owner`: its
first start waits for `/etc/omamobile/fingerprint-first-start`, created by
hand. The unit's `ExecCondition` (`omamobile-fp-chroot admitted`) checks it
before any module load, and `preflight` and `start` refuse without it,
leaving no state behind. A board the runner doesn't know at all fails the
same check and never starts.

The first start that passes preflight writes
`/var/lib/omamobile-fp/storage-first-start` (root only) with what admitted
it, so later boots need no go and the file can be removed. A phone that
already ran fingerprint under an older runner needs nothing: its `provenance`
record, or anything in Trusty's storage directory, counts as the first
start.

## Tests

`test/all` (static checks, the runner's lookups and `setup_sys`/`setup_dev`
for the 7 Pro under `set -euo pipefail` with the mounts stubbed, the gate,
the staged layout) and `test/preflight` (the safety checks against a fake
partition tree). Neither touches a phone.
