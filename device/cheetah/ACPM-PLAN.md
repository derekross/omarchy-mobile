# ACPM plan: gs201 firmware power manager, GPU DVFS first (cheetah / gs201)

Status (2026-10-12): **A0-A5 passed on the phone; GPU DVFS through ACPM is
on by default** (NOTES.md, "everything working so far comes up at boot";
omamobile-device-cheetah 0.1.13, `39e72a9`). A1 first failed with "Channel 3
queues outside the SRAM" (a type-2 buffer channel in DRAM); the driver now
skips unusable channels (`0a050ad`: 14 of 15 usable; DVFS on channel 0, PMIC
2, thermal 9). Panthor idles at 151 MHz, capped at 572 MHz. Kernel:
`omamobile-acpm` @ `a7a72e9f4` (`wt-acpm`, `out-acpm`), merged into
`omamobile-int`. The S2MPG12 PMIC core and its RTC on this link have since
come up in `SUSPEND-PLAN.md` S3b (`sec_acpm`, not yet loaded at every boot).
**Next** (section 8): ACPM thermal and the GPU cooling that lifts the cap,
CPU DVFS, MIF devfreq.

Earlier status (historical, superseded by the status above): kernel side written and built offline, **nothing run on the
phone yet**. Branch `omamobile-acpm` in `~/android/mainline/wt-acpm`, images in
`~/android/mainline/out-acpm/images`. The runbook is section 7.

**Goal.** The Mali-G710 runs at a fixed 151 MHz (`/sys/class/devfreq/28000000.gpu`
has one OPP). Its clocks and rail voltages belong to the APM firmware (ACPM), so
real GPU speeds need an ACPM link. The same link is what MIF (memory bus) DVFS,
CPU DVFS, the S2MPG12/S2MPG13 PMIC regulators, the ACPM thermal sensors and the
RTC all sit on.

**Expected GPU range after this plan: shader clock 202–848 MHz (top/L2
302–996 MHz)**, the same 11 levels as the stock kernel, plus the 151 MHz boot
level. We start capped at 572 MHz until there is a GPU thermal limit.

Path abbreviations (as in `GPU-PLAN.md`):

