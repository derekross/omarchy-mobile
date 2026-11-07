<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a (tegu): first-light review gates

Status, 2026-10-22: **WIP; firmware equalisation and normal-HCRX/KVM
control passed; B mark-successful layout agreed, peripherals pending**.
This is a staged review runbook, not an installation guide. Public tegu
kernel support, shared SOC_COMPATIBLE image tooling and a device package
are not available from this PR. The descriptor intentionally fails closed.
Historical results and source citations: [NOTES](NOTES.md).

Prototype kernel branch: private `omamobile-tegu-touch-power`;
worktree/output: `wt-touch-power` / `out-touch-power`; release:
`7.3.0-rc6-omamobile-tegu-tn3-g1cb4bd36f3be-dirty`.
The completed equalised-firmware control uses private branch
`omamobile-tegu-firmware-control`, worktree/output `wt-firmware-control` /
`out-firmware-control`, GNU build ID
`bd787a42658c58ed023e7bb6c203d46844e294b9`. Exact source/config/image/module
identities are retained privately. A dirty release string alone cannot
identify a kernel or reproduce the test; see the recorded result below.

## 0. Freeze the baseline and review the write boundary

**Risk:** low, read-only. Keep the working native B image set, exact
kernel/modules/manifests and protected backups outside the repository.
Verify sizes and SHA-256 checksums, known recovery instructions and stock
A's rollback build. Record the current boot ID/release and which services
would start automatically. Keep generic boot-success marking masked and
remove any automatic custom devinfo-marking path from the proposed retest.

**Expect / pass:** an exact, recoverable baseline; every protected backup
verifies; no devinfo writer will start. **Stop:** absent backup, unknown
layout, untracked boot-time writer or unidentified image/module mismatch.
**Rollback:** none; read-only. Do not change any partition permission.

## 1. Record slot and image facts

**Risk:** low for existing-file inspection; medium if a newly authorised
capture requires leaving Linux or changing slots. Announce screen changes,
obtain approval for that specific recovery/capture sequence and keep laptop
logs. Do not boot an unverified original B Android just to fill a table.

The private capture should retain `fastboot getvar all`. From Android on
each confirmed running stock slot, collect only these fields for the public
record (full logs remain private):

```sh
adb shell getprop ro.boot.slot_suffix
adb shell getprop ro.bootloader
adb shell getprop ro.build.id
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.security_patch
adb shell getprop ro.boot.dtbo_idx
```

**Expect / pass:** a slot-tagged build/loader table, with unknowns retained;
stock partition names/sizes, factory dtbo count/selected board ID/revision,
and live-DT `/soc_compatible` tuples where readable. If unrooted access is
unavailable, retain artifact-derived tuples as candidates and explicitly
record that limit; do not alter stock verification state to obtain them.
Bootloader selection and the
resident bootloader must be distinguished: changing active slot alone does
not reload its firmware. Sanitize identifiers before sharing any fact.
**Stop:** unresponsive phone, slot ambiguity, unexpected loader or lost
recovery path. **Rollback:** approved return to the frozen native B setup
or known stock A; no firmware downgrade. After *any* stock Android boot,
take fresh read-only protected backups before later peripheral work,
preserving the prior backups for comparison.

## 1a. Read-only devinfo layout comparison

**Risk:** low for guarded reads; medium for the separately announced boot
transition. Derek requested this pair on 2026-10-22: record version 3.15 and
only bytes 0x30–0x37 alongside ABL’s successful, unbootable and retry-count
getvars for both slots. Keep full captures and backups private. Read the
bytes before leaving guarded Linux and query ABL before selecting a slot,
flashing or issuing any other boot-control operation. Record whether ABL
itself changed anything on entry rather than assuming identical state.

**Expect / pass:** ABL’s values match the predicted byte meanings, then a
second pair across a firmware-managed slot-state event confirms the change.
An unmarked B boot should decrement B’s retry byte 0x34 by one. A static
match alone does not complete this request or authorise a manual write.
**Stop:** unknown version, ambiguous state transition or contradictory
flags. **Rollback:** none for reads; use the separately planned boot
recovery. No custom marker, retry refresh or direct devinfo write.

## 2. Equalise stock firmware — maintenance gate

**Risk:** high; system/firmware replacement, anti-rollback and loss of the
current B prototype. **Completed twice with stock recovery status 0;
recorded results below.** The maintainer explicitly requested
the same full OTA sideloaded twice, then selecting A, following PR #23.
Treat this as the requested stock-maintenance operation, separate from
ordinary five-image B development. Done on 2026-10-22 at the
maintainer's request; repeating it needs a new go. It does not authorise individual bootloader/radio/vbmeta/slot-A
fastboot writes or use of our devinfo marking tool.

