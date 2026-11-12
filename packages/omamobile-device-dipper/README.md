# omamobile-device-dipper

This package configures the Mi 8's USB network, keeps Android partitions out
of desktop storage tools, transfers the hardware watchdog to systemd, and
provides firmware path aliases and a `reboot-to` helper.

The watchdog timeout is 60 seconds, the value that reached multi-user in the
recorded RAM/NFS boot ([device notes](../../device/dipper/NOTES.md)).

It declares Mesa for the tested Freedreno graphics stack and the Qualcomm
QRTR userspace packages needed by the WLAN and modem stacks. Their services
are not enabled here.

Firmware blobs remain in `linux-firmware-qcom`; the package creates relative
symlinks under the path used by the device tree. It does not copy phone data or
firmware into this repository. The `[omamobile]` repository mirrorlist is
installed for future package updates. QRTR, `pd-mapper`, `tqftpserv` and
`rmtfs` are dependencies, but their services are not enabled here; no service
in this package writes the modem's partitions.

The package installs the same device descriptor used by the build tools.

Dipper support remains RAM-boot only. The single `boot` partition and UFS
storage are not written by this package.

## Build and test

```sh
tools/build-packages --local dipper packages/omamobile-device-dipper
packages/omamobile-device-dipper/test/all
```
