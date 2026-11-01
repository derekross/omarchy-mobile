<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 Pro (raven): power

Status (2026-10-16): **idle drain with the screen off is about 418 mA on
battery** (kernel `gb4d96e9c3ab7`, section 1; A/B runs show C2 saves 18 mA
and UFS clock gating 125 mA). Earlier, 460 mA, down from 610 mA
(kernel `g25b76ccf7ce2`, stacked
bring-up branch; now `omamobile-gs101-power` and `-display`): MIF at
1014 MHz, 13 unused power domains off, DECON's trigger masked while dark.
Cluster power-down (`exynos_pmu.cpd`, default 0) was an experiment on the
bring-up branch only and still needs a battery run. Open: Wi-Fi's
PCIe L1 substates, runtime PM for the GPU, real suspend. Thermal zones
work (section 3).

## 1. Measurements

**On battery, locked, panel off (bl_power 4):** 04:25-04:55, 2026-10-15, kernel
`g2c95d46a6603-dirty`, Wi-Fi associated with power save on. Log:
`logs/raven-drain-1.csv`.

- A steady 594-652 mA (current_avg about 610 mA).
- Charge went from 1564 to 1300 mAh in 25 min, and capacity from 37 % to 30 %:
  about 14 % an hour, roughly 7 h from full.
- CPU idle: about 98 % of the time in each core's deepest state (WFI or
  `cpu-*-sleep`). No cluster-off state exists.

**A/B while charging from the laptop:** the input is roughly fixed, so changes
in battery current show changes in system draw. 20 s means, noise about ±15 mA.

| Change | Saving |
| --- | --- |
| DECON0 HW trigger masked (TRIG_CON bit 4) while the panel is off | ~67 mA |
| Wi-Fi rfkill (associated, power save on) | ~60-80 mA |
| CPUs 4-7 offline | ~0 |
| All clusters capped at minimum frequency | ~0 |
| MIF 2028 to 1014 MHz (screen on) | ~70 mA |
| MIF 2028 to 421 MHz (screen on) | ~80 mA |
| TPU domain off | ~9 mA |
| Nine camera domains off | ~22 mA |
| MFC, G2D, BO domains off | ~14 mA |

All 23 gs101 power domains read on at boot (PMU regmap probe). Done:
- MIF boots at 1014 MHz (`assigned-clock-rates` on `acpm_ipc`);
- the 13 unused domains are `google,gs101-pd` nodes that genpd turns off at
  boot (exynos-pm-domains through the PMU regmap, no `pd_ignore_unused`);
  all 13 read `off` in `pm_genpd_summary`.

About 330 mA is still unexplained.

## 2. Suspects and work

1. **MIF stays at 2028 MHz,** the ACPM DVFS rate that ABL leaves (clk `mif`).
   Nothing lowers it. Next: an ACPM DVFS floor and ceiling policy for MIF, and
   INT, with DECON's bandwidth needs (about 1 GB/s at 60 Hz) as the floor
   while lit.
2. **There are no cluster power-down idle states.** Google's DT has only
   the per-core c2 (PSCI 0x0010000). Cluster power-down (CPD) belongs to
   Google's `exynos-cpupm`: when the last core of a cluster idles, it calls
   `cal_cluster_disable(cal_id)`, which:
   - hints `cpu_inform_cpd`;
   - sets CPUCLn `HCHGEN_CLKMUX_CPU` bit 4 (CMU at `0x20C00000+0x0844` for
     cluster 0);
   - calls EL3 through PMUCAL_EXT_FUNC `clusterN_noncpu_down` (id 0x29;
     `noncpu_up` is 0x28);
   - clears the mux bit.

   `cal_cluster_enable` runs on the first wake. Source: `kernel/gs` raviole
   android14, `exynos-cpupm.c`, `cal-if/pmucal_cpu.c` and
   `flexpmu_cal_cpu_gs101.h`. This means SMCs in the idle path, with
   cluster coordination: a port of its own, the riskiest item here. Each core has only its own
   sleep (`psci_idle`), so the DSU/L3 and cluster logic never power off.
   Google's gs101 has cluster idle states (CPD). Next: compare with Google's
   DT and add the PSCI cluster states.
