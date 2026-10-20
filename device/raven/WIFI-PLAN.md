<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 Pro (raven): Wi-Fi, then Bluetooth

Status (2026-10-14): **Wi-Fi works and comes up at boot** (kernel `7.3.0-rc6-omamobile-push1-g57d2749dcfca`; branch now `omamobile-gs101-wifi`). Bluetooth: [BLUETOOTH-PLAN](BLUETOOTH-PLAN.md).
NetworkManager joins the owner's saved network (a root-only keyfile) and
leaves `usb0` to systemd-networkd, whose route through the laptop is now
the fallback.

## 1. Goal

1. The BCM4389 on PCIe, through `brcmfmac`, connecting with the saved profile.
2. Bluetooth on the same chip (cheetah: the APM UART through `hci_bcm`).

## 2. Facts

`G/` is Google's GPL raviole device tree
(`kernel/google-modules/raviole-device`, branch `android17-6.18-gs101`), `C/`
the cheetah work on `omamobile-int` (`ebe48386d`).

| Fact | Evidence |
| --- | --- |
| Wi-Fi is on `pcie_1` at `0x14520000`; Google's node: elbi `0x14520000`, phy `0x14550000`, sysreg `0x14420000`, dbi `0x14800000`, pcs `0x14540000`, config `0x60FFE000`, ia `0x14500000`, PERST `gph2-0`, memory window `0x60000000` (16 MiB), `ip-ver` `0x984500`, PMU offset `0x3ec4` [V] | `G/gs101-pcie.dtsi:54-98` |
| Cheetah's `pcie_1` (`google,gs201-pcie`) has the same elbi, dbi, config and ia addresses, the same PERST pin and memory window; its PHY (`google,gs201-pcie-phy`) is at `0x14550000` [V]. So gs101's controller is very likely the same block [I] | `C/gs201.dtsi:1011-1075` |
| WLAN_REG_ON is `gpp14-2` (output); host wake `gpa7-0`; device wake `gph2-5` [V] | `G/gs101-common-wlan.dtsi` |
| Our gs101 clock driver has the 18 HSI2 PCIe GEN4 clocks and `cmu_hsi2` [V] | `include/dt-bindings/clock/google,gs101.h`, `gs101.dtsi:1723` |
| Upstream (and our `omamobile` branch) has no gs101 or gs201 PCIe support; cheetah's is `pcie-gs201.c` (1386 lines), `phy-gs201-pcie.c` (635), `pcie-gs201-sysmmu.c` (389) and brcmfmac changes [V] | `git diff omamobile omamobile-int` |

## 3. Design

Port cheetah's PCIe controller, PHY and SysMMU helper to gs101 by adding
`google,gs101-*` compatibles (data differences only where gs101 differs),
and describe `pcie_1`, its PHY and its pins in `gs101.dtsi`/raven. Then
`brcmfmac` with raven's own firmware and NVRAM from the user's factory image
(`tools/extract-vendor-firmware`, a raven map), confined to a restricted DMA
pool as on cheetah.

## 4. Risks (from cheetah, AGENTS.md)

- **PCIe ELBI while the PHY is isolated hangs the SoC**; never read
  controller registers from userspace.
- **The HSI2 SysMMU/S2MPU select by VID, and PCIe (AxID 0x0) and UFS
  (AxID 0x2) share VID 0**: translating VID 0 starved storage on cheetah.
  Keep the restricted DMA pool; never enable VID 0 translation.
- A hang during link-up has no console: kmsg streamed to the laptop and a
  watchdog feeder armed before every load (as for the GPU and touch tests).

## 5. Runbook (to write per step, read-only first)

- **W0** (offline): cherry-pick the three drivers onto a raven Wi-Fi branch,
  add gs101 compatibles, build, `dt-validate`.
- **W1**: boot with `pcie_1` disabled; read-only checks of pin states.
- **W2**: load the PHY and controller by hand (blacklisted at boot), with
  WLAN_REG_ON low: link must stay down, no hang.
- **W3**: WLAN_REG_ON high: link-up, the BCM4389 enumerates (`lspci`).
- **W4**: firmware and NVRAM in place, `brcmfmac` by hand, then
  NetworkManager with `usb0` unmanaged.

## 6. Results

**2026-10-14, `7.3.0-rc6-omamobile-push1-g57d2749dcfca`:**

- **Port (W0):** cheetah's `pcie-gs201`, `phy-gs201-pcie`, `pcie-gs201-sysmmu`
  and brcmfmac changes from `omamobile-int` `ebe48386d`, unchanged, then gs101
  support: a `google,gs101-pcie` compatible (Google: gs101 and gs201 share
  ip-ver 0x984500) and a gs101 PHY variant from Google's
  `pcie-exynos-gs101-rc-cal.c` (no 38.4 MHz input clock block, its own TX
  pre-emphasis and RX tuning, no Auto FBB or DFE, ERIO gate bit 4 only, no
  PLL/bias off delay). gs101's `pcie_1` uses GIC SPI 509 (Google's
  `IRQ_PCIE_GEN4A_1_HSI2`, the same numbering as the UFS node), gs101's
  HSI2 clock names, no cache coherency (Google's raven node).
- **Two fixes on the phone:** gs101's `soc` node translated only the first
  GiB, so the PCIe window (0x60000000) and config space were unreachable:
  widened to 0x80000000 as on gs201. With `trace=1` the controller dumped
  gs201's CMU_HSI2 gate registers and hit a hole of gs101's CMU at 0x20e0
  (synchronous external abort in probe; the following reboot left the phone
  frozen until a forced restart): the dump is gs201-only now.
- **W2/W3:** link up on the first try, Gen 2 x1; the BCM4389
  (`14e4:4441`, class 0x0280) enumerates and gets the restricted DMA pool.
- **W4:** firmware, NVRAM and CLM from the owner's factory image
  (`CP3A.261005.002.A1` vendor.img, ext4): `fw_bcmdhd.bin`, and the `_ROW`
  variants of `bcmdhd.cal` and `bcmdhd_clm.blob` for SKU GLU0G [I: ROW for
  the global model; the NVRAM header says `bcm94389c1…ROW`], installed as
  `brcmfmac4389c1-pcie.google,gs101-raven.{bin,txt,clm_blob}`. brcmfmac
  runs firmware 20.101.91 (c1). NetworkManager (with `usb0` unmanaged, under
  a dead-man timer) joined the saved network: 5 GHz, -68 dBm, 1297 Mbit/s;
  Wi-Fi is the default route (metric 600), the USB link the fallback (1024).
- **At boot:** the three modules load (only `pcie_gs201_sysmmu` stays
  blacklisted), NetworkManager is enabled, and the phone is on Wi-Fi about
  27 s after power-on.
- **To do:** the chip's MAC is random every boot (Google reads the phone's
  own from `persist`); suspend needs brcmfmac's D3 messages (cheetah
  gotcha); Bluetooth.
