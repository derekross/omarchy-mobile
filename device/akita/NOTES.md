<!-- SPDX-License-Identifier: MIT -->
# Pixel 8a (akita) bring-up notes

Findings for the Pixel 8a port, newest first. akita shares the zuma SoC (Tensor G3) with the Pixel 8 Pro (husky) and the Pixel 8 (shiba), tracked in [issue #1](https://github.com/derekross/omarchy-mobile/issues/1), so the SoC work is shared with [husky's port](../husky/NOTES.md). Facts are marked [V] (checked, with the source) or [I] (an inference to check on a phone). Stage 0 flashed and booted nothing of ours: its only write by hand was a Magisk-patched stock `init_boot_b`, for root on stock, and slot A's five boot images are Google's factory images byte for byte.

Sources:

- `R/`: read-only captures of a retail Pixel 8a with root (the live device tree, `fastboot getvar all`, the kernel log, `/proc`, `dumpsys`, and two partition backups), kept in `~/android/reference/`, never in the repository: facts only, no serials, IMEI or MACs.
- `F/`: Google's factory image `akita-cp3a.261005.005` (SHA-256 `416a76b2…`) and full OTA `akita-ota-cp3a.261005.005` (`daff3679…`), read on the laptop with `unpack_bootimg`, `avbtool info_image` and `mkdtboimg dump`.
- `G/`: Google's GPL device tree for akita, [kernel/devices/google/akita](https://android.googlesource.com/kernel/devices/google/akita/+/refs/tags/android-16.0.0_r0.10/dts/) at tag `android-16.0.0_r0.10`.
- `S/`: Google's GPL zuma SoC device tree, [kernel/devices/google/zuma](https://android.googlesource.com/kernel/devices/google/zuma/+/refs/tags/android-16.0.0_r0.10/dts/) at the same tag.
- `H/`: [husky's notes](../husky/NOTES.md) and [descriptor](../husky/device.conf), for what the two zuma phones share.

## 2026-11-11: buttons and touch (M3)

The buttons (gate f) and touch (gate g), so the phone is usable by hand. The steps and results are in [BRINGUP-M3](BRINGUP-M3.md). The kernel side is linux-omarchy-mobile#238 (the buttons and `mem_sleep_default=s2idle`, merged), #240 (the S2MPG14 supply setter) and #241 (the touch supplies, the touchscreen and the panel size).

- **The buttons are wired as on husky** [V]: volume down `gpa4-1`, volume up `gpa6-2`, power `gpa4-0` (G/ `zuma-common.dtsi`; R/ `/proc/interrupts`).
- **The touchscreen is a Goodix GT9895** [V], the Pixel 7a's chip, on husky's bus and lines (USI2_HSI0 SPI, interrupt `gpn0-0` falling, reset `gpp21-2`). Both of stock's firmware files (`goodix_firmware_ak3a.bin`, `_ak3b.bin`, in F/'s vendor image) carry `9895` in their Berlin header.
- **ABL leaves the touch supplies off, with LDO4M at 3.3 V** [V]. Stock runs it at 3.0 V (R/ live tree), and so does the 7a. The S2MPG14 LDOs couldn't set a voltage, so #240 adds a setter for LDO4M and LDO25M.
- **The S2MPG14's RTC keeps time** [V]. Once the PMIC is described, `rtc-s5m` registers it as `rtc0` and sets the clock at boot, so the clock is right after a reboot. With no PMIC interrupt, it has no alarm.
- **No GPU and no cpufreq yet**, so the session renders in software at ABL's CPU rates and is slow.

## 2026-11-06: storage and the Arch root (M2)

UFS with the storage guard (gate c) and Arch on `userdata` (gate d). The steps and results are in [BRINGUP-M2](BRINGUP-M2.md). The kernel side is linux-omarchy-mobile#206, merged as `75b9c0b73`.

- **UFS links at stock's mode** [V]: `FAST series_B G_4 L_2`, with husky's three board nodes (VCC on `gpp0-1`). All 62 partitions appear on stock's device nodes, and the guard leaves exactly `UFS_RW` writable, in the initramfs and under Arch.
- **The disks attach before PID 1** [V]: at 0.26 s, with `/init` starting at 0.28 s, because UFS is built in. The guard has flagged every partition by 0.61 s, and nothing is mounted before then.
- **The kernel's default sleep is `deep`** [V]: `/sys/power/mem_sleep` reads `s2idle [deep]` under Arch. Linux has no zuma SoC sleep sequence, so `omamobile-device-akita` makes Suspend use `s2idle`, as the Pixel 7 Pro's package does.
- **`NV_PARTS` names the radio's partitions only** (the Pixel 7 Pro's list, all present on akita). Other per-phone partitions it doesn't name:
  - `mfg_data`: factory data, which the Pixel 7 Pro's fingerprint stack reads a copy of ([cheetah's FINGERPRINT-PLAN](../cheetah/FINGERPRINT-PLAN.md));
  - `trusty_persist` and `trusty_userdata`: Trusty's persistent storage ([tegu's FINGERPRINT-PLAN](../tegu/FINGERPRINT-PLAN.md));
  - `pinfo`, `fips` and `blenv`, whose contents haven't been read [I].

  None is on `UFS_RW`, so the guard keeps them read-only, and all are in M2.4's full backup. Since stage 0's clean backup, `mfg_data`, `pinfo`, `fips`, `blenv` and `trusty_userdata` are unchanged, and `trusty_persist` changed (stock ran) [V]. The two Trusty partitions are now in `NV_BACKUP_EXTRA`, as on the Pixel 8 Pro, so `tools/nv-backup --check` shows when Android has written Trusty's storage.