- `L/` = our kernel, branch `omamobile-acpm` (`~/android/mainline/wt-acpm`)
- `G/` = `~/android/omamobile/out-kernel/google/gs-6.1/private` (Google's GPL gs201 kernel)
- `GS/` = `G/google-modules/soc/gs`
- `R/` = `~/android/reference/cheetah-stock-cp2a-root` (stock live DT and logs)
- `ECT` = the ECT blob in the phone's own `bl2_a.img` @ `0x60000`
  (`cheetah-partition-backup-20261011`), parsed with the layout of
  `GS/drivers/soc/google/ect_parser.c`

---

## 1. The gs201 ACPM link is gs101's at different addresses

Upstream already has gs101 ACPM: the mailbox (`L/drivers/mailbox/exynos-mailbox.c`),
the protocol (`L/drivers/firmware/samsung/exynos-acpm*.c`), DVFS clocks
(`L/drivers/clk/samsung/clk-acpm.c`) and the S2MPG10/11 PMICs over it
(`L/drivers/mfd/sec-acpm.c`). Google ships **one** ACPM driver for gs101 and
gs201 (`GS/drivers/soc/google/acpm/`), with no SoC-specific code, so the
protocol is the same. What differs is in the device tree:

| Item | gs201 | gs101 | Evidence |
|---|---|---|---|
| AP2APM mailbox | `0x18210000`, 4 KiB | `0x17610000` | `G/devices/google/gs201/dts/gs201.dtsi:561`; `G/devices/google/gs101/dts/gs101.dtsi:505`; `R/iomem.txt:68` |
| Mailbox IRQ (APM→AP) | GIC SPI 78 | SPI 73 | `R/live.dts:12965` (`<0 0x4e 4>`); `R/interrupts.txt:15` (hwirq 110 = SPI 78) |
| APM SRAM | `0x18500000`, `0x48000` | `0x2039000`, `0x40000` | `gs201.dtsi:562`; `R/iomem.txt:76` |
| Framework data (`initdata-base`) | SRAM + `0xa000` | same | `gs201.dtsi:564`; upstream `ACPM_GS101_INITDATA_BASE` |
| Mailbox APB clock | CMU_APM gate `0x20d4`, auto clock gating (Q-channel `0x30b0`) | CMU_APM gate | `GS/drivers/soc/google/cal-if/gs201/cmucal-sfr.c:1061,2967`; `cmucal-qch.c:69` |

**Framework header** (what the AP reads at SRAM + 0xa000), `GS/.../acpm/fw_header/framework.h:36`
`struct acpm_framework`: word 2 = `ipc_channels` (offset of the channel table),
word 6 = `ipc_ap_max` (AP channel count). Google's `channel_init()` uses exactly
these (`GS/.../acpm/acpm_ipc.c:946-961`). Upstream's `struct acpm_shmem`
(`L/drivers/firmware/samsung/exynos-acpm.c:55`) reads the same words 2 and 6.

**Channel descriptor**, `framework.h:98,125` (`struct ipc_channel` with an
embedded `struct channel_info`): `id`, `field`, `owner`, `type`, then
`rx_rear/front/base`, 3 indirect-buffer words, `tx_rear/front/base`, `q_len`,
`q_elem_size`, `credit`, `mbox_addr`, `ap_poll` = 18 words. Upstream's
`struct acpm_chan_shmem` (`exynos-acpm.c:79`) is the same 18 words. As in
Google's driver, the AP's TX queue is the firmware's "rx" queue.

**Doorbell.** Google rings the APM with `INTGR1 = 1 << channel` and masks the AP
side with `INTMR0` (`GS/.../acpm/acpm_ipc.h:105-117`, `acpm_ipc.c:418-420,1002`).
Upstream's gs101 mailbox data is the same (`INTGR1` 0x40, `INTMR0` 0x28,
`L/drivers/mailbox/exynos-mailbox.c:19,78`); its probe masks all 16 AP-side bits
(`:189`), which only stops APM→AP interrupts (upstream polls).

**Channels** (`acpm-ipc-channel` in the stock DT):

| Ch | User | Evidence |
|---|---|---|
| 0 | DVFS (`cal_if`, CMU) | `R/live.dts:12923-12934` |
| 1 | exynos-dm (DVFS manager policy) | `R/live.dts:14751-14754` |
| 2 | PMIC register access (S2MPG12 main, S2MPG13 sub) | `R/live.dts:13105,13755` |
| 4 | `gs-acpm` (APM timer) | `R/live.dts:12955` |
| 9 | ACPM TMU (thermal) | `R/live.dts:15433-15434` |
| 10, 11 | SLC | `R/live.dts:12990-12996` |
| 12 | ACPM log | `R/live.dts:12972` |

The same numbers as gs101 for DVFS (0) and PMIC (2): upstream's clock driver
uses channel 0 (`clk-acpm.c`, `mbox_chan_id = 0`) and `sec-acpm.c:545,555`
channel 2.

**DVFS messages** are 4 words, the same in Google's and upstream's code:
`cmd[0]` = domain index, `cmd[1]` = rate in kHz, `cmd[2]` = `FREQ_REQ` (0) or
`FREQ_GET` (1), `cmd[3]` = a timestamp in ms. The firmware answers `FREQ_GET`
with the rate in `cmd[1]`. Evidence: `GS/drivers/soc/google/cal-if/acpm_dvfs.c:97-130,167-191`,
`acpm_dvfs.h:23-24`; `L/drivers/firmware/samsung/exynos-acpm-dvfs.c:33-67`.
Google sends MIF/INT/CPU requests without waiting for a reply and all others
with one (`acpm_dvfs.c:111-117`); upstream waits for the firmware's
acknowledgement on every message, which works for both.

