<!-- SPDX-License-Identifier: MIT -->
# omamobile-sensors

The Pixel 7 Pro's sensors (accelerometer, gyroscope, light, proximity, compass) belong
to the AoC, the audio and sensor DSP, and reach Linux through its sensor
framework (USF) on `/dev/acd-com.google.usf`. This package turns them into
iio-sensor-proxy's D-Bus API, and rotates Hyprland with the phone.

| File | What |
|---|---|
| `omamobile-sensor-proxy` (system service, enabled at boot after `omamobile-aoc.service`) | `net.hadess.SensorProxy` on the system bus: `HasAccelerometer`, `AccelerometerOrientation`, `AccelerometerTilt`, light (lux), proximity, compass; a sensor samples only while a client holds a claim. Loads the AoC's sensor registry once per AoC boot from `/usr/share/omamobile/sensors/registry` (Google's files from the phone's vendor partition, never shipped) and the factory calibration from `persist` (read-only, with debugfs) |
| `omamobile-autorotate` (user service, turned on from the rotation lock tile) | claims the accelerometer and sets the monitor's and the touchscreen's transform through `hyprctl` (normal 0, left-up 1, bottom-up 2, right-up 3); `~/.local/state/omamobile/rotation-lock` locks it; while the screen is locked it holds portrait (the PIN pad), remembers the orientation and applies it on unlock |
| `omamobile-gyro` | test client of the gyroscope stream: samples, `--stats` (rate, jitter, latency, drops), `--integrate` (angle turned per axis) |
| `omamobile-usf` | the USF client, for bring-up: sensor list, registry load, sampling |

It provides and conflicts with `iio-sensor-proxy`, whose daemon would take
the same bus name. `monitor-sensor` (from iio-sensor-proxy's source) works
against it.

## Gyroscope stream (`org.omamobile.SensorProxy.Gyro1`)

For the camera's video stabilisation: every gyroscope sample, at up to
480 Hz, with the time the sensor took it. D-Bus signals are too slow for
that, so a claim returns a socket and the samples come through it.

Object `/net/hadess/SensorProxy/Gyro` on `net.hadess.SensorProxy` (system
bus; any local user may call it, like the rest of the proxy):

| Member | |
|---|---|
| `ClaimGyroscope(u rate_hz) -> (h stream, u rate_hz)` | starts the gyroscope (if this is the first claim) and returns the client's end of a `SOCK_SEQPACKET` socket pair, and the rate the sensor will run at. `rate_hz` 0 means 200. The LSM6DSV runs at 15 Hz times a power of two (15 to 480), the first at or above the request: 100 gives 120, 200 gives 240, 400 gives 480. With several clients the sensor runs at the fastest claim and every client gets every sample. A second claim from the same bus name replaces its first stream |
| `ReleaseGyroscope()` | ends this bus name's claim; the proxy closes its end (the client reads end of stream) |
| `HasGyroscope` b, `MinRate` u, `MaxRate` u, `RecordSize` u (24), `TimestampClock` s (`monotonic`) | properties |

A claim also ends when the client closes its socket or leaves the bus, and
the gyroscope stops with the last claim: it draws no power while nobody
reads it.

Each packet holds one or more whole 24-byte records (at most 64, so a 4 KiB
read buffer always gets whole packets), little-endian:

| Offset | Type | Field |
|---|---|---|
| 0 | u64 | `timestamp_ns`: CLOCK_MONOTONIC, when the sensor took the sample |
| 8 | f32 ×3 | `x`, `y`, `z`: angular rate in rad/s |
| 20 | u32 | `seq`: this stream's record number; a gap means records were dropped |

**Axes** are Android's device frame: with the phone upright in its natural
portrait orientation, screen towards you, x points right, y up (towards the
top of the screen) and z out of the screen towards you. A positive rate
turns counter-clockwise looking down the axis from its positive end: turning
the phone counter-clockwise in the screen plane is +z, tilting its top
towards you is +x, and turning its right edge away from you (or, lying flat,
lifting its left edge) is +y. Checked on the phone on 2026-10-14
(`device/cheetah/AOC-PLAN.md` C6f). The values
are the AoC's calibrated output (with this phone's factory gyroscope
calibration from `persist`); at rest a few mrad/s of bias remain (about
-0.004 rad/s on z on the reference phone), so a long integration drifts.
The axes do not follow screen rotation.

