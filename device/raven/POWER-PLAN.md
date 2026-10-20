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
