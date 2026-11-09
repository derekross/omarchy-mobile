<!-- SPDX-License-Identifier: MIT -->
# Komodo first-light qualification

Status, 2026-11-09: descriptor parsing and slot-B allowlist checks passed.
This reduced target has not completed a full public-kernel image build or an
attended boot qualification. No installation or peripheral support is claimed.
The phone has already run a richer local development kernel; the retained
installation/fallback/boot-success history and unresolved evidence are recorded
in [NOTES](NOTES.md). Do not boot a new kernel/image set until that history,
stock provenance and the maintainer's recovery decision are complete.
Follow [CONTRIBUTING](../../CONTRIBUTING.md) sections 3 and 6 throughout.

## Required kernel source

The published `linux-omarchy-mobile` base inspected for this target is
`1a882ca6916f19ec914fba552c8070683c46ff0f`. It does not contain
`arch/arm64/boot/dts/exynos/google/zumapro-komodo.dts` or its build entry.
Building this descriptor therefore requires the separately prepared series:

| Patch subject | SHA-256 of the prepared patch |
| --- | --- |
| `dt-bindings: arm: google: add Pixel 9 Pro XL` | `02b29c1cfd2ef4c3c57e428e91a75d26dddeb754f888219741ab8fa8fc99cd04` |
| `arm64: dts: exynos: add Pixel 9 Pro XL first-light board` | `7819328db8f33400478ad9da31970d394e27074382ea2469f7553d3ca222a9c2` |

These identify local review artifacts, not published commits. No public PR URL
or qualified kernel head exists for this series yet. Before any build or boot
qualification, replace this pending dependency with its public repository,
exact commit IDs and review link. Recheck the board binding, build entry,
bootargs, reserved memory, watchdogs, UFS and USB against that exact source.
Do not substitute an unpublished development kernel or a sibling board DTB.

## Stock slot-A evidence, captured read-only 2026-11-09

Full `boot_a` and `init_boot_a` partition captures were read through held
O_RDONLY descriptors, with unique PARTNAME, exact size, block-device number,
read-only flag and same-boot checks before and after. The second complete
partition hash and independent host-copy hash matched for both images.
Private images and receipts remain off the public repository.

AOSP `avbtool info_image` on both captured images reports algorithm **NONE**,
rollback index **0**, rollback index location **0**, OS property `17` and
security-patch property `2026-10-05`. Their Android v4 headers are 1584 bytes
and both encode OS version `17.0.0`, patch level `2026-10`. The software
provenance properties identify vendor/software base `CP3A.261005.005`; this is
not an attestation of the whole Android system or Google factory signing.
The descriptor now uses the observed slot-A rollback index `0`.

Current read-only sysfs discovery gives these partition sizes:

| Image | Partition size |
| --- | --- |
| `boot` | 67,108,864 bytes (`0x4000000`) |
| `init_boot` | 8,388,608 bytes (`0x800000`) |
| `vendor_boot` | 67,108,864 bytes (`0x4000000`) |
| `vendor_kernel_boot` | 67,108,864 bytes (`0x4000000`) |
| `dtbo` | 16,777,216 bytes (`0x1000000`) |

The full stock-A captures independently match the first two sizes. These are
sysfs/capture observations, not a claimed `fastboot getvar partition-size`
transcript. That requested bootloader-side evidence remains pending; no
bootloader transition was made to collect it.

### Development policy is not stock provenance

The retained working development cohort and a separate offline development
build used footers on all five images, AOSP's public RSA-4096 test key,
`SHA256_RSA4096`, rollback index `1791158400` and location `0`. That old index
is **not** the slot-A value and is no longer copied into the descriptor. The
working phone has not been rewritten to the new descriptor policy. Historical
development image verification does not qualify a new rollback policy or image
cohort and is not evidence of factory image signing.

The historical early trials do not establish that all five images require
footers: other boot/board changes occurred during bring-up. The all-five footer
list remains an explicitly unresolved policy, not a necessity claim. The
maintainer must review the intended owner's chained VBMeta/rollback behavior,
actual bootloader versions, footer geometry and recovery path before any new
kernel/image boot. Do not change `vbmeta`, bootloader or slot-success metadata
to resolve uncertainty. See [NOTES](NOTES.md) for the prior fallback, lost Linux
root, historical success operation, backup limitations and current conditional
read-only slot-state interpretation.

## Gated runbook

Each hardware operation needs a separate attended human approval. A successful
offline command is not authorization to install, push, flash or reboot.
Use a distinct kernel worktree and output directory; never reuse a current
phone's module directory or another subsystem's build output.