- **A second retail 8a passed M2.3, M2.4 and M2.6** on the same branch, with the same link, partition map and guard results ([#456](https://github.com/derekross/omarchy-mobile/pull/456)).

## 2026-11-03: first light (M1.3) and the console (M1.4)

Our kernel booted from slot B with the first-light board file, which has USB and no framebuffer. A second boot added the framebuffer. The steps and the builds are in [BRINGUP-M1](BRINGUP-M1.md).

- **The boot console reaches the panel** [V] (M1.4). This uses `simple-framebuffer` at 0xfac00000 (1080x2400, `a8r8g8b8`, stride 1080 × 4, `no-map` carve-out) and `SIMPLEFB_TRIG_CON="0x19470030 0x3061"`. simpledrm binds and fbcon runs at 67x75. Because `splash` reaches the command line, the init draws Omarchy's splash, and the panel shows it with the right geometry and colours. Text written to `/dev/tty0` afterwards shows over it.

- **ABL boots our five slot B images, and the initramfs runs** [V]. In kernel time, the init brings the USB gadget up at 0.37 s and SSH (`root@172.16.42.1`) at 0.38 s. All nine CPUs come online, and `MemTotal` is 7.3 GiB.
- **The booted tree is our DTB plus ABL's usual additions** [V] (`/sys/firmware/fdt`):
  - the RAM banks;
  - the four reservations it inserts itself (`pkvm_guest_firmware`, `sec_dram`, `sec_pt`, `debug_kinfo_reserved`);
  - `kaslr-seed` and the initrd range.

  It keeps both `/soc_compatible` children and names no splash carve-out.
- **The kernel command line is our DTB `bootargs`, then our `VENDOR_CMDLINE`, then ABL's own arguments** [V] (`/proc/cmdline`).
  - ABL replaces each `console=` with one `console=null`, as on husky (H/).
  - Its own arguments include `exynos_drm.panel_name=google-ak3b.80801e`, `tcpci_max77759.conf_sbu=0`, `arm64.nomte` and `id_aa64mmfr1.vh=0`.
  - Unlike cheetah's ABL (gs201, [its notes](../cheetah/NOTES.md)), this one keeps the vendor command line (`splash`, `plymouth.*`, `printk.devkmsg=on`, `bootconfig`).
- **Three display registers, read once each** from the SSH shell with the Google logo still on the panel [V]:

  | Register | Value |
  | --- | --- |
  | DPP0 `RDMA_BASEADDR_P0` (0x19900040) | `0xfac00000` |
  | DECON0 `GLOBAL_CON` (0x19470020) | `0x00000133` |
  | DECON0 `TRIG_CON` (0x19470030) | `0x00003070` |

  All three are husky's values (H/, [BRINGUP-M1](../husky/BRINGUP-M1.md) test 20). ABL's splash is at 0xfac00000, and the trigger is masked: `HW_TRIG_MASK_DECON` (bit 4) is set and `HW_TRIG_EN` (bit 0) clear.
- **The panel runs in DSI command mode** [V]. No mode in Google's driver (`display/panel-google-ak3b.c`, in the same repository as G/) sets `MIPI_DSI_MODE_VIDEO`; its modes set only `MIPI_DSI_CLOCK_NON_CONTINUOUS`. So, as on husky, frames reach the panel only once DECON0's trigger is unmasked. 0x3061 clears bit 4 and sets bit 0, hence `SIMPLEFB_TRIG_CON="0x19470030 0x3061"`.
- **The same driver gives the panel as 70 × 149 mm** (`width_mm`, `height_mm`) [V], which is where stock's reported DPI comes from: `dumpsys display` reads xDpi 391.885 and yDpi 409.127 for 1080x2400, which is 70.0 × 149.0 mm. That is larger than the glass: a 6.1-inch 20:9 panel is about 64 × 141 mm, and Google's touch node says `goodix,panel-height-mm = <141>`. The lit area measures 64 × 141 mm with a ruler [V], and that's what the board file carries since M3 (linux-omarchy-mobile#241), with stock's 70 × 149 named in its comment.
- **There is no `/sys/devices/soc0`** [V]: our kernel has no chip-id driver for zuma, so the silicon revision (B0 or B1) is still open.

## 2026-11-02: stage 0: a retail Pixel 8a (stock, rooted, bootloader unlocked)

### Identity

- **akita, zuma, MP1.0, SKU G6GPR** [V] (R/ `ro.product.device`, `ro.boot.hardware.platform`, `.revision`, `.sku`). `ro.soc.model` Tensor G3; launched with Android 14 (`ro.product.first_api_level` 34).
- **Nine CPUs in three clusters, as husky** [V] (R/ `/proc/cpuinfo`): four CPU part 0xd46 (Cortex-A510), four 0xd4d (Cortex-A715) and one 0xd4e (Cortex-X3).
- **8 GiB Micron LPDDR5, 128 GB Samsung UFS 3.1** (2 lanes, HS-G4 Series B) [V] (R/ `ro.boot.hardware.ddr`, `.ufs`, `getvar storage-*`). `MemTotal` is 7,754,796 kB. Husky's first phone has the same UFS; its second a Kioxia UFS 4.0 (H/).

### Bootloader, build and both slots

- **Starting point, 2026-11-01** [V] (R/): build CP3A.260905.009 (Android 17, security patch 2026-09-05), bootloader `akita-17.0-15681527`, unlocked (`ro.boot.flash.locked` 0, `vbmeta.device_state` unlocked, `verifiedbootstate` orange), stock rooted with Magisk 30.7 and running from slot B.
- **`getvar all`** [V] (R/; facts only): `product:akita`, `hw-revision:MP1.0`, `secure-boot:PRODUCTION`, `unlocked:yes`. As on husky, only the current slot's bootloader is reported. Anti-rollback counters 3 (`ap-ar-ns`, `ap-ar-s`, `gsa-bl1-ar`, `gsa-fw-ar`). Baseband `g5300o-260604-260807-B-16036236`.
- **Slot A started out `slot-successful:no`** (`slot-unbootable:no`, 3 tries) [V] (R/), and its five boot images were already byte-identical to the CP3A.261005.005 factory images (R/ pre-wipe backup against F/): an update staged on slot A that had never booted [I].
- **Both slots on CP3A.261005.005** [V]. The full OTA (`ota-type=AB`, `pre-device=akita`, no `pre-build`, post-build `google/akita/akita:17/CP3A.261005.005/16271449`, security patch 2026-10-05; F/) was sideloaded twice from recovery: pass 1 installed to slot A and booted it, pass 2 did the same for slot B. Each slot was read from Android while it was the running slot (`ro.boot.slot_suffix`, `ro.build.id`, `ro.bootloader`): CP3A.261005.005 with bootloader `akita-17.0-15681527` on both. That is the confirmation `tools/install-phone --bootloader-slots-match akita-17.0-15681527` asks for.
- **The October build keeps September's bootloader and modem firmware** [V] (F/ `android-info.txt`: `require version-bootloader=akita-17.0-15681527`, `require version-baseband=g5300o-260604-260807-B-16036236`), and the anti-rollback counters stayed at 3 (R/ `getvar` afterwards). Anti-rollback only moves forward, so no build older than the one installed goes on this phone [I].
- **A USB disconnect mid-sideload aborts the install with status 2** [V]: the laptop logged `USB disconnect` in the second the transfer stopped, and recovery answered `Install from ADB completed with status 2. Installation aborted.` The retry, with the cable left still, completed (`Total xfer: 2.00x`).
- **Then a factory reset, and root on slot B only** [V]. Magisk 31.1 patched the factory `init_boot.img`, keeping its AVB footer (`avbtool info_image`), and only `init_boot_b` was written (`fastboot flash init_boot_b`, then `--set-active=b`). Slot A's five boot images are now the factory images byte for byte, and slot B's are too, apart from `init_boot_b`, which is the patched image (R/ clean backup against F/). After the rooted boot both slots read `slot-successful:yes` (R/ `getvar`). Stock on slot A stays the way back; installing our build on slot B replaces the patch.
- **Magisk 31.1 has no root prompts** [V] (its release notes): `adb shell su` answers `Permission denied` until Shell is granted ahead of time in the app (Superuser tab, +).

### How ABL picks the DTB and the dtbo entry

- **The same four base DTBs as husky** [V] (F/ `vendor_kernel_boot`; none in `vendor_boot`): A0 FOPLP, A0 IPOP, B0 + B1 FOPLP and B0 + B1 IPOP, each with a `/soc_compatible` node and no `/soc_id`. They are S/'s `zuma_dtbs` (`zuma-a0-foplp`, `zuma-a0-ipop`, `zuma-b0-foplp`, `zuma-b0-ipop`).
- **This phone is IPOP** [V] (R/ live DT `/soc_compatible`: `B0_IPOP` and `B1_IPOP`, `product_id = <0x9865>`, `pkg_mode = <0x01>`; S/ `zuma-b0-ipop.dts`): ABL hands it the IPOP base DTB, where husky gets the FOPLP one (H/). So akita's `SOC_COMPATIBLE` is `b0-ipop:0x9865:1:0:1 b1-ipop:0x9865:1:1:1`, and our base DTB's `/soc_compatible` needs those two children. The exact revision, B0 or B1, is [I]: `/sys/devices/soc0/revision` reads 17 (R/), and its encoding isn't checked.
- **Board dtbo: entry 18 of 19, `board_id 0x40406`, `board_rev 0x10000`** [V] (F/ `dtbo.img`; R/ `androidboot.dtbo_idx` 18; G/ `zuma-akita-mp.dts`, the MP board overlay, model "ZUMA AKITA MP board based on ZUMA"). The other 18 entries are G/'s dev (0x40401), proto (0x40402), EVT (0x40403), DVT (0x40404) and PVT (0x40405) boards.
- **Stock's root compatible is `"google,ZUMA AKITA", "google,ZUMA"`** [V] (R/, G/). Ours follows husky's upstream style, `google,zuma-akita` [I] until its binding entry is written.

### Boot images and verified boot

- **The five slotted boot images, as husky** [V] (R/ `/dev/block/by-name`; F/): `boot`, `init_boot`, `vendor_boot`, `vendor_kernel_boot`, `dtbo`.
- **Headers** [V] (F/ `unpack_bootimg`): `boot` v4, the kernel only (no ramdisk, no OS version); `init_boot` v4, Android 17.0.0, patch level 2026-10, the generic ramdisk; `vendor_boot` v4, page size 0x800, no DTB; `vendor_kernel_boot` v4, page size 0x800, the four base DTBs and a ramdisk.
- **`vbmeta` chains `boot`, `init_boot`, `vbmeta_system` and `vbmeta_vendor`**, and holds hash descriptors for `vendor_boot`, `vendor_kernel_boot`, `dtbo` and the bootloader images [V] (F/ `avbtool info_image`). So, as on husky, slot B's `boot` and `init_boot` need AVB footers: partition sizes 0x4000000 and 0x800000 (R/ `getvar`, F/ footers), rollback index 1791158400 and security patch 2026-10-05 (F/), the values in husky's descriptor.
- **Partition sizes, the same as husky's** [V] (R/ `getvar`; H/): `boot`, `vendor_boot` and `vendor_kernel_boot` 64 MiB each, `init_boot` 8 MiB, `dtbo` 16 MiB, `vbmeta` 64 KiB, `modem` 200 MiB, `super` 7.95 GiB, `userdata` 117,744,685,056 bytes (109.7 GiB).
- **Stock's command line has the UART at `0x10870000`** [V] (F/ `vendor_boot`: `earlycon=exynos4210,0x10870000 console=ttySAC0,115200`, `bootconfig`; S/ `zuma.dtsi` `uart@10870000`), husky's `uart0` (H/).

### Memory

- **Root `#address-cells = <2>`, `#size-cells = <1>`** [V] (R/ live DT): 12-byte `reg` entries, as on husky.
- **RAM banks** [V] (R/): `0x80000000`, `0x880000000`, `0x900000000` and `0x980000000`, 2 GiB each (8 GiB): husky's first four (H/).
- **`reserved-memory`: 51 children, the same split as husky's** [V] (R/; H/): 30 fixed with `no-map`, 7 fixed without (`ect_binary`, `ramoops_mem@fd3ff000`, `cp_rmem`, `cp_msi_rmem`, `cp_rmem_1`, `cp_aoc_rmem`, `seclog_mem`) and 14 dynamic pools. Every region H/ names is at the same address (`gsa@90200000`, `tpu_fw@93000000`, `aoc@94000000`, `xhci_dma_dram@97000000`, `abl@f8800000`, `bldr_log_reserved@fd800000`). That all 51 match husky's region for region is [I] until the two live trees are compared.
- **`/ect`** [V] (R/): `parameter_address = <0x90000000>`, `parameter_size = <0x14000>`, as in husky's live tree.

### Display, touch and input

- **Panel: 1080x2400, with 60 and 120 Hz modes** [V] (R/ `dumpsys display`; G/ `zuma-akita-display.dtsi`, mode `1080x2400`). G/ describes two panels, `google,ak3a` and `google,ak3b`; this phone has the ak3b (R/ kernel log: `panel-google-ak3b` on the DSIM at `0x19440000`). Which panel another 8a has is [I].
- **DECON0 is at `0x19470000`** [V] (S/ `zuma-drm-dpu.dtsi`, `drmdecon@19470000`), as on husky. Its `TRIG_CON` value at handover hasn't been read on an 8a, so the descriptor writes no display register (no `SIMPLEFB_TRIG_CON`).
- **Touch: Goodix** (`goodix_ts0`), firmware `goodix_firmware_ak3b.bin`, matched to the panel [V] (R/ input devices, kernel log). **Fingerprint: Goodix** (`goodix_fingerprint`); **haptics: Cirrus CS40L26** (`cs40l26_input`); and `gpio_keys` [V] (R/ input devices).

### Partitions and backups

- **The same partitions as husky** [V] (R/ `/dev/block/by-name` against H/): four LUNs `sda`-`sdd`; slotted `abl`, `bl1`, `bl2`, `bl31`, `pbl`, `gsa`, `gsa_bl1`, `gcf`, `ldfw`, `tzsw`, `dram_train`, `dpm`, `modem`, `pvmfw`, `vbmeta`, `vbmeta_system`, `vbmeta_vendor` and the five boot images; not slotted `persist`, `efs`, `efs_backup`, `modem_userdata`, `devinfo`, `mfg_data`, `pinfo`, `fips`, `frp`, `klog`, `blenv`, `misc`, `metadata`, `trusty_persist`, `trusty_userdata`, `ufs_internal`, `super`, `userdata`.
- **Two read-only backups** [V] (R/): every partition except `userdata`, `super` and the whole LUN `sda` (63 partitions, 1.6 GB), each hashed on the phone before and after its copy and on the laptop, all three matching. One was taken before the wipe (on CP3A.260905.009), one of the clean, rooted phone.
- **Between the two, stock changed `efs`, `efs_backup`, `persist` and `modem_userdata`** (its modem stack writes them), along with `devinfo`, `frp`, `metadata`, `misc`, `trusty_persist`, `dram_train_a/b` and `ufs_internal`; `mfg_data`, `pinfo`, `fips`, `blenv` and `modem_a/b` didn't change [V] (R/). So later checksum checks compare against the clean backup.

### What `device.conf` rests on

The descriptor carries no comments; this table is its provenance.

| Key | Value | Mark | Source |
| --- | --- | --- | --- |
| `CODENAME`, `NAME`, `SOC` | akita, Pixel 8a, zuma | [V] | R/ `ro.product.device`, `ro.product.model`, `ro.boot.hardware.platform` |
| `COMPATIBLE` | `google,zuma-akita` | [V] | husky's upstream style (H/); the board DTS's first compatible, with its binding entry, in [linux-omarchy-mobile#192](https://github.com/derekross/linux-omarchy-mobile/pull/192) |
| `PACKAGE` | `omamobile-device-akita` | | the package doesn't exist yet; `bin/omamobile initramfs` builds the freestanding helpers when a package has no `omamobile-bootctl.c`, as for husky |
| `DTB` | `exynos/google/zuma-akita.dtb` | [V] | built from the board DTS in [linux-omarchy-mobile#192](https://github.com/derekross/linux-omarchy-mobile/pull/192); `bin/omamobile images` packs it ([BRINGUP-M1](BRINGUP-M1.md) M1.1) |
| `SOC_COMPATIBLE` | `b0-ipop:0x9865:1:0:1 b1-ipop:0x9865:1:1:1` | [V] | R/ live DT `/soc_compatible`; S/ `zuma-b0-ipop.dts` |
| `AVB_FOOTERS`, `AVB_ROLLBACK_INDEX`, `AVB_SECURITY_PATCH` | `boot:0x4000000 init_boot:0x800000`, 1791158400, 2026-10-05 | [V] | F/ `vbmeta.img` chain descriptors and the stock footers; R/ `getvar partition-size` |
| `DTBO_SOURCE`, `DTBO_BOARD_ID`, `DTBO_BOARD_REV` | the empty overlay, 0x40406, 0x10000 | [V] | F/ `dtbo.img` entry 18; R/ `androidboot.dtbo_idx`; G/ `zuma-akita-mp.dts` |
| `VENDOR_CMDLINE` | husky's line | [I] | H/; stock's UART is the same (F/) |
| `VENDOR_PAGESIZE` | 0x800 | [V] | F/ `vendor_boot` and `vendor_kernel_boot` headers |
| `OS_VERSION`, `OS_PATCH_LEVEL` | 17.0.0, 2026-10 | [V] | F/ `init_boot` header; the build on both slots (R/) |
| `BOOT_IMAGES`, `UFS_RW` | the five boot images; their `_b` names and `userdata` | [V] | R/ `/dev/block/by-name`; F/ |
| `NV_PARTS`, `NV_BACKUP_EXTRA` | `efs efs_backup modem_userdata persist modem_a modem_b`; `devinfo trusty_persist trusty_userdata` | [V] | R/ `/dev/block/by-name` has all nine, none on `UFS_RW`. `NV_PARTS` is cheetah's: the partitions of AGENTS.md §1's checksum check. `NV_BACKUP_EXTRA` is husky's (#449): `devinfo`, whose slot flags change with every flash, and Trusty's two partitions, which Android writes (`trusty_persist` changed while stock ran, M2.4). Together they let `tools/nv-backup` back them up read-only from our own kernel ([BRINGUP-M2](BRINGUP-M2.md), M2.4), and `--check` report the extras' changes |
| `INITRAMFS_INIT` | the shared init | [V] | as husky |
| `PANEL_SIZE` | 1080x2400 | [V] | R/ `dumpsys display`; G/ `zuma-akita-display.dtsi` |
| `SIMPLEFB_TRIG_CON` | `0x19470030 0x3061` | [V] | DECON0 `TRIG_CON` read 0x3070 at handover on a booted 8a (2026-11-03, above); 0x3061 unmasks the trigger as on husky (H/), and with it the console reaches the panel (M1.4, above) |
| `BRINGUP_PROBE` | unset | | its addresses are gs201's |

### Still needs the kernel or a phone

1. The board DTS, `zuma-akita.dts` on our `zuma.dtsi`, aimed at M1 (USB and SSH, then the simplefb console) as in [husky's BRINGUP-M1](../husky/BRINGUP-M1.md): the IPOP `/soc_compatible` children, `/chosen/bootargs`, the 1080x2400 framebuffer and the fixed `reserved-memory` regions from R/, with a binding entry for `google,zuma-akita`. USB and SSH work, and so does the framebuffer console (2026-11-03, above).
2. ~~DECON0's `TRIG_CON` at handover on an 8a, before `SIMPLEFB_TRIG_CON` goes in.~~ 0x3070, read 2026-11-03 (above).
3. The silicon revision (B0 or B1). `/sys/devices/soc0` doesn't exist under our kernel yet.
4. `omamobile-device-akita`.
