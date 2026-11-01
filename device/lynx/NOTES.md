<!-- SPDX-License-Identifier: MIT -->
# Pixel 7a (lynx) bring-up notes

Findings from real hardware, newest first. Tracking issue: #36.

## 2026-10-27: Wi-Fi parked

- **The chip's boot ROM stops at its authentication stage,** `pbl_auth.c`, after reading only the ELF header and the hash segment of an image byte-identical to stock's. Every host-side difference two testers could act on was tried, one change per boot, and all were negative. The write-up, the ruled-out list, both stop conditions and what is left are in [WIFI-PLAN.md](WIFI-PLAN.md). The maintainer agreed on #36 that parking here is the right call.
- **Stock-side read done.** `WLAN_SECURE_BOOTN` (`0x1E22B24`), the register that stage consults, reads `0x0` under stock's `cnss2` in the link-up pre-BHI state and in mission mode (six reads), not the `0x11111111` seen on mainline after the stall. Two more registers differ: `PBL_WLAN_BOOT_CFG` `0x200` and `TLMM_PBL_BOOTSTRAP_STATUS` `0x40` under stock, 0 on mainline. Read with stock Android restored to slot A for an afternoon (Magisk root, `userdata` backed up first and Arch put back the same evening). None of the windowed reads hung on stock.
- **Two stop conditions.** No windowed chip register reads before `mhi_sync_power_up()` (that read hung HSI2 and rebooted the other tester's phone), and no userspace reads of the HSI2 SysMMU or iATU blocks (`devmem` of `0x145c000c` reset this one). WIFI-PLAN.md section 6.
- **State:** the published kernel has no PCIe node for lynx and the Wi-Fi branch stays local; on the test phone `pcie_gs201` and `ath11k_pci` stay blacklisted. Bluetooth, on the same chip, waits on the same question.
- **Reinstalling Arch after the stock afternoon** needed `install-phone --bootloader-slots-match lynx-17.0-15199429` again. The root image carried package 0.1.0, without the marker, so the slot was marked successful once by hand with 0.2.0's `omamobile-boot-success` and its unit enabled. The PMIC RTC came back with stock's date; `hwclock -w` after setting the clock fixed it.

## 2026-10-24: Wi-Fi bring-up (not working yet)

- **The Wi-Fi chip is a Qualcomm QCA6490 (`17cb:1103`, subsystem `17cb:0108`) on PCIe channel 1,** not the Broadcom part in the Pixel 7 Pro. Linux drives it as WCN6855 hw2.1 through ath11k. Bluetooth is on the same chip.
- **Power pins, from the stock tree:** `gph2-5` enables the 0.95 V buck (stock name `bt-0p95-en`), and `gph2-4` is WLAN_EN. Stock raises the buck, then WLAN_EN, then waits 1 ms and brings up the link. BT_EN is `gpp16-2` on the PERIC1 pin controller (`0x10840000`), which our tree does not describe yet. The PCIe wake line `gpa6-1` only lets the chip wake the host.
- **Local, unsigned kernel branch `omamobile-gs201-lynx-wifi`** (on the touch branch). It imports the gs201 PCIe host, PHY and SysMMU drivers from `omamobile-int`. The board commit describes the two power pins as the root port's supply, with no restricted DMA pool: such a pool hands out at most 256 KiB in one piece, and MHI needs 512 KiB. A test-only `msi=1` adds MSI through iMSI-RX. A test-only `skip_soc_reset` stops ath11k from resetting the chip. Test-only `bhi_zero_from` and `bhi_flip_at` corrupt the image MHI hands over.
- **Working:** link Gen2 x1, enumeration, 32 MSI vectors, and the chip reading host memory.
- **Not working:** the chip's boot ROM stalls during the first firmware load (BHI), after about 20 s MHI times out with -110. `TCSR_PBL_LOGGING` reads `0xef0a0002`. `BHI_STATUS` stays 0, no MSI arrives, and neither end logs an AER error or completion timeout.
- **Bisecting the image shows where it stalls:**

  | Image handed to the chip | Boot ROM ends at |
  | --- | --- |
  | real image | `0xef0a0002` |
  | all zeros | `0xef128100` |
  | hash segment (offset 0x1000) zeroed | `0xef0a0125` |
  | code from 0x2000 zeroed | `0xef0a0002` |
  | one byte flipped in the header hash (0x1028) or the first segment hash (0x1068) | `0xef0a0002` |

  So the boot ROM reads the ELF header and the hash table's header, then stalls before it checks a single hash. The hash segment holds plain SHA-256 hashes with no signature. The Pixel's own `amss20.bin` stalls at the same stage, so the image is not the cause.
- **Ruled out:** firmware signing, cache coherency, power-up timing (also tried after several minutes powered off), the S2MPU, SysMMU bypass, Relaxed Ordering and No Snoop, read request size, ath11k's SOC global reset, the QFPROM shutdown bit (`0x1F8031C` reads `0x62`), and the BT_EN pin held high (stock raises it about 1 s before WLAN_EN). That BT_EN test was the pin only: `gpp16-2` set high with `devmem` several seconds before the buck, with no Bluetooth firmware over the UART. FlorencioJP later ruled Bluetooth out from stock's side (WIFI-PLAN.md section 4).
- **Stock (dmesg from 2026-10-23):** the BHI load finishes in 57 ms. Stock runs with the SysMMU translating (image buffers near `0xfa880000`, in `wifi_region`), a 36-bit DMA mask, PCIe I/A on, L1.2 on, and three MSI vectors for MHI. Here the SysMMU is bypassed (control register `0x24`), the device has no IOMMU group, and DMA uses physical addresses.
- **Next, as of this entry:** run with the SysMMU translating as stock does, then with I/A on, then check the chip's supplies. The PCIe PHY rails are S2MPG13 `LDO3S` and `LDO18S`, both always-on in the stock tree. (Superseded: see the 2026-10-27 entry and [WIFI-PLAN.md](WIFI-PLAN.md).)
- **Firmware on the phone** lives in `/usr/lib/firmware/updates/ath11k/WCN6855/hw2.1`: linux-firmware `amss.bin` and `m3.bin`, plus the phone's own calibration as `board.bin`. Nothing from the vendor image goes into this repo.
- **`devmem` here takes only `ADDRESS [VALUE]`.** A second argument is written as a value, not read as a width. Reading SysMMU offset `0x145c000c` crashed the phone.

## 2026-10-24: touchscreen, RTC and slot retries

- **The touchscreen is a Goodix GT9895 on SPI0 (USI0),** chip select `gpp20-3`, interrupt `gpa7-0` (falling edge), reset `gpp23-2`. Kernel branch `omamobile-gs201-lynx-touch` adds it to `goodix_berlin_spi` with the Berlin D register addresses. Touch works in the Hyprland session, with no checksum errors over about 1000 interrupts.
- **The GT9895 sends 14-byte contact records,** not the 8 bytes the Berlin driver assumed. With 8 every report failed its checksum. The driver now takes the record size from the chip's match data.
- **ABL leaves the touch supplies off.** The first probe read all zeros ("device confirm failed") and the interrupt line stayed low after reset. The supplies are S2MPG12 `LDO25M` (vddio, 1.6 to 1.95 V) and `LDO26M` (avdd, 3.0 V, not felix's 3.3 V), from the stock tree. The board file describes the PMIC on ACPM and hands both LDOs to the touch node. The AOC mux on `gph1-0` is not involved.
- **The S2MPG12 RTC sets the clock at boot,** now that the PMIC is described. The "No RTC" entry below no longer applies.
- **Slot B has three retries after `fastboot --set-active=b`, and each unmarked boot uses one.** The fourth push in a row booted slot A, where Android shows "Cannot load Android system" (shared `userdata`). It was not a bad DTB. `fastboot --set-active=b` from the bootloader menu (Power + Volume Down) brought slot B back. Never pick "Factory data reset" there: it wipes the Arch root.
- **devinfo is `sdd1`, layout 3.15, the same as the Pixel 7 Pro.** Slot B's flags are byte 0x35. `omamobile-bootctl mark-successful` changed it from `04` to `06`, and the retry count stayed. `omamobile-device-lynx` 0.2.0 ships the Pixel 7 Pro's `omamobile-boot-success` unit, which does this after every boot. The bytes against `fastboot getvar` are in [BRINGUP-M1.md](BRINGUP-M1.md#devinfo-against-fastboot-2026-10-27-g38b5a04d67e0-device-lynx-020).
- **The on-screen keyboard (squeekboard) appears** for text fields in the session, as well as at the PIN prompt.

## 2026-10-24: Arch root on userdata

- **`tools/install-phone` works on lynx.** It flashed slot B's five boot images and a root image built with `DEVICE=lynx tools/build-rootfs`, set B active and rebooted. The phone booted into the Arch root on `sda31` (grown to 109 GiB), `omamobile-firstboot` created the user, and SDDM logged in to Hyprland on simpledrm. Slot A's Android does not boot after this (shared `userdata`).
- **The bootloader reports only the current slot's version.** `install-phone` needs `--bootloader-slots-match`. Slot B's `lynx-17.0-15199429` comes from stock's `getprop` while it ran from slot B (`ro.boot.bootloader`), the same as slot A.
- **`omamobile-device-lynx`** is felix's package without the lid drop-in: storage guard rule, USB address, power-key drop-in, mirrorlist, `reboot-to`. No boot-success marker yet, so slot B stays unmarked.
- **No RTC.** The clock starts days behind (2026-10-18 on the first boot), and `pacman-key --populate` skips a signing key created "in the future", so the keyring step of `omamobile-firstboot` can fail. Setting the clock and repopulating fixes it.
- **The lock screen blanks after about 10 seconds** and nothing wakes it without touch. `qs ipc call lock wake` lights it again, and the PIN can be typed with `wtype`. `loginctl unlock-sessions` does not unlock it.
- **`systemd-firstboot.service` fails** (status 208/STDIN): no console with `console=null`. `omamobile-firstboot` already sets the host name, time zone and locale.

## 2026-10-24: on-screen console and UFS

- **UFS works with cheetah's nodes.** The board file enables `ufs_0` and its PHY with an always-on fixed VCC (stock drives it from `gpp0-1`, boot-on, as on cheetah). The link comes up at `FAST series_B G_4 L_2`, as on stock. The part is an SK hynix `HN8T05DEHKX073` (fw G002): `sda` 128 GB (31 partitions, `userdata` is `sda31`, 109 GiB), `sdb` and `sdc` 32 MiB each (10 partitions), `sdd` 4 MiB (4). No UFS errors at boot.
- **`poweroff -f` does not fully power off.** PSCI system-off stops the SoC (USB and SSH go away), but the panel stays lit with its last frame and Power alone does nothing. Holding Power for about 30 seconds force-restarts the phone (back into slot B), so a real power-off goes through the bootloader menu. Probably the PMIC rails stay up with no S2MPG12 driver; not investigated.
- **The storage guard holds on lynx.** It removes `/dev/sda`, sets `sdb`, `sdc` and `sdd` read-only, and leaves exactly six partitions writable: `boot_b`, `init_boot_b`, `vendor_boot_b`, `vendor_kernel_boot_b`, `dtbo_b` (`sda20` to `sda24`) and `userdata`. The first UFS boot ran with `omamobile.initramfs` on the vendor cmdline, so the init did not touch `userdata`.
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
