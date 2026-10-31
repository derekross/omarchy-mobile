<!-- SPDX-License-Identifier: MIT -->
# Pixel 6 first-light policy

Initial standalone package, version 0.1.0. No kernel, rootfs integration or
hardware qualification is supplied. Installation stages files only and enables
no services. The optional system setup command configures locale/time and
enables timesyncd.

Portable helpers, build script, USB network policy and storage udev policy
come from the cheetah package. The storage rules continue an existing
initramfs guard: they do not set partitions read-only themselves. A guarded
initramfs and matching kernel remain prerequisites. USB gadget creation and
networkd activation are also external prerequisites. USB has fallback metric
2000, below ordinary Wi-Fi preference.

All four sleep modes are disabled. UPower selects PowerOff on critical
battery. Coldplug blocks alias and explicit modprobe for clk_acpm,
max77759_charger, gpio_max77759, arm_dsu_pmu, at24 and max17042_battery.
These six names follow the recovered Oriole ROOTFS-PLAN coldplug audit;
this package makes no claim that the underlying hardware is qualified.
Built-in drivers are outside modprobe policy.

No battery startup, staged boot checker, automatic boot-success, radio,
charging or GS201 hardware services are included. Boot-control writes require
an explicit flag and separate human authorization. No phone testing was
performed for this package; exact-branch boot remains unqualified.

Run test/all for a native helper build, synthetic boot-control dry run and
staged installation checks. Do not install on a phone without a separate
device-specific, watchdog-protected qualification gate and rollback.
