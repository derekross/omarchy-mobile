<!-- SPDX-License-Identifier: MIT -->
# Modem plan (raven / gs101): Exynos 5123 on PCIe channel 0

Status (2026-10-27, `gb3d6253b0d61`): **the modem works as a phone on SIM 1
(tray)**. The eSIM (SIM 2) is switched off by the owner in Android, which
disables its profile on the eUICC, so Linux sees no USIM there; since
device-raven 0.1.23 its sitd (`omamobile-sitd-2`) is opt-in. Since device-raven
0.1.24 the package enables none of the modem's units and ships no
`modem-sit.d/raven.conf` (Derek's review of #41): they come back with the
`omamobile-modem-policy` change in their own PR. Until then a fresh install
starts the modem only after `systemctl enable --now omamobile-modem
omamobile-sitd`. NV baseline:
`~/android/reference/raven-backup-2026-10-27b`.

Earlier status (2026-10-20, `g675676713161`): **the modem works as a phone**:
it boots to ONLINE at every boot (NV only as verified RAM copies), both
SIMs (tray and eSIM, one sitd per modem stack) register, texts go both
ways, an outgoing CS call has audio, and mobile data runs over the data
SIM through the packet processor (uncached for now, section 9 D2). Not
done yet: see "Done means" below. Kernel branch `omamobile-gs101-int`
(worktree `~/android/mainline/wt-gs101-int`, output `out-gs101-int`), the
modem port on `omamobile-gs101-cpif` (`wt-gs101-cpif-pr`,
`out-gs101-cpif-pr`).

**D3, criterion 8 (2026-10-20):** `omamobile-gs101-cpif` 62b4b8193 (NOT FOR
MERGE, like the CPIF import) folds modem-spi-test, modem-cpif-test and
modem-cpif-pktproc into gs101-raven.dts; merged into `omamobile-gs101-int`
(8bc6e0e85, release `g8bc6e0e857f3`). The new base DTB, sorted and without
phandles, is identical to the running overlaid one; `device.conf` drops
the three overlays and they are deleted. First boot on it (asks the human:
push and reboot; risk: low, the device tree is unchanged) is also the
first where only the packages start the modem and both SIMs. Pass: the
boot check's modem, modem-data-path, sim-1, sim-2 and ufs-errors (SIMs
may wait for their PIN), then mobile data. Rollback:
`out-gs101-int/images-g675676713161-pktproc-uncached` (with its modules,
`g675676713161`) and the overlays back in `device.conf`.

**D3 result (2026-10-20, `g8bc6e0e857f3`): passed.** The packages alone
started the modem and both SIMs (neither asked for its PIN this boot);
the boot check: modem, modem-data-path, sim-1 (tray, home EDGE), sim-2
(eSIM, home LTE), ufs-errors 0 all ok (Bluetooth failed this boot, its
known early-boot flake). Mobile data: the bearer SIM 2 set up at boot
(CID 1, raw active 1) carried nothing (the modem took every uplink packet,
one downlink packet came back, also with a steady ping keeping the PCIe
link up, which otherwise idles every few seconds); after `systemctl
restart omamobile-sitd-2` the new bearer (also raw 1) answered at once
(pings 88-249 ms, HTTP in 0.1 s). On D2 the boot-time bearer (raw 2)
worked. Open: why a boot-time bearer can be dead; a watchdog in
omamobile-sit-data (it already probes the bearer) could recreate it.

**Done means the phone works as a phone after a fresh install, with no
hand steps:**

| # | Criterion | State (2026-10-20) |
| --- | --- | --- |
| 1 | The modem boots to ONLINE at every boot, NV only as verified RAM copies | done |
| 2 | Both SIMs register at boot; the PIN on the shell's sheet; the SIMs page picks the data, calls and texts SIM | done |
| 3 | Texts in and out | done |
| 4 | An outgoing call with audio | done (CS) |
| 5 | An incoming call: rings, can be answered, audio both ways | done: 3 of 3 connected with audio both ways (2026-10-20, modem-sit 0.3.43); 0.3.44 starts the audio when the call is up (noise at the pick-up before) |
| 6 | Mobile data through the data SIM | works, uncached; the bearer set up at boot sometimes carries nothing until SIM 2's sitd restarts (D3) |
| 7 | A reproducible install: packages enable the modem, first setup writes the SIM settings; no hand-written `/etc` files | done, then split: device-raven enabled it until 0.1.24 (now the modem PR's job), install-phone asks the APNs, `phone-provision -d raven` brings the modem chroot, board id and NV checksums (checked identical to the phone's) |
| 8 | No bring-up overlays: the modem, CPIF and packet-processor nodes in raven's device tree | done (D3) |
| 9 | 30 minutes of normal use with the modem on (data, a call, texts): no UFS errors, no USB stall | not measured |
| 10 | A modem crash is noticed: CPIF leaves ONLINE, the user is told, the crash record keeps how it started | in progress (D4): the link died after 93 minutes on 2026-10-21 and nothing noticed |

Follow-ups, not blockers: VoLTE (the network refuses the IMS bearer with
2253, so calls use 2G CS, which ends if the network switches 2G off), the
cached packet processor (IOCC not coherent on gs101 yet), the modem's
S2MPU (not ported, as on cheetah), 5G (off on purpose), signal bars, MMS,
emergency-call handling (cheetah's T8), the checksum flag on every
downlink packet.

Template: cheetah's [MODEM-PLAN](../cheetah/MODEM-PLAN.md), where the S5300
boots to ONLINE and serves SIT over PCIe (M4.1h). Raven differs in the
modem (S5123), its first boot stage (SPI) and its pins (section 2).

**Hard rule, as on cheetah:** `efs`, `efs_backup`, `modem_userdata`,
`persist`, `modem_a` and `modem_b` are never written from Linux. The
modem's daemons only ever get RAM copies of verified images.

## 1. M0.1: backup check (2026-10-16, `g83d22c63e946`): passed

The six NV and firmware partitions, found by `PARTNAME`, hashed on the
phone against `~/android/reference/raven-backup-2026-10-15b/SHA256SUMS`
(taken after the GrapheneOS reflash; no stock boot since): all six match,
and all six read `ro=1` at the block layer.

Since 2026-10-20 the baseline is `~/android/reference/raven-backup-2026-10-20`:
GrapheneOS ran again before the reinstall and changed efs, efs_backup,
modem_userdata and persist (modem_a and modem_b are unchanged). Taken
read-only from the reinstalled Omarchy, all six `ro=1` and unmounted, each
image's checksum equal on the phone and the laptop.

## 2. Stock facts (factory image `cp3a.261005.002.a1`, overlay `dtbo_idx` 6)

From the phone's own factory image (`vendor_boot` base DTB and `dtbo.img`
entry 6, board_id 0x20204, which stock booted): `fragment@modemif`.