1. **Source and recovery preflight (read-only; low risk).** Resolve the public
   dependency above and record exact Mobile and kernel commits. Confirm the
   stock slot-A recovery path, matching slot bootloaders, this board's partition
   names and sizes, and a complete retained known-good slot-B image/module set.
   Check protected-partition backup checksums off-repository; a stock boot
   requires a fresh read-only backup before radio/PMIC/Trusty work.
   **Pass:** every prerequisite has dated evidence and a recoverable image set.
   **Stop:** missing public source, mismatched firmware, unknown slot state,
   unexplained backup changes or no recovery path. **Rollback:** no change.

2. **Descriptor and build (laptop only; low risk).** With `KERNEL_DIR` set to
   the reviewed worktree and `KERNEL_OUT` to its dedicated output, run:

   ```sh
   DEVICE=komodo bin/omamobile initramfs-config "$KERNEL_OUT/init-check"
   DEVICE=komodo bin/omamobile kernel
   DEVICE=komodo bin/omamobile modules
   DEVICE=komodo bin/omamobile initramfs
   DEVICE=komodo bin/omamobile images
   ```

   **Pass:** the actual public loader emits only `omamobile-ufs-rw` and
   `omamobile-usb-product`; the allowlist contains exactly the five boot images
   suffixed `_b` and `userdata`. Build with `W=1`, validate the built board DTB
   against that kernel's schemas, and record all five image sizes and AVB
   `info_image`/`verify_image` results. Check `/chosen/bootargs`, DT selectors,
   reserved memory and watchdogs in the final DTB, not just the source.
   **Stop:** any missing output, new compiler/schema diagnostic, unexpected
   hardware enablement, absent guard, wrong footer or incompatible metadata.
   **Rollback:** discard only this dedicated build output; the phone is unchanged.

3. **Offline review gate (read-only; low risk).** Run `tools/pr-check` against
   the exact public base, `tests/all` and `tests/packages`; investigate any
   failure on the unchanged base first. Have the complete image/source cohort
   and recovery commands reviewed before requesting a hardware operation.
   **Pass:** all required gates pass or a maintainer resolves a documented
   baseline/environment failure. **Stop:** incomplete evidence or review.
   **Rollback:** no phone change.

4. **Writer and retry-state gate (read-only first; medium risk).** Read the
   actual A/B bootloader versions, B successful/unbootable/retry state and
   current stock-A rollback metadata without changing flags. Historical success
   does not prove current success. A verified successful B with a working Linux
   transport may use the separately approved canonical `push`; it preserves
   the successful mark and its matching modules must be retained. A first
   install/recovery requiring `flash` needs the maintainer's explicit plan:
   `flash` sets B active. On the Pixel 9a (the same Tensor G4 family), even a
   plain suffixed fastboot flash cleared B's successful flag. Komodo must not
   assume that mark survives a flash. Do not substitute manual fastboot writes or
   automatically mark B successful. An unmarked B has only three ABL attempts;
   count every boot including watchdog resets and **stop before the third
   unmarked attempt**. Unknown remaining attempts, an already unmarked
   development B, or the recorded bootloader mismatch means stop and ask the
   maintainer, not one more experimental boot. Fallback to A can overwrite
   userdata and lose the Linux root before any recovery prompt is answered.
   **Pass:** the maintainer resolves the starting state, writer, remaining
   attempts, exact recovery set and backup chronology. **Stop:** any unknown or
   conflicting state. **Rollback:** no change; never clear/repair flags as a test.

5. **One attended slot-B boot (medium risk; not yet qualified).** The human
   first approves the exact reviewed image cohort, writer and recovery path.
   Only `DEVICE=komodo bin/omamobile push` or `flash` may write boot images;
   neither is authorized by these instructions. The recovery choice depends
   on the verified slot state: do not guess, unmark a slot experimentally or
   write `devinfo`. Announce the reboot and keep the cable attached. Arm the
   reviewed log stream, hang marker and hardware watchdog as the board runbook
   requires before any risky driver activity; perform no peripheral probes.
   **Pass:** USB and a fresh SSH session return, the running release and
   board match the reviewed source, and `tools/phone-smoke` confirms slot B,
   the guard and the root layout without new kernel faults.
   **Stop:** no fresh SSH within the reviewed timeout, unexpected fallback,
   storage changes or kernel fault. Do not send more commands to a hung phone.
   **Rollback:** allow the watchdog/shutdown timeout to finish, then use the
   human's verified button recovery and separately approved canonical writer
   with the retained known-good slot-B set. Never write slot A, choose a
   factory reset or lift the storage guard to recover. Any stock boot means
   stop and take a fresh read-only backup after returning safely to Linux.

6. **Record qualification (read-only; low risk).** Add a sanitized dated
   result with exact kernel/Mobile commits, release, final DTB identity,
   writer, passed gates and phone-smoke report. Keep identifiers and raw logs
   private. **Pass:** the evidence describes this exact minimal target.
   **Stop:** a private richer build is the only passing run. **Rollback:**
   retain the unqualified status; no capability matrix upgrade.
