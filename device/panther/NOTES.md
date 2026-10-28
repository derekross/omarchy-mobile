<!-- SPDX-License-Identifier: MIT -->
# Pixel 7 (panther) bring-up notes

Findings from real hardware, newest first. [BRINGUP-M1.md](BRINGUP-M1.md) is the first-light record.

The board file (`gs201-panther.dts`) is in review as [linux-omarchy-mobile#108](https://github.com/derekross/linux-omarchy-mobile/pull/108); this repository's images were built from the local branch it came from.

## 2026-10-27: boot 6's fallback was a stock boot, and a new backup

When slot B ran out of retries (boot 6, [BRINGUP-M1.md](BRINGUP-M1.md)), ABL booted stock Android on slot A, which went to recovery because its `userdata` is now Arch. The data reset that recovery offers was **declined**: the phone was taken to fastboot with `adb reboot bootloader` and slot B flashed again.

- **Stock recovery wrote to the protected partitions.** Read back over SSH from Linux (read-only, each checked `ro=1` and by `PARTNAME`) and compared against the 2026-10-26 baseline: `modem_a` and `modem_b` match; `efs`, `efs_backup` and `modem_userdata` differ only in their F2FS checkpoint areas, `persist` in its ext4 superblock and journal (it now reads "needs journal recovery"), and `devinfo` in slot B's retry byte and two flag bytes. That is what a mount by recovery leaves, with no sign of data rewritten.
- **New backup.** All seven were read again and checksum-matched; that copy, kept off the repository with its `SHA256SUMS`, is the baseline from 2026-10-27. Any later stock boot, a fallback included, means another one.

## 2026-10-26: UFS behind the guard, and a fresh backup

- **UFS enumerates** (4 LUNs, 55 partitions, the same names and numbers as stock) and the initramfs guard leaves only slot B's five boot images and `userdata` writable. Details: [BRINGUP-M1.md](BRINGUP-M1.md), boot 4.
- **Fresh read-only backup.** `persist`, `efs`, `efs_backup`, `modem_userdata`, `modem_a`, `modem_b` and `devinfo` were read over SSH from the guarded initramfs (each checked `ro=1` and by `PARTNAME` first) and checksum-matched against the phone; the copy and its `SHA256SUMS` stay off the repository. All seven differ from the copy taken under LineageOS that morning, as expected: the factory image rewrote `modem_a`/`modem_b` (radio) and the slot flags in `devinfo`, and stock's first boot writes `efs`, `efs_backup`, `persist` and `modem_userdata`. This copy is the baseline from now on.

## 2026-10-26: first light

- **Console on the panel from boot** (boot 3): `simple-framebuffer` on `0xfac00000`, 1080x2400 ARGB8888, and the init writes DECON0 `TRIG_CON` `0x3061` (`SIMPLEFB_TRIG_CON`). Written by hand over SSH first (boot 2), then from the init.
- **Slot B boots** our kernel (`7.3.0-rc6`) with USB networking and SSH at `root@172.16.42.1`. Both cluster watchdogs are stopped, ramoops is at stock's `0xfd3ff000`. Slot B is not marked successful; slot A stays stock.
- **The bootloader scans the logo out of `0xfac00000`** (DPP0 `RDMA_BASEADDR_Y8`, read once over SSH), the same carve-out as the Pixel 7 Pro, which runs the same `cloudripper` ABL.
- **The splash is 1080x2400 ARGB8888** with no stride padding (DPP0 `RDMA_SRC_SIZE` `0x09600438`, `RDMA_IN_CTRL_0` format 0).
- **DECON0 `TRIG_CON` reads `0x3070`**: the hardware trigger is masked, so the panel keeps the logo until it is unmasked.
- **`reboot-to bootloader` did not reach fastboot.** `syscon-reboot-mode` is bound (`SYSIP_DAT0`, `mode-bootloader` 0xfc), but the phone rebooted straight back into slot B, and `/sys/fs/pstore` was empty on the next boot, so ramoops did not survive that reset. Not investigated yet; fastboot by the buttons meanwhile.
- **CMA:** the kernel's 384 MiB CMA reservation fails on this phone's 8 GB (`MemTotal` 7660972 kB). Nothing at first light needs it.

## 2026-10-26: stock facts

Captured on stock `CP3A.261005.002.A1` (Android 17, security patch 2026-10-05) on slot A, and from a rooted LineageOS 24 build on the same phone before it was restored. The captures stay off the repository.

| Fact | Value | Source |
| --- | --- | --- |
| SoC | GS201, MP1.0, package mode 0, SoC rev 2. Same B0 match as cheetah (`soc_id` 0x09855001) | [V] `getprop` ro.boot.hw.soc.pkg_mode, ro.boot.hw.soc.rev; live DT `/soc_id` |
| Board id | 0x30406, rev 0x10000, dtbo index 22 | [V] `ro.boot.cdt_hwid`, `ro.boot.dtbo_idx`; Google `gs201-panther-mp.dts:14-15` |
| Bootloader | `cloudripper-17.0-15902555`, the same ABL as the Pixel 7 Pro; radio `g5300q-260604-260807-B-16036236`. Both slots flashed from the factory image | [V] `fastboot getvar` |
| Boot images | `boot`, `init_boot`, `vendor_boot`, `vendor_kernel_boot`, `dtbo` on both slots, the same sizes as cheetah (64, 8, 64, 64 and 16 MiB) | [V] `fastboot getvar all` |
| Panel | `sdc-s6e3fc3-p10` (`samsung,s6e3fc3-p10`), 1080x2400, DSI 0 on DECON0 | [V] ABL's `exynos_drm.panel_name`, live DT, `dumpsys display` |
| Touch | FocalTech, `focaltech,ts` in the stock DT. Not cheetah's Synaptics: the TouchComm driver does not apply | [V] live DT |
| Charger, TCPC, gauge | MAX77759, as on cheetah | [V] live DT |
| Reserved memory | Every stock `reserved-memory` region that Google's tree describes matches gs201.dtsi. `sec_dram`, `sec_pt` and `pkvm_guest_firmware` are injected by the bootloader (not in Google's DTS); `cp_aoc_rmem` (0x197fd000) is AoC SRAM, not DRAM | [V] live DT against the built cheetah DTB; Google `gs201-rmem.dtsi` |
| Framebuffer | Not described in Google's tree: ABL injects it. Not copied from cheetah's `0xfac00000`; to be read from DPP0 on the first boot | [I] |
