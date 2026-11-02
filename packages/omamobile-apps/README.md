# omamobile-apps

A meta package: the apps a phone needs that desktop Omarchy doesn't ship.
`omamobile-shell` depends on it, so every Omarchy Mobile install gets them.

| App | Package | Status |
| --- | --- | --- |
| Maps and location | `gnome-maps`, `geoclue` | default: the GPS reaches GeoClue through `omamobile-gnss` |
| NFC tags | `neard` | default: tapping a tag with a web link opens it (`omamobile-nfc-open` in `omamobile-shell`) |
| Camera | `omacam` | default: "Camera", Omarchy Mobile's own camera app, on libcamera directly: all four cameras, one zoom control across the lenses, full-resolution photos ([CAMERA-APP-PLAN](../../docs/CAMERA-APP-PLAN.md), `packages/omacam`) |
| Cameras for other apps | `pipewire-libcamera` | default: browsers and video calls reach the cameras through the camera portal and PipeWire (CAMERA-PLAN CAM5.4) |
| Second camera app | `snapshot` | optional: GNOME Snapshot, for video until omacam records it. Its launcher is named "Snapshot" (a pacman hook writes an override in `/usr/local/share/applications`), so the app grid shows one "Camera" |
| Phone and Contacts | `omaphone` (pulls in `omatel-agent`) | default since 0.2.1: "Phone" (dialpad, call log, favorites, the in-call screen) and "Contacts" ([TELEPHONY-APPS-PLAN](../../docs/TELEPHONY-APPS-PLAN.md) T6, `packages/omaphone`). Without a modem it keeps contacts and the call log; a call is refused with "No modem is available" |
| Messages | `omamessages` (pulls in `omatel-agent`) | default since 0.2.1: SMS conversations (T7, `packages/omamessages`). Without a modem it keeps conversations and drafts; a sent message is marked "Not sent", with retry |
| The modem | `omamobile-mmd` (with `omamobile-modem-sit`) | optional, and only for the Pixel 7 Pro: calls, SMS and data come with the modem in a later release (MODEM-PLAN M4). When it ships it goes in the device's image (`ROOTFS_PACKAGES`), never in this package's `depends` |
| Other phone apps | `gnome-calls`, `chatty` | optional: clients of the same ModemManager API |

An app moves from `optdepends` to `depends` when the hardware behind it
works on the reference device, or when it is useful without that hardware
and shows clearly what is missing (Phone and Messages).
