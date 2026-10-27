<!-- SPDX-License-Identifier: MIT -->
# Pixel Fold (felix) bring-up notes

Findings from real hardware, newest first. [BRINGUP-M1.md](BRINGUP-M1.md) is the first-light record.

## 2026-10-27: both triggers unmasked

- **Cover tear source.** On the earlier cover-rate boot, DECON1 `TRIG_CON` (`0x1c241030`) read `0x00003061` before the select, source DDI0. One store of `0x01003061` locked the host counter to the cover tear, DDI1, on `gpp0-4`. That is the finding from the issue #3 report. The inner pair is the DDI0 form at DECON0 `0x1c240030`.
- **This boot.** `uname -r` was `7.3.0-rc6-omamobile-push1-g485f83c27e5c-dirty`, slot B. The init wrote both pairs before SSH. After the boot, cover `TRIG_CON` read `0x01003061` and inner `TRIG_CON` read `0x00003061`. The DTB reserved `fac00000-fbb7ffff`. That reservation is linux-omarchy-mobile#72, which had not merged. The booted kernel was not that pull request's head. Before that reservation, a filter of `/proc/iomem` for `fac00000` printed no line. The only reserved splash line was `fc000000-fc89efff : reserved`. `0xfac00000` sat in System RAM, not in a reserved range of its own. DPP0 `RDMA_BASEADDR` (`0x1c0b0040`) read `fac00000`, and `RDMA_IMG_SIZE` (`0x1c0b0018`) read `08a00730`, 1840×2208. That is why the inner node uses that address. After the reservation, `/proc/iomem` showed `fac00000-fbb7ffff : reserved`.
- **What was on the panels.** Both simpledrm cards were connected. Hyprland listed the cover at 1080×2092 and the inner panel at 1840×2208, cover first, so the inner card was a second output rather than the splash. The session was running. This is not a brightness slider, a KMS mode, or DPMS.
- **The refresh oneshot was still installed.** `omamobile-cover-rate.service` was enabled and ran after the init's pair. Its line was 124.0 Hz, underrun clear, DDI1 already selected. It is not the descriptor change.

## 2026-10-26: the power key and the GPU in the published kernel

- **Power key.** linux-omarchy-mobile#41 (merged) describes `gpa10-0` on `gpio-keys`, so the 2026-10-22 entry's "not described" no longer holds. On `7.3.0-rc6-omamobile-push1-g9860657fffb1`, slot B, not marked successful: event0 advertised `KEY_VOLUMEDOWN`, `KEY_VOLUMEUP` and `KEY_POWER`, a short press read code 116 down then up, logind reported `HandlePowerKey` and `HandlePowerKeyLongPress` as ignore (`omamobile-device-felix` 0.1.2), and the phone stayed up. A long press was not tried.
- **GPU.** linux-omarchy-mobile#5 (merged) enables the Mali-G710. On `7.3.0-rc6-omandroid-push1-gb60e882f0c1f` Panthor bound at 151 MHz and glmark2-es2-drm ran on the cover's simple framebuffer with no GPU fault. The #41 boot's smoke test found no render node, so the GPU is not up on every image yet.

## 2026-10-23: cover touch id

- **Which boot.** The rail, chip-id, and attention lines below were read on an unpublished tree: the hinge-hall commit `994dd90` plus uncommitted work, `uname -r` `7.3.0-rc6-omandroid-push1-g994dd90ad7c3-dirty`, with an overlay that set `regulator-always-on`. linux-omarchy-mobile#27 and #32 carry the published versions. #27 is merged. A later boot of #32 head `b1b5f1fd6` (`7.3.0-rc6-omamobile-push1-gb1b5f1fd66ba`) had the driver enable the rails itself, with no `regulator-always-on`, and the cover still answered `36 40`. That boot was the built-in reader and a kernel overlay. A boot of #32 head `dd05dd347` (`7.3.0-rc6-omamobile-push1-gdd05dd347ad0`) loaded the blacklisted module by hand. The blacklist was not the package file. A test initramfs wrote `/etc/modprobe.d/omamobile-cover-touch.conf` and copied `exynos-mailbox.ko`, `acpm-protocol.ko`, `sec-acpm.ko`, and `salixp.ko` to `/root/fts`. It did not load them. The installed package was still `omamobile-device-felix` 0.1.1. Slot B was written by hand, to `boot_b`, `init_boot_b`, `vendor_boot_b`, `vendor_kernel_boot_b`, and `dtbo_b`, and was not marked successful. The boot logged `salixp spi0.0: chip id 36 40`, held each rail with one user, and left both disabled with no users after unbind. The reader does not load firmware or report touches.
- **How it was read.** Rails came from `/sys/class/regulator` (`state`, `microvolts`, `num_users`). Reset `gpp23-3` was driven as a GPIO and attention `gpa6-7` was read as a GPIO. Nothing read the PMIC's registers through debugfs.
- **Rails.** With no consumer, S2MPG12 LDO25M (`vdd-outer-ts`) and LDO26M (`avdd-outer-ts`) read disabled at 1.8 V and 3.3 V. ABL leaves both off. On the unpublished boot an overlay held them on, and they then read enabled at 1800000 µV and 3300000 µV. On the #32 head the driver held each rail enabled at those voltages, min equal to max, with one user and no `regulator-always-on`.
- **Chip id.** On both boots the cover controller answered `36 40`.
- **Reset and attention.** On the unpublished boot, after the rails had settled, the reader was unloaded and both rails stayed enabled. Holding cover reset `gpp23-3` low for 20 ms and releasing it: attention `gpa6-7` was low while reset was held, high at the release read, and low at 20 ms, 100 ms, and 500 ms. Reset was left released. Cover panel reset `gpp23-0`, inner touch reset `gpp23-2`, and inner panel reset `gpa7-1` were not written. S2MPG13 was left alone.
- **Backup.** The 2026-10-16 backup was checksum-verified when it was taken. Those checksums were not re-checked immediately before the first S2MPG12 regulator bind. The boots since then were slot B, and the slot was not marked successful. There is no record of a slot A boot since that backup.
- **Not on by default.** linux-omarchy-mobile#32 adds the cover controller and leaves it disabled. `device/felix/overlays/cover-touch.dtso` enables that path and does not set `regulator-always-on`. The always-on overlay was unpublished bring-up and is not in this tree. The inner panel and its touch controller stay undescribed.

