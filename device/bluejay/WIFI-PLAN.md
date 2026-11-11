<!-- SPDX-License-Identifier: MIT -->
# Bluejay station Wi-Fi

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
