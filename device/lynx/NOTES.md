<!-- SPDX-License-Identifier: MIT -->
# Pixel 7a (lynx) bring-up notes

Findings from real hardware, newest first. Tracking issue: #36.

## 2026-10-24: on-screen console

- **simpledrm drives the panel through ABL's pipeline.** The board file reserves `0xfac00000` (`splash@fac00000`, no-map, 1080 x 2400 x 4 bytes) and adds a 1080x2400 a8r8g8b8 simple-framebuffer on it. simpledrm binds it, fbcon switches to it at 67x75 (Terminus 16x32), and the boot log and a shell prompt show on the panel. No panel driver: the framebuffer node has no panel phandle.
- **DECON0 TRIG_CON (`0x1c240030`) reads `0x3070` after ABL,** the same masked value as the Pixel 7 Pro. The initramfs writes cheetah's `0x3061` (`SIMPLEFB_TRIG_CON`), and it reads back `0x3061`. Without it the panel, a command-mode panel, keeps ABL's last frame. `BRINGUP_PROBE=1` logs `dpp0 cfg 0x40000004 base 0xfac00000`.
- **ABL rewrites the console arguments.** It drops our `console=tty0` from `bootargs` and appends `console=null`. fbcon still takes the framebuffer and the init's messages reach it.
- **Getting into fastboot without buttons works:** `omamobile fastboot` (reboot-to is ignored, so it crashes our Linux, ABL falls back to slot A, then `adb reboot bootloader`). Holding Volume Down during `reboot-to omamobile` was missed once: by the orange warning it is too late.

## 2026-10-23: first light

