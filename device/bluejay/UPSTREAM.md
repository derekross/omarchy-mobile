<!-- SPDX-License-Identifier: MIT -->
# Bluejay development source and review status

Status (2026-11-11): documentation split from [#543](https://github.com/derekross/omarchy-mobile/pull/543), now closed unmerged in favour of the split PRs below.
The historical source below demonstrates one working development handset; it
is not a release installer. This status page changes no boot or hardware
policy. Source-only instructions are not authority to run a phone operation.

## Kernel topics in review

| Topic | PR | Remaining work |
| --- | --- | --- |
| NCM aggregation retry | [#225](https://github.com/derekross/linux-omarchy-mobile/pull/225) | Driver/selftest commits split; attended SSH profile in [mobile #666](https://github.com/derekross/omarchy-mobile/pull/666); reference phone and laptop-sleep qualification remain |
| Retained-memory exclusions | [#226](https://github.com/derekross/linux-omarchy-mobile/pull/226) | Provenance and node naming addressed; passing CI, awaiting maintainer merge |
| GS101 PCIe/PHY | [#227](https://github.com/derekross/linux-omarchy-mobile/pull/227) | Power control, match data and single-try/failure-history-read rationale revised; qualify a fresh 6a boot |
| BCM4389 bring-up | [#228](https://github.com/derekross/linux-omarchy-mobile/pull/228) | Probe-time DMA-limit cache and oversized-TX completion/counter revised; chip-only diagnostics excluded; matched-stack phone trial remains |
| ALIX touch | [#229](https://github.com/derekross/linux-omarchy-mobile/pull/229) | Staging knobs removed and shared reset-order header checked; qualify a fresh 6a boot |
| Disabled Wi-Fi DT | [#230](https://github.com/derekross/linux-omarchy-mobile/pull/230) | Revised dependency stack refreshed; merge after #227 and #228, then rebase to its own two commits |
| Trusty trace API | [#231](https://github.com/derekross/linux-omarchy-mobile/pull/231) | Merged 2026-11-09; no Trusty runtime claimed |

The attended USB SSH transfer profile is `tools/ncm-transfer --peer root@<usb-ip> --interface <host-usb-interface>`. It performs sixteen SHA-256-verified 2 MiB zero transfers with a shared 20-second deadline and no retry. Run it only after the device identity and storage checks pass; USB tracing is separately required to establish that aggregation retry was exercised. It does not test laptop sleep or USB replug.

The November 11 replacements for #225, #227, #228, #229 and #230 are based on
`fc7086a68fcaaed8960d09f1bdf6c51c9926c759` and were certified by the human
under DCO after source review. Signing preserves the reviewed source trees
and exact diffs. The common integration passes W=1 builds of seven touched C
files, ten Google device trees without new dtbs_check warnings, four binding
checks, policy and strict checkpatch without errors. New-file coverage
warnings and one continuation-alignment check remain disclosed in the PRs.
A complete Image, Bluejay DTB and 1,828 modules also build for
`7.3.0-rc6-omamobile-bluejay-review-20261111`; the full build has two format
warnings in unchanged AoC ALSA code. Matching dependency indexes and module
resolution pass. The revised build has not been installed or booted on the
phone. The PR checks show fresh published-head CI separately from these local
results and the earlier heads' passing CI.

This is build/policy evidence, not runtime qualification of the rebased stack.
The tested source is the
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
agreement with #346's author or passive-package phone migration is claimed here.
A focused [passive policy follow-up](https://github.com/latentoperator/omarchy-mobile/commit/ffb2c8c82f8d6c53e1beaa10f420537ca7890ee2)
is coordinated on that PR and requires #563 first. Its package fixtures and
aarch64 build pass; replacing the old active development package still needs
an explicit migration of the startup files it owns.

The tested overlays, startup files, Aquamarine patch and probe tools remain
inspectable at [the immutable #543 source](https://github.com/latentoperator/omarchy-mobile/tree/6ad4651f8ac151333345c72db99f1fd83259696f).
The subsystem plans describe them historically; their relative file paths do
not imply that these status notes install those files. The original
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