Before execution, pin the exact official full-OTA build for tegu, verify
its checksum/compatibility and anti-rollback requirements, and prove the
backup and recovery route. The prepared candidate BP3A.250905.014 matches
captured A, with its published checksum and stock-image correspondence
verified. Account for B's replacement and for stock Android encountering
the Arch filesystem on userdata. Preserve the working Linux file backup,
matching modules and B images first. Do not assume recovery menus or a
stock first boot can be driven remotely; use attended recovery unless a
standard noninteractive route has been established. Do not assume an
older factory image remains bootable after the update. Absence of devinfo
as a payload partition does not mean stock A/B bookkeeping never updates
metadata, and is not a workaround for the manual-write restriction.

**Expect / pass, following the maintainer's requested evidence:** both
resident loaders report the same version after the two official OTA passes;
guarded readback verifies both slots' top-level/system AVB signatures,
stock-zero flags and correspondence to the selected build. Stock A boots
and reports that build and loader. A single getvar or the two sideload
success messages alone do not prove equality. Preserve the slot-tagged
evidence and take fresh protected backups after the final stock boot.
Successful stock-B Android boot is a stronger, separate observation and is
not claimed by this maintenance result.
**Stop:** unresolved recovery/policy scope, checksum/build/device mismatch,
rollback uncertainty, slot mismatch, OTA failure or unexpected slot state.
**Rollback:** use only the maintenance procedure's approved recovery at the
new rollback level; never downgrade firmware. Until this gate passes, do
not publish a general workaround or proceed to the HCRX/KVM retest.

## 3. Derive descriptor header values from that stock build

**Risk:** low, offline/read-only. Extract the verified equalised build's
stock `init_boot.img` and parse its header with AOSP `unpack_bootimg`.
Record source build, tool revision, image SHA-256, header version and the
decoded OS version / security patch level. A read-only copy from the
confirmed running stock slot can establish image correspondence when
available; do not use fastboot fetch support as an assumption.
Offline template (replace paths with the pinned artifacts; output stays private):

```sh
python3 /path/to/aosp/system/tools/mkbootimg/unpack_bootimg.py \
  --boot_img /path/to/equalised-stock/init_boot.img \
  --out /tmp/tegu-stock-init-boot-header
sha256sum /path/to/equalised-stock/init_boot.img
```

**Expect / pass:** OS_VERSION and OS_PATCH_LEVEL derived from this stock
init_boot header, with traceable correspondence to both-slot evidence.
**Stop:** zero/ambiguous header values or disagreement with the selected
build. Android properties and an older custom bundle are not replacements
for a header parse. **Rollback:** none. Only then restore the two descriptor
assignments; shared selector support still needs separate review/tests.

## 4. Build the no-workaround, KVM-enabled control

**Risk:** low, offline. Use an isolated kernel worktree/output and pinned
base. Remove the HCRX_EL2 bypass, set `CONFIG_KVM=y`, and remove command-line
or feature overrides which disable KVM or hide the relevant EL2 feature.
Audit the final packed DT bootargs and bootloader-appended command line,
not just the source config. Use explicit build directories; with the pinned
ARM64 toolchain/config already selected, the offline command templates are:

```sh
KERNEL_DIR=/path/to/wt-tegu-kvm KERNEL_OUT=/path/to/out-tegu-kvm \
  bin/omamobile kernel
make -C /path/to/wt-tegu-kvm O=/path/to/out-tegu-kvm \
  ARCH=arm64 LLVM=1 W=1 Image dtbs modules
make -C /path/to/wt-tegu-kvm O=/path/to/out-tegu-kvm \
  ARCH=arm64 LLVM=1 W=1 dt_binding_check dtbs_check
```

Run strict `scripts/checkpatch.pl --strict` on the isolated patch; retain
complete build/schema logs privately and resolve diagnostics before images.
Keep all unrelated board/subsystem changes
identical. Match modules to this exact Image and retain both hashes.

**Expect / pass:** a reproducible diff proving no HCRX workaround, KVM on,
clean strict checkpatch, W=1, relevant binding/DT validation and Android-v4
packing/AVB load checks. Public image tooling must not be bypassed with a
fabricated SOC_IDS. **Stop:** any unreviewed boot workaround, unrelated
change, warning or missing source. **Rollback:** discard the candidate;
no phone change. Do not silently use the prototype's KVM-disabled Image.

## 5. One supervised native B boot and KVM test

