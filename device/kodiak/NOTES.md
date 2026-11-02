<!-- SPDX-License-Identifier: MIT -->
# Pixel 11 Pro XL (kodiak)

Tracking issue: https://github.com/derekross/omarchy-mobile/issues/199

## Stock facts

- Model: Pixel 11 Pro XL (`adb shell getprop ro.product.model`)
- Codename: kodiak (`adb shell getprop ro.product.device`)
- SoC: Tensor G6 / platform malibu (`adb shell getprop ro.boot.hardware.platform`, `ro.soc.model`)
- Root compatible: `google,mbu` (stock DTB from `vendor_kernel_boot.img`)
- `/soc_compatible` node present with one child:
  - A0: product_id=0x06, major=0x00, minor=0x00, pkg_mode=0x00 (no `/soc_id`)
- GPU: PowerVR (`adb shell getprop ro.hardware.egl` / `ro.hardware.vulkan`)
- RAM: 16 GB Samsung LPDDR5 (`adb shell getprop ro.boot.hardware.ddr`)
- Storage: 512 GB Micron UFS 4.1
- Build: CD1A.260905.001.B1 (`adb shell getprop ro.build.id`)
- Bootloader: spacecraft-17.4-16238327 on both slots (`fastboot getvar version-bootloader`, confirmed with `--set-active=b`)
- Kernel: 6.12.69-android16-6-g5c5f2fea42dd-ab15835541-4k (`adb shell uname -a`)
- CPU: 6× 0xd8b (rev 1) + 1× 0xd8c (rev 0) (`/proc/cpuinfo`)
- Boot image header: v4
- DTB: in `vendor_kernel_boot.img` (decompiled to confirm nodes)
- Display: Verisilicon DC9x00 DPU + MIPI DSI2 (stock DTB)
- dtbo_idx: 37 (`adb shell getprop ro.boot.dtbo_idx`)
- DTBO entry 37: id=0x80406 rev=0x10000 (factory `dtbo.img`)
- Bootloader unlocked: yes
- Current confirmed bootable slots: both (factory flash + full OTA sideload)
- ABL still appends `console=null` (`adb shell cat /proc/cmdline`)

## Hardware from stock DTB (vendor_kernel_boot)

- Root compatible: `google,mbu` (no `soc_id`)
- `/soc_compatible` → A0 (see above)
- Watchdogs: `google,wdt` @ 0x200c4000 and 0x200c5000
- UARTs: `goog,goog-dw-apb-uart` (uart0–10, serial0/1)
- Display subsystem: `verisilicon,display-subsystem` + `verisilicon,dc9x00` DPU
- MIPI DSI2 hosts present
- UFS controller present (`ufs@3c2d0000`)
- Edge TPU: `google,edgetpu-malibu`
- AoC: `google,aoc`
- PMIC: `google,da9188mfd`
- GPU: PowerVR (no Mali nodes)
- reserved-memory: includes `xhci_dma*`, `nvmem`, `boot_metadata`

## Display and battery

- Physical resolution: 1344×2992
- Logical resolution: 1080×2404 @ 120 Hz, density 390
- LCD density: 480
- HDR: supported (types 2/3/4), max luminance 1000
- Battery: Li-ion, charge_full ~5265 mAh

## Status

Stock facts collected and both slots restored to factory.  
Device descriptor added in `device/kodiak/device.conf`.  
Critical calibration partitions backed up off-device with SHA-256 checksums (persist, modem_a/b, nvdata, nvram, devinfo, trusty_userdata).  