## 2026-10-22: volume keys and the hinge hall

- **Volume keys.** Volume down is `gpa10-1` with a pull-up. Volume up is `gpa8-5` with no pull. Both are active-low. The factory groups are `key-voldown` and `key-volup`, and they are the Pixel 7 Pro's key pins. Each reported a press and a release on slot B.
- **Power key.** Factory `key-power` is `gpa10-0`, the S2MPG12 PWRONB line, active-low with a pull-up, the same line as the Pixel 7 Pro. It is not described. logind's built-in default is poweroff. Omarchy's settings set ignore, and `omamobile-device-felix` ships that same drop-in, so describing the key cannot power the phone off on the image we build, unless a local `/etc` drop-in that sorts later sets something else. Check with `busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandlePowerKey`. Suspend has not been tried on this phone. The long press stays the PMIC reset.
- **Hinge hall.** Factory `hall_sensor` (`hall,drv5032`) is `gpa2-3`, active-low, with no pull. The factory pin group is `hall_sensor_pinctrl`. Closed reads as shut and open reads as open. `gpa2` is an alive bank, so the mainline group sets no sleep pin config. logind treats `SW_LID` as a closed lid. `omamobile-device-felix` ignores that switch, so a folded phone does not suspend and the USB gadget stays up.

## 2026-10-20: stock panels and touch

The stock capture's build is `google/felix/felix:17/CP3A.261005.002.A1/2026100601`. That factory image's bootloader is `felix-17.0-15902555` and its radio is `g5300q-260604-260807-B-16036236`, the same strings `fastboot getvar` returned on this phone. Dtbo entry 10 is board id `0x30606`, rev `0x10000`, which matches `ro.boot.cdt_hwid` and `ro.boot.dtbo_idx`. The wiring below is from that overlay. Our board file still has neither panel node and neither touch node. The firmware names stay in the factory image.

- **Cover, the screen the simple framebuffer already scans.** Panel `samsung,ea8182-f10` on DSI 1. Reset pin `gpp23-0`. Supplies are S2MPG12 LDO27M (`vci`) and LDO23M (`vddi`), plus `disp_vddd`. Touch is `st,fts` on `spi_6` at 10 MHz. Clock and data are `gpp12-0` through `gpp12-2`, chip select `gpp12-3`. Interrupt `gpa6-7`, reset `gpp23-3`. `st,max-coords` is 1079 by 2091, the 1080×2092 cover. Supplies are S2MPG12 LDO25M (`vdd`) and LDO26M (`avdd`), the same two rails as the Pixel 7 Pro touch. Stock firmware name `ftm5_fw_f10_ext.ftb`. The node sets `st,sensor_inverted_x` and `st,sensor_inverted_y`.
- **Inner panel.** Stock calls it `samsung,ana6707-f10` on DSI 0. Reset pin `gpa7-1`. Supplies are S2MPG13 LDO28S (`vci`) and LDO4S (`vddi`), plus `disp_vddr`. Its touch is `st,fst2` on `spi_0` at 10 MHz, the same SPI port as the Pixel 7 Pro touch. Clock and data are `gpp20-0` through `gpp20-2`, chip select `gpp20-3`. Interrupt `gpa7-0` and reset `gpp23-2` are the 7 Pro's touch pins. `st,max-coords` is 2207 by 1839, the 2208×1840 inner panel. Supplies are S2MPG13 LDO22S (`vdd`) and LDO6S (`avdd`). Stock firmware name `ftm5_fw_f10.ftb`. The node sets `st,tx_rx_dir_swap`. Do not reset this panel or program its DSI.
- **Stock hands both controllers to the AoC.** Each touch node sets `goog,tbn-enabled` and `goog,offload-enabled`. A `touch_bus_negotiator` allows two devices, with `gph1-0` from the AP to the AoC and `gpa8-7` back. The vendor modules are `fst2.ko` and `ftm5.ko`.
- **Mainline binds neither compatible.** `drivers/input/touchscreen/stmfts.c` matches `st,stmfts` on I2C. These nodes are SPI compatibles `st,fts` and `st,fst2`.

