<!-- SPDX-License-Identifier: MIT -->
# Pixel 6a: reconcile reserved memory before further bring-up

Status (2026-11-06): the approved M2 boot **passes live memory validation**;
fresh post-stock backups and their independent check are complete. USB SSH
timeouts during bulk copy remain a separate observation. The first-boot kernel is
`7.3.0-rc6-omamobile-push1-g29a7a9326bf0`, published kernel commit
`29a7a9326bf0`, branch `omamobile-bluejay-m1-20261105` in
`~/android/mainline/wt-bluejay-m1-20261105`, output
`~/android/mainline/out-bluejay-m1-20261105`. No new driver or register
probe is authorized by this plan. First-boot results: [NOTES](NOTES.md).

## Evidence and limits

The native live FDT has twelve enabled static reserved-memory entries,
covering eleven distinct ranges. All are excluded from unreserved System
RAM in the captured iomem, but two entries cover the same debug-info page.
This exclusion check alone does not validate the stock-reference layout.

The verified, read-only stock-A `vendor_boot` backup contains two stock
base DTBs, A0 and B0. Applying entry 9 (MP1.0, board ID `0x20506`, revision
`0x10000`) from stock A's `dtbo` to B0 succeeds offline. This reconstructed
tree has twenty-two enabled static reserved regions and five nodes without
a static `reg`. It is **not** a captured stock live DT: ABL runtime edits,
memory reservations and its DPM overlay are not represented. Stock Android
did not expose `/sys/firmware/fdt` to the unprivileged shell.

These stock ranges overlap native unreserved System RAM:

| Stock node | Start | Size | Native unreserved overlap |
| --- | --- | --- | --- |
| `ect_binary` | `0x90000000` | 237568 bytes | entire range |
| `abl@f8800000` | `0xf8800000` | 32 MiB | `0xf9800000`–`0xfa800000` (end exclusive) |
| `suspend_diag_log_reserved@fd90c000` | `0xfd90c000` | 4 KiB | entire range |
| `ramoops_mem@fd3ff000` | `0xfd3ff000` | 4 MiB | entire range |
| `cp_rmem` | `0xf0000000` | 8 MiB | entire range |
| `cp_rmem_1` | `0xe8000000` | 28 MiB | entire range |
| `cp_rmem_2` | `0xee000000` | 4 MiB | entire range |
| `seclog_mem` | `0xc3000000` | 512 KiB | entire range |
| `xhci_dma@97000000` | `0x97000000` | 4 MiB | entire range |

Nodes without static `reg`: `vstream`, `vframe`, `vscaler`, `tui`, `mfc_fw`.
Their dynamic allocations cannot be compared by assuming an address.

An overlap is an audit candidate, not proof of an active firmware writer.
Some stock buffers serve Android drivers which are not running in the M1
kernel. Do not blindly reserve all stock ranges or claim all can be freed.

## Resumed audit: allocator reservations are not firmware carve-outs

[V] Re-examining the saved first-boot log finds CMA at
`[0xc8000000, 0xe0000000)` (384 MiB) and the software I/O TLB at
`[0xf4800000, 0xf8800000)` (64 MiB). Both appear as child `reserved`
resources inside System RAM in iomem. They are Linux allocation pools,
not proof that overlapping stock buffers are protected. The original
comparison subtracted those child resources and therefore missed seven
additional candidates:

| Stock node | Range, end exclusive | Native allocator overlap |
| --- | --- | --- |
| `header` | `0xd8100000`–`0xd8110000` | CMA, 64 KiB |
| `log_kevents` | `0xd8110000`–`0xd8810000` | CMA, 7 MiB |
| `log_s2d` | `0xd8810000`–`0xda010000` | CMA, 24 MiB |
| `log_array_reset` | `0xda010000`–`0xdaa10000` | CMA, 10 MiB |
| `log_bcm` | `0xdd610000`–`0xdda10000` | CMA, 4 MiB |
| `log_itmon` | `0xdda10000`–`0xdda20000` | CMA, 64 KiB |
| `cp_msi_rmem` | `0xf6200000`–`0xf6201000` | SWIOTLB, 4 KiB |

