<!-- SPDX-License-Identifier: MIT -->
# AoC plan (cheetah / gs201): audio and sensor DSP bring-up

Status (2026-10-13): **the AoC starts at every boot and serves audio and
sensors.** On the phone: C1-C4a, C4t (the start through Trusty), C5 (core,
IPC and character devices), C6 (sensors at every boot, auto-rotate), C7 (the
AoC sound card: both speakers with stock's channel map, the microphones), C8
(speaker protection, UCM, PipeWire) and C8f (the amplifiers across idle)
passed; C9a-C9d-6 ran. The everyday level is stage `media` (737/10 on both
amplifiers, media delta, DRE and noise gate on, **the boost converter off
since C9j**), about 17 dB below stock; stock's 817/17 still trips the coil
temperature at once (C9d-3..6). **C9j (2026-10-27, omamobile-audio
0.5.3):** the watchdog had been muting media at 737/10 on the bottom
amplifier's open-loop coil estimate, which jumps on any level drop; the
5 C jump rule now applies above the stage's analog ceiling of 10 only. The
"static" under music was the amplifiers' boost converter in its light-load
regime; with it off (the cs35l41 `boost_en` bring-up parameter, "ASoC:
cs35l41: bring-up option to run without the boost converter") both
speakers are 8-11 dB louder and clean. The routing was verified again on
the way: the earpiece is the top speaker, and it plays the full left
channel as on stock. omamobile-audio 0.5.4 then made the speaker filter flat
with 6 dB of limiter drive, the owner's choice by ear, and the owner now finds
the speakers good (2026-10-27).
**Earlier plan (2026-10-13, before C9j):** the speakers sounded thin; the ranked plan and three
runbooks follow C9d-6: C9g (omamobile-audio 0.4.0's speaker filter, by ear
and measured, risk low), C9d-7/C9d-8 (the V/I feedback stream stock runs
and the firmware's own impedance reading, for the gain-17 runaway), and
T3b/T4 in `AOC-TUNING-RESEARCH.md` (stock's Waves processing on the AoC).
**omamobile-audio 0.4.1** (offline review of 0.4.0, below C9g) fixes a
PipeWire start failure mode and adds bass management, bass harmonics,
stereo width and orientation, a limiter per speaker and a better
measurement; **C9h** is the one ordered listening session that installs it
and goes through C9g, then optionally C9d-7/8 and T3b/T4.
Kernel: `omamobile-aoc` @ `829fd316a` (`wt-aoc`, `out-aoc`) and
`omamobile-audio-amp` @ `9fcc941b3` (hibernate, word length, RX6 knob;
`wt-audio-amp`), both merged into `omamobile-int`. Packages:
omamobile-device-cheetah 0.1.25 (`omamobile-aoc.service`, start script,
sensor-rail cycle), omamobile-sensors 0.2.0 (gyroscope stream, C6f), omamobile-audio 0.4.1 (not yet
installed: 0.3.5 runs; 0.4.0 was never installed),
omamobile-speaker-tuning 0.1.2 (off by default). The "Checkpoint" section
below is the running log of C5-C9: its first lists are the state before C5,
and each stage's results follow its runbook.

Earlier status (historical, superseded by the status above): **C1, C2, C3 and C4a passed on the phone; C4b (start)
did not finish** (section 0.2): the GSA accepted `START` but reported state
4, and the firmware never wrote its control block. C4b-2 (diagnostics,
setup re-apply, release reset) ran cleanly: the mailbox `START` cannot
start the firmware (section 0.3). Next is C4t: the same start through
Trusty's `hwmgr.aoc`, as stock does. Kernel branch
`omamobile-aoc` in `~/android/mainline/wt-aoc` (out dir
`~/android/mainline/out-aoc`), on `omamobile` @ `7b0f8b5d1` plus the Trusty
commits of `omamobile-fingerprint`. Everything new is disabled by default.
The runbook is section 7; stage C2 is next.

The AoC (Always-on Compute) is Google's audio and sensor DSP. On gs201 every
on-device audio path ends there: the speaker amplifiers' TDM link, the three
PDM microphones, the earpiece (the top speaker amp) and Bluetooth SCO
(`AUDIO-PLAN.md` 0.1). It also runs the sensor hub: accelerometer (auto-rotate),
proximity, light, gyro, magnetometers, barometer. `AUDIO-PLAN.md` stage A6 is
this plan.

Path abbreviations (as in the other plans):

- `L/` = our kernel, branch `omamobile-aoc` (`~/android/mainline/wt-aoc`)
- `G/` = `~/android/omamobile/out-kernel/google/gs-6.1/private` (Google's GPL gs201 kernel, the one stock runs)
- `GA/` = `G/google-modules/aoc`, `GSA/` = `G/google-modules/soc/gs/drivers/soc/google/gsa`
- `GS/` = `G/google-modules/soc/gs`
- `R/` = `~/android/reference/cheetah-stock-cp2a-root` (stock live DT, dmesg)
- `V/` = `~/android/omamobile/vendor/google/cheetah/proprietary/vendor` (stock vendor blobs)

---

## Checkpoint 2026-10-12

> **Historical.** The "Done", "Half-done" and "Next steps" lists that
> open this section are the state before C5 (kernel `f716b607e`). The
> results recorded under each numbered step (C6b-C6e, C7d, C8, C8f,
> C9a-C9d-2) and the status at the top supersede them. The numbered
> steps remain the runbook.

**Done on the phone:** C1 (GSA mailbox), C2 (read-only probes), C3 (rails
read: all five off at hand-off), C4a (load), C4t (**AoC firmware online**:
started through Trusty `hwmgr.aoc`, 82 services, 0 faults). The mailbox
`START` (cmd 91) is not enough (section 0.3).

**Done offline, built, not run** (kernel `omamobile-aoc` @ `f716b607e`,
merges cleanly into int; `make modules dtbs` passes in `out-aoc`):

- `drivers/soc/google/aoc/`: Google's AoC core (aoc.c, aoc_v1.c,
  aoc_service_core.c, aoc_firmware.c, aoc_ipc_core.c), mailbox driver
  (mailbox-wc.c, `google,gs201-aoc-mbox`), `/dev/acd-*` front ends
  (aoc_char_dev.c, aoc_channel_dev.c), imported (`f141bb96a`) and ported
  (`f716b607e`): GSA load + Trusty start, S2MPU open, System MMU windows
  from the header, vendor stubs in aoc-compat.h, restart disabled.
  Config: `CONFIG_GS201_AOC_MBOX`, `CONFIG_GS201_AOC`, `CONFIG_GS201_AOC_CHAR`
  (=m, in `kernel/configs/omamobile.config`).
- DT: three mailbox nodes and the AoC node's 48 `mboxes` (disabled).
- Repo: `overlays/aoc-core-test.dtso` (Trusty, GSA, System MMU, mailboxes,
  AoC); `omamobile-device-cheetah`: `bin/omamobile-aoc-start` (Trusty → gsa
  → rails → sysmmu → mailboxes → core → channel/char devs → load `aoc.bin`
  → wait for services and `/dev/acd-com.google.usf`, hang marker),
  `omamobile-aoc.service` (not enabled), `modprobe.d/omamobile-aoc.conf`
  (blacklists); package version not bumped. `tools/usf.py` (USF client:
  sensor list, registry load, sampling; `--self-test` passes offline) and
  `USF-PROTOCOL.md`.

**Half-done / not started:**

- W=1 and checkpatch not run over the imported Google files (vendor style).
- `dt_binding_check` not run (no dtschema here) for `google,gs201-aoc-mbox`
  and the AoC binding changes.
- No iio-sensor-proxy-style D-Bus service yet (only `tools/usf.py`).
- Audio: `aoc_alsa` not ported; CS35L41 A2/A3 not run.

**Next steps, in order:**

1. **C5 (ready to run):** merge `omamobile-aoc` @ `f716b607e` into int,
   build, push with `aoc-core-test` (instead of `aoc-boot-test` and
   `fingerprint-trusty`) plus the usual overlays. Install the device
   package files by hand for now (or bump and publish it), and the
   firmware: `tools/aoc-stage --fw … c4a` copies `aoc.bin`, or
   `tools/phone-ssh 'mkdir -p /usr/lib/firmware/updates && cat > /usr/lib/firmware/updates/aoc.bin' < V/firmware/aoc.bin`.
   Then:
   ```sh
   tools/phone-ssh 'rm -f /var/lib/omamobile/aoc-bringup-started'
   tools/phone-ssh 'cat > /usr/bin/omamobile-aoc-start && chmod +x /usr/bin/omamobile-aoc-start' < packages/omamobile-device-cheetah/bin/omamobile-aoc-start
   tools/phone-ssh 'cat > /etc/modprobe.d/omamobile-aoc.conf' < packages/omamobile-device-cheetah/vendor/modprobe.d/omamobile-aoc.conf
   tools/phone-ssh 'omamobile-aoc-start; dmesg | grep -iE "aoc|gsa|wc-mbox|sysmmu" | tail -40; ls /dev/acd-* | head; head -3 /sys/bus/platform/devices/181d0000.aoc/services'
   ```
   Expect "omamobile-aoc: up: Services : 82", `/dev/acd-com.google.usf`
   and `.non_wake_up`, "firmware version … did become online with 82
   services" from the core. Stop: any abort, "blocked" line, "aoc init no
   respond", or the AoC watchdog. Rollback: reboot (the marker then keeps
   the AoC off; `omamobile-aoc-start --retry`).
2. **C6 first sensor** (after C5 passed in the same boot):
   ```sh
   # Google's registry, from the extracted vendor tree (never commit it)
   tar -C ~/android/omamobile/vendor/google/cheetah/proprietary/vendor/etc/sensors -c registry |
     tools/phone-ssh 'mkdir -p /usr/share/omamobile/sensors && tar -C /usr/share/omamobile/sensors -x'
   tools/phone-ssh 'for f in product stage major minor variant; do printf "%s=" $f; od -An -tx1 /sys/firmware/devicetree/base/chosen/plat/$f; done'
   # C6a: read-only (sensor list, registry state)
   tools/phone-ssh 'python3 - --check-registry --duration 0' < tools/usf.py
   # C6b: load the registry into the AoC's RAM, then 3 s of accelerometer at 50 Hz
   tools/phone-ssh 'python3 - --load-registry /usr/share/omamobile/sensors/registry /usr/share/omamobile/sensors/registry/append --duration 3' < tools/usf.py
   ```
   Expect: `plat` present (stock: product 3, stage 6, major 1, minor 0,
   variant 0); after the load, a sensor list with the LSM6DSV accelerometer
   and samples near (0, 9.8, 0) m/s² with the phone upright. Only the AoC's
   RAM changes; an AoC restart (reboot) undoes it. Stop: an empty list after
   the load (the rails: `omamobile-aoc-start` turns them on before the
   firmware, check `dmesg | grep rails`), USF errors.

   **C6b result (first run):** the seven `cheetah_*.reg` scripts and the two
   `append/` ones loaded, `"/" loaded=1` (CDT 0x36100), then "0 sensors".
   Loading every script is what the HAL does and is right: each script
   starts with CDT filter lines that the AoC checks against the CDT sent with
   it (`?+0x30000:0xFFFF0000`, minus `0x32xxx` proto and `0x33xxx` EVT, in
   `cheetah_dvt.reg`), so for 0x36100 only `cheetah_dvt.reg` applies and the
   other six are dropped, not merged. The list was read at once, though:
   the AoC creates its sensors asynchronously after `loaded=1` (Registry
   Loaded, Physical Devices Ready, Virtual Devices Ready, USF Ready), and
   Android's HAL waits 500 ms after loading before its first SensorList,
   then retries once (`SensorHal::Init`). `usf.py` now polls the list
   (`--wait`, default 5 s) until it stops growing, and `--list` skips the
   sampling.

   **C6b-2** (the same boot as C6b: the registry is already loaded, so do
   not load it again):
   ```sh
   tools/phone-ssh 'python3 - --check-registry --list --wait 10' < tools/usf.py
   tools/phone-ssh 'python3 - --wait 10 --duration 3' < tools/usf.py      # accelerometer, 50 Hz
   ```
   Expect `"/" properties [('loaded', '1')]`, "N.N s: M sensors" lines as
   the list grows, then a few dozen sensors (LSM6DSV accelerometer, gyroscope,
   two MMC5633, ICP20100, TMD3719, VD6282 and Google's fused ones) and
   samples near (0, 9.8, 0) m/s² upright. If the list stays empty after
   10 s: `dmesg | grep -iE "aoc|usf" | tail -30` and stop. A clean retry is
   a reboot, `omamobile-aoc-start`, then C6b with the new `usf.py` (it now
   polls after the load). The persist calibration is not needed for a first
   reading (the service loads it read-only; never copy it into the repo).

   **C6c, auto-rotate** (package `omamobile-sensors`, build it on the phone
   with makepkg like the others, or copy `lib/` by hand):
   ```sh
   tools/phone-ssh 'systemctl start omamobile-sensor-proxy; journalctl -u omamobile-sensor-proxy -b --no-pager | tail -5'
   tools/phone-ssh 'timeout 10 monitor-sensor --accel 2>&1 | tail -5'     # iio-sensor-proxy's tool, if installed
   tools/phone-ssh 'U=$(id -nu 1000); runuser -u $U -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user start omamobile-autorotate'
   ```
   Expect: "sensors: accel (handle …), light …, proximity …", then turning
   the phone rotates the screen and touch. If a direction is mirrored, the
   transform table in `autorotate.py` needs 1 and 3 swapped (report which).
   Rollback: `systemctl stop omamobile-sensor-proxy`; the user service
   restores nothing by itself, so `hyprctl reload` (or rotate back to
   upright) before stopping it.

   **C6c result (first run):** the proxy failed with ENODEV, and every
   `AOCC_CMD_OPEN_CHANNEL` failed with -19. Not a channel leak (channel
   IDs only ever count up). The proxy unit `Requires=omamobile-aoc.service`.
   The AoC had been started by hand, so the unit was inactive and systemd
   ran `omamobile-aoc-start` again. That wrote `aoc.bin` to a running AoC:
   the core took the AoC offline, the GSA refused the image (-16), and the
   AoC stayed down until a reboot. Fixed twice:
   - `omamobile-aoc-start` (omamobile-device-cheetah 0.1.17) exits 0 when
     the AoC is already online, and refuses when an earlier start this boot
     failed;
   - kernel `67abdfab5` refuses a firmware write unless the AoC is offline.

   **Clean sequence, next boot** (device-cheetah 0.1.17 and
   omamobile-sensors 0.1.1 installed; no audio before this passes):
   ```sh
   tools/phone-ssh 'systemctl start omamobile-aoc; journalctl -u omamobile-aoc -b --no-pager | tail -3'
   tools/phone-ssh 'systemctl start omamobile-sensor-proxy; sleep 3; journalctl -u omamobile-sensor-proxy -b --no-pager | tail -8'
   tools/phone-ssh 'python3 - --check-registry --list --wait 10' < tools/usf.py
   tools/phone-ssh 'timeout 10 monitor-sensor --accel 2>&1 | tail -5'
   tools/phone-ssh 'U=$(id -nu 1000); runuser -u $U -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user start omamobile-autorotate'
   ```
   Always start the AoC through the unit (`systemctl start omamobile-aoc`),
   not the script, so units that require it see it active. The proxy loads
   the registry itself (stock scripts, then the factory calibration read
   from persist, read-only) and waits up to 10 s for the sensors. Expect
   "up: Services : 82", then "sensors: accel (handle …), light …,
   proximity …", `loaded=1` and the sensor list, then rotation.

   **C6c result (2026-10-12, 7.3.0-rc6-omamobile-push1-00269-ga874b95ca381,
   device-cheetah 0.1.18): passed.** "up: Services : 82", then "sensors:
   accel (handle 30), light (handle 44), proximity (handle 23), compass
   (handle 53)". A claim of the accelerometer read `right-up`/`tilted-up`,
   and turning the phone rotated the screen and touch in every direction.
   With the phone lying flat the orientation stays `undefined`, as with
   iio-sensor-proxy (neither axis passes 35°), so read it with the phone
   upright. Two boot problems were fixed first:
   - `aoc_alsa_dev` autoloads from the sound card node and pulls in
     `aoc_core`, `gsa` and Trusty, where `aoc_core` waits unbound (mailbox
     -517). The start script took the loaded module for "already started"
     and refused. 0.1.18 blacklists `aoc_alsa_dev`/`aoc_alsa_dev_util`,
     loads the sound card after the services are up, and tracks the
     firmware load with a marker in `/run`.
   - A copy of `omamobile-aoc.conf` left in `/etc/modprobe.d` from bring-up
     overrode the package's file of the same name: delete it (and
     `omamobile-aoc-bringup.conf`).

   **Accelerometer missing when the AoC starts at boot** (2026-10-12,
   00283 kernel, device-cheetah 0.1.20): the AoC started at about 4.8 s and
   the proxy loaded the registry at about 5.7 s. Light, proximity and the
   magnetometers (I2C) came up; the LSM6DSV (I3C) did not, even after a
   proxy restart at 225 s. On the earlier boot the registry was loaded
   minutes after the AoC started, and all of them came up. The AoC probes
   its physical sensors once, when the registry loads (the restart found it
   loaded and skipped it), so a probe that fails at that moment stays
   failed until the AoC restarts. The rails were on in both cases. Most
   likely the I3C sensor is probed before the AoC's I3C bus is ready.
   omamobile-sensors 0.1.3 waits until the AoC's firmware was loaded at
   least 15 s ago (the start script's `/run/omamobile/aoc-firmware-loaded`;
   `OMAMOBILE_AOC_SETTLE_S` overrides it) before loading the registry.
   **Result (00285 kernel): not enough.** The proxy waited 13.8 s and still
   found light, proximity and compass without the accelerometer. The AoC
   log (`/dev/acd-logging` holds everything since AoC boot, 16 KB here)
   has no sensor probe lines at its default level. Two candidates are left:
   the AoC needs much longer than 15 s after boot before the LSM6DSV
   probes, or the factory calibration from persist (which the proxy adds
   and `usf.py --load-registry` does not) is what drops the
   accelerometer; C6b-2 (stock scripts only) and C6c (proxy) both found
   it, but on C6c check whether the proxy actually read persist
   (`journalctl -u omamobile-sensor-proxy -b -N | grep loaded` for that
   boot).

   **C6d** (read-only apart from the AoC's registry RAM): before the
   reboot, `systemctl disable omamobile-sensor-proxy` (the AoC itself still
   starts at boot). Two minutes after boot, start the proxy by hand: the same
   load as at boot (stock scripts, then persist), only later:
   ```sh
   tools/phone-ssh 'systemctl start omamobile-sensor-proxy; sleep 15; journalctl -u omamobile-sensor-proxy -b --no-pager | grep -E "loaded|sensors:"'
   ```
   - accelerometer listed: boot timing; the fix is a longer settle (the
     log shows how long the AoC had been up);
   - accelerometer missing: the persist calibration is the suspect (C6b-2
     found it with the stock scripts only). On the next boot, with the proxy
     still disabled, load the stock scripts only
     (`python3 - --load-registry /usr/share/omamobile/sensors/registry /usr/share/omamobile/sensors/registry/append --list --wait 10 < tools/usf.py`)
     and send the list, plus the names of the persist files the proxy
     loaded (not their contents).
   Rollback: `systemctl enable omamobile-sensor-proxy`.

   **C6d result: neither timing nor calibration.** The proxy started about
   95 s after the AoC and still found no accelerometer, and every boot
   loads the same eight calibration files. The difference is the rails: on
   the boot where the accelerometer worked, `gs201_aoc_rails` found LDO7S
   (ctrl 0x2c) and LDO5S (0x3c) off and turned them on before the
   firmware; on every boot since, they read on (0xac, 0xbc) at 4.9 s,
   left powered through the warm reboot. The I3C LSM6DSV then keeps the
   previous AoC session's state and the new AoC never finds it; the I2C
   sensors don't care. Google's driver power-cycles these supplies around
   an AoC restart (`reset_sensor_power()`: off in reverse order, 150 ms,
   on). Kernel `829fd316a` adds `gs201_aoc_rails cycle=1` (with
   `enable=1`): sensor rails already on are turned off (LDO5S, then
   LDO7S) for `cycle_ms` (150) ms first; device-cheetah 0.1.22 passes it.

   **C6e** (same boot as C7d-6; re-enable the proxy first:
   `systemctl enable omamobile-sensor-proxy`; warm reboot from a session
   where the AoC ran, so the rails start on):
   ```sh
   tools/phone-ssh 'dmesg | grep gs201-aoc-rails; journalctl -u omamobile-sensor-proxy -b --no-pager | grep -E "settle|sensors:"'
   ```
   Expect "LDO5S prox: was on (ctrl 0xbc), cycled: off for 150 ms", the
   same for LDO7S, then both "enabled", and the proxy's "sensors: accel
   (handle …), light …, proximity …, compass …". Stop: a rail that does not
   come back on (no microphones or sensors; reboot), or accel still
   missing (send the `gs201-aoc-rails` lines). Rollback: device-cheetah
   0.1.21's start script (no `cycle`).

   **C6f gyroscope stream** (omamobile-sensors 0.2.0, for the camera's
   video stabilisation; API in `packages/omamobile-sensors/README.md`):
   `org.omamobile.SensorProxy.Gyro1` hands each client a SOCK_SEQPACKET
   socket of 24-byte records (CLOCK_MONOTONIC ns, x/y/z rad/s, seq). The
   gyroscope (LSM6DSV, `type 2`, `/dev/lsm6dsv/0/gyro`, 15-480 Hz) samples
   only while a claim is held, unbatched (`max_latency` 0, non-wakeup
   channel). Sample times are on the AoC's clock (USF slot 11 = 0); the proxy
   maps them with `aoc_clock_and_kernel_boottime` (the kernel reads the AoC
   counter and CLOCK_BOOTTIME together), re-read every second.
   **Result (2026-10-14, 7.3.0-rc6-omamobile-push1-00554-g63c0abe9c290,
   a test copy of the proxy on a private bus beside the service):** requests
   of 100, 200 and 400 Hz ran at 121.3, 242.7 and 485.4 Hz by the sample
   times (the LSM6DSV's ODRs, its clock about 1 % fast); interval SD 7-8 µs;
   latency from the sample time to the client's read 0.7-1.9 ms (median
   1.3-1.5 ms), never negative, which also confirms the clock mapping
   (GetTime and the sysfs pairing agree on the AoC − boottime offset,
   +3.604 s on that boot); one record per packet, no drops in 10 s at
   480 Hz; the proxy used about 10 % of one core at 480 Hz.
   **Installed (0.2.0, same day, proxy restarted):** the journal lists
   "gyro (handle 31, 15-480 Hz)"; an unprivileged session user's
   `omamobile-gyro` got 240 Hz over the system bus with no drops. Axes, by
   integrating the stream while the owner turned the phone: counter-clockwise
   in the screen plane +87° on z (back -90°), top towards the viewer +86° on
   x (back -103°), lying flat and lifting the left edge positive on y with x
   and z within 5° (the rolls went past 90°, so this confirms the sign only).
   That is Android's device frame, as the README states.

   **Don't `rmmod` the AoC modules.** Removing `aoc_alsa_dev`,
   `aoc_alsa_dev_util`, `aoc_core`, `gs201_aoc_sysmmu` and `gsa` while
   `aoc_core` waited for deferred probe oopsed the deferred-probe worker
   (`__device_attach_driver` on a freed driver: one of them leaves a
   driver on the bus). The device lock it held then hung every reboot in
   `device_shutdown`, which the shutdown watchdog doesn't cover: it needed
   a held power key. **Found and fixed** (kernel `dfeafb2ba`, modules
   only): `aoc_alsa_dev_util` registers its seven platform drivers (PCM,
   voice, compress, path, no-host, in-call, VoIP) at module init, but its
   exit unregistered them only once every AoC audio service had probed.
   With the AoC not online, unloading it left them on the platform bus in
   freed memory. It now always unregisters them and unwinds a failed init.
   Until that kernel is on the phone, still don't `rmmod` these modules.
3. **C7 audio** (kernel `omamobile-aoc` @ `33b28cee6` or later: the AoC
   sound card, `aoc_alsa_dev`/`aoc_alsa_dev_util`, ported from Google's
   driver, with the speaker limits in code; the amplifier description from
   `omamobile-audio` merged in). Merging into int has one conflict in
   `gs201.dtsi`: int's `usi5`/`spi_5` (GNSS) and the branch's
   `usi7`/`spi_7` (amplifiers) were added at the same place; keep both,
   `usi5` first. Config: `CONFIG_GS201_AOC_ALSA=m`, `CONFIG_SND_SOC_CS35L41_SPI=m`.
   Overlays: `aoc-core-test`, `audio-amps-test`, `aoc-sound-test` (the
   stock sound card with the amplifiers as TDM 0 codecs, generated from
   the stock tree; top amplifier slot 0, bottom slot 1).

   **Limits in code** (`aoc_alsa_card.c`, `aoc_speaker_limits()`, logged
   at card probe): "Top/Bottom Digital PCM Volume" capped at 817 (0 dB) and
   set to 657 (-20 dB); "Top/Bottom Analog PCM Volume" capped at 10 (17
   only with `speaker_protection=1`, never before C9). Boost peak 2.5 A,
   1 µH, 30 µF come from the DT (`cirrus,boost-*`). AUDIO-PLAN section 4
   applies on top: earpiece (top amp) analog ≤ 6, 1 kHz bursts of 1-2 s,
   never below 300 Hz, ≤ 30 s without protection.

   No step here uses `devmem`. The phone's `/usr/local/bin/devmem` is our
   `tools/devmem.c` (`devmem ADDRESS [VALUE]`): a second argument WRITES, so
   never pass a width (`devmem ADDR 32` writes 0x20), and never read PMU
   registers from userspace. PCM numbers do not follow the stock order
   (C7b: EP1 capture is 44, EP6 playback 47), so the steps find a device by
   its id in `/proc/asound`:
   `pcm() { grep -l "^id: $1" /proc/asound/card$C/pcm*/info | sed -n 's#.*/pcm\([0-9]*\)[pc]/info#\1#p' | head -1; }`.

   - **C7a amplifiers, read-only:** `AUDIO-PLAN.md` A2 (IDs over spidev)
     and A3 (driver probe, no card), unchanged. Stop as there.
   - **C7b card, no sound** (C5 passed this boot):
     ```sh
     tools/phone-ssh 'modprobe snd-soc-cs35l41-spi; modprobe aoc_alsa_dev_util; modprobe aoc_alsa_dev; sleep 3;
       cat /proc/asound/cards; aplay -l; arecord -l; dmesg | grep -E "aoc_speaker_limits|cs35l41|aoc_snd|aoc-snd" | tail -20'
     ```
     Expect a card with driver `aoc-snd-card`, both amplifiers ("Cirrus
     Logic CS35L41 (35a40), Revision: B2"), and four `aoc_speaker_limits`
     lines ending in `: 0`. **Stop** if any limit line is not `: 0` (the
     control was not found, so the limit is not in force): no sound tests.
   - **C7c microphones** (rails on: `omamobile-aoc-start` turned them on):
     ```sh
     tools/phone-ssh 'C=$(awk "/aoc-snd-card/{print \$1; exit}" /proc/asound/cards);
       amixer -c $C cset name="EP1 TX Mixer INTERNAL_MIC_TX" 1;
       amixer -c $C cset name="BUILDIN MIC ID CAPTURE LIST" 0,3,2,-1;
       amixer -c $C cset name="MIC DC Blocker" 1; amixer -c $C cset name="MIC Record Soft Gain (dB)" 22;
       pcm() { grep -l "^id: $1" /proc/asound/card$C/pcm*/info | sed -n "s#.*/pcm\([0-9]*\)[pc]/info#\1#p" | head -1; };
       arecord -D hw:$C,$(pcm "EP1 capture") -f S16_LE -r 48000 -c 2 -d 3 /tmp/mic.wav; ls -l /tmp/mic.wav'
     ```
     (control names from the stock `mixer_paths.xml`, `handset-mic` and
     `audio-recordC`.) Expect a 3 s file that is not all zeros (tap the phone
     while it records). **Passed** on 2026-10-12: floor RMS about 35, peaks
     to 946 / 2635 with noise.
   - **C7d first sound, top amplifier alone, DSP bypassed, -20 dB:**
     ```sh
     tools/phone-ssh 'python3 - <<"PY"
     import math, struct, wave
     w = wave.open("/tmp/tone.wav", "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
     a = int(32767 * 0.1)  # -20 dBFS
     w.writeframes(b"".join(struct.pack("<hh", s, s) for s in (int(a * math.sin(2 * math.pi * 1000 * n / 48000)) for n in range(72000))))
     w.close()
     PY'
     tools/phone-ssh 'C=$(awk "/aoc-snd-card/{print \$1; exit}" /proc/asound/cards);
       amixer -c $C cset name="Bottom Digital PCM Volume" 0; amixer -c $C cset name="Bottom Analog PCM Volume" 0;
       amixer -c $C cset name="Top PCM Source" ASP; amixer -c $C cset name="Top Analog PCM Volume" 6;
       amixer -c $C cget name="Top Digital PCM Volume";
       amixer -c $C cset name="TDM_0_RX Mixer EP6" 1;
       pcm() { grep -l "^id: $1" /proc/asound/card$C/pcm*/info | sed -n "s#.*/pcm\([0-9]*\)[pc]/info#\1#p" | head -1; };
       aplay -M -D hw:$C,$(pcm "EP6 playback") /tmp/tone.wav; dmesg | grep -iE "cs35l41|aoc" | tail -10'
     ```
     Expect a quiet 1.5 s 1 kHz tone from the **top** speaker (the
     earpiece grille): that also confirms top = chip select 0. Then the same
     for the bottom amplifier (swap Top and Bottom; Bottom Analog ≤ 10).
     **Stop:** no sound or the wrong speaker (report; do not raise the
     gain), any CS35L41 error or IRQ line, distortion, a warm phone. Never
     raise "Digital PCM Volume" above 657 or loop the tone before C9.
     Rollback: `amixer … cset name="TDM_0_RX Mixer EP6" 0`, then
     `rmmod aoc_alsa_dev aoc_alsa_dev_util snd_soc_cs35l41_spi` (the amps go
     back into reset).

     **C7d result (first run):** card, amplifiers and limits fine, but
     `aplay` (copy mode, no `-M`) failed at once with "Bad address":
     `ERR: inconsistent write/read pointers, avail = 0, towrite = 15360`.
     Not the iov_iter port (capture uses the same copy path and works).
     Prepare resets the down ring's write pointer to the ring start; on a
     ring that was never used (wp 0) that marks the whole ring as written,
     and the first copy finds no room. Google's HAL plays through mmap,
     where prepare treats the ring as full anyway and the AoC drains it.
     Hence `aplay -M` above (C7d-2). Kernel `d696fde42` (modules only:
     `aoc_alsa_dev_util.ko`) logs the ring's written/read counters if a
     copy write still fails. Stop as before, and also if `aplay -M` reports
     an mmap error or the AoC logs a SysMMU fault (report the dmesg).

     **C7d-2 result:** `aplay -M` hung (killed after 60 s) and nothing was
     heard. The AoC accepted bind, EP setup and start (`0x00c9`), then sent
     no period interrupts and no position updates. The PCM's interrupt is
     AoC mailbox index 20 (`PCM_CHANNEL`), which is the F1 mailbox
     (0x18320000, SPI 76), channel 4; the sensors use the A32 mailbox only.
     Still to tell apart: the AoC never ran the stream (no TDM 0 clock, so
     nothing drains the ring); it ran but its interrupt does not reach us;
     or the amplifiers never powered up.

   - **C7d-3, diagnosis** (kernel `omamobile-aoc` @ `dee7e2334` for the
     complete `debugfs aoc/services` listing; the sysfs `services` file
     stops at a page; modules only: `aoc_core.ko`, `aoc_alsa_dev_util.ko`).
     `tools/aoc-audio-diag` sets the C7d mixer (bottom amplifier 0/0, Top
     PCM Source ASP, Top Analog 6, Top Digital left at 657, `TDM_0_RX Mixer
     EP6` 1), plays `/tmp/tone.wav` for at most 5 s with mmap and then in
     copy mode (each under `timeout`), snapshots before, during and after,
     and sets EP6 and Top Analog back to 0:
     ```sh
     tools/phone-ssh 'bash -s' < tools/aoc-audio-diag > logs/c7d3.txt 2>&1
     ```
     Only reads apart from the mixer and the two `aplay` runs (the regmap
     files are read up to 0x10100 and the reading stops there). What the
     snapshots show:
     - the F1 mailbox's count in `/proc/interrupts` (`18320000.mailbox` or
       similar) going up during playback means the AoC signals and we
       lose it after the IRQ; no change means the AoC sends nothing;
     - `audio_playback5` Down `Rx` going up means the AoC drains the
       ring (the stream runs); flat means it never started;
     - CS35L41 0x2014 bit 0 (GLOBAL_EN) and 0x2018 bit 0 (AMP_EN) set,
       "Main AMP: On" in DAPM: the amplifier is on; 0x10090 and 0x10098
       hold the raw status bits (a PLL or clock error means no BCLK from
       the AoC); 0x4800 shows the enabled receive slots.
     Run it after the clean sequence above, C7b, and the tone file step of
     C7d (`/tmp/tone.wav` is gone after a reboot).
     Stop on anything louder than a tone burst, an amplifier error, or a
     watchdog. Send `logs/c7d3.txt`.

     **C7d-3 result (2026-10-12, 7.3.0-rc6-omamobile-push1-00269-ga874b95ca381):
     nothing heard; the AoC never read the ring.**
     - `audio_playback5` Down ring (1 × 4 MiB): Tx 0 before, 4194304
       during and after the mmap run, Rx 0 throughout. The copy run then
       failed with "avail = 0 … written 8388608, read 0".
     - Interrupts: A32 mailbox (IRQ 107) flat at 4732; F1 mailbox
       (IRQ 108, the PCM's) 12 → 15 → 16; P6 (109) 0.
     - Amplifiers: GLOBAL_EN and AMP_EN on during playback, RX slot 1
       enabled (0x4800 0x10000). IRQ1_STATUS3 0x2000003f afterwards has
       PLL_LOCK (bit 1) and PLL_CLK_CTRL moved 0x10 → 0x510: **both
       amplifiers locked to the AoC's TDM 0 bit clock**, so the AoC's
       sink ran (playing silence) while EP6 never pulled from its ring.
     - The AoC answered every command (bind 0x010f, EP setup 0x00ce and
       0x012a, start 0x00c9) with no error reply.

     What that rules out: the amplifiers, TDM 0 clocking, the PCM
     interrupt line, and the AP sending TDM configuration (it never does:
     the `TDM_0_RX` Chan/Format/Rate controls only feed the codec's
     `hw_params`; the AoC configures its port itself). The ring itself is
     the suspect: prepare "resets" the write pointer by advancing it to the
     ring start, and on a fresh ring (wp 0) that advanced it by a whole
     ring, so the ring read as full of stale data before the AoC saw the
     setup, and the AoC never flushed it. Google's HAL plays in copy mode
     (not mmap), so the copy path must work on a fresh ring.

   - **C7d-4** (kernel `omamobile-aoc` @ `24483c36e`, modules only:
     `aoc_core.ko`, `aoc_alsa_dev_util.ko`; a fresh boot, because the
     rings this boot used stay full until the AoC restarts):
     - `2211dd734` leaves a ring alone when its write pointer is already
       at the start, so a fresh ring stays empty after prepare;
     - `24483c36e` adds `aoc_alsa_dev_util ring_debug=1`, which logs the
       ring's written/read counters at prepare, start, stop and each AoC
       PCM interrupt (`aoc-audio-diag` sets it).

     Run C7b's check, the C7d tone step, then copy mode first:
     ```sh
     tools/phone-ssh 'EP=6 MODES="copy" bash -s' < tools/aoc-audio-diag > logs/c7d4a.txt 2>&1
     ```
     Expect "aoc pcm audio_playback5 prepared: written 0 read 0", then
     `irq` lines with `read` going up, Rx going up in the snapshots, and a
     quiet 1.5 s tone from the top speaker (-20 dB digital, analog 6).
     - If the tone plays: run the same with `MODES="copy copy"` (second
       stream on the same ring, wp no longer 0) and send both logs.
     - If `read` stays 0 again: try the low-latency endpoint EP2 (service
       `audio_playback1`) the same way, to tell an EP6 problem from a
       general one:
       `tools/phone-ssh 'EP=2 MODES="copy" bash -s' < tools/aoc-audio-diag > logs/c7d4b.txt 2>&1`.
     Stop: anything louder than the tone, distortion, an amplifier error,
     an AoC watchdog or a SysMMU line. Rollback: the script sets the route
     and Top Analog back to 0 itself.

     **C7d-4 result (2026-10-12, 7.3.0-rc6-omamobile-push1-00283-gafa4d777403d,
     fresh boot): the ring fix works, the AoC still reads nothing.**
     - EP6 (`audio_playback5`, 4 MiB ring), copy mode: "prepared: written 0
       read 0", "started: written 96000 read 0", then "stopping: written
       96000 read 0" 8 s later. aplay ended with EIO. No `irq` line: the AoC
       raised no PCM interrupt.
     - EP2 (`audio_playback1`, 16 KiB ring): 15360 bytes written before the
       start, never read; the next write found 1024 bytes free (-EFAULT).
     - A second EP6 run in the same boot: "prepared: written 4194304": the
       reset advances a partly used ring (wp 96000) to its start, which reads
       as full again. Use each endpoint once per boot until the AoC reads.
     - A click when the amplifier powers up (silence on TDM 0).

     **Compared with Google's older driver.** Google's gs-5.10 android14
     AoC driver (google-modules/aoc 222ba49, aoc-ipc 61ee513), written for
     older AoC firmware, against our gs-6.1 import:
     - the ring core (`aoc_ipc_core.c`) is the same, including the reset in
       prepare, so the firmware is expected to flush the ring at entry
       point setup; ours neither flushes nor reads;
     - the bind (0x010f), entry point setup (0x00ce) and source start
       (0x00c9) commands and their structures are the same;
     - gs-6.1 adds CMD_AUDIO_OUTPUT_EP_SETUP2 (0x012a: buffer and period
       size) after 0x00ce; gs-5.10 never sends it;
     - nothing else reaches the AoC: the card sends no commands at probe,
       and the `TDM_0_RX` Chan/Format/Rate controls only feed the codec;
     - the module order differs only in time (there the ALSA modules and
       the card load before the firmware; ours load after it is online,
       before `aoc_char_dev`, so the audio services still bind to ALSA).

     Our firmware is 14022723. Its strings include "Attempt to start
     playback without configuration", "Entrypoint %s is not configured and
     cannot be started" and "Entrypoint %u cannot be configured": the AoC
     logs why an entry point does not run. Google's `aocd` forwards that log
     from `/dev/acd-logging`, which our `aoc_char_dev` already exposes.

   - **C7d-5** (kernel `omamobile-aoc` @ `e8929e1b2`, modules only:
     `aoc_alsa_dev_util.ko`, which adds `ep_setup2`; fresh boot; C7b and
     the C7d tone step first). `tools/aoc-audio-diag` now also reads the
     AoC's "Audio DSP State", "Audio DSP Mode", "Audio Sink 0 Processing
     State" and "AoC Speaker Sink Channel Bitmap" in every snapshot, and with
     `AOCLOG=1` records the AoC firmware log while it runs (read only).
     1. **C7d-5a, the AoC's own account** (EP6, both setup commands, as
        before):
        ```sh
        tools/phone-ssh 'AOCLOG=1 EP=6 MODES="copy" bash -s' < tools/aoc-audio-diag > logs/c7d5a.txt 2>&1
        ```
        Expect the same failure, now with AoC log lines around the
        entry point setup and start (look for "Entrypoint", "configur",
        "Binding", "Enabling Audio Output Source", "sink"). Check the log
        excerpt for identifiers before quoting it.
     2. **C7d-5b, without EP_SETUP2** (a ring not used this boot: EP2):
        ```sh
        tools/phone-ssh 'AOCLOG=1 SETUP2=0 EP=2 MODES="copy" bash -s' < tools/aoc-audio-diag > logs/c7d5b.txt 2>&1
        ```
        Pass: "read" grows in the `irq` lines and a short quiet tone plays
        (EP2 is the stock low-latency endpoint, also routed to TDM 0). Then
        EP_SETUP2 is what stops this firmware, and its values (or its
        ordering) are the next thing to fix.
     3. Only if both fail and the log does not say why: compare with an
        older AoC firmware from an older factory image of the user's own
        (`tools/extract-vendor-firmware`), with `SETUP2=0`, on a later boot.

     Stop on anything louder than the tone, an amplifier error, an AoC
     watchdog or a SysMMU line. Rollback: the script resets the route and
     Top Analog; `echo 1 > /sys/module/aoc_alsa_dev_util/parameters/ep_setup2`.

     **C7d-5a result (2026-10-12, 7.3.0-rc6-omamobile-push1-00285-ge821a4becdea):
     root cause found in the AoC's own log.**
     ```
     F1: ERR: controller_audio_output.cc, 1912: Mode Playback is not supported by Entrypoint 47
     F1: ERR: controller_audio_output.cc, 2005: Entrypoint 47 cannot be configured
     F1: ERR: controller.cc, 906: AudioOutCtrl: ipc: audio_output_co, cmd ID: 0x00ce, tag: 0x10, rc: -1
     F1: ERR: controller_audio_output.cc, 1764: Entrypoint 47 cannot be enabled
     ```
     The driver takes the AoC entry point from the PCM device number
     (`entry_point_idx = pcm->device`, Google's "TODO: refactor needed on
     mapping between device number and entrypoint"), and the capture use
     case too (`UC_AUDIO_RECORD` is 8, EP1 capture). ASoC numbers a card's
     PCMs in DAI link order. `fdtoverlay` (libfdt) inserts every node an
     overlay creates as the first child of its parent, so the card's links
     came out reversed: BE links first, then EP6..EP1 capture, then
     EP8..EP1 playback, which made EP6 playback PCM 47 and EP1 capture
     PCM 44. Capture "worked" through the generic path, not the record use
     case. The AoC also answers a rejected command with rc -1, which the
     driver does not treat as an error (it only flags 4-byte replies).
     The snapshots read Audio DSP State 1 (Playback), DSP Mode 0, Sink 0
     Processing State 1, Speaker Sink Channel Bitmap 32.

     Fixes (second attempt; the first, writing the overlay in reverse,
     changed nothing on the phone: the applied DTB kept the source order and
     the PCM numbers stayed the same, so node order cannot be relied on and
     the overlay is back in the stock order):
     - kernel `24d9b9826` (`aoc_alsa_dev.ko`): the card sorts its parsed
       DAI links by link id into the stock order (the known front ends in
       Google's order, other front ends, then the back ends), whatever the
       device tree order: EP1-EP8 playback are PCM 0-7, EP1-EP6 capture
       PCM 8-13, as in Google's HAL configuration.
     - kernel `71c7777b0` (`aoc_alsa_dev_util.ko`): the PCM driver refuses
       to open an EP playback or capture PCM whose number does not match its
       link id ("… is PCM N, expected PCM M: the card's DAI links are not
       in the stock order"), instead of configuring another entry point.

   - **C7d-6** (kernel `omamobile-aoc` @ `829fd316a`, modules only:
     `aoc_alsa_dev.ko`, `aoc_alsa_dev_util.ko`, `gs201-aoc-rails.ko`; the
     overlay content is unchanged; device-cheetah 0.1.22; one boot together
     with C6e; C7b and the C7d tone step first):
     1. Numbering, read-only:
        ```sh
        tools/phone-ssh 'head -2 /proc/asound/card0/pcm5p/info /proc/asound/card0/pcm8c/info; dmesg | grep -c "not in the stock order"'
        ```
        Expect `id: EP6 playback` for pcm5p, `id: EP1 capture` for pcm8c,
        and 0. Stop otherwise (the new `aoc_alsa_dev.ko` is not loaded).
     2. First sound, top amplifier, -20 dB digital, analog 6:
        ```sh
        tools/phone-ssh 'AOCLOG=1 EP=6 MODES="copy" bash -s' < tools/aoc-audio-diag > logs/c7d6a.txt 2>&1
        ```
        Expect in the AoC log "Enabling Audio Output Source 5 in Mode
        Playback" and no "Entrypoint … cannot", `irq` lines with "read"
        growing, Rx moving in the snapshots, and a quiet 1.5 s 1 kHz tone
        from the top speaker. Stop: no sound with "read" growing (report the
        amplifier registers), anything louder than the tone, distortion, an
        amplifier error, an AoC watchdog.
     3. The ring after a played stream: run step 2 again in the same boot.
        Expect "prepared: written N read N" (the AoC drained the ring), and
        the tone again. If "prepared" shows written ahead of read by a whole
        ring, report it: the prepare-time reset then needs the AoC's flush.
     4. Bottom amplifier: as C7d (swap Top and Bottom, Bottom Analog ≤ 10),
        with `aoc-audio-diag` adapted or by hand under `timeout 5`.
     5. Microphones again (C7c with PCM 8, which is now the AoC record use
        case): expect a 3 s file that is not all zeros.

     **C7d-6 result (2026-10-12, 7.3.0-rc6-omamobile-push1-00290-g66446bf5b725,
     device-cheetah 0.1.22): first sound.** PCM 5 is EP6 playback and PCM 8
     EP1 capture. The top speaker played the -20 dB tone (heard); the AoC
     drained the ring (Tx = Rx = 291840, a PCM interrupt every 80 ms, 15360
     bytes each), and a second stream started from a drained ring ("written
     4194304 read 4194304"). Microphones on PCM 8 with the C7c controls:
     speech and taps at RMS 350-1100, peaks to 15013, both channels. The
     bottom amplifier never powered up: mid-tone, spi6.1 had GLOBAL_EN 0,
     AMP_EN 0 and no RX slot enabled (0x4800 0), while spi6.0 (muted) had
     all three, though both took hw_params (same SP_FORMAT, PLL locked).
     "AoC Speaker Sink Channel Bitmap" is read-only: the endpoints bound to
     the speaker sink (32 = EP6), not a channel setting.

   - **C7d-7, bottom amplifier** (same kernel; no new build). Both amplifiers
     are codecs of the one TDM_0_RX back end, with the same routes and DT
     setup, so the question is which DAPM widget of spi6.1 stays off.
     `tools/aoc-amp-diag` sets stock's back end format first (TDM_0_RX and
     TDM_0_TX: Four, S32_LE, SR_48K; with the driver default, S16_LE stereo,
     the amplifiers get 16-bit words in 32-bit slots), mutes the other
     amplifier, plays a 2 s tone at -20 dB digital, analog 6, and 0.8 s in
     dumps every DAPM widget of both amplifiers (state and paths), their
     registers and the DAPM and CS35L41 debug log (dynamic debug, if built).
     1. Bottom alone:
        `tools/phone-ssh 'AMP=bottom CH=LR bash -s' < tools/aoc-amp-diag > logs/c7d7a.txt 2>&1`.
        If it plays: go on. If not: send the log (look at "Bottom AMP
        Playback", "Bottom ASPRX1", "Bottom PCM Source", "Bottom Main AMP",
        "Bottom SPK": the first one that is Off with an active input is the
        break; also any "Enable(1) failed" or PUP_DONE line).
     2. Channel map: `AMP=both CH=L` (expect the top speaker only), then
        `AMP=both CH=R` (expect the bottom only), into c7d7b/c7d7c.txt. Stock
        puts left on the top (slot 0) and right on the bottom (slot 1).
     3. Both: `AMP=both CH=LR` (c7d7d.txt), quiet tone from both.
     Stop: anything louder than the tone, distortion, an amplifier error or
     IRQ storm, a warm phone. Rollback: the script sets the route and both
     analog gains to 0; the TDM_0 format controls can stay (stock values).

4. **C8 speaker protection, UCM and PipeWire** (package `omamobile-audio`
   0.1.0; after C7d-6 passed: stock PCM numbers, the AoC drains EP6). Goal:
   the speaker is "Built-in Audio Speaker" in PipeWire and the microphones
   "Built-in Audio Microphone"; the volume keys and the quick-settings
   slider move it; both amplifiers run Cirrus's protection firmware with the
   factory calibration, as stock. **The C7 limits stay:** digital ≤ 657
   (-20 dB), analog ≤ 10, enforced by the kernel (`aoc_speaker_limits()`)
   and again by the service, which refuses to unmute above them or on a
   kernel without them. Stock's gains (analog 17, digital 817) are C9.

   **What the package does** (`packages/omamobile-audio`, `README.md` there):
   - `omamobile-speaker-protection.service` (not enabled by the package):
     loads `snd_soc_cs35l41_spi` (now blacklisted, so this is the only way
     the card comes up), waits for the card, **mutes both amplifiers**
     (Digital PCM Volume 0), checks the limits, the firmware and the
     calibration, sets `DSP1 Preload Switch` (the firmware and each
     speaker's tuning load), writes `CAL_AMBIENT`, `CAL_R`, `CAL_STATUS`,
     `CAL_CHECKSUM` (mainline cs-amp-lib's order) and reads them back,
     sets `DSP RX1/RX2 Source` ASPRX1 and `PCM Source` DSP (stock's default
     path in `V/etc/mixer_paths.xml`), analog 6, and unmutes to 657 last.
     Any failure leaves both muted; a hang leaves a marker, and the next
     boot keeps the driver unloaded (no card at all). It logs no
     calibration values. `omamobile-speaker-protection status` reports
     the DSP state, `mute` mutes.
   - The calibration: `persist:/audio/speaker.cal`, read with debugfs
     (read-only; persist is never mounted), copied to `/run/omamobile`
     (mode 0600). Six LE u32 per amplifier; the service checks status 1,
     checksum = R + status, R < 2^24, ambient ≤ 60 °C. **Record 0 goes
     to Top, record 1 to Bottom.** Evidence: the stock HAL library
     (`V/lib64/audio_spk_35l41.so`) indexes its amplifiers 0-3 as
     "Left/Top", "Right/Bottom", "Left Bottom", "Right Bottom" (the dump in
     `cs35l41_set_healthe_data_to_property`), reads the file per
     `amp_index`, and amp 0 is the unprefixed (left) mixer controls, which
     are chip select 0, the top speaker (`AUDIO-PLAN.md` 1.1). The fifth
     word is what its dump calls `amp_pcm_gain`; the fifth and sixth equal
     stock's AMP PCM Gain and Digital PCM Volume; neither is used. C8c
     checks the mapping on the phone.
   - The firmware: `tools/extract-vendor-firmware` now also copies
     `cs35l41-dsp1-spk-prot.wmfw` (both amplifiers) and the two tunings,
     named as mainline wm_adsp asks for them with our DT's
     `cirrus,subsystem-id = "cheetah"` and the Top/Bottom prefixes:
     `cirrus/cs35l41-dsp1-spk-prot-cheetah.wmfw`, `-cheetah-top.bin`
     (stock's unprefixed `.bin`) and `-cheetah-bottom.bin` (stock's `R-`).
     The service refuses to start unless all three are there: otherwise
     wm_adsp falls back to linux-firmware's generic
     `cirrus/cs35l41-dsp1-spk-prot.{wmfw,bin}` (a laptop's tuning) or to an
     unsuffixed tuning. The stock prot and cali `.wmfw` are the same file;
     only the tunings differ.
   - UCM2 for the card driver `aoc-snd-card`
     (`ucm2/conf.d/aoc-snd-card/aoc-snd-card.conf`,
     `ucm2/Google/cheetah/HiFi.conf`), verb HiFi: Speaker = `EP6 playback`,
     Mic = `EP1 capture`, both **found by their PCM id**
     (`${find-device:…regex='^EP6 playback'}`), so they resolve to PCM 5
     and PCM 8 with the C7d-6 kernel and keep working if the numbering
     moves. The verb sets the routes (an ASoC DPCM front end with no back
     end fails at prepare, and PipeWire opens the PCMs while probing):
     `TDM_0_RX Mixer EP6`, stock's record path (C7c), and stock's TDM 0
     init values `TDM_0_RX/TX Chan Four, Format S32_LE, Sample Rate
     SR_48K`. The format matters: cs35l41's `hw_params` takes the slot
     width from the sample width, so the default S16_LE gives the
     amplifiers 16-bit slots against the AoC's four 32-bit ones, and the
     bottom amplifier (slot 1) would read the low half of slot 0. The
     profile touches no amplifier control, so PipeWire uses software
     volume and cannot raise the amplifiers.
   - WirePlumber (`51-omamobile-aoc.conf`, matched on the card name
     `google,aoc-snd-card`): no mmap and 4 periods of 960 frames (stock
     `audio_platform_configuration.xml`: deep buffer and record are
     `mmap="false"`, 4 × 20 ms), and the names "Built-in Audio Speaker" /
     "Built-in Audio Microphone" (the card is a platform device with no
     udev form factor).

   Checked offline: `packages/omamobile-audio/test/all` (alsa-lib parses
   the profile; the service against stand-ins for amixer, modprobe and
   debugfs: the happy path, record → amplifier mapping, mute first and
   unmute last, refusal and mute for each failed check, the hang marker,
   no values in the output); the PCM lookup by id against a real card on
   the laptop; `tools/extract-vendor-firmware` against the factory image.

   No step uses `devmem`. Volume ceilings: never edit the service's
   `DIGITAL_CEIL`/`ANALOG_CEIL` or pass `speaker_protection=1` in C8.

   - **C8.0 install** (laptop, then the phone; risk low: files only):
     ```sh
     tools/extract-vendor-firmware ~/android/factory/cheetah-<build>/image-cheetah-<build>.zip   # -> out/vendor-firmware
     tar -C out/vendor-firmware -cf - usr/lib/firmware/updates/cirrus | tools/phone-ssh 'tar -C / -xf -'
     tools/phone-install-package packages/omamobile-audio
     tools/phone-ssh 'rm -f /etc/modprobe.d/omamobile-audio-bringup.conf; ls /etc/modprobe.d/'
     ```
     (the last line drops A3's bring-up blacklist, now in the package.)
     Expect `omamobile-audio 0.1.0-1` and all `ok` lines from `test/all`
     in makepkg's check. Then **reboot (ask first)**, so the boot starts
     with the amplifier driver blacklisted and fresh AoC rings.
     Rollback: `pacman -R omamobile-audio`.
   - **C8a read-only** (risk none):
     ```sh
     tools/phone-ssh 'uname -r; ls /usr/lib/firmware/updates/cirrus/; lsmod | grep -c cs35l41; cat /proc/asound/cards;
       systemctl is-enabled omamobile-speaker-protection;
       d=$(grep -l "^PARTNAME=persist$" /sys/class/block/*/uevent); debugfs -R "stat /audio/speaker.cal" /dev/$(basename ${d%/uevent}) 2>/dev/null | grep -o "Size: [0-9]*"'
     ```
     Expect the three `cs35l41-dsp1-spk-prot-cheetah*` files, `0` (driver
     not loaded), no `aoc-snd-card` line, `disabled`, `Size: 48`. Stop:
     the card is already there (something else loads the driver: find it
     before going on), or no `speaker.cal`.
   - **C8b the service by hand** (risk low: the amplifiers power up and
     their DSPs load, nothing plays; announce it, a click is possible):
     ```sh
     tools/phone-ssh 'systemctl start omamobile-speaker-protection; journalctl -u omamobile-speaker-protection -b --no-pager | tail -8;
       omamobile-speaker-protection status; dmesg | grep -iE "cs35l41|DSP1|aoc_speaker_limits" | tail -25'
     ```
     Expect "factory calibration read from persist (read-only): both
     records valid", "calibration written to both DSPs and read back",
     "speaker protection on: both amplifiers through the DSP, digital 657,
     analog 6"; `status`: for Top and Bottom "PCM Source DSP, Digital 657
     (max 817), Analog 6 (max 10), DSP1 Firmware Protection, Preload on"
     and "calibration in the DSP vs persist: match"; dmesg: per amplifier
     `cirrus/cs35l41-dsp1-spk-prot-cheetah.wmfw: format 3 …`, its own
     `-top.bin` / `-bottom.bin` line, "Firmware: 400a4 …", no errors, and
     the four `aoc_speaker_limits` lines ending in `: 0`.
     **Stop:** any "did not start" line (the amplifiers are muted; send
     the journal and dmesg lines), the wrong tuning on an amplifier, a
     CS35L41 error or IRQ line, `max` other than 817 / 10. **If the log
     says MUTING FAILED:** `rmmod snd_soc_cs35l41_spi` at once (the amps go
     into reset). Rollback: `omamobile-speaker-protection mute`.
   - **C8c protected tone, each speaker alone** (risk medium: the first
     sound through the protection firmware; -20 dBFS 1 kHz for 2 s at the
     C7 levels; announce it):
     ```sh
     tools/phone-ssh 'python3 - <<"PY"
     import math, struct, wave
     a = int(32767 * 0.1)  # -20 dBFS
     for name, l, r in (("left", 1, 0), ("right", 0, 1)):
         w = wave.open(f"/tmp/tone-{name}.wav", "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
         s = [int(a * math.sin(2 * math.pi * 1000 * n / 48000)) for n in range(96000)]
         w.writeframes(b"".join(struct.pack("<hh", v * l, v * r) for v in s)); w.close()
     PY'
     tools/phone-ssh 'C=$(awk "/\]: aoc-snd-card - /{print \$1; exit}" /proc/asound/cards);
       for n in "Chan Four" "Format S32_LE" "Sample Rate SR_48K"; do amixer -q -c $C cset name="TDM_0_RX ${n% *}" "${n##* }"; done;
       amixer -q -c $C cset name="TDM_0_RX Mixer EP6" 1;
       for side in left right; do echo "== $side";
         (sleep 1; omamobile-speaker-protection status | grep -vE "^(ok|no state)") & timeout 5 aplay -q -D hw:$C,5 /tmp/tone-$side.wav; wait; sleep 1; done;
       amixer -q -c $C cset name="TDM_0_RX Mixer EP6" 0; dmesg | grep -iE "cs35l41|DSP1" | tail -10'
     ```
     (with PipeWire running and the card new to it, it may already hold
     the PCM: if `aplay` says busy, do C8d first and come back to the
     mapping check with `pw-play --target` on the speaker sink.)
     Expect "left" from the **top** speaker only, then "right" from the
     **bottom** speaker only, both quiet and clean. During each tone, for
     both amplifiers: `CAL_SET_STATUS 2` (stock HAL: 2 = calibration
     applied, 1 = firmware defaults), `CSPL_ERRORNO 0`, and
     `CSPL_TEMPERATURE` values that agree between the two amplifiers.
     Record all of them. A swapped calibration (records 0/1 the other way
     round) shows as the two temperatures apart by roughly 15 °C worth (the
     two resistances differ by about 6 %), one above and one below room
     temperature. **Stop:** sound from the wrong speaker or both, silence
     (send status and dmesg; do not raise any gain), `CAL_SET_STATUS` 1 or
     other, `CSPL_ERRORNO` non-zero, distortion, an amplifier error, a warm
     phone. Rollback: `omamobile-speaker-protection mute`.
   - **C8d PipeWire, keys, slider, microphones** (risk medium; announce
     it: short sounds at low volume):
     ```sh
     U='U=$(loginctl list-users --no-legend | awk "\$2 != \"root\" {print \$2; exit}"); I=$(id -u $U); as_user() { runuser -u $U -- env XDG_RUNTIME_DIR=/run/user/$I "$@"; }'
     tools/phone-ssh "$U"'; as_user wpctl status | sed -n "/Sinks/,/Streams/p"; as_user pactl get-default-sink; as_user pactl get-default-source'
     tools/phone-ssh "$U"'; as_user wpctl inspect @DEFAULT_AUDIO_SINK@ | grep -E "node.description|disable-mmap|period-size|period-num|api.alsa.path"'
     tools/phone-ssh "$U"'; as_user wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.4; (sleep 1; cat /proc/asound/card*/pcm5p/sub0/hw_params) & as_user timeout 5 pw-play /tmp/tone-left.wav; wait'
     tools/phone-ssh "$U"'; as_user timeout 4 pw-record --rate 48000 --channels 2 /tmp/mic.wav; python3 -c "import wave,array,sys; w=wave.open(\"/tmp/mic.wav\"); a=array.array(\"h\", w.readframes(w.getnframes())); print(len(a), max(map(abs,a)))"'
     ```
     Expect the sink "Built-in Audio Speaker" and the source "Built-in
     Audio Microphone", both defaults (not "Dummy Output");
     `api.alsa.disable-mmap = true`, period size 960, 4 periods,
     `api.alsa.path` on PCM 5; `hw_params` with `access: RW_INTERLEAVED`
     and `period_size: 960`; the tone from the top speaker; a recording
     that is not all zeros (tap the phone). Then by hand: the volume keys
     move Omarchy's OSD and `pactl get-sink-volume @DEFAULT_SINK@`; the
     quick-settings slider follows them and changes the level; mute works.
     The amplifier controls do not move (`omamobile-speaker-protection
     status` still shows 657 / 6). **Stop:** "Dummy Output" (send
     `journalctl --user -u wireplumber -b | grep -iE "ucm|aoc|alsa"` and
     dmesg's "no backend DAIs" lines), underruns or crackle (try
     `api.alsa.disable-tsched = true` in the WirePlumber rule and report),
     anything louder than C8c at 40 %. Rollback: `wpctl set-mute
     @DEFAULT_AUDIO_SINK@ 1`; `omamobile-speaker-protection mute`.
   - **C8e at boot** (risk low-medium: boot ordering; ask before the
     reboot):
     ```sh
     tools/phone-ssh 'systemctl enable omamobile-speaker-protection'
     # reboot, then after the login:
     tools/phone-ssh 'systemd-analyze blame | grep -E "speaker|aoc"; journalctl -u omamobile-speaker-protection -b --no-pager | tail -4; omamobile-speaker-protection status | head -3'
     ```
     The unit runs after `omamobile-aoc.service` and before
     `systemd-user-sessions.service`, so PipeWire meets the card once,
     already protected. Expect "speaker protection on" before the session
     starts, a few seconds in the blame list, and the C8d sink right after
     login. **Stop:** the login waits on it for long (its timeout is 60 s;
     `systemctl disable omamobile-speaker-protection` and report), or a
     "did not start" line. If a boot hangs in the service, the next one
     says "the last start … never finished" and leaves the amplifiers off;
     after reading that boot's log, `omamobile-speaker-protection start
     --retry`. Rollback: `systemctl disable omamobile-speaker-protection`
     (no card from the next boot on).

   Results go here with the date and `uname -r`. Then bump
   `omamobile-audio` if anything changed, and record the CSPL readings as
   the baseline C9 compares against.

   **C7d-7 result (2026-10-12, 7.3.0-rc6-omamobile-push1-00290-g66446bf5b725):
   passed.** With the stock TDM_0 format set first (Four, S32_LE, SR_48K),
   `AMP=bottom CH=LR` powered the bottom amplifier (0x2014 1, 0x4800
   0x10000; every DAPM widget from "Bottom AMP Playback" to "Main AMP" On),
   and the tone came from the bottom speaker. Then `AMP=both`: `CH=L` from
   the top only, `CH=R` from the bottom only, `CH=LR` from both, as stock
   (left = top = slot 0, right = bottom = slot 1). The earlier silent bottom
   run used the driver's default TDM_0 format (S16_LE stereo). The UCM
   profile (C8) sets the stock format.

   **C8 result (2026-10-12, 7.3.0-rc6-omamobile-push1-00303-g9086704161a9,
   omamobile-audio 0.1.1): C8a-C8e passed.**
   - C8b first failed on a parser bug (the limits check read the dB line's
     "max=12.00dB" as a second maximum and kept the amplifiers muted),
     fixed in 0.1.1. Then: top "…C10_EVT1p1_top_tune.bin", bottom
     "…C10_DVT_bot_tune.bin"; calibration "match" on both; 657/6, PCM
     Source DSP, Preload on. "DSP1: Legacy support not available" once per
     amplifier at first playback.
   - C8c: left from the top only, right from the bottom only (by ear).
     During each tone, both amplifiers: CAL_SET_STATUS 2, CSPL_STATE 0,
     CSPL_ERRORNO 0, HALO_STATE 2. **CSPL baseline** (CSPL_TEMPERATURE,
     unsigned Q14 °C): top 409852 then 409664 (25.02 °C, 25.00 °C), bottom
     409662 both times (25.00 °C). Both near room temperature and within
     0.02 °C of each other: with the two records swapped, the 6 % apart
     resistances would put them about 15 °C apart. So record 0 = top is
     confirmed.
   - C8d: "Built-in Audio Speaker" and "Built-in Audio Microphone" the
     defaults; disable-mmap true, period 960 × 4, `hw:googleaocsndcar,5`;
     `pw-play` worked; `pw-record` 3.9 s, peak 483 in a quiet room; the
     amplifier controls stayed at 657/6; the volume keys and the
     quick-settings slider work (confirmed by the human). The runbook's
     `id -nu 1000` was wrong for this phone (the user is uid 1001): find
     the session user instead (below).
   - C8e: `systemd-analyze blame`: omamobile-speaker-protection 1.168 s,
     omamobile-aoc 1.072 s; "speaker protection on" at 7.05 s, before
     login; after login both nodes the defaults; status "ok: protection
     firmware with factory calibration, PCM Source DSP, digital 657,
     analog 6".
   - By ear (the human): at these levels media is soft and the top
     earpiece dominates; it sounds like the call speaker. C9 takes this.

   **C8 failure in real use (same boot as C8e).** YouTube through PipeWire
   played, then:
   ```
   [205.53] alsa-aoc cmd [output] id 0x00c9 (stream stop)
   [205.54] cs35l41 spi6.0: Failed to set mailbox cmd 1 (status 0)
   [205.54] ASoC: PRE_PMD: Top DSP1 event failed: -42      (the same for Bottom)
   [221.48] cs35l41 spi6.0: Wake failed, re-enter hibernate: -42
            … "CSPL Error Detected" (361 in total), "Wake failed … -22"
   [223.17] cs35l41 spi6.0: Timed out waking device; ASoC error (-110) at
            snd_soc_pcm_component_pm_runtime_get()
   ```
   PipeWire's open timed out, the speaker node went to error and was
   destroyed (Dummy Output); the microphones went later. `systemctl stop`
   muted, `rmmod` was refused (the card holds the module), and a
   `systemctl start` then reported "ok" and **unmuted the broken
   amplifiers without reloading their firmware**. Forcing a resume
   (`power/control` on) failed the same way.

   Analysis (mainline `sound/soc/codecs/cs35l41.c`, `cs35l41-lib.c`;
   Google's `google-modules/amplifiers/cs35l41/cs35l41.c` for stock):
   - At stream stop the DSP1 widget's PRE_PMD sends CSPL_MBOX_CMD_PAUSE (1)
     and polls DSP_MBOX_2 five times, 1 ms apart, for PAUSED. This
     firmware kept answering 0 (RUNNING). The AoC had already stopped the
     TDM bit clock (cmd 0x00c9), which is the amplifiers' PLL reference, so
     the DSP most likely had no clock to act on the mailbox. Google's
     driver sends the same pause later (main amplifier POST_PMD) and
     ignores its result.
   - runtime suspend (autosuspend 3000 ms) hibernates the DSP only once
     it has run (`dsp.cs_dsp.running`); that is why the 7 s start and the
     idle minutes before the first playback were fine. It writes the
     hibernate command without waiting for an answer; resume then sends
     "out of hibernate" and waits for PAUSED, which never comes, retries,
     re-enters hibernate, and ends in CSPL errors and -ETIMEDOUT at the next
     stream's `pm_runtime_get`. Stock's driver hibernates only with its
     own `cirrus,hibernate-enable` sequence; ours is not that one.
   - Without hibernation the unacknowledged pause is harmless: the next
     stream's POST_PMU finds RUNNING (or PAUSED) and sends RESUME, which
     this firmware answers.

   Fixes:
   - Kernel, branch `omamobile-audio-amp` @ `60d3ca176` (worktree
     `~/android/mainline/wt-audio-amp`, out `out-audio-amp`, on int
     `908670416`): `8c4a74fc3` dt-binding `cirrus,dsp-no-hibernate`,
     `165c2da7b` cs35l41 skips hibernate in runtime suspend and the wake in
     runtime resume when it is set, `60d3ca176` sets it on both cheetah
     amplifiers. Built (Image.gz, dtbs, modules); `cs35l41.o` W=1 clean;
     checkpatch: only the trailer warnings; the cheetah DTB carries the
     property on both amplifiers. `dt_binding_check` not run (no dtschema
     here).
   - omamobile-audio 0.2.0 (`7be2246`): holds both amplifiers awake
     (`power/control` on, from a udev rule at bind and checked by the
     service), so it works on kernels without the property too; `start`
     rebinds the amplifiers when the driver is already bound (a chip reset
     and a fresh firmware load: `systemctl restart` is the recovery);
     a health check before unmute; `omamobile-speaker-watch.service` mutes
     on any amplifier failure in the kernel log, an amplifier no longer held
     awake, a level above the ceilings, or a DSP not running the protection
     with its calibration during playback. Its tests cover each case.

   **Checkpoint 2026-10-12 (amp hibernate fix / C9; historical, superseded
   by the C8f result and the C9 results below).** Done: the kernel
   fix (branch above, built), omamobile-audio 0.2.0, extract-vendor-firmware
   with the media deltas (`231936e`). Ready: C8f below. Next: C9 (stock
   gains and balance under verified protection), after C8f passes.

   - **C8f the amplifiers across idle** (kernel: int with
     `omamobile-audio-amp` merged; omamobile-audio 0.2.0; the media deltas
     are installed by the same firmware step but stay off). The session
     user, for all PipeWire steps from here on:
     ```sh
     U='U=$(loginctl list-users --no-legend | awk "\$2 != \"root\" {print \$2; exit}"); I=$(id -u $U); as_user() { runuser -u $U -- env XDG_RUNTIME_DIR=/run/user/$I "$@"; }'
     ```
     1. Install (risk low): merge and push the kernel (ask first), then
        ```sh
        tools/extract-vendor-firmware ~/android/factory/cheetah-<build>/image-cheetah-<build>.zip
        tar -C out/vendor-firmware -cf - usr/lib/firmware/updates/cirrus | tools/phone-ssh 'tar -C / -xf -'
        tools/phone-install-package packages/omamobile-audio
        tools/phone-ssh 'udevadm control --reload; systemctl daemon-reload'
        ```
        Expect `omamobile-audio 0.2.0-1` with every test `ok`. Reboot
        (ask first).
     2. Read-only after the boot (risk none):
        ```sh
        tools/phone-ssh 'uname -r; for d in /sys/bus/spi/drivers/cs35l41/spi*; do echo ${d##*/} $(cat $d/power/control $d/power/runtime_status) $([ -e $(readlink -f $d/of_node)/cirrus,dsp-no-hibernate ] && echo no-hibernate); done;
          systemctl is-active omamobile-speaker-protection omamobile-speaker-watch; omamobile-speaker-protection status; omamobile-speaker-protection health'
        ```
        Expect both amplifiers "on active no-hibernate", both units active, status "ok: stage c8 … held
        awake", "healthy". Stop: a unit failed or "not healthy" (send the
        journal of both units).
     3. Five cycles of play, stop, idle well past the 3 s autosuspend,
        play again (risk low: C8 levels; announce it, ten short tones):
        ```sh
        tools/phone-ssh 'omamobile-speaker-protection signal tone /tmp/c8f.wav --level -23 --seconds 2'
        for i in 1 2 3 4 5; do
          tools/phone-ssh "$U"'; as_user timeout 6 pw-play /tmp/c8f.wav; echo "pw-play $?"; sleep 15;
            omamobile-speaker-protection health; dmesg | grep -E "cs35l41|DSP1" | tail -3; systemctl is-active omamobile-speaker-watch'
        done
        tools/phone-ssh 'journalctl -u omamobile-speaker-watch -b --no-pager | tail -20; omamobile-speaker-protection status | tail -4'
        ```
        Expect each cycle: the tone, `pw-play 0`, "healthy" (notes about
        "Failed to set mailbox cmd 1" are allowed: the pause at stop), the
        watchdog active, no "Wake failed", "CSPL Error", "Timed out" or
        "pm_runtime_get" line. **Stop:** a cycle without sound, any of those
        lines, the watchdog inactive or a "muted: watchdog: …" status (send
        the journal). Rollback: `omamobile-speaker-protection mute`.
     4. The same with PipeWire left idle for 60 s between two plays (its
        own suspend closes the PCM after 5 s), then a few minutes of real
        media in Chromium with pauses. Expect the same.
     5. Recovery (risk low): `tools/phone-ssh 'systemctl restart
        omamobile-speaker-protection; sleep 3; omamobile-speaker-protection
        status | head -3; systemctl is-active omamobile-speaker-watch'`.
        Expect "rebinding both amplifiers", "ok", the watchdog active
        again, and the speaker back in PipeWire within a few seconds (the
        card goes away and comes back). Stop: no card after the rebind
        (reboot, ask first).
     6. Watchdog negative test (risk low, C8 levels; the --level is RMS, so
        -23 is a -20 dBFS peak tone):
        ```sh
        tools/phone-ssh "$U"'; C=$(awk "/\]: aoc-snd-card - /{print \$1; exit}" /proc/asound/cards);
          as_user timeout 6 pw-play /tmp/c8f.wav & sleep 1; amixer -q -c $C cset name="Top PCM Source" ASP; wait; sleep 2;
          omamobile-speaker-protection status | head -1'
        ```
        Expect the watchdog
        to mute both within about 2 s ("muted: watchdog: Top: PCM Source
        is ASP, not DSP"), then `systemctl restart
        omamobile-speaker-protection` to restore.

   **C8f result (2026-10-12, 7.3.0-rc6-omamobile-push1-00306-g60d3ca176c80,
   omamobile-audio 0.2.1): passed.** Both amplifiers "power/control on,
   active" with `cirrus,dsp-no-hibernate`. 0.2.0's watchdog crashed at boot
   (it failed safe, muted): `AlsaCtl._info` kept the previous control's numid,
   so every read returned the previous control; fixed in 0.2.1 (`2625199`,
   `snd_ctl_elem_id_clear` before each lookup). Then: `systemctl restart`
   rebound both amplifiers and came up "healthy"; five cycles of a 2 s tone,
   stop, 15 s idle and a health check all played (heard), each "healthy",
   zero "Wake failed / CSPL Error / Timed out / pm_runtime_get" lines, the
   watchdog active throughout; real YouTube media in Chromium with pauses of
   30 s and more kept playing (the human). Watchdog negative test: switching
   Top PCM Source to ASP mid-tone logged "watchdog: Top: PCM Source is ASP,
   not DSP", muted both and exited; a restart restored "ok". (Minor: `status`
   then shows "muted: the speaker watchdog stopped", the stop handler's
   reason, instead of the watchdog's own.)

5. **C9 stock media gains and balance under verified protection**
   (after C8f passed; omamobile-audio 0.2.0 has everything this needs).

   **What stock does for media on the speaker**, from `V/etc/mixer_paths.xml`,
   `V/etc/audio_platform_configuration.xml`, `V/etc/waves_config.ini` and
   our analysis of the stock HAL libraries (`audio.primary.gs201.so`,
   `audio_spk_35l41.so`, `audio_waves_aoc.so`, `audio.platform.aoc.so`):
   - **The amplifiers get equal gains:** Digital PCM Volume 817 (0 dB) and
     AMP PCM Gain 17 (17.5 dB) on both, PCM Source DSP, both DSP inputs
     from ASPRX1, boost peak 2.5 A for the speaker. Nothing in the HAL
     sets a per-amplifier media gain. The only per-amplifier change is
     "acoustic shock" protection: when proximity says the phone is at the
     ear during media, the amp library saves the top amplifier's Digital
     PCM Volume, sets it to 0, waits 34 ms and switches the top amplifier
     off; when the phone moves away it restores both.
   - **The media delta:** the route code enables a device's path, then at
     once its "-post" path. For the speaker that is `speaker-post`, which
     loads `fast_switch3.txt` into the top DSP and `fast_switch4.txt` into
     the bottom DSP (Google's driver: the word list into
     `CSPL_UPDATE_PARAMS_CONFIG`, command 8 into `CSPL_COMMAND`, then
     `CSPL_STATE` must read running). `mixer_paths.xml` calls these "load
     Bypass FIR"; the voice speaker path loads 1/2, "Enable FIR". Whether
     the tuning's state after load is the FIR-on (voice) one is not
     readable from the files: the deltas differ from each other in two
     words only, and the tuning blobs are opaque. C9b tells by ear.
   - **The AoC processes the speaker sink:** stock runs Waves MaxxAudio
     on the AoC's speaker sink (`audio_waves_aoc.so`, module argument
     `Sink=SPK:1`; `waves_config.ini`: instance 1 on device 0 at 48 kHz,
     presets SPEAKER_MUSIC / SPEAKER_SAFE_MUSIC and throttled versions, with
     per-orientation subtypes), with its preset (`V/etc/waves_preset.mps`)
     sent as tuning data through `/dev/acd-audio_output_tuning`; the
     speaker back end has its own tuning id (2). The amp library reads
     "AoC Speaker Mixer ASP Mode" to decide whether Waves or the amplifiers
     swap left and right with the orientation. **We send none of this**, so
     our speaker path is flat: no EQ, no dynamics, no loudness. That, more
     than the amplifier gains, is likely why the top earpiece (bright, near
     the ear) dominates and the whole is soft. Driving the AoC's tuning
     interface is a project of its own (C10-tuning, below).
   - **What protection needs:** the CSPL model reads its voltage and
     current sense inside the amplifier: DSP1 RX3/RX4 default to VMON/IMON
     (`cs35l41-lib.c` register defaults), and the driver points RX5-RX7 at
     VPMON, VBSTMON and TEMPMON (`cs35l41_dsp_init()`); powering the DSP
     widget powers those monitors (DAPM routes "DSP1" → VMON, IMON, …).
     The TDM TX slots (ASP TX1/TX2 = VMON/IMON, also the register
     defaults, as stock sets them) only carry the sense back to the AoC for
     its own use and need nothing from us.
   - **Formats** (from the HAL's own conversions): CSPL_TEMPERATURE and
     BDLOG_MAX_TEMP are unsigned Q14 °C; BDLOG_MAX_EXC unsigned Q19 mm;
     SPK_OUTPUT_POWER raw / 2^23 × 667.19. States: HALO_STATE 2 = running;
     CSPL_STATE 0 running, 1 error, 2 muted, 3 reiniting, 6 diagnosing;
     CAL_SET_STATUS 2 = calibration applied, 1 = defaults.
     `omamobile-speaker-protection status` / `monitor` print these decoded.

   **Rules for every C9 step.** The watchdog is active
   (`systemctl is-active omamobile-speaker-watch`); `monitor` runs during
   every sound (`tools/phone-ssh 'omamobile-speaker-protection monitor 15 1'`
   in a second terminal, or as below) and its lines go into the results;
   test signals are the package's multitone (300 Hz-8 kHz, pink, peaks
   below -1 dBFS) or a 1 kHz tone, 10 s at most per burst, 60 s rest
   between bursts; PipeWire's sink volume is set explicitly before each
   burst. **Stop** on any of: CSPL_STATE not 0, CSPL_ERRORNO not 0,
   BDLOG_OVER_TEMP_COUNT or BDLOG_OVER_EXC_COUNT rising, BDLOG_ABNORMAL_MUTE
   not 0, a coil temperature above 45 °C or more than 10 °C above its value
   before the burst, a watchdog mute, any cs35l41 error in dmesg, buzzing,
   rattling or distortion, a warm phone. CSPL_ATTENUATION moving from its
   idle value means the protection is limiting: record it, finish the
   burst, and do not go to a louder step. Rollback for every step:
   `omamobile-speaker-protection mute`, then the previous
   `/etc/omamobile/speaker.conf` and `systemctl restart
   omamobile-speaker-protection`.

   ```sh
   U='U=$(loginctl list-users --no-legend | awk "\$2 != \"root\" {print \$2; exit}"); I=$(id -u $U); as_user() { runuser -u $U -- env XDG_RUNTIME_DIR=/run/user/$I "$@"; }'
   burst() {  # burst FILE SINK-VOLUME: one burst with the DSPs sampled every second
     tools/phone-ssh "$U"'; as_user wpctl set-volume @DEFAULT_AUDIO_SINK@ '"$2"';
       (omamobile-speaker-protection monitor 13 1 > /tmp/mon.txt) & sleep 1;
       as_user timeout 12 pw-play '"$1"'; wait; cat /tmp/mon.txt; dmesg | grep -iE "cs35l41|DSP1" | tail -3'
   }
   tools/phone-ssh 'S=omamobile-speaker-protection;
     $S signal multitone /tmp/mt20.wav --level -20 --seconds 10; $S signal multitone /tmp/mt10.wav --level -10 --seconds 10;
     $S signal multitone /tmp/mtL.wav --level -20 --seconds 5 --channels left; $S signal multitone /tmp/mtR.wav --level -20 --seconds 5 --channels right'
   ```

   - **C9a protection proven, still at C8 levels** (risk low):
     1. Sense paths, read-only, during a 10 s burst (`burst /tmp/mt20.wav
        1.0` in one terminal, and in another, 3 s into it):
        ```sh
        tools/phone-ssh 'for r in /sys/kernel/debug/regmap/spi6.[01]*; do echo $r;
          awk -F": " "{a = strtonum(\"0x\" \$1)} a == 0x2018 || (a >= 0x4c48 && a <= 0x4c58) {print} a > 0x10100 {exit}" $r/registers; done'
        ```
        **Never read past 0x10100** (the awk stops there, as
        `tools/aoc-*-diag` do): the full file goes on into the DSP's
        memories and core registers, and reading them froze the protection
        algorithm of both amplifiers (C9a result below).
        Expect PWR_CTRL2 (2018) bits 12 and 13 set (VMON, IMON on),
        4c48 = 0x18, 4c4c = 0x19 (DSP inputs VMON/IMON), 4c58 = 0x3a
        (TEMPMON). Stop: VMON/IMON off during playback (the model would be
        blind: report).
     2. The burst's `monitor` lines: HALO_STATE 2, CSPL_STATE 0,
        CAL_SET_STATUS 2, the heartbeat moving every second, both
        temperatures near room temperature and within 1 °C of each other,
        SPK_OUTPUT_POWER above zero while it plays.
     3. Tracking: `burst /tmp/mt10.wav 1.0` twice, 5 s apart. Expect the
        coil temperatures to move with the signal (a small rise while it
        plays, back down after), not to sit still. Record the largest rise.
     4. Verify and stamp: start `burst /tmp/mt20.wav 1.0`, and 2 s in:
        `tools/phone-ssh 'omamobile-speaker-protection verify'`. Expect
        "verified: … heartbeat moving, coil temperatures …" and "stamp
        written". Stop: "not verified" (send its reason).
     **C9a result (first run, 2026-10-12, 7.3.0-rc6-omamobile-push1-00306,
     omamobile-audio 0.2.1): stopped at step 3.**
     - Step 1 passed: 0x2018 = 0x3721 (VMON, IMON on), DSP1 RX3-RX7 =
       0x18, 0x19, 0x28, 0x29, 0x3a on both amplifiers.
     - Step 2: state 0, HALO_STATE 2, CAL_SET_STATUS 2, errorno 0,
       25.00-25.02 °C, maximum excursion 0.28 mm top / 0.45 mm bottom, the
       heartbeat moving about 1500 a second (the firmware's 32-sample audio
       blocks). Then the top heartbeat stopped about 5 s into the burst and
       the bottom one about 3 s later, while the stream still ran.
     - Step 3: through both -10 dBFS bursts every DSP value stayed frozen
       (heartbeat, temperature, excursion), state still 0, and both bursts
       were clearly audible. At the stream stops only the bottom amplifier
       logged a failed pause.
     - **Cause: step 1's `grep` over the whole regmap `registers` file.**
       The file lists every readable register, which for this driver goes
       on past the amplifier's registers into the DSP's XM, YM and program
       memories and its core registers (all readable and volatile in
       `cs35l41-lib.c`). A read reads the hardware, the top amplifier's file
       first, then the bottom's: the two stops are seconds apart in that
       order, about the time each read takes to get there. Reading the
       DSP's memories and core registers while it runs stopped its
       algorithm. The firmware still answered the mailbox, and audio still
       passed. So the speakers played **unprotected** from then on. Our
       control reads were not stale: these controls are volatile in the
       regmap and the driver reads the DSP while it runs, which is why the
       values moved until the freeze. The fix is the step's command: never
       read past 0x10100 while a DSP runs. Recovery: `systemctl restart
       omamobile-speaker-protection` (it rebinds the amplifiers, which
       resets the chips).
     - **The watchdog did not mute: by our design.** In stage c8 a stuck
       heartbeat was only logged, once. 0.2.2 mutes on it in every stage,
       within about 2 s of the last change (2 s grace at stream start); only
       `OMAMOBILE_SPK_HEARTBEAT=0` turns it back into a log line, and not in
       c9. Its test reproduces C9a's case (moving, then frozen mid-stream).
     - **Power 0** is real resolution, not a decoding error: one count of
       SPK_OUTPUT_POWER is about 80 µW on the stock HAL's scale, and at
       digital 657 / analog 6 with a -20 dBFS signal the output is around
       tens of µW. It should read non-zero from the louder C9d steps.

     **C9a, second run** (omamobile-audio 0.2.2; `systemctl restart
     omamobile-speaker-protection` first, so both DSPs start fresh): steps
     1 (with the bounded read), 2, 3 and 4 as above, with `monitor` running
     through all three bursts. Expect the heartbeat to keep moving through
     every stream (about 1500 a second, also in the silence PipeWire plays
     after a file ends) and the watchdog to stay quiet. Then a check for
     false mutes: real media in Chromium, paused and resumed a few times
     over a minute; PipeWire keeps the PCM running with silence or closes
     it, and in both cases the watchdog must not mute. Stop: any mute with
     "HALO_HEARTBEAT stuck" (send the watchdog journal and the `monitor`
     lines), or a heartbeat that stops while `monitor` says RUN.

   - **C9b the stock media delta, at C8 levels** (risk low-medium: the
     first write into the protection firmware's parameters; listening):
     1. `burst` a piece of real music the human chooses (copied to the
        phone, `timeout 12`) and the multitone at 1.0, delta off. Note how
        the top and bottom sound.
     2. Turn it on and restart:
        ```sh
        tools/phone-ssh 'echo OMAMOBILE_SPK_MEDIA_DELTA=1 >> /etc/omamobile/speaker.conf; systemctl restart omamobile-speaker-protection; sleep 3; omamobile-speaker-protection status | head -1'
        ```
        Then the same bursts. Expect in `journalctl -u
        omamobile-speaker-watch -b` "Top: stock media delta applied" and the
        same for Bottom about 2 s into each stream, CSPL_STATE 0 throughout,
        and a change in the top speaker's sound (less "telephone"). Stop: a
        watchdog mute ("no media delta", "CSPL_UPDATE_PARAMS_CONFIG is N
        bytes", "CSPL_STATE not running"): report it, set the switch back to
        0. If nothing changes by ear, keep it on anyway (it is what stock
        does) and record that.
   - **C9c the kernel's limit for stock gains** (risk low; ask before the
     reboot):
     ```sh
     tools/phone-ssh 'echo "options aoc_alsa_dev speaker_protection=1" > /etc/modprobe.d/omamobile-audio-c9-bringup.conf'
     # reboot, then:
     tools/phone-ssh 'cat /sys/module/aoc_alsa_dev/parameters/speaker_protection; dmesg | grep aoc_speaker_limits; omamobile-speaker-protection status | head -4'
     ```
     Expect `Y`, the Analog limit lines saying 17, and the service still at
     stage c8 levels (657, top 6, bottom 6). When C9 passes, the option
     moves into the package and this file is deleted (AGENTS.md).
   - **C9d stepping up** (risk **medium-high**: louder than anything so
     far; the human holds the phone at arm's length or lays it on a table
     screen up; announce every step). Each step: write the levels, restart
     the service, check status, then `burst /tmp/mt20.wav 1.0`, 60 s rest,
     `burst /tmp/mt10.wav 1.0`, 60 s rest, recording each burst's
     `monitor` lines. Stage c9 needs the stamp from C9a.4 and C9c's `Y`.
     ```sh
     step() {  # step DIGITAL ANALOG
       tools/phone-ssh "printf 'OMAMOBILE_SPK_STAGE=c9\nOMAMOBILE_SPK_MEDIA_DELTA=1\nOMAMOBILE_SPK_DIGITAL=$1\nOMAMOBILE_SPK_ANALOG=$2\n' > /etc/omamobile/speaker.conf;
         systemctl restart omamobile-speaker-protection; sleep 3; omamobile-speaker-protection status | head -1; systemctl is-active omamobile-speaker-watch"
     }
     step 657 10;  step 737 10;  step 817 10;  step 817 13;  step 817 17
     ```
     (737 = -10 dB; 817 = 0 dB; analog 17 = 17.5 dB, stock.) Expect at
     each step a louder but clean sound, CSPL_STATE 0, no over-counts, the
     temperature rise per 10 s burst staying small (record it; the largest
     at 817/17 is the baseline for later), and CSPL_ATTENUATION at its idle
     value at least through -20 dBFS. Stop as in the rules; on a stop,
     go back to the previous step's levels.

     **C9a-C9d results (2026-10-12, 7.3.0-rc6-omamobile-push1-00306,
     speaker_protection=1, omamobile-audio 0.2.2, media delta on).**
     - C9a second run passed: the heartbeats moved through every burst, and
       `verify` wrote the stamp. Real media with pauses gave no false mute.
     - C9b: the delta was applied on both amplifiers, and both speakers play.
     - C9c: `Y`, analog limit 17.
     - C9d step 1 (657/10): largest coil temperature rise 0.07 °C.
     - C9d step 2 (737/10): at -20 dBFS, top +0.13 °C and bottom +0.06 °C;
       at -10 dBFS, top +0.43 °C and bottom +0.17 °C. Clean.
     - **C9d step 3 (817/10) stopped.** In the first -20 dBFS burst the
       readings (top/bottom, °C) went 25.0/25.0 → 57.2/40.0 within the
       first second → 66.6/42.0 → 71.3/43.6 → 74.9/44.5 → 77.0/44.8 →
       78.0/45.4 → 79.9/45.8. They then **fell while the burst still
       played** (77.6, 75.4, … 69.4 on the top; 45.4 … 43.6 on the bottom).
       State 0, errorno 0, no over-temperature or over-excursion counts.
       The watchdog's backstop muted at "Top: coil temperature 80.1 above
       80.0 C", so the next burst played into muted amplifiers.
     - By ear (the human): "loud, not too distorted, a little scratchy". The
       phone was only slightly warm afterwards, which fits a day on charge
       with the screen on; nothing stood out near the earpiece.
     - Physically implausible. A coil does not gain 32 °C in one second at
       -20 dBFS and then cool under the same drive. Step 2's -10 dBFS bursts
       (737/10) put the same voltage on the speakers as step 3's -20 dBFS
       burst (817/10), and they rose 0.43 °C.

     **What the firmware's own tables and the stock HAL say** (the .wmfw's
     coefficient descriptors; our analysis of `audio_spk_35l41.so`):
     - **Which controls are live.** HALO_STATE, HALO_HEARTBEAT, CSPL_STATE,
       CSPL_ERRORNO, CSPL_TEMPERATURE, CAL_R_SELECTED, CAL_SET_STATUS,
       SPK_OUTPUT_POWER and the BDLOG values are volatile: the DSP updates
       them and we read them live.
     - **Which are settings.** ATTENUATION, REDUCE_POWER, CH_BAL and
       CAL_AMBIENT are host-written, so reading them only returns what was
       written. ATTENUATION is therefore not a measurement: our "None" was
       a wrong name, and the value would mean nothing anyway. It is gone
       from `monitor`. SPK_OUTPUT_POWER is live, so its 0 is what the
       firmware reports. `monitor` now prints it raw.
     - **Calibration.** Stock writes CAL_R, CAL_STATUS, CAL_CHECKSUM and
       CAL_AMBIENT, each a big-endian 32-bit word copied from the record
       unchanged, in that order. We write the same words; only our order
       differs (ambient first, as mainline cs-amp-lib does). Stock then
       checks CAL_SET_STATUS (2), which we saw too.
     - **The record's last two words** are the analog gain (17) and digital
       volume (817) at which the factory calibration was taken. The HAL
       only prints them. Stock always plays media at exactly those gains.
     - **Other DSP controls stock writes for media:** CH_BAL (when it swaps
       left and right for orientation) and ENABLE_FULL_US_BYPASS. Neither
       is a gain or a model parameter. The amplifier gains themselves come
       only from `mixer_paths.xml`.
     - **Two more live values worth watching.** BDLOG_VMON_LOW_FLAG: the
       firmware logs when the voltage sense is too low to use. And
       CAL_R_SELECTED: the coil resistance the model is actually using.
       `monitor` 0.2.3 shows the flag, and whether CAL_R_SELECTED equals
       the CAL_R we wrote ("R_selected=CAL_R yes/NO"; never the values).

     **Reading.** Below some level the model has too little sense signal to
     measure the coil. It holds 25 °C plus a small power-based rise, as in
     steps 1-2. At step 3 it began estimating temperature from the measured
     resistance against CAL_R, and the estimate came out high (top +55 °C,
     bottom +20 °C), then drifted. Candidates, most likely first:
     1. **The model assumes stock's gains (17 / 817), the conditions of the
        factory calibration and of every stock media stream.** At step 3
        the digital volume matched stock but the analog gain was 10, 7 dB
        below what the model expects. If any part of the estimate uses the
        expected rather than the measured voltage, a gain mismatch shows up
        as a resistance error. That could also explain why step 2 (digital
        737, 10 dB off) never left the hold state (VMON "low" relative to
        expectation).
     2. **The test signal.** The multitone has nothing below 300 Hz (our
        safety rule), so the resistance estimate works where the speaker's
        impedance is well above its DC resistance (inductance, and the
        small top speaker's resonance). That would read high, more on the
        top than the bottom, as seen.
     3. **The media delta** changes model parameters. It was on in every
        step, so these results can't separate it.
     The calibration itself is not the suspect: CAL_SET_STATUS 2 on both;
     C8c's 25.0 °C agreement on both amplifiers; the same words as stock.
     CAL_R_SELECTED will confirm the model uses it. "A little scratchy" may
     be the multitone itself, or the protection starting to act on the
     false temperature; C9d-2 checks with a pure tone.

   - **C9d-2 the temperature reading** (omamobile-audio 0.2.3; stage c9;
     nothing above 737 digital until this is explained; each burst ≤ 10 s
     with 60 s rest; stop as in the C9 rules, and on any reading above
     45 °C). The order changes one thing at a time; record each burst's
     `monitor` lines, including "R_selected" and "vmon low".
     1. Install 0.2.3 (`tools/phone-install-package packages/omamobile-audio;
        tools/phone-ssh 'systemctl restart omamobile-speaker-protection'`).
        Then a pure tone at C8 levels (657/6), delta on, then delta off
        (set `OMAMOBILE_SPK_MEDIA_DELTA=0` and restart). Use `signal tone
        /tmp/t1k.wav --level -23 --seconds 3`, a -20 dBFS peak. Listen for
        scratchiness. Expect clean in both.
     2. 737/10, delta **off**: `burst /tmp/mt10.wav 1.0`, then a 1 kHz tone
        at -13 dBFS RMS. Expect the step-2 behaviour (≤ 0.5 °C, vmon low
        possibly set). This repeats step 2 without the delta.
     3. **The gain question, at lower output than step 3:** 657/17 (stock
        analog gain, digital -20 dB), delta off. Its output is 13 dB below
        step 3's (-20 dB digital, +7 dB analog). Then 737/17 (3 dB below
        step 3). Multitone at -20 dBFS, then the tone. If the reading stays
        near room temperature at 737/17 while 817/10 jumped, the model
        wants stock's analog gain (candidate 1). If 737/17 also jumps by
        tens of degrees, stop: the signal or the delta is next.
     4. Only if 3 points at the gain: the same at 737/17 with the delta
        on (candidate 3).
     5. Report the lines. The next step is decided then: 817/17 (stock) only
        once a burst at 737/17 reads plausibly (within a few °C, rising and
        falling with the signal) with "R_selected=CAL_R yes" on both
        amplifiers.
     Rollback for every step: `omamobile-speaker-protection mute`, stage c8
     levels in `/etc/omamobile/speaker.conf`, restart.

     **C9d-2 result (2026-10-12, 7.3.0-rc6-omamobile-push1-00317-gdea700f6eec2,
     omamobile-audio 0.2.3, speaker_protection=1).**
     - Step 1: the 1 kHz tone at 657/6, delta on and then off, was clean
       both times (no scratchiness). R_selected=CAL_R yes on both
       amplifiers, vmon low 1 on both, 25.00-25.02 °C, state 0, halo 2,
       cal 2, power raw 0.
     - Step 2 (737/10, delta off): mt10 top 25.00 → 25.43 °C, bottom → 25.17;
       the 1 kHz tone at -13 dBFS top → 25.36, bottom → 25.15. vmon low 1
       every second on both. By ear: "loud and sounded good", "okay".
     - Step 3a (657/17, delta off), mt20: the **top showed vmon low 0 every
       second (sensing active)** and read a plausible 25.01 → 25.23 °C. The
       bottom stayed at vmon low 1, 25.00 → 25.12. By ear: "quieter but
       staticky". The run stopped there: the tone at 657/17 and 737/17
       never ran.
     - **Reading.** The firmware senses the coil only when the amplifier's
       analog gain is near what its tuning expects. At analog 10 it never
       sensed, even at the step-2 level that equals step 3's output. At
       analog 17 the top sensed at a 13 dB lower output, and read
       plausibly. So C9d's 80 °C came from sensing at 817/10, off the gain
       the model expects. Candidate 1 holds: the model wants stock's
       analog 17. The calibration is fine (R_selected = CAL_R).

     **Everyday level until stock's gains: stage `media`, 737/10 on both,
     media delta on (omamobile-audio 0.3.0, the new default).**
     - Inside AUDIO-PLAN.md section 4's limits even with the DSP bypassed
       (digital ≤ 817, analog ≤ 10). It is 17 dB below stock's media
       output (817/17.5 dB), about 1/50 of the power.
     - For the top amplifier (the earpiece) it is 7 dB below stock's
       in-call earpiece level (full-scale voice at 7.5 dB, DSP bypassed).
     - **What protects the speakers at this level.** The firmware does not
       sense the coil here (vmon low 1), so its thermal estimate runs from
       the signal alone, without the resistance check. Its excursion
       limiter, feed-forward from the signal, still runs. Both assume
       stock's analog gain, so they overestimate the real output by 7 dB
       and err on the safe side.
     - **What the watchdog guarantees.** Both DSPs run the protection
       firmware with the calibration applied: heartbeat, state, error,
       CAL_SET_STATUS.
     - **The honest residual risk.** If the firmware's open-loop model were
       wrong for this speaker, nothing would catch slow overheating at
       sustained full volume. The power is so far below stock's
       sustained-music levels that this is unlikely to matter. Low risk;
       the human chose it by ear.
     - **Stage c8** (657, analog 6 top) stays for bring-up. **Stage c9**
       (stock) needs the stamp and `speaker_protection=1`, as before.
     - **The media delta** is on by default whenever its two files are
       installed.

     **The static at 657/17.** At -20 dB digital and +17.5 dB analog the
     signal reaches the DAC 20 dB lower than at stock's 817/17. Everything
     after the digital volume is then amplified 7 dB more than at analog
     10: the amplifier's own noise and the DSP output's low-level noise.
     That is hiss heard as "static", and it shrinks as the digital level
     goes up: at 737/17 by 10 dB, at 817/17 by 20 dB.
     - Stock also runs **DRE** (dynamic range enhancement, "DRE DRE Switch"
       1 at init in `mixer_paths.xml`). DRE lowers the amplifier's noise
       floor on quiet passages; we leave it off.
     - omamobile-audio 0.3.0 can turn it on (`OMAMOBILE_SPK_DRE=1`, default
       off); C9d-3 compares.
     - If static remains at 817/17 with DRE on and real music, it is not
       noise floor. The amplifier's hardware noise gate (stock DT:
       `hw-noise-gate-select = 63`) and the protection's own actions are
       next.

   - **C9d-3 to stock gains with sensing** (omamobile-audio 0.3.0; stage
     c9; rules as in C9; stop at any reading above 45 °C, a jump of more
     than 5 °C within a burst, vmon low 1 at analog 17 during a -20 dBFS
     burst on either amplifier, or R_selected NO):
     0. Install and restore the default config (risk low):
        ```sh
        tools/phone-install-package packages/omamobile-audio
        tools/phone-ssh 'cp /etc/omamobile/speaker.conf.pacnew /etc/omamobile/speaker.conf 2>/dev/null; grep -v "^#" /etc/omamobile/speaker.conf; systemctl restart omamobile-speaker-protection; omamobile-speaker-protection status | head -1'
        ```
        Expect "ok: stage media … Top 737/10, Bottom 737/10" and, at the
        next stream, "stock media delta applied" twice in the watchdog
        journal. This is the everyday level from now on.
     1. The rest of C9d-2 step 3, delta off, DRE off: 657/17 with the 1 kHz
        tone at -13 dBFS RMS, then 737/17 with mt20, mt10 and the tone.
        Expect vmon low 0 on both amplifiers at least at 737/17, R_selected
        yes, and temperatures that rise by tenths of a degree with the
        signal and fall back after.
     2. DRE: 737/17 with mt20 and real music, `OMAMOBILE_SPK_DRE=1` versus
        unset. The human listens for static, and the monitor lines must
        stay as in 1.
     3. 737/17 with the media delta on (unset `OMAMOBILE_SPK_MEDIA_DELTA`
        or set it to 1). Same expectations.
     4. 817/17, delta on, DRE as chosen in 2: mt20, then mt10, then real
        music at 50/75/100 % sink volume, each ≤ 10 s, 60 s apart, with
        monitor. Expect sensing on both, plausible temperatures and no
        over-counts. This is stock's media setting.
     5. Then C9e (balance) and C9f (real use) at 817/17. If both pass, make
        c9 at 817/17 the package default, and move
        `options aoc_alsa_dev speaker_protection=1` into the package.
     Rollback for every step: `omamobile-speaker-protection mute`, then the
     default config (stage media) and a restart.
     **C9d-3 step 1 result (2026-10-13, 7.3.0-rc6-omamobile-push1-00375-gc73a652bd07a;
     stopped):**
     - 657/17, delta off, DRE off: a -20 dBFS multitone burst and a
       -13 dBFS RMS 1 kHz tone read plausibly (top +0.4 °C, bottom
       +0.2 °C, falling back afterwards). But vmon low stayed 1 on both
       amplifiers throughout. R_selected was CAL_R yes, with no over-counts.
     - 737/17, -20 dBFS multitone: **stop.** The top read 25 → 65 → 85 → 93 °C
       (maximum) within 6 s and the bottom 25 → 43 °C. vmon low was still
       1. The watchdog muted at 08:24:21, as designed. The listener heard
       the tones with **a lot of background static** (as at 657/17 on
       2026-10-12).
     - Reading: vmon low 1 at analog 17 contradicts C9d-2. The temperature
       runs away as at 817/10, and static comes with gain 17. Sensing and
       the analog stage at gain 17 are not configured as on stock; the
       coils are not really hot.
     - **Next:** offline, compare the amplifiers' configuration at gain 17
       with stock: the boost target and peak current, VMON/IMON enables,
       the ADC and the class-H settings. Use the stock tuning and our own
       register captures. No more listening steps at analog 17 until that
       difference is found. The default stays stage media 737/10.
     **C9d-4 step 1 (2026-10-13, 7.3.0-rc6-omamobile-push1-00395-g6c0e876bd580;
     stopped):** this tested whether the runaway comes from our post-DSP gain
     differing from stock's. Both amplifiers were at stock's 817/17, with
     the level taken down in the file instead: a -40 dBFS multitone at sink
     1.0, the same speaker voltage as 657/17 with mt20. **It still ran away:**
     the top read 25 → 50 → 61 → 69 → 77 °C (maximum 83) in 8 s, and the
     bottom 25 → 43 °C, with vmon low 1 on both throughout. R_selected
     stayed CAL_R yes, and there were no over-counts. The listener heard
     static again. The watchdog didn't mute, because the live reading
     peaked at 77 °C, under its 80 °C limit.
     - So the gain-mismatch theory is disproved: at analog gain 17 the
       voltage sense is wrong whatever the signal level.
     - A -23 dBFS tone at the default 737/10 right after was clean.
     - Next (offline): what changes with gain 17 on our setup, such as
       boost headroom and target, the class-H mode, the RX6 source, and the
       VMON/IMON ranges.
     - Also lower the watchdog's limit so that it acts on a jump, not only
       on 80 °C.
     **C9d-5 and the bottom speaker's static (2026-10-13, same kernel):**
     - **Channel check at 737/10:** a left-only multitone (top earpiece)
       sounded clean; a right-only multitone (bottom loudspeaker) had static.
       The static is on the bottom path at the everyday level too.
     - **The bottom amplifier with its DSP bypassed** (`PCM Source` ASP,
       watchdog paused, 737/10, the top muted) still had "a tiny bit of
       static", less than through the DSP. With the watchdog running, the
       first attempt muted both amplifiers at once ("PCM Source is ASP, not
       DSP"), as designed.
     - **DRE on and the hardware noise gate at 63**, as stock, through the
       DSP at 737/10: clearly cleaner by ear. Both are now the default
       (omamobile-audio 0.3.2).
     - **817/17 with DRE and the gate on:** a -40 dBFS multitone tripped a
       1 s tripwire (more than 5 °C above the start) within a second: top 25
       → 56 °C. A -40 dBFS 1 kHz tone did the same (top 25 → 55.5 °C). So
       the runaway at stock's level doesn't depend on the signal's
       spectrum, and DRE and the gate don't affect it. Both tunings are the
       stock files: top "EVT1p1 top tune", bottom "DVT bot tune", the same
       as the factory image's `cs35l41-dsp1-spk-prot.bin` and
       `R-cs35l41-dsp1-spk-prot.bin`. Routing (EP6 → TDM_0, left in slot 0
       = top, right in slot 1 = bottom) and DSP RX1/RX2 = ASPRX1 match
       stock.
     - **Open:** why the protection's reading runs away at gain 17 on our
       setup. Next suspects are the VMON/IMON scaling the DSP sees and the
       amplifiers held awake.
     - **Meanwhile:** omamobile-audio 0.3.3 adds a PipeWire loudness filter
       ahead of the DSP: a 150 Hz high-pass and a limiter with +6 dB and a
       -1 dBFS ceiling. The amplifiers stay at 737/10.
     **C9d-6 (2026-10-13, 7.3.0-rc6-omamobile-push1-00405-g3bc8d8565645):**
     - **The bottom speaker's static is fixed.** The cause was `SP_RX_WL`
       (0x4840) read back 32, but that field takes 12-24 bits. Mainline
       wrote `params_width()`, while Google's driver caps it at 24.
       omamobile-audio-amp `cb1ae8c7d` programs the slot width from the
       physical width and caps the word length at 24. A right-only multitone
       at 737/10 "sounded much better" to the listener.
     - **The runaway at 817/17 remains.** A -40 dBFS 1 kHz tone with a
       0.5 s tripwire tripped at once: top 25 → about 50 °C at the first
       sample, bottom 25 → 36 °C, vmon low 1. With `dsp_rx6_classh=Y`
       (`9fcc941b3`, the class-H target into DSP RX6 as stock) and a
       service restart it tripped the same way. It isn't known whether the
       parameter took effect without a firmware reload.
     - The first sample already reads about 20 % high, so a scaling
       mismatch is the lead. The default stays 737/10.
     - omamobile-audio 0.3.5: the watchdog also mutes on a rise of more
       than 5 °C within a stream (`OMAMOBILE_SPK_TEMP_JUMP`).

   **Why the speakers sound thin, and the plan (2026-10-13, offline;
   omamobile-audio 0.4.0).** The listener: the speakers work but sound
   tinny next to a stock Pixel. In order of expected effect:
   1. **Stock shapes the speaker signal on the AoC (Waves), and we send
      none of it.** That processing is stock's sound: EQ, bass
      enhancement, loudness. Our path is flat apart from our own filter.
      The package exists (omamobile-speaker-tuning 0.1.2, off); the next
      steps are T3b and T4 in `AOC-TUNING-RESEARCH.md`, now at the
      everyday level (737/10) with our filter set flat for the comparison.
      This is the only lever that gives stock's sound itself.
   2. **Level.** Media plays about 17 dB below stock. The ear hears bass
      and the low mids least at low levels, so the same speakers sound
      thinner the quieter they play. Stock's level needs the gain-17
      runaway solved: C9d-7 and C9d-8 below.
   3. **Our filter.** 0.3.3-0.3.5 high-passed at 150 Hz (2nd order) with no
      other shaping. The cut itself removed little these speakers can
      play, but nothing compensated their steep low-frequency roll-off.
      0.4.0 replaces it (C9g below): a 100 Hz high-pass, a +4 dB low shelf
      at 400 Hz, a -2 dB presence dip at 3.5 kHz, per-channel treble and
      trim, and the same limiter (-3 dBFS, no gain), all adjustable while
      playing (`omamobile-speaker-eq`). The values are a starting point.
      C9g measures the speakers with the phone's own microphone and sets
      them by ear.
   4. **Balance.** Stock maps left to the top speaker (the earpiece, small,
      little bass) and right to the bottom one, at equal gains. Measured
      balance and per-speaker trims belong to C9e, now in software
      (`trim_top`, `trim_bottom`; cuts only) instead of the amplifier
      levels.

   **C9d-7 and C9d-8: the gain-17 runaway (design and helpers, 2026-10-13,
   offline).** Two things we don't do that stock does at every speaker
   stream, from our analysis of the stock speaker library (in our own words):
   - **C9d-7, the V/I feedback stream.** When the speaker use case starts,
     stock applies `hostless-ulC spk-vi` (`NoHost1 TX Mixer TDM_0_TX` 1),
     then opens and starts PCM 15 (`UC_HOSTLESS_UL`, "nohost1 capture")
     for capture: 2 channels, 48 kHz, S16_LE, 2 periods of 480 frames. It
     never reads from it. At the end it closes the PCM and resets the path.
     That runs TDM 0's transmit side, so both amplifiers send VMON/IMON to
     the AoC. omamobile-audio 0.4.0 does the same:
     `omamobile-speaker-protection feedback start|stop|status`, or the
     watchdog with every stream when `OMAMOBILE_SPK_FEEDBACK=1` (default
     off). It refuses unless both amplifiers' DT nodes carry disjoint
     `google,tdm-tx-slots` (the aoc-sound-test overlay, stock's 0/2/4/6 and
     1/3/5/7), because the two share one SDOUT line. arecord can't hold
     this PCM: no data ever arrives, and ALSA fails a blocking read after
     10 s. So a small alsa-lib holder starts it without reading, as stock
     does.
   - **C9d-8, the firmware's own impedance reading.** Stock arms the
     protection firmware's real-time logger at every speaker stream: 3
     firmware variables, count 3, enable. It then takes five samples about
     0.2 s apart: `RTLOG_STATE` := 0, wait for 1, read `RTLOG_DATA`. Word 1
     is the coil impedance the firmware measures from its voltage and
     current sense, in CAL_R's units. 0xfffffd and 0xfffffe mean no valid
     measurement, as at a signal too low to measure. Stock keeps the median
     as a metric only. `omamobile-speaker-protection impedance` does the
     same and prints only Z/CAL_R and the coil rise that ratio means
     (copper, 0.39 %/°C), never a resistance. At gain 17 the first
     temperature sample read about 25 °C high, which matches a Z/CAL_R near
     1.10. This step tells whether the firmware really measures a 10 %
     higher V/I at gain 17 (sense scaling) or not (the model's inputs).
   - Nothing else stock writes at stream start could plausibly change the
     sensing. CH_BAL and rotation are for four-amplifier devices only. The
     ultrasound configuration isn't on cheetah's paths. Hibernate Force
     Wake only controls hibernation, and AMCS is telemetry.

   **C9d-7/C9d-8 runbook** (omamobile-audio 0.4.0; the TX slot overlay in
   the DTB; rules as C9d-6: the phone screen up on a table, the human told
   before each burst, `tools/speaker-trip-burst` with RISE 5, 30 s between
   bursts). Stop on TRIPPED, any watchdog mute, R_selected NO, over-counts
   that move, or anything the listener dislikes. Rollback for every step:
   `omamobile-speaker-protection feedback stop; omamobile-speaker-protection
   mute`, then `lvl 737 10 media`.
   ```sh
   lvl() { tools/phone-ssh "printf 'OMAMOBILE_SPK_STAGE=${3:-c9}\nOMAMOBILE_SPK_DIGITAL=$1\nOMAMOBILE_SPK_ANALOG=$2\nOMAMOBILE_SPK_TEMP_JUMP=5\nOMAMOBILE_WATCH_INTERVAL=0.5\n' > /etc/omamobile/speaker.conf; systemctl restart omamobile-speaker-protection; sleep 3; omamobile-speaker-protection status | head -1"; }
   tb() { tools/phone-ssh "F=$1 S=${2:-5} VOL=1.0 RISE=5 IMP=${IMP:-0} FB=${FB:-0} bash -s" < tools/speaker-trip-burst | tee -a logs/c9d7.log; }
   tools/phone-ssh 'S=omamobile-speaker-protection;
     $S signal tone /tmp/t1k30.wav --level -30 --seconds 3; $S signal tone /tmp/t1k23.wav --level -23 --seconds 3;
     $S signal multitone /tmp/mt20.wav --level -20 --seconds 3'
   ```
   | Step | What | Risk | Pass | Stop |
   | --- | --- | --- | --- | --- |
   | 0 | **Read-only, no sound:** `tools/phone-ssh 'uname -r; omamobile-speaker-protection feedback status; amixer -c0 controls \| grep -c RTLOG'` | none | "TX slots ok", hostless PCM device 15 (closed); 10 RTLOG controls (5 per amplifier) | TX slots not ok (the overlay is missing: stop, it needs its own boot) |
   | 1 | **The feedback stream alone, no playback:** `tools/phone-ssh 'S=omamobile-speaker-protection; $S feedback start --seconds 5; sleep 1; $S feedback status; sleep 6; $S feedback status; dmesg \| tail -5'` | low | "holder pid …", PCM "state: RUNNING", then "not running"; no AoC or cs35l41 error | an oops, an AoC or amplifier error, a PCM that stays open |
   | 2 | **The impedance at the everyday level** (737/10, the current default): `IMP=1 tb /tmp/t1k23.wav 3`, then `IMP=1 FB=1 tb /tmp/t1k23.wav 3`. If both say "not measurable", the same with `/tmp/mt20.wav` | low | Z/CAL_R 0.97-1.05 on both, or "not measurable" (record which); CLEAN | Z/CAL_R off by more than 10 % at 737/10 |
   | 3 | **Gain 17, one 1 s burst, feedback off:** `lvl 817 17; IMP=1 tb /tmp/t1k30.wav 1`, then `lvl 737 10 media` | medium | CLEAN, Z/CAL_R near 1.00 | TRIPPED (expected, as in C9d-5/6): record Z/CAL_R or "not measurable" and go on to 4 |
   | 4 | **Gain 17 with the feedback stream:** `lvl 817 17; IMP=1 FB=1 tb /tmp/t1k30.wav 1`, then `lvl 737 10 media` | medium | CLEAN where 3 tripped: C9d-7 is the fix | TRIPPED again: stop listening steps, send the lines |

   A -30 dBFS 1 kHz tone at 817/17 is well under 10 mW in either speaker,
   for 1 s, so a coil cannot really heat. The tripwire and the watchdog's
   5 °C jump rule stay armed regardless.

   Reading 3 and 4:
   - **Z/CAL_R near 1.10 at gain 17, near 1.00 at gain 10:** the firmware
     really measures a higher V/I at gain 17. Then the sense path's
     scaling depends on the gain on our setup. Next, offline: the
     amplifiers' VMON/IMON configuration at gain 17 against stock's.
   - **"Not measurable" at gain 17 while the temperature still jumps:**
     the sensing isn't used, and the model's open-loop estimate is what
     runs away. Suspect its inputs (the tuning's expected gain, the media
     delta, the class-H input on DSP RX6).
   - **Z/CAL_R near 1.00 and the temperature still jumps:** the
     temperature isn't computed from that impedance. Suspect CAL_AMBIENT or
     the calibration's own gain fields.
   - **4 CLEAN:** set `OMAMOBILE_SPK_FEEDBACK=1` in
     `/etc/omamobile/speaker.conf`, then run C9d-3 step 4 (817/17, mt20,
     then mt10, then music at 50/75/100 %, each burst ≤ 10 s through `tb`,
     `IMP=1`). With the C9 rules met, C9e and C9f follow, and the package
     default changes in its own version bump.

   **C9g: the speaker filter, by ear and measured (omamobile-audio 0.4.0;
   risk low).** The amplifiers stay at stage media (737/10) throughout;
   only the signal into the protection DSP changes. The limiter still caps
   it at -3 dBFS. `omamobile-speaker-eq` runs as the desktop user:
   ```sh
   U='U=$(loginctl list-users --no-legend | awk "\$2 != \"root\" {print \$2; exit}"); I=$(id -u $U); as_user() { runuser -u $U -- env XDG_RUNTIME_DIR=/run/user/$I "$@"; }'
   eq() { tools/phone-ssh "$U; as_user omamobile-speaker-eq $*"; }
   ```
   0. Install, then restart the user's PipeWire. Announce it: the sound
      changes, with more low end.
      ```sh
      tools/phone-install-package packages/omamobile-audio
      tools/phone-ssh "$U"'; as_user systemctl --user restart pipewire pipewire-pulse wireplumber; sleep 3; as_user omamobile-speaker-eq show'
      ```
      Expect: the filter's node and the package values (hp 100 Hz, bass
      +4 dB at 400 Hz, dip -2 dB at 3500 Hz, treble 0, trims 0). Stop: "no
      effect_input.omamobile_speaker_loudness node". Send `journalctl
      --user -u pipewire -b | tail` (as the user). Rollback: reinstall
      0.3.5.
   1. **A/B by ear** with music the listener knows, at their normal
      volume. Run `omamobile-speaker-protection monitor 120 2` in a second
      terminal. Switch every 15-20 s and tell the listener which is which
      only afterwards: `eq preset flat`, `eq preset default`, and 0.3.5's
      sound `eq set hp=150 bass=0 dip=0`. Then vary one thing at a time:
      `eq set bass=2`, `bass=6`, `bass_freq=600`, `dip=-4`,
      `treble_top=-3`. Pass: the listener prefers a setting clearly. The
      monitor shows temperatures moving by tenths of a degree and no
      over-count changes. Stop: distortion, rattle or pumping on bass-heavy
      music (`eq set bass=2`, or `eq preset flat`).
   2. **Measure** (two runs of about 15 s of stepped tones at -30 dBFS,
      100 Hz-16 kHz, one speaker at a time; tell the listener first):
      ```sh
      eq measure right --out /tmp/resp; eq measure left --out /tmp/resp
      tools/phone-ssh 'python3 -I /usr/lib/omamobile-audio/speaker_response.py suggest /tmp/resp/left-result.json /tmp/resp/right-result.json'
      ```
      The filter is flat during the tones and restored afterwards. Record
      the printed responses (a frequency-and-level table, no identifiers),
      each speaker's -12 dB corner and the suggestion. The phone's
      microphone sits beside the bottom speaker, so treat its balance
      figure as a rough guide. C9e settles balance by ear. Stop: "CLIPPED"
      (repeat with `--level -40`) or "no 1 kHz marker" (check the default
      source with `wpctl status`).
   3. **Apply the suggestion and A/B it** against `preset default`. Fine-
      tune by ear. With the listener's choice, `eq set … --save` keeps it
      for them. Record the values here. The next omamobile-audio version
      takes them as the package's defaults.
   4. **Full volume with the chosen values:** bass-heavy music at 100 %
      sink volume for 30 s, the monitor running. Pass: nothing the
      listener dislikes; temperatures within tenths of a degree; no
      over-exc count change. Stop: over-exc count moves (lower `bass` by
      2 dB, repeat).
   Rollback: `eq reset` (the package's values), or `eq preset flat`.

   **0.4.0 reviewed offline, and what 0.4.1 changes (2026-10-13; no phone).**
   The graph was loaded and run in a private PipeWire 1.6.8 instance on the
   laptop (its own runtime directory, no ALSA, the limiters replaced by
   `copy` because swh-plugins isn't installed there), and
   `omamobile-speaker-eq` was driven against it.
   - **Bug: a filter that fails to load stopped PipeWire.** A module in
     `context.modules` without `flags = [ nofail ]` is mandatory, so a
     missing LADSPA plugin or an unknown label would have left the phone
     without any audio (and without PipeWire's video). 0.4.1 marks it
     `nofail`: the speaker then plays unfiltered.
   - **Bug: the filter could be bypassed silently.** If the smart filter's
     target name (`alsa_output.platform-sound-aoc.HiFi__Speaker__sink`,
     never checked on the phone) doesn't match, WirePlumber links streams
     past it, and `eq show` still found the node. `show` now prints where
     the filter's output goes ("in the path" or "NOT in the path").
   - **One stereo-linked limiter** ducked the earpiece whenever the bass
     pushed the bottom speaker into limiting, and with the +4 dB shelf on
     loud masters that is often. 0.4.1 has one limiter per speaker, same
     ceiling (-3 dBFS), same zero gain.
   - **The 2nd-order high-pass** passed the +4 dB shelf's lift down into
     100-200 Hz, where these speakers make almost no sound: limiter work
     and excursion for nothing. 0.4.1 uses a 4th-order Butterworth (two
     stages, same 100 Hz corner).
   - **Measurement:** the sink volume (applied after the filter) was not
     recorded, so a volume change between the two sides skewed the
     balance; a muted sink measured nothing; a failed `pw-play` wasn't
     noticed; a clipped recording still fed `suggest`; the two sides could
     be picked up by different microphone channels; and the balance was
     computed from the phone's own microphone, which sits next to the
     bottom speaker and 15 cm from the top one. 0.4.1 records the volume,
     refuses a muted sink, checks `pw-play`, flags clipping and skips it,
     compares only like with like, and suggests a balance trim only from a
     microphone marked as at the listening position (`--listener`; a
     laptop's, through `measure --play-only`). `suggest` is now per
     speaker (`hp_top`, `bass_bottom`, …), halves treble cuts without a
     microphone calibration (`--mic-cal`, a MEMS capsule reads high above
     about 8 kHz), and proposes a crossover and a harmonics corner.
     `analyze` reports the 2nd and 3rd harmonics per step; `compare`
     prints B minus A per step.
   - **New, all off or neutral by default** (so 0.4.1's default sound is
     0.4.0's with the steeper high-pass and per-speaker limiters):
     - `bassmono=1 xover=HZ`: a 4th-order Linkwitz-Riley crossover; below
       it both channels, summed, go to the bottom speaker only. The
       earpiece can't play that range, and the bottom one then gets all of
       it. Measured in the laptop instance: the bottom output sums flat
       (0.0 dB at every step, 50 Hz-12.8 kHz), the top is a clean
       high-pass (-6 dB at the crossover).
     - `harm=G harm_freq=HZ`: the bass below `harm_freq` is full-wave
       rectified, high-passed at `harm_freq` and low-passed at four times
       it: its 2nd and 4th harmonics, at a level proportional to the bass
       itself (rectifying is linear in level, unlike a polynomial), mixed
       in with gain G. The ear infers the missing fundamental from them. In
       the laptop instance, -20 dBFS tones at 60/80/100 Hz gave even
       harmonics at -11 to -18 dB relative at G=1, no 3rd. Needs
       PipeWire's builtin `abs` (Arch Linux ARM has 1.6.9).
     - `width=W` (portrait: both speakers play some of both channels) and
       `swap=0|1`, with `orient` and `follow`: the input matrix follows
       the phone's orientation as stock swaps left and right in landscape
       (a user unit, `omamobile-speaker-orient`, not enabled). Which
       landscape side swaps (`left-up`, the earpiece on the listener's
       right) is checked by ear in C9h.
     - `drive=DB` (0-6): the limiters' input gain, for loudness at full
       volume. 0.3.3's +6 dB was heard distorted, but that was before the
       word-length fix (C9d-6) and with a stereo-linked limiter; C9h tries
       2-3 dB again.
   - **PipeWire quality.** The AoC's EP6 PCM takes S16, S24, S32 and
     FLOAT; stock's deep buffer plays 48 kHz float. PipeWire picks the
     format itself; C9h reads `hw_params` once during playback. 44.1 kHz
     sources are resampled at PipeWire's default quality, which is not
     audible on these speakers; nothing to change. The sink volume is
     applied after the filter, so the shaping is the same at every volume
     (a volume-dependent loudness contour, as Waves' volume link laws do,
     would need a small daemon feeding the sink volume into the filter:
     later, if C9h's listener wants more bass at low volume only).
   - **Not done, a grey area for the human:** measuring stock's speaker
     response (Waves on) and matching it with our own filter. The tools
     can do it (C9h F); whether to copy a measured stock curve is the
     human's call.

   **The gain-17 runaway: what C9d-7/8 will distinguish, and the prepared
   next step for each outcome** (2026-10-13, offline). What we know: at
   analog 17 the coil reading jumps by about 25 °C at the first sample
   with vmon low 1, at any signal level (-40 dBFS), any spectrum, DRE and
   gate on or off, media delta on or off, and DSP RX6 from VBSTMON or the
   class-H target (that knob is read at probe, and the service's restart
   rebinds the amplifiers, so C9d-6's test did take effect). At analog 10
   it never runs away. A 25 °C jump is what a Z/CAL_R near 1.10 would
   mean (copper, 0.39 %/°C). Google's amplifier driver writes no register
   that bears on the sense path and that mainline leaves alone (compared
   2026-10-13: its extra writes are hibernation trim caching and an
   earpiece/speaker volume ramp); the DSP inputs match stock's except RX6
   (tested).
   | C9d-8 / C9d-7 reading | Meaning | Prepared next step |
   | --- | --- | --- |
   | Z/CAL_R near 1.10 at 817/17, near 1.00 at 737/10 | the firmware really measures a higher V/I at gain 17: the sense path's scale depends on the gain on our setup | a read-only register snapshot (the bounded `awk` of C9a step 1, stop at 0x10100) of both amplifiers during the same -30 dBFS tone at 737/10 and at 817/17; diff the two. Anything besides `AMP_GAIN_CTRL` (0x6c04) that differs is the lead. If nothing else differs, the next comparison needs the same snapshot from stock (a slot A boot: fresh NV backups afterwards, AGENTS.md) |
   | "not measurable" at 817/17 and the reading still jumps | the sense isn't used; the open-loop estimate itself runs away | step 4 (the feedback stream) is the test; if it trips too, repeat C9d-8 at 737/17 with `mt10` (more sense signal): vmon low must go to 0 there; then `OMAMOBILE_SPK_CAL_ORDER=stock` (0.4.1) and one more 1 s burst |
   | Z/CAL_R near 1.00 at 817/17 and the reading still jumps | the temperature isn't computed from that impedance; suspect CAL_AMBIENT, which we write first and stock writes last | `OMAMOBILE_SPK_CAL_ORDER=stock` in `/etc/omamobile/speaker.conf`, `systemctl restart omamobile-speaker-protection`, the same 1 s burst |
   | step 4 CLEAN where step 3 tripped | the V/I stream is what the firmware needs | as written under "Reading 3 and 4" above |
   Whatever the outcome, no step above 1 s at analog 17 until a burst
   reads plausibly, and the default stays stage media.

   **C9h: one listening session for omamobile-audio 0.4.1** (prepared
   2026-10-13; run by the main session with the human listening). The
   amplifiers stay at stage media (737/10) in sections A-D, so every step
   there is inside the levels proven without protection; only the signal
   into the protection DSP changes, and its peaks stay at or below
   -3 dBFS. Sections E and F are optional and need the human's go
   separately. Rules for every sound: the phone screen up on a table, the
   listener at about 40 cm, told before each sound what it will be;
   `omamobile-speaker-protection monitor 600 2` running in a second
   terminal; music the listener knows, copied to the phone as `/tmp/m.flac`
   (bass-heavy) and `/tmp/v.flac` (voice). **Stop** (any step): a
   watchdog mute, an over-count that moves, a cs35l41 error in `dmesg`, a
   coil reading more than 1 °C above room at 737/10, buzzing, rattling,
   distortion or anything the listener dislikes. **Rollback** (any step):
   `eq reset` (the package's values); for the filter as a whole
   `tools/phone-ssh 'mv /usr/share/pipewire/pipewire.conf.d/60-omamobile-speaker-loudness.conf{,.off}'`
   and restart the user's PipeWire (unfiltered, as before 0.3.3).
   ```sh
   U='U=$(loginctl list-users --no-legend | awk "\$2 != \"root\" {print \$2; exit}"); I=$(id -u $U); as_user() { runuser -u $U -- env XDG_RUNTIME_DIR=/run/user/$I "$@"; }'
   eq() { tools/phone-ssh "$U; as_user omamobile-speaker-eq $*"; }
   play() { tools/phone-ssh "$U; as_user wpctl set-volume @DEFAULT_AUDIO_SINK@ ${2:-0.6}; as_user timeout ${3:-20} pw-play $1"; }
   R=packages/omamobile-audio/lib/speaker_response.py
   lrec() {  # lrec left|right: the phone plays the stimulus, the laptop's microphone records it
     pw-record --rate 48000 --channels 1 --format s16 logs/resp-$1.wav & P=$!; sleep 1
     eq measure $1 --play-only --out /tmp/resp; sleep 1; kill -INT $P; wait $P
     python3 -I $R analyze logs/resp-$1.wav --listener --source laptop --json logs/resp-$1.json
   }
   ```
   | Step | What | Risk | Expect / Pass | Stop / note |
   | --- | --- | --- | --- | --- |
   | A0 | **Read-only, no sound:** `tools/phone-ssh 'uname -r; pacman -Q omamobile-audio pipewire wireplumber swh-plugins; omamobile-speaker-protection status \| head -1; systemctl is-active omamobile-speaker-watch'` | none | pipewire 1.4 or later (1.6.x expected); "ok: stage media … Top 737/10, Bottom 737/10"; `active` | pipewire older than 1.4 (no builtin `abs`: don't install 0.4.1, report); the stage not media (restore the default config first, C9d-3 step 0) |
   | A1 | **Install 0.4.1, restart the user's PipeWire** (announce: the sound changes): `tools/phone-install-package packages/omamobile-audio`, then `tools/phone-ssh "$U"'; as_user systemctl --user restart pipewire pipewire-pulse wireplumber; sleep 3; as_user omamobile-speaker-eq show'` | low | the values (hp 100, bass +4 at 400, dip -2 at 3500, width 1, swap 0, bassmono 0, harm 0, drive 0) | "no … node": `as_user journalctl --user -u pipewire -b \| tail` (an unknown label or plugin), then the filter-wide rollback |
   | A2 | **In the path, and the PCM format,** during a -23 dBFS 1 kHz tone (announce it): `tools/phone-ssh 'omamobile-speaker-protection signal tone /tmp/t1k23.wav --level -23 --seconds 4'; tools/phone-ssh "$U"'; (as_user timeout 5 pw-play /tmp/t1k23.wav &); sleep 2; as_user omamobile-speaker-eq show \| tail -1; cat /proc/asound/card*/pcm5p/sub0/hw_params'` | low | "in the path: plays into alsa_output…Speaker…"; `hw_params` format and rate: record (FLOAT_LE as stock, or S32_LE/S24_LE) | "NOT in the path": record `as_user wpctl status` and the speaker sink's `node.name` (`as_user pw-dump \| grep '"node.name": "alsa_output'`): the target name needs fixing, not a stop for the hardware; S16_LE: record (a later version pins float) |
   | B1 | **A/B by ear** (C9g step 1), told which only afterwards, 15-20 s each of `/tmp/m.flac` and `/tmp/v.flac` at the listener's volume: `eq preset flat`, `eq preset default`, and 0.3.5's sound `eq set hp=150 bass=0 dip=0` | low | a clear preference; the monitor moves by tenths of a degree | as in the rules |
   | B2 | **Measure with the phone's microphone** (announce: about 15 s of quiet stepped tones per speaker): `eq measure left --out /tmp/resp; eq measure right --out /tmp/resp; tools/phone-ssh "python3 -I /usr/lib/omamobile-audio/speaker_response.py suggest /tmp/resp/left-result.json /tmp/resp/right-result.json"` | low | two response tables (record them: frequency and level only) and per-speaker corners; the volume line equal for both | "CLIPPED" (again with `--level -40`); "no 1 kHz marker" (the default source: `as_user wpctl status`) |
   | B3 | **Measure at the listening position with the laptop's microphone** (tell the human: the laptop records the room for about 17 s per side; the recordings stay in `logs/`, gitignored, and are deleted after): the laptop at the listener's ear, `lrec left; lrec right; python3 -I $R suggest logs/resp-left.json logs/resp-right.json; rm logs/resp-*.wav` | low | the responses as heard, a balance figure and possibly a trim; compare with B2 (`python3 -I $R compare` one against the other is meaningless across microphones; compare shapes by eye) | the marker not found (the laptop's input muted or too far: closer, or `--level -25` on both sides) |
   | B4 | **Apply the B3 suggestion** (B2's if B3 failed) and A/B against `preset default`; fine-tune one value at a time. Record the values here | low | a preference | as in the rules |
   | C1 | **Bass to the bottom speaker:** `eq set bassmono=1 xover=X` (X from B2/B3's note, else 500), A/B against `bassmono=0` with `/tmp/m.flac` | low | fuller bass, the earpiece cleaner; prefer by ear | rattle on the bottom speaker (`bassmono=0`) |
   | C2 | **Bass harmonics:** `eq set harm_freq=F harm=0.5` (F from the notes, else 150), then `harm=1`, then `harm=0`, 20 s each | low | "more bass" without fuzz at 0.5 or 1 | a buzz or fuzz on bass notes (back to the lower value) |
   | C3 | **Width in portrait:** `eq set width=0.6` against `width=1` with `/tmp/m.flac` | low | preference (both speakers carry everything at 0.6) | none |
   | C4 | **Loudness at full volume:** `play /tmp/m.flac 1.0 30` with `drive=0`, then `eq set drive=2`, then `drive=3`; the monitor running | low (peaks stay at -3 dBFS; average power rises a little, far below the C9d-2 levels) | louder without distortion; tenths of a degree | distortion or pumping (`drive=0`; record which step) |
   | C5 | **Full volume with the chosen values** (C9g step 4): bass-heavy music at 1.0 for 30 s | low | as C4 | an over-exc count that moves (lower `bass` or `harm`, repeat) |
   | D1 | **Orientation:** `tools/phone-ssh "$U"'; as_user systemctl --user enable --now omamobile-speaker-orient'`, auto-rotation on; `tools/phone-ssh 'omamobile-speaker-protection signal multitone /tmp/mtL.wav --level -20 --seconds 5 --channels left'`; for each landscape side `play /tmp/mtL.wav 0.6 6` and ask the listener which side of the phone (as they see it) it comes from; `eq show \| tail -2` each time | low | from the left in both landscape orientations; `swap 1` in one of them | from the right in both: the side is the wrong way round (record it; `SWAPPED` in `omamobile-speaker-eq` becomes `right-up`); rollback `systemctl --user disable --now omamobile-speaker-orient; eq set swap=0` |
   | D2 | **Keep it:** `eq save`; record every chosen value here (no identifiers involved) | none | "saved: …"; the next version takes them as the package defaults | |
   | E | **Optional (medium; the human's separate go): C9d-7/C9d-8** as in their runbook above, with `eq preset flat` first so the bursts match C9d-6's signal, `eq reset` after; read the outcome with the table above | medium | | as in that runbook |
   | F | **Optional (medium; the human's separate go): Waves on the AoC**, T3b then T4 in `AOC-TUNING-RESEARCH.md` (with `eq preset waves`), plus its open-question-8 measurement there | medium | | as there |
   Record the results here with the date and `uname -r`.

   - **C9e balance** (at the last step that passed; risk medium):
     `burst /tmp/mtL.wav 1.0`, then `burst /tmp/mtR.wav 1.0`, with the
     phone upright in front of the listener at about 30 cm (and, if
     available, a sound-level meter app on another phone at the same
     spot: record both numbers). Then real media through PipeWire at
     50 %, 75 % and 100 % sink volume. Stock's amplifiers are equal, so
     equal levels are the target; what stock adds on top is the AoC's
     Waves processing, which we lack. If the top still dominates clearly:
     from omamobile-audio 0.4.0 lower it in software, `eq set trim_top=-2`
     and so on in 1-2 dB steps (C9g; trims only cut), until the balance
     sounds right, and record the value: a stand-in, not stock, until
     C10-tuning. Try also `eq set bass_top=0`: the earpiece plays little
     below its own resonance, so a bass lift there only adds excursion.
     The amplifier level `OMAMOBILE_SPK_TOP_DIGITAL` stays the fallback.
     Never raise the bottom above 817/17 to compensate.
   - **C9f real use** (risk medium): 15 minutes of mixed media at the
     user's normal volume, the watchdog on, then `omamobile-speaker-protection
     status` and `journalctl -u omamobile-speaker-watch -b`. Expect no
     mute, temperatures back near room temperature after, the over-counts
     unchanged (or explained). Then make it the default: bump
     omamobile-audio with stage c9, the levels from C9d/C9e, the media
     delta on, and `options aoc_alsa_dev speaker_protection=1` in its
     modprobe file; delete `/etc/modprobe.d/omamobile-audio-c9-bringup.conf`
     and the test lines in `/etc/omamobile/speaker.conf`.

   **Microphones:** stock records with 22 dB soft gain (`handset-mic-post`),
   and so do we. Speech close to the phone peaked near 15000 (about -7 dBFS)
   through `arecord` in C7c and a quiet room near 480 (about -37 dBFS) in
   C8d: a normal floor with 6 dB of headroom for close speech. Keep 22 dB
   and PipeWire's source at 100 %; revisit only if calls or recordings
   clip.

   **Loudness filter** (historical: done in 0.3.3-0.3.5, replaced by C9g's
   filter in 0.4.0): not before C9e. Stock's loudness comes from the
   AoC's Waves processing, not from the amplifiers. If, at stock gains with
   the media delta, media is still too soft, a PipeWire filter-chain on the
   speaker sink only (a 150-200 Hz high-pass, then a lookahead limiter with
   up to 6 dB of make-up gain and a -1 dBFS ceiling) raises average
   loudness without raising peaks, so the amplifiers' output and the
   protection's work stay where C9d measured them. It needs a LADSPA
   limiter (swh-plugins) on the phone. Stage it as C9g with the same rules.

   **Earpiece and calls (design; after the speaker, with the modem):**
   stock's `handset` path is the top amplifier alone with PCM Source ASP
   (DSP bypassed), AMP PCM Gain 6 (7 in a call, `voice-handset`, with boost
   peak 3.5 A), the bottom amplifier off. Plan: a "Voice Call" UCM verb with
   an `Earpiece` device (lowest priority, never a default sink) whose enable
   and disable sequences `exec` a small request to the protection service
   (a root-owned socket or a polkit-gated `systemctl start
   omamobile-earpiece@on/off`): the service mutes, sets top ASP / analog ≤ 6,
   bottom digital 0, and tells the watchdog the mode, so that in earpiece
   mode it expects the bypass on the top amplifier only at analog ≤ 6 and
   the bottom muted, and mutes on anything else. Acoustic shock, as stock:
   the watchdog claims proximity from omamobile-sensor-proxy during speaker
   playback and mutes the top amplifier (34 ms ramp-down) while the phone
   is at the ear.

   **C10-tuning (research, later):** drive the AoC's speaker processing
   as stock does: the tuning interface (`/dev/acd-audio_output_tuning`),
   Waves' instance and preset selection, the speaker back end's tuning id 2,
   and "AoC Speaker Mixer ASP Mode". From our analysis of the stock HAL
   first (the message format and order), then read-only probes of the
   AoC's replies; nothing is sent to the AoC before that is understood.

   **C9j: the muted speakers, the "wrong speaker" question and DRE
   (2026-10-27, 7.3.0-rc6-omamobile-push1-00588-gcd72ae58ee47,
   omamobile-audio 0.4.1 on the phone, stage media 737/10, PipeWire sink at
   1.0 unless stated; logs `logs/c9j-*-20261027.txt` on the laptop).**
   The listener found media very quiet, "like the call speaker", and asked
   whether media plays through the wrong speaker. Since 2026-10-26 22:28
   the watchdog had muted both amplifiers at the first stream of every boot
   ("Bottom: coil temperature jumped 14-27 C in this stream"), and nothing
   in the UI shows a mute; the 10-26 note that a power-off cleared it was
   wrong (the trip repeated 2.5 min into the cold boot, with no suspend in
   it).
   - **Routing is right.** The idle register snapshot of both amplifiers
     (bounded below 0x10100) differs only in the TDM slot registers, as
     stock: top RX slot 0 / TX 0,2,4,6, bottom RX slot 1 / TX 1,3,5,7,
     24-bit words, DSP RX1/RX2 from each amplifier's own ASPRX1. Left-only
     and right-only multitones came from the top and the bottom speaker
     respectively. The earpiece *is* the top speaker: it carries the full
     left channel at the same gain as the bottom one, on stock too; stock
     adds 17 dB of gain, Waves processing on the AoC and a proximity mute.
     With the sink at 60 % (cubic, about -13 dB) on top of the stage cap,
     media was about 30 dB under stock's maximum.
   - **The trip reproduces on the reference burst and is the bottom
     amplifier's protection model, not the signal.** `mt20` (stereo,
     -20 dBFS, the C9d-2 step-2 signal): the bottom's CSPL_TEMPERATURE
     went 25.00 -> 30.1 C within the first second (top 25.08), the
     watchdog muted at 5.1 C; on 10-12 the same burst moved the bottom by
     0.06 C. Left-only: the bottom stays at 25.00 (max excursion 0.027 mm),
     the top rises 0.17 C. Right-only: the bottom jumps to 31 C and trips.
     Both DSPs' RX sources swapped (top DSP <- ASPRX2 = slot 1, bottom DSP
     <- ASPRX2 = slot 0) and right-only again: the **top's model on the
     right channel's content rises 0.17 C, as on the left**, the bottom on
     silence stays flat. The bottom's model on slot 0's content (left-only
     with the swap) climbs the same way (36.7 C after 6 s). Right-only at
     sink 0.10: the bottom stays at 25.01 C. So the bottom's model
     over-estimates its output by roughly 20 dB on any content above a
     low level, with the same character as the gain-17 runaway both
     amplifiers show at 817/17 (C9d-5/6); the top's model is fine at
     737/10. Its BDLOG_MAX_EXC sits at the log's ceiling (0x3fffe,
     0.5000 mm) from the first second, DRE on or off; the top's reads
     0.3171 mm on the same content.
   - **What did not matter:** both amplifiers' DSP controls read the same
     apart from CAL_R, TUNING_ID (top 0x180000, bottom 0x141000) and the
     logs; the firmware files, the media delta files, speaker.conf and the
     calibration (DSP = persist) are unchanged since 10-13; no audio
     package changed since 10-13 (omamobile-audio 0.4.1 on the phone since
     10-13 19:34); the kernel went 00558 -> 00588 between the last stream
     that passed the 5 C rule (10-19 13:10) and the trips, with no commit
     in sound/ or firmware; the S2MPG12 LDO driver (00561) registered 28
     LDOs with no users and disabled none (`regulator_summary`,
     "disabling" only for `vddio_cam`); the hardware noise gate, the media
     delta (applied mid-stream in a clean run) and
     `OMAMOBILE_SPK_CAL_ORDER=stock` changed nothing.
   - **DRE is the difference.** `OMAMOBILE_SPK_DRE=0` (the C9d-2
     configuration of 10-12; DRE has been on by default since 0.3.2 /
     C9d-5): mt20 top +0.21 C / bottom +0.15 C, mt10 top +0.49 / bottom
     +0.21, right-only +0.13, and 30 s of music at sink 1.0 top +0.47 /
     bottom +0.25, no trip. With DRE on, the same right-only burst: bottom
     +6.4, +5.4, +5.1 C within a second. On 10-12 (DRE off) mt20 read top
     +0.12 / bottom +0.06 and mt10 +0.48 / +0.14, so DRE off restores the
     reference. Stock only runs DRE at analog gain 17 (`mixer_paths.xml`
     init: "DRE DRE Switch" 1 with "AMP PCM Gain" 17); the bottom's tune
     evidently assumes that gain when DRE moves gain between the stages,
     the top's does not. (An interim, unreleased 0.5.2 made DRE stage-dependent on this
     reading; the afternoon showed DRE was only the first of many triggers
     of the same estimate, and 0.5.3 keeps DRE on and moves the jump rule
     to stage c9 instead; see below.) `status` shows DRE. Why the 10-14..10-19 streams passed the 5 C rule: they ran at the
     sink's 60 %, and at low levels the model stays calm (sink 0.10 above).
   - **Open:** (1) one DRE-off right-only run (the first toggle, 09:38:16)
     tripped at the stream's last second with "25.0 -> 36.4" while the
     monitor had read 25.12 C one second earlier; four later DRE-off
     right-only runs and the music were clean; keep an eye on readings
     taken as a stream ends. (2) Whether DRE at gain 17 (stage c9) behaves,
     which is the C9i session's question anyway. (3) The by-ear items
     (cover test, left/right balance, C9e) were not judged yet: the
     listener's call. (4) The 10-26 suspend note and SUSPEND-PLAN's stop
     condition (PR #66) blame sleep for this; they should point here.
   - **Continued the same morning: DRE off is not enough; the estimate
     jumps on any level drop.** With DRE off, 60 s of music at sink 1.0
     tripped the watchdog at the listener's unlock (25.1 -> 36.7 C within
     a second, 09:58:16). Reproduced on demand: a sink volume step 1.0 ->
     0.6 during music (25.1 -> 37.3 C), a 20-step ramp over 1 s (at its
     first 0.02 step, 25.1 -> 38.0 C), and, with the sink untouched, a
     13 dB drop cut into the music itself (25.1 -> 36.7 C at the drop, the
     rise back 5 s later changed nothing). The top amplifier's estimate
     moved by 0.1 C through the same steps. So the bottom's tune reacts
     to level *drops*, which explains the whole list: DRE engaging at
     stream start, a quiet passage, a volume step down, the end of a
     stream (the first toggle's "36.4 at the last second"), the unlock
     (the shell's lock duck or notification). The sink volume is software
     only (the AoC's `PCM Playback Volume` stays 1000 across a `wpctl`
     change; the default sink is the ALSA node, not a filter). The
     firmware's own `ATTENUATION` stays at full scale (0x7fffff) through
     an estimate of 39 C on both amplifiers: it acts on nothing. DSP RX6
     from the class-H target (`dsp_rx6_classh=Y`, register 0x4c54 read
     0x21 on both) made no difference to the drop; set back to N. Stock's
     DT differs from ours in boost peak 3.5 A (ours 2.5 A, as stock's
     speaker path) and hibernate; stock's only bottom tune is the one we
     load (`R-cs35l41-dsp1-spk-prot.bin`, `cirrus,tuning-has-prefix`).
   - **Policy (omamobile-audio 0.5.3):** at analog 10 or below the
     firmware does not sense the coil (vmon low 1), its open-loop
     estimate is unreliable, the firmware does not act on it, and the
     levels are inside AUDIO-PLAN section 4's no-protection limits, so the
     watchdog's 5 C jump rule now applies only when the stage's analog
     ceiling is above 10 (stage c9, where the C9d-3..6 runaway it was
     written for happens; the boost decision below follows the configured
     levels instead);
     `OMAMOBILE_SPK_TEMP_JUMP` sets it in any stage. The 80 C backstop,
     the heartbeat, the level, bypass, runtime-PM and kernel-log rules
     stay in every stage. With 0.5.3 installed: the stepped music, a
     volume step and 30 s of music at sink 1.0 played through (the
     bottom's estimate peaked at 43 C, no mute).
   - **Phone left (evening):** `7.3.0-rc6-omamobile-push1-00591-gebc0cd6858ee`
     (the 00588 integration line plus the three `ASoC: cs35l41: bring-up
     option …` commits, branch `omamobile-test-wkfet`; the same three on
     `omamobile-audio-amp`), omamobile-audio 0.5.3, speaker.conf at the
     package defaults (boost off, DRE on, jump rule off at media), sink at
     1.0; `dsp_rx6_classh` N, `wkfet_amp` Y, `bst_ctl` 0.
   - **The afternoon: the "static" is the boost converter.** With the
     mutes gone the listener heard constant static under music, worse on
     the bottom. Measured through the phone's own microphone (EP1, the UCM's
     22 dB soft gain set to 0 for the loud tones; the path validated with
     an external clean 1 kHz tone at 0.4-0.6 % THD; pure-Python FFT on the
     laptop, logs in `logs/c9j-*`): at 737/10 a 1 kHz tone gives **44 % THD
     on the bottom at -20 dBFS** (0.4 % at -26) and **10 % on the top at
     -10 dBFS** (0.6 % at -20), odd harmonics, the fundamental compressed
     in a band of 10-15 dB and recovering above it; the same at 700 Hz,
     1.5 and 3 kHz, with the DSPs bypassed (PCM Source ASP, watchdog
     paused), hand-held out of the case, and at analog 6 with the file
     raised to the same output, so the threshold is a fixed *output* per
     speaker: about 30 mA peak into the bottom, 25 mA into the top.
     Ruled out one by one: DRE, the hardware noise gate, the DSP, PipeWire's
     float format (S32 forced: no change; PipeWire's volumes all 1.0), bit
     errors on the link (a 20 kHz tone on either slot raises the audible
     floor by nothing), the weak-FET output mode ("ASoC: cs35l41:
     bring-up option to switch the weak-FET output mode off",
     `wkfet_amp=N`, PWR_CTRL3 read 0x00000010 during playback: no change), brown-out prevention (VPBR/VBBR status 0),
     the class-H input (`dsp_rx6_classh=Y`, verified 0x21 at 0x4c54), VP
     (stock: VSYS directly), the serial port and PLL (6.144 MHz, dsp_a,
     as Google's driver sets them). **With "ASoC: cs35l41: bring-up option to
     run without the boost converter" (`boost_en=N`: PWR_CTRL2 BST_EN = 0,
     the output stage from VP; `7.3.0-rc6-omamobile-push1-00590-g317c80785330`,
     PWR_CTRL2 read 0x3701 and PWR_CTRL3 0x01000010 on both amplifiers
     during playback, against 0x3721 with the converter on; rollback: the
     parameter back to Y and `systemctl restart
     omamobile-speaker-protection`, which rebinds): the same inputs
     come out 8-11 dB louder and clean: top at -10 dBFS 1.0 %, bottom at
     -26 dBFS 0.5 %, at -20 dBFS 12 %, with DRE on 4 %.** At hot content
     (-4 dBFS) both compress cleanly (the firmware's limiter). The
     listener: "so much better and much louder and much more clear
     without static". Reading: at the everyday level the converter sits in
     its light-load regime, where it droops and distorts; stock's 817/17
     never runs it there. Its registers (peak 2.5 A as stock's speaker
     path, coefficients, DCM, class-H 0x000b0405, WKFET 0x111, VCTRL1 0 as
     the chip default, VCTRL2 class-H) match Google's driver, which also
     never writes the boost target unless the DT gives one (stock's does
     not). The bottom's remaining 6-11 % from -10 dBFS up with the
     converter off was the next question. **A fixed boost target ("ASoC:
     cs35l41: bring-up option for a fixed boost target", `bst_ctl`,
     BST_CTL_SEL = register; AUDIO-PLAN section 4's reserved register,
     written with the owner's go and restored after; its row now says so)
     does not beat the converter off:** at 8.0 V the bottom reads 1.1 % at
     -20 dBFS and 6 % at -10 (better), the top 4.4 % at -10 (worse than
     1.1 %); at 5.7 V the top falls apart (76 % at -10 dBFS) and the bottom
     reads 17 % at -20. The lighter load (the top, about 25 mA) suffers
     most, as light-load switching behaviour would. Output levels with the
     converter off equal those at 8 V, so nothing is lost. Decision: the
     converter stays off at analog 10 and below (0.5.3); the bottom's
     6-11 % from -10 dBFS up is a separate, smaller question. The
     converter is needed at gain 17 (stage c9), where its load is 10-20 dB
     higher and stock runs it; that is the C9i session's ground.
   - **omamobile-audio 0.5.3:** the boost converter off at analog 10 and
     below and on at 17, through `boost_en` (set before the amplifiers
     probe; a kernel without the parameter keeps it on and the status says
     so); DRE on by default again; `OMAMOBILE_SPK_BOOST=1|0` forces it.
   - **Gotcha, written into AGENTS.md:** routing `TDM_0_TX` (the
     amplifiers' VMON/IMON return) into an entry-point capture (`EP5 TX
     Mixer TDM_0_TX` = on and a capture of PCM 12) fired the AoC's
     watchdog and took the AoC offline ("aoc watchdog triggered",
     "taking aoc offline"); every service answered -517 until a reboot,
     and PipeWire lost the card. EP6's capture defers the same way, and the
     hostless PCM 15 opens but delivers nothing to the host. There is no
     host-readable copy of the amplifiers' V/I on this card.
   - **Also seen:** the top DSP's resume command failed once at stream
     start ("Failed to set mailbox cmd 2 (status 1)", POST_PMU) and its
     heartbeat stuck once for 2 s, each time muted by the watchdog as
     designed; both after the amplifiers had been rebound many times that
     hour. PipeWire re-applies the UCM's 22 dB mic gain after a speaker
     service restart (the card re-probes), which bit two measurements.
   - **Loudness, the same evening.** The owner heard the test tones as
     much louder than streamed music: a -3 dBFS multitone is 10-15 dB
     hotter than music normalised to about -14 LUFS, so the amplifiers
     were not at fault. The filter is where application streams land
     (WirePlumber remembers it as their target; plain players take the
     sink), and its limiter drive is the right lever: flat preset plus
     6 dB of drive on YouTube Music, "louder" and clean, chosen over the
     default shelf and dip ("it's definitely louder", "amazing" for the
     plain path). **omamobile-audio 0.5.4 makes that the default:** 20 Hz
     high-pass, no shelf, no dip, drive 6 dB. **817/10 without the
     converter is not usable** (watchdog paused, both amplifiers at 817):
     bottom -20 dBFS 4.3 % (+9 dB), bottom -10 dBFS 82 % (a hard ceiling
     near 2 V peak, the output stage out of supply), top -20 dBFS 4.5 %,
     top -10 dBFS 7.7 % compressed; the open-loop estimates reached 85 C
     (top) and 58 C (bottom) in four 6 s tones, above the paused
     watchdog's backstop; restored at once. A second player (`cliamp`)
     ran alongside YouTube during part of the comparison. Sink-monitor
     captures (`pw-record --target <sink> -P stream.capture.sink=true`)
     returned identical data whatever played and are no measurement on
     this phone; the mic and the ear are.
   - **Still open:** the bottom's residual 6-11 % distortion from -10 dBFS
     up with the converter off (a fixed target did not remove it, above);
     what gain 17 needs (stage c9 keeps the converter on); why both tunes'
     open-loop estimates misbehave (the bottom on level drops
     at gain 10, both at gain 17 from the first sample, C9d-5/6). The
     balance by ear and the cover test are the listener's.

## 0. Top findings

1. **Stock starts the AoC through Trusty; this phone's GSA also takes the
   mailbox command (C1).** Stock
   loads `aoc.bin` from the kernel (`aoc 19000000.aoc: attempting to load
   firmware "aoc.bin"`, `R/dmesg.txt:5799`), the GSA authenticates it over its
   mailbox (`GSA_MB_CMD_LOAD_AOC_FW_IMG` = 90, `GSA/gsa_core.c:169-176`), and
   then `GSA_AOC_START` goes to the Trusty service
   `com.android.trusty.gsa.hwmgr.aoc` (`GSA/gsa_core.c:187-194`,
   `R/dmesg.txt:5886` "TZ: com.android.trusty.gsa.hwmgr.aoc connected").
   Every public Google kernel does the same, back to the first Pixel 6 branch
   (`android-gs-raviole-5.10-android12-d1`). But the GSA mailbox also
   carries AoC state commands (command 91), and C1 got an answer: the
   **GSA-direct path** (section 0.1) needs no Trusty. Trusty (already ported
   on `omamobile-fingerprint`, shared with fingerprint) stays as the
   fallback; `gsa.c` speaks both.
2. **The bootloader does not leave the AoC running.** Stock's kernel loads and
   starts it 4.07 s into boot and it reports "firmware version
   14022723-polygon did become online with 82 services" at 4.60 s
   (`R/dmesg.txt:5799-6042`). Nothing earlier touches it. So there is no
   running firmware for a minimal client to talk to; the full
   load-authenticate-start path is needed.
3. **The firmware and Google's 6.1 driver match, and the firmware carries its
   own IOMMU map.** Parsed offline from our `V/firmware/aoc.bin` (21,328,448
   bytes, auth header generation 1, superbin magic `0xaabbccdd`, release
   build "14022723-polygon"):
   - all 286 interface UUIDs that `GA/aoc-interface-gs201.h` checks
     (`AocInterfaceCheck()`) are in the firmware's 537-entry table, so the
     driver accepts this firmware;
   - the image config puts the body at `0x94000000` (`fw_size` 0x1600000,
     22 MiB), the IPC area at carve-out offset 0x1600000, and lists **six
     IOMMU windows** (AoC address → physical, size):

     | AoC VA | PA | Size | What |
     |---|---|---|---|
     | `0x98000000` | `0x94000000` | 48 MiB | the AoC carve-out (`aoc@94000000`) |
     | `0x9b000000` | `0x97000000` | 4 MiB | `xhci-dma` (USB audio offload) |
     | `0x9e000000` | `0x18200000` | 2 MiB | APM/AoC mailboxes (`0x18210000`, `0x18300000`-`0x18340000`) |
     | `0x9e200000` | `0x17c00000` | 1 MiB | GSA block (`0x17c60000` S2MPU, `0x17c90000` mailbox) |
     | `0x9e500000` | `0x11200000` | 1 MiB | USB PHY/dwc3 (HSI0) |
     | `0x9e300000` | `0x40000000` | 1 MiB | PCIe ch0 outbound window (modem) |

     All are 1 MiB multiples, so a first-level-only SysMMU v8 table (the
     format our Wi-Fi work already uses, `WIFI-BATTERY-PLAN.md` 9.17) covers
     them: about 300 lines instead of Google's 3,200-line IOMMU driver.
4. **AoC state commands work over the GSA mailbox.**
   `GSA_MB_CMD_AOC_CMD` (91) is defined next to the load command
   (`GSA/gsa_mbox.h:49-52`) but no public driver sends it. C1 asked it for
   `GSA_AOC_GET_STATE` and got a proper answer (state 0, inactive). Start,
   shutdown and reset are the same command with another argument.
5. **ACPM channel 13 is a doorbell, not a queue, and is not needed to start
   the AoC.** Our A1 dump shows it as type 2 (buffer), all offsets 0, `mlen
   0` (`logs/acpm-20261012-112536-a1.log`). Google's driver handles a type-2
   channel by calling the client's callback on the APM→AP mailbox interrupt
   bit (`GS/drivers/soc/google/acpm/acpm_ipc.c:499-505`), and the AoC callback
   ignores the payload (`GA/aoc_v1.c:58-67`, sets `aoc_reset_done`). It is
   used only after an AoC watchdog reset (`aoc_watchdog_restart()`,
   `GA/aoc_v1.c:109-206`). So the fix for crash recovery is to watch bit 13
   of the AP2APM mailbox status (SPI 78), not to read any SRAM ring. A
   **clean** restart needs no ACPM at all: Google's `aoc_take_offline()`
   (`GA/aoc.c:1582-1640`) does shutdown (GSA 4, back to "loaded"), then
   unload (the GSA unlocks the carve-out, "inactive"), after which load and
   start run again.
6. **First sensor reading comes before first sound.** Sensors need the AoC
   core plus a character-device client in userspace; audio additionally
   needs the 16,700-line `aoc_alsa` port, the amplifiers and their protection.

### 0.1 C1 result and the GSA-direct path

C1 on `omamobile-int` `7.3.0-rc6-omamobile-push1-00186-ga0b0c0ebb3f6`
(default DTB + `display-decon-test` + `aoc-gsa-test`):

```
google-gsa 17c90000.gsa: mailbox ready, irq 104
sjtag_status: args 3: debug_allowed 0x00000000 hw_status 0x00000010 debug_time 0x00000000
cmd 100: answer 0x80000064 err 0 argc 3
cmd 91: answer 0x8000005b err 0 argc 1
aoc_state: args 1: 0x00000000 ... (state inactive)
```

`hw_status 0x10` is what stock prints for the same command
(`R/dmesg.txt:2012`). No hang.

GSA commands for the AoC (`GSA/gsa_mbox.h:49-52`, `include/linux/gsa/gsa_aoc.h`,
`GSA/hwmgr-ipc.h`):

| Mailbox cmd | Args | Reply | Stock sends it |
|---|---|---|---|
| 90 `LOAD_AOC_FW_IMG` | header DMA lo, hi; body PA lo, hi | none | yes, on the mailbox; a "data transfer" command: under a GSA wakelock (150/151) with the GSA S2MPU open |
| 91 `AOC_CMD` | one: `GET_STATE` 0, `START` 1, `SHUTDOWN` 4, `RELEASE_RESET` 5, `RESET` 6 | one: state `INACTIVE` 0, `LOADED` 1, `RUNNING` 2 | no: stock sends the same commands as Trusty `hwmgr.aoc` `STATE_CMD` (1) |
| 92 `UNLOAD_AOC_FW_IMG` | none | none | no: stock uses `hwmgr.aoc` `UNLOAD_IMG` (2) |
| 150 / 151 `WAKELOCK_ACQUIRE/RELEASE` | none | none | yes, around data transfers (`GSA/gsa_mbox.c:466-560`) |

Stock's order:

- **Boot** (`GA/aoc.c:508-710`): `aoc_req` = 1 → copy the body → load (90) →
  write the parameter block → `START` → the firmware fills its control
  block ("online with 82 services" 0.45 s later).
- **Offline** (`GA/aoc.c:1582-1640`): `aoc_req` = 1 and wait for the
  acknowledge → `SHUTDOWN` (expects "loaded") → unload (expects success,
  state "inactive").
- **Crash**: the PCU watchdog, ACPM channel 13, then boot again.

So the GSA-direct path is: load (90), then 91 `START`; restart = 91
`SHUTDOWN`, 92, load, 91 `START`. `gsa.c` sends 91/92 when loaded with
`aoc_cmd_mbox=1`, and the Trusty messages otherwise.

### 0.2 C2-C4 results (omamobile-int 00200, DTB default + display-decon-test + aoc-boot-test)

| Stage | Result |
|---|---|
| C2 | pass. `aoc_req` 1, ack 1: **BLK_AOC is on at hand-off**. GSA state 0. Chip 0x9855000, type 0x1, revision 0x10; board 0x30301/0x10000. Carve-out not System RAM. **AoC S2MPU CTRL0 0x5** (enabled, blocking). AoC System MMU v8.1, CTRL 0x24, CAPA0 0x41085800, CAPA1 0xe051 (8 VIDs), every VID off (ctrl 0, cfg 0x20000, no table) |
| C3 | pass. S2MPG12 and S2MPG13 CHIPID 0x05. **All five rails off**: LDO20M/19S/20S/7S ctrl 0x2c (1800 mV), LDO5S 0x3c (3300 mV), enable bits clear |
| C4a | pass. GSA S2MPU CTRL0 0x1 → 0 for the load; "cmd 90: answer 0x8000005a err 0"; state 1 (loaded); no faults |
| C4b | **no**. "cmd 91 … argc 1", reply **4**; no control block in 5 s; GSA state stays 4; no System MMU fault line. `SHUTDOWN` then gives state 1 (loaded), and the phone is fine |

**The "magic 0xa0cda7a" is our own parameter block.** The boot driver wrote
`AOC_PARAMETER_MAGIC` 0x0a0cda7a at carve-out + 0x1600000 before the start,
and the firmware overwrites that area with its control block (magic
0xa0c00a0c) when it comes up (`GA/aoc.c` writes both at the same address).
The "control block" printed is that parameter block read as one: status
0x1001 is the first key (`kAOCBoardID`), "4098 services" is 0x1002
(`kAOCBoardRevision`), "size 4" its length, "+0x10000" the board revision
value. Nothing is half-written or mis-parsed: **the firmware never got as
far as writing its control block.**

**State 4 is not in Google's enum** (`gsa_aoc.h`: inactive 0, loaded 1,
running 2; the TPU adds suspended 3, the DSP's own enum has 5 values). It is
the reply to `START`, read the same way as the replies that were right
(0 before load, 1 after load and after `SHUTDOWN`), so it is a real state.
Google's `aoc_take_offline()` carries a note that the shutdown command's
number changed in the GSA firmware (`GA/aoc.c:1619-1621`), so the GSA's AoC
interface has moved over time and its states are not all in the public
header. Readings to tell apart in C4b-2:

1. **A block reset during load or start cleared our setup.** The AoC S2MPU
   was 0x5 (blocking) at hand-off and the System MMU was off. If cmd 90 or
   `START` resets BLK_AOC, the S2MPU blocks every AoC access again (its
   faults are not reported to us) or the System MMU passes the AoC's
   addresses through untranslated. Either way the A32 cannot fetch its code.
   Stock restores both after a reset (pKVM for the S2MPU, the IOMMU driver
   on runtime resume). C4b-2 reads both after the load and before and after
   the start, and puts them back before `START`.
2. **The A32 is still in reset.** `START` may prepare the AoC and leave the
   A32 to a separate release (`GSA_AOC_RELEASE_RESET` 5, "take AoC A32 out of
   reset" in `gsa_aoc.h`), which Trusty's service might send itself. C4b-2
   reads the PCU reset control and, only if the A32 is held, sends 5.
3. **The firmware runs but waits or crashes early.** The ramdump header at
   carve-out + 32 MiB (`GA/aoc_ramdump_regions.h`, outside the locked body)
   has boot breadcrumbs, and the AoC watchdog (SPI 116) fires on a crash.
   C4b-2 dumps both.
4. **The rails.** Stock powers the microphone and sensor LDOs before the
   load (`configure_sensor_regulator()` and `configure_dmic_regulator()` at
   probe); on this phone all five are off at hand-off. The firmware publishes
   its control block before it probes sensors, so this is the least likely,
   but C4b-3 tests it.

Stock needs nothing else from the AP between `START` and "online": the
firmware writes its control block and rings an AoC mailbox; the AP only
checks the magic (`aoc_mbox_rx_callback()` → `aoc_fw_ready()`) and then
drops `aoc_req` (`aoc_did_become_online()`, `GA/aoc.c:1358-1440`). No ACPM
message, no AP doorbell first.

### 0.3 C4b-2 result: the GSA-direct start is not enough; use Trusty

C4b-2 rerun (int 00238, `deb7b47bd`): no abort, no fault, no watchdog.
After the load the System MMU translates VID 0 (global ctrl 0x25, VID 0
ctrl 0x9, our table), the AoC S2MPU stays 0 through the start, `START`
gives state 4 again, the IPC area keeps our parameters, the ramdump header
has no "AOCDUMP" and no breadcrumbs (0x300-0x32f zero). `RELEASE_RESET` (5)
gives state 2 ("running"), twice, but still nothing: no control block, no
breadcrumbs, no System MMU fault (`int` 0).

What Google's driver does that we did not, compared line by line
(6.1 `GA/aoc.c` `aoc_fw_callback()` and Google's 5.10 aoc.c at commit
222ba49, the version that drives this firmware generation through Trusty):

| Step | 5.10 driver | 6.1 driver | Ours |
|---|---|---|---|
| `aoc_req` = 1 before the load | yes | yes | yes |
| AoC S2MPU | CTRL0 read at probe, written back after a restart | (pKVM) | 0 before the load, stays 0 |
| System MMU windows | `aoc_configure_sysmmu()` at probe, non-secure domain via samsung-iommu (VID 0) | IOMMU driver | same windows, VID 0, before the load |
| body copy, GSA load (90), parameter block | yes | yes | yes |
| `START` | `gsa_send_aoc_cmd()` → **Trusty `hwmgr.aoc`** | same | **mailbox 91** |
| mailboxes | AP-side masks only; the firmware writes its control block first and rings after | same | not set up |

The only material difference left is **who sends `START`**. The mailbox
path answers, but not like Trusty's: `START` leaves state 4, and an explicit
`RELEASE_RESET` runs the A32 without any visible progress. The System MMU
has a secure half (`sysmmu,secure_base = <0x1a0a0000>`, secure fault
interrupt SPI 119) that only the secure world can program and whose faults
never reach Linux. The likeliest reading: Trusty's `hwmgr.aoc` service does
secure-side setup for the authenticated image (its secure translation,
security state of the AoC's masters) before it has the GSA start the AoC,
and the bare mailbox command skips it. An A32 that runs with that missing
would fault silently on the secure side, which is exactly what we see.

So the **Trusty path is now the main path**: load with the mailbox (as
stock), state commands through `hwmgr.aoc`. `gsa.c` already speaks it
(`CONFIG_GOOGLE_GSA_TRUSTY`, default when `aoc_cmd_mbox=0`), and the Trusty
driver is the fingerprint port (gate F2 not yet run), already in
`omamobile-aoc`. It is also the order stock uses (`R/dmesg.txt:5886`, "TZ:
com.android.trusty.gsa.hwmgr.aoc connected" right before the AoC comes up).

The rails (all off) stay a separate variable: change one thing at a time,
Trusty first, rails after if needed.

What is mandatory, in boot order:

| Piece | Why | Source | Our status |
|---|---|---|---|
| GSA mailbox | authenticates and loads `aoc.bin`; AoC state commands (91) | `GSA/gsa_mbox.c` (600) + `gsa_core.c` | **written**; C1 passed |
| S2MPU off for the GSA and the AoC | the GSA reads the image header by DMA; stock's pKVM programs both S2MPUs at power-up (`R/dmesg.txt:462`), nothing does without a hypervisor | `GS/drivers/soc/google/s2mpu/s2mpu-regs.h` (CTRL0 at 0x0; 0 passes everything) | **written**: CTRL0 = 0 only, GSA's under a GSA wakelock and restored after the load, the AoC's while BLK_AOC is on |
| Trusty + GSA `hwmgr.aoc` client | `GSA_AOC_START` on stock | `G/google-modules/trusty`, `GSA/gsa_tz.c` (236) | **fallback, written** (`CONFIG_GOOGLE_GSA_TRUSTY`); not needed while command 91 works |
| SysMMU `sysmmu_asoc` (`0x1a090000`, v8) | the AoC's view of DRAM and its peripherals | `GS/drivers/iommu/samsung-iommu.[ch]` (v8 VM register set) | **written**: windows from the image header, VID 0 |
| AoC mailboxes (`0x18300000`, `0x18320000`, `0x18340000`) | service doorbells | `GA/mailbox-wc.c` (412) | to port |
| AoC boot (parameters, start, control block) | gets the firmware to "online" | `GA/aoc.c` `aoc_fw_callback()`, `aoc_v1.c` | **written** as a bring-up driver (`gs201-aoc-boot`) |
| AoC core | services, rings, char devices | `GA/aoc.c`, `aoc_service_core.c`, `aoc_channel_dev.c`, `aoc_char_dev.c`, `aoc_control_dev.c`, `aoc_ipc` (~6,000) | to port (C5) |
| PMIC rails over ACPM ch 2 | mics (LDO20M, LDO19S, LDO20S), sensors (LDO7S then LDO5S) | `GS/include/linux/mfd/samsung/s2mpg1[23]-register.h`, `GS/drivers/regulator/s2mpg1[23]-regulator.c` | **written** (`gs201-aoc-rails`, read-only unless `enable=1`) |
| `aoc_alsa` | the sound card | `GA/alsa/` (~16,700) | audio only; to port |
| ACPM ch 13 | AoC restart after a crash | above | later |

---

## 1. How stock brings the AoC up (evidence)

Order in `aoc_fw_callback()` (`GA/aoc.c:508-710`), with `gsa-enabled` set in
the stock DT (`R/live.dts:6068`):

1. `request_aoc_on(true)`: write 1 to `aoc_req` (`0x181d0000`); the
   acknowledge is `aoc_req + 0x40` (`GA/aoc_v1.c:87-106`).
2. Validate the superbin, check the interface UUIDs, refuse unsigned images.
3. Copy the image body (without the 4 KiB auth header) into the carve-out
   at `0x94000000` (`_aoc_fw_commit()`; `AOC_BINARY_DRAM_OFFSET` is 0).
4. `aoc_fw_authenticate()`: copy the 4 KiB header into a
   `dma_alloc_coherent()` buffer **of the GSA device**, then mailbox command
   90 with header DMA address (lo, hi) and body physical address (lo, hi)
   (`GSA/gsa_core.c:82-95`). The GSA authenticates, then locks the body: from
   here the AP must not touch `0x94000000`-`0x955fffff`.
5. `aoc_pass_fw_information()`: write the parameter block at the IPC area
   (carve-out + 0x1600000): magic `0x0a0cda7a`, then key/size/value triples:
   board id `0x30301`, board rev `0x10000` (DT `aoc-board-cfg = "C10"`),
   carve-out address and size, the three heap addresses (sensor direct 4 MiB,
   playback 16 KiB, capture 64 KiB, carved from the top of the carve-out and
   given as AoC addresses = PA - 0x94000000 + 0x98000000), chip revision,
   type and product id, a random seed, and zeros for the debug switches.
6. `gsa_send_aoc_cmd(GSA_AOC_START)` over Trusty.
7. Enable the watchdog IRQ (SPI 116), keep the AP out of deep idle for 2 s,
   and wait for the firmware to write `AOC_MAGIC` into the control block;
   then it enumerates its services (82) and the bus binds drivers by name:
   `aoc_alsa` to `audio_output_control` and friends, `aoc_channel_dev` to
   `com.google.usf`, `com.google.usf.non_wake_up`, `com.google.chre`
   (`R/dmesg.txt:6076-6082`), everything else to `aoc_char_dev`.

With `gsa-enabled`, the kernel does **not** install the firmware's IOMMU table
(`aoc_configure_iommu()` runs only on the non-GSA path); stock's samsung-iommu
driver owns `sysmmu_asoc` and restores its state on runtime resume
(`GA/aoc_v1.c:185-198`). Which side programs the six windows on stock (the
non-secure table, or the secure half at `sysmmu,secure_base = 0x1a0a0000`)
is not visible in the GPL code; on our kernel nothing programs it, so we
install the six windows ourselves (C4).

Other facts the port needs:

- `pd_aoc` (`0x18061880`) is `disabled` in the stock DT: the APM powers
  BLK_AOC on `aoc_req`, the kernel never does. AoC power status is PMU
  `0x18061884` (`GS/drivers/soc/google/cal-if/gs201/flexpmu_cal_local_gs201.h:8-23`),
  but **do not read the PMU from user space**: a `/dev/mem` read of a PMU
  power-domain register crashed the phone (`GPU-PLAN.md`, incident).
- No SSMT setup on gs201 (`aoc_configure_ssmt()` is gs101-only,
  `GA/aoc_v1.c:314-342`).
- Pins: `aoc_vsync_pins` = gpp3-1, gpp5-1, gpp7-1, gpp9-1, function 2
  (`R/live.dts:4212-4216`, PERIC0 pin controller): display TE to the AoC,
  which times the under-display light sensor.
- Sensor supplies `sensor_1v8` then `sensor_3v3` (`sensor_power_list`,
  `R/live.dts:6092-6094`); DMIC supplies are always-on regulators in the DT.
- The AoC's view of time: `aoc_clock_and_kernel_boottime`, used to stamp
  sensor events.

---

## 2. Shortcuts considered

| Idea | Verdict | Why |
|---|---|---|
| The bootloader leaves the AoC running; talk to it with a minimal mailbox client | **no** | stock's kernel loads and starts it (finding 2) |
| Load with the GSA mailbox, start without Trusty (mailbox cmd 91) | **yes** | C1: the GSA answers command 91 (section 0.1) |
| Release the AoC from reset ourselves (`aoc_release_from_reset()`, PCU bit 0) | **no** | only for unsigned images without GSA; signed images are locked by the GSA, and the production firmware is signed |
| Skip the SysMMU (bypass) | **no** | the firmware addresses its carve-out at `0x98000000`, which is physically the GXP region; translation is required |
| Skip ACPM ch 13 | **yes** | needed only for crash recovery; a clean restart is shutdown, unload, load, start (finding 5) |
| Skip `aoc_alsa` for sensors | **yes** | sensors use `aoc_channel_dev` only |
| Skip the S2MPG12/13 regulator driver | **yes, at first** | five LDO enable bits over ACPM ch 2 (section 5); a proper regulator driver later |
| Port Google's samsung-iommu (3,200 lines) | **no** | a static six-window table is enough; the AoC needs no runtime maps for first light (the heaps are inside the 48 MiB window) |

### 2.1 Can the AoC client live in userspace, as Android's HAL does?

Partly. On stock the split is already kernel core + userspace HALs: the kernel
loads the firmware, runs the mailbox doorbells and the service rings, and
exposes each service as a character device (`/dev/acd-com.google.usf`,
`/dev/aoc`); the sensor HAL (`V/lib64/sensors.usf.so`, `libusf.so`) and the
audio HAL speak the services' message formats from userspace.

- **The kernel part cannot move to userspace.** The GSA needs a DMA buffer below 4 GiB that it can
  read, the SysMMU and S2MPUs need privileged writes, and the services are
  interrupt-driven rings. A UIO/`/dev/mem` client would reimplement the same
  core worse and could not be upstreamed.
- **The sensor client should live in userspace**, exactly like stock: our own
  USF client over `/dev/acd-com.google.usf` (FlatBuffers messages; the
  stock registry in `V/etc/sensors/registry/cheetah_dvt.reg` and
  `persist:/sensors/registry`), feeding an iio-sensor-proxy-compatible
  D-Bus service for Hyprland rotation and brightness.
- **Audio could, in principle, skip `aoc_alsa`** with a userspace daemon
  that drives `audio_output_control` and a playback ring through
  `aoc_char_dev` and exposes a PipeWire node. But the command set it would
  have to replicate is `aoc_alsa_hw.c`/`aoc_alsa_ctl.c` (7,400 lines), and
  PipeWire/UCM/volume keys all expect an ALSA card. Port `aoc_alsa`
  out of tree (with the CS35L41 as TDM codecs) instead.

---

## 3. Effort

| Piece | Lines (Google) | Effort | Notes |
|---|---|---|---|
| GSA mailbox driver, load/state/unload | 600 | **done** | `L/drivers/soc/google/gsa.c` |
| S2MPU CTRL0 handling | - | **done** | in `gsa.c` and `gs201-aoc-boot.c` |
| GSA `hwmgr.aoc` client over Trusty IPC | 236 | **done** (fallback) | on the fingerprint branch's `tipc` kernel API |
| SysMMU six-window driver | (3,200) → ~400 | **done** | v8 VM registers as in `GS/drivers/iommu/samsung-iommu.c:38-75,182-240` |
| AoC boot to "online" (bring-up) | (part of `aoc.c`) | **done** | `gs201-aoc-boot.c`, debugfs steps |
| AoC mailbox + core + char devices | ~6,000 | 2 weeks | out of tree first; vendor hooks (`exynos_pmu`, `dbg_snapshot`, `acpm_ipc`, `gs_chipid`, ITMON, power-mode) become stubs or upstream equivalents; the boot steps come from `gs201-aoc-boot` |
| Rails over ACPM ch 2 | - | **done** for the five LDO bits; 2-3 weeks for a real S2MPG12/13 regulator driver | `gs201-aoc-rails.c`; `ACPM-PLAN.md` 6 |
| USF sensor client + D-Bus service | - | 2-4 weeks | clean-room from the stock library's behaviour |
| `aoc_alsa` port to 7.3 ASoC | ~16,700 | 3-6 weeks | dummy codec on links with no driver, TDM slots from the DT |
| Machine/UCM/calibration/protection | - | 2 weeks | `AUDIO-PLAN.md` A7 |
| ACPM ch 13 doorbell + AoC restart | - | 3-5 days | upstream `exynos-mailbox` has no RX interrupt support yet |

Calendar, one developer: **first AoC "online" as soon as C2-C4 pass (the
code is written), first accelerometer reading 3-4 weeks after that (core
port + USF client), first protected speaker sound 6-10 weeks after
"online"**. Much shorter than the "months" estimate in `AUDIO-PLAN.md`:
no Trusty needed, the IOMMU is a static table, and ACPM works.

---

## 4. Risks

| Risk | Mitigation |
|---|---|
| S2MPU registers other than CTRL0 can reset the SoC; any S2MPU register can abort while its block is off | touch only CTRL0, only after the GSA wakelock (`GSA_MB_CMD_WAKELOCK_ACQUIRE` 150) or `aoc_req` acknowledge; never from user space |
| PMU reads from user space crash the phone (`GPU-PLAN.md` incident) | AoC power state only through the kernel, via `aoc_req + 0x40` or the GSA/Trusty `GET_STATE` |
| After `LOAD_AOC_FW_IMG` the carve-out body is locked; an AP read faults | never read `0x94000000`-`0x955fffff` after load; the carve-out is already `no-map` (`gs201.dtsi`) |
| A failed start cannot be retried in the same boot | hang-safe marker as for Wi-Fi: `tools/aoc-stage c4a` writes and syncs `/var/lib/omamobile/aoc-bringup-started` before the load and refuses to run while it exists; `c4b` clears it on success. A clean retry is `unload`, then load and start; after a failure, reboot |
| The AoC writes outside its windows (wrong table, wrong VID) | the System MMU translates VID 0 with only the six windows; anything else faults and is logged ("blocked ... VID n"). Untranslated traffic would reach physical memory directly, so C2 records the VID registers first, and C4b counts "blocked" lines |
| GSA mailbox command never answered | `gsa.c` times out after 1 s and disables the mailbox until reload (Google's waits forever) |
| AoC watchdog / IOMMU fault storms | the AoC watchdog IRQ (SPI 116) is not requested by the bring-up driver; System MMU fault lines are rate-limited |
| The AoC holds the AP awake or wakes MIF constantly (sensors at high rate) | non-wakeup USF channels for UI sensors; pause sensors when the screen is off |
| Firmware/driver mismatch after a vendor update | the UUID check refuses it; extract `aoc.bin` from the phone's own vendor partition with the matching kernel sources (checked offline for 14022723) |
| **Speaker damage** | `AUDIO-PLAN.md` section 4 limits apply unchanged: boost peak ≤ 2.5 A, `Analog PCM Volume` ≤ 6 for the top amp as earpiece and ≤ 10 for either amp with the DSP bypassed, `Digital PCM Volume` ≤ 657 for first sound, 1 kHz bursts of 1-2 s, ≤ 30 s without protection, mapping and calibration confirmed before tuning loads. Also AoC-specific: the amps take their PLL reference from the AoC's TDM BCLK, so the TDM link must run before an amp's `GLOBAL_EN` and the amp must be muted before the AoC stops TDM |
| Mic rails off: recordings are a burst then zeros | turn LDO20M, LDO19S, LDO20S on (ACPM ch 2) before the first capture |
| Sensor rails off when the registry loads: only virtual sensors until the AoC restarts | LDO7S then LDO5S on before loading the registry |
| Under-display light/proximity (TMD3719) never converts | send the display state (panel on/off, brightness, refresh rate) to the AoC's display-info service at start and on every change |

---

## 5. Kernel and repo changes made

Kernel branch `omamobile-aoc` (`L/`), on `omamobile` @ `7b0f8b5d1`. It
merges cleanly into `omamobile-int` @ `741b6ed1d` (`git merge-tree`).

| Commit | What | Default |
|---|---|---|
| `58e9fb0a2` dt-bindings: soc: google: add the gs201 GSA mailbox | `google,gs201-gsa` | - |
| `21aa277d2` soc: google: add a GSA mailbox driver | `drivers/soc/google/gsa.c` (`CONFIG_GOOGLE_GSA`): Google's register protocol, 1 s timeout per command, then the mailbox is refused; debugfs `sjtag_status`, `aoc_state` (`aoc_query=1`) | module |
| `aed858b94` arm64: dts: exynos: google: gs201: add the GSA mailbox | `gsa@17c90000`, SPI 363 | `disabled` |
| `372cdfcb5` merge of `omamobile-fingerprint` @ `5a9cf359f` | the Trusty driver commits, shared with fingerprint (same commits, so both branches merge into int together) | modules, node disabled |
| `477a82e16` arm64: dts: ... gs201: add Trusty | cherry-pick of `0c28d9948` (identical hunk; merges cleanly with fingerprint) | `disabled` |
| `18c468053` dt-bindings: ... gs201-gsa: add the GSA's S2MPU | optional second range | - |
| `6b3275d37` soc: google: gsa: load and start AoC firmware | `gsa_load_aoc_fw_image()` (cmd 90 under a GSA wakelock, GSA S2MPU CTRL0 = 0 for the load and restored after, 32-bit DMA mask), `gsa_send_aoc_cmd()` (Trusty `hwmgr.aoc`, or cmd 91 with `aoc_cmd_mbox=1`), `gsa_get_device()`; debugfs `aoc_state_tz`, `s2mpu_ctrl0` (`s2mpu_probe=1`) | - |
| `36319e05e` arm64: dts: ... gs201: add the GSA's S2MPU range | `0x17c60000` | - |
| `d239d411e`, `2fcba2704` AoC System MMU binding and driver | `gs201-aoc-sysmmu.c` (`CONFIG_GS201_AOC_SYSMMU`): first-level table of 1 MiB sections from the windows it is given, VID 0, stall on fault, stock QoS/TLB setup, fault lines with VID and AxID; touches no register until the AoC driver calls it with BLK_AOC on; `empty=1` = negative test | module |
| `5caf0d303`, `0610de752` AoC binding and boot driver | `gs201-aoc-boot.c` (`CONFIG_GS201_AOC_BOOT`): debugfs `info`, `power`, `blk`, `load`, `start`, `control`, `shutdown` (section 7) | module |
| `3a71f0471` soc: google: add the gs201 AoC supplies over ACPM | `gs201-aoc-rails.c` (`CONFIG_GS201_AOC_RAILS`): reads S2MPG12/13 CHIPID and the five LDOs; sets their enable bits only with `enable=1`, never a voltage | module, no DT |
| `973b54b71` arm64: dts: ... gs201: add the AoC and its System MMU | `sysmmu@1a090000` (SPI 118), `aoc@181d0000` | `disabled` |
| `0e5c2082d`, `edfb4e5df`, `aa453aaee`, `c868f906b` C4b diagnostics | System MMU "lost" check and reprogram, VID 0 fault registers in the dump; the AoC node gains the PCU (`0x19a00000`) and the watchdog interrupt (SPI 116); the boot driver logs S2MPU, PCU reset control, System MMU, IPC words and ramdump breadcrumbs around `START`, re-applies a cleared S2MPU/System MMU setup first (`reapply=1`), and gains `cmd` (any GSA AoC command) and `ramdump` (hex dump) | - |
| `01be75e8a`, `d9cc04ae4`, `7bea582c5` AoC mailbox view | the AoC node gains the three mailbox ranges; debugfs `mbox` (and `diag_mbox=1` around start) reads masks, raw status and shared registers, AP side | - |
| `deb7b47bd` gate the PCU read, no lock in read-only views | after the PCU read aborted (C4b-2 first try) | - |
| `2f785843b`, `615b5188a` unload | `gsa_unload_aoc_fw_image()` (cmd 92 or Trusty `UNLOAD_IMG`); debugfs `unload` (shutdown, unload, System MMU off, as `aoc_take_offline()`) | - |

Build in `out-aoc`: release `7.3.0-rc6-omamobile-push1-00079-g615b5188a148`
(kernel, modules tarball, images). The new C files build with `W=1` and no
warnings and pass `checkpatch.pl`; the DTB has only the existing framebuffer
`unit_address_vs_reg` warning; both overlays apply with `fdtoverlay`. Not
run: `dt_binding_check` (no dtschema on this host).

**Module dependencies:** with `CONFIG_GOOGLE_GSA_TRUSTY=y`, `gsa.ko` needs
the Trusty modules, so `modprobe gsa` also loads `trusty-core`,
`trusty-virtio` and `trusty-ipc` (a blacklist does not stop dependencies).
With the `/trusty` node disabled, as in all AoC overlays, they bind to
nothing and never call into the secure world.

Repo:

- `kernel/configs/omamobile.config`: `CONFIG_GOOGLE_GSA=m`,
  `CONFIG_GOOGLE_GSA_TRUSTY=y`, `CONFIG_GS201_AOC_SYSMMU=m`,
  `CONFIG_GS201_AOC_BOOT=m`, `CONFIG_GS201_AOC_RAILS=m`.
- `device/cheetah/overlays/aoc-gsa-test.dtso` (C1), `aoc-boot-test.dtso`
  (C2-C4: GSA, AoC System MMU, AoC node with cheetah's board id `0x30301`
  and revision `0x10000`).
- `tools/aoc-stage`: runs C2-C4 with the log streamed to `logs/` first,
  optional hardware watchdog, the hang marker, `--pstore`.

---

## 6. Stages

| Stage | What | Writes to hardware | Risk | Needs |
|---|---|---|---|---|
| C0 | offline: firmware header, IOMMU windows, UUID check | none | none | **done** |
| C1 | GSA mailbox: `sjtag_status`, `aoc_state` (cmd 91) | mailbox only | low | **passed** |
| **C2** | read-only: `aoc_req` and acknowledge, GSA AoC state, chip id, GSA S2MPU CTRL0 (under a GSA wakelock), carve-out not System RAM; if BLK_AOC is on, the AoC System MMU registers (which VIDs exist, which are already on) and the AoC S2MPU CTRL0 | GSA wakelock commands | low | this branch, `aoc-boot-test` |
| C2p | only if C2 found BLK_AOC off: `aoc_req` = 1, then C2's reads | `aoc_req` | low | C2 |
| **C3** | read-only: S2MPG12/13 CHIPID and the five AoC LDOs over ACPM channel 2 | none | low | ACPM loaded (int) |
| **C4a** | load: power, AoC S2MPU CTRL0 = 0, System MMU windows on VID 0, body into the carve-out, GSA authentication (90), parameters; state must become "loaded" | S2MPUs, System MMU, carve-out | medium | C2, C3 |
| **C4b** | start: 91 `START`; control block within 5 s, ~82 services, no "blocked" lines | AoC runs | **high** (first run of the firmware) | C4a |
| C4c | `unload`, then C4a/C4b again: proves a clean restart | GSA | medium | C4b |
| C4n | negative test (separate boot): `gs201_aoc_sysmmu empty=1`, C4a, C4b: the AoC must fault at once with "blocked READ at 0x98..." on VID 0 and never come up; proves its traffic goes through this System MMU on VID 0 | as C4 | medium | C4b passed |
| C5 | AoC core port (mailboxes, services, char devices) | - | - | C4b |
| C6 | first sensor reading: `gs201_aoc_rails enable=1` (LDO7S then LDO5S), registry load, accelerometer samples; then rotation | PMIC LDO bits | medium | C5, USF client |
| C7 | microphones: mic rails, capture EP1 (PCM 8) | PMIC, AoC | low | C5, `aoc_alsa` |
| C8 | speaker protection (firmware and factory calibration on both amplifier DSPs), UCM2, PipeWire, still at the C7 limits (digital ≤ 657, analog ≤ 10). First sound itself came in C7d-6 | amps, AoC TDM | medium | C7d-6, `AUDIO-PLAN.md` A7 |
| C8f | the amplifiers across idle: no runtime hibernate (kernel `cirrus,dsp-no-hibernate`, service holds them awake), health check before unmute, restart = rebind, watchdog | amps | low | C8 |
| C9 | stock gains under protection (`speaker_protection=1`: analog 17, digital 817), VMON/IMON slots, earpiece (Voice Call verb) | amps | **speaker damage** if protection is not really running | C8 |
| C10 | crash recovery: ACPM ch 13 doorbell, AoC watchdog | AoC PCU watchdog | medium | C5 |

The order inside C4 follows stock (section 0.1). C4n comes after a working
C4b on purpose: before the firmware runs there is no AoC traffic to test,
and a firmware that runs with a wrong VID would reach physical memory
untranslated. If C4b shows "blocked ... VID n" with n not 0, stop: rerun C4
with `gs201_aoc_sysmmu vids=<1<<n>` after a reboot.

---

## 7. Runbook

From the omamobile repo, phone in Arch over USB. Overlays as in
`HAPTICS-TORCH-PLAN.md` 4. **Never use `devmem` for any of this.** The
phone's `/usr/local/bin/devmem` is our `tools/devmem.c`, with usage
`devmem ADDRESS [VALUE]`: a second argument WRITES (`devmem ADDR 32` writes
0x20). All AoC registers are read from the kernel; PMU registers must not be
read from user space at all (`GPU-PLAN.md` incident).

### C1: GSA mailbox status queries (read-only): passed

Overlay `aoc-gsa-test`, `modprobe gsa` then `cat
/sys/kernel/debug/17c90000.gsa/sjtag_status`, and `modprobe gsa aoc_query=1`
then `cat …/aoc_state`. Results in section 0.1.

### Build and install for C2-C4

On the integration kernel (merge `omamobile-aoc` again: it now carries the
Trusty commits, the System MMU, boot and rails drivers):

```sh
export KERNEL_DIR=$HOME/android/mainline/wt-int KERNEL_OUT=$HOME/android/mainline/out-int
O=$KERNEL_OUT D=$O/arch/arm64/boot/dts/exynos/google/gs201-cheetah.dtb
git -C $KERNEL_DIR merge --no-edit omamobile-aoc
bin/omamobile kernel && bin/omamobile modules && bin/omamobile initramfs && bin/omamobile images
tools/phone-ssh 'printf "blacklist gsa\nblacklist gs201_aoc_sysmmu\nblacklist gs201_aoc_boot\nblacklist gs201_aoc_rails\n" > /etc/modprobe.d/omamobile-aoc-bringup.conf'
cp "$D" "$D.default"
$O/scripts/dtc/dtc -q -I dts -O dtb -o out/aoc-boot-test.dtbo device/cheetah/overlays/aoc-boot-test.dtso
$O/scripts/dtc/fdtoverlay -i "$D.default" -o "$D" out/aoc-boot-test.dtbo   # add display-decon-test etc. as usual
bin/omamobile images && bin/omamobile modules-push && bin/omamobile push
tools/phone-ssh 'lsmod | grep -cE "^(gsa|gs201_aoc|trusty)"'     # expect 0
```

Rollback for every stage below: reboot (nothing persists; the PMIC keeps a
rail that C6 turns on until a cold boot), or the default DTB:
`cp "$D.default" "$D"; bin/omamobile images && bin/omamobile push`.

### C2: read-only probes

```sh
tools/aoc-stage --watchdog c2
```

- **Does:** loads `gsa aoc_cmd_mbox=1 s2mpu_probe=1` (pulls in the Trusty
  modules, which bind to nothing), `gs201_aoc_sysmmu`, `gs201_aoc_boot`.
  None of them touches an AoC register at probe. Then reads: `aoc_req` and
  `aoc_req + 0x40` (acknowledge), GSA AoC state (cmd 91), the chip id block,
  the GSA S2MPU CTRL0 (GSA wakelock acquire, read, release), the carve-out
  check against `/proc/iomem`. Then `blk`: only if the acknowledge is set,
  the AoC System MMU registers and the AoC S2MPU CTRL0.
- **Expect:**
  - `gsa aoc state 0 (inactive)`;
  - `chip product 0x9855000`, `revision 0x10` (stock: "CPU[GS201]B0
    CPU_REV[0x10]", `R/dmesg.txt:397`), board `0x30301/0x10000`;
  - "carve-out 94000000-96ffffff: not System RAM";
  - GSA S2MPU `CTRL0 0x…` (record it; bit 0 set = blocking);
  - `aoc_req`/ack: record both. If BLK_AOC is on, the kernel log has
    `blk: version 0x… (v8.x) … capa1 0x… (8 VIDs)` and one line per VID:
    **record which VIDs are enabled and their table addresses**. All VIDs off
    (ctrl bit 0 = 0) is expected before the AoC was ever loaded.
- **Stop:** any abort or hang (the watchdog resets the phone; then
  `tools/aoc-stage --pstore`); a `blk` line on a VID with a table already
  set (someone else programs this System MMU: report it before C4); the
  carve-out overlapping System RAM.
- **If BLK_AOC is off:** run `tools/aoc-stage --watchdog c2p` (one write:
  `aoc_req` = 1, then the same reads). Expect `aoc_req 1: ack 0x1`. A
  time-out ("aoc_req 1: ack 0x0 (timed out)") is a stop: the APM did not
  power the block.

### C3: the AoC rails, read-only

```sh
tools/phone-ssh 'lsmod | grep -c "^acpm_protocol"'   # 1 on int (the GPU uses ACPM)
tools/aoc-stage c3
```

- **Expect:** `S2MPG12 CHIPID 0x…` and `S2MPG13 CHIPID 0x…` (non-zero, not
  equal), then five lines `LDO… : ctrl 0x…, on|off, N mV`. Expected
  voltages: LDO20M, LDO19S, LDO20S and LDO7S 1800 mV (vsel `0x2c`), LDO5S
  2500-3300 mV. The stock DT marks the sensor rails `regulator-boot-on`, so
  LDO7S and LDO5S are probably on already; record the mic rails.
- **Stop:** an ACPM error or timeout; a voltage outside the stock ranges
  (the rail is then never enabled by the driver).
- Nothing is written. Enabling (`modprobe gs201_aoc_rails enable=1`) comes
  in C6/C7, not now.

### C4a: load (the AoC stays in reset)

```sh
tools/aoc-stage --watchdog c4a
```

- **Does:** copies `V/firmware/aoc.bin` to `/usr/lib/firmware/updates/aoc.bin`
  if the phone's copy differs (it is Google's file: never commit or publish
  it), writes and syncs the hang marker, then `echo aoc.bin > load`:
  1. GSA state must be "inactive";
  2. validates the image (signed, superbin, `fw_start` = carve-out base,
     IPC offset, six windows);
  3. `aoc_req` = 1 and the acknowledge;
  4. AoC S2MPU CTRL0 = 0 (logged before and after);
  5. System MMU: the six windows on VID 0 (logged one per line, then the
     registers again);
  6. copies the 21 MB body to `0x94000000`;
  7. GSA load (cmd 90): wakelock, GSA S2MPU CTRL0 = 0, load, CTRL0 restored,
     wakelock released;
  8. writes the parameter block at carve-out + `0x1600000`.
- **Expect:** "image 14022723-polygon (release), body 0x… bytes at
  0x94000000, IPC at +0x1600000, 6 windows"; "cmd 90: answer 0x8000005a err
  0"; "loaded; GSA AoC state 1 (loaded)".
- **Stop:**
  - `cmd 90 … err 1` (invalid args: the header address or the S2MPU),
    `err 2` (authentication failed: wrong or modified image);
  - "no answer in 10000 ms" (the GSA mailbox is then disabled until
    reboot);
  - a System MMU fault line already now (the AoC is still in reset and must
    not access anything).
  Report the log and reboot. The marker stays, so `c4a` refuses to run again
  until you have rebooted and removed `/var/lib/omamobile/aoc-bringup-started`.
- **Never** read the carve-out (`0x94000000`-`0x955fffff`) after this step:
  the GSA has locked it.

### C4b: start

```sh
tools/aoc-stage --watchdog c4b
```

- **Does:** power request, cmd 91 `START`, then polls the control block at
  carve-out + `0x1600000` for magic `0xa0c00a0c` (5 s), prints the firmware
  version and the service list, counts "blocked" lines.
- **Expect:** "AoC command 1: GSA state 2 (running)"; "firmware up: 82
  services" (stock: 82, `R/dmesg.txt:6042`); `control` shows `fw
  14022723-polygon` and names such as `audio_output_control`,
  `com.google.usf`, `com.google.chre`; **0 "blocked" lines**. The hang
  marker is removed.
- **Stop:**
  - any "blocked READ/WRITE at … (VID n …)": note n and the address, then
    `tools/aoc-stage stop`. With n other than 0, see section 6;
  - "no control block after 5 s": the firmware did not come up; `stop`,
    then report the log;
  - a hang: the watchdog resets the phone; `tools/aoc-stage --pstore`.
- The AoC now runs without its AP-side services (no mailbox driver yet): it
  may log nothing or wait for the AP. Leave it running at most a few minutes,
  then `tools/aoc-stage stop` (`GSA_AOC_SHUTDOWN`, expect "state 1
  (loaded)"), or reboot.

### C4b-2: diagnose the start (one boot)

**First try (int 00214, `c868f906b`): synchronous external abort** in
`aoc_diag+0xdc` during C2's `blk` read. `llvm-objdump` puts `+0xdc` on the
load from `ab->pcu + 0`: the **PCU at 0x19a00000 aborts** with BLK_AOC on
and the AoC in reset (the S2MPU and System MMU reads just before it were
fine, as in the first C2). The `blk` task died holding the driver's lock,
so load and start blocked. Fixed in `deb7b47bd`: the PCU is read only with
`diag_pcu=1` from its own `pcu` file, the ramdump header only with
`diag_ramdump=1` or from the `ramdump` file, the System MMU fault registers
only with `gs201_aoc_sysmmu dump_faults=1`; read-only views take no lock,
and optional reads around start run outside it. `blk` and the start
diagnostics now read only what has already read fine on the phone.

Rebuild int with `omamobile-aoc` @ `deb7b47bd` (merge again) and push as
before, same overlay. Then:

```sh
tools/phone-ssh 'rm -f /var/lib/omamobile/aoc-bringup-started'
tools/aoc-stage --watchdog c2
tools/aoc-stage --watchdog c4a
tools/aoc-stage diag          # after the load, before the start
tools/aoc-stage --watchdog c4b
tools/aoc-stage diag
```

Read, in the kernel log (prefixed blk/before/after/5 s):

- `aoc s2mpu CTRL0`: 0 after our load, or 0x5 again (a block reset).
- the System MMU lines: global ctrl bit 0 and VID 0 ctrl bit 0 set, table at
  our address, `int` status.
- "AoC S2MPU CTRL0 is 0x… again, setting 0" or "System MMU setup was
  cleared, programming it again": printed by the re-apply before `START`.
- `ipc …`: 0a0cda7a … (our parameters) or a0c00a0c … (the firmware's).
- "AoC watchdog interrupt": the firmware ran and stopped.

Then the ramdump header, one read on its own (never read before; it is
ordinary DRAM outside the locked body, and Google's driver reads it after a
crash):

```sh
tools/aoc-stage --watchdog ramdump
```

- **Expect:** a hex dump. "AOCDUMP" at offset 0 and non-zero words at 0x318
  (the breadcrumbs) mean the firmware ran; all zeros mean it never wrote
  there.
- **Stop:** an abort (the watchdog resets the phone): the region is
  protected; never read it again.

Then, only if `START` gave state 4 and nothing came up:

```sh
tools/aoc-stage --watchdog release    # GSA_AOC_RELEASE_RESET (5)
tools/aoc-stage diag
tools/aoc-stage stop
```

- **Expect (if this is it):** state 2 (running), "firmware up: 82 services".
- **Stop:** any "blocked … VID n", the watchdog interrupt, or an unexpected
  state (record it). `stop` returns the AoC to "loaded"; a reboot clears
  everything.

The PCU stays unread: it aborts with the AoC in reset. If everything above
is inconclusive, a later step reads it once **after** a start that left
state 4, with `echo 1 > /sys/module/gs201_aoc_boot/parameters/diag_pcu`
and `cat /sys/kernel/debug/aoc/pcu`, armed watchdog, as the last action of
a boot.

Send the logs (`logs/aoc-*-diag.log`, `-c4b.log`, `-ramdump.log`,
`-release.log`).

### C4t: start through Trusty (passed 2026-10-12; see the Checkpoint and NOTES.md)

Rebuild int with `omamobile-aoc` @ `7bea582c5` (merge again; adds the
mailbox view) and push with **both** overlays, `aoc-boot-test` and
`fingerprint-trusty` (enables `/trusty`), plus the usual ones. The Trusty
modules stay blacklisted (`omamobile-fingerprint.conf`, or add
`blacklist trusty_core/trusty_log/trusty_ipc/trusty_virtio` to
`omamobile-aoc-bringup.conf`). Note: `modprobe gsa` loads `trusty_core` and
`trusty_ipc` as dependencies, so load Trusty first, on purpose.

```sh
tools/phone-ssh 'rm -f /var/lib/omamobile/aoc-bringup-started'
tools/aoc-stage --watchdog trusty        # FINGERPRINT-RESEARCH.md F2, the first SMCs into Trusty
tools/aoc-stage --watchdog --trusty c2   # gsa without aoc_cmd_mbox: state via hwmgr.aoc
tools/aoc-stage mbox                     # baseline: AoC mailboxes, AP side (read-only)
tools/aoc-stage --watchdog c4a           # load: mailbox 90, as stock
tools/aoc-stage --watchdog c4b           # START through Trusty hwmgr.aoc
tools/aoc-stage diag; tools/aoc-stage mbox; tools/aoc-stage ramdump
tools/aoc-stage stop                     # SHUTDOWN through Trusty (back to "loaded")
```

- **trusty, expect** (stock `R/dmesg.txt:737-890`): "trusty version:
  Project: cloudripper …", "selected api version: 5" (or lower),
  `/dev/trusty-ipc-dev0`, "trusty_ipc virtio0: is online".
  **Stop:** a hang (watchdog), "failed" lines, no `trusty-ipc-dev0`.
- **c2 --trusty, expect:** `gsa aoc state 0 (inactive)` through Trusty;
  dmesg "TZ: com.android.trusty.gsa.hwmgr.aoc connected" (stock prints the
  same, `R/dmesg.txt:5886`). **Stop:** "TZ: connect failed" (the service is
  not there: report).
- **c4a, expect:** as before, state 1 (loaded).
- **c4b, expect:** "AoC command 1 (Trusty): 2", "GSA state 2 (running)",
  then "firmware up: 82 services", `control` with `fw 14022723-polygon`.
  `mbox` may show bits in `intsr1` (the AoC's doorbells) and the ramdump
  header may gain breadcrumbs. **Stop:** state 4 again (then the secure
  setup is not the answer: report), any "blocked" line, the watchdog
  interrupt.
- If it comes up but stalls later, or does not come up with Trusty: C4b-3
  below, with the rails on before the load.
- Rollback: `tools/aoc-stage stop`, or reboot.

The mailbox view (`mbox`) has not been read on the phone yet: it reads the
AP side of three APM-domain mailboxes, the same kind of block as the
AP-to-APM mailbox ACPM uses every boot. If it aborts, drop it (the
watchdog resets the phone).

### C4b-3: rails first (separate boot, if C4t starts the A32 but no control block appears)

```sh
tools/phone-ssh 'rm -f /var/lib/omamobile/aoc-bringup-started'
tools/aoc-stage --watchdog trusty
tools/aoc-stage --watchdog --trusty c2
tools/aoc-stage rails         # LDO7S, LDO5S and the mic LDOs on, stock voltages
tools/aoc-stage --watchdog c4a
tools/aoc-stage --watchdog c4b
tools/aoc-stage diag; tools/aoc-stage mbox
```

- **Expect:** "LDO… : enabled, ctrl now 0xac" (LDO7S; LDO5S 0xbc, the mic
  rails 0xec), then the read-back "on". Rails stay on until a cold boot
  (stock keeps them on all the time).

### C4c: clean restart (optional, after C4b)

```sh
tools/phone-ssh 'echo 1 > /sys/kernel/debug/aoc/unload; cat /sys/kernel/debug/aoc/info'
tools/phone-ssh 'rm -f /var/lib/omamobile/aoc-bringup-started'
tools/aoc-stage --watchdog c4a && tools/aoc-stage --watchdog c4b
```

- **Expect:** "AoC unload (mailbox): 0", "unloaded; GSA AoC state 0
  (inactive)", then the same C4a/C4b results as the first time.
- **Stop:** unload refused or failing: reboot instead.

### C4n: negative test (separate boot, after C4b passed)

```sh
tools/phone-ssh 'modprobe gsa aoc_cmd_mbox=1 s2mpu_probe=1; modprobe gs201_aoc_sysmmu empty=1; modprobe gs201_aoc_boot'
tools/aoc-stage --watchdog c4a && tools/aoc-stage --watchdog c4b
```

- **Expect:** "empty table: every AoC access will fault"; C4a as before (the
  AoC is in reset); C4b: "blocked READ at 0x98…" or similar on **VID 0**
  right after `START`, and "no control block after 5 s". That proves the
  AoC's traffic goes through this System MMU on VID 0.
- Then `tools/aoc-stage stop` and reboot.
- **Stop:** the firmware comes up anyway, with no "blocked" lines: its
  traffic does not go through VID 0 of this System MMU. Do not run the AoC
  again until that is understood.

---

## 8. Open questions

1. Is BLK_AOC on at hand-off (C2 `aoc_req` acknowledge)?
2. Which System MMU VIDs exist and are any already programmed (C2 `blk`)?
   Expect 8 VIDs (VM support), all off, and AoC traffic on VID 0 (C4n).
3. Who programmed `sysmmu_asoc` on stock? Older Google AoC drivers map the
   same windows into the AoC's IOMMU domain from the kernel, so the
   non-secure table is the one that matters; C4b confirms it.
4. GSA and AoC S2MPU CTRL0 at hand-off (C2): blocking (bit 0 set) is
   expected for the GSA one.
5. Are the mic LDOs on at hand-off (C3)? The sensor LDOs are
   `regulator-boot-on` in the stock DT.
6. Does the firmware need anything from the AP before it publishes its
   control block (C4b without a mailbox driver)?
7. Is the factory sensor calibration in `persist:/sensors/registry` intact
   on this phone (read-only, as `speaker.cal` was read)?
