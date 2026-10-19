<!-- SPDX-License-Identifier: MIT -->
# flame: installed loader and boot-success metadata

**Policy hold (2026-10-26):** the SG_IO metadata writer below is a proposal.
It cannot land or run under current AGENTS.md until the maintainer approves
a named exception. A phone owner's hardware approval alone does not change
that repository policy. The proposed userdata flash is also held out of the
boot-method plumbing; no unsuffixed flash command is added by that split.

Status: kernel `7.0.0-sm8150`, tested 2026-10-19; native profile requires
`DEVICE=flame FLAME_NATIVE=1`. The default profile remains RAM-only.
This is a development procedure for the measured Pixel 4 layout, not a
general Qualcomm installer. Stock A on this handset is unbootable.

## Measured failures and corrections

1. Writing the small header-v0 U-Boot image over stock boot B left old
   Android ramdisk-size, OS-version and command-line bytes where the new
   header contained zeros. The compressed U-Boot payload matched, but the
   complete image prefix did not. Erasing **only `boot_b`** before flashing
   the checked image produced an exact match, including every header byte.
   The loader path in `bin/omamobile flash` now performs that erase.
2. Flashing boot B cleared `slot-successful:b`, even without `set_active`.
   Preserving an already-successful flag is therefore insufficient. The
   boot tool stops in Android fastboot when the flag is clear; it must not
   declare a permanent installation complete or start repeated slot boots.
3. Pixel 4 uses Qualcomm GPT attributes for boot control. Its `devinfo`
   is not the Tensor `DEVI` structure. Do not use the cheetah boot-success
   writer on flame. The [coral HAL][coral] uses the [QCOM boot-control
   implementation][bootctrl] and [coral GPT utilities][gpt]. The success
   flag is bit 6 of attribute byte 6 (bit 54 of the 64-bit GPT attributes).
   `isSlotMarkedSuccessful` queries the `boot_b` entry for slot B.
4. UFS LUN letters changed across a reboot. The NV partitions remained
   byte-for-byte unchanged, but old `/dev/sdX` paths pointed at different
   partitions. the packaged `flame-partition-links` helper now resolves unique GPT names into
   root-only RAM symlinks and checks their read-only flags. The private
   calibration manifest uses those links, so Wi-Fi's guard survives that
   enumeration change.
5. A private bring-up journal override used `ForwardToConsole=yes` and
   `TTYPath=/dev/ttyGS0`. After unplugging, the charger reported offline
   while the USB controller still reported configured. The journal captured
   105 `remote wakeup not configured` errors in the four seconds before its
   final shutdown record. Forwarding those errors back to the same USB
   terminal creates a feedback path. The standalone journal configuration
   disables that forwarding while retaining local logs. That change alone
   did not pass the battery restart gate: the next shutdown progressed,
   but the handset still required reconnection.
6. The native payload also requested `console=tty0 console=ttyGS0,115200`.
   Linux uses the last console for `/dev/console` ([console documentation][console]),
   so disabling journal forwarding did not remove USB from the normal
   console path. The standalone payload uses `console=tty0` only; the
   kernel, DT and ramdisk stay unchanged. The native builder now uses this
   setting. Keep USB serial login an explicit attached-only debugging step.

7. A later unreadable restart display led to a concrete U-Boot simplefb defect:
   a missing `rot` property left an uninitialized value, and the probe ignored
   framebuffer stride. The corrected driver defaults rotation and validates
   row layout. The installed correction passed normal, deliberate-crash and
   unplugged restarts. This is not proof of the original spontaneous runtime
   reset cause. The separate GPL source and the new host-only configuration
   are pinned by `tools/build-flame-loader`; see [native results](native/RESULTS.md).

[coral]: https://android.googlesource.com/device/google/coral/+/refs/heads/android13-release/bootctrl/Android.bp
[bootctrl]: https://android.googlesource.com/platform/hardware/qcom/bootctrl/+/refs/heads/android13-release/boot_control.cpp
[gpt]: https://android.googlesource.com/device/google/coral/+/refs/heads/android13-release/gpt-utils/gpt-utils.h
[console]: https://docs.kernel.org/admin-guide/serial-console.html

## Constrained boot-success exception

Marking B successful is a separate, explicitly authorized boot-metadata
transaction. The implementation changes only boot B's success bit and
the two table/header checksums. It never changes partition GUIDs, names,
bounds, other attributes, remaining attempts, PMBR, or table padding.
It never creates `/dev/sda` or clears a read-only flag. This exception is
not a general permission for raw SCSI writes or additional writable nodes.
It is not enabled as an automatic startup service.

The measured main LUN has 4096-byte sectors, 15 entries of 128 bytes, and
boot B at entry index 6. Both GPT copies are validated. The backup header
retains a primary-array pointer of LBA 2, while its physical table is
immediately before the final header. The helper verifies and preserves this
legacy layout rather than silently rewriting it into another GPT format.

The tools are deliberately separate:

- `native/read_gpt.py` permits only read-capacity and read commands, through
  the existing, verified `boot_b` block node resolved by unique `PARTNAME`.
  Both it and the final RO check resolve `userdata` by `PARTNAME` too,
  require a common parent LUN, and reject missing/duplicate labels. It saves both GPT copies and
  the surrounding reserved sectors. Its output contains identifiers and
  must stay outside the repository.
- `native/boot_success_plan.py BEFORE.json PLAN.json` is host-only. It
  validates the backup and proposes exactly four sector writes, backup
  first. Only the boot-success bit and checksum bytes differ.
