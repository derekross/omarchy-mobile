<!-- SPDX-License-Identifier: MIT -->
# Pixel 7a (lynx) bring-up notes

Findings from real hardware, newest first. Tracking issue: #36.

## 2026-10-23: first light

- **Slot B boots and SSH comes up at `root@172.16.42.1`.** Kernel 7.3.0-rc6 from linux-omarchy-mobile. Both cluster watchdogs are stopped at probe. Slot B is not marked successful. Slot A is stock CP2A.260705.006 with Magisk on `init_boot_a`.
- **ABL needs AVB footers on `boot` and `init_boot`.** Stock signs both with their own SHA256_RSA4096 keys, rollback index `1783209600`, and vbmeta chains them. With no footer, unlocked ABL never showed the orange warning for slot B. The screen went black, ABL retried until `slot-retry-count:b` reached 0, then booted slot A. Nothing reached USB and pstore stayed empty. Putting stock's own IPOP DTB into our `vendor_kernel_boot` failed the same way, so the DTB was not the cause. With `AVB_FOOTERS`, `AVB_ROLLBACK_INDEX` and `AVB_SECURITY_PATCH` (stock's values, from `avbtool info_image`) the next boot reached our kernel. The Pixel 7 Pro has not needed footers, so this may be a lynx bootloader difference rather than gs201's. `vendor_boot`, `vendor_kernel_boot` and `dtbo` carry only unsigned hash footers on stock, and ours have none.
- **The DTB is matched on `/soc_compatible`.** The SoC is the IPOP package (`ro.boot.hw.soc.pkg_mode` 1, `ro.boot.hw.soc.rev` 2). Stock's `vendor_kernel_boot` holds three DTBs: `soc_id` 0x9855000, `soc_id` 0x9855001, and `/soc_compatible/B0_IPOP { product_id 0x9855, major 1, minor 0, pkg_mode 1 }`. The live stock tree is the third. One DTB with that node and no `soc_id` was accepted (`SOC_COMPATIBLE="b0-ipop:0x9855:1:0:1"`). Whether ABL would also take a `soc_id` DTB on this chip was not tried. Fastboot's screen says "Product revision: lynx MP1.0 B0".
- **ABL adds `sec_dram` (0xb7200000), `sec_pt` (0xe0000000) and `pkvm_guest_firmware` to the tree it hands over.** On our boot it put `pkvm_guest_firmware` at 0xb5000000, not 0x8b000000 as on stock. `tui` (0xf3200000, 48 MiB) is not added and gs201.dtsi does not reserve it, so the board file does.
- **DPP0's RDMA base (`0x1c0b0040`) reads `0xfac00000`,** read once over SSH while the bootloader logo was on screen. That is the Pixel 7 Pro's address too. On stock it lies inside the `wifi_region` CMA pool (0xfa800000 to 0xfcffffff), so a simple-framebuffer here needs its own reservation. Not done yet: the screen keeps the bootloader logo.
- **The phone's DHCP server did not answer** NetworkManager on this laptop. A manual `172.16.42.2/24` on the host link worked.
- `cma: Failed to reserve 384 MiB`, from the shared kernel config. Nothing at first light uses that pool.

## 2026-10-23: stock facts

| Fact | Value | Source |
| --- | --- | --- |
| Build | `google/lynx/lynx:17/CP2A.260705.006`, patch 2026-07-05 | [V] `getprop` |
| Bootloader, radio | `lynx-17.0-15199429`, `g5300q-260317-260505-B-15346003` | [V] `fastboot getvar` |
| SKU, hardware | GWKK3, MP1.0 | [V] `getprop` |
| SoC | gs201, rev 2, package mode 1 (IPOP) | [V] `getprop` ro.boot.hw.soc.* |
| RAM | 8 GiB LPDDR5, four ranges from ABL: 0x80000000, 0x880000000, 0x900000000, 0x980000000, 2 GiB each | [V] live DT `/memory` |
| Board dtbo | index 9: board_id 0x30506, board_rev 0x10000 | [V] `ro.boot.cdt_hwid`, `ro.boot.dtbo_idx`, stock `dtbo.img` table |
| Boot images | `boot`, `init_boot`, `vendor_boot`, `vendor_kernel_boot`, `dtbo`, A/B; `boot` 64 MiB, `init_boot` 8 MiB | [V] `fastboot getvar` |
| `vendor_boot` page size | 0x800, header v4 | [V] stock image header |
| Panel | `sdc-s6e3fc5`, 1080x2400, on DECON0 and DSIM0 | [V] `exynos_drm.panel_name`, `dumpsys display`, stock dmesg |
| Storage | 128 GB SK hynix UFS 3.1 | [V] `fastboot getvar` |
