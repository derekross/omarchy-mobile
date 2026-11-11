<!-- SPDX-License-Identifier: MIT -->
# Pixel 6a: NCM flush retry fix

Status (2026-11-06): flashed and live gates passed; matched fixed-image trace
passes all 16 transfers and confirms retry at a full request pool. Broader
read-only transfer and backup qualification also passed under standing
project authority. Wi-Fi/display/input and desktop installation remain pending.

## Evidence and change

T5's corrected generic USB trace has no loss, all 35 serial samples and a
working ACM positive control. All 361 NCM requests complete successfully.
At the final flush timer expiry the ten-request pool is full; the first
request returns four microseconds later, all ten within 3.182 ms. These
events occur in the same CPU/task, with no reconstruction anomalies.
Normal network submissions continue returning success, but no new flush
timer or NCM USB request follows. The buffered tail is stranded.

The pinned `ncm_tx_timeout()` invokes `ndo_start_xmit(NULL, netdev)` and
ignores `NETDEV_TX_BUSY`, returning `HRTIMER_NORESTART`. The gether path
returns BUSY when no request is free; its ordinary queue wakeup cannot
resubmit NCM's internal aggregation buffer. This matches the observed
loss of progress, while serial and USB completions remain responsive.

T6 changes only the callback's BUSY handling: forward by the existing
300 microsecond interval and return `HRTIMER_RESTART`. Success and null
netdev still stop. Each invocation returns promptly; this is not a
synchronous polling loop. Existing unbind cancellation remains intact.
Matched fixed-image validation below now exercises this retry path.

The DWC3 request-name metadata defect is separate. T5 uses existing generic
gadget events that copy their names; no trace-header patch is bundled here.
The earlier spontaneous USB disconnects also remain separate observations,
not automatically explained by this network aggregation bug.

## Exact candidate

Base `29a7a9326bf064c7079396090c262271196b4a7b`, branch
`omamobile-bluejay-usbfix-20261106`, worktree
`~/android/mainline/wt-bluejay-usbfix-20261106`, output
`~/android/mainline/out-bluejay-usbfix-20261106`.
Release `7.3.0-rc6-omamobile-usbfix1`.

The config differs from T4 only in its release suffix. Exact T4 initramfs,
DTB, DTBO and guard retained, including no deliberate no-USB panic/fallback.
No new driver, memory policy, GPIO, firmware or Wi-Fi change.

| Image | Bytes | SHA-256 |
| --- | ---: | --- |
| boot.img | 67108864 | `798d6276b8afb82333b617adc29726b520f632512e73a44f45300d7de00a3b2c` |
| vendor_boot.img | 6819840 | `44caeba83b30f2a5d619d0a32928468bc85e0a30a0e1f716fb837fa345afbb0d` |
| dtbo.img | 4096 | `72d5e0020cbdbfd6de6e2581f11c459e0b0aca0ded2acb616ae87ad49dc2144d` |

Actual callback-body host tests pass success, repeated BUSY then success,
and null-netdev handling. The pinned control callback stops on BUSY; the
fixed callback schedules one existing-interval retry per BUSY result.
This is a function-level test with stubs, not full USB integration.

Strict checkpatch clean. W=1 Image.gz/bluejay DTB builds without errors,
1,143 warning lines retained, not warning-free. Image/AVB/payload preflight
passes. Guard/layout results are inherited from exact T4 init/helper inputs;
limited DT schemas only, because DTB bytes match. No full-schema claim.

## Staged validation

Private exact runbook, source patch, tests, hashes and scripts:
`~/android/reference/bluejay-usbfix-candidate-20261106/`.

Fresh read-only T4 prestate, then owner-assisted fastboot entry and
serial-pinned identity/bootloader/A-recovery/slot/size gates. One invocation
of the project helper writes only the three B images and boots once. Keep
the preserved M2/T4 sets; no slot-success or protected write. The temporary
host access rule should grant the recreated ACM node automatically; verify it.

