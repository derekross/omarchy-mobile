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
zumapro. The device is tracked in [#28](https://github.com/derekross/omamobile/issues/28),
linked from the WIP matrix row. No release-support claim is made.