3. **Wi-Fi's PCIe link never reaches L1.1/L1.2.** ASPM L1 is enabled on
   both ends, but the root port advertises no L1 substates (L1SubCap all
   `-`), while the BCM4389 supports L1.1 and L1.2. Google enables them with
   its own code (`exynos_pcie_rc_set_l1ss()` in `soc-gs-pcie/pcie-exynos-rc.c`,
   about 300 lines of PHY, ELBI and CLKREQ handling). Port it with care:
   ELBI accesses while the PHY is isolated hang the SoC. That's a guess from 60-80 mA
   with power save on. Next: check ASPM on the gs201/gs101 PCIe port.
4. **Done (`g25b76ccf7ce2`): DECON's trigger is masked while the display is
   off.** gs-dsim-cmd masks it after DCS display off and unmasks it before
   display on (`google,decon` phandle); TRIG_CON reads `0x3071` with the
   frames stopped while dark, `0x3061` afterwards. The ~67 mA saving is
   proven; it needs a kernel path, either gs-dsim-cmd telling DECON or
   gs-decon once D3 works.
5. Power domains still on: AoC off drew ~15 mA less (now in the boot-time
   off list, `27488a822`); G3D + embedded G3D off with panfrost unloaded,
   ~12 mA (runtime PM on the GPU node later; a panfrost reload ran into one
   job timeout). Rails ABL leaves on: not yet checked.

**Second battery run** (05:24-05:34, kernel `g25b76ccf7ce2`, locked, panel
off, Wi-Fi on): 437-475 mA, mean about 460 mA. That's 76 mAh in 10 min, 31 %
to 29 %. Down from about 610 mA with MIF at 1014 MHz, the 13 unused domains
off and DECON's trigger masked while dark: about 150 mA, roughly 10 h
instead of 7. Log: `logs/raven-drain-2.csv`.

**Cluster power-down (2026-10-15, `ga87365f74ac5`):**
- exynos-pmu hints CPU_INFORM CPD (2) from the last idle CPU of a cluster
  allowed by `exynos_pmu.cpd` (bitmask, default 0). Sampling the PMU
  CLUSTERn_NONCPU_STATUS 200 times from CPU0: with cpd=0 no cluster was
  ever off; with cpd=6, cl1 was off 195/200 and cl2 139/200.
- Stable over minutes with cpd=4 and cpd=6. The A/B while charging showed
  no difference outside the noise, so it needs a battery run.
- Soak: cpd=6 set at runtime.
- Seen twice: right after `bin/omamobile push`, the new kernel booted, then
  rebooted cleanly about 11 s later. To chase in push.

**Third battery run** (2026-10-16 07:11-07:19, kernel `gb4d96e9c3ab7`,
locked, panel off, Wi-Fi on, `tools/power-ab baseline --phase 120
--rounds 2`): **418 mA** (1.77 W); A/B differ by 3 mA. Since the second
run: GPU DVFS (idle at 151 MHz), the merge-test kernel without
`exynos_pmu.cpd`. MIF reads 1014 MHz with the panel off (gs-decon drops
its 120 Hz floor of 1352 MHz on disable). EAS is on: energy model for
the three clusters (capacity 160/498/1024), `sched_energy_aware` 1.

**A/B on battery** (2026-10-16 07:55-10:08, kernel `gb4d96e9c3ab7`, locked,
panel off, Wi-Fi on, `tools/power-ab`, 120 s phases, 20 s settle, 4 rounds
unless noted):

| Test | A | B | Saving |
| --- | --- | --- | --- |
| `c2`: per-core C2 off / on | 441.1 mA | 423.0 mA | **18 mA** (75 mW) |
| `ufs-gate`: UFS clock gating off / on | 557.7 mA | 432.5 mA | **125 mA** (484 mW) |
| `ufs-delay`, 2 rounds: Hibern8 after 150 / 4 ms | 430.7 mA | 429.2 mA | none |
| `units`: sensor proxy and auto-rotate stopped / running | 418.6 mA | 417.8 mA | none |

C2 and UFS clock gating are on by default and pay off; the 150 ms Hibern8
delay stays, and the sensor stack costs nothing measurable while idle. No
`ufshcd_err_handler` after the runs.