After boot, bounded ACM image-prefix hashes, guard and memory validation
must pass before tracing. Require 27 reservations/all 22 stock extents,
full CMA/SWIOTLB pools, no overlap/fatal logs, no modules or Android mounts,
and `/dev/sda` absent. Stop on any mismatch; do not force allocator addresses.

Then run the matched T5 trace profile on the fixed image: max 16 × 2 MiB
zero chunks, 20 s transfer stage, 35 serial samples, bounded ring and host
capture, first failure stops traffic. Require zero loss and positive ACM
control; inspect full-pool timer expiry followed by retry/queue progress.

If that passes, qualify without active tracing: fresh 128 MiB zero stream
and 64 × 2 MiB shared chunks with an independent serial observer, followed
by guarded UFS bulk reads into a new private backup and independent check.
Require zero failures/retries, exact sizes/hashes, final guard/health and
host USB continuity. A first-failure host gate prevents tool retries from
masking errors. All original backups and incomplete evidence stay preserved.

Risk: new-kernel boot medium/high; bounded existing-path traffic afterward.
No new driver, radio, raw register access or rootfs install. B stays unmarked
by us; no watchdog or intentional fallback loop. Stop on failed gates, serial
loss, reset loop or new kernel/storage error. No blind repeat. Recovery uses
owner-assisted fastboot and the exact preserved T4 set with fresh gates,
recorded separately under standing authority. Avoid stock A unless needed;
a stock boot requires fresh calibration backups before subsystem work.

Preserve the Pixel 7a comparison. A common USB transport fix is not evidence
about its Qualcomm firmware/BHI failure or bluejay's untested Broadcom path.

## Hardware results

One serial-pinned project-helper flash wrote the three B images and booted
`7.3.0-rc6-omamobile-usbfix1`. Read-only ACM capture matches all three image
prefixes, all 49 guard flags and M2 memory geometry: 27 distinct regions, all
22 stock extents covered, full disjoint CMA/SWIOTLB pools. No modules or
Android mounts, no fatal kernel signatures. Slot B remains unmarked by us.

Matched capture: all 16 × 2 MiB transfers have exact sizes/hashes; all 35
serial samples, zero ring loss, ACM positive control. All 2,749 NCM queues
return full length successfully; no reconstruction anomalies or unmatched
requests. The ten-request pool is full at 216 timer entries; 215 have an
immediate core ABS rearm, including six that expire again before another
timer start. The core enqueues HRTIMER_RESTART as ABS; ordinary NCM starts
use REL|SOFT. This directly observes the repaired callback path and continued
queue progress under the condition that stranded the control. Two ordinary
network BUSY results are handled without transfer failure. One full-pool
entry has no immediate rearm, so the count is not claimed as 216 BUSY results.

Private evidence: `bluejay-t6-20261106T182004Z/causal-validation.json`,
`trace/trace-integrity.json`, chronology and original serial capture.
The first offline analysis incorrectly expected no hrtimer_start event on
core restart; the pinned core emits ABS start on restart. Corrected source
backed analysis is preserved with the original failed attempt; no extra
hardware capture was needed. Historical spontaneous disconnects remain
unqualified by this matched result.

Broader untraced test: one fresh 128 MiB stream plus 64 shared 2 MiB
chunks, 256 MiB total, all exact sizes/hashes and no failed requests. All
60 serial samples, unchanged 49 guard flags, no modules/Android mounts or
fatal signatures. Fresh ten-partition UFS backup with the original 8 MiB
chunk/shared-SSH profile copies 629 MiB without retry or timeout; separate
fresh-session independent check reports all ten SAME. Local hashes also
pass, and all ten match the preserved M2 backup, including stock A images.
The first-failure gate never latched. Original backups remain untouched.

Final same-boot ACM recheck at 445.87 s repeats all three image-prefix
hashes, storage guard and full memory gates successfully. Host kernel
journal has no entries after the initial boot enumeration through the
qualification window. No extra reboot, slot-success mark, driver load or
Wi-Fi operation. This qualifies the observed workbench transfer profiles;
it does not establish indefinite stability or explain earlier spontaneous
disconnects. Next gate is the pinned gs101 Wi-Fi source/board/firmware port
review before any PCIe or WLAN driver probe.
