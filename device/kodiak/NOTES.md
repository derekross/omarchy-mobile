# Pixel 11 Pro XL (kodiak)

Tracking issue: https://github.com/derekross/omarchy-mobile/issues/199

## Stock facts

- Model: Pixel 11 Pro XL (getprop ro.product.model)
- Codename: kodiak (getprop ro.product.device)
- SoC: Tensor G6 (platform malibu; DT compatible "google,mbu" from factory vendor_kernel_boot DTB)
- GPU: PowerVR (getprop ro.hardware.egl / ro.hardware.vulkan)
- RAM: 16 GB Samsung LPDDR5 (fastboot getvar ddr-size / ddr-manu / ddr-type)
- Storage: 512 GB Micron UFS 4.1 (fastboot getvar storage-*)
- Build: CD1A.260905.001.B1 (getprop ro.build.id)
- Bootloader: spacecraft-17.4-16262255 (fastboot getvar version-bootloader)
- Kernel: 6.12.69-android16-6-g5c5f2fea42dd-ab15835541-4k (uname -a)
- CPU: 6× 0xd8b (rev 1) + 1× 0xd8c (rev 0) (/proc/cpuinfo)
- Boot image header: v4 (unpack_bootimg on factory boot.img)
- DTB: in vendor_kernel_boot.img (unpack_bootimg)
- Display: Verisilicon DC9x00 DPU + MIPI DSI2 (factory DTB nodes)
- dtbo_idx: 37 (getprop ro.boot.dtbo_idx)
- Bootloader unlocked: yes (fastboot getvar unlocked)
- Current confirmed bootable slots: both (factory flash + full OTA sideload)

## Status

Stock facts collected and both slots restored to factory. Device descriptor in #231. Ready for first slot-B experiments once the descriptor lands.
