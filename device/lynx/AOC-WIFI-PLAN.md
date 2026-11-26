<!-- SPDX-License-Identifier: MIT -->
# Pixel 7a: AoC before WLAN power

Status (2026-11-15): **guarded association and traffic passed on two boots of
the old local experimental kernel**. This records our reproduction of alfikpl's AoC-first
ordering and four mainline fixes reported in [issue 36](https://github.com/derekross/omamobile/issues/36#issuecomment-6819528828)
and the subsequent tests on the original lynx test phone. The kernel changes
and test overlays for those historical runs are not included here. The revised signed integration later
booted with AoC and WLAN held off (section 3).
No release package or automatic driver startup is qualified by these results.

The historical source and its distinction from the revised series are recorded
in section 1. Private build configuration and overlay receipts are retained
separately; no firmware or device capture is published.

## 1. Build and ordering

The two successful MSI-candidate connection tests ran on
`7.3.0-rc6-omamobile-lynx-msi-20261113+`. The exact historical kernel source is
[archival commit `3fd82de7aefe7eed42453271ef60ef6d29e4bbf0`](https://github.com/latentoperator/linux-omarchy-mobile/commit/3fd82de7aefe7eed42453271ef60ef6d29e4bbf0),
based on `2db2bc35beecbf2deccb7f2e9bc8c3843b1edc9c`. It preserves the complete
previously uncommitted tested tree, including Trusty, AoC, power-sequencing,
PCIe and board changes. This archival test branch is not proposed for merge
and is separate from the revised signed topic series. The base commit alone
does not reproduce the tested source. The earlier firmware/scan build was
`7.3.0-rc6-omamobile-lynx-wifi-aoc-20261113+` on the same base with local
changes, before the MSI edge-rearm candidate.

The sequence was Trusty IPC, GSA/AoC, WLAN power, PCIe link, then ath11k.
The local changes include:

- Trusty IPC descriptors using premapped shared-memory buffer IDs;
- preserving GSA probe deferral in AoC and mapping the chip-ID range without
  requesting exclusive ownership (alfikpl reported an exynos-chipid conflict
  on their build; this phone’s archived DT identifies no second owner);
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
were used to obtain the result. In both MSI runs the WCN6855 endpoint had
no restricted DMA pool, and the PCIe controller had no active IOMMU mapping
(the HSI2 SysMMU was disabled in the tested DT).

The recorded lab stages did not start `storageproxyd` or any fingerprint or
modem service. Their preflights required those services inactive and rejected
a running storage proxy; the saved process checks found none. Trusty was used
for GSA/AoC startup. This describes the lab-stage scope, not an RPMB
write-counter measurement or a continuous whole-boot execution audit.

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
partition hashes matching the post-stock baseline. After fresh identity and
health checks, the successful stage explicitly disabled the S3C2410 hardware
watchdog it had opened as `/dev/watchdog0` with a 20-second timeout
(`WDIOS_DISABLECARD`), confirmed its disabled receipt and closed the descriptor.
Final checks found no watchdog descriptor owner and no active stage feeder
service or network rollback timer. This refers to that lab watchdog, not every
watchdog in the SoC. The successful connection stage did not reboot,
reload firmware or modules, mark slot B, or write a protected partition.
Optional smoke rows still reported a failed CMA reservation and no GPU
render node; this Wi-Fi result does not qualify those paths.

4. **A later post-reboot restoration passed on the same old release.** Private
   receipts saved on November 14 record a fresh guarded Trusty/AoC/link/firmware
   sequence after the owner's reboot. AoC again reported 82 services and zero
   restarts, and passive scan returned 21 BSS entries. The first activation
   associated but its immediate IPv4 check raced DHCP completion and stopped;
   Wi-Fi isolation rollback and watchdog disarm succeeded. The stage summary's
   false association-request flag is stale: its primary per-boot marker and
   kernel capture show that association was requested.

   A revised activation on that same boot added an eight-second
   bound for IPv4 address, DHCP options and gateway readiness. It passed DHCP,
   three gateway pings, Wi-Fi-bound HTTPS (HTTP 200, 577 bytes, TLS verified),
   and fresh USB SSH. Ordinary HTTPS also used Wi-Fi and passed. The revised
   activation did not reload modules or firmware or reboot. All six protected
   hashes and required smoke checks passed, with no new WMI/TX or kernel error;
   watchdogs and deadman timers were inactive at task close. Startup remained
   manual after reboot; device autoconnect within that boot was enabled.

These are **successful connection tests on two boots** with the MSI edge-rearm
candidate, including a preserved DHCP-readiness failure on the later boot.
They do not establish why the earlier WMI/TX connection stalled or demonstrate
that the MSI change fixes it. The original failure and successful retests all
remain part of the result. This is not a counted cold-start, reconnect or
endurance qualification series.

## 3. Current state and remaining gates

The experimental drivers remain blacklisted for boot. Startup is a guarded
manual lab sequence. The owner subsequently rebooted the same kernel; home
and touch were confirmed working, and the later restoration in section 2
repeated guarded Wi-Fi startup on that boot. These are historical receipts,
not proof of present connectivity. On November 15 the signed integration at
`dfdf8ce251c89d3cd05a6325c61ed7ea1c61a741` booted from B as
`7.3.0-rc6-omamobile-lynx-qual-dfdf8ce251c8+`. The first host check stopped
at an obsolete pinctrl debugfs path. A separate read-only check confirmed
the build and module set, with AoC and WLAN held off. Association and HTTPS
have only been demonstrated on the old experimental kernel.

The board change still needs a restricted DMA pool that ath11k can use.
On this kernel MHI requests a contiguous 512 KiB firmware segment and the
restricted pool permits at most 256 KiB per allocation. Increasing the
total pool size would leave that limit in place.
[ath11k MHI configuration](https://github.com/latentoperator/linux-omarchy-mobile/blob/dfdf8ce251c89d3cd05a6325c61ed7ea1c61a741/drivers/net/wireless/ath/ath11k/mhi.c#L381-L384)
and [SWIOTLB segment and slot sizes](https://github.com/latentoperator/linux-omarchy-mobile/blob/dfdf8ce251c89d3cd05a6325c61ed7ea1c61a741/include/linux/swiotlb.h#L20-L32).

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

As of 2026-11-15 the human-certified topics were open as drafts from
[linux-omamobile#251](https://github.com/derekross/linux-omamobile/pull/251) through
[linux-omamobile#255](https://github.com/derekross/linux-omamobile/pull/255).
That integration had a complete offline kernel/module
build and matched AoC-only/AoC+WLAN images, with image, AVB, module and overlay
verification. Testing AoC and Wi-Fi on that build still requires a revised
attended runner and owner approval. Shared Trusty/AoC paths still require a maintainer-approved
Pixel 7 Pro regression before merge. This does not establish that those paths
are unchanged or ready to merge. Private logs, network identifiers,
partition images and calibration hashes remain off-repository.
