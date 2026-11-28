# omamobile-device-tangorpro

Omamobile's first userspace package for the Google Pixel Tablet (codename tangorpro, Tensor G2 / gs201). It hides the Android partitions from desktop tools, holds the USB address, and gives pacman the same `[omamobile]` repository as the Pixel 7 Pro. It also carries the Wi-Fi bring-up pieces (the Pixel 7's files, unchanged), which start nothing by themselves. It does not drive the charger, the dock or a camera, and it does not mark a boot slot successful. The tablet has no modem.

| File | Installed to | Why |
|---|---|---|
| `vendor/udev/rules.d/10-omamobile-storage.rules` | `/usr/lib/udev/rules.d` | Only `userdata` is visible to desktop tools; the whole-disk node is inaccessible |
| `vendor/systemd/network/20-usb-gadget.network` | `/usr/lib/systemd/network` | The tablet keeps `172.16.42.1/24` on the USB gadget |
| `vendor/systemd/logind.conf.d/10-omamobile-power-key.conf` | `/usr/lib/systemd/logind.conf.d` | Same power-key handling as the other gs201 ports |
| `vendor/NetworkManager/conf.d/10-omamobile-usb.conf` | `/usr/lib/NetworkManager/conf.d` | NetworkManager leaves the USB gadget to systemd-networkd |
| `omamobile-device-tangorpro.install` | pacman hook | Adds `[omamobile]` to `pacman.conf` before `[omarchy]`, once. Same script as the Pixel 7 Pro package |
| `src/reboot-to.c` | `/usr/bin/reboot-to` | Reboot with a reason (bootloader, recovery) |
| `bin/omamobile-wifi-start` | `/usr/bin` | Hang-safe Wi-Fi start: a hang marker, then `pcie_gs201` and `brcmfmac`. Same file as the Pixel 7's |
| `vendor/systemd/system/omamobile-wifi.service` | `/usr/lib/systemd/system` | Runs it, only on a DTB with PCIe GEN4A_1 enabled (`overlays/wifi.dtso`). **Not enabled at boot** until [WIFI-PLAN](../../device/tangorpro/WIFI-PLAN.md) passes |
| `vendor/modprobe.d/omamobile-wifi.conf` | `/usr/lib/modprobe.d` | Blacklists `pcie_gs201` and `brcmfmac` from autoload, so only the start script powers the chip |
| `bin/omamobile-wlan-mac`, `vendor/udev/rules.d/80-omamobile-wlan-mac.rules` | `/usr/bin`, `/usr/lib/udev/rules.d` | The interface gets the bootloader's MAC (`/chosen/config/wlan_mac1`), if it wrote one |
| `device.conf` | `/usr/share/omamobile/device.conf` | The descriptor, the same bytes as `device/tangorpro/device.conf` |
