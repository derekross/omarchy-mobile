<!-- SPDX-License-Identifier: MIT -->
# omamobile-device-alioth

Initial experimental POCO F3 support for the pinned 6.15.1 reference kernel:
USB networking, key-authenticated access through firstboot, native nftables
firewall, display scale, watchdog and disabled suspend. No Pixel hardware,
slot-success or calibration writers are installed. The sensor proxy stays
masked until cold-start initialization is repeatable.

`omamobile-setup-system` configures locale/time and the limited pacman
Landlock workaround. A future Landlock-capable kernel can remove the
helper's own setting by rerunning it. DownloadUser and syscall filtering
are retained. No service is started by the package build/install scripts.

Build with `tools/build-packages packages/omamobile-device-alioth` and run
`test/all` for local staging, syntax, udev and kernel-compatibility checks.
See [the flashing runbook](../../device/alioth/FLASH-RUNBOOK.md) for the full
image and backup workflow. This package alone is not a flashable image.
