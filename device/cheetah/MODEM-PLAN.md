<!-- SPDX-License-Identifier: MIT -->
# Modem plan (cheetah / gs201): S5300 on PCIe GEN4A_0

Status (2026-10-13): **IPC works: the CP serves SIT (M4.1h passed).**
The modem boots to ONLINE (M3.4.5b, M3.4.6) and, since M4.1h, answers
SIT requests (no SIM: "SIM card state 0 applications []", radio state 3
= POWER_OFF) and cycles its idle link as stock does, with no UFS handler
pass so far. What it took, M4.1-M4.1h: the link at Gen3 x2 (`02cc44421`),
stock's BAR layout (`7a7af33a2`), and above all **this phone's board id
(`ro.boot.cdt_hwid`)**, without which the main firmware hung after
INIT_END; `omamobile-modem` 0.1.4 requires it. **Never touch the modem's
BARs from userspace while CPIF may have the link down** (section 4: a
read of BAR0 with the link powered down hung the SoC, M4.1h). Earlier:
M0, M2.5, M3.1, M3.3-B, M3.4.0-M3.4.4 passed. **Every modem power-off is
followed by one recovered UFS error-handler pass**, so the modem stays
on once up (M2.6). **M4.1i passed** (the full probe twice, ten minutes of
idle link cycles, 0 UFS passes, NV unchanged). **But a reboot with the
modem ONLINE and its link idle hung the phone** (power key needed):
DesignWare's MSI code touches DBI while our PHY is isolated; `4b1364136`
guards it. **M4.1j passed (2026-10-13, 00511):** with that kernel the
same reboot came back on its own in about 25 s, NV unchanged. Shutdown
still printed two WARNs: CPIF's s51xx never freed the endpoint's MSI
vectors, so the endpoint's MSI domain went with them allocated;
fixed in `7b2b87cb7`. **M4.1k passed (2026-10-13, 00514):** the same
reboot with no WARN at all, NV unchanged. That is the second clean
reboot with the modem up, so a reboot after a modem start no longer
needs the human at the phone. T1 (2026-10-14): the ModemManager bridge
passed without a SIM. **M4.2 needs a SIM: follow "M4.2-M4.7: the first
SIM test" (end of section 3).** Section 6.3 lists what our CPIF port
still lacks for data and suspend.
Kernel branch `omamobile-modem` in `~/android/mainline/wt-modem` (head
`d34bbbad4`, section 6.3, M3.4.5b and M4.1b-M4.1k), build in `~/android/mainline/out-modem` (last
full build `7.3.0-rc6-omamobile-push1-00370-gd34bbbad467d`, W=1 clean on
the touched files).
Everything new is disabled by default. RADIOS-CAMERA-PLAN.md section 1 is
the survey this follows.

**Hard rule, unchanged:** the modem's NV and firmware partitions (`efs`,
`efs_backup`, `modem_userdata`, `persist`, `modem_a`, `modem_b`) are never
written from Linux. `cbd` and `rfsd` will only ever see RAM copies made from
verified images (M3). Nothing in M0-M2 touches them; M0 adds a udev rule
that makes the first five read-only at the block layer.

Path abbreviations:

