<!-- SPDX-License-Identifier: MIT -->
# Pixel 7a (lynx): Wi-Fi and Bluetooth

Status (2026-10-27): **parked.** The chip enumerates and reads host memory,
but its boot ROM stops at its authentication stage on the first firmware
load, with the same unsigned image stock loads in 57 ms. Every host-side
difference two testers could act on has been tried, one change per boot,
and all were negative. A stock-side read of the register that stage
consults is done (section 5). The published kernel has no PCIe node for
lynx; the Wi-Fi branch stays local, and on the test phone `pcie_gs201` and
`ath11k_pci` stay blacklisted (section 8). Bluetooth is on the same chip and
waits on the same question. Tracking issue: #36.

Two phones contributed: this one (`latentoperator`, sections 3 to 6) and
FlorencioJP's (#36, 2026-10-26: the ROM dump, the iATU bisection and the
stop condition in section 6). Where a fact is theirs it says so.

## 1. Goal

1. The QCA6490 (`17cb:1103`, subsystem `17cb:0108`, driven as WCN6855 hw2.1)
   on PCIe channel 1 through `ath11k`, connecting with a saved profile.
2. Bluetooth on the same chip.

## 2. Facts

`S/` is the stock Android 16 `lynx` tree and its public `cnss2` sources;
`B/` a stock `dmesg` captured 2026-10-23 and the bugreport timing
FlorencioJP pulled from theirs.

| Fact | Evidence |
| --- | --- |
| `gph2-5` enables the 0.95 V buck (stock `bt-0p95-en`), `gph2-4` is WLAN_EN; stock raises the buck, then WLAN_EN, then waits 1 ms and brings the link up. BT_EN is `gpp16-2` on PERIC1 (`0x10840000`), which our tree does not describe. `gpa6-1` is the chip's wake line to the host [V] | `S/` device tree |
| The PCIe PHY rails are S2MPG13 `LDO3S` and `LDO18S`, always-on in the stock tree [V] | `S/` device tree |
| Stock's first cold cycle already passes authentication: from the buck, WLAN_EN at +109 ms, first BHI at +167 ms, SBL at +270 ms, AMSS at +935 ms, then power-off and a second WLAN_EN cycle at +8.8 s (mission mode) [V] | `B/` (FlorencioJP) |
| Stock's `cnss2` probe (2.37 s) raises the buck and WLAN_EN, enumerates, reads the device version, suspends the link and drops WLAN_EN without a BHI; `init.lynx.rc` then writes `fs_ready` at `vendor.all.modules.ready` (4.8 s) and the calibration load runs without `cnss-daemon` [V] | `B/`, `S/init.lynx.rc` |
| Stock runs with the HSI2 SysMMU translating (image buffers in `wifi_region`), a 36-bit DMA mask, PCIe I/A on, L1.2 on and three MSI vectors for MHI. The BHI load takes 57 ms [V] | `B/` |
| The image `ath11k` requests (`ath11k/WCN6855/hw2.1/amss.bin`) is byte-identical to stock's `/vendor/firmware/amss20.bin`, the only `amss*` there; `m3.bin` matches too. It is an MBN version 5 hash segment with `sig_size` 0 and `cert_chain_size` 0; all 17 segment hashes verify [V] | FlorencioJP, sha256 on #36 |
| On our kernel: link Gen2 x1, enumeration, 32 MSI vectors through iMSI-RX, `BHI_IMGADDR_HIGH` 0, the buffer below 4 GiB, and the chip reads host memory (section 3) [V] | NOTES 2026-10-24, this phone |
| The chip's stall code is `TCSR_PBL_LOGGING` (`0x01B000F8`) `0xef0a0002`: stage `0x0a`, status `0002`. `BHI_STATUS` stays 0, `BHI_EXECENV` 0 (still in PBL), `BHI_ERRCODE` 0, no MSI, no AER on either end, MHI gives up with -110 after about 20 s [V] | both phones |

## 3. Where it stops: `pbl_auth.c`