## 3. Thermal

Kernel branch `omamobile-raven-thermal`: `thermal: samsung: add gs101
sensors read through ACPM` (`3f83fd6e1`) and the gs101 thermal zones with
CPU cooling (`4fd3f0dd1`); `CONFIG_GS101_ACPM_THERMAL=m`.

- **Thermal (2026-10-14):** `gs101_acpm_tmu` reads the six TMU sensors
  (BIG, MID, LITTLE, G3D, ISP, TPU) from the ACPM firmware, channel 9.
  First reading at idle: 61-63 C (CPUs), 50-51 C (others). Each CPU
  cluster throttles from 85 C; everything is critical at 110 C. Before it,
  Chromium on llvmpipe reset the phone about 90 s in, twice.

## 4. Review checks for PRs #6-#9 (runbook, 2026-10-26)

Derek's reviews of linux-omarchy-mobile #6-#9 asked for things only the
phone can show. Every step below is gated: the human runs or approves it.
The phone runs `7.3.0-rc6-omamobile-push1-g0422abf64c05`
(`omamobile-gs101-int` 0422abf64, images in
`~/android/mainline/out-gs101-int/images`): that is the rollback for every
push here.

Two kernels, so one boot changes one thing (AGENTS.md):

| Kernel | Branch (worktree, output) | What it adds to the phone's kernel |
| --- | --- | --- |
| initcheck | `omamobile-gs101-int-initcheck` (`wt-gs101-int-initcheck`, `out-gs101-int-initcheck`) | the TMU driver's channel from match data, and a NOT FOR MERGE dump of the TMU trip registers around `ACPM_TMU_INIT` (`gs101_acpm_tmu.initcheck=1`) |
| review | `omamobile-gs101-int-review` (`wt-gs101-int-review`, `out-gs101-int-review`) | initcheck, plus #7 v2's GPU critical trip at 115 °C, #8 v2's s6sy761 (CONFIG_SPI guard, reset work ordered against suspend and unbind), #6 v2's Bluetooth (CMU_APM mux fix without the DT override, BCM4389 delay as match data, BT pin states) |

