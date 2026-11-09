<!-- SPDX-License-Identifier: MIT -->
# Pixel 11 Pro XL (kodiak) bringup notes

Tracking: https://github.com/derekross/omarchy-mobile/pull/231

## Current state
- Bootloader unlocked
- Stock CD1A.260905.001.B1 on slot B (factory flash-all.sh). On 2026-11-01 OrangeFox’s recovery replaced slot B’s vendor_boot (stock copy saved by the installer at backup/20261101-151204/vendor_boot_b before the rebuild).
- Stock recovery did not provide adb root, so OrangeFox was installed on slot B to take the read-only calibration backup.
- Slot A is the safety slot (do not flash)
- device.conf has partition sizes, AVB values, and confirmed board id/rev
- Critical calibration partitions backed up off-device with SHA-256 checksums  
  (persist, modem_a/b, nvdata, nvram, devinfo, trusty_userdata).  
- Calibration backup taken from OrangeFox recovery (read-only `dd` of the by-name nodes, pulled off-device, contents at that time; recovery may have mounted persist/metadata). Not a clean stock baseline.  
- OrangeFox was installed via the AIO installer (`install-desktop.sh`) after the factory flash and OTA sideload, and before the calibration backup.
- The installer replaced only the recovery part of `vendor_boot` on slot B. Slot A remains stock.
- It did not write `vbmeta`, `boot`, or `init_boot`.
- No plan to restore stock `vendor_boot` on slot A (it was never changed).
- Images and SHA256SUMS live in a local `kodiak-critical/` directory (not in the repository).  
- No classic efs*/modem_userdata nodes exist on this device.

## Still needed
- [x] Slot-B backup of stock boot images (taken before OrangeFox install; stock vendor_boot_b also saved by the installer at backup/20261101-151204/vendor_boot_b)
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
- Partition mapping (from recovery sysfs/by-name): all on sda — boot_b (sda23), init_boot_b (sda24), vendor_boot_b (sda25), vendor_kernel_boot_b (sda26), dtbo_b (sda27), userdata (sda42).