- **The ROM reads only the header and the hash segment.** Inbound iATU
  windows that answer with an Unsupported Request, one range per boot
  (FlorencioJP): blocking `[BHI, +0x1000)` gives `0xef128100` (the
  bad-magic code) with `UnsupReq+` on the root port; blocking
  `[BHI+0x1000, +0x80000)` gives `0xef0a011f` with `UnsupReq+`; blocking
  `[BHI+0x2000, +0x80000)` changes nothing and raises no UR. So the ROM
  issues the header read and exactly one read of `+0x1000..+0x1248`, that
  read completes on the PCIe side, and nothing at `+0x2000` or beyond is
  ever read. No SRAM write follows: a code word the ROM would place first
  is still zero 2 s after the doorbell (this phone), and a scan of
  `0x1400000..0x1800000` finds neither the ELF header nor the hash table
  (FlorencioJP).
- **The hash content does not matter; only its shape does.** One change per
  boot, image served through `firmware_class.path`, nothing written to the
  phone's firmware directory (both phones):

  | Change to the image | `TCSR_PBL_LOGGING` |
  | --- | --- |
  | none | `0xef0a0002` |
  | ELF magic destroyed | `0xef128100` |
  | `e_phnum` 0 | `0xef0e0200` |
  | hash-segment program header without its hash-type flag | `0xef120200` |
  | hash segment shrunk to 16 or 256 bytes, `hash[0]` recomputed | `0xef0a0125`, `0xef0a0118` |
  | hash segment zeroed | `0xef0a0125` |
  | `hash[0]` or `hash[2]` corrupted; a program-header byte flipped; MBN version 5 to 0x55; one byte flipped in the header hash or the first segment hash | `0xef0a0002` |
  | hash segment moved into page 0, or its `p_paddr` moved to SRAM | `0xef0a0002` |
  | code from `0x2000` zeroed; all zeros past the header | `0xef0a0002` |

- **Stage `0x0a` is the authentication step.** FlorencioJP copied 128 KiB
  of the ROM at `0x00800000` through the BAR window after the stall and
  disassembled it as Hexagon. The ROM keeps its source file names:
  `pbl_cache_mmu.c`, `pbl_auth.c`, `pbl_ram_init.c`, `pbl_hw_init.c`,
  `pbl_elf_loader.c`, `pbl_flash_pcie.c`, `pbl_common.c`, with the strings
  `USE_SERIAL_NUMBER_IN_SIGNING` and `ROOT_CERT_SEL`. The bad-magic path
  logs `pbl_auth.c` line `0x1c6` with `0x128100`; the normal path reaches
  `pbl_auth.c` line `0x1ba`. The routine that runs just before the stop
  reads `WLAN_SECURE_BOOTN` (`0x01E22B24`) twice, masks bit 0 and compares
  the two reads; nearby code reads `0x1E22B2C` and `0x1E22B3C` and selects
  a root certificate. The ROM itself is Qualcomm's and is not published.
- **What the chip says about itself after the stall** (windowed reads,
  FlorencioJP; this phone read only the QFPROM power control): `WLAN_SECURE_BOOTN` `0x11111111`,
  `QFPROM_RAW_OEM_SECURE_ROW0_LSB` 0, all 16 `BHI_OEMPKHASH` words 0,
  `PBL_WLAN_BOOT_CFG` (`0x01E22B34`) 0, `TLMM_PBL_BOOTSTRAP_STATUS`
  (`0x1910008`) 0, `WLAON_QFPROM_PWR_CTRL_REG` (`0x1F8031C`) `0x62`. The
  PBL log SRAM (`0x01403DA0..`) holds the stall code and a few nonzero
  words. Nothing here says the part demands a signed image: the fuse row is
  zero and the OEM key hash is zero.

So the chip gets the hash segment and then makes an authentication decision
that goes the other way than under stock, with an identical image. That
points away from the host and at the chip's own state before the first BHI.

## 4. Ruled out

Each row is one matched change against an unchanged control, on the same
build, with the kernel log streamed to the laptop, the watchdog armed and
the six protected partitions checksummed before and after. "Both" means
the row's items come from the two phones. Every row ended at
`0xef0a0002`.