**Timestamps.** The AoC stamps each sample with its own clock (24.576 MHz
ticks, in ns from the AoC's boot). The proxy maps that to CLOCK_MONOTONIC with
the kernel's own pairing of the two clocks
(`/sys/bus/platform/devices/*.aoc/aoc_clock_and_kernel_boottime`: AoC ticks
and CLOCK_BOOTTIME read together), minus CLOCK_BOOTTIME − CLOCK_MONOTONIC
(the time spent suspended), and re-reads the pairing every second while the
stream runs. CLOCK_MONOTONIC is the clock of V4L2 buffer timestamps, and so
of libcamera's `SensorTimestamp`: a frame's timestamp and a gyroscope
record's can be compared directly. (CLOCK_BOOTTIME differs from it only by
time spent suspended, which is constant while a recording runs.)

**Latency** on the phone (2026-10-14): 0.8-1.9 ms from the sample's
timestamp to the client's read, median 1.4 ms, one record per packet at
120, 240 and 480 Hz, no drops; the sensor's own clock runs about 1 % fast
(242.7 Hz at 240). Read the socket from a thread of its own: a client that
falls behind by more than the socket buffer loses records (`seq` skips)
rather than stalling the proxy.

```sh
omamobile-gyro --stats --duration 5          # rate, jitter, latency, drops
omamobile-gyro --integrate --duration 30     # degrees turned about x, y, z
```

A client in Rust with zbus (sketch):

```rust
use std::io::Read;
use std::os::fd::OwnedFd;
use std::os::unix::net::UnixStream; // SOCK_SEQPACKET reads like this too

#[zbus::proxy(
    interface = "org.omamobile.SensorProxy.Gyro1",
    default_service = "net.hadess.SensorProxy",
    default_path = "/net/hadess/SensorProxy/Gyro"
)]
trait Gyro {
    fn claim_gyroscope(&self, rate_hz: u32) -> zbus::Result<(zbus::zvariant::OwnedFd, u32)>;
    fn release_gyroscope(&self) -> zbus::Result<()>;
}

#[derive(Clone, Copy, Debug)]
struct GyroSample { t_ns: u64, rate: [f32; 3], seq: u32 }

fn gyro_thread(tx: std::sync::mpsc::Sender<GyroSample>) -> zbus::Result<()> {
    let conn = zbus::blocking::Connection::system()?;
    let gyro = GyroProxyBlocking::new(&conn)?;
    let (fd, hz) = gyro.claim_gyroscope(200)?;          // runs at 240 Hz
    eprintln!("gyroscope at {hz} Hz");
    // Keep `conn` alive: the claim also ends when the connection closes.
    let mut sock = UnixStream::from(OwnedFd::from(fd));
    let mut buf = [0u8; 4096];
    loop {
        let n = sock.read(&mut buf).map_err(|e| zbus::Error::InputOutput(e.into()))?;
        if n == 0 { break; }                             // released
        for r in buf[..n].chunks_exact(24) {
            let f = |o: usize| f32::from_le_bytes(r[o..o + 4].try_into().unwrap());
            let s = GyroSample {
                t_ns: u64::from_le_bytes(r[0..8].try_into().unwrap()),
                rate: [f(8), f(12), f(16)],
                seq: u32::from_le_bytes(r[20..24].try_into().unwrap()),
            };
            if tx.send(s).is_err() { return Ok(()); }   // drop the socket: claim ends
        }
    }
    Ok(())
}
```

To stabilise a frame, integrate the rates between frame times. On cheetah
the CSIS driver (`gs201-csis`) stamps a buffer with `ktime_get_ns()` when
its DMA frame end arrives, so `SensorTimestamp` is the end of the frame's
readout: the middle of the frame's exposure is about that minus half the
readout time minus half the exposure time, and each row is offset by the
rolling shutter's line time. How the camera sensor sits relative to these
axes is the camera's side (its rotation in the device tree).

Needs the AoC running (`omamobile-aoc.service` in omamobile-device-cheetah).
Bring-up: `device/cheetah/AOC-PLAN.md`, stage C6.
