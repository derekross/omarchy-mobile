<!-- SPDX-License-Identifier: MIT -->
# OnePlus 7T device package

Development profiles for an existing, provisioned OnePlus 7T root.
See the [bring-up notes](../../device/hotdogb/NOTES.md) for the
kernel, known working configuration and gaps.

- The lens table is installed under `/usr/share/omacam`. Its identifiers
  match the development DT paths and its telephoto ISO assumes libcamera's
  S5K3M5 gain conversion for the corresponding kernel. Check `cam -l`
  against the table when changing the kernel or camera modules.
- Auto-brightness can be started by the owner with
  `systemctl start omamobile-hotdogb-autobrightness` once the backlight and
  already-provisioned SensorProxy report lux. It corrects for the OLED
  light reaching the sensor and remembers the owner's manual adjustment.
  Stop the service to return to manual brightness. The package leaves it
  off by default.
- The ALSA UCM tree under `/usr/share/omamobile/hotdogb/ucm2` is staged
  separately for attended testing. The HiFi speaker route uses stereo
  S16_LE and a fixed -24 dBFS attenuation. The amplifier driver has no
  speaker protection. Direct hardware PCM or a fallback profile can
  bypass the attenuation. Before making the UCM profile active,
  establish that the session cannot select an uncapped fallback route
  and start testing at low volume. Do not enable audio modules through
  this package.

The package stages files only. Firmware and calibration must be
provisioned by the owner following [CONTRIBUTING §7](../../CONTRIBUTING.md#7-licensing-and-vendor-firmware).
