<!-- SPDX-License-Identifier: MIT -->
# hexagonrpcd (Omamobile build)

hexagonrpcd 0.4.0, the FastRPC file server for Qualcomm Hexagon DSPs.
Arch Linux ARM doesn't package it. On sm8250 phones the sensor DSP (SLPI)
reads its sensor configuration, registry and SoC information through it;
without it libssc, and so iio-sensor-proxy's SSC drivers, find no sensors.

| Piece | Use |
| --- | --- |
| `hexagonrpcd-sdsp.service` | serves `/dev/fastrpc-sdsp` (the SLPI's sensors PD); conditional on the node |
| `hexagonrpcd-adsp-*.service` | the same for phones whose sensors are on the ADSP |
| `fastrpc` user | runs the daemon; the udev rule gives it the `/dev/fastrpc-*` nodes |

The daemon serves `/usr/share/qcom/{soc}/{vendor}/{codename}`, guessed from
the device tree (`-R` overrides it). A device package fills it from the
phone's own partitions:

| Path | What |
| --- | --- |
| `sensors/config/` | the sensor JSON configs |
| `sensors/sns_reg.conf` | the registry configuration (Android's `sns_reg_config`) |
| `sensors/registry/` | the parsed registry from the phone's `persist` |
| `sensors/sns_reg_version` | the registry's version, beside it on `persist` (patch 0002) |
| `socinfo/` | `hw_platform`, `platform_subtype`, ... (mainline has no `/sys/devices/soc0/hw_platform`) |
| `dsp/sdsp/` | the DSP's shared objects |

The file service is read-only: the DSP's writes (a rebuilt registry) are
refused. Patch 0002 is what keeps the DSP from needing them. See the
PKGBUILD's header for both patches.

Build and install it on the phone:

```sh
tools/phone-install-package packages/hexagonrpcd
```
