<!-- SPDX-License-Identifier: MIT -->
# Pixel 8 Pro (husky) bring-up notes

Findings for the Pixel 8 Pro port, newest first. husky shares the zuma SoC (Tensor G3) with the Pixel 8 (shiba) and 8a (akita, [issue #1](https://github.com/derekross/omarchy-mobile/issues/1)), so the SoC work is shared with those ports. Facts are marked [V] (checked, with the source) or [I] (an inference to check on a phone). Stage 0 flashed and booted nothing of ours: its only write was a Magisk-patched stock `init_boot_b` for the root capture (part 4), since rolled back. Our own builds run on slot B from M1 on ([BRINGUP-M1.md](BRINGUP-M1.md)).

Sources:

- `R/`: read-only queries of a retail Pixel 8 Pro (`bin/omamobile capture`, no root): facts only, no serials, IMEI or MACs.
- `U/`: upstream Linux (torvalds/linux master, 2026-10-21).
- `P/`: postmarketOS pmaports `device/testing` (2026-10-21).
- `G/`: Google's GPL kernel for this phone, `android-gs-shusky-6.1-android16` ([source.android.com: Build Pixel kernels](https://source.android.com/docs/setup/build/building-pixel-kernels)).

## 2026-10-31: a second phone: Kioxia 256 GB, UFS 4.0

A second retail Pixel 8 Pro, first run through the same read-only steps. `R2/` below means read-only queries of this phone (`adb shell getprop` while booted, `fastboot getvar all`, the fastboot screen), facts only, no serial, IMEI or MACs. The kernel is `omamobile` at `1c5ba1aa2` unless noted.

- **Storage differs from the first phone** [V] (R2/ getvar): `storage-vendor:KIOXIA`, `storage-model:THGJFJT1E45BATPC`, `storage-capacity:256 GB`, `storage-protocol:4.0`, `storage-rev:0300`, `storage-power-mode:lanes=2 gear=4 mode=FAST hs_series=SERIES_B`. The device reports the UFS spec version `0x0400`, `manufacturer_id=0x0198`, `ufs_features=0xB3` in sysfs (`device_descriptor/`), and a `raw_device_capacity` of `0x1DCBC000` 512-byte blocks (499,892,224); `sda` shows 499,490,816 sectors, 401,408 fewer, and that difference was not looked into [I]. The first phone is Samsung 128 GB, UFS 3.1: same link shape, different vendor and spec version.
- **The U2 probe passes on it** [V] (UFS-PLAN U2: `omamobile.ufs-probe` and `omamobile.initramfs` on the command line, no hand-over to Arch, nothing written to UFS). The existing driver brings the link up 0.28 s into boot (`exynos-ufshc 13200000.ufs: Power mode changed to : FAST series_B G_4 L_2`); SCSI sees `KIOXIA THGJFJT1E45BATPC 0300` on three well-known LUNs and four disks, 62 partitions: `sda` has 34 (`persist` is `sda1`, `userdata` is `sda34`), `sdb` and `sdc` are the boot LUNs with 12 each (`bl1`, `pbl`, `bl2`, `dram_train`, `abl`, `bl31`, `tzsw`, `gsa`, `gsa_bl1`, `ldfw`, `dpm`, `gcf`), `sdd` has `devinfo`, `pinfo`, `blenv` and `mfg_data`. The storage guard held: the allowlist was `boot_b init_boot_b vendor_boot_b vendor_kernel_boot_b dtbo_b userdata`, the whole-disk node `/dev/sda` was removed, and only those six partitions were writable. Both watchdogs said "watchdog inactive, reset disabled" and the phone stayed up.
- **dmesg lines seen** [V]: `exynos-clkout … probe … failed with error -22` and the `vdd-hba`/`vccq`/`vccq2` supply lines from `ufshcd_populate_vreg` ("assuming enabled"), also present on the first phone, per its owner: zuma's PMU is not in `clk-exynos-clkout`'s match table, and the device tree does not describe UFS's rails yet.
- **Revision** [I]: the fastboot screen reads `Product revision: husky MP1.0 B1`, which may be the silicon revision. The live `/proc/device-tree/soc_compatible` holds both `B0_FOPLP` and `B1_FOPLP` (product_id 0x9865, major 1, minor 0 and 1, pkg_mode 0), exactly as on the first phone, so it cannot tell them apart (it is the property our own DTB carries); the chip-ID block would, and no zuma chip-ID driver is bound yet.
- **Starting state** [V] (R2/): GrapheneOS `2026102101` (`CP3A.261005.005`, security patch 2026-10-05), bootloader locked with its own verified boot key, current slot b and `slot-unbootable:a:yes`: what a GrapheneOS update leaves behind, as on raven. Bootloader `ripcurrent-17.0-15681527` and baseband `g5300i-260604-260807-B-16036236` (the first phone had `…250605-250630…`), anti-rollback `ap-ar-ns`, `ap-ar-s`, `gsa-bl1-ar` and `gsa-fw-ar` all 3, `hw-revision` `MP1.0`, `ro.boot.dtbo_idx` 8, `boot`, `init_boot`, `vendor_boot`, `vendor_kernel_boot` and `dtbo` the same sizes as the first phone, `userdata` 0x3935215000 bytes. GrapheneOS's own signed `flash-all.sh` for the same version (read, not guessed: it flashes the same bootloader to both slots, forces slot A, radio to slot A, erases `userdata`) put it back on slot A, which then booted and showed `slot-successful:a:yes`, `slot-unbootable:a:no`, with slot B free. It needs an unlocked bootloader, and the bootloader was not locked again.
- **U4 on it** [V]: the signed development channel (39 packages, `omamobile-device-husky` 0.1.1) and Omarchy 4.0.6 stable, `tools/install-phone` with `--bootloader-slots-match ripcurrent-17.0-15681527`: boots, SDDM logs in, Hyprland and the Omarchy shell run, the lock screen shows. First boot hit #188: the clock started at 2026-10-18 and gpg skipped the release key (`key 8632C8075EB94673 was created 8 days in the future`); setting the clock over ssh and `pacman-key --populate omamobile` fixed it. `tools/phone-smoke` passes every required check (boot, storage guard, root, kernel health, USB gadget, session).
- **The display goes off about 43 s into the session; it is the lock screen's idle blank, and Power wakes it** [V]: Omarchy's lock service (`plugins/lock/Service.qml`) has an `idleBlankTimer` that runs `omarchy-brightness-display off` while the session is locked and idle, whose `off` branch is `hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'`. Caught with kernel audit watch rules on `omarchy-brightness-display` and `hyprctl`: the script ran at uptime 1100.657 s, `hyprctl` 26 ms later, and the DRM connector read `disabled`/`Off` by 1101.4 s (43.2 s after `systemctl restart sddm`). By hand the same dispatch with `action = "enable"` brings the display back at once and it stays on. On the test tag below, pressing Power wakes the blanked screen, and so does a tap on it (both reported by the phone's owner), and the key reaches the system (`KEY_POWER`); the lock screen then took a swipe up and the on-screen PIN pad by touch and unlocked (`unlocked` in the lock service's log). The `omamobile` head (`1c5ba1aa2`) has no `gpio-keys` node in `zuma-husky.dts` (the test tag has one, from #148), so on the head kernel no key can wake a blanked screen and there is no touch either [V: the device trees]; that is probably why the first boots looked like a dead panel [I]. Hyprland's log has `CDRMRenderer(drm): Can't create renderer, no matching devices found` and `drm: Failed to update renderer state … on applyCommit` from start-up on (the DRM device is `simple-framebuffer`, `/dev/dri` has only `card0`); the first DPMS enable after a disable worked regardless, so these lines are not what blanks it. Why the blank fires at about 43 s and not 5 s after the lock is not known [I].
- **Test tag `husky-test-20261031-c6`** (greenbrettmichael/linux-omarchy-mobile, kernel `7.3.0-rc6-omamobile-push1-gc7a0b2ef2f66`, the repository's husky config unchanged, then `modules-push` and a reboot) [V]: `dmesg | grep salixp` shows `sysinfo fw 0083 cxver ffff`, `afe cfg 03 cx 03 panel 03`, `sense echo yes events 2` and an input device `SALIXP Touchscreen`; the raw events of two rounds of hand taps (top-left, top-right, bottom-left, bottom-right, centre) decode to corners at x 57 to 1255 of 0..1343 and y 37 to 2962 of 0..2991, axes not swapped or flipped; `gpio-keys` gives `KEY_VOLUMEUP`, `KEY_VOLUMEDOWN` and `KEY_POWER`. If the modules are brought up by hand before a reboot, `acpm-protocol` can probe before `exynos-mailbox` (`no mailbox channel (-EPROBE_DEFER), skipped`, `16 channels, 0 usable`) and `salixp` then fails with `-ENODEV: enabling vdd`; after a reboot with the modules installed it says `16 channels, 16 usable` and the touch driver binds at about 3.7 s.

## 2026-10-31: the touchscreen

Touch works on a test kernel, [kernel #153](https://github.com/derekross/linux-omarchy-mobile/pull/153) (in review, stacked on #148). The test booted the U4 Omarchy image from `userdata` ([UFS-PLAN](UFS-PLAN.md)), with U4's kernel config.

- **The controller** [V, `R/` live DT]: an ST FTM5 (SALIXP, chip id `36 40`, firmware `0083`) on HSI0's USI2 SPI at `0x111d0000`.
  - It runs at 10 MHz with manual chip select, as stock's `fts` node.
  - Its attention line is `gpn0-0` (CUSTOM_ALIVE) and its reset is `gpp21-2` (PERIC1).
  - The panel is 1344 × 2992.
- **Its rails** [V, `R/` live DT]: the main PMIC's (S2MPG14) LDO25M at 1.8 V and LDO4M at 3.3 V. The firmware leaves both off, already at those voltages.
  - The PMIC sits behind ACPM, so #153 adds ACPM and its mailbox too.
- **Its clock** [V, `G/` CMUCAL tables]: the bootloader leaves USI2 at 399.36 MHz (PLL_SHARED2 / 2).
  - zuma had no clock driver, so #153 adds one: it describes the path from CMU_TOP to USI2.
  - It writes only USI2's divider and gates.
- **The scan echo** [V]: after the scan command, husky's firmware first reports a forced calibration (`43 05 01`), then echoes the command about 60 ms later.
  - The `salixp` driver gave up after 50 ms. #153 waits up to stock's 2.5 s and stops at the echo.
  - The touchscreen registers 3.8 s into the boot.
- **Orientation** [V, tag `husky-test-20261031-c5` on greenbrettmichael/linux-omarchy-mobile]: stock's node inverts both axes, but `salixp` already reports in the panel's orientation.
  - With stock's inversion, taps came in rotated 180°: a tap at the top-left read (1191, 2824).
  - Without it, a tap at the top-left reads (87, 144) of 1343 × 2991.
- **In Omarchy** [V]: Hyprland lists the touchscreen (`salixp-touchscreen`). The lock screen's PIN pad takes the keys that are touched, and the phone unlocks by touch. A touch wakes the screen.

## 2026-10-30: the buttons

Power and volume work through `gpio-keys` on a test kernel, the U4 kernel plus [kernel #148](https://github.com/derekross/linux-omarchy-mobile/pull/148) (in review). The test booted the U4 Omarchy image from `userdata` ([UFS-PLAN](UFS-PLAN.md)), with U4's kernel config.

- **The pins** [V, `R/` live DT]: power on `gpa4-0` (pull-up), volume down on `gpa4-1` and volume up on `gpa6-2`. All are active low, in the EINT function, and wake-up sources.
- **The ALIVE pin controller** [V, `R/` live DT]:
  - It is at `0x154d0000`, controller 0 of the driver's zuma data, with ten banks (gpa0–gpa4, gpa6–gpa10).
  - Each of its 50 pins has its own GIC interrupt, SPI 10–59 in pin order, level high, through a wake-up interrupt controller like Tensor G4's.
  - zuma's upstream device tree had no ALIVE node, so #148 adds it.
- **Events** [V, tags `husky-test-20261030-b` and `-b2` on greenbrettmichael/linux-omarchy-mobile]: a reader on `/dev/input/event0` (`gpio-keys`) logged a down and an up event for each press of volume down (`KEY_VOLUMEDOWN`), volume up (`KEY_VOLUMEUP`) and power (`KEY_POWER`).
- **In Omarchy** [V]:
  - A short press of power locks and darkens the screen, and the next one wakes it (omamobile-keys).
  - Volume does nothing visible yet, since there is no sound card.
- **The driver's `irq number not available`** [V]: once ALIVE was described, the zuma pinctrl data ran the GPIO EINT setup on ALIVE, whose banks are all wake-up EINTs, and it logged this line at every boot. #148 drops that setup from ALIVE, as gs101 does, and test `-b2` logs no such line.

## 2026-10-21: stage 0, part 4: root capture, backup, and how ABL picks the DTB

Root for the capture: the stock `init_boot` from the CP3A.261005.005 OTA, extracted with `payload-dumper-go` 2.1.0 (hashes checked against the signed payload) and patched with Magisk v31.0, the first release with Android 17 support. It was flashed to **`init_boot_b` only**, with slot B booted. Slot A was not written. The capture and backup were read-only (`su -c cat`), into `~/android/reference/husky-root-*` (never the repository).

- **Backup** [V]: all 60 partitions except `userdata`, `super` and the whole LUNs, about 1.5 GB. Each was hashed on the phone before and after the copy and on the laptop, and all three matched for every partition, at full size. Calibration first: `efs`, `efs_backup`, `persist`, `modem_userdata`, `devinfo`, `pinfo`, `mfg_data`, `trusty_persist`, `trusty_userdata`, `fips`, `frp`, `misc`, `blenv`.
- **Base DTB selection: not `/soc_id`** [V]. The four base DTBs in `vendor_kernel_boot` (none in `vendor_boot`; no `dt_table` header) have no `/soc_id` property, unlike gs201's. Instead each has a `/soc_compatible` node whose children carry `product_id = <0x9865>`, `major`, `minor` and `pkg_mode`: DTB 0 A0 FOPLP, DTB 1 A0 IPOP (`pkg_mode` 1), DTB 2 B0 + B1 FOPLP, DTB 3 B0 IPOP. ABL passes DTB 2 to this phone (live DT `/soc_compatible`: B0 and B1 FOPLP). So `bin/omamobile`'s `SOC_IDS` (one copy per `/soc_id` rewrite) doesn't fit zuma. It needs a `/soc_compatible`-based key (for example `SOC_COMPATIBLE="b0-foplp:0x9865:1:0:0 b1-foplp:0x9865:1:1:0"`). The phone's exact revision (B0 or B1) is [I].
- **Board dtbo: entry 8 of 19, `board_id 0x40206`, `board_rev 0x10000`** [V] (factory `dtbo.img` parsed; `androidboot.dtbo_idx = "8"` on Android 17).
- **Root `#address-cells = <2>`, `#size-cells = <1>`** [V], as on gs201 and gs101: 12-byte `reg` entries.
- **RAM banks** [V]: `0x80000000`, `0x880000000`, `0x900000000`, `0x980000000`, `0xa00000000`, `0xa80000000`, 2 GiB each (12 GiB). `reserved-memory` has 51 children: **30 fixed with `no-map`** (among them `gsa@90200000`, `tpu_fw@93000000`, `aoc@94000000`, `xhci_dma_dram@97000000`, `abl@f8800000`, `bldr_log_reserved@fd800000`), **7 fixed without `no-map`** (`ect_binary`, `ramoops_mem@fd3ff000`, the three `cp_rmem` regions, `cp_aoc_rmem`, `seclog_mem`) and **14 dynamic pools** placed by `size`/`alloc-ranges` (camera, faceauth, video codec, TUI). **The fixed DRAM ones must be copied from the live DT into the board DTS**; BRINGUP-M1 says which made it.
- **`/ect`** [V]: `parameter_address = <0x90000000>`, `parameter_size = <0x14000>` in the live tree, as on gs201. Stock's four base DTBs carry `parameter_size = <0x53000>`, which ABL rewrites at boot; our base DTB carries the base value.
- **Console** [V]: `uart0 = "/uart@10870000"`. Stock boots `console=ttynull`. The earlycon address for `VENDOR_CMDLINE` is `0x10870000` [I, from the alias; check the node's compatible].
- **Stock command line** [V]: `clk_ignore_unused`, `kvm-arm.mode=protected`, `bootconfig`, `androidboot.hardware.cpu.pagesize = "4096"`.
- `debugfs` summaries (clk, regulator, pinmux) are empty on the user build [V].
- **Rolled back** [V]: the stock `init_boot` (SHA-256 `c319cbae…`, checked before flashing) went back to `init_boot_b` (fastboot `OKAY`), then `--set-active=a`, and stock booted from `_a`. The bootloader refuses `fastboot fetch init_boot_b` ("Command failed"), so the write can't be read back from fastboot; that needs root on a booted slot [I].

## 2026-10-21: stage 0, part 3: stock on slot A, both slots matched

The full OTA `husky-ota-cp3a.261005.005` (Android 17, 2026-10-05; SHA-256 checked against Google's list) was sideloaded twice from recovery, which is Google's own way to make both Pixel 8 slots bootable. Pass 1 installed to A, pass 2 to B, and then `fastboot --set-active=a`.

- **Both slots: CP3A.261005.005, bootloader `ripcurrent-17.0-15681527`** [V]. Each slot was read from Android while it was the running slot (`ro.boot.slot_suffix`, `ro.build.id`, `ro.bootloader`). That is the confirmation `tools/install-phone --bootloader-slots-match ripcurrent-17.0-15681527` asks for.
- **Stock now runs from slot A** [V] (`_a` after `fastboot reboot`). `--set-active=a` reset A to `slot-successful:no`, `slot-retry-count:3`; it boots normally.
- The full OTA has no `pre-build` (`ota-type=AB`, `pre-device=husky`) [V], so it applied over the older Android 16 build. Anti-rollback only moves forward, so builds before CP3A.261005.005 are now off-limits on this phone [I].

## 2026-10-21: stage 0, part 2: `fastboot getvar all`

Read-only, from the bootloader; facts only (no serial, `soc-id` or storage serial).

- **`product:husky`, `hw-revision:MP1.0`, `secure-boot:PRODUCTION`, `unlocked:yes`** [V].
- **Only the current slot's bootloader is reported**: `current-slot:b`, `version-bootloader:ripcurrent-16.3-13642541`, with no per-slot `version-bootloader-a/b` [V]. Both slots are marked `slot-successful:yes`, `slot-unbootable:no`, retry count 2 [V]. So slot A holds a bootable build, but which bootloader is on it is unknown. This is the case `tools/install-phone` handles with `--bootloader-slots-match` after the other slot has been checked.
- **Anti-rollback counters 3** (`ap-ar-ns`, `ap-ar-s`, `gsa-bl1-ar`, `gsa-fw-ar`) [V]. Flashing a factory image with a lower rollback index than these is what bricks; only this build or newer.
- **Baseband `g5300i-250605-250630-B-13713258`** [V]: the S5300 modem family, like cheetah's [I].
- **Partition sizes** [V]: `boot`, `vendor_boot` and `vendor_kernel_boot` 64 MiB each, `init_boot` 8 MiB, `dtbo` 16 MiB, `vbmeta` 64 KiB, `pvmfw` 1 MiB, `modem` 200 MiB; `super` 7.95 GiB; `userdata` 117,744,685,056 bytes (109.7 GiB). `persist` 128 MiB f2fs; `efs` and `efs_backup` 64 MiB f2fs; `modem_userdata`, `trusty_persist` and `metadata` 64 MiB; `trusty_userdata` 128 MiB. The dynamic partitions are listed for slot B only (`system_b`, `system_dlkm_b`, `system_ext_b`, `product_b`, `vendor_b`, `vendor_dlkm_b`) [V], consistent with stock running from B.
- **UFS**: Samsung, UFS 3.1, 2 lanes, HS-G4 Series B [V] (`storage-*`).

## 2026-10-21: stage 0, part 1: a retail Pixel 8 Pro (stock, bootloader unlocked)

### Identity

- **husky, zuma, MP1.0** [V] (R/ `ro.product.device`, `ro.boot.hardware.platform`, `ro.boot.hardware.revision`). `ro.soc.model` Tensor G3. SKU G1MNW [V].
- **Nine CPUs in three clusters** [V] (R/ `/proc/cpuinfo`): four CPU part 0xd46 (Cortex-A510), four 0xd4d (Cortex-A715) and one 0xd4e (Cortex-X3).
- **12 GiB Samsung LPDDR5, 128 GB Samsung UFS** at `13200000.ufs` [V] (R/ `ro.boot.hardware.ddr`, `.ufs`, `ro.boot.boot_devices`). `MemTotal` is 11,827,196 kB.

### Bootloader and build

- **Stock build BP3A.250905.014** (Android 16, security patch 2025-09-05), **bootloader `ripcurrent-16.3-13642541`** [V] (R/). `ripcurrent` is zuma's bootloader family name [I]. The matching factory image is `husky-bp3a.250905.014` [I]: check its `android-info.txt` against this bootloader before relying on it.
- **Unlocked** [V] (R/ `ro.boot.flash.locked` 0, `vbmeta.device_state` unlocked, `verifiedbootstate` orange).
- **Stock is running from slot B** [V] (R/ `ro.boot.slot_suffix` `_b`). That conflicts with the project's model (stock on slot A, ours on slot B; CONTRIBUTING §3.1). Before any write, stock has to be on slot A, with the same bootloader version on both slots (`tools/install-phone` refuses otherwise). Which slot holds what, and whether slot A carries the same bootloader, needs `fastboot getvar all` (next step).
- `ro.boot.dtbo_idx` is 8 [V] (R/). The `board_id`/`board_rev` of that entry need the factory `dtbo.img` [I].

### Partitions

[V] (R/ `/dev/block/by-name`), four LUNs `sda`–`sdd`:

- **Slotted boot images: `boot`, `init_boot`, `vendor_boot`, `vendor_kernel_boot`, `dtbo`**, the same five as cheetah. So `BOOT_IMAGES="boot init_boot vendor_boot vendor_kernel_boot dtbo"`.
- **Other slotted partitions**: `abl`, `bl1`, `bl2`, `bl31`, `pbl`, `gsa`, `gsa_bl1` (new against gs201 [I]), `gcf`, `ldfw`, `tzsw`, `dram_train`, `dpm`, `modem`, `pvmfw`, `vbmeta`, `vbmeta_system`, `vbmeta_vendor`.
- **Not slotted**: `persist`, `efs`, `efs_backup`, `modem_userdata`, `devinfo`, `mfg_data`, `pinfo`, `fips`, `frp`, `klog`, `blenv`, `misc`, `metadata`, `trusty_persist`, `trusty_userdata`, `ufs_internal`, `super`, `userdata`. The backup set for CONTRIBUTING §3.3 adds `pinfo`, `trusty_persist` and `trusty_userdata` to cheetah's list [I].

### Mainline and community status

- **Upstream has no zuma** [V] (U/ `arch/arm64/boot/dts/exynos/google/`: only `gs101*`). Our kernel (`linux-omarchy-mobile`) has no zuma branch either [V] (`omamobile`, `omamobile-int` only).
- **No postmarketOS port** for shiba, husky or akita [V] (P/: the Google devices are blueline, flame, oriole, raven, bluejay and the Chromebooks, plus `soc-google-gs101`).
- So zuma starts from gs201 as the pattern and G/ as the register reference (CONTRIBUTING §5.2; derekross's guidance in #1: SoC dtsi, clocks and pinctrl, then a minimal `zuma-husky.dts` aimed at first light).

### Still needs a phone

1. ~~`fastboot getvar all`~~ (part 2) and ~~stock on slot A with matching bootloaders~~ (part 3).
2. ~~Root capture and backup~~ and ~~the dtbo entry~~ (part 4).
3. The exact silicon revision (B0 or B1), from a kernel log line or Google's GPL kernel's `soc_compatible` handling.