| Area | Tested | Who |
| --- | --- | --- |
| Image | Pixel's `amss20.bin` and linux-firmware's WCN6855 `amss.bin` + `m3.bin` (the image that boots unsigned on laptops); hash content, hash location, MBN version (section 3) | both |
| Addressing | `BHI_IMGADDR` and the MSI target below 4 GiB, high words 0; the image buffer placed in stock's `wifi_region` range | both |
| Coherency and ordering | IOCC/AxCACHE on and off, software coherency, Relaxed Ordering, No Snoop, `MaxReadReq` 128 and 256, read request size | both |
| SysMMU, S2MPU, iATU | SysMMU bypass (`CTRL` `0x24`, as the ROM path needs a 512 KiB window); inbound iATU region 1:1 over `0x80000000..0xffffffff`; UR-coded inbound bisection; HSI2 S2MPU fault status 0 and `CTRL0` enable bit clear before, during and after the stall | both |
| MSI | 32 vectors through iMSI-RX; vector 0 unmasked, never pending; the missing host MSI route bit (real, enabling it changed nothing) | this phone |
| Power | buck 103 ms before WLAN_EN; buck held across a WLAN_EN cycle; minutes powered off before a try; the seven S2MPG12/S2MPG13 rails stock keeps always-on but ABL leaves off (`LDO20M`, `LDO9S`, `LDO10S`, `LDO11S`, `LDO15S`, `LDO19S`, `LDO20S`, enabled through ACPM at stock voltages); BT_EN held high (stock raises it about 1 s before WLAN_EN); `TCXO_BUF_CTRL` `0xf0f` | both |
| PCIe link | Gen1 versus Gen2; D3hot/D0 cycle before the load; PERST released about 20 ms after WLAN_EN; CMU_HSI2 clock gating cleared (`cmu_acg_off`) and the clock-gating sequence; the PHY's one-lane sequence against Google's `pcie-exynos-rc.c` tables (offline model, identical); stock's ELBI soft-power-reset pulse at teardown | both |
| Resets | `ath11k`'s SOC global reset skipped; its pre-MHI resets skipped; the chip's own startup reset skipped | both |
| MHI handshake | `BHI_OEMPKHASH[0..15]` read before the download, as downstream MHI does (the read runs, all zero, same stall); the BHI buffer's prefix fingerprinted against the file; an invalid magic moves the code (so the header is read) | both |
| Fuses | `WLAON_QFPROM_PWR_CTRL_REG` `0x62`, the same as stock; `QFPROM_RAW_OEM_SECURE_ROW0_LSB` 0 | both |

Not tried: running with the HSI2 SysMMU translating as stock does. The
PCIe root port and UFS share VID 0 on gs201, and translating VID 0 starved
storage on cheetah (AGENTS.md §4), so that needs its own plan, a
restricted window for storage and a reinstall, not a module swap.

## 5. The stock-side read (2026-10-27, this phone)

Stock Android (slot A, `CP2A.260705.006`) was restored for an afternoon with
`userdata` backed up and Arch put back the same evening. With root, stock's
`cnss2` debugfs: `dev_boot` `on`, then `linkup`, then
`echo "0xFE <addr> 4" > reg_read`; the value appears only in `dmesg`
(`cnss: Read 0x... from register offset ...`), not in `cat reg_read`. The
calibration load cannot be held back on this build (`init.lynx.rc` writes
`fs_ready` itself), so these are reads from the link-up, pre-BHI state of a
fresh WLAN_EN cycle after calibration (`shutdown`, `off`, 5 s, `on`,
`linkup`), with the buck held high throughout, as stock's own cycles run.
Vendor init was not changed. None of the reads hung on stock.

