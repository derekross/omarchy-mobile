<!-- SPDX-License-Identifier: MIT -->
# Pixel 3a (sargo) first-light policy

Minimal policy package for the Pixel 3a, version 0.1.0: no kernel, no
hardware services. Installation stages files only and enables nothing. The
optional system setup command sets the locale and time zone and enables
timesyncd. Bring-up and results: [device/sargo](../../device/sargo/NOTES.md).

- **Storage.** The Pixel 3a keeps every partition on eMMC (`mmcblk0`). The
  udev rules continue the initramfs guard in Arch (they do not set anything
  read-only themselves): the whole-disk node, the hardware boot areas
  (`mmcblk0boot0/1`) and the RPMB node are made inaccessible, and desktop
  tools ignore every partition but `userdata`.
- **USB.** The gadget the initramfs creates survives the switch to Arch;
  `usb0` keeps 172.16.42.1 with a fallback route below Wi-Fi's priority.
- **Power.** All four sleep modes are disabled until suspend is qualified on
  this phone; UPower powers off on critical battery (not yet qualified here).
- **Not included.** No boot-success marking: the Pixel 3a's slot flags are
  GPT attributes, and marking slot B needs a CONTRIBUTING.md §3.1 entry. An
  unmarked slot B gets three boot tries before the bootloader falls back to
  slot A.

The reboot helper and the USB policy are cheetah's (test/all checks they
match). Run test/all for a native build and staged-install checks.
