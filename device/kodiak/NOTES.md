<!-- SPDX-License-Identifier: MIT -->
# Pixel 11 Pro XL (kodiak)

Tracking issue: https://github.com/derekross/omarchy-mobile/issues/199

## Stock facts

- Model: Pixel 11 Pro XL (`ro.product.model`)
- Codename: kodiak (`ro.product.device`)
- SoC: Tensor G6 (platform malibu; DT compatible `google,mbu`)
- GPU: PowerVR
- RAM: 16 GB Samsung LPDDR5
- Storage: 512 GB Micron UFS 4.1
- Build: CD1A.260905.001.B1
- Bootloader: spacecraft-17.4-16262255
- Kernel: 6.12.69-android16-6-g5c5f2fea42dd-ab15835541-4k
- CPU: 6× 0xd8b (rev 1) + 1× 0xd8c (rev 0)
- Boot image header: v4
- DTB: in `vendor_kernel_boot.img`
- Display: Verisilicon DC9x00 DPU + MIPI DSI2
- dtbo_idx: 37
- Bootloader unlocked: yes
- Current confirmed bootable slots: both (factory flash + full OTA sideload)

## Hardware from stock DTB (vendor_kernel_boot)

- Root compatible: `google,mbu` (no `soc_id` present)
- Display subsystem: `verisilicon,display-subsystem` + `verisilicon,dc9x00` DPU
- MIPI DSI2 hosts present
- UFS controller present (`ufs@3c2d0000`)
- Edge TPU: `google,edgetpu-malibu`
- AoC: `google,aoc`
- PMIC: `google,da9188mfd`
- GPU: PowerVR (no Mali nodes)

## Display and battery

- Physical resolution: 1344×2992
- Logical resolution: 1080×2404 @ 120 Hz, density 390
- LCD density: 480
- HDR: supported (types 2/3/4), max luminance 1000
- Battery: Li-ion, charge_full ~5265 mAh

## Status

Stock facts collected and both slots restored to factory.  
Device descriptor added in `device/kodiak/device.conf`.  
Ready for first slot-B experiments once the descriptor lands.
