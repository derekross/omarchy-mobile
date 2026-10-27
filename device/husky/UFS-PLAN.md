<!-- SPDX-License-Identifier: MIT -->
# Pixel 8 Pro (husky): UFS plan

Goal: the mainline UFS driver brings up husky's UFS behind the read-only storage guard, the init's UFS probe report lists every LUN and partition by name, and the guard leaves only `UFS_RW` (slot B's boot images and `userdata`) writable. After that, the Arch root on `userdata` (as cheetah, [BRINGUP-M1](../cheetah/BRINGUP-M1.md)).

**Status (2026-10-26):** U1-U3 done. UFS links at HS-G4 on two lanes behind the guard, and Arch runs from `userdata` (results below). The kernel side is derekross/linux-omarchy-mobile#49 (PMU tables), #50 (pinctrl) and #51 (UFS bindings), all merged, and #53, the DT follow-up to #13. U4 waits for the signed repository (issue #1).

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

1. **PHY and host: Tensor G4's driver data, through a fallback compatible.** U1 first ported zuma's own PHY tables and host hooks. Then Tensor G4's UFS support merged (W4HO), taken from the same `drivers/ufs/zuma/` CAL. Its 36 PMA writes match ours value for value, and so do the calibration-done register, the PMU isolation (0x3ec0) and the PCS and UniPro values. Google's `soc/gs` tree has the whole `drivers/ufs/zuma/` directory with the same blob ids on the Pixel 8 branch (`android-gs-shusky-6.1-android16`) and the Pixel 9a branch (`android-gs-tegu-6.1-android16`); `ufs-cal.h` is `a25ab865` on both (found by the maintainer on #51; the shusky copy here hashes the same). So `google,zuma-ufs-phy` and `google,zuma-ufs` fall back to `google,zumapro-ufs-phy` and `google,zumapro-ufs`, with no new driver code (#51, merged).
2. **Pins and VCC through a zuma pin controller** (#50: Tensor G4's bank tables, with zuma's shorter ALIVE). The DT describes the HSI2UFS and PERIC0 controllers. The host takes stock's `ufs-rst-n` and `ufs-refclk-out` groups, and VCC is stock's GPIO-switched fixed regulator on `gpp0-1`, which ufshcd turns on.
3. **DT**: `ufs@13200000` and its PHY with `reg-names` as gs201's, `samsung,sysreg = <&sysreg_ufs 0x710>`, `dma-coherent`, the PMU phandle. The clocks are `fixed-clock` stand-ins: 178 MHz for `sclk_unipro_main` (stock's `mclk`), a `core_clk` rate inside the driver's PCLK range [I: stock never prints it] that also stands in for the FMP, bus and sysreg gates, and 38.4 MHz for the PHY's reference.
4. **Bindings** in `omamobile-zuma-ufs` (#51) and `omamobile-zuma-pinctrl` (#50); the DTS in #53, the DT follow-up to #13.
5. **`userdata` is not touched.** It is on the allowlist, and still holds stock Android's data. With UFS up, the init's `boot_arch` would find it writable and run `e2fsck -p` and an ext4 mount on it; on stock's file system both should fail without writing, but U2 doesn't rely on that: its `bootargs` carry `omamobile.initramfs`, which skips `boot_arch`.
6. **Nothing writes before the guard.** The guard runs before the UFS driver's disks appear (the init is PID 1 before any module or late probe), and `UFS_RW` is unchanged. The first UFS boot is `omamobile.ufs-probe`: a read-only listing.

## Runbook

Ask the human before every flash and reboot (AGENTS.md §1). The phone is in fastboot on slot B, or `reboot-to bootloader` gets there (BRINGUP-M1 test 22).

**Slot B's retries.** Nothing marks slot B successful: the device package has no boot-success marker, on purpose. So ABL counts every boot of B, clean or not. `fastboot --set-active=b` gives B three retries, and each boot uses one: `slot-retry-count:b` read 2 after one clean boot (test K). When they run out, the next boot is stock slot A (BRINGUP-M1 tests 1 and 13). `bin/omamobile flash` and `tools/install-phone` both end with `--set-active=b`, so each flash or install starts again at three. Before a third reboot without a flash, set them again from fastboot: `reboot-to bootloader`, then `fastboot --set-active=b` and `fastboot reboot`.

If stock boots anyway, with Arch on `userdata`:
- Stock can't read its data [I: what it shows is still to see; recovery's factory-reset offer is the expected screen]. **Decline the factory reset:** it erases `userdata`, which is the install.
- Get to fastboot (recovery's "Reboot to bootloader", or Power + Volume Down), then `fastboot --set-active=b` and `fastboot reboot`.
- Take a fresh read-only backup before the next radio, PMIC, AoC or Trusty work (AGENTS.md): a stock boot counts, since stock's modem stack writes `efs`, `persist` and `modem_userdata`.

U3 never fell back: it booted twice after `install-phone`'s `--set-active=b`, and test K's flash set it again.

### U1 Port (laptop only)
The PHY tables, the host variant, the DT and bindings. **Pass:** builds; `dt_binding_check` and `CHECK_DTBS` clean for the new nodes; each zuma table entry is accounted for (ported, matched to gs201's, or left out with a reason) in this file. **Risk:** none.

### U2 First UFS boot, read only (gate c)
The U1 kernel and DTB with `omamobile.ufs-probe` and `omamobile.initramfs` in the klog overlay's `bootargs` (the probe listing; no hand-over to Arch, so nothing runs on `userdata`), flashed to `boot_b` and `vendor_kernel_boot_b`.
- **Expect:** the usual USB and ssh; then `dmesg` shows the link up, and `/run/ufs-probe.txt` lists `sda`–`sdd` with every partition name, all `ro=1` except `UFS_RW`.
- **Pass:** the listing matches R/partitions.txt by name and device node, and the guard's log shows each partition handled.
- **Stop if:** the link doesn't come up (keep `dmesg`, then `reboot-to bootloader`); any partition outside `UFS_RW` is writable (`reboot-to bootloader` at once, report, change nothing else).
- **Rollback:** `fastboot --set-active=a`. Slot A is untouched; nothing on UFS is written.
- **Risk:** medium. A wrong PHY table can fail the link (no harm), or hang the bus (a panic, then a reset). The guard sets disks read-only as they appear, so a working link is guarded from its first moment.
- **Reads** (U2, U2b): in this boot, one register per call, with the initramfs's `devmem`: `tools/phone-ssh '/usr/local/bin/devmem 0x13060000'` is `gph5` CON (`0x13060004` its DAT), and `0x10840000`/`0x10840004` are `gpp0` CON/DAT, PERIC0's first bank.

### U3 Arch root on `userdata` (gate d)
U2c's kernel and DTB without `omamobile.initramfs` (no overlay), so the init hands over to Arch on `userdata`, as on cheetah. The full root image needs the signed repository (U4), so U3 uses a test image. `device/husky/build-u3-root` builds it from three things:
- Arch Linux ARM's base tarball, its MD5 and signature checked by `tools/lib/alarm.sh`;
- `omamobile-device-husky`, through its own `build` and `install`, with `reboot-to` cross-compiled;
- the kernel's modules.

Root and `alarm` are locked, and there is no machine id. Built from U2c's kernel:
```
KERNEL_OUT=~/android/mainline/out-zuma-ufs2 bin/omamobile modules
device/husky/build-u3-root ~/android/mainline/out-zuma-ufs2
KERNEL_OUT=~/android/mainline/out-zuma-ufs2 tools/install-phone --device husky \
  --rootfs out/husky/u3-root/omamobile-rootfs-u3-husky-aarch64.img.zst \
  --bootloader-slots-match ripcurrent-17.0-15681527 --dry-run
```
Then run the same `install-phone` without `--dry-run`. It needs the human's go, because it erases `userdata`, which holds stock Android's data. `--bootloader-slots-match` names the bootloader that both slots carry, as checked in stage 0.
- **Expect:** `install-phone`'s checks pass. It writes slot B's five images and `userdata`, sets B active and reboots. The init finds `omamobile-root` on `userdata`, grows it to the whole partition, and switches to Arch, and systemd reaches `running`.
- **Pass:**
  - ssh as root with the installed key;
  - `systemctl --failed` is empty;
  - the guard's flags hold under Arch: only `UFS_RW` writable, `sdb`-`sdd` `ro`, no `/dev/sda`;
  - `reboot-to bootloader` reaches fastboot;
  - a second boot comes up the same.
- **Stop if:** no ssh after 2 minutes: the init's log is on the panel; then Power + Volume Up, then Power + Volume Down for fastboot. Also stop if any partition outside `UFS_RW` is writable (`reboot-to bootloader` at once).
- **Rollback:** flash U2c's images with `omamobile.initramfs` to stay in the initramfs, or `fastboot --set-active=a`. Stock then needs a factory reset, since its `userdata` is gone.
- **Risk:** low for the hardware, since the kernel is U2c's. `userdata` is erased by design. Mind slot B's retries (above).

### U4 The Omarchy root image (gate e)
The kernel is tag `husky-test-20261026-k`: U2c's kernel and modules, with #53's device tree (test K), in `~/android/mainline/out-zuma-kinfo`. If #13 and #53 have merged by then, use a fresh build of `omamobile` instead, tagged before it's flashed.
1. **Fill `out/repo/aarch64`** from the maintainer's signed repository, once its URL is on issue #1: `omamobile.db` with its `.sig`, and every package with its `.sig`. Don't run `tools/build-packages`: it signs with `keys/`, which only the maintainer holds. `build-rootfs`'s container trusts only omamobile-keyring's key, so a file the maintainer didn't sign stops the build.
2. `DEVICE=husky KERNEL_OUT=~/android/mainline/out-zuma-kinfo tools/build-rootfs`. Add `--allow-missing` for any of our packages the repository doesn't carry; the MANIFEST lists them.
3. `KERNEL_OUT=~/android/mainline/out-zuma-kinfo tools/install-phone --device husky --bootloader-slots-match ripcurrent-17.0-15681527`, with `--dry-run` first. It needs the human's go, because it erases `userdata` again.
- **Needs:** the package in the signed `[omamobile]` repository (issue #1), and an aarch64 binfmt handler on the laptop (`qemu-user-binfmt`, installed).
- **Expect:**
  - as U3, then `omamobile-firstboot` creates the user from `firstboot.conf` and runs Omarchy's setup;
  - slot B's three retries count down as in U3, so stock boots on the fourth boot after the install unless `--set-active=b` runs again (above).
- **Pass:**
  - the user logs in over ssh;
  - `systemctl --failed` is empty;
  - the guard's flags hold;
  - `reboot-to bootloader` works;
  - `tools/phone-smoke`'s report goes to the pull request, with what doesn't apply named (no GPU or touch driver yet).
- **Stop if:**
  - `omamobile-firstboot` fails (keep its journal);
  - any partition outside `UFS_RW` is writable (`reboot-to bootloader` at once);
  - stock boots: decline the factory reset, and follow the steps above.
- **Rollback:** reinstall U3's image (U3's commands; `device/husky/build-u3-root` rebuilds it). Or `fastboot --set-active=b` after a fallback. Or `fastboot --set-active=a`, after which stock needs a factory reset.
- **Risk:** low for the hardware: nothing new touches it. The trap is the fallback to stock after three boots, since stock then offers to factory-reset the install. Accepting erases `userdata`, and any stock boot means a fresh backup.

### U5 Hibern8 (gate f)
Let the UFS device runtime-suspend, with the link in hibern8. zuma's CAL has hibern8 entry and exit sequences (`post_h8_enter`, `pre_h8_exit`) that neither Tensor G3 nor G4 runs yet. Run it attended, from an `omamobile.initramfs` boot (in the klog overlay's `bootargs`, as U2), not under Arch: Arch's root is on `userdata`, so a link that drops mid-journal could cost a write.
- **Before:**
  - Stream the kernel log to the laptop in its own terminal (`tools/phone-ssh 'cat /dev/kmsg' > kmsg.txt`): the panel loses its last lines before a freeze.
  - Know the way out. A freeze defeats the `sysrq` fallback (BRINGUP-M1 tests 23-28), so Power + Volume Up for 15-30 s is the way out, then Power + Volume Down. On a dead link, `power/control` can't be set back either.
- **Step 1, read only** (done under Arch on test K's boot, which changed nothing):
  - The device W-LUN `0:0:0:49488` is `auto` and `active`.
  - `sda`-`sdd` and the boot and RPMB W-LUNs (`0:0:0:49456`, `0:0:0:49476`) are all `on`.
  - `rpm_lvl` is 3 (`SLEEP`, `HIBERN8`), `spm_lvl` 5, and `auto_hibern8` is empty.

  ufshcd links the other six LUNs to the device W-LUN as runtime-PM consumers (`ufshcd_setup_links`; `/sys/class/devlink` lists all six) [V], so the device suspends only when all six have.
- **Step 2,** for each cycle:
  - Arm a detached fallback first (`sleep 120; echo c > /proc/sysrq-trigger`). Cancel it only after this cycle's fresh ssh login, and arm a new one for the next cycle. If it fires, the panic reboot uses one of slot B's retries (above).
  - `echo auto` into `power/control` of `sda`-`sdd` and of both W-LUNs.
  - Wait for the device W-LUN's `runtime_status` to read `suspended`: at `rpm_lvl` 3 that is the device asleep with the link in hibern8.
  - Read one block of `boot_b` with `dd iflag=direct`. Without it, the page cache answers every read after the first, and the device never wakes.
- **Pass:** ten cycles, each with:
  - the device W-LUN suspends and resumes, and the direct read succeeds;
  - the guard's flags hold after the cycle (only `UFS_RW` writable, `sdb`-`sdd` `ro`, no `/dev/sda`);
  - kmsg shows no UIC error, no `ufshcd_err_handler` run and no reset.
- **Stop if:**
  - **a guard flag changed:** `reboot-to bootloader` at once (Power + Volume Up if it won't go down, then Power + Volume Down), and run no more cycles. The initramfs guard marks each disk once and never looks at that name again, and this boot never reaches the check before `switch_root`, so a LUN that a host reset dropped and re-added would come back writable. The per-cycle check is the only thing that would see it.
  - **an error handler run, a reset, or no answer:** if ssh still answers, put `power/control` back to `on`; otherwise use the buttons.

  Then add the CAL's hibern8 sequences before trying again. For context: on the Pixel 7 Pro, the first hibern8 exit at `spm_lvl` 3 needed a host reset (AGENTS.md, [SUSPEND-PLAN](../cheetah/SUSPEND-PLAN.md) S1). There, gs101's vendor `suspend` hook asserts the device reset (`HCI_GPIO_OUT`). Tensor G4's host data (which husky binds through its fallback compatible) had no such hook until kernel #83 (2026-10-27) added a `suspend` hook that holds the device in reset, as Google's driver does on zuma and zumapro, so that cause now carries over; its `drv_init` sets `spm_lvl` 5, and `UFSHCD_QUIRK_BROKEN_AUTO_HIBERN8` is why `auto_hibern8` is empty (L/`drivers/ufs/host/ufs-exynos.c`) [V].
- **Rollback:** `on` again, or a reboot: nothing persists.
- **Risk:** medium. A failed hibern8 exit can leave the link down until the host resets it. From the initramfs, nothing writes to UFS.

### U6 System suspend (after U5)
Omarchy's menu offers Suspend. At `spm_lvl` 5, system suspend powers the UFS device down and turns the link off, then re-initialises both on resume. That has run on neither Tensor G3 nor G4, so suspend on husky is untested until this step has its own runbook, written after U5 and on the model of the Pixel 7 Pro's [SUSPEND-PLAN](../cheetah/SUSPEND-PLAN.md).

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
| K | `husky-test-20261026-k` (`b5c7b15ed`). `uname -r` still reads `…-ge446d69d2ab2`: the kernel and modules are U2c's build, and only the DTB is rebuilt | U2c with #53's device tree at `28670f326`: two comments moved, and the debug carve-out ends where ABL's `debug_kinfo_reserved` begins |


| # | Test | Seen | Meaning |
| --- | --- | --- | --- |
| U1 | The port | builds; `dt_binding_check` and `CHECK_DTBS` clean for the UFS nodes | then rebased onto Tensor G4's merged UFS data (Design 1) |
| U2 | S's kernel + UFS (`…-g32f1eaffced5`), `omamobile.ufs-probe omamobile.initramfs` | probe, PHY calibration done, then `link startup failed 1` four times, `-EIO`; no disks | the device never answers on the link [V]. `gph5` reads `0x21`/`0x2`: the reference-clock pin is a GPIO driven low [V] |
| U2b | + the zuma pin controller, HSI2UFS only (`…-g536865667062`) | `gph5` reads `0x22` (both pins in function 2); link start-up still fails | not only the pins. `gpp0` reads `0x2010`/`0x8`: VCC is off [V] |
| U2c | + PERIC0 and VCC as stock's GPIO regulator (`…-ge446d69d2ab2`) | `Power mode changed to : FAST series_B G_4 L_2`; 4 LUNs, 62 partitions with stock's names on stock's nodes; only `UFS_RW` writable, `sdb`-`sdd` read-only, `/dev/sda` removed; a 64 MiB read of `boot_b` at 1.8 GB/s | **gate c passed**: UFS up behind the guard, as on stock [V] |
| U3 | U2c's kernel without `omamobile.initramfs`; `tools/install-phone` with the test root image (`device/husky/build-u3-root`, which rebuilds it with the same files) | the init grows the file system to all of `userdata` (108 GB) and switches to Arch; systemd `running`, no failed units, ssh with the installed key; the guard's read-only flags hold under Arch and `/dev/sda` stays gone; `reboot-to bootloader` from Arch reaches fastboot in 19 s; a second boot reaches ssh in 28 s | **gate d passed**: Arch on `userdata` [V] |
| K | U3's root, test K's images by `bin/omamobile flash` | Arch `running`, ssh. No `OVERLAP DETECTED`: ABL's `debug_kinfo_reserved@fd3fe000` is in the booted tree and `debug@fd3f0000` is 0xe000, and `/proc/iomem` reserves `fd3f0000-fd3fefff`, as before. `tools/phone-smoke`: boot (with the tool's bootconfig fix), storage guard, root, kernel health and USB ok; GPU, session and touch not ok (no drivers, no Omarchy). `slot-retry-count:b` 2 after this one boot, then 3 after `--set-active=b` | #53's head as published [V]. Every boot of slot B uses a retry, clean ones too [V] |

Findings:
- **ABL hands UFS over powered down:** VCC off and the reference-clock pin a GPIO driven low (U2, U2b). Stock's kernel sets both up itself, so mainline needs the pin controller and the GPIO regulator.
- **Hibern8 is untested, on Tensor G3 and on Tensor G4.** Here, the device never runtime-suspended, in the initramfs or under Arch, because the sd devices' runtime PM stays `on`. Tensor G4's UFS support didn't qualify it either.
- **Slot B's retries count every boot (test K).** With no boot-success marker, an install runs three boots and then falls back to stock, which can't read `userdata` (Runbook).
- **The full Omarchy image comes next (U4).** `tools/build-rootfs` needs `omamobile-device-husky` in the signed `[omamobile]` repository. U3's image used only Arch Linux ARM's base, so it has no desktop and no `omamobile-firstboot`. The user's answers sit unused in `/etc/omamobile/firstboot.conf`, and root logs in with the key.
- **System suspend is untested (U6),** as hibern8 is, on Tensor G3 and on Tensor G4.
- **No clock source:** with no RTC driver and no network time, the clock starts at the image's build date (it read Jul 24).
