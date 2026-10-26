# Pixel 9a device package

First-light userspace policy for `tegu`: guarded storage visibility, the
USB gadget network address, and a bounded reboot watchdog. The package
also provides the generic `reboot-to` command and the device descriptor.

Installing the package does not mark slot B successful or start Wi-Fi,
charging, audio, sensors, cameras, or other peripherals. A reviewed board
DTB, qualified image selector and AVB values, and USB/UFS boot evidence are
still required before a device load.
