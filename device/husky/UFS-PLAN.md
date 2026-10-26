<!-- SPDX-License-Identifier: MIT -->
# Pixel 8 Pro (husky): UFS plan

Goal: the mainline UFS driver brings up husky's UFS behind the read-only storage guard, the init's UFS probe report lists every LUN and partition by name, and the guard leaves only `UFS_RW` (slot B's boot images and `userdata`) writable. After that, the Arch root on `userdata` (as cheetah, [BRINGUP-M1](../cheetah/BRINGUP-M1.md)).

**Status (2026-10-26):** U1-U3 done. UFS links at HS-G4 on two lanes behind the guard, and Arch runs from `userdata` (results below). The kernel side is derekross/linux-omarchy-mobile#49 (PMU tables), #50 (pinctrl), #51 (UFS bindings) and a DT follow-up to #13.

Path abbreviations as in [BRINGUP-M1.md](BRINGUP-M1.md). `GU/` = Google's GPL UFS driver, `GM/drivers/ufs` (`ufs-exynos.c`, `zuma/ufs-cal*.h`, `zuma/ufs-cal-if.c`). Facts are [V] (checked, with the source) or [I] (an inference to check).

## Facts

| What | Value | Source |
| --- | --- | --- |
| Host | `ufs@13200000`, SPI 466. Regions: HCI 0x13200000/0x200, vendor HCI 0x13201100/0x2000, UniPro 0x13280000/0x8000, UFSP 0x132a0000/0xa014, PHY 0x13204000/0x4000, CPort 0x13208000/0x804 | R/live.dts [V] |
| Sysreg | `sysreg_ufs@13020000` (`google,zuma-sysreg-ufs`, its own block, not HSI2 as on gs201); IOCC at 0x710, mask 0x3 | R/live.dts `ufs-iocc`, R/dmesg [V] |
| PHY isolation | PMU 0x3ec0, mask 0x1 (gs201: 0x3ec8) | R/live.dts `ufs-phy-iso` [V] |
| Clocks | `GATE_UFS_EMBD`, `UFS_EMBD` from the one CAL provider; no zuma clock driver upstream. **UniPro (`mclk`) runs at 178 MHz** | R/live.dts; R/dmesg `mclk: 178000000` [V] |
| Pins | `gph5-1` UFS reset and `gph5-0` reference-clock out, function 2, in the HSI2UFS pin controller (0x13060000) | R/live.dts [V] |
| Pins at handover | `gph5` CON `0x21`, DAT `0x2`: the reset is in function 2, but the reference-clock pin is a GPIO output driven low | U2, one register per read [V] |
| VCC | `regulator-fixed` on `gpp0-1` (PERIC0 pinctrl 0x10840000) | R/live.dts [V] |
| VCC at handover | `gpp0` CON `0x2010`, DAT `0x8`: `gpp0-1` is an output driven low, so the device is off. ABL hands UFS over powered down | U2b, one register per read [V] |
| Reference clock | 38.4 MHz | GU/`zuma/ufs-cal.h` `USE_38_4_MHZ` [V] |
| Link at stock | HS-G4, 2 lanes, rate series B (`HS-series(2)`); WriteBooster configuration refused ("It is not allowed to configure WB!") | R/dmesg [V] |
| CAL variant | `evt version : 0, board: 1`: the `*_evt0` tables, board mask `BRD_SMDK` | R/dmesg; GU/`zuma/ufs-cal-if.h` [V] |
| CAL tables | `init_cfg_evt0` (pre-link), `post_init_cfg_evt0`, `calib_of_pwm`, `calib_of_hs_rate_a/b` with their `post_*`, `post_ah8_cfg_evt0`, `post_h8_enter`, `pre_h8_exit`, `lane1_sq_off` | GU/`zuma/ufs-cal.h` [V] |
| LUNs | `sda`: `persist`, `efs`, `efs_backup`, `modem_*`, `metadata`, slot A and B boot images, `userdata` (`sda34`). `sdb`, `sdc`: the two boot LUNs (`bl1`, `abl`, `gsa`…). `sdd`: `devinfo`, `blenv`, `mfg_data`. The same shape as cheetah's, so the guard's name allowlist and its deletion of `/dev/sda` apply unchanged | R/partitions.txt [V] |
| Mainline | `ufs-exynos` and `phy-samsung-ufs` support gs101 and gs201 (gs201 merged here, derekross/linux-omarchy-mobile#4: the gs101 sequences with gs201's PMA table, no pinctrl, a fixed always-on VCC) | L/ [V] |

## Design

1. **PHY and host: Tensor G4's driver data, through a fallback compatible.** U1 first ported zuma's own PHY tables and host hooks. Then Tensor G4's UFS support merged (W4HO), taken from the same `drivers/ufs/zuma/` CAL. Its 36 PMA writes match ours value for value, and so do the calibration-done register, the PMU isolation (0x3ec0) and the PCS and UniPro values. So `google,zuma-ufs-phy` and `google,zuma-ufs` fall back to `google,zumapro-ufs-phy` and `google,zumapro-ufs`, with no new driver code (#51).
2. **Pins and VCC through a zuma pin controller** (#50: Tensor G4's bank tables, with zuma's shorter ALIVE). The DT describes the HSI2UFS and PERIC0 controllers. The host takes stock's `ufs-rst-n` and `ufs-refclk-out` groups, and VCC is stock's GPIO-switched fixed regulator on `gpp0-1`, which ufshcd turns on.
3. **DT**: `ufs@13200000` and its PHY with `reg-names` as gs201's, `samsung,sysreg = <&sysreg_ufs 0x710>`, `dma-coherent`, the PMU phandle. The clocks are `fixed-clock` stand-ins: 178 MHz for `sclk_unipro_main` (stock's `mclk`), a `core_clk` rate inside the driver's PCLK range [I: stock never prints it] that also stands in for the FMP, bus and sysreg gates, and 38.4 MHz for the PHY's reference.
4. **Bindings** in `omamobile-zuma-ufs` (#51) and `omamobile-zuma-pinctrl` (#50); the DTS in the DT follow-up to #13.
5. **`userdata` is not touched.** It is on the allowlist, and still holds stock Android's data. With UFS up, the init's `boot_arch` would find it writable and run `e2fsck -p` and an ext4 mount on it; on stock's file system both should fail without writing, but U2 doesn't rely on that: its `bootargs` carry `omamobile.initramfs`, which skips `boot_arch`.
6. **Nothing writes before the guard.** The guard runs before the UFS driver's disks appear (the init is PID 1 before any module or late probe), and `UFS_RW` is unchanged. The first UFS boot is `omamobile.ufs-probe`: a read-only listing.

## Runbook

Ask the human before every flash and reboot (AGENTS.md §1). The phone is in fastboot on slot B, or `reboot-to bootloader` gets there (BRINGUP-M1 test 22).

### U1 Port (laptop only)
The PHY tables, the host variant, the DT and bindings. **Pass:** builds; `dt_binding_check` and `CHECK_DTBS` clean for the new nodes; each zuma table entry is accounted for (ported, matched to gs201's, or left out with a reason) in this file. **Risk:** none.

### U2 First UFS boot, read only (gate c)
The U1 kernel and DTB with `omamobile.ufs-probe` and `omamobile.initramfs` in the klog overlay's `bootargs` (the probe listing; no hand-over to Arch, so nothing runs on `userdata`), flashed to `boot_b` and `vendor_kernel_boot_b`.
- **Expect:** the usual USB and ssh; then `dmesg` shows the link up, and `/run/ufs-probe.txt` lists `sda`–`sdd` with every partition name, all `ro=1` except `UFS_RW`.
- **Pass:** the listing matches R/partitions.txt by name and device node, and the guard's log shows each partition handled.
- **Stop if:** the link doesn't come up (keep `dmesg`, then `reboot-to bootloader`); any partition outside `UFS_RW` is writable (`reboot-to bootloader` at once, report, change nothing else).
- **Rollback:** `fastboot --set-active=a`. Slot A is untouched; nothing on UFS is written.
- **Risk:** medium. A wrong PHY table can fail the link (no harm), or hang the bus (a panic, then a reset). The guard sets disks read-only as they appear, so a working link is guarded from its first moment.

### U3 Arch root on `userdata` (gate d)
After U2, the init's existing hand-over to Arch, as on cheetah. Separate plan step; needs the human's go to format `userdata` (it is on the allowlist, and stock Android's data is on it).

### U4 The Omarchy root image (gate e)
`tools/build-packages` with `omamobile-device-husky`, then `DEVICE=husky tools/build-rootfs`, then `tools/install-phone` (needs the human's go: it erases `userdata` again).
- **Needs:** the package in the signed `[omamobile]` repository (the maintainer's key; see issue #1), and an aarch64 binfmt handler on the laptop (`qemu-user-binfmt`).
- **Expect:** as U3, then `omamobile-firstboot` creates the user from `firstboot.conf` and runs Omarchy's setup.
- **Pass:** the user logs in over ssh, `systemctl --failed` is empty, the guard's flags hold, and `reboot-to bootloader` works.
- **Stop if:** `omamobile-firstboot` fails (keep its journal); any partition outside `UFS_RW` is writable (`reboot-to bootloader` at once).
- **Rollback:** reinstall U3's image, or `fastboot --set-active=a` (stock needs a factory reset after `userdata` was written).
- **Risk:** low. Nothing new touches the hardware.

### U5 Hibern8 (gate f)
Let the UFS device runtime-suspend, with the link in hibern8. zuma's CAL has hibern8 entry and exit sequences (`post_h8_enter`, `pre_h8_exit`) that neither Tensor G3 nor G4 runs yet.
- **Step 1, read only:** `cat` the `power/control` and `runtime_status` of the UFS well-known LUN and of `sda`-`sdd`. Nothing changes.
- **Step 2:** `echo auto` into `sda`'s `power/control`, with a detached fallback armed first (`sleep 120; echo c > /proc/sysrq-trigger`, cancelled by a fresh ssh login), then wait for `runtime_status` to read `suspended` and read one block of `boot_b`.
- **Pass:** the device suspends and resumes, the read succeeds, and dmesg shows no UIC error, `ufshcd_err_handler` or reset; ten cycles the same.
- **Stop if:** an error handler run, a reset, or no answer: put `power/control` back to `on` (or let the fallback panic the phone), and add the CAL's hibern8 sequences before trying again.
- **Rollback:** `on` again, or a reboot: nothing persists.
- **Risk:** medium. A failed hibern8 exit can leave the link down until the host resets it; nothing is written to the disk.

## Risks

- **No clock driver.** The stand-in rates must match what ABL set: UniPro timings come from `mclk` (178 MHz is stock's). ~~ABL leaves the reference clock and the device reset pin in their UFS function [I].~~ Wrong: ABL hands UFS over powered down (U2, U2b). So the pins and VCC need the pin controller (Design 2).
- **WriteBooster and device attributes.** Checked in U1: the zuma host sets no `UFSHCD_CAP_WB_EN`, so the core writes no WriteBooster flag; it has no `ref_clk` host clock, so it leaves `bRefClkFreq` alone. What the core still writes at probe is `fDeviceInit` (stock does too), the exception-event mask and, on UFS 4.0 parts, the RTC attribute: device state, not partition data. With Tensor G4's host data, runtime PM uses the core's default level 3 (device asleep, link in hibern8), which also toggles background operations. Until U3 it never ran: the sd devices' runtime PM stays `on`, so the device never suspends (U2c, U3).
- **Inline encryption.** Stock uses wrapped keys through KDN/FMP; mainline leaves FMP to its own path. Nothing of stock's encrypted `userdata` is read or written in U2.

## Results

Each kernel is the merge the phone booted, tagged on greenbrettmichael/linux-omarchy-mobile, so every `uname -r` resolves to public code. All of them sit on BRINGUP-M1 test 32's kernel (#13, #42, #49 and the two DT follow-ups, tag `husky-test-20261026-s`), with the shipped config, images by #27 and main's init. Logs are kept outside the repository (`~/android/reference/husky-u2*`, `husky-u3-*`).

| Boot | Tag | Adds to test 32's kernel |
| --- | --- | --- |
| U2 | `husky-test-20261026-u2` (`…-g32f1eaffced5`) | #51 (`79a5b8ccd`'s tree), and a first UFS DT: no pin controller, VCC an always-on fixed regulator |
| U2b | `husky-test-20261026-u2b` (`…-g536865667062`) | U2 + #50 (`3ab64be4a`'s tree) + the HSI2UFS pin controller only |
| U2c, U3 | `husky-test-20261026-u2c` (`…-ge446d69d2ab2`) | #51 + #50 + the DT follow-up as published (`1888cb854`, `d84cce8c5` trees): both pin controllers and VCC on `gpp0-1` |


| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| U1 | The port | builds; `dt_binding_check` and `CHECK_DTBS` clean for the UFS nodes | then rebased onto Tensor G4's merged UFS data (Design 1) |
| U2 | S's kernel + UFS (`…-g32f1eaffced5`), `omamobile.ufs-probe omamobile.initramfs` | probe, PHY calibration done, then `link startup failed 1` four times, `-EIO`; no disks | the device never answers on the link [V]. `gph5` reads `0x21`/`0x2`: the reference-clock pin is a GPIO driven low [V] |
| U2b | + the zuma pin controller, HSI2UFS only (`…-g536865667062`) | `gph5` reads `0x22` (both pins in function 2); link start-up still fails | not only the pins. `gpp0` reads `0x2010`/`0x8`: VCC is off [V] |
| U2c | + PERIC0 and VCC as stock's GPIO regulator (`…-ge446d69d2ab2`) | `Power mode changed to : FAST series_B G_4 L_2`; 4 LUNs, 62 partitions with stock's names on stock's nodes; only `UFS_RW` writable, `sdb`-`sdd` read-only, `/dev/sda` removed; a 64 MiB read of `boot_b` at 1.8 GB/s | **gate c passed**: UFS up behind the guard, as on stock [V] |
| U3 | U2c's kernel without `omamobile.initramfs`; `tools/install-phone` with a test root image (Arch Linux ARM's base, its signature checked by `tools/lib/alarm.sh`, plus `omamobile-device-husky` and the kernel's modules) | the init grows the file system to all of `userdata` (108 GB) and switches to Arch; systemd `running`, no failed units, ssh with the installed key; the guard's read-only flags hold under Arch and `/dev/sda` stays gone; `reboot-to bootloader` from Arch reaches fastboot in 19 s; a second boot reaches ssh in 28 s | **gate d passed**: Arch on `userdata` [V] |

Findings:
- **ABL hands UFS over powered down:** VCC off and the reference-clock pin a GPIO driven low (U2, U2b). Stock's kernel sets both up itself, so mainline needs the pin controller and the GPIO regulator.
- **Hibern8 is untested, on Tensor G3 and on Tensor G4.** Here, the device never runtime-suspended, in the initramfs or under Arch, because the sd devices' runtime PM stays `on`. Tensor G4's UFS support didn't qualify it either.
- **The full Omarchy image comes next (U4).** `tools/build-rootfs` needs `omamobile-device-husky` in the signed `[omamobile]` repository. U3's image used only Arch Linux ARM's base, so it has no desktop and no `omamobile-firstboot`. The user's answers sit unused in `/etc/omamobile/firstboot.conf`, and root logs in with the key.
- **No clock source:** with no RTC driver and no network time, the clock starts at the image's build date (it read Jul 24).