- `native/boot_success_apply.py` requires the backup and plan checksums,
  the exact reviewed loader file and checksum, and the explicit apply
  flag. It refuses a changed live GPT, changed plan, wrong model/layout,
  inactive/unbootable B, or an installed loader that differs from the
  reference. Every sector is read back before the next write; the complete
  GPT reservation is compared afterward. Failed writes are never retried
  automatically. An already-successful B needs no transaction.

All three Python files run together from a root-only RAM directory on the
native phone. Keep the original snapshot and plan on the computer as well.
Stage the reviewed loader there for the exact-prefix check. Example of the
final command, **after** those files and safety checks are in place:

```sh
python3 /run/flame-boot-repair/boot_success_apply.py \
  --backup /run/flame-boot-repair/before.json \
  --backup-sha256 "$verified_backup_sha256" \
  --plan /run/flame-boot-repair/plan.json \
  --plan-sha256 "$verified_plan_sha256" \
  --loader /run/flame-boot-repair/loader.img \
  --loader-sha256 "$reviewed_loader_sha256" \
  --apply-only-boot-b-successful
```

Use a current checksum-verified private backup set, PID 1's hardware watchdog,
external logging and an independent RAM return-to-fastboot timer. The
calibration manifest must already use the label-based RAM links. Cancel
the timer only after a fresh recovery SSH login. An unexpected result is
a stop condition, not a reason to weaken the guard or restore calibration.

The apply command checks that PID 1 holds the watchdog and that this timer
is running. Arm it from the independently verified **RAM recovery SSH**
session (port 2222), not from an unverified root filesystem connection:

```sh
cat > /run/flame-boot-repair-deadman.sh <<'EOF'
#!/bin/sh
/bin/busybox sleep 120
/sbin/reboot-to bootloader
EOF
nohup /bin/sh /run/flame-boot-repair-deadman.sh \
  >/run/flame-boot-repair-deadman.log 2>&1 </dev/null &
echo $! > /run/flame-boot-repair-deadman.pid
```

Keep the computer's logging connection open, apply the reviewed transaction
from native Arch, then use a **new** RAM SSH login to check and stop the
saved timer PID. Do not leave a successful repair waiting for that reboot.

## Installation and recovery gates

| Step | Expect / pass | Stop condition | Rollback | Risk |
| --- | --- | --- | --- | --- |
| Check the recovery image, owner backups and temporary storage loader | Matching factory boot B retained; native ext4 root and reviewed loader already tested | Missing evidence or checksum mismatch | Stay in Android fastboot | Low |
| Stage the exact loader with `bin/omamobile images` | Checked `DEVICE`, role and image checksum | Wrong header/device/hash | Delete local staged output | Low |
| Install with `bin/omamobile flash` | Only boot B erased/written; flag-clear result stays in fastboot | Any identity, erase or flash failure | Restore the checked stock boot B through `stock-recovery` role; Android also needs a data reset | High |
| Historical failed-installation repair (policy hold) | B is still active, bootable and has attempts remaining | Wrong slot or exhausted B | Stay in fastboot | High |
| Temporarily boot the same reviewed storage loader | Native root, guard, watchdog and control return | Wrong root, storage error or missing control | Buttons to Android fastboot | Medium |
| Snapshot, review and apply the constrained success transaction | Exact loader prefix; one success bit plus checksums; all other GPT bytes and protected hashes unchanged | Any precondition/write/readback mismatch | Stop; preserve both GPT snapshots and Android fastboot | High |
| Restart into Android fastboot and inspect B | `slot-successful:b:yes`, `slot-unbootable:b:no` | Flag missing or slot changed | Remain in fastboot | Low |
| Start normally, then restart from Linux | Different boot ID, native desktop and automatic WLAN association; HTTPS and protected hashes pass | Recovery screen, missing control, firmware/storage/GPU fault | Android fastboot with the buttons | Medium |

Synthetic tests cover the exact write scope/order, padding preservation,
checksums, stale/tampered plans, wrong loader bytes and failures at each
write. Keep those fixtures synthetic; never add a real GPT snapshot.

## Earlier hardware result

The corrected loader prefix matched exactly. The constrained transaction
read back every changed sector and preserved all other GPT bytes and all
storage read-only flags. Android fastboot then reported B successful and
bootable. Starting the installed loader normally, followed by two Linux
restarts, reached native Arch and the desktop each time. WLAN associated
automatically, interface-bound HTTPS returned HTTP 200, and all seven
protected calibration/modem hashes matched. A separate read after those
restarts confirmed the success flag remained set. Complete updated private
partition backups were also verified.

Those first repeat boots had USB connected. With the standalone screen-console
payload, a further connected restart passed, followed by an automatic restart
triggered after cable removal. The owner confirmed the PIN screen returned
while unplugged. A fresh USB login then verified a different boot ID, active
desktop/guard/WLAN services, automatic association, HTTPS 200 and unchanged
protected hashes. The preceding shutdown journal contained no remote-wakeup
errors. The boot-success bit persisted, and no temporary restart units remained.
The repacked payload changed only its Android command-line bytes; kernel,
ramdisk, DT and installed U-Boot loader were unchanged.

## Current validation boundary (2026-10-19)

The later display-corrected installed loader passed four connected starts,
one deliberate crash recovery and an unplugged restart observed by the owner.
Five further display power cycles and the bounded paced-load/idle run passed.
Both GPT CRCs and boot B success remained valid, and all seven protected-data
hashes matched. No metadata transaction is needed again for that handset.

The new recipe removes unused write/menu facilities and adds an invalid-width
arithmetic guard. The native builder also exits on its first guard failure
and no longer starts a USB getty automatically. These publication changes
were host tested/rebuilt, not flashed as part of preparing this PR. Do not
transfer the installed-image test results to these new image bytes without
a new approved RAM boot. Full evidence and remaining limits are in
[native/RESULTS.md](native/RESULTS.md).
