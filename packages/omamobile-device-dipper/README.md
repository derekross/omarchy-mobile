<!-- SPDX-License-Identifier: MIT -->
# omamobile-device-dipper

This package configures the Mi 8's USB network, keeps Android partitions out
of desktop storage tools, transfers the hardware watchdog to systemd, and
provides a `reboot-to` helper.

The watchdog timeout is 60 seconds, the value that reached multi-user in the
recorded RAM/NFS boot ([device notes](../../device/dipper/NOTES.md)).

It declares Mesa for the tested Freedreno graphics stack and the Qualcomm
QRTR userspace packages needed by the WLAN and modem stacks. Their services
are not enabled here.

The published Dipper device tree requests `adsp.mbn`, `a630_zap.mbn`,
`ipa_fws.mbn`, `mba.mbn` and `modem.mbn` under
`qcom/sdm845/Xiaomi/dipper/`, plus Bluetooth calibration
`Xiaomi/dipper/crnv21.bin`. These device-specific blobs must be extracted
from the owner's phone or image; they are not included here. The
`linux-firmware-qcom` dependency supplies generic Qualcomm firmware such as
`a630_sqe.fw`, but does not supply those Dipper-specific names. The
`[omamobile]` repository mirrorlist is installed for future package updates.
QRTR, `pd-mapper`, `tqftpserv` and
`rmtfs` are dependencies, but their services are not enabled here; no service
in this package writes the modem's partitions.

The package installs the same device descriptor used by the build tools.

Dipper support remains RAM-boot only. The single `boot` partition and UFS
storage are not written by this package.

Suspend is untested and must stay disabled while booting an NFS root, since the
USB link carries the root filesystem.

The USB route uses metric 1000 for Dipper's NFS-root session, where USB carries
the root filesystem. The Pixel profiles use 2000 so Wi-Fi (metric 600) and
cellular (metric 700) stay preferred over USB.

## Build and test

```sh
tools/build-packages --local dipper packages/omamobile-device-dipper
packages/omamobile-device-dipper/test/all
```