| What | Raven (S5123) | Cheetah (S5300), for comparison |
| --- | --- | --- |
| Driver | `samsung,exynos-cp`, `mif,name` "s5123", IPC version 0x32, link "PCIE" (`mif,link_attrs` 0xfc8) | CPIF s51xx on GEN4A_0 |
| PCIe | channel 0 (`pci_ch_num`), doorbell `pci_db_addr` 0x40060000 | doorbell 0x14e60000 |
| First boot stage | over SPI bus 9 (`cpboot_spi_bus_num`) | see cheetah M3 |
| AP to CP | power-on gph1-0, reset (nreset_n) gph1-3, PDA active gph1-1, wake gph0-2, dump notification gph0-3 | gph0/gph1 too, other pins |
| CP to AP | wake gpa8-4, PS_HOLD gpa9-5, phone active gpa8-5 | gpa8 |
| Mailbox | SBI layout: ap2cp_msg 0x800, cp2ap_msg 0x804, united status 0x808/0x80c, kerneltime 0x824 (bank 2); boot indicator at 0x90 | same family |
| Memory | `cp_shmem` and `cp_on_chip_0`..`6` reserved regions in the overlay | |
| Baseband | `g5123b-145971-260721-B-15910359` | |

The board's `ro.boot.cdt_hwid`, which cheetah's firmware needed (M4.1),
is in the stock capture (`~/android/reference/raven-stock/getprop.txt`);
it stays out of the repository, as on cheetah.

## 3. Gotcha: GSA's pin controller aborts, not HSI1 (2026-10-16)

`grep … /sys/kernel/debug/pinctrl/*/pins` (all pin controllers at once)
hung the SoC once (the watchdog reset it about 40 s later). Reading each
controller's `pins` on its own (logs/pinctrl-probe-143535.kmsg) found the
cause: **`17940000` (`pinctrl_gsactrl`, GSA's) raises a synchronous
external abort** in `samsung_pinconf_rw` (from `samsung_pin_dbg_show`); the
reader dies holding the bank's lock with interrupts off, which can hang the
phone later. GSA's pins belong to the secure world. Every other controller
reads cleanly, HSI1 (`11840000`, gph0/gph1) included: 14 lines in 8 ms.

Never read `17940000` (or `17a80000`, gsacore) from Linux; reboot after an
abort there. The fix is to keep that node away from Linux on raven.

## 4. M0.2, M0.3 (2026-10-16, `g83d22c63e946`)

**M0.2, ALIVE lines:** passed. The CP's lines to the AP are inputs, low,
pulled down, as ABL leaves them: wake gpa8-4 and phone active gpa8-5
(`174e0000`), PS_HOLD gpa9-5 (`174d0000`): the modem is off.

**M1a (2026-10-16, `g8473e4c23685`):** passed. `pinctrl_gsactrl` is
disabled on raven (`271d72657` on `omamobile-gs101-modem`; the controller
is gone from debugfs). HSI1's gph0-0..5 and gph1-0..6 all read as inputs,
low, pulled down (`CON` 0, `DAT` 0, `PUD` 0x1; power-down state input,
pull-down): the AP drives none of the modem's lines; power-on (gph1-0)
and reset (gph1-3) are low, so the CP is off and held in reset.

**M0.3, HSI1 and PCIe channel 0 (offline, plus clk_summary):**

- `gout_cmu_hsi1_bus` (CMU_TOP) reads enabled `N` after boot, yet HSI1's
  pin registers answer (and the pin driver saves them at every suspend):
  the bus clock gate isn't what feeds them. A CMU_HSI1 driver (mainline
  has none) and HSI1's power domain (on: ABL leaves every domain on, and
  ours isn't in the boot-time off list) matter for PCIe channel 0, M1.
- **PCIe channel 0** is the Wi-Fi channel's IP (`ip-ver` 0x984500, two
  lanes, Gen3): elbi 0x11920000, phy 0x11950000, pcs 0x11940000, dbi
  0x11c00000, config 0x40ffe000, ia 0x11900000, sysreg 0x11820000, SPI
  472, PHY isolation at PMU 0x3ec0 (Wi-Fi: 0x3ec4). Stock's node lists no
  clocks or power domain.

## 5. M1b: CMU_HSI1 (2026-10-16, `g0e4bab6d18ee`): passed

Branch `omamobile-gs101-modem` (worktree `~/android/mainline/wt-gs101-modem`):
`6873cc8b7` binding and clock IDs, `159143abc` the CMU_HSI1 driver (user
muxes for bus and PCIe; gates for PCIe channel 0's controller, PHY, IA
and QE, as CMU_HSI2 has for channel 1; GPIO and SYSREG bus clocks, the
latter critical; offsets from Google's GPL `cal-if/gs101/cmucal-sfr.c`;
no automatic clock gating; unlisted gates untouched), `4b21ebea3` the HSI1
SYSREG compatible, the DT commit (CMU_HSI1 and SYSREG nodes; HSI1's pin
controller clocked from the GPIO gate instead of `<0>`). Merged into
merge-test `0e4bab6d1`. `W=1` clean (driver and DTB); `dt-doc-validate`
clean for both bindings; `dt-validate` reports nothing for HSI1 (the rest
is the known set: soc_id, Trusty, AoC, Wi-Fi memory-region,
orientation-switch).

**Runbook (risk low-medium: a new clock unit registers at boot).** Push
`g0e4bab6d18ee` (same overlays as now). Then, read-only:

```sh
tools/phone-ssh 'uname -r; dmesg | grep -iE "hsi1|11800000|11820000|11840000|clk.*fail" | head
grep -E "hsi1" /sys/kernel/debug/clk/clk_summary
grep -E "gph[01]-[0-3]" /sys/kernel/debug/pinctrl/11840000.pinctrl-samsung-pinctrl/pins'
```

- **Expect:** the phone boots as before; `mout_hsi1_bus_user` and the
  `gout_hsi1_*` clocks listed; `gout_cmu_hsi1_bus` now enabled (`Y`);
  the PCIe gates off after `clk_disable_unused` (nothing uses them); HSI1's
  pins read as in M1a.
- **Pass:** all of the above, then one `rtcwake -m freeze -s 20` (the CMU's
  registers are saved and restored across sleep) and the pins again.
- **Stop:** no SSH after 3 min, an oops naming clk/pinctrl/HSI1, or any pin
  state different from M1a.
- **Rollback:** `out-raven-split/images-g8473e4c23685` with `bin/omamobile
  flash` from fastboot (Volume Down + Power about 20 s); slot A has no OS.

