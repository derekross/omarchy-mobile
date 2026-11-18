<!-- SPDX-License-Identifier: MIT -->
# Bluejay station Wi-Fi

## Reviewed integration: November 13 staged run

Status (2026-11-14): the signed integration
[`720a495233734e4328a09c33c095d72a8291e1c4`](https://github.com/latentoperator/linux-omarchy-mobile/commit/720a495233734e4328a09c33c095d72a8291e1c4)
ran the revised pool, PCIe and station paths on November 13. Kernel release:
`7.3.0-rc6-omamobile-bluejay-review-20261111`. These were separate attended
headless boots; the trial prepared each DT by setting its stage's `status`
properties directly. The source overlays below reproduce those exact DT
changes; they are not a claim that these new overlay files were booted.

| Stage | Overlays, applied to the unchanged integration DTB | Enabled path |
| --- | --- | --- |
| w0 pool | `wifi-pool` | 64 MiB restricted pool at `0xc4000000` only |
| w1 link | `wifi-pool`, `wifi-reviewed-controller` | Pool, `regulator-wlan`, PHY and PCIe; endpoint disabled |
| w2 station | `wifi-pool`, `wifi-reviewed-controller`, `wifi-endpoint` | The same path plus the Wi-Fi endpoint |

The reviewed controller overlay includes `regulator-wlan`: the PCI power
control path consumes that supply. The historical `wifi-controller` overlay
does not enable it and belongs to the older kernel described below. The
reviewed DT already has the corrected INTx specifiers, so do not add the
historical `wifi-intx` overlay. USI, SPI and touch stay disabled in these
Wi-Fi stages. Base nodes remain disabled; no descriptor enables these
overlays automatically.

The w0 boot verified the pool. The w1 boot linked on try 1 to `14e4:4441`
with the endpoint unbound and no firmware loaded. The separate w2 boot
verified restricted DMA below 4 GiB, then one managed station obtained DHCP
and completed interface-bound HTTPS (HTTP 200, 16,932 bytes); IRQ counts
increased from 725 to 744 and `tx_oversize_dropped` was zero. This does not
exercise intentional oversized-frame drops. The public runtime reports are
on [PCIe #227](https://github.com/derekross/linux-omarchy-mobile/pull/227) and
[Wi-Fi #228](https://github.com/derekross/linux-omarchy-mobile/pull/228).

Offline verification compiles and applies the overlays to the integration's
base DTB and compares every node/property with both silicon DT variants
extracted from each saved w0/w1/w2 `vendor_boot` image. Only the trial's
`/chosen/bootargs` and silicon `soc_id` differ; all stage status switches,
DMA policy, reservations and interrupt maps match. Images and captures
remain private. No new phone operation or runtime qualification is added.

These overlays describe the hardware stages, not a complete boot/runbook.
The historical startup helpers remain pinned to `c934e316b` and must not be
used with this integration. A future hardware run needs a new attended
runbook with exact kernel/module pins, root and recovery gates, drivers
blocked before boot, host logging, a watchdog and fresh SSH postchecks.
Qualify the pool before the link and the link before firmware; stop on a
pool/DMA mismatch, transport loss or new kernel fault, and recover using
that runbook's known-good image set rather than unloading/rebinding.
Hardware stages carry medium risk; compiling/applying/comparing DTBs
offline has no phone risk. The recorded results do not qualify a release
installer, native panel modesetting, roaming, hotspot, suspend or endurance.
The dependency order remains kernel
[#227](https://github.com/derekross/linux-omarchy-mobile/pull/227) and
[#228](https://github.com/derekross/linux-omarchy-mobile/pull/228) before
[#230](https://github.com/derekross/linux-omarchy-mobile/pull/230)'s two own commits.

## Historical development kernel: November 8

Status (2026-11-08): BCM4389 revision 3 station Wi-Fi initializes and reconnects
automatically in the installed Arch/Omarchy desktop. NetworkManager owns
association, DHCP and DNS. Fresh boots passed wireless-interface-bound HTTPS
with certificate verification. No P2P, hotspot, roaming/endurance or suspend claim.

## Kernel dependencies

The tested source adds the GS101 PCIe1 controller/PHY variant, Bluejay supply
and GPIO wiring, a restricted DMA pool and the brcmfmac board path. The PHY
calibration table comes from Google's GPL `pcie-exynos-gs101-rc-cal.c` at
`204078758737776959ecc85c527a00fd2cabb62f`. GS201-only CMU holes and TCXO paths
must not be touched on GS101.

The enabled pool is 64 MiB at 0xc4000000, below 4 GiB and separate from the
retained firmware/CMA/SWIOTLB reservations. The driver verifies the exact DMA
attachment before bus mastering, bounds packet/index geometry and obtains the
provisioned MAC from ABL's `/chosen/config/wlan_mac1`, without copying it into
source. The current work also retains an identification-only diagnostic gate.

The kernel board source leaves the new path disabled. Apply `wifi-pool`,
`wifi-controller`, `wifi-endpoint` and `wifi-intx` in that order for the qualified
configuration. The last overlay matters: the parent's PCI INTx specifiers are
1 through 4, not 0 through 3. The qualified image proved IRQ delivery before
association; an interface node alone was not treated as success.

## Firmware and startup

Use only the owner's own matching stock files, never another handset's data:
`bcmdhd4389.bin` becomes `brcmfmac4389c1-pcie.bin`,
`bcmdhd.cal` becomes `brcmfmac4389c1-pcie.google,gs101-bluejay.txt`, and
`bcmdhd_clm.blob_ROW` becomes
`brcmfmac4389c1-pcie.google,gs101-bluejay.clm_blob` under `/usr/lib/firmware/brcm`.
Firmware, hashes, network names and credentials are not redistributed.

The device package starts only after USB rescue and the tested hardware path.
It holds the endpoint while the PHY/controller and brcmfmac/WCC modules are
loaded, then binds once. `feature_disable=16` masks BRCMF_FEAT_P2P in the pinned
kernel so NetworkManager does not request the unqualified P2P-device path.
A root-only NetworkManager profile supplies the user's own credentials.
USB stays unmanaged by NetworkManager.

## Gates and recovery

Check reserved memory, disabled DT nodes, exact matching modules/firmware and
USB transport before the first probe. Stream logs, require the watchdog and
qualify pool, controller, link, chip identity, firmware/IRQ and station traffic
in bounded stages. Stop on DMA geometry mismatch, loss of transport, firmware
control failure or new faults. Never unload/rebind to retry or restore NV data.
The installed startup's persisted marker and 45-second deadline leave a failed
radio held on the next boot, with USB available for diagnosis.

The current kernel is `7.3.0-rc6-omamobile-bluejay-input-gated0`; the tested
source is linked from [UPSTREAM.md](UPSTREAM.md). The phone uses dynamic interface
naming; read `/run/omamobile-bluejay-wifi-interface` rather than assuming wlan0.
