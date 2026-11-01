# Pixel 11 Pro XL (kodiak) bringup notes

Tracking: https://github.com/derekross/omarchy-mobile/pull/231

## Current state
- Bootloader unlocked
- Stock CD1A.260905.001.B1 on slot B (factory flash-all.sh)
- Slot A is the safety slot (do not flash)
- device.conf has partition sizes, AVB values, and confirmed board id/rev
- Critical calibration partitions backed up off-device with SHA-256 checksums  
  (persist, modem_a/b, nvdata, nvram, devinfo, trusty_userdata).  
  No classic efs*/modem_userdata nodes exist on this device.

## Still needed
- [x] Slot-B backup of stock boot images
- [x] Calibration partition backup (see above)
- [ ] First Omarchy build / flash to slot B

## Stock facts
- SoC: Tensor G6 (malibu), compatible "google,mbu"
- GPU: PowerVR
- RAM: 16 GB Samsung LPDDR5
- Storage: 512 GB Micron UFS 4.1
- Kernel: 6.12.69-android16-6-g5c5f2fea42dd-ab15835541-4k
- Boot image header: v4
- DTB lives in vendor_kernel_boot.img
- DTBO entry 37: id=0x80406 rev=0x10000
- Bootloader: spacecraft-17.4-16238327 (both slots)
