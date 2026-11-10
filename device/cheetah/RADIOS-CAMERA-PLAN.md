<!-- SPDX-License-Identifier: MIT -->
# Radios and cameras plan: modem, GNSS, NFC, cameras (cheetah / gs201)

Status (2026-10-19): **NFC works** (section 3: the ST54J through st-nci
with our plain-NCI link, loaded at boot; neard reads and writes tags, and a
tag with a web link opens it; N2 results below). The cameras moved to
[CAMERA-PLAN](CAMERA-PLAN.md): all four run in omacam.

Earlier status: **offline survey, 2026-10-12. Nothing has run on the phone.**
Update: GNSS and NFC (N1) are built: see GNSS-PLAN.md and section 3.7. One
kernel piece is built: the HSI1 pin controller that the modem and NFC both
need (section 6). Kernel branch `omamobile-hsi1` in
`~/android/mainline/wt-hsi1`, on `omamobile` @ `7b0f8b5d1`, build in
`~/android/mainline/out-hsi1`. The new node is disabled by default and is
enabled only by `overlays/hsi1-pinctrl-test.dtso`.

**Goal.** Decide the order for the four pieces of hardware still dark after
display, GPU, touch, USB, UFS, Wi-Fi, Bluetooth, haptics and torch: the
cellular modem, GNSS, NFC and the cameras. For each, say what the hardware
is, what Linux has, what userspace needs, the shortest path to "works", and
a first stage that only reads.

Path abbreviations:

