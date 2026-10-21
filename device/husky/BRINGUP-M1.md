<!-- SPDX-License-Identifier: MIT -->
# husky M1: first light on zuma

**Status (2026-10-21):** stage 0 done ([NOTES.md](NOTES.md)). A minimal `zuma.dtsi` and `zuma-husky.dts` are written on branch `omamobile-zuma-husky-dts` (off `omamobile`, not yet pushed). They compile with no `dtc` warnings, and the board overlay plus Google's user-build DPM overlay apply onto them with `fdtoverlay`. Nothing has been built into images or booted.

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
| ABL glue | empty `/ect`; `/chosen/bootargs`; the DPM overlay targets `&dpm`, `&itmon`, `&log_arrdumppanic`, `&log_bcm`, `&log_preslcdump`, `&log_slcdump` (both `dpm` partitions are empty on this phone) | GZ/`zuma-dpm-user.dtsi`; R/partitions [V] |
| Reservations | 18 fixed DRAM carve-outs from the live tree (GSA, GXP, TPU, AoC, xHCI, pKVM, secure DRAM, seclog, debug-snapshot, CP, ABL, ramoops, bootloader log) | R/live.dts `reserved-memory` [V] |
| USB | DWC3 0x11210000, SPI 402, peripheral; eUSB2 PHY 0x11100000 (`phy_version` 0x600, `phy_eusb_version` 0x700, 19.2 MHz ref, PMU offsets 0x3eb0/0x3eb4); Samsung eUSB2 repeater on I2C at 0x3e | R/live.dts; GS/`zuma-shusky-usb.dtsi` [V] |
| PMU | `exynos-pmu` 0x15460000; reboot command offset 0x810 (`google,pixel-reboot`) | R/live.dts [V] |
| Console | `uart0` = 0x10870000, SPI 641, `samsung,exynos-uart`; stock runs `console=ttynull` | R/live.dts [V] |
| Panel | `exynos_drm.panel_name=google-hk3.20800a`, native 1344×2992; DECON0 0x19470000 | R/cmdline, `dumpsys display`, R/live.dts [V] |
| Framebuffer | **unknown**: no splash carve-out in the live tree or the stock log | R/live.dts, R/dmesg [V] |

## Design

- **No CMU, pinctrl, power-domain or PMU providers in M1.** The bootloader leaves what first light needs running (`clk_ignore_unused pd_ignore_unused`, as stock does). Fixed or real providers come per subsystem, the way gs201 grew.
- **USB without a PHY node first.** ABL runs USB fastboot, so the eUSB2 PHY and repeater are configured at handoff [I]. A bare `snps,dwc3` in peripheral mode at high speed may enumerate on that state. If it doesn't, the next step is a PHY driver. Upstream has Synopsys eUSB2 PHY support for Exynos 2200 (`phy-snps-eusb2.c`, `samsung,exynos2200-eusb2-phy`). Whether zuma's PHY is the same IP is [I] (compare GM/'s `phy-exynos-usbdrd` eUSB code with it).
- **No guessed framebuffer.** As on the Fold: the address is read from DPP's RDMA base register on a booted phone. On zuma that needs DPU register addresses from GM/ display code [I].
- **Image layout**: as cheetah (`BOOT_IMAGES` has all five). The DTB goes in `vendor_kernel_boot`'s dtb section, once `bin/omamobile images` can write `/soc_compatible` (the `SOC_COMPATIBLE` proposal in #1).

## Risks

- **A black-screen boot with no USB tells us nothing.** Fallbacks, cheapest first:
  1. `ramoops` at 0xfd3ff000 survives a warm reset, but reading it back needs a rooted kernel afterwards [I].
  2. The bootloader's UART on the USB-C SBU pins (`fastboot oem uart enable` on Pixels [I]) with an SBU breakout and a 1.8 V USB-UART adapter.
- **Cluster watchdogs**: on gs201, ABL leaves them running and they reset the phone after about 60 s [V for gs201; I for zuma]. A first boot that dies at about a minute is that, not our kernel.
- **Slot B fallback**: after the retries, an unmarked slot B falls back to stock A. Don't mark it successful during M1.

## Runbook

Ask the human before every flash and reboot (AGENTS.md §1).

### M1.1 Tooling (laptop only)
`bin/omamobile images` learns `SOC_COMPATIBLE` (separate PR, after derekross agrees in #1). Then the descriptor gains it in place of the missing `SOC_IDS`. **Pass:** `DEVICE=husky bin/omamobile images` builds all five images, and `tests/images-layout` covers zuma. **Risk:** none.

### M1.2 Kernel build (laptop only)
`bin/omamobile kernel` on `omamobile-zuma-husky-dts`, with `CONFIG_USB_DWC3_GADGET`, `CONFIG_USB_CONFIGFS_NCM`, `CONFIG_BOOT_CONFIG`, `CONFIG_DRM_SIMPLEDRM` and `CONFIG_FRAMEBUFFER_CONSOLE` (all in `kernel/configs/omamobile.config` already [I]). **Pass:** `zuma-husky.dtb` is built, and `dtbs_check` reports nothing for the new files. **Risk:** none.

### M1.3 First boot, slot B (gate a: USB)
`DEVICE=husky bin/omamobile flash`: the five `*_b` images, `--set-active=b`, reboot.
- **Expect:** the bootloader's orange-state warning, then a USB gadget appearing on the laptop (`lsusb`, then a new `usb0`/`enx…` interface) within about 30 s.
- **Pass:** `ping 172.16.42.1`, then `ssh root@172.16.42.1`. `dmesg` is saved to R/.
- **Stop if:** nothing on USB after 2 minutes. Then hold Power about 30 s, Volume Down + Power for fastboot, `fastboot --set-active=a`, and reboot to stock. One change per boot from there: PHY driver, then repeater.
- **Rollback:** `fastboot --set-active=a`. Slot A is untouched.
- **Risk:** medium (unknown hangs), with writes only to `*_b`.

### M1.4 Framebuffer address (gate b)
From the SSH shell, read DPP0's RDMA base address register (address from GM/'s zuma DPU code [I]) **once, read only, one register per call** (AGENTS.md: read only blocks known to be powered and clocked). Add `simple-framebuffer` and its `no-map` carve-out to `zuma-husky.dts`. **Pass:** a kernel console on the panel.

## Results

None yet.

## Open questions

- Does a bare DWC3 enumerate on the PHY and repeater state ABL leaves behind?
- Where is ABL's splash buffer, and is DECON0 in command mode (needing a `SIMPLEFB_TRIG_CON`, as on gs201)?
- Is zuma's eUSB2 PHY the Synopsys IP that upstream's Exynos 2200 driver handles?
- B0 or B1: what `CPU_REV[0x11]` means against `/soc_compatible`'s major/minor.