Stock boot: `R/dmesg.txt:400-410` (`gs-acpm-ipc 18210000.acpm_ipc: acpm_ipc probe done`),
and the SLC plugin reports "acpm firmware 1.8" (`:1133`).

## 2. DVFS domains

Index = `cmd[0]` = the low bits of Google's `ACPM_DVFS_*` IDs
(`GS/include/dt-bindings/clock/gs201.h:314-327`, `0x0B04000N`), in the order of
`GS/drivers/soc/google/cal-if/gs201/acpm_dvfs_gs201.h:6-20`. That order is the
same as gs101's, so the IDs match upstream `google,gs101-acpm.h`. Our
`L/include/dt-bindings/clock/google,gs201-acpm.h` adds index 14, the paired
GPU clock (section 3).

Levels and the boot level from the phone's ECT (DVFS block; boot from
`GEN/MINMAX_*`, which ACPM uses when the DVFS `boot_level_idx` is -1):

| Idx | Domain | ECT levels (MHz) | Boot (MHz) |
|---|---|---|---|
| 0 | MIF | 3172 2730 2535 2288 2028 1716 1539 1352 1014 845 676 546 421 | **3172** (max) in the ECT; the phone runs at 2028 (below) |
| 1 | INT | 533 465 332 267 200 155 100 | 533 (max) |
| 2 | CPUCL0 | 2196 … 300 (15 levels) | 1197 |
| 3 | CPUCL1 | 2466 … 400 (17 levels) | 910 or 1197 (by ASV group) |
| 4 | CPUCL2 | 3195 … 500 (21 levels) | 984 or 1106 |
| 5 | G3D (shaders) | 848 762 701 572 510 471 400 351 302 251 202 151 | 151 |
| 6 | G3DL2 (top, L2) | 996 885 750 603 470 302 151 | 151 |
| 7 | TPU | 1150 … 226 | 226 |
| 8–10 | INTCAM, TNR, CAM | 664 … 67 | 67 |
| 11 | MFC | 711 … 100 | 100 |
| 12 | DISP | 664 … 134 | 400 |
| 13 | BO | 620 … 95 | 95 |

Consequences:

- **MIF runs at 2028 MHz, not the ECT's boot level of 3172 MHz, and INT at
  533 MHz.** ACPM's own rate read in A2 (`logs/acpm-a2.out`: mif 2028000000)
  and every gs-decon probe in `logs/` (332 of them: "MIF at 2028000000 Hz")
  agree. This line said "already at its maximum (3172 MHz)" until 2026-11-07;
  the ECT's boot entry isn't what the firmware leaves running. Google's GPU
  table asks for MIF ≥ 3172 MHz only at the top GPU level
  (`gs201-gpu.dtsi:93`), so the top GPU level would want MIF raised, which
  nothing does yet. Below that, MIF DVFS is about power, not speed: a
  devfreq/interconnect driver on clock index 0 later.
- **The CPUs are still at their boot levels** (about 1.2/0.9–1.2/1.0–1.1 GHz;
  stock goes to 2.1/2.35/2.85 GHz). The same ACPM clocks give cpufreq-dt CPU
  DVFS, as upstream gs101 does (`L/arch/arm64/boot/dts/exynos/google/gs101.dtsi:81`).
  Not in this branch; it's the obvious next win once A2 passes.

## 3. The GPU operating points

**Google's v2 table cannot be used on this phone.** kbase tries the DT tables
from the highest version down and takes the first whose every rate has a
voltage in ECT (`G/google-modules/gpu/mali_kbase/platform/pixel/pixel_gpu_dvfs.c:501-515,736-741`).
The v2 table (`gs201-gpu.dtsi:107-127`) needs 633 and 434 MHz, which this
ECT's G3D domain doesn't have (they exist only in a separate `G3D_PO` domain).
So stock uses **v1** (`gs201-gpu.dtsi:86-104`): it prints "mcu_util_min/max not
set" 11 times, once per v1 row, and lists exactly the v1 levels as GPU cooling
states (`R/dmesg.txt:3975-3985,3989-3999`). `GPU-PLAN.md` section 1.2 quoted v2;
v1 is the right one.

