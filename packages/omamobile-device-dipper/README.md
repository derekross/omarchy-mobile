# omamobile-device-dipper

This package supplies the Mi 8's Dipper-specific firmware path aliases and
declares the runtime packages needed for the tested Freedreno graphics stack
and Qualcomm QRTR userspace. It also installs a small `reboot-to` helper so a
running system can request a reboot to fastboot.

Firmware blobs remain in `linux-firmware-qcom`; the package creates relative
symlinks under the path used by the device tree. It does not copy phone data or
firmware into this repository. QRTR, `pd-mapper`, `tqftpserv` and `rmtfs` are
dependencies, but their services are not enabled here. In particular, no
service in this package writes the modem's partitions.

Dipper support remains RAM-boot only. The single `boot` partition and UFS
storage are not written by this package.

## Build and test

```sh
tools/build-packages --local dipper packages/omamobile-device-dipper
packages/omamobile-device-dipper/test/all
```
