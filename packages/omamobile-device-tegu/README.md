# Pixel 9a device package

Boot and touch userspace policy for `tegu`: guarded storage visibility, the
USB gadget network address, a bounded reboot watchdog, and delayed touch
startup. The package also provides `reboot-to` and the device descriptor.

Installing the package does not mark slot B successful or start Wi-Fi,
charging, audio, sensors, cameras, or other peripherals. When the tegu
touchscreen DT child is enabled, a timer starts ACPM and the S2MPG14 PMIC
after early boot and checks that touch input registered. The package keeps
these modules from loading before the USB rescue path is available.

The descriptor selects both tested tegu silicon revisions and packs the
qualified boot overlays with the stock partition sizes and AVB metadata.
The board DTB and required kernel drivers must come from a matching tegu
kernel build. A release also needs a root image containing this package.
