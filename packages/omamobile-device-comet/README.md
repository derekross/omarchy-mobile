<!-- SPDX-License-Identifier: MIT -->
# omamobile-device-comet 0.1.0

Staged boot policy for the Pixel 9 Pro Fold (comet, Tensor G4 / zumapro).
This is not a supported install profile. The descriptor needs the separate
public Comet board DTS (linux-omarchy-mobile#273) before it can build from
upstream. That DTS enables USB on the Pixel 9a's plain `snps,dwc3` node,
which the shared kernel config builds in, so comet has no per-device build
fragment. Everything else the DTS leaves disabled needs its own attended
qualification.

The package installs the descriptor, reboot-to, USB networking at metric
2000, storage-hiding udev rules, power-key/lid logind policy, shutdown watchdog
configuration, an AoC module blacklist and the repository mirrorlist hook.
The initramfs storage guard, not the udev rule, enforces read-only storage.
Shared network, mirrorlist, hook and reboot-to files follow current main.
The package ships nothing the shell reads and does not depend on
`omamobile-shell`. The descriptor sets no MONITOR_SCALE: with #635 (open)
the shell works the scale out from the panel's size. The AoC blacklist names
the modules the comet zumapro kernel builds.

## Boot-success disabled

BOOT_SUCCESS=disabled in status, and install creates no service wants links.
No boot-success script, unit or devinfo writer is shipped. This keeps the
maintainer's [issue #143](https://github.com/derekross/omarchy-mobile/issues/143)
hold in force. Existing owner-installed scripts or service links are outside
this package: the owner must keep the reported mask in place. Installing or
upgrading this candidate does not remove administrator-created files.

Daily hardware startup, display/touch rules, AoC firmware loading, modem,
charging, trial-kernel writes and automatic slot marking remain separate
work. No binary firmware, calibration or boot image is included.

Run ./build [DIR], ./install DESTDIR [DIR], and test/all offline.
The tests compile reboot-to without executing it, stage the package, check
the allowlist and assert that neither service enablement nor a devinfo writer
is present. They do not establish phone behavior. Historical private-kernel
observations and recovery limitations are recorded in device/comet/NOTES.md.