| OPP (shader, G3D) | top/L2 (G3DL2) | stock QoS | G3D voltage by ASV group (ECT) |
|---|---|---|---|
| 848 MHz | 996 MHz | INT ≥ 533, MIF ≥ 3172 | 650–806 mV |
| 762 | 996 | MIF ≥ 845 | 625–775 mV |
| 701 | 885 | MIF ≥ 845 | 594–750 mV |
| 572 | 750 | | 556–706 mV |
| 510 | 750 | | 550–688 mV |
| 471 | 603 | | 538–675 mV |
| 400 | 603 | | 525–656 mV |
| 351 | 470 | | 513–644 mV |
| 302 | 470 | | 500–625 mV |
| 251 | 302 | | 500–613 mV |
| 202 | 302 | | 500–594 mV |
| 151 (ours: boot level) | 151 | | 500–575 mV |

Rules taken from kbase:

- G3DL2 ≥ G3D at all times: raise G3DL2 first, lower it last
  (`pixel_gpu_dvfs.c:105-114`).
- Voltages are not in the DT. ACPM applies the fused ASV voltage with every
  rate change, which is why the OPP table has no `opp-microvolt` and the GPU
  has no `mali-supply` (`GPU-PLAN.md` 2.2).
- G3D and G3DL2 are separate rails (S2MPG13 BUCK2S and BUCK8S), so each
  domain's voltage follows its own rate.
- `gpu_dvfs_max_freq = 900000` (`gs201-gpu.dtsi:133`): no cap below 848 MHz in stock.

## 4. What's built

Kernel, `omamobile-acpm` on top of `omamobile` @ `e7cb10fe5` (8 commits):

| Commit | What |
|---|---|
| `dt-bindings: mailbox: google,gs101-mbox: add gs201` | `"google,gs201-mbox", "google,gs101-mbox"`; the driver needs no change |
| `dt-bindings: firmware: google,gs101-acpm-ipc: add gs201` | compatible + `google,gs201-acpm.h` (IDs 0–13 = domains, 14 = GPU) |
| `firmware: samsung: acpm: check the channel table read from SRAM` | rejects a channel count of 0 or > 64 and any table or queue outside the SRAM (a wrong base would otherwise write outside the mapping or divide by zero); one info line "N channels", each channel at debug level |
| `firmware: samsung: acpm: add gs201 support` | match data: initdata 0xa000, clocks device `gs201-acpm-clk` |
| `firmware: samsung: acpm: skip channels the AP cannot use` | a channel whose queues are outside the SRAM (or that gets no mailbox channel) is skipped with its raw descriptor printed, instead of failing the probe; `dump_chans=1` prints the whole table (SRAM reads only); "N channels, M usable" |
| `clk: samsung: acpm: add gs201 with a paired GPU clock` | the 14 domain clocks plus `gpu`: rate = G3D, set_rate moves G3DL2 to the paired level in the safe order. Module parameter `clk_acpm.gs201_gpu_max_khz` (runtime-writable): **0 (default) = read-only**, nothing is sent; otherwise the highest allowed shader rate. gs201 clocks are `CLK_GET_RATE_NOCACHE`: every read asks the firmware |
| `arm64: dts: ... gs201: add the APM mailbox, SRAM and ACPM` | the three nodes; the mailbox APB clock is a fixed-clock placeholder (no CMU_APM driver yet; Google never enables that gate either) |
| `arm64: dts: ... gs201: clock the GPU through ACPM DVFS` | GPU `core` clock = `<&acpm_ipc GS201_CLK_ACPM_GPU>`, 12-entry OPP table (151 + v1); the fixed 151 MHz stand-in is gone |

