<!-- SPDX-License-Identifier: MIT -->
# Bluejay development source and review status

Status (2026-11-10): documentation split from [#543](https://github.com/derekross/omarchy-mobile/pull/543), now closed unmerged in favour of the split PRs below.
The historical source below demonstrates one working development handset; it
is not a release installer. No code or device descriptor is changed by this
PR. Source-only instructions are not authority to run a phone operation.

## Kernel topics in review

| Topic | PR | Remaining work |
| --- | --- | --- |
| NCM aggregation retry | [#225](https://github.com/derekross/linux-omarchy-mobile/pull/225) | Suspend handling revised; separate selftests and validate on the reference phone, including laptop sleep |
| Retained-memory exclusions | [#226](https://github.com/derekross/linux-omarchy-mobile/pull/226) | Provenance and node naming addressed; passing CI, awaiting maintainer merge |
| GS101 PCIe/PHY | [#227](https://github.com/derekross/linux-omarchy-mobile/pull/227) | Power control and match data revised; explain single link try/history suppression and qualify a fresh 6a boot |
| BCM4389 bring-up | [#228](https://github.com/derekross/linux-omarchy-mobile/pull/228) | Cache DMA-size limit at probe, count size drops and keep chip-only bring-up separate |
| ALIX touch | [#229](https://github.com/derekross/linux-omarchy-mobile/pull/229) | Staging knobs removed; check reset-order header and qualify a fresh 6a boot |
| Disabled Wi-Fi DT | [#230](https://github.com/derekross/linux-omarchy-mobile/pull/230) | Merge after both #227 and #228, then rebase to its own two commits |
| Trusty trace API | [#231](https://github.com/derekross/linux-omarchy-mobile/pull/231) | Merged 2026-11-09; no Trusty runtime claimed |

All seven submitted heads passed CI. That is build/policy evidence, not
runtime qualification of the rebased stack. The tested source is the
contributor's `bringup/bluejay-tested-20261108`, commit `c934e316b`, based on
`29a7a9326bf0`; the tested release is
`7.3.0-rc6-omamobile-bluejay-input-gated0`.

## Separate changes

The initramfs and installer changes affect every device and are submitted
separately as [#562](https://github.com/derekross/omarchy-mobile/pull/562) and
[#563](https://github.com/derekross/omarchy-mobile/pull/563), with existing
descriptors retaining their behavior unless explicitly opted in. Historical
startup is submitted in [#565](https://github.com/derekross/omarchy-mobile/pull/565),
which follows #562 for its matching root-ready marker. The planned
Bluejay package builds on the passive first-light proposal [#346](https://github.com/derekross/omarchy-mobile/pull/346).
Kernel-release pins, module hashes and experimental startup belong in
`device/bluejay/bringup/` until their dependencies merge. No combined package
agreement with #346's author or new phone qualification is claimed here.

The tested overlays, startup files, Aquamarine patch and probe tools remain
inspectable at [the immutable #543 source](https://github.com/latentoperator/omarchy-mobile/tree/6ad4651f8ac151333345c72db99f1fd83259696f).
The subsystem plans describe them historically; their relative file paths do
not imply that this documentation-only PR installs those files. The original
#543 is closed unmerged in favour of documentation [#561](https://github.com/derekross/omarchy-mobile/pull/561),
initramfs #562, installer #563 and bring-up #565.

## Tested desktop dependencies and limits

The development root used matching manually staged modules, the owner's
privately extracted firmware and Aquamarine 0.16.0 patched to support the
retained simpledrm output with a separate Panfrost renderer. The package
database reported device-bluejay 0.1.1, with later files staged directly.
It did not run an installed release package matching #543's 0.1.3 label.
No firmware, device addresses, credentials, captures or binaries are published.

The owner verified unlock, app launch and scrolling. Polling touch, station
Wi-Fi reconnect/TLS and Panfrost rendering at 151 MHz passed on that handset.
Native panel modesetting, Power-key release, full DVFS, Vulkan, Wi-Fi hotspot,
roaming/suspend, audio, modem, Bluetooth, battery monitoring/charging, sensors,
cameras and suspend remain unqualified. Native display, Bluetooth, battery
monitoring and torch are owner priorities, not working-feature claims.

Before any new phone run, follow the subsystem's gated runbook, confirm the
actual device state read-only, and take/validate the required fresh backups.
Further gs101 slot-success writes are on hold; see [NOTES](NOTES.md).
