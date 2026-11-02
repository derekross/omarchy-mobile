<!-- SPDX-License-Identifier: MIT -->
# Pixel 11 Pro XL (kodiak)

Tracking issue: https://github.com/derekross/omarchy-mobile/issues/199

## Stock facts (locked bootloader)

- Model: Pixel 11 Pro XL
- Codename: kodiak
- SoC: Tensor G6 (platform malibu, compatible "google,mbu")
- GPU: PowerVR
- RAM: 16 GB Samsung LPDDR5
- Storage: 512 GB Micron UFS 4.1
- Build: CD1A.260905.001.B1
- Bootloader: spacecraft-17.4-16262255
- Kernel: 6.12.69-android16-6-g5c5f2fea42dd-ab15835541-4k
- CPU: 6× 0xd8b (rev 1) + 1× 0xd8c (rev 0)
- Boot image header: v4
- DTB: in vendor_kernel_boot.img
- Display: Verisilicon DC9x00 DPU + MIPI DSI2
- dtbo_idx: 37

## Status

Stock facts collected. Bootloader still locked. Next: a §3.1 descriptor, the partition backup and a gated first-boot plan.