**Result (2026-10-16 16:25, `g0e4bab6d18ee`): passed.** Booted as before.
CMU_HSI1 registered: `gout_cmu_hsi1_bus` now enabled (held by the unit's
`bus` clock), `mout_hsi1_bus_user` on, `gout_hsi1_sysreg_hsi1_pclk` on
(critical), `gout_hsi1_gpio_hsi1_pclk` prepared and enabled around pin
accesses; the PCIe channel 0 gates and `mout_hsi1_pcie_user` off (unused).
No new boot messages (CMU_TOP's "Unable to get CMU sysreg" and
exynos-clkout's -22 were there before). gph0/gph1 as in M1a. One
`rtcwake -m freeze -s 20`: `rc=0`, no clock, HSI1 or UFS error, clocks and
pins unchanged after.

## 6. M1c: the kernel port (offline, 2026-10-16)

Branch `omamobile-gs101-cpif` (worktree `~/android/mainline/wt-gs101-cpif`,
build `~/android/mainline/out-gs101-cpif`), on merge-test `0e4bab6d1`.
Renamed `omamobile-gs101-int` on 2026-10-20: it is the kernel raven runs,
not a subsystem branch. The CPIF and PCIe commits below still need a
branch of their own before a PR:

- `0a5d7b776` NOT FOR MERGE: cheetah's CPIF (`drivers/soc/google/cpif`)
  and `pcie-gs201-cp` from `omamobile-int`, unchanged.
- `12fc8352c` the SPI boot device (`boot_device_spi.c`, Google's, GPL-2.0)
  as module `boot_device_spi` (`CONFIG_BOOT_DEVICE_SPI=m`,
  device/raven/kernel.config); without it the header's stub reports a
  successful load that wrote nothing.
- `72a873c85` `google,gs101-pcie-cp`; the driver takes the clocks the
  node lists (gs101's CMU_HSI1 gates them as unused otherwise).
- `6670043e5` the warm-reset lines optional: the S5123 has none.
- `e1c94298f` gs101 `pcie_0`/`pcie_0_phy` (disabled): stock's addresses,
  SPI 472 as the controller interrupt, CMU_HSI1 clocks, PERST# gph0-0,
  CLKREQ gph0-1, PMU 0x3ec0, sysreg 0x704 (Google's common driver uses
  0x704 for HSI1 on gs101 and gs201).
- `5ae0245c6` alias `spi9 = &spi_9`; `876d89aaa` the modem's lines under
  `pcie_0` (section 2), compatible `samsung,s5123-modem`, no memory yet.

Raven builds merge cheetah's `kernel/configs/omamobile.config`, so
`PCIE_GS201_CP`, `EXYNOS_MODEM_IF`, `SEC_MODEM_S5100`, `SHM_IPC` and the
packet options come from there. Full build clean; `W=1` clean on
`pcie-gs201-cp.c`, `boot_device_spi.c` and the raven DTB; the overlay
`device/raven/overlays/modem-link-test.dtso` applies (pcie@11920000 and
phy@11950000 `okay`). `omamobile-device-raven` 0.1.10 (installed)
blacklists `pcie_gs201_cp`, `cpif`, `shm_ipc` and `boot_device_spi`.

## 7. M2: link only

As cheetah's M2 (its section 3), on a kernel from `omamobile-gs101-cpif`
with `DTB_OVERLAYS="aoc-boot-test aoc-sound-test audio-amps-test gnss-test
modem-link-test"`. No firmware, nothing near the NV partitions. Stream the
kernel log first (`tools/phone-ssh 'dmesg -w'`). Attended: the human at the
phone for every power step. After each step `dmesg | grep
ufshcd_err_handler` must stay empty (cheetah's UFS events, M2.5).

1. **M2.0 bind, read-only:** `modprobe pcie-gs201-cp allow_hw=1`; status in
   `/sys/kernel/debug/gs201-pcie-cp/status`: PMU 0x3ec0 bit 0 = 0
   (isolated), lines as in M1a, the three warm-reset lines `-`.
2. **M2.1 modem power only:** `cp_on`, status after 2 s and 10 s; record
   cp2ap-wakeup, ps-hold, phone-active; then `cp_off`.
3. **M2.2 link at Gen1:** `cp_on`, `link_up`. **Raven caveat:** the S5123
   may wait for its first stage over SPI before its ROM answers on PCIe
   (cheetah's S5300 boots over PCIe alone). "no L0" three times then means
   M3's SPI step comes first, not a fault: record status and the lines,
   then `link_down`, `cp_off`.
4. **M2.4 everything off:** `link_down`, `cp_off`, `rmmod pcie_gs201_cp`;
   PMU bit 0 back to 0, outputs 0, PERST# asserted.

- **Stop:** an oops, a UFS error-handler pass, no SSH for 3 min, or the PMU
  bit not returning to 0.
- **Rollback:** reboot (the overlay only enables nodes; the blacklist keeps
  the drivers out), or the previous images (`images-g0e4bab6d18ee` once
  saved).
- **Risk:** medium: the first time Linux powers raven's modem.

**M2 result (2026-10-16 18:05, `g876d89aaa5ea` = `omamobile-gs101-cpif`
`876d89aaa`, overlays as device.conf plus `modem-link-test`; log
`logs/m2-*.kmsg`): the AP side works; the S5123 doesn't answer on PCIe.**

- **Boot:** no modem module loaded (the blacklist holds); `11920000.pcie`
  and `11950000.phy` present; the PHY driver bound the modem PHY passively
  (clocks off, no output).
- **M2.0 passed:** "modem PCIe ch0 bring-up: 2 lanes, steps enabled, modem
  lines here"; outputs and inputs 0, the three warm-reset lines `-`,
  PERST# asserted, PMU 0x3ec0 = 0 (isolated), MSI not set up (no memory
  region yet).
- **M2.1:** stock's power-on sequence drove pda-active, cp-pwr-on and
  nreset to 1; **no cp2ap line moved in 10 s** (ps-hold, wakeup,
  phone-active 0). Cheetah's S5300 raised cp2ap-wakeup within 2 s. Power-off
  clean.
- **M2.2:** first controller access on raven: the PHY reached **PLL lock 1,
  CDR lock 1, OC done 1**, and the DBI read **ID 0xa5a5144d** (as cheetah):
  CMU_HSI1, the PHY and the controller work. **No L0, LTSSM 0x0
  (Detect.Quiet), three tries:** no receiver on the far end, so the
  modem presents no PCIe endpoint. With M2.1 this fits the S5123 waiting
  for its first stage over SPI before it powers its PCIe side; M3 sends it.
- **M2.4 passed:** all lines 0 (`pda_off`), PERST# asserted, **PMU 0x3ec0
  back to 0** (re-isolated; cheetah needed `c22dc53b3` for this), driver
  unloaded. **No UFS error-handler pass** during the whole test, no oops.

## 8. M3a: the SPI boot stage

**What it is (offline, 2026-10-16).** Google's gs101 CPIF (`kernel/gs`
raviole, `drivers/soc/google/cpif`): cbd sets `IOCTL_SET_SPI_BOOT_MODE`,
powers the modem (`IOCTL_POWER_RESET`), sends an image with
`IOCTL_LOAD_CP_IMAGE`, which `boot_device_spi.c` writes as **one TX-only
transfer** (8-bit words, mode 0, the DT's 2.15 MHz, at most 128 KiB), then
`IOCTL_START_CP_BOOTLOADER`: `start_normal_boot()` sets ap2cp-pda-active,
then on the SPI path **polls cp2ap-wakeup every 20 ms, 200 times (4 s)**
and only then brings the link up (`register_pcie()`). The image: the
**BOOT** entry of `modem.bin` (`images/g5123b-145971-260721-B-15910359/` in
`modem_a`, an ext4 image; read from the 2026-10-15b backup, never from the
phone): TOC at 0, BOOT at 0x320, **0xff50 bytes (65,360)**, load address
0. MAIN (96 MB, load 0x40010000), VSS, APM and the NV entries follow over
PCIe. That explains M2: before BOOT, the ROM neither raises a line nor
presents a PCIe endpoint.

**Built:** `omamobile-gs101-cpif` `usi9` in SPI mode and `spi_9` with
stock's pins and a `cpboot-spi@0` child (`samsung,exynos-cp-spi`, 2.15 MHz),
disabled; overlay `device/raven/overlays/modem-spi-test.dtso` enables them
(checked against the built DTB).

**Runbook (attended, risk medium: the modem runs its own bootloader for the
first time under Linux; it has no NV access at this stage).** Kernel from
`omamobile-gs101-cpif` with `modem-link-test modem-spi-test` added to
`DTB_OVERLAYS` in `device/raven/device.conf` (locally). Stream the kernel
log first. BOOT is cut from the backup on the laptop and sent to `/run`
(RAM), never stored in the repository:

```sh
# TOC entries: name[12], offset, load address, size, CRC, id (32 bytes); BOOT is the second
python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(); assert d[32:44].split(b"\0")[0]==b"BOOT"; o,s=struct.unpack("<I4xI",d[44:56]); open(sys.argv[2],"wb").write(d[o:o+s])' modem.bin boot.bin
tools/phone-ssh 'cat > /run/cp-boot.bin' < boot.bin     # 65360 bytes
tools/phone-ssh 'modprobe spidev bufsiz=131072
echo spidev > /sys/bus/spi/devices/spi9.0/driver_override; echo spi9.0 > /sys/bus/spi/drivers/spidev/bind
modprobe pcie-gs201-cp allow_hw=1; D=/sys/kernel/debug/gs201-pcie-cp
echo cp_on > $D/ctl; sleep 0.1
dd if=/run/cp-boot.bin of=/dev/spidev9.0 bs=65360 count=1
for i in $(seq 200); do grep -q "^cp2ap-wakeup *1" $D/status && break; sleep 0.02; done; grep ^cp2ap $D/status'
# if cp2ap-wakeup is 1: the link at Gen1, then the endpoint's ID
tools/phone-ssh 'D=/sys/kernel/debug/gs201-pcie-cp; echo link_up > $D/ctl; echo atu > $D/ctl; echo id > $D/ctl; dmesg | tail -6'
# always: everything off
tools/phone-ssh 'D=/sys/kernel/debug/gs201-pcie-cp; echo link_down > $D/ctl; echo cp_off > $D/ctl; echo pda_off > $D/ctl
rmmod pcie_gs201_cp; echo spi9.0 > /sys/bus/spi/drivers/spidev/unbind; rm /run/cp-boot.bin; dmesg | grep -c ufshcd_err_handler'
```

- **Pass:** the SPI write returns 65360 bytes; cp2ap-wakeup rises within
  4 s; then L0 at Gen1 and an endpoint `144d:*`.
- **A partial result is still a result:** wakeup rising without L0, or
  neither (record the lines; then the transfer format is next: Google's
  cbd may prepend a header, to check against the stock daemon).
- **Stop:** an oops, a UFS error-handler pass, no SSH for 3 min, the PMU
  bit not back to 0, or `dd` failing.
- **Rollback:** reboot (the overlays only enable nodes; the drivers are
  blacklisted).

**M3a result (2026-10-16, `ga3b605de30cc` = `omamobile-gs101-cpif`
`a3b605de3`, plus `pcie-gs201-cp` from `529d7a390` built for that release in
`/lib/modules/<release>/updates`; overlays as device.conf plus
`modem-link-test modem-spi-test`; logs `logs/m3a-*.kmsg`): the S5123 boots
its bootloader and the link comes up.**

- Boot: `spi9.0` (`spi:exynos-cp-spi`, "feedback delay set to default"),
  no driver bound, no modem module loaded.
- `spidev` (`bufsiz=131072`) bound by `driver_override`; `cp_on`; BOOT
  (65,360 bytes) written in one `dd` to `/dev/spidev9.0` in 0.46-0.56 s.
- **cp2ap-wakeup rose about 460 ms after the write, and cp2ap-ps-hold with
  it**: the modem's bootloader runs and holds its own power. phone-active
  stays 0 (main firmware only).
- First try, `link_up` straight after: **no L0, LTSSM 0x0**, three tries;
  the modem stayed up (wakeup and ps-hold 1). Google's driver raises
  **ap2cp-wakeup 5 ms before the link** when the modem booted over SPI
  (`s5100_poweron_pcie(boot_on = false)`; cheetah's PCIe boot skips it):
  new steps `wake_on`/`wake_off` (`529d7a390`).
- Second try, `wake_on` then `link_up`: **"link up: Gen1 x2 (target Gen1),
  try 1", LTSSM 0x11 (L0).**
- `atu`: **"secure ATU SMC: 0x3"** (refused): cheetah's EL3 owns the iATU,
  but stock gs101's pcie_0 says `use-secure-atu = "false"`: on raven Linux
  programs the outbound ATU itself. `id` then has no window (-67).
- Everything off after each try: lines 0, PERST# asserted, PMU 0x3ec0 back
  to 0, drivers unloaded; **no UFS error-handler pass**, no oops.

**M3b result (2026-10-16, same kernel, `pcie-gs201-cp` from `c8c4930d4`
in `updates/`; log `logs/m3b-*.kmsg`): passed.** The `atu` step programs
gs101's outbound iATU itself (`c8c4930d4`): region 0 CFG0 from the DT's
config window (0x40ffe000, 8 KiB) to bus 1, region 1 MEM from `ranges`
(0x40000000-0x40feffff to PCI 0x14e00000), as Google's `prog_viewport_*`
(whose MEM region stops at 2 MiB). The full sequence: SPI BOOT,
cp2ap-wakeup after about 460 ms, `wake_on`, **link up Gen1 x2 first try,
iATU, "endpoint 144d:a5a5 class 000000"** (Samsung, cheetah's ID too).
Everything off after: lines 0, PERST# asserted, PMU 0x3ec0 back to 0,
drivers unloaded, no UFS error-handler pass, no oops.

## 9. Next

**M3c, first findings (offline, 2026-10-16).** Stock's `cp_shmem`
(`samsung,exynos-cp-shmem`, overlay 6) maps four regions onto four
`exynos,modem_if` carve-outs in the base DTB:

| Region (index) | Carve-out | Size | Note |
| --- | --- | --- | --- |
| IPC (3), cached | `cp_rmem` 0xf0000000 | 8 MiB (region 4 MiB) | cheetah's is at 0xea400000 |
| MSI (11), uncached | `cp_msi_rmem` 0xf6200000 | 4 KiB | as cheetah |
| PKTPROC (7) | `cp_rmem_1` 0xe8000000 | 28 MiB | as cheetah |
| PKTPROC_UL (8) | `cp_rmem_2` 0xee000000 | 4 MiB | |

All four were **System RAM** in our kernel (`/proc/iomem`: 0xe2500000-
0xf87fffff System RAM). Reserved `no-map` in raven's DT (`e23bb70c1` on
`omamobile-gs101-cpif`, 12-byte `reg` entries); takes effect with the next
kernel. **Checked (2026-10-16, `ge23bb70c1189`):** "OF: reserved mem" for
all four (nomap non-reusable), and `/proc/iomem` shows 0xe8000000-0xe9bfffff,
0xee000000-0xee3fffff, 0xf0000000-0xf07fffff and 0xf6200000-0xf6200fff
reserved, cut out of System RAM. Safe to let the modem run past its
bootloader from this kernel on. (`cp_on_chip_*`
in the overlay are the modem's thermal zones, not memory.)

**The CPIF node, raven's stock against cheetah's `modem-cpif-test`
overlay (offline, 2026-10-16):** 69 properties identical, 5 different, 46
raven-only, 1 cheetah-only.

- **Different:** `pci_db_addr` 0x40060000 (cheetah 0x14e60000); `mif,name`
  "s5123"; `mif,link_attrs` 0xfc8 against 0x17c8: the same bits but bit 11
  (`LINK_ATTR_XMIT_BTDLR_SPI`, the bootloader over SPI) where cheetah has
  bit 12 (`LINK_ATTR_XMIT_BTDLR_PCIE`, ROM boot over PCIe); `srinfo_offset`
  0x300 and `srinfo_size` 0x400 (cheetah 0x400000 and 0x300000).
- **Raven-only:** `cpboot_spi_bus_num` (9), `s2mpu`, the packet processor's
  settings (cheetah keeps them in its `modem-cpif-pktproc` overlay), the
  pins and `gpio_ap2cp*`/`gpio_cp2ap*` (ours are the modem node's, M1c).
- **Cheetah-only:** `mif,cp2ap_active_not_alive`.

So raven's `modem-cpif-test` overlay is cheetah's with those values, the
IPC carve-out at 0xf0000000 (region 4 MiB of 8), and `cpboot_spi_bus_num`.

**The modem daemons (offline, 2026-10-16).** `extract-vendor-chroot -d
raven -p modem` (`omamobile-raven-tools`, gs101 reads the modem mount from
`fstab.gs101`) took cbd, rfsd and their 28 libraries and files (13 MB,
`google/raven/raven:17/CP3A.261005.002.A1`) into
`~/android/vendor-chroot-raven-modem` (private). Raven's stock:
- `cbd -d -t ${ro.vendor.cbd.modem_type} -P by-name/modem${slot} -s 2`,
  user radio;
- the modem image `/dev/block/by-name/modem` on `/mnt/vendor/modem_img`
  (ext4, read-only, slot-selected);
- the NV partitions `efs`, `efs_backup` and `modem_userdata` are **ext4**
  (cheetah's are f2fs): the RAM-copy profile needs ext4 images.

**M3c, the rest (offline, 2026-10-16), on `omamobile-gs101-cpif`:**
- `f59d4c61c` + `8ee507659` **gs101's MSIs**: one interrupt (SPI 472)
  carries controller events and MSIs (overlay 6: `use-msi`, no
  `separated-msi`); without an `msi0` line the link driver creates the MSI
  domain alone, enables the MSI edge in ELBI IRQ2_EN (bit 17) and dispatches
  from its controller handler (DesignWare's `dw_handle_msi_irq()` exported).
- `ddeb26724` the MSI page on `pcie_0` and the four carve-outs on the modem
  node, in stock's order.
- `099913a74` CPIF found the modem node by `samsung,s5300-modem` only:
  raven's `samsung,s5123-modem` matches too now.
- Overlay `modem-cpif-test` (`dbb1eb6`): cheetah's with raven's values
  (section 8's comparison); the iodevs are cheetah's (raven's stock lists
  the same channels with `oem_ipc0`-`7` one by one).
- `omamobile-modem` 0.1.5 (`d689082`): depends on a virtual
  `omamobile-modem-policy` (device-cheetah 0.1.32 and device-raven 0.1.11
  provide it) instead of device-cheetah; NV copies mounted as what they are
  (ext4 on raven); on gs101 the profile needs `ro.hardware=raven` and
  `ro.boot.hardware.platform=gs101` in the per-phone props.
- **Raven's NV passes the stock salted checksum** (`omamobile-modem-cp
  nv-check` on copies from the 2026-10-15b backup, deleted after).
- Notes: the four PCIe rails (`vdd085_pcie0/1`, `vdd18_pcie0/1`, LDO16-19M)
  read enabled with 0 users: they survive the 30 s clean-up but nothing
  claims them; the PCIe drivers should. On the SPI path CPIF asks for the
  link at **Gen3** (`s5100_poweron_pcie`, `boot_on` false); raven has only
  trained Gen1 so far.

Built, not flashed: kernel `g099913a744bf` (`out-gs101-cpif/images`, with
`device.conf`'s local `DTB_OVERLAYS` = the four usual plus `modem-spi-test
modem-cpif-test`); packages `omamobile-modem` 0.1.5 and
`omamobile-device-raven` 0.1.11 (`out/unsigned`); the chroot in
`~/android/vendor-chroot-raven-modem`.

### M3d: the first full start (attended; passed 2026-10-16)

As cheetah's M3.4 (its section 3, M3.4.0-M3.4.5), with these raven values:

0. **M0.1 again** (read-only): the six partitions against
   `raven-backup-2026-10-20/SHA256SUMS` (GrapheneOS ran again before the
   2026-10-20 reinstall), all `ro=1`, unmounted.
1. **Per phone, never in the repo:** `/etc/omamobile/modem-nv.sha256` from
   that backup's five lines (modem_a, efs, efs_backup, modem_userdata,
   persist); `/var/lib/omamobile-vendor/modem/props.conf` with
   `ro.boot.cdt_hwid` and `persist.vendor.modem.cdt_hwid` from
   `~/android/reference/raven-stock/getprop.txt`, plus `ro.hardware=raven`
   and `ro.boot.hardware.platform=gs101`.
2. **Install** device-raven 0.1.11 and omamobile-modem 0.1.5 from the local
   repo (copy and `repo-add`), and the chroot (`tar -C
   ~/android/vendor-chroot-raven-modem -cf - root MANIFEST SOURCE STUBS`
   into `/usr/lib/omamobile-vendor/modem`). Enable nothing.
3. **Boot** `g099913a744bf`; no modem module loaded, no UFS pass, the six
   partitions `ro=1`.
4. **Modules, no power:** `modprobe pcie-gs201-cp allow_hw=1; modprobe
   shm_ipc; modprobe boot_device_spi; modprobe cpif trace_lines=1`;
   `modem_state` OFFLINE; `omamobile-vendor-chroot modem check` ends with
   "preconditions met"; the shared memory found ("cp_rmem"/region lines in
   dmesg at the four addresses).
5. **rfsd only** (`OMAMOBILE_MODEM_STAGE=rfsd`): every RAM copy matches,
   the three NV files "stock checksum matches", the baseband version
   `g5123b-145971-260721-B-15910359`, rfsd running, modem OFFLINE.
6. **cbd** (the human at the phone): expect the SPI boot device used
   ("size:65360 bus_num:9"), cp2ap-wakeup, ap2cp-wakeup, the link (Gen3
   asked: if it fails to train, record and stop; a Gen1 cap is the next
   change), then MAIN over PCIe and the CP's boot stages. **Stop** on a UFS
   error-handler pass, an oops, a CPIF crash dump request, or any NV
   checksum change after the run (M0.1 again).

**Results 2026-10-16** (7.3.0-rc6-omamobile-push1-g6efb2b9205c1, `cpif.ko`
rebuilt from `479080536` for that release; the first two tries ran the old
binary: a single-module `make` had rebuilt nothing):
- Step 4 passed: CPIF probes (the three WRST lines reported absent and
  skipped), `link_attrs:0x00000fc8` (BTDLR_SPI set), the four regions at
  f0000000, f6200000, e8000000 and ee000000, `cpboot_spi_probe: bus_num:9`,
  AP2CP_NRESET held at 0, `modem_state` OFFLINE, "preconditions met", no
  UFS error-handler pass.
- Step 5 passed: the five RAM copies match the backup, the three NV files'
  stock checksums match, baseband `g5123b-145971-260721-B-15910359`, rfsd
  verified `nv_normal.bin` and `nv_protected.bin` and waits for the modem,
  modem OFFLINE. Afterwards the five partitions still `ro=1` and their
  checksums unchanged.

- Step 6, first run: the SPI boot (65,360 bytes on bus 9), CP2AP_WAKEUP
  after about 0.6 s, the link at Gen3 x2 first try, the endpoint
  144d:a5a5 enumerated; then the root port's MSI allocation warned in
  `__irq_do_set_handler` and hit the BUG in `msi_domain_activate`: the
  gs101 combined-MSI path had made the domain without the DWC irq_chip.
  cbd died with it; the modem was powered off by the profile's stop, NV
  unchanged, no UFS error. A software reboot then hung in
  `s5100_reboot_handler` (a lock the dead ioctl held): a forced restart.
  Fixed in `20908513e` (both SoCs through `dw_pcie_msi_host_init()`).
- **Step 6 passed** (second run, the fixed `pcie-gs201-cp.ko`): the link at
  Gen3 x2, s51xx probed (doorbell at BAR0 + 0x60000, MSI base IRQ 161),
  BOOTING -> **ONLINE** about 2 s after the SPI boot, cbd "Boot up process
  done", rfsd serving the NV. After 30 s ONLINE: 2315 modem messages over
  MSI, no oops, warning or UFS error-handler pass, NV unchanged. `systemctl
  stop omamobile-modem` powered it off (CP_PWR and NRESET low, OFFLINE).
  Not yet: the SIT bridge (`omamobile-sitd`, `omamobile-mmd`) on raven, and
  a SIM (T2).

- A second start in the same boot stalls in BOOTING: the link comes up
  but the s51xx device stays registered from the first start ("bus already
  registered"), and cbd never sends MAIN. As on cheetah, one start per
  boot; stop only to power off.
- **T1 passed** (cheetah's no-SIM runbook, after a reboot; `omamobile-modem-sit`
  0.3.0 and `omamobile-mmd` 0.1.0 built on the phone, nothing enabled):
  ONLINE 2 s after the boot started, sitd without `--bringup` sent only
  GET_SIM_STATUS, GET_RADIO_POWER and GET_PS_REG_STATE (three each, all
  `error=0`), no AT command, no oops or UFS pass. The bridge exported
  Modem/0; NetworkManager made `umts_ipc0` (gsm, unavailable). Unlike
  cheetah's no-SIM run, the modem reports a SIM: physical, active, and
  `UnlockRequired` 2 (SIM PIN), modem state 2 (locked), `PowerState` 0
  (cheetah: 2). To check against the tray: if no card is in it, sitd
  misreads g5123b's SIM status (142 bytes once the SIM answers).

- **SIM PIN entry, first tries (2026-10-16, the same boot as T1;
  `omamobile-modem-sit` 0.3.1).** The tray holds a
  physical card (physical; one USIM application, AID `A0000000871002`, 16 bytes; no
  label). The eSIM is not visible: only the physical slot is in use.
  Two VERIFY_SIM_PIN requests through `omamobile-sit sim-pin`, the second
  with the PIN shown and confirmed before sending: both `error=3`
  (incorrect password), each spending a PIN try. The owner is sure the PIN
  was right. Checked: the payload is
  byte-for-byte raven's own `ProtocolSimBuilder::BuildSimVerifyPin`
  (vendor.radio.protocol.sit.stream.so: 38 bytes, PIN length at 0x0c,
  ASCII digits zero-padded at 0x0d, AID length at 0x15, AID at 0x16), and
  stock `SimLockHandler::DoVerifyPin` calls that builder with type 0
  (0x0201), no encrypted variant. Not settled: whether the card's PIN is
  the one the owner knows. **Next: the card in another phone with the same
  PIN** (no try spent here). It works there: look again at this path. It
  fails there too: the card's PUK from its carrier. Until then nothing sends
  the last try (sitd refuses it without `last_try`).
- The test sitd (systemd-run, no `--bringup`) leaves `/run/omamobile-sit`
  root-only, so the shell's tile reads "no modem" and `omamobile-sit` says
  sitd isn't running; and the Mobile data tile starts the real
  `omamobile-sitd.service`, which fails on the IPC lock (correctly: nothing
  reached the modem) and resets the directory to root-only again. Fixed by
  hand each time (`chgrp wheel`, 0750). To do: a proper no-SIM/PIN-locked
  mode of the real unit, and a PIN sheet in the shell.

- **The eSIM (2026-10-20, g6efb2b9205c1, `omamobile-modem-sit` 0.3.22):**
  registered on LTE (home), and a text to its own number came back about
  20 s later (CS, `ims = no`). With the tray card in too, the modem keeps
  both stacks active (slot table: tray on logical 0, eSIM on logical 1), as
  GrapheneOS runs them. What it took, in `[network]`: `sim_slot = 1`,
  `stack = 1`, `apn` = the eSIM carrier's.
  - **Stack 1 is its own SIT channel**, `/dev/umts_ipc1`. Moving the eSIM
    onto stack 0 (a one-entry mapping, then the full `[eSIM, tray]` one)
    got the modem to accept SET_PS_SERVICE but never searching: reg state
    0, RAT alternating 3 and 16; a manual AT+CGATT=1 read CREG/CGREG 3.
  - **Radio-config requests only go through stack 0:** stack 1 answers
    GET_SLOT_STATUS with error 6, so sitd maps the slot through a second
    client on `umts_ipc0`. SET_MODEM_CONFIG 2 (stock's SetModemsConfig,
    1 plus phone count > 1) is refused with error 2 while both stacks are
    already active.
  - **The preferred network type is per stack:** stack 1's was 38, set to 9
    (LTE/GSM/WCDMA) at start-up.
  - **SET_UICC_SUBSCRIPTION 1** (stock's BuildSetUicc: one u8) is sent for
    the SIM in use; not shown to be needed.
  - **Incoming calls (2026-10-20, modem-sit 0.3.36-0.3.37, SIM 2):** the
    call rings (IND_CALL_RING, GET_CURRENT_CALLS state 4) and ANSWER
    (stock's BuildAnswer: a bare header) is accepted. Twice the modem then
    listed the call as active while the caller kept ringing into voicemail,
    and no state change came until our hang-up; the third time (right after
    a sitd restart) it connected, the caller's voice came out of the
    Pixel, and the caller's hang-up was reported. 0.3.37 sends CALL_CONFIRM
    (0x000f, stock's SetCallConfirmHandler) on IND_CALL_PRESENT_IND
    (0x0010), but that indication never came, so it didn't take part. Open:
    what made the first two answers fail; the Pixel's microphone on a call.
  - **The PIN:** sitd now serves `omamobile-sit sim-pin` while start-up
    waits for the SIM (0.3.12). A remap restarts the SIM, so it asks again.
  - **Both SIMs at once (modem-sit 0.3.33):** one sitd per stack, both at
    boot, the SIM PIN sheet in the shell, and the SIMs page for the data,
    calls and texts SIM. Only the data SIM gets packet service:
    SET_PREFERRED_DATA_MODEM (0x0740, u8 stack) on it, SET_PS_SERVICE 0
    on the other, which then shows its CS registration.
  - **Open: mobile data on stack 1 carries nothing.** The eSIM's bearer
    (CID 1) comes up with an address, but pings out of `rmnet0` (37 sent)
    get no reply on any of the 30 `rmnet` links, and the address on
    `rmnet8`, `rmnet10` or `rmnet15` didn't help either. Stock gives each
    RIL socket an `ifprefix`/`ifstart`/`ifmaxsize` (libsitril's
    `RilContextParam`); socket 1's `ifstart` is the thing to read, then
    which CPIF channel that interface rides on.
  - **Found offline (2026-10-20):** stock's `RilApplication::OnInitialize`
    builds socket 0 as `/dev/umts_ipc0`, `rmnet`, `ifstart` 0 and socket 1
    as `/dev/umts_ipc1`, `ifstart = ifmaxsize = getIfIndex()` (half the
    rmnet count: 15 of CPIF's 30), so SIM 2's first bearer is `rmnet15`.
    And raven never had the packet processor: cheetah applies
    `modem-cpif-pktproc`, raven didn't, so CPIF ran raven's modem on the
    legacy buffers (calls and texts fine, no IP path). Raven's own
    overlay, `overlays/modem-cpif-pktproc.dtso`, takes stock's values
    (dtbo entry 6): one downlink queue on the shared MSI block, two uplink
    queues, UL at PKTPROC + 0x6000000 = the PKTPROC_UL carve-out. The
    images (`out-gs101-int/images`, same `g675676713161` kernel, the DTB
    plus 32 pktproc lines only) are built; rollback
    `out-gs101-int/images-g675676713161-nopktproc`.

  **D1. The packet processor on (asks the human: push and reboot; risk:
  medium: first run of CPIF's packet processor on gs101 and the S5123).**

  ```sh
  cd ~/projects/omarchy-mobile-raven-device
  sg docker -c "env DEVICE=raven KERNEL_DIR=$HOME/android/mainline/wt-gs101-int \
      KERNEL_OUT=$HOME/android/mainline/out-gs101-int TMPDIR=$HOME/android/tmp-build bin/omamobile push"
  tools/phone-ssh 'ls /proc/device-tree/cpif/pktproc_dl_support; dmesg | grep -E "pktproc|capability"'
  ```

  - **Expect:** `pktproc_get_info: version:2 ... num_queue:1`,
    `pktproc_create: Create queue 0`, the UL info with two queues, then at
    the modem's start `capability part:0 AP:0x00000003`, ONLINE; both SIMs
    register as before; then mobile data on SIM 2 with its bearer on
    `rmnet15`, and a ping through it answers.
  - **Stop:** an Oops, "pktproc_init() error", "UL regions outside", the
    CP not ONLINE or a crash file, `ufshcd_err_handler` beyond 0.
  - **Rollback:** the same push with `images-g675676713161-nopktproc` as
    `images` (or `bin/omamobile flash` from fastboot), and
    `modem-cpif-pktproc` out of `device.conf`.

  **D1 result (2026-10-20, `g675676713161` + the overlay): the packet
  processor runs, data doesn't flow yet.** `pktproc_init: version:2 ...
  num_queue:1`, two UL queues, capability AP 0x3 / CP 0x3, ONLINE, UFS 0,
  both SIMs registered, SIM 2's bearer up (CID 1, IPv4, a private 10.x
  address at the expected place in the 280-byte response). The USB link
  stalled once a few minutes after boot (the phone kept running; a replug
  fixed it). With the address on `rmnet15`: the modem takes every uplink
  packet (UL queue 1 fore/rear 25/25) and nothing comes back (DL rear 0, no
  MSI during the pings), for ICMP and for a TCP connect alike. Scanning
  the address over all 30 links: no reply on any, but two downlink packets
  arrived on `rmnet0`, both counted as checksum failures (`csum`), and none
  reached ping or curl; a raw capture during three more pings saw nothing.
  Reading: the modem may be reading stale uplink buffers through the
  cached mapping (IOCC set as Google does for gs101: DBI 0x8e8 and
  SYSREG_HSI1 0x704).

  **D2: the same with the packet processor's memory uncached (asks the
  human: push and reboot; risk: low on top of D1).** All six `*_rgn_cached`
  to 0; images built, D1's in `images-g675676713161-pktproc-cached`. Pass:
  a ping or a small HTTP request through the bearer answers (try `rmnet0`
  and `rmnet15`). If it works, coherency is the cause and stock's cached
  mapping comes back once IOCC is fixed.

  **D2 result (2026-10-20): mobile data works.** Uncached, SIM 2's (eSIM,
  stack 1) bearer carries traffic on **`rmnet0`**, not `rmnet15`: pings to
  1.1.1.1 answer (46-270 ms), an HTTP request by address answers in 85 ms,
  through `omamobile-sit-data` (Wi-Fi still preferred). So the cached
  mapping was the fault: the modem read stale uplink buffers. Every
  downlink packet is still counted as a checksum failure (`csum`) by the
  packet processor and delivered anyway. Open: why the cached mapping
  isn't coherent on gs101 although DBI 0x8e8 and SYSREG_HSI1 0x704 are set
  as Google sets them (stock maps cached); until then the overlay keeps
  the regions uncached. Stock's socket 1 `ifstart` is not the rmnet index
  on this modem (modem-sit 0.3.35 went back to rmnet<CID-1>).
  - **A CS call works with audio:** `omamobile-sit dial` to the eSIM's own
    number reached its voicemail, and the owner heard it on the phone.

, g6efb2b9205c1, `omamobile-modem-sit`
  0.3.2):** registered on LTE, home network 234-15 (Vodafone UK; the
  owner's tray card), data bearer CID 1 up (not routed: sit-data off).
  What raven needed beyond cheetah:
  - **The SIM slot.** The modem keeps the last Android's mapping: logical
    SIM 0 was physical slot 1, the eSIM (its profile has a PIN). GET_SLOT_STATUS
    (0x024d, 0x111-byte reply: 65 bytes per slot, card/slot state, logical
    slot at +0x24) showed slot 0 = the tray (empty when the tray was out),
    1 = the eSIM, 2 = unused. SET_LOGICAL_TO_PHYSICAL_SLOT_MAPPING [1, 0]
    moved it to the tray. **The two PIN tries of 2026-10-16 went to the eSIM
    profile**, not to the tray card: our PIN path was
    right. `[network] sim_slot = 0`.
  - **The radio through SIT.** After AT+CFUN=1 the modem said CFUN 1 but
    did not search (CEREG 0,0; CREG/CGREG 3), with a valid IMEI that
    matches the bootloader's and a preferred network type of 38, which
    stock's table never sends (set to 9; not the cause). Stock's order,
    SET_RADIO_POWER 1, SET_MODEM_CONFIG 1, SET_RADIO_POWER 2, SET_PS_SERVICE
    1, registered on LTE in 3 s. `[network] radio = sit`.
  - Radio state 10 is RIL's RADIO_STATE_ON (sitd showed "unknown").
  - The tray card keeps its PIN lock: it needs `omamobile-sit sim-pin` at
    every boot (sitd's start-up waits up to sim_timeout and then fails; to
    do: wait for the PIN while serving the socket; later the shell's sheet).
  - **SMS works over CS (2026-10-17, modem-sit 0.3.7).** CS registration
    is SIT 0x0700 byte 0 (1 = home); AT+CREG reads 0 on this modem and is
    misleading. Sending: SEND_SMS 0x0100 (259 bytes: domain, 13-byte SMSC,
    TPDU length, TPDU) was accepted with `ims = no`. Receiving: texts were
    held for hours until sitd sent **SEND_SMS_MEM_STATUS 0x010a, u32 1**
    (room for texts), which stock's `BuildSmsMemoryStatus` sends when the
    radio comes on and sitd never did. Right after it, a text from another
    phone arrived about 1 s after the SMSC's time stamp. Texts sent while
    the memory status was missing never arrived. The CS ack (0x0102,
    `<IBI` success, reference = indication byte 8, cause) matches stock's
    `BuildSmsAck` and `ProtocolNewSmsIndAdapter`.
  - **Sending works (2026-10-17, modem-sit 0.3.10, a second card).** On the
    first tray card every text came back with RP-cause 28 (unidentified
    subscriber; the cause is the u32 at 249 of SEND_SMS's reply, the SIT
    error stays 0) through both the SIM's and Vodafone's published SMSC;
    the card had little credit. Another carrier's card in the tray (no PIN,
    its own APN) went through sitd's whole start-up unattended and its
    text was delivered. Start-up fixes on the way: the slot switch waits
    out a switch in progress (error 7), and SEND_SMS_MEM_STATUS goes after
    registration (error 1 before it).
  - **CS calls work (2026-10-17, modem-sit 0.3.11, the second card).** DIAL
    0x0001 in stock's BuildDial layout rang the other phone: dialing,
    alerting at 5-8 s, active when answered, released by the far end with
    cause 16. GET_CURRENT_CALLS answers with 364-byte entries (state at 0,
    index at 1, TOA at 5, MT flag at 10, call type at 12, number length
    at 14, number at 15); IND_CALL_STATE_CHANGED (0x0009, no payload)
    marks each change. Not yet tested: an incoming call (the other phone
    ran out of credit), call audio (not routed; the AoC voice path is
    next).
  - **IMS is refused:** the IMS bearer (APN ims) fails with status 2253
    whether sitd provisions an IMS profile (type 2, APN type 64), lets the
    modem bring the bearer up itself, or asks for ipv4v6. So no VoLTE, and
    upstream sitd's calls were IMS-only (AIMS_DIAL); 0.3.11 adds CS.
  - sitd can only start once per modem boot (a bearer left from a failed
    start blocks the next: reboot), and it skips itself when started
    before the modem's /dev/umts_ipc0 exists (start it after ONLINE).

- **Risk:** medium: the modem DMAs into reserved memory with no IOMMU, and
  stock's S2MPU for it (`s2mpu` in the cpif node) isn't ported, as on
  cheetah.
- **Rollback:** reboot into `images-ge23bb70c1189`; nothing persistent
  changes (NV only as RAM copies).

## 10. D4: the link died after 93 minutes and nothing noticed (2026-10-21, `g08419862513c`)

- **What happened:** about 93 minutes into a boot (uptime 5586 s) both
  sitds exited together and never came back. CPIF still said ONLINE, so
  the profile's watcher recorded nothing. Mobile data then failed with
  "No internet bearer" every 70 s, and the kernel logged
  `cpif: s51xx_pcie_send_doorbell_int: cmd reg = 0xffff` thousands of
  times a second (`gs201-pcie-cp 11920000.pcie: LTSSM 0x11 ... faults
  0x1`): journald used 70% of a CPU, the journal reached 3.3 GiB, and
  rotation dropped the start, so the trigger is unknown. Wi-Fi was
  unaffected; Chromium kept failing the sites it had tried over the dead
  bearer until it was restarted.
- **Why nothing recovered:** the doorbell that reads all ones calls
  `exynos_pcie_rc_force_linkdown_work()`, which flags LINKDOWN and sends
  CPIF its event. CPIF's answer is a PCIe power-on retry
  (`cp2ap_wakeup_work`), and only the eleventh event forces a CP crash.
  The power-on skips itself ("already powered on": the LTSSM still reads
  L0; or the modem's wake line is low), the fault flag stays set, so no
  second event ever comes, and each later doorbell prints 20 `cmd reg`
  lines and a register dump and returns.
- **Recovery by hand:** `systemctl restart omamobile-modem` left the CP in
  BOOTING (the unit says never to restart it), which tripped the start
  latch: the next boot skipped the modem until `omamobile-modem-start
  --retry` (or removing `/var/lib/omamobile/modem-bringup-started`). A
  reboot, then the latch cleared, brought both SIMs and data back.
- **Fixes (built, not yet on the phone):**
  - kernel (`omamobile-gs101-cpif`): when doorbells still fail 5 s after a
    flagged link-down, declare the CP crash once
    (`CRASH_REASON_PCIE_LINKDOWN_RECOVERY_FAILURE`), so CPIF leaves ONLINE
    and the runtime sees it; the `cmd reg` lines and the register dumps
    are rate-limited;
  - omamobile-modem 0.1.7: a critical notification when the CP leaves
    ONLINE; the crash record keeps the PCIe driver's lines and folds a
    repeated line into a count;
  - omamobile-device-raven 0.1.22: the journal capped at 1 GiB.
- **Next:** what kills the link (the crash record should now keep it);
  then recovery without a reboot (a CP power cycle that reaches ONLINE).

