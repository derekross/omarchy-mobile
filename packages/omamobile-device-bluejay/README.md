<!-- SPDX-License-Identifier: MIT -->
# Bluejay development integration

The Pixel 6a now boots a persistent Arch Linux ARM root with USB SSH and an
Omarchy lock screen. A fresh reboot demonstrated automatic touch initialization,
retained display refresh and Hyprland/Quickshell startup. The owner confirmed
unlocking and opening an app after that reboot. Panfrost now renders the desktop at the initial 151 MHz GPU point, using the
opt-in Aquamarine patch under `device/bluejay/patches` for retained simpledrm.
The owner also confirmed app launch and scrolling in the accelerated session.

It supplies the rescue USB address, passive storage check, runtime watchdog and
SSH-ready completion. SDDM requires the tested hardware startup service and its
runtime ready marker. A durable failed-start marker holds hardware on the next
boot while USB SSH remains available. Drivers stay blacklisted so only that
service initializes the tested input path. The development root must also stage
the project's static `/usr/local/bin/devmem` helper and the patched Aquamarine
library under `/usr/local/lib/bluejay`; this package alone is not a release image.

It ships no bootctl writer, USB-switch I2C helper or board firmware. Automatic
boot updates and automatic boot-success marking remain disabled. The installed
development system's B success flag was set once with the existing project helper
after persistent root and automatic desktop startup passed. Native panel
modesetting, full GPU/CPU DVFS and suspend remain unqualified. GPU startup
requires explicit `bluejay-gpu-enable`; a held startup falls back to software.

The installed system also enables the Wi-Fi startup service with privately staged
qualified firmware. It reconnects through NetworkManager after reboot and passes
wireless-bound HTTPS. Wi-Fi Direct is hidden using the pinned kernel feature mask;
the package does not redistribute firmware or network credentials. The development
phone omits OBS Studio, Kdenlive, GPU Screen Recorder, ddcutil and bolt; mobile,
browser, document and development tools are retained.

The root installer must honor `BOOT_UPDATE_AUTO_WRITE=no`. Before installing,
audit the packed initramfs and root, including the storage guard across udev,
the held USI path, exact module provenance, radio policy and boot-success mask.
Use the project installer after its dry run. This development phone's Android
and userdata are expendable; existing backups are retained without repeated
preservation checks. See `device/bluejay/PERSISTENCE-PLAN.md`.

This package is a pinned development overlay, not a general release image.
Its exact kernel/module checks intentionally reject an unrelated build. See
`device/bluejay/UPSTREAM.md` for the source dependency and packaging gaps.
