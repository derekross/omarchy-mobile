# Pixel 9a device package

First-light userspace policy for `tegu`: guarded storage visibility, the
USB gadget network address, and a bounded reboot watchdog. The package
also provides the generic `reboot-to` command and the device descriptor.

Installing the package does not mark slot B successful or start Wi-Fi,
charging, audio, sensors, cameras, or other peripherals. The public kernel
board source and image selector are still required before a device load.
The supervised bring-up gates are in
[`device/tegu/BRINGUP-M1.md`](../../device/tegu/BRINGUP-M1.md).
