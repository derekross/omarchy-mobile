<!-- SPDX-License-Identifier: MIT -->
# Sensors plan (hotdog / SM8150): ambient light and proximity through the SLPI

**Status (2026-11-18): ambient light works, and the screen turns off at
the ear in calls; on `boot_a`, slot A marked.** The SLPI starts from the
device tree and the fastrpc fix is in the kernel; the TCS3701's light reaches
iio-sensor-proxy from boot (`monitor-sensor --light`: about 700-1,300 lux
indoors, 100 covered, 12,300 at a lamp). The TCS3701's proximity is listed
by the SSC but never reports: OnePlus's SLPI firmware switches it off on
this project (§1). Proximity comes from the touchscreen's ear mode instead
(§5): an `SW_FRONT_PROXIMITY` switch on the touch driver, which
`omamobile-call-proximity` (omamobile-shell 0.2.135) holds open in calls.
Userspace: device-hotdog 0.1.18, hexagonrpc 0.5.0.r20.gda7a374-2, Arch Linux
ARM's libssc 0.4.4 and iio-sensor-proxy 3.9. Kernel branch
`omamobile-hotdog-sensors` (worktree `~/omamobile-kernel/wt-hotdog-sensors`,
output `~/omamobile-kernel/out-hotdog-sensors`), five commits on
`omamobile-hotdog-haptics` @ `3ae752f99c6a`; `boot_a` =
`7.3.0-rc6-omamobile-push1-g7539ca3e06f6`
(`~/omamobile-kernel/boot-prox-g7539ca3e06f6-2026-11-18.img`, sha256
`2920917b…5f86`; rollback `boot-haptics-g3ae752f99c6a-2026-11-18.img`).

**Goal.** iio-sensor-proxy's `net.hadess.SensorProxy` reports the light
level (and proximity, where there is one), so the shell and apps using that
API see them.

## 1. Facts

