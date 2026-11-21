<!-- SPDX-License-Identifier: MIT -->
# omamobile-device-dipper

This package configures the Mi 8's USB network, keeps Android partitions out
of desktop storage tools, disables the unstable CPU0 rail-collapse idle state,
transfers the hardware watchdog to systemd, and provides a `reboot-to` helper.

The runtime and reboot watchdog timeouts are 30 seconds, below the Dipper
`qcom_wdt` driver's 31-second limit.

It declares Mesa for the Freedreno graphics stack and the Qualcomm
QRTR userspace packages needed by the WLAN and modem stacks. Their services
are not enabled here.

The Dipper drivers request `a630_zap.mbn`, `ipa_fws.mbn`, `adsp.mbn`,
`mba.mbn` and `modem.mbn` under `qcom/sdm845/Xiaomi/dipper/`, `cdsp.mdt`
at the firmware root, and `venus.mbn` under `qcom/venus-5.2/`. The WCN3990
Bluetooth driver also needs `qca/Xiaomi/dipper/crnv21.bin` and
`qca/crbtfw21.tlv`. Obtain these files from the owner's own phone or firmware
image; none is included here.
Run `tools/extract-vendor-firmware -d dipper /path/to/local-backup` on a
local directory containing copied `vendor/`, `modem/` and `bluetooth/`
partition contents. It preserves the modem `.bNN` segments required by the
Qualcomm loader. `linux-firmware-qcom` supplies
generic Qualcomm firmware such as `a630_sqe.fw`; it does not supply these
Dipper-specific files. The
`[omamobile]` repository mirrorlist is installed for future package updates.
QRTR, `pd-mapper` and `tqftpserv` are dependencies, but their services are
not enabled here. `rmtfs` is not installed until its modem storage role has
a gated device plan.

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