Why one "paired" clock: Panthor's devfreq sets only its `core` clock through
the OPP core, and multi-clock OPPs need driver support Panthor doesn't have.
A paired clock keeps Panthor unchanged. The cleaner long-term shape is a G3D
power-domain driver with `set_performance_state` (the MT8196 model, `GPU-PLAN.md`
3.3), which the G4c power-domain work needs anyway; the pairing table then
moves there.

Why the GPU still works while ACPM is read-only: the OPP table contains the
151 MHz boot level, the firmware reports 151 MHz, so Panthor's probe
(`dev_pm_opp_set_opp()` on the current rate) asks for the rate the clock
already has, and the clock framework sends nothing. Every devfreq request
rounds to 151 MHz while the cap is 0.

Repo: `tools/acpm-stage` (runs one stage, streams `/dev/kmsg` to
`logs/acpm-*.log` first, optional hardware watchdog, `--pstore`), and
`packages/omamobile-device-cheetah/vendor/modprobe.d/omamobile-acpm.conf`
(blacklists `exynos_mailbox`, `acpm_protocol`, `clk_acpm`).

Builds: kernel, modules tarball and images in `~/android/mainline/out-acpm`
(release in `out-acpm/include/config/kernel.release`). W=1 clean for the
changed C files; `dt-validate` clean for the new nodes.

## 5. Risks

1. **Mailbox clock gated.** The first mailbox write (probe, `INTMR0`) hangs the
   phone if the CMU_APM gate is off. Low: the gate is under automatic clock
   gating, Google's driver uses the mailbox without ever touching it, and the
   APM block is always on.
2. **Wrong SRAM layout.** Caught by the new checks: probe fails with
   "Implausible channel count" or "... outside the SRAM" before any message.
3. **DVFS channel not in polling mode.** Upstream supports polling only; a
   transfer then fails with "Interrupt mode not supported" (no hang). The fix
   would be IRQ support (SPI 78).
4. **Firmware answers in another word.** Google's `exynos_acpm_get_rate()`
   returns `cmd[3]` if non-zero, else `cmd[1]` (`acpm_dvfs.c:189-191`);
   upstream reads `cmd[1]`. A2 shows which: rates that are 0 or timestamps mean
   the reply format differs. Nothing is written in A2.
5. **Overheating.** No GPU thermal limit exists yet (the ACPM TMU on channel 9
   has firmware ops upstream, `exynos-acpm-tmu.c`, but no thermal driver uses
   them). The firmware's own TMU still has hardware trips (stock thresholds up
   to 120 °C, `R/dmesg.txt:1060`). We cap at 572 MHz until a thermal zone with
   GPU cooling exists.
6. **Concurrent APM users.** Nothing else on our kernel talks to ACPM, so
   upstream's per-channel locking is enough.
7. **Changing rates of a powered-off GPU.** kbase skips DVFS while G3D is off
   (`pixel_gpu_dvfs.c:98-103`). On our kernel G3D never powers off
   (`GPU-PLAN.md` G2, the always-on udev rule), so this can't happen yet. It
   matters for the G3D power-domain work (G4c).

## 6. PMIC, thermal and RTC on top of this link (not built)

- **S2MPG12 (main) / S2MPG13 (sub) are not S2MPG10/11 register-compatible.**
  Same transport (ACPM channel 2; S2MPG12 on PMIC bus 0, S2MPG13 on bus 1:
  `GS/drivers/mfd/s2mpg12-core.c:63`, `s2mpg13-core.c:57`), same address-block
  scheme (common 0x0, PM 0x1, RTC 0x2, meter 0xA, `s2mpg12-core.c:29-36`), but
  different maps: CHIPID at 0x0B (S2MPG10/11: 0x00), BUCK1M OUT1 at 0x18
  (S2MPG10: 0x19), BUCK1S OUT1 at 0x10 (S2MPG11: 0x13); S2MPG12 has 10 bucks
  and 28 LDOs (S2MPG10: 10/31), S2MPG13 13 bucks and 28 LDOs (S2MPG11: 12/15)
  (`GS/include/linux/mfd/samsung/s2mpg1[0-3]-register.h`).
  Work: `sec-acpm.c` device types and regmaps, `sec-irq.c` tables, regulator
  descriptors in `s2mps11.c`, binding + `samsung,s2mpg12-regulator.h`. Read-only
  first (regulator `regulator-always-on` everywhere, no voltage writes) until
  the map is checked against `R/live.dts:13096-13760`.
