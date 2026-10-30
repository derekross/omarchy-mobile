<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a modem and GNSS plan (tegu, Samsung S5300)

Status (2026-10-27): M0.1, M0.4 and M2.2 passed; FAR_ALIVE (GPA5, the
modem's cp2ap lines) is bound with its EINTs in the base DT
(FAR-ALIVE-PLAN FA1, FA2). M2.0-M2.4 passed: the modem powers up,
trains Gen1 x1 and enumerates as 144d:a5a5; M3-M5 passed: CPIF and cbd
boot it to **ONLINE** (Gen3 x2) with working IPC (pktproc), no SIM yet;
G1-G2 passed: gnssd loads Kepler's firmware and talks CHPP over SPI;
G3 partial: our HAL client starts sessions and the engine tracks
satellites, but the CHPP link over the GNSS SPI loses bytes and gnssd's
own watchdog resets Kepler (the "hardfault"); the clock and the transfer
cut are in derekross/linux-omarchy-mobile#138 (in review), and GNSS is parked without a
hardware probe (the owner's decision, 2026-10-29). The CP link hang with
frequent Kepler resets is open. Next: a stock GNSS capture, IOCC, the SIM.
The staged plan (sections F, K, U and runbooks M0.2-M6, G1-G4) is below,
with each step's results under it. Kernel branches `omamobile-tegu-modem` and `omamobile-tegu-gnssif`
(section K).

**The modem is an S5300, not an S5400** [V]: tegu builds Google's
`radio/samsung/s5300` CPIF (`devices/google/tegu/BUILD.bazel:62,108`,
`tegu_defconfig:4-16`), stock's `cpif` node says `mif,name = "s5300"`, the
vendor image's firmware is `g5300t-*` and cbd runs as `s5100sit`. "S5400"
appears only in the name of the GNSS include stock uses
(`zuma-cp-s5400-phone-gnss.dtsi`) and in a comment on AoC's `gnss-type`.
So the cheetah CPIF port (same S5300 driver) carries over almost unchanged.

The 9a's GNSS is the modem's own: stock's `cp_shmem` carries a
`GNSS_FW` region and its `gnssif` (`samsung,exynos-gnss`) talks to the modem
over SPI (`gnss@0`, `samsung,gnss-spi`, interrupt on gpa5-4). So GNSS needs
the modem up, but not a SIM. Following Derek's advice on issue #51, the
modem comes up for GNSS first, and the SIM (a prepaid physical one on a
T-Mobile-network MVNO, PIN off, activated on slot A) comes later.

## Safety

As cheetah's MODEM-PLAN: Linux never writes the modem's NV (`efs`,
`efs_backup`, `modem_userdata`, `persist`); the chroot works on
checksum-verified RAM copies. Check the partitions against the off-repo
backup before every modem session, and take a fresh read-only backup after
any stock Android boot (stock's modem stack writes them).

## M0.1, partitions against the backup (2026-10-27, passed)

Backup: `~/android/reference/tegu-protected-post-recovery-20261026T185656Z/`
(off-repo). On the palmtop, each partition found by `PARTNAME` in
`/sys/class/block/*/uevent`, read with `sha256sum` only:

| Partition | Matches the backup | Read-only | Mounted |
| --- | --- | --- | --- |
| efs | yes | ro=1 | no |
| efs_backup | yes | ro=1 | no |
| modem_userdata | yes | ro=1 | no |
| persist | yes | ro=1 | no |
| modem_a | yes | ro=1 | no |
| modem_b | yes (same as modem_a) | ro=1 | no |

---

Path abbreviations below:

- `G/` = Google's GPL zumapro kernel on omb, `~/tegu/kernel/private`
- `CP/` = `G/google-modules/radio/samsung/s5300` (tegu's CPIF, `CPIF-20220408R1`)
- `PC/` = `G/google-modules/soc/gs/drivers/pci/controller/dwc` (`pcie-exynos-gs.ko` +
  `pcie-exynos-zuma-rc-cal.ko`, `G/devices/google/zumapro/BUILD.bazel:132-133`)
- `GN/` = `G/google-modules/soc/gs/drivers/soc/google/gnssif_spi` (`gnss_spi.ko`, `gnssif.ko`)
- `D9/` = stock board overlay 9 (`~/android/reference/tegu-vendor-a-20261026/dtbo_a-9.dts`,
  "TEGU MP", board_id 0x60b06 rev 0x10000: the owner's board, AUDIO-PLAN)
- `T/` = our tegu tree on omb, `~/tegu/int-dt-20261026/kernel` (`991042e2e`)
- `L/` = our cheetah modem port, in `omamobile-int` (`~/android/mainline/linux`)
- `V/` = the owner-equivalent factory vendor image (cp3a.261005.005), read on
  omb with `debugfs` only; never committed

[V] = read in source, stock DT or our captures. [I] = inferred; each [I]
names the step that settles it.

## F. Facts the steps rely on

### F1. The modem link: PCIe channel 0 (HSI1 GEN3A_0)

Not the Wi-Fi channel. Wi-Fi is channel 1 (HSI2, `0x13120000`, PMU `0x3ec8`,
one lane), working through `probes/tegu-pcie1.c` (NOTES: wlan0 link up).

| Item | Value | Source |
| --- | --- | --- |
| Controller | `pcie@12100000`, `ip-ver` 0x987500, `ch-num` 0, max Gen3 | [V] `G/devices/google/zumapro/dts/zumapro-pcie.dtsi:11-58` |
| Regions | elbi 0x12100000+0x2000, soc 0x12110000+0x5000, udbg 0x12130000+0xd000, phy 0x12140000+0x3000, sysreg 0x12020000+0x2000, dbi 0x12400000+0x381000, pcs 0x12120000+0x5000, config 0x40ffe000+0x2000, ia 0x12170000+0x1000 | [V] same |
| Interrupts | SPI 414 (controller), 416-420 (MSI 0-4); 415 doorbell, 421 PCS unused | [V] `IRQ_PCIE_GEN3_2L_*_HSI1` in Google's `dt-bindings/interrupt-controller/zumapro.h` |
| Window | CPU 0x40000000, 0xff0000 bytes = PCI 0x14e00000 (board ranges); CPIF's doorbell `pci_db_addr` 0x14e60000 | [V] `zumapro-board-pcie-cp-s5300.dtsi`, D9/ `cpif` |
| Board | `num-lanes` 2, `use-sysmmu` true, `use-cache-coherency`, `use-msi`, `use-l1ss`, `perst-delay-us` 18000, `ep-device-type` 4 (modem) | [V] same file, D9/ fragment@61 |
| Pins | PERST# gph0-0 (output), CLKREQ gph0-1 (function 2, pull-up, drive X4); both power-down "previous" | [V] `zumapro-pinctrl.dtsi:840-854` |
| PMU | PHY control `0x3ec4` (bit 0 isolation bypass, bit 10 after PHY config, `rmw_priv_reg`) | [V] `zumapro-pcie.dtsi:56`, `PC/pcie-exynos-rc.c:3568` |
| Clocks | `pcie-clk-num = <0>`: stock's host names none; CMU_HSI1 gates at 0x2068-0x20e4 (DBI/MSTR/SLV ACLK, PHY APB/REFCLK, IA, UASC, SSMT) | [V] DT; offsets [I] from zuma's `cal-if/zuma/cmucal-sfr.c:1614-1635`, as HSI1-PLAN uses zuma CAL for G4 |
| Rails | LDO16M and LDO18M ("PCIE0") always-on in stock | [V] `zuma/dts/zuma-pmic.dtsi:411-440`; [I] left on, since our DT doesn't describe them (M0.2) |
| PHY sequence | channel 0's own branches of the CAL: external PLL (UDBG 0xC710/0xC700, lock poll 0xC704 bit 3), SOC 0x4004 selects it, ELBI 0x80 = 4, soft power reset 0x3a4, PMA reset 0x1400-0x1408, PMA/lane/PCS tables for 2 lanes, PLL/CDR/OC polls (PMA 0xA80 b0, 0x15C0 b4, 0x140C b7), PHY 0x32C = 0, ELBI 0x1078 = 1; power-down-clear and power-down differ from channel 1 | [V] `PC/pcie-exynos-zuma-rc-cal.c:38-225,276-724` (the `else` branches) |
| Host extras | UDBG 0xC800 &= ~(3<<5) for ch0 (ch1 writes 0x421); PCS 0x150 = 0x300D5 after power-on; APP_XFER_PENDING 1 before, 0 after each config access | [V] `PC/pcie-exynos-rc.c:3570-3576,3954-3962,1821-1832` |
| iATU | **no secure-ATU SMC on zumapro**: the host writes the unrolled outbound iATU itself (DBI + 0x300000) | [V] `PC/pcie-exynos-rc.h:299-309`, `PC/pcie-exynos-rc.c:1644-1690`; gs201's SMC 0x820020D8 is absent |
| IOCC | SYSREG_HSI1 + 0x704, bits 1:0 = 3 | [V] `PC/pcie-exynos-rc.h:240`, `:1988` |
| SysMMU / S2MPU | `sysmmu_hsi1` 0x12060000 (SPI 424) enabled by stock with CPIF's PCIe IOMMU (`CONFIG_LINK_DEVICE_PCIE_IOMMU=y`); S2MPU `s2mpu_s0_hsi1` 0x12090000 | [V] `zumapro-pcie.dtsi:60-73`, `tegu/dts/zuma/zuma-s2mpu.dtsi:85`; [I] both pass DMA untranslated under our boot, as HSI2's did for Wi-Fi and gs201's for cheetah's modem (M5) |

**What our tegu tree has (T/):** CMU_HSI1 (GPIO clock path only, no PCIe
gates registered), `pinctrl_hsi1` with gph0, `pinctrl_peric0` (gpp2/8/12/16),
`pinctrl_alive` (gpa3, gpa7), `pinctrl_far_alive` (gpa5, GPIO-only, its
EINTs not advertised: FAR-ALIVE-PLAN), and the four modem regions in
`zumapro-reserved-memory.dtsi` (F3). It has **no** `pcie_0`, PHY,
`sysreg_hsi1`, `sysmmu_hsi1`, CPIF or gnssif, no HSI0 USI3 (`spi_21`) and no
CMU_HSI0 USI3 clocks. The cheetah port (`L/drivers/soc/google/cpif/`,
`L/drivers/pci/controller/dwc/pcie-gs201-cp.c`) is in `omamobile-int`, not in
the tegu tree. The PMU owner routes only 0x3ec8 to the secure RMW for G4
(PMU-PLAN): 0x3ec4 needs the same routing.

### F2. Control lines (D9/ and `zumapro-board-cp-s5300-sit.dtsi`) [V]

| Line | Pin | Controller | Stock pin state |
| --- | --- | --- | --- |
| ap2cp_wake_up | gpp16-0 | PERIC0 0x10840000 | output, no pull, pdn previous |
| ap2cp_dump_noti | gpp16-1 | PERIC0 | same |
| ap2cp_pda_active | gpp16-2 | PERIC0 | same |
| ap2cp_cp_wrst_n | gpp16-3 | PERIC0 | same |
| ap2cp_cp_pwr_on | gpp12-2 | PERIC0 | same |
| ap2cp_nreset_n | gpp12-3 | PERIC0 | same |
| ap2cp_pm_wrst_n | gpp8-3 | PERIC0 | output (function 1), same |
| cp2ap_cp_ps_hold | gpa5-0 | FAR_ALIVE 0x154e0000 | input, no pull |
| cp2ap_wake_up | gpa5-1 | FAR_ALIVE | EINT, pull-down (**don't port the pull-down**: cheetah 2.1/6.3) |
| cp2ap_phone_active | gpa5-2 | FAR_ALIVE | EINT, no pull |
| cp2ap_cp_wrst_n | gpa7-3 | ALIVE 0x154d0000 | input, pull-down |
| gnss2ap_spi | gpa5-4 | FAR_ALIVE | EINT, pull-down, pdn previous |
| ap2gnss_spi | gpp2-3 | PERIC0 | output, no pull |
| S5910 SPMI clk/dat | gpa3-0/1 | ALIVE | bit-banged SPMI to the S5910 clock buffer |

Boot and power sequences are the same code as cheetah's [V]:
`CP/modem_ctrl_s5100.c:906-938` (`gpio_power_off_cp`, `gpio_power_offon_cp`)
is cheetah's section 1 to the millisecond; `start_normal_boot()` and
`s5100_poweron_pcie()` (`:1335`, `:1765`) likewise. The one addition: on
power-off stock first drives nreset low and runs the S5910's off sequence
(`:1081-1086`, `s5910,seq` = 0x215←0x0f, 1 s, 0x20e←0x04, 0x240←0x10). The
S5910 driver writes nothing at probe (`G/google-modules/soc/gs/drivers/misc/s5910/s5910.c:165-200`),
so the boot doesn't need it [V]; the modem stays on once up (cheetah M2.6),
so it isn't ported before a power-off test.

GPA5 is shared (WLAN host wake pin 3, TAS2572 pin 5, Bluetooth pin 6):
FAR-ALIVE-PLAN's bank-wide EINT ownership question is settled (FA2,
2026-10-27): the base DT gives Linux the whole bank, pins masked until a
consumer requests one.

### F3. Shared memory [V]

| Region | Address, size | Stock (`G/devices/google/zumapro/dts/zumapro-rmem.dtsi:96-118`) | Ours (`T/.../zumapro-reserved-memory.dtsi`) |
| --- | --- | --- | --- |
| cp_rmem | 0xea400000, 12 MiB | `exynos,modem_if`, rmem_index 0 | `cp@ea400000`, no-map (:159) |
| cp_msi_rmem | 0xf6200000, 4 KiB | rmem_index 1 | `cp-msi@f6200000`, no-map (:164) |
| cp_rmem_1 | 0xe8000000, 32 MiB | rmem_index 2 | `cp-extra@e8000000`, no-map (:154) |
| cp_aoc_rmem | 0x197fd000, 12 KiB | rmem_index 3 | `cp-aoc@197fd000`, no-map (:28) |

Stock's `cp_shmem` regions (D9/): IPC = cp_rmem +0, 8 MiB, cached; **GNSS_FW
= cp_rmem +0x800000, 4 MiB, cached** (why cp_rmem is 12 MiB here and 8 MiB on
gs201); MSI = cp_msi_rmem; PKTPROC = cp_rmem_1 +0, 0x1c00000; PKTPROC_UL =
cp_rmem_1 +0x1c00000, 4 MiB; VSS_AOC = cp_aoc_rmem (left out, as on cheetah:
never CPU-mapped). Our DT already matches; M0.2 checks them on the running
kernel.

### F4. CPIF: tegu against our cheetah port

[V] The same driver: 24 of the port's files are byte-identical to tegu's
`CP/`; in `modem_main.c` and `modem_ctrl_s5100.c` every difference is one of
the port's own changes (gpiod, no panics, permanent module, `allow_poweroff`,
the MSI and pktproc fixes). [I] the rest likewise (K4 diffs them all).

The stock nodes differ from cheetah's (`device/cheetah/overlays/modem-cpif-test.dtso`) only in:

- `mif,link_attrs` 0x37c8 vs 0x17c8: bit 13 `LINK_ATTR_XMIT_BTDLR_GNSS`
  ("GNSS FW on DRAM", `L/.../gs-include/dt-bindings/soc/google/exynos-cpif.h:146`).
  It makes CPIF map GNSS_FW and give the boot device the
  `IOCTL_LOAD_GNSS_IMAGE`/`READ_GNSS_IMAGE` ioctls (`CP/link_device.c:2124-2190,3746,3859`);
  already in our port, unused on cheetah. Bit 11 (SPI boot) is clear, so
  `cpboot_spi_bus_num = 15` is unused.
- two more iodevs: `gnss_boot` (ch 0xf0, raw, attrs 0x4200) and `gnss_dump`
  (ch 0xef, attrs 0x200).
- `cp_shmem` + GNSS_FW (F3); no `offset_boot_indicator` (cheetah 0x90);
  `mif_off_during_volte = 1`; `google,clk-buffer` (S5910, F2).
- line pin states and GPIO banks (F2). Everything else (legacy buffers,
  SBI fields, `pci_db_addr`, all 33 `pktproc_*`) is identical.

[V] Userspace is cheetah's shape (V/ `etc/init/cbd.rc`, `rfsd.rc`,
`build.prop`): `cbd -d -t s5100sit -P by-name/modem${slot} -s 2`, `rfsd -d`,
`/mnt/vendor/modem_img` = by-name/modem (ext4, `fstab.modem`). The
partition is the same tar/ext4 polyglot as cheetah's (ext4 magic at 0x438
of the backup's modem_a [V]). cbd's strings add `nv_5g_data.bin`,
`nv_data.bin`, and TN/NTN image selection (`vendor.cbd.modem_bin_type`,
`/vendor/firmware/{stable,ntn}_modem`): keep type 0. It still reads
`ro.boot.cdt_hwid` / `persist.vendor.modem.cdt_hwid` (present in the private
2026-10-20 getprop capture) and `/chosen/{plat,config}`.

### F5. GNSS

[V] Kernel (`GN/`, `CONFIG_EXYNOS_GNSS_IF_SPI`, about 1,300 lines):
`gnss_spi.ko` binds `samsung,gnss-spi` on `spi_21`; `gnssif.ko` binds
`samsung,exynos-gnss` ("KEPLER") and creates `/dev/gnss_ipc`: an SPI byte
pipe with a request/ready handshake (gnss2ap_spi gpa5-4 high-level IRQ, wake
source; ap2gnss_spi gpp2-3 output, starts 0). No regulator, clock or PMU of
its own: the Kepler core is inside the S5300, runs firmware the AP puts in
GNSS_FW, and needs the CP ONLINE.

[V] `spi_21` = HSI0 USI3 at 0x111e0000, SPI 409, `sysreg_hsi0` + 0x1020,
`pd_hsi0` (`G/devices/google/zumapro/dts/zumapro-usi.dtsi:1184-1201`);
CMU_HSI0 USI3 mux 0x1020, div 0x1820, gates 0x2124/0x2104/0x2108/0x20d0
(zuma CAL, USI2's +4, and USI2 is qualified for touch on SPI20). Stock MP
board: `gnss@0` at 3.125 MHz, `swap-mode`, no DMA (D9/ fragment@110).

[V] Userspace (V/): `/vendor/bin/hw/gnssd` (Samsung's engine, user `gps`),
bionic only (`libc++ liblog libm libandroid_net libssl libcrypto libcurl libz
libcutils libdl libc`): **no binder**, so it fits the vendor chroot as lhd/gpsd
did on cheetah. `/vendor/etc/gnss/gps.cfg`: device K041, patch file
`/vendor/firmware/kepler.bin` (about 1 MB), data port CHPP over
`/dev/gnss_ipc`. Its strings open `/dev/gnss_boot` (`GNSS_IOCTL_LOAD_GNSS_IMAGE`),
`/dev/gnss_dump`, `/dev/umts_boot0` (it waits for the CP to boot) and
`/dev/umts_ipc0` (SIT, control-plane assistance), and use `/data/vendor/gps`,
`/sys/power/wake_lock`, `/sys/devices/soc0/{machine,revision}` and
`/sys/devices/system/chip-id/evt_ver`. The framework HAL
(`android.hardware.gnss-service`) needs binder: not used. [I] NMEA leaves
gnssd through its HAL socket and, optionally, a `%s/nmea` output and
`gnss_nmea_<time>.txt` logs (`NmeaBitmask`, `SpotLogger_Allowed` in gps.cfg);
which one Linux can read is G0's question.

## K. Kernel work (offline, omb)

Branch `omamobile-tegu-modem` in `~/tegu/wt-modem`, output
`~/tegu/out-modem`, based on `T/` (`991042e2e`); GNSS in its own branch
`omamobile-tegu-gnssif` (`~/tegu/wt-gnssif`, `~/tegu/out-gnssif`). Each piece
builds `W=1` clean, passes `checkpatch --strict` (imported Google files keep
Google's style, as on cheetah), `dt_binding_check` and `dt-validate`.

- **K1, the link driver.** The cheetah driver's state machine and CPIF API
  (`pcie-gs201-cp.c`: steps `cp_on`/`cp_off`/`link_up`/`link_down`/`bus`,
  `allow_hw`, faults, the DBI guard `4b1364136`) with a zumapro variant,
  `google,zumapro-pcie-cp`: channel 0's CAL tables extracted mechanically
  into a `tegu-pcie0-seq.h` as was done for channel 1; the ELBI quirks
  `tegu-pcie1` already proved (APP_XFER_PENDING); PMU 0x3ec4; IOCC through
  `sysreg_hsi1`; and, instead of the SMC, the DesignWare core's own unrolled
  iATU (config window 0x40ffe000, memory window 0x40000000 → PCI 0x14e00000).
  The PHY tables belong in the planned `google,zumapro-pcie-phy` variant
  (WIFI-PLAN "Host glue"), as per-channel data.
- **K2, PMU.** Route 0x3ec4 to the secure RMW as PMU-PLAN does for 0x3ec8.
- **K3, DT (base, all disabled).** `sysreg_hsi1` (0x12020000); `pcie_0` +
  its PHY; the documented `samsung,s5300-modem` child with the eleven lines
  and the three regions (cheetah's binding, 2.1 "where the lines live");
  `pcie0_clkreq`/`pcie0_perst` pin states; no `sysmmu_hsi1`. Runtime
  overlays as tegu does (`tegu-pcie1-enable.dtso` + an activate module): the
  tegu base has symbols, so `cpif` and `cp_shmem` can be an overlay with
  phandles (`tegu-modem-cpif.dtso`, stock's nodes from D9/ minus VSS_AOC,
  pktproc in a second overlay as on cheetah).
- **K4, CPIF.** Bring the port from `omamobile-int`
  (`L/drivers/soc/google/cpif/`, `shm_ipc`), rename the compat layer to a
  link-neutral API (`pcie-gs201-compat.c` calls whichever link driver
  registered), diff every file against tegu's `CP/`, and build
  `EXYNOS_MODEM_IF=m`, `SEC_MODEM_S5100=y`, `SHM_IPC=m`,
  `CH_EXTENSION=y`, `CP_PKTPROC(_UL)=y`, `LINK_DEVICE_PCIE_IOCC=y`, no
  `S5910`, no PCIe IOMMU.
- **K5, gnssif.** Import `GN/` verbatim (one commit), then port: gpiod, no
  `BUG()`, IRQ requested at open rather than probe (so loading it can't
  take a GPA5 interrupt early), Linux 7.3 API drift. Module
  `gnssif`, blacklisted until G1.
- **K6, the GNSS SPI.** CMU_HSI0 USI3 clocks (USI2's code, +4), `usi3_hsi0`
  + `spi21` (disabled) beside the touch's USI2/SPI20.

## U. Userspace work (offline, this repo)

- **U1, `omamobile-modem` for tegu.** Today it is cheetah's: it loads
  `pcie-gs201-cp` (`lib/omamobile-modem-start:29-37`) and its props say
  `ro.boot.hardware.platform=gs201`, `ro.hardware=cheetah`
  (`modem/props.conf:10-11`). Make the link module and those two values
  per device (zumapro, tegu), add `nv_5g_data.bin`/`nv_data.bin` to what
  the profile expects in the efs copy (checksums only where stock has a
  salted one), and blacklist `cpif`, `shm_ipc` and the link module in
  `omamobile-device-tegu`. NV handling, start order, stop rule and markers
  stay exactly as cheetah's.
- **U2, the chroot image.** `tools/extract-vendor-chroot -p modem` on the
  owner's tegu factory image (on maclab, small result back), plus a new
  profile `gnss-kepler`: `gnssd`, `kepler.bin`, `gps.cfg`, `ca.pem`, and
  stand-ins for `/sys/devices/soc0/*` and `chip-id/evt_ver` (values from the
  private stock capture, never committed).
- **U3, the GNSS package.** `omamobile-gnss` (cheetah: Broadcom lhd/gpsd) gets
  a Kepler backend: start gnssd only after `omamobile-modem` reports
  ONLINE, then the same NMEA → gpsd → GeoClue bridge (`omamobile-gnss-nmea`)
  and Location tile. Which NMEA source the bridge reads is G0's answer.

## Runbooks

Every step: kmsg streamed to the laptop first (`tools/phone-ssh 'cat /dev/kmsg' > logs/tegu-modem-<step>.log &`),
the UFS check after it (`dmesg | grep -c ufshcd_err_handler` and the
13200000.ufs debugfs stats against the count before), and M0.1's checksums
before any step that runs a modem daemon. Stop rule everywhere: an Oops,
an I/O error, a UFS handler pass outside a modem power change, or an NV
mismatch. A hang: wait for the watchdog; if it doesn't come back, the human
forces a restart (the only physical action in this plan).

### M0.2-M0.4: read-only, current kernel (risk: none)

```sh
# M0.2 memory, chosen, packages
tools/phone-ssh 'ls /sys/firmware/devicetree/base/reserved-memory | grep -E "^cp"; grep -iE "e8000000|ea400000|f6200000|197fd000" /proc/iomem'
tools/phone-ssh 'ls /sys/firmware/devicetree/base/chosen'          # names only: plat, config present?
tools/phone-ssh 'systemctl is-enabled omamobile-modem omamobile-gnss 2>&1; ls /etc/modprobe.d'
tools/phone-ssh 'ls /sys/bus/platform/drivers | grep -iE "pinctrl|gpio"; ls /sys/kernel/debug/pinctrl'
# M0.3 the lines, where their controller is bound (record, change nothing)
tools/phone-ssh 'P=/sys/kernel/debug/pinctrl; grep -hE "\((gpp16-[0-3]|gpp12-[23]|gpp8-3|gpp2-3)\)" $P/*10840000*/pins;
  grep -hE "\((gpa3-[01]|gpa7-3)\)" $P/*154d0000*/pins; grep -hE "\((gpa5-[0124])\)" $P/*154e0000*/pins;
  grep -hE "\((gph0-[01])\)" $P/*12040000*/pins'
```

- Expect: the four `cp*` nodes, none listed as System RAM; omamobile-modem
  and omamobile-gnss disabled (they are cheetah's builds; leave them
  installed and disabled); outputs low or inputs, cp2ap inputs low (the CP
  is unpowered).
- Record: `PUD` of gpa5-1 (cp2ap_wakeup) as left by the bootloader: keep it
  (cheetah lesson). `plat`/`config` presence decides U1's chosen binds.
- Stop: an ap2cp output high or a cp2ap input high (the bootloader left
  the CP powered): record it; plan a power-off step before M2.
- **M0.4 (one probe build, read-only):** a fixed CMU-only observer, as
  WIFI-PLAN W2, for the CMU_HSI1 PCIe gates (F1), and the existing PMU
  regmap reader, as W3, for 0x3ec4. Expect gates on (`clk_ignore_unused`
  is on the command line), 0x3ec4 bit 0 clear (isolated). Stop on any
  read of a controller/PHY block: not in this step.

### M1: build (offline; risk: none)

K1-K4 and U1-U2; boot nothing. Pass: builds and checks above; `modinfo`
dependencies `cpif` → `shm_ipc`, the link module; the overlay applied to the
DTB offline with `fdtoverlay` matches D9/'s `cpif`/`cp_shmem` property by
property except the documented gaps; `git merge-tree` against the tegu int
branch clean.

### M2 results (2026-10-27, `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`)

[V] K1 is `probes/tegu-pcie0-cp.c`: cheetah's `pcie-gs201-cp.c` with
channel 0's CAL tables (`tegu-pcie0-seq.h`) in place of the PHY driver,
the host's own unrolled iATU in place of the SMC, APP_XFER_PENDING raised
for training and dropped after, no CMU_HSI1 clocks and no IOCC sysreg yet.
Runtime overlay `overlays/tegu-modem-link.dtso` through
`probes/tegu-modem-link-activate.c`. Builds W=1 clean; checkpatch: two
alignment checks. Logs: `logs/tegu-modem-20261027/` (m2-, m23-kmsg).

- **M2.0 passed.** Overlay id 11, the driver binds: every line as M0.3,
  PERST# asserted, PMU 0x3ec4 0xc0, "steps enabled, modem lines here". The
  overlay's `pcie0-clkreq`/`pcie0-perst` pin groups are refused ("invalid
  function ... in map table"): Samsung pinctrl takes groups only at its own
  probe. PERST# works as a plain GPIO; CLKREQ# stays an input. Both groups
  go in the base DT with the next DTB.
- **M2.1 failed, then passed.** With ABL's pulls (every GPA5 pin
  pull-down) the outputs switched (CON 1, DAT 1 on pwr-on, nreset, wrst,
  pm-wrst, pda-active) but all four cp2ap lines stayed 0 for 10 s. With
  cp2ap-wakeup pulled up and ps-hold and phone-active floating (stock's
  "no pull"; the new `bias` step), **cp2ap-wakeup and cp2ap-phone-active
  went to 1 within 0.5 s** and back to 0 at `cp_off`. ABL's pull-down
  hides the modem's lines, as stock's pull-down did on cheetah (2.1).
  cp2ap-ps-hold and cp2ap-cp-wrst stay 0 (no firmware yet).
- **M2.2 passed** earlier (0xc0, set 0x1, cleared 0xc0).
- **M2.3 passed.** `link_up`: PHY out of isolation (0x3ec4 = 0x1, 0x401
  after bit 10), no PLL, CDR or offset-calibration poll missed, DBI ID
  0xa5a5144d, **"link up: Gen1 x1 (target Gen1), try 1"**, LTSSM 0x11.
  `atu`: config 0x40ffe000 to bus 1, memory 0x40000000 to PCI 0x14e00000.
  `id`: **endpoint 144d:a5a5**, the S5300's ROM.
- **M2.4 passed.** `bus`: 0001:00:00.0 root port 144d:ecec, 0001:01:00.0
  144d:a5a5 class ff0000, BAR 0 (64-bit) and BARs 2-5 1 MiB each at
  0x40000000-0x404fffff, "MSI ready, irqs on". `link_down`: PHY isolated,
  0x3ec4 back to 0xc0; `cp_off`. No `ufshcd_err_handler` line through the
  whole session; Wi-Fi (0000:01:00.0) stayed up.

Next: the base DT gets the pull fix (FAR_ALIVE hog: gpa5-0 and gpa5-2 no
pull, gpa5-1 pull-up) and the PCIe0 pin groups; then K4 (CPIF) and M3.

### M3-M5 results (2026-10-27, same kernel)

[V] K4 is cheetah's CPIF port built unchanged against the tegu tree
(`cpif.ko`, `shm_ipc.ko`, with `tegu-pcie0-cp.ko` in one M= build,
`CONFIG_` choices as cheetah's fragment), W=1 clean. Overlay
`overlays/tegu-modem-cpif.dtso` through `probes/tegu-modem-cpif-activate.c`.
U2: `tools/extract-vendor-chroot -p modem -d tegu` on the BP3A.250905.014
factory image (slot A's build) on maclab: 30 files, 12 MB, installed in
`/usr/lib/omamobile-vendor/modem/` on the palmtop (never committed).
Per-palmtop props: `ro.hardware=tegu`, `ro.boot.hardware.platform=zumapro`
and `ro.boot.cdt_hwid` from the private capture; NV checksums from the
2026-10-26 backup.

- **M3 passed.** CPIF binds with the modem off: `umts_boot0`, `umts_ipc0/1`,
  `umts_rfs0`, `umts_router`, `gnss_boot`, `gnss_dump` and the rest, 30
  rmnet, "GNSS_FW 0xeac00000 0x00400000", "gnss_v_base=", PMU 0xc0, every
  output low.
- **M4 passed** after one profile fix: tegu's `persist` is f2fs, not ext4
  (`profiles/modem.conf` now mounts the RAM copy by type). Five RAM copies
  match the backup, the three salted NV checksums match, baseband
  g5300t-250605-250630-B-13713258; rfsd: Touch, IsCsumCorrect, Verified,
  "file is ok"; no Expand, Create or Clear.
- **M5, first try: the ROM stopped.** ROM link Gen1 x1, s51xx probe and
  doorbell fine, boot image at 0xEA410000, then boot_stage 0xFF -> 0x1FF and
  "check_cp_status fail", err_report 0x2000. The port maps cached regions
  write-back because stock's link is I/O coherent; ours has no IOCC yet, so
  the ROM could read stale memory. The profile's stop left the CP in
  BOOTING; `omamobile-modem-cp power-off` turned it off cleanly.
- **M5, second try: CP ONLINE.** IPC and GNSS_FW marked `region,cached = 0`
  (write-combine): boot_stage 0xFF -> 0x3FFF, "link up: Gen3 x2 (target
  Gen3), try 1" for the boot loader, PHONE_START, INIT_END, "CP ONLINE (cbd
  exit 0)" about 2 s after the power-on. No SIM. No UFS error-handler pass,
  no SysMMU or S2MPU fault, Wi-Fi unaffected.

- **The CP's IPC needs the packet processor.** With legacy buffers only
  the AP advertised capability 0x2 (stock 0x3), and the CP never took a
  frame: NORM_RAW tx 432/0, rfsd idle, CP2AP_WAKEUP held high (cheetah's
  pre-M4.1h picture). With stock's pktproc properties in the overlay (all
  regions uncached, `use_hw_iocc` 0, as the link has no IOCC): within 60 s
  FMT rx 1712/1712, NORM_RAW tx 10912/10912 and rx 690480/690480 (rfsd's
  traffic both ways), "cp2ap_wakeup:0 ap2cp_wakeup:0 pcie_powered_on:0" (the
  idle link power-down) and seven clean link cycles ("link up: Gen3 x2",
  "bus already registered, MSI re-armed", "PHY isolated"), UFS 0.
- A second CP boot in the same Linux boot, after IPC had run, stopped in
  the ROM (boot_stage 0x0, err 0x0: the ROM never answered). After a CRASH_EXIT
  without IPC a second boot worked. Until that is understood: reboot
  before booting the CP again.
- The profile's stop is the unit's ExecStop; my first test units had none,
  which is why the CP stayed up after `systemctl stop`.

Open: IOCC (SYSREG_HSI1 + 0x704) so IPC and pktproc can be cached as
stock; the second-boot stall; M6 (reboots with the CP up) not run: stop
the unit (its ExecStop powers the CP off) before a reboot.

On the palmtop, `/usr/local/bin/omamobile-tegu-modem-up` (source
`logs/tegu-modem-20261027/phone/`) does M5 in one step: the modules from
`/var/lib/omamobile-tegu/modem/`, the profile as the transient unit
`omamobile-tegu-modem` with the profile's stop as ExecStop, ONLINE within
about 10 s; it refuses a second start in the same boot.

### G1-G2 results (2026-10-27, same kernel plus the GNSS1 Image)

[V] K6: CMU_HSI0 USI3 clocks (IDs 28-32: mux 0x1020, divider 0x1820, gates
0x2124, 0x2104, 0x2108, USI2's layout), `usi3_hsi0` and `spi21` in
zumapro.dtsi, `gnss@0` and `gnssif` in the board dtsi
(`patches/zumapro-tegu-gnss-kernel-20261027.patch`). K5: `gnssif/` is
Google's gnssif_spi ported: GPIO descriptors (`gnss2ap-spi-gpios`,
`ap2gnss-spi-gpios`), 8-bit SPI words (stock's 32-bit words with the vendor
SPI driver's byte and half-word swap put bytes on the wire in memory
order; mainline has no swap mode), sscoredump stubbed, the remove() API,
W=1 clean. U2: `-p modem -d tegu` also extracts gnssd, kepler.bin, gps.cfg,
ca.pem and the CA store (188 files, 22 MB).

- **G1 passed.** spi21.0 at boot; gnss_spi and gnssif bind with the CP off:
  `/dev/gnss_ipc`, gnss2ap on gpa5-4 as EINT (Linux IRQ 87), ap2gnss gpp2-3
  output low. USI3 ipclk 24.96 MHz (399.36 / 16), SPI about 3.1 MHz.
- **G2 passed** after two fixes. Started 0.6 s after ONLINE without pktproc,
  gnssd's first message on gnss_boot (cmd 0xC2) was followed 0.8 s later
  by the CP's CRASH_EXIT (crash reason empty). With pktproc and gnssd 20 s
  after ONLINE: "pcie_init modem available", two `IOCTL_LOAD_GNSS_IMAGE`
  (kepler.bin into GNSS_FW), "state: CODELOAD->OPERATIONAL", then "GNSS
  ASSERT: chppPlatformNotifierWait in STATE_PERMANENT_FAILURE": about half
  the bytes from Kepler arrived one bit late ("68 43" read as "34 21",
  gnssif's packet dump), Kepler changing its data on our sampling edge.
  With `samsung,spi-feedback-delay = <2>` (DTB GNSS2): every frame starts
  "68 43", CHPP sequence numbers advance, no assert, and the chip reports
  itself in `/data/vendor/gps/chip.info`: "S.LSI,K041,
  SPOTNAV_4.15.4_5_250417_R1".
- **G0, found:** gnssd listens on the abstract Unix socket `@GNSSND` (and
  `@GNSS_ISM_CAPTURE_PLAYBACK`); stock's `android.hardware.gnss-service.pixel`
  connects there. Positions need a client that speaks that protocol, or
  gnssd's NMEA file output (`%s/nmea`, `SpotLogger_Allowed`, overlay config
  `/data/vendor/gps/overlay/gps_overlay.conf`). Next GNSS step.

### G3, partial (2026-10-27)

[V] Stock's chain is gnssd <- `@GNSSND` <- Samsung's AIDL HAL
`/vendor/bin/hw/android.hardware.gnss-service` (init `slsi_gnss_service`,
registers `android.hardware.gnss.IGnss/vendor`) <- the Pixel HAL
(`IGnss/default` for the framework). Ours: the `gnss-slsi` chroot profile
(packages/omamobile-gnss) runs servicemanager, the image's
vndservicemanager (vendor processes use `/dev/vndbinder`; the system
servicemanager refuses their "VNDR" parcels) and the Samsung HAL, and
`omamobile-gnss-client` (bionic/gnss-aidl, NDK, transactions written by
hand from the frozen AIDL V3: setCallback 1, start 14, setPositionMode 20,
startNmea 25; callbacks location 4, NMEA 5).

- The HAL registers ("IGnss V3 service added successfully"), the client
  connects, capabilities 0xe7df, setCallback, setPositionMode, start and
  startNmea all ok, status SESSION_BEGIN, then ENGINE_ON / ENGINE_OFF
  every few seconds and no NMEA.
- Why: at each engine start **Kepler's M7 hard-faults**, the same way every
  time ("KEP M7 HARDFAULT ... LR,PC 600B5B39 0000062C", gnssd logs a 1 MB
  fault dump through SIT), gnssd goes UNUSABLE, reloads the patch and the
  next start faults again. The CP stays ONLINE. Seven faults in 3 minutes
  (`logs/tegu-modem-20261027/g5-gnssd.log`).
- Just before it: "aiding_timemark_reader_thread: open() errno:2" (gps.cfg
  `ChipCfg_Timemark_Option=1`, `Is1PPSTimeSyncEnable=1`), and gnssd reads
  `/sys/devices/soc0/{machine,revision}` and
  `/sys/devices/system/chip-id/evt_ver`, which neither our kernel nor the
  chroot has. Also unknown: the GNSS RF front end's clock (the S5910
  buffer's outputs; stock has only its off sequence) and whether GNSS_FW
  must be cached and coherent as on stock.
- Kepler's soft watchdog wrote two 6 MB RAM dumps
  (`/data/vendor/gps/soft_dog_*_system_ram.bin` in the modem chroot's state,
  private). Their formatted text has "TEST4 ENB ACQCLK and RF", "TEST2 ENB
  ACQCLK" and **"Error: FCAL Part 1 is not done yet."**: the RF front end's
  frequency calibration hasn't finished when the engine starts. persist has
  no GPS files (read-only copy, 2026-10-27), so its calibration is likely in
  the modem's NV, which the CP has, or comes from a step stock's HAL or RIL
  triggers.
- Not the SIT channel itself: with umts_ipc0/1 bound into the chroot,
  gnssd still never opens them (its SIT traffic goes through RIL,
  libsitril-gps) and the fault is unchanged. The CP, meanwhile, sends
  unsolicited SIT messages to umts_ipc0 that nobody reads ("umts_ipc0->recv_skb
  fail (-19)"). It may need a RIL up before it powers the GNSS RF path:
  that ties G3 to the SIT client (cheetah's omamobile-modem-sit) the SIM
  stage needs anyway.
- **The SIT stack works on the 9a unchanged** (omamobile-modem-sit 0.3.3,
  plain `omamobile-sitd` without `--bringup`): "SIM: absent; radio: off",
  GET_RADIO_POWER, GET_PS_REG_STATE and GET_SIM_STATUS all error 0. With
  sitd up, and after `omamobile-sit radio on` (no SIM: the CP stays in
  POWER_OFF), Kepler still faulted on engine start; after six faults gnssd
  gave up ("chppPlatformNotifierWait in STATE_PERMANENT_FAILURE").
- Correction (2026-10-27, night): a stock reference can't come from this
  palmtop. Arch is on `userdata`, so stock Android on slot A can't mount its
  data and stops in recovery (HANDOFF, 10-26 slot A fallback). It needs a
  second 9a, or a factory reset and a reinstall. Was: boot slot A once with
  root and capture `logcat -b all` and dmesg while an app gets a fix (gnssd, the HAL, CPIF's gnss
  lines, the timemark device it opens), then compare; or decode the fault
  dump. Then the NMEA FIFO into omamobile-gnss-nmea, as cheetah.

### G3, second try (2026-10-27, night, same kernel plus the fp1 DTB)

- **The SoC identity files are not it.** gnssd reads
  `/sys/devices/soc0/{machine,revision}` and
  `/sys/devices/system/chip-id/evt_ver`. `probes/tegu-socinfo.c` registers
  them with stock's values in the formats of Google's GPL `gs-chipid.c`
  (machine "ZUMA PRO TEGU MP on ZUMA PRO", revision 16, EVT1.0; fixed, no
  register read). With them present, every code reload after a fault still
  ended in the same "KEP M7 HARDFAULT ... LR,PC 600B5B39 0000062C". The
  `%s/dcxo` path in gnssd is its own store of learned oscillator corrections
  (`cm_dcxo_corrections.bin`), not an input. Stock's S5910 node has only an
  off sequence (Google's driver also reads an optional `s5910,on_seq`,
  which tegu doesn't set), so the AP doesn't switch the RF clock on either.
  G3 stays blocked on a stock capture.
- **gnssd's exit took the modem down.** After about ten faults gnssd gives
  up and exits; the vendor-chroot supervisor then stops the whole modem
  profile (rfsd too), and the unit's ExecStop runs the CP power-off. On
  the second try the CP stayed ONLINE (power-off didn't complete); on the
  first, the profile stopped the same way about 20 s after ONLINE and the
  palmtop hard-reset with the journal's last 40 s lost, a file written just
  before it empty. Suspect: the CP power-off path on tegu, untested so far.
  omamobile-modem 0.1.7 runs gnssd as an optional daemon, so its exit no
  longer stops the profile. Until M6 qualifies the power-off, don't stop the
  modem profile by hand; reboot with someone at the palmtop.
- **gnssd's custom GNSS library (2026-10-28, omamobile-modem 0.1.8).** An
  `strace` of gnssd found two gaps. gps.cfg sets
  `GlueLayer_IsUseCustomGnssLib=1`, and gnssd `dlopen()`s
  `/vendor/lib64/libcustomgnss.so` (ENOENT), which waits for the CP at
  `/sys/bus/platform/devices/cpif/modem_state` and then `dlopen()`s
  `libsitril-gps.so`, which uses `libsitril-client.so` (RIL's GPS channel,
  over binder to the radioExternal HAL). Nothing links the three, so the
  extractor never copied them; they are `VENDOR_LIBS` of the tegu modem
  profile now, and the chroot binds cpif at its bus path too. With both,
  libcustomgnss logs "Modem state ONLINE"; `GpsOpen()` still fails (no
  radioExternal HAL in the chroot: no binder), and Kepler still faults at
  every engine start. A re-run of the extractor on the BP3A factory image
  (2026-10-29) resolves everything: 195 files against 188, the three
  libraries plus libbinder, libbinder_ndk, libapexsupport and the
  radioExternal NDK library, nothing new to stub. **An existing 9a chroot
  gets the libraries only when its owner re-extracts** (`tools/extract-vendor-chroot
  -p modem -d tegu` on the factory image, then the install line from its
  usage text); a chroot from before 0.1.8 keeps running without them, as
  before. The second `/sys` bind is in every phone's modem profile and is
  harmless on the 7 Pro and the 6 Pro: cbd never looks there.

### G3, third try: rails on (2026-10-28, `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`, round ps1 DTB with ldo9s-11s on)

[V] With LDO9S-11S on, Kepler loads, reaches OPERATIONAL and no longer
logs "FCAL Part 1 is not done yet": the RF front end calibrates now. The
gnss-slsi HAL and our client start a session (capabilities 0xe7df, start
and startNmea ok, status SESSION_BEGIN then ENGINE_ON), but every engine
start still ends in the same fault: "KEP M7 HARDFAULT ... LR,PC 600B5B39
0000062C" (16 times in 10 minutes, ENGINE_ON/ENGINE_OFF each time), no
NMEA. So the rails were one missing piece, not the fault itself. Indoor or
outdoor doesn't matter yet: the engine crashes before it searches.
The G3 script's HARDFAULT count missed these (gnssd wrote them outside its
window).

### G3, fourth try: the AoC told the GNSS type (2026-10-28, evening, gn3 DTB)

[V] With `&aoc { gnss-type = <2>; }` (kAOCGnssType, as Google's
`zumapro-phone-ignss.dtsi`), Kepler loads, goes OPERATIONAL, and the
gnss-slsi HAL and our client start a session (startNmea ok, "the HAL asks
for a location"). But every engine start still ends in the same "KEP M7
HARDFAULT ... LR,PC 600B5B39 0000062C" (20 in 4 minutes), so the type isn't
it. In the register dump, R3 = 0x62D and PC = 0x62C: the M7 jumped
through a function pointer holding 0x62D, a Thumb address near zero, which
looks like an entry nobody filled in. Other leads from the logs:
`aiding_timemark_reader_thread: open() errno:2` (gnssd can't open its
time-mark device), `TGT_MEMS initInterface: fromBinder() failed` (the HAL's
sensor service is missing), and `libsighandler.so` not found. Next, attended
and on the charger, with the modem up: `strace -f` gnssd across one engine start, to see which
files and devices it opens or fails to open (observation only).

### G3, fifth to eighth tries (2026-10-29, night, same kernel, on the charger, outdoors spot)

- **strace of gnssd across engine starts** (the g7 scripts, commit 8d77391d9 of [linux-omarchy-mobile#137](https://github.com/derekross/linux-omarchy-mobile/pull/137)):
  the HAL's request reaches gnssd, gnssd talks CHPP to Kepler over
  `gnss_ipc` normally (the all-zero reads after each write are the SPI
  full-duplex bytes Google's `send_betp` passes up by design), and Kepler
  stops answering a few seconds after the engine start; gnssd then reads the
  GNSS image back (`IOCTL_READ_GNSS_IMAGE`) and dumps RAM. `umts_boot0`
  ioctl 0x28 (EINVAL, not in our CPIF) comes after the fault, in the crash
  path.
- **Missing libraries**: gnssd `dlopen()`s `libcustomgnss.so`
  (`GlueLayer_IsUseCustomGnssLib=1`), which needs `libsitril-gps.so` and
  `libsitril-client.so` (RIL's GPS channel, binder to radioExternal). All
  three were missing from the chroot. With them in, libcustomgnss reads the
  CP state from `/sys/bus/platform/devices/cpif/modem_state`, which the
  chroot lacked; with that bound, it logs "Modem state ONLINE". `GpsOpen()`
  still fails (no radioExternal HAL). Kepler's fault is unchanged (PR #141).
- **DVS and DFS off** through gnssd's `/data/vendor/gps/overlay/gps_overlay.conf`
  (read 27 times): the fault is unchanged (9 in 4 minutes).
- **Stock's rails are Kepler's to control**: LDO9S-11S carry
  `channel-mux-selection` 0x29-0x2b (subsys GPS) in stock's DT, with
  LDO9S ranging 0.725-1.3 V; our DT holds them on at fixed voltages.
- **Hazard found**: after the modem profile has stopped (gnssd's exit),
  starting the profile again in `OMAMOBILE_MODEM_STAGE=rfsd` reset the
  palmtop silently (watchdog, no pstore). Reboot instead.
- **Where the fault is** (local disassembly of the soft-watchdog RAM dump,
  which is kepler.bin as loaded at 0x60000000; private, never committed):
  the patch code at 0x600B5B34 calls a veneer at 0x600E143C that jumps to
  0x200005B5 (R12 at the fault), code in Kepler's SRAM (the main stack is at
  0x2002FF38). That code branched through R3 = 0x62D, and the M7 faulted
  fetching 0x62C, low memory that isn't in the image. So something maps or
  powers Kepler's low memory, or fills that pointer, and it hasn't happened
  by engine start. `umts_boot0` ioctl 0x28 (gnssd's "SHMEM_SIZE -1") is
  not defined in Google's tegu CPIF either, so stock gets EINVAL too and it
  isn't the cause.
- **The loaded image is intact.** The dump differs from kepler.bin in 17
  words, all in the configuration header below 0x390, and they are gps.cfg's
  values that gnssd writes before the load (RfMiscCtrl 0x80008001 at 0x10,
  AidingConfiguration 0x20046 at 0x1c, the VDR 200/20 limits at
  0x344-0x350). So the write-combine mapping of GNSS_FW (stock: cached,
  over an I/O-coherent link) doesn't corrupt the load. The layout matches
  stock too: GNSS_FW at cp_rmem + 8 MiB, 4 MiB long. The missing piece is
  on the core's side (its low memory at engine start), which the AP can't
  see; the next step is Kepler's own debug log (`gps_overlay.conf.next`).

### G3, ninth to fourteenth tries: the "hardfault" is gnssd's watchdog (2026-10-29, night)

[V] With gnssd's debug log on (`gps_overlay.conf`: `debug_enable=1`,
`debug_console=1`, `chpp_log_level=4`), the engine is seen **working**: it
tracks satellites (SVIDs 5, 11, 12, 13 at C/N0 29-35 dB-Hz) within ~10 s
of the start. The fault that follows is gnssd's own: its soft watchdog
logs "KEP soft_dog pos req timeout", then "sw version timeout", resets
Kepler and sends BLC ID 6 ("Try and trigger hard fault to see if CPU is
locked up or maybe we can get RAM dumps"), which is the "KEP M7
HARDFAULT" with PC 0x62C. The watchdog fires because the CHPP link over
the GNSS SPI loses packets: thousands of "ACK timeout" and 244 "Rx BAD
checksum" in one run. In the raw reads, frames that should start with the
CHPP preamble `68 43` often read `34 21`, the same bits one bit late, and
long frames end in zeros.

The SPI settings tried, each on a fresh boot (the CP boots once per boot):

| SPI mode | rx chunk | feedback delay | RX bad checksums | Kepler |
| --- | --- | --- | --- | --- |
| 0 (as ported) | 64 | 2 (as ported) | 244 | tracks, then the watchdog |
| 0 | 32 | 2 | 17 | opstate 0 |
| 0 | 32 | 0 (stock's value) | 93 | opstate 0 |
| 1 | 32 | 0 | 34 | opstate 0 |
| 1 | 64 | 0 | 0 (RX clean) | TX lost: Kepler never sees our RESET-ACK |
| 0, 1 MHz | 64 | 0 | 63 | opstate 0 |
| 3 | 64 | 0 | 32 | opstate 0 |
| 0, 32-bit words (swapped in gnss_spi) | 64 | 2 | 1 | RX transfers time out (-110), opstate 0 |
| 0, 32-bit, auto CS (`google,gs101-spi` only) | 64 | 2 | 0 | RX transfers time out (-110), opstate 0 |
| 0, auto CS | 64 | 2 | 274 | tracks, then the watchdog (as ported) |

So RX samples the core's data a bit early in mode 0, mode 1 fixes RX but
breaks TX, and neither the feedback delay nor a slower clock fixes it.
Stock drives this SPI with 32-bit words, `swap-mode = <1>` and DMA
(`dma-mode`, PDMA 0x14/0x15); our port uses PIO. 32-bit words alone (byte
order fixed in gnss_spi) time out in PIO, so the next step is DMA for this
SPI. Google's driver uses auto CS for this device (no
`samsung,spi-chip-select-mode`), but auto CS changes nothing with 8-bit
words. Our DT has no PDMA controller (stock's overlay uses `pdma1`), so DMA
means a PL330 node for zumapro first. The palmtop is back on the as-ported setting (mode 0,
64-byte reads, delay 2, the gn3 DTB).

Next steps for the link, from the night of 10-29 (not tried yet):
- **32-bit words in PIO time out** (`res -110`, every 64-byte read) under
  mainline spi-s3c64xx. Not its FIFO-level check: Google's driver makes the
  same `RX_FIFO_LVL < xfer->len` comparison for 32-bit words and works, so
  the level counts bytes. -110 is mainline's interrupt wait
  (`wait_for_completion_timeout` in `s3c64xx_wait_for_pio()` with
  `use_irq`), which Google's driver doesn't have: it polls. The FIFO
  trigger interrupt with 32-bit words is the next thing to read
  (spi-s3c64xx is built in, so a change is a kernel push).
- **DMA:** stock's `pdma1` is a PL330 at 0x10130000 (SPI 806, a 200 MHz
  fixed clock, Samsung's 36-bit address wrappers, which mainline doesn't
  have), with the GNSS SPI on channels 0x14 (tx) and 0x15 (rx). A
  read-only probe (2026-10-29) read its PrimeCell IDs (periph 0x30 0x13,
  cell 0x0d 0xf0) from Linux without an abort, so a DT node can probe it.
  Mainline uses DMA only for transfers longer than the 64-byte FIFO, so the
  64-byte reads would stay PIO.

**What the link does (10-29, night), cause still open:** mainline spi-s3c64xx cuts
every PIO transfer of 64 bytes or more into 63-byte pieces
(`xfer->len = fifo_len - 1`), stopping and flushing the FIFO between them.
So each 64-byte read of Kepler becomes 63 + 1 bytes, and each longer write
is cut mid-frame; 32-bit words then can't work at all (63 isn't a multiple
of 4: the `len-63` timeouts). Stock never splits: it uses DMA. But the
split isn't shown to be the cause: with gnss_spi cutting every transfer
into 60-byte pieces itself (one message, CS held, every pause on a 32-bit
boundary, so the controller never cuts), the link garbled just the same
(369 bad checksums, Kepler tracking, then the watchdog). Progress: a runtime test module
registered stock's pdma1 (PL330 at 0x10130000, SPI 806) and the built-in
pl330 driver probed it and ran a 256-byte memcpy correctly; a DTB with the
node probes it at boot. But with `dmas` on the GNSS SPI (0x14/0x15, either
order), RX DMA moves nothing (residue 64): the SPI's DMA requests don't
reach pdma1, so some routing stock sets up is still missing (a sysreg or
USI DMA select, or the PL330's peripheral security setting). The palmtop
is back on gn3 without the node. A one-boot reset at 69 s happened on the
second boot with the node, cause not seen.

### G3, fifteenth to twenty-third tries: the SPI runs at twice stock's clock (2026-10-29, small hours)

[V] Each try on a fresh boot of the gn3 kernel, gnssd's debug log on, a test
`gnss_spi.ko` with module parameters (feedback delay, chip-select setup,
clock, `HIGH_SPEED_EN`), raw RX bytes taken from strace of gnssd's reads of
`/dev/gnss_ipc`. Results:

| Try | Setting | Bad checksums | Kepler |
| --- | --- | --- | --- |
| baseline (control) | as ported: 8-bit, 64-byte reads, delay 2 | 46 | tracks (C/N0 29-34), then the watchdog |
| w32p32 | 32-bit words, 32-byte pieces in one message | 19 | no watchdog, stops after RESET-ACK |
| w32rx32 | 32-bit, 32-byte reads | 7 | same |
| fb3 | 32-bit, feedback delay 3 | 5 | same |
| cs200 | 32-bit, delay 3, 200 us CS setup | 0 | same |
| osc | 32-bit, USI3 mux on OSCCLK, about 1.5 MHz | 0 | same |
| acs | 32-bit, auto CS DTB | 0 | same |
| osc8 | 8-bit, OSCCLK, about 1.5 MHz, delay 0 | 1 | same |
| hs | 8-bit, `HIGH_SPEED_EN` forced, 32-byte transfers | 17 | same |
| hs60 | 8-bit, `HIGH_SPEED_EN`, 60-byte reads | 408 | tracks, then the watchdog (38) |

What the raw bytes show:

- **The real SPI clock is 6.24 MHz, not 3.125.** USI3's mux (`zumapro_mout_hsi0_usi3_local`) is read-only in clk-zumapro and sits on the 399.36 MHz parent; the 4-bit divider stops at /16, so the IP clock is 24.96 MHz and the SPI clock 24.96 / 4, whatever spi-s3c64xx asks for. The "1 MHz" try of the night before ran at 6.24 MHz too.
- **The baseline's errors are per byte:** one byte of a repeated frame arrives with its top bit taken from the previous byte's last bit (`10 01 00 0a ... 4f b6 25 9c` read as `08 00 00 05 ... 27 db 12 ce`), and the rest of the frame is right. That is the controller sampling before Kepler's data has settled: too little margin at 6.24 MHz, as mode 1 (which samples half a clock later) showed.
- **Every changed setting broke the framing instead:** with 32-bit words, with the OSCCLK mux, and with chip select toggled every 32 bytes, CHPP frames arrive at any bit offset (8-bit baseline: always 0 or 1), the link stops after RESET-ACK, and the bad-checksum count drops only because few frames are recognised. A chip-select toggle in the middle of a frame drops one byte from Kepler at the break. So the low counts in this table are not improvements.

The next step is the clock itself, in the kernel: let spi-s3c64xx reach 12.5 MHz on USI3 (3.125 MHz SPI) from a parent that can give it, as stock does, with nothing else changed. The OSCCLK try isn't a fair test of that (24.576 / 4, about 1.5 MHz, switched behind the clock framework's back). The palmtop is back on the baseline (`gnss_spi` aa4618bb, `gnssif` eb0f3d9a, gn3 DTB, no debug overlay). One reset at 348 s, after the hs60 run had ended, came during modem PCIe link activity ("PHY isolated"), not in the SPI path.

### G3, twenty-fourth to thirty-fourth tries: stock's clock, mode 1 reads, where the bytes go (2026-10-29, small hours)

**Stock's clock, tried (twenty-fourth try):** Google's zuma CMU table (`cmucal-vclk.c`, `div_clk_hsi0_usix_12mhz_lut_params` = div 1, mux 1) makes USI3's 12 MHz from OSCCLK / 2 (12.288 MHz, a 3.07 MHz SPI clock). A test module set exactly that (mux to OSCCLK, divider held at /2, 8-bit, delay 0). Framing broke as in the other OSCCLK try: Kepler resent one frame (`68 43 00 20 01 00 0a ...`) for seconds, and every copy arrived shifted by the same 4 bits across many separate reads, then by 5, then 6. So Kepler's bit counter runs on across chip-select cycles, and on OSCCLK it gains or loses clocks; on the 399.36 MHz parent (baseline, 6.24 MHz) the frames stay at bit 0 and only single bytes are misread. A clk-zumapro change that lets USI3 reach OSCCLK / 2 is drafted but not worth a kernel until the slip is understood; it would reproduce this test (later: [linux-omarchy-mobile#138](https://github.com/derekross/linux-omarchy-mobile/pull/138)). The palmtop is on the baseline again.

**Read in mode 1, write in mode 0 (twenty-fifth and twenty-sixth tries).** The baseline's raw reads show more than single bytes: about 80% of CHPP frames arrive one whole bit late (the preamble found at bit offset 1, so CHPP never sees it), which is where most ACK timeouts come from. Feedback delay 3 at 8 bits changed nothing (57 bad checksums, same split of offsets). A test module that switches `spi->mode` per transfer (read-only transfers in mode 1, writes in mode 0; spi-s3c64xx reconfigures on every transfer because its `cur_speed` never equals the rate asked) put every frame at bit offset 0 for the first time on the as-ported clock: short frames pass, the engine reports satellites, the watchdog fires later. Long frames (279 bytes) still fail: the first byte or two after each read's chip select are damaged (in one string Kepler resent, the byte after a 60-byte boundary read `6` in one copy and `8` in the next, and `11 00 11` became `41`). 60-byte reads, so spi-s3c64xx never splits a read, didn't change that. Two resets came from the modem side, not the SPI: after Kepler's watchdog resets, gnssd reloads the image over the CP's PCIe link (`IOCTL_READ_GNSS_IMAGE`, then "PHY isolated"), and the SoC reset within a second (03:15, and 02:43 after the hs60 run). Frequent Kepler resets are therefore a crash risk until the link is fixed; keep GNSS runs short. Separately, two boots reset at about 34 s, right after Bluetooth started (01:41, 03:03), before any GNSS step.

**Where the bytes go (twenty-seventh try, mode 1 reads with 50 us chip-select setup):** 101 bad checksums (260 without the setup), and the palmtop stayed up through 14 Kepler watchdog resets with omamobile-modem 0.1.9's slower CP watcher (#148). Comparing the copies Kepler resends: short frames inside one 64-byte read agree byte for byte, and every copy of a long frame loses the same one or two bytes at each 64-byte read boundary (`11 00 11 00 10 00 01` read as `11 00 00 | 00 01`, `00 00 31 2e 30 2e 30` as `00 00 2e | 2e 30`). So in mode 1 Kepler's stream drops bytes when chip select is released between reads, deterministically, not by timing. In the as-ported mode 0 the copies disagree mostly at byte 63, the one-byte tail spi-s3c64xx splits off each 64-byte read. Next: hold chip select across rx_work's consecutive reads of one Kepler message (one long transfer while gnss2ap stays high), which also removes the split.

**Chip select held across a message (twenty-eighth try):** mode 1 reads with chip select kept asserted between rx_work's reads (released when gnss2ap drops or before a write) made it worse: 292 bad checksums, and the 279-byte frames now end in zeros (footer 0). Kepler wants chip select released between its 64-byte reads, as stock does, so the bytes lost at each release in the mode 1 tries have another cause. What's left untried needs stock evidence: a logic-analyzer capture of stock's SPI21 (CS, SCLK, MISO timing between reads), or stock's register state for SPI21 and CMU_HSI0 USI3 while GNSS runs.

**One bit late, cleanly, with feedback delay 3 (twenty-ninth to thirty-second tries, offline checks on the saved reads with CHPP's CRC32 over the 8-byte header and payload):** at feedback delay 3 (mode 0, 8 bits, the as-ported clock) Kepler's frames are intact but one bit late: shifting the reads left one bit turns 11 valid frames into 123 (at delay 2 the same shift recovers nothing). Kepler is on time just after it starts and one bit late later, so a fixed shift lost its first RESET-ACKs for 2 s and set off a reset storm (125 RESETs from Kepler, 144 RESET-ACKs from gnssd); delaying our writes by one bit as well killed the link outright, so writes are right as they are. A per-read choice (a preamble at bit 0 keeps the read, at bit 1 shifts it, a read without one keeps the last choice) gives clean short frames and the engine reporting satellites, but 279- and 361-byte frames still fail: setting the one dropped bit at each 64-byte boundary every possible way repairs none of them, so more than a bit goes missing at each chip-select release, as in the mode 1 tries. The test module (`gnss_spi.c` with `fb_delay`, `realign`, `rx_cpha`, `hold`, `osc`, `div` parameters) is the `realign` commits of linux-omarchy-mobile#137 (b5229f35d, ff0eadd34, dacf3e304, a0877abc3); the palmtop is back on the baseline.

**Stock's clock again, read correctly (thirty-third and thirty-fourth tries):** the OSCCLK frames are not garbled: every read that holds a frame has a valid one at some bit shift (offline: 32 of 33 valid when each read is shifted to its preamble). But at OSCCLK / 2 (3.07 MHz) Kepler's bit offset walks by one or two bits about every 100 ms (0, 2, 3, 5, 6, 7, 0, 1, 3 in the first second), roughly a clock edge gained or lost per transfer; with the offset tracked per read and our writes delayed by it, 20 frames came through clean but Kepler only answered RESETs. At OSCCLK / 1 (6.14 MHz) the offset changed twice in 100 s. So the drift grows as the clock slows, the opposite of a too-fast slave; a clock edge seen twice (or a glitch) at each transfer's start or stop would fit. The 05:02 reset (CLUSTER0_NONCPU_WDTRESET) came with #148's watcher installed: in its last minute the CP link cycled twice a second in step with gnssd's `IOCTL_LOAD_GNSS_IMAGE` calls, so the watcher was one source of link cycling, not the only one, and the hang (CPIF's link power-down racing an access, presumably) is still open. Keep GNSS runs short until it is fixed.

### The CP link hang (2026-10-29, read from the CPIF source, offline)

**The CP link hang, read from the source (offline):** our `tegu-pcie0-cp` guards DBI and configuration space while the PHY is isolated (accesses return 0 or are dropped), but not the CP's BAR window, which CPIF uses for its doorbell. CPIF's main doorbell path (`link_device.c`) looks safe: it rings under `pcie_tx_lock` after checking that `pcie_onoff_lock` is free and `pcie_powered_on` is set, and `s5100_poweroff_pcie()` takes `pcie_onoff_lock` first and then waits for `pcie_tx_lock` before it powers the link down, so a doorbell either finishes before the power-off or is reserved for later. `IOCTL_LOAD_GNSS_IMAGE` only copies into the GNSS_FW carve-out in AP memory (no link access); the reloads matter because the Kepler reset around them makes IPC traffic, so the link wakes and idles twice a second. I found no unguarded BAR access by reading; the other doorbell callers (`modem_ctrl_s5100.c`) are the CP boot and the power-on path. The step that would find it is below, gated; it has not run, and GNSS is parked (see "Parked" under the morning of 10-29), so it runs only if GNSS is ever resumed.

**What the kept consoles say (2026-10-29, read offline from `/var/log/omamobile/ramoops/`,
the 24 boots between 07:34 and 09:19 local; the extracts are in `logs/tegu-review-20261029/hangs/`,
not committed).** Each saved console holds the bootloader's log of the boot
that wrote it, the kernel's console, then the next boot's bootloader log,
whose `[PRE] RST_STAT` names the reset. The morning's resets sort into
three kinds:

- `SYSTEM_SWRESET_SYSTEM` after `sysrq: Resetting` with a `---[ end trace ]---`
  just before (eight boots): the curated start's fault check tripping on the
  `OF: overlay` WARNING and resetting, as item 7 of the morning list says;
- `SYSTEM_SWRESET_SYSTEM` after `reboot: Restarting system with command
  'bootloader'` (two) or `'omamobile'` (six): the 150 s dead-man and the
  pushes;
- `CLUSTER0_NONCPU_WDTRESET` (eight, at 07:37, 07:42, 07:48, 07:51, 08:45,
  08:52, 08:56, 09:09): the real hangs. Every one of them ends the same way.
  The last line is the pair `samsung-pinctrl 154e0000.pinctrl: wake disabled
  for irq N` / `wake enabled for irq N` (N = the `cp2ap_wakeup` line on
  FAR_ALIVE, 85, 84, 70, 76 or 96 depending on the boot), which is CPIF's
  `ap_wakeup_handler()` flipping the line's trigger after an edge; what
  should follow 5 ms later, `tegu-pcie0-cp: PHY out of isolation`, never
  comes. Before it the link was cycling once every half second: `PHY out
  of isolation`, `link up: Gen3 x2`, 55 ms, the toggle (the CP releasing
  the line), `PHY isolated`, 350 ms, the toggle (the line asserted again),
  and so on, eight to twenty toggles in the last minute. One console (07:42)
  caught the hang's shape: an `rcu_preempt detected stalls` report with
  CPUs 0, 3 and 7 stuck (`idle=...1/0x4000000000000002`, 5255 jiffies,
  detected by CPU 4) 22 s after the modem went ONLINE, i.e. right when
  gnssd starts (`OMAMOBILE_MODEM_GNSS_DELAY` is 20 s), with no backtrace,
  which is what a load that never completes looks like. Another (07:48)
  has, as its last lines before the toggle, gnssd's `lal_state_thread`
  opening `gnss_dump` and `gnss_boot` and CPIF answering `pcie_send_ap2cp_irq:
  Reserve doorbell interrupt: PCI not powered on`: an AP-to-CP interrupt
  asked for while the link was down, which CPIF parks and answers with
  `s5100_try_gpio_cp_wakeup()`.

  So the hang falls in the window after the CP (or the AP's own wake
  request) asserts `cp2ap_wakeup` and before the link is back, and it
  happens only while something cycles the link quickly: the old watcher's
  open/close (the 07:37-07:51 boots, before #148's watcher, omamobile-modem
  0.1.9, in review) or
  gnssd's Kepler loads (the later ones). In that window the paths that run
  are CPIF's `cp2ap_wakeup_work()` to `s5100_poweron_pcie()` and our
  `gs201_pcie_cp_poweron()`, whose first hardware step is the PMU bypass
  write that logs `PHY out of isolation`; nothing before that line touches
  the PCIe block. A load that hangs the CPU therefore comes from another
  thread in that window: a read of the modem's BAR window while the PHY is
  isolated, as the cheetah gotcha describes, from a path that doesn't take
  the link first. The GNSS image itself goes to DRAM (`SHMEM_GNSS_FW` through
  `gnss_v_base`), so the candidates are the IPC paths that follow it:
  `pcie_read_thread` on the shared-memory queues, `s51xx_pcie_restore_state()`
  and the MSI set-up on the way back up, and CPIF's own status reads.

  Two things follow for G3-L1. First, a cheaper step before the trace: a
  cpif module parameter that makes `s5100_poweroff_pcie()` keep the link
  up (Google's own "Skip pci power off" path, taken unconditionally), on a
  bring-up branch, then three 12-second sessions. If the hang goes away
  with the link held, the cause is a link-down access and the trace knows
  where to look; if it stays, the link is not it. Second, the trace points:
  `s5100_poweron_pcie()` entry and `gs201_pcie_cp_poweron()` entry (to see
  whether the power-on path is ever entered before the hang), and every
  `readl` of the BAR window in CPIF (the `s51xx_*` helpers and
  `pcie_read_thread`'s queue reads) with `pcie_powered_on` in the line.

**G3-L1: which BAR access lands after isolation (attended, on the charger; risk: medium-high).** It starts with the hold-the-link step from the section above: a cpif built with `keep_link_up=1` (kernel branch `tegu-cpif-keep-link`, commit 3f76f123b, the module staged on the palmtop as `modem/cpif-keep-link.ko`), three 12-second sessions, under exactly the frame below (M0.1 before and after, attended on the charger, kmsg to the laptop with `--watchdog`, the same Stop and Rollback); its sessions count toward the cap of three sessions, and a hang in them counts toward the two resets, so if the link held up still hangs, the trace gets what is left of the cap or waits for the next day. Then the trace: at each BAR access in CPIF and at `cp_phy_isolate()` (the caller, the lock state and `pcie_powered_on` in the kernel log), to see which access lands after isolation. The tracing change goes on a kernel branch first (`omamobile-tegu-modem`, or a bring-up branch on the fork, linked by commit), is built there and reaches slot B through `bin/omamobile push`; nothing is patched on the palmtop by hand, and the kernel never boots before the branch is pushed. Before the step: M0.1's partition check, the kmsg stream to the laptop with `--watchdog`, the palmtop on the charger with someone at it the whole time, and a 12-second GNSS session (as the morning's) to bring on Kepler's watchdog resets and the link cycling. Expect: the log names the access that follows `cp_phy_isolate()`, or the link cycles through Kepler's resets without a hang. Stop: two SoC resets (a hang with no record in pstore counts as one), or any `ufshcd_err_handler` line in dmesg, or an NV partition that reads `ro=0` or mounted; after a stop, no further boot of the tracing kernel that day. Cap: two resets per session and three sessions in all, then the step is closed and the hang waits for a stock capture. Rollback: `bin/omamobile push` of the previous images (the gn3 kernel), then M0.1 again, as after any reset with the modem up. Risk: medium-high, because each reset is a hang with the modem up, which has been followed by a recovered UFS error-handler pass on cheetah; the partition check afterwards is not optional.

### G3, the morning of 10-29: the clock fixed, the cut fixed, and what is left (thirty-fifth to forty-fourth tries)

[V] Two kernel changes, built from the gn3 source (`~/tegu/int-dt-20261026/kernel` on maclab, the reproducible build; the first attempt from `wt-modem` carried an older USI4 clock table and broke the audio I2C) and pushed as boot images only: spi-s3c64xx no longer cuts a transfer that fills the FIFO (64 bytes in one polled piece; the 32 + 32 test had shown every frame crossing a piece boundary failing with chip select held, so the cut, not the chip-select release, lost the bytes), and clk-zumapro lets USI3 reach OSCCLK (`nMUX`, so the framework may reparent, plus `CLK_SET_RATE_PARENT` on the divider and the source gate): `zumapro_gout_hsi0_usi3_ip` now reads 12.288 MHz after the first transfer, a 3.072 MHz bus, stock's rate. Both are in [linux-omarchy-mobile#138](https://github.com/derekross/linux-omarchy-mobile/pull/138) (in review; branch `tegu-spi-word-pieces`, replacing the closed #135). The morning's tries (thirty-fifth to forty-fourth) ran on those images; their `uname -r` is the night's string, `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`, because the build fixes LOCALVERSION, so the release does not change between these builds and the Image's sha256 tells them apart: `Image-osc` (sha256 7d620900…, the first attempt) and `Image-osc2` (75a44a1a…, the one the tries ran; `Image-nosplit` in the same directory is that same image), with the repack scripts in `logs/tegu-gnss-w32-20261029/`. Graphics, audio bring-up and touch are unaffected on that kernel. The SPI block's own prescaler does not exist on this IP (CLK_CFG reads 0 and ignores writes).

[V] Reads, with every byte dumped to the kernel log (a gnssif built with `GNSS_PKT_DEBUG`, 64 bytes per line) and short 12-second sessions so Kepler's watchdog does not pile up resets:
- Mode 0 at stock's clock is marginal at every feedback delay: the per-read detector flips between "on time" and "one bit late" within a session, and long frames fail wherever it flips. (Delay 3 at 6.24 MHz had looked stable only because the session was short.)
- Mode 1 reads (writes stay mode 0) are byte-aligned and intact, but every block after the first one of a message loses its first byte: inserting one byte (0xAA) at the first position of block 1 makes Kepler's constant version frame pass its CRC. With a 100 us chip-select setup the protocol was the healthiest seen (0 ACK timeouts, our packets acknowledged), the first-byte loss unchanged. A 500 us gap before each read made Kepler stop sending long frames; a 50 us chip-select hold did nothing.
- Padding each write to a whole 64-byte exchange (gnssif) changed nothing measurable.
- CHPP's checksum is CRC32 over the 8-byte header and the payload (checked on short frames); the offline checks are in commit 8d77391d9 of linux-omarchy-mobile#137 and the captures in `logs/tegu-gnss-w32-20261029/`.

So with the clock and the cut right, what is left is one byte per back-to-back chip-select cycle in mode 1, or a half-bit sampling margin in mode 0, which is exactly the kind of question a logic analyzer on SPI21's SCLK, CS and MISO answers in a minute and software guessing does not. The palmtop runs the new kernel with the as-ported modules. The resets during this morning's sessions were mostly the curated startup's 150 s dead-man after its own false-positive fault check (an `OF: overlay: WARNING` line), rebooting through `reboot-to bootloader`; a few hard resets with no record in pstore remain unexplained (`logs/morning-20261029.md` item 7).

**The night's test code and the partition check** (the maintainer's points 4 and 5 on #138):
- bring-up branch: [linux-omarchy-mobile#137](https://github.com/derekross/linux-omarchy-mobile/pull/137) (draft, `tegu-gnss-spi-bringup` on the owner's fork, head 8d77391d9, on top of the two kernel fixes): the gnssif_spi driver as ported (bb9999570), then one commit per variant in the order of the tries: 32-byte reads (401016f37), spi_mode and speed_hz (21cea1dd0), 32-bit words (45b492116), 60-byte pieces (7eec92532), w32p32 (c5223f5fc), the `fb_delay`/`cs_setup_us`/`osc` parameters with the USI3 mux write (cc78f333d), 8-bit words (840cac155), `hs` (e497c8be0, f8013d08b), the USI3 divider hold of the twenty-fourth try (b587e76f4), `rx_cpha`, the per-transfer `spi->mode` switch (f2dcd5241), `hold` (e8d4d64e2), `realign` 1-3 and `txshift` (b5229f35d, ff0eadd34, dacf3e304, a0877abc3), and the morning's `piece`, `carry`, `rx_gap_us`, the byte dump, `tx_gap_us`, padded writes, `psr` and `cs_hold_us` (dae13a1f9 to b8c423dda); the pdma1 ID probe and the runtime PL330 memcpy module (5f786c818, 288a87ecc); the feedback-delay-0, auto-CS, pdma1 and pdma1-swapped overlays (4d5548b4d); the g7 scripts and the offline CRC and bit-offset checks (8d77391d9). There was no separate USI3 mux-and-divider module: the mux write is the `osc` parameter and the divider hold the `div` parameter inside gnss_spi. Each test DTB and each of the morning's images reached slot B through our `bin/omamobile push`, run by a local wrapper that first runs `bin/omamobile images` with the base DTB and the overlays; `push` writes the `_b` images with `dd`, verifies them by sha256 and reboots with `reboot-to omamobile`. Never fastboot.
- partition check (2026-10-29 10:20, after the night's sessions and resets, release `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`): `efs`, `efs_backup`, `modem_userdata`, `persist`, `modem_a` and `modem_b`, each found by `PARTNAME` and read with `sha256sum` only, all match the 10-28 read-only backup (`tegu-protected-post-android-20261028T174253Z`, off-repo), all `ro=1`, none mounted. The boots from 07:34 to 09:19 local, the morning's tries among them, ran before this check, so it covers them and their resets too; the next modem session starts from this baseline.

**Stock's SPI configuration, read from the sources (2026-10-29, afternoon; no
hardware).** Three things settle what stock does on this link, none of which
the tries above reproduced together:

- The board overlay (the private capture, fragment@110) gives the GNSS node
  `swap-mode = <1>`, `spi-max-frequency = <3125000>`, `controller-data {
  samsung,spi-feedback-delay = <0> }`, no `cs-gpios`, no `dma-mode` (the
  SoC dtsi has the `dmas` line commented out: stock runs this SPI in PIO),
  and no `samsung,spi-chip-select-mode`.
- Google's `spi-s3c64xx.c` (google-modules/soc/gs at 183509aff980) makes
  `cs_mode = AUTO_CS_MODE` the default when that property is absent
  (`s3c64xx_get_slave_ctrldata()`), so stock drives chip select from the
  controller (`SLAVE_SEL |= SLAVE_AUTO | NSC_CNT_2`): nCS asserted by the
  hardware for the packet count and released with a two-clock inactive
  gap, never by software around each transfer. Our zumapro port uses
  manual native chip select (the SPI core asserts and releases it around
  every 64-byte transfer). With `swap-mode` and 32-bit words Google's driver
  programs `SWAP_CFG` (TX and RX byte and half-word swap); mainline has no
  swap support and our 32-bit tries swapped in software.
- Our running tree's node has `samsung,spi-feedback-delay = <2>`; stock's
  is 0.
- The gnssif port itself is byte for byte Google's (`gnss_link_device.c` and
  `gnss_spi.c` differ from google-modules' gnssif_spi only by one include;
  `gnss_main.c` by the platform glue), so the protocol handling, the
  `gnss2ap_spi` ready handshake included, is stock's. Everything that differs
  is in the SPI controller driver and the node.

The "auto CS" try (`acs`, the night) ran with 32-bit words at 6.24 MHz,
before the clock fix, and no try has run auto chip select at stock's clock
with 8-bit words and feedback delay 0. That is the next boot when GNSS
resumes (G3-A, attended, one DTB round): the `autocs` and `fb0` overlays from
linux-omarchy-mobile#137 on the current kernel, 8-bit words, 3.07 MHz; then,
if the first byte of a back-to-back block still goes missing, 32-bit words
with the controller's own swap (`SWAP_CFG` as Google programs it, a small
addition to the zumapro port) rather than a software swap. No analyzer in
either.

**Parked (2026-10-29, the owner's decision):** no logic analyzer, and no more module-level guessing. The two kernel changes stay ([linux-omarchy-mobile#138](https://github.com/derekross/linux-omarchy-mobile/pull/138), the signed-off replacement of #135); the as-ported gnssif and gnss_spi run on the palmtop. GNSS resumes when either a stock capture of SPI21's timing or a new idea about the first byte of a back-to-back block turns up.

### Suspend with the modem on (2026-10-27, early morning, same kernel)

- **What ran:** s2idle on `7.3.0-rc6-omamobile-tegu-s2mpg15-m1-g991042e2eff3-dirty`
  with the CP ONLINE (CPIF, cbd and rfsd up, no SIM), the bring-up's usual
  modules loaded (AoC, Wi-Fi, Bluetooth, NFC) and neard polling for tags.
- **What happened:** the palmtop didn't wake from that sleep. It came back
  only after Power was held, at 06:44; the journal kept nothing from the
  sleep itself.
- **What it was:** later the same morning, with the modem off, a suspend
  with neard polling reset the palmtop too. With polling stopped (the
  `omamobile-tegu-nfc` sleep hook, on the palmtop only for now), 35 s2idle
  cycles with 20-30 s RTC wakes on 2026-10-27, in three runs of 3, 12 and
  20 through `systemctl suspend`, all woke. A fourth run's fourth resume
  lost the UFS link, a separate problem since fixed (kernel PR #83). NFC
  polling alone explains the failure, so the modem's part in it is
  unknown: suspend with the modem on is still unqualified on the 9a
  (AGENTS.md, "Suspend and modem").

### M2: the link only (modem link driver, `allow_hw=1`; risk: medium)

One step per run, the CPIF overlay not applied, the link overlay applied
by its activate module.

| Step | What | Pass | Stop / rollback |
| --- | --- | --- | --- |
| M2.0 | bind, no hardware access | "2 lanes, steps disabled"; status: lines as M0.3, PMU 0x3ec4 0x0 | any controller read; rollback: reboot (no unload test yet) |
| M2.1 | `cp_on`, then `cp_off` (lines only, ~130 ms) | outputs 1 then 0; cp2ap-wakeup → 1 within 2 s (cheetah M2.1) | UFS handler pass; rollback `cp_off` |
| M2.2 | PMU 0x3ec4 bit 0 round trip, nothing else (as WIFI-PLAN W4a) | reads back 1 then 0 | readback mismatch: stop, reboot |
| M2.3 | `cp_on`, `link_up 1`, `id`, `link_down`, `cp_off` | "link up: Gen1 x1", LTSSM 0x11, endpoint `144d:a5a5` [I: S5300 ID as cheetah], 0x3ec4 back to 0 | "no L0" ×3: dump status, `link_down`, `cp_off`; a hang: watchdog |
| M2.4 | `bus`: host bridge, MSI at 0xf6200000, config read with the link down → all-ones | as cheetah M3.1.1-M3.1.3 | a hang on a down link: the DBI guard failed; stop |

Dead-man for M2.1-M2.4: `systemd-run --unit=x-deadman --on-active=120 sh -c 'echo link_down > …/ctl; echo cp_off > …/ctl'`,
stopped after a fresh SSH login confirms the step.

### M3: bind CPIF, no modem power (risk: low)

Blacklist first (the reinstall of `omamobile-device-tegu`), then apply the
CPIF overlay, load the link module **without** `allow_hw`, then `shm_ipc`
and `cpif`. Pass: probe without "xxx" or an Oops; `/dev/umts_boot0`,
`umts_ipc0/1`, `umts_rfs0`, `umts_router`, **`/dev/gnss_boot`**,
`gnss_dump`; 30 rmnet devices; "gnss_v_base=" logged (GNSS_FW mapped); every
AP2CP line low; PMU 0x3ec4 0x0; 60 s later nothing changed. Stop: a
"poweron" or "link up" line. Rollback: reboot (cpif is permanent).

### M4: rfsd alone on RAM copies (risk: low)

As cheetah M3.4.4 on the tegu chroot image: the five RAM copies match the
backup, the salted NV checksums match, the baseband version is recorded,
rfsd logs Touch/Verified and no Expand/Create/Clear. Stop lines and the
"never go on" list are cheetah's, unchanged. The CP stays unpowered.

### M5: first boot to ONLINE, left on (risk: medium-high)

As cheetah M3.4.5 (link at Gen1 for the ROM, BOOT image, Gen3 x2 for the
main firmware, "CP ONLINE (cbd exit 0)"), `ro.boot.cdt_hwid` from the
private capture in the per-phone props (cheetah M4.1h: without it the main
firmware hung). Pass also: no SysMMU/S2MPU fault at the first DMA (F1's
[I]); UFS count unchanged. Stop: a CP crash before ONLINE (record crash
reason and boot log, leave the CP, reboot); any NV stop line. Afterwards
M0.1 again: the real partitions unchanged.

### M6: reboot with the modem up (risk: medium)

Two reboots with the CP ONLINE, as cheetah M4.1j/M4.1k: back on its own,
no WARN, NV unchanged. Until both pass, reboot only with the human at the
palmtop. After that, the SIM stage follows cheetah's "M4.2-M4.7" runbook.

### G0: where gnssd's NMEA goes (offline; risk: none)

From V/'s `gnssd` and `gps.cfg` (strings and disassembly, offline): the
`%s/nmea` path and the HAL socket's protocol, and which `gps.cfg` keys turn
the NMEA output on. Pass: a named output the bridge can read without the
framework HAL (a FIFO or file, or a socket whose framing is known). If
none: the fallback is a small client of gnssd's HAL socket in U3.

### G1: the SPI and gnssif, CP off (risk: low)

K5/K6 on the GNSS branch; enable `spi21` and the gnssif node by overlay
after FAR-ALIVE-PLAN settles GPA5's pin 4. Pass: `gnss_spi` and `gnssif`
bound, `/dev/gnss_ipc` present, gpp2-3 output low, no gpa5-4 interrupts
while the CP is off. Stop: an interrupt storm on gpa5-4 or any change on
the WLAN/BT/TAS pins of GPA5.

### G2: Kepler firmware and first NMEA, CP ONLINE (risk: medium)

gnssd in its chroot (profile `gnss-kepler`, own `/data/vendor/gps` in tmpfs
first), started after M5's ONLINE: `IOCTL_LOAD_GNSS_IMAGE` copies
`kepler.bin` into GNSS_FW (RAM only; no partition is touched), then CHPP
over `/dev/gnss_ipc`. Pass, indoors: "codeload" without error, CHPP
discovery, NMEA sentences (GSV with satellites by 5 minutes near a window).
Stop: a CP crash (record, reboot), gnssd retrying the codeload, a UFS
event. Rollback: stop gnssd; the CP stays on. **Open: gnssd opening
`umts_ipc0`** while our SIT client holds it (check in G0 whether it does
without SUPL/control-plane assistance; if it does, give gnssd the SIT
channel only through the SIT client, or keep the SIT client off for G2).

### G3: Location on demand, outdoors (risk: low)

U3 installed: the Location tile starts gnssd through the package, NMEA
reaches gpsd and GeoClue, GNOME Maps shows a fix outdoors. Pass: a 3D fix,
HDOP recorded, gnssd stopped when Location is off (the CP stays on).

### G4: settings (risk: low)

Constellations, SGEE/assistance over the network (gnssd uses libcurl),
power: as cheetah's GNSS-PLAN section 7, adapted to gps.cfg's keys.

## Top risks

1. **The first channel 0 accesses.** A new PHY sequence (two lanes,
   external PLL) on a block Linux has never touched, and the AGENTS rule
   that an ELBI/DBI access with the PHY isolated hangs the SoC. Mitigation:
   isolation round trip alone first (M2.2), controller reads only between
   release and re-isolation, the DBI guard from cheetah in the driver from
   the start, watchdog.
2. **GPA5 interrupt ownership.** CPIF needs gpa5-1/2 and gnssif gpa5-4 as
   interrupts on a bank whose EINT setup masks every pin (FAR-ALIVE-PLAN),
   shared with Wi-Fi, Bluetooth and the speaker amplifier. A wrong move
   loses those wakes or storms. Settle it in FAR-ALIVE-PLAN before M3.
3. **DMA and the HSI1 translation units, and UFS.** Stock runs the modem
   behind `sysmmu_hsi1` with CPIF's PCIe IOMMU; we rely on the SysMMU and
   S2MPU passing DMA untranslated (true for HSI2 Wi-Fi here and for gs201's
   modem). If not, the first boot fails at the ROM's DMA (M5) and the CPIF
   IOMMU becomes a port stage. Cheetah also lost one UFS handler pass per
   modem power-off; the UFS check runs after every step here.

## Open questions

1. Does the CP stay off from the bootloader on tegu (M0.3)?
2. Do the CMU_HSI1 PCIe gates read as on with `clk_ignore_unused` (M0.4),
   and does channel 0 train with no clock driver, as gs201 and stock
   (`pcie-clk-num = 0`)?
3. gnssd's NMEA output and its use of `umts_ipc0` (G0).
4. Does the S5910's off sequence matter for the UFS disturbance seen on
   cheetah at modem power-off? Only relevant once a power-off is tested.

## What needs the human

Nothing before the SIM: every step above is offline, read-only, or a
kernel/module/daemon action on the palmtop with its own rollback. The only
physical action is a forced restart if a step hangs and the watchdog
doesn't bring the palmtop back. The per-phone `cdt_hwid` comes from the
private getprop capture already on disk.