- `L/` = our kernel, branch `omamobile-hsi1` (`~/android/mainline/wt-hsi1`)
- `G/` = `~/android/omamobile/out-kernel/google/gs-6.1/private` (Google's GPL gs201 kernel)
- `GS/` = `G/google-modules/soc/gs`
- `CP/` = `G/google-modules/radio/samsung/s5300` (Google's GPL modem interface driver, CPIF)
- `PC/` = `GS/drivers/pci/controller/dwc-whi` (the PCIe driver Google builds for gs201)
- `R/` = `~/android/reference/cheetah-stock-cp2a-root` (stock live DT, dmesg, modules)
- `V/` = `~/android/omamobile/vendor/google/cheetah/proprietary/vendor` (stock vendor files)
- `B/` = `~/android/reference/cheetah-partition-backup-20261011` (raw partition backup, with `SHA256SUMS`)
- `A/` = `~/android/omamobile/vendor/google/cheetah/proprietary/vendor/apex/com.google.pixel.camera.hal.apex`

---

## 0. Ranking and recommended order

| | Value | Effort | Value ÷ effort | Blocking dependencies |
|---|---|---|---|---|
| **GNSS** | 4: location for maps, weather, time zone | 3: port of a 2.8k-line GPL driver, PERIC0 USI5 SPI, three PMIC rails, stock daemons in a chroot | **1.3** | S2MPG13 regulators (ACPM plan step 4); shared vendor chroot |
| **NFC** | 2: tag read/write only; no payments | 1.5: a DT node for a driver mainline already has, a PMU clock bit, config options | **1.3** | HSI1 pinctrl (built) |
| **Modem** | 5: calls, SMS and data make it a phone | 5: second PCIe host mode, CPIF port (28k lines), stock daemons, our own SIT client, AoC for calls | **1.0** | HSI1 pinctrl (built); PCIe ch0 host; shared vendor chroot; AoC (calls only) |
| **Cameras** | 3.5: photos, video calls, QR codes | 5: new CSIS capture driver, four sensor drivers, camera PMIC, CAM/INT DVFS, power domains, C-PHY values only in a proprietary library | **0.7** | ACPM DVFS and regulators; a gs201 power-domain driver |
| USB webcam (UVC) | 1 | 1, after USB-C host mode | 1.0 | USB-C plan B4b, VBUS boost |

**Recommended order:**

1. **Shared foundations first.** They are on everyone's path:
   - HSI1 pinctrl: built (section 6), needs the M0/N0 test.
   - S2MPG12/S2MPG13 regulators over ACPM (ACPM-PLAN.md section 6, step 4):
     GNSS LDO9S-11S, camera LDO12S, and later the fingerprint's LDO15S.
   - One vendor-chroot runner for every Android daemon we keep (section 5),
     grown from `fingerprint/omamobile-fp-chroot`.
2. **GNSS.** Best value for its cost and no new PCIe work.
3. **Modem, data and SMS first.** It is the most valuable piece but the
   longest, so start its read-only stage (M0) and the PCIe ch0 host now, in
   parallel with GNSS. Calls come after the AoC (AOC-PLAN.md).
4. **NFC, as a filler.** It is cheap once HSI1 pinctrl is merged, but has
   little use on a Linux phone. Do it when someone has a free day.
5. **Cameras last.** They wait for ACPM DVFS (CAM, INT) and a power-domain
   driver. Start with the ultrawide and front cameras: their D-PHY setup is
   in Google's GPL source. The main and tele cameras use C-PHY, whose
   settings exist only inside the stock camera HAL (section 4.2).

**Dependencies between the areas:**

```
HSI1 pinctrl ──┬─> modem (PERST#, CLKREQ#, CP control lines)
               └─> NFC (reset, power-idle)
S2MPG13 regs ──┬─> GNSS (LDO9S-11S)
               └─> cameras (LDO12S, SLG51002 enables)
vendor chroot ─┬─> GNSS (lhd, gpsd)
               ├─> modem (cbd, rfsd)
               └─> fingerprint (already designed)
PCIe ch0 host ───> modem only (HSI1; Wi-Fi's ch1 is in HSI2)
AoC ─────────────> modem calls (voice PCM)
ACPM DVFS + PD ──> cameras
USB-C host ──────> UVC webcam
```

**Not in this plan:** the eSEs (ST54J's on SPI, ST33 on SPI11), the UWB
radio (Qorvo, `V/bin/hw/android.hardware.qorvo.uwb.service`) and the laser
autofocus (`stmvl53l1`).

---

## 1. Cellular modem: Samsung Exynos 5300 (S5300, "g5300")

### 1.1 Hardware

| Item | Value | Evidence |
|---|---|---|
| Part | Samsung S5300 external modem; firmware `g5300q-260317-260505-B-15346003` | `R/live.dts:18244` (`mif,name = "s5300"`); `B/modem_a.img:/images/` |
| Link | PCIe **channel 0** (`pcie@11920000`, GEN4A_0 in **HSI1**), 2 lanes, up to Gen3 | `R/live.dts:12053-12091` (`ch-num 0`, `num-lanes 2`, `max-link-speed 3`) |
| Controller regions | ELBI `0x11920000`, UDBG `0x11960000`, PHY `0x11950000`, sysreg `0x11820000`, DBI `0x11c00000`/`0x301000`, PCS `0x11940000`, config `0x40ffe000`, I/A `0x11900000` | `R/live.dts:12056-12057` |
| MEM window | PCI `0x14e00000` = CPU `0x40000000`, 16 MiB | `R/live.dts:12067` |
| Doorbell | `pci_db_addr = 0x14e60000` (in BAR space) | `R/live.dts:18243` |
| Interrupts | MSI, "separated" vectors on GIC SPI 388-393 | `R/live.dts:12058-12059,12073` |
| MSI target | `cp_msi_rmem` `0xf6200000`, 4 KiB | `R/live.dts:165-170` |
| PHY isolation | PMU `0x3ec0` (`pmu-offset`); ch1 is `0x3ec4` | `R/live.dts:12087` |
| Secure ATU | `use-secure-atu`: the outbound iATU belongs to EL3; Linux asks with SMC `0x820020D8` | `R/live.dts:12083`; `PC/pcie-exynos-rc.c:1341-1343,1373-1376`; `PC/pcie-exynos-rc.h:310-311` |
| DMA protection | HSI1 has its **own** SysMMU (`0x11860000`, "PCIe_CH0", VID 0) and S2MPU (`0x11880000`). Nothing else in HSI1 masters the bus | `R/live.dts:9629,12093-12105`; USB is HSI0 (`R/live.dts:14426`), UFS and Wi-Fi are HSI2 |
| Supplies | `vreg1`/`vreg2` (S2MPG12 LDO16M/LDO18M per stock regulator names) | `R/live.dts:12090-12091` |
| PERST#, CLKREQ# | gph0-0 (output), gph0-1 (function 2) | `R/live.dts:3287-3302`; `gpios = <gph0 0 ACTIVE_LOW>` at `12055` |
| AP→CP lines | `ap2cp_wake_up` gph0-2, `ap2cp_dump_noti` gph0-3, `ap2cp_cp_pwr_on` gph1-2, `ap2cp_pda_active` gph1-1, `ap2cp_nreset_n` gph1-3, `ap2cp_cp_wrst_n` gph1-6, `ap2cp_pm_wrst_n` gpa0-3 | `R/live.dts` cpif node, `gpio_*` properties (after 18300) |
| CP→AP lines | `cp2ap_cp_wrst_n` gpa0-2, `cp2ap_phone_active` gpa8-4 (EINT), `cp2ap_cp_ps_hold` gpa8-2, `cp2ap_wake_up` gpa8-3 (EINT) | same; pin states `R/live.dts:3010,3167-3185` |
| Shared memory | `cp_rmem` `0xea400000` 8 MiB (IPC), `cp_rmem_1` `0xe8000000` 32 MiB (packet rings DL 28 MiB, UL 4 MiB), `cp_aoc_rmem` `0x197fd000` 12 KiB (**AoC SRAM**, voice) | `R/live.dts:158-184,18649-18700` |
| Neighbours on HSI1 pins | gph1-0 is the AoC SPI-select line; gph1-4 is the ST54J eSE reset, gph1-5 the NFC reset, gph0-5 the NFC power-idle line | `R/live.dts:3305-3310,7920-7935,8880-8885` |

Our DT already reserves `cp_rmem` and `cp_rmem_1` (kernel `e7cb10fe5`). It
does **not** reserve the MSI page `0xf6200000` yet; stock reserves it
(without `no-map`). Add it before stage M2.

### 1.2 Linux driver state

- **Mainline:** nothing. The WWAN subsystem has no Samsung shared-memory
  driver, and our `pcie-gs201` only does what Wi-Fi needs: INTx, the
  controller programs its own iATU, Gen2 x1.
- **Google downstream (GPL):** two parts.
  - The modem driver CPIF, `CPIF-20220408R1` (`CP/cpif_version.h`), about
    28k lines in 75 files. It makes `/dev/umts_boot0` (boot and power
    ioctls), `umts_ipc` (SIT RIL), `umts_rfs0` (NV file service),
    `umts_router` (AT), `umts_dm0` (diagnostics) and the `rmnet*`
    interfaces (the iodev list is the cpif node in `R/live.dts`). The
    ioctls are `CP/modem_prj.h:56-203` (e.g. `IOCTL_POWER_ON` `0x6f19`,
    `IOCTL_POWER_OFF` `0x6f20`, `IOCTL_GET_CP_STATUS` `0x6f27`).
  - The PCIe RC driver in `PC/`. CPIF drives the link through about 20
    exported functions (`exynos_pcie_poweron`/`poweroff`,
    `register_event`, `l1ss_ctrl`, `chk_link_status`,
    `register_separated_msi_vector`, `set_msi_ctrl_addr`, ...:
    `PC/pcie-exynos-rc.c:4290-5118`), called from `CP/s51xx_pcie.c` and
    `CP/modem_ctrl_s5100.c`.
- **The link does not come up by itself.** CPIF powers the CP through the
  GPIOs first, then asks the RC to train the link, boots the ROM, and
  retrains after the bootloader stage. Before the retrain it raises
  `AP2CP_WAKEUP` and waits 5 ms (`CP/modem_ctrl_s5100.c:1809`).
- **Port needed:**
  1. **PCIe ch0 host mode in `pcie-gs201`.** The PHY driver can be reused:
     it is the same CAL with a 2-lane branch (`PC/pcie-exynos-gs201-rc-cal.c:161,338-361`).
     The controller needs, for ch0 only:
     - MSI through the DWC MSI block with the fixed target `0xf6200000`;
     - the secure-ATU SMC instead of programming the iATU;
     - Gen3 x2;
     - no link at probe. A small API lets the modem driver ask for link
       up and down, the same contract as Google's exports but behind one
       header.
  2. **CPIF on 7.3.** Build it as one out-of-tree module set first, with
     Kconfig matching the stock S5100/PCIe build: shared memory, PCIe,
     pktproc DL/UL, IOCC. Leave out the PCIe IOMMU, DIT, SPI boot,
     thermal and BTL. Fix the API drift (timers, class, netif, GPIO
     lookup). It must return errors instead of panicking. It must **never
     CPU-map `0x197fd000`** (AoC SRAM): that region is the AoC's
     (section 1.5).
  3. Upstreaming is not realistic soon: CPIF is a 28k-line vendor
     framework. Keep it as a separate module set (`kernel/modules/cpif/`
     style) built against our tree. The PCIe ch0 work can stay upstream-style.

### 1.3 Userspace

- **Boot and NV: stock `cbd` and `rfsd`, unchanged, in the vendor chroot.**
  - `V/etc/init/cbd.rc`: `cbd -d -t ${ro.vendor.cbd.modem_type} -P by-name/modem${slot} -s 2`.
  - `V/etc/init/rfsd.rc`: `rfsd -d`.
  - `cbd` needs only `liblog libcutils libjson libz libc++` and `rfsd` needs
    `liblog libutils libcutils libcrypto libc++` (`readelf -d`). No binder,
    so the modem profile needs no binderfs.
  - Firmware: the `modem_a`/`modem_b` partition (ext4,
    `images/g5300q-.../`, `V/etc/fstab.modem`).
  - NV:
    - `efs` and `efs_backup` (f2fs, the IMEI and calibration live here);
    - `modem_userdata` (f2fs);
    - `persist/modem/cpsha`.

    All of these are in `B/` with checksums.
- **NV safety rule (new, hard):** `cbd`/`rfsd` must **never** see the real
  `efs`, `efs_backup`, `modem_userdata` or `persist` read-write. They get
  private copies in RAM, made from verified images, and the real block
  devices are set read-only (`blockdev --setro`) before the modem driver is
  loaded.
  - The properties that pick `cbd`'s behaviour must be pinned: modem type,
    boot mode, `efs.clear.action`, baseband version.
  - An unexpected value can take a factory-reset or image-change path that
    rewrites NV. With private copies, that costs a RAM copy, not the IMEI.
  - The exact property set comes from `strings` on `cbd`/`rfsd` and the
    stock `getprop` capture (`~/android/reference/cheetah-stock-cp2a/getprop.txt`).
- **Control plane: SIT, not AT.**
  - Stock Android drives the modem with `rild_exynos` over `umts_ipc`
    using Samsung's SIT RIL protocol (`V/etc/init/rild_exynos.rc`). The
    AT port (`umts_router`) exists, but Android uses it for nothing
    essential. Expect ModemManager's generic AT plugin to see a partial
    modem at best.
  - SIT is not public. We need our own client, written from the
    request/response layouts that the stock libraries use.
  - Recommended shape:
    1. **M4:** a small daemon (`omamobile-modemd`) for attach, data call,
       SMS and signal.
    2. **Later:** a ModemManager plugin with the same logic, so
       NetworkManager, `mmcli` and any SMS/call UI work unchanged.

    oFono has no SIT driver either, and Omarchy has no oFono UI.
- **Data path:** `rmnet0` (CID 1) is a plain netdev. NetworkManager sees
  it as an unmanaged device until the ModemManager plugin exists; the
  daemon sets the address and a default route with a higher metric than
  Wi-Fi.
- **Calls:** voice PCM goes CP → AoC (the `VSS_AOC` region is AoC SRAM).
  Call audio therefore needs the AoC ALSA path (AOC-PLAN.md). Signalling
  (dial, answer, hang up) is SIT and doesn't need the AoC.
- **VoLTE/IMS:** carriers without 2G/3G fallback need IMS for both calls and
  SMS. IMS registration is a SIT feature of the modem firmware (a second
  PDN on the `ims` APN). Plan for it in M5, not M3.

### 1.4 Minimum path to "works"

"Works" = LTE data plus SMS, with the stock firmware, without touching real
NV. Calls are a later milestone.

| Stage | What | Needs |
|---|---|---|
| M0 | Read-only: partitions verified against `B/SHA256SUMS`, pin states, memory map (runbook below) | nothing new |
| M1 | Kernel: HSI1 pinctrl merged; `cp_msi_rmem` reserved; CP GPIOs described in DT (disabled); CPIF and the PCIe ch0 host built as modules, blacklisted | offline |
| M2 | Link only: power the CP with the GPIO sequence, release ch0 PHY isolation, train Gen1, secure ATU SMC, read `144d:` vendor ID; then power everything off. No firmware sent | M1; hang-safe capture tool like `tools/wifi-w1-capture` |
| M3 | Boot: chroot with private NV, `rfsd` then `cbd`; CP reaches ONLINE (`IOCTL_GET_CP_STATUS`), radio stays off | M2; vendor chroot (section 5) |
| M4 | Data and SMS: `omamobile-modemd` does initial attach, one data call, `rmnet0` up, one SMS each way | M3; SIT client |
| M5 | IMS (VoLTE registration), calls without audio, then with audio | M4; AoC voice path |
| M6 | Boot integration: hang-safe service like `omamobile-wifi`, suspend with the modem online (CP2AP wake as a wake source) | M4 |

### 1.5 Effort, value, risks

- **Effort: large.** PCIe ch0 host: 1-2 weeks; CPIF port: 2-3 weeks;
  chroot profile: days once section 5 exists; SIT client to data and SMS:
  2-4 weeks; IMS and calls: weeks more.
- **Value: highest.** Without it the phone is a small tablet.
- **Risks:**
  - **NV loss.** The IMEI and RF calibration are in `efs`; losing them is
    permanent. Mitigation: the rule in 1.3, plus `B/` backups and a
    checksum check before and after every stage.
  - **SoC hangs from the PHY.** ch1 hung on any ELBI access while the PHY
    was isolated (WIFI-BATTERY-PLAN section 8). ch0 has its own isolation
    bit (`0x3ec0`). Use the same order (isolation release first) and the
    same capture tooling.
  - **DMA.**
    - The modem is a bus master behind HSI1 with access to all of RAM
      unless confined.
    - Unlike Wi-Fi, HSI1's SysMMU and S2MPU serve **only** PCIe ch0, so
      confinement may be possible here; the HSI2 problem was UFS sharing
      VID 0 (WIFI-BATTERY-PLAN 9.20).
    - Stock enables `sysmmu_hsi1` with `pcie-vid-num 0` and
      `use-map-once`. Test it after M4, under the same S2MPU rule as
      before: touch only CTRL0.
    - Until then, use a restricted DMA pool for the endpoint's buffers, as
      for Wi-Fi.
  - **AoC SRAM.** CPIF maps `cp_aoc_rmem` as normal memory on stock. Our
    AoC work owns that SRAM. Mapping it twice, or with a cacheable
    attribute, can corrupt the AoC's state. Keep it unmapped until the AoC
    voice path is designed.
  - **Legal and carrier:**
    - the modem firmware and daemons are Google's and stay on the user's
      phone;
    - a SIT client is interoperability work;
    - emergency calls must not be advertised until they are tested
      end-to-end.
- **Dependencies:** HSI1 pinctrl (built); the vendor chroot (shared with
  GNSS and fingerprint); AoC for call audio; ACPM is probably **not** needed: the
  rails `vreg1`/`vreg2` (S2MPG12 LDO16M/LDO18M) are expected to be on from
  the bootloader. That is unverified (open question 1); M2 fails safely if
  they are off (no link).

### 1.6 Runbook M0 (read-only; current int kernel, no new images)

From the omamobile repo, phone in Arch over USB.

```sh
# M0.1  the modem's NV and firmware partitions are untouched: checksums match the backup.
#       Reads only. ~430 MB from UFS, a minute or two.
tools/phone-ssh 'for p in efs efs_backup modem_userdata persist modem_a modem_b; do
  d=$(grep -lx "PARTNAME=$p" /sys/class/block/*/uevent | head -1 | cut -d/ -f5)
  printf "%s  %s.img\n" "$(sha256sum < /dev/$d | cut -d" " -f1)" "$p"; done' \
  > logs/m0-partitions.sha256
grep -E ' (efs|efs_backup|modem_userdata|persist|modem_a|modem_b)\.img$' \
  ~/android/reference/cheetah-partition-backup-20261011/SHA256SUMS | sort -k2 | diff - <(sort -k2 logs/m0-partitions.sha256)
#   pass: no diff for efs, efs_backup, modem_a, modem_b. persist and modem_userdata
#         may differ if stock Android ran after 2026-10-11; then take a fresh backup
#         before M2 into a new directory on the laptop (tools/nv-backup DIR).
#   also: nothing mounts them
tools/phone-ssh 'grep -E "sda(1|5|6|7|19|29) " /proc/mounts
  grep -xE "PARTNAME=(efs|efs_backup|modem_userdata|persist|modem_a|modem_b)" /sys/class/block/*/uevent'
#   pass: no mount lines. The PARTNAME lines give each partition's sdaN.

# M0.2  memory map: the CP regions must not be System RAM in use.
tools/phone-ssh 'grep -iE "e8000000|ea400000|f6200000|reserved" /proc/iomem | head -20'
#   expect: e8000000-e9ffffff and ea400000-eabfffff reserved (no-map, e7cb10fe5).
#   0xf6200000 is probably inside "System RAM": that is the M1 DT fix (reserve it).

# M0.3  CP lines on ALIVE/FAR_ALIVE (controllers already bound in int; debugfs reads registers only)
tools/phone-ssh 'P=/sys/kernel/debug/pinctrl; grep -hE "\((gpa0-[23]|gpa8-[234])\)" $P/*180d0000*/pins $P/*180e0000*/pins'
#   record CON/DAT/PUD for each. Expect inputs (CON 0) or EINT (0xf), DAT 0 (CP off).
#   Note the PUD of gpa8-3 (cp2ap_wake_up): stock's DT sets pull-down (1); if ABL left
#   something else, keep ABL's value in our DT until a test proves the stock one.

# M0.4  HSI1 lines (gph0/gph1). Needs omamobile-hsi1 merged into int, built, and the overlay
#       applied with the usual helper (as in AUDIO-PLAN.md, KERNEL_OUT = the int out dir):
#   O=$KERNEL_OUT D=$O/arch/arm64/boot/dts/exynos/google/gs201-cheetah.dtb
#   ov() { cp -n "$D" "$D.default"; local o= n
#     for n; do $O/scripts/dtc/dtc -q -I dts -O dtb -o out/$n.dtbo device/cheetah/overlays/$n.dtso; o="$o out/$n.dtbo"; done
#     $O/scripts/dtc/fdtoverlay -i "$D.default" -o "$D" $o; bin/omamobile images; }
#   ov hsi1-pinctrl-test && bin/omamobile push          # reboots
#   pass first: USB/SSH, UFS, touch, Wi-Fi as before; the controller registered
tools/phone-ssh 'ls /sys/kernel/debug/pinctrl/ | grep 11840000; dmesg | grep -i 11840000'
tools/phone-ssh 'grep -hE "\((gph0-[0-5]|gph1-[0-6])\)" /sys/kernel/debug/pinctrl/*11840000*/pins'
#   expect PERST# gph0-0 output low or input; CP control lines inputs or low outputs.
#   rollback: images without the overlay.
```

Do **not** read PMU registers (`0x18060000` and up) from user space. One
`/dev/mem` read in the G3D range reset the phone (GPU-PLAN.md). The ch0
isolation bit (`0x3ec0`) is read in-kernel through the regmap in M2.

---

## 2. GNSS: Broadcom BCM4775x on SPI

**In one line:** port Google's GPL `bbd` + `bcm_gps_spi` driver, keep the stock `lhd` and
`gpsd` daemons in the vendor chroot, and feed their NMEA output to the Linux
`gpsd` and GeoClue.

### 2.1 Hardware

| Item | Value | Evidence |
|---|---|---|
| Part | Broadcom BCM4775x family (stock module `bcm47765.ko`, node `bcm4775@0`) | `R/modules.txt`; `R/live.dts:8603` |
| Bus | **SPI5** = PERIC0 USI5 at `0x10940000` (USI offset `0x10` in `sysreg_peric0`), DMA mode on stock | `R/live.dts:8595-8602` |
| SPI | 26 MHz max (`spi-max-frequency 0x18cba80`), mode 3 (CPOL, CPHA), feedback delay 1, chip select by the controller (mode 0) | `R/live.dts:8606-8622` |
| `nstandby` | gph2-3 (HSI2), output; DT flag active low | `R/live.dts:8614,3509-3515` |
| `mcu_req` | gpp4-3 (PERIC0), output | `R/live.dts:8613,4238-4244` |
| `mcu_resp` | gph2-2 (HSI2), input, pull-down | `R/live.dts:8616,3500-3506` |
| `host_req` | gpa6-4 (FAR_ALIVE), EINT, no pull | `R/live.dts:8615,3129-3135` |
| PPS | gpp15-1 (PERIC0), stock `bbd-pps-gpio` | `R/live.dts:17747-17753` |
| Rails | S2MPG13 LDO9S (0.725-1.3 V), LDO10S and LDO11S (1.6-1.95 V); `regulator-always-on` on stock | `R/live.dts:14072-14104` |
| Firmware | `SensorHub.patch` (loaded by `lhd` over the SPI link) | `V/firmware/SensorHub.patch`; `V/etc/gnss/lhd.conf` |
| Reference clock | 26 MHz TCXO, 2 ppm (`FrqPlan="FRQ_PLAN_26MHZ_2PPM_49_152MHZ_300PPB"`) | `V/etc/gnss/gps.xml` |

Our int DT has the PERIC0, HSI2, ALIVE and FAR_ALIVE pin controllers. USI5
and its SPI node are not described yet. The rails are not reachable until
the S2MPG13 regulator driver exists. Whether ABL leaves them on is the first
thing G1 must find out.

### 2.2 Linux driver state

- **Mainline:** nothing for this chip. `drivers/gnss/` has serial-NMEA
  drivers only; the BCM4775x speaks Broadcom's binary protocol (SSI framing
  on SPI, LHE/ESW messages above it) and needs a patch from the host at
  every power-up.
- **Google downstream (GPL):** `G/google-modules/gps/broadcom/bcm47765/`:
  - `bbd.c` (884 lines): the `/dev/bbd_*` char devices;
  - `bcm_gps_spi.c` (1632 lines): SSI framing, the MCU_REQ/MCU_RESP
    handshake, `/dev/ttyBCM`;
  - `bcm_gps_regs.c`;
  - `bbd_pps_gpio.c`.

  Stock dmesg: `GPSBBD: registered /dev/bbd_sensor ... bbd_control ...
  bbd_patch ... bbd_pwrstat` (`R/dmesg.txt`).
- **Port needed:**
  - **First pass:** the driver as one module.
    - Device nodes and the `nstandby` sysfs file exactly as `lhd` expects.
      The path is configurable: `GpioNStdbyPath` in `lhd.conf` and
      `gps.xml`.
    - Regulators, not raw PMIC writes.
    - The standard SPI core with our `spi-s3c64xx` gs201 support (already
      used for touch on USI0).
    - Keep the 1 Hz statistics timer out. `bbd_resume()` turns it on after
      every resume (`bbd.c:633-646`), which would wake an idle phone every
      second, but only when `DEBUG_1HZ_STAT` is defined, and Google's
      build leaves it out (`bbd.h:62`). The port drops that code.
  - **Upstream path, later:** a `drivers/gnss/` driver that exposes the raw
    SSI stream as `/dev/gnssN`, with `nstandby` and `mcu_req` handled in
    the kernel. It only works if `lhd` can live without `bbd_control`
    feedback: open question 3.
  - **PPS:** mainline `pps-gpio` on gpp15-1 instead of Google's `bbd_pps`.
    Point `PpsDevice` at it, or set `PpsEnable=false` until it is tested.

### 2.3 Userspace

- **Stock daemons, from `V/etc/init/init.gps.rc`:**
  - `lhd /vendor/etc/gnss/lhd.conf` loads the patch and runs the chip. It
    only needs `libz liblog libutils libhardware_legacy libc++`.
  - `gpsd -c /vendor/etc/gnss/gps.xml` is Broadcom's position engine, not
    the Linux gpsd. It links `libbinder_ndk`, the sensor-service NDK and
    `libsitril-gps` (control-plane A-GNSS through the modem), so its
    profile needs binderfs and quick failure of those lookups. That is the
    same shim job as the fingerprint HAL's power-HAL and `ISensorManager`
    stubs.
  - `scd` (sensor core) and `android.hardware.gnss@2.1-service-brcm` (the
    HAL) are **not** needed.
- **Output, from `V/etc/gnss/gps.xml`:**
  - `NmeaOutName="/data/vendor/gps/nmea_out"` is a FIFO with NMEA.
  - `CtrlPipe="/data/vendor/gps/glgpsctrl"` is the engine's control pipe.

  The bridge reads the FIFO and serves it to the Linux `gpsd` (as a pty or
  a `gpsd` `/dev/...` source). GeoClue then uses gpsd or its NMEA source.
  If the engine only produces positions while a HAL session is open, the
  bridge sends the start/stop requests through `CtrlPipe` (open question 4).
- **Assistance:**
  - `HttpSyncLto="true"` downloads `lto2.dat` (orbit predictions) over the
    internet; this works once Wi-Fi is up.
  - SUPL to `supl.google.com` with `gps.cer`.
  - Control-plane assistance through `libsitril-gps` needs the modem; skip
    it until M4.
- **State:** `NvStorageDir=/data/vendor/gps/` must be persistent and
  private: `/var/lib/omamobile/gnss`, bound into the chroot.

### 2.4 Minimum path to "works"

"Works" = a position fix outdoors shown by `gpspipe -r` / GeoClue's
`where-am-i`.

| Stage | What | Needs |
|---|---|---|
| G0 | Read-only pin states; offline extraction of `lhd`/`gpsd` closure | nothing new |
| G1 | S2MPG13 regulator driver (read-only first: report LDO9S-11S state) | ACPM plan step 4 |
| G2 | DT: USI5 SPI, the GNSS node, pins; driver module; `nstandby` high; one SSI status read, the first transfer of `bcm_ssi_rx()` (`bcm_gps_spi.c:812`) | G1 |
| G3 | `lhd` in the chroot loads `SensorHub.patch` and writes `BBD:PassThru=0`, then `ESW:READY` (strings in `lhd`) | section 5 |
| G4 | `gpsd` (Broadcom) running, NMEA from the FIFO, a fix outdoors | G3 |
| G5 | Bridge to Linux gpsd/GeoClue; service with hang-safe start; suspend check | G4 |

### 2.5 Effort, value, risks

- **Effort: medium.** Driver port 3-5 days; DT and SPI 1-2 days; chroot
  profile and bridge 3-5 days. Most of the time goes to the G1 regulator
  dependency, which other work needs anyway.
- **Value: high.** Location is used by maps, weather, time zone and the
  camera (geotags).
- **Risks:**
  - Low for the hardware.
  - Shared HSI2 pins: gph2-0/1/4/5 are Wi-Fi's. The GNSS node must claim
    only gph2-2/3.
  - A spurious `host_req` interrupt storm: no pull on stock. Check
    `/proc/interrupts` in G2.
  - `gpsd`'s binder and modem-client dependencies may block start-up.
    Check in the chroot with a 30 s timeout first.
- **Dependencies:** S2MPG13 regulators; vendor chroot (with binderfs);
  Wi-Fi for LTO/SUPL (done).

### 2.6 Runbook G0 (read-only; current int kernel)

```sh
# G0.1  pin states (registers read through the bound pin controllers' debugfs)
tools/phone-ssh 'P=/sys/kernel/debug/pinctrl; grep -hE "\((gph2-[0-5])\)" $P/*14440000*/pins;
  grep -hE "\((gpp4-3|gpp10-[0-3]|gpp15-1)\)" $P/*10840000*/pins; grep -hE "\((gpa6-4)\)" $P/*180e0000*/pins'
#   expect: gph2-3 (nstandby) input or output-low (chip in standby); gph2-2 input;
#   gpp10-0..3 (USI5 SPI pins) as ABL left them; gpa6-4 input/EINT. Record all; the G2 DT
#   must reproduce stock's functions (R/live.dts:3129,3500,3509,4238) for these pins only.
# G0.2  nothing has claimed the SPI5 block or the pins
tools/phone-ssh 'ls /sys/bus/platform/devices/ | grep -i 10940000; grep -h "gph2-[23]\|gpp4-3\|gpa6-4" /sys/kernel/debug/pinctrl/*/pinmux-pins'
#   expect: no 10940000 device; pins "(MUX UNCLAIMED)".
# G0.3  (laptop) the stock files we will need are present in the user's vendor image
V=~/android/omamobile/vendor/google/cheetah/proprietary/vendor
ls -l $V/bin/hw/lhd $V/bin/hw/gpsd $V/firmware/SensorHub.patch $V/etc/gnss/{lhd.conf,gps.xml,gps.cer}
readelf -d $V/bin/hw/gpsd | grep NEEDED     # the closure the extract tool must follow
```

No rail, SPI or PMIC access in G0. G1 belongs to the ACPM/PMIC work.

---

## 3. NFC: ST54J (ST21NFC-family NCI controller) on I2C

### 3.1 Hardware

| Item | Value | Evidence |
|---|---|---|
| Part | ST **ST54J** combo (NFC controller + eSE); NFC side is ST21NFC-family NCI. Stock module `st21nfc.ko` "version 2.0.1A"; eSE driver says "ST54J Combo" | `R/dmesg.txt` (`st21nfc_dev_init`, `st54spi ... ST54J Combo`) |
| Bus | Google I2C 8 = PERIC0 USI8 HSI2C `0x10970000` (our `hsi2c_8`, already up for haptics), address **`0x08`** | `R/live.dts:7920-7922`; HAPTICS-TORCH-PLAN.md 1.1 |
| IRQ | gpa9-1 (ALIVE), `irq-gpios` | `R/live.dts:7925-7928` |
| Reset | gph1-5 (**HSI1**), active high in the DT | `R/live.dts:7929` |
| CLKREQ | gpp25-3 (PERIC1), input | `R/live.dts:7930` |
| Power-idle | gph0-5 (HSI1), active low, used only for power statistics | `R/live.dts:7931-7932` |
| Reference clock | PMU `PAD_CTRL_CLKOUT1` (`0x3e84`, bit 0) while the device is open, plus clock `nfc_ref_clk` | `R/live.dts:7933-7935`; `G/google-modules/nfc/st21nfc.c:40,191-200,542-570`; `L/include/linux/soc/samsung/exynos-regs-pmu.h:994` |
| Firmware/config | `st54j_fw.bin`, `st54j_conf.bin` (the stock HAL updates them when versions differ) | `V/firmware/`; `V/etc/libnfc-hal-st.conf` (`STNFC_FW_BIN_NAME`, `STNFC_FW_CONF_NAME`) |
| eSE (do not touch) | ST54J eSE on SPI (`st,st54spi`, reset gph1-4); ST33 on SPI11 | `R/live.dts:8880-8895,9431-9447` |

### 3.2 Linux driver state

- **Mainline:** `drivers/nfc/st-nci/` (NCI over I2C, `st,st21nfcb-i2c` /
  `st,st21nfcc-i2c`) plus the NCI core, which handles NCI 2.0 init
  (`L/net/nfc/nci/core.c:518`). It needs `reset-gpios` and an interrupt;
  `ese-present`/`uicc-present` are optional (`L/Documentation/devicetree/bindings/net/nfc/st,st-nci.yaml`).
  - Whether the ST54J's NFC core answers `st-nci`'s init unchanged is the
    question N2 answers.
  - Expect a new compatible (`st,st54j-nci-i2c` or similar) with at most a
    quirk.
- **Google downstream:** `G/google-modules/nfc/st21nfc.c` is a raw char
  device for the vendor HAL (ioctls `ST21NFC_*`). We don't need it.
- **Kernel config:** `CONFIG_NFC_NCI=m`, `CONFIG_NFC_ST_NCI_I2C=m` (N1).
- **The clock:** mainline had no provider for the PMU's CLKOUT pads on
  gs201. Built on `omamobile-nfc` (section 3.7): the pads in
  `clk-exynos-clkout` through the PMU regmap, and an optional clock in
  st-nci that runs while the controller is powered up.

### 3.3 Userspace

- **neard + `nfctool`** (kernel NFC API, `AF_NFC`) for polling and NDEF
  read/write, or a small AF_NFC tool of ours.
- **No payments, no card emulation of secure applets.** Those go through
  the eSE and Google Wallet. Nothing to gain on Linux.
- **The stock HAL (`android.hardware.nfc-service.st`) is not used.** Its one
  job we lose is the firmware/config update. The controller keeps the
  firmware Android last installed, so never flash `st54j_fw.bin` from Linux.

### 3.4 Minimum path to "works"

"Works" = `nfctool -d nfc0 -p` sees a tag and reads its UID.

- **N0:** read-only pins (runbook below).
- **N1:** DT node on `hsi2c_8` with the four lines, the clock bit, config
  option; build only.
- **N2:** bind `st-nci`; NCI CORE_RESET/INIT succeed (`dmesg`, `nfc0` in
  `nfctool -l`).
- **N3:** poll and read a tag.

### 3.5 Effort, value, risks

- **Effort: small**, 2-4 days, mostly the clock and the first NCI
  exchange.
- **Value: low-medium.** Tags, NDEF, maybe pairing. Little software on the
  Linux side uses it.
- **Risks:**
  - The eSE shares the chip. Never toggle gph1-4 (eSE reset), never open
    the eSE SPI.
  - Never run the firmware updater.
  - The NFC node has no supply property, so the chip runs from a rail
    stock keeps always on. In our S2MPG13 regulator DT, keep every rail
    stock marks `regulator-always-on` (LDO14S `L14S_ALIVE` among them,
    `R/live.dts` S2MPG13 LDO14) always on, with no consumer able to
    disable it.
- **Dependencies:** HSI1 pinctrl (built). Nothing else.

### 3.6 Runbook N0 (read-only)

```sh
# N0.1  the bus and the address: who is bound (no scan, no transfer to 0x08)
tools/phone-ssh 'ls /sys/bus/i2c/devices/; for d in /sys/bus/i2c/devices/i2c-*; do echo "$d $(readlink -f $d/of_node | sed s,.*/,,)"; done'
#   expect the haptics bus (10970000.i2c) with only 8-0043 bound. Do NOT run i2cdetect on it.
# N0.2  IRQ and CLKREQ lines (bound controllers)
tools/phone-ssh 'P=/sys/kernel/debug/pinctrl; grep -hE "\((gpa9-1)\)" $P/*180d0000*/pins; grep -hE "\((gpp25-3)\)" $P/*10c40000*/pins'
# N0.3  reset and power-idle (needs omamobile-hsi1 merged + overlay hsi1-pinctrl-test, as M0.4)
tools/phone-ssh 'grep -hE "\((gph0-5|gph1-[45])\)" /sys/kernel/debug/pinctrl/*11840000*/pins'
#   record: gph1-5 (NFC reset) and gph1-4 (eSE reset) levels. Expect both released (high)
#   or both held: whatever ABL left is the state N2 must start from.
```


**N2.4b-N2.6 result (2026-10-12, 7.3.0-rc6-omamobile-push1-00345-g606b84c7a9fd,
omamobile-nfc 3502821fa merged): passed.** `gs101_pad_en_active_low` N (the
default polarity). Bind: nfc0, IRQ 127 count 1. `nfctool -d nfc0 -1` rc 0,
"Powered: Yes", protocols Felica MIFARE Jewel ISO-DEP NFC-DEP ISO-15693; the
IRQ count rose 1 → 9; two "nci_ntf_packet: unsupported ntf opcode 0xf02"
lines (ST proprietary notifications, ignored). A 10 s poll with no tag found
nothing, as expected. Power down rc 0, power up again rc 0 (the hard_fault fix
holds), power down. CONFIG_DYNAMIC_DEBUG is off in our config, so the
per-frame debug lines weren't available; enable it if a later stage needs
them. N3 (a tag's type) waits for the human with a card.

### 3.7 Built (2026-10-12): stages N1-N3

Kernel branch `omamobile-gnss` (GNSS-PLAN.md section 2), merged into int:
- `cad9624c0`: `st,st54j-i2c` in the st-nci binding;
- `ec375b274`: `nfc@8` on `hsi2c_8`, `interrupts-extended = <&gpa9 1
  IRQ_TYPE_LEVEL_HIGH>`, `reset-gpios = <&gph1 5 GPIO_ACTIVE_HIGH>` (st-nci
  pulses 0 then 1, like Google's driver), no `ese-present`/`uicc-present`;
  disabled. The reset pin group only sets power-down states, as stock.
- `CONFIG_NFC_ST_NCI_I2C=m` (`st-nci.ko`, `st-nci_i2c.ko`);
- overlay `overlays/nfc-test.dtso`, which enables the HSI1 pin controller
  and the node.

Kernel branch `omamobile-nfc` (worktree `~/android/mainline/wt-nfc`, output
`~/android/mainline/out-nfc`), on int `e821a4bec`, head `a6ed1ea8b`:
- `2f769ea68` dt-bindings: one optional `clocks` entry for st-nci.
- `40a8b3779` `clk-exynos-clkout`: the gs101/gs201 PMU pads. One gate per
  pad (`pmu-clkout0`, `pmu-clkout1`) through the PMU's SMC-backed regmap,
  never MMIO. Enable writes `PAD_CTRL_CLKOUTn` bits 13:8 = 0 (TCXO) and bit
  0 = 1; disable clears bit 0. `CLK_IGNORE_UNUSED`: the kernel leaves both
  pads as ABL left them until a consumer enables one. The driver is
  built in (`CONFIG_EXYNOS_CLKOUT=y`), so it binds at every boot once
  merged; before this it failed with "cannot match parent device".
- `9b7ba4873` st-nci i2c: the clock runs from before reset is released
  (`nfctool -1`, NCI power-up) until power-down (`nfctool -0`), as Google's
  st21nfc.c does around open/release. Nothing at probe.
- `829e25aed` st-nci: with neither `ese-present` nor `uicc-present`, power-up
  skips the HCI network set-up. Upstream st-nci otherwise clears every HCI
  pipe in the controller and writes its own session identity on the first
  Linux power-up (`nci_hci_dev_session_init()`), which would undo the pipes
  Android's NFC stack set up to the eSE. With this, Linux sends only NCI
  core and RF commands.
- `e4e3913df` gs201.dtsi: the PMU node is a clock provider
  (`#clock-cells = <1>`, `clocks = <&oscclk>`, `clock-names = "clkout0"`).
- `a6ed1ea8b` cheetah: `clocks = <&pmu_system_controller 1>` on `nfc@8`
  (stock: `clocks = <&clock CLKOUT1>`, `pmu_clk_pad = <0x3e84>`).

Checks (build `7.3.0-rc6-omamobile-push1-00291-ga6ed1ea8b5af` in
`out-nfc`): checkpatch clean apart from the missing Signed-off-by (the
human signs off) and the already undocumented `google,gs201-pmu`; W=1
clean for the four changed C files; `dt-doc-validate` passes for st,st-nci;
`dt-validate` of the default DTB and of default + nfc-test shows only the
two warnings that were there before (`soc_id`, simplefb), none for `nfc@8`
or the PMU node.

**Bit 0 polarity is the open question.** Google's sources disagree:
st21nfc.c sets bit 0 while the device is open, and its `ST21NFC_CLK_STATE`
reports bit 0 as "on"; the cal-if clkout code (`ra_enable_clkout()`) clears
it on enable. We follow st21nfc.c, the driver tested with this chip. N2.2
records ABL's state of the pads; if N2.4 times out with the clock "on",
the next build inverts the gate (one-line change in the driver). Never
test it by writing the PMU from userspace.

Userspace:
- `packages/neard`: neard 0.20 with `nfctool` (Arch Linux and Arch Linux
  ARM don't package it; Omarchy doesn't either). Built without eSE
  support; `neard.service` installed, not enabled.
- `packages/omamobile-device-cheetah/vendor/modprobe.d/omamobile-nfc.conf`:
  `blacklist st_nci_i2c`, so the nfc-test DTB never loads the driver at
  boot. The runbook loads it by hand. (Package version bump pending.)
- Quick settings: the NFC tile runs `rfkill block|unblock nfc`. The NFC
  core registers one rfkill switch per adapter (type `nfc`) when st-nci
  binds, so the tile shows "No NFC" before N2.3 and "On"/"Off" after.
  Blocking powers the controller down and refuses power-up; unblocking
  only allows it. Something must still power the adapter up (neard with
  `DefaultPowered`, or `nfctool -1`).

Never run i2cdetect on this bus, never run `nfctool -w` (firmware download),
never write `st54j_fw.bin` from Linux, never add `ese-present` to the node,
and never touch gph1-4 (eSE reset).

#### Runbook N2: bind st-nci, NCI power-up

Laptop first. The human merges `omamobile-nfc` into `omamobile-int`.

```sh
export KERNEL_DIR=~/android/mainline/wt-int KERNEL_OUT=~/android/mainline/out-int
bin/omamobile kernel && bin/omamobile modules
O=$KERNEL_OUT D=$O/arch/arm64/boot/dts/exynos/google/gs201-cheetah.dtb
rm -f "$D.default"     # the new base DTB carries the PMU clock provider; refresh ov's copy
# ov() as in M0.4 (section 1.6)
```

```sh
# N2.1  blacklist and tools on the phone first (risk: none; package installs only)
tools/phone-install-package packages/omamobile-device-cheetah    # after the version bump
tools/phone-install-package packages/neard
tools/phone-ssh 'modprobe -c | grep -c "^blacklist st_nci_i2c"; ls /etc/modprobe.d/;
  systemctl is-enabled neard; command -v nfctool'
#   pass: 1; no NFC file in /etc/modprobe.d; neard "disabled"; /usr/bin/nfctool.
#   stop: blacklist count 0. Don't install a DTB with nfc-test until it is 1.

# N2.2  boot with nfc-test (risk: low; the driver stays unloaded)
#   keep the overlays the phone already boots with, add nfc-test, e.g.:
ov gnss-pmic-test gnss-test aoc-boot-test nfc-test && bin/omamobile push    # reboots
tools/phone-ssh 'uname -r; lsmod | grep -c "^st_nci"; dmesg | grep -iE "clkout|st.nci|nfc";
  grep -E "pmu-clkout|oscclk" /sys/kernel/debug/clk/clk_summary;
  grep -hE "\((gph0-5|gph1-[45])\)" /sys/kernel/debug/pinctrl/*11840000*/pins'
#   pass: USB/SSH, UFS, touch, Wi-Fi, sound as before; 0 st_nci modules; no clkout error;
#   pmu-clkout0 and pmu-clkout1 under oscclk, enable count 0, rate 24576000.
#   record: the hardware-enable column of both pads (ABL's bit 0; a kernel regmap read).
#   record: gph1-5 output high, gph1-4 output low, gph0-5: as N0 (2026-10-12).
#   stop: no SSH within 2 minutes (the watchdog resets the phone), or any pin changed.
#   rollback: cp "$D.default" "$D"; bin/omamobile images && bin/omamobile push

# N2.3  bind (risk: low; no NCI traffic: probe only requests reset (already high) and the IRQ)
tools/phone-ssh 'modprobe st_nci_i2c; sleep 1; dmesg | grep -iE "st.nci|nfc" | tail;
  ls /sys/class/nfc/; rfkill -rn -o TYPE,SOFT,HARD | grep "^nfc";
  cat /sys/kernel/debug/clk/pmu-clkout1/clk_enable_count;
  grep -hE "\((gph1-[45])\)" /sys/kernel/debug/pinctrl/*11840000*/pins'
#   pass: nfc0 (8-0008 bound to st_nci_i2c); rfkill "nfc unblocked unblocked";
#   clk_enable_count 0; gph1-5 still high, gph1-4 unchanged. The NFC tile shows "On".
#   stop: "Unable to get reference clock" (the PMU provider did not register: check N2.2),
#   or any I2C error on bus 8 (haptics shares it).
#   rollback: modprobe -r st_nci_i2c st_nci

# N2.4  NCI power-up (risk: low-medium; first NCI traffic. The reset pulse on gph1-5
#       resets the whole ST54J, eSE included, as stock does every time NFC turns on.
#       CORE_RESET (reset config), CORE_INIT; no HCI, no NFCEE, no firmware)
#   second terminal first:  tools/phone-ssh dmesg -w
tools/phone-ssh 'nfctool -d nfc0 -1; echo rc=$?; nfctool -l;
  cat /sys/kernel/debug/clk/pmu-clkout1/clk_enable_count; grep pmu-clkout1 /sys/kernel/debug/clk/clk_summary;
  grep -hE "\((gph1-[45])\)" /sys/kernel/debug/pinctrl/*11840000*/pins'
#   pass: rc=0; nfctool lists nfc0 powered, with protocols (Felica MIFARE Jewel ISO-DEP NFC-DEP
#   ISO15693); enable count 1, hardware enable Y; no NCI error in dmesg; gph1-4 unchanged.
#   stop: rc != 0 or "Connection timed out" (NCI init timeout). Run N2.5, record ABL's pad
#   state from N2.2 next to the result: that decides the bit 0 polarity for the next build.
# N2.5  power-down (risk: low)
tools/phone-ssh 'nfctool -d nfc0 -0; nfctool -l; cat /sys/kernel/debug/clk/pmu-clkout1/clk_enable_count'
#   pass: nfc0 not powered; enable count 0 (pad off again).
# N2.6  rfkill, as the quick-settings tile uses it (risk: low)
tools/phone-ssh 'rfkill block nfc; nfctool -d nfc0 -1; echo rc=$?; rfkill unblock nfc; rfkill -rn -o TYPE,SOFT | grep ^nfc'
#   pass: power-up refused while blocked (rc != 0); "nfc unblocked" at the end.
#   rollback for N2.3-N2.6: nfctool -d nfc0 -0; modprobe -r st_nci_i2c st_nci
```

#### N2 results (2026-10-12, `7.3.0-rc6-omamobile-push1-00306-g60d3ca176c80`)

int with `omamobile-nfc` `a6ed1ea8b`, overlays including `nfc-test`,
device-cheetah 0.1.23, neard 0.20.

- **N2.1 pass:** blacklist count 1, no NFC file in `/etc/modprobe.d`,
  `nfctool` present. (neard built on the phone once its makedepends,
  autoconf-archive among them, were installed.)
- **N2.2 pass:** no st_nci module; `pmu-clkout0/1` at 24576000, enable
  count 0, hardware enable N: **ABL leaves bit 0 clear on both pads.**
  gph0-5 input low (PUD 0x1), gph1-4 output low, gph1-5 output high.
- **N2.3 pass:** nfc0 registered, rfkill `nfc unblocked unblocked`,
  clkout1 count 0. gph1-5's power-down settings changed to the pin group's
  (CON_PDN 0x2 to 0x3, PUD_PDN 0x1 to 0x0); live state unchanged.
- **N2.4 fail:** `nfctool -d nfc0 -1` "Connection timed out". Three 5 s
  `__nci_request` timeouts, then "SE discovery failed". No I2C errors
  logged, gph1-4/5 unchanged. **N2.5 pass** (powered: no).

Why:
1. **Wrong link protocol.** Upstream st-nci frames everything in NDLC (a
   PCB byte, acknowledges). The ST54J speaks plain NCI over I2C: Google's
   st21nfc.c reads a 3-byte NCI header (byte 2 = payload length), then the
   payload, and skips 0x7e idle bytes (`st21nfc_dev_read()`). The chip got
   an unknown leading byte and never answered. The three timeouts were:
   st-nci's proprietary SET_NFC_MODE in `ops->init` (before CORE_RESET
   was even sent), the SET_NFC_MODE in `ndlc_close()` during the error
   path, and NFCEE_DISCOVER.
2. **"SE discovery failed" is a core bug:** `nfc_dev_up()` ran
   `discover_se()` even after `dev_up()` failed, and the NCI core sends
   NFCEE_DISCOVER before calling the driver's hook. So `829e25aed`'s early
   return never mattered.
3. **The clock was enabled during the attempt** (count 1 between
   `nfctool -1` and the error path's close; the regmap write returned 0,
   or power-up would have failed with that error instead of a timeout).
   Whether the pad runs with bit 0 set is still unproven.
4. **Two latent st-nci bugs:** `hard_fault` was never cleared, so after one
   failure every later power-up failed until the module was reloaded. And
   the interrupt was enabled while the link was still marked unpowered, so
   a CORE_RESET_NTF right after reset made the IRQ thread disable the
   interrupt without reading the frame.

Not needed (question 3): gph0-5 (power-idle) is an output of the chip,
which stock only watches as an interrupt for power statistics. CLKREQ
(gpp25-3) is unused on stock (no `st,clk_pinctrl`). Reset timing: stock's
HAL resets with a double pulse (20 ms low, 10 ms high, 20 ms low, high) to
leave quick boot mode. The plain NCI mode does the same, then waits 80 ms.

#### Fix: `omamobile-nfc` head `3502821fa` (on `a6ed1ea8b`)

- `d86b6cfae` nfc core: no SE discovery after a failed `dev_up()`.
- `9e8575465` st-nci: plain NCI link for `st,st54j-i2c` (raw ndlc mode, I2C
  reader with idle-byte handling, double reset pulse, no SET_NFC_MODE);
  `hard_fault` cleared on open; powered before reset release; dev_dbg and
  hex dumps of every frame and I2C error.
- `ed80f106a` st-nci: with no SE described, the NCI device has no SE ops
  at all, so neither NFCEE_DISCOVER nor the HCI network set-up runs
  (replaces `829e25aed`'s early return).
- `3502821fa` clkout (bring-up only): writable parameter
  `clk_exynos_clkout.gs101_pad_en_active_low` (default 0: bit 0 set runs
  the pad), read at every enable/disable, and a pr_debug of `PAD_CTRL`
  after each change. Both polarities can be tried in one boot.

checkpatch clean (no Signed-off-by, by rule); W=1 clean for st-nci,
clkout and `net/nfc/core.c`.

#### Runbook N2.4b: plain NCI power-up, both clock polarities

```sh
# laptop: the human merges omamobile-nfc (3502821fa) into omamobile-int
export KERNEL_DIR=~/android/mainline/wt-int KERNEL_OUT=~/android/mainline/out-int
bin/omamobile kernel && bin/omamobile modules
O=$KERNEL_OUT D=$O/arch/arm64/boot/dts/exynos/google/gs201-cheetah.dtb; rm -f "$D.default"
ov <the overlays the phone boots now, nfc-test included> && bin/omamobile push    # reboots
#   pass: as N2.2 (boot, USB/SSH, UFS, touch, Wi-Fi, sound; st_nci not loaded).

# N2.4b-0  bind with dynamic debug on (risk: low, as N2.3)
#   second terminal first:  tools/phone-ssh dmesg -w
tools/phone-ssh 'modprobe nci dyndbg=+p; modprobe st_nci dyndbg=+p; modprobe st_nci_i2c dyndbg=+p;
  echo "file clk-exynos-clkout.c +p" > /sys/kernel/debug/dynamic_debug/control;
  cat /sys/module/clk_exynos_clkout/parameters/gs101_pad_en_active_low; ls /sys/class/nfc;
  grep st_nci /proc/interrupts'
#   pass: N (default polarity), nfc0, the st_nci IRQ line with its count.

# N2.4b-1  power-up, default polarity (bit 0 set = run) (risk: low-medium, as N2.4;
#          no SE ops now, so only CORE_RESET/CORE_INIT go out)
tools/phone-ssh 'nfctool -d nfc0 -1; echo rc=$?; nfctool -l; grep st_nci /proc/interrupts;
  dmesg | grep -E "st_nci|pmu-clkout|nci" | tail -40'
#   expect in dmesg: "pmu-clkout1: enable, PAD_CTRL 0x3e84 = 0x00000001", "reset released
#   (double pulse)", then tx 20 00 01 01 (CORE_RESET_CMD), rx 40 00 01 00 (RSP) and a
#   60 00 ... CORE_RESET_NTF, tx 20 01 02 00 00 (CORE_INIT), rx 40 01 ...
#   pass: rc=0, nfc0 powered, IRQ count went up. Skip to N2.5 (nfctool -0), then N2.6.
#   read the failure from the log:
#     no rx, IRQ count unchanged: the chip is silent (clock or reset): N2.4b-2;
#     rx of only "read: idle": the link works, the chip is not ready: record, stop;
#     "write of N bytes failed": I2C NACK: record the error, stop;
#     rx frames but a timeout: the dump says which command; record, stop.

# N2.4b-2  only if N2.4b-1 failed with no rx: the other polarity (risk: low-medium)
tools/phone-ssh 'nfctool -d nfc0 -0; cat /sys/kernel/debug/clk/pmu-clkout1/clk_enable_count;
  echo 1 > /sys/module/clk_exynos_clkout/parameters/gs101_pad_en_active_low;
  nfctool -d nfc0 -1; echo rc=$?; nfctool -l; grep st_nci /proc/interrupts;
  dmesg | grep -E "st_nci|pmu-clkout|nci" | tail -40'
#   flip the parameter only with enable count 0. Expect "PAD_CTRL 0x3e84 = 0x00000000" on
#   enable. pass as N2.4b-1. Record which polarity passed; that fixes the driver's default.
#   stop: both fail with no rx. Leave NFC off, keep the logs (no identifiers in them).
# rollback: nfctool -d nfc0 -0; echo 0 > /sys/module/clk_exynos_clkout/parameters/gs101_pad_en_active_low;
#   modprobe -r st_nci_i2c st_nci; images without nfc-test.
```

#### Runbook N3: read a tag (needs N2.4 or N2.4b passed)

Any NFC tag or transit card, held to the middle of the back. Don't copy a
tag's UID into this plan; record its length and type.

```sh
# N3.1  poll from the kernel API (risk: low; RF reader mode only)
tools/phone-ssh 'nfctool -d nfc0 -1 && timeout 30 nfctool -d nfc0 -p; nfctool -l'
#   pass: "Targets found for nfc0" with a tag (tag0) and its protocol in nfctool -l.
#   stop: nothing within 30 s with the tag in place: power down, record, retry once.
tools/phone-ssh 'nfctool -d nfc0 -0'

# N3.2  the UID through neard (risk: low; with upstream main.conf neard powers nfc0 and
#       keeps polling while it runs)
tools/phone-ssh 'systemctl start neard; sleep 2; busctl tree org.neard'
#   hold the tag, then:
tools/phone-ssh 'busctl tree org.neard; T=$(busctl tree --list org.neard | grep -m1 "/tag"); echo $T;
  busctl get-property org.neard $T org.neard.Tag Type Protocol Uid'
#   pass: a /org/neard/nfc0/tagN object; Type and Protocol set; Uid a byte array
#   (4, 7 or 10 bytes for ISO 14443-A).
tools/phone-ssh 'systemctl stop neard; nfctool -d nfc0 -0'
#   rollback: systemctl stop neard; nfctool -d nfc0 -0; modprobe -r st_nci_i2c st_nci
```

After N3 passes: drop the blacklist, move `nfc@8` and the HSI1 pin
controller to `okay` in the base DT, and decide whether neard runs by default
(the quick-settings tile works either way through rfkill).

---

## 4. Cameras: Google ISP, CSIS, four sensors

**Superseded by [CAMERA-PLAN.md](CAMERA-PLAN.md)** (staged plan, corrections to 4.1 and 4.6).

### 4.1 Hardware

| Camera | Stock node | Sensor | I2C bus, address | Reset | CSIS link / PHY |
|---|---|---|---|---|---|
| Main | `sensor-nagual` | Samsung GN1 (50 MP; named in the HAL: `vendor.camera.debug.enable_gn1_*`) | `hsi2c_1`, `0x3d` | gpp2-2 | C-PHY |
| Front | `sensor-dokkaebi` | Samsung 3J1 (to confirm by chip ID) | `hsi2c_2`, `0x10` | gpp4-2 | D-PHY |
| Ultrawide | `sensor-sandworm` | Sony IMX386 (to confirm by chip ID at `0x0016`) | `hsi2c_3`, `0x1a` | gpp6-3 | D-PHY, 4 lanes |
| Tele | `sensor-kraken` | Samsung GM5 (to confirm by chip ID) | `hsi2c_4`, `0x2d` | gpp6-2 | C-PHY |

Evidence: `R/live.dts:18745-18850` (all `google,lwis-i2c-device`, 16-bit
register addresses); `A/` → `lib64/liblyric_hwl.so` strings.

The C0 stage reads the chip ID registers to confirm the sensor names: Sony
`0x0016`, Samsung `0x0000`.

- **CSIS:** `lwis_csi@1a440000`.
  - Links 0-7 at `0x1a440000 + n*0x10000`, EBUF `0x1a4c0000`, the CSIS DMA
    block `0x1a4d0000`, DC-PHY `0x1a4f0000`, `csis-sysreg` `0x1a420000`.
  - Link, DMA and EBUF IRQs are GIC SPI 189-204, 217-219 and 234-236.
  - It sits behind a SysMMU in power domain `pd-csis`
    (`R/live.dts:10972-10994`, `7343-7360`).
- **DC-PHYs:** `dcphy_m0s4s4s4s4s4_csi0@1a4f1300`, ... with
  `samsung,mipi-phy-m0s4s4s4s4s4` (`R/live.dts:10864-10890`).
- **The rest of the ISP:**
  - PDP, IPP, G3AA, GTNR, ITP, MCSC, GDC and VOTF are LWIS ioreg devices
    (`R/live.dts:10996-11189`) programmed entirely by the proprietary HAL.
  - LWIS is a register pass-through (`G/google-modules/lwis/`); the kernel
    knows nothing about the pipeline.
- **Power:**
  - S2MPG13 LDO12S (camera I/O, 1.8 V);
  - the SLG51002 camera PMIC at `hsi2c_8` `0x75`
    (`compatible = "dlg,slg51002"`, `R/live.dts:7937-7945`). Mainline has
    only the different `slg51000`;
  - `CIS_CLK0..7` from CMU_TOP to the sensor MCLK pads.
- **Flash:** the LM3644TT torch already works (HAPTICS-TORCH-PLAN.md). Its
  bus `hsi2c_15` also holds a camera EEPROM at `0x50`.

### 4.2 Linux driver state

- **Mainline:**
  - no gs101/gs201 CSIS driver. `exynos4-is` and `imx-mipi-csis` are older
    CSIS versions;
  - none of the four sensors has a driver (`L/drivers/media/i2c` has
    `s5k3m5`, `s5kjn1`, `imx3xx` others, `ak7375`);
  - no SLG51002 regulator driver.
- **Google downstream:** LWIS and the ISP are useless without the HAL.
- **The HAL can't run here:**
  - `com.google.pixel.camera.hal.apex` needs Google's gralloc, the Mali
    vendor driver (we run Panthor), the EdgeTPU and GXP for its pipeline,
    and the ISP firmware behaviour.
  - It is not a chroot job like `cbd` or `lhd`.
- **What Google's GPL tree does give:**
  - `GS/drivers/phy/samsung/phy-exynos-mipi.c` (1068 lines) programs the
    DC-PHY isolation (PMU) and resets, and has **D-PHY** settings for this
    PHY generation (`__set_phy_cfg_0504_000{0,1,2}_dcphy`,
    `phy-exynos-mipi.c:516-770`).
  - Its C-PHY branches are `/* TODO: Configure C-PHY mode */`
    (`:594,680,765`). The C-PHY values for main and tele are written by the
    HAL through LWIS and exist only in `liblyric_hwl.so`.
  - The SLG51002 regulator and MFD drivers.
  - The camera power sequences in the stock DT (LWIS `power-up-seqs`).
- **Path:** raw Bayer capture, no ISP.
  - **Kernel:**
    - a V4L2 driver for CSIS link → CSIS DMA (bypassing the EBUF and the
      ISP), giving RAW10 in memory;
    - the DC-PHY as a generic PHY;
    - one subdev driver per sensor (register tables from the sensors'
      public/standard CCS-style registers where possible, mode tables from
      the HAL only if no other source exists; see risks);
    - the SLG51002 regulator driver;
    - a VCM driver (AK737x: mainline `ak7375` is close).
  - **Userspace:**
    - libcamera's *simple* pipeline handler with the **software ISP**
      (debayer, AWB, AGC on the GPU, upstream since libcamera 0.6/0.7);
    - one line in its supported-device table, plus sensor helpers and
      tuning files;
    - PipeWire's libcamera plugin then serves the browser and video calls.
  - **Practical details to expect:**
    - Mesa refuses dma-bufs whose pitch isn't 64-byte aligned, so pad the
      lines;
    - use the system dma-buf heap, not CMA, for the ISP's output buffers
      (CMA is small and needed below 4 GiB for capture);
    - cached buffers for the statistics pass.

### 4.3 Simpler paths, checked

- **USB webcam (UVC) through USB-C host mode.**
  - `CONFIG_USB_VIDEO_CLASS=m` is already built.
  - It needs USB-C plan B4b (dwc3 behind the role switch, `dr_mode =
    "otg"`) and the external VBUS boost (USB-C-PLAN.md: `ext-otg-only`,
    MAX77759 GPIO5).
  - Value is small (a webcam dangling off a phone), but it is a free test
    of the libcamera/PipeWire path.
- **The phone as a webcam (UVC gadget).** It needs the cameras first. Not a
  shortcut.
- **v4l2loopback** helps apps that want a `/dev/video` node (Waydroid,
  older apps) once libcamera works. It needs a fix for 7.3's file-based
  `v4l2_fh`.
- **libcamera without a kernel CSIS driver:** not possible. libcamera needs
  a V4L2 capture node.

### 4.4 Minimum path to "works"

"Works" = `cam -c 1 --capture=1 --file` writes a frame from the
ultrawide, then a preview in a camera app through libcamera.

| Stage | What | Needs |
|---|---|---|
| C0 | Read-only: pins, buses, EEPROM, libcamera build options (runbook below) | nothing |
| C1 | SLG51002 + LDO12S + CIS_CLK + sensor reset; read the ultrawide's chip ID | S2MPG13 regulators; CMU_TOP CIS_CLK gates |
| C2 | `pd-csis` on (power-domain driver), CSIS S2MPU CTRL0 = 0, DC-PHY out of isolation; CSIS test pattern into memory | PD driver (SUSPEND/POWER plans); ACPM CAM and INT DVFS ≥ 400 MHz |
| C3 | Ultrawide (D-PHY, GPL settings) streaming RAW10 via V4L2 | C2 + IMX386 driver |
| C4 | libcamera simple + SoftISP, PipeWire, camera app | C3 |
| C5 | Front (D-PHY), then main and tele (C-PHY) | C4; the C-PHY question below |

### 4.5 Effort, value, risks

- **Effort: large.**
  - CSIS + PHY driver: 2-3 weeks.
  - Per sensor: 3-7 days.
  - SLG51002: 3-5 days.
  - DVFS and PD: shared with other plans.
  - Total: 6-10 weeks to all four cameras.
- **Value: medium-high** for a phone (QR codes, video calls, photos). Below
  the modem and GNSS.
- **Risks:**
  - **Proprietary register data.**
    - C-PHY settings and sensor mode tables that exist only in
      `liblyric_hwl.so` can't be committed. If needed, generate them on the
      user's machine from their own image, as `tools/extract-vendor-firmware`
      does for firmware.
    - Prefer sensor-datasheet or CCS-standard registers wherever possible.
  - **Bus hangs.**
    - Touching CSIS or PHY registers with `pd-csis` off or the PHY in reset
      hangs the bus.
    - The PMU isolation bit for the DC-PHY is set through the SMC regmap
      only.
    - Every C stage needs the watchdog capture tooling.
  - **The S2MPU rule.** After a power-domain cycle the CSIS S2MPU blocks
    DMA. Write only CTRL0, never read other S2MPU registers.
  - **Shared pins.** gpp8 carries the tele sensor's bus and the torch's
    HWEN (gpp8-2). The pinctrl states must not overlap.
- **Dependencies:** ACPM DVFS (CAM, INT), S2MPG13 regulators, PD driver.
  None of the other three areas.

### 4.6 Runbook C0 (read-only; current int kernel)

```sh
# C0.1  sensor reset lines and MCLK pads as ABL left them
tools/phone-ssh 'grep -hE "\((gpp2-2|gpp4-2|gpp6-[23]|gpp3-0|gpp5-0|gpp7-0|gpp9-0|gpp8-[012])\)" /sys/kernel/debug/pinctrl/*10840000*/pins'
#   expect: resets low or input (sensors off), MCLK pads not in function 2.
# C0.2  the camera EEPROM on the torch bus (bus already up; one 256-byte read, no writes)
tools/phone-ssh 'for d in /sys/bus/i2c/devices/i2c-*; do readlink -f $d/of_node | grep -q 10da0000 && basename $d; done'
#   prints i2c-N for 10da0000.i2c; then, with that N:
tools/phone-ssh 'i2cdump -y -r 0x00-0xff N 0x50 b'
#   keep the dump: module vendor/ID bytes tell which camera module the EEPROM belongs to.
# C0.3  userspace readiness (no hardware)
tools/phone-ssh 'pacman -Qi libcamera 2>/dev/null | head -3; pacman -Si libcamera | grep -E "^Version"; ls /dev/dma_heap/ 2>&1; cam -l 2>&1 | head'
#   expect: no cameras; record the libcamera version and whether /dev/dma_heap/system exists
#   (CONFIG_DMABUF_HEAPS_SYSTEM=m: modprobe system_heap if not).
```

---

## 5. Shared vendor-chroot runner

`fingerprint/omamobile-fp-chroot` (286 lines) and its preload shim (594
lines) already do the hard parts:
- a private mount and PID namespace on a tmpfs;
- the image bound read-only;
- a property area filled from `build.prop` plus a small override file;
- a private binderfs;
- an LD_PRELOAD shim for liblog, properties, SELinux and wakelocks.

Make it one runner with **profiles** instead of three copies:

| Profile | Binaries | binderfs | Device nodes bound in | Writable state | Extra |
|---|---|---|---|---|---|
| `fp` | Goodix HAL, KeyMint, Gatekeeper, storageproxyd, apploader, servicemanagers | yes | `trusty-ipc-dev0`, RPMB `sg`, touch event node | `/var/lib/omamobile/fp` | as designed |
| `gnss` | `lhd`, `gpsd` (Broadcom) | yes (gpsd links binder; lookups must fail fast) | `ttyBCM`, `bbd_control`, `bbd_patch`, `bbd_pwrstat`, the `nstandby` sysfs file | `/var/lib/omamobile/gnss` → `/data/vendor/gps` | NMEA FIFO bound out to the host bridge |
| `modem` | `cbd`, `rfsd` | no | `umts_boot0`, `umts_rfs0` (only these) | RAM copies of efs, efs_backup, modem_userdata, persist/modem; nothing persistent until a design says so | firmware partition bound read-only as a **file**; NV checksums verified before start |

**Common rules:**
- No network namespace sharing unless the profile needs it: `cbd` and
  `rfsd` don't. Data uses host-side `rmnet`.
- Drop all capabilities and set `no_new_privs`.
- Real block devices are never visible inside a chroot.
- Each profile's start script writes a hang marker (the `omamobile-wifi`
  pattern), so a hang skips that subsystem on the next boot.

The extract tool becomes `tools/extract-vendor-chroot --profile NAME` (from
`extract-fingerprint-vendor`): the same DT_NEEDED closure, one file list per
profile, never shipped, always built from the user's own factory image.

---

## 6. Kernel work done (offline)

Branch `omamobile-hsi1` in `~/android/mainline/wt-hsi1`, off `omamobile` @
`7b0f8b5d1`:

| Commit | What |
|---|---|
| `f7a9852f1` arm64: dts: exynos: google: gs201: add HSI1 pinctrl | `pinctrl_hsi1: pinctrl@11840000` (GIC SPI 387, alias `pinctrl6`, empty `pclk` as gs101 does until a CMU_HSI1 driver exists), banks `gph0`/`gph1` in `gs201-pinctrl.dtsi`. **`status = "disabled"`** |

Notes:
- The driver already has the bank table: gs201 uses `gs101_pin_hsi1`, 6 +
  7 pins, which matches Google's `pinctrl-gs201.c:140-144`.
- HSI1 has no power domain in the stock DT (no `pd-hsi1` node among the
  `pd-*` nodes), so the block is not power-gated under us.
- omamobile repo: `device/cheetah/overlays/hsi1-pinctrl-test.dtso` turns it
  on for M0.4/N0.3.
- **Merge:** into `omamobile-int`, expect trivial conflicts in the
  `aliases` block (`pinctrl4`/`pinctrl7` from the PERIC0 and HSI2 branches)
  and at the end of `gs201-pinctrl.dtsi`. Keep all entries.
- Build: `KERNEL_DIR=~/android/mainline/wt-hsi1 KERNEL_OUT=~/android/mainline/out-hsi1 bin/omamobile kernel`
  (`logs/kernel-hsi1.log`). The result is in section 6.1.

### 6.1 Build result

- `bin/omamobile kernel` exits 0, release `7.3.0-rc6-omamobile-push1-00059-gf7a9852f1afd`
  (`logs/kernel-hsi1.log`, Image, DTBs and modules in `out-hsi1`). There are
  no dtc warnings for gs201.
- `dt-validate` (dtschema 2026.9, schema built from this tree) of the
  default `gs201-cheetah.dtb`, and of it with `hsi1-pinctrl-test` applied
  (`fdtoverlay`, node `okay`), reports only the existing `soc_id` and
  simplefb `post-init-providers` items.
- No images were packed; the main session builds images from int after the
  merge.

---

## 7. Open questions

1. **ABL rail state.** Are S2MPG12 LDO16M/LDO18M (modem) on, and
   S2MPG13 LDO9S-11S (GNSS) and LDO12S (camera) off, after ABL hands over
   to Linux? Stock marks the GNSS rails always-on, which says nothing about
   ABL. The S2MPG13 driver's read-only first stage answers this.
2. **HSI1 SysMMU confinement.** Can `sysmmu_hsi1` confine the modem (it is
   alone on HSI1, VID 0)? This needs a careful staged test after M4.
3. **`lhd` without `bbd_control`.** Does `lhd` need anything back from
   `/dev/bbd_control` beyond its own strings? This decides whether an
   upstream `drivers/gnss/` driver (one `/dev/gnssN`) is enough.
4. **Broadcom `gpsd` without the HAL.** Does it produce NMEA on
   `nmea_out` with no HAL client, or does it need a start request on
   `glgpsctrl`?
5. **ST54J and `st-nci`.** Does the ST54J's NFC core accept `st-nci`'s
   init sequence unchanged? Is the reference clock needed before the first
   NCI exchange, or only for RF?
6. **SIT documentation.** Write our SIT client against observed behaviour
   of the stock libraries, or start from AT (`umts_router`) for
   registration only and SIT for data? This decides whether ModemManager's
   generic plugin can be a stepping stone.
7. **Calls without IMS.** Does the user's carrier still allow CS fallback?
   If not, calls need IMS (M5) as well as the AoC voice path.
8. **The camera EEPROM at `hsi2c_15` `0x50`.** Which camera module does it
   belong to?
9. **C-PHY settings.** Accept generating them on the user's machine from
   `liblyric_hwl.so`, or limit Omarchy Mobile to the two D-PHY cameras until
   another source appears?
