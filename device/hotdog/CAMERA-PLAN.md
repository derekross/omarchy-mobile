<!-- SPDX-License-Identifier: MIT -->
# Camera plan (hotdog / SM8150): four cameras, the pop-up and the torch

**Status (2026-11-13): torch, all four sensors, focus and the GPU ISP work;
`boot_a` carries them** (`7.3.0-rc6-omamobile-push1-g8da458f2d9a9`, §7). The
pop-up has not moved yet (P3-P5). The open work is in
[CAMERA-NEXT.md](CAMERA-NEXT.md). The kernel is the local branch
`omamobile-hotdog-int` (worktree `~/omamobile-kernel/wt-hotdog-int`, output
`~/omamobile-kernel/out-hotdog-int`): `omamobile-hotdog-af` (camera, C-PHY,
focus actuators, s5k3m5 crop) plus the mic commits. It is not pushed and has
no Signed-off-by yet. Overlays [`torch`](overlays/torch.dtso),
[`camera`](overlays/camera.dtso), [`camera-main`](overlays/camera-main.dtso),
[`camera-af`](overlays/camera-af.dtso), [`popup`](overlays/popup.dtso).
Pop-up tool and libcamera configuration in `packages/omamobile-device-hotdog`
0.1.6; sensor helpers and tuning in `packages/libcamera` 0.7.2-4.24; tables
tool [`tools/hotdog-camera-tables`](../../tools/hotdog-camera-tables).

**Goal.** The rear flash works as the shell's torch; the three rear cameras
and the front camera stream through libcamera (simple pipeline, software
ISP) into omacam; the front camera rises when it is opened and lowers when it
is closed.

```
sensor --CCI (I2C)-- control      CCI0/CCI1, 4 masters             i2c-qcom-cci
   \-- CSI-2 --> CSIPHY0-3 --> CSID --> VFE (RDI) --> /dev/videoN   qcom-camss (SM8150 series)
                                                                    + C-PHY on CSIPHY1 (main)
   /dev/videoN --> libcamera simple pipeline + software ISP --> omacam / PipeWire
torch:   PM8150L flash module, channels 1+2 --> white:torch          leds-qcom-flash
pop-up:  PM8150L LPG (STEP) + PMIC GPIOs --> DRV8834 --> stepper    omamobile-hotdog-popup
         M1120 hall sensors (0x0c top, 0x0d bottom) on QUP SE1     (userspace, i2c-dev)
```

---

## 0. Facts, from our own captures