- `L/` = our kernel, branch `omamobile-modem` (`~/android/mainline/wt-modem`)
- `G/` = `~/android/omamobile/out-kernel/google/gs-6.1/private` (Google's GPL gs201 kernel)
- `PC/` = `G/google-modules/soc/gs/drivers/pci/controller/dwc-whi` (the PCIe driver stock gs201 runs: `pcie-exynos-gs.ko`, `G/devices/google/gs201/BUILD.bazel:55`)
- `CP/` = `G/google-modules/radio/samsung/s5300` (stock cheetah's CPIF: `G/devices/google/pantah/BUILD.bazel:37`, options in `pantah_defconfig:2-11`)
- `R/` = `~/android/reference/cheetah-stock-cp2a-root`
- `B/` = `~/android/reference/cheetah-partition-backup-20261011`

---

## 1. How stock brings the modem up

From `CP/modem_ctrl_s5100.c` and `PC/pcie-exynos-rc.c`:

1. **`power_on_cp()`** (`:992`) drives the control lines, raw levels:
   - `ap2cp_pda_active` = 1, `ap2cp_dump_noti` = 0.
   - `gpio_power_offon_cp()` (`:936`, `CONFIG_CP_WRESET_WA` unset):
     - **off:** `ap2cp_wakeup` 1 for 10 ms then 0, `nreset` 0,
       `cp_wrst_n` 0, `cp_pwr_on` 0 (30 ms), `pm_wrst_n` 0 (50 ms);
     - **on:** `pm_wrst_n` 1 (10 ms), `cp_pwr_on` 1 (10 ms), `nreset` 1
       (10 ms), `cp_wrst_n` 1.
2. **`start_normal_boot()`** (`:1335`) → `register_pcie()` (`:806`):
   - 200 ms, then `s5100_poweron_pcie(boot_on)` (`:1765`);
   - that calls `exynos_pcie_poweron(ch 0, Gen1)`, then enumerates
     `144d:*`;
   - `set_cp_rom_boot_img()`: the ROM DMAs the BOOT image from shared memory.
3. Check the CP status; power the link off; check again.
4. `s5100_poweron_pcie(Gen3)` for the main firmware: `ap2cp_wakeup` 1 and
   5 ms before it (`:1809`).

**The link itself** (`PC/pcie-exynos-rc.c`):
- `exynos_pcie_rc_poweron()` `:3358`: PHY isolation bypass, pins
  "active", PHY power-down clear, then `establish_link()`.
- `exynos_pcie_rc_establish_link()` `:3103`:
  - PHY config and lock checks;
  - soft power reset, RC mode, non-sticky reset;
  - EQ off (DBI 0x890 = 0x12000);
  - PERST# high and **18-20 ms** (Wi-Fi: 20-22);
  - ELBI 0x3bc/0x3a0/0x3a8/0x474/0x1078;
  - `dw_pcie_setup_rc()` + `exynos_pcie_setup_rc()` `:2720`, which for
    `EP_SAMSUNG_MODEM` also clears the root port BAR0 and ROM BAR
    (DBI 0x100010/0x100030);
  - IOCC: SYSREG_HSI1 **0x704** (`PC/pcie-exynos-rc.h:226`);
  - LTSSM, L0 within 48 ms (up to 10 tries);
  - 3 ms for the Gen1 → max change.
- Outbound ATU:
  - `prog_viewport_cfg0()` `:1361`: with `use-secure-atu` this is only
    **SMC 0x820020D8** (`:1343`, `PC/pcie-exynos-rc.h:311`);
  - `prog_viewport_mem_outbound()` `:1389` is skipped (EL3 owns the
    iATU);
  - config space is then read through the fixed config window
    (`0x40ffe000`).
- MSI:
  - the target is the modem's shared-memory MSI page (`cp_msi_rmem`
    0xf6200000, set by CPIF through `exynos_pcie_set_msi_ctrl_addr()`
    `:5109`);
  - separated vectors on GIC SPI 389-393, controller events on 388
    (`:4900-4950`, `R/live.dts:12058`).

## 2. M1: what is built (offline)

| Commit | What |
|---|---|
| `af92668ea` dt-bindings: soc: samsung: exynos-sysreg: add gs201 HSI1 | `google,gs201-hsi1-sysreg` |
| `d6b91d06d` dt-bindings: PCI: add Google gs201 PCIe GEN4A_0 (modem link) | `google,gs201-pcie-cp`, with a `modem` child for the control lines |
| `5f6a1a989` PCI: dwc: add a gs201 modem-link bring-up driver | `L/drivers/pci/controller/dwc/pcie-gs201-cp.c`, `CONFIG_PCIE_GS201_CP` (m) |
| `fb3537d02` arm64: dts: exynos: google: gs201: add PCIe GEN4A_0 and the modem MSI page | `cp-msi@f6200000` (no-map), `sysreg_hsi1`, `pcie_0` + `pcie_0_phy` (**disabled**), `pcie0_clkreq`/`pcie0_perst` pins |
| `665a08b47` arm64: dts: exynos: google: gs201-cheetah: describe the modem's control lines | `modem` child of `pcie_0` |
| `c22dc53b3` PCI: dwc: gs201-cp: isolate the PHY again after link_down | M2.4 fix: PMU 0x3ec0 back to 0 after the PHY is powered down; controller soft power reset as stock |
| `d04cff4b9` PCI: dwc: gs201-cp: optionally log the modem's cp2ap line changes | `watch_lines=1`: both-edge interrupts on the four cp2ap inputs, logged with kernel timestamps (M2.5) |
| `9c201b3f3` dt-bindings: PCI: google,gs201-pcie-cp: add the MSI page, isolation note | `memory-region` |
| `078ad0c76` arm64: dts: exynos: google: gs201: point PCIe GEN4A_0 at the modem MSI page | `cp_msi_mem` label, `memory-region` on `pcie_0` (still disabled) |
| `3a8f4c503` PCI: dwc: gs201-cp: register the modem's PCI bus on request, with MSI | `bus` step: host bridge, guarded config access, DWC MSI aimed at 0xf6200000 (M3.1) |

Checks (repeated for the five newer commits, 2026-10-12):
- full build exits 0 (`logs/kernel-modem2.log`, then `logs/kernel-modem3.log`);
  the driver builds `W=1` clean; checkpatch clean;
- `dt_binding_check` of `google,gs201-pcie-cp.yaml` passes;
- `dt-doc-validate` of both bindings passes;
- `dt-validate` of the default DTB and of the DTB with `modem-link-test`
  reports only the existing `soc_id`/simplefb items;
- `git merge-tree` against `omamobile-int`: clean.

**Merge order:** `omamobile-modem` alone, after `omamobile-gnss`; it is
based on int, which already has it.

**Default boot changes one thing:** 4 KiB at 0xf6200000 become reserved
(they were free RAM, and stock reserves them for the modem).

omamobile repo:
- `kernel/configs/omamobile.config`: `CONFIG_PCIE_GS201_CP=m`; for M3
  `CONFIG_F2FS_FS=m` (the RAM copies of the NV partitions are f2fs).
- Overlay `device/cheetah/overlays/modem-link-test.dtso`: enables the HSI1
  pin controller, `pcie_0` and `pcie_0_phy`.

**The driver** (`pcie-gs201-cp`) is deliberately not a PCI host yet:

- **Probe only maps and looks up.**
  - The PHY stays isolated.
  - PERST# and the eleven modem lines are taken with `GPIOD_ASIS`.
  - The PCIe pins are a pinctrl state named `active`, selected only by
    `link_up`.
- **Steps, one per write to `/sys/kernel/debug/gs201-pcie-cp/ctl`**, and
  only with the module parameter `allow_hw=1`:
  - `cp_on`, `cp_off`: the stock sequences above;
  - `link_up [1|2|3]`: Google's establish_link, reusing our
    `phy-gs201-pcie` (two lanes, PMU 0x3ec0) as the Wi-Fi link does, 3
    tries;
  - `atu`: the SMC;
  - `id`: vendor/device from the config window;
  - `link_down`: PERST#, LTSSM off, PHY power-down and isolation.
- **`status`** reads:
  - the line levels;
  - the PMU isolation bit, through the PMU regmap (the same path the PHY
    driver uses);
  - controller registers only once the PHY is out of isolation (the Wi-Fi
    lesson: an ELBI access while isolated hangs the SoC).
- `bus` (M3.1): register and scan the PCI bus, MSI on (3.3).
- Since M3.2 (section 2.1): the API CPIF calls (`gs201_pcie_cp_*()`) and
  the controller-event interrupt (link-down, completion timeout). **Not
  yet:** suspend.

Why our own driver and not Google's: Google's RC driver is one module for
both channels, built around its vendor DWC fork, and the Wi-Fi link already
runs on our `pcie-gs201`. The modem link shares only the PHY. A separate
driver keeps the Wi-Fi driver untouched.

### 2.1 M3.2 and the first M3.3 stage (offline, 2026-10-12)

Branch `omamobile-modem`, back-merged from `omamobile-int` first (a fast
forward: int already had the modem branch), then:

| Commit | What |
|---|---|
| `e760ccf73` dt-bindings: PCI: google,gs201-pcie-cp: let the modem driver own the lines | the `modem` child may be disabled |
| `ce6c974f8` PCI: dwc: gs201-cp: leave the modem lines to the modem driver | lines taken only while `modem` is available; otherwise `cp_on`/`cp_off` return -ENODEV and `status` says so |
| `4513ebe14` soc: google: cpif: import Google's S5300 modem interface driver | `CP/` files for boot, IPC, RFS, verbatim, not built (`L/drivers/soc/google/cpif/`) |
| `acfb82374` PCI: dwc: gs201-cp: export the modem link to the modem driver | `gs201_pcie_cp_*()` (`L/include/linux/soc/google/gs201-pcie-cp.h`) and the "ctrl" interrupt |
| `ff5b99009` soc: google: aoc: alsa: notify voice calls through the modem notifier only | AoC card built again once `EXYNOS_MODEM_IF` exists; no behaviour change |
| `f521c0894` soc: google: cpif: port the S5300 boot, IPC and RFS path to Linux 7.3 | `cpif.ko`, `shm_ipc.ko`, `pcie-gs201-compat.c` |
| `3ec0e495a` soc: google: cpif: shm_ipc: index regions by their memory-region position | no `rmem_index` needed on our reserved-memory nodes |
| `4983fc51e` dt-bindings: PCI: google,gs201-pcie-cp: add the modem's shared memory | `memory-region` on `modem` |
| `2afb0db3f` arm64: dts: exynos: google: gs201-cheetah: describe the modem's shared memory | IPC 0xea400000, MSI 0xf6200000, packets 0xe8000000, stock's order |
| `6ff2a4690` soc: google: cpif: take the lines and regions from the board's modem node | see "where the lines live" below |
| `4dce2136a` PCI: dwc: gs201-cp: refuse the modem driver's poweron without allow_hw | bind CPIF with the link provably down |
| `1344a9e0b` soc: google: cpif: do not let the driver be unloaded | no `remove()`, so no `module_exit()`: permanent |

**The link API (M3.2).** CPIF's ~20 `exynos_pcie_*()` calls map onto
`gs201_pcie_cp_*()` in `L/drivers/soc/google/cpif/pcie-gs201-compat.c`:

| Google's call | Ours | Notes |
|---|---|---|
| `exynos_pcie_poweron(ch, spd, width)` | `gs201_pcie_cp_poweron(spd)` | `link_up` + secure ATU + bus (scanned the first time, then MSI re-armed and the endpoint's saved config restored, as `PC/pcie-exynos-rc.c:3358-3530`); faults cleared; width ignored, as Google; **-EPERM without `allow_hw=1`** |
| `exynos_pcie_poweroff(ch)` | `gs201_pcie_cp_poweroff()` | PME_Turn_Off and the wait for L2 idle (`:3033-3101`), then our `link_down` (PHY isolated again); bus kept |
| `exynos_pcie_rc_chk_link_status(ch)` | `gs201_pcie_cp_link_ok()` | LTSSM 0x0d-0x14 = up (`:4299-4349`); lock-free, reads ELBI only while the PHY is out of isolation |
| `exynos_pcie_set_msi_ctrl_addr(ch, a)` | `gs201_pcie_cp_check_msi_addr(a)` | the target is the controller's `memory-region`; a mismatch is an error |
| `exynos_pcie_set_perst_gpio(ch, on)` | `gs201_pcie_cp_set_perst_level()` | raw level |
| `exynos_pcie_rc_l1ss_ctrl()` | `gs201_pcie_cp_l1ss()` | no-op: L1SS never enabled yet (open question 5) |
| `exynos_pcie_register_event()` / `deregister` | `gs201_pcie_cp_register_event()` | one client; callback from a work item with Google's event codes |
| `rc_get/set_sudden_linkdown_state`, `rc_get/set_cpl_timeout_state` | `gs201_pcie_cp_faults()` / `clear_faults()` | |
| `exynos_pcie_rc_force_linkdown_work()` | `gs201_pcie_cp_force_linkdown()` | atomic-safe; CPIF calls it with a spinlock held |
| `exynos_pcie_set_ready_cto_recovery()` | `gs201_pcie_cp_prepare_recovery()` | our `link_down` |
| `rc_register_dump`, `rc_dump_all_status`, `rc_print_msi_register` | `gs201_pcie_cp_dump()` | LTSSM, IRQ0-2, faults |
| `rc_set_outbound_atu` (BTL), `register_separated_msi_vector` (pktproc) | -EOPNOTSUPP | parts not ported |

**The "ctrl" interrupt (SPI 388).** Enabled after `link_up`, disabled first
in `link_down` (ELBI is readable only between them). IRQ1 bit 10 = link
down, IRQ2 bit 24 = completion timeout, as `exynos_pcie_rc_irq_handler()`
(`PC/pcie-exynos-rc.c:2853-2920`). The first fault is kept until CPIF
clears it, later ones are only logged (Google ignores them during a
recovery). After a link-down the endpoint's config space reads as absent
and the link-down source stays masked until the next `link_up`, so a dead
link cannot storm. Without a client the driver only logs "event ...: no
client". `status` shows `faults: <bits>, ctrl irq on|off`. This also
applies to the debugfs `link_up` from now on (M2.5.3 and M3.1 log a
link-down if the ROM's link drops).

**Where the lines live.** The plan said "move the lines to a CPIF node
(overlay)". That cannot work with our overlays: the base DTB has no
`__symbols__`, and our dtc refuses `<&{/path}>` references in an overlay
("Can't generate fixup for reference to path"), so an overlay cannot give a
new node GPIO or memory-region phandles. Putting Google's CPIF node in the
base DTS instead adds ~200 dt-validate items (vendor properties, no
binding). So the board describes the modem once, in the documented
`samsung,s5300-modem` child of `pcie_0` (lines, and now the three shared
regions); CPIF's own nodes carry only CPIF's configuration, and CPIF takes
the lines and regions from the modem node (`cp_lines_node()`,
`cp_rmem_node()`). Ownership is the node's status: the `modem-cpif-test`
overlay disables it, so the link driver leaves the lines alone and CPIF
owns them. Never apply `modem-link-test` and `modem-cpif-test` together.

**The CPIF port, stage 1 (M3.3).** `CONFIG_EXYNOS_MODEM_IF=m`,
`SEC_MODEM_S5100=y`, `SHM_IPC=m` (in `kernel/configs/omamobile.config`).
Built: the platform driver and DT parsing, the boot/dump device
(`/dev/umts_boot0`), the IPC/RFS character devices (`umts_ipc0/1`,
`umts_rfs0`, ...), the rmnet network devices, the shared-memory link with
legacy buffers, the S5100 control, the PCIe endpoint driver and the region
driver. Not built (as planned): packet processor (data goes through the
legacy raw buffers, `pktproc_*` left out of the node), DIT, PCIe IOMMU,
S2MPU, BTL, throughput monitor, thermal zones, SPI boot. Port changes
beyond API drift:
- GPIO descriptors from the modem node (raw levels, outputs start low).
- Regions are `no-map` here: `memremap()` (WB for cached, WC otherwise)
  instead of `phys_to_virt()`/`vmap()`; nothing is ever given back to the
  page allocator.
- Every `panic()` and `BUG()` is an error or a log line, including the one
  cbd can request (`IOCTL_TRIGGER_KERNEL_PANIC`).
- The PCI driver matches 144d:a5a5 only (stock: any Samsung function,
  which would take our root port 144d:ecec).
- `cpif` has no `remove()`, so it has no `module_exit()` either: once loaded
  it stays until reboot (`rmmod` refuses). Lesson from the AoC `rmmod` oops.
- `pcie-gs201-cp` refuses `gs201_pcie_cp_poweron()` unless loaded with
  `allow_hw=1`, so binding CPIF without it cannot touch the link.

DT: the modem node gets `memory-region` (base DTS); the overlay
`device/cheetah/overlays/modem-cpif-test.dtso` enables the HSI1 pins, the
controller and the PHY, disables the modem node for the link driver, and
adds `cpif` and `cp-shmem` from stock's nodes (`R/live.dts:18238`,
`:18649`), compared property by property with stock after `fdtoverlay`:
identical except the left-out parts, the GPIO property names, `pinctrl`
(below) and the AoC voice window. The modules are blacklisted by a new
file, `packages/omamobile-device-cheetah/vendor/modprobe.d/omamobile-cpif.conf`
(package version unchanged; reinstall it before the overlay boots).

**Stock's line pin states, not ported yet.** Stock's `cpif` node selects
11 pinctrl states: the seven ap2cp outputs with no pull and
`pin-con-pdn = 3` (keep the level in power-down), cp2ap-wakeup and
cp2ap-phone-active as EINT (function 0xf) with pull-down (`pin-pud = 1`),
ps-hold and cp2ap-cp-wrst with pull-down. M0.3 found ABL leaves gpa8-3
(cp2ap-wakeup) at `PUD` 0x3. Irrelevant for bind and boot with the AP
awake; needed before any suspend with the modem on (M3.4+). **Don't port
the pull-down on cp2ap-wakeup:** on this phone model, applying stock's
pull-down to that pin lost the ROM's wake signal, and keeping the
bootloader's pull-up (what M0.3 found) restored it (section 6.3).

**After M2.5 (2026-10-12, on int `606b84c7a`, back-merged as a fast forward):**

| Commit | What |
|---|---|
| `4bcede988` PCI: dwc: gs201-cp: power the modem off as stock does, and trace the lines | `cp_off` = stock's sequence (pda-active untouched), `pda_off`, `trace_lines` |
| `1aa72188d` soc: google: cpif: keep the modem on unless a power-off is allowed | `allow_poweroff` (default off), `trace_lines` |
| `d01e1ebbe` soc: google: cpif: s51xx: map the doorbell only inside the bridge window | stock maps BAR0 + offset from the window start even when the window is unassigned |
| `781b9c3d8` PCI: dwc: gs201-cp: add a slow power-off step to tell the edges apart | `cp_off_slow`, 1 s between edges |

Same checks as below: full build exits 0 (`logs/kernel-modem7.log`),
`W=1` clean, checkpatch clean on the changes. Repo:
`packages/omamobile-modem/profiles/modem.conf` binds `by-name/modem`
(rfsd and cbd open it unsuffixed), `/dev/kmsg`, CPIF's sysfs device,
`/chosen/plat` and `/chosen/config` read-only, and a stand-in
`/sys/power/wake_lock`, and refuses to start without CPIF's device.

**Checks (2026-10-12):**
- full build exits 0: `logs/kernel-modem6.log` (release in the last line
  of this list);
- `W=1`: `pcie-gs201-cp.o` and all of `drivers/soc/google/cpif/` build with
  no warnings (16 missing-prototype warnings in Google's code fixed);
- checkpatch `--strict`: clean on our new code (driver, header,
  `pcie-gs201-compat.c`, `cpif-compat.h`, Kconfig, Makefile); the imported
  Google files keep Google's style, as with the AoC port;
- `dt_binding_check` of `google,gs201-pcie-cp.yaml`: passes;
- `dt-validate` of the default DTB: only the existing `soc_id`,
  simplefb and gs201 PMU/watchdog compatible items; with `modem-cpif-test`:
  the same plus the vendor properties of `cpif` and `cp-shmem` (no binding,
  overlay only);
- `modinfo`: `cpif` depends on `shm_ipc` and `pcie-gs201-cp`.
- release `7.3.0-rc6-omamobile-push1-00318-g1344a9e0b9ea` (head `1344a9e0b`);
  `git merge-tree` against `omamobile-int`: clean.

## 3. Runbooks

### M0: read-only, current int kernel

**M0.1-M0.3 as RADIOS-CAMERA-PLAN.md 1.6:**

```sh
# M0.1 partitions unchanged against the 2026-10-11 backup (reads ~430 MB)
tools/phone-ssh 'for p in efs efs_backup modem_userdata persist modem_a modem_b; do
  printf "%s  %s.img\n" "$(sha256sum < /dev/disk/by-partlabel/$p | cut -d" " -f1)" "$p"; done' \
  > logs/m0-partitions.sha256
grep -E ' (efs|efs_backup|modem_userdata|persist|modem_a|modem_b)\.img$' \
  ~/android/reference/cheetah-partition-backup-20261011/SHA256SUMS | sort -k2 | diff - <(sort -k2 logs/m0-partitions.sha256)
tools/phone-ssh 'grep -E "sda(1|5|6|7|19|29) " /proc/mounts'
# M0.2 memory map
tools/phone-ssh 'grep -iE "e8000000|ea400000|f6200000" /proc/iomem'
# M0.3 CP lines on ALIVE / FAR_ALIVE
tools/phone-ssh 'P=/sys/kernel/debug/pinctrl; grep -hE "\((gpa0-[23]|gpa8-[234])\)" $P/*180d0000*/pins $P/*180e0000*/pins'
```

**M0.4, HSI1 lines.** HSI1 pinctrl is in int now (via `omamobile-gnss`).
Add `hsi1-pinctrl-test` to the overlays the phone already boots with:

```sh
ov gnss-pmic-test gnss-test aoc-boot-test hsi1-pinctrl-test && bin/omamobile push   # reboots
tools/phone-ssh 'grep -hE "\((gph0-[0-5]|gph1-[0-6])\)" /sys/kernel/debug/pinctrl/*11840000*/pins'
```

Expected:
- gph0-0 (PERST#) and the ap2cp lines (gph0-2/3, gph1-1/2/3/6) inputs or
  low outputs;
- gph1-4/5 (eSE/NFC resets) as ABL left them;
- gph1-0 (AoC SPI select) untouched.

Record `PUD` for gpa8-3 (`cp2ap_wake_up`): keep whatever ABL set.

**M0.5, protection (no hardware access: block-layer flag only, undone by
reboot or `blockdev --setrw`):**

```sh
tools/phone-ssh 'cat > /etc/udev/rules.d/60-omamobile-modem-nv-ro.rules' <<'EOF'
# Omarchy Mobile: the modem's NV and firmware partitions are never written from Linux
SUBSYSTEM=="block", ENV{ID_PART_ENTRY_NAME}=="efs|efs_backup|modem_userdata|modem_a|modem_b", RUN+="/usr/bin/blockdev --setro $devnode"
EOF
tools/phone-ssh 'udevadm control --reload; udevadm trigger -s block -c change;
  for p in efs efs_backup modem_userdata modem_a modem_b; do echo $p $(blockdev --getro /dev/disk/by-partlabel/$p); done'
#   pass: all 1. (persist stays writable for the fingerprint work's own plan; nothing here writes it.)
```

**M0 result (2026-10-12, 7.3.0-rc6-omamobile-push1-00283-gafa4d777403d).**
This root has no `/dev/disk/by-partlabel`, so find each partition by its
`PARTNAME` instead:
`d=$(grep -l "^PARTNAME=$p\$" /sys/class/block/*/uevent | head -1 | cut -d/ -f5)`.
- **M0.1: mismatch, explained, new backup.** `modem_a` matched the
  2026-10-11 backup. `efs`, `efs_backup`, `modem_userdata` and `persist`
  differed: stock Android booted once on slot A after the backup (a
  fallback during bring-up), and its modem stack writes those. `modem_b`
  also differed, and now has exactly `modem_a`'s contents; nothing in our
  Linux writes it (all six read `ro=1` and none is mounted). The old backup
  still matches its own `SHA256SUMS`, so it was intact. A fresh read-only
  copy of the six went to
  `~/android/reference/cheetah-partition-backup-20261012-radio/` (off-repo,
  mode 600), and its checksums match the M0.1 reads. Compare against that
  one from now on; a stock boot will change the NV partitions again.
- **M0.2:** `e8000000-e9ffffff` and `ea400000-eabfffff` are reserved;
  `f6200000` is not listed.
- **M0.3:** gpa0-2/3 and gpa8-2/4 inputs, low, `PUD` 0x1; gpa8-3
  (`cp2ap_wake_up`) input, low, `PUD` 0x3 (keep it).
- **M0.4** runs on the M2 boot: `modem-link-test` enables the HSI1 pin
  controller too. **Result:** gph0-0..5 and gph1-0..3, gph1-6 are inputs,
  low, `PUD` 0x1; gph1-4 (eSE reset) is an output driven low, gph1-5 (NFC
  reset) an output driven high, both as ABL left them; gph1-0 (AoC SPI
  select) untouched.
- **M0.5: passed.** The udev rule is in place, and all five partitions read
  `blockdev --getro` 1.

**M2.0 result (same boot): passed.** `pcie_gs201_cp` is blacklisted
(device-cheetah 0.1.21) and was loaded by hand with `allow_hw=1`: "modem
PCIe ch0 bring-up: 2 lanes, steps enabled". Every ap2cp output and cp2ap
input is 0, PERST# is asserted, PMU 0x3ec0 is 0x0 (PHY isolated), and the
state is "cp 0, phy 0/0, link 0, atu 0". No controller access.

### M2: link only (int + `omamobile-modem`, overlay `modem-link-test`)

No firmware is involved and nothing reaches the NV partitions. The modem's
ROM only answers on PCIe and waits for a BOOT image it never gets. Watch the
kernel log from a second terminal (`tools/phone-ssh dmesg -w`). If anything
hangs, the watchdog resets the phone; the overlay is not in the default DTB.

```sh
ov gnss-pmic-test gnss-test aoc-boot-test modem-link-test && bin/omamobile push   # reboots
# M2.0 bind, read-only
tools/phone-ssh 'modprobe pcie-gs201-cp allow_hw=1; dmesg | grep -i "pcie-cp\|11920000" | tail -3;
  cat /sys/kernel/debug/gs201-pcie-cp/status'
#   pass: "modem PCIe ch0 bring-up: 2 lanes, steps enabled"; PMU 0x3ec0 bit 0 = 0 (isolated);
#   lines as in M0.3/M0.4; no LTSSM line (PHY isolated, so no controller reads)
# M2.1 modem power only, no PCIe (about 130 ms of GPIO steps)
tools/phone-ssh 'echo cp_on > /sys/kernel/debug/gs201-pcie-cp/ctl; sleep 2; cat /sys/kernel/debug/gs201-pcie-cp/status;
  sleep 8; cat /sys/kernel/debug/gs201-pcie-cp/status'
#   expect: outputs pda-active 1, pwr-on 1, nreset 1, cp-wrst 1, pm-wrst 1. The cp2ap inputs
#   may stay low: the ROM waits for the link. Record them.
#   then: echo cp_off > .../ctl ; status shows the outputs back at 0
# M2.2 link at Gen1 (the first ELBI/DBI accesses on this controller, after isolation release)
tools/phone-ssh 'echo cp_on > /sys/kernel/debug/gs201-pcie-cp/ctl; sleep 0.2;
  echo link_up > /sys/kernel/debug/gs201-pcie-cp/ctl; dmesg | tail -8; cat /sys/kernel/debug/gs201-pcie-cp/status'
#   pass: "link up: Gen1 x1|x2 (target Gen1)"; LTSSM 0x11 (L0)
#   "no L0" three times: send dmesg and status; then link_down + cp_off
# M2.3 secure ATU and the endpoint ID
tools/phone-ssh 'echo atu > /sys/kernel/debug/gs201-pcie-cp/ctl; echo id > /sys/kernel/debug/gs201-pcie-cp/ctl; dmesg | tail -3'
#   pass: "secure ATU SMC: 0"; "endpoint 144d:a5a5 class ..."
# M2.4 everything off
tools/phone-ssh 'echo link_down > /sys/kernel/debug/gs201-pcie-cp/ctl; echo cp_off > /sys/kernel/debug/gs201-pcie-cp/ctl;
  cat /sys/kernel/debug/gs201-pcie-cp/status; rmmod pcie_gs201_cp'
#   pass: PMU bit 0 back to 0, outputs 0, PERST# asserted
```

**M2.1-M2.4 result (2026-10-12, same boot): the link works; two open
problems.**
- **M2.1 passed.** All five ap2cp outputs went to 1. The modem raised
  `cp2ap-wakeup` 1 within 2 s (its ROM asking for the link);
  `cp2ap-cp-wrst`, `ps-hold` and `phone-active` stayed 0.
- **M2.2 passed.** PHY "PLL lock 1, CDR lock 1, OC done 1", "DBI ID
  0xa5a5144d", "link up: Gen1 x1 (target Gen1), try 1", LTSSM 0x11 (L0).
  Only one lane trained, at the Gen1 target.
- **M2.3 passed.** "secure ATU SMC: 0x0"; "endpoint 144d:a5a5 class
  000000".
- **M2.4 partial.** The outputs went back to 0 and PERST# was asserted,
  but **PMU 0x3ec0 stayed 0x1**: the PHY was not isolated again. Fixed in
  `c22dc53b3` (M2 analysis below); re-test in M2.5.3.
- **UFS errors around modem power changes.** UFS ran its error handler
  (`saved_err = 0x4; saved_uic_err = 0x40`, a PA-layer error), recovered
  at once (Gear 4, 2 lanes, HBA operational), and logged no I/O or
  filesystem errors. It happened twice, at 252.24 s (about 1 s before the
  M2.2 power cycle, with the modem powered since M2.1 at 231 s) and at
  277.14 s (0.23 s after the M2.4 power-off). The two previous boots had
  none. Until the cause is known (a shared supply, ground bounce or a
  reference clock between HSI1 and UFS are candidates), keep the modem
  powered only for short attended tests, and check
  `dmesg | grep ufshcd_err_handler` after each. Analysis and the M2.5
  measurement below.

### M2 analysis (offline, 2026-10-12)

**M2.4, the PHY stayed out of isolation: a driver bug, fixed in `c22dc53b3`.**
- `link_down` called `phy_exit()` and assumed it isolates the PHY. Our
  `phy-gs201-pcie` exit deliberately only drops the clocks: Google never
  isolates the Wi-Fi link's PHY after probe, and that controller is
  accessed after exit.
- Stock does not isolate ch0 at runtime either: `R/live.dts` has neither
  `use-phy-isol-en` (so `use_phy_isol_con` is false,
  `PC/pcie-exynos-rc.c:1934-1950`) and sets `phy-power-off = "false"`. It
  isolates a link that is down only when the system suspends
  (`exynos_pcie_rc_suspend_noirq()`, `PC/pcie-exynos-rc.c:5433-5442`).
- The modem link is down most of the time, so ours isolates at every
  `link_down`, after the PHY power-down and the clock release, through the
  same SMC-backed PMU regmap that `phy_init()` uses to release it (never
  devmem), and logs the value read back: "PHY isolated (PMU 0x3ec0 =
  0x0)". `link_down` now also pulses the controller's soft power reset
  after LTSSM is off, as `exynos_pcie_rc_poweroff()` does
  (`PC/pcie-exynos-rc.c:3626-3632`). Re-test in M2.5.3.

**M2.2, x1 instead of x2: expected.** CPIF asks for the ROM link with
`exynos_pcie_poweron(ch, 1, 1)` (Gen1, width 1) and for the main firmware
with `(ch, 3, 2)` (`CP/modem_ctrl_s5100.c:1824`). Google's RC driver
ignores the width (`PC/pcie-exynos-rc.c:4280`, two arguments), so the x1
comes from the modem's ROM.

**The UFS errors: what they are.** `saved_err 0x4` is `UIC_ERROR`,
`saved_uic_err 0x40` is `UFSHCD_UIC_PA_GENERIC_ERROR`: the PA layer
reported a **LINERESET** on the UFS M-PHY link (`L/drivers/ufs/core/ufshcd.c:7194-7206`).
With only that bit set, the error handler checks the power mode and
restores it if needed (`:7079-7090`); no reset, no aborted command. So
the UFS link saw a burst of errors bad enough for one side to send a line
reset, then carried on. That points at signal integrity or a reference
or supply disturbance on the UFS lanes, not at anything the modem driver
wrote.

**What UFS and the modem link share, from stock's DT and sources:**

| Candidate | Finding | Verdict |
|---|---|---|
| A PMIC rail | PCIe ch0 PHY: S2MPG12 LDO16M (`L16M_PCIE0`, 0.85 V) and LDO18M (`L18M_PCIE0`, 1.8 V), both `regulator-always-on` (`R/live.dts:13487-13520`), nothing else on them. UFS: `ufs-vcc` (a GPIO-switched fixed regulator, `:9829-9836`) and S2MPG13 LDO2S (`L2S_PLL_MIPI_UFS`, `:14002`). Our DT does not describe these regulators, so nothing switches them. | Not shared |
| A reference clock | UFS takes its 38.4 MHz reference from the AP's `ufs_refclk_out` pin gph3-0 in HSI2 (`R/live.dts:4870-4876`); the PCIe ch0 PHY is in HSI1, with no CMU clocks in stock (`pcie-clk-num = 0`). Both PHYs run from the TCXO, but the first error came with the ch0 PHY still isolated and never powered. | Unlikely for event 1; possible for event 2 (PHY power-down 0.2 s before) |
| PMU registers | PHY controls are neighbours (PCIe ch0 0x3ec0, ch1 0x3ec4, UFS 0x3ec8: `R/live.dts:9805`), each its own register, written with atomic set/clear SMCs. No PMU write happened near event 1. | No |
| Pins | The modem lines are in HSI1 (gph0/gph1) and ALIVE (gpa0/gpa8); the UFS pins are gph3 in HSI2. | No |
| The modem's own power | The S5300 has its own supply from VSYS (`VSYS_PWR_MODEM`, ODPM channel `R/live.dts:13717`), sequenced by `pm_wrst_n`/`cp_pwr_on`. Event 2 came 0.14 s after the last power line dropped (the modem's PMIC turning its rails off). Event 1 came 21 s after power-on with the ROM waiting for a link, and with no AP action: consistent with the ROM giving up and resetting itself, which stock never lets happen (CPIF trains the link 200 ms after power-on, `CP/modem_ctrl_s5100.c:870-872`). | Most likely: a load step on VSYS or ground bounce when the modem changes power state |
| DMA from the modem | Event 1 came before any link existed. The endpoint's bus mastering was never enabled. | No |

Stock's error-free record does not contradict this: stock powers the modem
once per boot and keeps it running; it powers it off only at shutdown. Our
M2 sat the ROM on a missing link for 21 s and cut its power with the UFS
link busy, two states stock does not reach.

**Proposed fix: follow stock's timing; no software can remove a supply
transient.**
1. Never leave the modem powered without a link for more than a few
   seconds: `cp_on` is followed by `link_up` within 0.2 s (M2.5.3, M3.1),
   and from M3 on CPIF does this itself.
2. Power the modem off only when it has to be (stock: shutdown, crash
   reset). The M3 service keeps it on.
3. The measurement below tells which of the two transitions disturbs UFS
   and whether stock's timing avoids it. If a transition still causes a
   LINERESET with stock timing, the next step is hardware (a scope on VSYS
   and the UFS supplies), which is out of reach here. The errors recovered
   cleanly, so that would be a nuisance at boot and shutdown, not a risk to
   data.

### M2.5: isolation re-test and the UFS measurement (int + `omamobile-modem` @ `3a8f4c503` or later)

**Before:** the human merges `omamobile-modem` into `omamobile-int` (merge
tree clean on 2026-10-12) and builds int into `out-int`. The DTB changes
(`memory-region`), so push the images, not only the modules. Same overlays
as M2 (`modem-link-test`, never `modem-cpif-test`). **Risk: medium.** UFS
is the root disk and M2.5.2/M2.5.3 deliberately repeat the two transitions
that coincided with LINERESETs. Each was seen once and recovered at once.

The same runbook works at the M3.2 head (section 2.1): the steps are
unchanged; the driver also enables the "ctrl" interrupt after `link_up`,
so a link that drops during M2.5.3 now logs "link down (IRQ0/1/2 ...)",
and `status` has a `faults:` line (expect `0x0`, `ctrl irq off` after
`link_down`).

**Modem power is attended and short.** M2.5.2 and M2.5.3 keep the modem
powered for 60 s each, under load, with a human watching the kmsg stream.
Each is one SSH command that ends with `cp_off`; in case the session dies
in between, arm a dead-man timer first that powers the modem off after
100 s, and stop it after the step (it does nothing if the modem is
already off):

```sh
tools/phone-ssh 'systemd-run --unit=x-modem-off --on-active=100 sh -c "C=/sys/kernel/debug/gs201-pcie-cp/ctl; echo link_down > \$C; echo cp_off > \$C"'
# ... the step ...
tools/phone-ssh 'systemctl stop x-modem-off.timer 2>/dev/null; cat /sys/kernel/debug/gs201-pcie-cp/status | grep -E "pwr-on|PMU|state"'
#   pass: ap2cp-cp-pwr-on 0, PMU 0x3ec0: 0x0, "state: cp 0"
```

```sh
ov gnss-pmic-test gnss-test aoc-boot-test modem-link-test && bin/omamobile push   # reboots
# second terminal, for all of M2.5 and M3.1:
tools/phone-ssh dmesg -w | tee logs/m2.5-kmsg.log

# M2.5.0 load with the line watch (reads only)
tools/phone-ssh 'modprobe pcie-gs201-cp allow_hw=1 watch_lines=1; dmesg | grep -E "pcie-cp|watching" | tail -6'
#   pass: "steps enabled" and four "watching cp2ap-... (now 0)". A "no interrupt" or
#   "cannot watch" warning for a line: record it and go on (the others still log).
# UFS counters (debugfs) and a 1 GiB file to read (once; a normal file on the root fs)
tools/phone-ssh 'cat /sys/kernel/debug/ufshcd/14700000.ufs/stats; dmesg | grep -c ufshcd_err_handler;
  test -f /var/tmp/ufsload || head -c 1G /dev/zero > /var/tmp/ufsload'

# M2.5.1 baseline: 60 s of UFS reads, modem off
tools/phone-ssh 'timeout 60 sh -c "while :; do dd if=/var/tmp/ufsload of=/dev/null bs=1M iflag=direct status=none; done";
  dmesg | grep -c ufshcd_err_handler; cat /sys/kernel/debug/ufshcd/14700000.ufs/stats'
#   pass: the err_handler count and every counter unchanged

# M2.5.2 M2's timing: modem powered with no link for 60 s under load, then off under load
#   (dead-man armed as above)
tools/phone-ssh 'C=/sys/kernel/debug/gs201-pcie-cp/ctl
  (timeout 70 sh -c "while :; do dd if=/var/tmp/ufsload of=/dev/null bs=1M iflag=direct status=none; done") &
  echo cp_on > $C; sleep 60; echo cp_off > $C; wait
  dmesg | grep -E "cp2ap|power-|ufshcd_err_handler|saved_err" | tail -30; cat /sys/kernel/debug/ufshcd/14700000.ufs/stats'
#   record: the time of every cp2ap edge (expect cp2ap-wakeup -> 1 within 2 s of
#   "modem power-on sequence"; anything at about +20 s is the ROM giving up),
#   and of every ufshcd_err_handler, against "modem power-on/off sequence".

# M2.5.3 stock timing: link 0.2 s after power-on, 60 s up under load, then down and off under load
#   (dead-man armed as above)
tools/phone-ssh 'C=/sys/kernel/debug/gs201-pcie-cp/ctl
  (timeout 70 sh -c "while :; do dd if=/var/tmp/ufsload of=/dev/null bs=1M iflag=direct status=none; done") &
  echo cp_on > $C; sleep 0.2; echo link_up > $C; sleep 60; echo link_down > $C; echo cp_off > $C; wait
  dmesg | grep -E "cp2ap|power-|link up|PHY isolated|ufshcd_err_handler|saved_err" | tail -30
  cat /sys/kernel/debug/gs201-pcie-cp/status; cat /sys/kernel/debug/ufshcd/14700000.ufs/stats'
#   pass (the M2.4 fix): "link up: Gen1 x1", then "PHY isolated (PMU 0x3ec0 = 0x0)";
#   status shows PMU 0x3ec0: 0x0, outputs 0, perst 1, "state: cp 0, phy 0/0, link 0, atu 0"
#   (M3.2 head: also "faults: 0x0, ctrl irq off"; a "link down" line during the 60 s
#   means the ROM dropped its link: record its time against the cp2ap edges)
#   record: ufshcd_err_handler times as in M2.5.2
tools/phone-ssh 'rmmod pcie_gs201_cp; rm -f /var/tmp/ufsload'
```

**Expect/Pass** per step above. **Stop** at once (`echo link_down > $C;
echo cp_off > $C; rmmod pcie_gs201_cp`, no more modem power until
analysed) if UFS logs anything
beyond the error handler and its recovery: an I/O error, `Host Resets` or
`SCSI command aborts` going up in `stats`, "link broken", an ext4 error.
If the root filesystem stops answering, wait for the watchdog, or ask the
human to force a restart.
**Rollback:** `rmmod pcie_gs201_cp`; images without `modem-link-test`.

**Reading the result:**

| Errors seen in | Meaning | Next |
|---|---|---|
| none of 1-3 | Neither transition disturbs UFS at this load; M2's two events need the ROM timeout or chance | Go on to M3.1 with stock timing |
| 2 only, with a cp2ap edge at about +20 s | The ROM's own reset after the link timeout | Fix 1 is enough; go on |
| 2 and 3, at `cp_off` | The modem's power-down disturbs UFS | Fix 2: power off only at shutdown; repeat 3 without the load to see whether an idle (hibernated) UFS link is immune |
| 1 | Not the modem | Stop modem work; investigate UFS on its own |

### M2.6: the modem power-off and UFS (after the M2.5 result)

**What M2.5 found** (result below, in M3): every modem power-off is
followed, 0.08-0.15 s after "modem power-off sequence", by one recovered
UFS error-handler pass (`saved_uic_err 0x40`, a PA LINERESET) and
thousands of Data Link Layer errors (76021 over three power-offs, 12 PHY
Adapter). Power-on, a 60 s link under load and `link_down` before the
power-off were not separated in time from it, so M2.5 cannot say whether
`link_down` alone disturbs UFS. No I/O errors, resets or aborts.

**Our sequence against stock's, edge by edge** (`CP/modem_ctrl_s5100.c`):

| | stock `power_off_cp()` (cbd's POWER_OFF) | stock `power_shutdown_cp()` (shutdown) | ours, M2.5 (`link_down` + `cp_off`) |
|---|---|---|---|
| before the lines | state OFFLINE; link off first (`pcie_clean_dislink()` -> `s5100_poweroff_pcie()`: ap2cp-wakeup 0 + 5 ms, PME_Turn_Off, PERST# low, LTSSM off, soft reset, PHY powered down, **not isolated**) | cp2ap interrupts off; waits up to 3 s for phone-active high (CP running); the link stays up | `link_down`: PERST# low, LTSSM off, soft reset, PHY powered down **and isolated** (no PME_Turn_Off in the debugfs step) |
| lines (`gpio_power_off_cp()`) | wakeup 1, 10 ms, wakeup 0, nreset 0, cp-wrst 0, pwr-on 0, 30 ms, pm-wrst 0, 50 ms | the same | the same |
| after | nothing | link off afterwards | **pda-active 0** (never in stock: stock drives it low only for AP suspend) |

There is no graceful shutdown handshake in stock's kernel driver: cbd/RIL
may turn the radio off first, then the same line sequence cuts the
modem's power. The only differences were the trailing pda-active edge
and the PHY isolation. The PHY can't be the cause: in M2.5.2 it was never
released (no link) and the error came anyway. The timing argues against
pda-active too (it came at +90 ms, one error at +80 ms), which leaves the
modem's own power-down (pwr-on at +10 ms, pm-wrst at +40 ms): its PMIC
turning its rails off. Stock reaches that edge only at shutdown and in
crash recovery, so it would not show there.

**Changes (offline, kernel `4bcede988`, `1aa72188d`, `781b9c3d8`):**
- `cp_off` is now stock's sequence exactly: pda-active stays high; a
  separate `pda_off` step (only with the modem off) drives it low, so
  each edge is measured on its own. Module removal still leaves all lines
  low.
- `trace_lines=1` (`pcie-gs201-cp` and `cpif`) logs every output edge with
  its time.
- `cp_off_slow`: the same edges, same order, 1 s apart: a diagnostic to
  attribute the disturbance to one edge.
- **Policy: the modem stays on once it is up.** CPIF refuses cbd's
  `IOCTL_POWER_OFF` unless loaded with `allow_poweroff=1` ("power off
  refused, the modem stays on"); stopping the modem profile leaves it on.
  The modem is powered off only by: shutdown/reboot (stock's
  `power_shutdown_cp()`, one UFS event per reboot, as now), crash
  recovery (cbd's reset: a power cycle), and an explicit, attended
  request (`allow_poweroff=1` and the profile's stop, or `cp_off` on the
  link driver when it owns the lines). Restarting cbd power-cycles the
  modem (its POWER_ON starts with the off sequence): don't, reboot
  instead.

**M2.6 runbook: one power-off with the new sequence, edges apart in time.**
Kernel: int with `omamobile-modem` at `781b9c3d8` or later; overlays as
M2.5 (`modem-link-test`, not `modem-cpif-test`). **Risk: medium**: one
deliberate modem power-off, which so far always gave one recovered UFS
handler pass; the root disk is under load as in M2.5 for an A/B
comparison. Attended; kmsg streamed (`tools/phone-ssh dmesg -w | tee
logs/m2.6-kmsg.log`).

```sh
# M2.6.0 load with tracing (reads only), baseline
tools/phone-ssh 'modprobe pcie-gs201-cp allow_hw=1 watch_lines=1 trace_lines=1;
  cat /sys/bus/platform/devices/14700000.ufs/auto_hibern8 2>&1; dmesg | grep -c ufshcd_err_handler;
  cat /sys/kernel/debug/ufshcd/14700000.ufs/stats; test -f /var/tmp/ufsload || head -c 1G /dev/zero > /var/tmp/ufsload'
#   record: auto_hibern8, the err_handler count, the stats

# M2.6.1 dead-man, then one power cycle with each transition 5 s apart, under load
tools/phone-ssh 'systemd-run --unit=x-modem-off --on-active=100 sh -c "C=/sys/kernel/debug/gs201-pcie-cp/ctl; echo link_down > \$C; echo cp_off > \$C"'
tools/phone-ssh 'C=/sys/kernel/debug/gs201-pcie-cp/ctl; S=/sys/kernel/debug/ufshcd/14700000.ufs/stats
  (timeout 50 sh -c "while :; do dd if=/var/tmp/ufsload of=/dev/null bs=1M iflag=direct status=none; done") &
  echo cp_on > $C; sleep 0.2; echo link_up > $C; sleep 20
  echo "== link_down"; echo link_down > $C; sleep 5; grep -E "Data Link|PHY Adapter" $S
  echo "== cp_off";    echo cp_off > $C;    sleep 5; grep -E "Data Link|PHY Adapter" $S
  echo "== pda_off";   echo pda_off > $C;   sleep 5; grep -E "Data Link|PHY Adapter" $S; wait
  systemctl stop x-modem-off.timer
  dmesg | grep -E "pcie-cp|ufshcd_err_handler|saved_err" | tail -40; cat /sys/kernel/debug/gs201-pcie-cp/status'
#   expect: "link up: Gen1 x1"; at link_down "PHY isolated (PMU 0x3ec0 = 0x0)"; the traced edges
#   "ap2cp-wakeup = 1", "... = 0", "ap2cp-nreset = 0", "ap2cp-cp-wrst = 0", "ap2cp-cp-pwr-on = 0",
#   "ap2cp-pm-wrst = 0", then 5 s later "ap2cp-pda-active = 0"; status: outputs 0, PMU 0x0
#   record: the time of every ufshcd_err_handler and the stats after each phase
```

| UFS errors after | Meaning | Next |
|---|---|---|
| `link_down` | taking the link down (PERST#, PHY power-down or isolation) disturbs UFS: CPIF does that whenever the modem idles | offline: stop isolating at runtime (stock doesn't), measure again; before M3.4 |
| `cp_off` only | the modem's power-down itself; stock's sequence doesn't avoid it | keep the policy; optional M2.6.2 attributes the edge; go on to M3.3-B |
| `pda_off` only | the extra pda-active edge was the cause; fixed by matching stock | go on |
| none | the M2.5 events needed the old edge timing, or chance | keep the policy; go on |

```sh
# M2.6.2 OPTIONAL, only on the human's go (a second power-off): which edge
tools/phone-ssh 'systemd-run --unit=x-modem-off --on-active=100 sh -c "C=/sys/kernel/debug/gs201-pcie-cp/ctl; echo link_down > \$C; echo cp_off > \$C"'
tools/phone-ssh 'C=/sys/kernel/debug/gs201-pcie-cp/ctl
  (timeout 30 sh -c "while :; do dd if=/var/tmp/ufsload of=/dev/null bs=1M iflag=direct status=none; done") &
  echo cp_on > $C; sleep 2; echo cp_off_slow > $C; sleep 3; wait; systemctl stop x-modem-off.timer
  dmesg | grep -E "pcie-cp|ufshcd_err_handler" | tail -20'
#   record: which traced edge (1 s apart) the ufshcd_err_handler follows
tools/phone-ssh 'rmmod pcie_gs201_cp; rm -f /var/tmp/ufsload'
```

**Stop** as M2.5 (an I/O error, Host Resets or SCSI aborts going up,
"link broken", an ext4 error): no more modem power until analysed.
**Rollback:** `link_down`, `cp_off`, `systemctl stop x-modem-off.timer`,
`rmmod pcie_gs201_cp` (leaves all lines low).

### M3: boot the modem

**Goal:** the S5300 boots its stock firmware from a RAM copy of
`modem_a` and reaches ONLINE (`IOCTL_GET_CP_STATUS`), with `rfsd` serving
NV from RAM copies. The radio stays off: nothing sends the SIT request
that turns it on (that is M4). The real NV and firmware partitions are
never written and never enter the chroot.

**What the host side needs, from `CP/` (CPIF-20220408R1, the pantah
options in `G/devices/google/pantah/pantah_defconfig:2-11`):**

- **A PCI device to bind to.** `s51xx_pcie.c` is a `pci_driver` for
  `144d:a5a5`. It allocates four MSI vectors with
  `pci_alloc_irq_vectors_affinity()` (`CP/s51xx_pcie.c:305-316`,
  `CP/modem_ctrl_s5100.c:733-804`) and rewrites BAR0 itself to
  `pci_db_addr` (0x14e60000, the doorbell; `CP/s51xx_pcie.c:381-420`),
  which is inside our MEM window. **Done offline:** the `bus` step
  (`3a8f4c503`), tested in M3.1.
- **MSI.** Separated MSI: one GIC SPI per DWC MSI block (SPI 389-393 =
  blocks 0-4; `PC/pcie-exynos-rc.c:4913-4945`), the same split mainline's
  DWC core handles with `msi0`..`msi4`. The target is `cp_msi_rmem`
  (0xf6200000). **Done offline**, with one gap: pktproc's "exclusive" IRQs
  take a raw block IRQ through Google's `register_separated_msi_vector()`
  (`PC/pcie-exynos-rc.c:4856-4895`). Mainline's chained handlers own those
  SPIs, so the port runs pktproc with `use_exclusive_irq` off (all queues
  on the shared vectors) first.
- **The link API.** About 20 `exynos_pcie_*` calls (`CP/` grep): the ones
  that matter are `exynos_pcie_poweron(ch, speed, width)` (link_up + secure
  ATU + MSI re-arm + restore the endpoint's saved config),
  `exynos_pcie_poweroff(ch)` (link_down; the bus stays), `chk_link_status`,
  `set_msi_ctrl_addr` (check it equals the memory-region),
  `set_perst_gpio`, `l1ss_ctrl` (no-op at first), `register_event`
  (link-down callback from the "ctrl" IRQ 388, later). The rest are dump,
  recovery-state and BTL helpers that can be stubs. **M3.2**: export them
  from `pcie-gs201-cp` as `gs201_pcie_cp_*()` with a header, and give the
  CPIF port a small compat file that maps the `exynos_pcie_*` names.
- **The modem's lines.** Stock CPIF drives them itself from its own DT node
  (`CP/modem_ctrl_s5100.c:906-934`). M3.2 moves them from our `modem` child
  node to the CPIF node (an overlay), so there is one owner; our `cp_on` /
  `cp_off` steps stay for debugging without CPIF.
- **Shared memory.** `cp_rmem` (0xea400000, 8 MiB IPC) and `cp_rmem_1`
  (0xe8000000, 32 MiB packet rings) are reserved `no-map` already
  (`e7cb10fe5`); CPIF maps them itself. `cp_aoc_rmem` (0x197fd000, AoC
  SRAM, voice) is left out of the CPIF node: never mapped until the AoC
  voice path is designed (RADIOS-CAMERA-PLAN 1.5).
- **Left out of the port:** `LINK_DEVICE_PCIE_IOMMU` (Google's pcie
  sysmmu), `GS_S2MPU`, DIT, SPI boot, `CP_THERMAL`, BTL, logbuffer (stubbed),
  the AP-suspend-during-call path. CPIF must return errors where stock
  panics.
- **DMA.** Without the HSI1 SysMMU/S2MPU the modem can write anywhere in
  RAM once CPIF enables bus mastering. Unlike HSI2, HSI1's SysMMU serves
  only PCIe ch0 (`R/live.dts:12093-12105`), so confining it is possible:
  M3.6, after the modem boots, under the S2MPU rule (touch only CTRL0).

**Userspace (packaged 2026-10-13: `packages/omamobile-modem`, section 6):**
- `tools/extract-vendor-chroot -p modem`: `cbd`, `rfsd`, their libraries
  (`libjson`, `libz`, `libcutils`, `libutils`, `libcrypto`, `libc++`,
  `liblog`; no binder) and `cbd.rc`, `rfsd.rc`, `fstab.modem`; since
  2026-10-13 also `/system/bin/sh` and `toybox` with the commands cbd runs
  (`tar`, `timeout`, `gunzip`, `mkdir`, `chmod`, `rm`, `cp`, `mv`, and
  `/vendor/bin/tar`). Tested on the laptop against CP2A.260705.006 before
  that change (22 files, 7.9 MB); re-run it for M3.4.
  `ro.vendor.cbd.modem_type=s5100sit` comes from the vendor `build.prop`.
- `profiles/modem.conf` for `omamobile-vendor-chroot`, with
  `modem/props.conf`. At start it checks that the five NV/firmware
  partitions read `ro=1` and none of the six is mounted, reads `modem_a`,
  `efs`, `efs_backup`, `modem_userdata` and `persist` **into a tmpfs**,
  compares each copy with `/etc/omamobile/modem-nv.sha256` (the human
  copies the matching lines from the off-repo backup's `SHA256SUMS`; the
  phone keeps them, the repo never does) and stops on any mismatch. The
  chroot gets loop devices of the copies only: `modem_a` read-only at
  `by-name/modem_a` (and `by-name/modem`) and `/mnt/vendor/modem_img`, the
  three f2fs images read-write at `/mnt/vendor/{efs,efs_backup,modem_userdata}`,
  and a copy of `persist/modem`. Then, new: the three NV files must pass
  the stock salted checksum (MD5 of the file plus a fixed salt against the
  `.md5` beside it; rfsd crashes the CP on purpose if they don't), and
  `persist.vendor.modem.baseband.version` is set from the firmware's TOC.
  Then `rfsd` (no arguments) alone for 2 s, then **`cbd -t s5100sit -P
  by-name/modem_a -s 2 -o r` once, in the foreground**: without `-d` cbd
  boots the CP and exits; `-o r` keeps it uid 0 in the chroot. rfsd stays.
  Whatever the modem writes to NV is lost at stop.
- Properties (`modem/props.conf`): slot `_a`, `ro.bootmode=normal`,
  **`persist.vendor.modem.efs.clear.action=none`** (an empty value makes
  rfsd treat the start as a factory reset and clear the NV copy: the 0.0
  profile had it empty), `vendor.cbd.modem_bin_type=0`,
  `persist.radio.multisim.config=dsds`, recovery off, logging off. Per
  phone, never in the repo: `ro.boot.cdt_hwid` in
  `/var/lib/omamobile-vendor/modem/props.conf`.
- `CONFIG_F2FS_FS=m` in `kernel/configs/omamobile.config`.

**Stages:**

| Stage | What | Where | Effort | Risk |
|---|---|---|---|---|
| M3.1 | `bus` on the ROM link: enumerate, MSI domain, guarded config space | phone, runbook below | an hour | medium |
| M3.2 | `gs201_pcie_cp_*` API + compat names; lines handed to CPIF (overlay); "ctrl" IRQ for link-down | offline | **done 2026-10-12** (2.1) | none |
| M3.3 | CPIF port, in-tree modules (`L/drivers/soc/google/cpif/`): stage 1 (boot, IPC, RFS, legacy buffers; 18 C files, 13.6k lines) **builds, 2026-10-12** (2.1); then M3.3-B on the phone (bind only); pktproc later | offline + phone | stage 1 done; M3.3-B an hour | low-medium |
| M3.4 | Load the port with the line overlay; the modem profile with `OMAMOBILE_MODEM_STAGE=rfsd`, then `cbd`: BOOT image over PCIe at Gen1, main firmware at Gen3 x2, CP ONLINE | phone | 1-2 weeks of debugging (boot handshake, shared-memory layout, doorbell, MSI) | medium: the modem DMAs into reserved memory with no IOMMU |
| M3.5 | After every M3.4 run: the M0.1 checksums of the six partitions against the 20261012-radio backup | phone, read-only | minutes | none |
| M3.6 | HSI1 SysMMU confining the modem's DMA to its shared memory | offline, then phone | 1 week | medium |

M4 (registration, data, SMS, voice) uses `omamobile-modem-sit` 0.2.0, the
SIT RIL ported from a stack that did all four on this phone model (section
6; [MODEM-CLIENT.md](MODEM-CLIENT.md)). The protocol background is in
[MODEM-SIT-RESEARCH.md](MODEM-SIT-RESEARCH.md). Desktop front ends
(ModemManager, oFono) are still open: MODEM-CLIENT.md section 3.


**M2.5 result (2026-10-12, 7.3.0-rc6-omamobile-push1-00345-g606b84c7a9fd, int
with omamobile-modem 1344a9e0b; overlays incl. `modem-link-test`): power-off
of the modem disturbs UFS every time; the rest is clean.**
- M2.5.0: four "watching cp2ap-... (now 0)", "steps enabled, modem lines here".
- M2.5.1 baseline, 60 s of `dd` reads with the modem off: err_handler count 0,
  every UFS stats counter 0.
- M2.5.2 (powered, no link, 60 s under load): `cp2ap-wakeup -> 1` 18 ms after
  "modem power-on sequence"; **no** event at +20 s (the M2 event at 21 s did
  not repeat); no UFS error while powered. 0.15 s after "modem power-off
  sequence": `ufshcd_err_handler` (saved_err 0x4, saved_uic_err 0x40), back
  to operational; stats then PHY Adapter 6, Data Link 20518.
- M2.5.3 (stock timing): "link up: Gen1 x1 (target Gen1), try 1" 0.28 s after
  power-on; 60 s up under load with no link-down and no UFS error; at
  link_down + cp_off: **"PHY isolated (PMU 0x3ec0 = 0x0)"** (the M2.4 fix
  works), status PMU 0x0, perst 1, "faults: 0x0, ctrl irq off". 0.08 s after
  the power-off sequence: the same UFS handler pass (+3 PHY Adapter, +5540
  Data Link).
- In every case: no I/O error, no ext4 error, Host Resets 0, SCSI aborts 0,
  Logical Unit Resets 0.
- **Conclusion:** the modem's power-off sequence (not power-on, not a running
  link) disturbs the UFS link, as the agent's analysis suspected (the
  modem's own supplies collapsing; stock powers the modem off only at
  shutdown). The modem stack must keep the modem on once it's up and avoid
  power cycles; investigate the power-off ordering (PDA_ACTIVE, PM/CP reset
  lines, a delay) and whether quiescing UFS around a power-off is needed.

**M3.1 result (same boot): passed.** ASPM policy set to `performance`. One
command did power-on, link, ATU, ID and bus scan: "bridge configuration
invalid ... reconfiguring" (normal for a fresh bus), then `0001:00:00.0
144d:ecec` (root port) and `0001:01:00.0 [144d:a5a5] type 00 class 0x000000
PCIe Endpoint`, BARs 0 and 2-5 sized 1 MiB (unassigned: CPIF assigns them),
ROM 64 KiB, "ASPM: default states L1"; LTSSM 0x11, "faults: 0x0, ctrl irq
on". No driver bound to the endpoint (and none to the root port).
`link_down` + `cp_off`: config space read `ffffffff` (no hang), PMU 0x3ec0
0x0, "state: cp 0, phy 0/0, link 0, atu 0", "faults: 0x0, ctrl irq off",
no link-down event. The power-off again gave one recovered UFS handler pass.
`rmmod pcie_gs201_cp` removed domain 0001. UFS totals after M2.5 and M3.1:
PHY Adapter 12, Data Link 76021, no resets or aborts, no I/O errors.
Next: M3.3-B (bind only) needs a boot with `modem-cpif-test` instead of
`modem-link-test`.

#### M3.1: the bus on the ROM link (after M2.5, same boot or the next)

**Kernel:** int with `omamobile-modem` at the M3.2 head (section 2.1) or
at `3a8f4c503`; overlays as M2.5 (`modem-link-test`, never
`modem-cpif-test`). **Risk: medium.** The first enumeration through the
secure monitor's config window, and the first root-port services
(`pcieport`: AER, PME, bandwidth notification) on this controller. ASPM is
set to `performance` first so the core does not put the ROM's link into L1
while we look. Nothing binds to the endpoint, so its bus mastering stays
off. **Modem power:** about 30 s, attended, under a 90 s dead-man; the
power-on and the bus scan are one command so the ROM never waits for a
link (the M2 analysis).

Keep the kmsg stream from M2.5 running (`tools/phone-ssh dmesg -w | tee logs/m3.1-kmsg.log`).

```sh
# M3.1.0 read-only: ASPM policy, then load (no hardware access)
tools/phone-ssh 'cat /sys/module/pcie_aspm/parameters/policy; echo performance > /sys/module/pcie_aspm/parameters/policy;
  lsmod | grep -c pcie_gs201_cp || modprobe pcie-gs201-cp allow_hw=1 watch_lines=1;
  dmesg | grep -c ufshcd_err_handler; cat /sys/kernel/debug/gs201-pcie-cp/status | grep -E "PMU|state|faults"'
#   expect: "PMU 0x3ec0: 0x0", "state: cp 0, phy 0/0, link 0, atu 0", "faults: 0x0, ctrl irq off"
#   record: the err_handler count

# M3.1.1 dead-man, then power-on, link, ATU, bus in one go
tools/phone-ssh 'systemd-run --unit=x-modem-off --on-active=90 sh -c "C=/sys/kernel/debug/gs201-pcie-cp/ctl; echo link_down > \$C; echo cp_off > \$C"'
tools/phone-ssh 'C=/sys/kernel/debug/gs201-pcie-cp/ctl; echo cp_on > $C; sleep 0.2; echo link_up > $C &&
  echo atu > $C && echo id > $C && echo bus > $C; dmesg | grep -E "pcie-cp|11920000|pcieport|144d" | tail -20;
  cat /sys/kernel/debug/gs201-pcie-cp/status | grep -E "LTSSM|faults"'
#   pass: "link up: Gen1 x1"; "MSI: 160 vectors, target 0x00000000f6200000"
#   (from `000a39ed3`: "MSI: 32 vectors, target 0x00000000f6200000, 4 queue blocks");
#   "<dom>:00:00.0 144d:ecec class 060400" and "<dom>:01:00.0 144d:a5a5 class ..." (dom 0001 or the next free);
#   M3.2 head: "faults: 0x0, ctrl irq on", LTSSM 0x11

# M3.1.2 read-only look at the bus (same power window)
tools/phone-ssh 'for d in /sys/bus/pci/devices/*; do echo "$d $(cat $d/vendor):$(cat $d/device)"; done;
  E=$(grep -l 0xa5a5 /sys/bus/pci/devices/*/device | head -1 | xargs dirname);
  cat $E/resource | head -2; grep -E "PCI-MSI|pcie" /proc/interrupts'
#   pass: BAR0 of the endpoint inside 0x40000000-0x40feffff (or unassigned: CPIF sets it itself);
#   the root port's MSI vectors listed (pcieport); no driver bound to the a5a5 function

# M3.1.3 link down with the bus kept: config space must read as absent, not hang; then power off
tools/phone-ssh 'C=/sys/kernel/debug/gs201-pcie-cp/ctl; E=$(grep -l 0xa5a5 /sys/bus/pci/devices/*/device | head -1 | xargs dirname);
  echo link_down > $C; echo cp_off > $C; od -An -tx4 -N4 $E/config; cat /sys/kernel/debug/gs201-pcie-cp/status;
  systemctl stop x-modem-off.timer'
#   pass: ffffffff; PMU 0x3ec0: 0x0; outputs 0; "state: cp 0, phy 0/0, link 0, atu 0";
#   M3.2 head: "faults: 0x0, ctrl irq off" (a link-down event logged at link_down would be a bug: report it)

# M3.1.4 unload (the bus goes with the module)
tools/phone-ssh 'rmmod pcie_gs201_cp; ls /sys/bus/pci/devices; dmesg | grep -c ufshcd_err_handler'
#   pass: the modem's domain is gone; the err_handler count as in M3.1.0
```

**Stop:** `bus` does not return, or the phone resets (the watchdog): the
config window or DBI path is wrong; send `logs/m3.1-kmsg.log`. "no L0":
as M2.2 (`link_down`, `cp_off`, analyse). A "link down" or "completion
timeout" line while the link should be up: power off (`link_down`,
`cp_off`) and send the log. Any UFS message beyond a recovered error
handler: as M2.5.
**Rollback:** `link_down`, `cp_off`, `systemctl stop x-modem-off.timer`,
`rmmod pcie_gs201_cp`; reboot clears the ASPM policy. If the phone stops
answering, wait for the watchdog (or the dead-man) and ask the human; send
no more commands.

#### M3.3-B: bind CPIF, no firmware, no modem power

**What it proves:** the port probes on the phone: `shm_ipc` finds and maps
the three regions, CPIF parses its node, takes the eleven lines from the
modem node, registers its interrupts and creates its devices, and the
link driver hands over the lines. CPIF requests the cp2ap interrupts
only once the modem has booted (`complete_normal_boot()`), so none are
requested here. **Nothing powers the modem:**
`pcie-gs201-cp` is loaded *without* `allow_hw`, so the link API refuses
`poweron` (and the debugfs steps); CPIF powers the modem only when `cbd`
asks (`IOCTL_POWER_ON`/`BOOT`), and nothing here opens its devices. The NV
and firmware partitions are not involved at all (no `cbd`, no `rfsd`, no
chroot).

**Before:** M2.5 and M3.1 passed (M3.1 proves the bus that CPIF will scan
in M3.4). Int with `omamobile-modem` at the M3.2 head, built, and
`modules-<release>.tar.zst` pushed with the images (CPIF is new). **Risk:
low-medium**: first probe of a large vendor driver (13.6k lines), which
maps 8 MiB of reserved memory (`memremap()` of no-map RAM) and takes the
eleven lines. Binding drives the ap2cp outputs low; M0.4 found them low
already. CPIF cannot be unloaded once loaded (no `remove()`): undo by
reboot.

```sh
# M3.3-B.0 blacklist first (AGENTS: before the DTB that enables the node).
# Same package version, reinstalled with the new omamobile-cpif.conf:
tools/phone-install-package packages/omamobile-device-cheetah
tools/phone-ssh 'modprobe -c | grep -E "^blacklist (cpif|shm_ipc|pcie_gs201_cp)$"; ls /etc/modprobe.d/'
#   pass: the three blacklist lines; no omamobile-*.conf copies in /etc/modprobe.d
# M0.1-style checksums of the six partitions against the 20261012-radio backup (read-only)
#   pass: all match (M0 result); if a stock boot happened since, take a fresh backup first (AGENTS)

# M3.3-B.1 boot the overlay (asks the human: reboots)
ov gnss-pmic-test gnss-test aoc-boot-test modem-cpif-test && bin/omamobile push
tools/phone-ssh 'uname -r; lsmod | grep -E "^(cpif|shm_ipc|pcie_gs201_cp) " ; ls /dev/umts_* 2>&1 | head -2;
  cat /sys/kernel/debug/gpio | grep -E "gph0-[23]|gph1-[1236]|gpa0-[23]|gpa8-[234]"'
#   pass: none of the three modules loaded; no /dev/umts_*; the eleven lines as M0.3/M0.4 (no owner)

# second terminal for the rest:
tools/phone-ssh dmesg -w | tee logs/m3.3b-kmsg.log

# M3.3-B.2 link driver without hardware access
tools/phone-ssh 'modprobe pcie-gs201-cp; dmesg | grep pcie-cp | tail -2; cat /sys/kernel/debug/gs201-pcie-cp/status'
#   pass: "steps disabled (allow_hw=0), modem lines left to the modem driver";
#   status: "modem lines: owned by the modem driver", "PMU 0x3ec0: 0x0", "state: cp 0, phy 0/0, link 0, atu 0",
#   "faults: 0x0, ctrl irq off"

# M3.3-B.3 the regions
tools/phone-ssh 'modprobe shm_ipc; dmesg | grep -iE "rmem|shmem|cp_shmem" | tail -12'
#   pass: "rmem 0 cp-rmem@ea400000 0xea400000 0x00800000", "rmem 1 cp-msi@f6200000 0xf6200000 0x00001000",
#   "rmem 2 cp-rmem1@e8000000 0xe8000000 0x02000000", then the four regions; no "failed"

# M3.3-B.4 CPIF
tools/phone-ssh 'modprobe cpif; dmesg | grep -iE "cpif|cp_interface|s5100|s51xx|mif|xxx" | tail -40'
#   pass: the probe ends without "xxx" (CPIF's failure marker) and without an Oops;
#   "num_iodevs:52"; "PCIe Channel Number:0"; no "Failed to vmap"/"Failed to map"; no "poweron" line
tools/phone-ssh 'ls /dev/umts_*; ls /sys/class/net | grep -c rmnet; grep -ciE "cp2ap|phone_active" /proc/interrupts;
  cat /sys/kernel/debug/gpio | grep -E "AP2CP|CP2AP"; cat /sys/kernel/debug/gs201-pcie-cp/status | grep -E "PMU|state|faults";
  grep "^cpif " /proc/modules; dmesg | grep -c ufshcd_err_handler'
#   pass: /dev/umts_boot0, umts_ipc0, umts_ipc1, umts_rfs0 (and the other iodevs); 30 rmnet devices;
#   0 cp2ap interrupts (requested only after a boot); every AP2CP_* line "out lo", CP2AP_* "in";
#   link status unchanged (PMU 0x0, state all 0); /proc/modules shows cpif "[permanent]";
#   err_handler count unchanged

# M3.3-B.5 nothing changes on its own: wait 60 s, look again
tools/phone-ssh 'sleep 60; cat /sys/kernel/debug/gpio | grep -E "AP2CP|CP2AP"; dmesg | tail -5'
#   pass: AP2CP lines still low, CP2AP inputs low (the modem is unpowered); no new CPIF lines
```

**Record** in this plan: the date, `uname -r`, the probe log lines (no
addresses beyond the region bases above), the `/dev/umts_*` list.
**Stop** (and reboot, never `rmmod cpif`): an Oops or a panic; any
`AP2CP_*` line high, or `ap2cp-cp-pwr-on`/`nreset` driven; "PMU 0x3ec0"
not 0x0; a "poweron" or "link up" line (the `allow_hw` gate failed: report
it, it must not happen); a CP2AP input high while the modem is unpowered
(a floating line: compare gpa8-3's `PUD` with stock's pull-down, section
2.1); anything from UFS beyond the M2.5 baseline.
**Rollback:** reboot (`reboot-to omamobile`); CPIF's reboot handler only
sets a flag, and its shutdown runs the power-off line sequence on an
already unpowered modem. Then images without `modem-cpif-test`: `cp
"$D.default" "$D"; bin/omamobile images && bin/omamobile push`.
**Next:** M3.4 below, on a fresh boot (`allow_hw` is fixed at load time,
and CPIF can't be unloaded): the modem was never powered in M3.3-B, so
that reboot costs no UFS event.


**M3.3-B result (2026-10-12, 7.3.0-rc6-omamobile-push1-00349-g781b9c3d8523,
int with omamobile-modem 781b9c3d8; overlays incl. `modem-cpif-test`;
unattended): passed.** Before: none of the three modules loaded, no
`/dev/umts_*`, err_handler count 0. `modprobe pcie-gs201-cp` (no
`allow_hw`): "steps disabled (allow_hw=0), modem lines left to the modem
driver"; status "modem lines: owned by the modem driver", PMU 0x3ec0 0x0,
"state: cp 0, phy 0/0, link 0, atu 0", "faults: 0x0, ctrl irq off".
`modprobe shm_ipc`: rmem 1 cp-msi@f6200000 0x1000, rmem 2 cp-rmem1@e8000000
0x2000000, then IPC 0xea400000 0x800000, PKTPROC 0xe8000000 0x1c00000,
PKTPROC_UL 0xe9c00000 0x400000, MSI 0xf6200000 0x1000. `modprobe cpif`
rc 0: "num_iodevs:52", "PCIe Channel Number:0", no failure marker, no Oops,
no map failure, no power-on. Devices: umts_boot0, dm0, ipc0, ipc1,
loopback, rcs0/1, rfs0, router, toe0, wfc0/1; 30 rmnet interfaces; 0 cp2ap
interrupts requested; link state unchanged; `cpif ... [permanent]`; UFS
err_handler count still 0. M3.4 (the first firmware boot) waits for the
human.

#### M3.4: boot the S5300 firmware from a RAM copy, and leave it on

**What it does:** `omamobile-modem.service` loads the CPIF modules and runs
the modem vendor chroot (`packages/omamobile-modem`): RAM copies of
`modem_a`, `efs`, `efs_backup`, `modem_userdata` and `persist/modem`, each
checked against the human's off-repo backup and the three NV files against
their stock checksum before any daemon runs; then `rfsd`, then `cbd` once.
cbd powers the modem through CPIF, trains the link at Gen1, hands the ROM
the BOOT image over PCIe (`/dev/umts_boot0`), then the main firmware at
Gen3, and the CP reaches ONLINE with rfsd serving NV from the copies; cbd
exits, rfsd stays. The radio stays off (no SIT client runs). **The modem is
left on at the end**, until the next reboot: every power-off costs a UFS
error-handler pass (M2.5/M2.6).

**Order and stop, as on the working stack (section 6.1):** rfsd before cbd;
the CP off before rfsd stops. The unit's stop does the second
(`omamobile-modem-cp power-off`, which sets CPIF's `allow_poweroff` for
that one request), so `systemctl stop omamobile-modem` and every reboot
power the CP off: one UFS handler pass each. Restarting the unit is a CP
power cycle: don't.

**Never:** a real NV or firmware partition in the chroot, a write to one,
`rmmod cpif`, restarting the modem unit or cbd, `-d` on cbd (it would stay
and power-cycle the CP on a crash), killing rfsd while the CP runs.

**What cbd needs, read from the binaries (2026-10-12):** `/dev/umts_boot0`,
`/dev/block/by-name/modem` and `modem_a` (both bound to the RAM copy),
`/mnt/vendor/modem_img/images/default/...` (the image's ext4),
`/mnt/vendor/efs/nv_*.bin` (the RAM copy: cbd writes NV files there),
`/sys/devices/platform/cpif/sim/ds_detect`,
`/sys/firmware/devicetree/base/chosen/{plat,config}` (bound read-only if
the bootloader put them in our DTB; the profile says so if not),
`/sys/power/wake_lock` (a stand-in: no `CONFIG_PM_WAKELOCKS`), and the
properties `ro.boot.cdt_hwid` / `persist.vendor.modem.cdt_hwid` (the
board's hardware id; without them cbd falls back to the default hardware
config). rfsd needs `/dev/umts_rfs0`, `/mnt/vendor/efs*` and the
firmware file (`vendor.modem.bin.path`, below: "What rfsd does at start"). cbd can ask the kernel to panic
(`IOCTL_TRIGGER_KERNEL_PANIC`): the port only logs it.

**UFS check, after every step from M3.4.2 on:**
`tools/phone-ssh 'dmesg | grep -c ufshcd_err_handler; grep -E "Host Resets|SCSI command aborts|Logical Unit" /sys/kernel/debug/ufshcd/14700000.ufs/stats'`
against the count before it. Expected: unchanged, except exactly one
recovered pass after each modem **power-off** (reboot, unit stop).
**Stop** on anything beyond that: an I/O or ext4 error, resets or aborts
going up, or a handler pass while the modem is up and not changing power.

**Before (offline / laptop; risk: none):**
1. M2.6 recorded (its table decides whether `link_down` alone disturbs
   UFS: CPIF takes the link down between the BOOT and main stages and when
   the modem idles), or the human waives it.
2. Kernel: int with `omamobile-modem` at `781b9c3d8` or later, built, the
   modules tarball pushed with the images; overlay `modem-cpif-test`
   (M3.3-B passed on it). With `23e3d01c4` (section 6.3) and the
   2026-10-13 config fragment: the channel extension is on, the packet
   processor is built but stays off without `modem-cpif-pktproc`, and the
   link waits for training to end after the first L0.
   **For M3.4.5b: `7d9c1c3a4` or later** (the probe fixes below).
3. The modem chroot image, from the user's own factory image, **re-run
   with the 2026-10-13 tool** (it adds the shell and toybox), never
   committed: `tools/extract-vendor-chroot -p modem -o
   ~/android/vendor-chroot-work/modem <image-cheetah-...zip>`. Check
   `grep -c 'system/bin/toybox' ~/android/vendor-chroot-work/modem/MANIFEST` = 1.
4. Packages: `packages/omamobile-modem/test/all` and
   `packages/omamobile-modem-sit/test/all` pass.
5. The checksum file for the phone, from the newest off-repo backup: only
   the five lines the profile reads, never committed:
   `grep -E ' (modem_a|efs|efs_backup|modem_userdata|persist)\.img$' <newest backup>/SHA256SUMS > /tmp/modem-nv.sha256`
6. Per-phone property (optional, recommended): `ro.boot.cdt_hwid` from
   this phone's private stock getprop capture, for
   `/var/lib/omamobile-vendor/modem/props.conf` as
   `ro.boot.cdt_hwid=<value>` and `persist.vendor.modem.cdt_hwid=<value>`.
   Never in the repo, never in a log excerpt.

```sh
# M3.4.0 M0.1: the six partitions against the newest backup, ro, unmounted (read-only; risk: none)
tools/phone-ssh 'for p in efs efs_backup modem_userdata persist modem_a modem_b; do
  d=$(grep -lx "PARTNAME=$p" /sys/class/block/*/uevent | head -1 | cut -d/ -f5);
  echo "$(sha256sum < /dev/$d | cut -d" " -f1)  $p.img ro=$(cat /sys/class/block/$d/ro) mounted=$(grep -c "^/dev/$d " /proc/mounts)"; done' > logs/m3.4-before.sha256
grep -E ' (efs|efs_backup|modem_userdata|persist|modem_a|modem_b)\.img$' <newest backup>/SHA256SUMS | sort -k2 |
  diff - <(sed 's/ ro=.*//' logs/m3.4-before.sha256 | sort -k2); grep -c 'ro=1 mounted=0' logs/m3.4-before.sha256
#   expect/pass: no diff; 5 (persist is the writable one; the profile only reads it); every mounted=0
#   stop: any mismatch: a stock boot changed NV. Take a fresh read-only backup first (AGENTS), then redo 5. above
#   rollback: nothing changed

# M3.4.1 install, enable nothing (writes /usr/lib, /etc; asks the human; risk: none)
tools/phone-install-package packages/omamobile-modem
tar -C ~/android/vendor-chroot-work/modem -cf - root MANIFEST SOURCE STUBS |
  tools/phone-ssh 'rm -rf /usr/lib/omamobile-vendor/modem/root && mkdir -p /usr/lib/omamobile-vendor/modem &&
    tar --no-same-owner -C /usr/lib/omamobile-vendor/modem -xf -'
tools/phone-ssh 'install -Dm600 /dev/stdin /etc/omamobile/modem-nv.sha256' < /tmp/modem-nv.sha256; rm /tmp/modem-nv.sha256
# the bring-up copy of the M0.5 rule is now the package's (AGENTS: a file in /etc shadows the package's)
tools/phone-ssh 'cmp /etc/udev/rules.d/60-omamobile-modem-nv-ro.rules /usr/lib/udev/rules.d/60-omamobile-modem-nv-ro.rules;
  rm -f /etc/udev/rules.d/60-omamobile-modem-nv-ro.rules; udevadm control --reload'
tools/phone-ssh 'pacman -Q omamobile-modem; systemctl is-enabled omamobile-modem; cat /usr/lib/omamobile-vendor/modem/SOURCE;
  wc -l < /etc/omamobile/modem-nv.sha256; ls -l /etc/modprobe.d/'
#   expect/pass: omamobile-modem 0.1.1; "disabled"; the CP2A source line; 5; no omamobile-*.conf
#   bring-up copies in /etc/modprobe.d (cmp may differ only in comments: the package's rule wins)
#   stop: the package's check fails; rollback: pacman -R omamobile-modem

# M3.4.2 boot with the CPIF overlay (as M3.3-B.1; asks the human: reboots; risk: low)
ov gnss-pmic-test gnss-test aoc-boot-test modem-cpif-test && bin/omamobile push
tools/phone-ssh 'uname -r; lsmod | grep -cE "^(cpif|shm_ipc|pcie_gs201_cp) "; dmesg | grep -c ufshcd_err_handler;
  for p in efs efs_backup modem_userdata modem_a modem_b; do
    d=$(grep -lx "PARTNAME=$p" /sys/class/block/*/uevent | head -1 | cut -d/ -f5); printf "%s ro=%s\n" $p $(cat /sys/class/block/$d/ro); done'
#   expect/pass: the int release; 0 modules; err_handler 0; all five ro=1 (now from the package's rule)
#   stop: a module loaded (the blacklist failed) or ro=0; rollback: images without modem-cpif-test

# second terminal, until the end of M4:
tools/phone-ssh dmesg -w | tee logs/m3.4-kmsg.log

# M3.4.3 modules and preconditions, no modem power (risk: low; as M3.3-B.2-B.4 but allow_hw=1)
tools/phone-ssh 'modprobe pcie-gs201-cp allow_hw=1; modprobe shm_ipc; modprobe cpif trace_lines=1;
  cat /sys/module/cpif/parameters/allow_poweroff; cat /sys/devices/platform/cpif/modem_state;
  /usr/lib/omamobile-vendor/omamobile-vendor-chroot modem check;
  cat /sys/kernel/debug/gs201-pcie-cp/status | grep -E "PMU|state|faults"'
#   expect/pass: "steps enabled"; allow_poweroff N; modem_state OFFLINE; "check" ends with
#   "preconditions met"; PMU 0x3ec0 0x0, "state: cp 0", "faults: 0x0, ctrl irq off"
#   stop: a "poweron"/"link up" line (nothing may power the modem yet); rollback: reboot (cpif is permanent)

# M3.4.4 rfsd only: the RAM copies, the NV checksums, the chroot; no modem power (risk: low)
tools/phone-ssh 'systemd-run --unit=x-modem-rfsd -E OMAMOBILE_MODEM_STAGE=rfsd \
  /usr/lib/omamobile-vendor/omamobile-vendor-chroot modem start; sleep 25;
  journalctl -u x-modem-rfsd --no-pager | tail -50; cat /sys/devices/platform/cpif/modem_state'
#   expect: "<part>: RAM copy matches the backup" for modem_a, efs, efs_backup, modem_userdata, persist;
#   "nv_normal.bin: stock checksum matches" and the same for nv_protected.bin, nv_protected.bak;
#   "baseband version <...>" (record it); "starting rfsd"; "running"; modem_state OFFLINE; AP2CP lines low
#   pass: all of that; no "no /chosen/..." warning (record it if there is one); and from rfsd
#     (0.1.1, "What rfsd does at start" below), in this order:
#     "Modem Path : /mnt/vendor/modem_img/images/default/modem.bin" (not by-name/modem_a), ReadToc,
#     CheckNvFiles, CleanupAllRfsFiles, then NO "TOC not found" and NO "Bypass radio versions"
#     (matching versions log nothing), "[RfsService::Nv] Touch", "[RfsService::Nv] <file> : Verified" (no
#     "Expand", no "Create"), NvProtected likewise without an error line, Init, IoChannel Open;
#     then "Modem boot timeout" every few seconds is expected (no CP yet)
#   stop: "differs from the backup" or "stock checksum does not match": the profile stops before rfsd.
#     Never "fix" a checksum. Take a fresh backup and compare (the NV may have changed under stock)
#   stop: "vendor.modem.bin.path ... is not a file" or "baseband ... differs": the profile stops before
#     rfsd (a per-phone baseband value must go, or match the firmware)
#   stop, never go on to M3.4.5: "Radio version changed", "Going to clear EFS", "EFS ... cleared",
#     "File ... smaller ... Expand", "Create ... Size", "TOC record is broken", "Failed to touch":
#     rfsd changed or would change the NV copies (RAM only; record the lines, names only)
tools/phone-ssh 'systemctl stop x-modem-rfsd; sleep 2; losetup -l | grep -c modem-nv; grep -c modem-nv /proc/mounts'
#   pass: 0 and 0 (the namespace took the copies with it); the CP was never powered, so no UFS event

# M3.4.5 THE FIRST BOOT (announce: the modem powers on and stays on; risk: medium-high)
#   dead-man first: if the session dies, the modem must not stay half-booted for long
tools/phone-ssh 'systemd-run --unit=x-modem-deadman --on-active=300 systemctl stop omamobile-modem'
tools/phone-ssh 'dmesg | grep -c ufshcd_err_handler; systemctl start --no-block omamobile-modem; sleep 60;
  /usr/lib/omamobile-vendor/omamobile-modem-cp state; cat /sys/devices/platform/cpif/modem_state;
  journalctl -u omamobile-modem --no-pager | tail -40; ls /var/lib/omamobile/modem-bringup-started 2>&1;
  cat /sys/kernel/debug/gs201-pcie-cp/status | grep -E "LTSSM|faults"; dmesg | grep -c ufshcd_err_handler'
#   expect, in this order in the kmsg terminal (about 10-30 s):
#   - "IOCTL_POWER_ON", the traced power-on edges (pm-wrst, pwr-on, nreset, cp-wrst = 1);
#   - "link up: Gen1 x1", "secure ATU SMC: 0x0", 0001:01:00.0 144d:a5a5, the s51xx probe
#     (from `d1fe3981d`: "doorbell: BAR0 [mem ...] (bus 0x14e00000, ...) + 0x60000"), 4 MSI vectors;
#   - cbd's boot steps ([cbd] lines in the journal), a link_down, "link up: Gen3 x2" (main firmware);
#   - CPIF "ONLINE"; the journal: "CP ONLINE (cbd exit 0)", "omamobile-modem-cp: CP ONLINE"
#   pass: state ONLINE; the marker file is gone; "faults: 0x0"; err_handler count unchanged
#     (power-on and a running link were clean in M2.5); rfsd logs NV file requests (names only),
#     its ModemStateMonitor sees the CP online, and none of M3.4.4's rfsd stop lines appears
#     (cbd publishes vendor.modem.bin.path too: the same path, so nothing changes for rfsd)
#   record: Gen/width of the main link, the time from POWER_ON to ONLINE, cbd's last lines,
#     the "capability part:0 AP:0x..." line (from `907f73727` with CONFIG_CH_EXTENSION:
#     0x00000002; 0x00000003 with modem-cpif-pktproc, the uplink processor; section 6.3)
tools/phone-ssh 'systemctl stop x-modem-deadman.timer'     # only once ONLINE was seen
#   stop (record, then reboot-to omamobile; expect one UFS pass at the power-off):
#   - an Oops, a panic line, the watchdog;
#   - "BAR0 ... not assigned: no doorbell" or "doorbell ... outside BAR0" (the s51xx probe refused;
#     from `7d9c1c3a4` cbd's attempt then fails at once with "no PCIe endpoint for the ROM boot");
#   - the journal says "not ONLINE. Leaving it for diagnosis": collect `journalctl -u omamobile-modem`,
#     the kmsg log and `/usr/lib/omamobile-vendor/omamobile-modem-cp state`, then reboot. The marker
#     stays, so the next boot skips the modem until `omamobile-modem-start --retry`. Section 6.2
#     lists what to try next, one change per boot;
#   - repeated "link down" or "completion timeout" events;
#   - a CRASH state: the watcher has written /var/log/omamobile/modem-crashes.log (root-only, never
#     quoted without checking it for identifiers); reboot;
#   - UFS beyond the expectation above.
#   rollback: reboot (the unit's stop powers the CP off before rfsd). For a boot without CPIF: images
#   without modem-cpif-test (`cp "$D.default" "$D"; bin/omamobile images && bin/omamobile push`)

# M3.4.6 leave it on for 10 minutes (read-only; risk: low)
tools/phone-ssh 'sleep 600; /usr/lib/omamobile-vendor/omamobile-modem-cp state; dmesg | grep -cE "link down|completion timeout";
  dmesg | grep -c ufshcd_err_handler; test -e /run/omamobile-modem/crashed && cat /run/omamobile-modem/crashed'
#   pass: still ONLINE; 0 link faults (CPIF may cycle the link when the modem idles: record each
#   link_down/link up pair and the UFS count around it); err_handler unchanged; no crashed file
```

**M3.4.4, first run (2026-10-13, `7.3.0-rc6-omamobile-push1-00407`,
`omamobile-modem` 0.1.0):** all five RAM copies matched the backup, the
three stock NV checksums matched, baseband version
`g5300q-260317-260505-B-15346003`, "starting rfsd", "running", modem
OFFLINE; the copies were gone after the stop. rfsd logged, besides the
expected lines: "Modem Path : /dev/block/by-name/modem_a", "TOC not found,
g5300q-...", "Bypass radio versions comparing as empty", "AllocFile,
idx=1", "[RfsService::Nv] Touch", "TOC record is broken", "Failed to
touch normal registry file", then Init and the state monitor waiting. Also
noise, harmless: the launcher's glibc complaining that it can't preload the
Android shim, and the Android linker's missing `ld.config.txt`.

**What rfsd does at start (from the user's own `rfsd`, read offline
2026-10-13; behaviour only):**
- *Which file is the "TOC" read from:* rfsd waits up to about 5 s
  (51 polls, 100 ms) for `vendor.modem.bin.path`; if that stays empty it
  falls back to `/dev/block/by-name/modem` plus `ro.boot.slot_suffix`. It
  reads the first 512 bytes of that file as the firmware's table of
  contents: 32-byte entries, entry 0 named `TOC` whose last word is the
  index of the last entry; `NV_NORM` and `NV_PROT` give the NV file sizes
  (both 512 KiB in this firmware), `INFO` (or `GVERSION`) the version
  string. On stock, cbd publishes `vendor.modem.bin.path` (the
  `modem.bin` it finds in `/mnt/vendor/modem_img/images/default/`, or a
  gunzipped copy in `/data/vendor/radio/image/`), and rfsd, started next to
  it, picks it up within the wait. The raw `modem_a` partition is an ext4
  image whose first 512 bytes double as a tar header named after the
  version: that string is what "TOC not found, %s" printed. So the M3.4.4
  bind of `by-name/modem_a` was correct and readable; it is just not what
  rfsd wants once the path property is missing (no cbd ran in M3.4.4). The
  working stack (section 6.1) sets the property itself.
- *CheckNvFiles / CleanupAllRfsFiles:* the NV list is `nv_normal.bin`
  and `nv_protected.bin` under `vendor.ril.exynos.nvpath` (default
  `/mnt/vendor/efs/`). If any is missing: nothing is deleted
  (`efs.clear.action` set to `cleared`). Else by
  `persist.vendor.modem.efs.clear.action`: empty is the factory-reset
  case and `needed` a forced clear, **both delete the NV files**; any other
  value (`none`) goes to the version check: with no TOC version, "Bypass
  radio versions comparing as empty" and nothing is deleted (M3.4.4); with
  one, it is compared with `persist.vendor.modem.baseband.version`: equal,
  nothing is logged or deleted and the property is set to `none`;
  different, "Radio version changed", then unless `vendor.cbd.modem_bin_type`
  is 1, "Going to clear EFS for image changed case" and **both NV files
  are deleted** (in our layout: from the RAM copy; the real partitions
  are never visible). So `none` alone doesn't protect NV: the baseband
  property must equal the TOC's string, which `omamobile-modem-cp
  baseband-version` now reads exactly as rfsd does, and the profile stops
  if it can't or if a per-phone value differs.
- *Touch ("registry file"):* the "normal registry file" is
  `nv_normal.bin`, the protected one `nv_protected.bin`. Touch needs the
  TOC: without it, "TOC record is broken" and it returns before opening
  anything (no write; the protected file isn't tried). With it, it checks
  the file's stored checksum ("Verified"), creates a zero-filled file of
  the TOC size if the file is missing, and pads it to the TOC size if it is
  smaller ("Expand"): stock files should already be 512 KiB, so neither
  should happen.
- *Verdict on the first run:* no NV was changed (the bypass and the failed
  Touch both write nothing), and the copies were discarded at the stop.
  But booting the CP with an rfsd that has no TOC is untested and unlike
  both stock and the working stack, and once cbd published the path in
  M3.4.5, whether rfsd saw it would have been a race (cbd starts 2 s
  after rfsd; rfsd stops waiting at about 5 s). `omamobile-modem` 0.1.1
  sets `vendor.modem.bin.path=/mnt/vendor/modem_img/images/default/modem.bin`
  in `props.conf`, so rfsd reads the real TOC from the first second, and
  checks the baseband property against the same file before any daemon
  runs. **Repeat M3.4.1 (install 0.1.1) and M3.4.4 with the new
  expectations before M3.4.5.**

**M3.4.5, first run (2026-10-13, `7.3.0-rc6-omamobile-push1-00407-g618475741fa7`,
overlay `modem-cpif-test`, `omamobile-modem` 0.1.1; logs `logs/m3.4.5-*`,
private): FAILED, recovered by a clean reboot; M3.5 unchanged.**
- cbd: the stage table from the real TOC, "CDT property invalid" (no
  per-phone `cdt_hwid`, optional), "Power on CP", "Load CP bootloader",
  "xmit bootloader complete!", "Start CP bootloader", then "ERR!
  IOCTL_START_CP_BOOTLOADER fail", "start boot fail". cbd then powered the
  CP on again by itself, every ~5.5 s: **15 power-ons** until its timeout
  (exit 124); the unit: "CP is BOOTING: not ONLINE".
- Kernel, first attempt: IOCTL_POWER_ON, "link up: Gen1 x1", then the PCI
  core's "removing 2.5GT/s downstream link speed restriction" on the root
  port; the root port read **class 0x000000** and the modem 144d:a5a5
  **class 0x000000** with a 1 MiB 64-bit BAR0 and 1 MiB BARs 2-5. The core
  sizes and assigns nothing for class 0, so the root port's window stayed
  `[mem 0x00000000 disabled]`. The s51xx probe's stock "Disable BAR
  resources" loop then failed every BAR ("can't assign; no space"), and our
  bridge-window check refused to map the doorbell ("doorbell base 0x0 +
  0x60000 outside the bridge window"): no s51xx device, so the ROM was never
  given its boot image address and `boot_stage` stayed 0 for 200 polls.
- Every later attempt: "Driver 's51xx' is already registered, aborting...",
  `pci_register_driver() failed, rc:-16`: the failed first probe left the
  driver registered, and register_pcie() registers it on each power-on.
  The error was ignored and boot_stage polled for 5 s each time.
- Correctable AER (RxErr, physical layer) on **0000:00:00.0 (144d:eced),
  the Wi-Fi root port**, near several modem power-ons: not the modem's
  link. Record whether it recurs.
- UFS: 9 recovered `ufshcd_err_handler` passes (no resets, aborts or I/O
  errors) during the retries, as M2.5 predicted for repeated link changes.
- The debugfs status read "state: cp 0, phy 0/0, link 0" afterwards: the
  "cp" field only tracks the debugfs steps' own power-on, so it said 0
  while CPIF had the modem powered.

**Fixes (offline, 2026-10-13; `omamobile-modem` `1fc15c4a6`..`7d9c1c3a4`,
built as `7.3.0-rc6-omamobile-push1-00363-g7d9c1c3a4465`, W=1 clean,
checkpatch clean but for the missing sign-off):**

| Commit | What |
| --- | --- |
| `1fc15c4a6` | root port set up as `dw_pcie_setup_rc()` does on every link up (bridge class, bus numbers, memory/bus master); AER, PME, DPC and hotplug kept off the port |
| `e8264de16` | the modem's function reports class "other" (0xff0000) instead of 0, so the core sizes and assigns its BARs |
| `873fea0cc` | the root port's Link Control 2 target speed stays at link_up's (Gen1 for the ROM): no core retrain under the ROM |
| `c3e4b7364` | the root port's windows saved after the scan and restored after each link down (the soft power reset clears them; the pci_devs outlive it) |
| `56b98efba` | debugfs status: "cp -" when CPIF owns the lines; trained speed/width while the link is up |
| `d1fe3981d` | s51xx probe keeps the core's BAR0 and finds the doorbell at `pci_db_addr`'s offset in it (0x60000); fails if BAR0 is unassigned or the device can't be enabled |
| `7d9c1c3a4` | the s51xx driver is unregistered when nothing bound, so the next power-on probes again; register_pcie()'s error fails the ROM boot at once (normal and dump boot) instead of 200 polls |

`omamobile-modem` 0.1.2: the profile stops cbd at its first failed boot
attempt (the first "ERR! IOCTL_... fail" or "start boot fail" after a
"Power on CP"; `OMAMOBILE_MODEM_CBD_ATTEMPTS`, default 1), so one failure
costs one power-on, not 15. The CP is left as it is for diagnosis; the
reboot powers it off (one UFS pass).

```sh
# M3.4.5b THE FIRST BOOT, again (announce: the modem powers on and stays on; risk: medium-high)
# Before (laptop): the human merges omamobile-modem (7d9c1c3a4 or later) into omamobile-int and builds it;
#   packages/omamobile-modem/test/all passes (0.1.2).
# 0. M3.4.0 (read-only): the six partitions against the newest backup, as above: no diff
# 1. install 0.1.2 (asks the human; risk: none)
tools/phone-install-package packages/omamobile-modem
tools/phone-ssh 'pacman -Q omamobile-modem; systemctl is-enabled omamobile-modem; cat /var/lib/omamobile/modem-bringup-started 2>&1'
#   pass: omamobile-modem 0.1.2; "disabled"; the M3.4.5 marker still there (expected: it never reached ONLINE)
# 2. the int kernel with the overlay (asks the human: reboots; risk: low)
ov gnss-pmic-test gnss-test aoc-boot-test modem-cpif-test && bin/omamobile push
tools/phone-ssh 'uname -r; lsmod | grep -cE "^(cpif|shm_ipc|pcie_gs201_cp) "; dmesg | grep -c ufshcd_err_handler'
#   pass: the new int release (record it); 0 modules; err_handler 0. Second terminal as in M3.4.2:
tools/phone-ssh dmesg -w | tee logs/m3.4.5b-kmsg.log
# 3. M3.4.3 again (modules, preconditions, no modem power; risk: low): same pass as M3.4.3, and the
#    status file now shows "state: cp -, phy 0/0, link 0, atu 0"
# 4. the boot: clear the M3.4.5 marker and start the unit, never `omamobile-modem-start --retry` by hand
#    (the unit would not see it; as with the AoC)
tools/phone-ssh 'systemd-run --unit=x-modem-deadman --on-active=300 systemctl stop omamobile-modem'
tools/phone-ssh 'dmesg | grep -c ufshcd_err_handler; rm -f /var/lib/omamobile/modem-bringup-started; sync;
  systemctl start --no-block omamobile-modem; sleep 60;
  /usr/lib/omamobile-vendor/omamobile-modem-cp state; cat /sys/devices/platform/cpif/modem_state;
  journalctl -u omamobile-modem --no-pager | grep -v linker | tail -40; ls /var/lib/omamobile/modem-bringup-started 2>&1;
  cat /sys/kernel/debug/gs201-pcie-cp/status | grep -E "state|link Gen|LTSSM|faults"; dmesg | grep -c ufshcd_err_handler'
#   expect in the kmsg terminal, first attempt:
#   - IOCTL_POWER_ON, the power-on edges, "link up: Gen1 x1 (target Gen1)", and NO "removing 2.5GT/s
#     downstream link speed restriction";
#   - "pci 0001:00:00.0: [144d:ecec] type 01 class 0x060400", "pci 0001:01:00.0: [144d:a5a5] type 00
#     class 0xff0000", then "BAR 0 [mem 0x14e00000-0x14efffff 64bit]: assigned" (record the
#     addresses; the bus side, not CPU) and a bridge window "[mem 0x14e00000-...]" on 0001:00:00.0;
#   - "s51xx EP driver Probe", "doorbell: BAR0 [mem ...] (bus 0x14e00000, reads 0x14e0000x) + 0x60000;
#     pci_db_addr 0x14e60000", "Set Doorbell register address", "Enable PCI device", 4 MSI vectors,
#     "CP EP driver initialization end";
#   - check_cp_status: boot_stage moving off 0x0, cbd's later stages, a link down and "link up: Gen3 x2";
#   - CPIF ONLINE; journal "CP ONLINE (cbd exit 0)"
#   pass: as M3.4.5 (ONLINE, marker gone, faults 0x0, err_handler unchanged across power-on and boot
#     except a pass at the Gen1->Gen3 link change, which is to be recorded, not a stop on its own);
#     status "link Gen3 x2 (target Gen3)"
tools/phone-ssh 'systemctl stop x-modem-deadman.timer'     # only once ONLINE was seen
#   stop (record, collect the three logs as in M3.4.5, then reboot-to omamobile; one UFS pass expected):
#   - "BAR0 ... not assigned: no doorbell" / "doorbell ... outside BAR0" / "pci_enable_device() failed":
#     the probe refused; the journal shows "cbd: 1 failed boot attempt(s): stopping it" and only ONE
#     IOCTL_POWER_ON in the kmsg (two at most if cbd's retry raced the stop). Record the scan lines
#     (classes, BARs, bridge windows) and stop: next step is offline;
#   - the probe passed but boot_stage stays 0x0 to cnt 200 ("check_cp_status fail (err -14)"): the
#     doorbell or the boot image address doesn't reach the ROM. Record the doorbell line, BAR0's
#     "reads" value and `lspci -vv -s 0001:01:00.0` (Control: Mem+ BusMaster+), then stop;
#   - more than 2 IOCTL_POWER_ON in total, or any "already registered": the 0.1.2 profile or
#     7d9c1c3a4 is not what runs: stop the unit at once (`systemctl stop omamobile-modem`);
#   - AER lines on 0001:00:00.0 (the modem's root port; 0000:00:00.0 is Wi-Fi's: record only);
#   - UFS beyond one pass per link change, an Oops, a panic, the watchdog
#   rollback: reboot (the unit's stop powers the CP off before rfsd); a boot without CPIF: images
#   without modem-cpif-test
# 5. M3.5 (read-only), then M3.4.6 if ONLINE
```

**M3.4.5b result (2026-10-13, int `a0a2d81c1`, 7.3.0-rc6-omamobile-push1-00419-ga0a2d81c16c6,
`omamobile-modem` 0.1.2): passed.**

- Step 0: the six partitions matched the backup; all ro=1, unmounted.
- Step 3: "state: cp -, phy 0/0, link 0, atu 0", preconditions met.
- Step 4: one IOCTL_POWER_ON. "link up: Gen1 x1 (target Gen1), try 1";
  root port class 0x060400, modem 144d:a5a5 class 0xff0000; BAR0 assigned
  (CPU 0x40000000, bus 0x14e00000, reads 0x14e00004); doorbell "+ 0x60000;
  pci_db_addr 0x14e60000". cbd: "Complete normal bootup", "Boot up process
  done"; rfsd's ModemStateMonitor saw ONLINE; journal "CP ONLINE (cbd exit
  0)" about 8 s after the unit started. Marker gone, faults 0x0, ctrl irq
  on, "capability part:0 AP:0x00000002". UFS handler passes: 0.
- Not as expected, recorded: the PCI core still printed "removing 2.5GT/s
  downstream link speed restriction" once at the first scan (harmless this
  time), and the main link trained at **Gen1 x2 (target Gen3), try 3**
  rather than Gen3 x2.
- M3.5: no change. M3.4.6 (10 min): ONLINE, 0 link down or completion
  timeouts, 0 UFS handler passes, no crash file, faults 0x0.
- Side effect found: the chroot's loop devices (RAM copies of efs,
  efs_backup, modem_userdata, modem_a) were seen by udisks, and the user
  session's automounter (udiskie) asked polkit to mount each one, which
  showed administrator password prompts on the screen. `omamobile-modem`
  0.1.3 marks loop devices backed by `/run/omamobile-vendor/*`
  UDISKS_IGNORE; the mounts all failed, so nothing touched the copies.

**M3.5 (after every M3.4 or M4 run; read-only; risk: none):** repeat the
M3.4.0 commands into `logs/m3.4-after.sha256` and diff against
`logs/m3.4-before.sha256`. **Pass:** no change. **Stop:** any change: all
modem work stops; NV was written from Linux. This check also works with
the modem running (it only reads the real partitions, which the chroot
never sees).

```sh
# M3.4.7 the orderly stop, once, on the human's go (a reboot; risk: medium: one modem power-off)
tools/phone-ssh 'reboot-to omamobile'
# after the reboot: the previous boot's journal if it is persistent, else the kmsg terminal's log
tools/phone-ssh 'journalctl -b -1 -u omamobile-modem --no-pager | tail -8; journalctl -b -1 -k --no-pager | grep -cE "ufshcd_err_handler"'
grep -nE "CP OFFLINE|power-off sequence|ufshcd_err_handler" logs/m3.4-kmsg.log | tail -5
#   pass: "omamobile-modem-cp: CP OFFLINE" in the stop, before the namespace ends (rfsd outlived the CP);
#   one recovered handler pass in the previous boot's kernel log after "modem power-off sequence"
#   stop: "CP did not reach OFFLINE": CPIF's shutdown still powered it off, but report it
```

**Record** in this plan: the date, `uname -r`, the probe and boot log lines
(no addresses beyond the region bases above, nothing from `/chosen/config`,
no IMEI), the baseband version, the main link's Gen/width.

**Hand-over to M4:** M3.4.6 passed, the modem left ONLINE in
`omamobile-modem.service`; M3.5 passed.

### M4: registration, data, SMS and voice (`omamobile-modem-sit` 0.2.0)

**What it does:** `omamobile-sitd --bringup` registers the fresh CP in the
order that worked on this phone model (MODEM-CLIENT.md 1.1): SIM ready,
radio off, initial attach APN and data profile, radio on, packet
registration, NR off (LTE), the internet bearer, IMS (stack, IPv6 IMS
bearer, ADD_PDN_INFO, registration with voice and SMS). Then it serves
calls and SMS on its socket; `omamobile-sit-data` puts rmnet0 behind Wi-Fi
as a fallback route. **From M4.2 the radio transmits**: the phone can be
reached by calls and SMS while the RIL runs.

**Preconditions:** M3.4.6 passed and the modem left ONLINE; M3.5 passed.
A SIM with its PIN lock off (the RIL has no PIN entry: take the lock off in
another phone). The carrier's APN known. The UFS check above after every
step. Check every excerpt for digit runs before quoting it here: numbers,
IMSI and addresses never go into the plan.

**2026-10-25: M4.0 and M4.2-M4.7 below are superseded by "M4.2-M4.7: the
first SIM test" at the end of section 3** (`omamobile-modem-sit`
0.3.3: no call audio by default, the earpiece ceiling, IMS failure keeps
data). They stay as written for the record; M4.1 is the probe both use.
M4.5 below routed call audio at stage `media`, which puts the top
amplifier (the earpiece) at analog 10, above the earpiece ceiling of 6
(AUDIO-PLAN section 4): don't run it.

```sh
# M4.0 install, enable nothing (risk: none). The human writes the APN.
tools/phone-install-package packages/omamobile-modem-sit
tools/phone-ssh 'pacman -Q omamobile-modem-sit; systemctl is-enabled omamobile-sitd omamobile-sit-data;
  sed -n "/^\[network\]/,/^\[data\]/p" /etc/omamobile/modem-sit.conf | grep -E "^(apn|ims|nr) "'
#   pass: 0.2.0; "disabled" twice; apn = <the carrier APN>, ims = yes, nr = off
#   rollback: pacman -R omamobile-modem-sit

# M4.1 first SIT contact, read-only: radio stays off (risk: low)
tools/phone-ssh 'timeout 60 omamobile-sitd --probe' 2>&1 | tee logs/m4.1-probe.log
#   expect: "SIM card state 1 applications [(2, 5)]" (a USIM, READY); radio state 0;
#   packet registration state 0; NR mode 3 (stock's byte); "SMSC present True"
#   pass: those lines, every request "error=0"; the CP still ONLINE (omamobile-modem-cp state)
#   stop: a SIM application in state 2 (PIN): stop here, take the PIN lock off in another phone;
#     no response at all (the IPC channel or CPIF's IPC path: send the kmsg log); a CP crash
#   rollback: none needed (read-only)

#   no SIM in the phone (2026-10-13): see M4.1b for what the probe prints then

# M4.2 registration (announce: the radio transmits from now on; risk: medium)
tools/phone-ssh 'systemctl start --no-block omamobile-sitd; sleep 5; journalctl -fu omamobile-sitd' | tee logs/m4.2-sitd.log
#   (Ctrl-C once "Calls and SMS service ready" or a failure shows; allow up to ~6 minutes)
#   expect: "SIM card state and application type/state: (1, ((2, 5),))"; SET_INITIAL_ATTACH_APN and
#   SET_DATA_PROFILE error=0; "waiting for packet registration"; "verified NR mode 0";
#   "data-call status 0 CID 1 active raw 2"; AIMS_STACK_START_REQ error=0; "data-call status 0 CID 2";
#   "IMS PDN information accepted"; "Startup: LTE, IMS voice and SMS registered"; "service ready"
tools/phone-ssh 'omamobile-sit status; systemctl is-active omamobile-sitd'
#   pass: "network: home LTE ..."; "IMS voice: yes, SMS: yes, data bearer: up"; active
#   stop: the unit fails (journal names the step: SIM timeout, registration deadline, "data call
#     did not become active" with its status, IMS deadline). Record the step and status, then reboot
#     before another try (a second start-up on the same CP isn't supported; about one start in twenty
#     crashed the CP during registration on this phone model: the watcher records it)
#   rollback: `omamobile-sit radio off` (AT+CFUN=0: deregisters; turning it on again may stall
#     registration until a reboot), then `systemctl stop omamobile-sitd`; or reboot

# M4.3 data (risk: low-medium: mobile data use; Wi-Fi keeps the default route while up)
tools/phone-ssh 'systemd-run --unit=x-data-deadman --on-active=600 systemctl stop omamobile-sit-data'
tools/phone-ssh 'omamobile-sit data on; sleep 5; ip -br addr show rmnet0; ip route show default;
  ping -c3 -I rmnet0 9.9.9.9; curl -sS --interface rmnet0 -o /dev/null -w "%{http_code}\n" https://example.org/'
#   pass: rmnet0 UP with a /32 (don't paste it); "default dev rmnet0 ... metric 700" behind Wi-Fi's;
#   3 replies; 200
#   stop: no replies with the bearer up (record "Cellular bearer carries nothing" lines); UFS
#   rollback: omamobile-sit data off; systemctl stop x-data-deadman.timer
#   optional, attended (USB stays: it's the gadget, not Wi-Fi): Wi-Fi off for one minute
#   (`nmcli radio wifi off; sleep 60; nmcli radio wifi on` in one command), check that the journal of
#   omamobile-sit-data says "Default internet path cellular" and then "Wi-Fi/other"

# M4.4 SMS (risk: low; sending costs what the plan charges)
#   receive: the human texts the phone from another phone
tools/phone-ssh 'omamobile-sit status; omamobile-sit sms list | head -2'
#   pass: the journal shows "SMS stored and acknowledged"; the list shows it (a number: don't paste)
#   send, on the human's explicit go only, to a number of theirs:
tools/phone-ssh 'omamobile-sit sms send <NUMBER> "omamobile test"'
#   pass: "sent", and the message arrives. "unknown": never resend blindly; ask the recipient

# M4.5 voice (announce: a call; audio plays through the top speaker/earpiece amplifier; listener
# needed; risk: medium). Precondition: omamobile-audio stage media, protection running.
tools/phone-ssh 'amixer -c $(awk "/aoc/ {print \$1; exit}" /proc/asound/cards) cget name="TDM_0_RX Mixer EP5" | tail -1'
#   record the value (expect off): it must be back after the call
tools/phone-ssh 'omamobile-sit dial <NUMBER>'          # the human's other phone; answer it
#   pass: the human hears and is heard both ways; `omamobile-sit status` shows the call "active"
tools/phone-ssh 'omamobile-sit hangup; sleep 2; omamobile-sit status;
  amixer -c $(awk "/aoc/ {print \$1; exit}" /proc/asound/cards) cget name="TDM_0_RX Mixer EP5" | tail -1'
#   pass: the call "terminated"; the mixer back at the recorded value; the journal says
#   "AoC call routes restored". Then the human calls the phone: `omamobile-sit answer`, talk, hangup
#   stop: no audio either way (record the journal: "voice PCM ... failed" means the AoC card; check that
#     PipeWire does not hold PCM 4/11), distorted or loud audio (hang up at once), a release that is
#     never confirmed (the RIL stops the modem unit by design after 12 s: one UFS pass; reboot after)
#   rollback: omamobile-sit hangup

# M4.6 at boot (asks the human: reboots; risk: medium: from now on every boot powers the modem on,
# and every reboot off: one UFS pass per reboot, as now with the modem unit)
tools/phone-ssh 'systemctl enable omamobile-modem omamobile-sitd omamobile-sit-data'
tools/phone-ssh 'reboot-to omamobile'
tools/phone-ssh 'sleep 240; systemctl is-active omamobile-modem omamobile-sitd omamobile-sit-data; omamobile-sit status;
  ls /var/lib/omamobile/modem-bringup-started 2>&1; dmesg | grep -c ufshcd_err_handler'
#   pass: active x3; registered with IMS voice and SMS; no marker; err_handler 0 (power-on only)
#   stop: the unit skipped with "never reached ONLINE": a previous boot hung during bring-up; look
#     before `omamobile-modem-start --retry`
#   rollback: systemctl disable omamobile-modem omamobile-sitd omamobile-sit-data; reboot

# M4.7 M3.5 again (read-only): the six partitions unchanged
```

**Record** in MODEM-CLIENT.md's results table or here: per step, the date,
`uname -r`, pass/fail, the failing step and its status code.

**M4.1, first run (2026-10-13, int `a0a2d81c1`,
`7.3.0-rc6-omamobile-push1-00419-ga0a2d81c16c6`, `omamobile-modem-sit`
0.2.0, no SIM in the phone): FAILED, no reply.** GET_SIM_STATUS timed
out after 8 s; the CP stayed ONLINE, UFS 0. Kernel log, from the boot on:
- At ONLINE (100.8 s) the init handshake **completed**: "INIT_START <-
  s5300", "capability part:0 AP:0x00000002 CP:0x00000007", "LINK_ATTR_SBD_IPC
  is NOT set" (expected: stock's `mif,link_attrs` is the same 0x17c8, without
  SBD; the S5300 uses the legacy buffers), "PIF_INIT_DONE -> s5300",
  "PHONE_START <- s5300", "INIT_END -> s5300", BOOTING -> ONLINE. With the
  SIT protocol CPIF sends INIT_END at PHONE_START without waiting for an
  IPC client.
- At the probe (1167 s): "ipc_open: umts_ipc0", then "ipc_write: umts_ipc0:
  wait for INIT_END done (150ms) cnt:1 last:0 cmd:0xC2". That line is a
  one-time 150 ms settle after an INIT_END the writer hasn't seen yet
  (`last_init_end_cnt` 0 -> 1), not a hang: the write then went to the
  FMT legacy buffer with no error logged, and `ap2cp_msg` still held
  INIT_END (0xC2 = valid | command | 2). Then nothing until "ipc_release"
  8 s later: no CPIF error, no MSI-side message, no link event.
- From ONLINE to the probe (about 1070 s): **no cp2ap_wakeup interrupt and
  no link change at all**. On the working stack the modem drops its wakeup
  line when idle and the AP powers the link down; replies came through
  "idle PCIe wake/retrain". Here either the modem held CP2AP_WAKEUP high
  throughout, or the GPIO interrupt (gpa8-3, level-low) never reached
  CPIF. Not yet known which.
- Also at load: a workqueue WARN with backtrace (`mem_rx_work` without
  WQ_PERCPU; harmless, fixed in `cf6661059`).

Our CPIF's device tree (link attributes, legacy buffer offsets and sizes,
control-message offsets, channel numbers) matches stock's live DT line for
line; the doorbell and MSI paths carried PIF_INIT_DONE and PHONE_START
within a millisecond of each other, so both directions of the command
path work. What the log can't tell is which of three things happened:
the modem never took the frame from the FMT buffer, it took it and didn't
answer, or it answered and the reply never reached umts_ipc0.
`151fa8928` adds a read-only `/sys/devices/platform/cpif/legacy_queues`
(the ring pointers of each legacy buffer, flow control, both wakeup lines,
a held-back doorbell) that separates the three, and M4.1b reads it around
one probe, plus a read-only AT query on the other buffer (RAW,
`umts_router`). Differences from the working stack that are still open,
for after M4.1b and one per boot: the packet processor (stock and the
working stack run it; we run without `modem-cpif-pktproc`, so the AP
capability is 0x2 instead of 0x3), and the idle wake/link-down cycle.

```sh
# M4.1b SIT contact with diagnostics (read-only; risk: low). Needs a reboot to the new kernel, which
# powers the CP off (one UFS pass), then M3.4.5b's start again.
# Before (laptop): the human merges omamobile-modem (151fa8928 or later) into omamobile-int, builds it.
# 1. new kernel (asks the human: reboot; risk: low): as M3.4.5b step 2, then kmsg terminal:
tools/phone-ssh dmesg -w | tee logs/m4.1b-kmsg.log
#   pass: no "mem_rx_work is using neither WQ_PERCPU" WARN when CPIF loads
# 2. the modem to ONLINE: M3.4.5b step 4 (dead-man, clear the marker, start the unit); pass as there
# 3. state before the probe (read-only)
tools/phone-ssh 'C=/sys/devices/platform/cpif; cat $C/legacy_queues $C/info_region;
  cat $C/napi/rx_int_count $C/napi/rx_poll_count; grep -E "mif_cp2ap|cp2ap_wakeup|phone_active" /proc/interrupts' | tee logs/m4.1b-before.txt
#   expect: "magic:0x000000AA mem_access:1" ("active" is a field CPIF never sets: ignore it); for each buffer tx head == tail and rx head == tail;
#   tx_flowctrl_mask:0x0; record cp2ap_wakeup (1 = the modem holds the link awake), the interrupt counts
# 4. the probe (read-only): no SIM is in the phone
tools/phone-ssh 'timeout 60 omamobile-sitd --probe' 2>&1 | tee logs/m4.1b-probe.log
#   pass for the IPC path: any "SIT GET_SIM_STATUS: error=<n> length=<n>" line: a reply came back.
#   With no SIM, expect "SIM card state 0 applications []" (0 = absent, no applications), or, if the
#   modem answers absent with a short or error reply, "SIM status layout unexpected, length <n>" or a
#   "modem rejected request with error <n>" traceback: all three are a pass here (record which).
#   Then radio state 0, packet registration state 0, NR mode, SMSC present False (no SIM): any value.
#   fail: "TimeoutError: SIT GET_SIM_STATUS" again: go on with 5. and 6., they tell where it stopped
# 5. state after (read-only), at once
tools/phone-ssh 'C=/sys/devices/platform/cpif; cat $C/legacy_queues $C/info_region;
  cat $C/napi/rx_int_count $C/napi/rx_poll_count; grep -E "mif_cp2ap|cp2ap_wakeup|phone_active" /proc/interrupts' | tee logs/m4.1b-after.txt
#   read the FMT line against 3.:
#   - fmt tx head moved and tail did NOT follow: the modem never took the frame (AP->CP: the doorbell
#     or what it reads in shared memory). Stop; record both files
#   - tx tail followed head, rx head unchanged, mif_cp2ap_msg count unchanged: the modem took it and
#     didn't answer. Stop; record cp2ap_wakeup. Next change (one per boot, offline first): the
#     packet processor overlay, or the idle wake cycle
#   - rx head moved but rx tail didn't follow, or tail followed and the probe still timed out: the reply
#     arrived and CPIF didn't deliver it (MSI count, rx_int_count/rx_poll_count tell interrupt vs NAPI)
# 6. the other buffer: a read-only AT query on umts_router (RAW), radio stays off
tools/phone-ssh 'cd /usr/lib/omamobile-sit && timeout 20 python3 -c "import os, at, paths
fd = paths.open_channel(paths.ROUTER)
try: print(repr(at.exchange(fd, at.COMMANDS[\"radio-state\"], 8)))
finally: os.close(fd)"; cat /sys/devices/platform/cpif/legacy_queues'
#   pass: "+CFUN: 0" and "OK" (the radio is off). Empty: the RAW buffer doesn't answer either
#   stop (any step): a CP crash (modem_state not ONLINE, /run/omamobile-modem/crashed), an Oops,
#     UFS beyond 0 while the modem doesn't change power
#   rollback: none (read-only); the modem stays ONLINE. Quote only the queue and count lines, never
#     the AT reply beyond "+CFUN: <n>" and OK
```

**M4.1b, results (2026-10-13, int `b28635c96`,
`7.3.0-rc6-omamobile-push1-00422-gb28635c965f3`; logs `logs/m4.1b-*`):
FAILED the same way, and located.** Step 1 passed (no workqueue WARN);
ONLINE with one POWER_ON, UFS 0, link Gen1 x2 (target Gen3).
- Before the probe: "magic:0x000000AA mem_access:1" (the legacy link's
  words, written at PHONE_START; "active:0" is an unused field); FMT and
  NORM_RAW: every head and tail 0; flow control 0; cp2ap_wakeup 1,
  ap2cp_wakeup 1, link powered, no doorbell held back; `ap2cp_msg` 0xC2
  (INIT_END), `cp2ap_msg` 0xC8 (PHONE_START, the CP's last command);
  `ap2cp_united_status` 0x4000 (the SIM-slot bits only). Interrupts:
  mif_cp2ap_msg 2052 (all during the boot), mif_cp2ap_status 0,
  cp2ap_wakeup 0, phone_active 0.
- Probe: TimeoutError on GET_SIM_STATUS. After: **FMT "tx head:24 tail:0"**,
  rx 0/0; `ap2cp_msg` 0x82 (valid | send FMT: the data doorbell went out,
  none held back); MSI count unchanged at 2052. The AT query on
  `umts_router`: no reply, NORM_RAW "tx head:24 tail:0".
- So the modem takes nothing from either legacy transmit buffer, and from
  ONLINE on it sends nothing at all (no MSI, no indication, no RFS
  request), while it stays ONLINE with both wakeup lines high.

Checked offline against stock's live DT, Google's CPIF and the working
stack's patches:
- Doorbell: the same address (BAR0 at bus 0x14e00000, CPU 0x40000000, +
  0x60000) and value (0x10000 | int 0) as the working stack, written with
  no error and read back; PIF_INIT_DONE through it got PHONE_START 0.9 ms
  later.
- Coherency: the IPC region is mapped write-back as on stock (linear map
  there), and the boot loader image cbd sends is copied into the same
  write-back mapping (IPC region + 0x10000) and the CP's ROM read it and
  booted it: the CP does see what the AP writes through that mapping. The host sets the same IOCC registers as the working stack
  (DBI 0x8e8 = 0x10101010, HSI1 sysreg 0x704 bits 1:0).
- Device tree, legacy offsets, control-message offsets, magic (0xAA),
  INIT_END at PHONE_START for SIT: as stock.
- **Different from stock and from the working stack: the packet
  processor.** We run without `modem-cpif-pktproc`: the AP capability word
  reads 0x2 (channel extension only) where both others write 0x3
  (+ uplink packet processor), and the downlink processor's info region
  is left empty ("pktproc_init: version:0 ... num_queue:0") where the CP
  expects version 2 with four queues. The CP announces 0x7. Open question
  7 and section 6.2 item 4 named this as the first suspect for a CP that
  stops at the IPC start; the symptom (ONLINE, then no IPC in either
  direction) fits a CP that waits on its packet-processor setup.

The int kernel already has `CONFIG_CP_PKTPROC` and `CONFIG_CP_PKTPROC_UL`
(the 2026-10-13 fragment), so M4.1c needs no new kernel: only the overlay,
in the images. **It can't be tried without a reboot**: the CP reads the
capability word and the packet-processor info once, at the INIT handshake
after its boot, and the overlay changes the device tree CPIF bound to
(CPIF can't be unloaded). The reboot powers the CP off (one UFS pass) and
the modem then needs M3.4.5b's start. The packet-processor code
(`27a9eb4e9`, `000a39ed3`, `db2aaa156`) has never run on the hardware:
the step below is risk medium for that reason.

```sh
# M4.1c the packet processor on (asks the human: reboot; announce: the modem powers on; risk: medium:
# first run of the CPIF packet processor and its four MSI blocks)
# 1. the same int kernel, images with the overlay after modem-cpif-test
ov gnss-pmic-test gnss-test aoc-boot-test modem-cpif-test modem-cpif-pktproc && bin/omamobile push
tools/phone-ssh 'uname -r; lsmod | grep -cE "^(cpif|shm_ipc|pcie_gs201_cp) "; dmesg | grep -c ufshcd_err_handler;
  ls /proc/device-tree/cpif/pktproc_dl_support'
#   pass: the int release (record it); 0; 0; the property exists
tools/phone-ssh dmesg -w | tee logs/m4.1c-kmsg.log      # second terminal
# 2. the modem to ONLINE: M3.4.5b step 4. Expect, in addition, at CPIF load (as stock's dmesg):
#   "pktproc_get_info: version:2 cp_base:0x20000000 mode:1 num_queue:4", "pktproc_create: Create queue 0".."3",
#   "pktproc_get_info_ul: ... num_queue:2", "pktproc_create_ul: Queue 0" and "Queue 1", and NOT "legacy
#   buffers only"; at the first link up no "register_separated_msi_vector ... err"; at INIT_START
#   "pktproc_init: version:2 ... num_queue:4", "capability part:0 AP:0x00000003", no "pktproc_init_ul() ret",
#   PIF_INIT_DONE, "PHONE_START", "capability part:0 AP:0x00000003 CP:0x00000007", INIT_END, ONLINE
#   stop: an Oops or panic (the watchdog resets the phone; record the kmsg log); "pktproc_init() error",
#     "init_ap_capabilities part:0 fail", "ERR! capability"; the CP not ONLINE (collect as M3.4.5); a crash file
#   rollback: images without modem-cpif-pktproc (as M4.1b); reboot
# 3. a minute after ONLINE, read-only: is the CP talking by itself now?
tools/phone-ssh 'sleep 60; C=/sys/devices/platform/cpif; cat $C/legacy_queues $C/info_region;
  grep -E "mif_cp2ap|cp2ap_wakeup|phone_active|pktproc|DW-PCI-MSI" /proc/interrupts' | tee logs/m4.1c-before.txt
#   record: mif_cp2ap_msg above its count at ONLINE, an FMT/NORM_RAW rx head off 0 (an indication or an RFS
#   request), cp2ap_wakeup 0 with a link power-down in the kmsg (the idle cycle): any of these means the
#   CP's IPC side started. None of them: go on anyway, 4. decides
# 4. the probe, no SIM (read-only), and the state after, as M4.1b steps 4 and 5
tools/phone-ssh 'timeout 60 omamobile-sitd --probe' 2>&1 | tee logs/m4.1c-probe.log
tools/phone-ssh 'C=/sys/devices/platform/cpif; cat $C/legacy_queues $C/info_region;
  grep -E "mif_cp2ap|cp2ap_wakeup|DW-PCI-MSI" /proc/interrupts' | tee logs/m4.1c-after.txt
#   pass: a "SIT GET_SIM_STATUS: error=<n> length=<n>" line; with no SIM "SIM card state 0 applications []"
#     (or "SIM status layout unexpected, length <n>", or "modem rejected request with error <n>": also a pass);
#     FMT tx tail == head after it
#   fail: TimeoutError and FMT "tx head:24 tail:0" again: the packet processor was not it. Stop, keep the
#     modem up, send the four files; the next suspects are the CP's own view (its boot log) and the
#     wakeup handshake, offline first
#   if the link went down while idle (step 3), the probe's write wakes it: expect "Reserve doorbell
#     interrupt: PCI not powered on", a link up and the reply; one UFS check after (power changes)
# 5. AT on the RAW buffer, as M4.1b step 6: "+CFUN: 0" and OK
# UFS after every step: unchanged, except a pass at a link power change (record it)
```

**M4.1c, results (2026-10-13, int `937d47233`,
`7.3.0-rc6-omamobile-push1-00446-g937d47233338`, overlays as M4.1b plus
`modem-cpif-pktproc`; logs `logs/cam-m41c-kmsg.log`, `logs/m4.1c-*`):
FAILED, unchanged.** The packet processor came up as on stock
("pktproc_get_info: version:2 cp_base:0x20000000 mode:1 num_queue:4",
UL 2 queues, MSI blocks 1-4, no "legacy buffers only"), one POWER_ON,
ONLINE, UFS 0, "capability part:0 AP:0x00000003 CP:0x00000007". A minute
after ONLINE: every legacy head and tail 0, both wakeup lines 1,
`ap2cp_msg` 0xC2, `cp2ap_msg` 0xC8, MSI count 2052 as at the boot,
cp2ap_wakeup interrupts 0. Probe: TimeoutError; after it FMT "tx head:24
tail:0", `ap2cp_msg` 0x82. So the packet processor was not it (keep the
overlay: it is stock's configuration). (Its downlink rings come out at
4468 descriptors of 1584 bytes, stock's at 3456 of 2048 because stock
sizes them for its IOMMU; the CP reads the count from the info region.)

**Stock's own CP boot, read offline (2026-10-13) from the stock capture's
dmesg** (`~/android/reference/cheetah-stock-cp2a-root/dmesg.txt`,
private): the AP side runs the same steps in the same order and with the
same timing as ours: IOCTL_HANDOVER_BLOCK_INFO, POWER_ON,
START_CP_BOOTLOADER, ds_det 1, the ROM link, "set_cp_rom_boot_img:
boot_img addr:0xEA410000 size:0x16800", boot_stage 0xFF then 0x3FFF, the
ROM link down, CP2AP_WAKEUP 0 -> 1, the boot loader link,
COMPLETE_NORMAL_BOOTUP, INIT_START about 1.05 s later, PIF_INIT_DONE,
PHONE_START 0.5 ms later, the same capabilities, INIT_END, ONLINE. Then
on stock: rild's first umts_ipc0/1 writes 66 ms after ONLINE (with the
same one-off "wait for INIT_END done (150ms) cnt:1 last:0 cmd:0xC2" line
as ours); at +2.4 s the FMT transmit buffer is busy enough to fill
("NOSPC FMT_TX ... in:1656 out:1696"), so the CP is taking frames; from
+3.9 s the CP drops CP2AP_WAKEUP and CPIF powers the link down and up
again and again ("Reserve doorbell interrupt: PCI not powered on", a new
L0 each time). Ours: the CP takes nothing and holds CP2AP_WAKEUP high for
good. So the CP stops between INIT_END and its IPC service, and the AP's
sequence up to there matches stock's.

What differs before that point is the boot loader link: **Gen1 x2 on
every one of our boots** ("link at Gen1, below Gen3: retrying" twice,
then the last try kept, each retry with a PERST# cycle under the boot
loader), where stock's boot loader link and the working stack's are
Gen3 x2. Upstream `dw_pcie_setup_rc()`, which Google's establish_link
runs, ends by setting `PORT_LOGIC_SPEED_CHANGE` (DBI 0x80C bit 17; the
working stack's host writes it too); without it a DesignWare port stays
at 2.5 GT/s whatever Link Control 2 says. Our root-port setup
(`1fc15c4a6`) stopped one write short. Whether the CP's IPC waits on the
Gen3 link is not proven, but it is the one difference left on the path,
the modem never asked for anything else, and a CP that holds its wakeup
line high while waiting on a link change fits. `02cc44421` sets the bit
(nothing changes for the ROM link, whose target is Gen1).

Checked and the same as stock: the modem's GPIOs (stock's
`gpio_ap2cp_*`/`gpio_cp2ap_*` and our board node name the same pins);
`AP2CP_AP_ACTIVE` (PDA active) set high at the boot start by the same
code; `ap2cp_united_status` 0x4000 (only ds_det; stock's CPIF writes no
AP-status or PDA bits there either, those masks are parsed and never
used); `ap2cp_kerneltime` is written only at suspend, resume and LCD
events on stock too. The CP's own log: cbd clears the CP boot log at
ONLINE (`IOCTL_CLR_CP_BOOTLOG`), and `IOCTL_GET_CP_BOOTLOG` (0x6F47 on
umts_boot0) prints whatever the CP wrote there since to the kernel log;
umts_dm0 needs a DM start request from a client, which we don't send.

```sh
# M4.1d the boot loader link at Gen3 (asks the human: reboot; announce: the modem powers on and the link
# then may cycle on its own; risk: medium: a new link speed under the modem, and from here CPIF's idle
# link power-downs, which may each cost a UFS handler pass (M2.5/M2.6))
# Before (laptop): the human merges omamobile-modem (02cc44421 or later) into omamobile-int, builds it.
# 1. the same overlays as M4.1c (modem-cpif-test, modem-cpif-pktproc after it), push, reboot;
#    kmsg terminal into logs/m4.1d-kmsg.log; pass: lsmod 0, err_handler 0
# 2. the modem to ONLINE (M3.4.5b step 4). Expect: the ROM link "link up: Gen1 x1 (target Gen1), try 1";
#    the boot loader link "link up: Gen3 x2 (target Gen3), try 1" and NO "below Gen3: retrying";
#    then as M4.1c (pktproc lines, AP:0x00000003 CP:0x00000007, INIT_END, ONLINE)
#    stop: "no L0", "link did not settle", the boot loader link failing (cbd's attempt fails at once:
#      0.1.2 stops it); the CP not ONLINE; an Oops. Rollback: images/kernel without 02cc44421; reboot
# 3. the first minute after ONLINE (read-only), the UFS count before and after:
tools/phone-ssh 'dmesg | grep -c ufshcd_err_handler; sleep 60; C=/sys/devices/platform/cpif;
  cat $C/legacy_queues $C/info_region; cat /sys/kernel/debug/gs201-pcie-cp/status | grep -E "state|link Gen";
  grep -E "mif_cp2ap|cp2ap_wakeup|phone_active|DW-PCI-MSI" /proc/interrupts; dmesg | grep -c ufshcd_err_handler' | tee logs/m4.1d-before.txt
#   expect (stock's pattern): cp2ap_wakeup interrupts above 0, CP2AP_WAKEUP at 0 when idle, link power-downs
#   and new link ups in the kmsg ("PHY isolated", "link up: Gen3 x2"), MSI counts rising, maybe an rx head
#   off 0 (an indication or an RFS request)
#   stop: UFS handler passes climbing with each link cycle (more than 3 in the minute): reboot now, record
#     the count per cycle; the policy question (keep the link up while the modem runs) goes offline
# 4. the probe, no SIM, and the after-state, as M4.1c step 4 (logs/m4.1d-probe.log, m4.1d-after.txt)
#   pass: "SIT GET_SIM_STATUS: error=<n> length=<n>"; with no SIM "SIM card state 0 applications []" (or
#     "SIM status layout unexpected, length <n>", or "modem rejected request with error <n>"); FMT tx
#     tail == head. If the link was down, expect "Reserve doorbell interrupt: PCI not powered on" first
#   fail: TimeoutError with "tx head:24 tail:0" again. Then, read-only, before anything else:
tools/phone-ssh 'python3 -c "import fcntl, os
fd = os.open(\"/dev/umts_boot0\", os.O_RDWR)
try: fcntl.ioctl(fd, 0x6F47)
except OSError as e: print(e)
finally: os.close(fd)"; dmesg | grep -A2 "CP boot log" | tail -5'
#     ("Invalid CP boot log[0]" = the CP wrote nothing since ONLINE; any text: check it for identifiers,
#     quote only error words). Keep the modem up, send the logs
# 5. AT on the RAW buffer, as M4.1b step 6: "+CFUN: 0" and OK
# UFS after every step: unchanged except passes at link power changes (record each)
```

**M4.1d, results (2026-10-13, int `8070cddd9`,
`7.3.0-rc6-omamobile-push1-00448-g8070cddd92a6` = `937d47233` +
`02cc44421`; overlays as M4.1c plus camera-main; logs `logs/m4.1d-*`):
the link fix works, the IPC doesn't.** ROM link "Gen1 x1 (target Gen1),
try 1", boot loader link "**link up: Gen3 x2 (target Gen3), try 1**", no
"below Gen3: retrying"; one POWER_ON, ONLINE, UFS 0 throughout. A minute
after ONLINE: every legacy head and tail 0, both wakeup lines 1, link
powered; cp2ap_wakeup interrupts 0, mif_cp2ap_msg 2052 as at the boot,
mif_cp2ap_status 0; no link cycle. Probe: TimeoutError, FMT "tx head:24
tail:0". `IOCTL_GET_CP_BOOTLOG`: "Invalid CP boot log[0]" (the CP wrote
nothing there since ONLINE). AT: no reply, NORM_RAW "tx head:24 tail:0".
Keep `02cc44421`: Gen3 x2 is stock's link.

**Stock's window after ONLINE, read again:** stock's CP doesn't answer at
once either. rild writes umts_ipc0/1 and oem_ipc3 at +66 ms, and at
+2.4 s the FMT transmit buffer is still full ("NOSPC FMT_TX{qsize:4096
in:1656 out:1696 space:39"): the CP took nothing for at least 2.4 s. At
+3.9 s "check_legacy_tx_pending: idx: 0, head: 2552, tail: 2456": the
tail has moved, so the CP started taking frames between +2.4 s and
+3.9 s, and at the same time dropped CP2AP_WAKEUP for the first time (the
link cycle starts there). Stock's interrupt counts, captured later:
mif_cp2ap_msg 2710 (ours stays at 2052), cp2ap_wakeup 31, the four packet
queue blocks 0. So on stock the CP spends 2-4 s in its own start-up after
INIT_END, then serves IPC and goes idle; ours never leaves that phase,
and never sends a single message (no RFS request, no indication, no
status) or drops its wakeup line.

**Ruled out since M4.1c:** the link speed (now Gen3 x2); the packet
processor; the AP's sequence up to ONLINE (step for step and timing as
stock); the GPIOs; the AP-status bits; the boot log (empty). Not yet
seen: whether the CP's PCIe controller accepts the doorbell writes after
its main firmware took over. Before ONLINE every stage could be polling
shared memory (the ROM's mailbox, PIF_INIT_DONE answered within 0.9 ms),
so a doorbell that stopped working when the firmware re-initialised its
endpoint would show exactly this: the init handshake passes, every later
doorbell (INIT_END, the data sends, the link-ack) goes nowhere. A posted
write the endpoint rejects leaves "UnsupReq+" in its Device Status; a
read it rejects leaves "<MAbort+" at the root port. Both are in config
space, readable now without touching the modem.

```sh
# M4.1e the endpoint's view of the doorbell (read-only; risk: low; no reboot, on the ONLINE modem;
# config-space reads over the up link only, nothing written)
# 1. config space of the modem's function and of its root port, before
tools/phone-ssh 'command -v lspci >/dev/null || { echo "no lspci (pacman -S pciutils, asks the human)"; exit 1; }
  lspci -vvv -s 0001:01:00.0; lspci -vvv -s 0001:00:00.0; lspci -xxxx -s 0001:01:00.0' | tee logs/m4.1e-before.txt
#   read and record, for the modem's function: "Control: ... Mem+ BusMaster+"; "Region 0: Memory at 40000000
#   (64-bit, non-prefetchable) [size=...]" (record the size: the main firmware's BAR0) and Regions 2-5;
#   "MSI: Enable+ Count=4/..." with "Address: 00000000f6200000"; "DevSta: ... UnsupReq-/+"; the class.
#   For the root port: "Secondary status: ... <TAbort- <MAbort-", "DevSta", "LnkSta: Speed 8GT/s, Width x2"
# 2. one doorbell: the read-only AT query (as M4.1b step 6), then the same reads
tools/phone-ssh 'cd /usr/lib/omamobile-sit && timeout 20 python3 -c "import os, at, paths
fd = paths.open_channel(paths.ROUTER)
try: print(repr(at.exchange(fd, at.COMMANDS[\"radio-state\"], 8)))
finally: os.close(fd)"; lspci -vvv -s 0001:01:00.0; lspci -vvv -s 0001:00:00.0' | tee logs/m4.1e-after.txt
#   decide:
#   - the function's BAR0 no longer at 0x14e00000/CPU 0x40000000, Mem- or BusMaster-, MSI Enable-, or
#     UnsupReq+ (new after the doorbell) or <MAbort+ at the root port: the endpoint the main firmware set up
#     does not take our doorbell. Next (offline): restore or re-probe the endpoint's config after ONLINE
#   - all as at the probe (BAR0 at 0x14e00000, Mem+ BusMaster+, MSI on, no UnsupReq/MAbort): the doorbell is
#     accepted by the PCIe side and the CP's firmware ignores it. Next (one change, a reboot): make the first
#     IPC come as stock's does, umts_ipc0 open before the boot and a request within 100 ms of ONLINE
#   stop: an Oops or a CP crash (reading config space should cause neither)
#   rollback: none (nothing written); the modem stays ONLINE
```

**M4.1e, results (2026-10-13, int `0470612d2`,
`7.3.0-rc6-omamobile-push1-00451-g0470612d2158`, modem ONLINE, boot loader
link Gen3 x2, UFS 0; logs `logs/m4.1e-before.txt`, `m4.1e-after.txt`).**
Clean before, and unchanged by the one AT query: the modem's function
Mem+ BusMaster+, Region 0 at 0x40000000 (64-bit, 1M), Regions 2-5 at
0x40100000, 0x40200000, 0x40300000, 0x40400000 (32-bit, 1M each), MSI
Enable+ 4/32 at 0xf6200000, DevSta and the AER status registers clear,
link 8GT/s x2; the root port's window 0x40000000-0x405fffff (6M, as
stock's). **Changed by the one doorbell: the modem's Status ">TAbort+"
(Signaled Target Abort) and the root port's Secondary status "<TAbort+"
(Received Target Abort).** So the modem's endpoint completes our doorbell
access (CPIF writes the doorbell, then reads it back) with a Completer
Abort. Both bits were clear before the query although INIT_END and the
link-ack went through the same doorbell, with the same read-back, during
the boot: the endpoint changed after INIT_END, when the main firmware
starts its IPC.

**Why (offline):** stock's s51xx probe writes `pci_db_addr` into BAR0,
then "disables" BARs 0-5 by rewriting their resources and calling
`pci_assign_resource()`; stock's own log shows the result: "BAR 0:
assigned [mem 0x40000000 64bit]", "BAR 2: assigned [mem 0x40000001]",
BAR 3 0x40000002, BAR 4 0x40000003, BAR 5 0x40000004, then BAR 0 again at
0x40000005-0x40001005. Each register takes the address down to the BAR's
1 MiB alignment, so on stock **all five BARs decode the same 1 MiB at bus
0x14e00000**, and the doorbell at 0x14e60000 falls in every one of them.
`d1fe3981d` kept the PCI core's assignment instead (BARs 2-5 in their own
windows), which serves the boot stages through BAR0 but evidently not the
main firmware's IPC. Which BAR or translation the firmware uses can't be
read from the AP; stock's layout works, so `7a7af33a2` restores it:
BARs 2-5 released from the PCI core and pointed at BAR0's bus address in
the probe (before the configuration is saved) and after every restore.

```sh
# M4.1f-live OPTIONAL, on the modem ONLINE now, no reboot (asks the human: writes the modem's PCI config
# space; risk: low-medium: the modem then sees stock's BAR layout; if its firmware fixed its doorbell
# mapping at start the test is merely negative)
tools/phone-ssh 'C=/sys/devices/platform/cpif; cat $C/legacy_queues; grep -E "mif_cp2ap|cp2ap_wakeup" /proc/interrupts;
  setpci -s 0001:01:00.0 BASE_ADDRESS_2=14e00000 BASE_ADDRESS_3=14e00000 BASE_ADDRESS_4=14e00000 BASE_ADDRESS_5=14e00000;
  lspci -b -vvv -s 0001:01:00.0 | grep -E "Region|Status:"' | tee logs/m4.1f-live-1.txt
#   expect (-b shows the bus addresses in the registers): Regions 0 and 2-5 "at 14e00000"; the TAbort bits as
#   M4.1e left them (status is not cleared here)
# then one doorbell: the AT query of M4.1b step 6, and the state after
tools/phone-ssh 'cd /usr/lib/omamobile-sit && timeout 20 python3 -c "import os, at, paths
fd = paths.open_channel(paths.ROUTER)
try: print(repr(at.exchange(fd, at.COMMANDS[\"radio-state\"], 8)))
finally: os.close(fd)"; C=/sys/devices/platform/cpif; cat $C/legacy_queues;
  grep -E "mif_cp2ap|cp2ap_wakeup" /proc/interrupts' | tee logs/m4.1f-live-2.txt
#   pass: "+CFUN: 0" and OK, or at least NORM_RAW tx tail == head (the modem took the frame) and the MSI count
#     rising; then the SIT probe (M4.1b step 4) too, without SIM: "SIT GET_SIM_STATUS: error=<n> ..."
#   negative: no reply and "tx tail" unchanged: the firmware keeps the mapping it set up at INIT_END; M4.1f
#     (the reboot) decides
#   stop: a CP crash (modem_state not ONLINE, a crash file), an Oops
#   rollback (either way, before anything else):
#   setpci -s 0001:01:00.0 BASE_ADDRESS_2=14f00000 BASE_ADDRESS_3=15000000 BASE_ADDRESS_4=15100000 BASE_ADDRESS_5=15200000
#   (a positive result can stay as it is: it is the layout the fixed kernel sets)

# M4.1f the fixed kernel (asks the human: reboot; announce: the modem powers on; risk: medium)
# Before (laptop): the human merges omamobile-modem (7a7af33a2 or later) into omamobile-int, builds it.
# 1. same overlays as M4.1d, push, reboot, kmsg terminal into logs/m4.1f-kmsg.log; lsmod 0, err_handler 0
# 2. the modem to ONLINE (M3.4.5b step 4). Expect, new: "BARs 2-5 on BAR0's bus address 0x14e00000, as stock"
#    after the doorbell line; the two links as M4.1d (Gen1 x1, then Gen3 x2, try 1); ONLINE
#    stop: the probe refusing, the CP not ONLINE, an Oops. Rollback: the M4.1d kernel
# 3. read-only, before any IPC:
tools/phone-ssh 'lspci -b -vvv -s 0001:01:00.0 | grep -E "Region|Status:"; C=/sys/devices/platform/cpif;
  sleep 10; cat $C/legacy_queues; grep -E "mif_cp2ap|cp2ap_wakeup|phone_active" /proc/interrupts;
  dmesg | grep -c ufshcd_err_handler' | tee logs/m4.1f-before.txt
#   expect: Regions 0 and 2-5 all "at 14e00000" (bus view); Status ">TAbort-"; and now possibly stock's pattern by itself
#   within seconds of ONLINE: an rx head off 0 (an RFS request or an indication), the MSI count rising,
#   cp2ap_wakeup interrupts, link power-downs ("PHY isolated", "link up: Gen3 x2" again)
#   stop: UFS handler passes climbing with each link cycle (more than 3 in a minute): reboot, record per cycle
# 4. the probe, no SIM (M4.1b step 4) and the state after; lspci status again
#   pass: "SIT GET_SIM_STATUS: error=<n> length=<n>"; with no SIM "SIM card state 0 applications []" (or the
#     short layout / "modem rejected request with error <n>"); FMT tx tail == head; ">TAbort-" still
#   fail: TimeoutError and ">TAbort+" again: the doorbell is still refused; keep the modem up, send the logs
# 5. AT on the RAW buffer: "+CFUN: 0" and OK
# UFS after every step: unchanged except a pass at a link power change (record each)
```

**M4.1f, results (2026-10-13, int `dd6026712`,
`7.3.0-rc6-omamobile-push1-00455-gdd6026712200` = `0470612d2` +
`7a7af33a2`, overlays as M4.1d; no kmsg stream this boot).** "BARs 2-5 on
BAR0's bus address 0x14e00000, as stock"; ROM link Gen1 x1, boot loader
link Gen3 x2, both at try 1; ONLINE, UFS 0; `lspci -b`: Regions 0 and 2-5
at 14e00000, ">TAbort-". About 65 s after ONLINE: every legacy head and
tail 0, both wakeup lines 1, link powered, cp2ap_wakeup interrupts 0,
mif_cp2ap_msg 2052. Probe: TimeoutError, FMT "tx head:24 tail:0",
**">TAbort-" now** (the doorbell read-back completes), MSI count
unchanged. Keep `7a7af33a2` (stock's layout, and the abort is gone); it
did not make the CP take frames.

Where that leaves it: the AP side now matches stock in every register and
step we can see (link Gen3 x2, BAR layout, MSI, doorbell address and
value, shared-memory layout and coherency, the INIT handshake), and the
CP passed INIT_END (it changed its endpoint after it, M4.1e) but never
sends a message, never drops its wakeup line and never takes a frame. The
AP can't see inside the CP; the next steps ask the CP directly:
- the doorbell register itself, read back once (CPIF reads it after
  every doorbell and throws the value away): a value still holding our
  last doorbell (0x10000) means the CP's firmware never serviced the
  interrupt; 0 means it did, and the frames are ignored above that;
- a forced CP crash (`IOCTL_TRIGGER_CP_CRASH`): on the S5300 that goes
  out on the AP2CP_DUMP_NOTI line, not the doorbell. A CRASH_ACK back (an
  MSI, "CP_CRASH_ACK") proves the firmware alive with working MSIs, which
  puts the fault on the doorbell side; "No CRASH_ACK from CP" means the
  firmware hangs as a whole after INIT_END.

```sh
# M4.1g-1 read-only, on the modem ONLINE now (risk: was "low"; it is NOT: see the warning below; one 32-bit
# read of the modem's doorbell register, the access CPIF already makes after every doorbell, and config/log reads)
# !!! DO NOT RUN THIS AGAIN as written. A read of the modem's BAR space while CPIF has the link powered
# !!! down (idle cycling, from M4.1h on) hangs the SoC hard: M4.1h, 2026-10-13, watchdog reset after ~2 min,
# !!! no pstore (section 4). It ran safely here only because this CP never idled. Any BAR access from
# !!! userspace needs, in the same shell and immediately before it: pcie_powered_on:1 in legacy_queues AND
# !!! "link 1" in the host's debugfs status; even then CPIF can power the link down in between, so prefer
# !!! CPIF's own paths (its doorbell read-back runs under its own locks) and config space (lspci/setpci
# !!! go through the host's guarded config accessors and are safe with the link down).
tools/phone-ssh 'dmesg | grep -nE "link down|PHY isolated|no L2 idle|link up|secure ATU" | tail -8;
  C=/sys/devices/platform/cpif; grep -q "pcie_powered_on:1" $C/legacy_queues &&
  grep -q "link 1" /sys/kernel/debug/gs201-pcie-cp/status || { echo "link down: no BAR access"; exit 1; };
  python3 -c "import mmap, os, ctypes
fd = os.open(\"/sys/bus/pci/devices/0001:01:00.0/resource0\", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x61000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
r = ctypes.c_uint32.from_buffer(m, 0x60000)
print(\"doorbell reads %#010x\" % r.value)
del r; m.close(); os.close(fd)";
  lspci -vvv -s 0001:01:00.0 | grep -E "Status:|Masking|Pending|DevSta|UESta"; lspci -vvv -s 0001:00:00.0 | grep -E "Secondary status|UESta|DevSta";
  C=/sys/devices/platform/cpif; cat $C/legacy_queues; cat /sys/kernel/debug/gs201-pcie-cp/status | grep -E "state|link Gen|faults"' | tee logs/m4.1g-1.txt
#   record: the link lines (the one "PHY isolated" should be the ROM link's end at the boot, before the Gen3
#   link up; anything after ONLINE is new); the doorbell value; MSI Pending (a set bit 0/1 = an MSI the CP
#   raised that never got out); the error bits
#   note: the mapping is writable only because ctypes needs that for a 32-bit load; the script only reads.
#   Never use devmem for this (AGENTS: a second argument writes)
#   stop: an Oops, a CP crash; rollback: none

# M4.1g-2 the forced CP crash (asks the human; do it last on this boot, right before the planned reboot;
# risk: medium: the modem goes to its crash state and stays there until the reboot, which powers it off
# as always (one UFS pass); no NV is written (the crash dump is not collected: no cbd runs))
tools/phone-ssh 'grep -E "mif_cp2ap|phone_active|cp2ap_wakeup" /proc/interrupts; python3 -c "import fcntl, os
fd = os.open(\"/dev/umts_boot0\", os.O_RDWR)
try: fcntl.ioctl(fd, 0x6F34, 0)
finally: os.close(fd)"; sleep 12; dmesg | grep -E "cpif|s51xx" | tail -25;
  grep -E "mif_cp2ap|phone_active|cp2ap_wakeup" /proc/interrupts; cat /sys/devices/platform/cpif/modem_state;
  cat /sys/devices/platform/cpif/legacy_queues; dmesg | grep -c ufshcd_err_handler' | tee logs/m4.1g-2.txt
#   expect: "trigger_cp_crash_internal: +++", "SET GPIO AP2CP_DUMP_NOTI = 1", "CP_CRASH_REQ by ...";
#   then either "CP_CRASH_ACK" (an MSI: mif_cp2ap_msg above 2052) and/or a phone_active interrupt and
#   modem_state CRASH_EXIT: the firmware is alive and its MSIs work -> the doorbell side is the fault;
#   or "ERR! No CRASH_ACK from CP" after the timeout: the firmware hangs after INIT_END
#   (the modem unit's watcher records a crash; that is expected here)
#   stop: an Oops; UFS beyond 0 before the reboot
#   rollback: the reboot (planned anyway)
```

**M4.1g, results (2026-10-13, int `dd6026712`, `...00455`; logs
`logs/m4.1g-1.txt`, `m4.1g-2.txt`).**
- M4.1g-1 (read-only): the only link events of the boot are the ROM link
  (Gen1 x1, try 1), its end ("no L2 idle, LTSSM 0x11", "PHY isolated"),
  and the boot loader link (Gen3 x2, try 1); nothing after ONLINE.
  **"doorbell reads 0x00010000"**: our last doorbell still sits in the
  modem's doorbell register, never serviced. ">TAbort-"; MSI Masking
  fffffffc, Pending 0; DevSta, UESta, root port secondary status clean;
  FMT tx 24/0; both wakeup lines 1; host "phy 1/1, link 1, atu 1",
  faults 0, Gen3 x2.
- M4.1g-2 (forced crash): "trigger_cp_crash_internal: +++", "SET GPIO
  AP2CP_DUMP_NOTI = 1", "CP_CRASH_REQ by 9", then after 5 s **"ERR! No
  CRASH_ACK from CP"**, ONLINE -> CRASH_EXIT. No MSI (2052), no
  phone_active or cp2ap_wakeup edge, magic 0xBDBD (CPIF's crash magic,
  written by the AP), UFS 0. The phone was rebooted after (CP off).

So the CP's firmware stops answering anything, its doorbell interrupt and
its DUMP_NOTI line alike, somewhere after INIT_END, without signalling a
crash (phone_active stays high). Stock's CP spends the same 2-4 s after
INIT_END in its own start-up before serving IPC (M4.1d); ours hangs in it.
A hang without a crash report is what a CP core stalled on a bus access,
or stuck in hardware bring-up, looks like.

**What its start-up depends on that differs from the working stack:**
- **The board's hardware id (`ro.boot.cdt_hwid`).** The working stack
  copies it from the phone's own stock properties (section 6.1); we left
  it optional and never set it, and cbd says so on every boot: "CDT
  property invalid", "WRN! cannot fetch cdt values", "WRN! cdt value
  rfid has not been set. Use handover_table", "WRN! cdt value hwinfo has
  not been set", "rfid:0". cbd hands the CP its RF id and hardware info
  in the handover block (IOCTL_HANDOVER_BLOCK_INFO, just before
  POWER_ON); the boot stages don't use them, the main firmware's RF and
  board bring-up after INIT_END does. An RF configuration for the wrong
  (or no) board variant hanging the CP in that bring-up fits everything
  seen. This is the first change: runtime only, one property file.
- Later, one per boot, if that is not it: the AoC voice window (stock's
  `cp_aoc_rmem` 0x197fd000 and CPIF's 0x195fd000; we leave both out, and
  a CP read into AoC SRAM that never completes would stall it); the
  firmware version (the working stack ran g5300q-240919-241106, ours is
  the factory image's g5300q-260317-260505: a newer firmware may need what
  the older didn't); `ro.vendor.cbd.modem_type=s5100sit` (the working
  stack sets it; we pass `-t s5100sit` to cbd instead).
- Ruled out by now: the link (Gen3 x2), the BAR layout, MSI, the
  doorbell's address and value, the shared memory's layout and coherency,
  the packet processor, the AP's sequence and timing to ONLINE, the GPIO
  pins, the AP-status bits, rfsd (the CP never got as far as asking it).

```sh
# M4.1h the board id for cbd (asks the human: writes /var/lib/omamobile-vendor/modem/props.conf, a reboot;
# announce: the modem powers on; risk: medium: the CP gets a hardware id it never had under Linux; it is the
# one stock and the working stack hand it). The value is per phone: never in the repo, a log excerpt or here.
# Before (laptop, private): the value from this phone's own stock getprop capture
#   (~/android/reference/cheetah-stock-cp2a/getprop.txt, "[ro.boot.cdt_hwid]"); don't print it
grep -F '[ro.boot.cdt_hwid]' ~/android/reference/cheetah-stock-cp2a/getprop.txt |
  sed -E 's/^\[ro\.boot\.cdt_hwid\]: \[(.*)\]$/ro.boot.cdt_hwid=\1\npersist.vendor.modem.cdt_hwid=\1/' |
  tools/phone-ssh 'install -d -m 700 /var/lib/omamobile-vendor/modem; f=/var/lib/omamobile-vendor/modem/props.conf;
    touch $f; chmod 600 $f; grep -v cdt_hwid $f > $f.new || true; cat >> $f.new; mv $f.new $f;
    grep -c "^ro.boot.cdt_hwid=." $f; grep -c "^persist.vendor.modem.cdt_hwid=." $f'
#   pass: 1 and 1 (counts only; the value is not shown)
# 1. reboot as M4.1f (same kernel, same overlays); kmsg terminal; lsmod 0, err_handler 0
# 2. the modem to ONLINE (M3.4.5b step 4). In the unit's journal, check cbd's lines, without quoting values:
tools/phone-ssh 'journalctl -u omamobile-modem --no-pager | grep -E "\[cbd\]" | grep -ciE "CDT property invalid|cannot fetch cdt|has not been set"'
#   pass: 0 (cbd found the CDT values); "rfid:" no longer 0 (look, don't paste); ONLINE as before
#   stop: cbd refuses or fails earlier than before (record the step names, not values); the CP not ONLINE
#   rollback: remove the two lines from the props file; reboot
# 3. a minute after ONLINE, read-only, as M4.1f step 3 (legacy_queues, interrupts, link lines, UFS)
#   expect if it was this: stock's pattern by itself (an rx head off 0, MSIs above the boot's count,
#   cp2ap_wakeup interrupts, link power-downs); UFS check as before
# 4. the probe, no SIM, and the after-state (M4.1f step 4); 5. AT on the RAW buffer
#   pass: a "SIT GET_SIM_STATUS: error=<n> length=<n>" line; FMT tx tail == head
#   fail: TimeoutError again: read the doorbell register (M4.1g-1) and stop; the AoC window is next
# UFS after every step: unchanged except a pass at a link power change (record each)
```

**M4.1h, results (2026-10-13, int `aca2c8163`,
`7.3.0-rc6-omamobile-push1-00457`, same kernel and overlays as M4.1g, a
fresh boot, the board id in `/var/lib/omamobile-vendor/modem/props.conf`;
log `logs/m4.1h-probe.log`): PASSED, IPC works.**
- cbd: "cdt property fetched from ro.boot.cdt_hwid", "Update handover
  block info", "handover block v1"; still "WRN! cdt value rfid has not
  been set. Use handover_table.", "WRN! cdt value hwinfo has not been
  set.", "rfid:0" (see below). ONLINE, UFS 0.
- About 60 s after ONLINE, by itself, stock's pattern: FMT rx head 2704 =
  tail (indications delivered), NORM_RAW tx 10656/10656 and rx
  672408/672408 (rfsd's traffic both ways), **cp2ap_wakeup:0
  ap2cp_wakeup:0 pcie_powered_on:0** (the idle link power-down),
  cp2ap_wakeup interrupts 13, mif_cp2ap_msg 2397 (2052 at the boot), UFS 0.
- Probe (no SIM): "SIT GET_SIM_STATUS: error=0 length=80", "SIM card
  state 0 applications []" (absent); "GET_RADIO_POWER: error=0", "radio
  state 3" (POWER_OFF, MODEM-SIT-RESEARCH 3.1: the radio is off);
  "GET_PS_REG_STATE: error=0", "packet registration state 0 reject 0 RAT
  0"; "GET_NR_MODE: error=0", "NR mode [3]"; "GET_PS_SERVICE: error=0",
  "PS service [1]"; "GET_SMSC_ADDR: error=11" (no SIM: expected). FMT tx
  144/144, rx 3024/3024 after.
- Then an operator error, recorded as a hazard (section 4): the M4.1g-1
  doorbell read (an mmap of BAR0) run while the link was powered down
  hung the SoC; the watchdog reset it about 2 minutes later, no pstore.
  The modem was off on the next boot (no modem start); M3.5 before M4.1i.

**The rfid/hwinfo warnings are benign.** cbd takes rfid and hwinfo from
the modem image's `hardware_config.json` ("Pick HW config path from
config table", `persist.vendor.modem.hw_config.json_table`), and this
factory image has none: `images/g5300q-260317-260505-B-15346003/` holds
only `modem.bin`, `confpack`, `uecap` and `pw_token_db*` (listed from the
private backup's ext4, nothing extracted), as the working stack also
noted. So cbd falls back ("Use handover_table") on stock exactly as here;
the board's own values reach the CP through the handover block built from
the CDT id and the bootloader's `/chosen/plat` (rfid, modem_hw, modem_sku,
which our profile binds read-only). What was missing before M4.1h was the
CDT id itself ("CDT property invalid", "cannot fetch cdt values"). The
"rfid:0" line is cbd's log of the config-table value it didn't find.

**`omamobile-modem` 0.1.10 and `modem check` as a health check:** the check
refuses once the profile has started in this boot, so the line below is a
post-install health check only before the modem is started, or after a
reboot. It stays read-only, and its refusal ("the modem profile already
started this boot") says the profile ran, not that the install is wrong.

**`omamobile-modem` 0.1.4:** the board id is a required per-phone input.
The profile's check (`omamobile-vendor-chroot modem check`, run by the
unit before the hang marker) refuses to start without a non-empty
`ro.boot.cdt_hwid` in `/var/lib/omamobile-vendor/modem/props.conf`, or with
a `persist.vendor.modem.cdt_hwid` that differs from it; the install
script says so on install and warns on upgrade. The value is copied from
this phone's own stock getprop (the M4.1h one-liner); it never goes into
the repo, a log excerpt or this plan. Tests cover the check with made-up
values.

```sh
# M4.1i a clean repeat, the full read-only probe, ten minutes idle (asks the human: install 0.1.4 and a reboot;
# announce: the modem powers on and then idles its link; risk: low-medium: link power cycles under load of
# nothing, each a possible UFS handler pass)
# NO BAR ACCESS from userspace in this step or after (section 4). Config space (lspci) is fine.
# 0. M3.5 (read-only): the six partitions against the backup, as M3.4.0; no diff
# 1. install 0.1.4 (the board id file stays as M4.1h wrote it)
tools/phone-install-package packages/omamobile-modem
tools/phone-ssh 'pacman -Q omamobile-modem; /usr/lib/omamobile-vendor/omamobile-vendor-chroot modem check | tail -2'
#   pass: 0.1.4; "preconditions met" (with the id; without it the check names the missing property)
# 2. reboot, same kernel and overlays as M4.1h; kmsg terminal into logs/m4.1i-kmsg.log; lsmod 0, err_handler 0
# 3. the modem to ONLINE (M3.4.5b step 4); pass as M4.1h (cbd fetches the CDT id; ONLINE; UFS 0)
# 4. the probe at once, then AT, read-only
tools/phone-ssh 'timeout 60 omamobile-sitd --probe' 2>&1 | tee logs/m4.1i-probe.log
#   pass: every request "error=0" except GET_SMSC_ADDR (error 11 without a SIM); "SIM card state 0
#   applications []"; "radio state 3" (POWER_OFF); "packet registration state 0 ..."
tools/phone-ssh 'cd /usr/lib/omamobile-sit && timeout 20 python3 -c "import os, at, paths
fd = paths.open_channel(paths.ROUTER)
try: print(repr(at.exchange(fd, at.COMMANDS[\"radio-state\"], 8)))
finally: os.close(fd)"'
#   pass: "+CFUN: 0" and OK (the radio off as SIT says; quote only those)
# 5. ten minutes idle: count link power cycles and UFS handler passes (read-only)
tools/phone-ssh 'u0=$(dmesg | grep -c ufshcd_err_handler); d0=$(dmesg | grep -c "PHY isolated"); sleep 600;
  u1=$(dmesg | grep -c ufshcd_err_handler); d1=$(dmesg | grep -c "PHY isolated");
  echo "link power-downs: $((d1-d0)), UFS handler passes: $((u1-u0))";
  grep -E "mif_cp2ap|cp2ap_wakeup" /proc/interrupts; cat /sys/devices/platform/cpif/modem_state;
  cat /sys/devices/platform/cpif/legacy_queues | grep -E "FMT|NORM_RAW|wakeup"' | tee logs/m4.1i-idle.txt
#   record: power-downs per 10 min, UFS passes per 10 min (expect 0: M4.1h saw none over its cycles); still ONLINE
#   stop: UFS passes rising with the cycles (more than one per ten cycles, or any I/O, ext4 or reset line): stop
#     the step and report: the next change is a link policy (keep the link up while the modem runs), offline
# 6. the probe once more after the idle period (it wakes the link): the same pass as 4.; one UFS check
# 7. M3.5 (read-only) at the end; leave the modem up or reboot as the human prefers (a reboot: one UFS pass)
```

**M4.1i, results (2026-10-13; logs `logs/m4.1i-*`): PASSED.** The
probe five times "error=0" (SIM absent, radio state 3), `AT+CFUN?` "+CFUN:
0" and OK; after ten minutes idle still ONLINE, 0 UFS handler passes, no
I/O errors; the second probe again five times "error=0"; M3.5 before and
after unchanged. The link power-down count came out -10: `dmesg` had
wrapped during the ten minutes, so a difference of two `dmesg | grep -c`
counts is no measure. Count from the kmsg stream (`dmesg -w | tee`,
started before the modem) or from a counter that doesn't wrap: the
interrupt counts in `/proc/interrupts` (cp2ap_wakeup counts both edges of
each idle cycle) or CPIF's `/sys/devices/platform/cpif/modem/power_stats`.
Then `bin/omamobile push` rebooted the phone with the modem ONLINE and
its link idle, and it hung (section 4).

```sh
# M4.1j the guarded kernel, and the reboot it fixes (asks the human: reboots; the human at the phone for
# step 4; risk: medium: a reboot with the modem up, the case that hung)
# Before (laptop): the human merges omamobile-modem (4b1364136 or later) into omamobile-int, builds it.
# 1. push it the attended way: the modem must not be running on the current boot (it isn't after a
#    forced restart), or the push's reboot can hang as in M4.1i. Kmsg terminal into logs/m4.1j-kmsg.log
# 2. the modem to ONLINE (M3.4.5b step 4) and the probe (M4.1i step 4): pass as M4.1i
# 3. wait for an idle link: read-only, config space and CPIF's files only (no BAR access)
tools/phone-ssh 'for i in $(seq 30); do grep -q "pcie_powered_on:0" /sys/devices/platform/cpif/legacy_queues && break; sleep 2; done;
  grep -E "wakeup|powered" /sys/devices/platform/cpif/legacy_queues; dmesg | grep -c ufshcd_err_handler'
#   pass: "pcie_powered_on:0" (the link is down, the PHY isolated): the state that hung
# 4. the reboot, attended (announce: a reboot; if the phone hangs, Power held ~30 s, then Power)
tools/phone-ssh 'sync; (sleep 1; reboot-to omamobile) >/dev/null 2>&1 &'
#   pass: the phone comes back on its own within the usual time (USB, ssh); then, from the previous boot's
#     kmsg log: "PHY isolated" before the reboot, "s51xx PCIe Remove!!!", and no hang
#   expect: one recovered UFS handler pass after the modem's power-off (M2.6), in the new boot's count 0
#   stop: a hang again (force restart): record the last kmsg lines; next step offline (where else the
#     shutdown touches the controller)
# 5. M3.5 (read-only)
```

**M4.1j, results (2026-10-13, `7.3.0-rc6-omamobile-push1-00511-g9626f17f7825`;
logs `logs/m4.1j-*`): PASSED.** M3.5 before: the six partitions match the
2026-10-13 backup. M3.4.3: "preconditions met", PMU 0x3ec0 0x0, faults 0x0.
`systemctl start omamobile-modem`: ONLINE within 60 s, 0 UFS handler
passes. The probe (with `omamobile-modem-sit` 0.2.0, which the reinstall
leaves out on purpose): five requests "error=0", GET_SMSC_ADDR error 11
(no SIM), "SIM card state 0 applications []", "radio state 3". The link
went idle ("pcie_powered_on:0", 0 UFS passes), then `reboot-to omamobile`:
the kmsg stream shows "PHY isolated (PMU 0x3ec0 = 0x0)" before the reboot,
"s51xx PCIe Remove!!!", `power_shutdown_cp` and the AP2CP power-off GPIO
edges, and the phone was back on SSH in about 25 s with no hang and no
power key. New boot: 0 UFS handler passes, no failed units. M3.5 after:
unchanged. Left on the shutdown path, not fatal: two WARNs in
`device_shutdown` from `gs201_pcie_cp_shutdown`:
`irq_domain_remove+0xf0` (kernel/irq/irqdomain.c:408) and
`msi_device_data_release+0x44` (kernel/irq/msi.c:294), i.e. the MSI
domain is torn down while s51xx's vectors are still allocated. Next,
offline: free the endpoint's vectors (or remove the root bus) before
the domain in the shutdown path, then a second attended M4.1j run.

**M4.1k, offline (2026-10-13): the WARNs are CPIF's, not the host
driver's.** Both traces run through `device_release_driver` of the
S5300 function inside `pci_stop_root_bus`, before
`gs201_pcie_cp_remove()` gets to `dw_pcie_free_msi()`: the host driver
already removes the bus before its own MSI domain. What goes is the
endpoint's per-device MSI domain, a devres of the `pci_dev` released when
s51xx unbinds, and it still holds the four vectors that
`request_pcie_int()` allocated on the first power-on: `s51xx_pcie_remove()`
never freed them, nor the two doorbell handlers on them, and it left
`mc->s51xx_pdev` pointing at the `pci_dev` the bus removal frees (which
`power_shutdown_cp()` reads a moment later). `omamobile-modem` `7b2b87cb7`
frees the handlers (and their wake setting), then the vectors, and
forgets the `pci_dev`; `d34bbbad4` drops the unpaired
`pci_release_regions()` behind the "Trying to free nonexistent resource
<0x40000000-0x400fffff>" line just before the first WARN. With the link
idle the masking this adds is dropped by the host driver (config space
refused, DBI skipped while the PHY is isolated, `4b1364136`); no BAR or
ELBI access is added. Build `7.3.0-rc6-omamobile-push1-00370-gd34bbbad467d`
in `out-modem`, W=1 clean on `s51xx_pcie.c` and `modem_ctrl_s5100.c`,
checkpatch clean.

```sh
# M4.1k the shutdown without WARNs (asks the human: a push and two reboots; the human at the phone for
# step 4; risk: medium: a reboot with the modem up, the path M4.1i hung on and M4.1j fixed)
# NO BAR ACCESS from userspace (section 4). Config space and CPIF's sysfs files only.
# Before (laptop): the human merges omamobile-modem (d34bbbad4 or later) into omamobile-int and builds it
#   (explicit KERNEL_DIR/KERNEL_OUT). The phone runs 00511 (int 9626f17f7) or a later int without the modem.
# 0. M3.5 (read-only): the six partitions against the backup, as M3.4.0; no diff
#   stop: any diff (stock booted since? take a fresh backup first, AGENTS.md section 1)
# 1. push, the attended way: the modem must not be running on the current boot (it isn't unless started),
#    so the push's reboot is the ordinary one. Kmsg terminal into logs/m4.1k-kmsg.log before step 2
bin/omamobile push
tools/phone-ssh 'uname -r; dmesg | grep -c ufshcd_err_handler; lsmod | grep -c "^cpif "'
#   pass: the new release; err_handler 0; cpif 0 (not loaded yet)
#   stop: no SSH within the usual time: wait for the reboot watchdog, then the human's force restart;
#     rollback below
# 2. the modem to ONLINE (M3.4.5b step 4) and the probe (M4.1i step 4): pass as M4.1j
# 3. wait for an idle link (M4.1j step 3, read-only)
#   pass: "pcie_powered_on:0"; err_handler count unchanged
# 4. the reboot, attended (announce: a reboot; if the phone hangs, Power held ~30 s, then Power)
tools/phone-ssh 'sync; (sleep 1; reboot-to omamobile) >/dev/null 2>&1 &'
#   pass: back on SSH on its own (M4.1j: about 25 s); in logs/m4.1k-kmsg.log after "s51xx PCIe Remove!!!":
#     no "WARNING:", no "Trying to free", no "already-free IRQ", no "Unbalanced", no oops, then
#     power_shutdown_cp and the AP2CP power-off edges as in M4.1j
grep -nE "WARNING:|Trying to free|already-free|Unbalanced|Unable to handle|Internal error" logs/m4.1k-kmsg.log
#   pass: no line at or after "s5100_reboot_handler" (quote any line found, nothing else)
#   expect: the new boot's err_handler count 0
#   stop: a hang (force restart; record the last kmsg lines), an oops, or a new WARN in the shutdown path:
#     record its first trace and stop; the next step is offline
# 5. M3.5 (read-only): unchanged
#   stop: any diff: no more modem runs until it is explained
# Rollback: push the previous int build again (00511, int 9626f17f7: M4.1j's, two WARNs at shutdown but no
#   hang), or merge int without 7b2b87cb7/d34bbbad4; the modem must be stopped (or never started) on the
#   boot that the push reboots. If slot B does not come up, slot A is stock as always.
```

**M4.1k, results (2026-10-13, `7.3.0-rc6-omamobile-push1-00514-g9938ea8b8b8d`,
int `9938ea8b8` = 00511 plus `omamobile-modem` through `d34bbbad4`; logs
`logs/m4.1k-*`): PASSED.** Pushed with the modem off; the boot came up
with 0 failed units and 0 UFS handler passes. M3.5 before: unchanged.
Modules and preconditions as M4.1j; `systemctl start omamobile-modem`:
ONLINE within 60 s, 0 UFS passes; the probe five times "error=0" plus
GET_SMSC_ADDR error 11 (no SIM), radio state 3. Idle link
("pcie_powered_on:0"), then `reboot-to omamobile`: the kmsg stream shows
"s51xx PCIe Remove!!!" and `power_shutdown_cp` and **no WARNING, no
"Trying to free nonexistent resource", no oops**; back on SSH in 23 s.
New boot: 0 failed units, fingerprint listed, AoC, speaker protection,
the four sensors and Wi-Fi up. M3.5 after: unchanged. Published as
linux-omarchy-mobile `omamobile-int` snapshot `c237ad9d1`.

**Before M4.2:** M4.1i passed; a SIM with its PIN lock off in the phone
(M4.2's preconditions), the carrier's APN in
`/etc/omamobile/modem-sit.conf` (M4.0). M4.2's own expectations above are
unchanged; with the CP's start-up fixed they apply as written. Open,
not blocking M4.2: suspend with the modem up (CPIF's PM paths, section
6.3), and whether the link's idle cycles stay UFS-clean over hours.

**M4.2 needs a SIM**: registration waits for GET_SIM_STATUS to show a
ready USIM (`sim_timeout`, 120 s) and fails without one. With no SIM,
M4.1b is the last M4 step. With one: "M4.2-M4.7: the first SIM test"
below.

### T0/T1: the ModemManager bridge (`omamobile-modem-sit` 0.3.0, `omamobile-mmd` 0.1.0)

[TELEPHONY-APPS-PLAN](../../docs/TELEPHONY-APPS-PLAN.md) phases T0 and T1:
`omamobile-mmd` owns `org.freedesktop.ModemManager1` and serves MM 1.24's
API from `omamobile-sitd`'s socket, so GNOME Calls, Chatty, mmsd-tng and
NetworkManager see a modem. sitd stays the only process that talks to the
modem; the bridge never starts it or the modem.

**T0 (sitd 0.3.0, offline):** a `subscribe` request (the full status at
once and after every change; MODEM-CLIENT section 2); the SIM state
(card and application state, PIN/PUK retries, never an AID, label, ICCID
or IMSI) and the radio state from GET_SIM_STATUS and GET_RADIO_POWER in
the 30 s poll (both already allow-listed and used by `--probe`), plus
IND_RADIO_STATE_CHANGED and IND_SIM_STATUS_CHANGED read passively; the
emergency numbers of TS 22.101 10.1.1. **No new SIT request.** Hold,
swap, conference, call waiting, signal strength and SIM PIN stay for
T8: each is a request that has never met our firmware, and none can be
tested without a SIM. `tools/sit-sim` gained a `--control` socket (ring,
remote hang-up, SMS, WAP push) and answers, DTMF and the research
note's radio-state values.

**T1 (`omamobile-mmd` 0.1.0):**

- Python with PyGObject's Gio (owner's Q3), not dbus-fast: python-gobject
  is on the phone already, Gio answers Get/GetAll/Introspect from the
  interface XML, and the method handler gets the caller's bus name for
  polkit.
- Interfaces: Manager + ObjectManager, Modem, Modem3gpp, Simple,
  Location, Messaging, Signal, Voice; Sim, Bearer (read-only), Sms, Call.
  Names and signatures written out from MM 1.24.2 (tag `1.24.2`,
  `f2b9ab1ad78d`); `test/test_api.py` compares them with MM's own
  introspection XML: identical. Everything not possible yet returns MM's
  `Error.Core.Unsupported`.
- States as MM: no SIM is FAILED/sim-missing with Modem, 3GPP, Voice and
  Location only and `Voice.EmergencyOnly` set; `Enable` is refused
  (WrongState). Emergency numbers are refused at `CreateCall` with a
  clear error (TELEPHONY-APPS-PLAN section 3). IMEI, IMSI and ICCID stay
  empty (Q9). A WAP push is an Sms with Text empty and Data set
  (mmsd-tng's rule; ofono2mm lacks Data).
- Package of its own (it takes over MM's bus name, policy and polkit
  actions, which the RIL alone must not): `conflicts=(modemmanager)`, no
  `provides=` (gnome-calls 51.1, chatty 0.8.9, networkmanager and geoclue
  depend on libmm-glib only; mmsd-tng is AUR-only, libmm-glib too).
  The unit is not enabled, `Conflicts=ModemManager.service`, requires
  nothing, starts with `omamobile-sitd` once enabled; no D-Bus
  activation file, so no client can start it.
- Offline: `packages/omamobile-mmd/test/all` (private dbus-daemon: the
  bridge against a fake sitd, libmm-glib as the client, polkit with a
  fake authority, and the chain down to `tools/sit-sim`) green;
  `test/conformance` (container, Xvfb): mmcli, GNOME Calls 51.1 and
  Chatty 0.8.9, 43 checks pass. Calls finds the modem, answers, sends
  DTMF, hangs up and dials; Chatty receives an SMS, stores it and
  deletes it on the modem. The conformance run found that listing
  `org.freedesktop.DBus.*` in `GetManagedObjects` crashed GNOME Calls
  (libmm-glib gives those no interface info); they are left out.

```sh
# T1 on the phone, no SIM (risk: low-medium: one modem start; the radio stays off)
# 0. M3.5 (read-only) as M3.4.0, into logs/t1-m3.5-before.sha256: no diff against the 2026-10-13 backup
# 1. install, enable nothing (packages built locally with tools/build-packages)
tools/phone-ssh 'cat > /tmp/s.pkg.tar.zst' < out/repo/aarch64/omamobile-modem-sit-0.3.0-1-aarch64.pkg.tar.zst
tools/phone-ssh 'cat > /tmp/m.pkg.tar.zst' < out/repo/aarch64/omamobile-mmd-0.1.0-1-aarch64.pkg.tar.zst
tools/phone-ssh 'OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -U --noconfirm /tmp/s.pkg.tar.zst /tmp/m.pkg.tar.zst;
  systemctl is-enabled omamobile-sitd omamobile-mmd omamobile-modem'
#   pass: 0.3.0, 0.1.0; "disabled" three times
# 2. kmsg terminal (logs/t1-kmsg.log), M3.4.3, dead-man, the modem to ONLINE (M3.4.5b step 4), the probe (M4.1i step 4)
# 3. sitd WITHOUT its start-up (no SIM: --bringup would wait for one), then the bridge
tools/phone-ssh 'systemd-run --unit=x-sitd -p Type=notify -p NotifyAccess=main /usr/bin/omamobile-sitd;
  systemctl start omamobile-mmd; journalctl -u omamobile-mmd -b -o cat | tail -3'
#   pass: "Modem .../Modem/0 exported: state -1, failed reason sim-missing, SIM absent, radio off"
tools/phone-ssh python3 - < packages/omamobile-mmd/test/libmm-status.py
tools/phone-ssh 'nmcli -f DEVICE,TYPE,STATE device; gdbus call --system -d org.freedesktop.ModemManager1
  -o /org/freedesktop/ModemManager1/Modem/0 -m org.freedesktop.ModemManager1.Modem.Enable true'
#   pass: failed / sim-missing / power low; NM: umts_ipc0 gsm unavailable; Enable: WrongState
#   stop: any AT command or SIT request beyond GET_SIM_STATUS, GET_RADIO_POWER, GET_PS_REG_STATE in the sitd journal;
#     UFS handler passes; a CP crash
# 4. stop the bridge and sitd; cancel the dead-man; the modem stays ONLINE until the next reboot (the M4.1k path)
tools/phone-ssh 'systemctl stop x-modem-deadman.timer omamobile-mmd x-sitd'
# 5. M3.5 (read-only) again; ufshcd_err_handler again about 10 minutes later
# rollback: pacman -U the previous omamobile-modem-sit; pacman -R omamobile-mmd
```

**T1 on the phone, results (2026-10-14,
`7.3.0-rc6-omamobile-push1-00545-g3f9a2a5aba8e`; logs `logs/t1-*`):
PASSED.** M3.5 before: the six partitions match the 2026-10-13 backup,
all six `ro=1`, none mounted. Installed `omamobile-modem-sit` 0.3.0 and
`omamobile-mmd` 0.1.0, nothing enabled. M3.4.3: "preconditions met",
PMU 0x3ec0 0x0, faults 0x0. The modem ONLINE within 60 s, the marker
cleared, 0 UFS handler passes. The probe as M4.1i (five requests
`error=0`, GET_SMSC_ADDR error 11, "SIM card state 0 applications []",
radio state 3). sitd without `--bringup` served at once; its journal
shows only GET_SIM_STATUS, GET_RADIO_POWER and GET_PS_REG_STATE; its
status: SIM absent, radio off, not registered. The bridge exported
`/org/freedesktop/ModemManager1/Modem/0`: State -1 (FAILED),
StateFailedReason 2 (sim-missing), PowerState 2 (low), Sim `/`,
interfaces Modem, Modem3gpp, Voice, Location; Voice EmergencyOnly true,
no calls; IMEI and equipment identifier empty; `Version` "1.24.2";
`Enable` refused with `Error.Core.WrongState: Modem in failed state:
sim-missing`. libmm-glib on the phone (`test/libmm-status.py`, mmcli
isn't installed) shows the same. **NetworkManager** created a `gsm`
device `umts_ipc0`, "unavailable", and logged "modem state 'failed'" and
"No SIM object available", as with MM itself (and a harmless "error
setting IPv4 forwarding" warning: `umts_ipc0` is a character device,
not a netdev). As the phone's user: properties readable, `Modem.Command`
refused by the bus policy. Bridge and sitd stopped cleanly; no kernel
WARN or oops, no failed units. **The modem was left ONLINE** (link idle,
`pcie_powered_on:0`) until the next reboot, the path M4.1j/k proved,
because a unit stop with the link idle has not been run on this kernel
yet. M3.5 after: unchanged. About 12 minutes after ONLINE
(12:29): still ONLINE, 0 UFS handler passes, no kernel WARN or oops,
cp2ap_wakeup interrupts counting (the idle link cycling).

**Next (T2) needs the SIM:** with a SIM (PIN lock off) and the APN, the
runbook below (S7 is M4.2, sitd `--bringup`; S11 the bridge and the apps). Before that, nothing more can be learned on
hardware: registration, calls, SMS and the WAP push path all wait on
M4.2-M4.4.


### M4.2-M4.7: the first SIM test (gated runbook, written 2026-10-25)

**This is the runbook to follow when the SIM arrives.** It replaces the
M4.0 and M4.2-M4.7 steps in the M4 section above (written for
`omamobile-modem-sit` 0.2.0, before M4.1-M4.1k). M4.1-M4.1k and T1 passed
without a SIM; everything below is the first time the radio transmits.

**What is ready (offline, 2026-10-25):** `omamobile-modem` 0.1.4 (on the
phone since M4.1h), `omamobile-modem-sit` 0.3.3 and `omamobile-mmd` 0.1.0,
all with their `test/all` green against `tools/sit-sim`. 0.3.1-0.3.3 add,
for this test: a PIN-, PUK- or network-locked SIM stops start-up within
10 s with what to do (nothing is ever sent to unlock it); an IMS failure
keeps data instead of ending start-up (`[network] ims_required = no`);
**no call audio by default** (`[audio] card = none`), and with a card,
audio is refused unless the top amplifier (the earpiece) is at analog 6 or
less and both are within the media stage; the simulator now carries a
SIM AID, label and IMS identity, and the tests prove none reaches a log or
a status.

**What to expect, honestly:**

| Step | Expectation | Why |
|---|---|---|
| SIM detection (M4.2a) | likely | GET_SIM_STATUS answered `error=0` on every probe since M4.1h |
| LTE registration (M4.2) | likely on a T-Mobile-network SIM; unverified elsewhere | the start-up order is the one that registered this phone model, on a T-Mobile-network MVNO (MODEM-CLIENT 1.3) |
| Data (M4.3) | likely if the bearer has IPv4 | rmnet0 is configured IPv4 only (MODEM-CLIENT 1.3); an IPv6-only bearer (`PDP type 2` in the journal) can't pass yet |
| IMS registration, SMS (M4.2, M4.4) | possible on a T-Mobile-network SIM; unlikely elsewhere | the IMS values were proven on that one network; on any other, IMS is the likeliest step to fail (data stays up since 0.3.2) |
| Calls (M4.5) | may ring and connect, **with no audio** either way | call audio is M5: the AoC voice path and an earpiece mode under speaker protection (TELEPHONY-APPS-PLAN T4). Nothing in the call path touches an amplifier while `[audio] card = none` |
| Emergency calls | **never**: refused by the RIL and the bridge | MODEM-CLIENT 1.3; keep another phone for emergencies |
| MMS, NR (5G), the eSIM, suspend with the modem on | not part of this test | T3; `nr = off`; the RIL speaks only to the physical slot (`umts_ipc0`); MODEM-PLAN 6.3 |

About one fresh CP start in twenty crashed during registration on this
phone model (section 4): a crash is recorded, and a reboot recovers it.
**A second start-up on the same CP is not supported**: after any failed
step, reboot before the next try. Every reboot with the modem up powers
it off: one recovered UFS error-handler pass, expected (M2.6, not yet
attributed to an edge; M4.1j/M4.1k proved the reboot itself clean).

**Never in the repository, a log excerpt or a screenshot:** the phone
number, the IMSI, the ICCID (it's printed on the SIM card), the IMEI, the
carrier's name, the APN (TELEPHONY-APPS-PLAN Q8), IP addresses, message
text, the other phone's number. sitd logs states and codes only; cbd and
rfsd log through our shim. Before quoting any log, grep it:
`grep -nE '[0-9]{7,}|\+[0-9]|[0-9a-f]{2}(:[0-9a-f]{2}){5}|@' logs/<file>` must
show nothing you'd quote.

**Before buying (the human):** a physical nano-SIM, prepaid, ideally on
the T-Mobile network (section "Which SIM" in MODEM-CLIENT 1.4). Note down
privately, off the repository: the internet APN exactly as the carrier
publishes it (and whether it is the same APN for MMS), the IMS APN if the
carrier names one (most use `ims`), the SIM's default PIN and PUK (on the
card holder), the phone number, and how to activate it.

```sh
# S0 laptop, before the SIM (risk: none). Packages and tests.
packages/omamobile-modem-sit/test/all && packages/omamobile-mmd/test/all && tools/pr-check
tools/build-packages packages/omamobile-modem-sit     # -> out/repo/aarch64/omamobile-modem-sit-0.3.3-1-aarch64.pkg.tar.zst
#   pass: all ok. The kernel the phone runs must contain omamobile-modem through d34bbbad4 (M4.1k):
git -C <int worktree> merge-base --is-ancestor d34bbbad4 <the sha in `tools/phone-ssh uname -r`> && echo has-M4.1k
#   stop: no "has-M4.1k": push an int build with it first (the modem must not be running on that boot)

# S1 activate and unlock the SIM in ANOTHER phone (the human; risk: none for this phone)
#   Activate it as the carrier says; make one call or send one SMS from that phone so the line is live;
#   turn the SIM PIN lock OFF there (the RIL has no PIN entry; 0.3.1 stops with "SIM PIN lock is on").
#   Don't use this phone's stock Android (slot A) for it: a stock boot rewrites efs, persist and
#   modem_userdata, and then the profile refuses the stale RAM-copy checksums until a fresh backup
#   (AGENTS.md section 1; M3.4.4). If slot A is used anyway: fresh read-only backup, new
#   /etc/omamobile/modem-nv.sha256 (M3.4.1), before S4.

# S2 install and configure, phone still without SIM (asks the human: installs; risk: none)
tools/phone-ssh 'systemctl is-active omamobile-modem omamobile-sitd omamobile-mmd'
#   pass: inactive x3 (nothing modem is running this boot). Else: reboot first (M4.1j path)
tools/phone-ssh 'cat > /tmp/s.pkg.tar.zst' < out/repo/aarch64/omamobile-modem-sit-0.3.3-1-aarch64.pkg.tar.zst
tools/phone-ssh 'OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -U --noconfirm /tmp/s.pkg.tar.zst; pacman -Q omamobile-modem
  omamobile-modem-sit omamobile-mmd; systemctl is-enabled omamobile-modem omamobile-sitd omamobile-sit-data omamobile-mmd;
  ls /etc/omamobile/modem-sit.conf.pacnew 2>/dev/null'
#   pass: 0.1.4, 0.3.3, 0.1.0; "disabled" x4. A .pacnew: merge it (keep card = none, the new ims_* keys)
# the APN: typed by the human on the phone or through ssh; never pasted into a log
tools/phone-ssh 'sed -i "s/^apn =.*/apn = <APN>/" /etc/omamobile/modem-sit.conf'
tools/phone-ssh 'grep -cE "^apn = .+" /etc/omamobile/modem-sit.conf;
  grep -E "^(ims|ims_apn|ims_required|nr|card) " /etc/omamobile/modem-sit.conf'
#   pass: 1; ims = yes, ims_apn = ims (or the carrier's IMS APN), ims_required = no, nr = off, card = none
#   stop: card is anything but none (call audio is M5)
#   rollback: pacman -U the previous package (0.3.0 is in the phone's pacman cache)
# Keep the phone on the charger for the whole test: upower's critical action suspends the phone
# (NOTES 2026-10-18), and suspend with the modem on is untested (section 6.3). Don't toggle airplane
# mode or `nmcli radio wwan` while the bridge runs: that reaches AT+CFUN=0, and the radio may not
# register again until a reboot.

# S3 insert the SIM with the phone off (the human; risk: low)
#   Power-off isn't proven from Linux on this phone (`systemctl poweroff` never ran here). Instead:
#   hold Volume Down + Power about 20 s (fastboot, AGENTS.md section 1), choose "Power off" in the
#   bootloader menu (volume keys, Power to confirm). Eject the tray with the SIM tool, nano-SIM in
#   the tray as its outline shows, tray fully in. Power on with the Power key.
#   No hot insertion: SIM hot-plug has never run under Linux, and start-up waits only 120 s for the SIM.
tools/phone-ssh 'uname -r; grep -oE "androidboot.slot_suffix=_[ab]" /proc/cmdline; systemctl --failed --no-legend | wc -l;
  dmesg | grep -c ufshcd_err_handler'
#   pass: the expected int release; "_b" (or nothing, as tools/phone-smoke allows); 0; 0
#   stop: it came up in stock Android (slot A fallback): power off, eject nothing, boot slot B again, and
#     take a fresh read-only backup before S4 (AGENTS.md section 1)

# S4 M3.5 before (read-only; risk: none): the six partitions against the newest backup, as M3.4.0
#   into logs/sim-m3.5-before.sha256. pass: no diff, 5x "ro=1 mounted=0". stop: any diff (AGENTS)

# S5 log streams, then the modem to ONLINE (announce: the modem powers on and stays on; risk: medium)
tools/phone-ssh dmesg -w | tee logs/sim-kmsg.log                       # terminal 2, before anything else
tools/phone-ssh 'journalctl -f -o short-monotonic -u omamobile-modem -u omamobile-sitd -u omamobile-sit-data
  -u omamobile-mmd' | tee logs/sim-journal.log                         # terminal 3
tools/phone-ssh 'systemd-run --unit=x-modem-deadman --on-active=300 systemctl stop omamobile-modem'
tools/phone-ssh 'rm -f /var/lib/omamobile/modem-bringup-started; sync; systemctl start --no-block omamobile-modem;
  sleep 60; /usr/lib/omamobile-vendor/omamobile-modem-cp state; dmesg | grep -c ufshcd_err_handler'
#   pass: ONLINE, as M4.1k (one POWER_ON, ROM link Gen1 x1, main link Gen3 x2, "CP ONLINE (cbd exit 0)");
#     err_handler unchanged
tools/phone-ssh 'systemctl stop x-modem-deadman.timer'                 # only once ONLINE was seen
#   stop: not ONLINE within 5 minutes (the dead-man stops the unit: one UFS pass); collect as M3.4.5, reboot
#   rollback: reboot

# S6 = M4.1 with the SIM: the read-only probe; the radio stays off (risk: low)
tools/phone-ssh 'timeout 60 omamobile-sitd --probe' 2>&1 | tee logs/sim-m4.1-probe.log
#   expect: every request "error=0"; "SIM card state 1 applications [(2, 5), ...]" (a USIM, READY; an ISIM
#     (5, x) may be listed too); radio state 3 or 1; packet registration state 0; "SMSC present True"
#   record: the application list (types and states only), radio state, NR mode
#   stop: card state 0 again (no SIM seen: tray, contacts; power off and reseat; never hot-plug);
#     the USIM (2, 2) = PIN lock on: back to S1 (power off, the other phone); (2, 3) = PUK: S1, never guess;
#     (2, 4) = network lock: the carrier; a timeout or a CP crash: collect, reboot
#   rollback: none (read-only)

# S7 = M4.2 registration and IMS (announce: the radio transmits from now until reboot or `radio off`;
#   risk: medium: first registration; about 1 in 20 fresh starts crashed the CP here on this model)
tools/phone-ssh 'systemctl start --no-block omamobile-sitd'
#   watch terminal 3 until "Calls and SMS service ready" or a failure (allow ~7 minutes: SIM 120 s,
#   registration 180 s, LTE 120 s, IMS 120 s at most). Expect, in order:
#   "SIM card state and application type/state: (1, ((2, 5), ...))";
#   "SIT SET_INITIAL_ATTACH_APN: error=0", "SIT SET_DATA_PROFILE: error=0", "default data profile accepted";
#   "waiting for packet registration"; "verified NR mode 0";
#   "data-call status 0 CID 1 active raw 2 PDP type <n>" (record n: 3 IPv4v6, 1 IPv4, 2 IPv6 only);
#   "SIT AIMS_STACK_START_REQ: error=0"; "data-call status 0 CID 2 ..."; "SIT AIMS_HIDDEN_MENU: error=0";
#   "SIT AIMS_ADD_PDN_INFO: error=0", "IMS PDN information accepted"; then "Startup: LTE, IMS voice and SMS registered" OR
#   "Startup: IMS did not register (...); serving data only" (record which); "Calls and SMS service ready"
tools/phone-ssh 'omamobile-sit status; systemctl is-active omamobile-sitd; /usr/lib/omamobile-vendor/omamobile-modem-cp state;
  dmesg | grep -c ufshcd_err_handler'
#   pass: "SIM: ready (...)"; "network: home LTE ..." (or roaming); "data bearer: up"; active; ONLINE;
#     err_handler unchanged (record any pass with its time against the link lines)
#   IMS registered: "IMS voice: yes, SMS: yes" -> M4.4 and M4.5 apply. IMS failed: M4.3 only; record the
#     failing step and status code from the journal, then (offline) the carrier's IMS values are the work
#   stop: the unit fails before "ready". The journal names the step: "SIM not usable: ..." (S1);
#     "No ready USIM within 120 s (...)"; "Modem registration deadline exceeded" (no service, the APN, or
#     the SIM not activated: check coverage and activation in the other phone); "data call did not become
#     active" with its status (36 = APN refused: check the APN); a CP crash (the watcher writes
#     /var/log/omamobile/modem-crashes.log). Record step and status, then reboot before another try
#   rollback: `omamobile-sit radio off` (AT+CFUN=0: deregisters; on again may stall until a reboot), then
#     `systemctl stop omamobile-sitd`; or reboot (one UFS pass)

# S8 = M4.3 data (risk: low-medium: mobile data use; Wi-Fi keeps the default route)
tools/phone-ssh 'systemd-run --unit=x-data-deadman --on-active=600 systemctl stop omamobile-sit-data'
tools/phone-ssh 'omamobile-sit data on; sleep 5; systemctl is-active omamobile-sit-data; ip -br addr show rmnet0 | wc -l;
  ip route show default | grep -c "dev rmnet0 .*metric 700"; ping -c3 -I rmnet0 9.9.9.9 | tail -2;
  curl -sS --interface rmnet0 -o /dev/null -w "%{http_code}\n" https://example.org/'
#   pass: active; 1 (rmnet0 UP with a /32: don't paste it); 1; "3 received"; 200
#   stop: "An active IPv4 internet bearer is required" (PDP type 2: IPv6-only, a known gap); no replies with the
#     bearer up (record "Cellular bearer carries nothing"); UFS beyond the expectation
#   rollback: omamobile-sit data off; systemctl stop x-data-deadman.timer
#   optional, attended (USB stays: it's the gadget, not Wi-Fi):
tools/phone-ssh 'nmcli radio wifi off; sleep 60; nmcli radio wifi on'
#   pass: the journal says "Default internet path cellular", then "Wi-Fi/other"

# S9 = M4.4 SMS (risk: low; sending costs what the plan charges). Needs "SMS: yes" from S7.
#   receive: the human texts the phone from the other phone
tools/phone-ssh 'omamobile-sit sms list --json | python3 -c "import json,sys; print(len(json.load(sys.stdin)))"'
#   pass: the journal says "SMS stored and acknowledged"; the count is 1 (look at the text on the phone only)
#   send, on the human's explicit go only, to a number of theirs (international form, +1...):
tools/phone-ssh 'omamobile-sit sms send <NUMBER> "omamobile test"'
#   pass: "sent", and it arrives. "unknown": never resend blindly; ask the recipient. "failed": record the reason
#   (with IMS failed, receiving may still work over the network's SMS path; sending is refused by design)

# S10 = M4.5 calls WITHOUT audio (announce: the phone takes and places a call; silence both ways is the
#   expected result; risk: medium: the first IMS call). Needs "IMS voice: yes". `card = none` stays.
#   incoming: the human calls the phone from the other phone
tools/phone-ssh 'sleep 15; omamobile-sit status | grep -E "^call"'
#   pass: "call <id>: incoming ringing-in"; the journal says "Incoming call ringing"; the caller hears ringback
tools/phone-ssh 'omamobile-sit answer; sleep 10; omamobile-sit status | grep -E "^call"; omamobile-sit hangup; sleep 3;
  omamobile-sit status | grep -E "^call"'
#   pass: "active" (the other phone shows the call connected, silent), then "terminated"; the journal says
#     "Call audio routing is off ([audio] card = none)" and nothing about "Stopping the modem"
#   outgoing, to the human's other phone (international form); answer it there, hang up there after ~10 s:
tools/phone-ssh 'omamobile-sit dial <NUMBER>; sleep 30; omamobile-sit status | grep -E "^call"'
#   pass: the other phone rings and connects (silent), then "terminated" after the remote hang-up
#   stop: "Call release was not confirmed; modem stopped" (the RIL powered the CP off by design: one UFS
#     pass; reboot before anything else); a CP crash; any sound from the phone's speakers (stop at once:
#     nothing should route audio: record `amixer -c <aoc card> cget name="TDM_0_RX Mixer EP5"`)
#   rollback: omamobile-sit hangup
#   Never dial an emergency number to test (refused anyway; TELEPHONY-APPS-PLAN 3.3)

# S11 = T2 the bridge and the apps (risk: low; reads sitd's state, forwards calls and SMS)
tools/phone-ssh 'systemctl start omamobile-mmd; sleep 3; journalctl -u omamobile-mmd -b -o cat | tail -3;
  nmcli -f DEVICE,TYPE,STATE device | grep -c gsm'
tools/phone-ssh python3 - < packages/omamobile-mmd/test/libmm-status.py
#   pass: "Modem .../Modem/0 exported: state 11" (connected) or 8 (registered), "SIM ready"; libmm-status shows
#     the same; NM lists the gsm device (it stays unmanaged for data: omamobile-sit-data owns rmnet0, T3)
#   then on the phone's screen: GNOME Calls or omaphone/omamessages (omatel) see the modem; one SMS each way
#   and one call each way as S9/S10. Announce: if omatel-agent runs, an incoming call rings through the
#   loudspeaker at the media stage (PipeWire, inside its ceilings) and vibrates; the call itself stays silent
#   rollback: systemctl stop omamobile-mmd

# S12 = M4.7 end: radio off, M3.5 after (read-only), and the reboot (asks the human; one UFS pass)
tools/phone-ssh 'omamobile-sit radio off; systemctl stop omamobile-mmd omamobile-sit-data omamobile-sitd'
#   M3.5 into logs/sim-m3.5-after.sha256; pass: no diff against S4. stop: any diff: all modem work stops
tools/phone-ssh 'sync; (sleep 1; reboot-to omamobile) >/dev/null 2>&1 &'
#   the SIM can stay in the tray; nothing starts the modem at boot (units disabled)
```

**M4.6 (the modem and sitd at boot) waits** until S5-S11 have passed on
two separate boots: enabling it means every boot powers the modem and
every reboot costs one UFS pass; the M4 section's M4.6 steps apply then.

**Record** here, one block per run: the date, `uname -r`, the three
package versions; per step pass/fail, the failing step's journal line
(states and codes only), the SIM application list (types and states),
the RAT, the bearer's PDP type, IMS registered or the step it failed
at, the time from `systemctl start omamobile-sitd` to "ready", the UFS
handler count at each step, CP crashes. Not the carrier, the APN, the
PLMN or any number (TELEPHONY-APPS-PLAN Q8).

## 4. Risks

- **A reboot with the modem ONLINE and its link idle hangs before the
  restart** on kernels without `4b1364136` (M4.1i, 2026-10-13: `bin/omamobile
  push`'s `reboot-to omamobile` after M4.1i; the journal stops, no
  shutdown lines, no pstore; the power key was needed). `reboot-to` is a
  raw reboot syscall: no unit is stopped, the kernel shuts the devices
  down directly. The PCI devices behind the modem's link are torn down
  then and their MSI vectors freed; DesignWare's MSI code masks vectors
  in DBI as it does, and a DBI access with the PHY isolated hangs the SoC
  (as the ELBI one in AGENTS 4). `4b1364136` drops DBI accesses while the
  PHY is isolated. **Until the phone runs it: once the modem has been
  started on a boot, reboot only with the human at the phone, ready for
  Power held ~30 s; never with `bin/omamobile push` unattended.** Stopping
  the unit first doesn't help (the power-off leaves the link down and
  the PHY isolated, and the teardown still frees the vectors).
- **Never touch the modem's BARs from userspace while CPIF may have the
  link down.** From M4.1h on the modem idles like stock: it drops
  CP2AP_WAKEUP and CPIF powers the link down (PHY isolated) until either
  side wants it again. A read of BAR0 (an mmap of `resource0`, the M4.1g-1
  doorbell read) with the link powered down hung the SoC hard on
  2026-10-13: SSH and ping gone, the watchdog reset it about 2 minutes
  later, no pstore. The access goes to an isolated PCIe controller and
  never completes; it is the "PCIe ELBI while the PHY is isolated" hang
  (AGENTS 4) through the outbound window. Config space is safe (the host's
  config accessors refuse while the link is down: `lspci`, `setpci` read
  all-ones); `devmem` and sysfs `resource*` mmaps are not. A check of
  `pcie_powered_on:1` and "link 1" right before narrows the window but
  can't close it (CPIF may power down in between): use CPIF's own paths.
- **First accesses to HSI1's controller.** Isolation is released before any
  ELBI read (as for Wi-Fi). If `link_up` hangs, the cause is the PHY or a
  clock: HSI1 has no CMU driver, and stock manages no clocks for ch0
  (`pcie-clk-num = 0`).
- **The modem is a bus master** once the link is up. M2 never enables bus
  mastering in the endpoint, and the endpoint's BAR is not assigned. From
  M3.1 the BAR is assigned but nothing enables bus mastering; from M3.4
  CPIF does, with no IOMMU until M3.6.
- **UFS line resets** around modem power changes (M2 analysis): keep stock's
  timing, check `ufshcd_err_handler` after each step, stop on anything
  worse than a recovered handler.
- **NV.** From M3.4 the daemons run; they only ever see RAM copies (the
  modem profile), and M3.5 re-checks the real partitions after each run.
  The copies must also pass the stock NV checksum before rfsd starts, and
  `efs.clear.action` is pinned to `none` (empty clears the NV copy).
- **CP crashes.** About one fresh start in twenty crashed the CP during
  registration on this phone model (section 6.1). Nothing restarts it here:
  the watcher records the crash, and a reboot recovers (one UFS pass).
- **The radio** transmits from M4.2 on; the RIL has no emergency calling
  (MODEM-CLIENT.md 1.3).
- **Power.** The S5300 powered for minutes with no firmware draws power;
  `cp_off` and `rmmod` turn it off, and so does reboot (shutdown callback).
- **Shared HSI1 pins.** gph1-0 (AoC), gph1-4/5 (eSE, NFC) and gph0-5 (NFC)
  are not touched.

## 5. Open questions

1. ~~Does `link_up` need the CMU_HSI1 gates?~~ No: M2.2 trained and
   read DBI with no HSI1 clock driver, as stock (`pcie-clk-num = 0`).
2. ~~x2 or x1 for the ROM link?~~ x1, which is what CPIF asks for
   (M2 analysis); the main firmware should train Gen3 x2 (M3.4).
3. The `cp2ap` levels without a link: `cp2ap-wakeup` goes to 1 within
   2 s, the others stay 0 (M2.1). Whether the ROM gives up later is M2.5.2.
4. Which modem transition disturbs UFS, and does stock's timing avoid it
   (M2.5)?
5. Does the endpoint keep answering config reads with ASPM on (M3.1 turns
   it off), and does CPIF's own L1SS control work without Google's
   `exynos_pcie_rc_l1ss_ctrl()` (M3.2 starts with a no-op)?
6. `cbd -s 2` and the `persist.vendor.modem.efs.clear.action` paths: read
   from the binaries before M3.4 (strings and disassembly, offline); the
   RAM copies make a wrong guess cost a copy, not NV. **2026-10-13:**
   `efs.clear.action` must be `none`; empty takes rfsd's factory-reset
   path (section 6.1). `-s 2` is kept as stock's `cbd.rc` has it.
7. Does the S5300 firmware boot and serve IPC/RFS with the packet
   processor absent on the AP side (`pktproc_*` left out of the CPIF node,
   AP capabilities 0)? Stock negotiates capabilities at boot
   (`capability_offset`); if the firmware insists, the packet processor
   (`link_rx_pktproc.c`, `link_tx_pktproc.c`, ~2.8k lines) is the next port
   stage, with `use_exclusive_irq` off (3.3).
   **2026-10-13:** a stack on this phone model booted, registered and moved
   data with pktproc DL/UL enabled (section 6.3); whether the firmware
   accepts legacy buffers alone is still open, and is the first suspect if
   M3.4 stops at the INIT handshake.

## 6. A working stack on this phone model, compared with ours (2026-10-13)

A collaborating project runs the same architecture on a Pixel 7 Pro (stock
`cbd`/`rfsd` in a RAM-only chroot, Google's CPIF ported to Linux 7.3, a
Python SIT client) and has LTE registration, IMS calls with two-way audio,
SMS both ways and LTE data working. Its owner permits reusing its code. Its
sources were read offline only (nothing built or run from them); the RIL
and the runtime lessons are ported into `packages/omamobile-modem-sit` and
`packages/omamobile-modem`. This section records what differed and what
our kernel still lacks.

### 6.1 Runtime and bring-up order

| | Working stack | Ours before 2026-10-13 | Ours now |
|---|---|---|---|
| NV in RAM | files extracted from the f2fs backups into a tmpfs root; stock salted MD5 of `nv_normal.bin`, `nv_protected.bin`, `nv_protected.bak` checked | loop-mounted f2fs RAM copies of the whole partitions, SHA-256 against the backup | the same, **plus the salted MD5 check** (`omamobile-modem-cp nv-check`): rfsd crashes the CP on purpose on a bad checksum |
| Chroot | private mount, PID and network namespaces; all capabilities dropped, `NO_NEW_PRIVS`; a bionic shim for properties and log filtering | `omamobile-vendor-chroot`: mount and PID namespaces, our shim; root with capabilities, host network namespace | unchanged. Follow-up: a network namespace and a capability drop for the modem profile (neither daemon needs the network) |
| Start order | rfsd (no arguments), 2 s, then `cbd -t s5100sit -P by-name/modem -s 2 -o r` once: cbd boots the CP and exits; rfsd stays | `rfsd -d`, 1 s, `cbd -d` supervised: **a cbd exit would have stopped the profile and killed rfsd with the CP up** | rfsd, 2 s, alive check, cbd once (`-o r`, no `-d`), bounded by a timeout; rfsd stays |
| `efs.clear.action` | `none` | **empty: rfsd's factory-reset path, which clears NV (the RAM copy)** | `none` |
| Other properties | `ro.bootmode=normal`, `vendor.cbd.modem_bin_type=0`, `persist.radio.multisim.config=dsds`, baseband version from the firmware TOC (INFO + 20, 31 bytes), `ro.boot.cdt_hwid` per phone | `ro.bootmode=unknown`, none of the others | as the working stack; the baseband version set at start; `cdt_hwid` in the per-phone props file |
| Firmware path | the factory radio image's `modem.bin` as a plain file; `by-name/modem` and `modem_img/images/default/modem.bin` both point at it; `vendor.modem.bin.path` set | the `modem_a` RAM copy (ext4) as `by-name/modem_a` and `by-name/modem`, mounted at `/mnt/vendor/modem_img`, as stock | stock's layout, plus `vendor.modem.bin.path` set to the image's `modem.bin` (0.1.1: without it rfsd read the raw partition and found no TOC, M3.4.4); the plain-file `by-name/modem` is fallback 1 in 6.2 |
| Shell in the chroot | `sh`, `toybox` and its links; `/vendor/bin/tar` (cbd builds an archive with tar while booting) | none | `tools/extract-vendor-chroot -p modem` adds them (re-run before M3.4) |
| `/chosen/plat`, `/chosen/config` | copied in (cbd reads the board ids and the IMEIs there) | bound read-only | unchanged; `model_info-system_rev` is not needed |
| Stop | CP off (`IOCTL_POWER_OFF`) before rfsd stops; if the power-off fails rfsd is kept | the profile's stop left the CP on and rfsd went | the unit's stop powers the CP off first (`allow_poweroff` set for that one request); reboot does the same |
| CP crash | crash reason (`IOCTL_GET_CP_CRASH_REASON`), boot log (`IOCTL_GET_CP_BOOTLOG`) and CPIF's kernel lines saved before anything else; no warm restart (warm recovery never proved reliable); about 1 in 20 fresh starts crashed during registration, ~33 s after ONLINE | nothing | `omamobile-modem-cp watch` records the same to `/var/log/omamobile/modem-crashes.log` (0600) and leaves the CP alone; reboot recovers |
| Boot-time guard | a marker across each start: a start that never reached ONLINE blocks the next automatic one | none | the same marker (`/var/lib/omamobile/modem-bringup-started`), dropped at ONLINE |
| Link power | ASPM and L1 substates off | ASPM `performance` by hand in M3.1 | set by `omamobile-modem-start` |
| Radio power | `AT+CFUN` on `/dev/umts_router`; SIT radio state and AT CFUN were seen to disagree; a SIT radio off/on cycle stalled packet registration until a CP restart | SIT SET_RADIO_POWER | `AT+CFUN`, as the working stack |
| NR | NR mode byte 3 -> 0 keeps the modem on LTE; on NR (RAT 21) the bearer carried nothing | n/a | `[network] nr = off` (default) |
| IMS | needed for SMS and voice on that carrier; stack start, IPv6 IMS bearer with P-CSCF, hidden-menu settings, ADD_PDN_INFO, wait for registration state 2 with voice and SMS | none | as the working stack |
| Call audio | AoC: `TDM_0_RX Mixer EP5` (PCM 4 playback), `EP4 TX Mixer INTERNAL_MIC_TX` (PCM 11 capture), Voice Call Audio Enable, ASRC mode 1, mic gain 130 cB + 6 dB (judged better in calls); AoC SRAM (`cp_aoc_rmem`) never CPU-mapped | none (M5) | as the working stack; our card numbers its PCMs as stock, so PCM 4/11 are EP5/EP4 |

### 6.2 If M3.4 doesn't reach ONLINE: next changes, one per boot

1. cbd can't find or open its image: bind the firmware file itself as
   `by-name/modem` and set `vendor.modem.bin.path` to it in the per-phone
   props, as the working stack does.
2. cbd logs an image-change or NV-rebuild path: compare the
   `baseband version` line of M3.4.4 with what cbd expects. Don't set a
   different `persist.vendor.modem.baseband.version` per phone: rfsd
   deletes the NV files when it differs from the TOC (M3.4.4, "What rfsd
   does at start"), and the profile now refuses to start with one.
3. rfsd forces a CP crash right after the NV requests: the checksum check
   should have caught it; read rfsd's log for the file name.
4. BOOTING, then nothing at the INIT handshake: the AP capability word
   without pktproc (open question 7): boot again with
   `modem-cpif-pktproc` after `modem-cpif-test` (stock's packet
   processor, 6.3; needs the 2026-10-13 config fragment).
5. A shell or tar error from cbd: the chroot image predates the 2026-10-13
   tool; re-extract.

### 6.3 Kernel: their CPIF and PCIe port against `omamobile-modem`

Their port is the same Google CPIF (CPIF-20220408R1, from a public mirror
of Google's gs201 kernel) in nine patches, on their own channel-0 PCIe host
that exports the `exynos_pcie_*` API, separated MSI included. What ours
lacked, by when it matters, and its status.

**2026-10-13, offline (`omamobile-modem` `907f73727`..`23e3d01c4`, built
`7.3.0-rc6-omamobile-push1-00356-g23e3d01c4543`, `logs/kernel-modem8.log`;
`W=1` clean on the touched objects, checkpatch clean apart from Google's
own style; nothing run on the phone):**

| Commit | What |
|---|---|
| `907f73727` soc: google: cpif: add the channel extension option | `CONFIG_CH_EXTENSION` (default y with CPIF) |
| `3bb1b619d` soc: google: cpif: import Google's packet processor | `link_rx_pktproc.c`, `link_tx_pktproc.c` from `CP/`, unchanged, not built |
| `000a39ed3` PCI: dwc: gs201-cp: give MSI blocks 1-4 to the modem's packet queues | DWC MSI domain = block 0 (32 vectors); `msi1`..`msi4` are the queues', `gs201_pcie_cp_register_queue()`, re-armed at every link_up |
| `27a9eb4e9` soc: google: cpif: port the packet processor | `CONFIG_CP_PKTPROC`, `CONFIG_CP_PKTPROC_UL` (default n), `CONFIG_LINK_DEVICE_PCIE_IOCC` (y); memremap of the no-map regions, DT range checks, no panics; **runtime switch:** used only when the cpif node has `pktproc_dl_support`/`pktproc_ul_support` |
| `db2aaa156` soc: google: cpif: give the packet queues their own MSI blocks | `register_separated_msi_vector()` mapped; each exclusive queue's handler run once after every PCIe power-on (the ring check) |
| `1ae88f591` PCI: dwc: gs201-cp: wait for the link to settle before using it | after 3 ms, up to 48 ms for L0..L1_IDLE with training over; below the target speed retried, kept on the last try |
| `23e3d01c4` soc: google: cpif: add the uplink priority queue option | `CONFIG_MODEM_IF_QOS` (default n): TCP ACKs on the high-priority UL queue |

Config fragment (uncommitted in this repo, 2026-10-13):
`CONFIG_CH_EXTENSION=y`, `CONFIG_CP_PKTPROC=y`, `CONFIG_CP_PKTPROC_UL=y`,
`CONFIG_MODEM_IF_QOS=y`. Overlay (uncommitted):
`device/cheetah/overlays/modem-cpif-pktproc.dtso`, stock's 33 `pktproc_*`
properties, applied after `modem-cpif-test`. Without that overlay the
packet processor code is built but idle: the AP capability word is
`0x2` (channel extension only) and data uses the legacy buffers, as
before. With it: `0x3`, four DL queues on MSI blocks 1-4, two UL queues.

| Missing in ours | Needed for | Detail |
|---|---|---|
| `CONFIG_CH_EXTENSION` (no Kconfig symbol in our port). **Done, `907f73727`** | **M4 data** | Stock's `pantah_defconfig` and the working stack both enable it. Our `modem-cpif-test` overlay copies stock's iodevs, whose rmnet channels are the extended ones (`iod,ch = <0xb5>`: 181 = `SIPC_CH_EX_ID_PDP_0`, 30 channels). Without it `sipc_ps_ch()` covers only 10-24 and the AP doesn't advertise `AP_CAP_0_CH_EXTENSION`, so PS traffic on 181+ isn't handled as rmnet data: registration and SIT can work while rmnet0 carries nothing. Add the symbol (default y with `EXYNOS_MODEM_IF`) and build it in |
| `CONFIG_CP_PKTPROC`, `CONFIG_CP_PKTPROC_UL`, `CONFIG_CPIF_PAGE_RECYCLING`; separated MSI for the queues. **Done, `27a9eb4e9`, `000a39ed3`, `db2aaa156`; untested on hardware; behind `modem-cpif-pktproc`.** Page recycling not ported: only the CPIF IOMMU's buffer manager uses it (their build doesn't load it either) | possibly M3.4 (open question 7); data throughput | The working stack runs 4 DL and 2 UL queues. Their exclusive interrupts need `register_separated_msi_vector()` (ours returns -EOPNOTSUPP), MSI blocks 1-4 on SPI 389-392. Their host also re-checks each pktproc receive ring after the link wakes (descriptors survive a link power collapse, the MSI can be lost in the retrain) |
| `CONFIG_MODEM_IF_QOS`. **Done, `23e3d01c4`** (needs the UL processor) | later | priority queue for rmnet (stock: m) |
| Suspend refusal propagated. **Already in ours:** Google's gs-6.1 `modem_suspend()` (what we imported) returns `suspend_cp()`'s -EBUSY; their patch fixes the older gs201 tree they started from. Nothing to change | suspend with the modem on | their patch makes `modem_suspend()` return the S5100 suspend hook's error, so the AP does not sleep while CP2AP_WAKEUP is asserted; that older tree drops it, gs-6.1 (and ours, `L/drivers/soc/google/cpif/modem_main.c` `modem_suspend()`) does not |
| Pull on cp2ap-wakeup (gpa8-3) | M3.4 and suspend | keep the bootloader's pull-up (M0.3 found `PUD` 0x3); stock's pull-down lost the ROM's wake signal on this phone model. Our port takes no pin states, so nothing to change; don't add them (2.1) |
| Link settle check. **Done, `1ae88f591`** | M3.4 (low) | after the first L0 the link can report a transient Gen1 while it retrains: their host waits 2.8-3 ms and checks the requested speed, the training bit and L0 again before touching the endpoint. Ours waits 3 ms and logs the speed but doesn't re-check L0 or the training bit |
| ROM link speed | M3.4 (check) | the PCI core must leave the ROM link's Gen1 target alone; their config ops keep it even if generic link recovery tries to raise it. M3.1 bound `pcieport` services (bandwidth notification included) on our root port: watch for a retrain in the M3.4 kmsg |
| PME without L2 | link power-off | a ROM or BL link sometimes acknowledged PME_Turn_Off without entering L2; ours logs "no L2 idle" and goes on, which is the right behaviour |

Already equivalent: the doorbell interrupt written as `0x10000 | n`
(Google's `DOORBELL_INT_MASK`, verbatim in ours); the endpoint's MSI address
at 0xf6200000 (our DWC MSI target); `AP2CP_WAKEUP` raised 5 ms before the
BL1 retrain (Google's sequence, verbatim); L1 substates never enabled; IO
coherency on before DMA (`cp_set_iocc()` at `link_up`); write-back mappings
of the cacheable regions; no CPU mapping of AoC voice SRAM; no `remove()`
for cpif; panics turned into errors.

