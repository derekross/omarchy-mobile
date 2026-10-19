<!-- SPDX-License-Identifier: MIT -->
# omamobile-device-flame

Experimental Pixel 4 native-root policy. Install only into the opt-in flame
root described in [the native runbook](../../device/flame/native/README.md).
The package enables the storage guard, hides protected partitions from desktop
disk tools, keeps the journal off USB, and selects the tested software-rendering
fallback for SDDM and user services. PID 1 feeds the 30-second watchdog; USB
networkd/DHCP stays separate from NetworkManager, and first-boot 0.1.3 adds
USB-only recovery/DHCP firewall rules. It does not mark a boot slot successful.

Foot, xdg-terminal-exec and udiskie are explicit dependencies so hand-built
roots cannot omit the terminal or disk helpers used by upstream Omarchy.
The existing AI Agent shortcut and chooser remain upstream's; no separate
Codex desktop app or agent selection is installed by this package.

`omamobile-flame-configure-user` seeds the tested 2.5 display scale. Its optional
`--chrome` switch merges the tested Wayland/software-rendering/0.6 scale flags
for an already installed Chrome browser. Other flags are preserved and prior
files are backed up under the owner's private state directory. It never
accepts a browser license or starts the browser. Chrome is not a dependency.
Normal mobile user setup calls `--chrome-if-installed` once for flame roots.

Wi-Fi's unit is shipped **disabled**. Before enabling it, supply the owner's
matching firmware and current verified private manifests/NV shadows and pass
the native Wi-Fi gates. No firmware, calibration, host keys or credentials
are in this package. Keep `ftm5_fw.ftb` absent before the first touch test.