**Risk:** high, potential early hang/reset. Run only after gates 0–4 and
specific operator approval. Prepare a hang marker, laptop log stream,
watchdog/dead-man recovery and matching modules before the test. Keep
stock A intact. Write only the five B boot images through the reviewed
project flash/push path, after generic selector support is available.
Do not write devinfo or unmask boot-success marking. Retry exhaustion is
possible; bound the trial and retain attended fastboot recovery.

**Expect / pass:** normal B-resident firmware loads Linux without a
laptop RAM-boot assist; eight CPUs and guarded native root/USB return;
both inherited cluster watchdogs are taken over and the boot remains
healthy beyond their approximately 60-second expiry (brief SSH is not a
pass); the final command line permits KVM, `/dev/kvm` exists, KVM initialises
without EL2 faults, and a minimal guest actually runs. Mere boot with
CONFIG_KVM=y is not proof of working KVM. Save source/config/image/module
identities, exact equalised build/loader, log excerpts and guest result.
**Stop:** first unexpected reset, timeout, EL2 fault, storage-guard change,
missing log/recovery or absent KVM; do not repeat to consume all retries.
**Rollback:** approved return to verified B rollback images compatible
with the new firmware, or stock A via attended fastboot. No devinfo write.

If the control succeeds, drop the old-firmware workaround entirely. If it
fails, preserve the first discriminating trace and discuss it before any
new kernel workaround. This PR must retain the outstanding status until
that evidence exists.

## 6. Slot B marked successful by hand

**Status (2026-11-07):** tool written, **never run on a phone**; it waits for
the maintainer's review of its pull request. The 9a's hold in AGENTS.md ("Pixel 9a: a fallback to slot A costs the Linux root") still stands: nothing here may run until the maintainer has merged the tool and lifted it.