The power rework (#9 v2, André Draszik's pmdomain series) is not in either:
it changes the power-domain driver and leaves the AoC's domain on, so it
gets its own boot after these (R5).

**R1 (read-only, no push):** what Derek asked that the running kernel can
already answer.

```sh
tools/phone-ssh 'tr -d "\0" < /proc/device-tree/model; echo; uname -r
grep -iE "mif|acpm" /sys/kernel/debug/clk/clk_summary | head
dmesg | grep -ciE "underrun|underflow"'
```

Then a GPU-heavy minute (the shell's app switcher, Chromium scrolling a
long page), and the `dmesg` count again.

- **Pass:** the model reads Raven; the ACPM MIF clock reads 1014000000;
  the underrun count doesn't grow. Quote the clk line in #9's message.
- **Stop:** a different model, or MIF not at 1014 MHz: record, don't push.
- **Risk:** none (reads).

**R2 (write, reversible, low):** have the TMU driver dump its registers at
the next boot.

```sh
tools/phone-ssh 'echo "options gs101_acpm_tmu initcheck=1" > /etc/modprobe.d/omamobile-thermal-initcheck-bringup.conf'
```

- **Rollback:** `rm /etc/modprobe.d/omamobile-thermal-initcheck-bringup.conf`.
  The running kernel ignores the option (it has no such parameter).

**R3 (push, reboot; the human approves):** the initcheck kernel (or the
review kernel, to check #6-#8 on the same boot).

```sh
cd ~/projects/omarchy-mobile-topic
sg docker -c "env DEVICE=raven KERNEL_DIR=$HOME/android/mainline/wt-gs101-int-initcheck \
    KERNEL_OUT=$HOME/android/mainline/out-gs101-int-initcheck TMPDIR=$HOME/android/tmp-build \
    bin/omamobile push"
```

- **Screen:** the phone reboots; the splash and the lock screen come back.
- **Expect:** SSH back within about 60 s, `uname -r` reads the new
  release, slot B marked good.
- **Stop:** no SSH after 3 minutes: ask the human to hold Power about
  30 s. If it doesn't come back, roll back.
- **Rollback:** `bin/omamobile push` with
  `KERNEL_DIR=~/android/mainline/wt-gs101-int KERNEL_OUT=~/android/mainline/out-gs101-int`;
  without SSH, Volume Down + Power about 20 s for fastboot and
  `bin/omamobile flash` with the same variables.
- **Built (2026-10-26):** `out-gs101-int-initcheck/images`, release
  `7.3.0-rc6-omamobile-push1-g261ceb0345ea`; its DTBs are byte-for-byte
  the running ones' once decompiled. No early boot logo (this branch's
  `bin/omamobile` has no `SPLASH_BGRA_GZ` yet): the screen stays dark
  until Plymouth.
- **Risk:** low. The only new firmware request is TMU_IPC_REG_READ (0xfe),
  reads of TMU registers through ACPM, inside the range Google's own
  `tmu_reg_read` parameter allows.

**R4 (read-only):** compare the registers before and after INIT.

```sh
tools/phone-ssh 'dmesg | grep initcheck' > logs/raven-tmu-initcheck.log
grep -c initcheck logs/raven-tmu-initcheck.log
diff <(grep " before " logs/raven-tmu-initcheck.log | sed "s/.*before //") \
     <(grep " after " logs/raven-tmu-initcheck.log | sed "s/.*after //")
```

- **Pass:** 340 lines (2 TMUs x (5 + 16 x 5) registers, before and after),
  every one with return code 0, and the diff empty: INIT leaves CONTROL,
  the probe enables and each probe's rise thresholds and interrupt enables
  as the bootloader set them. Record CONTROL's value (the trip-enable bit)
  for the reply.
- **Not a pass:** any register differs. INIT changes the trip setup; the
  driver then has to program the thresholds itself (Google's
  `set_threshold`, `interrupt_enable`, `tz_control` after INIT).
- **Stop:** return codes other than 0 on every read: the firmware doesn't
  serve 0xfe; record it and fall back to Derek's other option, a test that
  the hardware trip fires (not here: it powers the phone off hot).
- Afterwards: R2's rollback, so the next boot is quiet.

**R4b (review kernel only, read-only):** #6-#8 on the same boot. Built
2026-10-26: `out-gs101-int-review/images`, release
`7.3.0-rc6-omamobile-push1-g1de37d2bef30` (push it as in R3 with
`KERNEL_DIR=~/android/mainline/wt-gs101-int-review
KERNEL_OUT=~/android/mainline/out-gs101-int-review`). Its DT differs from
the running one's in three places only: no `assigned-clock-parents` on
`usi_apm1`, the Bluetooth node's pin states (and their three groups), and
`gpu_crit` at 115 °C. No early boot logo, as in R3.

```sh
tools/phone-ssh 'cat /sys/kernel/debug/clk/clk_summary | grep -E "mout_apm_func|usi1_uart"
dmesg | grep -iE "hci_bcm|bluetooth|s6sy761|thermal" | tail -30
bluetoothctl show | head -3; cat /sys/class/thermal/thermal_zone*/trip_point_1_temp'
```

- **Pass:** mout_apm_func reads mout_apm_funcsrc as its parent and the
  UART clock about 197 MHz (as the DT override gave); Bluetooth comes up
  (if B3's silent chip has recovered; otherwise note it, the clock lines
  still count); touch works, then a lock and unlock and a display off/on
  keep it working; the GPU zone's critical trip reads 115000.
- **Stop:** the UART clock at about 12 MHz (the mux fix reads the wrong
  field): roll back.

**R5 (later, its own boot):** the power rework, #9 v2. Needs an
integration kernel with `omamobile-gs101-power-v2` in place of
`omamobile-gs101-power` (not built yet). Expect the same domains off
(their PMU STATUS 0), about the same idle current, and the AoC still
starting with its domain left on. Derek also asked whether a warm reset
brings the domains back: answered without stock, from the initramfs, in
R5b below (2026-10-27).

**Results (2026-10-26, review kernel `7.3.0-rc6-omamobile-push1-g1de37d2bef30`,
after a reinstall over GrapheneOS):** boot check `ok` on every line, the
first clean one since 2026-10-20.

- R1 (#9): MIF reads 1014000000 with the panel off (the assigned rate) and
  1352000000 while lit (gs-decon's 120 Hz floor); 0 underruns or underflows
  across boot, a minute of normal use, a lock and an unlock; no panfrost
  faults.
- R4 (#7): 340 lines, every read rc 0, and before == after: ACPM_TMU_INIT
  changes none of CONTROL, CONTROL1, PROBE_EN_CON, SAMPLING_INTERVAL,
  EMUL_CON or any probe's rise thresholds and INTEN, on either TMU. CONTROL
  reads 0x00019003 on both (bit 12, the trip enable in the older Exynos
  TMU layout, is set). Log: `logs/raven-tmu-initcheck.log`. R2's option
  removed afterwards.
- R4b (#6): mout_apm_func's parent reads mout_apm_funcsrc, whose parent is
  pll_alv_div2_apm, and the UART clock 196608000 without the DT override;
  BCM4389C1 patched (build 0203), its own address set, a 10 s scan lists
  devices. Bluetooth works again (B3).
- R4b (#7): big and GPU critical trips read 115000.
- R4b (#8): the controller's boot-time power cycle, then no failed reads or
  resets through a minute of use, a lock and an unlock; the user saw no
  problem with touch.
- R5 (#9 v2, 2026-10-26, `7.3.0-rc6-omamobile-push1-gb3d6253b0d61` = the
  review kernel with `omamobile-gs101-power-v2`'s driver, bindings and DT):
  the same 13 domains read off in `pm_genpd_summary` (g2d, mfc, csis, pdp,
  dns, g3aa, ipp, itp, mcsc, gdc, tnr, bo, tpu; IPP under PDP and DNS
  under ITP), now `google,gs101-pd` children of the PMU. The AoC's domain
  is left to the AoC: it came online (69 services), the sound card and the
  sensor proxy came up; its three ssmt/acpm-reset/invalid-resource lines
  were there on the previous kernel too. No UFS errors. Boot check: only
  `services` (omamobile-sitd-2, the eSIM, stopped by hand while debugging,
  unrelated). Not measured: an idle-current A/B against the old driver.

**R5b, warm reset (Derek's #9 question, 2026-10-27,
`7.3.0-rc6-omamobile-push1-gb3d6253b0d61` = #9 v2):** the boot chain powers
the 13 domains back on after a warm reset. Run from the initramfs only
(`omamobile.initramfs`, `userdata` dropped from the guard's allowlist so
GrapheneOS's data stayed read-only), on slot B, with GrapheneOS on slot A.
- **`pd_ignore_unused` can't answer this on 7.3.** It only skips
  `genpd_power_off_unused()`; genpd's `sync_state` (`of_genpd_sync_state()`)
  still turns off every domain with no consumer about 0.4 s into boot. So
  `pm_genpd_summary` read all 13 `off` with the flag too, after a warm and
  after a cold boot. What answers it is each domain's `active_time` in
  `/sys/kernel/debug/pm_genpd/<name>/`: the driver reads the PMU STATUS at
  probe (`pm_genpd_init(..., !on)`), so a domain found on accumulates
  active time until `sync_state`, and one found off reads 0.
- **Cold control** (fastboot menu Power off with the cable out, over 30 s
  off, Power): all 13 about 375 ms active (dns 5 ms, registered later).
  The bootloader leaves them on.
- **Warm** (`reboot-to omamobile` from the same image once all 13 read
  off): all 13 about 380 ms active (dns 7 ms). The bootloader powered them
  on again, so a warm reboot into stock finds them as it does after a cold
  boot.
- **Open:** one unexplained reset on this kernel at about 06:58 UTC, during
  a long `cat` of `modem_a` over SSH (domains off, 13 read off): no pstore
  entry, both watchdogs inactive, and the initramfs's USB-fallback crash
  doesn't apply (the gadget was configured). Not seen on 10-26's Arch boots
  with the same kernel. Whether a button was pressed is being checked.
- Fastboot's Power off with the cable in restarted the phone at once
  instead of powering off: not a cold boot.
- Each unmarked test boot spends one of slot B's retries; the fourth
  (the cold boot) fell back to slot A. `fastboot --set-active=b` refills
  them.