| What | Source |
| --- | --- |
| The phone's sensors (light, proximity, accelerometer, compass) are not wired to Linux: they hang off the SLPI's own buses and are driven by Qualcomm's Snapdragon Sensor Core (SSC) in the SLPI's `sensor_process` PD, which serves them over QMI (QRTR service 400) | stock vendor `/etc/sensors` (the HAL is `sensors.ssc.so`) |
| The SLPI firmware on the phone is `SLPI.HY.2.2-00083-SM8150AZL-1` with OnePlus's 2021-01-27 build; the `dsp_a` partition's `/sdsp` and the vendor image's `/etc/sensors` are from the same build | `strings` of `slpi.mbn` on the phone and of the owner's OxygenOS image |
| The sensors PD reads at start, over FastRPC: `sns_reg_config` (`/vendor/etc/sensors/`), the JSON driver configs (`/vendor/etc/sensors/config`, 61 files: every ALS/proximity variant OnePlus fitted; the PD probes them), its registry (`/mnt/vendor/persist/sensors/registry/registry`) and `/sys/devices/soc0/{hw_platform,soc_id,...}`, which the JSON filters match (`MTP`, `339`) | `sns_reg_config`; JSON `config` blocks |
| `persist:/sensors/registry/registry` holds stock's parsed registry, with this phone's factory calibration (`*.fac_cal`) | `debugfs` read of the 2026-11-14 persist backup |
| SMEM platform 8 (MTP), subtype 0, version 65536; mainline's soc0 has `soc_id` 339 and `revision` 2.2 but no `hw_platform` | `/sys/kernel/debug/qcom_socinfo`, `/sys/devices/soc0` |
| `vendor_a` is one linear extent in `super`; `persist`, `dsp_a` and `super` read `ro` 1 under the storage guard | LP metadata, read on the phone |
| Without a file server the PD stalls ("USER-PD DOG detects stalled initialization") and its watchdog restarts the SLPI about 40 s after boot | BRINGUP notes in `sm8150-oneplus-hotdog.dts`, 2026-11 |
| Without a `sleepstate` outbound smp2p entry the sensors PD's CHRE takes a fatal error | SDM670 ADSP series (R. Acayan, v2 07/11, 2026-10-03); the Pixel 4 XL bring-up (coral, same SoC) |
| The SDSP sends the context bank's SID in address bits 32+ and the SMMU translates the whole address: with mainline's fastrpc (IOVA below 4 GiB, SID added on top) the first access faults, `iova=0x1fffff000, cbfrsynra=0x5a1`, and `sensor_process` crashes (`frpck_0_0`) | S3a, 2026-11-18 |
| An address below 4 GiB without the SID (the coherent DMA mask left at 32 bits) is not an SMMU fault but an interconnect error: the modem's `wlan_process` reports `NOC_error.c:357` and the SoC goes to crash-dump mode | S3c and the first S5, 2026-11-18 |
| The light and proximity chip is an ams TCS3701 (I2C on the SSC's bus 3 at 0x39): light polled at 5 Hz, proximity interrupt-driven on TLMM GPIO 117 (`is_dri` 1, PDC input 85). With proximity enabled (on-change or at a forced 5 Hz) the SSC sends nothing, and GPIO 117 stays high while the sensor is covered: the chip never raises a proximity interrupt | `ssccli -v`, `/sys/kernel/debug/gpio`, 2026-11-18 |
| OnePlus's SLPI firmware: `sns_tcs3701_sensor_island.c: TCS3701 PROX: soft screen project disable prox sensor`; the TCS3701 HAL also takes the display's brightness, refresh rate and DC mode from OnePlus's HAL. It reads the project from `/sys/project_info/project_name` (19801, `androidboot.project_name`); serving 19801 or the OnePlus 7T's 19811 changed nothing | firmware strings; S3e |
| Stock's proximity on this phone is not the TCS3701: `init.oem.rc` "add for tp and ultrasound proximity", `/dev/sensor_ultrasound`, `/dev/audio_ultrasound` (an ultrasound virtual sensor on the audio DSP, and the touchscreen) | owner's OxygenOS vendor image |
| The touchscreen (S6SY761 on I2C 4-0048, firmware 10 64 08 04, 17 TX x 37 RX lines, 1440 x 3120) rejects a face: with an ear or cheek on the glass it sends almost no touches, only vendor status events (`1d 69 01`/`00`, toggling while the contact moves) and wet-mode events (`09 01 01`/`00`) that mainline's driver drops. Silent while the face is still, so they are no proximity signal | debug driver, ear test A, 2026-11-18 |
| Stock's call mode ("earsense"): `0xEE` = 1 (hover detect) and `0x70` = 0x3c (delta), then the delta map is read with `0x75` (length, big-endian) and `0x76`; OnePlus's userspace decides near/far from it. In that mode the chip sends no interrupts while a face is near | OnePlus's GPL touchscreen driver (`oplus_touchscreen/Samsung/S6SY761`); ear tests B and C |
| The delta map in ear mode (1,258 bytes, big-endian s16, top of the phone first): sum of positive nodes 600-750 with nothing near (max under 25); 7,000-16,000 at the ear without the cheek touching (25-75 nodes above 50, all in the top third); 40,000-63,000 with the cheek pressed (200-285 nodes above 50); back to idle at once when the phone comes away. Without `0xEE` the map reads all zero | ear test C, 2026-11-18 |
| The sensors PD tries to write its registry back (`temp.json`) about 2,500 times in the first second after every start; hexagonrpcd refuses each | S3e |

## 2. Design

```
SLPI (remoteproc, slpi.mbn) --glink "dsps"--> fastrpc /dev/fastrpc-sdsp
  sensors PD <--FastRPC file reads-- hexagonrpcd -s -R /var/lib/omamobile/sensors/root
  SSC (QMI svc 400 over QRTR) <-- libssc <-- iio-sensor-proxy (ssc-light)
                                              --> net.hadess.SensorProxy (system bus)
```

- **Kernel** (`omamobile-hotdog-sensors`):
  - `misc: fastrpc: Keep the SM8150 SDSP's IOVAs in the session's window`:
    for the SDSP on SM8150 the context bank's DMA mask is
    `(sid << 32) + 0xf7ffffff`, so IOVAs come from that window (downstream
    maps each SDSP bank at `0x80000000 + (cb << 32)`), and the address goes
    to the DSP unchanged.
  - `arm64: dts: qcom: sm8150-oneplus-hotdog: Enable the SLPI`: the SLPI on,
    and the `sleepstate` entry under `smp2p-slpi` (nothing drives it).
- **hexagonrpc** (new package `packages/hexagonrpc`, upstream `da7a374` plus
  dodge's fix that keeps the listener serving after an unsupported call).
- **libssc, iio-sensor-proxy**: Arch Linux ARM's (iio-sensor-proxy 3.9 is
  built with SSC support there).
- **device-hotdog 0.1.16**:
  - `omamobile-hotdog-sensors-root` builds the served directory once, from
    the phone's own partitions, read-only: `persist` and `dsp_a` with
    `debugfs -c` on their read-only block devices (never mounted),
    `vendor_a` through a read-only loop device over its extent in `super`;
    `socinfo/` from SMEM (`MTP`). Under `/var/lib/omamobile/sensors` (0700);
    it holds this phone's calibration and is never shipped or committed.
  - `omamobile-hotdog-sensors.service`: hexagonrpcd, wanted by udev when
    `/dev/fastrpc-sdsp` appears and bound to it, so it follows SLPI
    restarts; `Restart=on-failure` covers the node appearing before its
    sessions (`open`: EBUSY). Its `ExecStartPost` waits for the SSC to
    answer (`ssccli --sensor light`) and restarts iio-sensor-proxy, which
    looks for SSC sensors only when it starts.
  - `81-omamobile-hotdog-sensors.rules`: the udev wants above. Proximity
    is not tagged for iio-sensor-proxy (§1): a claim would time out after
    25 s, and the shell's double-tap guard claims proximity when it is
    offered.
  - hexagonrpc serves `/sys/project_info/project_name` too (OnePlus's
    firmware reads it); the root builder writes it from
    `androidboot.project_name`.
  - `systemctl mask omamobile-hotdog-sensors` keeps it off.
- Nothing writes `persist`: hexagonfs refuses writes from the DSP, and it
  serves a copy anyway.

## 3. Runbook

Every step is the owner's go. Bring-up files on the phone (remove after
S6): `/root/sensors/` (the overlay module, a patched `fastrpc.ko`, the
first copy of the root script), `/usr/lib/firmware/omamobile/sensors/slpi.dtbo`;
both built in `~/omamobile-kernel/ext-sensors` against `out-hotdog-haptics`.

