# omamobile-apps

A meta package: the apps a phone needs that desktop Omarchy doesn't ship.
`omamobile-shell` depends on it, so every Omarchy Mobile install gets them.

| App | Package | Status |
| --- | --- | --- |
| Maps and location | `gnome-maps`, `geoclue` | default: the GPS reaches GeoClue through `omamobile-gnss` |
| NFC tags | `neard` | default: tapping a tag with a web link opens it (`omamobile-nfc-open` in `omamobile-shell`) |
| Camera | `omacam` | default: "Camera", Omarchy Mobile's own camera app, on libcamera directly: all four cameras, one zoom control across the lenses, full-resolution photos ([CAMERA-APP-PLAN](../../docs/CAMERA-APP-PLAN.md), `packages/omacam`) |
| Images | `loupe` | default: "Image Viewer", GNOME Loupe, opens images (`/etc/xdg/mimeapps.list`, read before Omarchy's list, with imv as the fallback): it fits each image to the screen and takes touch, pinch and double-tap to zoom and a swipe to the next image in the folder. Omarchy's imv reads no touchscreen input; it stays installed, and `omamobile-setup-user` hides its duplicate "Image Viewer" entry once, while Loupe is installed |
| Cameras for other apps | `pipewire-libcamera` | default: browsers and video calls reach the cameras through the camera portal and PipeWire (CAMERA-PLAN CAM5.4) |
| Second camera app | `snapshot` | optional: GNOME Snapshot, for video until omacam records it. Its launcher is named "Snapshot" (a pacman hook writes an override in `/usr/local/share/applications`), so the app grid shows one "Camera" |
| Phone calls | `gnome-calls` | optional until the modem works (MODEM-PLAN M4) and Calls can talk to its RIL |
| Messages | `chatty` | optional, as Calls |

An app moves from `optdepends` to `depends` when the hardware behind it
works on the reference device.
