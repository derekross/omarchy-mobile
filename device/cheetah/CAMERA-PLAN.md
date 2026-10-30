<!-- SPDX-License-Identifier: MIT -->
# Camera plan (cheetah / gs201): raw capture first, then libcamera

Status (2026-10-14, night): **all four cameras stream real frames.**
The C-PHY main and telephoto cameras needed one fix: the CSIS write DMA
loses lines that arrive faster than about 400 MB/s, so the sensor driver
now lengthens their lines (`samsung,max-line-throughput = <360>`, section
CAM-M.5l). Front: F.5-F.7 passed. Telephoto: T.1, T.2, T.4, T.5 passed;
its SEM1215SA lens NACKed in T.3 and holds its I2C bus when driven, so it
isn't driven: the telephoto is fixed-focus at its resting position, sharp on
distant subjects (outdoors, 2026-10-26) and soft up close (docs/DEVICES.md).
Kernel: int `9626f17f7` = `7.3.0-rc6-omamobile-push1-00511-g9626f17f7825`
(the same code as 00504),
overlays as `device.conf` (now with `camera-tele`). Earlier status (2026-10-13, evening): **the ultrawide works end to end through
libcamera (CAM5). The other three cameras are built offline and wait for
the phone: main (Samsung S5KGN1, C-PHY, link 1; runbook CAM-M), front
(Samsung S5K3J1, D-PHY, link 0; CAM7) and telephoto (Samsung S5KGM5,
C-PHY, link 4, SEM1215SA focus; CAM-T). Question 11 is done: every DC-PHY
setting, D-PHY included, now comes from the per-phone data file
`gs201-dcphy.bin`, so the ultrawide needs that file before it runs a
kernel from this branch: runbook P comes first.** On the phone (2026-10-13): P passed (the ultrawide unchanged with the
PHY file), CAM-M passed M.1-M.4 (the S5KGN1 answers, its C-PHY link
counts 30 fps), M.5's first DMA in the 2032x1536 mode stopped with
`LASTADDR`, and so did 2016x1136 (M.5b, either start value); next
CAM-M.5c (error bits: only `ERR_WRONG_CONFIG`; LRTE no effect; the
overrun's last packet is a VC 1 RAW10 line), CAM-M.5d (VC 1 is the
phase data, 2016 x ~284, and lands cleanly alone; VC 0 still overruns
with VC 1 on its own channel), CAM-M.5e (VC 0 overran even at
twice the height), CAM-M.5f (8192
lines and 4080x3072 overrun too: the WDMA never gets VC 0's frame
starts), CAM-M.5g (the WDMA gets VC 0's first frame
start and only five line ends: no line framing; every VC 0 DMA so far
ran with the sensor's colour bars), CAM-M.5h (a real image
fails the same way), CAM-M.5i (VC 1 has line
ends, VC 0 doesn't; dual/single overflow on the link, octa is clean),
CAM-M.5j-1 (CAM 664 MHz: no change). Paused there; next options under
"Where we stopped" (CAM-M.5j-1 result). libcamera 0.7.2-4.6 is
installed on the phone. CAM7: F.1-F.3 passed (the S5K3J1 answers, link 0's graph is
up); F.4 next. Kernel branch
`omamobile-camera` head `d73ed198d` (all in int `7e9131775`);
libcamera 0.7.2-4.6 (patches 0013-0014: the front and
telephoto sensors, a near-size mode rule) built and checked offline, the
phone still runs 4.4. Ultrawide quality: CAM5.3, Snapshot CAM5.4, what to
expect and what needs captures: 7.Q. Order on the phone: section 7.R.
Earlier status: **K, CAM0 (partly), CAM1, CAM2 and CAM3a passed on the
phone (the ultrawide answers as a Sony IMX386); CAM3b.3 showed the sensor
streaming but nothing on links 0 or 1. The ultrawide is on CSIS link 2
with DC-PHY slaves 2+3 as one four-lane receiver (section 4.4); the link 2
path is built offline (`omamobile-camera` head `3390774a8`, overlay
`camera-stream-link2`) and CAM3b.5 is the next phone test.** Kernel branch `omamobile-camera` in `~/android/mainline/wt-camera`
(output `~/android/mainline/out-camera`); `omamobile-int` 606b84c7a already
has its first part (up to `6cb2be364`). On top, not merged yet (head
`35295a9ab`): CIS clock rounding, the DC-PHY receiver, the CSIS link + CSIS
WDMA V4L2 driver, a Sony IMX386 sensor driver and their DT, all disabled or
blacklisted. The sensor's manufacturer settings come from
`tools/extract-camera-data`, run on the user's machine; libcamera 0.7.2 with
our simple-pipeline entry is in `packages/libcamera` (not built yet). Two
facts are still unknown and are what CAM3b/CAM4 find out on the phone:
which four-lane CSIS link the ultrawide is wired to, and the WDMA input
value for a direct link-to-WDMA route (section 4.3). Nothing streams yet.

This plan replaces section 4 of `RADIOS-CAMERA-PLAN.md`, which was the
starting survey. It corrects two of its facts (section 1.7).

**Goal.** In order:

1. a raw Bayer frame from one camera, captured to a file on the phone;
2. a photo from that camera in a Linux app (libcamera `cam`, then a
   PipeWire camera app);
3. video (a live preview and a recording);
4. the other three cameras, then focus.

Claims are marked **[V]** (checked, with a source) or **[I]** (inferred, to
be checked on the phone), as CONTRIBUTING.md asks.

Path abbreviations (as in the other plans):

- `L/` = our kernel, `omamobile-int` (`~/android/mainline/wt-int`, release 7.3.0-rc6)
- `G/` = `~/android/omamobile/out-kernel/google/gs-6.1/private` (Google's GPL gs201 kernel)
- `GS/` = `G/google-modules/soc/gs`
- `GD/` = `G/devices/google` (Google's GPL device trees: `gs201/dts/gs201-isp.dtsi`, `pantah/dts/gs201-cheetah-camera.dtsi`, `pantah/dts/gs201-pantah-camera-pmic.dtsi`)
- `LW/` = `G/google-modules/lwis` (Google's GPL LWIS driver)
- `R/` = `~/android/reference/cheetah-stock-cp2a-root` (stock live DT, dmesg; private)
- `A/` = the camera HAL APEX from the user's own image, `com.google.pixel.camera.hal.apex` (private; never committed)

---

## 0. Summary and recommendation

- **Recommended path: (a), raw capture without Google's ISP.** A new V4L2
  driver for the CSIS receiver and its "CSIS WDMA" (raw Bayer straight to
  memory), a generic PHY driver for the receive side of the Samsung DC-PHY,
  one sensor driver per camera, and the camera PMIC. libcamera's *simple*
  pipeline handler with its software ISP does debayer, white balance and
  exposure. Stock itself uses this exact route (link → CSIS WDMA) for RAW
  output, so the hardware supports it without PDP, G3AA, ITP or MCSC
  (section 1.3).
- **First camera: the ultrawide** (Sony sensor, `sensor-sandworm`): standard
  Bayer, 8-bit register values (Sony layout, close to the mainline
  `imx258`/`imx319`/`imx355` drivers), believed D-PHY [I], and its EEPROM
  needs only the 1.8 V I/O rail (section 1.2).
- **What makes it hard:** the CSIS receiver and its DMA have no Linux driver
  anywhere and no GPL register description beyond interrupt bits and DT
  offsets. The rest of the register meaning (formats, DMA control bits, link
  routing) must be learned from the stock HAL with REA and written down as
  facts in our own words (section 4). Sensor mode tables come from the HAL
  too and are never committed: an extract tool generates them on the
  user's machine (section 5.3).
- **Not recommended: (b)**, porting LWIS and running the stock HAL in a
  chroot. It needs Google's gralloc, Mali kbase OpenCL (we run Panthor), the
  EdgeTPU and GXP, BTS, SLC, a SysMMU v8 driver and an Android camera client,
  and it would still need a bridge to PipeWire. LWIS is a userspace register
  pass-through that upstream will never take (section 3).
- **(c), mainline:** nothing for gs101/gs201 cameras in 7.3-rc6. The closest
  relatives are `imx-mipi-csis` (an older version of the same Samsung
  receiver: the link registers match) and `phy-rockchip-samsung-dcphy` (the
  transmit side of the same DC-PHY family). Both are useful references; no
  code can be reused as is (section 3).
- **Timeline:** about 8-12 weeks of focused work to a photo from the
  ultrawide in `cam`, about 2-3 more for video, and 4-6 months to all four
  cameras with focus (section 6). The C-PHY cameras (main and tele, if the
  survey is right) carry most of the schedule risk.

---

## 1. Hardware facts

### 1.1 The four cameras

| Camera | LWIS node | Sensor | I2C bus (base), addr | Reg width (addr/val) | Reset | MCLK (clock, pad, rate) |
|---|---|---|---|---|---|---|
| Main | `sensor-nagual` | Samsung GN1, 50 MP [I] | `hsi2c_1` (`0x10900000`), `0x3d` | 16/16 | gpp2-2 | `CIS_CLK3`, gpp9-0 (`sensor_mclk4`), 26 MHz |
| Front | `sensor-dokkaebi` | Samsung S5K3J1 [V: the HAL's driver for chip ID 0x30a1, section 4.5; CAM7 reads it] | `hsi2c_2` (`0x10910000`), `0x10` | 16/16 | gpp4-2 | `CIS_CLK1`, gpp5-0 (`sensor_mclk2`), 24 MHz |
| Ultrawide | `sensor-sandworm` | Sony IMX386 [V: model ID 0x0386 read on the phone, CAM3a] | `hsi2c_3` (`0x10920000`), `0x1a` | 16/8 | gpp6-3 | `CIS_CLK0`, gpp3-0 (`sensor_mclk1`), 24 MHz |
| Tele | `sensor-kraken` | Samsung S5KGM5 [V: the HAL's driver for chip ID 0x08d5, 4.5; CAM-T reads it] | `hsi2c_4` (`0x10930000`), `0x2d` | 16/16 | gpp6-2 | `CIS_CLK2`, gpp7-0 (`sensor_mclk3`), 24 MHz |

Evidence **[V]**: `GD/pantah/dts/gs201-cheetah-camera.dtsi` (nodes "REAR
CAMERA NAGUAL", "FRONT CAMERA DOKKAEBI", "REAR ULTRA WIDE CAMERA SANDWORM",
"REAR Folded Tele Camera KRAKEN"), the same in `R/live.dts:18745-18863`.
Reset lines are active high in LWIS terms (driven 1 to run). MCLK pads have
two pinctrl states: function 1 with pull-down (`mclk_off`) and function 2
(`mclk_on`).

Sensor part names come from the HAL (`vendor.camera.debug.enable_gn1_*`
properties in `A/lib64/liblyric_hwl.so`) and from public teardowns; only GN1
has a string in the HAL. **The CAM3a chip-ID reads settle them** (Sony model
ID at `0x0016`, Samsung at `0x0000`). The value width already splits them:
the ultrawide answers with 8-bit values (Sony style), the other three with
16-bit (Samsung style).

Each bus also carries the module's other parts **[V]** (`R/live.dts:18865-19100`):

| Bus | Parts besides the sensor |
|---|---|
| `hsi2c_1` | `eeprom-gargoyle`/`ois-gargoyle` at `0x24` (32-bit values: an OIS controller holding the module EEPROM), AF actuator `act-slenderman` at `0x0c`, the laser AF `stmvl53l1` at `0x29` |
| `hsi2c_2` | EEPROM `smaug-dokkaebi` at `0x51` (front is fixed focus: no actuator) |
| `hsi2c_3` | EEPROM `smaug-sandworm` at `0x50`, AF actuator `act-slenderman-sandworm` at `0x0f` (the ultrawide focuses, for macro) |
| `hsi2c_4` | `jotnar` at `0x34`: one controller for the tele's EEPROM, OIS and AF, a SEMCO SEM1215SA [V: the HAL's `sem121_family` drivers and `sem1215sa` properties] |

The flash (LM3644 on `hsi2c_15`, `0x63`) already works as the torch
(`HAPTICS-TORCH-PLAN.md`).

### 1.2 Power

Three layers **[V]** (`GD/pantah/dts/gs201-pantah-camera-pmic.dtsi:15-70`,
`R/live.dts:7938-8050, 14105-14113, 18709-18745`):

1. **S2MPG13 (sub-PMIC, over ACPM)**
   - `LDO12S` = `L12S_CAMIO`, 1.8 V: camera I/O for every sensor, EEPROM,
     actuator and the laser AF. Control register PM `0x37`, enable bit 7.
     Our `s2mps11.c` already describes it (`regulator_desc_s2mpg13_ldo_own(12, ...)`),
     but `pmic-2` in our DT doesn't list it yet.
   - S2MPG13 **GPIO 1** enables `PP3200_BB_CAM` (3.2 V fixed regulator,
     2 ms ramp); **GPIO 3** enables `PP1300_CAM` (1.3 V); **GPIO 0** is the
     SLG51002's chip select. The GPIOs live in the PMIC's GPIO bank (ACPM
     type `0x0c`): `GPIO_STATUS` `0x04`, `GPIO_n_SET` `0x05 + n`, with
     bit 5 = output level and bit 6 = output enable
     (`GS/include/linux/mfd/samsung/s2mpg13-register.h:380-395`,
     `GS/drivers/mfd/s2mpg1x-gpio-gs201.c`). We have no driver for this bank.
2. **SLG51002 camera PMIC** on `hsi2c_8` (`0x10970000`, the bus the
   haptics already use), address `0x75`. Eight LDOs and four GPIO switches.
   Its chip select (S2MPG13 GPIO 0) wakes it from a low-power reset; the
   datasheet time to ready is about 10 ms (Google's driver comment). Chip ID
   at `0x1105-0x1107`, 16-bit register addresses (`GS/drivers/mfd/slg51002-core.c:487-505, 570`).
   Mainline has only the different `slg51000`.

   | SLG output | Voltage | Supply | Used by |
   |---|---|---|---|
   | LDO1 | 2.85 V | PP3200_BB | main sensor |
   | LDO2 | 2.85 V | PP3200_BB | ultrawide sensor |
   | LDO3 | 2.25 V | PP3200_BB | tele sensor |
   | LDO4 | 2.9 V | PP3200_BB | main sensor, main AF, ultrawide AF |
   | LDO5 | 2.85 V | PP3200_BB | tele EEPROM/OIS/AF |
   | LDO6 | 1.1 V | PP1300 | ultrawide sensor |
   | LDO7 | 1.0 V | PP1300 | tele sensor |
   | LDO8 | 1.1 V | PP1300 | main and front sensors |
   | GPIO1 | switch | | main OIS/EEPROM, tele EEPROM/OIS/AF |
   | GPIO2 | switch | | main OIS |
   | GPIO3 | switch | | main sensor |
   | GPIO4 | switch | | front sensor |

3. **Power-up order** (stock LWIS sequences, `R/live.dts:18758-18860`):
   - Ultrawide: PP3200_BB, PP1300, LDO12S, LDO6, LDO2, 1 ms, MCLK on, 1 ms, reset high, 10 ms.
   - Front: PP3200_BB, PP1300, LDO12S, LDO8, GPIO4, 1 ms, MCLK on, 1 ms, reset high, 8 ms.
   - Tele: PP3200_BB, PP1300, LDO12S (0.3 ms), LDO7, LDO3, MCLK on, 1 ms, reset high, 10 ms.
   - Main: PP3200_BB, PP1300, LDO12S, LDO4 (1 ms), GPIO3, LDO8, LDO1 (2 ms), reset high (1 ms), MCLK on, 9 ms. The main sensor takes reset *before* MCLK.
   - Power-down is the reverse, reset low first (main: MCLK off first).
   - The two **EEPROMs `smaug-*` need only LDO12S** (1 ms). That makes them
     the first thing we can talk to: one rail, no MCLK, no reset (CAM2.3).

Stock writes "revision AA" trim values into the SLG51002 by entering a
software test mode (`slg51002-core.c:170-190, 265-300`). **Cheetah's part is
revision AB** [V]: stock's log reads `slg51002 8-0075: chip_id: 0xb13103`
(`R/dmesg.txt`), which Google's header names `REVISION_AB`, and the cheetah
DT has no `dlg,reg-init`, so stock writes nothing in test mode on this phone
(its probe only enters and leaves it). Our driver never enters test mode;
on an AA part it would register the LDOs only and say so.

### 1.3 The capture path: CSIS, its DMA and the PHYs

All **[V]** from `GD/gs201/dts/gs201-isp.dtsi` (= `R/live.dts:10858-10994`)
unless marked.

```
sensor ──MIPI──> DC-PHY slave n ──> CSIS link n ──┬──> CSIS WDMA ctx 0-3 ──> DRAM   (our path)
 (I2C ctl)       0x1a4f0000         0x1a44n000    ├──> EBUF ──> PDP/IPP ... (Google ISP, OTF)
                                                  └──> ZSL / STRP DMA ──> DRAM
                       all behind sysmmu_csis0/1 + s2mpu_csis0/1, in pd-csis
```

- **CSIS links 0-7** at `0x1a440000 + n * 0x10000` (4 KiB each). One GIC SPI
  per link, SPI 189-196, shared by four sources: INT0 (errors), INT1
  (frame start/end, line end, lost FS/FE, resolution mismatch), FS and FE
  (per virtual channel). Mask/source pairs at `0x10/0x14`, `0x18/0x1c`,
  `0x20/0x24`, `0x28/0x2c` (the `csi-event-info` nodes). The bit names are
  in `GS/include/dt-bindings/lwis/platform/gs201/csi.h` (4333 lines, GPL):
  INT0 has ERR_ID, CRC, ECC, WRONG_CONFIG, OVER, CRC_PH, MAL_CRC, then per
  lane invalid-code (12-15), SOT (16-19) and SOT-sync (20-23) errors.
- **The link is a newer version of the receiver in mainline's
  `imx-mipi-csis.c`.** Version at `0x00`, common control at `0x04`, the
  interrupt mask/source at `0x10/0x14`, and per-channel `ISP_CONFIG` at
  `0x40 + 0x10 * ch` and `ISP_RESOL` at `0x44 + 0x10 * ch` sit at the same
  offsets as in `L/drivers/media/platform/nxp/imx-mipi-csis.c:52-200`; the
  INT0 error bits line up too. The D-PHY control that lives inside the
  i.MX receiver is a separate DC-PHY block here. [V] for the offsets
  (gs201 from the DT and the HAL's register table, section 4.1); [I] that
  the bit fields inside them match.
- **CSIS DMA** at `0x1a4d0000` (64 KiB): three DMA families,
  each context with its interrupt mask/source at `+0x404/+0x408` of its
  4 KiB block:
  - ZSL WDMA contexts 0-2 at `0x1000-0x3000` (SPI 234-236);
  - STRP WDMA contexts 0-2 at `0x4000-0x6000` (SPI 217-219);
  - **CSIS WDMA contexts 0-3 at `0x7000-0xa000`** (SPI 197-200). Interrupt
    bits per context: line end, frame start and frame end for channels 0-3,
    FIFO full, last-data and last-address errors, abort done, overlap and
    frame drop per channel (`csi.h:3944-4031`).
- **EBUF** at `0x1a4c0000` (SPI 201-204): a buffer between the links and the
  ISP's on-the-fly path; it has a fake-frame generator. Not on our path [I].
- **The HAL names the route** in its log line
  "Camera ID, CSIS LINK, CSIS EBUF, WDMA INPUT, CSIS WDMA, PDP WDMA, ZSL WDMA, ..."
  and refuses a RAW output unless the usage includes "csis wdma"
  (`A/lib64/liblyric_hwl.so` strings). So stock's own RAW capture goes link →
  CSIS WDMA → memory, the route we want. [V] that the route exists; [I]
  how the link-to-WDMA routing is programmed (a common register in the DMA
  block's first page, section 4.1).
- **DC-PHY** `samsung,mipi-phy-m0s4s4s4s4s4`: no master, five 4-lane slave
  groups. Per-link PHY register windows:
  - link 0 at `0x1a4f1300` and link 1 at `0x1a4f1b00` (`0x500`: clock lane +
    four data lanes, `0x100` each): full 4-lane PHYs;
  - links 2-7 at `0x2300, 0x2600, 0x2b00, 0x2e00, 0x3300, 0x3600`
    (`0x300`: 2-lane). Pairs (2,3), (4,5), (6,7) combine into one 4-lane
    group; the odd member has its clock lane after its two data lanes
    (the HAL's register table puts the clock-lane `GNR_CON0` of PHYs 3, 5, 7 at
    `+0x200`), which is the GPL driver's "2lane, Data lane first" variant;
  - a shared bias block at `0x1a4f1000` (`M_BIAS_CON0-2`);
  - one PMU isolation bit for all of them at PMU `0x3ebc` (SMC regmap only)
    and one reset bit per PHY in `0x1a420500` (`samsung,reset-sysreg`, bits 0-7).
- **GPL D-PHY receive settings exist** for this PHY version (`0x0504`):
  `GS/drivers/phy/samsung/phy-exynos-mipi.c:516-770`, three variants (4-lane,
  2-lane, 2-lane data-first): per-lane `GNR_CON0/1`, `ANA_CON2/3/7`,
  `TIME_CON0/1` (settle count, settle clock select), `DESKEW_CON0/4`, and
  skew-delay selection by rate (1.5-6.5 Gbps). **The C-PHY branch is
  `/* TODO */`** (`:594, 680, 765`). LWIS only powers the PHY on and off
  (`LW/lwis_phy.c:120-160`); the HAL writes the lane settings itself through
  the `csis-phy` register space. So stock's values may differ from the GPL
  ones; that is a first thing to check if a link shows SOT errors.
- **Mainline relative for the PHY:** `L/drivers/phy/rockchip/phy-rockchip-samsung-dcphy.c`
  drives the *master* (transmit, D-PHY only) side of the same family: the
  same per-lane `GNR/ANA/TIME/DESKEW` layout and `0x100` lane stride, and
  "CPHY part to be implemented later". Useful to name the fields.
- **IOMMU and firewall:** `sysmmu_csis0` (`0x1a510000`, SPI 220/221) and
  `sysmmu_csis1` (`0x1a540000`, SPI 231/232) are Samsung SysMMU v8, which
  mainline's `exynos-iommu.c` doesn't support. `s2mpu_csis0/1`
  (`0x1a520000`, `0x1a550000`) are programmed by pKVM on stock; we don't run
  pKVM. Plan: SysMMU in bypass and physically contiguous buffers below
  4 GiB from a dedicated reserved pool [I: that the SysMMU is in bypass and
  the S2MPU allows all after ABL, as `s2mpu_hsi0` does (`WIFI-BATTERY-PLAN.md` 1.5)].
  `samsung,tzmp` on the CSIS node is for secure (face-unlock) buffers, not
  the normal path [I].

### 1.4 Power domains, clocks and DVFS

- **`pd-csis`** at PMU `0x18062400` (`CONFIGURATION` `+0x0`, `STATUS`
  `+0x4`), CMU_CSIS at `0x1a400000`, a DTZPC restore/save SMC with id
  `0x1a410204` around each power cycle (`R/live.dts:7343-7352`,
  `GS/drivers/soc/google/cal-if/pmucal_local.c:52-61, 122-130`,
  `GS/drivers/soc/google/cal-if/gs201/flexpmu_cal_local_gs201.h:907-934`).
  The `lwis_csi` node itself declares `pd-pdp` (`0x18062480`, no parent
  domain), while the CSIS SysMMUs and S2MPUs declare `pd-csis`
  (`GD/gs201/dts/gs201-isp.dtsi`, `gs201-sysmmu.dtsi:96,127`,
  `gs201-s2mpu.dtsi:40,47`), so stock holds both on while capturing.
- **ABL leaves every camera domain on.** Stock's `exynos-pd` reads the real
  status at probe and logs it: `pd-csis`, `pd-pdp`, `pd-g3aa`, `pd-ipp`,
  `pd-itp`, `pd-dns`, `pd-mcsc`, `pd-gdc`, `pd-tnr`, `pd-tpu` and `pd-aur`
  are all "on" at 0.30 s, and stock turns most of them off at `sync_state`
  (`R/dmesg.txt`, `GS/drivers/soc/google/exynos-pd.c:443-485`). Our DTB
  boots with `clk_ignore_unused pd_ignore_unused` and we have no gs201 PD
  driver, so **on our kernel these domains should still be on** [I: CAM1.1
  confirms it through the kernel's PMU regmap]. Two consequences:
  - CSIS registers are reachable without a power-domain driver, as long
    as nothing cycles the domain. We start there and leave the PD driver
    for later.
  - Today the phone spends power on an idle ISP. That belongs in
    `POWER-PLAN.md` once confirmed.
- **Clocks:** our `clk-gs201.c` already registers CMU_TOP's `CIS_CLK0-7`
  mux/divider/gate and `CSIS_NOC` (`L/drivers/clk/samsung/clk-gs201.c:103-117, 173-185, 258-271`).
  No CMU_CSIS driver yet; its Q-channels gate on their own.
- **DVFS:** CAM (ACPM DVFS index 10), INTCAM (8) and TNR (9) boot at their
  lowest level, 67 MHz (`ACPM-PLAN.md` section 2; stock devfreq tables
  67-664 MHz in `R/dmesg.txt`). The CSIS clock comes from these domains [I].
  A 12 MP RAW10 stream at 30 fps is about 450 MB/s; the first stages run
  binned or slow modes, and real frame rates wait for ACPM DVFS
  (`omamobile-acpm`, built, not yet run).
- **Bus QoS (BTS):** stock registers the scenario `camera_default`. Without
  it, display and camera DMA share the bus unmanaged; watch for WDMA
  `FIFO_FULL` and link `ERR_OVER` [I].

### 1.5 Firmware

- **Path (a) needs no firmware blob.** The sensors, CSIS and DMA are plain
  registers; LWIS loads nothing. What we need from the user's image is
  *data*: sensor mode register tables and, later, C-PHY settings
  (section 5.3).
- The OIS controllers (`gargoyle`, `jotnar`) may need firmware the HAL
  carries [I]; not needed for a photo.
- Only the HAL's extras use firmware: the GXP DSP (`gxp_fw_core0-3` in
  `/vendor/firmware`), the EdgeTPU. Not on our path.

### 1.6 Calibration and identifying data

- Each module EEPROM holds factory calibration (lens shading, white balance,
  PDAF, OIS) that is **unique to this phone**. We read it, never write it,
  and **never commit it**: the dumps stay in `~/android/reference/`.
- The HAL also reads per-phone camera calibration from `persist`
  (`/mnt/vendor/persist/camera/...`: multi-camera calibration, a tele module
  file, flash white balance). **Nothing writes `persist`.** If we ever use
  those files, we read them from the read-only partition backup.
- The HAL's tuning files (`A/etc/camera/*.binarypb`, the per-sensor
  `*_golden_sensor_factory_calibration_data.binarypb`) are Google's data:
  never committed, and our own tuning for libcamera starts from scratch.

### 1.7 Corrections to RADIOS-CAMERA-PLAN.md section 4

- **The `0x50` EEPROM on `hsi2c_15` is not a camera EEPROM.** It is an
  `at,24c08` next to the wireless charger (`idt,p9412` at `0x3c`) on the
  same bus (`R/live.dts:8408-8450`); the camera EEPROMs are on the sensor
  buses (section 1.1). Drop C0.2 of the old runbook: that EEPROM may
  hold identifiers.
- **The camera domains are on after ABL**, so `pd-csis` doesn't block the
  first CSIS stages (section 1.4).

---

## 2. Linux state

| Piece | Mainline 7.3-rc6 | Ours | Needed |
|---|---|---|---|
| `hsi2c_1-4` (PERIC0 USI1-4) | driver yes | `hsi2c_3` (USI3, sysreg `0x1008`, SPI 676) built, disabled; 1, 2, 4 not yet | DT: USI1-4 with `samsung,sysreg = <&sysreg_peric0 0x1000..0x100c>` [I: from stock `usi-offset` 0-0xc and our USI8 at `0x101c`], SPI 674-677, pins gpp2/4/6/8 0-1, 1 MHz (buses 1, 4) and 950 kHz (2, 3) as stock |
| S2MPG13 LDO12S | — | descriptor in `s2mps11.c`; `ldo12s` in `pmic-2`, disabled until camera-pwr-test (built) | — |
| S2MPG13 GPIO bank | no | `gpio` regmap (ACPM type `0x0c`) in `sec-acpm.c`, `gpio-s2mpg13` (built, blacklisted) | — |
| SLG51002 | no (`slg51000` only) | `slg51002-regulator` (built, blacklisted): LDO1-8 and the four switches, no test mode, no IRQ | GPIO/pinctrl part not needed |
| CIS_CLK0-7 | — | in `clk-gs201.c` | DT consumers |
| DC-PHY RX | no | no | new generic PHY driver (D-PHY first) |
| CSIS link + WDMA | no | no | new V4L2 driver |
| Sensors | none of the four | — | IMX386 [I] first (or `ccs` + static data, section 5.3), then 3J1, GM5, GN1 |
| AF actuators | `ak7375`-style drivers exist | — | identify `0x0c`/`0x0f` parts by ID register |
| SysMMU v8 | no | no | bypass for now |
| PD driver | no | no | later (runtime PM) |
| V4L2 core, `VIDEOBUF2_DMA_CONTIG`, DMA-BUF heaps (system, CMA) | yes | V4L2 modules; heaps built in (`omamobile.config`, built) | `CMA_SIZE_MBYTES=32` is too small: add a reserved pool |
| libcamera | simple + soft ISP | Arch `libcamera 0.7.2` | one entry in the simple handler's device table, a sensor helper, a tuning file |

---

## 3. The options

### (a) Raw capture, software ISP: recommended

- **Kernel:** about 3-4k lines of new code: the CSIS/WDMA V4L2 driver
  (media controller, one subdev per link, one video node per WDMA
  context), the DC-PHY RX PHY driver, the SLG51002 and S2MPG13 GPIO
  drivers, sensor drivers.
- **Userspace:** libcamera's simple pipeline handler with the software ISP
  (debayer, AWB, AGC; GPU debayer if Arch's build has it [I]), PipeWire's
  libcamera plugin for apps, the camera portal for Flatpak apps.
- **Licensing:** everything new is GPL kernel code and upstream-able in shape.
  Register *facts* learned from the HAL are written in our own words with
  our own names; sensor mode tables never enter the repository (section 5.3).
- **Limits:** no hardware 3A statistics, no PDAF, no hardware noise
  reduction or HDR+. Image quality will be "decent webcam", not Pixel. Fine
  for QR codes, video calls and snapshots.

### (b) LWIS + stock HAL in a vendor chroot: not recommended

- **LWIS** (`LW/`, about 23.8k lines GPL) is portable in principle, but it
  depends on Google's BTS, `exynos_pm_qos`, SLC partitions, the Samsung
  SysMMU driver and Google's DMA-BUF heaps (`LW/platform/busan/lwis_platform_busan.c`).
  It hands userspace raw MMIO and I2C, so it can never go upstream, and it
  would let a userspace bug write any ISP register.
- **The HAL** (`A/lib64/liblyric_hwl.so`, 20 MB, plus about 50 libraries)
  needs: Google's gralloc and AHardwareBuffer, Mali **kbase** with OpenCL
  (`A/lib64/camera/tuning_ocl.txt`; we run Panthor), the EdgeTPU and GXP
  drivers and firmware, the ISP blocks' power domains and DVFS (PDP, G3AA,
  IPP, ITP, DNS, MCSC, GDC, TNR), the SysMMU v8, binder and the camera
  provider AIDL, and an Android camera client to drive it. It reads
  `persist`; some paths look writable (`.../nagual_need_higher_gate_voltage.reg`).
- **Even working, it ends at an Android `camera2` stream**, which then needs
  a bridge to PipeWire or V4L2 loopback.
- GNSS and fingerprint work in a chroot because each is one daemon on one
  character device. The camera HAL is the opposite: dozens of kernel
  interfaces. Effort: many months, with no upstream value.

### (c) What mainline has

- `drivers/media/platform/samsung/exynos4-is/` (FIMC-IS, Exynos4 CSIS) and
  `drivers/media/platform/nxp/imx-mipi-csis.c` (CSIS v3.3/v3.6.3): older
  versions of the receiver. The link register offsets match gs201
  (section 1.3), so `imx-mipi-csis` is the model for the link half of our
  driver. Neither has the separate DC-PHY or the WDMA.
- `drivers/phy/rockchip/phy-rockchip-samsung-dcphy.c`: the transmit side of
  the same DC-PHY family, D-PHY only.
- No gs101/gs201 camera series in 7.3-rc6, nor any CSIS v5/WDMA driver.
  A Samsung FSD (Tesla) CSIS series was posted to linux-media in 2022 and
  didn't land [I: check lore before citing]. Rockchip's vendor kernel has
  DC-PHY receive and C-PHY code, but it isn't on our list of citable sources
  (AGENTS.md section 1); ask the human before using it.

---

## 4. What we must learn from the stock HAL (offline, REA)

GPL gives us addresses, interrupts, interrupt bit names, power sequences
and the D-PHY settings. It doesn't give the meaning of the CSIS link control
bits, the WDMA format/control bits, the link-to-WDMA routing, which link and
PHY each sensor uses, lane counts and rates, the C-PHY settings, or sensor
modes. Those are in `A/lib64/liblyric_hwl.so`. Rules: work only on the
user's own image; never commit decompiled code, tables or tuning; write
facts in our own words.

### 4.1 Findings so far (2026-10-12)

- **The HAL carries a named register table.** Records of 48 bytes: block
  name, register name, offset, in `.data.rel.ro`, found by searching
  for pointers to the name strings (the library uses RELR, so the pointers
  are stored in place). One table has 349 entries: 26 for the CSIS link
  and PHY windows (`csis`), 83 for the CSIS DMA (`csis_dma`), 8 for EBUF,
  232 for GTNR align. It confirms the DT offsets (CSIS WDMA context 0 at
  `0x7000`, its interrupt block at `0x7400`) and gives names for the context's
  control, format, skip, 32 per-frame address slots, resolution, stride,
  frame counter and SBWC (compression; keep it off) registers, and for a
  few common DMA registers in the first page. The dump stays off-repo.
- **Sensor modes** are built by per-sensor drivers inside the HAL
  (`.../lyric/drivers/sensors/{nagual,sandworm}/sensor_driver.cc` paths in
  its strings; "register_settings"). Sensor-to-link data lives in a
  `ModuleDescriptor` with `use_cphy`, `csis_link`, `num_lanes` and
  `mipi_rate` fields (strings in `liblyric_hwl.so` and `liblyric_base.so`).
- **The per-camera link, PHY type and lane count are not yet known.**
  RADIOS-CAMERA-PLAN's "main and tele are C-PHY" is unproven [I].

### 4.3 Findings, second pass (2026-10-12)

Offline, on the user's own HAL (`liblyric_hwl.so`); REA's Hopper provider
didn't come up on the 20 MB library, so the evidence is disassembly
addresses in the private notes (`~/android/reference/`-style, off-repo).
Facts in our own words:

- **RE1, ultrawide.** The HAL's sandworm driver expects model ID 0x0386:
  **Sony IMX386** [V]. It runs four D-PHY lanes, RAW10, at **1548 Mbps per
  lane** (link frequency 774.144 MHz) in its standard modes, and its own
  external-clock setting is 24.574 MHz: **stock feeds it the 24.576 MHz
  oscillator**, not a PLL tap. **Which CSIS link it uses is not found**:
  the link index arrives in a copied per-camera config (Cheetah-specific
  setup code not decoded). Only links 0 and 1 have four lanes of their
  own, so CAM3b tried those two; both saw nothing. Superseded by 4.4: it
  is link 2 with the PHY pair 2+3.
- **RE2, CSIS link** (version 0x05040000 on the phone, CAM1.2). Same
  layout as `imx-mipi-csis` for the enable bit, the lane-count field
  (bits 9:8), the data-type field of the channel config (7:2), its pixel
  mode field (13:12, stock uses quad) and the size register. New: a
  virtual-channel field in the channel config (20:16), a two-bit
  interleave field (11:10, stock 3), a separate shadow-update register at
  0xc (stock writes all four channels), the D-PHY common control at 0x704
  (stock 0x1f), a C-PHY bit (21), a debug option bit at 0x690 and a
  line-rate register at 0x600 left at its default. Unused channels get
  data type 0x3f. Stock writes the common control (with enable) last.
- **RE3, CSIS WDMA.** Each context has four channels at 0x100 apart (the
  stock RAW path writes channel 2). Per channel: control (bit 0 enable;
  stock writes 0xf83 to start and 0xf82 to stop), format (code 7 = RAW10
  packed as on the CSI-2 bus, 6 = 16-bit container, 0 = 8-bit; **no packed
  RAW12**), skip, 32 address slots (plain 32-bit values), width (height
  left 0), stride in bytes and a slot mask. The interrupt bits are the
  GPL ones. The common page gets four constant writes once. Stock's
  flush: data control 0, control 1, format 7, control 0.
- **Routing, in the CSIS sysreg** (`0x1a420000`): an EBUF input mux
  (0x430 + 4 x EBUF = link) and a WDMA input mux (0x414 + 4 x context =
  source); sources 8-10 are the PDP channels, and the value for an EBUF
  is **not** found ([I] 0-3 = EBUF 0-3). There is also a PDP mux stock
  sets that a RAW-only path doesn't need [I].
- **RE4, ultrawide settings.** Two init lists (139 writes without phase
  detection, 212 with), and three mode-list builders; the default one
  gives 4032x3016 at 30 fps, a 4032x2272 crop (at a different link
  rate, 794.6 MHz), and 2x2-binned 2016x1508 and 2016x1136 at 60 fps.
  Mode lists use the standard CCS registers for PLL, frame/line length,
  crop, output size and binning; the init lists are manufacturer
  registers. `tools/extract-camera-data` regenerates them (section 5.3).
- **RE5, DC-PHY.** Same registers and timing logic as Google's GPL
  settings, different analog trims (now in our PHY driver), and an HS
  settle count looked up by lane rate from a table; at 1548 Mbps it is 7
  with the fast settle clock [V], which our DT gives for links 0 and 1.

### 4.4 Findings from probing the path with the sensor streaming (2026-10-13)

Facts from bring-up on another Pixel 7 Pro running mainline with this
same camera block, found by setting up one DC-PHY bank at a time with each
sensor streaming and reading the link and WDMA status registers. **Not yet
reproduced on our phone** (CAM3b.5 and CAM4 check them); in our own words:

- **Links and PHYs per camera.** Ultrawide (IMX386, D-PHY, 4 lanes):
  **CSIS link 2 with DC-PHY slaves 2 and 3 as one four-lane receiver**:
  slave 2's clock lane and two data lanes, then slave 3's two data lanes
  (`0x1a4f2300` clock, `0x2400-0x2700` data; slave 3's clock lane unused).
  Front: link 0 / slave 0, D-PHY 4 lanes. Main: link 1 / slave 1, C-PHY.
  Tele: link 4 / slave 4, C-PHY. So CAM3b.3's silence on links 0 and 1 was
  the wrong link, not a missing step.
- **PHY reset.** Each slave's bit in CSIS sysreg `0x500` (Google's GPL DT
  `samsung,reset-sysreg`) must be **set before any access to that slave's
  lane registers**: a slave held in reset hangs the bus. For the pair both
  bits 2 and 3. (Our `f32305542` set the link's bit only after the PHY was
  programmed; for links 0 and 1 that didn't hang, so ABL may leave those
  bits set; CAM3b.5 logs the register before and after.)
- **Isolation**: PMU `0x3ebc` bit 0, as our PHY driver already does through
  the kernel's PMU regmap.
- **DVFS.** CAM (ACPM DVFS domain 10) boots at 67 MHz; there a four-lane
  link at about 1.5 Gbps per lane reports ECC, CRC and overflow errors and
  resolution mismatches. At **400 MHz** it runs clean. The WDMA needs INT
  (domain 1) at **400 MHz** under load (at the default 200 MHz it missed
  frame ends with the GPU busy: context `OVERLAP`).
- **Routing for the WDMA.** `0x430` (+ 4 x slot) = the link; with
  `SC_CON0-2` (`0x408`/`0x40c`/`0x410`, the stock software's "PDP mux") at
  0 the WDMA gets frame and line syncs but **no pixel data** (`LASTDATA`/
  `LASTADDR` errors); any non-zero value (1) lets it through. The EBUF
  (`0x1a4c0000`, bit 0 of its control) **bypassed**; programming it as stock
  does stalled before the first frame start. `0x488` has no effect.
- **Link and WDMA setup that works:** link soft reset first; 4 lanes,
  interleave 3, quad pixel mode, VC 0 RAW10 on channel 0, channels 1-3
  with data type 0x3f **parked on VC 15** (on VC 1 a sensor's second
  stream cut channel 0 to 8 bits); debug option bit 23 (pixel align) set;
  DMA common page reset, then IP processing; WDMA context 0, channel 0,
  format 7 (MIPI RAW10 as on the bus), width and height in the resolution
  register, **line stride rounded to 64 bytes** (2560 for 2016 pixels),
  one address slot rewritten per frame.
- **Values we did not take.** The lane analog values and settle count
  stay ours (RE5; settle 7 at 1548 Mbps agrees). Their bias block writes
  `M_BIAS_CON0-3` as well (`0x10, 0x110, 0x3223, 0`), replayed from the
  stock HAL; we write only `CON4` as RE5 found and log `CON0-4` at power-on
  instead: if CAM3b.5 shows SOT or ECC errors at 400 MHz and different
  `CON0-3`, that is the next single change. We keep stock's WDMA start
  value `0xf83` (they use `0x3`) and the HAL's `0x7fff` line-rate default.

### 4.5 Findings, third pass: front, telephoto, PHY (2026-10-13)

Offline, on the user's own HAL (sha256 `ce9acaad...`) with
`tools/extract-camera-data` and disassembly; facts in our own words:

- **Front: S5K3J1 [V: HAL].** One model-ID function returns 0x30a1; two
  driver classes share it (the camera's own and a "virtual" one). Unlike
  the GN1's, this driver asks a settings object it holds (8 bytes, made by
  the driver factory) for its lists. Default init: 366 writes after the
  soft reset it starts with (page 0xfcfc = 0x4000, 0x6010 = 1, then a
  3 ms delay record), switching between page 0x2000 (a firmware patch) and
  0x4000 (standard registers) through the direct page register 0xfcfc.
  Nine mode lists, five sizes: **3840x2736 at 30 fps** (full), 3840x2236
  at 30, **1920x1368 at 60** (binned, 4:3), 1920x1116 at 120, 3648x2736
  at 30. All four D-PHY lanes (0x0114 = 0x03xx) at an output PLL of
  24.576 MHz x 271 / 4 = **1665 Mbps per lane** [I: that this PLL is the
  lane rate; the ultrawide's analogue rule gave its measured 1548]; the
  HAL's PHY table gives settle 8 there.
- **Telephoto: S5KGM5 [V: HAL].** Model ID 0x08d5. Default init: 4047
  writes (two other variants, 3816 and 3870, behind debug flags), also
  paged through 0xfcfc; no soft reset in the list (the driver writes the
  GN1's). Four modes: **4032x3024 at 30 fps** (2x2 binned from the 48 MP
  array; 1530 writes), 4032x2272 at 60, 2016x1136 at 60, **2016x1512 at 60**.
  The lists don't touch 0x0114, so the part's default lane count applies
  (two C-PHY trios [I], as the board's DT for link 4 suggests). Output PLL
  24.576 x 220 / 3 = **1802 Msps** (the full mode: x 249 / 3 = 2040 Msps)
  [I]; settle 7.
- **The HAL's mode records** (1424 bytes) carry the pixel rate at 0x150
  (GN1 1307.66 M, 3J1 809-811 M, GM5 911.77 M pixels/s; with each list's
  frame and line length they give the frame rates the HAL names) and at
  0x158 the link's capacity in pixels/s: lanes x rate / 10 for D-PHY
  (3J1: 4 x 1665 / 10 = 666), trios x rate x 16/7 / 10 for C-PHY (GM5:
  2 x 1802 x 16/7 / 10 = 824). By the same rule the GN1's 1862 means 2716
  Msps per trio, its output PLL (24.576 x 442 / 4) [I]: the 931 MHz link
  frequency in our DT (CAM-M) is half the HAL's capacity figure, not half
  the symbol rate. Both give settle 7, so nothing changes until CAM-M
  measures it (question 10).
- **The DC-PHY setup, D-PHY [V: HAL].** The same function as for C-PHY,
  with its C-PHY flag clear, writes: every lane off, the bias block
  CON0-4 (`0x10, 0x110, 0x3223, 0, 0x200`: CON0-3 are new to our D-PHY
  path, which left them at 0 on the phone), the clock lane, then per data
  lane the writes our driver made (section 4.3, RE5), with three fields
  following the rate: the settle count, the settle clock select (below
  1500 Mbps) and the skew delay (ANA_CON2 9:8). Its settle table runs in
  111 steps from 80 to 2147 Mbps (the rate argument is a signed 32-bit Hz
  count, so higher rates can't be asked for); 1548 gives 7, as before.
- **Telephoto focus: SEMCO SEM1215SA [V: HAL].** The HAL's register table
  for its actuator family names 0x0200 mode, 0x0201 status, 0x0204/0x0205
  target low/high, 0x0206/0x0207 position read-back, 0x0b00 status
  monitor control (and temperature, soft-landing and standby registers we
  don't use). Its module calibration is read from the controller's memory
  window; the infinity and macro words at 0xc7b6/0xc7bc are [I] (CAM-T
  checks them, read only).
- **Emulator notes.** The library loads its static-guard bytes with
  Armv8.3 RCpc loads (LDAPR), which unicorn's default CPU faults on; the
  tool now selects its newest CPU model. Function-local static lists are
  built by their getter when the guard stub says "initialise now". The
  ultrawide's and main camera's outputs are byte-identical to before.

### 4.2 Work items

| Item | Question | How |
|---|---|---|
| RE1 | link, PHY type, lanes, MIPI rate per camera (ultrawide: all but the link answered, 4.3) | find the `ModuleDescriptor` values per sensor; cross-check on the phone by which link counts frames (CAM5) |
| RE2 | (answered, 4.3) CSIS link control: enable, lane count, data type and virtual channel per channel, `ISP_CONFIG` fields | the code that fills `csis_cmn_ctrl`, `isp_config_ch0` (compare with `imx-mipi-csis` bit fields) |
| RE3 | (answered except the WDMA input value, 4.3) CSIS WDMA: format codes for RAW10/RAW8/RAW16, packing, stride rules, address slot use, enable/abort, link routing | the code around the context-0 control and format registers and the common DMA config register |
| RE4 | (answered; extract tool built) ultrawide mode tables: one binned or 1080p-class mode, its PLL, line length, frame length | the sandworm sensor driver; express as CCS-standard registers where they are standard |
| RE5 | (answered, 4.3, CAM-M, 4.5) DC-PHY settings for both modes | the HAL's PHY setup, run per rate by `tools/extract-camera-data` into `gs201-dcphy.bin` |

---

## 5. Design

### 5.1 Kernel (`omamobile-camera`)

Built (2026-10-12), on `omamobile-int` @ `898ab3c1e`, head @ `6cb2be364`
(release `7.3.0-rc6-omamobile-push1-00331-g6cb2be364f15`):

- `soc: google: add a read-only gs201 camera receiver probe` (CAM1,
  bring-up, `gs201-cam-probe`);
- `dt-bindings: mfd: samsung,s2mpg13-pmic: add the GPIO block`,
  `mfd: sec: s2mpg13: add the GPIO block`, `gpio: add a driver for the
  Samsung S2MPG13 PMIC GPIOs` (item 2);
- `regulator: dt-bindings: add Dialog SLG51002`, `regulator: add a driver
  for the Dialog SLG51002 camera PMIC` (item 3);
- `soc: google: add a gs201 camera module power test driver` (CAM2.3/CAM3a,
  bring-up, `gs201-cam-power`, binding `google,gs201-camera-power-test`);
- `arm64: dts: exynos: google: gs201: add USI3 and its I2C bus`, and for
  cheetah the camera power path (S2MPG13 GPIO node, `ldo12s`, the fixed
  supplies, the SLG51002) and the ultrawide test nodes, all disabled.

Checks: see the end of this section. The plan as written:

1. `arm64: dts: exynos: gs201: add USI1-4 and the camera I2C buses`
   (disabled). USI3 done; USI1, 2, 4 when their cameras come up.
2. `mfd: sec: s2mpg13: add the GPIO bank` + `gpio: s2mpg13`, `ldo12s` in
   `pmic-2`. Done.
3. `regulator: add SLG51002` (port; binding first). Done.
4. `phy: samsung: add the gs201 MIPI DC-PHY receiver` (`google,gs201-mipi-dcphy-rx`):
   D-PHY 1/2/4 lanes from the GPL `0x0504` settings, isolation through the
   PMU regmap, reset through the CSIS sysreg; C-PHY later.
5. `media: samsung: add the gs201 CSIS receiver` (`google,gs201-csis`):
   - per-link subdev (sink pad from the sensor, source pad to a WDMA);
   - per WDMA context a V4L2 video node, `vb2-dma-contig`, MMAP and DMABUF;
   - IRQ handling from the GPL bit names; frame start/end counters in debugfs;
   - formats: RAW10 packed (`V4L2_PIX_FMT_SRGGB10P`) first, RAW8 for tests.
6. Sensor driver(s) (section 5.3).
7. DT for cheetah: sensors with their supplies, `reset-gpios`, `clocks`
   (`CIS_CLKn`), `pinctrl` MCLK states, endpoints with `data-lanes` and
   `link-frequencies`; a reserved `shared-dma-pool` below 4 GiB for capture
   (two cells address, one cell size, AGENTS.md gotcha), disabled by default,
   enabled by overlays in `device/cheetah/overlays/camera-*.dtso`.
8. Config: `CONFIG_VIDEO_GS201_CSIS=m`, `CONFIG_PHY_GS201_MIPI_DCPHY=m`,
   `CONFIG_REGULATOR_SLG51002=m` (done, with `GPIO_S2MPG13`, the two
   bring-up modules, the DMA-BUF heaps and `VIDEO_CCS`), sensor modules.

**Checks (laptop, 2026-10-12):** `bin/omamobile kernel` exit 0 into
`out-camera`; `W=1` on `gs201-cam-probe.o`, `gs201-cam-power.o`,
`gpio-s2mpg13.o`, `slg51002-regulator.o`, `sec-acpm.o`, `sec-common.o`: no
warnings; the DTB builds `W=1` with only the existing simplefb
`unit_address_vs_reg` warning; checkpatch `--strict`: only the usual
no-Signed-off-by and MAINTAINERS items, plus "binding in the same patch"
on the bring-up power test driver (never sent upstream). `dt-doc-validate`
and the examples of the three new or changed bindings pass; `dt-validate`
(dtschema 2026.9) on the default DTB and on default + `camera-pwr-test`:
only the existing `soc_id` and framebuffer `post-init-providers` reports.
The overlay applies with `fdtoverlay` and turns on the nine nodes it names.
Nothing has run on the phone.

**Capture path, built 2026-10-12 on top (head `35295a9ab`, test build in
`out-camera`):**

- `clk: samsung: gs201: round the camera master clock dividers to the
  closest rate`: a 24 MHz request on the oscillator gives 24.576 MHz, as
  stock, instead of 12.288 MHz.
- `dt-bindings: phy` + `phy: samsung: add the gs201 MIPI DC-PHY receiver`
  + `use the board's analog settings` (`phy-gs201-mipi-dcphy-rx`, D-PHY,
  settle per link from DT).
- `dt-bindings: media` + `media: samsung: add the gs201 CSIS receiver and
  CSIS WDMA driver` (`gs201-csis`): one link + one WDMA context per node,
  media graph sensor -> CSIS subdev -> video node, RAW8/RAW10, frame-sync
  events. Bring-up parameters: `allow_stream` (default off; on since
  `35f679a26`),
  `link_only` (run PHY, link and sensor without the WDMA: no DMA),
  `wdma_channel` (0-3, default 0). Debugfs `stats` and `regs` (registers
  only while streaming).
- `media: i2c: add a Sony IMX386 driver` (`imx386`): standard controls
  (exposure, analogue/digital gain, vblank, hblank, pixel rate, link
  frequency, test pattern, orientation), modes and init from the data file
  `omamobile/camera/imx386-uw.bin`; power-up in stock's order.
- DT: `sysreg_csis`, `csis_dcphy`, `csis0`/`csis1` (links 0/1, WDMA
  contexts 0/1), the IMX386 with an endpoint to each link, a 64 MiB
  capture pool below 4 GiB. Overlays `camera-stream-link0` and
  `camera-stream-link1` enable one link each (never together with
  `camera-pwr-test`). (Replaced 2026-10-13, below.)

**Link 2, built 2026-10-13 on top (head `3390774a8`, test build
`7.3.0-rc6-omamobile-push1-00351-g3390774a8b80` in `out-camera`; not
merged into int):**

- `d6d2c26a1` `dt-bindings: phy: ... add the slave reset register` and
  `aa6681da9` `phy: samsung: gs201-mipi-dcphy-rx: release the slave
  resets, and four-lane pairs`: links 2, 4, 6 accept four lanes and claim
  the odd partner; the reset bits of every slave in use are set before the
  first lane access and cleared after the lanes are off
  (`google,reset-sysreg = <&sysreg_csis 0x500>`); the power-on line now
  also logs the reset register and bias `CON0-4`.
- `e371c4675` `dt-bindings: media: ... add the EBUF and the DVFS clocks`
  and `280c409a7` `media: gs201-csis: DVFS votes, WDMA routing with the
  EBUF bypassed, PHY reset to the PHY`: optional `cam`/`int` clocks (ACPM
  DVFS 10 and 1) voted to 400 MHz while streaming (INT only with the
  WDMA on), restored at stop; parameters `cam_khz`, `int_khz` (0 = no
  vote). Routing: `SC_CON0-2` = 1, `0x430` = link, EBUF bypass, all put
  back at stop; the `0x414` write is gone. Channels 1-3 on VC 15, link
  soft reset, DMA common reset, WDMA height. `link_reset_release` is gone
  (the PHY owns `0x500`); `sysreg_link_sel` stays as an experiment.
- `3390774a8` `media: gs201-csis: align the WDMA line stride to 64 bytes`
  (2016 pixels: 2560 bytes a line, 3 860 480 a frame).
- `11ca65d94` (gs201: `csis2` at `0x1a460000`, SPI 191, WDMA context 0
  SPI 197, EBUF range, CAM/INT clocks; the PHY reset register) and
  `680d47604` (cheetah: one sensor endpoint, to link 2; capture pool on
  `csis2`; settle 7 for link 2). Overlay `camera-stream-link2` (repo)
  enables link 2 and keeps links 0 and 1 off; `camera-stream-link0/1`
  are removed (their links no longer have the sensor).

Checks (laptop, 2026-10-13): `bin/omamobile kernel` exit 0; `W=1` on
`gs201-csis.o`, `phy-gs201-mipi-dcphy-rx.o` and the DTB: only the
existing simplefb warning; checkpatch `--strict` per commit: only the
trailer-form items; `dt_binding_check` on both changed bindings (dtschema
2026.9) clean; `dt-validate` on the default DTB and on default +
`camera-stream-link2` (applied with `fdtoverlay`): only the existing
`soc_id` and framebuffer reports; the overlay leaves `csis@1a460000`,
`phy@1a4f0000` and `camera-sensor@1a` okay, `csis@1a440000/1a450000`
disabled.

Checks: `bin/omamobile kernel` exit 0; `W=1` clean on the new objects;
checkpatch `--strict` clean apart from the usual trailer items;
`dt-doc-validate` and examples pass for the new bindings; `dt-validate` on
the default DTB and default + each of the three camera overlays: only the
existing `soc_id` and framebuffer reports.

**Every PHY setting from the data file; front and telephoto, built
2026-10-13 on top of `e6fc91e77` (head `c91185280`, test build
`7.3.0-rc6-omamobile-push1-00382-gc91185280474` in `out-camera`; not
merged into int):**

| Commit | |
|---|---|
| `b53e91232` | `dt-bindings: phy: google,gs201-mipi-dcphy-rx: settings for every link from the data file` |
| `f397875e0` | `phy: samsung: gs201-mipi-dcphy-rx: take the D-PHY settings from the data file too` |
| `15b6520b0` | `arm64: dts: exynos: google: gs201-cheetah: one DC-PHY settings file` |
| `3a5034d4e` | `dt-bindings: media: google,gs201-csis: LRTE packet delimiters` |
| `96db0fbad` | `media: gs201-csis: LRTE packet delimiters` |
| `51d26c424` | `dt-bindings: media: i2c: samsung,s5kgn1: add the S5K3J1 and S5KGM5` |
| `2f58a69dd` | `media: i2c: s5kgn1: support the S5K3J1 and S5KGM5` |
| `58da5a453` | `dt-bindings: vendor-prefixes: add semco` |
| `963e2c8a1` | `dt-bindings: media: i2c: add SEMCO SEM1215SA` |
| `44addd39f` | `media: i2c: add a SEMCO SEM1215SA lens driver` |
| `30e0ab416` | `arm64: dts: exynos: google: gs201: add USI2, USI4 and CSIS link 4` |
| `c91185280` | `arm64: dts: exynos: google: gs201-cheetah: front and telephoto cameras` |

- **DC-PHY (question 11).** No stock value is left in the driver or the
  DT: the D-PHY bias and lane words, the settle count by rate (the DT's
  `google,hs-settle` is gone) and the skew delay come from
  `omamobile/camera/gs201-dcphy.bin`, like the C-PHY ones. New format
  "ODPH" v1 (replaces "OCPH", never installed): per mode a list of
  operations on the bias block, the clock lane (D-PHY) or every data lane
  or trio (write, masked update, or masked update from a rate-table
  column) and a rate table (Mbps or Msps). Loaded at the first power-on
  of any link; `firmware-name` is now required. **A missing or bad file
  fails the power-on** ("PHY settings ... not loaded (-2): generate them
  from your phone's software"), and a rate outside the table's range is
  refused. The only change on the wire for the ultrawide: bias CON0-3 are
  now written with stock's values (they read 0 before, CAM3b.5).
- **CSIS:** `google,lrte-packet-delimiters` on a link sets its LRTE
  packet delimiter enable (0x600 bit 31, spacers at reset: 0xffff7fff);
  the telephoto's link 4 has it [I: the bring-up in section 4.4 needed it].
- **Sensors:** the `s5kgn1` driver now takes `samsung,s5k3j1` and
  `samsung,s5kgm5`: per part the chip ID, supplies and waits in stock's
  order (3J1: LDO12S, LDO8, switch 4, 1 ms, MCLK, 1 ms, reset, 8 ms; GM5:
  LDO12S, 0.3 ms, LDO7, LDO3, MCLK, 1 ms, reset, 10 ms), the soft reset
  (3J1: through page 0xfcfc, 3 ms; GM5 as the GN1), page 0x4000 selected
  again before controls (3J1, GM5), and the crop mapping. Subdevs are
  named `s5k3j1`/`s5kgm5`/`s5kgn1` (libcamera picks helper and tuning by
  it). `samsung,vertical-flip` sets 0x0101 bit 1 after the settings and
  reports the flipped Bayer order (the telephoto: GRBG read flipped =
  BGGR) [I].
- **`sem1215`** (new, `CONFIG_VIDEO_SEM1215=m`): the telephoto's focus as
  a V4L2 lens subdev. Power in stock's order, wait for status 0x0201 = 1,
  servo on (0x0200 = 1), status monitor on (0x0b00 = 1), position low then
  high byte; servo off before power-off; powered while the subdev is open
  (as ak7375). At probe it reads the module's focus calibration (read
  only) and limits the control to it plus 40 codes; implausible values
  leave 0-1023. `debug_position=1` logs the read-back.
- **DT:** USI2 (0x1004, SPI 675, gpp4-0/1) and USI4 (0x100c, SPI 677,
  gpp8-0/1), CSIS link 4 (`csis4`, 0x1a480000, SPI 193, WDMA context 0);
  cheetah: the S5K3J1 at `hsi2c_2` 0x10 on `csis0` (4 D-PHY lanes,
  832512000 Hz), the S5KGM5 at `hsi2c_4` 0x2d on `csis4` (2 C-PHY trios,
  901120000 and 1019904000 Hz, vertical flip) and its SEM1215SA at 0x34,
  MCLK pins gpp5-0 and gpp7-0, all on the shared 128 MiB pool. All
  disabled. Overlays (repo): `camera-front`, `camera-tele`; `camera-main`
  and `camera-stream-link2` no longer disable link 0.
- Repo: `tools/extract-camera-data` writes all four sensors' files and
  `gs201-dcphy.bin` in one run; `tools/camera-cap-test` takes
  `SENSOR=s5k3j1|s5kgm5`; device-cheetah 0.1.28 blacklists `sem1215`;
  `CONFIG_VIDEO_SEM1215=m`.

**Checks (laptop, 2026-10-13):** `bin/omamobile kernel` exit 0; `W=1` on
`phy-gs201-mipi-dcphy-rx.o`, `gs201-csis.o`, `s5kgn1.o`, `sem1215.o` and
the DTB: only the existing simplefb warning; checkpatch `--strict` per
commit: only the trailer form and (new files) MAINTAINERS;
`dt_binding_check` (dtschema 2026.9) on the PHY, CSIS, sensor, lens and
vendor-prefix bindings clean; `dt-validate` on the default DTB, on
default + each of `camera-front` and `camera-tele`, and on default +
`camera-stream-link2 camera-uw-lens camera-main camera-front camera-tele`:
only the existing `soc_id` and framebuffer reports, and the last leaves
all four links, the PHY, the four sensors and three lenses okay. The data
files from this HAL: `imx386-uw.bin` and `s5kgn1-main.bin` byte-identical
to before, `s5k3j1-front.bin` (7088 bytes), `s5kgm5-tele.bin` (51452),
`gs201-dcphy.bin` (2480: D-PHY 32 writes, 3 rate columns, 111 ranges;
C-PHY 20 writes, 2 columns, 3 ranges, the same values as the old C-PHY
file); copies in `~/android/reference/` only.

### 5.2 Userspace

- libcamera: Arch Linux ARM ships 0.7.2-4 (= upstream's latest release)
  with the simple pipeline and the software ISP already built, but the
  simple handler matches only media devices whose driver name is in a
  fixed table, and a configuration file can't add one. So
  `packages/libcamera` (built 2026-10-12, not yet built for the phone) is
  Arch's PKGBUILD with one patch adding `gs201-csis` with the software ISP
  on, simple and uvcvideo pipelines only, the GPU debayer enabled (it
  falls back to the CPU; `LIBCAMERA_SOFTISP_MODE=cpu` forces it), pkgrel
  4.1. No IMX386 `CameraSensorHelper` or sensor-properties entry: without
  them libcamera treats the gain code as linear and has no unit cell size,
  which is enough for a first picture; the gain formula and pixel size
  have no citable public source yet.
- What libcamera needs from the kernel (checked against 0.7.2's simple
  handler): media driver name `gs201-csis`; a `CAM_SENSOR` entity with one
  source pad; a path sensor -> CSIS -> video node; the CSIS keeps the
  sink format on its source pad unchanged (so it must not align widths);
  a video node with `IO_MC`, `ENUM_FMT` by media bus code,
  `ENUM_FRAMESIZES`, exact `S_FMT`, MMAP/DMABUF/EXPBUF; a DMA-BUF heap
  (present since K); and on the sensor `ANALOGUE_GAIN`, `EXPOSURE`,
  `HBLANK`, `VBLANK`, `PIXEL_RATE`. Frame-sync events on the CSIS subdev
  keep the soft ISP's exposure updates in step. Our drivers do all of
  this; sensor crop selections and flips are left for later.
- `omamobile-camera` package: modprobe policy (modules blacklisted until
  the start unit loads them, the AoC pattern), a minimal tuning file, udev
  rules for `/dev/video*` and `/dev/media*`.
- Apps: `cam` for tests, then a PipeWire camera app (GNOME Snapshot) and
  the browser through the camera portal.

### 5.3 Sensor register data without committing it

- Prefer CCS-standard registers (mode select `0x0100`, PLL `0x0300-0x030f`,
  frame and line length `0x0340/0x0342`, output size `0x034c/0x034e`,
  binning `0x0900`, test pattern `0x0600`) and mainline drivers of the
  same family (`imx258`, `imx319`, `imx355` for Sony; `s5k3m5`, `s5kjn1`
  for Samsung).
- **Built: `tools/extract-camera-data`.** It finds the IMX386 functions in
  the user's own `liblyric_hwl.so` by a byte pattern (the model-ID
  function and the mode dispatcher next to it) and by the shape of the
  init-list builders, runs them in the unicorn AArch64 emulator (PLT calls
  and imported data stubbed), reads back the register lists they build,
  computes each mode's size, frame and line length, pixel rate and link
  frequency from the standard registers in it, and writes our own data
  format (documented in `imx386.c`), which the driver loads with
  `request_firmware()` from `/usr/lib/firmware/omamobile/camera/`.
  Checked on this laptop with the user's HAL: 139 init writes, four modes
  of 73 writes each, frame rates 30/60 as the HAL names them. The pixel
  rate assumes four pixels per video-timing clock [I]; the analogue gain
  range 0-480 and the exposure margin of 10 lines are [I] too. The output
  is per-phone and never committed; it needs `pip install unicorn
  pyelftools` in a virtual environment.
- **Extended 2026-10-13** to the three Samsung parts and the PHY: one run
  (`--apex ... -d DIR`) writes `imx386-uw.bin`, `s5kgn1-main.bin`,
  `s5k3j1-front.bin`, `s5kgm5-tele.bin` and `gs201-dcphy.bin`. The 3J1's
  and GM5's lists are found from their model-ID functions as the GN1's
  (the 3J1 through the settings object its driver holds; section 4.5);
  delay records in a list become the delay byte of the write before them;
  a part's leading soft reset (the driver's to write) is checked and
  dropped; one mode per output size (the HAL's first). The PHY file runs
  the HAL's PHY setup once per rate in D-PHY (80-2147 Mbps) and C-PHY
  (1-2147 Msps) mode with a stand-in register writer, checks that every
  lane gets the same writes in bias, clock lane, data lane order, and
  turns the masked writes whose value follows the rate into rate-table
  columns.
- Mainline `ccs` with CCS static data was the other candidate. It needs
  the sensor's limit registers or a full set of limits in the static data,
  neither of which we have for the IMX386; a small driver with the
  extracted lists is the more certain route. `ccs` stays worth a try once
  the sensor streams (an identify + limits read is harmless).
- Upstream may object to a driver that can't stream without a vendor data
  file. That is the honest trade-off; record it in the cover letter.

---

## 6. Stages, effort and timeline

| Stage | What | Needs | Effort |
|---|---|---|---|
| CAM0 | Read-only: clocks, pins, LDO12S, libcamera, CMA (current int kernel) | nothing | 0.5 day |
| CAM1 | Read-only kernel probe: PMU status of the camera domains, then CSIS link versions, one register per boot | probe module | 2-3 days |
| CAM2 | Rails, one per boot: S2MPG13 GPIOs and the fixed supplies; GPIO 0 → SLG51002 chip ID; LDO12S → ultrawide EEPROM answers | buses, S2MPG13 GPIO, SLG51002 (built) | 1 week |
| CAM3a | Full ultrawide sequence → sensor chip ID, read-only; then front, tele, main | `gs201-cam-power` (built) | 0.5-1 week |
| RE1-RE4 | Offline HAL analysis (section 4) | REA | 2-3 weeks, in parallel with CAM2 |
| CAM3b | Ultrawide streams a test pattern; DC-PHY RX up; find the link (0 or 1) whose frame counter runs, no errors; no DMA | built: PHY, CSIS (`link_only`), IMX386, data file | 2-4 boots |
| CAM4 | CSIS WDMA writes the test pattern, then a real image, to a file (`v4l2-ctl`); find the WDMA input value and channel | built: CSIS/WDMA | 3-6 boots |
| CAM5 | libcamera `cam` photo; PipeWire app preview | built: `packages/libcamera` | 1 week |
| CAM6 | Video: 1080p30 preview, recording (software encode), ACPM CAM DVFS | ACPM merged | 2-3 weeks |
| CAM7 | Front camera (fixed focus) | CAM5 | 1-2 weeks |
| CAM8 | Main and tele (C-PHY if RE1 says so; GN1/GM5 binned modes) | RE5, C-PHY PHY code | 4-8 weeks |
| CAM9 | Focus (VCM drivers, libcamera AF), OIS, flash sync | CAM5 | 2-4 weeks |
| CAM10 | Runtime PM: gs201 PD driver for `pd-csis` (SMC, DTZPC), SysMMU v8 | PD work shared with GPU | 2-3 weeks |

**Realistic timeline** (one agent writing, the human running gated steps):
first raw frame from the ultrawide in **6-9 weeks**, a photo in `cam` and a
PipeWire app in **8-12 weeks**, video **2-3 weeks** later, all four cameras
with focus in **4-6 months**. The biggest unknowns are RE2/RE3 (if the WDMA
needs more than its register table shows, CAM4 doubles) and RE5 (if the
C-PHY settings can't be recovered, main and tele wait, and Omarchy Mobile ships
with the ultrawide and front cameras).

### 6.1 Risks

- **Bus aborts.** Reading CSIS, CMU_CSIS or PHY registers with `pd-csis`
  off, or a PHY register while isolated, can abort the SoC. CAM1 reads the
  domain status through the kernel's PMU regmap before touching anything, and
  reads one register per boot on the first probe. Never read PMU registers
  from userspace.
- **The PMIC and the rails.** The camera rails share PP3200_BB_CAM with the
  laser AF supply. Only the documented stock voltages are used; no voltage
  writes on S2MPG13 (its regulators are switched only, as for GNSS); the
  SLG51002 test-mode trim is skipped unless the chip is revision AA, and
  read back first. Every stage that switches a rail also switches it off.
- **Shared pins.** gpp8 carries the tele bus (gpp8-0/1), the torch HWEN
  (gpp8-2) and the laser AF supply enable (gpp8-3): the pinctrl groups must
  not overlap.
- **The S2MPU after a domain cycle.** Nothing in CAM0-CAM9 cycles
  `pd-csis`. CAM10 must restore the DTZPC through the SMC and check that the
  S2MPU is allow-all before any DMA (it resets with the domain [I]).
- **DMA to the wrong place.** With the SysMMU in bypass, a wrong address in
  a WDMA slot writes anywhere in the first 4 GiB. The driver programs only
  addresses inside its own reserved pool and checks every slot it fills;
  first DMA tests use a test pattern into a pool far from other users, with
  `--watchdog` and the log stream on.
- **Calibration and persist.** Module EEPROMs and `persist` are read-only
  for us and never committed (section 1.6).
- **Proprietary data.** Nothing derived from the HAL enters the repo except
  facts in our own words; the extract tool generates data on the user's
  machine.

---

## 7. Runbooks (gated)

Phone in Arch over USB, from the omamobile repo. Run each step only when the
human says go; record the result here with the date and `uname -r`. `ov` is
the overlay helper from AUDIO-PLAN.md, with `KERNEL_DIR`/`KERNEL_OUT`
pointing at the kernel being pushed. The staged steps run through
`tools/camera-stage`, which streams `/dev/kmsg` to `logs/` before it touches
anything, marks each action in the kernel log, and with `--watchdog` arms the
hardware watchdog with a feeder, so a hang resets the phone and pstore keeps
the console (`tools/camera-stage --pstore` afterwards).

Built (2026-10-12): see section 5.1 for the branch. CAM0 is partly done;
CAM1, CAM2 and CAM3a are built and waiting for the phone.

### CAM0: read-only, current int kernel (partly run). Risk: none

```sh
# CAM0.1 clocks as ABL left them (software state only)
tools/phone-ssh 'grep -iE "cis_clk|csis" /sys/kernel/debug/clk/clk_summary'
#   expect: CIS_CLK0-3 and CSIS_NOC listed; record enable count and rate
# CAM0.2 sensor resets, MCLK pads, camera I2C pads
tools/phone-ssh 'grep -hE "\((gpp2-[0-2]|gpp4-[0-2]|gpp6-[0-3]|gpp8-[0-3]|gpp3-0|gpp5-0|gpp7-0|gpp9-0)\)" /sys/kernel/debug/pinctrl/*10840000*/pins'
#   expect: resets low or input (sensors off); MCLK pads not in function 2
# CAM0.3 LDO12S as ABL left it (needs gnss-pmic-test and sec_acpm, as GNSS G1)
tools/phone-ssh 'grep -E "^37:" /sys/kernel/debug/regmap/*pmic-2*pmic*/registers'
#   expect: bit 7 = enable; record the selector (stock 1.8 V)
# CAM0.4 userspace and memory
tools/phone-ssh 'pacman -Q libcamera libcamera-tools 2>&1; ls /dev/dma_heap/ /dev/video* /dev/media* 2>&1; grep -i cma /proc/meminfo'
#   expect: no camera nodes; record CmaTotal/CmaFree
```

Stop if any read hangs or errors in an unexpected way. Rollback: none (all
reads). Do **not** dump the `0x50` EEPROM on `hsi2c_15` (section 1.7).

**CAM0 partial result (2026-10-12, 7.3.0-rc6-omamobile-push1-00306-g60d3ca176c80),
read-only.** `clk_summary`: the CMU's sensor clocks (`mout/gout/dout_cmu_cis_clk5..7`
seen) are registered at 24.576 MHz, enable count 0, hardware enable Y, so ABL
leaves them running with no consumer. No `/dev/dma_heap` (CONFIG_DMABUF_HEAPS
and the system/CMA heaps are off in our config), CMA 124 MiB total, about
68 MiB free; no `/dev/video*` or `/dev/media*`; libcamera not installed. Not
yet done: the pin states (CAM0.2, now folded into CAM2.0) and LDO12S, which
needs the pmic-2 regmap (bound only while the GNSS power stack runs, as
FINGERPRINT-PLAN FB2 found; CAM2.0 reads it on the camera-pwr-test boot).

**CAM0.3 result (2026-10-12, 7.3.0-rc6-omamobile-push1-00345-g606b84c7a9fd,
GNSS running so `pmic-2`'s regmap was bound): LDO12S control (PM 0x37) reads
0x2c: bit 7 clear, so L12S_CAMIO is off as ABL left it.** The selector is in
bits 5:0 and LDO12S is in Google's voltage group 6 (0.7 V base, 25 mV
steps; `s2mpg13-regulator.c` `REG_DESC("LDO12S", ..., 6, ...)`, our
`regulator_desc_s2mpg13_ldo_own(12, 6, ...)`): 0.7 V + 44 x 25 mV =
**1.8 V**, stock's camera I/O voltage. (Group 7, 1.8 V base, would make
0x2c read 2.9 V; LDO12S isn't in it.) The GNSS rails read as the same
formulas predict: 0x34 (LDO9S, group 5, 0.725 V + 12.5 mV steps) 0xa6 = on,
1.2 V; 0x35/0x36 (LDO10S/LDO11S, group 6) 0xac = on, 1.8 V. So describing
`ldo12s` with stock's fixed 1.8 V in `camera-pwr-test` finds the selector
already at 1.8 V and writes no voltage; the regulator core only switches
bit 7 when a consumer enables it. CAM2.0 confirms the value again on that
boot.

**Note on the MCLK rate.** CIS_CLK0's divider parent is the 24.576 MHz
oscillator, and the divider rounds down, so asking for stock's 24 MHz would
give 12.288 MHz. The bring-up driver never sets the rate; it logs what it
gets. A sensor's ID registers don't depend on the exact MCLK; streaming will
(CAM3b), and needs a parent that gives 24 MHz (a `dout_cmu_shared*` PLL tap).

### K: the camera kernel and the blacklist. Risk: low (K3 flashes)

Everything in `omamobile-camera` is disabled or blacklisted until a step
enables it, so K3 should boot exactly like the int kernel it is based on,
plus `/dev/dma_heap`.

```sh
# K0 (laptop) build: the branch, or omamobile-int after the human merges it
export KERNEL_DIR=$HOME/android/mainline/wt-camera KERNEL_OUT=$HOME/android/mainline/out-camera
bin/omamobile kernel && bin/omamobile modules && bin/omamobile initramfs
# K1 (phone, one file) the camera blacklist, as a bring-up copy until
#    omamobile-device-cheetah ships modprobe.d/omamobile-camera.conf
tools/phone-ssh 'cat > /etc/modprobe.d/omamobile-camera-bringup.conf' \
  < packages/omamobile-device-cheetah/vendor/modprobe.d/omamobile-camera.conf
tools/phone-ssh 'cat /etc/modprobe.d/omamobile-camera-bringup.conf | grep -c ^blacklist'
#   expect: 4
# K2 (laptop) images with the overlays the phone boots today, no camera overlay yet
ov <the overlays the phone runs now>          # as in AUDIO-PLAN.md / MODEM-PLAN.md
# K3 flash slot B and reboot (ASK FIRST)
bin/omamobile push
# K4 read-only check
tools/camera-stage k
```

- **Expect/Pass (K4):** `uname -r` is the new release; the four modules are
  listed with paths; `blacklist` lines for all four; `/dev/dma_heap/`
  lists `system` and the default CMA heap; the camera-pwr-test overlay is
  not in the DTB. Display, touch, Wi-Fi, audio and GNSS behave as before.
- **Stop:** a regression anywhere (boot, USB, display), or a camera module
  missing.
- **Rollback:** push the previous int images (`$D.default` of the int build)
  or let the boot fall back to slot A.

**K result (2026-10-12, 7.3.0-rc6-omamobile-push1-00345-g606b84c7a9fd: int
606b84c7a with omamobile-camera 6cb2be364 merged, overlays as before, no
camera-pwr-test, device-cheetah 0.1.25): passed.** All four camera modules
are present; the package's blacklist is active (`gpio_s2mpg13`,
`slg51002_regulator`, `gs201_cam_power`, `gs201_cam_probe`), so the
bring-up copy of K1 isn't needed. `/dev/dma_heap` lists
`default_cma_region`, `display-pool`, `reserved` and `system`. Two
`camera-stage` bugs found and fixed since: `k` printed "no camera
blacklist" after listing it (a glob that didn't match made grep fail), and
the tool never exited (killing the log-stream subshell left its ssh
running); the stream now runs in its own process group and is stopped,
with the watchdog feeder, from an exit trap.

### CAM1: domain status, then CSIS registers (gs201-cam-probe). Risk: medium

The module only reads. CAM1.1 reads three PMU registers through the
kernel's PMU regmap (the same plain read stock's power-domain code uses
for these offsets; never from userspace, AGENTS.md); CAM1.2 adds exactly one
register of the camera block, and only if both domains read on. One CAM1.2
read per boot on the first runs: an abort kills the session.

```sh
# CAM1.1 (camera kernel, no overlay needed)
tools/camera-stage --watchdog p1
#   kernel log: "PMU 0x2404 CSIS_STATUS = ...", "0x2484 PDP_STATUS",
#   "0x3ebc PHY_CTRL_MIPI_DCPHY_S4S4S4S4", then "pd-csis on, pd-pdp on, DC-PHY ..."
# CAM1.2, next boot each: link0 first, then link1..link7, wdma, phybias
tools/camera-stage --watchdog --reg link0 p2
#   kernel log: "reading 0x1a440000 (CSIS link 0 version)", then its value
```

- **Pass (1.1):** CSIS_STATUS and PDP_STATUS bit 0 = 1. Record all three
  words; DC-PHY bit 0 is expected 0 (isolated) while nothing streams [I].
- **Stop (1.1):** either domain reads off: don't run CAM1.2; the gs201 PD
  driver (CAM10, shared with GPU-PLAN G4c) moves up. A read error: record
  it, stop.
- **Pass (1.2):** a plausible version word (not 0, not 0xffffffff) for
  link 0, the same for each other link; `wdma` a mask value (0 or a bit
  pattern); `phybias` only once a later stage has released the isolation
  (the module refuses it while bit 0 of 0x3ebc is 0).
- **Stop (1.2):** a hang (the watchdog resets the phone): the read was not
  safe; save pstore and don't retry that block until we know why.
  0xffffffff or 0 from a link: stop, compare with the HAL register table
  (section 4.1).
- **Rollback:** none needed (the module only reads; camera-stage unloads it).

**CAM1 result (2026-10-12, same kernel): passed.** CAM1.1
(`step=pmu`): CSIS_STATUS 0x1, PDP_STATUS 0x1, PHY_CTRL_MIPI_DCPHY_S4S4S4S4
0x0, "pd-csis on, pd-pdp on, DC-PHY isolated": ABL leaves both camera
domains on and our kernel doesn't turn them off, and the PHYs stay
isolated until a driver releases them. `rmmod` clean. CAM1.2
(`step=link0`): CSIS link 0 version **0x05040000**, a plausible version
word; it matches the DC-PHY version 0x0504 that Google's GPL PHY settings
are written for. The phone was fine afterwards. Still to read, one per
boot, when convenient: links 1-7, `wdma`; `phybias` only once the PHY
driver has released the isolation (CAM3b).

### CAM2: the camera power path, one change per boot. Risk: low to medium

Before CAM2: **the PMIC backup check (AGENTS.md).** Steps g1-e1 write the
S2MPG13's GPIO block and the SLG51002, so first confirm the off-repo backup
still matches:

```sh
# CAM2-B (read-only, ~430 MB of reads) against the 20261012-radio backup
tools/phone-ssh 'for p in efs efs_backup modem_userdata persist modem_a modem_b; do
  d=$(grep -l "^PARTNAME=$p\$" /sys/class/block/*/uevent | head -1 | cut -d/ -f5)
  printf "%s  %s.img\n" "$(sha256sum < /dev/$d | cut -d" " -f1)" "$p"; done' > logs/cam2-partitions.sha256
grep -E ' (efs|efs_backup|modem_userdata|persist|modem_a|modem_b)\.img$' \
  ~/android/reference/cheetah-partition-backup-20261012-radio/SHA256SUMS | sort -k2 |
  diff - <(sort -k2 logs/cam2-partitions.sha256) && echo BACKUP-MATCH
```

Stop if it doesn't print `BACKUP-MATCH`: find out why (a slot A boot since
then? MODEM-PLAN M0.1) and take a fresh backup before going on.

Then boot the overlay. `camera-pwr-test` enables `pmic-2` with `ldo12s`
described (stock's fixed 1.8 V), the S2MPG13 GPIO node, the two fixed camera
supplies, the SLG51002 on bus 8, USI3/`hsi2c_3` (950 kHz, as stock) and the
two `gs201-cam-power` nodes (ultrawide sensor 0x1a, its EEPROM 0x50). With
the blacklist in place nothing new binds except the bus: the fixed supplies
and the camera PMIC wait for the GPIO driver, the test nodes for their
supplies.

```sh
# CAM2-K overlay boot (ASK FIRST: flashes and reboots)
ov <the overlays the phone runs now> camera-pwr-test && bin/omamobile push
# CAM2.0 read-only: S2MPG13 GPIO block and LDO12S over ACPM, camera pins
tools/camera-stage r0
```

- **Expect (2.0):** the GPIO regmap dump (registers 02-14). In each pin's
  control register (05 = GPIO0 ... 0c = GPIO7) bit 6 is output enable and
  bit 5 the level; record pins 0 (SLG51002 CS), 1 (PP3200_BB_CAM enable)
  and 3 (PP1300_CAM enable). LDO12S (`37:`) reads 0x2c (off, 1.8 V) or
  0xac (on). gpp3-0 (MCLK) and gpp6-3 (reset) as ABL left them; gpp6-0/1
  in function 3 (I2C).
- **Stop (2.0):** no `-gpio` regmap (pmic-2 didn't bind: check `sec_pmic_acpm`
  in dmesg); bits 1:0 (pin mode) of pin 0, 1 or 3 not 0: something other
  than the output register may own the pin [I]; don't run g1 until that is
  understood. LDO12S's selector not 0x2c: the regulator core will rewrite
  it to 1.8 V when LDO12S registers, so check stock's value first.
- **Rollback:** `ov <the overlays the phone runs now> && bin/omamobile push`.

```sh
# CAM2.1 (this boot) the S2MPG13 GPIO driver. Changes: PP3200_BB_CAM and
#        PP1300_CAM enables become outputs, driven low (supplies off)
tools/camera-stage --watchdog g1
```

- **Expect (2.1):** `gpio-s2mpg13` registers 8 lines; the two fixed
  regulators probe (`PP3200_BB_CAM`, `PP1300_CAM` in the regulator summary,
  disabled); registers 06 and 08 show bit 6 set, bit 5 clear; nothing else
  in the dump changed from 2.0.
- **Pass:** as expected, phone otherwise unchanged (GNSS still powers if it
  runs).
- **Stop:** any other pin register changed; an ACPM error; a regulator
  enabled.
- **Rollback:** reboot (the module is blacklisted, so the pins go back to
  ABL's state only through a full reset; they stay "off" otherwise, which
  is safe).

```sh
# CAM2.2 (next boot) the SLG51002. Changes: GPIO0 high (CS), 10 ms; the LDO
#        voltage selectors set to the stock voltages; every output stays off
tools/camera-stage --watchdog s1
```

- **Expect (2.2):** "pattern ID 0xb13103 (revision AB)" (stock's dmesg
  shows `chip_id: 0xb13103`); 8 LDOs and 4 switches registered, all
  disabled, with the voltages from the DT (2.85, 2.85, 2.25, 2.9, 2.85, 1.1,
  1.0, 1.1 V); register 05 (GPIO0) bit 5 set.
- **Stop:** an I2C error on bus 8 or the haptics stop working (check with
  `tools/phone-ssh python3 - < tools/ff-rumble`, announce the buzz first):
  `rmmod slg51002_regulator` (drives CS low) and reboot. Revision AA or an
  unknown ID: stop; the driver refuses unknown IDs and skips the switches
  on AA.
- **Rollback:** `rmmod slg51002_regulator` (CS low), then reboot.

```sh
# CAM2.3 (next boot) the ultrawide module EEPROM: LDO12S only, one current-
#        address byte read (no address written: the EEPROM is never written)
tools/camera-stage --watchdog e1
```

- **Expect (2.3):** `gs201-cam-power` binds both nodes ("not powered");
  "dovdd on", "eeprom: ack", "dovdd off"; LDO12S back to off (`37:` bit 7
  clear). The byte itself is not printed and not kept: it is calibration
  data.
- **Stop:** "no answer": the rail, the bus pull-ups or the address is wrong.
  Power is already off; record the bus error, don't power anything else.
  Stock pulls the bus lines up only while it transfers; we keep them pulled
  up while bus 3 is enabled, so if the module ever misbehaves, try the
  stock idle state (function 0, no pull) first.
- **Rollback:** `echo 0 > /sys/kernel/debug/gs201-cam-power/*-0050/power`
  (camera-stage does it), reboot.

**CAM2 results (2026-10-12, unattended with the human's permission;
kernels 7.3.0-rc6-omamobile-push1-00345-g606b84c7a9fd for 2.0/2.1 and
-00349-g781b9c3d8523 (int + omamobile-modem 781b9c3d8) for 2.2/2.3;
overlays as before plus camera-pwr-test, suspend-pmic-test,
modem-cpif-test). All passed.** `sec_acpm` is blacklisted by the GNSS
bring-up file (`/etc/modprobe.d/omamobile-g1.conf`) and was loaded by hand
before each run so that `pmic-2` binds; `camera-stage` now does that itself
(and its exit was hardened again: the coordinator still saw it hang after
a step; the stream group is now killed with TERM then KILL and never
waited on unbounded).

- **CAM2-B:** the partition checksums match the 20261012-radio backup.
- **CAM2.0 (r0):** S2MPG13 GPIO block: interrupt masks (02/03) 0xff,
  status (04) 0x00, every pin control register (05-0c) 0x40 = output,
  driven low, mode bits 0, so all eight pins are plain outputs held low by
  ABL (the camera supplies and the SLG51002 are off); monitor selects
  (0d-14) 0. LDO12S `37:` 0x2c (off, 1.8 V). Pins: gpp3-0 (MCLK) input,
  pull-down; gpp6-0/1 function 3 (I2C), pull-up; gpp6-2 and gpp6-3 (reset)
  inputs, pull-down.
- **CAM2.1 (g1):** `gpio-s2mpg13` registered 8 lines; the fixed supplies
  took GPIO1 and GPIO3 as outputs, low; `PP3200_BB_CAM` and `PP1300_CAM`
  probed, use count 0; no register changed (they were already outputs,
  low).
- **CAM2.2 (s1):** `slg51002-regulator 1-0075: pattern ID 0xb13103
  (revision AB)`, as stock; the eight LDOs registered at the DT voltages
  (2.85, 2.85, 2.25, 2.9, 2.85, 1.1, 1.0, 1.1 V) and the four switches, all
  unused and off; no I2C errors on bus 8. The haptics buzz check was
  skipped (nobody at the phone); do it next time someone is.
- **CAM2.3 (e1):** both power-test nodes bound on `i2c-0` (bus 3 is
  adapter 0 on our kernel): `0-001a: 5 supplies, 8 readable registers,
  mclk, reset; not powered`, `0-0050: 1 supplies ... not powered`. LDO12S
  on, **"eeprom: ack"**, LDO12S off; `37:` 0x2c again afterwards.

**CAM3a result (same boot as CAM2.3): passed.** The full stock sequence
ran (PP3200_BB and PP1300 use 2 while powered, gpp3-0 switched to its MCLK
function, gpp6-3 an output driven high = reset released). Register
**0x0016 = 0x03, 0x0017 = 0x86: model 0x0386, the Sony IMX386**, as the
HAL said (section 4.3) and as `imx386.c` checks. Power-down in reverse
(avdd, dvdd, dovdd, PP1300, PP3200, "powered down"), every rail back to use
count 0. The ultrawide's rails, clock and reset are proven; next is CAM3b.

### CAM3a: the ultrawide sensor's chip ID, read-only. Risk: medium

Stock's full sequence for the ultrawide (section 1.2), driven by
`gs201-cam-power` from the DT: reset held asserted (gpp6-3 low) from the
start; PP3200_BB_CAM (2 ms ramp), PP1300_CAM (2 ms), LDO12S, LDO6 (1.1 V),
LDO2 (2.85 V), 1 ms; MCLK pad to function 2 and CIS_CLK0 on, 1 ms; reset
released, 10 ms. Then one register per command from the DT allowlist
(Sony model ID `0x0016`/`0x0017`, the CCS identification block
`0x0000-0x0005`); nothing is written to the sensor. Power-down is stock's
reverse: reset, 1 ms, MCLK off and pad back to output pulled down, 1 ms,
LDO2, LDO6, LDO12S (1 ms), PP1300, PP3200. Nothing streams.

```sh
# CAM3a.1 (next boot; or the same boot as a passed CAM2.3)
tools/camera-stage --watchdog u1
# optional, a later run: the CCS identification block, one register each
tools/camera-stage --watchdog --regs "0x0000 0x0001 0x0002 0x0003" u1
```

- **Expect:** the supplies come on in order ("pp3200 on" ... "avdd on"),
  "mclk on at 24576000 Hz", "powered up"; the regulator summary shows
  `vdda_uw` and `vddd_uw` enabled; gpp6-3 an output, high; gpp3-0 in
  function 2. `0x0016` and `0x0017` each answer; record the pair (the
  plan's guess is 0x03, 0x86 for an IMX386 [I]). Then "powered down" and
  every camera supply disabled.
- **Pass:** both reads answer with the same values on a second run, and the
  rails go off.
- **Stop:** an I2C error or timeout: the stage still powers down; check
  that 2.3 passed, that `vdda_uw`/`vddd_uw` report status `on`
  (`/sys/class/regulator/*/status`, from the SLG51002's own VOUT_OK flag),
  and stop. A supply fails to enable: everything already on is turned off
  in reverse; record which one. Any SLG51002 over-current status: stop.
- **Rollback:** `tools/camera-stage off`, reboot; images without
  camera-pwr-test.
- **Afterwards:** record the model ID in section 1.1 (settles the
  ultrawide's part), then the same for the front, tele and main cameras
  (new test nodes on buses 2, 4, 1 with their own stock sequences), each
  its own boot.

### CAM3b: the ultrawide streams to the CSIS link, no DMA. Risk: medium

Needs CAM2 and CAM3a passed (chip ID 0x0386 read with the bring-up
driver). From here on the bring-up nodes of `camera-pwr-test` are replaced
by the real sensor node: never apply `camera-pwr-test` and a
`camera-stream-*` overlay together. Same PMIC backup check as CAM2 first.

```sh
# CAM3b.0 (laptop, once) the sensor data file, from your own image's
#   camera HAL APEX (vendor partition, apex/com.google.pixel.camera.hal.apex;
#   tools/extract-vendor-firmware unpacks the vendor image)
python3 -m venv ~/.cache/omamobile-venv && ~/.cache/omamobile-venv/bin/pip install unicorn pyelftools
~/.cache/omamobile-venv/bin/python tools/extract-camera-data --apex <path>/com.google.pixel.camera.hal.apex -o ~/android/reference/imx386-uw.bin
#   expect: init 139 writes; modes 4032x3016 (30 fps), 4032x2272, 2016x1508,
#   2016x1136 (60 fps); never commit the file
tools/phone-ssh 'mkdir -p /usr/lib/firmware/omamobile/camera && cat > /usr/lib/firmware/omamobile/camera/imx386-uw.bin' < ~/android/reference/imx386-uw.bin
# CAM3b.K kernel with the capture drivers (head 35295a9ab or int after the
#   merge) and the blacklist for the three new modules until
#   omamobile-device-cheetah ships them (ASK FIRST: flashes and reboots)
printf 'blacklist imx386\nblacklist phy_gs201_mipi_dcphy_rx\nblacklist gs201_csis\n' |
  tools/phone-ssh 'cat > /etc/modprobe.d/omamobile-camera-capture-bringup.conf'
ov <the overlays the phone runs now> camera-stream-link1 && bin/omamobile push
# CAM3b.1 (this boot) the sensor driver: powers the module in stock's order,
#   reads the ID, powers off again
tools/phone-ssh 'modprobe gpio_s2mpg13; modprobe slg51002_regulator; sleep 1; modprobe imx386; sleep 2; dmesg | grep -iE "imx386|slg51002" | tail'
#   expect: no error; /sys/bus/i2c/drivers/imx386/*-001a bound;
#   the camera supplies off again in the regulator summary
# CAM3b.2 (next boot) PHY and CSIS drivers bound, nothing started
tools/phone-ssh 'for m in gpio_s2mpg13 slg51002_regulator imx386 phy_gs201_mipi_dcphy_rx gs201_csis; do modprobe $m; sleep 1; done; dmesg | grep -iE "gs201-csis|dcphy" | tail; media-ctl -d /dev/media0 -p'
#   expect: "link 1 -> WDMA context 1, 4 data lanes"; graph imx386 0-001a ->
#   gs201-csis link 1 -> gs201-csis-wdma1; PMU 0x3ebc still 0 (gs201_cam_probe step=pmu)
# CAM3b.3 (corrected, 2026-10-12) colour bars on the link, no DMA. Needs the
#   kernel with 38355918e and the overlays from repo main (each
#   camera-stream overlay now also disables the other link). Link 0 first:
ov <the overlays the phone runs now> camera-stream-link0 && bin/omamobile push   # ASK FIRST
tools/phone-ssh 'for n in 1a440000 1a450000; do printf "%s %s\n" $n "$(tr -d "\0" < /sys/firmware/devicetree/base/soc@0/csis@$n/status)"; done'
#   expect: 1a440000 okay, 1a450000 disabled (exactly one link)
tools/camera-stage --watchdog x --cmd 'LINK=0 DMA=0 bash -s' --script tools/camera-cap-test
#   then, next boot, the same with camera-stream-link1 and LINK=1
```

- **Expect (3b.3):** `cap-test: media ...; sensor->CSIS links: 1`; both
  pads and the video node at 2016x1508 SRGGB10 / `pRAA`, 2528 bytes per
  line; then, in order, the driver's own lines: `dcphy ... link N: 4
  lanes at 1548288000 bps, settle 7; PMU 0x3ebc = 0x1` (isolation
  released), `imx386 0-001a: streaming 2016x1508: mode_select 1,
  frame_count a -> b`, `gs201-csis ...: link N on: ...` and, after the
  stream, `link N off: FRM_CNT ... SRC0/1 ... FS/FE ...` and `stopped: FS
  ... FE ...`.
- **Pass:** the CSIS frame counter (`FRM_CNT`) and `frame_start`/
  `frame_end` rise by about 60 a second, link errors 0, `wdma_done` 0. That
  link is the ultrawide's.
- **Reading a failure** (which part is silent):
  - `frame_count` doesn't move or `mode_select` isn't 1: the sensor isn't
    streaming (data file, MCLK rate in the same line, its power);
  - PMU 0x3ebc still 0 or GNR_CON0 not 1: the PHY never came up;
  - sensor counting, PHY up, `FRM_CNT` 0 and SRC0/SRC1/FS/FE all 0: no
    data reaches this link: the other link is the right one (or lanes);
  - `FRM_CNT` rising but `link_irqs` 0: frames arrive but the interrupt
    mask sense or routing is wrong: still a pass for the link question;
  - SRC0 bits (SOT, CRC, ECC): wrong PHY settings or settle: stop, don't
    try DMA;
  - `EPIPE` at stream on: the `invalid` / `differs` line names the pads.
- **Stop:** any hang (the watchdog resets; save pstore), or errors on both
  links.
- **Rollback:** `rmmod gs201_csis imx386` (powers the module down), reboot;
  images without the overlay.

**CAM3b.2/3b.3 results so far (2026-10-12).** On 3cb70218b
(camera 35295a9ab), `camera-stream-link1`: **3b.2 passed**: the PHY and
CSIS bound ("link 1 -> WDMA context 1, 4 data lanes"), camera pool
assigned, graph `imx386 0-001a` -> `gs201-csis link 1` ->
`gs201-csis-wdma1` (`/dev/video0`), DC-PHY still isolated afterwards.
**3b.3 inconclusive:**
- On link 1 the runbook's media-ctl quoting didn't reach the sensor pad,
  which stayed at its default 2016x1136 (then the smallest mode; now the
  largest), so stream-on failed with EPIPE (pads differ). At 2016x1136 on
  every pad the stream started and stopped with FS 0, FE 0, no link
  errors, no WDMA activity: link 1 saw nothing, but the sensor, PHY and
  frame-counter state weren't logged then, so this doesn't yet say "wrong
  link".
- On link 0 (32c474a89, with the PM fix: "imx386 0-001a: model 0x0386",
  no underflow) both CSIS nodes probed, so an earlier link 1 overlay was
  still in the DTB, and the sensor got two media links into link 0 (the
  notifier walked all of the sensor's endpoints). Stream-on gave EPIPE.
- Fixed in 38355918e (one link per CSIS, data type from the sink format,
  diagnostics) and in the overlays (each disables the other link);
  `tools/camera-cap-test` replaces the hand-quoted commands.

**CAM3b.3 result (2026-10-12, 7.3.0-rc6-omamobile-push1-00365-g23c2869425ea:
int with 38355918e; `camera-stream-link0`, then `-link1`, the other link
disabled each time; `camera-cap-test LINK=N DMA=0`; logs
`logs/cam3b3-c.out`, `logs/cam3b3-l1c.out`, private): the sensor streams,
neither link receives anything.** Both runs alike: one sensor->CSIS link;
`dcphy: link N: 4 lanes at 1548288000 bps, settle 7; PMU 0x3ebc = 0x1,
clock lane GNR_CON0 0x3` (isolation released); `imx386: streaming
2016x1508: mode_select 1, frame_count 255 -> 6 in 100 ms, mclk 24576000 Hz`
and 53/48 at stop (about 60 fps); `link N on: ... CMN_CTRL 0x00004f01
PHY_CMN 0x1f INT_MSK0/1 0x00fff07f/0x7e`; at stop `FRM_CNT 0`, every
source 0, no link interrupt, no errors. Wi-Fi fine across the boots.

**Why (offline, second RE follow-up):** the stock camera software's last
start step is missing from ours: after configuring the PHY, the routing,
the DMA and the link, it sets the link's bit in CSIS sysreg 0x500
(`0x1a420500`, the register Google's GPL DT calls the per-PHY reset, which
no GPL driver writes) and clears it at stop. It never reads or polls a PHY
or link status while starting, and writes nothing else outside what we
already write (in D-PHY mode only the bias word outside the lane windows;
in the link only the RE2 list and the second interrupt mask). It also sets
a bit in sysreg 0x488 (link + 8 x PDP channel; with no PDP the code gives
link + 24, unconfirmed for a RAW-only stream). Added in `f32305542`: the
reset release (on by default, `link_reset_release=0` to leave it out), the
0x488 bit as an experiment (`sysreg_link_sel=1`), both registers logged at
stream on; and in `15e8541d3` a debugfs `scan` of all eight links and the
sysreg routing page and a dump of the PHY's lane registers, which
`camera-cap-test` prints mid-stream. Which link the ultrawide is on is
still not known statically; a stock logcat while the camera opens prints
it ("Camera ID ..., CSIS LINK ..."), but that needs a slot A boot (the
human's go, and a fresh partition backup after it).

### CAM3b.4: link reset released, then the 0x488 bit. Risk: medium (no DMA)

**Superseded (2026-10-13) by CAM3b.5; don't run.** The ultrawide isn't on
link 0 or 1 (section 4.4), and `link_reset_release` no longer exists: the
PHY driver releases the slave reset before programming the lanes.

Kernel from `f32305542` (or int after the merge). One run per boot, link 0
first, stop at the first pass:

```sh
# CAM3b.4a link 0 with the reset released (the new default)
ov <the overlays the phone runs now> camera-stream-link0 && bin/omamobile push   # ASK FIRST
tools/camera-stage --watchdog x --cmd 'LINK=0 DMA=0 bash -s' --script tools/camera-cap-test
# CAM3b.4b the same on link 1 (camera-stream-link1, LINK=1)
# CAM3b.4c only if neither counted: link 0 again with the 0x488 bit as well
tools/camera-stage --watchdog x --cmd 'LINK=0 DMA=0 CSIS_OPTS=sysreg_link_sel=1 bash -s' --script tools/camera-cap-test
# CAM3b.4d the same on link 1
```

- **Expect:** `sysreg 0x488 = ..., 0x500 = ... before start` (record both:
  ABL's values), then `... after start` with bit N of 0x500 set; the
  mid-stream `scan` shows this link's `FRM_CNT` and the other seven links;
  the PHY `regs` dump shows the clock and four data lanes with
  `GNR_CON0` = 1 or 3.
- **Pass:** this link's `FRM_CNT` and `frame_start`/`frame_end` rising
  (about 60/s) with no errors: that's the ultrawide's link, and CAM4 can
  follow on it.
- **Also useful if it fails:** whether `SRC0` now shows errors (data
  arrives but the PHY settings or lane order are wrong: stop before DMA),
  and whether any other link's `FRM_CNT` in the scan moved.
- **Stop:** link errors that keep coming, any hang (watchdog, pstore),
  anything odd on the other camera blocks.
- **Rollback:** reboot (the bit is cleared at stop and lost at reset);
  `link_reset_release=0` restores the CAM3b.3 behaviour.

### CAM3b.5: link 2 with the PHY pair 2+3 sees the sensor. Risk: medium (no DMA)

Goal: **link 2 sees frames.** Kernel `omamobile-camera` `3390774a8` (the
human merges it into int, or pushes the `out-camera` build), overlay
`camera-stream-link2` **instead of** `camera-stream-link0/1`; never with
`camera-pwr-test`. The blacklist from CAM3b.K stays. PMIC backup check as
CAM2 first. One change per boot: 5.1/5a without any DVFS vote, 5b adds
the CAM vote.

```sh
# CAM3b.5K (laptop) images with the link 2 overlay (ASK FIRST: flashes, reboots)
ov <the overlays the phone runs now, without camera-stream-link0/1> camera-stream-link2 && bin/omamobile push
tools/phone-ssh 'uname -r; cat /etc/modprobe.d/omamobile-camera-capture-bringup.conf'
#   expect: the new release; blacklist imx386, phy_gs201_mipi_dcphy_rx, gs201_csis
# CAM3b.5.1 (read-only) one link in the DT, the drivers bind, the DVFS rates
tools/phone-ssh 'for n in 1a440000 1a450000 1a460000; do printf "%s %s\n" $n "$(tr -d "\0" < /sys/firmware/devicetree/base/soc@0/csis@$n/status)"; done'
#   expect: 1a440000 disabled, 1a450000 disabled, 1a460000 okay
tools/phone-ssh 'for m in gpio_s2mpg13 slg51002_regulator imx386 phy_gs201_mipi_dcphy_rx gs201_csis; do modprobe $m; sleep 1; done; dmesg | grep -iE "gs201-csis|dcphy" | tail -5; media-ctl -d /dev/media0 -p | grep -E "entity|->"'
#   expect: "link 2 -> WDMA context 0, 4 data lanes"; imx386 0-001a -> "gs201-csis link 2" -> gs201-csis-wdma0
tools/phone-ssh 'mount -t debugfs none /sys/kernel/debug 2>/dev/null; for c in cam int intcam; do echo "$c $(cat /sys/kernel/debug/clk/$c/clk_rate)"; done'
#   expect: cam about 67000000, int about 200000000 (FREQ_GET only, nothing set)
# CAM3b.5a (same boot) colour bars on link 2, no DMA, no DVFS vote
tools/camera-stage --watchdog x --cmd 'LINK=2 DMA=0 CSIS_OPTS="cam_khz=0 int_khz=0" bash -s' --script tools/camera-cap-test
# CAM3b.5b (next boot; only after 5a passed or showed data with errors)
#   the CAM DVFS vote at 400 MHz (the driver's default), still no DMA
tools/camera-stage --watchdog x --cmd 'LINK=2 DMA=0 CSIS_OPTS="int_khz=0" bash -s' --script tools/camera-cap-test
tools/phone-ssh 'cat /sys/kernel/debug/clk/cam/clk_rate'
#   expect: back at the boot rate after the stop
```

- **Expect (5a):** `cap-test: media ...: 'imx386 0-001a' -> 'gs201-csis
  link 2' -> /dev/videoN; sensor->CSIS links: 1`; bytes per line **2560**;
  `sysreg 0x488 = ..., 0x500 = ... before start` (record both: ABL's
  values); `dcphy ...: link 2: 4 lanes (with the next link's) at
  1548288000 bps, settle 7; PMU 0x3ebc = 0x1, reset 0x...` with **bits 2
  and 3 set**, `clock lane GNR_CON0 0x1` (or 3), `bias ...` (record
  `CON0-4`); `imx386 0-001a: streaming 2016x1508: mode_select 1,
  frame_count a -> b`; `link 2 on: ... CAM 67... Hz`; mid-stream the
  `stats` and `scan` (link 2's `FRM_CNT`, all eight links) and the PHY
  `regs` (link 2 clock and d0-d3, d2/d3 at `0x2600`/`0x2700`); at stop
  `link 2 off: FRM_CNT ...` and `stopped: FS ... FE ...`, `0x500` back
  without bits 2 and 3.
- **Pass (5a):** link 2's `FRM_CNT` or `frame_start`/`frame_end` rising,
  about 60/s. **Errors are allowed here**: at 67 MHz ECC/CRC (INT0) and
  `ERR_OVER` or resolution mismatches (INT1 bits 5-6) are what the
  slow clock is expected to cause; they still prove the data reaches
  link 2. Record `last_link_err`.
- **Pass (5b):** `link 2 on: ... CAM 400000000 Hz`; `FRM_CNT` and
  `frame_start`/`frame_end` rising together at about 60/s, `link_errors`
  0; the CAM rate back at its boot value after the stop. Then CAM4 can
  follow on link 2.
- **Reading a failure:**
  - nothing at all (`FRM_CNT`, SRC0/1, FS/FE 0) with bits 2+3 set and the
    sensor counting: compare the PHY `regs` dump with the values the
    driver writes (lanes enabled?); then the bias `CON0-3` difference
    (section 4.4) is the next single change, on its own boot;
  - SOT/SOT-sync bits (INT0 16-23) at 400 MHz: PHY settings or settle;
    stop, no DMA;
  - `link 2: link 3 is in use` or `-EBUSY`: something else powered link 3
    (shouldn't exist); stop;
  - 5b: `CAM DVFS to 400000 kHz: <err>` or an ACPM timeout in dmesg: the
    first CAM DVFS request on our kernel failed; stop, stay on
    `cam_khz=0`, look at `ACPM-PLAN.md`.
- **Stop:** any hang (the watchdog resets; save pstore with
  `tools/camera-stage --pstore`), the bus hanging at the first lane access
  (= the reset wasn't released: don't retry), errors that don't drop at
  400 MHz, anything odd on the other camera blocks or the display.
- **Rollback:** reboot (the PHY reset bits are cleared at stop and lost at
  reset; DVFS rates restored at stop and reset at reboot); images without
  `camera-stream-link2`. `cam_khz=0` removes the vote.

**CAM3b.5 results (2026-10-13):**
- **5.1 (7.3.0-rc6-omamobile-push1-00383-gcc41390828d0): passed.** Only
  `csis@1a460000` is okay. "link 2 -> WDMA context 0, 4 data lanes". The
  sensor first deferred on the S2MPG13 GPIO supplier: load `sec_acpm` by
  hand (blacklisted at boot) before `gpio_s2mpg13`. After that the IMX386
  probed (model 0x0386) and the graph is imx386 0-001a -> "gs201-csis
  link 2" -> gs201-csis-wdma0. Rates cam 67 MHz, int 200 MHz, intcam 67 MHz.
- **5a (same boot): data reaches link 2 (passed), then a crash.**
  - 0x500 was 0 before start and 0xc after (bits 2+3, the PHY pair).
  - The PHY line read "4 lanes (with the next link's) at 1548288000 bps,
    settle 7; PMU 0x3ebc = 0x1", with bias CON0-3 all 0 and CON4 0x200.
  - Mid-stream, frame_start was 267654 and link_errors 266903 (last
    0x40000011: ERR_ID, ERR_OVER, plus INT1 bits), which is per-line errors
    at 67 MHz, as expected.
  - Then debugfs `scan` took a synchronous external abort in
    `regmap_read` on the CSIS sysreg (it read every word from 0x400 to
    0x50c). The reader exited with preemption disabled and the phone froze
    about two minutes later. Fix `f9cbc3f50`: scan reads only the sysreg
    registers the driver programs, and no longer walks the other links.
- **5b (7.3.0-rc6-omamobile-push1-00385-ga535168af42b, CAM vote 400 MHz):
  frames arrive at 60 fps.**
  - "CAM 400000000 Hz" at link on; the rate was back at 67 MHz after stop.
  - FRM_CNT went 0x9 -> 0x127 in about 4.8 s: 286 frames, 60 fps.
  - link_errors 294, about one per frame, last 0x8 = INT0 ERR_WRONG_CONFIG
    (bit names from Google's GPL gs201 LWIS bindings). This is most likely
    the sensor's embedded-data lines arriving in a data type the channel
    isn't set up for. Check it at CAM4: if the frame is complete, ignore
    it or mask it.
  - **An interrupt storm:** 817794 link interrupts for 286 frames, with FS/FE
    0x1/0x1 still set at stop. The per-VC FS/FE sources were never cleared,
    so INT1's summary refired. Fix `39afbe857`.
  - The scan with the fix read safely. The sysreg routing registers
    (0x408-0x410, 0x430) read 0 with DMA off, as expected (they're set only
    with DMA on).
  - Next: CAM4 on a kernel with `39afbe857`. Expect about 60 link
    interrupts a second.

### CAM4: the CSIS WDMA writes frames. Risk: high (first DMA)

The WDMA writes to the buffer address it is given, with its SysMMU in
bypass: a wrong route or a misread address field writes memory we don't
own. So: the test pattern first, at the smallest mode, into the camera
pool only (the driver refuses buffers above 4 GiB), with the watchdog and
the log stream on, and nothing else running that matters.

Only after CAM3b.5b passed (link 2 clean at CAM 400 MHz). Same kernel and
overlay. Link 2 feeds **WDMA context 0, channel 0** (`csis2`), routed by
`0x430` = 2 and `SC_CON0-2` = 1 with the EBUF bypassed (section 4.4), all
restored at stop.

```sh
# CAM4.0 (laptop) the camera pool really is below 4 GiB on this boot
tools/phone-ssh 'dmesg | grep -i "camera-pool\|camera_pool"'
#   expect: a reserved 64 MiB region inside 0x80000000-0xffffffff
# CAM4.1 (next boot) colour bars through the WDMA: channel 0, CAM vote on,
#   no INT vote yet (one change: the DMA and its routing)
tools/camera-stage --watchdog x --cmd 'LINK=2 DMA=1 CH=0 FRAMES=4 CSIS_OPTS="int_khz=0" bash -s' --script tools/camera-cap-test
tools/phone-ssh 'cat /tmp/cam-2016x1508.raw' > logs/cam4-bars.raw
# CAM4.2 (next boot) the same with the INT vote (the driver's default)
tools/camera-stage --watchdog x --cmd 'LINK=2 DMA=1 CH=0 FRAMES=4 bash -s' --script tools/camera-cap-test
# CAM4.3 a real picture: PATTERN=0 (then 4032x3016 at 30 fps, W=4032 H=3016)
```

- **Pass (4.1):** `wdma_done` = 4, `wdma_errors` 0, the file is exactly
  4 x 2560 x 1508 = 15 441 920 bytes; unpacked on the laptop (MIPI RAW10,
  2560-byte lines) it shows eight vertical colour bars (a small python
  unpacker into a PNG; no debayer needed for bars).
- **Not routed:** `wdma_done` 0, no WDMA errors, link counters running:
  the routing didn't take (read `sysreg+0x408..0x410` and `+0x430` in the
  `scan` output while streaming); stop and look before another variant.
- **Syncs but no data** (`LASTDATA`/`LASTADDR` errors, frame start and end
  on time): `SC_CON0-2` still 0 or the EBUF not bypassed: stop.
- **Stop:** `LASTADDR`/`LASTDATA`/`FIFO_FULL` errors, a picture shifted or
  torn, or anything else misbehaving after the run (a write landed
  elsewhere): stop and reboot at once, don't retry before the address
  format is understood. A hang: watchdog, pstore.
- **Rollback:** reboot (DMA stops with the module); images without the
  overlay.

**CAM3b.5b, CAM4.1 and CAM4.3 results (2026-10-13, int
`7.3.0-rc6-omamobile-push1-00395-g6c0e876bd580`: the link 2 work plus
`f9cbc3f50` (scan reads only the programmed sysreg registers) and
`39afbe857` (clear the per-VC FS/FE sources, which ended an interrupt
storm); `camera-stream-link2`):**

- **CAM3b.5b passed:** 60 fps on link 2 at CAM 400 MHz, with about one
  `ERR_WRONG_CONFIG` (INT0 bit 3) per frame (open: probably the parked
  channels or the data type of the sensor's embedded lines; not fatal).
- **CAM4.1 passed (first DMA):** `LINK=2 DMA=1 CH=0 FRAMES=4
  CSIS_OPTS=int_khz=0`, `PATTERN=2`: `wdma_done` 5, `wdma_errors` 0, file
  15 441 920 bytes (4 x 2560 x 1508: the 64-byte stride is right); frames
  1-3 bit-identical, frame 0 empty (2 dropped at start). The bars switch at
  exact eighths of the line. Per-position MSB means over the eight bars
  (1 = 255, 0 = 0): row 100 even columns `1 1 1 1 0 0 0 0`, odd columns
  all 1; row 101 even columns all 1, odd columns `1 1 0 0 1 1 0 0`.
- **CAM4.3: first real image.** `PATTERN=0`, held up at the ceiling,
  exposure 1700, `analogue_gain` 240: ceiling lamps with their glow and a
  fixture; MSB p1 15, p50 16, p99 23, so the lit room sits at the black
  level and only the lamps register (the first run looked all black
  because the phone lay camera-down). All the ultrawide rails were on at
  their voltages mid-stream.

**Reading the bars (offline, 2026-10-13).** The CCS colour bars are white,
yellow, cyan, green, magenta, red, blue, black, so per channel R = `1 1 0
0 1 1 0 0`, G = `1 1 1 1 0 0 0 0`, B = `1 0 1 0 1 0 1 0`. Row 100 even shows
G and row 101 odd shows R, but those two positions are diagonal in the 2x2
cell, where a Bayer sensor has either both greens or red and blue; and no
position shows the B pattern while two are saturated throughout. So the
data doesn't fit any of the four Bayer orders with the standard bars:
either this sensor's bars differ in the binned mode or the analysis
indexed the packed bytes differently. **Bayer order not settled;
SRGGB10 stays [I].** CAM4.3b reads it directly with the solid colour
pattern (one value per channel).

**Why so dim (offline, 2026-10-13).**
- Writes do reach the sensor in the right order: the driver writes the
  init and mode lists (which set 0x0202 = 1779, 0x0204 = 0, frame length
  1799 for 2016x1508), then `__v4l2_ctrl_handler_setup()` writes every
  control, then mode_select. Controls set before streaming are only stored
  (the sensor is off) and written there, so the mode list doesn't
  overwrite them. Neither list uses the group hold (0x0104). Not yet
  proven by a readback: `ddf414774` logs frame length, exposure,
  analogue and digital gain and the test pattern as the sensor reads
  them back after mode_select.
- **The analogue gain model is the open question.** The control range
  0-480 is our extraction tool's guess [I]. Two Sony models are in use
  for sensors of this family: gain = 512 / (512 - code) (0-480 = 1x-16x)
  and gain = 1024 / (1024 - code) (0-960 = 1x-16x). Code 240 is 1.88x in
  the first and 1.31x in the second; either way the test ran at under 2x
  analogue gain and 16 ms (60 fps), where stock indoors runs about 33 ms
  and several times the gain. So "dim" is expected even with everything
  right, and only a sweep at a fixed scene tells the model (CAM4.3b).
- The digital gain control wrote only the Gr channel's gain (0x020e); the
  mode lists set all four (0x020e-0x0215) to 1.0. Fixed in `ddf414774`
  (all four). Not a cause of the dim picture (the control was left at 1.0).
- **Black level: 64 in 10 bits** (p1 15 x 4 + LSBs, the floor of the
  real image at MSB 15-16), as expected for this kind of sensor.

### CAM4.3b: Bayer order, control readback and the gain model. Risk: medium (DMA as in CAM4.1)

Kernel with `ddf414774` (the human merges `omamobile-camera` into int);
the same overlay and module options as CAM4.1 (CAM vote, `int_khz=0`).
Prop the phone so the camera sees the same lit scene for every run (not a
lamp straight on), the room lights constant. Laptop side,
`tools/raw10-stats` (plain Python, reads the file only).

```sh
# 4.3b-1 Bayer order: solid colour, a different value per channel
tools/camera-stage --watchdog x --cmd 'LINK=2 DMA=1 CH=0 FRAMES=4 CSIS_OPTS=int_khz=0 PATTERN=1 CTRLS="red_pixel_value=256,green_red_pixel_value=512,blue_pixel_value=768,green_blue_pixel_value=1000" bash -s' --script tools/camera-cap-test
tools/phone-ssh 'cat /tmp/cam-2016x1508.raw' > logs/cam4-solid.raw
tools/raw10-stats logs/cam4-solid.raw
#   expect: each of the four positions flat at one of 256/512/768/1000:
#   row 0 col 0 = R -> RGGB, = Gr -> GRBG, = Gb -> GBRG, = B -> BGGR
#   (and the bars file again: tools/raw10-stats logs/cam4-bars.raw --bars 8)
# 4.3b-2 the readback: the same run's dmesg line
#   "imx386 0-001a: streaming 2016x1508: ... frame_length 1799, exposure E,
#   analogue gain G, digital gain 0x100, test pattern P" = the values set
# 4.3b-3 gain model: one run each, same scene, exposure 1700, PATTERN=0
for g in 0 120 240 360 480; do
  tools/camera-stage --watchdog x --cmd "LINK=2 DMA=1 CH=0 FRAMES=4 CSIS_OPTS=int_khz=0 PATTERN=0 CTRLS=exposure=1700,analogue_gain=$g bash -s" --script tools/camera-cap-test
  tools/phone-ssh 'cat /tmp/cam-2016x1508.raw' > logs/cam4-gain$g.raw
  tools/raw10-stats logs/cam4-gain$g.raw
done
# 4.3b-4 exposure is linear: analogue_gain 0, exposure 400, 800, 1600 (same scene)
# 4.3b-5 a brighter picture: 30 fps, the longest exposure, the top gain code
#   CTRLS="vblank=2090;exposure=3580,analogue_gain=480"
```

- **Pass (4.3b-1):** four flat positions with the four values; record
  the Bayer order. If it isn't RGGB, the data file header's `bayer` field
  is what changes (`tools/extract-camera-data`; the kernel takes the code
  from the file).
- **Pass (4.3b-2):** the readback equals the controls' values that
  `camera-cap-test` prints before streaming (`v4l2-ctl -l`).
- **Reading 4.3b-3** (signal = the green positions' p50 minus 64): at a
  fixed exposure the ratio to the code-0 run is the gain. 512 / (512 -
  code): 1.31x at 120, 1.88x at 240, 3.37x at 360, 16x at 480. 1024 /
  (1024 - code): 1.13x, 1.31x, 1.54x, 1.88x. Record the model; it sets
  the control's range (960 for the second model) and the libcamera helper.
- **Pass (4.3b-5):** the room visible above the black level.
- **Stop:** as CAM4.1 (any WDMA error, a torn or shifted frame, a hang);
  a readback that differs from what was set (a control isn't reaching the
  sensor: look before another run).
- **Rollback:** reboot; `PATTERN=2` and no `CTRLS` is CAM4.1 again.

**CAM4.3b results (2026-10-13, int
`7.3.0-rc6-omamobile-push1-00397-g94d7b3c9ae7f`, with `ddf414774`):**

- **4.3b-1 passed: the Bayer order is RGGB** (`SRGGB10`, as the driver
  reports). Solid colour R 256, Gr 512, B 768, Gb 1000 read back flat as
  row 0 col 0 = 64, row 0 col 1 = 128, row 1 col 0 = 250, row 1 col 1 =
  192, so R Gr / Gb B. Every value arrives divided by 4: the test data
  registers take the sensor's internal 12-bit scale (`49a0a54f4` widens
  the controls to 4095).
- **4.3b-2 passed:** the readback after mode_select matches the controls:
  `frame_length 1799, exposure 1549, analogue gain 0, digital gain 0x100,
  test pattern 1` with the defaults, and each sweep step's gain.
- **4.3b-3 invalid:** the phone fell over during the sweep, so the scene
  changed between steps. The gain-480 run had **`wdma_errors` 33,
  `last_wdma_err` 0x4000 (`LASTDATA`)**; all other DMA runs so far 0.
- **Retake, phone held facing the room:** exposure 1789, analogue gain
  360, `PATTERN=0`: `wdma_errors` 0; debayered as RGGB the frame is a
  sharp, correctly coloured, in-focus picture of the room, rotated (the DT
  now says `rotation = <90>`, `905599c28`). **Still very dark:** green p50
  2 codes above black (64), p99.5 19 above black with the lamps left out;
  it needed about 13x stretch.

**Why dark (offline).** The register writes are proven by the readback,
so what is left is how much gain and exposure they mean:
- At 16 ms (the binned modes' own 60 fps frame) and code 360, the
  sensor ran at about 1.5x (1024 model) or 3.4x (512 model) analogue
  gain. Stock indoors runs about 33 ms and roughly 8-16x (the ISO a
  phone uses indoors). So a dark frame is partly just exposure: 2x from
  the frame time, 3-10x from gain.
- **The gain model decides the rest.** If it is 1024 / (1024 - code),
  our control stops at 480 = 1.9x and the sensor's upper 8x of gain is
  unreachable. Another bring-up on this phone model runs this sensor with
  codes up to 960 (0x380 for "8x") and gets bright frames, which points
  that way [I]. `49a0a54f4` adds `imx386 again_max=` to open the range
  for the sweep, and defaults VBLANK to a 30 fps frame (exposure up to
  33 ms), since libcamera's simple pipeline never raises VBLANK itself.
- Nothing in the init or mode lists points at a shortened integration:
  they set 0x0202 = 1779 of 1799 lines, no HDR or short-exposure
  registers (0x0220-0x0225 aren't written), and the extra writes of the
  phase-detection init variant (73, all 0x3108-0x3165) are only
  phase-detection windows.

**The LASTDATA errors (offline).** The WDMA's last-data check compares
how much data a frame brought with what the context expects; with RAW10
and a fixed size, the amount doesn't depend on the picture or the gain.
What did differ in that run: the phone fell over (screen and rotation
activity on the same bus), and every DMA run so far used `int_khz=0`, the
bus (INT) domain at its boot level, where the WDMA is known to miss frame
ends under load (section 4.4). Most likely a bus-bandwidth stall, not
the gain. The next runs use the INT vote (CAM4.2, never run yet) and
repeat high gain to check; the per-frame `ERR_WRONG_CONFIG` on the link
(likely the sensor's embedded-data lines arriving with a data type the
link isn't set up for) is recorded alongside in case the two coincide.

**Autofocus:** the ultrawide has an AF actuator (an AK737x-type VCM at
0x0f on the same bus, stock `act-slenderman-sandworm`, on LDO12S plus
SLG51002 LDO4 2.9 V). Not needed now (the lens rests at a usable
focus); a later stage for macro.

### CAM4.3c: INT vote, the gain model and 30 fps, phone secured. Risk: medium (DMA)

Kernel `omamobile-camera` `49a0a54f4` merged into int (the human), same
overlay. **The phone fixed in a stand or taped, facing the same lit room,
screen off or untouched, room lights constant for the whole step.**
CAM4.3b's stop for DMA runs is lifted only for 4.3c-1 below.

```sh
# 4.3c-1 (next boot) CAM4.2: the INT vote (default), colour bars, 3 runs
for i in 1 2 3; do
  tools/camera-stage --watchdog x --cmd 'LINK=2 DMA=1 CH=0 FRAMES=8 SECS=6 bash -s' --script tools/camera-cap-test
done
#   pass: wdma_errors 0 in all three; dmesg "link 2 on: ... INT 400000000 Hz"
# 4.3c-2 the frame rate default: no CTRLS, PATTERN=0
tools/camera-stage --watchdog x --cmd 'LINK=2 DMA=1 CH=0 FRAMES=4 PATTERN=0 bash -s' --script tools/camera-cap-test
#   expect: vblank 2091 in the control list, frame_length 3599 in the readback,
#   FS rising at about 30/s
# 4.3c-3 the gain sweep at a fixed exposure: 30 fps, exposure 3000, range open
for g in 0 240 480 720 960; do
  tools/camera-stage --watchdog x --cmd "LINK=2 DMA=1 CH=0 FRAMES=4 PATTERN=0 SENSOR_OPTS=again_max=960 CTRLS=exposure=3000,analogue_gain=$g bash -s" --script tools/camera-cap-test
  tools/phone-ssh 'cat /tmp/cam-2016x1508.raw' > logs/cam4c-gain$g.raw
  tools/raw10-stats logs/cam4c-gain$g.raw
done
# 4.3c-4 exposure linearity at code 0: exposure 750, 1500, 3000
```

- **Reading 4.3c-3** (green mean minus 64, against code 0): 1024 / (1024 -
  code) gives 1.31x at 240, 1.88x at 480, 3.37x at 720, 16x at 960; 512 /
  (512 - code) gives 1.88x at 240 and 16x at 480, with 720 and 960 outside
  its range (expect them clamped, saturated or ignored). If the 1024 model
  fits, the data file's range becomes 960 (`tools/extract-camera-data`,
  regenerate and copy the file) and the libcamera helper uses it.
- **Pass:** 4.3c-1 clean three times; the sweep fits one model; at the top
  of the confirmed range and 33 ms the room is well above black.
- **Stop:** any `wdma_errors` with the INT vote on (record `stats` and the
  `scan`, compare `last_link_err`), a torn frame, a hang. With the 512
  model, don't run codes above 480 again.
- **Rollback:** reboot; no `SENSOR_OPTS` restores the 0-480 range.

### CAM5: libcamera. Risk: low (userspace)

```sh
# CAM5.0 (laptop) build packages/libcamera on the phone
tools/phone-install-package packages/libcamera
# CAM5.1 the camera is listed
tools/phone-ssh 'cam -l'
#   expect: one camera, "imx386 0-001a" (bus 3 is i2c-0 on our kernel, CAM2.3);
#   soft ISP created (log: SoftwareIsp)
# CAM5.2 one picture
tools/phone-ssh 'cam -c1 --capture=3 --file=/tmp/frame#.ppm --stream pixelformat=RGB888,width=2016,height=1508'
# CAM5.3 GNOME Snapshot through PipeWire; check with a screenshot
```

- **Pass:** a recognisable image (colours off is fine: no tuning yet).
- **Stop:** `cam -l` empty: check `media-ctl -p` and the libcamera log
  (`LIBCAMERA_LOG_LEVELS=SimplePipeline:0`).

**CAM5 readiness (2026-10-13).** What libcamera's simple pipeline and
software ISP need, and where it stands:
- media graph, formats, `V4L2_CAP_IO_MC`, the five sensor controls, a
  dma-buf heap: in place (CAM4.1 captured through the same nodes);
- **the Bayer order**: the sensor reports SRGGB10, unverified: CAM4.3b-1
  first, or the colours come out swapped;
- **black level**: 64 of 1023 (CAM4.3); without a sensor helper the soft
  ISP estimates it from the darkest pixels, which works for a first
  picture; a helper with `blackLevel_ = 4096` (16-bit scale) is better;
- **gain model**: without a helper libcamera treats the code as linear
  gain, so its AGC overshoots or crawls; a helper (`AnalogueGainLinear`
  with the model CAM4.3b-3 measures) goes into `packages/libcamera` as a
  second patch then, with `unitCellSize` 1.25 um only once there's a
  citable source;
- the mode: `cam` picks 2016x1508 at 60 fps (16 ms); for indoor light,
  libcamera's AGC raises gain but doesn't lengthen the frame (it never sets
  `VBLANK` in the simple pipeline), so indoor pictures will stay dark-ish
  until the default blanking gives 30 fps (a driver default, after
  CAM4.3b-5 shows the picture);
- `packages/libcamera` is still unbuilt (CAM5.0).
So CAM5.0-5.2 can run after CAM4.3b-1; CAM5.3 and an indoor-usable
picture wait for the gain model and the 30 fps default.

**CAM5.1/5.2 results (2026-10-13, int
`7.3.0-rc6-omamobile-push1-00405-g3bc8d8565645` with `49a0a54f4` and the
rotation; `packages/libcamera` 0.7.2-4.2):**
- **CAM5.1 passed:** `cam -l` lists "1: Internal back camera
  (/base/soc@0/usi@109200c0/i2c@10920000/camera-sensor@1a)". Warnings: no
  `imx386.yaml` (falls back to `uncalibrated.yaml`), "Unable to get
  rectangle 0 on pad 0/0" (no `get_selection` in the driver), "Failed to
  create camera sensor helper for imx386".
- **CAM5.2 failed:** `DmaBufAllocator: Unable to create buffer`, "Can't
  allocate buffers"; kernel `cma: ... reserved: alloc failed, req-size:
  3016 pages, ret: -16`. The software ISP takes its output buffers from
  the first heap of `linux,cma`, `reserved`, `system`; on our kernel
  `reserved` is the **default CMA area** (arm64 defconfig's 32 MiB, from
  `CONFIG_CMA_SIZE_MBYTES`; exported twice, as `reserved` and
  `default_cma_region`), too small for four 12 MiB RGB888 buffers next to
  its other users. (`camera-pool` and `display-pool` are the DT pools;
  this kernel has no `linux,cma` alias option.)

**Fixes (2026-10-13):**
- `kernel/configs/omamobile.config` (repo, uncommitted):
  `CONFIG_CMA_SIZE_MBYTES=192` (reusable; movable pages use it while the
  camera doesn't).
- `70da6c5a5` `media: i2c: imx386: report the pixel array and each mode's
  analogue crop`: `get_selection` with `CROP` (the mode's analogue crop,
  from its address registers), `NATIVE_SIZE`/`CROP_BOUNDS`/`CROP_DEFAULT`
  (4032x3016). Build `7.3.0-rc6-omamobile-push1-00357-g70da6c5a5b2f` in
  `out-camera` (with the config change).
- `packages/libcamera` 0.7.2-4.3 (repo, uncommitted):
  `0002-libcamera-Add-the-Sony-IMX386-sensor.patch`: the sensor helper
  (black level 4096 at 16 bits; the IMX258's gain model 512 / (512 -
  code) as a provisional choice until CAM4.3c), properties (1.25 um cell,
  test pattern numbers, two-frame delays) and an `imx386.yaml` tuning
  stub. Applies on 0.7.2 after the other two patches; not compiled yet.

### CAM5.2b: libcamera with the CMA area and the helper. Risk: low (userspace; kernel push)

```sh
# 5.2b-K kernel: omamobile-camera 70da6c5a5 merged into int, built with the
#   repo's config fragment (CMA 192 MiB) (ASK FIRST: flashes and reboots)
tools/phone-ssh 'grep -E "CmaTotal|CmaFree" /proc/meminfo; ls /dev/dma_heap'
#   expect: CmaTotal about 348 MiB (192 + 64 + 92; 188 before); heaps as before
# 5.2b-0 libcamera 0.7.2-4.3 (sensor helper, tuning stub)
tools/phone-install-package packages/libcamera
# 5.2b-1 the camera, without warnings about the helper, tuning or crop
tools/phone-ssh 'cam -l 2>&1 | grep -iE "warn|error|camera"'
# 5.2b-2 one picture (as CAM5.2)
tools/phone-ssh 'cam -c1 --capture=6 --file=/tmp/frame#.ppm --stream pixelformat=RGB888,width=2016,height=1508 2>&1 | tail -20'
tools/phone-ssh 'cat /tmp/frame000005.ppm' > logs/cam5-frame.ppm
```

- **Pass:** six frames written, no `cma` failure in dmesg; the last frame
  a recognisable, right-coloured picture (AGC settled: brighter than the
  raw captures, still noisy indoors).
- **If only the kernel changed:** CAM5.2 must already pass on 4.2 (the
  helper isn't needed to allocate); install 4.3 after.
- **Stop:** a `cma` failure again (read `CmaFree` and dmesg: someone else
  holds the area), any WDMA error, a hang.
- **Rollback:** `pacman -U` the 4.2 package; the old kernel images.

**CAM5.2b results (2026-10-13, int
`7.3.0-rc6-omamobile-push1-00407-g618475741fa7` with `70da6c5a5` and CMA
192 MiB: CmaTotal 356352 kB; libcamera 0.7.2-4.2, the helper package not
built yet):**
- **Allocation fixed:** no CMA failure.
- **Stream-on refused** with `gs201_csis` loaded by hand without
  `allow_stream=1` (QBUF/stream-on `EPERM`, "streaming disabled").
- With `allow_stream=1 link_only=0 wdma_channel=0`, `cam -c1 --capture=10
  ... width=2016,height=1508`: "Camera configuration adjusted", and the
  sensor and link ran **4032x3016** ("link 2 on: 4032x3016 DT 0x2b"); FS
  1795 / FE 1794, link errors 1794 (0x8, `ERR_WRONG_CONFIG`, as in every
  run), **WDMA done 0, errors 39, last 0x8000 (`LASTADDR`)**, no frame
  saved; vb2 "driver bug: stop_streaming operation is leaving buffer 0 in
  active state". No oops; rebooted per the runbook.

**Why (offline, 2026-10-13):**
- **4032x3016 was libcamera's choice, not a bug:** the software ISP's
  debayer keeps a border, so its largest output from a W x H Bayer input
  is (W - 2 x 4) x H for packed RAW10 (`DebayerCpu::sizes()`: pattern
  width 4, no top/bottom border for a 2-line pattern). From the binned
  2016x1508 mode that is 2008x1508, so a 2016x1508 request only fits the
  full mode. Ask for **2008x1508** (or less) to get the 60/30 fps binned
  mode; 1920x1080 picks 2016x1136.
- **The buffer leak** was ours: at a frame start the driver made the next
  buffer active and dropped the previous one when its frame end hadn't
  come. `35f679a26` completes such a buffer with an error (`missed_fe`).
- **LASTADDR at 4032x3016** is open. Our only full-resolution DMA so far
  (CAM4 ran 2016x1508 only). Differences that grow with the mode: the
  line stride 5056 bytes (64-aligned; 2560 at 2016 pixels is a multiple of
  512, 5056 is not), and stock's channel start value 0xf83 whose bits
  11:7 (= 31) are not understood, against 0x3 that another bring-up uses
  at this resolution. `35f679a26` logs the WDMA channel registers and the
  format at a stream's first WDMA error, and adds `stride_align=` and
  `wdma_ctrl=` to try one change per run.
- **`allow_stream`:** the gate has done its job (raw frames and libcamera
  both ran); `35f679a26` makes streaming the default. The bring-up gate is
  the camera modules' blacklist (`omamobile-camera.conf`), which stays
  until the package loads the camera at boot (a later, separate step).
  Until the kernel has `35f679a26`:
  `echo 'options gs201_csis allow_stream=1' > /etc/modprobe.d/omamobile-camera-stream-bringup.conf`.
- **`ERR_WRONG_CONFIG`** once per frame persists on both modes; harmless
  so far (likely the sensor's embedded-data lines, which channel 0 isn't
  set up for). Not chased yet.

### CAM5.2c: the binned mode through libcamera, then the full-resolution DMA. Risk: medium (DMA)

Kernel `omamobile-camera` `35f679a26` merged into int (with `70da6c5a5`
and the CMA fragment) (ASK FIRST: flashes and reboots). libcamera 4.2 is
enough; 4.3 (the helper) only when the coordinator says.

```sh
# 5.2c-1 libcamera, binned mode: 2008x1508 RGB888, default module options
tools/phone-ssh 'modprobe gs201_csis; cam -c1 --capture=10 --file=/tmp/frame#.ppm --stream pixelformat=RGB888,width=2008,height=1508 2>&1 | tail -15; dmesg | grep -E "gs201-csis|imx386" | tail -6'
#   expect: no "adjusted"; "link 2 on: 2016x1508"; "stopped: ... WDMA done ~10
#   errors 0 ... missed frame ends 0"; ten PPMs; no vb2 "driver bug"
tools/phone-ssh 'cat /tmp/frame000009.ppm' > logs/cam5c-frame.ppm
# 5.2c-2 full resolution, raw path with colour bars (no libcamera), as-is
tools/camera-stage --watchdog x --cmd 'LINK=2 DMA=1 CH=0 W=4032 H=3016 FRAMES=2 bash -s' --script tools/camera-cap-test
#   if LASTADDR again: the "WDMA error 0x...: CTRL ... STRIDE ..." line
# 5.2c-3 (only after 5.2c-2 failed) one change: stride 5120 (512-aligned)
tools/camera-stage --watchdog x --cmd 'LINK=2 DMA=1 CH=0 W=4032 H=3016 FRAMES=2 CSIS_OPTS=stride_align=512 bash -s' --script tools/camera-cap-test
# 5.2c-4 (only if 5.2c-3 failed too) the other change: channel start 0x3
tools/camera-stage --watchdog x --cmd 'LINK=2 DMA=1 CH=0 W=4032 H=3016 FRAMES=2 CSIS_OPTS=wdma_ctrl=3 bash -s' --script tools/camera-cap-test
```

- **Pass (5.2c-1):** ten frames, 0 WDMA errors, a right-coloured picture
  (dark indoors without the helper).
- **Pass (5.2c-2/3/4):** `wdma_done` 2, errors 0, the file 2 x stride x
  3016 bytes (5056 or 5120 a line), bars in it (`tools/raw10-stats
  --width 4032 --height 3016 --stride 5056 --bars 8`). Whichever variant
  passes becomes the default.
- **Stop:** an error other than `LASTADDR`, a torn or shifted frame, an
  oops, a hang; any WDMA error in 5.2c-1 (binned mode was clean in CAM4).
- **Rollback:** reboot; the parameters are per load.

**CAM4.3c results (2026-10-13, int
`7.3.0-rc6-omamobile-push1-00407`, phone propped, room lit; INT vote on;
libcamera 0.7.2-4.3 with the IMX386 helper):** every run 0 WDMA errors
(also with the INT vote; the gain-480 LASTDATA of CAM4.3b didn't recur),
the readback matched, and the 30 fps default works (frame length 3599).
- **Gain sweep** (exposure 3000, `again_max=960`; Gr p50/mean, black 64):
  code 0 66/66.5; 240 67/68.6; 480 93/104.2; 720 read back as 208, 68/68.3;
  960 read back as 448, 81/85.6. **The register is 9 bits** (codes wrap at
  512), and the signal ratio (mean - 64) 1 : 1.84 : 16.1 at 0/240/480 is
  **gain = 512 / (512 - code), 1x-16x over 0-480** (the IMX258's model).
- **Exposure** at code 480: 750, 1500, 3000, 3580 lines give 8.8, 16.8,
  33.5 (and 72.4, light probably changed) above black: linear. At the top
  settings this dim room reaches about 7% of full scale: **the sensor is
  fine**; the earlier dark frames were short exposure and low gain.
- **libcamera (4.3, no warnings now):** `cam -c1 --capture=40 --stream
  pixelformat=RGB888,width=2008,height=1508` still gave an essentially
  black last frame (mean red 0.9/255).

**Why libcamera stays black (offline, libcamera 0.7.2 source):** the
simple IPA's AGC (`src/ipa/simple/algorithms/agc.cpp`) steps by `1 + 0.04
x error` per frame (error = 2.5 - MSV, at most 1.5 for a black frame:
6%), exposure first up to the control's maximum (3589 lines at the 30
fps default, taken from the control range at configure), then gain in
steps of at least (16 - 1) / 100 or 6%. Each step builds on the values
the sensor applied two frames earlier (DelayedControls, our two-frame
delays), so from our old start (exposure 1549, 1x gain, about 1 code
above black here) it needs well over 100 frames to reach the 10x+ gain
this room needs: 40 frames is far too few. The black level (4096 / 256 =
16 at 8 bits) and the gain model (16x at 480) are right; the AGC limits
are right; it's the start point and the step size.

**Fixes (2026-10-13):**
- `9af41f2e3` `media: i2c: imx386: 16x analogue gain at code 480, start at
  the longest exposure`: range capped at 480 (the 9-bit register),
  `again_max` gone; each mode starts at the longest exposure its default
  frame allows (3589 at 2016x1508).
- `packages/libcamera` 0.7.2-4.4 (repo, uncommitted): `0003-ipa-simple-
  agc-Step-faster-when-far-from-the-target-.patch` (proportional gain 0.1
  instead of 0.04 while the error is above 1, still at most 15% a step;
  unchanged near the target); `0002` now says the gain model is measured.
  Patches apply on 0.7.2; not compiled yet.

### CAM5.2d: libcamera's picture brightens. Risk: low (userspace; kernel push)

```sh
# 5.2d-0 (current kernel and 4.3, no rebuild) confirm the cause: a long run,
#   the AGC's own log
tools/phone-ssh 'LIBCAMERA_LOG_LEVELS=IPASoftExposure:0,IPASoft:1 cam -c1 --capture=300 --file=/tmp/frame#.ppm --stream pixelformat=RGB888,width=2008,height=1508 2>&1 | grep -E "IPASoft.*(Exposure [0-9]|exp )" | sed -n "1p;50p;100p;200p;\$p"'
#   expect: "Exposure 1-3589, gain 1-16 (0.15)", then exp climbing to 3589 and
#   again climbing over hundreds of frames; frame 299 visibly brighter than 39
# 5.2d-1 kernel with 9af41f2e3 (ASK FIRST) and libcamera 0.7.2-4.4
#   (tools/phone-install-package packages/libcamera, when the phone is free)
tools/phone-ssh 'rm -f /tmp/frame*.ppm; cam -c1 --capture=60 --file=/tmp/frame#.ppm --stream pixelformat=RGB888,width=2008,height=1508 2>&1 | tail -3'
tools/phone-ssh 'cat /tmp/frame000059.ppm' > logs/cam5d-frame.ppm   # then the PPM renderer
```

- **Pass:** frame 59 (2 s) shows the room at a normal brightness (mean
  over all channels well above 60/255 in this room), no WDMA errors.
- **If still dark at 60 but brighter by 300 in 5.2d-0:** the AGC step is
  the limit; the 4.4 patch is the fix, check it's installed (`pacman -Q
  libcamera`).
- **Stop:** WDMA errors, flicker between frames (AGC oscillating: the
  far-error gain too high; back to 4.3).
- **Rollback:** the 4.3 package; the old kernel.

Update after CAM4.3b: the Bayer order is confirmed (RGGB), the 30 fps
default is in `49a0a54f4`, and the frame needs a 90 degree turn
(`rotation = <90>`, which libcamera reads). **CAM5.0-5.2 can start now**
(on a kernel with `49a0a54f4`; on the older one expect dark 60 fps
pictures). Expect dark indoor pictures until the gain model is known
(CAM4.3c-3): without a helper, libcamera's AGC treats the code as a
linear gain and stops at the control's 480. The helper patch follows the
sweep.
- **Rollback:** `pacman -S libcamera` (Arch Linux ARM's build).

### 7.Q Picture quality: where it stands and what can improve it (2026-10-13)

The human finds the ultrawide's pictures soft, noisy and dim. Expected,
and mostly not a bug:

- **The ultrawide is the weakest camera on the phone**: a 12 MP Sony
  IMX386 with small 1.25 um pixels behind a slower wide lens, and libcamera
  runs it in the 2x2 binned 2016x1508 mode (3 MP; `cam` picks 2008x1508,
  CAM5.2b). Binning halves the resolution; full resolution (4032x3016)
  still fails in the WDMA (`LASTADDR`, CAM5.2c).
- **No hardware ISP and no Google tuning.** Stock runs the frames through
  the ISP (noise reduction, lens shading, sharpening, tone mapping) and
  merges several frames (HDR+). We have libcamera's software ISP:
  bilinear-style debayer, grey-world white balance, a simple AGC, a
  colour matrix and gamma, and **no denoise, no lens shading correction,
  no sharpening and no multi-frame**. Google's tuning files and the
  module calibration are proprietary and per-phone (section 1.6) and stay
  out. "Decent webcam" (section 3a) is the honest ceiling for this path.
- **Dim** was exposure and gain (CAM4.3c, fixed in `9af41f2e3` and
  libcamera 4.4), plus the AGC's slow climb. The ultrawide reaches 16x
  analogue gain and 33 ms indoors and is still noisy there: that's the
  sensor, not our code.
- **Soft**: binning, no sharpening, and a lens parked where the actuator
  leaves it (unpowered: its rest, roughly far focus). The ultrawide
  focuses for macro; for subjects past about a metre the parked lens is
  close to right.

What can be done, biggest first:

| Change | Expected effect | Where |
|---|---|---|
| **The main camera** (Samsung GN1, 1.2 um pixels on a 1/1.31" sensor, f/1.85, AF) | by far the biggest: about 4x the light per output pixel of the ultrawide, a real 12.5 MP binned mode (4080x3072), autofocus | CAM-M below |
| Contrast autofocus in the software ISP (both lenses) | sharp close subjects; the main camera needs it at all distances (shallow depth of field) | `packages/libcamera` 4.5 (0005-0007), CAM5.3 |
| Cached capture buffers | the soft ISP's per-frame CPU read of the raw frame drops from tens of ms to a few (another bring-up measured 48 ms to 3.8 ms): full frame rate, more time for the debayer | `gs201-csis` (`cached_buffers`, default on) |
| Up to 4x digital gain past the analogue limit | brighter dim rooms (noisier) | libcamera 0011 |
| A colour matrix and contrast default for the IMX386 | more saturated colour; a stand-in (the Raspberry Pi IMX519 matrices shipped in libcamera, BSD-2-Clause), some hue error until a calibration | libcamera 0012 |
| Full-resolution ultrawide (4032x3016) for stills | sharper stills at 15-30 fps preview cost; needs the `LASTADDR` fix (CAM5.2c: try `wdma_ctrl=3` first, the value another bring-up streams 4032x3016 with) | CAM5.2c |
| Our own colour calibration (a colour chart, or a grey card under 2-3 lights) | right hues; uses only our captures | later |
| Lens shading / denoise | needs libcamera soft-ISP features that don't exist in 0.7.2 | upstream |

Default mode: keep the binned mode for preview and video (60 fps headroom,
30 fps default, cheap debayer); stills want full resolution once CAM5.2c
passes. libcamera picks the mode from the stream size the app asks for,
so this is per app (Snapshot asks for a preview size; its photo is the
preview frame).

**Added 2026-10-13 (offline, libcamera 4.6 and the kernel in 5.1):**

| Change | Expected effect | Where |
|---|---|---|
| The telephoto (48 MP GM5 behind a 5x folded lens, SEM1215SA focus) | real zoom: 4032x3024 binned stills, 2016x1512 preview; AF over the module's calibrated range | CAM-T |
| The front camera (3J1) | selfies and video calls; fixed focus | CAM7 |
| A sensor mode within 1% of the stream qualifies (0014) | 1080p video and previews run the binned modes (the 3J1's 1920x1368 instead of its 3840x2736: a quarter of the data per frame); a stream the size of a binned mode loses its last 8 columns instead of quadrupling the work | libcamera 0014 |
| Sensor helpers, properties and tuning stubs for the 3J1 and GM5 | right exposure and gain from the start (code / 32), identity matrix with contrast 1.2 and saturation 1.1, AF on the telephoto | libcamera 0013 |

**What needs captures on the phone** (each with `tools/camera-cap-test`
raw frames at a fixed exposure and gain, or `cam` DNGs of the raw stream;
everything stays ours, nothing from Google's tuning):

1. **Colour matrices, per camera:** a colour chart (24 patches) filling a
   third of the frame, under daylight, a 4000 K LED and a tungsten bulb,
   exposed so the white patch is at about 80% of full scale. libcamera's
   own tuning library (`utils/tuning/libtuning`, its CCM module, with
   `rkisp1.py` as the template for a soft-ISP script whose output is the
   same `ccms` list) fits one matrix per colour temperature; the result
   replaces the IMX519 stand-in and the identities.
2. **Lens shading, per camera:** flat fields (an evenly lit white wall or
   a diffuser over the lens) at the same three lights. Measures the
   vignetting and colour shading that make the corners dark and tinted.
   libcamera 0.7.2's soft ISP can't correct it yet; with the measurement a
   gain map in the GPU debayer is a contained patch (later work).
3. **Noise and black level per gain:** dark frames (lens covered) at
   analogue gain codes 1x-16x. Confirms the 64 black level on all four
   sensors and gives the noise growth that sets the AGC's gain ceiling
   against exposure time, and a denoise strength once there is a denoise.
4. **Focus ranges:** each lens's useful travel from the AF sweeps (CAM5.3-3,
   M.7, T.6/T.7) as `range: [ min, max ]` in its `Af` entry: shorter, more
   accurate scans.
5. **Rotation and mirroring** of each camera from one picture of text
   (CAM-M.5, F.7, T.5).

### P: the DC-PHY settings file, before any kernel from this branch. Risk: low

From `f397875e0` on, no link powers on without `gs201-dcphy.bin`: the
ultrawide stops working on such a kernel until the file is installed. So
the files go on the phone first (no reboot), then the kernel, then one
check that the ultrawide is unchanged.

```sh
# P.0 (laptop) every data file from your own HAL; never commit them
~/.cache/omamobile-venv/bin/python tools/extract-camera-data \
    --apex <vendor>/apex/com.google.pixel.camera.hal.apex -d /tmp/camdata
#   expect: HAL sha256 ce9acaad... (CP2A.260705.006; selectors at slots -1/-4)
#   or d8f9abb0... (CP3A.261005.002.A1; slots -2/-5, the same five files);
#   IMX386 init 139, S5KGN1 init 1565,
#   S5K3J1 init 366 (5 modes), S5KGM5 init 4047 (4 modes);
#   "D-PHY: 32 register writes, 3 by rate in 111 ranges (80-2147 Mbps)",
#   settle 7 at 1548 and 8 at 1665; "C-PHY: 20 register writes, 2 by rate in
#   3 ranges (1-2147 Msps)", settle 7 at 1802 and 1862
#   (the same five files are in ~/android/reference/ from this HAL)
# P.1 (phone, no reboot) install them, and the bring-up blacklist for the new
#   lens driver until omamobile-device-cheetah 0.1.28 is installed
for f in imx386-uw s5kgn1-main s5k3j1-front s5kgm5-tele gs201-dcphy; do
  tools/phone-ssh "cat > /usr/lib/firmware/omamobile/camera/$f.bin" < /tmp/camdata/$f.bin; done
tools/phone-ssh 'sha256sum /usr/lib/firmware/omamobile/camera/*.bin'
tools/phone-ssh 'printf "blacklist s5kgn1\nblacklist ak7375\nblacklist sem1215\n" > /etc/modprobe.d/omamobile-camera-bringup.conf'
#   expect: the sums match `sha256sum /tmp/camdata/*.bin`
# P.K kernel: the human merges omamobile-camera (head c91185280 or later)
#   into int; images with the overlays the phone runs today (camera-stream-link2,
#   camera-uw-lens if it has it), nothing new (ASK FIRST: flashes and reboots)
# P.2 (this boot) the ultrawide as in CAM5.2: one libcamera capture. The PMIC
#   modules are blacklisted at boot and the sensor defers without them
#   (regulator-pp3200-bb-cam "can't get GPIO"; cam -l lists nothing): load them first
tools/phone-ssh 'modprobe sec_acpm; modprobe gpio_s2mpg13; modprobe slg51002_regulator; sleep 2'
tools/phone-ssh 'cam -c1 --capture=30 --file=/tmp/p#.ppm --stream pixelformat=RGB888,width=2008,height=1508 2>&1 | tail -2; dmesg | grep -E "PHY settings|link 2: D-PHY|stopped" | tail -4'
#   pass: "PHY settings from omamobile/camera/gs201-dcphy.bin: D-PHY 32 writes,
#   111 rate ranges; C-PHY 20 writes, 3 rate ranges"; "link 2: D-PHY 4 lanes
#   (with the next link's) at 1548288000 bps, settle 7 ... bias 0x10 0x110
#   0x3223 0x0 0x200"; WDMA errors 0; the picture as before
#   stop: "not loaded" (P.1 missed: install, retry, no reboot); link errors on
#   every frame or no frames (the new bias CON0-3 words: rollback, record)
```

- **Rollback:** the previous kernel (`cp "$D.default" "$D"` with its
  images, or push the last int build). The files are harmless to older
  kernels.
- Then CAM-M, CAM7 and CAM-T, one overlay per boot (section 7.R).

### CAM-M: the main camera (Samsung S5KGN1, C-PHY on link 1). Risk: medium

**Facts.** All [V] from the user's own HAL by `tools/extract-camera-data
--sensor s5kgn1` (2026-10-13; HAL sha256 `ce9acaad...`), unless marked:

- Chip ID 0x08e1 at 0x0000; I2C bus 1 (`hsi2c_1`, USI1, SPI 674, 1 MHz),
  0x3d; reset gpp2-2; MCLK `CIS_CLK3` on gpp9-0. Its settings expect a
  **24.58 MHz** clock (EXCK register 0x0136 = 0x1894), so we run CIS_CLK3
  at 24.576 MHz like the ultrawide (section 1.1's "26 MHz" is stock DT's
  rate request, not what the sensor settings assume).
- **Three C-PHY trios** (0x0114 = 0x0201) to **CSIS link 1 / DC-PHY slave
  1** (section 4.4).
- Default init list: 1565 writes (a firmware patch through the indirect
  0x6028/0x602a/0x6f12 window, then analog and CCS settings), chosen by the
  HAL when no debug property is set (it has six more variants: v2plus,
  hres, hfr, full 50 MP...). Before it, Samsung's soft reset and clock
  enable (0x6028 = 0x4000, 0x6010 = 1, 10 ms, 0x6226 = 1, 10 ms), as
  mainline `s5kjn1.c` does for its sibling; the driver writes them.
- Four default modes, all at one pixel clock (1.307 Gpix/s at 8 pixels per
  clock [I]): **4080x3072 at 30 fps** (2x2 binned 12.5 MP, the stills
  mode), 4080x2288 at 60, 2016x1136 at 120 (video), **2032x1536 at 60**
  (4:3 preview). The driver defaults blanking to 30 fps.
- [I], checked below: Bayer GRBG, analogue gain code/32 (0x20 = 1x up to
  0x200 = 16x), black level 64, the C-PHY symbol rate (the DT carries
  931 229 968 Hz as "half the symbol rate"; only the PHY's settle choice
  depends on it), rotation 90, exposure margin 16.
- From another bring-up on this phone model (section 4.4), [I] here: the
  link needs CAM DVFS **533 MHz** (at 400 MHz its image FIFO overflows,
  `ERR_OVER`, and the WDMA stops at 64 Ki words); interleave 3, deskew
  level 2 and the C-PHY select bit in the link's common control; channels
  1-3 parked on VC 15 (the GN1 sends a second stream on VC 1); the AF is
  an AK7375-type at 0x0c; the OIS controller (0x24) and laser AF (0x29)
  are not needed for a picture.

**Built and committed (2026-10-13)** on `omamobile-camera` in
`~/android/mainline/wt-camera`, on top of `9af41f2e3`, head `e6fc91e77`
(not merged into `omamobile-int` yet), built clean as
`7.3.0-rc6-omamobile-push1-00370-ge6fc91e77693` in `out-camera`:

| Commit | |
|---|---|
| `58dd3134e` | `arm64: dts: exynos: google: gs201: add USI1 and its I2C bus` |
| `f9c29fe56` | `dt-bindings: phy: google,gs201-mipi-dcphy-rx: describe C-PHY` |
| `36a3ae0fa` | `phy: samsung: gs201-mipi-dcphy-rx: receive C-PHY` |
| `7ff3755d8` | `dt-bindings: media: google,gs201-csis: C-PHY endpoints, shared WDMA contexts` |
| `123ac15cd` | `media: gs201-csis: let links share a WDMA context` |
| `fe9cca64c` | `media: gs201-csis: receive C-PHY links` |
| `c01610e26` | `media: gs201-csis: cached capture buffers` |
| `fd4e3e1cb` | `dt-bindings: media: i2c: add Samsung S5KGN1` |
| `3b1b4d536` | `media: i2c: add a Samsung S5KGN1 driver` |
| `22a055f79` | `arm64: dts: exynos: google: gs201: CSIS links 0 and 1 on WDMA context 0` |
| `e6fc91e77` | `arm64: dts: exynos: google: gs201-cheetah: main camera and focus actuators` |

- DC-PHY C-PHY (`f9c29fe56`, `36a3ae0fa`):
  `phy_set_mode_ext(PHY_MODE_MIPI_DPHY, PHY_TYPE_CPHY)` selects C-PHY;
  lanes are trios (max 3), one data-lane block each, no clock lane, never
  paired. **The C-PHY values are not in the kernel source** (the human's
  decision, option B): they come from a data file,
  `omamobile/camera/gs201-cphy.bin`, named by the PHY node's
  `firmware-name` and loaded at the first C-PHY power-on (a clear error
  if it's missing; D-PHY never needs it). Format (ours, `"OCPH"` v1): an
  ordered list of writes to the bias block or to every trio's lane
  block, one of which is "the settle fields of TIME_CON0, by rate", and
  a settle table by symbol rate. `tools/extract-camera-data --sensor
  s5kgn1` writes it next to `s5kgn1-main.bin`, by running the HAL's PHY
  setup function once per rate (1-2147 Msps) with a stand-in register
  writer. From this HAL: 19 writes (bias CON0-4, then per trio the lane
  enable first, GNR_CON1, ANA_CON0-7, the settle, TIME_CON1 and two
  C-PHY-only registers at 0x64/0x68) and settle 9 below 999 Msps, 7 from
  999 (the settle clock select set below 500 Msps). Stock writes bias
  CON0-3 too, so we now do (the D-PHY path still leaves them as found).
- `media: gs201-csis`: (a) **links share WDMA context 0, one stream at a
  time** (the WDMA window and its interrupt mapped shared, a global owner;
  a second camera's stream-on gets `EBUSY`, and only the owner's handler
  reads the shared interrupt); (b) **C-PHY links** from the endpoint's
  `bus-type`: the C-PHY bit in the common control, the PHY in C-PHY mode,
  the CAM vote from `cam_khz_cphy` (533 MHz; `cam_khz` stays the D-PHY
  vote); (c) **cached capture buffers** (`cached_buffers=1`, default).
  Binding: `bus-type` on the endpoint.
- `media: i2c: add a Samsung S5KGN1 driver` (`s5kgn1`, binding
  `samsung,s5kgn1.yaml`): the imx386 driver's shape (data file, controls,
  crop, readback log), data file **version 2** (16-bit values), stock's
  power order (`vio` LDO12S, `vaux` SLG LDO4 2.9 V, 1 ms, `vsw` SLG switch
  3, `vdig` LDO8, `vana` LDO1, 2 ms, reset released, 1 ms, MCLK, 9 ms),
  soft reset + clock enable before the init list, exposure 0x0202,
  analogue gain 0x0204, digital gains 0x020e-0x0214, frame length 0x0340,
  test pattern 0x0600.
- DT: `csis0`/`csis1` now feed WDMA context 0 with the EBUF and the DVFS
  clocks (as `csis2`); cheetah: `hsi2c_1` with the S5KGN1 at 0x3d and its
  AK7375 at 0x0c, the ultrawide's AK7375 at 0x0f, the `cam_main_mclk_on`
  pins, `csis1`'s C-PHY endpoint, the camera pool 64 -> **128 MiB** (four
  4080x3072 RAW10 buffers are 63 MiB). All disabled.
- Config (repo): `CONFIG_VIDEO_S5KGN1=m`, `CONFIG_VIDEO_AK7375=m` (mainline
  `ak7375`). Overlays (repo): `camera-main` (main path + its lens,
  `lens-focus`), `camera-uw-lens` (ultrawide lens), and
  `camera-stream-link2` no longer disables link 1. Blacklist (repo,
  omamobile-device-cheetah 0.1.27): `s5kgn1`, `ak7375`.
- `tools/extract-camera-data --sensor s5kgn1` writes
  `s5kgn1-main.bin` (16 948 bytes) and `gs201-cphy.bin` (188 bytes);
  copies for this phone are in `~/android/reference/`, never committed.
  The IMX386 output is byte-identical to before. `tools/camera-cap-test` takes
  `SENSOR=s5kgn1` (GRBG, `pgAA`, loads `ak7375`).

**Checks (laptop, 2026-10-13):** `bin/omamobile kernel` exit 0; `W=1` on
`s5kgn1.o`, `gs201-csis.o`, `phy-gs201-mipi-dcphy-rx.o` and the DTB: only
the existing simplefb warning (the two intermediate `gs201-csis` commits
compile clean too); checkpatch `--strict` per commit: only MAINTAINERS and
the trailer-form items; `dt_binding_check` on the three bindings
(dtschema 2026.9) clean; `tools/extract-camera-data --sensor s5kgn1` on
this HAL: the C-PHY file in about 2 s, `s5kgn1-main.bin` byte-identical
to the earlier run;
`dt-validate` on the default DTB, on default + `camera-main`, and on
default + `camera-stream-link2` + `camera-uw-lens` + `camera-main`: only
the existing `soc_id` and framebuffer reports; the overlays leave
`csis@1a450000`, `csis@1a460000`, both lenses and both sensors okay,
`csis@1a440000` disabled, `lens-focus` set on both sensors.

**Runbook.** One change per boot; the watchdog and the log stream through
`tools/camera-stage` for anything that streams. The ultrawide's overlay
stays as the phone runs today.

```sh
# M.0 the data files and the bring-up blacklist: runbook P (P.0, P.1), done
#   once for all cameras (s5kgn1-main.bin: init 1565 writes; 4080x3072 30 fps,
#   4080x2288 60, 2016x1136 120, 2032x1536 60)
# M.1 (read-only, today's kernel) the main module's pins as ABL left them
tools/phone-ssh 'grep -E "gpp2-[012]|gpp9-0" /sys/kernel/debug/pinctrl/*/pins 2>/dev/null | head'
#   expect: gpp2-0/1/2 and gpp9-0 inputs (function 0); stop if any is an output
# M.K (after P) the same kernel, overlays camera-stream-link2 (camera-uw-lens)
#   camera-main (ASK FIRST: flashes and reboots)
KERNEL_DIR=~/android/mainline/wt-camera KERNEL_OUT=~/android/mainline/out-camera \
    ov camera-stream-link2 camera-main && bin/omamobile push
tools/phone-ssh 'uname -r; lsmod | grep -cE "s5kgn1|ak7375|gs201_csis"'
#   expect: the new release, 0 (all blacklisted)
# M.2 (this boot) the sensor's power-up and chip ID only (no stream)
tools/camera-stage --watchdog x --cmd 'modprobe sec_acpm; modprobe gpio_s2mpg13; modprobe slg51002_regulator; modprobe s5kgn1; sleep 1; dmesg | grep -E "s5kgn1|slg51002" | tail -5; cat /sys/kernel/debug/regulator/regulator_summary | grep -E "ldo12s|vdda_main|vdd_main_af|vddd_main|cam_sw3"'
#   pass: "s5kgn1 1-003d: model 0x08e1"; afterwards the main rails off again (runtime suspend)
#   stop: an I2C error/NACK (check MCLK pin and reset), a chip ID other than 0x08e1, any rail left on
# M.3 (same boot) the graph: lens, PHY, CSIS
tools/phone-ssh 'modprobe ak7375; modprobe phy_gs201_mipi_dcphy_rx; modprobe gs201_csis; sleep 1; for d in /dev/media*; do media-ctl -d $d -p | grep -E "entity|s5kgn1|ak7375|link 1|ancillary"; done'
#   pass: "gs201-csis link 1" with "s5kgn1 1-003d" and "ak7375 1-000c" (ancillary link);
#   dmesg "link 1 -> WDMA context 0, 3 C-PHY trios"; the ultrawide's link 2 graph unchanged
# M.4 (next boot) colour bars on link 1, link only (no DMA), 2032x1536
tools/camera-stage --watchdog x --cmd 'LINK=1 SENSOR=s5kgn1 W=2032 H=1536 DMA=0 bash -s' --script tools/camera-cap-test
#   pass: dmesg "link 1: C-PHY 3 trios at 1862459936 sps, settle 7" (the PHY file loaded
#   at P.2), "link 1 on: ... C-PHY trios ... CAM 533000000 Hz";
#   stats: frame_start/frame_end rising ~30/s, link_errors only ERR_WRONG_CONFIG (0x8) if any;
#   sensor log: frame_count rising
#   stop: "PHY settings ... not loaded" (P.1's file missing: install it, retry; no reboot needed),
#   CRC/ECC/OVER errors on every frame (next single change: CAM vote 664 MHz), no frame start at
#   all (the PHY or the trio count), a hang (watchdog, pstore)
# M.5 (next boot) first DMA on link 1: colour bars, then the solid colour for the Bayer order
tools/camera-stage --watchdog x --cmd 'LINK=1 SENSOR=s5kgn1 W=2032 H=1536 DMA=1 FRAMES=4 bash -s' --script tools/camera-cap-test
tools/phone-ssh 'cat /tmp/cam-2032x1536.raw' > logs/camm-bars.raw
tools/raw10-stats logs/camm-bars.raw --width 2032 --height 1536 --stride 2560 --bars 8
#   pass: wdma_done 4, wdma_errors 0, file 4 x 2560 x 1536 = 15 728 640 bytes, eight bars
tools/camera-stage --watchdog x --cmd 'LINK=1 SENSOR=s5kgn1 W=2032 H=1536 DMA=1 FRAMES=4 PATTERN=0 CTRLS=analogue_gain=256 bash -s' --script tools/camera-cap-test
#   a real picture (debayer as GRBG on the laptop); if the colours are swapped, the header's bayer field
# M.6 the gain model: as CAM4.3c-3 (phone propped, same scene), PATTERN=0, exposure fixed,
#   analogue_gain 32, 64, 128, 256, 512: signal ratio 1:2:4:8:16 confirms code/32
# M.7 libcamera (4.5): the main camera listed and a picture, then autofocus
tools/phone-ssh 'cam -l'
#   expect: two cameras (the ultrawide and "... i2c@10900000/camera-sensor@3d")
tools/phone-ssh 'LIBCAMERA_LOG_LEVELS=IPASoftAf:0 cam -c2 --capture=120 --file=/tmp/m#.ppm --stream pixelformat=RGB888,width=2024,height=1536 2>&1 | grep -E "Autofocus|focus|adjusted" | tail'
tools/phone-ssh 'cat /tmp/m000119.ppm' > logs/camm-frame.ppm
#   pass: a sharp, right-coloured picture; "Autofocus completed"; no WDMA errors
# M.8 stills mode: --stream width=4072,height=3072 (4080x3072 binned), 10 frames
```

- **Rollback:** reboot (everything is per load); images without
  `camera-main`; remove the bring-up blacklist file when the package
  ships it.
- **Risks:** a C-PHY setting we got wrong only shows as link errors (no
  DMA before M.5). The S5KGN1's 16-bit firmware patch writes can't harm
  the sensor (RAM, gone at power-off). The main module's OIS is left
  unpowered (stock powers it from SLG switches 1 and 2): the lens floats
  in its OIS suspension and may rattle; harmless. The capture pool
  doubles (128 MiB reusable CMA below 4 GiB).

**P and CAM-M results (2026-10-13, int `937d47233` =
`7.3.0-rc6-omamobile-push1-00446-g937d47233338`: int + `omamobile-camera`
`c91185280`; overlays as before + `modem-cpif-pktproc`, + `camera-main`
from M.K; logs `logs/camera-20261013-14*.log`, `logs/cam-m41c-kmsg.log`):**
- **P.0/P.1 passed:** the five files byte-identical to the reference
  copies, installed, sums match; device-cheetah 0.1.28 installed.
- **P.2 passed** once `sec_acpm`, `gpio_s2mpg13` and `slg51002_regulator`
  were loaded by hand (now in the step): "PHY settings from
  omamobile/camera/gs201-dcphy.bin: D-PHY 32 writes, 111 rate ranges;
  C-PHY 20 writes, 3 rate ranges"; "link 2: D-PHY 4 lanes ... 1548288000
  bps, settle 7 ... bias 0x10 0x110 0x3223 0x0 0x200"; 30 frames at 29.9
  fps, link errors one a frame (0x8, as always), WDMA errors 0, a normal
  picture. **The ultrawide is unchanged with stock's bias words.**
- **M.1 passed** (gpp2-0/1/2, gpp9-0 function 0, unclaimed). **M.2
  passed:** "s5kgn1 0-003d: S5KGN1, model 0x08e1", rails off afterwards.
  **M.3 passed:** link 1 <- `s5kgn1 0-003d`, the `ak7375 0-000c` entity
  present, "link 1 -> WDMA context 0, 3 C-PHY trios", link 2's graph
  unchanged; `cam -l` lists both cameras.
- **M.4 (fresh boot), link only at 2032x1536: frames arrive, with a link
  error in every interrupt.** "link 1: C-PHY 3 trios at 1862459936 sps,
  settle 7 ... bias 0x10 0x110 0x3223 0x0 0x40"; "link 1 on: 2032x1536
  DT 0x2b, 3 C-PHY trios; CMN_CTRL 0x00204e01 PHY_CMN 0x0000001f ...
  CAM 533000000 Hz"; FS 144 FE 144 in 4.7 s (30 fps, FRM_CNT_CH0 counts
  them too); 31139 link interrupts, every one with an error (about 216 a
  frame), the last 0x8 (`ERR_WRONG_CONFIG`); only the last word was
  kept, so the mix is unknown. The channel registers read as programmed:
  channel 0 0x20ac (RAW10, quad, VC 0), resolution 0x060007f0; channels
  1-3 0x000f20fc (VC 15, data type 0x3f). One difference from the
  ultrawide's scan: link+0x6a0 reads 0x00014100 (link 2: 0), an unnamed
  register.
- **M.5 (fresh boot), first DMA: stopped.** At the first frame "WDMA
  error 0x00008000 (`LASTADDR`): CTRL 0x00000001 FMT 0x00000007 ADDR1
  0xee600000 RESOL 0x060007f0 STRIDE 0x00000a00, 2032x1536, 2560 bytes a
  line, 3932160 a frame"; at stop FS 144 FE 144, link errors 35403 (last
  0x8), WDMA done 0, errors 340 (all `LASTADDR` as far as recorded), the
  file 0 bytes. INT 400 MHz, CAM 533 MHz.

**Why (offline, 2026-10-13):**
- `LASTADDR` means the WDMA reached the end of the frame it was told to
  write before the frame ended: more data arrived on channel 0 than
  2032 x 1536 RAW10. Everything we program matches what the bring-up in
  section 4.4 used to capture whole GN1 frames (533 MHz CAM, 400 MHz INT,
  channels 1-3 on VC 15, interleave 3, the C-PHY bit, EBUF bypass, format
  7, 64-byte line padding) except two things: the **mode** (that bring-up
  used the 2016x1136 and 4080x3072 modes, never 2032x1536) and the WDMA
  **start value** (0xf83, stock's, against their 0x3; 0xf83 works for the
  ultrawide's binned mode).
- **The 2032x1536 mode is the odd one out in the data file:** comparing
  its register list with the other three, besides size, crop and frame
  length it clears two manufacturer registers (0x0c02, 0x0c06) that
  2016x1136, 4080x2288 and 4080x3072 all set, one of them to a value that
  scales with the output height (a quarter of it). That reads like the
  phase-detection output's set-up [I]: in this mode the phase data
  likely leaves in another form, possibly on VC 0 as extra lines, which
  would overrun the WDMA, and would also fit a link error on nearly every
  line. The 2032x1536 mode is the one stock uses for its 4:3 preview with
  its own ISP, which takes whatever the sensor sends.
- The line burst is the same in every GN1 mode (one pixel clock, 3000
  clocks a line in the binned modes), so the bus can't explain one mode
  failing where 2016x1136 works elsewhere.
- `cb502b561` `media: gs201-csis: count each error bit` (on top of
  `c91185280`, built W=1 clean; comes with the next kernel push, not
  needed for M.5b): debugfs `stats` gets `int0_bits`/`int1_bits`/
  `wdma_bits` lines and the stop line a per-bit summary, so the next run
  says which link errors those are.

### CAM-M.5b: the 2016x1136 mode, then the WDMA start value. Risk: medium (DMA)

One change per step; the current kernel (`937d47233`) and overlays.
Don't use 2032x1536 (or a libcamera size that picks it, such as
2024x1536) until this is understood.

```sh
# M.5b-0 (this boot, link only, no DMA) the 2016x1136 mode's link behaviour
tools/camera-stage --watchdog x --cmd 'LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=0 bash -s' --script tools/camera-cap-test
#   record: link_irqs / frame_start against M.4's ~216 a frame, and link1+0x6a0 in the scan
#   pass: FS/FE ~30/s, no hang
# M.5b-1 (next boot) first DMA in the 2016x1136 mode: colour bars
tools/camera-stage --watchdog x --cmd 'LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=1 FRAMES=4 bash -s' --script tools/camera-cap-test
tools/phone-ssh 'cat /tmp/cam-2016x1136.raw' > logs/camm-bars.raw
tools/raw10-stats logs/camm-bars.raw --width 2016 --height 1136 --stride 2560 --bars 8
#   pass: wdma_done 4, wdma_errors 0, file 4 x 2560 x 1136 = 11 632 640 bytes, eight bars
#   then, same boot, a real picture (as M.5, W=2016 H=1136 PATTERN=0 CTRLS=analogue_gain=256)
#   stop: LASTADDR again (go to M.5b-2), any other WDMA error, a hang
# M.5b-2 (next boot, only if M.5b-1 gave LASTADDR) the start value another bring-up uses
tools/camera-stage --watchdog x --cmd 'LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=1 FRAMES=4 CSIS_OPTS=wdma_ctrl=3 bash -s' --script tools/camera-cap-test
#   pass as M.5b-1; stop: LASTADDR again: record and stop (next: CAM 664 MHz,
#   CSIS_OPTS=cam_khz_cphy=664000, one boot later)
# M.5b-3 (next boot, only after M.5b-1 or -2 passed) the stills mode, same settings
tools/camera-stage --watchdog x --cmd 'LINK=1 SENSOR=s5kgn1 W=4080 H=3072 DMA=1 FRAMES=2 bash -s' --script tools/camera-cap-test
#   pass: wdma_done 2, errors 0, 2 x 5120 x 3072 bytes
```

- **If 2016x1136 passes and 2032x1536 doesn't:** the 4:3 preview mode
  goes out of the driver's list (the data file keeps it; the driver skips
  a mode the board can't take, by a list in the DT or by its size) and
  libcamera previews from 4080x3072 or 2016x1136; or, later, its extra
  data is found and parked. M.6 (gain) and M.7 (libcamera, with
  `width=2008,height=1136` or `width=4072,height=3072`) follow on the
  passing mode.
- **Rollback:** reboot; all parameters are per load.

**CAM-M.5b results (2026-10-13, int `8070cddd9` =
`7.3.0-rc6-omamobile-push1-00448-g8070cddd92a6`: `937d47233` + the modem
PCIe speed fix; `camera-main`; `cb502b561` not in it yet; logs
`logs/camera-20261013-141*.log`):**
- **M.5b-0 (2016x1136, link only):** "link 1 on: 2016x1136 DT 0x2b, 3
  C-PHY trios ... CAM 533000000 Hz"; FS 144 FE 144; 28786 link
  interrupts, every one with an error (about 200 a frame, M.4: 216), the
  last 0x8. link+0x6a0 read **0x09d82b00**: 0x09d8 = 2520, exactly one
  2016-pixel RAW10 line, with data identifier 0x2b (VC 0, RAW10). M.4's
  0x00014100 reads the same way as a VC 1 frame end (identifier 0x41,
  frame number 1). So 0x6a0 holds the last packet header the link took
  [I], and **the GN1 does send a second stream on VC 1**; its VC 0 lines
  have the right length.
- **M.5b-1 (fresh boot, DMA):** "WDMA error 0x00008000: CTRL 0x00000001
  FMT 0x00000007 ADDR1 0xee500000 RESOL 0x047007e0 STRIDE 0x00000a00,
  2016x1136, 2560 bytes a line, 2908160 a frame"; FS 144 FE 144, link
  errors 25273, WDMA done 0, errors 250 (last `LASTADDR`), no data.
- **M.5b-2 (fresh boot, `wdma_ctrl=3`, read back 3):** the same, 251
  WDMA errors, 23079 link errors.
- **So neither the 2032x1536 mode nor the start value is the cause.**
  Stopped as the runbook says.

**Why, second pass (offline):**
- Lines on VC 0 are the right length (0x6a0), the channel registers are
  as programmed, and the same WDMA settings write whole frames from the
  ultrawide. What the WDMA sees from link 1 is therefore more than the
  VC 0 RAW10 lines: extra bytes or lines from somewhere in the C-PHY
  path. Our link set-up matches the one that captured whole GN1 frames
  elsewhere (section 4.4) in every register but one: **LRTE_CONFIG
  (0x600)**. We write 0x7fff (taken as stock's), which clears the upper
  spacer field (30:16) of a register that resets to 0x7fff7fff [I]; the
  working set-up wrote 0x7fff7fff (its reset value) for the GN1. LRTE
  spacers exist on C-PHY only, which fits a failure on C-PHY that the
  D-PHY ultrawide never shows. Our note that stock "leaves 0x600 at its
  default" (4.3, RE2) and the 0x7fff in the driver disagree; the test
  decides.
- The ~200 link errors a frame are probably the VC 1 stream's packets
  (no channel takes VC 1: `ERR_WRONG_CONFIG`), harmless as on the
  ultrawide; the per-bit counters will show whether anything else
  (resolution mismatches, overflow) is among them.
- CAM 664 MHz stays the change after this one: an overflow would show
  as `ERR_OVER` (INT0) or `FIFO_FULL`, which the counters will tell.
- Kernel (on `omamobile-camera`, not merged): `cb502b561` (per-bit error
  counters) and `32e190c83` (`lrte_config=` parameter, 0 = unchanged; the
  first WDMA error's log line adds the link's last packet header, its
  frame counter and the LRTE value). Defaults unchanged: on its own the
  kernel changes nothing on the wire.

### CAM-M.5c: error bits, then LRTE at its reset value. Risk: medium (DMA in c-2)

```sh
# M.5c-K kernel: int + omamobile-camera 32e190c83 (cb502b561, 32e190c83), the
#   same overlays (ASK FIRST: flashes and reboots)
tools/phone-ssh 'uname -r; modinfo -p gs201_csis | grep -E "lrte_config|wdma_ctrl"'
# M.5c-0 (this boot, link only) which link errors, at the driver's LRTE (0x7fff)
tools/camera-stage --watchdog x --cmd 'modprobe sec_acpm; modprobe gpio_s2mpg13; modprobe slg51002_regulator; sleep 1; LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=0 bash -s' --script tools/camera-cap-test
tools/phone-ssh 'dmesg | grep -E "error bits|stopped" | tail -4'
#   record: the INT0/INT1 bit counts (expect b3 ERR_WRONG_CONFIG dominant); any INT1 b5/b6
#   (H/V resolution mismatch) or INT0 b4 (overflow) is the lead
# M.5c-1 (same boot, link only) the same with LRTE at its reset value
tools/camera-stage --watchdog x --cmd 'LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=0 CSIS_OPTS=lrte_config=0x7fff7fff bash -s' --script tools/camera-cap-test
tools/phone-ssh 'dmesg | grep -E "error bits|stopped" | tail -4'
#   record: the bit counts again, and link1+0x600 in the scan (0x7fff7fff); pass: FS/FE ~30/s
# M.5c-2 (next boot) DMA with LRTE at its reset value
tools/camera-stage --watchdog x --cmd 'modprobe sec_acpm; modprobe gpio_s2mpg13; modprobe slg51002_regulator; sleep 1; LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=1 FRAMES=4 CSIS_OPTS=lrte_config=0x7fff7fff bash -s' --script tools/camera-cap-test
tools/phone-ssh 'cat /tmp/cam-2016x1136.raw' > logs/camm-bars.raw
tools/raw10-stats logs/camm-bars.raw --width 2016 --height 1136 --stride 2560 --bars 8
#   pass: wdma_done 4, errors 0, 11 632 640 bytes, eight bars
#   stop: LASTADDR again: record the WDMA error line (last packet, FRM_CNT) and the bit counts;
#   next single change (one boot later): CAM 664 MHz, CSIS_OPTS=cam_khz_cphy=664000
```

- If M.5c-2 passes: 0x7fff7fff becomes the C-PHY default in the driver
  (a small commit), then M.5b-3 (4080x3072), M.6, M.7.
- **Rollback:** reboot; parameters are per load; the previous int kernel.

**CAM-M.5c results (2026-10-13, int `0470612d2` =
`7.3.0-rc6-omamobile-push1-00451-g0470612d2158`: `8070cddd9` +
`cb502b561` + `32e190c83`; same overlays):**
- **M.5c-0 (link only, LRTE 0x7fff):** FS/FE 144, 26399 link errors,
  **INT0 bit 3 (`ERR_WRONG_CONFIG`) only**: no overflow, no CRC/ECC, no
  resolution mismatch.
- **M.5c-1 (same boot, `lrte_config=0x7fff7fff`):** FS/FE 143, 23251, bit
  3 only. LRTE makes no difference on the link.
- **M.5c-2 (fresh boot, DMA, 2016x1136, `lrte_config=0x7fff7fff`):**
  "WDMA error 0x00008000 ... 2016x1136, 2560 bytes a line, 2908160 a
  frame; link last packet **0x09d86b00**, FRM_CNT 0x00000001, LRTE
  0x7fff7fff"; FS/FE 143, link errors 27890 (bit 3 only), WDMA done 0,
  256 errors, **WDMA bits 15 (`LASTADDR`) x254, 20 x2**; no data. LRTE
  is not the cause.
- **The packet at the overrun is a 2520-byte RAW10 line on VC 1**
  (identifier 0x6b): the GN1's second stream is full-width RAW10 lines,
  not small phase-detection packets.

**Why, third pass (offline):**
- WDMA bit 20 is channel 0's `OVERLAP` (GPL bit names): a frame start
  while the channel was still busy with the last frame, as expected once
  it is stuck at its last address.
- The only link error is `ERR_WRONG_CONFIG`, about 180-200 interrupts a
  frame (coalesced; consistent with one per VC 1 line, the 2016x1136
  mode's settings set a manufacturer register to 284, a quarter of the
  height, perhaps that stream's line count [I]). The link flags those
  packets as matching no channel, yet the WDMA overruns with one as the
  last header: **the VC 1 lines most likely reach WDMA channel 0
  anyway**, so channel 0 gets 1136 + N lines and hits its last address
  in the first frame. That an unmatched packet falls through to channel
  0's output is [I]; it would also explain why the ultrawide works (its
  only extra is one short embedded line a frame, a smaller overrun the
  WDMA may tolerate) and fits the earlier note that a channel on VC 1
  changed what channel 0 delivered (section 4.4).
- Our VC filter is in the right place: channel 0's config reads 0x20ac
  (VC field 20:16 = 0), channels 1-3 0x000f20fc (VC 15, data type 0x3f).
  The shared-context change (`123ac15cd`) only shares context 0 between
  links that stream one at a time; it routes nothing extra, and WDMA
  channels 1-3 are never enabled.
- Stock gives VC 1 a channel (1, with "no data type" 0x3f, section 4.4)
  and runs its RAW output on WDMA channel 2; it never leaves the VC 1
  stream unmatched. The working set-up elsewhere is what we copied (VC
  15 parking), but it may have captured with the second stream off or
  smaller (real images, not the colour bars our runs use: unknown).
- **Not CAM 664 MHz:** no overflow bit on the link or the WDMA.

**Built:** `8c93e69cb` `media: gs201-csis: choose the virtual channels of
link channels 0 and 1` (W=1 clean; defaults unchanged): `ch1_vc=N`
gives link channel 1 virtual channel N with channel 0's data type and
size (its WDMA channel stays off), so the second stream has a channel of
its own; `ch0_vc=N` makes channel 0 (and the WDMA) take VC N instead, to
capture the second stream by itself.

### CAM-M.5d: give VC 1 its own channel (and look at the second stream). Risk: medium (DMA in d-3)

```sh
# M.5d-K kernel: int + omamobile-camera 8c93e69cb, the same overlays (ASK FIRST)
tools/phone-ssh 'modinfo -p gs201_csis | grep -E "ch0_vc|ch1_vc"'
P='modprobe sec_acpm; modprobe gpio_s2mpg13; modprobe slg51002_regulator; sleep 1;'
# M.5d-0 (this boot, link only) the second stream without the colour bars
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=0 PATTERN=0 bash -s" --script tools/camera-cap-test
#   record: the INT0 b3 count per frame (M.5c: ~180) and link1+0x6a0
# M.5d-1 (same boot, link only, colour bars) VC 1 on channel 1
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=0 CSIS_OPTS=ch1_vc=1 bash -s" --script tools/camera-cap-test
#   record: b3 count (pass: about 0: every VC 1 packet now matches channel 1), any INT1
#   b5/b6 (channel 1's size differs from the second stream's: record, harmless here),
#   link1+0x050 = 0x000120ac in the scan
# M.5d-2 (same boot, link only) channel 0 on VC 1: does the second stream form frames?
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=0 CSIS_OPTS=ch0_vc=1 bash -s" --script tools/camera-cap-test
#   record: FS/FE, error bits (INT1 b6 = V size mismatch: its line count isn't 1136)
# M.5d-3 (next boot) DMA with VC 1 on channel 1; if M.5d-0 showed no VC 1 traffic
#   without the bars, use PATTERN=0 instead of ch1_vc=1 (one change either way)
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=1 FRAMES=4 CSIS_OPTS=ch1_vc=1 bash -s" --script tools/camera-cap-test
tools/phone-ssh 'cat /tmp/cam-2016x1136.raw' > logs/camm-bars.raw
tools/raw10-stats logs/camm-bars.raw --width 2016 --height 1136 --stride 2560 --bars 8
#   pass: wdma_done 4, errors 0, 11 632 640 bytes, eight bars
#   stop: LASTADDR again: record the error line and bits; next (one boot later):
#   DMA of the second stream alone (ch0_vc=1, real image) to see what it is
```

- If M.5d-3 passes: VC 1 on channel 1 becomes the driver's default for
  the S5KGN1 (a DT property for "the sensor's second stream is on VC n"
  or always giving VC 1 a data-typed channel; a small commit), then
  M.5b-3 (4080x3072), M.6, M.7.
- **Rollback:** reboot; parameters per load.
- CAM7 (front) can run in between as 7.R says.

**CAM-M.5d results (2026-10-13, int `fd0aeb894` (00453) for d-0 to d-3,
int `dd6026712` = `7.3.0-rc6-omamobile-push1-00455-gdd6026712200` (+ a
modem fix, camera unchanged) for d-4; logs `logs/camera-20261013-14*.log`):**
- **d-0 (link only, `PATTERN=0`):** FS/FE 143, INT0 b3 x29282 only: the
  VC 1 stream doesn't depend on the colour bars.
- **d-1 (link only, `ch1_vc=1`):** FS 146 FE 149, INT0 b3 x548, **INT1
  b6 (V size mismatch) x949083** (about 6500 a frame, 190 000 a second):
  channel 1 takes VC 1 now, but its height (set to 1136) is wrong for it.
- **d-2 (link only, `ch0_vc=1`):** FS/FE 143, b3 x74964 (the unmatched
  VC 0 lines now), b6 x942949.
- **d-3 (fresh boot, DMA, `ch1_vc=1`, bars):** still `LASTADDR`: FS 151
  FE 147, INT0 b3 x628, INT1 b6 x1344929, WDMA done 0, b15 x228, b20 x1.
- **d-4 (fresh boot, DMA, `PATTERN=0`, `ch0_vc=1`: VC 1 alone into the
  WDMA): clean.** FS/FE 5, WDMA done 4, errors 0 (1 dropped), INT0 b3
  x3241, INT1 b6 x43562; 11 632 640 bytes. Frame 3 holds values near the
  black level in **about the first 284 rows** (a quarter of 1136, the
  value the mode's manufacturer register carries, section CAM-M.5), the
  rest of the buffer zero: **the second stream is the phase-detection
  data, 2016 x ~284 RAW10**, and a frame shorter than programmed lands
  without an error.

**Why, fourth pass (offline):**
- d-4 also shows that **unmatched packets do not reach the WDMA** (the
  unmatched VC 0 lines didn't, there): the earlier "falls through"
  guess is wrong. So in M.5-M.5d channel 0 got only VC 0 RAW10 lines,
  each the right length (0x6a0: 2520 bytes), and still passed the end
  of a 1136-line buffer: **the VC 0 frame has more lines than 1136**
  [I], or more line packets than lines (a line split in two packets).
- The other set-up's identical register values make a sensor-side
  difference likelier than a CSIS one: the same mode list, but perhaps
  with extra rows (embedded or optical-black lines sent as RAW10 on VC 0)
  that it cropped or never noticed.
- The b6 storm in d-1/d-3 is channel 1's height (1136 against ~284); it
  doesn't affect channel 0 (d-3 overran exactly as without it). Leave
  channel 1 parked for now.
- `48e1ba5e0` `media: gs201-csis: bring-up parameter for lines past the
  frame height` (W=1 clean, default unchanged): `extra_lines=N` lets the
  WDMA take N lines past the height into buffers that much larger. A
  frame that ends early lands cleanly (as d-4), so the capture measures
  the real line count.

### CAM-M.5e: how many lines is the VC 0 frame? Risk: medium (DMA)

```sh
# M.5e-K kernel: int + omamobile-camera 48e1ba5e0, the same overlays (ASK FIRST)
tools/phone-ssh 'modinfo -p gs201_csis | grep extra_lines'
P='modprobe sec_acpm; modprobe gpio_s2mpg13; modprobe slg51002_regulator; sleep 1;'
# M.5e-1 (this, fresh, boot) VC 0 into a double-height buffer, colour bars, VC 1 parked
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=1 FRAMES=4 CSIS_OPTS=extra_lines=1136 bash -s" --script tools/camera-cap-test
tools/phone-ssh 'cat /tmp/cam-2016x1136.raw' > logs/camm-tall.raw
python3 - logs/camm-tall.raw <<'PY'
import sys
d = open(sys.argv[1], 'rb').read(); stride, rows = 2560, 2272; fsz = stride * rows
for f in range(len(d) // fsz):
    fr = d[f * fsz:(f + 1) * fsz]
    nz = [r for r in range(rows) if any(fr[r * stride:r * stride + 2520])]
    ref = fr[600 * stride:600 * stride + 2520]          # a row in the middle of the bars
    odd = [r for r in nz if fr[r * stride:r * stride + 2520] != ref]
    print(f"frame {f}: rows written {len(nz)} (last {nz[-1] if nz else None}); rows unlike row 600: {odd[:12]} ... {odd[-12:]} ({len(odd)})")
PY
#   pass: wdma_done 4, errors 0; "rows written" gives the real frame height (expect 1136 + a
#   few); the rows unlike the bars tell where the extra ones are (top, bottom, between)
#   stop: LASTADDR even at double height (then the frame is far longer, or its lines arrive
#   as more than one packet each: record, stop)
```

- Then, one change at a time: if the extra lines are at the top or
  bottom, skip them (the WDMA channel's skip register, or the link
  channel's height with the WDMA's) or have the sensor's mode not send
  them; libcamera then gets 2016x1136 as now. If they're between image
  lines, they're the sensor's phase data inline, and the next step is
  the sensor register that moves them to VC 1 (the 0x0c02 family,
  section CAM-M.5).
- **Rollback:** reboot; parameters per load.

**CAM-M.5e result (2026-10-13, int `aca2c8163` =
`7.3.0-rc6-omamobile-push1-00457-gaca2c816302f`, + `48e1ba5e0`; fresh
boot; log `logs/camera-20261013-144957-x.log`):** DMA, 2016x1136, bars,
`extra_lines=1136` (WDMA height 2272, RESOL 0x08e007e0, 5 816 320 bytes a
buffer), VC 1 parked: **`LASTADDR` again, in the first frame** ("link
last packet 0x09d86b00, FRM_CNT 0x00000001, LRTE 0x00007fff", logged
about 40 ms after the stream-on, before the sensor's 100 ms readback);
FS/FE 144, INT0 b3 x32912 only, WDMA done 0, errors 255 (b14 `LASTDATA`
x1, b15 `LASTADDR` x253, b20 `OVERLAP` x2).

**Why, fifth pass (offline):**
- Doubling the height changed nothing, and the errors come at about two
  a frame: each frame overruns, from the first. Either the VC 0 frame is
  far longer than 2272 lines, or the WDMA doesn't see VC 0's frame
  boundaries (no frame start to bring it back to the buffer's top, so it
  runs on to the end): VC 1's frames, captured alone, end cleanly.
- The VC 1 header as the last packet at the error is expected either way:
  the phase lines are interleaved through the frame, so the last header
  the link saw is often one of them; it says nothing about where the
  WDMA's data came from (d-4 showed unmatched packets don't reach it).
- **Turning the sensor's phase output off is not a clean test yet:** the
  2032x1536 mode, whose list clears 0x0c02/0x0c06, still sent VC 1 frame
  ends and the same rate of unmatched packets (M.4), so those registers
  don't switch the stream off, and the register that does is unknown
  (writing guesses into the sensor's manufacturer space is not a single
  understood change).
- `LASTDATA` (b14) once, besides `LASTADDR`: the WDMA also saw a frame end
  with data still due at least once, which fits frames whose length the
  WDMA doesn't agree with, not a bus problem.

### CAM-M.5f: the largest buffer the WDMA takes, then the stills mode. Risk: medium (DMA)

No new kernel: `extra_lines` as far as it goes. If even 8192 lines
overrun, the WDMA isn't seeing VC 0's frames end at all; if it lands, the
frame's real height is in the file.

```sh
P='modprobe sec_acpm; modprobe gpio_s2mpg13; modprobe slg51002_regulator; sleep 1;'
# M.5f-1 (fresh boot, kernel aca2c8163) VC 0, bars, WDMA height 8192 (4 x 21 MB buffers
#   from the 128 MiB pool)
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=1 FRAMES=2 CSIS_OPTS=extra_lines=7056 bash -s" --script tools/camera-cap-test
tools/phone-ssh 'cat /tmp/cam-2016x1136.raw' > logs/camm-tall.raw
#   then the M.5e row count with rows = 8192 in the snippet
#   pass: wdma_done 2, errors 0: "rows written" is the real height
#   stop: LASTADDR again (the frame never ends for the WDMA: record; next is M.5f-2)
#   or a CMA allocation failure (record CmaFree; FRAMES=2 needs only the buffers v4l2-ctl asks for)
# M.5f-2 (next boot, only if M.5f-1 overran) the mode another set-up captured whole frames in
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=4080 H=3072 DMA=1 FRAMES=2 bash -s" --script tools/camera-cap-test
#   pass: wdma_done 2, errors 0, 2 x 5120 x 3072 bytes (then the 2016x1136 mode is the outlier)
#   stop: LASTADDR: no GN1 mode captures here; record. The next step is then a kernel
#   that logs the WDMA's frame-start/end and line-end interrupt counts (they're masked now)
#   for VC 0 against VC 1, to see whether VC 0's frame starts reach the WDMA
```

- **Rollback:** reboot; parameters per load.

**The front camera (CAM7) can go now, in parallel** (independent link,
PHY, bus, sensor and supplies; the int kernel the phone runs has it):
1. F.1 (read-only, this boot).
2. F.K: `ov <the overlays the phone boots now> camera-front && bin/omamobile
   push` with `KERNEL_DIR`/`KERNEL_OUT` of the current int build (one change:
   the overlay; ASK FIRST). F.2 and F.3 on that boot.
3. F.4 (link only) on a later fresh boot; F.5 (first DMA) on its own fresh
   boot. M.5f's DMA steps and F.5 never share a boot.

**CAM-M.5f results (2026-10-13, int `aca2c8163`, fresh boots):**
- **M.5f-1 (2016x1136, `extra_lines=7056`: WDMA height 8192, 20 971 520
  bytes a buffer, CmaFree 364180 kB before, no allocation failure):**
  `LASTADDR` ("ADDR1 0xef600000 RESOL 0x200007e0 STRIDE 0x00000a00 ...
  link last packet 0x09d86b00"); FS/FE 143, link errors 29736 (b3), WDMA
  done 0, errors 190 (b14 x1, b15 x188, b20 x2), no data.
- **M.5f-2 (4080x3072, no parameters):** `LASTADDR` ("ADDR1 0xef100000
  RESOL 0x0c000ff0 STRIDE 0x00001400 ... link last packet 0x13ec2b00": a
  VC 0 RAW10 line of 5100 bytes, the right length); "link 1 on:
  4080x3072 ... CAM 533000000 Hz, INT 400000000 Hz"; FS/FE 143, link
  errors 96662 (b3), WDMA done 0, errors 2128 (b15 x2125, b20 x3).

**Why, sixth pass (offline):**
- No buffer height helps and no mode works, so the frame isn't merely
  long: the WDMA writes VC 0 lines without ever being brought back to the
  top of the buffer. **The driver's own counters say the same:** in every
  VC 0 run `missed_fe` and `dropped` stayed 0 with four buffers queued,
  so the WDMA channel's frame-start interrupt (which makes a buffer
  active, and counts a missed frame end on the next one) came at most
  once. With VC 1 captured alone (d-4) it came every frame (FS 5, done 4,
  dropped 1). **The WDMA gets VC 1's frame starts but not VC 0's** [I],
  while the link itself counts 30 frame starts a second.
- What could separate them: the per-VC frame start/end sources at link
  0x24/0x2c (which VC's FS the link sees at all), how the GN1 frames VC 0
  on C-PHY (its VC 0 frame start packet could carry a VC the link files
  elsewhere, or be missing, with VC 1's FS framing both), or which WDMA
  channel a VC's frame syncs go to. The ultrawide (D-PHY, VC 0 only)
  works with the same WDMA set-up, so it is about this sensor's stream.
- `bcc97af77` `media: gs201-csis: count frame syncs per VC and per WDMA
  channel` (W=1 clean): counts the link's per-VC FS/FE source bits and
  the WDMA's FS/FE on all four channels (now all unmasked; only the
  capturing channel drives buffers), and with `wdma_line_irq=1` its line
  ends per channel; prints the counts at the first WDMA error and per-VC
  and per-channel totals after the stop line.

### CAM-M.5g: whose frame syncs reach the WDMA. Risk: medium (DMA)

```sh
# M.5g-K kernel: int + omamobile-camera bcc97af77, the same overlays (ASK FIRST)
P='modprobe sec_acpm; modprobe gpio_s2mpg13; modprobe slg51002_regulator; sleep 1;'
# M.5g-0 (this boot, link only) the link's frame syncs by VC
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=0 bash -s" --script tools/camera-cap-test
tools/phone-ssh 'dmesg | grep -A8 "stopped:" | tail -9'
#   record: "link FS by VC" and "link FE by VC" (expect bits 0 and 1 about 143 each; a
#   missing or odd bit 0 is the answer)
# M.5g-1 (same boot, the first DMA of the boot) VC 0, with line ends counted
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=1 FRAMES=2 SECS=3 CSIS_OPTS=wdma_line_irq=1 bash -s" --script tools/camera-cap-test
tools/phone-ssh 'dmesg | grep -E "WDMA error|so far" | tail -2; dmesg | grep -A8 "stopped:" | tail -9'
#   record: "so far: WDMA FS a/b/c/d FE ... lines ..." and the totals by channel
# M.5g-2 (next boot) the same with VC 1 (the stream that works) as the reference
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=1 FRAMES=2 SECS=3 PATTERN=0 CSIS_OPTS='ch0_vc=1 wdma_line_irq=1' bash -s" --script tools/camera-cap-test
#   record: the same totals (expect WDMA FS/FE on channel 0 every frame, ~284 lines a frame)
```

- Reading it: WDMA FS on channel 0 about once in M.5g-1 but every frame
  in M.5g-2 confirms the missing VC 0 frame start; the link's FS-by-VC
  counts tell whether the link sees it; line ends per frame tell the
  real line count; FS on another channel (1-3) would show the VC 0
  frame syncs going to the wrong WDMA channel. The next change follows
  from those numbers (no guess in the sensor's registers before them).
- **Rollback:** reboot; parameters per load.

**CAM-M.5g results (2026-10-13, int `a56ad74dc` =
`7.3.0-rc6-omamobile-push1-00459-ga56ad74dc41f`, + `bcc97af77`; fresh
boot; F.1 passed earlier: gpp4-0/1/2 and gpp5-0 function 0):**
- **M.5g-0 (link only):** FS/FE 143; link FS bits: b0 x143, FE bits: b0
  x143, nothing else; INT0 b3 x25823. The per-VC source registers show
  one bit only, so they are probably per link channel rather than per VC
  [I]: channel 0's frames start and end normally on the link.
- **M.5g-1 (DMA, `wdma_line_irq=1`, bars):** "WDMA error 0x00008001 ...
  link last packet 0x09d82b00"; "so far: WDMA FS 1/0/0/0 FE 0/0/0/0
  lines 5/0/0/0 (ch 0-3); link FS VC0 1 VC1 0, FE VC0 0 VC1 0". Run
  totals: WDMA FS on channel 0 once, line ends 252 in 143 frames, WDMA
  errors 250 (b14 x1, b15 x248, b20 x2).
- Bit 0 of 0x8001 is channel 0's line end (unmasked for this run), not an
  error.

**Why, seventh pass (offline):** the WDMA took the first frame start,
then **only five line ends before running out of a 1136-line buffer**: it
isn't told where VC 0's lines end, so it writes many sensor lines as one
and never reaches a frame end. The link itself frames VC 0 normally. **And
every VC 0 DMA run so far had the sensor's colour bars on** (the
cap-test default, `PATTERN=2`), while the only clean main-camera DMA
(d-4, VC 1) ran with `PATTERN=0`, and the ultrawide's bars come from a
different sensor. A test pattern generator that sends its lines without
the per-line framing the WDMA counts (line boundaries the link passes on
with real image lines) would give exactly this [I]. It is the one
untested difference that needs no kernel, so it goes first.

### CAM-M.5h: VC 0 with a real image instead of the colour bars. Risk: medium (DMA)

```sh
P='modprobe sec_acpm; modprobe gpio_s2mpg13; modprobe slg51002_regulator; sleep 1;'
# M.5h-1 (fresh boot, kernel a56ad74dc) the M.5g-1 run with PATTERN=0
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=1 FRAMES=4 PATTERN=0 CTRLS=analogue_gain=256 CSIS_OPTS=wdma_line_irq=1 bash -s" --script tools/camera-cap-test
tools/phone-ssh 'dmesg | grep -A9 "stopped:" | tail -10'
tools/phone-ssh 'cat /tmp/cam-2016x1136.raw' > logs/camm-real.raw
#   pass: wdma_done 4, errors 0, WDMA line ends about 1136 a frame, 11 632 640 bytes; a
#   picture after a GRBG debayer (check the Bayer order and rotation here)
#   stop: LASTADDR again with a few line ends: the pattern isn't the cause; record the
#   counts. The next step is then a link-side experiment with the WDMA's line framing (the
#   link channel's pixel mode for C-PHY, a kernel parameter), one boot later
```

- If M.5h-1 passes: the bars are a test-mode artefact of this sensor;
  `camera-cap-test`'s default for `SENSOR=s5kgn1` becomes `PATTERN=0`,
  M.5b-3 (4080x3072), M.6 (gain) and M.7 (libcamera, which never turns
  the pattern on) follow, and the same caution applies to the front and
  telephoto (bars only on the link, real images for DMA first).
- **Rollback:** reboot; parameters per load.

**CAM-M.5h result and CAM7 F.1-F.3 (2026-10-13, int `a56ad74dc`, one
boot: F.K added `camera-front`; no camera DMA before M.5h-1):**
- **F.2 passed:** "s5kgn1 1-0010: S5K3J1, model 0x30a1" (the main
  sensor's "S5KGN1, model 0x08e1" probes too); `vddd_main_front` and
  `cam_sw4` off afterwards. **F.3 passed:** "1a440000.csis: link 0 -> WDMA
  context 0, 4 D-PHY data lanes"; graph `s5k3j1 1-0010` -> "gs201-csis
  link 0". (F.1 had passed: gpp4-0/1/2, gpp5-0 function 0.)
- **M.5h-1 (VC 0 DMA, `PATTERN=0`, `analogue_gain=256`,
  `wdma_line_irq=1`): the same failure:** "so far: WDMA FS 1/0/0/0 FE
  0/0/0/0 lines 5/0/0/0"; FS/FE 143, link errors 26610 (b3), WDMA done 0,
  errors 248 (last 0x00108001), b15 x247, b20 x2, line ends 253. **Not
  the test pattern.**

**Why, eighth pass (offline):**
- `LASTADDR` at every buffer height (1136 to 8192 lines) and after only
  five line ends fits a WDMA that checks each line against the stride:
  a "line" that runs past 2560 bytes because its end never came raises
  it at once, wherever the buffer ends [I]. So the one fact to explain is
  **the missing line ends for VC 0**.
- VC 1 captured alone (d-4) landed, but its line ends were never counted:
  its ~284 lines without line ends would also fill about 284 rows of
  2560 bytes and need only one frame end, so d-4 doesn't prove VC 1 gets
  them either. Counting them (M.5g-2, never run) says whether the line
  framing is missing for VC 0 only (then something VC 0-specific in this
  sensor's stream) or for this link altogether (then the C-PHY link's
  hand-over to the WDMA).
- The link channel's pixel mode (13:12: 0 single, 1 dual, 2 quad, 3
  octa [I: the field's values beyond quad are inferred]) sets how many
  pixels a clock the link hands on; the ultrawide uses quad on D-PHY and
  its line ends arrive. At CAM 533 MHz quad passes 2.1 Gpixel/s, above
  this link's 1.86 G capacity, so quad isn't too narrow; dual or single
  would overflow during a line (`ERR_OVER` expected), octa leaves room. A
  different mode changing the line framing is a long shot [I]; it is the
  last link-side setting that differs from nothing we've varied.
- `d73ed198d` `media: gs201-csis: link pixel mode as a bring-up
  parameter` (W=1 clean; default 2, unchanged).

### CAM-M.5i: line ends for VC 1, then the pixel mode. Risk: medium (DMA)

Rules for these runs: link-only runs (no DMA) may share a boot, any
number; **one DMA attempt a boot**, on a fresh boot, because a run that
hits `LASTADDR` leaves the WDMA's state unknown until the next start's
reset, and two failed DMA runs in a boot can't be told apart. A DMA run
that passes may be followed on the same boot by link-only runs.

```sh
P='modprobe sec_acpm; modprobe gpio_s2mpg13; modprobe slg51002_regulator; sleep 1;'
# M.5i-0 (fresh boot, kernel a56ad74dc or later) the reference: VC 1 with line ends counted
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=1 FRAMES=4 PATTERN=0 CSIS_OPTS='ch0_vc=1 wdma_line_irq=1' bash -s" --script tools/camera-cap-test
tools/phone-ssh 'dmesg | grep -A9 "stopped:" | tail -10'
#   expect: wdma_done ~4, WDMA FS/FE on channel 0 every frame. Record the line ends per
#   frame: ~284 = VC 1 has line framing (the problem is VC 0-specific: go on with i-1 anyway,
#   and the next offline step is the sensor's VC 0 stream); ~1-5 = no line framing on this
#   link at all (the pixel mode runs below matter more)
# M.5i-K kernel: int + d73ed198d, the same overlays (ASK FIRST)
# M.5i-1 (that boot, link only) every pixel mode on the link, one run each
for m in 1 3 0; do
  tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=0 PATTERN=0 CSIS_OPTS=pixel_mode=$m bash -s" --script tools/camera-cap-test
  tools/phone-ssh 'dmesg | grep -A4 "stopped:" | tail -5'
done
#   record per mode: FS/FE (~143), the INT0 bits (b3 as always; b4 ERR_OVER expected for 0
#   and perhaps 1), and link1+0x040 in the scan (pixel mode in 13:12)
#   stop: no frames or a hang in a mode: don't take it to DMA
# M.5i-2 (next boot) DMA, dual (1)
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=1 FRAMES=4 PATTERN=0 CSIS_OPTS='pixel_mode=1 wdma_line_irq=1' bash -s" --script tools/camera-cap-test
# M.5i-3 (next boot, only if i-2 failed) DMA, octa (3)
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=1 FRAMES=4 PATTERN=0 CSIS_OPTS='pixel_mode=3 wdma_line_irq=1' bash -s" --script tools/camera-cap-test
# (single, 0, only if i-1 showed it clean on the link: it can't keep up with this link)
#   pass (any): wdma_done 4, errors 0, line ends ~1136 a frame (4 x 1136 = 4544 in all,
#   plus a few), 11 632 640 bytes, a picture
#   fail: the same five line ends: record; the pixel mode isn't it
```

- **After i-0 and i-2/3:** if VC 1 has line ends and no pixel mode gives
  VC 0 any, the cause is in how the sensor sends VC 0 in these settings
  (the next offline step: what the HAL's GN1 driver writes beyond the
  mode lists for C-PHY output, e.g. the sensor-side line-start/line-end
  packets), not the CSIS. If neither stream has line ends, it is the
  C-PHY link's hand-over: then the link registers the stock HAL writes
  through its field setters that we don't (section 4.3, RE2) are next.
- **Rollback:** reboot; parameters per load.

**CAM-M.5i results (2026-10-13, int `7e9131775` =
`7.3.0-rc6-omamobile-push1-00463-g7e9131775953`, + `d73ed198d` and a
modem fix; fresh boot; libcamera 0.7.2-4.6 installed, not used yet; logs
`logs/camera-20261013-153*.log`):**
- **i-1 (link only, 2016x1136):** `pixel_mode=1` (dual): FS/FE 144, INT0
  b3 x40532, **b4 (`ERR_OVER`) x73887**; `pixel_mode=3` (octa): FS/FE
  142, b3 x26046 only, as clean as quad; `pixel_mode=0` (single): FS/FE
  144, b3 x40172, **b4 x69841**. Dual and single overflow on the link, as
  expected; octa and quad don't.
- **i-0 (the boot's one DMA, VC 1 alone, `ch0_vc=1 wdma_line_irq=1`,
  `PATTERN=0`):** link FS/FE (channel 0) 4/4, WDMA FS 4, FE 4, **line
  ends 1021 (about 255 a frame)**, INT1 b6 x26930 (channel 0's height
  1136 against VC 1's ~284), 11 632 640 bytes. **VC 1 has its line
  framing; VC 0 doesn't** (M.5g/M.5h: five line ends, then `LASTADDR`).
- i-2/i-3 (DMA in dual/octa) skipped: dual overflows on the link.

**Why, ninth pass (offline):**
- The streams differ in timing more than in kind: both are 2520-byte
  RAW10 lines with frame syncs, but **VC 0's lines come back to back at
  the link's full rate** (2.3 us a line in these settings, ~1.1 GB/s
  during a line, the link's capacity figure 1862 Mpixel/s), while VC 1's
  come about one in four. Lines the WDMA loses line ends on while VC 1's
  arrive fine is a throughput sign between the link and the WDMA, not a
  framing one [I]; the link itself doesn't overflow in quad (no b4), but
  the CSIS-to-WDMA side runs on the CAM clock (533 MHz) and the WDMA on
  INT (400 MHz).
- That matches the earlier finding on another set-up (section 4.4): at a
  CAM vote of 400 MHz this sensor's link overflowed and the WDMA stopped
  part-way with `LASTDATA`/`LASTADDR`; 533 MHz was enough there for the
  same mode, but **our link runs faster** if the output PLL is the symbol
  rate (2716 Msps against the ~1600 that set-up estimated; section 4.5,
  open question 16). So CAM 664 MHz (the top of the CAM DVFS table) goes
  back on the list, ahead of anything sensor-side.
- **Sensor side (offline, the HAL):** our data file is the HAL's default
  init list and mode lists in full; the GN1 driver's other code paths in
  the library are a soft reset and clock enable (ours too), stream on,
  a "boost settings" path, an OTP read for calibration, and a per-phone
  gate-voltage file under `persist` (read only by the HAL). None of these
  names a MIPI framing or line-packet setting; the C-PHY framing
  registers (lane count 0x0114, 0x0118, data format 0x0112) are in the
  lists we write. So no sensor write is indicated yet.
- Octa (clean on the link) is the other cheap DMA try: if the hand-over
  is per clock, eight pixels a clock halves its rate.

### CAM-M.5j: the CAM clock at its top, then octa. Risk: medium (DMA)

No new kernel (`cam_khz_cphy` and `pixel_mode` exist); one DMA attempt a
fresh boot.

```sh
P='modprobe sec_acpm; modprobe gpio_s2mpg13; modprobe slg51002_regulator; sleep 1;'
# M.5j-1 (fresh boot) VC 0, real image, CAM 664 MHz
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=1 FRAMES=4 PATTERN=0 CTRLS=analogue_gain=256 CSIS_OPTS='cam_khz_cphy=664000 wdma_line_irq=1' bash -s" --script tools/camera-cap-test
tools/phone-ssh 'dmesg | grep -E "link 1 on|so far" | tail -2; dmesg | grep -A9 "stopped:" | tail -10'
#   check: "CAM 664000000 Hz" in the link-on line (if lower, the vote was capped: record)
#   pass: wdma_done 4, errors 0, line ends ~1136 a frame, 11 632 640 bytes, a picture
# M.5j-2 (next boot, only if j-1 failed) octa at the default CAM 533 MHz
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=1 FRAMES=4 PATTERN=0 CSIS_OPTS='pixel_mode=3 wdma_line_irq=1' bash -s" --script tools/camera-cap-test
# M.5j-3 (next boot, only if both failed) both together
tools/camera-stage --watchdog x --cmd "$P LINK=1 SENSOR=s5kgn1 W=2016 H=1136 DMA=1 FRAMES=4 PATTERN=0 CSIS_OPTS='cam_khz_cphy=664000 pixel_mode=3 wdma_line_irq=1' bash -s" --script tools/camera-cap-test
#   in each: record the line ends at the first error ("so far") and in all: more line
#   ends before the error than M.5h's five means the change helps
```

- If all three fail: slow the sensor instead (its output post-divider and
  a doubled line length halve the link rate, the change that let a whole
  frame through at 400 MHz on the other set-up), as a data-file variant
  for one test, and the INT vote above 400 MHz.
- **Rollback:** reboot; parameters per load.

**CAM-M.5j-1 result (2026-10-13, int `7e9131775`, fresh boot):** VC 0,
2016x1136, `PATTERN=0`, `cam_khz_cphy=664000`: "link 1 on" with "CAM
664000000 Hz"; "so far: WDMA FS 1/0/0/0 FE 0/0/0/0 lines 4/0/0/0; link
FS VC0 1 VC1 0, FE VC0 0 VC1 0"; FS/FE 143, link errors 25723 (b3), WDMA
done 0, errors 246 (last 0x00108001; b15 x245, b20 x2), line ends 251, no
data. **The CAM clock isn't it** (four line ends before the error, as at
533 MHz).

**Where we stopped (2026-10-13, hardware work paused):**
- Main camera: the sensor, its C-PHY link (30 fps, only VC 1 packets
  unmatched) and the phase stream on VC 1 (captured whole, with line
  ends) work; the VC 0 image reaches the WDMA without line ends, so every
  frame stops at `LASTADDR`. Ruled out: the 2032x1536 mode, the WDMA
  start value, LRTE, the test pattern, buffer height up to 8192 lines,
  the 4080x3072 mode, VC 1 on its own link channel, CAM 664 MHz;
  dual/single pixel modes overflow on the link.
- **Next options, in order** (one DMA attempt a fresh boot, no new
  kernel for the first two): M.5j-2 octa (`pixel_mode=3`) at 533 MHz;
  M.5j-3 octa with 664 MHz; then the sensor slowed (its output
  post-divider and a doubled line length, as a one-off data-file
  variant) together with an INT vote above 400 MHz.
- Front camera: F.1-F.3 passed (the S5K3J1 answers, link 0's graph is
  up); F.4 (link only) and F.5 (first DMA, its own boot) next.
- Telephoto: not started on the phone (CAM-T).
- libcamera 0.7.2-4.6 is installed on the phone, not used for a capture
  yet (CAM5.3-1 is the first run with it).

**The front camera (CAM7), on the next boot that has no camera DMA step**
(it can be M.5g-K's boot, if M.5g-0/-1 move to the boot after, or the boot
after M.5g-2):

```sh
# F.1 (read-only, any boot)
tools/phone-ssh 'grep -E "gpp4-[012]|gpp5-0" /sys/kernel/debug/pinctrl/*/pins 2>/dev/null | head'
# F.K images: the int build the phone runs plus camera-front (ASK FIRST: flashes, reboots)
KERNEL_DIR=~/android/mainline/wt-int KERNEL_OUT=~/android/mainline/out-int \
    ov <the overlays of the current int images> camera-front && bin/omamobile push
# F.2 (that boot) power-up and chip ID
tools/camera-stage --watchdog x --cmd 'modprobe sec_acpm; modprobe gpio_s2mpg13; modprobe slg51002_regulator; modprobe s5kgn1; sleep 1; dmesg | grep -E "s5kgn1|slg51002" | tail -6; grep -E "ldo12s|vddd_main_front|cam_sw4" /sys/kernel/debug/regulator/regulator_summary'
#   pass: "s5kgn1 N-0010: S5K3J1, model 0x30a1" (and the main camera's line as before);
#   LDO8 and switch 4 off afterwards
# F.3 (same boot) the graph
tools/phone-ssh 'modprobe phy_gs201_mipi_dcphy_rx; modprobe gs201_csis; sleep 1; dmesg | grep "link 0 ->"; for d in /dev/media*; do media-ctl -d $d -p | grep -E "s5k3j1|link 0"; done'
#   pass: "link 0 -> WDMA context 0, 4 D-PHY data lanes"; "s5k3j1 N-0010" -> "gs201-csis link 0"
```

### CAM-M.5k and F.4: overnight runs (2026-10-13/14). Risk: medium (DMA)

One DMA attempt a fresh boot throughout. Kernel commits on
`omamobile-camera` (all bring-up parameters, defaults unchanged, W=1
clean), each merged into `omamobile-int` and pushed:

| Commit | Parameter |
|---|---|
| `d35fc97cf` | gs201_csis `wdma_late=N` (enable the channel from the link interrupt at the Nth link frame end), `cmn_cfg_csis1=0` (leave DMA common 0x48 alone; its value is logged) |
| `09f7627b4` | gs201_csis `wdma_recover=1` (channel off at an error, on again at the next link frame end) |
| `04d6c778a` | gs201_csis `wdma_after_link=1`, `data_ctrl_clear=1`, `qurgent=0` (order and values of a set-up known to capture this camera) |
| `6359944ae` | gs201_csis `link_rmw=1` (read-modify-write the common control and channel configs; the values after the soft reset are logged) |
| `6f85a34bc` | gs201_csis `int0_mask=`; s5kgn1 `basic_ctrls=1` (no digital gain or zero test pattern writes) |
| `420da1faa` | s5kgn1 `extra_regs="addr=val,..."` (writes after the mode tables) |

Results, all VC 0, 2016x1136, `PATTERN=0` unless said (logs
`logs/camera-20261013-21*.log`):

- **F.4 passed** (int `0db95c439`, 00470): "link 0: D-PHY 4 lanes at
  1665024000 bps, settle 8"; FS/FE 147 in 5 s (30 fps); link errors 148,
  INT0 b3 (`ERR_WRONG_CONFIG`) only, once a frame, as on the ultrawide.
- **M.5j-2 (octa, same boot as F.4, 00470): fails differently.** WDMA
  done 1, errors 152: b14 (`LASTDATA`) x151, b15 x148; WDMA FS 2, FE 1;
  the first error came before the sensor's stream-on returned.
- **wdma_late=2 (00472):** "WDMA started at link frame end 2"; the first
  error in the next frame after hundreds of line ends ("so far ... lines
  618", interrupt-coalesced, a lower bound; M.5h: 5); WDMA FS 1 in the run.
  **The early start explained the "five line ends", not the failure.**
- **cmn_cfg_csis1=0 (00472):** "DMA common 0x48 was 0x00000100" on a fresh
  boot: our write never changed it. Same failure.
- **wdma_recover=1 (00474):** errors at link frames 3, 4 and 5, then the
  channel took no frame start and raised no error for the rest of the run:
  switching the enable bit off and on doesn't revive it.
- **The reference set-up's WDMA order and values together** (00476:
  `wdma_late=1 wdma_after_link=1 data_ctrl_clear=1 qurgent=0 wdma_ctrl=3
  lrte_config=0x7fff7fff`): same failure. Data control read 0, QURGENT 0.
- **+ link_rmw=1** (00478): the link after its soft reset reads CMN_CTRL
  0x00004000, ISP_CONFIG 0x000n00fc (VC n, data type 0x3f), DBG 0: nothing
  for read-modify-write to keep. Same failure.
- **+ int0_mask=0** (00480, no link error interrupts; 288 instead of
  ~21000): same failure.
- **+ s5kgn1 basic_ctrls=1, frame length 14528 (even)** (00480): same
  failure.

- **s5kgn1 extra_regs=0x0312=2,0x0342=6000** (00482, half the output
  rate, 30 fps at frame length 7264: the frame rate confirms the line
  length took effect): same failure ("so far ... lines 426"). **0x0342=6000
  alone** (twice the horizontal blanking at the full link rate): same
  ("lines 443"). Not the line timing.
- **wdma_late=1 extra_lines=1136** (double height, 00482): same failure.
- **keep_failed=1 wdma_recover=1, bars, cached_buffers=0** (00486): the
  buffer the error ended is **all zeros**: the WDMA wrote no data at all.
  The DMA block's debug counters (0x100 = 1; context 0's line/data count
  at 0x154) read lines 0x39-0x53, data 0-0x65 at the first error; frames
  0x90 at stop (the counter sees every frame). The sensor powered before
  the link (`PRE_STREAM`: runtime PM control "on"): same.
- **The telephoto fails the same way (T.5, below)**: both C-PHY cameras,
  neither D-PHY camera.

**Why (offline):** with these, our link, PHY (per-trio registers read
back identical: 0x1450, 9, 0x82b8, 1, 0x8600, 0x4000, 0x200, 0x638, 0x40,
settle 7, 0x32, 0x1503, 0x32), WDMA and sensor controls match the set-up
known to capture this camera, register for register, and the channel
still loses a line end within its first frame. What is left: the timing
on the wire (the sensor's output rate: 2716 Msps per trio by its output
PLL) against the link-to-WDMA hand-over; the next test halved it (above): no change.
So the C-PHY links' VC 0 data (and the telephoto's) never reaches memory
while its syncs reach the WDMA; the ultrawide and the front (D-PHY) and
the main camera's VC 1 stream (sparse lines) land. Next hypotheses, each
one boot: SC_CON values other than 1 (`sc_con=2..7`: the "PDP mux" is the
one known switch between syncs-only and data), CSIS sysreg 0x488 bits for
the link (`sysreg_link_sel=1`), and the HAL's C-PHY link start (REA on
`liblyric_hwl.so`: what it writes for a C-PHY context besides the common
control).

**CAM7 F.5-F.7 (2026-10-13, 00482/00486): the front camera works.**
- **F.5 bars (00482, fresh boot):** "link 0 on: 1920x1368 ... 4 lanes ...
  CAM 400000000 Hz, INT 400000000 Hz"; FS/FE 4, WDMA done 4, errors 0;
  13 307 904 bytes; eight clean bars **starting at row 0, column 0**
  (every even row equals row 600): channel 0's RAW10 filter drops the
  leading 4224 words (question 12 answered).
- **F.5 real image (same boot, `analogue_gain=256`, exposure 4716):** 8
  frames, errors 0; p50 ~90, p99 ~830: a real scene (the room's ceiling
  lamp, shelves, a microphone, a monitor), GRBG debayer correct.
- **F.7 (libcamera 0.7.2-4.6 + libcamera-tools installed for `cam`):**
  `cam -l` lists four cameras (front `.../camera-sensor@10`, main `@3d`,
  ultrawide `@1a`, telephoto `@2d`); `cam -c1 ... 1912x1368 RGB888`: 60
  frames at 30.0 fps, WDMA errors 0; the picture right-coloured.
- **Ultrawide regression (00486):** libcamera 60 frames at 30 fps, WDMA
  errors 0; raw bars clean. The scene was black (black level 64 at the
  longest exposure and gain 480: the rear cameras faced darkness tonight),
  so its picture couldn't be judged.

**CAM-T T.1-T.5 (2026-10-13, 00482-00486, overlay `camera-tele` added to
`device.conf`):**
- **T.1 passed:** gpp6-2, gpp7-0, gpp8-0/1 inputs, gpp8-2 output low
  (torch HWEN), all unclaimed.
- **T.2 passed:** "s5kgn1 3-002d: S5KGM5, model 0x08d5, vertical flip".
- **T.3: the lens doesn't answer:** "sem1215 3-0034: Error reading reg
  0x0201: -6", "no focus calibration (-6), range 0-1023". Stock powers
  the SEM1215SA with the sensor's sequence; with only its own supplies it
  NACKs [I]. Not needed for a picture; next: power it after the sensor.
- **T.4 passed:** "link 4 -> WDMA context 0, 2 C-PHY trios, LRTE packet
  delimiters"; "link 4: C-PHY 2 trios at 1802240000 sps, settle 7";
  0x600 = 0xffff7fff; FS/FE 135 (30 fps); INT0 b3 only (~325 a frame: a
  second stream, as on the main camera).
- **T.5 (bars, fresh boot): fails like the main camera:** WDMA FS 1,
  errors 223 (b14 x28, b15 x223), no data. (Without the lens driver loaded
  the sensor's format couldn't be set: `LENS=1` is needed.)

### CAM-M.5l: the fix, lines no faster than the WDMA takes them (2026-10-14)

Kernel `omamobile-camera` (built W=1 clean, merged into int, pushed):
bring-up options `keep_failed`, debug counters (DMA 0x100 = 1, context
counters at 0x144/0x154 logged at the first error and at stop),
`sc_con`, `link_sel_bits`, `wdma_rows`, `wdma_fmt`, `all_slots`,
`bw_limit0-2` (WDMA 0x560-0x568, read 0 on the phone), s5kgn1
`extra_regs`, camera-cap-test `PRE_STREAM`; and the fix:
`6c66d7456` (binding `samsung,max-line-throughput`), `15e0166b0` (s5kgn1
writes a longer 0x0342 where a mode's lines would exceed it),
`1e8739197` (cheetah: 360 MB/s for the main and telephoto sensors).

Results (00490-00500, main camera unless said):
- Every VC 0 run before the fix wrote **no data at all** (buffers handed
  back with `keep_failed=1` all zeros) in formats 7, 6 and 0, on WDMA
  channel 1 too, with SC_CON 7, with 0x488 bits for link 1, with all 32
  address slots valid, with a 32-row WDMA frame and with a 284-line
  sensor output.
- The sensor's second stream is the phase data and can be switched off:
  `0x0b02 = 0` (link errors from ~200 to 2 a frame); the image moves to
  VC 1 with `0x0110 = 0x0102`. Neither helped: **the image on VC 1 failed
  like on VC 0**, so the stream's VC is not the cause; the phase stream
  (one line in four) landed because its lines are sparse.
- **Line length decides** (link rate unchanged, `extra_regs=0x0342=N`):
  2016x1136, 2520-byte lines: 3000 (2.3 us) fails, 6000 (4.6 us) fails,
  7500 (5.7 us) fails, **9000 (6.9 us) lands every frame**, 12000 lands;
  4080x3072, 5100-byte lines: 11552 (8.8 us) fails, **17328 (13.2 us)
  lands**. About 400 MB/s within a line is the limit; CAM 664 MHz with INT
  533 MHz and the octa pixel mode don't move it. The D-PHY cameras stay
  under it (ultrawide 271 MB/s, front 343 MB/s).
- **With the fix and default options (00500):** main 2016x1136 raw: 4 of
  4 frames, errors 0, eight clean bars; 4080x3072: 3 of 3, errors 0;
  libcamera (`cam -c2`, 2008x1136): 91 frames at 30.0 fps, errors 0.
  Telephoto 2016x1512: bars clean (BGGR as flipped: libcamera shows the
  eight bars in the right colours), raw 30 of 30 frames, errors 0;
  4032x3024: 3 of 3; libcamera 91 frames at 26 fps, errors 0.
- Pictures (raw long exposures, not committed: the room): **main** a sharp
  real scene; **ultrawide** a real scene, upside down against the main
  (mounted the other way: rotation 270 [I], as question 14 suspects);
  **front** a real scene; **telephoto** only blurred shapes at 8 DN over
  black (dark side of the room, lens at its stop).
- Costs of the limit: the main camera's 4080x3072 mode runs at most about
  9 fps (18526 clocks a line), 2016x1136 up to about 128 fps; the
  telephoto's 2016-wide modes about 30 fps.

**Follow-ups (00502-00504):**
- `dcf09ccb2` (int) / camera `media: gs201-csis: don't lose the first
  buffer when streaming starts late`: with `min_queued_buffers = 2`, vb2
  calls buf_queue with the queue already streaming when STREAMON came
  before the buffers (libcamera's order), so the first buffer was taken
  and then replaced: "videobuf2_common: driver bug: stop_streaming
  operation is leaving buffer 0 in active state" after every libcamera
  run. Now: no warning in 12 libcamera start/stops (each camera twice or
  more), WDMA errors 0 in all.
- **The limit is the WDMA's, not C-PHY's:** libcamera's default size for
  the front is its 3840x2736 mode (4800-byte lines at 11.6 us, ~414 MB/s),
  which lost its lines the same way; the front gets
  `samsung,max-line-throughput = <360>` too and that mode now runs at 26
  fps. The ultrawide's full mode (5040-byte lines at ~10.8 us, ~467 MB/s)
  is the same failure (CAM5.2c's `LASTADDR`); the imx386 driver needs the
  same rule.
- libcamera's default size for the main and telephoto is the full mode;
  its RGB888 output buffers (4 x 37 MB) then fail to allocate ("dma-heap
  allocation failure"), a CMA-size limit, not a driver one. The binned
  sizes run (main 30 fps, telephoto 26 fps).

- **Telephoto lens (00506-00508, reverted in 00511):** letting the
  SEM1215SA's ready poll wait through NACKs (2 ms before the first read,
  up to 500 ms) made it worse: with its own supplies on for more than a
  few milliseconds the controller's reads time out ("exynos5-hsi2c
  10930000.i2c: tx timeout", -110) and **hsi2c_4 stays stuck until a
  reboot**, so the telephoto sensor's own chip-ID read fails too. The
  original driver (one immediate read, a NACK, supplies off) leaves the
  bus working. Both commits are reverted (`174134912`, `3e5457525`); with
  them out, all four cameras ran twice each through libcamera on 00511
  with no WDMA error, no bus timeout and no vb2 warning. Stock's bus has
  `samsung,reset-before-trans` (a controller reset before every
  transfer) and pin states for on/off; the lens is next tried with the
  bus reset before each transfer, read-only, on its own boot.

Next:
1. Telephoto lens: the SEM1215SA NACKs at 0x34 with its own supplies;
   stock powers it inside the sensor's sequence (power it after the
   sensor, then retry T.3/T.6).
2. M.6/F.6 gain models, M.7/T.7 autofocus in libcamera, rotations
   (question 14) with a picture of text per camera.
3. Whether the 400 MB/s limit is the WDMA's write path (a bus QoS or
   burst setting) rather than fixed: then the full-rate modes come back.

### CAM5.3: ultrawide quick wins. Risk: low to medium

```sh
# 5.3-1 (userspace) libcamera 0.7.2-4.6: AF patches, digital gain, tuning, the
#   front and telephoto sensors, the near-size mode rule (0014: a 2016x1508
#   request now runs the binned mode, adjusted to 2008x1508)
tools/phone-install-package packages/libcamera
tools/phone-ssh 'pacman -Q libcamera; cam -l'
# 5.3-2 (kernel with the gs201-csis changes above; ASK FIRST) cached buffers:
#   same scene, 300 frames, compare the frame rate and CPU with cached_buffers=0
tools/phone-ssh 'modprobe -r gs201_csis; modprobe gs201_csis cached_buffers=0; time cam -c1 --capture=300 --stream pixelformat=RGB888,width=2008,height=1508 >/dev/null'
tools/phone-ssh 'modprobe -r gs201_csis; modprobe gs201_csis; time cam -c1 --capture=300 --stream pixelformat=RGB888,width=2008,height=1508 >/dev/null'
#   pass: the cached run is at least as fast, the pictures identical in quality (no stale lines)
#   stop: torn or stale frames with cached buffers (a missing cache sync): back to cached_buffers=0
# 5.3-3 (next boot, overlay camera-uw-lens on top) the ultrawide's lens
tools/phone-ssh 'modprobe ak7375; for d in /dev/media*; do media-ctl -d $d -p | grep -A2 ak7375; done'
tools/phone-ssh 'v4l2-ctl -d /dev/v4l-subdevN --set-ctrl focus_absolute=1400'   # a desk at 0.5-1 m
#   then cam with IPASoftAf:0 as M.7 on the ultrawide, a subject at 10-20 cm
#   pass: the lens moves (audible tick, focus changes), AF settles; no I2C errors
# 5.3-4 full resolution: CAM5.2c, with 5.2c-4 (wdma_ctrl=3) tried first
```

Note on 5.3-3: libcamera opens the lens subdev for as long as a camera
manager runs, and the ak7375 driver powers the VCM (LDO12S + LDO4) on
open: with PipeWire's libcamera plugin loaded, the lenses stay powered.
Measure the idle current before shipping it (POWER-PLAN); a fix is
runtime PM tied to streaming in the ak7375 driver or in libcamera.

### CAM5.4: a camera app (GNOME Snapshot) and loading at boot. Risk: low

1. `pacman -S snapshot pipewire-libcamera` (Arch Linux ARM). Snapshot
   finds cameras through the camera portal and PipeWire's libcamera SPA
   plugin; check `wpctl status` lists them (Video sources), then open
   Snapshot and take a screenshot (verify-UI rule). Things to expect:
   Snapshot asks for a preview size and its photo is a preview frame;
   the rotation may not be applied by every PipeWire version (the DT's
   `rotation` reaches libcamera as `Rotation`); the first frames are dark
   until the AGC settles.
2. When it lists and previews: move `snapshot` (and `pipewire-libcamera`)
   from `optdepends` to `depends` in `omamobile-apps` (bump its version).
3. Loading at boot (after CAM-M, CAM7 and CAM-T pass and the overlays
   move into the default DT): drop `imx386`, `s5kgn1`, `ak7375`, `sem1215`,
   `phy_gs201_mipi_dcphy_rx`, `gs201_csis` (and the PMIC modules they need)
   from `omamobile-camera.conf` in a new device-cheetah version, or load
   them from a oneshot unit ordered after the regulators, as the AoC unit
   does. Nothing powers a sensor until a stream starts, except the lens
   (above) and each sensor's chip-ID read at probe.

**CAM5.4 result (2026-10-14, int `4fb221c0a` =
`7.3.0-rc6-omamobile-push1-00533-g4fb221c0aafc`, device-cheetah 0.1.31,
omamobile-apps 0.1.1): GNOME Snapshot works with all four cameras.**
- `snapshot` 51.0 and `pipewire-libcamera` 1.6.9 (Arch Linux ARM) are now
  `depends` of omamobile-apps.
- **Loading at boot:** the modules stay blacklisted for autoload;
  `omamobile-camera.timer` runs `omamobile-camera-start` 40 s into the boot
  (PMIC drivers, sensors and lenses, DC-PHY, CSIS; a marker skips the next
  boot's load if one never finished). On the phone: "camera drivers
  loaded; 4 media devices", no I2C timeout, no vb2 warning.
- **The session couldn't debayer:** WirePlumber (the user's) logged "Could
  not open any dma-buf provider": the DMA-BUF heaps were root-only, so
  libcamera's software ISP was off and apps got no usable format
  (`pipewiresrc`: "target not found"). `70-omamobile-dma-heap.rules` gives
  the video group and the seat's user `system`, `reserved` and
  `default_cma_region`; the rule applies when the heaps appear at boot,
  before the session.
- **Names and order:** `50-omamobile-cameras.conf` (WirePlumber) names the
  sources by their sensor's DT path (checked against the bound drivers:
  `0-003d` S5KGN1, `2-001a` IMX386, `3-002d` S5KGM5, `1-0010` S5K3J1):
  "Main camera" (default, priority 1000), "Front camera", "Ultrawide
  camera", "Telephoto camera", and disables the raw CSIS v4l2 devices.
  `gst-device-monitor-1.0 Video/Source` as the user lists the four names.
- **Rotations (question 14 answered):** with the phone upright, Snapshot
  showed the main camera upright and the other three upside down. The DT
  now has main 90, ultrawide 270, telephoto 90 (still vertically flipped),
  front 90; PipeWire reports `api.libcamera.rotation` 90/270/90/90. The
  ultrawide's raw frames were already upside down against the main's
  (its module is mounted the other way). The owner checks the result.
- Snapshot picks the binned modes (2016x1136 on the back cameras,
  1920x1116 on the front); the owner switched through all four, every
  stream with WDMA errors 0.
- **Main camera autofocus works** (M.7): `cam` with `IPASoftAf:0` on the
  main camera: coarse and fine sweeps, "Autofocus completed at 925". The
  ultrawide has no lens control on these images (the `camera-uw-lens`
  overlay isn't in `device.conf` yet: one boot to add).
- Open: the telephoto's lens (it NACKs; longer waits hung its bus, CAM-T
  T.3), so the telephoto has no autofocus. It stays at its resting focus:
  sharp on distant subjects outdoors, soft on close ones indoors (seen
  2026-10-26); the main and ultrawide AK7375
  lenses stay powered while PipeWire holds their subdevs (power: measure).

**CAM5.4 follow-ups (2026-10-14, 00533-00543):**
- **Ultrawide autofocus:** `camera-uw-lens` joins `device.conf`; libcamera's
  contrast AF sweeps the AK7375 (sharpness 46 000-198 000 across the
  sweep) and completes. The two AK7375s log "ak7375_vcm_resume I2C
  failure: -6" once when WirePlumber first opens them at 40 s; later opens
  work.
- **Snapshot photos are 1080p by design:** its camera library caps the
  stream at 1080 lines (`aperture/src/utils.rs`: `MAX_HEIGHT = 1080`) and
  takes photos from that stream. Our side isn't the limit: PipeWire offers
  sizes up to 3840x2400, and a 3840x2160 stream from the main camera ran
  through PipeWire (the 4080x2288 mode, WDMA errors 0). Higher-resolution
  photos need a patched Snapshot or another app.
- *(Superseded 2026-10-26: later boots found the lens holds its I2C bus when driven, so the telephoto runs fixed-focus, sharp at distance and soft up close; see this plan's status line and [DEVICES](../../docs/DEVICES.md). The entry below is kept as the record of that test.)*
- **Telephoto lens works** (int `1f83c16c0` = 00543): the SEM1215SA answers
  only while its sensor is powered, as stock powers it inside the sensor's
  sequence. Read-only first (00535, `boot_ms=20`, opened during a stream):
  positions read back 217→220, 248→246, no bus error. Now s5kgn1 holds its
  lens-focus device powered while it streams, sem1215 no longer powers on
  open (WirePlumber keeps lens subdevs open), waits 20 ms after its
  supplies and reads the calibration at the first stream ("focus range
  142-664 (calibrated 182-624)"). libcamera AF: "Autofocus completed at
  450", every move read back within a few codes; no I2C timeout in two
  runs. The telephoto bus also runs at 950 kHz now (`b267e0dd4`): mainline
  i2c-exynos5 runs 1 MHz as high-speed mode, which stock doesn't.
- **Telephoto rotation 270 again** (with its vertical flip): upside down at
  90 once Snapshot named the cameras; the earlier "upside down at 270" came
  while the three back cameras were indistinguishable. The owner checked
  text on 00543: upright, not mirrored. All four rotations are now
  confirmed (main 90, ultrawide 270, telephoto 270 with the vertical flip,
  front 90).
- **Snapshot crash after photos (not a camera bug):** GTK 4.24 exports GL
  textures as dmabufs for its Vulkan renderer; Mesa's panfrost makes every
  resource without `PIPE_BIND_SHARED` a BO private to its GPU VM, and
  panthor refuses to export those (-EINVAL: "We can't export GEMs that
  have an exclusive VM"). Every export failed ("drmPrimeHandleToFD() failed
  (err=22)"), GTK built a texture with no fd, and Snapshot crashed in
  `gsk_renderer_render_texture`. Fix in `packages/mesa` 0002 (images always
  shareable, buffers stay private); upstream recorded the same failure as
  a CI expectation in 2023 ("panfrost: Add spec@egl 1.4@egl-ext_egl_image_storage
  to the list of failures").
- **AGC from a dark start:** libcamera 0.7.2-4.7 (`0015`) doubles or halves
  the exposure while the histogram is pinned at an end, instead of 15% a
  frame (the front camera took seconds to brighten).

**CAM5.4, later on 2026-10-14 (00545-00554, libcamera 4.7-4.8, Mesa 1.2):**
- **Ultrawide full mode at 330 MB/s** (`sony,max-line-throughput`, 00545):
  5 x 21 frames of 4032x3016, WDMA errors 0 (one run at 360 had dropped
  lines).
- **CMA exhaustion in camera apps was a libcamera leak:** the GPU debayer
  made a new EGL context at every start and never destroyed the old one,
  which kept its last buffers imported; omacam held 290 MiB (software ISP
  output in the default CMA, camera buffers in the camera pool) after
  closing the camera, and later starts failed with "Cannot allocate
  memory". Hyprland's buffers were not the cause (GPU buffers from normal
  memory, scanout from `display-pool`). libcamera 4.8 (`0016`) destroys the
  context at stop; restarting WirePlumber returned 22 MiB it had leaked.
- **AGC from a dark start** (4.7, `0015`): doubles or halves the exposure
  while the histogram is pinned at an end.
- **Snapshot crash** fixed in Mesa 1:26.2.4-1.2 (`packages/mesa` 0002).
- **Main camera blurry in apps:** both AK7375 VCMs ignore writes for the
  first seconds after the camera drivers load (still after 250 ms of
  retries), so WirePlumber's lens open failed and libcamera dropped the
  lens for the session. The driver now keeps an unanswering VCM powered,
  lets the open succeed and sets it up at the first move (00554); main
  camera AF completes in libcamera.
- **No WARN when the camera pool is full** (`__GFP_NOWARN`; not
  `DMA_ATTR_NO_WARN`, which the non-coherent allocation refuses: tried on
  00548, every capture failed, fixed in 00550).
- **Telephoto yellow photos (omacam):** libcamera's white balance on the
  telephoto matches the raw frame's own grey-world ratios (gains R 1.09,
  B 1.56 against 1.10 and 1.56) and `cam`'s processed frame is only
  slightly warm (R 157, G 164, B 140); omacam's photo has blue at 62
  against about 145. The cast is in omacam's still path, not the sensor or
  libcamera.

**CAM5.4, evening of 2026-10-14 (00554 = `7.3.0-rc6-omamobile-push1-00554-g63c0abe9c290`, libcamera 4.9-4.11):**
- **Outdoor strobe and blown-out stills** (owner, overcast daylight, omacam
  0.1.9 on 4.8: the viewfinder flashed white, stills at 1/19 s ISO 978 with
  mean luma 247-251). Two causes:
  - The AGC acted on frames taken before its last request had reached the
    sensor. In an offline model of the loop, a sensor one frame slower than
    the pipeline's delay model made the old code (0003+0011+0015) toggle
    between pinned-dark and pinned-bright steps 51-68 times.
    libcamera 4.9 `0017` judges only frames taken with the last request,
    plus one settle frame, and re-requests the values until a frame shows
    them (at most 8 frames). It corrects the total exposure (time x
    analogue x digital gain) and steps a pinned histogram x8 or 1/16.
    Modelled convergence, no oscillation:
    - delay 2: dark→bright 31, steady bright 32, bright→dark 32 frames;
    - delay 3: 32, 53 and 84 frames.
  - A still switches sensor mode, and the driver starts the new mode at its
    longest exposure. `0018` carries the converged exposure, in time and
    gain, and the white balance across a mode change. `0021` gives the IPA
    each mode's own line length, which it used to take once at camera
    creation.
  - On the phone, headless `cam`, 4.9 (the back cameras faced a surface
    and saw black):
    - main 450, telephoto 150 and ultrawide 90 frames held steady at
      their limits, with no oscillation;
    - the front camera in a dim room brightened monotonically, MSV
      1.29 → 2.18 over 21 steps of x1.24 falling to x1.03, and stopped at
      the digital-gain limit with no overshoot.

    The bright-scene check waits for daylight.
- **Camera-app controls, libcamera 4.11 (`0019`-`0026`).** Each was tested
  with a `cam` capture script on the front, main and telephoto cameras
  (front: EV, AE and AWB only, no lens), and each was read back in metadata:
  - `AeState`;
  - `ExposureValue` ±1: the digital gain moved 2.86 ↔ 4.0 on the front
    camera, then converged;
  - `AeEnable` false (idle, exposure, gain and digital gain held);
  - manual `ExposureTime`/`AnalogueGain` 4000 µs at 2.0 (main 3995,
    telephoto 4004 µs), applied within 10 frames, with AE resuming from
    them;
  - `AwbEnable` false with `ColourGains` [1.5, 1.2];
  - `AeMeteringMode` Spot with `AfMetering` Windows and `AfWindows`, and an
    `AfTrigger` scan over the window;
  - manual `LensPosition` 0.2;
  - `AfPause` Immediate (paused, lens held).

  Two bugs this found were fixed before 4.11:
  - a single `AfWindows` rectangle, as `cam` scripts send it, asserted
    inside libcamera and aborted the application;
  - an AE lock dropped the digital gain to 1.
  The table of controls is in `packages/libcamera/README.md`.
- **60 fps** (for omacam). The simple pipeline had no FrameDurationLimits,
  and the drivers default VBLANK to 30 fps. With VBLANK set to its minimum
  by hand under `cam` at 1920x1080:
  - ultrawide (2016x1136): 59.6 fps through the software ISP, with `cam` at
    3.0 s user + 0.8 s system over 11.8 s, about a third of one core;
  - front (1920x1116): 60.0 fps.

  From the sensors' mode tables (lines at the receiver's 330-360 MB/s):
  - the ultrawide 2016x1136/2016x1508 and front 1920x1116/1920x1368 modes
    reach 60 fps within the line limit;
  - the main and telephoto 2016x1136 modes are stretched to the limit, and
    their shortest frame stayed the table's, which tops them out at about
    39 and 26 fps. omamobile-camera `38fb35993` lets VBLANK shorten those
    frames in proportion; it is not pushed yet (runbook CAM5.5 below).

  A libcamera patch for FrameDurationLimits (VBLANK through the delayed
  controls, per-mode limits after `configure()`) is next, in 4.12.

**CAM5.4, night of 2026-10-14 (00554, libcamera 4.12 run from an unpacked
copy in /tmp, not installed):**
- **FrameDurationLimits [16667, 16667] at 1920x1080 (`0027`):**
  - ultrawide 59.5 fps, FrameDuration 16676 µs;
  - front 59.9 fps, FrameDuration 16673 µs;
  - main 39.3 fps and telephoto 26.2 fps: their shortest frame (25429 and
    38201 µs) is the table's until the CAM5.5 kernel change.

  The second GPU pass (`0029`/`0030`) was on in all of these. The `cam`
  process at ultrawide 1080p60 took 19% of one core, with the GPU at
  351 MHz. The front camera's 10 MP output ran at 27.5 fps with or without
  the pass, so the sensor is the limit there.
- **Not judged yet:** lens shading (`0028`, no coefficients until a flat
  field is captured with `tools/camera-lsc-fit`), noise reduction and
  sharpening, and the grey-candidate white balance (`0031`/`0032`). The
  room was dark and the back cameras faced a surface.
- **Main camera 4:3 preview (2032x1536 binned).** `cam` at 1920x1440 picks
  it: 61 of 61 frames, WDMA errors 0, but 19.5 fps, because the stretched
  line keeps the table's 60 fps frame length. `9e5c1a218` (CAM5.5) makes it
  30 fps by default.
- **50 MP on the main camera.** The HAL builds an 8160x6144 unbinned
  mode list (0x0900 = 0x11, 418 registers, 8608 clocks a line, 6304 lines,
  24 fps at 1.31 Gpixel/s) in one of its static initialisers, but the mode
  vector we extract never includes it. Taking it needs:
  - `tools/extract-camera-data` taught to add that list;
  - lines stretched to 360 MB/s, about 37040 clocks, so about 5.6 fps;
  - at least 251 MiB of camera pool for four 62.7 MB RAW10 buffers (the
    pool is 128 MiB), or two buffers;
  - 200 MB per XRGB8888 output frame from the software ISP, more than the
    384 MiB default CMA holds for several buffers;
  - a check of the GPU's largest texture against the 10200-byte stride.

**CAM5.4, 2026-10-15 (00556 = `7.3.0-rc6-omamobile-push1-00556-gb98aa37cd585`, libcamera 4.12 → 4.13):**
- **Daylight stills about 1.5-2 stops bright** (owner, main camera, omacam
  0.3.0). The EV 0 JPEGs averaged sRGB 160-184 with 15-32% clipped; the
  EV −2 ones (exactly 4x shorter) looked right.
  - It is not a mode bug. On the same scene with the same exposure product
    (1577 and 1641 ms·gain), the 1080p and 4080x3072 modes gave the same
    output (mean 80 and 84).
  - The still mode's 107 ms frame lets the AGC reach its target, and that
    target was the bright part: the mean of a five-bin linear histogram at
    its middle, about 45% linear, sRGB 170.
  - The video looked right because its frames held the sky or ran out of
    exposure time.
- **libcamera 4.13 (`0033`-`0036`):**
  - `0036`: the AGC aims the mean linear luminance at 20% (about 1.2 stops
    lower), correcting three quarters of the error in stops each time;
  - `0033`: at most 2% of the picture clipped (10% when backlit);
  - `0034`: highlights near clipping fade to neutral instead of cyan;
  - `0035`: autofocus stops the coarse scan past the peak, fine-scans 5
    samples around a fitted centre, and rescans locally in continuous
    mode. Estimated scan at infinity: about 45 frames instead of about 100.

  In a model of the loop (lognormal scenes, sensor delay 2 or 3), a 50x
  change of light converges in 8-12 frames without a reversal.
- **Smoke test, unpacked 4.13 under `cam` (indoor, dim):**
  - main 1080p: mean 0.18 at the exposure limits, AeState converged, AF
    completed;
  - main still: mean 0.45 → 0.26 → target within 3 s at 9.4 fps;
  - front: at its limits.

  The shaders compile on the GPU and no errors were logged. The daylight
  check is the owner's, after the install.

**CAM5.4, overcast retest of 4.13 (00556, 2026-10-15) and libcamera 4.15:**
- **Ground scenes are right now** (main camera mean sRGB 79-132). But
  overcast skies clipped 25-44% on the main camera with shutter time to
  spare, and a telephoto still in shade came out at mean 32 (1/145 s
  ISO 50).
- **The highlight cap counted the wrong thing.** It counted raw samples in
  the top 3%, while the white balance gains and the contrast and gamma
  curves clip a neutral surface at about 78% raw. And "backlit" fired on
  almost any ground scene metered at a 20% mean, so the lenient limit
  applied. 4.15 (4.14 is the same without `0041`):
  - `0037`: counts what comes out clipped (the inverse tone curve over the
    gains); backlit needs 60% of the picture under a quarter of the target;
    the cap never takes the mean more than a stop under the target;
  - `0041`: after a cut, the exposure stays under 85% of the one that
    clipped.
- **Telephoto:** `0038` takes the first judgement after a mode change
  gently (two more settle frames, at most a stop). The dark still fits a
  frame from before the carried exposure being judged as pinned bright,
  but the frames weren't logged. omacam's MAX_DISCARD (10 frames, about
  1 s at 9-13 fps) should become time-based.
- **Colour:** `0039`, a hand-tuned matrix (no chart) for the main,
  telephoto and front cameras: saturation, greens, and +3% red and +4%
  blue against the 4% green cast measured on pavers (112/117/113) and an
  indoor white wall (114/121/108).
- **Autofocus:** `0040`, fine steps settle 3 frames and the jump to them 4.
  Estimated main-camera scan at infinity: 4.12 ~102 frames, 4.13 ~44,
  4.14 ~38.
- **Smoke tests (unpacked copies under `cam`, dim room with a ceiling
  light):**
  - 4.14: main 1080p and front reached their limits and converged; the
    main still mode cut 7% clipped to 0.1%, then climbed back (`0041` stops
    that);
  - 4.15: the main still mode went from mean 0.50 and 23% clipped through
    0.29/5.5% and 0.19/3.2% to 0.15/3.2%, converged without a bounce; main
    1080p held at 0.11/3.2%, converged, AF completed.
- **Lens shading needs raw flat fields.** The JPEGs can't seed
  `tools/camera-lsc-fit`: they are tone-mapped and colour-corrected, and the
  sky and the wall carry real light gradients. For each camera:
  1. Hold a sheet of white printer paper flat against the lens, aim it at
     an evenly overcast sky or a bright window with no direct sun, and keep
     it still.
  2. Run `cam -c N -C3 -s role=raw,width=W,height=H -F/tmp/flat-#.raw`
     with the camera's full mode (main 4080x3072, telephoto 4032x3024,
     ultrawide 4032x3016, front 3840x2736) and check that the AGC isn't
     clipping (`--metadata`).
  3. Fit: `tools/camera-lsc-fit FILE --width W --height H --stride S
     --order O --black 64`, with the Bayer order main GRBG, front GRBG,
     telephoto BGGR and ultrawide RGGB (as the sensors report them). The
     stride is in the log's "Input ... stride" line (5120 for the main
     camera). The printed `LensShading` entry goes into the sensor's
     tuning file.

**CAM5.4, evening review of 4.15 (00556, 2026-10-15) and libcamera 4.16:**
- **Dark or blown stills that started at the mode's longest exposure.**
  Main 165249 has 1/10 s in its EXIF, the full mode's longest (107 ms),
  with 28.5% clipped. Telephoto 165332 came out at mean sRGB 24, 1/23 s,
  ISO 50. The drivers start each mode at its longest exposure, and the
  carried exposure reached the sensor only through the first frames'
  requests. A still kept early (omacam keeps one after MAX_DISCARD frames)
  showed the start exposure. `0042` returns the starting controls from the
  IPA's configure() and the pipeline sets them before streaming.
  - A test that the telephoto's analogue gain takes effect in the full
    mode (raw means at gain 1, 4 and 8) still waits for the phone.
- **Colour:** the hand-tuned matrix made a red bush neon; `0045` softens it
  by 30%. `0043` keeps hues of out-of-range colours (gamut mapping towards
  the luminance) and fades to neutral only what the sensor clipped (from
  93%), so bright green leaves no longer wash out.
- **Overcast sky:** `0043` adds a highlight shoulder after the colour
  matrix (identity to 0.6, full scale at 2.0, applied to the three colours
  together), and `0044` counts clipping through it. Real high-dynamic-range
  scenes (a tree against the sky) would need multi-frame HDR: a later
  project.
- **White balance:** neutral on grey pavers (165413: 126/125/128), not
  drifting blue; the dark grass is the evening light.
- **The shaders pass glslang.**
- **Phone tests, 2026-10-16 (indoor and dim; 4.15 installed, 4.16 from an
  unpacked copy):**
  - **Telephoto gain test (4.15, manual exposure):** the gain takes effect.
    Gain 2 → 6 at 30 ms took sRGB 5.4 → 18.5, and 10 → 30 ms at gain 2
    took 0.6 → 5.3. So the dark telephoto stills weren't a gain mapping
    fault.
    - The reported metadata changes about two frames after the picture
      does: the modelled delay of 2 is longer than the sensor's. That only
      makes the AGC wait more than it needs to.
    - A raw-only stream runs without the IPA, so manual controls need a
      processed stream.
  - **4.16 smoke test:** all four cameras open and stream in their still
    modes (main 9.4, telephoto 13.1, ultrawide 21.1, front 26.1 fps), plus
    main 1080p at 30 fps. AeState converged on each, with no errors.
    - The main still went from mean 0.58/13% clipped to 0.33 and 0.23.
    - The telephoto, ultrawide and front sat at their limits (too dim for
      them).
    - `cam` configures once, so the mode change of `0042` wasn't exercised.
      It shows in omacam's preview-to-still switch.

**CAM5.4, daylight test 4 (4.16 + omacam 0.3.1, 2026-10-16, partly cloudy) and libcamera 4.17:**
- **Good:** red leaves natural, a 5x hammock in shade at mean 109, patio
  and grass natural, AWB neutral, no dark first stills.
- **A blue sky clipped at the sensor came out as a white disc in a blue
  ring** (105747, the ultrawide's 105828/832). Its clip contour follows the
  lens's vignetting. The luminance histogram kept the clipped blue under
  its top, so the cap didn't count it. `0046` counts the samples the
  sensor saturated; `0047` limits them to 2% (5% or 10% when the rest is
  dark); `0048` fades them to neutral from 80%, gently.
- **A sunny lawn came out milky** (105758, a quarter at sRGB 240-250): the
  shoulder kept it under the old 250 threshold. `0047` counts from sRGB
  240.
- **A room with a ceiling light came out dark** (105940): `0047` grades the
  limits by the mean of the samples that don't clip (2%, 10% or 20%), so a
  lamp doesn't hold the room's exposure.
- **Main exposures from 1.2 to 25.9 ms** follow the scenes: sunlit sky
  versus shaded foliage, about 4.5 stops. One still (105908) ran out of
  omacam's wait with AE searching.

**CAM5.4, daylight test 5 (4.17, 2026-10-16) against our own shots of the same scenes from another phone, and libcamera 4.18:**
- **4.17 wins:** no sky ring, blue skies with cloud detail, no milky
  lawn, near-white mostly 0-5%.
- **4.17 was too dark.** On nine pairs our mean was sRGB 38-92 against the
  reference's 80-109; median 30-97 against 65-114; up to 27% of the
  picture at 20 or under.
- **AE hunted:** 3 of 11 main stills were taken still searching after
  1.5 s. The limits stepped against clipped shares that jump with the
  exposure, and the dark-rest leniency flipped as the exposure moved.
- **Colour (HSV, our vs reference):** grass hue 74-146° vs 70-99°;
  shaded grass is cyan and dull (saturation 0.14-0.30 vs 0.37-0.57). Sky
  hue 223-232° vs 209-224°. Reds close.
- **4.18:**
  - `0049`: a peak histogram (each sample's brightest colour);
  - `0050`: the AGC predicts the output at any exposure and bisects for
    a mean of sRGB 102, with highlights and saturation within 2% beyond
    what still clips two stops lower (light sources). In a model of the
    loop, a lamp scene that reversed 33 times with 4.17's limits settles
    without a reversal;
  - `0051`/`0052`: hue and vibrance per hue sector and a shadow lift.
    The first tuning, previewed offline on the nine pairs, turned skies
    cyan and gravel pink. The final tuning shifts greens 15° and skies
    5°, with no vibrance on warm hues: mean 32 levels under the reference
    → within 1, median within 6, green saturation matched, sky hue about
    15° off but blue. Salmon clouds in 115105 are that shot's warm white
    balance (130/117/108 before the look), not the look.
  - Smoke test of 4.18, unpacked, dim room: all four still modes and main
    1080p stream and converge. The front camera, with a ceiling light in
    view, held its exposure, the light's glow counting as highlights.

### CAM5.5: 60 fps on the main and telephoto cameras. Risk: medium (DMA)

Kernel: omamobile-camera `9e5c1a218` ("media: i2c: s5kgn1: let VBLANK shorten
frames of stretched lines"), merged into omamobile-int. W=1 and checkpatch
are clean. The VBLANK minimum of modes whose lines are stretched goes down,
and the 30 fps default may use it:

- the main camera's 2032x1536 4:3 preview mode goes from 19.5 to 30 fps by
  default. It was measured on 00554 at 19.5 fps, 61/61 frames, WDMA errors
  0 and phase-packet link errors (b3) at about 265 a frame, like the 16:9
  mode's 185. The CAM-M.5b doubt about this mode came from the line rate,
  fixed since;
- the telephoto's 2016x1136 mode goes from about 26 to 30 fps.

Expected shortest frames:

| Camera | Mode | Shortest frame now | Shortest frame after | Fastest after |
| --- | --- | --- | --- | --- |
| Main | 2016x1136 | ~39 fps | 1190 lines | ~120 fps |
| Main | 2032x1536 | 19.5 fps | 2363 lines | 60 fps |
| Main | 4080x3072 | 9.4 fps | 3104 lines | ~22.7 fps |
| Telephoto | 2016x1136 | ~26 fps | ~2381 lines | 60 fps |

Each mode still sends lines no faster than its `max-line-throughput`.

1. **Push** (the human's go, batched). Health check afterwards, then
   `cam -c 2 -C60 -s role=viewfinder,width=1920,height=1440`.
   - Pass: 30 fps with WDMA errors 0.
   - Pass: `systemctl --failed` is empty; each sensor's `vertical_blanking`
     minimum (`v4l2-ctl -d /dev/v4l-subdevN -l`) is lower than before for
     main and telephoto and unchanged for front and ultrawide.
   - Stop: a camera fails to probe.
   - Rollback: the previous images (slot B).
2. **Main at 60 fps, read-only.** Run `cam -c 2 -C600 -s
   role=video,width=1920,height=1080`, and set `vertical_blanking` to
   `1307443200 / (line_length * 60) - 1136` by hand after 3 s.
   - Pass: about 60 fps, WDMA error counters still 0, no ufshcd or CSIS
     errors in dmesg.
   - Stop: dropped lines, WDMA errors, or a frame-sync timeout: go back to
     the default VBLANK and stop.
3. **Telephoto the same** (`-c 4`, 911770000 / (line_length * 60) - 1136).
4. **Main full resolution at its new minimum** (about 22 fps): 21 frames of
   4080x3072 with the CSIS throughput counters read before and after.
   - Pass: no WDMA errors.
   - Stop: any error. In that case raise `S5KGN1_VBLANK_MIN` to the old
     frame length for that mode only.

**CAM5.5 results, 2026-10-15 (7.3.0-rc6-omamobile-push1-00556-gb98aa37cd585,
libcamera 0.7.2-4.12, indoors):** passed.
- All four cameras probe; `systemctl --failed` is empty. `vertical_blanking`
  minimum: main 32 and telephoto 32, front 32 and ultrawide 82 as before.
- **Defaults:** main 1920x1440 (the 2032x1536 mode) 30.05 fps, telephoto
  1920x1080 30.01 fps, main 1920x1080 30.00 fps. WDMA errors 0, dropped 0.
- **60 fps** through `FrameDurationLimits` [16667, 16667] (a `cam --script`),
  300 frames each: main 1080p 60.03 fps, telephoto 1080p 60.01 fps. WDMA
  errors 0, dropped 0, missed frame ends 0. Link errors (last 0x8, the phase
  packets) about 240 a frame on main and 260 on the telephoto, the same
  harmless kind as before.
- **Main 4080x3072:** 22.08 fps with a fixed 10 ms exposure, as the table
  predicts; WDMA errors 0. Under auto-exposure in a dim room it ran at 5 fps
  because AGC chose a 200 ms exposure, so the exposure set the frame length.
- No `ufshcd_err_handler`. The AK7375 `vcm_resume I2C failure: -6` lines at
  load are the known ones.

### CAM7: the front camera (Samsung S5K3J1, D-PHY on link 0). Risk: medium

**Facts.** [V] from the user's own HAL (section 4.5) unless marked: chip ID
0x30a1 at 0x0000; `hsi2c_2` (USI2, 0x10910000, SPI 675, pins gpp4-0/1,
950 kHz as stock), 0x10; reset gpp4-2; MCLK `CIS_CLK1` on gpp5-0 at
24.576 MHz; supplies LDO12S, SLG LDO8 1.1 V (shared with the main
sensor), SLG switch 4 (stock DT, section 1.2); four D-PHY lanes at 1665
Mbps [I: from its PLL], settle 8; modes 3840x2736 at 30, 3840x2236 at 30,
1920x1368 at 60, 1920x1116 at 120, 3648x2736 at 30; fixed focus (EEPROM
at 0x51, not described). [I] (section 4.4's bring-up): link 0 / slave 0,
GRBG, rotation 270, and 4224 words of phase-detection and embedded data
ahead of each image on VC 0 that the WDMA wrote before the image (image
2 rows and 384 pixels in, an H-size mismatch on the link). Our link's
channel 0 takes RAW10 only, which may drop them if they come in another
data type [I]; F.5 looks.

**Built** (section 5.1): the `s5kgn1` driver's `samsung,s5k3j1` part, the
DT on `csis0`, overlay `camera-front`, `s5k3j1-front.bin` from P.0,
libcamera 0013 (helper, properties, `s5k3j1.yaml`) and 0014 (1080p video
from the binned mode).

```sh
# F.0 the data files: runbook P (s5k3j1-front.bin, gs201-dcphy.bin)
# F.1 (read-only, any kernel) the front module's pins as ABL left them
tools/phone-ssh 'grep -E "gpp4-[012]|gpp5-0" /sys/kernel/debug/pinctrl/*/pins 2>/dev/null | head'
#   expect: inputs (function 0); stop if any is an output driven high
# F.K (after P; CAM-M first if it's running) images with camera-front added
#   to the overlays the phone runs (ASK FIRST: flashes and reboots)
KERNEL_DIR=~/android/mainline/wt-camera KERNEL_OUT=~/android/mainline/out-camera \
    ov camera-stream-link2 camera-uw-lens camera-main camera-front && bin/omamobile push
# F.2 (this boot) power-up and chip ID only
tools/camera-stage --watchdog x --cmd 'modprobe sec_acpm; modprobe gpio_s2mpg13; modprobe slg51002_regulator; modprobe s5kgn1; sleep 1; dmesg | grep -E "s5kgn1|slg51002" | tail -6; grep -E "ldo12s|vddd_main_front|cam_sw4" /sys/kernel/debug/regulator/regulator_summary'
#   pass: "s5kgn1 N-0010: S5K3J1, model 0x30a1"; LDO8 and switch 4 off again afterwards
#   stop: NACK or another ID (MCLK pin, reset, or switch 4 not the right supply), a rail left on
# F.3 (same boot) the graph
tools/phone-ssh 'modprobe phy_gs201_mipi_dcphy_rx; modprobe gs201_csis; sleep 1; for d in /dev/media*; do media-ctl -d $d -p | grep -E "s5k3j1|link 0"; done; dmesg | grep "link 0 ->"'
#   pass: "link 0 -> WDMA context 0, 4 D-PHY data lanes"; "s5k3j1 N-0010" -> "gs201-csis link 0"
# F.4 (next boot) colour bars on link 0, link only, binned mode
tools/camera-stage --watchdog x --cmd 'LINK=0 SENSOR=s5k3j1 W=1920 H=1368 DMA=0 bash -s' --script tools/camera-cap-test
#   pass: "link 0: D-PHY 4 lanes at 1665024000 bps, settle 8"; frame_start/frame_end ~30/s;
#   link errors at most ERR_WRONG_CONFIG once a frame
#   stop: SOT/ECC/CRC on every frame (first change: CAM vote 533 MHz, `CSIS_OPTS=cam_khz=533000`),
#   no frame start (link or lanes: record), a hang
# F.5 (next boot) first DMA: bars, then a real image; where does the image start?
tools/camera-stage --watchdog x --cmd 'LINK=0 SENSOR=s5k3j1 W=1920 H=1368 DMA=1 FRAMES=4 bash -s' --script tools/camera-cap-test
tools/phone-ssh 'cat /tmp/cam-1920x1368.raw' > logs/camf-bars.raw
tools/raw10-stats logs/camf-bars.raw --width 1920 --height 1368 --stride 2432 --bars 8
#   pass: wdma_errors 0; eight bars that start at column 0 of row 0
#   if the bars start 2 rows and 384 pixels in: the leading data reached the WDMA; record
#   it and stop (next single change: park it by data type or a WDMA line skip, section 8)
tools/camera-stage --watchdog x --cmd 'LINK=0 SENSOR=s5k3j1 W=1920 H=1368 DMA=1 FRAMES=4 PATTERN=0 CTRLS=analogue_gain=256 bash -s' --script tools/camera-cap-test
# F.6 the gain model: as M.6 (codes 32-512, signal 1:2:4:8:16 confirms code/32)
# F.7 libcamera 4.6: listed, a picture, 1080p video from the binned mode
tools/phone-ssh 'cam -l; cam -c3 --capture=60 --file=/tmp/f#.ppm --stream pixelformat=RGB888,width=1912,height=1368 2>&1 | tail -2'
tools/phone-ssh 'LIBCAMERA_LOG_LEVELS=SimplePipeline:0 cam -c3 --capture=30 --stream pixelformat=RGB888,width=1920,height=1080 2>&1 | grep -E "Picked|Adjusting size"'
#   pass: the front listed (the camera index may differ: pick it from cam -l); a right-way-up
#   picture after the app's rotation (else: the DT rotation); "Picked ... 1920x1368" and
#   1920x1080 adjusted to 1912x1080
```

- **Rollback:** reboot (all per load); images without `camera-front`.
- **Risks:** LDO8 is shared with the main sensor: both cameras' drivers
  vote it, and one streams at a time. The bus pins sit next to gpp4-3
  (another device's request line): the pinctrl groups don't overlap.

### CAM-T: the telephoto (Samsung S5KGM5, C-PHY on link 4, SEM1215SA focus). Risk: medium

**Facts.** [V] from the user's own HAL (section 4.5) unless marked: chip ID
0x08d5; `hsi2c_4` (USI4, 0x10930000, SPI 677, pins gpp8-0/1, 1 MHz as
stock), 0x2d; reset gpp6-2 (the same bank as the ultrawide's bus and
reset); MCLK `CIS_CLK2` on gpp7-0 at 24.576 MHz; supplies LDO12S, 0.3 ms,
SLG LDO7 1.0 V, LDO3 2.25 V (stock DT); C-PHY at 1802 Msps (full mode
2040) [I: its PLL], settle 7; modes 4032x3024 at 30 (2x2 binned), 4032x2272
at 60, 2016x1136 at 60, 2016x1512 at 60. The SEM1215SA at 0x34 (focus,
OIS, module calibration) on LDO12S, 1 ms, SLG LDO5 2.85 V, switch 1.
[I] (section 4.4's bring-up): link 4 / slave 4, two trios; the link needs
LRTE packet delimiters enabled or it sees frame starts only; CAM DVFS 533
MHz; the image is mirrored at rotation 270 and right after a vertical
readout flip (then BGGR); the focus range is the module's calibrated span
(infinity to macro) plus a margin. gpp8-2 (the torch's HWEN) shares the
bus pins' bank.

**Built** (section 5.1): the `s5kgn1` driver's `samsung,s5kgm5` part with
`samsung,vertical-flip`, `sem1215`, `csis4` with
`google,lrte-packet-delimiters`, overlay `camera-tele`,
`s5kgm5-tele.bin` from P.0, libcamera 0013 (`s5kgm5.yaml` with Af).

```sh
# T.0 the data files: runbook P; device-cheetah 0.1.28 or P.1's bring-up file
#   (blacklist sem1215)
# T.1 (read-only, any kernel) pins as ABL left them; the torch off
tools/phone-ssh 'grep -E "gpp8-[012]|gpp6-2|gpp7-0" /sys/kernel/debug/pinctrl/*/pins 2>/dev/null | head'
#   expect: gpp8-0/1, gpp6-2, gpp7-0 inputs; gpp8-2 as the torch driver set it
# T.K (after P, one overlay per boot) images with camera-tele added (ASK FIRST)
KERNEL_DIR=~/android/mainline/wt-camera KERNEL_OUT=~/android/mainline/out-camera \
    ov camera-stream-link2 camera-uw-lens camera-main camera-front camera-tele && bin/omamobile push
# T.2 (this boot) sensor power-up and chip ID
tools/camera-stage --watchdog x --cmd 'modprobe sec_acpm; modprobe gpio_s2mpg13; modprobe slg51002_regulator; modprobe s5kgn1; sleep 1; dmesg | grep -E "s5kgn1|slg51002" | tail -6; grep -E "ldo12s|vddd_tele|vdda_tele" /sys/kernel/debug/regulator/regulator_summary'
#   pass: "s5kgn1 N-002d: S5KGM5, model 0x08d5, vertical flip"; LDO7 and LDO3 off again
#   stop: NACK, another ID, a rail left on; the torch stops working (bank sharing)
# T.3 (same boot) the lens: power, ready, calibration (read only)
tools/phone-ssh 'modprobe sem1215 debug_position=1; sleep 1; dmesg | grep sem1215 | tail -3'
#   pass: "focus range A-B (calibrated X-Y)" with 0 <= X < Y <= 1023 (record that it is
#   plausible, not the values: they are this module's calibration); or "no focus calibration"
#   (the addresses are [I]): the whole range, still usable; record which
#   stop: "not ready: status ..." (the ready bit or the supplies), any I2C error
# T.4 (same boot) graph, then (next boot) colour bars on link 4, link only
tools/phone-ssh 'modprobe phy_gs201_mipi_dcphy_rx; modprobe gs201_csis; sleep 1; dmesg | grep "link 4 ->"; for d in /dev/media*; do media-ctl -d $d -p | grep -E "s5kgm5|sem1215|link 4"; done'
#   pass: "link 4 -> WDMA context 0, 2 C-PHY trios, LRTE packet delimiters"; the lens's ancillary link
tools/camera-stage --watchdog x --cmd 'LINK=4 SENSOR=s5kgm5 W=2016 H=1512 DMA=0 bash -s' --script tools/camera-cap-test
#   pass: "link 4: C-PHY 2 trios at 1802240000 sps, settle 7", "CAM 533000000 Hz", FS and FE
#   ~30/s; debugfs regs: 0x600 = 0xffff7fff
#   stop: frame starts without frame ends (LRTE: record 0x600), CRC errors on every frame
#   (the trio count: record 0x0114 with SENSOR_OPTS unchanged, then stop), a hang
# T.5 (next boot) first DMA: bars, then a real image (BGGR as flipped)
tools/camera-stage --watchdog x --cmd 'LINK=4 SENSOR=s5kgm5 W=2016 H=1512 DMA=1 FRAMES=4 bash -s' --script tools/camera-cap-test
tools/phone-ssh 'cat /tmp/cam-2016x1512.raw' > logs/camt-bars.raw
tools/raw10-stats logs/camt-bars.raw --width 2016 --height 1512 --stride 2560 --bars 8
tools/camera-stage --watchdog x --cmd 'LINK=4 SENSOR=s5kgm5 W=2016 H=1512 DMA=1 FRAMES=4 PATTERN=0 CTRLS=analogue_gain=256 bash -s' --script tools/camera-cap-test
#   pass: wdma_errors 0; bars; the real frame right-way-round after a 270-degree turn
#   (text readable, not mirrored); if mirrored: the flip is wrong (record; drop
#   samsung,vertical-flip or add a horizontal one in a later DT change)
# T.6 focus by hand: the lens moves and reads back (it is powered while the subdev is open)
tools/phone-ssh 'for s in /dev/v4l-subdev*; do v4l2-ctl -d $s -l 2>/dev/null | grep -q focus_absolute && { echo $s; v4l2-ctl -d $s -l | grep focus_absolute; }; done'
#   the telephoto's lens is the one whose range matches T.3; for P = its min, middle and max:
tools/phone-ssh 'v4l2-ctl -d /dev/v4l-subdevN --set-ctrl focus_absolute=P; dmesg | grep sem1215 | tail -1'
#   pass: "position P, read back R" with R within a few percent of P each time
# T.7 libcamera 4.6: a picture with autofocus
tools/phone-ssh 'cam -l; LIBCAMERA_LOG_LEVELS=IPASoftAf:0 cam -cN --capture=120 --file=/tmp/t#.ppm --stream pixelformat=RGB888,width=2008,height=1512 2>&1 | grep -E "Focus range|Autofocus completed" | tail -3'
#   (N: the telephoto's index in cam -l) pass: AF completes, a sharp frame at 5x
```

- **Rollback:** reboot; images without `camera-tele`.
- **Risks:** the SEM1215SA also runs OIS: we never switch OIS on or write
  its memory; with the servo off the lens rests on its stops. The
  calibration read is read only. The torch shares gpp8's bank: kernel
  pinctrl and GPIO serialise the register writes.

### 7.R Order on the phone (2026-10-13)

1. **P** (files, no reboot; then the merged kernel with today's overlays,
   one reboot; the ultrawide must be unchanged).
2. **CAM5.3-1** (libcamera 0.7.2-4.6 instead of 4.5; no reboot) and CAM5.3-2.
3. **CAM-M** (reboot with `camera-main`), M.2-M.8. (2026-10-13: at M.5c.)
4. **CAM7** (reboot with `camera-front`), F.2-F.7. **Independent of
   CAM-M:** link 0, D-PHY, its own bus and sensor; the kernel the phone
   runs (`8070cddd9`) already has it. It can run while CAM-M waits:
   after M.5c-K, the next boot adds `camera-front` to the same overlays
   (one change: the overlay) for F.2-F.3, then F.4 and F.5 each on a
   fresh boot, interleaved with M.5c-2 (one DMA step per boot, never
   two cameras' DMA steps in one boot). F.1 (read-only) can run on any
   boot now.
5. **CAM-T** (reboot with `camera-tele`), T.2-T.7.
6. CAM5.3-3/-4 (ultrawide lens, full resolution) and CAM5.4 (Snapshot)
   whenever convenient; loading at boot only after all four pass.

---

## 8. Open questions

1. Which link does each camera use? The ultrawide is D-PHY, four lanes,
   1548 Mbps (4.3), on link 2 with the PHY pair 2+3 (4.4; CAM3b.5
   confirms it on our phone). Front link 0, main link 1 (C-PHY), tele
   link 4 (C-PHY) per 4.4, unconfirmed here.
2. Does our kernel still see `pd-csis` on (CAM1.1)? If not, the gs201 PD
   driver (shared with `GPU-PLAN.md` G4c) comes first.
3. Are `sysmmu_csis0/1` in bypass and `s2mpu_csis0/1` allow-all after
   ABL, as `s2mpu_hsi0` is?
4. Does the CSIS WDMA take 32-bit byte addresses (stock loads plain
   32-bit values, IOVAs there)? And which WDMA input value selects an
   EBUF, and which channel does a plain capture use (CAM4)?
5. Can mainline `ccs` with static data drive the ultrawide (section 5.3)?
   Not needed now; the IMX386 driver uses the extracted lists.
9. The IMX386's analogue gain formula and pixel size, for a libcamera
   sensor helper and properties entry: the formula is measured by
   CAM4.3c-3; black level 64 (CAM4.3). Bayer order RGGB (CAM4.3b-1).
6. ~~Is the SLG51002 revision AA?~~ No: revision AB (`0xb13103`, stock
   dmesg), no trim needed (section 1.2). CAM2.2 confirms it on our kernel.
7. For the main and tele: if they are C-PHY, can the sensor run a D-PHY
   mode over the same board wiring? (Probably not; the wiring decides.)
8. Can Rockchip's vendor DC-PHY receive code be cited (licensing is GPL;
   it isn't on AGENTS.md's list)? The human decides. (Not needed now: the
   C-PHY values come from stock's own writes, CAM-M.)
10. The main camera's C-PHY symbol rate, Bayer order, gain model and
    rotation (CAM-M.4-M.6), and whether its link needs 533 MHz here too.
11. ~~May the CAM-M kernel work be committed?~~ Yes, option B (the human,
    2026-10-13): all driver code committed, the C-PHY values in the
    per-phone data file `tools/extract-camera-data` generates. ~~The D-PHY
    values and `google,hs-settle`?~~ Done the same way (decided
    2026-10-13, `f397875e0`, `15b6520b0`): one file, `gs201-dcphy.bin`,
    for both modes; runbook P installs it before the kernel.
12. The front camera's leading 4224 words (CAM7): does channel 0's RAW10
    data type filter drop them (F.5)? If not: a data type or VC the
    sensor's settings can move them to (another HAL init variant), or a
    WDMA line skip.
13. The telephoto's lane count and LRTE: two trios by its default and
    delimiters needed are [I] (T.4 checks both); and whether the GN1
    wants the delimiters too (it worked without them elsewhere).
14. Rotations and mirroring: front 270, telephoto 270 with a vertical
    flip, main 90 are [I]; the ultrawide's 90 was set from our own CAM4
    frames, but another bring-up reports 270 for it: check with one
    picture of text per camera in an app that applies `Rotation`.
15. The SEM1215SA's calibration addresses (0xc7b6, 0xc7bc) are [I] (T.3).
16. The GN1's real symbol rate: its output PLL says 2716 Msps per trio,
    the HAL's capacity figure 1862 (section 4.5). Settle 7 either way; the
    DT value matters only if a rate-dependent setting ever does.
