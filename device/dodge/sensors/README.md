<!-- SPDX-License-Identifier: MIT -->
# dodge sensors (ADSP SSC via libssc)

The sensors sit behind the ADSP's Snapdragon Sensor Core (QMI service 400 on
QRTR node 5). They work once `hexagonrpcd -s` attaches to the sensors PD and
serves the phone's own registry, JSON config and DSP libs.

| Sensor | Status (2026-10-21) |
|---|---|
| accelerometer (bmi26x) | works: `ssccli`, iio-sensor-proxy |
| proximity (tcs3720) | works: NEAR/FAR |
| compass | works through iio-sensor-proxy |
| ambient light | not found (`ambient_light` discovery fails; OPlus ALS) |

Pieces:

- `prepare-root`: builds `/var/lib/omamobile/sensors/root` read-only from
  `persist` (registry, mounted `ro,noload`), `dsp_a` (ADSP libs) and the
  vendor/odm erofs in `super` (copied with dd, extracted with `fsck.erofs`). Also
  writes stub socinfo (no qcom-socinfo in this kernel). Phone-only data: never
  commit it.
- `hexagonrpc-da7a374-omamobile.patch`, against
  github.com/linux-msm/hexagonrpc:
  - maps `/odm/etc/sensor/config`;
  - keeps the listener running after an unsupported method. Without this,
    hexagonrpcd quit 257 ms in, on apps_std method 36.
- `libssc-4e4c6c8-no-gir.patch`: skips GObject introspection (no g-ir-scanner).
- `omamobile-sensors.service`: hexagonrpcd on `/dev/fastrpc-adsp-secure`, gated
  on `/etc/omamobile/sensors.enable`. The sensors PD attaches only once per ADSP
  boot, so the service has to be up at boot.
- `81-omamobile-ssc.rules` + `iio-sensor-proxy-omamobile.conf`: tag the fastrpc
  node `ssc-accel ssc-proximity`, set `ACCEL_MOUNT_MATRIX` with X and Y inverted
  (the raw data read 180° off), and order iio-sensor-proxy after hexagonrpcd.
  iio-sensor-proxy is built from git with `-Dssc-support=enabled`.
- `omamobile-autorotate`: raw accel via `ssccli` (libssc; no IIO sysfs on
  dodge) → `hyprctl eval` monitor and touch transform. Applies the udev
  `ACCEL_MOUNT_MATRIX` (-X,-Y). Hysteresis is relative to the current
  orientation (`OMAMOBILE_ROTATE_ANGLE_DEG`, default 75, same both ways), with
  debounce (`OMAMOBILE_ROTATE_DEBOUNCE_MS`, default 600), near-flat ignore
  (`OMAMOBILE_ROTATE_FLAT_DEG`, default 30), and ~8 Hz decide rate
  (`OMAMOBILE_ROTATE_HZ`); accel stream pauses while the backlight is off.
  `install` appends `hl.exec_cmd("omamobile-autorotate")` to the session user's
  `~/.config/hypr/autostart.lua`. Gated on `/etc/omamobile/sensors.enable`,
  one instance (flock), log `$XDG_RUNTIME_DIR/omamobile-autorotate.log`.
  `omamobile-autorotate --self-test` covers 60/75/80 deg, wobble, flat.
  Martin checked orientations 2026-10-21; angle threshold 2026-10-28.

Persist is never written. hexagonfs opens everything `O_RDONLY` and
refuses writes ("Tried to open … for writing"), and it serves a copy anyway.
