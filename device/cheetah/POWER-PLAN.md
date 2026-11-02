<!-- SPDX-License-Identifier: MIT -->
# Power plan before suspend: CPU idle C2 and UFS Hibern8 (cheetah / gs201)

Status (2026-10-12): **C2 idle on all cores is on by default.** P0, C1 (the
MCT) and C2 passed on the phone (section 7), and `omamobile-power-on` @
`241736cc0` (the MCT and C2 enabled in the default DTB) is merged into
`omamobile-int`, with `omamobile-power` @ `20bd72c37` (`wt-power`,
`out-power`). Little-cores-only C2 can't work (1.5), and the UFS controller
has no auto-hibernate, so U1 is skipped. **Next (the cable out):** the B0
baseline, `power-ab c2` and U2; the 30-minute C2 soak's result is not
recorded in section 7. Cluster power-down (1.6) is not built; suspend is
`SUSPEND-PLAN.md`.

Earlier status (historical, superseded by the status above): P0, C1 and C2 pass on the phone (section 7); the C2
soak and the battery measurements (B0, `power-ab c2`) are pending. Kernel
branch `omamobile-power` in `wt-power`, built into
`~/android/mainline/out-power`: the C2 states and the MCT are
`status = "disabled"` in the DT and turned on by test overlays; the UFS change
only removes a mode that Google never uses on this SoC. Branch
`omamobile-power-on` (`241736cc0`, one commit on top) enables the MCT and C2 by
default; not merged, waiting for the soak.

Goal: cheap power savings while the phone is awake, before real suspend
exists: (1) core power-down (C2) when a CPU is idle, (2) the UFS link in
Hibern8 when storage is idle, (3) a repeatable way to measure both on battery.

Path abbreviations:

- `L/` = `/home/raven/android/mainline/wt-power` (our kernel, this branch)
- `GS/` = `/home/raven/android/omamobile/out-kernel/google/gs-6.1/private/google-modules/soc/gs`
- `GD/` = `/home/raven/android/omamobile/out-kernel/google/gs-6.1/private/devices/google/gs201/dts`
- `R/` = `/home/raven/android/reference/cheetah-stock-cp2a-root` (stock live DT, logs)

Line numbers in `L/` are for the branch head (`20bd72c37`).

---

## 1. CPU idle

### 1.1 What we expose today: nothing but WFI