There are consequently **sixteen**, not nine, stock static regions not
wholly covered by native static reserved-memory entries. Nine intersect
the earlier definition of unreserved RAM; six intersect CMA and one
intersects SWIOTLB. This identifies layout conflicts to investigate; it
does not establish that firmware currently accesses those addresses.

The distinction follows the running kernel's
[CMA implementation](https://github.com/derekross/linux-omarchy-mobile/blob/29a7a9326bf064c7079396090c262271196b4a7b/mm/cma.c)
and [SWIOTLB implementation](https://github.com/derekross/linux-omarchy-mobile/blob/29a7a9326bf064c7079396090c262271196b4a7b/kernel/dma/swiotlb.c).
The stock debug consumer is Google's
[debug-snapshot driver](https://android.googlesource.com/kernel/google-modules/soc/gs/+/204078758737776959ecc85c527a00fd2cabb62f/drivers/soc/google/debug/debug-snapshot.c),
which acquires the described memory regions and initializes its enabled
buffers. That driver is absent from the native board's device tree.
The driver sources do not establish which firmware-only dump paths may
still run. Keep that uncertainty separate from Linux driver activity.

## Consumer trace and disposition

Reference sources are Google's GPL
[gs101 reservations](https://android.googlesource.com/kernel/devices/google/gs101/+/refs/tags/android-16.0.0_r0.9/dts/gs101-rmem.dtsi),
[SoC tree](https://android.googlesource.com/kernel/devices/google/gs101/+/refs/tags/android-16.0.0_r0.9/dts/gs101.dtsi)
and the consumers below. These Android 16 references have not been proved
identical to the phone's Android 17 firmware. Driver presence, handshake
requirements and a static DT cannot prove that a firmware agent is idle.

| Candidate | Verified consumer or runtime fact | Disposition before a new image |
| --- | --- | --- |
| ECT | Stock `exynos-ect` references `ect_binary`; its GPL parser maps that reservation. The native live `/ect` has address `0x90000000`, size `0x34000`, although the built tree's node was empty. The stock static reservation is `0x3a000`. | Preserve boot-populated data in a proposed board reservation; check bounds against live properties. Do not read its payload or treat it as unused because the native parser is absent. |
| ABL | Both stock reference and built native DTB reserve 32 MiB at `0xf8800000`. The native live DT and early log reserve only 16 MiB at the same base. | Runtime contraction is observed; its purpose is unknown. A source-only size change can be overwritten again. Resolve the runtime contract or design an independently checked conservative reservation before claiming protection of the tail. |
| Suspend diagnostic page | Stock DT references the page from `pixel-suspend-diag`. In the inspected GPL driver, probe creates sysfs controls and the state is a static kernel object; no use of that `memory-region` was found there. | An unused property in this driver is not proof no other agent uses the page. Keep as an unresolved diagnostic ABI candidate or quarantine conservatively. |
| Ramoops | Stock node binds the standard ramoops backend, with 2 MiB console and 2 MiB pmsg storage. M1 has `CONFIG_PSTORE_RAM=y` but no ramoops DT node. | No active M1 ramoops backend is established. Reserving bytes and enabling a persistent-log writer are separate changes; importing the stock compatible would enable behavior. |
| CP IPC, RX, TX | Stock `cp_shmem` uses reservation indices 0, 2 and 3 for IPC, PKTPROC and PKTPROC_UL. IPC's described 4 MiB region is within an 8 MiB reservation. | No CPIF module is loaded in M1. This does not establish the physical CP state. A future modem stage needs explicit ownership of all four reservations, including MSI, before power/link changes. |
| Secure log | GPL probe maps the reserved buffer and passes address, size and interrupt to EL3 via `SMC_CMD_SEC_LOG_INFO`; the header defines eight 64 KiB buffers at `0xc3000000`. | Native driver/handshake absent; secure-world behavior without that handshake is not proved. Conservatively preserve the buffer or establish the firmware contract; do not infer inactivity from missing Linux logs. |
| xHCI DMA | Stock DWC3 references a fixed 4 MiB shared DMA pool; Google's xHCI allocator assigns it through reserved-memory operations. Native M1 uses USB peripheral mode without this pool reference. | Host/offload pool consumer is not established in M1. Any later host/offload change must revisit this region and the AoC relationship. Importing pool bindings is separate from excluding RAM. |
| Six snapshot buffers | GPL debug-snapshot maps and initializes enabled regions; all six stock addresses fall inside native CMA. | Resolve firmware ownership and allocator placement together. A normal iomem `reserved` child is insufficient evidence. No debug driver or firmware dump service should be enabled as a diagnostic shortcut. |
| CP MSI | Stock index 1 supplies the MSI page; the native default SWIOTLB pool includes that address. | Include this page in the CP memory policy. Verify any reservation change relocates SWIOTLB safely instead of assuming its old address stays valid. |

Consumer references:

- [ECT probe](https://android.googlesource.com/kernel/google-modules/soc/gs/+/204078758737776959ecc85c527a00fd2cabb62f/drivers/soc/google/ect_parser.c)
- [Suspend diagnostic driver](https://android.googlesource.com/kernel/google-modules/soc/gs/+/204078758737776959ecc85c527a00fd2cabb62f/drivers/soc/google/debug/pixel-suspend-diag.c)
- [Native ramoops implementation](https://github.com/derekross/linux-omarchy-mobile/blob/29a7a9326bf064c7079396090c262271196b4a7b/fs/pstore/ram.c)
- [Stock CP memory-region wiring](https://android.googlesource.com/kernel/devices/google/gs101/+/refs/tags/android-16.0.0_r0.9/dts/gs101-cp-s5200-sit.dtsi),
  [CP shared-memory parser](https://android.googlesource.com/kernel/google-modules/radio/samsung/s5300/+/a8976934fe7f396627f9900958eb1457a74ebcca/shm_ipc.c),
  [CP power control](https://android.googlesource.com/kernel/google-modules/radio/samsung/s5300/+/a8976934fe7f396627f9900958eb1457a74ebcca/modem_ctrl_s5100.c)
- [Secure-log handshake](https://android.googlesource.com/kernel/google-modules/soc/gs/+/204078758737776959ecc85c527a00fd2cabb62f/drivers/soc/google/exynos-seclog.c),
  [buffer constants](https://android.googlesource.com/kernel/google-modules/soc/gs/+/204078758737776959ecc85c527a00fd2cabb62f/include/dt-bindings/soc/google/exynos-seclog.h)
- [xHCI pool declaration](https://android.googlesource.com/kernel/devices/google/gs101/+/refs/tags/android-16.0.0_r0.9/dts/gs101-dma-heap.dtsi),
  [allocator](https://android.googlesource.com/kernel/google-modules/soc/gs/+/204078758737776959ecc85c527a00fd2cabb62f/drivers/usb/host/xhci-goog-dma.c)

## Native duplicate and bootloader edits

[V] The live tree contains both `debug-kinfo-reserved@fd3fe000` and
`debug_kinfo_reserved@fd3fe000`, each covering `[0xfd3fe000, 0xfd3ff000)`.
The former is in the built DTB; the latter is additional in the live tree.
The early kernel log explicitly reports their overlap. This is a duplicate
reservation of the same page, not evidence the page was allocatable.
The exact bootloader code which added it is not available in this audit.

The recorded native twelve-entry exclusion result remains true, but it is
not a clean overlap check. A board-local naming fix must be compared with
the bootloader's actual injection behavior and keep the existing label's
consumers intact. Do not change shared gs101 behavior solely from bluejay.

## Next offline work and Wi-Fi attribution

The candidate below completes the initial offline proposal and build.
Its observed-bootloader projection is not a verified live result. Keep the
remaining runtime checks as gates, rather than treating the model as proof
of the next boot's layout.

1. Choose and document retention versus conservative exclusion for every
   candidate. Keep the five dynamic stock nodes separate. Do not add their
   guessed boot addresses to a static map.
2. Design a board-only candidate which accounts for the observed ABL
   contraction and duplicate debug-info node. State which runtime edits it
   expects, and how a subsequent live capture would falsify that expectation.
3. Recompute CMA and SWIOTLB placement from the candidate reservations and
   Linux's allocation rules, including DMA address limits. Check the kernel,
   initrd, splash and other bootloader reservations as well as each other.
   A reservation which intersects a current pool requires this analysis;
   it must not be applied to the running kernel.
4. Build a memory-only image set in a new output directory, with no PCIe,
   Wi-Fi, PMIC, display or rootfs enablement. Review the DTB changes and
   schemas, then prepare an attended approval-gated boot and rollback.
5. Record before/after allocator placement in [WIFI-PLAN](WIFI-PLAN.md).
   Memory changes can change future DMA addresses; that is a hypothesis
   to measure, not an identified explanation of the 7a's failure.

Reproduction, entirely offline:
`python3 ~/android/reference/bluejay-memory-audit-20261106/audit-memory.py`.
It reads the saved live and built DTBs, iomem, dmesg and original comparison;
its JSON receipt pins input hashes and checks the 12/11 native entries/ranges,
22 stock regions, 9 direct candidates, 6 CMA candidates, 1 SWIOTLB candidate,
16 incomplete static covers, ECT properties, ABL contraction and duplicate.
Raw DTs, source copies and receipts stay outside the public repository.

Resumed read-only SSH at uptime 3484 seconds identified the same kernel and
boot ID as the handoff, zero loaded modules and an absent `/dev/sda`.
No new kernel patch, build, driver load, register access, reboot or flash
was performed during this audit.

## 2026-11-06: conservative memory-only candidate M2

Worktree `~/android/mainline/wt-bluejay-memory-20261106`, branch
`omamobile-bluejay-memory-20261106`, base `29a7a9326bf0`; output
`~/android/mainline/out-bluejay-memory-20261106`.
Only `arch/arm64/boot/dts/exynos/google/gs101-bluejay.dts` is changed.
The M1 source tree/output and phone images have been preserved.

All sixteen unresolved reference ranges receive independent board-local
exclusions, based on the consumer trace above. This chooses conservative
retention instead of asserting that absent Linux drivers make firmware
buffers reclaimable. About 109.86 MiB is withheld from ordinary Linux
allocation. The new nodes have `no-map` and no driver or DMA-pool compatible:
they do not start CPIF, secure logging, ramoops, xHCI offload or snapshot
collection. Any later consumer needs a separate mapping/ownership review.
The five dynamic Android pools are not added.

The named ABL node is split into the observed 16 MiB prefix and an
independent 16 MiB tail exclusion. This preserves the full stock reference
extent without relying on ABL retaining the original node's 32 MiB size.
The debug-info node uses the underscore spelling observed live, while
retaining its shared source label. No other board's shared DTS is changed.
These choices predict specific runtime behavior; a different ABL edit or
another duplicate is a failed live gate.

The ECT exclusion covers the stock static `0x3a000` size and the captured
live `0x34000` payload at `0x90000000`. A changed live address or a size
outside the reservation is a stop condition, not permission to inspect the
payload or enlarge a live reservation.

### Allocator evidence and limits

A host harness links the pinned kernel's actual `mm/memblock.c` through
its tools/testing headers, with address/undefined-behavior sanitizers. Slab
use and region-table growth abort instead of being simulated. The broader
upstream simulator build lacked liburcu; this is a focused allocation test,
not a claim that the full upstream test suite passed.

Inputs are the saved RAM banks, static exclusions, FDT reservation map and
kernel/initrd/other boot allocations from the original capture. The
allocation order and constraints follow `arch/arm64/mm/init.c`,
`mm/cma.c`, `kernel/dma/contiguous.c` and `kernel/dma/swiotlb.c` at the
pinned base: CMA before SWIOTLB, low 32-bit RAM, full 384/64 MiB sizes,
4 MiB CMA alignment and 4 KiB SWIOTLB alignment.

| Case | CMA, end exclusive | SWIOTLB, end exclusive |
| --- | --- | --- |
| M1 control reproduced | `0xc8000000`–`0xe0000000` | `0xf4800000`–`0xf8800000` |
| M2 with observed ABL insertions | `0x98000000`–`0xb0000000` | `0xf2200000`–`0xf6200000` |

Both modeled M2 pools retain their full sizes below 4 GiB, with no
intersection with a proposed exclusion or captured boot allocation. All
22 stock static regions are covered. The built tree has 25 static entries;
adding only the observed `sec_pt` and `sec_dram` insertions projects 27
distinct live entries and no duplicate debug page. No CMA base is pinned
in the DT or command line; the allocator remains free to choose safely.

A deliberate negative case reserves a page at `0xa0000000` before pool
allocation. The model then cannot fit the full CMA pool: it reports
failure rather than overlapping the page. This demonstrates why new
bootloader placement cannot be assumed away. Live CMA failure, shrinkage
or an unexplained pool relocation must stop the test before driver work.
The harness does not emulate ABL, page-table construction or every early
allocation; the next live map is required evidence.

Reproduce offline with
`python3 ~/android/reference/bluejay-memory-candidate-20261106/check-layout.py`.
The receipt pins source/DTB/input hashes. `preflight.py` checks the packed
images and initramfs. Private evidence remains in that directory.

### Build and packed images

`W=1 exynos/google/gs101-bluejay.dtb` completed without diagnostics.
Strict checkpatch reports zero errors, warnings or checks. Google board
schema and installed reserved-memory schema validation report no diagnostics;
this is not a full subsystem binding validation. The 24 storage-guard and
37 image-layout tests pass.

The kernel C binary, modules within the initramfs, and compressed initramfs
are reused byte-for-byte from M1. No new C/module build is claimed. The
native kernel release therefore remains
`7.3.0-rc6-omamobile-push1-g29a7a9326bf0`; identify M2 by its DTB and
image hashes, not by `uname` alone. Packed B0 matches the built DTB's full
property tree; A0 differs only in its SoC ID.

| Image | Bytes | SHA-256 | Change from M1 |
| --- | --- | --- | --- |
| `boot.img` | 67108864 | `38f185103449a2ff2a6204c064a8451de6c32e195df58cf337d40a4a2fd2636e` | identical |
| `vendor_boot.img` | 6819840 | `7dc6afd4d01b149121c3ca75406d4d5a5bc6b2d81ab9cb5e163d4946adde7930` | memory DTBs only |
| `dtbo.img` | 4096 | `72d5e0020cbdbfd6de6e2581f11c459e0b0aca0ded2acb616ae87ad49dc2144d` | identical |

All fit the previously captured partition sizes. Boot's AVB footer and
rollback index remain unchanged. The packed init, four-name storage
allowlist and absence of MMIO/display/USB-switch hooks were checked again.
Images, source patch hash and validation receipt are pinned in
`out-bluejay-memory-20261106/preflight-validation.json`.

### Attended test runbook — executed once with owner approval, results below

1. **Identify the current environment, read-only; low risk.** On this
   session's reconnect, host USB identifies Google's Pixel 6a interface,
   serial-pinned ADB reports a bluejay transport, and shell requests return
   `error: closed`. There is no native USB network. This does not establish
   an Android boot, current slot or the reason for leaving Linux by itself.
   The owner subsequently confirms Android setup/lock screen: stock has
   booted and the original calibration backup is stale. Current slot and
   the shutdown/reboot history remain unverified. Stop on an
   unexpected identity, recovery error or ambiguity. Rollback: no action
   for reads. Do not spend another boot to clarify a screen.
2. **Fastboot preflight, read-only; low risk.** Once the owner approves
   entering fastboot, pin the saved private serial. Read `product`,
   `version-bootloader`, `current-slot`, slot A/B successful/unbootable
   flags and retry counts if supported, plus the three B partition sizes.
   Require bluejay, the previously captured bootloader, stock A still
   bootable/successful, and sizes matching the receipt. Stop on any
   mismatch; unsupported retry queries are unknown, not zero. This step
   does not activate a slot. Rollback: leave fastboot untouched.
3. **Approve the exact M2 set and one B boot; medium/high risk.** Re-run
   local preflight and compare all three hashes. The proposed command is
   `DEVICE=bluejay KERNEL_DIR=~/android/mainline/wt-bluejay-memory-20261106 KERNEL_OUT=~/android/mainline/out-bluejay-memory-20261106 bin/omamobile flash`,
   from the mobile worktree, with `FASTBOOT_SERIAL` set privately from the
   saved selection. The helper writes the three suffixed B images,
   activates B and boots it. Ask before running it. No userdata, devinfo,
   slot-success marker, firmware or protected-partition write is included.
   Expect USB/SSH within a minute; logo refresh is still not enabled.
   Stop if USB is absent after three minutes or a reset loop occurs; do
   not repeat automatically. Rollback: owner-assisted fastboot, then a
   separately approved baseline-image restore or stock-A boot. A previous
   approval from the first-light session is not this approval.
4. **Capture the new boot before further work; read-only, low risk.**
   Save compatible, release, boot ID, uptime, live FDT, iomem, dmesg,
   module/binding state and storage guard into a new private directory.
   Read back image prefixes and compare their hashes. Require unchanged
   no-driver/no-Android-mount state, protected partitions read-only and
   `/dev/sda` absent. Require all 22 stock static extents covered; 27
   distinct expected entries, ECT bounds and named ABL prefix/tail intact;
   no reserved-memory overlap; and full-size CMA/SWIOTLB disjoint from
   every exclusion and boot allocation. Investigate a new address rather
   than accepting the model blindly. Stop on any failed gate. Rollback
   requires the owner-approved recovery action from step 3.
5. **Refresh private backups if stock may have booted; read-only, low
   risk.** Keep the original backups. Obtain a fresh verified set through
   the guarded native environment before any radio, PMIC, AoC or Trusty
   work. Record stock-boot uncertainty if it cannot be resolved; do not
   treat old checksums as a current baseline. Stop on guard, size or
   checksum failures; never relax read-only flags. Rollback: retain both
   evidence sets without writing a partition.

   The public bluejay descriptor currently lacks `NV_PARTS`. A private
   backup kit stages the unchanged project `nv-backup` / `phone-ssh` tools
   and a descriptor listing the ten partitions verified in M1: six NV
   regions plus stock A's three boot images and devinfo. Run the kit from
   `~/android/reference/bluejay-memory-candidate-20261106/backup-kit/tools/nv-backup -d bluejay <new-private-directory>`
   only after guarded native SSH returns, followed by its `--check` mode.
   It refuses missing, writable or mounted partitions. The staged list
   does not change any boot image or the public device descriptor.

Wi-Fi, display refresh, charging control and rootfs installation remain
separate tests. M2 is one bundled memory policy: a regression would require
an offline reduction before a later approved test, not attribution to one
reservation without evidence.

### M2 live result, 2026-11-06

The owner approved the checks, exact image set and one B boot, live capture
and fresh read-only backups. Serial-pinned ADB rejected reboot with
`error: closed`; the owner entered Fastboot Mode with the buttons.
Fastboot reported the unchanged expected bootloader, A active/successful/
bootable, B unsuccessful/not-unbootable with zero retries, and the expected
three partition sizes. No slot-success marker was written. The project
helper wrote the approved three B images, each OKAY, then activated/booted
B; helper exit 0, SSH first answered at uptime 2.57 seconds.

The new live FDT has exactly the projected 27 distinct static reservations.
All 22 stock static extents are covered, ECT's actual `0x34000` bytes fit
inside its exclusion, the named ABL prefix and independent tail remain,
and the debug-info page appears once. There is no reserved-memory overlap.
The full 384 MiB CMA pool is at `[0x98000000, 0xb0000000)` and full 64 MiB
SWIOTLB at `[0xf2200000, 0xf6200000)`, exactly matching the checked model,
disjoint from the exclusions and captured boot allocations. No allocator
base was forced at boot.

All three flashed image prefixes match their local hashes. The protected
partitions remain read-only, `/dev/sda` is absent, no Android partition is
mounted and no module is loaded. A fresh health read at uptime 303.58 seconds
identifies the same boot, with no panic, oops, UFS error-handler, I/O-error
or reserved-memory-overlap signature. These observations pass the narrow
memory-layout test, not subsystem or indefinite stability qualification.

The first full-backup attempt encountered SSH connection timeouts. The log
shows recovery between them and all six NV copies verified before the
host stopped the remaining stock-image copies. USB did not disconnect in
the host log, and fresh SSH answered in the same native boot. The partial
copies and logs are retained. A second full attempt uses the same project
backup code with 2 MiB rather than 8 MiB host chunks; only its eventual
backup and independent check receipts can establish a completed fresh set.
Do not equate a retried connection with a kernel hang or attribute the
timeouts to M2 without a matched comparison.

Private run/evidence: `~/android/reference/bluejay-m2-20261106T143907Z`,
including `authority.json`, `fastboot-gates.json`, flash log, readbacks,
live memory/guard validation, same-boot health and backup receipts.
This is the executed result for M2; older proposed/unapproved status text
in build receipts records their creation time rather than revoking approval.

Final result: all ten partitions in the second full backup were copied,
size-checked and checksum-verified, and the independent `--check` reports
all ten SAME (both commands exit 0). The final native health read is the
same boot at uptime **1100.72 seconds**, with the guard intact, no modules
or Android mounts, and no panic/oops/UFS-handler/I/O-error/overlap signatures.
The copy recovered from 17 SSH connection timeouts; the independent check
had none. Smaller chunks therefore did not eliminate the observation.
The host recorded no USB reset/disconnect after native enumeration.

The fresh verified backup is private at
`~/android/reference/bluejay-backup-post-stock-m2-small-20261106T144843Z`.
Old verified and interrupted copies are preserved; the interrupted directory
is explicitly marked INCOMPLETE. Four NV partitions differ from the pre-stock
set (`efs`, `efs_backup`, `modem_userdata`, `persist`), confirming that the
older set is not the current baseline. Nothing was restored or written to
those partitions. Keep this fresh set until another stock Android boot.

The live-memory gate is complete for this image/boot. USB/SSH reliability
under bulk reads remains open before any driver bring-up. No second reboot,
slot-success mark, Wi-Fi load or other subsystem action followed.

Later U1 read-only diagnostics reproduced a stall with `/dev/zero`, before
any partition read. Initial state was the same healthy M2 boot; after the
stall one bounded fresh SSH connection timed out and phone commands stopped.
Current execution state is unknown. See [USB-SSH-PLAN](USB-FIX-T6.md).
This does not reopen or invalidate the completed memory-layout result;
causal attribution remains unassigned without a matched control. Historical
backup logs count 47 failed chunk attempts alongside 17 timeout messages.
Subsequent U2/U3 checks establish the same M2 boot is alive: a network
stall was reproduced while all 30 serial status samples continued, without
new kernel errors. TX completion accounting paused while RX/IRQ progressed.
The exact network/bulk-path cause remains open; no M2 attribution follows.

## Offline gate

For each candidate, trace Google's GPL board/SoC sources and its actual
consumer: who reads or writes it, whether that agent can run without the
Linux driver, and whether ABL changes its location or size. Compare the
published gs101 tree and raven's notes, keeping board-specific differences.
Quote citable source facts only; vendor blobs and reconstructed DTBs remain
private. Keep the native twelve-region audit separate from this stock
reference comparison.

Pass: every range has a sourced disposition, or a conservative board-only
reservation with its effect on existing pools checked. Stop: an unknown
firmware writer, an unaccounted runtime relocation, an overlap with a
live allocation, or an unsafe pool change. Leave hardware bring-up paused.
No phone mutation is needed for this gate; rollback is discarding only the
new local source change. Risk: low for offline analysis.

If a new kernel/DTB is needed, build it in a separate output, run the
relevant validation and prepare an exact gated test and stock-A rollback.
Ask the owner before its flash/reboot. A request for stock live capture,
raw register access or a new driver load is a separate staged operation;
do not infer permission from the completed first-boot test. Keep private
calibration backups fresh after any later stock boot.
