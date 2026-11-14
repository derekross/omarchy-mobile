<!-- SPDX-License-Identifier: MIT -->
# Pixel 7a: AoC before WLAN power

Status (2026-11-13): **one guarded association and traffic test passed on a
local experimental kernel**. This records a reproduction of the AoC-first
lead from [issue 36](https://github.com/derekross/omarchy-mobile/issues/36#issuecomment-6819528828)
and the subsequent tests on the original lynx test phone. The kernel changes
and test overlays are not published or included here. No release package or
automatic driver startup is qualified by this result.

Recorded local build: detached kernel worktree
`~/android/mainline/wt-lynx-wifi-aoc-20261113`, with the base and local
changes described below; output `~/android/mainline/out-lynx-msi-20261113`.

## 1. Build and ordering

The successful connection ran on
`7.3.0-rc6-omamobile-lynx-msi-20261113+`, built from the published kernel
`omamobile` at `2db2bc35beecbf2deccb7f2e9bc8c3843b1edc9c` plus local
Trusty, AoC, power-sequencing, PCIe and board changes. That base commit alone
does not reproduce this build. The earlier firmware/scan build was
`7.3.0-rc6-omamobile-lynx-wifi-aoc-20261113+` on the same base with local
changes, before the MSI edge-rearm candidate.

The sequence was Trusty IPC, GSA/AoC, WLAN power, PCIe link, then ath11k.
The local changes include:

- Trusty IPC descriptors using premapped shared-memory buffer IDs;
- preserving GSA probe deferral in AoC and avoiding a second claim of the
  chip-id resource already owned by exynos-chipid;
- an AoC-online dependency checked before WLAN power and PCIe bring-up;
- lynx-specific WCN6855 power sequencing and DWC iMSI-RX handling,
  including restoring ELBI interrupt enables after link reset;
- in the final candidate, rearming the MSI edge after dispatch by masking
  and restoring the DWC masks under the IRQ-chip lock.

AoC firmware came unchanged from the owner's factory image and reported
`14022723-polygon`, with 82 services. The Wi-Fi test used the owner's stock
firmware set: `amss20.bin`, `m3.bin`, `regdb.bin` and a `board-2.bin` packed
from the stock board files for this endpoint. Neither firmware nor board
data is redistributed. Bluetooth and the modem were not started for these
tests. No extra chip-window, PMU, SysMMU or iATU userspace register reads
were used to obtain the result.

## 2. Results, in order

1. **Firmware and scan passed.** With AoC online before WLAN power, Trusty
   IPC, AoC (82 services, zero restarts), PCIe/MSI, ath11k firmware boot and
   a passive scan passed. The earlier build returned 23 BSS entries on
   2.4/5 GHz. This reproduces the reported ordering result as a combined
   local stack; it does not isolate each change's necessity.
2. **Connection attempts stopped.** The first attempt raced NetworkManager
   supplicant readiness. After correcting that readiness check, a connection
   attempt stalled the ath11k WMI/TX queues and USB stopped responding. The
   bounded guard expired and the phone recovered to a new boot with the
   experimental drivers unloaded. The protected-partition checks and
   required smoke checks passed after recovery.
3. **One MSI-candidate connection passed.** On the final release named in
   section 1, fresh stages passed Trusty IPC, AoC (82 services, zero
   restarts), PCIe/MSI enumeration, one firmware boot and a passive scan
   with 24 BSS entries. One activation, after NetworkManager was ready,
   associated with a saved profile and obtained DHCPv4. Three gateway pings
   passed. HTTPS explicitly bound to Wi-Fi returned HTTP 200 and 577 bytes,
   with TLS verification enabled and its source address matching the
   Wi-Fi lease. Fresh SSH confirmed that USB access still worked. No new
   WMI timeout, TX flush timeout, oops or panic appeared in the connection
   capture.

The final read-only checks found no failed units, all six required
`phone-smoke` checks passing, the storage guard intact and all six protected
partition hashes matching the post-stock baseline. The watchdogs were
explicitly disabled after fresh healthy status; no stage guard or rollback
timer remained active. The successful connection stage did not reboot,
reload firmware or modules, mark slot B, or write a protected partition.
Optional smoke rows still reported a failed CMA reservation and no GPU
render node; this Wi-Fi result does not qualify those paths.

This is **one successful runtime test** with the MSI edge-rearm change.
It does not establish why the earlier connection stalled or demonstrate
that the MSI change fixes it. The original failure and the successful
retest both remain part of the result.

## 3. Current state and remaining gates

The experimental drivers remain blacklisted for boot. Startup is a guarded
manual lab sequence. The owner subsequently rebooted the same kernel;
home and touch were confirmed working, and Wi-Fi startup has not yet been
repeated on that boot. The connection result above belongs to the earlier
qualified boot, not the phone's present network state.

Reconnect, repeated cold-start operation, sustained traffic, suspend/resume,
Bluetooth coexistence and unattended startup remain unqualified. AoC
firmware being online does not qualify audio or sensors. Battery, charging,
camera and torch are separate work and are not advanced by this report.

Before another hardware run, prepare fresh per-boot stage markers and a
reviewed runbook with expected results, stop conditions and recovery. Keep
the existing identity checks, protected-partition baseline, storage guard,
laptop kernel-log capture, bounded hardware watchdog and network rollback.
Do not replay consumed helpers, retry firmware after a stall, unload AoC,
or repeat the prohibited register reads in [WIFI-PLAN section 6](WIFI-PLAN.md#6-stop-conditions).
On USB loss, stop sending commands and observe recovery before a fresh
identity-pinned probe. Any boot-image write or reboot needs the owner's
approval for that operation.

The next upstream code work is to separate the local kernel changes into
reviewable subsystem series, with explicit treatment of shared Trusty/AoC
paths and the Pixel 7 Pro. This documentation does not establish that those
paths are unchanged or ready to merge. Private logs, network identifiers,
partition images and calibration hashes remain off-repository.
