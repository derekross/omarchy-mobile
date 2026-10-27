<!-- SPDX-License-Identifier: MIT -->
# Pixel 9a device package

Boot and touch userspace policy for `tegu`: guarded storage visibility, the
USB gadget network address, a bounded reboot watchdog, and delayed touch
startup. The package also provides `reboot-to` and the device descriptor.
It skips Arch's old-kernel module cleanup while installed: modules shipped
as tarballs are not pacman-owned, and must survive until their B-slot kernel
boots, as well as remain available for rollback.

Installing the package does not mark slot B successful or start Wi-Fi,
charging, audio, sensors, cameras, or other peripherals. When the tegu
touchscreen DT child is enabled, a timer loads the touchscreen after early
boot and checks that touch input registered. Before loading any drivers,
it writes and syncs a persistent marker at
`/var/lib/omamobile/tegu-touch-started`. A failed or hung start leaves that
marker behind, so subsequent boots skip the attempt. After inspecting the
previous boot's journal, explicitly retry with
`sudo /usr/lib/omamobile/tegu-touch-start --retry`. Success removes the marker.
The tegu kernel fragment builds touch as a module, and the package blocks
its automatic loading so the marker gates it. The public board needs ACPM
and its PMIC built in for early USB power; on older modular kernels the
service loads those dependencies first. The marker cannot gate built-in
drivers. The delay allows userspace to start; this package provides no USB rescue.

The packaged descriptor matches main's staged descriptor: Android 16 and
September 2025 header values, no AVB footer override or display register write,
and no active DTB selector. Image building remains gated pending qualification
against the public board DTS in kernel PRs
[#80](https://github.com/derekross/linux-omarchy-mobile/pull/80) and
[#81](https://github.com/derekross/linux-omarchy-mobile/pull/81).
Those trees differ from the private prototype that produced the recorded
hardware results. In particular, the public board also uses ACPM for USB PHY
supplies: its boot ordering must be qualified with this package's module
policy. Boot, native DRM at 60 Hz, touch and module retention have passed
on the second contributor's phone; see `device/tegu/NOTES.md` for the exact
source and image metadata. Cross-owner footer qualification and clean
installation remain pending. This is not yet an installable release.

## Building the public kernel candidate

`device/tegu/kernel.sources` pins the public board, touch and native TG4C
display changes and the resulting source-tree hash. From the repository root,
prepare a new worktree without changing an existing kernel branch:

```sh
device/tegu/prepare-kernel "$HOME/android/mainline/linux" "$HOME/android/mainline/wt-tegu"
KERNEL_DIR="$HOME/android/mainline/wt-tegu" \
KERNEL_OUT="$HOME/android/mainline/out-tegu" DEVICE=tegu bin/omamobile kernel
```

Use the toolchain and AOSP prerequisites in `CONTRIBUTING.md`. If
`omamobile.local.conf` sets `KERNEL_DIR` or `KERNEL_OUT`, update those values
too: that file takes precedence over the environment. The preparation step
fetches only public source commits and checks the resulting tree; it does
not build images or touch the phone. The pinned candidate excludes GPU and
CPU-frequency changes, which need separate qualification. Its intended
display path is native DRM, without a shared framebuffer register write.
The native path has passed on one phone. Shared descriptor activation
awaits the other owner's footer qualification; no newer rollback metadata
is introduced here.