| Register | pre-BHI | mission (`dev_boot powerup`) | pre-BHI, second cycle |
| --- | --- | --- | --- |
| `WLAN_SECURE_BOOTN` `0x1E22B24` | **`0x0`** | `0x0` | `0x0` |
| `TCSR_PBL_LOGGING_REG` `0x01B000F8` | `0xef150600` | `0x5b1e21ed` | `0xef150600` |
| `PCIE_BHI_ERRDBG2`, `ERRDBG3` | `0x0`, `0x0` | `0xcafecace`, `0xcafecace` | `0x0`, `0x0` |
| `PBL_WLAN_BOOT_CFG` `0x01E22B34` | `0x200` | `0x200` | `0x200` |
| `TLMM_PBL_BOOTSTRAP_STATUS` `0x1910008` | `0x40` | `0x40` | `0x40` |
| `TLMM_OD_EN` `0x1910020` | `0x500` | `0x500` | `0x500` |
| `WLAON_QFPROM_PWR_CTRL_REG` `0x1F8031C` | `0x62` | `0x62` | `0x62` |
| `WLAON_SOC_POWER_CTRL` `0x1F80000` | `0x8020397` | `0x117` | `0x8020397` |
| `WLAON_WL_PWR_STATUS_REG` `0x1F8002C` | `0xd` | `0x9` | `0xd` |
| PBL log SRAM `0x01403DA0..DC4` (10 words) | all `0x0` | all `0x10001` | all `0x0` |

What it says:

- `WLAN_SECURE_BOOTN` reads 0 under the stock driver, six reads over three
  states, never `0x11111111`. So on this phone the register the ROM's
  authentication stage consults is zero when stock loads firmware, and the
  `0x11111111` we read after the stall is a state stock's sequence never
  leaves the chip in, not a fuse. The window does land where we think:
  FlorencioJP re-read the set after a stall on 2026-10-27 (cold reset with
  the buck dropped and restored, then the usual `-110`) and the WLAON and
  TLMM neighbours match the stock column exactly, `WLAON_SOC_POWER_CTRL`
  `0x8020397`, `WLAON_WL_PWR_STATUS_REG` `0xd`, `WLAON_QFPROM_PWR_CTRL_REG`
  `0x62`, `TLMM_OD_EN` `0x500`. The three that differ are exactly the three
  the ROM consults: `WLAN_SECURE_BOOTN` `0x11111111` against `0x0`,
  `PBL_WLAN_BOOT_CFG` `0x0` against `0x200`, `TLMM_PBL_BOOTSTRAP_STATUS`
  `0x0` against `0x40`.
- **The stock column is after a good run, not cold.** Stock's `cnss2` on
  lynx only ever raises the buck (`wlan_buck_enable()`, GPIO 103, logged
  `BUCK GPIO: [1]` on every later `on`); it has no path that drops it, and
  `dev_boot off` de-asserts WLAN_EN only. So `0x0 / 0x200 / 0x40` may be
  what a successful PBL leaves behind rather than what a cold chip shows,
  and the two readings are not yet the same experiment (section 7).
- `TCSR_PBL_LOGGING` keeps `0xef150600` across the WLAN_EN cycle (stage
  `0x15`, code `0x0600`, presumably the end of the last successful ROM run),
  so with the buck held the WLAON/TCSR domain retains state between cycles.
  "Pre-BHI after a cycle" is not "cold". A true cold read, before the
  first-ever BHI, needs the calibration load held back on a stock phone
  (vendor init edited, or a build whose init does not write `fs_ready`).
- Two registers that read 0 on mainline after the stall are nonzero under
  stock in every state: `PBL_WLAN_BOOT_CFG` `0x200` and
  `TLMM_PBL_BOOTSTRAP_STATUS` `0x40` (section 7).
- The whole `wlaon_reg_access_seq[]` table (131 registers) was read in each
  state; between the two pre-BHI cycles only the stack canary and a running
  counter differ. The table, the QFPROM row and the JTAG id stay off the
  repository (they identify the phone).

## 6. Stop conditions

These are stop conditions, not warnings. Each one has reset a phone.

1. **No windowed chip register reads before `mhi_sync_power_up()`.** Reading
   `WLAN_SECURE_BOOTN` (`0x1E22B24`) through the BAR window after link-up
   and before MHI's power-up hung the HSI2 bus and rebooted FlorencioJP's
   phone (the watchdog brought it back to slot B). The same read after the
   stall is fine. That stock's `cnss2` reads did not hang is a fact about
   stock's driver and power sequence, not a licence for ours.
