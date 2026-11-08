<!-- SPDX-License-Identifier: MIT -->
# omamobile-device-comet 0.1.60

Staged boot policy for the Pixel 9 Pro Fold (comet, Tensor G4 / zumapro).
This is not a supported install profile. The descriptor needs the separate
public Comet board DTS and USB glue before it can build from upstream.
The per-device build fragment selects that glue as a module; it does not
enable USB in the board DTS. Release builds exclude per-device fragments,
and this candidate is not a release-build profile. The separately prepared
board subset leaves USB disabled and needs its own attended qualification.

The package installs the descriptor, reboot-to, USB networking at metric
2000, storage-hiding udev rules, power-key/lid logind policy, shutdown watchdog
configuration, an AoC module blacklist and the repository mirrorlist hook.
The initramfs storage guard, not the udev rule, enforces read-only storage.
Shared network, mirrorlist, hook and reboot-to files follow current main.
It depends on the shell descriptor-scale support prepared with #204;
MONITOR_SCALE=2 seeds new users while preserving existing settings.

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
