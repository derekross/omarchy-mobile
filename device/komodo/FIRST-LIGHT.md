<!-- SPDX-License-Identifier: MIT -->
# Komodo first-light qualification

Status, 2026-11-09: descriptor parsing and slot-B allowlist checks passed.
This reduced target has not completed a full public-kernel image build or an
attended boot qualification. No installation or peripheral support is claimed.
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

## Boot metadata evidence, inspected 2026-11-09

The descriptor's footer policy was read back with AOSP `avbtool info_image`
from a retained working Komodo development image cohort. The five inspected
image sizes were:

| Image | Footer partition size |
| --- | --- |
| `boot` | 67,108,864 bytes (`0x4000000`) |
| `init_boot` | 8,388,608 bytes (`0x800000`) |
| `vendor_boot` | 67,108,864 bytes (`0x4000000`) |
| `vendor_kernel_boot` | 67,108,864 bytes (`0x4000000`) |
| `dtbo` | 16,777,216 bytes (`0x1000000`) |

All five report `SHA256_RSA4096`, rollback index `1791158400`, rollback index
location `0`, OS-version property `17`, and security-patch property
`2026-10-05`. The descriptor expresses these as `OS_VERSION=17.0.0`,
`OS_PATCH_LEVEL=2026-10` and `AVB_SECURITY_PATCH=2026-10-05`.
The key SHA-1 is `2597c218aae470a130f61162feaae70afd97f011`, AOSP's public
RSA-4096 test key; it is not a Google production signing key.

A separate offline five-image development build on this date reproduced the
same footer policy and passed `avbtool verify_image` for all five images. That
build contains additional development changes and does not qualify the minimal
target here. No vendor images, device captures or private signing keys are
distributed with this change.

This evidence establishes the retained development layout, not the oldest
stock build supported by every Komodo or a universally safe rollback index.
The intended owner's stock slot-A build, chained VBMeta metadata, rollback
constraints, partition sizes and both slots' bootloader versions must be checked
read-only before proceeding. Stop on a mismatch or uncertain provenance and
ask the maintainer; this document grants no firmware, protected-partition or
boot-success write exception. Keep stock on slot A unchanged.

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

4. **One attended slot-B boot (medium risk; not yet qualified).** The human
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

5. **Record qualification (read-only; low risk).** Add a sanitized dated
   result with exact kernel/Mobile commits, release, final DTB identity,
   writer, passed gates and phone-smoke report. Keep identifiers and raw logs
   private. **Pass:** the evidence describes this exact minimal target.
   **Stop:** a private richer build is the only passing run. **Rollback:**
   retain the unqualified status; no capability matrix upgrade.
