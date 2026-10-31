<!-- SPDX-License-Identifier: MIT -->
# Pixel 9 Pro Fold (comet) bring-up notes

This is a curated first-port record for [issue #143](https://github.com/derekross/omarchy-mobile/issues/143).
The results below came from the owner's Comet and private kernel
`7.3.0-rc6-omamobile-comet-zumapro+`, not this PR's build. They establish
hardware observations, not support in the published kernel. No phone was
contacted while preparing this PR on 2026-10-30.

## 2026-10-30: slot state, devinfo history and the way back (for issue #143)

**Slot facts** (`fastboot getvar`; only slot and bootloader lines kept):

```text
current-slot:b            slot-count:2           slot-suffixes:_a,_b
slot-successful:a:yes     slot-unbootable:a:yes  slot-retry-count:a:2  slot-fastboot-ok:a:yes
slot-successful:b:yes     slot-unbootable:b:no   slot-retry-count:b:2  slot-fastboot-ok:b:yes
version-bootloader:ripcurrentpro-17.0-16118441   (ABL reports the active slot's only)
```

Slot A's bootloader version is not reported by `getvar` and has not been
read; A stays unbootable and is never selected.

**devinfo writes.** `devinfo` is /dev/sdd1, 8192 bytes, layout 3.15, kept
`ro=1` by the storage guard. `omamobile-boot-success`
(`omamobile-bootctl mark-successful`) wrote it three times, all on 2026-10-29,
lifting the read-only flag only for the write. Each write saved before/after
images in `/var/lib/omamobile/`, and full 8192-byte comparisons of all three
pairs show **exactly one changed byte, 0x35: 0x1c → 0x1e** (slot B
successful). Bytes 0x30-0x37 went from `02 1b 00 00 02 1c 00 00` to
`02 1b 00 00 02 1e 00 00`; the live bytes on 2026-10-30 are still
`02 1b 00 00 02 1e 00 00`. Every later boot found B already successful, and
the unit wrote nothing.

The writable interval was limited to each helper invocation; an exact
wall-clock duration was not captured. Before-write fastboot slot flag
output is not available in this curated record. The table above is the
2026-10-30 after-state, not a reconstructed before/after getvar comparison.
Those missing observations remain questions for the maintainer.

**Paused on 2026-10-30** at the maintainer's request (#143): the unit is
masked on the phone (`systemctl mask omamobile-boot-success`). No further
devinfo write until it is agreed on the issue. Because slot A is unbootable,
ABL has no slot to fall back to. Retry exhaustion on B would land in fastboot
rather than lose the Linux root, so comet may not need marking at all.

**The way back if slot B stops booting.**
- Buttons-only fastboot works on comet: the owner forced fastboot on
  2026-10-30 after the i-touch2 USB loss, and recovery used
  `bin/omamobile flash --keep-active` (slot B images only).
- Stock restoration needs a factory image **CP3A.261005.005 or newer**,
  never older, because of anti-rollback. The image on the laptop
  (CP2A.260805.005) is older and **must not** be flashed.
- A full factory flash overwrites both slots' bootloader/radio/boot
  partitions and wipes userdata (the Linux root). efs/persist/modem are
  backed up off-repo and checksum-verified (6/6 MATCH on 2026-10-30).
- **Owner acceptance recorded on issue #143:** until stock is back on a slot, recovery
  means fastboot by the buttons.


## 2026-10-28 to 2026-10-29: internal root and inner display

[V, owner's captures] The shared-base kernel booted eight CPUs with
MemTotal 15,873,676 kB. All 28 fixed live firmware ranges were excluded
from the allocator. UFS enumerated 62 partitions behind the storage guard;
only the five slot-B boot images and `userdata` were writable. Arch ran
on `userdata`, grown to 225 GiB. Protected partition backups remained
outside the repository and were checksum-verified before PMIC work.
Both watchdogs were taken over at probe. Warm reboot and watchdog reset
retained ramoops. NCM USB networking and fresh SSH reached the root.
Replug reliability was not qualified.

[V, owner's captures] The inherited CT3B inner panel displayed the Omarchy
login with gs-decon KMS at about 60 Hz, Panthor and Hyprland rendering.
This was an unpublished display-enabled tree, with zero flip timeouts in
that observation window. It does not establish 120 Hz, brightness control,
DPMS, cover switching or sustained GPU stability. Power and both volume
keys produced evtest events. Earlier inner Goodix probes hung the phone
twice; those hangs and several boot-return failures are unresolved.
Later subsystem experiments are deferred to their own submissions.

## Descriptor evidence from Comet

[V, owner's stock captures and factory-image parses] Comet's reported
DTBO index was 14: board ID `0x60606`, revision `0x10000`. The stock
`vendor_kernel_boot` contains four zumapro candidates: product `0x9875`,
major 0, minor 0/1, FOPLP package mode 0 or IPOP mode 1. Their union is
recorded without claiming the retail phone's exact stepping/package.
The cover panel is 1080x2424; the inner is 2076x2152 before mounting transform.

[V, owner's CP3A.261005.005 parses, 2026-10-28] AOSP avbtool info_image
and verify_image established boot/init_boot footer sizes 67108864 and
8388608 bytes, rollback index 1791158400 and security patch 2026-10-05;
init_boot header v4 carries Android 17.0.0 and patch level 2026-10.
These supersede older factory-reference values. They do not establish
slot A's unread bootloader version or authorize a flash.

No register address is imported from the Pixel 9a descriptor. In
particular SIMPLEFB_TRIG_CON and BRINGUP_PROBE are absent: no display
MMIO read or write is admitted by this descriptor. Future register values
must be checked against Comet itself with powered/clocked block evidence.
The board kernel and module closure are external dependencies; this
repository change alone cannot build or validate a Comet kernel.

See [BRINGUP-M1.md](BRINGUP-M1.md) for the remaining gates.