- **GPU rails need none of this** (`GPU-PLAN.md` 2.2): ACPM sets them.
- **Thermal**: a thermal driver on the upstream ACPM TMU ops (channel 9), then
  `#cooling-cells` on the GPU and the `G3D` zone. Lifts the 572 MHz cap.
- **RTC**: S2MPG12's RTC block (0x2xx) through `rtc-s5m` once the S2MPG12 MFD
  exists.

## 7. Runbook (gated; run with the user, phone in Arch over USB)

```sh
cd ~/Projects/omarchy-mobile
export KERNEL_OUT=$HOME/android/mainline/out-acpm
```

Each stage is one `tools/acpm-stage` call. Add `--watchdog` for A1–A3 (a hang
then resets on its own, and `tools/acpm-stage --pstore` saves the console).

### A0. Install (no ACPM access)

```sh
# 1. blacklist first, so the new DTB cannot autoload the ACPM modules
tools/phone-ssh 'cat > /etc/modprobe.d/omamobile-acpm.conf' \
  < packages/omamobile-device-cheetah/vendor/modprobe.d/omamobile-acpm.conf
# 2. modules for the new kernel, 3. slot B, reboot
bin/omamobile modules-push
bin/omamobile push
tools/phone-ssh 'uname -r; ls /sys/firmware/devicetree/base/firmware/; lsmod | grep -c "acpm\|exynos_mailbox"'
```

- **Expect:** the ACPM kernel boots, `power-management` exists, the count is 0.
  **No GPU**: Panthor waits for `clk_acpm` (`/dev/dri` has only simpledrm's
  card), so the session renders on the CPU until A2.
- **Risk:** none beyond a normal kernel update.
- **Rollback:** the previous images (`out-gpu` or the current omamobile build)
  with `bin/omamobile push`, or let ABL fall back to slot A.

### A1. Read-only handshake

```sh
tools/acpm-stage --watchdog a1
```

- **Does:** loads `exynos_mailbox` (one write: AP interrupt mask) and
  `acpm_protocol` (reads the channel table, requests mailbox channels). **No
  message is sent.**
- **Expect:** one `chan i: id .. type .. rx ../../.. indr ../../.. tx ../../.. qlen .. mlen .. poll ..`
  line per channel (`dump_chans=1`, SRAM reads only), then
  `N channels, M usable`. Channels whose queues fall outside the SRAM are
  logged as `skipped` and refused later; only channel 0 (DVFS) must be usable,
  with `poll 1` and `mlen` ≥ 16. Channel 2 (PMIC) and 9 (TMU) should be usable
  too, for later work.
- **First run (2026-10-12, integration kernel `-00161-gc9629d5ab1c3`):** failed
  safely with "Channel 3 queues outside the SRAM", because the first version
  rejected the whole table. Nothing was sent; the phone was fine. Google's
  driver maps the same window (`0x18500000`, `0x48000`: `gs201.dtsi:562`,
  `R/iomem.txt:76`) and never checks the table, so channel 3 is one the AP
  doesn't use (it's not in any stock `acpm-ipc-channel`). Fixed by skipping
  such channels (`firmware: samsung: acpm: skip channels the AP cannot use`).
  The rerun's dump shows what channel 3 holds (for example a `type 2` =
  `TYPE_BUFFER` channel, or offsets that are absolute addresses).
- **Risk:** low. A hang means the mailbox APB clock is gated (risk 1).
- **Rollback:** `modprobe -r acpm_protocol exynos_mailbox`; reboot.

### A2. Query the DVFS levels (still read-only)

