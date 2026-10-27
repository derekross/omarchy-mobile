<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a device package

Boot and touch userspace policy for `tegu`: guarded storage visibility, the
USB gadget network address, a bounded reboot watchdog, and delayed touch
startup. The package also provides `reboot-to` and the device descriptor.

Installing the package does not mark slot B successful or start Wi-Fi,
charging, audio, sensors, cameras, or other peripherals. When the tegu
touchscreen DT child is enabled, a timer starts ACPM and the S2MPG14 PMIC
after early boot and checks that touch input registered. Before loading the
mailbox, ACPM and PMIC drivers, it writes and syncs a persistent marker at
`/var/lib/omamobile/tegu-touch-started`. A failed or hung start leaves that
marker behind, so subsequent boots skip the attempt. After inspecting the
previous boot's journal, explicitly retry with
`sudo /usr/lib/omamobile/tegu-touch-start --retry`. Success removes the marker.
The delay allows userspace to start; this package does not provide USB rescue.

The packaged descriptor matches main's staged descriptor: Android 16 and
September 2025 header values, no AVB footer override or display register write,
and no active DTB selector. Image building remains gated pending qualification
against the public board DTS in kernel PRs
[#80](https://github.com/derekross/linux-omarchy-mobile/pull/80) and
[#81](https://github.com/derekross/linux-omarchy-mobile/pull/81).
Those trees differ from the private prototype that produced the recorded
hardware results. In particular, the public board also uses ACPM for USB PHY
supplies: its boot ordering must be qualified with this package's module
policy. This is not yet an installable release.
