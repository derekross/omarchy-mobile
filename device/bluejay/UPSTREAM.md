<!-- SPDX-License-Identifier: MIT -->
# Pixel 6a development source and reproduction status

This publishes the working bring-up source and its measured limits. It is a
**development milestone**, not a release image or an unattended installation
recipe. No firmware, credentials, partition images, device addresses, vendor
binaries or private captures are included.

## Source dependencies

The tested kernel starts at upstream `omamobile` commit `29a7a9326bf0` and adds
NCM flush retries, Bluejay retained-memory exclusions, GS101 PCIe/PHY support,
restricted BCM4389 DMA/provisioned-MAC handling, ALIX input and a targeted USI
hold. The complete tested source is preserved on the contributor branch
[`bringup/bluejay-tested-20261108`](https://github.com/latentoperator/linux-omarchy-mobile/tree/bringup/bluejay-tested-20261108)
(commit `c934e316b`). This is development source, not a published kernel release.
The review branch additionally fixes the PCI compatible binding; that DT-only
review correction has not been flashed to the test phone.

The phone ran `7.3.0-rc6-omamobile-bluejay-input-gated0`. The new
`device/bluejay/kernel.config` records its configuration differences from the
shared fragment. `bin/omamobile kernel` consumes the per-device fragment;
`--release` deliberately does not. Use an isolated `KERNEL_DIR`/`KERNEL_OUT` and
the project's pinned Android clang. Build all matching modules, not just the
hardware modules: the desktop requires netfilter and FUSE too.

## Boot configuration

The source DT leaves experimental devices disabled. For the tested enabled
shape, compile/apply these bring-up overlays in order:

```
wifi-pool wifi-controller wifi-endpoint wifi-intx
input-controller input-alix gpu-g1
```

`input-controller` includes the mandatory early USI11 hold in `/chosen/bootargs`.
`wifi-intx` corrects the parent specifiers to 1 through 4. `gpu-g1` uses a single
151 MHz shader OPP; the existing ACPM provider requests its 302 MHz L2 pair.
All source overlay changes must be inspected on both A0 and B0 DT variants
before a new phone boot. Keep the startup modules blacklisted.

The project image builder can use a local descriptor with `DTB_OVERLAYS` set to
the list above. The default descriptor deliberately does not enable them.
`tools/bluejay-development-images.py BASE OUTPUT` replaces the init and creates
or updates its explicit development selector in already built Bluejay images;
`--dt-overlay FILE` applies a compiled overlay to both silicon variants. Its
`--mode ram-rescue` selects a separate RAM-only image rather than entering an
installed userdata root. Retain that rescue set before installing a root.
The tool builds images offline; flashing still goes through `bin/omamobile`.

## Root and graphics dependencies

`omamobile-device-bluejay` 0.1.3 supplies passive checks, USB address policy,
watchdog settings, blacklists, guarded hardware/Wi-Fi/GPU services and the UWSM
renderer environment. Only the passive checks/SSH-ready units are enabled by
the package installer. The tested development root explicitly enabled hardware
and Wi-Fi startup, enabled GPU through `/etc/omamobile/bluejay-gpu-enable`, and
staged matching modules and firmware before allowing SDDM.
The submission also adds explicit `bluejay-hardware-enable` and
`bluejay-wifi-enable` conditions under `/etc/omamobile`: installing the package
alone must not start hardware on an unqualified phone. These extra conditions
were verified offline; the underlying scripts ran on the test handset.

The startup scripts intentionally pin the tested kernel release and selected
module hashes. A different build must be qualified and its provenance checks
updated before use; changing a hash alone is not hardware qualification. Moving
this policy into a versioned release kernel/device package remains future work.
The installed package database still says 0.1.1: subsequent development files
were staged directly, so the PR's package version is not a claim that a new
release package has already been installed on the phone.

Extract the three Wi-Fi files from the owner's own matching factory/OTA image,
as described in [WIFI-PLAN](WIFI-PLAN.md). Firmware and the NetworkManager profile
are not supplied. USB remains unmanaged by NetworkManager.

Build Aquamarine 0.16.0 with
`patches/aquamarine-simpledrm-no-aux-renderer.patch`. The tested native build
installed `libaquamarine.so.0.16.0` under `/usr/local/lib/bluejay`; the UWSM file
opts in to it. This library is not bundled. Mesa `1:26.2.4-1.4` already contains
the project's Mali-G78 model entry. The shell uses RHI with the qualified GPU,
and explicitly falls back to llvmpipe/software rendering if its ready marker
is absent.

## Validation and limitations

The installer dry run and actual installation, online root growth, repeated
normal reboots, station reconnect/TLS traffic and actual owner unlock/app/scroll
checks passed. The GLES probe checks every pixel for clear, solid and blended
shader draws at 64x64, 257x257 and 1024x1024. GPU and touch startup remained
fault-free at the final audit. See the PR smoke report and subsystem plans.

The initial full smoke report exposed missing FUSE in the partial development
module tree; adding the matching module repaired the document portal. The
inherited early `test_double_dereference` trace-format warning and the expected
USI `-ECANCELED` hold remain disclosed. Do not classify the latter as a new
hardware probe failure.

Native panel/DSI modesetting, Power-key release, full GPU/CPU DVFS, Vulkan,
Wi-Fi P2P/hotspot/roaming/suspend, audio, modem, Bluetooth, battery/charging,
sensors, cameras and suspend are unqualified. A self-contained release root
and installer, public firmware-extraction automation, package-built Aquamarine
and a fresh install from the final rebased release stack remain follow-up work.