```sh
tools/acpm-stage --watchdog a2
```

- **Does:** loads `clk_acpm`. Registering the 15 clocks sends one `FREQ_GET`
  per domain on channel 0; the script then reads every clock once more.
- **Expect (Hz):** mif 3172000000 (A2 read 2028000000: see section 2), int 533000000, g3d 151000000,
  g3dl2 151000000, gpu 151000000, CPU clusters near their boot levels
  (section 2), the rest at the table's levels. Then Panthor binds:
  `/dev/dri/card1` + `renderD128`, devfreq lists 12 frequencies,
  `cur_freq` 151000000, cap 0. Restart the session (`systemctl restart sddm`)
  to get the GPU back in Hyprland.
- **Check:** if values are 0 or look like timestamps, stop: the reply format
  differs (risk 4). If g3d is not 151 MHz, note it; nothing changes it while
  the cap is 0.
- **Risk:** low-medium: the first messages to the firmware. A wrong channel
  would make the firmware read a DVFS GET as something else; a timeout
  ("Timeout! ch:0") without a hang means no reply.
- **Rollback:** `modprobe -r panthor clk_acpm acpm_protocol exynos_mailbox`.

### A3. One step up and back

```sh
tools/acpm-stage --watchdog a3
```

- **Does:** cap 202000 kHz, devfreq pinned to 202 MHz: ACPM sets G3DL2 to
  302 MHz, then G3D to 202 MHz. 20 s of GPU load (vkcube in the session, or
  glmark2 offscreen). Then 151 MHz (G3D first, then G3DL2), cap back to 0.
- **Expect:** after the step `cur 202000000`, `g3d 202000000 g3dl2 302000000`;
  the load runs without GPU faults (no `panthor ... timeout`/`MMU fault`);
  after the return `cur 151000000`, both at 151 MHz. `trans_stat` shows the
  transitions.
- **Risk:** medium: the first writes to the firmware. ACPM picks the voltage
  from the fused table, so the risk is a firmware or GPU fault, not
  over-voltage. 202/302 MHz is the lowest real pair and only one step above
  boot.
- **Rollback:** `tools/acpm-stage off`; if the GPU misbehaves,
  `modprobe -r panthor`, then reboot (the firmware keeps the last rate across a
  driver reload, and ABL resets it at boot).

### A4. devfreq over the table

```sh
tools/acpm-stage --watchdog a4             # up to 572 MHz (default cap)
tools/acpm-stage --max 848000 --load 60 a4 # full table, only with a temperature check
```

- **Does:** cap 572000, min/max opened, `simple_ondemand` scales with load.
- **Expect:** `trans_stat` spread over 151–572 MHz under load and back to
  151/202 MHz when idle; g3dl2 always ≥ g3d; glmark2/vkcube scores clearly
  above A2's. Thermal zones listed at the end (none for the GPU yet).
- **Risk:** medium-high only at 701–848 MHz without thermal (risk 5). Watch
  the case temperature; stop if it gets hot.
- **Rollback:** `tools/acpm-stage off`.

### A5. Make it the default

When A1–A4 pass: in `omamobile-acpm.conf` replace the three `blacklist`
lines with `options clk_acpm gs201_gpu_max_khz=572000`, bump the
`omamobile-device-cheetah` version, publish it to `[omamobile]`
(`tools/repo-build`, `tools/repo-push`), and merge `omamobile-acpm` into
`omamobile`. Raise the cap to 848000 when GPU thermal throttling exists.

## 8. After this

1. CPU DVFS: cpufreq-dt on the CPUCL0-2 ACPM clocks with OPP tables from the
   ECT levels above (the CPUs are at boot levels today).
2. ACPM TMU thermal driver, GPU cooling, then lift the GPU cap.
3. MIF devfreq (power saving; MIF is pinned at maximum today).
4. S2MPG12/13 MFD + regulators (read-only first), RTC, then the G3D power
   domain with performance states (and the GPU pairing moved there).
