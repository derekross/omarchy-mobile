<!-- SPDX-License-Identifier: MIT -->
# Wi-Fi, Bluetooth and battery plan (cheetah / gs201)

Status (2026-10-19): the gauge reports Charging and Full on the cable:
`max17042_get_status` infers the status from the current when the DT names
no supplier (kernel `de0aa4d4e`, in int `cbd727f42`; sent upstream with a
Reviewed-by). Before it, the status read Unknown, upower took the phone for
on battery, and its critical action slept it ([NOTES](NOTES.md),
2026-10-18). Wi-Fi across s2idle: [SUSPEND-PLAN](SUSPEND-PLAN.md) S5.

Earlier status (2026-10-12): **Wi-Fi and the battery gauge work by default.** Wi-Fi:
W1-W3 passed (WPA2 on 5 GHz, about 19 MB/s; 9.14-9.16), and W4 ended in the
decision of 9.21: brcmfmac comes up at boot behind the restricted DMA pool,
without the SysMMU, which can't tell PCIe from UFS
(`omamobile-wifi.service`, omamobile-device-cheetah 0.1.12+). Battery: B1
and B1b passed (stock's battery model loaded at probe; NOTES.md). Charging
(B2-B4) continues in `USB-C-PLAN.md`, Bluetooth in `BLUETOOTH-PLAN.md`.
Kernel: `omamobile-wifi` @ `a3061be71` (`wt-wifi`) and `omamobile-w4` @
`242602382` (`wt-pcie`, on the `omamobile-pcie` work), both merged into
`omamobile-int`. **Next:** the D3 handshake for suspend, branch
`omamobile-wifi-d3` @ `e20614037` (`wt-wifi-d3`; built, not merged;
`SUSPEND-PLAN.md` S5); 6 GHz is future work.

Earlier status (historical, superseded by the status above): W0/B0 (offline prep) done, see "G0 status". B1 done on the phone.
PCIe drivers for Wi-Fi (W0b) built offline (section 7). **W1 hung the phone
twice on 2026-10-11; the cause is found and fixed offline, and W1.3 now runs
in stages with a log capture tool: see section 8, which replaces the W1.3
step of 7.5.** Written 2026-10-11 against `omamobile` @ `0e73f9013`
(Linux 7.3-rc6), kernel branch `omamobile-wifi` in `wt-wifi`; PCIe work in
`omamobile-pcie` (`wt-pcie`).

Goal: Wi-Fi through mainline brcmfmac, Bluetooth through hci_bcm, and battery
level plus charging through the upstream MAX77759 drivers, each with Google's
own firmware files taken from the user's factory image.

Path abbreviations:

- `L/` = `/home/raven/android/mainline/wt-wifi` (our kernel, this branch)
- `G/` = `/home/raven/android/omamobile/out-kernel/google/gs-6.1/private`
- `GS/` = `G/google-modules/soc/gs`
- `W/` = `G/google-modules/wlan/bcm4389` (Google's bcmdhd for this chip)
- `R/` = `/home/raven/android/reference/cheetah-stock-cp2a-root` (stock live DT, logs)
- `R0/` = `/home/raven/android/reference/cheetah-stock-cp2a`

---

## 1. Wi-Fi: the PCIe path

### 1.1 Which controller

The BCM4389 sits on **`pcie_1` at `0x14520000`**, the 1-lane Gen2 controller
in the HSI2 block (Google calls it GEN4A_1, `ch-num = 1`). The other
controller, `pcie_0` in HSI1 (`0x11920000`), carries the Exynos 5300 modem.
Stock: "exynos-pcie-rc 11920000.pcie: wlan gpio is not defined -> don't use
wifi through pcie#0" (`R/dmesg.txt:1994`).

| Item | Value | Evidence |
|---|---|---|
| ELBI (Samsung glue) | `0x14520000` / `0x2000` | `R/live.dts:12107-12111` |
| UDBG | `0x14560000` / `0xd000` | same |
| PHY (PMA) | `0x14550000` / `0x2000` | same |
| PCS | `0x14540000` / `0x1000` | same |
| SYSREG_HSI2 | `0x14420000` (IOCC bits at +0x730) | same; `GS/drivers/pci/controller/dwc/pcie-exynos-rc.h:240-245` |
| DBI (DesignWare, iATU unrolled at +0x300000) | `0x14800000` / `0x301000` | same |
| Config space | `0x60ffe000` / `0x2000` | same |
| IA (link-training sequencer) | `0x14500000` / `0x1000` | same |
| MEM window | PCI `0x60000000` -> CPU `0x60000000`, `0xff0000` | `R/live.dts:12121` |
| IRQ | GIC SPI **428** (`0x1ac`), level. Wi-Fi uses **INTx** (`use-msi = "false"`); `interrupt-map` sends INTx to SPI 428. SPIs 429-433 are the unused MSI lines | `R/live.dts:12112-12115,12131`; `R/interrupts.txt:243` ("exynos-pcie, dhdpcie") |
| Link | 1 lane, Gen2 max | `R/live.dts:12123,12138` |
| DW IP version | `0x984500` | `R/live.dts:12122` |
| Coherency | `dma-coherent`, `use-cache-coherency` | `R/live.dts:12128,12145` |
| PHY isolation | PMU `0x18060000 + 0x3ec4` (secure: goes through SMC; our gs201 PMU regmap already does that) | `R/live.dts:12136`; `GS/.../pcie-exynos-rc.c:393-407`; `L/drivers/soc/samsung/exynos-pmu.c:105-128` |
| Supplies | vreg1 0.85 V = S2MPG13 LDO3 "L3S_PCIE1", vreg2 1.8 V = S2MPG13 LDO18 "L18S_PCIE1", both `regulator-always-on` | `R/live.dts:12143-12144`; `G/devices/google/gs201/dts/gs201-common.dtsi:345-376` |
| Clocks | none in the DT (`pcie-clk-num = <0>`, `phy-clk-num = <0>`): the CMU_HSI2 gates run on automatic gating | `R/live.dts:12125-12126`; `GS/.../pcie-exynos-rc.c:2388-2425` |
| Power domain | none: `pd_hsi2` is disabled in stock, HSI2 is never power-gated (UFS lives there) | `R/live.dts:7285-7294` |

### 1.2 Pins

All on the HSI2 pin controller **`pinctrl@14440000`** (stock `pinctrl_7`,
alias `pinctrl7`, GIC SPI 421) except the host-wake line.

| Signal | Pin | Config | Evidence |
|---|---|---|---|
| PERST# | `gph2-0` | output | `R/live.dts:3480-3497` |
| CLKREQ# | `gph2-1` | function 2 | same |
| WL_REG_ON | `gph2-4` | output, no pull; Google drives it high, then waits 200 ms | `G/devices/google/gs201/dts/gs201-cloudripper-wlan.dtsi:25-33,51`; `W/dhd_custom_google.c:515-590`; `R/dmesg.txt:5171` |
| WL_DEV_WAKE | `gph2-5` | input, pull-down | `gs201-cloudripper-wlan.dtsi:34-42,53` |
| WL_HOST_WAKE (OOB) | `gpa6-1` (FAR_ALIVE, SPI 45) | EINT, pull-down | `gs201-cloudripper-wlan.dtsi:14-23,52`; `R/interrupts.txt:333` |

`L/drivers/pinctrl/samsung/pinctrl-exynos-arm64.c:2271-2275` already has the
gs201 HSI2 banks (`gph2` 6 pins, `gph4`); only the DT node is missing.

### 1.3 Handoff state: the link is down

ABL does not train the link. Google's driver probes `pcie_1` with nothing on
the bus and powers the PHY down at the end of probe
(`exynos_pcie_rc_resumed_phydown()`, `GS/.../pcie-exynos-rc.c:5712`;
`R/dmesg.txt:2059-2126`). When bcmdhd asks for the card it raises WL_REG_ON
(3.571 s), runs the full PHY table and LTSSM, reaches L0 at 3.809 s
(`R/dmesg.txt:5171,5424-5425`), and `0001:01:00.0 [14e4:4441]` enumerates at
3.817 s. So **we need the whole PHY init ourselves**. On the plus side the
HSI2 block is powered and clocked at handoff (DBI reads work at stock probe
with no clocks enabled, and our UFS driver already runs in HSI2).

### 1.4 What mainline has, and what a gs201 port needs

- `L/drivers/pci/controller/dwc/pci-exynos.c` supports only
  `samsung,exynos5433-pcie` (line 379). Its ELBI layout differs (LTSSM enable
  at 0x02c, link-up at 0x074 bit 4; lines 27-51) from Google's (LTSSM enable
  at **0x054**, link state at **0x2c8 & 0x3f == 0x11**).
- `L/drivers/phy/samsung/phy-exynos-pcie.c` supports only
  `samsung,exynos5433-pcie-phy` (line 138).
- No FSD, ExynosAuto v9, gs101 or gs201 PCIe support anywhere in our tree or
  in pmOS (`pmos-tensor` only has the gs101 PCIe regulators,
  `gs101-pixel-common.dtsi:359-377`). gs101 has no PCIe node upstream either.
- Clocks: `clk-gs201.c` has CMU_HSI2 with every PCIe gate (IDs 3, 9-10,
  13-18, 27-39, 44-47, 55, 57-64 in `L/include/dt-bindings/clock/google,gs201.h`;
  driver `hsi2_cmu_info` at `clk-gs201.c:3104`). CMU_HSI1 (the modem's PCIe)
  has no driver, which we don't need.

Port, in order:

1. **PHY driver** (`phy-exynos-pcie.c` variant `google,gs201-pcie-phy`):
   the ~200-write table of `GS/drivers/pci/controller/dwc/pcie-exynos-gs201-rc-cal.c:99-339`
   ("CAL ver 210802": PHY reset through ELBI 0x1400/0x1404/0x1408, common PMA,
   38.4 MHz refclk block, per-lane tables at +0x800 stride, PCS 0x004/0x150/
   0x154/0x170/0x190, reset release, XO config at 0x5d0), plus the
   power-down helpers at `:36-88` and the PMU isolation bit at 0x3ec4.
   gs101's table differs only in the 38.4 MHz block, some RX tuning and the
   power-down details, so one driver can cover both.
2. **Controller glue** (new `pcie-google.c` or a variant table in
   `pci-exynos.c`, ~300-400 lines): PERST GPIO, LTSSM at ELBI 0x054, link
   poll at 0x2c8, INTx demux from ELBI IRQ0/IRQ2 (0x0/0x8, enables
   0x10/0x18), SYSREG IOCC bits, UDBG 0x421 at +0xc800 for ch1, DBI 0x890
   "EQ off" write; follow `exynos_pcie_rc_establish_link`
   (`GS/.../pcie-exynos-rc.c:3551-3680`). The IA CDR-lock sequencer
   (`:2966-3068`), L1SS and the vendor SysMMU can wait.
3. **DT:** HSI2 pinctrl node, `pcie_1` + PHY nodes, a `wifi@0,0` child with
   `compatible = "pci14e4,4441"` and `brcm,board-type`, WL_REG_ON as a fixed
   regulator (`vpcie3v3`-style) or via `pwrseq`, and the two S2MPG13 LDOs as
   fixed always-on regulators until there is an S2MPG13 driver (stock keeps
   them always on, `R/live.dts:13494-13519,14013-14182`).

The sketch for step 3 is in section 1.7. It is deliberately **not** in the
kernel branch: without a binding and a driver, the compatible strings and
`reg-names` would be guesses that churn.

### 1.5 The DMA firewall (S2MPU) and what it means

Each gs201 bus has an S2MPU (stage-2 memory protection unit) in front of its
DMA masters. The HSI2 one covers the Wi-Fi chip (and UFS):

| Node | Address | IRQ | Notes |
|---|---|---|---|
| `s2mpu_hsi2` | `0x145e0000` | SPI 448 | `always-on`, programmed by pKVM | 
| `sysmmu_hsi2` (`samsung,pcie-sysmmu`, "PCIe_CH1") | `0x145c0000` | SPI 446 | Samsung PCIe IOMMU, Google's own driver |

Evidence: `R/live.dts:9638-9644,12157-12169`; `R/iomem.txt:48`.

- **Stock programs the S2MPU from the hypervisor, not EL3.** The bootargs
  carry `kvm-arm.mode=protected kvm-arm.protected_modules=exynos-pd,pkvm_s2mpu`
  (`R/dmesg.txt:111`), and "pkvm-s2mpu 145e0000.s2mpu_hsi2: registered with
  hypervisor" (`R/dmesg.txt:461`). The EL2 code
  (`GS/drivers/soc/google/pkvm-s2mpu/common/hyp/s2mpu.c:448-472`) installs the
  host's memory map on resume and blocks everything on suspend. Google's EL1
  driver notes "Most S2MPUs are in an allow-all state at boot"
  (`GS/drivers/soc/google/pkvm-s2mpu/common/pkvm_s2mpu.c:360`).
- **On our boot it is off.** We don't run pKVM. `S2MPU_HSI0` reads `CTRL0 = 0`
  (disabled) on our kernel (NOTES.md, "lost USB"). UFS DMA, which goes through
  `s2mpu_hsi2`, already works under mainline, so HSI2 is not blocking either.
  To confirm at W1, read `0x145e0000` (`REG_NS_CTRL0`, bit 0 = enable;
  `GS/drivers/soc/google/pkvm-s2mpu/common/kvm_s2mpu.h:224,252`). That is a
  plain MMIO read in HSI2, not a PMU register. Do it with `tools/devmem`
  **only while UFS is up**, which it always is on our boot.
- **Stock also puts the Wi-Fi chip behind `sysmmu_hsi2`** ("PCIe SysMMU is
  ENABLED", `R/dmesg.txt:2075`), but only as a 1:1 identity map of each DMA
  buffer (`GS/.../pcie-exynos-rc.c:273-283,333-340,3924-3927`). The driver
  (`GS/drivers/iommu/exynos-pcie-iommu-whi.c`) is not upstream, and
  upstream `exynos-iommu.c` (SysMMU v1-v7) is a different block.
- **Security implication.** With no S2MPU and no IOMMU, the BCM4389 can DMA
  to **all of RAM**. Its firmware parses untrusted radio frames, and
  Broadcom Wi-Fi firmware has had remote code execution bugs before
  (Broadpwn, CVE-2017-9417; Project Zero's 2017 BCM4358 chain). A firmware
  compromise would then mean full kernel compromise, with no Android-style
  containment. That is acceptable for bring-up and for a developer phone. It is
  **not acceptable for a default-on Wi-Fi in an image we ship**. Before
  Wi-Fi is on by default, one of these must be done:
  1. Program `s2mpu_hsi2` from EL1 (no pKVM): give the Wi-Fi VID access only
     to a dedicated `restricted-dma-pool` (swiotlb) region that brcmfmac
     bounces through. This is the smallest change. The register layout is in
     `kvm_s2mpu.h`; Google's EL1 driver `GS/drivers/soc/google/s2mpu/s2mpu-core.c`
     shows how to program it without the hypervisor. Watch out: UFS shares
     this S2MPU, so the map needs UFS's buffers too (or per-VID maps).
  2. Port `sysmmu_hsi2` as a real IOMMU driver.
  3. Run pKVM with Google's S2MPU hyp module (large; not upstream).

  Option 1 with a restricted DMA pool on the `wifi@0,0` node is the
  recommended path (W4).

### 1.6 BCM4389 in brcmfmac

**Not supported upstream** before this branch: no 4389 chip or PCI ID in
`L/drivers/net/wireless/broadcom/brcm80211/` (only up to 4387, Apple's).
Our commit `wifi: brcmfmac: add BCM4389 PCIe support` adds it. Facts:

| Item | Value | Evidence |
|---|---|---|
| PCI ID | `14e4:4441` | `R/dmesg.txt:5461`; `W/include/bcmdevs.h:138` |
| Chip ID | `0x4389` | `W/include/bcmdevs.h:193`; `R/dmesg.txt:5466` |
| CPU | ARM Cortex-A7 in SYSMEM, RAM base **0x200000**, 2752512 bytes (21 x 128 KiB banks) | `W/dhd_pcie.c:2336-2349`; `W/include/sbchipc.h:4245`; `R/dmesg.txt:5467-5490` |
| PCIe core rev | 72 (brcmfmac's rev >= 64 register map, same as BCM4387) | `R/dmesg.txt:6988` ("buscorerev=72") |
| Random seed | 0xfeedc0de TLV before NVRAM (stock writes 128 bytes; brcmfmac writes 256 with the length in the footer) | `R/dmesg.txt:6987`; `W/include/bcmrand.h:50,63` |
| Signed firmware | no: `FW_SIGNATURE` is not set in Google's build | `W/Kbuild` (no match); `W/dhd_pcie.c:10192` |
| Firmware | `4389c1-roml/config_pcie_release2 Version=20.101.90`, FWID 01-3f632e0d | `strings fw_bcmdhd.bin`; `R/dmesg.txt:7138` |
| CLM | "Google.C10sub6" | `R/dmesg.txt:7171` |
| NVRAM | text, "bcm94389c1GGmodG2 C10", board-revision suffixes picked by `ro.revision` (MP1.0 has none, so plain `bcmdhd.cal`) | `bcmdhd.cal` header; `W/dhd_custom_google.c:255-330,440-510` |
| MAC address | from ABL: `/chosen/config/wlan_mac1` (and `bt_addr`); bcmdhd reads it there | `W/dhd_custom_google.c:140-141,182-235`; `R/live.dts:12664-12665` |

brcmfmac requests (board type = first root compatible, `/` replaced by `-`;
`L/.../brcmfmac/of.c:99-114`, `firmware.c:621-675`):

```
brcm/brcmfmac4389c1-pcie.google,gs201-cheetah.bin       (then brcmfmac4389c1-pcie.bin)
brcm/brcmfmac4389c1-pcie.google,gs201-cheetah.txt       (NVRAM, optional)
brcm/brcmfmac4389c1-pcie.google,gs201-cheetah.clm_blob  (optional)
brcm/brcmfmac4389c1-pcie.google,gs201-cheetah.txcap_blob (optional; Google has none)
```

Risks, to be settled at W2:

- **IPC version.** brcmfmac accepts shared-ring versions 5-7
  (`pcie.c:217-218`); Google's driver knows up to 9 (`W/include/bcmpcie.h:45-49`).
  If the firmware reports 8 or 9, probe fails with "Unsupported PCIE version".
  Then check what changed in 8/9 in `W/dhd_msgbuf.c` before widening the check.
- **D2H sync.** Stock logs "D2H sync mechanism is XORCSUM": the firmware
  checksums completions. brcmfmac doesn't verify them. That is harmless unless
  it reads a completion before the DMA finishes. Watch for corrupted messages.
- **Inband device wake** ("FW supports Inband dw ? Y", "ENABLING DW:2"): the host
  opts in, and brcmfmac doesn't. Expect no deep sleep, so more power use.
- **MAC address.** brcmfmac takes `local-mac-address` only from its own DT
  node, and ABL's `/chosen/config/wlan_mac1` isn't wired. Without it the
  firmware uses the OTP or NVRAM MAC, or a random one. Fix in userspace first: a
  udev/systemd-networkd `.link` from `/proc/device-tree/chosen/config/wlan_mac1`.
  Don't commit or print the value; it's a device identifier.
- **Chip revision.** The firmware entry matches all revisions as "4389c1". Read
  the real revision from brcmfmac's "chip BCM4389/N" line at W2 and narrow the
  mask.

### 1.7 DT (built, see section 7)

The sketch that was here is now real: `gs201.dtsi` has `pinctrl_hsi2`,
`pcie_1` and `pcie_1_phy`, and `gs201-cheetah.dts` wires WL_REG_ON, the
host-wake and dev-wake pins and the `wifi@0,0` node (section 7.2). Two
corrections to the sketch: the controller clocks are the x2 controller's
(`PCIE_003`), not `PCIE_004` (7.3), and WL_REG_ON hangs off a root port
node, where the PCI pwrctrl core finds it.

---
## 2. Firmware: where it is and how we get it

### 2.1 Files on the vendor partition

`/vendor/firmware` (`R/vendor-firmware.txt`; LineageOS lists them in
`device/google/pantah/cheetah/proprietary-files-vendor.txt:500-508`):

| Vendor file | Size | What | Mainline name we install |
|---|---|---|---|
| `fw_bcmdhd.bin` | 1764091 | Wi-Fi firmware, `4389c1-roml/config_pcie_release2`, 20.101.90 | `brcm/brcmfmac4389c1-pcie.google,gs201-cheetah.bin` |
| `bcmdhd.cal` | 27237 | Wi-Fi NVRAM (text), board bcm94389c1GGmodG2 C10 | `brcm/brcmfmac4389c1-pcie.google,gs201-cheetah.txt` |
| `bcmdhd_clm.blob` | 18348 | Regulatory (CLM) "Google.C10sub6" | `brcm/brcmfmac4389c1-pcie.google,gs201-cheetah.clm_blob` |
| `brcm/BCM.hcd` | 478867 | Bluetooth patch "BCM4389C1 ES1PX_GG_C10" (selected by `persist.bluetooth.firmware.selection=BCM.hcd`, `device/google/pantah/cheetah/product.prop:14`) | `brcm/BCM.google,gs201-cheetah.hcd` |
| `bcmdhd.cal_{EVT,PROTO}*`, `brcm/BTFW_{B,D}.hcd`, `fw_bcmdhd.map` | | Pre-production boards, alternative BT builds, symbol map | not needed (our phone is `ro.revision=MP1.0`, `R0/getprop.txt`) |

Files go under `/usr/lib/firmware/updates/brcm/`. The firmware loader looks
there before linux-firmware's own files, and no package owns that directory.
Both drivers try the board-specific name first (`brcm_alt_fw_path()`,
`L/.../brcmfmac/firmware.c:621-675`; `btbcm_initialize()`,
`L/drivers/bluetooth/btbcm.c:651-667`), so a generic file from some
future linux-firmware can't shadow ours.

### 2.2 Extraction (done, offline): `tools/extract-vendor-firmware`

Pixel factory zips carry `vendor.img` directly. It is **not** inside a
`super.img`; the zip only has `super_empty.img`. In `cp2a.260705.006` it is a
**raw ext4** image (magic `0xef53` at 0x438, 841 MB), so `debugfs` reads it
without mounting or root. The script:

- takes the outer factory zip, the inner `image-cheetah-*.zip`, or a raw or
  sparse `vendor.img`;
- falls back to `lpunpack` for super-only images and to `fsck.erofs --extract`
  for EROFS vendors, so it keeps working if Google changes format;
- checks `android-info.txt` (`require board=...|cheetah|...`) and the vendor
  partition's own `ro.product.vendor.device=cheetah`;
- copies the four files under their mainline names, sanity-checks them
  (`4389c1-roml` tag, `BCM4389C1` patch, `NVRAMRev=` text NVRAM), and writes a
  sha256 list.

Verified on `image-cheetah-cp2a.260705.006.zip` (4.4 s), on the raw
`vendor.img`, and on an `img2simg` sparse copy. All three give identical
output:

```
c42039b351c9254a475a9eab8f090a2564901dd0aaca44c7412908ecd6929ff4  BCM.google,gs201-cheetah.hcd
8a52ffe1d71d29f3729247a31be912ff9e9b9959effa36fe94f2e3f5cccf916b  brcmfmac4389c1-pcie.google,gs201-cheetah.bin
adb2b2a28469c25fa196cffe0be4fb0ce29c250ec85b2ef3d4e9fa2db99771f8  brcmfmac4389c1-pcie.google,gs201-cheetah.clm_blob
a08c7df9e2ebc1522029825bd94e340d6cbed8ecdf002c02e1f6f808f60746a2  brcmfmac4389c1-pcie.google,gs201-cheetah.txt
```

Usage:

```sh
tools/extract-vendor-firmware -o out/vendor-firmware \
  ~/android/factory/cheetah-cp2a.260705.006/image-cheetah-cp2a.260705.006.zip
tar -C out/vendor-firmware -cf - usr | tools/phone-ssh 'tar -C / -xf -'
```

### 2.3 Licensing and redistribution

- These files are Broadcom/Google proprietary firmware. Google's factory images
  are offered for restoring Pixel devices, under Google's terms. They carry no
  redistribution licence like linux-firmware's `LICENCE.broadcom_bcm43xx`, and
  the NVRAM header even says `<<Broadcom-WL-IPTag/Proprietary:Vendor1007>>`.
- **So Omamobile never ships them:** not in git, not in a package, not in an
  image we publish. `*.img` and `*.zip` are already gitignored, and the script
  writes under `out/`, which is ignored too. The user extracts them on their own
  machine from the factory image of their own phone, as LineageOS's
  `extract-files.sh` does (it pulls the same paths from a device or image).
- An Arch package can depend on the *script* and run it at install time
  against a user-supplied zip (like `extract-files`). It must not contain the
  blobs.
- Never commit the MAC addresses ABL puts in `/chosen/config` (`wlan_mac1`,
  `bt_addr`): they identify the device.

---

## 3. Bluetooth

**Moved to `BLUETOOTH-PLAN.md` (2026-10-12)**, which has the hardware table
with evidence, the kernel work (branch `omamobile-bt`, all off by default)
and the BT1-BT3 runbook. Bluetooth does not depend on the PCIe/Wi-Fi work.
What changed against the notes that were here:

- **CMU_APM blocker solved** with a read-only CMU_APM subset in
  `clk-gs201.c`: real mux/divider tree for the UART, no register writes
  (read-only mux/divider, no clk_regs, no option write, auto-mode gates).
  The UART clock should read 197 MHz (Google's LUT); BT1.1 checks it.
- **USI wrapper confirmed:** the APM UART has the standard USIv2 block at
  +0xc0 (Google's driver writes `USI_CON` +0xc4 and `USI_OPTION` +0xc8 with
  CLKREQ_ON), so the upstream `exynos850-usi` driver with `samsung,clkreq-on`
  handles it. SW_CONF is `sysreg_apm` +0x4e4 (confirmed: stock sysreg node at
  `0x180204e0`, usi-offset 4).
- **BT is powered alone:** BT_REG_ON (`gpp16-2`) and WL_REG_ON (`gph2-4`) are
  separate pins with no shared regulator in the stock DT.
- `samsung_tty` needs no change: `google,gs201-uart` falls back to
  `google,gs101-uart`.

---

## 4. Battery and charging: MAX77759

### 4.1 Wiring (cheetah)

All on **PERIC1 USI13 / HSI2C13** at `0x10d60000`, GIC SPI **695**, 400 kHz,
pins `gpp25-0/1` function 2 (`R/live.dts:4510-4517,8185-8205`;
`G/devices/google/gs201/dts/gs201-usi.dtsi:368-386`). Clocks are already in
`clk-gs201.c` (`CLK_GOUT_PERIC1_USI13_USI_{IPCLK,PCLK}`,
`L/include/dt-bindings/clock/google,gs201.h:598-599`).

| Addr | Function | IRQ | Evidence |
|---|---|---|---|
| 0x66 | MAX77759 core (+ MAXQ, same address) | `gpa9-4`, low | `R/live.dts:8273-8292,2995-3001` |
| 0x69 | charger (MFD cell, no DT node upstream) | shares `gpa9-4` | `R/live.dts:8354-8380`; `R/interrupts.txt` "max777x9_pmic, max77759_charger" |
| 0x36 | fuel gauge, the MAX77759's own "M5" gauge (no NVM, so no 0x0b) | `gpa9-3`, low | `R/live.dts:8295`; `R/dmesg.txt:1225-1230` |
| 0x25 | TCPCI | `gpa9-7`, low | `R/live.dts:8207-8215,2943-2949` |
| 0x57 | PCA9468 direct charger (separate chip, not needed) | `gpa9-0` | `G/devices/google/gs201/dts/gs201-cloudripper-battery.dtsi` |

`gpa9` is on ALIVE (`pinctrl@180d0000`). The ALIVE pinctrl node comes from
the buttons branch (`a3e96fceb`, cherry-picked here; it drops out on rebase).

Battery: 4926 mAh (`google,chg-battery-capacity`,
`G/devices/google/pantah/dts/gs201-cheetah-battery.dtsi:10`). Rsense 5 mΩ
(`maxim,rsense-default = <500>`). Stock float voltage is 4400 mV
(`R/live.dts:8354-8380`). Stock at capture time: 87 %, 4404 mV, 29.4 °C,
charging over USB at up to 3 A (`R0/dumpsys-battery.txt`).

### 4.2 Upstream drivers (all present in 7.3)

| Function | Driver | Binds by |
|---|---|---|
| core | `drivers/mfd/max77759.c` | `maxim,max77759` (checks PMIC_ID 0x3b; stock reports 0x3b rev 2) |
| GPIO | `drivers/gpio/gpio-max77759.c` | `gpio` subnode |
| NVMEM | `drivers/nvmem/max77759-nvmem.c` | `nvmem-0` subnode (left out: no reboot-mode use yet) |
| charger | `drivers/power/supply/max77759_charger.c` | MFD cell |
| fuel gauge | `drivers/power/supply/max17042_battery.c:1666` | `maxim,max77759-fg` |
| TCPCI | `drivers/usb/typec/tcpm/tcpci_maxim_core.c:588` | `maxim,max77759-tcpci` |

The upstream gs101 board (`L/arch/arm64/boot/dts/exynos/google/gs101-pixel-common.dtsi:645-850`)
is the template. We use the same nodes on hsi2c_13 with gs201's pins.

### 4.3 Gotchas found in the drivers

- **The charger turns charging off at probe.** `max77759_charger_init()`
  sets mode OFF and only turns it back on when a power supply named
  `tcpm-source` reports online (`max77759_charger.c:540-553,663`). Without
  TCPM, loading it **stops charging**. It also programs float voltage and
  fast-charge current from `monitored-battery`, or the defaults 4300 mV /
  2.27 A (`:27-28`). Those are conservative next to stock's 4400 mV, so safe.
  The MFD binding has no `monitored-battery` yet
  (`maxim,max77759.yaml`, `unevaluatedProperties: false`).
- **TCPCI owns the USB-C port.** Loading `tcpci_maxim` makes TCPM drive
  CC/VBUS. Today the USB PHY forces VBUS valid (NOTES.md, "USB doesn't
  reconnect"), and USB is our only link. So TCPCI comes last, with the
  role-switch/orientation wiring, and only with a recovery path ready.
- **The fuel gauge re-initialises only after a POR.** `max17042_probe()` runs
  the init worker only if STATUS bit 1 (POR) is set
  (`max17042_battery.c:1551`). Stock's driver ran first and cleared it, so
  probe should only read. Check that bit before loading anyway.
- **Capacity units.** Google's model has DesignCap 0x09c5 (2501) for a
  4926 mAh pack (`gs201-cheetah-battery-data.dtsi:63-83`), i.e. about 2 mAh/LSB.
  Upstream max17042 assumes 5 µVh/Rsense = 1 mAh/LSB at 5 mΩ. Expect
  `charge_full` to read about half the real value until this is understood.
  Compare with `R0/dumpsys-battery.txt` (charge counter 3982000 µAh at 87 %).
  **Resolved in B1b:** the model's TaskPeriod 0x2d00 doubles the LSB to 2 mAh,
  and upstream already scales by TaskPeriod.

---

## 5. Bring-up sequence with gates

Rules: everything new is a module, blacklisted from autoload where probing
changes hardware state (`device/cheetah/rootfs/etc/modprobe.d/omamobile-max77759.conf`).
It is loaded by hand over SSH while a second session runs `dmesg -w`.
`panic=10` and ABL's A/B fallback are the recovery path (NOTES.md).

### Gate B0 / W0: offline prep (done; see "G0 status")

### Gate B1: I2C and fuel gauge (low risk)

1. Boot the new DTB. **Pass:** USB/SSH, UFS and touch unchanged;
   `/sys/bus/i2c/devices/i2c-*/name` shows `10d60000.i2c`; the clients
   `*-0036` and `*-0066` exist but are unbound (blacklisted).
2. `i2cget -y <bus> 0x66 0x00` must return 0x3b (PMIC_ID). `i2cget -y <bus>
   0x36 0x00 w` reads STATUS; **stop if bit 1 (POR) is set**. Note the value.
3. `modprobe max17042_battery`. **Pass:** `/sys/class/power_supply/max77759-fg*`
   with sensible `capacity`, `voltage_now` (about 3.6-4.4 V) and `temp`.
   `current_now` changes sign when the cable is pulled.

### Gate B2: MFD core and GPIO (low risk)

`modprobe max77759` (the charger cell then tries to autoload, but is
blacklisted). **Pass:** `max77759` binds, `gpiochip` with 2 lines, and the
interrupt on gpa9-4 does not storm (`grep gpa9 /proc/interrupts` twice).

### Gate B3: charger (medium risk: charging stops)

Only with the battery above 50 %. Before loading, record the charger mode:
`i2cget -y <bus> 0x69 0xb9` (CHG_CNFG_00, mode in bits 3:0;
`L/include/linux/mfd/max77759.h:91-92`). Then `modprobe max77759_charger`.
**Expected:** `power_supply/max77759-charger` appears and **charging stops**
(no `tcpm-source`). This proves register access. After `rmmod`, the mode
register keeps OFF; write the recorded value back with `i2cset` (the mode
field is not write-protected, unlike the registers `unlock_prot_regs()`
guards), or boot stock, whose driver sets it again. Real charging needs B4.

### Gate B4: Type-C (high risk: USB link)

Needs the dwc3 role switch and USB PHY orientation wiring first (USB-C row of
the main plan), and a second way in (Wi-Fi, W3). Then enable
`usb-typec@25`, load `tcpci_maxim`, and check that `tcpm-source` goes
online and the charger switches to charge mode.

### Gate W1: PCIe controller (medium-high risk)

Runbook: section 8.4 (staged; 7.5 for W1.0-W1.2). **Pass:** "PCIe Gen.2 x1 link up" and
`lspci -nn` shows `01:00.0 Network controller [0280]: Broadcom ... [14e4:4441]`.
(0x4441 is the PCI device ID; 0x4389 is the chip ID that brcmfmac prints at
W2.) Never touch PMU 0x3ec4 from userspace (see the PMU warnings in
NOTES.md and GPU-PLAN.md); the PHY driver does it through the PMU regmap.

### Gate W2: brcmfmac (medium risk)

Runbook: section 7.6. **Expected:** "brcmfmac: brcmf_fw_alloc_request: using
brcm/brcmfmac4389c1-pcie for chip BCM4389/N", then the firmware version line
with 20.101.90 and the CLM version, `wlan0` in `iw dev`, and a scan that
lists networks. Note the chip rev N. **Failures:** "Unsupported PCIE
version" (see 1.6), FW-up timeout (seed/NVRAM placement), or a missing CLM
file (check the names).

### Gate W3: Wi-Fi works (low risk)

`iw dev`, set the MAC from `/proc/device-tree/chosen/config/wlan_mac1`,
NetworkManager scan and connect, then `iperf3`. Watch for
"XORCSUM"/sequence errors and firmware traps.

### Gate W4: DMA protection before default-on (required)

Program `s2mpu_hsi2` for the Wi-Fi VID to a restricted DMA pool (1.5). The
pool is already in the DT, disabled (`wifi_dma_pool`, 16 MiB); 7.7 shows how
to test brcmfmac through it before the S2MPU work. **Until W4 is done, Wi-Fi
must not ship enabled:** `pcie_1` stays `disabled` in the default DTB, and
`pcie_gs201` and `brcmfmac` stay blacklisted in `omamobile-device-cheetah`.

What W1-W2 found about the HSI2 SysMMU and S2MPU (registers that abort,
the working DMA setup) is in 9.14, "W4".

### Gates BT1-BT3

See `BLUETOOTH-PLAN.md` section 4: BT1.0 new kernel, BT1.1 CMU_APM read-only
check, BT1.2 UART loopback, BT1.3 HCI_Reset by hand (`tools/bt-uart-test`),
BT2 `hci_uart` + firmware patch, BT3 BlueZ scan/pair and low power.

---

## 6. Effort and risks

| Step | Estimate | Risk |
|---|---|---|
| B1-B2 fuel gauge + MFD | 0.5 day | low |
| B3-B4 charging through TCPM | 2-4 days (needs the dwc3 role switch + PHY orientation) | high (USB link) |
| W1 PCIe PHY + controller drivers | 4-7 days | medium-high (SError if a register block is unclocked) |
| W2-W3 brcmfmac on BCM4389 | 1-3 days | medium (IPC version, sync mode) |
| W4 S2MPU restricted DMA | 2-4 days | medium (UFS shares the S2MPU) |
| BT1-BT3 CMU_APM + UART + hci_bcm | 3-5 days | medium (APM-owned CMU) |

Top risks:

1. **The PHY table has to be right first time.** If the link doesn't train,
   all we get is a timeout. Compare register dumps with Google's CAL step by
   step. HSI2 is powered, so reads are safe.
2. **brcmfmac vs. firmware IPC differences** (version 8/9, XORCSUM, inband
   DW). Fallback: port the specific pieces from Google's `dhd_msgbuf.c`.
3. **DMA from the Wi-Fi chip** is unrestricted until W4.
4. **Charging regressions:** the charger stops charging at probe (4.3).
   Never autoload it before B4.
5. **CMU_APM** belongs to the APM/ACPM firmware domain. Writing its gates
   from Linux may race with ACPM. Read-only first.

---

## G0 status (2026-10-11, offline; nothing was run on the phone)

> **Historical.** Superseded by the B1 and B1b results, sections 8 and 9
> (W1-W4, decision 9.21) and the status at the top.

### Kernel: `omamobile-wifi` in `wt-wifi`, on `omamobile` @ `0e73f9013`

| Commit | What | State |
|---|---|---|
| `6efec864b` wifi: brcmfmac: add BCM4389 PCIe support | chip/PCI IDs, CA7 RAM base 0x200000, firmware name `brcmfmac4389c1-pcie`, random seed | built; idle until W1 (no PCIe host) |
| `6b1fe828d` dt-bindings: net: wireless: brcm,bcm4329-fmac: add BCM4389 PCI ID | `pci14e4,4441` | `dt-doc-validate` ok |
| `aed2733f5` arm64: dts: exynos: google: gs201: add ALIVE pinctrl | **cherry-pick of `a3e96fceb` from `omamobile-buttons`**, needed for gpa9; it drops out when both land | as in buttons |
| `93dd7f5c2` dt-bindings: i2c: exynos5: add Google gs201 compatible | `google,gs201-hsi2c` | `dt-doc-validate` ok |
| `dab016aab` arm64: dts: exynos: google: gs201: add USI13 with its HSI2C | `usi13` + `hsi2c_13` (disabled in the SoC dtsi), `hsi2c13_bus` pins | |
| `f14275eb2` arm64: dts: exynos: google: gs201-cheetah: add the MAX77759 | USI13 in I2C mode, **okay**; `pmic@66` + `gpio`, `fuel-gauge@36` **okay**; `usb-typec@25` **disabled**; gpa9 IRQ pin configs | modules blacklisted (below) |
| `284a464ac` dt-bindings: net: bluetooth: brcm: add BCM4389 | `brcm,bcm4389-bt` | `dt-doc-validate` ok |
| `a79ca362f` Bluetooth: hci_bcm: add BCM4389 compatible | OF match only | built; idle until BT1 |

- Build: `logs/kernel-wifi.log`, `modules-wifi.log` and `images-wifi.log`
  all exit 0. Release `7.3.0-rc6-omamobile-push1-00041-ga79ca362f84d`;
  1680 modules; images in `~/android/mainline/out-wifi/images`.
- `dt-validate` (dtschema 2026.9) of `gs201-cheetah.dtb` against this tree's
  bindings reports only the existing `soc_id` property.
- The modules are there and carry the right aliases: `brcmfmac.ko` has
  `pci:v000014E4d00004441…` and the `brcmfmac4389c1-pcie` firmware names;
  `hci_uart.ko` has `of:…brcm,bcm4389-bt`; `max77759.ko`,
  `max77759_charger.ko`, `max17042_battery.ko`, `tcpci_maxim.ko` and
  `gpio-max77759.ko` exist.
- **Not in the branch, on purpose:** the PCIe controller, the PHY and the
  `pcie_1` node (no binding or driver yet; sketch in 1.7), and anything for the
  APM UART (no CMU_APM).

### omamobile repo

- `kernel/configs/omamobile.config`: `BRCMFMAC_PCIE=y`, `BRCMFMAC=m`,
  `BT_HCIUART(_BCM)`, `MFD_MAX77759`, `CHARGER_MAX77759`, `BATTERY_MAX17042`
  (the MAX77759 gauge driver; not MAX1720X).
- `device/cheetah/rootfs/etc/modprobe.d/omamobile-max77759.conf`: blacklists
  `max77759`, `max77759_charger`, `tcpci_maxim`, `max17042_battery`,
  `gpio_max77759` and `nvmem_max77759`.
- `tools/extract-vendor-firmware`: section 2.2.

### B1 runbook (phone in Arch over USB; run from the omamobile repo)

```sh
export KERNEL_OUT=$HOME/android/mainline/out-wifi
# 0. firmware for later (harmless now) and i2c-tools
tools/extract-vendor-firmware -o out/vendor-firmware \
  ~/android/factory/cheetah-cp2a.260705.006/image-cheetah-cp2a.260705.006.zip
tar -C out/vendor-firmware -cf - usr | tools/phone-ssh 'tar -C / -xf -'
tools/phone-ssh 'pacman -S --needed --noconfirm i2c-tools'
# 1. blacklist FIRST, so the new DTB cannot autoload the charger
tools/phone-ssh 'mkdir -p /etc/modprobe.d && cat > /etc/modprobe.d/omamobile-max77759.conf' \
  < device/cheetah/rootfs/etc/modprobe.d/omamobile-max77759.conf
# 2. modules, then the images into slot B, and reboot
bin/omamobile modules-push
bin/omamobile push
# 3. B0 pass check: unchanged USB/UFS/touch, the bus and unbound clients
tools/phone-ssh 'uname -r; lsmod | grep -cE "max77759|max17042|tcpci"; \
  ls -l /sys/bus/i2c/devices/ | grep 10d60000'   # i2c-BUS, BUS-0036, BUS-0066 (0x25 is disabled)
# 4. B1: read-only probes (BUS = the i2c number of 10d60000.i2c)
tools/phone-ssh 'i2cget -y BUS 0x66 0x00'        # expect 0x3b
tools/phone-ssh 'i2cget -y BUS 0x36 0x00 w'      # STATUS: stop if bit 1 (POR) is set
tools/phone-ssh 'i2cget -y BUS 0x69 0xb9'        # charger mode: write it down
# 5. fuel gauge (second terminal: tools/phone-ssh dmesg -w)
tools/phone-ssh modprobe max17042_battery
tools/phone-ssh 'grep . /sys/class/power_supply/*/{capacity,voltage_now,current_now,temp,charge_full}'
# 6. B2: core + GPIO; the charger cell stays unloaded (blacklisted)
tools/phone-ssh 'modprobe max77759 && modprobe gpio_max77759; grep gpa9 /proc/interrupts'
```

B3 (charger) and B4 (Type-C) follow section 5 and are **not** part of this
runbook.

### Open questions

- Does `hsi2c_13` work with our USI13 clocks as they are? The bus is clocked
  at handoff, since stock talks to it all the time, but this is the first
  HSI2C on gs201 under mainline. If step 3 shows timeouts, check
  `clk_summary` for `USI13`.
- The fuel gauge's capacity scale (4.3).
- The real BCM4389 chip revision and IPC version (W2).
- The APM UART clock rate and USI wrapper (BT1).
- Whether `s2mpu_hsi2` `CTRL0` reads 0 (W1, step 1).

## B1 result (2026-10-11, on the phone)

- Kernel `7.3.0-rc6-...-ga3061be71070` (`omamobile-wifi`, now merged into `omamobile`). USB, UFS, touch and the GPU unchanged.
- `10d60000.i2c` is `i2c-0`: the first gs201 HSI2C on mainline works with the clocks as they are. Clients `0-0036` and `0-0066` enumerate.
- `i2cget 0x66 0x00` = **0x3b** (PMIC_ID). Charger mode `0x69/0xb9` = 0x05.
- **Fuel gauge STATUS = 0x0082: the POR bit is set**, and DesignCap reads 3000 (the chip default; Google's model has 0x09c5). The gauge has lost Google's model and runs its own default EZ model. Read-only register dump: RepSOC 98 %, VCell 4.327 V, current about 0, Temp exactly 22.0 °C (probably a default; no thermistor configuration).
- Because our DT has no `monitored-battery`, `max17042_init_worker` writes nothing on POR (`max17042_battery.c:1187`: `enable_por_init` is only set by `max17042_apply_battery_properties`). So the driver was loaded: `max170xx_battery` reports capacity 97 %, 4.32 V, -7.8 mA, charge_full 2898 mAh of design 3000. Its interrupt (gpa9-3) stayed at 0, no storm. The fuel gauge now autoloads (removed from the blacklist); UPower and the status bar show the battery.
- Follow-ups: load Google's M5 model (`gs201-cheetah-battery-data.dtsi`) so capacity (4926 mAh) and temperature are right; check what Android's driver does when it next sees the gauge (it may reload its model on its own POR check); charger (B3) waits for Type-C (B4).


## B1b battery model (2026-10-11, offline; nothing was run on the phone)

Goal: right capacity and temperature from the MAX77759 gauge, by loading the
same ModelGauge m5 model that stock loads. Kernel branch `omamobile-battery`
in `/home/raven/android/mainline/wt-battery`, on `omamobile` @ `43918aeb7`;
build in `/home/raven/android/mainline/out-battery`.

### Why the B1 readings are wrong

- **Capacity.** After the POR the gauge runs its built-in EZ model:
  DesignCap 3000 and TaskPeriod 0x1680. Stock's model writes
  **TaskPeriod 0x2d00** (`G/devices/google/pantah/dts/gs201-cheetah-battery-data.dtsi:102`,
  the last fg-params word of the 1 kΩ model). This doubles the time base, so one capacity LSB is
  2 × 5 µVh / 5 mΩ = **2 mAh** (Google: `max_m5_period2caplsb()`, `cap_lsb=2` in
  `R/dmesg.txt:3295`). DesignCap 0x09c5 = 2501 LSB = **5002 mAh**. Google's
  model is rounded up a bit; their 4926 mAh is `google,chg-battery-capacity`.
  Upstream `max17042_battery.c` already scales every capacity by
  `TaskPeriod / 5760`, but it reads TaskPeriod only once, at probe. That
  settles the "2 mAh/LSB" question in 4.3.
- **Temperature.** At POR, Config has TEx set: the Temp register (0x08)
  holds a host-written value, 22.0 °C by default. Stock's Config 0x4217 clears
  TEx and sets TEn + ETHRM (external thermistor); TGain 0xed51, TOff 0x1eba
  and Curve 0x0014 convert AIN to °C (`max_m5_reg.h:396-411` for the Config
  bits). B1's exact 22.0 °C (0x1600) fits a TEx-mode register nobody writes.
- **`monitored-battery` alone would not help.** Upstream's POR init only
  applies `simple-battery` data for the MAX17055
  (`max17042_apply_battery_properties()` returns early for every other chip),
  and its legacy full-init path is the MAX17042 sequence, not the m5 one.

### The fix (kernel)

| Commit | What |
|---|---|
| `b83a53075` dt-bindings: power: supply: max17042: add MAX77759 battery model | `maxim,fg-model` (48 × u16, registers 0x80-0xaf) and `maxim,fg-params` (27 or 28 × u16, fixed order, Google's format); only for `maxim,max77759-fg`; each requires the other |
| `b26147fe2` power: supply: max17042_battery: load the MAX77759 battery model on POR | Only when the gauge reports POR and the DT has a model. Google's `max_m5_load_gauge_model()` order: wait FStat.DNR, refuse if Config2.LdMdl is set, unlock, write and verify the table, lock and verify (a locked table reads 0xffff), 500 ms, write the parameters (RepCap 0, RelaxCfg, extra-config unlock, VFSOC0, LearnCfg ... MiscCfg, AtRate, CV_MixCap = 75 % FullCapNom, CV_HalfTime 0x600, ConvgCfg, relock), Curve, FilterCfg, CGain, set Config2.LdMdl, poll until it clears and RepCap ≠ 0, check FullCapRep against FullCapNom (3 tries), re-read TaskPeriod, clear POR. On failure POR stays set (the next probe retries) and the driver keeps reporting from the default model |
| `50c4b244a` arm64: dts: exynos: google: gs201-cheetah: add the battery and its gauge model | `simple-battery` node (4926 mAh, 4.45 V max, 3.3 V min) as `monitored-battery`; the gauge model |

Model choice: stock reads a **1 kΩ battery ID** on this phone
(`R/dmesg.txt:3279`), so `maxim,cos-a1-1k` (model version 1), word for word as
in `R/live.dts:8337-8338`. Two words differ, on purpose: RelaxCfg 0x143b
(stock overwrites 0x0839 at every boot from `maxim,r_regval_1720x`) and
FilterCfg 0xc613 (stock switches to this above 10 °C, `filtercfg-default`).
We do **not** write the model version byte (TAlrtTh[15:8]); see the dual-boot
note. A different pack (ID 3, `lsn-a1-3k`) needs that model instead; Linux can't read the ID yet (stock gets it
through `gbms_storage` tag BRID, `max1720x_read_batt_id()`; the pack EEPROM
is `google,bee-name = "8-00500"` in `gs201-cheetah-battery.dtsi`).

Build: `logs/kernel-battery.log`, `modules-battery.log`, `images-battery.log`,
all exit 0. Release `7.3.0-rc6-omamobile-push1-00057-g50c4b244a706`, 1682 modules, images in `~/android/mainline/out-battery/images` (initramfs rebuilt there: `logs/initramfs-battery.log`). W=1 build of `max17042_battery.o` has no
warnings; `dt-validate` of `gs201-cheetah.dtb` (dtschema 2026.9) reports only the existing
`soc_id` and framebuffer `post-init-providers`; `dt-doc-validate` of the binding is clean.

### Expected registers after the load

Read with `i2cget -f -y 0 0x36 <reg> w` (the driver owns the address, so
`-f`; reads are harmless) or `cat /sys/kernel/debug/regmap/0-0036/registers`.

| Reg | Name | Before (B1) | Right after the load | Notes |
|---|---|---|---|---|
| 0x00 | Status | 0x0082 | bit 1 (POR) clear | other bits are alerts |
| 0x18 | DesignCap | 0x0bb8 (3000) | **0x09c5** | fixed |
| 0x3c | TaskPeriod | 0x1680 | **0x2d00** | fixed; doubles the LSB |
| 0x23 | FullCapNom | ? | 0x09c5 | learns afterwards |
| 0x35 | FullCapRep | ? | 0x09c5 ± 25 | learns; stock had 0x08f1 (4578 mAh) |
| 0x10 | FullCap | ~0x0b52 (2898) | about 0x09c5 | what `charge_full` reads |
| 0x1d | Config | ? | **0x4217** | TEx (bit 8) clear |
| 0xbb | Config2 | ? | 0x0090 | LdMdl (bit 5) clear |
| 0x2c / 0x2d | TGain / TOff | ? | **0xed51 / 0x1eba** | fixed |
| 0xb9 | Curve | ? | 0x0014 | fixed |
| 0x28 | LearnCfg | ? | 0x260e | the gauge changes the learn stage; stock read 0x247e |
| 0x2a / 0x29 | RelaxCfg / FilterCfg | ? | 0x143b / 0xc613 | fixed |
| 0x38 / 0x39 | RComp0 / TempCo | ? | 0x0770 / 0x2202 | learn; stock read 0x0965 / 0x2602 |
| 0x02 | TAlrtTh | ? | unchanged (0x7f80 after POR) | we don't write a version |
| 0x08 | Temp | 0x1600 (22.0 °C) | room/body temperature, moving | LSB 1/256 °C |

There is no ModelCfg (0xdb) on the m5 gauge; Config2.LdMdl is its
counterpart.

### Runbook (phone in Arch over USB; each step has its rollback)

```sh
export KERNEL_OUT=$HOME/android/mainline/out-battery
# B1b.0  read-only dump, current kernel. Keep the output.
tools/phone-ssh 'for r in 00 18 3c 23 35 10 1d bb 2c 2d b9 28 2a 29 38 39 02 08 27 17 3d; do
  printf "%s=%s\n" $r $(i2cget -f -y 0 0x36 0x$r w); done'
tools/phone-ssh 'grep . /sys/class/power_supply/max170xx_battery/{capacity,charge_full,charge_full_design,temp,voltage_now,current_now}'
#   gate: 0x00 has bit 1 set (POR). If it does NOT (Android ran since B1 and
#   loaded its own model), check 0x18=0x09c5 and 0x3c=0x2d00: then the gauge
#   already has the right model and the new kernel will leave it alone. Skip to B1b.3.
# B1b.1  new kernel + DTB (slot B), modules first
bin/omamobile modules-push
bin/omamobile push          # reboots into slot B
# B1b.2  the load happens at probe (max17042_battery autoloads). Watch for:
tools/phone-ssh 'dmesg | grep -i -E "max17042|max170xx|battery model"'
#   pass: "battery model loaded (DesignCap 0x9c5, TaskPeriod 0x2d00)", no
#         "model load failed", no "FullCapRep differs"
# B1b.3  the register dump again (same command as B1b.0): compare with the table above
# B1b.4  sysfs
tools/phone-ssh 'grep . /sys/class/power_supply/max170xx_battery/{capacity,charge_full,charge_full_design,temp,voltage_now,current_now,cycle_count}'
#   pass: charge_full_design 5002000; charge_full about 5000000 (it learns down
#         over full cycles; stock had learned 4578 mAh); temp 200-400 (deci-°C)
#         and it moves (hold the phone, run a CPU load: it rises within minutes);
#         capacity close to before (it may jump a few %, re-estimated from voltage);
#         current_now sign still flips with the cable.
# B1b.5  persistence: reboot into Linux again and repeat B1b.0
#   expect POR clear and the same model registers (no reload). If POR is set
#   on every boot, something resets the gauge between boots: write it down,
#   the loader then simply runs each boot (~1 s).
```

Forcing a reload (only if needed, e.g. to test the loader again): the gauge
reloads only after a POR. `i2cset -f -y 0 0x36 0x60 0x000f w` is the m5
hardware reset (Google's `max1720x_full_reset()`, `MAX_M5_COMMAND_HARDWARE_RESET`),
then `modprobe -r max17042_battery; modprobe max17042_battery`. It throws away
everything the gauge has learned (Cycles, FullCapNom, RComp0).

**Rollback.** The gauge has no NVM, so nothing we write survives a power
loss, and every change can be undone in software:

1. Bad readings after the load: `i2cset -f -y 0 0x36 0x60 0x000f w`
   (hardware reset: back to the default EZ model, POR set), then boot the
   previous kernel/DTB (`bin/omamobile push` from `out-wifi`, or let ABL fall
   back to slot A). With the old DTB, the driver writes nothing again.
2. Or boot stock Android in slot A: it reloads its own model (below).
3. A loader failure is already safe: POR stays set and the driver reports
   from the default model, as in B1.

### Dual boot: what stock Android does with our gauge

Google's driver checks the gauge at every probe (`max1720x_init_max_m5()`,
`G/google-modules/bms/max1720x_battery.c:5462-5530`): if the model version in
TAlrtTh[15:8] differs from the DT's (`max_m5_fg_model_check_version()`), it
issues a hardware reset and reloads its model (`"FG Version Changed, Reset,
Will Reload"`). It also reloads whenever it sees POR (`max1720x_check_por()`,
`:2525`). Our loader leaves TAlrtTh at its POR value (version 0x7f, not 1), so
**Android always replaces our load with its own**, then handles its saved
learned state (GMSR) as it does after any reset. The other way round, Android's load clears POR and sets
TaskPeriod 0x2d00, so the next Linux boot reads it correctly and does not
reload. Not writing the version is deliberate: on this gauge TAlrtTh[15:8] is
also the over-temperature alert threshold (1 °C for version 1), and upstream
enables the alert pin.

### Not in this step

- Battery ID and the ID-3 model: needs the battery ID in Linux.
- Charging (B3/B4). Stock's top CV limit is 4.45 V (`google,fv-max-uv`,
  `R/live.dts:18205`); upstream's charger programs 4.3 V unless its own power
  supply has battery info. Read the float voltage ABL leaves before B3.
- **USB data switch (separate gate, B4-adjacent).** Google's TCPC driver
  closes the MAX77759's USB2 data switch on attach and opens it on detach
  (`enable_data_path_locked()`, `GS/drivers/usb/typec/tcpm/google/tcpci_max77759.c:1117-1215`).
  Nothing in our Linux closes it again, a likely cause of our "USB doesn't
  reconnect after unplugging" note. The switch is
  TCPC (0x25) vendor register **0x93 `USBSW_CTRL`**, 0x09 = connected
  (Google `tcpci_max77759_vendor_reg.h:94-95`). Upstream `tcpci_maxim_core.c:24-26,302`
  already writes it from TCPM, so B4 should fix it for good. Gated test, only
  with a non-USB console (Wi-Fi SSH or the on-screen terminal), since USB is
  the link that breaks: read `i2cget -y 0 0x25 0x93` while connected (write it
  down), unplug and replug, read again (0x00 would confirm the report), then
  `i2cset -y 0 0x25 0x93 0x09` and check the host enumerates the gadget.
  Rollback: replug or reboot.

---

## 7. PCIe for Wi-Fi: W0b status (2026-10-11, offline; nothing was run on the phone)

> **Historical.** Superseded by sections 8 and 9 (W1-W4 on the phone).

Kernel branch `omamobile-pcie` in `/home/raven/android/mainline/wt-pcie`
(on top of the BCM4389 and MAX77759 commits), built into
`~/android/mainline/out-pcie`. Path abbreviations as at the top, plus
`P/` = `wt-pcie` and `GD/` = `GS/drivers/pci/controller/dwc`.

### 7.1 What was built

| Commit | What |
|---|---|
| `c66efda39` dt-bindings: phy: add Google gs201 PCIe PHY | `google,gs201-pcie-phy.yaml` |
| `cda2eddb1` phy: samsung: add Google gs201 PCIe PHY driver | `P/drivers/phy/samsung/phy-gs201-pcie.c`, `CONFIG_PHY_GS201_PCIE` (m) |
| `f6e5443d8` dt-bindings: PCI: add Google gs201 PCIe host controller | `google,gs201-pcie.yaml` |
| `65eb5647f` PCI: dwc: add Google gs201 PCIe host controller driver | `P/drivers/pci/controller/dwc/pcie-gs201.c`, `CONFIG_PCIE_GS201` (m) |
| `f08655559` dt-bindings: net: wireless: brcm,bcm4329-fmac: allow a restricted DMA pool | `memory-region` on the Wi-Fi node |
| `3f6c342fe` arm64: dts: exynos: google: gs201: add HSI2 pinctrl and PCIe GEN4A_1 | `pinctrl_hsi2` (enabled), `pcie_1` + `pcie_1_phy` (**disabled**) |
| `c2b4f9d3d` arm64: dts: exynos: google: gs201-cheetah: wire up the BCM4389 Wi-Fi | WL_REG_ON regulator, root port + `wifi@0,0`, pins, `wifi_dma_pool` (**disabled**) |

omamobile repo: `kernel/configs/omamobile.config` (`PCIE_GS201=m`,
`PHY_GS201_PCIE=m`, `PCI_PWRCTRL_GENERIC=y` (built in anyway: the arm64
defconfig's `PCIE_QCOM` selects it), `DMA_RESTRICTED_POOL=y`),
`device/cheetah/overlays/wifi-pcie-test.dtso` and `wifi-dma-pool-test.dtso`
(the explicit enable steps), and `packages/omamobile-device-cheetah/vendor/modprobe.d/omamobile-wifi.conf`
(blacklists `pcie_gs201` and `brcmfmac`).

Checks: `bin/omamobile kernel`, `modules` and `images` exit 0
(`logs/kernel-pcie.log`, `modules-pcie.log`, `images-pcie.log`). Both new
drivers build with `W=1` and no warnings, as does the DTB (the only dtc
warning is the existing `/chosen/framebuffer`). `dt_binding_check` and
yamllint pass for the three bindings. `dt-validate` (dtschema 2026.9) of the
default DTB **and** of the DTB with both test overlays applied (`pcie_1`,
the PHY and the pool all enabled) reports only the existing `soc_id`.

### 7.2 Hardware description (and what changed from the 1.7 sketch)

- **`pinctrl_hsi2`** `pinctrl@14440000`, alias `pinctrl7` (the 8th entry of
  `gs201_pin_ctrl[]`, `P/drivers/pinctrl/samsung/pinctrl-exynos-arm64.c`),
  GIC SPI 421, banks `gph2`/`gph4`. Enabled by default: it only registers two
  gpiochips. The UFS pins are on the separate HSI2UFS controller and are not
  touched.
- **`pcie_1`** `pcie@14520000`: ELBI `0x14520000/0x1400`, DBI
  `0x14800000/0x301000` (the DWC core finds the unrolled iATU at +0x300000 by
  itself), config `0x60ffe000/0x2000`, I/A `0x14500000/0x1000`; MEM window
  `0x60000000/0xff0000`; SPI 428; `num-lanes = 1`, `max-link-speed = 2`;
  `dma-coherent` with `samsung,sysreg = <&sysreg_hsi2 0x730>`. INTx goes
  through a `legacy-interrupt-controller` child. `soc@0` now maps up to
  `0x80000000` so the window is reachable.
- **`pcie_1_phy`** `phy@14550000`: PMA `0x14550000/0x2000`, PCS
  `0x14540000/0x1000`, `rst` = ELBI `+0x1400/0x10` (the three PHY reset
  registers; the controller's ELBI mapping stops at 0x1400 so the two don't
  overlap), UDBG `0x14560000/0xd000`, `samsung,pmu-syscon =
  <&pmu_system_controller 0x3ec4>`.
- **cheetah**: `wlan_pwr` = `regulator-fixed` on `gph2-4` (WL_REG_ON),
  `startup-delay-us = 200000`; root port `pcie@0,0` (`pciclass,0604`) with
  `vpcie3v3-supply = <&wlan_pwr>`; `wifi@0,0` = `pci14e4,4441`,
  `brcm,board-type = "google,gs201-cheetah"`, host-wake `gpa6-1` level-high
  (`interrupts-extended`), `memory-region = <&wifi_dma_pool>`; pinctrl for
  CLKREQ#, PERST#, dev-wake (`gph2-5`, input pull-down) and host-wake
  (EINT, pull-down) as in `G/devices/google/gs201/dts/gs201-cloudripper-wlan.dtsi:13-55`.
- **`wifi_dma_pool`**: `restricted-dma-pool`, 16 MiB, 2 MiB aligned, dynamic
  placement, `status = "disabled"`. Disabled reserved-memory nodes are not
  reserved at all, and `of_dma_set_restricted_buffer()` skips an unavailable
  pool (`P/drivers/of/device.c:51-58`), so it costs nothing until enabled.

### 7.3 Design choices, with evidence

> **Corrected 2026-10-11 (section 8.3).** This section was written against
> Google's `dwc/` driver, which is the Zuma (Pixel 8) one. The driver Google
> builds for gs201 is `dwc-whi/`. The PMU bit 10, UDBG 0xc800 and PMA 0x32c
> writes below are gone; the soft resets, RC device type and the newer CAL
> details were added; and the PHY now leaves isolation before any ELBI access.

- **PHY sequence = Google's CAL, verbatim.** Order in `phy_power_on()`:
  power-down clear (`GD/pcie-exynos-gs201-rc-cal.c:62-88`), then the
  config (`:99-339`): input clock 0xd8, PCS mux glitch fix, the reset pulse
  on ELBI 0x1400/0x1404/0x1408 with 0x1404 released first (`:123-133`),
  common PMA, 38.4 MHz block, per-lane table (`:176-276`), both-lane clock
  block (`:279-288`), PCS RC/L2 settings (`:293-325`), CMN/PORT release
  (`:328-329`), XO select at 0x5d0 (`:333-336`). Then Google's link-up
  extras: PMU 0x3ec4 bit 10, UDBG 0xc800 = 0x421, PMA 0x32c = 0
  (`GD/pcie-exynos-rc.c:3567-3578`). `phy_power_off()` is the all-power-down
  (`cal.c:36-59`). Tables are in `P/drivers/phy/samsung/phy-gs201-pcie.c:75-160`.
  Note Google's per-lane loop adds `i * 0x800` cumulatively (`cal.c:177`);
  that is only equal to a lane stride for one or two lanes, which is all
  this PHY has.
- **PHY isolation:** `phy_init()` sets PMU 0x3ec4 bit 0 (bypass), as
  `exynos_pcie_phy_isolation(PCIE_PHY_BYPASS)` does (`GD/pcie-exynos-rc.c:393-407`;
  values `GD/pcie-exynos-common.h:52-53`). It goes through the exynos-pmu
  regmap, which uses the secure SMC path; 0x3ec4 (`GS101_PHY_CTRL_PCIE_GEN4_1`)
  is in its writable table (`P/drivers/soc/samsung/gs101-pmu.c`, range ending
  at `GS101_PHY_CTRL_UFS`). Stock never isolates ch1 at runtime
  (`use-phy-isol-en` unset, `GD/pcie-exynos-rc.c:2263-2278`); we isolate
  only in `phy_exit()`.
- **Controller link-up = `exynos_pcie_rc_establish_link()`
  (`GD/pcie-exynos-rc.c:3551-3800`)**, split over the DWC host hooks in
  `P/drivers/pci/controller/dwc/pcie-gs201.c`:
  `host_init` (`:427`): PERST# low, pwrctrl power-on (WL_REG_ON + 200 ms),
  PHY init/power-on, I/A, DBI setup (`:242`: vendor/device 144d:eced,
  GEN3_RELATED_OFF = 0x12000 "EQ off" `rc.c:3581`, aux clock 26 MHz
  `rc.c:3191`, L1 exit latency and completion timeout as `rc.c:3160-3230`),
  ELBI setup (`:217`: 0x3bc exit-L1/NAK, 0x3a0 manual link-down reset,
  0x74 xfer pending, 0x3a8 Q-channel no gating for IP >= 0x889500, 0x474
  NAK, 0x1078 DBI L1 exit disable, history buffer; `rc.c:3594-3660`), IOCC
  (`:201`: DBI 0x8e8 = 0x10101010 and sysreg 0x730 = 3, `rc.c:1974-2028`,
  `rc.h:240-245`), PERST# high and 20 ms (`perst_delay_us` default,
  `rc.c:2083-2085`). `start_link` (`:356`): ELBI 0x54 = 1, poll
  0x2c8 & 0x3f for L0 for 48 ms (`MAX_TIMEOUT` 4800 x 10 us,
  `common.h:20`), up to 3 tries with PERST# low and a PHY redo in between
  (stock does 10, `rc.c:3686-3720`), then clear xfer-pending and enable the
  link-down and completion-timeout interrupts (`rc.c:3780-3798`).
  `link_up` uses stock's window RCVRY_LOCK..L1_IDLE (`rc.c:1775-1788`).
- **I/A sequencer kept, default on**, because the stock cheetah DT turns
  it on (`use-ia = "true"`, `R/live.dts:12134`; "PCIe I/A is ENABLED",
  `R/dmesg.txt:2076`) and Google runs it on every link-up right after the
  PHY config (`rc.c:3071-3086`). The microcode is `rc.c:2945-3068`, in
  `pcie-gs201.c:151`. It needs the ELBI, PMA and I/A physical addresses; the
  PMA one is read from the PHY node. `modprobe pcie_gs201 use_ia=0` skips it
  (an on-phone experiment, 7.5).
- **INTx only, as on stock** (`use-msi = "false"`, `R/live.dts:12131`). On
  stock the GIC line is shared between `exynos-pcie` and `dhdpcie`
  (`R/interrupts.txt:243`) and only the controller acks the ELBI status
  (`rc.c:3290-3305`). Here a chained handler (`pcie-gs201.c:554`) acks
  IRQ0-2 (write-one-to-clear) and dispatches IRQ0 bits 14/16/18/20
  (`rc.h:19-23`) to a 4-line INTx domain; the child chip masks through
  IRQ0_EN (`rc.h:31-35`). A no-op `msi_init` (`:501`) keeps the DWC core
  from chaining its iMSI-RX handler onto the same line; brcmfmac's
  `pci_enable_msi()` fails and it uses INTx.
- **WL_REG_ON through PCI pwrctrl.** 7.3 has `pci_pwrctrl_create_devices()`
  / `power_on_devices()` for DWC glue drivers (used by `pcie-qcom.c`); the
  generic driver binds `pciclass,0604` nodes with a `*-supply`. That gives
  the right order (power, then PERST#) and powers the chip off on unbind.
  The 200 ms is `WIFI_TURNON_DELAY` (`W/dhd.h:3138`; stock: REG_ON at 3.571 s,
  L0 at 3.809 s, `R/dmesg.txt:5171,5424`).
- **Clocks: the x2 controller (`PCIE_003`), not `PCIE_004`.** pcie_1 is
  GEN4A_1 (I/A `PCIE_IA_GEN4A_1` at 0x14500000, `QE_PCIE_GEN4A`,
  `UASC_PCIE_GEN4A_DBI_1`), and Google's base DT gives it `num-lanes = <2>`
  (`G/devices/google/gs201/dts/gs201-pcie.dtsi`), so it is the x2
  controller; cheetah only wires one lane. Stock manages no clocks at all
  (`pcie-clk-num = <0>`), and CMU_HSI2 runs automatic gating
  (`auto_clock_gate`), so enabling these gates is belt and braces. We boot
  with `clk_ignore_unused`, so a wrong pick cannot break W1; it matters only
  once that goes (7.8).
- **Not ported, on purpose:** L1 substates (`rc.c:4264-4590`), the
  suspend/L2 path (`rc.c:3979-4118`), the "ch2" PHY power-down of the unused
  third PHY at 0x131b0000 (`rc.c:3088-3131`, PMU 0x3ecc is outside the PMU
  regmap's writable table), the SysMMU/S2MPU DMA ops (`rc.c:232-360`), and
  `exynos_soc_write(0x15, 0x4000)` (`rc.c:3874`). The last writes a "soc"
  region that the stock DT does not have, so in the source we have it
  cannot run as written; it is an experiment if detection fails (7.5).

### 7.4 Security (unchanged rule, now enforced in three places)

Until gate W4, the BCM4389 can DMA to all of RAM (1.5). Therefore:
`pcie_1`, `pcie_1_phy` and `wifi_dma_pool` are `disabled` in the default
DTB; `pcie_gs201` and `brcmfmac` are blacklisted in
`omamobile-device-cheetah`; enabling is the explicit overlay step below.
**Wi-Fi must not ship enabled until W4** (a restricted-dma-pool that the
HSI2 S2MPU confines the chip to, or S2MPU programming by other means). Run
W1-W3 on a network you trust. Never commit the firmware (2.3) or the MAC
from `/chosen/config`.

### 7.5 W1 runbook: link up (on the phone; each step has its rollback)

From the omamobile repo, phone in Arch over USB, a second terminal running
`tools/phone-ssh dmesg -w`. `devmem` is `tools/devmem.c` (in the initramfs
at `/usr/local/bin/devmem`; copy it to the root if needed).

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-pcie KERNEL_OUT=$HOME/android/mainline/out-pcie
O=$KERNEL_OUT D=$O/arch/arm64/boot/dts/exynos/google/gs201-cheetah.dtb

# W1.0  the blacklist must be on the phone BEFORE any DTB with pcie_1 on
tools/phone-ssh 'grep -H . /usr/lib/modprobe.d/omamobile-wifi.conf'   # pcie_gs201, brcmfmac
#       if missing: reinstall omamobile-device-cheetah (or stream the file to /etc/modprobe.d/)

# W1.1  new kernel, default DTB (pcie_1 off). Only change: HSI2 pinctrl + an idle regulator
bin/omamobile modules-push && bin/omamobile push          # slot B, reboots
tools/phone-ssh 'uname -r; grep -E "gph2|gph4" /sys/kernel/debug/gpio | head -3;
  grep wlan /sys/kernel/debug/regulator/regulator_summary; lsmod | grep -c gs201'
#       pass: USB/SSH, UFS, touch, GPU as before; gph2/gph4 chips; wlan-reg-on 0 users; 0 modules
tools/phone-ssh 'devmem 0x145e0000'    # S2MPU_HSI2 CTRL0: expect 0 (off). UFS shares HSI2, so safe
#       rollback: power-cycle; ABL falls back to slot A after the retries, or push the previous out dir

# W1.2  explicit enable: overlay pcie_1 + PHY into the DTB, then images
cp "$D" "$D.default"
$O/scripts/dtc/dtc -q -I dts -O dtb -o out/wifi-pcie-test.dtbo device/cheetah/overlays/wifi-pcie-test.dtso
$O/scripts/dtc/fdtoverlay -i "$D.default" -o "$D" out/wifi-pcie-test.dtbo
bin/omamobile images && bin/omamobile push
tools/phone-ssh 'ls /sys/bus/platform/devices | grep -E "14520000|14550000"; lsmod | grep gs201'
#       pass: both devices exist; phy_gs201_pcie may be loaded (it only maps registers), pcie_gs201 not
# DO NOT read the controller's registers here (e.g. devmem 0x145202c8): ABL
# leaves the PHY isolated in the PMU, and while it is isolated any ELBI access
# hangs the SoC (no panic, so no auto-reboot; recover by holding Power ~30 s).
# This happened on 2026-10-11 (section 8.1). Never devmem PCIe registers at all;
# the driver logs what is needed.
#       rollback: cp "$D.default" "$D"; bin/omamobile images && bin/omamobile push
#       (bin/omamobile kernel also rebuilds the DTB without the overlay)

# W1.3  SUPERSEDED by section 8 (staged, with tools/wifi-w1-capture). Kept for the record:
tools/phone-ssh 'modprobe phy_gs201_pcie &&
  echo "module pcie_gs201 +p; module phy_gs201_pcie +p" > /sys/kernel/debug/dynamic_debug/control &&
  modprobe pcie_gs201 && sleep 1 && lspci -nn'
#       (the pwrctrl "slot" driver that switches WL_REG_ON is built in: arm64 defconfig)
#       pass: "PCIe Gen.2 x1 link up" (Gen.1 is acceptable for W1, note it),
#             0000:00:00.0 [144d:eced] bridge, 0000:01:00.0 [14e4:4441] network,
#             BAR0 64K and BAR2 4M assigned (stock: R/dmesg.txt:5461-5470)
tools/phone-ssh 'devmem 0x145202c8; grep -i gs201 /proc/interrupts'   # 0x11 = L0; no storm
#       rollback: tools/phone-ssh modprobe -r pcie_gs201   (PERST# low, PHY off, WL_REG_ON low)
#       if the phone hangs: panic=10 reboots on a panic; a bus hang needs Power held ~30 s;
#       then boot the default DTB (W1.2 rollback)
```

**If W1.3 fails**, the driver prints "link training failed (try n), LTSSM
0x.." and, after the last try, the controller's 32-entry LTSSM history.
Read it this way:

| Last LTSSM | Meaning | Next experiment |
|---|---|---|
| 0x00-0x01 Detect | no receiver: the chip is unpowered or held in reset | `grep gph2 /sys/kernel/debug/gpio`: gph2-4 (WL_REG_ON) and gph2-0 (PERST#) must be high during training; regulator_summary shows `wlan-reg-on` enabled. If both are right, suspect the S2MPG13 PCIe rails (LDO3 0.85 V, LDO18 1.8 V; always-on in stock, but we cannot read them without an S2MPG13 driver): boot stock, then warm-reboot into slot B so the rails were last set by Android, and retry |
| 0x02-0x06 Polling/Detect-wait | receiver seen, no bit lock: PHY, refclk or CLKREQ# | `modprobe -r pcie_gs201; modprobe pcie_gs201 use_ia=0`; compare the dyndbg line "PMA 0x3f0 .. 0xfc0 .. PCS 0x188" across tries; check `gph2-1` is in function 2 (CLKREQ#) |
| 0x07-0x10 Config/Recovery | trains but drops | try `max-link-speed = <1>` via a one-line overlay (Gen1) |
| L0 but no 01:00.0 | config TLPs fail | `lspci -vv -s 00:00.0` bus numbers; dmesg for "completion timeout"; iATU lines from the DWC core |

### 7.6 W2 runbook: brcmfmac, firmware, interface, scan

**Superseded by 9.4** for W2.2-W2.3 (the first W2 run failed; section 9 has
the cause and the fixed runbook). W2.1 (firmware to the phone) still applies.

The firmware comes from the user's own factory image, extracted on the
laptop by `tools/extract-vendor-firmware` (2.2), into `out/` (gitignored).
It is never committed or packaged.

```sh
# W2.1  firmware (laptop -> phone)
tools/extract-vendor-firmware -o out/vendor-firmware \
  ~/android/factory/cheetah-cp2a.260705.006/image-cheetah-cp2a.260705.006.zip
tar -C out/vendor-firmware -cf - usr | tools/phone-ssh 'tar -C / -xf -'
tools/phone-ssh 'ls -l /usr/lib/firmware/updates/brcm/ | grep cheetah'   # .bin .txt .clm_blob (+ BT .hcd)
#       rollback: tools/phone-ssh 'rm /usr/lib/firmware/updates/brcm/*google,gs201-cheetah*'

# W2.2  driver (the blacklist only stops autoload; an explicit modprobe works). Link from W1.3 is up.
tools/phone-ssh 'modprobe brcmfmac && sleep 5 && dmesg | grep -i brcmf | tail -20 && iw dev'
#       pass: "using brcm/brcmfmac4389c1-pcie for chip BCM4389/N", firmware 20.101.90,
#             CLM "Google.C10sub6" loaded, wlan0 listed. Write down N.
#       rollback: tools/phone-ssh 'modprobe -r brcmfmac'   (chip keeps its firmware until
#                 'modprobe -r pcie_gs201' drops WL_REG_ON)

# W2.3  scan (no association yet; the MAC is whatever the chip reports, see 1.6)
tools/phone-ssh 'ip link set wlan0 up && iw dev wlan0 scan | grep -E "^BSS|SSID:|signal:" | head -30'
#       pass: nearby networks with sane signal levels; no "brcmf_.*error" or firmware trap in dmesg
#       rollback: 'ip link set wlan0 down; modprobe -r brcmfmac; modprobe -r pcie_gs201'
```

W2 failure signatures and what to change are in 1.6 (IPC version 8/9,
FW-up timeout, CLM name). Interrupt problems show as "brcmf_pcie_..."
timeouts with `grep gs201-pcie-intx /proc/interrupts` not counting: then
INTx is not reaching brcmfmac (check that IRQ0 bit 14 is set in `devmem
0x14520000` while the chip is up).

### 7.7 Before W4: brcmfmac through the restricted pool (optional, safe)

Apply `wifi-dma-pool-test.dtso` on top of `wifi-pcie-test.dtso` (same as
W1.2, second `fdtoverlay` pass) and reboot. **Expect** "Reserved memory:
created restricted DMA pool at 0x..., size 16 MiB" early in dmesg, and W2
working unchanged. This proves brcmfmac runs with all its DMA bounced
through one region, which is the precondition for W4. It does **not**
protect anything yet: the S2MPU still allows everything. Rollback: the
W1.2 DTB.

### 7.8 Open risks and how each gets answered

- **The PHY table is untested.** It is Google's verbatim, but our order
  differs in two small ways: the PMU bit 10 goes before, not after, the I/A
  programming, and the controller's DBI/ELBI setup is done once, not
  repeated on every retry. The history dump in 7.5 tells which stage fails.
- **PCIe rails.** S2MPG13 LDO3/LDO18 are `regulator-always-on` in stock; we
  assume ABL leaves them on. A Detect-only failure with WL_REG_ON and PERST#
  high points here (7.5 table).
- **I/A on or off.** Stock runs it; if it misbehaves without L1.2 it can be
  dropped with `use_ia=0`.
- **Gates 003 vs 004.** Once `clk_ignore_unused` goes, check that the link
  still trains and that `clk_summary` shows the 003 gates enabled.
- **INTx semantics.** The ELBI INTA bit is an assert event, not a level;
  brcmfmac masks the chip's interrupt in its hard IRQ handler and unmasks it
  after the thread, which produces a fresh assert. Same contract as stock,
  but watch for stalls under load at W3.
- **No link-down recovery.** A link-down or completion-timeout is logged
  only. Recovery is `modprobe -r brcmfmac pcie_gs201` and load again.
- **Suspend.** No L2/PME path yet; keep suspend off (it already is).
- **Domain number.** We have one host bridge, so the Wi-Fi chip is
  `0000:01:00.0`, not stock's `0001:01:00.0`.

---

## 8. W1 on the phone: two hangs, the cause, and the staged W1.3 (2026-10-11)

Path abbreviations as above, plus `GW/` =
`GS/drivers/pci/controller/dwc-whi`.

### 8.1 What happened

1. **W1.2** booted fine with `wifi-pcie-test.dtso`: `14520000.pcie` and
   `14550000.phy` were present and `phy_gs201_pcie` autoloaded (its probe only
   maps registers). Then `devmem 0x145202c8` (ELBI LTSSM) **hung the whole
   phone**: no panic, no auto-reboot, recovered with a 30 s Power hold.
2. **W1.3, try 1:** `modprobe pcie_gs201` failed cleanly with -EBUSY ("can't
   request region for resource [mem 0x14520000-0x145213ff]"). The DWC core
   requested "elbi" a second time. Fixed by handing the mapping over
   (`pci->elbi_base = gp->elbi`), folded into the driver commit.
3. **W1.3, try 2:** `modprobe phy_gs201_pcie; modprobe pcie_gs201` **hung the
   whole phone within seconds**. The network went, and there was no panic.
   Nothing reached the disk (the nohup log and the journal were empty), and
   pstore was empty after the Power-hold reset.

Why nothing was logged:

- **The disk could not help.** The root file system is UFS, in the same HSI2
  block. With one CPU stuck in a load that never completes, IPIs and RCU stall
  the rest within seconds.
- **pstore could not help either:**
  - the bootargs carry `quiet`, so the pstore console only got warnings and
    worse;
  - a 30 s Power hold is a cold PMIC reset, so DRAM, and with it ramoops, is
    lost.

### 8.2 Cause, ranked, with evidence

1. **ELBI accessed while the PHY was still isolated (almost certain).**
   - ABL leaves the channel-1 PHY isolated in the PMU (`0x18063ec4` bit 0 =
     0). While it is isolated, even a read of the controller's ELBI registers
     hangs the SoC. Isolation must be released first, through the secure SMC
     path. Copying Google's probe order verbatim hits this.
   - **W1.2:** `devmem 0x145202c8` was an ELBI read with the PHY still
     isolated, which explains hang 1 exactly.
   - **W1.3:** our old probe did the following, all before `phy_init()` (the
     only place that released isolation):
     - wrote ELBI `0x10/0x14/0x18` in `gs201_pcie_init_irq()`;
     - installed the chained IRQ handler, which reads ELBI;
     - wrote ELBI `0x54` (LTSSM off) at the top of `host_init`.

     The first access hung. That explains hang 2.
   - **Google's code agrees:**
     - its gs201 config accessor refuses DBI reads while `phy_control ==
       PCIE_PHY_ISOLATION` (`GW/pcie-exynos-rc.c:1269-1290`);
     - it never isolates ch1 again after probe (`use-phy-isol-con` is not set
       in the stock DT).
2. **We ported the wrong Google driver (certain; a link-training risk, and
   one unknown register write).**
   - Section 7 used `GS/drivers/pci/controller/dwc/`, which is the Zuma
     (Pixel 8) driver. Its `get_resource()` requires a "soc" region that the
     stock cheetah DT does not have.
   - The gs201 build compiles `GS/drivers/pci/controller/dwc-whi/`. That is
     the path of the built `pcie-exynos-gs.ko` under
     `out/bazel/.../gs201_soc/.../dwc-whi/`.
   - **What `dwc-whi` does differently:**
     - **No** PMU `0x3ec4` bit 10 write, **no** UDBG `0xc800 = 0x421` and no
       PMA `0x32c` write. All three are Zuma's. On gs201, UDBG 0xc800 is an
       undocumented register, so writing it was a hang candidate of its own.
     - A soft power reset (ELBI `0x3a4` bit 1), **DEVICE_TYPE = 4 (root
       complex) at ELBI `0x80`**, and a non-sticky reset (bit 3) before the
       DBI setup (`GW/pcie-exynos-rc.c:3142-3173`). Without them the core may
       not even be in RC mode.
     - CAL changes (`GW/pcie-exynos-gs201-rc-cal.c`):
       - PMA `0x404` in power-down and its clear;
       - PMA `0x400` bit 7 (PMA off) at power-down;
       - PCS `0x184` rate switching;
       - ERIO gating bits 4 and 5, not only 4;
       - AFC calibration restart (`0xbf4 = 4`);
       - a reset-value self-check.

       The big PMA tables are identical (checked line by line).
     - PLL, CDR and offset-calibration polls after the config, each bounded
       at 10 ms (`:908-935`, `:3122-3160`).
     - No `XFER_PENDING` writes in the link path.
3. **CMU_HSI2 global automatic clock gating (unproven; kept as an opt-in
   experiment).**
   - Our clk-gs201 writes `CMU_HSI2 CONTROLLER_OPTION` (`0x14400800`) =
     `0xf1000000` at boot (bit 28 = global HWACG, `clk-exynos-arm64.c:104-112`).
   - Google's gs201 probe clears bit 28 for ch1 ("Disable automatic clock
     gating on OSCCLK", `GW/pcie-exynos-rc.c:2673-2716`), and the controller's
     Q-channel by default allows APB/AXI gating in Detect.Quiet (`QCH_SEL`
     bits, `GW/pcie-exynos-rc.h:64-85`).
   - UFS shares this CMU. So it stays off unless stage 2 or 3 still hangs
     (`cmu_acg_off=1`).
4. **Lower-ranked, checked:**
   - The DWC core only issues config cycles to bus 1 when `link_up` is true
     (`dw_pcie_other_conf_map_bus()`).
   - The PMU write goes through the SMC (`tensor_sec_update_bits`). A refusal
     returns an error, not a hang.
   - There are no unbounded polls in our code.
   - The clock "enables" are no-ops on CMU_HSI2's auto gates
     (`samsung_auto_clk_gate_en()` returns 0), so they cannot be the
     difference.

### 8.3 What changed (all offline)

Kernel `omamobile-pcie` in `wt-pcie`, fixups squashed into the existing
commits. The new heads:

| Commit | What |
|---|---|
| `cda2eddb1` | phy: samsung: add Google gs201 PCIe PHY driver |
| `f6e5443d8` | dt-bindings: PCI: add Google gs201 PCIe host controller |
| `65eb5647f` | PCI: dwc: add Google gs201 PCIe host controller driver |
| `3f6c342fe` | arm64: dts: exynos: google: gs201: add HSI2 pinctrl and PCIe GEN4A_1 |

The other commits are unchanged in content.

**PHY driver:**
- `phy_init()` releases the isolation through the PMU regmap (SMC), then
  powers the PHY down. This is Google's probe step, and the first PMA/PCS
  access happens here.
- `phy_power_on()` runs the `dwc-whi` CAL and the lock polls.
- `phy_calibrate()` reports OC after the soft reset.
- `phy_exit()` **no longer re-isolates**, as stock.

**Controller driver:**
- The new order follows `GW/`, with the isolation release moved first:
  1. isolation off and PHY power-down;
  2. the first ELBI access (interrupt enables off, LTSSM off);
  3. the chained IRQ handler;
  4. WL_REG_ON and 200 ms;
  5. PHY config and I/A;
  6. soft power reset, RC device type, non-sticky reset;
  7. PERST# and 20 ms;
  8. ELBI setup, DBI setup and IOCC;
  9. DWC root-port setup, then LTSSM.
- A failed try redoes the PHY, controller and `dw_pcie_setup_rc()`, as stock.
- The DT has a new optional `samsung,cmu = <&cmu_hsi2>` (binding updated). It
  is used only for the CMU option read, the dump and `cmu_acg_off`.

**Bring-up aids (module parameters):**

| Module | Parameter | Meaning |
|---|---|---|
| `pcie_gs201` | `stop_after=N` (0444) | end probe after stage N, undo, do not bind (returns -ENODEV, silent) |
| both | `trace=1` (0644) | log each hardware step *before* doing it: "about to read PMA 0x400", "enable clk ...", ... |
| both | `trace_delay_ms=20` (0644) | sleep after each trace line, so `/dev/kmsg` readers get it before a possible hang |
| `pcie_gs201` | `use_ia=0` | skip the I/A sequencer |
| `pcie_gs201` | `cmu_acg_off=1` | clear CMU_HSI2 global automatic clock gating in stage 1 (Google's step) |
| `phy_gs201_pcie` | `check_tcxo=1` | read PMU `0x3c10` (TCXO_BUF_CTRL; stock reads it raw on every boot) and set bits 2/3/10 via SMC if missing |

Stages:

| N | Stage | Hardware touched |
|---|---|---|
| 0 | resources | none (mappings, GPIO PERST# held low) |
| 1 | clocks | clock refs (no-ops on HSI2); with `samsung,cmu`: one CMU_HSI2 read (option), with trace a dump of the HSI2 gate and PCIe Q-channel registers; `cmu_acg_off=1` writes the option |
| 2 | PHY isolation off, first register access | PMU 0x3ec4 bit 0 via SMC; PHY power-down (first PMA/PCS writes and reads); ELBI `0x10-0x18`, `0x54` writes; ELBI `0x3a8/0x3a4/0x80` reads |
| 3 | PHY configuration | power-down clear, PMA reset self-check, CAL tables, ELBI `+0x1400` PHY resets, lock polls; I/A program and start |
| 4 | controller setup | soft resets, DEVICE_TYPE, first DBI reads (ID, `0x8f8` version), DBI and ELBI setup, IOCC; ELBI `0x2e8/0x2c8` read (the register that hung W1.2) |
| 5 | link (default) | WL_REG_ON, PERST#, DWC iATU/root port, LTSSM, enumeration |

With `stop_after < 5` WL_REG_ON is never raised, PERST# stays low and no host
bridge is registered. Each staged run ends with the PHY powered down (not
isolated) and the clock refs dropped, so stages can be re-run on the same
boot.

**`tools/wifi-w1-capture`** (MIT), run from the laptop:
1. Checks the phone: both devices present, the blacklist, and whether
   `pcie_gs201` is loaded (if so, unloads it).
2. Sets `dmesg -n 8`, so the pstore console keeps info lines too.
3. Sets the PHY module's parameters through sysfs.
4. Starts `cat /dev/kmsg` over a first SSH connection into
   `logs/wifi-w1-<time>-s<N>.log`, with the laptop's receive time on each
   line.
5. Writes a start marker to `/dev/kmsg`.
6. Optionally (`--watchdog`) arms `/dev/watchdog0` with a 2 s feeder on the
   phone. A full hang then becomes a warm watchdog reset in about 15 s, with
   DRAM and ramoops kept, instead of a cold Power hold.
7. Runs `modprobe pcie_gs201 trace=1 stop_after=N ...` over a second
   connection.
8. Waits for an end marker. If the phone still answers, it stops the watchdog,
   checks that UFS still reads, and unloads (stage < 5) or runs `lspci`
   (stage 5). If the phone is gone, it prints the last lines that arrived.
9. `tools/wifi-w1-capture --pstore` saves `/sys/fs/pstore/*` after a watchdog
   reset.

Builds: `bin/omamobile kernel`, `modules` and `images` with
`KERNEL_DIR=wt-pcie KERNEL_OUT=out-pcie` exit 0 (`logs/kernel-pcie.log`,
`modules-pcie.log`, `images-pcie.log`). Both drivers are clean with `W=1`.
`out-pcie`'s DTB **has the test overlay applied** (`pcie_1` and the PHY
okay, `samsung,cmu` present); the plain one is
`gs201-cheetah.dtb.default`. `dt_binding_check` was not re-run (dtschema is
not installed in the container or on the host); the YAML parses.

### 8.4 W1.3 runbook (staged)

Prerequisites:
- The W1.0 blacklist is on the phone.
- The phone boots the `out-pcie` kernel with the test DTB:
  `bin/omamobile modules-push && bin/omamobile push` with
  `KERNEL_DIR=$HOME/android/mainline/wt-pcie
  KERNEL_OUT=$HOME/android/mainline/out-pcie`. The new modules must be on the
  phone, because the old `pcie_gs201.ko` is the one that hangs.
- **Never use devmem on any PCIe, PHY or PMU register.**

Run each stage once, in order, on the same boot. Stop at the first stage that
does not pass.

```sh
tools/wifi-w1-capture 0              # driver loads, parses DT, no hardware: "stopped after stage 0"
tools/wifi-w1-capture 1              # clocks + CMU_HSI2 option read (+ gate dump)
tools/wifi-w1-capture --watchdog 2   # THE decisive step: isolation release, first PHY and ELBI access
tools/wifi-w1-capture --watchdog 3   # PHY config: look at "PLL lock 1"
tools/wifi-w1-capture --watchdog 4   # soft resets, RC mode, first DBI access
tools/wifi-w1-capture --watchdog 5   # WL_REG_ON, PERST#, training, lspci
```

What each pass looks like (lines from the summary, `14520000.pcie:` /
`14550000.phy:` prefixes omitted):

- **0:** `stage 0/5: resources (stop_after=0, trace=1, use_ia=1,
  cmu_acg_off=0)`, then `stopped after stage 0 as asked`.
- **1:**
  - `enable clk gout_hsi2_pcie_gen4_1_pcie_003_...` lines;
  - `CMU_HSI2 option 0x........ (automatic gating on|off)`, plus 8 + 2 dump
    lines. Write down the option value and the dump: they record ABL's gate
    state, which we never had;
  - `stage 1 done`.
- **2:**
  - `trace: about to set PMU 0x3ec4 bit 0 (PHY isolation off, SMC)`;
  - `about to read PMA 0x400 (first PMA read)`, then `about to read PCS 0x184`;
  - `PHY out of isolation and powered down`;
  - `about to write ELBI 0x010-0x018 (first ELBI access ...)`;
  - `ELBI QCH_SEL 0x... SOFT_RESET 0x... DEVICE_TYPE 0x...`;
  - `stage 2 done`.

  The UFS check prints a `dd` line.
- **3:**
  - `PLL lock 1, CDR lock 0|1, OC done 1 (...)`. CDR may be 0: there is no
    partner, WL_REG_ON is off below stage 5;
  - possibly `PMA 0x.. after reset: ... (expected ...)` lines (Google's
    self-check; note them, not fatal);
  - `about to program the I/A sequencer`, then `stage 3 done`.
- **4:**
  - `DBI ID 0x........`: a Samsung or Synopsys ID, **not 0xffffffff**;
  - `DWC version 0x........`;
  - possibly `OC not done after soft power reset: ...`;
  - `D-state 0, LTSSM 0x0`, then `stage 4 done`.
- **5:**
  - `about to power the endpoint (WL_REG_ON, gph2-4, 200 ms)`;
  - `link try 1: ...`, then `link up on try 1`;
  - the DWC core's `PCIe Gen.2 x1 link up` line;
  - `lspci -nn` shows `00:00.0 [144d:eced]` and `01:00.0 [14e4:4441]`.

  Then continue with W2 (7.6).

**Reading a hang.**
- The log's last `trace: about to ...` line names the access that never
  completed. Lines are ordered and carry the laptop's receive time, so a gap
  of more than about 1 s before the end means the phone died during that
  step.
- With `--watchdog` the phone resets itself in about 15 s. Then run
  `tools/wifi-w1-capture --pstore`; the `console-ramoops-0` file should end
  at the same line.
- What to do next, by the last line:

| Last line | Meaning | Next try (one more reset at most) |
|---|---|---|
| `about to set PMU 0x3ec4 bit 0` (stage 2) | the SMC itself stalled, which is unexpected | report; check the SMC path with a known register (reboot-mode's 0x810 works) |
| `PMU write failed: -22` (stage 2, no hang) | EL3 refused the atomic set-bits form | add a TENSOR_PMUREG_RMW path for this register (Google uses `rmw_priv_reg`), no phone risk |
| `about to read PMA 0x400` or `PCS 0x184` (stage 2) | PHY APB clock gated | rerun stage 2 with `--cmu-acg-off` |
| `about to write/read ELBI ...` (stage 2) | isolation release did not take, or the APB clock is gated | `--cmu-acg-off`; if it still hangs, compare the gate dump from stage 1 with stock |
| `about to poll PMA ...` (stage 3) | should not hang (pure reads after successful ones) | `--ia 0`, `--tcxo` |
| `about to program the I/A sequencer` (stage 3) | I/A misbehaves | `--ia 0` |
| `about to read DBI 0x000 ...` (stage 4) | the DWC core is not clocked (no pipe/core clock) | `--cmu-acg-off`; check `PLL lock 1` in stage 3 |
| `link try N ...` (stage 5) | hang during training (should be impossible) | `--ia 0` |

**Rollback:**
- A hang: a Power hold of about 30 s (or the watchdog). ABL then boots
  slot B again, or slot A after its retries.
- To return to the main kernel: unset `KERNEL_DIR`/`KERNEL_OUT`, then run
  `bin/omamobile modules-push && bin/omamobile push`. That pushes
  `~/android/mainline/out`, which has no PCIe at all.
- To keep `out-pcie` but turn PCIe off: `cp "$D.default" "$D"`, then
  `bin/omamobile images && bin/omamobile push`.

### 8.5 Still open

- **L1.2 teardown.** A link torn down while in L1.2 can make the next
  bring-up hang in training: leave L1, send PME_Turn_Off and reach L2 before
  PERST#. We have no L1 substates yet, so this cannot bite at W1. It
  matters before ASPM/L1SS or runtime suspend.
- **brcmfmac for this chip likely needs more than 1.6 lists**, on top of the
  Pixel 6 work:
  - H2D sequence numbers (otherwise an "h2d livelock" trap);
  - ring indices in host memory;
  - XOR-checksum D2H sync;
  - the v1 join parameters;
  - the host builds the 802.3/LLC header;
  - packet ID 0 never used;
  - reused ring slots cleared;
  - **all four save/restore power domains requested through ChipCommon
    `powerctl` after every reset** (otherwise the backplane faults from a
    cold boot).

  Our firmware is 20.101.90. Plan W2 with this list. **Done for W2 in
  section 9** (sequence numbers, packet ID 0, slot clearing, power domains;
  host-memory indices were already in brcmfmac); the rest is for W3.
- **S2MPU (W4).** Reportedly, touching any
  S2MPU register other than CTRL0 reset the SoC, and S2MPUs come back with
  CTRL0 = 1 after a power-domain cycle. Reading CTRL0 (W1.1) stays fine.
  Revisit W4 (EL1 S2MPU programming) with this in mind.
- **pstore and `quiet`.** The capture tool raises the console level at run
  time. To keep boot-time messages in pstore as well, `quiet` would have to
  leave the DT bootargs. Not done, because it is a user-visible boot change.

---

## 9. W2 on the phone: "Invalid shared RAM address 0xffffffff", the cause and the fixes (2026-10-12)

`L` = upstream brcmfmac as of `4487813cb` (before the fixes),
`W` = Google's `private/google-modules/wlan/bcm4389/`, `R` = the stock
captures. Log: `logs/w2-brcmfmac-20261012-0016.log` (W1 link log:
`logs/wifi-w1-20261012-001501-s5.log`).

### 9.1 What happened

W1 passed: Gen.2 x1 on try 1, `01:00.0 [14e4:4441]` rev 03, BAR0 64K,
BAR2 4M, and brcmfmac took the restricted DMA pool. Then `modprobe
brcmfmac`:

```
brcmfmac: brcmf_fw_alloc_request: using brcm/brcmfmac4389c1-pcie for chip BCM4389/3
brcmfmac 0000:01:00.0: brcmf_pcie_download_fw_nvram: Invalid shared RAM address 0xffffffff
brcmfmac 0000:01:00.0: brcmf_pcie_setup: Dongle setup failed
ieee80211 phy0: brcmf_fw_crashed: Firmware has halted or crashed
WARNING: kernel/workqueue.c:4409 at __flush_work+0x27c/0x2a4
 ... brcmf_bus_cancel_reset_work <- brcmf_pcie_remove <- brcmf_pcie_setup
```

The failure line came 390 ms after the firmware request, download
included, so on one of the first 50 ms polls: the word at what brcmfmac
took for the top of RAM changed to 0xffffffff once the ARM ran. The phone rebooted about
5 minutes later; the log stream (still running) ends with `sd ...:
Synchronizing SCSI cache`, an orderly kernel restart, not a watchdog bite
(a bite prints nothing). The capture tool's disarm was fragile anyway and
its log stream leaked; both are fixed (9.3).

### 9.2 Cause: brcmfmac sized the RAM at 256 KiB instead of 2688 KiB

| | brcmfmac (`L`) | Broadcom/Google (`W`, `R`) |
|---|---|---|
| SYSMEM coreinfo decode | SOCRAM layout: banks = bits 7:4 (`L/.../chip.c:158-160,669`), banks counted from index 0 (`chip.c:672`) | RAM banks = bits 4:0, ROM banks = bits 9:5 (bits 23:16 / 31:24 from core rev 12), RAM banks start after the ROM banks (`W/siutils.c:7045-7057`, `W/include/sbsysmem.h:115-123`) |
| BCM4389 coreinfo 0x115 | 1 bank, and it is ROM bank 0 | 8 ROM + 21 RAM banks of 128 KiB (`R/dmesg.txt:5468-5490`) |
| RAM | 0x200000 + **0x40000** | 0x200000 + **0x2a0000** = 2752512 (`R/dmesg.txt:5490`; base `W/dhd_pcie.c:2336-2349`, `W/include/sbchipc.h:4245`) |

Evidence from our own failure: the WARNING's register dump (callee-saved
registers left by the inlined download code) holds `x24 = 0xe8b4174b`, the
NVRAM length token (stock prints the same token, `R/dmesg.txt:6986`), and
`x26 = 0x23a2d0` = 0x240000 - 23856, the NVRAM address for a 256 KiB RAM.
So brcmfmac wrote the NVRAM, the random seed and the "top of RAM"
handshake word (`L/.../pcie.c:1722-1744`) at 0x23a1c8-0x23ffff, inside the
1.7 MB firmware image it had just copied to 0x200000 (code and data run to
0x3ae944, `_end` in `fw_bcmdhd.map`). The firmware started on corrupted code and died, and the
read of 0x23fffc returned 0xffffffff (`L/.../pcie.c:1779`). Nothing in the
PCIe link or the DMA pool was at fault.

Two more defects sit right behind it, and would have failed the next try:

- **The RAM does not fit the BAR.** With the right size, RAM ends at
  0x49ffff, but brcmfmac maps BAR2 (4 MiB) 1:1 from backplane address 0
  (`L/.../pcie.c:568-578,1818`), so the NVRAM, the seed and the handshake
  word would land past its ioremap(). bcmdhd moves the BAR1 window (PCI
  config 0x84) for every access (`W/dhd_pcie.c:6143-6260,2458`,
  `W/include/pcicfg.h:489`) and resets it to 0 before the download
  (`W/dhd_pcie.c:10105`); stock writes the seed at 0x49a248
  (`R/dmesg.txt:6987`).
- **Power domains.** bcmdhd treats the 4389 as a multi-backplane chip
  (`W/include/siutils.h:963-969`): it requests all four save/restore
  domains (PCIe, ARM/backplane, MAC aux, MAC main) in the PCIe core's
  `powerctl` (BAR0 + 0x2000 + 0x1e8, request bits 11:8, status 19:16)
  before a reset (`W/dhd_pcie.c:832-857,2778`, PCIe core rev 72 is in
  `W/dhd_pcie.h:153-155`, `R/dmesg.txt:6988`), and asserts the ARM domain
  in the DAR copy (0xa0c) because "ARM fails to boot" from cold without it
  (`W/dhd_pcie.c:735-748,2505-2513`). It also sets the CA7's BAR
  coherent-access bits, config 0x88 bits 9:8 (`W/dhd_pcie.c:2219-2223`).
  brcmfmac does none of this. A warm chip can hide it.

And three protocol details, needed once the firmware runs:

- **H2D sequence numbers.** bcmdhd puts `seqnum % 253` (seqnum from 254) in
  the `epoch` byte of every message on the control and rxpost submit rings
  (`W/include/bcmmsgbuf.h:38-39`, `W/dhd_msgbuf.c:1816-1824,5900,10883`);
  brcmfmac leaves it 0. The 20.101.90 image contains the trap string
  "h2d livelock error".
- **Packet ID 0** is "invalid" to bcmdhd and never used
  (`W/dhd_msgbuf.c:2278,2760,2901`); brcmfmac hands it out after a wrap.
- **Stale slot bytes.** brcmfmac fills ioctl and flow-ring create/delete
  messages field by field on reused slots; with the epoch byte now
  meaningful, the slots are cleared first (buffer posts already were).

The WARNING is a plain brcmfmac bug: `drvr->bus_reset` is only
`INIT_WORK`ed in `brcmf_bus_started()` (`L/.../core.c:1303`), but the
remove path that the failed setup triggers cancels it unconditionally
(`core.c:1190`).

### 9.3 What changed (all offline)

Kernel, branch `omamobile-pcie` in `wt-pcie`, one upstream-style commit each:

| Commit | Change |
|---|---|
| `eaa318f86` wifi: brcmfmac: chip: size the BCM4389 SYSMEM from its RAM banks | bcmdhd's coreinfo decode for the 4389 (both layouts), ROM banks skipped; logs `SYSMEM rev N coreinfo 0x...: R ROM, N RAM banks` at debug INFO. Other SYSMEM chips unchanged |
| `f43633f62` wifi: brcmfmac: pcie: move the BAR1 window for RAM beyond the BAR | every TCM access goes through one helper; when RAM ends beyond the BAR the window (config 0x84) moves under a spinlock; block copies split at window edges and into 4 KiB pieces; window reset before download and after reset. No change for chips whose RAM fits |
| `dc88c3c73` wifi: brcmfmac: pcie: request the BCM4389 power domains after reset | for 14e4:4441 only: request all four domains (+ DAR ARM domain) once the BARs are mapped, before and after the watchdog reset; set the BAR coherent bits. The requests stay on while bound (idle power, to release later) |
| `a8d467176` wifi: brcmfmac: msgbuf: put sequence numbers in H2D control messages | epoch on control + rxpost submit messages, set when a message is final; ioctl and flow-ring create/delete slots cleared first |
| `2766d0ecf` wifi: brcmfmac: msgbuf: never use packet ID 0 | |
| `2733238b7` wifi: brcmfmac: don't cancel the bus reset work before it exists | the WARNING |

All build clean with `W=1`. Config: `CONFIG_BRCMDBG=y` (brcmfmac's debug
messages, off unless `debug=` is set). Builds: `logs/kernel-w2fix.log`,
`modules-w2fix.log`, `images-w2fix.log` (out-pcie, both overlays re-applied,
plain DTB in `.default`).

`tools/wifi-w1-capture`:

- the watchdog feeder runs in its own session (`setsid`), writes the magic
  'V' and closes `/dev/watchdog0` on TERM/INT/HUP at once (no waiting for
  `sleep`), and disarms itself after `--wait` + 120 s at the latest;
- the end of the run, Ctrl-C, or any exit disarms: stop the feeder, wait
  until it is gone, then `printf V > /dev/watchdog0` (open + magic close),
  and check dmesg for "watchdog did not stop". `--disarm` does only that;
- the log stream's ssh is now killed with the rest of the pipeline (it used
  to outlive the run);
- `--brcmfmac` (stage 5 only): load brcmfmac with `debug=0x80004` (PCIe +
  INFO) on the fresh link, under the same watchdog and capture, and wait for
  `Firmware: BCM4389` or a failure line.

Not done here (W3 or later): D2H XOR-checksum verification (the firmware
uses it, `R/dmesg.txt:7120`; brcmfmac relies on PCIe write ordering, fine
with DMA'd indices), the v1 join parameters and the host-built 802.3/LLC TX
header (association and data, not scan), in-band device wake, releasing
the power requests once the firmware runs, and the ABL MAC address (1.6).

### 9.4 W2 runbook (on the phone; each step has its rollback)

From the omamobile repo, phone in Arch over USB.

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-pcie KERNEL_OUT=$HOME/android/mainline/out-pcie

# W2.0  new kernel + modules (out-pcie, DTB already has both test overlays)
bin/omamobile modules-push && bin/omamobile push          # slot B, reboots
tools/phone-ssh 'uname -r; ls /usr/lib/firmware/updates/brcm/ | grep 4389c1;
  grep -H . /usr/lib/modprobe.d/omamobile-wifi.conf; dmesg | grep "restricted DMA pool"'
#   pass: release 7.3.0-rc6-omamobile-push1-00068-g2733238b74d0; .bin .txt .clm_blob present;
#         blacklist lists pcie_gs201 and brcmfmac; "created restricted DMA pool ... 16 MiB"
#   rollback: unset KERNEL_DIR KERNEL_OUT; bin/omamobile modules-push && bin/omamobile push

# W2.1  link + brcmfmac in one run, watchdog armed, every line on the laptop
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5
#   (the summary prints the brcmf lines; the full log is logs/wifi-w1-<time>-s5.log)
#   rollback: tools/phone-ssh 'modprobe -r brcmfmac; modprobe -r pcie_gs201'
#   if the phone hangs: the watchdog resets it in ~15 s; then tools/wifi-w1-capture --pstore
#   if the run is interrupted: tools/wifi-w1-capture --disarm
```

W2.1 lines, in order (`brcmfmac: ` prefix and `0000:01:00.0` omitted):

| Line | Pass | If not |
|---|---|---|
| W1 lines up to `link up on try 1`, `PCIe Gen.2 x1 link up` | as W1 | W1 regressed: stop, compare with `logs/wifi-w1-20261012-001501-s5.log` |
| `assigned reserved memory node wifi-dma-pool` | present | DTB lost the overlay (9.5 rollback, re-apply) |
| `brcmf_pcie_srpwr_request power domains up, powerctl 0x...` | `value & 0x000f0f00 == 0x000f0f00` (request and status bits for all four; the top nibble is the domain ID) | `power domains not up, powerctl 0x...`: note the value; continue, it may still load. `power control reads 0xffffffff`: the chip is not answering on BAR0: stop |
| `brcmf_chip_sysmem_ramsize SYSMEM rev N coreinfo 0x00000115: 8 ROM, 21 RAM banks` | exactly 8 and 21 | other coreinfo: write it down, stop (decode is wrong for this rev) |
| `brcmf_chip_get_raminfo RAM: base=0x200000 size=2752512 (0x2a0000)` | 2752512 | anything else: stop |
| `brcmf_pcie_tcm_win_setup RAM 0x200000-0x49ffff does not fit the 4096 KiB BAR, moving its window` | present | missing: the window code is off, the NVRAM goes past the BAR: stop |
| `using brcm/brcmfmac4389c1-pcie for chip BCM4389/3` | rev 3 | |
| `Download FW brcm/brcmfmac4389c1-pcie.google,gs201-cheetah.bin`, `Download NVRAM ...txt`, `Download random seed`, `Bring ARM in running state`, `Wait for FW init` | all | no NVRAM line: the .txt is missing |
| `Shared RAM addr: 0x003eabf0` | about 0.6 s after "Wait for FW init"; stock had 0x3eabf0 (`R/dmesg.txt:7100`) | `FW failed to initialize` (5 s): the firmware never came up, look at the console lines (`brcmf_pcie_bus_console_read`) just before; `Invalid shared RAM address 0x...`: write the value down |
| `PCIe protocol version 7` | 5-7 | `Unsupported PCIE version 8/9`: see 1.6 |
| `Using host memory indices`, `max rx buf post ...` | present | "Using TCM indices" also works, just slower |
| `brcmf_c_preinit_dcmds: Firmware: BCM4389/3 wl0: ... version 20.101.90 (wlan=r1098710 c1 release2) FWID 01-3f632e0d` | present | a trap or `h2d livelock error` in the console: the epoch fix is not enough, keep the log |
| `CLM version = Google.C10sub6` | present | `no clm_blob available`: the .clm_blob name is wrong (1.6) |
| no `WARNING`, no `Firmware has halted` | | |

```sh
# W2.2  the interface
tools/phone-ssh 'iw dev; ip link show wlan0; cat /sys/kernel/debug/ieee80211/phy*/revinfo 2>/dev/null'
#   pass: "Interface wlan0", "type managed", a MAC addr; revinfo: "chip: BCM4389/3 (...)",
#         "clmver: Google.C10sub6"
#   rollback: tools/phone-ssh 'modprobe -r brcmfmac'

# W2.3  scan (no association; the MAC is whatever the chip reports, 1.6)
tools/phone-ssh 'ip link set wlan0 up && iw dev wlan0 scan | grep -E "^BSS|SSID:|signal:|freq:" | head -40'
tools/phone-ssh 'dmesg | grep -iE "brcmf.*(error|fail|trap|timeout)|livelock|halted" | tail'
#   pass: nearby networks on 2.4 and 5 GHz (6 GHz may appear), signal -30..-90 dBm;
#         the dmesg grep is empty. Run the scan twice: the second must work too.
#   rollback: tools/phone-ssh 'ip link set wlan0 down; modprobe -r brcmfmac; modprobe -r pcie_gs201'

# W2.4  unload/reload (the remove path and the power requests after reset)
tools/phone-ssh 'modprobe -r brcmfmac && sleep 1 && dmesg | tail -5 | grep -c WARNING;
  modprobe brcmfmac debug=0x80004 && sleep 8 && iw dev | grep -c wlan0'
#   pass: 0 WARNINGs, then 1 (wlan0 back on a warm chip)
#   rollback: as W2.3
```

If W2.1 hangs the phone (no reset after the watchdog either), recover with
a 30 s Power hold, then boot the default DTB (9.5).

### 9.5 Rollback

- **brcmfmac only:** `tools/phone-ssh 'modprobe -r brcmfmac'`. The chip keeps
  running until `modprobe -r pcie_gs201` drops WL_REG_ON.
- **PCIe off, same kernel:** `D=$KERNEL_OUT/arch/arm64/boot/dts/exynos/google/gs201-cheetah.dtb;
  cp "$D.default" "$D"; bin/omamobile images && bin/omamobile push`.
- **Back to the main kernel:** unset `KERNEL_DIR`/`KERNEL_OUT`, then
  `bin/omamobile modules-push && bin/omamobile push` (`~/android/mainline/out`,
  no PCIe).
- **A leftover watchdog:** `tools/wifi-w1-capture --disarm`.
- Nothing is written to the chip's OTP or to any phone partition other than
  the boot images; the firmware files stay in `/usr/lib/firmware/updates/brcm/`
  (remove with the 7.6 W2.1 rollback).

### 9.6 Second W2.1 run: "Allocating ring buffers failed" (2026-10-12)

Log: `logs/wifi-w1-20261012-012412-s5.log`. Everything in the 9.4 table
passed up to `PCIe protocol version 7` and `max rx buf post 1535`
(shared area at 0x003b26e8 after 0.67 s, and the firmware console shows a
full boot). Then:

```
brcmf_pcie_init_ringbuffers Using TCM indices
brcmf_pcie_init_ringbuffers: Allocating ring buffers failed
```

**Cause: brcmfmac's DMA mask is 32 bits, and the restricted pool sits above
4 GiB.** brcmfmac never sets a DMA mask (no `dma_set_mask` anywhere in
`L/.../brcmfmac/`), so the PCI default of 32 bits applies. The overlay's
pool has no fixed address, and the kernel placed it at 0xaff000000 (top
of RAM; first line of the log). With a restricted pool, every
`dma_alloc_coherent()` is carved from the pool (`L/kernel/dma/direct.c:275-286`),
and `dma_direct_alloc_swiotlb()` drops any page above the coherent mask
(`direct.c:104-115`). So the first allocation, the DMA index buffer, failed
silently ("Using TCM indices" is brcmfmac's fallback). The next one, the
2.5 KB control ring, failed too (`pcie.c brcmf_pcie_alloc_dma_and_ring()`),
13 µs later. The ring sizes and counts were never involved: the failure
is on the first ring. Stock sets a 64-bit mask (`W/dhd_pcie_linux.c:329-330`;
Google's gs101 builds use 36 bits for the Exynos PCIe DMA,
`W/dhd_pcie_linux.c:2190-2197`, `W/dhd_pcie.h:826`). RAM ends at
0xaffffffff, inside 36 bits.

**DMA indices:** stock used them (`R/dmesg.txt:7105`, "H2D DMA WR INDX"), so
the firmware advertises `BRCMF_PCIE_SHARED_DMA_INDEX`. Our "TCM indices"
came from the failed index-buffer allocation, not from the flags. The
new debug line `shared flags 0x...` shows them: bit 16 (0x10000) should be
set and bit 20 (0x100000, 2-byte indices) clear (stock: "4 * 43").

**Fix** (wt-pcie, now rebased onto `omamobile` so it includes the battery
model commits `84217ab38`, `fdd6273e1`, `7b0f8b5d1`):

| Commit | Change |
|---|---|
| `7151e4834` wifi: brcmfmac: pcie: use a 64-bit DMA mask | `dma_set_mask_and_coherent(64)`, fall back to 32 |
| `449fdf52b` wifi: brcmfmac: pcie: say why the ring indices fall back to TCM | error line on the fallback; `shared flags 0x%08x` at PCIe debug |

(The earlier six commits are unchanged but have new hashes after the
rebase: `6505722a9`, `18b233c95`, `f5efa077b`, `9f7b5cac4`, `44dca3e6b`,
`47b75a6a2`.)

Builds: `logs/{kernel,modules,images}-w2dma.log`, out-pcie with both
overlays re-applied (plain DTB in `.default`), release
`7.3.0-rc6-omamobile-push1-00073-g449fdf52b5d2`.

**Next run (same command as 9.4 W2.1):**

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-pcie KERNEL_OUT=$HOME/android/mainline/out-pcie
bin/omamobile modules-push && bin/omamobile push           # reboots into slot B
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5
```

New lines to expect after `max rx buf post 1535, rx dataoffset 0`:

| Line | Pass | If not |
|---|---|---|
| `shared flags 0x...` (just before `PCIe protocol version 7`) | `& 0x10000` set | clear: the firmware wants TCM indices, fine but slower |
| `Using host memory indices` | present, and no `no DMA memory for ring indices` | the error line: DMA is still failing; check `cat /sys/kernel/debug/swiotlb/*` if present, and the pool line at boot |
| no `Allocating ring buffers failed` | | still there: note the line before it |
| `Nr of flowrings is 40` | 40 (stock "max H2D queues 40") | |
| then the 9.4 table from `Firmware: BCM4389/3 ...` on | | a firmware trap in the console lines: keep the log |

Then 9.4 W2.2-W2.4 (`iw dev`, `iw dev wlan0 scan`, reload). Rollback as 9.5.

### 9.7 Third W2.1 run: the firmware never reads the rings (2026-10-12)

Log: `logs/wifi-w1-20261012-013214-s5.log`, kernel `…-00073-g449fdf52b5d2`.
The DMA fix worked: `shared flags 0x70050107`, `Using host memory indices`,
`Nr of flowrings is 40`, and the firmware boots to "ThreadX v5.6
initialized". Then the rxpost ring is never read (`r_ptr 0 (1023), ring
1` over and over), `brcmf_msgbuf_rxbuf_ctrl_post: No PKTID available !!`
twice, and the first ioctl (`cur_etheraddr`) times out after 2 s.

The shared flags decode as: version 7, ASSERT_BUILT (0x100), DMA_INDEX
(0x10000, 4-byte indices since 0x100000 is clear), D2H sync XORCSUM
(0x40000), HOSTRDY_SUPPORT (0x10000000), NO_OOB_DW (0x20000000),
INBAND_DS (0x40000000), and **no DAR (bit 31 clear)**
(`W/include/bcmpcie.h:54-120`). The shared address moving (0x3b26e8 then
0x461198) is expected: the firmware randomises its heap from the host's
seed (`heap_aslr_*` in `fw_bcmdhd.map`).

Three causes, each with a fix:

1. **Wrong doorbell registers (the main one).** For PCIe core rev >= 64
   brcmfmac rings the DAR copies, H2D DB0/DB1 at 0xa20/0xa24
   (`L/.../pcie.c` `brcmf_reginfo_64`). bcmdhd rings those only when the
   firmware offers DAR and the host enables it; otherwise it uses the core's
   own `PCIH2D_MailBox` 0x140 and `PCIH2D_DB1` 0x144, on any core revision
   (`W/dhd_pcie.c:659-680`, `W/dhd_pcie.h:82`, `W/include/pcie_core.h:1030-1031`).
   This firmware has no DAR (also stock: "FW supports DAR ? N",
   `R/dmesg.txt:7104`). So neither the ring doorbells nor the host-ready
   ring (DB1) reached it, which fits a firmware that boots and then sits
   idle. D2H interrupts were never the problem: no D2H message was ever
   written.
2. **No host capability word.** For shared revision >= 6 bcmdhd writes
   `host_cap` (offset 84 of `pciedev_shared_t`) before it uses the rings:
   the IPC version, HOSTRDY, the device-wake mode, and UR_FW_NO_TRAP
   (`W/dhd_msgbuf.c:3878-4037,4347`, `W/include/bcmpcie.h:356-433,440-466`).
   brcmfmac writes nothing there. It does write a legacy "ring update"
   buffer at offsets 64/68, which in the v7 layout is `host_scb_addr`, and
   its high half spills into `host_scb_size` (72). With the pool at
   0xaff000000 that is 0xa, not 0.
3. **Rx packet IDs run out.** The firmware allows 1535 rx data buffers
   (`max rx buf post 1535`), brcmfmac has 1024 rx IDs for data, ioctl
   response and event buffers together, and fills them with data buffers
   first. The ioctl response buffers got no IDs ("No PKTID available"), so
   even a working ring could not have returned the `cur_etheraddr` answer.
   Stock posts 2040 (`R/dmesg.txt:7131`, "RxBuf Post : 2040").

"EL: 30 12fc" and "EL: e6 8a58" are binary event-log records (set, tag)
printed to the console. They are not decodable without Broadcom's
event-log string tables, which are not in the GPL tree, and they also
appear during a normal boot. Not a lead.

| Commit (wt-pcie) | Change |
|---|---|
| `8358ff260` wifi: brcmfmac: pcie: ring the core doorbells when the firmware has no DAR | BCM4389 without the DAR flag: doorbells at 0x140/0x144; logs `no DAR: doorbells at 0x140/0x144` |
| `bacfef43f` wifi: brcmfmac: pcie: write the host capabilities for the BCM4389 | `host_cap` = 7 \| ENABLE_HOSTRDY \| DS_NO_OOB_DW \| UR_FW_NO_TRAP = `0x00801407`; no legacy ring-update fields; logs `host capabilities 0x...` |
| `e89538839` wifi: brcmfmac: msgbuf: keep rx packet IDs for the control buffers | rx ID pool 2048; data buffers capped at 2047 - 16 |

Builds: `logs/{kernel,modules,images}-w2ipc.log`; out-pcie with both
overlays re-applied (plain DTB in `.default`), release
`7.3.0-rc6-omamobile-push1-00076-ge89538839a44`.

**Next run (same command):**

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-pcie KERNEL_OUT=$HOME/android/mainline/out-pcie
bin/omamobile modules-push && bin/omamobile push
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5
```

| Line | Pass | If not |
|---|---|---|
| `shared flags 0x70050107`, then `no DAR: doorbells at 0x140/0x144` | both | no second line: the flags changed (DAR now set?), note them |
| `host capabilities 0x00801407` | that value | — |
| `Using host memory indices`, `Nr of flowrings is 40` | as run 3 | — |
| `ring_mb_update_rptr R r_ptr N (...), ring 1` with N growing past 0 | the firmware reads rxpost | still 0: the doorbell is still not seen; keep the log (next suspect: hostready ordering) |
| no `No PKTID available` | absent | present: note how many |
| `Firmware: BCM4389/3 wl0: ... version 20.101.90 ...`, then `CLM version = Google.C10sub6` | both | `Timeout on response for query command` again: keep the log and the console lines after it |

Then 9.4 W2.2-W2.4. Rollback as 9.5.

### 9.8 Fourth W2.1 run: doorbells right, firmware still idle (2026-10-12)

Log: `logs/wifi-w1-20261012-014147-s5.log`, kernel `…-00076-ge89538839a44`.
`no DAR: doorbells at 0x140/0x144` and `host capabilities 0x00801407` were
both present. Ring 1 `r_ptr` stayed 0, ring 0 went to `w_ptr` 17 with a
doorbell each time, the ioctl timed out, and the firmware console ended at
"ThreadX v5.6 initialized" with no trap.

**What was checked against bcmdhd, and is right:** the doorbell registers
(0x140/0x144, `W/dhd_pcie.c:659-680`; any value works, bcmdhd writes
0x12345678); the BAR0 window at the PCIe core when ringing (brcmfmac
selects PCIE2 before `request_irq` and nothing moves it after); the v7
`ring_info_t` layout (`W/include/bcmpcie.h` `ring_info`, the same four 64-bit
host index addresses after the five 32-bit TCM pointers as brcmfmac's
`brcmf_pcie_dhi_ringinfo`); the host index layout (four arrays, 4-byte
indices, H2D indexed 0 = control, 1 = rxpost); and `host_cap`, which is
written after the rings but before any doorbell. The dongle cannot tell
the order of host writes it has not been rung about, so that is not too late.

**The order of host ready was different:** bcmdhd rings it right after the
common rings are set up, before any buffer is posted (`W/dhd_msgbuf.c:4430`
in `dhd_prot_init()`, `hostrdy_after_init` from `W/dhd_pcie.c:987`).
brcmfmac rang it only in preinit, after 1023 rx and 16 control buffers
were posted. Now it also rings it right after `request_irq` (4389 only).

**Remaining suspect: DMA between chip and host memory.** Nothing so far
proves that any DMA in either direction has ever worked. Firmware download
and the shared area go through BAR2 (MMIO). The chip is `dma-coherent`
through the bridge; if the coherency (AxCACHE in DBI 0x8e8, shareability in
SYSREG_HSI2 0x730) is not in effect, the chip reads stale zeros for our
indices and rings, and we never see its writes. That matches "firmware
idle, no trap" exactly. Google programs it after the root port setup and
again after enumeration (`G/pcie-exynos-rc.c:3624` in
`exynos_pcie_rc_establish_link()`, `:5748` at the end of probe). We did it
once, before link up. Now we do all three, and print the registers.

| Commit (wt-pcie) | Change |
|---|---|
| `6f384898b` PCI: dwc: gs201: program the coherency again after link up | `IOCC after link up: …` and `IOCC after enumeration: AxCACHE 0x…, shareability 0x…` |
| `2c738ed2d` wifi: brcmfmac: pcie: ring host ready early on the BCM4389, debug the indices | `host ready on 0x144` after `request_irq` (and again in preinit); `ring info: ringmem …, TCM idx …`; at each control doorbell and every 64th poll: `host H2D w … r …, D2H w … r …` and `TCM H2D w … r …, D2H w … r …, mailboxint 0x…` |

Builds: `logs/{kernel,modules,images}-w2db.log`, release
`7.3.0-rc6-omamobile-push1-00078-g2c738ed2d334`; out-pcie with both
overlays re-applied, and `.default` rebuilt from kbuild's preprocessed
source (pcie_1 disabled; checked).

**Run A (same command):**

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-pcie KERNEL_OUT=$HOME/android/mainline/out-pcie
bin/omamobile modules-push && bin/omamobile push
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5
```

| Line | Expect | Meaning |
|---|---|---|
| `IOCC after link up: AxCACHE 0x10101010, shareability 0x…3` (and `after enumeration`) | 0x10101010, low two bits 3 | other values: the coherency does not hold; go to run B |
| `host ready on 0x144` | right after `request_irq Enter` | — |
| `ring bell: host H2D w 8 1023 …` then `ring bell: TCM H2D w X Y …` | **X follows the host (8, 16, 17) and Y = 1023**: the chip fetches our indices (DMA reads work) | **X and Y stay 0**: the chip never read host memory, or never took the doorbell: go to run B |
| later `update rptr: host … r …` | host H2D r rising (r of ring 1 > 0) | TCM moves but the host's r stays 0: the chip's writes to host memory are not visible: run B |
| `mailboxint 0x…` | non-zero once the chip answers | — |
| success | `Firmware: BCM4389/3 …`, `CLM version = Google.C10sub6` | then 9.4 W2.2-W2.4 |

**Run B (only if A fails as above): the device made non-coherent.** Same
kernel; only the DTB loses `dma-coherent` on `pcie@14520000`. The DMA core
then maps the pool uncached and the bridge leaves IOCC off. If B works and
A does not, the IOCC setup is the bug.

```sh
D=$KERNEL_OUT/arch/arm64/boot/dts/exynos/google/gs201-cheetah.dtb
cp "$D" "$D.coherent"
$KERNEL_OUT/scripts/dtc/dtc -q -I dtb -O dts "$D" |
  awk '/pcie@14520000 \{/{f=1} f&&/^[ \t]*dma-coherent;/{f=0;next} {print}' |
  $KERNEL_OUT/scripts/dtc/dtc -q -I dts -O dtb -o "$D" -
$KERNEL_OUT/scripts/dtc/dtc -q -I dtb -O dts "$D" | grep -c dma-coherent   # 1 (UFS only; was 2)
bin/omamobile images && bin/omamobile push
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5
#   expect: no "IOCC after ..." lines (coherent is off), then the same table as run A
#   rollback: cp "$D.coherent" "$D"; bin/omamobile images && bin/omamobile push
```

Rollback otherwise as 9.5.

### 9.9 Runs A and B: the chip reads host memory, its writes never show (2026-10-12)

Logs: `logs/wifi-w1-20261012-015240-s5.log` (A, coherent) and
`…-015339-s5.log` (B, `dma-coherent` removed). The two are identical:
- IOCC holds in A (AxCACHE 0x10101010, shareability 0x13).
- The TCM copies show the chip **fetching** our H2D write indices from the
  pool (one doorbell behind) and consuming all 1023 rxpost and 5 control
  entries.
- But the host's copies of the read indices and all D2H write indices stay
  0, `mailboxint` stays 0, and there is no AER/fault line.

So DMA reads from 0xaff000000 work and DMA writes do not, and it is not
caching.

**Checked in Google's driver:** nothing programs a separate write path. The
only sysreg write is the shareability (`G/pcie-exynos-rc.c:2008`);
`PCIE_APP_XFER_PENDING` (ELBI 0x74) only gates L1 entry around config
accesses (`:1813,3597,3798`), and there is no MPS, inbound ATU or AXI
user-bit setup. One real difference from stock: **stock never DMAs above
4 GiB.** Its HSI2 PCIe SysMMU is on (`R/dmesg.txt:656-659` "Probe HSI2
block", "PCIe SysMMU is ENABLED" at `:2075`) and hands the chip 32-bit
IOVAs, so a write path with fewer address bits than the read path would
never show in stock. Our pool sits at the top of RAM because the overlay
gives it no range.

**Leading hypothesis:** the chip's (or the HSI2 fabric's) write addresses
lose the bits above 31, so the writes land at `addr & 0xffffffff`. For the
pool that is 0xff000000-0xffffffff, which is in the CMA area
(`cma: Reserved 32 MiB at 0xfe000000`): ordinary RAM, so nothing faults.
Other possibilities: writes dropped (an S2MPU or SysMMU in write-protect
mode; no fault registers are readable without devmem on HSI2, which
section 7.5 forbids), or the D2H path stalls in the chip.

**This build separates them:**

| Commit / file | What |
|---|---|
| `e765e7004` wifi: brcmfmac: pcie: watch the 32-bit aliases of high DMA buffers | at PCIe debug level: snapshot the RAM at the low-32-bit alias of the index buffer and of the control and rx completion rings before the first doorbell, and with each index dump report which words changed (`alias <name> +0x..: old -> new`, `alias <name>: N words changed`). Read-only |
| `device/cheetah/overlays/wifi-dma-pool-low-test.dtso` | `alloc-ranges` 0x80000000-0xffffffff for the pool: the pool below 4 GiB, so no address bit above 31 |

Builds: `logs/{kernel,modules,images}-w2alias.log`, release `7.3.0-rc6-omamobile-push1-00079-ge765e70044e3`. out-pcie has the
standard test DTB (pcie_1 + pool, coherent); `.default` was rebuilt
plain.

**Run C (diagnosis, same command; pool high as before):**

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-pcie KERNEL_OUT=$HOME/android/mainline/out-pcie
bin/omamobile modules-push && bin/omamobile push      # also replaces the run-B DTB on the phone
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5
```

| Line | Reading |
|---|---|
| `alias watch indices: dma 0xaff0..... -> 0xff0....., N bytes` (and `ctrl complete`, `rx complete`) | the watch is armed (pool above 4 GiB, alias is RAM). Missing: the pool moved below 4 GiB, so go straight to run D |
| `alias indices: N words changed` with N > 0, and the changed offsets are those of the read indices (`+0x..` = 4 × ring for H2D r, after the 43 H2D w slots) with values 1023 / 5 | **truncation proven**: the writes land at the 32-bit alias. Fix = DMA below 4 GiB (run D) |
| `alias ctrl complete: N words changed` > 0 | the ioctl completion was written to the alias |
| all aliases `0 words changed`, host r still 0 | **writes are dropped** (or never issued): run D still tells whether the address is the trigger |

**Run D (the candidate fix): pool below 4 GiB.**

```sh
O=$KERNEL_OUT D=$O/arch/arm64/boot/dts/exynos/google/gs201-cheetah.dtb
cp "$D" "$D.highpool"
$O/scripts/dtc/dtc -q -I dts -O dtb -o out/wifi-dma-pool-low-test.dtbo device/cheetah/overlays/wifi-dma-pool-low-test.dtso
$O/scripts/dtc/fdtoverlay -i "$D.highpool" -o "$D" out/wifi-dma-pool-low-test.dtbo
bin/omamobile images && bin/omamobile push
tools/phone-ssh 'dmesg | grep "restricted DMA pool"'    # expect an address below 0x100000000
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5
#   rollback: cp "$D.highpool" "$D"; bin/omamobile images && bin/omamobile push
```

| Line | Pass |
|---|---|
| `created restricted DMA pool at 0x00000000........` | below 4 GiB |
| no `alias watch` lines | (nothing to watch below 4 GiB) |
| `update rptr: host H2D w … r 5 1023 …` | host read indices now move |
| `mailboxint 0x…` non-zero, D2H w moving | the chip signals |
| `Firmware: BCM4389/3 …`, `CLM version = Google.C10sub6` | then 9.4 W2.2-W2.4 |

If D passes, the permanent fix is DT only: keep `alloc-ranges` below
4 GiB in the pool node (W4 wants a fixed region anyway). Until the S2MPU/
SysMMU question is settled, no device DMA above 4 GiB. If D fails the
same way as A/B, writes are dropped regardless of address: the next
suspect is the HSI2 SysMMU at 0x145c0000 (stock enables it; we leave it
as ABL did), and that needs its own staged, read-only probe.

### 9.10 Run C and the pool that would not move (2026-10-12)

**Run C** (`logs/wifi-w1-20261012-020701-s5.log`): the alias watch was
armed (0xaff000000 → 0xff000000, plus the control and rx completion
rings), and every check said `0 words changed`. So the chip's writes do
not land at the 32-bit alias. They are dropped, or go somewhere else.

**Run D could not run: the pool stayed at 0xaff000000.** Cause: both
overlays had the wrong cell count. gs201 has `#address-cells = <2>`,
`#size-cells = <1>` at the root and in `/reserved-memory`. `alloc-ranges =
<0x0 0x80000000 0x0 0x80000000>` (my 9.9 overlay) and the fixed `reg =
<0x0 0xa0000000 0x0 0x1000000>` are 16 bytes, not a multiple of the
12-byte entry. `of_flat_dt_get_addr_size_prop()` (`L/drivers/of/fdt.c:626-641`)
then returns NULL as if the property were absent, with no message. In
`fdt_scan_reserved_mem()` (`L/drivers/of/of_reserved_mem.c`) a node with
no usable `reg` but a `size` is dynamic, and with no usable
`alloc-ranges` it is placed top-down anywhere: 0xaff000000. That also
explains why the pool was "initialized" before the static regions in
dmesg (dynamic nodes are set up in the early scan). /proc/device-tree
shows the raw properties, so they looked right.

| Commit / file | Change |
|---|---|
| `d520f515d` of: fdt: warn when an address/size property has the wrong length | `OF: fdt: <node>: '<prop>' is N bytes, not a multiple of M (...): ignored` |
| `7ba655a94` arm64: dts: …gs201-cheetah: keep the Wi-Fi DMA pool below 4 GiB | `alloc-ranges = <0x0 0x80000000 0x80000000>` in the pool node itself, so the standard test DTB (pcie + pool overlays) is run D. Still disabled by default |
| `device/cheetah/overlays/wifi-dma-pool-low-test.dtso` | fixed to one size cell; no longer needed with the DT change, kept for older builds |

Builds: `logs/{kernel,modules,images}-w2low.log`, release `7.3.0-rc6-omamobile-push1-00081-g7ba655a9481e`; out-pcie has the
standard test DTB (pcie_1 + pool), `.default` rebuilt plain.

**Run D (same command, standard DTB):**

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-pcie KERNEL_OUT=$HOME/android/mainline/out-pcie
bin/omamobile modules-push && bin/omamobile push       # replaces the fixed-reg DTB in slot B
tools/phone-ssh 'dmesg | grep -E "restricted DMA pool|wifi-dma-pool|not a multiple"'
#   pass: "created restricted DMA pool at 0x00000000........" (below 4 GiB), "OF: reserved mem:
#         0x00000000........ (16384 KiB) map non-reusable wifi-dma-pool", no "not a multiple"
#   not below 4 GiB: stop and send the dmesg lines
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5
```

| Line | Pass | If not |
|---|---|---|
| no `alias watch` lines | (nothing above 4 GiB to watch) | `alias watch …` means the pool is still high |
| `ring bell: TCM H2D w …` | follows the host as before | — |
| `update rptr: host H2D w … r 5 1023 …` | host read indices move | still 0: writes are dropped whatever the address. Next is the HSI2 SysMMU at 0x145c0000 (stock enables it; we never touch it), which needs a staged read-only probe of its own |
| `mailboxint 0x…` | non-zero | — |
| `Firmware: BCM4389/3 …`, `CLM version = Google.C10sub6` | both | then 9.4 W2.2-W2.4 (`iw dev`, `iw dev wlan0 scan`) |

Rollback as 9.5.

### 9.11 Run D: the pool below 4 GiB changes nothing; probing the HSI2 path (2026-10-12)

Run D (`logs/wifi-w1-20261012-021916-s5.log`): the pool is at 0xff000000,
with the same pattern as every earlier run. The chip fetches one round of
H2D indices and ring entries (TCM H2D w 16, r 5, rxpost 1023/1023), and
then nothing: host H2D r and D2H w stay 0 and `mailboxint` stays 0. So the
writes fail whatever the address.

**One detail that narrows it.** PCIe does not let a read pass an earlier
posted write. The chip did one burst of reads, then stopped fetching: its
TCM copy of the control write index stays at 16 while the host goes to 17,
and it never rings a D2H doorbell (a register inside the chip, which needs
no host write). That fits a **write that never completes**, with the
chip's DMA engine blocked behind it. It fits less well with a write that
is accepted and then dropped, since then the reads and the doorbell would
carry on. This build reads the chip's own DMA engine state to settle it.

**What Google's code says about the two HSI2 blocks:**

- **S2MPU (0x145e0000).** With `CTRL0.ENABLE` = 0 "all traffic would be
  allowed through" (`G/drivers/soc/google/pkvm-s2mpu/common/hyp/s2mpu.c:183-195`).
  Its reset state blocks **all** DMA until the hypervisor configures it
  (same comment), which would block reads too. Permissions are per
  gigabyte and per VID, R and W separately (`common/kvm_s2mpu.h:340-346,420-424`),
  so a read-only setup is possible in principle. We read `CTRL0` = 0 at
  W1.1. Stock runs it from pKVM (`always-on`, `R/live.dts:9638-9645`), and
  we boot without pKVM.
- **PCIe SysMMU (0x145c0000).** Stock enables it (`use-sysmmu = "true"`,
  `R/live.dts:12107-12149`; "PCIe SysMMU is ENABLED", `R/dmesg.txt:2075`)
  and programs a page table for VID 1 (`pcie-vid-num = <1>`). Global
  `CTRL` 0 is bypass ("PCIe SysMMU use full disable(by pass) as default",
  `G/drivers/iommu/exynos-pcie-iommu-whi.c:203-221`). There are also BLOCK
  values (0x7, 0x3), and a per-VID enable with "stall mode is default"
  (`:190-193`, `exynos-pcie-iommu-whi.h:96-105`). A VID left enabled by
  the bootloader, with a page table that maps only some pages or stalls on
  a write fault, would explain a write that never completes. It records
  separate read and write fault addresses (`FAULT_AR_*` 0x70/0x78,
  `FAULT_AW_*` 0x80/0x88).
- Google's controller driver programs nothing else for the inbound path:
  no inbound iATU, no AXI AW/AR user bits, no MPS. The ELBI setup
  (`L1_REQ_NAK`, `QCH_SEL`, `MSTR_PEND_SEL_NAK`, `DBI_L1_EXIT_DISABLE`)
  and the DBI setup match ours (`G/pcie-exynos-rc.c:3560-3624` and
  `exynos_pcie_setup_rc()`). `use-msi = "false"` in stock, so the INTx
  path we use is the stock one.

**New in this build** (wt-pcie):

| Commit | What |
|---|---|
| `c7b2c66ec` PCI: dwc: gs201: add a staged read-only probe of the HSI2 DMA path | `echo N > /sys/module/pcie_gs201/parameters/hsi2_probe` reads one group; each register is logged (`hsi2 probe: about to read …`) before the read: **1** SysMMU VERSION, CTRL, CFG, STATUS, INT_STATUS, FAULT_AR/AW addr+info; **2** SysMMU CTRL/CFG/PT_BASE for VID 0 and 1; **3** S2MPU CTRL0, VERSION, CTRL1, CFG, INFO, STATUS; **4** S2MPU FAULT_STATUS + per-VID fault PA/INFO; **5** S2MPU L1 entries, VIDs 0-7, 2-4 GiB |
| `53a679e7a` wifi: brcmfmac: pcie: dump the dongle's DMA engine state when debugging | with every index dump: `dongle DMA H2D/D2H tx/rx ctrl … st0 … st1 …` (st0 bits 31:28 = state: 1 active, 2 idle, 3 stopped; st1 bits 31:28 = error: 3 data transfer, 4 descriptor read, 5 core), `dongle DAR errlog … erraddr … intstatus …`. These are chip registers read over BAR0, no SoC risk |

`tools/wifi-w1-capture --hsi2-probe N` runs groups 1..N after the link and
brcmfmac, under the same watchdog. Builds: `logs/{kernel,modules,images}-w2hsi2.log`,
release `7.3.0-rc6-omamobile-push1-00083-g53a679e7ae2a`, standard test DTB
(pool with `alloc-ranges`), `.default` rebuilt plain.

**Runbook (one group further per run; stop at the first hang).** The
SysMMU groups are what Google's EL1 driver reads in stock, so they are the
lower risk. The S2MPU beyond `CTRL0` is normally run from EL2 and **may
not be reachable from EL1**: a hang or reset there is possible, which is
what the watchdog is for.

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-pcie KERNEL_OUT=$HOME/android/mainline/out-pcie
bin/omamobile modules-push && bin/omamobile push

# E1: brcmfmac with the dongle DMA dump + SysMMU groups 1-2
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac --hsi2-probe 2 5
tools/phone-ssh 'lspci -vvv -s 00:00.0; lspci -vvv -s 01:00.0' > logs/w2-lspci-$(date +%H%M).txt
#   (config space through the kernel, safe while the link is up: look at the
#    root port's "Secondary status" <MAbort/<TAbort, DevSta, and the AER UESta lines)
# E2 (only if E1 did not hang): add the S2MPU control group
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac --hsi2-probe 3 5
# E3: S2MPU faults; E4: S2MPU permissions
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac --hsi2-probe 4 5
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac --hsi2-probe 5 5
#   if the phone resets: tools/wifi-w1-capture --pstore; the last "about to read" names the register
#   rollback: modprobe -r brcmfmac pcie_gs201; tools/wifi-w1-capture --disarm
```

How to read it:

| Reading | Meaning | Next |
|---|---|---|
| `dongle DMA D2H tx … st0 0x1…` (active) that never goes idle, st1 error 0 | the write is stuck in flight: the host is not accepting it | SysMMU/S2MPU lines below |
| `D2H tx … st1 0x3…/0x5…` | the host answered the write with an error | AER/lspci lines; SysMMU fault AW |
| `D2H tx` idle, `ptr` unchanged | the chip never started a write | back to the chip side (firmware console after the ioctl) |
| SysMMU `CTRL` 0, `CTRL_VID1` 0 | bypassed: not the SysMMU | S2MPU groups |
| SysMMU `CTRL` 0x5 or `CTRL_VIDn` bit 0 set, `FAULT_AW_ADDR` ≈ our pool address | the bootloader left the SysMMU translating, and our writes fault and stall in it | fix: disable it the way Google's driver does (`CTRL_VID` = 0, then `CTRL` = 0), or program a page table for VID 1 as stock does: a later, separate gate |
| S2MPU `CTRL0` 1, `FAULT_INFO` with the RW bit (bit 20) = write and a pool PA | S2MPU write protection | program the S2MPU (W4 work) |
| everything bypassed and no faults | the block is not on the write path we probed | next: the HSI2 sysreg/SSMT and the IA (the I/A sequencer also has ELBI/AXI hooks; `use_ia=0` is a cheap test: `--ia 0`) |

### 9.12 E1: brcmfmac had the wrong interrupt (2026-10-12)

E1 (`logs/wifi-w1-20261012-024325-s5.log`, `logs/w2-e1-abort-dmesg.txt`,
`logs/w2-lspci-0243.txt`):

- **Dongle DMA:** the H2D engines move (the chip reads), the D2H engines
  never move, and DAR errlog is 0. lspci shows no AER errors on either
  side.
- **One interrupt got through.** At 16.912 the thread read
  `mailboxint` = 1, which is `D2H0_DB0` for core rev >= 64
  (`W/include/pcie_core.h:516`, brcmfmac `BRCMF_PCIE_64_MB_INT_D2H0_DB0`).
  So the firmware did ring the D2H doorbell once, 20 µs before we read
  the (still 0) DMA'd D2H indices. Our last dongle-DMA dump was taken
  *before* that doorbell, so "D2H never moves" is not proven after it.
- **Then `irq 97: nobody cared`** through `exynos_irq_eint0_15` →
  `brcmf_pcie_quick_check_isr`, and the IRQ was disabled. After that no
  interrupt could reach brcmfmac, and the ioctl timed out.

**Cause:** brcmfmac's IRQ was the host-wake GPIO, not the PCIe INTx.
- The Wi-Fi DT node had `interrupts-extended = <&gpa6 1 IRQ_TYPE_LEVEL_HIGH>`
  ("host-wake"). For a PCI device with a DT node, `of_irq_parse_pci()`
  uses the node's own interrupt first (`L/drivers/pci/of.c:465-482`), so
  `pdev->irq` became the gpa6-1 EINT (IRQ 97).
- brcmfmac's PCIe bus never uses host-wake: its quick check reads the
  chip's mailbox status. The chip holds host-wake high (stock arms it,
  "hostwake_oob enabled", `R/dmesg.txt:7139`), so the level-high EINT
  fired with `mailboxint` mostly 0, until the kernel disabled it.
- **Second bug, hidden behind the first:** the host bridge's
  `interrupt-map` numbered INTA..INTD 0..3, but our INTx domain
  translates with `pci_irqd_intx_xlate()`, which takes 1..4 and rejects 0
  (`L/include/linux/pci.h:1884-1899`; `dra7.dtsi` uses 1..4). INTA could
  not have been mapped even without the host-wake entry.

The D2H mailbox bits for rev 72 are the ones brcmfmac uses (0xC30, bits
0..15 = DB0..DB7 D2H0/1). The quick check reads the right register. The
DAR `intstatus` (0xA10) went 0 → 0x80 → 0x100 over the bells; we don't
need it now.

**In-band device wake / host wake:** the flags offer INBAND_DS and
NO_OOB_DW. We told the firmware in `host_cap` "no device wake"
(`DS_NO_OOB_DW` without `DS_INBAND_DW`), which is bcmdhd's "Disable DS
altogether" branch (`W/dhd_msgbuf.c:3920-3930`). Host-wake only says the
chip wants attention; stock's out-of-band handler just schedules the same
work as its INTx handler. So no handshake is owed on it.

**SysMMU, from E1's probe:** `VERSION 0x80200001`, `CTRL 0x24`.
- Google's values are `CTRL_ENABLE` 0x5 (bit 0 = enable),
  `CTRL_BLOCK` 0x7, `CTRL_DISABLE` 0 = bypass
  (`G/iommu/exynos-pcie-iommu-whi.h:99-105`). Bit 0 is clear, so the
  SysMMU is not translating.
- Reading 0x70 on this version is a synchronous external abort (it left
  `pcie_gs201` unremovable, so a reboot is needed). That register is now
  out of the probe.

| Commit (wt-pcie) | Change |
|---|---|
| `1d2d4f08e` arm64: dts: …gs201: number the PCIe INTx map from 1 | interrupt-map INTA..D → 1..4 |
| `beb64496c` arm64: dts: …gs201-cheetah: let the Wi-Fi chip use INTx | no `interrupts` on the Wi-Fi node; host-wake keeps only its pin config |
| `2cf2a9426` wifi: brcmfmac: pcie: look at the rings again after an INTx on the BCM4389 | INTx can overtake the DMA'd index update (bcmdhd `dhd_bus_handle_intx_ahead_dma_indices()`): process the rings a second time ~1 ms later; debug dump from the interrupt thread (`isr: …`) |
| `998f718de` PCI: dwc: gs201: drop the SysMMU fault registers from the HSI2 probe | group 1 ends at INT_STATUS |

Builds: `logs/{kernel,modules,images}-w2intx.log`, release
`7.3.0-rc6-omamobile-push1-00087-g998f718de3f6`; the standard test DTB
(wifi node without `interrupts`, interrupt-map 1..4; checked), `.default` rebuilt plain.

**Runbook (after the reboot that clears the stuck module):**

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-pcie KERNEL_OUT=$HOME/android/mainline/out-pcie
bin/omamobile modules-push && bin/omamobile push
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5        # no --hsi2-probe
tools/phone-ssh 'grep -E "brcmf|gs201|97:" /proc/interrupts'
```

| Line | Pass | If not |
|---|---|---|
| `/proc/interrupts` | `brcmf_pcie_intr` on the `gs201-pcie-intx` chip, count > 0; nothing on gpa6/IRQ 97 | still an EINT: the DTB on the phone is old |
| no `nobody cared` | — | note which IRQ |
| `isr: host … D2H w a b c …` | D2H w becomes non-zero (ring 2, control complete, first) | INTx arrives but D2H w stays 0 even after the second look: the write problem is real; continue with 9.11 (dongle DMA `D2H tx` lines after the doorbell now show) |
| `Firmware: BCM4389/3 …`, `CLM version = Google.C10sub6` | both | — |

Then 9.4 W2.2-W2.4: `iw dev`, `ip link set wlan0 up && iw dev wlan0 scan`,
and the reload. Rollback as 9.5 (`--disarm` for a leftover watchdog).

### 9.13 Kernel 00087: the firmware traps on the second host ready (2026-10-12)

Run (`logs/wifi-w1-20261012-092910-s5.log`, `logs/w2-00087.out`): the
interrupt storm is gone and INTx reaches brcmfmac. The chip consumed
control entries up to TCM r 12 of 16, and D2H w stayed 0 in TCM as well
as in host memory. This time the firmware console was read after the
interrupt, and it ends in a trap:

```
000000.784 THREADX TRAP INFO: Thread: main_thread ...
TRAP 4(326dc8): pc 27489a, lr 27488d, sp 327020, cpsr 60000193 ... dfsr 80f, dfar 0
000000.784   srpwr: 0x000f0200 ...
```

With `fw_bcmdhd.map`, pc and lr are in **`_hnd_die`** (0x27486c), which
is a deliberate stop. The stack holds `pciedev_handle_hostready_intr+0x75`
(0x2315f1, also in r6/r7) and `pciedev_dpc+0xff` (0x2317c3). The firmware
died in its **host-ready handler**, 20 ms after our **second** host-ready
doorbell. Since 00078 we ring it twice: right after `request_irq`
(bcmdhd's single, early one) and again in `brcmf_pcie_preinit()`. The
first was accepted. bcmdhd rings it once at init
(`W/dhd_msgbuf.c:4430`) and otherwise only on resume, with the value
0x12345678 (`W/dhd_pcie.c:9215-9240`).

This also explains the earlier picture:
- **No D2H completion ever.** The firmware stopped before it answered
  anything; the 16 control entries were buffer posts, which need no
  answer, and the ioctl came after the second host ready.
- **D2H w 0 even in TCM.** Nothing was ever produced.
- **H2D r 0 in host memory.** The read-index writeback had not happened
  before the trap.
- Before the INTx fix the trap went unseen: no interrupt meant the
  console was only read at teardown, if at all.

The "writes never arrive" theory has no evidence left for it. The
chip's reads worked all along, and there was nothing to write yet.

| Commit (wt-pcie) | Change |
|---|---|
| `07c519fd7` wifi: brcmfmac: pcie: ring host ready only once on the BCM4389 | no host ready in preinit for the 4389 (the early one stays); value 0x12345678 |

Builds: `logs/{kernel,modules,images}-w2hrdy.log`, release
`7.3.0-rc6-omamobile-push1-00088-g07c519fd78ff`; standard test DTB,
`.default` rebuilt plain.

**Runbook:**

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-pcie KERNEL_OUT=$HOME/android/mainline/out-pcie
bin/omamobile modules-push && bin/omamobile push
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5
tools/phone-ssh 'grep -E "brcmf|gs201" /proc/interrupts; dmesg | grep -iE "TRAP|hnd_die|halted" | tail'
```

| Line | Pass | If not |
|---|---|---|
| exactly one `host ready on 0x144` | one, right after `request_irq Enter` | two: the old module is loaded |
| no `THREADX TRAP` / `TRAP 4` in the console lines | — | another trap: symbolise pc/lr/stack with `fw_bcmdhd.map` (`awk` on the map as in 9.13) and keep the log |
| `isr: … D2H w a b c` | a (control complete) > 0 | still 0 with no trap: now the write path is suspect again; dump `isr:` lines and dongle `D2H tx` |
| `Firmware: BCM4389/3 … 20.101.90 …`, `CLM version = Google.C10sub6` | both | `Timeout on response for query command`: keep the console lines after it |
| `/proc/interrupts` | `brcmf_pcie_intr` on `gs201-pcie-intx`, count rising | — |

Then 9.4 W2.2-W2.4:

```sh
tools/phone-ssh 'iw dev'                                   # wlan0, managed
tools/phone-ssh 'ip link set wlan0 up && iw dev wlan0 scan | grep -E "^BSS|SSID:|signal:" | head -40'
tools/phone-ssh 'modprobe -r brcmfmac && sleep 1 && modprobe brcmfmac debug=0x80004 && sleep 8 && iw dev | grep -c wlan0'
```

Rollback as 9.5 (`--disarm` for a leftover watchdog).

### 9.14 W2 passed; reload, MAC address, W3 and W4 (2026-10-12)

**W2 passed on 00088** (`logs/wifi-w1-20261012-093326-s5.log`):
firmware 20.101.90 and CLM Google.C10sub6 loaded, D2H completions arrive,
`brcmf_pcie_intr` on `gs201-pcie-intx` reached 176, no trap, and a scan
found 2.4 and 5 GHz networks (-61/-70 dBm). The interface is `wlp1s0`
(predictable naming), with a random MAC.

#### Driver-only reload (W2.4 failed)

`modprobe -r brcmfmac_wcc brcmfmac; modprobe brcmfmac` with `pcie_gs201`
loaded gives "FW failed to initialize". A full-stack reload works, because
WL_REG_ON cycles. brcmfmac resets the chip with the ChipCommon watchdog
(`brcmf_pcie_reset_device()`, at probe and at remove). Broadcom's driver
never does that on this chip: it uses a function level reset at attach
and at remove (`W/dhd_pcie.c` `dhdpcie_dongle_reset()` →
`dhd_bus_perform_flr()`: set Initiate FLR, 70 ms, clear it, poll config
0x88 bit 13, restore config space; stock does it at every Wi-Fi on,
`R/dmesg.txt:6717-6805`).

| Commit (wt-pcie) | Change |
|---|---|
| `1b668f01f` wifi: brcmfmac: pcie: reset the BCM4389 with an FLR | FLR instead of the watchdog for 14e4:4441, between the power-domain requests; watchdog as fallback |

Build: `logs/{kernel,modules,images}-w2flr.log`, release
`7.3.0-rc6-omamobile-push1-00089-g1b668f01f21d`; standard test DTB,
`.default` plain.

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-pcie KERNEL_OUT=$HOME/android/mainline/out-pcie
bin/omamobile modules-push && bin/omamobile push
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5       # W2 again: must still pass
tools/phone-ssh 'dmesg | grep -c "FLR done"'                   # >= 1 (probe)
# W2.4: driver-only reload, twice
tools/phone-ssh 'for i in 1 2; do modprobe -r brcmfmac_wcc brcmfmac; sleep 1; modprobe brcmfmac debug=0x80000; sleep 8;
  ip -br link | grep -c wlp1s0; done; dmesg | grep -E "FLR|FW failed|TRAP|Firmware: BCM4389" | tail'
#   pass: "1" twice, a "FLR done" per remove and per probe, "Firmware: BCM4389/3 ..." each time
#   fail "FLR did not complete, config 0x88 = ...": note the value (FLR not accepted; the
#   driver falls back to the watchdog, so the old failure comes back)
#   rollback: modprobe -r brcmfmac_wcc brcmfmac; modprobe -r pcie_gs201
```

#### The real MAC address

- **Where stock gets it:** from the bootloader. ABL writes a
  `/chosen/config` node into the DT at every boot, with `wlan_mac1` and
  `bt_addr` as text strings (stock: `R/live.dts:12655-12668`). Google's
  driver reads `/chosen/config/wlan_mac1`, and rejects it if it is locally
  administered (`W/dhd_custom_google.c:138-235`, `GET_CUSTOM_MAC_ENABLE`
  is on in `W/Kbuild:111`). Nothing comes from `persist`, an
  `.macaddr` file or the cmdline.
- The chip's own address is random because the NVRAM has none and the OTP
  isn't read (1.6). brcmfmac only reads `local-mac-address` from a node
  that is compatible with `brcm,bcm4329-fmac`
  (`L/drivers/net/wireless/broadcom/brcm80211/brcmfmac/of.c:124-131`);
  ours is `pci14e4,4441`. Even then, the value only exists at boot.
- **Check on the phone (prints nothing sensitive):**
  ```sh
  tools/phone-ssh 'test -s /proc/device-tree/chosen/config/wlan_mac1 && echo wlan_mac1 present;
    test -s /proc/device-tree/chosen/config/bt_addr && echo bt_addr present'
  ```
- **Proposal: a udev rule in `omamobile-device-cheetah`.** It runs before
  NetworkManager touches the link. Nothing is stored, and the value is
  never printed.
  - `/usr/lib/udev/rules.d/80-omamobile-wlan-mac.rules`:
    ```
    ACTION=="add", SUBSYSTEM=="net", DRIVERS=="brcmfmac", RUN+="/usr/lib/omamobile/wlan-mac %k"
    ```
  - `/usr/lib/omamobile/wlan-mac` (MIT):
    ```sh
    #!/bin/sh
    # Set the Wi-Fi MAC from the bootloader's /chosen/config/wlan_mac1, as Android does.
    f=/proc/device-tree/chosen/config/wlan_mac1
    [ -s "$f" ] || exit 0
    mac=$(tr -d '\000' < "$f" | tr 'A-F' 'a-f')
    case "$mac" in ??:??:??:??:??:??) ;; *) exit 0 ;; esac
    ip link set dev "$1" down 2>/dev/null
    ip link set dev "$1" address "$mac"
    ```
  - NetworkManager keeps the current address with its default
    `cloned-mac-address` (`preserve`), and only randomises the MAC while
    scanning. To test by hand before packaging:
    `tools/phone-ssh '/usr/lib/omamobile/wlan-mac wlp1s0; ip -br link show wlp1s0 | cut -c1-30'`
    (check that the address changed, without pasting it anywhere).
  - Bluetooth's `bt_addr` is the same kind of value, for the BT plan.

#### W3 runbook: associate (needs Derek's OK first; W4 is not done)

Omarchy uses **NetworkManager** (with wpa_supplicant) for Wi-Fi:
`/usr/share/omarchy/install/hardware/network.sh` disables iwd, and
`install/config/enable-services.sh` enables NetworkManager. Its UI is the
shell's network panel (`omarchy-shell shell toggle omarchy.network`). Our
`omamobile-device-cheetah` only keeps NetworkManager off `usb0`.

```sh
# W3.0  state: NM running and managing wlp1s0, Wi-Fi radio on
tools/phone-ssh 'systemctl is-active NetworkManager wpa_supplicant; nmcli radio wifi; nmcli -t dev | grep wlp1s0'
#   pass: active/active (wpa_supplicant is D-Bus activated, may say inactive until used), enabled,
#         "wlp1s0:wifi:disconnected"
# W3.1  scan through NM
tools/phone-ssh 'nmcli dev wifi rescan; sleep 5; nmcli -f SSID,SECURITY,SIGNAL,CHAN dev wifi list | head -20'
# W3.2  WPA2-PSK (password asked on the phone's terminal, not on the command line)
tools/phone-ssh -t 'nmcli --ask dev wifi connect "<SSID>" ifname wlp1s0'
tools/phone-ssh 'nmcli -t -f GENERAL.STATE,IP4.ADDRESS dev show wlp1s0; ping -c 3 -I wlp1s0 1.1.1.1'
#   pass: "100 (connected)", an address, 0% loss
# W3.3  throughput, short (no long runs before W4)
tools/phone-ssh 'curl -o /dev/null -w "%{speed_download}\n" https://speed.cloudflare.com/__down?bytes=50000000'
# W3.4  WPA3-SAE (an SAE or transition-mode network)
tools/phone-ssh -t 'nmcli --ask dev wifi connect "<SAE-SSID>" ifname wlp1s0'
# W3.5  from the UI: omarchy-shell shell toggle omarchy.network, pick a network
# rollback: nmcli dev disconnect wlp1s0; nmcli con delete "<SSID>"; then the 9.5 module unloads
```

What a failure looks like:
- **The four-way handshake never completes** (NM: "password wrong", or
  `wlp1s0: 4-Way Handshake failed`). brcmfmac may be using the firmware
  supplicant. Omarchy already handles this for Apple's Broadcom parts
  (`install/hardware/apple/fix-brcmfmac-supplicant.sh`). Try:
  `modprobe -r brcmfmac_wcc brcmfmac; modprobe brcmfmac feature_disable=0x82000`
  (FWSUP 0x2000 + FWAUTH 0x80000 off, wpa_supplicant does the handshake).
- **Association works but no data, or the firmware traps on TX.** These
  are the two items left from 8.5: the v1 join parameters, and the host
  building the 802.3/LLC header. Keep the log and the console lines.
- **D2H completions corrupted under load.** This would be the XOR-checksum
  sync brcmfmac doesn't check (1.6). Look for "invalid" or "unknown
  msgtype" lines.

#### W4: what W1-W2 taught us about the HSI2 DMA path

- **SysMMU HSI2 (0x145c0000):** `VERSION` 0x80200001, `CTRL` 0x24.
  - Bit 0 (enable, Google's `CTRL_ENABLE` = 0x5) is clear, so it is
    bypassed.
  - `CFG`, `STATUS` and `INT_STATUS` read 0.
  - **Reading 0x70 (`FAULT_AR_ADDR` in the whi map) is a synchronous
    external abort** on this version. It left `pcie_gs201` unremovable
    until a reboot. The fault registers of this version are elsewhere.
    Read nothing past 0x60 until the v8.2 map is known.
- **S2MPU HSI2 (0x145e0000):** `CTRL0` = 0, all traffic allowed
  (`G/drivers/soc/google/pkvm-s2mpu/common/hyp/s2mpu.c:183-195`).
  - Nothing else in it has been read. Stock programs it from EL2 (pKVM),
    so the other registers may not be reachable from EL1.
  - Probe groups 3-5 exist in `pcie_gs201` (`hsi2_probe`), one group per
    run under the watchdog. Expect a reset as the possible outcome.
- **DMA works with no IOMMU,** coherent (IOCC on), from a restricted pool
  below 4 GiB (`alloc-ranges` 0x80000000-0xffffffff in the DT, 9.10). The
  chip reads and writes there. W4 can therefore confine VID-of-PCIe-ch1 to
  one 16 MiB window below 4 GiB. With 1 GiB S2MPU granules that means an
  L2 table for the gigabyte at 3-4 GiB (`L1ENTRY_ATTR` gran 4K/64K + an
  L2 table), and UFS shares the S2MPU (other VIDs or the same table).
- **Order for W4:**
  1. Find out from EL1, read-only, under the watchdog, which S2MPU
     registers are reachable (group 3 first).
  2. If the per-VID L1/L2 registers are writable from EL1, program them
     with the pool only.
  3. If they are not, the remaining options are 1.5's other routes: pKVM
     with Google's S2MPU module, or the PCIe SysMMU path that stock uses
     (VID 1, a page table that maps only the pool).

### 9.15 W3: association fails, "join" needs the versioned layout (2026-10-12)

**W3 on the integration kernel (00126):** the scan works, and
`nmcli --ask dev wifi connect <SSID>` stores the profile. Then every
attempt logs `brcmf_cfg80211_connect: BRCMF_C_SET_SSID failed (-52)` and
NetworkManager reports "ssid-not-found". There is no trap.
- -52 is `-EBADE`, brcmfmac's code for "the firmware returned an error"
  (`L/.../brcmfmac/fwil.c:110-125`).
- The "join" iovar failed first, quietly, then the `WLC_SET_SSID`
  fallback failed too.
- Reloading with `feature_disable=0x82000` changed nothing, so the
  firmware supplicant is not involved.

**Cause: the join parameter layout.**
- Broadcom's driver chooses between two "join" layouts by the firmware's
  WLC interface version. 14.2, 14.4, 16.1+ and 17+ take
  `wl_extjoin_params_v1_t` (`W/wl_cfg80211.c:18509-18517`, constants
  `W/wl_cfg80211.h:1393-1404`, fill `wl_fillup_assoc_params_v1()`).
- Our firmware reports WLC **14.4** (`R/dmesg.txt:7128`).
- The v1 layout (`W/include/wlioctl.h:1333-1346,1505-1520`) adds a
  `version`/pad word in front of the SSID. Its assoc params start with
  `version`, `flags`, then the BSSID, `bssid_cnt` and `chanspec_num`.
  bcmdhd leaves both version fields 0.
- brcmfmac only knows the unversioned layout. That one matches
  `wl_extjoin_params_t` (with the `bssid_cnt` slot as alignment padding),
  so older firmware is fine and this one is not.
- **Chanspec:** the scan's channels decode correctly (ch 6 and 48 listed
  right), and the join uses the same `d11inf` encoder (D11AC format, the
  4389's io_type). For 2.4 GHz ch 6, 20 MHz, that is 0x1006, the same
  value `wl_freq_to_chanspec()` gives. It is not the cause.

| Commit (wt-pcie) | Change |
|---|---|
| `dfc8407db` wifi: brcmfmac: use the versioned join parameters on the BCM4389 | new `JOIN_V1` feature from `wlc_ver` (bcmdhd's test), BCM4389 only; `brcmf_ext_join_params_v1_le`/`brcmf_assoc_params_v1_le`; v1 "join" when set, logging the firmware's own error code (`join (v1, chanspec 0x...., N bytes) failed: firmware error E`) |

Build: `logs/{kernel,modules,images}-w3join.log`, wt-pcie release
`7.3.0-rc6-omamobile-push1-00090-gdfc8407db34a` (standard test DTB,
`.default` plain), to be merged into omamobile-int.

**Runbook.**

1. **No rebuild (current 00126 kernel, CONFIG_BRCMDBG is on): get the
   firmware's error string for the failing join.**
   ```sh
   tools/phone-ssh 'modprobe -r brcmfmac_wcc brcmfmac; modprobe brcmfmac debug=0x1000; sleep 8;
     nmcli con up <SSID>; sleep 10; dmesg | grep -E "Firmware error|SET_SSID|join" | tail -20'
   nmcli con modify <SSID> connection.autoconnect no   # (on the phone) keep it from retrying
   ```
   Expect `brcmf_fil_cmd_data: Firmware error: BCME_BADLEN` (or
   `BADARG`) for "join" and for `WLC_SET_SSID`. A different error (e.g.
   `NOTASSOCIATED`, `BUSY`, `NOTREADY`) means the layout is not the
   problem: send it.

2. **New kernel** (wt-pcie, to merge into omamobile-int):
   ```sh
   # after merging and pushing your integration kernel, with Wi-Fi loaded as before:
   tools/phone-ssh 'dmesg | grep -i "enabling firmware feature: JOIN_V1"'   # needs debug=0x4 at load
   tools/phone-ssh -t 'nmcli con up <SSID>'
   tools/phone-ssh 'dmesg | grep -E "join \\(v1|SET_SSID|Firmware error" | tail; nmcli -t -f GENERAL.STATE,IP4.ADDRESS dev show wlp1s0'
   ```
   - **Pass:** no "join (v1 ...) failed" and no `SET_SSID failed`;
     NetworkManager reaches "100 (connected)" with an address. Then
     continue with 9.14 W3.2-W3.5.
   - **"join (v1 …) failed: firmware error E":** send E. -2 (BADARG) or
     -24 (BADLEN) mean the layout is still off.
   - **Associated but the 4-way handshake fails:** try
     `feature_disable=0x82000` (9.14).
   - **Rollback:** `nmcli dev disconnect wlp1s0`, then
     `nmcli con modify <SSID> connection.autoconnect no`.

### 9.16 W3: the join works, the 4-way handshake does not (2026-10-12)

**What happened.** On omamobile-int 00128 (with `dfc8407db`), JOIN_V1 is
enabled and the join goes through: wpa_supplicant goes associating →
4way_handshake. Then "Authentication with … timed out" and "4-Way
Handshake failed" (reason 3, locally generated)
(`logs/w3-join-00128-dmesg.txt`, `logs/w3-join-00128-nm.txt`). A second
try at about 10:13 left the control ring full ("Failed to reserve space in
commonring", escan -12) until a full reload (`logs/w3-join-00128-dmesg2.txt`).

**Reading the logs:**
- **Control completions get lost well before the join.**
  - `brcmf_p2p_create_p2pdev: timeout occurred` at 19.9 s, right after
    load; that is a missed firmware event.
  - From 32 s, `Timeout on response for query command` about every 2 s.
  - Mapping NM's clock to dmesg (wlp1s0 appears at 17.5 s =
    10:08:52.1), the connect at 10:09:29 is ≈54.8 s. The timeouts run
    straight through the join and the handshake. Some ioctls (the join
    itself) complete, others don't.
  - This is how completions behave when they are only processed by a
    *later* interrupt.
  - The 4-way handshake needs the AP's TX flowring. Brcmfmac creates it
    with a control-ring request and waits for its completion before it
    sends EAPOL msg 2. With completions going missing, msg 2 can sit in the
    flowring queue. wpa_supplicant only reaches the 4way_handshake state
    after it has *received* msg 1, so RX works and TX of msg 2 is the
    stuck side.
- **The firmware also asks for host-built TX headers.** Its capability
  list ends in `host_sfhllc`. For that capability Broadcom's driver posts
  every TX frame already converted to 802.3 + LLC/SNAP: the whole frame is
  in the data buffer, the original Ethernet header is in `txhdr`, and the
  post sets `BCMPCIE_TXPOST_FLAGS_HOST_SFH_LLC` 0x10
  (`W/dhd_msgbuf.c:5464-5470,8620-8636`; `W/dhd_common.c:10863-10963`,
  `dhd_ether_to_8023_hdr()`). It reverses this on TX completion. RX is
  plain Ethernet either way.
- **Not the cause:**
  - `Invalid chanspec 0x5001`: a 6 GHz chanspec (band bits 0x4000) that
    brcmutil's D11AC decoder doesn't know. 6 GHz channels are skipped,
    which is harmless for now.
  - `WLC_SET_ROAM_TRIGGER error (-52)`: a roam setting.
  - The flow ring create request matches bcmdhd's
    `tx_flowring_create_request_t` field for field.
- **Not ruled out yet:** a firmware trap after association. The console
  was never read, because `debug=0x4` has no FWCON. The runbook below
  reads it.

| Commit (wt-pcie) | Change |
|---|---|
| `bbad7a1c6` wifi: brcmfmac: msgbuf: build the 802.3/LLC TX header on the host for the BCM4389 | `HOST_SFHLLC` feature from "cap" (4389 only; feature bit 27, `feature_disable=0x8000000` turns it off); TX frames converted as bcmdhd does, flag 0x10, converted back before completion; `TX EAPOL …`, `TX EAPOL done … status N`, `RX EAPOL …` at the msgbuf debug level |
| `e1c6379cf` wifi: brcmfmac: pcie: poll the D2H rings after interrupts on the BCM4389 | after each interrupt and doorbell, process the D2H rings every 10 ms for 500 ms (bcmdhd re-runs its interrupt work for INTx with DMA'd indices); mutex between poll and IRQ thread; `poll: mailboxint … pending without an interrupt` at PCIe debug |

Build: `logs/{kernel,modules,images}-w3eapol.log`, wt-pcie release
`7.3.0-rc6-omamobile-push1-00092-ge1c6379cf4e3` (standard test DTB).

**Capture runbook** (after merging into omamobile-int and pushing). The debug
mask 0x1c8000 is MSGBUF + PCIE + FWCON + CONN; PCIE is chatty but carries
the index dumps.

```sh
# C0 load with the capture mask, poll the firmware console every ~80 ms
tools/phone-ssh 'modprobe -r brcmfmac_wcc brcmfmac; modprobe brcmfmac debug=0x1c8000; sleep 8;
  echo 20 > /sys/kernel/debug/ieee80211/phy0/console_interval;
  dmesg | grep -E "HOST_SFHLLC|JOIN_V1|Firmware: BCM4389"'
#   pass: "enabling feature: HOST_SFHLLC" (needs 0x4 in the mask for that line; optional), firmware line
# C1 connect, stream the log (second terminal: tools/phone-ssh dmesg -w > logs/w3-eapol-$(date +%H%M).txt)
tools/phone-ssh -t 'nmcli con up <SSID>'
# C2 afterwards
tools/phone-ssh 'dmesg | grep -E "EAPOL|poll: mailboxint|Timeout on response|Failed to reserve|CONSOLE.*(TRAP|trap|ASSERT)|join \(v1" | tail -60;
  nmcli -t -f GENERAL.STATE,IP4.ADDRESS dev show wlp1s0; journalctl -u wpa_supplicant --since "-3min" | tail -20'
# if the control ring is stuck again: the index state and the firmware console right then
tools/phone-ssh 'dmesg | grep -E "dump_indices|dump_dma|CONSOLE" | tail -40'
# rollback: nmcli dev disconnect wlp1s0; nmcli con modify <SSID> connection.autoconnect no
```

| Line / state | Pass | Meaning if not |
|---|---|---|
| `RX EAPOL pktid … len 121…` | M1 (and later M3) arrive | no RX EAPOL: the AP never got as far as M1, or RX completions are lost; look at `poll:` lines |
| `TX EAPOL pktid … (802.3+LLC)` | M2 posted, flagged | no TX line: msg 2 never left the flowring queue; look for the flowring create completion (`Flow Create` lines at MSGBUF level) and `Timeout` lines |
| `TX EAPOL done … status 0` | firmware sent it | status ≠ 0: the firmware rejected the frame. Try `feature_disable=0x8000000` (SFH off) once to compare |
| `poll: mailboxint … pending without an interrupt` | rare | frequent: INTx delivery is losing doorbells; the poll covers it; a host-side INTx fix is still owed (gs201 ELBI INTA event latching) |
| no `Timeout on response for query command` | none | still there with the poll: completions are not in the ring at all → firmware console |
| `CONSOLE: … TRAP` / `ASSERT` | none | symbolise pc/lr/stack with `fw_bcmdhd.map` (9.13 method) and send |
| NM `GENERAL.STATE:100 (connected)`, an IPv4 address | yes | then 9.14 W3.2-W3.5 |

If the handshake still fails with all of the above clean, two cheap
comparisons:
- `feature_disable=0x8000000`: SFH off, the old TX format.
- `feature_disable=0x2000`: firmware supplicant off (FWSUP is bit 13 in
  this kernel's list; Omarchy's Apple value 0x82000 also turns off bit 19,
  which in this kernel is SAE, so don't reuse it here).

### 9.17 W4: the DMA firewall (2026-10-12, offline; started)

W3 passed on omamobile-int 00131 (WPA2, 5 GHz, DHCP, real MAC, 50 MB at
19 MB/s, no timeouts or traps). W4 must confine the BCM4389's DMA before
Wi-Fi may load at boot.

#### Which route, with evidence

- **The HSI2 PCIe System MMU is PCIe-only, and stock uses it for the
  Wi-Fi chip.**
  - `sysmmu@145C0000` is `samsung,pcie-sysmmu`, `port-name =
    "PCIe_CH1"`, `pcie-vid-num = <1>`, SPI 446 (`R/live.dts:12157-12170`).
  - Stock's PCIe node has `use-sysmmu = "true"` (`R/live.dts:12107-12149`).
  - The UFS node references no SysMMU (only the shared S2MPU), so turning
    this SysMMU on cannot affect UFS. This settles the "UFS shares HSI2"
    worry for this route.
- **The SysMMU is a v8.1 ("whi" variant).**
  - Our `VERSION` 0x80200001 decodes with Google's macros
    (`MMU_RAW_VER` = bits 31:17, major = 8, minor = 1;
    `G/drivers/iommu/exynos-pcie-iommu-whi.h:191-194`).
  - For v7 and later, its fault registers are at 0x1010/0x1014/0x1018,
    not 0x70 (`exynos-pcie-iommu-whi.c:422-428,518-525`). That is why
    reading 0x70 aborted.
  - Table format:
    - one first-level table for a 36-bit IOVA: 65536 entries of 1 MiB,
      256 KiB, 256 KiB-aligned ("36bit VA FLPD must be aligned in 256KB");
    - sections are `(pa >> 4) | 2`, plus bit 6 for shareable
      (`whi.h:28-89`, `whi.c:1348-1360`);
    - the base goes in `PT_BASE_PPN_VID(n)` (0x800c + n·0x1000) as
      `pa >> 12`.
  - Enable sequence (`__sysmmu_enable_nocount()`, `whi.c:164-200`):
    1. `TLB_CFG(0)` = 0;
    2. write the table base, then flush the VID;
    3. `CTRL |= 0x5`;
    4. `CTRL_VID(n) |= 1` (bit 3 = stall on fault);
    5. flush again.
  - The table is written by the CPU and walked by the SysMMU
    non-coherently (Google cleans it with `dma_sync_single_for_device`).
  - Upstream's `exynos-iommu` does not cover this PCIe variant.
- **We don't need a translating IOMMU, only a window.**
  - The Wi-Fi DMA pool is now below 4 GiB (0xff000000, 16 MiB; 9.10).
  - A first-level table that maps exactly those 16 sections 1:1
    (IOVA = PA) leaves brcmfmac and the DMA API untouched.
  - Every other address becomes a translation fault, and the SysMMU
    interrupt reports it. That is the firewall.
  - It is small, self-contained, and the same hardware path stock uses.
- **S2MPU: possible later, not needed first.**
  - Google's own EL1 driver for the gs101 S2MPUs programs `L1ENTRY_ATTR`
    and `CTRL0` directly from EL1 (`G/drivers/soc/google/s2mpu/s2mpu-lib.c:160-178`),
    so the block is not EL2-only by design.
  - But `s2mpu_hsi2` is `always-on` and pKVM-owned in stock
    (`R/live.dts:9638-9645`), and UFS shares it.
  - Reachability from EL1 is still unproven: probe groups 3-5 exist, one
    per watchdog run.
  - It would be a second layer: per-VID GB permissions, with the 3-4 GiB
    gigabyte cut down by an L2 table. **Not needed for W4's goal.**
- **pKVM:** out of scope. It is a large change of the boot model.

#### What was built (branch `omamobile-w4` off `omamobile-pcie`)

| Commit | Change |
|---|---|
| `be2c591e3` dt-bindings: iommu: add the Google gs201 PCIe System MMU as a DMA window | `google,gs201-pcie-sysmmu`: reg, interrupts, 2 clocks, `memory-region`, `google,vid` |
| `43d687e72` PCI: dwc: gs201: add a System MMU DMA window for the GEN4A_1 controller | `pcie_gs201_sysmmu`, a standalone platform driver. `mode=0` (default) only logs the registers; `mode=1` maps `memory-region` 1:1 and enables VID translation; `mode=2` enables it with an empty table (negative test). Fault IRQ logs `blocked READ/WRITE at …`. Stall-on-fault is off unless `stall=1`; sections are shareable (`shareable=1`) |
| `cb50d430a` arm64: dts: …gs201: add the PCIe GEN4A_1 System MMU | `pcie_1_sysmmu` (`sysmmu@145c0000`, SPI 446, `CLK_GOUT_HSI2_SYSMMU_HSI2_CLK_S1/S2`, VID 1), **disabled**; cheetah points it at `wifi_dma_pool` |
| `434a1be2e` PCI: dwc: gs201: probe the SysMMU v7+ fault registers | `hsi2_probe` group 6: 0x870, 0x874, 0x1010, 0x1014, 0x1018, 0x2004, 0x2008 |

- omamobile repo:
  - `CONFIG_PCIE_GS201_SYSMMU=m`;
  - overlay `device/cheetah/overlays/wifi-dma-firewall-test.dtso`
    (enables the node);
  - `wifi-w1-capture --hsi2-probe` now also takes a list (`2,6`).
- Boot pieces, **committed disabled** in `omamobile-device-cheetah`:
  - `bin/omamobile-wifi-start` and `vendor/systemd/system/omamobile-wifi.service`;
  - no wants link, so the service is installed but not enabled;
  - the script writes and syncs a marker
    (`/var/lib/omamobile/wifi-bringup-started`) before touching the
    hardware, and skips Wi-Fi on a boot that finds it;
  - order: `pcie_gs201_sysmmu mode=1`, then check it is bound, then
    `pcie_gs201`, then `brcmfmac`, then wait up to 30 s for the
    interface, then remove the marker;
  - `--retry` clears the marker;
  - the `omamobile-wifi.conf` blacklist stays (explicit modprobe works).
- Builds: `logs/{kernel,modules,images}-w4a.log`, release
  `7.3.0-rc6-omamobile-push1-00096-g434a1be2ee09`.
  - The images carry the **standard test DTB** (pcie + pool; firewall node
    disabled).
  - `gs201-cheetah.dtb.firewall` is the same plus the firewall overlay,
    for F2.

#### Staged runbook

Each step is one run. Stop at the first surprise. **⚠** marks steps that can
hang the SoC: recovery is the watchdog (if armed) or a 30 s Power hold.

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-pcie KERNEL_OUT=$HOME/android/mainline/out-pcie
O=$KERNEL_OUT D=$O/arch/arm64/boot/dts/exynos/google/gs201-cheetah.dtb
bin/omamobile modules-push && bin/omamobile push            # standard test DTB (no firewall node)

# F1 ⚠ read-only: SysMMU VID registers (group 2) and the v7+ fault/TLB registers (group 6)
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac --hsi2-probe 2,6 5
#   pass: every "hsi2 probe: about to read X" is followed by "X = 0x…"
#   expect: CTRL_VID1 bit 0 = 0 (not translating), PT_BASE_PPN_VID1 = 0 or a stale value,
#           FAULT_* = 0, TLB_CFG0 = some default
#   a read that aborts ("synchronous external abort") or hangs: note the register, do not
#   go on to F2 with that register in the driver (tell me which)
#   Wi-Fi still works in this run (nothing was changed)
```

F2-F4 come only after F1 passes. Each needs the firewall DTB (`cp "$D.firewall" "$D"; bin/omamobile images && bin/omamobile push`) and the order *firewall, then PCIe, then brcmfmac*:

```sh
# F2  log only (mode=0): the driver binds, reads the same registers, changes nothing
tools/phone-ssh 'modprobe pcie_gs201_sysmmu; dmesg | grep gs201-pcie-sysmmu'
#   pass: "probe: version 0x80200001 (v8.1) ctrl 0x24 …" and "VID 1 ctrl … pt_base …"
# F3 ⚠ enforce (mode=1), then Wi-Fi as W3
tools/phone-ssh 'modprobe -r pcie_gs201_sysmmu; modprobe pcie_gs201_sysmmu mode=1; dmesg | grep gs201-pcie-sysmmu | tail -4'
#   pass: "allowing 0x00000000ff000000..0x0000000100000000 (16 sections)", "enforcing: … VID 1 ctrl 0x…1 …"
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5
tools/phone-ssh -t 'nmcli con up <SSID>'; tools/phone-ssh 'curl -o /dev/null -w "%{speed_download}\n" https://speed.cloudflare.com/__down?bytes=50000000; dmesg | grep -c "blocked"'
#   pass: connects, ~19 MB/s as in W3, 0 "blocked" lines
#   "blocked … at 0x…" during normal use: some buffer lives outside the pool: send the line
# F4 ⚠ the negative test (mode=2, empty table): proves VID 1 really carries the Wi-Fi DMA
tools/phone-ssh 'modprobe -r brcmfmac_wcc brcmfmac; modprobe -r pcie_gs201; modprobe -r pcie_gs201_sysmmu;
  modprobe pcie_gs201_sysmmu mode=2'
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5
#   pass: brcmfmac fails to come up AND "blocked READ at 0x00000000ff……" lines appear; the SoC stays fine
#   brcmfmac comes up anyway with no "blocked" lines: the Wi-Fi traffic is not on VID 1 → stop (the
#   firewall would be a no-op); tell me
# rollback for all: modprobe -r brcmfmac_wcc brcmfmac pcie_gs201 pcie_gs201_sysmmu;
#   DTB: cp "$D.default" "$D" + both test overlays (9.4), or bin/omamobile images from a fresh kernel build
```

#### After F2-F4 pass (not now)

1. Default DTB: enable `pcie_1`, `pcie_1_phy`, `wifi_dma_pool` and
   `pcie_1_sysmmu` (one DT commit), plus `options pcie_gs201_sysmmu mode=1`
   in a modprobe.d file.
2. Enable `omamobile-wifi.service`: add the
   `multi-user.target.wants/omamobile-wifi.service` link in
   `omamobile-device-cheetah`. Keep the blacklist, so the stack only ever
   loads through the guarded script.
3. Optional second layer: the S2MPU, after probe groups 3-5.

### 9.18 F1 results; probe hang explained (2026-10-12)

F1 on omamobile-int 00143 (contains `434a1be2e`):
- Group 2: `CTRL_VID0` 0, `CFG_VID0` 0x00020000, `PT_BASE_PPN_VID0` 0,
  and the same for VID1 (0, 0x00020000, 0). **Neither VID translates.**
- Group 6: `CAPA0_V7` 0x41085800, `CAPA1_V7` 0x0000f011, `FAULT_ADDR_VA`,
  `FAULT_INFO0/1` 0, `TLB_CFG0` 0.
- **`TLB_MATCH_CFG0` (0x2008) never printed a value.** A few minutes
  later `modprobe -r pcie_gs201` hung in D state, the same as after the
  0x70 abort in E1.

**Cause of the hang:** the probe parameter held a mutex across its reads,
and `pcie_gs201`'s remove() takes the same mutex. A read that aborts kills
the writing task with the mutex held, so remove() waits forever. Fixed in
`49b341b4a` (wt-pcie `omamobile-w4`):
- the mutex is replaced by a ready flag;
- every probe line is logged at KERN_ERR, so a brcmfmac debug flood can't
  push it out of the log;
- 0x2008 is gone from group 6. Google's driver only ever touches
  `TLB_MATCH_CFG(1)`, under `MULTI_TLB`/TLB pinning.

**Registers `pcie_gs201_sysmmu` touches, against the v8.1 map:**

| Offset | Register | Access | Evidence |
|---|---|---|---|
| 0x0000 | CTRL | read, write `\| 0x5` (mode ≥ 1), restore on remove | read OK (E1); `__sysmmu_enable_nocount()` |
| 0x0004 | CFG | read | read OK (E1) |
| 0x0008 | STATUS | read | read OK (E1) |
| 0x0034 | VERSION | read | read OK (E1) |
| 0x0060 | INT_STATUS | read (dump; IRQ) | read OK (E1) |
| 0x0064 | INT_CLEAR | write (IRQ only) | Google's IRQ handler, all versions |
| 0x1010, 0x1014 | FAULT_ADDR_VA, FAULT_INFO0 | read (IRQ only) | read OK (F1); Google's v7+ path |
| 0x2004 | TLB_CFG(0) | write 0 (mode ≥ 1) | read OK (F1); Google's `__sysmmu_init_config()` |
| 0x8000+0x1000·vid | CTRL_VID | read, write (mode ≥ 1) | read OK (F1) |
| 0x8004+… | CFG_VID | read | read OK (F1) |
| 0x800c+… | PT_BASE_PPN_VID | read, write (mode ≥ 1) | read OK (F1) |
| 0x8010+… | FLUSH_VID | write (mode ≥ 1) | Google's `__sysmmu_tlb_invalidate_all()` |

**F2 (mode=0) only reads VERSION, CTRL, CFG, STATUS, INT_STATUS, CTRL_VID1,
CFG_VID1 and PT_BASE_PPN_VID1, and all of them read fine in E1/F1.** There
is nothing risky in it.

Build: `logs/{kernel,modules,images}-w4b.log`, release
`7.3.0-rc6-omamobile-push1-00097-g49b341b4a7bb`; standard test DTB in the
images, `gs201-cheetah.dtb.firewall` beside it. Merge `omamobile-w4`
(now `49b341b4a`) into omamobile-int, then F2-F4 as in 9.17. Also in
`wifi-w1-capture`: the `grep -q` checks are now `grep -c … >/dev/null`.
With `pipefail` and a large log, `grep -q` exiting early SIGPIPEd
`since_start` and silently skipped steps.

### 9.19 F4 failed: why, the table placement, new F3/F4 (2026-10-12, offline)

F2 passed and F3 "passed", but **F4 failed**: with an empty table on VID 1
(mode=2) brcmfmac came up normally and nothing was blocked. The firewall
was a no-op.

**Why F4 can pass on stock but fail here.** Stock enables the SysMMU
(`pcie_sysmmu_enable()`, VID from `pcie-vid-num` = 1) in the power-on path
before link-up, then swaps the Wi-Fi device's DMA ops so every buffer is
mapped **1:1** (IOVA = PA). So stock never shows that VID 1 really carries
the controller's traffic: a bypassed VID works just as well. Google's
sources contain no code that assigns a VID to the PCIe master:
- no AxUSER/VID field in the RC driver or the gs201 CAL;
- the only HSI2 sysreg write is shareability (0x730);
- the `soc` region write (`0x4000`) is a clock-source select, and gs201
  doesn't even map that region.

Our enable sequence matches `__sysmmu_enable_nocount()`. The capability
registers from F1 show the controller has **VM support** (`CAPA1` bit 14,
so 8 VIDs), **one port** and **one TLB**. So the master's traffic most likely
carries a VID other than 1, and that VID is not translating, so it passes
through untouched. The other possibility is that this SysMMU is not in the
Wi-Fi DMA path at all. The next run tells the two apart.

Also fixed: with VM support, the fault registers are per VID at
`0x1000 + 0x10·vid` (`0x1004 + …` for the info). The old 0x1010/0x1014
were VID 1's only.

**Table placement.** pt_base was an address (PPN << 12), and it really was
inside the pool. The cause: the SysMMU node used `memory-region = <&wifi_dma_pool>`.
For a restricted-dma-pool, `of_dma_configure()` gives that pool to the
SysMMU device as its own swiotlb, so `dma_map_single()` of the table
**bounced it into the window**. The chip could then have rewritten its own
page table. Fixes:
- the property is now `google,dma-window` (binding + cheetah DT), so the
  SysMMU device gets no pool;
- the driver refuses a table whose DMA address differs from its physical
  address or overlaps the window;
- the log says `table at 0x… (outside the window)`.

**New in `pcie_gs201_sysmmu`** (wt-pcie `omamobile-w4`: `aecc19faa`,
`528c3381f`, `841baece6`):
- `vids=<mask>`: the VIDs to translate (default: the DT's `google,vid`);
- `mode=3`: everything 1:1 **except** the window. Only DMA into the window
  faults, and nothing else lives there, so it is safe to turn on for all
  VIDs (`vids=0xff`). The "blocked" line names the VID;
- on remove, each VID's CTRL is restored.

Build: `logs/{kernel,modules,images}-w4c.log`, release
`7.3.0-rc6-omamobile-push1-00100-g841baece617c`. The images carry the
standard test DTB, with `gs201-cheetah.dtb.firewall` beside it (rebuilt:
it now has `google,dma-window`). **The old firewall DTB will not work:**
the driver no longer reads `memory-region`.

#### Runbook (after merging `omamobile-w4` @ `841baece6` into int)

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-pcie KERNEL_OUT=$HOME/android/mainline/out-pcie
O=$KERNEL_OUT D=$O/arch/arm64/boot/dts/exynos/google/gs201-cheetah.dtb
cp "$D.firewall" "$D"; bin/omamobile images && bin/omamobile modules-push && bin/omamobile push
reset_wifi() { tools/phone-ssh 'modprobe -r brcmfmac_wcc brcmfmac; modprobe -r pcie_gs201; modprobe -r pcie_gs201_sysmmu'; }

# F4a ⚠ find the VID: block only the window, on all eight VIDs
reset_wifi; tools/phone-ssh 'modprobe pcie_gs201_sysmmu mode=3 vids=0xff; dmesg | grep gs201-pcie-sysmmu | tail -12'
#   expect: "blocking only 0x…ff000000..0x…100000000, everything else 1:1",
#           "table at 0x… (outside the window)" with an address NOT in ff000000-ffffffff,
#           "enforcing: VID n ctrl 0x…1 … table at <same address>" for n = 0..7
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5
tools/phone-ssh 'dmesg | grep "blocked" | head -5'
#   pass: brcmfmac fails (timeouts) AND "blocked WRITE|READ at 0xff…… (… VID n …)": note n
#   no "blocked" lines and Wi-Fi works: this SysMMU is not in the Wi-Fi path at all → stop,
#     tell me (the firewall then has to be the S2MPU, probe groups 3-5)
#   UFS/USB/touch must be unaffected either way (nothing outside the window is changed)

# F4b ⚠ the real negative test, on that VID only (vids = 1 << n, e.g. 0x01 for VID 0)
reset_wifi; tools/phone-ssh 'modprobe pcie_gs201_sysmmu mode=2 vids=<1<<n>'
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5
#   pass: brcmfmac fails AND "blocked … (… VID n …)" lines
#   If the stuck master raises a fault storm: lines are rate-limited, and the watchdog is armed

# F3 ⚠ enforce on that VID, then Wi-Fi as W3
reset_wifi; tools/phone-ssh 'modprobe pcie_gs201_sysmmu mode=1 vids=<1<<n>; dmesg | grep gs201-pcie-sysmmu | tail -4'
#   expect: "allowing 0x…ff000000..0x…100000000 (16 sections)", "table at 0x… (outside the window)"
tools/wifi-w1-capture --watchdog --wait 40 --brcmfmac 5
tools/phone-ssh -t 'nmcli con up <SSID>'; tools/phone-ssh 'curl -o /dev/null -w "%{speed_download}\n" https://speed.cloudflare.com/__down?bytes=50000000; dmesg | grep -c "blocked"'
#   pass: connects, ~19-21 MB/s, 0 "blocked"
# rollback: reset_wifi; modprobe pcie_gs201_sysmmu (mode=0), or cp "$D.default" "$D" + the two test overlays
```

If n ≠ 1: put `google,vid = <n>` in the cheetah DT (one-line DT commit), and
`omamobile-wifi-start` needs nothing else. Nothing ships until F4b passes.

### 9.20 F4a/F4b/F3: the SysMMU is shared with UFS on VID 0 (2026-10-12)

Results on int 00151 (contains `841baece6`):
- **F4a** (`mode=3 vids=0xff`): Wi-Fi failed. One line: `blocked READ at
  0xff000000 (VID 0, AxID 0x0)`. **PCIe traffic is on VID 0.**
- **F4b** (`mode=2 vids=0x1`): blocked VID 0, AxID 0x2, at 0x8859b9000 and
  0x8859b90c0. Those addresses are the **UFS host's transfer request list**:
  `UTRLBA` = 0x8_859b9000 in the `host_regs` dump printed right after, and
  `UTMRLBA` = 0x8_859ba000.
- **F3** (`mode=1 vids=0x1`) only allowed the Wi-Fi window on VID 0. That
  starved storage and wedged the phone (`ufshcd_abort`, SCSI EH), and the
  display and SSH died after it.

**Conclusion: the HSI2 SysMMU at 0x145c0000 carries both the PCIe
controller (AxID 0x0) and UFS (AxID 0x2) on VID 0.** Any table on VID 0
that isn't a full 1:1 map confines storage too. The 0xff000000 read in
F4a is the chip's first access into the pool. Every brcmfmac buffer is
allocated against 01:00.0, which has the restricted pool, so nothing from
Wi-Fi was seen outside the window.

**Stock never shows this.** Stock DT gives `sysmmu_hsi2` `pcie-vid-num = <1>`
and enables VID 1, and UFS has no IOMMU. But stock maps every Wi-Fi buffer
1:1, so if PCIe also arrives on VID 0 there, stock's SysMMU is a no-op as
well, and nothing breaks.

Nothing in Google's kernel tree assigns a VID or AxUSER:
- PCIe RC driver (dwc and dwc-whi) and the gs201 CAL;
- the UFS driver (its only HSI2 sysreg write is IOCC);
- the SysMMU drivers.

If a VID mux exists, it is set before Linux (bootloader/EL3) or not at all.
The S2MPU is also selected per VID (`NR_VIDS` 8, `PROT_EN_PER_VID`), so it
can't separate the two masters either. There is no AxID-based protection
in either block: the SysMMU's `TLB_MATCH_ID` only steers TLB allocation.

**Change:** `pcie_gs201_sysmmu` now **refuses any mode that translates VID
0** unless `allow_vid0=1` (debug only). It still never enables VID 0 by
default, and the DT stays `google,vid = <1>`. On this hardware, mode 1 on
VID 1 is a harmless no-op. Commit `7ff22794d` (wt-pcie `omamobile-w4`),
release `7.3.0-rc6-omamobile-push1-00101-g7ff22794d119`, logs
`logs/{kernel,modules,images}-w4d.log`. Nothing that enforces is proposed.

**Options:**
1. **Restricted pool only (recommended for now).**
   - Every kernel-provided DMA buffer is in the 16 MiB window, as measured.
   - That protects against driver/DMA bugs and stray pointers, but not
     against hostile Wi-Fi firmware, which can still DMA anywhere.
   - The firmware is Broadcom's signed blob, the same as stock, and stock's
     own SysMMU appears to give no more protection.
   - Ship Wi-Fi this way with the firewall module not loaded.
2. **Deny-list on VID 0** (`mode=3`-style: everything 1:1 except selected
   regions):
   - Candidates are the kernel image (text/rodata) and reserved firmware
     carve-outs, which UFS never targets.
   - It blocks firmware patching kernel text, but not page tables or heap,
     so it's a partial mitigation.
   - The risk is storage: one wrong region and UFS stalls as in F3.
   - It needs its own staged runbook (read-only first, canary region,
     watchdog) and your agreement before anything is built.
3. **Find a VID mux:**
   - The only lead is an undocumented SYSREG_HSI2 field set before Linux.
     A read-only sweep of SYSREG_HSI2 isn't risk-free (the SysMMU 0x70 read
     aborted), so I don't recommend it without a register map.
   - A stock-Android root dump of SYSREG_HSI2 to compare against would
     settle it, but needs a stock device.
4. **IOMMU-free hardening:** keep the pool, keep the blacklist and the
   guarded start script, and load the newest firmware.

No runbook in this section: nothing new should run on the phone until we
pick an option. If you want a data point, F4a (`mode=3 vids=0xfe`, so not
VID 0) is now the only firewall test that still makes sense. It should show
**no** blocked lines and working Wi-Fi, which confirms PCIe never uses
VIDs 1-7.

### 9.21 W4 decision: ship with the restricted pool, no SysMMU (2026-10-12)

Derek chose option (a) from 9.20:
- Wi-Fi comes up at boot with the restricted DMA pool and the hang-safe
  start script;
- no SysMMU enforcement: the node is disabled and the module isn't loaded;
- this protects against driver bugs and stray pointers, not hostile
  firmware, which appears to be no worse than stock.

**Kernel** (wt-pcie `omamobile-w4`, on top of the pcie work):
- `7ff22794d` the SysMMU driver refuses VID 0 unless `allow_vid0=1`;
- `c0545e232` brcmutil decodes the 6 GHz band (band 0x4000) in d11ac
  chanspecs. This silences `WARN_ONCE("Invalid chanspec 0x5001")` from
  `brcmf_setup_wiphybands()` (0x5001 = 6 GHz ch 1, 20 MHz);
- `24cfee473` brcmfmac skips 6 GHz chanspecs quietly when building the
  channel list. 6 GHz support itself is future work;
- `242602382` cheetah DT: `pcie_1`, `pcie_1_phy` and `wifi_dma_pool` are
  enabled by default. `pcie_1_sysmmu` stays disabled, so the two test
  overlays (`wifi-pcie-test`, `wifi-dma-pool-test`) are no longer needed.

Build: release `7.3.0-rc6-omamobile-push1-00104-g242602382ed0`, logs
`logs/{kernel,modules,images}-w4e.log`. The images carry the plain
default DTB with no overlays.

**omamobile-device-cheetah 0.1.12:**
- `omamobile-wifi-start` no longer touches the SysMMU. It writes the hang
  marker, then:
  - exits quietly if `14520000.pcie` doesn't exist (DTB without Wi-Fi);
  - refuses if the `wifi-dma-pool` node is missing or disabled;
  - then `pcie_gs201`, then `brcmfmac`, then waits up to 30 s for the
    interface.
- `omamobile-wifi.service` is enabled by a vendor
  `multi-user.target.wants` link, with
  `ConditionPathExists=/sys/bus/platform/devices/14520000.pcie`.
- `modprobe.d/omamobile-wifi.conf` keeps `blacklist pcie_gs201` and
  `blacklist brcmfmac`. That only stops udev autoloading them ahead of the
  guard (explicit modprobe still works), so the service is the only loader
  and a hang skips Wi-Fi on the next boot.
- Tests check the staged files, the wants link, the blacklist, and that the
  script never passes `mode=`.

#### Runbook (merge `omamobile-w4` @ `242602382` into int; package 0.1.12)

```sh
# build/push the int kernel as usual (no DTB overlays for Wi-Fi any more), then:
bin/omamobile modules-push && bin/omamobile push          # reboots
# install omamobile-device-cheetah 0.1.12 on the phone (your usual package path), then
tools/phone-ssh 'nmcli con modify <SSID> connection.autoconnect yes'
tools/phone-ssh 'systemctl reboot'

# boot 1 (repeat for boot 2)
tools/phone-ssh 'uname -r; systemctl is-enabled omamobile-wifi; systemctl status --no-pager omamobile-wifi | tail -3;
  journalctl -b -u omamobile-wifi --no-pager | tail -3; ls /var/lib/omamobile/wifi-bringup-started 2>&1;
  lsmod | grep -E "^(pcie_gs201|brcmfmac|pcie_gs201_sysmmu) "; dmesg | grep -E "restricted|wifi-dma-pool" | head -3;
  dmesg | grep -cE "Invalid chanspec|WARNING"; nmcli -t -f DEVICE,STATE,CONNECTION dev | grep -i wl'
#   pass: enabled; "omamobile-wifi: up: wlp1s0" (or the renamed interface); no marker file;
#         pcie_gs201 + brcmfmac loaded, pcie_gs201_sysmmu NOT loaded; the pool assigned to
#         0000:01:00.0; 0 "Invalid chanspec"; NetworkManager connected to <SSID>
tools/phone-ssh 'curl -o /dev/null -w "%{speed_download}\n" https://speed.cloudflare.com/__down?bytes=50000000'
#   pass: ~19-21 MB/s
# if a boot hangs: after the watchdog reset, Wi-Fi is skipped and the journal says
#   "the last bring-up (...) never finished"; send that boot's log, retry with omamobile-wifi-start --retry
# rollback: systemctl disable is not possible for a vendor link; mask it instead:
#   systemctl mask omamobile-wifi.service   (or reinstall 0.1.11 and the previous kernel)
```