- **Slot B boots and SSH comes up at `root@172.16.42.1`.** Kernel 7.3.0-rc6 from linux-omarchy-mobile. Both cluster watchdogs are stopped at probe. Slot B is not marked successful. Slot A is stock CP2A.260705.006 with Magisk on `init_boot_a`.
- **ABL needs AVB footers on `boot` and `init_boot`.** Stock signs both with their own SHA256_RSA4096 keys, rollback index `1783209600`, and vbmeta chains them. With no footer, unlocked ABL never showed the orange warning for slot B. The screen went black, ABL retried until `slot-retry-count:b` reached 0, then booted slot A. Nothing reached USB and pstore stayed empty. Putting stock's own IPOP DTB into our `vendor_kernel_boot` failed the same way, so the DTB was not the cause. With `AVB_FOOTERS`, `AVB_ROLLBACK_INDEX` and `AVB_SECURITY_PATCH` (stock's values, from `avbtool info_image`) the next boot reached our kernel. The Pixel 7 Pro's stock `vbmeta` also chains `boot` and `init_boot`, with the same rollback index, and its bootloader is the same build (15199429), yet it boots our images without footers (checked by the maintainer on review). So this is the 7a's bootloader, not gs201 or the vbmeta layout. `vendor_boot`, `vendor_kernel_boot` and `dtbo` carry only unsigned hash footers on stock, and ours have none.
- **The DTB is matched on `/soc_compatible`.** The SoC is the IPOP package (`ro.boot.hw.soc.pkg_mode` 1, `ro.boot.hw.soc.rev` 2). Stock's `vendor_kernel_boot` holds three DTBs: `soc_id` 0x9855000, `soc_id` 0x9855001, and `/soc_compatible/B0_IPOP { product_id 0x9855, major 1, minor 0, pkg_mode 1 }`. The live stock tree is the third. One DTB with that node and no `soc_id` was accepted (`SOC_COMPATIBLE="b0-ipop:0x9855:1:0:1"`). Whether ABL would also take a `soc_id` DTB on this chip was not tried. Fastboot's screen says "Product revision: lynx MP1.0 B0".
- **ABL adds `sec_dram` (0xb7200000), `sec_pt` (0xe0000000) and `pkvm_guest_firmware` to the tree it hands over.** On our boot it put `pkvm_guest_firmware` at 0xb5000000, not 0x8b000000 as on stock. Stock's `tui` (48 MiB), `mfc_fw` and `famodel` are not fixed regions: Google's `gs101-dma-heap.dtsi` gives them a `size` and `alloc-ranges` only, and 0xf3200000 is just where stock's kernel placed `tui` on that boot (it goes to the secure world only during a Trusted UI session). The board file reserves none of them; an earlier version reserved `tui` at that address for nothing.
- **Reserved memory: distinguish the experimental and curated first-light boots.**
  The three overlap reports below are from the earlier experimental kernel
  `7.3.0-rc6-omamobile-push1-g1cb4bd36f3be-dirty`, captured in
  `lynx-m1-firstlight-20261023/dmesg.txt`. All reserved-memory lines and
  overlap reports are reproduced in kernel order, followed by the CMA and
  watchdog results (timestamps and unrelated lines omitted):

  ```text
  OF: reserved mem: 0x00000000b5000000..0x00000000b50cffff (832 KiB) nomap non-reusable pkvm_guest_firmware
  OF: reserved mem: 0x00000000fd3fe000..0x00000000fd3fefff (4 KiB) nomap non-reusable debug_kinfo_reserved@fd3fe000
  OF: reserved mem: 0x00000000e0000000..0x00000000e37fffff (57344 KiB) nomap non-reusable sec_pt
  OF: reserved mem: 0x00000000b7200000..0x00000000bfffffff (145408 KiB) nomap non-reusable sec_dram
  OF: reserved mem: 0x0000000090000000..0x0000000090039fff (232 KiB) nomap non-reusable ect@90000000
  OF: reserved mem: 0x0000000090200000..0x00000000905fffff (4096 KiB) nomap non-reusable gsa@90200000
  OF: reserved mem: 0x0000000091e00000..0x0000000092ffffff (18432 KiB) nomap non-reusable tpu-ctx@91e00000
  OF: reserved mem: 0x0000000093000000..0x0000000093ffffff (16384 KiB) nomap non-reusable tpu-fw@93000000
  OF: reserved mem: 0x0000000094000000..0x0000000096ffffff (49152 KiB) nomap non-reusable aoc@94000000
  OF: reserved mem: 0x0000000097000000..0x00000000973fffff (4096 KiB) nomap non-reusable xhci-dma@97000000
  OF: reserved mem: 0x0000000098000000..0x00000000984fffff (5120 KiB) nomap non-reusable gxp@98000000
  OF: reserved mem: 0x00000000c3000000..0x00000000c307ffff (512 KiB) nomap non-reusable seclog@c3000000
  OF: reserved mem: 0x00000000d8100000..0x00000000de01ffff (97408 KiB) nomap non-reusable dss@d8100000
  OF: reserved mem: 0x00000000e8000000..0x00000000e9ffffff (32768 KiB) nomap non-reusable cp-rmem1@e8000000
  OF: reserved mem: 0x00000000ea400000..0x00000000eabfffff (8192 KiB) nomap non-reusable cp-rmem@ea400000
  OF: reserved mem: 0x00000000f6200000..0x00000000f6200fff (4 KiB) nomap non-reusable cp-msi@f6200000
  OF: reserved mem: 0x00000000f8800000..0x00000000f97fffff (16384 KiB) nomap non-reusable abl@f8800000
  OF: reserved mem: 0x00000000fd3f0000..0x00000000fd3fffff (64 KiB) nomap non-reusable debug@fd3f0000
  OF: reserved mem: 0x00000000fd800000..0x00000000fd8fffff (1024 KiB) nomap non-reusable bldr-log@fd800000
  OF: reserved mem: 0x00000000fd90c000..0x00000000fd90cfff (4 KiB) nomap non-reusable suspend-diag@fd90c000
  OF: reserved mem: 0x000000008b000000..0x000000008b0cffff (832 KiB) nomap non-reusable pkvm-guest-fw@8b000000
  OF: reserved mem: 0x00000000b7200000..0x00000000bfffffff (145408 KiB) nomap non-reusable sec-dram@b7200000
  OF: reserved mem: 0x00000000e0000000..0x00000000e37fffff (57344 KiB) nomap non-reusable sec-pt@e0000000
  OF: reserved mem: 0x00000000f3200000..0x00000000f61fffff (49152 KiB) nomap non-reusable tui@f3200000
  OF: reserved mem: 0x00000000ffdf0000..0x00000000ffffffff (2112 KiB) nomap non-reusable mfc-fw@ffdf0000
  OF: reserved mem: 0x00000009ce900000..0x00000009d33fffff (76800 KiB) nomap non-reusable famodel@9ce900000
  OF: reserved mem: 0x00000000fd3ff000..0x00000000fd7fefff (4096 KiB) map non-reusable ramoops@fd3ff000
  OF: reserved mem: OVERLAP DETECTED!
  sec_dram (0x00000000b7200000--0x00000000c0000000) overlaps with sec-dram@b7200000 (0x00000000b7200000--0x00000000c0000000)
  OF: reserved mem: OVERLAP DETECTED!
  sec-pt@e0000000 (0x00000000e0000000--0x00000000e3800000) overlaps with sec_pt (0x00000000e0000000--0x00000000e3800000)
  OF: reserved mem: OVERLAP DETECTED!
  debug@fd3f0000 (0x00000000fd3f0000--0x00000000fd400000) overlaps with debug_kinfo_reserved@fd3fe000 (0x00000000fd3fe000--0x00000000fd3ff000)
  cma: Failed to reserve 384 MiB
  s3c2410-wdt 10060000.watchdog: watchdog inactive, reset disabled, irq disabled
  s3c2410-wdt 10070000.watchdog: watchdog inactive, reset disabled, irq disabled
  ```

  This experimental live tree contained `sec-dram@b7200000` and
  `sec-pt@e0000000` in addition to ABL's `sec_dram` and `sec_pt`. Those
  pairs cover identical ranges, but the extra nodes are not in the shared
  `gs201.dtsi` or the curated board file. The third report is a different
  problem: the shared 64 KiB `debug@fd3f0000` reservation contains ABL's
  4 KiB `debug_kinfo_reserved@fd3fe000`. It also intersects the first 4 KiB
  of `ramoops@fd3ff000`, although that pair is not printed in this capture.
  These are overlapping allocations, not evidence that all warnings are
  harmless duplicates. The shared debug reservation has since been fixed
  in `gs201.dtsi` (linux-omarchy-mobile #58 shrinks `debug@fd3f0000`), so
  a kernel from the current `omamobile` branch prints one overlap fewer.

  The later curated first-light capture, `lynx-m1-omamobile-20261023/dmesg.txt`
  from `7.3.0-rc6-omamobile-push1-g0661f78797ed`, has only the debug/kinfo
  overlap report; it has no `sec-dram@b7200000` or `sec-pt@e0000000` nodes.
  It still includes `tui@f3200000`, so neither of these captures proves the
  subsequent boot with the amended, no-`tui` DTB. The current board file
  adds only `ramoops`; its inherited shared reservations and ABL's additions
  remain separate from that board-local node.

  The CMA failure is consistent with `pkvm_guest_firmware` at `0xb5000000`
  splitting the otherwise available range below `sec_dram` at `0xb7200000`.
  On the Pixel 7 Pro the 384 MiB pool occupies `0x9f200000..0xb71fffff`.
  Nothing at first light uses that pool.

  The no-`tui` DTB was booted on 2026-10-24 at 17:35 CDT, on the later
  local integration kernel: `uname -r` is
  `7.3.0-rc6-omamobile-push1-g38b5a04d67e0` (a DTB-only replacement, so
  `uname` does not change), uptime three minutes, zero `tui` reservation
  lines in the boot journal, two `watchdog inactive` lines, and
  `pkvm_guest_firmware`, `ramoops` and `splash` still reserved. That is not
  a boot of the exact two-commit first-light tree; the `g0661f78797ed`
  capture above predates the removal of `tui`.
- **DPP0's RDMA base (`0x1c0b0040`) reads `0xfac00000`,** read once over SSH while the bootloader logo was on screen. That is the Pixel 7 Pro's address too. On stock it lies inside the `wifi_region` CMA pool (0xfa800000 to 0xfcffffff), so a simple-framebuffer here needs its own reservation (done on 2026-10-24, above).
- **The phone's DHCP server did not answer** NetworkManager on this laptop. A manual `172.16.42.2/24` on the host link worked.

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