2. **No userspace reads of the HSI2 SysMMU or iATU blocks.** `devmem` of
   SysMMU offset `0x145c000c` reset this phone (2026-10-24); one `/dev/mem`
   read of the iATU registers dropped FlorencioJP's SSH session. Reads of
   these blocks, the S2MPU and the PCIe controller go through a kernel
   module, after link-up, one register group per boot (AGENTS.md §1), and
   never from a shell.

And the gate before any radio step, from CONTRIBUTING.md §3: the six
protected partitions checksummed against the off-repo backup, `kmsg`
streamed to the laptop, the watchdog armed, a fresh SSH login to confirm,
one change per boot, and the rollback written before the boot.

## 7. What is left

Ordered by what it costs. Nothing here is scheduled.

1. **Offline: the bootstrap straps.** `TLMM_PBL_BOOTSTRAP_STATUS` reads
   `0x40` under stock and 0 here, and `PBL_WLAN_BOOT_CFG` `0x200` against 0.
   If the bootstrap status is the chip's strap pins sampled at its reset
   [I], a line the host drives or pulls differently while WLAN_EN rises
   would show up there. Compare the stock tree's pin configuration for
   every line to the chip (function, pull, drive, the `pdn` states) with
   ours, on paper first. Then confirm the two values on mainline at the
   stall, where windowed reads are safe, before changing a pin.
2. **The cold stock read.** The one that settles the caveat in section 5:
   on stock, a cold chip (power-off, not a reboot: `cnss2` never drops the
   buck) and the three registers read after `dev_boot on` and `linkup`,
   before the first BHI write. On this build that means holding back the
   calibration load, since `init.lynx.rc` writes `fs_ready` at 4.8 s: a
   Magisk overlay of `/vendor/etc/init/hw/init.lynx.rc` without the two
   `fs_ready` writes, removed afterwards. If stock reads `0x11111111 / 0x0 /
   0x0` cold and `0x0 / 0x200 / 0x40` only after a good run, the PBL writes
   these and our stop is upstream of them. If stock reads `0x0` cold too,
   our power-up leaves bit 0 of `WLAN_SECURE_BOOTN` set, the bit
   `pbl_auth.c` masks and compares. Costs a stock cycle on this phone
   (`userdata` wiped and the Arch root restored from the backup).
3. **The sequence around WLAN_EN.** Stock's `cnss2` suspends the link and
   drops WLAN_EN once before the real load; our path does one cycle. Also
   worth keeping in view: on stock none of the windowed reads before the
   first BHI hang, on mainline the same read before `mhi_sync_power_up()`
   froze HSI2. Whatever leaves `WLAN_SECURE_BOOTN` at `0x11111111` may be
   what makes that page unreadable before power-up.
4. **SysMMU translating as stock**, with its own plan (section 4).

## 8. State and how to resume

- **Published kernel:** no PCIe node for lynx. **Local branch**
  `omamobile-gs201-lynx-wifi` (unsigned, on the touch branch) imports the
  gs201 PCIe host, PHY and SysMMU drivers from `omamobile-int`, describes
  `pcie_1` with the two power pins as the root port's supply and no
  restricted DMA pool (MHI needs 512 KiB in one piece), describes the
  sub-PMIC, and carries test-only parameters: `msi=1` (iMSI-RX),
  `skip_soc_reset`, `skip_sw_reset`, `skip_mhictrl_reset`, `bhi_zero_from`
  and `bhi_flip_at`. The private diagnostic tree behind section 4 adds
  default-off `capture_*` flags to the host, `ath11k` and MHI; none of it
  is for merging.
- **Test phone:** runs that branch's build, so the node is enabled there;
  `pcie_gs201` and `ath11k_pci` are blacklisted in
  `/etc/modprobe.d/omamobile-wifi-test.conf` and only the PHY module
  autoloads, which does nothing without the controller. Firmware is in
  `/usr/lib/firmware/updates/ath11k/WCN6855/hw2.1`: linux-firmware
  `amss.bin` and `m3.bin`, plus the phone's own calibration as
  `board.bin`. Nothing from the vendor image goes into this repository.
- **To resume:** read sections 6 and 7, re-check the live kernel, DT and
  the six protected hashes, then run the next item in section 7 as a gated
  step (expect, stop condition, rollback) and record the result here with
  the date and `uname -r`.
