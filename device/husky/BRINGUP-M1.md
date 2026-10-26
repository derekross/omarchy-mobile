<!-- SPDX-License-Identifier: MIT -->
# husky M1: first light on zuma

**Status (2026-10-21):** stage 0 done ([NOTES.md](NOTES.md)). Kernel branch `omamobile-zuma-husky-dts` (binding, then DTS; not yet pushed) builds with the distro LLVM 21 toolchain. `dt_binding_check` passes, and `dtbs_check` leaves only the two stock-style `description` labels in `/soc_compatible`. With `SOC_COMPATIBLE` support in `bin/omamobile` (proposed in #1), `DEVICE=husky bin/omamobile images` builds all five images (results below). Nothing had been flashed or booted when this was written; the first boots came later that day (Results).

**Status (2026-10-22):** slot B boots our kernel to the init with USB, ssh and a console on the panel (gates a and b passed; Results). The images were built with an unpublished `SOC_COMPATIBLE` patch to `bin/omamobile` and AVB hash footers added by hand; #27 brings both (`SOC_COMPATIBLE`, `AVB_FOOTERS`) and reproduces those images. The kernel was built natively with the distro LLVM 21, not in the container, from a slim config (defconfig with most other SoCs off) plus bring-up debugging; the shipped path is `kernel/configs/omamobile.config` plus [kernel.config](kernel.config).

## Goal

1. Our kernel starts from slot B and is **visible**: a USB gadget on the laptop, then `ssh root@172.16.42.1` (CONTRIBUTING §5.4 stage 1).
2. Read the bootloader framebuffer's address from DPP's RDMA base register on the running phone, then add `simple-framebuffer`.
3. Slot A stays stock throughout. Only `*_b` boot images are written, and only by `bin/omamobile flash`.

## Path abbreviations

`R/` = `~/android/reference/husky-root-20261021` (live DT, dmesg, backups; never in the repository). `GZ/` = Google `kernel/devices/google/zuma`, `GS/` = `kernel/devices/google/shusky`, `GM/` = `kernel/google-modules/soc/gs`, all at `android-gs-shusky-6.1-android16`. `L/` = our kernel tree.

## Facts behind the DTS

| Item | Value | Evidence |
| --- | --- | --- |
| CPUs | 4× A510 (0xd46) @0x000–0x300, 4× A715 (0xd4d) @0x400–0x700, 1× X3 (0xd4e) @0x800; capacity 193/927/1024; PSCI 1.0 over SMC | R/`/proc/cpuinfo`, R/live.dts `cpus`, `psci` [V] |
| GIC | GICv3, GICD 0x10400000/0x10000, GICR 0x10440000/**0x200000**, maintenance PPI 9 | R/live.dts [V] |
| Arch timer | PPIs 13/14/11/10 level-low, `clock-frequency` 24.576 MHz | R/live.dts [V] |
| Base DTB match | `/soc_compatible` children (`product_id` 0x9865, major/minor/pkg_mode); this phone matches B0/B1 FOPLP. `dmesg`: `CPU[ZUMA]B0 CPU_REV[0x11]` | stock `vendor_kernel_boot`, R/live.dts, R/dmesg [V] |
| ABL glue | `/ect` with stock's base-DTB ECT location (`0x90000000`, size `0x53000`; ABL rewrites the size to `0x14000`), a `/memory` node for the first bank; `/chosen/bootargs`; the DPM overlay targets `&dpm`, `&itmon`, `&log_arrdumppanic`, `&log_bcm`, `&log_preslcdump`, `&log_slcdump` (both `dpm` partitions are empty on this phone) | GZ/`zuma-dpm-user.dtsi`; R/partitions [V] |
| Reservations | **15 regions** from the live tree's fixed DRAM reservations, contiguous ones merged (GSA, GXP and debug-snapshot): ECT, GSA, GXP, TPU, AoC, xHCI, seclog, debug-snapshot, the two CP regions and CP MSI, ABL, the debug log, ramoops, the bootloader log. Left out: the three ABL inserts itself (`pkvm_guest_firmware`, `sec_dram`, `sec_pt`), as stock's base DTB does, and `debug_kinfo_reserved`, which stock's base DTB carries and ABL adds to a tree without it (the debug region covered it until linux-omarchy-mobile#53; [UFS-PLAN](UFS-PLAN.md) test K); dropped in test 2, which showed this was not why ABL refused the images (the missing AVB footers were, test 8), and kept since, as in every image that booted, three outside DRAM (two xHCI SRAM buffers at 0x17bb5000/0x17bc0000, `cp_aoc_rmem` at 0x197fd000) and the 14 dynamic pools (NOTES.md) | R/live.dts `reserved-memory` [V] |
| USB | DWC3 0x11210000, SPI 402, peripheral. The PHY node's six regions are: USB control (blkcon) 0x11100000; **eUSB2 PHY control 0x11110000**; eUSB2 PHY configuration (Synopsys CR) 0x11120000; USB3/DP combo PHY 0x11130000 and 0x11140000; the link. 19.2 MHz ref, PMU offsets 0x3eb0/0x3eb4, `phy_eusb_version` 0x700 | R/live.dts; GM/`phy-exynos-usbdrd-eusb.c` (`reg_eusb_ctrl` = region 1, `reg_eusb_phy` = region 2) [V] |
| eUSB2 PHY vs upstream | GM/`eusb-con-reg.h` has the same layout as upstream's Exynos 2200 Synopsys eUSB2 driver (`L/drivers/phy/phy-snps-eusb2.c`, `samsung,exynos2200-eusb2-phy`): RST 0x0 (PHY reset bits 1:0, UTMI port reset bits 5:4), COMMON 0x4 (repeater mode bit 10), PLLCFG0/1 0x8/0xc, TX tune 0x14, TESTSE 0x20 | GM/, L/ [V]; the same IP, with only the register map compared [I] |
| eUSB2 repeater | Samsung part on I2C at 0x3e (`samsung,eusb-repeater`, REV_ID register 0xb0, `vdd33` supply, tuning tables in DT). No upstream driver | GS/`zuma-shusky-usb.dtsi`, GM/`eusb_repeater.c` [V] |
| PMU | `exynos-pmu` 0x15460000; reboot command offset 0x810 (`google,pixel-reboot`) | R/live.dts [V] |
| Console | `uart0` = 0x10870000, SPI 641, `samsung,exynos-uart`; stock runs `console=ttynull` | R/live.dts [V] |
| Panel | `exynos_drm.panel_name=google-hk3.20800a`, native 1344×2992; DECON0 0x19470000 | R/cmdline, `dumpsys display`, R/live.dts [V] |
| Framebuffer | **0xfac00000** (DPP0 `RDMA_BASEADDR_P0` on a booted phone, test 20), as on gs201; no splash carve-out in the live tree or the stock log | R/live.dts, R/dmesg, test 20 [V] |
| Where to read it | DPP0's DMA block is 0x19900000 (reg-name `dma`); `RDMA_BASEADDR_P0` is offset 0x40 (**0x19900040**), with its shadow at +0x400 | R/live.dts `drmdpp@19900000`; Google display `cal_9865/regs-dpp.h:33,175` [V] |
| Panel mode | **DSI command mode**: no `hk3` mode sets `MIPI_DSI_MODE_VIDEO`. So, as on gs201, ABL may leave DECON0's trigger masked and the splash frozen. DECON0 `TRIG_CON` is **0x19470030**; `HW_TRIG_EN` is bit 0 and `HW_TRIG_MASK_DECON` bit 4, the bits behind cheetah's `0x3070` → `0x3061`. ABL leaves it masked on zuma too: `TRIG_CON` reads 0x3070 at handover (test 20) | GS/`display/panel-gs-hk3.c`; Google display `cal_9865/regs-decon.h:95-112`; test 20 [V] |

## Design

- **No CMU, pinctrl, power-domain or PMU providers in M1.** The bootloader leaves what first light needs running (`clk_ignore_unused pd_ignore_unused`, as stock does). Fixed or real providers come per subsystem, the way gs201 grew.
- **USB without a PHY node first.** ABL runs USB fastboot, so the eUSB2 PHY and repeater are configured at handoff [I]. A bare `snps,dwc3` in peripheral mode at high speed may enumerate on that state. If it doesn't, the next step is upstream's Exynos 2200 split: a `google,zuma-eusb2-phy` node at 0x11110000 handled by `phy-snps-eusb2.c` (the register map matches), under a USB DRD PHY node for the control block at 0x11100000, as `phy-exynos5-usbdrd.c` does for Exynos 2200. Both need clocks and the HSI0 power domain, so CMU_HSI0 data comes first. The repeater stays in the state ABL left it in until it has a driver. (The bare DWC3 did not enumerate, test 17; the Exynos 2200 split did, with the repeater as ABL left it, test 18.)
- **No guessed framebuffer.** As on the Fold: the address is read from DPP's RDMA base register on a booted phone. On zuma that needs DPU register addresses from GM/ display code [I].
- **Image layout**: as cheetah (`BOOT_IMAGES` has all five). The DTB goes in `vendor_kernel_boot`'s dtb section, once `bin/omamobile images` can write `/soc_compatible` (the `SOC_COMPATIBLE` proposal in #1).

## Risks

- **A black-screen boot with no USB tells us nothing.** Fallbacks, cheapest first:
  1. ~~`ramoops` at 0xfd3ff000 survives a warm reset~~: zuma's user-build ABL does not keep it (test 11).
  2. The bootloader's UART on the USB-C SBU pins (`fastboot oem uart enable` on Pixels [I]) with an SBU breakout and a 1.8 V USB-UART adapter.
- **Cluster watchdogs**: ABL leaves them running, and they reset the phone after about 60 s on gs201 and 80 s on zuma (test 18) until the zuma watchdog driver takes them over (test 19). A first boot that dies at about a minute is that, not our kernel.
- **Slot B fallback**: after the retries, an unmarked slot B falls back to stock A. Don't mark it successful during M1.

## Runbook

Ask the human before every flash and reboot (AGENTS.md §1).

### M1.1 Tooling (laptop only)
`bin/omamobile images` learns `SOC_COMPATIBLE` (separate PR, after derekross agrees in #1). Then the descriptor gains it in place of the missing `SOC_IDS`. **Pass:** `DEVICE=husky bin/omamobile images` builds all five images, and `tests/images-layout` covers zuma. **Risk:** none.

### M1.2 Kernel build (laptop only)
`bin/omamobile kernel` on `omamobile-zuma-husky-dts`, with `CONFIG_USB_DWC3_GADGET`, `CONFIG_USB_CONFIGFS_NCM`, `CONFIG_BOOT_CONFIG`, `CONFIG_DRM_SIMPLEDRM` and `CONFIG_FRAMEBUFFER_CONSOLE` (all in `kernel/configs/omamobile.config` already), plus husky's [kernel.config](kernel.config): defconfig builds the eUSB2 PHY as a module, which the initramfs can't load before USB, and has no lockup detectors. **Pass:** `zuma-husky.dtb` is built, and `dtbs_check` reports nothing for the new files. **Risk:** none.

### M1.3 First boot, slot B (gate a: USB)
`DEVICE=husky bin/omamobile flash`: the five `*_b` images, `--set-active=b`, reboot.
- **Expect:** the bootloader's orange-state warning, then a USB gadget appearing on the laptop (`lsusb`, then a new `usb0`/`enx…` interface) within about 30 s.
- **Pass:** `ping 172.16.42.1`, then `ssh root@172.16.42.1`. `dmesg` is saved to R/.
- **Stop if:** nothing on USB after 2 minutes. The watchdog driver stops ABL's watchdogs (test 19), so without a panic the phone stays in our kernel until someone holds Power + Volume Up for 15-30 s (test 23; then Power + Volume Down for fastboot). Power alone does nothing. The shipped `bootargs` (`zuma-husky.dts`, derekross/linux-omarchy-mobile#13) carry `panic=10 reboot=warm` and turn soft and hard lockups and RCU stalls into panics (`softlockup_panic=1 nmi_watchdog=panic sysctl.kernel.panic_on_rcu_stall=1`, with the detectors from [kernel.config](kernel.config)); the init's own crash after the UDC wait makes one too. Wait for slot B's three retries to run out and ABL boots stock slot A, then `adb reboot bootloader`. A hang that stops every CPU at once, as a DWC3 rebind did before derekross/linux-omarchy-mobile#42 (tests 23-28), escapes the detectors and lasts until the buttons reset the phone; arming and feeding the watchdog instead would catch that too, and is a later step. With ssh up, `reboot-to bootloader` reaches fastboot directly (test 22). One change per boot from there: PHY driver, then repeater. (Tests 12-17 also used `omamobile.deadman`, an init hang marker that is not on main: it comes in a later PR, with the init changes from bring-up.)
- **Watchdog:** until the kernel has a zuma watchdog driver, ABL's cluster watchdogs reset the phone about 80 s into each boot (test 18), so the ssh window is about a minute after USB comes up: enough for `dmesg` and single reads, not for long sessions. With the driver (test 19) the window is unlimited.
- **Rollback:** `fastboot --set-active=a`. Slot A is untouched.
- **Risk:** medium (unknown hangs), with writes only to `*_b`.

### M1.4 Framebuffer address (gate b)
From the SSH shell, read DPP0's `RDMA_BASEADDR_P0` (0x19900040) and DECON0's `GLOBAL_CON` (0x19470020) and `TRIG_CON` (0x19470030) **once each, read only, one register per call** (AGENTS.md: read only blocks known to be powered and clocked), as `/usr/local/bin/devmem <address>`. `devmem` takes no width argument: a second argument is a value to **write**, so a read never has one (dropbear's PATH also omits `/usr/local/bin`). Add `simple-framebuffer` and its `no-map` carve-out to `zuma-husky.dts`, and `SIMPLEFB_TRIG_CON` to the descriptor if `TRIG_CON` shows the trigger masked.
- **Expect:** the Google logo still on the panel while our kernel runs (the evidence that the display block is powered), and a framebuffer address in DRAM.
- **Pass:** a kernel console on the panel.
- **Stop if:** the logo is gone before the reads (the block may be powered down; skip them), or a read hangs or panics.
- **Rollback:** reads change nothing. The framebuffer change is in the slot B DTB only; `fastboot --set-active=a` returns to stock.
- **Risk:** low for the reads (a powered, clocked block, read once); low for the trigger write (one register, as on cheetah, undone by any reset).

## Results

### 2026-10-21: images built, not flashed

- Kernel `7.3.0-rc6` from `omamobile-zuma-husky-dts` (arm64 `defconfig` + `kernel/configs/omamobile.config`, `LLVM=1` with Ubuntu clang 21, natively, not in the container). `CONFIG_USB_DWC3_DUAL_ROLE`, `USB_CONFIGFS_NCM`/`ACM`, `BOOT_CONFIG`, `DRM_SIMPLEDRM`, `PSTORE_RAM` and `S3C2410_WATCHDOG` are built in [V].
- The initramfs packs husky's `UFS_RW` and the USB product string "Pixel 8 Pro", and no `SIMPLEFB_TRIG_CON`, compatible or probe marker: it writes no display register [V].
- Headers against stock CP3A.261005.005 [V] (`unpack_bootimg`): header v4 and page size 0x800 for both vendor images; `init_boot` carries 17.0.0 / 2026-10 with an empty ramdisk; `vendor_boot` has no DTB; `vendor_kernel_boot` carries the DTB (one copy, 5.3 KiB) and our initramfs. `boot.img` is 18 MiB (partition 64 MiB).
- ramoops uses stock's layout (0xfd3ff000, 4 MiB, 2 MiB console + 2 MiB pmsg). So after a warm reset from a failed boot, stock Android on slot A may keep our console as its last kmsg (`adb shell dumpsys dropbox --print SYSTEM_LAST_KMSG`) [I]. That is the observation channel for a gate (a) with no USB. (Test 11 closed it: ABL does not keep ramoops.)

### 2026-10-21: first boots on slot B (M1.3)

All writes went to `*_b` only. Each test was confirmed by eye (counting orange-state screens) and by the laptop's USB log. Slot A fell back to stock unaided every time, after slot B's three retries.

| # | Slot B images | Seen | Meaning |
| --- | --- | --- | --- |
| 1 | all five ours | one orange screen, then stock | ABL rejects B **before** the orange-state screen (retries 3 → 0 in about 20 s) |
| 2 | ours + `/memory`, ECT location, no ABL-inserted reservations | the same | not the DTB layout |
| 3 | all five stock (control) | stock boots on `_b` | slot B and the flashing are fine |
| 4 | stock + our `dtbo` | orange, then a frozen logo (stock kernel without its board overlay) | our `dtbo` is accepted |
| 5 | stock + our `vendor_kernel_boot` + our `dtbo` | orange, logo, black, repeating | our DTB, `/soc_compatible` match and vendor_kernel_boot packing are accepted |
| 6 | stock `init_boot`/`vendor_boot` + our `boot` + our `vendor_kernel_boot`/`dtbo` | one orange screen, then stock | **our `boot` is rejected** |
| 7 | as 1 with a slim kernel (non-Exynos `ARCH_*` off; `image_size` 25.7 MiB, against 41.8 MiB and stock's 34.6 MiB) | one orange screen, then stock | not the kernel's size |
| 8 | as 7, plus **AVB hash footers** on `boot` and `init_boot` | orange, then a **frozen logo**, no reboot for minutes, no USB | **accepted: ABL boots our kernel** |
| 9 | as 8 without `earlycon` in `VENDOR_CMDLINE` | the same | (ABL ignores the vendor cmdline anyway; kernel arguments are DTB `bootargs`) |
| 10 | as 8, DTB `bootargs` `rdinit=/omamobile-no-such-init panic=5` (`overlays/panic-probe.dtso`) | orange screen **every few seconds**, then stock | **our kernel reaches userspace**: it panics on the missing init and reboots |

Findings:

- **zuma's `vbmeta` chains `boot` and `init_boot`** (rollback locations 2 and 4, each with its own signed AVB footer). `vendor_boot`, `vendor_kernel_boot` and `dtbo` are plain hash descriptors. With the bootloader unlocked, ABL tolerates a wrong hash or key but **rejects a chained partition with no footer**, before the orange-state screen [V, tests 6-8]. The fix used: `avbtool add_hash_footer` on both images (AOSP test key, stock's rollback index 1791158400, `os_version` 17 and `security_patch` 2026-10-05 props, padded to 64 MiB and 8 MiB). `bin/omamobile images` needs to do this for zuma (an `AVB_FOOTERS="boot init_boot"` descriptor key, proposed).
- **The kernel boots on the minimal zuma DTB** far enough to exec init from the initramfs [V, test 10]: CPUs, GIC, timer, memory and the reservations are good enough.
- **With the real init, the phone hangs without rebooting** [V, tests 8-9]. The shared init's USB self-recovery (crash 45 s after `ready` if the gadget is never configured) never fires, so the init stops before `ready`. At 20 s it is still waiting for a USB device controller to appear (2026-10-22, tests 13-15 below).

### 2026-10-22: no ramoops on zuma; a stopwatch finds the missing PHY; USB up (M1.3)

Kernel `out-zuma-debug`: the slim kernel plus the lockup, hung-task and workqueue-stall detectors set to panic, `PANIC_TIMEOUT=5` and `DYNAMIC_DEBUG`. DTB `bootargs` from `overlays/klog.dtso`. The init has a new hang marker: with `omamobile.deadman=<s>` it records how far it got (`stage N`) and, if no host has configured the gadget by then, waits a further fixed time per stage and crashes. The time from one orange-state screen to the next then gives the stage.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 11 | stock `adb reboot` (warm), then `adb bugreport` | no `console-ramoops` and no `pmsg` (LAST KMSG and LAST LOGCAT empty); stock's ramoops did register at the same `0xfd3ff000` layout; no SELinux denials for dumpstate | **zuma's ABL (user build, `debug_level` low) does not keep ramoops across a warm reset**: no log out of slot B this way, rooted or not |
| 12 | deadman 60 s, 15 s per stage | 1:48 from orange to orange; stock's boot reason afterwards `watchdog,apc,early` | the last reset was a watchdog, not our panic; not yet explained |
| 13 | deadman 20 s, 10 s per stage | 1:22, three times, then stock with boot reason `reboot,pin` (as after test 10's panics) | userspace is alive at 20 s and USB is not configured; stage 3 once test 15 measured the offset |
| 14 | deadman 20 s, 7 s per stage, finer stages after the bind | 1:13 from orange to orange, 0:09 from orange to the Google logo; stock afterwards with `reboot,pin` | same stage as test 13 |
| 15 | deadman 20 s, 0 s per stage (calibration) | 0:52 from orange to orange; the screen goes black 0:35 after the orange screen starts, then 0:17 later the next orange screen; stock afterwards with `reboot,pin` | **offset 32 s** (about 10 s from orange to the init, 5 s of `panic=5`, 17 s from the reset to the next orange). Tests 13 and 14 both give exactly **stage 3**: (82 - 52) / 10 = (73 - 52) / 7 = 3 |
| 16 | deadman 20 s, 7 s per code, `omamobile.deadman_why=11210000.usb` | 0:56 from orange to black, 1:12 from orange to orange; stock afterwards with `reboot,pin` | **code 3: `11210000.usb` has no driver and is not waiting in deferred probe, so dwc3's probe failed** |
| 17 | as 16, with a failed probe split by dwc3's log line | 1:24 from orange to black, 1:41 from orange to orange; stock afterwards with `reboot,pin` | **code 7: "failed to initialize core"**. The ID check before it passed, so the link at 0x11210000 is powered and its bus clock runs. With no PHYs in the DT, `dwc3_core_init`'s only realistic failure is `dwc3_core_soft_reset` timing out (`DCTL.CSFTRST` never clears), which is what happens when the PHY gives the link no UTMI clock [I, by elimination: event buffer setup cannot fail, no ULPI on Exynos] |
| 18 | kernel with a `google,zuma-pmu` (gs101's EL3 write path, no tables or CPU hooks), a `google,zuma-usb32drd-phy` control block at 0x11100000 (Exynos 2200's link code, PMU isolation at 0x3eb0) and the eUSB2 PHY at 0x11110000 (`samsung,exynos2200-eusb2-phy`, now built in), all on a 19.2 MHz fixed-clock stand-in; the DWC3 takes `usb2-phy` from the control block | **gate a passed**: the host enumerated the gadget (CDC NCM + ACM, high speed) 22 s after the flash, ping and ssh to 172.16.42.1 work, the init reached `ready` 0.2 s into boot, the deadman stood down. Nine CPUs online, 11.2 GiB RAM, DWC3 interrupts arriving, nothing in deferred probe | the eUSB2 PHY was the only thing missing; ABL leaves HSI0 powered and clocked and the repeater usable on a normal boot [V] |

Findings:

- **No USB device controller appears.** 20 s after the init starts, it is still in its 30 s loop waiting for `/sys/class/udc` to fill (stage 3), so `dwc3` never registered a gadget controller. Test 16: dwc3's probe ran and failed. Test 17: in core init, after the ID check, so the link is up and the eUSB2 PHY is not: on a normal boot ABL leaves the PHY off (it only runs it for fastboot). The bare-DWC3 plan is done; next is the PHY (Design, second bullet). Test 18: with the PHY, USB works. The DTB's `usb@11210000` is a bare `snps,dwc3` with no clocks, power domain or PHY, so it relies on ABL leaving HSI0 powered and clocked. On a normal boot ABL may not do that (it only drives USB in fastboot mode).
- The init should give up on the UDC after 30 s and carry on, then crash 45 s after `ready`. Test 8 instead sat for about 3.5 min with no reset, so something after the UDC wait also stalls. Test 12's watchdog reset (deadman 60 s) points the same way.
- **ABL leaves the CPU-cluster watchdogs running.** About 80 s into test 18's boot, USB dropped and the phone reset; stock then reported `watchdog,apc,early`, as after test 12. Stock's log shows both cluster watchdogs counting from the 24.576 MHz oscillator with a 30 s timeout until `s3c2410_wdt` takes them over, and our kernel has no watchdog driver. Fix: a zuma variant of `s3c2410_wdt` (gs101's, with Google's zuma PMU offsets: cluster 0 `0x1244`/`0x1220`, cluster 1 `0x1544`/`0x1520`, count-enable bit 4) [V for the reset, I for the fix].
- The screen going black (test 15) is the reset after the panic. Orange to black is the offset without the 17 s reset tail, a second reading of each run.

### 2026-10-22: the watchdog and a screen console (M1.4)

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 19 | kernel with a `google,zuma-wdt` variant of `s3c2410_wdt` (gs101's, cluster 1 at 0x1544/0x1520, count enable bit 4) and both cluster watchdogs in the DT on a 24.576 MHz stand-in clock | both report `watchdog inactive, reset disabled`; still up at 187 s, then 1083 s (no reset) | **the watchdog was the 80 s reset** [V] |
| 20 | with the Google logo still on the panel, from the ssh shell, once each: DPP0 `RDMA_BASEADDR_P0` (0x19900040), DECON0 `GLOBAL_CON` (0x19470020), `TRIG_CON` (0x19470030) | `0xfac00000`, `0x00000133`, `0x00003070` | ABL's splash is at 0xfac00000, as on cheetah; the trigger is masked, as on cheetah (0x3070) |
| 21 | `simple-framebuffer` at 0xfac00000, 1344×2992 `a8r8g8b8`, `no-map` carve-out; `SIMPLEFB_TRIG_CON="0x19470030 0x3061"` | simpledrm binds, fbcon 84×93 in TER16x32; the panel shows the init's lines (`first light`, `USB gadget up`, `ssh`, `ready`, `arch: no userdata partition`) | **gate b passed**: a kernel console on the panel [V] |

Findings:

- ~~**The buttons do nothing under our kernel.**~~ Corrected by test 23: holding Power alone for 30 s does nothing, but Power + Volume Up held for 15-30 s resets the phone (only Power was held here; Volume Down + Power was not really tried). Stock's device tree has the PMIC's cold reset disabled (`coldrst_en = "disabled"`), and its only long-press handler is the software `keydebug` (Power + Volume Up, 6 s). Our kernel has no `keydebug`, so the reset in test 23 is most likely the PMIC's own long-press reset [I]. The software ways out are ssh, a panic (every panic resets) and `reboot-to`; the lockup and stall panics make a hang reset by itself, without someone at the phone.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 22 | `syscon-reboot-mode` under the PMU (SYSIP_DAT0 0x810, bootloader 0xfc), then `reboot-to bootloader` | the driver binds; with the default cold reset the phone boots slot B again; after `echo warm > /sys/kernel/reboot/mode`, fastboot in about 20 s; with `reboot=warm` in `bootargs`, fastboot in 22 s from a fresh boot | **a cold PSCI reset clears SYSIP_DAT0 on zuma; `SYSTEM_RESET2` (warm) keeps it**. Stock's `pixel-zuma-reboot.c` writes the same register with the same values as gs201's [V] |
- ABL replaces any `console=` in `bootargs` with `console=null`; fbcon still takes the panel, and the init writes to `/dev/tty0`.

**2026-10-23, the PHY exit/init cycle (derekross/linux-omarchy-mobile#33).** Today's `omamobile` with #13 and #33, built by the shipped path (`omamobile.config` plus [kernel.config](kernel.config)), images by #27, main's init.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 23 | Boot, then a detached DWC3 unbind and bind of `11210000.usb` (rewriting the gadget's `UDC` if empty), with a detached `sleep 120; reboot-to bootloader` armed first | boot: eUSB2/usbdrd/dwc3 probe with only the dummy-supply lines, no `SMC failed`, gadget configured at high speed, `softlockup_panic`, `hardlockup_panic` and `panic_on_rcu_stall` 1, `CNTFRQ_EL0` 24576000. Cycle: the gadget leaves the laptop's bus at the unbind and never comes back; no fresh ssh login in 104 s; nothing on USB when the fallback was due; the panel keeps the init's last lines for minutes. Power + Volume Up held 15-30 s resets it; then Power + Volume Down reaches fastboot | **The phone froze at the cycle, without tripping the lockup or stall panics** (tests 24-28 find where). The cycle's log and dmesg were in RAM and are lost. The arch timer runs at 24.576 MHz without the DT's help [V] |

- **Corrected:** test 23 was first written up as a re-enumeration 22 s after the unbind, with the network dead and the fallback's reboot then hanging. The laptop's kernel log says otherwise: the fastboot device left at 16:59:58 (the flash's reboot), the gadget arrived at 17:00:20 (the boot), the read-only checks then ran over ssh until 17:01:48, the cycle started at 17:01:49, and the gadget left at 17:01:50 for good. The "re-enumeration" and 172.16.42.2 were the boot, and nothing on the phone ran after the freeze, the fallback included. 172.16.42.2 is the laptop's static NetworkManager profile: the initramfs has no DHCP server (Alpine's busybox has no `udhcpd`).

**2026-10-23, where the rebind freezes (derekross/linux-omarchy-mobile#42).** The same cycle, detached, on several kernels: unbind `11210000.usb`, wait, bind, rewrite `UDC` if empty. Each run had a detached `echo c > /proc/sysrq-trigger` fallback (150-180 s), which panics a phone that is still running. The panel is the only log: simpledrm's console draws into a shadow buffer that a worker copies to the panel, so the last tens of milliseconds before a freeze never show.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 24 | test 23's cycle (3 s between unbind and bind) on #13 + #33, then on #13 alone, both with a 30 s hung-task panic added for the test | both froze as in test 23: the gadget never came back, and neither the hung-task panic nor the fallback reset the phone. #13 alone: the panel's last line is `unbind rc=0` | **not #33**: the base freezes the same way. Every CPU stops, not one task [V] |
| 25 | a debug build of #13 alone: markers in the DWC3 removal, the PHY exit and dwc3's probe, kernel messages on the panel; unbind only | alive lines for 40 s, then the 150 s fallback panicked the phone and `panic=10` reset it | the unbind alone doesn't freeze |
| 26 | the same build, unbind, 3 s, bind | froze; the panel shows the whole removal, through the PHY exit's link reset and isolation to `remove: done` and `unbind rc=0` | the removal completes |
| 27 | the same build: `usb0` down, unbind, 40 s of alive lines, bind | alive for 40 s; froze at the bind, which never returned | **the freeze is at the bind** [V] |
| 28 | the same build with a switch that skips parts of the PHY exit, a cycle each (6 s between unbind and bind) | skip the link reset and the isolation: works. Skip only the link reset: works, re-enumerated in 6 s, fresh ssh. Skip only the isolation, keeping the link reset: froze | **the exit's link reset is what the bind can't survive** [V]. `exynos2200_usbdrd_phy_exit()` sets `CLKRST_LINK_SW_RST` and never clears it, and dwc3's probe reads the core's registers before `phy_init()` runs. On zuma that read of a link held in reset most likely hangs the bus [I] |
| 29 | #13 (`953a356a1`) + #33 (`502e57240`) + #42 (the exit pulses the reset: set, 10 µs, clear; its code is unchanged since `71b1d1d49`), merged locally into `b49cd108a`: tag `husky-test-20261023-t29`, shipped config: three cycles of unbind, 3 s, bind | each cycle re-enumerated the gadget within 4 s, a fresh ssh login worked each time, no eUSB2, usbdrd or dwc3 lines in dmesg, `SMC failed` 0 (`7.3.0-rc6-omamobile-push1-gb49cd108a652`) | **fixed by #42** [V] |

- **Without #42, every DWC3 rebind froze the phone:** tests 23, 24 (twice), 26 and 27, and test 28 with the link reset kept.

**2026-10-26, follow-ups on #13 and the PMU tables (linux-omarchy-mobile#49).** Each kernel is the merge the phone booted, tagged on greenbrettmichael/linux-omarchy-mobile; the shipped config, images by #27, main's init.

| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| 30 | #13 (`953a356a1`) + #42 (`10a49efe3`'s tree) + #49 (its first head, `0c98c7b60`'s tree): tag `husky-test-20261026-p`, `…-g64ecc04a3ebf`. Boot, then one detached DWC3 unbind and bind (3 s apart) with the 150 s `sysrq` fallback, then `reboot-to bootloader` | no `SMC failed`, no regmap error; both watchdogs probe ("inactive, reset disabled"); the cycle re-enumerated 3 s after the unbind and a fresh ssh login cancelled the fallback, with no PHY or DWC3 lines after the unbind; fastboot in 18 s | **#49's tables serve every PMU user** (USB isolation set and cleared, watchdogs, reboot mode). **#42 stands without #33** [V] |
| 31 | test 30 + `zuma: drop the timer's clock-frequency` (`8316600ac`'s tree): tag `husky-test-20261026-t`, `…-g86d443ac6529` | no `clock-frequency` under `/timer`; `arch_timer: cp15 timer running at 24.57MHz`; `CNTFRQ_EL0` 24576000; the uptime advanced 30.11 s while the laptop's clock advanced 30.11 s | the firmware programs CNTFRQ; the property can go [V] |
| 32 | test 31 + `zuma-husky: drop the soc_compatible descriptions` (`850638fe4`'s tree): tag `husky-test-20261026-s`, `…-g4e88be3f7d9c` | ABL picks the DTB and boots it; `/soc_compatible`'s children hold only `product_id`, `major`, `minor`, `pkg_mode`; USB configured, no `SMC failed` | ABL matches without the labels [V] |

The UFS boots that followed (U2, U3 and test K) are in husky's [UFS plan](UFS-PLAN.md).

## Open questions

- ~~Does a bare DWC3 enumerate on the PHY and repeater state ABL leaves behind?~~ No: the PHY is off (test 17); with the eUSB2 PHY driven, the repeater as ABL leaves it works (test 18).
- Why did test 8's init (bare DWC3, no UDC) stall after the UDC wait instead of reaching `ready`?
- ~~Where is ABL's splash buffer, and does ABL leave DECON0's trigger masked?~~ 0xfac00000, and yes (tests 20-21).
- ~~What stops the phone answering after a DWC3 unbind and bind (test 23), and is it #33 or the base?~~ The base: the PHY exit leaves the DWC3 link in reset, and the next bind freezes the phone. derekross/linux-omarchy-mobile#42 fixes it (tests 24-29).
- What exactly does the bind's first access to a link held in reset do on zuma: a bus hang, or an EL3 or interconnect stall? Nothing in software survives it, so it needs a debugger or the PMIC's reset log.
- Do the eUSB2 PHY's bit fields beyond the reset and common registers also match Exynos 2200 (PLL dividers for 19.2 MHz, TX tune)?
- B0 or B1: what `CPU_REV[0x11]` means against `/soc_compatible`'s major/minor.