## 2026-10-13: cover console

- **Slot B boots folded.** USB networking and SSH at `root@172.16.42.1`. Both cluster watchdogs are stopped. Slot B is not marked successful. Slot A stays GrapheneOS.
- **The cover console is the cover controller only.** ABL leaves DECON1 `TRIG_CON` (`0x1c241030`) at `0x3070`, which masks the hardware trigger, so the cover keeps the bootloader logo. Writing `0x3061` clears `HW_TRIG_MASK_DECON` and sets `HW_TRIG_EN`. That pair is `SIMPLEFB_TRIG_CON` in `device.conf`. The shared init writes it only when the board's first compatible string is this descriptor's `COMPATIBLE`, and the cover shows the Linux console. Kernel 7.3.0-rc6.
- **DECON0 `TRIG_CON` (`0x1c240030`) is the inner panel on this phone.** On this date it was not written. The inner frame count stayed frozen, and the inner panel kept the bootloader logo, including while folded. The 2026-10-27 section is the later boot, which writes it on purpose. Do not reset the panel or program its DSI.
- **The first-light board file** enables the USB controller and the cover framebuffer the bootloader is already scanning, and it leaves both panel nodes, both touch controllers, the GPU, and UFS disabled. That is kernel pull request #1.
- **The read-only guard was checked on 2026-10-16** (`uname -r`: `7.3.0-rc6-omandroid-push1-g056bfe463354-dirty`). `efs`, `efs_backup`, `modem_userdata`, `persist`, `modem_a`, `modem_b`, and `devinfo` were copied off the phone. The guard's `ufs-ro:` lines for those seven, and for the allowlist:

      omamobile: ufs-ro: /dev/sda1 (persist) set read-only
      omamobile: ufs-ro: /dev/sda19 (modem_a) set read-only
      omamobile: ufs-ro: /dev/sda20 (boot_b) left writable (allowlist)
      omamobile: ufs-ro: /dev/sda21 (init_boot_b) left writable (allowlist)
      omamobile: ufs-ro: /dev/sda22 (vendor_boot_b) left writable (allowlist)
      omamobile: ufs-ro: /dev/sda23 (vendor_kernel_boot_b) left writable (allowlist)
      omamobile: ufs-ro: /dev/sda24 (dtbo_b) left writable (allowlist)
      omamobile: ufs-ro: /dev/sda29 (modem_b) set read-only
      omamobile: ufs-ro: /dev/sda31 (userdata) left writable (allowlist)
      omamobile: ufs-ro: /dev/sda5 (efs) set read-only
      omamobile: ufs-ro: /dev/sda6 (efs_backup) set read-only
      omamobile: ufs-ro: /dev/sda7 (modem_userdata) set read-only
      omamobile: ufs-ro: /dev/sdd1 (devinfo) set read-only

  linux-omarchy-mobile#4 enables UFS. That boot did not pass the initramfs-hold argument.
- **`omamobile-device-felix`** does not run a guard loop of its own. The initramfs stops its loop before `switch_root`. What carries over is the kernel's read-only flags, plus this package's udev rule, which hides `sda` and the Android partitions from desktop tools. The USB unit sets 172.16.42.1. A replug may need a reboot, because nothing here closes the USB2 switch the way `omamobile-usb-rescue` does on the Pixel 7 Pro. It does not mark a slot successful and it does not start the radio, the charger, or a camera.

## 2026-10-13: stock facts

| Fact | Value | Source |
| --- | --- | --- |
| SoC | GS201, MP1.0, package mode 0, SoC rev 2. Same B0 match as cheetah (`soc_id` 0x09855001) | [V] `getprop` ro.boot.hw.soc.pkg_mode, ro.boot.hw.soc.rev, ro.boot.hardware.revision |
| Board id | 0x30606, rev 0x10000, dtbo index 10 | [V] `ro.boot.cdt_hwid`, `ro.boot.dtbo_idx` |
| Bootloader | felix-17.0-15902555, unchanged by the unlock | [V] `fastboot getvar version-bootloader` |
| Cover panel | 1080×2092, 120 Hz, DSI port 1. Active while folded (device state 0) | [V] `dumpsys display` |
| Inner panel | 2208×1840, 120 Hz, DSI port 0. Not described in the board file | [V] `dumpsys display`; Google `gs201-felix-display.dtsi` |
| Slots after the GrapheneOS reinstall | A successful and current. B bootable, not yet successful, not unbootable | [V] `fastboot getvar` |

The cover framebuffer is not the Pixel 7 Pro's splash. The inner address is the later DPP0 read in the 2026-10-27 section, not a copy taken from the 7 Pro tree before that read.