The decision on [#252](https://github.com/derekross/omarchy-mobile/issues/252):
slot B is marked successful by hand, attended, once per install of slot B's
images, and only after that image set has booted cleanly and passed
`tools/phone-smoke`. Never on the first boot of an untested image, and never
from a unit, a hook or the installer. Once B is marked, ABL no longer falls
back to slot A, so a broken image after that means fastboot by the buttons
(with the phone off, Volume Down then Power, both held about 20 s). Any fastboot flash of slot B's images clears the mark again
([NOTES](NOTES.md) 2026-10-31); mark again only after the new set passes the smoke test.

The tool is `omamobile-bootctl` from `omamobile-device-tegu`
(`packages/omamobile-device-tegu/src/omamobile-bootctl.c`, the same source as
the husky package; this phone's values in `src/bootctl-device.h`). It
refuses another board, a devinfo version other than 3.15 (the one recorded
for tegu: [NOTES](NOTES.md) "Read-only layout evidence after official OTA maintenance", the pair across a boot that spent a try, and the three marks of 2026-10-22 to 10-31), a boot from slot A, a slot B that isn't active or is
marked unbootable, and a storage guard that isn't holding (the main LUN's
whole-disk node usable, or any disk or partition outside `UFS_RW` writable).
It prints the devinfo version and the eight slot bytes 0x30-0x37, decoded,
and nothing else from the partition.

**Its read-write window.** The kernel can't write a partition of a read-only
disk: `bdev_read_only()` is the partition's own flag OR its disk's
(`include/linux/blkdev.h`), and the write path (`blkdev_write_iter()`), the
`BLKROGET` ioctl and sysfs `ro` all use it. So `devinfo` can't be made
writable while its boot LUN stays read-only, and the tool clears the LUN's
flag too, for as long as the one byte takes. What that exposes beyond
`devinfo` is the whole-disk node: each sibling partition on the LUN (on
husky `pinfo`, `blenv`, `mfg_data`) keeps its own flag, which the storage guard set, and the tool
checks each one right after clearing the disk's (the only moment a
partition's own flag can be read) and closes again if any is clear. In order:
the disk writable; the siblings' and devinfo's own flags checked; devinfo
writable; devinfo read again and compared with what the checks saw; one byte
written (0x35, slot B's flags, OR 0x02) with `O_DSYNC`; the whole partition
read back past the page cache (`O_DIRECT`) and compared with the prediction
(on a mismatch the original is written back and read back, and the tool
fails); devinfo read-only and checked; the disk read-only and checked. ^C,
SIGTERM and SIGHUP are blocked for the window, and a relock child sets both
flags back if the tool is killed, stops or hangs for 10 s. Before opening it,
the tool refuses if devinfo is mounted or held, or if any other process has
the LUN or one of its partitions open for writing.

Each step: risk, command, expect / pass, stop, rollback. Record the results
here with the date and `uname -r`. Post only the version and the eight slot
bytes, never a dump.

1. **Preconditions** (none; read-only). The installed image set has booted
   cleanly at least once and `tools/phone-smoke` passed on it (keep the
   report). `pacman -Q omamobile-device-tegu` shows the version with the tool,
   built from the merged source. The layout pair is recorded
   ([NOTES](NOTES.md), 2026-10-22); repeat it if the bootloader was updated
   since.
   **Stop:** any of these missing. **Rollback:** none.
2. **Status** (none; read-only). `omamobile-bootctl status`.
   **Expect:** `devinfo version 3.15 (the layout recorded for tegu)`, `booted
   from slot b`, `storage guard: holding`, slot b active, not successful, not
   unbootable. **Stop:** any refusal, another version, slot a booted, the
   guard not holding. **Rollback:** none.
3. **Dry run** (none; read-only: nothing is opened for writing).
   `omamobile-bootctl mark-b-successful`. **Expect:** `planned: byte 0x35 XX
   -> YY (slot b successful), nothing else`, where YY is XX OR 02, and the
   write command with this boot's eight bytes. Post the output on #252 and
   wait for the maintainer's go. **Stop:** any other plan, a refusal, no go.
   **Rollback:** none.
4. **Read-only backup** (none; read-only). From the laptop,
   `tools/nv-backup DIR` (devinfo is in the descriptor's `NV_BACKUP_EXTRA`),
   then `tools/nv-backup --check DIR` right before step 5. Keep it off the
   repository. **Expect:** every copy verified, and the check matches live
   storage. **Stop:** a failed copy or a mismatch. **Rollback:** none.
5. **The write** (medium: one bit of `devinfo`, outside the allowlist). With a
   kernel log stream to the laptop running and nobody about to reboot the
   phone: `omamobile-bootctl mark-b-successful --write --codename tegu
   --expect "<the eight bytes from step 3>"`. Nothing changes on the screen.
   **Expect:** exit 0, `before` and `after` lines that differ only in byte
   0x35 by 0x02, then `slot b marked successful: written, read back, devinfo
   and <its LUN> read-only again`. **Stop:** any other exit, and don't run it
   again: exit 1 or 2 refused before anything was opened; 3, the write
   failed or was put back and devinfo reads as before; 4, devinfo may differ
   from the backup (don't reboot; post the output and wait); 5, a read-only
   flag could not be restored (`systemctl reboot`: the initramfs sets it
   again). **Rollback:** the mark is undone by flashing slot B's images
   (`bin/omamobile flash` with a known-good set), which clears it; the
   step 4 backup is for exit 4, and writing it back is the maintainer's call.
6. **Read back** (none; read-only). `omamobile-bootctl status` again, then
   `tools/nv-backup --check DIR`. **Expect:** slot b successful, the guard
   holding; the check differs only in `devinfo`, and a fresh read-only copy
   of it differs from the backup in byte 0x35 alone (`cmp -l` prints one
   line, offset 54). **Stop:** anything else. **Rollback:** as in step 5.
7. **ABL's view** (low: one trip to fastboot, which spends no try with B
   marked). `reboot-to bootloader`, then `fastboot getvar slot-successful:b`,
   `slot-unbootable:b` and `slot-retry-count:b`, then `fastboot reboot`.
   **Expect:** `yes`, `no`, and the phone boots slot B again. **Stop:** `no`
   for successful: post it and don't repeat the write. **Rollback:** as in
   step 5.

## Recorded control result, 2026-10-22

Both official OTA passes, stock-A build properties, both-slot signed AVB
flags 0 and fresh protected backups pass. Two ordinary installed-B boots
reach guarded internal root with normal HCRX and all eight CPUs. A real
ARM64 KVM guest passed on the first control boot. Sources, build identity,
exact eight-byte layout pairs and remaining qualifications are recorded
in [NOTES](NOTES.md). This supersedes the pending firmware/control status;
it does not qualify desktop peripherals on the new firmware. The later
maintainer-approved B mark-successful operation also passed: a fresh
backup and full comparison verified only byte 0x35 OR 0x02, the guard was
restored and ABL confirmed successful=yes. Only this marking operation
is agreed; no set-active or other devinfo write. See the before/after
eight-byte record in NOTES.

## Submission boundaries

Keep UFS clock-stop ordering, touch power/ACPM/regulator support and Panthor
SoC hash data in separate kernel subsystem PRs, each with its own source,
bindings, checks and measured evidence. Shared SOC_COMPATIBLE packing also
needs a separate tooling PR with images-layout coverage for zuma and
zumapro. The device is tracked in [#28](https://github.com/derekross/omarchy-mobile/issues/28),
linked from the WIP matrix row. No release-support claim is made.
