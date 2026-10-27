<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a modem and GNSS plan (tegu, Samsung S5300)

Status (2026-10-27): M0.1, M0.4 and M2.2 passed; FAR_ALIVE (GPA5, the
modem's cp2ap lines) is bound with its EINTs in the base DT
(FAR-ALIVE-PLAN FA1, FA2). M2.0-M2.4 passed: the modem powers up,
trains Gen1 x1 and enumerates as 144d:a5a5; M3-M5 passed: CPIF and cbd
boot it to **ONLINE** (Gen3 x2) with working IPC (pktproc), no SIM yet;
G1-G2 passed: gnssd loads Kepler's firmware and talks CHPP over SPI;
G3 partial: our HAL client starts sessions, but Kepler's core faults at
engine start. Next: a stock GNSS capture, IOCC, the SIM.
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