From the owner's OxygenOS 10.0.14 image (decrypted under
`~/android/reference/hotdog/ops/extract`, vendor in `vendor-fp/`), never
committed: the boot image's base DTB (`SM8150 v2`), `dtbo.img` entry 18
("MTP 19801 MP 14 15", board-id <8 0>; OnePlus's camera fragment on
`cam_cci0` overrides Qualcomm's template, and the four `cam-sensor` nodes it
rewrites are this phone's), and the camera module files
`vendor/lib64/camera/com.qti.sensormodule.*.bin`, decoded by
[`tools/camx-sensormodule-decode`](../../tools/camx-sensormodule-decode)
(the file layout is in its header comment).

| | Main | Telephoto | Front (pop-up) | Ultrawide |
| --- | --- | --- | --- | --- |
| Sensor | Sony IMX586, ID 0x0586 @0x0016 | Samsung S5K3M5, ID 0x30d5 @0x0000 | Sony IMX471, ID 0x0471 @0x0016 | Sony IMX481, ID 0x0481 @0x0016 |
| Vendor slot | 0 (REAR) | 1 | 2 (FRONT) | 3 (REAR_AUX) |
| CCI / master / address | CCI0 / 1 / 0x1a | CCI0 / 0 / 0x10 | CCI1 / 0 / 0x10 | CCI1 / 1 / 0x1a |
| PHY | CSIPHY1, **C-PHY, 3 trios** (0x210) | CSIPHY0, D-PHY 4 lanes | CSIPHY2, D-PHY 4 lanes | CSIPHY3, D-PHY 4 lanes |
| MCLK | MCLK1, gpio14, 19.2 MHz | MCLK0, gpio13, 19.2 MHz | MCLK2, gpio15, 19.2 MHz | MCLK3, gpio16, 19.2 MHz |
| XCLR | gpio30 | gpio28 | gpio12 | gpio23 |
| Analogue | switch on gpio11, then switch on gpio29 | switch on gpio148 | switch on PM8150L gpio12 | switch on PM8150L gpio2 |
| Digital | PM8009 L1 1.104 V, then switch on PM8150L gpio1 | PM8009 L2 1.056 V | PM8009 L3 1.056 V | PM8009 L4 1.056 V |
| Interface | PM8150L L1 1.8 V | same | same | same |
| Power-up (vendor) | VANA, VANA2, VDIG, VDIG2, VIO, MCLK, RESET | VANA, VDIG, VIO, MCLK, RESET | same | same |
| Bayer, black level | RGGB, 64 | GRBG, 64 | BGGR, 64 | RGGB, 64 |
| Lens extras (not used) | AF + OIS | AF (VAF gpio35) + OIS | fixed focus | AF (AK7374, VAF PM8150L gpio4) |
| Mounting (roll / yaw) | 90 / 180 | 90 / 180 | 90 / 0 | 270 / 0 |

- The load switches are fed from BoB (the vendor tree's `cam_vana` is BoB at
  3.3 V plus a `gpio-vana`); their output voltage isn't written anywhere we
  can read.
- Every module variant (semco, ofilm, `_2nd_lens`, `_no_otp`) decodes to the
  same register tables for its sensor.
- **Modes we use** (register counts are the tables' sizes):
  - **IMX586:** init 1710 writes. 4000x3000@30.10, line length 7872, frame
    length 3695, 577.65 Mpix/s out, which is a C-PHY link frequency of
    421 203 125 Hz. 2000x1500@120.10, link 340 003 125. 8000x6000@28.3,
    link 1 166 396 875, not in the device tree.
  - **IMX481:** init 205. 4656x3496@30.14, line length 5120, frame length
    3566, link 659 200 000.
  - **IMX471** and **S5K3M5:** the mainline drivers' own tables,
    1928x1088 at 200 MHz (19.2 MHz MCLK) and 4208x3120 or 2104x1184 at
    602.5 MHz (24 MHz MCLK).
- **CCI and CAMSS addresses, interrupts and pins:** the base DTB's
  `cam_cci0` @0xac4a000 (SPI 460, gpio17-20) and `cam_cci1` @0xac4b000
  (SPI 271, gpio31-34). CSIPHYs are `qcom,csiphy-v1.1` @0xac65000-0xac68000
  with a 1.2 V supply (PM8150L L3), and the camera clock controller is
  `camcc-sm8150-v2`. The running kernel already builds `SM_CAMCC_8150` as
  a module.
- **Flash:** PM8150L flash module @0xd300; `flash_0` and `flash_1` (1500 mA
  maximum, 1000 mA default, 1280 ms), `torch_0` and `torch_1` (500 mA
  maximum, **300 mA default**). Stock drives both through `switch_2`
  (mask 0x3), and channel 2 is disabled.
- **Pop-up:** a DRV8834 stepper driver at 1/32 microsteps with two MagnaChip
  M1120 hall sensors.
  - Pins:
    - STEP is PM8150L GPIO10 in `func1`, the LPG channel at 0xbd00
      (`pwm 4`).
    - DIR is PM8150L GPIO11: 0 = up, 1 = down.
    - M1 is PM8150L GPIO8 = 1.
    - M0 is PM8150B GPIO5, high-impedance.
    - nSLEEP is PM8150 GPIO10.
    - Boost enable is PM8150B GPIO12, set once and left on.
  - Hall sensors: on QUP SE1 at 0x0c (top) and 0x0d (bottom), vdd L7C,
    vio L8C, ID 0x9c @0x09; register 0x06 = 0x37 disables their I2C.
  - The stock move (OnePlus's GPL driver, `drivers/misc/oplus_motor/`,
    `oneplus_motor.c` and `oneplus_drv8834.c`):
    - about 100 ms of slow steps (stock asks for a 104 167 ns period), then
      fast steps (asks for 12 000 ns);
    - stopped by a timer after about 618 ms up, 626 ms down;
    - the hall sensors are read afterwards, to decide whether the move
      worked;
    - a sensor reading above 150 (absolute) means "there".
  - Stock's PWM driver rounds each period to the nearest value the LPG can
    make (about 13.3 µs). Mainline's `leds-qcom-lpg` rounds down instead,
    so we ask for the exactly reachable 13 125 ns and 105 000 ns.

## 1. What is reused, what is new

| Piece | State |
| --- | --- |
| `camcc-sm8150`, `i2c-qcom-cci`, `leds-qcom-flash`, `leds-qcom-lpg`, `s5k3m5` | mainline |
| SM8150 CAMSS: CCI binding, CAMSS binding, driver, dtsi nodes (Andrew Gigena, v1, 2026-11-04, [lore](https://lore.kernel.org/all/20261104-sm8150-v7-4-rc1-camss-v1-0-7a9534a9a22f@andrewgigena.dev/)) | posted upstream, not merged; applied as is (`e2c10d7fc`..`03e8c6abf`), tested by its author on a Pixel 4 |
| `media: qcom: camss: Skip the endpoints of disabled sensors` | **new**: a sensor whose node is disabled kept the notifier from completing, so no camera came up; lets the plan enable one sensor at a time |
| `media: i2c: imx471: Bind through devicetree` + binding | **new**: an OF match and the `vdig`/`vif` supplies (mainline binds it through ACPI only) |
| `media: i2c: Add a Sony IMX481/IMX586 driver with firmware tables` (`sony-fwtable`) + binding | **new**: shares no vendor data; loads the owner's tables (§5.2) and refuses tables that write mode select or the OTP registers |
| C-PHY in CAMSS (`omamobile-hotdog-cphy`, 12 commits on top) | David Heidelberg's series "media: camss: Add support for C-PHY configuration on Qualcomm platforms" v9 (2026-06-17, [lore](https://lore.kernel.org/r/20260617-qcom-cphy-v9-0-83da8a8e4e44@ixit.cz), not merged), plus three of ours: the SM8150 C-PHY init sequence (`csiphy_3ph_v1_1_reg[]` and CTRL7 = 0x72 from Google's GPL Pixel 4 kernel, `cam_csiphy_1_1_hwreg.h`, all 129 entries checked), a fix to v9's C-PHY link-frequency fallback (about 5.2x too high; for upstream), and a settle-count comment. For the main camera only |
| DT: flash LED, cameras, pop-up pins | **new**, all disabled; the overlays enable them |
| `tools/camx-sensormodule-decode`, `tools/hotdog-camera-tables` | **new**: read the owner's image on the laptop |
| `omamobile-hotdog-popup` + `omamobile-hotdog-popup.service` | **new**, device-hotdog 0.1.5; the service isn't enabled by the package |
| libcamera `0057`: IMX586, IMX481, IMX471, S5K3M5 helpers and tuning stubs | **new**, 0.7.2-4.23; the simple pipeline already knows `qcom-camss` |

**Why tables from firmware.** No register settings for the IMX586 or IMX481
are published under a licence a kernel driver can carry. The ones that exist
in other GPL kernels came from SoC vendors' trees, which are not sources this
project cites. The owner's own image has them; the cheetah ultrawide
(`tools/extract-camera-data`) set the pattern.

## 2. Unknowns (each is checked read-only, or in its own step)

- **U1, CAMSS streaming on SM8150.** The upstream series streamed on a
  Pixel 4. The earlier Pixel 4 port needed three more changes before its
  VFE wrote anything: CAMNOC QoS writes, a 31-bit DMA mask and a 150 MHz
  `camnoc_axi` floor. Symptom: CSID counts frames but no buffer completes.
  Fix path: the QoS writes through a proper `reg` entry, not that port's
  hard-coded `ioremap`.
- **U2, the load switches' output.** The vana/vana2/vdig2 switches are
  modelled as fixed regulators on BoB. If a sensor's ID read fails with
  everything else right, the switch polarity or its rail (U2a: PM8150L
  gpio1 "PVDD") is the first suspect.
- **U3, the S5K3M5 at 24 MHz.** Stock runs it at 19.2 MHz; mainline's tables
  want 24 MHz, which MCLK0 makes exactly. The datasheet range covers both.
  If C4 shows no frames, a 19.2 MHz table set from the owner's image (as for
  the Sony sensors) is the fallback.
- **U4, the front camera's resolution.** The mainline IMX471 driver has one
  mode, 1928x1088 (a crop). Full resolution needs the vendor's 4656x3496
  table, the same way as the other Sony sensors, later.
- **U5, rotation.** The device tree's `rotation` is the vendor's
  `sensor-position-roll` (90, or 270 on the ultrawide). C5 checks one
  picture per camera and fixes the values.
- **U6, C-PHY.** New code on a separate branch. If C7 fails, the main
  camera stays off and the other three keep working.
  - **Settle count.** It comes from the spec: 85 ns + 6 UI, which is 21 at
    4000x3000@30 on the 300 MHz timer. The vendor file's settle hint of
    "14" has unknown units, so this is the first thing to change if C7
    shows no frames or SOT errors.
  - **Rate cap.** The 300 MHz CSIPHY timer and CAMSS's clock check limit a
    trio to about 2.28 Gsym/s. That is why the 8000x6000 mode (1.17 GHz
    link frequency) isn't in the device tree.
  - **Not implemented:** the vendor's extra settings above 5.24 Gbit/s per
    trio, and line-order (A/B/C) swaps.
- **U7, the pop-up's calibration.**
  - Stock's motor service writes per-phone hall thresholds and step counts
    from a source we don't have; P2 measures this phone's values.
  - No stall detection and no free-fall protection: the free-fall interrupt
    (TLMM gpio163) has no known source on Linux.
  - The boost enable's purpose is inferred from its name.
- **U8, LPG side effects.** Enabling the PM8150L LPG turns off its tri-colour
  LED block, which this phone doesn't use.

## 3. Rules for this subsystem

- Nothing here touches radio, PMIC registers, RPMB, any partition or a
  slot. The phone writes are: a test kernel's module tree; bring-up files in
  `/etc/modprobe.d`; the owner's table files in
  `/usr/lib/firmware/omamobile/camera/`; and (later) the device and
  libcamera packages.
- Test kernels are **RAM-booted** (`fastboot boot`); `boot_a` stays as it
  is. Every return to `boot_a` spends a slot-A try while
  `slot-successful:a` is `no` ([BRINGUP-M1](BRINGUP-M1.md)): read the count
  first and keep boots few.
- One change per step: every new module is blacklisted for the test boot and
  loaded by hand under a log stream (`dmesg -w` to the laptop first).
- **Announce before T2** (the torch lights), **before P3 and every
  pop-up step** (the camera moves; the phone lies flat, nothing over the
  slot, no finger on it), and before any step that powers a sensor (no
  visible effect, but the phone warms).
- The torch is never left on: every torch step switches it off again within
  30 s.
- The pop-up is never forced by hand while the motor runs, and never moved
  while the hall readings are unknown, except `down`.
- Never write a hall sensor register except its reset and setup (0x00,
  0x01, 0x07, 0x08); the tool refuses others. 0x06 disables its I2C.
- The table files are the owner's vendor data: never commit, upload or copy
  them off this owner's machines.

## 4. Decisions for the owner

1. Run the plan at all, and when: each step needs a yes.
2. The upstream SM8150 CAMSS series is one day old: use it as is (this plan),
   or wait for v2.
3. The torch cap: stock's 300 mA per LED (this plan) or lower.
4. After P5: enable `omamobile-hotdog-popup.service` and create
   `/etc/omamobile/popup-hotdog-enable`.
5. Making it stay: flash a RAM-booted image to `boot_a` (BRINGUP-M1's
   rule), or enable the nodes in the kernel DT and drop the overlays.

## 5. Build

### 5.1 Kernel and images

```sh
# the fingerprint and camera options on top (temporary: do not commit)
cat device/hotdog/kernel-fingerprint.config device/hotdog/kernel-camera.config \
  >> device/hotdog/kernel.config
DEVICE=hotdog KERNEL_DIR=~/omamobile-kernel/wt-hotdog-camera \
  KERNEL_OUT=~/omamobile-kernel/out-hotdog-camera bin/omamobile kernel
git checkout device/hotdog/kernel.config
DEVICE=hotdog KERNEL_OUT=~/omamobile-kernel/out-hotdog-camera bin/omamobile modules
DEVICE=hotdog KERNEL_OUT=~/omamobile-kernel/out-hotdog-camera bin/omamobile initramfs
# DTB_OVERLAYS="torch camera popup" in device/hotdog/device.conf for this build only
DEVICE=hotdog KERNEL_OUT=~/omamobile-kernel/out-hotdog-camera bin/omamobile images
```

Without the overlays this kernel boots like `omamobile-hotdog-fingerprint`:
every new node is disabled. With them, at boot:

- The fixed regulators drive their enable pins low, so the sensors stay off.
- QUP SE1 probes.
- L7C and L8C come on (the hall sensors' supplies).

The blacklisted modules hold back everything else.

For C7 the same build from `wt-hotdog-cphy` into `out-hotdog-cphy`, with
`DTB_OVERLAYS="torch camera popup camera-main"`.

### 5.2 The owner's register tables (laptop)

```sh
tools/hotdog-camera-tables ~/android/reference/hotdog/vendor-fp/vendor/lib64/camera \
  ~/android/reference/hotdog/camera-tables
```

- **Expect:** `imx586-main.bin` (3 trios, C-PHY; modes 4000x3000, 2000x1500,
  8000x6000) and `imx481-wide.bin` (4 lanes; 4656x3496).
- **Check:** the printed link frequencies are the ones in the device tree
  (421203125 and 340003125; 659200000).
- **Never:** commit or upload the output.

## 6. Runbook

Each step is the owner's to run or approve. Read-only first. Each has
Expect/Pass, a **Stop** condition, a Rollback and a risk level. Results go in
§7 with the date and `uname -r`.

### C0: preconditions (read-only; risk none)

- The phone boots Omarchy Mobile from `boot_a` with USB SSH.
- In fastboot: `fastboot getvar slot-successful:a`,
  `fastboot getvar slot-retry-count:a`. **Stop** if the retry count is 2
  or lower (mark slot A first, the owner's open decision).

```sh
tools/phone-ssh 'lsmod | grep -E "camcc|cci|camss|lpg|flash"; ls /sys/class/leds /sys/class/pwm'
tools/phone-ssh 'grep -E "gpio(11|12|23|28|29|30|148) " /sys/kernel/debug/gpio'
tools/phone-ssh 'cat /sys/kernel/debug/gpio | grep -A12 -E "pmic@(0|2|4)"'
tools/phone-ssh 'grep -iE "l1f|l2f|l3f|l4f|l1c|l7c|l8c|bob" /sys/kernel/debug/regulator/regulator_summary'
```

- **Expect:**
  - `camcc_sm8150` loaded or absent, nothing camera-related bound;
  - none of these GPIOs claimed;
  - the PMIC GPIOs listed;
  - the PM8009 LDOs off.
- **Stop** if another driver owns one of the camera or motor pins.

### C1: the test kernel's modules, blacklist and tables (one write each; risk low)

```sh
DEVICE=hotdog KERNEL_OUT=~/omamobile-kernel/out-hotdog-camera bin/omamobile modules-push
tools/phone-ssh 'printf "%s\n" "# CAMERA-PLAN: each step loads one by hand" \
  "blacklist leds_qcom_flash" "blacklist leds_qcom_lpg" "blacklist i2c_qcom_cci" \
  "blacklist qcom_camss" "blacklist s5k3m5" "blacklist imx471" "blacklist sony_fwtable" \
  > /etc/modprobe.d/omamobile-camera-hotdog-bringup.conf'
tools/phone-ssh 'mkdir -p /usr/lib/firmware/omamobile/camera'
for f in imx586-main.bin imx481-wide.bin; do
  tools/phone-ssh "cat > /usr/lib/firmware/omamobile/camera/$f" < ~/android/reference/hotdog/camera-tables/$f
done
```

- **Rollback:** remove the blacklist file and the two table files; the extra
  module tree is harmless.

### T1-T2: the torch (RAM boot 1; risk low)

The owner brings the phone to fastboot by the buttons, then
`fastboot boot ~/omamobile-kernel/out-hotdog-camera/images/boot.img`. Fingerprint
unlock is off in this boot (its bring-up module is built for the running
kernel); unlock with the PIN. A log stream first:
`tools/phone-ssh 'dmesg -w' > logs/camera-$(date +%H%M).log &`.

**T1** (no light):

```sh
tools/phone-ssh 'uname -r; modprobe leds-qcom-flash; ls /sys/class/leds; cat /sys/class/leds/white:torch/max_brightness'
```

- **Expect:** `white:torch` with `max_brightness` 255; no error.

**T2** (announce: the rear flash lights, dim, for 2 s, then full for 5 s):

```sh
tools/phone-ssh 'cd /sys/class/leds/white:torch; echo 40 > brightness; sleep 2; echo 0 > brightness'
tools/phone-ssh 'cd /sys/class/leds/white:torch; echo 255 > brightness; sleep 5; echo 0 > brightness; cat brightness'
```

- **Pass:** the owner sees both LEDs light, dim then bright; `brightness` reads
  0; no `led-fault` in the log. Then the quick-settings Torch tile turns it on
  and off (its `brightnessctl --device=white:torch` path).
- **Stop** on a fault interrupt, one LED dark, or anything but 0 after off.
- **Rollback:** `echo 0 > brightness`; `rmmod leds_qcom_flash`.

### C2-C6: the D-PHY cameras (same boot; risk low to medium)

**C2, the CCI controllers:**

```sh
tools/phone-ssh 'modprobe i2c-qcom-cci; sleep 1; dmesg | grep -iE "cci|camcc|gdsc" | tail; ls /sys/bus/i2c/devices/ | grep -E "^i2c-"'
```

- **Expect:** four new I2C adapters; no clock or GDSC error.
- **Never** run `i2cdetect` on them.

**C3, the telephoto** (powers the S5K3M5 and reads its ID):

```sh
tools/phone-ssh 'modprobe s5k3m5; sleep 1; dmesg | grep -iE "s5k3m5|regulator|cci" | tail'
```

- **Pass:** probe without error.
- **Stop:** a chip ID mismatch, an I2C NACK, or a regulator error (U2).

**C4, the front and the ultrawide:**

```sh
tools/phone-ssh 'modprobe imx471; sleep 1; modprobe sony-fwtable; sleep 1; dmesg | grep -iE "imx471|imx481|sony" | tail'
```

- **Expect:** IMX471 probes; `IMX481, 1 modes from the tables`.
- **Stop:** any ID mismatch, or `refusing ...`.

**C5, CAMSS** (no streaming yet):

```sh
tools/phone-ssh 'modprobe qcom-camss; sleep 2; dmesg | grep -iE "camss|smmu|icc" | tail -20; media-ctl -d /dev/media0 -p | grep -E "entity|-> "'
```

- **Expect:** `msm_csiphy0..3`, CSIDs and VFEs; the three sensors linked to
  CSIPHY0, 2 and 3; no SMMU fault.
- **Stop** on an SMMU fault or a CAMSS probe error.

**C6, raw frames, one camera at a time** (telephoto first; the front sensor
streams dark frames with the pop-up down, which is fine):

```sh
tools/phone-ssh 'media-ctl -d /dev/media0 -r; \
  media-ctl -d /dev/media0 -l "\"msm_csiphy0\":1->\"msm_csid0\":0[1],\"msm_csid0\":1->\"msm_vfe0_rdi0\":0[1]"; \
  media-ctl -d /dev/media0 -V "\"s5k3m5 0-0010\":0[fmt:SGRBG10_1X10/4208x3120]"; \
  media-ctl -d /dev/media0 -V "\"msm_csiphy0\":0[fmt:SGRBG10_1X10/4208x3120],\"msm_csid0\":0[fmt:SGRBG10_1X10/4208x3120],\"msm_vfe0_rdi0\":0[fmt:SGRBG10_1X10/4208x3120]"; \
  timeout 20 v4l2-ctl -d /dev/video0 --set-fmt-video=width=4208,height=3120,pixelformat=pgAA \
    --stream-mmap --stream-count=30 --stream-to=/tmp/tele.raw'
```

- The entity names (the sensor's `<bus>-<addr>`), the VFE's video node and
  the packed-format fourcc come from C5's `media-ctl -p`; adjust before
  running.
- **Pass:** 30 frames, the expected size; `tools/raw10-stats` shows a
  plausible image (cover the lens: dark; uncover: brighter).
- **Stop:** a timeout with no frame (U1), an SMMU fault, `csid ... error`
  floods.
- **Rollback:** `pkill v4l2-ctl`; reboot rather than `rmmod`.
- Then the ultrawide on CSIPHY3 and the front on CSIPHY2 the same way.

### C7: the main camera (RAM boot 2, the C-PHY kernel; risk medium)

As C1 with `out-hotdog-cphy` and `camera-main` added. Then as C2-C6 for
`imx586` on CSIPHY1 (`sony-fwtable` probes it with the 4000x3000 and
2000x1500 modes).

- **Stop** on an ID mismatch, a CSIPHY error, or CSID errors (the C-PHY
  setup is the first suspect, U6).

### C8: libcamera and omacam (risk low)

```sh
tools/phone-install-package packages/libcamera
tools/phone-ssh 'cam -l'
tools/phone-ssh 'cam -c 1 -C 10 -F /tmp/cam1-#.ppm -s pixelformat=RGB888,width=1920,height=1440'
```

- **Expect:** four cameras (three before C7), each with its sensor model;
  pictures are the right way up (U5: else fix `rotation` in the DT).
- Then omacam.

### P0: pop-up preconditions (read-only, same boot as C2-C6; risk none)

```sh
tools/phone-ssh 'ls /sys/class/pwm; ls /sys/bus/i2c/devices | grep -E "^i2c-"; cat /sys/kernel/debug/gpio | grep -B2 -A14 "pmic@4"'
```

- **Expect:**
  - no PM8150L PWM yet (LPG blacklisted);
  - an adapter for `i2c@884000`;
  - PM8150L GPIO8, 10 and 11, PM8150 GPIO10 and PM8150B GPIO5 and 12
    unclaimed.

### P1: hall sensors and pins (risk low; no movement)

```sh
tools/phone-ssh 'modprobe leds-qcom-lpg; ls /sys/class/pwm; cat /sys/kernel/debug/pinctrl/*pmic@4*/pinconf-pins 2>/dev/null | grep -E "gpio(8|10|11)"'
scp packages/omamobile-device-hotdog/libexec/omamobile-hotdog-popup root@172.16.42.1:/root/
tools/phone-ssh 'python3 -I /root/omamobile-hotdog-popup status'
```

- **Expect:**
  - a `pwmchip` for `pmic@5/pwm`;
  - PM8150L GPIO10 in `func1`, GPIO11 and 8 low;
  - `status` prints `down up=<small> down=<large>` (both sensors answer
    ID 0x9c).
- **Stop:**
  - a hall sensor doesn't answer, or its ID is wrong;
  - the reading isn't `down` with the camera visibly down: don't move
    anything; record the values and work out the thresholds first.

### P2: the hall values at both ends (risk none; the owner moves nothing)

Record `status` three times with the camera down. Its values at the top come
from P3. Write the measured thresholds (about half of each end's value) to
`/etc/omamobile/popup-hotdog.conf` if they differ from 150.

### P3: the first move up (announce; risk medium: mechanical)

The phone lies flat, the slot is free, the owner watches it:

```sh
tools/phone-ssh 'python3 -I /root/omamobile-hotdog-popup up; python3 -I /root/omamobile-hotdog-popup status'
```

- **Expect:**
  - one smooth move of about 0.6 s;
  - the log says `sensor reached`, then `now up`;
  - the owner sees the camera fully up.
- **Stop:** `NOT reached`, a buzzing or grinding motor, or the camera
  stopping halfway. Then run `down` once (allowed from an unknown
  position) and stop the plan there.
- **Rollback:** `python3 -I /root/omamobile-hotdog-popup down`.

### P4: down, then five cycles (announce; risk medium)

```sh
tools/phone-ssh 'P=/root/omamobile-hotdog-popup; python3 -I $P down; for i in 1 2 3 4 5; do python3 -I $P up; sleep 2; python3 -I $P down; sleep 2; done'
```

- **Pass:** all moves end `reached`; times are steady; nothing grinds.
- Record the hall values at the top and bottom, and the time to "reached"
  in each direction.

### P5: the front camera follows the pop-up (announce; risk low)

Install device-hotdog 0.1.5, then
`touch /etc/omamobile/popup-hotdog-enable; systemctl start omamobile-hotdog-popup`.

- **Expect:**
  - streaming the front camera (C6's commands for CSIPHY2) raises it within
    about 0.8 s;
  - stopping lowers it 1.5 s later;
  - pushing it in while up lowers it and logs `left the top while in use`;
  - `systemctl stop omamobile-hotdog-popup` with it up lowers it.
- **Rollback:** `systemctl stop omamobile-hotdog-popup` (lowers it);
  remove the enable file.

### After the plan

Remove `/etc/modprobe.d/omamobile-camera-hotdog-bringup.conf` and
`/root/omamobile-hotdog-popup`, and keep the table files. Then the owner's
decision 5.

## 7. Results

**2026-11-05, RAM boot 1 (`7.3.0-rc6-omamobile-push1-g43b7e8ece3ad`,
overlays torch, camera and popup): T1, C0-C6 pass; the D-PHY cameras give
images.**

- **C0:** only `camcc_sm8150` loaded, nothing bound; none of the camera or
  motor pins claimed; battery 53 %. `slot-retry-count:a` 5 before and after
  both RAM boots: `fastboot boot` spends no slot-A try.
- **C1:** the module tree, the blacklist and both tables (sha256 read back).
- **First RAM boot hung:** the initramfs answered SSH after 44 s, switched
  root, and Arch never opened port 22 (ping answered, the panel black, more
  than 12 minutes). It left no journal at all (no entry in `--list-boots`,
  no pstore), so it stopped before the journal flush. The same image with
  `systemd.debug_shell=ttyGS0` added booted cleanly (SSH 10 s), so the hang
  is intermittent, the same symptom as BRINGUP-M1's 2026-11-04 boot of the
  fingerprint kernel. Test images now carry the debug shell (a root shell on
  the laptop's `/dev/ttyACM0`) so the next one can be read.
- **T1:** `white:torch`, `max_brightness` 255. **T2:** dim 2 s, full 5 s,
  `brightness` 0 afterwards, no fault in the log; the owner's sighting is
  not recorded yet.
- **C2:** four `Qualcomm-CCI` adapters (i2c-4 to i2c-7), no clock or GDSC
  error.
- **C3:** `s5k3m5 4-0010` probes (`afvdd` dummy: no actuator supply in the
  DT yet).
- **C4:** `imx471 6-0010` probes; `sony-fwtable 7-001a: IMX481, 1 modes
  from the tables`.
- **C5:** CAMSS probes; the sensors link to CSIPHY0 (tele), 2 (front) and 3
  (wide); four CSIDs, VFEs with RDI0-2 and PIX. The only SMMU faults in the
  log are at 1.1 s of boot, before CAMSS loaded (SIDs 0x800, 0xc20).
- **C6, through CSID0 and VFE0 RDI0:**
  - telephoto 4208x3120 `pgAA` at 30.00 fps, no CSID error; its colour bars
    (`test_pattern=2`) arrive whole, Bayer order GRBG as expected. With the
    phone on its back it read only the pedestal (64) even at exposure 3300
    and gain 16, which first looked like a dead analog rail; streaming, the
    rails read on (GPIO 148 high, `cam_tele_vana`, L2F, L1C) and reset
    released (GPIO 28 high). Pointed at the room: light (mean 77-118 per
    phase at exposure 1600, gain 4), a wall out of focus (no actuator);
  - ultrawide 4656x3496 `pRAA` at 30.1 fps: a recognisable picture of the
    room (exposure 3000, `analogue_gain` 480), upside down and green as raw
    frames are;
  - front 1928x1088 `pRAA` at 57.8 fps, no error; the pedestal only (the
    pop-up is down). Its test pattern does nothing: the upstream `imx471`
    driver writes the pattern code as `CCI_REG8(0x0600)`, the high byte of
    the 16-bit SMIA register 0x0600-0x0601, so the mode byte stays 0.
- **C8, libcamera 0.7.2-4.23** (built and installed on the phone with
  `tools/phone-install-package`, which also installed `libcamera-tools`):
  `cam -l` lists the three D-PHY cameras (two back, one front). The
  sensor helpers warn that `imx471` and `s5k3m5` give no crop rectangles
  (harmless). Two fixes before a user session gets a picture:
  - **The GPU debayer gives all-zero frames** on the Adreno 640 (FD640,
    Mesa 26.2.6), also with `copy_input_buffer: true`; AGC then runs to
    gain 16 and 33 ms. No GPU fault, but closing the imported buffers logs
    `io-pgtable-arm.c:673` unmap warnings from `msm_gem_close` (36-37 per
    capture). The CPU debayer is correct (white-balanced, exposed) at
    30 fps for 1920x1440 from the ultrawide, as on the Pixel 4 (the same
    SoC and GPU). device-hotdog 0.1.6 ships `software_isp.mode: cpu` as
    `/usr/share/libcamera/configuration.yaml`.
  - **As the user, no software ISP at all** ("Could not open any dma-buf
    provider"): the DMA-BUF heaps are root-only. device-hotdog 0.1.6 ships
    cheetah's and tegu's `70-omamobile-dma-heap.rules`.
  - On the phone, until 0.1.6 is installed: `/etc/libcamera/configuration.yaml`
    and `/etc/udev/rules.d/70-omamobile-camera-hotdog-bringup.rules`
    (bring-up copies; remove both when the package is installed).
  - `omacam --list` as the user: `main` = IMX481 (the ultrawide, until the
    IMX586 works), `front` = IMX471, the S5K3M5 unused.
  - The owner saw the pictures in omacam: upside down, blurry and flat.
    Causes: the ultrawide's DT rotation (270, should be 90: stock's roll
    270/yaw 0 is the others' roll 90/yaw 180), no focus drivers, the
    identity CCM, and the CPU debayer only crops (a 1920x1440 viewfinder is
    a centre crop of the full sensor frame; it needs binned modes).
- **Colour tuning (laptop, private):** stock's CCMs, AWB points and
  shading tables decoded from the owner's
  `com.qti.tuned.*.bin` into `~/android/reference/hotdog/tuning/` (never
  committed: derived from Qualcomm's data). On the phone in `/tmp/hdtune`
  only (lost at reboot); A/B on the ultrawide loaded (`Using tuning file
  /tmp/hdtune/simple/imx481.yaml`) and is more neutral; the owner's verdict
  is open. Keep: `install -Dm644 -t /etc/libcamera/ipa/simple/`.
- **P0-P2 pass:** i2c@884000 is i2c-0; the LPG is `pwmchip0` (5 channels);
  both hall sensors answer, `down up=-11 down=-325` three times (thresholds
  150). The pop-up tool looked for `/sys/class/i2c-adapter`, which 7.3 no
  longer has: fixed (device-hotdog 0.1.6). P3 (first move) not run yet.

**2026-11-05 evening, the combined test kernel (`7.3.0-rc6-omamobile-push1-gc65cd2d1979f`,
branch `omamobile-hotdog-af` = `omamobile-hotdog-cphy` + focus + two fixes,
`out-hotdog-af`; overlays torch, camera, popup, camera-main, camera-af):
built, modules pushed, never reached Arch.**

- Focus (laptop): main and tele are one dual module; SEMCO uses an
  LC898217XC at 0x72 (main) and 0x74 (tele), O-film an AK7374 at 0x2d and
  0x74; the ultrawide an AK7374 at 0x0c. 10-bit position; stock travels
  codes 50-930. The DT assumes SEMCO (the first test settles it). Commits:
  AK7374 in `ak7375`, a new `lc898217xc` driver, `v4l2-fwnode` skipping
  disabled lens references, the DT, the ultrawide rotation 90, and the
  IMX471 test pattern as a 16-bit write. `slot-retry-count:a` read 4 at
  this boot (5 earlier: one `boot_a` boot happened in between).
- **Two RAM boots in a row hung**: black panel, ping answers, SSH refused,
  the serial debug shell silent; the second one reached the initramfs SSH
  only after 149 s (normally 5-44 s), then froze after `switch_root`.
  Hypothesis: the panel stalls after a RAM boot from the fastboot screen
  (initramfs/init's note: "a stalled panel flooded the console"), and
  console writes to it (`console=tty0`, the init's `say` to `/dev/tty0`)
  block, so systemd freezes at its first console write. A third image with
  `console=null` (same kernel and overlays, `out-hotdog-af/images/boot.img`,
  sha256 `ccb971ab…`; the tty0 one kept as `boot-tty0.img`) is built and
  untested.
- **Next:** RAM-boot the `console=null` image; C7 (IMX586, C-PHY); the
  focus test (which module maker, then `focus_absolute` 50-930 with the
  subdev held open); libcamera AF; the owner's tuning verdict; binned
  modes for the viewfinder; P3-P5 (the pop-up, announce each move).

**2026-11-12, the `console=null` image (`gc65cd2d1979f`, RAM boot): boots,
system `running` at 4 min. C7 and the focus test pass.**

- This boot, with the same kernel and overlays, came up clean. (Not proof
  that the console caused the hangs: see the `geaa88b840c8e` boot below.)
- **C7:** `sony-fwtable 5-001a: IMX586, 2 modes from the tables` (8000x6000
  skipped: its link frequency isn't in the DT); `cam -c 2` streams
  2000x1500 at 30 fps over CSIPHY1 C-PHY with no CSID errors, and the
  picture is clean (the owner's desk).
- **Focus:** both LC898217XC answer (0x72, 0x74): the module is **SEMCO**.
  Each logs `status still 0x20 after power-up` (stock polls 0xb3 for 0 for
  10 ms; the lens moves anyway: the bit's meaning is open). The AK7374 at
  0x0c answers silently. `focus_absolute` 0/300/600/930 on the main lens
  visibly moves the focus. libcamera lists AF controls for all three back
  cameras.
- **Orientation:** `cam` frames are never rotated; with the phone on its
  left edge they come out upside down, which is what libcamera's
  counter-clockwise `rotation = <90>` predicts. omacam turns all four
  cameras 270 clockwise and shows the scene upright: the DT is right, no
  change. All three back cameras read out the same way up.
- **omacam** had no hotdog lens table and took the IMX481 as main. A table
  (main IMX586 1x 1992x1500/3992x3000, ultrawide 0.5x 4648x3496, tele 3x
  2096x1184/4200x3120, front) is in the owner's
  `~/.config/omacam/lenses.toml` for now; it belongs in omacam.
- **Tuning on the phone:** the stock-derived files plus `Af` (coarse 8,
  fine 32 main / 16 wide and tele) in `/etc/libcamera/ipa/simple/` (private,
  never committed). AF moved the main lens to 814 and the wide to 404 in a
  scripted omacam run. The owner: "camera works and looks good", but very
  noisy, about 10 fps preview, slow focus: all three are the CPU debayer
  (no denoise or sharpening, slow, and AF steps once per frame).
- **s5k3m5 crop (upstream bug):** `get_selection()` gave the output size,
  height = width (4208x4208), so libcamera put the tele's AF window off
  centre. Fixed: the per-mode analogue crop from the mode registers, plus
  CROP_DEFAULT and NATIVE_SIZE (`eaa88b840`, W=1 clean as a module).
- **C9, the GPU debayer's zero frames: `CONFIG_DMABUF_DEBUG=y`.** A
  standalone EGL test (render magenta into a dmabuf, read it back) works on
  a GBM buffer and fails on every *imported* one (dma-heap `system`,
  `reserved`, `default_cma_region`): the CPU's prefill survives, the GPU's
  own `glReadPixels` reads 0, and each close warns 35 times in
  `__arm_lpae_unmap` (nothing was mapped). DMABUF_DEBUG (default y under
  DEBUG_KERNEL) scrambles the page links of an importer's sg table, and msm
  maps an import's pages from it (upstream "drm/msm: DMABUF_DEBUG fixes",
  not merged). Off in `kernel-camera.config`. The GPU path ran 13-20 fps
  even writing nothing. Built: `7.3.0-rc6-omamobile-push1-geaa88b840c8e`
  (sha256 `b0d3feb3…`), modules pushed.
- **Its first RAM boot (17:55, from button fastboot, `console=null`) was a
  bad boot, like the two of 11-05:** the panel showed noise (DPU `frame done
  timeout`, `ctl 1 reset failure`, `vblank wait timed out` every ~1.5 s),
  everything ran late from the start (ufshcd re-probed at 22 s, `scsi host0`
  at 38 s, the partitions at 76 s, the storage guard at 170 s), then
  `ufshcd-qcom: pwr ctrl cmd 0x17 ... completion timeout` (hibern8 enter) at
  122 s and every read after it failed at once (`hostbyte=0x07`, the UFS IRQ
  count frozen at 392): `EXT4-fs (sda22): unable to read superblock`, `arch:
  cannot mount /dev/sda22`. The initramfs SSH answered. Nothing was mounted,
  so nothing was written. So the 11-05 hangs were most likely this (UFS and
  DPU both failing on some RAM boots), not the console. Unknown: why some
  RAM boots go bad (shared RPMh/interconnect votes? the time spent in
  fastboot?).
- **Second RAM boot of `geaa88b840c8e` (18:22): clean** (Arch at 9 s, no
  DPU, UIC or I/O errors). The EGL test now writes into imported dma-heap
  buffers (`system` and `gbm` both magenta, no unmap warnings): C9 fixed.
  `LIBCAMERA_SOFTISP_MODE=gpu cam -c 2` gives real frames (mean 99) at the
  sensor's rate. `/etc/libcamera/configuration.yaml` on the phone set to
  `gpu`; device-hotdog's copy changed to `gpu` (it needs the kernel option
  off). The tuning files on the phone gained the Pixel's `Detail` block
  (sharpen 0.6, denoise 0.015, chroma 0.03) as a start. omacam: main
  preview **62 fps** (was about 10 on the CPU), AF sharp on text at 1x; at
  3x it keeps the main camera ("Low light: main camera"); the ultrawide is
  grainy at its indoor gain. The laptop needed a NetworkManager profile
  (`omamobile-phone`, 172.16.42.2/24) after a reboot: without it the
  address went at each USB re-enumeration.

**2026-11-13, the cameras made permanent: `boot_a` =
`7.3.0-rc6-omamobile-push1-g8da458f2d9a9`.**

- **The image:** `omamobile-hotdog-int` = `omamobile-hotdog-af` (with the
  s5k3m5 crop fix) plus the three mic commits. Built with
  `kernel-camera.config`, so `DMABUF_DEBUG` is off. Its overlays are
  `mic torch camera popup camera-main camera-af`. The cmdline is
  `clk_ignore_unused pd_ignore_unused panic=10 console=tty0`, with no debug
  shell. sha256 `91d92b34…`. The DTB was checked: the camera, lens,
  fingerprint, qseecom-compat, SLIMbus and slimcap nodes are all `okay`.
- **RAM boot (22:14, from button fastboot, `slot-retry-count:a` 2):
  clean.** There were no DPU, UIC or I/O errors and no `WARNING`. `cam -l`
  lists all four cameras, and the modules loaded at boot without the
  bring-up blacklist (device-hotdog 0.1.6). The main, ultrawide and
  telephoto cameras each delivered 30 frames. The fingerprint service and
  `fprintd` were active. The sound card and SLIMbus were up, and a 4 s
  `pw-record` gave live audio (RMS 27, peak 277, in a quiet room).
- **Flash (22:20):** before it, the old `boot_a` (the mic kernel
  `gb743280ab222`) was read back from `sde11` to the laptop and its sha256
  matched the partition; it is the rollback. Then `fastboot -s <serial>
  flash boot_a`. Slot A's tries went from 2 to 7 and `slot-successful:a`
  stayed `no`. `fastboot reboot` booted it: the release above, system
  `running`, four cameras, fingerprint and the sound card. Its first
  51 630 080 bytes of `sde11` match the image's sha256.

**C-PHY branch:** `omamobile-hotdog-cphy` rebased onto the final camera
branch and built (`7.3.0-rc6-omamobile-push1-g8ff34aa9e03b`):

- no new warnings;
- `W=1` on `drivers/media/platform/qcom/camss/` and `sony-fwtable.o` clean;
- `checkpatch --strict` clean on our three commits (they carry no
  Signed-off-by, which is the owner's to add);
- the upstream nine keep their author's tags and Links.

**2026-11-05, laptop only:** stock facts in §0 from the owner's OxygenOS
image (base DTB, dtbo entry 18, the camera module files); the kernel branch,
the overlays, the pop-up tool, the tables tool and the libcamera patch
written. Checks:

- **Kernel build.** Built as §5.1, with the fingerprint and camera options
  (`7.3.0-rc6-omamobile-push1-g43b7e8ece3ad`). No new warnings; the
  modules `qcom-camss`, `i2c-qcom-cci`, `s5k3m5`, `imx471`, `sony-fwtable`
  and `leds-qcom-flash` are built.
- **W=1** on `sony-fwtable.o`, `imx471.o` and `camss.o`: clean.
- **`checkpatch --strict`:** the eight commits on top of the upstream series
  are clean, except that the three adding files ask about MAINTAINERS.
- **`dt_binding_check`** (dtschema 2026.9) for `sony,imx471`, `sony,imx586`,
  `qcom,sm8150-camss` and `qcom,i2c-cci`: clean.
- **`dt-validate`:** the same 22 messages for the running kernel's DTB, this
  branch's, and this branch's with all four overlays applied; nothing new.
- **Overlays:** all four compile; `fdtoverlay` applies them to the built
  DTB, and every target goes from `disabled` to `okay` (L7C and L8C become
  always-on).
- **Tables:** `tools/hotdog-camera-tables` on the owner's image gives
  `imx586-main.bin` (16 296 bytes) and `imx481-wide.bin` (2 952 bytes), kept
  in the scratchpad only. A Python mirror of the driver's parser accepts
  both: no write to 0x0100 or the OTP range, delays at most 100 ms, sizes
  exact.
- **Pop-up tool:** simulated against a mocked motor and hall sensors. It
  stops at the target's threshold plus 10 ms, refuses `up` toward an end the
  camera is at or from an unknown position, and allows `down` from one.
  device-hotdog's `test/all` passes.
- **libcamera:** the 0057 patch applies on top of 0001-0056 (it was
  generated there); libcamera itself was not built.
