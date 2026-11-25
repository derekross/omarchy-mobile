<!-- SPDX-License-Identifier: MIT -->
# Pixel 3a (sargo) first-light policy

Minimal policy package for the Pixel 3a, version 0.1.2: no kernel, no
hardware services. Installation stages files only; the clock's offset units
are enabled by vendor wants links, and the Bluetooth address unit is
started by udev. The
optional system setup command sets the locale and time zone and enables
timesyncd. Bring-up and results: [device/sargo](../../device/sargo/NOTES.md).

- **Storage.** The Pixel 3a keeps every partition on eMMC (`mmcblk0`). The
  udev rules continue the initramfs guard in Arch (they do not set anything
  read-only themselves): the whole-disk node, the hardware boot areas
  (`mmcblk0boot0/1`) and the RPMB node are made inaccessible, and desktop
  tools ignore every partition but `userdata`.
- **USB.** The gadget the initramfs creates survives the switch to Arch;
  `usb0` keeps 172.16.42.1 with a fallback route below Wi-Fi's priority.
- **Clock.** Linux can't set the PM660's RTC, which counts from 1970.
  `omamobile-rtc-offset` keeps the clock's offset from it in
  `/var/lib/omamobile/rtc-offset`: its unit sets the clock early in the boot
  (forward only, never before the last save), and the offset is saved at
  shutdown, every 15 minutes and after each network time sync. A reboot
  that stops no unit (`reboot-to`) loses at most the last quarter hour's
  change to the clock.
- **Bluetooth.** The WCN3990 has no address of its own and comes up
  unconfigured, so BlueZ doesn't see it. `omamobile-bt-addr`, started by
  udev for the `hci_uart_qca` controller, gives it the phone's address from
  the bootloader (`/chosen/cdt/cdb2/bt_addr`, a unicast public address
  only), as Android does.
- **Power.** All four sleep modes are disabled until suspend is qualified on
  this phone; UPower powers off on critical battery (not yet qualified here).
- **Not included.** No boot-success marking: the Pixel 3a's slot flags are
  GPT attributes, and marking slot B needs a CONTRIBUTING.md §3.1 entry. An
  unmarked slot B gets three boot tries before the bootloader falls back to
  slot A.

The reboot helper and the USB policy are cheetah's (test/all checks they
match). Run test/all for a native build and staged-install checks.