Before this branch our `gs201.dtsi` had no `idle-states` node and no
`cpu-idle-states` on any CPU. `cpuidle-psci` then refuses to register
(`L/drivers/cpuidle/cpuidle-psci.c`, "no reason to initialize the idle driver
if only wfi is supported"), so every idle CPU sits in architectural WFI with
its core powered. There is no `/sys/devices/system/cpu/cpu0/cpuidle/` on the
phone today.

The config side is ready: `CONFIG_CPU_IDLE=y`, `CONFIG_ARM_PSCI_CPUIDLE=y`,
menu governor, `CONFIG_CLKSRC_EXYNOS_MCT=y` (arm64 defconfig, checked in
`out-power/.config`).

### 1.2 What stock exposes

One PSCI state per core type, all named `c2`, `arm,psci-suspend-param =
<0x10000>` (power-down, state id 0) (`R/live.dts:2555-2600`):

| Cores | Stock name | entry / exit / min residency (us) |
|---|---|---|
| cpu0-3 Cortex-A55 | `ANANKE_CPU_SLEEP` | 70 / 160 / 2000 |
| cpu4-5 Cortex-A78 | `HERCULES_CPU_SLEEP` | 150 / 190 / 2500 |
| cpu6-7 Cortex-X1 | `HERA_CPU_SLEEP` | 235 / 220 / 3500 |

On top of that, a vendor `cpupm` node (`R/live.dts:2603-2650`) describes
cluster power-down (`cpd_cl0/1/2`, target residency 10 ms; cluster 0 has no
`entry-allowed`, so only clusters 1 and 2 may do it) and system idle
(`sicd`, all 8 CPUs). These are not PSCI states: they are chosen by Google's
driver and signalled through the same PMU hint register (1.3).

Stock has no `local-timer-stop` because its per-CPU tick is the MCT, not the
arch timer: `R/interrupts.txt:49-51` shows `exynos-mct` interrupts counting on
one CPU each, and the MCT node is `R/live.dts:12763-12784` (SPI 785-796).

### 1.3 What Google's cpupm driver writes

Path: CPU PM notifier `exynos_cpu_pm_notify_callback()`
(`GS/drivers/soc/google/exynos-cpupm.c:979`) -> `exynos_cpupm_enter()`
(`:921`) -> `cal_cpu_disable(cpu)` -> `pmucal_cpu_disable()`
(`GS/drivers/soc/google/cal-if/pmucal_cpu.c:54`). Exit is the mirror
(`cal_cpu_enable` -> `pmucal_cpu_enable`, `pmucal_cpu.c:16`). Hotplug uses the
same two calls (`exynos-cpupm.c:1146-1195`).

On entry, for the CPU going idle:

1. **CPU_INFORM hint, secure write.** `pmucal_powermode_hint(cpu_inform_c2)`
   (`pmucal_cpu.c:70`) -> `set_priv_reg(PMU + 0x860 + 4*cpu, 1)`
   (`GS/drivers/soc/google/cal-if/pmucal_powermode.c:15-20`). `set_priv_reg` is
   SMC `0x82000504` (`GS/include/linux/soc/samsung/exynos-smc.h:45`,
   `GS/drivers/soc/google/exynos-pd_el3.c:40`). Addresses:
   `GS/drivers/soc/google/cal-if/gs201/flexpmu_cal_cpu_gs201.h:6-16`; values
   C2 = 1, CPD = 2, SICD = 3 (`.../gs201/flexpmu_cal_define_gs201.h:6-14`,
   `.../gs201/cal_data.c:51-52`).
2. **PMU interrupt generator, plain MMIO at `0x18070000`**
   (`flexpmu_cal_cpu_gs201.h`, `core00_off` and following): set bit `cpu` in
   `GRP2_INTR_BID_ENABLE` (+0x200), then clear pending bits `cpu` and `cpu+8`
   in `GRP1_INTR_BID_CLEAR` (+0x10c) if `GRP1_INTR_BID_UPEND` (+0x108) shows
   them.

On exit: CPU_INFORM = 0 (`pmucal_powermode_hint_clear()`), clear bit `cpu` in
`GRP2_INTR_BID_ENABLE`, clear its pending bit in `GRP2_INTR_BID_CLEAR`
(+0x20c) via `GRP2_INTR_BID_UPEND` (+0x208).

The last CPU of cluster 1 or 2 may write CPD (2) instead
(`pmucal_cpu_cluster_disable()`, `pmucal_cpu.c:171-181`), when every sibling
is idle with a long enough expected sleep (`entry_allow()`,
`exynos-cpupm.c:812`). The cluster sequences themselves are empty on gs201
(`flexpmu_cal_cpu_gs201.h:139-167`): only the hint differs. SICD
(`enter_power_mode()`, `exynos-cpupm.c:853`) needs idle-IP tracking, ACPM and
wake-up masks; out of scope here. The `PMU_INFORM0 = 1` write at the end of
probe is Zuma-only (`exynos-cpupm.c:1516-1520`).

### 1.4 Mainline already does the per-CPU hint for gs201

`L/drivers/soc/samsung/exynos-pmu.c` has exactly this sequence for gs101, and
our gs201 compatible reuses `gs101_pmu_data` (`exynos-pmu.c:127`), whose
`pmu_cpuhp = true` (`L/drivers/soc/samsung/gs101-pmu.c:325-330`):

- `__gs101_cpu_pmu_offline()` (`exynos-pmu.c:299`): CPU_INFORM(cpu) =
  `CPU_INFORM_C2` (1) through the SMC regmap (`tensor_sec_reg_write()`,
  `gs101-pmu.c:343`, same SMC id 0x82000504), then GRP2 enable and the two
  GRP1 clears on pmu-intr-gen: the same registers and order as Google's
  `coreNN_off`.
- `__gs101_cpu_pmu_online()` (`exynos-pmu.c:238`): CPU_INFORM = 0, GRP2
  disable and clear: Google's `coreNN_on`.
- Called from a CPU PM notifier at `INT_MAX` priority
  (`exynos-pmu.c:368-386`) and from CPU hotplug, skipped during reboot and
  suspend, refused (NOTIFY_BAD) for a CPU in hotplug, all under a raw spinlock.
- CPU_INFORM (0x860-0x87c) is inside the writable range `GS101_INFORM4 ..
  GS101_IROM_INFORM` (`gs101-pmu.c:33`), and the CPU_INFORM / GRP offsets are
  the same on gs201 (`L/include/linux/soc/samsung/exynos-regs-pmu.h:707,
  1012-1016` vs `flexpmu_cal_cpu_gs201.h`).
- Our `gs201.dtsi` already has `pmu_intr_gen` at `0x18070000` and the
  `google,pmu-intr-gen-syscon` phandle (`L/.../gs201.dtsi`, the PMU node), so
  `setup_cpuhp_and_cpuidle()` (`exynos-pmu.c:413`) ran on every boot so far:
  the probe-time "online" writes for all CPUs (SMC + intr-gen MMIO) and all
  hotplug paths have been exercised without trouble. Only the CPU PM
  notifier has never fired, because nothing enters a PSCI idle state.

**So no new driver is needed for C2.** A "gs201 cpuidle/PMU hint driver" would
duplicate `exynos-pmu.c`. What was missing is the DT description (states +
broadcast timer). One upstream nit, harmless: the probe loop calls
`gs101_cpuhp_pmu_online(cpu)` for every CPU from the boot CPU, and
`__gs101_cpu_pmu_online()` uses `smp_processor_id()` for the hint index, so it
clears CPU_INFORM(0) eight times; each CPU clears its own on its first idle
exit anyway.

### 1.5 Design (built, disabled)

| Commit | What |
|---|---|
| `f417af56e` dt-bindings: timer: exynos4210-mct: add Google gs201 compatible | `google,gs201-mct` with the gs101 rules (12 interrupts) |
| `8aafd27af` arm64: dts: exynos: google: gs201: add the MCT | `timer@10050000`, SPI 785-796, `oscclk` + `CLK_GOUT_MISC_MCT_PCLK` (CMU_MISC is registered early, `L/drivers/clk/samsung/clk-gs201.c`, "Register CMU_MISC early"); **disabled** (`L/.../gs201.dtsi:520`) |
| `048d17940` arm64: dts: exynos: google: gs201: add the C2 CPU idle states | `idle-states` with the stock values + `local-timer-stop`, `cpu-idle-states` on all CPUs; the three states **disabled** (`L/.../gs201.dtsi:51-99,118-153`) |

Why the MCT: in C2 the core, and with it its generic timer, is powered
down, so the states carry `local-timer-stop` (as upstream gs101 does). On
arm64 the MCT's per-CPU timers rate 350, below the arch timer
(`L/drivers/clocksource/exynos_mct.c:56-60`), so the tick stays on the arch
timer; the MCT's global comparator `mct-comp` (rating 250, `:325`) becomes the
tick broadcast device. Without it the kernel falls back to the hrtimer
broadcast, which keeps one CPU out of C2 at all times.

Why "disabled" works as an off switch: `dt_init_idle_driver()` skips
unavailable state nodes (`L/drivers/cpuidle/dt_idle_states.c:177`), and with
the one state of a CPU skipped, `psci_idle_init_cpu()` registers nothing
(WFI only, today's behaviour). `timer_probe()` likewise skips a disabled MCT.

Test overlays, applied with `fdtoverlay` exactly like the Wi-Fi ones:

- `device/cheetah/overlays/power-mct-test.dtso`: MCT on (gate C1)
- `device/cheetah/overlays/power-c2-all-test.dtso`: C2 on all 8 CPUs (C2)

**C2 can only be enabled on all CPUs at once.** `psci_cpuidle_probe()` walks
every present CPU; `psci_idle_init_cpu()` returns -ENODEV for a CPU without
idle states (`L/drivers/cpuidle/cpuidle-psci.c:401`), and the probe then
unwinds every CPU (`:437-440`), so no driver registers at all. A
little-cores-only overlay therefore gives WFI everywhere (seen on the phone).
To narrow C2 down, boot with all states and disable `state1` at runtime on
the CPUs to exclude.

Once the overlays are on, C2 can be switched off **at runtime** per CPU
(`/sys/devices/system/cpu/cpuN/cpuidle/state1/disable`), which is also what
the A/B measurement uses. The firmware's verdict is visible per CPU in
`state1/rejected` (PSCI CPU_SUSPEND denied, or the PMU notifier refused) next
to `state1/usage` and `state1/time`.

### 1.6 Later: cluster power-down (CPD), not built

Stock lets the last idle CPU of cluster 1 (A78) or 2 (X1) write CPD (2)
instead of C2 when all siblings are idle and their next timer is at least
10 ms away. A mainline-acceptable shape, inside `exynos-pmu.c` so it shares
the lock and the hint path:

- per-cluster mask of CPUs that have done CPU_PM_ENTER (set in
  `gs101_cpu_pmu_offline()`, cleared in `gs101_cpu_pmu_online()`);
- if this CPU completes the mask of an allowed cluster and
  `tick_nohz_get_next_hrtimer()` of the siblings is past the residency, write
  `CPU_INFORM_CPD` instead of `CPU_INFORM_C2`;
- the allowed clusters and the residency from DT (a gs201 property on the
  PMU node, or PSCI cluster states if the firmware supports OSI, which it
  does not advertise: stock uses platform-coordinated mode);
- off unless the DT says so.

Do it only after C2 is measured, and only if a cluster-level measurement
shows a gain: the A78/X1 clusters are mostly idle with the screen on, but the
cost of a mispredicted cluster power-down is the cluster's cache.

---

## 2. UFS Hibern8

### 2.1 What our driver does today (it already hibernates the link)

`gs201_ufs_drvs` (`L/drivers/ufs/host/ufs-exynos.c:2319`) uses
`gs101_ufs_drv_init()` (`:228-244`), which sets `UFSHCD_CAP_CLK_GATING |
UFSHCD_CAP_HIBERN8_WITH_CLK_GATING`. So, as soon as the UFS host has had no
request for `clkgate_delay_ms` (150 ms, `L/drivers/ufs/core/ufshcd.c:2238`),
`ufshcd_gate_work()` sends DME_HIBERNATE_ENTER and gates the clocks
(`ufshcd.c:2071-2084`); the next request exits Hibern8 first
(`ufshcd.c:1948`). The vendor hooks then run the PHY sequences
(`exynos_ufs_post_hibern8()` / `exynos_ufs_pre_hibern8()`,
`ufs-exynos.c:1646-1698`, -> `tensor_gs101_post_h8_enter` /
`tensor_gs101_pre_h8_exit`, `L/drivers/phy/samsung/phy-gs101-ufs.c:186-206`,
used for gs201 too). Those tables are register for register Google's gs201
`post_h8_enter` / `pre_h8_exit` (`GS/drivers/ufs/gs201/ufs-cal-if.c:448-477`;
PMA offsets there are 4x the mainline register numbers: 0x988 = 0x262,
0x994 = 0x265, 0x888 = 0x222, 0x918 = 0x246; COMN 0x00/0x04/0x20 = 0x0/0x1/0x8).

**Auto-Hibern8 (the controller's own idle timer) is the open question.** If
the controller sets the AH8 capability bit, `ufshcd_init()` programs a 150 ms
auto-hibernate timer (`ufshcd.c:11323-11327`), because nothing in our gs201
data marks it broken. The core's clock-gating work then sends
DME_HIBERNATE_ENTER for a link the controller may already have parked. Other
vendor drivers treat the two as exclusive.

### 2.2 What Google does on gs201

- **Software Hibern8 on clock gating, never auto-hibernate.**
  `exynos_ufs_set_features()` (`GS/drivers/ufs/ufs-exynos.c:567-591`) sets
  `UFSHCD_QUIRK_BROKEN_AUTO_HIBERN8` unconditionally (`:583`) and
  `HIBERN8_WITH_CLK_GATING` whenever AH8 is not configured. AH8 is only
  configured with a `samsung,support-ah8` DT property (`:1324-1337`), which is
  neither in `GD/gs201-ufs.dtsi` nor in the stock tree (`R/live.dts:9778-9830`).
  Google's gs201 CAL has no AH8 timer setup; only Zuma's programs one
  (`GS/drivers/ufs/zuma/ufs-cal-if.c:333-339`).
- **Hibern8 after 4 ms idle, not 150 ms.** `params[UFS_SYSFS_H8_D_MS] = 4`
  (`GS/drivers/ufs/ufs-exynos.c:1631`), applied to `clk_gating.delay_ms` after
  every Hibern8 exit (`:1010-1016`); tunable through the vendor `h8_delay_ms`
  sysfs file.
- System suspend level 5 (`exynos_ufs_override_hba_params()`, `:702-705`):
  suspend-only, not relevant before suspend exists.

### 2.3 Design

1. **Measure first** (gate U0): whether AH8 is active on our kernel
   (`auto_hibern8` sysfs), and how much the existing software Hibern8 saves
   (`clkgate_enable` 0 vs 1).
2. **Commit `20bd72c37` scsi: ufs: exynos: don't enable auto-hibernate on
   gs201**: adds `UFSHCD_QUIRK_BROKEN_AUTO_HIBERN8` to `gs201_ufs_drvs`
   (`ufs-exynos.c:2322`), matching Google. If U0 shows AH8 unsupported, this is
   a no-op. If U0 shows it active, `echo 0 > auto_hibern8` reproduces the
   commit's behaviour at runtime first (gate U1), so the kernel change is
   proven before it ships.
3. **The Hibern8 delay is the knob.** It is already runtime-configurable
   through the core's `clkgate_delay_ms`. Step it down 150 -> 20 -> 4 ms
   (stock) with A/B measurements (gate U2), and only then persist it with a
   udev rule in `omamobile-device-cheetah` (gate U3), e.g.
   `ACTION=="add", SUBSYSTEM=="platform", KERNEL=="14700000.ufs", ATTR{clkgate_delay_ms}="4"`.
   Rollback = delete the rule, or write 150 back.

No new kernel code for the delay: an upstream driver would set a default
through the core, and 150 ms is a safe default until we have numbers.

Why this is conservative for the root filesystem: every step keeps the code
path stock Android uses on this phone (SW Hibern8 + clock gating + Google's
PHY tables), and every change before U3 is a runtime sysfs write that a
reboot undoes.

---

## 3. Builds and checks

- `bin/omamobile kernel`, `modules` and `images` with
  `KERNEL_DIR=wt-power KERNEL_OUT=out-power`: see "Build result" at the end.
- No new C: the only C change is one quirk flag.
- The default DTB has the MCT and the three states present but disabled. The
  overlays are compiled and applied in the runbook.

---

## 4. Measuring with the MAX77759 fuel gauge

The gauge driver (`max17042_battery`, autoloaded since B1) exposes
`/sys/class/power_supply/max170xx_battery/`:

- `current_now` (uA): the Current register, signed, 5 mOhm shunt
  (`shunt-resistor-micro-ohms = <5000>` in our cheetah DT, Google's
  `maxim,rsense-default = <500>`). **Negative while discharging.** It is a
  direct measurement and doesn't depend on the battery model (the model only
  affects capacity and SOC).
- `current_avg` (uA): AvgCurrent, the gauge's filtered value (seconds).
- `voltage_now` (uV): VCell, for power = V x I.

Rules for a meaningful number:

- **The cable must be out**: with USB in, the charger or VBUS supplies the
  system and the battery current says nothing. USB networking does not come
  back after an unplug until the next boot (NOTES, "USB doesn't reconnect"),
  so the measurement must run detached on the phone and write to the UFS
  root.
- **Same conditions in A and B**: screen in the same state (off, or the same
  brightness and the same static picture), no Wi-Fi/BT (none yet), no
  interactive use. Alternate A and B in rounds so battery voltage and
  temperature drift average out; discard the first seconds of each phase.
- **Know the noise**: run `baseline` (A = B) once. A difference smaller than
  the baseline difference is not a result.

`tools/power-ab` (new) does exactly this on the phone: `power-ab [--detach]
baseline|c2|ufs-gate|ufs-delay`, default 60 s to unplug, then 4 rounds of
A/B at 120 s each (20 s settle), 1 Hz samples into
`/var/lib/omamobile/power/<time>-<test>.csv` and a summary `.txt` with mean
current and power per phase and B - A. It restores every setting it touched
at the end (and on SIGTERM). Copy it over with
`tools/phone-ssh 'cat > /usr/local/bin/power-ab && chmod +x /usr/local/bin/power-ab' < tools/power-ab`.

Targets set for this work, to be verified, not promises: about 0.65 W for
C2 (8 cores in WFI vs powered down) and about 160 mA for UFS Hibern8 on idle.
B0 (`ufs-gate`) tells us how much of the UFS part we already have.

---

## 5. Staged runbook (on the phone, run by the main session)

Rules for every gate: one change at a time; slot B only; keep the previous
images (`out-*/images`) to flash back. A boot that hangs falls back to stock
slot A after ABL's retries (NOTES, "Slot B fallback works"); from there
`adb reboot bootloader` and flash the previous images. Read-only gates touch
nothing.

Shorthand: `O=~/android/mainline/out-power`,
`D=$O/arch/arm64/boot/dts/exynos/google/gs201-cheetah.dtb`.

### 5.1 P0: read-only state on the current kernel (any kernel, no flash)

```sh
tools/phone-ssh 'uname -r
ls /sys/devices/system/cpu/cpu0/cpuidle 2>&1 | head -3       # expect: No such file
cat /sys/devices/system/clockevents/broadcast/current_device  # expect: bc_hrtimer (or none)
dmesg | grep -iE "pmu-intr-gen|SMC failed|exynos-pmu"         # expect: nothing
U=$(ls -d /sys/bus/platform/devices/*.ufs); echo $U
cat $U/auto_hibern8 2>&1           # "Operation not supported" = no AH8; a number (us) = AH8 active
cat $U/clkgate_enable $U/clkgate_delay_ms   # expect 1 and 150
cat $U/power/runtime_status
grep -E "ufshcd|14700000" /proc/interrupts
grep . /sys/class/power_supply/max170xx_battery/{voltage_now,current_now,current_avg}'
```

Record the answers in NOTES. **`auto_hibern8` decides U1.** A line
"SMC failed" would mean the PMU hint writes are refused: stop, C2 must not
be enabled.

### 5.2 B0: baseline measurement (current kernel)

```sh
tools/phone-ssh 'cat > /usr/local/bin/power-ab && chmod +x /usr/local/bin/power-ab' < tools/power-ab
tools/phone-ssh 'power-ab --detach baseline'    # then unplug within 60 s
# wait ~17 min (4 rounds x 2 x 120 s + 60 s), replug; if USB stays down, reboot
tools/phone-ssh 'cat /var/lib/omamobile/power/*-baseline.txt'
tools/phone-ssh 'power-ab --detach ufs-gate'     # same routine: SW Hibern8 off vs on
```

`ufs-gate` gives the value of the Hibern8 we already have (B - A).

### 5.3 C1: MCT only (new kernel, flash)

```sh
cd ~/Projects/omarchy-mobile
cp "$D" "$D.default"
$O/scripts/dtc/dtc -q -I dts -O dtb -o out/power-mct-test.dtbo device/cheetah/overlays/power-mct-test.dtso
$O/scripts/dtc/fdtoverlay -i "$D.default" -o "$D" out/power-mct-test.dtbo
KERNEL_DIR=~/android/mainline/wt-power KERNEL_OUT=$O bin/omamobile images > logs/images-power-c1.log 2>&1
# flash slot B as usual (bin/omamobile flash), boot
tools/phone-ssh 'dmesg | grep -iE "mct|clocksource|clockevent"
cat /sys/devices/system/clockevents/broadcast/current_device   # expect: mct-comp
cat /sys/devices/system/clocksource/clocksource0/current_clocksource  # expect: arch_sys_counter
grep -E "mct" /proc/interrupts'
```

**Pass:** boots, `mct-comp` is the broadcast device, the clocksource is still
`arch_sys_counter`, `mct_comp_irq` registered. Leave it up 10 minutes
(`uptime`, `date` against the laptop: no drift). **Fail:** no boot -> slot A
fallback, flash the previous images; MCT error lines -> stop and report.

### 5.4 C2: all cores (one gate)

```sh
$O/scripts/dtc/dtc -q -I dts -O dtb -o out/power-c2-all-test.dtbo device/cheetah/overlays/power-c2-all-test.dtso
$O/scripts/dtc/fdtoverlay -i "$D.default" -o "$D" out/power-mct-test.dtbo out/power-c2-all-test.dtbo
KERNEL_DIR=~/android/mainline/wt-power KERNEL_OUT=$O bin/omamobile images > logs/images-power-c2.log 2>&1
# flash slot B, boot. Then arm the watchdog feeder (tools/wifi-w1-capture --watchdog
# pattern) so a later hang resets the phone instead of needing a 30 s Power hold:
tools/phone-ssh 'nohup sh -c "exec 3>/dev/watchdog0; trap \"printf V >&3; exit 0\" TERM
  while :; do printf k >&3; sleep 2; done" >/dev/null 2>&1 & echo $! > /run/power-wd.pid'
tools/phone-ssh 'for c in 0 1 2 3 4 5 6 7; do d=/sys/devices/system/cpu/cpu$c/cpuidle
  echo "cpu$c $(cat $d/state1/name 2>/dev/null) usage=$(cat $d/state1/usage 2>/dev/null) rejected=$(cat $d/state1/rejected 2>/dev/null) time=$(cat $d/state1/time 2>/dev/null)"; done
cat /sys/devices/system/cpu/cpuidle/current_driver
dmesg | grep -iE "psci|cpuidle|SMC failed"'
```

**Expect:** driver `psci_idle`, `state1` "c2" on cpu0-7 with `usage`
growing and `rejected` a small fraction of it; no "SMC failed". Check twice,
a minute apart. For a more cautious start, disable `state1` on cpu4-7 right
after boot and re-enable it after a few minutes (the same command with
`v=0`). It names each core's file, since a glob can't be a redirect target,
reads the value back and stops at the first core that doesn't take it (a
"stop" line, non-zero exit); the cores it printed before that keep the new
value. If either run stops, go no further: collect `dmesg` and report.

```sh
tools/phone-ssh 'v=1; for c in 4 5 6 7; do f=/sys/devices/system/cpu/cpu$c/cpuidle/state1/disable
  [ -e "$f" ] && echo $v > "$f" && [ "$(cat "$f")" = $v ] || { echo "cpu$c: state1/disable is not $v, stop" >&2; exit 1; }
  echo "cpu$c state1/disable=$v"; done'
```

Then a 30-minute soak with normal use and
one all-core load (`stress-ng --cpu 8 --timeout 60`, or 8 `yes > /dev/null`
for a minute), looking for RCU stalls, soft lockups or a frozen screen.

**Fail modes and actions:**

| Symptom | Meaning | Action |
|---|---|---|
| `rejected` grows like `usage` | firmware refuses C2 (hint not seen) | `echo 1 > .../state1/disable` on all CPUs, collect `dmesg`, stop |
| "SMC failed" flood | secure PMU writes refused | same |
| RCU stall / lockup messages | a CPU doesn't wake | disable at runtime if the shell answers; else watchdog reset; reflash previous images |
| no boot | hang before userspace | slot A fallback, reflash previous images |

To stop the feeder cleanly: `tools/phone-ssh 'kill $(cat /run/power-wd.pid)'`
(the trap writes the magic close, so the watchdog stops).

### 5.5 C2 measurement and default-on

```sh
tools/phone-ssh 'power-ab --detach c2'     # A = C2 off on all CPUs, B = on
```

Needs the phone on battery (cable out). **Pass:** B - A clearly above the
baseline noise. Then merge `omamobile-power-on` (`241736cc0`, drops
`status = "disabled"` from the MCT and the three states), so default images
get C2 without overlays.

### 5.6 U1: auto-hibernate (only if P0 printed a number)

```sh
tools/phone-ssh 'U=$(ls -d /sys/bus/platform/devices/*.ufs); echo 0 > $U/auto_hibern8; cat $U/auto_hibern8'
```

That is the runtime equivalent of commit `20bd72c37`. Use the phone normally
for an hour (package installs, `sync`, a big `cp`), and check `dmesg` for
`ufshcd` errors. Then the commit can ship in the next default kernel. If P0
printed "not supported", the commit is a no-op and ships as is.

### 5.7 U2: Hibern8 delay

```sh
tools/phone-ssh 'power-ab --detach --delay-ms 20 ufs-delay'   # 150 ms vs 20 ms
tools/phone-ssh 'power-ab --detach --delay-ms 4 ufs-delay'    # 150 ms vs 4 ms (stock)
```

Between runs, use the phone at 4 ms for an hour
(`echo 4 > $U/clkgate_delay_ms`) and watch `dmesg` for `hibern8 enter
failed` / `hibern8 exit failed` / `ufshcd` error-handler lines. Any error:
`echo 150 > $U/clkgate_delay_ms` and stop. A shorter delay means more
Hibern8 transitions (each exit costs a few hundred us of latency on the next
I/O), so the gain has to show in the numbers.

### 5.8 U3: persist

Only after U2 shows a gain with no errors: add the udev rule from 2.3 to
`omamobile-device-cheetah` (new package version through the repo).
Rollback: `pacman -U` the previous package, or delete the rule and reboot.

---

## 6. Risks and rollback

| Change | Risk | Default | Rollback |
|---|---|---|---|
| MCT node | timer misconfiguration -> no boot or stalls | disabled; overlay C1 | images without the overlay |
| C2 states | CPU not woken, firmware rejects, lockups | disabled; overlay C2 (all cores); default-on commit ready | runtime `state1/disable`; images without the overlay |
| UFS AH8 quirk | changes link handling on the root disk | in the kernel; runtime-proven by U1 first, no-op if AH8 unsupported | previous kernel; nothing on disk changes |
| Hibern8 delay | more H8 transitions, latency; link errors would hit the root FS | runtime sysfs only until U3 | write 150; remove the rule |
| power-ab | none (sysfs writes it restores) | manual | n/a |

Not touched: CPD and SICD (1.6), UFS runtime/system suspend levels, any
PMU register outside the CPU_INFORM path upstream already uses.

---

## Build result (2026-10-12)

- Kernel `7.3.0-rc6-omamobile-push1-00059-g20bd72c374e7` (branch head
  `20bd72c37`): `bin/omamobile kernel`, `modules` (1712 modules),
  `initramfs` and `images` exit 0 (`logs/kernel-power.log`,
  `modules-power.log`, `initramfs-power.log`, `images-power.log`). Images in
  `~/android/mainline/out-power/images`; their DTB has the MCT and the C2
  states **disabled**.
- `ufs-exynos.o` builds with `W=1` and no warnings.
- `dt-doc-validate` and yamllint pass for the MCT binding. `dt-validate`
  (dtschema 2026.9) of the default DTB and of the DTB with
  `power-mct-test` + `power-c2-all-test` applied reports only the existing
  `soc_id` and `/chosen/framebuffer` items. All three overlays compile, and
  `fdtoverlay` sets exactly the four `status` properties to `okay`.

---

## 7. On-phone results (2026-10-12, integration kernel 00097-g6caaf25a0a21)

- **P0:** as expected. No cpuidle directory, broadcast `bc_hrtimer`, no
  "SMC failed", `auto_hibern8` "Operation not supported" (so the controller
  has no auto-hibernate; commit `20bd72c37` is a no-op and U1 is skipped),
  `clkgate_enable` 1, `clkgate_delay_ms` 150. Measured on USB power, so no
  battery numbers yet.
- **C1 (MCT): pass.** Broadcast device `mct-comp`, clocksource still
  `arch_sys_counter`, `mct_comp_irq` and `mct_tick0..7` registered.
- **Little-cores-only C2: cannot work** (see 1.5): no driver registered.
  The overlay was removed and the runbook now has one all-cores gate.
- **C2 (all cores): pass so far.** Driver `psci_idle`, `state1` on all 8
  CPUs. Over 60 s idle each CPU spent 51-53 s in C2; rejected/usage about 7%
  on cpu0 and 1-4% on the others. An all-core 30 s load, then idle: no RCU
  stall, lockup or SMC failure. 30-minute soak under the watchdog feeder in
  progress.
- **Pending (needs the cable out):** B0 baseline and `ufs-gate`,
  `power-ab c2`, U2.
