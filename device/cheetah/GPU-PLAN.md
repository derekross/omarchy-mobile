# GPU acceleration plan: Mali-G710 on Panthor + Mesa (cheetah / gs201)

Status (2026-10-12): **Hyprland renders on the Mali-G710 by default, with
frequency scaling.** G0-G3 passed ("G2 result" at the end): Panthor
autoloads at boot, and patched Mesa (`packages/mesa` 26.2.4-1.1) gives
OpenGL ES 3.1 and PanVK Vulkan 1.4. DVFS runs through ACPM (`ACPM-PLAN.md`
A1-A5, omamobile-device-cheetah 0.1.13+): 151 MHz idle, capped at 572 MHz
until there is a GPU thermal limit. Scan-out is now gs-decon
(`DISPLAY-PLAN.md` D6), not simpledrm. Kernel: `omamobile-gpu` @ `1f1b44ac6`
(`wt-gpu`), merged into `omamobile-int`. **Next:** G4 (a real G3D power
domain; the GPU stays powered through `20-omamobile-gpu-always-on.rules`),
the thermal limit that lifts the cap, and upstreaming the G710 Mesa entry.

Earlier status (historical, superseded by the status above): G0, G1 and G2 done (2026-10-11). Hyprland renders on the Mali-G710; see "G2 result" at the end. Written 2026-10-11 against
`omamobile` @ `cbde67d76` (Linux 7.3-rc6), Arch `mesa 1:26.2.4-1`,
`linux-firmware-other 20260916-1`.

Goal: Hyprland renders on the GPU through Mesa Panfrost (GL/GLES) and PanVK
(Vulkan), using the upstream Panthor kernel driver. When this was written it used Mesa
`kms_swrast` on simpledrm (`/chosen/framebuffer@fac00000`).

Path abbreviations used below:

- `L/` = `/home/raven/android/mainline/linux` (our kernel)
- `G/` = `/home/raven/android/omamobile/out-kernel/google/gs-6.1/private`
  (Google's GPL gs201 kernel)
- `GS/` = `G/google-modules/soc/gs`
- `R/` = `/home/raven/android/reference/cheetah-stock-cp2a-root`
  (stock Android live DT and logs)
- `M/` = Mesa at tag/branch `26.2` on gitlab.freedesktop.org

> **Incident during this research.** A single 32-bit `/dev/mem` **read** of
> PMU `0x18061e00` (`G3D_CONFIGURATION`) with `tools/devmem` crashed the
> phone right away, and it rebooted (`panic=10`). It came back on its own and
> Hyprland restarted. The previous boot's journal holds no crash log. Until
> this is understood, **do not touch PMU G3D registers (`0x18061e00`–`0x18062010`)
> or any G3D/CMU_G3D/GPU register from user space**. That includes
> `cat /sys/kernel/debug/regmap/18060000.system-controller-pmu_regs/registers`,
> which reads that range through the same raw `readl`
> (`L/drivers/soc/samsung/gs101-pmu.c:380-384`). Read PMU state from inside
> the kernel through the EL3 SMC instead (see section 2.3).

---

## 1. GPU block facts

| Item | Value | Evidence |
|---|---|---|
| GPU | Mali-G710, arch **10.8.6**, product major **0x2**, r0p0, status 4 | `R/dmesg.txt:4006` "GPU identified as 0x2 arch 10.8.6 r0p0 status 4" |
| Raw GPU_ID (derived) | `0xa8620004` (Panthor will print `id 0xa862`) | field layout from the line above |
| Register base / size | `0x28000000`, size `0x480000` | `G/devices/google/gs201/dts/gs201-gpu.dtsi:50-52`, `R/live.dts:5991-5993`, `R/iomem.txt:262` |
| IRQs (GIC SPI, level-high) | JOB **329**, MMU **330**, GPU **328** | `GS/include/dt-bindings/interrupt-controller/gs201.h:342-344`; `R/live.dts:5994` (`0x149 0x14a 0x148`) |
| Panthor IRQ order | `job, mmu, gpu` = 329, 330, 328 | `L/Documentation/devicetree/bindings/gpu/arm,mali-valhall-csf.yaml` (interrupt-names) |
| Shader core mask | Not in DT. Read from `GPU_SHADER_PRESENT` at probe (`L/drivers/gpu/drm/panthor/panthor_hw.c:229-236`). Marketed as MC7. Confirm from Panthor's probe log. | — |
| Power domains (kbase) | `pd_g3d` ("top") + `pd_embedded_g3d` ("cores") | `gs201-gpu.dtsi:60-64` |
| CMU_G3D base | `0x27f00000` | `G/devices/google/gs201/dts/gs201-pm-domains.dtsi:53` (`cmu_id`), `GS/drivers/soc/google/cal-if/gs201/flexpmu_cal_local_gs201.h:444-467` |
| D_TZPC_G3D / SYSREG_G3D | `0x27f10000` (DTZPC; `need_smc = 0x27f10204`) / `0x27f20000` | `gs201-pm-domains.dtsi:52`, `flexpmu_cal_local_gs201.h:493-494` |
| GPU S2MPU | `s2mpu_g3d@20080000`, `always-on` (outside the G3D domain) | `R/live.dts:9585-9592` |
| Stock firmware | `mali_csffw-r54p3.bin` (kbase r54p3) | `R/vendor-firmware.txt`, `R/dmesg.txt:3972` |

### 1.1 Clocks

The GPU's clocks are in **CMU_G3D (`0x27f00000`)**. It has two PLLs:

- `PLL_G3D` (shader stacks): rate table 850, 700, 470 and 150 MHz.
- `PLL_G3D_L2` (top/L2/coregroup): rate table 1000, 750, 470 and 150 MHz.

Evidence: `GS/drivers/soc/google/cal-if/gs201/cmucal-node.c:70-81,135-136`.

The three GPU clock gates line up with Panthor's three clock names:

| Panthor name | CMU_G3D gate | Offset | Parent |
|---|---|---|---|
| `core` | `CLK_BLK_G3D_UID_GPU_IPCLKPORT_CLK` | `0x2014` | `MUX_CLKCMU_EMBEDDED_G3D_TOP_USER` |
| `coregroup` | `..._GPU_IPCLKPORT_CLK_COREGROUP` | `0x2018` | `MUX_CLKCMU_EMBEDDED_G3D_COREGROUP_USER` |
| `stacks` | `..._GPU_IPCLKPORT_CLK_STACKS` | `0x201c` | `MUX_CLKCMU_EMBEDDED_G3D_STACKS_USER` |

Evidence: `cmucal-node.c:2244,2251,2255`; `cmucal-sfr.c:1625,1632,1636`.

Our `clk-gs201.c` covers only the CMU_TOP side (`CLKCMU_G3D_{GLB,NOCD,SWITCH}`
mux/div/gate at `L/drivers/clk/samsung/clk-gs201.c:122-124,190-192,276-278`;
IDs `L/include/dt-bindings/clock/google,gs201.h:51-53,119-121,205-207`).
It has **no CMU_G3D**.

**Google never sets GPU clock rates from Linux.** kbase calls `cal_dfs_set_rate()`
with the ACPM DVFS IDs `ACPM_DVFS_G3DL2 = 0x0B040006` (gpu0, top/L2) and
`ACPM_DVFS_G3D = 0x0B040005` (gpu1, shaders):

- `gs201-gpu.dtsi:78-79`
- `GS/include/dt-bindings/clock/gs201.h:319-320`
- `G/google-modules/gpu/mali_kbase/platform/pixel/pixel_gpu_dvfs.c:66`

The APM firmware (ACPM) programs the PLLs and the rail voltage together. A
Linux CMU_G3D driver therefore only needs gates and read-only PLLs. Rate
changes belong to ACPM.

### 1.2 OPP / DVFS table (Google DT, v2 table; kHz)

> **Correction (2026-10-12, `ACPM-PLAN.md` section 3):** this phone runs the
> **v1** table (11 levels, without 633 and 434 MHz). kbase drops v2 because
> this ECT's G3D domain has no 633/434 MHz levels; the stock kernel lists the
> v1 levels as GPU cooling states (`R/dmesg.txt:3989-3999`).

From `gs201-gpu.dtsi:106-127` (v1 table at `:86-104`). The live DT has the same
values in hex (`R/live.dts:6009-6012`).

| gpu0 (L2/top) | gpu1 (shaders) | notes |
|---|---|---|
| 996000 | 848000 | top level, requests INT ≥533 MHz, MIF ≥3172 MHz |
| 996000 | 762000 | MIF ≥845 MHz |
| 885000 | 701000 | MIF ≥845 MHz |
| 885000 | 633000 | |
| 750000 | 572000 | |
| 750000 | 510000 | |
| 603000 | 471000 | |
| 603000 | 434000 | |
| 603000 | 400000 | |
| 470000 | 351000 | |
| 470000 | 302000 | |
| 302000 | 251000 | |
| 302000 | 202000 | lowest |

`gpu_dvfs_max_freq = 900000` (`:133`). Stock logs "GPU max frequency
initialized to 848000 KHz" (`R/dmesg.txt:3986`).

**The DT holds no voltages.** kbase reads them at runtime from the
ECT/ASV fused tables (`cal_dfs_get_rate_asv_table`, `pixel_gpu_dvfs.c:566-567`),
and ACPM applies them. Our OPP table therefore carries **no `opp-microvolt`**,
and voltage stays ACPM's job.

---

## 2. Power

### 2.1 Domains and how Google turns them on

Two PMU power domains, `pd_g3d` → `pd_embedded_g3d` (child):

- `pd_g3d`: `samsung,exynos-pd` at `0x18061e00`, `cal_id 0xB1380007`,
  `need_smc = 0x27F10204`, `cmu_id = 0x27F00000`. Evidence:
  `gs201-pm-domains.dtsi:48-57`.
- `pd_embedded_g3d`: at `0x18062000`, `cal_id 0xB1380006`, `power-domains = <&pd_g3d>`.
  Evidence: `:59-67`.
- Same PMU offsets as gs101: `GS101_SUBBBLK_OFFSET_G3D 0x1e00`,
  `GS101_SUBBBLK_OFFSET_EMBEDDED_G3D 0x2000` (`L/include/linux/soc/samsung/exynos-regs-pmu.h:782,784`).
  Both ranges are already in the gs101 PMU regmap tables that gs201 reuses
  (`L/drivers/soc/samsung/gs101-pmu.c:98,100`; `exynos-pmu.c:127-128`).

The power-on sequence comes from Google's `pmucal_local_enable()`
(`GS/drivers/soc/google/cal-if/pmucal_local.c:41-71`) and the gs201 tables in
`flexpmu_cal_local_gs201.h`.

1. **PMU write** `G3D_CONFIGURATION (0x18061e00) bit0 = 1`, then poll
   `G3D_STATUS (0x18061e04) bit0 == 1` (`flexpmu_cal_local_gs201.h:438-441`).
   - PMU writes are secure-only. `pmucal_write_reg()` turns any write to the
     PMU_ALIVE base into `set_priv_reg()` = SMC `0x82000504`
     (`pmucal_rae.c:148-154`). Upstream already has this SMC write path as the
     PMU regmap (`tensor_sec_reg_write`, `L/drivers/soc/samsung/gs101-pmu.c:343-357`).
2. **DTZPC restore**: SMC `SMC_CMD_PREPARE_PD_ONOFF (0x82000410)` with
   `EXYNOS_WAKEUP_PD_DOWN (1)`, address `0x27F10204`, and
   `RUNTIME_PM_TZPC_GROUP (2)`.
   - Evidence: `GS/drivers/soc/google/exynos-pd_el3.c:28-37`,
     `GS/include/linux/soc/samsung/exynos-smc.h:42`,
     `GS/include/soc/google/exynos-el3_mon.h:16-19`.
   - Without this step, the TrustZone protection controller for G3D comes back
     from power-off in its reset (secure-only) state. Non-secure GPU access
     would then fault.
3. **Restore CMU_G3D** state (PLL_CON*, mux/div, `QCH_CON_*`,
   `CONTROLLER_OPTION`) and SYSREG_G3D `BUS_COMPONENT_DRCG_EN`/`MEMCLK`. These
   were saved before the power-off (`flexpmu_cal_local_gs201.h:443-512`).
4. Embedded (cores) domain: `EMBEDDED_G3D_CONFIGURATION (0x18062000) bit0`,
   then poll `0x18062004` (`:421-424`). No DTZPC step.
5. Power-off is the reverse: save CMU state, `exynos_pd_tz_save` SMC
   (`EXYNOS_GET_IN_PD_DOWN`), clear `G3D_CMU_G3D_CONTROLLER_OPTION` bit 24,
   then clear the CONFIGURATION bit (`pmucal_local.c:118-130`;
   `flexpmu_cal_local_gs201.h:518-522`).

kbase drives both domains with `pm_runtime_get_sync()` on the "top" and
"cores" genpd devices, plus the S2MPU device
(`G/google-modules/gpu/mali_kbase/platform/pixel/pixel_gpu_power.c:252-266,739`).

**Upstream `exynos-pd` cannot do this.** `exynos_pd_power()` writes the PMU
with plain `writel_relaxed` and only knows `exynos4210-pd` and `exynos5433-pd`
(`L/drivers/pmdomain/samsung/exynos-pm-domains.c:36-63,84-92`). On gs201 those
writes are silently ignored (`device/cheetah/NOTES.md`, "PMU registers are
secure-only"). It also has no DTZPC SMC and no CMU save/restore.

### 2.2 Regulators

The GPU rails are on the **S2MPG13** sub-PMIC (`G/devices/google/gs201/dts/gs201-pmic.dtsi`):

| Rail | Regulator | Line |
|---|---|---|
| `S2S_VDD_G3D` | `BUCK2S` | `:764-777` |
| `S8S_VDD_G3D_L2` | `BUCK8S` | `:849-862` |
| `L1S_VDD_G3D_M` (memories) | `LDO1S` | `:948-957` |

All three are `regulator-always-on` with
`regulator-initial-mode = <SEC_OPMODE_SUSPEND>`. That mode means the rail is
"changed by PWREN pin" (`GS/include/dt-bindings/regulator/samsung,s2mpg-regulator.h:10-14`):
the PMIC switches the rail on and off with the PMU's G3D power-domain signal,
and ACPM sets the voltage during DVFS. gs101 upstream describes the same thing
for S2MPG11 with `samsung,ext-control = <S2MPG11_EXTCTRL_G3D_EN>`
(`/home/raven/android/mainline/pmos-tensor/arch/arm64/boot/dts/exynos/google/gs101-pixel-common.dtsi:462-467`).

**Conclusion:** no S2MPG12/13 regulator driver is needed. Do **not** give
Panthor a `mali-supply`. A fixed regulator would only be a stand-in and would
hide the fact that voltage follows ACPM. Leaving `mali-supply` out is valid,
and the MT8196 binding variant has the same firmware-managed setup
(`arm,mali-valhall-csf.yaml`, `mediatek,mt8196-mali` branch: `mali-supply: false`,
no OPP table). The only real limit is that **we must not raise GPU clocks
behind ACPM's back**. Without ACPM DVFS the rail stays at whatever voltage
the last ACPM level set, so the clock must stay at the handoff rate.

### 2.3 Is the GPU powered at handoff?

**Very likely yes, but this is not yet verified on our kernel.** The stock
kernel's `exynos-pd` probe reads the status at 0.305 s and reports both
domains **on**, before anything in Linux has turned them on:

- `R/dmesg.txt:417` `18061e00.pd-g3d: on`
- `R/dmesg.txt:418` `18062000.pd-embedded_g3d: on`
- `GS/drivers/soc/google/exynos-pd.c:443` reads `cal_pd_status()`

So ABL leaves G3D powered and clocked. In our boot nothing powers it down:

- There is no PD driver for G3D.
- `pd_ignore_unused clk_ignore_unused` are on the command line.
- The kernel runs at EL2 in plain nVHE KVM, not pKVM ("CPU: All CPU(s) started
  at EL2", "Hyp nVHE mode initialized"). No hypervisor re-programs S2MPUs, and
  UFS DMA already works through `s2mpu_hsi2`. That suggests the S2MPUs pass
  traffic through after ABL.

Verifying this from user space crashed the phone (see the incident at the top).
Safe ways to verify:

- **(a)** A tiny debug module or early-boot print that calls
  `arm_smccc_smc(0x82000504, 0x18061e04, 0 /*READ*/, …)`, i.e. reads through
  EL3. The gs101 comment says the SMC read works for registers that are also
  writable (`gs101-pmu.c:376-379`), which covers CONFIGURATION/STATUS.
- **(b)** Just load Panthor (gate G1 below). If its `GPU_ID` read returns
  `0xa862…`, the domain is on, and the worst case is a reboot.

---

## 3. Panthor requirements

### 3.1 What the driver needs

| Need | Source | gs201 status |
|---|---|---|
| `compatible` | `dt_match`: `mediatek,mt8196-mali`, `rockchip,rk3588-mali`, `arm,mali-valhall-csf` (`L/drivers/gpu/drm/panthor/panthor_drv.c:1884-1888`) | Use `"google,gs201-mali", "arm,mali-valhall-csf"`. Add the enum entry to `arm,mali-valhall-csf.yaml`. No `panthor_soc_data` is needed at first (ASN hash is MT8196-only, `panthor_drv.c:1879-1882`). |
| `reg`, 3 IRQs named `job/mmu/gpu` | binding | Known (section 1). |
| `clocks`: `core` required, `coregroup`/`stacks` optional | `panthor_device.c:32-50` | No provider yet. Phase 1 uses a fixed-clock stand-in. |
| **OPP table: required** | `panthor_devfreq_init()` calls `devm_pm_opp_of_add_table()` and fails the probe on error unless a PM domain already registered an OPP table (`panthor_devfreq.c:157-178`, `panthor_device.c:232-234`) | Must add one, even if it has a single entry. |
| `power-domains` (0..5; ≥2 → attached as a list) | `panthor_device.c:56-61`; binding `maxItems: 5` | Optional. Phase 1 has none and relies on ABL. |
| `mali-supply`/`sram-supply` | optional (`-ENODEV` tolerated, `panthor_devfreq.c:167-168`) | Omit (section 2.2). |
| Timestamp / FW timer | `arch_timer_get_cntfrq()`; core clock only if the GPU counter is the source (`panthor_fw.c:387-392`) | A fixed clock is fine. |
| Product name | `GPU_PROD_ID_MAKE(10, 2)` → "Mali-G710" (`panthor_hw.c:130-131`) | Supported. |
| Firmware | `arm/mali/arch%d.%d/mali_csffw.bin` → **`arm/mali/arch10.8/mali_csffw.bin`** (`panthor_fw.c:811-816`; `MODULE_FIRMWARE` `:1553`) | Present, see 3.2. |
| Kernel config | `CONFIG_DRM_PANTHOR=m` already set (`/proc/config.gz` on the phone) | OK. |

### 3.2 Firmware

The firmware is already installed on the phone (`pacman -Ql linux-firmware-other`):

```
/usr/lib/firmware/arm/mali/arch10.8/mali_csffw.bin -> ../arch10.10/mali_csffw.bin   (282624 bytes)
/usr/lib/firmware/arm/mali/arch10.12/mali_csffw.bin -> ../arch10.10/mali_csffw.bin
/usr/lib/firmware/arm/mali/arch11.8 … arch13.8 (separate files)
```

G710 is arch **10.8**, the same as the RK3588's G610 that Panthor was built
on. So Panthor will request the file that `linux-firmware-other` ships.

Remaining risk: this is Arm's generic CSF build, not Google's
`mali_csffw-r54p3.bin`. Google's file is a kbase-ABI blob for r54p3, so do not
try it with Panthor.

### 3.3 What we lack (kernel)

1. **A DT GPU node** in `gs201.dtsi` (+ binding enum).
2. **Clocks.** Phase 1: a `fixed-clock` stand-in. Final: ACPM DVFS clocks
   `g3d` (shaders) and `g3dl2` (top/L2).
   - Upstream already has `clk-acpm` with exactly these, for gs101:
     `ACPM_CLK("g3d")` index 5, `"g3dl2"` index 6
     (`L/drivers/clk/samsung/clk-acpm.c:43-58`;
     `L/include/dt-bindings/clock/google,gs101-acpm.h`).
   - The indices match gs201's `0x0B040005/6` low bits.
   - We need gs201 ACPM plumbing: AP2APM mailbox, APM SRAM, an ACPM IPC node
     with a gs201 compatible, and the CMU_APM mailbox pclk.
   - Stock gs201 values from `R/live.dts:12961-12974`: mailbox reg
     `0x18210000`, SRAM `0x18500000` size `0x48000`, `initdata-base = 0xa000`
     (same as `ACPM_GS101_INITDATA_BASE`, `L/drivers/firmware/samsung/exynos-acpm.c:42,879-887`),
     IRQ SPI 78.
   - gs101 reference nodes: `L/arch/arm64/boot/dts/exynos/google/gs101.dtsi:492-497`
     (acpm_ipc), `:1866-1873` (mailbox), `:1920-1926` (sram).
3. **CMU_G3D driver** (gates + read-only PLLs) if we want `core`/`coregroup`/`stacks`
   as real gates. This is optional: the gates have auto clock gating
   (Q-channel), and rate belongs to ACPM.
4. **A gs201 G3D power-domain driver.** It performs SMC PMU writes, an SMC
   status read, the DTZPC restore/save SMC and the CMU_G3D save/restore
   (section 2.1). This is needed only for runtime power-off; until it exists,
   keep G3D always on.
   - Upstream shape: extend `exynos-pm-domains.c` with a regmap (PMU syscon)
     backend and a `google,gs201-pd` compatible, or write a gs201 genpd
     provider.
   - The MT8196 `mediatek,mt8196-mali` model (one firmware-backed
     PD + clock provider, OPP registered by the PD) is a good template for
     folding ACPM DVFS in later.

### 3.4 DT sketch (phase 1, not applied)

```dts
/* gs201.dtsi, top level */
gpu_clk_stub: clock-gpu-stub {
	compatible = "fixed-clock";
	#clock-cells = <0>;
	clock-frequency = <151000000>;	/* ECT boot level, see G0 status */
	clock-output-names = "gpu-stub";
};

gpu_opp_table: opp-table-gpu {
	compatible = "operating-points-v2";
	opp-151000000 { opp-hz = /bits/ 64 <151000000>; };	/* = stub rate */
};

/* in soc { } */
gpu: gpu@28000000 {
	compatible = "google,gs201-mali", "arm,mali-valhall-csf";
	reg = <0x28000000 0x480000>;
	interrupts = <GIC_SPI 329 IRQ_TYPE_LEVEL_HIGH>,
		     <GIC_SPI 330 IRQ_TYPE_LEVEL_HIGH>,
		     <GIC_SPI 328 IRQ_TYPE_LEVEL_HIGH>;
	interrupt-names = "job", "mmu", "gpu";
	clocks = <&gpu_clk_stub>;
	clock-names = "core";
	operating-points-v2 = <&gpu_opp_table>;
	#cooling-cells = <2>;
	dynamic-power-coefficient = <625>;	/* gpu_power_coeff, gs201-gpu.dtsi:142 (units unverified) */
	status = "okay";
};
```

The OPP rate must equal the fixed clock's rate. `dev_pm_opp_set_opp()` then
asks for a rate the fixed clock already has, so nothing is touched. The
stub's value has no effect on the hardware. Do **not** use `dma-coherent`,
because Google's DT does not claim coherency.

Final form (phase 3):

- `clocks = <&acpm_ipc GS201_CLK_ACPM_DVFS_G3DL2>, <&acpm_ipc GS201_CLK_ACPM_DVFS_G3D>`
  with names `"core", "stacks"`.
- An OPP table from section 1.2.
- `power-domains = <&pd_embedded_g3d>` (child of `pd_g3d`).

Panthor's devfreq sets only `core`. The two-clock pairing (L2 ↔ shaders)
therefore needs either a PD with `set_performance_state` that sets both ACPM
domains from one OPP (the MT8196 pattern), or an OPP table with per-clock
`opp-hz` arrays. The PD approach is simpler.

---

## 4. Mesa side

**Arch's Mesa 26.2.4 does not support G710.**

- `pan_model_list` in `M/src/panfrost/model/pan_model.c` (26.2) has Valhall
  entries only for G57 (9.0.1/9.0.3), **G610 = `PAN_PROD_ID(10, 8, 7)`**
  (lines 88-89), G310 v1-v5 (10.12.4), then G720/G725/G1.
- Mesa `main` adds G68 (9.2.4), G715 (11.8.2) and G615 (11.8.3), but **not
  G710**.
- On the phone, `strings libgallium-26.2.4-arch1.1.so | grep Mali-G` lists
  G610 and no G710.
- No Mesa MR or issue mentioning G710 / gs201 was found (gitlab API search,
  2026-10-11).

Impact when the model is unknown:

- Gallium bails out early: `if (!dev->model) goto err_free_kmod_dev;`
  (`M/src/gallium/drivers/panfrost/pan_device.c:43-48`).
- PanVK fails with `VK_ERROR_INCOMPATIBLE_DRIVER`, "Unknown gpu_id"
  (`M/src/panfrost/vulkan/panvk_physical_device.c:394-399`).
- Once the model is known, arch 10 is PanVK's conformant path. There is no
  `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER` gate (`:402-414,458-459`).

Lookup key:

- `PAN_PROD_ID(arch_major, arch_minor, prod_major)`
  (`M/src/panfrost/model/pan_model.h:39-40`) → G710 = `PAN_PROD_ID(10, 8, 2)`.
- `gpu_variant = core_features & 0xff` (`M/src/panfrost/lib/kmod/panthor_kmod.c:173`).
  Panthor fills `core_features` from `GPU_CORE_FEATURES` (`0x8`)
  (`L/drivers/gpu/drm/panthor/panthor_hw.c:202`).
- Expect 0 on 10.8 (G610 uses variant 0). **Verify** with the first Panthor
  probe, e.g. a `DEV_QUERY` dump or Mesa's error message, which prints both
  id and variant.

Entry to add (the G710 shader core is the G610's big sibling: same Valhall
core, tile buffer and per-core rates):

```c
   VALHALL_MODEL(PAN_PROD_ID(10, 8, 2), 0, "G710",   "G710", MODEL_ANISO(ALL),  MODEL_TB_SIZES(32768, 16384),
                                              MODEL_RATES_X(4, 8, 16,  64,  64, 16)),
```

Place it next to the G610 line. If the variant turns out non-zero, use the
observed value.

**No other Mesa change is needed for display.** `simpledrm` (card0) is not a
known driver name, so the pipe loader falls back to `kmsro`
(`M/src/gallium/auxiliary/pipe-loader/pipe_loader_drm.c:181-183`). `kmsro`
opens a render node and accepts `panthor`
(`M/src/gallium/winsys/kmsro/drm/kmsro_drm_winsys.c:110-114`). Scanout
buffers become simpledrm dumb buffers that Panthor imports.

That fallback is exactly why we get `kms_swrast` today: there is no render
node, so kmsro fails. Expect the GPU to be picked up automatically once
`/dev/dri/renderD128` exists and the model is known.

How to ship:

1. **Now:** a patched `mesa` in the Omamobile repo. Take Arch's
   `mesa 1:26.2.4` PKGBUILD, add `0001-panfrost-add-Mali-G710.patch`, bump
   `pkgrel` to `…-1.1omamobile`, and build in the aarch64 docker
   (`docker/Dockerfile`). Ship `vulkan-panfrost` from the same build; it is
   not installed today. Pin the package with `IgnorePkg` or a higher epoch in
   our repo so `pacman -Syu` does not replace it.
2. **In parallel:** send an upstream MR with the one-line model entry. Include
   the Panthor `dmesg`, `glmark2`, `vkcube` results and dEQP-GLES3/VK smoke
   results. It will likely land in 26.3/27.0, then we drop the patch.

---

## 5. Bring-up sequence with gates

Rules for every step:

- The panthor module is **blacklisted from autoload**
  (`/etc/modprobe.d/omamobile-panthor.conf: blacklist panthor`) and only loaded by
  hand over SSH, so a failure costs at most one reboot.
- `panic=10` and ABL A/B fallback are the recovery path
  (`device/cheetah/NOTES.md`).

### Gate G0: offline prep (no risk)

- Write the DT node (3.4) with `status = "okay"` and the binding enum. Run
  `make dtbs_check` for `gs201-cheetah.dtb`.
- Add the blacklist file to the rootfs overlay.
- Build patched Mesa (section 4). Install it: `kms_swrast` is still used
  because there is no render node, so nothing changes visibly.
- Check that `modinfo panthor` lists `arm/mali/arch10.8/mali_csffw.bin` and
  that the file exists (done: present).
- **Pass:** the kernel boots with the new DTB, `/sys/bus/platform/devices/28000000.gpu`
  exists, panthor is not bound, and display/USB/UFS are unchanged.

### Gate G1: Panthor probes (medium risk: reboot)

- `modprobe panthor` over SSH while watching `dmesg -w` on a second SSH
  session.
- **Expected:** `Mali-G710 id 0xa862 major 0x0 minor 0x0 status 0x4`,
  `shader_present` (MC7 mask), "clock rate = 151000000", a CSF firmware
  interface version, and `/dev/dri/renderD128` + `card1`.
- **Failure modes:**
  - SError/reboot on the first register read: G3D is not powered or clocked
    → go to G1b.
  - `Failed to load firmware`: path issue.
  - FW boot timeout ("Failed to boot MCU"): firmware incompatible, or
    `stacks`/`coregroup` gated.
- **G1b (only if G1 crashes):** write a debug module that SMC-reads PMU
  `0x18061e04`/`0x18062004` (2.3a).
  - If the domains are off, implement the PD driver first (G4) and add
    `power-domains`.
  - If they are on, suspect CMU_G3D gates. Add the CMU_G3D driver to see gate
    state via `clk_summary`; it reads CMU_G3D only while the PD is known on.

### Gate G2: GPU smoke tests (low risk)

Stop Hyprland first (`systemctl --user stop` / leave the TTY).

- `eglinfo -B` should show `Mali-G710 (Panfrost)` on the GBM/surfaceless
  platform.
- `kmscube -D /dev/dri/card0` (simpledrm KMS + kmsro), and
  `glmark2-es2-drm` (or `glmark2-es2-wayland` later).
- `vulkaninfo --summary`, `vkcube --wsi display` (or headless
  `vkmark`/dEQP-VK subset).
- Watch `dmesg` for `panthor` MMU faults or FW timeouts.
- **Worst case:** a GPU hang. Panthor resets the GPU and kills the context.
  A reboot is unlikely.

### Gate G3: Hyprland on the GPU (low risk)

- Restart Hyprland unchanged. Aquamarine opens card0 (simpledrm) → GBM →
  kmsro/Panthor.
- Check `hyprctl systeminfo` / the Hyprland log for the GL renderer string
  (no longer `llvmpipe`/`kms_swrast`).
- If aquamarine picks the wrong card, set
  `AQ_DRM_DEVICES=/dev/dri/card0` (Panthor's `card1` has no KMS).
- **Expected gain:** composition, blur and animations move to the GPU.
  simpledrm still CPU-copies each damaged frame into `0xfac00000`. Real
  zero-copy scanout needs a DECON/DPU KMS driver, which is out of scope.

### Gate G4: power management (medium-high risk)

- **G4a:** gs201 ACPM bring-up (mailbox + SRAM + `google,gs201-acpm-ipc` +
  `clk-acpm` gs201 variant). First read only: `clk_get_rate()` of
  `g3d`/`g3dl2` reports the ABL rate. Then put that rate in the stub OPP.
- **G4b:** GPU DVFS through ACPM `set_rate`: real OPP table from 1.2 and a PD
  `set_performance_state` that sets both domains.
  - Raise frequency only after G4a shows ACPM answers DVFS calls.
  - Thermal: wire `#cooling-cells` to the G3D TMU zone (`gs-tmu 100b0000.G3D`
    in stock, `R/dmesg.txt:1082`) once a TMU driver exists. Until then, cap
    at a mid OPP (e.g. 572/750 MHz).
- **G4c:** a G3D genpd with the full SMC + DTZPC + CMU restore sequence.
  Allow runtime power-off only after on/off cycles pass a stress loop.
  Also confirm that `s2mpu_g3d` (always-on) does not need re-programming.

---

## 6. Effort and risks

| Step | Work | Estimate | Risk |
|---|---|---|---|
| G0 DT + binding + blacklist | DT node, yaml enum, overlay file | 0.5 day | none |
| G0 Mesa package | PKGBUILD + 1-line patch, aarch64 build, repo publish | 0.5–1 day (build time dominates) | none |
| G1 Panthor probe | load, read logs | 0.5 day if ABL state holds | medium (reboot) |
| G1b PMU SMC-read debug module (only if needed) | ~50 lines | 0.5 day | low–medium |
| G2 smoke tests | install tools (`kmscube`, `glmark2`, `vulkan-tools`, `mesa-utils`) | 0.5 day | low |
| G3 Hyprland | config/env tweaks | 0.5 day | low |
| Upstream Mesa MR | patch + test evidence | 0.5 day + review latency | none |
| G4a ACPM on gs201 | mailbox, SRAM, compatibles, CMU_APM pclk (or stub) | 2–4 days | medium (ACPM IPC wrong → APM confusion; read-only first) |
| G4b DVFS + thermal | PD perf-state or OPP multi-clock, tables, cooling | 3–5 days | medium-high (overclock/undervolt if mis-paired) |
| G4c G3D genpd + CMU_G3D driver | SMC PD driver, DTZPC, CMU save/restore, CMU_G3D gates | 4–7 days | high (SErrors on power-cycle) |

The **MVP (G0–G3)** takes about **2–4 days** if the ABL handoff holds. Full
power management takes another 2–3 weeks.

### Top risks

1. **GPU not usable at handoff.** If ABL leaves G3D off or clock-gated, the
   first Panthor register read SErrors (we already saw a PMU G3D read crash
   from `/dev/mem`). Mitigations:
   - manual `modprobe` only;
   - the G1b SMC read;
   - fall back to building the PD driver (G4c) first.
2. **Firmware/hardware mismatch.** The generic arch10.8 CSF firmware has not
   been proven on G710 r0p0 in upstream CI. Third-party reports say it works.
   Fallback: try the `arch10.10` vs `arch10.8` builds from older
   linux-firmware tags.
3. **Mesa model details.** `gpu_variant` may not be 0, or G710 r0p0 errata may
   need quirks. Tile-buffer sizes are inferred from G610. Validate with dEQP
   before upstreaming.
4. **Power-cycling G3D** without the DTZPC restore SMC and CMU restore leaves
   the block secure-only/unclocked → SError. Never enable runtime PD power-off
   until G4c is complete. Panthor's own runtime suspend (L2/shader power-down
   via GPU registers) is fine.
5. **DVFS safety.** Voltages live in ECT/ACPM, not DT. Never change PLL rates
   directly through CMU_G3D. Use only ACPM `set_rate`, which applies the
   matching voltage.
6. **Display path stays CPU-bound.** simpledrm copies frames with the CPU, so
   the gain is limited to rendering. Damage tracking in Hyprland helps. Full
   benefit needs a DECON KMS driver (separate project).
7. **SLC/MGM, protected memory and the priority manager** (`gs201-gpu.dtsi:10-48`)
   are kbase-only Pixel features. Panthor ignores them, which costs some
   performance but is not a correctness problem.

---

## G0 status (2026-10-11, offline; nothing was run on the phone)

> **Historical.** Superseded by the G2 result below, `ACPM-PLAN.md` and the
> status at the top.

### Kernel: `omamobile-gpu` in `wt-gpu`, rebased onto `omamobile` @ `1f151cd80` (touch included)

- `b7b9b8bf3` dt-bindings: gpu: mali-valhall-csf: add the `google,gs201-mali` compatible.
  No SoC-specific constraints. `dt-doc-validate` passes.
- `121b584c2` gs201.dtsi: `gpu@28000000` (disabled), with `reg`, the
  `job/mmu/gpu` IRQs 329/330/328, and a `core` clock from the `clock-gpu`
  fixed clock. One-entry `opp-table-gpu`. No `power-domains`, no
  `mali-supply` (the reasons are in a comment and the commit message).
- `1f1b44ac6` gs201-cheetah: `&gpu { status = "okay"; }`.
- `dt-validate` of `gs201-cheetah.dtb` against the tree's bindings reports
  nothing for the GPU nodes. The only finding is the existing `soc_id`
  property, which has no schema.
- `CONFIG_DRM_PANTHOR=m`. The module's `.modinfo` lists
  `arm/mali/arch10.8/mali_csffw.bin`. It depends on the modules `drm_exec`,
  `gpu-sched` and `drm_gpuvm`.

**Why 151 MHz.** The phone's own bl2 partition (backup
`cheetah-partition-backup-20261011/bl2_a.img` @ `0x60000`) holds the ECT
blob (`PARA` version 0042, the same version stock prints). Parsing it with
the layout from Google's `ect_parser.c` gives:

- DVFS domains `G3D` (848…151 MHz) and `G3DL2` (996…151 MHz). Both have
  `boot_level_idx = -1`, so the boot rate comes from the GEN table instead.
- GEN `MINMAX_G3D` / `MINMAX_G3DL2`: boot = resume = **151 MHz** for every
  ASV group (columns `asv_fusing, asv_table, min, max, boot, resume`;
  `vclk.c` reads `MINMAX_BOOT_FREQ`).

The factory bootloader `cp2a.260705.006` contains the same table.

This is the rate the firmware declares as the boot level. Whether ABL
actually leaves G3D at that rate will be confirmed in G4a, when the ACPM
`get_rate` call is implemented. A 151 MHz fixed clock is safe either way:
the OPP equals the clock, so devfreq never calls a real `set_rate`. The
only side effect is that Panthor's `fast_rate` and devfreq statistics
assume 151 MHz.

The parser script is not in the repo. It is about 50 lines of Python
following `ect_parser.c`; rewrite it if it's needed again.

### Userspace and tooling (omamobile repo)

- `device/cheetah/rootfs/etc/modprobe.d/omamobile-panthor.conf`: `blacklist panthor`.
  This stops udev's modalias autoload. An explicit `modprobe panthor` still
  works.
- `bin/omamobile modules`: runs `modules_install` with `INSTALL_MOD_STRIP=1`
  and packs the result as `$KERNEL_OUT/modules-<release>.tar.zst` (paths
  `<release>/…`, 1680 modules, 16 MB). The container has no depmod, so
  `depmod` runs on the phone.
- `bin/omamobile modules-push`: streams that tarball into
  `/usr/lib/modules/<release>` over SSH, swapping the tree atomically, then
  runs `depmod -a <release>`. Written but **not run yet**.
- Fixed `omamobile images`: `grep -q` under `pipefail` SIGPIPEd dtc once
  the DTB grew, and that produced a false "soc_id rewrite failed".
- `packages/mesa/`: the G710 patch, a trimmed aarch64 PKGBUILD from Arch
  `1-26.2.4-1`, plus `README.md` and `UPSTREAM.md`. Verified so far:
  - the tarball's checksums and signature;
  - `makepkg --nobuild` (the patch applies), and `patch --dry-run` passes as well;
  - the patch also applies to Mesa `main` with fuzz 2.

  It has **not been built**; the build happens natively on the phone.

Images for G1 are built in `~/android/mainline/out-gpu/images`. Kernel
release: `7.3.0-rc6-omamobile-push1-00032-g1f1b44ac61b9`.

### G1 runbook (run from the omamobile repo, phone in Arch over USB)

```sh
export KERNEL_OUT=$HOME/android/mainline/out-gpu
# 1. blacklist first, so the new DTB cannot autoload panthor
tools/phone-ssh 'mkdir -p /etc/modprobe.d && cat > /etc/modprobe.d/omamobile-panthor.conf' \
  < device/cheetah/rootfs/etc/modprobe.d/omamobile-panthor.conf
# 2. modules for the new kernel (installed alongside the running one)
bin/omamobile modules-push
# 3. write slot B and reboot into it
bin/omamobile push
# 4. G0 pass check
tools/phone-ssh 'uname -r; ls -d /sys/bus/platform/devices/28000000.gpu; \
  lsmod | grep -c panthor; ls -l /usr/lib/firmware/arm/mali/arch10.8/'
# 5. G1: watch the log in one terminal, load the driver in another
tools/phone-ssh dmesg -w
tools/phone-ssh modprobe panthor
tools/phone-ssh 'ls -l /dev/dri; cat /sys/class/devfreq/*/cur_freq'
```

For the upstream Mesa MR, record the `core_features` low byte (the Mesa
`gpu_variant`). If Mesa reports "Unknown gpu_id … variant N" with
`N != 0`, change the patch to use that `N`.

### Open questions

- **Whether G3D is really on and clocked at handoff.** Unverified; G1 tests it.
- **Whether the generic arch10.8 CSF firmware boots on G710 r0p0.** Unverified.
- **Whether the "stacks"/"coregroup" CMU_G3D gates could be off** while
  the "core" gate is on. The Q-channel should keep them running. If the MCU
  times out, this is the first suspect.

## G2 result (2026-10-11)

- Patched Mesa 26.2.4 (`packages/mesa`, G710 model entry) built natively on the
  phone and installed: `mesa`, `vulkan-panfrost`, `vulkan-mesa-implicit-layers`.
- `eglinfo`: OpenGL ES 3.1 / OpenGL 3.1, renderer "Mali-G710 MC7 (Panfrost)".
  `vulkaninfo`: "Mali-G710 MC7", driver panvk, Vulkan 1.4.354. `vkcube` runs in
  the Hyprland session.
- Hyprland/aquamarine: "Renderer: Mali-G710 MC7 (Panfrost)". No Mesa change was
  needed for the display side: simpledrm has no Gallium driver of its own, so
  Mesa's pipe-loader falls back to kmsro (`pipe_loader_drm.c`, "kmsro supports
  lots of drivers, try as a fallback"), which renders on the panthor render node
  and scans out on simpledrm.
- The panthor blacklist is gone: udev autoloads the module at boot, before SDDM
  starts Hyprland. The GPU stays powered through
  `20-omamobile-gpu-always-on.rules` (G3D cannot be powered back up yet).
- Still open: `_opp_set_regulators: no regulator (mali)` at probe (harmless,
  fixed OPP at 151 MHz); DVFS and a real power-domain driver; upstream the G710
  Mesa entry.