**S0. Userspace (phone, no hardware).** `tools/phone-install-package
packages/hexagonrpc`; `pacman -S --needed libssc iio-sensor-proxy` (from
the phone's sync database, no `-Sy`). Risk: low.
*2026-11-18: done. iio-sensor-proxy started from the ADSP's FastRPC node's
udev tag, found no sensors and exited, as expected.*

**S1. Served root (read-only).** `omamobile-hotdog-sensors-root`. Pass:
`registry/`, 61 configs, `dsp/sdsp/` (18 files), `socinfo/` reads
`MTP`/`339`/`2.2`; `persist`, `dsp_a` and `super` still `ro` 1; no loop
device left. *2026-11-18: pass.*

**S2. Overlay (laptop).** `slpi.dtso` (`sleepstate` under `/smp2p-slpi`,
`/soc@0/remoteproc@2400000` okay) and `omamobile_dtoverlay.ko`. smp2p reads
its entries only at probe, so the step unbinds `smp2p-slpi` before the
overlay and binds it after. *2026-11-18: built.*

**S3. SLPI from the overlay, kmsg streamed to the laptop.** Risk: medium (a
crashing SLPI could end in crash-dump mode: Power held about 20 s).
- *S3a (2026-11-18, mainline fastrpc): the SLPI booted in 0.1 s. hexagonrpcd
  opened the node before its sessions probed ("No session available",
  EBUSY); started again 13 s later, its first call faulted in the SMMU
  (§1) and `sensor_process` crashed; the SLPI recovered by itself. `rmmod
  omamobile_dtoverlay` stopped it cleanly; modem, ADSP and CDSP unaffected.*
- *S3b (2026-11-18, swapping in the patched `fastrpc.ko`): **don't do this.** `rmmod
  fastrpc` closed the ADSP's and CDSP's FastRPC channels, and neither DSP
  answered sysmon or glink SSR afterwards (`timeout waiting for subsystem
  event response`, `intent request timed out`); the SLPI's start then timed
  out (`-110`) and SLIMbus's power request to the ADSP failed, so the phone
  had no audio until a reboot. Never unload fastrpc while the ADSP or CDSP
  runs; test a fastrpc change by booting a kernel with it.*

- *S3c (2026-11-18, after a Sahara reset to `boot_a` and a reboot with
  `/etc/modprobe.d/omamobile-sensors-hotdog-bringup.conf` loading the
  patched module at boot): crash-dump mode 0.15 s after the SLPI came up,
  `wlan_process` `NOC_error`. The module raised only the streaming DMA mask;
  `dma_alloc_coherent()` buffers stayed below 4 GiB and went to the DSP
  without the SID. Fixed with `dma_set_mask_and_coherent()` and a check that
  refuses any buffer or mapping outside the window.*
- *S3d/S3e (2026-11-18, the fixed module, the same way): the SLPI up,
  hexagonrpcd attached from `omamobile-hotdog-sensors.service`, no fault in
  over an hour; the light results in the status line. An SLPI restart
  through `/sys/class/remoteproc/*/state` stop/start brought everything back
  by itself (the unit follows the node). Proximity: §1.*

Crash-dump mode (`05c6:900e`) needs no buttons: the Sahara memory-debug
session reads the ramoops console (`KMSG.txt` at `0xa997f008`) and a Sahara
reset reboots the phone ([SUSPEND-PLAN](SUSPEND-PLAN.md)).

**S4. Build (laptop).** As [HAPTICS-PLAN](HAPTICS-PLAN.md) H4, with
`wt-hotdog-sensors`/`out-hotdog-sensors`, `kernel-camera.config` and
`kernel-voice.config` appended to a copy of `kernel.config` (restored
after), `DTB_OVERLAYS="mic torch camera popup camera-main camera-af voice"`
and `boot_a`'s command line (`clk_ignore_unused pd_ignore_unused panic=10
splash`) in device.conf for the build only.
*2026-11-18: the first build (`-g0b640949576d`) had the streaming-mask-only
fastrpc; its RAM boot ended in crash-dump mode when the modem powered up
(S3c's cause). Rebuilt with the fixed commit.* Pass: the overlaid DTB has
`/smp2p-slpi/sleepstate` and the SLPI `okay`; fastrpc builds without
warnings at `W=1`; checkpatch `--strict` shows only the missing
Signed-off-by.

**S5. Modules and RAM boot.** `DEVICE=hotdog KERNEL_OUT=~/omamobile-kernel/out-hotdog-sensors bin/omamobile modules-push`,
`systemctl reboot --reboot-argument=bootloader`, `fastboot boot
~/omamobile-kernel/out-hotdog-sensors/images/boot.img`. A RAM boot spends no
slot-A try. Before it, remove the bring-up modprobe line (the new kernel has
the fix in its own fastrpc). Risk: medium (a new kernel and a new DSP at
boot). Pass: Arch up as on `boot_a` (audio, cameras, fingerprint, modem,
keys, haptics); `slpi running`; `omamobile-hotdog-sensors` active with no
SMMU fault and no SLPI crash in 3 minutes; `monitor-sensor --light` follows
a hand over the top of the screen. Stop: no SSH in 2 minutes
(retry once), or SLPI crashes in a loop: `systemctl mask
omamobile-hotdog-sensors` and reboot (`boot_a` has no SLPI). Rollback: a
reboot.

**S6. Sleep.** `systemctl suspend` with iio-sensor-proxy holding no claim,
woken by the power key; then with a proximity claim held. Pass: it sleeps
(no wake from the SLPI with no claim) and the sensors answer after the
wake. Then flash `boot_a` as [KEYS-PLAN](KEYS-PLAN.md) K6, re-mark slot A
([BRINGUP-M1](BRINGUP-M1.md)), and remove the bring-up files.

## 4. Open

- **Proximity.** Not from the TCS3701 (§1). Stock uses an ultrasound
  virtual sensor (earpiece out, microphone in, a closed algorithm on the
  audio DSP behind downstream's `/dev/sensor_ultrasound`) and the
  touchscreen's ear mode. The ear mode works on mainline (§5); the
  ultrasound one would need the vendor's DSP module and driver.
- The accelerometer and compass are in the same SSC: auto-rotate would
  need `ssc-accel` tagged and the shell's rotation path on this phone.
- The registry is served read-only: calibration the SSC learns at run time
  is lost at its next start, and its write-back burst at every start is
  only rate-limited in the journal.
- `sleepstate` is never driven: the SSC always sees the APPS as awake.

## 5. Proximity from the touchscreen's ear mode

The phone has no proximity sensor Linux can use, but the touchscreen sees a
face up to about a centimetre above the glass in its ear mode (§1, ear test
C), which is what stock does in calls.

- **Kernel (s6sy761, `samsung,ear-detect`).** A second input device,
  "s6sy761 proximity", with `SW_FRONT_PROXIMITY`. Opening it turns the ear
  mode on and polls the delta map (every 100 ms, plus some 40 ms for the
  read); near at 50 nodes above 20 in the upper half, far after three polls
  under 10; closing it turns the mode off, so outside calls the controller
  runs as before. The whole map is read: after reads of only the upper half
  the controller kept returning the same snapshot. udev and logind open the
  new device for a moment when it appears; nothing keeps it open.
- **Shell (`omamobile-call-proximity`, omamobile-shell 0.2.135).** While a
  call is dialling, ringing out or active on the earpiece (omatel's agent
  through `omamobile-call-watch --observe`), it holds the switch (or
  iio-sensor-proxy's proximity on a phone with a sensor) open; near turns
  the panel off and grabs the touchscreen, far brings both back.
  `omamobile-keys dark-unlocked` leaves the phone unlocked while that blank
  is up.

Results, 2026-11-18:

- Test module on `7.3.0-rc6-omamobile-push1-g3ae752f99c6a` (reloaded by
  hand): one finger tapping and swiping on the upper half for 15 s, at most
  12 nodes (far); ear: near within one poll (213-276 nodes); cheek likewise;
  far within a second of taking the phone away. A hand 2 cm above the glass
  reads nothing.
- Flashed to `boot_a` (`g7539ca3e06f6`), slot A marked (GPT `3466da83…` ->
  `361c9ccc…`, dump in `~/android/reference/hotdog/gpt/`): SLPI, ADSP, CDSP
  and modem running, light from boot, both input devices present, no failed
  unit; the ten early SMMU context faults at 1.35 s are on every earlier
  boot too. A real call on the earpiece: the screen went off at the ear and
  came back when the phone was taken away (owner).
- Bring-up files removed from the phone: the fastrpc modprobe line,
  `/root/sensors/`, `/usr/lib/firmware/omamobile/sensors/`, the test
  modules.

Open: a touch the face starts before the grab may stay down in the
compositor until the next touch (not seen); the in-call keypad is far by the
finger test above, but not measured with the panel off.
