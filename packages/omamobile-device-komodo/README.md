<!-- SPDX-License-Identifier: MIT -->
# omamobile-device-komodo

Experimental first-light support for the Google Pixel 9 Pro XL (`komodo`,
Tensor G4 / `zumapro`). This package and descriptor are for development only;
Komodo is not a supported installer or release target.

The descriptor follows the existing Komodo first-light target. Its selected
overlays only enable the touchscreen and GPU nodes described by the matching
kernel board DTS. The GPU overlay is usable only with this package's guarded
GPU start service: it writes a persistent attempt marker before loading
Panthor, while a modprobe blacklist prevents an earlier modalias load, and
leaves the GPU disabled on the next boot if the probe does not complete.
Internal Wi-Fi is deliberately excluded from the selected overlays;
the observed vendor-driver probe failed and the proposed DMA pool is not
qualified.

The package installs the device descriptor, USB networking configuration,
and the guarded GPU/root-ready services used by the one-device bring-up. It
contains no firmware, raw captures, phone identifiers, or per-device data.
`device/komodo/NOTES.md` and `device/komodo/BRINGUP-M1.md` record hardware
evidence and remaining work. The descriptor's NV partitions are for read-only
backup/check tooling; they are never placed on Linux's write allow-list.

Build and run the offline package checks with:

```sh
./test/all
```

The test does not access a phone or load a driver.
